// Feldexa core field model (T018).
//
// Owner: `packages/feldexa_core/lib/src/model/field.dart` (T018, issue #18).
// Normative sources:
//   * `data-model.md` §2.3–§2.4 and §3.4–§3.8 — the field, suggestion,
//     signature, verification, and value types owned by T018;
//   * `contracts/recognition-output.md` §2–§3 and §6 — the suggestion evidence
//     shape, the deterministic `s_p<page>_<ordinal>` id, and the cue
//     vocabulary;
//   * `contracts/editor-interactions.md` §3–§5 — review and filling behavior;
//   * `spec.md` FR-021, FR-028, FR-029, FR-031, FR-038, FR-107/FR-108;
//   * constitution Principles V, VI, and VIII — a platform-independent,
//     serializable model whose validation never echoes user content.
//
// Every type here is immutable and validates in a release build (no debug-only
// assertions). Labels, text, numbers, dates, and signature data are document
// content: a validation error, [Object.toString], or a JSON parse error never
// echoes a rejected label or value. Parsing throws [FormatException];
// construction throws [ArgumentError].
//
// Page membership (`pageIndex` against the page count) and the cross-document
// value/field/key invariants are enforced by the document aggregate (T017);
// this file enforces every constraint that a single value object can know.

library;

import '../geometry/rect.dart';

/// A field's content type (`data-model.md` §2.3).
///
/// The order is the canonical serialization order used when a later task sorts
/// fields by type.
enum FieldType {
  /// Free text; German characters are preserved and line breaks are removed.
  text('text'),

  /// German decimal input stored with a `.` decimal and no exponent.
  number('number'),

  /// Canonical `YYYY-MM-DD` storage with a real calendar date.
  date('date'),

  /// Boolean only.
  checkbox('checkbox'),

  /// Text with `\n` preserved.
  multiline('multiline'),

  /// A reference to a [SignatureMark]; no text value.
  signature('signature');

  const FieldType(this.wireName);

  /// Stable JSON token; matches the names in `data-model.md` §2.3.
  final String wireName;

  /// Parses a JSON token.
  ///
  /// Throws [FormatException] for a non-string or unknown token. The error
  /// deliberately does not echo the input.
  static FieldType fromWire(Object? token) {
    return _enumFromWire(values, (FieldType value) => value.wireName, token);
  }
}

/// How a confirmed field came into existence (`data-model.md` §2.4).
///
/// Provenance survives save, reopen, template derivation, and export planning
/// (constitution Principle IV).
enum Provenance {
  /// Came from a suggestion and was confirmed; keeps the suggestion id and
  /// confidence.
  machine('machine'),

  /// Created manually by the user.
  user('user'),

  /// Inherited from the pinned template version.
  template('template');

  const Provenance(this.wireName);

  /// Stable JSON token.
  final String wireName;

  /// Parses a JSON token.
  ///
  /// Throws [FormatException] for a non-string or unknown token.
  static Provenance fromWire(Object? token) {
    return _enumFromWire(values, (Provenance value) => value.wireName, token);
  }
}

/// The review state of a suggestion (`data-model.md` §3.4).
///
/// A rejection is reversible: `rejected -> unresolved` is an undo, not a new
/// record. Confirmation creates a [ConfirmedField] and copies geometry and
/// type; later field edits never rewrite the suggestion record.
enum SuggestionResolution {
  /// Not yet reviewed.
  unresolved('unresolved'),

  /// Confirmed; a [ConfirmedField] with [Provenance.machine] exists.
  confirmed('confirmed'),

  /// Rejected; reversible with undo.
  rejected('rejected');

  const SuggestionResolution(this.wireName);

  /// Stable JSON token.
  final String wireName;

  /// Parses a JSON token.
  ///
  /// Throws [FormatException] for a non-string or unknown token.
  static SuggestionResolution fromWire(Object? token) {
    return _enumFromWire(
      values,
      (SuggestionResolution value) => value.wireName,
      token,
    );
  }
}

/// A geometric or OCR cue that supports a suggestion.
///
/// The six values in `data-model.md` §3.4 are the source vocabulary:
/// `line`, `box`, `grid`, `whitespace`, `ocr_alignment`, and `keyword`.
/// [signatureArea] is the `signature_area` cue from
/// `contracts/recognition-output.md` §3.1; it is required before a suggestion
/// may propose the [FieldType.signature] type.
enum SuggestionCue {
  /// A horizontal rule directly below the candidate region.
  line('line'),

  /// A closed rectangle enclosing the candidate.
  box('box'),

  /// A cell of a detected table grid.
  grid('grid'),

  /// Bounded empty background adjacent to printed content.
  whitespace('whitespace'),

  /// The candidate aligns with an OCR label line.
  ocrAlignment('ocr_alignment'),

  /// A label lexeme implies the inferred type.
  keyword('keyword'),

  /// A large low-ink region labelled as a signature area.
  signatureArea('signature_area');

  const SuggestionCue(this.wireName);

  /// Stable JSON token.
  final String wireName;

  /// Parses a JSON token.
  ///
  /// Throws [FormatException] for a non-string or unknown token.
  static SuggestionCue fromWire(Object? token) {
    return _enumFromWire(
      values,
      (SuggestionCue value) => value.wireName,
      token,
    );
  }
}

/// A non-blocking field warning (`data-model.md` §3.5 and §3.8).
///
/// Warnings are surfaced to the user and never delete or truncate content
/// (FR-038). [FieldValidation] uses the same vocabulary for a warning state.
enum WarningCode {
  /// The committed content does not fit the field at layout time.
  overflow('overflow'),

  /// Content was preserved after an incompatible reclassification.
  incompatibleContent('incompatible_content'),

  /// The machine suggestion confidence is below the review threshold.
  lowConfidence('low_confidence'),

  /// Another suggestion overlaps this one.
  conflict('conflict');

  const WarningCode(this.wireName);

  /// Stable JSON token.
  final String wireName;

  /// Parses a JSON token.
  ///
  /// Throws [FormatException] for a non-string or unknown token.
  static WarningCode fromWire(Object? token) {
    return _enumFromWire(values, (WarningCode value) => value.wireName, token);
  }
}

/// The per-field review state (`data-model.md` §3.8).
enum FieldVerificationState {
  /// Not reviewed yet.
  unreviewed('unreviewed'),

  /// Reviewed and confirmed by the user.
  confirmed('confirmed'),

  /// Reviewed and corrected by the user.
  corrected('corrected'),

  /// Reviewed and rejected.
  rejected('rejected');

  const FieldVerificationState(this.wireName);

  /// Stable JSON token.
  final String wireName;

  /// Parses a JSON token.
  ///
  /// Throws [FormatException] for a non-string or unknown token.
  static FieldVerificationState fromWire(Object? token) {
    return _enumFromWire(
      values,
      (FieldVerificationState value) => value.wireName,
      token,
    );
  }
}

/// Suggestion evidence: the cue flags and quality signals of one candidate
/// (`data-model.md` §3.4; `contracts/recognition-output.md` §2–§3).
///
/// [cues] is a non-empty, duplicate-free set. [cueAgreement] counts independent
/// cue families and is at least one. [skewDegrees] is the estimated page skew
/// in degrees on the closed interval `-10 … 10`. [lowContrast] is the
/// contract's `contrast == "low"` flag, and [ocrUsed] is false when OCR failed
/// and geometry-only detection ran.
final class SuggestionEvidence {
  /// Creates evidence for a candidate.
  ///
  /// Throws [ArgumentError] when [cues] is empty or contains duplicates, when
  /// [cueAgreement] is less than one, or when [skewDegrees] is non-finite or
  /// outside `-10 … 10`.
  factory SuggestionEvidence({
    required Iterable<SuggestionCue> cues,
    int cueAgreement = 1,
    double skewDegrees = 0,
    bool lowContrast = false,
    bool ocrUsed = true,
  }) {
    final List<SuggestionCue> cueList = cues.toList(growable: false);
    final Set<SuggestionCue> cueSet = cueList.toSet();
    if (cueSet.isEmpty) {
      throw ArgumentError('cues must contain at least one cue');
    }
    if (cueSet.length != cueList.length) {
      throw ArgumentError('cues must not contain duplicates');
    }
    if (cueAgreement < 1) {
      throw ArgumentError('cueAgreement must be at least 1');
    }
    if (!skewDegrees.isFinite || skewDegrees < -10 || skewDegrees > 10) {
      throw ArgumentError('skewDegrees must be finite and between -10 and 10');
    }
    final List<SuggestionCue> sorted = cueSet.toList()
      ..sort((SuggestionCue a, SuggestionCue b) => a.index.compareTo(b.index));
    return SuggestionEvidence._(
      cues: Set<SuggestionCue>.unmodifiable(sorted),
      cueAgreement: cueAgreement,
      skewDegrees: skewDegrees,
      lowContrast: lowContrast,
      ocrUsed: ocrUsed,
    );
  }

  const SuggestionEvidence._({
    required this.cues,
    required this.cueAgreement,
    required this.skewDegrees,
    required this.lowContrast,
    required this.ocrUsed,
  });

  /// Reads the persisted evidence object.
  ///
  /// Throws [FormatException] for missing, mistyped, or out-of-range fields.
  factory SuggestionEvidence.fromJson(Map<String, Object?> json) {
    final Object? rawCues = json['cues'];
    if (rawCues is! List<Object?>) {
      throw const FormatException('JSON field "cues" must be an array');
    }
    final List<SuggestionCue> cues = <SuggestionCue>[
      for (final Object? cue in rawCues) SuggestionCue.fromWire(cue),
    ];
    try {
      return SuggestionEvidence(
        cues: cues,
        cueAgreement: _readInt(json, 'cueAgreement'),
        skewDegrees: _readDouble(json, 'skewDegrees'),
        lowContrast: _readBool(json, 'lowContrast'),
        ocrUsed: _readBool(json, 'ocrUsed'),
      );
    } on ArgumentError catch (error) {
      throw FormatException(
        'Invalid suggestion evidence JSON: ${error.message}',
      );
    }
  }

  /// Unique cue flags, sorted by declaration order.
  final Set<SuggestionCue> cues;

  /// Number of independent cue families supporting the candidate; at least 1.
  final int cueAgreement;

  /// Estimated page skew in degrees on `-10 … 10`.
  final double skewDegrees;

  /// Whether the page contrast was low.
  final bool lowContrast;

  /// Whether OCR supplied evidence, as opposed to geometry-only detection.
  final bool ocrUsed;

  /// Whether the optional signature-area cue is present.
  bool get hasSignatureCue => cues.contains(SuggestionCue.signatureArea);

  /// Serializes to the persisted evidence object.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'cues': <String>[for (final SuggestionCue cue in cues) cue.wireName],
      'cueAgreement': cueAgreement,
      'skewDegrees': skewDegrees,
      'lowContrast': lowContrast,
      'ocrUsed': ocrUsed,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is SuggestionEvidence &&
        other.cueAgreement == cueAgreement &&
        other.skewDegrees == skewDegrees &&
        other.lowContrast == lowContrast &&
        other.ocrUsed == ocrUsed &&
        _setsEqual<SuggestionCue>(other.cues, cues);
  }

  @override
  int get hashCode {
    return Object.hash(
      Object.hashAllUnordered(cues),
      cueAgreement,
      skewDegrees,
      lowContrast,
      ocrUsed,
    );
  }

  @override
  String toString() {
    return 'SuggestionEvidence(cues: ${cues.length}, '
        'cueAgreement: $cueAgreement)';
  }
}

/// A machine suggestion produced by page analysis (`data-model.md` §3.4).
///
/// A suggestion is never treated as a [ConfirmedField] and never contributes
/// export content (aggregate invariant 4). Confirming one creates a
/// [ConfirmedField] with [Provenance.machine]; the suggestion record keeps its
/// original geometry and type for audit.
final class FieldSuggestion {
  /// Creates a suggestion.
  ///
  /// [id] must use the deterministic `s_p<pageIndex>_<ordinal>` form with a
  /// one-based ordinal of at least four digits, and it must embed [pageIndex].
  /// [confidence] is on `0.0 … 1.0`. [labelText] is trimmed, must contain no
  /// control characters, and is at most 200 characters; null or blank means no
  /// credible label. A [FieldType.signature] suggestion requires the
  /// [SuggestionCue.signatureArea] cue. [conflictsWith] must reference other
  /// suggestion ids, contain no duplicates, and never reference [id].
  ///
  /// Throws [ArgumentError] for every invalid value. The error never echoes a
  /// label or any other document content.
  factory FieldSuggestion({
    required String id,
    required int pageIndex,
    required Rect rect,
    required FieldType proposedType,
    required double confidence,
    required String? labelText,
    required SuggestionEvidence evidence,
    Iterable<String> conflictsWith = const <String>[],
    SuggestionResolution resolution = SuggestionResolution.unresolved,
  }) {
    final int checkedPage = _checkPageIndex(pageIndex);
    final String checkedId = _validateSuggestionId(id, checkedPage);
    final double checkedConfidence = _checkUnitInterval(
      confidence,
      'confidence',
    );
    final String? checkedLabel = _normalizeOptionalLabel(
      labelText,
      maxLength: 200,
      name: 'labelText',
    );
    final List<String> checkedConflicts = _normalizeConflicts(
      conflictsWith,
      checkedId,
    );
    if (proposedType == FieldType.signature && !evidence.hasSignatureCue) {
      throw ArgumentError(
        'A signature suggestion requires the signature_area cue',
      );
    }
    return FieldSuggestion._(
      id: checkedId,
      pageIndex: checkedPage,
      rect: rect,
      proposedType: proposedType,
      confidence: checkedConfidence,
      labelText: checkedLabel,
      evidence: evidence,
      conflictsWith: checkedConflicts,
      resolution: resolution,
    );
  }

  const FieldSuggestion._({
    required this.id,
    required this.pageIndex,
    required this.rect,
    required this.proposedType,
    required this.confidence,
    required this.labelText,
    required this.evidence,
    required this.conflictsWith,
    required this.resolution,
  });

  /// Reads a persisted suggestion object.
  ///
  /// Throws [FormatException] for missing, mistyped, or invalid fields.
  factory FieldSuggestion.fromJson(Map<String, Object?> json) {
    try {
      return FieldSuggestion(
        id: _readString(json, 'id'),
        pageIndex: _readInt(json, 'pageIndex'),
        rect: Rect.fromJson(_readObject(json, 'rect')),
        proposedType: FieldType.fromWire(json['proposedType']),
        confidence: _readDouble(json, 'confidence'),
        labelText: _readOptionalString(json, 'labelText'),
        evidence: SuggestionEvidence.fromJson(_readObject(json, 'evidence')),
        conflictsWith: _readStringList(json, 'conflictsWith'),
        resolution: SuggestionResolution.fromWire(json['resolution']),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid field suggestion JSON: ${error.message}');
    }
  }

  /// The deterministic id created by [idFor].
  final String id;

  /// Zero-based page index; validation against the page count belongs to the
  /// document aggregate.
  final int pageIndex;

  /// Display-space rectangle in PDF points; see [fitsWithinPage].
  final Rect rect;

  /// The inferred type. [FieldType.signature] is only allowed with the
  /// signature-area cue.
  final FieldType proposedType;

  /// Confidence on `0.0 … 1.0`; a UI or priority signal, never a probability
  /// claim.
  final double confidence;

  /// Nearest label, trimmed, at most 200 characters; null when no label is
  /// credible. Document content: never logged.
  final String? labelText;

  /// Cue flags and quality signals supporting the candidate.
  final SuggestionEvidence evidence;

  /// Ids of suggestions with an IoU of at least 0.5.
  ///
  /// Symmetry and the IoU threshold are producer responsibilities
  /// (`contracts/recognition-output.md` §6); this value object enforces the
  /// structural invariants: unique, sorted, valid suggestion ids, no self
  /// reference.
  final List<String> conflictsWith;

  /// Current review state; persisted suggestions are [unresolved] until the
  /// user acts.
  final SuggestionResolution resolution;

  /// The deterministic suggestion id for [pageIndex] and a one-based
  /// [ordinal].
  ///
  /// `contracts/recognition-output.md` §2 fixes the spelling
  /// `s_p<pageIndex>_<zero-padded ordinal>`, for example `s_p0_0007`.
  /// [data-model.md] §3.4 writes the same form as `s_<page>_<ordinal>`.
  static String idFor({required int pageIndex, required int ordinal}) {
    final int checkedPage = _checkPageIndex(pageIndex);
    if (ordinal < 1) {
      throw ArgumentError('ordinal must be at least 1');
    }
    final String padded = ordinal.toString().padLeft(4, '0');
    return 's_p${checkedPage}_$padded';
  }

  /// Uncertainty implied by [confidence]: `1 - confidence`.
  double get uncertainty => 1 - confidence;

  /// Whether [rect] is inside a page display box within the 0.5 pt tolerance
  /// from `data-model.md` §2.1.
  ///
  /// A rectangle outside by more than 0.5 pt is an error; clamping is never
  /// silent. The value object does not store the page size, so the document
  /// aggregate (T017) calls this with [PageGeometry.displaySize].
  bool fitsWithinPage(Size displaySize) {
    return _fitsWithinPage(rect, displaySize);
  }

  /// Returns a copy with the supplied fields replaced.
  ///
  /// [labelText] can be cleared by passing `null`; omitting it keeps the
  /// current value. The result is revalidated by the public constructor.
  FieldSuggestion copyWith({
    int? pageIndex,
    Rect? rect,
    FieldType? proposedType,
    double? confidence,
    Object? labelText = _unset,
    SuggestionEvidence? evidence,
    Iterable<String>? conflictsWith,
    SuggestionResolution? resolution,
  }) {
    return FieldSuggestion(
      id: id,
      pageIndex: pageIndex ?? this.pageIndex,
      rect: rect ?? this.rect,
      proposedType: proposedType ?? this.proposedType,
      confidence: confidence ?? this.confidence,
      labelText: identical(labelText, _unset)
          ? this.labelText
          : labelText as String?,
      evidence: evidence ?? this.evidence,
      conflictsWith: conflictsWith ?? this.conflictsWith,
      resolution: resolution ?? this.resolution,
    );
  }

  /// Serializes to the persisted suggestion object.
  ///
  /// Key ordering is not canonical here; the T017 canonical JSON encoder owns
  /// that.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'pageIndex': pageIndex,
      'rect': rect.toJson(),
      'proposedType': proposedType.wireName,
      'confidence': confidence,
      'labelText': labelText,
      'evidence': evidence.toJson(),
      'conflictsWith': List<String>.unmodifiable(conflictsWith),
      'resolution': resolution.wireName,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is FieldSuggestion &&
        other.id == id &&
        other.pageIndex == pageIndex &&
        other.rect == rect &&
        other.proposedType == proposedType &&
        other.confidence == confidence &&
        other.labelText == labelText &&
        other.evidence == evidence &&
        _listsEqual<String>(other.conflictsWith, conflictsWith) &&
        other.resolution == resolution;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      pageIndex,
      rect,
      proposedType,
      confidence,
      labelText,
      evidence,
      Object.hashAll(conflictsWith),
      resolution,
    );
  }

  @override
  String toString() {
    return 'FieldSuggestion(id: $id, pageIndex: $pageIndex, '
        'proposedType: ${proposedType.wireName}, confidence: $confidence, '
        'resolution: ${resolution.wireName})';
  }
}

/// A field that belongs to the confirmed document structure
/// (`data-model.md` §3.5).
///
/// Only confirmed fields contribute values and export content. A machine field
/// keeps the suggestion id and confidence that produced it; the other
/// provenances must not carry them.
final class ConfirmedField {
  /// Creates a confirmed field.
  ///
  /// [id] is a UUIDv4 or a deterministic template field id: non-empty, at most
  /// 128 characters, with no whitespace or control characters. [label] is
  /// trimmed and must be 1–120 characters; German characters are preserved.
  /// [order] is at least 0. [createdAt] and [updatedAt] must be UTC.
  /// [sourceSuggestionId] and [suggestionConfidence] are required exactly when
  /// [provenance] is [Provenance.machine], and the suggestion must be on the
  /// same page.
  ///
  /// Throws [ArgumentError] for every invalid value. The error never echoes a
  /// label.
  factory ConfirmedField({
    required String id,
    required int pageIndex,
    required Rect rect,
    required FieldType type,
    required Provenance provenance,
    String? sourceSuggestionId,
    double? suggestionConfidence,
    required String label,
    required int order,
    required DateTime createdAt,
    required DateTime updatedAt,
    FieldValidation validation = FieldValidation.ok,
  }) {
    final int checkedPage = _checkPageIndex(pageIndex);
    final String checkedId = _validateFieldId(id);
    final String checkedLabel = _normalizeRequiredLabel(
      label,
      maxLength: 120,
      name: 'label',
    );
    if (order < 0) {
      throw ArgumentError('order must be at least 0');
    }
    final String? checkedSuggestionId = sourceSuggestionId == null
        ? null
        : _validateSuggestionId(sourceSuggestionId, checkedPage);
    final double? checkedSuggestionConfidence = suggestionConfidence == null
        ? null
        : _checkUnitInterval(suggestionConfidence, 'suggestionConfidence');
    if (provenance == Provenance.machine) {
      if (checkedSuggestionId == null || checkedSuggestionConfidence == null) {
        throw ArgumentError(
          'A machine field requires sourceSuggestionId and '
          'suggestionConfidence',
        );
      }
    } else if (checkedSuggestionId != null ||
        checkedSuggestionConfidence != null) {
      throw ArgumentError(
        'Only a machine field may carry sourceSuggestionId and '
        'suggestionConfidence',
      );
    }
    return ConfirmedField._(
      id: checkedId,
      pageIndex: checkedPage,
      rect: rect,
      type: type,
      provenance: provenance,
      sourceSuggestionId: checkedSuggestionId,
      suggestionConfidence: checkedSuggestionConfidence,
      label: checkedLabel,
      order: order,
      createdAt: _checkUtc(createdAt, 'createdAt'),
      updatedAt: _checkUtc(updatedAt, 'updatedAt'),
      validation: validation,
    );
  }

  const ConfirmedField._({
    required this.id,
    required this.pageIndex,
    required this.rect,
    required this.type,
    required this.provenance,
    required this.sourceSuggestionId,
    required this.suggestionConfidence,
    required this.label,
    required this.order,
    required this.createdAt,
    required this.updatedAt,
    required this.validation,
  });

  /// Reads a persisted confirmed field.
  ///
  /// Throws [FormatException] for missing, mistyped, or invalid fields.
  factory ConfirmedField.fromJson(Map<String, Object?> json) {
    try {
      return ConfirmedField(
        id: _readString(json, 'id'),
        pageIndex: _readInt(json, 'pageIndex'),
        rect: Rect.fromJson(_readObject(json, 'rect')),
        type: FieldType.fromWire(json['type']),
        provenance: Provenance.fromWire(json['provenance']),
        sourceSuggestionId: _readOptionalString(json, 'sourceSuggestionId'),
        suggestionConfidence: _readOptionalDouble(json, 'suggestionConfidence'),
        label: _readString(json, 'label'),
        order: _readInt(json, 'order'),
        createdAt: _readTimestamp(json, 'createdAt'),
        updatedAt: _readTimestamp(json, 'updatedAt'),
        validation: FieldValidation.fromJson(_readObject(json, 'validation')),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid confirmed field JSON: ${error.message}');
    }
  }

  /// UUIDv4 or deterministic template field id.
  final String id;

  /// Zero-based page index; the document aggregate validates it against the
  /// page count.
  final int pageIndex;

  /// Display-space rectangle in PDF points; see [fitsWithinPage].
  final Rect rect;

  /// The field's current type.
  final FieldType type;

  /// How the field came into existence.
  final Provenance provenance;

  /// The suggestion that produced this field; required exactly for
  /// [Provenance.machine].
  final String? sourceSuggestionId;

  /// The machine suggestion's confidence; required exactly for
  /// [Provenance.machine].
  final double? suggestionConfidence;

  /// User-visible name, 1–120 characters; document content, never logged.
  final String label;

  /// Non-negative contiguous order; normalization is the document
  /// aggregate's responsibility.
  final int order;

  /// Creation time in UTC.
  final DateTime createdAt;

  /// Last modification time in UTC.
  final DateTime updatedAt;

  /// The current validation state.
  final FieldValidation validation;

  /// Whether [value] is compatible with this field's type.
  ///
  /// A reclassification keeps incompatible content as an [IncompatibleValue]
  /// and flags it with a [WarningCode.incompatibleContent] validation state
  /// instead of discarding it (FR-029/FR-038), so an incompatible value is
  /// accepted here; the validation state carries the warning.
  bool acceptsValue(FieldValue value) {
    return value is IncompatibleValue || value.type == type;
  }

  /// Whether [rect] is inside a page display box within the 0.5 pt tolerance
  /// from `data-model.md` §2.1. Clamping is never silent.
  bool fitsWithinPage(Size displaySize) {
    return _fitsWithinPage(rect, displaySize);
  }

  /// Returns a copy with the supplied fields replaced.
  ///
  /// The nullable suggestion fields use a sentinel, so passing `null` clears
  /// them. The result is revalidated by the public constructor.
  ConfirmedField copyWith({
    int? pageIndex,
    Rect? rect,
    FieldType? type,
    Provenance? provenance,
    Object? sourceSuggestionId = _unset,
    Object? suggestionConfidence = _unset,
    String? label,
    int? order,
    DateTime? createdAt,
    DateTime? updatedAt,
    FieldValidation? validation,
  }) {
    return ConfirmedField(
      id: id,
      pageIndex: pageIndex ?? this.pageIndex,
      rect: rect ?? this.rect,
      type: type ?? this.type,
      provenance: provenance ?? this.provenance,
      sourceSuggestionId: identical(sourceSuggestionId, _unset)
          ? this.sourceSuggestionId
          : sourceSuggestionId as String?,
      suggestionConfidence: identical(suggestionConfidence, _unset)
          ? this.suggestionConfidence
          : suggestionConfidence as double?,
      label: label ?? this.label,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      validation: validation ?? this.validation,
    );
  }

  /// Serializes to the persisted confirmed-field object.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'pageIndex': pageIndex,
      'rect': rect.toJson(),
      'type': type.wireName,
      'provenance': provenance.wireName,
      'sourceSuggestionId': sourceSuggestionId,
      'suggestionConfidence': suggestionConfidence,
      'label': label,
      'order': order,
      'createdAt': _serializeTimestamp(createdAt),
      'updatedAt': _serializeTimestamp(updatedAt),
      'validation': validation.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is ConfirmedField &&
        other.id == id &&
        other.pageIndex == pageIndex &&
        other.rect == rect &&
        other.type == type &&
        other.provenance == provenance &&
        other.sourceSuggestionId == sourceSuggestionId &&
        other.suggestionConfidence == suggestionConfidence &&
        other.label == label &&
        other.order == order &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.validation == validation;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      pageIndex,
      rect,
      type,
      provenance,
      sourceSuggestionId,
      suggestionConfidence,
      label,
      order,
      createdAt,
      updatedAt,
      validation,
    );
  }

  @override
  String toString() {
    return 'ConfirmedField(id: $id, pageIndex: $pageIndex, '
        'type: ${type.wireName}, provenance: ${provenance.wireName}, '
        'order: $order)';
  }
}

/// A handwritten signature asset reference (`data-model.md` §3.7).
///
/// A signature belongs only to the current document (FR-036), is not reusable,
/// and template creation excludes it (FR-057). Deleting the field deletes its
/// asset after the next verified commit.
final class SignatureMark {
  /// Creates a signature mark.
  ///
  /// [assetId] must be a lowercase UUIDv4 and [fieldId] a valid field id.
  /// [widthPx] and [heightPx] must be positive and at most 1024 on the long
  /// edge. [capturedAt] must be UTC. [sha256] is the 64-lowercase-hex hash of
  /// the plaintext PNG.
  ///
  /// Throws [ArgumentError] for every invalid value. The error never echoes
  /// signature bytes, which are never held by this value object.
  factory SignatureMark({
    required String assetId,
    required String fieldId,
    required int pageIndex,
    required Rect rect,
    required int widthPx,
    required int heightPx,
    required DateTime capturedAt,
    required String sha256,
  }) {
    if (widthPx < 1 || heightPx < 1) {
      throw ArgumentError('widthPx and heightPx must be greater than 0');
    }
    if (widthPx > 1024 || heightPx > 1024) {
      throw ArgumentError('the signature long edge must be at most 1024 px');
    }
    return SignatureMark._(
      assetId: _validateUuidV4(assetId, 'assetId'),
      fieldId: _validateFieldId(fieldId),
      pageIndex: _checkPageIndex(pageIndex),
      rect: rect,
      widthPx: widthPx,
      heightPx: heightPx,
      capturedAt: _checkUtc(capturedAt, 'capturedAt'),
      sha256: _validateSha256(sha256, 'sha256'),
    );
  }

  const SignatureMark._({
    required this.assetId,
    required this.fieldId,
    required this.pageIndex,
    required this.rect,
    required this.widthPx,
    required this.heightPx,
    required this.capturedAt,
    required this.sha256,
  });

  /// Reads a persisted signature mark.
  ///
  /// Throws [FormatException] for missing, mistyped, or invalid fields.
  factory SignatureMark.fromJson(Map<String, Object?> json) {
    try {
      return SignatureMark(
        assetId: _readString(json, 'assetId'),
        fieldId: _readString(json, 'fieldId'),
        pageIndex: _readInt(json, 'pageIndex'),
        rect: Rect.fromJson(_readObject(json, 'rect')),
        widthPx: _readInt(json, 'widthPx'),
        heightPx: _readInt(json, 'heightPx'),
        capturedAt: _readTimestamp(json, 'capturedAt'),
        sha256: _readString(json, 'sha256'),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid signature mark JSON: ${error.message}');
    }
  }

  /// UUIDv4 naming the encrypted PNG object in the same document.
  final String assetId;

  /// The signature field this ink belongs to.
  final String fieldId;

  /// Zero-based page index; the same page as the field.
  final int pageIndex;

  /// Ink bounds in display-space PDF points.
  final Rect rect;

  /// Raster width in pixels; positive and at most 1024.
  final int widthPx;

  /// Raster height in pixels; positive and at most 1024.
  final int heightPx;

  /// Capture time in UTC.
  final DateTime capturedAt;

  /// 64-lowercase-hex plaintext PNG hash for integrity.
  final String sha256;

  /// Whether this mark belongs to [field]: same id, same page, and the field
  /// is a signature field.
  bool describesField(ConfirmedField field) {
    return field.id == fieldId &&
        field.pageIndex == pageIndex &&
        field.type == FieldType.signature;
  }

  /// Returns a copy with the supplied fields replaced.
  SignatureMark copyWith({
    String? assetId,
    String? fieldId,
    int? pageIndex,
    Rect? rect,
    int? widthPx,
    int? heightPx,
    DateTime? capturedAt,
    String? sha256,
  }) {
    return SignatureMark(
      assetId: assetId ?? this.assetId,
      fieldId: fieldId ?? this.fieldId,
      pageIndex: pageIndex ?? this.pageIndex,
      rect: rect ?? this.rect,
      widthPx: widthPx ?? this.widthPx,
      heightPx: heightPx ?? this.heightPx,
      capturedAt: capturedAt ?? this.capturedAt,
      sha256: sha256 ?? this.sha256,
    );
  }

  /// Serializes to the persisted signature object.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'assetId': assetId,
      'fieldId': fieldId,
      'pageIndex': pageIndex,
      'rect': rect.toJson(),
      'widthPx': widthPx,
      'heightPx': heightPx,
      'capturedAt': _serializeTimestamp(capturedAt),
      'sha256': sha256,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is SignatureMark &&
        other.assetId == assetId &&
        other.fieldId == fieldId &&
        other.pageIndex == pageIndex &&
        other.rect == rect &&
        other.widthPx == widthPx &&
        other.heightPx == heightPx &&
        other.capturedAt == capturedAt &&
        other.sha256 == sha256;
  }

  @override
  int get hashCode {
    return Object.hash(
      assetId,
      fieldId,
      pageIndex,
      rect,
      widthPx,
      heightPx,
      capturedAt,
      sha256,
    );
  }

  @override
  String toString() {
    return 'SignatureMark(assetId: $assetId, fieldId: $fieldId, '
        'pageIndex: $pageIndex)';
  }
}

/// Per-field review state and warnings (`data-model.md` §3.8).
final class FieldVerification {
  /// Creates a verification record.
  ///
  /// [reviewedAt] is required for [FieldVerificationState.confirmed] and
  /// [FieldVerificationState.corrected], must be null for
  /// [FieldVerificationState.unreviewed], and must be UTC. [warnings] must be
  /// duplicate-free; the stored list is sorted by declaration order.
  ///
  /// Throws [ArgumentError] for every invalid value.
  factory FieldVerification({
    required FieldVerificationState state,
    DateTime? reviewedAt,
    Iterable<WarningCode> warnings = const <WarningCode>[],
  }) {
    final DateTime? checkedReviewedAt = reviewedAt == null
        ? null
        : _checkUtc(reviewedAt, 'reviewedAt');
    final bool requiresTimestamp =
        state == FieldVerificationState.confirmed ||
        state == FieldVerificationState.corrected;
    if (requiresTimestamp && checkedReviewedAt == null) {
      throw ArgumentError(
        'reviewedAt is required for the confirmed and corrected states',
      );
    }
    if (state == FieldVerificationState.unreviewed &&
        checkedReviewedAt != null) {
      throw ArgumentError('reviewedAt must be null for the unreviewed state');
    }
    final List<WarningCode> warningList = warnings.toList(growable: false);
    final Set<WarningCode> warningSet = warningList.toSet();
    if (warningSet.length != warningList.length) {
      throw ArgumentError('warnings must not contain duplicates');
    }
    final List<WarningCode> sorted = warningList.toList()
      ..sort((WarningCode a, WarningCode b) => a.index.compareTo(b.index));
    return FieldVerification._(
      state: state,
      reviewedAt: checkedReviewedAt,
      warnings: List<WarningCode>.unmodifiable(sorted),
    );
  }

  const FieldVerification._({
    required this.state,
    required this.reviewedAt,
    required this.warnings,
  });

  /// Reads a persisted verification record.
  ///
  /// Throws [FormatException] for missing, mistyped, or invalid fields.
  factory FieldVerification.fromJson(Map<String, Object?> json) {
    final Object? rawWarnings = json['warnings'];
    if (rawWarnings is! List<Object?>) {
      throw const FormatException('JSON field "warnings" must be an array');
    }
    try {
      return FieldVerification(
        state: FieldVerificationState.fromWire(json['state']),
        reviewedAt: _readOptionalTimestamp(json, 'reviewedAt'),
        warnings: <WarningCode>[
          for (final Object? warning in rawWarnings)
            WarningCode.fromWire(warning),
        ],
      );
    } on ArgumentError catch (error) {
      throw FormatException(
        'Invalid field verification JSON: ${error.message}',
      );
    }
  }

  /// The review state.
  final FieldVerificationState state;

  /// When the user reviewed the field; required for confirmed/corrected.
  final DateTime? reviewedAt;

  /// Non-blocking warnings, sorted by declaration order.
  final List<WarningCode> warnings;

  /// Returns a copy with the supplied fields replaced.
  ///
  /// [reviewedAt] must be passed explicitly to change it.
  FieldVerification copyWith({
    FieldVerificationState? state,
    Object? reviewedAt = _unset,
    Iterable<WarningCode>? warnings,
  }) {
    return FieldVerification(
      state: state ?? this.state,
      reviewedAt: identical(reviewedAt, _unset)
          ? this.reviewedAt
          : reviewedAt as DateTime?,
      warnings: warnings ?? this.warnings,
    );
  }

  /// Serializes to the persisted verification object.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'state': state.wireName,
      'reviewedAt': reviewedAt == null
          ? null
          : _serializeTimestamp(reviewedAt!),
      'warnings': <String>[
        for (final WarningCode warning in warnings) warning.wireName,
      ],
    };
  }

  @override
  bool operator ==(Object other) {
    return other is FieldVerification &&
        other.state == state &&
        other.reviewedAt == reviewedAt &&
        _listsEqual<WarningCode>(other.warnings, warnings);
  }

  @override
  int get hashCode {
    return Object.hash(state, reviewedAt, Object.hashAll(warnings));
  }

  @override
  String toString() {
    return 'FieldVerification(state: ${state.wireName}, '
        'warnings: ${warnings.length})';
  }
}

/// The validation state of a confirmed field (`data-model.md` §3.5):
/// `ok | warning(code, messageKey) | error(code)`.
sealed class FieldValidation {
  const FieldValidation._();

  /// The valid state: no warning or error.
  static const FieldValidation ok = _FieldValidationOk();

  /// A non-blocking warning with a German catalog message key.
  factory FieldValidation.warning(WarningCode code, String messageKey) {
    return _FieldValidationWarning(code, _validateMessageKey(messageKey));
  }

  /// A blocking error with a stable catalog code such as `NUM-001`.
  factory FieldValidation.error(String code) {
    return _FieldValidationError(_validateCatalogCode(code));
  }

  /// Reads a persisted validation object.
  ///
  /// Throws [FormatException] for missing, mistyped, or invalid fields.
  static FieldValidation fromJson(Map<String, Object?> json) {
    final Object? status = json['status'];
    try {
      if (status == 'ok') {
        return ok;
      }
      if (status == 'warning') {
        return FieldValidation.warning(
          WarningCode.fromWire(json['code']),
          _readString(json, 'messageKey'),
        );
      }
      if (status == 'error') {
        return FieldValidation.error(_readString(json, 'code'));
      }
    } on ArgumentError catch (error) {
      throw FormatException('Invalid field validation JSON: ${error.message}');
    }
    throw const FormatException('Unknown field validation status token.');
  }

  /// Whether this state is [ok].
  bool get isOk => this is _FieldValidationOk;

  /// Whether this state is a warning.
  bool get isWarning => this is _FieldValidationWarning;

  /// Whether this state is a blocking error.
  bool get isError => this is _FieldValidationError;

  /// The warning code, or null for ok and error states.
  WarningCode? get warningCode => null;

  /// The German message key, or null for ok and error states.
  String? get messageKey => null;

  /// The catalog error code, or null for ok and warning states.
  String? get errorCode => null;

  /// Serializes to the persisted validation object.
  Map<String, Object?> toJson();
}

final class _FieldValidationOk extends FieldValidation {
  const _FieldValidationOk() : super._();

  @override
  Map<String, Object?> toJson() => <String, Object?>{'status': 'ok'};

  @override
  bool operator ==(Object other) => other is _FieldValidationOk;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'FieldValidation.ok()';
}

final class _FieldValidationWarning extends FieldValidation {
  const _FieldValidationWarning(this.warningCode, this.messageKey) : super._();

  @override
  final WarningCode warningCode;

  @override
  final String messageKey;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': 'warning',
      'code': warningCode.wireName,
      'messageKey': messageKey,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is _FieldValidationWarning &&
        other.warningCode == warningCode &&
        other.messageKey == messageKey;
  }

  @override
  int get hashCode => Object.hash(warningCode, messageKey);

  @override
  String toString() {
    return 'FieldValidation.warning(${warningCode.wireName}, $messageKey)';
  }
}

final class _FieldValidationError extends FieldValidation {
  const _FieldValidationError(this.errorCode) : super._();

  @override
  final String errorCode;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{'status': 'error', 'code': errorCode};
  }

  @override
  bool operator ==(Object other) {
    return other is _FieldValidationError && other.errorCode == errorCode;
  }

  @override
  int get hashCode => errorCode.hashCode;

  @override
  String toString() => 'FieldValidation.error($errorCode)';
}

/// A committed field value: a tagged union on the field type
/// (`data-model.md` §3.6).
///
/// Every variant carries [lastEditedAt] (UTC) and [overflow]. Overflow is
/// derived at layout time, stored for status display, and never alters
/// content. Invalid numbers and dates are rejected before a value is
/// constructed (FR-108/SC-022); reclassification keeps incompatible content in
/// an [IncompatibleValue] instead of dropping it (FR-029/FR-038).
sealed class FieldValue {
  FieldValue({required DateTime lastEditedAt, required this.overflow})
    : lastEditedAt = _checkUtc(lastEditedAt, 'lastEditedAt');

  /// When the user last committed an edit, in UTC.
  final DateTime lastEditedAt;

  /// Whether the value overflowed its field at the last layout.
  final bool overflow;

  /// The compatible [FieldType], or null for [IncompatibleValue], which is
  /// content preserved after an incompatible reclassification.
  FieldType? get type;

  /// The stable JSON discriminator.
  String get kind;

  /// Returns a copy with only the metadata replaced.
  FieldValue copyWithMetadata({DateTime? lastEditedAt, bool? overflow});

  /// Serializes the value and its metadata.
  Map<String, Object?> toJson();

  /// Reads a persisted value.
  ///
  /// Throws [FormatException] for an unknown, missing, or mistyped
  /// discriminator or payload.
  static FieldValue fromJson(Map<String, Object?> json) {
    final String kind = _readString(json, 'type');
    final DateTime lastEditedAt = _readTimestamp(json, 'lastEditedAt');
    final bool overflow = _readBool(json, 'overflow');
    try {
      switch (kind) {
        case 'text':
          return TextValue(
            text: _readString(json, 'text'),
            lastEditedAt: lastEditedAt,
            overflow: overflow,
          );
        case 'number':
          return NumberValue(
            canonical: _readString(json, 'canonical'),
            rawGerman: _readString(json, 'rawGerman'),
            lastEditedAt: lastEditedAt,
            overflow: overflow,
          );
        case 'date':
          return DateValue(
            canonical: _readString(json, 'canonical'),
            lastEditedAt: lastEditedAt,
            overflow: overflow,
          );
        case 'checkbox':
          return CheckboxValue(
            checked: _readBool(json, 'checked'),
            lastEditedAt: lastEditedAt,
            overflow: overflow,
          );
        case 'multiline':
          return MultilineValue(
            text: _readString(json, 'text'),
            lastEditedAt: lastEditedAt,
            overflow: overflow,
          );
        case 'signature':
          return SignatureValue(
            signatureAssetId: _readString(json, 'signatureAssetId'),
            lastEditedAt: lastEditedAt,
            overflow: overflow,
          );
        case 'incompatible':
          return IncompatibleValue(
            preservedText: _readString(json, 'preservedText'),
            reasonCode: _readString(json, 'reasonCode'),
            lastEditedAt: lastEditedAt,
            overflow: overflow,
          );
        default:
          throw const FormatException('Unknown field value type token.');
      }
    } on ArgumentError catch (error) {
      throw FormatException('Invalid field value JSON: ${error.message}');
    }
  }
}

/// Single-line free text (`text`).
///
/// At most 10,000 characters and no control characters; line breaks are not
/// accepted because the `text` type removes them.
final class TextValue extends FieldValue {
  /// Creates a text value.
  ///
  /// Throws [ArgumentError] when [text] exceeds 10,000 characters or contains
  /// a control character, or when [lastEditedAt] is not UTC. The error never
  /// echoes the text.
  TextValue({
    required String text,
    required super.lastEditedAt,
    super.overflow = false,
  }) : text = _validateText(
         text,
         name: 'text',
         maxLength: _maxValueTextLength,
         allowNewlines: false,
       );

  /// The committed text; document content, never logged.
  final String text;

  @override
  FieldType get type => FieldType.text;

  @override
  String get kind => 'text';

  @override
  TextValue copyWithMetadata({DateTime? lastEditedAt, bool? overflow}) {
    return TextValue(
      text: text,
      lastEditedAt: lastEditedAt ?? this.lastEditedAt,
      overflow: overflow ?? this.overflow,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': kind,
      'text': text,
      'lastEditedAt': _serializeTimestamp(lastEditedAt),
      'overflow': overflow,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is TextValue &&
        other.text == text &&
        other.lastEditedAt == lastEditedAt &&
        other.overflow == overflow;
  }

  @override
  int get hashCode => Object.hash(text, lastEditedAt, overflow);

  @override
  String toString() {
    return 'TextValue(length: ${text.runes.length}, overflow: $overflow)';
  }
}

/// Normalized German number (`number`).
///
/// [canonical] matches `-?\d+(\.\d+)?` with no exponent; [rawGerman] is the
/// user's display input and is never used for computation.
final class NumberValue extends FieldValue {
  /// Creates a number value.
  ///
  /// Throws [ArgumentError] when [canonical] is not a normalized decimal,
  /// [rawGerman] is empty or contains a control character, or
  /// [lastEditedAt] is not UTC. The error never echoes the input.
  NumberValue({
    required String canonical,
    required String rawGerman,
    required super.lastEditedAt,
    super.overflow = false,
  }) : canonical = _validateCanonicalNumber(canonical),
       rawGerman = _validateDisplayText(rawGerman, name: 'rawGerman');

  /// Canonical decimal string; document content, never logged.
  final String canonical;

  /// Raw German display input; document content, never logged.
  final String rawGerman;

  @override
  FieldType get type => FieldType.number;

  @override
  String get kind => 'number';

  @override
  NumberValue copyWithMetadata({DateTime? lastEditedAt, bool? overflow}) {
    return NumberValue(
      canonical: canonical,
      rawGerman: rawGerman,
      lastEditedAt: lastEditedAt ?? this.lastEditedAt,
      overflow: overflow ?? this.overflow,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': kind,
      'canonical': canonical,
      'rawGerman': rawGerman,
      'lastEditedAt': _serializeTimestamp(lastEditedAt),
      'overflow': overflow,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is NumberValue &&
        other.canonical == canonical &&
        other.rawGerman == rawGerman &&
        other.lastEditedAt == lastEditedAt &&
        other.overflow == overflow;
  }

  @override
  int get hashCode => Object.hash(canonical, rawGerman, lastEditedAt, overflow);

  @override
  String toString() {
    return 'NumberValue(overflow: $overflow)';
  }
}

/// Canonical calendar date (`date`), stored as `YYYY-MM-DD`.
final class DateValue extends FieldValue {
  /// Creates a date value.
  ///
  /// Throws [ArgumentError] when [canonical] is not a real calendar date in
  /// `YYYY-MM-DD` form or when [lastEditedAt] is not UTC. The error never
  /// echoes the date.
  DateValue({
    required String canonical,
    required super.lastEditedAt,
    super.overflow = false,
  }) : canonical = _validateCanonicalDate(canonical);

  /// Canonical `YYYY-MM-DD`; document content, never logged.
  final String canonical;

  @override
  FieldType get type => FieldType.date;

  @override
  String get kind => 'date';

  @override
  DateValue copyWithMetadata({DateTime? lastEditedAt, bool? overflow}) {
    return DateValue(
      canonical: canonical,
      lastEditedAt: lastEditedAt ?? this.lastEditedAt,
      overflow: overflow ?? this.overflow,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': kind,
      'canonical': canonical,
      'lastEditedAt': _serializeTimestamp(lastEditedAt),
      'overflow': overflow,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is DateValue &&
        other.canonical == canonical &&
        other.lastEditedAt == lastEditedAt &&
        other.overflow == overflow;
  }

  @override
  int get hashCode => Object.hash(canonical, lastEditedAt, overflow);

  @override
  String toString() {
    return 'DateValue(overflow: $overflow)';
  }
}

/// Boolean checkbox state (`checkbox`).
final class CheckboxValue extends FieldValue {
  /// Creates a checkbox value; the default state is unchecked.
  CheckboxValue({
    this.checked = false,
    required super.lastEditedAt,
    super.overflow = false,
  });

  /// Whether the box is checked; document content, never logged.
  final bool checked;

  @override
  FieldType get type => FieldType.checkbox;

  @override
  String get kind => 'checkbox';

  @override
  CheckboxValue copyWithMetadata({DateTime? lastEditedAt, bool? overflow}) {
    return CheckboxValue(
      checked: checked,
      lastEditedAt: lastEditedAt ?? this.lastEditedAt,
      overflow: overflow ?? this.overflow,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': kind,
      'checked': checked,
      'lastEditedAt': _serializeTimestamp(lastEditedAt),
      'overflow': overflow,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is CheckboxValue &&
        other.checked == checked &&
        other.lastEditedAt == lastEditedAt &&
        other.overflow == overflow;
  }

  @override
  int get hashCode => Object.hash(checked, lastEditedAt, overflow);

  @override
  String toString() => 'CheckboxValue(overflow: $overflow)';
}

/// Multiline text (`multiline`) with line breaks preserved.
///
/// At most 10,000 characters. `\n` is preserved; other control characters are
/// rejected.
final class MultilineValue extends FieldValue {
  /// Creates a multiline value.
  ///
  /// Throws [ArgumentError] when [text] exceeds 10,000 characters or contains
  /// a control character other than `\n`, or when [lastEditedAt] is not UTC.
  /// The error never echoes the text.
  MultilineValue({
    required String text,
    required super.lastEditedAt,
    super.overflow = false,
  }) : text = _validateText(
         text,
         name: 'text',
         maxLength: _maxValueTextLength,
         allowNewlines: true,
       );

  /// The committed text; document content, never logged.
  final String text;

  @override
  FieldType get type => FieldType.multiline;

  @override
  String get kind => 'multiline';

  @override
  MultilineValue copyWithMetadata({DateTime? lastEditedAt, bool? overflow}) {
    return MultilineValue(
      text: text,
      lastEditedAt: lastEditedAt ?? this.lastEditedAt,
      overflow: overflow ?? this.overflow,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': kind,
      'text': text,
      'lastEditedAt': _serializeTimestamp(lastEditedAt),
      'overflow': overflow,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is MultilineValue &&
        other.text == text &&
        other.lastEditedAt == lastEditedAt &&
        other.overflow == overflow;
  }

  @override
  int get hashCode => Object.hash(text, lastEditedAt, overflow);

  @override
  String toString() {
    return 'MultilineValue(length: ${text.runes.length}, overflow: $overflow)';
  }
}

/// A reference to a [SignatureMark] (`signature`); no text value.
final class SignatureValue extends FieldValue {
  /// Creates a signature value.
  ///
  /// Throws [ArgumentError] when [signatureAssetId] is not a lowercase UUIDv4
  /// or when [lastEditedAt] is not UTC.
  SignatureValue({
    required String signatureAssetId,
    required super.lastEditedAt,
    super.overflow = false,
  }) : signatureAssetId = _validateUuidV4(signatureAssetId, 'signatureAssetId');

  /// UUIDv4 of the signature asset in the same document.
  final String signatureAssetId;

  @override
  FieldType get type => FieldType.signature;

  @override
  String get kind => 'signature';

  @override
  SignatureValue copyWithMetadata({DateTime? lastEditedAt, bool? overflow}) {
    return SignatureValue(
      signatureAssetId: signatureAssetId,
      lastEditedAt: lastEditedAt ?? this.lastEditedAt,
      overflow: overflow ?? this.overflow,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': kind,
      'signatureAssetId': signatureAssetId,
      'lastEditedAt': _serializeTimestamp(lastEditedAt),
      'overflow': overflow,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is SignatureValue &&
        other.signatureAssetId == signatureAssetId &&
        other.lastEditedAt == lastEditedAt &&
        other.overflow == overflow;
  }

  @override
  int get hashCode => Object.hash(signatureAssetId, lastEditedAt, overflow);

  @override
  String toString() {
    return 'SignatureValue(overflow: $overflow)';
  }
}

/// Content preserved after an incompatible reclassification
/// (`data-model.md` §3.5–§3.6).
///
/// The original text is kept verbatim and is never deleted, truncated, or
/// altered by the reclassification (FR-029/FR-038). [reasonCode] is a stable
/// machine token; it never contains content.
final class IncompatibleValue extends FieldValue {
  /// Creates a preserved-content value.
  ///
  /// [preservedText] is kept verbatim, may contain any characters (including
  /// line breaks and other control characters), and is at most 10,000
  /// characters. [reasonCode] is a lowercase machine token.
  ///
  /// Throws [ArgumentError] for an invalid length, reason code, or
  /// non-UTC [lastEditedAt]. The error never echoes preserved content.
  IncompatibleValue({
    required String preservedText,
    required String reasonCode,
    required super.lastEditedAt,
    super.overflow = false,
  }) : preservedText = _validatePreservedText(preservedText),
       reasonCode = _validateMachineToken(reasonCode, 'reasonCode');

  /// The content preserved exactly as entered; document content, never
  /// logged.
  final String preservedText;

  /// Stable machine token describing why the content is incompatible.
  final String reasonCode;

  @override
  FieldType? get type => null;

  @override
  String get kind => 'incompatible';

  @override
  IncompatibleValue copyWithMetadata({DateTime? lastEditedAt, bool? overflow}) {
    return IncompatibleValue(
      preservedText: preservedText,
      reasonCode: reasonCode,
      lastEditedAt: lastEditedAt ?? this.lastEditedAt,
      overflow: overflow ?? this.overflow,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': kind,
      'preservedText': preservedText,
      'reasonCode': reasonCode,
      'lastEditedAt': _serializeTimestamp(lastEditedAt),
      'overflow': overflow,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is IncompatibleValue &&
        other.preservedText == preservedText &&
        other.reasonCode == reasonCode &&
        other.lastEditedAt == lastEditedAt &&
        other.overflow == overflow;
  }

  @override
  int get hashCode {
    return Object.hash(preservedText, reasonCode, lastEditedAt, overflow);
  }

  @override
  String toString() {
    return 'IncompatibleValue(reasonCode: $reasonCode, '
        'length: ${preservedText.runes.length})';
  }
}

/// The maximum length of a text or multiline value in characters.
const int _maxValueTextLength = 10000;

/// The page-bounds tolerance in PDF points from `data-model.md` §2.1.
///
/// A rectangle outside by more than this tolerance is a validation error;
/// clamping is never silent.
const double pageBoundsTolerance = 0.5;

/// Sentinel used by `copyWith` methods to distinguish "not supplied" from an
/// explicit `null`.
const Object _unset = Object();

final RegExp _suggestionIdPattern = RegExp(r'^s_p(\d+)_(\d{4,})$');
final RegExp _canonicalNumberPattern = RegExp(r'^-?\d+(\.\d+)?$');
final RegExp _canonicalDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final RegExp _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
final RegExp _catalogCodePattern = RegExp(r'^[A-Z]{2,6}-[0-9]{3}$');
final RegExp _messageKeyPattern = RegExp(r'^[A-Za-z][A-Za-z0-9_.-]*$');
final RegExp _machineTokenPattern = RegExp(r'^[a-z][a-z0-9_]*$');

int _checkPageIndex(int value) {
  if (value < 0) {
    throw ArgumentError('pageIndex must be at least 0');
  }
  return value;
}

double _checkUnitInterval(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError('$name must be finite and between 0 and 1');
  }
  return value;
}

DateTime _checkUtc(DateTime value, String name) {
  if (!value.isUtc) {
    throw ArgumentError('$name must be UTC');
  }
  return value;
}

String _validateSuggestionId(String value, int pageIndex) {
  final RegExpMatch? match = _suggestionIdPattern.firstMatch(value);
  if (match == null) {
    throw ArgumentError('id must use the s_p<pageIndex>_<ordinal> form');
  }
  final int embeddedPage = int.parse(match.group(1)!);
  if (embeddedPage != pageIndex) {
    throw ArgumentError('id must embed the suggestion page index');
  }
  if (int.parse(match.group(2)!) < 1) {
    throw ArgumentError('id ordinal must be at least 1');
  }
  return value;
}

String _validateFieldId(String value) {
  if (value.isEmpty) {
    throw ArgumentError('id must not be empty');
  }
  if (value.runes.length > 128) {
    throw ArgumentError('id must be at most 128 characters');
  }
  for (final int rune in value.runes) {
    if (rune <= 0x20 || rune == 0x7F) {
      throw ArgumentError(
        'id must not contain whitespace or control characters',
      );
    }
  }
  return value;
}

String? _normalizeOptionalLabel(
  String? value, {
  required int maxLength,
  required String name,
}) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (trimmed.runes.length > maxLength) {
    throw ArgumentError('$name must be at most $maxLength characters');
  }
  _checkNoControlCharacters(trimmed, name);
  return trimmed;
}

String _normalizeRequiredLabel(
  String value, {
  required int maxLength,
  required String name,
}) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError('$name must not be empty');
  }
  if (trimmed.runes.length > maxLength) {
    throw ArgumentError('$name must be at most $maxLength characters');
  }
  _checkNoControlCharacters(trimmed, name);
  return trimmed;
}

List<String> _normalizeConflicts(Iterable<String> values, String ownId) {
  final List<String> result = values.toList(growable: false);
  final Set<String> unique = result.toSet();
  if (unique.length != result.length) {
    throw ArgumentError('conflictsWith must not contain duplicates');
  }
  for (final String id in result) {
    if (id == ownId) {
      throw ArgumentError(
        'conflictsWith must not reference the suggestion itself',
      );
    }
    if (!_suggestionIdPattern.hasMatch(id)) {
      throw ArgumentError(
        'conflictsWith must contain s_p<pageIndex>_<ordinal> ids',
      );
    }
  }
  return List<String>.unmodifiable(result..sort());
}

void _checkNoControlCharacters(String value, String name) {
  for (final int rune in value.runes) {
    if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) {
      throw ArgumentError('$name must not contain control characters');
    }
  }
}

String _validateText(
  String value, {
  required String name,
  required int maxLength,
  required bool allowNewlines,
}) {
  if (value.runes.length > maxLength) {
    throw ArgumentError('$name must be at most $maxLength characters');
  }
  for (final int rune in value.runes) {
    if (allowNewlines && rune == 0x0A) {
      continue;
    }
    if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) {
      throw ArgumentError('$name must not contain control characters');
    }
  }
  return value;
}

String _validateDisplayText(String value, {required String name}) {
  if (value.isEmpty) {
    throw ArgumentError('$name must not be empty');
  }
  _checkNoControlCharacters(value, name);
  return value;
}

String _validatePreservedText(String value) {
  if (value.runes.length > _maxValueTextLength) {
    throw ArgumentError(
      'preservedText must be at most $_maxValueTextLength characters',
    );
  }
  return value;
}

String _validateMachineToken(String value, String name) {
  if (!_machineTokenPattern.hasMatch(value)) {
    throw ArgumentError('$name must be a lowercase machine token');
  }
  return value;
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

String _validateCatalogCode(String value) {
  if (!_catalogCodePattern.hasMatch(value)) {
    throw ArgumentError('code must be a catalog code such as NUM-001');
  }
  return value;
}

String _validateMessageKey(String value) {
  if (!_messageKeyPattern.hasMatch(value)) {
    throw ArgumentError('messageKey must be a stable message key');
  }
  return value;
}

String _validateCanonicalNumber(String value) {
  if (!_canonicalNumberPattern.hasMatch(value)) {
    throw ArgumentError(
      'canonical must be a decimal number with a dot and no exponent',
    );
  }
  return value;
}

String _validateCanonicalDate(String value) {
  final RegExpMatch? match = _canonicalDatePattern.firstMatch(value);
  if (match == null) {
    throw ArgumentError('canonical must be a YYYY-MM-DD date');
  }
  final int year = int.parse(match.group(1)!);
  final int month = int.parse(match.group(2)!);
  final int day = int.parse(match.group(3)!);
  final DateTime parsed = DateTime.utc(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    throw ArgumentError('canonical must be a real calendar date');
  }
  return value;
}

bool _fitsWithinPage(Rect rect, Size displaySize) {
  return rect.left >= -pageBoundsTolerance &&
      rect.top >= -pageBoundsTolerance &&
      rect.right <= displaySize.width + pageBoundsTolerance &&
      rect.bottom <= displaySize.height + pageBoundsTolerance;
}

bool _setsEqual<T>(Set<T> a, Set<T> b) {
  return a.length == b.length && a.containsAll(b);
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

T _enumFromWire<T extends Enum>(
  List<T> values,
  String Function(T value) wireName,
  Object? token,
) {
  if (token is String) {
    for (final T value in values) {
      if (wireName(value) == token) {
        return value;
      }
    }
  }
  throw const FormatException('Unknown enum token.');
}

String _serializeTimestamp(DateTime value) {
  return DateTime.fromMillisecondsSinceEpoch(
    value.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}

DateTime _readTimestamp(Map<String, Object?> json, String key) {
  final String value = _readString(json, key);
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException(
      'JSON field "$key" must be an ISO-8601 UTC timestamp',
    );
  }
  return parsed;
}

DateTime? _readOptionalTimestamp(Map<String, Object?> json, String key) {
  if (json[key] == null) {
    return null;
  }
  return _readTimestamp(json, key);
}

Map<String, Object?> _readObject(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('JSON field "$key" must be an object');
  }
  return value;
}

String _readString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String) {
    throw FormatException('JSON field "$key" must be a string');
  }
  return value;
}

String? _readOptionalString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('JSON field "$key" must be a string or null');
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

double _readDouble(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! num) {
    throw FormatException('JSON field "$key" must be a number');
  }
  final double result = value.toDouble();
  if (!result.isFinite) {
    throw FormatException('JSON field "$key" must be finite');
  }
  return result;
}

double? _readOptionalDouble(Map<String, Object?> json, String key) {
  if (json[key] == null) {
    return null;
  }
  return _readDouble(json, key);
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
