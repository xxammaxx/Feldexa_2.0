# Adaptive second-pass trigger decision (T264C, first slice)

| Field | Value |
| --- | --- |
| Code | `tools/evaluation/adaptive_trigger.dart` |
| Test | `dart tools/evaluation/adaptive_trigger_test.dart` (21 checks) |
| Consumes | `tools/evaluation/adaptive-policy.v1.json` (`frozen-before-run`, `implementation: BLOCKED`) and `tools/evaluation/adaptive-provenance.v1.json` (`decisionRule`) |
| Task / issue | T264C / [#264](https://github.com/xxammaxx/Feldexa_2.0/issues/264) |
| Evidence class | `NONE` (host logic and host tests only) |

## 1. What this slice decides

`decideAdaptiveTrigger({policy, request})` answers one question per page: is a
second analysis pass permitted? The answer is a record, not a boolean:
`Verdict` (`noSecondPass` / `secondPass` / `rejected`), one reason line per
considered signal with the dotted policy path and the frozen value it was
compared to, the fired `TriggerHit`s, the latched trigger set, the pass/time/
memory bounds, the evidence bookkeeping, and the pass-1 fallback rule.

`resolveSecondPassOutcome({pass1, pass2, pass2Failed})` applies that fallback: a
failed or absent second pass returns the pass-1 result unchanged.

## 2. Triggers and thresholds — owned by the policy file

No number is written twice. The values are parsed from `adaptive-policy.v1.json`:

| Trigger | Frozen value | Path |
| --- | --- | --- |
| `lowContrast` | enter `contrastSpread < 96`, leave above `112`, `16` points | `runtimeSignals.lowContrast` |
| `skew` | enter `> 0.5°`, leave below `0.25°` (caller-supplied; never estimated) | `runtimeSignals.skew` |
| `ocrFailure` | port threw or zero usable label lines | `runtimeSignals.ocrFailure` |
| `missingLabel` | unlabelled fraction `>= 0.5`, at least `3` candidates | `runtimeSignals.missingLabel` |
| `conflict` | `>= 1` conflict-graph pair at `IoU >= 0.5` | `runtimeSignals.conflict` |

Hysteresis is stateful: `TriggerRequest.latched` carries the previous decision's
`AdaptiveDecision.latched` forward, so a trigger inside the band neither enters
nor drops out. An unlatched trigger enters only through the stricter enter
value, a latched one releases only beyond the leave value.

Signals without a frozen rule are reported, never guessed: structure comparison
is `runtimeTrigger: false` (evaluation-only), and detector instability has no
frozen threshold at all. Both appear in `ignoredSignals`.

## 3. Bounds, returned not commented

`bounds` are attached to every decision: `maxPassesPerPage: 2` (a page at the
limit gets `noSecondPass` with reason `passBudgetExhausted`), `4000 ms` per page,
`8000000` variant pixels, one concurrent pass, one variant raster in memory, and
`bounds.pageFailureIsolation` as `secondPassFailureRule`.

## 4. Refused instead of guessed

`Verdict.rejected` with a code, never a silent yes:

* `policyImplementationBlocked` — a `production`-mode decision while the frozen
  policy keeps `implementation: BLOCKED`.
* `holdoutAlreadyScored` — a repeated scoring of a `holdoutPages` page.
* `correlationLimited` — offered evidence covers fewer than
  `decisionRule.minIndependentGroups` (2) correlation groups. A repeated group
  keeps one observation, a `PENDING_RUN` variant hash produces no evidence row,
  and the observation count is never the evidence count.

## 5. What this slice does not do

No UI, no pipeline wiring, no raster or OCR work, no variant rendering, no
measurement, no A/B/C benchmark. It writes no evidence row and claims no
`SIMULATED`/`EMULATOR`/`DEVICE` class. Nothing here changes
`adaptive-policy.v1.json` or `adaptive-provenance.v1.json`; both stay byte
identical and a policy edit fails the pinned test. SC-001/SC-003/SC-004 remain
owned by T142/T136/T141, and the adaptive second pass stays `BLOCKED` until the
`SuggestionSchema` provenance decision (T264P) is settled.
