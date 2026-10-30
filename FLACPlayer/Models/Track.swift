import Foundation

/// Un brano della libreria.
///
/// `id` è stabile per tutta la vita del brano: non dipende dal percorso, quindi
/// playlist e preferiti sopravvivono allo spostamento o alla rinomina del file.
/// `relativePath` è relativo a Documents perché il percorso assoluto del
/// container cambia a ogni aggiornamento dell'app.
struct Track: Identifiable, Hashable, Codable {
    let id: UUID
    var contentHash: String
    var relativePath: String
    var fileSize: Int64
    var modifiedAt: TimeInterval

    var title: String
    var artist: String
    var album: String
    var albumArtist: String
    var genre: String
    var date: String
    var trackNumber: Int
    var discNumber: Int

    var duration: TimeInterval
    var sampleRate: Int
    var bitDepth: Int
    var channels: Int

    var coverID: String?
    var isMissing: Bool
    var addedAt: Date

    /// Anno a quattro cifre ricavato dal tag DATE, che può contenere una data completa.
    var year: String {
        String(date.prefix(4))
    }

    /// Es. "24 bit · 96 kHz".
    var qualityDescription: String {
        "\(bitDepth) bit · \(AudioFormatInfo.formatKilohertz(Double(sampleRate))) kHz"
    }
}

/// Ordinamenti disponibili nella lista dei brani.
enum TrackSortOrder: String, CaseIterable, Identifiable {
    case title
    case artist
    case album

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: return String(localized: "Titolo")
        case .artist: return String(localized: "Artista")
        case .album: return String(localized: "Album")
        }
    }

    func sorted(_ tracks: [Track]) -> [Track] {
        switch self {
        case .title:
            return tracks.sorted { Self.ascending($0.title, $1.title) }
        case .artist:
            return tracks.sorted {
                if $0.artist != $1.artist { return Self.ascending($0.artist, $1.artist) }
                return Self.albumOrder($0, $1)
            }
        case .album:
            return tracks.sorted(by: Self.albumOrder)
        }
    }

    /// Ordine naturale di un album: disco, traccia, poi titolo.
    static func albumOrder(_ lhs: Track, _ rhs: Track) -> Bool {
        if lhs.album != rhs.album { return ascending(lhs.album, rhs.album) }
        if lhs.discNumber != rhs.discNumber { return lhs.discNumber < rhs.discNumber }
        if lhs.trackNumber != rhs.trackNumber { return lhs.trackNumber < rhs.trackNumber }
        return ascending(lhs.title, rhs.title)
    }

    private static func ascending(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }
}
