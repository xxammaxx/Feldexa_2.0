package de.feldexa.app.storage

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong
import java.util.zip.CRC32
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * T026 JVM tests for the `FXC1` container, the atomic commit protocol, the
 * per-aggregate KEK binding, aggregate deletion, and startup recovery/sweep.
 *
 * These are host tests with real AES-GCM and a real filesystem; they do not
 * claim Android Keystore or emulator acceptance. The Pixel 7 / API 35
 * instrumentation suite covers that layer.
 */
class EncryptedStoreTest {

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
    // Round-trip and container format
    // ------------------------------------------------------------------

    @Test
    fun createDocumentRoundTripAndReadBack() {
        val documentId = newId()
        val source = "%PDF-1.7 synthetic source".toByteArray()
        val receipt = store.createDocument(
            documentId = documentId,
            metaJson = meta("Dokument"),
            sourceId = newId(),
            sourceBytes = source,
            revisionId = newId(),
            revisionJson = revision(1),
        )

        assertTrue(receipt.readBackVerified)
        assertEquals(AggregateKind.DOCUMENT, receipt.aggregateKind)
        val loaded = store.loadDocument(documentId)
        assertArrayEquals(source, loaded.sourceBytes)
        assertArrayEquals(revision(1), loaded.revisionPlaintext)
        assertEquals("Dokument", titleOf(loaded.metaPlaintext))
        assertEquals(receipt.revisionId, loaded.head.revisionId)
        assertFalse(loaded.fellBackToOlderRevision)
    }

    @Test
    fun emptyObjectIsAValidContainer() {
        val ref = AggregateRef(AggregateKind.DOCUMENT, newId())
        keystore.createAggregateKey(ref)
        val objectId = newId()
        val obj = RevisionObject(ref, objectId)

        store.commitObjectForTest(obj, ByteArray(0))

        assertArrayEquals(ByteArray(0), store.readObjectForTest(obj))
        val header = headerOf(docFile(ref.id, "rev/$objectId.fx1"))
        assertEquals(0, header.chunkCount)
        assertEquals(0L, header.plaintextLength)
        assertEquals(160L, docFile(ref.id, "rev/$objectId.fx1").length())
    }

    @Test
    fun boundaryPlaintextSizesRoundTrip() {
        val sizes = listOf(1, 65_535, 65_536, 1_048_575, 1_048_576, 1_048_577)
        for (size in sizes) {
            val documentId = newId()
            val source = ByteArray(size) { (it * 31).toByte() }
            store.createDocument(
                documentId,
                meta("Size $size"),
                newId(),
                source,
                newId(),
                revision(size),
            )
            assertArrayEquals(
                "source size $size",
                source,
                store.loadDocument(documentId).sourceBytes,
            )
        }
    }

    @Test
    fun headerMatchesTheContractOffsets() {
        val ref = AggregateRef(AggregateKind.DOCUMENT, newId())
        keystore.createAggregateKey(ref)
        val revisionId = newId()
        val plaintext = ByteArray(100) { it.toByte() }
        val obj = RevisionObject(ref, revisionId)
        store.commitObjectForTest(obj, plaintext)

        val file = docFile(ref.id, "rev/$revisionId.fx1")
        val bytes = file.readBytes()
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)

        assertEquals("FXC1", String(bytes.copyOfRange(0, 4), Charsets.US_ASCII))
        assertEquals(1, buffer.getShort(4).toInt())
        assertEquals(1, buffer.getShort(6).toInt())
        assertEquals(1, buffer.get(8).toInt())
        assertEquals(ObjectKind.REVISION.wire, buffer.get(9).toInt())
        assertEquals(0, buffer.getShort(10).toInt())
        assertEquals(1_048_576, buffer.getInt(12))
        assertEquals(100L, buffer.getLong(16))
        assertEquals(1, buffer.getInt(24))
        assertEquals(12, buffer.getShort(40).toInt())
        assertEquals(48, buffer.getShort(54).toInt())
        assertEquals(32, bytes.copyOfRange(104, 136).size)
        assertEquals(20, bytes.copyOfRange(136, 156).size)
        assertEquals(160, bytes.size - 100 - 16)
        assertEquals(bytes.copyOfRange(0, 156).crc32(), buffer.getInt(156))
    }

    @Test
    fun everyObjectGetsAFreshNonceAndWrapIv() {
        val ref = AggregateRef(AggregateKind.DOCUMENT, newId())
        keystore.createAggregateKey(ref)
        val firstId = newId()
        val secondId = newId()
        store.commitObjectForTest(RevisionObject(ref, firstId), revision(1))
        store.commitObjectForTest(RevisionObject(ref, secondId), revision(1))

        val first = headerOf(docFile(ref.id, "rev/$firstId.fx1"))
        val second = headerOf(docFile(ref.id, "rev/$secondId.fx1"))
        assertFalse(first.noncePrefix.contentEquals(second.noncePrefix))
        assertFalse(first.wrapIv.contentEquals(second.wrapIv))
    }

    @Test
    fun metadataObjectsUseTheSixtyFourKiBChunkSize() {
        val ref = AggregateRef(AggregateKind.DOCUMENT, newId())
        keystore.createAggregateKey(ref)
        val obj = MetaObject(ref)
        val plaintext = ByteArray(200_000) { (it % 251).toByte() }
        store.commitObjectForTest(obj, plaintext)

        val bytes = docFile(ref.id, "meta.fx1").readBytes()
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
        assertEquals(EncryptedStore.META_CHUNK_SIZE, buffer.getInt(12))
        assertEquals(4, buffer.getInt(24))
        assertArrayEquals(plaintext, store.readObjectForTest(obj))
    }

    // ------------------------------------------------------------------
    // Header validation and tamper
    // ------------------------------------------------------------------

    @Test
    fun headerCrcMismatchIsSave003() {
        val created = createDoc()
        val file = docFile(created.aggregateId, "rev/${created.revisionId}.fx1")
        flip(file, 20)
        assertFailure("SAVE-003") { store.loadDocument(created.aggregateId) }
    }

    @Test
    fun unsupportedVersionIsSave005() {
        val ref = AggregateRef(AggregateKind.DOCUMENT, newId())
        keystore.createAggregateKey(ref)
        val revisionId = newId()
        val obj = RevisionObject(ref, revisionId)
        store.commitObjectForTest(obj, revision(1))
        patchShort(docFile(ref.id, "rev/$revisionId.fx1"), 4, 2)
        assertFailure("SAVE-005") { store.readObjectForTest(obj) }
    }

    @Test
    fun unknownFlagsAreCorrupt() {
        val obj = committedRevision()
        patchShort(obj.file, 6, 3)
        assertCorrupt { store.readObjectForTest(obj.objectForTest) }
    }

    @Test
    fun nonZeroReservedBytesAreCorrupt() {
        val obj = committedRevision()
        patchShort(obj.file, 10, 1)
        assertCorrupt { store.readObjectForTest(obj.objectForTest) }
    }

    @Test
    fun wrongChunkSizeIsCorrupt() {
        val obj = committedRevision()
        patchInt(obj.file, 12, 1234)
        assertCorrupt { store.readObjectForTest(obj.objectForTest) }
    }

    @Test
    fun wrongWrappedKeyLengthIsCorrupt() {
        val obj = committedRevision()
        patchShort(obj.file, 54, 47)
        assertCorrupt { store.readObjectForTest(obj.objectForTest) }
    }

    @Test
    fun chunkCountMismatchIsCorrupt() {
        val obj = committedRevision()
        patchInt(obj.file, 24, 3)
        assertCorrupt { store.readObjectForTest(obj.objectForTest) }
    }

    @Test
    fun changedPlaintextHashIsSave003() {
        val obj = committedRevision()
        flip(obj.file, 104)
        recomputeCrc(obj.file)
        assertFailure("SAVE-003") { store.readObjectForTest(obj.objectForTest) }
    }

    @Test
    fun changedFileIdIsCorrupt() {
        val obj = committedRevision()
        flip(obj.file, 136)
        recomputeCrc(obj.file)
        assertCorrupt { store.readObjectForTest(obj.objectForTest) }
    }

    @Test
    fun tamperedCiphertextIsSave003() {
        val obj = committedRevision()
        flip(obj.file, 160)
        assertFailure("SAVE-003") { store.readObjectForTest(obj.objectForTest) }
    }

    @Test
    fun tamperedSourceCiphertextIsSave003() {
        val created = createDoc()
        val sourceFile = File(storeRoot, "docs/${created.aggregateId}/src/${created.sourceId}.fxc")
        flip(sourceFile, 160)
        assertFailure("SAVE-003") { store.loadDocument(created.aggregateId) }
    }

    @Test
    fun truncatedFinalChunkIsSave003() {
        val obj = committedRevision()
        val bytes = obj.file.readBytes()
        obj.file.writeBytes(bytes.copyOf(bytes.size - 1))
        assertFailure("SAVE-003") { store.readObjectForTest(obj.objectForTest) }
    }

    @Test
    fun reorderedChunksAreSave003() {
        val ref = AggregateRef(AggregateKind.DOCUMENT, newId())
        keystore.createAggregateKey(ref)
        val revisionId = newId()
        val obj = RevisionObject(ref, revisionId)
        store.commitObjectForTest(obj, ByteArray(1_048_576 + 100) { it.toByte() })
        val file = docFile(ref.id, "rev/$revisionId.fx1")
        val bytes = file.readBytes()
        val first = bytes.copyOfRange(160, 160 + 1_048_576 + 16)
        val second = bytes.copyOfRange(160 + 1_048_576 + 16, bytes.size)
        val swapped = ByteArray(bytes.size)
        System.arraycopy(bytes, 0, swapped, 0, 160)
        System.arraycopy(second, 0, swapped, 160, second.size)
        System.arraycopy(first, 0, swapped, 160 + second.size, first.size)
        file.writeBytes(swapped)
        assertFailure("SAVE-003") { store.readObjectForTest(obj) }
    }

    @Test
    fun splicedChunkFromAnotherObjectIsSave003() {
        val ref = AggregateRef(AggregateKind.DOCUMENT, newId())
        keystore.createAggregateKey(ref)
        val firstId = newId()
        val secondId = newId()
        val first = RevisionObject(ref, firstId)
        val second = RevisionObject(ref, secondId)
        store.commitObjectForTest(first, ByteArray(4096) { 1 })
        store.commitObjectForTest(second, ByteArray(4096) { 2 })

        val firstFile = docFile(ref.id, "rev/$firstId.fx1")
        val secondFile = docFile(ref.id, "rev/$secondId.fx1")
        val bytes = firstFile.readBytes()
        val donor = secondFile.readBytes()
        System.arraycopy(donor, 160, bytes, 160, donor.size - 160)
        firstFile.writeBytes(bytes)
        assertFailure("SAVE-003") { store.readObjectForTest(first) }
    }

    // ------------------------------------------------------------------
    // Per-aggregate keys
    // ------------------------------------------------------------------

    @Test
    fun perAggregateKekBindsObjectsToTheirAggregate() {
        val first = createDoc(title = "Erstes")
        val second = createDoc(title = "Zweites")
        val firstRevision = docFile(first.aggregateId, "rev/${first.revisionId}.fx1")
        val secondRevision = docFile(second.aggregateId, "rev/${first.revisionId}.fx1")

        secondRevision.writeBytes(firstRevision.readBytes())

        assertFailure("SAVE-003") {
            store.readObjectForTest(RevisionObject(doc(second.aggregateId), first.revisionId))
        }
        assertEquals("Erstes", titleOf(store.loadDocument(first.aggregateId).metaPlaintext))
        assertEquals("Zweites", titleOf(store.loadDocument(second.aggregateId).metaPlaintext))
    }

    @Test
    fun oneLostAggregateKeyIsSave002WhileSiblingLoads() {
        val first = createDoc(title = "Erstes")
        val second = createDoc(title = "Zweites")
        backend.deleteAlias(doc(first.aggregateId).alias)

        assertFailure("SAVE-002") { store.loadDocument(first.aggregateId) }
        assertEquals("Zweites", titleOf(store.loadDocument(second.aggregateId).metaPlaintext))
    }

    @Test
    fun noUsableAggregateKeyIsGlobalSave008() {
        val first = createDoc()
        val second = createDoc()
        backend.deleteAlias(doc(first.aggregateId).alias)
        backend.deleteAlias(doc(second.aggregateId).alias)

        assertFailure("SAVE-008") { store.loadDocument(first.aggregateId) }
    }

    @Test
    fun providerOutageIsSave008AndLeavesNoVisibleAggregate() {
        val documentId = newId()
        backend.providerAvailableFlag = false

        assertFailure("SAVE-008") {
            store.createDocument(
                documentId,
                meta("Nicht sichtbar"),
                newId(),
                "%PDF-1.7".toByteArray(),
                newId(),
                revision(1),
            )
        }

        assertFalse(File(storeRoot, "docs/$documentId").exists())
        assertTrue(backend.keys.isEmpty())
        assertTrue(store.list(AggregateKind.DOCUMENT).isEmpty())
    }

    // ------------------------------------------------------------------
    // Commit protocol
    // ------------------------------------------------------------------

    @Test
    fun staleExpectedHeadIsSave006AndOldHeadSurvives() {
        val created = createDoc()
        val secondRevision = newId()
        store.saveRevision(
            created.aggregateId,
            secondRevision,
            revision(2),
            RevisionKindWire.AUTOSAVE,
            expectedHead = created.revisionId,
        )

        assertFailure("SAVE-006") {
            store.saveRevision(
                created.aggregateId,
                newId(),
                revision(3),
                RevisionKindWire.AUTOSAVE,
                expectedHead = created.revisionId,
            )
        }

        assertEquals(secondRevision, store.loadDocument(created.aggregateId).head.revisionId)
    }

    @Test
    fun successfulSaveCleansTemporaryFilesAndUpdatesStamp() {
        val created = createDoc()
        val secondRevision = newId()
        val receipt = store.saveRevision(
            created.aggregateId,
            secondRevision,
            revision(2),
            RevisionKindWire.EXPLICIT,
            expectedHead = created.revisionId,
        )

        assertEquals(secondRevision, receipt.revisionId)
        assertEquals(created.revisionId, receipt.parentRevisionId)
        assertTrue(receipt.readBackVerified)
        assertTrue(File(storeRoot, "tmp").listFiles()!!.isEmpty())

        val stamp = store.recoveryStamp(AggregateKind.DOCUMENT, created.aggregateId)
        assertEquals(secondRevision, stamp.verifiedRevisionId)
        assertFalse(stamp.fellBackToOlderRevision)
        assertFalse(stamp.headCorrupt)
    }

    // ------------------------------------------------------------------
    // Deletion
    // ------------------------------------------------------------------

    @Test
    fun deleteRemovesObjectsThenAliasAndSiblingSurvives() {
        val first = createDoc(title = "Alpha")
        val second = createDoc(title = "Beta")
        val receipt = store.delete(
            AggregateKind.DOCUMENT,
            first.aggregateId,
            DeleteConfirmation(acknowledged = true, title = "Alpha"),
            notReadableTitle = "Nicht lesbar",
        )

        assertTrue(receipt.directoryDeleted)
        assertTrue(receipt.aliasDeleted)
        assertTrue(receipt.objectsDeleted > 0)
        assertFalse(File(storeRoot, "docs/${first.aggregateId}").exists())
        assertFalse(backend.keys.containsKey(doc(first.aggregateId).alias))
        assertTrue(backend.keys.containsKey(doc(second.aggregateId).alias))
        assertEquals("Beta", titleOf(store.loadDocument(second.aggregateId).metaPlaintext))
    }

    @Test
    fun failedAliasDeleteLeavesOnlyTheOrphanForTheStartupSweep() {
        val created = createDoc(title = "Alpha")
        backend.failDeletes = true

        val receipt = store.delete(
            AggregateKind.DOCUMENT,
            created.aggregateId,
            DeleteConfirmation(acknowledged = true, title = "Alpha"),
            notReadableTitle = "Nicht lesbar",
        )

        assertTrue(receipt.directoryDeleted)
        assertFalse(receipt.aliasDeleted)
        assertTrue(receipt.orphanAliasLeft)
        assertFalse(File(storeRoot, "docs/${created.aggregateId}").exists())

        backend.failDeletes = false
        val report = store.startupRecovery()
        assertEquals(1, report.orphanAliasesRemoved)
        assertTrue(backend.keys.isEmpty())
    }

    @Test
    fun deleteRejectsAWrongTitleWithoutTouchingData() {
        val created = createDoc(title = "Alpha")
        assertThrows(PlatformSecurityException::class.java) {
            store.delete(
                AggregateKind.DOCUMENT,
                created.aggregateId,
                DeleteConfirmation(acknowledged = true, title = "Beta"),
                notReadableTitle = "Nicht lesbar",
            )
        }
        assertTrue(File(storeRoot, "docs/${created.aggregateId}/meta.fx1").exists())
    }

    @Test
    fun unreadableAggregateMatchesThePlaceholderAndStaysDeletable() {
        val created = createDoc(title = "Alpha")
        backend.deleteAlias(doc(created.aggregateId).alias)

        val receipt = store.delete(
            AggregateKind.DOCUMENT,
            created.aggregateId,
            DeleteConfirmation(acknowledged = true, title = "Nicht lesbar"),
            notReadableTitle = "Nicht lesbar",
        )

        assertTrue(receipt.directoryDeleted)
        assertFalse(File(storeRoot, "docs/${created.aggregateId}").exists())
    }

    // ------------------------------------------------------------------
    // Startup recovery and sweep
    // ------------------------------------------------------------------

    @Test
    fun staleAndUnknownTempEntriesAreSwept() {
        val tmp = File(storeRoot, "tmp")
        val recentKnown = File(tmp, newId() + ".part").apply { writeBytes(byteArrayOf(1)) }
        val staleKnown = File(tmp, newId() + ".head").apply { writeBytes(byteArrayOf(2)) }
        val unknown = File(tmp, "not-a-transaction.tmp").apply { writeBytes(byteArrayOf(3)) }
        val staleUnknown = File(tmp, "junk.bin").apply { writeBytes(byteArrayOf(4)) }
        staleKnown.setLastModified(now.get() - EncryptedStore.STALE_TEMP_MS - 1_000)
        staleUnknown.setLastModified(now.get() - EncryptedStore.STALE_TEMP_MS - 1_000)

        val report = store.startupRecovery()

        assertEquals(3, report.tempEntriesRemoved)
        assertTrue(recentKnown.exists())
        assertFalse(staleKnown.exists())
        assertFalse(unknown.exists())
        assertFalse(staleUnknown.exists())
    }

    @Test
    fun incompleteImportIsRemovedAndItsOrphanAliasSwept() {
        val documentId = newId()
        val aggregate = File(storeRoot, "docs/$documentId")
        File(aggregate, "src").mkdirs()
        File(aggregate, "rev").mkdirs()
        File(aggregate, "src/${newId()}.fxc").writeBytes(byteArrayOf(1, 2, 3))
        keystore.createAggregateKey(doc(documentId))

        val report = store.startupRecovery()

        assertEquals(1, report.incompleteAggregatesRemoved)
        assertEquals(1, report.orphanAliasesRemoved)
        assertFalse(aggregate.exists())
        assertTrue(backend.keys.isEmpty())
    }

    @Test
    fun orphanAliasWithoutDirectoryIsSweptButVisibleAliasIsRetained() {
        val orphanId = newId()
        keystore.createAggregateKey(doc(orphanId))
        val visible = createDoc()

        val report = store.startupRecovery()

        assertEquals(1, report.orphanAliasesRemoved)
        assertFalse(backend.keys.containsKey(doc(orphanId).alias))
        assertTrue(backend.keys.containsKey(doc(visible.aggregateId).alias))
    }

    @Test
    fun missingHeadFallsBackToTheNewestVerifiedRevision() {
        val created = createDoc(revisionKind = RevisionKindWire.AUTOSAVE)
        val second = newId()
        val third = newId()
        store.saveRevision(
            created.aggregateId,
            second,
            revision(2),
            RevisionKindWire.AUTOSAVE,
            created.revisionId,
        )
        store.saveRevision(
            created.aggregateId,
            third,
            revision(3),
            RevisionKindWire.EXPLICIT,
            second,
        )
        setMtime(docFile(created.aggregateId, "rev/${created.revisionId}.fx1"), -3_000)
        setMtime(docFile(created.aggregateId, "rev/$second.fx1"), -2_000)
        setMtime(docFile(created.aggregateId, "rev/$third.fx1"), -1_000)
        docFile(created.aggregateId, "head.fx1").delete()

        val stamp = store.recoveryStamp(AggregateKind.DOCUMENT, created.aggregateId)

        assertTrue(stamp.fellBackToOlderRevision)
        assertTrue(stamp.headCorrupt)
        assertTrue(stamp.readable)
        assertEquals(third, stamp.verifiedRevisionId)
        assertEquals(third, store.loadDocument(created.aggregateId).head.revisionId)
    }

    @Test
    fun corruptNewestRevisionFallsBackToAnOlderVerifiedRevision() {
        val created = createDoc()
        val second = newId()
        store.saveRevision(
            created.aggregateId,
            second,
            revision(2),
            RevisionKindWire.AUTOSAVE,
            created.revisionId,
        )
        val secondFile = docFile(created.aggregateId, "rev/$second.fx1")
        flip(secondFile, 160)
        setMtime(docFile(created.aggregateId, "rev/${created.revisionId}.fx1"), -2_000)
        setMtime(secondFile, -1_000)

        val stamp = store.recoveryStamp(AggregateKind.DOCUMENT, created.aggregateId)

        assertTrue(stamp.fellBackToOlderRevision)
        assertEquals(created.revisionId, stamp.verifiedRevisionId)
    }

    @Test
    fun noVerifiableRevisionIsUnreadableButNeverDeleted() {
        val created = createDoc()
        flip(docFile(created.aggregateId, "rev/${created.revisionId}.fx1"), 160)
        docFile(created.aggregateId, "head.fx1").delete()

        val stamp = store.recoveryStamp(AggregateKind.DOCUMENT, created.aggregateId)

        assertFalse(stamp.readable)
        assertEquals("SAVE-003", stamp.unreadableReasonCode)
        assertTrue(File(storeRoot, "docs/${created.aggregateId}").exists())
        assertFailure("SAVE-003") { store.loadDocument(created.aggregateId) }
    }

    @Test
    fun missingMetaWithAnotherEntryIsUnreadableAndKept() {
        val created = createDoc()
        val aggregate = File(storeRoot, "docs/${created.aggregateId}")
        File(aggregate, "meta.fx1").delete()
        val sigDir = File(aggregate, "sig").apply { mkdirs() }
        File(sigDir, "${newId()}.fxs").writeBytes(byteArrayOf(1, 2, 3))

        val stamp = store.recoveryStamp(AggregateKind.DOCUMENT, created.aggregateId)

        assertFalse(stamp.readable)
        assertEquals("SAVE-003", stamp.unreadableReasonCode)
        assertTrue(aggregate.exists())
    }

    @Test
    fun listReportsSave002PlaceholderAndKeepsSiblingReadable() {
        val first = createDoc(title = "Erstes")
        val second = createDoc(title = "Zweites")
        backend.deleteAlias(doc(first.aggregateId).alias)

        val listed = store.list(AggregateKind.DOCUMENT).associateBy { it.aggregateId }

        assertFalse(listed.getValue(first.aggregateId).readable)
        assertEquals("SAVE-002", listed.getValue(first.aggregateId).unreadableReasonCode)
        assertNull(listed.getValue(first.aggregateId).metaPlaintext)
        assertTrue(listed.getValue(second.aggregateId).readable)
        assertEquals("Zweites", titleOf(listed.getValue(second.aggregateId).metaPlaintext!!))
    }

    @Test
    fun listReportsGlobalSave008WhenEveryAliasIsGone() {
        val first = createDoc()
        val second = createDoc()
        backend.deleteAlias(doc(first.aggregateId).alias)
        backend.deleteAlias(doc(second.aggregateId).alias)

        val listed = store.list(AggregateKind.DOCUMENT)

        assertEquals(2, listed.size)
        assertTrue(listed.all { !it.readable && it.unreadableReasonCode == "SAVE-008" })
    }

    @Test
    fun twoSourceObjectsMakeTheAggregateUnreadable() {
        val created = createDoc()
        val srcDir = File(storeRoot, "docs/${created.aggregateId}/src")
        File(srcDir, "${newId()}.fxc").writeBytes(byteArrayOf(9, 9, 9))

        assertFailure("SAVE-003") { store.loadDocument(created.aggregateId) }
    }

    @Test
    fun noPlaintextResidueOutsideTheContainer() {
        val marker = "PDF-SECRET-MARKER"
        val source = "%PDF-1.7 $marker".toByteArray()
        val documentId = newId()
        store.createDocument(
            documentId,
            meta("GEHEIM"),
            newId(),
            source,
            newId(),
            revision(1),
        )

        val root = File(storeRoot, "docs/$documentId")
        val plaintextMarkers = listOf(marker, "GEHEIM", "%PDF-")
        for (file in root.walkTopDown().filter { it.isFile }) {
            val text = String(file.readBytes(), Charsets.ISO_8859_1)
            for (needle in plaintextMarkers) {
                assertFalse(
                    "plaintext '$needle' must not appear in ${file.name}",
                    text.contains(needle),
                )
            }
        }
    }

    @Test
    fun diagnosticsEventHasCountsOnly() {
        val created = createDoc()
        store.startupRecovery()

        val event = File(storeRoot, "diagnostics/redacted.jsonl").readText()
        assertTrue(event.contains("\"tempRemoved\""))
        assertTrue(event.contains("\"orphanAliasesRemoved\""))
        assertFalse(event.contains(created.aggregateId))
        assertFalse(event.contains("Dokument"))
        assertFalse(event.contains("title"))
    }

    @Test
    fun staleUnreferencedSignatureIsSweptAndReferencedKept() {
        val created = createDoc()
        val oldAsset = newId()
        val referencedAsset = newId()
        store.writeSignature(created.aggregateId, oldAsset, byteArrayOf(1, 2, 3))
        store.writeSignature(created.aggregateId, referencedAsset, byteArrayOf(4, 5, 6))
        val sigDir = File(storeRoot, "docs/${created.aggregateId}/sig")
        File(sigDir, "$oldAsset.fxs").setLastModified(now.get() - EncryptedStore.STALE_TEMP_MS - 1_000)
        File(sigDir, "$referencedAsset.fxs").setLastModified(now.get() - EncryptedStore.STALE_TEMP_MS - 1_000)

        val removed = store.sweepUnreferencedSignatures { _, assetId ->
            assetId == referencedAsset
        }

        assertEquals(1, removed)
        assertFalse(File(sigDir, "$oldAsset.fxs").exists())
        assertTrue(File(sigDir, "$referencedAsset.fxs").exists())
    }

    @Test
    fun startupRecoverySurvivesAProviderOutageAndSkipsTheAliasSweep() {
        createDoc()
        backend.providerAvailableFlag = false

        val report = store.startupRecovery()

        assertTrue(report.aliasSweepSkipped)
        assertEquals(1, report.unreadableAggregates)
    }

    @Test
    fun creatingADuplicateVisibleAggregateIsSave006() {
        val created = createDoc()
        assertFailure("SAVE-006") {
            store.createDocument(
                created.aggregateId,
                meta("Doppelt"),
                newId(),
                "%PDF-1.7".toByteArray(),
                newId(),
                revision(1),
            )
        }
    }

    @Test
    fun invalidAggregateIdIsRejectedBeforeAnyIo() {
        assertThrows(PlatformSecurityException::class.java) {
            store.createDocument(
                "not-a-uuid",
                meta("Ungueltig"),
                newId(),
                "%PDF-1.7".toByteArray(),
                newId(),
                revision(1),
            )
        }
        assertFalse(File(storeRoot, "docs/not-a-uuid").exists())
    }

    @Test
    fun oversizedSignatureIsSave007() {
        val created = createDoc()
        assertFailure("SAVE-007") {
            store.writeSignature(
                created.aggregateId,
                newId(),
                ByteArray((EncryptedStore.MAX_SIGNATURE_BYTES + 1).toInt()),
            )
        }
    }

    // ------------------------------------------------------------------
    // Templates and signatures
    // ------------------------------------------------------------------

    @Test
    fun templateVersionsAreImmutableAndLoadable() {
        val templateId = newId()
        val source = "%PDF-1.7 template".toByteArray()
        val firstVersion = newId()
        val created = store.createTemplate(
            templateId,
            meta("Vorlage"),
            newId(),
            source,
            firstVersion,
            revision(1),
        )
        val secondVersion = newId()
        store.saveTemplateVersion(
            templateId,
            secondVersion,
            revision(2),
            expectedHead = created.revisionId,
        )

        val first = store.loadTemplate(templateId, firstVersion)
        val second = store.loadTemplate(templateId)
        assertArrayEquals(revision(1), first.revisionPlaintext)
        assertArrayEquals(revision(2), second.revisionPlaintext)
        assertEquals(secondVersion, second.head.revisionId)
        assertEquals("Vorlage", titleOf(second.metaPlaintext))
        assertArrayEquals(source, second.sourceBytes)
    }

    @Test
    fun signatureRoundTripAndTamper() {
        val created = createDoc()
        val assetId = newId()
        val png = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 1, 2, 3)
        store.writeSignature(created.aggregateId, assetId, png)
        assertArrayEquals(png, store.readSignature(created.aggregateId, assetId))

        flip(docFile(created.aggregateId, "sig/$assetId.fxs"), 160)
        assertFailure("SAVE-003") { store.readSignature(created.aggregateId, assetId) }
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private fun newId(): String = UUID.randomUUID().toString()

    private fun doc(id: String) = AggregateRef(AggregateKind.DOCUMENT, id)

    private fun docFile(documentId: String, relative: String): File =
        File(storeRoot, "docs/$documentId/$relative")

    private fun meta(title: String): ByteArray =
        ("{\"createdAt\":\"2026-11-15T00:00:00.000Z\",\"title\":\"$title\"}")
            .toByteArray()

    private fun revision(value: Int): ByteArray =
        ("{\"pageCount\":$value,\"schemaVersion\":1}").toByteArray()

    private fun titleOf(meta: ByteArray): String? {
        val parsed = CanonicalJson.parse(meta) as? Map<*, *> ?: return null
        return parsed["title"] as? String
    }

    private fun createDoc(
        title: String = "Dokument",
        source: ByteArray = "%PDF-1.7 synthetic".toByteArray(),
        revisionKind: RevisionKindWire = RevisionKindWire.EXPLICIT,
    ): CreateReceipt {
        val documentId = newId()
        return store.createDocument(
            documentId,
            meta(title),
            newId(),
            source,
            newId(),
            revision(1),
            revisionKind,
        )
    }

    private fun committedRevision(): CommittedObject {
        val ref = AggregateRef(AggregateKind.DOCUMENT, newId())
        keystore.createAggregateKey(ref)
        val revisionId = newId()
        val obj = RevisionObject(ref, revisionId)
        store.commitObjectForTest(obj, revision(1))
        return CommittedObject(
            objectForTest = obj,
            file = docFile(ref.id, "rev/$revisionId.fx1"),
        )
    }

    private data class CommittedObject(
        val objectForTest: StoreObject,
        val file: File,
    )

    private fun headerOf(file: File): HeaderView {
        val bytes = file.readBytes()
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
        return HeaderView(
            chunkCount = buffer.getInt(24),
            plaintextLength = buffer.getLong(16),
            noncePrefix = bytes.copyOfRange(28, 36),
            wrapIv = bytes.copyOfRange(42, 54),
        )
    }

    private data class HeaderView(
        val chunkCount: Int,
        val plaintextLength: Long,
        val noncePrefix: ByteArray,
        val wrapIv: ByteArray,
    )

    private fun flip(file: File, offset: Int) {
        val bytes = file.readBytes()
        bytes[offset] = (bytes[offset].toInt() xor 0x01).toByte()
        file.writeBytes(bytes)
    }

    private fun patchShort(file: File, offset: Int, value: Int) {
        val bytes = file.readBytes()
        ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN).putShort(offset, value.toShort())
        recomputeCrc(bytes)
        file.writeBytes(bytes)
    }

    private fun patchInt(file: File, offset: Int, value: Int) {
        val bytes = file.readBytes()
        ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN).putInt(offset, value)
        recomputeCrc(bytes)
        file.writeBytes(bytes)
    }

    private fun recomputeCrc(file: File) {
        val bytes = file.readBytes()
        recomputeCrc(bytes)
        file.writeBytes(bytes)
    }

    private fun recomputeCrc(bytes: ByteArray) {
        val crc = bytes.copyOfRange(0, 156).crc32()
        ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN).putInt(156, crc)
    }

    private fun setMtime(file: File, deltaMs: Long) {
        assertTrue(file.setLastModified(now.get() + deltaMs))
    }

    private fun ByteArray.crc32(): Int = CRC32().apply { update(this@crc32, 0, 156) }.value.toInt()

    private fun assertCorrupt(block: () -> Unit) {
        assertFailure("SAVE-003", block)
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
}
