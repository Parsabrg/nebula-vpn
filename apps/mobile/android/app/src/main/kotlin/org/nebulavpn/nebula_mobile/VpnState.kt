package org.nebulavpn.nebula_mobile

import android.app.ActivityManager
import android.app.AppOpsManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build

/**
 * The two questions about VPNs this app asks, answered without changing
 * anything. Shared by the activity and by [RestartReceiver], which runs with
 * no activity at all.
 */
object VpnState {
    /**
     * Whether the user has approved this app as a VPN, found out without
     * changing anything.
     *
     * Not VpnService.prepare(). For an app approved before, prepare() makes it
     * the active VPN app on the spot, which tears down whatever VPN is running
     * -- v2rayNG's, say. Called only to ask a question, it could disconnect
     * somebody's other VPN just because this app was opened. The consent it
     * would have found is this app op, which is what Android itself checks.
     */
    fun consentHeld(context: Context): Boolean {
        return try {
            val appOps = context.getSystemService(AppOpsManager::class.java) ?: return false
            val uid = context.applicationInfo.uid
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow("android:activate_vpn", uid, context.packageName)
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow("android:activate_vpn", uid, context.packageName)
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (error: Exception) {
            false
        }
    }

    /**
     * Whose VPN is up: "own", "other", "none", or null where Android does not
     * say -- before 11 there is no owner on a network (getOwnerUid is API 30;
     * gated on 10, it crashed the app on a moto g8 plus, 2026-11-21).
     *
     * Every network, not `activeNetwork`: that one answers for the calling app,
     * and the Xray tunnel excludes this app from itself, so from in here a
     * running tunnel looks like plain Wi-Fi.
     *
     * Read off the VPN network's owner UID, which answers the question without
     * touching anything. It replaced asking whether a VPN was up and then
     * whether this app held consent, whose second half was prepare() and could
     * disconnect the very VPN it was asking about.
     */
    @Suppress("DEPRECATION") // The replacement is a callback; this is a one-off question.
    fun owner(context: Context): String? {
        val connectivity = context.getSystemService(ConnectivityManager::class.java) ?: return null
        var anyVpn = false
        for (network in connectivity.allNetworks) {
            val capabilities = connectivity.getNetworkCapabilities(network) ?: continue
            if (!capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                continue
            }
            anyVpn = true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                capabilities.ownerUid == context.applicationInfo.uid
            ) {
                return "own"
            }
        }
        return when {
            !anyVpn -> "none"
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> "other"
            // 8-10 name no owner. A VPN up while this app's own VPN service
            // runs is this app's: answered "unknown", the app opened from
            // the notification showed Off over its own running tunnel
            // (moto g8 plus, Android 10, 2026-11-21).
            ownVpnServiceRunning(context) -> "own"
            else -> null
        }
    }

    /** Whether one of this app's VPN services (Xray's or WireGuard's) runs. */
    @Suppress("DEPRECATION") // Still answers for the app's own services.
    private fun ownVpnServiceRunning(context: Context): Boolean {
        val activities = context.getSystemService(ActivityManager::class.java) ?: return false
        return try {
            activities.getRunningServices(Int.MAX_VALUE).any {
                it.service.packageName == context.packageName &&
                    it.service.className.endsWith("VpnService")
            }
        } catch (error: SecurityException) {
            false
        }
    }

    /**
     * Whether there is a network to tunnel over at all: any network but a
     * VPN that offers the internet. Not Android's "validated": that check
     * reaches Google, which networks in Iran often block, and they carry
     * tunnels all the same. Null where Android does not say.
     */
    @Suppress("DEPRECATION") // A one-off question, as in owner().
    fun hasNetwork(context: Context): Boolean? {
        val connectivity = context.getSystemService(ConnectivityManager::class.java) ?: return null
        return connectivity.allNetworks.any { network ->
            val capabilities = connectivity.getNetworkCapabilities(network)
            capabilities != null &&
                !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        }
    }
}
