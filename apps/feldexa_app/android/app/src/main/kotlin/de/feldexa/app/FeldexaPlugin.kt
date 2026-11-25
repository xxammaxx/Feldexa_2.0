package de.feldexa.app

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.math.BigDecimal
import java.math.BigInteger
import java.util.ArrayDeque
import java.util.LinkedHashMap
import java.util.UUID
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.CancellationException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * T024: the single Flutter <-> Android platform facade.
 *
 * Contract: `specs/001-scanned-form-workflow/contracts/platform-channel.md`.
 *
 * This file deliberately contains only the channel boundary and its validation,
 * error, threading, cancellation, start/result, event, and lifecycle machinery.
 * Asynchronous methods return a reliable start reply with an operation id; their
 * terminal data is delivered on `de.feldexa/results`. It contains no UI, form,
 * geometry, layout, OCR, storage, or PDF implementation: the later
 * service tasks register a [PlatformService] per method prefix through
 * [FeldexaPlugin.registerService]. Until a prefix is registered, its methods
 * fail closed with `PLT-001` instead of pretending a capability exists.
 *
 * Security and logging rules enforced here: no request payload, document title,
 * path, URI, OCR text, field value, signature byte, or page image is ever put in
 * an error message or details map, and this facade performs no payload logging.
 */
class FeldexaPlugin internal constructor(
    private val limits: ChannelLimits = ChannelLimits(),
) : FlutterPlugin, ActivityAware {

    private val mainPoster: ThreadPoster = AndroidMainThreadPoster()
    private val pendingServices = mutableListOf<Pair<String, PlatformService>>()
    private val pendingImportMessengers = mutableListOf<BinaryMessenger>()
    private val registrationLock = Any()

    private var facade: PlatformChannelFacade? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var resultChannel: EventChannel? = null
    private var importChannel: MethodChannel? = null
    private var activityBinding: ActivityPluginBinding? = null

    /** Current host Activity, if the plugin is attached to one. */
    val activity: android.app.Activity?
        get() = activityBinding?.activity

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        synchronized(registrationLock) {
            if (facade != null) return

            val publisher = PlatformEventPublisher(mainPoster)
            val results = PlatformResultPublisher(mainPoster)
            val created = PlatformChannelFacade(
                mainPoster = mainPoster,
                events = publisher,
                results = results,
                limits = limits,
                // §11 point 7: the activity owns the window; without one the
                // route is reported as not protected.
                sensitiveRoute = { activity as? SensitiveRouteHost },
            )
            facade = created

            methodChannel = MethodChannel(
                binding.binaryMessenger,
                FeldexaChannels.PLATFORM,
            ).also { channel ->
                channel.setMethodCallHandler { call, result ->
                    created.handle(call.method, call.arguments, FlutterChannelReply(result))
                }
            }
            eventChannel = EventChannel(
                binding.binaryMessenger,
                FeldexaChannels.EVENTS,
            ).also { channel ->
                channel.setStreamHandler(FlutterEventStreamHandler(publisher::attachSink))
            }
            resultChannel = EventChannel(
                binding.binaryMessenger,
                FeldexaChannels.RESULTS,
            ).also { channel ->
                channel.setStreamHandler(FlutterEventStreamHandler(results::attachSink))
            }

            pendingServices.forEach { (prefix, service) ->
                created.services.register(prefix, service)
            }
            pendingServices.clear()

            val importMessengers = pendingImportMessengers.toList()
            pendingImportMessengers.clear()
            importMessengers.forEach(::registerImportChannel)
        }
    }

    /**
     * Registers `de.feldexa/import`. The contract assigns this activity-bound
     * channel to MainActivity, so the host calls this after adding the plugin to
     * the engine. The method is idempotent and safe to call before engine
     * attachment (the messenger is remembered).
     */
    fun registerImportChannel(messenger: BinaryMessenger) {
        synchronized(registrationLock) {
            val created = facade
            if (created == null) {
                pendingImportMessengers += messenger
                return
            }
            if (importChannel != null) return
            importChannel = MethodChannel(messenger, FeldexaChannels.IMPORT).also { channel ->
                channel.setMethodCallHandler { call, result ->
                    created.handle(call.method, call.arguments, FlutterChannelReply(result))
                }
            }
        }
    }

    /**
     * Registers the service that owns [prefix] (`import`, `store`, `ocr`,
     * `export`, or `delivery`). T025/T026/T038-T040 use this seam; the facade
     * validates and envelopes every call before the service sees it.
     */
    fun registerService(prefix: String, service: PlatformService) {
        synchronized(registrationLock) {
            val created = facade
            if (created == null) {
                pendingServices += prefix to service
            } else {
                created.services.register(prefix, service)
            }
        }
    }

    /** Forwards the Android host lifecycle to Dart as the contract-defined event. */
    fun onHostLifecycle(lifecycle: HostLifecycle) {
        val created = facade ?: return
        created.events.emitLifecycle(lifecycle)
        if (lifecycle == HostLifecycle.DETACHED) {
            created.dispose()
        }
    }

    /** Emits the contract's `storage.status` event. Never includes a title. */
    fun emitStorageStatus(
        scope: String,
        kind: String?,
        itemId: String?,
        keyAvailable: Boolean,
        reasonCode: String?,
    ) {
        facade?.events?.emitStorageStatus(scope, kind, itemId, keyAvailable, reasonCode)
    }

    /** Emits the contract's `import.pickerResult` event. */
    fun emitImportPickerResult(correlationId: String, cancelled: Boolean) {
        facade?.events?.emitImportPickerResult(correlationId, cancelled)
    }

    /**
     * Stops channel work. The method channel itself is removed by the Flutter
     * engine on detach; this only makes the facade fail closed from now on and
     * cancels the bounded executor so no service keeps decrypting, parsing, or
     * writing during destruction. Idempotent.
     */
    fun dispose() {
        facade?.dispose()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        synchronized(registrationLock) {
            methodChannel?.setMethodCallHandler(null)
            eventChannel?.setStreamHandler(null)
            resultChannel?.setStreamHandler(null)
            importChannel?.setMethodCallHandler(null)
            methodChannel = null
            eventChannel = null
            resultChannel = null
            importChannel = null
            pendingImportMessengers.clear()
            facade?.dispose()
            facade = null
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivity() {
        activityBinding = null
    }

    private class FlutterChannelReply(
        private val methodResult: MethodChannel.Result,
    ) : ChannelReply {
        override fun success(result: Any?) {
            methodResult.success(result)
        }

        override fun error(failure: PlatformFailure) {
            methodResult.error(failure.code, failure.machineMessage, failure.details())
        }
    }

    private class FlutterEventStreamHandler(
        private val attachSink: (FeldexaEventSink?) -> Unit,
    ) : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            attachSink(events?.let { sink -> FeldexaEventSink { sink.success(it) } })
        }

        override fun onCancel(arguments: Any?) {
            attachSink(null)
        }
    }
}

/** Channel names from `contracts/platform-channel.md` §1. */
object FeldexaChannels {
    const val PLATFORM = "de.feldexa/platform"
    const val EVENTS = "de.feldexa/events"
    const val RESULTS = "de.feldexa/results"
    const val IMPORT = "de.feldexa/import"
    const val SCHEMA_VERSION = 1
}

/**
 * Methods that use the owner-authorized start/result protocol: the MethodChannel
 * reply is the start reply `{operationId}`; the method-specific data is delivered
 * later as a terminal `operation.result` on `de.feldexa/results`.
 */
private val ASYNC_METHODS: Set<String> = setOf(
    "import.pickAndImport",
    "import.verifySource",
    "store.saveRevision",
    "store.writeSignature",
    "store.createTemplate",
    "store.saveTemplateVersion",
    "ocr.recognize",
    "export.validate",
    "export.render",
)

/** Host lifecycle values accepted by the `lifecycle` event (§8). */
enum class HostLifecycle(val wireValue: String) {
    RESUMED("resumed"),
    INACTIVE("inactive"),
    PAUSED("paused"),
    DETACHED("detached"),
}

/**
 * Every catalog code from `contracts/error-catalog.de.md` plus the developer
 * codes in §10 of the same catalog. A service may not invent a code.
 */
private val CATALOG_CODES: Set<String> = setOf(
    "DATE-001", "DATE-002",
    "DEL-001", "DEL-002", "DEL-003",
    "EXP-001", "EXP-002", "EXP-003", "EXP-004", "EXP-005", "EXP-006",
    "FLD-001", "FLD-002", "FLD-003",
    "IMP-000", "IMP-001", "IMP-002", "IMP-003", "IMP-004", "IMP-005", "IMP-006", "IMP-007",
    "NUM-001",
    "PAGE-001",
    "PLT-001", "PLT-002", "PLT-003", "PLT-004",
    "PRIV-001",
    "REC-001", "REC-002", "REC-003", "REC-004",
    "SAVE-001", "SAVE-002", "SAVE-003", "SAVE-004", "SAVE-005", "SAVE-006", "SAVE-007", "SAVE-008",
    "SIM-001",
    "TPL-001", "TPL-002", "TPL-003",
)

/**
 * Closed category allowlist. A category names an error class, never a title,
 * field label, path, URI, OCR text, or field value (§2.2).
 */
private val ALLOWED_CATEGORIES: Set<String> = setOf(
    "storageFull", "invalidPayload", "invalidIdentifier", "unsupported", "cancelled",
    "internalError", "capacity", "invalidData", "concurrentWrite", "keyUnavailable",
    "keystoreUnavailable", "corruptData", "schemaTooNew", "importRejected", "unreadable",
    "missing", "notPdf", "tooLarge", "exportBlocked", "exportFailed", "ocrUnavailable",
    "ocrFailed", "renderFailed", "deliveryUnavailable", "privacy", "simulated",
    "geometryInvalid", "missingGlyph", "sourceUnreadable", "pageNotCopiable",
    "deliveryCancelled", "invalidRaster",
)

/** Stable message key shape; the exact key must also be in the allowlist below. */
private val MACHINE_MESSAGE_PATTERN = Regex("^[a-z][A-Za-z0-9]*(?:[._:-][a-z][A-Za-z0-9]*){1,5}$")

/**
 * Closed, content-free machine-message allowlist. The namespace is not enough:
 * `save.antrag` must be rejected just like `antrag.secret`. A new catalog mapping
 * must add its exact key here deliberately; arbitrary suffixes never pass.
 */
private val ALLOWED_MACHINE_MESSAGES: Set<String> = setOf(
    // platform/facade validation
    "platform.invalidPayload", "platform.identifier", "platform.unsupported",
    "platform.cancelled", "platform.internal", "platform.busy",
    "platform.payloadNotMap", "platform.nonStringKey", "platform.unknownField",
    "platform.payloadTooLarge", "platform.schemaVersionMissing",
    "platform.schemaVersionUnsupported", "platform.payloadTooDeep",
    "platform.unsupportedValue", "platform.missingField", "platform.invalidString",
    "platform.invalidInteger", "platform.valueOutOfRange", "platform.invalidNumber",
    "platform.invalidMap", "platform.invalidEnum", "platform.invalidHash",
    "platform.invalidConfirmation", "platform.invalidRaster",
    // stable domain mappings used by the catalog/tests
    "save.invalidData", "save.concurrentWrite", "save.noSpace", "save.storageFull",
    "save.keyUnavailable", "save.corruptData", "save.writeFailed",
    "save.schemaTooNew", "save.keystoreUnavailable",
    "import.passwordProtected", "import.unreadable", "import.missing", "import.notPdf",
    // T040: T039's precise IMP-001/IMP-004 distinctions must survive the
    // channel without over-claiming password protection or not-PDF.
    "import.unsupportedEncryption", "import.unsupportedStructure",
    "import.unknown", "import.partiallyUnreadable", "import.tooLarge", "import.cancelled",
    "export.blocked", "export.failed", "export.geometryInvalid", "export.missingGlyph",
    "export.sourceUnreadable", "export.pageNotCopiable", "export.cancelled",
    "ocr.unavailable", "ocr.failed", "page.renderFailed", "page.unreadable",
    "page.unsupported", "delivery.cancelled", "delivery.failed", "delivery.unavailable",
    "template.invalid", "template.versionConflict", "template.notFound",
    "date.invalid", "number.invalid", "field.invalid", "field.overflow",
    "privacy.redaction", "simulated.capability",
)

/**
 * A safe, catalog-coded platform failure. Only codes, counts, and durations may
 * cross this type; document content, paths, URIs, and German UI text may not.
 */
class PlatformFailure(
    val code: String,
    val category: String,
    val retryable: Boolean,
    val machineMessage: String,
    val pageIndex: Int? = null,
    val fieldCount: Int? = null,
    val durationMs: Long? = null,
) : RuntimeException(machineMessage) {

    init {
        require(code in CATALOG_CODES) { "code is not a catalog code" }
        require(category in ALLOWED_CATEGORIES) { "category is not in the allowlist" }
        require(machineMessage.length <= 64 && MACHINE_MESSAGE_PATTERN.matches(machineMessage)) {
            "machineMessage is not a stable machine key"
        }
        require(machineMessage in ALLOWED_MACHINE_MESSAGES) {
            "machineMessage is not in the exact allowlist"
        }
        require(pageIndex == null || pageIndex >= 0) { "pageIndex must be non-negative" }
        require(fieldCount == null || fieldCount >= 0) { "fieldCount must be non-negative" }
        require(durationMs == null || durationMs >= 0) { "durationMs must be non-negative" }
    }

    fun details(): Map<String, Any?> = linkedMapOf(
        "schemaVersion" to FeldexaChannels.SCHEMA_VERSION,
        "category" to category,
        "retryable" to retryable,
        "pageIndex" to pageIndex,
        "fieldCount" to fieldCount,
        "durationMs" to durationMs,
    )

    fun withDuration(elapsedMs: Long): PlatformFailure = PlatformFailure(
        code = code,
        category = category,
        retryable = retryable,
        machineMessage = machineMessage,
        pageIndex = pageIndex,
        fieldCount = fieldCount,
        durationMs = elapsedMs,
    )

    companion object {
        fun invalidPayload(message: String = "platform.invalidPayload"): PlatformFailure =
            PlatformFailure("PLT-003", "invalidPayload", false, message)

        fun invalidIdentifier(message: String = "platform.identifier"): PlatformFailure =
            PlatformFailure("PLT-002", "invalidIdentifier", false, message)

        fun unsupported(message: String = "platform.unsupported"): PlatformFailure =
            PlatformFailure("PLT-001", "unsupported", false, message)

        fun cancelled(): PlatformFailure =
            PlatformFailure("PLT-004", "cancelled", true, "platform.cancelled")

        fun internal(message: String = "platform.internal"): PlatformFailure =
            PlatformFailure("PLT-001", "internalError", false, message)

        fun busy(): PlatformFailure =
            PlatformFailure("PLT-001", "capacity", true, "platform.busy")

        fun invalidSavedData(): PlatformFailure =
            PlatformFailure("SAVE-007", "invalidData", false, "save.invalidData")

        fun concurrentWrite(): PlatformFailure =
            PlatformFailure("SAVE-006", "concurrentWrite", true, "save.concurrentWrite")
    }
}

/** Result sink used by [PlatformChannelFacade]; the Flutter adapter wraps a MethodChannel.Result. */
interface ChannelReply {
    fun success(result: Any?)
    fun error(failure: PlatformFailure)
}

/** A service registered by a later Android implementation task. */
interface PlatformService {
    /**
     * Handles one validated method call on a background worker. Return the
     * unwrapped response data; the facade adds the success envelope. Throw
     * [PlatformFailure] for a catalog-coded error.
     */
    fun handle(request: PlatformRequest, context: OperationContext): Any?

    /**
     * Called once when the facade is detached or destroyed, after the worker
     * pool is cancelled. Services close PDFBox/PDFium documents and delete only
     * their own session export artifacts here; durable user data is never
     * deleted. Failures are contained so one service cannot block the rest.
     */
    fun onFacadeDetached() = Unit
}

/** Read-only access to a payload that the facade already validated. */
class PlatformRequest(
    val method: String,
    val payload: Map<String, Any?>,
) {
    fun string(name: String): String? = payload[name] as? String

    fun uuid(name: String): String? = payload[name] as? String

    fun number(name: String): Number? = payload[name] as? Number

    fun bool(name: String): Boolean? = payload[name] as? Boolean

    fun bytes(name: String): ByteArray? = payload[name] as? ByteArray

    @Suppress("UNCHECKED_CAST")
    fun map(name: String): Map<String, Any?>? = payload[name] as? Map<String, Any?>
}

/** Per-call cancellation + progress seam handed to a [PlatformService]. */
class OperationContext internal constructor(
    val operationId: String,
    private val handle: OperationHandle,
    private val publisher: PlatformEventPublisher,
) {
    val isCancelled: Boolean
        get() = handle.isCancelled

    /**
     * T040: lock-free cancellation-claim signal.
     *
     * Services that hold their own staged-state cleanup lock while running a
     * long operation must not call [checkCancelled] there: the facade's
     * cancellation cleanup holds the operation-handle lock while it waits for
     * that staged-state lock, so taking the handle lock on the service side
     * would invert the order. This flag is set by the winning claim before any
     * cleanup runs and never acquires the handle lock.
     */
    internal val isCancellationClaimed: Boolean
        get() = handle.hasClaimedCancellation()

    fun checkCancelled() {
        if (handle.isCancellationRequested) throw PlatformFailure.cancelled()
    }

    /**
     * T038 review correction rounds 1-2: registers the one cleanup action for
     * this operation. The action runs exactly once inside the handle's
     * cancellation linearization:
     *
     * * if cancellation is already pending, it runs immediately while the
     *   handle lock is held, so the recorded failure is visible before
     *   cancellation is observable or published;
     * * if cancellation is claimed after registration, the facade hands the
     *   detached action to its cancellation executor, which still runs it under
     *   the same lock.
     *
     * The action must be bounded and must not call back into the handle.
     * Cancellation cannot be observed as terminal ([isCancelled], terminal
     * publication) until the action finished. A failing cleanup must be
     * reported through [recordCancellationCleanupFailure] so the terminal
     * result is a non-cancelled failure instead of a clean `PLT-004`.
     */
    internal fun registerCancellationCleanup(action: () -> Unit) {
        handle.setCancelCleanup(action)
    }

    /** Records why the registered cleanup could not remove the staged state. */
    internal fun recordCancellationCleanupFailure(failure: PlatformFailure) {
        handle.recordCancelActionFailure(failure)
    }

    /** Non-null when cancellation won but the cleanup retained staged state. */
    internal fun cancellationCleanupFailure(): PlatformFailure? = handle.cancelActionFailure()

    fun progress(kind: String, phase: String, fraction: Double, pageIndex: Int? = null) {
        checkCancelled()
        publisher.emitOperationProgress(operationId, kind, phase, fraction, pageIndex)
    }

    fun exportProgress(phase: String, fraction: Double, pageIndex: Int? = null) {
        checkCancelled()
        publisher.emitExportProgress(operationId, phase, fraction, pageIndex)
    }
}

/** Active operation registry backing `cancel.operation`. */
class OperationRegistry {
    private val active = ConcurrentHashMap<String, OperationHandle>()

    internal fun begin(id: String): OperationHandle {
        val handle = OperationHandle(id)
        active[id] = handle
        return handle
    }

    internal fun finish(handle: OperationHandle) {
        active.remove(handle.id, handle)
    }

    internal fun find(operationId: String): OperationHandle? = active[operationId]

    internal fun clear() {
        active.clear()
    }
}

class OperationHandle internal constructor(val id: String) {
    private enum class State { ACTIVE, CANCELLING, CANCELLED, COMPLETED }

    /** One cancellation claim; [cleanup] is set when a registered action was detached. */
    internal class CancellationClaim(
        val cancelled: Boolean,
        val cleanup: (() -> Unit)?,
    )

    private val lock = ReentrantLock()
    private val cancelSignal = lock.newCondition()

    /**
     * Lock-free "cancellation claim decided" signal. It is set inside the
     * winning claim, before any cleanup can run, so a repeated `cancel.operation`
     * can acknowledge immediately without touching the handle lock (which a
     * late cleanup may hold for the duration of storage I/O).
     */
    private val claimDecided = AtomicBoolean(false)
    private var state = State.ACTIVE
    private var started = false
    private var queuedCancelAction: (() -> Unit)? = null
    private var cancellationCleanup: (() -> Unit)? = null
    private var cleanupInProgress = false
    private var cancelActionFailure: PlatformFailure? = null
    private var cancellationPublished = false

    /** Lock-free check used by the repeated-cancel fast path. */
    internal fun hasClaimedCancellation(): Boolean = claimDecided.get()

    /** Cancellation is terminal and cleanup (if any) has completed. */
    val isCancelled: Boolean
        get() = lock.withLock { state == State.CANCELLED }

    /**
     * Cancellation has won the transition race, even if its cleanup is still
     * running. Services poll this to abort; [isCancelled] stays false until the
     * cleanup finished.
     */
    internal val isCancellationRequested: Boolean
        get() = lock.withLock {
            state == State.CANCELLING || state == State.CANCELLED
        }

    /** A queued operation is no longer cancellable through the queued path. */
    internal fun markStarted() {
        lock.withLock {
            started = true
            queuedCancelAction = null
        }
    }

    /** Registers the facade's queued-operation cancellation action. */
    internal fun setCancelAction(action: () -> Unit) {
        lock.withLock {
            if (state == State.ACTIVE && !started) queuedCancelAction = action
        }
    }

    /**
     * Registers the service's staged-state cleanup. A registration that arrives
     * after cancellation won runs inside the handle lock and records its
     * failure before the terminal cancellation becomes observable.
     */
    internal fun setCancelCleanup(action: () -> Unit) {
        var notify = false
        lock.withLock {
            when (state) {
                State.ACTIVE -> cancellationCleanup = action
                State.CANCELLING -> {
                    // Late registration: stay inside the cancellation lock so an
                    // observer cannot see CANCELLED before the cleanup and its
                    // failure are recorded.
                    runCancelAction(action)
                    if (!cleanupInProgress) {
                        state = State.CANCELLED
                        notify = true
                    }
                }
                // Defensive: the facade seals publication only after the service
                // call ended, so a cleanup must not arrive here. Run it anyway
                // rather than silently retaining staged state.
                State.CANCELLED -> runCancelAction(action)
                State.COMPLETED -> Unit
            }
            if (notify) cancelSignal.signalAll()
        }
    }

    /**
     * Claims cancellation without running a registered cleanup. The facade runs
     * this on its dedicated claim executor; cleanup is then handed to the
     * separate cancellation executor. The claim sets [hasClaimedCancellation]
     * before releasing the lock, so later cancels never need to acquire it. A
     * queued operation's still-cheap cancellation action runs inline,
     * preserving the existing queued-cancellation protocol and its single
     * terminal result.
     */
    internal fun claimCancellation(): CancellationClaim = lock.withLock {
        if (state != State.ACTIVE) {
            CancellationClaim(false, null)
        } else if (!started && queuedCancelAction != null) {
            val action = queuedCancelAction
            queuedCancelAction = null
            claimDecided.set(true)
            state = State.CANCELLED
            action?.let(::runCancelAction)
            CancellationClaim(true, null)
        } else {
            val cleanup = cancellationCleanup
            cancellationCleanup = null
            cleanupInProgress = cleanup != null
            claimDecided.set(true)
            state = State.CANCELLING
            CancellationClaim(true, cleanup)
        }
    }

    internal fun recordCancelActionFailure(failure: PlatformFailure) {
        lock.withLock {
            if (cancelActionFailure == null) cancelActionFailure = failure
        }
    }

    internal fun cancelActionFailure(): PlatformFailure? = lock.withLock {
        cancelActionFailure
    }

    /**
     * Runs a claimed cleanup under the same lock as the cancellation transition,
     * so the recorded failure is complete before CANCELLED becomes observable.
     * Called on the facade's cancellation executor (off the channel thread).
     */
    internal fun runClaimedCleanup(cleanup: () -> Unit) {
        lock.withLock {
            if (state != State.CANCELLING || !cleanupInProgress) return
            runCancelAction(cleanup)
            cleanupInProgress = false
            state = State.CANCELLED
            cancelSignal.signalAll()
        }
    }

    /**
     * Runs a cleanup exactly once. A failure is recorded (first failure wins)
     * and never escapes into the channel caller.
     */
    private fun runCancelAction(action: () -> Unit) {
        try {
            action()
        } catch (failure: PlatformFailure) {
            recordCancelActionFailure(failure)
        } catch (_: Throwable) {
            recordCancelActionFailure(PlatformFailure.internal())
        }
    }

    /**
     * Direct inline cancellation used by host-JVM tests. It is deliberately not
     * used by the channel facade: the facade calls [claimCancellation] and runs
     * cleanup on its cancellation executor, never on the channel thread. A
     * registered cleanup runs synchronously under the lock here, so once this
     * returns CANCELLED is observable with its cleanup complete.
     */
    internal fun cancel(): Boolean {
        val claim = claimCancellation()
        if (!claim.cancelled) return false
        claim.cleanup?.let(::runClaimedCleanup)
        return true
    }

    /**
     * Publishes the terminal success/error result while holding the same lock as
     * cancellation. A concurrent cancel therefore either wins before this call
     * (false) or observes a completed terminal state (false); it never observes
     * an active operation after the result was published.
     */
    internal fun complete(publish: () -> Unit): Boolean = lock.withLock {
        if (state != State.ACTIVE) {
            false
        } else {
            state = State.COMPLETED
            queuedCancelAction = null
            cancellationCleanup = null
            publish()
            true
        }
    }

    /**
     * Publishes the one terminal cancellation result if cancellation won.
     *
     * The cleanup failure is read inside this critical section, not snapshotted
     * before it, so a late registration cannot be missed. If a claimed cleanup
     * is still running, publication waits for it: `PLT-004` is never emitted
     * while the staged aggregate may still be retained. If the service ended
     * without registering a cleanup, the pending claim is folded into CANCELLED
     * here. [publish] receives the recorded failure (null for a clean cancel).
     */
    internal fun publishCancellation(publish: (PlatformFailure?) -> Unit): Boolean {
        lock.withLock {
            if (state == State.CANCELLING) {
                if (!cleanupInProgress) {
                    state = State.CANCELLED
                    cancelSignal.signalAll()
                }
                while (state == State.CANCELLING) {
                    try {
                        cancelSignal.await()
                    } catch (interrupted: InterruptedException) {
                        Thread.currentThread().interrupt()
                        return false
                    }
                }
            }
            if (state != State.CANCELLED || cancellationPublished) return false
            cancellationPublished = true
            publish(cancelActionFailure)
            return true
        }
    }
}

/** Thread abstraction so the channel core stays JVM-testable. */
fun interface ThreadPoster {
    fun post(block: () -> Unit)
}

class AndroidMainThreadPoster : ThreadPoster {
    private val handler = Handler(Looper.getMainLooper())

    override fun post(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            handler.post(block)
        }
    }
}

/** Bounded background executor contract (§9: at most 2 workers). */
interface BackgroundExecutor {
    fun execute(task: () -> Unit)
    fun shutdown()
}

class BoundedBackgroundExecutor(
    maxWorkers: Int = 2,
    queueCapacity: Int = 64,
) : BackgroundExecutor {
    private val counter = AtomicInteger(0)
    private val pool = ThreadPoolExecutor(
        maxWorkers,
        maxWorkers,
        0L,
        TimeUnit.MILLISECONDS,
        ArrayBlockingQueue(queueCapacity),
        { runnable ->
            Thread(runnable, "feldexa-channel-${counter.incrementAndGet()}").apply {
                isDaemon = true
            }
        },
    )

    override fun execute(task: () -> Unit) {
        pool.execute(task)
    }

    override fun shutdown() {
        pool.shutdownNow()
    }
}

/**
 * Serializes tasks that carry the same aggregate key while allowing different
 * keys to use the shared bounded worker pool concurrently. A `null` key is
 * dispatched immediately. This implements the per-document ordering required by
 * `contracts/platform-channel.md` §9 for operations whose payload exposes a
 * stable aggregate id; OCR/import have no document id in that contract and use
 * conservative domain keys instead (see [PlatformChannelFacade.serializationKey]).
 */
class KeyedSerialExecutor(
    private val executor: BackgroundExecutor,
    private val maxPendingPerKey: Int = 8,
    private val maxPendingTotal: Int = 32,
) : BackgroundExecutor {
    /** A queued task that can be removed before it starts. */
    class QueuedOperation internal constructor(
        internal val key: String,
        internal val task: () -> Unit,
    )

    private val lock = Any()
    private val queues = HashMap<String, ArrayDeque<QueuedOperation>>()
    private val queued = HashSet<QueuedOperation>()
    private val runningKeys = HashSet<String>()
    private var pendingTotal = 0

    /**
     * Queues a task under [key]. Returns the cancelable handle, or null when the
     * task was dispatched immediately. Throws [RejectedExecutionException] when
     * the per-key or total bound is reached, so aggregate queues cannot bypass
     * the §9 bounded-executor backpressure.
     */
    fun submit(key: String?, task: () -> Unit): QueuedOperation? {
        if (key == null) {
            executor.execute(task)
            return null
        }
        val entry = QueuedOperation(key, task)
        val schedule = synchronized(lock) {
            val queue = queues.getOrPut(key) { ArrayDeque() }
            if (queue.size >= maxPendingPerKey || pendingTotal >= maxPendingTotal) {
                if (queue.isEmpty()) queues.remove(key)
                throw RejectedExecutionException("serial queue is full")
            }
            queue.addLast(entry)
            queued.add(entry)
            pendingTotal++
            runningKeys.add(key)
        }
        if (!schedule) return entry
        try {
            executor.execute { drain(key) }
        } catch (failure: Throwable) {
            synchronized(lock) {
                val removed = queues.remove(key) ?: ArrayDeque()
                runningKeys.remove(key)
                removed.forEach {
                    queued.remove(it)
                    pendingTotal--
                }
            }
            throw failure
        }
        return entry
    }

    /** Removes a still-queued task. Running tasks cannot be removed here. */
    fun cancel(entry: QueuedOperation): Boolean {
        var removed = false
        synchronized(lock) {
            if (queued.remove(entry)) {
                val queue = queues[entry.key]
                if (queue != null) {
                    queue.remove(entry)
                    if (queue.isEmpty()) queues.remove(entry.key)
                }
                pendingTotal--
                removed = true
            }
        }
        return removed
    }

    override fun execute(task: () -> Unit) {
        submit(null, task)
    }

    override fun shutdown() {
        synchronized(lock) {
            queues.clear()
            queued.clear()
            runningKeys.clear()
            pendingTotal = 0
        }
        executor.shutdown()
    }

    private fun drain(key: String) {
        while (true) {
            val entry = synchronized(lock) {
                val queue = queues[key]
                if (queue == null || queue.isEmpty()) {
                    queues.remove(key)
                    runningKeys.remove(key)
                    null
                } else {
                    val next = queue.removeFirst()
                    queued.remove(next)
                    pendingTotal--
                    next
                }
            } ?: return
            try {
                entry.task()
            } catch (_: Throwable) {
                // The facade converts service Throwables (including Error) to a
                // terminal result before returning; keep draining the same key so
                // one bad task cannot stall the queue.
            }
        }
    }
}

/** Service registry keyed by the `<domain>` prefix; one owner per prefix. */
class PlatformServiceRegistry {
    private val services = ConcurrentHashMap<String, PlatformService>()

    fun register(prefix: String, service: PlatformService) {
        require(prefix in METHOD_PREFIXES) { "unknown method prefix" }
        val existing = services.putIfAbsent(prefix, service)
        check(existing == null) { "service already registered for prefix $prefix" }
    }

    fun unregister(prefix: String) {
        services.remove(prefix)
    }

    fun closeAll() {
        val registered = services.values.toList()
        services.clear()
        registered.forEach { service ->
            try {
                service.onFacadeDetached()
            } catch (_: Exception) {
                // A failing service must not keep the engine or other services alive.
            }
        }
    }

    fun serviceFor(method: String): PlatformService? = services[method.substringBefore('.')]

    fun registeredPrefixes(): Set<String> = services.keys.toSet()

    companion object {
        val METHOD_PREFIXES = setOf("import", "store", "ocr", "export", "delivery")
    }
}

/**
 * Applies the editor/export screenshot protection of
 * `contracts/platform-channel.md` §11 point 7.
 *
 * Implemented by the activity-bound host (`MainActivity`), which owns the
 * window; the facade only forwards the validated route token and never touches
 * window or activity state itself. `apply` must be main-thread safe and returns
 * the read-back `FLAG_SECURE` state: `false` means the route is *not* protected
 * and is reported to Dart unchanged.
 */
fun interface SensitiveRouteHost {
    fun apply(route: String): Boolean

    companion object {
        /** Wire token that clears the protection (§11 point 7). */
        const val ROUTE_NONE: String = "none"

        /** Wire token of the editor route. */
        const val ROUTE_EDITOR: String = "editor"

        /** Wire token of the export preview route. */
        const val ROUTE_EXPORT: String = "export"

        /** Every accepted route token, in contract order. */
        val ROUTES: Set<String> = setOf(ROUTE_EDITOR, ROUTE_EXPORT, ROUTE_NONE)
    }
}

/**
 * The reusable channel core: payload validation, envelope, threading,
 * cancellation, duration, and error mapping. [FeldexaPlugin] is the thin
 * Flutter/Android adapter around this class.
 */
class PlatformChannelFacade(
    val services: PlatformServiceRegistry = PlatformServiceRegistry(),
    private val mainPoster: ThreadPoster = AndroidMainThreadPoster(),
    val events: PlatformEventPublisher = PlatformEventPublisher(mainPoster),
    val results: PlatformResultPublisher = PlatformResultPublisher(mainPoster),
    private val executor: BackgroundExecutor = BoundedBackgroundExecutor(),
    /**
     * Resolves the activity-bound sensitive-route host, or null when the
     * engine has no activity. A null host is answered as "not protected".
     */
    private val sensitiveRoute: () -> SensitiveRouteHost? = { null },
    /**
     * Dedicated cancellation paths. They intentionally bypass the keyed serial
     * executor: the running operation holds its key, so a cancel queued behind
     * it would stall until the operation finished. The claim executor only runs
     * the constant-time transition handshake; the cleanup executor runs storage
     * cleanup. The channel handler waits only for the claim, never for cleanup.
     */
    private val cancelClaimExecutor: BackgroundExecutor = BoundedBackgroundExecutor(maxWorkers = 1),
    private val cancelExecutor: BackgroundExecutor = BoundedBackgroundExecutor(maxWorkers = 1),
    val limits: ChannelLimits = ChannelLimits(),
    private val operations: OperationRegistry = OperationRegistry(),
    private val operationIdFactory: () -> String = { UUID.randomUUID().toString() },
    private val clock: () -> Long = { System.nanoTime() / 1_000_000L },
) {
    private val disposed = AtomicBoolean(false)
    private val catalog = MethodCatalog(limits)
    private val serialExecutor = KeyedSerialExecutor(executor)
    private val inFlightSaves = ConcurrentHashMap<String, Boolean>()

    fun handle(method: String, arguments: Any?, reply: ChannelReply) {
        val startedAt = clock()
        if (disposed.get()) {
            reply.error(PlatformFailure.unsupported().withDuration(elapsedSince(startedAt)))
            return
        }
        val request = try {
            validate(method, arguments)
        } catch (failure: PlatformFailure) {
            reply.error(failure.withDuration(elapsedSince(startedAt)))
            return
        } catch (error: Error) {
            throw error
        } catch (unexpected: Exception) {
            reply.error(PlatformFailure.internal().withDuration(elapsedSince(startedAt)))
            return
        }

        if (method == "platform.sensitiveRoute") {
            // `contracts/platform-channel.md` §11 point 7: apply or clear
            // FLAG_SECURE for the current document route. The activity-bound
            // host owns the window and is main-thread safe; this handler only
            // forwards the already validated token and reports the read-back
            // state. A missing host or a thrown failure is answered as
            // "not protected" instead of claiming a protection that does not
            // exist.
            val route = request.payload["route"] as String
            val secure = try {
                sensitiveRoute()?.apply(route) ?: false
            } catch (error: Exception) {
                false
            }
            reply.success(
                successEnvelope(linkedMapOf("route" to route, "secure" to secure)),
            )
            return
        }

        if (method == "cancel.operation") {
            val operationId = request.payload["operationId"] as String
            val handle = operations.find(operationId)
            if (handle == null) {
                reply.success(successEnvelope(mapOf("cancelled" to false)))
                return
            }

            // The reply acknowledges that cancellation is claimed/linearized;
            // it is not the terminal result. It may precede cleanup, while the
            // terminal result still waits for cleanup and is published exactly
            // once. A repeated cancel never touches the handle lock: a late
            // cleanup can hold it for the duration of storage I/O.
            if (handle.hasClaimedCancellation()) {
                reply.success(successEnvelope(mapOf("cancelled" to true)))
                return
            }

            // The transition itself runs on the dedicated claim executor; the
            // channel thread only waits for the claim handshake (first cancel
            // and terminal-race linearization), never for storage cleanup.
            // Cleanup is handed to the separate cancellation executor. A queued
            // operation's still-cheap action runs inside the claim, preserving
            // the queued-cancellation protocol and its single terminal result.
            val claimRef = AtomicReference<OperationHandle.CancellationClaim?>(null)
            val claimDone = CountDownLatch(1)
            val claimTask: () -> Unit = {
                var claim: OperationHandle.CancellationClaim? = null
                try {
                    // Re-check lock-free: a concurrent first claim may have won
                    // between the handler check and this task, and its cleanup
                    // may already hold the handle lock.
                    claim = if (handle.hasClaimedCancellation()) {
                        OperationHandle.CancellationClaim(true, null)
                    } else {
                        handle.claimCancellation()
                    }
                } finally {
                    claimRef.set(claim)
                    claimDone.countDown()
                }
                claim?.cleanup?.let { cleanup ->
                    try {
                        cancelExecutor.execute { handle.runClaimedCleanup(cleanup) }
                    } catch (rejected: RejectedExecutionException) {
                        // Fail-safe: run the cleanup on this already-off-channel
                        // claim thread rather than retaining staged state.
                        handle.runClaimedCleanup(cleanup)
                    }
                }
                Unit
            }
            try {
                cancelClaimExecutor.execute(claimTask)
            } catch (rejected: RejectedExecutionException) {
                // Extreme fallback (claim executor exhausted/shut down): this
                // is the only path that can perform the claim on the channel
                // thread; cleanup still goes to the cancellation executor.
                claimTask()
            }
            try {
                claimDone.await()
            } catch (interrupted: InterruptedException) {
                Thread.currentThread().interrupt()
            }
            val claim = claimRef.get()
            reply.success(successEnvelope(mapOf("cancelled" to (claim?.cancelled == true))))
            return
        }

        val service = services.serviceFor(method)
        if (service == null) {
            reply.error(PlatformFailure.unsupported().withDuration(elapsedSince(startedAt)))
            return
        }

        val saveDocumentId = if (method == "store.saveRevision") {
            request.string("documentId")
        } else {
            null
        }
        if (saveDocumentId != null && inFlightSaves.putIfAbsent(saveDocumentId, true) != null) {
            // §9/§12: a second save for the same document is rejected, not queued.
            reply.error(PlatformFailure.concurrentWrite().withDuration(elapsedSince(startedAt)))
            return
        }

        val operationId = operationIdFactory()
        val handle = operations.begin(operationId)
        val async = method in ASYNC_METHODS
        val queued = try {
            serialExecutor.submit(serializationKey(request)) {
                runOperation(
                    request = request,
                    service = service,
                    operationId = operationId,
                    handle = handle,
                    reply = if (async) null else reply,
                    startedAt = startedAt,
                    saveDocumentId = saveDocumentId,
                    async = async,
                )
            }
        } catch (rejected: RejectedExecutionException) {
            operations.finish(handle)
            releaseSave(saveDocumentId)
            reply.error(PlatformFailure.busy().withDuration(elapsedSince(startedAt)))
            return
        } catch (failure: PlatformFailure) {
            operations.finish(handle)
            releaseSave(saveDocumentId)
            reply.error(failure.withDuration(elapsedSince(startedAt)))
            return
        } catch (unexpected: Exception) {
            operations.finish(handle)
            releaseSave(saveDocumentId)
            reply.error(PlatformFailure.internal().withDuration(elapsedSince(startedAt)))
            return
        }

        queued?.let { entry ->
            handle.setCancelAction {
                if (serialExecutor.cancel(entry)) {
                    publishCancelled(handle, reply, async, operationId, startedAt)
                    operations.finish(handle)
                    releaseSave(saveDocumentId)
                }
            }
        }

        if (async) {
            // Owner decision: a reliable start reply carries the operation id.
            // The method-specific data follows on the result channel.
            reply.success(successEnvelope(linkedMapOf("operationId" to operationId)))
        }
    }

    private fun releaseSave(documentId: String?) {
        if (documentId != null) inFlightSaves.remove(documentId)
    }

    /**
     * Per-aggregate ordering for the operations named in §9. Import has no
     * document id before staging, so it uses one import key; OCR has no document
     * id in the request either, so it uses a conservative OCR key. Per-document
     * OCR remains the service/adapter owner (T056/T027) because the contract
     * gives the facade no document identifier for that call.
     */
    private fun serializationKey(request: PlatformRequest): String? = when (request.method) {
        "import.pickAndImport", "import.verifySource" -> "import"
        "ocr.recognize" -> "ocr"
        "store.saveRevision", "store.writeSignature" ->
            request.string("documentId")?.let { "document:$it" }
        "store.createTemplate" -> "template:create"
        "store.saveTemplateVersion" ->
            request.string("templateId")?.let { "template:$it" }
        "export.validate", "export.render" -> {
            val documentId = request.map("plan")?.get("documentId") as? String
            documentId?.let { "export:$it" } ?: "export"
        }
        else -> null
    }

    private fun runOperation(
        request: PlatformRequest,
        service: PlatformService,
        operationId: String,
        handle: OperationHandle,
        reply: ChannelReply?,
        startedAt: Long,
        saveDocumentId: String?,
        async: Boolean,
    ) {
        try {
            val data = try {
                handle.markStarted()
                if (handle.isCancellationRequested) throw PlatformFailure.cancelled()
                service.handle(
                    request,
                    OperationContext(operationId, handle, events),
                )
            } catch (failure: PlatformFailure) {
                deliverFailure(handle, reply, async, operationId, failure, startedAt)
                return
            } catch (interrupted: InterruptedException) {
                Thread.currentThread().interrupt()
                deliverFailure(handle, reply, async, operationId, PlatformFailure.cancelled(), startedAt)
                return
            } catch (cancelled: CancellationException) {
                deliverFailure(handle, reply, async, operationId, PlatformFailure.cancelled(), startedAt)
                return
            } catch (security: SecurityException) {
                deliverFailure(handle, reply, async, operationId, PlatformFailure.invalidIdentifier(), startedAt)
                return
            } catch (unsupported: UnsupportedOperationException) {
                deliverFailure(handle, reply, async, operationId, PlatformFailure.unsupported(), startedAt)
                return
            } catch (error: Error) {
                // An accepted service must always terminate. AssertionError and
                // other Errors are mapped to the content-free internal failure;
                // the Error text and stack are never forwarded.
                deliverFailure(handle, reply, async, operationId, PlatformFailure.internal(), startedAt)
                return
            } catch (unexpected: Exception) {
                deliverFailure(handle, reply, async, operationId, PlatformFailure.internal(), startedAt)
                return
            }

            if (handle.isCancelled) {
                publishCancelled(handle, reply, async, operationId, startedAt)
            } else {
                val completed = handle.complete {
                    publishSuccess(reply, async, operationId, data)
                }
                if (!completed) {
                    publishCancelled(handle, reply, async, operationId, startedAt)
                }
            }
        } finally {
            operations.finish(handle)
            releaseSave(saveDocumentId)
        }
    }

    private fun publishSuccess(
        reply: ChannelReply?,
        async: Boolean,
        operationId: String,
        data: Any?,
    ) {
        if (async) {
            results.publish(successResult(operationId, data))
        } else {
            mainPoster.post {
                reply?.success(successEnvelope(data))
            }
        }
    }

    private fun deliverFailure(
        handle: OperationHandle,
        reply: ChannelReply?,
        async: Boolean,
        operationId: String,
        failure: PlatformFailure,
        startedAt: Long,
    ) {
        val timed = failure.withDuration(elapsedSince(startedAt))
        if (handle.isCancelled) {
            publishCancelled(handle, reply, async, operationId, startedAt)
            return
        }
        val completed = handle.complete {
            if (async) {
                results.publish(errorResult(operationId, timed))
            } else {
                mainPoster.post { reply?.error(timed) }
            }
        }
        if (!completed) {
            publishCancelled(handle, reply, async, operationId, startedAt)
        }
    }

    private fun publishCancelled(
        handle: OperationHandle,
        reply: ChannelReply?,
        async: Boolean,
        operationId: String,
        startedAt: Long,
    ) {
        // The failure is read inside handle.publishCancellation's critical
        // section, not snapshotted before it: a late cleanup registration or a
        // claimed cleanup running on the cancellation executor cannot be
        // missed. A cleanup failure is reported instead of PLT-004, so a
        // retained aggregate never looks like a clean cancellation.
        handle.publishCancellation { cleanupFailure ->
            val failure = (cleanupFailure ?: PlatformFailure.cancelled())
                .withDuration(elapsedSince(startedAt))
            if (async) {
                results.publish(errorResult(operationId, failure))
            } else {
                mainPoster.post { reply?.error(failure) }
            }
        }
    }

    private fun successResult(operationId: String, data: Any?): Map<String, Any?> = linkedMapOf(
        "schemaVersion" to FeldexaChannels.SCHEMA_VERSION,
        "event" to "operation.result",
        "operationId" to operationId,
        "ok" to true,
        "data" to data,
    )

    private fun errorResult(
        operationId: String,
        failure: PlatformFailure,
    ): Map<String, Any?> = linkedMapOf(
        "schemaVersion" to FeldexaChannels.SCHEMA_VERSION,
        "event" to "operation.result",
        "operationId" to operationId,
        "ok" to false,
        "error" to linkedMapOf(
            "code" to failure.code,
            "message" to failure.machineMessage,
            "details" to failure.details(),
        ),
    )

    private fun successEnvelope(data: Any?): Map<String, Any?> = linkedMapOf(
        "schemaVersion" to FeldexaChannels.SCHEMA_VERSION,
        "ok" to true,
        "data" to data,
    )

    /** Stops background work and makes subsequent calls fail closed. */
    fun dispose() {
        if (!disposed.compareAndSet(false, true)) return
        serialExecutor.shutdown()
        cancelClaimExecutor.shutdown()
        cancelExecutor.shutdown()
        operations.clear()
        inFlightSaves.clear()
        events.dispose()
        results.dispose()
        services.closeAll()
    }

    private fun elapsedSince(startedAt: Long): Long = (clock() - startedAt).coerceAtLeast(0L)

    private fun validate(method: String, arguments: Any?): PlatformRequest {
        val spec = catalog.specFor(method)
            ?: throw PlatformFailure.unsupported()
        if (arguments !is Map<*, *>) {
            throw PlatformFailure.invalidPayload("platform.payloadNotMap")
        }

        val payload = linkedMapOf<String, Any?>()
        for ((key, value) in arguments) {
            if (key !is String) throw PlatformFailure.invalidPayload("platform.nonStringKey")
            if (key !in spec.allowedFields) {
                throw PlatformFailure.invalidPayload("platform.unknownField")
            }
            payload[key] = value
        }

        // §10 limits the method payload as a whole, not just its top-level
        // values. Account for the StandardMethodCodec method-call encoding:
        // the method-name string plus the root map marker, its entry count,
        // every key's own encoding, and every value (recursively). This is
        // allocation-free for large byte arrays and strings, so the guard
        // never builds a second serialized copy of a near-96 MiB payload.
        val payloadBytes = PayloadSize.measureMethodCall(method, payload, limits.maxPayloadBytes)
        if (payloadBytes > limits.maxPayloadBytes) {
            throw PlatformFailure.invalidPayload("platform.payloadTooLarge")
        }

        val schemaVersion = payload["schemaVersion"]
            ?: throw PlatformFailure.invalidPayload("platform.schemaVersionMissing")
        if (!isIntegral(schemaVersion) || (schemaVersion as Number).toLong() != FeldexaChannels.SCHEMA_VERSION.toLong()) {
            throw PlatformFailure.invalidPayload("platform.schemaVersionUnsupported")
        }

        spec.fields.forEach { rule -> rule.apply(payload[rule.name]) }
        spec.postValidate?.invoke(payload)
        return PlatformRequest(method, payload)
    }

    private fun isIntegral(value: Any?): Boolean {
        if (value !is Number) return false
        val asDouble = value.toDouble()
        return asDouble.isFinite() && asDouble % 1.0 == 0.0
    }
}

/** Per-method limits from `contracts/platform-channel.md` §10. */
data class ChannelLimits(
    val maxPayloadBytes: Long = 96L * 1024L * 1024L,
    val maxSourceBytes: Long = 80L * 1024L * 1024L,
    val maxExportPlanBytes: Long = 8L * 1024L * 1024L,
    val maxRevisionBytes: Long = 32L * 1024L * 1024L,
    val maxSignatureBytes: Long = 2L * 1024L * 1024L,
    val maxOcrEdgePx: Int = 4096,
    val maxTitleLength: Int = 200,
    val maxSuggestedNameLength: Int = 120,
)

/**
 * Versioned event publisher for `de.feldexa/events`. Progress is coalesced per
 * operation so a fast PDFBox loop cannot flood the Dart side; terminal method
 * results remain authoritative (§8). Event maps follow §8 and add the `event`
 * discriminator used by §6; they are not method payloads and therefore carry no
 * `schemaVersion` envelope.
 */
class PlatformEventPublisher(
    private val poster: ThreadPoster,
) {
    private val sink = AtomicReference<FeldexaEventSink?>(null)
    private val pendingProgress = ConcurrentHashMap<String, Map<String, Any?>>()
    private val drainScheduled = AtomicBoolean(false)
    private val disposed = AtomicBoolean(false)

    fun attachSink(newSink: FeldexaEventSink?) {
        sink.set(newSink)
        if (newSink == null) pendingProgress.clear()
    }

    fun emitLifecycle(lifecycle: HostLifecycle) {
        emitDirect(
            linkedMapOf(
                "event" to "lifecycle",
                "state" to lifecycle.wireValue,
            ),
        )
    }

    fun emitStorageStatus(
        scope: String,
        kind: String?,
        itemId: String?,
        keyAvailable: Boolean,
        reasonCode: String?,
    ) {
        require(scope == "store" || scope == "aggregate") { "invalid storage scope" }
        require(kind == null || kind == "document" || kind == "template") { "invalid storage kind" }
        if (scope == "store") {
            require(kind == null && itemId == null) { "store scope has no aggregate" }
        } else {
            require(kind != null && itemId != null) { "aggregate scope requires kind and itemId" }
            require(UUID_PATTERN.matches(itemId)) { "invalid aggregate itemId" }
        }
        require(reasonCode == null || reasonCode == "SAVE-002" || reasonCode == "SAVE-008") {
            "invalid storage reason code"
        }
        emitDirect(
            linkedMapOf(
                "event" to "storage.status",
                "scope" to scope,
                "kind" to kind,
                "itemId" to itemId,
                "keyAvailable" to keyAvailable,
                "reasonCode" to reasonCode,
            ),
        )
    }

    fun emitImportPickerResult(correlationId: String, cancelled: Boolean) {
        require(correlationId.length in 1..128 && !hasControlCharacters(correlationId)) {
            "invalid picker correlation id"
        }
        emitDirect(
            linkedMapOf(
                "event" to "import.pickerResult",
                "correlationId" to correlationId,
                "cancelled" to cancelled,
            ),
        )
    }

    fun emitOperationProgress(
        operationId: String,
        kind: String,
        phase: String,
        fraction: Double,
        pageIndex: Int? = null,
    ) {
        require(kind == "import" || kind == "analyze" || kind == "save" || kind == "export") {
            "invalid progress kind"
        }
        val event = progressEvent(
            eventName = "operation.progress",
            operationId = operationId,
            phase = phase,
            fraction = fraction,
            pageIndex = pageIndex,
        )
        event["kind"] = kind
        queueProgress("operation.progress:$operationId", event)
    }

    fun emitExportProgress(
        operationId: String,
        phase: String,
        fraction: Double,
        pageIndex: Int? = null,
    ) {
        val event = progressEvent(
            eventName = "export.progress",
            operationId = operationId,
            phase = phase,
            fraction = fraction,
            pageIndex = pageIndex,
        )
        queueProgress("export.progress:$operationId", event)
    }

    fun dispose() {
        if (!disposed.compareAndSet(false, true)) return
        sink.set(null)
        pendingProgress.clear()
    }

    private fun progressEvent(
        eventName: String,
        operationId: String,
        phase: String,
        fraction: Double,
        pageIndex: Int?,
    ): LinkedHashMap<String, Any?> {
        require(UUID_PATTERN.matches(operationId)) { "invalid operation id" }
        require(phase.length in 1..32 && !hasControlCharacters(phase)) { "invalid progress phase" }
        require(fraction.isFinite() && fraction in 0.0..1.0) { "invalid progress fraction" }
        require(pageIndex == null || pageIndex >= 0) { "invalid progress page index" }
        return linkedMapOf(
            "event" to eventName,
            "operationId" to operationId,
            "phase" to phase,
            "fraction" to fraction,
            "pageIndex" to pageIndex,
        )
    }

    private fun queueProgress(key: String, event: Map<String, Any?>) {
        if (disposed.get()) return
        pendingProgress[key] = event
        scheduleDrain()
    }

    private fun scheduleDrain() {
        if (drainScheduled.compareAndSet(false, true)) {
            poster.post { drainProgress() }
        }
    }

    private fun drainProgress() {
        drainScheduled.set(false)
        val batch = pendingProgress.entries.toList()
        for ((key, event) in batch) {
            if (pendingProgress.remove(key, event)) {
                sink.get()?.success(event)
            }
        }
        if (pendingProgress.isNotEmpty()) scheduleDrain()
    }

    private fun emitDirect(event: Map<String, Any?>) {
        if (disposed.get()) return
        poster.post { sink.get()?.success(event) }
    }
}

/**
 * Retains terminal async results and replays them when a result listener attaches.
 * Retention is session-scoped, bounded, and duplicate-tolerant; the start reply is
 * already reliable because it carries the operation id before any terminal work.
 */
class PlatformResultPublisher(
    private val poster: ThreadPoster,
    private val maxRetained: Int = 64,
) {
    private val lock = Any()
    private val retained = LinkedHashMap<String, Map<String, Any?>>()
    private val sink = AtomicReference<FeldexaEventSink?>(null)
    private val disposed = AtomicBoolean(false)

    init {
        require(maxRetained > 0) { "maxRetained must be positive" }
    }

    /**
     * Attaches the result sink and replays all retained terminal results. Replay
     * duplicates are allowed; Dart deduplicates by operationId.
     */
    fun attachSink(newSink: FeldexaEventSink?) {
        val replay: List<Map<String, Any?>>
        synchronized(lock) {
            if (disposed.get()) return
            sink.set(newSink)
            replay = retained.values.toList()
        }
        if (newSink != null) {
            replay.forEach { event ->
                poster.post {
                    if (!disposed.get()) sink.get()?.success(event)
                }
            }
        }
    }

    /** Publishes a terminal result and retains it for a late listener. */
    fun publish(result: Map<String, Any?>) {
        val operationId = result["operationId"] as? String ?: return
        synchronized(lock) {
            if (disposed.get()) return
            retained.remove(operationId)
            retained[operationId] = result
            while (retained.size > maxRetained) {
                retained.remove(retained.keys.iterator().next())
            }
        }
        poster.post {
            if (!disposed.get()) sink.get()?.success(result)
        }
    }

    fun dispose() {
        synchronized(lock) {
            if (!disposed.compareAndSet(false, true)) return
            retained.clear()
            sink.set(null)
        }
    }
}

/** Adapter used by [FeldexaPlugin] to keep the core free of Flutter types. */
fun interface FeldexaEventSink {
    fun success(event: Any?)
}

/**
 * Allocation-free size accounting for the `StandardMessageCodec` encoding used
 * by Flutter's `StandardMethodCodec` on method calls.
 *
 * It mirrors the encoder in
 * `io.flutter.plugin.common.StandardMessageCodec`: one type byte per value, the
 * variable-width `writeSize` prefix for strings/byte arrays/maps/lists, the
 * 4/8-byte alignment before typed numeric arrays and doubles, and the complete
 * encoding of every map key. [measureMethodCall] additionally counts the
 * method-name string and the root arguments map, so the §10 "Method payload
 * ≤ 96 MiB total" limit covers the whole method payload instead of only its
 * top-level values.
 *
 * No serialized copy is allocated: byte arrays contribute their length
 * directly, strings and other `CharSequence`s are measured by scanning code
 * units, and a `BigInteger` contributes the length of its hexadecimal text
 * without building that string. A cheap sign/bit-length lower bound rejects an
 * oversized magnitude before the negative power-of-two disambiguation needs
 * `bitCount()`. The `remaining` budget stops traversal as soon as the limit is
 * known to be exceeded.
 */
internal object PayloadSize {
    private const val MAX_DEPTH = 64
    private const val TYPE_BYTE = 1L

    fun measure(value: Any?, remaining: Long): Long =
        Counter(remaining).also { it.writeValue(value, 0) }.size

    /** Exact encoded size of `StandardMethodCodec.encodeMethodCall`. */
    fun measureMethodCall(method: String, arguments: Map<*, *>, remaining: Long): Long =
        Counter(remaining).also {
            it.writeString(method)
            it.writeValue(arguments, 0)
        }.size

    private class Counter(private val limit: Long) {
        var size: Long = 0L
            private set

        private fun add(amount: Long) {
            size += amount
        }

        private fun overBudget(): Boolean = size > limit

        private fun sizePrefixBytes(value: Long): Long =
            when {
                value < 254L -> 1L
                value <= 0xffffL -> 3L
                else -> 5L
            }

        private fun writeSize(value: Long) {
            add(sizePrefixBytes(value))
        }

        private fun writeBytes(length: Long) {
            writeSize(length)
            add(length)
        }

        private fun align(alignment: Int) {
            val mod = (size % alignment).toInt()
            if (mod != 0) add((alignment - mod).toLong())
        }

        fun writeString(text: CharSequence) {
            add(TYPE_BYTE)
            // Each UTF-16 code unit needs at least one UTF-8 byte; when that
            // lower bound already breaks the budget, skip the full scan.
            if (size + 1L + text.length.toLong() > limit) {
                size = limit + 1L
                return
            }
            val bytes = utf8Length(text)
            writeSize(bytes)
            add(bytes)
        }

        fun writeBigInteger(value: BigInteger) {
            add(TYPE_BYTE)
            // Every hexadecimal representation has at least one byte ("0",
            // "1", "-1", ...), so the type byte plus the one-byte size prefix
            // already decides one- and two-byte budgets without inspecting the
            // magnitude at all.
            if (size + 1L + 1L > limit) {
                size = limit + 1L
                return
            }
            // A sign/bit-length lower bound is cheap and never scans the whole
            // magnitude. For negatives the exact digit count still needs
            // `bitCount()` to disambiguate a power-of-two magnitude from
            // `|value| - 1`; run that disambiguation only after the lower bound
            // has proven the representation cannot fit the remaining budget.
            val lowerBound = hexStringLengthLowerBound(value)
            if (size + sizePrefixBytes(lowerBound) + lowerBound > limit) {
                size = limit + 1L
                return
            }
            writeBytes(hexStringLength(value))
        }

        /**
         * Cheap lower bound of the `toString(16)` byte length from `signum` and
         * `bitLength()` only: no `bitCount()`, no full magnitude scan, no copy.
         *
         * Positives need exactly `ceil(bitLength / 4)` digits. For negatives
         * `bitLength()` describes `|value| - 1`, so the magnitude can add at
         * most one significant bit; `ceil(bitLength / 4)` digits plus the
         * leading `-` therefore never overstates the exact length.
         */
        private fun hexStringLengthLowerBound(value: BigInteger): Long {
            val signum = value.signum()
            val digits = (value.bitLength().toLong() + 3L) / 4L
            return when {
                signum == 0 -> 1L
                signum > 0 -> digits
                else -> digits + 1L
            }
        }

        /**
         * Exact byte length of `BigInteger.toString(16)` without materializing
         * that string. `StandardMessageCodec` writes the hexadecimal text (with
         * a leading `-` for negatives) as UTF-8, so its length equals the digit
         * count on this ASCII path.
         *
         * Positives need `ceil(bitLength / 4)` digits. For negatives,
         * `bitLength()` describes `|value| - 1`; only a power-of-two magnitude
         * adds one more significant bit, which `bitCount() == bitLength()`
         * identifies without allocating `abs()` or the hex text.
         */
        private fun hexStringLength(value: BigInteger): Long {
            val signum = value.signum()
            if (signum == 0) return 1L
            val bits = value.bitLength().toLong()
            if (signum > 0) return (bits + 3L) / 4L
            val magnitudeBits = if (value.bitCount().toLong() == bits) bits + 1L else bits
            return (magnitudeBits + 3L) / 4L + 1L
        }

        private fun writeTypedArray(elementBytes: Int, count: Int, alignment: Int) {
            add(TYPE_BYTE)
            writeSize(count.toLong())
            align(alignment)
            add(count.toLong() * elementBytes.toLong())
        }

        private fun writeList(count: Int, depth: Int, values: Iterator<*>) {
            if (depth >= MAX_DEPTH) throw PlatformFailure.invalidPayload("platform.payloadTooDeep")
            add(TYPE_BYTE)
            writeSize(count.toLong())
            var written = 0
            while (written < count && values.hasNext()) {
                writeValue(values.next(), depth + 1)
                written++
                if (overBudget()) return
            }
        }

        fun writeValue(value: Any?, depth: Int) {
            if (overBudget()) return
            when (value) {
                null -> add(1L)
                is Boolean -> add(1L)
                is Int, is Short, is Byte -> {
                    add(TYPE_BYTE)
                    add(4L)
                }
                is Long -> {
                    add(TYPE_BYTE)
                    add(8L)
                }
                is Float, is Double -> {
                    add(TYPE_BYTE)
                    align(8)
                    add(8L)
                }
                is BigInteger -> writeBigInteger(value)
                is String -> writeString(value)
                is CharSequence -> writeString(value)
                is ByteArray -> {
                    add(TYPE_BYTE)
                    writeBytes(value.size.toLong())
                }
                is IntArray -> writeTypedArray(4, value.size, 4)
                is LongArray -> writeTypedArray(8, value.size, 8)
                is DoubleArray -> writeTypedArray(8, value.size, 8)
                is FloatArray -> writeTypedArray(4, value.size, 4)
                is Map<*, *> -> {
                    if (depth >= MAX_DEPTH) {
                        throw PlatformFailure.invalidPayload("platform.payloadTooDeep")
                    }
                    add(TYPE_BYTE)
                    writeSize(value.size.toLong())
                    for ((key, child) in value) {
                        if (key !is String) {
                            throw PlatformFailure.invalidPayload("platform.nonStringKey")
                        }
                        writeString(key)
                        writeValue(child, depth + 1)
                        if (overBudget()) return
                    }
                }
                is List<*> -> writeList(value.size, depth, value.iterator())
                is Array<*> -> writeList(value.size, depth, value.iterator())
                is Iterable<*> -> {
                    // Collections expose their size without copying; only a
                    // non-Collection Iterable needs the one-pass snapshot, and
                    // StandardMessageCodec has no Iterable encoding at all.
                    if (value is Collection<*>) {
                        writeList(value.size, depth, value.iterator())
                    } else {
                        val items = value.toList()
                        writeList(items.size, depth, items.iterator())
                    }
                }
                else -> throw PlatformFailure.invalidPayload("platform.unsupportedValue")
            }
        }
    }

    /**
     * UTF-8 byte length as produced by `String.toByteArray(StandardCharsets.UTF_8)`,
     * without allocating the byte array. Malformed surrogate code units are
     * replaced by a single `?` byte, matching the JDK encoder's default. Takes
     * a [CharSequence] so the counter can measure a `CharSequence` payload
     * without materializing its `toString()` copy.
     */
    private fun utf8Length(text: CharSequence): Long {
        var bytes = 0L
        var index = 0
        while (index < text.length) {
            val unit = text[index]
            when {
                unit.code < 0x80 -> bytes += 1
                unit.code < 0x800 -> bytes += 2
                unit.isHighSurrogate() &&
                    index + 1 < text.length &&
                    text[index + 1].isLowSurrogate() -> {
                    bytes += 4
                    index++
                }
                unit.isSurrogate() -> bytes += 1
                else -> bytes += 3
            }
            index++
        }
        return bytes
    }
}

private sealed class FieldRule(
    val name: String,
    private val required: Boolean = true,
) {
    open fun apply(value: Any?) {
        if (value == null) {
            if (required) throw PlatformFailure.invalidPayload("platform.missingField")
            return
        }
        check(value)
    }

    protected abstract fun check(value: Any?)
}

private class StringRule(
    name: String,
    private val maxLength: Int,
    required: Boolean = true,
    private val exact: String? = null,
    private val pattern: Regex? = null,
    private val rejectPathSeparators: Boolean = false,
    private val failure: () -> PlatformFailure = { PlatformFailure.invalidPayload("platform.invalidString") },
) : FieldRule(name, required) {
    override fun check(value: Any?) {
        val text = value as? String ?: throw failure()
        if (text.isEmpty()) throw failure()
        if (text.length > maxLength) throw failure()
        if (hasControlCharacters(text)) throw failure()
        if (rejectPathSeparators && (text.contains('/') || text.contains('\\'))) throw failure()
        exact?.let { if (text != it) throw failure() }
        pattern?.let { if (!it.matches(text)) throw failure() }
    }
}

private class OptionalStringRule(
    name: String,
    private val maxLength: Int,
    private val pattern: Regex? = null,
    private val failure: () -> PlatformFailure = { PlatformFailure.invalidPayload("platform.invalidString") },
) : FieldRule(name, required = false) {
    override fun check(value: Any?) {
        val text = value as? String ?: throw failure()
        if (text.length > maxLength) throw failure()
        if (hasControlCharacters(text)) throw failure()
        pattern?.let { if (!it.matches(text)) throw failure() }
    }
}

private class UuidRule(
    name: String,
    required: Boolean = true,
    private val nullable: Boolean = false,
) : FieldRule(name, required) {
    override fun apply(value: Any?) {
        if (value == null && nullable) return
        super.apply(value)
    }

    override fun check(value: Any?) {
        val text = value as? String ?: throw PlatformFailure.invalidIdentifier()
        if (!UUID_PATTERN.matches(text)) throw PlatformFailure.invalidIdentifier()
    }
}

/**
 * Exact integral value of a channel integer, or `null` when it is not a finite
 * integer. Bounds must be applied to this exact value before any conversion:
 * `Double.toLong()` saturates out-of-range magnitudes to `Long.MAX_VALUE`, so a
 * post-conversion bound whose max is `Long.MAX_VALUE` would otherwise accept a
 * finite but out-of-range Double such as `1e20` or the rounded `2^63` that
 * `Long.MAX_VALUE.toDouble()` produces. Integral JVM number types are taken
 * verbatim so a genuine `Long.MAX_VALUE` stays a valid boundary.
 */
private fun exactChannelInteger(number: Number): BigDecimal? {
    val double = number.toDouble()
    if (!double.isFinite() || double % 1.0 != 0.0) return null
    return when (number) {
        is Long, is Int, is Short, is Byte -> BigDecimal(number.toLong())
        is BigInteger -> BigDecimal(number)
        is BigDecimal -> number
        else -> BigDecimal(double)
    }
}

private class IntRule(
    name: String,
    private val min: Int,
    private val max: Int,
    required: Boolean = true,
) : FieldRule(name, required) {
    override fun check(value: Any?) {
        val number = value as? Number ?: throw PlatformFailure.invalidPayload("platform.invalidInteger")
        val exact = exactChannelInteger(number)
            ?: throw PlatformFailure.invalidPayload("platform.invalidInteger")
        if (exact < BigDecimal(min) || exact > BigDecimal(max)) {
            throw PlatformFailure.invalidPayload("platform.valueOutOfRange")
        }
    }
}

private class LongRule(
    name: String,
    private val min: Long,
    private val max: Long,
    required: Boolean = true,
) : FieldRule(name, required) {
    override fun check(value: Any?) {
        val number = value as? Number ?: throw PlatformFailure.invalidPayload("platform.invalidInteger")
        val exact = exactChannelInteger(number)
            ?: throw PlatformFailure.invalidPayload("platform.invalidInteger")
        if (exact < BigDecimal(min) || exact > BigDecimal(max)) {
            throw PlatformFailure.invalidPayload("platform.valueOutOfRange")
        }
    }
}

private class DoubleRule(
    name: String,
    private val minExclusive: Double = 0.0,
    required: Boolean = true,
) : FieldRule(name, required) {
    override fun check(value: Any?) {
        val number = value as? Number ?: throw PlatformFailure.invalidPayload("platform.invalidNumber")
        val converted = number.toDouble()
        if (!converted.isFinite() || converted <= minExclusive) {
            throw PlatformFailure.invalidPayload("platform.invalidNumber")
        }
    }
}

private class BytesRule(
    name: String,
    private val maxBytes: Long,
    private val failure: () -> PlatformFailure = { PlatformFailure.invalidPayload("platform.payloadTooLarge") },
) : FieldRule(name, required = true) {
    override fun check(value: Any?) {
        val bytes = value as? ByteArray ?: throw failure()
        if (bytes.size.toLong() > maxBytes) throw failure()
    }
}

private class MapRule(
    name: String,
    private val maxEstimatedBytes: Long = Long.MAX_VALUE,
    private val failure: () -> PlatformFailure = { PlatformFailure.invalidPayload("platform.invalidMap") },
) : FieldRule(name, required = true) {
    override fun check(value: Any?) {
        if (value !is Map<*, *>) throw failure()
        if (maxEstimatedBytes != Long.MAX_VALUE &&
            PayloadSize.measure(value, maxEstimatedBytes) > maxEstimatedBytes
        ) {
            throw failure()
        }
    }
}

private class EnumRule(
    name: String,
    private val values: Set<String>,
    required: Boolean = true,
) : FieldRule(name, required) {
    override fun check(value: Any?) {
        val text = value as? String ?: throw PlatformFailure.invalidPayload("platform.invalidEnum")
        if (text !in values) throw PlatformFailure.invalidPayload("platform.invalidEnum")
    }
}

private class Sha256Rule(name: String) : FieldRule(name, required = true) {
    override fun check(value: Any?) {
        val text = value as? String ?: throw PlatformFailure.invalidPayload("platform.invalidHash")
        if (!SHA256_PATTERN.matches(text)) throw PlatformFailure.invalidPayload("platform.invalidHash")
    }
}

private class ConfirmRule(name: String) : FieldRule(name, required = true) {
    override fun check(value: Any?) {
        val confirmation = value as? Map<*, *>
            ?: throw PlatformFailure.invalidPayload("platform.invalidConfirmation")
        val allowed = setOf("title", "acknowledged")
        for (key in confirmation.keys) {
            if (key !is String || key !in allowed) {
                throw PlatformFailure.invalidPayload("platform.unknownField")
            }
        }
        val title = confirmation["title"] as? String
            ?: throw PlatformFailure.invalidPayload("platform.invalidConfirmation")
        if (title.isEmpty() || title.length > 200 || hasControlCharacters(title)) {
            throw PlatformFailure.invalidPayload("platform.invalidConfirmation")
        }
        val acknowledged = confirmation["acknowledged"] as? Boolean
            ?: throw PlatformFailure.invalidPayload("platform.invalidConfirmation")
        if (!acknowledged) throw PlatformFailure.invalidSavedData()
    }
}

private class MethodSpec(
    val name: String,
    val fields: List<FieldRule>,
    val postValidate: ((Map<String, Any?>) -> Unit)? = null,
) {
    val allowedFields: Set<String> = fields.mapTo(linkedSetOf()) { it.name } + "schemaVersion"
}

private class MethodCatalog(private val limits: ChannelLimits) {
    private val specs: Map<String, MethodSpec> = listOf(
        MethodSpec(
            "import.pickAndImport",
            listOf(
                LongRule("maxBytes", 1L, limits.maxSourceBytes),
                OptionalStringRule("titleHint", limits.maxTitleLength),
            ),
        ),
        MethodSpec("import.verifySource", listOf(UuidRule("sourceId"))),
        MethodSpec(
            "import.discardStaged",
            listOf(
                StringRule(
                    "txnId",
                    128,
                    pattern = Regex("^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"),
                ),
            ),
        ),
        MethodSpec("store.status", emptyList()),
        MethodSpec("store.list", listOf(EnumRule("kind", setOf("document", "template")))),
        MethodSpec(
            "store.stageSource",
            listOf(
                UuidRule("documentId"),
                UuidRule("sourceId"),
                BytesRule(
                    "bytes",
                    limits.maxSourceBytes,
                    failure = {
                        PlatformFailure("IMP-007", "tooLarge", false, "import.tooLarge")
                    },
                ),
                Sha256Rule("sha256"),
            ),
        ),
        MethodSpec(
            "store.createDocument",
            listOf(
                UuidRule("documentId"),
                StringRule("title", limits.maxTitleLength),
                MapRule("source", 64L * 1024L),
                MapRule(
                    "initialRevision",
                    limits.maxRevisionBytes,
                    PlatformFailure::invalidSavedData,
                ),
            ),
        ),
        MethodSpec(
            "store.startupRecovery",
            listOf(LongRule("deadlineEpochMs", 1L, Long.MAX_VALUE, required = false)),
        ),
        MethodSpec("store.readSource", listOf(UuidRule("documentId"))),
        MethodSpec(
            "store.readSignature",
            listOf(UuidRule("documentId"), UuidRule("assetId")),
        ),
        MethodSpec(
            "store.writeSignature",
            listOf(
                UuidRule("documentId"),
                UuidRule("assetId"),
                BytesRule("bytes", limits.maxSignatureBytes, PlatformFailure::invalidSavedData),
                Sha256Rule("sha256"),
            ),
        ),
        MethodSpec(
            "store.saveRevision",
            listOf(
                UuidRule("documentId"),
                MapRule(
                    "revision",
                    limits.maxRevisionBytes,
                    PlatformFailure::invalidSavedData,
                ),
                UuidRule("expectedHead", required = false, nullable = true),
                EnumRule("kind", setOf("autosave", "explicit", "recovery")),
            ),
        ),
        MethodSpec(
            "store.createTemplate",
            listOf(
                MapRule("template"),
                MapRule("revision", limits.maxRevisionBytes, PlatformFailure::invalidSavedData),
            ),
        ),
        MethodSpec(
            "store.saveTemplateVersion",
            listOf(
                UuidRule("templateId"),
                MapRule("version"),
                UuidRule("expectedHead", required = false, nullable = true),
            ),
        ),
        MethodSpec("store.loadDocument", listOf(UuidRule("documentId"))),
        MethodSpec(
            "store.loadTemplate",
            listOf(
                UuidRule("templateId"),
                UuidRule("versionId", required = false, nullable = true),
            ),
        ),
        MethodSpec(
            "store.delete",
            listOf(
                EnumRule("kind", setOf("document", "template")),
                UuidRule("id"),
                ConfirmRule("confirm"),
            ),
        ),
        MethodSpec(
            "store.recoveryStamp",
            listOf(EnumRule("kind", setOf("document", "template")), UuidRule("id")),
        ),
        MethodSpec(
            "ocr.recognize",
            listOf(
                IntRule("pageIndex", 0, Int.MAX_VALUE),
                IntRule("imageWidth", 1, limits.maxOcrEdgePx),
                IntRule("imageHeight", 1, limits.maxOcrEdgePx),
                DoubleRule("pageWidthPt"),
                DoubleRule("pageHeightPt"),
                EnumRule("format", setOf("gray8", "rgba8888")),
                BytesRule("bytes", limits.maxOcrEdgePx.toLong() * limits.maxOcrEdgePx.toLong() * 4L),
                StringRule("language", 16, exact = "de"),
            ),
            postValidate = { payload ->
                val width = (payload["imageWidth"] as Number).toLong()
                val height = (payload["imageHeight"] as Number).toLong()
                val channels = if (payload["format"] == "gray8") 1L else 4L
                val expectedBytes = width * height * channels
                val actualBytes = (payload["bytes"] as ByteArray).size.toLong()
                if (actualBytes != expectedBytes) {
                    throw PlatformFailure.invalidPayload("platform.invalidRaster")
                }
            },
        ),
        MethodSpec(
            "export.validate",
            listOf(MapRule("plan", limits.maxExportPlanBytes)),
        ),
        MethodSpec(
            "export.render",
            listOf(MapRule("plan", limits.maxExportPlanBytes)),
        ),
        MethodSpec("export.readArtifact", listOf(UuidRule("artifactId"))),
        MethodSpec("export.deleteArtifact", listOf(UuidRule("artifactId"))),
        MethodSpec(
            "delivery.save",
            listOf(
                UuidRule("artifactId"),
                StringRule(
                    "suggestedName",
                    limits.maxSuggestedNameLength,
                    rejectPathSeparators = true,
                ),
            ),
        ),
        MethodSpec(
            "delivery.share",
            listOf(
                UuidRule("artifactId"),
                StringRule("mimeType", 128, exact = "application/pdf"),
            ),
        ),
        MethodSpec(
            "delivery.print",
            listOf(UuidRule("artifactId"), StringRule("jobName", 200)),
        ),
        MethodSpec("cancel.operation", listOf(UuidRule("operationId"))),
        MethodSpec(
            "platform.sensitiveRoute",
            listOf(EnumRule("route", SensitiveRouteHost.ROUTES)),
        ),
    ).associateBy { it.name }

    fun specFor(method: String): MethodSpec? = specs[method]
}

private const val UUID_REGEX =
    "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
private val UUID_PATTERN = Regex(UUID_REGEX)
private val SHA256_PATTERN = Regex("^[0-9a-fA-F]{64}$")

private fun hasControlCharacters(text: String): Boolean = text.any { it == '\u0000' || Character.isISOControl(it) }
