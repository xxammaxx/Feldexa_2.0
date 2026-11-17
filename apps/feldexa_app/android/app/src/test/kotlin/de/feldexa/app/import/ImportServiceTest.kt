package de.feldexa.app.import

import de.feldexa.app.BackgroundExecutor
import de.feldexa.app.ChannelReply
import de.feldexa.app.FeldexaEventSink
import de.feldexa.app.OperationContext
import de.feldexa.app.OperationHandle
import de.feldexa.app.PlatformChannelFacade
import de.feldexa.app.PlatformEventPublisher
import de.feldexa.app.PlatformFailure
import de.feldexa.app.PlatformRequest
import de.feldexa.app.PlatformResultPublisher
import de.feldexa.app.PlatformService
import de.feldexa.app.PlatformServiceRegistry
import de.feldexa.app.ThreadPoster
import de.feldexa.app.storage.StagedSourceReceipt
import de.feldexa.app.storage.StorageFullException
import de.feldexa.app.storage.StorageWriteException
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * T038 host-JVM tests for the SAF streaming import core.
 *
 * The picker, staging and discard seams are fakes: no Activity, no Android
 * framework, no real document content. Evidence class: HOST-JVM.
 */
class ImportServiceTest {

    private val bytes = "synthetic-pdf-bytes".toByteArray()
    private val expectedSha = sha256(bytes)

    @Test
    fun happyPathStagesExactBytesAndReturnsContractFields() {
        val staging = RecordingStaging()
        val discard = RecordingDiscard()
        val service = ImportService(
            picker = FakePicker(FakePickedDocument(bytes, "antrag.pdf")),
            staging = staging,
            discard = discard,
        )
        val (_, context) = context()

        @Suppress("UNCHECKED_CAST")
        val data = service.handle(pickRequest(1_000L), context) as Map<String, Any?>

        assertEquals(1, staging.calls)
        assertArrayEquals(bytes, staging.bytes)
        assertEquals(expectedSha, staging.sha)
        assertEquals(staging.documentId, data["documentId"])
        assertEquals(staging.sourceId, data["sourceId"])
        assertEquals(expectedSha, data["sha256"])
        assertEquals(bytes.size.toLong(), data["sizeBytes"])
        assertEquals("antrag.pdf", data["displayName"])
        assertTrue(discard.ids.isEmpty())
    }

    @Test
    fun streamIsReadInBoundedChunksAndAllBytesAreStaged() {
        val staging = RecordingStaging()
        val service = ImportService(
            picker = FakePicker(ChunkedPickedDocument(bytes, maxChunk = 3, "scan.pdf")),
            staging = staging,
        )
        val (_, context) = context()

        service.handle(pickRequest(1_000L), context)

        assertEquals(1, staging.calls)
        assertArrayEquals(bytes, staging.bytes)
        assertEquals(expectedSha, staging.sha)
    }

    @Test
    fun exceedingMaxBytesRejectsIMP007AndStagesNothing() {
        val staging = RecordingStaging()
        val service = ImportService(
            picker = FakePicker(FakePickedDocument(bytes, "geheim.pdf")),
            staging = staging,
        )
        val (_, context) = context()

        val failure = expectFailure { service.handle(pickRequest(4L), context) }

        assertEquals("IMP-007", failure.code)
        assertEquals("tooLarge", failure.category)
        assertEquals("import.tooLarge", failure.machineMessage)
        assertFalse(failure.retryable)
        assertEquals(0, staging.calls)
        // No content in the failure: neither the title nor any byte text leaks.
        assertFalse(failure.machineMessage.contains("geheim"))
        assertFalse(failure.details().values.any { it is String && it.contains("geheim") })
    }

    @Test
    fun missingStreamRejectsIMP003WithoutContent() {
        val staging = RecordingStaging()
        val service = ImportService(
            picker = FakePicker(FakePickedDocument(bytes, "scan.pdf", nullStream = true)),
            staging = staging,
        )
        val (_, context) = context()

        val failure = expectFailure { service.handle(pickRequest(1_000L), context) }

        assertEquals("IMP-003", failure.code)
        assertEquals("missing", failure.category)
        assertEquals(0, staging.calls)
    }

    @Test
    fun userCancellingThePickerCreatesNoStage() {
        val staging = RecordingStaging()
        val service = ImportService(picker = FakePicker(null), staging = staging)
        val (_, context) = context()

        val failure = expectFailure { service.handle(pickRequest(1_000L), context) }

        assertEquals("PLT-004", failure.code)
        assertEquals(0, staging.calls)
    }

    @Test
    fun cancellationDuringStreamLeavesNoStage() {
        val (handle, context) = context()
        val staging = RecordingStaging()
        val service = ImportService(
            picker = FakePicker(FakePickedDocument(
                bytes,
                "scan.pdf",
                stream = CancellingInputStream(handle, bytes),
            )),
            staging = staging,
        )

        val failure = expectFailure { service.handle(pickRequest(1_000L), context) }

        assertEquals("PLT-004", failure.code)
        assertEquals(0, staging.calls)
    }

    @Test
    fun cancellationAfterStageDiscardsTheIncompleteAggregate() {
        val (handle, context) = context()
        val staging = RecordingStaging().apply { onStage = { handle.cancel() } }
        val discard = RecordingDiscard()
        val service = ImportService(
            picker = FakePicker(FakePickedDocument(bytes, "scan.pdf")),
            staging = staging,
            discard = discard,
        )

        val failure = expectFailure { service.handle(pickRequest(1_000L), context) }

        assertEquals("PLT-004", failure.code)
        assertEquals(1, staging.calls)
        assertEquals(listOf(staging.documentId), discard.ids)
    }

    @Test
    fun cancellationDuringPickerWaitAbortsPromptlyWithoutStaging() {
        val staging = RecordingStaging()
        val pickerEntered = CountDownLatch(1)
        val service = ImportService(
            // The picker never calls back: only cancellation can end the wait.
            picker = DocumentPicker { pickerEntered.countDown() },
            staging = staging,
            pickerTimeoutMs = TEST_PICKER_TIMEOUT_MS,
        )
        val (handle, context) = context()
        val canceller = Thread {
            if (pickerEntered.await(5, TimeUnit.SECONDS)) {
                Thread.sleep(50L)
                handle.cancel()
            }
        }
        canceller.start()

        val startedAt = System.nanoTime()
        val failure = expectFailure { service.handle(pickRequest(1_000L), context) }
        val elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt)
        canceller.join(5_000L)

        assertEquals("PLT-004", failure.code)
        assertEquals(0, staging.calls)
        assertTrue(
            "picker wait took ${elapsedMs}ms; cancellation must not wait out ${TEST_PICKER_TIMEOUT_MS}ms",
            elapsedMs < TEST_PICKER_TIMEOUT_MS / 2,
        )
    }

    @Test
    fun cancelAfterStageDiscardsBeforePlt004Surfaces() {
        val (handle, context) = context()
        val discardEntered = CountDownLatch(1)
        val releaseDiscard = CountDownLatch(1)
        val discard = RecordingDiscard().apply {
            onDiscard = {
                discardEntered.countDown()
                releaseDiscard.await(5, TimeUnit.SECONDS)
            }
        }
        val staging = RecordingStaging().apply { onStage = { handle.cancel() } }
        val service = ImportService(
            picker = FakePicker(FakePickedDocument(bytes, "scan.pdf")),
            staging = staging,
            discard = discard,
        )
        val failure = AtomicReference<PlatformFailure?>()
        val done = CountDownLatch(1)
        val worker = Thread {
            try {
                service.handle(pickRequest(1_000L), context)
            } catch (thrown: PlatformFailure) {
                failure.set(thrown)
            } finally {
                done.countDown()
            }
        }
        worker.start()

        assertTrue(discardEntered.await(5, TimeUnit.SECONDS))
        assertFalse(
            "PLT-004 surfaced before the staged aggregate was discarded",
            done.await(150, TimeUnit.MILLISECONDS),
        )

        releaseDiscard.countDown()
        assertTrue(done.await(5, TimeUnit.SECONDS))
        worker.join(5_000L)

        assertEquals("PLT-004", failure.get()?.code)
        assertEquals(listOf(staging.documentId), discard.ids)
    }

    @Test
    fun cancelArrivingAfterServiceReturnDiscardsBeforeCancellationIsObservable() {
        val staging = RecordingStaging()
        val discard = RecordingDiscard()
        val service = ImportService(
            picker = FakePicker(FakePickedDocument(bytes, "scan.pdf")),
            staging = staging,
            discard = discard,
        )
        val (handle, context) = context()

        @Suppress("UNCHECKED_CAST")
        val data = service.handle(pickRequest(1_000L), context) as Map<String, Any?>
        val documentId = data["documentId"] as String
        assertTrue(discard.ids.isEmpty())
        assertFalse(handle.isCancelled)

        // The facade's post-handle window: the service has returned, then a
        // cancel arrives before the facade evaluates handle.isCancelled.
        assertTrue(handle.cancel())

        // Cleanup completed inside the cancellation linearization, so no
        // PLT-004 publication can observe a retained staged aggregate.
        assertEquals(listOf(documentId), discard.ids)
        assertTrue(handle.isCancelled)
        assertNull(handle.cancelActionFailure())

        // Exactly once: a second cancel is a no-op.
        assertFalse(handle.cancel())
        assertEquals(1, discard.ids.size)
    }

    @Test
    fun failingDiscardIsNotReportedAsCleanCancellation() {
        val (handle, context) = context()
        val staging = RecordingStaging().apply { onStage = { handle.cancel() } }
        val discard = RecordingDiscard().apply { throwable = StorageWriteException() }
        val service = ImportService(
            picker = FakePicker(FakePickedDocument(bytes, "scan.pdf")),
            staging = staging,
            discard = discard,
        )

        val failure = expectFailure { service.handle(pickRequest(1_000L), context) }

        assertEquals(1, discard.ids.size)
        assertNotEquals("PLT-004", failure.code)
        assertEquals("SAVE-003", failure.code)
        assertEquals("SAVE-003", context.cancellationCleanupFailure()?.code)
    }

    @Test
    fun storageFullMapsToSAVE001WithoutContent() {
        val staging = RecordingStaging().apply { throwable = StorageFullException() }
        val service = ImportService(
            picker = FakePicker(FakePickedDocument(bytes, "scan.pdf")),
            staging = staging,
        )
        val (_, context) = context()

        val failure = expectFailure { service.handle(pickRequest(1_000L), context) }

        assertEquals("SAVE-001", failure.code)
        assertEquals("storageFull", failure.category)
        assertEquals("save.storageFull", failure.machineMessage)
        assertTrue(failure.retryable)
    }

    @Test
    fun readFailureMapsToIMP002() {
        val service = ImportService(
            picker = FakePicker(FakePickedDocument(
                bytes,
                "scan.pdf",
                stream = FailingInputStream(),
            )),
            staging = RecordingStaging(),
        )
        val (_, context) = context()

        val failure = expectFailure { service.handle(pickRequest(1_000L), context) }

        assertEquals("IMP-002", failure.code)
        assertEquals("unreadable", failure.category)
    }

    @Test
    fun notYetOwnedMethodsFailClosed() {
        val staging = RecordingStaging()
        val picker = FakePicker(FakePickedDocument(bytes, "scan.pdf"))
        val service = ImportService(picker = picker, staging = staging)
        val (_, context) = context()

        val verify = expectFailure {
            service.handle(
                PlatformRequest(
                    "import.verifySource",
                    mapOf("schemaVersion" to 1, "sourceId" to UUID.randomUUID().toString()),
                ),
                context,
            )
        }
        val discard = expectFailure {
            service.handle(
                PlatformRequest(
                    "import.discardStaged",
                    mapOf("schemaVersion" to 1, "txnId" to "txn-1"),
                ),
                context,
            )
        }

        assertEquals("PLT-001", verify.code)
        assertEquals("PLT-001", discard.code)
        assertEquals(0, staging.calls)
        assertEquals(0, picker.calls)
    }

    @Test
    fun facadePublishesStartReplyAndExactlyOneTerminalResult() {
        val staging = RecordingStaging()
        val service = ImportService(
            picker = FakePicker(FakePickedDocument(bytes, "scan.pdf")),
            staging = staging,
        )
        val services = PlatformServiceRegistry().apply { register("import", service) }
        val reply = RecordingReply()
        val sink = RecordingSink()
        val results = PlatformResultPublisher(DirectPoster)
        results.attachSink(sink)
        val facade = PlatformChannelFacade(
            services = services,
            mainPoster = DirectPoster,
            events = PlatformEventPublisher(DirectPoster),
            results = results,
            executor = DirectExecutor,
            clock = { 0L },
        )

        facade.handle(
            "import.pickAndImport",
            mapOf("schemaVersion" to 1, "maxBytes" to 1_000L),
            reply,
        )

        assertNull(reply.failure)
        @Suppress("UNCHECKED_CAST")
        val start = reply.successValue as Map<String, Any?>
        @Suppress("UNCHECKED_CAST")
        val startData = start["data"] as Map<String, Any?>
        val operationId = startData["operationId"] as String
        assertTrue(operationId.isNotEmpty())
        assertEquals(setOf("operationId"), startData.keys)

        val terminal = sink.events.filterIsInstance<Map<*, *>>().filter {
            it["event"] == "operation.result" && it["operationId"] == operationId
        }
        assertEquals(1, terminal.size)
        val result = terminal.single()
        assertEquals(true, result["ok"])
        @Suppress("UNCHECKED_CAST")
        val data = result["data"] as Map<String, Any?>
        assertEquals(expectedSha, data["sha256"])
        assertEquals(bytes.size.toLong(), data["sizeBytes"])
        assertEquals("scan.pdf", data["displayName"])
    }

    @Test
    fun facadeReportsDiscardFailureInsteadOfCleanCancellation() {
        val stagingEntered = CountDownLatch(1)
        val releaseStaging = CountDownLatch(1)
        val staging = RecordingStaging().apply {
            onStage = {
                stagingEntered.countDown()
                releaseStaging.await(5, TimeUnit.SECONDS)
            }
        }
        val discard = RecordingDiscard().apply { throwable = StorageWriteException() }
        val service = ImportService(
            picker = FakePicker(FakePickedDocument(bytes, "scan.pdf")),
            staging = staging,
            discard = discard,
        )
        val services = PlatformServiceRegistry().apply { register("import", service) }
        val reply = RecordingReply()
        val sink = RecordingSink()
        val results = PlatformResultPublisher(DirectPoster)
        results.attachSink(sink)
        val executor = QueueExecutor()
        val facade = PlatformChannelFacade(
            services = services,
            mainPoster = DirectPoster,
            events = PlatformEventPublisher(DirectPoster),
            results = results,
            executor = executor,
            clock = { 0L },
        )

        facade.handle(
            "import.pickAndImport",
            mapOf("schemaVersion" to 1, "maxBytes" to 1_000L),
            reply,
        )
        @Suppress("UNCHECKED_CAST")
        val start = reply.successValue as Map<String, Any?>
        @Suppress("UNCHECKED_CAST")
        val operationId = (start["data"] as Map<String, Any?>)["operationId"] as String

        val worker = Thread { executor.runNext() }
        worker.start()
        assertTrue(stagingEntered.await(5, TimeUnit.SECONDS))

        val cancelReply = RecordingReply()
        facade.handle(
            "cancel.operation",
            mapOf("schemaVersion" to 1, "operationId" to operationId),
            cancelReply,
        )
        assertEquals(mapOf("cancelled" to true), (cancelReply.successValue as Map<*, *>)["data"])
        releaseStaging.countDown()
        worker.join(5_000L)
        assertFalse(worker.isAlive)

        assertEquals(1, discard.ids.size)
        val terminal = sink.events.filterIsInstance<Map<*, *>>().filter {
            it["event"] == "operation.result" && it["operationId"] == operationId
        }
        assertEquals(1, terminal.size)
        val result = terminal.single()
        assertEquals(false, result["ok"])
        val error = result["error"] as Map<*, *>
        assertEquals("SAVE-003", error["code"])
        assertNotEquals("PLT-004", error["code"])
    }

    // ---- helpers ------------------------------------------------------------

    private fun context(): Pair<OperationHandle, OperationContext> {
        val id = UUID.randomUUID().toString()
        val handle = OperationHandle(id)
        return handle to OperationContext(id, handle, PlatformEventPublisher(DirectPoster))
    }

    private fun pickRequest(maxBytes: Long) = PlatformRequest(
        "import.pickAndImport",
        mapOf("schemaVersion" to 1, "maxBytes" to maxBytes),
    )

    private fun expectFailure(block: () -> Unit): PlatformFailure {
        try {
            block()
        } catch (failure: PlatformFailure) {
            return failure
        }
        fail("expected a PlatformFailure")
        throw AssertionError("unreachable")
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") {
            "%02x".format(it.toInt() and 0xFF)
        }

    private companion object {
        /** Long enough that a cancellation-blind wait would be obvious. */
        const val TEST_PICKER_TIMEOUT_MS: Long = 5_000L
    }

    private class FakePicker(private val document: PickedDocument?) : DocumentPicker {
        var calls = 0
        override fun pick(onResult: (PickedDocument?) -> Unit) {
            calls++
            onResult(document)
        }
    }

    private class FakePickedDocument(
        private val content: ByteArray,
        override val displayName: String? = "scan.pdf",
        private val stream: InputStream? = null,
        private val nullStream: Boolean = false,
    ) : PickedDocument {
        override fun openStream(): InputStream? =
            if (nullStream) null else stream ?: ByteArrayInputStream(content)
    }

    /** Forces many short reads so the service's bounded chunk loop is exercised. */
    private class ChunkedPickedDocument(
        private val content: ByteArray,
        private val maxChunk: Int,
        override val displayName: String? = "scan.pdf",
    ) : PickedDocument {
        override fun openStream(): InputStream = object : InputStream() {
            private var position = 0
            override fun read(): Int = if (position >= content.size) -1 else content[position++].toInt() and 0xFF
            override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                if (position >= content.size) return -1
                val count = minOf(maxChunk, length, content.size - position)
                System.arraycopy(content, position, buffer, offset, count)
                position += count
                return count
            }
        }
    }

    private class CancellingInputStream(
        private val handle: OperationHandle,
        @Suppress("UNUSED_PARAMETER") private val content: ByteArray,
    ) : InputStream() {
        private var cancelled = false
        override fun read(): Int = -1
        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            if (!cancelled) {
                cancelled = true
                handle.cancel()
            }
            return -1
        }
    }

    private class FailingInputStream : InputStream() {
        override fun read(): Int = throw IOException("synthetic read failure")
        override fun read(buffer: ByteArray, offset: Int, length: Int): Int =
            throw IOException("synthetic read failure")
    }

    private class RecordingStaging : SourceStaging {
        var calls = 0
        var documentId: String? = null
        var sourceId: String? = null
        var bytes: ByteArray? = null
        var sha: String? = null
        var throwable: Throwable? = null
        var onStage: (() -> Unit)? = null

        override fun stage(
            documentId: String,
            sourceId: String,
            bytes: ByteArray,
            expectedSha256: String?,
        ): StagedSourceReceipt {
            calls++
            this.documentId = documentId
            this.sourceId = sourceId
            this.bytes = bytes
            this.sha = expectedSha256
            onStage?.invoke()
            throwable?.let { throw it }
            return StagedSourceReceipt(
                aggregateId = documentId,
                sourceId = sourceId,
                sourceSha256 = expectedSha256!!,
                sizeBytes = bytes.size.toLong(),
                readBackVerified = true,
            )
        }
    }

    private class RecordingDiscard : StagedDiscard {
        val ids = mutableListOf<String>()
        var throwable: Throwable? = null
        var onDiscard: (() -> Unit)? = null

        override fun discard(documentId: String) {
            ids.add(documentId)
            onDiscard?.invoke()
            throwable?.let { throw it }
        }
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
            events.add(event)
        }
    }

    private object DirectPoster : ThreadPoster {
        override fun post(block: () -> Unit) = block()
    }

    private object DirectExecutor : BackgroundExecutor {
        override fun execute(task: () -> Unit) = task()
        override fun shutdown() = Unit
    }

    /** Defers queued facade work so a test can inject a cancel mid-operation. */
    private class QueueExecutor : BackgroundExecutor {
        private val tasks = LinkedBlockingQueue<() -> Unit>()

        override fun execute(task: () -> Unit) {
            tasks.add(task)
        }

        fun runNext() {
            tasks.take().invoke()
        }

        override fun shutdown() = Unit
    }
}
