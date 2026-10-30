package com.dario.flacplayer

import com.dario.flacplayer.library.FileScanner
import com.dario.flacplayer.library.FlacFormatException
import com.dario.flacplayer.library.FlacMetadataReader
import com.dario.flacplayer.library.IgnoredFile
import com.dario.flacplayer.library.ScannedFile
import com.dario.flacplayer.library.TrackStore
import com.dario.flacplayer.library.UNKNOWN_ALBUM
import com.dario.flacplayer.library.UNKNOWN_ARTIST
import com.dario.flacplayer.library.sanitizedName
import com.dario.flacplayer.model.Track
import com.dario.flacplayer.model.TrackSort
import com.dario.flacplayer.model.groupAlbums
import com.dario.flacplayer.model.kilohertz
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

private class MemoryStore : TrackStore {
    val tracks = LinkedHashMap<String, Track>()
    val ignored = HashMap<String, IgnoredFile>()
    override fun allTracks() = tracks.values.toList()
    override fun trackWithHash(hash: String) = tracks.values.firstOrNull { it.contentHash == hash }
    override fun insert(track: Track) { tracks[track.id] = track }
    override fun update(track: Track) { tracks[track.id] = track }
    override fun setMissing(missing: Boolean, ids: List<String>) {
        ids.forEach { tracks[it] = tracks.getValue(it).copy(isMissing = missing) }
    }
    override fun ignoredFiles() = ignored.toMap()
    override fun setIgnored(path: String, file: IgnoredFile) { ignored[path] = file }
    override fun removeIgnored(path: String) { ignored.remove(path) }
}

class LibraryTest {
    @get:Rule val folder = TemporaryFolder()
    private val store = MemoryStore()
    private val scanner = FileScanner(store) { "cover" }

    private fun fixture(name: String) = File(javaClass.classLoader!!.getResource("Fixtures/$name")!!.toURI())
    private fun copy(name: String, target: String) =
        fixture(name).copyTo(File(folder.root, target).also { it.parentFile!!.mkdirs() })
    private fun files() = folder.root.walkTopDown().filter { it.isFile }.map { ScannedFile(it) }.toList()

    @Test fun readsAllTags() {
        val m = FlacMetadataReader.read(fixture("tagged_16_44100.flac"))
        assertEquals("Perché no", m.title)
        assertEquals("Àrtista", m.artist)
        assertEquals("Album di prova", m.album)
        assertEquals("Vari", m.albumArtist)
        assertEquals(3, m.trackNumber)
        assertEquals(1, m.discNumber)
        assertEquals("Jazz", m.genre)
        assertEquals("1999-05-01", m.date)
        assertEquals(44100, m.sampleRate)
        assertEquals(16, m.bitDepth)
        assertEquals(2, m.channels)
        assertEquals(22050, m.totalFrames)
        assertEquals(500, m.durationMs)
    }

    @Test fun readsCover() {
        val cover = FlacMetadataReader.read(fixture("tagged_16_44100.flac")).cover
        assertNotNull(cover)
        assertEquals(0x89.toByte(), cover!![0])
        assertEquals('P'.code.toByte(), cover[1])
    }

    @Test fun readsHighResolutionFormat() {
        val m = FlacMetadataReader.read(fixture("tagged_24_96000.flac"))
        assertEquals(96000, m.sampleRate)
        assertEquals(24, m.bitDepth)
        assertEquals(24000, m.totalFrames)
    }

    @Test fun missingTagsUseDefaults() {
        val m = FlacMetadataReader.read(fixture("untagged_24_96000.flac"))
        assertEquals("untagged_24_96000", m.title)
        assertEquals(UNKNOWN_ARTIST, m.artist)
        assertEquals(UNKNOWN_ALBUM, m.album)
        assertNull(m.cover)
    }

    @Test fun rejectsInvalidFile() {
        assertThrows(FlacFormatException::class.java) { FlacMetadataReader.read(fixture("not_a_flac.flac")) }
    }

    @Test fun scanAddsFiles() {
        copy("tagged_16_44100.flac", "brano.flac")
        copy("tagged_24_96000.flac", "Album/traccia.flac")
        assertEquals(2, scanner.scan(files()).added)
        assertEquals(2, store.tracks.size)
    }

    @Test fun secondScanChangesNothing() {
        copy("tagged_16_44100.flac", "brano.flac")
        scanner.scan(files())
        assertEquals(com.dario.flacplayer.library.ScanReport(), scanner.scan(files()))
    }

    @Test fun duplicateIsIgnoredThenTakesOverWhenOriginalDisappears() {
        copy("tagged_16_44100.flac", "a.flac")
        copy("tagged_16_44100.flac", "b.flac")
        assertEquals(1, scanner.scan(files()).duplicates)
        assertEquals(0, scanner.scan(files()).duplicates)

        val track = store.tracks.values.single()
        File(track.path).delete()
        scanner.scan(files())
        val updated = store.tracks.values.single()
        assertEquals(track.id, updated.id)
        assertTrue(File(updated.path).exists())
        assertFalse(updated.isMissing)
    }

    @Test fun movedFileKeepsIdentity() {
        val original = copy("tagged_16_44100.flac", "vecchio.flac")
        scanner.scan(files())
        val track = store.tracks.values.single()
        original.renameTo(File(folder.root, "nuovo.flac"))
        val report = scanner.scan(files())
        assertEquals(1, report.updated)
        assertEquals(track.id, store.tracks.values.single().id)
    }

    @Test fun deletedFileBecomesMissingAndReturns() {
        val file = copy("tagged_16_44100.flac", "brano.flac")
        scanner.scan(files())
        val id = store.tracks.values.single().id
        file.delete()
        assertEquals(1, scanner.scan(files()).newlyMissing)
        assertTrue(store.tracks.getValue(id).isMissing)
        copy("tagged_16_44100.flac", "tornato.flac")
        scanner.scan(files())
        assertFalse(store.tracks.getValue(id).isMissing)
    }

    @Test fun userRemovedFileStaysOut() {
        val file = copy("tagged_16_44100.flac", "brano.flac")
        store.setIgnored(file.path, IgnoredFile(file.length(), file.lastModified(), byUser = true))
        assertEquals(0, scanner.scan(files()).added)
    }

    @Test fun invalidFileIsReported() {
        copy("not_a_flac.flac", "rotto.flac")
        assertEquals(listOf("rotto.flac"), scanner.scan(files()).failed)
    }

    private fun track(title: String = "x", album: String = "A", artist: String = "B", disc: Int = 1, number: Int = 1) = Track(
        contentHash = title, path = title, fileSize = 0, modifiedAt = 0, title = title, artist = artist, album = album,
        albumArtist = artist, genre = "", date = "", trackNumber = number, discNumber = disc, durationMs = 0,
        sampleRate = 44100, bitDepth = 16, channels = 2, coverId = null,
    )

    @Test fun albumOrderFollowsDiscAndTrack() {
        val albums = groupAlbums(listOf(track("Z", number = 2), track("A", disc = 2), track("M")))
        assertEquals(listOf("M", "Z", "A"), albums.single().tracks.map { it.title })
    }

    @Test fun sameAlbumNameDifferentArtists() {
        assertEquals(2, groupAlbums(listOf(track(artist = "Uno"), track(artist = "Due"))).size)
    }

    @Test fun sortIsCaseInsensitive() {
        val sorted = TrackSort.TITLE.sorted(listOf(track("beta"), track("Alfa"), track("Gamma")))
        assertEquals(listOf("Alfa", "beta", "Gamma"), sorted.map { it.title })
    }

    @Test fun sanitizedNames() {
        assertEquals("AC DC  Live", sanitizedName("AC/DC: Live?"))
        assertEquals("Sconosciuto", sanitizedName("..."))
    }

    @Test fun kilohertzFormat() {
        assertEquals("44,1", kilohertz(44100))
        assertEquals("96", kilohertz(96000))
    }
}
