import CFLAC
import Foundation

/// Tag e formato di un file FLAC, già completi di valori predefiniti.
struct TrackMetadata {
    var title: String
    var artist: String
    var album: String
    var albumArtist: String
    var genre: String
    var date: String
    var trackNumber: Int
    var discNumber: Int
    var coverData: Data?
    var info: FLACStreamInfo
}

struct MetadataReader {
    static let unknownArtist = String(localized: "Artista sconosciuto")
    static let unknownAlbum = String(localized: "Album sconosciuto")

    /// Legge tag e copertina senza decodificare l'audio.
    func read(url: URL) throws -> TrackMetadata {
        var raw = cflac_metadata()
        let status = url.withUnsafeFileSystemRepresentation { path in
            cflac_metadata_read(path, &raw)
        }
        guard status == CFLAC_OK else {
            throw FLACError(status: status)
        }
        defer { cflac_metadata_free(&raw) }

        var tags: [String: [String]] = [:]
        for index in 0..<Int(raw.comment_count) {
            guard let pointer = raw.comments[index] else { continue }
            let entry = String(cString: pointer)
            guard let separator = entry.firstIndex(of: "=") else { continue }
            let key = entry[..<separator].uppercased()
            let value = entry[entry.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                tags[key, default: []].append(value)
            }
        }

        var coverData: Data?
        if let picture = raw.picture_data, raw.picture_size > 0 {
            coverData = Data(bytes: picture, count: raw.picture_size)
        }

        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let artist = Self.joined(tags["ARTIST"])
        let albumArtist = Self.joined(tags["ALBUMARTIST"] ?? tags["ALBUM ARTIST"])

        return TrackMetadata(
            title: Self.joined(tags["TITLE"]) ?? fallbackTitle,
            artist: artist ?? albumArtist ?? Self.unknownArtist,
            album: Self.joined(tags["ALBUM"]) ?? Self.unknownAlbum,
            albumArtist: albumArtist ?? artist ?? Self.unknownArtist,
            genre: Self.joined(tags["GENRE"]) ?? "",
            date: tags["DATE"]?.first ?? tags["YEAR"]?.first ?? "",
            trackNumber: Self.leadingNumber(tags["TRACKNUMBER"]?.first),
            discNumber: Self.leadingNumber(tags["DISCNUMBER"]?.first),
            coverData: coverData,
            info: FLACStreamInfo(raw.info)
        )
    }

    /// I tag Vorbis ammettono più valori per la stessa chiave.
    private static func joined(_ values: [String]?) -> String? {
        guard let values, !values.isEmpty else { return nil }
        return values.joined(separator: ", ")
    }

    /// "3/12" → 3. Il tag può indicare anche il totale; senza numero restituisce 0.
    private static func leadingNumber(_ value: String?) -> Int {
        guard let value else { return 0 }
        return Int(value.prefix { $0.isNumber }) ?? 0
    }
}

extension Track {
    init(id: UUID = UUID(), metadata: TrackMetadata, file: ScannedFile, contentHash: String, coverID: String?, addedAt: Date = Date()) {
        self.init(
            id: id,
            contentHash: contentHash,
            relativePath: file.relativePath,
            fileSize: file.fileSize,
            modifiedAt: file.modifiedAt,
            title: metadata.title,
            artist: metadata.artist,
            album: metadata.album,
            albumArtist: metadata.albumArtist,
            genre: metadata.genre,
            date: metadata.date,
            trackNumber: metadata.trackNumber,
            discNumber: metadata.discNumber,
            duration: metadata.info.duration,
            sampleRate: metadata.info.sampleRate,
            bitDepth: metadata.info.bitDepth,
            channels: metadata.info.channels,
            coverID: coverID,
            isMissing: false,
            addedAt: addedAt
        )
    }
}
