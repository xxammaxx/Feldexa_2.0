package de.feldexa.app.storage

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
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
    fun parallelSavesSerializeOnDevice() {
        val created = createDocument()
        val firstEntered = CountDownLatch(1)
        val releaseFirst = CountDownLatch(1)
        val secondStarted = CountDownLatch(1)
        val firstInjection = AtomicBoolean(true)
        val faultStore = EncryptedStore(
            root = root,
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
            Thread.sleep(250)
            releaseFirst.countDown()

            val outcomes = listOf(
                runCatching { first.get(10, TimeUnit.SECONDS) },
                runCatching { second.get(10, TimeUnit.SECONDS) },
            )
            assertEquals(1, outcomes.count { it.isSuccess })
            assertEquals(
                1,
                outcomes.count { outcome ->
                    outcome.exceptionOrNull()?.causedBy<ConcurrentSaveException>() != null
                },
            )
            val head = store.loadDocument(created.aggregateId).head.revisionId
            assertTrue(head == secondRevision || head == thirdRevision)
        } finally {
            releaseFirst.countDown()
            executor.shutdownNow()
        }
    }

    @Test
    fun pruneRevisionsKeepsHeadOnDevice() {
        val documentId = UUID.randomUUID().toString()
        val first = fixedUuid(1)
        val second = fixedUuid(2)
        store.createDocument(
            documentId,
            meta("Pruning"),
            UUID.randomUUID().toString(),
            "%PDF-1.7".toByteArray(),
            first,
            revision(1),
        )
        store.saveRevision(
            documentId,
            second,
            revision(2),
            RevisionKindWire.AUTOSAVE,
            first,
        )

        val deleted = store.pruneRevisions(documentId, setOf(second))

        assertEquals(1, deleted)
        assertFalse(File(root, "docs/$documentId/rev/$first.fx1").exists())
        assertTrue(File(root, "docs/$documentId/rev/$second.fx1").exists())
        assertEquals(second, store.loadDocument(documentId).head.revisionId)
    }

    @Test
    fun equalTimestampRecoveryFailsClosedOnDevice() {
        val documentId = UUID.randomUUID().toString()
        val higherUuid = fixedUuid(9)
        val lowerUuid = fixedUuid(1)
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
        val revDir = File(root, "docs/$documentId/rev")
        val highFile = File(revDir, "$higherUuid.fx1")
        val lowFile = File(revDir, "$lowerUuid.fx1")
        val equalTimestamp = System.currentTimeMillis() - 1_000
        assertTrue(highFile.setLastModified(equalTimestamp))
        assertTrue(lowFile.setLastModified(equalTimestamp))
        File(root, "docs/$documentId/head.fx1").delete()

        val stamp = store.recoveryStamp(AggregateKind.DOCUMENT, documentId)

        assertFalse(stamp.readable)
        assertEquals("SAVE-003", stamp.unreadableReasonCode)
        assertTrue(stamp.ambiguousRevisionOrder)
        assertTrue(highFile.exists())
        assertTrue(lowFile.exists())
    }

    @Test
    fun headHistoryAndPolicyOnDevice() {
        val documentId = UUID.randomUUID().toString()
        val ids = (1..6).map(::fixedUuid)
        val created = store.createDocument(
            documentId,
            meta("History"),
            UUID.randomUUID().toString(),
            "%PDF-1.7 history".toByteArray(),
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
        store.saveRevision(
            documentId,
            ids[4],
            revision(5),
            RevisionKindWire.EXPLICIT,
            expectedHead,
        )
        store.saveRevision(
            documentId,
            ids[5],
            revision(6),
            RevisionKindWire.RECOVERY,
            ids[4],
        )

        assertFalse(File(root, "docs/$documentId/rev/${ids[0]}.fx1").exists())
        for (index in 1 until 6) {
            assertTrue(File(root, "docs/$documentId/rev/${ids[index]}.fx1").exists())
        }
        val head = store.readHeadForTest(
            AggregateRef(AggregateKind.DOCUMENT, documentId),
        )
        assertEquals(ids[5], head.revisionId)
        assertEquals(RevisionKindWire.RECOVERY, head.kind)
        assertEquals(
            setOf(ids[1], ids[2], ids[3], ids[4], ids[5]),
            head.history.map { it.revisionId }.toSet(),
        )
        assertTrue(head.history.size <= EncryptedStore.MAX_HEAD_HISTORY)
        assertEquals(ids[5], store.loadDocument(documentId).head.revisionId)
    }

    @Test
    fun legacyHeadWithoutHistoryKeepsFilesOnDevice() {
        val documentId = UUID.randomUUID().toString()
        val ids = (1..3).map(::fixedUuid)
        val created = store.createDocument(
            documentId,
            meta("Legacy"),
            UUID.randomUUID().toString(),
            "%PDF-1.7 legacy".toByteArray(),
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
            RevisionKindWire.EXPLICIT,
            ids[1],
        )
        val ref = AggregateRef(AggregateKind.DOCUMENT, documentId)
        val head = store.readHeadForTest(ref)
        store.commitHeadForTest(ref, head.copy(history = emptyList()))

        assertEquals(0, store.pruneRevisions(documentId, emptySet()))
        for (index in 0 until 3) {
            assertTrue(File(root, "docs/$documentId/rev/${ids[index]}.fx1").exists())
        }
        assertEquals(ids[2], store.loadDocument(documentId).head.revisionId)
    }

    @Test
    fun unknownHistoryEntryIsRetainedOnDevice() {
        val documentId = UUID.randomUUID().toString()
        val first = fixedUuid(1)
        val second = fixedUuid(2)
        val created = store.createDocument(
            documentId,
            meta("Unknown"),
            UUID.randomUUID().toString(),
            "%PDF-1.7 unknown".toByteArray(),
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
        store.commitHeadForTest(
            ref,
            head.copy(
                history = listOf(
                    HeadHistoryEntry(first, null),
                    HeadHistoryEntry(second, RevisionKindWire.EXPLICIT),
                ),
            ),
        )

        assertEquals(0, store.pruneRevisions(documentId, setOf(second)))
        assertTrue(File(root, "docs/$documentId/rev/$first.fx1").exists())
        assertTrue(File(root, "docs/$documentId/rev/$second.fx1").exists())
    }

    @Test
    fun pruneFsyncFailureKeepsHistoryRetryableOnDevice() {
        val documentId = UUID.randomUUID().toString()
        val ids = (1..4).map(::fixedUuid)
        val created = store.createDocument(
            documentId,
            meta("PruneFsync"),
            UUID.randomUUID().toString(),
            "%PDF-1.7 prune".toByteArray(),
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
        val firstFile = File(root, "docs/$documentId/rev/${ids[0]}.fx1")
        val firstBytes = firstFile.readBytes()
        val faultStore = EncryptedStore(
            root = root,
            keystore = keystore,
            faultInjector = StoreFaultInjector { point, _ ->
                if (point == StoreFaultPoint.PRUNE_FSYNC) {
                    throw IOException("prune fsync failed")
                }
            },
        )

        val receipt = faultStore.saveRevision(
            documentId,
            ids[3],
            revision(4),
            RevisionKindWire.AUTOSAVE,
            ids[2],
        )

        assertFalse(firstFile.exists())
        assertEquals(0, receipt.prunedRevisions)
        val afterFailure = store.readHeadForTest(
            AggregateRef(AggregateKind.DOCUMENT, documentId),
        )
        assertTrue(afterFailure.history.any { it.revisionId == ids[0] })

        // Crash resurrection: the unconfirmed delete is lost.
        firstFile.writeBytes(firstBytes)
        val report = store.startupRecovery()

        assertTrue(report.prunedRevisions >= 1)
        assertFalse(firstFile.exists())
        val recovered = store.readHeadForTest(
            AggregateRef(AggregateKind.DOCUMENT, documentId),
        )
        assertFalse(recovered.history.any { it.revisionId == ids[0] })
        assertEquals(ids[3], recovered.revisionId)
    }

    @Test
    fun pruneFsyncFailureWithoutResurrectionRetriesOnDevice() {
        val documentId = UUID.randomUUID().toString()
        val ids = (1..4).map(::fixedUuid)
        val created = store.createDocument(
            documentId,
            meta("NoResurrection"),
            UUID.randomUUID().toString(),
            "%PDF-1.7 nores".toByteArray(),
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
            root = root,
            keystore = keystore,
            faultInjector = StoreFaultInjector { point, _ ->
                if (point == StoreFaultPoint.PRUNE_FSYNC) {
                    throw IOException("prune fsync still failing")
                }
            },
        )
        faultStore.saveRevision(
            documentId,
            ids[3],
            revision(4),
            RevisionKindWire.AUTOSAVE,
            ids[2],
        )
        val firstFile = File(root, "docs/$documentId/rev/${ids[0]}.fx1")
        assertFalse(firstFile.exists())

        val failedRetry = faultStore.startupRecovery()
        assertEquals(0, failedRetry.prunedRevisions)
        val afterFailure = store.readHeadForTest(
            AggregateRef(AggregateKind.DOCUMENT, documentId),
        )
        assertTrue(afterFailure.history.any { it.revisionId == ids[0] })

        val retry = store.startupRecovery()

        assertEquals(0, retry.prunedRevisions)
        assertFalse(firstFile.exists())
        val finalHead = store.readHeadForTest(
            AggregateRef(AggregateKind.DOCUMENT, documentId),
        )
        assertFalse(finalHead.history.any { it.revisionId == ids[0] })
        assertEquals(ids[3], finalHead.revisionId)
    }

    @Test
    fun historyCapDoesNotEvictUnconfirmedMissingOnDevice() {
        val documentId = UUID.randomUUID().toString()
        val ids = (1..24).map(::fixedUuid)
        val created = store.createDocument(
            documentId,
            meta("Cap"),
            UUID.randomUUID().toString(),
            "%PDF-1.7 cap".toByteArray(),
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
            root = root,
            keystore = keystore,
            faultInjector = StoreFaultInjector { point, _ ->
                if (point == StoreFaultPoint.PRUNE_FSYNC) {
                    throw IOException("persistent prune fsync failure")
                }
            },
        )
        faultStore.saveRevision(
            documentId,
            ids[3],
            revision(4),
            RevisionKindWire.AUTOSAVE,
            ids[2],
        )
        val ref = AggregateRef(AggregateKind.DOCUMENT, documentId)
        assertFalse(File(root, "docs/$documentId/rev/${ids[0]}.fx1").exists())

        // More than the 16-entry bound worth of save attempts: each must
        // refuse before staging/head-cap instead of silently evicting the
        // unconfirmed-missing entry.
        for (index in 4..21) {
            assertThrows(StorageWriteException::class.java) {
                faultStore.saveRevision(
                    documentId,
                    ids[index],
                    revision(index + 1),
                    RevisionKindWire.AUTOSAVE,
                    ids[3],
                )
            }
            val head = store.readHeadForTest(ref)
            assertEquals(ids[3], head.revisionId)
            assertTrue(head.history.any { it.revisionId == ids[0] })
            assertTrue(head.history.size <= EncryptedStore.MAX_HEAD_HISTORY)
        }

        store.saveRevision(
            documentId,
            ids[22],
            revision(23),
            RevisionKindWire.AUTOSAVE,
            ids[3],
        )

        assertFalse(File(root, "docs/$documentId/rev/${ids[0]}.fx1").exists())
        val finalHead = store.readHeadForTest(ref)
        assertFalse(finalHead.history.any { it.revisionId == ids[0] })
        assertEquals(ids[22], finalHead.revisionId)
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

    @Test
    fun invalidSignaturePngIsRejectedAndPreservesPriorStateOnDevice() {
        val created = createDocument("Signatur")
        val keptAsset = newId()
        val kept = AndroidTestPng.validRgba(3, 2)
        assertEquals(3 to 2, AndroidTestPng.decodedSize(kept))
        store.writeSignature(created.aggregateId, keptAsset, kept)

        val revDir = File(root, "docs/${created.aggregateId}/rev")
        val revisionsBefore = revDir.listFiles()!!
            .associate { it.name to it.readBytes().toList() }
        val headBefore = store.loadDocument(created.aggregateId).head
        val sigDir = File(root, "docs/${created.aggregateId}/sig")
        val signaturesBefore = sigDir.listFiles()!!
            .associate { it.name to it.readBytes().toList() }

        val corrupt = AndroidTestPng.validRgba(2, 2).copyOf().also {
            it[16] = (it[16].toInt() xor 0x01).toByte()
        }
        for (invalid in listOf(
            "%PDF-1.7 definitely not a PNG".toByteArray(),
            AndroidTestPng.validRgba(4, 4).copyOf(20),
            corrupt,
            // `contracts/storage-format.md` §2.4 requires alpha/transparency.
            AndroidTestPng.opaqueRgb(2, 2),
        )) {
            val assetId = newId()
            val failure = assertThrows(InvalidDataException::class.java) {
                store.writeSignature(created.aggregateId, assetId, invalid)
            }
            assertEquals("SAVE-007", failure.code)
            assertFalse(File(sigDir, "$assetId.fxs").exists())
            assertArrayEquals(
                kept,
                store.readSignature(created.aggregateId, keptAsset),
            )
            assertEquals(headBefore, store.loadDocument(created.aggregateId).head)
            assertEquals(
                revisionsBefore,
                revDir.listFiles()!!.associate { it.name to it.readBytes().toList() },
            )
            assertEquals(
                signaturesBefore,
                sigDir.listFiles()!!.associate { it.name to it.readBytes().toList() },
            )
        }
    }

    @Test
    fun signatureAlphaRepresentationsAreAcceptedOnDevice() {
        val created = createDocument("SignaturAlpha")
        val fixtures = listOf(
            AndroidTestPng.validGrayscaleAlpha(2, 2),
            AndroidTestPng.validRgbWithTransparency(2, 2),
        )
        for (png in fixtures) {
            assertEquals(2 to 2, AndroidTestPng.decodedSize(png))
            val assetId = newId()
            store.writeSignature(created.aggregateId, assetId, png)
            assertArrayEquals(
                png,
                store.readSignature(created.aggregateId, assetId),
            )
        }
    }

    @Test
    fun signatureBoundary1024IsAcceptedAnd1025IsSave007OnDevice() {
        val created = createDocument("Signaturgrenze")
        val acceptedAsset = newId()
        val boundary = AndroidTestPng.validRgba(1024, 1024)
        assertEquals(1024 to 1024, AndroidTestPng.decodedSize(boundary))
        store.writeSignature(created.aggregateId, acceptedAsset, boundary)
        assertArrayEquals(
            boundary,
            store.readSignature(created.aggregateId, acceptedAsset),
        )

        val tooWide = AndroidTestPng.validRgba(1025, 1024)
        assertEquals(1025 to 1024, AndroidTestPng.decodedSize(tooWide))
        val failure = assertThrows(InvalidDataException::class.java) {
            store.writeSignature(created.aggregateId, newId(), tooWide)
        }
        assertEquals("SAVE-007", failure.code)
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private fun fixedUuid(suffix: Int): String =
        "00000000-0000-4000-8000-%012d".format(suffix)

    private inline fun <reified T : Throwable> Throwable.causedBy(): T? {
        var current: Throwable? = this
        while (current != null) {
            if (current is T) return current
            current = current.cause
        }
        return null
    }

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
    internal class IsolatedTestBackend : KeystoreBackend {

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
