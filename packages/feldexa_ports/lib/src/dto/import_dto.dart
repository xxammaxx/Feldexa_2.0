// T013 `DocumentImportPort` request and result DTOs.
//
// Owner: `packages/feldexa_ports/lib/src/dto/import_dto.dart` (T013).
// Normative sources:
//   * `contracts/ports.md` §2.1 and §2.10 — `ImportRequest`, `ImportedSource`,
//     and `SourceIntegrity`;
//   * `data-model.md` §3.3 — the canonical `PageFailure` shape;
//   * `contracts/storage-format.md` — SHA-256 source identity and the 80 MiB
//     (`83,886,080` byte) import cap.
//
// The canonical `PageGeometry`, `PageFailure`, and source-size cap come from
// `feldexa_core`; this file must not redeclare them. `ImportRejectionKind` is
// owned by T014 (`lib/src/errors.dart`) and is not repeated here.

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/evidence.dart';

import 'validation.dart';

/// Limits for one import attempt (`contracts/ports.md` §2.1).
///
/// [maxBytes] defaults to the contract's 80 MiB cap and can only be lowered;
/// a larger request would contradict `IMP-007` and the storage-format cap.
final class ImportRequest {
  /// Creates an import request.
  ///
  /// [maxBytes] must be between 1 and [maxSourceSizeBytes] (83,886,080 bytes).
  /// Throws a safe [ArgumentError] for a value outside that range.
  factory ImportRequest({int maxBytes = maxSourceSizeBytes}) {
    if (maxBytes < 1 || maxBytes > maxSourceSizeBytes) {
      throw ArgumentError('maxBytes must be between 1 and $maxSourceSizeBytes');
    }
    return ImportRequest._(maxBytes);
  }

  const ImportRequest._(this.maxBytes);

  /// The maximum accepted source size in bytes.
  final int maxBytes;

  @override
  String toString() => 'ImportRequest(maxBytes: $maxBytes)';
}

/// The result of a completed, verified document import
/// (`contracts/ports.md` §2.1).
///
/// The encrypted source is already written, read back, and hash-verified when
/// this value is returned; no partial source is visible. [pages] carries the
/// preflight geometry of every page, while [pageFailures] is non-empty only
/// for the partially-readable case. [displayName] is user-visible only and is
/// never treated as a path.
final class ImportedSource {
  /// Creates a verified imported-source result.
  ///
  /// [documentId] and [sourceId] are lowercase UUIDv4 values, [sha256] is the
  /// 64-character lowercase digest, [sizeBytes] is 1–[maxSourceSizeBytes],
  /// [pageCount] is at least 1, and `pages.length` must equal [pageCount].
  /// Each failure must name a unique page inside the source. Invalid values
  /// throw a safe [ArgumentError] that does not echo content.
  factory ImportedSource({
    required String documentId,
    required String sourceId,
    required String sha256,
    required int sizeBytes,
    required int pageCount,
    required Iterable<PageGeometry> pages,
    Iterable<PageFailure> pageFailures = const <PageFailure>[],
    String? displayName,
    required CapabilityEvidence evidence,
  }) {
    final String checkedDocumentId = requireUuidV4(documentId, 'documentId');
    final String checkedSourceId = requireUuidV4(sourceId, 'sourceId');
    final String checkedSha256 = requireSha256(sha256, 'sha256');
    if (sizeBytes < 1 || sizeBytes > maxSourceSizeBytes) {
      throw ArgumentError(
        'sizeBytes must be between 1 and $maxSourceSizeBytes',
      );
    }
    final int checkedPageCount = requirePositiveInt(pageCount, 'pageCount');
    final List<PageGeometry> pageList = freezeList<PageGeometry>(pages);
    if (pageList.length != checkedPageCount) {
      throw ArgumentError('pages.length must equal pageCount');
    }
    final List<PageFailure> failures = freezeList<PageFailure>(pageFailures);
    final Set<int> failedPages = <int>{};
    for (final PageFailure failure in failures) {
      if (failure.pageIndex >= checkedPageCount) {
        throw ArgumentError('a page failure references a missing page');
      }
      if (!failedPages.add(failure.pageIndex)) {
        throw ArgumentError('a page may fail at most once');
      }
    }
    final String? checkedDisplayName = optionalDisplayName(displayName);
    return ImportedSource._(
      documentId: checkedDocumentId,
      sourceId: checkedSourceId,
      sha256: checkedSha256,
      sizeBytes: sizeBytes,
      pageCount: checkedPageCount,
      pages: pageList,
      pageFailures: failures,
      displayName: checkedDisplayName,
      evidence: evidence,
    );
  }

  const ImportedSource._({
    required this.documentId,
    required this.sourceId,
    required this.sha256,
    required this.sizeBytes,
    required this.pageCount,
    required this.pages,
    required this.pageFailures,
    required this.displayName,
    required this.evidence,
  });

  /// UUIDv4 of the document aggregate created for this source.
  final String documentId;

  /// UUIDv4 of the immutable encrypted source object.
  final String sourceId;

  /// Verified SHA-256 of the original source bytes.
  final String sha256;

  /// Size of the original source in bytes.
  final int sizeBytes;

  /// Number of pages in the source.
  final int pageCount;

  /// Preflight geometry of every page, ordered contiguously from index 0.
  final List<PageGeometry> pages;

  /// Failed pages; empty unless the source was only partially readable.
  final List<PageFailure> pageFailures;

  /// Optional user-visible file name, never a path.
  final String? displayName;

  /// Evidence class of the adapter that produced this result.
  final CapabilityEvidence evidence;

  /// Redacted identity for logs; content and the display name are omitted.
  @override
  String toString() {
    return 'ImportedSource(pageCount: $pageCount, sizeBytes: $sizeBytes, '
        'pageFailures: ${pageFailures.length})';
  }
}

/// The result of re-validating an already stored source without user
/// interaction (`contracts/ports.md` §2.1).
///
/// [actualSha256] and [pageCount] are optional because an unreadable source may
/// not expose either. When [pageCount] is known, every failure must reference a
/// page inside it.
final class SourceIntegrity {
  /// Creates a source-integrity result.
  ///
  /// [actualSha256], when present, must be a 64-character lowercase digest and
  /// [pageCount], when present, must be at least 1. Invalid values throw a safe
  /// [ArgumentError].
  factory SourceIntegrity({
    required bool readable,
    String? actualSha256,
    int? pageCount,
    Iterable<PageFailure> pageFailures = const <PageFailure>[],
  }) {
    final String? checkedSha256 = optionalSha256(actualSha256, 'actualSha256');
    final int? checkedPageCount = pageCount == null
        ? null
        : requirePositiveInt(pageCount, 'pageCount');
    final List<PageFailure> failures = freezeList<PageFailure>(pageFailures);
    final Set<int> failedPages = <int>{};
    for (final PageFailure failure in failures) {
      if (checkedPageCount != null && failure.pageIndex >= checkedPageCount) {
        throw ArgumentError('a page failure references a missing page');
      }
      if (!failedPages.add(failure.pageIndex)) {
        throw ArgumentError('a page may fail at most once');
      }
    }
    return SourceIntegrity._(
      readable: readable,
      actualSha256: checkedSha256,
      pageCount: checkedPageCount,
      pageFailures: failures,
    );
  }

  const SourceIntegrity._({
    required this.readable,
    required this.actualSha256,
    required this.pageCount,
    required this.pageFailures,
  });

  /// Whether the stored source could be read and authenticated.
  final bool readable;

  /// The hash observed on read-back, or null when it could not be computed.
  final String? actualSha256;

  /// The observed page count, or null when it could not be computed.
  final int? pageCount;

  /// Failed pages; empty when every page is readable or the list is unknown.
  final List<PageFailure> pageFailures;

  @override
  String toString() {
    return 'SourceIntegrity(readable: $readable, pageCount: $pageCount, '
        'pageFailures: ${pageFailures.length})';
  }
}
