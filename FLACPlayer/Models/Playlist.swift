import Foundation

/// Playlist personalizzata: contiene solo identificativi di brani, mai copie dei file.
struct Playlist: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var trackIDs: [UUID]
    let createdAt: Date

    init(id: UUID = UUID(), name: String, trackIDs: [UUID] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.trackIDs = trackIDs
        self.createdAt = createdAt
    }
}
