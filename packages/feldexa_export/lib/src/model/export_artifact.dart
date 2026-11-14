// Feldexa export-attempt artifact and verification model (T022).
//
// Owner: `packages/feldexa_export/lib/src/model/export_artifact.dart` (T022).
// Normative sources:
//   * `data-model.md` §3.15 — `ExportArtifact` fields, the `ArtifactVerification`
//     record, and the export state machine;
//   * `contracts/export-plan.md` §1, §4, §5, and §6 — no artifact before
//     verification succeeds, failure deletes the temp file, and verification
//     checks page count, media boxes, glyphs, interactive fields, and overlay
//     bounds;
//   * `contracts/ports.md` §1 and §2.5 — the canonical `ExportArtifact` and
//     `ArtifactVerification` types returned by `PdfExportPort.export`;
//   * `spec.md` FR-069, FR-070, and FR-072 — a failed, interrupted, or partial
//     export is never presented as a successful one and never occupies the
//     successful artifact location.
//
// The state machine below is deliberately strict. A caller can only create an
// artifact in `validating` and advance it through `rendering` and `verifying`.
// `succeeded` requires a complete, all-passing verification record plus a
// positive byte size and a SHA-256; `failed` requires a catalog failure code
// and can never carry output bytes or a hash. There is no shortcut from
// `validating` to `succeeded`, so an optimistic success cannot be represented.
//
// `data-model.md` §3.15 names `blocked` in the state diagram for a validation
// outcome that produces no artifact. When an attempt record exists, that
// outcome is the terminal `failed` state with one of the blocking `EXP-001`,
// `EXP-003`, `EXP-004`, `EXP-005`, or `EXP-006` codes; [ExportArtifact.isBlocked]
// exposes that distinction without inventing an additional persisted state.
//
// Every model is immutable and validates in release mode. Unknown same-schema
// JSON fields are retained (`data-model.md` §6).
library;

import 'package:feldexa_core/feldexa_core.dart';

/// The maximum accepted source page count (`data-model.md` §3.2).
const int _maxArtifactPageCount = 100;

/// Failure codes that mean the attempt was blocked before an artifact existed.
///
/// A blocked attempt has no successful-location file (`contracts/export-plan.md`
/// §4); `EXP-002` and `SAVE-001` are failures rather than preflight blocks.
const Set<String> exportArtifactBlockedFailureCodes = <String>{
  'EXP-001',
  'EXP-003',
  'EXP-004',
  'EXP-005',
  'EXP-006',
};

const Set<String> _verificationJsonKeys = <String>{
  'pageCountMatches',
  'mediaBoxesMatch',
  'fontGlyphsPresent',
  'noInteractiveFields',
  'overlayBoundsWithinPage',
  'checkedAt',
};

const Set<String> _artifactJsonKeys = <String>{
  'id',
  'documentId',
  'revisionId',
  'state',
  'pageCount',
  'byteSize',
  'sha256',
  'verification',
  'failureCode',
  'createdAt',
};

final RegExp _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
final RegExp _failureCodePattern = RegExp(r'^[A-Z][A-Z0-9]*-[0-9]{3}$');

/// The transient export-attempt state (`data-model.md` §3.15).
///
/// `succeeded` is reachable only from `verifying` and only with an all-passing
/// [ArtifactVerification]. `deleted` is reachable only from `succeeded` after
/// preview delivery or dismissal. `failed` and `deleted` are terminal; the
/// diagram's `blocked` outcome is represented by a `failed` artifact with a
/// blocking `EXP-*` code (see `exportArtifactBlockedFailureCodes`).
enum ExportArtifactState {
  /// Plan validation is running; no output exists.
  validating('validating'),

  /// PDF rendering is running; output is a temp file only.
  rendering('rendering'),

  /// The output is being reopened and checked; not success yet.
  verifying('verifying'),

  /// All verification checks passed; a preview is available.
  succeeded('succeeded'),

  /// The attempt failed or was blocked; no success-location file remains.
  failed('failed'),

  /// A succeeded artifact was delivered/dismissed and the preview was removed.
  deleted('deleted');

  const ExportArtifactState(this.wireName);

  /// Stable JSON token.
  final String wireName;

  /// Parses a JSON token.
  ///
  /// Throws [FormatException] for a non-string or unknown token.
  static ExportArtifactState fromWire(Object? token) {
    if (token is String) {
      for (final ExportArtifactState state in values) {
        if (state.wireName == token) {
          return state;
        }
      }
    }
    throw const FormatException('Unknown export artifact state token');
  }
}

/// The canonical export verification record (`data-model.md` §3.15).
///
/// All five checks must pass before an artifact may enter `succeeded`; the
/// individual booleans are retained so a failed verification can report which
/// check failed. [checkedAt] is UTC and never precedes the artifact creation.
final class ArtifactVerification extends JsonObject {
  /// Creates a verification record.
  ///
  /// [checkedAt] must be UTC.
  ///
  /// Throws [ArgumentError] for a local timestamp.
  factory ArtifactVerification({
    required bool pageCountMatches,
    required bool mediaBoxesMatch,
    required bool fontGlyphsPresent,
    required bool noInteractiveFields,
    required bool overlayBoundsWithinPage,
    required DateTime checkedAt,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    _checkUtc(checkedAt, 'checkedAt');
    return ArtifactVerification._(
      pageCountMatches: pageCountMatches,
      mediaBoxesMatch: mediaBoxesMatch,
      fontGlyphsPresent: fontGlyphsPresent,
      noInteractiveFields: noInteractiveFields,
      overlayBoundsWithinPage: overlayBoundsWithinPage,
      checkedAt: checkedAt,
      unknownFields: freezeUnknownJsonFields(unknownFields),
    );
  }

  const ArtifactVerification._({
    required this.pageCountMatches,
    required this.mediaBoxesMatch,
    required this.fontGlyphsPresent,
    required this.noInteractiveFields,
    required this.overlayBoundsWithinPage,
    required this.checkedAt,
    required super.unknownFields,
  });

  /// Reads a verification record.
  ///
  /// Throws [FormatException] for missing, mistyped, or invalid fields.
  factory ArtifactVerification.fromJson(Map<String, Object?> json) {
    try {
      return ArtifactVerification(
        pageCountMatches: _readBool(json, 'pageCountMatches'),
        mediaBoxesMatch: _readBool(json, 'mediaBoxesMatch'),
        fontGlyphsPresent: _readBool(json, 'fontGlyphsPresent'),
        noInteractiveFields: _readBool(json, 'noInteractiveFields'),
        overlayBoundsWithinPage: _readBool(json, 'overlayBoundsWithinPage'),
        checkedAt: parseCanonicalUtcTimestamp(
          json['checkedAt'],
          name: 'checkedAt',
        ),
        unknownFields: unknownJsonFields(json, _verificationJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException(
        'Invalid artifact verification JSON: ${error.message}',
      );
    }
  }

  /// Page count and order match the source and plan.
  final bool pageCountMatches;

  /// MediaBox/CropBox/rotation match the plan within tolerance.
  final bool mediaBoxesMatch;

  /// Every planned glyph is present in the embedded font.
  final bool fontGlyphsPresent;

  /// No AcroForm fields or widget annotations remain.
  final bool noInteractiveFields;

  /// Every overlay rect lies inside the page display box.
  final bool overlayBoundsWithinPage;

  /// Verification time in UTC.
  final DateTime checkedAt;

  /// Whether every required check passed.
  bool get allChecksPassed {
    return pageCountMatches &&
        mediaBoxesMatch &&
        fontGlyphsPresent &&
        noInteractiveFields &&
        overlayBoundsWithinPage;
  }

  /// Serializes the verification record.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'pageCountMatches': pageCountMatches,
      'mediaBoxesMatch': mediaBoxesMatch,
      'fontGlyphsPresent': fontGlyphsPresent,
      'noInteractiveFields': noInteractiveFields,
      'overlayBoundsWithinPage': overlayBoundsWithinPage,
      'checkedAt': canonicalUtcTimestamp(checkedAt),
    });
  }

  @override
  bool operator ==(Object other) {
    return other is ArtifactVerification &&
        other.pageCountMatches == pageCountMatches &&
        other.mediaBoxesMatch == mediaBoxesMatch &&
        other.fontGlyphsPresent == fontGlyphsPresent &&
        other.noInteractiveFields == noInteractiveFields &&
        other.overlayBoundsWithinPage == overlayBoundsWithinPage &&
        other.checkedAt == checkedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      pageCountMatches,
      mediaBoxesMatch,
      fontGlyphsPresent,
      noInteractiveFields,
      overlayBoundsWithinPage,
      checkedAt,
    );
  }

  @override
  String toString() =>
      'ArtifactVerification(allChecksPassed: $allChecksPassed)';
}

/// One export attempt (`data-model.md` §3.15).
///
/// An artifact starts in [ExportArtifactState.validating]. The only legal
/// transitions are:
///
/// ```text
/// validating --startRendering--> rendering
/// rendering  --startVerification--> verifying
/// validating/rendering/verifying --fail--> failed
/// verifying  --succeed (all checks pass)--> succeeded
/// succeeded  --markDeleted--> deleted
/// ```
///
/// There is no path from `validating` or `rendering` to `succeeded`, and a
/// `failed` artifact cannot carry output bytes, a hash, or a preview. The
/// constructor-like [start] factory is the only way to create a fresh attempt;
/// [fromJson] restores a previously valid record.
final class ExportArtifact extends JsonObject {
  /// Starts a new attempt in [ExportArtifactState.validating].
  ///
  /// [id], [documentId], and [revisionId] must be lowercase UUIDv4 values.
  /// [pageCount] must be between 1 and 100 and [createdAt] must be UTC.
  ///
  /// Throws [ArgumentError] for every invalid value.
  factory ExportArtifact.start({
    required String id,
    required String documentId,
    required String revisionId,
    required int pageCount,
    required DateTime createdAt,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    return _checked(
      id: id,
      documentId: documentId,
      revisionId: revisionId,
      state: ExportArtifactState.validating,
      pageCount: pageCount,
      byteSize: null,
      sha256: null,
      verification: null,
      failureCode: null,
      createdAt: createdAt,
      unknownFields: unknownFields,
    );
  }

  const ExportArtifact._({
    required this.id,
    required this.documentId,
    required this.revisionId,
    required this.state,
    required this.pageCount,
    required this.byteSize,
    required this.sha256,
    required this.verification,
    required this.failureCode,
    required this.createdAt,
    required super.unknownFields,
  });

  /// Reads a previously valid artifact record.
  ///
  /// The same state invariants as the transitions are enforced, so a
  /// hand-written `succeeded` record without an all-passing verification is
  /// refused. Throws [FormatException] for missing, mistyped, or invalid
  /// fields.
  factory ExportArtifact.fromJson(Map<String, Object?> json) {
    try {
      final Object? rawPageCount = json['pageCount'];
      final Object? rawByteSize = json['byteSize'];
      final Object? rawSha256 = json['sha256'];
      final Object? rawVerification = json['verification'];
      final Object? rawFailureCode = json['failureCode'];
      return _checked(
        id: _readNonEmptyString(json, 'id'),
        documentId: _readNonEmptyString(json, 'documentId'),
        revisionId: _readNonEmptyString(json, 'revisionId'),
        state: ExportArtifactState.fromWire(json['state']),
        pageCount: rawPageCount == null
            ? null
            : _asInt(rawPageCount, 'pageCount'),
        byteSize: rawByteSize == null ? null : _asInt(rawByteSize, 'byteSize'),
        sha256: rawSha256 == null ? null : _asString(rawSha256, 'sha256'),
        verification: rawVerification == null
            ? null
            : ArtifactVerification.fromJson(
                _asObject(rawVerification, 'verification'),
              ),
        failureCode: rawFailureCode == null
            ? null
            : _asString(rawFailureCode, 'failureCode'),
        createdAt: parseCanonicalUtcTimestamp(
          json['createdAt'],
          name: 'createdAt',
        ),
        unknownFields: unknownJsonFields(json, _artifactJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid export artifact JSON: ${error.message}');
    }
  }

  /// UUIDv4 of this attempt.
  final String id;

  /// Parent document UUIDv4.
  final String documentId;

  /// Exported revision UUIDv4.
  final String revisionId;

  /// Current state; see the class documentation for the legal transitions.
  final ExportArtifactState state;

  /// Source/plan page count, compared before success.
  final int? pageCount;

  /// Output byte size; positive only after success.
  final int? byteSize;

  /// Output SHA-256; present only after success.
  final String? sha256;

  /// Verification record; present after verification ran (or after success).
  final ArtifactVerification? verification;

  /// Catalog failure code such as `EXP-002` or `SAVE-001`.
  final String? failureCode;

  /// Attempt creation time in UTC.
  final DateTime createdAt;

  /// Whether a verified preview is available.
  bool get isPreviewAvailable => state == ExportArtifactState.succeeded;

  /// Whether no further transition is possible.
  bool get isTerminal {
    return state == ExportArtifactState.failed ||
        state == ExportArtifactState.deleted;
  }

  /// Whether the attempt failed with a blocking preflight code.
  ///
  /// This is the `blocked` outcome from the `data-model.md` §3.15 diagram;
  /// no artifact exists in the successful location.
  bool get isBlocked {
    final String? code = failureCode;
    return state == ExportArtifactState.failed &&
        code != null &&
        exportArtifactBlockedFailureCodes.contains(code);
  }

  /// Advances `validating` to `rendering`.
  ///
  /// Throws [StateError] from any other state.
  ExportArtifact startRendering() {
    _requireState(ExportArtifactState.validating, 'startRendering');
    return _copy(state: ExportArtifactState.rendering);
  }

  /// Advances `rendering` to `verifying`.
  ///
  /// Throws [StateError] from any other state.
  ExportArtifact startVerification() {
    _requireState(ExportArtifactState.rendering, 'startVerification');
    return _copy(state: ExportArtifactState.verifying);
  }

  /// Marks a verified attempt as succeeded.
  ///
  /// Only `verifying` can succeed. [verification] must pass every check,
  /// [byteSize] must be positive, [sha256] must be 64 lowercase hex
  /// characters, and the verification must not predate [createdAt].
  ///
  /// Throws [StateError] from another state and [ArgumentError] for an
  /// incomplete success claim. This is the only path to `succeeded`.
  ExportArtifact succeed({
    required int byteSize,
    required String sha256,
    required ArtifactVerification verification,
  }) {
    _requireState(ExportArtifactState.verifying, 'succeed');
    return _copy(
      state: ExportArtifactState.succeeded,
      byteSize: byteSize,
      sha256: sha256,
      verification: verification,
    );
  }

  /// Marks the attempt failed or blocked.
  ///
  /// Allowed from `validating`, `rendering`, or `verifying`. [failureCode] must
  /// be a catalog code. [verification] may be supplied only from `verifying`
  /// and only to record a failed re-open check. A failed attempt never carries
  /// output bytes or a hash.
  ///
  /// Throws [StateError] from a terminal or succeeded state and [ArgumentError]
  /// for an invalid code or verification placement.
  ExportArtifact fail({
    required String failureCode,
    ArtifactVerification? verification,
  }) {
    if (state != ExportArtifactState.validating &&
        state != ExportArtifactState.rendering &&
        state != ExportArtifactState.verifying) {
      throw StateError('fail is not allowed from ${state.wireName}');
    }
    if (verification != null && state != ExportArtifactState.verifying) {
      throw ArgumentError(
        'verification is only allowed when failing from verifying',
      );
    }
    return _copy(
      state: ExportArtifactState.failed,
      verification: verification,
      failureCode: failureCode,
      dropOutput: true,
    );
  }

  /// Removes the preview after delivery or dismissal.
  ///
  /// Allowed only from `succeeded`. Throws [StateError] from any other state.
  ExportArtifact markDeleted() {
    _requireState(ExportArtifactState.succeeded, 'markDeleted');
    return _copy(state: ExportArtifactState.deleted);
  }

  /// Serializes the attempt.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'id': id,
      'documentId': documentId,
      'revisionId': revisionId,
      'state': state.wireName,
      'pageCount': pageCount,
      'byteSize': byteSize,
      'sha256': sha256,
      'verification': verification?.toJson(),
      'failureCode': failureCode,
      'createdAt': canonicalUtcTimestamp(createdAt),
    });
  }

  ExportArtifact _copy({
    required ExportArtifactState state,
    int? byteSize,
    String? sha256,
    ArtifactVerification? verification,
    String? failureCode,
    bool dropOutput = false,
  }) {
    return _checked(
      id: id,
      documentId: documentId,
      revisionId: revisionId,
      state: state,
      pageCount: pageCount,
      byteSize: dropOutput ? null : (byteSize ?? this.byteSize),
      sha256: dropOutput ? null : (sha256 ?? this.sha256),
      verification: dropOutput
          ? verification
          : (verification ?? this.verification),
      failureCode: failureCode ?? this.failureCode,
      createdAt: createdAt,
      unknownFields: unknownFields,
    );
  }

  void _requireState(ExportArtifactState expected, String operation) {
    if (state != expected) {
      throw StateError('$operation is not allowed from ${state.wireName}');
    }
  }

  @override
  bool operator ==(Object other) {
    return other is ExportArtifact &&
        other.id == id &&
        other.documentId == documentId &&
        other.revisionId == revisionId &&
        other.state == state &&
        other.pageCount == pageCount &&
        other.byteSize == byteSize &&
        other.sha256 == sha256 &&
        other.verification == verification &&
        other.failureCode == failureCode &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      documentId,
      revisionId,
      state,
      pageCount,
      byteSize,
      sha256,
      verification,
      failureCode,
      createdAt,
    );
  }

  @override
  String toString() => 'ExportArtifact(state: ${state.wireName})';
}

ExportArtifact _checked({
  required String id,
  required String documentId,
  required String revisionId,
  required ExportArtifactState state,
  required int? pageCount,
  required int? byteSize,
  required String? sha256,
  required ArtifactVerification? verification,
  required String? failureCode,
  required DateTime createdAt,
  required Map<String, Object?> unknownFields,
}) {
  final String checkedId = _checkUuidV4(id, 'id');
  final String checkedDocumentId = _checkUuidV4(documentId, 'documentId');
  final String checkedRevisionId = _checkUuidV4(revisionId, 'revisionId');
  _checkUtc(createdAt, 'createdAt');
  if (state == ExportArtifactState.succeeded ||
      state == ExportArtifactState.deleted) {
    if (verification == null || !verification.allChecksPassed) {
      throw ArgumentError('succeeded requires an all-passing verification');
    }
    if (byteSize == null || byteSize <= 0) {
      throw ArgumentError('succeeded requires a positive byteSize');
    }
    if (sha256 == null) {
      throw ArgumentError('succeeded requires a sha256');
    }
    if (failureCode != null) {
      throw ArgumentError('a succeeded artifact cannot carry a failureCode');
    }
    if (pageCount == null) {
      throw ArgumentError('a succeeded artifact requires a pageCount');
    }
  }
  if (state == ExportArtifactState.failed) {
    if (failureCode == null) {
      throw ArgumentError('a failed artifact requires a failureCode');
    }
    if (byteSize != null || sha256 != null) {
      throw ArgumentError('a failed artifact cannot carry output bytes');
    }
  }
  if (state == ExportArtifactState.validating ||
      state == ExportArtifactState.rendering ||
      state == ExportArtifactState.verifying) {
    if (byteSize != null || sha256 != null) {
      throw ArgumentError('only a succeeded artifact may carry output bytes');
    }
    if (verification != null) {
      throw ArgumentError(
        'only a failed or succeeded artifact may carry verification',
      );
    }
    if (failureCode != null) {
      throw ArgumentError('an in-progress artifact cannot carry a failureCode');
    }
    if (pageCount == null) {
      throw ArgumentError('an in-progress artifact requires a pageCount');
    }
  }
  if (pageCount != null &&
      (pageCount < 1 || pageCount > _maxArtifactPageCount)) {
    throw ArgumentError(
      'pageCount must be between 1 and $_maxArtifactPageCount',
    );
  }
  if (byteSize != null && byteSize <= 0) {
    throw ArgumentError('byteSize must be positive');
  }
  final String? checkedSha256 = sha256 == null
      ? null
      : _checkSha256(sha256, 'sha256');
  final String? checkedFailureCode = failureCode == null
      ? null
      : _checkFailureCode(failureCode, 'failureCode');
  if (verification != null && verification.checkedAt.isBefore(createdAt)) {
    throw ArgumentError('verification must not predate artifact creation');
  }
  return ExportArtifact._(
    id: checkedId,
    documentId: checkedDocumentId,
    revisionId: checkedRevisionId,
    state: state,
    pageCount: pageCount,
    byteSize: byteSize,
    sha256: checkedSha256,
    verification: verification,
    failureCode: checkedFailureCode,
    createdAt: createdAt,
    unknownFields: freezeUnknownJsonFields(unknownFields),
  );
}

String _checkUuidV4(String value, String name) {
  if (!_uuidV4Pattern.hasMatch(value)) {
    throw ArgumentError('$name must be a lowercase UUIDv4');
  }
  return value;
}

String _checkSha256(String value, String name) {
  if (!_sha256Pattern.hasMatch(value)) {
    throw ArgumentError('$name must be 64 lowercase hex characters');
  }
  return value;
}

String _checkFailureCode(String value, String name) {
  if (!_failureCodePattern.hasMatch(value)) {
    throw ArgumentError('$name must be a catalog code such as EXP-001');
  }
  return value;
}

void _checkUtc(DateTime value, String name) {
  if (!value.isUtc) {
    throw ArgumentError('$name must be UTC');
  }
}

String _readNonEmptyString(Map<String, Object?> json, String name) {
  final Object? value = json[name];
  if (value is! String || value.isEmpty) {
    throw FormatException('JSON field "$name" must be a non-empty string');
  }
  return value;
}

bool _readBool(Map<String, Object?> json, String name) {
  final Object? value = json[name];
  if (value is! bool) {
    throw FormatException('JSON field "$name" must be a boolean');
  }
  return value;
}

Map<String, Object?> _asObject(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$name must be an object');
  }
  return value;
}

String _asString(Object? value, String name) {
  if (value is! String) {
    throw FormatException('$name must be a string');
  }
  return value;
}

int _asInt(Object? value, String name) {
  if (value is! int) {
    throw FormatException('$name must be an integer');
  }
  return value;
}
