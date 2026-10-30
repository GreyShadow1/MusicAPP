import SwiftUI

/// Riga di un brano: tocco per riprodurre, cuore e menu delle azioni.
struct TrackRow: View {
    let track: Track
    /// Numero di traccia da mostrare al posto della copertina, nelle pagine album.
    var trackNumber: Int?
    let onPlay: () -> Void

    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var favorites: FavoritesManager

    @State private var isChoosingPlaylist = false
    @State private var isConfirmingDelete = false

    private var isCurrent: Bool {
        player.currentTrack?.id == track.id
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPlay) {
                HStack(spacing: 12) {
                    leading
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.body)
                            .foregroundColor(isCurrent ? .accentColor : .primary)
                            .lineLimit(1)
                        Text(track.isMissing ? String(localized: "File mancante") : "\(track.artist) · \(track.album)")
                            .font(.caption)
                            .foregroundColor(Theme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            FavoriteButton(trackID: track.id)
            actionsMenu
        }
        .opacity(track.isMissing ? 0.45 : 1)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Theme.separator)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                player.addToQueue([track])
            } label: {
                Label("Aggiungi alla coda", systemImage: "text.badge.plus")
            }
            .tint(.accentColor)
        }
        .sheet(isPresented: $isChoosingPlaylist) {
            AddToPlaylistView(trackIDs: [track.id])
        }
        .confirmationDialog(
            "Eliminare «\(track.title)» da questo iPhone?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Elimina", role: .destructive) {
                library.delete(track)
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Il file verrà cancellato e il brano sparirà da playlist e preferiti.")
        }
    }

    @ViewBuilder
    private var leading: some View {
        if let trackNumber {
            Text(trackNumber > 0 ? "\(trackNumber)" : "–")
                .font(.subheadline.monospacedDigit())
                .foregroundColor(Theme.secondaryText)
                .frame(width: 28)
        } else {
            CoverArtView(coverID: track.coverID, side: 44)
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button {
                player.playNext([track])
            } label: {
                Label("Riproduci dopo", systemImage: "text.insert")
            }
            Button {
                player.addToQueue([track])
            } label: {
                Label("Aggiungi alla coda", systemImage: "text.badge.plus")
            }
            Button {
                isChoosingPlaylist = true
            } label: {
                Label("Aggiungi a una playlist", systemImage: "music.note.list")
            }
            Button {
                favorites.toggle(track.id)
            } label: {
                if favorites.isFavorite(track.id) {
                    Label("Rimuovi dai preferiti", systemImage: "heart.slash")
                } else {
                    Label("Aggiungi ai preferiti", systemImage: "heart")
                }
            }
            Divider()
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Elimina da iPhone", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundColor(Theme.secondaryText)
                .frame(minWidth: 32, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Altre azioni")
    }
}
