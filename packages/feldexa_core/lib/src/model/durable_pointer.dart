// Feldexa durable-head pointer (T017).
//
// Owner: `packages/feldexa_core/lib/src/model/durable_pointer.dart` (T017).
// Normative sources: `data-model.md` §3.13, §4.1 and
// `contracts/storage-format.md` §3.1.
//
// `DurablePointer` is embedded in `Document.lastDurable`, so T017 owns it. T020
// owns `Revision`, `RevisionKind`, and `RevisionContent` and must not redeclare
// this pointer. To keep the T017 <-> T020 dependency acyclic, this file stores
// the revision kind as the validated wire token instead of importing T020's
// `RevisionKind`; T020 maps its enum to [kind] when it builds a pointer.
//
// Only a verified commit may produce a pointer: [verifyReadBack] is therefore
// required to be true, and decoding a pointer that claims otherwise fails
// closed instead of presenting unverified data as durable.
library;

import 'canonical_json.dart';

/// A pointer to the last revision whose read-back verification succeeded.
///
/// Unknown same-schema JSON fields are retained across a read/write round
/// (`data-model.md` §6).
final class DurablePointer extends JsonObject {
  /// Creates a durable pointer.
  ///
  /// [revisionId] and an optional [parentRevisionId] must be lowercase UUIDv4
  /// values, [kind] must be `autosave`, `explicit`, or `recovery`, [sha256]
  /// must be 64 lowercase hexadecimal characters, and [committedAt] must be
  /// UTC. [verifyReadBack] must be true. [unknownFields] are opaque
  /// same-schema JSON extensions retained for a later write.
  ///
  /// Throws [ArgumentError] for every invalid value.
  factory DurablePointer({
    required String revisionId,
    String? parentRevisionId,
    required String kind,
    required DateTime committedAt,
    required String sha256,
    bool verifyReadBack = true,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    if (!_uuidV4Pattern.hasMatch(revisionId)) {
      throw ArgumentError('revisionId must be a lowercase UUIDv4');
    }
    if (parentRevisionId != null) {
      if (!_uuidV4Pattern.hasMatch(parentRevisionId)) {
        throw ArgumentError('parentRevisionId must be a lowercase UUIDv4');
      }
      if (parentRevisionId == revisionId) {
        throw ArgumentError('a revision must not be its own parent');
      }
    }
    if (!_allowedKinds.contains(kind)) {
      throw ArgumentError('kind must be autosave, explicit, or recovery');
    }
    if (!committedAt.isUtc) {
      throw ArgumentError('committedAt must be UTC');
    }
    if (!_sha256Pattern.hasMatch(sha256)) {
      throw ArgumentError('sha256 must be 64 lowercase hexadecimal characters');
    }
    if (!verifyReadBack) {
      throw ArgumentError(
        'verifyReadBack must be true; only a verified commit is durable',
      );
    }
    return DurablePointer._(
      revisionId: revisionId,
      parentRevisionId: parentRevisionId,
      kind: kind,
      committedAt: committedAt,
      sha256: sha256,
      unknownFields: Map<String, Object?>.unmodifiable(unknownFields),
    );
  }

  const DurablePointer._({
    required this.revisionId,
    required this.parentRevisionId,
    required this.kind,
    required this.committedAt,
    required this.sha256,
    required super.unknownFields,
  });

  /// Reads a persisted durable pointer.
  ///
  /// `verifyReadBack` is part of the contract and must be `true`; a missing or
  /// false value is rejected rather than silently upgraded. Unknown
  /// same-schema keys are retained for a later write.
  ///
  /// Throws [FormatException] for missing, mistyped, or invalid fields.
  factory DurablePointer.fromJson(Map<String, Object?> json) {
    final Object? revisionId = json['revisionId'];
    if (revisionId is! String) {
      throw const FormatException('JSON field "revisionId" must be a string');
    }
    final Object? parentRevisionId = json['parentRevisionId'];
    if (parentRevisionId != null && parentRevisionId is! String) {
      throw const FormatException(
        'JSON field "parentRevisionId" must be a string or null',
      );
    }
    final Object? kind = json['kind'];
    if (kind is! String) {
      throw const FormatException('JSON field "kind" must be a string');
    }
    final Object? sha256 = json['sha256'];
    if (sha256 is! String) {
      throw const FormatException('JSON field "sha256" must be a string');
    }
    final Object? verifyReadBack = json['verifyReadBack'];
    if (verifyReadBack is! bool || !verifyReadBack) {
      throw const FormatException('JSON field "verifyReadBack" must be true');
    }
    try {
      return DurablePointer(
        revisionId: revisionId,
        parentRevisionId: parentRevisionId as String?,
        kind: kind,
        committedAt: parseCanonicalUtcTimestamp(
          json['committedAt'],
          name: 'committedAt',
        ),
        sha256: sha256,
        unknownFields: unknownJsonFields(json, _durablePointerJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid durable pointer JSON: ${error.message}');
    }
  }

  /// Stable revision-kind token for an autosave commit.
  static const String autosaveKind = 'autosave';

  /// Stable revision-kind token for an explicit save.
  static const String explicitKind = 'explicit';

  /// Stable revision-kind token for a recovery restore.
  static const String recoveryKind = 'recovery';

  /// UUIDv4 of the committed revision.
  final String revisionId;

  /// UUIDv4 of the parent revision, or null for the first revision.
  final String? parentRevisionId;

  /// One of [autosaveKind], [explicitKind], or [recoveryKind].
  final String kind;

  /// When the commit was verified, in UTC.
  final DateTime committedAt;

  /// Verified SHA-256 of the plaintext revision payload.
  final String sha256;

  /// Returns a copy with the supplied fields replaced.
  ///
  /// The result is revalidated by the public constructor.
  DurablePointer copyWith({
    String? revisionId,
    Object? parentRevisionId = _unset,
    String? kind,
    DateTime? committedAt,
    String? sha256,
    bool? verifyReadBack,
    Map<String, Object?>? unknownFields,
  }) {
    return DurablePointer(
      revisionId: revisionId ?? this.revisionId,
      parentRevisionId: identical(parentRevisionId, _unset)
          ? this.parentRevisionId
          : parentRevisionId as String?,
      kind: kind ?? this.kind,
      committedAt: committedAt ?? this.committedAt,
      sha256: sha256 ?? this.sha256,
      verifyReadBack: verifyReadBack ?? true,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  /// Serializes to the persisted durable-pointer object.
  ///
  /// `verifyReadBack` is always written as true because the constructor
  /// rejects every other value. Unknown same-schema fields are emitted beneath
  /// the modeled keys.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'revisionId': revisionId,
      'parentRevisionId': parentRevisionId,
      'kind': kind,
      'committedAt': canonicalUtcTimestamp(committedAt),
      'sha256': sha256,
      'verifyReadBack': true,
    });
  }

  @override
  bool operator ==(Object other) {
    return other is DurablePointer &&
        other.revisionId == revisionId &&
        other.parentRevisionId == parentRevisionId &&
        other.kind == kind &&
        other.committedAt == committedAt &&
        other.sha256 == sha256;
  }

  @override
  int get hashCode {
    return Object.hash(revisionId, parentRevisionId, kind, committedAt, sha256);
  }

  @override
  String toString() {
    return 'DurablePointer(revisionId: $revisionId, kind: $kind)';
  }
}

/// Sentinel used by `copyWith` to distinguish "not supplied" from an explicit
/// `null`.
const Object _unset = Object();

/// The revision kinds `DurablePointer` stores without importing T020's enum.
const Set<String> _allowedKinds = <String>{
  DurablePointer.autosaveKind,
  DurablePointer.explicitKind,
  DurablePointer.recoveryKind,
};

final RegExp _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

/// Modeled keys of a persisted durable pointer.
const Set<String> _durablePointerJsonKeys = <String>{
  'revisionId',
  'parentRevisionId',
  'kind',
  'committedAt',
  'sha256',
  'verifyReadBack',
};
