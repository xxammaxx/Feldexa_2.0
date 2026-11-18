package de.feldexa.app.storage

import java.io.ByteArrayInputStream
import java.io.File
import java.io.InputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CancellationException
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * T040 host-JVM tests for the true streaming staged-source path.
 *
 * These tests use the real `FXC1` container, real AES-GCM, a real temporary
 * filesystem, and the T025/T026 test Keystore backend. They prove the
 * structural streaming properties (bounded chunk sizes, two read passes, no
 * whole-source API, no plaintext file, decrypting seek reader) without making a
 * performance claim. No Android runtime is involved.
 */
class EncryptedStoreStreamingTest {

    @Rule
    @JvmField
    val temporary = TemporaryFolder()

    private lateinit var backend: TestStoreKeystoreBackend
    private lateinit var keystore: KeystoreService
    private lateinit var store: EncryptedStore

    @Before
    fun setUp() {
        backend = TestStoreKeystoreBackend()
        keystore = KeystoreService(backend, sleeper = {})
        store = EncryptedStore(
            root = File(temporary.root, "store").absoluteFile,
            keystore = keystore,
        )
        store.ensureLayout()
    }

    @Test
    fun stageSourceFromStreamUsesBoundedChunksAndWritesCiphertextOnly() {
        val source = sourceBytes(2 * 1_048_576 + 12_345)
        val documentId = newId()
        val sourceId = newId()
        val chunks = mutableListOf<Pair<SourceReadPass, Int>>()

        val receipt = store.stageSourceFromStream(
            documentId = documentId,
            sourceId = sourceId,
            countPass = ByteArrayInputStream(source),
            openStreamForWrite = { ByteArrayInputStream(source) },
            onChunk = { pass, count -> chunks += pass to count },
        )

        assertTrue(receipt.readBackVerified)
        assertEquals(sha256(source), receipt.sourceSha256)
        assertEquals(source.size.toLong(), receipt.sizeBytes)

        val hashChunks = chunks.filter { it.first == SourceReadPass.HASH }.map { it.second }
        val writeChunks = chunks.filter { it.first == SourceReadPass.WRITE }.map { it.second }
        assertTrue("hash pass must be multi-chunk: $hashChunks", hashChunks.size > 1)
        assertTrue(
            "hash pass exceeded the 64 KiB bound: $hashChunks",
            hashChunks.all { it <= EncryptedStore.SOURCE_HASH_CHUNK_SIZE },
        )
        assertTrue("write pass must be multi-chunk: $writeChunks", writeChunks.size > 1)
        assertTrue(
            "write pass exceeded the 1 MiB FXC1 chunk: $writeChunks",
            writeChunks.all { it <= EncryptedStore.LARGE_CHUNK_SIZE },
        )

        // Exactly one immutable encrypted source object exists; tmp/ is empty.
        val aggregate = File(File(store.root, "docs"), documentId)
        val sourceFile = File(File(aggregate, "src"), "$sourceId.fxc")
        assertTrue(sourceFile.isFile)
        assertTrue(File(store.root, "tmp").listFiles().orEmpty().isEmpty())
        assertEquals(1, File(aggregate, "src").listFiles().orEmpty().size)

        // No plaintext copy or scratch file exists in the store: the source
        // marker appears only inside the ciphertext-free test input.
        assertNoPlaintext(source, store.root)

        // Read back through the decrypting range reader, including a seek and a
        // read that crosses the 1 MiB chunk boundary.
        store.openSourceReader(documentId, sourceId).use { reader ->
            assertEquals(source.size.toLong(), reader.length)
            assertArrayEquals(source, readAll(reader))
            reader.seek(1_048_576L - 7)
            val crossing = ByteArray(32)
            assertEquals(32, reader.read(crossing, 0, crossing.size))
            assertArrayEquals(
                source.copyOfRange(1_048_576 - 7, 1_048_576 + 25),
                crossing,
            )
            reader.seek(source.size.toLong() - 3)
            val tail = ByteArray(10)
            assertEquals(3, reader.read(tail, 0, tail.size))
            assertEquals(-1, reader.read(tail, 0, tail.size))
        }
    }

    @Test
    fun secondPassMismatchFailsClosedAndRemovesTheAggregate() {
        val first = sourceBytes(1_200_000)
        val second = first.copyOf().also { it[100] = (it[100] + 1).toByte() }
        val documentId = newId()
        val sourceId = newId()

        val failure = assertThrows(InvalidDataException::class.java) {
            store.stageSourceFromStream(
                documentId = documentId,
                sourceId = sourceId,
                countPass = ByteArrayInputStream(first),
                openStreamForWrite = { ByteArrayInputStream(second) },
            )
        }

        assertEquals("SAVE-007", failure.code)
        assertNoAggregate(documentId)
        assertTrue(File(store.root, "tmp").listFiles().orEmpty().isEmpty())
    }

    @Test
    fun secondPassWithExtraBytesFailsClosedAndRemovesTheAggregate() {
        val source = sourceBytes(1_200_000)
        val longer = source + byteArrayOf(0x7F)
        val documentId = newId()

        assertThrows(InvalidDataException::class.java) {
            store.stageSourceFromStream(
                documentId = documentId,
                sourceId = newId(),
                countPass = ByteArrayInputStream(source),
                openStreamForWrite = { ByteArrayInputStream(longer) },
            )
        }

        assertNoAggregate(documentId)
    }

    @Test
    fun oversizeSourceIsRejectedDuringTheHashPassWithoutCreatingAnAggregate() {
        val source = sourceBytes(2_000)
        val documentId = newId()

        assertThrows(SourceLimitExceededException::class.java) {
            store.stageSourceFromStream(
                documentId = documentId,
                sourceId = newId(),
                countPass = ByteArrayInputStream(source),
                openStreamForWrite = { error("must not write an oversize source") },
                maxBytes = 1_000L,
            )
        }

        assertNoAggregate(documentId)
    }

    @Test
    fun abortDuringTheWritePassCleansUpAndNeverPublishesASource() {
        val source = sourceBytes(2_500_000)
        val documentId = newId()
        val writeOpened = java.util.concurrent.atomic.AtomicBoolean(false)

        assertThrows(CancellationException::class.java) {
            store.stageSourceFromStream(
                documentId = documentId,
                sourceId = newId(),
                countPass = ByteArrayInputStream(source),
                openStreamForWrite = {
                    writeOpened.set(true)
                    ByteArrayInputStream(source)
                },
                shouldAbort = { writeOpened.get() },
            )
        }

        assertNoAggregate(documentId)
        assertTrue(File(store.root, "tmp").listFiles().orEmpty().isEmpty())
    }

    @Test
    fun createDocumentFromStagedSourceVerifiesTheSourceAndCommitsOnce() {
        val source = sourceBytes(1_100_000)
        val documentId = newId()
        val sourceId = newId()
        val revisionId = newId()
        store.stageSourceFromStream(
            documentId = documentId,
            sourceId = sourceId,
            countPass = ByteArrayInputStream(source),
            openStreamForWrite = { ByteArrayInputStream(source) },
        )

        val receipt = store.createDocumentFromStagedSource(
            documentId = documentId,
            metaJson = "meta".toByteArray(),
            sourceId = sourceId,
            sourceSha256 = sha256(source),
            sourceSizeBytes = source.size.toLong(),
            revisionId = revisionId,
            revisionJson = "revision".toByteArray(),
        )

        assertTrue(receipt.readBackVerified)
        assertEquals(revisionId, receipt.revisionId)
        val loaded = store.loadDocument(documentId)
        assertArrayEquals(source, loaded.sourceBytes)
        assertEquals(1, store.list(AggregateKind.DOCUMENT).size)
        assertTrue(store.list(AggregateKind.DOCUMENT).single().readable)
    }

    @Test
    fun wrongHashRejectsTheCommitWithoutCreatingAVisibleDocument() {
        val source = sourceBytes(700_000)
        val documentId = newId()
        val sourceId = newId()
        store.stageSourceFromStream(
            documentId = documentId,
            sourceId = sourceId,
            countPass = ByteArrayInputStream(source),
            openStreamForWrite = { ByteArrayInputStream(source) },
        )

        assertThrows(CorruptDataException::class.java) {
            store.createDocumentFromStagedSource(
                documentId = documentId,
                metaJson = "meta".toByteArray(),
                sourceId = sourceId,
                sourceSha256 = "0".repeat(64),
                sourceSizeBytes = source.size.toLong(),
                revisionId = newId(),
                revisionJson = "revision".toByteArray(),
            )
        }

        assertNoAggregate(documentId)
        assertTrue(store.list(AggregateKind.DOCUMENT).isEmpty())
    }

    @Test
    fun abortBeforeMetaLeavesNoVisibleDocumentAndRemovesTheAggregate() {
        val source = sourceBytes(600_000)
        val documentId = newId()
        val sourceId = newId()
        store.stageSourceFromStream(
            documentId = documentId,
            sourceId = sourceId,
            countPass = ByteArrayInputStream(source),
            openStreamForWrite = { ByteArrayInputStream(source) },
        )

        assertThrows(CancellationException::class.java) {
            store.createDocumentFromStagedSource(
                documentId = documentId,
                metaJson = "meta".toByteArray(),
                sourceId = sourceId,
                sourceSha256 = sha256(source),
                sourceSizeBytes = source.size.toLong(),
                revisionId = newId(),
                revisionJson = "revision".toByteArray(),
                shouldAbort = { true },
            )
        }

        assertNoAggregate(documentId)
        assertTrue(store.list(AggregateKind.DOCUMENT).isEmpty())
    }

    @Test
    fun duplicateVisibleAggregateIsRejectedWithoutOverwritingAnyObject() {
        val source = sourceBytes(500_000)
        val documentId = newId()
        val sourceId = newId()
        store.stageSourceFromStream(
            documentId = documentId,
            sourceId = sourceId,
            countPass = ByteArrayInputStream(source),
            openStreamForWrite = { ByteArrayInputStream(source) },
        )
        store.createDocumentFromStagedSource(
            documentId = documentId,
            metaJson = "meta".toByteArray(),
            sourceId = sourceId,
            sourceSha256 = sha256(source),
            sourceSizeBytes = source.size.toLong(),
            revisionId = newId(),
            revisionJson = "revision".toByteArray(),
        )
        val before = store.loadDocument(documentId)

        assertThrows(ConcurrentSaveException::class.java) {
            store.createDocumentFromStagedSource(
                documentId = documentId,
                metaJson = "other".toByteArray(),
                sourceId = newId(),
                sourceSha256 = sha256(source),
                sourceSizeBytes = source.size.toLong(),
                revisionId = newId(),
                revisionJson = "other".toByteArray(),
            )
        }

        val after = store.loadDocument(documentId)
        assertArrayEquals(before.metaPlaintext, after.metaPlaintext)
        assertArrayEquals(before.revisionPlaintext, after.revisionPlaintext)
        assertEquals(before.head, after.head)
        assertEquals(1, store.list(AggregateKind.DOCUMENT).size)
    }

    // ---- helpers ------------------------------------------------------------

    private fun sourceBytes(size: Int): ByteArray {
        val out = ByteArray(size)
        val marker = "%PDF-1.7 synthetic T040 source".toByteArray()
        System.arraycopy(marker, 0, out, 0, minOf(marker.size, size))
        for (index in marker.size until size) {
            out[index] = (index * 31 + 7).toByte()
        }
        return out
    }

    private fun readAll(reader: EncryptedSourceReader): ByteArray {
        val out = ByteArray(reader.length.toInt())
        var read = 0
        while (read < out.size) {
            val count = reader.read(out, read, out.size - read)
            if (count < 0) break
            read += count
        }
        assertEquals(out.size, read)
        return out
    }

    private fun assertNoAggregate(documentId: String) {
        assertFalse(File(File(store.root, "docs"), documentId).exists())
        assertTrue(
            File(store.root, "docs").listFiles().orEmpty().isEmpty(),
        )
    }

    private fun assertNoPlaintext(source: ByteArray, root: File) {
        val marker = source.copyOfRange(0, minOf(source.size, 16))
        for (file in root.walkTopDown().filter { it.isFile }) {
            assertFalse(
                "plaintext marker found in ${file.relativeTo(root)}",
                file.readBytes().containsSubsequence(marker),
            )
        }
    }

    private fun ByteArray.containsSubsequence(needle: ByteArray): Boolean {
        if (needle.isEmpty()) return true
        if (needle.size > size) return false
        outer@ for (index in 0..size - needle.size) {
            for (offset in needle.indices) {
                if (this[index + offset] != needle[offset]) continue@outer
            }
            return true
        }
        return false
    }

    private fun newId(): String = UUID.randomUUID().toString()

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") {
            "%02x".format(it.toInt() and 0xFF)
        }
}
