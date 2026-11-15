package de.feldexa.app.storage

import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * T026 post-review: why the §3.1 step 8 retention policy cannot be inferred
 * from the canonical persisted state.
 *
 * The storage contract persists `RevisionContent` (no kind) in
 * `rev/<id>.fx1`; `head.fx1` carries only the current revision's kind and
 * parent. These tests show that two histories with identical persisted
 * revision payloads and identical heads can require different keep sets, so an
 * automatic save-path policy would need a contract decision (persisted kind or
 * caller-supplied policy), not a guess.
 */
class EncryptedStoreRetentionTest {

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
    fun persistedRevisionPayloadCarriesNoKindWhileHeadCarriesCurrentKind() {
        val documentId = UUID.randomUUID().toString()
        val revisionIds = listOf(fixedUuid(1), fixedUuid(2))
        store.createDocument(
            documentId,
            meta("Kind-Gap"),
            sourceId(),
            source(),
            revisionIds[0],
            revision(1),
            RevisionKindWire.AUTOSAVE,
        )
        store.saveRevision(
            documentId,
            revisionIds[1],
            revision(2),
            RevisionKindWire.EXPLICIT,
            revisionIds[0],
        )

        val ref = AggregateRef(AggregateKind.DOCUMENT, documentId)
        val first = store.readObjectForTest(RevisionObject(ref, revisionIds[0]))
        val second = store.readObjectForTest(RevisionObject(ref, revisionIds[1]))
        val head = store.readHeadForTest(ref)

        // RevisionContent (data-model §3.12) has no kind field. Only the
        // current head records kind (storage-format §3.1 step 5).
        assertFalse(String(first, Charsets.UTF_8).contains("\"kind\""))
        assertFalse(String(second, Charsets.UTF_8).contains("\"kind\""))
        assertEquals(RevisionKindWire.EXPLICIT, head.kind)
        assertEquals(revisionIds[1], head.revisionId)
        assertEquals(revisionIds[0], head.parentRevisionId)
    }

    @Test
    fun identicalPersistedPayloadsCanRequireDifferentKeepSets() {
        val firstDocument = UUID.randomUUID().toString()
        val secondDocument = UUID.randomUUID().toString()
        val revisionIds = (1..5).map(::fixedUuid)

        // History A: four autosaves then the newest explicit.
        val kindsA = listOf(
            RevisionKindWire.AUTOSAVE,
            RevisionKindWire.AUTOSAVE,
            RevisionKindWire.AUTOSAVE,
            RevisionKindWire.AUTOSAVE,
            RevisionKindWire.EXPLICIT,
        )
        // History B: the same revision payloads/head, but revision 2 was a
        // recovery restore. Only revision content and the current head are
        // persisted, so this difference is invisible on disk.
        val kindsB = listOf(
            RevisionKindWire.AUTOSAVE,
            RevisionKindWire.RECOVERY,
            RevisionKindWire.AUTOSAVE,
            RevisionKindWire.AUTOSAVE,
            RevisionKindWire.EXPLICIT,
        )

        createHistory(firstDocument, revisionIds, kindsA)
        createHistory(secondDocument, revisionIds, kindsB)

        val firstRef = AggregateRef(AggregateKind.DOCUMENT, firstDocument)
        val secondRef = AggregateRef(AggregateKind.DOCUMENT, secondDocument)

        // The persisted canonical revision payloads and heads are identical.
        assertEquals(store.readHeadForTest(firstRef), store.readHeadForTest(secondRef))
        for (revisionId in revisionIds) {
            assertArrayEquals(
                store.readObjectForTest(RevisionObject(firstRef, revisionId)),
                store.readObjectForTest(RevisionObject(secondRef, revisionId)),
            )
        }

        // Policy A: last 3 autosaves (rev2, rev3, rev4) + newest explicit
        // (rev5); no recovery. Policy B: last 3 autosaves (rev1, rev3, rev4)
        // + newest explicit (rev5) + recovery (rev2). The persisted state
        // cannot distinguish them.
        val keepA = setOf(revisionIds[1], revisionIds[2], revisionIds[3], revisionIds[4])
        val keepB = revisionIds.toSet()
        assertNotEquals(keepA, keepB)

        assertEquals(1, store.pruneRevisions(firstDocument, keepA))
        assertEquals(0, store.pruneRevisions(secondDocument, keepB))
        assertFalse(File(storeRoot, "docs/$firstDocument/rev/${revisionIds[0]}.fx1").exists())
        assertTrue(File(storeRoot, "docs/$secondDocument/rev/${revisionIds[0]}.fx1").exists())
    }

    @Test
    fun saveRevisionDoesNotGuessAPolicy() {
        val documentId = UUID.randomUUID().toString()
        val revisionIds = (1..6).map(::fixedUuid)
        store.createDocument(
            documentId,
            meta("Kein Raten"),
            sourceId(),
            source(),
            revisionIds[0],
            revision(1),
            RevisionKindWire.AUTOSAVE,
        )
        for (index in 1 until revisionIds.size) {
            store.saveRevision(
                documentId,
                revisionIds[index],
                revision(index + 1),
                RevisionKindWire.AUTOSAVE,
                revisionIds[index - 1],
            )
        }

        val revDir = File(storeRoot, "docs/$documentId/rev")
        val present = revDir.listFiles()!!.count { it.name.endsWith(".fx1") }
        // Until the owner chooses a kind-bearing persistence or a caller
        // policy, the save path must not invent retention and silently delete
        // data. This guard is intentionally removed only with that decision.
        assertEquals(6, present)
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private fun createHistory(
        documentId: String,
        revisionIds: List<String>,
        kinds: List<RevisionKindWire>,
    ) {
        require(revisionIds.size == kinds.size)
        store.createDocument(
            documentId,
            meta("History"),
            sourceId(),
            source(),
            revisionIds[0],
            revision(1),
            kinds[0],
        )
        for (index in 1 until revisionIds.size) {
            store.saveRevision(
                documentId,
                revisionIds[index],
                revision(index + 1),
                kinds[index],
                revisionIds[index - 1],
            )
        }
    }

    private fun fixedUuid(suffix: Int): String =
        "00000000-0000-4000-8000-%012d".format(suffix)

    private fun sourceId(): String = fixedUuid(100)

    private fun source(): ByteArray = "%PDF-1.7 retention".toByteArray()

    private fun meta(title: String): ByteArray =
        ("{\"createdAt\":\"2026-11-15T00:00:00.000Z\",\"title\":\"$title\"}")
            .toByteArray()

    private fun revision(value: Int): ByteArray =
        ("{\"pageCount\":$value,\"schemaVersion\":1}").toByteArray()
}
