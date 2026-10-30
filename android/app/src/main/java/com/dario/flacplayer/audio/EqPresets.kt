package com.dario.flacplayer.audio

import kotlin.math.ln

data class EqPreset(val name: String, val gains: List<Float>)

/** Stato dell'equalizzatore. `preset` è null quando i cursori sono stati modificati a mano. */
data class EqState(
    val enabled: Boolean = false,
    val preset: String? = "Piatto",
    val gains: List<Float> = emptyList(),
)

/** Preset a 10 bande, in dB. Gli stessi valori sono usati dall'app iOS. */
object EqPresets {
    val frequencies = listOf(32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000)

    val all = listOf(
        EqPreset("Piatto", listOf(0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f)),
        EqPreset("Bassi", listOf(6f, 5f, 4f, 2f, 0f, 0f, 0f, 0f, 0f, 0f)),
        EqPreset("Rock", listOf(4f, 3f, 2f, 0f, -1f, -1f, 1f, 2f, 3f, 4f)),
        EqPreset("Pop", listOf(-1f, 0f, 1f, 3f, 4f, 3f, 1f, 0f, -1f, -1f)),
        EqPreset("Jazz", listOf(3f, 2f, 1f, 2f, -1f, -1f, 0f, 1f, 2f, 3f)),
        EqPreset("Classica", listOf(3f, 2f, 1f, 0f, 0f, 0f, 0f, 1f, 2f, 3f)),
        EqPreset("Elettronica", listOf(5f, 4f, 1f, 0f, -2f, 1f, 0f, 1f, 4f, 5f)),
        EqPreset("Voce", listOf(-2f, -2f, -1f, 1f, 3f, 4f, 3f, 1f, 0f, -1f)),
    )

    /** Valore del preset a una frequenza qualsiasi: i telefoni hanno bande diverse. */
    fun gainAt(preset: EqPreset, hertz: Int): Float {
        val first = frequencies.first()
        val last = frequencies.last()
        if (hertz <= first) return preset.gains.first()
        if (hertz >= last) return preset.gains.last()
        val upper = frequencies.indexOfFirst { it >= hertz }
        val lower = upper - 1
        val position = (ln(hertz.toDouble()) - ln(frequencies[lower].toDouble())) /
            (ln(frequencies[upper].toDouble()) - ln(frequencies[lower].toDouble()))
        return (preset.gains[lower] + (preset.gains[upper] - preset.gains[lower]) * position).toFloat()
    }
}
