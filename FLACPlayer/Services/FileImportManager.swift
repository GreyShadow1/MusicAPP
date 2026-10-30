import Foundation

enum ImportError: LocalizedError {
    case insufficientSpace

    var errorDescription: String? {
        switch self {
        case .insufficientSpace:
            return String(localized: "Spazio insufficiente sull'iPhone.")
        }
    }
}

struct ImportReport: Equatable {
    var imported = 0
    var duplicates = 0
    var failures: [String] = []
    var stoppedForLackOfSpace = false
}

/// Importazione dal selettore di File. Ogni file viene copiato in una cartella
/// temporanea, controllato e solo allora spostato nella libreria: un'interruzione
/// non lascia file a metà e gli originali non vengono mai toccati.
struct FileImportManager {
    let paths: AppPaths
    let persistence: PersistenceManager
    let metadataReader = MetadataReader()

    /// `urls` può contenere file e cartelle. L'accesso security-scoped deve essere
    /// già attivo: lo gestisce `MusicLibraryManager`, perché va aperto subito nel
    /// callback del selettore e mantenuto per tutta la durata del lavoro.
    func importItems(_ urls: [URL], progress: (Int, Int) -> Void) -> ImportReport {
        let sources = urls.flatMap(Self.expand)
        var report = ImportReport()

        for (index, source) in sources.enumerated() {
            progress(index, sources.count)
            do {
                try autoreleasepool {
                    try importFile(source, report: &report)
                }
            } catch ImportError.insufficientSpace {
                report.stoppedForLackOfSpace = true
                break
            } catch {
                report.failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        progress(sources.count, sources.count)
        return report
    }

    /// Una cartella selezionata diventa l'elenco dei suoi FLAC.
    private static func expand(_ url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return [url]
        }
        if isDirectory.boolValue {
            return FileScanner.findFLACFiles(in: url).map(\.url)
        }
        return url.pathExtension.lowercased() == "flac" ? [url] : []
    }

    private func importFile(_ source: URL, report: inout ImportReport) throws {
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".flac")
        defer { try? manager.removeItem(at: temporary) }

        try copyCoordinated(source, to: temporary)

        let metadata = try metadataReader.read(url: temporary)
        // Apre il decoder sul file: scarta subito ciò che non si può riprodurre.
        _ = try FLACDecoder(url: temporary)
        let hash = try FileHasher.sha256(of: temporary)

        if let existing = try persistence.track(withHash: hash) {
            if manager.fileExists(atPath: paths.fileURL(for: existing).path) {
                report.duplicates += 1
                return
            }
            // Era mancante: si ricollega al brano originale con il suo identificativo.
            let file = try moveIntoLibrary(temporary, metadata: metadata)
            var restored = existing
            restored.relativePath = file.relativePath
            restored.fileSize = file.fileSize
            restored.modifiedAt = file.modifiedAt
            restored.isMissing = false
            try persistence.update(restored)
            report.imported += 1
            return
        }

        let file = try moveIntoLibrary(temporary, metadata: metadata)
        let coverID = metadata.coverData.flatMap(CoverStore(paths: paths).save)
        do {
            try persistence.insert(Track(metadata: metadata, file: file, contentHash: hash, coverID: coverID))
        } catch {
            try? manager.removeItem(at: file.url)
            throw error
        }
        report.imported += 1
    }

    /// Il coordinatore attende il download dei file che si trovano solo su iCloud.
    private func copyCoordinated(_ source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [.withoutChanges], error: &coordinationError) { url in
            do {
                try ensureSpace(for: url)
                try FileManager.default.copyItem(at: url, to: destination)
            } catch {
                copyError = error
            }
        }
        if let copyError {
            throw copyError
        }
        if let coordinationError {
            throw coordinationError
        }
    }

    private func ensureSpace(for url: URL) throws {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let values = try? paths.documents.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values?.volumeAvailableCapacityForImportantUsage, available < Int64(size) * 2 {
            throw ImportError.insufficientSpace
        }
    }

    private func moveIntoLibrary(_ temporary: URL, metadata: TrackMetadata) throws -> ScannedFile {
        let manager = FileManager.default
        let folder = paths.music
            .appendingPathComponent(Self.sanitized(metadata.albumArtist), isDirectory: true)
            .appendingPathComponent(Self.sanitized(metadata.album), isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)

        let destination = Self.availableURL(in: folder, baseName: Self.fileName(for: metadata))
        try manager.moveItem(at: temporary, to: destination)
        AppPaths.excludeFromBackup(destination)

        let values = try destination.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return ScannedFile(
            relativePath: Self.relativePath(of: destination, in: paths.documents),
            url: destination,
            fileSize: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate?.timeIntervalSince1970 ?? 0
        )
    }

    private static func relativePath(of url: URL, in root: URL) -> String {
        let rootPath = root.resolvingSymlinksInPath().path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return String(url.resolvingSymlinksInPath().path.dropFirst(prefix.count))
    }

    /// Es. "03 - Titolo".
    private static func fileName(for metadata: TrackMetadata) -> String {
        let title = sanitized(metadata.title)
        guard metadata.trackNumber > 0 else { return title }
        return String(format: "%02d - ", metadata.trackNumber) + title
    }

    private static func availableURL(in folder: URL, baseName: String) -> URL {
        var candidate = folder.appendingPathComponent(baseName + ".flac")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(baseName) \(counter).flac")
            counter += 1
        }
        return candidate
    }

    /// Rende un tag utilizzabile come nome di file o cartella.
    static func sanitized(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters)
        let cleaned = name.components(separatedBy: invalid).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let limited = String(cleaned.prefix(100))
        return limited.isEmpty ? "Sconosciuto" : limited
    }
}
