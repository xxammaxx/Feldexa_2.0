package de.feldexa.app.delivery

import android.content.ActivityNotFoundException
import android.net.Uri
import de.feldexa.app.OperationContext
import de.feldexa.app.PlatformFailure
import de.feldexa.app.PlatformRequest
import de.feldexa.app.PlatformService
import de.feldexa.app.export.ExportArtifactStore
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * T107: the `delivery` prefix owner — save, share, and print of a verified
 * session artifact.
 *
 * Normative sources: `contracts/platform-channel.md` §7 (the three synchronous
 * methods and their `{completed, cancelled, locationHint}` shape), §11 points 2
 * and 8 (no path or URI in an error; `FileProvider` limited to
 * `cacheDir/feldexa_exports/`), and `contracts/export-plan.md` §5 step 10
 * (delivery never deletes the durable document).
 *
 * Semantics that are deliberately narrow:
 *  - `save` writes the artifact bytes to the SAF-created URI and then re-opens
 *    the URI to verify the byte count; a mismatch is a failure, never a
 *    success. The write is bounded and cancellation is observed while waiting
 *    for the picker.
 *  - `share` uses a `FileProvider` `content://` URI with
 *    `FLAG_GRANT_READ_URI_PERMISSION`; no `file://` URI is ever produced.
 *  - `print` hands the artifact to the system print UI, which is the authority
 *    on completion.
 *  - A user who dismisses the picker is **not** an error: the response is
 *    `{completed: false, cancelled: true}`, which is what the Dart
 *    `DeliveryPort` client requires (`contracts/ports.md` §2.6). Only a real
 *    failure produces `delivery.failed`, and a missing share/print target
 *    produces `delivery.unavailable`.
 *
 * Content rules: no failure, response, or event carries a title, file name,
 * path, or URI. The artifact bytes never leave through an error path.
 */
class DeliveryService(
    private val artifacts: ExportArtifactStore,
    private val host: DeliveryHost,
    private val pickerTimeoutMs: Long = DEFAULT_PICKER_TIMEOUT_MS,
) : PlatformService {

    override fun handle(request: PlatformRequest, context: OperationContext): Any? = when (request.method) {
        "delivery.save" -> save(request, context)
        "delivery.share" -> share(request)
        "delivery.print" -> print(request)
        else -> throw PlatformFailure.unsupported()
    }

    override fun onFacadeDetached() {
        // Delivery owns no long-lived handle and never deletes durable data; the
        // session artifacts belong to the export service's detach cleanup.
    }

    /**
     * `ACTION_CREATE_DOCUMENT` plus verified write (`platform-channel.md` §7).
     *
     * `locationHint` stays `null`: any hint that names the target would carry a
     * provider, a document name, or a path across the channel (§11 point 2), and
     * the system picker already confirms the destination to the user.
     */
    private fun save(request: PlatformRequest, context: OperationContext): Map<String, Any?> {
        val artifactId = requireArtifactId(request.string("artifactId"))
        val suggestedName = DeliveryNames.sanitizeSuggestedName(request.string("suggestedName"))
        val record = artifacts.record(artifactId) ?: throw artifactNotFound()
        if (!record.file.isFile || record.file.length() != record.byteSize) {
            throw artifactNotFound()
        }

        val target = awaitSaveLocation(suggestedName, context)
            ?: return linkedMapOf(
                "completed" to false,
                "cancelled" to true,
                "locationHint" to null,
            )

        writeVerified(target, record.file)
        return linkedMapOf(
            "completed" to true,
            "cancelled" to false,
            "locationHint" to null,
        )
    }

    /** Copies the artifact to [target] and proves the written byte count. */
    private fun writeVerified(target: Uri, file: File) {
        val expected = file.length()
        try {
            val sink = host.openOutputStream(target) ?: throw deliveryUnavailable()
            sink.use { output ->
                file.inputStream().use { input -> copyBounded(input, output) }
                output.flush()
            }
            val readBack = countBytes(host.openInputStream(target) ?: throw deliveryFailed())
            if (readBack != expected) throw deliveryFailed()
        } catch (failure: PlatformFailure) {
            throw failure
        } catch (failure: IOException) {
            throw deliveryFailed()
        } catch (failure: SecurityException) {
            throw deliveryUnavailable()
        } catch (failure: Exception) {
            throw deliveryFailed()
        }
    }

    private fun copyBounded(input: InputStream, output: OutputStream) {
        val buffer = ByteArray(COPY_BUFFER_BYTES)
        while (true) {
            val read = input.read(buffer)
            if (read <= 0) break
            output.write(buffer, 0, read)
        }
    }

    private fun countBytes(input: InputStream): Long = input.use { stream ->
        val buffer = ByteArray(COPY_BUFFER_BYTES)
        var total = 0L
        while (true) {
            val read = stream.read(buffer)
            if (read <= 0) break
            total += read
        }
        total
    }

    /** `ACTION_SEND` through a temporary `FileProvider` grant (§7). */
    private fun share(request: PlatformRequest): Map<String, Any?> {
        val artifactId = requireArtifactId(request.string("artifactId"))
        val mimeType = request.string("mimeType")
        if (mimeType != PDF_MIME_TYPE) throw PlatformFailure.invalidPayload("platform.invalidEnum")
        val record = artifacts.record(artifactId) ?: throw artifactNotFound()
        if (!record.file.isFile || record.file.length() != record.byteSize) {
            throw artifactNotFound()
        }
        try {
            host.shareArtifact(record.file, mimeType)
        } catch (failure: ActivityNotFoundException) {
            throw deliveryUnavailable()
        } catch (failure: SecurityException) {
            throw deliveryUnavailable()
        } catch (failure: Exception) {
            throw deliveryFailed()
        }
        return linkedMapOf("completed" to true, "cancelled" to false)
    }

    /** System print UI (§7); no artifact is rasterised by the app itself. */
    private fun print(request: PlatformRequest): Map<String, Any?> {
        val artifactId = requireArtifactId(request.string("artifactId"))
        val jobName = request.string("jobName")
        if (jobName.isNullOrEmpty() || jobName.length > MAX_JOB_NAME_LENGTH) {
            throw PlatformFailure.invalidPayload("platform.invalidString")
        }
        if (jobName.any { it == '\u0000' || Character.isISOControl(it) }) {
            throw PlatformFailure.invalidPayload("platform.invalidString")
        }
        val record = artifacts.record(artifactId) ?: throw artifactNotFound()
        if (!record.file.isFile || record.file.length() != record.byteSize) {
            throw artifactNotFound()
        }
        val started = try {
            host.printArtifact(record.file, jobName)
        } catch (failure: SecurityException) {
            throw deliveryUnavailable()
        } catch (failure: Exception) {
            throw deliveryFailed()
        }
        if (!started) throw deliveryUnavailable()
        return linkedMapOf("completed" to true, "cancelled" to false)
    }

    /**
     * Launches `ACTION_CREATE_DOCUMENT` and waits in bounded slices so a
     * cancelled operation aborts promptly and a lost result can never pin a
     * worker. `null` is the user's cancel, not a failure (§7).
     */
    private fun awaitSaveLocation(suggestedName: String, context: OperationContext): Uri? {
        val latch = CountDownLatch(1)
        val result = AtomicReference<Uri?>()
        try {
            host.pickSaveLocation(suggestedName) { uri ->
                result.set(uri)
                latch.countDown()
            }
        } catch (failure: ActivityNotFoundException) {
            throw deliveryUnavailable()
        } catch (failure: Exception) {
            throw deliveryFailed()
        }
        val deadlineNanos = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(pickerTimeoutMs)
        while (true) {
            context.checkCancelled()
            val remaining = deadlineNanos - System.nanoTime()
            if (remaining <= 0L) throw deliveryFailed()
            if (latch.await(minOf(remaining, PICKER_WAIT_SLICE_NANOS), TimeUnit.NANOSECONDS)) break
        }
        return result.get()
    }

    private fun requireArtifactId(value: String?): String =
        value ?: throw artifactNotFound()

    private fun deliveryFailed(): PlatformFailure =
        PlatformFailure("PLT-001", "internalError", false, "delivery.failed")

    private fun deliveryUnavailable(): PlatformFailure =
        PlatformFailure("PLT-001", "deliveryUnavailable", false, "delivery.unavailable")

    /**
     * The artifact is not part of this session (`platform-channel.md` §6: an
     * unknown or expired artifact id is `EXP-002`). Delivery has no code of its
     * own for a missing artifact.
     */
    private fun artifactNotFound(): PlatformFailure =
        PlatformFailure("EXP-002", "exportFailed", false, "export.failed")

    private companion object {
        const val PDF_MIME_TYPE = "application/pdf"
        const val MAX_JOB_NAME_LENGTH = 200
        const val COPY_BUFFER_BYTES = 64 * 1024
        const val DEFAULT_PICKER_TIMEOUT_MS = 10L * 60L * 1_000L
        val PICKER_WAIT_SLICE_NANOS: Long = TimeUnit.MILLISECONDS.toNanos(100L)
    }
}

/**
 * The activity-bound surface the delivery flows need.
 *
 * The host Activity owns everything that must run on the main thread or that
 * needs an `Activity` (the SAF picker result, `startActivity`, `PrintManager`,
 * `FileProvider`); this service owns the flow, the byte copy, the read-back
 * verification, and the catalog mapping. No method returns or throws a path.
 */
interface DeliveryHost {
    /**
     * Launches SAF `ACTION_CREATE_DOCUMENT` for `application/pdf`. Exactly one
     * callback with the chosen URI, or `null` when the user cancels.
     */
    fun pickSaveLocation(suggestedName: String, onResult: (Uri?) -> Unit)

    /** Opens the chosen URI for writing; `null` when the provider refuses. */
    fun openOutputStream(uri: Uri): OutputStream?

    /** Opens the chosen URI again for the byte-count verification. */
    fun openInputStream(uri: Uri): InputStream?

    /** Shares the artifact through a temporary `FileProvider` read grant. */
    fun shareArtifact(file: File, mimeType: String)

    /** Opens the system print UI for the artifact; false when no print service answers. */
    fun printArtifact(file: File, jobName: String): Boolean
}
