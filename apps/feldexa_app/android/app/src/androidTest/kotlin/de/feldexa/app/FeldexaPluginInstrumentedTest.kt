package de.feldexa.app

import android.app.Instrumentation
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.FlutterException
import io.flutter.plugin.common.StandardMethodCodec
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.platform.PlatformViewRegistry
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * T024 `EMULATOR` instrumentation tests for the Flutter platform-channel facade.
 *
 * The tests attach the real [FeldexaPlugin] to an in-process [BinaryMessenger]
 * and drive the actual `MethodChannel`/`EventChannel` boundary with
 * [StandardMethodCodec]. They therefore exercise the platform-channel envelope,
 * channel names, handler registration, the real Android main `Looper`, the
 * bounded executor, and channel teardown on an Android runtime. They use only
 * synthetic ids and in-memory fake services: no document, file, URI, Keystore,
 * or device data is created, read, or deleted.
 *
 * This is the T024 instrumentation layer required by
 * `contracts/platform-channel.md` §12. It is not a Dart-engine end-to-end test;
 * that limitation is recorded in the evidence report.
 */
@RunWith(AndroidJUnit4::class)
class FeldexaPluginInstrumentedTest {

    private val documentId = "123e4567-e89b-42d3-a456-426614174000"
    private val assetId = "123e4567-e89b-42d3-a456-426614174001"
    private val templateId = "123e4567-e89b-42d3-a456-426614174002"
    private val artifactId = "123e4567-e89b-42d3-a456-426614174003"
    private val operationId = "123e4567-e89b-42d3-a456-426614174004"

    private lateinit var instrumentation: Instrumentation
    private lateinit var messenger: RecordingMessenger
    private lateinit var binding: FlutterPlugin.FlutterPluginBinding
    private lateinit var engine: FlutterEngine
    private lateinit var plugin: FeldexaPlugin

    private val codec = StandardMethodCodec.INSTANCE

    @Before
    fun setUp() {
        instrumentation = InstrumentationRegistry.getInstrumentation()
        messenger = RecordingMessenger()
        val context = instrumentation.targetContext
        instrumentation.runOnMainSync {
            engine = FlutterEngine(context)
            binding = FlutterPlugin.FlutterPluginBinding(
                context,
                engine,
                messenger,
                engine.renderer,
                NoPlatformViews,
                NoAssets,
                FlutterEngineGroup(context),
            )
            plugin = FeldexaPlugin()
            plugin.onAttachedToEngine(binding)
        }
    }

    @After
    fun tearDown() {
        instrumentation.runOnMainSync {
            if (this::plugin.isInitialized) plugin.onDetachedFromEngine(binding)
            if (this::engine.isInitialized) engine.destroy()
        }
        instrumentation.waitForIdleSync()
    }

    /**
     * Rebuilds the in-process engine with test [ChannelLimits] so the real
     * MethodChannel + StandardMethodCodec boundary can be exercised at small
     * byte limits without allocating a second 96 MiB payload.
     */
    private fun reattachWithLimits(limits: ChannelLimits) {
        instrumentation.runOnMainSync {
            plugin.onDetachedFromEngine(binding)
            engine.destroy()
            messenger = RecordingMessenger()
            val context = instrumentation.targetContext
            engine = FlutterEngine(context)
            binding = FlutterPlugin.FlutterPluginBinding(
                context,
                engine,
                messenger,
                engine.renderer,
                NoPlatformViews,
                NoAssets,
                FlutterEngineGroup(context),
            )
            plugin = FeldexaPlugin(limits)
            plugin.onAttachedToEngine(binding)
        }
    }

    // ---- registration and envelope -----------------------------------------

    @Test
    fun platformChannelIsRegisteredAndSyncCallReturnsSuccessEnvelope() {
        val data = linkedMapOf<String, Any?>("keyAvailable" to true, "objectCount" to 2, "totalBytes" to 10)
        plugin.registerService("store", ReturningService(data))

        val envelope = invoke("store.status", mapOf("schemaVersion" to 1))

        assertEquals(1, envelope["schemaVersion"])
        assertEquals(true, envelope["ok"])
        assertEquals(data, envelope["data"])
        assertTrue(messenger.hasHandler(FeldexaChannels.EVENTS))
        assertTrue(messenger.hasHandler(FeldexaChannels.RESULTS))
    }

    @Test
    fun everyContractMethodAcceptsMinimalPayloadThroughRealChannels() {
        registerAllServices()
        assertEquals("contract method inventory", 24, minimalPayloads().size)

        val failures = mutableListOf<String>()
        for ((method, payload) in minimalPayloads()) {
            try {
                val envelope = invoke(method, withSchema(payload))
                when {
                    envelope["ok"] != true -> failures += "$method -> not ok"
                    method in ASYNC_METHODS -> {
                        val data = envelope["data"] as? Map<*, *>
                        if (data == null || data.keys != setOf("operationId")) {
                            failures += "$method -> start reply is not operationId-only"
                        }
                    }
                }
            } catch (failure: FlutterException) {
                failures += "$method -> ${failure.code}"
            }
        }
        assertTrue(failures.joinToString(), failures.isEmpty())
    }

    // ---- asynchronous start and terminal result ----------------------------

    @Test
    fun asyncCallReturnsOperationIdAndPublishesOneTerminalResult() {
        val data = mapOf("recognized" to false)
        plugin.registerService("ocr", ReturningService(data))
        listenResults()

        val start = invoke("ocr.recognize", ocrPayload())
        val operationId = startOperationId(start)
        assertEquals(setOf("operationId"), (start["data"] as Map<*, *>).keys)

        val result = awaitResult(operationId)
        assertEquals("operation.result", result["event"])
        assertEquals(true, result["ok"])
        assertEquals(data, result["data"])
        assertNoMoreResults(operationId)
    }

    @Test
    fun asyncFailureIsPublishedAsResultNotMethodException() {
        plugin.registerService(
            "ocr",
            ThrowingService(PlatformFailure("SAVE-001", "storageFull", true, "save.storageFull")),
        )
        listenResults()

        val start = invoke("ocr.recognize", ocrPayload())
        val operationId = startOperationId(start)

        val result = awaitResult(operationId)
        assertEquals(false, result["ok"])
        val error = result["error"] as Map<*, *>
        assertEquals("SAVE-001", error["code"])
        assertEquals("save.storageFull", error["message"])
        assertNoMoreResults(operationId)
    }

    @Test
    fun serviceAssertionErrorPublishesOneSafeInternalResult() {
        plugin.registerService("ocr", ThrowingService(AssertionError("secret /private/title.pdf")))
        listenResults()

        val start = invoke("ocr.recognize", ocrPayload())
        val operationId = startOperationId(start)

        val result = awaitResult(operationId)
        assertEquals(false, result["ok"])
        val error = result["error"] as Map<*, *>
        assertEquals("PLT-001", error["code"])
        assertEquals("platform.internal", error["message"])
        assertEquals("internalError", (error["details"] as Map<*, *>)["category"])

        val rendered = result.toString()
        assertFalse(rendered.contains("secret"))
        assertFalse(rendered.contains("/private"))
        assertFalse(rendered.contains("AssertionError"))
        assertFalse(rendered.contains("java.lang"))
        assertFalse(rendered.contains("FeldexaPluginInstrumentedTest"))
        assertNoMoreResults(operationId)
    }

    // ---- rejection has no operation and no result --------------------------

    @Test
    fun validationFailureRejectsWithFlutterExceptionAndEmitsNoResult() {
        plugin.registerService("store", ReturningService(mapOf("ok" to true)))
        listenResults()

        val failure = invokeFailure("store.status", mapOf("schemaVersion" to 1, "unknown" to true))
        assertEquals("PLT-003", failure.code)
        assertNoResults()
    }

    @Test
    fun everyMethodRejectsAnUnknownField() {
        registerAllServices()
        val failures = mutableListOf<String>()
        for ((method, payload) in minimalPayloads()) {
            val failure = invokeFailure(method, withSchema(payload) + ("unknown" to true))
            if (failure.code != "PLT-003" || failure.message != "platform.unknownField") {
                failures += "$method -> ${failure.code}/${failure.message}"
            }
        }
        assertTrue(failures.joinToString(), failures.isEmpty())
    }

    @Test
    fun everyDeclaredUuidFieldRejectsStrictRegexViolations() {
        registerAllServices()
        val minimal = minimalPayloads()

        // Guard the explicit contract inventory against the payload table in
        // both directions, so a copied or mistyped field cannot silently skip
        // a method.
        for ((method, fields) in UUID_FIELDS) {
            val payload = minimal[method] ?: throw AssertionError("UUID_FIELDS names unknown method $method")
            for (field in fields) {
                assertTrue("$method.$field is missing from the minimal payload", payload.containsKey(field))
            }
        }
        val observed = minimal.flatMap { (method, payload) ->
            payload.filterValues { it is String && UUID_PATTERN.matches(it) }
                .keys.map { method to it }
        }.toSet() + OPTIONAL_UUID_FIELDS
        val declared = UUID_FIELDS.flatMap { (method, fields) -> fields.map { method to it } }.toSet()
        assertEquals("UUID field inventory", declared, observed)

        val failures = mutableListOf<String>()
        for ((method, fields) in UUID_FIELDS) {
            val payload = minimal.getValue(method)
            for (field in fields) {
                for (invalid in INVALID_UUIDS) {
                    val failure = invokeFailure(method, withSchema(payload) + (field to invalid))
                    if (failure.code != "PLT-002" || failure.message != "platform.identifier") {
                        failures += "$method.$field=${invalid.ifEmpty { "<empty>" }} -> ${failure.code}/${failure.message}"
                    }
                }
            }
        }
        assertTrue(failures.joinToString(), failures.isEmpty())
    }

    @Test
    fun everyMethodRejectsPayloadExceedingGlobalLimit() {
        registerAllServices()
        val failures = mutableListOf<String>()
        val oversized = ByteArray(96 * 1024 * 1024 + 1)
        for ((method, payload) in minimalPayloads()) {
            // `schemaVersion` is the only field every method declares, so the
            // huge value is accepted by the field allowlist and the total-size
            // guard must reject it before any type rule. This asserts the
            // contract's 96 MiB method-payload limit, not a field limit.
            val failure = invokeFailure(method, payload + ("schemaVersion" to oversized))
            if (failure.code != "PLT-003" || failure.message != "platform.payloadTooLarge") {
                failures += "$method -> ${failure.code}/${failure.message}"
            }
        }
        assertTrue(failures.joinToString(), failures.isEmpty())
    }

    @Test
    fun payloadLimitMatchesActualStandardMethodCodecEnvelopeAtBoundary() {
        val method = "import.pickAndImport"
        val titleHint = "a".repeat(40)
        val payload = mapOf("schemaVersion" to 1, "maxBytes" to 1024, "titleHint" to titleHint)

        // The real Flutter codec, not a hand formula, defines the boundary:
        // method name 22 + root map 2 + keys 36 + values 10 + string 42.
        val encoded = codec.encodeMethodCall(MethodCall(method, payload))
        val exactBytes = encoded.limit().toLong()
        assertEquals(72L + titleHint.length, exactBytes)
        assertEquals(exactBytes, PayloadSize.measureMethodCall(method, payload, Long.MAX_VALUE))

        reattachWithLimits(ChannelLimits(maxPayloadBytes = exactBytes))
        plugin.registerService("import", ReturningService(mapOf("ok" to true)))
        assertEquals(true, invoke(method, payload)["ok"])

        reattachWithLimits(ChannelLimits(maxPayloadBytes = exactBytes - 1))
        plugin.registerService("import", ReturningService(mapOf("ok" to true)))
        val failure = invokeFailure(method, payload)
        assertEquals("PLT-003", failure.code)
        assertEquals("platform.payloadTooLarge", failure.message)
    }

    @Test
    fun missingServiceRejectsWithUnsupportedAndEmitsNoResult() {
        listenResults()

        val failure = invokeFailure("store.status", mapOf("schemaVersion" to 1))
        assertEquals("PLT-001", failure.code)
        assertNoResults()
    }

    @Test
    fun concurrentSaveForSameDocumentRejectsBeforeStart() {
        val service = BlockingService()
        plugin.registerService("store", service)
        listenResults()
        val payload = mapOf(
            "schemaVersion" to 1,
            "documentId" to documentId,
            "revision" to mapOf("value" to "x"),
            "expectedHead" to null,
            "kind" to "autosave",
        )

        val start = invoke("store.saveRevision", payload)
        val operationId = startOperationId(start)
        assertTrue(service.entered.await(5, TimeUnit.SECONDS))

        val failure = invokeFailure("store.saveRevision", payload)
        assertEquals("SAVE-006", failure.code)
        assertNoResults()

        service.release.countDown()
        val result = awaitResult(operationId)
        assertEquals(true, result["ok"])
        assertNoMoreResults(operationId)
    }

    // ---- cancellation and replay -------------------------------------------

    @Test
    fun runningCancellationPublishesOnlyCancellationAndTerminalCancelReturnsFalse() {
        val service = BlockingService()
        plugin.registerService("ocr", service)
        listenResults()

        val start = invoke("ocr.recognize", ocrPayload())
        val operationId = startOperationId(start)
        assertTrue(service.entered.await(5, TimeUnit.SECONDS))

        val cancel = invoke(
            "cancel.operation",
            mapOf("schemaVersion" to 1, "operationId" to operationId),
        )
        assertEquals(mapOf("cancelled" to true), cancel["data"])
        service.release.countDown()

        val result = awaitResult(operationId)
        assertEquals(false, result["ok"])
        assertEquals("PLT-004", (result["error"] as Map<*, *>)["code"])
        assertNoMoreResults(operationId)

        val afterTerminal = invoke(
            "cancel.operation",
            mapOf("schemaVersion" to 1, "operationId" to operationId),
        )
        assertEquals(mapOf("cancelled" to false), afterTerminal["data"])
    }

    @Test
    fun resultCompletedBeforeListenerAttachIsReplayed() {
        val data = mapOf("recognized" to true)
        plugin.registerService("ocr", ReturningService(data))

        val start = invoke("ocr.recognize", ocrPayload())
        val operationId = startOperationId(start)
        Thread.sleep(500)

        listenResults()
        val replayed = awaitResult(operationId)
        assertEquals(true, replayed["ok"])
        assertEquals(data, replayed["data"])
    }

    @Test
    fun teardownRemovesChannelHandlersAndFailsClosed() {
        plugin.registerService("store", ReturningService(mapOf("ok" to true)))
        plugin.onDetachedFromEngine(binding)

        assertFalse(messenger.hasHandler(FeldexaChannels.PLATFORM))
        assertFalse(messenger.hasHandler(FeldexaChannels.RESULTS))
        assertFalse(messenger.hasHandler(FeldexaChannels.EVENTS))
    }

    // ---- helpers ------------------------------------------------------------

    private fun registerAllServices() {
        PlatformServiceRegistry.METHOD_PREFIXES.forEach { prefix ->
            plugin.registerService(prefix, ReturningService(mapOf("ok" to true)))
        }
    }

    private fun withSchema(payload: Map<String, Any?>): Map<String, Any?> =
        mapOf("schemaVersion" to 1) + payload

    private fun ocrPayload(): Map<String, Any?> = mapOf(
        "schemaVersion" to 1,
        "pageIndex" to 0,
        "imageWidth" to 100,
        "imageHeight" to 100,
        "pageWidthPt" to 100.0,
        "pageHeightPt" to 100.0,
        "format" to "gray8",
        "bytes" to ByteArray(10_000),
        "language" to "de",
    )

    private fun minimalPayloads(): Map<String, Map<String, Any?>> = linkedMapOf(
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
        "ocr.recognize" to ocrPayload().minus("schemaVersion"),
        "export.validate" to mapOf("plan" to mapOf("value" to "x")),
        "export.render" to mapOf("plan" to mapOf("value" to "x")),
        "export.readArtifact" to mapOf("artifactId" to artifactId),
        "export.deleteArtifact" to mapOf("artifactId" to artifactId),
        "delivery.save" to mapOf("artifactId" to artifactId, "suggestedName" to "Antrag.pdf"),
        "delivery.share" to mapOf("artifactId" to artifactId, "mimeType" to "application/pdf"),
        "delivery.print" to mapOf("artifactId" to artifactId, "jobName" to "Feldexa Dokument"),
        "cancel.operation" to mapOf("operationId" to operationId),
    )

    private fun invoke(method: String, payload: Map<String, Any?>): Map<*, *> {
        val reply = dispatch(method, payload)
        val decoded = codec.decodeEnvelope(reply)
        return decoded as Map<*, *>
    }

    private fun invokeFailure(method: String, payload: Map<String, Any?>): FlutterException {
        val reply = dispatch(method, payload)
        try {
            codec.decodeEnvelope(reply)
        } catch (failure: FlutterException) {
            return failure
        }
        fail("expected FlutterException for $method")
        throw AssertionError("unreachable")
    }

    private fun dispatch(method: String, payload: Map<String, Any?>): ByteBuffer {
        val handler = messenger.handler(FeldexaChannels.PLATFORM)
        val encoded = codec.encodeMethodCall(MethodCall(method, payload)).also { it.rewind() }
        val latch = CountDownLatch(1)
        var reply: ByteBuffer? = null
        instrumentation.runOnMainSync {
            handler.onMessage(
                encoded,
                BinaryMessenger.BinaryReply { buffer ->
                    reply = buffer
                    latch.countDown()
                },
            )
        }
        assertTrue("no MethodChannel reply for $method", latch.await(10, TimeUnit.SECONDS))
        return reply!!.also { it.rewind() }
    }

    private fun listenResults() {
        val handler = messenger.handler(FeldexaChannels.RESULTS)
        val encoded = codec.encodeMethodCall(MethodCall("listen", null)).also { it.rewind() }
        instrumentation.runOnMainSync {
            handler.onMessage(encoded, BinaryMessenger.BinaryReply { })
        }
    }

    private fun startOperationId(start: Map<*, *>): String {
        assertEquals(true, start["ok"])
        val data = start["data"] as Map<*, *>
        val operationId = data["operationId"] as String
        assertTrue(operationId.isNotEmpty())
        return operationId
    }

    private fun awaitResult(operationId: String): Map<*, *> {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
        while (System.nanoTime() < deadline) {
            val result = results().lastOrNull { it["operationId"] == operationId }
            if (result != null) return result
            Thread.sleep(20)
        }
        fail("no terminal result for $operationId")
        throw AssertionError("unreachable")
    }

    private fun assertNoMoreResults(operationId: String) {
        Thread.sleep(300)
        assertEquals(1, results().count { it["operationId"] == operationId })
    }

    private fun assertNoResults() {
        Thread.sleep(300)
        assertTrue("unexpected result event: ${results()}", results().isEmpty())
    }

    private fun results(): List<Map<*, *>> =
        messenger.events(FeldexaChannels.RESULTS).mapNotNull { it as? Map<*, *> }

    private class ReturningService(private val data: Any?) : PlatformService {
        override fun handle(request: PlatformRequest, context: OperationContext): Any? = data
    }

    private class ThrowingService(private val error: Throwable) : PlatformService {
        override fun handle(request: PlatformRequest, context: OperationContext): Any? = throw error
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

    private class RecordingMessenger : BinaryMessenger {
        private val lock = Any()
        private val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler>()
        private val sent = mutableListOf<Pair<String, ByteBuffer>>()

        fun handler(channel: String): BinaryMessenger.BinaryMessageHandler =
            synchronized(lock) { handlers[channel] ?: error("no handler for $channel") }

        fun hasHandler(channel: String): Boolean = synchronized(lock) { handlers[channel] != null }

        fun events(channel: String): List<Any?> = synchronized(lock) {
            sent.filter { it.first == channel }
                .map { CODEC.decodeEnvelope(it.second.duplicate()) }
        }

        override fun send(channel: String, message: ByteBuffer?) {
            if (message != null) record(channel, message)
        }

        override fun send(
            channel: String,
            message: ByteBuffer?,
            callback: BinaryMessenger.BinaryReply?,
        ) {
            if (message != null) record(channel, message)
        }

        override fun setMessageHandler(
            channel: String,
            handler: BinaryMessenger.BinaryMessageHandler?,
        ) {
            synchronized(lock) {
                if (handler == null) handlers.remove(channel) else handlers[channel] = handler
            }
        }

        private fun record(channel: String, message: ByteBuffer) {
            val copy = message.duplicate()
            copy.rewind()
            synchronized(lock) { sent += channel to copy }
        }
    }

    private object NoPlatformViews : PlatformViewRegistry {
        override fun registerViewFactory(factoryId: String, factory: PlatformViewFactory): Boolean =
            false
    }

    private object NoAssets : FlutterPlugin.FlutterAssets {
        override fun getAssetFilePathByName(assetName: String): String = assetName
        override fun getAssetFilePathByName(assetName: String, packageName: String): String = assetName
        override fun getAssetFilePathBySubpath(subpath: String): String = subpath
        override fun getAssetFilePathBySubpath(subpath: String, packageName: String): String = subpath
    }

    private companion object {
        val ASYNC_METHODS = setOf(
            "import.pickAndImport",
            "import.verifySource",
            "store.saveRevision",
            "store.writeSignature",
            "store.createTemplate",
            "store.saveTemplateVersion",
            "ocr.recognize",
            "export.validate",
            "export.render",
        )

        val CODEC = StandardMethodCodec.INSTANCE

        /**
         * Every top-level UUID-bearing field declared by
         * `contracts/platform-channel.md` §3-§7, grouped by method. Optional
         * nullable ids are listed here because [minimalPayloads] keeps them
         * null; the test guards this inventory against that table.
         */
        val UUID_FIELDS: Map<String, List<String>> = linkedMapOf(
            "import.verifySource" to listOf("sourceId"),
            "store.readSource" to listOf("documentId"),
            "store.readSignature" to listOf("documentId", "assetId"),
            "store.writeSignature" to listOf("documentId", "assetId"),
            "store.saveRevision" to listOf("documentId", "expectedHead"),
            "store.saveTemplateVersion" to listOf("templateId", "expectedHead"),
            "store.loadDocument" to listOf("documentId"),
            "store.loadTemplate" to listOf("templateId", "versionId"),
            "store.delete" to listOf("id"),
            "store.recoveryStamp" to listOf("id"),
            "export.readArtifact" to listOf("artifactId"),
            "export.deleteArtifact" to listOf("artifactId"),
            "delivery.save" to listOf("artifactId"),
            "delivery.share" to listOf("artifactId"),
            "delivery.print" to listOf("artifactId"),
            "cancel.operation" to listOf("operationId"),
        )

        val OPTIONAL_UUID_FIELDS: Set<Pair<String, String>> = setOf(
            "store.saveRevision" to "expectedHead",
            "store.saveTemplateVersion" to "expectedHead",
            "store.loadTemplate" to "versionId",
        )

        val UUID_PATTERN = Regex(
            "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}" +
                "-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$",
        )

        /** Malformed ids that the strict UUID regex in §10 must reject. */
        val INVALID_UUIDS = listOf(
            "invalid-uuid",
            "",
            "123e4567-e89b-42d3-a456-42661417400",
            "123e4567e89b42d3a456426614174000",
            "123e4567-e89b-02d3-a456-426614174000",
            "123e4567-e89b-42d3-7456-426614174000",
        )
    }
}
