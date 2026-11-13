// T014 error taxonomy.
//
// Owner: `packages/feldexa_ports/lib/src/errors.dart` (T014, issue #14).
// Normative sources:
//   * `contracts/ports.md` §3 — the complete exception table, including the
//     two `SAVE-003` causes and the `PLT-002` `SecurityException` mapping;
//   * `contracts/error-catalog.de.md` — stable codes and German user text;
//   * `contracts/storage-format.md` §5 — durable state after storage failures;
//   * constitution Principle VIII — failures are explicit and labelled, never
//     an optimistic success.
//
// Every user-facing German sentence lives in `contracts/error-catalog.de.md`
// and, later, in `apps/feldexa_app/lib/l10n/app_de.arb` (T029). Exceptions
// carry only a catalog code, an ARB key, a stable machine message, a retry
// flag, and an internal severity. They never carry bytes, file names, paths,
// OCR text, field values, signatures, or a German sentence.

/// Internal triage severity of a [FeldexaException].
///
/// Severity is for logs, diagnostics, and test assertions only. It is not a
/// user-facing value and must never replace the German catalog message. The
/// contract requires the field but does not prescribe values; these mirror
/// ordinary log levels.
enum ErrorSeverity {
  info('INFO'),
  warning('WARNING'),
  error('ERROR'),
  fatal('FATAL');

  const ErrorSeverity(this.label);

  /// Uppercase diagnostic token.
  final String label;
}

/// Base class for every typed Feldexa failure.
///
/// A failure is never represented by a `null` result and is never swallowed
/// silently. The UI resolves [messageKey] to German at its boundary; [message]
/// is a stable machine key for logs and tests and is never shown to a user.
///
/// Contract: `contracts/ports.md` §3.
abstract class FeldexaException implements Exception {
  FeldexaException({
    required String code,
    required String messageKey,
    required String message,
    required this.retryable,
    required this.severity,
  }) : code = _validateCatalogCode(code, 'code'),
       messageKey = _validateMessageKey(messageKey),
       message = _validateMachineKey(message);

  /// Stable catalog code, for example `SAVE-001`.
  ///
  /// Codes are machine identifiers used by tests and diagnostics. They are
  /// never shown in the UI.
  final String code;

  /// ARB key resolved to German at the UI boundary.
  ///
  /// Until T029 creates the ARB entries, the key is the catalog code itself;
  /// `contracts/error-catalog.de.md` is the source of truth for both.
  final String messageKey;

  /// Stable machine key for logs and tests, never a German sentence.
  final String message;

  /// Whether the operation may succeed if the user retries under the
  /// documented recovery action. `false` does not mean the failure is fatal to
  /// stored data; it means an immediate identical retry is not offered.
  final bool retryable;

  /// Internal triage level; see [ErrorSeverity].
  final ErrorSeverity severity;

  static final RegExp _catalogCodePattern = RegExp(r'^[A-Z]{2,6}-[0-9]{3}$');
  static final RegExp _messageKeyPattern = RegExp(r'^[A-Za-z][A-Za-z0-9_.-]*$');
  static final RegExp _machineKeyPattern = RegExp(
    r'^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)*$',
  );

  static String _validateCatalogCode(String value, String name) {
    if (!_catalogCodePattern.hasMatch(value)) {
      // Never echo the rejected value: it may be untrusted input and an error
      // string is a common leak channel.
      throw ArgumentError(
        '$name must be a stable catalog code such as SAVE-001',
      );
    }
    return value;
  }

  static String _validateMessageKey(String value) {
    if (!_messageKeyPattern.hasMatch(value)) {
      throw ArgumentError(
        'messageKey must be a non-empty ARB key without spaces or path '
        'separators',
      );
    }
    return value;
  }

  static String _validateMachineKey(String value) {
    if (!_machineKeyPattern.hasMatch(value)) {
      throw ArgumentError(
        'message must be a lowercase dotted machine key, never a German '
        'sentence',
      );
    }
    return value;
  }

  /// Content-free identity for logs.
  ///
  /// Subtype-specific values such as page indices are intentionally omitted
  /// here so a stack trace or log line cannot grow into document content.
  @override
  String toString() =>
      '$runtimeType(code: $code, message: $message, retryable: $retryable, '
      'severity: ${severity.label})';
}

/// The import rejection categories from `contracts/ports.md` §2.1.
///
/// This enum is owned by T014 because [ImportRejectedException] uses it; T013
/// imports it and does not redeclare it.
enum ImportRejectionKind {
  passwordProtected,
  unsupportedEncryption,
  missing,
  unreadable,
  truncated,
  notPdf,
  unsupportedStructure,
  tooLarge,
  storageFull,
  cancelled,
  unknownReason,
}

/// Maps each import rejection to its stable catalog code and machine key.
///
/// Several kinds share a catalog code because the catalog distinguishes the
/// user-facing cause at a coarser granularity than the importer's diagnosis.
/// The machine message keeps the precise kind for tests and diagnostics.
extension ImportRejectionKindCatalog on ImportRejectionKind {
  /// Stable catalog code from `contracts/error-catalog.de.md` §1.
  String get catalogCode => switch (this) {
    ImportRejectionKind.passwordProtected => 'IMP-001',
    ImportRejectionKind.unsupportedEncryption => 'IMP-001',
    ImportRejectionKind.missing => 'IMP-003',
    ImportRejectionKind.unreadable => 'IMP-002',
    ImportRejectionKind.truncated => 'IMP-002',
    ImportRejectionKind.notPdf => 'IMP-004',
    ImportRejectionKind.unsupportedStructure => 'IMP-004',
    ImportRejectionKind.tooLarge => 'IMP-007',
    ImportRejectionKind.storageFull => 'SAVE-001',
    ImportRejectionKind.cancelled => 'IMP-000',
    ImportRejectionKind.unknownReason => 'IMP-005',
  };

  /// Stable machine message, never a German sentence.
  String get machineMessage => switch (this) {
    ImportRejectionKind.passwordProtected =>
      'import.rejected.passwordProtected',
    ImportRejectionKind.unsupportedEncryption =>
      'import.rejected.unsupportedEncryption',
    ImportRejectionKind.missing => 'import.rejected.missing',
    ImportRejectionKind.unreadable => 'import.rejected.unreadable',
    ImportRejectionKind.truncated => 'import.rejected.truncated',
    ImportRejectionKind.notPdf => 'import.rejected.notPdf',
    ImportRejectionKind.unsupportedStructure =>
      'import.rejected.unsupportedStructure',
    ImportRejectionKind.tooLarge => 'import.rejected.tooLarge',
    ImportRejectionKind.storageFull => 'import.rejected.storageFull',
    ImportRejectionKind.cancelled => 'import.rejected.cancelled',
    ImportRejectionKind.unknownReason => 'import.rejected.unknownReason',
  };

  /// Internal severity for a rejected import.
  ErrorSeverity get severity => switch (this) {
    ImportRejectionKind.cancelled => ErrorSeverity.info,
    ImportRejectionKind.tooLarge => ErrorSeverity.warning,
    _ => ErrorSeverity.error,
  };
}

/// A positively diagnosed import rejection (`IMP-*`).
///
/// The import adapter must throw [StorageFullException] or
/// [StorageWriteException] for storage failures and [ImportCancelledException]
/// for cancellation. The corresponding enum kinds exist for classification at
/// the boundary but do not change this exception's fixed `retryable: false`
/// contract row.
final class ImportRejectedException extends FeldexaException {
  ImportRejectedException(ImportRejectionKind kind)
    : kind = _validateKind(kind),
      super(
        code: kind.catalogCode,
        messageKey: kind.catalogCode,
        message: kind.machineMessage,
        retryable: false,
        severity: kind.severity,
      );

  /// Precise importer diagnosis.
  final ImportRejectionKind kind;

  /// Rejects the two kinds that have a dedicated exception.
  ///
  /// §2.1 requires cancellation to throw [ImportCancelledException] and a full
  /// storage to throw [StorageFullException]. Routing them through this
  /// `IMP-*` exception would either invent a code or hide the dedicated
  /// recovery contract (`contracts/ports.md` §2.1 and §3).
  static ImportRejectionKind _validateKind(ImportRejectionKind kind) {
    if (kind == ImportRejectionKind.cancelled ||
        kind == ImportRejectionKind.storageFull) {
      throw ArgumentError(
        'use ImportCancelledException or StorageFullException for this kind',
      );
    }
    return kind;
  }
}

/// The user cancelled the platform picker (`IMP-000`).
final class ImportCancelledException extends FeldexaException {
  ImportCancelledException()
    : super(
        code: 'IMP-000',
        messageKey: 'IMP-000',
        message: 'import.cancelled',
        retryable: true,
        severity: ErrorSeverity.info,
      );
}

/// Storage is exhausted (`SAVE-001`).
///
/// The last verified head stays intact; unsaved changes remain in memory with
/// the risk badge. The operation is retryable after the user frees space
/// (`contracts/storage-format.md` §5; FR-074…FR-077).
final class StorageFullException extends FeldexaException {
  StorageFullException()
    : super(
        code: 'SAVE-001',
        messageKey: 'SAVE-001',
        message: 'storage.full',
        retryable: true,
        severity: ErrorSeverity.error,
      );
}

/// The device key material is unavailable or invalidated (`SAVE-002`).
///
/// Ciphertext is untouched and other documents load normally, but this
/// document cannot be opened. Recovery is not possible (FR-052).
final class KeyUnavailableException extends FeldexaException {
  KeyUnavailableException()
    : super(
        code: 'SAVE-002',
        messageKey: 'SAVE-002',
        message: 'storage.keyUnavailable',
        retryable: false,
        severity: ErrorSeverity.fatal,
      );
}

/// Stored data is corrupt or fails authentication (`SAVE-003`).
///
/// This is the read-side `SAVE-003` cause. It must never be collapsed into an
/// optimistic success or into [StorageWriteException], the write-side cause
/// (`contracts/storage-format.md` §5).
final class CorruptDataException extends FeldexaException {
  CorruptDataException()
    : super(
        code: 'SAVE-003',
        messageKey: 'SAVE-003',
        message: 'storage.corruptData',
        retryable: false,
        severity: ErrorSeverity.fatal,
      );
}

/// A staged write or fsync failed (`SAVE-003`).
///
/// This is the write-side `SAVE-003` cause: the staged file is removed and the
/// previous verified head stays intact, so retrying is safe. It is a distinct
/// type from [CorruptDataException] by design (`contracts/ports.md` §3).
final class StorageWriteException extends FeldexaException {
  StorageWriteException()
    : super(
        code: 'SAVE-003',
        messageKey: 'SAVE-003',
        message: 'storage.writeFailed',
        retryable: true,
        severity: ErrorSeverity.error,
      );
}

/// A path or name failed validation before any I/O (`PLT-002`).
final class SecurityException extends FeldexaException {
  SecurityException()
    : super(
        code: 'PLT-002',
        messageKey: 'PLT-002',
        message: 'platform.securityRejected',
        retryable: false,
        severity: ErrorSeverity.error,
      );
}

/// The stored schema is newer than this app version (`SAVE-005`).
///
/// Data stays untouched; writes are refused until the app is updated.
final class SchemaTooNewException extends FeldexaException {
  SchemaTooNewException()
    : super(
        code: 'SAVE-005',
        messageKey: 'SAVE-005',
        message: 'storage.schemaTooNew',
        retryable: false,
        severity: ErrorSeverity.error,
      );
}

/// Export was blocked by content that would be clipped or invalid (`EXP-001`).
///
/// No PDF is created. [fieldIds] identifies the blocking fields for the
/// message placeholders; it is a defensive, read-only copy and must never
/// contain document content.
final class ExportBlockedException extends FeldexaException {
  ExportBlockedException(List<String> fieldIds)
    : fieldIds = _validateFieldIds(fieldIds),
      super(
        code: 'EXP-001',
        messageKey: 'EXP-001',
        message: 'export.blocked',
        retryable: true,
        severity: ErrorSeverity.warning,
      );

  /// Identifiers of the fields that block the export, in caller order.
  ///
  /// Each id must be 1–128 ASCII letters, digits, hyphens, or underscores and
  /// start with a letter or digit. Paths, file names, whitespace, and
  /// free-form content are rejected; the ids are opaque identifiers, never
  /// document text.
  final List<String> fieldIds;

  static final RegExp _fieldIdPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$',
  );

  static List<String> _validateFieldIds(List<String> values) {
    if (values.isEmpty) {
      throw ArgumentError('a blocked export requires at least one field id');
    }
    final Set<String> seen = <String>{};
    for (final String value in values) {
      if (!_fieldIdPattern.hasMatch(value)) {
        // Field ids are opaque identifiers, never content. Reject paths,
        // file names with separators/extensions, whitespace, and free-form
        // text. Do not echo the rejected value.
        throw ArgumentError(
          'fieldIds must be 1-128 ASCII letters, digits, hyphens, or '
          'underscores, starting with a letter or digit',
        );
      }
      if (!seen.add(value)) {
        throw ArgumentError('fieldIds must be unique');
      }
    }
    return List<String>.unmodifiable(values);
  }
}

/// Export failed or was interrupted (`EXP-002`).
///
/// No valid artifact is presented; the document is unchanged.
final class ExportFailedException extends FeldexaException {
  ExportFailedException()
    : super(
        code: 'EXP-002',
        messageKey: 'EXP-002',
        message: 'export.failed',
        retryable: true,
        severity: ErrorSeverity.error,
      );
}

/// A page cannot be rendered (`PAGE-001`).
///
/// The remaining pages stay available and manual fields are still possible.
final class RenderException extends FeldexaException {
  RenderException({required int pageIndex})
    : pageIndex = _validatePageIndex(pageIndex),
      super(
        code: 'PAGE-001',
        messageKey: 'PAGE-001',
        message: 'render.pageFailed',
        retryable: true,
        severity: ErrorSeverity.warning,
      );

  /// Zero-based index of the page that could not be rendered.
  final int pageIndex;

  static int _validatePageIndex(int value) {
    if (value < 0) {
      throw ArgumentError('pageIndex must be a zero-based page index');
    }
    return value;
  }
}

/// On-device OCR is unavailable (`REC-001`).
///
/// Geometry-only detection remains available. The catalog explicitly does not
/// show this as a blocking error (FR-017).
final class OcrUnavailableException extends FeldexaException {
  OcrUnavailableException()
    : super(
        code: 'REC-001',
        messageKey: 'REC-001',
        message: 'ocr.unavailable',
        retryable: true,
        severity: ErrorSeverity.warning,
      );
}

/// A simulated adapter was registered in a production build (`SIM-001`).
///
/// The canonical code is `SIM-001` from the §3 table and the German catalog.
final class SimulatedInProductionException extends FeldexaException {
  SimulatedInProductionException()
    : super(
        code: 'SIM-001',
        messageKey: 'SIM-001',
        message: 'simulated.inProduction',
        retryable: false,
        severity: ErrorSeverity.fatal,
      );
}

/// The current compile target does not support the requested capability
/// (`PLT-001`).
final class UnsupportedOperationException extends FeldexaException {
  UnsupportedOperationException()
    : super(
        code: 'PLT-001',
        messageKey: 'PLT-001',
        message: 'platform.unsupported',
        retryable: false,
        severity: ErrorSeverity.error,
      );
}
