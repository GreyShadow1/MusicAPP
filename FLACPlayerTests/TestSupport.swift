import Foundation
import XCTest
@testable import FLACPlayer

/// File di prova inclusi nel bundle di test.
enum Fixture: String {
    case tagged16 = "tagged_16_44100.flac"
    case tagged24 = "tagged_24_96000.flac"
    case untagged24 = "untagged_24_96000.flac"
    case corrupt = "corrupt_16_44100.flac"
    case notFLAC = "not_a_flac.flac"

    var url: URL {
        Bundle(for: FixtureBundleToken.self)
            .bundleURL
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(rawValue)
    }
}

private final class FixtureBundleToken {}

/// Cartelle temporanee che imitano il container dell'app.
final class TestEnvironment {
    let root: URL
    let paths: AppPaths
    let persistence: PersistenceManager

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FLACPlayerTests-\(UUID().uuidString)", isDirectory: true)
        paths = AppPaths(
            documents: root.appendingPathComponent("Documents", isDirectory: true),
            support: root.appendingPathComponent("Support", isDirectory: true)
        )
        try paths.prepare()
        persistence = try PersistenceManager(url: paths.database)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Copia un file di prova in Documents, come farebbe il trasferimento USB.
    @discardableResult
    func copyToDocuments(_ fixture: Fixture, as relativePath: String) throws -> URL {
        let destination = paths.documents.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: fixture.url, to: destination)
        return destination
    }

    @discardableResult
    func scan() throws -> ScanReport {
        try FileScanner(paths: paths, persistence: persistence).scan { _, _ in }
    }
}

extension Track {
    static func stub(id: UUID = UUID(), title: String = "Brano", isMissing: Bool = false) -> Track {
        Track(
            id: id,
            contentHash: id.uuidString,
            relativePath: "Music/\(id.uuidString).flac",
            fileSize: 1,
            modifiedAt: 0,
            title: title,
            artist: "Artista",
            album: "Album",
            albumArtist: "Artista",
            genre: "",
            date: "",
            trackNumber: 1,
            discNumber: 1,
            duration: 180,
            sampleRate: 44100,
            bitDepth: 16,
            channels: 2,
            coverID: nil,
            isMissing: isMissing,
            addedAt: Date()
        )
    }
}
