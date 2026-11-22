# 2026-11-22 NONE — T086B box-detector candidate indexing (sf-001 analysis timeout, issue #270)

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `PASS` |
| Task / issue | `T086B` / `#270` |
| Date / timezone | `2026-11-22 08:29–10:10 Europe/Berlin` |
| Revision | base commit `2ab14cc93f2452a0153e6ca28293573df8376f48` (verified `origin/main`); tree `dirty`: `apps/feldexa_app/android/gradlew.bat` SHA-256 `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62` (pre-existing line-ending-only working-tree change, not created, staged, or committed by T086B); branch `t086b` (owner prefix redacted per `reports/README.md` §4.2); the local candidate commit, final HEAD, and tree are recorded in the external attestation |
| External attestation | Coordinator-held dispatch transport record for this T086B run; it records the local commit, the final HEAD and tree, and this report's byte size and SHA-256 after the report commit |
| Build identity | No application build artifact. Host-VM `flutter test`, `dart analyze`, and `dart run` executed the Dart kernel under the git-ignored `.dart_tool/`; no APK, Gradle/Android build, PDFium runtime, emulator, or device was invoked |
| Toolchain | Flutter `3.47.7` stable (framework `abaf9c5237`), Dart `3.13.5`; Poppler `pdftoppm 26.10.0` (host rasterization only); Python `3.14.8`; Spec Kit CLI `1.2.3` (command binding only) |
| Input | committed fixtures `sf-001.pdf` 2 pages SHA-256 `22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038`; corpus `sf-002.pdf` 5 pages SHA-256 `bd8a0f7b231b0d5ba494b816350144999534c6dbffb151a14dc175f9fe802025`, `sf-003.pdf` 5 pages SHA-256 `c19afcf6f86ed21a422426c5f01613bb9643b097d0facad3b3349f9873e4ea4f`, `sf-004.pdf` 1 page SHA-256 `009c3babd2013e13fad9ef5977ec3d4c1d5842a52da0718e4ac06e3ff39d171e`; fixture catalog `apps/feldexa_app/assets/fixtures/catalog.json` 39163 bytes SHA-256 `62b075d53e102b23b172087bee215c2384526aaca8e9a870c5fa30efaa7f6b9a` |

## 1. Scope

This report covers exactly T086B / issue #270, the owner-approved prerequisite
for T086: diagnose and fix the real cause of the `sf-001.pdf` analysis timeout
without weakening detection quality or test requirements.

It changes three files and nothing else:

- `packages/feldexa_recognition/lib/src/geometry_detector.dart` — the box
  detector's candidate enumeration;
- `packages/feldexa_recognition/test/geometry_detector_performance_test.dart` —
  new rule-dense regression test (RED before, green after);
- `tools/evaluation/benchmark_detection_pgm.dart` — host-only per-page
  detection benchmark used for the measurements in §6.

What this run proves:

- The dominant cost was **not** rules, grids, underlines, whitespace, or merge,
  and not a micro-inefficiency inside the corner predicate: it was the
  `_detectBoxes` *enumeration order*. Every horizontal rule pair was crossed
  with every vertical rule pair before the corner test was applied, so the scan
  paid `O(h² · v²)` for combinations that the corner test rejects.
- On the committed `sf-001` raster the box stage consumed 83,440 ms of
  86,842 ms (96.1 %) on page 1 and 141,947 ms of 142,269 ms (99.8 %) on page 2.
- Indexing the vertical rules by the corner test's own necessary conditions
  removes 5–6 orders of magnitude of loop iterations while keeping the accepted
  combinations, their cues, and their emission order identical.
- Detection output on 12 of the 13 contract-valid fixture/corpus pages is
  **byte-identical** before and after (rect, sorted cues, measured ink
  coverage). No field, cue, or coverage value changed.
- The regression test fails on the unindexed scan (29,771 ms) and passes on the
  indexed scan (571 ms in the full suite) inside a 10,000 ms budget.

This report does not prove, and does not claim, any Android/emulator/device
behaviour, the SC-004 three-second device target, or a re-measured product
`editorAnalysisTimeout`. It is host-VM provenance only.

## 2. Revision and build

- Base commit: `2ab14cc93f2452a0153e6ca28293573df8376f48` (merge of PR #271,
  the owner-approved T086A/T086B prerequisite documentation).
- Working tree: clean except the pre-existing, line-ending-only
  `apps/feldexa_app/android/gradlew.bat` modification listed in the header. That
  file was not staged and not committed.
- No build step: every check ran from source through the Dart VM
  (`flutter test`, `dart analyze`, `dart run`). There is no artifact, so no
  build-identity hash is claimed.
- The candidate commit is recorded in the external attestation, not here
  (`reports/README.md` §4.1).

### 2.1 Command binding (required before the first edit)

The task required resolving `command:speckit.implement` through
MCP → JSON CLI → command file before the first edit. Recorded once at
`2026-11-22 08:29 Europe/Berlin`, before any repository write:

| Step | What was executed | Result |
| --- | --- | --- |
| 1 | MCP `spec_kit` server: `specify_artifact_info(identifier: "command:speckit.implement")` | returned `kind: command`, `name: speckit.implement`, single `replace` stack layer, no source path |
| 2 | `specify artifact info command:speckit.implement --json` (Spec Kit CLI `1.2.3`, repo root) | exit `0`, 576 ms, same payload without a source path |
| 3 | resolved to the repository command file `.opencode/commands/speckit.implement.md` | 218 lines, 12,562 bytes, SHA-256 `e036ce63702db93e656e1c91ee6c02a8dc3d4a4f8624f8ba4adc69027fe68983` |

The MCP server exposes only `version`, `artifact list/info`, and a
`version`-only `run_command`, so the JSON CLI call is the authoritative step that
identifies the artifact; the command file above is the binding this run
followed.

## 3. Environment

```text
NONE (host VM): Linux 7.2.7-1-cachyos x86_64; Intel Core i5-3570K @ 3.40 GHz, 4 cores / 4 threads
                (no SMT), 23 GiB RAM, no CPU pinning, no cgroup CPU limit applied;
                Dart 3.13.5 (Flutter 3.47.7 stable, framework abaf9c5237);
                host rasterizer Poppler pdftoppm 26.10.0 (grayscale, 200 DPI);
                shared Orca compute slot held for every heavy command, one sequence at a time.
```

Serial-execution note: every heavy command in this run was wrapped in the
maintainer compute-slot helper and executed one sequence at a time; the slot was
shared with other worktrees (including the T086A emulator run), which is why
single measurements are reported instead of a repeated-run median. Timings are
single-shot, JIT-warm-once values from `dart run`, not AOT or device numbers.

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `dart format --output=none --set-exit-if-changed packages/feldexa_recognition/lib/src/geometry_detector.dart packages/feldexa_recognition/test/geometry_detector_performance_test.dart tools/evaluation/benchmark_detection_pgm.dart` (repo root) | `0` | console only (not retained) | `PASS` |
| 2 | `dart analyze packages/feldexa_recognition tools/evaluation` (repo root) | `0` | console only (not retained) | `PASS` |
| 3 | `flutter test` (`packages/feldexa_recognition`) | `0` | console only (not retained) | `PASS` — 323 tests, 0 failures (was 320 before the new file) |
| 4 | `flutter test test/geometry_detector_performance_test.dart` against the **unindexed** detector (RED capture, fixed file temporarily replaced by the base revision of the detector) | `1` | console only (not retained) | `FAIL` as designed — `T086B dense page: 29771 ms, 7 candidates, budget 10000 ms`; the other two tests of the file still pass on the unindexed scan |
| 5 | `flutter test test/geometry_detector_performance_test.dart` against the indexed detector | `0` | console only (not retained) | `PASS` — `T086B dense page: 1229 ms` first-run JIT, 571 ms inside the full suite |
| 6 | `python3 -m unittest tools/evaluation/test_benchmark_recognition.py tools/evaluation/test_check_evidence_docs.py tools/evaluation/test_manual_baseline.py` (repo root) | `0` | console only (not retained) | `PASS` — 31 tests |
| 7 | `flutter test test/editor_analysis_test.dart test/simulated_raster_parity_test.dart test/synthetic_fixtures_test.dart` (`apps/feldexa_app`) | `0` | console only (not retained) | `PASS` — 64 tests |
| 8 | `dart run tools/evaluation/benchmark_recognition.dart --synthetic --output <scratch>/bench-synthetic.json --form-id sf-001 --device-profile host-vm --build-mode host` (repo root) | `0` | `<scratch>/bench-synthetic.json` (not retained) | `PASS` — T063 tool unaffected, `detectMs` 219 measured, raster/OCR `NOT_RUN` by that tool |
| 9 | `flutter test test/web_recognition_browser_entry_test.dart` (`apps/feldexa_app`) | `0` | console only (not retained) | `UNAVAILABLE` — the file is a browser-platform entry; the VM runner reports "No tests were found" |
| 10 | 24 per-page detector runs of the fixture/corpus rasters through `tools/evaluation/benchmark_detection_pgm.dart`, 12 with the unindexed detector and 12 with the indexed detector (§6) | `0` | `<scratch>/old-*.json`, `<scratch>/new-*.json` (not retained) | `PASS` — see §5.3 |

`PARTIAL` is not used: every check named above either ran or is named as
unavailable. The unavailable one is a browser-platform entry file, not a
regression signal.

## 5. Results

### 5.1 Root cause

`GeometryDetector.detect` is synchronous, so the 5-minute
`editorAnalysisTimeout` cannot preempt it; the timeout only observes later that
the page never finished. The measured stage split for `sf-001` page 1 (200 DPI
raster 1654 × 2339, produced with `pdftoppm -gray -r 200`) was:

| Stage | Page 1 before | Page 1 after | Page 2 before | Page 2 after |
| --- | ---: | ---: | ---: | ---: |
| ink mask | 8 ms | 8 ms | 8 ms | 8 ms |
| rules | 77 ms | 72 ms | 80 ms | 82 ms |
| grids | 42 ms | 39 ms | 44 ms | 54 ms |
| **boxes** | **83,440 ms** | **34 ms** | **141,947 ms** | **45 ms** |
| underlines | 1 ms | 1 ms | 1 ms | 1 ms |
| whitespace | 172 ms | 172 ms | 174 ms | 176 ms |
| merge + alignment | 4 ms | 3 ms | 5 ms | 4 ms |
| **`detect` total** | **86,842 ms** | **350 ms** | **142,269 ms** | **382 ms** |

(Instrumented builds; totals without instrumentation are 81,080 ms and
141,823 ms before, and 350 ms / 382 ms after — consistent within ±7 %.)

The box stage dominated because of its enumeration, not its predicate:

| Page | horizontal rules | vertical rules | horizontal pairs | vertical pairs | corner-compatible boxes | rule-pair slots visited |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `sf-001` page 1 | 291 | 540 | 42,195 | 145,530 | 16 | 6.14 × 10⁹ |
| `sf-001` page 2 | 339 | 608 | 57,291 | 184,528 | 20 | 1.06 × 10¹⁰ |

The former loop body applied `_cornersAgree` only *after* both nested pair
enumerations, so 99.9999997 % of the visited combinations were provably
impossible: only 16 (page 1) and 20 (page 2) combinations ever reached the
corner test, and therefore the ink-coverage measurement, at all.

### 5.2 Fix

`_detectBoxes` now asks an index (`_VerticalRuleIndex`) which vertical rules can
be one side of the box instead of enumerating all of them. The index encodes the
corner test's own necessary conditions, derived from the unchanged predicate
`_cornersAgree`:

- a rule can be the `left` side only if its centre x is within
  `_cornerTolerancePx` of **both** `top.x0` and `bottom.x0`, and its start y is
  within tolerance of `top.centerY` and its end y within tolerance of
  `bottom.centerY`;
- the `right` side is the same with `x1`;
- therefore a box can only exist when the two horizontal rules' endpoints agree
  within twice the tolerance, and the vertical candidates of each side live in
  the two-centre window.

The index is built once per page (centre-x list in the detector's existing
`_compareRuleCenterX` order, plus a start-y permutation) and each query is two
binary searches plus a filter over the smaller window. The loop body — the
ordering checks, `_cornersAgree`, the page-border rejection, the grid-line
rejection, the ink gate, and the `small_square` decision — is unchanged, and the
`rightIndex > leftRuleIndex` pairing and ascending emission order are preserved,
so the accepted combinations, their cues, and their order are identical to the
exhaustive scan.

No isolate, worker, timeout, or other architectural device was added: the task
allows one only as an additional defence, and the measured residual cost (≤
632 ms on any fixture/corpus page, of which ≈ 46 % is the linear whitespace
pass) makes a second defence unnecessary for this corpus. The synchronous
detector and its 5-minute product timeout are unchanged.

### 5.3 Detection equivalence

The harness writes every candidate's `x`, `y`, `width`, `height`, sorted `cues`,
and measured `inkCoverage`. Comparing the unindexed and indexed builds page by
page:

| Page | Candidates (before = after) | Byte-identical output |
| --- | ---: | --- |
| `sf-001` page 1 | 22 | yes |
| `sf-001` page 2 | 42 | yes |
| `sf-002` page 1 | 15 | yes |
| `sf-002` page 2 | 19 | yes |
| `sf-002` page 3 | 18 | yes |
| `sf-002` page 4 | 17 | yes |
| `sf-002` page 5 | 13 | yes |
| `sf-003` page 1 | 7 | yes |
| `sf-003` page 2 | 7 | yes |
| `sf-003` page 3 | 7 | yes |
| `sf-003` page 4 | 7 | yes |
| `sf-004` page 1 | 24 | yes |
| `sf-003` page 5 | `NOT_RUN` (see §7) | `NOT_RUN` |

Every candidate on every measured page is equal in `rect`, `cues`, and
`inkCoverage`; no field was dropped, added, reordered, or degraded for speed.
Cue classes exercised include `box`, `small_square`, `grid_cell`/`table_cell`,
`underline`, `whitespace`, and `alignment_left`. The 323-test recognition suite
(covering exact rects, cue sets, ink gates, grids, whitespace, and alignment)
also passes unchanged, as does the application-level analysis suite and the
fixture-parity suite.

### 5.4 Regression test

`packages/feldexa_recognition/test/geometry_detector_performance_test.dart`
builds a 1654 × 2339 A4 raster with 340 independent horizontal rules (2 px
thick, 6 px pitch, five span variants so no grid cluster forms) and 240
independent vertical rules (2 px thick, 5 px pitch, placed below the horizontals
so the page contains no addressable cell), plus three closed rectangles in an
otherwise clean corner. That shape reproduces the pathology (roughly
1.65 × 10⁹ rule-pair slots) without depending on PDF rasterization.

- RED: with the exhaustive scan, `detect` needs 29,771 ms and the budget
  assertion fails.
- GREEN: with the index, `detect` needs 571 ms in the full suite (1,229 ms on a
  cold first run in its own process, which is JIT onset, not detection work).
- The budget is 10,000 ms: ≈ 17× above the observed indexed cost and ≈ 3× below
  the observed exhaustive cost, so the test is neither a stopwatch race nor
  satisfiable by the old implementation.
- Two further assertions in the same file keep the test honest: the three
  rectangles must still be detected as `box` candidates with their exact
  interior rects on the rule-dense page, and two successive calls on the same
  raster must return equal candidate lists. Both pass on the unindexed and the
  indexed build, so the file cannot be satisfied by returning an empty list.

## 6. Performance

Conditions (per `reports/README.md` §4.4): host VM, Intel Core i5-3570K
(4 threads, 3.40 GHz base), 23 GiB RAM, Linux 7.2.7-1-cachyos, Dart 3.13.5 JIT
via `dart run`, Poppler `pdftoppm 26.10.0` for rasterization, one page per
process, single shot per page, no warm-up beyond process start, compute slot
held. Each row is the measured `GeometryDetector.detect` time only
(`RasterAnalysis` construction excluded, 112–310 ms per page and unchanged by
this fix). This is not the SC-004 device claim and not an emulator result.

Command shape (rasterization is host-only and shared by both builds):

```text
pdftoppm -gray -r 200 -f <page> -l <page> <pdf> <scratch>/<id>
dart run tools/evaluation/benchmark_detection_pgm.dart <scratch>/<id>-<page>.pgm <widthPt> <heightPt> <scratch>/<tag>.json
```

| Page | Size (pt) | Before: exhaustive scan | After: indexed scan | Speed-up | Candidate count |
| --- | --- | ---: | ---: | ---: | ---: |
| `sf-001` page 1 | 595.28 × 841.89 | 81,080 ms | **350 ms** | 231.7× | 22 |
| `sf-001` page 2 | 595.28 × 841.89 | 141,823 ms | **382 ms** | 371.3× | 42 |
| `sf-002` page 1 | 595.28 × 841.89 | 230,034 ms | **343 ms** | 670.7× | 15 |
| `sf-002` page 2 | 595.28 × 841.89 | 191,191 ms | **443 ms** | 431.6× | 19 |
| `sf-002` page 3 | 595.28 × 841.89 | 188,591 ms | **415 ms** | 454.4× | 18 |
| `sf-002` page 4 | 595.28 × 841.89 | 205,653 ms | **429 ms** | 479.4× | 17 |
| `sf-002` page 5 | 595.28 × 841.89 | 182,624 ms | **632 ms** | 289.0× | 13 |
| `sf-003` page 1 | 595.28 × 841.89 | 1,787 ms | **380 ms** | 4.7× | 7 |
| `sf-003` page 2 | 841.89 × 595.28 | 1,584 ms | **497 ms** | 3.2× | 7 |
| `sf-003` page 3 (rot 90) | 841.89 × 595.28 | 1,914 ms | **550 ms** | 3.5× | 7 |
| `sf-003` page 4 (rot 180) | 595.28 × 841.89 | 1,622 ms | **498 ms** | 3.3× | 7 |
| `sf-004` page 1 | 595.28 × 841.89 | 294,564 ms | **596 ms** | 494.2× | 24 |
| `sf-003` page 5 (rot 270) | 595.28 × 419.53 | `NOT_RUN` | `NOT_RUN` | — | — |

Product-level reading: the worst measured page before the fix needed
294.6 s and the second worst 230.0 s against the unchanged 5-minute
`editorAnalysisTimeout`, i.e. the timeout was being hit or nearly hit on
ordinary corpus pages, not on a single outlier. After the fix the worst measured
page needs 0.632 s.

Residual cost distribution after the fix (`sf-001` page 1): whitespace 172 ms
(49 %), rules 72 ms (21 %), grids 39 ms (11 %), boxes 34 ms (10 %), mask 8 ms,
underlines 1 ms, merge/alignment 3 ms. The box stage is no longer a hot spot; the
next-largest stage is the linear 4-connected background pass, left unchanged
because it is not pathological and out of T086B scope.

## 7. Limitations

- **Host class only.** All timings are JIT `dart run` on one host CPU. No AOT
  measurement, no Android/emulator/device measurement, no thermal or
  background-load control, no repeated-run median/p95. The reported speed-ups
  are order-of-magnitude evidence for the removed algorithmic cost, not an
  SC-004 claim.
- **One page excluded from the equivalence matrix.** `sf-003` page 5 is
  catalogued as 595.28 × 419.53 pt, rotation 270, so the contract raster is
  1654 × 1165 px; host `pdftoppm` renders it as 1654 × 1166 px at 200 DPI
  (rounding up), and the detector correctly rejects the mismatched raster with a
  content-free `ArgumentError`. Feeding it would have required editing the page,
  which the task forbids, so that page carries no before/after number. The
  shared compute slot was also held by the T086A emulator run at that point and
  the remaining evidence did not justify re-queueing.
- **Statistics over 12 pages.** Equivalence is proved on the committed fixture
  and corpus rasters plus 323 host tests; it is not a proof for arbitrary pages.
  The argument in §5.2 is a superset argument over the unchanged predicate, and
  the 12-page byte-identical comparison is the empirical check on that argument.
- **No emulator evidence.** Deliberately out of scope: the task forbids touching
  the T086A emulator worktree and requires any emulator evidence to use a
  separate allocation window. None was taken, and the product-level claim that
  the editor no longer times out is therefore *derived* from the detector
  measurements, not observed on Android.
- **No isolate/timeout defence.** A future pathological page could still make
  the synchronous detector exceed 5 minutes. That risk was not addressed here
  because it needs an architecture decision (scope limit) and because the
  measured corpus no longer comes close.
- **Browser entry check unavailable** (§4 check 9): the web recognition entry
  file only runs on the browser platform; no browser run was taken in this
  worktree.

## 8. Artifacts

`NOT_RUN`/unretained logs: every check above logged to the terminal only, and
the per-page candidate JSON files and the synthetic T063 benchmark report live
in a scratch directory outside the repository; none are candidate or bundle
contents. The report's own row is omitted per `reports/README.md` §4.1.

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Detector (box scan indexed) | `packages/feldexa_recognition/lib/src/geometry_detector.dart` | 54,222 | `4bc1569fa8a0f886fc2de6bfdf03c3bab492930f3482694925704b789b085aa6` |
| Rule-dense regression test | `packages/feldexa_recognition/test/geometry_detector_performance_test.dart` | 6,751 | `735f2cd616b963f90ab6aadd4136e57e21efa0a0e9e75cfdbb3d130b3223ebcf` |
| Host per-page detection benchmark | `tools/evaluation/benchmark_detection_pgm.dart` | 6,908 | `e5b0a01cc2fddc1b9e054ec507334e0fa3e6db95378e225585a2c9a2494fa7a5` |

## 9. Reproducibility

1. Start from base commit `2ab14cc93f2452a0153e6ca28293573df8376f48` on a Dart
   `3.13.5` toolchain (`flutter pub get --offline` in the workspace root).
2. Rasterize a page at the contract size:
   `pdftoppm -gray -r 200 -f 1 -l 1 apps/feldexa_app/assets/fixtures/sf-001.pdf <scratch>/sf001`
   → `<scratch>/sf001-1.pgm`, binary PGM `P5`, header `1654 2339 255`.
3. Measure the detector only:
   `dart run tools/evaluation/benchmark_detection_pgm.dart <scratch>/sf001-1.pgm 595.28 841.89 <scratch>/after-p1.json`
   → one JSON line; expected after the fix: `detectMs` in the low hundreds of
   milliseconds and `candidates` 22.
4. To reproduce the before/after comparison, restore the base revision of
   `packages/feldexa_recognition/lib/src/geometry_detector.dart`
   (`git show 2ab14cc9:packages/feldexa_recognition/lib/src/geometry_detector.dart`),
   repeat step 3 with a different `<scratch>/before-p1.json`, then
   `cmp <scratch>/before-p1.json <scratch>/after-p1.json` → expected: no
   difference. Restore the fixed file afterwards. Expect ≈ 81 s for that page on
   the hardware in §3.
5. Regression test:
   `cd packages/feldexa_recognition && flutter test test/geometry_detector_performance_test.dart`
   → expected: 3 tests pass, printed dense-page time well under 10,000 ms. With
   the base revision of the detector the same command fails the budget assertion.
6. Full suite: `cd packages/feldexa_recognition && flutter test` → expected: 323
   tests, 0 failures.
7. Cleanup: remove the scratch rasters and JSON files; they are not repository
   content.

## 10. External attestation

The transport attestation is held by the coordinator for this dispatch; it is
not part of the candidate commit and is not reproduced here. It records the
candidate commit SHA, the final HEAD and tree, this report's byte size and
SHA-256 after the report commit, and the delivered patch/bundle transport
hashes. Per `reports/README.md` §4.1 this report therefore omits its own commit
SHA, its own byte size, and its own hash.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
