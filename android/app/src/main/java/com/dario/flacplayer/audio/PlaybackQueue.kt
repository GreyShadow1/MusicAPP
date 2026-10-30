package com.dario.flacplayer.audio

import java.util.UUID

enum class RepeatMode { OFF, ALL, ONE;

    val next: RepeatMode get() = when (this) {
        OFF -> ALL
        ALL -> ONE
        ONE -> OFF
    }
}

/** Una voce della coda: lo stesso brano può comparire più volte. */
data class QueueItem(val id: String = UUID.randomUUID().toString(), val trackId: String)

/**
 * Stato della coda, come valore immutabile senza dipendenze audio.
 *
 * - Brano corrente: [current].
 * - Coda corrente: [order], l'ordine effettivo.
 * - Ordine originale: [original], ripristinato spegnendo lo shuffle.
 * - Sorgente: [source], solo un'etichetta: la coda non tocca mai libreria o playlist.
 */
data class PlaybackQueue(
    val source: String = "",
    val original: List<QueueItem> = emptyList(),
    val order: List<QueueItem> = emptyList(),
    val index: Int = -1,
    val shuffled: Boolean = false,
    val repeat: RepeatMode = RepeatMode.OFF,
) {
    val current: QueueItem? get() = order.getOrNull(index)
    val upcoming: List<QueueItem> get() = if (index < 0) emptyList() else order.drop(index + 1)
    val isEmpty: Boolean get() = order.isEmpty()

    fun load(trackIds: List<String>, start: Int, source: String): PlaybackQueue {
        if (start !in trackIds.indices) return cleared()
        val items = trackIds.map { QueueItem(trackId = it) }
        val loaded = copy(source = source, original = items, order = items, index = start)
        return if (shuffled) loaded.shuffleAroundCurrent() else loaded
    }

    fun cleared(): PlaybackQueue = copy(source = "", original = emptyList(), order = emptyList(), index = -1)

    /** Allinea il brano corrente a quello scelto dal player. */
    fun at(itemId: String): PlaybackQueue {
        val position = order.indexOfFirst { it.id == itemId }
        return if (position >= 0) copy(index = position) else this
    }

    fun withShuffle(enabled: Boolean): PlaybackQueue {
        if (enabled == shuffled) return this
        if (enabled) return copy(shuffled = true).shuffleAroundCurrent()
        val item = current
        return copy(shuffled = false, order = original, index = original.indexOf(item))
    }

    /** Il brano corrente va in testa e tutto il resto viene mescolato. */
    private fun shuffleAroundCurrent(): PlaybackQueue {
        val item = current ?: return this
        val rest = (original - item).shuffled().toMutableList()
        if (rest.firstOrNull()?.trackId == item.trackId) {
            val alternative = rest.indexOfFirst { it.trackId != item.trackId }
            if (alternative > 0) rest[0] = rest[alternative].also { rest[alternative] = rest[0] }
        }
        return copy(order = listOf(item) + rest, index = 0)
    }

    fun appended(trackIds: List<String>): PlaybackQueue {
        if (trackIds.isEmpty()) return this
        val items = trackIds.map { QueueItem(trackId = it) }
        return copy(
            source = if (isEmpty) "Coda" else source,
            original = original + items,
            order = order + items,
            index = if (isEmpty) 0 else index,
        )
    }

    fun insertedNext(trackIds: List<String>): PlaybackQueue {
        val item = current ?: return appended(trackIds)
        val items = trackIds.map { QueueItem(trackId = it) }
        val position = original.indexOf(item) + 1
        return copy(
            order = order.take(index + 1) + items + order.drop(index + 1),
            original = original.take(position) + items + original.drop(position),
        )
    }

    /** Sposta una voce di [upcoming]. Durante lo shuffle cambia solo l'ordine mescolato. */
    fun movedUpcoming(from: Int, to: Int): PlaybackQueue {
        val list = upcoming.toMutableList()
        if (from !in list.indices || to !in list.indices) return this
        list.add(to, list.removeAt(from))
        val reordered = order.take(index + 1) + list
        return copy(order = reordered, original = if (shuffled) original else reordered)
    }

    fun without(itemId: String): PlaybackQueue = removing { it.id == itemId }

    fun withoutTracks(trackIds: Set<String>): PlaybackQueue = removing { it.trackId in trackIds }

    /** Se sparisce il brano corrente, il suo posto va a quello successivo. */
    private fun removing(predicate: (QueueItem) -> Boolean): PlaybackQueue {
        val kept = order.filterNot(predicate)
        val before = order.take(index.coerceAtLeast(0)).count(predicate)
        val newIndex = when {
            kept.isEmpty() -> -1
            else -> (index - before).coerceIn(0, kept.size - 1)
        }
        return copy(
            source = if (kept.isEmpty()) "" else source,
            original = original.filterNot(predicate),
            order = kept,
            index = newIndex,
        )
    }

    fun clearedExceptCurrent(): PlaybackQueue {
        val item = current ?: return cleared()
        return copy(source = "Coda", original = listOf(item), order = listOf(item), index = 0)
    }
}
