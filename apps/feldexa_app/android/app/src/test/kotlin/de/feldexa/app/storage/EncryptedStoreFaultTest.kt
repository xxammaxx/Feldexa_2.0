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
 * T026 native fault-injection tests.
 *
 * The store's [StoreFaultInjector] is the Kotlin equivalent of the T036
 * testkit fault taxonomy: a test interrupts stage, fsync, promote, head
 * promotion, and read-back. The assertions follow `contracts/storage-format.md`
 * §3.1 and §5: a failure never reports success, the previous verified head
 * stays readable, and `ENOSPC` maps to `SAVE-001` while other I/O failures map
 * to `SAVE-003`.
 */
class EncryptedStoreFaultTest {

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
    fun quotaAtStageMapsToSave001AndKeepsOldHead() {
        val created = createDoc()
        val faultStore = storeWith(Faults(StoreFaultPoint.STAGE_CREATE) {
            throw IOException("ENOSPC: no space left on device")
        })

        assertFailure("SAVE-001") {
            faultStore.saveRevision(
                created.aggregateId,
                newId(),
                revision(2),
                RevisionKindWire.AUTOSAVE,
                created.revisionId,
            )
        }
        assertEquals(created.revisionId, store.loadDocument(created.aggregateId).head.revisionId)
        assertTmpClean()
    }

    @Test
    fun stageWriteFailureIsSave003AndKeepsOldHead() {
        val created = createDoc()
        val faultStore = storeWith(Faults(StoreFaultPoint.STAGE_WRITE) {
            throw IOException("short write")
        })

        assertFailure("SAVE-003") {
            faultStore.saveRevision(
                created.aggregateId,
                newId(),
                revision(2),
                RevisionKindWire.AUTOSAVE,
                created.revisionId,
            )
        }
        assertEquals(created.revisionId, store.loadDocument(created.aggregateId).head.revisionId)
        assertTmpClean()
    }

    @Test
    fun stageFsyncFailureIsSave003AndKeepsOldHead() {
        val created = createDoc()
        val faultStore = storeWith(Faults(StoreFaultPoint.STAGE_FSYNC) {
            throw IOException("fsync failed")
        })

        assertFailure("SAVE-003") {
            faultStore.saveRevision(
                created.aggregateId,
                newId(),
                revision(2),
                RevisionKindWire.AUTOSAVE,
                created.revisionId,
            )
        }
        assertEquals(created.revisionId, store.loadDocument(created.aggregateId).head.revisionId)
        assertTmpClean()
    }

    @Test
    fun promoteFailureIsSave003AndKeepsOldHead() {
        val created = createDoc()
        val faultStore = storeWith(Faults(StoreFaultPoint.PROMOTE) {
            throw IOException("rename failed")
        })

        assertFailure("SAVE-003") {
            faultStore.saveRevision(
                created.aggregateId,
                newId(),
                revision(2),
                RevisionKindWire.AUTOSAVE,
                created.revisionId,
            )
        }
        assertEquals(created.revisionId, store.loadDocument(created.aggregateId).head.revisionId)
        assertTmpClean()
    }

    @Test
    fun promoteFsyncFailureIsSave003AndKeepsOldHead() {
        val created = createDoc()
        val faultStore = storeWith(Faults(StoreFaultPoint.PROMOTE_FSYNC) {
            throw IOException("directory fsync failed")
        })

        assertFailure("SAVE-003") {
            faultStore.saveRevision(
                created.aggregateId,
                newId(),
                revision(2),
                RevisionKindWire.AUTOSAVE,
                created.revisionId,
            )
        }
        assertEquals(created.revisionId, store.loadDocument(created.aggregateId).head.revisionId)
    }

    @Test
    fun headStageFsyncFailureLeavesPreviousHeadReadable() {
        val created = createDoc()
        // First fsync belongs to the revision, second to the head.
        val faultStore = storeWith(
            Faults(StoreFaultPoint.STAGE_FSYNC, occurrence = 2) {
                throw IOException("head fsync failed")
            },
        )

        assertFailure("SAVE-003") {
            faultStore.saveRevision(
                created.aggregateId,
                newId(),
                revision(2),
                RevisionKindWire.AUTOSAVE,
                created.revisionId,
            )
        }
        assertEquals(created.revisionId, store.loadDocument(created.aggregateId).head.revisionId)
        assertTmpClean()
    }

    @Test
    fun corruptHeadAfterPromotionIsDetectedAndPreviousHeadRestored() {
        val created = createDoc()
        val headFile = File(storeRoot, "docs/${created.aggregateId}/head.fx1")
        val faultStore = storeWith(
            Faults(StoreFaultPoint.HEAD_PROMOTED) {
                // Return normally after corrupting the promoted file so the
                // store's own read-back verification must catch it.
                headFile.writeBytes(byteArrayOf(1, 2, 3))
            },
        )

        assertFailure("SAVE-003") {
            faultStore.saveRevision(
                created.aggregateId,
                newId(),
                revision(2),
                RevisionKindWire.AUTOSAVE,
                created.revisionId,
            )
        }

        // The previous head ciphertext was restored byte-for-byte.
        val loaded = store.loadDocument(created.aggregateId)
        assertEquals(created.revisionId, loaded.head.revisionId)
        assertTrue(headFile.length() > EncryptedStore.HEADER_SIZE)
    }

    @Test
    fun corruptRevisionAfterPromotionFailsReadBackAndKeepsOldHead() {
        val created = createDoc()
        val revisionId = newId()
        val revisionFile = File(storeRoot, "docs/${created.aggregateId}/rev/$revisionId.fx1")
        val faultStore = storeWith(
            Faults(StoreFaultPoint.PROMOTE_FSYNC) {
                if (revisionFile.exists()) {
                    val bytes = revisionFile.readBytes()
                    bytes[160] = (bytes[160].toInt() xor 0x01).toByte()
                    revisionFile.writeBytes(bytes)
                }
            },
        )

        assertFailure("SAVE-003") {
            faultStore.saveRevision(
                created.aggregateId,
                revisionId,
                revision(2),
                RevisionKindWire.AUTOSAVE,
                created.revisionId,
            )
        }
        assertEquals(created.revisionId, store.loadDocument(created.aggregateId).head.revisionId)
    }

    @Test
    fun failedCreateLeavesNoVisibleAggregateAndNoAlias() {
        val documentId = newId()
        val faultStore = storeWith(Faults(StoreFaultPoint.STAGE_CREATE) {
            throw IOException("ENOSPC")
        })

        assertFailure("SAVE-001") {
            faultStore.createDocument(
                documentId,
                meta("Nicht sichtbar"),
                newId(),
                "%PDF-1.7".toByteArray(),
                newId(),
                revision(1),
            )
        }

        assertFalse(File(storeRoot, "docs/$documentId").exists())
        assertFalse(backend.keys.containsKey(AggregateRef(AggregateKind.DOCUMENT, documentId).alias))
        assertTrue(store.list(AggregateKind.DOCUMENT).isEmpty())
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private fun storeWith(injector: StoreFaultInjector): EncryptedStore =
        EncryptedStore(
            root = storeRoot,
            keystore = keystore,
            faultInjector = injector,
            clock = { now.get() },
        )

    private fun createDoc(): CreateReceipt {
        val documentId = newId()
        return store.createDocument(
            documentId,
            meta("Dokument"),
            newId(),
            "%PDF-1.7 synthetic".toByteArray(),
            newId(),
            revision(1),
        )
    }

    private fun newId(): String = UUID.randomUUID().toString()

    private fun meta(title: String): ByteArray =
        ("{\"createdAt\":\"2026-11-15T00:00:00.000Z\",\"title\":\"$title\"}")
            .toByteArray()

    private fun revision(value: Int): ByteArray =
        ("{\"pageCount\":$value,\"schemaVersion\":1}").toByteArray()

    private fun assertTmpClean() {
        val tmp = File(storeRoot, "tmp")
        assertTrue(
            "tmp must be clean, found ${tmp.listFiles()?.map { it.name }}",
            tmp.listFiles()!!.isEmpty(),
        )
    }

    private fun assertFailure(expectedCode: String, block: () -> Unit) {
        val failure = try {
            block()
            null
        } catch (error: StorageException) {
            error
        }
        assertNotNull("expected a StorageException with $expectedCode", failure)
        assertEquals(expectedCode, failure!!.code)
    }

    private class Faults(
        private val point: StoreFaultPoint,
        private val occurrence: Int = 1,
        private val action: () -> Unit = { throw IOException("injected") },
    ) : StoreFaultInjector {
        private var seen: Int = 0

        override fun onFault(point: StoreFaultPoint, transactionId: String) {
            if (point != this.point) return
            seen++
            if (seen < occurrence) return
            action()
        }
    }
}
