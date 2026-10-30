import Foundation

/// Cartelle dell'app.
///
/// Documents è visibile da Windows tramite la condivisione file e contiene solo
/// musica. Il database e le copertine stanno in Application Support, dove
/// l'utente non può cancellarli per errore.
struct AppPaths {
    let documents: URL
    let music: URL
    let support: URL
    let covers: URL
    let database: URL

    init(documents: URL, support: URL) {
        self.documents = documents
        self.music = documents.appendingPathComponent("Music", isDirectory: true)
        self.support = support
        self.covers = support.appendingPathComponent("Covers", isDirectory: true)
        self.database = support.appendingPathComponent("library.sqlite")
    }

    static func live() -> AppPaths {
        let manager = FileManager.default
        let documents = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FLACPlayer", isDirectory: true)
        return AppPaths(documents: documents, support: support)
    }

    func prepare() throws {
        let manager = FileManager.default
        for directory in [documents, music, support, covers] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        Self.excludeFromBackup(music)
    }

    func fileURL(for track: Track) -> URL {
        documents.appendingPathComponent(track.relativePath, isDirectory: false)
    }

    /// La musica può pesare decine di GB e gli originali sono sul PC: senza questa
    /// esclusione finirebbe nel backup di iCloud.
    static func excludeFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }
}
