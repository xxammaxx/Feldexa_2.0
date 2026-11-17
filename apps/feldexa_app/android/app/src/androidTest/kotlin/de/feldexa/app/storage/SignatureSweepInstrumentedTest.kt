package de.feldexa.app.storage

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * T031 / A-1 Android instrumentation coverage for the default §4 step 3
 * unreferenced-signature sweep.
 *
 * The production [EncryptedStore] is constructed WITHOUT an injected
 * `signatureReferenceResolver`, matching `MainActivity`. The test uses the
 * existing [EncryptedStoreInstrumentedTest.IsolatedTestBackend] so no
 * production Keystore alias is created or deleted.
 *
 * This file is written for an exclusively allocated emulator/device run. It is
 * intentionally not executed by the host JVM suite.
 */
@RunWith(AndroidJUnit4::class)
class SignatureSweepInstrumentedTest {

    private lateinit var context: Context
    private lateinit var backend: EncryptedStoreInstrumentedTest.IsolatedTestBackend
    private lateinit var keystore: KeystoreService
    private lateinit var store: EncryptedStore
    private lateinit var root: File

    @Before
    fun setUp() {
        context = InstrumentationRegistry.getInstrumentation().targetContext
        backend = EncryptedStoreInstrumentedTest.IsolatedTestBackend()
        keystore = KeystoreService(backend, strongBoxSupported = false)
        root = File(context.filesDir, "t031-signature-test-" + UUID.randomUUID())
        store = EncryptedStore(root, keystore)
        store.ensureLayout()
    }

    @After
    fun tearDown() {
        runCatching { root.deleteRecursively() }
        backend.deleteCreatedTestAliases()
    }

    @Test
    fun productionStoreSweepsOldUnreferencedSignatureAndKeepsReferences() {
        val referencedByDocument = newId()
        val referencedByTemplate = newId()
        val unreferencedOld = newId()
        val freshUnreferenced = newId()
        val revisionJson =
            ("{\"pageCount\":1,\"signatures\":{\"field-1\":{" +
                "\"assetId\":\"$referencedByDocument\"}}}").toByteArray()
        val document = createDocument(revisionJson)
        store.writeSignature(
            document.aggregateId,
            referencedByDocument,
            AndroidTestPng.validRgba(3, 3),
        )
        store.writeSignature(
            document.aggregateId,
            referencedByTemplate,
            AndroidTestPng.validRgba(4, 4),
        )
        store.writeSignature(
            document.aggregateId,
            unreferencedOld,
            AndroidTestPng.validRgba(5, 5),
        )
        store.writeSignature(
            document.aggregateId,
            freshUnreferenced,
            AndroidTestPng.validRgba(6, 6),
        )
        val versionJson =
            ("{\"pageCount\":1,\"templateUnknown\":{" +
                "\"assetId\":\"$referencedByTemplate\"}}").toByteArray()
        store.createTemplate(
            newId(),
            meta("Vorlage"),
            newId(),
            "%PDF-1.7 template".toByteArray(),
            newId(),
            versionJson,
        )
        val sigDir = File(root, "docs/${document.aggregateId}/sig")
        setOld(sigDir, referencedByDocument)
        setOld(sigDir, referencedByTemplate)
        setOld(sigDir, unreferencedOld)

        store.startupRecovery()

        assertFalse(
            "an old unreferenced signature must be deleted",
            File(sigDir, "$unreferencedOld.fxs").exists(),
        )
        assertTrue(
            "a document revision reference must keep the asset",
            File(sigDir, "$referencedByDocument.fxs").exists(),
        )
        assertTrue(
            "a template-version reference must keep the asset",
            File(sigDir, "$referencedByTemplate.fxs").exists(),
        )
        assertTrue(
            "a fresh unreferenced signature must be kept",
            File(sigDir, "$freshUnreferenced.fxs").exists(),
        )
    }

    @Test
    fun corruptRevisionKeepsUnreferencedSignatureOnDevice() {
        val assetId = newId()
        val document = createDocument(revision(1))
        store.writeSignature(
            document.aggregateId,
            assetId,
            AndroidTestPng.validRgba(7, 7),
        )
        val sigDir = File(root, "docs/${document.aggregateId}/sig")
        setOld(sigDir, assetId)
        File(
            root,
            "docs/${document.aggregateId}/rev/${newId()}.fx1",
        ).writeBytes("not-a-container".toByteArray())

        store.startupRecovery()

        assertTrue(
            "an unreadable revision must keep the asset",
            File(sigDir, "$assetId.fxs").exists(),
        )
        // T031 round 4: the step-6 recovery event must report the uncertain
        // scan instead of looking like a clean, empty signature sweep.
        val event = File(root, "diagnostics/redacted.jsonl").readLines().last()
        assertTrue(
            "an uncertain signature scan must be visible in the redacted event",
            event.contains("\"signatureSweepUncertainAggregates\":1"),
        )
        assertTrue(
            "the conservative keep must report zero removals",
            event.contains("\"signatureAssetsRemoved\":0"),
        )
        assertFalse(
            "the step-6 event must stay counts-only",
            event.contains(assetId),
        )
    }

    @Test
    fun expiredDeadlineKeepsTmpAndSignatureOnDevice() {
        val assetId = newId()
        val document = createDocument(revision(1))
        store.writeSignature(
            document.aggregateId,
            assetId,
            AndroidTestPng.validRgba(11, 11),
        )
        val sigDir = File(root, "docs/${document.aggregateId}/sig")
        setOld(sigDir, assetId)
        val staleTmp = File(root, "tmp/unknown-deadline-entry")
        staleTmp.writeText("x")

        val report = store.startupRecovery(
            deadlineEpochMs = System.currentTimeMillis() - 1,
        )

        assertTrue("the deadline stop must be reported", report.deadlineReached)
        assertTrue("the stale tmp entry must survive", staleTmp.exists())
        assertTrue(
            "the old unreferenced signature must survive the deadline stop",
            File(sigDir, "$assetId.fxs").exists(),
        )
        val event = File(root, "diagnostics/redacted.jsonl").readLines().last()
        assertTrue(event.contains("\"deadlineReached\":true"))
        assertTrue(event.contains("\"signatureAssetsRemoved\":0"))
        assertFalse("the event must stay counts-only", event.contains(assetId))
    }

    private fun createDocument(revisionJson: ByteArray): CreateReceipt {
        val documentId = newId()
        return store.createDocument(
            documentId,
            meta("Dokument"),
            newId(),
            "%PDF-1.7 synthetic".toByteArray(),
            newId(),
            revisionJson,
        )
    }

    private fun setOld(sigDir: File, assetId: String) {
        assertTrue(
            File(sigDir, "$assetId.fxs").setLastModified(
                System.currentTimeMillis() -
                    EncryptedStore.STALE_TEMP_MS -
                    1_000,
            ),
        )
    }

    private fun newId(): String = UUID.randomUUID().toString()

    private fun meta(title: String): ByteArray =
        ("{\"createdAt\":\"2026-11-15T00:00:00.000Z\",\"title\":\"$title\"}")
            .toByteArray()

    private fun revision(value: Int): ByteArray =
        ("{\"pageCount\":$value,\"schemaVersion\":1}").toByteArray()
}
