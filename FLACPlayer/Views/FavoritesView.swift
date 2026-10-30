import SwiftUI

struct FavoritesView: View {
    var body: some View {
        NavigationStack {
            FavoritesListView()
        }
    }
}

/// Playlist automatica "PREFERITI": riflette sempre l'elenco dei preferiti e non
/// si modifica a mano. Un brano si toglie solo dal suo cuore.
struct FavoritesListView: View {
    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var favorites: FavoritesManager
    @EnvironmentObject var player: AudioPlayer

    var body: some View {
        let tracks = library.tracks(ids: favorites.orderedIDs)
        Group {
            if tracks.isEmpty {
                EmptyStateView(
                    systemImage: "heart",
                    title: "Nessun preferito",
                    message: "Tocca il cuore accanto a un brano per aggiungerlo qui."
                )
            } else {
                List {
                    PlayActionsHeader(
                        onPlay: { player.play(tracks: tracks, startAt: 0, source: .favorites) },
                        onShuffle: { player.shufflePlay(tracks: tracks, source: .favorites) }
                    )
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(track: track) {
                            player.play(tracks: tracks, startAt: index, source: .favorites)
                        }
                    }
                }
                .flacListStyle()
            }
        }
        .navigationTitle("PREFERITI")
    }
}
