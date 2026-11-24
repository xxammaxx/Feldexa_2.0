// T264D: A/B/C benchmark of the adaptive second analysis pass, host-only.
//
// Normative sources:
//  * `tools/evaluation/adaptive-policy.v1.json` — `acceptanceThresholds`
//    (comparison modes, `sameInputs`, `holdoutTuning`, the twelve
//    `requiredOutcomes`, `noGainClaim`), `bounds` (pass/time/memory ceilings),
//    `runtimeSignals`, `renderStrategy`, and `corpusAndHoldout` (dev/holdout
//    split and the real-corpus statement). Every threshold is read from that
//    file; no number is duplicated here, and a declared outcome whose wording
//    this module cannot parse fails closed instead of being skipped.
//  * `tools/evaluation/adaptive-provenance.v1.json` — consumed read-only by
//    `AdaptivePolicy.load`; this module claims no evidence row, no correlation
//    group and no independence.
//  * `specs/001-scanned-form-workflow/tasks.md` T264D.
//
// What this tool measures. Three schedules over *identical* inputs (the declared
// synthetic corpus of `field_inventory_baseline.dart`, its ground truth declared
// at draw time):
//
//   A  single pass              pass 1 only
//   B  full second pass         pass 2 on every page
//   C  targeted adaptive        pass 2 only where `decideAdaptiveTrigger` says
//
// Each pass is the productive host pipeline: `RasterAnalysis` ->
// `GeometryDetector.detect` -> `TypeInference.infer` -> `FieldInventoryBuilder`
// -> `StructureComparison` against the declared ground truth. The frozen
// `PhotometricQuality` measurement supplies the trigger signals. Pass 2 analyses
// the only variant `renderStrategy.allowed` admits on this corpus, the same-DPI
// contrast stretch; see [_variantFor] for why deskew cannot be exercised.
//
// What it reports. Field precision/recall/F1 (supplementary, not the gate),
// type accuracy, label accuracy, mean matched IoU, missing/extra/duplicate,
// false accepts, review rate, page latency p50/p95, measured peak RSS, and the
// pass count, per mode. Every declared outcome becomes one PASS/FAIL verdict
// with its measured values. When C is not strictly better than A the frozen
// `noGainClaim` is reported verbatim.
//
// What it does not do. No OCR engine, no adapter, no Android/emulator/device
// run, no production wiring, no suggestion set, no cross-pass merge (that needs
// the T264P provenance decision), no schema change, no auto-confirmation, no
// second pipeline, no cloud or ML training. The corpus is synthetic, so no real
// form, real-corpus qualification, SC-001/SC-003 (T142) or SC-004 (T136/T141)
// claim is made. Evidence class `NONE`: host measurements are not runtime
// evidence.
//
// Usage:
//   dart run tools/evaluation/adaptive_benchmark.dart --output <run.json> \
//     --score dev
//   dart run tools/evaluation/adaptive_benchmark.dart --output <run.json> \
//     --score holdout --holdout-ledger <ledger.json>
//   dart run tools/evaluation/adaptive_benchmark.dart --help
//
// Exit codes:
//   0  run written, every declared outcome PASS
//   1  I/O failure or internal invariant failure; no run is written
//   2  usage error (unknown/missing/duplicate argument)
//   3  run written, at least one declared outcome FAIL
//   4  holdout refused: this policy already had its single holdout scoring
//
// The dev set is the development set. `--score holdout` scores the frozen
// holdout pages once and records that scoring in the ledger, so a repeated
// scoring is refused instead of silently repeated.
//
// `feldexa_recognition` is a workspace package and intentionally not a root
// `pubspec.yaml` dependency; the root workspace resolves it for `dart run`.
// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:feldexa_recognition/src/field_inventory.dart';
import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:feldexa_recognition/src/geometry_metrics.dart' show iou;
import 'package:feldexa_recognition/src/photometric_quality.dart';
import 'package:feldexa_recognition/src/raster.dart';
import 'package:feldexa_recognition/src/structure_comparison.dart';
import 'package:feldexa_recognition/src/type_inference.dart';

import 'adaptive_trigger.dart';
import 'field_inventory_baseline.dart'
    show
        SyntheticCorpusLabel,
        SyntheticCorpusPage,
        SyntheticGroundTruthField,
        buildSyntheticCorpus,
        hostMemoryMeasurement,
        syntheticCorpusId,
        syntheticCorpusIdentity;
import 'validate_report.dart' show sha256Hex;

/// One of the three comparison schedules of `acceptanceThresholds`.
enum Mode {
  /// A: single pass.
  a,

  /// B: full second pass.
  b,

  /// C: targeted adaptive.
  c,
}

/// Which declared corpus pages a run scores.
enum ScoreSet {
  /// `corpusAndHoldout.devPages`: the development set.
  dev,

  /// `corpusAndHoldout.holdoutPages`: scored once, at the end.
  holdout,
}

/// The benchmark cannot load, parse, or run what the frozen artifacts declare.
final class BenchmarkException implements Exception {
  BenchmarkException(this.message);

  final String message;

  @override
  String toString() => 'BenchmarkException: $message';
}

/// A variant raster may not exceed the frozen pixel ceiling.
final class VariantBudgetException implements Exception {
  VariantBudgetException(this.message);

  final String message;

  @override
  String toString() => 'VariantBudgetException: $message';
}

/// The frozen policy already had its single holdout scoring.
final class HoldoutAlreadyScoredException implements Exception {
  HoldoutAlreadyScoredException(this.message);

  final String message;

  @override
  String toString() => 'HoldoutAlreadyScoredException: $message';
}

// ---------------------------------------------------------------------------
// Frozen acceptance thresholds
// ---------------------------------------------------------------------------

/// Run-level measurements an outcome clause can reference without a mode.
final class RunMetrics {
  const RunMetrics({
    required this.peakVariantPixels,
    required this.peakResidentSetBytes,
    required this.variantRasterHashes,
  });

  /// Largest variant raster rendered in the run, in pixels.
  final int peakVariantPixels;

  /// Measured peak resident set of this host process, in bytes.
  final int peakResidentSetBytes;

  /// Variant id -> SHA-256 of the variant raster that was analysed.
  final Map<String, String> variantRasterHashes;
}

/// One declared outcome with its measured verdict.
final class OutcomeVerdict {
  const OutcomeVerdict({
    required this.text,
    required this.passed,
    required this.detail,
  });

  /// The declared `acceptanceThresholds.requiredOutcomes` text, unchanged.
  final String text;

  final bool passed;

  /// The measured values the verdict was derived from.
  final String detail;

  @override
  String toString() => '${passed ? 'PASS' : 'FAIL'} $text ($detail)';
}

/// One parsed `acceptanceThresholds.requiredOutcomes` clause.
///
/// The clause is parsed from the frozen prose, so the threshold, the mode
/// orientation, and the tolerance are the declared ones. An unparsable wording
/// throws [BenchmarkException] at load time instead of being skipped.
final class RequiredOutcome {
  RequiredOutcome._(this.text, this._clause);

  /// The declared outcome text, unchanged.
  final String text;

  final _Clause _clause;

  /// Evaluates this outcome against the measured metrics.
  OutcomeVerdict evaluate(
    Map<Mode, ModeMetrics> byMode,
    RunMetrics runMetrics,
  ) => _clause.evaluate(text, byMode, runMetrics);

  @override
  String toString() => 'RequiredOutcome($text)';
}

/// The frozen policy plus the parsed acceptance thresholds beside it.
final class AdaptiveBenchmarkPolicy {
  AdaptiveBenchmarkPolicy._({
    required this.policyFile,
    required this.policySha256,
    required this.policy,
    required this.comparisonModes,
    required this.sameInputs,
    required this.holdoutTuning,
    required this.requiredOutcomes,
    required this.noGainClaim,
    required this.corpusId,
  });

  /// Loads `adaptive-policy.v1.json` and parses its `acceptanceThresholds`.
  static AdaptiveBenchmarkPolicy load(File policyFile) {
    final AdaptivePolicy policy;
    try {
      policy = AdaptivePolicy.load(policyFile);
    } on AdaptivePolicyException catch (error) {
      throw BenchmarkException(error.message);
    }
    final Map<String, Object?> document = _decodeObject(
      policyFile,
      'frozen policy',
    );
    final Map<String, Object?> acceptance = _map(
      document,
      'acceptanceThresholds',
    );
    final List<RequiredOutcome> outcomes = <RequiredOutcome>[
      for (final String text in _stringList(acceptance, 'requiredOutcomes'))
        RequiredOutcome._(text, _parseClause(text)),
    ];
    if (outcomes.isEmpty) {
      throw BenchmarkException(
        'acceptanceThresholds.requiredOutcomes is empty, so there is no gate '
        'to report',
      );
    }
    return AdaptiveBenchmarkPolicy._(
      policyFile: policyFile,
      policySha256: sha256Hex(policyFile.readAsBytesSync()),
      policy: policy,
      comparisonModes: _stringList(acceptance, 'comparisonModes'),
      sameInputs: _bool(acceptance, 'sameInputs'),
      holdoutTuning: _bool(acceptance, 'holdoutTuning'),
      requiredOutcomes: List<RequiredOutcome>.unmodifiable(outcomes),
      noGainClaim: _string(acceptance, 'noGainClaim'),
      corpusId: _string(_map(document, 'corpusAndHoldout'), 'corpusId'),
    );
  }

  final File policyFile;

  /// SHA-256 of the frozen policy bytes.
  final String policySha256;

  final AdaptivePolicy policy;

  /// `acceptanceThresholds.comparisonModes`, unchanged.
  final List<String> comparisonModes;

  /// `acceptanceThresholds.sameInputs`; the run refuses `false`.
  final bool sameInputs;

  /// `acceptanceThresholds.holdoutTuning`; the run refuses `true`.
  final bool holdoutTuning;

  /// One entry per declared outcome, in declared order.
  final List<RequiredOutcome> requiredOutcomes;

  /// `acceptanceThresholds.noGainClaim`, reported verbatim when C gains nothing.
  final String noGainClaim;

  /// `corpusAndHoldout.corpusId`: the corpus the policy expects to be scored.
  final String corpusId;
}

// ---------------------------------------------------------------------------
// Corpus partition
// ---------------------------------------------------------------------------

/// The declared corpus split into dev, holdout, and undeclared pages.
final class CorpusPartition {
  CorpusPartition._({
    required this.dev,
    required this.holdout,
    required this.undeclared,
    required this.undeclaredReasons,
  });

  final List<SyntheticCorpusPage> dev;
  final List<SyntheticCorpusPage> holdout;

  /// Drawn pages the frozen `corpusAndHoldout` block does not declare. They are
  /// never scored and never enter the gate arithmetic.
  final List<SyntheticCorpusPage> undeclared;

  /// Why each undeclared page is not scored.
  final Map<String, String> undeclaredReasons;

  /// Every scored page: dev first, then holdout, in declared order.
  List<SyntheticCorpusPage> get scored => <SyntheticCorpusPage>[
    ...dev,
    ...holdout,
  ];

  /// The pages of [scoreSet].
  List<SyntheticCorpusPage> of(ScoreSet scoreSet) =>
      scoreSet == ScoreSet.dev ? dev : holdout;
}

/// Splits [pages] by the frozen `corpusAndHoldout` declaration.
///
/// A declared page the corpus does not draw throws: a corpus and a policy that
/// disagree cannot be scored. Undeclared pages are reported, never scored.
CorpusPartition partitionCorpus({
  required AdaptivePolicy policy,
  required List<SyntheticCorpusPage> pages,
}) {
  final Map<String, SyntheticCorpusPage> byId = <String, SyntheticCorpusPage>{
    for (final SyntheticCorpusPage page in pages) page.id: page,
  };
  List<SyntheticCorpusPage> pick(List<String> ids, String label) =>
      <SyntheticCorpusPage>[
        for (final String id in ids)
          byId[id] ??
              (throw BenchmarkException(
                'corpusAndHoldout.$label declares the page "$id", which the '
                'corpus does not draw',
              )),
      ];
  final List<SyntheticCorpusPage> dev = pick(policy.devPages, 'devPages');
  final List<SyntheticCorpusPage> holdout = pick(
    policy.holdoutPages,
    'holdoutPages',
  );
  final Set<String> overlap = policy.devPages.toSet().intersection(
    policy.holdoutPages.toSet(),
  );
  if (overlap.isNotEmpty) {
    throw BenchmarkException(
      'corpusAndHoldout declares ${overlap.join(', ')} as dev and holdout page',
    );
  }
  final Set<String> declared = <String>{
    for (final SyntheticCorpusPage page in dev) page.id,
    for (final SyntheticCorpusPage page in holdout) page.id,
  };
  final List<SyntheticCorpusPage> undeclared = <SyntheticCorpusPage>[
    for (final SyntheticCorpusPage page in pages)
      if (!declared.contains(page.id)) page,
  ];
  return CorpusPartition._(
    dev: List<SyntheticCorpusPage>.unmodifiable(dev),
    holdout: List<SyntheticCorpusPage>.unmodifiable(holdout),
    undeclared: List<SyntheticCorpusPage>.unmodifiable(undeclared),
    undeclaredReasons: <String, String>{
      for (final SyntheticCorpusPage page in undeclared)
        page.id:
            'not declared in corpusAndHoldout.devPages or .holdoutPages, so '
            'this page is outside the frozen split: it is never scored, never '
            'enters the gate arithmetic, and no result is claimed for it',
    },
  );
}

/// Refuses a policy that declares a different corpus than the one drawn.
void checkCorpusId({required String declared, required String drawn}) {
  if (declared != drawn) {
    throw BenchmarkException(
      'corpusAndHoldout.corpusId is $declared, but this run draws $drawn: the '
      'declared corpus and the policy disagree',
    );
  }
}

// ---------------------------------------------------------------------------
// Same-DPI variant
// ---------------------------------------------------------------------------

/// The rendered variant of one page.
final class VariantRaster {
  const VariantRaster({
    required this.variantId,
    required this.raster,
    required this.rasterSha256,
    required this.pixelCount,
    required this.identity,
  });

  /// `renderStrategy.allowed` id of this variant.
  final String variantId;

  final GrayRaster raster;

  /// SHA-256 of the variant bytes, recorded for auditability.
  final String rasterSha256;

  final int pixelCount;

  /// Whether the transform left every byte unchanged.
  final bool identity;

  int get widthPx => raster.width;

  int get heightPx => raster.height;
}

/// `renderStrategy.allowed[contrastStretch]`: a linear stretch from the measured
/// 5th/95th percentiles to 0/255 on the same raster grid.
///
/// [p05Luminance] and [p95Luminance] are the frozen `PhotometricQuality`
/// nearest-rank percentiles of the *original* raster. A raster without a
/// measurable spread keeps its bytes; the result then reports [VariantRaster
/// .identity] `true` instead of inventing a gain.
VariantRaster renderContrastStretch(
  GrayRaster raster, {
  required int p05Luminance,
  required int p95Luminance,
}) {
  final Uint8List source = raster.pixels;
  final Uint8List out = Uint8List(source.length);
  final int low = p05Luminance.clamp(0, 255);
  final int high = p95Luminance.clamp(0, 255);
  // The variant is the identity when the declared stretch cannot change a byte:
  // a full 0..255 range maps onto itself, and a raster without a measurable
  // spread (the two percentiles are equal) keeps its bytes.
  final bool identity = high <= low || (low == 0 && high == 255);
  if (high <= low) {
    out.setRange(0, source.length, source);
  } else {
    final int span = high - low;
    for (int index = 0; index < source.length; index++) {
      final int value = source[index];
      if (value <= low) {
        out[index] = 0;
      } else if (value >= high) {
        out[index] = 255;
      } else {
        out[index] = ((value - low) * 255 + span ~/ 2) ~/ span;
      }
    }
  }
  return VariantRaster(
    variantId: 'contrastStretch',
    raster: GrayRaster.fromGrayBytes(
      width: raster.width,
      height: raster.height,
      bytes: out,
    ),
    rasterSha256: sha256Hex(out),
    pixelCount: out.length,
    identity: identity,
  );
}

/// `bounds.maxVariantPixels` / `renderStrategy.memoryCeiling` as a guard.
///
/// [maxVariantPixels] is the frozen bound; a variant above it is refused instead
/// of rendered.
void checkVariantPixelBudget({
  required int widthPx,
  required int heightPx,
  required int maxVariantPixels,
}) {
  if (widthPx <= 0 || heightPx <= 0) {
    throw VariantBudgetException(
      'a variant needs a positive raster size, got ${widthPx}x$heightPx',
    );
  }
  final int pixels = widthPx * heightPx;
  if (pixels > maxVariantPixels) {
    throw VariantBudgetException(
      'bounds.maxVariantPixels=$maxVariantPixels: a ${widthPx}x$heightPx '
      'variant is $pixels px, so it is refused instead of rendered',
    );
  }
}

// ---------------------------------------------------------------------------
// Frozen metric definitions
// ---------------------------------------------------------------------------

/// Nearest-rank percentile of an ascending list; `0` for an empty list.
int percentileOfSorted(List<int> values, double quantile) {
  if (values.isEmpty) {
    return 0;
  }
  final int rank = math.max(1, (values.length * quantile).ceil());
  return values[math.min(rank, values.length) - 1];
}

/// The frozen field metrics of one comparison.
///
/// Precision, recall, F1, type accuracy, and label accuracy keep exactly the
/// definition `field_inventory_baseline.dart` froze; the review rate and the
/// false-accept count are added here because the policy gates on them.
///
/// * review rate = observed proposals that carry at least one comparison defect
///   (extra, geometry mismatch, type mismatch, ambiguous, unlabelled, or
///   duplicate) / observed proposals.
/// * false accepts = auto-confirmed proposals that are extra or type-mismatched.
///   Nothing is auto-confirmed here, so the counter is `0` by construction; it is
///   still computed from [autoConfirmed] instead of being hardcoded, and
///   [wouldBeFalseAccepts] shows how many defects would have become false
///   accepts with an auto-confirm step.
final class StructureMetrics {
  const StructureMetrics._({
    required this.expected,
    required this.observed,
    required this.matched,
    required this.extra,
    required this.missing,
    required this.duplicate,
    required this.duplicateUnmatched,
    required this.kindMatched,
    required this.labelledExpected,
    required this.labelsAgree,
    required this.typeMismatched,
    required this.reviewNeeded,
    required this.autoConfirmed,
    required this.falseAccepts,
    required this.wouldBeFalseAccepts,
    required this.meanMatchedIou,
  });

  /// Derives the frozen metrics from one structure comparison.
  factory StructureMetrics.fromComparison({
    required List<ExpectedField> expected,
    required List<ObservedField> observed,
    required StructureComparisonResult result,
  }) {
    int kindMatched = 0;
    for (final StructureMatch match in result.matches) {
      if (expected[match.expectedIndex].kind ==
          observed[match.observedIndex].kind) {
        kindMatched++;
      }
    }
    final Set<int> matchedObserved = <int>{
      for (final StructureMatch match in result.matches) match.observedIndex,
    };
    final int duplicateUnmatched = result.duplicates
        .where(
          (StructureDuplicate duplicate) =>
              !matchedObserved.contains(duplicate.observedIndex),
        )
        .length;
    int labelledExpected = 0;
    for (final ExpectedField field in expected) {
      final String? label = field.labelText?.trim();
      if (label != null && label.isNotEmpty) {
        labelledExpected++;
      }
    }
    int labelsAgree = 0;
    for (final StructureMatch match in result.matches) {
      final String expectedLabel =
          expected[match.expectedIndex].labelText?.trim().toLowerCase() ?? '';
      final String observedLabel =
          observed[match.observedIndex].labelText?.trim().toLowerCase() ?? '';
      if (expectedLabel.isNotEmpty && expectedLabel == observedLabel) {
        labelsAgree++;
      }
    }
    final Set<int> reviewNeeded = <int>{
      ...result.extraObserved,
      for (final StructureMatch match in result.geometryMismatchedMatches)
        match.observedIndex,
      for (final StructureMatch match in result.typeMismatchedMatches)
        match.observedIndex,
      ...result.ambiguousObserved,
      ...result.unlabelledObserved,
      for (final StructureDuplicate duplicate in result.duplicates)
        duplicate.observedIndex,
    };
    final int typeMismatched = result.typeMismatchedMatches.length;
    // The benchmark proposes a result and stops: it writes no suggestion set and
    // calls no confirm command, so no proposal is auto-confirmed.
    const int autoConfirmed = 0;
    return StructureMetrics._(
      expected: expected.length,
      observed: observed.length,
      matched: result.matches.length,
      extra: result.extraObserved.length,
      missing: result.missingExpected.length,
      duplicate: result.duplicates.length,
      duplicateUnmatched: duplicateUnmatched,
      kindMatched: kindMatched,
      labelledExpected: labelledExpected,
      labelsAgree: labelsAgree,
      typeMismatched: typeMismatched,
      reviewNeeded: reviewNeeded.length,
      autoConfirmed: autoConfirmed,
      // Nothing is auto-confirmed, so no proposal can become a false accept.
      // The counter stays derived from the auto-confirm count instead of being
      // hardcoded, so a future auto-confirm step cannot pass this gate silently.
      falseAccepts: autoConfirmed,
      wouldBeFalseAccepts: typeMismatched + result.extraObserved.length,
      meanMatchedIou: result.meanMatchedIou,
    );
  }

  final int expected;
  final int observed;
  final int matched;
  final int extra;
  final int missing;
  final int duplicate;
  final int duplicateUnmatched;
  final int kindMatched;
  final int labelledExpected;
  final int labelsAgree;
  final int typeMismatched;
  final int reviewNeeded;
  final int autoConfirmed;
  final int falseAccepts;
  final int wouldBeFalseAccepts;
  final double meanMatchedIou;

  /// Precision over unique proposals (frozen definition).
  double get precision {
    final int denominator = matched + extra + duplicateUnmatched;
    return denominator == 0 ? 1 : matched / denominator;
  }

  double get recall => expected == 0 ? 1 : matched / expected;

  double get f1 {
    final double p = precision;
    final double r = recall;
    return p + r == 0 ? 0 : 2 * p * r / (p + r);
  }

  double get typeAccuracy => matched == 0 ? 0 : kindMatched / matched;

  double get labelAccuracy =>
      labelledExpected == 0 ? 1 : labelsAgree / labelledExpected;

  double get reviewRate => observed == 0 ? 0 : reviewNeeded / observed;

  Map<String, Object?> toJson() => <String, Object?>{
    'expected': expected,
    'observed': observed,
    'matched': matched,
    'extra': extra,
    'missing': missing,
    'duplicate': duplicate,
    'duplicateUnmatched': duplicateUnmatched,
    'kindMatched': kindMatched,
    'labelledExpected': labelledExpected,
    'labelsAgree': labelsAgree,
    'typeMismatched': typeMismatched,
    'reviewNeeded': reviewNeeded,
    'autoConfirmed': autoConfirmed,
    'falseAccepts': falseAccepts,
    'wouldBeFalseAccepts': wouldBeFalseAccepts,
    'precision': _round6(precision),
    'recall': _round6(recall),
    'f1': _round6(f1),
    'typeAccuracy': _round6(typeAccuracy),
    'labelAccuracy': _round6(labelAccuracy),
    'reviewRate': _round6(reviewRate),
    'meanMatchedIou': _round6(meanMatchedIou),
  };
}

/// The aggregated metrics of one mode over the scored pages.
final class ModeMetrics {
  const ModeMetrics({
    required this.mode,
    required this.pageCount,
    required this.passes,
    required this.expected,
    required this.matched,
    required this.observed,
    required this.extra,
    required this.missing,
    required this.duplicateUnmatched,
    required this.kindMatched,
    required this.labelledExpected,
    required this.labelsAgree,
    required this.meanMatchedIou,
    required this.reviewNeeded,
    required this.autoConfirmed,
    required this.falseAccepts,
    required this.latencyMillis,
    this.typeMismatched = 0,
    this.duplicate = 0,
    this.wouldBeFalseAccepts = 0,
    this.peakVariantPixels = 0,
  });

  final Mode mode;
  final int pageCount;

  /// Analysis passes this mode executed over the scored pages.
  final int passes;

  final int expected;
  final int matched;
  final int observed;
  final int extra;
  final int missing;
  final int duplicateUnmatched;
  final int kindMatched;
  final int labelledExpected;
  final int labelsAgree;
  final int typeMismatched;
  final int duplicate;
  final int reviewNeeded;
  final int autoConfirmed;
  final int falseAccepts;
  final int wouldBeFalseAccepts;

  /// Mean matched IoU across all pages, weighted by matched pairs.
  final double meanMatchedIou;

  /// Per-page latency of this mode, in milliseconds.
  final List<int> latencyMillis;

  /// Largest variant raster this mode analysed, in pixels.
  final int peakVariantPixels;

  double get precision {
    final int denominator = matched + extra + duplicateUnmatched;
    return denominator == 0 ? 1 : matched / denominator;
  }

  double get recall => expected == 0 ? 1 : matched / expected;

  double get f1 {
    final double p = precision;
    final double r = recall;
    return p + r == 0 ? 0 : 2 * p * r / (p + r);
  }

  double get typeAccuracy => matched == 0 ? 0 : kindMatched / matched;

  double get labelAccuracy =>
      labelledExpected == 0 ? 1 : labelsAgree / labelledExpected;

  double get reviewRate => observed == 0 ? 0 : reviewNeeded / observed;

  List<int> get _sortedLatency => List<int>.of(latencyMillis)..sort();

  int get latencyP50Ms => percentileOfSorted(_sortedLatency, 0.5);

  int get latencyP95Ms => percentileOfSorted(_sortedLatency, 0.95);

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.name,
    'pageCount': pageCount,
    'passes': passes,
    'expected': expected,
    'matched': matched,
    'observed': observed,
    'extra': extra,
    'missing': missing,
    'duplicate': duplicate,
    'duplicateUnmatched': duplicateUnmatched,
    'kindMatched': kindMatched,
    'labelledExpected': labelledExpected,
    'labelsAgree': labelsAgree,
    'typeMismatched': typeMismatched,
    'reviewNeeded': reviewNeeded,
    'autoConfirmed': autoConfirmed,
    'falseAccepts': falseAccepts,
    'wouldBeFalseAccepts': wouldBeFalseAccepts,
    'precision': _round6(precision),
    'recall': _round6(recall),
    'f1': _round6(f1),
    'typeAccuracy': _round6(typeAccuracy),
    'labelAccuracy': _round6(labelAccuracy),
    'reviewRate': _round6(reviewRate),
    'meanMatchedIou': _round6(meanMatchedIou),
    'latencyMs': <String, Object?>{
      'p50': latencyP50Ms,
      'p95': latencyP95Ms,
      'perPage': latencyMillis,
    },
    'peakVariantPixels': peakVariantPixels,
  };
}

/// Whether C is strictly better than A on any gated axis.
///
/// This is the `acceptanceThresholds.noGainClaim` test: a strict improvement is
/// required, an equal or worse result is no gain.
bool isNoGain(Map<Mode, ModeMetrics> byMode) {
  final ModeMetrics? a = byMode[Mode.a];
  final ModeMetrics? c = byMode[Mode.c];
  if (a == null || c == null) {
    throw BenchmarkException('noGain needs both mode A and mode C metrics');
  }
  final List<bool> improvements = <bool>[
    c.recall > a.recall,
    c.precision > a.precision,
    c.typeAccuracy > a.typeAccuracy,
    c.meanMatchedIou > a.meanMatchedIou,
    c.missing < a.missing,
    c.extra < a.extra,
  ];
  return !improvements.any((bool improved) => improved);
}

// ---------------------------------------------------------------------------
// Outcome clauses
// ---------------------------------------------------------------------------

sealed class _Clause {
  const _Clause();

  OutcomeVerdict evaluate(
    String text,
    Map<Mode, ModeMetrics> byMode,
    RunMetrics runMetrics,
  );
}

final class _ComparisonClause extends _Clause {
  const _ComparisonClause({
    required this.left,
    required this.operator,
    required this.right,
  });

  final _Term left;
  final String operator;
  final _Term right;

  @override
  OutcomeVerdict evaluate(
    String text,
    Map<Mode, ModeMetrics> byMode,
    RunMetrics runMetrics,
  ) {
    final double leftValue = left.resolve(byMode, runMetrics);
    final double rightValue = right.resolve(byMode, runMetrics);
    final bool passed = switch (operator) {
      '>=' => leftValue >= rightValue,
      '<=' => leftValue <= rightValue,
      '<' => leftValue < rightValue,
      '>' => leftValue > rightValue,
      _ => throw BenchmarkException('unsupported operator "$operator"'),
    };
    // A constant right side is shown once: its label *is* the number.
    final String rightSide = right.constant == null
        ? '${right.label}=${_num(rightValue)}'
        : _num(rightValue);
    return OutcomeVerdict(
      text: text,
      passed: passed,
      detail: 'measured ${left.label}=${_num(leftValue)} $operator $rightSide',
    );
  }
}

final class _FalseAcceptClause extends _Clause {
  const _FalseAcceptClause({required this.limit});

  /// The declared `must be <limit>` value, parsed from the frozen sentence.
  final int limit;

  @override
  OutcomeVerdict evaluate(
    String text,
    Map<Mode, ModeMetrics> byMode,
    RunMetrics runMetrics,
  ) {
    final List<String> parts = <String>[];
    bool passed = true;
    for (final Mode mode in Mode.values) {
      final ModeMetrics metrics = _modeOrThrow(byMode, mode);
      final bool modePassed = metrics.falseAccepts <= limit;
      passed = passed && modePassed;
      parts.add(
        '${mode.name}: falseAccepts=${metrics.falseAccepts} '
        '(autoConfirmed=${metrics.autoConfirmed}, '
        'wouldBeFalseAccepts=${metrics.wouldBeFalseAccepts})',
      );
    }
    return OutcomeVerdict(
      text: text,
      passed: passed,
      detail: 'declared limit $limit; ${parts.join(', ')}',
    );
  }
}

/// One side of a clause: a constant, or a metric of one mode.
final class _Term {
  const _Term.metric({
    required this.metricKey,
    required this.mode,
    this.multiplier = 1,
    this.offset = 0,
  }) : constant = null;

  const _Term.constant(double value)
    : constant = value,
      metricKey = null,
      mode = null,
      multiplier = 1,
      offset = 0;

  final double? constant;
  final String? metricKey;
  final Mode? mode;
  final double multiplier;
  final double offset;

  String get label {
    final double? fixed = constant;
    if (fixed != null) {
      return _num(fixed);
    }
    final Mode? selected = mode;
    final String key = selected == null
        ? metricKey!
        : '$metricKey(${selected.name.toUpperCase()})';
    if (multiplier != 1) {
      return '${_num(multiplier)} * $key';
    }
    if (offset != 0) {
      return '$key + ${_num(offset)}';
    }
    return key;
  }

  double resolve(Map<Mode, ModeMetrics> byMode, RunMetrics runMetrics) {
    final double? fixed = constant;
    if (fixed != null) {
      return fixed;
    }
    final double value = _metricValue(metricKey!, mode, byMode, runMetrics);
    return value * multiplier + offset;
  }
}

final RegExp _clausePattern = RegExp(
  r'^(?<key>[A-Za-z][A-Za-z ]*?)'
  r'(?:\((?<mode>[ABC])\))?'
  r'\s*(?<op>>=|<=|<|>)\s*'
  r'(?<rhs>.+)$',
);

final RegExp _metricTermPattern = RegExp(
  r'^(?<key>[A-Za-z][A-Za-z ]*?)\((?<mode>[ABC])\)$',
);

final RegExp _metricPlusPattern = RegExp(
  r'^(?<key>[A-Za-z][A-Za-z ]*?)\((?<mode>[ABC])\)\s*\+\s*'
  r'(?<num>[0-9]+(?:\.[0-9]+)?)$',
);

final RegExp _scalePattern = RegExp(
  r'^(?<num>[0-9]+(?:\.[0-9]+)?)\s*\*\s*'
  r'(?<key>[A-Za-z][A-Za-z ]*?)\((?<mode>[ABC])\)$',
);

final RegExp _constantPattern = RegExp(r'^[0-9]+(?:\.[0-9]+)?$');

final RegExp _falseAcceptLimitPattern = RegExp(r'must be ([0-9]+)\s*$');

_Clause _parseClause(String text) {
  final String trimmed = text.trim();
  if (trimmed.toLowerCase().startsWith('false accepts')) {
    final RegExpMatch? match = _falseAcceptLimitPattern.firstMatch(trimmed);
    if (match == null) {
      throw BenchmarkException(
        'the false-accept outcome declares no numeric limit: "$text"',
      );
    }
    return _FalseAcceptClause(limit: int.parse(match.group(1)!));
  }
  final RegExpMatch? match = _clausePattern.firstMatch(trimmed);
  if (match == null) {
    throw BenchmarkException(
      'cannot parse the declared acceptance outcome "$text"; the benchmark '
      'fails closed instead of skipping a gate',
    );
  }
  return _ComparisonClause(
    left: _parseLeftTerm(match.namedGroup('key')!, match.namedGroup('mode')),
    operator: match.namedGroup('op')!,
    right: _parseRightTerm(match.namedGroup('rhs')!, text),
  );
}

_Term _parseLeftTerm(String key, String? mode) =>
    _Term.metric(metricKey: key, mode: mode == null ? null : _modeOf(mode));

_Term _parseRightTerm(String rhs, String text) {
  final String value = rhs.trim();
  final RegExpMatch? scaled = _scalePattern.firstMatch(value);
  if (scaled != null) {
    return _Term.metric(
      metricKey: scaled.namedGroup('key')!,
      mode: _modeOf(scaled.namedGroup('mode')!),
      multiplier: double.parse(scaled.namedGroup('num')!),
    );
  }
  final RegExpMatch? plus = _metricPlusPattern.firstMatch(value);
  if (plus != null) {
    return _Term.metric(
      metricKey: plus.namedGroup('key')!,
      mode: _modeOf(plus.namedGroup('mode')!),
      offset: double.parse(plus.namedGroup('num')!),
    );
  }
  final RegExpMatch? metric = _metricTermPattern.firstMatch(value);
  if (metric != null) {
    return _Term.metric(
      metricKey: metric.namedGroup('key')!,
      mode: _modeOf(metric.namedGroup('mode')!),
    );
  }
  if (_constantPattern.hasMatch(value)) {
    return _Term.constant(double.parse(value));
  }
  throw BenchmarkException(
    'cannot parse the right side "$value" of the declared acceptance outcome '
    '"$text"',
  );
}

Mode _modeOf(String token) => switch (token) {
  'A' => Mode.a,
  'B' => Mode.b,
  'C' => Mode.c,
  _ => throw BenchmarkException('unknown comparison mode "$token"'),
};

ModeMetrics _modeOrThrow(Map<Mode, ModeMetrics> byMode, Mode mode) =>
    byMode[mode] ??
    (throw BenchmarkException('the run has no metrics for mode ${mode.name}'));

double _metricValue(
  String key,
  Mode? mode,
  Map<Mode, ModeMetrics> byMode,
  RunMetrics runMetrics,
) {
  if (mode == null) {
    switch (key) {
      case 'peak variant pixels':
        return runMetrics.peakVariantPixels.toDouble();
      case 'peak resident set':
        return runMetrics.peakResidentSetBytes.toDouble();
      case 'false accepts':
        return <int>[
          for (final Mode each in Mode.values)
            _modeOrThrow(byMode, each).falseAccepts,
        ].reduce(math.max).toDouble();
      default:
        throw BenchmarkException(
          'the declared outcome metric "$key" needs a comparison mode',
        );
    }
  }
  final ModeMetrics metrics = _modeOrThrow(byMode, mode);
  switch (key) {
    case 'field recall':
      return metrics.recall;
    case 'field precision':
      return metrics.precision;
    case 'field f1':
      return metrics.f1;
    case 'type accuracy':
      return metrics.typeAccuracy;
    case 'label accuracy':
      return metrics.labelAccuracy;
    case 'mean matched IoU':
      return metrics.meanMatchedIou;
    case 'missing fields':
      return metrics.missing.toDouble();
    case 'extra fields':
      return metrics.extra.toDouble();
    case 'duplicate fields':
      return metrics.duplicate.toDouble();
    case 'review rate':
      return metrics.reviewRate;
    case 'passes':
      return metrics.passes.toDouble();
    case 'median latency':
      return metrics.latencyP50Ms.toDouble();
    case 'p95 latency':
      return metrics.latencyP95Ms.toDouble();
    case 'false accepts':
      return metrics.falseAccepts.toDouble();
    default:
      throw BenchmarkException(
        'the declared outcome metric "$key" is not measured by this benchmark',
      );
  }
}

// ---------------------------------------------------------------------------
// Passes and pages
// ---------------------------------------------------------------------------

/// One analysis pass over one page.
final class PagePassResult {
  const PagePassResult({
    required this.pageId,
    required this.passNumber,
    required this.variantId,
    required this.sourceRasterSha256,
    required this.inputRasterSha256,
    required this.elapsedMicros,
    required this.variantPixels,
    required this.observed,
    required this.fieldCandidates,
    required this.unlabelledCandidates,
    required this.conflictPairs,
    required this.metrics,
  });

  final String pageId;

  /// `1` or `2`.
  final int passNumber;

  /// Variant analysed by this pass; `original` for pass 1.
  final String variantId;

  /// SHA-256 of the page raster the pass derives from (identical for A/B/C).
  final String sourceRasterSha256;

  /// SHA-256 of the raster this pass analysed.
  final String inputRasterSha256;

  final int elapsedMicros;

  /// Variant pixels this pass held in memory; `0` for pass 1.
  final int variantPixels;

  final int observed;

  /// `FieldInventory` field candidates of this pass.
  final int fieldCandidates;

  /// Field candidates without credible label context.
  final int unlabelledCandidates;

  /// Conflict-graph pairs with `IoU >= 0.5` in this pass.
  final int conflictPairs;

  final StructureMetrics metrics;

  int get elapsedMilliseconds => elapsedMicros ~/ 1000;

  Map<String, Object?> toJson() => <String, Object?>{
    'passNumber': passNumber,
    'variantId': variantId,
    'sourceRasterSha256': sourceRasterSha256,
    'inputRasterSha256': inputRasterSha256,
    'observed': observed,
    'fieldCandidates': fieldCandidates,
    'unlabelledCandidates': unlabelledCandidates,
    'conflictPairs': conflictPairs,
    'metrics': metrics.toJson(),
    'elapsedMs': elapsedMilliseconds,
    'variantPixels': variantPixels,
  };
}

/// One page under all three schedules.
final class PageRun {
  const PageRun({
    required this.pageId,
    required this.pageClass,
    required this.scored,
    required this.undeclaredReason,
    required this.pass1,
    required this.pass2,
    required this.decision,
    required this.quality,
    required this.fields,
    required this.variantIdentity,
  });

  final String pageId;
  final PageClass pageClass;

  /// Whether this page is part of the frozen dev/holdout split.
  final bool scored;

  /// Why an undeclared page is never scored.
  final String? undeclaredReason;

  final PagePassResult pass1;
  final PagePassResult pass2;
  final AdaptiveDecision decision;

  /// Photometric quality of the *original* raster, measured once per page.
  final PhotometricQuality quality;

  /// Declared ground-truth field count, identical for A/B/C.
  final int fields;

  /// Whether the pass-2 variant left every byte of the page unchanged, in which
  /// case pass 2 analysed the same bytes as pass 1.
  final bool variantIdentity;

  /// Whether mode C replaces the pass-1 result with the pass-2 result.
  bool get secondPassApplied => decision.verdict == Verdict.secondPass;

  /// The pass a mode scores for this page.
  PagePassResult resultFor(Mode mode) => switch (mode) {
    Mode.a => pass1,
    Mode.b => pass2,
    Mode.c => secondPassApplied ? pass2 : pass1,
  };

  /// The total analysis time a mode pays for this page.
  ///
  /// A pays pass 1, B pays both passes on every page (that is what a full
  /// second pass costs), and C pays pass 2 only on the pages the frozen trigger
  /// admitted. The value is the page's total analysis cost, never the cost of
  /// one stage in isolation.
  int latencyMillisFor(Mode mode) => switch (mode) {
    Mode.a => pass1.elapsedMilliseconds,
    Mode.b => pass1.elapsedMilliseconds + pass2.elapsedMilliseconds,
    Mode.c =>
      pass1.elapsedMilliseconds +
          (secondPassApplied ? pass2.elapsedMilliseconds : 0),
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'id': pageId,
    'pageClass': pageClass.name,
    'scored': scored,
    if (undeclaredReason != null) 'undeclaredReason': undeclaredReason,
    'declaredFields': fields,
    'photometric': <String, Object?>{
      'p05Luminance': quality.p05Luminance,
      'p95Luminance': quality.p95Luminance,
      'contrastSpread': quality.dynamicRange,
      'inkDensity': _round6(quality.inkDensity),
    },
    'decision': <String, Object?>{
      'verdict': decision.verdict.name,
      'triggers': <String>[
        for (final TriggerHit hit in decision.triggers) hit.trigger.name,
      ],
      'triggersAgainst': <Map<String, Object?>>[
        for (final TriggerHit hit in decision.triggers)
          <String, Object?>{
            'trigger': hit.trigger.name,
            'policyPath': hit.policyPath,
            'threshold': hit.threshold,
            'observed': _round6(hit.observed),
            'heldByHysteresis': hit.heldByHysteresis,
          },
      ],
      'reasons': decision.reasons,
      'ignoredSignals': <Map<String, Object?>>[
        for (final SignalNote note in decision.ignoredSignals)
          <String, Object?>{'signal': note.signal, 'reason': note.reason},
      ],
      'bounds': <String, Object?>{
        'maxPassesPerPage': decision.bounds.maxPassesPerPage,
        'passesCompleted': decision.bounds.passesCompleted,
        'passesRemaining': decision.bounds.passesRemaining,
        'maxElapsedMsPerPage': decision.bounds.maxElapsedMsPerPage,
        'maxVariantPixels': decision.bounds.maxVariantPixels,
      },
      'rejection': decision.rejection == null
          ? null
          : <String, Object?>{
              'code': decision.rejection!.code,
              'message': decision.rejection!.message,
            },
    },
    'secondPassApplied': secondPassApplied,
    'variantIdentity': variantIdentity,
    'pass1': pass1.toJson(),
    'pass2': pass2.toJson(),
  };
}

// ---------------------------------------------------------------------------
// The run
// ---------------------------------------------------------------------------

/// One completed benchmark run.
final class BenchmarkRun {
  const BenchmarkRun({
    required this.scoreSet,
    required this.pages,
    required this.byMode,
    required this.runMetrics,
    required this.outcomes,
    required this.noGain,
    required this.noGainClaim,
    required this.artifact,
  });

  final ScoreSet scoreSet;
  final List<PageRun> pages;
  final Map<Mode, ModeMetrics> byMode;
  final RunMetrics runMetrics;
  final List<OutcomeVerdict> outcomes;

  /// Whether C failed to beat A on every gated axis.
  final bool noGain;

  /// `acceptanceThresholds.noGainClaim`, reported verbatim.
  final String noGainClaim;

  /// The complete report-ready artifact.
  final Map<String, Object?> artifact;

  /// Whether every declared outcome passed.
  bool get allOutcomesPassed =>
      outcomes.every((OutcomeVerdict outcome) => outcome.passed);
}

/// Runs A/B/C over [pages] and evaluates the frozen acceptance outcomes.
///
/// All three modes analyse the same declared rasters and the same declared
/// ground truth; only the pass schedule differs. Pass 2 analyses the same-DPI
/// contrast stretch of the original raster.
BenchmarkRun runBenchmark({
  required AdaptiveBenchmarkPolicy benchmark,
  required List<SyntheticCorpusPage> pages,
  required ScoreSet scoreSet,
}) {
  if (!benchmark.sameInputs) {
    throw BenchmarkException(
      'acceptanceThresholds.sameInputs is false, so an A/B/C comparison over '
      'identical inputs cannot be claimed',
    );
  }
  if (benchmark.holdoutTuning) {
    throw BenchmarkException(
      'acceptanceThresholds.holdoutTuning is true, so this run would tune on '
      'the holdout and must not be scored',
    );
  }
  checkCorpusId(declared: benchmark.corpusId, drawn: syntheticCorpusId);
  final Map<String, String> variantHashes = <String, String>{};
  int peakVariantPixels = 0;
  final List<PageRun> runs = <PageRun>[];
  for (final SyntheticCorpusPage page in pages) {
    final PageRun pageRun = _runPage(
      benchmark: benchmark,
      page: page,
      pageClass: scoreSet == ScoreSet.dev ? PageClass.dev : PageClass.holdout,
      variantHashes: variantHashes,
    );
    peakVariantPixels = math.max(
      peakVariantPixels,
      pageRun.pass2.variantPixels,
    );
    runs.add(pageRun);
  }
  final Map<Mode, ModeMetrics> byMode = <Mode, ModeMetrics>{
    for (final Mode mode in Mode.values) mode: _aggregate(mode, runs),
  };
  final Map<String, Object?> memory = hostMemoryMeasurement();
  final RunMetrics runMetrics = RunMetrics(
    peakVariantPixels: peakVariantPixels,
    peakResidentSetBytes: memory['peakResidentSetBytes']! as int,
    variantRasterHashes: Map<String, String>.unmodifiable(variantHashes),
  );
  final List<OutcomeVerdict> outcomes = <OutcomeVerdict>[
    for (final RequiredOutcome outcome in benchmark.requiredOutcomes)
      outcome.evaluate(byMode, runMetrics),
  ];
  final bool noGain = isNoGain(byMode);
  final List<SyntheticCorpusPage> corpus = buildSyntheticCorpus();
  final Map<String, String> identity = syntheticCorpusIdentity(corpus);
  return BenchmarkRun(
    scoreSet: scoreSet,
    pages: List<PageRun>.unmodifiable(runs),
    byMode: Map<Mode, ModeMetrics>.unmodifiable(byMode),
    runMetrics: runMetrics,
    outcomes: List<OutcomeVerdict>.unmodifiable(outcomes),
    noGain: noGain,
    noGainClaim: benchmark.noGainClaim,
    artifact: <String, Object?>{
      'schemaVersion': 1,
      'task': 'T264D',
      'issue': 264,
      'evidenceClass': 'NONE',
      'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'scoreSet': scoreSet.name,
      'conditions': <String, Object?>{
        'runtime': 'host VM',
        'dart': Platform.version,
        'analysisDpi': analysisDpi,
        'ocrEngine': null,
        'ocrEngineNote':
            'No OCR engine ran: the label observations are the declared '
            'SIMULATED labels of the synthetic corpus.',
        'claim':
            'host-only A/B/C evaluation; no Android, emulator, device, '
            'OCR-engine, real-form, or performance claim',
        'evidenceClass': 'NONE',
        'notRun': <String>[
          'Android EMULATOR production-path evidence',
          'real-corpus qualification',
          'real-form evidence',
          'SC-001/SC-003 (T142) and SC-004 (T136/T141)',
          'cross-pass suggestion merge (needs the T264P provenance decision)',
          'deskew variant (the corpus declares no caller-supplied skew angle)',
        ],
      },
      'inputs': <String, Object?>{
        'policy': <String, Object?>{
          'path': benchmark.policyFile.path,
          'sha256': benchmark.policySha256,
          'version': benchmark.policy.version,
          'status': benchmark.policy.status,
          'implementation': benchmark.policy.implementation,
        },
        'corpus': <String, Object?>{
          'corpusId': syntheticCorpusId,
          'declaredCorpusId': benchmark.corpusId,
          'generator': 'tools/evaluation/field_inventory_baseline.dart',
          'golden': 'tools/evaluation/goldens/field-inventory-baseline.v1.json',
          'pageCount': corpus.length,
          'fixtureSha256': identity['fixtureSha256'],
          'corpusSha256': identity['corpusSha256'],
          'groundTruthSha256': identity['groundTruthSha256'],
          'scoredPages': <Map<String, Object?>>[
            for (final PageRun page in runs)
              <String, Object?>{
                'id': page.pageId,
                'pageClass': page.pageClass.name,
                'sourceRasterSha256': page.pass1.sourceRasterSha256,
                'declaredFields': page.fields,
              },
          ],
        },
        'sameInputs': benchmark.sameInputs,
        'comparisonModes': benchmark.comparisonModes,
      },
      'run': <String, Object?>{
        'peakResidentSetBytes': runMetrics.peakResidentSetBytes,
        'memory': memory,
        'peakVariantPixels': peakVariantPixels,
        'variantRasterHashes': variantHashes,
        'variantBudgetPixels': benchmark.policy.bounds.maxVariantPixels,
      },
      'modes': <String, Object?>{
        for (final Mode mode in Mode.values) mode.name: byMode[mode]!.toJson(),
      },
      'pages': <Map<String, Object?>>[
        for (final PageRun page in runs) page.toJson(),
      ],
      'outcomes': <Map<String, Object?>>[
        for (final OutcomeVerdict outcome in outcomes)
          <String, Object?>{
            'text': outcome.text,
            'passed': outcome.passed,
            'detail': outcome.detail,
          },
      ],
      'noGain': <String, Object?>{
        'applies': noGain,
        'claim': noGain ? benchmark.noGainClaim : null,
      },
    },
  );
}

PageRun _runPage({
  required AdaptiveBenchmarkPolicy benchmark,
  required SyntheticCorpusPage page,
  required PageClass pageClass,
  required Map<String, String> variantHashes,
}) {
  final PhotometricQuality quality = PhotometricQuality.measure(page.raster);
  final PagePassResult pass1 = _analyse(
    page: page,
    raster: page.raster,
    passNumber: 1,
    variantId: 'original',
    variantPixels: 0,
  );
  final VariantRaster variant = _variantFor(
    raster: page.raster,
    quality: quality,
    maxVariantPixels: benchmark.policy.bounds.maxVariantPixels,
  );
  variantHashes[variant.variantId] = variant.rasterSha256;
  final PagePassResult pass2 = _analyse(
    page: page,
    raster: variant.raster,
    passNumber: 2,
    variantId: variant.variantId,
    variantPixels: variant.pixelCount,
  );
  final _PassSignals signals = _signalsFrom(pass1, page);
  final AdaptiveDecision decision = decideAdaptiveTrigger(
    policy: benchmark.policy,
    request: TriggerRequest(
      signals: PageSignals(
        p05Luminance: quality.p05Luminance.toDouble(),
        p95Luminance: quality.p95Luminance.toDouble(),
        // runtimeSignals.skew.metric is caller-supplied and must never be
        // estimated. The declared corpus carries no skew angle, so the signal is
        // absent and can never trigger.
        skewDegrees: null,
        ocrFailed: signals.labels == 0,
        fieldCandidates: signals.fieldCandidates,
        unlabeledCandidates: signals.unlabelledCandidates,
        conflictPairs: signals.conflictPairs,
        detectorInstabilityEvents: 0,
        structureMismatchFields: pass1.metrics.missing + pass1.metrics.extra,
        pageClass: pageClass,
      ),
      passesCompleted: 1,
      // No evidence row is claimed: nothing is merged across passes, so there is
      // no cross-pass observation whose provenance could be resolved. The variant
      // raster hash is recorded in the run artifact for auditability instead.
      evidence: const <VariantObservation>[],
      mode: AdaptiveMode.hostEvaluation,
    ),
  );
  return PageRun(
    pageId: page.id,
    pageClass: pageClass,
    scored: true,
    undeclaredReason: null,
    pass1: pass1,
    pass2: pass2,
    decision: decision,
    quality: quality,
    fields: page.fields.length,
    variantIdentity: variant.identity,
  );
}

/// The pass-1 values the frozen trigger signals are measured from.
final class _PassSignals {
  const _PassSignals({
    required this.labels,
    required this.fieldCandidates,
    required this.unlabelledCandidates,
    required this.conflictPairs,
  });

  final int labels;
  final int fieldCandidates;
  final int unlabelledCandidates;
  final int conflictPairs;
}

_PassSignals _signalsFrom(PagePassResult pass1, SyntheticCorpusPage page) =>
    _PassSignals(
      labels: page.labels.length,
      fieldCandidates: pass1.fieldCandidates,
      unlabelledCandidates: pass1.unlabelledCandidates,
      conflictPairs: pass1.conflictPairs,
    );

PagePassResult _analyse({
  required SyntheticCorpusPage page,
  required GrayRaster raster,
  required int passNumber,
  required String variantId,
  required int variantPixels,
}) {
  final Stopwatch watch = Stopwatch()..start();
  final RasterAnalysis analysis = raster.analyze();
  final List<GeometryCandidate> candidates = GeometryDetector.detect(
    analysis,
    pageWidthPt: page.widthPt,
    pageHeightPt: page.heightPt,
  );
  final List<LabelObservation> labels = <LabelObservation>[
    for (final SyntheticCorpusLabel label in page.labels)
      LabelObservation(text: label.text, rect: label.rect, ocrConfidence: 0.9),
  ];
  final double medianHeight = _medianCandidateHeight(candidates);
  final List<FieldTypeHint> hints = <FieldTypeHint>[];
  final List<ObservedField> observed = <ObservedField>[];
  for (final GeometryCandidate candidate in candidates) {
    final TypeInferenceResult inference = TypeInference.infer(
      candidate: candidate,
      labels: labels,
      singleLineMedianHeightPt: medianHeight,
      pageWidthPt: page.widthPt,
      pageHeightPt: page.heightPt,
    );
    observed.add(
      ObservedField(
        pageIndex: 0,
        rect: candidate.rect,
        kind:
            fieldInventoryKindForSuggestionType(inference.proposedType) ??
            FieldInventoryKind.unknown,
        labelText: inference.labelText,
        provenance: 'suggestion',
      ),
    );
    hints.add(
      FieldTypeHint(rect: candidate.rect, proposedType: inference.proposedType),
    );
  }
  final FieldInventory inventory = FieldInventoryBuilder.build(
    pageIndex: 0,
    pageWidthPt: page.widthPt,
    pageHeightPt: page.heightPt,
    candidates: candidates,
    labels: labels,
    typeHints: hints,
  );
  final List<ExpectedField> expected = <ExpectedField>[
    for (final SyntheticGroundTruthField field in page.fields)
      ExpectedField(
        pageIndex: 0,
        rect: field.rect,
        kind: field.kind,
        labelText: field.labelText,
        sourceId: field.id,
      ),
  ];
  final StructureComparisonResult comparison = StructureComparison.compare(
    expected: expected,
    observed: observed,
    groundTruthPages: <int>{0},
  );
  watch.stop();
  final StructureMetrics metrics = StructureMetrics.fromComparison(
    expected: expected,
    observed: observed,
    result: comparison,
  );
  return PagePassResult(
    pageId: page.id,
    passNumber: passNumber,
    variantId: variantId,
    sourceRasterSha256: page.rasterSha256,
    inputRasterSha256: variantId == 'original'
        ? page.rasterSha256
        : sha256Hex(raster.pixels),
    elapsedMicros: watch.elapsedMicroseconds,
    variantPixels: variantPixels,
    observed: observed.length,
    metrics: metrics,
    fieldCandidates: inventory.fieldCandidates.length,
    unlabelledCandidates: inventory.coverage.unlabelledFieldCandidates,
    conflictPairs: _conflictPairs(observed),
  );
}

int _conflictPairs(List<ObservedField> observed) {
  final double threshold = StructureComparisonConfig.production.iouThreshold;
  int pairs = 0;
  for (int first = 0; first < observed.length; first++) {
    for (int second = first + 1; second < observed.length; second++) {
      if (iou(observed[first].rect, observed[second].rect) >= threshold) {
        pairs++;
      }
    }
  }
  return pairs;
}

double _medianCandidateHeight(List<GeometryCandidate> candidates) {
  if (candidates.isEmpty) {
    return 18;
  }
  final List<double> heights = <double>[
    for (final GeometryCandidate candidate in candidates) candidate.rect.height,
  ]..sort();
  final int count = heights.length;
  if (count.isOdd) {
    return heights[count ~/ 2];
  }
  return (heights[count ~/ 2 - 1] + heights[count ~/ 2]) / 2;
}

/// The only variant `renderStrategy.allowed` admits on this corpus.
///
/// `renderStrategy.allowed` lists exactly two transforms: the same-DPI contrast
/// stretch and the deskew at a *caller-supplied* angle.
/// `runtimeSignals.skew.metric` forbids estimating that angle and the declared
/// corpus carries none, so deskew cannot be exercised here and is reported as
/// not run instead of guessed. Both B and C use the contrast stretch, so B and C
/// differ only in *when* the second pass runs, never in what it is.
VariantRaster _variantFor({
  required GrayRaster raster,
  required PhotometricQuality quality,
  required int maxVariantPixels,
}) {
  checkVariantPixelBudget(
    widthPx: raster.width,
    heightPx: raster.height,
    maxVariantPixels: maxVariantPixels,
  );
  return renderContrastStretch(
    raster,
    p05Luminance: quality.p05Luminance,
    p95Luminance: quality.p95Luminance,
  );
}

ModeMetrics _aggregate(Mode mode, List<PageRun> pages) {
  int passes = pages.length;
  int expected = 0;
  int matched = 0;
  int observed = 0;
  int extra = 0;
  int missing = 0;
  int duplicate = 0;
  int duplicateUnmatched = 0;
  int kindMatched = 0;
  int labelledExpected = 0;
  int labelsAgree = 0;
  int typeMismatched = 0;
  int reviewNeeded = 0;
  int autoConfirmed = 0;
  int falseAccepts = 0;
  int wouldBeFalseAccepts = 0;
  int peakVariantPixels = 0;
  double matchedIouSum = 0;
  final List<int> latency = <int>[];
  for (final PageRun page in pages) {
    final PagePassResult result = page.resultFor(mode);
    final StructureMetrics metrics = result.metrics;
    switch (mode) {
      case Mode.a:
        break;
      case Mode.b:
        // B runs the second pass on every page.
        passes += 1;
      case Mode.c:
        // C runs it only where the frozen trigger permitted it.
        if (page.secondPassApplied) {
          passes += 1;
        }
    }
    if (mode != Mode.a && (mode == Mode.b || page.secondPassApplied)) {
      peakVariantPixels = math.max(peakVariantPixels, result.variantPixels);
    }
    expected += metrics.expected;
    matched += metrics.matched;
    observed += metrics.observed;
    extra += metrics.extra;
    missing += metrics.missing;
    duplicate += metrics.duplicate;
    duplicateUnmatched += metrics.duplicateUnmatched;
    kindMatched += metrics.kindMatched;
    labelledExpected += metrics.labelledExpected;
    labelsAgree += metrics.labelsAgree;
    typeMismatched += metrics.typeMismatched;
    reviewNeeded += metrics.reviewNeeded;
    autoConfirmed += metrics.autoConfirmed;
    falseAccepts += metrics.falseAccepts;
    wouldBeFalseAccepts += metrics.wouldBeFalseAccepts;
    matchedIouSum += metrics.meanMatchedIou * metrics.matched;
    latency.add(page.latencyMillisFor(mode));
  }
  return ModeMetrics(
    mode: mode,
    pageCount: pages.length,
    passes: passes,
    expected: expected,
    matched: matched,
    observed: observed,
    extra: extra,
    missing: missing,
    duplicateUnmatched: duplicateUnmatched,
    kindMatched: kindMatched,
    labelledExpected: labelledExpected,
    labelsAgree: labelsAgree,
    typeMismatched: typeMismatched,
    duplicate: duplicate,
    reviewNeeded: reviewNeeded,
    autoConfirmed: autoConfirmed,
    falseAccepts: falseAccepts,
    wouldBeFalseAccepts: wouldBeFalseAccepts,
    meanMatchedIou: matched == 0 ? 0 : matchedIouSum / matched,
    latencyMillis: List<int>.unmodifiable(latency),
    peakVariantPixels: peakVariantPixels,
  );
}

// ---------------------------------------------------------------------------
// Holdout discipline
// ---------------------------------------------------------------------------

/// The recorded holdout scorings of the frozen policy.
///
/// `corpusAndHoldout.rule` allows exactly one scoring of `holdoutPages`; a
/// holdout-driven change needs a new policy version and a new scored run. The
/// ledger makes that checkable: a second scoring for the same policy SHA-256 is
/// refused.
final class HoldoutLedger {
  HoldoutLedger._(this.entries);

  /// Reads [file]; an absent file is an empty ledger.
  static HoldoutLedger read(File file) {
    if (!file.existsSync()) {
      return HoldoutLedger._(const <Map<String, Object?>>[]);
    }
    final Map<String, Object?> document = _decodeObject(file, 'holdout ledger');
    return HoldoutLedger._(<Map<String, Object?>>[
      for (final Map<String, Object?> entry in _objectList(
        document,
        'holdoutScorings',
      ))
        entry,
    ]);
  }

  /// Recorded scorings, oldest first.
  final List<Map<String, Object?>> entries;

  /// Whether [policySha256] was already scored on the holdout.
  bool hasScored(String policySha256) => entries.any(
    (Map<String, Object?> entry) => entry['policySha256'] == policySha256,
  );

  /// Returns a ledger that additionally records one holdout scoring.
  HoldoutLedger record({
    required String policySha256,
    required String runId,
    required DateTime atUtc,
  }) => HoldoutLedger._(<Map<String, Object?>>[
    ...entries,
    <String, Object?>{
      'policySha256': policySha256,
      'runId': runId,
      'scoredAtUtc': atUtc.toUtc().toIso8601String(),
      'scorings': <String>['holdoutPages scored once'],
    },
  ]);

  /// Writes the ledger to [file].
  void write(File file) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{'schemaVersion': 1, 'task': 'T264D', 'rule': 'corpusAndHoldout.rule: holdoutPages are scored once at the end; a '
          'holdout-driven change requires a new policy version and a new '
          'scored run', 'holdoutScorings': entries})}\n',
    );
  }
}

/// Refuses a repeated holdout scoring for the same frozen policy.
void expectHoldoutNotScored({
  required HoldoutLedger ledger,
  required String policySha256,
}) {
  if (ledger.hasScored(policySha256)) {
    throw HoldoutAlreadyScoredException(
      'corpusAndHoldout.rule: the holdout was already scored for policy '
      '$policySha256. A repeated scoring would be holdout tuning; it needs a '
      'new policy version and a new scored run.',
    );
  }
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

const int _exitOk = 0;
const int _exitInvalid = 1;
const int _exitUsage = 2;
const int _exitOutcomeFailed = 3;
const int _exitHoldoutRefused = 4;

const String _help = '''
T264D A/B/C adaptive benchmark over the declared synthetic corpus (host-only).

Usage:
  adaptive_benchmark.dart --output <run.json> --score dev
  adaptive_benchmark.dart --output <run.json> --score holdout \\
      --holdout-ledger <ledger.json>
  adaptive_benchmark.dart --help

Options:
  --output PATH          Destination run artifact JSON (required).
  --score dev|holdout    Which frozen page set to score (required). `dev` is the
                         development set; `holdout` is scored once at the end.
  --holdout-ledger PATH  Ledger that records the single holdout scoring
                         (required with --score holdout).
  --help, -h             Show this help and exit 0.

Exit codes:
  0 run written, every declared acceptance outcome PASS
  1 I/O or internal failure; no run is written
  2 usage error (unknown, missing, or duplicate argument)
  3 run written, at least one declared acceptance outcome FAIL
  4 holdout refused: this policy already had its single holdout scoring

This tool proves no Android, emulator, device, OCR-engine, real-form, or
performance claim. Evidence class NONE.
''';

void main(List<String> arguments) {
  try {
    _run(arguments);
  } on _Usage catch (usage) {
    stderr.writeln('error: ${usage.message}');
    stderr.writeln('Run --help for the usage.');
    exitCode = _exitUsage;
  } on _Failure catch (failure) {
    stderr.writeln('error: ${failure.message}');
    exitCode = failure.exitCode;
  } on Object catch (error) {
    stderr.writeln('error: internal: $error');
    exitCode = _exitInvalid;
  }
}

final class _Usage implements Exception {
  const _Usage(this.message);

  final String message;
}

final class _Failure implements Exception {
  const _Failure(this.exitCode, this.message);

  final int exitCode;
  final String message;
}

void _run(List<String> arguments) {
  String? output;
  String? score;
  String? ledgerPath;
  for (int index = 0; index < arguments.length; index++) {
    final String argument = arguments[index];
    switch (argument) {
      case '--help':
      case '-h':
        stdout.write(_help);
        exitCode = _exitOk;
        return;
      case '--output':
        output = _value(arguments, index, 'output');
        index++;
      case '--score':
        score = _value(arguments, index, 'score');
        index++;
      case '--holdout-ledger':
        ledgerPath = _value(arguments, index, 'holdout-ledger');
        index++;
      default:
        throw _Usage('unknown-argument: $argument');
    }
  }
  if (output == null || output.isEmpty) {
    throw const _Usage('missing-value: output');
  }
  final ScoreSet scoreSet = switch (score) {
    'dev' => ScoreSet.dev,
    'holdout' => ScoreSet.holdout,
    null || '' => throw const _Usage('missing-value: score'),
    _ => throw _Usage('unknown-score: $score'),
  };
  if (scoreSet == ScoreSet.holdout &&
      (ledgerPath == null || ledgerPath.isEmpty)) {
    throw const _Usage(
      'missing-value: holdout-ledger (required with --score holdout)',
    );
  }

  final Directory directory = File.fromUri(Platform.script).parent;
  final File policyFile = File.fromUri(
    directory.uri.resolve('adaptive-policy.v1.json'),
  );
  final AdaptiveBenchmarkPolicy benchmark;
  final CorpusPartition partition;
  try {
    benchmark = AdaptiveBenchmarkPolicy.load(policyFile);
    partition = partitionCorpus(
      policy: benchmark.policy,
      pages: buildSyntheticCorpus(),
    );
  } on BenchmarkException catch (error) {
    throw _Failure(_exitInvalid, error.message);
  }

  final File? ledgerFile = ledgerPath == null ? null : File(ledgerPath);
  if (ledgerFile != null) {
    try {
      expectHoldoutNotScored(
        ledger: HoldoutLedger.read(ledgerFile),
        policySha256: benchmark.policySha256,
      );
    } on HoldoutAlreadyScoredException catch (error) {
      throw _Failure(_exitHoldoutRefused, error.message);
    }
  }

  final BenchmarkRun run;
  try {
    run = runBenchmark(
      benchmark: benchmark,
      pages: partition.of(scoreSet),
      scoreSet: scoreSet,
    );
  } on BenchmarkException catch (error) {
    throw _Failure(_exitInvalid, error.message);
  } on VariantBudgetException catch (error) {
    throw _Failure(_exitInvalid, error.message);
  }

  final File outputFile = File(output);
  try {
    outputFile.parent.createSync(recursive: true);
    outputFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(run.artifact)}\n',
    );
  } on FileSystemException catch (error) {
    throw _Failure(_exitInvalid, 'io: ${error.message}');
  }

  if (ledgerFile != null && scoreSet == ScoreSet.holdout) {
    try {
      HoldoutLedger.read(ledgerFile)
          .record(
            policySha256: benchmark.policySha256,
            runId: output,
            atUtc: DateTime.now().toUtc(),
          )
          .write(ledgerFile);
    } on FileSystemException catch (error) {
      throw _Failure(_exitInvalid, 'io: ${error.message}');
    }
  }

  final int failed = run.outcomes
      .where((OutcomeVerdict outcome) => !outcome.passed)
      .length;
  stdout.writeln(
    'benchmark written: scoreSet=${scoreSet.name} '
    'pages=${run.pages.length} '
    'passes(A/B/C)=${run.byMode[Mode.a]!.passes}/'
    '${run.byMode[Mode.b]!.passes}/${run.byMode[Mode.c]!.passes} '
    'outcomes=${run.outcomes.length - failed}/${run.outcomes.length} PASS '
    'noGain=${run.noGain}',
  );
  for (final OutcomeVerdict outcome in run.outcomes) {
    stdout.writeln(
      '${outcome.passed ? 'PASS' : 'FAIL'} ${outcome.text} '
      '(${outcome.detail})',
    );
  }
  for (final SyntheticCorpusPage page in partition.undeclared) {
    stdout.writeln(
      'UNSCORED ${page.id}: ${partition.undeclaredReasons[page.id]}',
    );
  }
  exitCode = failed == 0 ? _exitOk : _exitOutcomeFailed;
}

String _value(List<String> arguments, int index, String name) {
  if (index + 1 >= arguments.length) {
    throw _Usage('missing-value: $name');
  }
  return arguments[index + 1];
}

// ---------------------------------------------------------------------------
// JSON helpers
// ---------------------------------------------------------------------------

double _round6(double value) => (value * 1000000).round() / 1000000;

String _num(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

Map<String, Object?> _decodeObject(File file, String label) {
  final String text;
  try {
    text = file.readAsStringSync();
  } on FileSystemException catch (error) {
    throw BenchmarkException('cannot read $label ${file.path}: $error');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error) {
    throw BenchmarkException(
      '$label ${file.path} is not JSON: ${error.message}',
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw BenchmarkException('$label ${file.path} is not a JSON object');
  }
  return decoded;
}

Map<String, Object?> _map(Map<String, Object?> node, String key) {
  final Object? value = node[key];
  if (value is! Map<String, Object?>) {
    throw BenchmarkException('$key is missing or not a JSON object');
  }
  return value;
}

String _string(Map<String, Object?> node, String key) {
  final Object? value = node[key];
  if (value is! String) {
    throw BenchmarkException('$key is missing or not a string');
  }
  return value;
}

bool _bool(Map<String, Object?> node, String key) {
  final Object? value = node[key];
  if (value is! bool) {
    throw BenchmarkException('$key is missing or not a boolean');
  }
  return value;
}

List<String> _stringList(Map<String, Object?> node, String key) {
  final Object? value = node[key];
  if (value is! List<Object?>) {
    throw BenchmarkException('$key is missing or not a JSON array');
  }
  return <String>[
    for (final Object? entry in value)
      if (entry is String)
        entry
      else
        throw BenchmarkException('$key contains a non-string entry'),
  ];
}

List<Map<String, Object?>> _objectList(Map<String, Object?> node, String key) {
  final Object? value = node[key];
  if (value is! List<Object?>) {
    throw BenchmarkException('$key is missing or not a JSON array');
  }
  return <Map<String, Object?>>[
    for (final Object? entry in value)
      if (entry is Map<String, Object?>)
        entry
      else
        throw BenchmarkException('$key contains a non-object entry'),
  ];
}
