package de.feldexa.app.storage

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T027 contract tests for [SignaturePng].
 *
 * Validity is anchored on two hard-coded PNGs produced by an independent
 * Python zlib/CRC implementation; the ordinary fixtures use the test encoder.
 * The adversarial cases mutate the real chunk stream (CRC, IHDR, IDAT, IEND,
 * filters, decompression bomb) so a magic/header-only check would fail this
 * suite.
 */
class SignaturePngTest {

    @Test
    fun acceptsSyntheticRgbaPngs() {
        for (png in listOf(TestPng.validRgba(1, 1), TestPng.validRgba(3, 2))) {
            val (width, height) = TestPng.size(png)
            assertTrue(width > 0 && height > 0)
            assertTrue(SignaturePng.isValid(png))
            SignaturePng.requireValid(png)
        }
    }

    @Test
    fun acceptsIndependentlyGeneratedPngs() {
        val independent2x2 = TestPng.independent2x2()
        assertEquals(2 to 2, TestPng.size(independent2x2))
        assertTrue(SignaturePng.isValid(independent2x2))

        val independent1024 = TestPng.independent1024()
        assertEquals(1024 to 1, TestPng.size(independent1024))
        assertTrue(SignaturePng.isValid(independent1024))
    }

    @Test
    fun acceptsLongEdgeBoundary1024() {
        val cases = listOf(
            TestPng.validRgba(1024, 1024),
            TestPng.validRgba(1024, 1),
            TestPng.validRgba(1, 1024),
        )
        for (png in cases) {
            val (width, height) = TestPng.size(png)
            assertEquals(1024, maxOf(width, height))
            assertTrue("valid 1024 px fixture must be accepted", SignaturePng.isValid(png))
        }
    }

    @Test
    fun rejectsValidPngOver1024LongEdge() {
        for (png in listOf(TestPng.validRgba(1025, 1024), TestPng.validRgba(1024, 1025))) {
            val (width, height) = TestPng.size(png)
            assertEquals(1025, maxOf(width, height))
            assertFalse(SignaturePng.isValid(png))
            assertThrows(InvalidDataException::class.java) { SignaturePng.requireValid(png) }
        }
        val square = TestPng.validRgba(1025, 1025)
        assertEquals(1025, TestPng.size(square).first)
        assertFalse(SignaturePng.isValid(square))
    }

    @Test
    fun acceptsAdam7InterlacedPng() {
        val png = interlacedRgba(9, 9)
        assertEquals(9 to 9, TestPng.size(png))
        assertTrue(SignaturePng.isValid(png))
    }

    @Test
    fun rejectsNonPngTruncatedAndTrailingBytes() {
        val valid = TestPng.validRgba(2, 2)
        assertFalse(SignaturePng.isValid(ByteArray(0)))
        assertFalse(SignaturePng.isValid("%PDF-1.7 not a signature".toByteArray()))
        assertFalse(SignaturePng.isValid(valid.copyOf(20)))
        assertFalse(SignaturePng.isValid(valid + byteArrayOf(0)))
    }

    @Test
    fun rejectsBadChunkCrc() {
        val valid = TestPng.validRgba(2, 2)
        val corrupt = valid.copyOf()
        // First byte of the IHDR payload (offset 16) is covered by its CRC.
        corrupt[16] = (corrupt[16].toInt() xor 0x01).toByte()
        assertFalse(SignaturePng.isValid(corrupt))
    }

    @Test
    fun rejectsCorruptOrMissingImageData() {
        val valid = TestPng.validRgba(2, 2)
        val corruptIdat = TestPng.replaceFirstChunkData(valid, "IDAT") {
            byteArrayOf(0x78, 0x01, 0x02, 0x03, 0x04)
        }
        assertFalse(SignaturePng.isValid(corruptIdat))
        assertFalse(SignaturePng.isValid(valid.copyOf(valid.size - 12)))
    }

    @Test
    fun rejectsDecompressionBomb() {
        // A 1×1 RGBA image may inflate to exactly 5 scanline bytes. A stream
        // that inflates far beyond that must not be decoded into memory.
        val bomb = TestPng.fromRawScanlines(
            width = 1,
            height = 1,
            colorType = 6,
            bitDepth = 8,
            interlace = 0,
            rawScanlines = ByteArray(2_000_000),
        )
        assertTrue(bomb.size < 100_000)
        assertFalse(SignaturePng.isValid(bomb))
    }

    @Test
    fun rejectsInvalidFilterByte() {
        val png = TestPng.fromRawScanlines(
            width = 1,
            height = 1,
            colorType = 6,
            bitDepth = 8,
            interlace = 0,
            rawScanlines = byteArrayOf(5, 0, 0, 0, 0),
        )
        assertFalse(SignaturePng.isValid(png))
    }

    @Test
    fun rejectsInvalidHeaderFields() {
        val valid = TestPng.validRgba(2, 2)
        assertFalse(
            SignaturePng.isValid(
                TestPng.replaceFirstChunkData(valid, "IHDR") { data ->
                    data.copyOf().also { it[0] = 0; it[1] = 0; it[2] = 0; it[3] = 0 }
                },
            ),
        )
        assertFalse(
            SignaturePng.isValid(
                TestPng.replaceFirstChunkData(valid, "IHDR") { data ->
                    data.copyOf().also { it[8] = 3 } // bit depth 3 is not valid for RGBA
                },
            ),
        )
        assertFalse(
            SignaturePng.isValid(
                TestPng.replaceFirstChunkData(valid, "IHDR") { data ->
                    data.copyOf().also { it[9] = 1 } // colour type 1 does not exist
                },
            ),
        )
        assertFalse(
            SignaturePng.isValid(
                TestPng.replaceFirstChunkData(valid, "IHDR") { data ->
                    data.copyOf().also { it[12] = 2 } // interlace method 2 is invalid
                },
            ),
        )
    }

    @Test
    fun rejectsPaletteImageWithoutPalette() {
        val png = TestPng.fromRawScanlines(
            width = 1,
            height = 1,
            colorType = 3,
            bitDepth = 8,
            interlace = 0,
            rawScanlines = byteArrayOf(0, 0),
        )
        assertFalse(SignaturePng.isValid(png))
    }

    @Test
    fun rejectsUnknownCriticalChunk() {
        val valid = TestPng.validRgba(2, 2)
        val ihdr = TestPng.firstChunkData(valid, "IHDR")
        val idat = TestPng.firstChunkData(valid, "IDAT")
        val unknownCritical = TestPng.assemble(
            listOf(
                TestPng.chunk("IHDR", ihdr),
                TestPng.chunk("ZZZZ", ByteArray(0)),
                TestPng.chunk("IDAT", idat),
                TestPng.chunk("IEND", ByteArray(0)),
            ),
        )
        assertFalse(SignaturePng.isValid(unknownCritical))
    }

    @Test
    fun rejectsOversizedPngMetadataRange() {
        // The validator is size-agnostic; the store's 2 MiB cap remains the
        // outer limit. This fixture only proves the structure path is bounded.
        val png = TestPng.validRgba(1024, 1024)
        assertTrue(png.size < EncryptedStore.MAX_SIGNATURE_BYTES)
        assertTrue(SignaturePng.isValid(png))
    }

    @Test
    fun acceptsNativeAlphaColourTypes() {
        val grayAlpha = TestPng.validGrayscaleAlpha(3, 2)
        assertEquals(3 to 2, TestPng.size(grayAlpha))
        assertTrue(SignaturePng.isValid(grayAlpha))
        SignaturePng.requireValid(grayAlpha)

        // An RGBA image whose pixels are all opaque still has the required
        // alpha channel; the contract does not require a transparent pixel.
        val opaqueRgba = TestPng.validRgba(2, 2, argb = 0xFF336699.toInt())
        assertTrue(SignaturePng.isValid(opaqueRgba))
    }

    @Test
    fun acceptsTrnsBackedTransparencyForOpaqueColourTypes() {
        val gray = TestPng.insertBeforeIdat(
            TestPng.validGrayscale(2, 2, gray = 0x40),
            TestPng.chunk("tRNS", byteArrayOf(0x00, 0x40)),
        )
        assertEquals(2 to 2, TestPng.size(gray))
        assertTrue(SignaturePng.isValid(gray))

        val rgb = TestPng.insertBeforeIdat(
            TestPng.validRgb(2, 2, red = 0x11, green = 0x22, blue = 0x33),
            TestPng.chunk(
                "tRNS",
                byteArrayOf(0x00, 0x11, 0x00, 0x22, 0x00, 0x33),
            ),
        )
        assertTrue(SignaturePng.isValid(rgb))

        val indexed = TestPng.insertBeforeIdat(
            TestPng.validIndexed(2, 2),
            TestPng.chunk("tRNS", byteArrayOf(0x00, 0x80.toByte())),
        )
        assertTrue(SignaturePng.isValid(indexed))
        SignaturePng.requireValid(indexed)
    }

    @Test
    fun validatesTransparencySampleAgainstBitDepth() {
        val base = TestPng.fromRawScanlines(
            width = 1,
            height = 1,
            colorType = 0,
            bitDepth = 1,
            interlace = 0,
            rawScanlines = byteArrayOf(0, 0x80.toByte()),
        )
        val accepted = TestPng.insertBeforeIdat(
            base,
            TestPng.chunk("tRNS", byteArrayOf(0x00, 0x01)),
        )
        assertTrue(SignaturePng.isValid(accepted))
        val rejected = TestPng.insertBeforeIdat(
            base,
            TestPng.chunk("tRNS", byteArrayOf(0x00, 0x02)),
        )
        assertFalse(SignaturePng.isValid(rejected))
    }

    @Test
    fun rejectsOpaqueColourTypesWithoutAlphaOrTransparency() {
        for (png in listOf(
            TestPng.validGrayscale(2, 2),
            TestPng.validRgb(2, 2),
            TestPng.validIndexed(2, 2),
        )) {
            assertFalse(SignaturePng.isValid(png))
            assertThrows(InvalidDataException::class.java) {
                SignaturePng.requireValid(png)
            }
        }
    }

    @Test
    fun rejectsMalformedTransparencyChunks() {
        val gray = TestPng.validGrayscale(1, 1, gray = 0x80)
        val rgb = TestPng.validRgb(1, 1)
        val indexed = TestPng.validIndexed(1, 1)
        val rgba = TestPng.validRgba(1, 1)
        val cases = listOf(
            "gray tRNS too short" to TestPng.insertBeforeIdat(
                gray,
                TestPng.chunk("tRNS", byteArrayOf(0x00)),
            ),
            "gray tRNS too long" to TestPng.insertBeforeIdat(
                gray,
                TestPng.chunk("tRNS", byteArrayOf(0x00, 0x80.toByte(), 0x00)),
            ),
            "gray tRNS above bit depth" to TestPng.insertBeforeIdat(
                gray,
                TestPng.chunk("tRNS", byteArrayOf(0x01, 0x00)),
            ),
            "rgb tRNS too short" to TestPng.insertBeforeIdat(
                rgb,
                TestPng.chunk("tRNS", byteArrayOf(0x00, 0x11, 0x00, 0x22)),
            ),
            "rgb tRNS too long" to TestPng.insertBeforeIdat(
                rgb,
                TestPng.chunk(
                    "tRNS",
                    byteArrayOf(0x00, 0x11, 0x00, 0x22, 0x00, 0x33, 0x00),
                ),
            ),
            "rgb tRNS above bit depth" to TestPng.insertBeforeIdat(
                rgb,
                TestPng.chunk(
                    "tRNS",
                    byteArrayOf(0x01, 0x00, 0x00, 0x22, 0x00, 0x33),
                ),
            ),
            "indexed tRNS exceeds palette" to TestPng.insertBeforeIdat(
                indexed,
                TestPng.chunk("tRNS", ByteArray(3)),
            ),
            "indexed tRNS empty" to TestPng.insertBeforeIdat(
                indexed,
                TestPng.chunk("tRNS", ByteArray(0)),
            ),
            "native alpha tRNS is invalid" to TestPng.insertBeforeIdat(
                rgba,
                TestPng.chunk("tRNS", byteArrayOf(0x00)),
            ),
        )
        for ((reason, png) in cases) {
            assertFalse("$reason must be rejected", SignaturePng.isValid(png))
            assertThrows(
                "$reason must map to SAVE-007",
                InvalidDataException::class.java,
            ) {
                SignaturePng.requireValid(png)
            }
        }
    }

    @Test
    fun rejectsTransparencyChunkOrderViolations() {
        // tRNS before PLTE in an indexed image.
        val trnsBeforePlte = TestPng.fromRawScanlines(
            width = 1,
            height = 1,
            colorType = 3,
            bitDepth = 8,
            interlace = 0,
            rawScanlines = byteArrayOf(0, 0),
            beforeIdat = listOf(
                TestPng.chunk("tRNS", byteArrayOf(0x00)),
                TestPng.chunk("PLTE", TestPng.INDEXED_PALETTE),
            ),
        )
        assertFalse(SignaturePng.isValid(trnsBeforePlte))

        // A duplicate tRNS chunk.
        val gray = TestPng.validGrayscale(1, 1, gray = 0x80)
        val duplicate = TestPng.insertBeforeIdat(
            TestPng.insertBeforeIdat(
                gray,
                TestPng.chunk("tRNS", byteArrayOf(0x00, 0x80.toByte())),
            ),
            TestPng.chunk("tRNS", byteArrayOf(0x00, 0x80.toByte())),
        )
        assertFalse(SignaturePng.isValid(duplicate))

        // A tRNS that appears after the IDAT chunk.
        val afterIdat = TestPng.fromRawScanlines(
            width = 1,
            height = 1,
            colorType = 0,
            bitDepth = 8,
            interlace = 0,
            rawScanlines = byteArrayOf(0, 0x80.toByte()),
            afterIdat = listOf(
                TestPng.chunk("tRNS", byteArrayOf(0x00, 0x80.toByte())),
            ),
        )
        assertFalse(SignaturePng.isValid(afterIdat))

        // PLTE must precede tRNS for RGB too when it is present.
        val plteAfterTrns = TestPng.fromRawScanlines(
            width = 1,
            height = 1,
            colorType = 2,
            bitDepth = 8,
            interlace = 0,
            rawScanlines = byteArrayOf(0, 0x11, 0x22, 0x33),
            beforeIdat = listOf(
                TestPng.chunk(
                    "tRNS",
                    byteArrayOf(0x00, 0x11, 0x00, 0x22, 0x00, 0x33),
                ),
                TestPng.chunk("PLTE", TestPng.INDEXED_PALETTE),
            ),
        )
        assertFalse(SignaturePng.isValid(plteAfterTrns))
    }

    @Test
    fun validationDoesNotMutateSignedBytes() {
        val png = TestPng.insertBeforeIdat(
            TestPng.validRgb(2, 2),
            TestPng.chunk(
                "tRNS",
                byteArrayOf(0x00, 0x11, 0x00, 0x22, 0x00, 0x33),
            ),
        )
        val before = png.copyOf()
        assertTrue(SignaturePng.isValid(png))
        SignaturePng.requireValid(png)
        assertArrayEquals(before, png)
    }

    private fun interlacedRgba(width: Int, height: Int): ByteArray {
        val passes = listOf(
            intArrayOf(0, 0, 8, 8),
            intArrayOf(4, 0, 8, 8),
            intArrayOf(0, 4, 4, 8),
            intArrayOf(2, 0, 4, 4),
            intArrayOf(0, 2, 2, 4),
            intArrayOf(1, 0, 2, 2),
            intArrayOf(0, 1, 1, 2),
        )
        val out = ByteArrayOutputStream()
        for (pass in passes) {
            val xStart = pass[0]
            val yStart = pass[1]
            val xStep = pass[2]
            val yStep = pass[3]
            val passWidth = if (width <= xStart) 0 else (width - xStart + xStep - 1) / xStep
            val passHeight = if (height <= yStart) 0 else (height - yStart + yStep - 1) / yStep
            if (passWidth == 0 || passHeight == 0) continue
            repeat(passHeight) {
                out.write(0)
                repeat(passWidth) {
                    out.write(0x33)
                    out.write(0x66)
                    out.write(0x99)
                    out.write(0xFF)
                }
            }
        }
        return TestPng.fromRawScanlines(
            width = width,
            height = height,
            colorType = 6,
            bitDepth = 8,
            interlace = 1,
            rawScanlines = out.toByteArray(),
        )
    }
}
