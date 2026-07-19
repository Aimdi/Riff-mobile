package com.anandnet.harmonymusic

import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guards that the BassBoost AudioEffect API we bind to still exists in the
 * compile SDK (a cheap compile-time contract check; the effect itself
 * needs a device audio session to instantiate).
 */
class BassBoostAvailabilityTest {
    @Test
    fun bassBoostClassIsPresent() {
        val cls = Class.forName("android.media.audiofx.BassBoost")
        assertTrue(
            cls.methods.any { it.name == "setStrength" })
    }
}
