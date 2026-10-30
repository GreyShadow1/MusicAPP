import SwiftUI

struct LibraryView: View {
    private enum Section: CaseIterable, Hashable {
        case tracks
        case albums
        case artists

        var label: LocalizedStringKey {
            switch self {
            case .tracks: return "Brani"
            case .albums: return "Album"
            case .artists: return "Artisti"
            }
        }
    }

    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var player: AudioPlayer

    @State private var section: Section = .tracks
    @State private var sortOrder: TrackSortOrder = .title
    @State private var searchText = ""
    @State private var isImporting = false

    private var query: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    private var visibleTracks: [Track] {
        let sorted = library.sortedTracks(by: sortOrder)
        guard !query.isEmpty else { return sorted }
        return sorted.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.artist.localizedCaseInsensitiveContains(query)
                || $0.album.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            content
                .safeAreaInset(edge: .top, spacing: 0) {
                    Picker("Vista", selection: $section) {
                        ForEach(Section.allCases, id: \.self) { section in
                            Text(section.label).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Theme.background)
                }
                .background(Theme.background)
                .navigationTitle("Libreria")
                .searchable(text: $searchText, prompt: "Titolo, artista o album")
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        if section == .tracks {
                            sortMenu
                        }
                        Button {
                            library.rescan(silent: false)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(library.progress != nil)
                        .accessibilityLabel("Aggiorna la libreria")
                    }
                }
                .musicImporter(isPresented: $isImporting, library: library)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .tracks:
            tracksList
        case .albums:
            AlbumsView(searchText: query)
        case .artists:
            ArtistsView(searchText: query)
        }
    }

    private var tracksList: some View {
        let tracks = visibleTracks
        return List {
            if query.isEmpty {
                ImportMusicView { isImporting = true }
            }
            if tracks.isEmpty, !query.isEmpty {
                Text("Nessun risultato")
                    .foregroundColor(Theme.secondaryText)
                    .listRowBackground(Color.clear)
            }
            ForEach(tracks) { track in
                TrackRow(track: track) {
                    player.play(
                        tracks: tracks,
                        startAt: tracks.firstIndex(of: track) ?? 0,
                        source: .library
                    )
                }
            }
        }
        .flacListStyle()
    }

    private var sortMenu: some View {
        Menu {
            Picker("Ordina per", selection: $sortOrder) {
                ForEach(TrackSortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Ordina")
    }
}
