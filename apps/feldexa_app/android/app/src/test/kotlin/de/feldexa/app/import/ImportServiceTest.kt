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
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
        override fun discard(documentId: String) {
            ids.add(documentId)
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
}
