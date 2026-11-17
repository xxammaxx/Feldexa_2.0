package de.feldexa.app.import

import de.feldexa.app.OperationContext
import de.feldexa.app.PlatformFailure
import de.feldexa.app.PlatformRequest
import de.feldexa.app.PlatformService
import de.feldexa.app.storage.ConcurrentSaveException
import de.feldexa.app.storage.CorruptDataException
import de.feldexa.app.storage.InvalidDataException
import de.feldexa.app.storage.KeystoreUnavailableException
import de.feldexa.app.storage.KeyUnavailableException
import de.feldexa.app.storage.SchemaTooNewException
import de.feldexa.app.storage.StagedSourceReceipt
import de.feldexa.app.storage.StorageFullException
import de.feldexa.app.storage.StorageWriteException
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * T038 — SAF `ACTION_OPEN_DOCUMENT` streaming import (FR-001; FR-095).
 *
 * This service is the `"import"` prefix owner of the T024 [PlatformService]
 * facade. It contains no UI, no file/path handling and no Flutter types: the
 * host Activity supplies a narrow [DocumentPicker] that launches the ordinary
 * Android document picker, and every picked byte is consumed exclusively
 * through [PickedDocument.openStream] (backed by `ContentResolver.openInputStream`).
 *
 * The picked stream is read in bounded chunks, counted and hashed while it is
 * read, and staged through the existing `EncryptedStore.stageSource` seam
 * ([SourceStaging]). `EncryptedStore.stageSource` writes an encrypted,
 * read-back-verified source object but deliberately leaves the aggregate
 * incomplete (no `meta.fx1`/`head.fx1`), so a stage that is rejected or
 * cancelled never becomes a visible document (FR-009). The true streaming
 * encrypted copy and the import commit remain T040; PDF preflight, page
 * geometry and encryption detection remain T039; the German error mapping
 * remains T041. This task does not change the IMP-007 wording, its ARB key,
 * or the error catalog (T045).
 *
 * Content rules follow `contracts/platform-channel.md` §2.2: no method result
 * or failure carries a URI, path, file name, document title, or source byte
 * content. The only content-bearing value produced here is the
 * contract-specified `displayName` in the *success* payload (§3). Failures
 * carry catalog codes and stable machine keys only.
 */
class ImportService(
    private val picker: DocumentPicker,
    private val staging: SourceStaging,
    private val discard: StagedDiscard = StagedDiscard { },
    private val maxBytesCap: Long = DEFAULT_MAX_SOURCE_BYTES,
    private val idGenerator: () -> String = { UUID.randomUUID().toString() },
    private val pickerTimeoutMs: Long = DEFAULT_PICKER_TIMEOUT_MS,
) : PlatformService {

    override fun handle(request: PlatformRequest, context: OperationContext): Any? = when (request.method) {
        "import.pickAndImport" -> pickAndImport(request, context)
        // T039/T040 own verifySource; T040 owns staged cleanup. Both stay
        // fail-closed with a catalog-coded unsupported failure until then —
        // no wire shape is invented here.
        "import.verifySource",
        "import.discardStaged",
        -> throw PlatformFailure.unsupported()
        else -> throw PlatformFailure.unsupported()
    }

    override fun onFacadeDetached() {
        // Import holds no long-lived PDF/storage handle; the picker callback
        // is owned by the host Activity and cleared there on teardown.
    }

    private fun pickAndImport(request: PlatformRequest, context: OperationContext): Map<String, Any?> {
        val maxBytes = effectiveMaxBytes(request)
        val documentId = requireUuid(idGenerator())
        val sourceId = requireUuid(idGenerator())

        // The picker runs on the host main thread; the facade invokes the
        // service on a background worker. Deliver the picked document (or a
        // user cancellation) through a bounded wait so a lost callback can
        // never pin a worker forever.
        val picked = awaitPickedDocument() ?: throw PlatformFailure.cancelled()
        val displayName = picked.displayName

        val digest = MessageDigest.getInstance("SHA-256")
        val materialized = ByteArrayOutputStream(CHUNK_BYTES.coerceAtMost(maxBytes.toInt()))
        var total = 0L
        try {
            val stream = picked.openStream()
                ?: throw PlatformFailure("IMP-003", "missing", false, "import.missing")
            stream.use { input ->
                val chunk = ByteArray(CHUNK_BYTES)
                while (true) {
                    context.checkCancelled()
                    val read = input.read(chunk)
                    if (read < 0) break
                    if (read == 0) continue
                    if (total + read > maxBytes) {
                        // Existing IMP-007 mapping (category/machine key are
                        // already in the facade allowlist); no T045 wording.
                        throw PlatformFailure("IMP-007", "tooLarge", false, "import.tooLarge")
                    }
                    digest.update(chunk, 0, read)
                    materialized.write(chunk, 0, read)
                    total += read
                }
            }
        } catch (failure: PlatformFailure) {
            throw failure
        } catch (failure: IOException) {
            throw PlatformFailure("IMP-002", "unreadable", false, "import.unreadable")
        } catch (failure: SecurityException) {
            throw PlatformFailure("IMP-002", "unreadable", false, "import.unreadable")
        }

        // No cancellation may win between the last chunk and the encrypted
        // stage, and none may leave a staged object behind unchecked.
        context.checkCancelled()
        val sha256 = hex(digest.digest())
        val bytes = materialized.toByteArray()
        val receipt = try {
            staging.stage(documentId, sourceId, bytes, sha256)
        } catch (failure: PlatformFailure) {
            throw failure
        } catch (failure: Exception) {
            throw mapStorageFailure(failure)
        }

        if (context.isCancelled) {
            // An incomplete staged aggregate has no meta, so the existing
            // destructive-delete seam is confirmed with the localized
            // "not readable" title; no new store method is introduced.
            runCatching { discard.discard(documentId) }
            context.checkCancelled()
        }
        if (!receipt.readBackVerified) throw PlatformFailure.internal()

        // T038 can produce source/document identity, hash, size and the picked
        // display name. pageCount/pages are T039 (PDF preflight) outputs and
        // are intentionally absent until that task exists. The facade adds the
        // envelope and publishes exactly one terminal result; this service
        // never publishes one itself.
        return linkedMapOf(
            "sourceId" to receipt.sourceId,
            "documentId" to receipt.aggregateId,
            "sha256" to receipt.sourceSha256,
            "sizeBytes" to receipt.sizeBytes,
            "displayName" to displayName,
        )
    }

    private fun effectiveMaxBytes(request: PlatformRequest): Long {
        val requested = request.number("maxBytes")?.toLong()
        return when {
            requested == null || requested <= 0L -> DEFAULT_MAX_SOURCE_BYTES
            requested > maxBytesCap -> maxBytesCap
            else -> requested
        }
    }

    private fun awaitPickedDocument(): PickedDocument? {
        val latch = CountDownLatch(1)
        val result = AtomicReference<PickedDocument?>()
        picker.pick { picked ->
            result.set(picked)
            latch.countDown()
        }
        if (!latch.await(pickerTimeoutMs, TimeUnit.MILLISECONDS)) {
            throw PlatformFailure.cancelled()
        }
        return result.get()
    }

    private fun requireUuid(value: String): String {
        if (!UUID_V4.matches(value.lowercase(Locale.ROOT))) throw PlatformFailure.internal()
        return value
    }

    private fun hex(bytes: ByteArray): String =
        bytes.joinToString("") { "%02x".format(it.toInt() and 0xFF) }

    /** Same content-free mapping as StoreService; no source byte is leaked. */
    private fun mapStorageFailure(failure: Exception): PlatformFailure = when (failure) {
        is StorageFullException -> PlatformFailure("SAVE-001", "storageFull", true, "save.storageFull")
        is StorageWriteException -> PlatformFailure("SAVE-003", "corruptData", true, "save.writeFailed")
        is KeyUnavailableException -> PlatformFailure("SAVE-002", "keyUnavailable", false, "save.keyUnavailable")
        is KeystoreUnavailableException -> PlatformFailure(
            "SAVE-008", "keystoreUnavailable", failure.retryable, "save.keystoreUnavailable",
        )
        is CorruptDataException -> PlatformFailure("SAVE-003", "corruptData", false, "save.corruptData")
        is SchemaTooNewException -> PlatformFailure("SAVE-005", "schemaTooNew", false, "save.schemaTooNew")
        is ConcurrentSaveException -> PlatformFailure("SAVE-006", "concurrentWrite", true, "save.concurrentWrite")
        is InvalidDataException -> PlatformFailure("SAVE-007", "invalidData", false, "save.invalidData")
        else -> PlatformFailure.internal()
    }

    companion object {
        /** `contracts/platform-channel.md` §10 / `storage-format.md` §3.2: 80 MiB. */
        const val DEFAULT_MAX_SOURCE_BYTES: Long = 80L * 1024L * 1024L

        /** Bounded read chunk; the stream is never read whole in one call. */
        const val CHUNK_BYTES: Int = 64 * 1024

        private const val DEFAULT_PICKER_TIMEOUT_MS: Long = 10L * 60L * 1_000L

        private val UUID_V4 = Regex(
            "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
        )
    }
}

/** Narrow, injectable seam over the host's `ActivityResultContracts.OpenDocument`. */
fun interface DocumentPicker {
    /**
     * Launches the system document picker. Exactly one callback is expected:
     * the picked document, or `null` when the user cancels. The host invokes
     * the callback on its main thread.
     */
    fun pick(onResult: (PickedDocument?) -> Unit)
}

/** Narrow view of a picked content URI; no path or `File` is ever exposed. */
interface PickedDocument {
    /** Opens the content with `ContentResolver.openInputStream`; may be null. */
    fun openStream(): InputStream?

    /** Content-free display name for the success payload; no path/URI. */
    val displayName: String?
}

/** The existing `EncryptedStore.stageSource` seam, injected for testability. */
fun interface SourceStaging {
    fun stage(
        documentId: String,
        sourceId: String,
        bytes: ByteArray,
        expectedSha256: String?,
    ): StagedSourceReceipt
}

/** Cleanup of an incomplete staged aggregate through the existing delete seam. */
fun interface StagedDiscard {
    fun discard(documentId: String)
}
