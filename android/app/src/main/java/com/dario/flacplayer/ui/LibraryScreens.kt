package com.dario.flacplayer.ui

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.dario.flacplayer.audio.AudioPlayer
import com.dario.flacplayer.library.MusicLibrary
import com.dario.flacplayer.model.Album
import com.dario.flacplayer.model.Artist
import com.dario.flacplayer.model.Track
import com.dario.flacplayer.model.TrackSort

private enum class Section(val label: String) { TRACKS("Brani"), ALBUMS("Album"), ARTISTS("Artisti") }

private fun Track.matches(query: String) =
    title.contains(query, ignoreCase = true) || artist.contains(query, ignoreCase = true) ||
        album.contains(query, ignoreCase = true)

@Composable
fun LibraryScreen(library: MusicLibrary, player: AudioPlayer, open: (Page) -> Unit) {
    var section by remember { mutableStateOf(Section.TRACKS) }
    var sort by remember { mutableStateOf(TrackSort.TITLE) }
    var query by remember { mutableStateOf("") }
    var sortMenu by remember { mutableStateOf(false) }
    val allTracks by library.tracks.collectAsState()
    val progress by library.progress.collectAsState()

    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        Row(Modifier.padding(start = 16.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                "Libreria", Modifier.weight(1f),
                style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold,
            )
            if (section == Section.TRACKS) {
                Box {
                    IconButton({ sortMenu = true }) { Icon(Icons.AutoMirrored.Filled.Sort, "Ordina") }
                    DropdownMenu(sortMenu, { sortMenu = false }) {
                        TrackSort.entries.forEach {
                            DropdownMenuItem({ Text(it.label) }, { sort = it; sortMenu = false })
                        }
                    }
                }
            }
            IconButton({ library.rescan(silent = false) }, enabled = progress == null) {
                Icon(Icons.Filled.Refresh, "Aggiorna la libreria")
            }
        }
        OutlinedTextField(
            query, { query = it },
            Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            placeholder = { Text("Titolo, artista o album") },
            leadingIcon = { Icon(Icons.Filled.Search, null) },
            singleLine = true,
        )
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(16.dp, 8.dp)) {
            Section.entries.forEachIndexed { index, item ->
                SegmentedButton(
                    selected = section == item,
                    onClick = { section = item },
                    shape = SegmentedButtonDefaults.itemShape(index, Section.entries.size),
                ) { Text(item.label) }
            }
        }

        val text = query.trim()
        when (section) {
            Section.TRACKS -> {
                val tracks = remember(allTracks, sort, text) {
                    sort.sorted(allTracks).filter { text.isEmpty() || it.matches(text) }
                }
                LazyColumn {
                    if (text.isEmpty()) item { ImportPanel(library) }
                    if (tracks.isEmpty() && text.isNotEmpty()) {
                        item { Text("Nessun risultato", Modifier.padding(16.dp), color = Secondary) }
                    }
                    itemsIndexed(tracks, key = { _, track -> track.id }) { index, track ->
                        TrackRow(library, player, track) { player.play(tracks, index, "Libreria") }
                    }
                }
            }
            Section.ALBUMS -> {
                val albums = remember(allTracks, text) {
                    library.albums.filter {
                        text.isEmpty() || it.title.contains(text, true) || it.artist.contains(text, true)
                    }
                }
                LazyVerticalGrid(GridCells.Fixed(2), Modifier.padding(horizontal = 16.dp)) {
                    items(albums, key = { it.id }) { album -> AlbumCell(library, album) { open(Page.AlbumPage(album)) } }
                }
            }
            Section.ARTISTS -> {
                val artists = remember(allTracks, text) {
                    library.artists.filter { text.isEmpty() || it.name.contains(text, true) }
                }
                LazyColumn {
                    items(artists, key = { it.name }) { artist ->
                        ListRow(library, artist.coverId, artist.name, "${artist.albums.size} album · ${artist.tracks.size} brani") {
                            open(Page.ArtistPage(artist))
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun ListRow(library: MusicLibrary, coverId: String?, title: String, subtitle: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(16.dp, 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Cover(library, coverId, 44.dp)
        Spacer(Modifier.width(12.dp))
        Column {
            Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(subtitle, color = Secondary, style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun AlbumCell(library: MusicLibrary, album: Album, onClick: () -> Unit) {
    Column(Modifier.padding(6.dp).clickable(onClick = onClick)) {
        Cover(library, album.coverId, 160.dp, 8.dp)
        Text(album.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(album.artist, color = Secondary, style = MaterialTheme.typography.bodySmall, maxLines = 1)
    }
}

@Composable
private fun ImportPanel(library: MusicLibrary) {
    val progress by library.progress.collectAsState()
    val result by library.lastResult.collectAsState()
    var choosing by remember { mutableStateOf(false) }
    var help by remember { mutableStateOf(false) }

    val files = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris: List<Uri> ->
        if (uris.isNotEmpty()) library.import(uris, null)
    }
    val folder = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri: Uri? ->
        if (uri != null) library.import(emptyList(), uri)
    }

    Column(Modifier.padding(16.dp, 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Button(
            { choosing = true }, Modifier.fillMaxWidth(), enabled = progress == null,
            colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Color.Black),
        ) { Text("IMPORTA MUSICA", fontWeight = FontWeight.Bold) }

        val running = progress
        if (running != null) {
            Text(running.title, color = Secondary, style = MaterialTheme.typography.bodySmall)
            if (running.total > 0) {
                LinearProgressIndicator({ running.completed.toFloat() / running.total }, Modifier.fillMaxWidth())
            } else {
                LinearProgressIndicator(Modifier.fillMaxWidth())
            }
        } else {
            result?.let { Text(it, color = Secondary, style = MaterialTheme.typography.bodySmall) }
        }
        TextButton({ help = true }) { Text("Trasferire musica via USB da Windows") }
    }

    if (choosing) {
        AlertDialog(
            onDismissRequest = { choosing = false },
            title = { Text("Importa musica") },
            text = { Text("Scegli singoli file FLAC oppure una cartella intera.") },
            confirmButton = {
                TextButton({ choosing = false; files.launch(arrayOf("audio/flac", "audio/x-flac", "application/octet-stream")) }) { Text("File") }
            },
            dismissButton = { TextButton({ choosing = false; folder.launch(null) }) { Text("Cartella") } },
        )
    }
    if (help) {
        AlertDialog(
            onDismissRequest = { help = false },
            title = { Text("Trasferimento USB") },
            text = {
                Text(
                    "1. Collega il telefono al PC con il cavo USB.\n" +
                        "2. Sul telefono scegli «Trasferimento file».\n" +
                        "3. In Esplora file apri il telefono e la cartella Music.\n" +
                        "4. Trascina i file FLAC o intere cartelle.\n" +
                        "5. Riapri FLAC Player: i nuovi brani vengono rilevati da soli.\n\n" +
                        "I file non vengono convertiti e i duplicati vengono ignorati.",
                )
            },
            confirmButton = { TextButton({ help = false }) { Text("Fine") } },
        )
    }
}

@Composable
private fun PageTitle(title: String) {
    Text(
        title, Modifier.statusBarsPadding().padding(16.dp, 8.dp),
        style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold,
    )
}

@Composable
fun AlbumScreen(library: MusicLibrary, player: AudioPlayer, album: Album) {
    val byId by library.tracksById.collectAsState()
    val tracks = album.tracks.mapNotNull { byId[it.id] }
    LazyColumn(Modifier.statusBarsPadding()) {
        item {
            Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Cover(library, album.coverId, 220.dp, 10.dp)
                Spacer(Modifier.height(8.dp))
                Text(album.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                Text(if (album.year.isEmpty()) album.artist else "${album.artist} · ${album.year}", color = Secondary)
            }
        }
        item {
            PlayActions({ player.play(tracks, 0, album.title) }, { player.shufflePlay(tracks, album.title) })
        }
        itemsIndexed(tracks, key = { _, track -> track.id }) { index, track ->
            TrackRow(library, player, track, trackNumber = track.trackNumber) { player.play(tracks, index, album.title) }
        }
    }
}

@Composable
fun ArtistScreen(library: MusicLibrary, player: AudioPlayer, artist: Artist, open: (Page) -> Unit) {
    val byId by library.tracksById.collectAsState()
    val tracks = artist.tracks.mapNotNull { byId[it.id] }
    LazyColumn {
        item { PageTitle(artist.name) }
        item { PlayActions({ player.play(tracks, 0, artist.name) }, { player.shufflePlay(tracks, artist.name) }) }
        items(artist.albums, key = { it.id }) { album ->
            ListRow(library, album.coverId, album.title, album.year) { open(Page.AlbumPage(album)) }
        }
    }
}

@Composable
fun FavoritesScreen(library: MusicLibrary, player: AudioPlayer) {
    val ids by library.favorites.collectAsState()
    val byId by library.tracksById.collectAsState()
    val tracks = ids.mapNotNull { byId[it] }
    Column {
        PageTitle("PREFERITI")
        if (tracks.isEmpty()) {
            EmptyState("Nessun preferito", "Tocca il cuore accanto a un brano per aggiungerlo qui.")
        } else {
            LazyColumn {
                item { PlayActions({ player.play(tracks, 0, "PREFERITI") }, { player.shufflePlay(tracks, "PREFERITI") }) }
                itemsIndexed(tracks, key = { _, track -> track.id }) { index, track ->
                    TrackRow(library, player, track) { player.play(tracks, index, "PREFERITI") }
                }
            }
        }
    }
}
