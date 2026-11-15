package de.feldexa.app.storage

import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import java.security.MessageDigest
import java.security.SecureRandom
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import java.util.zip.CRC32
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * T026: `FXC1` encrypted store.
 *
 * Implements `contracts/storage-format.md`:
 *  * the 160-byte `FXC1` v1 header and authenticated chunk records (§2);
 *  * per-aggregate KEK selection through [KeystoreService] (§2.3);
 *  * the staged, verified, atomically promoted commit protocol (§3.1–§3.4);
 *  * aggregate deletion with the KEK alias removed last (§3.6);
 *  * startup recovery, stale-temp sweep, and orphan-alias sweep (§4).
 *
 * The store owns no Android framework type. It is testable on the JVM with a
 * fake [KeystoreBackend] and with a native fault injector; the production
 * adapters supply [RealStoreIo] and [KeystoreService.forAndroid].
 *
 * Integrity rules enforced on every read:
 *  * header magic, version, flags, reserved bytes, CRC-32, file id, chunk size,
 *    chunk count, wrapped-key length, and exact file length;
 *  * per-chunk AES-256-GCM authentication with the normative AAD;
 *  * the full plaintext SHA-256 against the header value.
 *
 * Failure mapping (`contracts/storage-format.md` §5):
 *  * `ENOSPC`/`EDQUOT` at any stage → [StorageFullException] (`SAVE-001`);
 *  * any other write/fsync/promote failure → [StorageWriteException]
 *    (`SAVE-003`), staged file removed, previous head intact;
 *  * a missing/invalidated aggregate KEK with a usable sibling → 
 *    [KeyUnavailableException] (`SAVE-002`);
 *  * provider outage or no usable aggregate key → 
 *    [KeystoreUnavailableException] (`SAVE-008`);
 *  * authentication/integrity damage while the KEK works → 
 *    [CorruptDataException] (`SAVE-003`);
 *  * a newer container/schema version → [SchemaTooNewException] (`SAVE-005`).
 *
 * No exception carries a path, file name, title, plaintext, or key byte.
 */
class EncryptedStore(
    private val root: File,
    private val keystore: KeystoreService,
    private val io: StoreIo = RealStoreIo(),
    private val faultInjector: StoreFaultInjector = StoreFaultInjector.NONE,
    private val clock: () -> Long = System::currentTimeMillis,
    private val random: SecureRandom = SecureRandom(),
    private val idGenerator: () -> String = { UUID.randomUUID().toString() },
    /**
     * Optional T031 hook. The store deliberately does not parse revision
     * plaintext, so signature reference discovery is supplied by the caller
     * that owns revision content. When null, §4 step 3 is skipped here and
     * stays with T031; stale temp and orphan aliases are still swept.
     */
    private val signatureReferenceResolver:
        ((documentId: String, assetId: String) -> Boolean)? = null,
) {

    init {
        require(root.isAbsolute) { "store.rootMustBeAbsolute" }
    }

    // ------------------------------------------------------------------
    // Layout
    // ------------------------------------------------------------------

    private val docsDir: File get() = File(root, "docs")
    private val templatesDir: File get() = File(root, "templates")
    private val tmpDir: File get() = File(root, "tmp")
    private val diagnosticsDir: File get() = File(root, "diagnostics")
    private val diagnosticsFile: File get() = File(diagnosticsDir, "redacted.jsonl")

    /** Creates the documented root layout without touching any object. */
    fun ensureLayout() {
        for (dir in listOf(root, docsDir, templatesDir, tmpDir, diagnosticsDir)) {
            if (!io.isDirectory(dir)) {
                try {
                    io.mkdirs(dir)
                } catch (failure: Throwable) {
                    throw mapWriteFailure(failure)
                }
            }
        }
    }

    private fun aggregateDir(aggregate: AggregateRef): File =
        File(if (aggregate.kind == AggregateKind.DOCUMENT) docsDir else templatesDir, aggregate.id)

    private fun fileFor(obj: StoreObject): File =
        File(File(aggregateDir(obj.aggregate), obj.relativeDir), obj.fileName)

    private fun tmpFile(txnId: String, suffix: String): File =
        File(tmpDir, txnId + suffix)

    private fun newTxnId(): String = idGenerator()

    /**
     * Serializes compare-and-commit per aggregate.
     *
     * The store is used by one Android app process; a JVM-wide lock keyed by
     * the store root and aggregate id also serializes two store instances in
     * one process. Without it, two saves could both read the same head and
     * both pass the expected-head check, and a read-back rollback could
     * overwrite a concurrent commit. Cross-process writers are not claimed.
     */
    private fun <T> withAggregateLock(ref: AggregateRef, block: () -> T): T {
        val lock = COMMIT_LOCKS.computeIfAbsent(lockKey(ref)) { ReentrantLock() }
        lock.lock()
        try {
            return block()
        } finally {
            lock.unlock()
        }
    }

    private fun lockKey(ref: AggregateRef): String =
        root.absolutePath + "|" + ref.kind.name + "|" + ref.id

    // ------------------------------------------------------------------
    // Public read/write API
    // ------------------------------------------------------------------

    /**
     * Imports a new document aggregate (§3.2).
     *
     * The aggregate KEK is created before the first ciphertext write. A
     * failure at any step leaves no visible document: the incomplete directory
     * and the alias are removed best-effort and the startup sweep is the
     * backstop. Only after source, revision, head, and meta were written and
     * read back is the document considered visible.
     */
    fun createDocument(
        documentId: String,
        metaJson: ByteArray,
        sourceId: String,
        sourceBytes: ByteArray,
        revisionId: String,
        revisionJson: ByteArray,
        revisionKind: RevisionKindWire = RevisionKindWire.EXPLICIT,
    ): CreateReceipt {
        val ref = AggregateRef(AggregateKind.DOCUMENT, documentId)
        requireAggregateId(ref)
        return withAggregateLock(ref) {
            createDocumentUnlocked(documentId, metaJson, sourceId, sourceBytes, revisionId, revisionJson, revisionKind)
        }
    }

    /** Locked implementation; callers hold the aggregate commit lock. */
    private fun createDocumentUnlocked(
        documentId: String,
        metaJson: ByteArray,
        sourceId: String,
        sourceBytes: ByteArray,
        revisionId: String,
        revisionJson: ByteArray,
        revisionKind: RevisionKindWire = RevisionKindWire.EXPLICIT,
    ): CreateReceipt {
        val ref = AggregateRef(AggregateKind.DOCUMENT, documentId)
        requireAggregateId(ref)
        requireObjectId(sourceId)
        requireObjectId(revisionId)
        requirePayload(metaJson, MAX_META_BYTES, "meta")
        requirePayload(revisionJson, MAX_REVISION_BYTES, "revision")
        requireSourceSize(sourceBytes.size.toLong())

        val aggregate = aggregateDir(ref)
        if (io.exists(fileFor(MetaObject(ref)))) {
            // A visible aggregate already owns this id: never overwrite it.
            throw ConcurrentSaveException()
        }
        if (io.exists(aggregate) && isIncomplete(ref)) {
            // A crash before meta became visible: remove the incomplete
            // directory and continue as a fresh import.
            io.deleteTree(aggregate)
        }

        // §3.2 key setup: alias exists with the aggregate directory before the
        // first ciphertext write. No directory is created before the key.
        keystore.createAggregateKey(ref)
        try {
            ensureLayout()
            for (sub in listOf("rev", "src", "sig")) io.mkdirs(File(aggregate, sub))

            val txn = newTxnId()
            commitObject(
                SourceObject(ref, sourceId),
                sourceBytes,
                txn,
                TMP_SUFFIX_PART,
            )
            commitObject(
                RevisionObject(ref, revisionId),
                revisionJson,
                txn,
                TMP_SUFFIX_PART,
                lastModifiedMillis = nextRevisionTimestampMillis(ref),
            )
            val head = CommittedHead(
                revisionId = revisionId,
                plaintextSha256 = sha256Hex(revisionJson),
                committedAt = nowIso(),
                parentRevisionId = null,
                kind = revisionKind,
            )
            commitHead(ref, head, txn)
            commitObject(MetaObject(ref), metaJson, txn, TMP_SUFFIX_PART)

            // Final read-back: only now may the caller treat it as imported.
            readContainer(MetaObject(ref), fileFor(MetaObject(ref)))
            require(readHeadStrict(ref) == head)
            val readRevision = verifyContainer(
                RevisionObject(ref, revisionId),
                fileFor(RevisionObject(ref, revisionId)),
            )
            if (readRevision.plaintextSha256 != head.plaintextSha256) {
                throw CorruptDataException()
            }
            return CreateReceipt(
                aggregateId = documentId,
                aggregateKind = AggregateKind.DOCUMENT,
                sourceId = sourceId,
                sourceSha256 = sha256Hex(sourceBytes),
                revisionId = revisionId,
                revisionSha256 = head.plaintextSha256,
                committedAt = head.committedAt,
                readBackVerified = true,
            )
        } catch (failure: Throwable) {
            // Creation never reported success: no visible aggregate may remain.
            runCatching { io.deleteTree(aggregate) }
            runCatching { keystore.deleteAggregateKey(ref) }
            throw failure
        }
    }

    /** Creates a template aggregate with its first immutable version (§3.3). */
    fun createTemplate(
        templateId: String,
        metaJson: ByteArray,
        sourceId: String,
        sourceBytes: ByteArray,
        versionId: String,
        versionJson: ByteArray,
    ): CreateReceipt {
        val ref = AggregateRef(AggregateKind.TEMPLATE, templateId)
        requireAggregateId(ref)
        return withAggregateLock(ref) {
            createTemplateUnlocked(templateId, metaJson, sourceId, sourceBytes, versionId, versionJson)
        }
    }

    /** Locked implementation; callers hold the aggregate commit lock. */
    private fun createTemplateUnlocked(
        templateId: String,
        metaJson: ByteArray,
        sourceId: String,
        sourceBytes: ByteArray,
        versionId: String,
        versionJson: ByteArray,
    ): CreateReceipt {
        val ref = AggregateRef(AggregateKind.TEMPLATE, templateId)
        requireAggregateId(ref)
        requireObjectId(sourceId)
        requireObjectId(versionId)
        requirePayload(metaJson, MAX_META_BYTES, "meta")
        requirePayload(versionJson, MAX_REVISION_BYTES, "version")
        requireSourceSize(sourceBytes.size.toLong())

        val aggregate = aggregateDir(ref)
        if (io.exists(fileFor(MetaObject(ref)))) throw ConcurrentSaveException()
        if (io.exists(aggregate) && isIncomplete(ref)) {
            io.deleteTree(aggregate)
        }

        keystore.createAggregateKey(ref)
        try {
            ensureLayout()
            for (sub in listOf("ver", "src")) io.mkdirs(File(aggregate, sub))

            val txn = newTxnId()
            commitObject(
                SourceObject(ref, sourceId),
                sourceBytes,
                txn,
                TMP_SUFFIX_PART,
            )
            commitObject(
                TemplateVersionObject(ref, versionId),
                versionJson,
                txn,
                TMP_SUFFIX_PART,
                lastModifiedMillis = nextRevisionTimestampMillis(ref),
            )
            val head = CommittedHead(
                revisionId = versionId,
                plaintextSha256 = sha256Hex(versionJson),
                committedAt = nowIso(),
                parentRevisionId = null,
                kind = RevisionKindWire.EXPLICIT,
            )
            commitHead(ref, head, txn)
            commitObject(MetaObject(ref), metaJson, txn, TMP_SUFFIX_PART)

            readContainer(MetaObject(ref), fileFor(MetaObject(ref)))
            require(readHeadStrict(ref) == head)
            val readVersion = verifyContainer(
                TemplateVersionObject(ref, versionId),
                fileFor(TemplateVersionObject(ref, versionId)),
            )
            if (readVersion.plaintextSha256 != head.plaintextSha256) {
                throw CorruptDataException()
            }
            return CreateReceipt(
                aggregateId = templateId,
                aggregateKind = AggregateKind.TEMPLATE,
                sourceId = sourceId,
                sourceSha256 = sha256Hex(sourceBytes),
                revisionId = versionId,
                revisionSha256 = head.plaintextSha256,
                committedAt = head.committedAt,
                readBackVerified = true,
            )
        } catch (failure: Throwable) {
            runCatching { io.deleteTree(aggregate) }
            runCatching { keystore.deleteAggregateKey(ref) }
            throw failure
        }
    }

    /**
     * Saves one document revision atomically (§3.1).
     *
     * [expectedHead] is the revision id the caller verified; null means the
     * caller expects no head yet. A persistent mismatch maps to `SAVE-006`
     * after one automatic retry, and the previous head is preserved.
     */
    fun saveRevision(
        documentId: String,
        revisionId: String,
        revisionJson: ByteArray,
        revisionKind: RevisionKindWire,
        expectedHead: String?,
    ): CommitReceipt {
        val ref = AggregateRef(AggregateKind.DOCUMENT, documentId)
        requireAggregateId(ref)
        return withAggregateLock(ref) {
            saveRevisionUnlocked(documentId, revisionId, revisionJson, revisionKind, expectedHead)
        }
    }

    /** Locked implementation; callers hold the aggregate commit lock. */
    private fun saveRevisionUnlocked(
        documentId: String,
        revisionId: String,
        revisionJson: ByteArray,
        revisionKind: RevisionKindWire,
        expectedHead: String?,
    ): CommitReceipt {
        val ref = AggregateRef(AggregateKind.DOCUMENT, documentId)
        requireAggregateId(ref)
        requireObjectId(revisionId)
        requirePayload(revisionJson, MAX_REVISION_BYTES, "revision")
        if (!io.exists(fileFor(MetaObject(ref)))) {
            throw CorruptDataException()
        }

        val current = verifyExpectedHead(ref, expectedHead)
        val txn = newTxnId()
        val revisionObject = RevisionObject(ref, revisionId)
        val revisionFile = fileFor(revisionObject)

        if (io.exists(revisionFile)) {
            // Idempotent retry of a commit that was promoted before a crash.
            val existing = verifyContainer(revisionObject, revisionFile)
            if (existing.plaintextSha256 != sha256Hex(revisionJson)) {
                throw ConcurrentSaveException()
            }
        } else {
            commitObject(
                revisionObject,
                revisionJson,
                txn,
                TMP_SUFFIX_PART,
                lastModifiedMillis = nextRevisionTimestampMillis(ref),
            )
        }

        val head = CommittedHead(
            revisionId = revisionId,
            plaintextSha256 = sha256Hex(revisionJson),
            committedAt = nowIso(),
            parentRevisionId = current?.revisionId,
            kind = revisionKind,
        )
        commitHead(ref, head, txn)

        // §3.1 step 7: read back head and referenced revision again.
        val readHead = readHeadStrict(ref)
        val readRevision = verifyContainer(revisionObject, revisionFile)
        if (readHead != head ||
            readRevision.plaintextSha256 != head.plaintextSha256
        ) {
            throw CorruptDataException()
        }
        return CommitReceipt(
            aggregateId = documentId,
            aggregateKind = AggregateKind.DOCUMENT,
            revisionId = revisionId,
            plaintextSha256 = head.plaintextSha256,
            parentRevisionId = head.parentRevisionId,
            committedAt = head.committedAt,
            revisionKind = revisionKind,
            revisionFileBytes = revisionFile.length(),
            headFileBytes = fileFor(HeadObject(ref)).length(),
            readBackVerified = true,
        )
    }

    /** Saves one immutable template version (§3.3). */
    fun saveTemplateVersion(
        templateId: String,
        versionId: String,
        versionJson: ByteArray,
        expectedHead: String?,
    ): CommitReceipt {
        val ref = AggregateRef(AggregateKind.TEMPLATE, templateId)
        requireAggregateId(ref)
        return withAggregateLock(ref) {
            saveTemplateVersionUnlocked(templateId, versionId, versionJson, expectedHead)
        }
    }

    /** Locked implementation; callers hold the aggregate commit lock. */
    private fun saveTemplateVersionUnlocked(
        templateId: String,
        versionId: String,
        versionJson: ByteArray,
        expectedHead: String?,
    ): CommitReceipt {
        val ref = AggregateRef(AggregateKind.TEMPLATE, templateId)
        requireAggregateId(ref)
        requireObjectId(versionId)
        requirePayload(versionJson, MAX_REVISION_BYTES, "version")
        if (!io.exists(fileFor(MetaObject(ref)))) {
            throw CorruptDataException()
        }

        val current = verifyExpectedHead(ref, expectedHead)
        val txn = newTxnId()
        val versionObject = TemplateVersionObject(ref, versionId)
        val versionFile = fileFor(versionObject)

        if (io.exists(versionFile)) {
            val existing = verifyContainer(versionObject, versionFile)
            if (existing.plaintextSha256 != sha256Hex(versionJson)) {
                throw ConcurrentSaveException()
            }
        } else {
            commitObject(
                versionObject,
                versionJson,
                txn,
                TMP_SUFFIX_PART,
                lastModifiedMillis = nextRevisionTimestampMillis(ref),
            )
        }

        val head = CommittedHead(
            revisionId = versionId,
            plaintextSha256 = sha256Hex(versionJson),
            committedAt = nowIso(),
            parentRevisionId = current?.revisionId,
            kind = RevisionKindWire.EXPLICIT,
        )
        commitHead(ref, head, txn)

        val readHead = readHeadStrict(ref)
        val readVersion = verifyContainer(versionObject, versionFile)
        if (readHead != head ||
            readVersion.plaintextSha256 != head.plaintextSha256
        ) {
            throw CorruptDataException()
        }
        return CommitReceipt(
            aggregateId = templateId,
            aggregateKind = AggregateKind.TEMPLATE,
            revisionId = versionId,
            plaintextSha256 = head.plaintextSha256,
            parentRevisionId = head.parentRevisionId,
            committedAt = head.committedAt,
            revisionKind = RevisionKindWire.EXPLICIT,
            revisionFileBytes = versionFile.length(),
            headFileBytes = fileFor(HeadObject(ref)).length(),
            readBackVerified = true,
        )
    }

    /** Loads a document only after meta, head, revision, and source verify. */
    fun loadDocument(documentId: String): LoadedAggregate {
        val ref = AggregateRef(AggregateKind.DOCUMENT, documentId)
        requireAggregateId(ref)
        return withAggregateLock(ref) {
            loadDocumentUnlocked(documentId)
        }
    }

    /** Locked implementation; callers hold the aggregate commit lock. */
    private fun loadDocumentUnlocked(documentId: String): LoadedAggregate {
        val ref = AggregateRef(AggregateKind.DOCUMENT, documentId)
        requireAggregateId(ref)
        val health = recoverAggregate(ref)
        if (!health.readable) {
            throw health.toException()
        }
        val head = health.head ?: throw CorruptDataException()
        val meta = readContainer(MetaObject(ref), fileFor(MetaObject(ref)))
        val revisionObject = RevisionObject(ref, head.revisionId)
        val revision = readContainer(revisionObject, fileFor(revisionObject))
        if (sha256Hex(revision) != head.plaintextSha256) throw CorruptDataException()
        val source = readSingleSource(ref)
        return LoadedAggregate(
            aggregateId = documentId,
            aggregateKind = AggregateKind.DOCUMENT,
            metaPlaintext = meta,
            head = head,
            revisionPlaintext = revision,
            sourceBytes = source,
            fellBackToOlderRevision = health.fellBackToOlderRevision,
        )
    }

    /** Loads a template version (`versionId` null means the verified head). */
    fun loadTemplate(templateId: String, versionId: String? = null): LoadedAggregate {
        val ref = AggregateRef(AggregateKind.TEMPLATE, templateId)
        requireAggregateId(ref)
        return withAggregateLock(ref) {
            loadTemplateUnlocked(templateId, versionId)
        }
    }

    /** Locked implementation; callers hold the aggregate commit lock. */
    private fun loadTemplateUnlocked(templateId: String, versionId: String? = null): LoadedAggregate {
        val ref = AggregateRef(AggregateKind.TEMPLATE, templateId)
        requireAggregateId(ref)
        if (versionId != null) requireObjectId(versionId)
        val health = recoverAggregate(ref)
        if (!health.readable) {
            throw health.toException()
        }
        val head = health.head ?: throw CorruptDataException()
        val requested = versionId ?: head.revisionId
        val versionObject = TemplateVersionObject(ref, requested)
        val version = readContainer(versionObject, fileFor(versionObject))
        if (versionId == null && sha256Hex(version) != head.plaintextSha256) {
            throw CorruptDataException()
        }
        val meta = readContainer(MetaObject(ref), fileFor(MetaObject(ref)))
        val source = readSingleSource(ref)
        return LoadedAggregate(
            aggregateId = templateId,
            aggregateKind = AggregateKind.TEMPLATE,
            metaPlaintext = meta,
            head = head.copy(revisionId = requested),
            revisionPlaintext = version,
            sourceBytes = source,
            fellBackToOlderRevision = health.fellBackToOlderRevision,
        )
    }

    /** Writes one signature PNG and verifies it before returning (§3.4). */
    fun writeSignature(documentId: String, assetId: String, pngBytes: ByteArray) {
        val ref = AggregateRef(AggregateKind.DOCUMENT, documentId)
        requireAggregateId(ref)
        return withAggregateLock(ref) {
            writeSignatureUnlocked(documentId, assetId, pngBytes)
        }
    }

    /** Locked implementation; callers hold the aggregate commit lock. */
    private fun writeSignatureUnlocked(documentId: String, assetId: String, pngBytes: ByteArray) {
        val ref = AggregateRef(AggregateKind.DOCUMENT, documentId)
        requireAggregateId(ref)
        requireObjectId(assetId)
        requirePayload(pngBytes, MAX_SIGNATURE_BYTES, "signature")
        if (!io.exists(fileFor(MetaObject(ref)))) throw CorruptDataException()
        ensureLayout()
        io.mkdirs(File(aggregateDir(ref), "sig"))
        commitObject(
            SignatureObject(ref, assetId),
            pngBytes,
            newTxnId(),
            TMP_SUFFIX_PART,
        )
    }

    /** Reads one signature PNG after full authentication. */
    fun readSignature(documentId: String, assetId: String): ByteArray {
        val ref = AggregateRef(AggregateKind.DOCUMENT, documentId)
        requireAggregateId(ref)
        return withAggregateLock(ref) {
            readSignatureUnlocked(documentId, assetId)
        }
    }

    /** Locked implementation; callers hold the aggregate commit lock. */
    private fun readSignatureUnlocked(documentId: String, assetId: String): ByteArray {
        val ref = AggregateRef(AggregateKind.DOCUMENT, documentId)
        requireAggregateId(ref)
        requireObjectId(assetId)
        return readObject(SignatureObject(ref, assetId))
    }

    /**
     * Deletes an aggregate (§3.6).
     *
     * Objects and directory are removed first, the KEK alias last. A failed
     * alias deletion is reported and left for the startup sweep; no other
     * aggregate or alias is read or deleted. The confirmation must name the
     * stored title, or the caller-supplied localized "not readable" title for
     * an unreadable aggregate.
     */
    fun delete(
        kind: AggregateKind,
        id: String,
        confirmation: DeleteConfirmation,
        notReadableTitle: String,
    ): DeletionReceipt {
        val ref = AggregateRef(kind, id)
        requireAggregateId(ref)
        return withAggregateLock(ref) {
            deleteUnlocked(kind, id, confirmation, notReadableTitle)
        }
    }

    /** Locked implementation; callers hold the aggregate commit lock. */
    private fun deleteUnlocked(
        kind: AggregateKind,
        id: String,
        confirmation: DeleteConfirmation,
        notReadableTitle: String,
    ): DeletionReceipt {
        val ref = AggregateRef(kind, id)
        requireAggregateId(ref)
        if (!confirmation.acknowledged) throw PlatformSecurityException()

        val aggregate = aggregateDir(ref)
        if (!io.isDirectory(aggregate)) throw CorruptDataException()

        val storedTitle = readTitleOrNull(MetaObject(ref))
        val expectedTitle = storedTitle ?: notReadableTitle
        if (confirmation.title != expectedTitle) throw PlatformSecurityException()

        var objectsDeleted = 0
        if (io.exists(aggregate)) {
            objectsDeleted = countObjectFiles(aggregate)
            try {
                faultInjector.onFault(StoreFaultPoint.DELETE_OBJECTS, id)
            } catch (failure: Throwable) {
                throw mapWriteFailure(failure)
            }
            try {
                if (!io.deleteTree(aggregate)) throw StorageWriteException()
            } catch (failure: Throwable) {
                throw mapWriteFailure(failure)
            }
        }

        var aliasDeleted = false
        try {
            faultInjector.onFault(StoreFaultPoint.DELETE_ALIAS, id)
            aliasDeleted = keystore.deleteAggregateKey(ref)
        } catch (failure: StorageException) {
            // The contract keeps the deletion successful: the ciphertext is
            // gone and the startup sweep removes the orphan alias.
            aliasDeleted = false
        } catch (failure: Exception) {
            aliasDeleted = false
        }

        return DeletionReceipt(
            aggregateId = id,
            aggregateKind = kind,
            objectsDeleted = objectsDeleted,
            directoryDeleted = !io.exists(aggregate),
            aliasDeleted = aliasDeleted,
            orphanAliasLeft = !aliasDeleted,
        )
    }

    /** Lists aggregates of one namespace without inventing ciphertext titles. */
    fun list(kind: AggregateKind): List<AggregateListing> {
        val listed = mutableListOf<AggregateListing>()
        for (id in listAggregateIds(kind)) {
            val ref = AggregateRef(kind, id)
            val aggregate = aggregateDir(ref)
            if (!io.isDirectory(aggregate)) continue
            if (!io.exists(fileFor(MetaObject(ref))) && isIncomplete(ref)) {
                // Not visible yet; the startup sweep removes it.
                continue
            }
            val (health, metaPlaintext) = withAggregateLock(ref) {
                val recovered = recoverAggregate(ref)
                val meta = if (recovered.readable) {
                    try {
                        readContainer(MetaObject(ref), fileFor(MetaObject(ref)))
                    } catch (failure: Exception) {
                        null
                    }
                } else {
                    null
                }
                recovered to meta
            }
            listed += AggregateListing(
                aggregateId = id,
                aggregateKind = kind,
                readable = health.readable,
                unreadableReasonCode = health.reasonCode,
                metaPlaintext = metaPlaintext,
                head = health.head,
                fellBackToOlderRevision = health.fellBackToOlderRevision,
            )
        }
        return listed.sortedBy { it.aggregateId }
    }

    /** Non-fatal store summary for `StoreStatus` (`SAVE-002` vs `SAVE-008`). */
    fun status(): StoreStatus {
        val known = knownAggregates()
        val keyStatus = keystore.storeKeyStatus(known)
        var objectCount = 0
        var totalBytes = 0L
        for (aggregate in known) {
            val dir = aggregateDir(aggregate)
            if (!io.isDirectory(dir)) continue
            for (file in io.walkFiles(dir)) {
                if (file.extension !in OBJECT_EXTENSIONS) continue
                objectCount++
                totalBytes += file.length()
            }
        }
        return StoreStatus(
            keyAvailable = keyStatus.keyAvailable,
            objectCount = objectCount,
            totalBytes = totalBytes,
            globalKeyFailure = keyStatus.globalFailure,
            reasonCode = keyStatus.reasonCode,
        )
    }

    // ------------------------------------------------------------------
    // Recovery and sweep (§4)
    // ------------------------------------------------------------------

    /** Per-aggregate recovery stamp; adopts a verified older revision. */
    fun recoveryStamp(kind: AggregateKind, id: String): RecoveryStampView {
        val ref = AggregateRef(kind, id)
        requireAggregateId(ref)
        return withAggregateLock(ref) {
            recoveryStampUnlocked(kind, id)
        }
    }

    /** Locked implementation; callers hold the aggregate commit lock. */
    private fun recoveryStampUnlocked(kind: AggregateKind, id: String): RecoveryStampView {
        val ref = AggregateRef(kind, id)
        requireAggregateId(ref)
        val health = recoverAggregate(ref)
        return RecoveryStampView(
            verifiedRevisionId = health.head?.revisionId,
            committedAt = health.head?.committedAt,
            headCorrupt = health.headCorrupt,
            fellBackToOlderRevision = health.fellBackToOlderRevision,
            readable = health.readable,
            unreadableReasonCode = health.reasonCode,
            ambiguousRevisionOrder = health.ambiguousRevisionOrder,
        )
    }

    /**
     * Startup recovery in the contract order:
     *  1. stale/unknown `tmp/` entries;
     *  2. incomplete aggregates, head fallback, unreadable marking;
     *  3. unreferenced signature assets older than 24 h (when a resolver exists);
     *  4. orphan KEK aliases without an aggregate directory;
     *  5. one redacted counts-only recovery event.
     *
     * Export-artifact cleanup lives with T031 because it is in `cacheDir`, not
     * this store.
     */
    fun startupRecovery(): RecoveryReport {
        ensureLayout()
        var tempRemoved = 0
        var incompleteRemoved = 0
        var unreadable = 0
        var fallbacks = 0
        var ambiguousRevisionOrder = 0
        var aliasSweepSkipped = false
        var aliasSweep = OrphanAliasSweep(0, 0, 0)

        // Step 1: tmp/ entries older than 24 h or with unknown names.
        for (entry in io.list(tmpDir)) {
            val known = TMP_NAME.matches(entry.name)
            val stale = clock() - entry.lastModified() > STALE_TEMP_MS
            if (!known || stale) {
                if (io.deleteTree(entry)) tempRemoved++
            }
        }

        // Step 2: each aggregate.
        for (kind in AggregateKind.entries) {
            for (id in listAggregateIds(kind)) {
                val ref = AggregateRef(kind, id)
                withAggregateLock(ref) {
                    if (!io.exists(fileFor(MetaObject(ref))) && isIncomplete(ref)) {
                        if (io.deleteTree(aggregateDir(ref))) incompleteRemoved++
                        return@withAggregateLock
                    }
                    val health = recoverAggregate(ref)
                    if (health.fellBackToOlderRevision) fallbacks++
                    if (health.ambiguousRevisionOrder) ambiguousRevisionOrder++
                    if (!health.readable) unreadable++
                }
            }
        }

        // Step 3: unreferenced signature assets older than 24 h.
        if (signatureReferenceResolver != null) {
            sweepUnreferencedSignatures(signatureReferenceResolver)
        }

        // Step 4: orphan aliases. A provider outage must not abort startup.
        try {
            aliasSweep = keystore.sweepOrphanAliases { ref ->
                io.isDirectory(aggregateDir(ref))
            }
        } catch (failure: KeystoreUnavailableException) {
            aliasSweepSkipped = true
        }

        // Step 5: redacted event, counts only.
        val event = linkedMapOf<String, Any?>(
            "type" to "startupRecovery",
            "tempRemoved" to tempRemoved,
            "incompleteRemoved" to incompleteRemoved,
            "unreadableAggregates" to unreadable,
            "fallbackAdoptions" to fallbacks,
            "ambiguousRevisionOrder" to ambiguousRevisionOrder,
            "orphanAliasesRemoved" to aliasSweep.removedAliases,
            "orphanAliasesRetained" to aliasSweep.retainedAliases,
            "orphanAliasesFailed" to aliasSweep.failedAliases,
            "aliasSweepSkipped" to aliasSweepSkipped,
        )
        writeRecoveryEvent(event)

        return RecoveryReport(
            tempEntriesRemoved = tempRemoved,
            incompleteAggregatesRemoved = incompleteRemoved,
            unreadableAggregates = unreadable,
            fallbackAdoptions = fallbacks,
            ambiguousRevisionOrder = ambiguousRevisionOrder,
            orphanAliasesRemoved = aliasSweep.removedAliases,
            orphanAliasesRetained = aliasSweep.retainedAliases,
            orphanAliasesFailed = aliasSweep.failedAliases,
            aliasSweepSkipped = aliasSweepSkipped,
        )
    }

    /**
     * §4 step 3 helper. Unreferenced signature assets are deleted only when
     * older than 24 h; referenced assets are never touched. Supplied by T031
     * or by tests with an explicit reference map.
     */
    fun sweepUnreferencedSignatures(
        isReferenced: (documentId: String, assetId: String) -> Boolean,
    ): Int {
        var removed = 0
        for (id in listAggregateIds(AggregateKind.DOCUMENT)) {
            val ref = AggregateRef(AggregateKind.DOCUMENT, id)
            removed += withAggregateLock(ref) {
                var local = 0
                val sigDir = File(aggregateDir(ref), "sig")
                if (io.isDirectory(sigDir)) {
                    for (file in io.list(sigDir)) {
                        val assetId = file.name.removeSuffix(".fxs")
                        if (!AggregateRef.isValidId(assetId)) continue
                        val stale = clock() - file.lastModified() > STALE_TEMP_MS
                        if (!stale) continue
                        if (isReferenced(id, assetId)) continue
                        if (io.delete(file)) local++
                    }
                }
                local
            }
        }
        return removed
    }

    /**
     * Deletes revision objects that the caller explicitly excluded from
     * retention, while never deleting the verified current head.
     *
     * `contracts/storage-format.md` §3.1 step 8 requires pruning, but the
     * persisted `RevisionContent` carries no revision kind, so the store
     * cannot compute the "last 3 autosave + newest explicit + recovery"
     * policy without inventing data. The save orchestration/history owner
     * computes the keep set and calls this primitive. A corrupt or missing
     * head, or a head revision that does not verify, aborts pruning without
     * deleting anything. Only `rev/<uuid>.fx1` files are considered.
     *
     * @return number of revision files deleted.
     */
    fun pruneRevisions(documentId: String, keepRevisionIds: Set<String>): Int {
        val ref = AggregateRef(AggregateKind.DOCUMENT, documentId)
        requireAggregateId(ref)
        keepRevisionIds.forEach(::requireObjectId)
        return withAggregateLock(ref) {
            val head = readHeadStrict(ref)
            val headObject = RevisionObject(ref, head.revisionId)
            val headVerification = verifyContainer(headObject, fileFor(headObject))
            if (headVerification.plaintextSha256 != head.plaintextSha256) {
                throw CorruptDataException()
            }
            val dir = File(aggregateDir(ref), "rev")
            if (!io.isDirectory(dir)) return@withAggregateLock 0
            var deleted = 0
            for (file in io.list(dir)) {
                if (!file.isFile || !file.name.endsWith(".fx1")) continue
                val revisionId = file.name.removeSuffix(".fx1")
                if (!AggregateRef.isValidId(revisionId)) continue
                if (revisionId == head.revisionId || revisionId in keepRevisionIds) {
                    continue
                }
                if (io.delete(file)) deleted++
            }
            if (deleted > 0) io.fsyncDirectory(dir)
            deleted
        }
    }

    // ------------------------------------------------------------------
    // Commit protocol internals
    // ------------------------------------------------------------------

    private fun commitHead(
        ref: AggregateRef,
        head: CommittedHead,
        txnId: String,
    ) {
        val headObject = HeadObject(ref)
        val headFile = fileFor(headObject)
        val previous = if (io.exists(headFile)) io.readAll(headFile) else null
        val staged = stageObject(headObject, encodeHead(head), txnId, TMP_SUFFIX_HEAD)
        try {
            promote(staged, headObject, txnId)
            faultInjector.onFault(StoreFaultPoint.HEAD_PROMOTED, txnId)
            val readBack = readHeadStrict(ref)
            if (readBack != head) throw CorruptDataException()
        } catch (failure: Throwable) {
            // Never report success with an unverified head. Restore the exact
            // previous ciphertext when one existed; recovery handles the rest.
            restoreHead(headFile, previous)
            if (failure is CorruptDataException ||
                failure is SchemaTooNewException ||
                failure is KeyUnavailableException ||
                failure is KeystoreUnavailableException ||
                failure is StorageFullException ||
                failure is StorageWriteException
            ) {
                throw failure
            }
            throw mapWriteFailure(failure)
        }
    }

    private fun commitObject(
        obj: StoreObject,
        plaintext: ByteArray,
        txnId: String,
        suffix: String,
        lastModifiedMillis: Long? = null,
    ): ObjectReceipt {
        val staged = stageObject(obj, plaintext, txnId, suffix)
        if (lastModifiedMillis != null) {
            try {
                if (!io.setLastModified(staged.file, lastModifiedMillis)) {
                    throw StorageWriteException()
                }
                // The parent-directory fsync below makes the rename durable,
                // but it does not necessarily persist the inode mtime that
                // orders this revision. Flush the changed file metadata before
                // the rename, then fsync the parent after it.
                faultInjector.onFault(StoreFaultPoint.ORDERING_FSYNC, txnId)
                io.fsyncFile(staged.file)
            } catch (failure: Throwable) {
                runCatching { io.deleteTree(staged.file) }
                throw mapWriteFailure(failure)
            }
        }
        promote(staged, obj, txnId)
        return readBackObject(obj, plaintext)
    }

    /**
     * Strictly increasing revision/version mtime.
     *
     * The FXC1 format stores no revision sequence, so recovery uses the file
     * mtime as the commit order. Enforcing `max(existing + 1, clock)` at
     * commit keeps that order deterministic even when the clock has only
     * millisecond precision; recovery never falls back to UUID order.
     */
    private fun nextRevisionTimestampMillis(ref: AggregateRef): Long {
        val dirName = if (ref.kind == AggregateKind.DOCUMENT) "rev" else "ver"
        val dir = File(aggregateDir(ref), dirName)
        val latest = if (io.isDirectory(dir)) {
            io.list(dir)
                .filter { it.isFile && it.name.endsWith(".fx1") }
                .maxOfOrNull { it.lastModified() }
        } else {
            null
        }
        val now = clock()
        return if (latest == null) now else maxOf(now, latest + 1)
    }

    private fun readBackObject(
        obj: StoreObject,
        plaintext: ByteArray,
    ): ObjectReceipt {
        val target = fileFor(obj)
        val verification = try {
            verifyContainer(obj, target)
        } catch (failure: Throwable) {
            throw mapReadFailure(failure)
        }
        val expectedSha = sha256Hex(plaintext)
        if (verification.plaintextSha256 != expectedSha ||
            verification.plaintextLength != plaintext.size.toLong()
        ) {
            throw CorruptDataException()
        }
        return ObjectReceipt(
            plaintextSha256 = expectedSha,
            fileIdHex = hex(expectedFileId(obj)),
            plaintextLength = plaintext.size.toLong(),
            fileLength = target.length(),
        )
    }

    private fun stageObject(
        obj: StoreObject,
        plaintext: ByteArray,
        txnId: String,
        suffix: String,
    ): StagedObject {
        ensureLayout()
        val staged = tmpFile(txnId, suffix)
        try {
            faultInjector.onFault(StoreFaultPoint.STAGE_CREATE, txnId)
            val header = writeContainer(
                obj,
                ByteArrayInputStream(plaintext),
                plaintext.size.toLong(),
                staged,
                txnId,
            )
            val verified = verifyContainer(obj, staged)
            if (verified.plaintextSha256 != sha256Hex(plaintext) ||
                verified.plaintextLength != plaintext.size.toLong()
            ) {
                throw CorruptDataException()
            }
            return StagedObject(obj, staged, header)
        } catch (failure: Throwable) {
            runCatching { io.deleteTree(staged) }
            if (failure is StorageException) throw failure
            throw mapWriteFailure(failure)
        }
    }

    private fun promote(staged: StagedObject, obj: StoreObject, txnId: String) {
        val target = fileFor(obj)
        val parent = target.parentFile ?: throw CorruptDataException()
        try {
            faultInjector.onFault(StoreFaultPoint.PROMOTE, txnId)
            if (!io.isDirectory(parent)) io.mkdirs(parent)
            io.atomicMove(staged.file, target)
            faultInjector.onFault(StoreFaultPoint.PROMOTE_FSYNC, txnId)
            io.fsyncDirectory(parent)
        } catch (failure: Throwable) {
            runCatching { io.deleteTree(staged.file) }
            throw mapWriteFailure(failure)
        }
    }

    private fun writeContainer(
        obj: StoreObject,
        input: InputStream,
        length: Long,
        file: File,
        txnId: String,
    ): FxcHeader {
        if (length < 0 || length > MAX_OBJECT_BYTES) throw InvalidDataException()
        val chunkSize = obj.objectKind.chunkSize
        val chunkCount = chunkCount(length, chunkSize)
        val dek = randomBytes(DEK_SIZE_BYTES)
        val noncePrefix = randomBytes(NONCE_PREFIX_SIZE)
        val wrapped = keystore.wrapDek(obj.aggregate, dek)
        val fileId = expectedFileId(obj)

        var channel: FileChannel? = null
        try {
            channel = io.openExclusive(file)
            // Header is patched after the digest is known; the placeholder is
            // never visible outside tmp/.
            writeFully(channel, ByteArray(HEADER_SIZE))
            val digest = MessageDigest.getInstance("SHA-256")
            var index = 0
            var total = 0L
            val buffer = ByteArray(chunkSize)
            input.use { stream ->
                while (total < length) {
                    val wanted = minOf(chunkSize.toLong(), length - total).toInt()
                    readFully(stream, buffer, wanted)
                    digest.update(buffer, 0, wanted)
                    val iv = chunkIv(noncePrefix, index)
                    val aad = chunkAad(
                        fileId = fileId,
                        objectKind = obj.objectKind,
                        chunkIndex = index,
                        chunkCount = chunkCount,
                        plaintextLength = length,
                    )
                    val cipher = Cipher.getInstance(TRANSFORM)
                    cipher.init(
                        Cipher.ENCRYPT_MODE,
                        SecretKeySpec(dek, "AES"),
                        GCMParameterSpec(TAG_BITS, iv),
                    )
                    cipher.updateAAD(aad)
                    val ciphertext = cipher.doFinal(buffer, 0, wanted)
                    faultInjector.onFault(StoreFaultPoint.STAGE_WRITE, txnId)
                    writeFully(channel, ciphertext)
                    total += wanted
                    index++
                }
                if (stream.read() != -1) throw InvalidDataException()
            }
            if (total != length || index != chunkCount) throw InvalidDataException()
            val header = FxcHeader(
                version = CONTAINER_VERSION,
                flags = FLAG_CHUNKED,
                keyScheme = KEY_SCHEME_AGGREGATE_KEK,
                objectKind = obj.objectKind,
                chunkSize = chunkSize,
                plaintextLength = length,
                chunkCount = chunkCount,
                noncePrefix = noncePrefix,
                wrapIv = wrapped.wrapIv,
                wrappedKey = wrapped.wrappedKey,
                plaintextSha256 = digest.digest(),
                fileId = fileId,
            )
            faultInjector.onFault(StoreFaultPoint.STAGE_PATCH, txnId)
            channel.position(0)
            writeFully(channel, header.encode())
            faultInjector.onFault(StoreFaultPoint.STAGE_FSYNC, txnId)
            channel.force(true)
            channel.close()
            channel = null
            return header
        } catch (failure: Throwable) {
            runCatching { channel?.close() }
            runCatching { io.deleteTree(file) }
            throw mapWriteFailure(failure)
        }
    }

    private data class ContainerVerification(
        val plaintextSha256: String,
        val plaintextLength: Long,
        val chunkCount: Int,
        val plaintext: ByteArray?,
    )

    /**
     * Materializes the plaintext because the load/read port signatures return
     * bytes to the caller. Commit verification, read-back, and recovery use
     * [verifyContainer] instead and keep only chunk-sized buffers.
     */
    private fun readContainer(obj: StoreObject, file: File): ByteArray =
        readContainerInternal(obj, file, keepPlaintext = true).plaintext
            ?: throw CorruptDataException()

    /**
     * Decrypts and authenticates every chunk without retaining the complete
     * plaintext. Commit read-back and recovery use this path so only one
     * ciphertext buffer, one plaintext chunk buffer, and one GCM tag are live
     * at a time, as required by `contracts/storage-format.md` §6.
     */
    private fun verifyContainer(
        obj: StoreObject,
        file: File,
        onChunk: ((index: Int, length: Int) -> Unit)? = null,
    ): ContainerVerification =
        readContainerInternal(obj, file, keepPlaintext = false, onChunk = onChunk)

    private fun readContainerInternal(
        obj: StoreObject,
        file: File,
        keepPlaintext: Boolean,
        onChunk: ((index: Int, length: Int) -> Unit)? = null,
    ): ContainerVerification {
        if (!io.exists(file)) throw CorruptDataException()
        var channel: FileChannel? = null
        try {
            channel = io.openRead(file)
            val size = channel.size()
            if (size < HEADER_SIZE) throw CorruptDataException()
            val headerBytes = readExactly(channel, HEADER_SIZE)
            val header = FxcHeader.decode(
                bytes = headerBytes,
                expectedKind = obj.objectKind,
                expectedFileId = expectedFileId(obj),
            )
            val expectedSize =
                HEADER_SIZE.toLong() +
                    header.plaintextLength +
                    header.chunkCount.toLong() * TAG_SIZE
            if (size != expectedSize) throw CorruptDataException()

            val dek = keystore.unwrapDek(
                obj.aggregate,
                WrappedDek(header.wrapIv, header.wrappedKey),
            )
            val digest = MessageDigest.getInstance("SHA-256")
            val plaintext = if (keepPlaintext) {
                ByteArray(header.plaintextLength.toInt())
            } else {
                null
            }
            // Reused per chunk; peak live memory is bounded by one ciphertext
            // chunk plus one plaintext chunk plus the GCM tag.
            val cipherBuffer = if (header.chunkCount > 0) {
                ByteArray(header.chunkSize + TAG_SIZE)
            } else {
                null
            }
            val chunkBuffer = if (header.chunkCount > 0) {
                ByteArray(header.chunkSize)
            } else {
                null
            }
            var offset = 0
            for (index in 0 until header.chunkCount) {
                val chunkLength = minOf(
                    header.chunkSize.toLong(),
                    header.plaintextLength - offset,
                ).toInt()
                if (chunkLength <= 0) throw CorruptDataException()
                readExactlyInto(channel, cipherBuffer!!, chunkLength + TAG_SIZE)
                val iv = chunkIv(header.noncePrefix, index)
                val aad = chunkAad(
                    fileId = header.fileId,
                    objectKind = header.objectKind,
                    chunkIndex = index,
                    chunkCount = header.chunkCount,
                    plaintextLength = header.plaintextLength,
                )
                val cipher = Cipher.getInstance(TRANSFORM)
                cipher.init(
                    Cipher.DECRYPT_MODE,
                    SecretKeySpec(dek, "AES"),
                    GCMParameterSpec(TAG_BITS, iv),
                )
                cipher.updateAAD(aad)
                val written = cipher.doFinal(
                    cipherBuffer,
                    0,
                    chunkLength + TAG_SIZE,
                    chunkBuffer!!,
                    0,
                )
                if (written != chunkLength) throw CorruptDataException()
                digest.update(chunkBuffer, 0, written)
                if (plaintext != null && written > 0) {
                    System.arraycopy(chunkBuffer, 0, plaintext, offset, written)
                }
                onChunk?.invoke(index, written)
                offset += written
            }
            if (offset.toLong() != header.plaintextLength) {
                throw CorruptDataException()
            }
            if (!digest.digest().contentEquals(header.plaintextSha256)) {
                throw CorruptDataException()
            }
            channel.close()
            channel = null
            return ContainerVerification(
                plaintextSha256 = hex(header.plaintextSha256),
                plaintextLength = header.plaintextLength,
                chunkCount = header.chunkCount,
                plaintext = plaintext,
            )
        } catch (failure: StorageException) {
            runCatching { channel?.close() }
            throw failure
        } catch (failure: Throwable) {
            runCatching { channel?.close() }
            throw mapReadFailure(failure)
        }
    }

    private fun readExactlyInto(channel: FileChannel, into: ByteArray, length: Int) {
        val buffer = ByteBuffer.wrap(into, 0, length)
        while (buffer.hasRemaining()) {
            if (channel.read(buffer) <= 0) throw CorruptDataException()
        }
    }

    private fun readObject(obj: StoreObject): ByteArray =
        readContainer(obj, fileFor(obj))

    // ------------------------------------------------------------------
    // Test seams (same package; not part of the adapter surface)
    // ------------------------------------------------------------------

    internal fun commitObjectForTest(obj: StoreObject, plaintext: ByteArray): ObjectReceipt =
        commitObject(obj, plaintext, newTxnId(), TMP_SUFFIX_PART)

    internal fun readObjectForTest(obj: StoreObject): ByteArray = readObject(obj)

    internal fun verifyObjectForTest(
        obj: StoreObject,
        onChunk: ((index: Int, length: Int) -> Unit)? = null,
    ): String = verifyContainer(obj, fileFor(obj), onChunk).plaintextSha256

    internal fun readHeadForTest(aggregate: AggregateRef): CommittedHead =
        readHeadStrict(aggregate)

    // ------------------------------------------------------------------
    // Head parsing
    // ------------------------------------------------------------------

    private fun readHeadStrict(ref: AggregateRef): CommittedHead {
        val bytes = try {
            readContainer(HeadObject(ref), fileFor(HeadObject(ref)))
        } catch (failure: StorageException) {
            throw failure
        } catch (failure: Error) {
            throw failure
        } catch (failure: Throwable) {
            throw CorruptDataException()
        }
        return decodeHead(bytes)
    }

    private fun readHeadOrNull(ref: AggregateRef): CommittedHead? {
        if (!io.exists(fileFor(HeadObject(ref)))) return null
        return try {
            readHeadStrict(ref)
        } catch (failure: KeyUnavailableException) {
            throw failure
        } catch (failure: KeystoreUnavailableException) {
            throw failure
        } catch (failure: CorruptDataException) {
            null
        }
    }

    private fun encodeHead(head: CommittedHead): ByteArray = CanonicalJson.encode(
        linkedMapOf(
            "revisionId" to head.revisionId,
            "plaintextSha256" to head.plaintextSha256,
            "committedAt" to head.committedAt,
            "parentRevisionId" to head.parentRevisionId,
            "kind" to head.kind.wireName,
        ),
    )

    private fun decodeHead(bytes: ByteArray): CommittedHead {
        val parsed = try {
            CanonicalJson.parse(bytes)
        } catch (failure: Exception) {
            throw CorruptDataException()
        }
        val map = parsed as? Map<*, *> ?: throw CorruptDataException()
        val revisionId = map["revisionId"] as? String
            ?: throw CorruptDataException()
        val sha = map["plaintextSha256"] as? String
            ?: throw CorruptDataException()
        val committedAt = map["committedAt"] as? String
            ?: throw CorruptDataException()
        val kindText = map["kind"] as? String ?: throw CorruptDataException()
        if (!map.containsKey("parentRevisionId")) throw CorruptDataException()
        val parentValue = map["parentRevisionId"]
        val parent = when (parentValue) {
            null -> null
            is String -> parentValue
            else -> throw CorruptDataException()
        }
        if (!AggregateRef.isValidId(revisionId)) throw CorruptDataException()
        if (parent != null && !AggregateRef.isValidId(parent)) {
            throw CorruptDataException()
        }
        if (!SHA256_HEX.matches(sha)) throw CorruptDataException()
        val kind = RevisionKindWire.fromWire(kindText)
            ?: throw CorruptDataException()
        return CommittedHead(
            revisionId = revisionId,
            plaintextSha256 = sha,
            committedAt = committedAt,
            parentRevisionId = parent,
            kind = kind,
        )
    }

    private fun restoreHead(headFile: File, previous: ByteArray?) {
        try {
            if (previous == null) {
                io.delete(headFile)
            } else {
                val txn = newTxnId()
                val restore = tmpFile(txn, TMP_SUFFIX_RESTORE)
                val channel = io.openExclusive(restore)
                try {
                    writeFully(channel, previous)
                    channel.force(true)
                } finally {
                    channel.close()
                }
                io.atomicMove(restore, headFile)
                io.fsyncDirectory(headFile.parentFile!!)
            }
        } catch (failure: Exception) {
            // Recovery on the next start handles a head that could not be
            // restored; never mask the original failure.
        }
    }

    // ------------------------------------------------------------------
    // Recovery internals
    // ------------------------------------------------------------------

    private fun recoverAggregate(ref: AggregateRef): AggregateHealth {
        val aggregate = aggregateDir(ref)
        if (!io.isDirectory(aggregate)) throw CorruptDataException()

        val metaObject = MetaObject(ref)
        if (!io.exists(fileFor(metaObject))) {
            if (isIncomplete(ref)) {
                io.deleteTree(aggregate)
                return AggregateHealth(
                    readable = false,
                    reasonCode = null,
                    head = null,
                    headCorrupt = true,
                    fellBackToOlderRevision = false,
                    incomplete = true,
                )
            }
            return AggregateHealth(
                readable = false,
                reasonCode = SAVE_003,
                head = null,
                headCorrupt = true,
                fellBackToOlderRevision = false,
            )
        }

        try {
            readContainer(metaObject, fileFor(metaObject))
        } catch (failure: KeyUnavailableException) {
            return unreadable(SAVE_002)
        } catch (failure: KeystoreUnavailableException) {
            return unreadable(SAVE_008)
        } catch (failure: CorruptDataException) {
            return unreadable(SAVE_003)
        } catch (failure: SchemaTooNewException) {
            return unreadable(SAVE_005)
        } catch (failure: StorageException) {
            return unreadable(SAVE_003)
        }

        val head = try {
            readHeadOrNull(ref)
        } catch (failure: KeyUnavailableException) {
            return unreadable(SAVE_002)
        } catch (failure: KeystoreUnavailableException) {
            return unreadable(SAVE_008)
        } catch (failure: SchemaTooNewException) {
            return unreadable(SAVE_005)
        }

        if (head != null) {
            val revisionSha = revisionSha(ref, head.revisionId)
            if (revisionSha != null && revisionSha == head.plaintextSha256) {
                return AggregateHealth(
                    readable = true,
                    reasonCode = null,
                    head = head,
                    headCorrupt = false,
                    fellBackToOlderRevision = false,
                )
            }
        }

        // §4 step 2: head missing/corrupt or pointing to a missing/corrupt
        // revision -> adopt the newest revision whose hash verifies.
        val search = findNewestVerifiableRevision(ref)
        if (search.ambiguous) {
            return AggregateHealth(
                readable = false,
                reasonCode = SAVE_003,
                head = null,
                headCorrupt = true,
                fellBackToOlderRevision = false,
                ambiguousRevisionOrder = true,
            )
        }
        val candidate = search.candidate
            ?: return AggregateHealth(
                readable = false,
                reasonCode = SAVE_003,
                head = null,
                headCorrupt = true,
                fellBackToOlderRevision = false,
            )
        val recovered = CommittedHead(
            revisionId = candidate.revisionId,
            plaintextSha256 = candidate.plaintextSha256,
            committedAt = nowIso(),
            parentRevisionId = null,
            kind = RevisionKindWire.RECOVERY,
        )
        return try {
            commitHead(ref, recovered, newTxnId())
            AggregateHealth(
                readable = true,
                reasonCode = null,
                head = recovered,
                headCorrupt = true,
                fellBackToOlderRevision = true,
            )
        } catch (failure: StorageException) {
            // The previous head/ciphertext is untouched; report unreadable.
            AggregateHealth(
                readable = false,
                reasonCode = failure.code,
                head = null,
                headCorrupt = true,
                fellBackToOlderRevision = false,
            )
        }
    }

    private fun unreadable(code: String): AggregateHealth = AggregateHealth(
        readable = false,
        reasonCode = code,
        head = null,
        headCorrupt = true,
        fellBackToOlderRevision = false,
    )

    private fun revisionSha(ref: AggregateRef, revisionId: String): String? {
        val objectForRevision = revisionObject(ref, revisionId)
        return try {
            verifyContainer(objectForRevision, fileFor(objectForRevision))
                .plaintextSha256
        } catch (failure: KeyUnavailableException) {
            throw failure
        } catch (failure: KeystoreUnavailableException) {
            throw failure
        } catch (failure: Error) {
            throw failure
        } catch (failure: Throwable) {
            null
        }
    }

    private fun revisionObject(ref: AggregateRef, revisionId: String): StoreObject =
        if (ref.kind == AggregateKind.DOCUMENT) {
            RevisionObject(ref, revisionId)
        } else {
            TemplateVersionObject(ref, revisionId)
        }

    private fun findNewestVerifiableRevision(ref: AggregateRef): RevisionSearch {
        val dirName = if (ref.kind == AggregateKind.DOCUMENT) "rev" else "ver"
        val dir = File(aggregateDir(ref), dirName)
        if (!io.isDirectory(dir)) return RevisionSearch(null, ambiguous = false)
        val candidates = io.list(dir)
            .filter { it.isFile && it.name.endsWith(".fx1") }
            .sortedByDescending { io.lastModifiedNanos(it) }
        var index = 0
        while (index < candidates.size) {
            val timestamp = io.lastModifiedNanos(candidates[index])
            var end = index + 1
            while (end < candidates.size &&
                io.lastModifiedNanos(candidates[end]) == timestamp
            ) {
                end++
            }
            val group = candidates.subList(index, end)
            if (group.size > 1) {
                // Equal timestamps with no persisted revision sequence: the
                // actual commit order is unknowable. Do not fall back to the
                // random UUID; fail closed and keep every revision.
                return RevisionSearch(null, ambiguous = true)
            }
            val file = group.single()
            val revisionId = file.name.removeSuffix(".fx1")
            index = end
            if (!AggregateRef.isValidId(revisionId)) continue
            val objectForRevision = revisionObject(ref, revisionId)
            val verification = try {
                verifyContainer(objectForRevision, file)
            } catch (failure: KeyUnavailableException) {
                throw failure
            } catch (failure: KeystoreUnavailableException) {
                throw failure
            } catch (failure: Error) {
                throw failure
            } catch (failure: Throwable) {
                continue
            }
            return RevisionSearch(
                RevisionCandidate(revisionId, verification.plaintextSha256),
                ambiguous = false,
            )
        }
        return RevisionSearch(null, ambiguous = false)
    }

    private fun isIncomplete(ref: AggregateRef): Boolean {
        val aggregate = aggregateDir(ref)
        if (!io.isDirectory(aggregate)) return false
        val entries = io.list(aggregate)
        if (entries.isEmpty()) return true
        val names = entries.map { it.name }.toSet()
        if (names.any { it !in ALLOWED_AGGREGATE_ENTRIES }) return false
        if (names.contains("meta.fx1")) return false
        if (names.contains("head.fx1")) return false
        if (names.contains("sig")) return false
        // Only immutable object directories remain: an import/template-create
        // that never wrote meta, as described by §4 step 2.
        return names.all { it in setOf("src", "rev", "ver") }
    }

    private fun readSingleSource(ref: AggregateRef): ByteArray {
        val srcDir = File(aggregateDir(ref), "src")
        if (!io.isDirectory(srcDir)) throw CorruptDataException()
        val sources = io.list(srcDir).filter { it.isFile && it.name.endsWith(".fxc") }
        if (sources.size != 1) throw CorruptDataException()
        val sourceId = sources.single().name.removeSuffix(".fxc")
        if (!AggregateRef.isValidId(sourceId)) throw CorruptDataException()
        return readObject(SourceObject(ref, sourceId))
    }

    private fun readTitleOrNull(meta: MetaObject): String? {
        val bytes = try {
            readContainer(meta, fileFor(meta))
        } catch (failure: Exception) {
            return null
        }
        val map = try {
            CanonicalJson.parse(bytes) as? Map<*, *>
        } catch (failure: Exception) {
            null
        } ?: return null
        return map["title"] as? String
    }

    // ------------------------------------------------------------------
    // Head/expected-head concurrency
    // ------------------------------------------------------------------

    private fun verifyExpectedHead(
        ref: AggregateRef,
        expectedHead: String?,
    ): CommittedHead? {
        if (expectedHead != null && !AggregateRef.isValidId(expectedHead)) {
            throw ConcurrentSaveException()
        }
        repeat(2) { attempt ->
            val current = readHeadOrNull(ref)
            if (current?.revisionId == expectedHead) return current
            if (attempt == 0) {
                // §3.1: retry the comparison once before surfacing a conflict.
                try {
                    Thread.sleep(CONFLICT_RETRY_MS)
                } catch (failure: InterruptedException) {
                    Thread.currentThread().interrupt()
                }
            }
        }
        throw ConcurrentSaveException()
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private fun requireAggregateId(ref: AggregateRef) {
        if (!AggregateRef.isValidId(ref.id)) throw PlatformSecurityException()
    }

    private fun requireObjectId(id: String) {
        if (!AggregateRef.isValidId(id)) throw PlatformSecurityException()
    }

    private fun requirePayload(bytes: ByteArray, max: Long, label: String) {
        if (bytes.isEmpty() || bytes.size.toLong() > max) {
            throw InvalidDataException()
        }
    }

    private fun requireSourceSize(size: Long) {
        if (size <= 0 || size > MAX_SOURCE_BYTES) throw InvalidDataException()
    }

    private fun nowIso(): String = ISO_MILLIS.format(
        Instant.ofEpochMilli(clock()).atOffset(ZoneOffset.UTC),
    )

    private fun randomBytes(size: Int): ByteArray =
        ByteArray(size).also { random.nextBytes(it) }

    private fun chunkIv(noncePrefix: ByteArray, index: Int): ByteArray {
        val iv = ByteArray(IV_SIZE)
        System.arraycopy(noncePrefix, 0, iv, 0, NONCE_PREFIX_SIZE)
        iv[NONCE_PREFIX_SIZE] = (index ushr 24).toByte()
        iv[NONCE_PREFIX_SIZE + 1] = (index ushr 16).toByte()
        iv[NONCE_PREFIX_SIZE + 2] = (index ushr 8).toByte()
        iv[NONCE_PREFIX_SIZE + 3] = index.toByte()
        return iv
    }

    private fun chunkAad(
        fileId: ByteArray,
        objectKind: ObjectKind,
        chunkIndex: Int,
        chunkCount: Int,
        plaintextLength: Long,
    ): ByteArray = (
        "FXC1|" + hex(fileId) + "|" + objectKind.wire + "|" +
            chunkIndex + "|" + chunkCount + "|" + plaintextLength
        ).toByteArray(StandardCharsets.UTF_8)

    private fun expectedFileId(obj: StoreObject): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(
            (
                obj.objectKind.wire.toString() + ":" + obj.fileIdToken
                ).toByteArray(StandardCharsets.UTF_8),
        )
        return digest.digest().copyOf(FILE_ID_SIZE)
    }

    private fun chunkCount(length: Long, chunkSize: Int): Int {
        if (length == 0L) return 0
        return ((length + chunkSize - 1) / chunkSize).toInt()
    }

    private fun writeFully(channel: FileChannel, bytes: ByteArray) {
        val buffer = ByteBuffer.wrap(bytes)
        while (buffer.hasRemaining()) channel.write(buffer)
    }

    private fun writeFully(channel: FileChannel, bytes: ByteArray, length: Int) {
        val buffer = ByteBuffer.wrap(bytes, 0, length)
        while (buffer.hasRemaining()) channel.write(buffer)
    }

    private fun readExactly(channel: FileChannel, length: Int): ByteArray {
        val out = ByteArray(length)
        val buffer = ByteBuffer.wrap(out)
        var read = 0
        while (read < length) {
            val count = channel.read(buffer)
            if (count <= 0) throw CorruptDataException()
            read += count
        }
        return out
    }

    private fun readFully(stream: InputStream, buffer: ByteArray, wanted: Int) {
        var read = 0
        while (read < wanted) {
            val count = stream.read(buffer, read, wanted - read)
            if (count < 0) throw InvalidDataException()
            read += count
        }
    }

    private fun mapWriteFailure(failure: Throwable): StorageException {
        if (failure is StorageException) return failure
        // Never turn a VM error (for example OutOfMemoryError) into a
        // recoverable storage diagnosis.
        if (failure is Error) throw failure
        return if (isQuota(failure)) StorageFullException() else StorageWriteException()
    }

    private fun mapReadFailure(failure: Throwable): StorageException {
        if (failure is StorageException) return failure
        if (failure is Error) throw failure
        return if (isQuota(failure)) StorageFullException() else CorruptDataException()
    }

    private fun isQuota(failure: Throwable): Boolean {
        val message = (failure.message ?: "").lowercase()
        return message.contains("enospc") ||
            message.contains("edquot") ||
            message.contains("no space")
    }

    private fun listAggregateIds(kind: AggregateKind): List<String> {
        val namespace = if (kind == AggregateKind.DOCUMENT) docsDir else templatesDir
        if (!io.isDirectory(namespace)) return emptyList()
        return io.list(namespace)
            .filter { it.isDirectory && AggregateRef.isValidId(it.name) }
            .map { it.name }
            .sorted()
    }

    private fun knownAggregates(): List<AggregateRef> =
        AggregateKind.entries.flatMap { kind ->
            listAggregateIds(kind).map { AggregateRef(kind, it) }
        }

    private fun countObjectFiles(dir: File): Int =
        io.walkFiles(dir).count { it.extension in OBJECT_EXTENSIONS }

    private fun writeRecoveryEvent(event: Map<String, Any?>) {
        try {
            ensureLayout()
            if (io.exists(diagnosticsFile) && io.size(diagnosticsFile) > DIAGNOSTICS_CAP) {
                io.delete(diagnosticsFile)
            }
            io.appendLine(diagnosticsFile, CanonicalJson.encode(event))
        } catch (failure: Exception) {
            // Diagnostics are best-effort and must never fail startup.
        }
    }

    private fun sha256Hex(bytes: ByteArray): String =
        hex(MessageDigest.getInstance("SHA-256").digest(bytes))

    private fun hex(bytes: ByteArray): String {
        val out = StringBuilder(bytes.size * 2)
        for (byte in bytes) {
            val value = byte.toInt() and 0xFF
            out.append(HEX[value ushr 4])
            out.append(HEX[value and 0x0F])
        }
        return out.toString()
    }

    companion object {
        const val HEADER_SIZE: Int = 160
        const val CONTAINER_VERSION: Int = 1
        const val KEY_SCHEME_AGGREGATE_KEK: Int = 1
        const val FLAG_CHUNKED: Int = 1
        const val META_CHUNK_SIZE: Int = 65_536
        const val LARGE_CHUNK_SIZE: Int = 1_048_576
        const val NONCE_PREFIX_SIZE: Int = 8
        const val IV_SIZE: Int = 12
        const val TAG_SIZE: Int = 16
        const val TAG_BITS: Int = 128
        const val DEK_SIZE_BYTES: Int = 32
        const val HASH_SIZE: Int = 32
        const val FILE_ID_SIZE: Int = 20
        const val WRAP_IV_SIZE: Int = 12
        const val WRAPPED_DEK_SIZE: Int = 48
        const val TRANSFORM: String = "AES/GCM/NoPadding"

        const val MAX_SOURCE_BYTES: Long = 83_886_080L
        const val MAX_SIGNATURE_BYTES: Long = 2L * 1024 * 1024
        const val MAX_META_BYTES: Long = 8L * 1024 * 1024
        const val MAX_REVISION_BYTES: Long = 32L * 1024 * 1024
        const val MAX_OBJECT_BYTES: Long = 96L * 1024 * 1024

        const val STALE_TEMP_MS: Long = 24L * 60 * 60 * 1000
        const val DIAGNOSTICS_CAP: Long = 64L * 1024
        const val CONFLICT_RETRY_MS: Long = 1L

        const val SAVE_002: String = "SAVE-002"
        const val SAVE_003: String = "SAVE-003"
        const val SAVE_005: String = "SAVE-005"
        const val SAVE_008: String = "SAVE-008"

        const val TMP_SUFFIX_PART: String = ".part"
        const val TMP_SUFFIX_HEAD: String = ".head"
        const val TMP_SUFFIX_RESTORE: String = ".restore"

        private val ISO_MILLIS: DateTimeFormatter =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")

        private val SHA256_HEX = Regex("^[0-9a-f]{64}$")
        private val HEX = "0123456789abcdef".toCharArray()
        private val MAGIC = byteArrayOf(
            'F'.code.toByte(),
            'X'.code.toByte(),
            'C'.code.toByte(),
            '1'.code.toByte(),
        )
        private val TMP_NAME = Regex(
            "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-" +
                "[89ab][0-9a-f]{3}-[0-9a-f]{12}" +
                "\\.(part|head|meta|src|sig|ver|restore)$",
        )
        private val ALLOWED_AGGREGATE_ENTRIES = setOf(
            "meta.fx1",
            "head.fx1",
            "rev",
            "src",
            "sig",
            "ver",
        )
        private val OBJECT_EXTENSIONS = setOf("fx1", "fxc", "fxs")

        /** JVM-wide per-aggregate commit locks (store root + aggregate id). */
        private val COMMIT_LOCKS = ConcurrentHashMap<String, ReentrantLock>()
    }
}

// --------------------------------------------------------------------------
// Public value types
// --------------------------------------------------------------------------

/** FXC1 object kinds and their header wire values (`contracts/storage-format.md` §2.1). */
enum class ObjectKind(val wire: Int, val chunkSize: Int) {
    META(1, EncryptedStore.META_CHUNK_SIZE),
    REVISION(2, EncryptedStore.LARGE_CHUNK_SIZE),
    SOURCE(3, EncryptedStore.LARGE_CHUNK_SIZE),
    SIGNATURE(4, EncryptedStore.LARGE_CHUNK_SIZE),
    TEMPLATE_VERSION(5, EncryptedStore.LARGE_CHUNK_SIZE);

    companion object {
        fun fromWire(value: Int): ObjectKind? = entries.firstOrNull { it.wire == value }
    }
}

/** Persisted revision provenance (`data-model.md` §3.12). */
enum class RevisionKindWire(val wireName: String) {
    AUTOSAVE("autosave"),
    EXPLICIT("explicit"),
    RECOVERY("recovery");

    companion object {
        fun fromWire(value: String): RevisionKindWire? =
            entries.firstOrNull { it.wireName == value }
    }
}

/** Parsed `head.fx1` envelope (`contracts/storage-format.md` §3.1 step 5). */
data class CommittedHead(
    val revisionId: String,
    val plaintextSha256: String,
    val committedAt: String,
    val parentRevisionId: String?,
    val kind: RevisionKindWire,
)

/** Staged-object receipt; no path or key bytes. */
data class ObjectReceipt(
    val plaintextSha256: String,
    val fileIdHex: String,
    val plaintextLength: Long,
    val fileLength: Long,
)

/** Atomic revision/version commit receipt; `readBackVerified` is always true. */
data class CommitReceipt(
    val aggregateId: String,
    val aggregateKind: AggregateKind,
    val revisionId: String,
    val plaintextSha256: String,
    val parentRevisionId: String?,
    val committedAt: String,
    val revisionKind: RevisionKindWire,
    val revisionFileBytes: Long,
    val headFileBytes: Long,
    val readBackVerified: Boolean,
)

/** New aggregate receipt after source, revision, head, and meta read-back. */
data class CreateReceipt(
    val aggregateId: String,
    val aggregateKind: AggregateKind,
    val sourceId: String,
    val sourceSha256: String,
    val revisionId: String,
    val revisionSha256: String,
    val committedAt: String,
    val readBackVerified: Boolean,
)

/** Fully verified aggregate load; caller owns [sourceBytes]. */
data class LoadedAggregate(
    val aggregateId: String,
    val aggregateKind: AggregateKind,
    val metaPlaintext: ByteArray,
    val head: CommittedHead,
    val revisionPlaintext: ByteArray,
    val sourceBytes: ByteArray,
    val fellBackToOlderRevision: Boolean,
)

/** Explicit destructive-delete confirmation (`contracts/ports.md` §2.4). */
data class DeleteConfirmation(
    val acknowledged: Boolean,
    val title: String,
)

/** Deletion receipt; `orphanAliasLeft` is retried by the startup sweep. */
data class DeletionReceipt(
    val aggregateId: String,
    val aggregateKind: AggregateKind,
    val objectsDeleted: Int,
    val directoryDeleted: Boolean,
    val aliasDeleted: Boolean,
    val orphanAliasLeft: Boolean,
)

/** List entry produced without inventing a ciphertext-derived title. */
data class AggregateListing(
    val aggregateId: String,
    val aggregateKind: AggregateKind,
    val readable: Boolean,
    val unreadableReasonCode: String?,
    val metaPlaintext: ByteArray?,
    val head: CommittedHead?,
    val fellBackToOlderRevision: Boolean,
)

/** Non-fatal store summary (`SAVE-002` vs `SAVE-008` scope). */
data class StoreStatus(
    val keyAvailable: Boolean,
    val objectCount: Int,
    val totalBytes: Long,
    val globalKeyFailure: Boolean,
    val reasonCode: String?,
)

/** Recovery stamp exposed to the port (`contracts/ports.md` §2.4). */
data class RecoveryStampView(
    val verifiedRevisionId: String?,
    val committedAt: String?,
    val headCorrupt: Boolean,
    val fellBackToOlderRevision: Boolean,
    val readable: Boolean,
    val unreadableReasonCode: String?,
    val ambiguousRevisionOrder: Boolean = false,
)

/** Counts-only startup recovery result; no ids, titles, or content. */
data class RecoveryReport(
    val tempEntriesRemoved: Int,
    val incompleteAggregatesRemoved: Int,
    val unreadableAggregates: Int,
    val fallbackAdoptions: Int,
    val orphanAliasesRemoved: Int,
    val orphanAliasesRetained: Int,
    val orphanAliasesFailed: Int,
    val aliasSweepSkipped: Boolean,
    val ambiguousRevisionOrder: Int = 0,
)

// --------------------------------------------------------------------------
// Fault injection (native equivalent of the T036 testkit taxonomy)
// --------------------------------------------------------------------------

/** Commit points at which a test may inject an I/O failure. */
enum class StoreFaultPoint {
    STAGE_CREATE,
    STAGE_WRITE,
    STAGE_PATCH,
    STAGE_FSYNC,
    ORDERING_FSYNC,
    PROMOTE,
    PROMOTE_FSYNC,
    HEAD_PROMOTED,
    DELETE_OBJECTS,
    DELETE_ALIAS,
}

/** Native fault seam for stage/fsync/commit interruption tests. */
fun interface StoreFaultInjector {

    /**
     * Called before the named operation. Throwing simulates an interruption;
     * [StorageException] values pass through, `IOException("ENOSPC")` maps to
     * `SAVE-001`, and other I/O failures map to `SAVE-003`.
     */
    fun onFault(point: StoreFaultPoint, transactionId: String)

    companion object {
        val NONE: StoreFaultInjector = StoreFaultInjector { _, _ -> }
    }
}

// --------------------------------------------------------------------------
// Filesystem seam
// --------------------------------------------------------------------------

/** Narrow filesystem seam so atomic commits can be fault-injected on the JVM. */
interface StoreIo {
    fun openExclusive(file: File): FileChannel
    fun openRead(file: File): FileChannel
    fun atomicMove(from: File, to: File)
    fun fsyncDirectory(directory: File)
    fun delete(file: File): Boolean
    fun deleteTree(file: File): Boolean
    fun mkdirs(directory: File): Boolean
    fun list(directory: File): List<File>
    fun walkFiles(directory: File): List<File>
    fun exists(file: File): Boolean
    fun isDirectory(file: File): Boolean
    fun size(file: File): Long
    fun appendLine(file: File, line: ByteArray)

    /** Nanosecond mtime where the filesystem supports it; millisecond fallback. */
    fun lastModifiedNanos(file: File): Long = try {
        Files.getLastModifiedTime(file.toPath()).to(TimeUnit.NANOSECONDS)
    } catch (failure: IOException) {
        file.lastModified() * 1_000_000L
    }

    /** Sets the mtime; false means the filesystem rejected the update. */
    fun setLastModified(file: File, millis: Long): Boolean =
        file.setLastModified(millis)

    /**
     * Flushes the file's data and inode metadata (including mtime) before a
     * rename. A parent-directory fsync alone does not prove the ordering
     * metadata durable.
     */
    fun fsyncFile(file: File) {
        openRead(file).use { it.force(true) }
    }

    fun readAll(file: File): ByteArray {
        val channel = openRead(file)
        try {
            val size = channel.size()
            if (size > Int.MAX_VALUE) throw IOException("fileTooLarge")
            val out = ByteArray(size.toInt())
            val buffer = ByteBuffer.wrap(out)
            while (buffer.hasRemaining()) {
                if (channel.read(buffer) <= 0) throw IOException("shortRead")
            }
            return out
        } finally {
            channel.close()
        }
    }
}

/** Production filesystem implementation (`O_CREAT|O_EXCL`, fsync, atomic rename). */
class RealStoreIo : StoreIo {

    override fun openExclusive(file: File): FileChannel =
        FileChannel.open(
            file.toPath(),
            StandardOpenOption.CREATE_NEW,
            StandardOpenOption.READ,
            StandardOpenOption.WRITE,
        )

    override fun openRead(file: File): FileChannel =
        FileChannel.open(file.toPath(), StandardOpenOption.READ)

    override fun atomicMove(from: File, to: File) {
        Files.move(
            from.toPath(),
            to.toPath(),
            StandardCopyOption.ATOMIC_MOVE,
            StandardCopyOption.REPLACE_EXISTING,
        )
    }

    override fun fsyncDirectory(directory: File) {
        FileChannel.open(directory.toPath(), StandardOpenOption.READ).use { channel ->
            channel.force(true)
        }
    }

    override fun delete(file: File): Boolean = Files.deleteIfExists(file.toPath())

    override fun deleteTree(file: File): Boolean {
        if (!Files.exists(file.toPath(), LinkOption.NOFOLLOW_LINKS)) return true
        if (Files.isSymbolicLink(file.toPath()) || !Files.isDirectory(file.toPath())) {
            return Files.deleteIfExists(file.toPath())
        }
        Files.walkFileTree(
            file.toPath(),
            object : java.nio.file.SimpleFileVisitor<java.nio.file.Path>() {
                override fun visitFile(
                    path: java.nio.file.Path,
                    attrs: java.nio.file.attribute.BasicFileAttributes,
                ): java.nio.file.FileVisitResult {
                    Files.deleteIfExists(path)
                    return java.nio.file.FileVisitResult.CONTINUE
                }

                override fun postVisitDirectory(
                    path: java.nio.file.Path,
                    failure: IOException?,
                ): java.nio.file.FileVisitResult {
                    Files.deleteIfExists(path)
                    return java.nio.file.FileVisitResult.CONTINUE
                }
            },
        )
        return !Files.exists(file.toPath(), LinkOption.NOFOLLOW_LINKS)
    }

    override fun mkdirs(directory: File): Boolean =
        directory.isDirectory || directory.mkdirs()

    override fun list(directory: File): List<File> =
        directory.listFiles()?.toList() ?: emptyList()

    override fun walkFiles(directory: File): List<File> {
        if (!directory.isDirectory) return emptyList()
        val out = mutableListOf<File>()
        val stack = ArrayDeque<File>()
        stack.addLast(directory)
        while (stack.isNotEmpty()) {
            val current = stack.removeLast()
            val children = current.listFiles() ?: continue
            for (child in children) {
                if (child.isDirectory) stack.addLast(child) else out += child
            }
        }
        return out
    }

    override fun exists(file: File): Boolean = file.exists()

    override fun isDirectory(file: File): Boolean = file.isDirectory

    override fun size(file: File): Long = file.length()

    override fun appendLine(file: File, line: ByteArray) {
        file.parentFile?.let { if (!it.isDirectory) it.mkdirs() }
        java.io.FileOutputStream(file, true).use { output ->
            output.write(line)
            output.write('\n'.code)
            output.fd.sync()
        }
    }
}

// --------------------------------------------------------------------------
// Store objects and FXC1 header
// --------------------------------------------------------------------------

/** A single named FXC1 object inside an aggregate. */
sealed class StoreObject {
    abstract val aggregate: AggregateRef
    abstract val objectKind: ObjectKind
    abstract val fileIdToken: String
    abstract val relativeDir: String
    abstract val fileName: String
}

data class MetaObject(override val aggregate: AggregateRef) : StoreObject() {
    override val objectKind: ObjectKind = ObjectKind.META
    override val fileIdToken: String = aggregate.id
    override val relativeDir: String = ""
    override val fileName: String = "meta.fx1"
}

data class HeadObject(override val aggregate: AggregateRef) : StoreObject() {
    override val objectKind: ObjectKind = ObjectKind.META
    override val fileIdToken: String = "head:" + aggregate.id
    override val relativeDir: String = ""
    override val fileName: String = "head.fx1"
}

data class RevisionObject(
    override val aggregate: AggregateRef,
    val revisionId: String,
) : StoreObject() {
    init {
        if (!AggregateRef.isValidId(revisionId)) throw PlatformSecurityException()
    }

    override val objectKind: ObjectKind = ObjectKind.REVISION
    override val fileIdToken: String = revisionId
    override val relativeDir: String = "rev"
    override val fileName: String = revisionId + ".fx1"
}

data class SourceObject(
    override val aggregate: AggregateRef,
    val sourceId: String,
) : StoreObject() {
    init {
        if (!AggregateRef.isValidId(sourceId)) throw PlatformSecurityException()
    }

    override val objectKind: ObjectKind = ObjectKind.SOURCE
    override val fileIdToken: String = sourceId
    override val relativeDir: String = "src"
    override val fileName: String = sourceId + ".fxc"
}

data class SignatureObject(
    override val aggregate: AggregateRef,
    val assetId: String,
) : StoreObject() {
    init {
        if (!AggregateRef.isValidId(assetId)) throw PlatformSecurityException()
    }

    override val objectKind: ObjectKind = ObjectKind.SIGNATURE
    override val fileIdToken: String = assetId
    override val relativeDir: String = "sig"
    override val fileName: String = assetId + ".fxs"
}

data class TemplateVersionObject(
    override val aggregate: AggregateRef,
    val versionId: String,
) : StoreObject() {
    init {
        if (!AggregateRef.isValidId(versionId)) throw PlatformSecurityException()
    }

    override val objectKind: ObjectKind = ObjectKind.TEMPLATE_VERSION
    override val fileIdToken: String = versionId
    override val relativeDir: String = "ver"
    override val fileName: String = versionId + ".fx1"
}

private data class StagedObject(
    val obj: StoreObject,
    val file: File,
    val header: FxcHeader,
)

private data class RevisionCandidate(
    val revisionId: String,
    val plaintextSha256: String,
)

private data class RevisionSearch(
    val candidate: RevisionCandidate?,
    val ambiguous: Boolean,
)

private data class AggregateHealth(
    val readable: Boolean,
    val reasonCode: String?,
    val head: CommittedHead?,
    val headCorrupt: Boolean,
    val fellBackToOlderRevision: Boolean,
    val incomplete: Boolean = false,
    val ambiguousRevisionOrder: Boolean = false,
) {
    fun toException(): StorageException = when (reasonCode) {
        EncryptedStore.SAVE_002 -> KeyUnavailableException()
        EncryptedStore.SAVE_008 -> KeystoreUnavailableException(retryable = false)
        EncryptedStore.SAVE_005 -> SchemaTooNewException()
        else -> CorruptDataException()
    }
}

/** Parsed and validated 160-byte FXC1 header. */
class FxcHeader(
    val version: Int,
    val flags: Int,
    val keyScheme: Int,
    val objectKind: ObjectKind,
    val chunkSize: Int,
    val plaintextLength: Long,
    val chunkCount: Int,
    val noncePrefix: ByteArray,
    val wrapIv: ByteArray,
    val wrappedKey: ByteArray,
    val plaintextSha256: ByteArray,
    val fileId: ByteArray,
) {

    fun encode(): ByteArray {
        val buffer = ByteBuffer.allocate(EncryptedStore.HEADER_SIZE)
            .order(ByteOrder.BIG_ENDIAN)
        buffer.put(MAGIC)
        buffer.putShort(version.toShort())
        buffer.putShort(flags.toShort())
        buffer.put(keyScheme.toByte())
        buffer.put(objectKind.wire.toByte())
        buffer.putShort(0)
        buffer.putInt(chunkSize)
        buffer.putLong(plaintextLength)
        buffer.putInt(chunkCount)
        buffer.put(noncePrefix)
        buffer.putInt(0)
        buffer.putShort(EncryptedStore.WRAP_IV_SIZE.toShort())
        buffer.put(wrapIv)
        buffer.putShort(EncryptedStore.WRAPPED_DEK_SIZE.toShort())
        buffer.put(wrappedKey)
        buffer.put(plaintextSha256)
        buffer.put(fileId)
        val crc = CRC32().apply { update(buffer.array(), 0, 156) }.value.toInt()
        buffer.putInt(crc)
        return buffer.array()
    }

    companion object {
        private val MAGIC = byteArrayOf(
            'F'.code.toByte(),
            'X'.code.toByte(),
            'C'.code.toByte(),
            '1'.code.toByte(),
        )
        private val CHUNK_SIZES = setOf(
            EncryptedStore.META_CHUNK_SIZE,
            EncryptedStore.LARGE_CHUNK_SIZE,
        )

        fun decode(
            bytes: ByteArray,
            expectedKind: ObjectKind,
            expectedFileId: ByteArray,
        ): FxcHeader {
            if (bytes.size != EncryptedStore.HEADER_SIZE) {
                throw CorruptDataException()
            }
            val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
            val magic = ByteArray(4)
            buffer.get(magic)
            if (!magic.contentEquals(MAGIC)) throw CorruptDataException()

            val version = buffer.short.toInt() and 0xFFFF
            if (version > EncryptedStore.CONTAINER_VERSION) {
                throw SchemaTooNewException()
            }
            if (version != EncryptedStore.CONTAINER_VERSION) {
                throw CorruptDataException()
            }
            val flags = buffer.short.toInt() and 0xFFFF
            if (flags != EncryptedStore.FLAG_CHUNKED) throw CorruptDataException()
            val keyScheme = buffer.get().toInt() and 0xFF
            if (keyScheme != EncryptedStore.KEY_SCHEME_AGGREGATE_KEK) {
                throw CorruptDataException()
            }
            val kindWire = buffer.get().toInt() and 0xFF
            val kind = ObjectKind.fromWire(kindWire) ?: throw CorruptDataException()
            if (kind != expectedKind) throw CorruptDataException()
            if (buffer.short.toInt() != 0) throw CorruptDataException()

            val chunkSize = buffer.int
            val plaintextLength = buffer.long
            val chunkCount = buffer.int
            val noncePrefix = ByteArray(EncryptedStore.NONCE_PREFIX_SIZE)
            buffer.get(noncePrefix)
            if (buffer.int != 0) throw CorruptDataException()
            val wrapIvLength = buffer.short.toInt() and 0xFFFF
            if (wrapIvLength != EncryptedStore.WRAP_IV_SIZE) {
                throw CorruptDataException()
            }
            val wrapIv = ByteArray(wrapIvLength)
            buffer.get(wrapIv)
            val wrappedKeyLength = buffer.short.toInt() and 0xFFFF
            if (wrappedKeyLength != EncryptedStore.WRAPPED_DEK_SIZE) {
                throw CorruptDataException()
            }
            val wrappedKey = ByteArray(wrappedKeyLength)
            buffer.get(wrappedKey)
            val sha = ByteArray(EncryptedStore.HASH_SIZE)
            buffer.get(sha)
            val fileId = ByteArray(EncryptedStore.FILE_ID_SIZE)
            buffer.get(fileId)
            val storedCrc = buffer.int

            val computedCrc = CRC32().apply { update(bytes, 0, 156) }.value.toInt()
            if (storedCrc != computedCrc) throw CorruptDataException()
            if (!fileId.contentEquals(expectedFileId)) throw CorruptDataException()
            if (chunkSize !in CHUNK_SIZES) throw CorruptDataException()
            if (plaintextLength < 0 ||
                plaintextLength > EncryptedStore.MAX_OBJECT_BYTES
            ) {
                throw CorruptDataException()
            }
            val expectedChunks = if (plaintextLength == 0L) {
                0
            } else {
                ((plaintextLength + chunkSize - 1) / chunkSize).toInt()
            }
            if (chunkCount != expectedChunks) throw CorruptDataException()
            return FxcHeader(
                version = version,
                flags = flags,
                keyScheme = keyScheme,
                objectKind = kind,
                chunkSize = chunkSize,
                plaintextLength = plaintextLength,
                chunkCount = chunkCount,
                noncePrefix = noncePrefix,
                wrapIv = wrapIv,
                wrappedKey = wrappedKey,
                plaintextSha256 = sha,
                fileId = fileId,
            )
        }
    }
}

// --------------------------------------------------------------------------
// Minimal canonical JSON (sorted keys, UTF-8, no whitespace)
// --------------------------------------------------------------------------

/**
 * Canonical JSON for the store's own small envelopes and for the redacted
 * diagnostics event. It is deliberately local: the Kotlin storage layer gains
 * no third-party dependency, and persisted document/revision plaintext stays
 * opaque to the store.
 */
internal object CanonicalJson {

    fun encode(value: Any?): ByteArray =
        encodeToString(value).toByteArray(StandardCharsets.UTF_8)

    fun encodeToString(value: Any?): String = buildString { appendValue(this, value) }

    fun parse(bytes: ByteArray): Any? = Parser(String(bytes, StandardCharsets.UTF_8)).parse()

    private fun appendValue(out: StringBuilder, value: Any?) {
        when (value) {
            null -> out.append("null")
            is Boolean -> out.append(if (value) "true" else "false")
            is Int, is Long -> out.append(value.toString())
            is String -> appendString(out, value)
            is Map<*, *> -> {
                out.append('{')
                val entries = value.entries
                    .map { (key, entryValue) ->
                        val stringKey = key as? String
                            ?: throw IllegalArgumentException("jsonKey")
                        stringKey to entryValue
                    }
                    .sortedBy { it.first }
                entries.forEachIndexed { index, (key, entryValue) ->
                    if (index > 0) out.append(',')
                    appendString(out, key)
                    out.append(':')
                    appendValue(out, entryValue)
                }
                out.append('}')
            }
            is Iterable<*> -> {
                out.append('[')
                value.forEachIndexed { index, item ->
                    if (index > 0) out.append(',')
                    appendValue(out, item)
                }
                out.append(']')
            }
            else -> throw IllegalArgumentException("jsonValue")
        }
    }

    private fun appendString(out: StringBuilder, value: String) {
        out.append('"')
        for (char in value) {
            when (char) {
                '"' -> out.append("\\\"")
                '\\' -> out.append("\\\\")
                '\b' -> out.append("\\b")
                '\u000C' -> out.append("\\f")
                '\n' -> out.append("\\n")
                '\r' -> out.append("\\r")
                '\t' -> out.append("\\t")
                else -> {
                    if (char.code < 0x20) {
                        out.append("\\u")
                        out.append(char.code.toString(16).padStart(4, '0'))
                    } else {
                        out.append(char)
                    }
                }
            }
        }
        out.append('"')
    }

    private class Parser(private val text: String) {

        private var index = 0

        fun parse(): Any? {
            skipWhitespace()
            val value = readValue()
            skipWhitespace()
            if (index != text.length) throw IllegalArgumentException("jsonTrailing")
            return value
        }

        private fun readValue(): Any? {
            if (index >= text.length) throw IllegalArgumentException("jsonEof")
            return when (val char = text[index]) {
                '{' -> readObject()
                '[' -> readArray()
                '"' -> readString()
                't' -> readLiteral("true", true)
                'f' -> readLiteral("false", false)
                'n' -> readLiteral("null", null)
                '-', in '0'..'9' -> readNumber()
                else -> throw IllegalArgumentException("jsonChar")
            }
        }

        private fun readObject(): Map<String, Any?> {
            expect('{')
            skipWhitespace()
            val result = LinkedHashMap<String, Any?>()
            if (peek() == '}') {
                index++
                return result
            }
            while (true) {
                skipWhitespace()
                val key = readString()
                skipWhitespace()
                expect(':')
                skipWhitespace()
                result[key] = readValue()
                skipWhitespace()
                when (peek()) {
                    ',' -> {
                        index++
                    }
                    '}' -> {
                        index++
                        return result
                    }
                    else -> throw IllegalArgumentException("jsonObject")
                }
            }
        }

        private fun readArray(): List<Any?> {
            expect('[')
            skipWhitespace()
            val result = mutableListOf<Any?>()
            if (peek() == ']') {
                index++
                return result
            }
            while (true) {
                skipWhitespace()
                result += readValue()
                skipWhitespace()
                when (peek()) {
                    ',' -> {
                        index++
                    }
                    ']' -> {
                        index++
                        return result
                    }
                    else -> throw IllegalArgumentException("jsonArray")
                }
            }
        }

        private fun readString(): String {
            expect('"')
            val out = StringBuilder()
            while (index < text.length) {
                val char = text[index++]
                when (char) {
                    '"' -> return out.toString()
                    '\\' -> {
                        if (index >= text.length) throw IllegalArgumentException("jsonEscape")
                        when (val escaped = text[index++]) {
                            '"' -> out.append('"')
                            '\\' -> out.append('\\')
                            '/' -> out.append('/')
                            'b' -> out.append('\b')
                            'f' -> out.append('\u000C')
                            'n' -> out.append('\n')
                            'r' -> out.append('\r')
                            't' -> out.append('\t')
                            'u' -> {
                                if (index + 4 > text.length) {
                                    throw IllegalArgumentException("jsonUnicode")
                                }
                                val hex = text.substring(index, index + 4)
                                out.append(hex.toInt(16).toChar())
                                index += 4
                            }
                            else -> throw IllegalArgumentException("jsonEscape")
                        }
                    }
                    else -> {
                        if (char.code < 0x20) throw IllegalArgumentException("jsonControl")
                        out.append(char)
                    }
                }
            }
            throw IllegalArgumentException("jsonString")
        }

        private fun readNumber(): Any {
            val start = index
            if (peek() == '-') index++
            while (index < text.length && text[index].isDigit()) index++
            if (index < text.length && text[index] == '.') {
                index++
                while (index < text.length && text[index].isDigit()) index++
                return text.substring(start, index).toDouble()
            }
            val raw = text.substring(start, index)
            return raw.toLongOrNull() ?: raw.toDouble()
        }

        private fun readLiteral(literal: String, value: Any?): Any? {
            if (!text.startsWith(literal, index)) {
                throw IllegalArgumentException("jsonLiteral")
            }
            index += literal.length
            return value
        }

        private fun skipWhitespace() {
            while (index < text.length && text[index].isWhitespace()) index++
        }

        private fun peek(): Char? = if (index < text.length) text[index] else null

        private fun expect(expected: Char) {
            if (peek() != expected) throw IllegalArgumentException("jsonExpected")
            index++
        }
    }
}
