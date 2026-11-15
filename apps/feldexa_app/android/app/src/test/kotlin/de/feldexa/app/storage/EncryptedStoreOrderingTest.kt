package de.feldexa.app.storage

import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * T026 security review: durable revision-order metadata.
 *
 * The store uses the revision/version mtime as the recovery order. A
 * parent-directory fsync after the atomic rename does not by itself prove that
 * the inode mtime changed by `setLastModified` is durable. The correct order is
 *
 *     setLastModified → fsync(file) → rename → fsync(parent directory)
 *
 * These tests record the actual call order and inject a failure at the
 * metadata fsync, proving that no revision is promoted when the ordering
 * metadata could not be flushed. They cannot simulate a physical power loss;
 * the durability claim is limited to that syscall order.
 */
class EncryptedStoreOrderingTest {

    @Rule
    @JvmField
    val temporary = TemporaryFolder()

    private lateinit var backend: TestStoreKeystoreBackend
    private lateinit var keystore: KeystoreService
    private lateinit var store: EncryptedStore
    private val now = AtomicLong(1_760_000_000_000L)
    private val storeRoot: File get() = File(temporary.root, "store")

    @Before
    fun setUp() {
        backend = TestStoreKeystoreBackend()
        keystore = KeystoreService(backend, sleeper = {})
        store = EncryptedStore(storeRoot, keystore, clock = { now.get() })
        store.ensureLayout()
    }

    @Test
    fun revisionOrderingMetadataIsFsyncedBeforePromoteAndParentFsync() {
        val recording = RecordingStoreIo()
        val recordingStore = EncryptedStore(
            root = storeRoot,
            keystore = keystore,
            io = recording,
            clock = { now.get() },
        )
        recordingStore.ensureLayout()
        val documentId = UUID.randomUUID().toString()
        val revisionId = fixedUuid(1)
        recordingStore.createDocument(
            documentId,
            meta("Ordering"),
            UUID.randomUUID().toString(),
            "%PDF-1.7 ordering".toByteArray(),
            revisionId,
            revision(1),
        )

        val revisionFile = File(storeRoot, "docs/$documentId/rev/$revisionId.fx1")
        val events = recording.events
        val metadataSet = events.indexOfFirst { it.kind == "mtime" }
        val metadataFsync = events.indexOfFirst { it.kind == "file-fsync" }
        val promote = events.indexOfFirst {
            it.kind == "move" && it.to == revisionFile
        }
        val parentFsync = events.indexOfFirst {
            it.kind == "dir-fsync" && it.file == revisionFile.parentFile
        }

        assertTrue("mtime must be set", metadataSet >= 0)
        assertTrue("mtime must precede the file fsync", metadataSet < metadataFsync)
        assertTrue(
            "file fsync must precede the rename",
            metadataFsync >= 0 && metadataFsync < promote,
        )
        assertTrue(
            "rename must precede the parent-directory fsync",
            promote >= 0 && promote < parentFsync,
        )
    }

    @Test
    fun orderingFsyncFailurePreventsPromoteAndKeepsOldHead() {
        val documentId = UUID.randomUUID().toString()
        val firstRevision = fixedUuid(1)
        val secondRevision = fixedUuid(2)
        store.createDocument(
            documentId,
            meta("Ordering"),
            UUID.randomUUID().toString(),
            "%PDF-1.7 ordering".toByteArray(),
            firstRevision,
            revision(1),
        )
        val faultStore = EncryptedStore(
            root = storeRoot,
            keystore = keystore,
            faultInjector = StoreFaultInjector { point, _ ->
                if (point == StoreFaultPoint.ORDERING_FSYNC) {
                    throw IOException("ordering metadata fsync failed")
                }
            },
            clock = { now.get() },
        )

        val failure = try {
            faultStore.saveRevision(
                documentId,
                secondRevision,
                revision(2),
                RevisionKindWire.AUTOSAVE,
                firstRevision,
            )
            null
        } catch (error: StorageException) {
            error
        }

        assertNotNull(failure)
        assertEquals("SAVE-003", failure!!.code)
        assertEquals(firstRevision, store.loadDocument(documentId).head.revisionId)
        assertFalse(File(storeRoot, "docs/$documentId/rev/$secondRevision.fx1").exists())
        assertTrue(File(storeRoot, "tmp").listFiles()!!.isEmpty())
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private fun fixedUuid(suffix: Int): String =
        "00000000-0000-4000-8000-%012d".format(suffix)

    private fun meta(title: String): ByteArray =
        ("{\"createdAt\":\"2026-11-15T00:00:00.000Z\",\"title\":\"$title\"}")
            .toByteArray()

    private fun revision(value: Int): ByteArray =
        ("{\"pageCount\":$value,\"schemaVersion\":1}").toByteArray()

    private data class IoEvent(
        val kind: String,
        val file: File,
        val to: File? = null,
    )

    private class RecordingStoreIo(
        private val delegate: StoreIo = RealStoreIo(),
    ) : StoreIo {

        val events: MutableList<IoEvent> = mutableListOf()

        override fun openExclusive(file: File) = delegate.openExclusive(file)

        override fun openRead(file: File) = delegate.openRead(file)

        override fun atomicMove(from: File, to: File) {
            events += IoEvent("move", from, to)
            delegate.atomicMove(from, to)
        }

        override fun fsyncDirectory(directory: File) {
            events += IoEvent("dir-fsync", directory)
            delegate.fsyncDirectory(directory)
        }

        override fun delete(file: File): Boolean = delegate.delete(file)

        override fun deleteTree(file: File): Boolean = delegate.deleteTree(file)

        override fun mkdirs(directory: File): Boolean = delegate.mkdirs(directory)

        override fun list(directory: File): List<File> = delegate.list(directory)

        override fun walkFiles(directory: File): List<File> =
            delegate.walkFiles(directory)

        override fun exists(file: File): Boolean = delegate.exists(file)

        override fun isDirectory(file: File): Boolean = delegate.isDirectory(file)

        override fun size(file: File): Long = delegate.size(file)

        override fun appendLine(file: File, line: ByteArray) =
            delegate.appendLine(file, line)

        override fun setLastModified(file: File, millis: Long): Boolean {
            events += IoEvent("mtime", file)
            return delegate.setLastModified(file, millis)
        }

        override fun fsyncFile(file: File) {
            events += IoEvent("file-fsync", file)
            delegate.fsyncFile(file)
        }
    }
}
