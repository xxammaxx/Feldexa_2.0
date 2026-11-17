package de.feldexa.app

import de.feldexa.app.storage.EncryptedStore
import de.feldexa.app.storage.KeystoreService
import de.feldexa.app.storage.StoreService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import java.io.File

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
 */
class MainActivity : FlutterActivity() {

    companion object {
        /** `contracts/storage-format.md` §1. */
        const val STORE_ROOT_DIR: String = "feldexa"
    }

    private var feldexaPlugin: FeldexaPlugin? = null

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
        feldexaPlugin = null
        super.onDestroy()
    }
}
