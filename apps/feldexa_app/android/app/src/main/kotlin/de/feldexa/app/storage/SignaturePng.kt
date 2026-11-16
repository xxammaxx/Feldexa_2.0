package de.feldexa.app.storage

import java.util.zip.CRC32
import java.util.zip.Inflater

/**
 * T027 signature-PNG validation for `contracts/platform-channel.md` §10 and
 * `data-model.md` §3.7.
 *
 * The channel caps a signature at 2 MiB, but a size/hash check alone accepts
 * arbitrary bytes and PNG headers with absurd dimensions. This validator
 * therefore parses the real chunk stream, verifies every chunk CRC, enforces
 * the IHDR fields and the 1024 px long-edge rule, inflates the complete IDAT
 * stream into a buffer sized from the already-bounded dimensions, and
 * unfilters every scanline (including Adam7). It never trusts only the magic
 * or the header: truncated, corrupt, wrong-colour-type, and over-long
 * compressed streams are rejected before any signature object is staged.
 *
 * Memory is bounded by the accepted dimensions, not by the compressed size:
 * at most 1024 × 1024 pixels and 16 bits per channel, so the decoded scanline
 * buffer stays below 9 MiB and the 2 MiB input cap is unchanged. The
 * [Inflater] output buffer is sized to the exact expected scanline total, so
 * an IDAT decompression bomb cannot expand beyond it.
 */
internal object SignaturePng {
    /** `data-model.md` §3.7 and `contracts/platform-channel.md` §10. */
    const val MAX_LONG_EDGE_PX: Int = 1024

    private val MAGIC = byteArrayOf(
        0x89.toByte(),
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
    )

    /** Bound on the decoded scanline buffer; 1024² × 16-bit RGBA is < 8.4 MiB. */
    private const val MAX_RAW_BYTES: Long = 16L * 1024L * 1024L

    /**
     * Rejects anything that is not a structurally valid, fully decodable PNG
     * whose width and height are positive and whose long edge is at most
     * [MAX_LONG_EDGE_PX]. The canonical failure is `SAVE-007`.
     */
    fun requireValid(pngBytes: ByteArray) {
        validate(pngBytes) ?: throw InvalidDataException()
    }

    /**
     * Returns true only for a valid PNG within the contract limits. Kept
     * separate from [requireValid] so the tests can exercise every rejection
     * without catching storage exceptions.
     */
    fun isValid(pngBytes: ByteArray): Boolean = validate(pngBytes) != null

    private fun validate(pngBytes: ByteArray): Unit? {
        if (pngBytes.size < MAGIC.size + 12) return null
        for (index in MAGIC.indices) {
            if (pngBytes[index] != MAGIC[index]) return null
        }

        var offset = MAGIC.size
        var sawIhdr = false
        var sawIdat = false
        var sawIend = false
        var idatClosed = false
        var sawPalette = false
        var widthPx = 0L
        var heightPx = 0L
        var bitDepth = 0
        var colorType = 0
        var interlace = 0
        val idatChunks = ArrayList<ByteArray>()

        while (offset < pngBytes.size) {
            if (pngBytes.size - offset < 12) return null
            val length = readU32(pngBytes, offset)
            if (length > Int.MAX_VALUE.toLong()) return null
            val dataStart = offset + 8
            if (length > (pngBytes.size - dataStart - 4).toLong()) return null
            val dataEnd = dataStart + length.toInt()
            val type = String(pngBytes, offset + 4, 4, Charsets.ISO_8859_1)
            if (!isChunkType(type)) return null
            if (!crcMatches(pngBytes, offset + 4, dataEnd, readU32(pngBytes, dataEnd))) {
                return null
            }

            when (type) {
                "IHDR" -> {
                    if (sawIhdr || offset != MAGIC.size || length != 13L) return null
                    sawIhdr = true
                    widthPx = readU32(pngBytes, dataStart)
                    heightPx = readU32(pngBytes, dataStart + 4)
                    if (widthPx <= 0L || heightPx <= 0L) return null
                    if (widthPx > MAX_LONG_EDGE_PX || heightPx > MAX_LONG_EDGE_PX) return null
                    bitDepth = pngBytes[dataStart + 8].toInt() and 0xFF
                    colorType = pngBytes[dataStart + 9].toInt() and 0xFF
                    if (!validColorType(colorType, bitDepth)) return null
                    if (pngBytes[dataStart + 10].toInt() != 0) return null
                    if (pngBytes[dataStart + 11].toInt() != 0) return null
                    interlace = pngBytes[dataStart + 12].toInt() and 0xFF
                    if (interlace != 0 && interlace != 1) return null
                }

                "PLTE" -> {
                    if (!sawIhdr || sawIdat || sawPalette) return null
                    if (colorType == 0 || colorType == 4) return null
                    if (length <= 0L || length % 3L != 0L || length > 768L) return null
                    val entries = length / 3L
                    if (colorType == 3 && entries > (1L shl bitDepth)) return null
                    sawPalette = true
                }

                "IDAT" -> {
                    if (!sawIhdr || idatClosed) return null
                    sawIdat = true
                    idatChunks += pngBytes.copyOfRange(dataStart, dataEnd)
                }

                "IEND" -> {
                    if (length != 0L || !sawIdat) return null
                    sawIend = true
                    offset = dataEnd + 4
                    if (offset != pngBytes.size) return null
                    break
                }

                else -> {
                    // Unknown critical chunks cannot be ignored. Ancillary
                    // chunks are CRC-checked above and otherwise opaque.
                    if (type[0].isUpperCase()) return null
                }
            }

            if (sawIdat && type != "IDAT" && type != "IEND") idatClosed = true
            offset = dataEnd + 4
        }

        if (!sawIhdr || !sawIdat || !sawIend) return null
        if (colorType == 3 && !sawPalette) return null
        return decodeIdat(
            idatChunks = idatChunks,
            widthPx = widthPx,
            heightPx = heightPx,
            bitDepth = bitDepth,
            colorType = colorType,
            interlace = interlace,
        )
    }

    private fun decodeIdat(
        idatChunks: List<ByteArray>,
        widthPx: Long,
        heightPx: Long,
        bitDepth: Int,
        colorType: Int,
        interlace: Int,
    ): Unit? {
        if (idatChunks.isEmpty()) return null
        val compressedSize = idatChunks.sumOf { it.size.toLong() }
        if (compressedSize <= 0L || compressedSize > Int.MAX_VALUE.toLong()) return null
        val compressed = ByteArray(compressedSize.toInt())
        var compressedOffset = 0
        for (chunk in idatChunks) {
            System.arraycopy(chunk, 0, compressed, compressedOffset, chunk.size)
            compressedOffset += chunk.size
        }

        val bitsPerPixel = channelsFor(colorType) * bitDepth
        if (bitsPerPixel <= 0) return null
        val rawSize = expectedRawSize(widthPx, heightPx, bitsPerPixel, interlace)
        if (rawSize <= 0L || rawSize > MAX_RAW_BYTES || rawSize > Int.MAX_VALUE.toLong()) return null
        val raw = ByteArray(rawSize.toInt())

        val inflater = Inflater()
        var written = 0
        try {
            inflater.setInput(compressed)
            while (true) {
                if (written == raw.size) {
                    val overflow = ByteArray(1)
                    val extra = inflater.inflate(overflow)
                    if (extra > 0 || !inflater.finished() || inflater.remaining != 0) return null
                    break
                }
                val count = inflater.inflate(raw, written, raw.size - written)
                if (count > 0) {
                    written += count
                    continue
                }
                if (inflater.finished()) {
                    if (written != raw.size) return null
                    break
                }
                if (inflater.needsDictionary()) return null
                if (inflater.needsInput()) return null
                return null
            }
        } catch (failure: Exception) {
            return null
        } finally {
            inflater.end()
        }
        if (written != raw.size) return null

        var cursor = 0
        if (interlace == 0) {
            cursor = validatePass(
                raw = raw,
                offset = cursor,
                widthPx = widthPx,
                heightPx = heightPx,
                bitsPerPixel = bitsPerPixel,
            ) ?: return null
        } else {
            for (pass in ADAM7) {
                val passWidth = passWidth(widthPx, pass.xStart, pass.xStep)
                val passHeight = passHeight(heightPx, pass.yStart, pass.yStep)
                if (passWidth == 0L || passHeight == 0L) continue
                cursor = validatePass(
                    raw = raw,
                    offset = cursor,
                    widthPx = passWidth,
                    heightPx = passHeight,
                    bitsPerPixel = bitsPerPixel,
                ) ?: return null
            }
        }
        return if (cursor == raw.size) Unit else null
    }

    private fun validatePass(
        raw: ByteArray,
        offset: Int,
        widthPx: Long,
        heightPx: Long,
        bitsPerPixel: Int,
    ): Int? {
        val rowBytes = rowBytes(widthPx, bitsPerPixel)
        if (rowBytes <= 0L || rowBytes > Int.MAX_VALUE.toLong()) return null
        val rowSize = rowBytes.toInt()
        var cursor = offset
        var prior = ByteArray(rowSize)
        var current = ByteArray(rowSize)
        val filterBpp = ((bitsPerPixel + 7) / 8).coerceAtLeast(1)
        repeat(heightPx.toInt()) {
            if (cursor >= raw.size) return null
            val filter = raw[cursor].toInt() and 0xFF
            cursor += 1
            if (cursor + rowSize > raw.size) return null
            System.arraycopy(raw, cursor, current, 0, rowSize)
            cursor += rowSize
            when (filter) {
                0 -> Unit
                1 -> for (index in filterBpp until rowSize) {
                    current[index] = (current[index] + current[index - filterBpp]).toByte()
                }
                2 -> for (index in 0 until rowSize) {
                    current[index] = (current[index] + prior[index]).toByte()
                }
                3 -> for (index in 0 until rowSize) {
                    val left = if (index >= filterBpp) {
                        current[index - filterBpp].toInt() and 0xFF
                    } else {
                        0
                    }
                    val above = prior[index].toInt() and 0xFF
                    current[index] = (current[index] + ((left + above) / 2)).toByte()
                }
                4 -> for (index in 0 until rowSize) {
                    val left = if (index >= filterBpp) {
                        current[index - filterBpp].toInt() and 0xFF
                    } else {
                        0
                    }
                    val above = prior[index].toInt() and 0xFF
                    val aboveLeft = if (index >= filterBpp) {
                        prior[index - filterBpp].toInt() and 0xFF
                    } else {
                        0
                    }
                    current[index] = (current[index] + paeth(left, above, aboveLeft)).toByte()
                }
                else -> return null
            }
            val swap = prior
            prior = current
            current = swap
        }
        return cursor
    }

    private fun paeth(left: Int, above: Int, aboveLeft: Int): Int {
        val estimate = left + above - aboveLeft
        val distanceLeft = kotlin.math.abs(estimate - left)
        val distanceAbove = kotlin.math.abs(estimate - above)
        val distanceAboveLeft = kotlin.math.abs(estimate - aboveLeft)
        return when {
            distanceLeft <= distanceAbove && distanceLeft <= distanceAboveLeft -> left
            distanceAbove <= distanceAboveLeft -> above
            else -> aboveLeft
        }
    }

    private fun expectedRawSize(
        widthPx: Long,
        heightPx: Long,
        bitsPerPixel: Int,
        interlace: Int,
    ): Long {
        if (interlace == 0) {
            return (rowBytes(widthPx, bitsPerPixel) + 1L) * heightPx
        }
        var total = 0L
        for (pass in ADAM7) {
            val passWidth = passWidth(widthPx, pass.xStart, pass.xStep)
            val passHeight = passHeight(heightPx, pass.yStart, pass.yStep)
            if (passWidth == 0L || passHeight == 0L) continue
            total += (rowBytes(passWidth, bitsPerPixel) + 1L) * passHeight
        }
        return total
    }

    private fun rowBytes(widthPx: Long, bitsPerPixel: Int): Long =
        (widthPx * bitsPerPixel.toLong() + 7L) / 8L

    private fun passWidth(widthPx: Long, start: Long, step: Long): Long =
        if (widthPx <= start) 0L else (widthPx - start + step - 1L) / step

    private fun passHeight(heightPx: Long, start: Long, step: Long): Long =
        if (heightPx <= start) 0L else (heightPx - start + step - 1L) / step

    private fun channelsFor(colorType: Int): Int = when (colorType) {
        0 -> 1
        2 -> 3
        3 -> 1
        4 -> 2
        6 -> 4
        else -> 0
    }

    private fun validColorType(colorType: Int, bitDepth: Int): Boolean = when (colorType) {
        0 -> bitDepth in setOf(1, 2, 4, 8, 16)
        2 -> bitDepth in setOf(8, 16)
        3 -> bitDepth in setOf(1, 2, 4, 8)
        4 -> bitDepth in setOf(8, 16)
        6 -> bitDepth in setOf(8, 16)
        else -> false
    }

    private fun isChunkType(type: String): Boolean =
        type.length == 4 && type.all { it in 'A'..'Z' || it in 'a'..'z' }

    private fun crcMatches(bytes: ByteArray, start: Int, end: Int, expected: Long): Boolean {
        val crc = CRC32()
        crc.update(bytes, start, end - start)
        return crc.value == expected
    }

    private fun readU32(bytes: ByteArray, offset: Int): Long {
        if (offset < 0 || bytes.size - offset < 4) return -1L
        return ((bytes[offset].toLong() and 0xFFL) shl 24) or
            ((bytes[offset + 1].toLong() and 0xFFL) shl 16) or
            ((bytes[offset + 2].toLong() and 0xFFL) shl 8) or
            (bytes[offset + 3].toLong() and 0xFFL)
    }

    private data class Adam7Pass(
        val xStart: Long,
        val yStart: Long,
        val xStep: Long,
        val yStep: Long,
    )

    private val ADAM7 = listOf(
        Adam7Pass(0L, 0L, 8L, 8L),
        Adam7Pass(4L, 0L, 8L, 8L),
        Adam7Pass(0L, 4L, 4L, 8L),
        Adam7Pass(2L, 0L, 4L, 4L),
        Adam7Pass(0L, 2L, 2L, 4L),
        Adam7Pass(1L, 0L, 2L, 2L),
        Adam7Pass(0L, 1L, 1L, 2L),
    )
}
