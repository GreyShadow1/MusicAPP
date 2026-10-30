import SwiftUI

struct ArtistsView: View {
    let searchText: String

    @EnvironmentObject var library: MusicLibraryManager

    private var artists: [Artist] {
        guard !searchText.isEmpty else { return library.artists }
        return library.artists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List(artists) { artist in
            NavigationLink {
                ArtistDetailView(artist: artist)
            } label: {
                HStack(spacing: 12) {
                    CoverArtView(coverID: artist.coverID, side: 44, cornerRadius: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(artist.name)
                            .lineLimit(1)
                        Text("\(artist.albums.count) album · \(artist.tracks.count) brani")
                            .font(.caption)
                            .foregroundColor(Theme.secondaryText)
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Theme.separator)
        }
        .flacListStyle()
    }
}

struct ArtistDetailView: View {
    let artist: Artist

    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var player: AudioPlayer

    private var currentTracks: [Track] {
        artist.tracks.compactMap { library.tracksByID[$0.id] }
    }

    var body: some View {
        let tracks = currentTracks
        let source = QueueSource.artist(name: artist.name)
        List {
            PlayActionsHeader(
                onPlay: { player.play(tracks: tracks, startAt: 0, source: source) },
                onShuffle: { player.shufflePlay(tracks: tracks, source: source) }
            )
            ForEach(artist.albums) { album in
                NavigationLink {
                    AlbumDetailView(album: album)
                } label: {
                    HStack(spacing: 12) {
                        CoverArtView(coverID: album.coverID, side: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(album.title)
                                .lineLimit(1)
                            Text(album.year)
                                .font(.caption)
                                .foregroundColor(Theme.secondaryText)
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Theme.separator)
            }
        }
        .flacListStyle()
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
