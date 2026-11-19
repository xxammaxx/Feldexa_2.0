// Feldexa persistence value objects (T020).
//
// Owner: `packages/feldexa_core/lib/src/model/persistence.dart` (T020).
// Normative sources:
//   * `data-model.md` §2.5 — `DurabilityStatus`;
//   * `data-model.md` §3.12 — `Revision`, `RevisionKind`, and
//     `RevisionContent`;
//   * `data-model.md` §3.13 — `DurablePointer` is T017-owned and is
//     deliberately imported, never redeclared here;
//   * `contracts/storage-format.md` §2.4 and §3.1 — canonical JSON and the
//     verified commit protocol;
//   * `contracts/ports.md` §1 and §2.10 — `RevisionContent` and
//     `RevisionKind` are canonical shared types;
//   * `contracts/error-catalog.de.md` §3 — the durability labels and German
//     save error codes;
//   * `spec.md` FR-044, FR-046, and FR-048.
//
// A revision is a full document snapshot without source bytes. The aggregate
// modules own the individual value objects; this file only composes them and
// validates the cross-object invariants that a standalone `RevisionContent`
// can know. Source bytes, document metadata, and the durable head pointer are
// deliberately not part of a revision payload.
//
// Every type is immutable, validates in release builds, and never echoes
// document content in an error or `toString`.
library;

import 'canonical_json.dart';
import 'document.dart';
import 'durable_pointer.dart';
import 'field.dart';
import 'template_origin.dart';

/// The durability state shown on every save-related surface
/// (`data-model.md` §2.5).
///
/// Only [CleanDurabilityStatus] and [SavedDurabilityStatus] may be presented
/// as durable (FR-046). The state is transient: it is derived from the
/// in-memory document and the last verified head, so it is never persisted in
/// a revision.
sealed class DurabilityStatus {
  const DurabilityStatus._();

  /// No changes since the last durable state.
  static const DurabilityStatus clean = CleanDurabilityStatus._();

  /// A commit is in progress; it is not durable yet.
  static const DurabilityStatus saving = SavingDurabilityStatus._();

  /// In-memory changes exist and are at risk (FR-046/FR-048).
  static const DurabilityStatus unsaved = UnsavedDurabilityStatus._();

  /// A verified commit completed at [SavedDurabilityStatus.lastDurableAt].
  ///
  /// Throws [ArgumentError] when [lastDurableAt] is not UTC.
  factory DurabilityStatus.saved({required DateTime lastDurableAt}) {
    return SavedDurabilityStatus._(_requireUtc(lastDurableAt, 'lastDurableAt'));
  }

  /// A save failed and the previous durable head is preserved.
  ///
  /// [errorCode] is a stable German catalog code such as `SAVE-003`, never a
  /// user-visible sentence. Throws [ArgumentError] for an invalid code.
  factory DurabilityStatus.saveFailed(String errorCode) {
    return SaveFailedDurabilityStatus._(
      _requireCatalogCode(errorCode, 'errorCode'),
    );
  }

  /// Startup recovery adopted an older verified revision.
  ///
  /// [revisionId] is the UUIDv4 of the adopted revision. Throws
  /// [ArgumentError] for an invalid id.
  factory DurabilityStatus.recoveryFallback(String revisionId) {
    return RecoveryFallbackDurabilityStatus._(
      _requireUuidV4(revisionId, 'revisionId'),
    );
  }

  /// Stable token matching `data-model.md` §2.5.
  String get wireName;

  /// Whether the state may honestly be presented as durable.
  bool get isDurable;
}

/// `clean`: no changes since the last durable state.
final class CleanDurabilityStatus extends DurabilityStatus {
  const CleanDurabilityStatus._() : super._();

  @override
  String get wireName => 'clean';

  @override
  bool get isDurable => true;

  @override
  bool operator ==(Object other) => other is CleanDurabilityStatus;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'DurabilityStatus.clean';
}

/// `saving`: a commit is in progress and is not durable yet.
final class SavingDurabilityStatus extends DurabilityStatus {
  const SavingDurabilityStatus._() : super._();

  @override
  String get wireName => 'saving';

  @override
  bool get isDurable => false;

  @override
  bool operator ==(Object other) => other is SavingDurabilityStatus;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'DurabilityStatus.saving';
}

/// `unsaved(risk)`: in-memory changes only.
///
/// The risk is inherent: no commit has verified these changes, so the state
/// is never durable.
final class UnsavedDurabilityStatus extends DurabilityStatus {
  const UnsavedDurabilityStatus._() : super._();

  @override
  String get wireName => 'unsaved';

  @override
  bool get isDurable => false;

  @override
  bool operator ==(Object other) => other is UnsavedDurabilityStatus;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'DurabilityStatus.unsaved';
}

/// `saved`: a verified commit completed at [lastDurableAt].
final class SavedDurabilityStatus extends DurabilityStatus {
  const SavedDurabilityStatus._(this.lastDurableAt) : super._();

  /// When the read-back-verified commit completed, in UTC.
  final DateTime lastDurableAt;

  @override
  String get wireName => 'saved';

  @override
  bool get isDurable => true;

  @override
  bool operator ==(Object other) {
    return other is SavedDurabilityStatus &&
        other.lastDurableAt == lastDurableAt;
  }

  @override
  int get hashCode => Object.hash(runtimeType, lastDurableAt);

  @override
  String toString() {
    return 'DurabilityStatus.saved('
        'lastDurableAt: ${canonicalUtcTimestamp(lastDurableAt)})';
  }
}

/// `saveFailed(errorCode)`: the last save failed; the previous head remains.
final class SaveFailedDurabilityStatus extends DurabilityStatus {
  const SaveFailedDurabilityStatus._(this.errorCode) : super._();

  /// Stable German catalog code such as `SAVE-003`.
  final String errorCode;

  @override
  String get wireName => 'saveFailed';

  @override
  bool get isDurable => false;

  @override
  bool operator ==(Object other) {
    return other is SaveFailedDurabilityStatus && other.errorCode == errorCode;
  }

  @override
  int get hashCode => Object.hash(runtimeType, errorCode);

  @override
  String toString() => 'DurabilityStatus.saveFailed($errorCode)';
}

/// `recoveryFallback(revisionId)`: an older verified revision was adopted.
final class RecoveryFallbackDurabilityStatus extends DurabilityStatus {
  const RecoveryFallbackDurabilityStatus._(this.revisionId) : super._();

  /// UUIDv4 of the older revision adopted by startup recovery.
  final String revisionId;

  @override
  String get wireName => 'recoveryFallback';

  @override
  bool get isDurable => false;

  @override
  bool operator ==(Object other) {
    return other is RecoveryFallbackDurabilityStatus &&
        other.revisionId == revisionId;
  }

  @override
  int get hashCode => Object.hash(runtimeType, revisionId);

  @override
  String toString() => 'DurabilityStatus.recoveryFallback($revisionId)';
}

/// The provenance of a revision commit (`data-model.md` §3.12).
///
/// The wire names are exactly the tokens accepted by the T017-owned
/// [DurablePointer.kind], so a revision can build its pointer without a second
/// token vocabulary.
enum RevisionKind {
  /// Debounced, coalesced automatic save.
  autosave('autosave'),

  /// User-requested explicit save.
  explicit('explicit'),

  /// A restore that creates a new revision.
  recovery('recovery');

  const RevisionKind(this.wireName);

  /// Stable JSON token; also a valid [DurablePointer] kind.
  final String wireName;

  /// Parses a JSON token.
  ///
  /// Throws [FormatException] for a non-string or unknown token. The error
  /// deliberately does not echo the input.
  static RevisionKind fromWire(Object? token) {
    if (token is String) {
      for (final RevisionKind value in values) {
        if (value.wireName == token) {
          return value;
        }
      }
    }
    throw const FormatException('Unknown revision kind token.');
  }
}

/// The full document snapshot stored in a revision
/// (`data-model.md` §3.12).
///
/// The payload contains pages, suggestions, confirmed fields, their order,
/// committed values, signatures, verification state, and the pinned template
/// origin. It never contains source bytes, document metadata, preferences, or
/// the durable head. Unknown same-schema JSON fields are retained across a
/// read/write round (`data-model.md` §6); a `source` key is rejected instead of
/// being preserved because no revision may embed source bytes.
final class RevisionContent extends JsonObject {
  /// Creates and validates a full revision snapshot.
  ///
  /// [pages] must be non-empty and ordered contiguously from index 0.
  /// Suggestions must reference existing pages, fit their display box, have
  /// unique ids, and carry symmetric conflicts. Suggestion resolution and
  /// machine-field provenance are cross-checked per
  /// `contracts/recognition-output.md` §7: a confirmed suggestion has exactly
  /// one matching machine field, a machine field points back to a confirmed
  /// same-page suggestion with equal confidence, and a `duplicateOfConfirmed`
  /// suggestion is never confirmed and needs a matching machine field. Fields
  /// must have unique ids, fit their page, and be a permutation of [fieldOrder]
  /// whose `order` equals the field's position. Values exist only for fields
  /// and must be compatible
  /// or preserved as [IncompatibleValue] flagged by the `incompatible_content`
  /// warning or a blocking field error; signatures exist only for signature
  /// fields on the same page; verification entries exist only for fields.
  /// [unknownFields] are opaque same-schema JSON extensions retained for a
  /// later write.
  ///
  /// Throws [ArgumentError] for every invalid value. The error never echoes
  /// document content.
  factory RevisionContent({
    required Iterable<Page> pages,
    Iterable<FieldSuggestion> suggestions = const <FieldSuggestion>[],
    Iterable<ConfirmedField> fields = const <ConfirmedField>[],
    required Iterable<String> fieldOrder,
    Map<String, FieldValue> values = const <String, FieldValue>{},
    Map<String, SignatureMark> signatures = const <String, SignatureMark>{},
    Map<String, FieldVerification> verification =
        const <String, FieldVerification>{},
    TemplateOrigin? templateOrigin,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    final List<Page> pageList = pages.toList(growable: false);
    if (pageList.isEmpty) {
      throw ArgumentError('pages must contain at least one page');
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
            'conflictsWith must reference a suggestion in the revision',
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

    // recognition-output §7: suggestions and their resolution/provenance must
    // stay consistent with the confirmed machine fields.
    validateSuggestionFieldProvenance(
      suggestions: suggestionList,
      fields: orderedFields,
    );

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
      final bool hasIncompatibleValue = value is IncompatibleValue;
      final bool warnsIncompatible =
          field.validation.isWarning &&
          field.validation.warningCode == WarningCode.incompatibleContent;
      // data-model.md §3.5 flags incompatible content either with the
      // incompatible_content warning (explicit user resolution pending) or with
      // a blocking error (a failed number/date parse). An unflagged
      // IncompatibleValue still fails, and the warning still requires the
      // preserved value it claims.
      final bool flagsIncompatible =
          warnsIncompatible || field.validation.isError;
      if (hasIncompatibleValue && !flagsIncompatible) {
        throw ArgumentError(
          'incompatible content must be flagged by an incompatible_content '
          'warning or a blocking field error',
        );
      }
      if (warnsIncompatible && !hasIncompatibleValue) {
        throw ArgumentError(
          'an incompatible_content warning requires preserved incompatible '
          'content',
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

    return RevisionContent._(
      pages: List<Page>.unmodifiable(pageList),
      suggestions: List<FieldSuggestion>.unmodifiable(suggestionList),
      fields: List<ConfirmedField>.unmodifiable(orderedFields),
      fieldOrder: List<String>.unmodifiable(suppliedOrder),
      values: Map<String, FieldValue>.unmodifiable(valueMap),
      signatures: Map<String, SignatureMark>.unmodifiable(signatureMap),
      verification: Map<String, FieldVerification>.unmodifiable(verification),
      templateOrigin: templateOrigin,
      unknownFields: freezeUnknownJsonFields(unknownFields),
    );
  }

  const RevisionContent._({
    required this.pages,
    required this.suggestions,
    required this.fields,
    required this.fieldOrder,
    required this.values,
    required this.signatures,
    required this.verification,
    required this.templateOrigin,
    required super.unknownFields,
  });

  /// Captures the persisted snapshot fields of [document].
  ///
  /// Source bytes, document metadata, transient status, preferences, and the
  /// durable head are deliberately excluded.
  factory RevisionContent.fromDocument(Document document) {
    return RevisionContent(
      pages: document.pages,
      suggestions: document.suggestions,
      fields: document.fields,
      fieldOrder: document.fieldOrder,
      values: document.values,
      signatures: document.signatures,
      verification: document.verification,
      templateOrigin: document.templateOrigin,
    );
  }

  /// Reads a persisted revision snapshot.
  ///
  /// A `source` key is rejected: a revision must never embed source bytes.
  /// Unknown same-schema keys are retained for a later write.
  ///
  /// Throws [FormatException] for missing, mistyped, invalid, or unsupported
  /// fields.
  factory RevisionContent.fromJson(Map<String, Object?> json) {
    if (json.containsKey('source')) {
      throw const FormatException(
        'Revision content must not embed source bytes',
      );
    }
    try {
      return RevisionContent(
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
        unknownFields: unknownJsonFields(json, _revisionContentJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid revision content JSON: ${error.message}');
    }
  }

  /// Pages ordered contiguously from index 0.
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

  /// Number of pages in the snapshot.
  int get pageCount => pages.length;

  /// Serializes the snapshot.
  ///
  /// No `source` key is ever emitted. Unknown same-schema fields are emitted
  /// beneath the modeled keys; nested objects emit their own retained fields.
  /// Use [canonicalJsonEncode] on this map for the canonical byte form.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
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
    });
  }

  @override
  bool operator ==(Object other) {
    return other is RevisionContent &&
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
        other.templateOrigin == templateOrigin;
  }

  @override
  int get hashCode {
    return Object.hash(
      Object.hashAll(pages),
      Object.hashAll(suggestions),
      Object.hashAll(fields),
      Object.hashAll(fieldOrder),
      _mapHash<FieldValue>(values),
      _mapHash<SignatureMark>(signatures),
      _mapHash<FieldVerification>(verification),
      templateOrigin,
    );
  }

  @override
  String toString() {
    return 'RevisionContent(pages: ${pages.length}, '
        'suggestions: ${suggestions.length}, fields: ${fields.length})';
  }
}

/// One immutable document revision (`data-model.md` §3.12).
///
/// A revision contains the snapshot [content] and the hash of its canonical
/// plaintext bytes. It does not embed source bytes or the durable head; the
/// verified [DurablePointer] is T017-owned and is created separately after the
/// storage adapter's read-back check. Unknown same-schema JSON fields are
/// retained across a read/write round (`data-model.md` §6).
final class Revision extends JsonObject {
  /// Creates a revision.
  ///
  /// [id] and [documentId] must be lowercase UUIDv4 values and
  /// [parentRevisionId] must be null for the first revision or a different
  /// lowercase UUIDv4 otherwise. [createdAt] must be UTC and
  /// [plaintextSha256] must be 64 lowercase hexadecimal characters.
  /// [unknownFields] are opaque same-schema JSON extensions retained for a
  /// later write.
  ///
  /// Throws [ArgumentError] for every invalid value. The error never echoes
  /// document content.
  factory Revision({
    required String id,
    required String documentId,
    String? parentRevisionId,
    required RevisionKind kind,
    required DateTime createdAt,
    required String plaintextSha256,
    required RevisionContent content,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    final String checkedId = _requireUuidV4(id, 'id');
    final String checkedDocumentId = _requireUuidV4(documentId, 'documentId');
    if (parentRevisionId != null) {
      _requireUuidV4(parentRevisionId, 'parentRevisionId');
      if (parentRevisionId == checkedId) {
        throw ArgumentError('a revision must not be its own parent');
      }
    }
    return Revision._(
      id: checkedId,
      documentId: checkedDocumentId,
      parentRevisionId: parentRevisionId,
      kind: kind,
      createdAt: _requireUtc(createdAt, 'createdAt'),
      plaintextSha256: _requireSha256(plaintextSha256, 'plaintextSha256'),
      content: content,
      unknownFields: freezeUnknownJsonFields(unknownFields),
    );
  }

  const Revision._({
    required this.id,
    required this.documentId,
    required this.parentRevisionId,
    required this.kind,
    required this.createdAt,
    required this.plaintextSha256,
    required this.content,
    required super.unknownFields,
  });

  /// Reads a persisted revision.
  ///
  /// Unknown same-schema keys are retained for a later write.
  ///
  /// Throws [FormatException] for missing, mistyped, invalid, or unsupported
  /// fields.
  factory Revision.fromJson(Map<String, Object?> json) {
    final Object? parentRevisionId = json['parentRevisionId'];
    if (parentRevisionId != null && parentRevisionId is! String) {
      throw const FormatException(
        'JSON field "parentRevisionId" must be a string or null',
      );
    }
    final Object? content = json['content'];
    if (content is! Map<String, Object?>) {
      throw const FormatException('JSON field "content" must be an object');
    }
    try {
      return Revision(
        id: _readString(json, 'id'),
        documentId: _readString(json, 'documentId'),
        parentRevisionId: parentRevisionId as String?,
        kind: RevisionKind.fromWire(json['kind']),
        createdAt: parseCanonicalUtcTimestamp(
          json['createdAt'],
          name: 'createdAt',
        ),
        plaintextSha256: _readString(json, 'plaintextSha256'),
        content: RevisionContent.fromJson(content),
        unknownFields: unknownJsonFields(json, _revisionJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid revision JSON: ${error.message}');
    }
  }

  /// UUIDv4 of this revision.
  final String id;

  /// UUIDv4 of the parent document.
  final String documentId;

  /// UUIDv4 of the parent revision, or null for the first revision.
  final String? parentRevisionId;

  /// Provenance of this commit.
  final RevisionKind kind;

  /// When the revision was created, in UTC.
  final DateTime createdAt;

  /// SHA-256 of the canonical plaintext snapshot, verified before the head
  /// update.
  final String plaintextSha256;

  /// The full snapshot; never contains source bytes.
  final RevisionContent content;

  /// Returns a copy with the supplied fields replaced.
  ///
  /// The result is revalidated by the public constructor. Passing `null` for
  /// [parentRevisionId] clears it; omitting it keeps the current value.
  Revision copyWith({
    String? id,
    String? documentId,
    Object? parentRevisionId = _unset,
    RevisionKind? kind,
    DateTime? createdAt,
    String? plaintextSha256,
    RevisionContent? content,
    Map<String, Object?>? unknownFields,
  }) {
    return Revision(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      parentRevisionId: identical(parentRevisionId, _unset)
          ? this.parentRevisionId
          : parentRevisionId as String?,
      kind: kind ?? this.kind,
      createdAt: createdAt ?? this.createdAt,
      plaintextSha256: plaintextSha256 ?? this.plaintextSha256,
      content: content ?? this.content,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  /// Builds the durable pointer for this revision after a verified commit.
  ///
  /// Call this only after the storage adapter has decrypted and hash-verified
  /// the written revision and head. [committedAt] is the verification time in
  /// UTC. The revision kind maps to the T017 [DurablePointer.kind] vocabulary.
  ///
  /// Throws [ArgumentError] when [committedAt] is not UTC.
  DurablePointer toDurablePointer({required DateTime committedAt}) {
    return DurablePointer(
      revisionId: id,
      parentRevisionId: parentRevisionId,
      kind: kind.wireName,
      committedAt: _requireUtc(committedAt, 'committedAt'),
      sha256: plaintextSha256,
    );
  }

  /// Serializes the revision.
  ///
  /// `createdAt` uses the canonical UTC form. Unknown same-schema fields are
  /// emitted beneath the modeled keys; [content] emits its own retained
  /// fields. Use [canonicalJsonEncode] on this map for the canonical byte
  /// form.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'id': id,
      'documentId': documentId,
      'parentRevisionId': parentRevisionId,
      'kind': kind.wireName,
      'createdAt': canonicalUtcTimestamp(createdAt),
      'plaintextSha256': plaintextSha256,
      'content': content.toJson(),
    });
  }

  @override
  bool operator ==(Object other) {
    return other is Revision &&
        other.id == id &&
        other.documentId == documentId &&
        other.parentRevisionId == parentRevisionId &&
        other.kind == kind &&
        other.createdAt == createdAt &&
        other.plaintextSha256 == plaintextSha256 &&
        other.content == content;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      documentId,
      parentRevisionId,
      kind,
      createdAt,
      plaintextSha256,
      content,
    );
  }

  @override
  String toString() {
    return 'Revision(id: $id, kind: ${kind.wireName}, '
        'pages: ${content.pages.length})';
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

int _mapHash<V>(Map<String, V> map) {
  final List<String> keys = map.keys.toList(growable: false)..sort();
  return Object.hashAll(<int>[
    for (final String key in keys) Object.hash(key, map[key]),
  ]);
}

String _requireUuidV4(String value, String name) {
  if (!_uuidV4Pattern.hasMatch(value)) {
    throw ArgumentError('$name must be a lowercase UUIDv4');
  }
  return value;
}

DateTime _requireUtc(DateTime value, String name) {
  if (!value.isUtc) {
    throw ArgumentError('$name must be UTC');
  }
  return value;
}

String _requireSha256(String value, String name) {
  if (!_sha256Pattern.hasMatch(value)) {
    throw ArgumentError('$name must be 64 lowercase hexadecimal characters');
  }
  return value;
}

String _requireCatalogCode(String value, String name) {
  if (!_catalogCodePattern.hasMatch(value)) {
    throw ArgumentError('$name must be a German catalog code such as SAVE-003');
  }
  return value;
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

final RegExp _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

final RegExp _catalogCodePattern = RegExp(r'^[A-Z]{2,6}-[0-9]{3}$');

/// Marker for copyWith parameters that are deliberately nullable.
const Object _unset = Object();

/// Modeled keys of a persisted revision snapshot.
const Set<String> _revisionContentJsonKeys = <String>{
  'pages',
  'suggestions',
  'fields',
  'fieldOrder',
  'values',
  'signatures',
  'verification',
  'templateOrigin',
};

/// Modeled keys of a persisted revision.
const Set<String> _revisionJsonKeys = <String>{
  'id',
  'documentId',
  'parentRevisionId',
  'kind',
  'createdAt',
  'plaintextSha256',
  'content',
};
