// Feldexa versioned document aggregate (T017).
//
// Owner: `packages/feldexa_core/lib/src/model/document.dart` (T017).
// Normative sources:
//   * `data-model.md` §3.1–§3.3, §4.1, §5, and §6 — the aggregate root,
//     `SourceFileRef`, `Page`, `DocumentStatus`, `DocumentPreferences`, and the
//     persisted `DocumentMeta` envelope;
//   * `contracts/coordinates-and-geometry.md` §1–§3 — display-space geometry,
//     the 0.5 pt page-bounds tolerance, and the zoom ratio range;
//   * `contracts/recognition-output.md` §6 — conflicts are symmetric and never
//     remove a candidate;
//   * `contracts/ports.md` §2.1 and §2.10 — `PageFailure`, `SourceFileRef`,
//     `DocumentMeta`, and `Page` are the shared canonical types;
//   * `contracts/storage-format.md` §2.4 and §3.1–§3.2 — canonical plaintext
//     JSON, the initial revision, and the verified durable head;
//   * `spec.md` FR-043, FR-044, FR-096, FR-104, and FR-107.
//
// This file owns the canonical document-side types. It does not redeclare T018
// field types, T020 persistence types, or T021 template types. `DurablePointer`
// and `TemplateOrigin` are imported from their T017-owned files.
//
// Every entity is immutable-by-convention: lists and maps are stored as
// unmodifiable views and `copyWith` returns a revalidated value. Validation
// runs in release builds and never echoes a title, label, filename, text
// value, or other document content.
//
// `Document.status` is deliberately not part of the persisted JSON
// (`data-model.md` §3.1: derived, never persisted as an optimistic claim).
// `Document.fromJson` therefore restores the safe derived state (`saved`, or
// `unreadable` for an unreadable source); callers that own transient UI state
// may pass `status` explicitly. Equality includes the transient status, so a
// JSON round-trip compares equal only for the derived safe state.
//
// `Page.renderCacheKey` is likewise derived and explicitly "not persisted
// content" (`data-model.md` §3.3). It is excluded from JSON and from
// [Page.operator ==] so a cached page still equals its persisted form.
library;

import '../geometry/page_geometry.dart';
import 'canonical_json.dart';
import 'durable_pointer.dart';
import 'field.dart';
import 'page_failure.dart';
import 'template_origin.dart';

/// The only document schema version this reader accepts.
const int documentSchemaVersion = 1;

/// The 80 MiB (83,886,080-byte) source cap from `data-model.md` §3.2 and
/// `contracts/error-catalog.de.md` `IMP-007`.
const int maxSourceSizeBytes = 83886080;

/// The maximum preflight page count from `data-model.md` §3.2.
const int maxSourcePageCount = 100;

/// The transient document lifecycle state (`data-model.md` §3.1).
///
/// This state is derived from in-memory and durable state and is never written
/// to `meta.fx1` as an optimistic claim. [deleted] is terminal and therefore
/// has no live aggregate: [Document] rejects it.
enum DocumentStatus {
  /// Imported and visible, with no explicit save yet.
  draft,

  /// A verified commit completed and no changes are pending.
  saved,

  /// Committed content has changed in memory since the last verified commit.
  dirty,

  /// The last save attempt failed; the previous durable head is untouched.
  saveFailed,

  /// Export verification succeeded; a label only, no data change.
  exportReady,

  /// The source or key cannot be read; isolated to this document.
  unreadable,

  /// The user confirmed deletion; the record is removed.
  deleted,
}

/// The per-page analysis state (`data-model.md` §3.3).
enum AnalysisState {
  /// No analysis run has started.
  pending('pending'),

  /// Analysis is running.
  running('running'),

  /// Analysis completed.
  complete('complete'),

  /// Analysis failed; [Page.failure] is required.
  failed('failed');

  const AnalysisState(this.wireName);

  /// Stable JSON token.
  final String wireName;

  /// Parses a JSON token.
  ///
  /// Throws [FormatException] for a non-string or unknown token.
  static AnalysisState fromWire(Object? token) {
    if (token is String) {
      for (final AnalysisState value in values) {
        if (value.wireName == token) {
          return value;
        }
      }
    }
    throw const FormatException('Unknown page analysis state token.');
  }
}

/// The source-integrity state of an immutable encrypted source
/// (`data-model.md` §3.2).
enum SourceIntegrityState {
  /// Read-back verified the source bytes.
  verified('verified'),

  /// The source cannot be read; the document is isolated, never deleted.
  unreadable('unreadable');

  const SourceIntegrityState(this.wireName);

  /// Stable JSON token.
  final String wireName;

  /// Parses a JSON token.
  ///
  /// Throws [FormatException] for a non-string or unknown token.
  static SourceIntegrityState fromWire(Object? token) {
    if (token is String) {
      for (final SourceIntegrityState value in values) {
        if (value.wireName == token) {
          return value;
        }
      }
    }
    throw const FormatException('Unknown source integrity token.');
  }
}

/// The two review orders named by FR-026: page order and document order.
enum ReviewOrderMode {
  /// The user-visible field order stored in `Document.fieldOrder`.
  documentOrder('document_order'),

  /// Page order, then reading order within the page.
  pageOrder('page_order');

  const ReviewOrderMode(this.wireName);

  /// Stable JSON token.
  final String wireName;

  /// Parses a JSON token.
  ///
  /// Throws [FormatException] for a non-string or unknown token.
  static ReviewOrderMode fromWire(Object? token) {
    if (token is String) {
      for (final ReviewOrderMode value in values) {
        if (value.wireName == token) {
          return value;
        }
      }
    }
    throw const FormatException('Unknown review order mode token.');
  }
}

/// Immutable metadata about the encrypted original source
/// (`data-model.md` §3.2).
///
/// A `SourceFileRef` is embedded in `Document` and `Template` and is never
/// mutated in place (aggregate invariant 1). A new value object may replace it
/// to record an integrity change; the source bytes are never modified.
final class SourceFileRef {
  /// Creates a source reference.
  ///
  /// [id] must be a lowercase UUIDv4, [sha256] 64 lowercase hexadecimal
  /// characters, [sizeBytes] in `1 … 83,886,080`, and [pageCount] in
  /// `1 … 100`. [originalName] is display-only, may be null, is trimmed, and is
  /// at most 255 characters without control characters. [importedAt] must be
  /// UTC.
  ///
  /// Throws [ArgumentError] for every invalid value. The error never echoes
  /// the original filename.
  factory SourceFileRef({
    required String id,
    required String sha256,
    required int sizeBytes,
    required int pageCount,
    String? originalName,
    required DateTime importedAt,
    SourceIntegrityState integrity = SourceIntegrityState.verified,
  }) {
    final String checkedId = _validateUuidV4(id, 'id');
    final String checkedSha256 = _validateSha256(sha256, 'sha256');
    if (sizeBytes < 1 || sizeBytes > maxSourceSizeBytes) {
      throw ArgumentError(
        'sizeBytes must be between 1 and $maxSourceSizeBytes',
      );
    }
    if (pageCount < 1 || pageCount > maxSourcePageCount) {
      throw ArgumentError(
        'pageCount must be between 1 and $maxSourcePageCount',
      );
    }
    return SourceFileRef._(
      id: checkedId,
      sha256: checkedSha256,
      sizeBytes: sizeBytes,
      pageCount: pageCount,
      originalName: _normalizeOriginalName(originalName),
      importedAt: _checkUtc(importedAt, 'importedAt'),
      integrity: integrity,
    );
  }

  const SourceFileRef._({
    required this.id,
    required this.sha256,
    required this.sizeBytes,
    required this.pageCount,
    required this.originalName,
    required this.importedAt,
    required this.integrity,
  });

  /// Reads a persisted source reference.
  ///
  /// Throws [FormatException] for missing, mistyped, or invalid fields.
  factory SourceFileRef.fromJson(Map<String, Object?> json) {
    final Object? originalName = json['originalName'];
    if (originalName != null && originalName is! String) {
      throw const FormatException(
        'JSON field "originalName" must be a string or null',
      );
    }
    try {
      return SourceFileRef(
        id: _readString(json, 'id'),
        sha256: _readString(json, 'sha256'),
        sizeBytes: _readInt(json, 'sizeBytes'),
        pageCount: _readInt(json, 'pageCount'),
        originalName: originalName as String?,
        importedAt: parseCanonicalUtcTimestamp(
          json['importedAt'],
          name: 'importedAt',
        ),
        integrity: SourceIntegrityState.fromWire(json['integrity']),
      );
    } on ArgumentError catch (error) {
      throw FormatException(
        'Invalid source file reference JSON: '
        '${error.message}',
      );
    }
  }

  /// UUIDv4 naming the encrypted source object.
  final String id;

  /// SHA-256 of the original plaintext bytes, 64 lowercase hex characters.
  final String sha256;

  /// Original byte length in `1 … 83,886,080`.
  final int sizeBytes;

  /// Preflight page count in `1 … 100`.
  final int pageCount;

  /// Display-only original filename, or null when cleared. Never logged and
  /// never used as a path.
  final String? originalName;

  /// Import time in UTC.
  final DateTime importedAt;

  /// Read-back integrity of the encrypted source.
  final SourceIntegrityState integrity;

  /// Returns a copy with the supplied fields replaced.
  ///
  /// [originalName] can be cleared by passing `null`; omitting it keeps the
  /// current value. The result is revalidated by the public constructor.
  SourceFileRef copyWith({
    String? id,
    String? sha256,
    int? sizeBytes,
    int? pageCount,
    Object? originalName = _unset,
    DateTime? importedAt,
    SourceIntegrityState? integrity,
  }) {
    return SourceFileRef(
      id: id ?? this.id,
      sha256: sha256 ?? this.sha256,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      pageCount: pageCount ?? this.pageCount,
      originalName: identical(originalName, _unset)
          ? this.originalName
          : originalName as String?,
      importedAt: importedAt ?? this.importedAt,
      integrity: integrity ?? this.integrity,
    );
  }

  /// Serializes to the persisted source reference.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'sha256': sha256,
      'sizeBytes': sizeBytes,
      'pageCount': pageCount,
      'originalName': originalName,
      'importedAt': canonicalUtcTimestamp(importedAt),
      'integrity': integrity.wireName,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is SourceFileRef &&
        other.id == id &&
        other.sha256 == sha256 &&
        other.sizeBytes == sizeBytes &&
        other.pageCount == pageCount &&
        other.originalName == originalName &&
        other.importedAt == importedAt &&
        other.integrity == integrity;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      sha256,
      sizeBytes,
      pageCount,
      originalName,
      importedAt,
      integrity,
    );
  }

  @override
  String toString() {
    return 'SourceFileRef(id: $id, sizeBytes: $sizeBytes, '
        'pageCount: $pageCount, integrity: ${integrity.wireName})';
  }
}

/// One immutable page of the document (`data-model.md` §3.3).
final class Page {
  /// Creates a page.
  ///
  /// [index] is zero-based and non-negative. A [PageFailure] is required
  /// exactly when [analysis] is [AnalysisState.failed], and its page index must
  /// match [index]. [renderCacheKey] is a derived in-memory cache key: it is
  /// never persisted and does not participate in equality.
  ///
  /// Throws [ArgumentError] for every invalid value.
  factory Page({
    required int index,
    required PageGeometry geometry,
    AnalysisState analysis = AnalysisState.pending,
    PageFailure? failure,
    bool unreadable = false,
    String? renderCacheKey,
  }) {
    if (index < 0) {
      throw ArgumentError('index must be at least 0');
    }
    final bool failed = analysis == AnalysisState.failed;
    if (failed != (failure != null)) {
      throw ArgumentError(
        'failure is required exactly when analysis is failed',
      );
    }
    if (failure != null && failure.pageIndex != index) {
      throw ArgumentError('failure pageIndex must match the page index');
    }
    if (renderCacheKey != null) {
      _validateRenderCacheKey(renderCacheKey);
    }
    return Page._(
      index: index,
      geometry: geometry,
      analysis: analysis,
      failure: failure,
      unreadable: unreadable,
      renderCacheKey: renderCacheKey,
    );
  }

  const Page._({
    required this.index,
    required this.geometry,
    required this.analysis,
    required this.failure,
    required this.unreadable,
    required this.renderCacheKey,
  });

  /// Reads a persisted page.
  ///
  /// `renderCacheKey` is derived and is not read; a persisted value would be
  /// ignored. Throws [FormatException] for missing, mistyped, or invalid
  /// fields.
  factory Page.fromJson(Map<String, Object?> json) {
    final Object? rawFailure = json['failure'];
    Map<String, Object?>? failureJson;
    if (rawFailure != null) {
      if (rawFailure is! Map<String, Object?>) {
        throw const FormatException(
          'JSON field "failure" must be an object or null',
        );
      }
      failureJson = rawFailure;
    }
    try {
      return Page(
        index: _readInt(json, 'index'),
        geometry: PageGeometry.fromJson(_readObject(json, 'geometry')),
        analysis: AnalysisState.fromWire(json['analysis']),
        failure: failureJson == null ? null : PageFailure.fromJson(failureJson),
        unreadable: _readBool(json, 'unreadable'),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid page JSON: ${error.message}');
    }
  }

  /// Zero-based, contiguous page index; the document aggregate enforces that
  /// the page list is exactly `0 … pageCount - 1`.
  final int index;

  /// Preflight geometry of the page.
  final PageGeometry geometry;

  /// The analysis state.
  final AnalysisState analysis;

  /// The failure record, required exactly for [AnalysisState.failed].
  final PageFailure? failure;

  /// Whether page content could not be decoded at import.
  final bool unreadable;

  /// Derived in-memory render-cache key; never persisted, never content.
  ///
  /// Excluded from [toJson] and from equality so a cached page equals its
  /// persisted form.
  final String? renderCacheKey;

  /// Returns a copy with the supplied fields replaced.
  ///
  /// [failure] and [renderCacheKey] can be cleared by passing `null`; omitting
  /// them keeps the current value. The result is revalidated by the public
  /// constructor, so a retry must set `analysis: running, failure: null`.
  Page copyWith({
    int? index,
    PageGeometry? geometry,
    AnalysisState? analysis,
    Object? failure = _unset,
    bool? unreadable,
    Object? renderCacheKey = _unset,
  }) {
    return Page(
      index: index ?? this.index,
      geometry: geometry ?? this.geometry,
      analysis: analysis ?? this.analysis,
      failure: identical(failure, _unset)
          ? this.failure
          : failure as PageFailure?,
      unreadable: unreadable ?? this.unreadable,
      renderCacheKey: identical(renderCacheKey, _unset)
          ? this.renderCacheKey
          : renderCacheKey as String?,
    );
  }

  /// Serializes the persisted page fields.
  ///
  /// [renderCacheKey] is deliberately omitted.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'index': index,
      'geometry': geometry.toJson(),
      'analysis': analysis.wireName,
      'failure': failure?.toJson(),
      'unreadable': unreadable,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is Page &&
        other.index == index &&
        other.geometry == geometry &&
        other.analysis == analysis &&
        other.failure == failure &&
        other.unreadable == unreadable;
  }

  @override
  int get hashCode {
    return Object.hash(index, geometry, analysis, failure, unreadable);
  }

  @override
  String toString() {
    return 'Page(index: $index, analysis: ${analysis.wireName}, '
        'unreadable: $unreadable)';
  }
}

/// Non-content document view preferences (`data-model.md` §3.1).
final class DocumentPreferences {
  /// Creates document preferences.
  ///
  /// [zoom] is an optional ratio of `fitWidthScale`
  /// (`contracts/coordinates-and-geometry.md` §3) on the closed interval
  /// `0.5 … 8`; null means no stored preference. [currentPage] is
  /// non-negative; the document aggregate validates it against the page count.
  ///
  /// Throws [ArgumentError] for every invalid value.
  factory DocumentPreferences({
    double? zoom,
    int currentPage = 0,
    ReviewOrderMode reviewOrderMode = ReviewOrderMode.documentOrder,
  }) {
    if (zoom != null && (!zoom.isFinite || zoom < 0.5 || zoom > 8)) {
      throw ArgumentError('zoom must be finite and between 0.5 and 8');
    }
    if (currentPage < 0) {
      throw ArgumentError('currentPage must be at least 0');
    }
    return DocumentPreferences._(
      zoom: zoom,
      currentPage: currentPage,
      reviewOrderMode: reviewOrderMode,
    );
  }

  const DocumentPreferences._({
    required this.zoom,
    required this.currentPage,
    required this.reviewOrderMode,
  });

  /// Reads persisted preferences.
  ///
  /// `zoom` is optional and may be null. Throws [FormatException] for missing,
  /// mistyped, or invalid fields.
  factory DocumentPreferences.fromJson(Map<String, Object?> json) {
    final Object? rawZoom = json['zoom'];
    double? zoom;
    if (rawZoom != null) {
      if (rawZoom is! num) {
        throw const FormatException(
          'JSON field "zoom" must be a number or null',
        );
      }
      zoom = rawZoom.toDouble();
    }
    try {
      return DocumentPreferences(
        zoom: zoom,
        currentPage: _readInt(json, 'currentPage'),
        reviewOrderMode: ReviewOrderMode.fromWire(json['reviewOrderMode']),
      );
    } on ArgumentError catch (error) {
      throw FormatException(
        'Invalid document preferences JSON: '
        '${error.message}',
      );
    }
  }

  /// Optional zoom ratio of `fitWidthScale`; null means no preference.
  final double? zoom;

  /// Zero-based page the user last viewed; validated by [Document].
  final int currentPage;

  /// The review order the user selected.
  final ReviewOrderMode reviewOrderMode;

  /// Returns a copy with the supplied fields replaced.
  ///
  /// [zoom] can be cleared by passing `null`; omitting it keeps the current
  /// value. The result is revalidated by the public constructor.
  DocumentPreferences copyWith({
    Object? zoom = _unset,
    int? currentPage,
    ReviewOrderMode? reviewOrderMode,
  }) {
    return DocumentPreferences(
      zoom: identical(zoom, _unset) ? this.zoom : zoom as double?,
      currentPage: currentPage ?? this.currentPage,
      reviewOrderMode: reviewOrderMode ?? this.reviewOrderMode,
    );
  }

  /// Serializes to the persisted preferences object.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'zoom': zoom,
      'currentPage': currentPage,
      'reviewOrderMode': reviewOrderMode.wireName,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is DocumentPreferences &&
        other.zoom == zoom &&
        other.currentPage == currentPage &&
        other.reviewOrderMode == reviewOrderMode;
  }

  @override
  int get hashCode => Object.hash(zoom, currentPage, reviewOrderMode);

  @override
  String toString() {
    return 'DocumentPreferences(currentPage: $currentPage, '
        'reviewOrderMode: ${reviewOrderMode.wireName})';
  }
}

/// The persisted `docs/<id>/meta.fx1` envelope (`data-model.md` §4.1).
///
/// It contains list metadata only: no page content, values, or signatures. This
/// is the canonical type the start list projects from; it is not a second
/// document record.
final class DocumentMeta {
  /// Creates persisted document metadata.
  ///
  /// [id] must be a lowercase UUIDv4 and [title] is trimmed to 1–200
  /// characters without control characters. [createdAt] and [updatedAt] must
  /// be UTC. The optional [latestRevisionId] and [lastDurableAt] are validated
  /// independently because a recovered or partially written envelope may
  /// legitimately expose only one of them. A readable envelope must not carry
  /// an [unreadableReasonCode]; an unreadable envelope may omit it when the
  /// failure has no specific catalog key.
  ///
  /// Throws [ArgumentError] for every invalid value.
  factory DocumentMeta({
    required String id,
    required String title,
    required DateTime createdAt,
    required DateTime updatedAt,
    required SourceFileRef source,
    String? latestRevisionId,
    DateTime? lastDurableAt,
    bool readable = true,
    String? unreadableReasonCode,
  }) {
    final String checkedId = _validateUuidV4(id, 'id');
    final String checkedTitle = _normalizeTitle(title);
    final DateTime created = _checkUtc(createdAt, 'createdAt');
    final DateTime updated = _checkUtc(updatedAt, 'updatedAt');
    if (latestRevisionId != null) {
      _validateUuidV4(latestRevisionId, 'latestRevisionId');
    }
    if (lastDurableAt != null && !lastDurableAt.isUtc) {
      throw ArgumentError('lastDurableAt must be UTC');
    }
    if (readable && unreadableReasonCode != null) {
      throw ArgumentError(
        'unreadableReasonCode must be null when readable is true',
      );
    }
    if (unreadableReasonCode != null) {
      _validateCatalogCode(unreadableReasonCode, 'unreadableReasonCode');
    }
    return DocumentMeta._(
      id: checkedId,
      title: checkedTitle,
      createdAt: created,
      updatedAt: updated,
      source: source,
      latestRevisionId: latestRevisionId,
      lastDurableAt: lastDurableAt,
      readable: readable,
      unreadableReasonCode: unreadableReasonCode,
    );
  }

  const DocumentMeta._({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.source,
    required this.latestRevisionId,
    required this.lastDurableAt,
    required this.readable,
    required this.unreadableReasonCode,
  });

  /// Reads a persisted metadata envelope.
  ///
  /// The `kind` discriminator must be `document`. Throws [FormatException] for
  /// missing, mistyped, or invalid fields.
  factory DocumentMeta.fromJson(Map<String, Object?> json) {
    if (json['kind'] != 'document') {
      throw const FormatException(
        'JSON field "kind" must be the document discriminator',
      );
    }
    final Object? latestRevisionId = json['latestRevisionId'];
    if (latestRevisionId != null && latestRevisionId is! String) {
      throw const FormatException(
        'JSON field "latestRevisionId" must be a string or null',
      );
    }
    final Object? rawLastDurableAt = json['lastDurableAt'];
    DateTime? lastDurableAt;
    if (rawLastDurableAt != null) {
      lastDurableAt = parseCanonicalUtcTimestamp(
        rawLastDurableAt,
        name: 'lastDurableAt',
      );
    }
    final Object? unreadableReasonCode = json['unreadableReasonCode'];
    if (unreadableReasonCode != null && unreadableReasonCode is! String) {
      throw const FormatException(
        'JSON field "unreadableReasonCode" must be a string or null',
      );
    }
    try {
      return DocumentMeta(
        id: _readString(json, 'id'),
        title: _readString(json, 'title'),
        createdAt: parseCanonicalUtcTimestamp(
          json['createdAt'],
          name: 'createdAt',
        ),
        updatedAt: parseCanonicalUtcTimestamp(
          json['updatedAt'],
          name: 'updatedAt',
        ),
        source: SourceFileRef.fromJson(_readObject(json, 'source')),
        latestRevisionId: latestRevisionId as String?,
        lastDurableAt: lastDurableAt,
        readable: _readBool(json, 'readable'),
        unreadableReasonCode: unreadableReasonCode as String?,
      );
    } on ArgumentError catch (error) {
      throw FormatException(
        'Invalid document metadata JSON: '
        '${error.message}',
      );
    }
  }

  /// The `document` discriminator.
  String get kind => 'document';

  /// UUIDv4 of the document.
  final String id;

  /// User-visible title, trimmed to 1–200 characters.
  final String title;

  /// Creation time in UTC.
  final DateTime createdAt;

  /// Last metadata update time in UTC.
  final DateTime updatedAt;

  /// The immutable encrypted source.
  final SourceFileRef source;

  /// The latest committed revision, or null before the initial commit.
  final String? latestRevisionId;

  /// When the latest revision was verified, or null before the initial commit.
  final DateTime? lastDurableAt;

  /// Whether the record and its source are currently readable.
  final bool readable;

  /// Catalog key explaining an unreadable record, or null when readable.
  final String? unreadableReasonCode;

  /// Returns a copy with the supplied fields replaced.
  ///
  /// [unreadableReasonCode] can be cleared by passing `null`; omitting it keeps
  /// the current value. The result is revalidated by the public constructor.
  DocumentMeta copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    SourceFileRef? source,
    Object? latestRevisionId = _unset,
    Object? lastDurableAt = _unset,
    bool? readable,
    Object? unreadableReasonCode = _unset,
  }) {
    return DocumentMeta(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source ?? this.source,
      latestRevisionId: identical(latestRevisionId, _unset)
          ? this.latestRevisionId
          : latestRevisionId as String?,
      lastDurableAt: identical(lastDurableAt, _unset)
          ? this.lastDurableAt
          : lastDurableAt as DateTime?,
      readable: readable ?? this.readable,
      unreadableReasonCode: identical(unreadableReasonCode, _unset)
          ? this.unreadableReasonCode
          : unreadableReasonCode as String?,
    );
  }

  /// Serializes the persisted metadata envelope.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'kind': kind,
      'title': title,
      'createdAt': canonicalUtcTimestamp(createdAt),
      'updatedAt': canonicalUtcTimestamp(updatedAt),
      'source': source.toJson(),
      'latestRevisionId': latestRevisionId,
      'lastDurableAt': lastDurableAt == null
          ? null
          : canonicalUtcTimestamp(lastDurableAt!),
      'readable': readable,
      'unreadableReasonCode': unreadableReasonCode,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is DocumentMeta &&
        other.id == id &&
        other.title == title &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.source == source &&
        other.latestRevisionId == latestRevisionId &&
        other.lastDurableAt == lastDurableAt &&
        other.readable == readable &&
        other.unreadableReasonCode == unreadableReasonCode;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      title,
      createdAt,
      updatedAt,
      source,
      latestRevisionId,
      lastDurableAt,
      readable,
      unreadableReasonCode,
    );
  }

  @override
  String toString() {
    return 'DocumentMeta(id: $id, readable: $readable)';
  }
}

/// The versioned document aggregate root (`data-model.md` §3.1).
///
/// The aggregate owns the page list, suggestions, confirmed fields, field
/// order, values, signatures, verification, the optional template pin, the
/// durable head, and the view preferences. It never mutates its
/// [SourceFileRef] and it never edits page content; the list read models are
/// derived elsewhere from [DocumentMeta].
final class Document {
  /// Creates a validated document aggregate.
  ///
  /// [schemaVersion] must be [documentSchemaVersion]. [id] must be a lowercase
  /// UUIDv4 and [title] is trimmed to 1–200 characters. [createdAt] and
  /// [updatedAt] must be UTC and [updatedAt] must not precede [createdAt].
  /// Pages must be exactly `0 … source.pageCount - 1` in order. Suggestions
  /// must reference existing pages, fit their display box, have unique ids, and
  /// carry symmetric same-page conflicts. Fields must have unique ids, fit
  /// their page, and be a permutation of [fieldOrder] whose `order` equals the
  /// field's position. Values exist only for fields and must be compatible or
  /// flagged `incompatible_content`; signatures exist only for signature
  /// fields on the same page; verification entries exist only for fields.
  ///
  /// [status] is transient. When omitted, an unreadable source yields
  /// [DocumentStatus.unreadable] and every other new aggregate yields
  /// [DocumentStatus.draft]; [Document.fromJson] restores a loaded document as
  /// [DocumentStatus.saved]. [DocumentStatus.deleted] is rejected because a
  /// deleted document has no live aggregate.
  ///
  /// Throws [ArgumentError] for every invalid value. The error never echoes
  /// document content.
  factory Document({
    required String id,
    required String title,
    required DateTime createdAt,
    required DateTime updatedAt,
    required SourceFileRef source,
    required Iterable<Page> pages,
    Iterable<FieldSuggestion> suggestions = const <FieldSuggestion>[],
    Iterable<ConfirmedField> fields = const <ConfirmedField>[],
    required Iterable<String> fieldOrder,
    Map<String, FieldValue> values = const <String, FieldValue>{},
    Map<String, SignatureMark> signatures = const <String, SignatureMark>{},
    Map<String, FieldVerification> verification =
        const <String, FieldVerification>{},
    TemplateOrigin? templateOrigin,
    required DurablePointer lastDurable,
    DocumentPreferences? preferences,
    DocumentStatus? status,
    int schemaVersion = documentSchemaVersion,
  }) {
    if (schemaVersion != documentSchemaVersion) {
      throw ArgumentError('schemaVersion must be $documentSchemaVersion');
    }
    final String checkedId = _validateUuidV4(id, 'id');
    final String checkedTitle = _normalizeTitle(title);
    final DateTime created = _checkUtc(createdAt, 'createdAt');
    final DateTime updated = _checkUtc(updatedAt, 'updatedAt');

    final List<Page> pageList = pages.toList(growable: false);
    if (pageList.isEmpty) {
      throw ArgumentError('pages must contain at least one page');
    }
    if (pageList.length != source.pageCount) {
      throw ArgumentError('pages.length must equal source.pageCount');
    }
    for (int index = 0; index < pageList.length; index++) {
      if (pageList[index].index != index) {
        throw ArgumentError('pages must be ordered contiguously from index 0');
      }
    }

    final List<FieldSuggestion> suggestionList = suggestions.toList(
      growable: false,
    )..sort(_compareSuggestions);
    final Map<String, FieldSuggestion> suggestionById =
        <String, FieldSuggestion>{};
    for (final FieldSuggestion suggestion in suggestionList) {
      if (suggestionById.containsKey(suggestion.id)) {
        throw ArgumentError('suggestion ids must be unique');
      }
      suggestionById[suggestion.id] = suggestion;
      if (suggestion.pageIndex >= pageList.length) {
        throw ArgumentError('a suggestion references a missing page');
      }
      if (!suggestion.fitsWithinPage(
        pageList[suggestion.pageIndex].geometry.displaySize,
      )) {
        throw ArgumentError('a suggestion lies outside its page display box');
      }
    }
    for (final FieldSuggestion suggestion in suggestionList) {
      for (final String conflictId in suggestion.conflictsWith) {
        final FieldSuggestion? conflict = suggestionById[conflictId];
        if (conflict == null) {
          throw ArgumentError(
            'conflictsWith must reference a suggestion in the document',
          );
        }
        if (!conflict.conflictsWith.contains(suggestion.id)) {
          throw ArgumentError('suggestion conflicts must be symmetric');
        }
      }
    }

    final List<ConfirmedField> suppliedFields = fields.toList(growable: false);
    final Map<String, ConfirmedField> fieldById = <String, ConfirmedField>{};
    for (final ConfirmedField field in suppliedFields) {
      if (fieldById.containsKey(field.id)) {
        throw ArgumentError('confirmed field ids must be unique');
      }
      fieldById[field.id] = field;
      if (field.pageIndex >= pageList.length) {
        throw ArgumentError('a confirmed field references a missing page');
      }
      if (!field.fitsWithinPage(
        pageList[field.pageIndex].geometry.displaySize,
      )) {
        throw ArgumentError(
          'a confirmed field lies outside its page display box',
        );
      }
    }

    final List<String> suppliedOrder = fieldOrder.toList(growable: false);
    if (suppliedOrder.length != fieldById.length) {
      throw ArgumentError(
        'fieldOrder must contain every confirmed field exactly once',
      );
    }
    if (suppliedOrder.toSet().length != suppliedOrder.length) {
      throw ArgumentError('fieldOrder must not contain duplicate ids');
    }
    for (int index = 0; index < suppliedOrder.length; index++) {
      final ConfirmedField? field = fieldById[suppliedOrder[index]];
      if (field == null) {
        throw ArgumentError('fieldOrder references an unknown field id');
      }
      if (field.order != index) {
        throw ArgumentError(
          'field.order must equal the field position in fieldOrder',
        );
      }
    }
    final List<ConfirmedField> orderedFields = <ConfirmedField>[
      for (final String fieldId in suppliedOrder) fieldById[fieldId]!,
    ];

    final Map<String, FieldValue> valueMap = Map<String, FieldValue>.from(
      values,
    );
    for (final MapEntry<String, FieldValue> entry in valueMap.entries) {
      final ConfirmedField? field = fieldById[entry.key];
      if (field == null) {
        throw ArgumentError('a value references an unknown confirmed field');
      }
      final FieldValue value = entry.value;
      if (!field.acceptsValue(value)) {
        throw ArgumentError('a value is incompatible with its field type');
      }
      final bool isIncompatible = value is IncompatibleValue;
      final bool flaggedIncompatible =
          field.validation.isWarning &&
          field.validation.warningCode == WarningCode.incompatibleContent;
      if (isIncompatible != flaggedIncompatible) {
        throw ArgumentError(
          'incompatible content and its incompatible_content warning must '
          'occur together',
        );
      }
    }

    final Map<String, SignatureMark> signatureMap =
        Map<String, SignatureMark>.from(signatures);
    final Set<String> signatureAssetIds = <String>{};
    for (final MapEntry<String, SignatureMark> entry in signatureMap.entries) {
      final ConfirmedField? field = fieldById[entry.key];
      if (field == null) {
        throw ArgumentError('a signature references an unknown field');
      }
      final SignatureMark mark = entry.value;
      if (!mark.describesField(field)) {
        throw ArgumentError(
          'a signature must belong to a signature field on the same page',
        );
      }
      if (!signatureAssetIds.add(mark.assetId)) {
        throw ArgumentError('signature asset ids must be unique');
      }
      final FieldValue? value = valueMap[entry.key];
      if (value is! SignatureValue || value.signatureAssetId != mark.assetId) {
        throw ArgumentError(
          'a signature mark requires the matching signature value',
        );
      }
    }
    for (final ConfirmedField field in orderedFields) {
      final FieldValue? value = valueMap[field.id];
      if (value is SignatureValue) {
        final SignatureMark? mark = signatureMap[field.id];
        if (mark == null || mark.assetId != value.signatureAssetId) {
          throw ArgumentError(
            'a signature value requires the matching signature mark',
          );
        }
      }
    }

    for (final String fieldId in verification.keys) {
      if (!fieldById.containsKey(fieldId)) {
        throw ArgumentError('verification references an unknown field');
      }
    }

    final DocumentPreferences checkedPreferences =
        preferences ?? DocumentPreferences();
    if (checkedPreferences.currentPage >= pageList.length) {
      throw ArgumentError('preferences.currentPage must reference a page');
    }

    final DocumentStatus resolvedStatus =
        status ??
        (source.integrity == SourceIntegrityState.unreadable
            ? DocumentStatus.unreadable
            : DocumentStatus.draft);
    if (resolvedStatus == DocumentStatus.deleted) {
      throw ArgumentError('a deleted document has no live aggregate');
    }
    final bool sourceUnreadable =
        source.integrity == SourceIntegrityState.unreadable;
    if (resolvedStatus == DocumentStatus.unreadable && !sourceUnreadable) {
      throw ArgumentError('status unreadable requires an unreadable source');
    }
    if (sourceUnreadable && resolvedStatus != DocumentStatus.unreadable) {
      throw ArgumentError(
        'an unreadable source requires the unreadable status',
      );
    }

    return Document._(
      schemaVersion: schemaVersion,
      id: checkedId,
      title: checkedTitle,
      createdAt: created,
      updatedAt: updated,
      source: source,
      pages: List<Page>.unmodifiable(pageList),
      suggestions: List<FieldSuggestion>.unmodifiable(suggestionList),
      fields: List<ConfirmedField>.unmodifiable(orderedFields),
      fieldOrder: List<String>.unmodifiable(suppliedOrder),
      values: Map<String, FieldValue>.unmodifiable(valueMap),
      signatures: Map<String, SignatureMark>.unmodifiable(signatureMap),
      verification: Map<String, FieldVerification>.unmodifiable(verification),
      templateOrigin: templateOrigin,
      lastDurable: lastDurable,
      preferences: checkedPreferences,
      status: resolvedStatus,
    );
  }

  const Document._({
    required this.schemaVersion,
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.source,
    required this.pages,
    required this.suggestions,
    required this.fields,
    required this.fieldOrder,
    required this.values,
    required this.signatures,
    required this.verification,
    required this.templateOrigin,
    required this.lastDurable,
    required this.preferences,
    required this.status,
  });

  /// Reads a persisted document aggregate.
  ///
  /// Only [documentSchemaVersion] is accepted; a higher version fails closed
  /// so the caller can refuse to save without data loss (FR-044). [status] is
  /// transient and never read from JSON; it defaults to the safe derived state.
  ///
  /// Throws [FormatException] for missing, mistyped, invalid, or unsupported
  /// fields.
  factory Document.fromJson(
    Map<String, Object?> json, {
    DocumentStatus? status,
  }) {
    final Object? rawSchemaVersion = json['schemaVersion'];
    if (rawSchemaVersion is! int) {
      throw const FormatException(
        'JSON field "schemaVersion" must be an integer',
      );
    }
    if (rawSchemaVersion != documentSchemaVersion) {
      throw FormatException(
        'Unsupported document schema version $rawSchemaVersion',
      );
    }
    if (json['kind'] != 'document') {
      throw const FormatException(
        'JSON field "kind" must be the document discriminator',
      );
    }
    try {
      final SourceFileRef source = SourceFileRef.fromJson(
        _readObject(json, 'source'),
      );
      return Document(
        schemaVersion: rawSchemaVersion,
        id: _readString(json, 'id'),
        title: _readString(json, 'title'),
        createdAt: parseCanonicalUtcTimestamp(
          json['createdAt'],
          name: 'createdAt',
        ),
        updatedAt: parseCanonicalUtcTimestamp(
          json['updatedAt'],
          name: 'updatedAt',
        ),
        source: source,
        pages: _readObjectList(
          json,
          'pages',
        ).map(Page.fromJson).toList(growable: false),
        suggestions: _readObjectList(
          json,
          'suggestions',
        ).map(FieldSuggestion.fromJson).toList(growable: false),
        fields: _readObjectList(
          json,
          'fields',
        ).map(ConfirmedField.fromJson).toList(growable: false),
        fieldOrder: _readStringList(json, 'fieldOrder'),
        values: _readObjectMap(json, 'values').map(
          (String key, Map<String, Object?> value) =>
              MapEntry<String, FieldValue>(key, FieldValue.fromJson(value)),
        ),
        signatures: _readObjectMap(json, 'signatures').map(
          (String key, Map<String, Object?> value) =>
              MapEntry<String, SignatureMark>(
                key,
                SignatureMark.fromJson(value),
              ),
        ),
        verification: _readObjectMap(json, 'verification').map(
          (String key, Map<String, Object?> value) =>
              MapEntry<String, FieldVerification>(
                key,
                FieldVerification.fromJson(value),
              ),
        ),
        templateOrigin: json['templateOrigin'] == null
            ? null
            : TemplateOrigin.fromJson(_readObject(json, 'templateOrigin')),
        lastDurable: DurablePointer.fromJson(_readObject(json, 'lastDurable')),
        preferences: DocumentPreferences.fromJson(
          _readObject(json, 'preferences'),
        ),
        status:
            status ??
            (source.integrity == SourceIntegrityState.unreadable
                ? DocumentStatus.unreadable
                : DocumentStatus.saved),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid document JSON: ${error.message}');
    }
  }

  /// The document schema version.
  final int schemaVersion;

  /// The `document` discriminator.
  String get kind => 'document';

  /// UUIDv4 of the document.
  final String id;

  /// User-visible title, trimmed to 1–200 characters.
  final String title;

  /// Creation time in UTC.
  final DateTime createdAt;

  /// Last change time in UTC.
  final DateTime updatedAt;

  /// The immutable encrypted source.
  final SourceFileRef source;

  /// The pages, ordered contiguously from index 0.
  final List<Page> pages;

  /// Machine suggestions, in canonical page/ordinal order.
  final List<FieldSuggestion> suggestions;

  /// Confirmed fields, in [fieldOrder] order.
  final List<ConfirmedField> fields;

  /// Confirmed field ids in user-visible order.
  final List<String> fieldOrder;

  /// Committed values keyed by confirmed field id.
  final Map<String, FieldValue> values;

  /// Signature marks keyed by signature field id.
  final Map<String, SignatureMark> signatures;

  /// Review state keyed by confirmed field id.
  final Map<String, FieldVerification> verification;

  /// The immutable template version pin, or null for an un-derived document.
  final TemplateOrigin? templateOrigin;

  /// The verified durable head.
  final DurablePointer lastDurable;

  /// View preferences.
  final DocumentPreferences preferences;

  /// The transient lifecycle state; never persisted.
  final DocumentStatus status;

  /// Returns a copy with the supplied fields replaced.
  ///
  /// The caller must supply a consistent combination (for example, fields and
  /// fieldOrder together) because the public constructor revalidates every
  /// invariant. [templateOrigin] can be cleared by passing `null`; omitting it
  /// keeps the current value.
  Document copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    SourceFileRef? source,
    Iterable<Page>? pages,
    Iterable<FieldSuggestion>? suggestions,
    Iterable<ConfirmedField>? fields,
    Iterable<String>? fieldOrder,
    Map<String, FieldValue>? values,
    Map<String, SignatureMark>? signatures,
    Map<String, FieldVerification>? verification,
    Object? templateOrigin = _unset,
    DurablePointer? lastDurable,
    DocumentPreferences? preferences,
    DocumentStatus? status,
    int? schemaVersion,
  }) {
    return Document(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source ?? this.source,
      pages: pages ?? this.pages,
      suggestions: suggestions ?? this.suggestions,
      fields: fields ?? this.fields,
      fieldOrder: fieldOrder ?? this.fieldOrder,
      values: values ?? this.values,
      signatures: signatures ?? this.signatures,
      verification: verification ?? this.verification,
      templateOrigin: identical(templateOrigin, _unset)
          ? this.templateOrigin
          : templateOrigin as TemplateOrigin?,
      lastDurable: lastDurable ?? this.lastDurable,
      preferences: preferences ?? this.preferences,
      status: status ?? this.status,
    );
  }

  /// Serializes the persisted aggregate fields.
  ///
  /// The transient [status] is deliberately omitted. Use
  /// [canonicalJsonEncode] on this map for the canonical byte form.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'id': id,
      'kind': kind,
      'title': title,
      'createdAt': canonicalUtcTimestamp(createdAt),
      'updatedAt': canonicalUtcTimestamp(updatedAt),
      'source': source.toJson(),
      'pages': <Map<String, Object?>>[
        for (final Page page in pages) page.toJson(),
      ],
      'suggestions': <Map<String, Object?>>[
        for (final FieldSuggestion suggestion in suggestions)
          suggestion.toJson(),
      ],
      'fields': <Map<String, Object?>>[
        for (final ConfirmedField field in fields) field.toJson(),
      ],
      'fieldOrder': List<String>.unmodifiable(fieldOrder),
      'values': <String, Object?>{
        for (final MapEntry<String, FieldValue> entry in values.entries)
          entry.key: entry.value.toJson(),
      },
      'signatures': <String, Object?>{
        for (final MapEntry<String, SignatureMark> entry in signatures.entries)
          entry.key: entry.value.toJson(),
      },
      'verification': <String, Object?>{
        for (final MapEntry<String, FieldVerification> entry
            in verification.entries)
          entry.key: entry.value.toJson(),
      },
      'templateOrigin': templateOrigin?.toJson(),
      'lastDurable': lastDurable.toJson(),
      'preferences': preferences.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is Document &&
        other.schemaVersion == schemaVersion &&
        other.id == id &&
        other.title == title &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.source == source &&
        _listsEqual<Page>(other.pages, pages) &&
        _listsEqual<FieldSuggestion>(other.suggestions, suggestions) &&
        _listsEqual<ConfirmedField>(other.fields, fields) &&
        _listsEqual<String>(other.fieldOrder, fieldOrder) &&
        _mapsEqual<String, FieldValue>(other.values, values) &&
        _mapsEqual<String, SignatureMark>(other.signatures, signatures) &&
        _mapsEqual<String, FieldVerification>(
          other.verification,
          verification,
        ) &&
        other.templateOrigin == templateOrigin &&
        other.lastDurable == lastDurable &&
        other.preferences == preferences &&
        other.status == status;
  }

  @override
  int get hashCode {
    return Object.hash(
      schemaVersion,
      id,
      title,
      createdAt,
      updatedAt,
      source,
      Object.hashAll(pages),
      Object.hashAll(suggestions),
      Object.hashAll(fields),
      Object.hashAll(fieldOrder),
      Object.hashAll(values.entries),
      Object.hashAll(signatures.entries),
      Object.hashAll(verification.entries),
      templateOrigin,
      lastDurable,
      preferences,
      status,
    );
  }

  @override
  String toString() {
    return 'Document(id: $id, pages: ${pages.length}, '
        'fields: ${fields.length}, status: ${status.name})';
  }
}

/// Compares suggestions by page, then ordinal, then id for the canonical list
/// order required by `data-model.md` §7.
int _compareSuggestions(FieldSuggestion a, FieldSuggestion b) {
  final int byPage = a.pageIndex.compareTo(b.pageIndex);
  if (byPage != 0) {
    return byPage;
  }
  final int byOrdinal = _suggestionOrdinal(a.id)
      .compareTo(_suggestionOrdinal(b.id));
  if (byOrdinal != 0) {
    return byOrdinal;
  }
  return a.id.compareTo(b.id);
}

int _suggestionOrdinal(String id) {
  final int separator = id.lastIndexOf('_');
  return int.parse(id.substring(separator + 1));
}

/// Sentinel used by `copyWith` to distinguish "not supplied" from an explicit
/// `null`.
const Object _unset = Object();

final RegExp _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
final RegExp _catalogCodePattern = RegExp(r'^[A-Z]{2,6}-[0-9]{3}$');
final RegExp _renderCacheKeyPattern = RegExp(r'^[\x21-\x7E]{1,256}$');

String _normalizeTitle(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError('title must not be empty');
  }
  if (trimmed.runes.length > 200) {
    throw ArgumentError('title must be at most 200 characters');
  }
  _checkNoControlCharacters(trimmed, 'title');
  return trimmed;
}

String? _normalizeOriginalName(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (trimmed.runes.length > 255) {
    throw ArgumentError('originalName must be at most 255 characters');
  }
  _checkNoControlCharacters(trimmed, 'originalName');
  return trimmed;
}

void _checkNoControlCharacters(String value, String name) {
  for (final int rune in value.runes) {
    if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) {
      throw ArgumentError('$name must not contain control characters');
    }
  }
}

void _validateRenderCacheKey(String value) {
  if (!_renderCacheKeyPattern.hasMatch(value)) {
    throw ArgumentError(
      'renderCacheKey must be a printable ASCII machine token',
    );
  }
}

String _validateUuidV4(String value, String name) {
  if (!_uuidV4Pattern.hasMatch(value)) {
    throw ArgumentError('$name must be a lowercase UUIDv4');
  }
  return value;
}

String _validateSha256(String value, String name) {
  if (!_sha256Pattern.hasMatch(value)) {
    throw ArgumentError('$name must be 64 lowercase hexadecimal characters');
  }
  return value;
}

void _validateCatalogCode(String value, String name) {
  if (!_catalogCodePattern.hasMatch(value)) {
    throw ArgumentError('$name must be a catalog code such as SAVE-002');
  }
}

DateTime _checkUtc(DateTime value, String name) {
  if (!value.isUtc) {
    throw ArgumentError('$name must be UTC');
  }
  return value;
}

bool _listsEqual<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int index = 0; index < a.length; index++) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

bool _mapsEqual<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final MapEntry<K, V> entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

Map<String, Object?> _readObject(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('JSON field "$key" must be an object');
  }
  return value;
}

List<Map<String, Object?>> _readObjectList(
  Map<String, Object?> json,
  String key,
) {
  final Object? value = json[key];
  if (value is! List<Object?>) {
    throw FormatException('JSON field "$key" must be an array');
  }
  final List<Map<String, Object?>> result = <Map<String, Object?>>[];
  for (final Object? item in value) {
    if (item is! Map<String, Object?>) {
      throw FormatException('JSON field "$key" must contain only objects');
    }
    result.add(item);
  }
  return result;
}

Map<String, Map<String, Object?>> _readObjectMap(
  Map<String, Object?> json,
  String key,
) {
  final Object? value = json[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('JSON field "$key" must be an object');
  }
  final Map<String, Map<String, Object?>> result =
      <String, Map<String, Object?>>{};
  for (final MapEntry<String, Object?> entry in value.entries) {
    final Object? item = entry.value;
    if (item is! Map<String, Object?>) {
      throw FormatException('JSON field "$key" must contain only objects');
    }
    result[entry.key] = item;
  }
  return result;
}

String _readString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String) {
    throw FormatException('JSON field "$key" must be a string');
  }
  return value;
}

int _readInt(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! int) {
    throw FormatException('JSON field "$key" must be an integer');
  }
  return value;
}

bool _readBool(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! bool) {
    throw FormatException('JSON field "$key" must be a boolean');
  }
  return value;
}

List<String> _readStringList(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! List<Object?>) {
    throw FormatException('JSON field "$key" must be an array');
  }
  final List<String> result = <String>[];
  for (final Object? item in value) {
    if (item is! String) {
      throw FormatException('JSON field "$key" must contain only strings');
    }
    result.add(item);
  }
  return result;
}
