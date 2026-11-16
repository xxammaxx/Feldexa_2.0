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
 * [EncryptedStore]/[KeystoreService]. The store root is app-private
 * `filesDir/feldexa_store`; no path is exposed to Dart. `startupRecovery` is
 * exposed as `store.startupRecovery` and is deliberately not run here: T031's
 * bootstrap owns the ordering "native recovery before the list is shown".
 */
class MainActivity : FlutterActivity() {

    private var feldexaPlugin: FeldexaPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val plugin = FeldexaPlugin()
        feldexaPlugin = plugin
        flutterEngine.plugins.add(plugin)
        plugin.registerImportChannel(flutterEngine.dartExecutor.binaryMessenger)

        val store = EncryptedStore(
            root = File(filesDir, "feldexa_store").absoluteFile,
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
