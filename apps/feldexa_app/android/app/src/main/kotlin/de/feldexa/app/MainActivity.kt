package de.feldexa.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityOptionsCompat
import de.feldexa.app.import.DocumentPicker
import de.feldexa.app.import.ImportService
import de.feldexa.app.import.PickedDocument
import de.feldexa.app.import.SourceStaging
import de.feldexa.app.import.StagedDiscard
import de.feldexa.app.storage.AggregateKind
import de.feldexa.app.storage.DeleteConfirmation
import de.feldexa.app.storage.EncryptedStore
import de.feldexa.app.storage.KeystoreService
import de.feldexa.app.storage.StoreService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import java.io.File
import java.io.InputStream

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
 */
class MainActivity : FlutterActivity() {

    companion object {
        /** `contracts/storage-format.md` §1. */
        const val STORE_ROOT_DIR: String = "feldexa"

        /** Matches StoreService's localized title for an incomplete aggregate. */
        private const val NOT_READABLE_TITLE = "Nicht lesbar"

        /** `contracts/platform-channel.md` §3: PDF documents only. */
        private val PDF_MIME_TYPES = arrayOf("application/pdf")

        private const val IMPORT_PICK_KEY = "t038.import.openDocument"
    }

    private var feldexaPlugin: FeldexaPlugin? = null
    private lateinit var importPickerLauncher: ActivityResultLauncher<Array<String>>
    private var pendingImportPicker: ((PickedDocument?) -> Unit)? = null

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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val plugin = FeldexaPlugin()
        feldexaPlugin = plugin
        flutterEngine.plugins.add(plugin)
        plugin.registerImportChannel(flutterEngine.dartExecutor.binaryMessenger)

        val store = EncryptedStore(
            root = File(filesDir, STORE_ROOT_DIR).absoluteFile,
            keystore = KeystoreService.forAndroid(this),
        )
        runCatching { store.ensureLayout() }
        plugin.registerService("store", StoreService(store))

        // T038: SAF streaming import. The picker callback is delivered on the
        // main thread; ImportService consumes the stream on the facade worker.
        plugin.registerService(
            "import",
            ImportService(
                picker = DocumentPicker { onResult ->
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
                staging = SourceStaging { documentId, sourceId, bytes, sha256 ->
                    store.stageSource(documentId, sourceId, bytes, sha256)
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

    override fun onResume() {
        super.onResume()
        feldexaPlugin?.onHostLifecycle(HostLifecycle.RESUMED)
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
        feldexaPlugin = null
        super.onDestroy()
    }
}
