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
//    claims), the declared variant -> correlation-group mapping
//    (`variants[].id` / `variants[].correlationGroup`), and the
//    `excludedVariants[].id` list. An observation whose variant is undeclared,
//    excluded, or claims a group other than its declared one is dropped
//    (`correlationRule.failClosed`) instead of counted as independent.
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
import 'dart:math' as math;

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
    required this.variantGroups,
    required this.excludedVariants,
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

  /// Declared variant id -> declared `correlationGroup` (`variants[]` of the
  /// provenance artifact). A variant id outside this map has no declared
  /// derivation and carries no usable evidence.
  final Map<String, String> variantGroups;

  /// `excludedVariants[].id`: declared as out of scope, never evidence.
  final Set<String> excludedVariants;

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

    final Map<String, String> variantGroups = <String, String>{
      for (final Map<String, Object?> variant in _objectList(
        provenance,
        'variants',
      ))
        _string(variant, 'id'): _string(variant, 'correlationGroup'),
    };
    final Set<String> excludedVariants = <String>{
      for (final Map<String, Object?> variant in _objectList(
        provenance,
        'excludedVariants',
      ))
        _string(variant, 'id'),
    };

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
      variantGroups: variantGroups,
      excludedVariants: excludedVariants,
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
/// [rasterHashRecorded] mirrors the provenance `hashGate`: only a variant whose
/// `variantRasterSha256` was captured produces an evidence row. It defaults to
/// `false`, so the caller has to assert the captured hash explicitly with
/// `rasterHashRecorded: true`; every other observation is treated as
/// `PENDING_RUN` and carries no evidence row.
final class VariantObservation {
  const VariantObservation({
    required this.variantId,
    required this.correlationGroup,
    this.rasterHashRecorded = false,
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

  /// Signals that were supplied but carry no frozen runtime rule, or that cannot
  /// be evaluated below a frozen minimum.
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
  final PageSignals signals = request.signals;
  final PassBounds limits = policy.bounds;
  final AdaptiveBounds bounds = AdaptiveBounds(
    maxPassesPerPage: limits.maxPassesPerPage,
    passesCompleted: request.passesCompleted,
    passesRemaining: math.max(
      0,
      limits.maxPassesPerPage - request.passesCompleted,
    ),
    maxElapsedMsPerPage: limits.maxElapsedMsPerPage,
    maxVariantPixels: limits.maxVariantPixels,
    maxConcurrentPasses: limits.maxConcurrentPasses,
    maxVariantRastersInMemory: limits.maxVariantRastersInMemory,
    pageFailureIsolation: limits.pageFailureIsolation,
  );
  final _EvidenceSet evidence = _selectEvidence(policy, request.evidence);
  final List<SignalNote> ignored = <SignalNote>[
    SignalNote(
      signal: 'structureMismatch',
      reason:
          'runtimeSignals.structureMismatch.runtimeTrigger='
          '${policy.structureMismatchIsRuntimeTrigger}: structure comparison is '
          'evaluation-only (observed ${signals.structureMismatchFields} '
          'mismatched field(s)); it never triggers a pass',
    ),
    SignalNote(
      signal: 'detectorInstability',
      reason:
          'not declared in runtimeSignals: observed '
          '${signals.detectorInstabilityEvents} instable candidate(s), recorded '
          'only; the frozen policy has no threshold, so it never triggers and '
          'no value is guessed',
    ),
  ];
  final List<String> reasons = <String>[...evidence.notes];

  AdaptiveDecision refuse(String code, String message) => AdaptiveDecision(
    verdict: Verdict.rejected,
    reasons: <String>[...reasons, '$code: $message'],
    triggers: const <TriggerHit>[],
    ignoredSignals: ignored,
    latched: request.latched,
    bounds: bounds,
    selectedEvidence: evidence.selected,
    droppedEvidence: evidence.dropped,
    independentGroups: evidence.independentGroups,
    rejection: Rejection(code: code, message: message),
    secondPassFailureRule: limits.pageFailureIsolation,
  );

  if (request.mode == AdaptiveMode.production &&
      policy.implementation == 'BLOCKED') {
    return refuse(
      'policyImplementationBlocked',
      '${policy.artifactId} ${policy.version} is ${policy.status} with '
          'implementation: BLOCKED, so no production adaptive pass is decided. '
          'The page keeps its pass-1 result.',
    );
  }
  if (signals.pageClass == PageClass.holdout && signals.holdoutAlreadyScored) {
    return refuse(
      'holdoutAlreadyScored',
      'corpusAndHoldout.rule: holdoutPages are scored once, so a repeated '
          'holdout scoring is refused; a holdout-driven change needs a new policy '
          'version. Rule text: ${policy.holdoutRule}',
    );
  }
  if (request.passesCompleted >= limits.maxPassesPerPage) {
    reasons.add(
      'passBudgetExhausted: passesCompleted=${request.passesCompleted} >= '
      'bounds.maxPassesPerPage=${limits.maxPassesPerPage}; no further '
      'escalation, the page keeps its current result',
    );
    return AdaptiveDecision(
      verdict: Verdict.noSecondPass,
      reasons: reasons,
      triggers: const <TriggerHit>[],
      ignoredSignals: ignored,
      latched: request.latched,
      bounds: bounds,
      selectedEvidence: evidence.selected,
      droppedEvidence: evidence.dropped,
      independentGroups: evidence.independentGroups,
      rejection: null,
      secondPassFailureRule: limits.pageFailureIsolation,
    );
  }
  if (request.evidence.isNotEmpty &&
      evidence.independentGroups < policy.provenance.minIndependentGroups) {
    return refuse(
      'correlationLimited',
      'decisionRule.minIndependentGroups='
          '${policy.provenance.minIndependentGroups}: the offered evidence covers '
          '${evidence.independentGroups} independent correlation group(s) '
          '(${evidence.groups.join(', ')}). A repeated group is not independent '
          'evidence, so the request is refused instead of counted '
          '(decisionRule.insufficientGroupsOutcome).',
    );
  }

  final List<TriggerHit> triggers = <TriggerHit>[];
  final LowContrastRule lowContrast = policy.lowContrast;
  final double spread = signals.contrastSpread;
  final bool contrastLatched = request.latched.contains(Trigger.lowContrast);
  if (contrastLatched && spread <= lowContrast.leaveAbove) {
    triggers.add(
      TriggerHit(
        trigger: Trigger.lowContrast,
        metric: 'contrastSpread (p95 - p05 luminance)',
        policyPath: 'runtimeSignals.lowContrast.leaveAbove',
        threshold: lowContrast.leaveAbove,
        observed: spread,
        heldByHysteresis: true,
      ),
    );
    reasons.add(
      'lowContrast: held latched, contrastSpread=${_num(spread)} <= '
      'runtimeSignals.lowContrast.leaveAbove='
      '${_num(lowContrast.leaveAbove)}',
    );
  } else if (!contrastLatched && spread < lowContrast.enterBelow) {
    triggers.add(
      TriggerHit(
        trigger: Trigger.lowContrast,
        metric: 'contrastSpread (p95 - p05 luminance)',
        policyPath: 'runtimeSignals.lowContrast.enterBelow',
        threshold: lowContrast.enterBelow,
        observed: spread,
        heldByHysteresis: false,
      ),
    );
    reasons.add(
      'lowContrast: contrastSpread=${_num(spread)} < '
      'runtimeSignals.lowContrast.enterBelow='
      '${_num(lowContrast.enterBelow)}',
    );
  } else if (contrastLatched) {
    reasons.add(
      'lowContrast: released, contrastSpread=${_num(spread)} > '
      'runtimeSignals.lowContrast.leaveAbove='
      '${_num(lowContrast.leaveAbove)}; it does not re-enter below '
      'runtimeSignals.lowContrast.enterBelow='
      '${_num(lowContrast.enterBelow)}',
    );
  } else {
    reasons.add(
      'lowContrast: not triggered, contrastSpread=${_num(spread)} >= '
      'runtimeSignals.lowContrast.enterBelow='
      '${_num(lowContrast.enterBelow)} (release only above '
      'runtimeSignals.lowContrast.leaveAbove='
      '${_num(lowContrast.leaveAbove)})',
    );
  }

  final SkewRule skew = policy.skew;
  final double? measuredSkew = signals.skewDegrees;
  final bool skewLatched = request.latched.contains(Trigger.skew);
  if (measuredSkew == null) {
    ignored.add(
      const SignalNote(
        signal: 'skew',
        reason:
            'runtimeSignals.skew.metric is caller-supplied; the policy forbids '
            'estimating it, so an absent angle is not triggered',
      ),
    );
  } else {
    // runtimeSignals.skew.metric is the absolute angle, so a reading of -3°
    // is 3° of skew and is compared as such.
    final double skewDegrees = measuredSkew.abs();
    if (skewLatched && skewDegrees >= skew.leaveBelow) {
      triggers.add(
        TriggerHit(
          trigger: Trigger.skew,
          metric: 'caller-supplied absolute skew in degrees',
          policyPath: 'runtimeSignals.skew.leaveBelow',
          threshold: skew.leaveBelow,
          observed: skewDegrees,
          heldByHysteresis: true,
        ),
      );
      reasons.add(
        'skew: held latched, |skewDegrees|=${_num(skewDegrees)} >= '
        'runtimeSignals.skew.leaveBelow=${_num(skew.leaveBelow)}',
      );
    } else if (!skewLatched && skewDegrees > skew.enterAbove) {
      triggers.add(
        TriggerHit(
          trigger: Trigger.skew,
          metric: 'caller-supplied absolute skew in degrees',
          policyPath: 'runtimeSignals.skew.enterAbove',
          threshold: skew.enterAbove,
          observed: skewDegrees,
          heldByHysteresis: false,
        ),
      );
      reasons.add(
        'skew: |skewDegrees|=${_num(skewDegrees)} > '
        'runtimeSignals.skew.enterAbove=${_num(skew.enterAbove)}',
      );
    } else {
      reasons.add(
        'skew: not triggered, |skewDegrees|=${_num(skewDegrees)} outside '
        'enterAbove=${_num(skew.enterAbove)} / '
        'leaveBelow=${_num(skew.leaveBelow)} with latched=$skewLatched',
      );
    }
  }

  if (policy.ocrFailureEnters && signals.ocrFailed) {
    triggers.add(
      TriggerHit(
        trigger: Trigger.ocrFailure,
        metric: 'OCR port threw or produced zero usable label lines',
        policyPath: 'runtimeSignals.ocrFailure.enterAt',
        threshold: policy.ocrFailureEnters ? 1 : 0,
        observed: 1,
        heldByHysteresis: false,
      ),
    );
    reasons.add(
      'ocrFailure: OCR failed or produced no usable label line '
      '(runtimeSignals.ocrFailure.enterAt=${policy.ocrFailureEnters})',
    );
  } else {
    reasons.add(
      'ocrFailure: not triggered, ocrFailed=${signals.ocrFailed} against '
      'runtimeSignals.ocrFailure.enterAt=${policy.ocrFailureEnters}',
    );
  }

  final MissingLabelRule missingLabel = policy.missingLabel;
  if (signals.fieldCandidates < missingLabel.minimumFieldCandidates) {
    ignored.add(
      SignalNote(
        signal: 'missingLabel',
        reason:
            'not evaluable: fieldCandidates=${signals.fieldCandidates} < '
            'runtimeSignals.missingLabel.minimumFieldCandidates='
            '${missingLabel.minimumFieldCandidates}, so the unlabelled fraction '
            'is not computed and not guessed',
      ),
    );
  } else {
    final double unlabeledFraction =
        signals.unlabeledCandidates / signals.fieldCandidates;
    if (unlabeledFraction >= missingLabel.enterAtOrAbove) {
      triggers.add(
        TriggerHit(
          trigger: Trigger.missingLabel,
          metric: 'unlabelled field candidates / all field candidates',
          policyPath: 'runtimeSignals.missingLabel.enterAtOrAbove',
          threshold: missingLabel.enterAtOrAbove,
          observed: unlabeledFraction,
          heldByHysteresis: false,
        ),
      );
      reasons.add(
        'missingLabel: unlabelledFraction=${_num(unlabeledFraction)} >= '
        'runtimeSignals.missingLabel.enterAtOrAbove='
        '${_num(missingLabel.enterAtOrAbove)} '
        '(${signals.unlabeledCandidates}/${signals.fieldCandidates})',
      );
    } else {
      reasons.add(
        'missingLabel: not triggered, unlabelledFraction='
        '${_num(unlabeledFraction)} < '
        'runtimeSignals.missingLabel.enterAtOrAbove='
        '${_num(missingLabel.enterAtOrAbove)}',
      );
    }
  }

  final ConflictRule conflict = policy.conflict;
  if (signals.conflictPairs >= conflict.enterAtOrAbove) {
    triggers.add(
      TriggerHit(
        trigger: Trigger.conflict,
        metric: 'conflict-graph pairs with IoU >= 0.5',
        policyPath: 'runtimeSignals.conflict.enterAtOrAbove',
        threshold: conflict.enterAtOrAbove,
        observed: signals.conflictPairs.toDouble(),
        heldByHysteresis: false,
      ),
    );
    reasons.add(
      'conflict: conflictPairs=${signals.conflictPairs} >= '
      'runtimeSignals.conflict.enterAtOrAbove='
      '${_num(conflict.enterAtOrAbove)}',
    );
  } else {
    reasons.add(
      'conflict: not triggered, conflictPairs=${signals.conflictPairs} < '
      'runtimeSignals.conflict.enterAtOrAbove='
      '${_num(conflict.enterAtOrAbove)}',
    );
  }

  final Set<Trigger> latched = <Trigger>{
    for (final TriggerHit hit in triggers) hit.trigger,
  };
  if (triggers.isEmpty) {
    reasons.add(
      'noSecondPass: no frozen runtime trigger fired, so the page stays at its '
      'pass-1 result',
    );
    return AdaptiveDecision(
      verdict: Verdict.noSecondPass,
      reasons: reasons,
      triggers: triggers,
      ignoredSignals: ignored,
      latched: latched,
      bounds: bounds,
      selectedEvidence: evidence.selected,
      droppedEvidence: evidence.dropped,
      independentGroups: evidence.independentGroups,
      rejection: null,
      secondPassFailureRule: limits.pageFailureIsolation,
    );
  }
  reasons.add(
    'secondPass: ${triggers.length} frozen runtime trigger(s) fired '
    '(${triggers.map((TriggerHit hit) => hit.trigger.name).join(', ')}); '
    'passesRemaining=${bounds.passesRemaining}, '
    'maxElapsedMsPerPage=${limits.maxElapsedMsPerPage}, '
    'maxVariantPixels=${limits.maxVariantPixels}. A failed second pass returns '
    'the pass-1 result.',
  );
  return AdaptiveDecision(
    verdict: Verdict.secondPass,
    reasons: reasons,
    triggers: triggers,
    ignoredSignals: ignored,
    latched: latched,
    bounds: bounds,
    selectedEvidence: evidence.selected,
    droppedEvidence: evidence.dropped,
    independentGroups: evidence.independentGroups,
    rejection: null,
    secondPassFailureRule: limits.pageFailureIsolation,
  );
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
  if (pass2Failed || pass2 == null) {
    return pass1;
  }
  return pass2;
}

/// The evidence set after the provenance `hashGate`, the `correlationRule`
/// declaration check, and the per-group cap.
final class _EvidenceSet {
  _EvidenceSet({
    required this.selected,
    required this.dropped,
    required this.groups,
    required this.notes,
  });

  final List<VariantObservation> selected;
  final List<VariantObservation> dropped;
  final List<String> groups;
  final List<String> notes;

  int get independentGroups => groups.length;
}

_EvidenceSet _selectEvidence(
  AdaptivePolicy policy,
  List<VariantObservation> observations,
) {
  final List<VariantObservation> selected = <VariantObservation>[];
  final List<VariantObservation> dropped = <VariantObservation>[];
  final List<String> groups = <String>[];
  final List<String> notes = <String>[];
  final Map<String, int> perGroup = <String, int>{};
  for (final VariantObservation observation in observations) {
    if (policy.excludedVariants.contains(observation.variantId)) {
      dropped.add(observation);
      notes.add(
        'evidence.failClosed: ${observation.variantId} is declared in '
        'excludedVariants and produces no evidence row; it is dropped instead '
        'of counted as independent (correlationRule.failClosed)',
      );
      continue;
    }
    final String? declaredGroup = policy.variantGroups[observation.variantId];
    if (declaredGroup == null) {
      dropped.add(observation);
      notes.add(
        'evidence.failClosed: ${observation.variantId} is not a declared '
        'variant of adaptive-provenance.v1.json, so its derivation cannot be '
        'resolved; it is dropped instead of counted as independent '
        '(correlationRule.failClosed)',
      );
      continue;
    }
    if (declaredGroup != observation.correlationGroup) {
      dropped.add(observation);
      notes.add(
        'evidence.failClosed: ${observation.variantId} is declared in '
        'correlationGroup $declaredGroup but the observation claims '
        '${observation.correlationGroup}; it is dropped instead of counted as '
        'independent (correlationRule.failClosed)',
      );
      continue;
    }
    if (!observation.rasterHashRecorded) {
      dropped.add(observation);
      notes.add(
        'evidence.hashGate: ${observation.variantId} has '
        'variantRasterSha256Status PENDING_RUN and produces no evidence row '
        '(decisionRule.hashGate)',
      );
      continue;
    }
    final int seen = perGroup[observation.correlationGroup] ?? 0;
    if (seen >= policy.provenance.maxObservationsPerCorrelationGroup) {
      dropped.add(observation);
      notes.add(
        'evidence.groupCap: ${observation.variantId} repeats correlationGroup '
        '${observation.correlationGroup}; '
        'decisionRule.maxObservationsPerCorrelationGroup='
        '${policy.provenance.maxObservationsPerCorrelationGroup} keeps one '
        'observation per group',
      );
      continue;
    }
    perGroup[observation.correlationGroup] = seen + 1;
    selected.add(observation);
    if (!groups.contains(observation.correlationGroup)) {
      groups.add(observation.correlationGroup);
    }
  }
  return _EvidenceSet(
    selected: selected,
    dropped: dropped,
    groups: groups,
    notes: notes,
  );
}

String _num(double value) => value.toString();

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

List<Map<String, Object?>> _objectList(Map<String, Object?> node, String key) {
  final Object? value = node[key];
  if (value is! List<Object?>) {
    throw AdaptivePolicyException('$key is missing or not a JSON array');
  }
  return <Map<String, Object?>>[
    for (final Object? entry in value)
      if (entry is Map<String, Object?>)
        entry
      else
        throw AdaptivePolicyException('$key contains a non-object entry'),
  ];
}
