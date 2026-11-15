package de.feldexa.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * T024: hosts the single [FeldexaPlugin] facade.
 *
 * The plugin is added explicitly because [FeldexaPlugin] is application Kotlin,
 * not a published Flutter plugin package, so GeneratedPluginRegistrant cannot
 * discover it. `de.feldexa/import` is registered here as required by
 * `contracts/platform-channel.md` §1; the facade owns its validation and
 * envelope. Activity lifecycle is forwarded only as an event; Kotlin never
 * autosaves (§9).
 */
class MainActivity : FlutterActivity() {

    private var feldexaPlugin: FeldexaPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val plugin = FeldexaPlugin()
        feldexaPlugin = plugin
        flutterEngine.plugins.add(plugin)
        plugin.registerImportChannel(flutterEngine.dartExecutor.binaryMessenger)
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
