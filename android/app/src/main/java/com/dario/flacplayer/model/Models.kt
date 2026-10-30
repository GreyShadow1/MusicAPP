package com.dario.flacplayer.model

import java.util.Locale
import java.util.UUID

/** Brano della libreria. `id` non dipende dal percorso: sopravvive a spostamenti e rinomine. */
data class Track(
    val id: String = UUID.randomUUID().toString(),
    val contentHash: String,
    val path: String,
    val fileSize: Long,
    val modifiedAt: Long,
    val title: String,
    val artist: String,
    val album: String,
    val albumArtist: String,
    val genre: String,
    val date: String,
    val trackNumber: Int,
    val discNumber: Int,
    val durationMs: Long,
    val sampleRate: Int,
    val bitDepth: Int,
    val channels: Int,
    val coverId: String?,
    val isMissing: Boolean = false,
    val addedAt: Long = System.currentTimeMillis(),
) {
    val year: String get() = date.take(4)
    val quality: String get() = "$bitDepth bit · ${kilohertz(sampleRate)} kHz"
}

fun kilohertz(hertz: Int): String {
    val value = hertz / 1000.0
    return if (value % 1.0 == 0.0) value.toInt().toString()
    else String.format(Locale.ITALY, "%.1f", value)
}

data class Playlist(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val trackIds: List<String> = emptyList(),
    val createdAt: Long = System.currentTimeMillis(),
)

data class Album(
    val id: String,
    val title: String,
    val artist: String,
    val year: String,
    val coverId: String?,
    val tracks: List<Track>,
)

data class Artist(
    val name: String,
    val albums: List<Album>,
    val tracks: List<Track>,
) {
    val coverId: String? get() = albums.firstNotNullOfOrNull { it.coverId }
}

enum class TrackSort(val label: String) {
    TITLE("Titolo"), ARTIST("Artista"), ALBUM("Album");

    fun sorted(tracks: List<Track>): List<Track> = when (this) {
        TITLE -> tracks.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.title })
        ARTIST -> tracks.sortedWith(
            compareBy<Track, String>(String.CASE_INSENSITIVE_ORDER) { it.artist }.then(albumOrder),
        )
        ALBUM -> tracks.sortedWith(albumOrder)
    }
}

/** Ordine naturale: album, disco, traccia, titolo. */
val albumOrder: Comparator<Track> =
    compareBy<Track, String>(String.CASE_INSENSITIVE_ORDER) { it.album }
        .thenBy { it.discNumber }
        .thenBy { it.trackNumber }
        .thenBy(String.CASE_INSENSITIVE_ORDER) { it.title }

/** Raggruppa per (artista dell'album, titolo): album omonimi di artisti diversi restano separati. */
fun groupAlbums(tracks: List<Track>): List<Album> =
    tracks.groupBy { it.albumArtist + "\u001F" + it.album }
        .map { (key, members) ->
            val ordered = members.sortedWith(albumOrder)
            val first = ordered.first()
            Album(key, first.album, first.albumArtist, first.year, ordered.firstNotNullOfOrNull { it.coverId }, ordered)
        }
        .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.title })

fun groupArtists(tracks: List<Track>): List<Artist> =
    tracks.groupBy { it.albumArtist }
        .map { (name, members) -> Artist(name, groupAlbums(members), members.sortedWith(albumOrder)) }
        .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
