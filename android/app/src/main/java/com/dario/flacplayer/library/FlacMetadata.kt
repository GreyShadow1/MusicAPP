package com.dario.flacplayer.library

import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

class FlacFormatException(message: String) : IOException(message)

const val UNKNOWN_ARTIST = "Artista sconosciuto"
const val UNKNOWN_ALBUM = "Album sconosciuto"

data class FlacMetadata(
    val title: String,
    val artist: String,
    val album: String,
    val albumArtist: String,
    val genre: String,
    val date: String,
    val trackNumber: Int,
    val discNumber: Int,
    val sampleRate: Int,
    val channels: Int,
    val bitDepth: Int,
    val totalFrames: Long,
    val cover: ByteArray?,
) {
    val durationMs: Long get() = if (sampleRate > 0) totalFrames * 1000 / sampleRate else 0
}

/** Lettore dei blocchi di metadati FLAC (RFC 9639), senza decodificare l'audio. */
object FlacMetadataReader {
    private const val STREAMINFO = 0
    private const val VORBIS_COMMENT = 4
    private const val PICTURE = 6
    private const val FRONT_COVER = 3
    private const val MAX_BLOCK = 1 shl 24

    fun read(file: File): FlacMetadata {
        RandomAccessFile(file, "r").use { input ->
            skipId3(input)
            val magic = ByteArray(4)
            if (input.read(magic) != 4 || String(magic, Charsets.ISO_8859_1) != "fLaC") {
                throw FlacFormatException("Il file non è un FLAC valido oppure è danneggiato.")
            }

            var sampleRate = 0
            var channels = 0
            var bitDepth = 0
            var totalFrames = 0L
            val tags = LinkedHashMap<String, MutableList<String>>()
            var cover: ByteArray? = null
            var coverIsFront = false

            while (true) {
                val header = input.read()
                if (header < 0) throw FlacFormatException("Il file FLAC è incompleto.")
                val b1 = input.read()
                val b2 = input.read()
                val b3 = input.read()
                if (b3 < 0) throw FlacFormatException("Il file FLAC è incompleto.")
                val length = (b1 shl 16) or (b2 shl 8) or b3
                val type = header and 0x7F
                val next = input.filePointer + length

                when (type) {
                    STREAMINFO -> {
                        if (length < 34) throw FlacFormatException("Intestazione FLAC non valida.")
                        val data = readBytes(input, length)
                        val packed = ByteBuffer.wrap(data, 10, 8).long
                        sampleRate = (packed ushr 44).toInt() and 0xFFFFF
                        channels = ((packed ushr 41).toInt() and 0x7) + 1
                        bitDepth = ((packed ushr 36).toInt() and 0x1F) + 1
                        totalFrames = packed and 0xFFFFFFFFFL
                    }
                    VORBIS_COMMENT -> parseComments(readBytes(input, length), tags)
                    PICTURE -> {
                        val (pictureType, bytes) = parsePicture(readBytes(input, length)) ?: (0 to null)
                        val isFront = pictureType == FRONT_COVER
                        if (bytes != null && (cover == null || (isFront && !coverIsFront))) {
                            cover = bytes
                            coverIsFront = isFront
                        }
                    }
                }
                input.seek(next)
                if (header and 0x80 != 0) break
            }
            if (sampleRate == 0) throw FlacFormatException("Intestazione FLAC non valida.")

            val artist = joined(tags["ARTIST"])
            val albumArtist = joined(tags["ALBUMARTIST"] ?: tags["ALBUM ARTIST"])
            return FlacMetadata(
                title = joined(tags["TITLE"]) ?: file.nameWithoutExtension,
                artist = artist ?: albumArtist ?: UNKNOWN_ARTIST,
                album = joined(tags["ALBUM"]) ?: UNKNOWN_ALBUM,
                albumArtist = albumArtist ?: artist ?: UNKNOWN_ARTIST,
                genre = joined(tags["GENRE"]) ?: "",
                date = tags["DATE"]?.first() ?: tags["YEAR"]?.first() ?: "",
                trackNumber = leadingNumber(tags["TRACKNUMBER"]?.first()),
                discNumber = leadingNumber(tags["DISCNUMBER"]?.first()),
                sampleRate = sampleRate,
                channels = channels,
                bitDepth = bitDepth,
                totalFrames = totalFrames,
                cover = cover,
            )
        }
    }

    private fun skipId3(input: RandomAccessFile) {
        val header = ByteArray(10)
        if (input.read(header) == 10 && String(header, 0, 3, Charsets.ISO_8859_1) == "ID3") {
            val size = (header[6].toInt() and 0x7F shl 21) or (header[7].toInt() and 0x7F shl 14) or
                (header[8].toInt() and 0x7F shl 7) or (header[9].toInt() and 0x7F)
            input.seek(10L + size)
        } else {
            input.seek(0)
        }
    }

    private fun readBytes(input: RandomAccessFile, length: Int): ByteArray {
        if (length > MAX_BLOCK || input.filePointer + length > input.length()) {
            throw FlacFormatException("Il file FLAC è incompleto.")
        }
        return ByteArray(length).also(input::readFully)
    }

    private fun parseComments(data: ByteArray, tags: MutableMap<String, MutableList<String>>) {
        val buffer = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
        try {
            skip(buffer, length(buffer))
            repeat(length(buffer)) {
                val bytes = ByteArray(length(buffer))
                buffer.get(bytes)
                val entry = String(bytes, Charsets.UTF_8)
                val separator = entry.indexOf('=')
                if (separator > 0) {
                    val value = entry.substring(separator + 1).trim()
                    if (value.isNotEmpty()) {
                        tags.getOrPut(entry.substring(0, separator).uppercase()) { mutableListOf() }.add(value)
                    }
                }
            }
        } catch (_: RuntimeException) {
            // Tag danneggiati: si tiene ciò che è stato letto finora.
        }
    }

    private fun parsePicture(data: ByteArray): Pair<Int, ByteArray>? = try {
        val buffer = ByteBuffer.wrap(data)
        val type = buffer.int
        skip(buffer, length(buffer))
        skip(buffer, length(buffer))
        skip(buffer, 16)
        val bytes = ByteArray(length(buffer))
        buffer.get(bytes)
        type to bytes
    } catch (_: RuntimeException) {
        null
    }

    /** Legge una lunghezza; se supera i dati rimasti il blocco è danneggiato. */
    private fun length(buffer: ByteBuffer): Int {
        val value = buffer.int
        if (value < 0 || value > buffer.remaining()) throw IllegalArgumentException("Lunghezza non valida")
        return value
    }

    private fun skip(buffer: ByteBuffer, count: Int) {
        buffer.position(buffer.position() + count)
    }

    private fun joined(values: List<String>?): String? = values?.joinToString(", ")

    /** "3/12" → 3. */
    private fun leadingNumber(value: String?): Int =
        value?.takeWhile(Char::isDigit)?.toIntOrNull() ?: 0
}
