// T264C trigger/admissibility decision tests.
//
// This is a dependency-free host test harness, not a package:test suite:
//   dart tools/evaluation/adaptive_trigger_test.dart
//
// It proves the adaptive second-pass decision is driven by the *frozen* policy
// values only: a trigger inside its threshold requests nothing, a crossed
// threshold requests a pass with the frozen reason, the hysteresis band does not
// flip-flop, the pass/time/memory bounds and the pass-1 fallback are explicit,
// and a provenance rule (holdout, `minIndependentGroups`, correlated variants,
// pending variant hash) refuses the decision instead of guessing.
//
// The pinned values below are the contract: editing
// `tools/evaluation/adaptive-policy.v1.json` or
// `tools/evaluation/adaptive-provenance.v1.json` makes this harness fail.
//
// Host-only tooling. No raster, OCR, emulator, device, or measurement, and no
// SIMULATED/EMULATOR/DEVICE evidence.

import 'dart:convert';
import 'dart:io';

import 'adaptive_trigger.dart';
import 'validate_report.dart' show sha256Hex;

int _checks = 0;
int _failures = 0;

/// SHA-256 of `tools/evaluation/adaptive-policy.v1.json`, as bound by
/// `policyArtifact.sha256` in `tools/evaluation/adaptive-provenance.v1.json`.
const String _pinnedPolicySha256 =
    'eb940399ce1533aaa0a6dba4bba814b311a5041b06daeddc0f9866cacc40e073';

void main() {
  final Directory directory = File.fromUri(Platform.script).parent;
  final File policyFile = File.fromUri(
    directory.uri.resolve('adaptive-policy.v1.json'),
  );
  final AdaptivePolicy policy;
  try {
    policy = AdaptivePolicy.load(policyFile);
  } on AdaptivePolicyException catch (error) {
    stderr.writeln('cannot load the frozen policy: $error');
    exitCode = 1;
    return;
  }

  _group('frozen policy', () {
    _check('pins the consumed values of the frozen policy', () {
      _expect(policy.artifactId == 'feldexa.adaptive-ocr-policy', 'artifactId');
      _expect(policy.version == '1.0.0', 'version');
      _expect(policy.status == 'frozen-before-run', 'status');
      _expect(policy.implementation == 'BLOCKED', 'implementation');
      _expect(policy.lowContrast.enterBelow == 96, 'enterBelow');
      _expect(policy.lowContrast.leaveAbove == 112, 'leaveAbove');
      _expect(policy.lowContrast.hysteresisPoints == 16, 'hysteresisPoints');
      _expect(policy.skew.enterAbove == 0.5, 'skew enterAbove');
      _expect(policy.skew.leaveBelow == 0.25, 'skew leaveBelow');
      _expect(policy.ocrFailureEnters, 'ocrFailure.enterAt');
      _expect(policy.missingLabel.enterAtOrAbove == 0.5, 'missingLabel');
      _expect(policy.missingLabel.minimumFieldCandidates == 3, 'minCandidates');
      _expect(policy.conflict.enterAtOrAbove == 1, 'conflict');
      _expect(!policy.structureMismatchIsRuntimeTrigger, 'structureMismatch');
      _expect(policy.bounds.maxPassesPerPage == 2, 'maxPassesPerPage');
      _expect(policy.bounds.maxElapsedMsPerPage == 4000, 'maxElapsedMsPerPage');
      _expect(policy.bounds.maxVariantPixels == 8000000, 'maxVariantPixels');
      _expect(policy.bounds.maxConcurrentPasses == 1, 'maxConcurrentPasses');
      _expect(policy.bounds.maxVariantRastersInMemory == 1, 'maxRasters');
      _expect(policy.provenance.minIndependentGroups == 2, 'minGroups');
      _expect(
        policy.provenance.maxObservationsPerCorrelationGroup == 1,
        'maxObservationsPerCorrelationGroup',
      );
      _expect(
        !policy.provenance.twoIndependentOcrLinesAgree,
        'twoIndependentOcrLinesAgree',
      );
      _expect(
        policy.provenance.forbiddenClaims.contains(
          'twoIndependentOcrLinesAgree',
        ),
        'forbiddenClaims',
      );
      _expect(policy.holdoutPages.length == 4, 'holdoutPages');
    });

    _check('pins the frozen policy bytes', () {
      final String digest = sha256Hex(policyFile.readAsBytesSync());
      _expect(
        digest == _pinnedPolicySha256,
        'the frozen policy drifted: $digest != $_pinnedPolicySha256',
      );
    });

    _check('rejects an inconsistent hysteresis band', () {
      final File mutated = _mutatedPolicy('bad-hysteresis', (
        Map<String, Object?> policy,
      ) {
        _lowContrast(policy)['leaveAbove'] = 100;
      });
      _expectThrows<AdaptivePolicyException>(
        () => AdaptivePolicy.load(mutated),
      );
    });

    _check(
      'reads the thresholds from the file instead of duplicating them',
      () {
        final File mutated = _mutatedPolicy('enter-below-60', (
          Map<String, Object?> policy,
        ) {
          _lowContrast(policy)['enterBelow'] = 60;
          _lowContrast(policy)['hysteresisPoints'] = 52;
        });
        final AdaptivePolicy relaxed = AdaptivePolicy.load(mutated);
        _expect(relaxed.lowContrast.enterBelow == 60, 'mutated enterBelow');
        final AdaptiveDecision decision = decideAdaptiveTrigger(
          policy: relaxed,
          request: TriggerRequest(signals: _signals(p95Luminance: 140)),
        );
        _expect(
          decision.verdict == Verdict.noSecondPass,
          'contrastSpread 90 must not trigger against a mutated enterBelow 60',
        );
      },
    );
  });

  _group('trigger thresholds', () {
    _check('inside the threshold requests no second pass', () {
      final AdaptiveDecision decision = _decide(_signals(p95Luminance: 200));
      _expect(decision.verdict == Verdict.noSecondPass, 'verdict');
      _expect(decision.triggers.isEmpty, 'no trigger may fire');
      _expect(decision.rejection == null, 'no rejection');
      _expect(
        _hasReason(decision, 'runtimeSignals.lowContrast.enterBelow=96.0'),
        'the reason must name the frozen threshold: ${decision.reasons}',
      );
    });

    _check('a crossed threshold requests a second pass with the reason', () {
      final AdaptiveDecision decision = _decide(_signals(p95Luminance: 110));
      _expect(decision.verdict == Verdict.secondPass, 'verdict');
      _expect(decision.triggers.length == 1, 'exactly one trigger');
      final TriggerHit hit = decision.triggers.single;
      _expect(hit.trigger == Trigger.lowContrast, 'trigger');
      _expect(
        hit.policyPath == 'runtimeSignals.lowContrast.enterBelow',
        'path',
      );
      _expect(hit.threshold == 96, 'threshold 96');
      _expect(hit.observed == 90, 'observed spread 90');
      _expect(!hit.heldByHysteresis, 'not held by hysteresis');
      _expect(
        _hasReason(
          decision,
          'contrastSpread=90.0 < runtimeSignals.lowContrast',
        ),
        'the reason must name metric and threshold: ${decision.reasons}',
      );
    });

    _check('every declared runtime trigger fires on its own threshold', () {
      _expect(
        _decide(_signals(skewDegrees: 0.6)).triggers.single.trigger ==
            Trigger.skew,
        'skew > 0.5',
      );
      _expect(
        _decide(_signals(ocrFailed: true)).triggers.single.trigger ==
            Trigger.ocrFailure,
        'OCR failure',
      );
      _expect(
        _decide(_signals(unlabeledCandidates: 3)).triggers.single.trigger ==
            Trigger.missingLabel,
        'unlabelled fraction 3/6 >= 0.5',
      );
      _expect(
        _decide(_signals(conflictPairs: 1)).triggers.single.trigger ==
            Trigger.conflict,
        'one conflict pair',
      );
    });

    _check('the unlabelled fraction needs the minimum candidate count', () {
      final AdaptiveDecision decision = _decide(
        _signals(fieldCandidates: 2, unlabeledCandidates: 2),
      );
      _expect(decision.verdict == Verdict.noSecondPass, 'verdict');
      _expect(
        decision.ignoredSignals.any(
          (SignalNote note) =>
              note.signal == 'missingLabel' &&
              note.reason.contains('minimumFieldCandidates=3'),
        ),
        'the fraction is not evaluable below 3 candidates: '
        '${decision.ignoredSignals.map((SignalNote note) => note.reason)}',
      );
    });
  });

  _group('hysteresis', () {
    _check('a latched trigger stays latched inside the band', () {
      for (final double spread in <double>[96, 100, 105, 111, 112]) {
        final AdaptiveDecision latched = _decide(
          _signals(p95Luminance: 20 + spread),
          latched: const <Trigger>{Trigger.lowContrast},
        );
        _expect(
          latched.verdict == Verdict.secondPass && latched.triggers.length == 1,
          'spread $spread must stay latched',
        );
        _expect(latched.triggers.single.heldByHysteresis, 'held by hysteresis');
        _expect(
          latched.triggers.single.policyPath ==
              'runtimeSignals.lowContrast.leaveAbove',
          'held against leaveAbove',
        );
        _expect(latched.latched.contains(Trigger.lowContrast), 'latched out');
      }
    });

    _check('an unlatched trigger does not enter inside the band', () {
      for (final double spread in <double>[96, 100, 105, 111, 112]) {
        final AdaptiveDecision fresh = _decide(
          _signals(p95Luminance: 20 + spread),
        );
        _expect(
          fresh.verdict == Verdict.noSecondPass,
          'spread $spread must not enter without a latch',
        );
      }
    });

    _check('a latched trigger is released above the leave threshold', () {
      final AdaptiveDecision released = _decide(
        _signals(p95Luminance: 133),
        latched: const <Trigger>{Trigger.lowContrast},
      );
      _expect(released.verdict == Verdict.noSecondPass, 'verdict');
      _expect(released.latched.isEmpty, 'nothing stays latched');
      _expect(
        _hasReason(released, 'runtimeSignals.lowContrast.leaveAbove=112.0'),
        'the release must name the leave threshold: ${released.reasons}',
      );
    });

    _check('the skew band holds the same way', () {
      _expect(
        _decide(
          _signals(skewDegrees: 0.3),
          latched: const <Trigger>{Trigger.skew},
        ).triggers.single.heldByHysteresis,
        'skew 0.3 stays latched above leaveBelow 0.25',
      );
      _expect(
        _decide(_signals(skewDegrees: 0.3)).verdict == Verdict.noSecondPass,
        'skew 0.3 does not enter below enterAbove 0.5',
      );
      _expect(
        _decide(
          _signals(skewDegrees: 0.2),
          latched: const <Trigger>{Trigger.skew},
        ).latched.isEmpty,
        'skew 0.2 releases below leaveBelow 0.25',
      );
    });
  });

  _group('bounds', () {
    _check('every decision carries the frozen pass/time/memory bounds', () {
      final AdaptiveDecision decision = _decide(_signals(p95Luminance: 110));
      _expect(decision.bounds.maxPassesPerPage == 2, 'maxPassesPerPage');
      _expect(decision.bounds.passesCompleted == 0, 'passesCompleted');
      _expect(decision.bounds.passesRemaining == 2, 'passesRemaining');
      _expect(decision.bounds.maxElapsedMsPerPage == 4000, 'maxElapsedMs');
      _expect(decision.bounds.maxVariantPixels == 8000000, 'maxVariantPixels');
      _expect(decision.bounds.maxVariantRastersInMemory == 1, 'maxRasters');
      _expect(
        decision.secondPassFailureRule == policy.bounds.pageFailureIsolation,
        'the pass-1 fallback is returned, not commented',
      );
    });

    _check('maxPasses reached stops escalation', () {
      final AdaptiveDecision decision = _decide(
        _signals(p95Luminance: 90, ocrFailed: true, conflictPairs: 4),
        passesCompleted: 2,
      );
      _expect(decision.verdict == Verdict.noSecondPass, 'verdict');
      _expect(decision.triggers.isEmpty, 'no trigger escapes the budget');
      _expect(decision.bounds.passesRemaining == 0, 'passesRemaining');
      _expect(
        _hasReason(decision, 'passBudgetExhausted'),
        'the budget must be the reason: ${decision.reasons}',
      );
    });

    _check('a failed second pass keeps the pass-1 result', () {
      _expect(
        resolveSecondPassOutcome<String>(
              pass1: 'pass-1',
              pass2: 'pass-2',
              pass2Failed: true,
            ) ==
            'pass-1',
        'a failed second pass must not replace the pass-1 result',
      );
      _expect(
        resolveSecondPassOutcome<String>(
              pass1: 'pass-1',
              pass2: 'pass-2',
              pass2Failed: false,
            ) ==
            'pass-2',
        'a successful second pass replaces it',
      );
      _expect(
        resolveSecondPassOutcome<String>(
              pass1: 'pass-1',
              pass2: null,
              pass2Failed: false,
            ) ==
            'pass-1',
        'an absent second pass keeps the pass-1 result',
      );
    });
  });

  _group('provenance', () {
    _check('correlated variants are not independent evidence', () {
      final AdaptiveDecision decision = _decide(
        _signals(p95Luminance: 110),
        evidence: const <VariantObservation>[
          VariantObservation(
            variantId: 'clean-200dpi',
            correlationGroup: 'group-pdfium-200',
          ),
          VariantObservation(
            variantId: 'contrastStretch-200dpi',
            correlationGroup: 'group-pdfium-200',
          ),
        ],
      );
      _expect(decision.verdict == Verdict.rejected, 'verdict');
      _expect(decision.rejection?.code == 'correlationLimited', 'code');
      _expect(decision.independentGroups == 1, 'one independent group');
      _expect(decision.selectedEvidence.length == 1, 'one observation kept');
      _expect(
        decision.droppedEvidence.single.variantId == 'contrastStretch-200dpi',
        'the repeated group member is dropped',
      );
      _expect(
        decision.rejection?.message.contains('minIndependentGroups=2') ?? false,
        'the refusal must name the frozen rule: '
        '${decision.rejection?.message}',
      );
    });

    _check('two independent groups are admissible', () {
      final AdaptiveDecision decision = _decide(
        _signals(p95Luminance: 110),
        evidence: const <VariantObservation>[
          VariantObservation(
            variantId: 'clean-200dpi',
            correlationGroup: 'group-pdfium-200',
          ),
          VariantObservation(
            variantId: 'clean-150dpi',
            correlationGroup: 'group-pdfium-150',
          ),
        ],
      );
      _expect(decision.rejection == null, 'not refused');
      _expect(decision.independentGroups == 2, 'two independent groups');
      _expect(decision.selectedEvidence.length == 2, 'two observations kept');
      _expect(decision.droppedEvidence.isEmpty, 'nothing dropped');
      _expect(decision.verdict == Verdict.secondPass, 'trigger decides');
    });

    _check('a pending variant hash produces no evidence row', () {
      final AdaptiveDecision decision = _decide(
        _signals(p95Luminance: 110),
        evidence: const <VariantObservation>[
          VariantObservation(
            variantId: 'clean-200dpi',
            correlationGroup: 'group-pdfium-200',
          ),
          VariantObservation(
            variantId: 'scan-150dpi-low-contrast',
            correlationGroup: 'group-poppler-150',
            rasterHashRecorded: false,
          ),
        ],
      );
      _expect(decision.verdict == Verdict.rejected, 'verdict');
      _expect(
        decision.independentGroups == 1,
        'the pending hash carries no row',
      );
      _expect(
        _hasReason(decision, 'hashGate'),
        'the hash gate must be named: ${decision.reasons}',
      );
    });
  });

  _group('refusals', () {
    _check('production is refused while the policy is blocked', () {
      final AdaptiveDecision decision = _decide(
        _signals(p95Luminance: 110),
        mode: AdaptiveMode.production,
      );
      _expect(decision.verdict == Verdict.rejected, 'verdict');
      _expect(
        decision.rejection?.code == 'policyImplementationBlocked',
        'code',
      );
      _expect(
        decision.rejection?.message.contains('BLOCKED') ?? false,
        'the refusal must quote the frozen state: ${decision.rejection?.message}',
      );
    });

    _check('a repeated holdout scoring is refused', () {
      final AdaptiveDecision decision = _decide(
        _signals(
          p95Luminance: 110,
          pageClass: PageClass.holdout,
          holdoutAlreadyScored: true,
        ),
      );
      _expect(decision.verdict == Verdict.rejected, 'verdict');
      _expect(decision.rejection?.code == 'holdoutAlreadyScored', 'code');
      _expect(
        decision.rejection?.message.contains('scored once') ?? false,
        'the refusal must quote the holdout rule: ${decision.rejection?.message}',
      );
    });

    _check('unfrozen signals never trigger a pass', () {
      final AdaptiveDecision decision = _decide(
        _signals(
          p95Luminance: 200,
          detectorInstabilityEvents: 99,
          structureMismatchFields: 99,
        ),
      );
      _expect(decision.verdict == Verdict.noSecondPass, 'verdict');
      _expect(decision.triggers.isEmpty, 'no trigger');
      for (final String signal in <String>[
        'detectorInstability',
        'structureMismatch',
      ]) {
        _expect(
          decision.ignoredSignals.any(
            (SignalNote note) => note.signal == signal,
          ),
          '$signal must be reported as non-decisive',
        );
      }
    });
  });

  stdout.writeln('\n$_checks checks, $_failures failure(s)');
  if (_failures > 0) {
    exitCode = 1;
  }
}

PageSignals _signals({
  double p05Luminance = 20,
  double p95Luminance = 200,
  double? skewDegrees,
  bool ocrFailed = false,
  int fieldCandidates = 6,
  int unlabeledCandidates = 0,
  int conflictPairs = 0,
  int detectorInstabilityEvents = 0,
  int structureMismatchFields = 0,
  PageClass pageClass = PageClass.dev,
  bool holdoutAlreadyScored = false,
}) => PageSignals(
  p05Luminance: p05Luminance,
  p95Luminance: p95Luminance,
  skewDegrees: skewDegrees,
  ocrFailed: ocrFailed,
  fieldCandidates: fieldCandidates,
  unlabeledCandidates: unlabeledCandidates,
  conflictPairs: conflictPairs,
  detectorInstabilityEvents: detectorInstabilityEvents,
  structureMismatchFields: structureMismatchFields,
  pageClass: pageClass,
  holdoutAlreadyScored: holdoutAlreadyScored,
);

AdaptiveDecision _decide(
  PageSignals signals, {
  int passesCompleted = 0,
  Set<Trigger> latched = const <Trigger>{},
  List<VariantObservation> evidence = const <VariantObservation>[],
  AdaptiveMode mode = AdaptiveMode.hostEvaluation,
}) {
  final File policyFile = File.fromUri(
    File.fromUri(Platform.script).parent.uri.resolve('adaptive-policy.v1.json'),
  );
  return decideAdaptiveTrigger(
    policy: AdaptivePolicy.load(policyFile),
    request: TriggerRequest(
      signals: signals,
      passesCompleted: passesCompleted,
      latched: latched,
      evidence: evidence,
      mode: mode,
    ),
  );
}

bool _hasReason(AdaptiveDecision decision, String needle) =>
    decision.reasons.any((String reason) => reason.contains(needle));

Map<String, Object?> _lowContrast(Map<String, Object?> policy) =>
    (policy['runtimeSignals']! as Map<String, Object?>)['lowContrast']!
        as Map<String, Object?>;

/// Writes a mutated copy of both frozen artifacts so a load sees the change.
File _mutatedPolicy(
  String name,
  void Function(Map<String, Object?> policy) mutate,
) {
  final Directory source = File.fromUri(Platform.script).parent;
  final Directory target = Directory('.dart_tool/adaptive_trigger_test/$name');
  if (target.existsSync()) {
    target.deleteSync(recursive: true);
  }
  target.createSync(recursive: true);
  _copyArtifact(source, target, 'adaptive-provenance.v1.json');

  final Map<String, Object?> policy = jsonDecode(
    File.fromUri(source.uri.resolve('adaptive-policy.v1.json'))
        .readAsStringSync(),
  ) as Map<String, Object?>;
  mutate(policy);
  final File mutated = File('${target.path}/adaptive-policy.v1.json');
  mutated.writeAsStringSync(jsonEncode(policy));
  return mutated;
}

void _group(String name, void Function() body) {
  stdout.writeln('== $name ==');
  body();
}

void _check(String name, void Function() body) {
  _checks++;
  try {
    body();
    stdout.writeln('PASS $name');
  } catch (error) {
    _failures++;
    stdout.writeln('FAIL $name: $error');
  }
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

void _expectThrows<T extends Object>(void Function() body) {
  try {
    body();
  } on T {
    return;
  }
  throw StateError('expected $T');
}

/// Copies one frozen artifact into [target] unchanged.
void _copyArtifact(Directory source, Directory target, String name) {
  File.fromUri(source.uri.resolve(name)).copySync('${target.path}/$name');
}
