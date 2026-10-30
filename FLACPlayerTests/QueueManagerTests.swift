import XCTest
@testable import FLACPlayer

final class QueueManagerTests: XCTestCase {
    private let ids = (0..<6).map { _ in UUID() }

    private func makeQueue(startAt index: Int = 0) -> PlaybackQueueManager {
        var queue = PlaybackQueueManager()
        queue.load(trackIDs: ids, startAt: index, source: .library)
        return queue
    }

    func testLoadSetsCurrentAndSource() {
        let queue = makeQueue(startAt: 2)
        XCTAssertEqual(queue.currentItem?.trackID, ids[2])
        XCTAssertEqual(queue.source, .library)
        XCTAssertEqual(queue.upcoming.map(\.trackID), Array(ids[3...]))
    }

    func testLoadWithInvalidIndexEmptiesQueue() {
        var queue = makeQueue()
        queue.load(trackIDs: ids, startAt: 99, source: .library)
        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.currentItem)
    }

    // MARK: Ripetizione

    func testRepeatOffStopsAtEnd() {
        var queue = makeQueue(startAt: 5)
        XCTAssertNil(queue.advance(userInitiated: false))
        XCTAssertEqual(queue.currentItem?.trackID, ids[5])
    }

    func testRepeatOneRestartsOnlyOnNaturalEnd() {
        var queue = makeQueue(startAt: 1)
        queue.repeatMode = .one
        XCTAssertEqual(queue.advance(userInitiated: false)?.trackID, ids[1])
        XCTAssertEqual(queue.advance(userInitiated: true)?.trackID, ids[2])
    }

    func testRepeatAllWrapsToFirst() {
        var queue = makeQueue(startAt: 5)
        queue.repeatMode = .all
        XCTAssertEqual(queue.advance(userInitiated: false)?.trackID, ids[0])
    }

    func testRepeatOneNextOnLastTrackWraps() {
        var queue = makeQueue(startAt: 5)
        queue.repeatMode = .one
        XCTAssertEqual(queue.advance(userInitiated: true)?.trackID, ids[0])
    }

    func testRetreat() {
        var queue = makeQueue(startAt: 1)
        XCTAssertEqual(queue.retreat()?.trackID, ids[0])
        XCTAssertEqual(queue.retreat()?.trackID, ids[0], "Senza ripetizione resta sul primo brano")
        queue.repeatMode = .all
        XCTAssertEqual(queue.retreat()?.trackID, ids[5])
    }

    // MARK: Shuffle

    func testShuffleKeepsCurrentAndAllTracks() {
        var queue = makeQueue(startAt: 3)
        let current = queue.currentItem
        queue.setShuffle(true)
        XCTAssertEqual(queue.currentItem, current)
        XCTAssertEqual(queue.currentIndex, 0)
        XCTAssertEqual(Set(queue.playOrder.map(\.trackID)), Set(ids))
        XCTAssertEqual(queue.playOrder.count, ids.count)
    }

    func testDisablingShuffleRestoresOriginalOrderAndKeepsCurrent() {
        var queue = makeQueue(startAt: 3)
        queue.setShuffle(true)
        _ = queue.advance(userInitiated: true)
        let current = queue.currentItem
        queue.setShuffle(false)
        XCTAssertEqual(queue.playOrder.map(\.trackID), ids)
        XCTAssertEqual(queue.currentItem, current)
    }

    func testShuffleNeverRepeatsTrackAcrossCycles() {
        var queue = makeQueue()
        queue.repeatMode = .all
        queue.setShuffle(true)
        var last = queue.currentItem?.trackID
        for _ in 0..<500 {
            let next = queue.advance(userInitiated: false)?.trackID
            XCTAssertNotEqual(next, last)
            last = next
        }
    }

    func testShuffleCycleWithTwoTracksAlternates() {
        var queue = PlaybackQueueManager()
        queue.load(trackIDs: Array(ids[..<2]), startAt: 0, source: .library)
        queue.repeatMode = .all
        queue.setShuffle(true)
        var last = queue.currentItem?.trackID
        for _ in 0..<50 {
            let next = queue.advance(userInitiated: true)?.trackID
            XCTAssertNotEqual(next, last)
            last = next
        }
    }

    func testRepeatOneWinsOverShuffle() {
        var queue = makeQueue()
        queue.setShuffle(true)
        queue.repeatMode = .one
        let current = queue.currentItem
        XCTAssertEqual(queue.advance(userInitiated: false), current)
    }

    func testSingleTrackRepeatAll() {
        var queue = PlaybackQueueManager()
        queue.load(trackIDs: [ids[0]], startAt: 0, source: .library)
        queue.repeatMode = .all
        queue.setShuffle(true)
        XCTAssertEqual(queue.advance(userInitiated: false)?.trackID, ids[0])
    }

    func testLoadWhileShuffledKeepsShuffleAndSelectedTrack() {
        var queue = makeQueue()
        queue.setShuffle(true)
        queue.load(trackIDs: ids, startAt: 4, source: .library)
        XCTAssertTrue(queue.isShuffled)
        XCTAssertEqual(queue.currentItem?.trackID, ids[4])
    }

    // MARK: Modifiche

    func testMoveUpcoming() {
        var queue = makeQueue(startAt: 1)
        queue.moveUpcoming(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        XCTAssertEqual(queue.upcoming.map(\.trackID), [ids[3], ids[2], ids[4], ids[5]])
        XCTAssertEqual(queue.originalOrder.map(\.trackID), [ids[0], ids[1], ids[3], ids[2], ids[4], ids[5]])
    }

    func testMoveDuringShuffleKeepsOriginalOrder() {
        var queue = makeQueue()
        queue.setShuffle(true)
        queue.moveUpcoming(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(queue.originalOrder.map(\.trackID), ids)
    }

    func testRemoveBeforeCurrentKeepsCurrent() throws {
        var queue = makeQueue(startAt: 2)
        let removed = queue.playOrder[0].id
        XCTAssertFalse(queue.remove(itemID: removed))
        XCTAssertEqual(queue.currentItem?.trackID, ids[2])
        XCTAssertEqual(queue.currentIndex, 1)
    }

    func testRemoveCurrentSelectsNext() throws {
        var queue = makeQueue(startAt: 2)
        let current = try XCTUnwrap(queue.currentItem)
        XCTAssertTrue(queue.remove(itemID: current.id))
        XCTAssertEqual(queue.currentItem?.trackID, ids[3])
    }

    func testRemoveLastRemainingItemEmptiesQueue() throws {
        var queue = PlaybackQueueManager()
        queue.load(trackIDs: [ids[0]], startAt: 0, source: .library)
        let current = try XCTUnwrap(queue.currentItem)
        XCTAssertTrue(queue.remove(itemID: current.id))
        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.currentIndex)
    }

    func testSameTrackTwiceIsRemovedIndividually() throws {
        var queue = PlaybackQueueManager()
        queue.load(trackIDs: [ids[0], ids[1], ids[0]], startAt: 1, source: .library)
        let last = try XCTUnwrap(queue.upcoming.last)
        queue.remove(itemID: last.id)
        XCTAssertEqual(queue.playOrder.map(\.trackID), [ids[0], ids[1]])
    }

    func testRemoveDeletedTracksFromLibrary() {
        var queue = makeQueue(startAt: 2)
        let changed = queue.remove(trackIDs: [ids[0], ids[2], ids[4]])
        XCTAssertTrue(changed)
        XCTAssertEqual(queue.playOrder.map(\.trackID), [ids[1], ids[3], ids[5]])
        XCTAssertEqual(queue.currentItem?.trackID, ids[3])
    }

    func testInsertNextGoesAfterCurrent() {
        var queue = makeQueue(startAt: 1)
        let added = UUID()
        queue.insertNext(trackIDs: [added])
        XCTAssertEqual(queue.upcoming.first?.trackID, added)
        XCTAssertEqual(queue.originalOrder[2].trackID, added)
    }

    func testAppendSurvivesDisablingShuffle() {
        var queue = makeQueue()
        queue.setShuffle(true)
        let added = UUID()
        queue.append(trackIDs: [added])
        XCTAssertEqual(queue.playOrder.last?.trackID, added)
        queue.setShuffle(false)
        XCTAssertEqual(queue.playOrder.last?.trackID, added)
    }

    func testAppendToEmptyQueueSelectsFirst() {
        var queue = PlaybackQueueManager()
        queue.append(trackIDs: [ids[0], ids[1]])
        XCTAssertEqual(queue.currentItem?.trackID, ids[0])
        XCTAssertEqual(queue.source, .manual)
    }

    func testClearKeepsCurrentTrack() {
        var queue = makeQueue(startAt: 3)
        queue.clearExceptCurrent()
        XCTAssertEqual(queue.playOrder.map(\.trackID), [ids[3]])
        XCTAssertEqual(queue.currentIndex, 0)
    }

    func testJump() {
        var queue = makeQueue()
        let target = queue.playOrder[4]
        XCTAssertEqual(queue.jump(to: target.id), target)
        XCTAssertEqual(queue.currentIndex, 4)
    }

    func testCodableRoundTrip() throws {
        var queue = makeQueue(startAt: 2)
        queue.setShuffle(true)
        queue.repeatMode = .one
        let data = try JSONEncoder().encode(queue)
        XCTAssertEqual(try JSONDecoder().decode(PlaybackQueueManager.self, from: data), queue)
    }
}
