package com.dario.flacplayer.library

import android.content.ContentResolver
import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import androidx.documentfile.provider.DocumentFile
import com.dario.flacplayer.model.Album
import com.dario.flacplayer.model.Artist
import com.dario.flacplayer.model.Playlist
import com.dario.flacplayer.model.Track
import com.dario.flacplayer.model.groupAlbums
import com.dario.flacplayer.model.groupArtists
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class LibraryProgress(val title: String, val completed: Int, val total: Int)

/** Libreria, playlist e preferiti. I lavori lunghi girano in sequenza fuori dal thread principale. */
class MusicLibrary(private val context: Context, val database: Database) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val resolver: ContentResolver = context.contentResolver
    private val lastWork = AtomicReference<Job?>(null)

    /** Cartella privata in cui finiscono i brani importati. */
    val musicDir: File = (context.getExternalFilesDir(Environment.DIRECTORY_MUSIC) ?: File(context.filesDir, "Music"))
        .also { it.mkdirs() }
    val coversDir: File = File(context.filesDir, "covers").also { it.mkdirs() }

    val tracks = MutableStateFlow<List<Track>>(emptyList())
    val playlists = MutableStateFlow<List<Playlist>>(emptyList())
    val favorites = MutableStateFlow<List<String>>(emptyList())
    val progress = MutableStateFlow<LibraryProgress?>(null)
    val lastResult = MutableStateFlow<String?>(null)
    val error = MutableStateFlow<String?>(null)

    var onTracksChanged: () -> Unit = {}

    private val byId = MutableStateFlow<Map<String, Track>>(emptyMap())
    val tracksById: StateFlow<Map<String, Track>> = byId

    val albums: List<Album> get() = groupAlbums(tracks.value)
    val artists: List<Artist> get() = groupArtists(tracks.value)

    fun track(id: String): Track? = byId.value[id]

    fun tracks(ids: List<String>): List<Track> = ids.mapNotNull(byId.value::get)

    fun load() {
        val all = database.allTracks()
        tracks.value = all
        byId.value = all.associateBy { it.id }
        playlists.value = database.allPlaylists()
        favorites.value = database.favoriteIds()
    }

    private fun saveCover(bytes: ByteArray): String? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0) return null
        val id = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        val file = File(coversDir, id)
        if (!file.exists()) {
            val temporary = File(coversDir, "$id.tmp")
            temporary.writeBytes(bytes)
            temporary.renameTo(file)
        }
        return id
    }

    /** Tutti i FLAC: cartella dell'app e, con il permesso, il resto del telefono. */
    private fun findFiles(): List<ScannedFile> {
        val files = LinkedHashMap<String, ScannedFile>()
        musicDir.walkTopDown()
            .filter { it.isFile && it.extension.equals("flac", ignoreCase = true) }
            .forEach { files[it.path] = ScannedFile(it) }
        val columns = arrayOf(MediaStore.Audio.Media.DATA)
        val selection = "${MediaStore.Audio.Media.DATA} LIKE '%.flac' COLLATE NOCASE"
        runCatching {
            resolver.query(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, columns, selection, null, null)?.use { cursor ->
                while (cursor.moveToNext()) {
                    val file = File(cursor.getString(0))
                    if (file.isFile && file.canRead()) files[file.path] = ScannedFile(file)
                }
            }
        }
        return files.values.toList()
    }

    fun rescan(silent: Boolean) = runInBackground("Scansione della libreria") { update ->
        val report = FileScanner(database, ::saveCover).scan(findFiles(), update)
        report.summary().takeIf { !silent || report.hasChanges || report.failed.isNotEmpty() }
    }

    fun import(uris: List<Uri>, folder: Uri?) = runInBackground("Importazione") { update ->
        val sources = uris.mapNotNull { DocumentFile.fromSingleUri(context, it) } +
            (folder?.let { DocumentFile.fromTreeUri(context, it) }?.let(::flacFiles) ?: emptyList())
        var imported = 0
        var duplicates = 0
        val failures = ArrayList<String>()
        var noSpace = false
        for ((index, source) in sources.withIndex()) {
            update(index, sources.size)
            if (source.length() * 2 > musicDir.usableSpace) {
                noSpace = true
                break
            }
            try {
                if (importFile(source)) imported++ else duplicates++
            } catch (exception: Exception) {
                failures += "${source.name}: ${exception.message}"
            }
        }
        update(sources.size, sources.size)
        when {
            noSpace -> error.value = "Importazione interrotta: spazio insufficiente sul telefono."
            failures.isNotEmpty() -> error.value = failures.take(5).joinToString("\n")
        }
        listOfNotNull(
            "$imported importati",
            "$duplicates duplicati ignorati".takeIf { duplicates > 0 },
            "${failures.size} non riusciti".takeIf { failures.isNotEmpty() },
        ).joinToString(" · ")
    }

    private fun flacFiles(folder: DocumentFile): List<DocumentFile> = folder.listFiles().flatMap { item ->
        when {
            item.isDirectory -> flacFiles(item)
            item.name?.endsWith(".flac", ignoreCase = true) == true -> listOf(item)
            else -> emptyList()
        }
    }

    /** Copia in un file temporaneo, controlla, poi sposta: nessun file a metà. Restituisce false se duplicato. */
    private fun importFile(source: DocumentFile): Boolean {
        val temporary = File(context.cacheDir, UUID.randomUUID().toString() + ".flac")
        try {
            val input = resolver.openInputStream(source.uri) ?: throw FlacFormatException("File non leggibile.")
            input.use { stream -> temporary.outputStream().use(stream::copyTo) }

            val metadata = FlacMetadataReader.read(temporary)
            val hash = sha256(temporary)
            val existing = database.trackWithHash(hash)
            if (existing != null && File(existing.path).exists()) return false

            val folder = File(File(musicDir, sanitizedName(metadata.albumArtist)), sanitizedName(metadata.album))
            folder.mkdirs()
            val base = (if (metadata.trackNumber > 0) "%02d - ".format(metadata.trackNumber) else "") + sanitizedName(metadata.title)
            var target = File(folder, "$base.flac")
            var counter = 2
            while (target.exists()) target = File(folder, "$base ${counter++}.flac")
            // Cache e cartella musica possono stare su volumi diversi.
            if (!temporary.renameTo(target)) temporary.copyTo(target)

            val file = ScannedFile(target)
            if (existing != null) {
                database.update(existing.copy(path = file.path, fileSize = file.fileSize, modifiedAt = file.modifiedAt, isMissing = false))
            } else {
                database.insert(newTrack(metadata, file, hash, metadata.cover?.let(::saveCover)))
            }
            return true
        } finally {
            temporary.delete()
        }
    }

    private fun runInBackground(title: String, work: ((Int, Int) -> Unit) -> String?) {
        val previous = lastWork.get()
        val job = scope.launch {
            previous?.join()
            progress.value = LibraryProgress(title, 0, 0)
            val result = withContext(Dispatchers.IO) {
                runCatching { work { done, total -> progress.value = LibraryProgress(title, done, total) } }
            }
            progress.value = null
            load()
            onTracksChanged()
            result.onSuccess { if (it != null) lastResult.value = it }
                .onFailure { error.value = it.message ?: "Errore durante l'operazione." }
        }
        lastWork.set(job)
    }

    /**
     * I file importati si cancellano. Quelli copiati altrove restano sul telefono
     * ma escono dalla libreria: Android non consente di eliminarli senza chiedere.
     */
    fun remove(track: Track) {
        val file = File(track.path)
        if (file.startsWith(musicDir)) {
            file.delete()
        } else {
            database.setIgnored(track.path, IgnoredFile(track.fileSize, track.modifiedAt, byUser = true))
        }
        database.deleteTrack(track.id)
        load()
        onTracksChanged()
    }

    fun isInAppFolder(track: Track): Boolean = File(track.path).startsWith(musicDir)

    fun toggleFavorite(trackId: String) {
        database.setFavorite(trackId !in favorites.value, trackId)
        favorites.value = database.favoriteIds()
    }

    fun createPlaylist(name: String, trackIds: List<String> = emptyList()) {
        val trimmed = name.trim()
        if (trimmed.isNotEmpty()) save(Playlist(name = trimmed, trackIds = trackIds))
    }

    fun rename(playlist: Playlist, name: String) {
        if (name.isNotBlank()) save(playlist.copy(name = name.trim()))
    }

    fun add(trackIds: List<String>, playlistId: String) {
        playlist(playlistId)?.let { save(it.copy(trackIds = it.trackIds + trackIds)) }
    }

    fun removeTrackAt(index: Int, playlistId: String) {
        playlist(playlistId)?.let { save(it.copy(trackIds = it.trackIds.filterIndexed { i, _ -> i != index })) }
    }

    fun moveTrack(playlistId: String, from: Int, to: Int) {
        playlist(playlistId)?.let {
            val ids = it.trackIds.toMutableList()
            ids.add(to, ids.removeAt(from))
            save(it.copy(trackIds = ids))
        }
    }

    fun delete(playlist: Playlist) {
        database.deletePlaylist(playlist.id)
        playlists.value = database.allPlaylists()
    }

    fun playlist(id: String): Playlist? = playlists.value.firstOrNull { it.id == id }

    private fun save(playlist: Playlist) {
        database.save(playlist)
        playlists.value = database.allPlaylists()
    }
}
