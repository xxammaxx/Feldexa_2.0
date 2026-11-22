package de.feldexa.app.ocr

import android.graphics.Bitmap
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import de.feldexa.app.OperationContext
import de.feldexa.app.PlatformFailure
import de.feldexa.app.PlatformRequest
import de.feldexa.app.PlatformService
import java.util.concurrent.atomic.AtomicBoolean

/**
 * T056 — bundled Latin ML Kit OCR for `ocr.recognize`
 * (`contracts/platform-channel.md` §2.4/§5; `contracts/ports.md` §2.3).
 *
 * The facade has already validated the wire payload and accepted the
 * asynchronous operation before this service runs. The service re-validates the
 * OCR-specific invariants defensively, converts the single `gray8` raster to
 * opaque ARGB, runs the injected recognizer exactly once, and maps raster
 * rectangles to source-page display points using only the supplied page and
 * image sizes (never device density or rotation). The terminal result is the
 * contract's `{blocks, engine, durationMs}` map; the facade adds the envelope.
 *
 * Privacy rules (Principle VI): recognized text stays in the returned result
 * only. This file never logs, caches, persists, or includes OCR text, document
 * paths, or raster bytes in a failure. Failures carry catalog codes and stable
 * machine keys only. The bundled ML Kit variant is fully on-device; this
 * service opens no sockets and downloads no model.
 *
 * The recognizer is injectable so every conversion, validation, mapping, and
 * error rule runs on the host JVM without Android or ML Kit. The production
 * [MlKitTextRecognizer] owns the one long-lived `TextRecognizer`, converts the
 * pure ARGB raster to an Android `Bitmap`, and recycles that bitmap after each
 * call. The service closes the recognizer once in [onFacadeDetached].
 */
class MlKitOcrService internal constructor(
    private val recognizer: OcrRecognizer,
    private val clock: () -> Long = { System.nanoTime() / 1_000_000L },
) : PlatformService {

    private val detached = AtomicBoolean(false)

    override fun handle(request: PlatformRequest, context: OperationContext): Any? =
        when (request.method) {
            "ocr.recognize" -> recognize(request, context)
            else -> throw PlatformFailure.unsupported()
        }

    override fun onFacadeDetached() {
        if (!detached.compareAndSet(false, true)) return
        // A failing close must not keep the engine or other services alive.
        runCatching { recognizer.close() }
    }

    private fun recognize(request: PlatformRequest, context: OperationContext): Map<String, Any?> {
        val input = validateOcrRequest(request.payload)
        context.checkCancelled()
        val startedAt = clock()
        val blocks = try {
            recognizer.recognize(
                OcrRaster(
                    width = input.imageWidth,
                    height = input.imageHeight,
                    argb = gray8ToArgb(input.gray8),
                ),
            )
        } catch (failure: PlatformFailure) {
            throw failure
        } catch (failure: OcrRecognizerException) {
            throw failure.toPlatformFailure(input.pageIndex)
        } catch (interrupted: InterruptedException) {
            Thread.currentThread().interrupt()
            throw PlatformFailure.cancelled()
        } catch (failure: Exception) {
            throw ocrFailed(input.pageIndex)
        }
        context.checkCancelled()
        val durationMs = (clock() - startedAt).coerceAtLeast(0L)
        return ocrResultMap(blocks, input, durationMs)
    }
}

/** `contracts/platform-channel.md` §5: the bundled Latin engine identity. */
internal const val OCR_ENGINE: String = "mlkit-latin-bundled-v1"

/** Bounded, content-free language hint; production always sends `de`. */
private const val MAX_LANGUAGE_LENGTH: Int = 16

/**
 * ML Kit error codes that mean the model or engine itself is missing or
 * unavailable. They map to `REC-001`; every other recognition failure maps to
 * `REC-002`.
 */
private val MODEL_UNAVAILABLE_CODES: Set<Int> = setOf(
    MlKitException.NOT_FOUND,
    MlKitException.UNAVAILABLE,
    MlKitException.FAILED_PRECONDITION,
)

/** Validated, service-owned OCR input. Contains the raster only in memory. */
internal data class OcrInput(
    val pageIndex: Int,
    val imageWidth: Int,
    val imageHeight: Int,
    val pageWidthPt: Double,
    val pageHeightPt: Double,
    val gray8: ByteArray,
)

/** Opaque ARGB raster handed to the recognizer seam. */
internal data class OcrRaster(
    val width: Int,
    val height: Int,
    val argb: IntArray,
)

/** Raster-pixel rectangle as returned by the recognizer (origin top-left). */
internal data class OcrRasterRect(
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int,
)

/** One recognized line in raster pixels; confidence stays best effort. */
internal data class OcrRawLine(
    val text: String,
    val rect: OcrRasterRect,
    val confidence: Double,
)

/** One recognized block in raster pixels; block confidence may be absent. */
internal data class OcrRawBlock(
    val text: String,
    val rect: OcrRasterRect,
    val confidence: Double?,
    val lines: List<OcrRawLine>,
)

/**
 * Test seam over one long-lived recognizer instance. Implementations must be
 * usable repeatedly and release engine resources in [close].
 */
internal interface OcrRecognizer {
    fun recognize(raster: OcrRaster): List<OcrRawBlock>
    fun close()
}

/**
 * Content-free recognizer failure. [unavailable] distinguishes a missing or
 * unusable model (`REC-001`) from a recognition failure (`REC-002`). The cause
 * is retained for local diagnosis only and is never copied into a channel
 * failure.
 */
internal class OcrRecognizerException(
    val unavailable: Boolean,
    cause: Throwable? = null,
) : Exception("ocrRecognizerFailure", cause)

private fun OcrRecognizerException.toPlatformFailure(pageIndex: Int): PlatformFailure =
    if (unavailable) {
        PlatformFailure("REC-001", "ocrUnavailable", true, "ocr.unavailable", pageIndex)
    } else {
        ocrFailed(pageIndex)
    }

private fun ocrFailed(pageIndex: Int): PlatformFailure =
    PlatformFailure("REC-002", "ocrFailed", true, "ocr.failed", pageIndex)

/**
 * Validates the §5 OCR request before any conversion or recognition.
 *
 * The boundary facade also validates the wire shape. These checks are the
 * service's own fail-closed invariants: a caller must never reach the
 * recognizer with a mismatched raster or an unsupported format. Every failure
 * is `PLT-003` with a content-free machine key.
 */
internal fun validateOcrRequest(payload: Map<String, Any?>): OcrInput {
    requireSchemaVersion(payload)
    val pageIndex = channelInteger(payload, "pageIndex", minimum = 0)
    val imageWidth = channelInteger(payload, "imageWidth", minimum = 1)
    val imageHeight = channelInteger(payload, "imageHeight", minimum = 1)
    val pageWidthPt = positiveFinite(payload, "pageWidthPt")
    val pageHeightPt = positiveFinite(payload, "pageHeightPt")

    val format = payload["format"] as? String ?: throw invalidPayload("platform.invalidEnum")
    if (format != "gray8") throw invalidPayload("platform.invalidEnum")

    val language = payload["language"] as? String ?: throw invalidPayload("platform.invalidString")
    if (language.isEmpty() ||
        language.length > MAX_LANGUAGE_LENGTH ||
        language.any { it == '\u0000' || Character.isISOControl(it) }
    ) {
        throw invalidPayload("platform.invalidString")
    }

    val bytes = payload["bytes"] ?: throw invalidPayload("platform.missingField")
    if (bytes !is ByteArray) throw invalidPayload("platform.invalidRaster")
    val expectedBytes = imageWidth.toLong() * imageHeight.toLong()
    if (expectedBytes > Int.MAX_VALUE.toLong()) throw invalidPayload("platform.valueOutOfRange")
    if (bytes.size.toLong() != expectedBytes) throw invalidPayload("platform.invalidRaster")

    return OcrInput(
        pageIndex = pageIndex,
        imageWidth = imageWidth,
        imageHeight = imageHeight,
        pageWidthPt = pageWidthPt,
        pageHeightPt = pageHeightPt,
        gray8 = bytes,
    )
}

private fun requireSchemaVersion(payload: Map<String, Any?>) {
    val raw = payload["schemaVersion"] ?: throw invalidPayload("platform.schemaVersionMissing")
    val number = raw as? Number ?: throw invalidPayload("platform.schemaVersionUnsupported")
    val value = number.toDouble()
    if (!value.isFinite() || value % 1.0 != 0.0 || value != 1.0) {
        throw invalidPayload("platform.schemaVersionUnsupported")
    }
}

private fun channelInteger(payload: Map<String, Any?>, name: String, minimum: Int): Int {
    val number = payload[name] as? Number ?: throw invalidPayload("platform.invalidInteger")
    val value = number.toDouble()
    if (!value.isFinite() || value % 1.0 != 0.0) {
        throw invalidPayload("platform.invalidInteger")
    }
    if (value < Int.MIN_VALUE.toDouble() || value > Int.MAX_VALUE.toDouble()) {
        throw invalidPayload("platform.valueOutOfRange")
    }
    val exact = value.toInt()
    if (exact < minimum) throw invalidPayload("platform.valueOutOfRange")
    return exact
}

private fun positiveFinite(payload: Map<String, Any?>, name: String): Double {
    val number = payload[name] as? Number ?: throw invalidPayload("platform.invalidNumber")
    val value = number.toDouble()
    if (!value.isFinite() || value <= 0.0) throw invalidPayload("platform.invalidNumber")
    return value
}

private fun invalidPayload(message: String): PlatformFailure =
    PlatformFailure.invalidPayload(message)

/**
 * Converts the analysis raster to opaque ARGB (`alpha = 255`) for ML Kit.
 * Pure and allocation-bounded: one output int per gray byte.
 */
internal fun gray8ToArgb(gray8: ByteArray): IntArray {
    val argb = IntArray(gray8.size)
    for (index in gray8.indices) {
        val gray = gray8[index].toInt() and 0xFF
        argb[index] = (0xFF shl 24) or (gray shl 16) or (gray shl 8) or gray
    }
    return argb
}

/**
 * Terminal result shape (`platform-channel.md` §5). Coordinates are display
 * points; no density or rotation is applied because the raster is already
 * display-oriented.
 */
internal fun ocrResultMap(
    blocks: List<OcrRawBlock>,
    input: OcrInput,
    durationMs: Long,
): Map<String, Any?> = linkedMapOf(
    "blocks" to blocks.map { ocrBlockMap(it, input) },
    "engine" to OCR_ENGINE,
    "durationMs" to durationMs.coerceAtLeast(0L),
)

private fun ocrBlockMap(block: OcrRawBlock, input: OcrInput): Map<String, Any?> {
    val lines = block.lines.map { ocrLineMap(it, input) }
    val confidence = block.confidence?.let(::clampConfidence)
        ?: if (lines.isEmpty()) {
            0.0
        } else {
            lines.sumOf { it["confidence"] as Double } / lines.size.toDouble()
        }
    return linkedMapOf(
        "text" to block.text,
        "rect" to ocrRectToPoints(block.rect, input),
        "confidence" to confidence,
        "lines" to lines,
    )
}

private fun ocrLineMap(line: OcrRawLine, input: OcrInput): Map<String, Any?> = linkedMapOf(
    "text" to line.text,
    "rect" to ocrRectToPoints(line.rect, input),
    "confidence" to clampConfidence(line.confidence),
)

/**
 * Converts a raster rectangle to source-page display points using the request's
 * own scales. The separate X/Y factors preserve non-square rasters and page
 * offsets; `left`/`top` are the raster offsets, not a device-space origin.
 */
internal fun ocrRectToPoints(rect: OcrRasterRect, input: OcrInput): Map<String, Any?> {
    val scaleX = input.pageWidthPt / input.imageWidth.toDouble()
    val scaleY = input.pageHeightPt / input.imageHeight.toDouble()
    return linkedMapOf(
        "x" to rect.left.toDouble() * scaleX,
        "y" to rect.top.toDouble() * scaleY,
        "width" to (rect.right.toLong() - rect.left.toLong()).toDouble() * scaleX,
        "height" to (rect.bottom.toLong() - rect.top.toLong()).toDouble() * scaleY,
    )
}

/** Clamps best-effort confidence to `0..1`; absent/non-finite becomes `0.0`. */
internal fun clampConfidence(value: Double?): Double {
    if (value == null || !value.isFinite()) return 0.0
    return value.coerceIn(0.0, 1.0)
}

/**
 * Production recognizer over the bundled Latin model. One `TextRecognizer` is
 * created lazily on the first call and reused for the service lifetime; the
 * service closes it on facade detach. A bitmap is created for exactly one call
 * and recycled in `finally`, including failure paths.
 */
internal class MlKitTextRecognizer : OcrRecognizer {

    private var recognizer: TextRecognizer? = null

    override fun recognize(raster: OcrRaster): List<OcrRawBlock> {
        require(raster.width > 0 && raster.height > 0) { "invalid raster size" }
        require(raster.argb.size == raster.width * raster.height) { "invalid raster length" }

        val client = clientOrUnavailable()
        // T263 correction-2: a tilted scan is rotated upright before
        // recognition and the recognized rectangles are mapped back into the
        // original raster frame. An upright page (correction below the
        // threshold) is passed to the recognizer untouched.
        val gray = ByteArray(raster.argb.size)
        for (index in raster.argb.indices) {
            gray[index] = (raster.argb[index] and 0xFF).toByte()
        }
        val correction = SkewCorrection.correctionFor(gray, raster.width, raster.height)
        val argb = if (correction == 0.0) {
            raster.argb
        } else {
            gray8ToArgb(SkewCorrection.rotate(gray, raster.width, raster.height, correction))
        }
        var bitmap: Bitmap? = null
        try {
            bitmap = Bitmap.createBitmap(
                argb,
                raster.width,
                raster.height,
                Bitmap.Config.ARGB_8888,
            )
            val text = Tasks.await(client.process(InputImage.fromBitmap(bitmap, 0)))
            return text.textBlocks.mapNotNull { block ->
                mapBlock(block, raster.width, raster.height, correction)
            }
        } catch (interrupted: InterruptedException) {
            throw interrupted
        } catch (failure: Exception) {
            throw OcrRecognizerException(
                unavailable = failure.isModelUnavailable(),
                cause = failure,
            )
        } finally {
            bitmap?.recycle()
        }
    }

    override fun close() {
        val current = recognizer
        recognizer = null
        current?.close()
    }

    private fun clientOrUnavailable(): TextRecognizer {
        recognizer?.let { return it }
        val created = try {
            TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        } catch (failure: Exception) {
            throw OcrRecognizerException(unavailable = true, cause = failure)
        }
        recognizer = created
        return created
    }

    private fun mapBlock(
        block: Text.TextBlock,
        rasterWidth: Int,
        rasterHeight: Int,
        correction: Double,
    ): OcrRawBlock? {
        val box = block.boundingBox ?: return null
        return OcrRawBlock(
            text = block.text,
            rect = SkewCorrection.mapRectBack(
                box.toRasterRect(),
                rasterWidth,
                rasterHeight,
                correction,
            ),
            confidence = null,
            lines = block.lines.mapNotNull { line ->
                mapLine(line, rasterWidth, rasterHeight, correction)
            },
        )
    }

    private fun mapLine(
        line: Text.Line,
        rasterWidth: Int,
        rasterHeight: Int,
        correction: Double,
    ): OcrRawLine? {
        val box = line.boundingBox ?: return null
        return OcrRawLine(
            text = line.text,
            rect = SkewCorrection.mapRectBack(
                box.toRasterRect(),
                rasterWidth,
                rasterHeight,
                correction,
            ),
            confidence = line.confidence.toDouble(),
        )
    }

    private fun android.graphics.Rect.toRasterRect(): OcrRasterRect =
        OcrRasterRect(left, top, right, bottom)

    private fun Throwable.isModelUnavailable(): Boolean {
        var current: Throwable? = this
        while (current != null) {
            if (current is MlKitException && current.errorCode in MODEL_UNAVAILABLE_CODES) {
                return true
            }
            current = current.cause
        }
        return false
    }
}
