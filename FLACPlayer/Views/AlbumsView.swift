import SwiftUI

struct AlbumsView: View {
    let searchText: String

    @EnvironmentObject var library: MusicLibraryManager

    private static let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    private var albums: [Album] {
        guard !searchText.isEmpty else { return library.albums }
        return library.albums.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.artist.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let side = max((geometry.size.width - 48) / 2, 1)
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 20) {
                    ForEach(albums) { album in
                        NavigationLink {
                            AlbumDetailView(album: album)
                        } label: {
                            AlbumCell(album: album, side: side)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.background)
    }
}

private struct AlbumCell: View {
    let album: Album
    let side: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CoverArtView(coverID: album.coverID, side: side, cornerRadius: 8)
            Text(album.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text(album.artist)
                .font(.caption)
                .foregroundColor(Theme.secondaryText)
                .lineLimit(1)
        }
    }
}

struct AlbumDetailView: View {
    let album: Album

    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var player: AudioPlayer

    /// Rilegge i brani dalla libreria, così una cancellazione si vede subito.
    private var currentTracks: [Track] {
        album.tracks.compactMap { library.tracksByID[$0.id] }
    }

    var body: some View {
        let tracks = currentTracks
        let source = QueueSource.album(title: album.title)
        List {
            VStack(spacing: 6) {
                CoverArtView(coverID: album.coverID, side: 220, cornerRadius: 10)
                Text(album.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(album.year.isEmpty ? album.artist : "\(album.artist) · \(album.year)")
                    .font(.subheadline)
                    .foregroundColor(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            PlayActionsHeader(
                onPlay: { player.play(tracks: tracks, startAt: 0, source: source) },
                onShuffle: { player.shufflePlay(tracks: tracks, source: source) }
            )

            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(track: track, trackNumber: track.trackNumber) {
                    player.play(tracks: tracks, startAt: index, source: source)
                }
            }
        }
        .flacListStyle()
        .navigationBarTitleDisplayMode(.inline)
    }
}
