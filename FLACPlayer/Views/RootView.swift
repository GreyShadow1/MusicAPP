import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var favorites: FavoritesManager
    @EnvironmentObject var player: AudioPlayer

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            LibraryView()
                .miniPlayerInset()
                .tabItem { Label("Libreria", systemImage: "music.note.list") }
                .tag(AppState.Tab.library)

            PlaylistsView()
                .miniPlayerInset()
                .tabItem { Label("Playlist", systemImage: "music.note.house") }
                .tag(AppState.Tab.playlists)

            FavoritesView()
                .miniPlayerInset()
                .tabItem { Label("Preferiti", systemImage: "heart") }
                .tag(AppState.Tab.favorites)

            NowPlayingView()
                .tabItem { Label("In riproduzione", systemImage: "play.circle") }
                .tag(AppState.Tab.nowPlaying)
        }
        .errorAlert(activeError)
    }

    /// Un solo avviso alla volta: più modificatori `.alert` sulla stessa vista
    /// si escluderebbero a vicenda.
    private var activeError: Binding<String?> {
        Binding(
            get: {
                appState.startupError ?? library.errorMessage ?? player.errorMessage ?? favorites.errorMessage
            },
            set: { newValue in
                guard newValue == nil else { return }
                if appState.startupError != nil {
                    appState.startupError = nil
                } else if library.errorMessage != nil {
                    library.errorMessage = nil
                } else if player.errorMessage != nil {
                    player.errorMessage = nil
                } else {
                    favorites.errorMessage = nil
                }
            }
        )
    }
}

private extension View {
    func miniPlayerInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayerView()
        }
    }
}
