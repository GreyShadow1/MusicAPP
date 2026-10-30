import Foundation

/// Album ricavato dai tag. Non viene salvato: si ricostruisce dalla libreria.
struct Album: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let year: String
    let coverID: String?
    let tracks: [Track]

    /// Raggruppa per coppia (artista dell'album, titolo): due album omonimi
    /// di artisti diversi restano separati.
    static func group(_ tracks: [Track]) -> [Album] {
        let groups = Dictionary(grouping: tracks) { "\($0.albumArtist)\u{1F}\($0.album)" }
        return groups.map { key, members in
            let ordered = members.sorted(by: TrackSortOrder.albumOrder)
            let first = ordered[0]
            return Album(
                id: key,
                title: first.album,
                artist: first.albumArtist,
                year: first.year,
                coverID: ordered.lazy.compactMap(\.coverID).first,
                tracks: ordered
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
