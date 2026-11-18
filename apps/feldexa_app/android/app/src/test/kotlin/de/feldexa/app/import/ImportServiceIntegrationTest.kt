package de.feldexa.app.import

import de.feldexa.app.OperationContext
import de.feldexa.app.OperationHandle
import de.feldexa.app.PlatformEventPublisher
import de.feldexa.app.PlatformFailure
import de.feldexa.app.PlatformRequest
import de.feldexa.app.ThreadPoster
import de.feldexa.app.pdf.PdfPageBox
import de.feldexa.app.pdf.PdfPreflight
import de.feldexa.app.pdf.PdfPreflightPage
import de.feldexa.app.pdf.PdfPreflightSuccess
import de.feldexa.app.pdf.PdfTestDocuments
import de.feldexa.app.storage.AggregateKind
import de.feldexa.app.storage.CanonicalJson
import de.feldexa.app.storage.DeleteConfirmation
import de.feldexa.app.storage.EncryptedStore
import de.feldexa.app.storage.KeystoreService
import de.feldexa.app.storage.LoadedAggregate
import de.feldexa.app.storage.RevisionKindWire
import de.feldexa.app.storage.StoreFaultInjector
import de.feldexa.app.storage.StoreFaultPoint
import de.feldexa.app.storage.TestStoreKeystoreBackend
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.ArrayDeque
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * T040 host-JVM integration tests with the real [EncryptedStore] (real AES-GCM
 * and a temporary filesystem) and the real `PdfPreflight` on synthetic PDFs.
 *
 * No Android runtime, SAF, Keystore provider, Activity, or channel is involved.
 * Evidence class: HOST-JVM. The test double [TestStoreKeystoreBackend] performs
 * real authenticated wrapping/unwrapping with random per-alias keys.
 */
class ImportServiceIntegrationTest {

    @Rule
    @JvmField
    val temporary = TemporaryFolder()

    private lateinit var backend: TestStoreKeystoreBackend
    private lateinit var keystore: KeystoreService
    private lateinit var store: EncryptedStore
    private lateinit var pdfPreflight: PdfPreflight

    private val now = AtomicLong(1_760_000_000_000L)

    @Before
    fun setUp() {
        backend = TestStoreKeystoreBackend()
        keystore = KeystoreService(backend, sleeper = {})
        store = EncryptedStore(
            root = File(temporary.root, "store").absoluteFile,
            keystore = keystore,
            clock = { now.get() },
        )
        store.ensureLayout()
        pdfPreflight = PdfPreflight(clock = { now.get() })
    }

    @Test
    fun importCommitsAVisibleDocumentAndReadsBackTheProtectedCopy() {
        val pdf = PdfTestDocuments.pages(3)
        val picked = ReopenablePickedDocument(pdf, "antrag.pdf")
        val (_, context) = context()
        val service = serviceFor(picked)

        @Suppress("UNCHECKED_CAST")
        val data = service.handle(pickRequest(), context) as Map<String, Any?>

        val documentId = data["documentId"] as String
        val sourceId = data["sourceId"] as String
        assertEquals(3, data["pageCount"])
        assertEquals((data["pages"] as List<*>).size, data["pageCount"])
        assertTrue((data["pageFailures"] as List<*>).isEmpty())
        assertEquals("antrag.pdf", data["displayName"])
        // Exactly the two read-only passes: hash/count, then encrypted write.
        assertEquals(2, picked.opens.get())

        val listed = store.list(AggregateKind.DOCUMENT)
        assertEquals(1, listed.size)
        assertTrue(listed.single().readable)
        assertNotNull(listed.single().head)

        val loaded = store.loadDocument(documentId)
        assertArrayEquals(pdf, loaded.sourceBytes)
        assertEquals(3, pageCountOf(loaded))
        assertEquals(sourceId, sourceIdOf(loaded))
        assertEquals(data["sha256"], sourceShaOf(loaded))

        // From here on the picked source is unavailable; the protected copy is
        // still the source of truth (FR-095/FR-096).
        picked.disabled.set(true)
        val reopened = store.loadDocument(documentId)
        assertArrayEquals(pdf, reopened.sourceBytes)
        assertEquals(documentId, reopened.aggregateId)
        assertNoPlaintextOnDisk(pdf)
    }

    @Test
    fun passwordProtectedPdfIsRejectedWithoutCreatingAnyDocument() {
        val pdf = PdfTestDocuments.encrypted("user-secret", "owner-secret")
        val service = serviceFor(ReopenablePickedDocument(pdf, "geschuetzt.pdf"))
        val (_, context) = context()

        val failure = expectFailure { service.handle(pickRequest(), context) }

        assertEquals("IMP-001", failure.code)
        assertTrue(failure.machineMessage.contains("password") ||
            failure.machineMessage.contains("Encryption"))
        assertNoDocumentDirectories()
        assertTrue(store.list(AggregateKind.DOCUMENT).isEmpty())
        assertNoPlaintextOnDisk(pdf)
        assertFalse(failure.machineMessage.contains("geschuetzt"))
    }

    @Test
    fun truncatedPdfIsRejectedWithoutCreatingAnyDocument() {
        val pdf = PdfTestDocuments.truncate(PdfTestDocuments.pages(2), 0.5)
        val service = serviceFor(ReopenablePickedDocument(pdf, "abgeschnitten.pdf"))
        val (_, context) = context()

        val failure = expectFailure { service.handle(pickRequest(), context) }

        assertEquals("IMP-002", failure.code)
        assertNoDocumentDirectories()
        assertNoPlaintextOnDisk(pdf)
    }

    @Test
    fun nonPdfIsRejectedWithoutCreatingAnyDocument() {
        val bytes = "not a pdf at all".toByteArray()
        val service = serviceFor(ReopenablePickedDocument(bytes, "notiz.pdf"))
        val (_, context) = context()

        val failure = expectFailure { service.handle(pickRequest(), context) }

        assertEquals("IMP-004", failure.code)
        assertNoDocumentDirectories()
        assertNoPlaintextOnDisk(bytes)
    }

    @Test
    fun partiallyUnreadablePdfCommitsTheUsableDocumentAndKeepsTheFailure() {
        val pdf = PdfTestDocuments.document(
            PdfTestDocuments.PageSpec(),
            PdfTestDocuments.PageSpec(omitMediaBox = true),
            PdfTestDocuments.PageSpec(),
        )
        val picked = ReopenablePickedDocument(pdf, "teilweise.pdf")
        val (_, context) = context()
        val service = serviceFor(picked)

        @Suppress("UNCHECKED_CAST")
        val data = service.handle(pickRequest(), context) as Map<String, Any?>

        assertEquals(3, data["pageCount"])
        val pages = data["pages"] as List<*>
        assertEquals(false, (pages[0] as Map<*, *>)["unreadable"] ?: false)
        assertEquals(true, (pages[1] as Map<*, *>)["unreadable"])
        val failures = data["pageFailures"] as List<*>
        assertEquals(1, failures.size)
        assertEquals("IMP-006", (failures.single() as Map<*, *>)["messageKey"])
        assertEquals(1, (failures.single() as Map<*, *>)["pageIndex"])

        val documentId = data["documentId"] as String
        val loaded = store.loadDocument(documentId)
        assertArrayEquals(pdf, loaded.sourceBytes)
        val revision = CanonicalJson.parse(loaded.revisionPlaintext) as Map<*, *>
        val revisionPages = revision["pages"] as List<*>
        val unreadable = revisionPages[1] as Map<*, *>
        assertEquals(true, unreadable["unreadable"])
        assertEquals("failed", unreadable["analysis"])
        assertNotNull(unreadable["failure"])
        assertEquals("IMP-006", (unreadable["failure"] as Map<*, *>)["messageKey"])
        // The placeholder is a schema-valid 1x1 box, never the original geometry.
        val geometry = unreadable["geometry"] as Map<*, *>
        val media = geometry["mediaBox"] as Map<*, *>
        assertEquals(1.0, (media["width"] as Number).toDouble(), 0.0)
        assertEquals(1.0, (media["height"] as Number).toDouble(), 0.0)
        assertTrue(store.list(AggregateKind.DOCUMENT).single().readable)
    }

    @Test
    fun duplicateDocumentIdIsRejectedWithoutOverwritingTheVisibleDocument() {
        val pdf = PdfTestDocuments.pages(1)
        val documentId = UUID.randomUUID().toString()
        val firstSourceId = UUID.randomUUID().toString()
        val firstRevisionId = UUID.randomUUID().toString()
        val secondSourceId = UUID.randomUUID().toString()
        val secondRevisionId = UUID.randomUUID().toString()
        val ids = ArrayDeque(
            listOf(
                documentId, firstSourceId, firstRevisionId,
                documentId, secondSourceId, secondRevisionId,
            ),
        )
        val picked = ReopenablePickedDocument(pdf, "einmal.pdf")
        val service = serviceFor(picked, idGenerator = { ids.removeFirst() })
        val (_, context) = context()

        @Suppress("UNCHECKED_CAST")
        val first = service.handle(pickRequest(), context) as Map<String, Any?>
        val before = store.loadDocument(documentId)
        val firstHead = before.head
        val firstRevision = before.revisionPlaintext.copyOf()
        val firstMeta = before.metaPlaintext.copyOf()

        val failure = expectFailure { service.handle(pickRequest(), context) }

        assertEquals("SAVE-006", failure.code)
        assertEquals(1, store.list(AggregateKind.DOCUMENT).size)
        val after = store.loadDocument(documentId)
        assertEquals(first["sourceId"], after.head.let { sourceIdOf(after) })
        assertArrayEquals(firstRevision, after.revisionPlaintext)
        assertArrayEquals(firstMeta, after.metaPlaintext)
        assertEquals(firstHead, after.head)
        assertEquals(1, revisionFiles(documentId))
        assertArrayEquals(pdf, after.sourceBytes)
    }

    @Test
    fun commitFaultLeavesNoVisibleDocumentOrIncompleteAggregate() {
        val faulty = EncryptedStore(
            root = File(temporary.root, "faulty-store").absoluteFile,
            keystore = keystore,
            clock = { now.get() },
            faultInjector = StoreFaultInjector { point, _ ->
                if (point == StoreFaultPoint.HEAD_PROMOTED) {
                    throw IOException("synthetic commit fault")
                }
            },
        )
        faulty.ensureLayout()
        val pdf = PdfTestDocuments.pages(1)
        val service = serviceFor(ReopenablePickedDocument(pdf, "fehler.pdf"), store = faulty)
        val (_, context) = context()

        val failure = expectFailure { service.handle(pickRequest(), context) }

        assertEquals("SAVE-003", failure.code)
        assertTrue(faulty.list(AggregateKind.DOCUMENT).isEmpty())
        assertTrue(File(faulty.root, "docs").listFiles().orEmpty().isEmpty())
        assertNoPlaintextOnDisk(pdf, faulty)
    }

    @Test
    fun cancellationDuringPreflightRemovesTheStagedAggregate() {
        val pdf = PdfTestDocuments.pages(1)
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val blockingPreflight = StagedPreflight { _, _ ->
            entered.countDown()
            release.await(5, TimeUnit.SECONDS)
            successOnePage()
        }
        val service = serviceFor(
            ReopenablePickedDocument(pdf, "abbruch.pdf"),
            preflight = blockingPreflight,
        )
        val (handle, context) = context()
        val failure = AtomicReference<Throwable?>()
        val worker = Thread {
            try {
                service.handle(pickRequest(), context)
            } catch (thrown: Throwable) {
                failure.set(thrown)
            }
        }
        worker.start()
        assertTrue(entered.await(5, TimeUnit.SECONDS))
        val canceller = Thread { handle.cancel() }
        canceller.start()
        awaitClaim(handle)
        release.countDown()
        worker.join(5_000L)
        canceller.join(5_000L)

        val thrown = failure.get()
        assertTrue("expected PlatformFailure, got $thrown", thrown is PlatformFailure)
        assertEquals("PLT-004", (thrown as PlatformFailure).code)
        assertTrue(store.list(AggregateKind.DOCUMENT).isEmpty())
        assertNoDocumentDirectories()
    }

    @Test
    fun lateCancelAfterCommitDoesNotDeleteTheVisibleDocument() {
        val pdf = PdfTestDocuments.pages(1)
        val service = serviceFor(ReopenablePickedDocument(pdf, "spaet.pdf"))
        val (handle, context) = context()

        @Suppress("UNCHECKED_CAST")
        val data = service.handle(pickRequest(), context) as Map<String, Any?>
        val documentId = data["documentId"] as String

        assertTrue(handle.cancel())
        assertTrue(handle.isCancelled)
        assertEquals(1, store.list(AggregateKind.DOCUMENT).size)
        assertArrayEquals(pdf, store.loadDocument(documentId).sourceBytes)
    }

    @Test
    fun requestedCapAboveTheSupportedMaximumIsClampedAndOversizeIsIMP007() {
        val pdf = PdfTestDocuments.pages(1)
        val service = serviceFor(ReopenablePickedDocument(pdf, "zu-gross.pdf"))
        val (_, context) = context()

        val failure = expectFailure {
            service.handle(pickRequest(maxBytes = 10L), context)
        }

        assertEquals("IMP-007", failure.code)
        assertNoDocumentDirectories()
    }

    // ---- helpers ------------------------------------------------------------

    private fun serviceFor(
        picked: PickedDocument,
        store: EncryptedStore = this.store,
        preflight: StagedPreflight? = null,
        commit: StagedCommit? = null,
        discard: StagedDiscard? = null,
        idGenerator: () -> String = { UUID.randomUUID().toString() },
    ): ImportService = ImportService(
        picker = DocumentPicker { onResult -> onResult(picked) },
        staging = SourceStaging {
                documentId, sourceId, countPass, openStreamForWrite, maxBytes, shouldAbort ->
            store.stageSourceFromStream(
                documentId = documentId,
                sourceId = sourceId,
                countPass = countPass,
                openStreamForWrite = openStreamForWrite,
                maxBytes = maxBytes,
                shouldAbort = shouldAbort,
            )
        },
        preflight = preflight ?: StagedPreflight { documentId, sourceId ->
            store.openSourceReader(documentId, sourceId).use { reader ->
                pdfPreflight.preflight(EncryptedSourceRandomAccess(reader))
            }
        },
        commit = commit ?: StagedCommit {
                documentId,
                sourceId,
                sourceSha256,
                sourceSizeBytes,
                revisionId,
                metaJson,
                revisionJson,
                shouldAbort,
            ->
            store.createDocumentFromStagedSource(
                documentId = documentId,
                metaJson = metaJson,
                sourceId = sourceId,
                sourceSha256 = sourceSha256,
                sourceSizeBytes = sourceSizeBytes,
                revisionId = revisionId,
                revisionJson = revisionJson,
                revisionKind = RevisionKindWire.EXPLICIT,
                shouldAbort = shouldAbort,
            )
        },
        discard = discard ?: StagedDiscard { documentId ->
            store.delete(
                kind = AggregateKind.DOCUMENT,
                id = documentId,
                confirmation = DeleteConfirmation(acknowledged = true, title = "Nicht lesbar"),
                notReadableTitle = "Nicht lesbar",
            )
        },
        idGenerator = idGenerator,
        clock = { now.get() },
    )

    private fun pickRequest(maxBytes: Long = ImportService.DEFAULT_MAX_SOURCE_BYTES) =
        PlatformRequest(
            "import.pickAndImport",
            mapOf("schemaVersion" to 1, "maxBytes" to maxBytes),
        )

    private fun context(): Pair<OperationHandle, OperationContext> {
        val id = UUID.randomUUID().toString()
        val handle = OperationHandle(id)
        return handle to OperationContext(id, handle, PlatformEventPublisher(DirectPoster))
    }

    private fun awaitClaim(handle: OperationHandle) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        while (!handle.hasClaimedCancellation()) {
            if (System.nanoTime() > deadline) fail("cancel was not claimed")
            Thread.sleep(5L)
        }
    }

    private fun expectFailure(block: () -> Unit): PlatformFailure {
        try {
            block()
        } catch (failure: PlatformFailure) {
            return failure
        }
        fail("expected a PlatformFailure")
        throw AssertionError("unreachable")
    }

    private fun pageCountOf(loaded: LoadedAggregate): Int {
        val meta = CanonicalJson.parse(loaded.metaPlaintext) as Map<*, *>
        val source = meta["source"] as Map<*, *>
        return (source["pageCount"] as Number).toInt()
    }

    private fun sourceIdOf(loaded: LoadedAggregate): String {
        val meta = CanonicalJson.parse(loaded.metaPlaintext) as Map<*, *>
        val source = meta["source"] as Map<*, *>
        return source["id"] as String
    }

    private fun sourceShaOf(loaded: LoadedAggregate): String {
        val meta = CanonicalJson.parse(loaded.metaPlaintext) as Map<*, *>
        val source = meta["source"] as Map<*, *>
        return source["sha256"] as String
    }

    private fun revisionFiles(documentId: String): Int =
        File(File(store.root, "docs"), "$documentId/rev").listFiles()
            ?.count { it.isFile && it.name.endsWith(".fx1") }
            ?: 0

    private fun assertNoDocumentDirectories() {
        val docs = File(store.root, "docs")
        assertTrue(
            "no document aggregate may remain",
            docs.listFiles().orEmpty().isEmpty(),
        )
    }

    private fun assertNoPlaintextOnDisk(marker: ByteArray, store: EncryptedStore = this.store) {
        val needle = if (marker.size > 5) {
            marker.copyOfRange(0, minOf(marker.size, 16))
        } else {
            marker
        }
        val files = store.root.walkTopDown().filter { it.isFile }.toList()
        for (file in files) {
            val bytes = file.readBytes()
            assertFalse(
                "plaintext marker found in ${file.relativeTo(store.root)}",
                bytes.containsSubsequence(needle),
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

    private fun successOnePage(): PdfPreflightSuccess {
        val box = PdfPageBox(0.0, 0.0, 595.0, 842.0)
        return PdfPreflightSuccess(
            pages = listOf(
                PdfPreflightPage(0, box, box, 0, unreadable = false),
            ),
            pageFailures = emptyList(),
        )
    }

    private object DirectPoster : ThreadPoster {
        override fun post(block: () -> Unit) = block()
    }

    private class ReopenablePickedDocument(
        private val content: ByteArray,
        override val displayName: String?,
    ) : PickedDocument {
        val opens = AtomicInteger(0)
        val disabled = AtomicBoolean(false)

        override fun openStream(): InputStream? {
            opens.incrementAndGet()
            if (disabled.get()) throw IOException("picked source is no longer available")
            return ByteArrayInputStream(content)
        }
    }
}
