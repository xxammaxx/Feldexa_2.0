# 2026-11-24 NONE — T264D: A/B/C adaptive benchmark on the declared synthetic corpus

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `PARTIAL` |
| Task / issue | `T264` / `#264` |
| Date / timezone | `2026-11-24 15:40 Europe/Berlin` |
| Revision | base commit `2a0c4c5dfbaa931eb988ad1eb3b54f92c013872e`, branch `t264d`; tree `dirty` while the checks ran, holding exactly these files with these SHA-256 values, and the same bytes are committed at the HEAD of this correction: `tools/evaluation/adaptive_benchmark.dart` SHA-256 `566644d7a172089f9278c40929a73b08328b7abe199537ef052978563d0f3b73`; `tools/evaluation/adaptive_benchmark_test.dart` SHA-256 `c01bc9ea25bc64ce2b282f7e77983ae1b81571f7cf8bec7489ea49b3d4e4de4c`; `tools/evaluation/field_inventory_baseline.dart` SHA-256 `3154e8e73fe3710a28ea7d24b93e25b6fd39e8955e8171b0273a3e69c6cb8d0e` (additive read-only corpus seam, byte-neutral: see check 7); `tools/evaluation/adaptive-benchmark.md` SHA-256 `6d0f50d04729ecbe62bb3c939247f28044e3d1be73835c4f37f0a8c08f41ad90`; `specs/001-scanned-form-workflow/reports/README.md` SHA-256 `2c67a0a08ae452b4099ac7183994903f88683304722089767475bdd9e2f0dbfa`; `specs/001-scanned-form-workflow/reports/artifacts/2026-11-24-t264d-abc-benchmark/dev.json` SHA-256 `c14ff67ce23622266cbc07f7ac313432a7506b0f0d89ef13ed027b344fc99407`; `specs/001-scanned-form-workflow/reports/artifacts/2026-11-24-t264d-abc-benchmark/holdout.json` SHA-256 `ce9e8d357bc5a9b8431b64f169d717b5c84427d0dbde993b4207418175d2dc47`; `specs/001-scanned-form-workflow/reports/artifacts/2026-11-24-t264d-abc-benchmark/holdout-ledger.json` SHA-256 `bdcc3f7690445a4ae066df8fd9fa18a7467bd08c9f926003fb339cf4b87f6a83`; candidate commit SHA and this report's hash are recorded in the external attestation |
| External attestation | Coordinator-held worker_done transport attestation for the T264D dispatch; it records the candidate commit, tree, and this report's byte size and SHA-256 after the report commit |
| Build identity | No application build artifact. Host Dart CLI `dart run tools/evaluation/adaptive_benchmark.dart`; no APK, Gradle, Android, release, or Web build |
| Toolchain | Flutter `3.47.7` stable (framework `abaf9c5237`), Dart `3.13.5`, Python `3.14.8`; Linux `7.2.7-1-cachyos` x86_64 host VM with KVM; no emulator, device, browser, OCR engine, PDF engine, Android SDK, or Gradle invoked |
| Input | synthetic corpus `field-inventory-synthetic-v1`, 12 pages drawn at 200 DPI by `tools/evaluation/field_inventory_baseline.dart` with ground truth declared at draw time; `fixtureSha256` `0100e19f2967ba4437ff6649974f766987a1bf3eb22bf033b99f766ddd18d16c`, `corpusSha256` `c595b7ea7321d081926c277449419921f8b3622fabbd0cc08ee5e40077461f60`, `groundTruthSha256` `7cfedb615aef3a0326ae2401ca5c5be3e5a3bc650be96f4818c5abcd2dd0cbfe` (identical to the frozen T264A golden); frozen policy `tools/evaluation/adaptive-policy.v1.json` SHA-256 `eb940399ce1533aaa0a6dba4bba814b311a5041b06daeddc0f9866cacc40e073` and `tools/evaluation/adaptive-provenance.v1.json` SHA-256 `50af51a9eab0def559b1100b2d9b1b290062cc414008d3f13596f174d8146c72`, both unmodified; no real or personal document |

## 1. Scope

This report covers the T264D slice of issue #264: the A/B/C benchmark of three
analysis schedules over identical inputs, the measured metrics, and one
PASS/FAIL verdict per frozen acceptance outcome.

- **A single pass**: pass 1 only.
- **B full second pass**: pass 2 on every page.
- **C targeted adaptive**: pass 2 only on the pages for which the frozen
  `decideAdaptiveTrigger` returns `secondPass`.

Every pass is the productive host pipeline on one 200 DPI page:
`RasterAnalysis` -> `GeometryDetector.detect` -> `TypeInference.infer` ->
`FieldInventoryBuilder` -> `StructureComparison` against the ground truth
declared at draw time. The frozen `PhotometricQuality` measurement of the
photometric original supplies the trigger signals.

**Why the result is `PARTIAL`.** The host-layer deliverable is complete: the
benchmark runs, the thresholds are read from the frozen policy, and the holdout
was scored once. The measured outcome is nevertheless not an upgrade claim.
`corpusAndHoldout.holdoutPages` scores **12/12 declared outcomes PASS** but
`acceptanceThresholds.noGainClaim` is in force — no mode C result is *strictly*
better than mode A, so the conservative baseline stays. The development set
scores 11/12 and reproduces the single outcome that the frozen low-contrast
metric cannot satisfy (§5.3). Android `EMULATOR` production-path evidence,
real-corpus qualification, and any SC-001/SC-003/SC-004 claim remain `NOT_RUN`.

## 2. Revision and build

Base commit `2a0c4c5dfbaa931eb988ad1eb3b54f92c013872e` (origin/main after the
T264C integration). T264D adds exactly three files and one report row:

| File | Role |
| --- | --- |
| `tools/evaluation/adaptive_benchmark.dart` | the A/B/C benchmark and its CLI |
| `tools/evaluation/adaptive_benchmark_test.dart` | 19-check host harness, RED at base before the implementation existed |
| `tools/evaluation/field_inventory_baseline.dart` | additive read-only corpus seam (`buildSyntheticCorpus`, `syntheticCorpusIdentity`, `hostMemoryMeasurement`); `_fixtureIdentity` now delegates to `syntheticCorpusIdentity` instead of duplicating the derivation |
| `tools/evaluation/adaptive-benchmark.md` | method and artefact documentation |
| `specs/001-scanned-form-workflow/reports/README.md` | one index row for this report |

No production, contract, schema, provenance, or policy byte changed.
`tools/evaluation/adaptive-policy.v1.json` and
`tools/evaluation/adaptive-provenance.v1.json` are byte-identical to base and
their SHA-256 values are pinned in the test. `geometry_detector.dart`,
`type_inference.dart`, the editor and the UI are untouched.

## 3. Environment

```text
NONE (host checks only): Linux 7.2.7-1-cachyos x86_64 host VM; Flutter 3.47.7
stable; Dart 3.13.5 JIT; Python 3.14.8. Synthetic 200 DPI grayscale corpus with
ground truth declared at draw time. No emulator, device, browser, OCR engine,
PDF engine, Android SDK, or Gradle build. Timings are host JIT diagnostics of one
run, not a performance claim.
```

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `dart format --output=none --set-exit-if-changed tools/evaluation/adaptive_benchmark.dart tools/evaluation/adaptive_benchmark_test.dart tools/evaluation/field_inventory_baseline.dart` (`repository root`) | `0` | console only (not retained) | `PASS` |
| 2 | `dart analyze tools/evaluation/adaptive_benchmark.dart tools/evaluation/adaptive_benchmark_test.dart tools/evaluation/field_inventory_baseline.dart` (`repository root`) | `0` | console only (not retained) | `PASS` |
| 3 | `dart tools/evaluation/adaptive_benchmark_test.dart` (`repository root`) | `0` | console only (not retained) | `PASS` |
| 4 | `dart run tools/evaluation/adaptive_benchmark.dart --output dev.json --score dev` (`repository root`) | `3` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-24-t264d-abc-benchmark/dev.json` | `PARTIAL` |
| 5 | `dart run tools/evaluation/adaptive_benchmark.dart --output holdout.json --score holdout --holdout-ledger holdout-ledger.json` (`repository root`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-24-t264d-abc-benchmark/holdout.json` | `PASS` |
| 6 | the same holdout command repeated after check 5 (`repository root`) | `4` | console only (not retained) | `PARTIAL` |
| 7 | `dart run tools/evaluation/field_inventory_baseline.dart --output run.json --snapshot snapshot.json` at base `2a0c4c5` and at this HEAD (`repository root`) | `0` | console only (not retained) | `PASS` |
| 8 | `python3 -m unittest tools/evaluation/test_field_inventory_baseline.py` (`repository root`, Dart on `PATH`) | `1` | console only (not retained) | `FAIL` |
| 9 | `dart tools/evaluation/adaptive_trigger_test.dart` (`repository root`) | `0` | console only (not retained) | `PASS` |
| 10 | `bash tools/gate.sh --offline --allow-absent --allow-unavailable` (`repository root`) | `1` | console only (not retained) | `PARTIAL` |
| 11 | `dart tools/evaluation/validate_report.dart specs/001-scanned-form-workflow/reports/2026-11-24-t264d-abc-benchmark.md` (`repository root`) | `0` | console only (not retained) | `PASS` |
| 12 | `git diff --check` (`repository root`) | `0` | console only (not retained) | `PASS` |
| 13 | Android `EMULATOR` production-path A/B/C journey (`not applicable`) | `-` | none | `UNAVAILABLE` |
| 14 | rights-cleared real-form corpus (`not applicable`) | `-` | none | `ABSENT` |

Key result lines. Check 1 `Formatted 3 files (0 changed)`; check 2
`No issues found!`; check 3 `19 checks, 0 failure(s)`; check 4
`benchmark written: scoreSet=dev pages=6 passes(A/B/C)=6/12/12 outcomes=11/12
PASS noGain=true`; check 5 `benchmark written: scoreSet=holdout pages=4
passes(A/B/C)=4/8/7 outcomes=12/12 PASS noGain=true`; check 6
`error: corpusAndHoldout.rule: the holdout was already scored for policy
eb940399…` and no run file was written; check 7 both runs printed
`baseline written: pages=12 verdicts={pass: 6, fail: 6}` and produced the
byte-identical snapshot `8095dcf3a01bfe4bf753f4a41319ed8e25a4d2060a646d387696765c12e19975`;
check 9 `26 checks, 0 failure(s)`; check 10 `Checks passed: 13; failed: 1;
unavailable: 1; absent planned layers: 1`.

Check 6 is the holdout-once enforcement, not a second scoring: the ledger entry
from check 5 makes the tool exit `4` before any page is analysed, so the frozen
`corpusAndHoldout.rule` is machine-checked instead of promised. Its outcome is
recorded as `PARTIAL` only because the fixed vocabulary requires exit `0` for
`PASS`; the refusal is the intended behaviour and it wrote no run file.

Check 8 is a **pre-existing** failure of the T264A golden gate, reproduced
identically at base with the T264D seam stashed: 2 of 12 assertions
(`test_run_matches_the_committed_golden_snapshot`,
`test_golden_binds_fixture_corpus_and_ground_truth_identity`) fail because the
committed golden `508ed9be…` predates the `type_inference.dart` label-association
change of T263 (`b3ac1f1`, `3102557`), which touched
`typeObservations.labelText`/`addedCues` in the frozen projection. The corpus and
ground-truth identity hashes did **not** drift. Regenerating the golden is not
T264D scope, so the failure is reproduced and reported, not repaired.

Check 10 reproduces the documented pre-existing format `FAIL` (three unformatted
`tools/corpus/*.dart` files from the T263 merge, issue #302) and adds no new
gate failure: the T264D files are format- and analysis-clean, and every other
check passes. Chrome is `UNAVAILABLE` and the browser integration driver is
`ABSENT` on this host; `EMULATOR`/`DEVICE` layers are never run by this gate.

## 5. Results

Both scored sets use the same declarations: `devPages` (6 pages, 27 declared
fields) for development and `holdoutPages` (4 pages, 6 declared fields) scored
once. Two drawn pages — `numeric-variants` and `multiline-area` — are **not**
declared in `corpusAndHoldout`: they are not scored, they never enter the gate
arithmetic, and no result is claimed for them. Their absence is explicit in every
artifact (`undeclaredReason`) and in the CLI output (`UNSCORED …`).

Pass-2 variant: only `renderStrategy.allowed[contrastStretch]` is exercised
(same raster grid, measured 5th/95th percentiles to 0/255). `deskew` cannot be
exercised: `runtimeSignals.skew.metric` is caller-supplied and must never be
estimated, and this corpus declares no angle. A stretch that cannot change a byte
is reported as the identity instead of as a gain.

### 5.1 Metrics per mode

Holdout (4 pages, 6 declared fields) — the single scored holdout run:

| Metric | A single pass | B full second pass | C targeted adaptive |
| --- | ---: | ---: | ---: |
| passes | 4 | 8 | **7** |
| expected / matched / observed | 6 / 2 / 5 | 6 / 0 / 3 | 6 / 2 / 5 |
| missing / extra / duplicate | 4 / 3 / 0 | 6 / 3 / 0 | 4 / 3 / 0 |
| field precision | 0.400 | 0.000 | 0.400 |
| field recall | 0.333 | 0.000 | 0.333 |
| field F1 (supplementary) | 0.364 | 0.000 | 0.364 |
| type accuracy | 1.000 | 0.000 | 1.000 |
| label accuracy | 0.250 | 0.000 | 0.250 |
| mean matched IoU | 0.954 | 0.000 | 0.954 |
| review rate | 0.600 | 1.000 | 0.600 |
| false accepts | 0 | 0 | 0 |
| latency p50 / p95 (ms) | 258 / 342 | 479 / 638 | 479 / 638 |
| peak variant pixels | 0 | 3868706 | 3868706 |

Dev (6 pages, 27 declared fields) — development diagnostics, not the gate:

| Metric | A single pass | B full second pass | C targeted adaptive |
| --- | ---: | ---: | ---: |
| passes | 6 | 12 | 12 |
| expected / matched / observed | 27 / 26 / 35 | 27 / 26 / 35 | 27 / 26 / 35 |
| missing / extra / duplicate | 1 / 4 / 6 | 1 / 4 / 6 | 1 / 4 / 6 |
| field precision / recall / F1 | 0.743 / 0.963 / 0.839 | 0.743 / 0.963 / 0.839 | 0.743 / 0.963 / 0.839 |
| type accuracy | 0.808 | 0.808 | 0.808 |
| label accuracy | 1.000 | 1.000 | 1.000 |
| mean matched IoU | 0.964 | 0.964 | 0.964 |
| review rate | 0.429 | 0.429 | 0.429 |
| false accepts | 0 | 0 | 0 |
| latency p50 / p95 (ms) | 242 / 369 | 481 / 670 | 481 / 670 |
| peak variant pixels | 0 | 3868706 | 3868706 |

`false accepts` is 0 in every mode because nothing is auto-confirmed: the
benchmark proposes a comparison result and stops. The counter is derived from the
measured auto-confirm count instead of being hardcoded, and
`wouldBeFalseAccepts` (9 on dev, 3 on holdout) reports how many extra or
type-mismatched proposals would have become false accepts with an auto-confirm
step, so the zero is not vacuous.

Peak resident set, measured once per run from the kernel counters:
`VmHWM` `355500` KiB (`364032000` bytes) on the dev run and `339572` KiB
(`347721728` bytes) on the holdout run; `dart:io ProcessInfo.maxRss` reports
`364032000` / `347721728` bytes verbatim on this host. Largest variant raster:
`3868706` px (A4 portrait at 200 DPI), below the frozen `8000000` ceiling.

### 5.2 PASS/FAIL per declared outcome

`holdoutPages` (the gate; scored once) — 12/12 `PASS`:

| # | Declared outcome (frozen text) | Holdout measured | Verdict |
| ---: | --- | --- | --- |
| 1 | field recall(C) >= field recall(A) | 0.333 >= 0.333 | `PASS` |
| 2 | field precision(C) >= field precision(A) | 0.400 >= 0.400 | `PASS` |
| 3 | type accuracy(C) >= type accuracy(A) | 1.000 >= 1.000 | `PASS` |
| 4 | mean matched IoU(C) >= mean matched IoU(A) | 0.9544 >= 0.9544 | `PASS` |
| 5 | missing fields(C) <= missing fields(A) | 4 <= 4 | `PASS` |
| 6 | extra fields(C) <= extra fields(A) | 3 <= 3 | `PASS` |
| 7 | review rate(C) <= review rate(A) + 0.05 | 0.600 <= 0.650 | `PASS` |
| 8 | passes(C) < passes(B) | 7 < 8 | `PASS` |
| 9 | median latency(C) <= 2.0 * median latency(A) | 479 <= 516 | `PASS` |
| 10 | median latency(C) <= median latency(B) | 479 <= 479 | `PASS` |
| 11 | peak variant pixels <= 8000000 | 3868706 <= 8000000 | `PASS` |
| 12 | false accepts … must be 0 | 0 / 0 / 0 | `PASS` |

`devPages` (development set) — 11/12 `PASS`, one `FAIL`:

| # | Declared outcome | Dev measured | Verdict |
| ---: | --- | --- | --- |
| 8 | passes(C) < passes(B) | 12 < 12 | `FAIL` |

All other dev outcomes pass with identical A/B/C values.

**`noGainClaim` applies on both sets.** The frozen text is reported verbatim in
both artifacts (`noGain: {applies: true, claim: …}`):
"If no mode C outcome is strictly better than mode A, the conservative baseline
stays and the report must say so. No existing SC gate is lowered by this policy."
No mode C metric is strictly better than mode A on either set, so the
conservative single-pass baseline stays.

### 5.3 Why C gains nothing: two measured properties of the frozen policy

The benchmark reports, it does not tune. Two measured properties of the frozen
artefacts explain the result; both are findings for T264C/T264A, not T264D
defects, and neither threshold was changed.

1. **`runtimeSignals.lowContrast` is degenerate on sparse-ink pages.** The metric
   is `p95Luminance - p05Luminance` over the full luminance histogram. On a form
   whose ink covers less than 5 % of the page, the 5th percentile is paper white,
   so `p05 = p95 = 255` and the measured spread is `0`, far below `enterBelow`
   `96`. Measured spread on all 6 dev pages and on 3 of 4 holdout pages: `0`
   (dev inkDensity `0.000179`-`0.005933`). The trigger therefore fires on every dev
   page and on 3 of 4 holdout pages, which is why C executes 12 of 12 possible
   passes on dev and 7 of 8 on holdout.
2. **The percentile-driven contrast stretch cannot recover the low-contrast
   page.** The `low-contrast` holdout page declares faint ink at luminance `170`
   on `255` paper; its measured percentiles are again `255`/`255`, so the variant
   is the identity and pass 2 sees exactly the pass-1 bytes. The page keeps
   `0` of `3` declared fields (`inkDensity` `0.0`, all ink above the fixed `128`
   ink threshold) in **all three modes**.

Conversely, on the one holdout page where the stretch is real (`shadow`,
`p05 = 154`, spread `101`, no trigger), the stretch is **harmful**: mode B
destroys the page's two matched fields (matched `2` -> `0`, mean IoU `0.954` ->
`0`), while mode C keeps the pass-1 result because no frozen trigger fired. C
being better than B here is the only measured benefit of the targeted schedule,
and it is a benefit over B, not over A.

### 5.4 Latency and measurement noise

`median latency(C) <= 2.0 * median latency(A)` passes on the holdout at
`479 <= 516` and failed on one earlier dev iteration at `483 > 482`. C pays a
second pass on 3 of 4 holdout pages and on all 6 dev pages, so C's latency is
close to B's and close to the doubling bound of A. These two outcomes are the
noise-sensitive ones: they are single-run host JIT measurements of one process,
not a performance claim, and no warm-up or repetition is claimed. A later
repetition would need its own report.

## 6. Performance

No performance claim. SC-004 remains owned by T136 and T141 on a named Android
device.

Host diagnostics of the two scored runs, host JIT, one run each, no warm-up:

| Diagnostic | Dev run | Holdout run |
| --- | ---: | ---: |
| Pages / passes (A/B/C) | 6 / 6/12/12 | 4 / 4/8/7 |
| Latency p50 (ms) | 242 / 481 / 481 | 258 / 479 / 479 |
| Latency p95 (ms) | 369 / 670 / 670 | 342 / 638 / 638 |
| Kernel peak resident set (`VmHWM`) | `355500` KiB | `339572` KiB |
| `dart:io ProcessInfo.maxRss` (bytes, verbatim) | `364032000` | `347721728` |
| Largest variant raster (px) | `3868706` | `3868706` |
| Frozen variant ceiling (px) | `8000000` | `8000000` |

The corpus is synthetic and the run happens after JIT warm-up of the harness
itself, so these values are diagnostics of this host run only — they are not a
budget, not a bound, and not comparable to any device measurement. `VmHWM` is the
peak resident set of the whole `dart` process including the JIT and the page
rasters, not a product memory figure.

## 7. Limitations

- **No mode C gain.** No C metric is strictly better than A on either set, so
  `noGainClaim` applies and the conservative single-pass baseline stays. The
  adaptive second pass is measured but not justified by this corpus.
- **Dev set has one failing outcome.** `passes(C) < passes(B)` fails on dev
  (12 vs 12) because the frozen low-contrast trigger fires on every dev page
  (§5.3). The holdout passes it only because one page (`shadow`) does not fire.
- **`deskew` is not exercised.** `renderStrategy.allowed` permits it only at a
  caller-supplied angle, the policy forbids estimating that angle, and the corpus
  declares none. Skew behaviour is therefore `NOT_RUN`, not "passing".
- **One OCR-free corpus.** Labels are the declared SIMULATED observations of the
  synthetic corpus; no OCR engine ran, so OCR variance, engine-specific errors,
  and German glyph handling are outside this report (T263 owns them).
- **Single-run latencies.** p50/p95 come from one run per set with no warm-up and
  no repetition; the two latency outcomes are the noise-sensitive ones.
- **Structure comparison is evaluation-only.** It feeds the report and is
  reported as a non-decisive signal; it never triggers a pass
  (`runtimeSignals.structureMismatch.runtimeTrigger: false`).
- **No cross-pass merge.** Pass 2 replaces the pass-1 result per
  `bounds.pageFailureIsolation`; a merged suggestion set needs the explicit
  detector-pass provenance and the declared spatial merge rule that T264P has not
  decided (frozen prerequisite `P2`, `state: UNDECIDED`). No evidence row, no
  correlation group, and no independence is claimed.
- **Undeclared pages are never scored.** `numeric-variants` and `multiline-area`
  are drawn but not declared in `corpusAndHoldout`; they are excluded from the
  gate arithmetic and no result is claimed for them.
- **Pre-existing golden drift** (§4, check 8) means the T264A byte-equality gate
  currently fails at base for reasons outside T264D; the metrics here measure the
  current pipeline, not the frozen golden projection.
- **The additive corpus seam changes the recorded bytes of a T264A artifact.**
  `tools/evaluation/field_inventory_baseline.dart` gains `buildSyntheticCorpus`,
  `syntheticCorpusIdentity`, and `hostMemoryMeasurement` and delegates its own
  identity derivation to them, so the T264A report's artifact row for that file
  no longer matches the current bytes. It is byte-*neutral* (check 7), but the
  T264A report already failed the same current-bytes check at base for
  `tools/evaluation/adaptive-policy.v1.md` (`6098` bytes now, `4639` recorded).
  Re-cutting another task's report is out of T264D scope.
- No Android, emulator, device, UI, editor, persistence, export, or accessibility
  evidence; no SC-001/SC-003 (T142) or SC-004 (T136/T141) claim.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Benchmark | `tools/evaluation/adaptive_benchmark.dart` | 71128 | `566644d7a172089f9278c40929a73b08328b7abe199537ef052978563d0f3b73` |
| Benchmark test | `tools/evaluation/adaptive_benchmark_test.dart` | 25963 | `c01bc9ea25bc64ce2b282f7e77983ae1b81571f7cf8bec7489ea49b3d4e4de4c` |
| Corpus seam host | `tools/evaluation/field_inventory_baseline.dart` | 72956 | `3154e8e73fe3710a28ea7d24b93e25b6fd39e8955e8171b0273a3e69c6cb8d0e` |
| Method notes | `tools/evaluation/adaptive-benchmark.md` | 6140 | `6d0f50d04729ecbe62bb3c939247f28044e3d1be73835c4f37f0a8c08f41ad90` |
| Frozen adaptive policy | `tools/evaluation/adaptive-policy.v1.json` | 7414 | `eb940399ce1533aaa0a6dba4bba814b311a5041b06daeddc0f9866cacc40e073` |
| Frozen provenance | `tools/evaluation/adaptive-provenance.v1.json` | 27851 | `50af51a9eab0def559b1100b2d9b1b290062cc414008d3f13596f174d8146c72` |
| Trigger decision | `tools/evaluation/adaptive_trigger.dart` | 36588 | `b9947766fbd8f22a8b334a9f231cb76c42162b278e150fdc234cb7e6f04bea7e` |
| T264A golden | `tools/evaluation/goldens/field-inventory-baseline.v1.json` | 167045 | `508ed9beed5a3844aa3ce101d378f7243b47e259cbcda72a412bbe6067f205e6` |
| Dev run artifact | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-24-t264d-abc-benchmark/dev.json` | 39029 | `c14ff67ce23622266cbc07f7ac313432a7506b0f0d89ef13ed027b344fc99407` |
| Holdout run artifact | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-24-t264d-abc-benchmark/holdout.json` | 27596 | `ce9e8d357bc5a9b8431b64f169d717b5c84427d0dbde993b4207418175d2dc47` |
| Holdout ledger | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-24-t264d-abc-benchmark/holdout-ledger.json` | 553 | `bdcc3f7690445a4ae066df8fd9fa18a7467bd08c9f926003fb339cf4b87f6a83` |

## 9. Reproducibility

1. Start from base commit `2a0c4c5dfbaa931eb988ad1eb3b54f92c013872e`; the T264D
   files above are its children.
2. Run `flutter pub get --offline` at the repository root for workspace
   resolution; `pubspec.lock` stays unchanged.
3. Put the Dart SDK on `PATH` (or use an explicit path).
4. `dart tools/evaluation/adaptive_benchmark_test.dart` → `19 checks, 0
   failure(s)`, exit `0`.
5. `dart run tools/evaluation/adaptive_benchmark.dart --output dev.json --score
   dev` → exit `3` with `outcomes=11/12 PASS noGain=true` and the single `FAIL`
   on `passes(C) < passes(B)`; latencies differ per run.
6. `dart run tools/evaluation/adaptive_benchmark.dart --output holdout.json
   --score holdout --holdout-ledger holdout-ledger.json` → exit `0` with
   `outcomes=12/12 PASS noGain=true`.
7. Repeat step 6 → exit `4`, no run written, no page analysed. Deleting the
   ledger entry is a holdout-tuning act and needs a new policy version.
8. Compare the artifact `inputs.corpus.fixtureSha256` / `corpusSha256` /
   `groundTruthSha256` with §Input; they depend only on the corpus definition and
   are identical on any host. Artifact bytes differ per run only in
   `generatedAtUtc`, latencies, and the measured memory values.
9. `bash tools/gate.sh --offline --allow-absent --allow-unavailable` reproduces
   the pre-existing `tools/corpus/*.dart` format `FAIL` (issue #302) plus 13
   passing checks; the T264D files introduce no new failure.

## 10. External attestation

The candidate commit, tree, this report's bytes and SHA-256, and the transport
hashes are recorded outside the candidate commit in the coordinator-held
attestation for this dispatch. No bundle is produced by this task. This report
deliberately contains neither its own hash nor the candidate commit SHA.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
