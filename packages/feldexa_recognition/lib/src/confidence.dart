// T054 confidence and uncertainty model.
//
// Normative sources:
//  * specs/001-scanned-form-workflow/contracts/recognition-output.md
//    section 2 (confidence/uncertainty fields), section 3.1 (cue vocabulary
//    and Source column), section 3.3 (normative confidence model), and
//    section 3.4 (uncertainty presentation thresholds);
//  * specs/001-scanned-form-workflow/spec.md FR-015 and FR-083.
//
// Scope: this library owns one pure, deterministic score and its
// presentational band. It has no detector, OCR, type inference, conflict
// handling, page envelope, persistence, UI widget, Android, I/O, randomness,
// clock, or locale dependency. T053 owns typing, T055 conflicts, T056 OCR, and
// T057 the page envelope; T122 owns the visible badge. Callers supply the
// section 3.3 inputs.
//
// Formula (recognition-output.md section 3.3), in integer hundredths:
//
//   base                                    35
//   + 12 per supporting cue family (max 4)  0..48
//   + 10 credible keyword matches type      0..10
//   +  5 geometry inside typical bounds     0..5
//   - 25 |skewDegrees| > 2.0                0 or -25
//   - 20 contrast == low                    0 or -20
//   - 15 ocrUsed == false                   0 or -15
//   + 10 two independent OCR lines agree    0..10
//   clamp to 5..98, then confidence = h/100, uncertainty = (100-h)/100
//
// All additive terms are integers, so no binary floating-point operation can
// drift the result: every reachable confidence is an exact multiple of 0.01.
// `confidence + uncertainty` is exactly 1.0. The binary expression
// `1.0 - confidence` can differ from the two-decimal `uncertainty` by one
// IEEE-754 ulp, so the decimal complement is authoritative; callers must not
// re-derive `uncertainty` with floating-point subtraction.
//
// The section 3.3 terms are independent. In particular the OCR-agreement bonus
// and the missing-OCR penalty are applied as written even when a caller
// supplies a combination that a real evidence producer would not (the producer
// must not claim OCR agreement when OCR did not run). The skew threshold is
// the literal `abs(skewDegrees) > 2.0`; exactly +/-2.0 is not penalized. Input
// skew is restricted to -10..+10 degrees, matching section 2.
//
// Cue families (section 3.1 Source column). `evidence.cueAgreement` counts
// independent families, not cue tokens:
//
//   line          underline                      raster line detection
//   box           box                            raster line detection
//   grid          grid_cell                      grid detection
//   whitespace    whitespace                     connected components
//   alignment     alignment_left                 layout analysis
//   ocrAlignment  label_below, ocr_alignment_*   OCR alignment
//   keyword       keyword_<key>                  OCR label classifier
//   ocrContext    numeric_context, date_context  OCR
//   geometry      small_square, table_cell,      geometry (signature_area is
//                 signature_area                 OCR + geometry)
//
// A token outside this mapping is a stable extension family of its own:
// `familyId` is `extension:<token>`. Distinct unknown tokens therefore count
// as distinct families and repeated unknown tokens count once; mapping never
// throws. Tokens are matched exactly; aliases and case variants are extension
// families. `keyword_` with an unknown or empty key remains the keyword family
// because the family describes the OCR label-classifier source; the closed
// lexicon check belongs to `suggestion_schema.dart`.
//
// Invalid input raises content-free `ArgumentError`s: a negative cue-family
// count, a non-finite skew, or a skew outside -10..+10. No message contains an
// input value. Zero cue families is valid at this layer even though persisted
// suggestions require `cueAgreement >= 1` (schema-owned).
library;

/// Maximum absolute input skew in degrees (`recognition-output.md` section 2).
const double _maxInputSkewDegrees = 10.0;

/// Evidence contrast classes (`recognition-output.md` section 2).
enum Contrast {
  /// Normal printed contrast.
  normal,

  /// Low printed contrast; applies the section 3.3 penalty.
  low,
}

/// Independent cue families derived from the section 3.1 Source column.
///
/// One family is counted once per candidate regardless of how many tokens of
/// that family support it.
enum CueFamily {
  /// Raster line detection of an underline.
  line,

  /// Raster line detection of a closed rectangle.
  box,

  /// Table-grid detection.
  grid,

  /// Connected-component whitespace.
  whitespace,

  /// Layout alignment analysis.
  alignment,

  /// OCR alignment cues.
  ocrAlignment,

  /// The OCR label-classifier keyword vocabulary.
  keyword,

  /// OCR-derived numeric/date context cues.
  ocrContext,

  /// Geometric cues, including signature areas.
  geometry,
}

/// One deterministic cue-family assignment.
///
/// Known section 3.1 tokens carry a non-null [family] and use the enum name as
/// [familyId]. Any other token is an extension family with a null [family] and
/// a `extension:<token>` identifier, so each distinct unknown token is one
/// stable family and never throws.
final class CueFamilyAssignment implements Comparable<CueFamilyAssignment> {
  const CueFamilyAssignment._(this.familyId, this.family);

  /// Stable family identifier.
  ///
  /// This is a [CueFamily] name for known tokens and `extension:<token>` for
  /// unknown tokens. It contains no document content; cue tokens are
  /// non-sensitive per `recognition-output.md` section 9.
  final String familyId;

  /// The known family, or null for an extension token.
  final CueFamily? family;

  /// Whether this assignment describes an unknown/extension token.
  bool get isExtension => family == null;

  static const String _keywordPrefix = 'keyword_';

  static const Map<String, CueFamily> _fixedCueFamilies = <String, CueFamily>{
    'underline': CueFamily.line,
    'box': CueFamily.box,
    'grid_cell': CueFamily.grid,
    'whitespace': CueFamily.whitespace,
    'alignment_left': CueFamily.alignment,
    'label_below': CueFamily.ocrAlignment,
    'ocr_alignment_right': CueFamily.ocrAlignment,
    'ocr_alignment_below': CueFamily.ocrAlignment,
    'small_square': CueFamily.geometry,
    'table_cell': CueFamily.geometry,
    'signature_area': CueFamily.geometry,
    'numeric_context': CueFamily.ocrContext,
    'date_context': CueFamily.ocrContext,
  };

  /// Maps one cue token to its family.
  ///
  /// Every `keyword_*` token maps to [CueFamily.keyword]. Unknown tokens map
  /// to a stable `extension:<token>` family instead of throwing.
  static CueFamilyAssignment of(String cue) {
    if (cue.startsWith(_keywordPrefix)) {
      return const CueFamilyAssignment._('keyword', CueFamily.keyword);
    }
    final CueFamily? known = _fixedCueFamilies[cue];
    if (known != null) {
      return CueFamilyAssignment._(known.name, known);
    }
    return CueFamilyAssignment._('extension:$cue', null);
  }

  /// Returns the distinct families of [cues], sorted by [familyId].
  ///
  /// Duplicate tokens and multiple tokens of one family collapse to one
  /// entry. The returned list is unmodifiable, so the result is deterministic
  /// and safe to share. The list length is the section 2 `cueAgreement` value
  /// a caller passes to [ConfidenceInputs.supportingCueFamilies].
  static List<CueFamilyAssignment> distinctFamilies(Iterable<String> cues) {
    final Set<CueFamilyAssignment> unique = <CueFamilyAssignment>{
      for (final String cue in cues) CueFamilyAssignment.of(cue),
    };
    final List<CueFamilyAssignment> sorted = unique.toList()..sort();
    return List<CueFamilyAssignment>.unmodifiable(sorted);
  }

  @override
  int compareTo(CueFamilyAssignment other) {
    return familyId.compareTo(other.familyId);
  }

  @override
  bool operator ==(Object other) {
    return other is CueFamilyAssignment && other.familyId == familyId;
  }

  @override
  int get hashCode => familyId.hashCode;

  @override
  String toString() => 'CueFamilyAssignment($familyId)';
}

/// Presentation band from `recognition-output.md` section 3.4.
///
/// The enum name is the stable identifier. This library deliberately defines
/// no UI string, including no localized "unsicher" text; the visible badge and
/// its localized label belong to the UI task. Confidence is never hidden for
/// low-confidence suggestions (FR-083).
enum ConfidencePresentation {
  /// Confidence >= 0.75: solid suggestion outline.
  solidOutline,

  /// Confidence 0.50..0.74: dashed suggestion outline.
  dashedOutline,

  /// Confidence < 0.50: dashed outline plus the uncertainty badge.
  dashedWithUncertaintyBadge;

  /// Classifies an exact confidence in integer hundredths.
  ///
  /// Accepts the schema range 0..100. Values outside it raise a content-free
  /// [ArgumentError].
  static ConfidencePresentation forConfidenceHundredths(int hundredths) {
    if (hundredths < 0 || hundredths > 100) {
      throw ArgumentError('hundredths must be within 0..100');
    }
    if (hundredths >= 75) {
      return solidOutline;
    }
    if (hundredths >= 50) {
      return dashedOutline;
    }
    return dashedWithUncertaintyBadge;
  }

  /// Whether this band shows the uncertainty badge (FR-083).
  bool get showsUncertaintyBadge => this == dashedWithUncertaintyBadge;
}

/// Immutable, explicit inputs of the section 3.3 confidence model.
///
/// Construction validates the numeric domain and throws content-free
/// [ArgumentError]s. The object has only final fields, so evaluating the model
/// cannot mutate it.
final class ConfidenceInputs {
  /// Creates validated inputs.
  ///
  /// Throws [ArgumentError] when [supportingCueFamilies] is negative, or when
  /// [skewDegrees] is non-finite or outside -10..+10. Input values are never
  /// reproduced in the message.
  factory ConfidenceInputs({
    required int supportingCueFamilies,
    required bool credibleKeywordMatchesInferredType,
    required bool geometryWithinTypicalBounds,
    required double skewDegrees,
    required Contrast contrast,
    required bool ocrUsed,
    required bool twoIndependentOcrLinesAgree,
  }) {
    if (supportingCueFamilies < 0) {
      throw ArgumentError('supportingCueFamilies must be non-negative');
    }
    if (!skewDegrees.isFinite ||
        skewDegrees < -_maxInputSkewDegrees ||
        skewDegrees > _maxInputSkewDegrees) {
      throw ArgumentError('skewDegrees must be finite and within -10.0..10.0');
    }
    return ConfidenceInputs._(
      supportingCueFamilies: supportingCueFamilies,
      credibleKeywordMatchesInferredType: credibleKeywordMatchesInferredType,
      geometryWithinTypicalBounds: geometryWithinTypicalBounds,
      skewDegrees: skewDegrees,
      contrast: contrast,
      ocrUsed: ocrUsed,
      twoIndependentOcrLinesAgree: twoIndependentOcrLinesAgree,
    );
  }

  const ConfidenceInputs._({
    required this.supportingCueFamilies,
    required this.credibleKeywordMatchesInferredType,
    required this.geometryWithinTypicalBounds,
    required this.skewDegrees,
    required this.contrast,
    required this.ocrUsed,
    required this.twoIndependentOcrLinesAgree,
  });

  /// Number of independent cue families supporting the candidate.
  final int supportingCueFamilies;

  /// Whether a credible keyword matches the inferred type.
  final bool credibleKeywordMatchesInferredType;

  /// Whether geometry is well inside typical bounds for the inferred type.
  final bool geometryWithinTypicalBounds;

  /// Estimated page skew in degrees, -10..+10.
  final double skewDegrees;

  /// Printed contrast class.
  final Contrast contrast;

  /// Whether OCR ran for this candidate.
  final bool ocrUsed;

  /// Whether two independent OCR lines agree on the candidate's label.
  final bool twoIndependentOcrLinesAgree;
}

/// Deterministic confidence, uncertainty, and presentation band.
final class ConfidenceAssessment {
  const ConfidenceAssessment._({
    required this.confidenceHundredths,
    required this.presentation,
  });

  /// Exact confidence in integer hundredths, 5..98.
  final int confidenceHundredths;

  /// The section 3.4 presentation band.
  final ConfidencePresentation presentation;

  /// Confidence as an exact two-decimal double (`hundredths / 100`).
  double get confidence => confidenceHundredths / 100;

  /// Exact uncertainty in integer hundredths (`100 - confidenceHundredths`).
  int get uncertaintyHundredths => 100 - confidenceHundredths;

  /// Uncertainty as an exact two-decimal double.
  ///
  /// This is the decimal complement of [confidence]; the two values sum to
  /// exactly 1.0. Binary `1.0 - confidence` is not used because it can differ
  /// by one ulp from the two-decimal representation.
  double get uncertainty => uncertaintyHundredths / 100;

  /// Whether this assessment shows the uncertainty badge (FR-083).
  bool get showsUncertaintyBadge => presentation.showsUncertaintyBadge;
}

/// The normative `recognition-output.md` section 3.3 confidence model.
///
/// Evaluation is pure: the same [ConfidenceInputs] always produces the same
/// [ConfidenceAssessment], with no state, clock, randomness, I/O, or locale
/// dependency.
abstract final class ConfidenceModel {
  /// Base score in integer hundredths.
  static const int baseConfidenceHundredths = 35;

  /// Bonus per supporting cue family in integer hundredths.
  static const int cueFamilyBonusHundredths = 12;

  /// Maximum cue-family bonus in integer hundredths.
  static const int cueFamilyBonusCapHundredths = 48;

  /// Number of cue families that can earn a bonus.
  static const int maxCountedCueFamilies = 4;

  /// Credible keyword-match bonus in integer hundredths.
  static const int keywordMatchBonusHundredths = 10;

  /// Geometry-inside-typical-bounds bonus in integer hundredths.
  static const int geometryBonusHundredths = 5;

  /// Skew magnitude above which the penalty applies, in degrees.
  static const double skewPenaltyThresholdDegrees = 2.0;

  /// Skew penalty in integer hundredths.
  static const int skewPenaltyHundredths = 25;

  /// Low-contrast penalty in integer hundredths.
  static const int lowContrastPenaltyHundredths = 20;

  /// Missing-OCR penalty in integer hundredths.
  static const int missingOcrPenaltyHundredths = 15;

  /// OCR-agreement bonus in integer hundredths.
  static const int ocrAgreementBonusHundredths = 10;

  /// Minimum emitted confidence in integer hundredths.
  static const int minConfidenceHundredths = 5;

  /// Maximum emitted confidence in integer hundredths.
  static const int maxConfidenceHundredths = 98;

  /// Evaluates the normative formula exactly in integer hundredths.
  ///
  /// The skew predicate is the literal `abs(skewDegrees) > 2.0`; exactly
  /// +/-2.0 is unpenalized. All section 3.3 terms are applied independently.
  static ConfidenceAssessment evaluate(ConfidenceInputs inputs) {
    final int countedFamilies =
        inputs.supportingCueFamilies > maxCountedCueFamilies
        ? maxCountedCueFamilies
        : inputs.supportingCueFamilies;
    int total =
        baseConfidenceHundredths + countedFamilies * cueFamilyBonusHundredths;

    if (inputs.credibleKeywordMatchesInferredType) {
      total += keywordMatchBonusHundredths;
    }
    if (inputs.geometryWithinTypicalBounds) {
      total += geometryBonusHundredths;
    }
    if (inputs.skewDegrees.abs() > skewPenaltyThresholdDegrees) {
      total -= skewPenaltyHundredths;
    }
    if (inputs.contrast == Contrast.low) {
      total -= lowContrastPenaltyHundredths;
    }
    if (!inputs.ocrUsed) {
      total -= missingOcrPenaltyHundredths;
    }
    if (inputs.twoIndependentOcrLinesAgree) {
      total += ocrAgreementBonusHundredths;
    }

    if (total < minConfidenceHundredths) {
      total = minConfidenceHundredths;
    } else if (total > maxConfidenceHundredths) {
      total = maxConfidenceHundredths;
    }

    return ConfidenceAssessment._(
      confidenceHundredths: total,
      presentation: ConfidencePresentation.forConfidenceHundredths(total),
    );
  }
}
