package de.feldexa.app.ocr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * T263 correction-2 host-JVM tests for [SkewCorrection].
 *
 * RED at the pre-fix baseline: the pipeline had no deskew stage
 * (`correctionFor` returned no correction for every raster), so a three-degree
 * rotated raster reached the recognizer tilted and the resulting line boxes were
 * too tall to be associated — T263 EMULATOR `scan-200dpi-skew-3deg`, CER
 * 48.48 %, 30/51 lines associated. These tests are `NONE`-class evidence: pure
 * raster math on the host JVM, no ML Kit, no Android `Bitmap`, no emulator.
 */
class SkewCorrectionTest {

    /** White page with [bars] horizontal dark bars. */
    private fun uprightPage(width: Int, height: Int, bars: Int = 24): ByteArray {
        val gray = ByteArray(width * height) { 0xFF.toByte() }
        val barHeight = 4
        val spacing = height / bars
        for (bar in 0 until bars) {
            val top = bar * spacing + spacing / 2
            for (y in top until minOf(top + barHeight, height)) {
                for (x in width / 8 until width * 7 / 8) {
                    gray[y * width + x] = 0
                }
            }
        }
        return gray
    }

    /** Independent row-alignment score: sum of squared row-ink counts. */
    private fun rowAlignment(gray: ByteArray, width: Int, height: Int): Double {
        val bins = IntArray(height)
        for (y in 0 until height) {
            for (x in 0 until width) {
                if ((gray[y * width + x].toInt() and 0xFF) < 160) bins[y]++
            }
        }
        return bins.sumOf { it.toDouble() * it.toDouble() }
    }

    @Test
    fun uprightPageIsNotRotated() {
        val gray = uprightPage(400, 600)
        assertEquals(0.0, SkewCorrection.correctionFor(gray, 400, 600), 1e-9)
    }

    @Test
    fun emptyPageIsNotRotated() {
        val blank = ByteArray(200 * 200) { 0xFF.toByte() }
        assertEquals(0.0, SkewCorrection.correctionFor(blank, 200, 200), 1e-9)
    }

    @Test
    fun estimatedCorrectionDeskewsARotatedPage() {
        val width = 400
        val height = 600
        val base = uprightPage(width, height)
        val rotated = SkewCorrection.rotate(base, width, height, 3.0)
        val correction = SkewCorrection.correctionFor(rotated, width, height)

        // The returned correction must have the true magnitude ...
        assertTrue(
            "expected about three degrees, got $correction",
            abs(abs(correction) - 3.0) <= 0.75,
        )
        // ... and applying it must actually improve row alignment.
        val deskewed = SkewCorrection.rotate(rotated, width, height, correction)
        val before = rowAlignment(rotated, width, height)
        val after = rowAlignment(deskewed, width, height)
        assertTrue(
            "deskew must improve row alignment (before=$before after=$after)",
            after > before * 1.05,
        )
    }

    @Test
    fun correctionIsSymmetricForBothRotationDirections() {
        val width = 360
        val height = 480
        val base = uprightPage(width, height)
        for (applied in doubleArrayOf(-3.0, 3.0)) {
            val rotated = SkewCorrection.rotate(base, width, height, applied)
            val correction = SkewCorrection.correctionFor(rotated, width, height)
            val deskewed = SkewCorrection.rotate(rotated, width, height, correction)
            assertTrue(
                "applied=$applied correction=$correction",
                rowAlignment(deskewed, width, height) >
                    rowAlignment(rotated, width, height),
            )
        }
    }

    @Test
    fun mapRectBackIsTheIdentityWithoutCorrection() {
        val rect = OcrRasterRect(10, 20, 30, 60)
        assertEquals(rect, SkewCorrection.mapRectBack(rect, 400, 600, 0.0))
    }

    @Test
    fun mapRectBackKeepsACentredRectAndGrowsAnOffCentreOne() {
        val width = 400
        val height = 600
        // A rectangle centred on the raster centre stays centred; the
        // axis-aligned box may grow by a pixel or two because the corners move.
        val centred = OcrRasterRect(190, 290, 210, 310)
        val mappedCentred = SkewCorrection.mapRectBack(centred, width, height, 3.0)
        assertTrue(abs(mappedCentred.left - centred.left) <= 2)
        assertTrue(abs(mappedCentred.right - centred.right) <= 2)
        assertTrue(abs(mappedCentred.top - centred.top) <= 2)
        assertTrue(abs(mappedCentred.bottom - centred.bottom) <= 2)

        val offCentre = OcrRasterRect(300, 100, 340, 120)
        val mapped = SkewCorrection.mapRectBack(offCentre, width, height, 3.0)
        assertTrue(mapped.right - mapped.left >= offCentre.right - offCentre.left)
        assertTrue(mapped.bottom - mapped.top >= offCentre.bottom - offCentre.top)
        assertTrue(mapped.left <= offCentre.left || mapped.right >= offCentre.right)
    }
}
