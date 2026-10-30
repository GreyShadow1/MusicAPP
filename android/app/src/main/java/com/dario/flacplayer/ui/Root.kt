package com.dario.flacplayer.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.dario.flacplayer.audio.AudioPlayer
import com.dario.flacplayer.library.MusicLibrary
import com.dario.flacplayer.model.Album
import com.dario.flacplayer.model.Artist

enum class Tab(val label: String, val icon: ImageVector) {
    LIBRARY("Libreria", Icons.Filled.LibraryMusic),
    PLAYLISTS("Playlist", Icons.AutoMirrored.Filled.QueueMusic),
    FAVORITES("Preferiti", Icons.Filled.Favorite),
    NOW_PLAYING("In riproduzione", Icons.Filled.PlayCircle),
}

/** Pagine interne a una scheda. */
sealed interface Page {
    data class AlbumPage(val album: Album) : Page
    data class ArtistPage(val artist: Artist) : Page
    data class PlaylistPage(val id: String) : Page
    data object FavoritesPage : Page
    data object QueuePage : Page
    data object EqualizerPage : Page
}

private val colors = darkColorScheme(
    primary = Accent,
    secondary = Accent,
    primaryContainer = Color(0xFF1F3A30),
    secondaryContainer = Color(0xFF1F3A30),
    onSecondaryContainer = Accent,
    surfaceContainerHighest = Color(0xFF2A2A2A),
    background = Color.Black,
    surface = Color.Black,
    surfaceContainer = Surface,
    onBackground = Color.White,
    onSurface = Color.White,
)

@Composable
fun FlacPlayerRoot(library: MusicLibrary, player: AudioPlayer) {
    MaterialTheme(colorScheme = colors) {
        var tab by remember { mutableStateOf(Tab.LIBRARY) }
        val pages = remember { mutableStateListOf<Page>() }
        val open: (Page) -> Unit = { pages.add(it) }

        BackHandler(pages.isNotEmpty()) { pages.removeAt(pages.lastIndex) }

        Scaffold(
            containerColor = Color.Black,
            bottomBar = {
                Column {
                    if (tab != Tab.NOW_PLAYING && pages.lastOrNull() != Page.QueuePage) {
                        MiniPlayer(library, player) { pages.clear(); tab = Tab.NOW_PLAYING }
                    }
                    NavigationBar(containerColor = Color.Black) {
                        Tab.entries.forEach { item ->
                            NavigationBarItem(
                                selected = tab == item,
                                onClick = { pages.clear(); tab = item },
                                icon = { Icon(item.icon, item.label) },
                                label = { Text(item.label, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                            )
                        }
                    }
                }
            },
        ) { padding ->
            Box(Modifier.padding(padding).fillMaxSize()) {
                when (val page = pages.lastOrNull()) {
                    is Page.AlbumPage -> AlbumScreen(library, player, page.album)
                    is Page.ArtistPage -> ArtistScreen(library, player, page.artist, open)
                    is Page.PlaylistPage -> PlaylistScreen(library, player, page.id) { pages.removeAt(pages.lastIndex) }
                    Page.FavoritesPage -> FavoritesScreen(library, player)
                    Page.QueuePage -> QueueScreen(library, player)
                    Page.EqualizerPage -> EqualizerScreen(player.equalizer)
                    null -> when (tab) {
                        Tab.LIBRARY -> LibraryScreen(library, player, open)
                        Tab.PLAYLISTS -> PlaylistsScreen(library, open)
                        Tab.FAVORITES -> FavoritesScreen(library, player)
                        Tab.NOW_PLAYING -> NowPlayingScreen(library, player, open)
                    }
                }
            }
        }

        val libraryError by library.error.collectAsState()
        val playerError by player.error.collectAsState()
        val message = libraryError ?: playerError
        if (message != null) {
            val dismiss = { if (libraryError != null) library.error.value = null else player.error.value = null }
            AlertDialog(
                onDismissRequest = dismiss,
                title = { Text("Attenzione") },
                text = { Text(message) },
                confirmButton = { TextButton(dismiss) { Text("OK") } },
            )
        }
    }
}

@Composable
private fun MiniPlayer(library: MusicLibrary, player: AudioPlayer, onOpen: () -> Unit) {
    val track by player.currentTrack.collectAsState()
    val playing by player.isPlaying.collectAsState()
    val position by player.positionMs.collectAsState()
    val duration by player.durationMs.collectAsState()
    val current = track ?: return

    Column(Modifier.background(Surface)) {
        LinearProgressIndicator(
            progress = { if (duration > 0) position.toFloat() / duration else 0f },
            Modifier.fillMaxWidth().height(2.dp),
            color = Accent, trackColor = Surface, drawStopIndicator = {},
        )
        Row(Modifier.padding(start = 12.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(
                Modifier.weight(1f).clickable(onClick = onOpen).padding(vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Cover(library, current.coverId, 40.dp, 4.dp)
                Spacer(Modifier.width(12.dp))
                Column {
                    Text(current.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(
                        current.artist, color = Secondary, style = MaterialTheme.typography.bodySmall,
                        maxLines = 1, overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            IconButton(player::togglePlayPause) {
                Icon(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (playing) "Pausa" else "Riproduci")
            }
            IconButton(player::next) { Icon(Icons.Filled.SkipNext, "Brano successivo") }
        }
    }
}
