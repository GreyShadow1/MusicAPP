import XCTest
@testable import FLACPlayer

final class PlaylistTests: XCTestCase {
    private var environment: TestEnvironment!

    override func setUpWithError() throws {
        environment = try TestEnvironment()
    }

    private func insertTracks(_ count: Int) throws -> [Track] {
        let tracks = (0..<count).map { Track.stub(title: "Brano \($0)") }
        try tracks.forEach(environment.persistence.insert)
        return tracks
    }

    func testCreateAndReadPlaylist() throws {
        let tracks = try insertTracks(3)
        let playlist = Playlist(name: "Viaggio", trackIDs: tracks.map(\.id))
        try environment.persistence.save(playlist)

        let stored = try environment.persistence.allPlaylists()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].name, "Viaggio")
        XCTAssertEqual(stored[0].trackIDs, tracks.map(\.id))
    }

    func testEditPlaylistKeepsOrder() throws {
        let tracks = try insertTracks(3)
        var playlist = Playlist(name: "Prima", trackIDs: tracks.map(\.id))
        try environment.persistence.save(playlist)

        playlist.name = "Dopo"
        playlist.trackIDs = [tracks[2].id, tracks[0].id]
        try environment.persistence.save(playlist)

        let stored = try environment.persistence.allPlaylists()
        XCTAssertEqual(stored.map(\.name), ["Dopo"])
        XCTAssertEqual(stored[0].trackIDs, [tracks[2].id, tracks[0].id])
    }

    func testSameTrackMayAppearTwice() throws {
        let tracks = try insertTracks(1)
        let playlist = Playlist(name: "Doppio", trackIDs: [tracks[0].id, tracks[0].id])
        try environment.persistence.save(playlist)
        XCTAssertEqual(try environment.persistence.allPlaylists()[0].trackIDs.count, 2)
    }

    func testDeletePlaylistKeepsTracks() throws {
        let tracks = try insertTracks(2)
        let playlist = Playlist(name: "Da togliere", trackIDs: tracks.map(\.id))
        try environment.persistence.save(playlist)

        try environment.persistence.deletePlaylist(id: playlist.id)

        XCTAssertTrue(try environment.persistence.allPlaylists().isEmpty)
        XCTAssertEqual(try environment.persistence.allTracks().count, 2)
    }

    func testDeletedTrackLeavesNoDanglingReferences() throws {
        let tracks = try insertTracks(3)
        try environment.persistence.save(Playlist(name: "Lista", trackIDs: tracks.map(\.id)))
        try environment.persistence.setFavorite(true, trackID: tracks[1].id)

        try environment.persistence.deleteTrack(id: tracks[1].id)

        XCTAssertEqual(try environment.persistence.allPlaylists()[0].trackIDs, [tracks[0].id, tracks[2].id])
        XCTAssertTrue(try environment.persistence.favoriteIDs().isEmpty)
    }

    func testFavoritesPersistAndAreNewestFirst() throws {
        let tracks = try insertTracks(2)
        try environment.persistence.setFavorite(true, trackID: tracks[0].id)
        Thread.sleep(forTimeInterval: 0.01)
        try environment.persistence.setFavorite(true, trackID: tracks[1].id)
        XCTAssertEqual(try environment.persistence.favoriteIDs(), [tracks[1].id, tracks[0].id])

        try environment.persistence.setFavorite(false, trackID: tracks[1].id)
        XCTAssertEqual(try environment.persistence.favoriteIDs(), [tracks[0].id])
    }

    func testDataSurvivesReopeningDatabase() throws {
        let tracks = try insertTracks(1)
        try environment.persistence.save(Playlist(name: "Persistente", trackIDs: [tracks[0].id]))
        try environment.persistence.setFavorite(true, trackID: tracks[0].id)
        try environment.persistence.setSetting("chiave", value: "valore")

        let reopened = try PersistenceManager(url: environment.paths.database)

        XCTAssertEqual(try reopened.allTracks().map(\.id), [tracks[0].id])
        XCTAssertEqual(try reopened.allPlaylists().map(\.name), ["Persistente"])
        XCTAssertEqual(try reopened.favoriteIDs(), [tracks[0].id])
        XCTAssertEqual(try reopened.setting("chiave"), "valore")
    }

    func testCorruptedDatabaseIsReplacedInsteadOfBlockingTheApp() throws {
        let url = environment.root.appendingPathComponent("rotto.sqlite")
        try Data("questo non è un database sqlite, solo testo".utf8).write(to: url)

        let persistence = try PersistenceManager(url: url)

        XCTAssertTrue(try persistence.allTracks().isEmpty)
    }

    @MainActor
    func testFavoritesManagerUpdatesImmediately() throws {
        let tracks = try insertTracks(1)
        let favorites = FavoritesManager(persistence: environment.persistence)

        favorites.toggle(tracks[0].id)
        XCTAssertTrue(favorites.isFavorite(tracks[0].id))
        XCTAssertEqual(favorites.orderedIDs, [tracks[0].id])

        favorites.toggle(tracks[0].id)
        XCTAssertFalse(favorites.isFavorite(tracks[0].id))
        XCTAssertTrue(favorites.orderedIDs.isEmpty)
    }
}
