package de.feldexa.app.ocr

import de.feldexa.app.OperationContext
import de.feldexa.app.OperationHandle
import de.feldexa.app.PlatformEventPublisher
import de.feldexa.app.PlatformFailure
import de.feldexa.app.PlatformRequest
import de.feldexa.app.ThreadPoster
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T056 host-JVM tests for [MlKitOcrService].
 *
 * These tests exercise the service's pure request validation, gray8 conversion,
 * coordinate mapping, confidence clamping, result shape, recognizer lifecycle,
 * and error mapping with a fake recognizer. They are `NONE`-class evidence: no
 * Android `Bitmap`, no ML Kit model, no MethodChannel and no emulator run here.
 * The real bundled model/offline behavior remains T061/T149 acceptance work.
 */
class MlKitOcrServiceTest {

    private val directPoster = ThreadPoster { it() }

    // ---- request validation ------------------------------------------------

    @Test
    fun validRequestIsAcceptedAndMapsBlocksLinesEngineAndDuration() {
        val fake = FakeRecognizer(
            blocks = listOf(
                OcrRawBlock(
                    text = "Name",
                    rect = OcrRasterRect(10, 20, 30, 60),
                    confidence = 0.9,
                    lines = listOf(
                        OcrRawLine("Name", OcrRasterRect(12, 22, 28, 32), 0.8),
                    ),
                ),
            ),
        )
        var now = 1_000L
        val service = MlKitOcrService(fake, clock = { now })
        fake.onRecognize = { now = 1_180L }
        val payload = validPayload().apply {
            put("bytes", ByteArray(20_000).also { it[0] = 200.toByte() })
        }

        @Suppress("UNCHECKED_CAST")
        val data = recognize(service, payload) as Map<String, Any?>

        assertEquals("mlkit-latin-bundled-v1", data["engine"])
        assertEquals(180L, data["durationMs"])
        val blocks = data["blocks"] as List<*>
        assertEquals(1, blocks.size)
        val block = blocks[0] as Map<*, *>
        assertEquals("Name", block["text"])
        assertEquals(0.9, block["confidence"] as Double, 0.0)
        val rect = block["rect"] as Map<*, *>
        assertEquals(5.0, rect["x"] as Double, 1e-9)
        assertEquals(10.0, rect["y"] as Double, 1e-9)
        assertEquals(10.0, rect["width"] as Double, 1e-9)
        assertEquals(20.0, rect["height"] as Double, 1e-9)
        val lines = block["lines"] as List<*>
        assertEquals(1, lines.size)
        val line = lines[0] as Map<*, *>
        assertEquals("Name", line["text"])
        assertEquals(0.8, line["confidence"] as Double, 0.0)
        val lineRect = line["rect"] as Map<*, *>
        assertEquals(6.0, lineRect["x"] as Double, 1e-9)
        assertEquals(11.0, lineRect["y"] as Double, 1e-9)
        assertEquals(8.0, lineRect["width"] as Double, 1e-9)
        assertEquals(5.0, lineRect["height"] as Double, 1e-9)

        val raster = fake.lastRaster!!
        assertEquals(100, raster.width)
        assertEquals(200, raster.height)
        assertEquals(20_000, raster.argb.size)
        assertEquals(0xFFC8C8C8.toInt(), raster.argb[0])
    }

    @Test
    fun rectMappingUsesIndependentAxisScalesAndKeepsRasterOffset() {
        val fake = FakeRecognizer(
            blocks = listOf(
                OcrRawBlock(
                    text = "Zeile",
                    rect = OcrRasterRect(125, 50, 375, 150),
                    confidence = 0.5,
                    lines = emptyList(),
                ),
            ),
        )
        val service = MlKitOcrService(fake)
        val payload = validPayload().apply {
            put("imageWidth", 1_000)
            put("imageHeight", 500)
            put("pageWidthPt", 595.28)
            put("pageHeightPt", 841.89)
            put("bytes", ByteArray(500_000))
        }

        @Suppress("UNCHECKED_CAST")
        val data = recognize(service, payload) as Map<String, Any?>
        @Suppress("UNCHECKED_CAST")
        val rect = ((data["blocks"] as List<*>)[0] as Map<*, *>)["rect"] as Map<*, *>

        assertEquals(74.41, rect["x"] as Double, 1e-9)
        assertEquals(84.189, rect["y"] as Double, 1e-9)
        assertEquals(148.82, rect["width"] as Double, 1e-9)
        assertEquals(168.378, rect["height"] as Double, 1e-9)
    }

    @Test
    fun confidenceIsClampedAndBlockUsesLineMeanWhenAbsent() {
        val fake = FakeRecognizer(
            blocks = listOf(
                OcrRawBlock(
                    text = "A",
                    rect = OcrRasterRect(0, 0, 10, 10),
                    confidence = null,
                    lines = listOf(
                        OcrRawLine("A", OcrRasterRect(0, 0, 10, 10), 1.4),
                        OcrRawLine("A", OcrRasterRect(0, 0, 10, 10), -0.2),
                        OcrRawLine("A", OcrRasterRect(0, 0, 10, 10), Double.NaN),
                    ),
                ),
                OcrRawBlock(
                    text = "B",
                    rect = OcrRasterRect(0, 0, 10, 10),
                    confidence = 2.5,
                    lines = emptyList(),
                ),
            ),
        )
        val service = MlKitOcrService(fake)

        @Suppress("UNCHECKED_CAST")
        val data = recognize(service, validPayload()) as Map<String, Any?>
        val blocks = data["blocks"] as List<*>
        val first = blocks[0] as Map<*, *>
        val firstLines = first["lines"] as List<*>
        assertEquals(1.0, (firstLines[0] as Map<*, *>)["confidence"] as Double, 0.0)
        assertEquals(0.0, (firstLines[1] as Map<*, *>)["confidence"] as Double, 0.0)
        assertEquals(0.0, (firstLines[2] as Map<*, *>)["confidence"] as Double, 0.0)
        assertEquals(1.0 / 3.0, first["confidence"] as Double, 1e-12)
        assertEquals(1.0, (blocks[1] as Map<*, *>)["confidence"] as Double, 0.0)
    }

    @Test
    fun emptyResultKeepsEngineAndNonNegativeDurationShape() {
        val service = MlKitOcrService(FakeRecognizer(), clock = { 42L })

        @Suppress("UNCHECKED_CAST")
        val data = recognize(service, validPayload()) as Map<String, Any?>

        assertTrue((data["blocks"] as List<*>).isEmpty())
        assertEquals("mlkit-latin-bundled-v1", data["engine"])
        assertEquals(0L, data["durationMs"])
    }

    @Test
    fun durationIsNonNegativeEvenIfClockMovesBackwards() {
        var now = 5_000L
        val service = MlKitOcrService(FakeRecognizer(), clock = { now })
        val payload = validPayload()
        now = 4_000L

        @Suppress("UNCHECKED_CAST")
        val data = recognize(service, payload) as Map<String, Any?>

        assertEquals(0L, data["durationMs"])
    }

    // ---- recognizer lifecycle ---------------------------------------------

    @Test
    fun recognizerIsReusedAcrossCallsAndClosedOnceOnDetach() {
        val fake = FakeRecognizer()
        val service = MlKitOcrService(fake)

        recognize(service, validPayload())
        recognize(service, validPayload())
        assertEquals(2, fake.recognizeCalls)
        assertEquals(0, fake.closeCalls)

        service.onFacadeDetached()
        service.onFacadeDetached()
        assertEquals(1, fake.closeCalls)
    }

    @Test
    fun closeFailureIsContained() {
        val fake = FakeRecognizer().apply { closeFailure = IllegalStateException("close") }
        val service = MlKitOcrService(fake)

        service.onFacadeDetached()

        assertEquals(1, fake.closeCalls)
    }

    // ---- validation failures ----------------------------------------------

    @Test
    fun missingOrUnsupportedSchemaVersionIsRejected() {
        val missing = validPayload().apply { remove("schemaVersion") }
        assertInvalid(missing, "platform.schemaVersionMissing")
        assertInvalid(validPayload().apply { put("schemaVersion", 2) }, "platform.schemaVersionUnsupported")
        assertInvalid(validPayload().apply { put("schemaVersion", 1.5) }, "platform.schemaVersionUnsupported")
    }

    @Test
    fun negativeOrFractionalPageIndexIsRejected() {
        assertInvalid(validPayload().apply { put("pageIndex", -1) }, "platform.valueOutOfRange")
        assertInvalid(validPayload().apply { put("pageIndex", 1.5) }, "platform.invalidInteger")
    }

    @Test
    fun nonPositiveOrFractionalImageDimensionsAreRejected() {
        assertInvalid(validPayload().apply { put("imageWidth", 0) })
        assertInvalid(validPayload().apply { put("imageHeight", -2) })
        assertInvalid(validPayload().apply { put("imageWidth", 10.5) }, "platform.invalidInteger")
        assertInvalid(validPayload().apply { put("imageHeight", "200") }, "platform.invalidInteger")
    }

    @Test
    fun nonFiniteOrNonPositivePageSizeIsRejected() {
        listOf(0.0, -1.0, Double.NaN, Double.POSITIVE_INFINITY).forEach { value ->
            assertInvalid(validPayload().apply { put("pageWidthPt", value) }, "platform.invalidNumber")
            assertInvalid(validPayload().apply { put("pageHeightPt", value) }, "platform.invalidNumber")
        }
    }

    @Test
    fun nonGrayFormatIsRejected() {
        assertInvalid(validPayload().apply { put("format", "rgba8888") }, "platform.invalidEnum")
    }

    @Test
    fun byteLengthMustEqualWidthTimesHeight() {
        assertInvalid(validPayload().apply { put("bytes", ByteArray(19_999)) }, "platform.invalidRaster")
        assertInvalid(validPayload().apply { put("bytes", ByteArray(20_001)) }, "platform.invalidRaster")
        assertInvalid(validPayload().apply { remove("bytes") }, "platform.missingField")
    }

    @Test
    fun emptyOrMissingLanguageIsRejected() {
        assertInvalid(validPayload().apply { put("language", "") }, "platform.invalidString")
        assertInvalid(validPayload().apply { remove("language") }, "platform.invalidString")
    }

    @Test
    fun invalidRequestMessagesNeverEchoPayloadContent() {
        val payload = validPayload().apply { put("format", "S3cr3t-Dokument.pdf") }
        val failure = assertInvalid(payload, "platform.invalidEnum")

        assertFalse(failure.message!!.contains("S3cr3t"))
        assertFalse(failure.details().values.any { it?.toString()?.contains("S3cr3t") == true })
    }

    // ---- recognizer error mapping -----------------------------------------

    @Test
    fun unavailableModelMapsToContentFreeRec001() {
        val fake = FakeRecognizer().apply {
            recognizeFailure = OcrRecognizerException(
                unavailable = true,
                cause = IllegalStateException("model /data/user/0/secret"),
            )
        }
        val payload = validPayload().apply { put("pageIndex", 3) }

        val failure = assertThrows(PlatformFailure::class.java) {
            recognize(MlKitOcrService(fake), payload)
        }

        assertEquals("REC-001", failure.code)
        assertEquals("ocrUnavailable", failure.category)
        assertTrue(failure.retryable)
        assertEquals("ocr.unavailable", failure.machineMessage)
        assertEquals(3, failure.pageIndex)
        assertNull(failure.durationMs)
        assertFalse(failure.message!!.contains("secret"))
        assertFalse(failure.details().values.any { it?.toString()?.contains("/data") == true })
    }

    @Test
    fun recognitionFailureMapsToContentFreeRec002() {
        val fake = FakeRecognizer().apply {
            recognizeFailure = OcrRecognizerException(
                unavailable = false,
                cause = IllegalStateException("text was NAME:ANTON"),
            )
        }

        val failure = assertThrows(PlatformFailure::class.java) {
            recognize(MlKitOcrService(fake), validPayload())
        }

        assertEquals("REC-002", failure.code)
        assertEquals("ocrFailed", failure.category)
        assertEquals("ocr.failed", failure.machineMessage)
        assertEquals(0, failure.pageIndex)
        assertFalse(failure.message!!.contains("ANTON"))
        assertFalse(failure.details().values.any { it?.toString()?.contains("ANTON") == true })
    }

    @Test
    fun unexpectedRecognizerExceptionMapsToRec002() {
        val fake = FakeRecognizer().apply {
            unexpectedFailure = IllegalArgumentException("raw engine detail")
        }

        val failure = assertThrows(PlatformFailure::class.java) {
            recognize(MlKitOcrService(fake), validPayload())
        }

        assertEquals("REC-002", failure.code)
        assertEquals("ocrFailed", failure.category)
    }

    @Test
    fun unknownMethodFailsClosedWithoutRecognition() {
        val fake = FakeRecognizer()
        val failure = assertThrows(PlatformFailure::class.java) {
            handle(MlKitOcrService(fake), "ocr.unknown", validPayload())
        }

        assertEquals("PLT-001", failure.code)
        assertEquals(0, fake.recognizeCalls)
    }

    // ---- pure conversion ---------------------------------------------------

    @Test
    fun gray8ConversionProducesOpaqueArgbChannels() {
        assertArrayEquals(
            intArrayOf(0xFF000000.toInt(), 0xFF7F7F7F.toInt(), 0xFFFFFFFF.toInt()),
            gray8ToArgb(byteArrayOf(0, 127, -1)),
        )
    }

    // ---- helpers -----------------------------------------------------------

    private fun validPayload(): MutableMap<String, Any?> = linkedMapOf(
        "schemaVersion" to 1,
        "pageIndex" to 0,
        "imageWidth" to 100,
        "imageHeight" to 200,
        "pageWidthPt" to 50.0,
        "pageHeightPt" to 100.0,
        "format" to "gray8",
        "bytes" to ByteArray(20_000),
        "language" to "de",
    )

    private fun recognize(service: MlKitOcrService, payload: Map<String, Any?>): Any? =
        handle(service, "ocr.recognize", payload)

    private fun handle(
        service: MlKitOcrService,
        method: String,
        payload: Map<String, Any?>,
    ): Any? {
        val operationId = "123e4567-e89b-42d3-a456-426614174000"
        val handle = OperationHandle(operationId)
        return service.handle(
            PlatformRequest(method, payload),
            OperationContext(operationId, handle, PlatformEventPublisher(directPoster)),
        )
    }

    private fun assertInvalid(payload: Map<String, Any?>, message: String? = null): PlatformFailure {
        val fake = FakeRecognizer()
        val failure = assertThrows(PlatformFailure::class.java) {
            recognize(MlKitOcrService(fake), payload)
        }
        assertEquals("PLT-003", failure.code)
        assertEquals("invalidPayload", failure.category)
        assertFalse(failure.retryable)
        assertEquals(0, fake.recognizeCalls)
        if (message != null) assertEquals(message, failure.machineMessage)
        return failure
    }

    private class FakeRecognizer(
        private val blocks: List<OcrRawBlock> = emptyList(),
    ) : OcrRecognizer {
        var recognizeCalls = 0
        var closeCalls = 0
        var lastRaster: OcrRaster? = null
        var onRecognize: (() -> Unit)? = null
        var recognizeFailure: OcrRecognizerException? = null
        var unexpectedFailure: RuntimeException? = null
        var closeFailure: RuntimeException? = null

        override fun recognize(raster: OcrRaster): List<OcrRawBlock> {
            recognizeCalls++
            lastRaster = raster
            onRecognize?.invoke()
            recognizeFailure?.let { throw it }
            unexpectedFailure?.let { throw it }
            return blocks
        }

        override fun close() {
            closeCalls++
            closeFailure?.let { throw it }
        }
    }
}
