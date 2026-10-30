package com.dario.flacplayer.audio

import android.content.Context
import android.media.AudioManager
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import com.dario.flacplayer.library.MusicLibrary
import com.dario.flacplayer.model.Track
import com.dario.flacplayer.model.kilohertz
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/**
 * Stato della riproduzione. [PlaybackQueue] decide l'ordine; il playlist di
 * ExoPlayer viene tenuto identico, così i passaggi tra brani restano senza pause
 * anche quando il brano parte dal blocco schermo.
 */
@OptIn(UnstableApi::class)
class AudioPlayer(private val context: Context, private val library: MusicLibrary) {
    private companion object {
        const val SESSION_KEY = "playback.session"
        const val MAX_FAILURES = 3
    }

    // L'uscita in float conserva i 24 bit fino al mixer di Android.
    val player: ExoPlayer = ExoPlayer.Builder(
        context,
        DefaultRenderersFactory(context).setEnableAudioFloatOutput(true),
    )
        .setAudioAttributes(
            AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(),
            /* handleAudioFocus = */ true,
        )
        .setHandleAudioBecomingNoisy(true)
        .setWakeMode(C.WAKE_MODE_LOCAL)
        .build()

    val equalizer = EqualizerController(library.database) { player.volume = it }

    val queue = MutableStateFlow(PlaybackQueue())
    val currentTrack = MutableStateFlow<Track?>(null)
    val isPlaying = MutableStateFlow(false)
    val positionMs = MutableStateFlow(0L)
    val durationMs = MutableStateFlow(0L)
    val error = MutableStateFlow<String?>(null)

    private var failures = 0
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    /** Frequenza nativa dell'uscita: Android ricampiona verso questo valore. */
    val outputDescription: String
        get() {
            val manager = context.getSystemService(AudioManager::class.java)
            val rate = manager.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull()
            return if (rate != null) "Uscita di sistema ${kilohertz(rate)} kHz" else "Uscita di sistema"
        }

    init {
        equalizer.attach(player.audioSessionId)
        player.addListener(object : Player.Listener {
            override fun onAudioSessionIdChanged(audioSessionId: Int) = equalizer.attach(audioSessionId)

            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                mediaItem?.let { queue.value = queue.value.at(it.mediaId) }
                refreshCurrent()
                saveSession()
            }

            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying.value = playing
                positionMs.value = player.currentPosition
                if (!playing) saveSession()
            }

            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_READY) {
                    failures = 0
                    if (player.duration != C.TIME_UNSET) durationMs.value = player.duration
                }
                if (state == Player.STATE_ENDED) {
                    // Fine coda: fermo all'inizio dell'ultimo brano.
                    player.pause()
                    player.seekToDefaultPosition()
                    positionMs.value = 0
                }
            }

            override fun onPlayerError(exception: PlaybackException) {
                val title = currentTrack.value?.title.orEmpty()
                error.value = "Impossibile riprodurre «$title». Il file è danneggiato o non più leggibile."
                failures++
                if (failures < minOf(queue.value.order.size, MAX_FAILURES) && player.hasNextMediaItem()) {
                    player.seekToNextMediaItem()
                    player.prepare()
                    player.play()
                } else {
                    failures = 0
                    player.pause()
                }
            }
        })
        scope.launch {
            while (isActive) {
                if (player.isPlaying) positionMs.value = player.currentPosition
                delay(250)
            }
        }
    }

    private fun refreshCurrent() {
        val track = queue.value.current?.let { library.track(it.trackId) }
        currentTrack.value = track
        durationMs.value = track?.durationMs ?: 0
        positionMs.value = player.currentPosition
    }

    private fun mediaItem(item: QueueItem): MediaItem? {
        val track = library.track(item.trackId) ?: return null
        val cover = track.coverId?.let { Uri.fromFile(File(library.coversDir, it)) }
        return MediaItem.Builder()
            .setMediaId(item.id)
            .setUri(Uri.fromFile(File(track.path)))
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(track.title)
                    .setArtist(track.artist)
                    .setAlbumTitle(track.album)
                    .setArtworkUri(cover)
                    .build(),
            )
            .build()
    }

    /** Porta il playlist del player a coincidere con la coda, senza interrompere il brano in corso. */
    private fun syncPlayer() {
        val target = queue.value.order
        val ids = target.map { it.id }.toSet()
        for (i in player.mediaItemCount - 1 downTo 0) {
            if (player.getMediaItemAt(i).mediaId !in ids) player.removeMediaItem(i)
        }
        target.forEachIndexed { index, item ->
            val found = (index until player.mediaItemCount).firstOrNull { player.getMediaItemAt(it).mediaId == item.id }
            when {
                found == null -> mediaItem(item)?.let { player.addMediaItem(index, it) }
                found != index -> player.moveMediaItem(found, index)
            }
        }
        if (player.mediaItemCount > 0 && player.playbackState == Player.STATE_IDLE) player.prepare()
        refreshCurrent()
        saveSession()
    }

    private fun startQueue(positionMs: Long = 0, autoplay: Boolean = true) {
        val value = queue.value
        player.setMediaItems(value.order.mapNotNull(::mediaItem), value.index, positionMs)
        player.repeatMode = value.repeat.toPlayer()
        player.prepare()
        player.playWhenReady = autoplay
        refreshCurrent()
        saveSession()
    }

    fun play(tracks: List<Track>, start: Int, source: String) {
        val selected = tracks.getOrNull(start) ?: return
        if (selected.isMissing) {
            error.value = "Il file di «${selected.title}» non è più presente sul dispositivo."
            return
        }
        val playable = tracks.filterNot { it.isMissing }
        queue.value = queue.value.load(playable.map { it.id }, playable.indexOf(selected), source)
        startQueue()
    }

    fun shufflePlay(tracks: List<Track>, source: String) {
        val playable = tracks.filterNot { it.isMissing }
        if (playable.isEmpty()) return
        queue.value = queue.value.copy(shuffled = true).load(playable.map { it.id }, playable.indices.random(), source)
        startQueue()
    }

    fun togglePlayPause() {
        if (player.isPlaying) {
            player.pause()
        } else {
            if (player.playbackState == Player.STATE_IDLE) player.prepare()
            player.play()
        }
    }

    fun next() {
        when {
            player.hasNextMediaItem() -> player.seekToNextMediaItem()
            queue.value.repeat != RepeatMode.OFF -> player.seekToDefaultPosition(0)
            else -> {
                player.pause()
                player.seekToDefaultPosition()
            }
        }
    }

    /** Oltre i 3 secondi riavvolge, altrimenti passa al brano precedente. */
    fun previous() = player.seekToPrevious()

    fun seekTo(position: Long) {
        player.seekTo(position)
        positionMs.value = position
        saveSession()
    }

    fun toggleShuffle() {
        queue.value = queue.value.withShuffle(!queue.value.shuffled)
        syncPlayer()
    }

    fun cycleRepeat() {
        queue.value = queue.value.copy(repeat = queue.value.repeat.next)
        player.repeatMode = queue.value.repeat.toPlayer()
        saveSession()
    }

    private fun RepeatMode.toPlayer() = when (this) {
        RepeatMode.OFF -> Player.REPEAT_MODE_OFF
        RepeatMode.ALL -> Player.REPEAT_MODE_ALL
        RepeatMode.ONE -> Player.REPEAT_MODE_ONE
    }

    fun addToQueue(tracks: List<Track>) = change { it.appended(tracks.filterNot(Track::isMissing).map(Track::id)) }

    fun playNext(tracks: List<Track>) = change { it.insertedNext(tracks.filterNot(Track::isMissing).map(Track::id)) }

    fun moveUpcoming(from: Int, to: Int) = change { it.movedUpcoming(from, to) }

    fun removeFromQueue(itemId: String) = change { it.without(itemId) }

    fun clearQueue() = change { it.clearedExceptCurrent() }

    private fun change(transform: (PlaybackQueue) -> PlaybackQueue) {
        queue.value = transform(queue.value)
        syncPlayer()
    }

    fun jump(itemId: String) {
        val index = queue.value.order.indexOfFirst { it.id == itemId }
        if (index < 0) return
        player.seekToDefaultPosition(index)
        player.play()
    }

    /** Toglie dalla coda i brani eliminati e aggiorna i metadati del brano corrente. */
    fun libraryChanged() {
        val unknown = queue.value.order.map { it.trackId }.filter { library.track(it) == null }.toSet()
        if (unknown.isNotEmpty()) queue.value = queue.value.withoutTracks(unknown)
        syncPlayer()
    }

    fun saveSession() {
        val value = queue.value
        fun items(list: List<QueueItem>) = JSONArray().apply {
            list.forEach { put(JSONObject().put("id", it.id).put("track", it.trackId)) }
        }
        val json = JSONObject()
            .put("source", value.source)
            .put("original", items(value.original))
            .put("order", items(value.order))
            .put("index", value.index)
            .put("shuffled", value.shuffled)
            .put("repeat", value.repeat.name)
            .put("position", player.currentPosition)
        library.database.setSetting(SESSION_KEY, json.toString())
    }

    /** Riprende coda e posizione senza far partire l'audio. */
    fun restoreSession() {
        val json = library.database.setting(SESSION_KEY)?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return
        fun items(name: String) = json.getJSONArray(name).let { array ->
            (0 until array.length()).map { array.getJSONObject(it) }.map { QueueItem(it.getString("id"), it.getString("track")) }
        }
        val saved = runCatching {
            PlaybackQueue(
                source = json.getString("source"),
                original = items("original"),
                order = items("order"),
                index = json.getInt("index"),
                shuffled = json.getBoolean("shuffled"),
                repeat = RepeatMode.valueOf(json.getString("repeat")),
            )
        }.getOrNull() ?: return
        val unknown = saved.order.map { it.trackId }.filter { library.track(it) == null }.toSet()
        queue.value = saved.withoutTracks(unknown)
        if (!queue.value.isEmpty) startQueue(json.optLong("position"), autoplay = false)
    }
}
