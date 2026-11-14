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
import 'canonical_json.dart';

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

/// A recognition-evidence cue from `contracts/recognition-output.md` §3.1.
///
/// This type represents the contract's wire vocabulary losslessly. The fixed
/// cues are constants, and a keyword cue carries its lexicon key, so
/// `keyword_<key>` is never flattened into a generic token. The data-model
/// §3.4 list (`line`, `box`, `grid`, `whitespace`, `ocr_alignment`, `keyword`)
/// is a coarse source taxonomy: [line] and [grid] are Dart aliases for
/// [underline] and [gridCell] but are not contract wire tokens and are read
/// only by [fromLegacyWire] during migration. The ambiguous `ocr_alignment`
/// and keyless `keyword` spellings are never accepted. Visible non-ASCII
/// keyword keys such as `straße` remain representable.
sealed class SuggestionCue implements Comparable<SuggestionCue> {
  const SuggestionCue._(this.order);

  /// A horizontal rule directly below the candidate region.
  static const SuggestionCue underline = _SimpleSuggestionCue('underline', 0);

  /// A closed rectangle enclosing the candidate.
  static const SuggestionCue box = _SimpleSuggestionCue('box', 1);

  /// A cell of a detected table grid.
  static const SuggestionCue gridCell = _SimpleSuggestionCue('grid_cell', 2);

  /// Bounded empty background adjacent to printed content.
  static const SuggestionCue whitespace = _SimpleSuggestionCue('whitespace', 3);

  /// The candidate left edge aligns with sibling candidates or labels.
  static const SuggestionCue alignmentLeft = _SimpleSuggestionCue(
    'alignment_left',
    4,
  );

  /// The label is directly below the candidate (for example a signature line).
  static const SuggestionCue labelBelow = _SimpleSuggestionCue(
    'label_below',
    5,
  );

  /// The candidate is to the right of an OCR label line.
  static const SuggestionCue ocrAlignmentRight = _SimpleSuggestionCue(
    'ocr_alignment_right',
    6,
  );

  /// The candidate is below an OCR label line.
  static const SuggestionCue ocrAlignmentBelow = _SimpleSuggestionCue(
    'ocr_alignment_below',
    7,
  );

  /// A near-square 4–20 pt low-ink region.
  static const SuggestionCue smallSquare = _SimpleSuggestionCue(
    'small_square',
    9,
  );

  /// A cell addressable individually within a detected table grid.
  static const SuggestionCue tableCell = _SimpleSuggestionCue('table_cell', 10);

  /// A large low-ink region labelled as a signature area.
  static const SuggestionCue signatureArea = _SimpleSuggestionCue(
    'signature_area',
    11,
  );

  /// An adjacent label or printed pattern implies digits.
  static const SuggestionCue numericContext = _SimpleSuggestionCue(
    'numeric_context',
    12,
  );

  /// An adjacent label or printed date mask (`TT.MM.JJJJ`) implies a date.
  static const SuggestionCue dateContext = _SimpleSuggestionCue(
    'date_context',
    13,
  );

  /// Data-model §3.4 coarse alias for [underline].
  static const SuggestionCue line = underline;

  /// Data-model §3.4 coarse alias for [gridCell].
  static const SuggestionCue grid = gridCell;

  /// The closed keyword lexicon v1 from `contracts/recognition-output.md`
  /// §3.1, normalized to lowercase.
  ///
  /// [SuggestionCue.keyword] accepts only these keys (case-insensitively), and
  /// [fromWire] accepts only `keyword_<key>` tokens built from them. A later
  /// lexicon version must extend this set explicitly; arbitrary keys are not
  /// valid wire cues.
  static const Set<String> keywordLexiconV1 = <String>{
    'name',
    'vorname',
    'nachname',
    'familienname',
    'geburtsdatum',
    'geburtsort',
    'datum',
    'straße',
    'strasse',
    'hausnummer',
    'plz',
    'postleitzahl',
    'ort',
    'wohnort',
    'telefon',
    'telefax',
    'e-mail',
    'email',
    'iban',
    'bic',
    'bank',
    'konto',
    'steuernummer',
    'steuer-id',
    'aktenzeichen',
    'geschäftszeichen',
    'antrag',
    'betrag',
    'summe',
    'unterschrift',
    'datum/unterschrift',
    'monat',
    'jahr',
    'zeitraum',
    'von',
    'bis',
  };

  /// Wire names of cues whose evidence is geometric and therefore satisfies
  /// the §2.1 requirement that every suggestion carry at least one geometric
  /// cue.
  ///
  /// `signature_area` is OCR+geometry (§3.1); its low-ink region is the
  /// geometric evidence. OCR-alignment, label, and keyword cues are not
  /// geometric on their own.
  static const Set<String> _geometricWireNames = <String>{
    'underline',
    'box',
    'grid_cell',
    'whitespace',
    'alignment_left',
    'small_square',
    'table_cell',
    'signature_area',
  };

  /// Whether this cue is geometric evidence.
  bool get isGeometric => _geometricWireNames.contains(wireName);

  /// Creates a `keyword_<key>` cue.
  ///
  /// [key] is the lexicon key. It is trimmed and lowercased for canonical
  /// determinism (the §3.1 lexicon is case-insensitive) and must be a member
  /// of [keywordLexiconV1]; visible German punctuation and letters (`straße`,
  /// `e-mail`, `datum/unterschrift`) are part of that closed list.
  ///
  /// Throws [ArgumentError] for a key outside the lexicon or containing
  /// whitespace, control, or invisible characters.
  factory SuggestionCue.keyword(String key) {
    return _KeywordSuggestionCue(_normalizeKeywordKey(key));
  }

  /// Declaration order from `contracts/recognition-output.md` §3.1.
  ///
  /// Used for deterministic cue sorting. Keyword cues share order 8 and are
  /// then ordered by their key.
  final int order;

  /// Stable wire token from `contracts/recognition-output.md` §3.1.
  String get wireName;

  /// Tie-breaker after [order]; empty for fixed cues.
  String get _sortKey;

  /// Whether this cue depends on OCR evidence.
  ///
  /// When [SuggestionEvidence.ocrUsed] is false, only cues with this getter
  /// false may appear. `signature_area` is OCR+geometry (§3.1), so it is
  /// geometric for the §2.1 requirement but still requires OCR.
  bool get requiresOcr;

  @override
  int compareTo(SuggestionCue other) {
    final int byOrder = order.compareTo(other.order);
    if (byOrder != 0) {
      return byOrder;
    }
    return _sortKey.compareTo(other._sortKey);
  }

  /// Parses a wire token.
  ///
  /// Accepts every exact §3.1 token, including `keyword_<key>` for a key in
  /// [keywordLexiconV1]. The data-model aliases `line` and `grid` are not
  /// contract wire tokens; only [fromLegacyWire] reads them during migration.
  /// Throws [FormatException] for a non-string, unknown, ambiguous
  /// (`ocr_alignment`), keyless (`keyword`), legacy-alias, or out-of-lexicon
  /// keyword token.
  static SuggestionCue fromWire(Object? token) {
    if (token is String) {
      for (final SuggestionCue cue in _fixedCues) {
        if (cue.wireName == token) {
          return cue;
        }
      }
      if (token.startsWith(_keywordPrefix) &&
          token.length > _keywordPrefix.length) {
        try {
          return SuggestionCue.keyword(token.substring(_keywordPrefix.length));
        } on ArgumentError {
          throw const FormatException('Invalid keyword cue token.');
        }
      }
    }
    throw const FormatException('Unknown suggestion cue token.');
  }

  /// Parses a pre-contract wire token during explicit migration.
  ///
  /// Accepts the strict §3.1 vocabulary plus the data-model aliases `line` and
  /// `grid`, which canonicalize to [underline] and [gridCell]. This is the
  /// only path that reads those legacy spellings; [fromWire] stays strict.
  static SuggestionCue fromLegacyWire(Object? token) {
    if (token == 'line') {
      return underline;
    }
    if (token == 'grid') {
      return gridCell;
    }
    return fromWire(token);
  }

  static const String _keywordPrefix = 'keyword_';

  static const List<SuggestionCue> _fixedCues = <SuggestionCue>[
    underline,
    box,
    gridCell,
    whitespace,
    alignmentLeft,
    labelBelow,
    ocrAlignmentRight,
    ocrAlignmentBelow,
    smallSquare,
    tableCell,
    signatureArea,
    numericContext,
    dateContext,
  ];
}

const int _keywordCueOrder = 8;

final class _SimpleSuggestionCue extends SuggestionCue {
  const _SimpleSuggestionCue(this.wireName, int order) : super._(order);

  @override
  final String wireName;

  @override
  String get _sortKey => '';

  static const Set<String> _ocrDependentWireNames = <String>{
    'label_below',
    'ocr_alignment_right',
    'ocr_alignment_below',
    'signature_area',
    'numeric_context',
    'date_context',
  };

  @override
  bool get requiresOcr => _ocrDependentWireNames.contains(wireName);

  @override
  bool operator ==(Object other) {
    return other is _SimpleSuggestionCue && other.wireName == wireName;
  }

  @override
  int get hashCode => wireName.hashCode;

  @override
  String toString() => 'SuggestionCue.$wireName';
}

final class _KeywordSuggestionCue extends SuggestionCue {
  const _KeywordSuggestionCue(this.key) : super._(_keywordCueOrder);

  final String key;

  @override
  String get wireName => 'keyword_$key';

  @override
  String get _sortKey => key;

  @override
  bool get requiresOcr => true;

  @override
  bool operator ==(Object other) {
    return other is _KeywordSuggestionCue && other.key == key;
  }

  @override
  int get hashCode => Object.hash('keyword', key);

  @override
  String toString() => 'SuggestionCue.keyword($key)';
}

String _normalizeKeywordKey(String key) {
  final String normalized = key.trim().toLowerCase();
  if (normalized.isEmpty) {
    throw ArgumentError('keyword key must not be empty');
  }
  if (normalized.runes.length > 64) {
    throw ArgumentError('keyword key must be at most 64 characters');
  }
  for (final int rune in normalized.runes) {
    if (rune < 0x20 ||
        (rune >= 0x7F && rune <= 0x9F) ||
        _isUnicodeWhitespace(rune) ||
        _isInvisibleCodePoint(rune)) {
      throw ArgumentError(
        'keyword key must not contain whitespace, control, or invisible '
        'characters',
      );
    }
  }
  if (!SuggestionCue.keywordLexiconV1.contains(normalized)) {
    throw ArgumentError('keyword key is not in the recognition v1 lexicon');
  }
  return normalized;
}

/// Page contrast reported by recognition (`contracts/recognition-output.md`
/// §2–§3).
enum EvidenceContrast {
  /// Normal contrast.
  normal('normal'),

  /// Low contrast; caps suggestion confidence.
  low('low');

  const EvidenceContrast(this.wireName);

  /// Stable JSON token.
  final String wireName;

  /// Parses a JSON token.
  ///
  /// Throws [FormatException] for a non-string or unknown token.
  static EvidenceContrast fromWire(Object? token) {
    return _enumFromWire(
      values,
      (EvidenceContrast value) => value.wireName,
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
/// [cues] is a non-empty, duplicate-free set that includes at least one
/// geometric cue; §2.1 forbids OCR-only suggestions. When [ocrUsed] is false,
/// every cue must also be OCR-independent (geometry-only detection).
/// [cueAgreement] counts independent cue families and is at least one; the
/// contract defines no upper bound or family partition. [skewDegrees] is the
/// estimated page skew in degrees on the closed interval `-10 … 10`.
/// [contrast] is the contract's `normal | low` page contrast, and [ocrUsed] is
/// false when OCR failed and geometry-only detection ran. Unknown same-schema
/// JSON fields are retained across a read/write round (`data-model.md` §6).
final class SuggestionEvidence extends JsonObject {
  /// Creates evidence for a candidate.
  ///
  /// [unknownFields] are opaque same-schema JSON extensions retained for a
  /// later write.
  ///
  /// Throws [ArgumentError] when [cues] is empty, contains duplicates, or has
  /// no geometric cue, when [ocrUsed] is false and a cue depends on OCR, when
  /// [cueAgreement] is less than one, or when [skewDegrees] is non-finite or
  /// outside `-10 … 10`.
  factory SuggestionEvidence({
    required Iterable<SuggestionCue> cues,
    int cueAgreement = 1,
    double skewDegrees = 0,
    EvidenceContrast contrast = EvidenceContrast.normal,
    bool ocrUsed = true,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    final List<SuggestionCue> cueList = cues.toList(growable: false);
    final Set<SuggestionCue> cueSet = cueList.toSet();
    if (cueSet.isEmpty) {
      throw ArgumentError('cues must contain at least one cue');
    }
    if (cueSet.length != cueList.length) {
      throw ArgumentError('cues must not contain duplicates');
    }
    // recognition-output §2.1: no suggestion may be generated from OCR text
    // alone; at least one geometric cue must support it.
    if (!cueSet.any((SuggestionCue cue) => cue.isGeometric)) {
      throw ArgumentError(
        'evidence must include at least one geometric cue; '
        '§2.1 forbids OCR-only suggestions',
      );
    }
    // Geometry-only detection (ocrUsed == false) cannot be supported by an
    // OCR-dependent cue. signature_area is geometric for §2.1, but the
    // signature label itself still needs OCR.
    if (!ocrUsed) {
      for (final SuggestionCue cue in cueSet) {
        if (cue.requiresOcr) {
          throw ArgumentError(
            'ocrUsed is false but the evidence contains an OCR-dependent cue',
          );
        }
      }
    }
    // recognition-output §2 defines cueAgreement as the number of independent
    // cue families supporting the candidate with a lower bound of 1. The
    // contract defines no family partition and no upper bound; §3.1's Source
    // column is not normative family membership (signature_area is explicitly
    // OCR + geometry). The model therefore enforces only the stated lower
    // bound, and the producer remains responsible for the family count.
    if (cueAgreement < 1) {
      throw ArgumentError('cueAgreement must be at least 1');
    }
    if (!skewDegrees.isFinite || skewDegrees < -10 || skewDegrees > 10) {
      throw ArgumentError('skewDegrees must be finite and between -10 and 10');
    }
    final List<SuggestionCue> sorted = cueSet.toList()
      ..sort((SuggestionCue a, SuggestionCue b) => a.compareTo(b));
    return SuggestionEvidence._(
      cues: Set<SuggestionCue>.unmodifiable(sorted),
      cueAgreement: cueAgreement,
      skewDegrees: skewDegrees,
      contrast: contrast,
      ocrUsed: ocrUsed,
      unknownFields: Map<String, Object?>.unmodifiable(unknownFields),
    );
  }

  const SuggestionEvidence._({
    required this.cues,
    required this.cueAgreement,
    required this.skewDegrees,
    required this.contrast,
    required this.ocrUsed,
    required super.unknownFields,
  });

  /// Decodes the recognition-output §2 evidence object.
  ///
  /// `contrast` is required. Use [fromLegacyJson] for the pre-contract
  /// `lowContrast` boolean shape.
  ///
  /// Throws [FormatException] for missing, mistyped, or out-of-range fields.
  factory SuggestionEvidence.fromJson(Map<String, Object?> json) {
    return SuggestionEvidence._decode(json, allowLegacy: false);
  }

  /// Decodes a pre-contract evidence object that used `lowContrast`.
  ///
  /// The next write emits the contract `contrast` key. A present but invalid
  /// `contrast` (including null) is still rejected rather than falling back.
  factory SuggestionEvidence.fromLegacyJson(Map<String, Object?> json) {
    return SuggestionEvidence._decode(json, allowLegacy: true);
  }

  static SuggestionEvidence _decode(
    Map<String, Object?> json, {
    required bool allowLegacy,
  }) {
    final Object? rawCues = json['cues'];
    if (rawCues is! List<Object?>) {
      throw const FormatException('JSON field "cues" must be an array');
    }
    final List<SuggestionCue> cues = <SuggestionCue>[
      for (final Object? cue in rawCues)
        allowLegacy
            ? SuggestionCue.fromLegacyWire(cue)
            : SuggestionCue.fromWire(cue),
    ];
    final EvidenceContrast contrast = _readEvidenceContrast(
      json,
      allowLegacy: allowLegacy,
    );
    try {
      return SuggestionEvidence(
        cues: cues,
        cueAgreement: _readInt(json, 'cueAgreement'),
        skewDegrees: _readDouble(json, 'skewDegrees'),
        contrast: contrast,
        ocrUsed: _readBool(json, 'ocrUsed'),
        unknownFields: unknownJsonFields(json, _suggestionEvidenceJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException(
        'Invalid suggestion evidence JSON: ${error.message}',
      );
    }
  }

  /// Unique cue flags, sorted by §3.1 declaration order and then by keyword
  /// key.
  final Set<SuggestionCue> cues;

  /// Number of independent cue families supporting the candidate; at least 1.
  ///
  /// The contract defines no upper bound or one-token/one-family mapping;
  /// `signature_area` is explicitly OCR + geometry.
  final int cueAgreement;

  /// Estimated page skew in degrees on `-10 … 10`.
  final double skewDegrees;

  /// Page contrast as reported by recognition.
  final EvidenceContrast contrast;

  /// Whether [contrast] is [EvidenceContrast.low].
  bool get lowContrast => contrast == EvidenceContrast.low;

  /// Whether OCR supplied evidence, as opposed to geometry-only detection.
  ///
  /// When false, [cues] must contain only OCR-independent cues; keyword,
  /// OCR-alignment, label, context, and signature-area cues are rejected.
  final bool ocrUsed;

  /// Whether the optional signature-area cue is present.
  bool get hasSignatureCue => cues.contains(SuggestionCue.signatureArea);

  /// Serializes to the persisted evidence object.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'cues': <String>[for (final SuggestionCue cue in cues) cue.wireName],
      'cueAgreement': cueAgreement,
      'skewDegrees': skewDegrees,
      'contrast': contrast.wireName,
      'ocrUsed': ocrUsed,
    });
  }

  @override
  bool operator ==(Object other) {
    return other is SuggestionEvidence &&
        other.cueAgreement == cueAgreement &&
        other.skewDegrees == skewDegrees &&
        other.contrast == contrast &&
        other.ocrUsed == ocrUsed &&
        _setsEqual<SuggestionCue>(other.cues, cues);
  }

  @override
  int get hashCode {
    return Object.hash(
      Object.hashAllUnordered(cues),
      cueAgreement,
      skewDegrees,
      contrast,
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
///
/// The JSON form follows `contracts/recognition-output.md` §2 for the shared
/// suggestion fields: `confidence`, the derived `uncertainty`, the contract cue
/// vocabulary, and `evidence.contrast` (`normal | low`). Envelope-only fields
/// (`schemaVersion`, `analysisRunId`, `timings`, `evidenceClass`) belong to
/// T057's `FieldSuggestionSet` and are not part of this model. Unknown
/// same-schema JSON fields are retained across a read/write round
/// (`data-model.md` §6).
final class FieldSuggestion extends JsonObject {
  /// Creates a suggestion.
  ///
  /// [id] must use the deterministic `s_p<pageIndex>_<ordinal>` form with
  /// [pageIndex] in plain decimal and a one-based ordinal zero-padded to at
  /// least four digits; it must embed [pageIndex]. The contract has exactly
  /// one spelling per suggestion, so padding aliases such as `s_p00_0001` or
  /// `s_p0_00001` are rejected. [rect] is rounded to the canonical 1/8 pt grid
  /// required by `contracts/recognition-output.md` §2 and §5.4 before it is
  /// stored; confirmed-field geometry is never rounded (FR-024).
  /// [confidence] is on `0.0 … 1.0` with at most
  /// two decimal places (`contracts/recognition-output.md` §2). [labelText] is
  /// trimmed, must contain no control characters, and is at most 200
  /// characters; null or blank means no credible label. A
  /// [FieldType.signature] suggestion requires the
  /// [SuggestionCue.signatureArea] cue. [conflictsWith] must reference other
  /// canonical same-page suggestion ids with positive ordinals, contain no
  /// duplicates, and never reference [id]. [unknownFields] are opaque
  /// same-schema JSON extensions retained for a later write.
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
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    final int checkedPage = _checkPageIndex(pageIndex);
    final String checkedId = _validateSuggestionId(id, checkedPage);
    final double checkedConfidence = _checkTwoDecimalConfidence(
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
      checkedPage,
    );
    if (proposedType == FieldType.signature && !evidence.hasSignatureCue) {
      throw ArgumentError(
        'A signature suggestion requires the signature_area cue',
      );
    }
    return FieldSuggestion._(
      id: checkedId,
      pageIndex: checkedPage,
      rect: canonicalRect(rect),
      proposedType: proposedType,
      confidence: checkedConfidence,
      labelText: checkedLabel,
      evidence: evidence,
      conflictsWith: checkedConflicts,
      resolution: resolution,
      unknownFields: Map<String, Object?>.unmodifiable(unknownFields),
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
    required super.unknownFields,
  });

  /// Decodes the recognition-output §2 suggestion object.
  ///
  /// `uncertainty` is required and must be numeric and equal to
  /// `1 - confidence`; the evidence must carry the contract `contrast` key.
  /// Use [fromLegacyJson] for a pre-contract persisted object.
  ///
  /// Throws [FormatException] for missing, mistyped, or invalid fields.
  factory FieldSuggestion.fromJson(Map<String, Object?> json) {
    return FieldSuggestion._decode(json, allowLegacy: false);
  }

  /// Decodes a pre-contract suggestion object.
  ///
  /// A missing `uncertainty` key is derived from confidence and the evidence
  /// may use the legacy `lowContrast` boolean; the next write emits the
  /// canonical contract shape. An explicit null is still rejected.
  factory FieldSuggestion.fromLegacyJson(Map<String, Object?> json) {
    return FieldSuggestion._decode(json, allowLegacy: true);
  }

  static FieldSuggestion _decode(
    Map<String, Object?> json, {
    required bool allowLegacy,
  }) {
    try {
      final FieldSuggestion suggestion = FieldSuggestion(
        id: _readString(json, 'id'),
        pageIndex: _readInt(json, 'pageIndex'),
        rect: Rect.fromJson(_readObject(json, 'rect')),
        proposedType: FieldType.fromWire(json['proposedType']),
        confidence: _readDouble(json, 'confidence'),
        labelText: _readOptionalString(json, 'labelText'),
        evidence: allowLegacy
            ? SuggestionEvidence.fromLegacyJson(_readObject(json, 'evidence'))
            : SuggestionEvidence.fromJson(_readObject(json, 'evidence')),
        conflictsWith: _readStringList(json, 'conflictsWith'),
        resolution: SuggestionResolution.fromWire(json['resolution']),
        unknownFields: unknownJsonFields(json, _fieldSuggestionJsonKeys),
      );
      // `uncertainty` is derived from confidence. The contract requires a
      // numeric key; only the legacy decoder may omit it. An explicit null is
      // never numeric and is rejected in both modes.
      if (json.containsKey('uncertainty')) {
        final double provided = _readDouble(json, 'uncertainty');
        if ((provided - suggestion.uncertainty).abs() > 1e-12) {
          throw const FormatException(
            'JSON field "uncertainty" must equal 1 - confidence',
          );
        }
      } else if (!allowLegacy) {
        throw const FormatException('JSON field "uncertainty" is required');
      }
      return suggestion;
    } on ArgumentError catch (error) {
      throw FormatException('Invalid field suggestion JSON: ${error.message}');
    }
  }

  /// The deterministic id created by [idFor].
  final String id;

  /// Zero-based page index; validation against the page count belongs to the
  /// document aggregate.
  final int pageIndex;

  /// Canonical 1/8 pt-rounded display-space rectangle in PDF points.
  ///
  /// The constructor stores [canonicalRect], the stability form required by
  /// `contracts/recognition-output.md` §2 and §5.4. Confirmed-field geometry is
  /// never rounded (FR-024), so this field is the only place the suggestion
  /// grid applies. See [fitsWithinPage].
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

  /// Ids of same-page suggestions with an IoU of at least 0.5.
  ///
  /// IoU is defined within one page, so every reference must embed this
  /// suggestion's [pageIndex] (`contracts/recognition-output.md` §1 and §6).
  /// Symmetry and the IoU threshold are producer responsibilities; this value
  /// object enforces the structural invariants: unique, sorted, canonical
  /// same-page suggestion ids with positive ordinals, and no self reference.
  final List<String> conflictsWith;

  /// Current review state; persisted suggestions are [unresolved] until the
  /// user acts.
  final SuggestionResolution resolution;

  /// Returns the canonical 1/8 pt rounding of a suggestion rectangle.
  ///
  /// `contracts/recognition-output.md` §2 and §5.4 require suggestion
  /// rectangles to be rounded to 1/8 pt before IDs and conflicts are computed.
  /// Each component (`x`, `y`, `width`, `height`) is rounded independently to
  /// the nearest 1/8 pt, with ties away from zero, so every edge lands on the
  /// 1/8 pt grid while the stored size stays positive.
  ///
  /// This rule applies to machine suggestions only. Confirmed-field geometry
  /// is never rounded; corrected rectangles must be preserved exactly
  /// (FR-024).
  ///
  /// Throws [ArgumentError] when a rounded width or height would not be
  /// positive, or when a component overflows to infinity while scaling.
  static Rect canonicalRect(Rect rect) {
    final double left = _roundToEighth(rect.left, 'x');
    final double top = _roundToEighth(rect.top, 'y');
    final double width = _roundToEighth(rect.width, 'width');
    final double height = _roundToEighth(rect.height, 'height');
    if (width <= 0 || height <= 0) {
      throw ArgumentError(
        'rect width and height must remain positive after 1/8 pt rounding',
      );
    }
    return Rect.fromLTWH(
      left,
      top,
      width,
      height,
      unknownFields: rect.unknownFields,
    );
  }

  /// The deterministic suggestion id for [pageIndex] and a one-based
  /// [ordinal].
  ///
  /// `contracts/recognition-output.md` §2 fixes the canonical wire spelling
  /// `s_p<pageIndex>_<zero-padded ordinal>`, for example `s_p0_0007`.
  /// `data-model.md` §3.4 writes the same id as `s_<page>_<ordinal>`; that is
  /// a shorthand placeholder for the recognition contract's spelling, not a
  /// second accepted wire format. The constructor accepts only the canonical
  /// form.
  static String idFor({required int pageIndex, required int ordinal}) {
    final int checkedPage = _checkPageIndex(pageIndex);
    if (ordinal < 1) {
      throw ArgumentError('ordinal must be at least 1');
    }
    final String padded = ordinal.toString().padLeft(4, '0');
    return 's_p${checkedPage}_$padded';
  }

  /// Uncertainty implied by [confidence]: `1 - confidence`, rounded to the
  /// two-decimal form required by `contracts/recognition-output.md` §2.
  double get uncertainty => _roundToTwoDecimals(1 - confidence);

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
    Map<String, Object?>? unknownFields,
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
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  /// Serializes to the recognition-output §2 suggestion object.
  ///
  /// `uncertainty` is always written as the two-decimal derived value, and
  /// `evidence.contrast` is `normal | low`. Unknown same-schema fields are
  /// emitted beneath the modeled keys. Key ordering is not canonical here; the
  /// T017 canonical JSON encoder owns that.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'id': id,
      'pageIndex': pageIndex,
      'rect': rect.toJson(),
      'proposedType': proposedType.wireName,
      'confidence': confidence,
      'uncertainty': uncertainty,
      'labelText': labelText,
      'evidence': evidence.toJson(),
      'conflictsWith': List<String>.unmodifiable(conflictsWith),
      'resolution': resolution.wireName,
    });
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
/// provenances must not carry them. Unknown same-schema JSON fields are
/// retained across a read/write round (`data-model.md` §6).
final class ConfirmedField extends JsonObject {
  /// Creates a confirmed field.
  ///
  /// [id] must be a lowercase UUIDv4. A [Provenance.template] field may keep a
  /// deterministic template field id instead: non-empty, at most 128
  /// characters, with no whitespace or control characters. [label] is trimmed
  /// and must be 1–120 characters; German characters are preserved.
  /// [order] is at least 0. [createdAt] and [updatedAt] must be UTC.
  /// [sourceSuggestionId] and [suggestionConfidence] are required exactly when
  /// [provenance] is [Provenance.machine], and the suggestion must be on the
  /// same page. [unknownFields] are opaque same-schema JSON extensions
  /// retained for a later write.
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
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    final int checkedPage = _checkPageIndex(pageIndex);
    final String checkedId = _validateConfirmedFieldId(id, provenance);
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
        : _checkTwoDecimalConfidence(
            suggestionConfidence,
            'suggestionConfidence',
          );
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
      unknownFields: Map<String, Object?>.unmodifiable(unknownFields),
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
    required super.unknownFields,
  });

  /// Reads a persisted confirmed field.
  ///
  /// Unknown same-schema keys are retained for a later write. Throws
  /// [FormatException] for missing, mistyped, or invalid fields.
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
        unknownFields: unknownJsonFields(json, _confirmedFieldJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid confirmed field JSON: ${error.message}');
    }
  }

  /// Lowercase UUIDv4, or a deterministic template field id for
  /// [Provenance.template].
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
    Map<String, Object?>? unknownFields,
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
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  /// Serializes to the persisted confirmed-field object.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
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
    });
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
/// asset after the next verified commit. Unknown same-schema JSON fields are
/// retained across a read/write round (`data-model.md` §6).
final class SignatureMark extends JsonObject {
  /// Creates a signature mark.
  ///
  /// [assetId] must be a lowercase UUIDv4 and [fieldId] a valid field id.
  /// [widthPx] and [heightPx] must be positive and at most 1024 on the long
  /// edge. [capturedAt] must be UTC. [sha256] is the 64-lowercase-hex hash of
  /// the plaintext PNG. [unknownFields] are opaque same-schema JSON extensions
  /// retained for a later write.
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
    Map<String, Object?> unknownFields = const <String, Object?>{},
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
      unknownFields: Map<String, Object?>.unmodifiable(unknownFields),
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
    required super.unknownFields,
  });

  /// Reads a persisted signature mark.
  ///
  /// Unknown same-schema keys are retained for a later write. Throws
  /// [FormatException] for missing, mistyped, or invalid fields.
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
        unknownFields: unknownJsonFields(json, _signatureMarkJsonKeys),
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
    Map<String, Object?>? unknownFields,
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
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  /// Serializes to the persisted signature object.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'assetId': assetId,
      'fieldId': fieldId,
      'pageIndex': pageIndex,
      'rect': rect.toJson(),
      'widthPx': widthPx,
      'heightPx': heightPx,
      'capturedAt': _serializeTimestamp(capturedAt),
      'sha256': sha256,
    });
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
///
/// Unknown same-schema JSON fields are retained across a read/write round
/// (`data-model.md` §6).
final class FieldVerification extends JsonObject {
  /// Creates a verification record.
  ///
  /// [reviewedAt] is required for [FieldVerificationState.confirmed] and
  /// [FieldVerificationState.corrected], must be null for
  /// [FieldVerificationState.unreviewed], and must be UTC. [warnings] must be
  /// duplicate-free; the stored list is sorted by declaration order.
  /// [unknownFields] are opaque same-schema JSON extensions retained for a
  /// later write.
  ///
  /// Throws [ArgumentError] for every invalid value.
  factory FieldVerification({
    required FieldVerificationState state,
    DateTime? reviewedAt,
    Iterable<WarningCode> warnings = const <WarningCode>[],
    Map<String, Object?> unknownFields = const <String, Object?>{},
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
      unknownFields: Map<String, Object?>.unmodifiable(unknownFields),
    );
  }

  const FieldVerification._({
    required this.state,
    required this.reviewedAt,
    required this.warnings,
    required super.unknownFields,
  });

  /// Reads a persisted verification record.
  ///
  /// Unknown same-schema keys are retained for a later write. Throws
  /// [FormatException] for missing, mistyped, or invalid fields.
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
        unknownFields: unknownJsonFields(json, _fieldVerificationJsonKeys),
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
    Map<String, Object?>? unknownFields,
  }) {
    return FieldVerification(
      state: state ?? this.state,
      reviewedAt: identical(reviewedAt, _unset)
          ? this.reviewedAt
          : reviewedAt as DateTime?,
      warnings: warnings ?? this.warnings,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  /// Serializes to the persisted verification object.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'state': state.wireName,
      'reviewedAt': reviewedAt == null
          ? null
          : _serializeTimestamp(reviewedAt!),
      'warnings': <String>[
        for (final WarningCode warning in warnings) warning.wireName,
      ],
    });
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
///
/// Unknown same-schema JSON fields are retained across a read/write round
/// (`data-model.md` §6).
sealed class FieldValidation extends JsonObject {
  const FieldValidation({super.unknownFields});

  /// The valid state: no warning or error.
  static const FieldValidation ok = _FieldValidationOk();

  /// A non-blocking warning with a German catalog message key.
  ///
  /// [unknownFields] are opaque same-schema JSON extensions retained for a
  /// later write.
  factory FieldValidation.warning(
    WarningCode code,
    String messageKey, {
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    return _FieldValidationWarning(
      code,
      _validateMessageKey(messageKey),
      unknownFields: Map<String, Object?>.unmodifiable(unknownFields),
    );
  }

  /// A blocking error with a stable catalog code such as `NUM-001`.
  ///
  /// [unknownFields] are opaque same-schema JSON extensions retained for a
  /// later write.
  factory FieldValidation.error(
    String code, {
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    return _FieldValidationError(
      _validateCatalogCode(code),
      unknownFields: Map<String, Object?>.unmodifiable(unknownFields),
    );
  }

  /// Reads a persisted validation object.
  ///
  /// Unknown same-schema keys are retained for a later write. Throws
  /// [FormatException] for missing, mistyped, or invalid fields.
  static FieldValidation fromJson(Map<String, Object?> json) {
    final Object? status = json['status'];
    final Map<String, Object?> unknown = unknownJsonFields(
      json,
      _fieldValidationJsonKeys,
    );
    try {
      if (status == 'ok') {
        return _FieldValidationOk(unknownFields: unknown);
      }
      if (status == 'warning') {
        return FieldValidation.warning(
          WarningCode.fromWire(json['code']),
          _readString(json, 'messageKey'),
          unknownFields: unknown,
        );
      }
      if (status == 'error') {
        return FieldValidation.error(
          _readString(json, 'code'),
          unknownFields: unknown,
        );
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
  const _FieldValidationOk({super.unknownFields});

  @override
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{'status': 'ok'});
  }

  @override
  bool operator ==(Object other) => other is _FieldValidationOk;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'FieldValidation.ok()';
}

final class _FieldValidationWarning extends FieldValidation {
  const _FieldValidationWarning(
    this.warningCode,
    this.messageKey, {
    super.unknownFields,
  });

  @override
  final WarningCode warningCode;

  @override
  final String messageKey;

  @override
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'status': 'warning',
      'code': warningCode.wireName,
      'messageKey': messageKey,
    });
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
  const _FieldValidationError(this.errorCode, {super.unknownFields});

  @override
  final String errorCode;

  @override
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'status': 'error',
      'code': errorCode,
    });
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
/// an [IncompatibleValue] instead of dropping it (FR-029/FR-038). Unknown
/// same-schema JSON fields are retained across a read/write round
/// (`data-model.md` §6).
sealed class FieldValue extends JsonObject {
  FieldValue({
    required DateTime lastEditedAt,
    required this.overflow,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) : lastEditedAt = _checkUtc(lastEditedAt, 'lastEditedAt'),
       super(unknownFields: Map<String, Object?>.unmodifiable(unknownFields));

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
  ///
  /// Unknown same-schema fields are retained unless [unknownFields] is
  /// supplied.
  FieldValue copyWithMetadata({
    DateTime? lastEditedAt,
    bool? overflow,
    Map<String, Object?>? unknownFields,
  });

  /// Serializes the value and its metadata.
  Map<String, Object?> toJson();

  /// Reads a persisted value.
  ///
  /// Unknown same-schema keys are retained for a later write. Throws
  /// [FormatException] for an unknown, missing, or mistyped discriminator or
  /// payload.
  static FieldValue fromJson(Map<String, Object?> json) {
    final String kind = _readString(json, 'type');
    final DateTime lastEditedAt = _readTimestamp(json, 'lastEditedAt');
    final bool overflow = _readBool(json, 'overflow');
    final Map<String, Object?> unknown = unknownJsonFields(
      json,
      _fieldValueJsonKeys,
    );
    try {
      switch (kind) {
        case 'text':
          return TextValue(
            text: _readString(json, 'text'),
            lastEditedAt: lastEditedAt,
            overflow: overflow,
            unknownFields: unknown,
          );
        case 'number':
          return NumberValue(
            canonical: _readString(json, 'canonical'),
            rawGerman: _readString(json, 'rawGerman'),
            lastEditedAt: lastEditedAt,
            overflow: overflow,
            unknownFields: unknown,
          );
        case 'date':
          return DateValue(
            canonical: _readString(json, 'canonical'),
            lastEditedAt: lastEditedAt,
            overflow: overflow,
            unknownFields: unknown,
          );
        case 'checkbox':
          return CheckboxValue(
            checked: _readBool(json, 'checked'),
            lastEditedAt: lastEditedAt,
            overflow: overflow,
            unknownFields: unknown,
          );
        case 'multiline':
          return MultilineValue(
            text: _readString(json, 'text'),
            lastEditedAt: lastEditedAt,
            overflow: overflow,
            unknownFields: unknown,
          );
        case 'signature':
          return SignatureValue(
            signatureAssetId: _readString(json, 'signatureAssetId'),
            lastEditedAt: lastEditedAt,
            overflow: overflow,
            unknownFields: unknown,
          );
        case 'incompatible':
          return IncompatibleValue(
            preservedText: _readString(json, 'preservedText'),
            reasonCode: _readString(json, 'reasonCode'),
            lastEditedAt: lastEditedAt,
            overflow: overflow,
            unknownFields: unknown,
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
    super.unknownFields,
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
  TextValue copyWithMetadata({
    DateTime? lastEditedAt,
    bool? overflow,
    Map<String, Object?>? unknownFields,
  }) {
    return TextValue(
      text: text,
      lastEditedAt: lastEditedAt ?? this.lastEditedAt,
      overflow: overflow ?? this.overflow,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'type': kind,
      'text': text,
      'lastEditedAt': _serializeTimestamp(lastEditedAt),
      'overflow': overflow,
    });
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
    super.unknownFields,
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
  NumberValue copyWithMetadata({
    DateTime? lastEditedAt,
    bool? overflow,
    Map<String, Object?>? unknownFields,
  }) {
    return NumberValue(
      canonical: canonical,
      rawGerman: rawGerman,
      lastEditedAt: lastEditedAt ?? this.lastEditedAt,
      overflow: overflow ?? this.overflow,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'type': kind,
      'canonical': canonical,
      'rawGerman': rawGerman,
      'lastEditedAt': _serializeTimestamp(lastEditedAt),
      'overflow': overflow,
    });
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
    super.unknownFields,
  }) : canonical = _validateCanonicalDate(canonical);

  /// Canonical `YYYY-MM-DD`; document content, never logged.
  final String canonical;

  @override
  FieldType get type => FieldType.date;

  @override
  String get kind => 'date';

  @override
  DateValue copyWithMetadata({
    DateTime? lastEditedAt,
    bool? overflow,
    Map<String, Object?>? unknownFields,
  }) {
    return DateValue(
      canonical: canonical,
      lastEditedAt: lastEditedAt ?? this.lastEditedAt,
      overflow: overflow ?? this.overflow,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'type': kind,
      'canonical': canonical,
      'lastEditedAt': _serializeTimestamp(lastEditedAt),
      'overflow': overflow,
    });
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
    super.unknownFields,
  });

  /// Whether the box is checked; document content, never logged.
  final bool checked;

  @override
  FieldType get type => FieldType.checkbox;

  @override
  String get kind => 'checkbox';

  @override
  CheckboxValue copyWithMetadata({
    DateTime? lastEditedAt,
    bool? overflow,
    Map<String, Object?>? unknownFields,
  }) {
    return CheckboxValue(
      checked: checked,
      lastEditedAt: lastEditedAt ?? this.lastEditedAt,
      overflow: overflow ?? this.overflow,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'type': kind,
      'checked': checked,
      'lastEditedAt': _serializeTimestamp(lastEditedAt),
      'overflow': overflow,
    });
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
    super.unknownFields,
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
  MultilineValue copyWithMetadata({
    DateTime? lastEditedAt,
    bool? overflow,
    Map<String, Object?>? unknownFields,
  }) {
    return MultilineValue(
      text: text,
      lastEditedAt: lastEditedAt ?? this.lastEditedAt,
      overflow: overflow ?? this.overflow,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'type': kind,
      'text': text,
      'lastEditedAt': _serializeTimestamp(lastEditedAt),
      'overflow': overflow,
    });
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
    super.unknownFields,
  }) : signatureAssetId = _validateUuidV4(signatureAssetId, 'signatureAssetId');

  /// UUIDv4 of the signature asset in the same document.
  final String signatureAssetId;

  @override
  FieldType get type => FieldType.signature;

  @override
  String get kind => 'signature';

  @override
  SignatureValue copyWithMetadata({
    DateTime? lastEditedAt,
    bool? overflow,
    Map<String, Object?>? unknownFields,
  }) {
    return SignatureValue(
      signatureAssetId: signatureAssetId,
      lastEditedAt: lastEditedAt ?? this.lastEditedAt,
      overflow: overflow ?? this.overflow,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'type': kind,
      'signatureAssetId': signatureAssetId,
      'lastEditedAt': _serializeTimestamp(lastEditedAt),
      'overflow': overflow,
    });
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
    super.unknownFields,
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
  IncompatibleValue copyWithMetadata({
    DateTime? lastEditedAt,
    bool? overflow,
    Map<String, Object?>? unknownFields,
  }) {
    return IncompatibleValue(
      preservedText: preservedText,
      reasonCode: reasonCode,
      lastEditedAt: lastEditedAt ?? this.lastEditedAt,
      overflow: overflow ?? this.overflow,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'type': kind,
      'preservedText': preservedText,
      'reasonCode': reasonCode,
      'lastEditedAt': _serializeTimestamp(lastEditedAt),
      'overflow': overflow,
    });
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

/// Modeled keys of a persisted suggestion-evidence object.
///
/// `lowContrast` is the legacy pre-contract spelling; it is consumed but never
/// re-emitted, so it is not treated as an extension.
const Set<String> _suggestionEvidenceJsonKeys = <String>{
  'cues',
  'cueAgreement',
  'skewDegrees',
  'contrast',
  'lowContrast',
  'ocrUsed',
};

/// Modeled keys of a persisted suggestion.
const Set<String> _fieldSuggestionJsonKeys = <String>{
  'id',
  'pageIndex',
  'rect',
  'proposedType',
  'confidence',
  'uncertainty',
  'labelText',
  'evidence',
  'conflictsWith',
  'resolution',
};

/// Modeled keys of a persisted confirmed field.
const Set<String> _confirmedFieldJsonKeys = <String>{
  'id',
  'pageIndex',
  'rect',
  'type',
  'provenance',
  'sourceSuggestionId',
  'suggestionConfidence',
  'label',
  'order',
  'createdAt',
  'updatedAt',
  'validation',
};

/// Modeled keys of a persisted signature mark.
const Set<String> _signatureMarkJsonKeys = <String>{
  'assetId',
  'fieldId',
  'pageIndex',
  'rect',
  'widthPx',
  'heightPx',
  'capturedAt',
  'sha256',
};

/// Modeled keys of a persisted field-verification object.
const Set<String> _fieldVerificationJsonKeys = <String>{
  'state',
  'reviewedAt',
  'warnings',
};

/// Modeled keys of a persisted field-validation object.
const Set<String> _fieldValidationJsonKeys = <String>{
  'status',
  'code',
  'messageKey',
};

/// Modeled keys of a persisted field value.
///
/// The union covers all tagged variants so a known key that is meaningless for
/// the current variant is dropped rather than retained as an extension.
const Set<String> _fieldValueJsonKeys = <String>{
  'type',
  'lastEditedAt',
  'overflow',
  'text',
  'canonical',
  'rawGerman',
  'checked',
  'signatureAssetId',
  'preservedText',
  'reasonCode',
};

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

final RegExp _suggestionIdPattern = RegExp(r'^s_p([0-9]+)_([0-9]+)$');
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

/// Validates a confidence on `0.0 … 1.0` with at most two decimal places.
///
/// `contracts/recognition-output.md` §2 requires confidence (and its derived
/// uncertainty) to be rounded to two decimals. A tolerance of `1e-12` absorbs
/// binary floating-point representation error for values such as `0.29`,
/// `0.58`, or `0.1 + 0.2`; the stored value is the canonical two-decimal
/// double, so JSON never emits a longer fraction. A genuine third decimal
/// (`0.825`, `0.999`) is rejected.
double _checkTwoDecimalConfidence(double value, String name) {
  final double checked = _checkUnitInterval(value, name);
  final double rounded = _roundToTwoDecimals(checked);
  if ((checked - rounded).abs() > 1e-12) {
    throw ArgumentError('$name must have at most two decimal places');
  }
  return rounded;
}

double _roundToTwoDecimals(double value) {
  final double result = (value * 100).roundToDouble() / 100;
  // Normalize negative zero so canonical JSON and equality see `0.0`.
  return result == 0 ? 0.0 : result;
}

/// Rounds one suggestion-rect component to the nearest 1/8 pt.
///
/// [name] names the component in the error without echoing a user value. A
/// finite component whose scaling overflows cannot be quantized, so it fails
/// closed instead of producing an infinite edge. Negative zero is normalized.
double _roundToEighth(double value, String name) {
  final double scaled = value * 8;
  if (!scaled.isFinite) {
    throw ArgumentError('rect $name must be finite after 1/8 pt rounding');
  }
  final double result = scaled.roundToDouble() / 8;
  return result == 0 ? 0.0 : result;
}

DateTime _checkUtc(DateTime value, String name) {
  if (!value.isUtc) {
    throw ArgumentError('$name must be UTC');
  }
  return value;
}

String _validateSuggestionId(String value, int pageIndex) {
  final ({int pageIndex, int ordinal}) parsed = _parseSuggestionId(value);
  if (parsed.pageIndex != pageIndex) {
    throw ArgumentError('id must embed the suggestion page index');
  }
  return value;
}

/// Parses the one canonical suggestion-id spelling from
/// `contracts/recognition-output.md` §2: `s_p<pageIndex>_<ordinal>`.
///
/// The page segment is the plain decimal form of the page index (no leading
/// zeros), and the one-based ordinal is zero-padded to at least four digits
/// (`s_p0_0001`, `s_p12_0007`, `s_p0_10000`). Every other spelling of the same
/// pair is an alias and is rejected, so persisted ids remain deterministic and
/// cannot multiply through padding variants. [name] names the offending field
/// in the error without echoing the rejected id.
({int pageIndex, int ordinal}) _parseSuggestionId(
  String value, {
  String name = 'id',
}) {
  final RegExpMatch? match = _suggestionIdPattern.firstMatch(value);
  if (match == null) {
    throw ArgumentError('$name must use the s_p<pageIndex>_<ordinal> form');
  }
  final String pageDigits = match.group(1)!;
  final String ordinalDigits = match.group(2)!;
  final int? pageIndex = int.tryParse(pageDigits);
  final int? ordinal = int.tryParse(ordinalDigits);
  if (pageIndex == null) {
    throw ArgumentError('$name page index is out of range');
  }
  if (pageDigits != pageIndex.toString()) {
    throw ArgumentError(
      '$name page index must be canonical decimal without leading zeros',
    );
  }
  if (ordinal == null) {
    throw ArgumentError('$name ordinal is out of range');
  }
  if (ordinal < 1) {
    throw ArgumentError('$name ordinal must be at least 1');
  }
  if (ordinalDigits != ordinal.toString().padLeft(4, '0')) {
    throw ArgumentError(
      '$name ordinal must be zero-padded to at least four digits',
    );
  }
  return (pageIndex: pageIndex, ordinal: ordinal);
}

/// Validates a [ConfirmedField.id] for [provenance].
///
/// `data-model.md` §3.5 requires a lowercase UUIDv4. A field inherited from a
/// template may keep a deterministic template field id instead; its format is
/// owned by the template task, so only the generic machine-id safety rules are
/// enforced for it.
String _validateConfirmedFieldId(String value, Provenance provenance) {
  if (provenance == Provenance.template) {
    return _validateFieldId(value);
  }
  return _validateUuidV4(value, 'id');
}

/// Validates the generic machine-id shape used by deterministic template field
/// ids and by `SignatureMark.fieldId` references.
String _validateFieldId(String value) {
  if (value.isEmpty) {
    throw ArgumentError('id must not be empty');
  }
  if (value.runes.length > 128) {
    throw ArgumentError('id must be at most 128 characters');
  }
  for (final int rune in value.runes) {
    if (rune < 0x20 ||
        (rune >= 0x7F && rune <= 0x9F) ||
        _isUnicodeWhitespace(rune) ||
        _isInvisibleCodePoint(rune)) {
      throw ArgumentError(
        'id must not contain whitespace, control, or invisible characters',
      );
    }
  }
  return value;
}

/// Whether [rune] has the Unicode `White_Space` property.
///
/// `String.trim()` only removes leading and trailing whitespace and the ASCII
/// check for `0x20` misses the separators a machine id must never hide, so
/// every Unicode whitespace code point is rejected explicitly. C1 controls
/// (`U+0080–U+009F`) are rejected by the caller; `U+0085` is also whitespace.
bool _isUnicodeWhitespace(int rune) {
  return rune == 0x20 ||
      rune == 0x00A0 ||
      rune == 0x1680 ||
      (rune >= 0x2000 && rune <= 0x200A) ||
      rune == 0x2028 ||
      rune == 0x2029 ||
      rune == 0x202F ||
      rune == 0x205F ||
      rune == 0x3000;
}

/// Whether [rune] is an invisible Unicode code point.
///
/// Covers the `Cf` format controls (zero-width joiners, bidirectional
/// overrides/isolates, tags, soft hyphen, BOM) and the non-`Cf` members of the
/// Unicode `Default_Ignorable_Code_Point` property, such as U+034F COMBINING
/// GRAPHEME JOINER, the fillers, and variation selectors. A machine identifier
/// must not hide such characters: they are invisible to a reviewer and can
/// make two different strings look equal. Visible combining marks (for example
/// the decomposed accent U+0301) and visible non-ASCII letters remain valid.
bool _isInvisibleCodePoint(int rune) {
  return rune == 0x00AD ||
      rune == 0x034F ||
      (rune >= 0x0600 && rune <= 0x0605) ||
      rune == 0x061C ||
      rune == 0x06DD ||
      rune == 0x070F ||
      (rune >= 0x0890 && rune <= 0x0891) ||
      rune == 0x08E2 ||
      (rune >= 0x115F && rune <= 0x1160) ||
      (rune >= 0x17B4 && rune <= 0x17B5) ||
      (rune >= 0x180B && rune <= 0x180F) ||
      (rune >= 0x200B && rune <= 0x200F) ||
      (rune >= 0x202A && rune <= 0x202E) ||
      (rune >= 0x2060 && rune <= 0x2064) ||
      (rune >= 0x2066 && rune <= 0x206F) ||
      rune == 0x3164 ||
      (rune >= 0xFE00 && rune <= 0xFE0F) ||
      rune == 0xFEFF ||
      rune == 0xFFA0 ||
      (rune >= 0xFFF0 && rune <= 0xFFF8) ||
      (rune >= 0xFFF9 && rune <= 0xFFFB) ||
      rune == 0x110BD ||
      rune == 0x110CD ||
      (rune >= 0x13430 && rune <= 0x1343F) ||
      (rune >= 0x1BCA0 && rune <= 0x1BCA3) ||
      (rune >= 0x1D173 && rune <= 0x1D17A) ||
      (rune >= 0xE0000 && rune <= 0xE0FFF);
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

List<String> _normalizeConflicts(
  Iterable<String> values,
  String ownId,
  int pageIndex,
) {
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
    // The referenced id must be the one canonical spelling with a positive,
    // zero-padded ordinal; padding aliases and zero ordinals are rejected.
    final ({int pageIndex, int ordinal}) parsed = _parseSuggestionId(
      id,
      name: 'conflictsWith',
    );
    // IoU is only defined within one page, so a cross-page reference could
    // never satisfy the conflict contract (`contracts/recognition-output.md`
    // §1 and §6).
    if (parsed.pageIndex != pageIndex) {
      throw ArgumentError(
        'conflictsWith must reference a suggestion on the same page',
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

/// Reads the contract `contrast` key.
///
/// Strict decoding requires the canonical key. The legacy `lowContrast`
/// boolean is read only by [SuggestionEvidence.fromLegacyJson]; every write
/// emits the contract's `normal | low` token.
EvidenceContrast _readEvidenceContrast(
  Map<String, Object?> json, {
  required bool allowLegacy,
}) {
  if (json.containsKey('contrast')) {
    return EvidenceContrast.fromWire(json['contrast']);
  }
  if (allowLegacy) {
    final Object? legacy = json['lowContrast'];
    if (legacy is bool) {
      return legacy ? EvidenceContrast.low : EvidenceContrast.normal;
    }
  }
  throw const FormatException(
    'JSON field "contrast" must be "normal" or "low"',
  );
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
