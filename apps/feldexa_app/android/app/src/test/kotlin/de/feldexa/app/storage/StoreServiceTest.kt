package de.feldexa.app.storage

import de.feldexa.app.OperationContext
import de.feldexa.app.OperationRegistry
import de.feldexa.app.PlatformEventPublisher
import de.feldexa.app.PlatformFailure
import de.feldexa.app.PlatformRequest
import de.feldexa.app.ThreadPoster
import java.io.File
import java.security.MessageDigest
import java.util.UUID
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
 * T027 host-JVM tests for the native [StoreService] over the real
 * [EncryptedStore] and [KeystoreService] (with the AES-GCM test backend).
 *
 * These are `NONE`-class evidence: no Android Keystore, MethodChannel, or
 * emulator runs here. The instrumentation test proves those layers.
 */
class StoreServiceTest {

    @Rule
    @JvmField
    val temporary = TemporaryFolder()

    private lateinit var backend: TestStoreKeystoreBackend
    private lateinit var store: EncryptedStore
    private lateinit var service: StoreService
    private val operationRegistry = OperationRegistry()
    private val poster = ThreadPoster { it() }

    @Before
    fun setUp() {
        backend = TestStoreKeystoreBackend()
        store = EncryptedStore(
            root = File(temporary.root, "store").absoluteFile,
            keystore = KeystoreService(backend, sleeper = {}),
            clock = { 1_760_000_000_000L },
        )
        store.ensureLayout()
        service = StoreService(store, clock = { 1_760_000_000_000L })
    }

    @Test
    fun stageCreateLoadListAndSaveKeepIdentityHeadAndSource() {
        val documentId = newId()
        val sourceId = newId()
        val revisionId = newId()
        val source = "%PDF-1.7 synthetic T027 source".toByteArray()
        val sourceSha = sha256(source)
        val content = linkedMapOf<String, Any?>(
            "pageCount" to 1,
            "labels" to listOf("synthetisch"),
        )
        val revisionSha = sha256(CanonicalJson.encode(content))

        val staged = handle(
            "store.stageSource",
            linkedMapOf(
                "documentId" to documentId,
                "sourceId" to sourceId,
                "bytes" to source,
                "sha256" to sourceSha,
            ),
        ) as Map<*, *>
        assertEquals(true, staged["verified"])
        assertEquals(sourceSha, staged["sha256"])

        val created = createDocument(
            documentId = documentId,
            sourceId = sourceId,
            revisionId = revisionId,
            sourceSha = sourceSha,
            sourceSize = source.size,
            revisionSha = revisionSha,
            content = content,
        )
        assertEquals(documentId, created["id"])
        assertEquals(revisionId, created["latestRevisionId"])
        assertEquals("T027 Dokument", created["title"])
        assertEquals(true, created["readable"])
        assertEquals("document", created["kind"])

        val listed = handle("store.list", linkedMapOf("kind" to "document")) as Map<*, *>
        val items = listed["items"] as List<*>
        assertEquals(1, items.size)
        val item = items.single() as Map<*, *>
        assertEquals(documentId, item["id"])
        assertEquals(revisionId, item["latestRevisionId"])

        val loaded = handle("store.loadDocument", linkedMapOf("documentId" to documentId)) as Map<*, *>
        val meta = loaded["meta"] as Map<*, *>
        assertEquals(documentId, meta["id"])
        assertEquals(revisionId, meta["latestRevisionId"])
        val head = loaded["head"] as Map<*, *>
        assertEquals(revisionId, head["revisionId"])
        assertArrayEquals(source, handle(
            "store.readSource",
            linkedMapOf("documentId" to documentId),
        ) as ByteArray)

        val saveContent = linkedMapOf<String, Any?>("pageCount" to 2)
        val receipt = handle(
            "store.saveRevision",
            linkedMapOf(
                "documentId" to documentId,
                "revision" to saveContent,
                "expectedHead" to revisionId,
                "kind" to "explicit",
            ),
        ) as Map<*, *>
        assertTrue(receipt["revisionId"] is String)
        assertEquals(36, (receipt["revisionId"] as String).length)
        assertEquals(true, receipt["verified"])
        assertEquals(sha256(CanonicalJson.encode(saveContent)), receipt["sha256"])

        val afterSave = handle("store.list", linkedMapOf("kind" to "document")) as Map<*, *>
        val savedMeta = (afterSave["items"] as List<*>).single() as Map<*, *>
        assertEquals(receipt["revisionId"], savedMeta["latestRevisionId"])
        assertEquals("explicit", (headAfter(documentId) as Map<*, *>)["kind"])
    }

    @Test
    fun duplicateVisibleCreateIsRefusedAndOriginalRemainsReadable() {
        val documentId = newId()
        val sourceId = newId()
        val revisionId = newId()
        val source = "%PDF-1.7 duplicate source".toByteArray()
        val content = linkedMapOf<String, Any?>("pageCount" to 1)
        val sha = sha256(CanonicalJson.encode(content))
        handle(
            "store.stageSource",
            linkedMapOf(
                "documentId" to documentId,
                "sourceId" to sourceId,
                "bytes" to source,
                "sha256" to sha256(source),
            ),
        )
        createDocument(documentId, sourceId, revisionId, sha256(source), source.size, sha, content)

        val failure = assertThrows(PlatformFailure::class.java) {
            createDocument(documentId, sourceId, revisionId, sha256(source), source.size, sha, content)
        }
        assertEquals("SAVE-006", failure.code)
        val loaded = handle("store.loadDocument", linkedMapOf("documentId" to documentId)) as Map<*, *>
        assertEquals(revisionId, (loaded["head"] as Map<*, *>)["revisionId"])
    }

    @Test
    fun sourceHashMismatchNeverBecomesVisible() {
        val documentId = newId()
        val sourceId = newId()
        val source = "%PDF-1.7 source".toByteArray()
        handle(
            "store.stageSource",
            linkedMapOf(
                "documentId" to documentId,
                "sourceId" to sourceId,
                "bytes" to source,
                "sha256" to sha256(source),
            ),
        )
        val content = linkedMapOf<String, Any?>("pageCount" to 1)
        val failure = assertThrows(PlatformFailure::class.java) {
            createDocument(
                documentId,
                sourceId,
                newId(),
                "0".repeat(64),
                source.size,
                sha256(CanonicalJson.encode(content)),
                content,
            )
        }
        assertEquals("SAVE-003", failure.code)
        val listed = handle("store.list", linkedMapOf("kind" to "document")) as Map<*, *>
        assertTrue((listed["items"] as List<*>).isEmpty())
    }

    @Test
    fun parentedInitialRevisionIsRejectedBeforeAnyWrite() {
        val documentId = newId()
        val failure = assertThrows(PlatformFailure::class.java) {
            handle(
                "store.createDocument",
                linkedMapOf(
                    "documentId" to documentId,
                    "title" to "Parented",
                    "source" to mapOf(
                        "id" to newId(),
                        "sha256" to "0".repeat(64),
                        "sizeBytes" to 1,
                        "pageCount" to 1,
                        "importedAt" to "2026-11-16T12:00:00.000Z",
                        "integrity" to "verified",
                    ),
                    "initialRevision" to mapOf(
                        "id" to newId(),
                        "documentId" to documentId,
                        "parentRevisionId" to newId(),
                        "kind" to "explicit",
                        "createdAt" to "2026-11-16T12:00:00.000Z",
                        "plaintextSha256" to "0".repeat(64),
                        "content" to mapOf("pageCount" to 1),
                    ),
                ),
            )
        }
        assertEquals("SAVE-007", failure.code)
    }

    @Test
    fun expectedHeadMismatchPreservesTheVerifiedHead() {
        val documentId = newId()
        val sourceId = newId()
        val revisionId = newId()
        val source = "%PDF-1.7 head source".toByteArray()
        val content = linkedMapOf<String, Any?>("pageCount" to 1)
        handle(
            "store.stageSource",
            linkedMapOf(
                "documentId" to documentId,
                "sourceId" to sourceId,
                "bytes" to source,
                "sha256" to sha256(source),
            ),
        )
        createDocument(
            documentId,
            sourceId,
            revisionId,
            sha256(source),
            source.size,
            sha256(CanonicalJson.encode(content)),
            content,
        )
        val failure = assertThrows(PlatformFailure::class.java) {
            handle(
                "store.saveRevision",
                linkedMapOf(
                    "documentId" to documentId,
                    "revision" to linkedMapOf<String, Any?>("pageCount" to 2),
                    "expectedHead" to newId(),
                    "kind" to "autosave",
                ),
            )
        }
        assertEquals("SAVE-006", failure.code)
        val head = headAfter(documentId) as Map<*, *>
        assertEquals(revisionId, head["revisionId"])
    }

    @Test
    fun wrongDeleteTitleIsPlatformSecurityAndPreservesTheDocument() {
        val documentId = newId()
        val sourceId = newId()
        val revisionId = newId()
        val source = "%PDF-1.7 delete source".toByteArray()
        val content = linkedMapOf<String, Any?>("pageCount" to 1)
        handle(
            "store.stageSource",
            linkedMapOf(
                "documentId" to documentId,
                "sourceId" to sourceId,
                "bytes" to source,
                "sha256" to sha256(source),
            ),
        )
        createDocument(
            documentId,
            sourceId,
            revisionId,
            sha256(source),
            source.size,
            sha256(CanonicalJson.encode(content)),
            content,
        )
        val failure = assertThrows(PlatformFailure::class.java) {
            handle(
                "store.delete",
                linkedMapOf(
                    "kind" to "document",
                    "id" to documentId,
                    "confirm" to linkedMapOf(
                        "title" to "Falscher Titel",
                        "acknowledged" to true,
                    ),
                ),
            )
        }
        assertEquals("PLT-002", failure.code)
        val loaded = handle("store.loadDocument", linkedMapOf("documentId" to documentId)) as Map<*, *>
        assertFalse((loaded["meta"] as Map<*, *>).isEmpty())
    }

    @Test
    fun startupRecoveryIsReachableThroughTheService() {
        val report = handle("store.startupRecovery", linkedMapOf()) as Map<*, *>
        assertEquals(0, report["tempEntriesRemoved"])
        assertEquals(0, report["incompleteAggregatesRemoved"])
        assertEquals(false, report["aliasSweepSkipped"])
    }

    private fun createDocument(
        documentId: String,
        sourceId: String,
        revisionId: String,
        sourceSha: String,
        sourceSize: Int,
        revisionSha: String,
        content: Map<String, Any?>,
    ): Map<*, *> {
        return handle(
            "store.createDocument",
            linkedMapOf(
                "documentId" to documentId,
                "title" to "T027 Dokument",
                "source" to linkedMapOf(
                    "id" to sourceId,
                    "sha256" to sourceSha,
                    "sizeBytes" to sourceSize,
                    "pageCount" to 1,
                    "importedAt" to "2026-11-16T12:00:00.000Z",
                    "integrity" to "verified",
                ),
                "initialRevision" to linkedMapOf(
                    "id" to revisionId,
                    "documentId" to documentId,
                    "parentRevisionId" to null,
                    "kind" to "explicit",
                    "createdAt" to "2026-11-16T12:00:00.000Z",
                    "plaintextSha256" to revisionSha,
                    "content" to content,
                ),
            ),
        ) as Map<*, *>
    }

    private fun headAfter(documentId: String): Any? {
        val loaded = handle("store.loadDocument", linkedMapOf("documentId" to documentId)) as Map<*, *>
        return loaded["head"]
    }

    private fun handle(method: String, payload: Map<String, Any?>): Any? {
        val handle = operationRegistry.begin("op-" + UUID.randomUUID())
        val context = OperationContext(
            "op",
            handle,
            PlatformEventPublisher(poster),
        )
        return service.handle(
            PlatformRequest(method, linkedMapOf("schemaVersion" to 1) + payload),
            context,
        )
    }

    private fun newId(): String = UUID.randomUUID().toString()

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") {
            "%02x".format(it.toInt() and 0xFF)
        }
}
