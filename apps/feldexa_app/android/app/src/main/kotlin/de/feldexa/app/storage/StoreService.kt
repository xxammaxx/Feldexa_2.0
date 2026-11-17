package de.feldexa.app.storage

import de.feldexa.app.OperationContext
import de.feldexa.app.PlatformFailure
import de.feldexa.app.PlatformRequest
import de.feldexa.app.PlatformService
import java.io.File
import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

/**
 * T027 secure-store implementation of the T024 [PlatformService] contract.
 *
 * It is deliberately a thin translation layer over the already-tested T026
 * [EncryptedStore] and T025 [KeystoreService]. It owns no encryption, key
 * lifecycle, commit protocol, or recovery algorithm: those remain in the
 * storage classes so the `FXC1` format has one implementation. This service
 * validates the channel DTOs, serializes the canonical metadata/revision
 * payloads, invokes the store, and projects only read-back-committed data into
 * the channel response.
 *
 * Content rules: no method response or failure carries a title, path, alias,
 * source byte, revision body, or OCR/field content. The only content-bearing
 * result is the explicitly requested `store.readSource`/`store.readSignature`
 * byte array and the `store.loadDocument` payload the authenticated store
 * returned.
 */
class StoreService(
    private val store: EncryptedStore,
    private val clock: () -> Long = System::currentTimeMillis,
    private val idGenerator: () -> String = { UUID.randomUUID().toString() },
) : PlatformService {

    override fun handle(request: PlatformRequest, context: OperationContext): Any? {
        return try {
            when (request.method) {
                "store.status" -> status()
                "store.list" -> list(request)
                "store.stageSource" -> stageSource(request)
                "store.createDocument" -> createDocument(request)
                "store.readSource" -> readSource(request)
                "store.readSignature" -> readSignature(request)
                "store.writeSignature" -> writeSignature(request, context)
                "store.saveRevision" -> saveRevision(request, context)
                "store.loadDocument" -> loadDocument(request)
                "store.delete" -> delete(request)
                "store.recoveryStamp" -> recoveryStamp(request)
                "store.startupRecovery" -> startupRecovery(request)
                // The template channel payload is not normatively specified by
                // `contracts/platform-channel.md` §4 (it only shows `{…}`), and
                // `CreateTemplateRequest` carries no template id. Inventing a
                // wire shape here would create a second, untraceable contract.
                // Template methods stay fail-closed until their task defines it.
                "store.createTemplate",
                "store.saveTemplateVersion",
                "store.loadTemplate",
                -> throw PlatformFailure.unsupported()
                else -> throw PlatformFailure.unsupported()
            }
        } catch (failure: PlatformFailure) {
            throw failure
        } catch (failure: Exception) {
            throw mapFailure(failure)
        }
    }

    override fun onFacadeDetached() {
        // The store keeps durable user data. No channel-owned object exists to
        // discard on detach.
    }

    // ------------------------------------------------------------------
    // Reads
    // ------------------------------------------------------------------

    private fun status(): Map<String, Any?> {
        val status = store.status()
        return linkedMapOf(
            "keyAvailable" to status.keyAvailable,
            "objectCount" to status.objectCount,
            "totalBytes" to status.totalBytes,
        )
    }

    private fun list(request: PlatformRequest): Map<String, Any?> {
        val kind = kindOf(request.string("kind"))
        return linkedMapOf(
            "items" to store.list(kind).map { projectListing(it) },
        )
    }

    private fun loadDocument(request: PlatformRequest): Map<String, Any?> {
        val documentId = requireUuid(request.string("documentId"), "documentId")
        val loaded = store.loadDocument(documentId)
        val head = loaded.head
        val meta = parseObject(loaded.metaPlaintext)
        // The persisted meta is written at creation; later saves only move the
        // verified head. Project the current head into the returned metadata so
        // the caller never sees a stale latestRevisionId/lastDurableAt.
        val projected = LinkedHashMap<String, Any?>(meta)
        projected["latestRevisionId"] = head.revisionId
        projected["lastDurableAt"] = head.committedAt
        projected["updatedAt"] = head.committedAt
        projected["readable"] = true
        projected["unreadableReasonCode"] = null
        return linkedMapOf(
            "meta" to projected,
            "revision" to parseObject(loaded.revisionPlaintext),
            "head" to headMap(head),
        )
    }

    private fun readSource(request: PlatformRequest): ByteArray {
        val documentId = requireUuid(request.string("documentId"), "documentId")
        return store.loadDocument(documentId).sourceBytes
    }

    private fun readSignature(request: PlatformRequest): ByteArray {
        val documentId = requireUuid(request.string("documentId"), "documentId")
        val assetId = requireUuid(request.string("assetId"), "assetId")
        return store.readSignature(documentId, assetId)
    }

    private fun recoveryStamp(request: PlatformRequest): Map<String, Any?> {
        val kind = kindOf(request.string("kind"))
        val id = requireUuid(request.string("id"), "id")
        val stamp = store.recoveryStamp(kind, id)
        return linkedMapOf(
            "verifiedRevisionId" to stamp.verifiedRevisionId,
            "committedAt" to stamp.committedAt,
            "headCorrupt" to stamp.headCorrupt,
            "fellBackToOlderRevision" to stamp.fellBackToOlderRevision,
        )
    }

    private fun startupRecovery(request: PlatformRequest): Map<String, Any?> {
        val deadlineEpochMs = request.number("deadlineEpochMs")?.toLong()
        val report = store.startupRecovery(deadlineEpochMs = deadlineEpochMs)
        return linkedMapOf(
            "tempEntriesRemoved" to report.tempEntriesRemoved,
            "incompleteAggregatesRemoved" to report.incompleteAggregatesRemoved,
            "unreadableAggregates" to report.unreadableAggregates,
            "fallbackAdoptions" to report.fallbackAdoptions,
            "orphanAliasesRemoved" to report.orphanAliasesRemoved,
            "orphanAliasesRetained" to report.orphanAliasesRetained,
            "orphanAliasesFailed" to report.orphanAliasesFailed,
            "aliasSweepSkipped" to report.aliasSweepSkipped,
            "ambiguousRevisionOrder" to report.ambiguousRevisionOrder,
            "prunedRevisions" to report.prunedRevisions,
            "deadlineReached" to report.deadlineReached,
        )
    }

    // ------------------------------------------------------------------
    // Writes
    // ------------------------------------------------------------------

    private fun stageSource(request: PlatformRequest): Map<String, Any?> {
        val documentId = requireUuid(request.string("documentId"), "documentId")
        val sourceId = requireUuid(request.string("sourceId"), "sourceId")
        val bytes = request.bytes("bytes")
            ?: throw PlatformFailure.invalidPayload("platform.missingField")
        val sha256 = requireSha256(request.string("sha256"), "sha256")
        if (bytes.size.toLong() > MAX_SOURCE_BYTES) {
            throw PlatformFailure("IMP-007", "tooLarge", false, "import.tooLarge")
        }
        val receipt = store.stageSource(documentId, sourceId, bytes, sha256)
        return linkedMapOf(
            "sourceId" to receipt.sourceId,
            "sha256" to receipt.sourceSha256,
            "sizeBytes" to receipt.sizeBytes,
            "verified" to receipt.readBackVerified,
        )
    }

    private fun createDocument(request: PlatformRequest): Map<String, Any?> {
        val documentId = requireUuid(request.string("documentId"), "documentId")
        val title = requireTitle(request.string("title"))
        val source = requireMap(request.map("source"), "source")
        val sourceId = requireUuid(source["id"] as? String, "source.id")
        val sourceSha = requireSha256(source["sha256"] as? String, "source.sha256")
        val sourceSize = requireLong(source["sizeBytes"], "source.sizeBytes", 1L, MAX_SOURCE_BYTES)
        val pageCount = requireLong(source["pageCount"], "source.pageCount", 1L, 100L)
        val importedAt = requireCanonicalInstant(source["importedAt"], "source.importedAt")
        requireVerifiedIntegrity(source["integrity"])
        // Persist a canonical timestamp while retaining the importer's opaque
        // same-schema extension fields.
        val normalizedSource = LinkedHashMap<String, Any?>(source)
        normalizedSource["importedAt"] = importedAt

        val initial = requireMap(request.map("initialRevision"), "initialRevision")
        val revisionId = requireUuid(initial["id"] as? String, "initialRevision.id")
        if (initial["documentId"] != documentId) {
            throw PlatformFailure.invalidPayload("platform.invalidIdentifier")
        }
        if (initial["parentRevisionId"] != null) {
            // The initial revision is the first identity; a parent would chain
            // it behind an unrelated aggregate.
            throw PlatformFailure.invalidSavedData()
        }
        val revisionKind = RevisionKindWire.fromWire(
            initial["kind"] as? String
                ?: throw PlatformFailure.invalidPayload("platform.invalidEnum"),
        ) ?: throw PlatformFailure.invalidPayload("platform.invalidEnum")
        val revisionCreatedAt = requireCanonicalInstant(
            initial["createdAt"],
            "initialRevision.createdAt",
        )
        val revisionSha = requireSha256(
            initial["plaintextSha256"] as? String,
            "initialRevision.plaintextSha256",
        )
        val content = requireMap(initial["content"] as? Map<*, *>, "initialRevision.content")
        if (content.containsKey("source")) {
            throw PlatformFailure.invalidSavedData()
        }
        val revisionBytes = canonicalBytes(content)
        if (sha256Hex(revisionBytes) != revisionSha) {
            // The importer's revision hash must describe exactly the canonical
            // content bytes the store will persist.
            throw PlatformFailure.invalidSavedData()
        }

        val now = nowIso()
        val meta = linkedMapOf<String, Any?>(
            "id" to documentId,
            "kind" to "document",
            "title" to title,
            "createdAt" to revisionCreatedAt,
            "updatedAt" to now,
            "source" to normalizedSource,
            "latestRevisionId" to revisionId,
            "lastDurableAt" to now,
            "readable" to true,
            "unreadableReasonCode" to null,
        )
        // The staged source is authenticated by the store against the
        // importer's hash/size before the revision, head, or meta is written.
        store.createDocumentFromStagedSource(
            documentId = documentId,
            metaJson = canonicalBytes(meta),
            sourceId = sourceId,
            sourceSha256 = sourceSha,
            sourceSizeBytes = sourceSize,
            revisionId = revisionId,
            revisionJson = revisionBytes,
            revisionKind = revisionKind,
        )
        val created = store.list(AggregateKind.DOCUMENT)
            .firstOrNull { it.aggregateId == documentId }
            ?: throw CorruptDataException()
        if (!created.readable) throw CorruptDataException()
        return projectListing(created)
    }

    private fun saveRevision(
        request: PlatformRequest,
        context: OperationContext,
    ): Map<String, Any?> {
        val documentId = requireUuid(request.string("documentId"), "documentId")
        val revisionMap = requireMap(request.map("revision"), "revision")
        if (revisionMap.containsKey("source")) {
            throw PlatformFailure.invalidSavedData()
        }
        val kind = RevisionKindWire.fromWire(
            request.string("kind")
                ?: throw PlatformFailure.invalidPayload("platform.invalidEnum"),
        ) ?: throw PlatformFailure.invalidPayload("platform.invalidEnum")
        val expectedHead = optionalUuid(request.payload["expectedHead"], "expectedHead")
        context.checkCancelled()
        val revisionId = idGenerator()
        if (!UUID_V4.matches(revisionId.lowercase(Locale.ROOT))) {
            throw PlatformFailure.internal()
        }
        val revisionBytes = canonicalBytes(revisionMap)
        val receipt = store.saveRevision(
            documentId = documentId,
            revisionId = revisionId,
            revisionJson = revisionBytes,
            revisionKind = kind,
            expectedHead = expectedHead,
        )
        return linkedMapOf(
            "revisionId" to receipt.revisionId,
            "committedAt" to receipt.committedAt,
            "sha256" to receipt.plaintextSha256,
            "verified" to receipt.readBackVerified,
            "prunedRevisions" to receipt.prunedRevisions,
        )
    }

    private fun writeSignature(
        request: PlatformRequest,
        context: OperationContext,
    ): Map<String, Any?> {
        val documentId = requireUuid(request.string("documentId"), "documentId")
        val assetId = requireUuid(request.string("assetId"), "assetId")
        val bytes = request.bytes("bytes")
            ?: throw PlatformFailure.invalidPayload("platform.missingField")
        val sha256 = requireSha256(request.string("sha256"), "sha256")
        if (sha256Hex(bytes) != sha256) throw PlatformFailure.invalidSavedData()
        context.checkCancelled()
        store.writeSignature(documentId, assetId, bytes)
        // Re-read through the store's authenticated path before claiming true.
        val readBack = store.readSignature(documentId, assetId)
        if (sha256Hex(readBack) != sha256) throw CorruptDataException()
        return linkedMapOf("verified" to true)
    }

    private fun delete(request: PlatformRequest): Map<String, Any?> {
        val kind = kindOf(request.string("kind"))
        val id = requireUuid(request.string("id"), "id")
        val confirm = requireMap(request.map("confirm"), "confirm")
        val title = requireString(confirm["title"] as? String, "confirm.title", 200)
        val acknowledged = confirm["acknowledged"] as? Boolean
            ?: throw PlatformFailure.invalidPayload("platform.invalidConfirmation")
        if (!acknowledged) throw PlatformFailure.invalidSavedData()
        val receipt = store.delete(
            kind = kind,
            id = id,
            confirmation = DeleteConfirmation(acknowledged = true, title = title),
            notReadableTitle = NOT_READABLE_TITLE,
        )
        return linkedMapOf(
            "deleted" to receipt.directoryDeleted,
            "freedBytes" to receipt.freedBytes,
        )
    }

    // ------------------------------------------------------------------
    // Projection
    // ------------------------------------------------------------------

    private fun projectListing(listing: AggregateListing): Map<String, Any?> {
        val kind = listing.aggregateKind.name.lowercase(Locale.ROOT)
        val meta = listing.metaPlaintext?.let { runCatching { parseObject(it) }.getOrNull() }
        if (listing.readable && meta != null) {
            val id = requireUuidOrNull(meta["id"] as? String) ?: listing.aggregateId
            val title = (meta["title"] as? String)?.takeIf { it.isNotEmpty() }
                ?: NOT_READABLE_TITLE
            val createdAt = canonicalOrNull(meta["createdAt"]) ?: observedInstant(listing)
            val head = listing.head
            return linkedMapOf(
                "id" to id,
                "kind" to kind,
                "title" to title,
                "createdAt" to createdAt,
                "updatedAt" to (head?.committedAt ?: canonicalOrNull(meta["updatedAt"]) ?: createdAt),
                "latestRevisionId" to head?.revisionId,
                "lastDurableAt" to head?.committedAt,
                "readable" to true,
                "unreadableReasonCode" to null,
            )
        }
        val observed = observedInstant(listing)
        return linkedMapOf(
            "id" to listing.aggregateId,
            "kind" to kind,
            "title" to NOT_READABLE_TITLE,
            "createdAt" to observed,
            "updatedAt" to observed,
            "latestRevisionId" to null,
            "lastDurableAt" to null,
            "readable" to false,
            "unreadableReasonCode" to (listing.unreadableReasonCode ?: "SAVE-003"),
        )
    }

    private fun headMap(head: CommittedHead): Map<String, Any?> = linkedMapOf(
        "revisionId" to head.revisionId,
        "plaintextSha256" to head.plaintextSha256,
        "committedAt" to head.committedAt,
        "parentRevisionId" to head.parentRevisionId,
        "kind" to head.kind.wireName,
        "history" to head.history.map {
            linkedMapOf("revisionId" to it.revisionId, "kind" to it.kind?.wireName)
        },
    )

    /**
     * An unreadable aggregate has no decryptable meta timestamp. The directory
     * mtime is the only honest observed instant; it is never derived from
     * ciphertext or an invented title.
     */
    private fun observedInstant(listing: AggregateListing): String {
        val container = if (listing.aggregateKind == AggregateKind.DOCUMENT) "docs" else "templates"
        val directory = File(File(store.root, container), listing.aggregateId)
        val millis = directory.lastModified().takeIf { it > 0L } ?: clock()
        return ISO_MILLIS.format(Instant.ofEpochMilli(millis))
    }

    // ------------------------------------------------------------------
    // Validation helpers
    // ------------------------------------------------------------------

    private fun kindOf(value: String?): AggregateKind = when (value) {
        "document" -> AggregateKind.DOCUMENT
        "template" -> AggregateKind.TEMPLATE
        else -> throw PlatformFailure.invalidPayload("platform.invalidEnum")
    }

    private fun requireUuid(value: String?, name: String): String {
        if (value == null || !UUID_V4.matches(value)) {
            throw PlatformFailure.invalidIdentifier()
        }
        return value
    }

    private fun optionalUuid(value: Any?, name: String): String? {
        if (value == null) return null
        return requireUuid(value as? String, name)
    }

    private fun requireUuidOrNull(value: String?): String? =
        value?.takeIf { UUID_V4.matches(it) }

    private fun requireSha256(value: String?, name: String): String {
        if (value == null || !SHA256.matches(value)) {
            throw PlatformFailure.invalidPayload("platform.invalidHash")
        }
        return value
    }

    private fun requireTitle(value: String?): String {
        val trimmed = value?.trim() ?: ""
        if (trimmed.isEmpty() || trimmed.length > MAX_TITLE_LENGTH || hasControl(trimmed)) {
            throw PlatformFailure.invalidPayload("platform.invalidString")
        }
        return trimmed
    }

    private fun requireString(value: String?, name: String, max: Int): String {
        if (value == null || value.isEmpty() || value.length > max || hasControl(value)) {
            throw PlatformFailure.invalidPayload("platform.invalidString")
        }
        return value
    }

    private fun requireMap(value: Map<*, *>?, name: String): Map<String, Any?> {
        if (value == null) throw PlatformFailure.invalidPayload("platform.invalidMap")
        val result = LinkedHashMap<String, Any?>()
        for ((key, child) in value) {
            if (key !is String) throw PlatformFailure.invalidPayload("platform.nonStringKey")
            result[key] = child
        }
        return result
    }

    private fun requireLong(value: Any?, name: String, min: Long, max: Long): Long {
        val number = value as? Number
            ?: throw PlatformFailure.invalidPayload("platform.invalidInteger")
        val asDouble = number.toDouble()
        if (!asDouble.isFinite() || asDouble % 1.0 != 0.0) {
            throw PlatformFailure.invalidPayload("platform.invalidInteger")
        }
        val converted = number.toLong()
        if (converted < min || converted > max) {
            throw PlatformFailure.invalidPayload("platform.valueOutOfRange")
        }
        return converted
    }

    private fun requireVerifiedIntegrity(value: Any?) {
        if (value != "verified") {
            // An unreadable staged source must never become a visible
            // document; the importer reports the rejection instead.
            throw PlatformFailure.invalidPayload("platform.invalidEnum")
        }
    }

    private fun requireCanonicalInstant(value: Any?, name: String): String {
        val text = value as? String
            ?: throw PlatformFailure.invalidPayload("platform.invalidString")
        return try {
            ISO_MILLIS.format(Instant.parse(text))
        } catch (failure: Exception) {
            throw PlatformFailure.invalidPayload("platform.invalidString")
        }
    }

    private fun canonicalOrNull(value: Any?): String? {
        val text = value as? String ?: return null
        return try {
            ISO_MILLIS.format(Instant.parse(text))
        } catch (failure: Exception) {
            null
        }
    }

    private fun parseObject(bytes: ByteArray): Map<String, Any?> {
        val parsed = try {
            CanonicalJson.parse(bytes)
        } catch (failure: Exception) {
            throw CorruptDataException()
        }
        return requireMap(parsed as? Map<*, *>, "stored")
    }

    private fun canonicalBytes(value: Map<String, Any?>): ByteArray {
        return try {
            CanonicalJson.encode(value)
        } catch (failure: IllegalArgumentException) {
            throw PlatformFailure.invalidSavedData()
        }
    }

    private fun mapFailure(failure: Exception): PlatformFailure = when (failure) {
        is KeyUnavailableException -> PlatformFailure(
            "SAVE-002", "keyUnavailable", false, "save.keyUnavailable",
        )
        is KeystoreUnavailableException -> PlatformFailure(
            "SAVE-008", "keystoreUnavailable", failure.retryable, "save.keystoreUnavailable",
        )
        is CorruptDataException -> PlatformFailure(
            "SAVE-003", "corruptData", false, "save.corruptData",
        )
        is StorageWriteException -> PlatformFailure(
            "SAVE-003", "corruptData", true, "save.writeFailed",
        )
        is StorageFullException -> PlatformFailure(
            "SAVE-001", "storageFull", true, "save.storageFull",
        )
        is SchemaTooNewException -> PlatformFailure(
            "SAVE-005", "schemaTooNew", false, "save.schemaTooNew",
        )
        is ConcurrentSaveException -> PlatformFailure(
            "SAVE-006", "concurrentWrite", true, "save.concurrentWrite",
        )
        is InvalidDataException -> PlatformFailure(
            "SAVE-007", "invalidData", false, "save.invalidData",
        )
        is PlatformSecurityException -> PlatformFailure.invalidIdentifier()
        else -> PlatformFailure.internal()
    }

    private fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") {
            "%02x".format(it.toInt() and 0xFF)
        }

    private fun nowIso(): String = ISO_MILLIS.format(Instant.ofEpochMilli(clock()))

    private fun hasControl(text: String): Boolean =
        text.any { it == '\u0000' || Character.isISOControl(it) }

    private companion object {
        const val MAX_TITLE_LENGTH = 200
        const val NOT_READABLE_TITLE = "Nicht lesbar"
        const val MAX_SOURCE_BYTES = 80L * 1024L * 1024L
        val UUID_V4 = Regex(
            "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
        )
        val SHA256 = Regex("^[0-9a-f]{64}$")
        val ISO_MILLIS: DateTimeFormatter =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")
                .withZone(ZoneOffset.UTC)
    }
}
