package com.dario.flacplayer.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.filled.Equalizer
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.RepeatOne
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.dario.flacplayer.audio.AudioPlayer
import com.dario.flacplayer.audio.RepeatMode
import com.dario.flacplayer.library.MusicLibrary
import com.dario.flacplayer.model.Track
import sh.calvin.reorderable.ReorderableItem
import sh.calvin.reorderable.rememberReorderableLazyListState

@Composable
fun NowPlayingScreen(library: MusicLibrary, player: AudioPlayer, open: (Page) -> Unit) {
    val current by player.currentTrack.collectAsState()
    val playing by player.isPlaying.collectAsState()
    val queue by player.queue.collectAsState()
    val equalizer by player.equalizer.state.collectAsState()
    val track = current

    if (track == null) {
        EmptyState("Nessun brano in riproduzione", "Scegli un brano dalla libreria.")
        return
    }

    BoxWithConstraints(Modifier.fillMaxSize().statusBarsPadding().padding(horizontal = 28.dp)) {
        val side = minOf(maxWidth, maxHeight * 0.48f)
        Column(
            Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceEvenly,
        ) {
            Cover(library, track.coverId, side, 12.dp)
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    track.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis,
                )
                Text(track.artist, color = Secondary, maxLines = 1)
                Text(track.album, color = Secondary, maxLines = 1, style = MaterialTheme.typography.bodyMedium)
                Text("FLAC ${track.quality}", color = Secondary, style = MaterialTheme.typography.labelSmall)
                Text(player.outputDescription, color = Secondary, style = MaterialTheme.typography.labelSmall)
            }
            ProgressBar(player)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                IconButton(player::previous, Modifier.size(56.dp)) {
                    Icon(Icons.Filled.SkipPrevious, "Brano precedente", Modifier.size(36.dp))
                }
                IconButton(player::togglePlayPause, Modifier.size(76.dp)) {
                    Icon(
                        if (playing) Icons.Filled.PauseCircle else Icons.Filled.PlayCircle,
                        if (playing) "Pausa" else "Riproduci", Modifier.size(72.dp),
                    )
                }
                IconButton(player::next, Modifier.size(56.dp)) {
                    Icon(Icons.Filled.SkipNext, "Brano successivo", Modifier.size(36.dp))
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                IconButton(player::toggleShuffle) {
                    Icon(
                        Icons.Filled.Shuffle, "Riproduzione casuale",
                        tint = if (queue.shuffled) Accent else Secondary,
                    )
                }
                IconButton(player::cycleRepeat) {
                    Icon(
                        if (queue.repeat == RepeatMode.ONE) Icons.Filled.RepeatOne else Icons.Filled.Repeat,
                        "Ripetizione", tint = if (queue.repeat == RepeatMode.OFF) Secondary else Accent,
                    )
                }
                FavoriteButton(library, track.id)
                IconButton({ open(Page.EqualizerPage) }) {
                    Icon(Icons.Filled.Equalizer, "Equalizzatore", tint = if (equalizer.enabled) Accent else Secondary)
                }
                IconButton({ open(Page.QueuePage) }) {
                    Icon(Icons.AutoMirrored.Filled.List, "Coda di riproduzione", tint = Secondary)
                }
            }
        }
    }
}

/** Durante il trascinamento mostra il punto scelto; la riproduzione si sposta al rilascio. */
@Composable
private fun ProgressBar(player: AudioPlayer) {
    val position by player.positionMs.collectAsState()
    val duration by player.durationMs.collectAsState()
    var dragged by remember { mutableStateOf<Float?>(null) }
    val shown = dragged ?: position.toFloat()

    Column {
        Slider(
            value = shown.coerceIn(0f, duration.toFloat().coerceAtLeast(1f)),
            onValueChange = { dragged = it },
            onValueChangeFinished = {
                dragged?.let { player.seekTo(it.toLong()) }
                dragged = null
            },
            valueRange = 0f..duration.toFloat().coerceAtLeast(1f),
            enabled = duration > 0,
        )
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(formatTime(shown.toLong()), color = Secondary, style = MaterialTheme.typography.bodySmall)
            Text(formatTime(duration), color = Secondary, style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun QueueRow(library: MusicLibrary, track: Track, trailing: @Composable () -> Unit = {}, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(start = 16.dp, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Cover(library, track.coverId, 40.dp)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(track.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(track.artist, color = Secondary, style = MaterialTheme.typography.bodySmall, maxLines = 1)
        }
        trailing()
    }
}

@Composable
fun QueueScreen(library: MusicLibrary, player: AudioPlayer) {
    val queue by player.queue.collectAsState()
    val current by player.currentTrack.collectAsState()
    val byId by library.tracksById.collectAsState()
    var adding by remember { mutableStateOf(false) }

    val upcoming = queue.upcoming
    val listState = rememberLazyListState()
    val reorderable = rememberReorderableLazyListState(listState) { from, to ->
        player.moveUpcoming(from.index - HEADER_ROWS, to.index - HEADER_ROWS)
    }

    Column(Modifier.statusBarsPadding()) {
        Row(Modifier.padding(start = 16.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Coda", Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            IconButton({ adding = true }) { Icon(Icons.Filled.Add, "Aggiungi brani") }
            TextButton(player::clearQueue, enabled = upcoming.isNotEmpty()) { Text("Svuota") }
        }
        LazyColumn(state = listState) {
            item(key = "current") {
                Column {
                    Text("In riproduzione", Modifier.padding(16.dp, 4.dp), color = Secondary)
                    current?.let { QueueRow(library, it) {} }
                    if (queue.source.isNotEmpty()) {
                        Text("Da: ${queue.source}", Modifier.padding(16.dp, 2.dp), color = Secondary, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
            item(key = "next") {
                Text(
                    if (upcoming.isNotEmpty()) "Successivi"
                    else if (queue.repeat == RepeatMode.ALL) "Alla fine la coda ricomincerà dal primo brano."
                    else "Non ci sono altri brani in coda.",
                    Modifier.padding(16.dp, 8.dp), color = Secondary,
                )
            }
            itemsIndexed(upcoming, key = { _, item -> item.id }) { _, item ->
                ReorderableItem(reorderable, key = item.id) {
                    byId[item.trackId]?.let { track ->
                        QueueRow(library, track, trailing = {
                            IconButton({ player.removeFromQueue(item.id) }) {
                                Icon(Icons.Filled.Close, "Rimuovi", tint = Secondary)
                            }
                            IconButton({}, Modifier.draggableHandle()) {
                                Icon(Icons.Filled.DragHandle, "Trascina per riordinare", tint = Secondary)
                            }
                        }) { player.jump(item.id) }
                    }
                }
            }
        }
    }

    if (adding) TrackPicker(library, "Aggiungi alla coda", { adding = false }) { player.addToQueue(it) }
}

private const val HEADER_ROWS = 2
