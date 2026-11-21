package org.nebulavpn.nebula_mobile

import java.io.File
import java.security.MessageDigest

/**
 * The checks on what reaches this app from outside it, kept free of Android
 * so they can be tested on a plain JVM (review Q-07).
 */
object GuardedInputs {
    /** Where the notification's Disconnect token lives (V2rayCoreManager writes it). */
    const val DISCONNECT_TOKEN_FILE = "disconnect_token"

    /**
     * Whether [given] is this app's Disconnect token. MainActivity is exported,
     * so any app can send the Disconnect action; only the notification's
     * button carries the token from the app's private files (review S-01).
     */
    fun disconnectTokenMatches(filesDir: File, given: String?): Boolean {
        if (given.isNullOrEmpty()) {
            return false
        }
        return try {
            val expected = File(filesDir, DISCONNECT_TOKEN_FILE).readText(Charsets.US_ASCII).trim()
            expected.length == 64 &&
                MessageDigest.isEqual(
                    expected.toByteArray(Charsets.US_ASCII),
                    given.toByteArray(Charsets.US_ASCII),
                )
        } catch (error: Exception) {
            false
        }
    }

    /**
     * The update the app may hand to the installer: an existing `.apk`
     * directly inside the cache's `updates` folder, after resolving `..` and
     * links, or null. Anything else Dart passes is refused.
     */
    fun installableUpdate(cacheDir: File, path: String?): File? {
        val folder = File(cacheDir, "updates").canonicalFile
        val file = path?.let { File(it).canonicalFile } ?: return null
        return if (file.parentFile == folder && file.isFile && file.name.endsWith(".apk")) file else null
    }
}
