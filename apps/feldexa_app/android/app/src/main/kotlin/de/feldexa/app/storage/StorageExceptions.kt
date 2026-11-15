package de.feldexa.app.storage

// T025 storage failure vocabulary for the Android trusted-storage layer.
//
// Normative sources:
//   * `contracts/storage-format.md` §2.3, §3.6 and §5;
//   * `contracts/ports.md` §3 (`KeyUnavailableException`, `SAVE-008`,
//     `CorruptDataException`, `PLT-002`);
//   * `contracts/error-catalog.de.md` §3; the German user text is resolved at
//     the UI boundary, never here.
//
// Exceptions carry only a catalog code, a stable machine message, a retry
// flag, and an internal severity. They never carry an alias, a document or
// template id, a path, bytes, or user content. `toString()` is deliberately
// content-free so a log line cannot leak storage identity.

/** Internal triage severity; never a user-facing value. */
enum class ErrorSeverity {
    INFO,
    WARNING,
    ERROR,
    FATAL,
}

/**
 * Base class for storage failures that map to a stable German catalog code.
 *
 * The Android implementation mirrors the canonical Dart taxonomy in
 * `packages/feldexa_ports/lib/src/errors.dart` (T014) so both adapters report
 * the same codes and retry semantics.
 */
abstract class StorageException(
    val code: String,
    val machineMessage: String,
    val retryable: Boolean,
    val severity: ErrorSeverity,
) : Exception(machineMessage) {

    /** Content-free identity; never includes an alias, id, or path. */
    override fun toString(): String =
        "${javaClass.simpleName}(code=$code, retryable=$retryable)"
}

/**
 * The owning document's or template's Keystore key is unavailable or
 * invalidated while at least one other aggregate key remains available
 * (`SAVE-002`).
 *
 * The affected aggregate's ciphertext is untouched and only that aggregate is
 * unreadable; sibling documents and templates keep their own keys. Recovery is
 * not possible (FR-052).
 */
class KeyUnavailableException : StorageException(
    code = "SAVE-002",
    machineMessage = "storage.keyUnavailable",
    retryable = false,
    severity = ErrorSeverity.FATAL,
)

/**
 * The Keystore provider is unavailable or no stored aggregate key remains
 * (`SAVE-008`).
 *
 * This is the global counterpart of [KeyUnavailableException] and must never
 * be used for one aggregate while other aggregate keys remain available.
 *
 * [retryable] is true for a temporary provider outage (retry once) and false
 * after a device-wide reset, where retrying cannot recover the keys.
 */
class KeystoreUnavailableException(
    retryable: Boolean = true,
) : StorageException(
    code = "SAVE-008",
    machineMessage = "storage.keystoreUnavailable",
    retryable = retryable,
    severity = ErrorSeverity.ERROR,
)

/**
 * Stored data failed authentication or is corrupt (`SAVE-003`).
 *
 * This is the read-side `SAVE-003` cause and the counterpart of the write-side
 * `StorageWriteException` that T026 owns. A wrapped DEK that does not
 * authenticate while its aggregate KEK is present is corrupt key material, not
 * a lost key; see the T025 evidence report for the §2.3/§5 contract reading.
 */
class CorruptDataException : StorageException(
    code = "SAVE-003",
    machineMessage = "storage.corruptData",
    retryable = false,
    severity = ErrorSeverity.FATAL,
)

/**
 * Storage is exhausted (`SAVE-001`), for example a stage write or fsync fails
 * with `ENOSPC`/`EDQUOT`.
 *
 * The last verified head is untouched and a retry after freeing space is
 * allowed (FR-074/FR-075, `contracts/storage-format.md` §5).
 */
class StorageFullException : StorageException(
    code = "SAVE-001",
    machineMessage = "storage.full",
    retryable = true,
    severity = ErrorSeverity.ERROR,
)

/**
 * A staged write, fsync, or promote failed (`SAVE-003`).
 *
 * This is the write-side counterpart of [CorruptDataException]; the staged
 * file is removed and the previous head stays intact
 * (`contracts/storage-format.md` §5).
 */
class StorageWriteException : StorageException(
    code = "SAVE-003",
    machineMessage = "storage.writeFailed",
    retryable = true,
    severity = ErrorSeverity.ERROR,
)

/**
 * Stored data was written by a newer schema version (`SAVE-005`).
 *
 * The data is untouched and writes are refused until the app is updated.
 */
class SchemaTooNewException : StorageException(
    code = "SAVE-005",
    machineMessage = "storage.schemaTooNew",
    retryable = false,
    severity = ErrorSeverity.ERROR,
)

/**
 * The caller's expected head no longer matches the verified head (`SAVE-006`).
 *
 * Internal only: the store retries the comparison once and the UI resolves a
 * persistent conflict; no optimistic success is reported.
 */
class ConcurrentSaveException : StorageException(
    code = "SAVE-006",
    machineMessage = "storage.concurrentSave",
    retryable = true,
    severity = ErrorSeverity.WARNING,
)

/**
 * A payload is too large or otherwise invalid for the store (`SAVE-007`).
 *
 * The rejected value is never included in the exception.
 */
class InvalidDataException : StorageException(
    code = "SAVE-007",
    machineMessage = "storage.invalidData",
    retryable = false,
    severity = ErrorSeverity.WARNING,
)

/**
 * A path/name or aggregate id failed validation before any Keystore access
 * (`PLT-002`).
 *
 * Extends [java.lang.SecurityException] so callers can also use the platform
 * exception type named by the contract. The rejected value is never included.
 */
class PlatformSecurityException : java.lang.SecurityException(
    "platform.securityRejected",
) {
    val code: String = "PLT-002"
    val retryable: Boolean = false
    val severity: ErrorSeverity = ErrorSeverity.ERROR

    override fun toString(): String = "PlatformSecurityException(code=$code)"
}
