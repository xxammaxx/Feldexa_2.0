package de.feldexa.app.export

import de.feldexa.app.PlatformFailure
import java.io.File
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * T104 host-JVM tests for the session artifact store and its naming hygiene
 * (`contracts/platform-channel.md` §6, §9, §11 point 8).
 *
 * Evidence class `NONE`: a temporary directory, no Android runtime.
 */
class ExportArtifactStoreTest {

    @Rule
    @JvmField
    val temporary = TemporaryFolder()

    private val artifactId = "1b4e28ba-2fa1-4d3b-a1f8-6f2a3c4d5e6f"

    @Test
    fun artifactPathsStayInsideTheArtifactDirectory() {
        val store = store()
        store.ensureDirectory()
        val file = store.artifactFile(artifactId)
        assertEquals(temporary.root.resolve(ExportArtifactStore.DIRECTORY_NAME), file.parentFile)
        assertEquals("$artifactId.pdf", file.name)
        assertEquals("$artifactId.pdf.tmp", store.temporaryFile(artifactId).name)
    }

    @Test
    fun identifierThatIsNotAUuidIsRejectedInsteadOfBecomingAPath() {
        val store = store()
        for (candidate in listOf("../escape", "a/b", "..", "$artifactId/../x", "")) {
            val failure = assertThrows(PlatformFailure::class.java) { store.artifactFile(candidate) }
            assertEquals("PLT-002", failure.code)
        }
    }

    @Test
    fun publishReadDeleteRoundTrip() {
        val store = store()
        store.ensureDirectory()
        val bytes = "%PDF-1.7 synthetisch".toByteArray()
        val file = store.artifactFile(artifactId)
        file.writeBytes(bytes)
        store.publish(record(file, bytes.size.toLong()))

        assertArrayEquals(bytes, store.read(artifactId))
        assertEquals(bytes.size.toLong(), store.record(artifactId)?.byteSize)
        assertTrue(store.delete(artifactId))
        assertFalse(file.exists())
        assertNull(store.record(artifactId))
    }

    @Test
    fun unknownArtifactIsExp002() {
        val store = store()
        val failure = assertThrows(PlatformFailure::class.java) { store.read(artifactId) }
        assertEquals("EXP-002", failure.code)
        assertFalse(store.delete(artifactId))
    }

    @Test
    fun truncatedFileIsRejectedInsteadOfPreviewed() {
        val store = store()
        store.ensureDirectory()
        val file = store.artifactFile(artifactId)
        file.writeBytes("%PDF-1.7 partial".toByteArray())
        store.publish(record(file, byteSize = 4096))
        assertThrows(PlatformFailure::class.java) { store.read(artifactId) }
    }

    @Test
    fun detachDeletesOnlyThisSessionsArtifacts() {
        val store = store()
        store.ensureDirectory()
        val bytes = "%PDF-1.7 synthetisch".toByteArray()
        val file = store.artifactFile(artifactId)
        file.writeBytes(bytes)
        store.publish(record(file, bytes.size.toLong()))
        // A file the service never published must never be deleted.
        val foreign = File(temporary.root.resolve(ExportArtifactStore.DIRECTORY_NAME), "author-note.txt")
        foreign.writeText("bleibt")

        store.deleteAll()

        assertFalse(file.exists())
        assertNull(store.record(artifactId))
        assertTrue(foreign.exists())
    }

    private fun store(): ExportArtifactStore =
        ExportArtifactStore(File(temporary.root, ExportArtifactStore.DIRECTORY_NAME).absoluteFile)

    private fun record(file: File, byteSize: Long) = ExportArtifactStore.ArtifactRecord(
        artifactId = artifactId,
        file = file,
        byteSize = byteSize,
        sha256 = "0".repeat(64),
        pageCount = 1,
    )
}
