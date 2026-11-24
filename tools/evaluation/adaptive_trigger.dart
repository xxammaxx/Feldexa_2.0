// T264C first slice: host-only trigger and admissibility decision for the
// adaptive second analysis pass.
//
// Normative sources:
//  * `tools/evaluation/adaptive-policy.v1.json` — `frozen-before-run`,
//    `implementation: BLOCKED`, consumed read-only. Every threshold, hysteresis
//    point, pass/elapsed/memory bound, and the page-failure rule are loaded from
//    that file; this module holds no numeric duplicate and retunes nothing.
//  * `tools/evaluation/adaptive-provenance.v1.json` — `decisionRule`
//    (`minIndependentGroups`, `maxObservationsPerCorrelationGroup`, forbidden
//    claims) and `correlationGroups`.
//
// What this module decides. Given one page's measured signal set it answers
// whether a second analysis pass is permitted, which trigger fired against which
// frozen threshold, and which bounds apply. A request that would need a rule the
// frozen artifacts do not contain is refused (`Verdict.rejected`) instead of
// guessed.
//
// What this module does not do. No UI, no pipeline wiring, no raster or OCR
// work, no measurement, no evidence class. It produces no SIMULATED, EMULATOR,
// or DEVICE evidence and no SC claim; SC-001/SC-003/SC-004 stay with T142, T136,
// and T141.
//
// Usage:
//   final AdaptivePolicy policy = AdaptivePolicy.load(policyFile);
//   final AdaptiveDecision decision = decideAdaptiveTrigger(
//     policy: policy,
//     request: TriggerRequest(signals: signals),
//   );

import 'dart:convert';
import 'dart:io';

/// Page corpus class from `corpusAndHoldout` in the frozen policy.
///
/// `holdoutPages` are scored once; a holdout-driven change needs a new policy
/// version, so a second holdout scoring is refused rather than repeated.
enum PageClass { dev, holdout }

/// Why the caller asks for the decision.
///
/// `production` is the future wired path. It is refused while the frozen policy
/// keeps `implementation: BLOCKED`; host evaluation (tests, evidence tooling)
/// stays permitted.
enum AdaptiveMode { hostEvaluation, production }

/// The five runtime triggers `runtimeSignals` declares.
///
/// Structure mismatch and detector instability are deliberately absent: the
/// policy declares structure comparison evaluation-only and has no frozen
/// threshold for detector instability, so neither can trigger a pass.
enum Trigger { lowContrast, skew, ocrFailure, missingLabel, conflict }

/// Outcome of one trigger/admissibility decision.
enum Verdict { noSecondPass, secondPass, rejected }

/// A frozen artifact is unreadable, inconsistent, or missing a consumed value.
final class AdaptivePolicyException implements Exception {
  AdaptivePolicyException(this.message);

  final String message;

  @override
  String toString() => 'AdaptivePolicyException: $message';
}

/// `runtimeSignals.lowContrast`.
final class LowContrastRule {
  const LowContrastRule({
    required this.enterBelow,
    required this.leaveAbove,
    required this.hysteresisPoints,
  });

  final double enterBelow;
  final double leaveAbove;
  final double hysteresisPoints;
}

/// `runtimeSignals.skew`.
final class SkewRule {
  const SkewRule({required this.enterAbove, required this.leaveBelow});

  final double enterAbove;
  final double leaveBelow;
}

/// `runtimeSignals.missingLabel`.
final class MissingLabelRule {
  const MissingLabelRule({
    required this.enterAtOrAbove,
    required this.minimumFieldCandidates,
  });

  final double enterAtOrAbove;
  final int minimumFieldCandidates;
}

/// `runtimeSignals.conflict`.
final class ConflictRule {
  const ConflictRule({required this.enterAtOrAbove});

  final double enterAtOrAbove;
}

/// `bounds` of the frozen policy.
final class PassBounds {
  const PassBounds({
    required this.maxPassesPerPage,
    required this.maxElapsedMsPerPage,
    required this.maxVariantPixels,
    required this.maxConcurrentPasses,
    required this.maxVariantRastersInMemory,
    required this.pageFailureIsolation,
  });

  final int maxPassesPerPage;
  final int maxElapsedMsPerPage;
  final int maxVariantPixels;
  final int maxConcurrentPasses;
  final int maxVariantRastersInMemory;
  final String pageFailureIsolation;
}

/// `decisionRule` of the frozen provenance artifact.
final class ProvenanceRule {
  const ProvenanceRule({
    required this.minIndependentGroups,
    required this.maxObservationsPerCorrelationGroup,
    required this.twoIndependentOcrLinesAgree,
    required this.forbiddenClaims,
  });

  final int minIndependentGroups;
  final int maxObservationsPerCorrelationGroup;
  final bool twoIndependentOcrLinesAgree;
  final List<String> forbiddenClaims;
}

/// The frozen policy values this module consumes.
final class AdaptivePolicy {
  AdaptivePolicy._({
    required this.artifactId,
    required this.version,
    required this.status,
    required this.implementation,
    required this.lowContrast,
    required this.skew,
    required this.ocrFailureEnters,
    required this.missingLabel,
    required this.conflict,
    required this.structureMismatchIsRuntimeTrigger,
    required this.bounds,
    required this.provenance,
    required this.devPages,
    required this.holdoutPages,
    required this.holdoutRule,
  });

  final String artifactId;
  final String version;
  final String status;
  final String implementation;
  final LowContrastRule lowContrast;
  final SkewRule skew;
  final bool ocrFailureEnters;
  final MissingLabelRule missingLabel;
  final ConflictRule conflict;
  final bool structureMismatchIsRuntimeTrigger;
  final PassBounds bounds;
  final ProvenanceRule provenance;
  final List<String> devPages;
  final List<String> holdoutPages;
  final String holdoutRule;

  /// Loads the frozen policy and the provenance `decisionRule` beside it.
  ///
  /// The provenance artifact is read from the same directory as [policyFile].
  static AdaptivePolicy load(File policyFile) {
    final Map<String, Object?> document = _decodeObject(
      policyFile,
      'frozen policy',
    );
    final File provenanceFile = File.fromUri(
      policyFile.absolute.parent.uri.resolve('adaptive-provenance.v1.json'),
    );
    final Map<String, Object?> provenance = _decodeObject(
      provenanceFile,
      'frozen provenance',
    );

    final Map<String, Object?> runtimeSignals = _map(
      document,
      'runtimeSignals',
    );
    final Map<String, Object?> lowContrast = _map(
      runtimeSignals,
      'lowContrast',
    );
    final Map<String, Object?> skew = _map(runtimeSignals, 'skew');
    final Map<String, Object?> ocrFailure = _map(runtimeSignals, 'ocrFailure');
    final Map<String, Object?> missingLabel = _map(
      runtimeSignals,
      'missingLabel',
    );
    final Map<String, Object?> conflict = _map(runtimeSignals, 'conflict');
    final Map<String, Object?> structureMismatch = _map(
      runtimeSignals,
      'structureMismatch',
    );
    final Map<String, Object?> bounds = _map(document, 'bounds');
    final Map<String, Object?> corpus = _map(document, 'corpusAndHoldout');
    final Map<String, Object?> decisionRule = _map(provenance, 'decisionRule');

    final LowContrastRule lowContrastRule = LowContrastRule(
      enterBelow: _double(lowContrast, 'enterBelow'),
      leaveAbove: _double(lowContrast, 'leaveAbove'),
      hysteresisPoints: _double(lowContrast, 'hysteresisPoints'),
    );
    if (lowContrastRule.leaveAbove - lowContrastRule.enterBelow !=
        lowContrastRule.hysteresisPoints) {
      throw AdaptivePolicyException(
        'runtimeSignals.lowContrast: hysteresisPoints '
        '${lowContrastRule.hysteresisPoints} does not match '
        'leaveAbove - enterBelow '
        '(${lowContrastRule.leaveAbove} - ${lowContrastRule.enterBelow})',
      );
    }
    final SkewRule skewRule = SkewRule(
      enterAbove: _double(skew, 'enterAbove'),
      leaveBelow: _double(skew, 'leaveBelow'),
    );
    if (skewRule.leaveBelow > skewRule.enterAbove) {
      throw AdaptivePolicyException(
        'runtimeSignals.skew: leaveBelow ${skewRule.leaveBelow} must not exceed '
        'enterAbove ${skewRule.enterAbove}',
      );
    }

    return AdaptivePolicy._(
      artifactId: _string(document, 'artifactId'),
      version: _string(document, 'version'),
      status: _string(document, 'status'),
      implementation: _string(document, 'implementation'),
      lowContrast: lowContrastRule,
      skew: skewRule,
      ocrFailureEnters: _bool(ocrFailure, 'enterAt'),
      missingLabel: MissingLabelRule(
        enterAtOrAbove: _double(missingLabel, 'enterAtOrAbove'),
        minimumFieldCandidates: _integer(
          missingLabel,
          'minimumFieldCandidates',
        ),
      ),
      conflict: ConflictRule(
        enterAtOrAbove: _double(conflict, 'enterAtOrAbove'),
      ),
      structureMismatchIsRuntimeTrigger: _bool(
        structureMismatch,
        'runtimeTrigger',
      ),
      bounds: PassBounds(
        maxPassesPerPage: _integer(bounds, 'maxPassesPerPage'),
        maxElapsedMsPerPage: _integer(bounds, 'maxElapsedMsPerPage'),
        maxVariantPixels: _integer(bounds, 'maxVariantPixels'),
        maxConcurrentPasses: _integer(bounds, 'maxConcurrentPasses'),
        maxVariantRastersInMemory: _integer(
          bounds,
          'maxVariantRastersInMemory',
        ),
        pageFailureIsolation: _string(bounds, 'pageFailureIsolation'),
      ),
      provenance: ProvenanceRule(
        minIndependentGroups: _integer(decisionRule, 'minIndependentGroups'),
        maxObservationsPerCorrelationGroup: _integer(
          decisionRule,
          'maxObservationsPerCorrelationGroup',
        ),
        twoIndependentOcrLinesAgree: _bool(
          decisionRule,
          'twoIndependentOcrLinesAgree',
        ),
        forbiddenClaims: _stringList(decisionRule, 'forbiddenClaims'),
      ),
      devPages: _stringList(corpus, 'devPages'),
      holdoutPages: _stringList(corpus, 'holdoutPages'),
      holdoutRule: _string(corpus, 'rule'),
    );
  }
}

/// One page's measured runtime signals.
///
/// The photometric values are measured on the photometric original, never on a
/// binarised derivative (`runtimeSignals.measuredOn`). `skewDegrees` is
/// caller-supplied: the policy forbids estimating it, so `null` means unknown
/// and never triggers.
final class PageSignals {
  const PageSignals({
    required this.p05Luminance,
    required this.p95Luminance,
    this.skewDegrees,
    this.ocrFailed = false,
    this.fieldCandidates = 0,
    this.unlabeledCandidates = 0,
    this.conflictPairs = 0,
    this.detectorInstabilityEvents = 0,
    this.structureMismatchFields = 0,
    this.pageClass = PageClass.dev,
    this.holdoutAlreadyScored = false,
  });

  final double p05Luminance;
  final double p95Luminance;
  final double? skewDegrees;
  final bool ocrFailed;
  final int fieldCandidates;
  final int unlabeledCandidates;
  final int conflictPairs;

  /// Recorded for the report, never decisive: the frozen policy declares no
  /// threshold for it.
  final int detectorInstabilityEvents;

  /// Recorded for the report, never decisive: structure comparison is
  /// evaluation-only (`runtimeSignals.structureMismatch.runtimeTrigger`).
  final int structureMismatchFields;

  final PageClass pageClass;
  final bool holdoutAlreadyScored;

  /// `p95Luminance - p05Luminance` (nearest-rank percentiles).
  double get contrastSpread => p95Luminance - p05Luminance;
}

/// One adaptive variant observation offered as corroborating evidence.
///
/// [rasterHashRecorded] mirrors the provenance `hashGate`: a variant whose
/// `variantRasterSha256` is still `PENDING_RUN` produces no evidence row.
final class VariantObservation {
  const VariantObservation({
    required this.variantId,
    required this.correlationGroup,
    this.rasterHashRecorded = true,
  });

  final String variantId;
  final String correlationGroup;
  final bool rasterHashRecorded;
}

/// One request for a trigger/admissibility decision.
final class TriggerRequest {
  const TriggerRequest({
    required this.signals,
    this.passesCompleted = 0,
    this.latched = const <Trigger>{},
    this.evidence = const <VariantObservation>[],
    this.mode = AdaptiveMode.hostEvaluation,
  });

  final PageSignals signals;

  /// Analysis passes already completed for this page (0 or 1 in v1).
  final int passesCompleted;

  /// Triggers currently latched by an earlier decision for the same page; this
  /// is what makes the hysteresis band meaningful.
  final Set<Trigger> latched;

  /// Variant observations the caller presents as independent corroboration.
  final List<VariantObservation> evidence;

  final AdaptiveMode mode;
}

/// One fired trigger with the frozen value it fired against.
final class TriggerHit {
  const TriggerHit({
    required this.trigger,
    required this.metric,
    required this.policyPath,
    required this.threshold,
    required this.observed,
    required this.heldByHysteresis,
  });

  final Trigger trigger;
  final String metric;

  /// Dotted path of the frozen policy value, e.g.
  /// `runtimeSignals.lowContrast.enterBelow`.
  final String policyPath;
  final double threshold;
  final double observed;

  /// `true` when the trigger stays latched through the leave threshold instead
  /// of re-entering through the stricter enter threshold.
  final bool heldByHysteresis;
}

/// A signal that was seen but carries no frozen rule.
final class SignalNote {
  const SignalNote({required this.signal, required this.reason});

  final String signal;
  final String reason;
}

/// A refusal: the request needs a rule the frozen artifacts do not provide.
final class Rejection {
  const Rejection({required this.code, required this.message});

  final String code;
  final String message;
}

/// The explicit pass/time/memory limits attached to every decision.
final class AdaptiveBounds {
  const AdaptiveBounds({
    required this.maxPassesPerPage,
    required this.passesCompleted,
    required this.passesRemaining,
    required this.maxElapsedMsPerPage,
    required this.maxVariantPixels,
    required this.maxConcurrentPasses,
    required this.maxVariantRastersInMemory,
    required this.pageFailureIsolation,
  });

  final int maxPassesPerPage;
  final int passesCompleted;
  final int passesRemaining;
  final int maxElapsedMsPerPage;
  final int maxVariantPixels;
  final int maxConcurrentPasses;
  final int maxVariantRastersInMemory;

  /// `bounds.pageFailureIsolation`: a failed adaptive pass returns the pass-1
  /// result unchanged and never removes page geometry.
  final String pageFailureIsolation;
}

/// The decision: verdict, reasons, bounds, and the evidence bookkeeping.
final class AdaptiveDecision {
  const AdaptiveDecision({
    required this.verdict,
    required this.reasons,
    required this.triggers,
    required this.ignoredSignals,
    required this.latched,
    required this.bounds,
    required this.selectedEvidence,
    required this.droppedEvidence,
    required this.independentGroups,
    required this.rejection,
    required this.secondPassFailureRule,
  });

  final Verdict verdict;

  /// One line per considered signal: which frozen value it was compared to and
  /// what the outcome was. This is the auditable part of the decision.
  final List<String> reasons;
  final List<TriggerHit> triggers;

  /// Signals that were supplied but have no frozen runtime rule.
  final List<SignalNote> ignoredSignals;

  /// Triggers latched after this decision; pass them to the next request for the
  /// same page to keep the hysteresis band stable.
  final Set<Trigger> latched;

  final AdaptiveBounds bounds;
  final List<VariantObservation> selectedEvidence;
  final List<VariantObservation> droppedEvidence;

  /// Distinct correlation groups in [selectedEvidence]; the observation count is
  /// never the evidence count.
  final int independentGroups;

  final Rejection? rejection;
  final String secondPassFailureRule;
}

/// Decides whether a second analysis pass is permitted for one page.
///
/// The four admissible refusals are ordered: a blocked implementation, a
/// repeated holdout scoring, an insufficient pass budget, and correlation-limited
/// evidence. Everything else is decided only against `runtimeSignals`.
AdaptiveDecision decideAdaptiveTrigger({
  required AdaptivePolicy policy,
  required TriggerRequest request,
}) {
  throw UnimplementedError('T264C RED: trigger decision not implemented');
}

/// Picks the effective result of a second pass.
///
/// A failed or absent second pass leaves the pass-1 result unchanged
/// (`bounds.pageFailureIsolation`).
T resolveSecondPassOutcome<T>({
  required T pass1,
  required T? pass2,
  required bool pass2Failed,
}) {
  throw UnimplementedError('T264C RED: second-pass fallback not implemented');
}

Map<String, Object?> _decodeObject(File file, String label) {
  final String text;
  try {
    text = file.readAsStringSync();
  } on FileSystemException catch (error) {
    throw AdaptivePolicyException('cannot read $label ${file.path}: $error');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error) {
    throw AdaptivePolicyException(
      '$label ${file.path} is not JSON: ${error.message}',
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw AdaptivePolicyException('$label ${file.path} is not a JSON object');
  }
  return decoded;
}

Map<String, Object?> _map(Map<String, Object?> node, String key) {
  final Object? value = node[key];
  if (value is! Map<String, Object?>) {
    throw AdaptivePolicyException('$key is missing or not a JSON object');
  }
  return value;
}

double _double(Map<String, Object?> node, String key) {
  final Object? value = node[key];
  if (value is! num) {
    throw AdaptivePolicyException('$key is missing or not a number');
  }
  return value.toDouble();
}

int _integer(Map<String, Object?> node, String key) {
  final Object? value = node[key];
  if (value is! int) {
    throw AdaptivePolicyException('$key is missing or not an integer');
  }
  return value;
}

bool _bool(Map<String, Object?> node, String key) {
  final Object? value = node[key];
  if (value is! bool) {
    throw AdaptivePolicyException('$key is missing or not a boolean');
  }
  return value;
}

String _string(Map<String, Object?> node, String key) {
  final Object? value = node[key];
  if (value is! String) {
    throw AdaptivePolicyException('$key is missing or not a string');
  }
  return value;
}

List<String> _stringList(Map<String, Object?> node, String key) {
  final Object? value = node[key];
  if (value is! List<Object?>) {
    throw AdaptivePolicyException('$key is missing or not a JSON array');
  }
  return <String>[
    for (final Object? entry in value)
      if (entry is String)
        entry
      else
        throw AdaptivePolicyException('$key contains a non-string entry'),
  ];
}
