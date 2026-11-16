package de.feldexa.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigInteger
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit

/**
 * T024 host-JVM contract tests for the platform-channel facade.
 *
 * These tests exercise the pure channel core (validation, envelope, error
 * mapping, cancellation, threading seam, events). They are `NONE`-class evidence:
 * they prove no Android runtime behavior and are never reported as `EMULATOR`.
 */
class FeldexaPluginTest {

    private val documentId = "123e4567-e89b-42d3-a456-426614174000"
    private val assetId = "123e4567-e89b-42d3-a456-426614174001"
    private val templateId = "123e4567-e89b-42d3-a456-426614174002"
    private val artifactId = "123e4567-e89b-42d3-a456-426614174003"
    private val operationId = "123e4567-e89b-42d3-a456-426614174004"

    // ---- success envelope and every contract method -------------------------

    @Test
    fun successEnvelopeWrapsServiceData() {
        val data = linkedMapOf<String, Any?>("keyAvailable" to true, "objectCount" to 2, "totalBytes" to 10)
        val facade = newFacade(service = ReturningService(data))
        val reply = RecordingReply()

        facade.handle("store.status", mapOf("schemaVersion" to 1), reply)

        assertNull(reply.failure)
        val envelope = reply.successValue as Map<*, *>
        assertEquals(1, envelope["schemaVersion"])
        assertEquals(true, envelope["ok"])
        assertEquals(data, envelope["data"])
    }

    @Test
    fun everyContractMethodAcceptsMinimalPayload() {
        val services = PlatformServiceRegistry()
        PlatformServiceRegistry.METHOD_PREFIXES.forEach { prefix ->
            services.register(prefix, ReturningService(mapOf("ok" to true)))
        }
        val facade = PlatformChannelFacade(
            services = services,
            mainPoster = DirectPoster,
            events = PlatformEventPublisher(DirectPoster),
            executor = DirectExecutor,
            clock = { 0L },
        )
        val minimalPayloads: Map<String, Map<String, Any?>> = linkedMapOf(
            "import.pickAndImport" to mapOf("maxBytes" to 1024, "titleHint" to null),
            "import.verifySource" to mapOf("sourceId" to documentId),
            "import.discardStaged" to mapOf("txnId" to "txn-1"),
            "store.status" to emptyMap(),
            "store.list" to mapOf("kind" to "document"),
            "store.readSource" to mapOf("documentId" to documentId),
            "store.readSignature" to mapOf("documentId" to documentId, "assetId" to assetId),
            "store.writeSignature" to mapOf(
                "documentId" to documentId,
                "assetId" to assetId,
                "bytes" to ByteArray(4),
                "sha256" to "a".repeat(64),
            ),
            "store.saveRevision" to mapOf(
                "documentId" to documentId,
                "revision" to mapOf("value" to "x"),
                "expectedHead" to null,
                "kind" to "autosave",
            ),
            "store.createTemplate" to mapOf(
                "template" to mapOf("title" to "T"),
                "revision" to mapOf("value" to "x"),
            ),
            "store.saveTemplateVersion" to mapOf(
                "templateId" to templateId,
                "version" to mapOf("value" to "x"),
                "expectedHead" to null,
            ),
            "store.loadDocument" to mapOf("documentId" to documentId),
            "store.loadTemplate" to mapOf("templateId" to templateId, "versionId" to null),
            "store.delete" to mapOf(
                "kind" to "document",
                "id" to documentId,
                "confirm" to mapOf("title" to "Titel", "acknowledged" to true),
            ),
            "store.recoveryStamp" to mapOf("kind" to "template", "id" to templateId),
            "ocr.recognize" to mapOf(
                "pageIndex" to 0,
                "imageWidth" to 100,
                "imageHeight" to 100,
                "pageWidthPt" to 100.0,
                "pageHeightPt" to 100.0,
                "format" to "gray8",
                "bytes" to ByteArray(10_000),
                "language" to "de",
            ),
            "export.validate" to mapOf("plan" to mapOf("value" to "x")),
            "export.render" to mapOf("plan" to mapOf("value" to "x")),
            "export.readArtifact" to mapOf("artifactId" to artifactId),
            "export.deleteArtifact" to mapOf("artifactId" to artifactId),
            "delivery.save" to mapOf("artifactId" to artifactId, "suggestedName" to "Antrag.pdf"),
            "delivery.share" to mapOf("artifactId" to artifactId, "mimeType" to "application/pdf"),
            "delivery.print" to mapOf("artifactId" to artifactId, "jobName" to "Feldexa Dokument"),
            "cancel.operation" to mapOf("operationId" to operationId),
        )

        val failures = mutableListOf<String>()
        for ((method, payload) in minimalPayloads) {
            val reply = RecordingReply()
            facade.handle(method, mapOf("schemaVersion" to 1) + payload, reply)
            val failure = reply.failure
            when {
                failure != null -> failures += "$method -> ${failure.code}"
                reply.successValue !is Map<*, *> -> failures += "$method -> no envelope"
                (reply.successValue as Map<*, *>)["ok"] != true -> failures += "$method -> not ok"
            }
        }
        assertTrue(failures.joinToString(), failures.isEmpty())
    }

    @Test
    fun longSchemaVersionIsAccepted() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle("store.status", mapOf("schemaVersion" to 1L), reply)
        assertNull(reply.failure)
    }

    // ---- payload validation -------------------------------------------------

    @Test
    fun nonMapPayloadIsRejected() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle("store.status", "not-a-map", reply)
        assertFailure(reply, "PLT-003")
    }

    @Test
    fun nullPayloadIsRejected() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle("store.status", null, reply)
        assertFailure(reply, "PLT-003")
    }

    @Test
    fun missingSchemaVersionIsRejected() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle("store.status", emptyMap<String, Any?>(), reply)
        assertFailure(reply, "PLT-003")
        assertEquals("platform.schemaVersionMissing", reply.failure?.machineMessage)
    }

    @Test
    fun unsupportedSchemaVersionIsRejected() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle("store.status", mapOf("schemaVersion" to 2), reply)
        assertFailure(reply, "PLT-003")
    }

    @Test
    fun unknownTopLevelFieldIsRejected() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle("store.status", mapOf("schemaVersion" to 1, "extra" to true), reply)
        assertFailure(reply, "PLT-003")
        assertEquals("platform.unknownField", reply.failure?.machineMessage)
    }

    @Test
    fun nonStringTopLevelKeyIsRejected() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle("store.status", linkedMapOf<Any?, Any?>(1 to "x", "schemaVersion" to 1), reply)
        assertFailure(reply, "PLT-003")
    }

    @Test
    fun missingRequiredFieldIsRejected() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle("store.readSource", mapOf("schemaVersion" to 1), reply)
        assertFailure(reply, "PLT-003")
    }

    @Test
    fun badUuidIsRejected() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle(
            "store.readSource",
            mapOf("schemaVersion" to 1, "documentId" to "../../etc/passwd"),
            reply,
        )
        assertFailure(reply, "PLT-002")
    }

    @Test
    fun nonStringUuidIsRejected() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle("store.readSource", mapOf("schemaVersion" to 1, "documentId" to 42), reply)
        assertFailure(reply, "PLT-002")
    }

    @Test
    fun overlongTitleHintIsRejected() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle(
            "import.pickAndImport",
            mapOf("schemaVersion" to 1, "maxBytes" to 1024, "titleHint" to "x".repeat(201)),
            reply,
        )
        assertFailure(reply, "PLT-003")
    }

    @Test
    fun controlCharacterIsRejected() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle(
            "import.pickAndImport",
            mapOf("schemaVersion" to 1, "maxBytes" to 1024, "titleHint" to "bad\u0000title"),
            reply,
        )
        assertFailure(reply, "PLT-003")
    }

    @Test
    fun payloadLimitIsEnforced() {
        val facade = newFacade(limits = ChannelLimits(maxPayloadBytes = 8))
        val reply = RecordingReply()
        facade.handle(
            "import.pickAndImport",
            mapOf("schemaVersion" to 1, "maxBytes" to 1, "titleHint" to "abcdef"),
            reply,
        )
        assertFailure(reply, "PLT-003")
        assertEquals("platform.payloadTooLarge", reply.failure?.machineMessage)
    }

    // ---- §10 total method-payload accounting ------------------------------

    @Test
    fun payloadSizeMatchesStandardMessageCodecByteAccounting() {
        // The exact byte prefixes emitted by StandardMessageCodec.writeValue.
        assertEquals(2L, PayloadSize.measure(emptyMap<String, Any?>(), Long.MAX_VALUE))
        assertEquals(10L, PayloadSize.measure(mapOf("a" to 1), Long.MAX_VALUE))
        assertEquals(5L, PayloadSize.measure("abc", Long.MAX_VALUE))
        assertEquals(258L, PayloadSize.measure("a".repeat(254), Long.MAX_VALUE))
        assertEquals(304L, PayloadSize.measure(ByteArray(300), Long.MAX_VALUE))
        // Doubles are aligned to an 8-byte boundary in the full message.
        assertEquals(16L, PayloadSize.measure(1.5, Long.MAX_VALUE))
        // map {"d": 1.5}: map header 2 + key 3 + type 1 + two pad bytes + 8.
        assertEquals(16L, PayloadSize.measure(mapOf("d" to 1.5), Long.MAX_VALUE))
        // Nested map keys belong to the map's encoded size.
        assertEquals(15L, PayloadSize.measure(mapOf("a" to mapOf("b" to 1)), Long.MAX_VALUE))
        // UTF-8 lengths: 2, 3 and a 4-byte surrogate pair, without copying.
        assertEquals(4L, PayloadSize.measure("\u00e4", Long.MAX_VALUE))
        assertEquals(5L, PayloadSize.measure("\u20ac", Long.MAX_VALUE))
        assertEquals(6L, PayloadSize.measure("\uD83D\uDE00", Long.MAX_VALUE))
        assertEquals(12L, PayloadSize.measure("a\u00e4\u20ac\uD83D\uDE00", Long.MAX_VALUE))
        // "store.status" (12 chars) = 1 type + 1 size + 12; empty map = 2.
        assertEquals(16L, PayloadSize.measureMethodCall("store.status", emptyMap<String, Any?>(), Long.MAX_VALUE))
    }

    @Test
    fun payloadSizeMatchesCodecHexadecimalBigIntegerEncoding() {
        // StandardMessageCodec writes a BigInteger as
        // writeBytes(value.toString(16).getBytes(UTF_8)), so the size is the
        // type byte, the size prefix and the ASCII hexadecimal text (the sign
        // byte included for negatives).
        val cases = linkedMapOf(
            BigInteger.ZERO to "0",
            BigInteger.ONE to "1",
            BigInteger.valueOf(-1) to "-1",
            BigInteger.valueOf(15) to "f",
            BigInteger.valueOf(16) to "10",
            BigInteger.valueOf(255) to "ff",
            BigInteger.valueOf(256) to "100",
            BigInteger.ONE.shiftLeft(63) to "8000000000000000",
            BigInteger.ONE.shiftLeft(64) to "10000000000000000",
            BigInteger.ONE.shiftLeft(64).negate() to "-10000000000000000",
            BigInteger.ONE.shiftLeft(64).subtract(BigInteger.ONE) to "ffffffffffffffff",
            BigInteger.ONE.shiftLeft(64).subtract(BigInteger.ONE).negate() to "-ffffffffffffffff",
        )
        for ((value, hex) in cases) {
            assertEquals(hex, value.toString(16))
            assertEquals(
                "value=$value",
                1L + sizePrefix(hex.length.toLong()) + hex.length.toLong(),
                PayloadSize.measure(value, Long.MAX_VALUE),
            )
        }
    }

    @Test
    fun payloadSizeMatchesCodecBigIntegerEncodingAcrossPowersAndSigns() {
        val values = mutableListOf<BigInteger>()
        for (exponent in 0..512) {
            val power = BigInteger.ONE.shiftLeft(exponent)
            values += power
            values += power.negate()
            values += power.subtract(BigInteger.ONE)
            values += power.subtract(BigInteger.ONE).negate()
            values += power.add(BigInteger.ONE)
            values += power.add(BigInteger.ONE).negate()
        }
        values += BigInteger.valueOf(Long.MAX_VALUE)
        values += BigInteger.valueOf(Long.MIN_VALUE)
        for (value in values) {
            val hex = value.toString(16)
            assertEquals(
                "value=$value",
                1L + sizePrefix(hex.length.toLong()) + hex.length.toLong(),
                PayloadSize.measure(value, Long.MAX_VALUE),
            )
        }
    }

    @Test
    fun payloadSizeMeasuresCharSequenceWithoutMaterializingToString() {
        val text = "a\u00e4\u20ac\uD83D\uDE00"
        assertEquals(12L, PayloadSize.measure(text, Long.MAX_VALUE))
        assertEquals(
            PayloadSize.measure(text, Long.MAX_VALUE),
            PayloadSize.measure(StringBuilder(text), Long.MAX_VALUE),
        )
    }

    @Test
    fun largeBigIntegerIsMeasuredWithinTinyBudgetsWithoutHexadecimalCopy() {
        val shift = 64 * 1024 * 1024
        val huge = BigInteger.ONE.shiftLeft(shift)
        // "1" followed by one zero for every four magnitude bits, plus the
        // 1 type byte and the 5-byte size prefix (the text exceeds 0xffff).
        val hexBytes = 1L + shift.toLong() / 4L
        val exact = 1L + 5L + hexBytes
        assertEquals(exact, PayloadSize.measure(huge, Long.MAX_VALUE))

        // Tiny budgets are decided from the type byte and the minimum one-byte
        // text before the magnitude is inspected at all.
        assertEquals(2L, PayloadSize.measure(huge, 1L))
        assertEquals(3L, PayloadSize.measure(huge, 2L))
        assertEquals(3L, PayloadSize.measure(huge.negate(), 2L))

        // The exact path returns the full length without materializing the
        // hexadecimal text; the implementation only reads bitLength (and
        // bitCount for negatives), never toString(16) or abs(). Negatives add
        // the leading '-' byte.
        assertEquals(exact + 1L, PayloadSize.measure(huge.negate(), Long.MAX_VALUE))
    }

    @Test
    fun hugeNegativeBigIntegerRejectsBeforeNegativeBitCountDisambiguation() {
        // |value| = 2^8_388_608. The exact negative hexadecimal text is
        // 2_097_154 bytes ("-" plus 2_097_153 digits) under a 5-byte prefix,
        // but the old guard only ruled out one- and two-byte budgets before
        // calling bitCount(), which scans the entire 8 Mi-bit magnitude.
        val shift = 8 * 1024 * 1024
        val magnitude = ByteArray(shift / 8 + 1).also { it[0] = 1 }
        val hugeNegative = BitCountTrackingBigInteger(-1, magnitude)
        val hexLength = hugeNegative.toString(16).length.toLong()
        val exact = 1L + sizePrefix(hexLength) + hexLength
        assertEquals(shift.toLong() / 4L + 2L, hexLength)
        assertEquals(1L + 5L + hexLength, exact)

        // Budgets above the two-byte minimum but far below the encoded
        // length: every one must reject from the sign/bit-length lower bound
        // without ever invoking bitCount().
        for (budget in listOf(3L, 4L, 253L, 254L, 65_535L, 65_536L, exact - 2L)) {
            hugeNegative.bitCountCalls = 0
            hugeNegative.bitLengthCalls = 0
            assertEquals("budget=$budget", budget + 1L, PayloadSize.measure(hugeNegative, budget))
            assertEquals("budget=$budget must not scan bitCount", 0, hugeNegative.bitCountCalls)
            assertTrue(
                "budget=$budget must use the cheap bitLength bound",
                hugeNegative.bitLengthCalls >= 1,
            )
        }

        // One byte below the exact total the lower bound cannot decide the
        // power-of-two disambiguation, so the exact path runs and rejects only
        // after exactly one bitCount(); this proves the double is live.
        hugeNegative.bitCountCalls = 0
        assertEquals(exact, PayloadSize.measure(hugeNegative, exact - 1L))
        assertEquals(1, hugeNegative.bitCountCalls)

        // The exact accepted size still equals the codec's size.
        hugeNegative.bitCountCalls = 0
        assertEquals(exact, PayloadSize.measure(hugeNegative, Long.MAX_VALUE))
        assertEquals(1, hugeNegative.bitCountCalls)

        // One- and two-byte budgets stay decided before even bitLength().
        hugeNegative.bitCountCalls = 0
        hugeNegative.bitLengthCalls = 0
        assertEquals(2L, PayloadSize.measure(hugeNegative, 1L))
        assertEquals(3L, PayloadSize.measure(hugeNegative, 2L))
        assertEquals(0, hugeNegative.bitCountCalls)
        assertEquals(0, hugeNegative.bitLengthCalls)
    }

    @Test
    fun acceptedNearBoundaryNegativeBigIntegersStayExact() {
        // Negative hexadecimal text lengths on both sides of the 1 -> 3 and
        // 3 -> 5 byte size-prefix thresholds, with non-power-of-two and
        // power-of-two magnitudes so both outcomes of the bitCount()
        // disambiguation are exercised.
        val cases = listOf(
            -(BigInteger.ONE.shiftLeft(4 * 252) - BigInteger.ONE) to 253L,
            -(BigInteger.ONE.shiftLeft(4 * 253) - BigInteger.ONE) to 254L,
            -(BigInteger.ONE.shiftLeft(4 * 254) - BigInteger.ONE) to 255L,
            -(BigInteger.ONE.shiftLeft(4 * 65_534) - BigInteger.ONE) to 65_535L,
            -(BigInteger.ONE.shiftLeft(4 * 65_535) - BigInteger.ONE) to 65_536L,
            BigInteger.ONE.shiftLeft(1_008).negate() to 254L,
            BigInteger.ONE.shiftLeft(65_536).negate() to 16_386L,
        )
        for ((value, textLength) in cases) {
            assertEquals("value bits", textLength, value.toString(16).length.toLong())
            val exact = 1L + sizePrefix(textLength) + textLength
            assertEquals("value=$value", exact, PayloadSize.measure(value, Long.MAX_VALUE))
            assertEquals("value=$value at the exact budget", exact, PayloadSize.measure(value, exact))
            assertTrue(
                "value=$value must not fit one byte under",
                PayloadSize.measure(value, exact - 1L) > exact - 1L,
            )
        }

        // The power-of-two case at text length 254 has a lower bound exactly
        // one byte short of the exact size, so acceptance at the exact total
        // envelope and rejection one byte under both go through the real
        // facade guard rather than the lower-bound shortcut alone.
        val boundary = BigInteger.ONE.shiftLeft(1_008).negate()
        val method = "export.validate"
        val payload = mapOf("schemaVersion" to 1, "plan" to mapOf("x" to boundary))
        val exactEnvelope = PayloadSize.measureMethodCall(method, payload, Long.MAX_VALUE)
        val accepted = RecordingReply()
        newFacade(servicePrefix = "export", limits = ChannelLimits(maxPayloadBytes = exactEnvelope))
            .handle(method, payload, accepted)
        assertNull("expected the negative near-boundary payload to fit: ${accepted.failure}", accepted.failure)
        val rejected = RecordingReply()
        newFacade(servicePrefix = "export", limits = ChannelLimits(maxPayloadBytes = exactEnvelope - 1L))
            .handle(method, payload, rejected)
        assertFailure(rejected, "PLT-003")
        assertEquals("platform.payloadTooLarge", rejected.failure?.machineMessage)
    }

    @Test
    fun payloadAtExactTotalEnvelopeIsAcceptedAndOneByteOverIsRejected() {
        // import.pickAndImport + {schemaVersion:1, maxBytes:1024, titleHint:N}
        // StandardMethodCodec encodes the method name (22), the root map
        // marker+count (2), keys (15+10+11), values (5+5) and the string
        // (1 type + 1 length + N), i.e. exactly 72 + N bytes for N < 254.
        val titleHint = "a".repeat(40)
        val payload = mapOf("schemaVersion" to 1, "maxBytes" to 1024, "titleHint" to titleHint)
        val exactBytes = 72L + titleHint.length
        assertEquals(exactBytes, PayloadSize.measureMethodCall("import.pickAndImport", payload, Long.MAX_VALUE))

        val accepted = RecordingReply()
        newFacade(servicePrefix = "import", limits = ChannelLimits(maxPayloadBytes = exactBytes))
            .handle("import.pickAndImport", payload, accepted)
        assertNull("expected the exact envelope to fit: ${accepted.failure}", accepted.failure)
        assertTrue(accepted.successValue != null)

        val rejected = RecordingReply()
        newFacade(servicePrefix = "import", limits = ChannelLimits(maxPayloadBytes = exactBytes - 1))
            .handle("import.pickAndImport", payload, rejected)
        assertFailure(rejected, "PLT-003")
        assertEquals("platform.payloadTooLarge", rejected.failure?.machineMessage)
    }

    @Test
    fun payloadIsRejectedWhenValuesFitButKeysAndRootExceedTheLimit() {
        // Review-A regression: summing only the top-level values (5+5+42 = 52)
        // would accept this payload at a 52-byte limit, even though the real
        // method call is 112 bytes once the method name, root map framing and
        // the three field keys are counted.
        val titleHint = "a".repeat(40)
        val payload = mapOf("schemaVersion" to 1, "maxBytes" to 1024, "titleHint" to titleHint)
        val valuesOnly = payload.values.sumOf { PayloadSize.measure(it, Long.MAX_VALUE) }
        assertEquals(52L, valuesOnly)
        assertTrue(PayloadSize.measureMethodCall("import.pickAndImport", payload, Long.MAX_VALUE) > valuesOnly)

        val reply = RecordingReply()
        newFacade(servicePrefix = "import", limits = ChannelLimits(maxPayloadBytes = valuesOnly))
            .handle("import.pickAndImport", payload, reply)
        assertFailure(reply, "PLT-003")
        assertEquals("platform.payloadTooLarge", reply.failure?.machineMessage)
    }

    @Test
    fun fixedTotalEnvelopeAcceptsBelowAndExactPayloadAndRejectsAbove() {
        // Review-A regression: keep the total-envelope limit fixed at 112 bytes
        // and grow only the payload, so below/exact/above are genuinely three
        // different inputs rather than three different limits.
        val method = "import.pickAndImport"
        val limit = 112L
        val payloads = listOf(39, 40, 41).associateWith { length ->
            mapOf("schemaVersion" to 1, "maxBytes" to 1024, "titleHint" to "a".repeat(length))
        }
        assertEquals(111L, PayloadSize.measureMethodCall(method, payloads.getValue(39), Long.MAX_VALUE))
        assertEquals(112L, PayloadSize.measureMethodCall(method, payloads.getValue(40), Long.MAX_VALUE))
        assertEquals(113L, PayloadSize.measureMethodCall(method, payloads.getValue(41), Long.MAX_VALUE))

        for (length in listOf(39, 40)) {
            val accepted = RecordingReply()
            newFacade(servicePrefix = "import", limits = ChannelLimits(maxPayloadBytes = limit))
                .handle(method, payloads.getValue(length), accepted)
            assertNull("expected a $length-character title to fit: ${accepted.failure}", accepted.failure)
            assertTrue(accepted.successValue != null)
        }

        val rejected = RecordingReply()
        newFacade(servicePrefix = "import", limits = ChannelLimits(maxPayloadBytes = limit))
            .handle(method, payloads.getValue(41), rejected)
        assertFailure(rejected, "PLT-003")
        assertEquals("platform.payloadTooLarge", rejected.failure?.machineMessage)
    }

    @Test
    fun exportPlanLimitIsEnforced() {
        val facade = newFacade(limits = ChannelLimits(maxExportPlanBytes = 4))
        val reply = RecordingReply()
        facade.handle(
            "export.validate",
            mapOf("schemaVersion" to 1, "plan" to mapOf("a" to "bcd")),
            reply,
        )
        assertFailure(reply, "PLT-003")
    }

    @Test
    fun signatureSizeLimitMapsToSave007() {
        val facade = newFacade(limits = ChannelLimits(maxSignatureBytes = 2))
        val reply = RecordingReply()
        facade.handle(
            "store.writeSignature",
            mapOf(
                "schemaVersion" to 1,
                "documentId" to documentId,
                "assetId" to assetId,
                "bytes" to ByteArray(3),
                "sha256" to "a".repeat(64),
            ),
            reply,
        )
        assertFailure(reply, "SAVE-007")
    }

    @Test
    fun revisionSizeLimitMapsToSave007() {
        val facade = newFacade(limits = ChannelLimits(maxRevisionBytes = 4))
        val reply = RecordingReply()
        facade.handle(
            "store.saveRevision",
            mapOf(
                "schemaVersion" to 1,
                "documentId" to documentId,
                "revision" to mapOf("a" to "bcd"),
                "expectedHead" to null,
                "kind" to "autosave",
            ),
            reply,
        )
        assertFailure(reply, "SAVE-007")
    }

    @Test
    fun oversizedOcrEdgeIsRejected() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle(
            "ocr.recognize",
            mapOf(
                "schemaVersion" to 1,
                "pageIndex" to 0,
                "imageWidth" to 4097,
                "imageHeight" to 100,
                "pageWidthPt" to 100.0,
                "pageHeightPt" to 100.0,
                "format" to "gray8",
                "bytes" to ByteArray(10),
                "language" to "de",
            ),
            reply,
        )
        assertFailure(reply, "PLT-003")
    }

    @Test
    fun unsupportedOcrFormatIsRejected() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle(
            "ocr.recognize",
            mapOf(
                "schemaVersion" to 1,
                "pageIndex" to 0,
                "imageWidth" to 100,
                "imageHeight" to 100,
                "pageWidthPt" to 100.0,
                "pageHeightPt" to 100.0,
                "format" to "rgb8",
                "bytes" to ByteArray(10),
                "language" to "de",
            ),
            reply,
        )
        assertFailure(reply, "PLT-003")
    }

    @Test
    fun nonGermanOcrLanguageIsRejected() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle(
            "ocr.recognize",
            mapOf(
                "schemaVersion" to 1,
                "pageIndex" to 0,
                "imageWidth" to 100,
                "imageHeight" to 100,
                "pageWidthPt" to 100.0,
                "pageHeightPt" to 100.0,
                "format" to "gray8",
                "bytes" to ByteArray(10),
                "language" to "en",
            ),
            reply,
        )
        assertFailure(reply, "PLT-003")
    }

    @Test
    fun ocrGrayBytesMustMatchDimensions() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle(
            "ocr.recognize",
            ocrPayload(100, 100, "gray8", 10),
            reply,
        )
        assertFailure(reply, "PLT-003")
        assertEquals("platform.invalidRaster", reply.failure?.machineMessage)
    }

    @Test
    fun ocrRgbaBytesMustMatchDimensions() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle(
            "ocr.recognize",
            ocrPayload(100, 100, "rgba8888", 10_000),
            reply,
        )
        assertFailure(reply, "PLT-003")
    }

    @Test
    fun ocrValidRasterSizesAreAccepted() {
        val facade = newFacade(servicePrefix = "ocr")
        val gray = RecordingReply()
        facade.handle("ocr.recognize", ocrPayload(100, 100, "gray8", 10_000), gray)
        assertNull(gray.failure)
        val rgba = RecordingReply()
        facade.handle("ocr.recognize", ocrPayload(100, 100, "rgba8888", 40_000), rgba)
        assertNull(rgba.failure)
    }

    @Test
    fun badSignatureHashIsRejected() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle(
            "store.writeSignature",
            mapOf(
                "schemaVersion" to 1,
                "documentId" to documentId,
                "assetId" to assetId,
                "bytes" to ByteArray(1),
                "sha256" to "not-a-hash",
            ),
            reply,
        )
        assertFailure(reply, "PLT-003")
    }

    @Test
    fun unacknowledgedDeleteIsRejected() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle(
            "store.delete",
            mapOf(
                "schemaVersion" to 1,
                "kind" to "document",
                "id" to documentId,
                "confirm" to mapOf("title" to "Titel", "acknowledged" to false),
            ),
            reply,
        )
        assertFailure(reply, "SAVE-007")
    }

    @Test
    fun unknownDeleteConfirmationFieldIsRejected() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle(
            "store.delete",
            mapOf(
                "schemaVersion" to 1,
                "kind" to "document",
                "id" to documentId,
                "confirm" to mapOf(
                    "title" to "Titel",
                    "acknowledged" to true,
                    "path" to "/tmp/secret.pdf",
                ),
            ),
            reply,
        )
        assertFailure(reply, "PLT-003")
    }

    @Test
    fun suggestedNameWithPathSeparatorIsRejected() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle(
            "delivery.save",
            mapOf(
                "schemaVersion" to 1,
                "artifactId" to artifactId,
                "suggestedName" to "a/b.pdf",
            ),
            reply,
        )
        assertFailure(reply, "PLT-003")
    }

    @Test
    fun wrongShareMimeTypeIsRejected() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle(
            "delivery.share",
            mapOf(
                "schemaVersion" to 1,
                "artifactId" to artifactId,
                "mimeType" to "text/plain",
            ),
            reply,
        )
        assertFailure(reply, "PLT-003")
    }

    // ---- routing ------------------------------------------------------------

    @Test
    fun unknownMethodIsUnsupported() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle("store.readAnyFile", mapOf("schemaVersion" to 1), reply)
        assertFailure(reply, "PLT-001")
        assertEquals("unsupported", reply.failure?.category)
    }

    @Test
    fun unregisteredServiceIsUnsupported() {
        val facade = newFacade(servicePrefix = null)
        val reply = RecordingReply()
        facade.handle("store.status", mapOf("schemaVersion" to 1), reply)
        assertFailure(reply, "PLT-001")
        assertEquals("unsupported", reply.failure?.category)
    }

    // ---- error mapping ------------------------------------------------------

    @Test
    fun platformFailureIsMappedWithDurationAndDetails() {
        val times = java.util.ArrayDeque(listOf(1000L, 1007L))
        val facade = newFacade(
            service = ThrowingService(
                PlatformFailure(
                    code = "SAVE-001",
                    category = "storageFull",
                    retryable = true,
                    machineMessage = "save.noSpace",
                    pageIndex = 2,
                    fieldCount = 3,
                ),
            ),
            clock = { times.removeFirst() },
        )
        val reply = RecordingReply()

        facade.handle("store.status", mapOf("schemaVersion" to 1), reply)

        val failure = reply.failure!!
        assertEquals("SAVE-001", failure.code)
        assertEquals("save.noSpace", failure.machineMessage)
        assertEquals("save.noSpace", failure.message)
        val details = failure.details()
        assertEquals(1, details["schemaVersion"])
        assertEquals("storageFull", details["category"])
        assertEquals(true, details["retryable"])
        assertEquals(2, details["pageIndex"])
        assertEquals(3, details["fieldCount"])
        assertEquals(7L, details["durationMs"])
    }

    @Test
    fun unexpectedExceptionIsSanitized() {
        val facade = newFacade(
            service = ThrowingService(IllegalStateException("secret /tmp/antrag.pdf")),
        )
        val reply = RecordingReply()

        facade.handle("store.status", mapOf("schemaVersion" to 1), reply)

        val failure = reply.failure!!
        assertEquals("PLT-001", failure.code)
        assertEquals("internalError", failure.category)
        assertEquals("platform.internal", failure.machineMessage)
        assertFalse(failure.message!!.contains("secret"))
        assertFalse(failure.message!!.contains("/tmp"))
        assertFalse(failure.details().toString().contains("secret"))
    }

    @Test
    fun securityExceptionMapsToInvalidIdentifier() {
        val facade = newFacade(service = ThrowingService(SecurityException("path")))
        val reply = RecordingReply()
        facade.handle("store.status", mapOf("schemaVersion" to 1), reply)
        assertFailure(reply, "PLT-002")
    }

    @Test
    fun unknownCatalogCodeIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            PlatformFailure("EVIL-999", "storageFull", true, "save.noSpace")
        }
    }

    @Test
    fun contentBearingFailureMessageIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            PlatformFailure("SAVE-001", "storageFull", true, "Titel /tmp/antrag.pdf")
        }
    }

    @Test
    fun sensitiveMachineMessageNamespaceIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            PlatformFailure("SAVE-001", "storageFull", true, "antrag.secret")
        }
    }

    @Test
    fun sensitiveMessageSuffixIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            PlatformFailure("SAVE-001", "storageFull", true, "save.antrag")
        }
        assertThrows(IllegalArgumentException::class.java) {
            PlatformFailure("SAVE-001", "storageFull", true, "save.documentTitle")
        }
    }

    @Test
    fun legitimateErrorMappingsRemainAccepted() {
        val mappings = listOf(
            "platform.invalidPayload" to "PLT-003",
            "save.storageFull" to "SAVE-001",
            "save.noSpace" to "SAVE-001",
            "save.keyUnavailable" to "SAVE-002",
            "save.corruptData" to "SAVE-003",
            "save.schemaTooNew" to "SAVE-005",
            "save.concurrentWrite" to "SAVE-006",
            "import.passwordProtected" to "IMP-001",
            "import.unreadable" to "IMP-002",
            "import.tooLarge" to "IMP-007",
            "export.blocked" to "EXP-001",
            "export.missingGlyph" to "EXP-004",
            "ocr.unavailable" to "REC-001",
            "page.renderFailed" to "PAGE-001",
            "delivery.cancelled" to "DEL-001",
        )
        mappings.forEach { (message, code) ->
            val failure = PlatformFailure(code, "storageFull", true, message)
            assertEquals(message, failure.machineMessage)
        }
    }

    @Test
    fun documentTitleCategoryIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            PlatformFailure("SAVE-001", "documentTitle", true, "save.noSpace")
        }
    }

    @Test
    fun singleTokenFailureMessageIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            PlatformFailure("SAVE-001", "storageFull", true, "antrag")
        }
    }

    @Test
    fun contentBearingFailureCategoryIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            PlatformFailure("SAVE-001", "storage full", true, "save.noSpace")
        }
    }

    @Test
    fun negativeFailureCountersAreRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            PlatformFailure("SAVE-001", "storageFull", true, "save.noSpace", pageIndex = -1)
        }
        assertThrows(IllegalArgumentException::class.java) {
            PlatformFailure("SAVE-001", "storageFull", true, "save.noSpace", fieldCount = -1)
        }
        assertThrows(IllegalArgumentException::class.java) {
            PlatformFailure("SAVE-001", "storageFull", true, "save.noSpace", durationMs = -1L)
        }
    }

    @Test
    fun everyCatalogCodeFamilyRemainsConstructible() {
        val codes = listOf(
            "IMP-007", "SAVE-008", "EXP-005", "REC-004", "PAGE-001",
            "TPL-001", "DEL-003", "DATE-001", "NUM-001", "FLD-001",
            "PRIV-001", "PLT-003", "SIM-001",
        )
        codes.forEach { code ->
            val failure = PlatformFailure(code, "storageFull", true, "save.noSpace")
            assertEquals(code, failure.code)
        }
    }

    @Test
    fun validationErrorCarriesDuration() {
        val times = java.util.ArrayDeque(listOf(1000L, 1005L))
        val facade = newFacade(clock = { times.removeFirst() })
        val reply = RecordingReply()
        facade.handle("store.status", emptyMap<String, Any?>(), reply)
        assertFailure(reply, "PLT-003")
        assertEquals(5L, reply.failure?.durationMs)
    }

    // ---- threading and cancellation ----------------------------------------

    @Test
    fun callIsDispatchedToExecutorAndResultIsPosted() {
        val executor = QueueExecutor()
        val poster = QueuePoster()
        val facade = newFacade(executor = executor, poster = poster)
        val reply = RecordingReply()

        facade.handle("store.status", mapOf("schemaVersion" to 1), reply)

        assertNull(reply.successValue)
        assertNull(reply.failure)
        executor.runNext()
        assertNull(reply.successValue)
        poster.runAll()
        assertNull(reply.failure)
        assertEquals(true, (reply.successValue as Map<*, *>)["ok"])
    }

    @Test
    fun executorRejectionFailsClosed() {
        val facade = newFacade(executor = RejectingExecutor)
        val reply = RecordingReply()
        facade.handle("store.status", mapOf("schemaVersion" to 1), reply)
        assertFailure(reply, "PLT-001")
        assertEquals("capacity", reply.failure?.category)
        assertEquals(true, reply.failure?.retryable)
    }

    @Test
    fun queuedOperationCanBeCancelledBeforeDispatch() {
        val executor = QueueExecutor()
        val facade = newFacade(
            executor = executor,
            operationIdFactory = { operationId },
        )
        val workReply = RecordingReply()
        facade.handle("store.status", mapOf("schemaVersion" to 1), workReply)

        val cancelReply = RecordingReply()
        facade.handle(
            "cancel.operation",
            mapOf("schemaVersion" to 1, "operationId" to operationId),
            cancelReply,
        )
        assertEquals(mapOf("cancelled" to true), (cancelReply.successValue as Map<*, *>)["data"])

        executor.runNext()
        assertFailure(workReply, "PLT-004")
    }

    @Test
    fun asyncStartReplyCarriesIdAndQueuedCancelPublishesResult() {
        val executor = QueueExecutor()
        val results = PlatformResultPublisher(DirectPoster)
        val sink = RecordingSink()
        results.attachSink(sink)
        val facade = newFacade(executor = executor, results = results)
        val startReply = RecordingReply()

        facade.handle("store.saveRevision", saveRevisionPayload(documentId), startReply)
        val operationId = startOperationId(startReply)
        assertEquals(1, executor.tasks.size)

        val cancelReply = RecordingReply()
        facade.handle(
            "cancel.operation",
            mapOf("schemaVersion" to 1, "operationId" to operationId),
            cancelReply,
        )
        assertEquals(mapOf("cancelled" to true), (cancelReply.successValue as Map<*, *>)["data"])

        val result = resultFor(sink, operationId)
        assertEquals(false, result["ok"])
        assertEquals("PLT-004", (result["error"] as Map<*, *>)["code"])

        executor.runNext()
        assertEquals(1, sink.events.size)
    }

    @Test
    fun sameDocumentSecondSaveReturnsSave006() {
        val executor = ManualExecutor()
        val service = ConcurrencyService()
        val results = PlatformResultPublisher(DirectPoster)
        val sink = RecordingSink()
        results.attachSink(sink)
        val facade = newFacade(service = service, executor = executor, results = results)
        val first = RecordingReply()
        val second = RecordingReply()

        facade.handle("store.saveRevision", saveRevisionPayload(documentId), first)
        val firstId = startOperationId(first)
        facade.handle("store.saveRevision", saveRevisionPayload(documentId), second)

        assertEquals(1, executor.tasks.size)
        assertFailure(second, "SAVE-006")
        assertEquals("concurrentWrite", second.failure?.category)
        assertEquals(true, second.failure?.retryable)
        assertNull(first.failure)

        executor.runNext()
        assertEquals(1, service.calls)
        assertEquals(true, resultFor(sink, firstId)["ok"])

        val third = RecordingReply()
        facade.handle("store.saveRevision", saveRevisionPayload(documentId), third)
        val thirdId = startOperationId(third)
        assertNull(third.failure)
        executor.runNext()
        assertEquals(2, service.calls)
        assertEquals(true, resultFor(sink, thirdId)["ok"])
    }

    @Test
    fun serialQueuesAreBoundedPerAggregate() {
        val executor = ManualExecutor()
        val service = ConcurrencyService()
        val facade = newFacade(servicePrefix = "ocr", service = service, executor = executor)

        repeat(8) {
            val reply = RecordingReply()
            facade.handle("ocr.recognize", ocrPayload(10, 10, "gray8", 100), reply)
            assertNull(reply.failure)
        }
        assertEquals(1, executor.tasks.size)

        val overflow = RecordingReply()
        facade.handle("ocr.recognize", ocrPayload(10, 10, "gray8", 100), overflow)
        assertFailure(overflow, "PLT-001")
        assertEquals("capacity", overflow.failure?.category)

        executor.runNext()
        assertEquals(8, service.calls)
    }

    @Test
    fun serialQueueTotalIsBoundedAcrossAggregates() {
        val executor = ManualExecutor()
        val serial = KeyedSerialExecutor(
            executor = executor,
            maxPendingPerKey = 10,
            maxPendingTotal = 2,
        )
        serial.submit("a") {}
        serial.submit("b") {}
        assertThrows(RejectedExecutionException::class.java) {
            serial.submit("c") {}
        }
        assertEquals(2, executor.tasks.size)
    }

    @Test
    fun queuedCancellationRemovesTaskAndFreesCapacity() {
        val executor = ManualExecutor()
        val service = ConcurrencyService()
        val results = PlatformResultPublisher(DirectPoster)
        val sink = RecordingSink()
        results.attachSink(sink)
        val facade = newFacade(
            servicePrefix = "ocr",
            service = service,
            executor = executor,
            results = results,
        )
        val replies = (1..8).map {
            val reply = RecordingReply()
            facade.handle("ocr.recognize", ocrPayload(10, 10, "gray8", 100), reply)
            assertNull(reply.failure)
            reply
        }
        val ids = replies.map(::startOperationId)

        val cancelReply = RecordingReply()
        facade.handle(
            "cancel.operation",
            mapOf("schemaVersion" to 1, "operationId" to ids[3]),
            cancelReply,
        )
        assertEquals(mapOf("cancelled" to true), (cancelReply.successValue as Map<*, *>)["data"])
        assertEquals(false, resultFor(sink, ids[3])["ok"])

        val replacement = RecordingReply()
        facade.handle("ocr.recognize", ocrPayload(10, 10, "gray8", 100), replacement)
        val replacementId = startOperationId(replacement)
        assertEquals(1, executor.tasks.size)

        executor.runNext()
        assertEquals(8, service.calls)
        assertEquals(9, sink.events.size)
        assertEquals(true, resultFor(sink, replacementId)["ok"])
    }

    @Test
    fun asyncResultReplaysForLateListener() {
        val executor = QueueExecutor()
        val results = PlatformResultPublisher(DirectPoster)
        val facade = newFacade(servicePrefix = "ocr", executor = executor, results = results)
        val startReply = RecordingReply()

        facade.handle("ocr.recognize", ocrPayload(10, 10, "gray8", 100), startReply)
        val operationId = startOperationId(startReply)
        executor.runNext()

        val lateSink = RecordingSink()
        results.attachSink(lateSink)
        val result = resultFor(lateSink, operationId)
        assertEquals(true, result["ok"])
        assertEquals("operation.result", result["event"])
    }

    @Test
    fun asyncFailureIsPublishedAsResultNotMethodException() {
        val executor = QueueExecutor()
        val results = PlatformResultPublisher(DirectPoster)
        val sink = RecordingSink()
        results.attachSink(sink)
        val service = ThrowingService(
            PlatformFailure("SAVE-001", "storageFull", true, "save.storageFull"),
        )
        val facade = newFacade(
            servicePrefix = "ocr",
            service = service,
            executor = executor,
            results = results,
        )
        val startReply = RecordingReply()

        facade.handle("ocr.recognize", ocrPayload(10, 10, "gray8", 100), startReply)
        val operationId = startOperationId(startReply)
        executor.runNext()

        assertNull(startReply.failure)
        val result = resultFor(sink, operationId)
        assertEquals(false, result["ok"])
        val error = result["error"] as Map<*, *>
        assertEquals("SAVE-001", error["code"])
        assertEquals("save.storageFull", error["message"])
        assertTrue((error["details"] as Map<*, *>).containsKey("durationMs"))
    }

    @Test
    fun assertionErrorIsPublishedAsSafeInternalResult() {
        val executor = QueueExecutor()
        val results = PlatformResultPublisher(DirectPoster)
        val sink = RecordingSink()
        results.attachSink(sink)
        val facade = newFacade(
            servicePrefix = "ocr",
            service = ThrowingService(AssertionError("secret /private/title.pdf")),
            executor = executor,
            results = results,
        )
        val startReply = RecordingReply()
        facade.handle("ocr.recognize", ocrPayload(10, 10, "gray8", 100), startReply)
        val operationId = startOperationId(startReply)
        executor.runNext()

        assertNull(startReply.failure)
        val result = resultFor(sink, operationId)
        assertEquals(false, result["ok"])
        val error = result["error"] as Map<*, *>
        assertEquals("PLT-001", error["code"])
        assertEquals("platform.internal", error["message"])
        val details = error["details"] as Map<*, *>
        assertEquals("internalError", details["category"])
        assertFalse(result.toString().contains("secret"))
        assertFalse(result.toString().contains("/private"))
        assertEquals(1, sink.events.size)
    }

    @Test
    fun syncAssertionErrorReturnsSafePlatformException() {
        val facade = newFacade(
            service = ThrowingService(AssertionError("secret /private/title.pdf")),
        )
        val reply = RecordingReply()
        facade.handle("store.status", mapOf("schemaVersion" to 1), reply)
        assertFailure(reply, "PLT-001")
        assertEquals("internalError", reply.failure?.category)
        assertEquals("platform.internal", reply.failure?.message)
        assertFalse(reply.failure.toString().contains("secret"))
    }

    @Test
    fun assertionErrorAfterCancelPublishesOnlyCancellation() {
        val executor = ManualExecutor()
        val service = BlockingErrorService()
        val results = PlatformResultPublisher(DirectPoster)
        val sink = RecordingSink()
        results.attachSink(sink)
        val facade = newFacade(
            servicePrefix = "ocr",
            service = service,
            executor = executor,
            results = results,
        )
        val startReply = RecordingReply()
        facade.handle("ocr.recognize", ocrPayload(10, 10, "gray8", 100), startReply)
        val operationId = startOperationId(startReply)

        val worker = Thread { executor.runNext() }
        worker.start()
        assertTrue(service.entered.await(5, TimeUnit.SECONDS))

        val cancelReply = RecordingReply()
        facade.handle(
            "cancel.operation",
            mapOf("schemaVersion" to 1, "operationId" to operationId),
            cancelReply,
        )
        assertEquals(mapOf("cancelled" to true), (cancelReply.successValue as Map<*, *>)["data"])
        service.release.countDown()
        worker.join(5_000)
        assertFalse(worker.isAlive)

        val result = sink.events.single() as Map<*, *>
        assertEquals(false, result["ok"])
        assertEquals("PLT-004", (result["error"] as Map<*, *>)["code"])
    }

    @Test
    fun assertionErrorAfterDisposeEmitsNothing() {
        val executor = ManualExecutor()
        val service = BlockingErrorService()
        val results = PlatformResultPublisher(DirectPoster)
        val sink = RecordingSink()
        results.attachSink(sink)
        val facade = newFacade(
            servicePrefix = "ocr",
            service = service,
            executor = executor,
            results = results,
        )
        val startReply = RecordingReply()
        facade.handle("ocr.recognize", ocrPayload(10, 10, "gray8", 100), startReply)
        startOperationId(startReply)

        val worker = Thread { executor.runNext() }
        worker.start()
        assertTrue(service.entered.await(5, TimeUnit.SECONDS))

        facade.dispose()
        service.release.countDown()
        worker.join(5_000)
        assertFalse(worker.isAlive)
        assertTrue(sink.events.isEmpty())
    }

    @Test
    fun ocrOperationsAreSerializedConservatively() {
        val executor = ManualExecutor()
        val service = ConcurrencyService()
        val results = PlatformResultPublisher(DirectPoster)
        val facade = newFacade(
            servicePrefix = "ocr",
            service = service,
            executor = executor,
            results = results,
        )
        val first = RecordingReply()
        val second = RecordingReply()

        facade.handle("ocr.recognize", ocrPayload(10, 10, "gray8", 100), first)
        facade.handle("ocr.recognize", ocrPayload(10, 10, "gray8", 100), second)
        val firstId = startOperationId(first)
        val secondId = startOperationId(second)

        assertEquals(1, executor.tasks.size)
        executor.runNext()
        assertEquals(2, service.calls)
        assertEquals(1, service.maxActive)
        assertNull(first.failure)
        assertNull(second.failure)

        val sink = RecordingSink()
        results.attachSink(sink)
        assertEquals(true, resultFor(sink, firstId)["ok"])
        assertEquals(true, resultFor(sink, secondId)["ok"])
    }

    @Test
    fun differentDocumentOperationsAreNotGloballySerialized() {
        val executor = ManualExecutor()
        val service = ConcurrencyService()
        val results = PlatformResultPublisher(DirectPoster)
        val facade = newFacade(service = service, executor = executor, results = results)
        val first = RecordingReply()
        val second = RecordingReply()

        facade.handle("store.saveRevision", saveRevisionPayload(documentId), first)
        facade.handle("store.saveRevision", saveRevisionPayload(assetId), second)
        val firstId = startOperationId(first)
        val secondId = startOperationId(second)

        assertEquals(2, executor.tasks.size)
        executor.runNext()
        executor.runNext()
        assertEquals(2, service.calls)
        assertNull(first.failure)
        assertNull(second.failure)

        val sink = RecordingSink()
        results.attachSink(sink)
        assertEquals(true, resultFor(sink, firstId)["ok"])
        assertEquals(true, resultFor(sink, secondId)["ok"])
    }

    @Test
    fun unknownOperationCancellationIsFalse() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle(
            "cancel.operation",
            mapOf("schemaVersion" to 1, "operationId" to operationId),
            reply,
        )
        assertEquals(mapOf("cancelled" to false), (reply.successValue as Map<*, *>)["data"])
    }

    @Test
    fun invalidOperationIdIsRejected() {
        val facade = newFacade()
        val reply = RecordingReply()
        facade.handle(
            "cancel.operation",
            mapOf("schemaVersion" to 1, "operationId" to "op-1"),
            reply,
        )
        assertFailure(reply, "PLT-002")
    }

    @Test
    fun disposeShutsDownOnceAndDetachesServices() {
        val executor = TrackingExecutor()
        val publisher = PlatformEventPublisher(DirectPoster)
        val service = TrackingService()
        val facade = newFacade(service = service, executor = executor, events = publisher)
        facade.dispose()
        facade.dispose()
        assertEquals(1, executor.shutdownCount)
        assertEquals(1, service.detachedCount)

        val reply = RecordingReply()
        facade.handle("store.status", mapOf("schemaVersion" to 1), reply)
        assertFailure(reply, "PLT-001")
    }

    // ---- events -------------------------------------------------------------

    @Test
    fun lifecycleEventMatchesContractShape() {
        val publisher = PlatformEventPublisher(DirectPoster)
        val sink = RecordingSink()
        publisher.attachSink(sink)

        publisher.emitLifecycle(HostLifecycle.PAUSED)

        assertEquals(
            mapOf("event" to "lifecycle", "state" to "paused"),
            sink.events.single() as Map<*, *>,
        )
    }

    @Test
    fun storageStatusStoreEventHasNoAggregate() {
        val publisher = PlatformEventPublisher(DirectPoster)
        val sink = RecordingSink()
        publisher.attachSink(sink)

        publisher.emitStorageStatus(
            scope = "store",
            kind = null,
            itemId = null,
            keyAvailable = false,
            reasonCode = "SAVE-008",
        )

        assertEquals(
            linkedMapOf(
                "event" to "storage.status",
                "scope" to "store",
                "kind" to null,
                "itemId" to null,
                "keyAvailable" to false,
                "reasonCode" to "SAVE-008",
            ),
            sink.events.single() as Map<*, *>,
        )
    }

    @Test
    fun storageStatusAggregateEventCarriesItemId() {
        val publisher = PlatformEventPublisher(DirectPoster)
        val sink = RecordingSink()
        publisher.attachSink(sink)

        publisher.emitStorageStatus(
            scope = "aggregate",
            kind = "template",
            itemId = templateId,
            keyAvailable = false,
            reasonCode = "SAVE-002",
        )

        val event = sink.events.single() as Map<*, *>
        assertEquals("aggregate", event["scope"])
        assertEquals("template", event["kind"])
        assertEquals(templateId, event["itemId"])
        assertEquals("SAVE-002", event["reasonCode"])
    }

    @Test
    fun malformedStorageStatusIsRejected() {
        val publisher = PlatformEventPublisher(DirectPoster)
        assertThrows(IllegalArgumentException::class.java) {
            publisher.emitStorageStatus(
                scope = "store",
                kind = "document",
                itemId = documentId,
                keyAvailable = false,
                reasonCode = "SAVE-002",
            )
        }
    }

    @Test
    fun operationProgressIsCoalescedToLatestPerOperation() {
        val poster = QueuePoster()
        val publisher = PlatformEventPublisher(poster)
        val sink = RecordingSink()
        publisher.attachSink(sink)

        publisher.emitOperationProgress(operationId, "export", "importing", 0.1, 0)
        publisher.emitOperationProgress(operationId, "export", "drawing", 0.6, 0)

        assertTrue(sink.events.isEmpty())
        poster.runAll()
        assertEquals(1, sink.events.size)
        val event = sink.events.single() as Map<*, *>
        assertEquals("operation.progress", event["event"])
        assertEquals("drawing", event["phase"])
        assertEquals(0.6, event["fraction"])
    }

    @Test
    fun exportProgressUsesContractEventName() {
        val publisher = PlatformEventPublisher(DirectPoster)
        val sink = RecordingSink()
        publisher.attachSink(sink)

        publisher.emitExportProgress(operationId, "verifying", 0.9, 1)

        val event = sink.events.single() as Map<*, *>
        assertEquals("export.progress", event["event"])
        assertEquals("verifying", event["phase"])
        assertEquals(1, event["pageIndex"])
    }

    @Test
    fun importPickerResultEventMatchesContractShape() {
        val publisher = PlatformEventPublisher(DirectPoster)
        val sink = RecordingSink()
        publisher.attachSink(sink)

        publisher.emitImportPickerResult(operationId, cancelled = true)

        assertEquals(
            linkedMapOf(
                "event" to "import.pickerResult",
                "correlationId" to operationId,
                "cancelled" to true,
            ),
            sink.events.single() as Map<*, *>,
        )
    }

    @Test
    fun asyncResultMayPrecedeStartReply() {
        val results = PlatformResultPublisher(DirectPoster)
        val sink = RecordingSink()
        results.attachSink(sink)
        val facade = newFacade(
            servicePrefix = "ocr",
            executor = DirectExecutor,
            results = results,
        )
        val startReply = RecordingReply()

        facade.handle("ocr.recognize", ocrPayload(10, 10, "gray8", 100), startReply)

        val operationId = startOperationId(startReply)
        val result = resultFor(sink, operationId)
        assertEquals(true, result["ok"])
        assertEquals(operationId, result["operationId"])
    }

    @Test
    fun cancellationAfterTerminalReturnsFalse() {
        val executor = QueueExecutor()
        val results = PlatformResultPublisher(DirectPoster)
        val sink = RecordingSink()
        results.attachSink(sink)
        val facade = newFacade(
            servicePrefix = "ocr",
            executor = executor,
            results = results,
        )
        val startReply = RecordingReply()
        facade.handle("ocr.recognize", ocrPayload(10, 10, "gray8", 100), startReply)
        val operationId = startOperationId(startReply)
        executor.runNext()
        assertEquals(true, resultFor(sink, operationId)["ok"])

        val cancelReply = RecordingReply()
        facade.handle(
            "cancel.operation",
            mapOf("schemaVersion" to 1, "operationId" to operationId),
            cancelReply,
        )
        assertEquals(mapOf("cancelled" to false), (cancelReply.successValue as Map<*, *>)["data"])
    }

    @Test
    fun startRejectionEmitsNoResult() {
        val executor = ManualExecutor()
        val service = ConcurrencyService()
        val results = PlatformResultPublisher(DirectPoster)
        val sink = RecordingSink()
        results.attachSink(sink)
        val facade = newFacade(
            servicePrefix = "ocr",
            service = service,
            executor = executor,
            results = results,
        )
        repeat(8) {
            val reply = RecordingReply()
            facade.handle("ocr.recognize", ocrPayload(10, 10, "gray8", 100), reply)
            assertNull(reply.failure)
        }
        val overflow = RecordingReply()
        facade.handle("ocr.recognize", ocrPayload(10, 10, "gray8", 100), overflow)
        assertFailure(overflow, "PLT-001")
        assertTrue(sink.events.isEmpty())
    }

    @Test
    fun cancelAfterSuccessTerminalWaitsForPublishAndReturnsFalse() {
        verifyCancelAfterTerminal(
            service = ReturningService(mapOf("ok" to true)),
            expectSuccess = true,
        )
    }

    @Test
    fun cancelAfterErrorTerminalWaitsForPublishAndReturnsFalse() {
        verifyCancelAfterTerminal(
            service = ThrowingService(
                PlatformFailure("SAVE-001", "storageFull", true, "save.storageFull"),
            ),
            expectSuccess = false,
        )
    }

    @Test
    fun cancelWinsBeforeServiceReturnsAndPublishesOnlyCancellation() {
        val executor = ManualExecutor()
        val service = BlockingService()
        val results = PlatformResultPublisher(DirectPoster)
        val sink = RecordingSink()
        results.attachSink(sink)
        val facade = newFacade(
            servicePrefix = "ocr",
            service = service,
            executor = executor,
            results = results,
        )
        val startReply = RecordingReply()
        facade.handle("ocr.recognize", ocrPayload(10, 10, "gray8", 100), startReply)
        val operationId = startOperationId(startReply)

        val worker = Thread { executor.runNext() }
        worker.start()
        assertTrue(service.entered.await(5, TimeUnit.SECONDS))

        val cancelReply = RecordingReply()
        facade.handle(
            "cancel.operation",
            mapOf("schemaVersion" to 1, "operationId" to operationId),
            cancelReply,
        )
        assertEquals(mapOf("cancelled" to true), (cancelReply.successValue as Map<*, *>)["data"])
        service.release.countDown()
        worker.join(5_000)
        assertFalse(worker.isAlive)

        val result = sink.events.single() as Map<*, *>
        assertEquals(false, result["ok"])
        assertEquals("PLT-004", (result["error"] as Map<*, *>)["code"])
    }

    @Test
    fun disposeDuringResultPublishDoesNotDeliverOrReplay() {
        val poster = BlockingPoster()
        val publisher = PlatformResultPublisher(poster)
        val publishThread = Thread {
            publisher.publish(resultMap("11111111-1111-4111-8111-111111111111"))
        }
        publishThread.start()
        assertTrue(poster.entered.await(5, TimeUnit.SECONDS))

        publisher.dispose()
        val sink = RecordingSink()
        publisher.attachSink(sink)
        poster.release.countDown()
        publishThread.join(5_000)
        assertFalse(publishThread.isAlive)

        assertTrue(sink.events.isEmpty())
    }

    @Test
    fun resultPublisherRetentionIsBounded() {
        val publisher = PlatformResultPublisher(DirectPoster, maxRetained = 2)
        publisher.publish(resultMap("11111111-1111-4111-8111-111111111111"))
        publisher.publish(resultMap("22222222-2222-4222-8222-222222222222"))
        publisher.publish(resultMap("33333333-3333-4333-8333-333333333333"))

        val sink = RecordingSink()
        publisher.attachSink(sink)
        assertEquals(2, sink.events.size)
        assertEquals("22222222-2222-4222-8222-222222222222", (sink.events[0] as Map<*, *>)["operationId"])
        assertEquals("33333333-3333-4333-8333-333333333333", (sink.events[1] as Map<*, *>)["operationId"])
    }

    @Test
    fun resultPublisherRetainsAcrossListenerDetach() {
        val publisher = PlatformResultPublisher(DirectPoster)
        val first = RecordingSink()
        publisher.attachSink(first)
        publisher.publish(resultMap("11111111-1111-4111-8111-111111111111"))
        assertEquals(1, first.events.size)

        publisher.attachSink(null)
        publisher.publish(resultMap("22222222-2222-4222-8222-222222222222"))
        val second = RecordingSink()
        publisher.attachSink(second)
        assertEquals(2, second.events.size)
    }

    @Test
    fun disposedResultPublisherEmitsNothing() {
        val publisher = PlatformResultPublisher(DirectPoster)
        publisher.dispose()
        publisher.publish(resultMap("11111111-1111-4111-8111-111111111111"))
        val sink = RecordingSink()
        publisher.attachSink(sink)
        assertTrue(sink.events.isEmpty())
    }

    @Test
    fun asyncStartReplyContainsOnlyOperationId() {
        val executor = QueueExecutor()
        val facade = newFacade(servicePrefix = "ocr", executor = executor)
        val reply = RecordingReply()
        facade.handle("ocr.recognize", ocrPayload(10, 10, "gray8", 100), reply)
        val data = (reply.successValue as Map<*, *>)["data"] as Map<*, *>
        assertEquals(setOf("operationId"), data.keys)
        assertEquals(1, data.size)
    }

    @Test
    fun disposedPublisherEmitsNothing() {
        val poster = QueuePoster()
        val publisher = PlatformEventPublisher(poster)
        val sink = RecordingSink()
        publisher.attachSink(sink)

        publisher.dispose()
        publisher.emitLifecycle(HostLifecycle.RESUMED)
        publisher.emitOperationProgress(operationId, "export", "drawing", 0.5)
        poster.runAll()

        assertTrue(sink.events.isEmpty())
    }

    @Test
    fun serviceCanReportProgressThroughOperationContext() {
        val publisher = PlatformEventPublisher(DirectPoster)
        val sink = RecordingSink()
        publisher.attachSink(sink)
        val service = object : PlatformService {
            override fun handle(request: PlatformRequest, context: OperationContext): Any? {
                context.progress("export", "drawing", 0.5, 0)
                return mapOf("ok" to true)
            }
        }
        val facade = newFacade(service = service, events = publisher)
        val reply = RecordingReply()

        facade.handle("store.status", mapOf("schemaVersion" to 1), reply)

        assertNull(reply.failure)
        assertEquals("operation.progress", (sink.events.single() as Map<*, *>)["event"])
    }

    @Test
    fun serviceExportProgressUsesExportEvent() {
        val publisher = PlatformEventPublisher(DirectPoster)
        val sink = RecordingSink()
        publisher.attachSink(sink)
        val service = object : PlatformService {
            override fun handle(request: PlatformRequest, context: OperationContext): Any? {
                context.exportProgress("verifying", 0.9)
                return mapOf("ok" to true)
            }
        }
        val facade = newFacade(service = service, events = publisher)
        val reply = RecordingReply()

        facade.handle("store.status", mapOf("schemaVersion" to 1), reply)

        assertEquals("export.progress", (sink.events.single() as Map<*, *>)["event"])
    }

    // ---- registry -----------------------------------------------------------

    @Test
    fun duplicateServiceRegistrationIsRejected() {
        val registry = PlatformServiceRegistry()
        registry.register("store", ReturningService(emptyMap<String, Any?>()))
        assertThrows(IllegalStateException::class.java) {
            registry.register("store", ReturningService(emptyMap<String, Any?>()))
        }
    }

    @Test
    fun unknownServicePrefixIsRejected() {
        val registry = PlatformServiceRegistry()
        assertThrows(IllegalArgumentException::class.java) {
            registry.register("filesystem", ReturningService(emptyMap<String, Any?>()))
        }
    }

    @Test
    fun unregisterRemovesService() {
        val registry = PlatformServiceRegistry()
        registry.register("store", ReturningService(emptyMap<String, Any?>()))
        registry.unregister("store")
        assertNull(registry.serviceFor("store.status"))
    }

    // ---- helpers ------------------------------------------------------------

    private fun ocrPayload(
        width: Int,
        height: Int,
        format: String,
        bytes: Int,
    ): Map<String, Any?> = mapOf(
        "schemaVersion" to 1,
        "pageIndex" to 0,
        "imageWidth" to width,
        "imageHeight" to height,
        "pageWidthPt" to 100.0,
        "pageHeightPt" to 100.0,
        "format" to format,
        "bytes" to ByteArray(bytes),
        "language" to "de",
    )

    private fun saveRevisionPayload(documentId: String): Map<String, Any?> = mapOf(
        "schemaVersion" to 1,
        "documentId" to documentId,
        "revision" to mapOf("value" to "x"),
        "expectedHead" to null,
        "kind" to "autosave",
    )

    private fun resultMap(operationId: String): Map<String, Any?> = linkedMapOf(
        "schemaVersion" to 1,
        "event" to "operation.result",
        "operationId" to operationId,
        "ok" to true,
        "data" to mapOf("ok" to true),
    )

    private fun verifyCancelAfterTerminal(service: PlatformService, expectSuccess: Boolean) {
        val executor = QueueExecutor()
        val poster = BlockingPoster()
        val results = PlatformResultPublisher(poster)
        val sink = RecordingSink()
        results.attachSink(sink)
        val facade = newFacade(
            servicePrefix = "ocr",
            service = service,
            executor = executor,
            results = results,
        )
        val startReply = RecordingReply()
        facade.handle("ocr.recognize", ocrPayload(10, 10, "gray8", 100), startReply)
        val operationId = startOperationId(startReply)

        val worker = Thread { executor.runNext() }
        worker.start()
        assertTrue(poster.entered.await(5, TimeUnit.SECONDS))

        val cancelStarted = CountDownLatch(1)
        val cancelDone = CountDownLatch(1)
        val cancelReply = RecordingReply()
        val canceller = Thread {
            cancelStarted.countDown()
            facade.handle(
                "cancel.operation",
                mapOf("schemaVersion" to 1, "operationId" to operationId),
                cancelReply,
            )
            cancelDone.countDown()
        }
        canceller.start()
        assertTrue(cancelStarted.await(5, TimeUnit.SECONDS))
        assertFalse(cancelDone.await(100, TimeUnit.MILLISECONDS))

        poster.release.countDown()
        worker.join(5_000)
        canceller.join(5_000)
        assertFalse(worker.isAlive)
        assertFalse(canceller.isAlive)

        assertEquals(mapOf("cancelled" to false), (cancelReply.successValue as Map<*, *>)["data"])
        val result = sink.events.single() as Map<*, *>
        assertEquals(expectSuccess, result["ok"])
    }

    private fun startOperationId(reply: RecordingReply): String {
        assertNull(reply.failure)
        val envelope = reply.successValue as Map<*, *>
        assertEquals(true, envelope["ok"])
        val data = envelope["data"] as Map<*, *>
        val operationId = data["operationId"] as String
        assertTrue(operationId.isNotEmpty())
        return operationId
    }

    private fun resultFor(sink: RecordingSink, operationId: String): Map<*, *> =
        sink.events
            .map { it as Map<*, *> }
            .last { it["event"] == "operation.result" && it["operationId"] == operationId }

    private fun newFacade(
        servicePrefix: String? = "store",
        service: PlatformService = ReturningService(linkedMapOf("ok" to true)),
        executor: BackgroundExecutor = DirectExecutor,
        poster: ThreadPoster = DirectPoster,
        events: PlatformEventPublisher = PlatformEventPublisher(poster),
        results: PlatformResultPublisher = PlatformResultPublisher(poster),
        limits: ChannelLimits = ChannelLimits(),
        operationIdFactory: () -> String = { UUID.randomUUID().toString() },
        clock: () -> Long = { 0L },
    ): PlatformChannelFacade {
        val services = PlatformServiceRegistry()
        if (servicePrefix != null) services.register(servicePrefix, service)
        return PlatformChannelFacade(
            services = services,
            mainPoster = poster,
            events = events,
            results = results,
            executor = executor,
            limits = limits,
            operationIdFactory = operationIdFactory,
            clock = clock,
        )
    }

    private fun assertFailure(reply: RecordingReply, code: String) {
        assertNull("expected failure $code but got success ${reply.successValue}", reply.successValue)
        assertEquals(code, reply.failure?.code)
    }

    /** StandardMessageCodec's variable-width byte-array/map/list size prefix. */
    private fun sizePrefix(length: Long): Long = when {
        length < 254L -> 1L
        length <= 0xffffL -> 3L
        else -> 5L
    }

    /**
     * `BigInteger` test double that counts the exact-path `bitCount()` calls.
     * `bitCount()` is the only O(magnitude) operation in the negative
     * disambiguation, so a zero count is deterministic proof that a rejection
     * never scanned the magnitude. The counters are reset after construction
     * so only the measured call is observed.
     */
    private class BitCountTrackingBigInteger(signum: Int, magnitude: ByteArray) :
        BigInteger(signum, magnitude) {
        var bitCountCalls = 0
        var bitLengthCalls = 0

        override fun toByte(): Byte = toInt().toByte()

        override fun toShort(): Short = toInt().toShort()

        override fun bitCount(): Int {
            bitCountCalls++
            return super.bitCount()
        }

        override fun bitLength(): Int {
            bitLengthCalls++
            return super.bitLength()
        }
    }

    private class ReturningService(private val data: Any?) : PlatformService {
        override fun handle(request: PlatformRequest, context: OperationContext): Any? = data
    }

    private class ThrowingService(private val error: Throwable) : PlatformService {
        override fun handle(request: PlatformRequest, context: OperationContext): Any? = throw error
    }

    private class RecordingReply : ChannelReply {
        var successValue: Any? = null
        var failure: PlatformFailure? = null

        override fun success(result: Any?) {
            successValue = result
        }

        override fun error(failure: PlatformFailure) {
            this.failure = failure
        }
    }

    private class RecordingSink : FeldexaEventSink {
        val events = mutableListOf<Any?>()

        override fun success(event: Any?) {
            events += event
        }
    }

    private object DirectPoster : ThreadPoster {
        override fun post(block: () -> Unit) = block()
    }

    private class QueuePoster : ThreadPoster {
        private val blocks = mutableListOf<() -> Unit>()

        override fun post(block: () -> Unit) {
            blocks += block
        }

        fun runAll() {
            while (blocks.isNotEmpty()) blocks.removeAt(0).invoke()
        }
    }

    private object DirectExecutor : BackgroundExecutor {
        override fun execute(task: () -> Unit) = task()
        override fun shutdown() = Unit
    }

    private class QueueExecutor : BackgroundExecutor {
        val tasks = mutableListOf<() -> Unit>()

        override fun execute(task: () -> Unit) {
            tasks += task
        }

        override fun shutdown() {
            tasks.clear()
        }

        fun runNext() {
            tasks.removeAt(0).invoke()
        }
    }

    private object RejectingExecutor : BackgroundExecutor {
        override fun execute(task: () -> Unit) {
            throw RejectedExecutionException("full")
        }

        override fun shutdown() = Unit
    }

    private class TrackingExecutor : BackgroundExecutor {
        var shutdownCount = 0

        override fun execute(task: () -> Unit) = task()
        override fun shutdown() {
            shutdownCount++
        }
    }

    private class BlockingPoster : ThreadPoster {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)

        override fun post(block: () -> Unit) {
            entered.countDown()
            release.await(5, TimeUnit.SECONDS)
            block()
        }
    }

    private class BlockingService : PlatformService {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)

        override fun handle(request: PlatformRequest, context: OperationContext): Any? {
            entered.countDown()
            release.await(5, TimeUnit.SECONDS)
            return mapOf("ok" to true)
        }
    }

    private class BlockingErrorService : PlatformService {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)

        override fun handle(request: PlatformRequest, context: OperationContext): Any? {
            entered.countDown()
            release.await(5, TimeUnit.SECONDS)
            throw AssertionError("secret /private/title.pdf")
        }
    }

    private class ManualExecutor : BackgroundExecutor {
        val tasks = mutableListOf<() -> Unit>()

        override fun execute(task: () -> Unit) {
            tasks += task
        }

        override fun shutdown() {
            tasks.clear()
        }

        fun runNext() {
            tasks.removeAt(0).invoke()
        }
    }

    private class ConcurrencyService : PlatformService {
        var calls = 0
        var active = 0
        var maxActive = 0

        override fun handle(request: PlatformRequest, context: OperationContext): Any? {
            calls++
            active++
            maxActive = maxOf(maxActive, active)
            active--
            return mapOf("ok" to true)
        }
    }

    private class TrackingService : PlatformService {
        var detachedCount = 0

        override fun handle(request: PlatformRequest, context: OperationContext): Any? =
            mapOf("ok" to true)

        override fun onFacadeDetached() {
            detachedCount++
        }
    }
}
