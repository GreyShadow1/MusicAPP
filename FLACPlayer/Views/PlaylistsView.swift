import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var favorites: FavoritesManager

    @State private var isCreating = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    FavoritesListView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.accentColor)
                            .frame(width: 44, height: 44)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PREFERITI")
                            Text("\(favorites.orderedIDs.count) brani · automatica")
                                .font(.caption)
                                .foregroundColor(Theme.secondaryText)
                        }
                    }
                }
                .listRowBackground(Color.clear)

                ForEach(library.playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlistID: playlist.id)
                    } label: {
                        PlaylistRow(playlist: playlist)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Theme.separator)
                }
                .onDelete { offsets in
                    let removed = offsets.map { library.playlists[$0] }
                    for playlist in removed {
                        library.delete(playlist)
                    }
                }
            }
            .flacListStyle()
            .navigationTitle("Playlist")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newName = ""
                        isCreating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Nuova playlist")
                }
            }
            .alert("Nuova playlist", isPresented: $isCreating) {
                TextField("Nome", text: $newName)
                Button("Annulla", role: .cancel) {}
                Button("Crea") {
                    library.createPlaylist(name: newName)
                }
            }
        }
    }
}

private struct PlaylistRow: View {
    let playlist: Playlist

    @EnvironmentObject var library: MusicLibraryManager

    var body: some View {
        HStack(spacing: 12) {
            CoverArtView(coverID: coverID, side: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .lineLimit(1)
                Text("\(playlist.trackIDs.count) brani")
                    .font(.caption)
                    .foregroundColor(Theme.secondaryText)
            }
        }
    }

    private var coverID: String? {
        library.tracks(ids: Array(playlist.trackIDs.prefix(10))).lazy.compactMap(\.coverID).first
    }
}

struct PlaylistDetailView: View {
    let playlistID: UUID

    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    @State private var isAddingTracks = false
    @State private var isRenaming = false
    @State private var isConfirmingDelete = false
    @State private var editedName = ""

    var body: some View {
        if let playlist = library.findPlaylist(id: playlistID) {
            content(playlist)
        } else {
            EmptyStateView(systemImage: "music.note.list", title: "Playlist eliminata", message: "")
        }
    }

    private func content(_ playlist: Playlist) -> some View {
        let tracks = library.tracks(ids: playlist.trackIDs)
        let source = QueueSource.playlist(id: playlist.id, name: playlist.name)
        return List {
            if tracks.isEmpty {
                Text("Questa playlist è vuota.")
                    .foregroundColor(Theme.secondaryText)
                    .listRowBackground(Color.clear)
            } else {
                PlayActionsHeader(
                    onPlay: { player.play(tracks: tracks, startAt: 0, source: source) },
                    onShuffle: { player.shufflePlay(tracks: tracks, source: source) }
                )
            }
            // L'identità è la posizione: lo stesso brano può comparire due volte.
            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                TrackRow(track: track) {
                    player.play(tracks: tracks, startAt: index, source: source)
                }
            }
            .onDelete { library.removeTracks(at: $0, from: playlist.id) }
            .onMove { library.moveTracks(in: playlist.id, fromOffsets: $0, toOffset: $1) }
        }
        .flacListStyle()
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    isAddingTracks = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Aggiungi brani")

                EditButton()

                Menu {
                    Button {
                        editedName = playlist.name
                        isRenaming = true
                    } label: {
                        Label("Rinomina", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Elimina playlist", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Altre azioni")
            }
        }
        .sheet(isPresented: $isAddingTracks) {
            TrackPickerView(title: "Aggiungi brani") { selected in
                library.add(selected.map(\.id), to: playlist.id)
            }
        }
        .alert("Rinomina playlist", isPresented: $isRenaming) {
            TextField("Nome", text: $editedName)
            Button("Annulla", role: .cancel) {}
            Button("Salva") {
                library.rename(playlist, to: editedName)
            }
        }
        .confirmationDialog(
            "Eliminare la playlist «\(playlist.name)»?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Elimina", role: .destructive) {
                library.delete(playlist)
                dismiss()
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("I brani resteranno nella libreria.")
        }
    }
}

/// Foglio per scegliere una playlist di destinazione, esistente o nuova.
struct AddToPlaylistView: View {
    let trackIDs: [UUID]

    @EnvironmentObject var library: MusicLibraryManager
    @Environment(\.dismiss) private var dismiss

    @State private var isCreating = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Button {
                    isCreating = true
                } label: {
                    Label("Nuova playlist", systemImage: "plus")
                }
                .listRowBackground(Color.clear)

                ForEach(library.playlists) { playlist in
                    Button {
                        library.add(trackIDs, to: playlist.id)
                        dismiss()
                    } label: {
                        Text(playlist.name)
                            .foregroundColor(.primary)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .flacListStyle()
            .navigationTitle("Aggiungi a playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
            .alert("Nuova playlist", isPresented: $isCreating) {
                TextField("Nome", text: $newName)
                Button("Annulla", role: .cancel) {}
                Button("Crea") {
                    if library.createPlaylist(name: newName, trackIDs: trackIDs) != nil {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Selezione multipla di brani dalla libreria.
struct TrackPickerView: View {
    let title: LocalizedStringKey
    let onConfirm: ([Track]) -> Void

    @EnvironmentObject var library: MusicLibraryManager
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selection = Set<UUID>()

    private var visibleTracks: [Track] {
        let sorted = library.sortedTracks(by: .title).filter { !$0.isMissing }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sorted }
        return sorted.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.artist.localizedCaseInsensitiveContains(query)
                || $0.album.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(visibleTracks) { track in
                Button {
                    if selection.contains(track.id) {
                        selection.remove(track.id)
                    } else {
                        selection.insert(track.id)
                    }
                } label: {
                    HStack(spacing: 12) {
                        CoverArtView(coverID: track.coverID, side: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.caption)
                                .foregroundColor(Theme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: selection.contains(track.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selection.contains(track.id) ? .accentColor : Theme.secondaryText)
                    }
                }
                .listRowBackground(Color.clear)
            }
            .flacListStyle()
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Titolo, artista o album")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aggiungi") {
                        // Mantiene l'ordine della lista, non quello dei tocchi.
                        onConfirm(library.sortedTracks(by: .title).filter { selection.contains($0.id) })
                        dismiss()
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
    }
}
