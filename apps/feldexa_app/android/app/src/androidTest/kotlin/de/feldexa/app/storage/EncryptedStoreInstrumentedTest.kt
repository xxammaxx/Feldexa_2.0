package de.feldexa.app.storage

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.IOException
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * T026 `EMULATOR`/`DEVICE` tests against the real `AndroidKeyStore`.
 *
 * Safety rule: the app id is the production id, so every logical aggregate
 * alias is mapped by [IsolatedTestBackend] into a unique
 * `feldexa.test.v1.<runToken>.` namespace. Cleanup deletes only the exact
 * physical aliases this instance created; there is no global alias sweep and
 * no production-prefix match. Store files live in a unique subdirectory of the
 * app-private `filesDir` and are removed in [tearDown].
 */
@RunWith(AndroidJUnit4::class)
class EncryptedStoreInstrumentedTest {

    private lateinit var context: Context
    private lateinit var backend: IsolatedTestBackend
    private lateinit var keystore: KeystoreService
    private lateinit var store: EncryptedStore
    private lateinit var root: File

    @Before
    fun setUp() {
        context = InstrumentationRegistry.getInstrumentation().targetContext
        backend = IsolatedTestBackend()
        keystore = KeystoreService(backend, strongBoxSupported = false)
        root = File(context.filesDir, "t026-test-" + UUID.randomUUID())
        store = EncryptedStore(root, keystore)
        store.ensureLayout()
        assertNull(
            "no master alias may exist",
            backend.physicalAliasIfPresent("feldexa.master.v1"),
        )
    }

    @After
    fun tearDown() {
        runCatching { root.deleteRecursively() }
        backend.deleteCreatedTestAliases()
    }

    @Test
    fun realKeystoreCreateSaveLoadAndReadBack() {
        val documentId = newId()
        val source = "%PDF-1.7 real-keystore source".toByteArray()
        val created = store.createDocument(
            documentId,
            meta("Echtes Dokument"),
            newId(),
            source,
            newId(),
            revision(1),
        )
        assertTrue(created.readBackVerified)

        val secondRevision = newId()
        val receipt = store.saveRevision(
            documentId,
            secondRevision,
            revision(2),
            RevisionKindWire.EXPLICIT,
            created.revisionId,
        )
        assertTrue(receipt.readBackVerified)
        assertEquals(36, secondRevision.length)

        val loaded = store.loadDocument(documentId)
        assertArrayEquals(source, loaded.sourceBytes)
        assertArrayEquals(revision(2), loaded.revisionPlaintext)
        assertEquals(secondRevision, loaded.head.revisionId)
        assertEquals("Echtes Dokument", titleOf(loaded.metaPlaintext))
        assertTrue(backend.hasTestAlias(AggregateRef(AggregateKind.DOCUMENT, documentId)))
        assertNull(backend.physicalAliasIfPresent("feldexa.master.v1"))
    }

    @Test
    fun boundarySizesRoundTripOnRealKeystore() {
        for (size in listOf(1, 65_535, 65_536, 1_048_577)) {
            val documentId = newId()
            val source = ByteArray(size) { (it * 17).toByte() }
            store.createDocument(
                documentId,
                meta("Groesse $size"),
                newId(),
                source,
                newId(),
                revision(size),
            )
            assertArrayEquals(
                "size $size",
                source,
                store.loadDocument(documentId).sourceBytes,
            )
        }
    }

    @Test
    fun tamperedCiphertextIsSave003OnDevice() {
        val created = createDocument()
        val revisionFile = File(
            root,
            "docs/${created.aggregateId}/rev/${created.revisionId}.fx1",
        )
        val bytes = revisionFile.readBytes()
        bytes[160] = (bytes[160].toInt() xor 0x01).toByte()
        revisionFile.writeBytes(bytes)

        val failure = assertThrows(CorruptDataException::class.java) {
            store.loadDocument(created.aggregateId)
        }
        assertEquals("SAVE-003", failure.code)
    }

    @Test
    fun lostAggregateKeyIsSave002WhileSiblingLoads() {
        val first = createDocument("Erstes")
        val second = createDocument("Zweites")
        backend.deleteTestAlias(AggregateRef(AggregateKind.DOCUMENT, first.aggregateId))

        val failure = assertThrows(KeyUnavailableException::class.java) {
            store.loadDocument(first.aggregateId)
        }
        assertEquals("SAVE-002", failure.code)
        assertEquals(
            "Zweites",
            titleOf(store.loadDocument(second.aggregateId).metaPlaintext),
        )
    }

    @Test
    fun everyAliasLostIsGlobalSave008() {
        val first = createDocument()
        val second = createDocument()
        backend.deleteTestAlias(AggregateRef(AggregateKind.DOCUMENT, first.aggregateId))
        backend.deleteTestAlias(AggregateRef(AggregateKind.DOCUMENT, second.aggregateId))

        val failure = assertThrows(KeystoreUnavailableException::class.java) {
            store.loadDocument(first.aggregateId)
        }
        assertEquals("SAVE-008", failure.code)
    }

    @Test
    fun deleteRemovesObjectsAndAliasAndSiblingSurvives() {
        val first = createDocument(title = "Alpha")
        val second = createDocument(title = "Beta")

        val receipt = store.delete(
            AggregateKind.DOCUMENT,
            first.aggregateId,
            DeleteConfirmation(acknowledged = true, title = "Alpha"),
            notReadableTitle = "Nicht lesbar",
        )

        assertTrue(receipt.directoryDeleted)
        assertTrue(receipt.aliasDeleted)
        assertFalse(File(root, "docs/${first.aggregateId}").exists())
        assertFalse(backend.hasTestAlias(AggregateRef(AggregateKind.DOCUMENT, first.aggregateId)))
        assertEquals("Beta", titleOf(store.loadDocument(second.aggregateId).metaPlaintext))
    }

    @Test
    fun startupSweepRemovesStaleTempAndOrphanAlias() {
        val orphanId = newId()
        keystore.createAggregateKey(AggregateRef(AggregateKind.DOCUMENT, orphanId))
        val stale = File(root, "tmp/" + newId() + ".part").apply {
            writeBytes(byteArrayOf(1, 2, 3))
            setLastModified(System.currentTimeMillis() - EncryptedStore.STALE_TEMP_MS - 1_000)
        }

        val report = store.startupRecovery()

        assertTrue(report.tempEntriesRemoved >= 1)
        assertTrue(report.orphanAliasesRemoved >= 1)
        assertFalse(stale.exists())
        assertFalse(backend.hasTestAlias(AggregateRef(AggregateKind.DOCUMENT, orphanId)))
    }

    @Test
    fun missingHeadFallsBackToNewestRevisionOnDevice() {
        val created = createDocument()
        val second = newId()
        store.saveRevision(
            created.aggregateId,
            second,
            revision(2),
            RevisionKindWire.AUTOSAVE,
            created.revisionId,
        )
        val firstFile = File(
            root,
            "docs/${created.aggregateId}/rev/${created.revisionId}.fx1",
        )
        val secondFile = File(root, "docs/${created.aggregateId}/rev/$second.fx1")
        val reference = System.currentTimeMillis()
        firstFile.setLastModified(reference - 2_000)
        secondFile.setLastModified(reference - 1_000)
        val head = File(root, "docs/${created.aggregateId}/head.fx1")
        head.delete()

        val stamp = store.recoveryStamp(AggregateKind.DOCUMENT, created.aggregateId)

        assertTrue(stamp.fellBackToOlderRevision)
        assertTrue(stamp.readable)
        assertEquals(second, stamp.verifiedRevisionId)
        assertEquals(second, store.loadDocument(created.aggregateId).head.revisionId)
    }

    @Test
    fun injectedFsyncFailureLeavesTheOldHeadReadable() {
        val created = createDocument()
        val faultStore = EncryptedStore(
            root = root,
            keystore = keystore,
            faultInjector = StoreFaultInjector { point, _ ->
                if (point == StoreFaultPoint.STAGE_FSYNC) {
                    throw IOException("injected fsync failure")
                }
            },
        )

        val failure = assertThrows(StorageWriteException::class.java) {
            faultStore.saveRevision(
                created.aggregateId,
                newId(),
                revision(2),
                RevisionKindWire.AUTOSAVE,
                created.revisionId,
            )
        }
        assertEquals("SAVE-003", failure.code)
        assertEquals(created.revisionId, store.loadDocument(created.aggregateId).head.revisionId)
    }

    @Test
    fun noPlaintextResidueInTheAggregateDirectory() {
        val marker = "PDF-DEVICE-SECRET"
        val created = store.createDocument(
            newId(),
            meta("GEHEIM"),
            newId(),
            "%PDF-1.7 $marker".toByteArray(),
            newId(),
            revision(1),
        )

        val aggregate = File(root, "docs/${created.aggregateId}")
        for (file in aggregate.walkTopDown().filter { it.isFile }) {
            val text = String(file.readBytes(), Charsets.ISO_8859_1)
            assertFalse("plaintext marker in ${file.name}", text.contains(marker))
            assertFalse("plaintext title in ${file.name}", text.contains("GEHEIM"))
            assertFalse("PDF magic in ${file.name}", text.contains("%PDF-"))
        }
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private fun createDocument(title: String = "Dokument"): CreateReceipt {
        val documentId = newId()
        return store.createDocument(
            documentId,
            meta(title),
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

    private fun titleOf(meta: ByteArray): String? {
        val parsed = CanonicalJson.parse(meta) as? Map<*, *> ?: return null
        return parsed["title"] as? String
    }

    /**
     * Test-only Keystore backend that maps every logical aggregate alias into a
     * unique `feldexa.test.v1.<runToken>.` namespace while delegating to the
     * real production [AndroidKeystoreBackend]. Cleanup is exact-only.
     */
    private class IsolatedTestBackend : KeystoreBackend {

        private val delegate = AndroidKeystoreBackend()
        private val namespace =
            NAMESPACE_PREFIX + UUID.randomUUID().toString() + "."
        private val createdAliases = LinkedHashSet<String>()
        private val logicalByPhysical = HashMap<String, String>()

        fun physicalAlias(alias: String): String = namespace + alias

        fun physicalAliasIfPresent(alias: String): String? =
            physicalAlias(alias).takeIf { delegate.containsAlias(it) }

        fun hasTestAlias(ref: AggregateRef): Boolean =
            delegate.containsAlias(physicalAlias(ref.alias))

        override fun providerAvailable(): Boolean = delegate.providerAvailable()

        override fun containsAlias(alias: String): Boolean =
            delegate.containsAlias(physicalAlias(alias))

        override fun listAliases(): Set<String> =
            createdAliases.mapNotNull { physical ->
                logicalByPhysical[physical]?.takeIf {
                    delegate.containsAlias(physical)
                }
            }.toSet()

        override fun isKeyUsable(alias: String): Boolean =
            delegate.isKeyUsable(physicalAlias(alias))

        override fun generateAesKey(alias: String, strongBox: Boolean) {
            val physical = physicalAlias(alias)
            createdAliases += physical
            logicalByPhysical[physical] = alias
            delegate.generateAesKey(physical, strongBox)
        }

        override fun deleteAlias(alias: String): Boolean {
            val physical = physicalAlias(alias)
            val deleted = delegate.deleteAlias(physical)
            if (deleted) {
                createdAliases.remove(physical)
                logicalByPhysical.remove(physical)
            }
            return deleted
        }

        fun deleteTestAlias(ref: AggregateRef): Boolean {
            val physical = physicalAlias(ref.alias)
            val deleted = delegate.deleteAlias(physical)
            if (deleted) {
                createdAliases.remove(physical)
                logicalByPhysical.remove(physical)
            }
            return deleted
        }

        override fun encrypt(
            alias: String,
            aad: ByteArray,
            plaintext: ByteArray,
        ): WrappedDek = delegate.encrypt(physicalAlias(alias), aad, plaintext)

        override fun decrypt(
            alias: String,
            iv: ByteArray,
            aad: ByteArray,
            ciphertext: ByteArray,
        ): ByteArray = delegate.decrypt(physicalAlias(alias), iv, aad, ciphertext)

        fun deleteCreatedTestAliases() {
            for (physical in createdAliases.toList()) {
                if (!physical.startsWith(NAMESPACE_PREFIX)) continue
                if (delegate.containsAlias(physical)) {
                    runCatching { delegate.deleteAlias(physical) }
                }
            }
            createdAliases.clear()
            logicalByPhysical.clear()
        }

        private companion object {
            const val NAMESPACE_PREFIX: String = "feldexa.test.v1."
        }
    }
}
