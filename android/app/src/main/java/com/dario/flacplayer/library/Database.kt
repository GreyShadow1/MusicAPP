package com.dario.flacplayer.library

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import com.dario.flacplayer.model.Playlist
import com.dario.flacplayer.model.Track

/**
 * Archivio SQLite in modalità WAL. Le chiavi esterne propagano le eliminazioni:
 * togliere un brano lo toglie anche da playlist e preferiti.
 */
class Database(context: Context) :
    SQLiteOpenHelper(context, "library.sqlite", null, 1), TrackStore {

    override fun onConfigure(db: SQLiteDatabase) {
        db.setForeignKeyConstraintsEnabled(true)
        db.enableWriteAheadLogging()
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """CREATE TABLE tracks (
                id TEXT PRIMARY KEY NOT NULL, content_hash TEXT NOT NULL UNIQUE,
                path TEXT NOT NULL UNIQUE, file_size INTEGER NOT NULL, modified_at INTEGER NOT NULL,
                title TEXT NOT NULL, artist TEXT NOT NULL, album TEXT NOT NULL,
                album_artist TEXT NOT NULL, genre TEXT NOT NULL, date TEXT NOT NULL,
                track_number INTEGER NOT NULL, disc_number INTEGER NOT NULL,
                duration_ms INTEGER NOT NULL, sample_rate INTEGER NOT NULL,
                bit_depth INTEGER NOT NULL, channels INTEGER NOT NULL, cover_id TEXT,
                is_missing INTEGER NOT NULL DEFAULT 0, added_at INTEGER NOT NULL)""",
        )
        db.execSQL("CREATE TABLE playlists (id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, created_at INTEGER NOT NULL)")
        db.execSQL(
            """CREATE TABLE playlist_items (
                playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
                position INTEGER NOT NULL,
                track_id TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
                PRIMARY KEY (playlist_id, position))""",
        )
        db.execSQL("CREATE INDEX playlist_items_track ON playlist_items(track_id)")
        db.execSQL(
            """CREATE TABLE favorites (
                track_id TEXT PRIMARY KEY NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
                added_at INTEGER NOT NULL)""",
        )
        db.execSQL(
            """CREATE TABLE ignored_files (
                path TEXT PRIMARY KEY NOT NULL, file_size INTEGER NOT NULL,
                modified_at INTEGER NOT NULL, by_user INTEGER NOT NULL)""",
        )
        db.execSQL("CREATE TABLE settings (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    // Brani

    override fun allTracks(): List<Track> =
        readableDatabase.rawQuery("SELECT * FROM tracks", null).use { it.tracks() }

    override fun trackWithHash(hash: String): Track? =
        readableDatabase.rawQuery("SELECT * FROM tracks WHERE content_hash = ?", arrayOf(hash))
            .use { it.tracks().firstOrNull() }

    override fun insert(track: Track) {
        writableDatabase.insertOrThrow("tracks", null, track.values())
    }

    override fun update(track: Track) {
        writableDatabase.update("tracks", track.values(), "id = ?", arrayOf(track.id))
    }

    override fun setMissing(missing: Boolean, ids: List<String>) {
        val values = ContentValues().apply { put("is_missing", if (missing) 1 else 0) }
        transaction { ids.forEach { update("tracks", values, "id = ?", arrayOf(it)) } }
    }

    fun deleteTrack(id: String) {
        writableDatabase.delete("tracks", "id = ?", arrayOf(id))
    }

    private fun Track.values() = ContentValues().apply {
        put("id", id); put("content_hash", contentHash); put("path", path)
        put("file_size", fileSize); put("modified_at", modifiedAt); put("title", title)
        put("artist", artist); put("album", album); put("album_artist", albumArtist)
        put("genre", genre); put("date", date); put("track_number", trackNumber)
        put("disc_number", discNumber); put("duration_ms", durationMs)
        put("sample_rate", sampleRate); put("bit_depth", bitDepth); put("channels", channels)
        put("cover_id", coverId); put("is_missing", if (isMissing) 1 else 0); put("added_at", addedAt)
    }

    private fun Cursor.tracks(): List<Track> {
        fun text(name: String) = getString(getColumnIndexOrThrow(name))
        fun long(name: String) = getLong(getColumnIndexOrThrow(name))
        val result = ArrayList<Track>(count)
        while (moveToNext()) {
            result += Track(
                id = text("id"), contentHash = text("content_hash"), path = text("path"),
                fileSize = long("file_size"), modifiedAt = long("modified_at"), title = text("title"),
                artist = text("artist"), album = text("album"), albumArtist = text("album_artist"),
                genre = text("genre"), date = text("date"), trackNumber = long("track_number").toInt(),
                discNumber = long("disc_number").toInt(), durationMs = long("duration_ms"),
                sampleRate = long("sample_rate").toInt(), bitDepth = long("bit_depth").toInt(),
                channels = long("channels").toInt(), coverId = text("cover_id"),
                isMissing = long("is_missing") != 0L, addedAt = long("added_at"),
            )
        }
        return result
    }

    // Playlist

    fun allPlaylists(): List<Playlist> {
        val items = HashMap<String, MutableList<String>>()
        readableDatabase.rawQuery("SELECT playlist_id, track_id FROM playlist_items ORDER BY playlist_id, position", null)
            .use { while (it.moveToNext()) items.getOrPut(it.getString(0)) { mutableListOf() } += it.getString(1) }
        return readableDatabase.rawQuery("SELECT id, name, created_at FROM playlists ORDER BY name COLLATE NOCASE", null).use {
            buildList {
                while (it.moveToNext()) {
                    val id = it.getString(0)
                    add(Playlist(id, it.getString(1), items[id].orEmpty(), it.getLong(2)))
                }
            }
        }
    }

    fun save(playlist: Playlist) = transaction {
        val values = ContentValues().apply {
            put("id", playlist.id); put("name", playlist.name); put("created_at", playlist.createdAt)
        }
        if (update("playlists", values, "id = ?", arrayOf(playlist.id)) == 0) {
            insertOrThrow("playlists", null, values)
        }
        delete("playlist_items", "playlist_id = ?", arrayOf(playlist.id))
        playlist.trackIds.forEachIndexed { position, trackId ->
            insertOrThrow("playlist_items", null, ContentValues().apply {
                put("playlist_id", playlist.id); put("position", position); put("track_id", trackId)
            })
        }
    }

    fun deletePlaylist(id: String) {
        writableDatabase.delete("playlists", "id = ?", arrayOf(id))
    }

    // Preferiti

    fun favoriteIds(): List<String> =
        readableDatabase.rawQuery("SELECT track_id FROM favorites ORDER BY added_at DESC", null).use {
            buildList { while (it.moveToNext()) add(it.getString(0)) }
        }

    fun setFavorite(favorite: Boolean, trackId: String) {
        if (favorite) {
            writableDatabase.insertWithOnConflict("favorites", null, ContentValues().apply {
                put("track_id", trackId); put("added_at", System.currentTimeMillis())
            }, SQLiteDatabase.CONFLICT_IGNORE)
        } else {
            writableDatabase.delete("favorites", "track_id = ?", arrayOf(trackId))
        }
    }

    // File ignorati

    override fun ignoredFiles(): Map<String, IgnoredFile> =
        readableDatabase.rawQuery("SELECT path, file_size, modified_at, by_user FROM ignored_files", null).use {
            buildMap {
                while (it.moveToNext()) put(it.getString(0), IgnoredFile(it.getLong(1), it.getLong(2), it.getInt(3) != 0))
            }
        }

    override fun setIgnored(path: String, file: IgnoredFile) {
        writableDatabase.insertWithOnConflict("ignored_files", null, ContentValues().apply {
            put("path", path); put("file_size", file.fileSize)
            put("modified_at", file.modifiedAt); put("by_user", if (file.byUser) 1 else 0)
        }, SQLiteDatabase.CONFLICT_REPLACE)
    }

    override fun removeIgnored(path: String) {
        writableDatabase.delete("ignored_files", "path = ?", arrayOf(path))
    }

    // Impostazioni

    fun setting(key: String): String? =
        readableDatabase.rawQuery("SELECT value FROM settings WHERE key = ?", arrayOf(key)).use {
            if (it.moveToFirst()) it.getString(0) else null
        }

    fun setSetting(key: String, value: String) {
        writableDatabase.insertWithOnConflict("settings", null, ContentValues().apply {
            put("key", key); put("value", value)
        }, SQLiteDatabase.CONFLICT_REPLACE)
    }

    private inline fun transaction(body: SQLiteDatabase.() -> Unit) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.body()
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }
}
