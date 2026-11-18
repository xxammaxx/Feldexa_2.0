// T041 German import-failure mapping and rejection gate.
//
// Owner: `apps/feldexa_app/lib/features/start/import_error_mapper.dart` (T041,
// issue #41).
//
// Normative sources:
//   * `contracts/error-catalog.de.md` §1 (import codes and messages), §3
//     (storage codes reachable during an import), §11.1 (ARB key mapping), and
//     the catalog tone rules;
//   * `contracts/platform-channel.md` §2.2/§2.3/§3 — the error envelope,
//     cancellation, and the `IMP-*` import results;
//   * `spec.md` FR-005…FR-010;
//   * constitution Principles V, VI, VIII, and X.
//
// This file is the only place that turns a typed platform failure into German
// user text. Every user-facing sentence is resolved through
// `AppLocalizations`, which reads the committed `app_de.arb`; no German
// sentence or recovery guidance is written here. Codes stay machine
// identifiers for callers, tests, and diagnostics and are never part of the
// rendered text.
//
// Two contracts are deliberately enforced by types rather than by comments:
//   * `IMP-006` is a warning attached to a *successful* partial import, so it
//     is produced by [ImportErrorMapper.partialWarning], never by an error
//     branch;
//   * a rejected or cancelled import cannot yield a document-creation input.
//     [ImportedDocumentCandidate] has a library-private constructor, and
//     [ImportFlow] creates it only after `pickAndImport` succeeded, so no
//     document, draft, template, or stored record can be created for a
//     rejected import (FR-009).

import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_ports/feldexa_ports.dart';

/// German presentation of one import failure.
///
/// [message] and [recovery] are the exact catalog sentences from
/// `AppLocalizations`. [code] is the observed stable catalog code and exists
/// for callers, tests, and diagnostics only; callers must render [message] and
/// [recovery], never [code].
///
/// A failure whose reason cannot be determined uses the `IMP-005` text
/// ([presentationCode] `IMP-005`, [isUnrecognized] true) and therefore never
/// claims password protection (FR-007).
final class ImportFailurePresentation {
  /// Creates a presentation. Only [ImportErrorMapper] produces these values.
  const ImportFailurePresentation._({
    required this.code,
    required this.presentationCode,
    required this.message,
    required this.recovery,
    required this.retryable,
    required this.severity,
    required this.isCancellation,
    required this.passwordProtectionConfirmed,
  });

  /// Stable catalog code observed from the platform, for tests and diagnostics.
  final String code;

  /// Catalog code whose German text is shown.
  ///
  /// This differs from [code] only when the observed code has no dedicated
  /// import presentation; the mapper then uses the `IMP-005` text.
  final String presentationCode;

  /// Exact German primary message, or `null` when the catalog defines none.
  ///
  /// `IMP-000` and cancellation (`PLT-004`) have no message: the picker result
  /// returns the user to the previous screen.
  final String? message;

  /// Exact German recovery guidance, or `null` when the catalog defines none.
  final String? recovery;

  /// Whether the documented recovery action may be retried immediately.
  final bool retryable;

  /// Internal triage severity, never rendered.
  final ErrorSeverity severity;

  /// Whether the user cancelled, so the screen returns without a message.
  final bool isCancellation;

  /// Whether the `IMP-001` sentence's claim of password protection is exact.
  ///
  /// It is true only for a positively classified
  /// `import.passwordProtected` failure. A PDF that is positively encrypted
  /// but reported as `import.unsupportedEncryption` still uses the single
  /// committed `IMP-001` catalog sentence, because the catalog has no second
  /// German text and this mapper must not invent one; for that case the flag
  /// is false to mark the open T041/owner wording question. `IMP-002`…
  /// `IMP-007`, storage codes, cancellation, and unknown codes are all false.
  final bool passwordProtectionConfirmed;

  /// Whether the observed code had no dedicated presentation and `IMP-005`
  /// semantics (cause unknown) were used.
  bool get isUnrecognized => code != presentationCode;

  /// Whether the platform defined a user-visible message for this failure.
  bool get hasMessage => message != null;

  /// Redacted identity for logs; never includes a code or document content.
  @override
  String toString() =>
      'ImportFailurePresentation(severity: ${severity.label}, '
      'retryable: $retryable, cancelled: $isCancellation)';
}

/// The `IMP-006` warning for a successful partial import (FR-010).
///
/// This is not an error state: the readable pages stay usable and the document
/// may be created. [pageNumbers] are the affected pages as 1-based numbers in
/// ascending order, ready for the page strip; [message] is the catalog
/// `imp006` sentence with its typed `{pages}` placeholder filled from those
/// numbers.
final class ImportPartialWarning {
  /// Creates the partial-import warning. Only [ImportErrorMapper] produces it.
  const ImportPartialWarning._({
    required this.message,
    required this.recovery,
    required this.pageNumbers,
  });

  /// Exact German warning with the affected pages filled in.
  final String message;

  /// Exact German recovery guidance for the warning.
  final String recovery;

  /// Affected pages as ascending 1-based page numbers.
  final List<int> pageNumbers;

  @override
  String toString() =>
      'ImportPartialWarning(pageNumbers: ${pageNumbers.join(', ')})';
}

/// Maps typed platform failures and partial-import results to German text.
///
/// The mapper is the single translation point; see the file header for the
/// catalog mapping and FR-007 rules.
final class ImportErrorMapper {
  /// Creates a mapper bound to the German localizations.
  const ImportErrorMapper(this.localizations);

  /// The German runtime resource resolved from `app_de.arb`.
  final AppLocalizations localizations;

  /// Returns the German presentation for [error].
  ///
  /// Known import codes (`IMP-001`…`IMP-005`, `IMP-007`), cancellation
  /// (`IMP-000`, `PLT-004`), and the storage codes an import can surface
  /// (`SAVE-001`, `SAVE-002`, `SAVE-003`, `SAVE-005`, `SAVE-006`, `SAVE-007`,
  /// `SAVE-008`) use their own catalog text. Any other code falls back to
  /// `IMP-005` semantics (cause unknown), never to a password claim.
  ///
  /// `IMP-006` is absent from this method by design: a partially readable
  /// source is a successful import and is presented through
  /// [partialWarning].
  ImportFailurePresentation describe(FeldexaException error) {
    final String code = error.code;
    switch (code) {
      case 'IMP-000':
      case 'PLT-004':
        return ImportFailurePresentation._(
          code: code,
          presentationCode: code,
          message: null,
          recovery: null,
          retryable: error.retryable,
          severity: error.severity,
          isCancellation: true,
          passwordProtectionConfirmed: false,
        );
      case 'IMP-001':
        // FR-007: only the positive `import.passwordProtected` diagnosis may
        // claim password protection. `import.unsupportedEncryption` is a
        // positive encryption finding but not necessarily a password, and the
        // catalog has one shared IMP-001 sentence; the flag records that this
        // wording is the open T041/owner question rather than silently
        // rewording the catalog.
        final bool password =
            (error is ImportRejectedException &&
                error.kind == ImportRejectionKind.passwordProtected) ||
            error.message == 'import.passwordProtected';
        return _catalog(
          error: error,
          presentationCode: 'IMP-001',
          message: localizations.imp001,
          recovery: localizations.imp001Recovery,
          passwordProtectionConfirmed: password,
        );
      case 'IMP-002':
        return _catalog(
          error: error,
          presentationCode: 'IMP-002',
          message: localizations.imp002,
          recovery: localizations.imp002Recovery,
        );
      case 'IMP-003':
        return _catalog(
          error: error,
          presentationCode: 'IMP-003',
          message: localizations.imp003,
          recovery: localizations.imp003Recovery,
        );
      case 'IMP-004':
        return _catalog(
          error: error,
          presentationCode: 'IMP-004',
          message: localizations.imp004,
          recovery: localizations.imp004Recovery,
        );
      case 'IMP-005':
        return _catalog(
          error: error,
          presentationCode: 'IMP-005',
          message: localizations.imp005,
          recovery: localizations.imp005Recovery,
        );
      case 'IMP-007':
        return _catalog(
          error: error,
          presentationCode: 'IMP-007',
          message: localizations.imp007,
          recovery: localizations.imp007Recovery,
        );
      case 'SAVE-001':
        return _catalog(
          error: error,
          presentationCode: 'SAVE-001',
          message: localizations.save001,
          recovery: localizations.save001Recovery,
        );
      case 'SAVE-002':
        return _catalog(
          error: error,
          presentationCode: 'SAVE-002',
          message: localizations.save002,
          recovery: localizations.save002Recovery,
        );
      case 'SAVE-003':
        return _catalog(
          error: error,
          presentationCode: 'SAVE-003',
          message: localizations.save003,
          recovery: localizations.save003Recovery,
        );
      case 'SAVE-005':
        return _catalog(
          error: error,
          presentationCode: 'SAVE-005',
          message: localizations.save005,
          recovery: localizations.save005Recovery,
        );
      case 'SAVE-006':
        // Catalog §3: internal, retried automatically once; this sentence is
        // shown only if the conflict persists. The catalog defines no recovery
        // sentence for it.
        return _catalog(
          error: error,
          presentationCode: 'SAVE-006',
          message: localizations.save006,
          recovery: null,
        );
      case 'SAVE-007':
        return _catalog(
          error: error,
          presentationCode: 'SAVE-007',
          message: localizations.save007,
          recovery: localizations.save007Recovery,
        );
      case 'SAVE-008':
        return _catalog(
          error: error,
          presentationCode: 'SAVE-008',
          message: localizations.save008,
          recovery: localizations.save008Recovery,
        );
      default:
        // FR-007/FR-008: an unknown code means the actual cause is unknown.
        // It must never be presented as password protection.
        return _catalog(
          error: error,
          presentationCode: 'IMP-005',
          message: localizations.imp005,
          recovery: localizations.imp005Recovery,
        );
    }
  }

  /// Returns the `IMP-005` presentation for a non-typed import failure.
  ///
  /// The flow uses this only for an [Exception] that is not a
  /// [FeldexaException], for example an adapter format error or an unknown
  /// channel code that the adapter rethrew unchanged. The cause is unknown by
  /// definition, so this never claims password protection.
  ImportFailurePresentation unclassified() => ImportFailurePresentation._(
    code: 'IMP-005',
    presentationCode: 'IMP-005',
    message: localizations.imp005,
    recovery: localizations.imp005Recovery,
    retryable: true,
    severity: ErrorSeverity.error,
    isCancellation: false,
    passwordProtectionConfirmed: false,
  );

  /// Returns the `IMP-006` warning for a successful partial import, or `null`
  /// when every page was readable.
  ///
  /// The `{pages}` placeholder is filled with the affected page numbers as a
  /// comma-separated ascending list of 1-based numbers, derived from the typed
  /// `PageFailure.pageIndex` values. The mapper invents no German noun for
  /// that placeholder; a wording such as „Seite 2“ would need its own
  /// catalog/ARB key.
  ImportPartialWarning? partialWarning(ImportedSource source) {
    if (source.pageFailures.isEmpty) {
      return null;
    }
    final List<int> pageNumbers =
        source.pageFailures
            .map((failure) => failure.pageIndex + 1)
            .toSet()
            .toList()
          ..sort();
    final List<int> frozen = List<int>.unmodifiable(pageNumbers);
    return ImportPartialWarning._(
      message: localizations.imp006(frozen.join(', ')),
      recovery: localizations.imp006Recovery,
      pageNumbers: frozen,
    );
  }

  ImportFailurePresentation _catalog({
    required FeldexaException error,
    required String presentationCode,
    required String message,
    required String? recovery,
    bool passwordProtectionConfirmed = false,
  }) {
    return ImportFailurePresentation._(
      code: error.code,
      presentationCode: presentationCode,
      message: message,
      recovery: recovery,
      retryable: error.retryable,
      severity: error.severity,
      isCancellation: false,
      passwordProtectionConfirmed: passwordProtectionConfirmed,
    );
  }
}

/// The only input to document creation after an import.
///
/// The constructor is library-private. [ImportFlow] creates a candidate only
/// after `DocumentImportPort.pickAndImport` returned a verified source, so a
/// rejected or cancelled [ImportOutcome] cannot reach document creation
/// (FR-009). No draft, template, or stored record is created by the flow.
final class ImportedDocumentCandidate {
  const ImportedDocumentCandidate._(this.source);

  /// The verified imported source that may become a document.
  final ImportedSource source;

  @override
  String toString() =>
      'ImportedDocumentCandidate(pageCount: ${source.pageCount})';
}

/// The result of one import attempt.
///
/// The hierarchy is sealed so a screen must handle rejection and cancellation
/// explicitly; only [ImportAccepted] carries an
/// [ImportedDocumentCandidate].
sealed class ImportOutcome {
  const ImportOutcome();
}

/// The import succeeded and document creation was invoked.
///
/// [warning] is non-null for a partially readable source (`IMP-006`); the
/// document is still usable (FR-010).
final class ImportAccepted extends ImportOutcome {
  const ImportAccepted._(this.document, this.warning);

  /// The verified source that was handed to document creation.
  final ImportedDocumentCandidate document;

  /// The `IMP-006` warning, or `null` when every page was readable.
  final ImportPartialWarning? warning;

  /// Whether this import was partially readable.
  bool get isPartial => warning != null;
}

/// The import was rejected and no document was created.
final class ImportRejected extends ImportOutcome {
  const ImportRejected(this.failure);

  /// The German presentation of the rejection.
  final ImportFailurePresentation failure;
}

/// The user cancelled the picker; no message is shown (FR-009).
final class ImportCancelled extends ImportOutcome {
  const ImportCancelled();
}

/// Creates one document from an accepted import candidate.
typedef ImportDocumentWriter = Future<void> Function(
  ImportedDocumentCandidate document,
);

/// Runs one import attempt and gates document creation on success.
///
/// [createDocument] is called exactly once, only after `pickAndImport`
/// returned a verified source. On a typed rejection, an unknown failure, or
/// cancellation it is never called, and the outcome carries no candidate that
/// could be persisted (FR-009).
final class ImportFlow {
  /// Creates the flow with the German localizations and the creation step.
  factory ImportFlow({
    required AppLocalizations localizations,
    required ImportDocumentWriter createDocument,
  }) {
    return ImportFlow._(ImportErrorMapper(localizations), createDocument);
  }

  ImportFlow._(this._mapper, this._createDocument);

  final ImportErrorMapper _mapper;
  final ImportDocumentWriter _createDocument;

  /// The mapper used by this flow, for failures outside the import call.
  ImportErrorMapper get mapper => _mapper;

  /// Picks and imports one source, then creates the document on success.
  Future<ImportOutcome> run({
    required DocumentImportPort port,
    required ImportRequest request,
  }) async {
    final ImportedSource source;
    try {
      source = await port.pickAndImport(request);
    } on FeldexaException catch (error) {
      final ImportFailurePresentation failure = _mapper.describe(error);
      if (failure.isCancellation) {
        return const ImportCancelled();
      }
      return ImportRejected(failure);
    } on Exception {
      // An adapter format error or an unknown channel code is a rejection
      // with an unknown cause; it is never treated as success.
      return ImportRejected(_mapper.unclassified());
    }
    final ImportedDocumentCandidate document = ImportedDocumentCandidate._(
      source,
    );
    final ImportPartialWarning? warning = _mapper.partialWarning(source);
    await _createDocument(document);
    return ImportAccepted._(document, warning);
  }
}
