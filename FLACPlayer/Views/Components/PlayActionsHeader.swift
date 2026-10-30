import SwiftUI

/// Pulsanti Riproduci e Casuale in testa ad album, artisti e playlist.
struct PlayActionsHeader: View {
    let onPlay: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            action("Riproduci", systemImage: "play.fill", perform: onPlay)
            action("Casuale", systemImage: "shuffle", perform: onShuffle)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func action(_ title: LocalizedStringKey, systemImage: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.borderless)
    }
}
