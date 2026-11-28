# 2026-11-28 NONE — T086B-R Rest: isolate-observable Cancellation + Golden-Consumption

| Field | Value |
| --- | --- |
| Evidence class | `NONE` (host-VM and host-process checks only; no Android runtime) |
| Result | `PASS` for the two delivered host checks (T086B-R point 5, golden consumption); point 9 stays `NOT_RUN` (device/emulator lane, §7) |
| Tasks / issues | T086B-R `#270` — remainder point 5 plus the T264A golden-consumption proof |
| Date / timezone | `2026-11-28 Europe/Berlin` |
| Revision | base `56c76c1cffe1c94afd641edeb5426715b6cb7a69` (`origin/main` at start, fetched); candidate HEAD `11856c71530da3a2986525de0fc2351ce331deac` (2 commits); **final candidate HEAD after the review-correction commit `09eac0c`**: the correction changes the VM cancellation observer (product code) plus tests, report and README — the final statistics are 46/46 focused and 227/227 application |
| Worktree | `run-tscn02hu/worktrees/t086br-cancel-golden`, branch `xxammaxx/t086br-cancel-golden` |
| Product-code changes | 4 recognition files, 2 test files, 1 new host checker and 1 new host test; no port, no schema, no envelope field, no detector, no typing change |
| Golden / threshold changes | **none**. `tools/evaluation/goldens/field-inventory-baseline.v1.json` is unchanged and consumed read-only (`508ed9beed5a3844aa3ce101d378f7243b47e259cbcda72a412bbe6067f205e6`) |
| External attestation | none; this report claims no independent review and no merge |
| Build identity | no build artifact; host checks only (`flutter test`, `dart run`, `python3 -m unittest`) |
| Toolchain | Flutter 3.47.7 stable, Dart 3.13.5 (stable), Linux x86_64 |
| Input | synthetic corpus `field-inventory-synthetic-v1` (12 pages, 50 candidates), committed golden SHA-256 `508ed9be…f205e6` |

## 1. Scope

This report closes the remainder the brief
`run-tscn02hu/reports/release/TASK-BRIEF-t086br-cancellation-golden.md` assigns:
the T086B-R merge (`#296`) and its review follow-ups (`#297`) left two gaps, and
this slice delivers exactly those two:

1. **T086B-R point 5 — isolate-observable cancellation.** The off-isolate stage
   runner could only be bounded by its per-page deadline; a caller-side
   cancellation could not reach the worker. The runner now accepts one
   cancellation observation, kills and joins the worker immediately when it
   completes, and returns the existing content-free cancelled-page outcome
   (REC-004). `AnalyzeDocument` observes the same signal across the page loop,
   so a cancelled page is not held until the deadline.
2. **Golden consumption.** `field-inventory-baseline.v1.json` was produced but
   no artifact consumed it and proved that the productive recognition path still
   reproduces its frozen projection. A new host checker reads the committed
   bytes, binds their SHA-256, runs the productive bytes-level stage over the
   declared synthetic corpus, and requires byte equality of the projected
   per-page/per-field data.

Point 9 of T086B-R — an Android run of the off-isolate stage with SC-004
p50/p95/memory — is explicitly **not** part of this slice and stays `NOT_RUN`
(§7). The brief forbids an emulator run for this task.

## 2. Revision and build

- Base: `56c76c1cffe1c94afd641edeb5426715b6cb7a69` (current `origin/main`,
  fetched before the worktree was created).
- Worktree: `git worktree add -b xxammaxx/t086br-cancel-golden
  run-tscn02hu/worktrees/t086br-cancel-golden 56c76c1`.
- Candidate commits (no push, no merge):
  - `7e43b821f1d5e2abcc9f5c5a6aed59a8ccb698bd` — point 5: cancellation
    observation in the VM runner, the inline runner, the stage outcome and
    `AnalyzeDocument`, plus the RED-first tests.
  - `11856c71530da3a2986525de0fc2351ce331deac` — golden consumption: the
    checker, its host test, this report and the README index row.
  - Correction after the two independent reviews: the VM cancellation observer
    is now bound **before** `Isolate.spawn` (a signal that fails during the
    spawn await is observed, not surfaced as a zone error, and the spawn catch
    reports `cancelled()` when the signal won), plus a failing-signal test and
    two inline-runner cancellation tests (an already-failed signal and a signal
    completing during the synchronous work). Focused runner + document suites:
    46/46.
- Build command: `flutter pub get` in the worktree (host, cached). No APK/AAB,
  no code generation, no golden and no threshold touched.

## 3. Environment

```text
NONE (host-only):
Linux x86_64, CachyOS kernel 7.2.7, Dart SDK 3.13.5, Flutter 3.47.7 stable;
no Android emulator, device, OCR engine, or browser lane involved;
test root = packages/feldexa_application/test and
packages/feldexa_recognition/test (host VM);
golden checker = dart run tools/evaluation/golden_consumption_check.dart
```

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `dart format --output=none --set-exit-if-changed .` (repo root) | `0` | console: `Formatted 392 files (0 changed)` | `PASS` |
| 2 | `flutter analyze --no-pub` (repo root) | `0` | console: `No issues found! (ran in 129.8s)` | `PASS` |
| 3 | `flutter test packages/feldexa_application/test/raster_page_stage_runner_test.dart packages/feldexa_application/test/analyze_document_test.dart` | `0` | console: `+46: All tests passed!` (final, after the correction; the pre-correction candidate was 43/43) | `PASS` |
| 4 | `flutter test packages/feldexa_application/test` | `0` | console | `PASS` — 227/227 tests (final, after the correction; 224/224 at `11856c7`) |
| 5 | `flutter test packages/feldexa_recognition/test` | `0` | console | `PASS` — 411/411 tests |
| 6 | `dart run tools/evaluation/golden_consumption_check.dart` | `0` | console: `consumed 508ed9be…f205e6`, `12 pages, 50 typed fields`, `projection EQUAL` | `PASS` |
| 7 | `python3 -m unittest tools/evaluation/test_golden_consumption.py` | `0` | console: `Ran 9 tests … OK` | `PASS` |
| 8 | `python3 -m unittest tools/evaluation/test_field_inventory_baseline.py` | `0` | console: `Ran 12 tests … OK` | `PASS` (unchanged producer gate) |
| 9 | `python3 -m unittest discover -s tools/repo -p 'test_*.py'` | `0` | console: `Ran 19 tests … OK` | `PASS` |

Check 3 includes the eleven new tests (final): nine runner-contract tests and four
`AnalyzeDocument` page-loop tests. Checks 4 and 5 are the complete package
suites required by the brief; check 8 re-runs the pre-existing producer gate to
show this slice did not disturb it.

## 5. Results

### 5.1 Red → green for point 5

The tests were written first against the intended API and run before any
implementation. The run failed to compile with the missing observation seam:

```text
packages/feldexa_application/test/analyze_document_test.dart:1320:9: Error:
  No named parameter with the name 'cancellation'.
  … lib/src/recognition/analyze_document.dart:342:41: Context: Found this
  candidate, but the arguments don't match.
packages/feldexa_application/test/raster_page_stage_runner_test.dart: [E]
  Failed to load … (same missing runner API; no `isCancelled` on the outcome)
```

After the minimal implementation the same command passes 46/46 (check 3, final; 43/43 at `11856c7`). The
new behaviour:

- **API parity.** `runRasterPageStageOffIsolate` accepts
  `Future<void>? cancellation` in both the VM and the inline variant, and
  `AnalyzeDocument.run` accepts the run-level signal under the same name.
  `RasterPageStageOutcome.cancelled()` / `isCancelled` is the content-free
  outcome; it has no suggestions, no failure category, and `timedOut == false`.
- **Worker is ended, not awaited.** On the VM the signal joins the same
  completion race as the deadline. When it wins, the worker is killed with
  `Isolate.immediate` and joined before the future completes — exactly like the
  deadline path — and the caller receives `cancelled()`. A stalled 3 s work
  closure with a 10 s deadline returns in under 2 s in the test. A signal that
  fails counts as a cancellation, so a broken signal cannot pin a page to the
  deadline. A signal that never completes leaves the deadline backstop intact
  (tested: 150 ms deadline, `timedOut == true`).
- **Nothing partial survives.** The returned outcome is content-free; the
  worker reply that would have carried the partial suggestion is no longer
  awaited, and the reply port is closed after the kill and join. The
  `AnalyzeDocument` page produces no envelope and is listed in
  `cancelledPageIndexes`, never in `timedOutPageIndexes` and never as failed
  (REC-004).
- **Page loop observes it.** Once the run-level signal completes, the in-flight
  page is cancelled by the runner and every page that has not started is
  reported cancelled without a render request. A page that had already finished
  keeps its envelope byte-identically: the test compares it against the same
  page analysed without cancellation (`canonicalJson` equality) and asserts that
  the raster port saw only pages 0 and 1 of a three-page run.
- **Inline parity is honest.** The single-isolate variant accepts the same
  signal and returns the same `cancelled()` outcome, but a running synchronous
  function cannot be preempted; it observes the signal before and after the
  work. The page-level checkpoint test cancels during render and proves the
  geometry stage is never dispatched for that page. This limitation is stated
  in the library comment and is not presented as preemption.
- **No new semantics.** Cancellation is the existing cancelled-page category of
  `page_analysis.dart` / `recognition-output.md` §4; no failure object, message
  key, envelope field, or `DocumentAnalysisResult` shape was added.

### 5.2 Golden consumption

The committed golden is **consumed, never regenerated**:

- the checker reads `tools/evaluation/goldens/field-inventory-baseline.v1.json`
  read-only, hashes the bytes it read, and rejects anything other than
  `508ed9beed5a3844aa3ce101d378f7243b47e259cbcda72a412bbe6067f205e6` before it
  parses a single projection field;
- the input corpus is the producer's own read-only seam
  `buildSyntheticCorpus()` (12 declared pages); the productive entry is
  `runRasterPageStage`, the same bytes-level stage `AnalyzeDocument` executes
  off-isolate, with the corpus's declared labels at confidence `0.9`;
- both sides are projected into one explicit canonical document — corpus
  identity (corpus/fixture/ground-truth SHA-256), per-page size, raster and
  declared-ground-truth identity, every typed field (rect, proposed type, label
  text, sorted union of geometry and typing cues) in the §5.2 order, the
  `baseline` comparison (verdict, failure codes, all integer counters, IoU
  aggregates) and the corpus-wide integer totals — and compared by canonical
  JSON bytes.

Result: **equal for all 12 pages and 50 typed fields**, exit 0 (checks 6/7).
The host test additionally proves:

- the golden's bytes, mtime and directory entries are unchanged after the run
  (consumption, not generation);
- a changed field rect or cue set is red (`projection DRIFT`, exit 1) even when
  the mutated copy's own hash is accepted via `--golden-sha`, so the projection
  comparison is not vacuous;
- a comment-only byte change stays green under an accepted hash (the checker
  consumes the projection rather than regenerating the artifact) but is red
  under the default bound hash;
- a missing or invalid golden is an error (exit 1), never a pass.

No golden value, threshold, fixture pin, or ground truth was edited.

## 6. Performance

No performance claim. The cancellation test asserts a functional bound only
(the future completes before the stalled work and before the 10 s deadline);
this is not a latency measurement and says nothing about SC-004. The golden
checker runs no OCR engine and reports no timing. Point 9 (Android
off-isolate run, SC-004 p50/p95/memory) is `NOT_RUN` and remains outstanding.

## 7. Limitations

- **Point 9 `NOT_RUN`.** The Android/emulator run of the off-isolate stage with
  SC-004 p50/p95 and memory numbers was not executed: the brief is host-only
  and forbids the emulator lane for this task. This is a deliberate `NOT_RUN`,
  not a `PASS`.
- **Inline mode cannot preempt.** A single web isolate cannot interrupt running
  work; it observes the signal at its checkpoints only. The VM/production path
  is the one that kills and joins immediately.
- **The signal is run-level.** `AnalyzeDocument.run` observes one cancellation
  future for the whole run; the existing `PageCancellation` predicate stays the
  per-page token. A completed signal also stops pages that have not started (they
  are reported cancelled, i.e. still pending).
- **The signal is a future.** A `Future` cannot be revoked, and a late
  completion after the page already finished is ignored. The VM runner attaches
  an observer for the page's lifetime; a long-lived caller-owned signal keeps
  that closure until it completes.
- **Golden proof is host-only.** It proves the productive stage still reproduces
  the frozen synthetic-corpus projection. It does not prove OCR quality, real
  document behaviour, Android runtime behaviour, or device performance.
- The new golden-consumption test is a host test invoked explicitly; it is not
  wired into `tools/gate.sh`.

## 8. Artifacts

Host-only code and tests (no binaries):

- `packages/feldexa_application/lib/src/recognition/raster_page_stage.dart` —
  `cancelled()` outcome and `isCancelled`.
- `packages/feldexa_application/lib/src/recognition/raster_page_stage_runner_vm.dart`
  — cancellation race, immediate kill and join.
- `packages/feldexa_application/lib/src/recognition/raster_page_stage_runner_inline.dart`
  — same signature and outcome contract, checkpoint observation.
- `packages/feldexa_application/lib/src/recognition/analyze_document.dart` —
  run-level watch, page boundary, cancelled outcome mapping.
- `packages/feldexa_application/test/raster_page_stage_runner_test.dart` —
  nine runner tests (four initial plus the failing-signal and two inline
  cancellation tests from the correction).
- `packages/feldexa_application/test/analyze_document_test.dart` — four
  page-loop tests and one stall helper.
- `tools/evaluation/golden_consumption_check.dart` — new read-only checker.
- `tools/evaluation/test_golden_consumption.py` — nine host tests.
- this report and its README index row.

## 9. Reproducibility

```sh
cd run-tscn02hu/worktrees/t086br-cancel-golden
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --no-pub
flutter test packages/feldexa_application/test/raster_page_stage_runner_test.dart \
  packages/feldexa_application/test/analyze_document_test.dart
flutter test packages/feldexa_application/test
flutter test packages/feldexa_recognition/test
dart run tools/evaluation/golden_consumption_check.dart
python3 -m unittest tools/evaluation/test_golden_consumption.py
python3 -m unittest tools/evaluation/test_field_inventory_baseline.py
python3 -m unittest discover -s tools/repo -p 'test_*.py'
```

The golden checker accepts `--golden PATH` and `--golden-sha SHA` for the drift
controls only; the default path and the default bound hash are the gate.

## 10. External attestation

None. No external reviewer, CI run, merge, or push is claimed.

## 11. Independent review (author leaves blank)

_Left blank for an independent reviewer._
