import SwiftUI

/// Stato della coda di riproduzione. È un valore puro, senza dipendenze audio.
///
/// - Brano corrente: `currentItem`, cioè `playOrder[currentIndex]`.
/// - Coda corrente: `playOrder`, l'ordine effettivo di riproduzione.
/// - Ordine originale: `originalOrder`, ripristinato quando si spegne lo shuffle.
/// - Sorgente: `source`, solo informativa; la coda è sempre una copia indipendente
///   degli identificativi, quindi modificarla non altera libreria o playlist.
struct PlaybackQueueManager: Codable, Equatable {
    private(set) var source: QueueSource = .none
    private(set) var originalOrder: [QueueItem] = []
    private(set) var playOrder: [QueueItem] = []
    private(set) var currentIndex: Int?
    private(set) var isShuffled = false
    var repeatMode: RepeatMode = .off

    var currentItem: QueueItem? {
        guard let currentIndex, playOrder.indices.contains(currentIndex) else { return nil }
        return playOrder[currentIndex]
    }

    /// Brani che seguono quello corrente, nell'ordine in cui verranno riprodotti.
    var upcoming: [QueueItem] {
        guard let currentIndex else { return [] }
        return Array(playOrder[(currentIndex + 1)...])
    }

    var isEmpty: Bool {
        playOrder.isEmpty
    }

    // MARK: - Caricamento

    /// Sostituisce la coda. Lo shuffle resta attivo se lo era già.
    mutating func load(trackIDs: [UUID], startAt index: Int, source: QueueSource) {
        guard trackIDs.indices.contains(index) else {
            clearAll()
            return
        }
        self.source = source
        originalOrder = trackIDs.map { QueueItem(trackID: $0) }
        playOrder = originalOrder
        currentIndex = index
        if isShuffled {
            shuffleAroundCurrent()
        }
    }

    mutating func clearAll() {
        source = .none
        originalOrder = []
        playOrder = []
        currentIndex = nil
    }

    // MARK: - Navigazione

    /// Passa al brano successivo e lo restituisce; `nil` se la coda è terminata.
    /// `userInitiated` distingue il tasto Avanti dalla fine naturale del brano:
    /// Repeat One ripete solo alla fine naturale.
    mutating func advance(userInitiated: Bool) -> QueueItem? {
        guard let index = currentIndex, !playOrder.isEmpty else { return nil }

        if repeatMode == .one, !userInitiated {
            return playOrder[index]
        }
        if index + 1 < playOrder.count {
            currentIndex = index + 1
            return playOrder[index + 1]
        }
        guard repeatMode != .off else { return nil }

        if isShuffled {
            reshuffleForNewCycle(lastPlayed: playOrder[index])
        }
        currentIndex = 0
        return playOrder[0]
    }

    /// Torna al brano precedente. All'inizio della coda resta sul primo brano,
    /// a meno che sia attiva la ripetizione della coda.
    mutating func retreat() -> QueueItem? {
        guard let index = currentIndex, !playOrder.isEmpty else { return nil }
        if index > 0 {
            currentIndex = index - 1
        } else if repeatMode == .all {
            currentIndex = playOrder.count - 1
        }
        return currentItem
    }

    mutating func jump(to itemID: UUID) -> QueueItem? {
        guard let index = playOrder.firstIndex(where: { $0.id == itemID }) else { return nil }
        currentIndex = index
        return playOrder[index]
    }

    // MARK: - Shuffle

    mutating func setShuffle(_ enabled: Bool) {
        guard enabled != isShuffled else { return }
        isShuffled = enabled
        if enabled {
            shuffleAroundCurrent()
        } else {
            let current = currentItem
            playOrder = originalOrder
            currentIndex = current.flatMap { item in playOrder.firstIndex(of: item) }
        }
    }

    /// Mette il brano corrente in testa e mescola tutto il resto.
    private mutating func shuffleAroundCurrent() {
        guard let current = currentItem else { return }
        var rest = originalOrder
        if let position = rest.firstIndex(of: current) {
            rest.remove(at: position)
        }
        playOrder = [current] + Self.shuffled(rest, notStartingWith: current)
        currentIndex = 0
    }

    /// Nuovo giro di Repeat All: il primo brano non è mai uguale all'ultimo appena
    /// ascoltato, se esiste un'alternativa.
    private mutating func reshuffleForNewCycle(lastPlayed: QueueItem) {
        playOrder = Self.shuffled(originalOrder, notStartingWith: lastPlayed)
    }

    private static func shuffled(_ items: [QueueItem], notStartingWith previous: QueueItem) -> [QueueItem] {
        var order = items.shuffled()
        if order.first?.trackID == previous.trackID,
           let alternative = order.firstIndex(where: { $0.trackID != previous.trackID }) {
            order.swapAt(0, alternative)
        }
        return order
    }

    // MARK: - Modifiche

    /// Aggiunge in fondo alla coda.
    mutating func append(trackIDs: [UUID]) {
        let items = trackIDs.map { QueueItem(trackID: $0) }
        guard !items.isEmpty else { return }
        if playOrder.isEmpty {
            source = .manual
            currentIndex = 0
        }
        originalOrder.append(contentsOf: items)
        playOrder.append(contentsOf: items)
    }

    /// Inserisce subito dopo il brano corrente.
    mutating func insertNext(trackIDs: [UUID]) {
        guard let index = currentIndex, let current = currentItem else {
            append(trackIDs: trackIDs)
            return
        }
        let items = trackIDs.map { QueueItem(trackID: $0) }
        playOrder.insert(contentsOf: items, at: index + 1)
        let originalPosition = originalOrder.firstIndex(of: current).map { $0 + 1 } ?? originalOrder.endIndex
        originalOrder.insert(contentsOf: items, at: originalPosition)
    }

    /// Sposta voci di `upcoming`; gli indici sono relativi a quella lista. Durante
    /// lo shuffle cambia solo l'ordine mescolato, non quello originale.
    mutating func moveUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let index = currentIndex else { return }
        var reordered = upcoming
        reordered.move(fromOffsets: source, toOffset: destination)
        playOrder.replaceSubrange((index + 1)..., with: reordered)
        if !isShuffled {
            originalOrder = playOrder
        }
    }

    /// Rimuove una voce. Restituisce `true` se era il brano corrente: in quel
    /// caso `currentItem` è già il brano che ne prende il posto.
    @discardableResult
    mutating func remove(itemID: UUID) -> Bool {
        originalOrder.removeAll { $0.id == itemID }
        guard let position = playOrder.firstIndex(where: { $0.id == itemID }) else { return false }
        return removeFromPlayOrder(at: position)
    }

    /// Rimuove tutte le occorrenze di brani eliminati dalla libreria.
    @discardableResult
    mutating func remove(trackIDs: Set<UUID>) -> Bool {
        originalOrder.removeAll { trackIDs.contains($0.trackID) }
        var currentChanged = false
        for position in playOrder.indices.reversed() where trackIDs.contains(playOrder[position].trackID) {
            if removeFromPlayOrder(at: position) {
                currentChanged = true
            }
        }
        return currentChanged
    }

    private mutating func removeFromPlayOrder(at position: Int) -> Bool {
        playOrder.remove(at: position)
        guard let current = currentIndex else { return false }
        if position < current {
            currentIndex = current - 1
            return false
        }
        guard position == current else { return false }
        currentIndex = playOrder.isEmpty ? nil : min(current, playOrder.count - 1)
        if playOrder.isEmpty {
            source = .none
        }
        return true
    }

    /// Svuota la coda mantenendo il brano in riproduzione.
    mutating func clearExceptCurrent() {
        guard let current = currentItem else {
            clearAll()
            return
        }
        originalOrder = [current]
        playOrder = [current]
        currentIndex = 0
        source = .manual
    }
}
