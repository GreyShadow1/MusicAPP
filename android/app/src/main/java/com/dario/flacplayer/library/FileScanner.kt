package com.dario.flacplayer.library

import com.dario.flacplayer.model.Track
import java.io.File
import java.security.MessageDigest

data class ScannedFile(val path: String, val fileSize: Long, val modifiedAt: Long) {
    constructor(file: File) : this(file.path, file.length(), file.lastModified())
}

/** File da non considerare: duplicato automatico, oppure tolto a mano dalla libreria. */
data class IgnoredFile(val fileSize: Long, val modifiedAt: Long, val byUser: Boolean)

data class ScanReport(
    val added: Int = 0,
    val updated: Int = 0,
    val duplicates: Int = 0,
    val failed: List<String> = emptyList(),
    val newlyMissing: Int = 0,
    val restored: Int = 0,
) {
    val hasChanges: Boolean get() = added > 0 || updated > 0 || newlyMissing > 0 || restored > 0

    fun summary(): String {
        if (!hasChanges && duplicates == 0 && failed.isEmpty()) return "Nessun nuovo brano trovato."
        return listOfNotNull(
            "$added nuovi".takeIf { added > 0 },
            "$updated aggiornati".takeIf { updated > 0 },
            "$restored ritrovati".takeIf { restored > 0 },
            "$duplicates duplicati ignorati".takeIf { duplicates > 0 },
            "$newlyMissing file mancanti".takeIf { newlyMissing > 0 },
            "${failed.size} file non validi".takeIf { failed.isNotEmpty() },
        ).joinToString(" · ")
    }
}

/** Parte dell'archivio usata da scansione e importazione. */
interface TrackStore {
    fun allTracks(): List<Track>
    fun trackWithHash(hash: String): Track?
    fun insert(track: Track)
    fun update(track: Track)
    fun setMissing(missing: Boolean, ids: List<String>)
    fun ignoredFiles(): Map<String, IgnoredFile>
    fun setIgnored(path: String, file: IgnoredFile)
    fun removeIgnored(path: String)
}

fun sha256(file: File): String {
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().use { input ->
        val buffer = ByteArray(1 shl 20)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            digest.update(buffer, 0, count)
        }
    }
    return digest.digest().joinToString("") { "%02x".format(it) }
}

fun newTrack(
    metadata: FlacMetadata,
    file: ScannedFile,
    hash: String,
    coverId: String?,
) = Track(
    contentHash = hash,
    path = file.path,
    fileSize = file.fileSize,
    modifiedAt = file.modifiedAt,
    title = metadata.title,
    artist = metadata.artist,
    album = metadata.album,
    albumArtist = metadata.albumArtist,
    genre = metadata.genre,
    date = metadata.date,
    trackNumber = metadata.trackNumber,
    discNumber = metadata.discNumber,
    durationMs = metadata.durationMs,
    sampleRate = metadata.sampleRate,
    bitDepth = metadata.bitDepth,
    channels = metadata.channels,
    coverId = coverId,
)

/** Allinea la libreria ai file presenti. I file già noti non vengono riletti. */
class FileScanner(
    private val store: TrackStore,
    private val saveCover: (ByteArray) -> String?,
) {
    fun scan(files: List<ScannedFile>, progress: (Int, Int) -> Unit = { _, _ -> }): ScanReport {
        val tracks = store.allTracks()
        val known = tracks.associateBy { it.path }.toMutableMap()
        val found = files.map { it.path }.toSet()
        // Se manca un brano, un suo duplicato ignorato può prenderne il posto.
        val someFileIsGone = tracks.any { it.path !in found }
        val ignored = store.ignoredFiles()
        val seen = HashSet<String>()
        var report = ScanReport()

        files.forEachIndexed { index, file ->
            progress(index, files.size)
            val track = known[file.path]
            val entry = ignored[file.path]
            when {
                track != null && unchanged(file, track) -> seen += track.id
                entry != null && entry.byUser -> Unit
                entry != null && !someFileIsGone && entry.fileSize == file.fileSize &&
                    entry.modifiedAt == file.modifiedAt -> Unit
                else -> try {
                    report = process(file, known, seen, report)
                } catch (_: Exception) {
                    report = report.copy(failed = report.failed + File(file.path).name)
                }
            }
        }
        progress(files.size, files.size)

        val current = store.allTracks()
        val nowMissing = current.filter { !it.isMissing && it.id !in seen }
        val nowPresent = current.filter { it.isMissing && it.id in seen }
        store.setMissing(true, nowMissing.map { it.id })
        store.setMissing(false, nowPresent.map { it.id })
        return report.copy(newlyMissing = nowMissing.size, restored = nowPresent.size)
    }

    private fun process(
        file: ScannedFile,
        known: MutableMap<String, Track>,
        seen: MutableSet<String>,
        report: ScanReport,
    ): ScanReport {
        // Prima i metadati: un file illeggibile si scarta senza calcolare l'hash.
        val metadata = FlacMetadataReader.read(File(file.path))
        val hash = sha256(File(file.path))
        val existing = store.trackWithHash(hash)

        if (existing != null) {
            if (existing.path != file.path && File(existing.path).exists()) {
                store.setIgnored(file.path, IgnoredFile(file.fileSize, file.modifiedAt, byUser = false))
                return report.copy(duplicates = report.duplicates + 1)
            }
            // Spostato o rinominato: l'identificativo resta.
            val moved = existing.copy(
                path = file.path,
                fileSize = file.fileSize,
                modifiedAt = file.modifiedAt,
                isMissing = false,
            )
            store.update(moved)
            known.remove(existing.path)
            known[file.path] = moved
            seen += moved.id
            return report.copy(updated = report.updated + 1)
        }

        val coverId = metadata.cover?.let(saveCover)
        val replaced = known[file.path]
        val result = if (replaced != null) {
            val updated = newTrack(metadata, file, hash, coverId).copy(id = replaced.id, addedAt = replaced.addedAt)
            store.update(updated)
            seen += updated.id
            known[file.path] = updated
            report.copy(updated = report.updated + 1)
        } else {
            val track = newTrack(metadata, file, hash, coverId)
            store.insert(track)
            seen += track.id
            known[file.path] = track
            report.copy(added = report.added + 1)
        }
        store.removeIgnored(file.path)
        return result
    }

    private fun unchanged(file: ScannedFile, track: Track) =
        track.fileSize == file.fileSize && track.modifiedAt == file.modifiedAt
}

/** Rende un tag utilizzabile come nome di file o cartella. */
fun sanitizedName(name: String): String {
    val cleaned = name.replace(Regex("[/\\\\:?%*|\"<>\\p{Cntrl}]"), " ").trim { it.isWhitespace() || it == '.' }
    return cleaned.take(100).ifEmpty { "Sconosciuto" }
}
