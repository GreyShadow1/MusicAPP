import SwiftUI

/// Avanzamento di un lavoro in background.
struct LibraryProgress: Equatable {
    let title: String
    let completed: Int
    let total: Int
}

/// Libreria e playlist visibili all'interfaccia. I lavori lunghi girano fuori dal
/// main thread e in sequenza, così importazione e scansione non si sovrappongono.
@MainActor
final class MusicLibraryManager: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var progress: LibraryProgress?
    @Published private(set) var lastResult: String?
    @Published var errorMessage: String?

    /// Chiamato dopo ogni cambiamento dei brani.
    var onTracksChanged: (() -> Void)?

    private(set) var tracksByID: [UUID: Track] = [:]
    private var sortedCache: [TrackSortOrder: [Track]] = [:]
    private var albumsCache: [Album]?
    private var artistsCache: [Artist]?

    private let paths: AppPaths
    private let persistence: PersistenceManager
    private var workTask: Task<Void, Never>?
    private var isWorking = false

    init(paths: AppPaths, persistence: PersistenceManager) {
        self.paths = paths
        self.persistence = persistence
    }

    // MARK: - Lettura

    func loadFromDisk() {
        do {
            setTracks(try persistence.allTracks())
            playlists = try persistence.allPlaylists()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setTracks(_ newTracks: [Track]) {
        tracks = newTracks
        tracksByID = Dictionary(newTracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        sortedCache = [:]
        albumsCache = nil
        artistsCache = nil
    }

    func sortedTracks(by order: TrackSortOrder) -> [Track] {
        if let cached = sortedCache[order] {
            return cached
        }
        let sorted = order.sorted(tracks)
        sortedCache[order] = sorted
        return sorted
    }

    var albums: [Album] {
        if let albumsCache {
            return albumsCache
        }
        let albums = Album.group(tracks)
        albumsCache = albums
        return albums
    }

    var artists: [Artist] {
        if let artistsCache {
            return artistsCache
        }
        let artists = Artist.group(tracks)
        artistsCache = artists
        return artists
    }

    func tracks(ids: [UUID]) -> [Track] {
        ids.compactMap { tracksByID[$0] }
    }

    // MARK: - Scansione e importazione

    /// Cerca i file copiati via USB. `silent` nasconde l'esito quando non è cambiato
    /// nulla: serve alla scansione automatica all'apertura dell'app.
    func rescan(silent: Bool) {
        let paths = self.paths
        let persistence = self.persistence
        runInBackground(
            title: String(localized: "Scansione della libreria"),
            work: { update -> ScanReport in
                try FileScanner(paths: paths, persistence: persistence).scan(progress: update)
            },
            completion: { [weak self] (report: ScanReport) in
                guard let self else { return }
                if !silent || report.hasChanges || !report.failed.isEmpty {
                    self.lastResult = Self.summary(of: report)
                }
            }
        )
    }

    func importItems(_ urls: [URL]) {
        // L'accesso va aperto qui, finché il permesso del selettore è valido.
        let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
        let paths = self.paths
        let persistence = self.persistence
        runInBackground(
            title: String(localized: "Importazione"),
            work: { update -> ImportReport in
                defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
                return FileImportManager(paths: paths, persistence: persistence).importItems(urls, progress: update)
            },
            completion: { [weak self] (report: ImportReport) in
                guard let self else { return }
                self.lastResult = Self.summary(of: report)
                if report.stoppedForLackOfSpace {
                    self.errorMessage = String(localized: "Importazione interrotta: spazio insufficiente sull'iPhone.")
                } else if !report.failures.isEmpty {
                    self.errorMessage = report.failures.prefix(5).joined(separator: "\n")
                }
            }
        )
    }

    private func runInBackground<Report: Sendable>(
        title: String,
        work: @escaping @Sendable (@escaping (Int, Int) -> Void) throws -> Report,
        completion: @escaping (Report) -> Void
    ) {
        let previous = workTask
        workTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }

            self.isWorking = true
            self.progress = LibraryProgress(title: title, completed: 0, total: 0)

            let update: @Sendable (Int, Int) -> Void = { [weak self] completed, total in
                DispatchQueue.main.async {
                    guard let self, self.isWorking else { return }
                    self.progress = LibraryProgress(title: title, completed: completed, total: total)
                }
            }
            let result: Result<Report, Error> = await Task.detached(priority: .utility) {
                Result(catching: { try work(update) })
            }.value

            self.isWorking = false
            self.progress = nil
            self.loadFromDisk()
            self.onTracksChanged?()

            switch result {
            case .success(let report):
                completion(report)
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private static func summary(of report: ScanReport) -> String {
        guard report.hasChanges || report.duplicates > 0 || !report.failed.isEmpty else {
            return String(localized: "Nessun nuovo brano trovato.")
        }
        var parts: [String] = []
        if report.added > 0 { parts.append(String(localized: "\(report.added) nuovi")) }
        if report.updated > 0 { parts.append(String(localized: "\(report.updated) aggiornati")) }
        if report.restored > 0 { parts.append(String(localized: "\(report.restored) ritrovati")) }
        if report.duplicates > 0 { parts.append(String(localized: "\(report.duplicates) duplicati ignorati")) }
        if report.newlyMissing > 0 { parts.append(String(localized: "\(report.newlyMissing) file mancanti")) }
        if !report.failed.isEmpty { parts.append(String(localized: "\(report.failed.count) file non validi")) }
        return parts.joined(separator: " · ")
    }

    private static func summary(of report: ImportReport) -> String {
        var parts = [String(localized: "\(report.imported) importati")]
        if report.duplicates > 0 { parts.append(String(localized: "\(report.duplicates) duplicati ignorati")) }
        if !report.failures.isEmpty { parts.append(String(localized: "\(report.failures.count) non riusciti")) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Eliminazione

    /// Cancella il file dal dispositivo e il brano da libreria, playlist e preferiti.
    func delete(_ track: Track) {
        do {
            let url = paths.fileURL(for: track)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try persistence.deleteTrack(id: track.id)
            loadFromDisk()
            onTracksChanged?()
        } catch {
            errorMessage = String(localized: "Impossibile eliminare «\(track.title)». \(error.localizedDescription)")
        }
    }

    // MARK: - Playlist

    @discardableResult
    func createPlaylist(name: String, trackIDs: [UUID] = []) -> Playlist? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let playlist = Playlist(name: trimmed, trackIDs: trackIDs)
        return save(playlist) ? playlist : nil
    }

    func rename(_ playlist: Playlist, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = playlist
        updated.name = trimmed
        save(updated)
    }

    func add(_ trackIDs: [UUID], to playlistID: UUID) {
        guard var playlist = findPlaylist(id: playlistID) else { return }
        playlist.trackIDs.append(contentsOf: trackIDs)
        save(playlist)
    }

    func removeTracks(at offsets: IndexSet, from playlistID: UUID) {
        guard var playlist = findPlaylist(id: playlistID) else { return }
        for offset in offsets.sorted(by: >) where playlist.trackIDs.indices.contains(offset) {
            playlist.trackIDs.remove(at: offset)
        }
        save(playlist)
    }

    func moveTracks(in playlistID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        guard var playlist = findPlaylist(id: playlistID) else { return }
        playlist.trackIDs.move(fromOffsets: source, toOffset: destination)
        save(playlist)
    }

    func delete(_ playlist: Playlist) {
        do {
            try persistence.deletePlaylist(id: playlist.id)
            playlists = try persistence.allPlaylists()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func findPlaylist(id: UUID) -> Playlist? {
        playlists.first { $0.id == id }
    }

    @discardableResult
    private func save(_ playlist: Playlist) -> Bool {
        do {
            try persistence.save(playlist)
            playlists = try persistence.allPlaylists()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
