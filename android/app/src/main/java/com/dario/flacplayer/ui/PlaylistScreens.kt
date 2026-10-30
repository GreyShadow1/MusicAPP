package com.dario.flacplayer.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material3.AlertDialog
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
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.dario.flacplayer.audio.AudioPlayer
import com.dario.flacplayer.library.MusicLibrary
import com.dario.flacplayer.model.Track
import sh.calvin.reorderable.ReorderableItem
import sh.calvin.reorderable.rememberReorderableLazyListState

@Composable
fun PlaylistsScreen(library: MusicLibrary, open: (Page) -> Unit) {
    val playlists by library.playlists.collectAsState()
    val favorites by library.favorites.collectAsState()
    var creating by remember { mutableStateOf(false) }

    Column(Modifier.statusBarsPadding()) {
        Row(Modifier.padding(start = 16.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                "Playlist", Modifier.weight(1f),
                style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold,
            )
            IconButton({ creating = true }) { Icon(Icons.Filled.Add, "Nuova playlist") }
        }
        LazyColumn {
            item {
                ListRow(library, null, "PREFERITI", "${favorites.size} brani · automatica") { open(Page.FavoritesPage) }
            }
            items(playlists, key = { it.id }) { playlist ->
                val cover = library.tracks(playlist.trackIds.take(10)).firstNotNullOfOrNull { it.coverId }
                ListRow(library, cover, playlist.name, "${playlist.trackIds.size} brani") { open(Page.PlaylistPage(playlist.id)) }
            }
        }
    }

    if (creating) {
        NameDialog("Nuova playlist", confirm = "Crea", onDismiss = { creating = false }) {
            library.createPlaylist(it)
            creating = false
        }
    }
}

@Composable
fun PlaylistScreen(library: MusicLibrary, player: AudioPlayer, id: String, onClose: () -> Unit) {
    val playlists by library.playlists.collectAsState()
    val byId by library.tracksById.collectAsState()
    val playlist = playlists.firstOrNull { it.id == id }
    var adding by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }

    if (playlist == null) {
        EmptyState("Playlist eliminata", "")
        return
    }
    val tracks = playlist.trackIds.mapNotNull { byId[it] }
    val listState = rememberLazyListState()
    val reorderable = rememberReorderableLazyListState(listState) { from, to ->
        library.moveTrack(id, from.index - 1, to.index - 1)
    }

    Column(Modifier.statusBarsPadding()) {
        Row(Modifier.padding(start = 16.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                playlist.name, Modifier.weight(1f), style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
            IconButton({ adding = true }) { Icon(Icons.Filled.Add, "Aggiungi brani") }
            IconButton({ renaming = true }) { Icon(Icons.Filled.Edit, "Rinomina") }
            IconButton({ deleting = true }) { Icon(Icons.Filled.Delete, "Elimina playlist") }
        }
        LazyColumn(state = listState) {
            item(key = "header") {
                if (tracks.isEmpty()) {
                    Text("Questa playlist è vuota.", Modifier.padding(16.dp), color = Secondary)
                } else {
                    PlayActions(
                        { player.play(tracks, 0, playlist.name) },
                        { player.shufflePlay(tracks, playlist.name) },
                    )
                }
            }
            // La chiave include la posizione: lo stesso brano può comparire due volte.
            itemsIndexed(tracks, key = { index, track -> "$index-${track.id}" }) { index, track ->
                ReorderableItem(reorderable, key = "$index-${track.id}") {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        TrackRow(library, player, track, modifier = Modifier.weight(1f)) {
                            player.play(tracks, index, playlist.name)
                        }
                        IconButton({ library.removeTrackAt(index, id) }) {
                            Icon(Icons.Filled.Close, "Rimuovi dalla playlist", tint = Secondary)
                        }
                        IconButton({}, Modifier.draggableHandle()) {
                            Icon(Icons.Filled.DragHandle, "Trascina per riordinare", tint = Secondary)
                        }
                    }
                }
            }
        }
    }

    if (adding) TrackPicker(library, "Aggiungi brani", { adding = false }) { selected ->
        library.add(selected.map { it.id }, id)
    }
    if (renaming) {
        NameDialog("Rinomina playlist", playlist.name, "Salva", { renaming = false }) {
            library.rename(playlist, it)
            renaming = false
        }
    }
    if (deleting) {
        ConfirmDialog(
            "Eliminare la playlist «${playlist.name}»?", "I brani resteranno nella libreria.", "Elimina",
            onDismiss = { deleting = false },
            onConfirm = {
                library.delete(playlist)
                deleting = false
                onClose()
            },
        )
    }
}

@Composable
fun AddToPlaylistDialog(library: MusicLibrary, trackIds: List<String>, onDismiss: () -> Unit) {
    val playlists by library.playlists.collectAsState()
    var creating by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Aggiungi a playlist") },
        text = {
            LazyColumn(Modifier.heightIn(max = 320.dp)) {
                item { TextButton({ creating = true }) { Text("Nuova playlist") } }
                items(playlists, key = { it.id }) { playlist ->
                    Text(
                        playlist.name,
                        Modifier.fillMaxWidth().clickable {
                            library.add(trackIds, playlist.id)
                            onDismiss()
                        }.padding(12.dp),
                    )
                }
            }
        },
        confirmButton = { TextButton(onDismiss) { Text("Annulla") } },
    )
    if (creating) {
        NameDialog("Nuova playlist", confirm = "Crea", onDismiss = { creating = false }) {
            library.createPlaylist(it, trackIds)
            creating = false
            onDismiss()
        }
    }
}

/** Selezione multipla di brani dalla libreria. */
@Composable
fun TrackPicker(library: MusicLibrary, title: String, onDismiss: () -> Unit, onConfirm: (List<Track>) -> Unit) {
    val all by library.tracks.collectAsState()
    var query by remember { mutableStateOf("") }
    var selection by remember { mutableStateOf(emptySet<String>()) }
    val sorted = remember(all) { all.filterNot { it.isMissing }.sortedBy { it.title.lowercase() } }
    val visible = sorted.filter {
        it.title.contains(query.trim(), true) || it.artist.contains(query.trim(), true) || it.album.contains(query.trim(), true)
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column {
                OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth(), placeholder = { Text("Cerca") }, singleLine = true)
                LazyColumn(Modifier.heightIn(max = 380.dp)) {
                    items(visible, key = { it.id }) { track ->
                        val selected = track.id in selection
                        Row(
                            Modifier.fillMaxWidth().clickable {
                                selection = if (selected) selection - track.id else selection + track.id
                            }.padding(vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(track.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(track.artist, color = Secondary, style = MaterialTheme.typography.bodySmall, maxLines = 1)
                            }
                            Spacer(Modifier.width(8.dp))
                            Icon(
                                if (selected) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                                null, tint = if (selected) Accent else Secondary,
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton({ onConfirm(sorted.filter { it.id in selection }); onDismiss() }, enabled = selection.isNotEmpty()) {
                Text("Aggiungi")
            }
        },
        dismissButton = { TextButton(onDismiss) { Text("Annulla") } },
    )
}
