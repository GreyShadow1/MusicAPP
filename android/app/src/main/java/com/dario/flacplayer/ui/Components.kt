package com.dario.flacplayer.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.dario.flacplayer.audio.AudioPlayer
import com.dario.flacplayer.library.MusicLibrary
import com.dario.flacplayer.model.Track
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

val Secondary = Color(0xFF999999)
val Surface = Color(0xFF1C1C1C)
val Accent = Color(0xFF61C79E)

private val coverCache = LruCache<String, Bitmap>(200)

private fun loadCover(file: File, pixels: Int): Bitmap? {
    val key = "${file.name}-$pixels"
    coverCache.get(key)?.let { return it }
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(file.path, bounds)
    var sample = 1
    while (bounds.outWidth / (sample * 2) >= pixels) sample *= 2
    val bitmap = BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })
    return bitmap?.also { coverCache.put(key, it) }
}

@Composable
fun Cover(library: MusicLibrary, coverId: String?, side: Dp, corner: Dp = 6.dp) {
    val pixels = with(LocalDensity.current) { side.roundToPx() }
    val bitmap by produceState<Bitmap?>(null, coverId, pixels) {
        value = coverId?.let { id -> withContext(Dispatchers.IO) { loadCover(File(library.coversDir, id), pixels) } }
    }
    Box(
        Modifier.size(side).clip(RoundedCornerShape(corner)).background(Surface),
        contentAlignment = Alignment.Center,
    ) {
        val image = bitmap
        if (image != null) {
            Image(image.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        } else {
            Icon(Icons.Filled.MusicNote, null, Modifier.size(side * 0.4f), tint = Secondary)
        }
    }
}

@Composable
fun FavoriteButton(library: MusicLibrary, trackId: String) {
    val favorites by library.favorites.collectAsState()
    val favorite = trackId in favorites
    IconButton(onClick = { library.toggleFavorite(trackId) }) {
        Icon(
            if (favorite) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
            if (favorite) "Rimuovi dai preferiti" else "Aggiungi ai preferiti",
            tint = if (favorite) Accent else Secondary,
        )
    }
}

@Composable
fun TrackRow(
    library: MusicLibrary,
    player: AudioPlayer,
    track: Track,
    trackNumber: Int? = null,
    modifier: Modifier = Modifier,
    onPlay: () -> Unit,
) {
    val current by player.currentTrack.collectAsState()
    var menu by remember { mutableStateOf(false) }
    var picking by remember { mutableStateOf(false) }
    var confirming by remember { mutableStateOf(false) }
    val favorites by library.favorites.collectAsState()

    Row(
        modifier.fillMaxWidth().alpha(if (track.isMissing) 0.45f else 1f).padding(start = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier.weight(1f).clickable(onClick = onPlay).padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (trackNumber != null) {
                Text(if (trackNumber > 0) "$trackNumber" else "–", Modifier.width(28.dp), color = Secondary)
            } else {
                Cover(library, track.coverId, 44.dp)
            }
            Spacer(Modifier.width(12.dp))
            Column {
                Text(
                    track.title, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    color = if (current?.id == track.id) Accent else Color.White,
                )
                Text(
                    if (track.isMissing) "File mancante" else "${track.artist} · ${track.album}",
                    style = MaterialTheme.typography.bodySmall, color = Secondary,
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
            }
        }
        FavoriteButton(library, track.id)
        Box {
            IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreHoriz, "Altre azioni", tint = Secondary) }
            DropdownMenu(menu, { menu = false }) {
                DropdownMenuItem({ Text("Riproduci dopo") }, { menu = false; player.playNext(listOf(track)) })
                DropdownMenuItem({ Text("Aggiungi alla coda") }, { menu = false; player.addToQueue(listOf(track)) })
                DropdownMenuItem({ Text("Aggiungi a una playlist") }, { menu = false; picking = true })
                DropdownMenuItem(
                    { Text(if (track.id in favorites) "Rimuovi dai preferiti" else "Aggiungi ai preferiti") },
                    { menu = false; library.toggleFavorite(track.id) },
                )
                DropdownMenuItem(
                    { Text(if (library.isInAppFolder(track)) "Elimina dal telefono" else "Togli dalla libreria") },
                    { menu = false; confirming = true },
                )
            }
        }
    }

    if (picking) AddToPlaylistDialog(library, listOf(track.id)) { picking = false }
    if (confirming) {
        val deletes = library.isInAppFolder(track)
        ConfirmDialog(
            title = if (deletes) "Eliminare «${track.title}» dal telefono?" else "Togliere «${track.title}» dalla libreria?",
            message = if (deletes) "Il file verrà cancellato e il brano sparirà da playlist e preferiti."
            else "Il file resta sul telefono, ma il brano sparirà da libreria, playlist e preferiti.",
            confirm = if (deletes) "Elimina" else "Togli",
            onDismiss = { confirming = false },
            onConfirm = { confirming = false; library.remove(track) },
        )
    }
}

@Composable
fun ConfirmDialog(title: String, message: String, confirm: String, onDismiss: () -> Unit, onConfirm: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = { TextButton(onConfirm) { Text(confirm) } },
        dismissButton = { TextButton(onDismiss) { Text("Annulla") } },
    )
}

@Composable
fun NameDialog(title: String, initial: String = "", confirm: String, onDismiss: () -> Unit, onConfirm: (String) -> Unit) {
    var name by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { OutlinedTextField(name, { name = it }, label = { Text("Nome") }, singleLine = true) },
        confirmButton = { TextButton({ onConfirm(name) }) { Text(confirm) } },
        dismissButton = { TextButton(onDismiss) { Text("Annulla") } },
    )
}

@Composable
fun PlayActions(onPlay: () -> Unit, onShuffle: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(16.dp, 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        FilledTonalButton(onPlay, Modifier.weight(1f)) {
            Icon(Icons.Filled.PlayArrow, null)
            Text("Riproduci")
        }
        FilledTonalButton(onShuffle, Modifier.weight(1f)) {
            Icon(Icons.Filled.Shuffle, null)
            Spacer(Modifier.width(4.dp))
            Text("Casuale")
        }
    }
}

@Composable
fun EmptyState(title: String, message: String) {
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(Icons.Filled.MusicNote, null, Modifier.size(44.dp), tint = Secondary)
        Spacer(Modifier.height(12.dp))
        Text(title, fontWeight = FontWeight.SemiBold)
        Text(message, color = Secondary, style = MaterialTheme.typography.bodyMedium)
    }
}

fun formatTime(ms: Long): String {
    val total = (ms / 1000).coerceAtLeast(0)
    val hours = total / 3600
    val minutes = total % 3600 / 60
    val seconds = total % 60
    return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, seconds) else "%d:%02d".format(minutes, seconds)
}
