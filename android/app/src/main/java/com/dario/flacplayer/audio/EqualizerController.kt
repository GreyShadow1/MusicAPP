package com.dario.flacplayer.audio

import android.media.audiofx.Equalizer
import com.dario.flacplayer.library.Database
import kotlin.math.pow
import kotlinx.coroutines.flow.MutableStateFlow
import org.json.JSONArray
import org.json.JSONObject

/**
 * Equalizzatore di sistema collegato alla sessione audio del player. Numero e
 * frequenza delle bande dipendono dal telefono, quindi i preset vengono adattati.
 */
class EqualizerController(
    private val database: Database,
    private val setVolume: (Float) -> Unit,
) {
    private companion object {
        const val SETTINGS_KEY = "equalizer"
    }

    private var equalizer: Equalizer? = null

    val state = MutableStateFlow(EqState())
    val bands = MutableStateFlow<List<Int>>(emptyList())
    var maxGain = 15f
        private set

    fun attach(sessionId: Int) {
        equalizer?.release()
        equalizer = runCatching { Equalizer(0, sessionId) }.getOrNull()
        val effect = equalizer
        if (effect == null) {
            bands.value = emptyList()
            setVolume(1f)
            return
        }
        bands.value = (0 until effect.numberOfBands).map { effect.getCenterFreq(it.toShort()) / 1000 }
        maxGain = effect.bandLevelRange[1] / 100f
        load()
        apply()
    }

    fun setEnabled(enabled: Boolean) = update(state.value.copy(enabled = enabled))

    fun selectPreset(preset: EqPreset) = update(
        state.value.copy(preset = preset.name, gains = bands.value.map { EqPresets.gainAt(preset, it) }),
    )

    fun setBand(index: Int, gain: Float) {
        val gains = state.value.gains.toMutableList()
        gains[index] = gain
        update(state.value.copy(preset = null, gains = gains))
    }

    private fun update(new: EqState) {
        state.value = new
        apply()
        database.setSetting(
            SETTINGS_KEY,
            JSONObject()
                .put("enabled", new.enabled)
                .put("preset", new.preset ?: "")
                .put("gains", JSONArray(new.gains.map(Float::toDouble)))
                .toString(),
        )
    }

    private fun load() {
        val flat = List(bands.value.size) { 0f }
        val json = database.setting(SETTINGS_KEY)?.let { runCatching { JSONObject(it) }.getOrNull() }
        val saved = json?.optJSONArray("gains")?.let { array -> List(array.length()) { array.getDouble(it).toFloat() } }
        // Le bande salvate valgono solo se il dispositivo è lo stesso.
        state.value = if (json != null && saved?.size == flat.size) {
            EqState(json.getBoolean("enabled"), json.getString("preset").ifEmpty { null }, saved)
        } else {
            EqState(gains = flat)
        }
    }

    private fun apply() {
        val effect = equalizer ?: return
        val current = state.value
        current.gains.forEachIndexed { band, gain ->
            effect.setBandLevel(band.toShort(), (gain * 100).toInt().toShort())
        }
        effect.enabled = current.enabled
        // Riduce il volume quanto il massimo aumento: evita la distorsione.
        val peak = if (current.enabled) current.gains.maxOrNull()?.coerceAtLeast(0f) ?: 0f else 0f
        setVolume(10f.pow(-peak / 20))
    }
}
