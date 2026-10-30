package com.dario.flacplayer.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.dario.flacplayer.audio.EqPresets
import com.dario.flacplayer.audio.EqualizerController

private fun bandLabel(hertz: Int) =
    if (hertz >= 1000) "${hertz / 1000} kHz" else "$hertz Hz"

@Composable
fun EqualizerScreen(controller: EqualizerController) {
    val state by controller.state.collectAsState()
    val bands by controller.bands.collectAsState()

    Column(Modifier.fillMaxSize().statusBarsPadding().verticalScroll(rememberScrollState()).padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                "Equalizzatore", Modifier.weight(1f),
                style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold,
            )
            Switch(state.enabled, controller::setEnabled, enabled = bands.isNotEmpty())
        }
        if (bands.isEmpty()) {
            Text("Questo dispositivo non mette a disposizione un equalizzatore.", color = Secondary)
            return@Column
        }
        Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            EqPresets.all.forEach { preset ->
                FilterChip(state.preset == preset.name, { controller.selectPreset(preset) }, { Text(preset.name) })
            }
        }
        bands.forEachIndexed { index, hertz ->
            val gain = state.gains.getOrElse(index) { 0f }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(bandLabel(hertz), Modifier.width(64.dp), color = Secondary, style = MaterialTheme.typography.bodySmall)
                Slider(
                    gain, { controller.setBand(index, it) }, Modifier.weight(1f),
                    enabled = state.enabled,
                    valueRange = -controller.maxGain..controller.maxGain,
                )
                Text("%+.1f".format(gain), Modifier.width(44.dp), color = Secondary, style = MaterialTheme.typography.bodySmall)
            }
        }
        Text(
            "Quando è spento, l'audio non viene modificato. Le bande dipendono dal telefono.",
            Modifier.padding(top = 8.dp), color = Secondary, style = MaterialTheme.typography.bodySmall,
        )
    }
}
