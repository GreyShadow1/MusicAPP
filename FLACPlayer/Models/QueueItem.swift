import Foundation

/// Una voce della coda. Ha un proprio `id` perché lo stesso brano può comparire
/// più volte e ogni occorrenza va spostata o rimossa singolarmente.
struct QueueItem: Identifiable, Hashable, Codable {
    let id: UUID
    let trackID: UUID

    init(id: UUID = UUID(), trackID: UUID) {
        self.id = id
        self.trackID = trackID
    }
}

/// Da dove proviene la coda. È solo un'informazione: modificare la coda non
/// tocca mai la libreria o la playlist di origine.
enum QueueSource: Codable, Equatable {
    case none
    case library
    case album(title: String)
    case artist(name: String)
    case playlist(id: UUID, name: String)
    case favorites
    case manual

    var label: String {
        switch self {
        case .none: return ""
        case .library: return String(localized: "Libreria")
        case .album(let title): return title
        case .artist(let name): return name
        case .playlist(_, let name): return name
        case .favorites: return String(localized: "PREFERITI")
        case .manual: return String(localized: "Coda")
        }
    }
}
