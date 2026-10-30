import SwiftUI

/// Cuore pieno se il brano è nei preferiti.
struct FavoriteButton: View {
    let trackID: UUID
    var font: Font = .body

    @EnvironmentObject var favorites: FavoritesManager

    var body: some View {
        let isFavorite = favorites.isFavorite(trackID)
        Button {
            favorites.toggle(trackID)
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(font)
                .foregroundColor(isFavorite ? .accentColor : Theme.secondaryText)
                .frame(minWidth: 32, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isFavorite ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti")
    }
}
