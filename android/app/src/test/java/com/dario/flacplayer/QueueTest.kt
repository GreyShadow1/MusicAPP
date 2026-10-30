package com.dario.flacplayer

import com.dario.flacplayer.audio.PlaybackQueue
import com.dario.flacplayer.audio.RepeatMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class QueueTest {
    private val ids = (0 until 6).map { "t$it" }
    private fun queue(start: Int = 0) = PlaybackQueue().load(ids, start, "Libreria")

    @Test fun loadSetsCurrentAndUpcoming() {
        val q = queue(2)
        assertEquals("t2", q.current?.trackId)
        assertEquals(ids.drop(3), q.upcoming.map { it.trackId })
    }

    @Test fun invalidStartEmptiesQueue() {
        assertTrue(queue().load(ids, 99, "x").isEmpty)
    }

    @Test fun shuffleKeepsCurrentAndAllTracks() {
        val q = queue(3)
        val s = q.withShuffle(true)
        assertEquals(q.current, s.current)
        assertEquals(0, s.index)
        assertEquals(ids.toSet(), s.order.map { it.trackId }.toSet())
        assertEquals(ids.size, s.order.size)
    }

    @Test fun disablingShuffleRestoresOrderAndCurrent() {
        var q = queue(3).withShuffle(true)
        q = q.at(q.order[2].id)
        val current = q.current
        q = q.withShuffle(false)
        assertEquals(ids, q.order.map { it.trackId })
        assertEquals(current, q.current)
    }

    @Test fun shuffleAvoidsSameTrackNextWhenDuplicated() {
        repeat(200) {
            val q = PlaybackQueue().load(listOf("a", "a", "b"), 0, "x").withShuffle(true)
            assertEquals("b", q.order[1].trackId)
        }
    }

    @Test fun repeatCyclesOffAllOne() {
        assertEquals(RepeatMode.ALL, RepeatMode.OFF.next)
        assertEquals(RepeatMode.ONE, RepeatMode.ALL.next)
        assertEquals(RepeatMode.OFF, RepeatMode.ONE.next)
    }

    @Test fun moveUpcoming() {
        val q = queue(1).movedUpcoming(0, 2)
        assertEquals(listOf("t3", "t4", "t2", "t5"), q.upcoming.map { it.trackId })
        assertEquals(q.order, q.original)
    }

    @Test fun moveDuringShuffleKeepsOriginal() {
        val q = queue().withShuffle(true).movedUpcoming(0, 3)
        assertEquals(ids, q.original.map { it.trackId })
    }

    @Test fun removeBeforeCurrentKeepsCurrent() {
        val q = queue(2)
        val r = q.without(q.order[0].id)
        assertEquals("t2", r.current?.trackId)
        assertEquals(1, r.index)
    }

    @Test fun removeCurrentSelectsNext() {
        val q = queue(2)
        assertEquals("t3", q.without(q.current!!.id).current?.trackId)
    }

    @Test fun removeLastItemEmptiesQueue() {
        val q = PlaybackQueue().load(listOf("a"), 0, "x")
        val r = q.without(q.current!!.id)
        assertTrue(r.isEmpty)
        assertNull(r.current)
    }

    @Test fun removeDeletedTracks() {
        val q = queue(2).withoutTracks(setOf("t0", "t2", "t4"))
        assertEquals(listOf("t1", "t3", "t5"), q.order.map { it.trackId })
        assertEquals("t3", q.current?.trackId)
    }

    @Test fun insertNextGoesAfterCurrent() {
        val q = queue(1).insertedNext(listOf("new"))
        assertEquals("new", q.upcoming.first().trackId)
        assertEquals("new", q.original[2].trackId)
    }

    @Test fun appendSurvivesDisablingShuffle() {
        val q = queue().withShuffle(true).appended(listOf("new")).withShuffle(false)
        assertEquals("new", q.order.last().trackId)
    }

    @Test fun appendToEmptySelectsFirst() {
        val q = PlaybackQueue().appended(listOf("a", "b"))
        assertEquals("a", q.current?.trackId)
    }

    @Test fun clearKeepsCurrent() {
        assertEquals(listOf("t3"), queue(3).clearedExceptCurrent().order.map { it.trackId })
    }
}
