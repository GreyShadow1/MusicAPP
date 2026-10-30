import SwiftUI

/// Costruisce i servizi dell'app e li collega tra loro.
@MainActor
final class AppState: ObservableObject {
    enum Tab: Hashable {
        case library
        case playlists
        case favorites
        case nowPlaying
    }

    @Published var selectedTab: Tab = .library
    @Published var startupError: String?

    let paths: AppPaths
    let library: MusicLibraryManager
    let favorites: FavoritesManager
    let player: AudioPlayer
    let coverLoader: CoverImageLoader

    private var didLoad = false

    init() {
        let paths = AppPaths.live()
        var startupError: String?
        do {
            try paths.prepare()
        } catch {
            startupError = String(localized: "Impossibile preparare le cartelle dell'app. \(error.localizedDescription)")
        }

        let persistence: PersistenceManager
        do {
            persistence = try PersistenceManager(url: paths.database)
        } catch {
            // Senza database l'app funziona comunque per questa sessione.
            startupError = String(localized: "Impossibile aprire il database: le modifiche non verranno salvate. \(error.localizedDescription)")
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
            guard let fallback = try? PersistenceManager(url: temporary) else {
                fatalError("SQLite non è disponibile: \(error)")
            }
            persistence = fallback
        }

        let library = MusicLibraryManager(paths: paths, persistence: persistence)
        let favorites = FavoritesManager(persistence: persistence)
        let session = AudioSessionManager()
        let player = AudioPlayer(
            engine: AudioEngineManager(session: session),
            session: session,
            nowPlaying: NowPlayingManager(),
            persistence: persistence,
            paths: paths,
            trackLookup: { [weak library] id in library?.tracksByID[id] }
        )

        self.paths = paths
        self.library = library
        self.favorites = favorites
        self.player = player
        self.coverLoader = CoverImageLoader(paths: paths)
        self.startupError = startupError

        library.onTracksChanged = { [weak player, weak favorites] in
            favorites?.reload()
            player?.libraryDidChange()
        }
    }

    /// Carica i dati salvati e cerca i file copiati via USB a app chiusa.
    func start() {
        guard !didLoad else { return }
        didLoad = true
        library.loadFromDisk()
        favorites.reload()
        player.restoreSession()
        library.rescan(silent: true)
    }

    func sceneDidChange(to phase: ScenePhase) {
        switch phase {
        case .active:
            if didLoad {
                library.rescan(silent: true)
            }
        case .background:
            player.saveSession()
        default:
            break
        }
    }
}
