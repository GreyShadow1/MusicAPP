import XCTest
@testable import FLACPlayer

final class LibraryTests: XCTestCase {
    private var environment: TestEnvironment!

    override func setUpWithError() throws {
        environment = try TestEnvironment()
    }

    private var importer: FileImportManager {
        FileImportManager(paths: environment.paths, persistence: environment.persistence)
    }

    // MARK: Metadati

    func testReadsAllRequestedTags() throws {
        let metadata = try MetadataReader().read(url: Fixture.tagged16.url)
        XCTAssertEqual(metadata.title, "Perché no")
        XCTAssertEqual(metadata.artist, "Àrtista")
        XCTAssertEqual(metadata.album, "Album di prova")
        XCTAssertEqual(metadata.albumArtist, "Vari")
        XCTAssertEqual(metadata.trackNumber, 3)
        XCTAssertEqual(metadata.discNumber, 1)
        XCTAssertEqual(metadata.genre, "Jazz")
        XCTAssertEqual(metadata.date, "1999-05-01")
    }

    func testReadsEmbeddedCover() throws {
        let metadata = try MetadataReader().read(url: Fixture.tagged16.url)
        let cover = try XCTUnwrap(metadata.coverData)
        XCTAssertEqual(Array(cover.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "Deve essere un PNG")
    }

    func testMissingTagsFallBackToFileNameAndDefaults() throws {
        let metadata = try MetadataReader().read(url: Fixture.untagged24.url)
        XCTAssertEqual(metadata.title, "untagged_24_96000")
        XCTAssertEqual(metadata.artist, MetadataReader.unknownArtist)
        XCTAssertEqual(metadata.album, MetadataReader.unknownAlbum)
        XCTAssertEqual(metadata.albumArtist, MetadataReader.unknownArtist)
        XCTAssertNil(metadata.coverData)
    }

    // MARK: Importazione

    func testImportSingleFileCopiesAndKeepsOriginal() throws {
        let report = importer.importItems([Fixture.tagged16.url]) { _, _ in }

        XCTAssertEqual(report, ImportReport(imported: 1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: Fixture.tagged16.url.path))

        let track = try XCTUnwrap(environment.persistence.allTracks().first)
        XCTAssertEqual(track.relativePath, "Music/Vari/Album di prova/03 - Perché no.flac")
        XCTAssertTrue(FileManager.default.fileExists(atPath: environment.paths.fileURL(for: track).path))
        let coverID = try XCTUnwrap(track.coverID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: CoverStore.url(for: coverID, in: environment.paths).path))
    }

    func testImportedFileIsByteIdenticalToOriginal() throws {
        _ = importer.importItems([Fixture.tagged16.url]) { _, _ in }
        let track = try XCTUnwrap(environment.persistence.allTracks().first)
        XCTAssertEqual(
            try Data(contentsOf: environment.paths.fileURL(for: track)),
            try Data(contentsOf: Fixture.tagged16.url)
        )
    }

    func testImportMultipleFiles() throws {
        let report = importer.importItems([Fixture.tagged16.url, Fixture.tagged24.url]) { _, _ in }
        XCTAssertEqual(report.imported, 2)
        XCTAssertEqual(try environment.persistence.allTracks().count, 2)
    }

    func testImportFolderFindsFilesInside() throws {
        let folder = environment.root.appendingPathComponent("Selezionata/Disco 1", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Fixture.tagged16.url, to: folder.appendingPathComponent("uno.flac"))
        try FileManager.default.copyItem(at: Fixture.tagged24.url, to: folder.appendingPathComponent("due.FLAC"))
        try Data("nota".utf8).write(to: folder.appendingPathComponent("leggimi.txt"))

        let report = importer.importItems([environment.root.appendingPathComponent("Selezionata")]) { _, _ in }

        XCTAssertEqual(report.imported, 2)
        XCTAssertTrue(report.failures.isEmpty)
    }

    func testImportRejectsDuplicates() throws {
        let first = importer.importItems([Fixture.tagged16.url]) { _, _ in }
        let second = importer.importItems([Fixture.tagged16.url]) { _, _ in }
        XCTAssertEqual(first.imported, 1)
        XCTAssertEqual(second, ImportReport(duplicates: 1))
        XCTAssertEqual(try environment.persistence.allTracks().count, 1)
    }

    func testImportReportsInvalidFileAndContinues() throws {
        let report = importer.importItems([Fixture.notFLAC.url, Fixture.tagged16.url]) { _, _ in }
        XCTAssertEqual(report.imported, 1)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertTrue(report.failures[0].hasPrefix(Fixture.notFLAC.rawValue))
    }

    func testImportLeavesNoFilesBehindForInvalidInput() throws {
        _ = importer.importItems([Fixture.notFLAC.url]) { _, _ in }
        XCTAssertTrue(FileScanner.findFLACFiles(in: environment.paths.documents).isEmpty)
    }

    func testSanitizedFileNames() {
        XCTAssertEqual(FileImportManager.sanitized("AC/DC: Live?"), "AC DC  Live")
        XCTAssertEqual(FileImportManager.sanitized("..."), "Sconosciuto")
        XCTAssertEqual(FileImportManager.sanitized(""), "Sconosciuto")
    }

    // MARK: Scansione USB

    func testScanFindsFilesCopiedToDocumentsRoot() throws {
        try environment.copyToDocuments(.tagged16, as: "brano.flac")
        try environment.copyToDocuments(.tagged24, as: "Album/Disco 1/traccia.flac")

        let report = try environment.scan()

        XCTAssertEqual(report.added, 2)
        XCTAssertEqual(
            Set(try environment.persistence.allTracks().map(\.relativePath)),
            ["brano.flac", "Album/Disco 1/traccia.flac"]
        )
    }

    func testScanIsCaseInsensitiveOnExtensionAndIgnoresOtherFiles() throws {
        try environment.copyToDocuments(.tagged16, as: "MAIUSCOLO.FLAC")
        try Data("x".utf8).write(to: environment.paths.documents.appendingPathComponent("nota.txt"))
        XCTAssertEqual(try environment.scan().added, 1)
    }

    func testSecondScanChangesNothing() throws {
        try environment.copyToDocuments(.tagged16, as: "brano.flac")
        try environment.scan()
        XCTAssertEqual(try environment.scan(), ScanReport())
    }

    func testScanIgnoresDuplicateWithoutDeletingIt() throws {
        try environment.copyToDocuments(.tagged16, as: "originale.flac")
        let copy = try environment.copyToDocuments(.tagged16, as: "copia.flac")

        let report = try environment.scan()

        XCTAssertEqual(report.added, 1)
        XCTAssertEqual(report.duplicates, 1)
        XCTAssertEqual(try environment.persistence.allTracks().count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertEqual(try environment.scan().duplicates, 0, "Il duplicato noto non va rianalizzato")
    }

    func testDuplicateReplacesOriginalWhenOriginalIsDeleted() throws {
        try environment.copyToDocuments(.tagged16, as: "a.flac")
        try environment.copyToDocuments(.tagged16, as: "b.flac")
        try environment.scan()
        // Quale dei due diventi il brano dipende dall'ordine di enumerazione.
        let track = try XCTUnwrap(environment.persistence.allTracks().first)
        let survivor = track.relativePath == "a.flac" ? "b.flac" : "a.flac"

        try FileManager.default.removeItem(at: environment.paths.fileURL(for: track))
        try environment.scan()

        let updated = try XCTUnwrap(environment.persistence.allTracks().first)
        XCTAssertEqual(updated.id, track.id)
        XCTAssertEqual(updated.relativePath, survivor)
        XCTAssertFalse(updated.isMissing)
    }

    func testMovedFileKeepsIdentityPlaylistsAndFavorites() throws {
        let original = try environment.copyToDocuments(.tagged16, as: "vecchio.flac")
        try environment.scan()
        let track = try XCTUnwrap(environment.persistence.allTracks().first)
        try environment.persistence.save(Playlist(name: "Lista", trackIDs: [track.id]))
        try environment.persistence.setFavorite(true, trackID: track.id)

        let destination = environment.paths.documents.appendingPathComponent("Spostato/nuovo.flac")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: original, to: destination)

        let report = try environment.scan()

        XCTAssertEqual(report.updated, 1)
        XCTAssertEqual(report.added, 0)
        let moved = try XCTUnwrap(environment.persistence.allTracks().first)
        XCTAssertEqual(moved.id, track.id)
        XCTAssertEqual(moved.relativePath, "Spostato/nuovo.flac")
        XCTAssertEqual(try environment.persistence.allPlaylists()[0].trackIDs, [track.id])
        XCTAssertEqual(try environment.persistence.favoriteIDs(), [track.id])
    }

    func testDeletedFileBecomesMissingAndReturnsWhenRestored() throws {
        let file = try environment.copyToDocuments(.tagged16, as: "brano.flac")
        try environment.scan()
        let track = try XCTUnwrap(environment.persistence.allTracks().first)
        try environment.persistence.save(Playlist(name: "Lista", trackIDs: [track.id]))

        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(try environment.scan().newlyMissing, 1)
        XCTAssertEqual(try environment.persistence.allTracks().first?.isMissing, true)
        XCTAssertEqual(try environment.persistence.allPlaylists()[0].trackIDs, [track.id])

        try environment.copyToDocuments(.tagged16, as: "tornato.flac")
        try environment.scan()
        let restored = try XCTUnwrap(environment.persistence.allTracks().first)
        XCTAssertEqual(restored.id, track.id)
        XCTAssertFalse(restored.isMissing)
    }

    func testChangedFileAtSamePathKeepsIdentity() throws {
        let file = try environment.copyToDocuments(.tagged16, as: "brano.flac")
        try environment.scan()
        let track = try XCTUnwrap(environment.persistence.allTracks().first)

        try FileManager.default.removeItem(at: file)
        try environment.copyToDocuments(.tagged24, as: "brano.flac")
        // La copia conserva la data del file di prova: la forza per simulare una modifica.
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        try environment.scan()

        let updated = try XCTUnwrap(environment.persistence.allTracks().first)
        XCTAssertEqual(updated.id, track.id)
        XCTAssertEqual(updated.title, "Hi-Res")
    }

    func testInvalidFileIsReportedByScan() throws {
        try environment.copyToDocuments(.notFLAC, as: "rotto.flac")
        let report = try environment.scan()
        XCTAssertEqual(report.failed, ["rotto.flac"])
        XCTAssertTrue(try environment.persistence.allTracks().isEmpty)
    }

    // MARK: Raggruppamento e ordinamento

    func testAlbumOrderFollowsDiscAndTrackNumbers() {
        var first = Track.stub(title: "Z")
        first.discNumber = 1
        first.trackNumber = 2
        var second = Track.stub(title: "A")
        second.discNumber = 2
        second.trackNumber = 1
        var third = Track.stub(title: "M")
        third.discNumber = 1
        third.trackNumber = 1

        let albums = Album.group([first, second, third])

        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums[0].tracks.map(\.title), ["M", "Z", "A"])
    }

    func testAlbumsWithSameNameFromDifferentArtistsStaySeparate() {
        var first = Track.stub()
        first.albumArtist = "Uno"
        first.album = "Greatest Hits"
        var second = Track.stub()
        second.albumArtist = "Due"
        second.album = "Greatest Hits"
        XCTAssertEqual(Album.group([first, second]).count, 2)
    }

    func testSortIsCaseInsensitive() {
        let tracks = [Track.stub(title: "beta"), Track.stub(title: "Alfa"), Track.stub(title: "Gamma")]
        XCTAssertEqual(TrackSortOrder.title.sorted(tracks).map(\.title), ["Alfa", "beta", "Gamma"])
    }

    func testKilohertzFormatting() {
        XCTAssertEqual(AudioFormatInfo.formatKilohertz(44100), "44,1")
        XCTAssertEqual(AudioFormatInfo.formatKilohertz(96000), "96")
        XCTAssertEqual(AudioFormatInfo.formatKilohertz(176400), "176,4")
    }
}
