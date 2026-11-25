package de.feldexa.app.delivery

import android.net.Uri
import de.feldexa.app.OperationContext
import de.feldexa.app.OperationHandle
import de.feldexa.app.PlatformEventPublisher
import de.feldexa.app.PlatformFailure
import de.feldexa.app.PlatformRequest
import de.feldexa.app.ThreadPoster
import de.feldexa.app.export.ExportArtifactStore
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * T107 review correction (PR #337): `delivery.print` must hand the verified
 * page count of the artifact record to the print host.
 *
 * `contracts/platform-channel.md` §11 forbids PDF parsing on the UI thread, and
 * `onLayout` runs there, so the adapter must not reopen the document to learn
 * its page count. These are host-JVM tests of the wiring; the framework
 * adapter itself needs an Android runtime, so it has **no** automated coverage
 * today — T110 (`integration_test/print_test.dart`) is the test that will cover
 * it, and it is still open.
 */
class DeliveryServicePrintTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun printHandsTheRecordedPageCountToTheHost() {
        val artifacts = store()
        val artifact = publishArtifact(artifacts, pageCount = 7)
        val host = RecordingDeliveryHost()

        val reply = DeliveryService(artifacts, host)
            .handle(printRequest(artifact.artifactId), context())

        assertEquals(true, (reply as Map<*, *>)["completed"])
        assertEquals(7, host.printedPageCount)
        assertEquals(artifact.file, host.printedFile)
    }

    @Test
    fun printReportsUnavailableWhenNoPrintServiceAnswers() {
        val artifacts = store()
        val artifact = publishArtifact(artifacts, pageCount = 1)
        val host = RecordingDeliveryHost(started = false)

        val failure = assertThrows(PlatformFailure::class.java) {
            DeliveryService(artifacts, host).handle(printRequest(artifact.artifactId), context())
        }

        assertEquals("PLT-001", failure.code)
        assertEquals("deliveryUnavailable", failure.details()["category"])
    }

    @Test
    fun printRejectsAnArtifactWhoseFileNoLongerMatchesTheRecord() {
        val artifacts = store()
        val artifact = publishArtifact(artifacts, pageCount = 2)
        artifact.file.writeBytes(ByteArray(1))
        val host = RecordingDeliveryHost()

        val failure = assertThrows(PlatformFailure::class.java) {
            DeliveryService(artifacts, host).handle(printRequest(artifact.artifactId), context())
        }

        assertEquals("EXP-002", failure.code)
        assertNull(host.printedPageCount)
    }

    // ---- helpers ------------------------------------------------------------

    private fun store(): ExportArtifactStore =
        ExportArtifactStore(temporaryFolder.newFolder()).also { it.ensureDirectory() }

    private fun publishArtifact(
        artifacts: ExportArtifactStore,
        pageCount: Int,
    ): ExportArtifactStore.ArtifactRecord {
        val file = artifacts.artifactFile(UUID.randomUUID().toString())
        file.writeBytes(ByteArray(16))
        val record = ExportArtifactStore.ArtifactRecord(
            artifactId = file.nameWithoutExtension,
            file = file,
            byteSize = file.length(),
            sha256 = "0".repeat(64),
            pageCount = pageCount,
        )
        artifacts.publish(record)
        return record
    }

    private fun printRequest(artifactId: String) = PlatformRequest(
        "delivery.print",
        mapOf("artifactId" to artifactId, "jobName" to "Antrag"),
    )

    private fun context(): OperationContext {
        val id = UUID.randomUUID().toString()
        return OperationContext(id, OperationHandle(id), PlatformEventPublisher(DirectPoster))
    }

    private object DirectPoster : ThreadPoster {
        override fun post(block: () -> Unit) = block()
    }

    private class RecordingDeliveryHost(private val started: Boolean = true) : DeliveryHost {
        var printedFile: File? = null
        var printedPageCount: Int? = null

        override fun pickSaveLocation(suggestedName: String, onResult: (Uri?) -> Unit) {
            throw UnsupportedOperationException("not used by delivery.print")
        }

        override fun openOutputStream(uri: Uri): OutputStream {
            throw UnsupportedOperationException("not used by delivery.print")
        }

        override fun openInputStream(uri: Uri): InputStream {
            throw UnsupportedOperationException("not used by delivery.print")
        }

        override fun shareArtifact(file: File, mimeType: String) {
            throw UnsupportedOperationException("not used by delivery.print")
        }

        override fun printArtifact(file: File, jobName: String, pageCount: Int): Boolean {
            printedFile = file
            printedPageCount = pageCount
            return started
        }
    }
}
