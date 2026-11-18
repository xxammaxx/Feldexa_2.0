package de.feldexa.app.import

import com.tom_roush.pdfbox.io.RandomAccessRead
import de.feldexa.app.OperationContext
import de.feldexa.app.PlatformFailure
import de.feldexa.app.PlatformRequest
import de.feldexa.app.PlatformService
import de.feldexa.app.pdf.PdfPageBox
import de.feldexa.app.pdf.PdfPageFailure
import de.feldexa.app.pdf.PdfPreflightFailure
import de.feldexa.app.pdf.PdfPreflightPage
import de.feldexa.app.pdf.PdfPreflightResult
import de.feldexa.app.pdf.PdfPreflightSuccess
import de.feldexa.app.storage.CanonicalJson
import de.feldexa.app.storage.ConcurrentSaveException
import de.feldexa.app.storage.CorruptDataException
import de.feldexa.app.storage.CreateReceipt
import de.feldexa.app.storage.EncryptedSourceReader
import de.feldexa.app.storage.InvalidDataException
import de.feldexa.app.storage.KeystoreUnavailableException
import de.feldexa.app.storage.KeyUnavailableException
import de.feldexa.app.storage.PlatformSecurityException
import de.feldexa.app.storage.SchemaTooNewException
import de.feldexa.app.storage.SourceLimitExceededException
import de.feldexa.app.storage.StagedSourceReceipt
import de.feldexa.app.storage.StorageFullException
import de.feldexa.app.storage.StorageWriteException
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID
import java.util.concurrent.CancellationException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * T038/T040 — SAF `ACTION_OPEN_DOCUMENT` streaming import (FR-001; FR-004;
 * FR-095/FR-096).
 *
 * This service is the `"import"` prefix owner of the T024 [PlatformService]
 * facade. It contains no UI, no file/path handling and no Flutter types: the
 * host Activity supplies a narrow [DocumentPicker] that launches the ordinary
 * Android document picker, and every picked byte is consumed exclusively
 * through [PickedDocument.openStream] (backed by `ContentResolver.openInputStream`).
 *
 * T040 makes the system's own protected copy the source of truth:
 *  1. [SourceStaging] reads the picked source in two bounded passes (64 KiB
 *     hash/count, then 1 MiB authenticated writes) and stages `src/<id>.fxc`
 *     without materializing the whole source or creating a plaintext temp file.
 *  2. [StagedPreflight] runs `PdfPreflight` over a decrypting, seekable
 *     `RandomAccessRead` on that staged ciphertext.
 *  3. Only after preflight succeeds is the initial revision and
 *     `meta.fx1`/`head.fx1` committed exactly once by [StagedCommit]. The
 *     aggregate becomes visible only after the store's verified read-back.
 *
 * A rejected or cancelled import removes the incomplete aggregate. A late
 * cancellation never deletes a committed, visible document. The picked file is
 * only ever opened read-only; it is never modified, rewritten, renamed, or
 * deleted (FR-004).
 *
 * Content rules follow `contracts/platform-channel.md` §2.2: no method result
 * or failure carries a URI, path, file name, document title, or source byte
 * content. The only content-bearing values produced here are the
 * contract-specified `displayName` in the *success* payload and the
 * corresponding default title/original-name metadata (§3); failures carry
 * catalog codes and stable machine keys only.
 */
class ImportService(
    private val picker: DocumentPicker,
    private val staging: SourceStaging,
    private val preflight: StagedPreflight,
    private val commit: StagedCommit,
    private val discard: StagedDiscard = StagedDiscard { },
    private val maxBytesCap: Long = DEFAULT_MAX_SOURCE_BYTES,
    private val idGenerator: () -> String = { UUID.randomUUID().toString() },
    private val clock: () -> Long = System::currentTimeMillis,
    private val pickerTimeoutMs: Long = DEFAULT_PICKER_TIMEOUT_MS,
) : PlatformService {

    override fun handle(request: PlatformRequest, context: OperationContext): Any? = when (request.method) {
        "import.pickAndImport" -> pickAndImport(request, context)
        // `import.verifySource` and the internal `import.discardStaged`
        // channel method are not part of T040's scope. They stay fail-closed
        // with a catalog-coded unsupported failure instead of inventing a
        // second wire contract.
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
        val revisionId = requireUuid(idGenerator())

        // The picker runs on the host main thread; the facade invokes the
        // service on a background worker. Deliver the picked document (or a
        // user cancellation) through a bounded wait so a lost callback can
        // never pin a worker forever, and so a cancelled operation aborts
        // promptly instead of waiting out the whole picker timeout.
        val picked = awaitPickedDocument(context) ?: throw PlatformFailure.cancelled()
        val displayName = sanitizeDisplayName(picked.displayName)

        // The first stream is the hash/count pass. A null stream is the
        // contract's missing-file case; open failures are unreadable.
        val countPass = try {
            picked.openStream()
        } catch (failure: IOException) {
            throw PlatformFailure("IMP-002", "unreadable", false, "import.unreadable")
        } catch (failure: SecurityException) {
            throw PlatformFailure("IMP-002", "unreadable", false, "import.unreadable")
        } ?: throw PlatformFailure("IMP-003", "missing", false, "import.missing")

        val receipt = try {
            staging.stage(
                documentId = documentId,
                sourceId = sourceId,
                countPass = countPass,
                openStreamForWrite = picked::openStream,
                maxBytes = maxBytes,
                shouldAbort = { cancellationRequested(context) },
            )
        } catch (failure: SourceLimitExceededException) {
            throw PlatformFailure("IMP-007", "tooLarge", false, "import.tooLarge")
        } catch (failure: CancellationException) {
            throw PlatformFailure.cancelled()
        } catch (failure: InvalidDataException) {
            throw PlatformFailure("IMP-002", "unreadable", false, "import.unreadable")
        } catch (failure: IOException) {
            throw PlatformFailure("IMP-002", "unreadable", false, "import.unreadable")
        } catch (failure: SecurityException) {
            throw PlatformFailure("IMP-002", "unreadable", false, "import.unreadable")
        } catch (failure: PlatformFailure) {
            throw failure
        } catch (failure: Exception) {
            throw mapStorageFailure(failure)
        } finally {
            // countPass is caller-owned by the SourceStaging contract: the
            // store only reads it, and this is its single close on every path
            // (success, validation/stage failure, and cancellation).
            runCatching { countPass.close() }
        }

        // One cleanup action covers the whole staged window. It is registered
        // immediately after a successful stage so a cancel that raced with the
        // stage itself is covered. The action and the commit share one lock:
        // cleanup can never delete the source while preflight or the commit is
        // reading it, and it becomes a no-op once meta.fx1 is visible.
        val lifecycle = StagedLifecycle()
        context.registerCancellationCleanup {
            lifecycle.lock.withLock {
                if (lifecycle.needsDiscard) {
                    lifecycle.needsDiscard = false
                    discardStagedAggregate(context, documentId)
                }
            }
        }

        // Preflight owns no storage: the production seam opens a decrypting
        // range reader over the staged ciphertext and hands it to PdfPreflight.
        // Hold the lifecycle lock across preflight and the commit so a claimed
        // cancellation can never delete the source while it is being read or
        // made visible. The registered cleanup waits on this lock and becomes
        // a no-op after a verified commit.
        val outcome = try {
            lifecycle.lock.withLock {
                if (!receipt.readBackVerified) throw PlatformFailure.internal()
                if (context.isCancellationClaimed) throw PlatformFailure.cancelled()
                val preflightResult = preflight.preflight(documentId, sourceId)
                if (preflightResult is PdfPreflightFailure) {
                    lifecycle.needsDiscard = false
                    val cleanupFailure = discardOnly(documentId)
                    throw cleanupFailure ?: preflightFailure(preflightResult)
                }
                val success = preflightResult as PdfPreflightSuccess
                if (context.isCancellationClaimed) throw PlatformFailure.cancelled()
                val importedAt = nowIso()
                val metaJson = buildMetaJson(
                    documentId = documentId,
                    sourceId = sourceId,
                    revisionId = revisionId,
                    sha256 = receipt.sourceSha256,
                    sizeBytes = receipt.sizeBytes,
                    pageCount = success.pageCount,
                    displayName = displayName,
                    importedAt = importedAt,
                )
                val revisionJson = buildRevisionJson(success)

                // The store checks shouldAbort before the revision, head, and
                // final meta promotion. A cancellation that wins before meta
                // is never visible as a document; the store removes the
                // unreferenced aggregate. A cancellation after the final meta
                // promotion cannot delete a committed document and is left to
                // the facade's exactly-once rule.
                val created = try {
                    val result = commit.commit(
                        documentId = documentId,
                        sourceId = sourceId,
                        sourceSha256 = receipt.sourceSha256,
                        sourceSizeBytes = receipt.sizeBytes,
                        revisionId = revisionId,
                        metaJson = metaJson,
                        revisionJson = revisionJson,
                        shouldAbort = { cancellationRequested(context) },
                    )
                    lifecycle.needsDiscard = false
                    result
                } catch (failure: CancellationException) {
                    // The store removed the staged aggregate before meta
                    // became visible; do not ask cleanup to delete it twice.
                    // Leave all operation-handle access to the outer catch:
                    // the facade cleanup holds the handle lock while waiting
                    // for this lifecycle lock, so reading the handle here would
                    // invert the lock order and deadlock.
                    lifecycle.needsDiscard = false
                    throw CommitCancelledException()
                } catch (failure: ConcurrentSaveException) {
                    // A visible aggregate owns this id. Never delete it.
                    lifecycle.needsDiscard = false
                    throw mapStorageFailure(failure)
                } catch (failure: PlatformFailure) {
                    lifecycle.needsDiscard = false
                    throw failure
                } catch (failure: Exception) {
                    // createDocumentFromStagedSource removes its unreferenced
                    // aggregate on every storage failure; no second delete.
                    lifecycle.needsDiscard = false
                    throw mapStorageFailure(failure)
                }
                success to created
            }
        } catch (failure: CommitCancelledException) {
            // The lifecycle lock is released here. Handle access is safe now:
            // if the facade cleanup is still waiting for that lock, it proceeds
            // and releases the handle; the store has already removed the
            // incomplete aggregate, so no cleanup residue is expected.
            throw context.cancellationCleanupFailure() ?: PlatformFailure.cancelled()
        } catch (failure: PlatformFailure) {
            val cleanupFailure = discardForFailure(context, lifecycle, documentId)
            if (cleanupFailure != null && failure.code == "PLT-004") throw cleanupFailure
            throw failure
        } catch (failure: Exception) {
            val mapped = mapStorageFailure(failure)
            val cleanupFailure = discardForFailure(context, lifecycle, documentId)
            throw cleanupFailure ?: mapped
        }
        val success = outcome.first
        val created = outcome.second

        if (!created.readBackVerified) throw PlatformFailure.internal()

        // Terminal `import.pickAndImport` data (`platform-channel.md` §3).
        // The page list always carries geometry in the contract's shape;
        // unreadable pages additionally carry `unreadable: true` and appear in
        // `pageFailures`. The facade adds the success envelope and publishes
        // exactly one terminal result; this service never publishes one.
        return linkedMapOf(
            "sourceId" to created.sourceId,
            "documentId" to created.aggregateId,
            "sha256" to created.sourceSha256,
            "sizeBytes" to receipt.sizeBytes,
            "pageCount" to success.pageCount,
            "pages" to success.pages.map(::pageResultMap),
            "pageFailures" to success.pageFailures.map(::pageFailureMap),
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

    /**
     * Runs inside the operation handle's cancellation linearization. The
     * incomplete staged aggregate has no meta, so the existing destructive
     * delete seam is confirmed with the localized "not readable" title; no new
     * store method is introduced. A failure is recorded on the handle so the
     * terminal result is a non-cancelled storage failure instead of a clean
     * PLT-004 while the aggregate is retained.
     */
    private fun discardStagedAggregate(
        context: OperationContext,
        documentId: String,
    ): PlatformFailure? = try {
        discard.discard(documentId)
        null
    } catch (failure: PlatformFailure) {
        context.recordCancellationCleanupFailure(failure)
        failure
    } catch (failure: Exception) {
        val mapped = mapStorageFailure(failure)
        context.recordCancellationCleanupFailure(mapped)
        mapped
    } catch (failure: Throwable) {
        val mapped = PlatformFailure.internal()
        context.recordCancellationCleanupFailure(mapped)
        mapped
    }

    /**
     * Non-throwing cancellation probe for the storage seams.
     *
     * [OperationContext.isCancellationClaimed] reads the handle's
     * `claimDecided` `AtomicBoolean` and never acquires the operation-handle
     * lock. It is therefore safe while this service holds the lifecycle lock.
     * All lock-taking handle access (`cancellationCleanupFailure`,
     * `recordCancellationCleanupFailure`) happens outside that lock.
     */
    private fun cancellationRequested(context: OperationContext): Boolean =
        context.isCancellationClaimed

    /**
     * Discards the staged aggregate without recording on the operation handle.
     * The caller must record outside the lifecycle lock: the facade's cleanup
     * thread may already hold the handle lock while waiting for that same
     * lifecycle lock.
     */
    private fun discardOnly(documentId: String): PlatformFailure? = try {
        discard.discard(documentId)
        null
    } catch (failure: PlatformFailure) {
        failure
    } catch (failure: Exception) {
        mapStorageFailure(failure)
    } catch (failure: Throwable) {
        PlatformFailure.internal()
    }

    private fun discardForFailure(
        context: OperationContext,
        lifecycle: StagedLifecycle,
        documentId: String,
    ): PlatformFailure? {
        var failure: PlatformFailure? = null
        lifecycle.lock.withLock {
            if (lifecycle.needsDiscard) {
                lifecycle.needsDiscard = false
                failure = discardOnly(documentId)
            }
        }
        // Record only after releasing the lifecycle lock, so a concurrent
        // facade cleanup holding the handle lock can never deadlock.
        failure?.let(context::recordCancellationCleanupFailure)
        return failure
    }

    private fun awaitPickedDocument(context: OperationContext): PickedDocument? {
        val latch = CountDownLatch(1)
        val result = AtomicReference<PickedDocument?>()
        picker.pick { picked ->
            result.set(picked)
            latch.countDown()
        }
        val deadlineNanos = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(pickerTimeoutMs)
        while (true) {
            // Slice the wait so a cancelled operation is observed promptly; the
            // overall picker timeout is still the hard bound, and the loop does
            // not busy-spin.
            context.checkCancelled()
            val remainingNanos = deadlineNanos - System.nanoTime()
            if (remainingNanos <= 0L) throw PlatformFailure.cancelled()
            val sliceNanos = minOf(remainingNanos, PICKER_WAIT_SLICE_NANOS)
            if (latch.await(sliceNanos, TimeUnit.NANOSECONDS)) break
        }
        context.checkCancelled()
        return result.get()
    }

    private fun requireUuid(value: String): String {
        if (!UUID_V4.matches(value.lowercase(Locale.ROOT))) throw PlatformFailure.internal()
        return value
    }

    // ------------------------------------------------------------------
    // Canonical initial revision and metadata
    // ------------------------------------------------------------------

    private fun buildMetaJson(
        documentId: String,
        sourceId: String,
        revisionId: String,
        sha256: String,
        sizeBytes: Long,
        pageCount: Int,
        displayName: String?,
        importedAt: String,
    ): ByteArray = CanonicalJson.encode(
        linkedMapOf(
            "id" to documentId,
            "kind" to "document",
            "title" to titleFrom(displayName),
            "createdAt" to importedAt,
            "updatedAt" to importedAt,
            "source" to linkedMapOf(
                "id" to sourceId,
                "sha256" to sha256,
                "sizeBytes" to sizeBytes,
                "pageCount" to pageCount,
                "originalName" to displayName,
                "importedAt" to importedAt,
                "integrity" to "verified",
            ),
            "latestRevisionId" to revisionId,
            "lastDurableAt" to importedAt,
            "readable" to true,
            "unreadableReasonCode" to null,
        ),
    )

    private fun buildRevisionJson(success: PdfPreflightSuccess): ByteArray = CanonicalJson.encode(
        linkedMapOf(
            "pages" to success.pages.map(::revisionPageMap),
            "suggestions" to emptyList<Any?>(),
            "fields" to emptyList<Any?>(),
            "fieldOrder" to emptyList<Any?>(),
            "values" to emptyMap<String, Any?>(),
            "signatures" to emptyMap<String, Any?>(),
            "verification" to emptyMap<String, Any?>(),
            "templateOrigin" to null,
        ),
    )

    private fun revisionPageMap(page: PdfPreflightPage): Map<String, Any?> = linkedMapOf(
        "index" to page.pageIndex,
        "geometry" to geometryMap(page),
        "analysis" to if (page.unreadable) "failed" else "pending",
        "failure" to page.pageFailure?.let(::pageFailureMap),
        "unreadable" to page.unreadable,
    )

    private fun pageResultMap(page: PdfPreflightPage): Map<String, Any?> {
        val result = LinkedHashMap<String, Any?>(geometryMap(page))
        // The contract adds `unreadable: true` for an IMP-006 page. Readable
        // pages stay in the exact `PageGeometry` shape the Dart client parses.
        if (page.unreadable) result["unreadable"] = true
        return result
    }

    /**
     * T039 reports null geometry for a page whose structure could not be read.
     * The persisted `Page` and the channel page shape still need a positive
     * box. A 1x1 placeholder is used only for such an unreadable page, which
     * is always marked `unreadable = true` and carries its `IMP-006` failure;
     * it is never presented as the original page geometry. T042/T044 must
     * treat an unreadable page as non-renderable content, not as a real 1x1
     * page.
     */
    private fun geometryMap(page: PdfPreflightPage): Map<String, Any?> {
        val media = page.mediaBox ?: UNREADABLE_PAGE_PLACEHOLDER_BOX
        val crop = page.cropBox ?: media
        return linkedMapOf(
            "mediaBox" to boxMap(media),
            "cropBox" to boxMap(crop),
            "rotation" to (page.rotation ?: 0),
        )
    }

    private fun boxMap(box: PdfPageBox): Map<String, Any?> = linkedMapOf(
        "x" to box.x,
        "y" to box.y,
        "width" to box.width,
        "height" to box.height,
    )

    private fun pageFailureMap(failure: PdfPageFailure): Map<String, Any?> = linkedMapOf(
        "pageIndex" to failure.pageIndex,
        "category" to failure.category,
        "messageKey" to failure.messageKey,
    )

    private fun preflightFailure(failure: PdfPreflightFailure): PlatformFailure = PlatformFailure(
        code = failure.code,
        category = failure.category,
        retryable = failure.retryable,
        machineMessage = failure.message,
        pageIndex = failure.pageIndex,
        durationMs = failure.durationMs,
    )

    private fun titleFrom(displayName: String?): String {
        val base = displayName
            ?.substringAfterLast('/')
            ?.substringAfterLast('\\')
            ?.trim()
            .orEmpty()
        val withoutExtension = base.substringBeforeLast('.', base).trim()
        val candidate = withoutExtension.ifEmpty { DEFAULT_TITLE }
        return candidate.take(MAX_TITLE_LENGTH).ifEmpty { DEFAULT_TITLE }
    }

    private fun sanitizeDisplayName(raw: String?): String? {
        val trimmed = raw?.trim() ?: return null
        if (trimmed.isEmpty()) return null
        val clean = trimmed.filterNot { it == '\u0000' || Character.isISOControl(it) }
        if (clean.isEmpty()) return null
        return clean.take(MAX_ORIGINAL_NAME_LENGTH)
    }

    private fun nowIso(): String = ISO_MILLIS.format(Instant.ofEpochMilli(clock()))

    /** Same content-free storage mapping as StoreService; no source byte leaks. */
    private fun mapStorageFailure(failure: Exception): PlatformFailure = when (failure) {
        is PlatformSecurityException -> PlatformFailure.invalidIdentifier()
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

    /**
     * Marker used inside the lifecycle lock so the cancellation-failure read
     * happens only after that lock is released. It never crosses the service
     * boundary.
     */
    private class CommitCancelledException : Exception("importCancelled")

    private class StagedLifecycle {
        val lock = ReentrantLock()

        /** True until the staged aggregate is committed or a cleanup ran. */
        var needsDiscard = true
    }

    companion object {
        /** `contracts/platform-channel.md` §10 / `storage-format.md` §3.2: 80 MiB. */
        const val DEFAULT_MAX_SOURCE_BYTES: Long = 83_886_080L

        /** Bounded read chunk; the picked source is never read whole. */
        const val CHUNK_BYTES: Int = 64 * 1024

        // Neutral fallback when the provider supplies no display name. T041
        // owns any localized default title wording; this task adds no German
        // UI text.
        private const val DEFAULT_TITLE = "PDF"
        private const val MAX_TITLE_LENGTH = 200
        private const val MAX_ORIGINAL_NAME_LENGTH = 255

        private const val DEFAULT_PICKER_TIMEOUT_MS: Long = 10L * 60L * 1_000L

        /** Cancellation is observed at least this often while awaiting the picker. */
        private val PICKER_WAIT_SLICE_NANOS: Long = TimeUnit.MILLISECONDS.toNanos(100L)

        private val UNREADABLE_PAGE_PLACEHOLDER_BOX = PdfPageBox(0.0, 0.0, 1.0, 1.0)

        private val ISO_MILLIS: DateTimeFormatter =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)

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

/**
 * T040 streaming staging seam.
 *
 * [countPass] is **caller-owned**: the seam reads it for SHA-256/size but does
 * not close it; the import service's `finally` closes it exactly once. The
 * stream returned by [openStreamForWrite] is **callee-owned**: the store wraps
 * it in exactly one `use` and closes it exactly once on every path, including
 * pre-container failures and write-pass cancellation. The picked source is
 * never modified and no plaintext temp file is created.
 */
fun interface SourceStaging {
    fun stage(
        documentId: String,
        sourceId: String,
        countPass: InputStream,
        openStreamForWrite: () -> InputStream?,
        maxBytes: Long,
        shouldAbort: () -> Boolean,
    ): StagedSourceReceipt
}

/** Preflight over the staged ciphertext through a decrypting reader. */
fun interface StagedPreflight {
    fun preflight(documentId: String, sourceId: String): PdfPreflightResult
}

/** Verified initial-revision/meta commit for an already staged source. */
fun interface StagedCommit {
    fun commit(
        documentId: String,
        sourceId: String,
        sourceSha256: String,
        sourceSizeBytes: Long,
        revisionId: String,
        metaJson: ByteArray,
        revisionJson: ByteArray,
        shouldAbort: () -> Boolean,
    ): CreateReceipt
}

/** Cleanup of an incomplete staged aggregate through the existing delete seam. */
fun interface StagedDiscard {
    fun discard(documentId: String)
}

/**
 * T040: adapts a storage [EncryptedSourceReader] to PDFBox's
 * `RandomAccessRead` without a plaintext copy or temporary file.
 *
 * The adapter implements every `RandomAccessRead` method used by PDFBox 2.0.27
 * and delegates chunk authentication/decryption to the store reader. Closing
 * the adapter closes the underlying reader; `PdfPreflight` never closes its
 * caller-owned reader.
 */
class EncryptedSourceRandomAccess(
    private val reader: EncryptedSourceReader,
) : RandomAccessRead {

    override fun read(): Int {
        val one = ByteArray(1)
        val count = reader.read(one, 0, 1)
        return if (count <= 0) -1 else one[0].toInt() and 0xFF
    }

    override fun read(buffer: ByteArray): Int = read(buffer, 0, buffer.size)

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int =
        reader.read(buffer, offset, length)

    override fun getPosition(): Long = reader.position

    override fun seek(position: Long) = reader.seek(position)

    override fun length(): Long = reader.length

    override fun isClosed(): Boolean = reader.isClosed

    override fun peek(): Int {
        val position = reader.position
        val value = read()
        reader.seek(position)
        return value
    }

    override fun rewind(pointer: Int) {
        if (pointer < 0) throw IOException("rewind")
        reader.seek((reader.position - pointer).coerceAtLeast(0L))
    }

    override fun readFully(length: Int): ByteArray {
        if (length < 0) throw IOException("length")
        val out = ByteArray(length)
        var read = 0
        while (read < length) {
            val count = read(out, read, length - read)
            if (count < 0) throw EOFException()
            read += count
        }
        return out
    }

    override fun isEOF(): Boolean = reader.position >= reader.length

    override fun available(): Int =
        (reader.length - reader.position).coerceIn(0L, Int.MAX_VALUE.toLong()).toInt()

    override fun close() = reader.close()
}
