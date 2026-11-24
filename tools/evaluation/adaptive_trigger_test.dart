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
// pending variant hash, excluded, undeclared or misgrouped variant, undeclared
// correlation group) refuses the decision instead of guessing.
//
// Both frozen artifacts are byte-pinned by SHA-256 below, and every compared
// threshold is proven to come from the file rather than from this harness: the
// mutation copies are written to a system temp directory and removed again, so a
// run leaves no artifact behind, in this tree or in a foreign working directory.
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

/// SHA-256 of `tools/evaluation/adaptive-provenance.v1.json` itself.
///
/// The consumed `decisionRule` values and variant mappings above are
/// value-pinned; this pin makes the whole artifact byte-pinned, so a note or
/// reason edit fails the harness as well.
const String _pinnedProvenanceSha256 =
    '50af51a9eab0def559b1100b2d9b1b290062cc414008d3f13596f174d8146c72';

void main() {
  final Directory directory = File.fromUri(Platform.script).parent;
  final File policyFile = File.fromUri(
    directory.uri.resolve('adaptive-policy.v1.json'),
  );
  final File provenanceFile = File.fromUri(
    directory.uri.resolve('adaptive-provenance.v1.json'),
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

    _check('pins the frozen provenance bytes', () {
      final String digest = sha256Hex(provenanceFile.readAsBytesSync());
      _expect(
        digest == _pinnedProvenanceSha256,
        'the frozen provenance drifted: $digest != $_pinnedProvenanceSha256',
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
          request: TriggerRequest(signals: _signals(p95Luminance: 110)),
        );
        _expect(
          decision.verdict == Verdict.noSecondPass,
          'contrastSpread 90 must not trigger against a mutated enterBelow 60, '
          'so a hardcoded 96 would enter here',
        );

        // The same proof for a second threshold: the skew band is read from the
        // file too, so a hardcoded enterAbove is caught here.
        final File mutatedBand = _mutatedPolicy('skew-band-2-0', (
          Map<String, Object?> policy,
        ) {
          final Map<String, Object?> skew =
              (policy['runtimeSignals']! as Map<String, Object?>)['skew']!
                  as Map<String, Object?>;
          skew['enterAbove'] = 2.0;
          skew['leaveBelow'] = 1.5;
        });
        final AdaptivePolicy widenedSkew = AdaptivePolicy.load(mutatedBand);
        _expect(widenedSkew.skew.enterAbove == 2.0, 'mutated skew enterAbove');
        final AdaptiveDecision skewDecision = decideAdaptiveTrigger(
          policy: widenedSkew,
          request: TriggerRequest(signals: _signals(skewDegrees: 1)),
        );
        _expect(
          skewDecision.verdict == Verdict.noSecondPass,
          'a 1 degree skew must not trigger against a mutated enterAbove 2.0, '
          'so a hardcoded 0.5 would enter here',
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

    _check('a negative skew enters as its absolute angle', () {
      final AdaptiveDecision decision = _decide(_signals(skewDegrees: -3));
      _expect(decision.verdict == Verdict.secondPass, 'verdict');
      _expect(decision.triggers.length == 1, 'exactly one trigger');
      final TriggerHit hit = decision.triggers.single;
      _expect(hit.trigger == Trigger.skew, 'trigger');
      _expect(
        hit.policyPath == 'runtimeSignals.skew.enterAbove',
        'the entry is measured against enterAbove: ${hit.policyPath}',
      );
      _expect(
        hit.observed == 3,
        'runtimeSignals.skew.metric is the absolute angle, so -3 is 3: '
        '${hit.observed}',
      );
      _expect(
        _hasReason(decision, '|skewDegrees|=3.0 > '),
        'the reason must report the absolute value: ${decision.reasons}',
      );
    });

    _check('a disabled ocrFailure entry fires in neither direction', () {
      final File mutated = _mutatedPolicy('ocr-failure-disabled', (
        Map<String, Object?> policy,
      ) {
        final Map<String, Object?> runtimeSignals =
            policy['runtimeSignals']! as Map<String, Object?>;
        final Map<String, Object?> ocrFailure =
            runtimeSignals['ocrFailure']! as Map<String, Object?>;
        ocrFailure['enterAt'] = false;
      });
      final AdaptivePolicy disabled = AdaptivePolicy.load(mutated);
      final AdaptiveDecision failed = decideAdaptiveTrigger(
        policy: disabled,
        request: TriggerRequest(signals: _signals(ocrFailed: true)),
      );
      _expect(failed.verdict == Verdict.noSecondPass, 'verdict');
      _expect(
        failed.triggers.isEmpty,
        'enterAt=false must not enter on a failed OCR port',
      );
      _expect(
        _hasReason(failed, 'runtimeSignals.ocrFailure.enterAt=false'),
        'the reason must render the loaded value: ${failed.reasons}',
      );
      final AdaptiveDecision succeeded = decideAdaptiveTrigger(
        policy: disabled,
        request: TriggerRequest(signals: _signals()),
      );
      _expect(
        succeeded.triggers.isEmpty,
        'enterAt=false must not enter on a successful OCR port either',
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

    _check('a latched negative skew is held as its absolute angle', () {
      final AdaptiveDecision held = _decide(
        _signals(skewDegrees: -0.3),
        latched: const <Trigger>{Trigger.skew},
      );
      _expect(held.verdict == Verdict.secondPass, 'verdict');
      _expect(held.triggers.length == 1, 'exactly one trigger');
      final TriggerHit hit = held.triggers.single;
      _expect(hit.trigger == Trigger.skew, 'trigger');
      _expect(
        hit.policyPath == 'runtimeSignals.skew.leaveBelow',
        'the hold is measured against leaveBelow: ${hit.policyPath}',
      );
      _expect(
        hit.observed == 0.3,
        'the leave branch compares the absolute angle too, so -0.3 is 0.3: '
        '${hit.observed}',
      );
      _expect(hit.heldByHysteresis, 'held by hysteresis');
      _expect(
        _hasReason(held, 'skew: held latched, |skewDegrees|=0.3 >='),
        'the reason must report the absolute value: ${held.reasons}',
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
          // rasterHashRecorded: true is the post-capture state, not the current
          // tree (every variant hash is still PENDING_RUN there).
          VariantObservation(
            variantId: 'clean-200dpi',
            correlationGroup: 'group-pdfium-200',
            rasterHashRecorded: true,
          ),
          VariantObservation(
            variantId: 'contrastStretch-200dpi',
            correlationGroup: 'group-pdfium-200',
            rasterHashRecorded: true,
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
          // rasterHashRecorded: true is the post-capture state, not the current
          // tree (every variant hash is still PENDING_RUN there). The
          // correlation groups are the ones declared in
          // adaptive-provenance.v1.json.
          VariantObservation(
            variantId: 'clean-200dpi',
            correlationGroup: 'group-pdfium-200',
            rasterHashRecorded: true,
          ),
          VariantObservation(
            variantId: 'clean-150dpi',
            correlationGroup: 'group-pdfium-150',
            rasterHashRecorded: true,
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
            rasterHashRecorded: true,
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

    _check('the hash gate defaults to fail-closed', () {
      // rasterHashRecorded is not asserted here, so both declared variants stay
      // PENDING_RUN and carry no evidence row.
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
      _expect(decision.verdict == Verdict.rejected, 'verdict');
      _expect(decision.rejection?.code == 'correlationLimited', 'code');
      _expect(decision.independentGroups == 0, 'no independent group');
      _expect(decision.selectedEvidence.isEmpty, 'no observation selected');
      _expect(
        decision.droppedEvidence.length == 2,
        'both observations dropped',
      );
      _expect(
        _hasReason(decision, 'hashGate'),
        'the default must name the hash gate: ${decision.reasons}',
      );
      _expect(
        _hasReason(decision, 'minIndependentGroups=2'),
        'the refusal must name the frozen rule: ${decision.reasons}',
      );
    });

    _check('a correlation-limited refusal without a group renders none', () {
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
      _expect(decision.rejection?.code == 'correlationLimited', 'code');
      _expect(decision.independentGroups == 0, 'no independent group');
      final String message = decision.rejection?.message ?? '';
      _expect(
        message.contains('covers 0 independent correlation group(s) (none)'),
        'an empty group list must render as none: $message',
      );
      _expect(
        !message.contains('()'),
        'no empty pair of parentheses in the refusal: $message',
      );
    });

    _check('an undeclared variant is dropped, not counted', () {
      final AdaptiveDecision decision = _decide(
        _signals(p95Luminance: 110),
        evidence: const <VariantObservation>[
          VariantObservation(
            variantId: 'made-up-200dpi',
            correlationGroup: 'group-pdfium-200',
            rasterHashRecorded: true,
          ),
          VariantObservation(
            variantId: 'clean-150dpi',
            correlationGroup: 'group-pdfium-150',
            rasterHashRecorded: true,
          ),
        ],
      );
      _expect(decision.verdict == Verdict.rejected, 'verdict');
      _expect(decision.rejection?.code == 'correlationLimited', 'code');
      _expect(decision.independentGroups == 1, 'one declared group only');
      _expect(decision.selectedEvidence.length == 1, 'one observation kept');
      _expect(
        decision.droppedEvidence.single.variantId == 'made-up-200dpi',
        'the undeclared variant is dropped: '
        '${decision.droppedEvidence.map((VariantObservation o) => o.variantId)}',
      );
      _expect(
        _hasReason(decision, 'failClosed'),
        'the refusal must name correlationRule.failClosed: '
        '${decision.reasons}',
      );
    });

    _check('an excluded variant is dropped with its own note', () {
      final AdaptiveDecision decision = _decide(
        _signals(p95Luminance: 110),
        evidence: const <VariantObservation>[
          // region-render-2x is declared in excludedVariants[] and in no
          // variants[], so only the exclusion gate can explain this drop.
          VariantObservation(
            variantId: 'region-render-2x',
            correlationGroup: 'group-pdfium-200',
            rasterHashRecorded: true,
          ),
          VariantObservation(
            variantId: 'clean-150dpi',
            correlationGroup: 'group-pdfium-150',
            rasterHashRecorded: true,
          ),
        ],
      );
      _expect(decision.verdict == Verdict.rejected, 'verdict');
      _expect(decision.rejection?.code == 'correlationLimited', 'code');
      _expect(decision.independentGroups == 1, 'one declared group only');
      _expect(
        decision.droppedEvidence.single.variantId == 'region-render-2x',
        'the excluded variant is dropped: '
        '${decision.droppedEvidence.map((VariantObservation o) => o.variantId)}',
      );
      _expect(
        _hasReason(
          decision,
          'region-render-2x is declared in excludedVariants',
        ),
        'the drop must name excludedVariants[]: ${decision.reasons}',
      );
    });

    _check('a group contradicting the declaration is dropped, not counted', () {
      final AdaptiveDecision decision = _decide(
        _signals(p95Luminance: 110),
        evidence: const <VariantObservation>[
          // clean-200dpi is declared in group-pdfium-200, not group-pdfium-150.
          VariantObservation(
            variantId: 'clean-200dpi',
            correlationGroup: 'group-pdfium-150',
            rasterHashRecorded: true,
          ),
          VariantObservation(
            variantId: 'clean-150dpi',
            correlationGroup: 'group-pdfium-150',
            rasterHashRecorded: true,
          ),
        ],
      );
      _expect(decision.verdict == Verdict.rejected, 'verdict');
      _expect(decision.rejection?.code == 'correlationLimited', 'code');
      _expect(decision.independentGroups == 1, 'one declared group only');
      _expect(decision.selectedEvidence.length == 1, 'one observation kept');
      _expect(
        decision.droppedEvidence.single.variantId == 'clean-200dpi',
        'the contradicting observation is dropped: '
        '${decision.droppedEvidence.map((VariantObservation o) => o.variantId)}',
      );
      _expect(
        _hasReason(decision, 'failClosed'),
        'the refusal must name correlationRule.failClosed: '
        '${decision.reasons}',
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

  _group('test hygiene', () {
    _check('mutation artifacts live in a system temp directory', () {
      final File mutated = _mutatedPolicy('cwd-probe', (
        Map<String, Object?> policy,
      ) {
        _lowContrast(policy)['leaveAbove'] = 100;
      });
      _expect(
        mutated.path.startsWith(Directory.systemTemp.path),
        'the mutated artifact must live under ${Directory.systemTemp.path}: '
        '${mutated.path}',
      );
      _expect(
        !mutated.path.contains('.dart_tool/adaptive_trigger_test'),
        'no scratch directory in the tree: ${mutated.path}',
      );
      _expect(
        !mutated.path.startsWith(Directory.current.path),
        'the mutated artifact must not be written under the caller CWD: '
        '${mutated.path}',
      );
    });

    _check('the scratch directory is removed again', () {
      final File mutated = _mutatedPolicy('cleanup-probe', (
        Map<String, Object?> policy,
      ) {
        _lowContrast(policy)['leaveAbove'] = 100;
      });
      final Directory scratch = Directory(_scratch().path);
      _expect(
        mutated.existsSync(),
        'the mutated artifact exists while running',
      );
      _expect(scratch.existsSync(), 'the scratch root exists while running');
      _deleteScratch();
      _expect(!scratch.existsSync(), 'the scratch root is deleted: $scratch');
      _expect(!mutated.existsSync(), 'its artifacts are gone: ${mutated.path}');
    });
  });

  _deleteScratch();
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

/// Scratch root for the mutated artifact copies, created on first use under the
/// system temp directory so a run from any working directory leaves nothing in
/// the tree. [main] deletes it before it prints its summary.
Directory? _scratchRoot;

Directory _scratch() => _scratchRoot ??= Directory.systemTemp.createTempSync(
  'adaptive_trigger_test.',
);

/// The per-mutation directory inside the scratch root, recreated per call.
Directory _scratchDir(String name) {
  final Directory target = Directory('${_scratch().path}/$name');
  if (target.existsSync()) {
    target.deleteSync(recursive: true);
  }
  target.createSync(recursive: true);
  return target;
}

/// Deletes the scratch root; the next [_mutatedPolicy] call creates a fresh one.
void _deleteScratch() {
  final Directory? scratch = _scratchRoot;
  _scratchRoot = null;
  if (scratch != null && scratch.existsSync()) {
    scratch.deleteSync(recursive: true);
  }
}

/// Writes a mutated copy of both frozen artifacts so a load sees the change.
File _mutatedPolicy(
  String name,
  void Function(Map<String, Object?> policy) mutate,
) {
  final Directory source = File.fromUri(Platform.script).parent;
  final Directory target = _scratchDir(name);
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
