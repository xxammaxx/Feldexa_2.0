# T264D A/B/C adaptive benchmark

| Item | Value |
| --- | --- |
| Code | `tools/evaluation/adaptive_benchmark.dart` |
| Test | `dart tools/evaluation/adaptive_benchmark_test.dart` (21 checks) |
| Corpora | `corpusAndHoldout.devPages` (6) and `.holdoutPages` (4) of the declared synthetic corpus `field-inventory-synthetic-v1` |
| Consumes (read-only) | `tools/evaluation/adaptive-policy.v1.json` (`frozen-before-run`, `implementation: BLOCKED`), `tools/evaluation/adaptive-provenance.v1.json`, `tools/evaluation/adaptive_trigger.dart`, `tools/evaluation/field_inventory_baseline.dart` (`buildSyntheticCorpus`) |
| Evidence class | `NONE` (host VM only) |

## What it measures

Three schedules over identical inputs:

| Mode | Schedule | Second pass |
| --- | --- | --- |
| A | single pass | never |
| B | full second pass | on every page |
| C | targeted adaptive | only where `decideAdaptiveTrigger` returns `secondPass` |

Every pass is the productive host pipeline over one page:
`RasterAnalysis` -> `GeometryDetector.detect` -> `TypeInference.infer`, scored by
`StructureComparison` against the ground truth the corpus declares at draw time.
The comparison runs on the one-proposal-per-candidate set: the `baselineObserved`
branch of the frozen T264A scorer, one `ObservedField` with
`provenance: 'suggestion'` per `GeometryCandidate`. `FieldInventoryBuilder` is
built as well, but it only feeds the trigger signals (`fieldCandidates`,
`coverage.unlabelledFieldCandidates`); no inventory-derived value enters the
metrics. The corpus, its rasters, and its ground truth come from
`buildSyntheticCorpus()`; the benchmark never draws a corpus of its own. The
frozen `PhotometricQuality` measurement of the photometric original supplies the
low-contrast trigger signal.

Pass 2 analyses a variant of the *same* page. `renderStrategy.allowed` declares
exactly two transforms: a same-DPI contrast stretch and a deskew at a
*caller-supplied* angle. `runtimeSignals.skew.metric` forbids estimating that
angle and this corpus declares none, so only the contrast stretch is exercised;
deskew is reported as not run instead of guessed. A stretch that cannot change a
byte (full 0-255 range, or two equal percentiles) is reported as the identity, so
a mode that "ran a second pass" on such a page is not read as having improved
anything.

A second pass *replaces* the pass-1 result for that page
(`bounds.pageFailureIsolation`: a failed adaptive pass returns the pass-1 result).
Nothing is merged across passes: a cross-pass observation needs the explicit
detector-pass provenance and the declared spatial merge rule that T264P has not
decided yet, so no suggestion set and no evidence row is claimed.

## Metrics

| Metric | Definition |
| --- | --- |
| field precision / recall / F1 | supplementary, exactly the frozen definition of `field_inventory_baseline.dart`: `matched / (matched + extra + unmatched duplicates)`, `matched / expected`, harmonic mean |
| type accuracy | matched pairs whose kind agrees / matched pairs |
| label accuracy | matched pairs whose declared label agrees / matched pairs with a declared label |
| mean matched IoU | mean IoU over the geometry-ok matches, weighted by matches per page |
| missing / extra / duplicate | structure-comparison counts against the declared ground truth |
| review rate | observed proposals that carry at least one comparison defect (extra, geometry mismatch, type mismatch, ambiguous, unlabelled, duplicate) / observed proposals |
| false accepts | auto-confirmed proposals that are extra or type-mismatched. Nothing is auto-confirmed, so the count is 0 by construction; `wouldBeFalseAccepts` reports how many defects would have become false accepts with an auto-confirm step, so the zero is not vacuous |
| latency p50 / p95 | nearest-rank percentiles of the per-page **total analysis** time of the passes: A pays pass 1, B pays both passes on every page, C pays pass 2 only where the trigger admitted it. The variant render (`renderContrastStretch`) and the `PhotometricQuality` measurement happen between the passes and are **not** in the measured time; only B and C consume the variant. The frozen outcome prose says "median latency"; the measured and compared quantity is p50 |
| variant raster hashes | `run.variantRasterHashes`: variant id -> SHA-256 of the **last scored page's** variant raster of that id. It is not a per-page binding; the per-page truth is `pages[].pass2.inputRasterSha256` |
| peak resident set | `VmHWM` of the kernel per-process status counters of the measured `dart` process, plus `dart:io ProcessInfo.maxRss` verbatim |
| passes | analysis passes the mode executed over the scored pages |

## Thresholds

Every acceptance threshold is read from `acceptanceThresholds` in the frozen
policy: the twelve `requiredOutcomes` are parsed as clauses (`>=`, `<=`, `<`, `>`
between a metric of a comparison mode and another metric, a scaled metric, a
metric plus a tolerance, or a plain number), the false-accept sentence is parsed
for its declared limit, and `noGainClaim`, `sameInputs`, and `holdoutTuning` are
read as declared. No number is duplicated in the code. A declared outcome whose
wording this module cannot parse throws instead of being skipped, and the run
refuses `sameInputs: false` or `holdoutTuning: true`.

## Corpus partition and holdout discipline

`partitionCorpus` splits the drawn corpus by the frozen `corpusAndHoldout` block.
A page the policy declares but the corpus does not draw throws. A drawn page the
block does not declare is reported as unscored and never enters the gate
arithmetic. `--score holdout` requires `--holdout-ledger`; the ledger records the
single scoring of a policy SHA-256 and a repeated scoring exits `4` before any
page is analysed, which makes the frozen "scored once" rule checkable instead of
a promise.

## Commands

```bash
dart tools/evaluation/adaptive_benchmark_test.dart
dart run tools/evaluation/adaptive_benchmark.dart --output dev.json --score dev
dart run tools/evaluation/adaptive_benchmark.dart --output holdout.json \
  --score holdout --holdout-ledger holdout-ledger.json
```

Exit codes: `0` run written and every declared outcome PASS, `1` I/O or internal
failure, `2` usage error, `3` run written but at least one declared outcome FAIL,
`4` holdout refused because this policy already had its single holdout scoring.

## What it does not do

- No OCR engine, no adapter, no raster port, no camera, no Android, emulator, or
  device run: no `SIMULATED`, `EMULATOR`, or `DEVICE` evidence and no SC claim.
  SC-001/SC-003 stay with T142, SC-004 with T136/T141.
- No real form and no real-corpus qualification: the corpus is synthetic and
  rights-free.
- No production wiring, no suggestion set, no cross-pass merge, no schema or
  provenance change, no auto-confirmation, no second pipeline, no cloud or ML
  training.
- No threshold tuning: the policy is consumed read-only and the values are never
  restated in code. The holdout pages are scored once.
- No UI and no editor evidence.
