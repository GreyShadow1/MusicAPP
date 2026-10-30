import XCTest
@testable import FLACPlayer

/// Motore finto: registra i comandi e permette di simulare gli eventi audio.
private final class FakeEngine: PlaybackEngine {
    enum Command: Equatable {
        case load(URL, TimeInterval)
        case pause
        case resume
        case seek(TimeInterval)
        case stop
        case invalidate
    }

    var onEvent: ((PlaybackEngineEvent) -> Void)?
    var commands: [Command] = []
    var lastToken: UInt64 = 0
    var lastEqualizer: EqualizerSettings?

    func load(url: URL, startingAt position: TimeInterval, token: UInt64) {
        lastToken = token
        commands.append(.load(url, position))
    }
    func pause() { commands.append(.pause) }
    func resume() { commands.append(.resume) }
    func seek(to position: TimeInterval) { commands.append(.seek(position)) }
    func stop() { commands.append(.stop) }
    func invalidate() { commands.append(.invalidate) }
    func setEqualizer(_ settings: EqualizerSettings) { lastEqualizer = settings }

    func finishTrack() {
        onEvent?(.finished(token: lastToken))
    }
    func report(position: TimeInterval) {
        onEvent?(.position(position, token: lastToken))
    }
    func fail() {
        onEvent?(.failed(FLACError.decodingFailed, token: lastToken))
    }
}

/// Copre la logica di Play, Pausa, cambio traccia, Seek e ripetizione. La resa
/// audio reale si verifica sull'iPhone: vedi la checklist nel README.
@MainActor
final class AudioPlayerTests: XCTestCase {
    private var environment: TestEnvironment!
    private var engine: FakeEngine!
    private var player: AudioPlayer!
    private var tracks: [Track] = []

    override func setUpWithError() throws {
        environment = try TestEnvironment()
        engine = FakeEngine()
        tracks = (0..<3).map { Track.stub(title: "Brano \($0)") }
        let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        player = AudioPlayer(
            engine: engine,
            session: AudioSessionManager(),
            nowPlaying: NowPlayingManager(),
            persistence: environment.persistence,
            paths: environment.paths,
            trackLookup: { byID[$0] }
        )
    }

    private func url(_ index: Int) -> URL {
        environment.paths.fileURL(for: tracks[index])
    }

    func testPlayLoadsSelectedTrackAndBuildsQueue() {
        player.play(tracks: tracks, startAt: 1, source: .library)

        XCTAssertEqual(engine.commands, [.load(url(1), 0)])
        XCTAssertEqual(player.currentTrack, tracks[1])
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.queue.upcoming.map(\.trackID), [tracks[2].id])
    }

    func testPauseAndResume() {
        player.play(tracks: tracks, startAt: 0, source: .library)
        player.pause()
        XCTAssertFalse(player.isPlaying)
        player.togglePlayPause()
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(Array(engine.commands.suffix(2)), [.pause, .resume])
    }

    func testNaturalEndAdvances() {
        player.play(tracks: tracks, startAt: 0, source: .library)
        engine.finishTrack()
        XCTAssertEqual(player.currentTrack, tracks[1])
        XCTAssertEqual(engine.commands.last, .load(url(1), 0))
    }

    func testEndOfQueueStopsWhenRepeatIsOff() {
        player.play(tracks: tracks, startAt: 2, source: .library)
        engine.finishTrack()
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentTrack, tracks[2])
        XCTAssertEqual(engine.commands.last, .stop)
    }

    func testPlayAfterEndOfQueueRestartsLastTrack() {
        player.play(tracks: tracks, startAt: 2, source: .library)
        engine.finishTrack()
        player.play()
        XCTAssertEqual(engine.commands.last, .load(url(2), 0))
        XCTAssertTrue(player.isPlaying)
    }

    func testRepeatOneReloadsSameTrackOnNaturalEnd() {
        player.play(tracks: tracks, startAt: 0, source: .library)
        player.cycleRepeatMode()
        player.cycleRepeatMode()
        XCTAssertEqual(player.queue.repeatMode, .one)
        engine.finishTrack()
        XCTAssertEqual(player.currentTrack, tracks[0])
        XCTAssertEqual(engine.commands.last, .load(url(0), 0))
    }

    func testRepeatAllWrapsAround() {
        player.play(tracks: tracks, startAt: 2, source: .library)
        player.cycleRepeatMode()
        engine.finishTrack()
        XCTAssertEqual(player.currentTrack, tracks[0])
        XCTAssertTrue(player.isPlaying)
    }

    func testPreviousRewindsWhenTrackHasAdvanced() {
        player.play(tracks: tracks, startAt: 1, source: .library)
        engine.report(position: 30)
        player.previous()
        XCTAssertEqual(player.currentTrack, tracks[1])
        XCTAssertEqual(engine.commands.last, .seek(0))
    }

    func testPreviousChangesTrackNearStart() {
        player.play(tracks: tracks, startAt: 1, source: .library)
        engine.report(position: 1)
        player.previous()
        XCTAssertEqual(player.currentTrack, tracks[0])
    }

    func testSeekWhilePlayingGoesToEngine() {
        player.play(tracks: tracks, startAt: 0, source: .library)
        player.seek(to: 42)
        XCTAssertEqual(engine.commands.last, .seek(42))
        XCTAssertEqual(player.progress.position, 42)
    }

    func testSeekIsClampedToDuration() {
        player.play(tracks: tracks, startAt: 0, source: .library)
        player.seek(to: 9_999)
        XCTAssertEqual(player.progress.position, tracks[0].duration)
    }

    func testSeekWhilePausedResumesFromNewPosition() {
        player.play(tracks: tracks, startAt: 0, source: .library)
        player.pause()
        player.seek(to: 60)
        player.play()
        XCTAssertEqual(engine.commands.last, .load(url(0), 60))
    }

    func testStaleEventsFromPreviousTrackAreIgnored() {
        player.play(tracks: tracks, startAt: 0, source: .library)
        let staleToken = engine.lastToken
        player.next()
        engine.onEvent?(.finished(token: staleToken))
        engine.onEvent?(.position(99, token: staleToken))
        XCTAssertEqual(player.currentTrack, tracks[1])
        XCTAssertEqual(player.progress.position, 0)
    }

    func testFailedTrackIsSkippedWithMessage() {
        player.play(tracks: tracks, startAt: 0, source: .library)
        engine.fail()
        XCTAssertEqual(player.currentTrack, tracks[1])
        XCTAssertNotNil(player.errorMessage)
    }

    func testAllTracksFailingDoesNotLoopForever() {
        player.cycleRepeatMode()
        player.play(tracks: tracks, startAt: 0, source: .library)
        for _ in 0..<10 where player.isPlaying {
            engine.fail()
        }
        XCTAssertFalse(player.isPlaying)
    }

    func testMissingFilesAreExcludedFromQueue() {
        let missing = Track.stub(isMissing: true)
        player.play(tracks: [tracks[0], missing, tracks[1]], startAt: 0, source: .library)
        XCTAssertEqual(player.queue.playOrder.map(\.trackID), [tracks[0].id, tracks[1].id])
    }

    func testSelectingMissingTrackShowsMessage() {
        player.play(tracks: [Track.stub(isMissing: true)], startAt: 0, source: .library)
        XCTAssertNil(player.currentTrack)
        XCTAssertNotNil(player.errorMessage)
    }

    func testAddToEmptyQueuePreparesWithoutPlaying() {
        player.addToQueue([tracks[0]])
        XCTAssertEqual(player.currentTrack, tracks[0])
        XCTAssertFalse(player.isPlaying)
        XCTAssertTrue(engine.commands.isEmpty)
    }

    func testEqualizerIsSentToEngineAndRestored() {
        player.updateEqualizer {
            $0.isEnabled = true
            $0.apply(EqualizerSettings.presets[2])
        }
        XCTAssertEqual(engine.lastEqualizer, player.equalizer)

        let restoredEngine = FakeEngine()
        let restored = AudioPlayer(
            engine: restoredEngine,
            session: AudioSessionManager(),
            nowPlaying: NowPlayingManager(),
            persistence: environment.persistence,
            paths: environment.paths,
            trackLookup: { _ in nil }
        )
        XCTAssertEqual(restored.equalizer, player.equalizer)
        XCTAssertEqual(restoredEngine.lastEqualizer, player.equalizer)
    }

    func testSessionRestoreKeepsQueueWithoutStartingAudio() {
        player.play(tracks: tracks, startAt: 1, source: .library)
        engine.report(position: 12)
        player.pause()

        let restoredEngine = FakeEngine()
        let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let restored = AudioPlayer(
            engine: restoredEngine,
            session: AudioSessionManager(),
            nowPlaying: NowPlayingManager(),
            persistence: environment.persistence,
            paths: environment.paths,
            trackLookup: { byID[$0] }
        )
        restored.restoreSession()

        XCTAssertEqual(restored.currentTrack, tracks[1])
        XCTAssertEqual(restored.progress.position, 12)
        XCTAssertFalse(restored.isPlaying)
        XCTAssertTrue(restoredEngine.commands.isEmpty)
    }
}
