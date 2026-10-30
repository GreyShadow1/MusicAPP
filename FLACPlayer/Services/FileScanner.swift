import Foundation

/// File musicale trovato sul disco, con percorso relativo a Documents.
struct ScannedFile: Equatable {
    let relativePath: String
    let url: URL
    let fileSize: Int64
    let modifiedAt: TimeInterval
}

struct ScanReport: Equatable {
    var added = 0
    var updated = 0
    var duplicates = 0
    var failed: [String] = []
    var newlyMissing = 0
    var restored = 0

    var hasChanges: Bool {
        added > 0 || updated > 0 || newlyMissing > 0 || restored > 0
    }
}

/// Allinea la libreria al contenuto di Documents.
///
/// Controlla tutta la cartella, non solo Documents/Music: da Windows i file
/// trascinati in Dispositivi Apple finiscono nella radice di Documents. I file
/// già noti con stessa dimensione e data non vengono riletti, così una scansione
/// senza novità dura pochi istanti anche con migliaia di brani.
struct FileScanner {
    let paths: AppPaths
    let persistence: PersistenceManager
    let metadataReader = MetadataReader()

    func scan(progress: (Int, Int) -> Void) throws -> ScanReport {
        let files = Self.findFLACFiles(in: paths.documents)
        let tracks = try persistence.allTracks()
        var known = Dictionary(tracks.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })

        // Se manca un brano, un suo duplicato ignorato può prenderne il posto:
        // in quel caso i file ignorati vanno ricontrollati.
        let foundPaths = Set(files.map(.relativePath))
        let someFileIsGone = tracks.contains { !foundPaths.contains($0.relativePath) }
        let ignored: [String: IgnoredFile] = try someFileIsGone ? [:] : persistence.ignoredFiles()

        var report = ScanReport()
        var seenIDs = Set<UUID>()

        for (index, file) in files.enumerated() {
            progress(index, files.count)
            if let track = known[file.relativePath], Self.isUnchanged(file, track) {
                seenIDs.insert(track.id)
                continue
            }
            if let entry = ignored[file.relativePath],
               entry.fileSize == file.fileSize, abs(entry.modifiedAt - file.modifiedAt) < 1 {
                continue
            }
            do {
                try autoreleasepool {
                    try process(file, known: &known, seenIDs: &seenIDs, report: &report)
                }
            } catch {
                report.failed.append(file.url.lastPathComponent)
            }
        }
        progress(files.count, files.count)

        try reconcileMissing(seenIDs: seenIDs, report: &report)
        return report
    }

    private func process(
        _ file: ScannedFile,
        known: inout [String: Track],
        seenIDs: inout Set<UUID>,
        report: inout ScanReport
    ) throws {
        // I metadati si leggono prima dell'hash: un file illeggibile, per esempio
        // ancora in copia via USB, viene scartato subito e ritentato alla prossima scansione.
        let metadata = try metadataReader.read(url: file.url)
        let hash = try FileHasher.sha256(of: file.url)
        AppPaths.excludeFromBackup(file.url)

        if let existing = try persistence.track(withHash: hash) {
            let previousFile = paths.fileURL(for: existing)
            if existing.relativePath != file.relativePath,
               FileManager.default.fileExists(atPath: previousFile.path) {
                // Stesso contenuto di un brano ancora presente: è un duplicato.
                // Il file non viene cancellato, ma non entra in libreria.
                try persistence.setIgnored(
                    relativePath: file.relativePath,
                    file: IgnoredFile(fileSize: file.fileSize, modifiedAt: file.modifiedAt)
                )
                report.duplicates += 1
                return
            }
            // File spostato o rinominato: l'identificativo resta, così playlist e
            // preferiti continuano a funzionare.
            var moved = existing
            moved.relativePath = file.relativePath
            moved.fileSize = file.fileSize
            moved.modifiedAt = file.modifiedAt
            moved.isMissing = false
            try persistence.update(moved)
            known[existing.relativePath] = nil
            known[file.relativePath] = moved
            seenIDs.insert(moved.id)
            report.updated += 1
            return
        }

        let coverID = metadata.coverData.flatMap(CoverStore(paths: paths).save)
        if let replaced = known[file.relativePath] {
            // Stesso percorso, contenuto nuovo: tag modificati sul PC e file ricopiato.
            let updated = Track(
                id: replaced.id,
                metadata: metadata,
                file: file,
                contentHash: hash,
                coverID: coverID,
                addedAt: replaced.addedAt
            )
            try persistence.update(updated)
            known[file.relativePath] = updated
            seenIDs.insert(updated.id)
            report.updated += 1
        } else {
            let track = Track(metadata: metadata, file: file, contentHash: hash, coverID: coverID)
            try persistence.insert(track)
            known[file.relativePath] = track
            seenIDs.insert(track.id)
            report.added += 1
        }
        try persistence.removeIgnored(relativePath: file.relativePath)
    }

    /// I brani spariti restano in libreria come mancanti: se il file ricompare,
    /// anche con un altro nome, ritornano con playlist e preferiti intatti.
    private func reconcileMissing(seenIDs: Set<UUID>, report: inout ScanReport) throws {
        let tracks = try persistence.allTracks()
        let nowMissing = tracks.filter { !$0.isMissing && !seenIDs.contains($0.id) }
        let nowPresent = tracks.filter { $0.isMissing && seenIDs.contains($0.id) }
        try persistence.setMissing(true, trackIDs: nowMissing.map(\.id))
        try persistence.setMissing(false, trackIDs: nowPresent.map(\.id))
        report.newlyMissing = nowMissing.count
        report.restored = nowPresent.count
    }

    private static func isUnchanged(_ file: ScannedFile, _ track: Track) -> Bool {
        track.fileSize == file.fileSize && abs(track.modifiedAt - file.modifiedAt) < 1
    }

    /// Elenca ricorsivamente i `.flac`. "Inbox" è la cartella di sistema dei file
    /// ricevuti da altre app.
    static func findFLACFiles(in root: URL) -> [ScannedFile] {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let resolvedRoot = root.resolvingSymlinksInPath()
        let prefix = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"

        guard let enumerator = manager.enumerator(
            at: resolvedRoot,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [ScannedFile] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent == "Inbox" {
                enumerator.skipDescendants()
                continue
            }
            guard url.pathExtension.lowercased() == "flac" else { continue }
            guard
                let values = try? url.resourceValues(forKeys: Set(keys)),
                values.isRegularFile == true
            else { continue }

            let path = url.resolvingSymlinksInPath().path
            guard path.hasPrefix(prefix) else { continue }
            files.append(ScannedFile(
                relativePath: String(path.dropFirst(prefix.count)),
                url: url,
                fileSize: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate?.timeIntervalSince1970 ?? 0
            ))
        }
        return files
    }
}
