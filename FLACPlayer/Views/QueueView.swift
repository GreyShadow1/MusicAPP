import SwiftUI

/// Coda di riproduzione: tocco per saltare a un brano, pressione prolungata per
/// riordinare, scorrimento per rimuovere.
struct QueueView: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var library: MusicLibraryManager
    @Environment(\.dismiss) private var dismiss

    @State private var isAddingTracks = false

    var body: some View {
        NavigationStack {
            List {
                if let track = player.currentTrack {
                    Section {
                        row(for: track)
                    } header: {
                        Text("In riproduzione")
                    } footer: {
                        if !player.queue.source.label.isEmpty {
                            Text("Da: \(player.queue.source.label)")
                        }
                    }
                }

                Section {
                    ForEach(player.queue.upcoming) { item in
                        if let track = library.tracksByID[item.trackID] {
                            Button {
                                player.jump(to: item.id)
                            } label: {
                                row(for: track)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onDelete { removeUpcoming(at: $0) }
                    .onMove { player.moveUpcoming(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Successivi")
                } footer: {
                    if player.queue.upcoming.isEmpty {
                        Text(player.queue.repeatMode == .all
                            ? "Alla fine la coda ricomincerà dal primo brano."
                            : "Non ci sono altri brani in coda.")
                    }
                }
            }
            .flacListStyle()
            .navigationTitle("Coda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Svuota") { player.clearQueue() }
                        .disabled(player.queue.upcoming.isEmpty)
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        isAddingTracks = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Aggiungi brani")
                    EditButton()
                    Button("Fine") { dismiss() }
                }
            }
            .sheet(isPresented: $isAddingTracks) {
                TrackPickerView(title: "Aggiungi alla coda") { selected in
                    player.addToQueue(selected)
                }
            }
        }
    }

    private func removeUpcoming(at offsets: IndexSet) {
        let items = player.queue.upcoming
        for offset in offsets where items.indices.contains(offset) {
            player.removeFromQueue(itemID: items[offset].id)
        }
    }

    private func row(for track: Track) -> some View {
        HStack(spacing: 12) {
            CoverArtView(coverID: track.coverID, side: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.caption)
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
