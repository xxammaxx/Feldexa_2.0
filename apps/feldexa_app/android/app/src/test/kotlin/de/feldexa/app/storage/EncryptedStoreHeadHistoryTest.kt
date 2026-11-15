package de.feldexa.app.storage

import java.io.File
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
 * T026 owner decision: bounded known-kind history in `head.fx1` and automatic
 * application of the retention policy after a durable, verified commit.
 *
 * Policy: last 3 autosaves + newest explicit + newest recovery + the verified
 * head. Unknown-kind/untrusted legacy revisions are retained conservatively.
 */
class EncryptedStoreHeadHistoryTest {

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
    fun headStoresBoundedKnownHistoryInCommitOrder() {
        val documentId = UUID.randomUUID().toString()
        val first = fixedUuid(1)
        val second = fixedUuid(2)
        val third = fixedUuid(3)
        val created = store.createDocument(
            documentId,
            meta("History"),
            sourceId(),
            source(),
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

        val head = store.readHeadForTest(AggregateRef(AggregateKind.DOCUMENT, documentId))
        assertEquals(
            listOf(first, second, third),
            head.history.map { it.revisionId },
        )
        assertEquals(
            listOf(
                RevisionKindWire.AUTOSAVE,
                RevisionKindWire.AUTOSAVE,
                RevisionKindWire.EXPLICIT,
            ),
            head.history.map { it.kind },
        )
        assertTrue(head.history.size <= EncryptedStore.MAX_HEAD_HISTORY)
        assertEquals(third, head.revisionId)
        assertEquals(RevisionKindWire.EXPLICIT, head.kind)
        // The revision payload remains RevisionContent; kind lives only in the
        // head history (and the current head fields).
        val revision = store.readObjectForTest(
            RevisionObject(AggregateRef(AggregateKind.DOCUMENT, documentId), first),
        )
        assertFalse(String(revision, Charsets.UTF_8).contains("\"kind\""))
    }

    @Test
    fun saveAppliesPolicyAfterVerifiedCommit() {
        val documentId = UUID.randomUUID().toString()
        val ids = (1..7).map(::fixedUuid)
        val created = store.createDocument(
            documentId,
            meta("Policy"),
            sourceId(),
            source(),
            ids[0],
            revision(1),
            RevisionKindWire.AUTOSAVE,
        )
        val kinds = listOf(
            RevisionKindWire.AUTOSAVE,
            RevisionKindWire.AUTOSAVE,
            RevisionKindWire.AUTOSAVE,
            RevisionKindWire.AUTOSAVE,
            RevisionKindWire.EXPLICIT,
            RevisionKindWire.RECOVERY,
            RevisionKindWire.EXPLICIT,
        )
        var expectedHead = created.revisionId
        var prunedAtRevision4 = 0
        for (index in 1 until ids.size) {
            val receipt = store.saveRevision(
                documentId,
                ids[index],
                revision(index + 1),
                kinds[index],
                expectedHead,
            )
            if (index == 3) prunedAtRevision4 = receipt.prunedRevisions
            expectedHead = ids[index]
        }

        // After four autosaves the policy keeps the last three: rev1 is gone.
        assertEquals(1, prunedAtRevision4)
        assertFalse(revFile(documentId, ids[0]).exists())
        assertTrue(revFile(documentId, ids[1]).exists())
        assertTrue(revFile(documentId, ids[2]).exists())
        assertTrue(revFile(documentId, ids[3]).exists())

        // After the newest explicit and recovery, the older explicit rev5 is
        // superseded; the last 3 autosaves, rev6 recovery, and rev7 explicit
        // remain. The head is always protected.
        assertFalse(revFile(documentId, ids[4]).exists())
        assertTrue(revFile(documentId, ids[5]).exists())
        assertTrue(revFile(documentId, ids[6]).exists())
        assertEquals(ids[6], store.loadDocument(documentId).head.revisionId)

        val head = store.readHeadForTest(AggregateRef(AggregateKind.DOCUMENT, documentId))
        assertEquals(
            setOf(ids[1], ids[2], ids[3], ids[5], ids[6]),
            head.history.map { it.revisionId }.toSet(),
        )
        assertTrue(head.history.all { entry ->
            entry.revisionId == head.revisionId || revFile(documentId, entry.revisionId).exists()
        })
    }

    @Test
    fun unknownHistoryEntriesAreRetainedConservatively() {
        val documentId = UUID.randomUUID().toString()
        val first = fixedUuid(1)
        val second = fixedUuid(2)
        val created = store.createDocument(
            documentId,
            meta("Unknown"),
            sourceId(),
            source(),
            first,
            revision(1),
            RevisionKindWire.AUTOSAVE,
        )
        store.saveRevision(
            documentId,
            second,
            revision(2),
            RevisionKindWire.EXPLICIT,
            created.revisionId,
        )
        val ref = AggregateRef(AggregateKind.DOCUMENT, documentId)
        val head = store.readHeadForTest(ref)
        // Simulate a legacy/unknown kind for rev1 while keeping rev2 known.
        store.commitHeadForTest(
            ref,
            head.copy(
                history = listOf(
                    HeadHistoryEntry(first, null),
                    HeadHistoryEntry(second, RevisionKindWire.EXPLICIT),
                ),
            ),
        )

        val deleted = store.pruneRevisions(documentId, setOf(second))

        assertEquals(0, deleted)
        assertTrue(revFile(documentId, first).exists())
        assertTrue(revFile(documentId, second).exists())
    }

    @Test
    fun legacyHeadWithoutHistoryKeepsUntrackedRevisions() {
        val documentId = UUID.randomUUID().toString()
        val first = fixedUuid(1)
        val second = fixedUuid(2)
        val third = fixedUuid(3)
        val created = store.createDocument(
            documentId,
            meta("Legacy"),
            sourceId(),
            source(),
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
        val ref = AggregateRef(AggregateKind.DOCUMENT, documentId)
        val head = store.readHeadForTest(ref)
        // Simulate a head written before the history field existed.
        store.commitHeadForTest(ref, head.copy(history = emptyList()))

        assertEquals(0, store.pruneRevisions(documentId, emptySet()))
        assertTrue(revFile(documentId, first).exists())
        assertTrue(revFile(documentId, second).exists())
        assertTrue(revFile(documentId, third).exists())

        // The next save learns only the current head's kind + the new kind;
        // the older legacy revisions remain untracked and are retained.
        store.saveRevision(
            documentId,
            fixedUuid(4),
            revision(4),
            RevisionKindWire.RECOVERY,
            third,
        )
        assertTrue(revFile(documentId, first).exists())
        assertTrue(revFile(documentId, second).exists())
    }

    @Test
    fun crashBeforePruneIsReconciledOnStartup() {
        val documentId = UUID.randomUUID().toString()
        val ids = (1..5).map(::fixedUuid)
        val created = store.createDocument(
            documentId,
            meta("Crash"),
            sourceId(),
            source(),
            ids[0],
            revision(1),
            RevisionKindWire.AUTOSAVE,
        )
        var expectedHead = created.revisionId
        for (index in 1 until 4) {
            store.saveRevision(
                documentId,
                ids[index],
                revision(index + 1),
                RevisionKindWire.AUTOSAVE,
                expectedHead,
            )
            expectedHead = ids[index]
        }
        // Rev1 was pruned normally. Add an untracked known autosave file and a
        // head history that still names it, simulating a crash between the
        // durable head and the prune step.
        val ref = AggregateRef(AggregateKind.DOCUMENT, documentId)
        val extra = fixedUuid(99)
        store.commitObjectForTest(RevisionObject(ref, extra), revision(99))
        val head = store.readHeadForTest(ref)
        store.commitHeadForTest(
            ref,
            head.copy(
                history = listOf(HeadHistoryEntry(extra, RevisionKindWire.AUTOSAVE)) +
                    head.history,
            ),
        )

        val report = store.startupRecovery()

        assertTrue(report.prunedRevisions >= 1)
        assertFalse(revFile(documentId, extra).exists())
        assertTrue(revFile(documentId, ids[3]).exists())
        assertEquals(ids[3], store.loadDocument(documentId).head.revisionId)
    }

    @Test
    fun historyStaysBoundedAfterManyCommits() {
        val documentId = UUID.randomUUID().toString()
        val ids = (1..20).map(::fixedUuid)
        val created = store.createDocument(
            documentId,
            meta("Bound"),
            sourceId(),
            source(),
            ids[0],
            revision(1),
            RevisionKindWire.AUTOSAVE,
        )
        var expectedHead = created.revisionId
        for (index in 1 until ids.size) {
            store.saveRevision(
                documentId,
                ids[index],
                revision(index + 1),
                RevisionKindWire.AUTOSAVE,
                expectedHead,
            )
            expectedHead = ids[index]
        }

        val head = store.readHeadForTest(AggregateRef(AggregateKind.DOCUMENT, documentId))
        assertTrue(head.history.size <= EncryptedStore.MAX_HEAD_HISTORY)
        assertTrue(head.history.all { revFile(documentId, it.revisionId).exists() })
        // Last three autosaves plus the current head survive; older known
        // revisions were pruned after their durable commits.
        assertTrue(revFile(documentId, ids[19]).exists())
        assertTrue(revFile(documentId, ids[18]).exists())
        assertTrue(revFile(documentId, ids[17]).exists())
        assertFalse(revFile(documentId, ids[0]).exists())
    }

    @Test
    fun deleteFailureIsConservativeAndRetriedOnNextCommit() {
        val noDeleteIo = NoDeleteStoreIo()
        val constrainedStore = EncryptedStore(
            root = storeRoot,
            keystore = keystore,
            io = noDeleteIo,
            clock = { now.get() },
        )
        constrainedStore.ensureLayout()
        val documentId = UUID.randomUUID().toString()
        val ids = (1..5).map(::fixedUuid)
        val created = constrainedStore.createDocument(
            documentId,
            meta("NoDelete"),
            sourceId(),
            source(),
            ids[0],
            revision(1),
            RevisionKindWire.AUTOSAVE,
        )
        var expectedHead = created.revisionId
        for (index in 1 until 4) {
            constrainedStore.saveRevision(
                documentId,
                ids[index],
                revision(index + 1),
                RevisionKindWire.AUTOSAVE,
                expectedHead,
            )
            expectedHead = ids[index]
        }
        // Deletions failed, but the durable head and all data remain.
        assertTrue(revFile(documentId, ids[0]).exists())
        assertEquals(ids[3], constrainedStore.loadDocument(documentId).head.revisionId)

        // A normal store on the same root retries and removes the known
        // non-kept revision on the next durable commit.
        val retryStore = EncryptedStore(storeRoot, keystore, clock = { now.get() })
        retryStore.saveRevision(
            documentId,
            ids[4],
            revision(5),
            RevisionKindWire.AUTOSAVE,
            ids[3],
        )
        assertFalse(revFile(documentId, ids[0]).exists())
        assertEquals(ids[4], retryStore.loadDocument(documentId).head.revisionId)
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private fun revFile(documentId: String, revisionId: String): File =
        File(storeRoot, "docs/$documentId/rev/$revisionId.fx1")

    private fun fixedUuid(suffix: Int): String =
        "00000000-0000-4000-8000-%012d".format(suffix)

    private fun sourceId(): String = fixedUuid(100)

    private fun source(): ByteArray = "%PDF-1.7 head history".toByteArray()

    private fun meta(title: String): ByteArray =
        ("{\"createdAt\":\"2026-11-15T00:00:00.000Z\",\"title\":\"$title\"}")
            .toByteArray()

    private fun revision(value: Int): ByteArray =
        ("{\"pageCount\":$value,\"schemaVersion\":1}").toByteArray()

    private class NoDeleteStoreIo(
        private val delegate: StoreIo = RealStoreIo(),
    ) : StoreIo {

        override fun openExclusive(file: File) = delegate.openExclusive(file)

        override fun openRead(file: File) = delegate.openRead(file)

        override fun atomicMove(from: File, to: File) = delegate.atomicMove(from, to)

        override fun fsyncDirectory(directory: File) = delegate.fsyncDirectory(directory)

        override fun delete(file: File): Boolean = false

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

        override fun lastModifiedNanos(file: File): Long =
            delegate.lastModifiedNanos(file)

        override fun setLastModified(file: File, millis: Long): Boolean =
            delegate.setLastModified(file, millis)

        override fun fsyncFile(file: File) = delegate.fsyncFile(file)
    }
}
