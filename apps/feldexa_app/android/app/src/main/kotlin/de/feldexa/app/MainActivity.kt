package de.feldexa.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Bundle
import android.os.Looper
import android.print.PrintAttributes
import android.print.PrintManager
import android.provider.OpenableColumns
import android.view.WindowManager
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityOptionsCompat
import androidx.core.content.FileProvider
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import de.feldexa.app.delivery.DeliveryHost
import de.feldexa.app.delivery.DeliveryService
import de.feldexa.app.delivery.PdfArtifactPrintAdapter
import de.feldexa.app.export.ExportArtifactStore
import de.feldexa.app.export.ExportContentSource
import de.feldexa.app.export.PdfExportService
import de.feldexa.app.export.RegularFontSource
import de.feldexa.app.import.DocumentPicker
import de.feldexa.app.import.EncryptedSourceRandomAccess
import de.feldexa.app.import.ImportService
import de.feldexa.app.import.PickedDocument
import de.feldexa.app.import.SourceStaging
import de.feldexa.app.import.StagedCommit
import de.feldexa.app.import.StagedDiscard
import de.feldexa.app.import.StagedPreflight
import de.feldexa.app.ocr.MlKitOcrService
import de.feldexa.app.ocr.MlKitTextRecognizer
import de.feldexa.app.pdf.PdfBoxDocumentLoader
import de.feldexa.app.pdf.PdfDocumentLoader
import de.feldexa.app.pdf.PdfPreflight
import de.feldexa.app.storage.AggregateKind
import de.feldexa.app.storage.DeleteConfirmation
import de.feldexa.app.storage.EncryptedStore
import de.feldexa.app.storage.KeystoreService
import de.feldexa.app.storage.RevisionKindWire
import de.feldexa.app.storage.StoreService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * T024: hosts the single [FeldexaPlugin] facade.
 *
 * The plugin is added explicitly because [FeldexaPlugin] is application Kotlin,
 * not a published Flutter plugin package, so GeneratedPluginRegistrant cannot
 * discover it. `de.feldexa/import` is registered here as required by
 * `contracts/platform-channel.md` §1; the facade owns its validation and
 * envelope. Activity lifecycle is forwarded only as an event; Kotlin never
 * autosaves (§9).
 *
 * T027: the `store` service is registered here with the real
 * [EncryptedStore]/[KeystoreService]. The store root is the normative
 * `contracts/storage-format.md` §1 path `filesDir/feldexa/`; no path is exposed
 * to Dart. `startupRecovery` is exposed as `store.startupRecovery` and is
 * deliberately not run here: T031's bootstrap owns the ordering "native
 * recovery before the list is shown".
 *
 * T031 A-1: the production store is intentionally constructed WITHOUT a
 * `signatureReferenceResolver`. `EncryptedStore` now builds the default §4
 * step 3 reference set from its own decrypted, hash-verified revision and
 * template-version plaintext, so production `store.startupRecovery` really
 * deletes unreferenced signatures older than 24 h. The injected resolver
 * remains a test-only override.
 *
 * The earlier T027 candidate used the non-contract directory
 * `filesDir/feldexa_store`. This unshipped build does not delete, rename, or
 * silently migrate that directory: the canonical root is used from now on and
 * any pre-existing test data is left where it is for explicit inspection. No
 * production migration path is introduced.
 *
 * T038: the single [ActivityResultLauncher] launches the ordinary SAF
 * `ACTION_OPEN_DOCUMENT` picker for `application/pdf` via
 * [ActivityResultContracts.OpenDocument]. `FlutterActivity` extends the plain
 * `android.app.Activity`, so the launcher is hosted by a small concrete
 * [ActivityResultRegistry] whose `onLaunch` uses `startActivityForResult` and
 * whose results are dispatched from `onActivityResult`. The picked content URI
 * is consumed only through `ContentResolver.openInputStream` inside the
 * narrow [PickedDocument] seam; no path conversion or custom file browser is
 * used. [ImportService] is registered behind injectable picker/staging/discard
 * seams so its streaming logic is unit-testable without an Activity.
 *
 * T104/T107: the `export` and `delivery` services are registered here for the
 * same reason — the applier needs the encrypted store as its source and the
 * delivery flows need an Activity-bound SAF picker, `startActivity`, and
 * `PrintManager`. The activity-bound half stays in this class ([DeliveryHost]);
 * the flows, the byte copy, and the verification live in `DeliveryService`. The
 * session artifacts live in `cacheDir/feldexa_exports/` — the only path the
 * `FileProvider` exposes (`contracts/platform-channel.md` §11 point 8).
 *
 * Issue #334 / §11 point 7: this class is the [SensitiveRouteHost] of
 * `platform.sensitiveRoute`. It owns the window and therefore the only place
 * that may add or clear `FLAG_SECURE`; the flag is mutated on the main thread
 * and read back before it is reported.
 */
class MainActivity : FlutterActivity(), SensitiveRouteHost {

    companion object {
        /** `contracts/storage-format.md` §1. */
        const val STORE_ROOT_DIR: String = "feldexa"

        /** Matches StoreService's localized title for an incomplete aggregate. */
        private const val NOT_READABLE_TITLE = "Nicht lesbar"

        /** `contracts/platform-channel.md` §3: PDF documents only. */
        private val PDF_MIME_TYPES = arrayOf("application/pdf")

        private const val IMPORT_PICK_KEY = "t038.import.openDocument"

        /** T107: SAF `ACTION_CREATE_DOCUMENT` launcher key for `delivery.save`. */
        private const val DELIVERY_SAVE_KEY = "t107.delivery.createDocument"

        /**
         * `contracts/export-plan.md` §2 font contract. `pubspec.yaml` declares
         * the font under `flutter: fonts:`, so the TTF is packaged as the
         * Flutter asset `assets/fonts/NotoSans-Regular.ttf` below `flutter_assets/`.
         */
        private const val NOTO_SANS_REGULAR_ASSET =
            "flutter_assets/assets/fonts/NotoSans-Regular.ttf"

        /** Authority of the `FileProvider` declared in the manifest. */
        private const val FILE_PROVIDER_AUTHORITY_SUFFIX = ".feldexa.exports"

        /**
         * Bound on the off-main handshake of [apply]. A slow or blocked UI
         * thread must not hang the channel; the answer is then "not
         * protected".
         */
        private const val SENSITIVE_ROUTE_TIMEOUT_SECONDS = 2L
    }

    private var feldexaPlugin: FeldexaPlugin? = null
    private lateinit var importPickerLauncher: ActivityResultLauncher<Array<String>>
    private lateinit var saveDocumentLauncher: ActivityResultLauncher<String>
    private var pendingImportPicker: ((PickedDocument?) -> Unit)? = null
    private var pendingSaveLocation: ((Uri?) -> Unit)? = null

    /** True only for a debug/development build; release is not debuggable. */
    private fun isDebuggableBuild(): Boolean =
        (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    /**
     * FlutterActivity is not a ComponentActivity, so it has no
     * `registerForActivityResult`. This registry provides the same
     * [ActivityResultLauncher] contract while delegating the actual launch to
     * the Activity's `startActivityForResult`.
     */
    private val importResultRegistry = object : ActivityResultRegistry() {
        override fun <I, O> onLaunch(
            requestCode: Int,
            contract: ActivityResultContract<I, O>,
            input: I,
            options: ActivityOptionsCompat?,
        ) {
            startActivityForResult(contract.createIntent(this@MainActivity, input), requestCode, options?.toBundle())
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        importPickerLauncher = importResultRegistry.register(
            IMPORT_PICK_KEY,
            ActivityResultContracts.OpenDocument(),
        ) { uri -> deliverPickedDocument(uri) }
        saveDocumentLauncher = importResultRegistry.register(
            DELIVERY_SAVE_KEY,
            ActivityResultContracts.CreateDocument(PDF_MIME_TYPES.first()),
        ) { uri -> deliverSaveLocation(uri) }
        importResultRegistry.onRestoreInstanceState(savedInstanceState)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!importResultRegistry.dispatchResult(requestCode, resultCode, data)) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        importResultRegistry.onSaveInstanceState(outState)
    }

    private fun deliverPickedDocument(uri: Uri?) {
        val callback = pendingImportPicker
        pendingImportPicker = null
        callback?.invoke(uri?.let(::activityPickedDocument))
    }

    private fun deliverSaveLocation(uri: Uri?) {
        val callback = pendingSaveLocation
        pendingSaveLocation = null
        callback?.invoke(uri)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // pdfbox-android reads its predefined CMaps and glyph lists from the APK
        // assets (`assets/com/tom_roush/fontbox/resources/…`). Without this
        // init the first `PDType0Font.load` fails with an `IOException` from
        // `CMapParser.getExternalCMap`, which the export answers as the
        // content-free `PLT-001` internal failure. It is idempotent and runs
        // before any service is registered, so no PDFBox call can precede it.
        PDFBoxResourceLoader.init(applicationContext)
        val plugin = FeldexaPlugin()
        feldexaPlugin = plugin
        flutterEngine.plugins.add(plugin)
        plugin.registerImportChannel(flutterEngine.dartExecutor.binaryMessenger)

        // T046: debug-only fixture gate for the import integration test. This
        // is a declared test seam: the handler exists only in debug builds and
        // delivers a source only after the test explicitly arms one. Release
        // builds never register it, and the production import semantics below
        // are unchanged.
        if (isDebuggableBuild()) {
            ImportTestHooks.register(flutterEngine.dartExecutor.binaryMessenger)
        }

        val store = EncryptedStore(
            root = File(filesDir, STORE_ROOT_DIR).absoluteFile,
            keystore = KeystoreService.forAndroid(this),
        )
        runCatching { store.ensureLayout() }
        plugin.registerService("store", StoreService(store))

        // T104/T107: the export applier and the delivery flows share one session
        // artifact store. Its directory is the only path the FileProvider
        // exposes (`contracts/platform-channel.md` §11 point 8) and it is
        // cleared when the facade detaches (export service `onFacadeDetached`).
        val exportArtifacts = ExportArtifactStore(
            File(cacheDir, ExportArtifactStore.DIRECTORY_NAME).absoluteFile,
        )
        runCatching { exportArtifacts.ensureDirectory() }
        plugin.registerService(
            "export",
            PdfExportService(
                // The applier reads the stored source and the referenced
                // signature assets; it never sees a path or a URI.
                content = object : ExportContentSource {
                    override fun loadSource(documentId: String): ByteArray =
                        store.loadDocument(documentId).sourceBytes

                    override fun loadSignature(documentId: String, assetId: String): ByteArray =
                        store.readSignature(documentId, assetId)
                },
                artifacts = exportArtifacts,
                // Bundled Noto Sans Regular (`contracts/export-plan.md` §2);
                // opened per render so the subset is built per document.
                regularFont = RegularFontSource { assets.open(NOTO_SANS_REGULAR_ASSET) },
            ),
        )
        plugin.registerService("delivery", DeliveryService(exportArtifacts, createDeliveryHost()))

        // T056: bundled Latin ML Kit OCR. The production recognizer owns one
        // lazily created, reused TextRecognizer and is closed when the facade
        // detaches. The bundled model needs no Play Services download and the
        // service opens no sockets; recognized text is returned in memory only.
        plugin.registerService("ocr", MlKitOcrService(MlKitTextRecognizer()))

        // T038/T040: SAF streaming import. The picker callback is delivered on
        // the main thread; ImportService consumes the source on the facade
        // worker. The store streams the encrypted copy, preflight reads the
        // staged ciphertext through a decrypting range reader, and only a
        // verified commit makes the document visible.
        // T046: in debug builds the test may force the real preflight
        // classifier's synthetic-unknown branch. The loader is otherwise the
        // production PDFBox loader; release builds construct the plain
        // PdfPreflight() and cannot reach this branch.
        val pdfPreflight = if (isDebuggableBuild()) {
            PdfPreflight(
                loader = PdfDocumentLoader { stream ->
                    if (ImportTestHooks.forceUnknownPreflight) {
                        throw IllegalStateException("t046 synthetic unknown preflight")
                    }
                    PdfBoxDocumentLoader.load(stream)
                },
            )
        } else {
            PdfPreflight()
        }
        plugin.registerService(
            "import",
            ImportService(
                picker = DocumentPicker { onResult ->
                    // T046: a declared debug-only seam for the integration
                    // test. Without an armed fixture the ordinary system
                    // picker below is launched exactly as in production.
                    val armed = if (isDebuggableBuild()) {
                        ImportTestHooks.takePickedDocument()
                    } else {
                        null
                    }
                    if (armed != null) {
                        onResult(armed)
                        return@DocumentPicker
                    }
                    runOnUiThread {
                        if (!::importPickerLauncher.isInitialized || pendingImportPicker != null) {
                            // No parallel picker and no result before registration.
                            onResult(null)
                            return@runOnUiThread
                        }
                        pendingImportPicker = onResult
                        try {
                            importPickerLauncher.launch(PDF_MIME_TYPES)
                        } catch (failure: Throwable) {
                            pendingImportPicker = null
                            onResult(null)
                        }
                    }
                },
                staging = SourceStaging {
                        documentId, sourceId, countPass, openStreamForWrite,
                        maxBytes, shouldAbort ->
                    store.stageSourceFromStream(
                        documentId = documentId,
                        sourceId = sourceId,
                        countPass = countPass,
                        openStreamForWrite = openStreamForWrite,
                        maxBytes = maxBytes,
                        shouldAbort = shouldAbort,
                    )
                },
                preflight = StagedPreflight { documentId, sourceId ->
                    store.openSourceReader(documentId, sourceId).use { reader ->
                        pdfPreflight.preflight(EncryptedSourceRandomAccess(reader))
                    }
                },
                commit = StagedCommit {
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
                discard = StagedDiscard { documentId ->
                    // An incomplete staged aggregate has no meta, so its
                    // confirmation title is the localized "not readable" one.
                    // Failures propagate: ImportService fails closed with a
                    // non-cancelled storage failure instead of reporting a clean
                    // cancellation while the aggregate is retained.
                    store.delete(
                        kind = AggregateKind.DOCUMENT,
                        id = documentId,
                        confirmation = DeleteConfirmation(true, NOT_READABLE_TITLE),
                        notReadableTitle = NOT_READABLE_TITLE,
                    )
                },
            ),
        )
    }

    /**
     * Consumes a picked URI only through ContentResolver; never via a path.
     *
     * The provider query for [OpenableColumns.DISPLAY_NAME] is resolved lazily
     * on the facade worker thread that reads `displayName`, never here on the
     * main thread inside the ActivityResult callback. The value is unchanged
     * (the name or null) and no permission is added.
     */
    private fun activityPickedDocument(uri: Uri): PickedDocument {
        val resolver = contentResolver
        return object : PickedDocument {
            override fun openStream(): InputStream? = resolver.openInputStream(uri)
            override val displayName: String? by lazy { queryDisplayName(uri) }
        }
    }

    private fun queryDisplayName(uri: Uri): String? = try {
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (column >= 0 && cursor.moveToFirst()) cursor.getString(column) else null
        }
    } catch (failure: Exception) {
        // A missing display name never blocks an import.
        null
    }

    // ------------------------------------------------------------------
    // T107 delivery host
    // ------------------------------------------------------------------

    /**
     * The activity-bound surface [DeliveryService] needs.
     *
     * Every callback runs on the main thread; the byte copy, the size
     * verification, and the catalog mapping stay in the service. No path and no
     * URI leaves this class, and nothing here logs content.
     */
    private fun createDeliveryHost(): DeliveryHost = object : DeliveryHost {
        override fun pickSaveLocation(suggestedName: String, onResult: (Uri?) -> Unit) {
            runOnUiThread {
                if (!::saveDocumentLauncher.isInitialized || pendingSaveLocation != null) {
                    // No parallel picker and no result before registration.
                    onResult(null)
                    return@runOnUiThread
                }
                pendingSaveLocation = onResult
                try {
                    saveDocumentLauncher.launch(suggestedName)
                } catch (failure: Throwable) {
                    pendingSaveLocation = null
                    onResult(null)
                }
            }
        }

        override fun openOutputStream(uri: Uri): OutputStream? =
            contentResolver.openOutputStream(uri, "wt") ?: contentResolver.openOutputStream(uri)

        override fun openInputStream(uri: Uri): InputStream? = contentResolver.openInputStream(uri)

        override fun shareArtifact(file: File, mimeType: String) {
            // `platform-channel.md` §7: a temporary read grant on a FileProvider
            // URI; a `file://` URI is never produced.
            val uri = FileProvider.getUriForFile(
                this@MainActivity,
                packageName + FILE_PROVIDER_AUTHORITY_SUFFIX,
                file,
            )
            val send = Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val chooser = Intent.createChooser(send, null)
            if (chooser.resolveActivity(packageManager) == null) {
                // DeliveryService maps this to `delivery.unavailable`. The check
                // runs before dispatch so no failure can escape to the main thread.
                throw ActivityNotFoundException("t107.noShareTarget")
            }
            // `startActivity` is a binder call on the live Activity; the facade
            // worker may start it without touching UI state.
            startActivity(chooser)
        }

        override fun printArtifact(file: File, jobName: String, pageCount: Int): Boolean {
            val printManager = getSystemService(PrintManager::class.java) ?: return false
            // No page size is forced: each page keeps its own geometry, and the
            // system print UI is the authority on the job. The page count comes
            // from the verified artifact record, so `onLayout` (main thread)
            // never parses the PDF (`platform-channel.md` §11).
            printManager.print(
                jobName,
                PdfArtifactPrintAdapter(file, pageCount),
                PrintAttributes.Builder().build(),
            )
            return true
        }
    }

    override fun onResume() {
        super.onResume()
        feldexaPlugin?.onHostLifecycle(HostLifecycle.RESUMED)
    }

    // ------------------------------------------------------------------
    // §11 point 7 screenshot protection
    // ------------------------------------------------------------------

    /**
     * Applies or clears `FLAG_SECURE` for `route` and returns the read-back
     * state.
     *
     * The token is already validated by the facade's method catalog. The flag
     * is mutated only on the main thread: an on-main caller applies it inline,
     * every other caller is handed to the UI thread with a bounded wait. A
     * missing window, a timeout, or an interrupt answers `false` — the route is
     * then reported as not protected, which is the honest state and never a
     * claim about a flag that was not set.
     */
    override fun apply(route: String): Boolean {
        val secure = route != SensitiveRouteHost.ROUTE_NONE
        val applyFlag = {
            val current = window
            if (current == null) {
                false
            } else {
                if (secure) {
                    current.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                } else {
                    current.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                // Read back instead of assuming: the flag is the claim.
                (current.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0
            }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            return applyFlag()
        }
        val applied = AtomicReference(false)
        val done = AtomicBoolean(false)
        val latch = CountDownLatch(1)
        runOnUiThread {
            if (done.compareAndSet(false, true)) {
                applied.set(applyFlag())
                latch.countDown()
            }
        }
        return try {
            if (latch.await(SENSITIVE_ROUTE_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                applied.get()
            } else {
                false
            }
        } catch (interrupted: InterruptedException) {
            Thread.currentThread().interrupt()
            false
        }
    }

    override fun onPause() {
        feldexaPlugin?.onHostLifecycle(HostLifecycle.INACTIVE)
        super.onPause()
    }

    override fun onStop() {
        feldexaPlugin?.onHostLifecycle(HostLifecycle.PAUSED)
        super.onStop()
    }

    override fun onDestroy() {
        val plugin = feldexaPlugin
        if (plugin != null && !isChangingConfigurations) {
            plugin.onHostLifecycle(HostLifecycle.DETACHED)
            plugin.dispose()
        }
        pendingImportPicker = null
        pendingSaveLocation = null
        feldexaPlugin = null
        super.onDestroy()
    }
}
