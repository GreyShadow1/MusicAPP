import Foundation

/// Artista ricavato dai tag. Non viene salvato: si ricostruisce dalla libreria.
struct Artist: Identifiable, Hashable {
    let id: String
    let name: String
    let albums: [Album]
    let tracks: [Track]

    var coverID: String? {
        albums.lazy.compactMap(\.coverID).first
    }

    static func group(_ tracks: [Track]) -> [Artist] {
        let groups = Dictionary(grouping: tracks, by: \.albumArtist)
        return groups.map { name, members in
            Artist(id: name, name: name, albums: Album.group(members), tracks: TrackSortOrder.album.sorted(members))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
