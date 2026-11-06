package org.nebulavpn.nebula_mobile

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.util.Log
import dev.amirzr.flutter_v2ray_client.v2ray.core.V2rayCoreManager
import java.io.BufferedInputStream
import java.io.InputStream

/**
 * The DNS tunnel's native helpers (plan 10): resolver tests with progress
 * and Stop, which network the phone is on, and which addresses are in Iran.
 */
object DnsTunnelNative {
    private class Scan(val process: Process, val total: Int) {
        @Volatile var tested = 0
        val valid = java.util.Collections.synchronizedList(mutableListOf<String>())
        val seen = java.util.Collections.synchronizedList(mutableListOf<String>())
        @Volatile var done = false
        @Volatile var error: String? = null
    }

    @Volatile private var scan: Scan? = null

    /**
     * Starts the engine's -scan-only run (one at a time; a new one stops the
     * old). It stops by itself once [stopAfter] resolvers carry the tunnel.
     * The app is outside its own VPN, so it tests the real network.
     */
    fun start(context: Context, config: String, resolvers: String, stopAfter: Int) {
        stop()
        val total = resolvers.lineSequence().count { it.isNotBlank() }
        val process = V2rayCoreManager.startCottenDns(context, config, resolvers, true)
            ?: throw IllegalStateException("engine missing")
        val current = Scan(process, total)
        scan = current
        Thread({
            try {
                process.inputStream.bufferedReader().forEachLine { line ->
                    Log.i("CottenDNS-Scan", line)
                    val valid = after(line, "WD_SCAN event=valid resolver=")
                    val rejected = after(line, "WD_SCAN event=rejected resolver=")
                    if (valid != null) {
                        current.valid += valid
                        current.seen += valid
                        current.tested++
                        if (current.valid.size >= stopAfter) process.destroy()
                    } else if (rejected != null) {
                        current.seen += rejected
                        current.tested++
                    }
                }
            } catch (_: java.io.IOException) {
                // Stopped: what was found is kept.
            } catch (e: Exception) {
                current.error = e.message ?: "scan failed"
            }
            current.done = true
        }, "CottenDNS_Scan").start()
    }

    private fun after(line: String, marker: String): String? {
        val at = line.indexOf(marker)
        return if (at < 0) null else line.substring(at + marker.length).trim().split(" ")[0]
    }

    fun progress(): Map<String, Any?> {
        val current = scan ?: return mapOf("done" to true, "tested" to 0, "total" to 0)
        return mapOf(
            "tested" to current.tested,
            "total" to current.total,
            "valid" to synchronized(current.valid) { current.valid.toList() },
            "seen" to synchronized(current.seen) { current.seen.toList() },
            "done" to current.done,
            "error" to current.error,
        )
    }

    fun stop() {
        scan?.process?.destroy()
    }

    /**
     * "wifi", "mobile-<MCC><MNC>" for the carrier carrying mobile data, or
     * "other". No permission: Wi-Fi names need location, so Wi-Fi is one.
     */
    fun networkKey(context: Context): String {
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: return "other"
        @Suppress("DEPRECATION")
        val capabilities = manager.allNetworks.mapNotNull { manager.getNetworkCapabilities(it) }
            .filter {
                it.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    !it.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
            }
        if (capabilities.any { it.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) }) return "wifi"
        if (capabilities.any { it.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) }) {
            val telephony = context.getSystemService(TelephonyManager::class.java)
                ?.createForSubscriptionId(SubscriptionManager.getDefaultDataSubscriptionId())
            val operator = telephony?.networkOperator.orEmpty()
            return if (operator.isEmpty()) "mobile" else "mobile-$operator"
        }
        return "other"
    }

    /** The resolvers the running DNS tunnel uses now (the engine reports them). */
    fun active(context: Context): List<String> =
        try {
            java.io.File(java.io.File(context.filesDir, "cottendns"), "active.txt")
                .readText().split(',').map { it.trim() }.filter { it.isNotEmpty() }
        } catch (_: Exception) {
            emptyList()
        }

    /** The phone's Wi-Fi is up (the full scan runs only there). */
    fun onWifi(context: Context): Boolean = networkKey(context) == "wifi"

    // Iran's IPv4 ranges from Xray's own geoip.dat, read once: (start, end).
    @Volatile private var iran: List<LongArray>? = null

    /** For each address ("1.2.3.4" or "1.2.3.4:53"), whether it is in Iran. */
    fun inIran(context: Context, addresses: List<String>): List<Boolean> {
        val ranges = iran ?: loadIran(context).also { iran = it }
        return addresses.map { address ->
            val ip = ipv4(address.substringBeforeLast(':').takeIf { address.count { c -> c == ':' } == 1 } ?: address)
            ip != null && ranges.any { ip >= it[0] && ip <= it[1] }
        }
    }

    private fun ipv4(text: String): Long? {
        val parts = text.split('.')
        if (parts.size != 4) return null
        var value = 0L
        for (part in parts) {
            val octet = part.toIntOrNull() ?: return null
            if (octet !in 0..255) return null
            value = value * 256 + octet
        }
        return value
    }

    /**
     * geoip.dat is a protobuf GeoIPList: repeated GeoIP (field 1), each with
     * country_code (1) and repeated CIDR (2) of ip bytes (1) and prefix (2).
     * Only the IR entry is decoded; the rest is skipped.
     */
    private fun loadIran(context: Context): List<LongArray> {
        val ranges = mutableListOf<LongArray>()
        try {
            BufferedInputStream(context.assets.open("geoip.dat"), 1 shl 16).use { input ->
                while (true) {
                    val key = varint(input) ?: break
                    val length = varint(input)!!.toInt()
                    if (key.toInt() != (1 shl 3 or 2)) {
                        skip(input, length.toLong()); continue
                    }
                    val entry = ByteArray(length)
                    readFully(input, entry)
                    parseEntry(entry, ranges)
                    if (ranges.isNotEmpty()) break
                }
            }
        } catch (e: Exception) {
            Log.w("CottenDNS", "geoip.dat unreadable: ${e.message}")
        }
        return ranges
    }

    private fun parseEntry(entry: ByteArray, ranges: MutableList<LongArray>) {
        val input = entry.inputStream()
        var country = ""
        val cidrs = mutableListOf<ByteArray>()
        while (true) {
            val key = varint(input) ?: break
            when ((key and 7L).toInt()) {
                0 -> varint(input)
                2 -> {
                    val bytes = ByteArray(varint(input)!!.toInt())
                    readFully(input, bytes)
                    when ((key shr 3).toInt()) {
                        1 -> country = String(bytes)
                        2 -> cidrs += bytes
                    }
                }
                else -> return
            }
        }
        if (!country.equals("IR", ignoreCase = true)) return
        for (cidr in cidrs) {
            val inner = cidr.inputStream()
            var ip: ByteArray? = null
            var prefix = 0
            while (true) {
                val key = varint(inner) ?: break
                when ((key shr 3).toInt()) {
                    1 -> { ip = ByteArray(varint(inner)!!.toInt()); readFully(inner, ip) }
                    2 -> prefix = varint(inner)!!.toInt()
                    else -> break
                }
            }
            if (ip == null || ip.size != 4) continue
            var start = 0L
            for (b in ip) start = start * 256 + (b.toInt() and 0xff)
            val size = 1L shl (32 - prefix)
            start = start and (size - 1).inv() and 0xffffffffL
            ranges += longArrayOf(start, start + size - 1)
        }
    }

    private fun varint(input: InputStream): Long? {
        var result = 0L
        var shift = 0
        while (true) {
            val b = input.read()
            if (b < 0) return if (shift == 0) null else throw java.io.EOFException()
            result = result or ((b and 0x7f).toLong() shl shift)
            if (b and 0x80 == 0) return result
            shift += 7
        }
    }

    private fun readFully(input: InputStream, into: ByteArray) {
        var read = 0
        while (read < into.size) {
            val n = input.read(into, read, into.size - read)
            if (n < 0) throw java.io.EOFException()
            read += n
        }
    }

    private fun skip(input: InputStream, count: Long) {
        var left = count
        while (left > 0) {
            val n = input.skip(left)
            if (n <= 0) {
                if (input.read() < 0) throw java.io.EOFException()
                left--
            } else {
                left -= n
            }
        }
    }
}
