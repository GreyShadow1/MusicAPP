import Combine
import Foundation

/// Preferiti. La playlist "PREFERITI" non esiste come dato a sé: è la vista di
/// questo elenco, quindi è sempre aggiornata e non è modificabile a mano.
@MainActor
final class FavoritesManager: ObservableObject {
    @Published private(set) var orderedIDs: [UUID] = []
    @Published var errorMessage: String?

    private var ids = Set<UUID>()
    private let persistence: PersistenceManager

    init(persistence: PersistenceManager) {
        self.persistence = persistence
    }

    func reload() {
        do {
            orderedIDs = try persistence.favoriteIDs()
            ids = Set(orderedIDs)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isFavorite(_ trackID: UUID) -> Bool {
        ids.contains(trackID)
    }

    /// La scrittura avviene subito: la scelta sopravvive a una chiusura improvvisa.
    func toggle(_ trackID: UUID) {
        let favorite = !ids.contains(trackID)
        do {
            try persistence.setFavorite(favorite, trackID: trackID)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
