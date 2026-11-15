package de.feldexa.app.storage

import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
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
 * T026 review-correction tests for `365b384`.
 *
 * The review found four concrete problems:
 *  1. compare-and-commit was not serialized, so two parallel saves could both
 *     accept the same expected head and a rollback could overwrite the other;
 *  2. `readContainer` buffered the complete plaintext (up to 96 MiB) during
 *     verification, against the chunk-memory rule in storage-format §6;
 *  3. recovery sorted equal-millisecond revisions by random UUID;
 *  4. §3.1 step 8 pruning was absent and not explicitly owned.
 *
 * Tests 1, 2, and 3 are deterministic reproductions/fixes. Test 4 covers the
 * new safe prune primitive; the policy ownership is documented in the
 * review-correction report because the persisted format has no revision kind.
 */
class EncryptedStoreReviewTest {

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

    // ------------------------------------------------------------------
    // 1. Compare-and-commit serialization
    // ------------------------------------------------------------------

    @Test
    fun twoSavesWithTheSameExpectedHeadMustNotBothCommit() {
        val created = createDocument()
        val firstEntered = CountDownLatch(1)
        val releaseFirst = CountDownLatch(1)
        val secondStarted = CountDownLatch(1)
        val firstInjection = AtomicBoolean(true)
        val faultStore = EncryptedStore(
            root = storeRoot,
            keystore = keystore,
            faultInjector = StoreFaultInjector { point, _ ->
                if (point == StoreFaultPoint.STAGE_CREATE &&
                    firstInjection.compareAndSet(true, false)
                ) {
                    firstEntered.countDown()
                    if (!releaseFirst.await(5, TimeUnit.SECONDS)) {
                        throw IllegalStateException("test latch timeout")
                    }
                }
            },
            clock = { now.get() },
        )

        val secondRevision = fixedUuid(2)
        val thirdRevision = fixedUuid(3)
        val executor = Executors.newFixedThreadPool(2)
        try {
            val first = executor.submit<CommitReceipt> {
                faultStore.saveRevision(
                    created.aggregateId,
                    secondRevision,
                    revision(2),
                    RevisionKindWire.AUTOSAVE,
                    created.revisionId,
                )
            }
            assertTrue(firstEntered.await(5, TimeUnit.SECONDS))

            val second = executor.submit<CommitReceipt> {
                secondStarted.countDown()
                faultStore.saveRevision(
                    created.aggregateId,
                    thirdRevision,
                    revision(3),
                    RevisionKindWire.AUTOSAVE,
                    created.revisionId,
                )
            }
            assertTrue(secondStarted.await(5, TimeUnit.SECONDS))
            // Without serialization the second save finishes while the first
            // is paused; with serialization it waits on the aggregate lock.
            Thread.sleep(250)
            releaseFirst.countDown()

            val outcomes = listOf(
                runCatching { first.get(10, TimeUnit.SECONDS) },
                runCatching { second.get(10, TimeUnit.SECONDS) },
            )
            val successes = outcomes.count { it.isSuccess }
            val conflicts = outcomes.count { outcome ->
                outcome.exceptionOrNull()?.causedBy<ConcurrentSaveException>() != null
            }
            assertEquals("exactly one save may win", 1, successes)
            assertEquals("the loser must report SAVE-006", 1, conflicts)
            val head = store.loadDocument(created.aggregateId).head.revisionId
            assertTrue(head == secondRevision || head == thirdRevision)
        } finally {
            releaseFirst.countDown()
            executor.shutdownNow()
        }
    }

    // ------------------------------------------------------------------
    // 2. Chunk-bounded verification
    // ------------------------------------------------------------------

    @Test
    fun verificationStreamsChunksInOrder() {
        val ref = AggregateRef(AggregateKind.DOCUMENT, UUID.randomUUID().toString())
        keystore.createAggregateKey(ref)
        val obj = RevisionObject(ref, UUID.randomUUID().toString())
        val plaintext = ByteArray(3 * 1024 * 1024 + 17) { (it % 251).toByte() }
        store.commitObjectForTest(obj, plaintext)

        val chunks = mutableListOf<Int>()
        val sha = store.verifyObjectForTest(obj) { _, length ->
            chunks += length
        }

        assertEquals(sha256Hex(plaintext), sha)
        assertEquals(listOf(1_048_576, 1_048_576, 1_048_576, 17), chunks)
    }

    @Test
    fun eightyMiBObjectVerifiesUnder128MiBHeap() {
        val java = File(System.getProperty("java.home"), "bin/java").absolutePath
        val classpath = System.getProperty("java.class.path")
        val process = ProcessBuilder(
            java,
            "-Xmx128m",
            "-cp",
            classpath,
            "de.feldexa.app.storage.MemoryBoundedStoreProbe",
        )
            .redirectErrorStream(true)
            .start()
        val output = process.inputStream.bufferedReader().use { it.readText() }
        val finished = process.waitFor(180, TimeUnit.SECONDS)
        if (!finished) process.destroyForcibly()
        assertTrue("memory probe timed out", finished)
        assertEquals(
            "memory probe failed; output:\n$output",
            0,
            process.exitValue(),
        )
        assertTrue(output.contains("MEMORY_PROBE_OK"))
    }

    // ------------------------------------------------------------------
    // 3. Recovery order
    // ------------------------------------------------------------------

    @Test
    fun commitsPersistStrictlyIncreasingRevisionTimestamps() {
        val created = createDocument()
        val second = fixedUuid(2)
        store.saveRevision(
            created.aggregateId,
            second,
            revision(2),
            RevisionKindWire.AUTOSAVE,
            created.revisionId,
        )

        val revDir = File(storeRoot, "docs/${created.aggregateId}/rev")
        val firstFile = File(revDir, "${created.revisionId}.fx1")
        val secondFile = File(revDir, "$second.fx1")
        assertTrue(
            "newer revision must have a strictly newer mtime",
            secondFile.lastModified() > firstFile.lastModified(),
        )

        File(storeRoot, "docs/${created.aggregateId}/head.fx1").delete()
        val stamp = store.recoveryStamp(AggregateKind.DOCUMENT, created.aggregateId)

        assertTrue(stamp.readable)
        assertTrue(stamp.fellBackToOlderRevision)
        assertEquals(second, stamp.verifiedRevisionId)
        assertFalse(stamp.ambiguousRevisionOrder)
    }

    @Test
    fun equalTimestampRecoveryMustNotPickByRandomUuid() {
        val higherUuid = fixedUuid(9)
        val lowerUuid = fixedUuid(1)
        val documentId = UUID.randomUUID().toString()
        val created = store.createDocument(
            documentId,
            meta("Rennen"),
            UUID.randomUUID().toString(),
            "%PDF-1.7".toByteArray(),
            higherUuid,
            revision(1),
        )
        store.saveRevision(
            documentId,
            lowerUuid,
            revision(2),
            RevisionKindWire.AUTOSAVE,
            created.revisionId,
        )

        val revDir = File(storeRoot, "docs/$documentId/rev")
        val highFile = File(revDir, "$higherUuid.fx1")
        val lowFile = File(revDir, "$lowerUuid.fx1")
        val equalTimestamp = now.get() - 1_000
        assertTrue(highFile.setLastModified(equalTimestamp))
        assertTrue(lowFile.setLastModified(equalTimestamp))
        assertEquals(highFile.lastModified(), lowFile.lastModified())
        File(storeRoot, "docs/$documentId/head.fx1").delete()

        val stamp = store.recoveryStamp(AggregateKind.DOCUMENT, documentId)

        // The format stores no revision sequence. Equal timestamps make the
        // actual order unknowable, so the store must fail closed instead of
        // silently restoring the older revision by UUID order.
        assertFalse(stamp.readable)
        assertEquals("SAVE-003", stamp.unreadableReasonCode)
        assertTrue(stamp.ambiguousRevisionOrder)
        assertTrue(highFile.exists())
        assertTrue(lowFile.exists())
    }

    // ------------------------------------------------------------------
    // 4. Safe pruning primitive (§3.1 step 8)
    // ------------------------------------------------------------------

    @Test
    fun pruneKeepsHeadAndRequestedRevisions() {
        val documentId = UUID.randomUUID().toString()
        val first = fixedUuid(1)
        val second = fixedUuid(2)
        val third = fixedUuid(3)
        val created = store.createDocument(
            documentId,
            meta("Pruning"),
            UUID.randomUUID().toString(),
            "%PDF-1.7".toByteArray(),
            first,
            revision(1),
            RevisionKindWire.AUTOSAVE,
        )
        store.saveRevision(
            documentId,
            second,
            revision(2),
            RevisionKindWire.AUTOSAVE,
            created.revisionId,
        )
        store.saveRevision(
            documentId,
            third,
            revision(3),
            RevisionKindWire.EXPLICIT,
            second,
        )

        val deleted = store.pruneRevisions(documentId, setOf(third))

        assertEquals(2, deleted)
        val revDir = File(storeRoot, "docs/$documentId/rev")
        assertFalse(File(revDir, "$first.fx1").exists())
        assertFalse(File(revDir, "$second.fx1").exists())
        assertTrue(File(revDir, "$third.fx1").exists())
        assertEquals(third, store.loadDocument(documentId).head.revisionId)
    }

    @Test
    fun pruneNeverDeletesTheHeadEvenWhenItIsNotInTheKeepSet() {
        val documentId = UUID.randomUUID().toString()
        val first = fixedUuid(1)
        val second = fixedUuid(2)
        val third = fixedUuid(3)
        val created = store.createDocument(
            documentId,
            meta("Pruning"),
            UUID.randomUUID().toString(),
            "%PDF-1.7".toByteArray(),
            first,
            revision(1),
            RevisionKindWire.AUTOSAVE,
        )
        store.saveRevision(
            documentId,
            second,
            revision(2),
            RevisionKindWire.AUTOSAVE,
            created.revisionId,
        )
        store.saveRevision(
            documentId,
            third,
            revision(3),
            RevisionKindWire.EXPLICIT,
            second,
        )

        val deleted = store.pruneRevisions(documentId, emptySet())

        assertEquals(2, deleted)
        val revDir = File(storeRoot, "docs/$documentId/rev")
        assertTrue(File(revDir, "$third.fx1").exists())
        assertEquals(third, store.loadDocument(documentId).head.revisionId)
    }

    @Test
    fun pruneRefusesToDeleteWhenTheHeadDoesNotVerify() {
        val created = createDocument()
        val second = fixedUuid(2)
        store.saveRevision(
            created.aggregateId,
            second,
            revision(2),
            RevisionKindWire.AUTOSAVE,
            created.revisionId,
        )
        val revDir = File(storeRoot, "docs/${created.aggregateId}/rev")
        val firstFile = File(revDir, "${created.revisionId}.fx1")
        val secondFile = File(revDir, "$second.fx1")
        val headFile = File(storeRoot, "docs/${created.aggregateId}/head.fx1")
        val headBytes = headFile.readBytes()
        headBytes[160] = (headBytes[160].toInt() xor 0x01).toByte()
        headFile.writeBytes(headBytes)

        val failure = try {
            store.pruneRevisions(created.aggregateId, setOf(second))
            null
        } catch (error: StorageException) {
            error
        }

        assertNotNull(failure)
        assertEquals("SAVE-003", failure!!.code)
        assertTrue(firstFile.exists())
        assertTrue(secondFile.exists())
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private fun createDocument(): CreateReceipt {
        val documentId = UUID.randomUUID().toString()
        return store.createDocument(
            documentId,
            meta("Dokument"),
            UUID.randomUUID().toString(),
            "%PDF-1.7".toByteArray(),
            fixedUuid(1),
            revision(1),
        )
    }

    private fun fixedUuid(suffix: Int): String =
        "00000000-0000-4000-8000-%012d".format(suffix)

    private fun meta(title: String): ByteArray =
        ("{\"createdAt\":\"2026-11-15T00:00:00.000Z\",\"title\":\"$title\"}")
            .toByteArray()

    private fun revision(value: Int): ByteArray =
        ("{\"pageCount\":$value,\"schemaVersion\":1}").toByteArray()

    private fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { "%02x".format(it.toInt() and 0xFF) }
    }

    private inline fun <reified T : Throwable> Throwable.causedBy(): T? {
        var current: Throwable? = this
        while (current != null) {
            if (current is T) return current
            current = current.cause
        }
        return null
    }
}
