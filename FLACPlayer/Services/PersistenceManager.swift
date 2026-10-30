import Foundation

/// File ignorato dalla scansione perché duplicato di un brano già in libreria.
struct IgnoredFile: Equatable {
    let fileSize: Int64
    let modifiedAt: TimeInterval
}

/// Archivio persistente su SQLite in modalità WAL: ogni scrittura è atomica e il
/// database resta integro anche se l'app viene chiusa all'improvviso.
///
/// Le eliminazioni si propagano con chiavi esterne: togliere un brano dalla
/// libreria lo toglie anche da playlist e preferiti, senza riferimenti orfani.
final class PersistenceManager: @unchecked Sendable {
    private static let schemaVersion: Int64 = 1
    private static let trackColumns = """
        id, content_hash, relative_path, file_size, modified_at, title, artist, album, \
        album_artist, genre, date, track_number, disc_number, duration, sample_rate, \
        bit_depth, channels, cover_id, is_missing, added_at
        """

    private let lock = NSLock()
    private let database: SQLiteDatabase

    /// Apre il database. Se è illeggibile lo mette da parte e ne crea uno nuovo:
    /// i brani si ricostruiscono dalla scansione dei file.
    init(url: URL) throws {
        do {
            database = try PersistenceManager.open(url: url)
        } catch {
            let corrupted = url.appendingPathExtension("corrupted")
            try? FileManager.default.removeItem(at: corrupted)
            try? FileManager.default.moveItem(at: url, to: corrupted)
            for suffix in ["-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
            database = try PersistenceManager.open(url: url)
        }
    }

    private static func open(url: URL) throws -> SQLiteDatabase {
        let database = try SQLiteDatabase(path: url.path)
        try database.execute("PRAGMA journal_mode = WAL")
        try database.execute("PRAGMA synchronous = NORMAL")
        try database.execute("PRAGMA foreign_keys = ON")

        let version = try database.query("PRAGMA user_version") { $0.integer(0) }.first ?? 0
        if version < schemaVersion {
            try migrate(database, from: version)
        }
        return database
    }

    private static func migrate(_ database: SQLiteDatabase, from version: Int64) throws {
        try database.transaction {
            if version < 1 {
                try database.execute("""
                    CREATE TABLE tracks (
                        id TEXT PRIMARY KEY NOT NULL,
                        content_hash TEXT NOT NULL UNIQUE,
                        relative_path TEXT NOT NULL UNIQUE,
                        file_size INTEGER NOT NULL,
                        modified_at REAL NOT NULL,
                        title TEXT NOT NULL,
                        artist TEXT NOT NULL,
                        album TEXT NOT NULL,
                        album_artist TEXT NOT NULL,
                        genre TEXT NOT NULL,
                        date TEXT NOT NULL,
                        track_number INTEGER NOT NULL,
                        disc_number INTEGER NOT NULL,
                        duration REAL NOT NULL,
                        sample_rate INTEGER NOT NULL,
                        bit_depth INTEGER NOT NULL,
                        channels INTEGER NOT NULL,
                        cover_id TEXT,
                        is_missing INTEGER NOT NULL DEFAULT 0,
                        added_at REAL NOT NULL
                    );
                    CREATE TABLE playlists (
                        id TEXT PRIMARY KEY NOT NULL,
                        name TEXT NOT NULL,
                        created_at REAL NOT NULL
                    );
                    CREATE TABLE playlist_items (
                        playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
                        position INTEGER NOT NULL,
                        track_id TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
                        PRIMARY KEY (playlist_id, position)
                    );
                    CREATE INDEX playlist_items_track ON playlist_items(track_id);
                    CREATE TABLE favorites (
                        track_id TEXT PRIMARY KEY NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
                        added_at REAL NOT NULL
                    );
                    CREATE TABLE ignored_files (
                        relative_path TEXT PRIMARY KEY NOT NULL,
                        file_size INTEGER NOT NULL,
                        modified_at REAL NOT NULL
                    );
                    CREATE TABLE settings (
                        key TEXT PRIMARY KEY NOT NULL,
                        value TEXT NOT NULL
                    );
                    """)
            }
            try database.execute("PRAGMA user_version = \(schemaVersion)")
        }
    }

    private func locked<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: - Brani

    func allTracks() throws -> [Track] {
        try locked {
            try database.query("SELECT \(Self.trackColumns) FROM tracks", map: Self.makeTrack)
        }
    }

    func track(withHash hash: String) throws -> Track? {
        try locked {
            try database.query(
                "SELECT \(Self.trackColumns) FROM tracks WHERE content_hash = ?",
                [.text(hash)],
                map: Self.makeTrack
            ).first
        }
    }

    func track(atPath relativePath: String) throws -> Track? {
        try locked {
            try database.query(
                "SELECT \(Self.trackColumns) FROM tracks WHERE relative_path = ?",
                [.text(relativePath)],
                map: Self.makeTrack
            ).first
        }
    }

    func insert(_ track: Track) throws {
        try locked {
            try database.run(
                "INSERT INTO tracks (\(Self.trackColumns)) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                Self.values(for: track)
            )
        }
    }

    /// Aggiorna i dati del brano mantenendo il suo identificativo.
    func update(_ track: Track) throws {
        try locked {
            var values = Self.values(for: track)
            values.removeFirst()
            values.append(.text(track.id.uuidString))
            try database.run("""
                UPDATE tracks SET content_hash = ?, relative_path = ?, file_size = ?, modified_at = ?,
                    title = ?, artist = ?, album = ?, album_artist = ?, genre = ?, date = ?,
                    track_number = ?, disc_number = ?, duration = ?, sample_rate = ?, bit_depth = ?,
                    channels = ?, cover_id = ?, is_missing = ?, added_at = ?
                WHERE id = ?
                """, values)
        }
    }

    func setMissing(_ missing: Bool, trackIDs: [UUID]) throws {
        guard !trackIDs.isEmpty else { return }
        try locked {
            try database.transaction {
                for id in trackIDs {
                    try database.run(
                        "UPDATE tracks SET is_missing = ? WHERE id = ?",
                        [.integer(missing ? 1 : 0), .text(id.uuidString)]
                    )
                }
            }
        }
    }

    func deleteTrack(id: UUID) throws {
        try locked {
            try database.run("DELETE FROM tracks WHERE id = ?", [.text(id.uuidString)])
        }
    }

    private static func values(for track: Track) -> [SQLiteValue] {
        [
            .text(track.id.uuidString),
            .text(track.contentHash),
            .text(track.relativePath),
            .integer(track.fileSize),
            .real(track.modifiedAt),
            .text(track.title),
            .text(track.artist),
            .text(track.album),
            .text(track.albumArtist),
            .text(track.genre),
            .text(track.date),
            .integer(Int64(track.trackNumber)),
            .integer(Int64(track.discNumber)),
            .real(track.duration),
            .integer(Int64(track.sampleRate)),
            .integer(Int64(track.bitDepth)),
            .integer(Int64(track.channels)),
            track.coverID.map(SQLiteValue.text) ?? .null,
            .integer(track.isMissing ? 1 : 0),
            .real(track.addedAt.timeIntervalSince1970)
        ]
    }

    private static func makeTrack(from row: SQLiteRow) -> Track {
        Track(
            id: UUID(uuidString: row.text(0)) ?? UUID(),
            contentHash: row.text(1),
            relativePath: row.text(2),
            fileSize: row.integer(3),
            modifiedAt: row.real(4),
            title: row.text(5),
            artist: row.text(6),
            album: row.text(7),
            albumArtist: row.text(8),
            genre: row.text(9),
            date: row.text(10),
            trackNumber: Int(row.integer(11)),
            discNumber: Int(row.integer(12)),
            duration: row.real(13),
            sampleRate: Int(row.integer(14)),
            bitDepth: Int(row.integer(15)),
            channels: Int(row.integer(16)),
            coverID: row.optionalText(17),
            isMissing: row.integer(18) != 0,
            addedAt: Date(timeIntervalSince1970: row.real(19))
        )
    }

    // MARK: - Playlist

    func allPlaylists() throws -> [Playlist] {
        try locked {
            let items = try database.query(
                "SELECT playlist_id, track_id FROM playlist_items ORDER BY playlist_id, position"
            ) { (row: SQLiteRow) in (row.text(0), row.text(1)) }

            var trackIDs: [String: [UUID]] = [:]
            for (playlistID, trackID) in items {
                if let id = UUID(uuidString: trackID) {
                    trackIDs[playlistID, default: []].append(id)
                }
            }
            return try database.query(
                "SELECT id, name, created_at FROM playlists ORDER BY name COLLATE NOCASE"
            ) { row in
                let id = row.text(0)
                return Playlist(
                    id: UUID(uuidString: id) ?? UUID(),
                    name: row.text(1),
                    trackIDs: trackIDs[id] ?? [],
                    createdAt: Date(timeIntervalSince1970: row.real(2))
                )
            }
        }
    }

    func save(_ playlist: Playlist) throws {
        try locked {
            try database.transaction {
                let id = playlist.id.uuidString
                try database.run(
                    "INSERT INTO playlists (id, name, created_at) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name",
                    [.text(id), .text(playlist.name), .real(playlist.createdAt.timeIntervalSince1970)]
                )
                try database.run("DELETE FROM playlist_items WHERE playlist_id = ?", [.text(id)])
                for (position, trackID) in playlist.trackIDs.enumerated() {
                    try database.run(
                        "INSERT INTO playlist_items (playlist_id, position, track_id) VALUES (?, ?, ?)",
                        [.text(id), .integer(Int64(position)), .text(trackID.uuidString)]
                    )
                }
            }
        }
    }

    func deletePlaylist(id: UUID) throws {
        try locked {
            try database.run("DELETE FROM playlists WHERE id = ?", [.text(id.uuidString)])
        }
    }

    // MARK: - Preferiti

    /// Identificativi dei preferiti, dal più recente.
    func favoriteIDs() throws -> [UUID] {
        try locked {
            try database.query("SELECT track_id FROM favorites ORDER BY added_at DESC") { $0.text(0) }
                .compactMap(UUID.init(uuidString:))
        }
    }

    func setFavorite(_ favorite: Bool, trackID: UUID) throws {
        try locked {
            if favorite {
                try database.run(
                    "INSERT OR IGNORE INTO favorites (track_id, added_at) VALUES (?, ?)",
                    [.text(trackID.uuidString), .real(Date().timeIntervalSince1970)]
                )
            } else {
                try database.run("DELETE FROM favorites WHERE track_id = ?", [.text(trackID.uuidString)])
            }
        }
    }

    // MARK: - File ignorati

    func ignoredFiles() throws -> [String: IgnoredFile] {
        try locked {
            let rows = try database.query("SELECT relative_path, file_size, modified_at FROM ignored_files") {
                (row: SQLiteRow) in (row.text(0), IgnoredFile(fileSize: row.integer(1), modifiedAt: row.real(2)))
            }
            return Dictionary(rows, uniquingKeysWith: { _, last in last })
        }
    }

    func setIgnored(relativePath: String, file: IgnoredFile) throws {
        try locked {
            try database.run(
                "INSERT OR REPLACE INTO ignored_files (relative_path, file_size, modified_at) VALUES (?, ?, ?)",
                [.text(relativePath), .integer(file.fileSize), .real(file.modifiedAt)]
            )
        }
    }

    func removeIgnored(relativePath: String) throws {
        try locked {
            try database.run("DELETE FROM ignored_files WHERE relative_path = ?", [.text(relativePath)])
        }
    }

    // MARK: - Impostazioni

    func setting(_ key: String) throws -> String? {
        try locked {
            try database.query("SELECT value FROM settings WHERE key = ?", [.text(key)]) { $0.text(0) }.first
        }
    }

    func setSetting(_ key: String, value: String) throws {
        try locked {
            try database.run(
                "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                [.text(key), .text(value)]
            )
        }
    }
}
