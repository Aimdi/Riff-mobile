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

    @Test
    fun audioEffectSuiteIsPresent() {
        // The full effect chain we bind to must exist in the compile SDK.
        assertTrue(Class.forName("android.media.audiofx.LoudnessEnhancer")
            .methods.any { it.name == "setTargetGain" })
        assertTrue(Class.forName("android.media.audiofx.PresetReverb")
            .methods.any { it.name == "setPreset" })
        assertTrue(Class.forName("android.media.audiofx.Virtualizer")
            .methods.any { it.name == "setStrength" })
    }
}
