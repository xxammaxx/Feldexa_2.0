package de.feldexa.app

import de.feldexa.app.import.PickedDocument
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream

/**
 * T046 debug-only fixture gate for the Android import integration test.
 *
 * The real Android document picker (`ACTION_OPEN_DOCUMENT`) cannot be driven
 * from a Flutter `integration_test`, so the test needs a declared way to hand
 * the production import pipeline a source. This object is that single seam:
 *
 *  * [register] is called from `MainActivity.configureFlutterEngine` only when
 *    the installed application is debuggable; release builds have no channel
 *    handler and the production picker path is unchanged.
 *  * The test explicitly arms one file path before each import via
 *    `de.feldexa/test.import.armFile`; nothing is armed by default.
 *  * The production `ImportService` still reads the source only through
 *    [PickedDocument.openStream], streams it through the real encrypted
 *    staging, runs the real preflight on the staged ciphertext, and performs
 *    the real verified commit. No import semantics are replaced.
 *
 * It also carries the one synthetic cause that cannot be produced
 * deterministically from a crafted PDF: `forceUnknownPreflight` makes the
 * debug-only PDF loader throw a generic exception, which the real
 * `PdfPreflight` classifier maps to `IMP-005`. It is false unless the test
 * arms it.
 *
 * The channel accepts a local app-readable path only in debug builds. It never
 * returns a path, source byte, title, or URI to Dart; the test already owns the
 * fixture path it supplied. This object is test-only infrastructure and must
 * be flagged as a declared seam in the T046 evidence report.
 */
internal object ImportTestHooks {
    /** Test-only method channel; not registered in release builds. */
    const val CHANNEL: String = "de.feldexa/test.import"

    @Volatile
    private var armed: ArmedFixture? = null

    /** Whether the next preflight should take the real `IMP-005` branch. */
    @Volatile
    var forceUnknownPreflight: Boolean = false
        private set

    private data class ArmedFixture(val path: String, val displayName: String?)

    /** Registers the debug-only test channel. Idempotent per engine. */
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "armFile" -> {
                    val path = call.argument<String>("path")
                    if (path == null || !File(path).isFile) {
                        result.error("TEST-001", "fixture file is not readable", null)
                        return@setMethodCallHandler
                    }
                    val unknown = call.argument<Boolean>("forceUnknownPreflight") ?: false
                    armed = ArmedFixture(path, call.argument<String>("displayName"))
                    forceUnknownPreflight = unknown
                    result.success(mapOf("armed" to true))
                }

                "clear" -> {
                    clear()
                    result.success(mapOf("cleared" to true))
                }

                else -> result.notImplemented()
            }
        }
    }

    /**
     * Returns the armed source as a one-shot-view [PickedDocument], or null.
     *
     * Every [PickedDocument.openStream] call opens a fresh read-only stream,
     * exactly like the production content resolver path. The file is never
     * written, renamed, or deleted here.
     */
    fun takePickedDocument(): PickedDocument? {
        val fixture = armed ?: return null
        return object : PickedDocument {
            override fun openStream(): InputStream = File(fixture.path).inputStream()

            override val displayName: String? = fixture.displayName
        }
    }

    /** Removes the armed fixture and the forced-failure switch. */
    fun clear() {
        armed = null
        forceUnknownPreflight = false
    }
}
