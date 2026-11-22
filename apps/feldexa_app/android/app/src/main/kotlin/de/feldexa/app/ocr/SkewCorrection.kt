package de.feldexa.app.ocr

import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.tan

/**
 * T263 correction-2 — bounded deskew preprocessing for `ocr.recognize`.
 *
 * T263 EMULATOR evidence at 40a4260 recorded `scan-200dpi-skew-3deg` at CER
 * 48.48 % with only 30 of 51 ground-truth lines associated: the pipeline handed
 * a three-degree rotated raster straight to the recognizer, which merges and
 * drops tilted text lines, and the resulting line boxes are too tall and too far
 * from the annotated rows to be associated.
 *
 * This file is pure math over the gray8 raster and the raster rectangles: no
 * Android class, no ML Kit, no I/O, no text. It estimates the dominant skew of
 * the ink rows with a projection-profile search, rotates the raster upright by
 * the estimated correction, and maps the recognizer's rectangles from the
 * deskewed frame back into the original raster frame so the page-point mapping
 * in [ocrRectToPoints] stays unchanged.
 *
 * Rules kept deliberately narrow:
 * * a raster whose estimated skew is below [MIN_CORRECTION_DEGREES] is not
 *   touched, so an upright page is recognised byte-for-byte as before;
 * * no recognized text is read, rewritten, normalised, or substituted here;
 * * the rotation is a geometric transform only. A character that the bundled
 *   Latin model cannot separate (`ß`/`ẞ` vs `B`, `²` vs `³`, `§` vs `S`) stays
 *   unresolved.
 */
internal object SkewCorrection {

    /** Below this magnitude the raster is treated as upright (no-op). */
    const val MIN_CORRECTION_DEGREES: Double = 1.0

    /** Search range of the projection-profile estimate. */
    const val MAX_SKEW_DEGREES: Double = 5.0

    /** Projection-profile search step. */
    const val STEP_DEGREES: Double = 0.25

    /** Longest raster side considered by the estimator (ink is subsampled). */
    private const val MAX_ESTIMATE_EXTENT: Int = 600

    /** Ink threshold on the gray8 luminance: printed text is darker. */
    private const val INK_THRESHOLD: Int = 160

    /** Minimum ink samples before an estimate is trusted. */
    private const val MIN_INK_SAMPLES: Int = 64

    /**
     * Estimates the skew of the dominant text rows in degrees.
     *
     * The estimator scores every candidate shear in
     * `-MAX_SKEW_DEGREES..MAX_SKEW_DEGREES` by the sum of squared row-ink
     * counts of the sheared projection and returns the best-scoring angle. The
     * sign convention is defined operationally: [correctionFor] returns this
     * angle and [rotate] applies it, and a deskewed raster scores at least as
     * well as the input raster (pinned by [SkewCorrectionTest]).
     *
     * Returns `0.0` for a raster without ink or with degenerate dimensions, so
     * callers never rotate on an empty page.
     */
    fun estimateSkewDegrees(gray8: ByteArray, width: Int, height: Int): Double {
        if (width < 2 || height < 2) return 0.0
        if (gray8.size < width * height) return 0.0
        val step = max(
            1,
            ceil(max(width, height).toDouble() / MAX_ESTIMATE_EXTENT).toInt(),
        )
        val sampledWidth = (width + step - 1) / step
        val sampledHeight = (height + step - 1) / step
        if (sampledWidth < 2 || sampledHeight < 2) return 0.0

        val xs = IntArray((sampledWidth + 1) * (sampledHeight + 1))
        val ys = IntArray(xs.size)
        var inkSamples = 0
        var y = 0
        while (y < height) {
            var x = 0
            while (x < width) {
                if ((gray8[y * width + x].toInt() and 0xFF) < INK_THRESHOLD) {
                    xs[inkSamples] = x / step
                    ys[inkSamples] = y / step
                    inkSamples++
                }
                x += step
            }
            y += step
        }
        if (inkSamples < MIN_INK_SAMPLES) return 0.0

        val centreX = (sampledWidth - 1) / 2.0
        val binCount = sampledHeight + 2 * (ceil(MAX_SKEW_DEGREES * sampledWidth).toInt() + 2)
        val bins = IntArray(binCount)
        val margin = binCount / 2 - sampledHeight / 2
        var bestScore = Double.NEGATIVE_INFINITY
        var bestAngle = 0.0
        var angle = -MAX_SKEW_DEGREES
        while (angle <= MAX_SKEW_DEGREES + 1e-9) {
            java.util.Arrays.fill(bins, 0)
            val shear = tan(Math.toRadians(angle))
            var index = 0
            while (index < inkSamples) {
                val shifted = ys[index] + margin + ((xs[index] - centreX) * shear).roundToInt()
                if (shifted >= 0 && shifted < binCount) bins[shifted]++
                index++
            }
            var score = 0.0
            for (bin in bins) {
                if (bin > 0) score += bin.toDouble() * bin.toDouble()
            }
            if (score > bestScore + 1e-9) {
                bestScore = score
                bestAngle = angle
            }
            angle += STEP_DEGREES
        }
        return bestAngle
    }

    /**
     * Returns the raster rotated upright by [degrees] about its centre.
     *
     * Bilinear sampling on opaque gray8 with a white background, so newly
     * exposed corners become page background instead of black. The output keeps
     * the input dimensions, which keeps the raster-to-page-point scale valid.
     */
    fun rotate(gray8: ByteArray, width: Int, height: Int, degrees: Double): ByteArray {
        if (width <= 0 || height <= 0) return gray8
        if (gray8.size < width * height) return gray8
        if (abs(degrees) < 1e-9) return gray8
        val radians = Math.toRadians(degrees)
        val cosA = cos(radians)
        val sinA = sin(radians)
        val centreX = (width - 1) / 2.0
        val centreY = (height - 1) / 2.0
        val out = ByteArray(width * height) { 0xFF.toByte() }
        for (y in 0 until height) {
            val dy = y - centreY
            for (x in 0 until width) {
                val dx = x - centreX
                // Inverse rotation samples the source for every destination pixel.
                val sourceX = centreX + dx * cosA - dy * sinA
                val sourceY = centreY + dx * sinA + dy * cosA
                if (sourceX < 0 || sourceY < 0 ||
                    sourceX > width - 1 || sourceY > height - 1
                ) {
                    continue
                }
                val x0 = floor(sourceX).toInt()
                val y0 = floor(sourceY).toInt()
                val x1 = min(x0 + 1, width - 1)
                val y1 = min(y0 + 1, height - 1)
                val fx = sourceX - x0
                val fy = sourceY - y0
                val topLeft = gray8[y0 * width + x0].toInt() and 0xFF
                val topRight = gray8[y0 * width + x1].toInt() and 0xFF
                val bottomLeft = gray8[y1 * width + x0].toInt() and 0xFF
                val bottomRight = gray8[y1 * width + x1].toInt() and 0xFF
                val value = topLeft * (1 - fx) * (1 - fy) +
                    topRight * fx * (1 - fy) +
                    bottomLeft * (1 - fx) * fy +
                    bottomRight * fx * fy
                out[y * width + x] = value.roundToInt().coerceIn(0, 255).toByte()
            }
        }
        return out
    }

    /**
     * Maps a rectangle from the deskewed frame back into the original frame.
     *
     * The four corners are rotated by `+correction` about the raster centre and
     * the axis-aligned bounding box is returned, because the OCR contract is
     * axis-aligned. `rotate` moves content by `R(-degrees)`, so the deskewed
     * frame maps back into the original frame with `R(+correction)`; the result
     * is clamped to `[0,width] x [0,height]`. `correction == 0.0` is the
     * identity.
     */
    fun mapRectBack(
        rect: OcrRasterRect,
        width: Int,
        height: Int,
        correction: Double,
    ): OcrRasterRect {
        if (abs(correction) < 1e-9) return rect
        // `rotate` moves content by R(-degrees) (destination-to-source), so the
        // deskewed frame maps back into the original frame with R(+correction).
        val radians = Math.toRadians(correction)
        val cosA = cos(radians)
        val sinA = sin(radians)
        val centreX = (width - 1) / 2.0
        val centreY = (height - 1) / 2.0
        var minX = Double.MAX_VALUE
        var maxX = -Double.MAX_VALUE
        var minY = Double.MAX_VALUE
        var maxY = -Double.MAX_VALUE
        for (corner in 0 until 4) {
            val px = if (corner == 0 || corner == 3) {
                rect.left.toDouble()
            } else {
                rect.right.toDouble()
            }
            val py = if (corner < 2) rect.top.toDouble() else rect.bottom.toDouble()
            val dx = px - centreX
            val dy = py - centreY
            val rx = centreX + dx * cosA - dy * sinA
            val ry = centreY + dx * sinA + dy * cosA
            minX = min(minX, rx)
            maxX = max(maxX, rx)
            minY = min(minY, ry)
            maxY = max(maxY, ry)
        }
        // Rotated corners of an edge rectangle leave the raster; the OCR
        // contract keeps every box inside the page.
        return OcrRasterRect(
            left = floor(minX).toInt().coerceIn(0, width),
            top = floor(minY).toInt().coerceIn(0, height),
            right = ceil(maxX).toInt().coerceIn(0, width),
            bottom = ceil(maxY).toInt().coerceIn(0, height),
        )
    }

    /**
     * Estimated correction in degrees, or `0.0` when the raster is upright
     * enough that rotating it would only resample text.
     */
    fun correctionFor(gray8: ByteArray, width: Int, height: Int): Double {
        val estimate = estimateSkewDegrees(gray8, width, height)
        if (abs(estimate) < MIN_CORRECTION_DEGREES) return 0.0
        // [rotate] rotates the content by `-degrees` (destination-to-source
        // convention), so undoing a measured skew needs the negated angle.
        return -estimate
    }
}
