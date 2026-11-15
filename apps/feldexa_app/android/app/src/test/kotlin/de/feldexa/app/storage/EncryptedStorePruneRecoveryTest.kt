package de.feldexa.app.storage

import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * T026 security review of `ff8f7fb`: prune-delete durability.
 *
 * A revision delete that is not followed by a successful revision-directory
 * fsync may reappear after a crash. The history must therefore stay complete
 * until the delete fsync is confirmed; otherwise the resurrected file becomes
 * untracked and bypasses retention forever.
 */
class EncryptedStorePruneRecoveryTest {

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
    fun pruneFsyncFailureKeepsFullHistoryAndStartupRetries() {
        val documentId = UUID.randomUUID().toString()
        val ids = (1..4).map(::fixedUuid)
        val created = store.createDocument(
            documentId,
            meta("PruneFsync"),
            sourceId(),
            source(),
            ids[0],
            revision(1),
            RevisionKindWire.AUTOSAVE,
        )
        store.saveRevision(
            documentId,
            ids[1],
            revision(2),
            RevisionKindWire.AUTOSAVE,
            created.revisionId,
        )
        store.saveRevision(
            documentId,
            ids[2],
            revision(3),
            RevisionKindWire.AUTOSAVE,
            ids[1],
        )
        val firstBytes = revFile(documentId, ids[0]).readBytes()
        val faultStore = EncryptedStore(
            root = storeRoot,
            keystore = keystore,
            faultInjector = StoreFaultInjector { point, _ ->
                if (point == StoreFaultPoint.PRUNE_FSYNC) {
                    throw IOException("prune directory fsync failed")
                }
            },
            clock = { now.get() },
        )

        val receipt = faultStore.saveRevision(
            documentId,
            ids[3],
            revision(4),
            RevisionKindWire.AUTOSAVE,
            ids[2],
        )

        // The delete ran, but its durability was not confirmed.
        assertFalse(revFile(documentId, ids[0]).exists())
        assertEquals(0, receipt.prunedRevisions)
        val headAfterFailure = store.readHeadForTest(
            AggregateRef(AggregateKind.DOCUMENT, documentId),
        )
        assertTrue(
            "history must remain complete after an unconfirmed delete fsync",
            headAfterFailure.history.any { it.revisionId == ids[0] },
        )

        // Simulate the crash: the non-durable delete is lost, so rev1
        // reappears. The full history still knows it and the next startup
        // retries the durable deletion before trimming.
        revFile(documentId, ids[0]).writeBytes(firstBytes)

        val report = store.startupRecovery()

        assertTrue(report.prunedRevisions >= 1)
        assertFalse(revFile(documentId, ids[0]).exists())
        val recoveredHead = store.readHeadForTest(
            AggregateRef(AggregateKind.DOCUMENT, documentId),
        )
        assertFalse(recoveredHead.history.any { it.revisionId == ids[0] })
        assertEquals(ids[3], recoveredHead.revisionId)
        assertTrue(revFile(documentId, ids[3]).exists())
    }

    @Test
    fun pruneFsyncFailureDuringStartupIsRetryableWithoutTrimmingHistory() {
        val documentId = UUID.randomUUID().toString()
        val ids = (1..4).map(::fixedUuid)
        val created = store.createDocument(
            documentId,
            meta("StartupFsync"),
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
        val ref = AggregateRef(AggregateKind.DOCUMENT, documentId)
        val extra = fixedUuid(99)
        store.commitObjectForTest(RevisionObject(ref, extra), revision(99))
        val extraBytes = revFile(documentId, extra).readBytes()
        val current = store.readHeadForTest(ref)
        store.commitHeadForTest(
            ref,
            current.copy(
                history = listOf(HeadHistoryEntry(extra, RevisionKindWire.AUTOSAVE)) +
                    current.history,
            ),
        )
        val faultStore = EncryptedStore(
            root = storeRoot,
            keystore = keystore,
            faultInjector = StoreFaultInjector { point, _ ->
                if (point == StoreFaultPoint.PRUNE_FSYNC) {
                    throw IOException("startup prune fsync failed")
                }
            },
            clock = { now.get() },
        )

        val firstReport = faultStore.startupRecovery()

        // The file may be gone from the namespace, but the unconfirmed delete
        // must not shorten the history or claim a durable prune.
        assertEquals(0, firstReport.prunedRevisions)
        val headAfterFailure = store.readHeadForTest(ref)
        assertTrue(headAfterFailure.history.any { it.revisionId == extra })
        assertFalse(revFile(documentId, extra).exists())

        // Crash resurrection: restore the file, then a normal startup retries
        // the delete, confirms the fsync and only then trims history.
        revFile(documentId, extra).writeBytes(extraBytes)
        val secondReport = store.startupRecovery()

        assertTrue(secondReport.prunedRevisions >= 1)
        assertFalse(revFile(documentId, extra).exists())
        val finalHead = store.readHeadForTest(ref)
        assertFalse(finalHead.history.any { it.revisionId == extra })
        assertEquals(ids[3], finalHead.revisionId)
    }

    @Test
    fun repeatedFsyncFailureWithoutResurrectionRetriesBeforeHistoryTrim() {
        val documentId = UUID.randomUUID().toString()
        val ids = (1..4).map(::fixedUuid)
        val created = store.createDocument(
            documentId,
            meta("NoResurrection"),
            sourceId(),
            source(),
            ids[0],
            revision(1),
            RevisionKindWire.AUTOSAVE,
        )
        store.saveRevision(
            documentId,
            ids[1],
            revision(2),
            RevisionKindWire.AUTOSAVE,
            created.revisionId,
        )
        store.saveRevision(
            documentId,
            ids[2],
            revision(3),
            RevisionKindWire.AUTOSAVE,
            ids[1],
        )
        val faultStore = EncryptedStore(
            root = storeRoot,
            keystore = keystore,
            faultInjector = StoreFaultInjector { point, _ ->
                if (point == StoreFaultPoint.PRUNE_FSYNC) {
                    throw IOException("prune fsync still failing")
                }
            },
            clock = { now.get() },
        )
        faultStore.saveRevision(
            documentId,
            ids[3],
            revision(4),
            RevisionKindWire.AUTOSAVE,
            ids[2],
        )

        // No crash resurrection: the file stays missing. The retry itself has
        // no delete to perform, but it still must confirm directory
        // durability before dropping the history entry.
        assertFalse(revFile(documentId, ids[0]).exists())
        val repeatedFailureReport = faultStore.startupRecovery()
        assertEquals(0, repeatedFailureReport.prunedRevisions)
        val headAfterFailure = store.readHeadForTest(
            AggregateRef(AggregateKind.DOCUMENT, documentId),
        )
        assertTrue(headAfterFailure.history.any { it.revisionId == ids[0] })

        val retryReport = store.startupRecovery()

        assertEquals(0, retryReport.prunedRevisions)
        assertFalse(revFile(documentId, ids[0]).exists())
        val finalHead = store.readHeadForTest(
            AggregateRef(AggregateKind.DOCUMENT, documentId),
        )
        assertFalse(finalHead.history.any { it.revisionId == ids[0] })
        assertEquals(ids[3], finalHead.revisionId)
    }

    @Test
    fun nextSaveRetainsUnconfirmedMissingHistoryAndTrimsAfterConfirmation() {
        val documentId = UUID.randomUUID().toString()
        val ids = (1..5).map(::fixedUuid)
        val created = store.createDocument(
            documentId,
            meta("SaveRetry"),
            sourceId(),
            source(),
            ids[0],
            revision(1),
            RevisionKindWire.AUTOSAVE,
        )
        store.saveRevision(
            documentId,
            ids[1],
            revision(2),
            RevisionKindWire.AUTOSAVE,
            created.revisionId,
        )
        store.saveRevision(
            documentId,
            ids[2],
            revision(3),
            RevisionKindWire.AUTOSAVE,
            ids[1],
        )
        val faultStore = EncryptedStore(
            root = storeRoot,
            keystore = keystore,
            faultInjector = StoreFaultInjector { point, _ ->
                if (point == StoreFaultPoint.PRUNE_FSYNC) {
                    throw IOException("prune fsync failed")
                }
            },
            clock = { now.get() },
        )
        faultStore.saveRevision(
            documentId,
            ids[3],
            revision(4),
            RevisionKindWire.AUTOSAVE,
            ids[2],
        )
        assertFalse(revFile(documentId, ids[0]).exists())

        // The next head rebuild must retain the unconfirmed-missing entry;
        // the prune then confirms absence via fsync before trimming.
        store.saveRevision(
            documentId,
            ids[4],
            revision(5),
            RevisionKindWire.AUTOSAVE,
            ids[3],
        )

        assertFalse(revFile(documentId, ids[0]).exists())
        val finalHead = store.readHeadForTest(
            AggregateRef(AggregateKind.DOCUMENT, documentId),
        )
        assertFalse(finalHead.history.any { it.revisionId == ids[0] })
        assertEquals(ids[4], finalHead.revisionId)
        // rev2 is a known autosave outside the last three and is pruned; the
        // last three autosaves plus the new head remain.
        assertFalse(revFile(documentId, ids[1]).exists())
        assertTrue(revFile(documentId, ids[2]).exists())
        assertTrue(revFile(documentId, ids[3]).exists())
        assertTrue(revFile(documentId, ids[4]).exists())
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private fun revFile(documentId: String, revisionId: String): File =
        File(storeRoot, "docs/$documentId/rev/$revisionId.fx1")

    private fun fixedUuid(suffix: Int): String =
        "00000000-0000-4000-8000-%012d".format(suffix)

    private fun sourceId(): String = fixedUuid(100)

    private fun source(): ByteArray = "%PDF-1.7 prune fsync".toByteArray()

    private fun meta(title: String): ByteArray =
        ("{\"createdAt\":\"2026-11-15T00:00:00.000Z\",\"title\":\"$title\"}")
            .toByteArray()

    private fun revision(value: Int): ByteArray =
        ("{\"pageCount\":$value,\"schemaVersion\":1}").toByteArray()
}
