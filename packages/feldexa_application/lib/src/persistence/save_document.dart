// T090 verified document-save use case.
//
// Owner: `packages/feldexa_application/lib/src/persistence/save_document.dart`
// (T090, issue #90).
// Normative sources:
//   * `spec.md` FR-043/FR-047/FR-048 and the FR-106 pattern — save an
//     incomplete document, report success only after the stored state is
//     confirmed readable, and preserve the last saved state on failure;
//   * `contracts/ports.md` §2.4 and §3 — `SecureStorePort.saveRevision` is
//     atomic and read-back-verified, and the typed `SAVE-*` failures keep
//     their exact catalog codes;
//   * `contracts/storage-format.md` §3.1 and §5 — the verified commit
//     protocol and the durable state after each failure;
//   * `contracts/error-catalog.de.md` §3 — the stable German catalog codes;
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// The use case is one orchestration step: it validates its inputs, performs
// exactly one `SecureStorePort.saveRevision` call, and reports success only
// when the returned metadata proves the document is readable and the head is a
// new verified revision. It performs no storage read of its own because the
// adapter already read back the written revision and head before returning.
// It keeps no state, starts no timer, schedules nothing, and retries nothing;
// debouncing and lifecycle handling remain in T089's `AutosaveCoordinator`.
//
// Failure results expose only a stable catalog code. No exception text,
// document title, path, field value, signature, page content, or raw error
// detail is embedded in a result or logged here.
library;

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';

/// The outcome of [saveDocument].
///
/// A success always carries the verified [meta] and no [errorCode]; a failure
/// always carries a stable [errorCode] and no metadata. The constructor is
/// private so an optimistic-success or metadata-carrying failure state cannot
/// be built elsewhere.
final class SaveDocumentResult {
  const SaveDocumentResult._({
    required this.success,
    required this.meta,
    required this.errorCode,
  });

  /// Whether the save was verified as durable.
  final bool success;

  /// The verified store read model, or null on failure.
  final StoredMeta? meta;

  /// Stable catalog code such as `SAVE-003`, or null on success.
  final String? errorCode;

  /// True iff [success].
  bool get isSuccess => success;

  @override
  String toString() {
    // Content-free: catalog codes only, never metadata or exception detail.
    return 'SaveDocumentResult(success: $success, errorCode: $errorCode)';
  }
}

/// Atomically saves one document revision and verifies the reported head.
///
/// The [SaveRevisionRequest] is built before any port call, so an invalid
/// [documentId] or [expectedHead] throws an [ArgumentError] and performs no
/// I/O; this programmer-error path is never converted to `SAVE-003`.
/// [content] is passed by identity and never mutated.
///
/// Calls [SecureStorePort.saveRevision] exactly once. Success requires all of:
/// the call did not throw, the returned [StoredMeta.id] equals [documentId],
/// the metadata is readable, a non-null [StoredMeta.latestRevisionId] exists,
/// and that head differs from [expectedHead]. A verified commit writes a new
/// revision; for an initial save [expectedHead] is null and any non-null head
/// passes. Malformed metadata fails as `SAVE-003` without exposing the
/// unverified meta.
///
/// A [FeldexaException] maps to its exact catalog code. Any other thrown
/// object maps to `SAVE-003`. This function performs no retry, follow-up
/// write, status bookkeeping, or lifecycle handling.
Future<SaveDocumentResult> saveDocument({
  required SecureStorePort store,
  required String documentId,
  String? expectedHead,
  required RevisionContent content,
  required RevisionKind kind,
}) async {
  final SaveRevisionRequest request = SaveRevisionRequest(
    documentId: documentId,
    expectedHead: expectedHead,
    content: content,
    kind: kind,
  );

  try {
    final StoredMeta meta = await store.saveRevision(request);
    final String? latestRevisionId = meta.latestRevisionId;
    final bool verified =
        meta.id == request.documentId &&
        meta.readable &&
        latestRevisionId != null &&
        latestRevisionId != request.expectedHead;
    if (!verified) {
      return const SaveDocumentResult._(
        success: false,
        meta: null,
        errorCode: 'SAVE-003',
      );
    }
    return SaveDocumentResult._(success: true, meta: meta, errorCode: null);
  } on FeldexaException catch (error) {
    return SaveDocumentResult._(
      success: false,
      meta: null,
      errorCode: error.code,
    );
  } catch (_) {
    // Unexpected failures fail closed. No detail is exposed.
    return const SaveDocumentResult._(
      success: false,
      meta: null,
      errorCode: 'SAVE-003',
    );
  }
}
