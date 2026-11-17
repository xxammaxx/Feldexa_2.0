// T037 reusable `DocumentImportPort` conformance suite.
//
// Owner: `packages/feldexa_testkit/lib/src/import_conformance_suite.dart`
// (T037). Normative sources:
//   * `contracts/ports.md` §1, §2.1, §2.10, §3, and §4;
//   * `contracts/storage-format.md` §3.1 step 3 and §5 — a staged read-back or
//     authentication mismatch is `CorruptDataException` (`SAVE-003`), while an
//     unreadable input is `IMP-002`;
//   * `contracts/error-catalog.de.md` §1 and §11.1 — catalog codes, German
//     messages, and the ARB-key mapping;
//   * `spec.md` FR-001, FR-002, FR-004, FR-005, FR-008, FR-009, FR-010.
//
// This package intentionally depends only on `feldexa_ports`. `feldexa_core`
// is not a dependency and must not be added, so this file never names a core
// type: page-geometry expectations arrive from the caller as opaque objects
// (equality, ordering, length, and hash facts are asserted) and the adapter
// wiring lives in the consuming test package. For the same reason the file
// does not import `flutter_test`; it returns declarative checks that a runner
// registers with its test framework.
//
// Every expectation declares one of three states per adapter:
//   * `satisfied`     — executed and asserted; a violation throws
//                       [ImportConformanceFailure] and fails the runner;
//   * `notCovered`    — the runner skips it with a mandatory reason; never a
//                       pass;
//   * `nonConforming` — the runner registers a deliberate failure; never a
//                       pass.
//
// The suite is host-VM only. It produces no SIMULATED, EMULATOR, or DEVICE
// runtime evidence by itself; the consuming runner labels its adapter.

library;

import 'package:feldexa_ports/feldexa_ports.dart';

import 'fixtures/sha256.dart' show sha256Hex;

/// The reusable import-contract expectations.
///
/// The doc comment of each value is the contract clause it pins. New adapters
/// implement [ImportConformanceSubject] and reuse the same suite.
enum ImportConformanceExpectation {
  /// FR-001/FR-002: a single-page PDF is accepted with the documented
  /// `ImportedSource` shape.
  singlePageTextImport(
    'single-page-text-import',
    'a single-page PDF is accepted with the documented source shape',
  ),

  /// FR-002/FR-003: a five-page source is accepted and every page keeps its
  /// preflight geometry in order.
  fivePageGeometryImport(
    'five-page-geometry-import',
    'a five-page source is accepted with ordered page geometry',
  ),

  /// `contracts/platform-channel.md` §3/§4 and
  /// `contracts/storage-format.md` §3.2: the import commits and verifies the
  /// initial revision and head before it returns.
  initialRevisionCommittedAndVerified(
    'initial-revision-committed-and-verified',
    'the initial revision and head are committed and the source is verified',
  ),

  /// FR-004: the picked bytes are never modified, the staged copy is distinct,
  /// and `verifySource` re-reads the same hash twice.
  sourceImmutabilityAndVerification(
    'source-immutability-and-verification',
    'the picked bytes stay immutable and verifySource re-reads the same hash',
  ),

  /// FR-004/§2.1: corruption of the stored source is detected on verification
  /// and never reported as readable.
  verifyDetectsStagedCorruption(
    'verify-detects-staged-corruption',
    'verifySource detects injected staged corruption and reports it as unreadable',
  ),

  /// §1: every acceptance-relevant result carries `CapabilityEvidence`, and a
  /// simulated adapter is labelled `SIMULATED`, never a real class.
  evidenceLabelledSimulated(
    'evidence-labelled-simulated',
    'the result and descriptor carry the SIMULATED evidence label',
  ),

  /// FR-005/FR-008: a positively encrypted PDF maps to `IMP-001` without any
  /// stored record.
  imp001PasswordProtected(
    'imp001-password-protected',
    'an encrypted PDF is rejected as IMP-001 passwordProtected',
  ),

  /// FR-008: a truncated input maps to `IMP-002` (unreadable/truncated input,
  /// not a stored-integrity failure).
  imp002TruncatedInput(
    'imp002-truncated-input',
    'a truncated input is rejected as IMP-002',
  ),

  /// FR-008: random/non-PDF bytes map to `IMP-004` `notPdf`.
  imp004NotPdf(
    'imp004-not-pdf',
    'a non-PDF input is rejected as IMP-004 notPdf',
  ),

  /// FR-008: an unknown cause maps to `IMP-005` and never implies encryption.
  imp005UnknownReason(
    'imp005-unknown-reason',
    'an unknown failure is rejected as IMP-005 without a password claim',
  ),

  /// FR-008/§2.1: a source above the request cap maps to `IMP-007`.
  imp007TooLarge(
    'imp007-too-large',
    'a source above the request byte cap is rejected as IMP-007',
  ),

  /// FR-009/§2.1: picker cancellation is `ImportCancelledException` (`IMP-000`)
  /// and stages nothing.
  imp000Cancelled(
    'imp000-cancelled',
    'picker cancellation is IMP-000 and stages nothing',
  ),

  /// §2.1: storage exhaustion is `StorageFullException` (`SAVE-001`) before
  /// any source or aggregate becomes visible.
  save001StorageFull(
    'save001-storage-full',
    'storage exhaustion is SAVE-001 and leaves no record',
  ),

  /// FR-009: every rejected or cancelled import leaves no document, draft,
  /// template, stored record, or staged source.
  noRecordAfterRejection(
    'no-record-after-rejection',
    'rejections and cancellation leave no document, draft, template, record, or source',
  ),

  /// FR-002: an image-only PDF (no selectable text, no interactive form
  /// fields) is accepted on the same page-geometry terms.
  imageOnlyPdfAccepted(
    'image-only-pdf-accepted',
    'an image-only PDF is accepted on the same page-geometry terms',
  ),

  /// FR-010/`IMP-006`: a partially readable source succeeds with page failures
  /// and still creates the document.
  imp006PartialPages(
    'imp006-partial-pages',
    'a partially readable source succeeds with IMP-006 page failures',
  ),

  /// FR-008/§2.1: an unsupported PDF structure maps to `IMP-004`
  /// `unsupportedStructure`.
  imp004UnsupportedStructure(
    'imp004-unsupported-structure',
    'an unsupported PDF structure is rejected as IMP-004 unsupportedStructure',
  ),

  /// §2.1/§3: a failed staged write is `StorageWriteException` (`SAVE-003`)
  /// and leaves nothing behind.
  save003StagedWriteFailure(
    'save003-staged-write-failure',
    'a failed staged write is SAVE-003 and leaves no record',
  ),

  /// `contracts/storage-format.md` §3.1 step 3 and §5: a staged read-back or
  /// authentication mismatch is `CorruptDataException` (`SAVE-003`), never an
  /// unreadable-input `IMP-002`.
  save003StagedIntegrityMismatch(
    'save003-staged-integrity-mismatch',
    'a staged hash/authentication mismatch is CorruptDataException SAVE-003',
  ),

  /// FR-001: the real Android SAF picker and password handling. A host-VM
  /// adapter cannot claim this expectation.
  realSafPickerAndPasswordEntry(
    'real-saf-picker-and-password-entry',
    'the real Android SAF picker and password handling are exercised',
  );

  const ImportConformanceExpectation(this.id, this.description);

  /// Stable expectation id used in runner declarations and reports.
  final String id;

  /// Human-readable contract description.
  final String description;
}

/// Per-adapter status of one [ImportConformanceExpectation].
enum ImportConformanceStatus {
  /// The adapter claims the expectation and the suite will assert it.
  satisfied,

  /// The adapter cannot exercise the expectation; it is skipped with a reason.
  notCovered,

  /// The adapter is known to violate the expectation; the suite fails loudly.
  nonConforming,
}

/// A per-adapter declaration for one expectation.
final class ImportConformanceDeclaration {
  /// Declares that the adapter satisfies the expectation.
  const ImportConformanceDeclaration.satisfied()
    : status = ImportConformanceStatus.satisfied,
      reason = null;

  /// Declares that the adapter cannot exercise the expectation.
  const ImportConformanceDeclaration.notCovered(this.reason)
    : status = ImportConformanceStatus.notCovered;

  /// Declares a known adapter violation that must fail the suite.
  const ImportConformanceDeclaration.nonConforming(this.reason)
    : status = ImportConformanceStatus.nonConforming;

  /// Declared status.
  final ImportConformanceStatus status;

  /// Mandatory explanation for [ImportConformanceStatus.notCovered] and
  /// [ImportConformanceStatus.nonConforming].
  final String? reason;
}

/// One executable check produced by [importConformanceChecks].
final class ImportConformanceCheck {
  /// Creates a check.
  const ImportConformanceCheck({
    required this.expectation,
    required this.status,
    required this.run,
    this.reason,
  });

  /// The expectation this check covers.
  final ImportConformanceExpectation expectation;

  /// Declared status for the adapter under test.
  final ImportConformanceStatus status;

  /// Executes the expectation and throws [ImportConformanceFailure] on a
  /// contract violation. Null exactly for [ImportConformanceStatus.notCovered].
  final Future<void> Function()? run;

  /// Skip reason for [ImportConformanceStatus.notCovered] and failure reason
  /// for [ImportConformanceStatus.nonConforming].
  final String? reason;
}

/// A loud, content-free conformance failure.
final class ImportConformanceFailure implements Exception {
  /// Creates a failure with the contract rule that was violated.
  const ImportConformanceFailure(this.message);

  /// Human-readable rule and expectation id.
  final String message;

  @override
  String toString() => 'ImportConformanceFailure: $message';
}

/// The observable result of executing one expectation.
///
/// All values are adapter-neutral. `expectedPages` holds opaque page-geometry
/// values supplied by the caller (never a core type named in this file), and
/// `expectedPageHashes` pins their equality/ordering without naming the type.
final class ImportConformanceObservation {
  /// Creates an observation.
  const ImportConformanceObservation({
    this.source,
    this.error,
    this.pickedBytes,
    this.stagedBytes,
    this.stagedIsDistinctBuffer,
    this.expectedPages = const <Object>[],
    this.expectedPageHashes = const <int>[],
    this.comparisonPages = const <Object>[],
    this.sourceIsImageOnly,
    this.documentCount = 0,
    this.revisionCount = 0,
    this.headPresent,
    this.templateCount = 0,
    this.artifactCount = 0,
    this.stagedSourceCount = 0,
    this.integrity,
    this.secondIntegrity,
    this.descriptor,
  });

  /// Successful import result, or null for a rejection observation.
  final ImportedSource? source;

  /// The caught typed failure, or null for a success observation.
  final Object? error;

  /// The bytes the picker supplied for this run.
  final List<int>? pickedBytes;

  /// The bytes the adapter staged, when observable.
  final List<int>? stagedBytes;

  /// Whether the staged bytes are a distinct buffer from [pickedBytes].
  final bool? stagedIsDistinctBuffer;

  /// Expected page-geometry values, supplied by the caller.
  final List<Object> expectedPages;

  /// Expected page-geometry hash codes, in page order.
  final List<int> expectedPageHashes;

  /// A second import's page geometry, used by the same-terms comparison.
  final List<Object> comparisonPages;

  /// Whether the picked source is image-only, when the adapter can observe it.
  final bool? sourceIsImageOnly;

  /// Documents present after the run.
  final int documentCount;

  /// Revisions/drafts present after the run.
  final int revisionCount;

  /// Whether the imported document has a committed head, when observed.
  final bool? headPresent;

  /// Templates present after the run.
  final int templateCount;

  /// Stored records/artifacts present after the run.
  final int artifactCount;

  /// Staged sources present after the run.
  final int stagedSourceCount;

  /// First `verifySource` result, when observed.
  final SourceIntegrity? integrity;

  /// Second `verifySource` result, when observed.
  final SourceIntegrity? secondIntegrity;

  /// The adapter descriptor, when observed.
  final CapabilityDescriptor? descriptor;
}

/// Adapter-specific wiring consumed by [importConformanceChecks].
///
/// A runner implements this once per adapter. The suite owns every contract
/// assertion; the subject only declares coverage and produces observations.
abstract interface class ImportConformanceSubject {
  /// Human-readable adapter label shown in the test names.
  String get adapterLabel;

  /// Declares whether this adapter covers [expectation].
  ImportConformanceDeclaration declare(
    ImportConformanceExpectation expectation,
  );

  /// Executes [expectation] and returns its observed values.
  Future<ImportConformanceObservation> observe(
    ImportConformanceExpectation expectation,
  );
}

/// Builds the complete check list for [subject].
///
/// The runner registers one test per check: call [ImportConformanceCheck.run]
/// for `satisfied` and `nonConforming`, and skip with `reason` for
/// `notCovered`.
List<ImportConformanceCheck> importConformanceChecks(
  ImportConformanceSubject subject,
) {
  final List<ImportConformanceCheck> checks = <ImportConformanceCheck>[];
  for (final ImportConformanceExpectation expectation
      in ImportConformanceExpectation.values) {
    final ImportConformanceDeclaration declaration = subject.declare(
      expectation,
    );
    switch (declaration.status) {
      case ImportConformanceStatus.satisfied:
        checks.add(
          ImportConformanceCheck(
            expectation: expectation,
            status: declaration.status,
            run: () async {
              final ImportConformanceObservation observation = await subject
                  .observe(expectation);
              assertImportConformance(expectation, observation);
            },
          ),
        );
      case ImportConformanceStatus.notCovered:
        checks.add(
          ImportConformanceCheck(
            expectation: expectation,
            status: declaration.status,
            run: null,
            reason: _requiredReason(declaration),
          ),
        );
      case ImportConformanceStatus.nonConforming:
        final String reason = _requiredReason(declaration);
        checks.add(
          ImportConformanceCheck(
            expectation: expectation,
            status: declaration.status,
            run: () async {
              throw ImportConformanceFailure(
                'NON-CONFORMING ${expectation.id}: $reason',
              );
            },
            reason: reason,
          ),
        );
    }
  }
  return List<ImportConformanceCheck>.unmodifiable(checks);
}

/// Asserts every contract rule of [expectation] against [observation].
///
/// Throws [ImportConformanceFailure] on the first violation. Public so a
/// future runner can execute the same assertions without the check list.
void assertImportConformance(
  ImportConformanceExpectation expectation,
  ImportConformanceObservation observation,
) {
  switch (expectation) {
    case ImportConformanceExpectation.singlePageTextImport:
    case ImportConformanceExpectation.fivePageGeometryImport:
      _assertSuccess(observation, expectation);
      _assertGeometry(observation, expectation);
    case ImportConformanceExpectation.initialRevisionCommittedAndVerified:
      _assertInitialRevision(observation, expectation);
    case ImportConformanceExpectation.sourceImmutabilityAndVerification:
      _assertSuccess(observation, expectation);
      _assertImmutability(observation, expectation);
      _assertIntegrity(observation, expectation);
    case ImportConformanceExpectation.verifyDetectsStagedCorruption:
      _assertSuccess(observation, expectation);
      _assertInjectedCorruption(observation, expectation);
    case ImportConformanceExpectation.evidenceLabelledSimulated:
      _assertSuccess(observation, expectation);
      _assertEvidence(observation, expectation);
    case ImportConformanceExpectation.imp001PasswordProtected:
      _assertRejection(
        observation,
        expectation,
        ImportRejectionKind.passwordProtected,
        'IMP-001',
      );
    case ImportConformanceExpectation.imp002TruncatedInput:
      _assertRejection(
        observation,
        expectation,
        ImportRejectionKind.truncated,
        'IMP-002',
      );
    case ImportConformanceExpectation.imp004NotPdf:
      _assertRejection(
        observation,
        expectation,
        ImportRejectionKind.notPdf,
        'IMP-004',
      );
    case ImportConformanceExpectation.imp005UnknownReason:
      _assertRejection(
        observation,
        expectation,
        ImportRejectionKind.unknownReason,
        'IMP-005',
      );
    case ImportConformanceExpectation.imp007TooLarge:
      _assertRejection(
        observation,
        expectation,
        ImportRejectionKind.tooLarge,
        'IMP-007',
      );
    case ImportConformanceExpectation.imp000Cancelled:
      _assertCancellation(observation, expectation);
    case ImportConformanceExpectation.save001StorageFull:
      _assertStorageFull(observation, expectation);
    case ImportConformanceExpectation.noRecordAfterRejection:
      _assertNoRecords(observation, expectation);
    case ImportConformanceExpectation.imageOnlyPdfAccepted:
      _assertSuccess(observation, expectation);
      _assertGeometry(observation, expectation);
      _require(
        observation.sourceIsImageOnly == true,
        '${expectation.id}: the source must be image-only',
      );
    case ImportConformanceExpectation.imp006PartialPages:
      _assertSuccess(observation, expectation, expectFullPages: false);
      _require(
        observation.source!.pageFailures.isNotEmpty,
        '${expectation.id}: IMP-006 requires page failures',
      );
    case ImportConformanceExpectation.imp004UnsupportedStructure:
      _assertRejection(
        observation,
        expectation,
        ImportRejectionKind.unsupportedStructure,
        'IMP-004',
      );
    case ImportConformanceExpectation.save003StagedWriteFailure:
      _assertStagedWriteFailure(observation, expectation);
    case ImportConformanceExpectation.save003StagedIntegrityMismatch:
      _assertStagedIntegrityMismatch(observation, expectation);
    case ImportConformanceExpectation.realSafPickerAndPasswordEntry:
      throw ImportConformanceFailure(
        '${expectation.id}: a host-VM adapter cannot claim the real Android '
        'SAF picker or password handling; this expectation requires an '
        'Android instrumentation runner.',
      );
  }
}

String _requiredReason(ImportConformanceDeclaration declaration) {
  final String? reason = declaration.reason;
  if (reason == null || reason.trim().isEmpty) {
    throw StateError(
      'a non-satisfied conformance declaration requires a non-empty reason',
    );
  }
  return reason;
}

void _require(bool condition, String message) {
  if (!condition) {
    throw ImportConformanceFailure(message);
  }
}

void _requireEqual(Object? actual, Object? expected, String message) {
  if (actual != expected) {
    throw ImportConformanceFailure(
      '$message: expected <$expected>, got <$actual>',
    );
  }
}

bool _sameList(Iterable<Object?> actual, Iterable<Object?> expected) {
  final List<Object?> left = actual.toList(growable: false);
  final List<Object?> right = expected.toList(growable: false);
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

void _assertSuccess(
  ImportConformanceObservation observation,
  ImportConformanceExpectation expectation, {
  bool expectFullPages = true,
}) {
  final String reason = expectation.id;
  _require(observation.error == null, '$reason: unexpected typed failure');
  final ImportedSource? source = observation.source;
  _require(source != null, '$reason: ImportedSource is missing');
  final ImportedSource imported = source!;
  final List<int>? pickedBytes = observation.pickedBytes;
  _require(pickedBytes != null, '$reason: picked bytes are missing');
  _require(imported.pageCount > 0, '$reason: pageCount must be positive');
  _requireEqual(
    imported.pageCount,
    observation.expectedPages.length,
    '$reason: pageCount',
  );
  _requireEqual(
    imported.pages.length,
    imported.pageCount,
    '$reason: pages.length',
  );
  if (expectFullPages) {
    _require(
      imported.pageFailures.isEmpty,
      '$reason: a full import must have no page failures',
    );
  }
  _requireEqual(imported.sha256, sha256Hex(pickedBytes!), '$reason: sha256');
  _requireEqual(imported.sizeBytes, pickedBytes.length, '$reason: sizeBytes');
  _requireEqual(observation.documentCount, 1, '$reason: document count');
  // The generic port expectation does not prescribe a document-specific
  // revision count; `initial-revision-committed-and-verified` owns that.
  _requireEqual(observation.templateCount, 0, '$reason: template count');
  _requireEqual(observation.artifactCount, 0, '$reason: stored record count');
  _requireEqual(observation.stagedSourceCount, 1, '$reason: staged source');
}

void _assertInitialRevision(
  ImportConformanceObservation observation,
  ImportConformanceExpectation expectation,
) {
  _assertSuccess(observation, expectation);
  final ImportedSource source = observation.source!;
  final String reason = expectation.id;
  _require(
    observation.revisionCount >= 1,
    '$reason: at least one committed revision is required',
  );
  _require(
    observation.headPresent == true,
    '$reason: the document head must be committed',
  );
  final SourceIntegrity? integrity = observation.integrity;
  _require(integrity != null, '$reason: the source must be verified');
  _require(integrity!.readable, '$reason: the source must be readable');
  _requireEqual(integrity.actualSha256, source.sha256, '$reason: source hash');
}

void _assertGeometry(
  ImportConformanceObservation observation,
  ImportConformanceExpectation expectation,
) {
  final ImportedSource source = observation.source!;
  final String reason = expectation.id;
  _requireEqual(
    observation.expectedPages.length,
    source.pageCount,
    '$reason: expected geometry count',
  );
  for (int index = 0; index < source.pageCount; index++) {
    _requireEqual(
      source.pages[index],
      observation.expectedPages[index],
      '$reason: page $index geometry',
    );
  }
  _require(
    _sameList(
      source.pages.map((Object page) => page.hashCode),
      observation.expectedPageHashes,
    ),
    '$reason: page geometry order and hash',
  );
  if (observation.comparisonPages.isNotEmpty) {
    _require(
      _sameList(source.pages, observation.comparisonPages),
      '$reason: same page-geometry terms',
    );
  }
}

void _assertImmutability(
  ImportConformanceObservation observation,
  ImportConformanceExpectation expectation,
) {
  final String reason = expectation.id;
  final List<int>? stagedBytes = observation.stagedBytes;
  _require(stagedBytes != null, '$reason: staged bytes are missing');
  _require(
    _sameList(stagedBytes!, observation.pickedBytes!),
    '$reason: staged bytes must equal the picked bytes',
  );
  _require(
    observation.stagedIsDistinctBuffer == true,
    '$reason: the staged bytes must be a defensive copy',
  );
}

void _assertIntegrity(
  ImportConformanceObservation observation,
  ImportConformanceExpectation expectation,
) {
  final ImportedSource source = observation.source!;
  final String reason = expectation.id;
  final SourceIntegrity? integrity = observation.integrity;
  _require(integrity != null, '$reason: first verifySource is missing');
  _require(integrity!.readable, '$reason: verifySource must be readable');
  _requireEqual(integrity.actualSha256, source.sha256, '$reason: hash');
  _requireEqual(integrity.pageCount, source.pageCount, '$reason: page count');
  _require(
    integrity.pageFailures.isEmpty,
    '$reason: verifySource page failures',
  );
  final CapabilityDescriptor? descriptor = observation.descriptor;
  _require(descriptor != null, '$reason: adapter descriptor is required');
  _requireEqual(
    integrity.evidence.evidenceClass,
    descriptor!.evidence.evidenceClass,
    '$reason: verify evidence must match the adapter descriptor',
  );
  _requireEqual(
    integrity.evidence,
    descriptor.evidence,
    '$reason: verify evidence label must match the descriptor',
  );
  final SourceIntegrity? second = observation.secondIntegrity;
  _require(second != null, '$reason: second verifySource is missing');
  _require(second!.readable, '$reason: second verifySource must be readable');
  _requireEqual(second.actualSha256, source.sha256, '$reason: second hash');
}

void _assertInjectedCorruption(
  ImportConformanceObservation observation,
  ImportConformanceExpectation expectation,
) {
  final ImportedSource source = observation.source!;
  final String reason = expectation.id;
  // The runner must inject real corruption, not select a hard-coded flag.
  _require(
    !_sameList(observation.stagedBytes!, observation.pickedBytes!),
    '$reason: corruption must have been written to the staged source',
  );
  final SourceIntegrity? integrity = observation.integrity;
  _require(integrity != null, '$reason: verifySource is missing');
  _require(
    !integrity!.readable,
    '$reason: verifySource must report the corrupted source as unreadable',
  );
  _require(
    integrity.actualSha256 != source.sha256,
    '$reason: the corrupted hash must differ from the imported hash',
  );
  final SourceIntegrity? second = observation.secondIntegrity;
  _require(second != null, '$reason: second verifySource is missing');
  _require(!second!.readable, '$reason: second verify must stay unreadable');
  _requireEqual(
    second.actualSha256,
    integrity.actualSha256,
    '$reason: deterministic read-back',
  );
}

void _assertEvidence(
  ImportConformanceObservation observation,
  ImportConformanceExpectation expectation,
) {
  final ImportedSource source = observation.source!;
  final String reason = expectation.id;
  final CapabilityEvidence evidence = source.evidence;
  _requireEqual(
    evidence.evidenceClass,
    EvidenceClass.simulated,
    '$reason: evidence class',
  );
  _requireEqual(evidence.evidenceClass.label, 'SIMULATED', '$reason: label');
  _require(evidence.simulated, '$reason: simulated flag');
  _require(evidence.evidenceClass.isRuntime, '$reason: runtime class');
  _require(
    evidence.evidenceClass != EvidenceClass.emulator,
    '$reason: never EMULATOR',
  );
  _require(
    evidence.evidenceClass != EvidenceClass.device,
    '$reason: never DEVICE',
  );
  _require(
    evidence.toString().contains('SIMULATED'),
    '$reason: evidence toString label',
  );
  final CapabilityDescriptor? descriptor = observation.descriptor;
  _require(descriptor != null, '$reason: descriptor is missing');
  _requireEqual(
    descriptor!.kind,
    CapabilityKind.documentImport,
    '$reason: descriptor kind',
  );
  _require(descriptor.isSimulated, '$reason: descriptor simulated flag');
  _requireEqual(
    descriptor.evidence.evidenceClass,
    EvidenceClass.simulated,
    '$reason: descriptor evidence',
  );
  _requireEqual(descriptor.evidence, evidence, '$reason: same evidence label');
}

void _assertRejection(
  ImportConformanceObservation observation,
  ImportConformanceExpectation expectation,
  ImportRejectionKind kind,
  String code,
) {
  final String reason = expectation.id;
  final Object? error = observation.error;
  _require(
    error is ImportRejectedException,
    '$reason: expected ImportRejectedException, got ${error.runtimeType}',
  );
  final ImportRejectedException rejection = error as ImportRejectedException;
  _requireEqual(rejection.kind, kind, '$reason: rejection kind');
  _requireEqual(rejection.code, code, '$reason: catalog code');
  _requireEqual(rejection.kind.catalogCode, code, '$reason: kind catalog code');
  _requireEqual(
    rejection.messageKey,
    _expectedArbKey(code),
    '$reason: ARB messageKey',
  );
  _require(!rejection.retryable, '$reason: retryable');
  _assertNoRecords(observation, expectation);
}

void _assertCancellation(
  ImportConformanceObservation observation,
  ImportConformanceExpectation expectation,
) {
  final String reason = expectation.id;
  final Object? error = observation.error;
  _require(
    error is ImportCancelledException,
    '$reason: expected ImportCancelledException, got ${error.runtimeType}',
  );
  final ImportCancelledException cancelled = error as ImportCancelledException;
  _requireEqual(cancelled.code, 'IMP-000', '$reason: code');
  _requireEqual(cancelled.messageKey, 'IMP-000', '$reason: messageKey');
  _require(cancelled.retryable, '$reason: retryable');
  _assertNoRecords(observation, expectation);
}

void _assertStorageFull(
  ImportConformanceObservation observation,
  ImportConformanceExpectation expectation,
) {
  final String reason = expectation.id;
  final Object? error = observation.error;
  _require(
    error is StorageFullException,
    '$reason: expected StorageFullException, got ${error.runtimeType}',
  );
  final StorageFullException full = error as StorageFullException;
  _requireEqual(full.code, 'SAVE-001', '$reason: code');
  _requireEqual(full.messageKey, 'save001', '$reason: messageKey');
  _require(full.retryable, '$reason: retryable');
  _assertNoRecords(observation, expectation);
}

void _assertStagedWriteFailure(
  ImportConformanceObservation observation,
  ImportConformanceExpectation expectation,
) {
  final String reason = expectation.id;
  final Object? error = observation.error;
  _require(
    error is StorageWriteException,
    '$reason: expected StorageWriteException, got ${error.runtimeType}',
  );
  final StorageWriteException write = error as StorageWriteException;
  _requireEqual(write.code, 'SAVE-003', '$reason: code');
  _requireEqual(write.messageKey, 'save003', '$reason: messageKey');
  _require(write.retryable, '$reason: retryable');
  _assertNoRecords(observation, expectation);
}

void _assertStagedIntegrityMismatch(
  ImportConformanceObservation observation,
  ImportConformanceExpectation expectation,
) {
  final String reason = expectation.id;
  // The T037-B2 contract: a staged hash/authentication mismatch is storage
  // damage (`CorruptDataException`, SAVE-003), not an unreadable input
  // (`ImportRejectedException(unreadable)`, IMP-002).
  final Object? error = observation.error;
  _require(
    error is CorruptDataException,
    '$reason: expected CorruptDataException, got ${error.runtimeType}',
  );
  _require(
    error is! ImportRejectedException,
    '$reason: must not collapse into ImportRejectedException IMP-002',
  );
  final CorruptDataException corrupt = error as CorruptDataException;
  _requireEqual(corrupt.code, 'SAVE-003', '$reason: code');
  _requireEqual(corrupt.messageKey, 'save003', '$reason: messageKey');
  _require(!corrupt.retryable, '$reason: retryable');
  _assertNoRecords(observation, expectation);
}

void _assertNoRecords(
  ImportConformanceObservation observation,
  ImportConformanceExpectation expectation,
) {
  final String reason = expectation.id;
  _requireEqual(observation.documentCount, 0, '$reason: document count');
  _requireEqual(observation.revisionCount, 0, '$reason: draft count');
  _requireEqual(observation.templateCount, 0, '$reason: template count');
  _requireEqual(observation.artifactCount, 0, '$reason: stored record count');
  _requireEqual(observation.stagedSourceCount, 0, '$reason: staged source');
}

/// `contracts/error-catalog.de.md` §11.1: `IMP-001` -> `imp001`.
///
/// `IMP-000` is the only import code with no German message, so it keeps the
/// catalog code as its key.
String _expectedArbKey(String code) {
  if (code == 'IMP-000') {
    return code;
  }
  return code.toLowerCase().replaceAll('-', '');
}
