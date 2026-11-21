package org.nebulavpn.nebula_mobile

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class GuardedInputsTest {
    @get:Rule
    val dir = TemporaryFolder()

    private val token = "a".repeat(64)

    @Test
    fun disconnectNeedsTheAppsOwnToken() {
        val files = dir.newFolder("files")
        // No token written yet: nothing is accepted.
        assertFalse(GuardedInputs.disconnectTokenMatches(files, token))
        File(files, GuardedInputs.DISCONNECT_TOKEN_FILE).writeText("$token\n")
        assertTrue(GuardedInputs.disconnectTokenMatches(files, token))
        // What another app can send: nothing, empty, or a guess.
        assertFalse(GuardedInputs.disconnectTokenMatches(files, null))
        assertFalse(GuardedInputs.disconnectTokenMatches(files, ""))
        assertFalse(GuardedInputs.disconnectTokenMatches(files, "b".repeat(64)))
        assertFalse(GuardedInputs.disconnectTokenMatches(files, token.substring(1)))
    }

    @Test
    fun aShortStoredTokenIsNeverAccepted() {
        val files = dir.newFolder("files")
        File(files, GuardedInputs.DISCONNECT_TOKEN_FILE).writeText("abc")
        assertFalse(GuardedInputs.disconnectTokenMatches(files, "abc"))
    }

    @Test
    fun onlyAnApkDirectlyInUpdatesIsInstalled() {
        val cache = dir.newFolder("cache")
        val updates = File(cache, "updates").apply { mkdirs() }
        val apk = File(updates, "nebula.apk").apply { writeText("x") }
        assertEquals(apk.canonicalFile, GuardedInputs.installableUpdate(cache, apk.path))
        // Outside the folder, by a way round it, or not an APK.
        val outside = File(cache, "evil.apk").apply { writeText("x") }
        assertNull(GuardedInputs.installableUpdate(cache, outside.path))
        assertNull(GuardedInputs.installableUpdate(cache, "${updates.path}/../evil.apk"))
        val notApk = File(updates, "notes.txt").apply { writeText("x") }
        assertNull(GuardedInputs.installableUpdate(cache, notApk.path))
        val nested = File(updates, "deeper").apply { mkdirs() }
        val deep = File(nested, "nebula.apk").apply { writeText("x") }
        assertNull(GuardedInputs.installableUpdate(cache, deep.path))
        assertNull(GuardedInputs.installableUpdate(cache, File(updates, "missing.apk").path))
        assertNull(GuardedInputs.installableUpdate(cache, null))
    }
}
