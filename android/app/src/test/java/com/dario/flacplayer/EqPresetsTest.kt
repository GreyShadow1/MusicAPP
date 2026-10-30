package com.dario.flacplayer

import com.dario.flacplayer.audio.EqPresets
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class EqPresetsTest {
    @Test fun everyPresetHasOneGainPerBand() {
        EqPresets.all.forEach { assertEquals(it.name, EqPresets.frequencies.size, it.gains.size) }
    }

    @Test fun presetsStayWithinSafeRange() {
        EqPresets.all.flatMap { it.gains }.forEach { assertTrue(it in -6f..6f) }
    }

    @Test fun exactBandReturnsItsValue() {
        val rock = EqPresets.all.first { it.name == "Rock" }
        assertEquals(4f, EqPresets.gainAt(rock, 32), 0.001f)
        assertEquals(-1f, EqPresets.gainAt(rock, 1000), 0.001f)
    }

    @Test fun frequenciesOutsideRangeUseEdges() {
        val bass = EqPresets.all.first { it.name == "Bassi" }
        assertEquals(6f, EqPresets.gainAt(bass, 10), 0.001f)
        assertEquals(0f, EqPresets.gainAt(bass, 20000), 0.001f)
    }

    @Test fun betweenBandsIsInterpolated() {
        val bass = EqPresets.all.first { it.name == "Bassi" }
        val gain = EqPresets.gainAt(bass, 90)
        assertTrue(gain < 5f && gain > 4f)
    }
}
