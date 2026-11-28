# Browser-Lane entsperrt: Ursache, Fix und Suite-Belege (T072/T087/T101/T111/T121/T127, T131/T132 abgegrenzt)

**Date**: 2026-11-28 02:40 Europe/Berlin · **Branch**: `xxammaxx/browser-lane` ·
**Base**: `2017df7` (current `origin/main` at rebase time); candidate `aa3878d` (code `abcd808`) · **Role**: build
(worker) · **Evidence classes**: `SIMULATED` (Chrome browser lane), host checks
(`NONE` provenance: bootstrap, formatter, analyzer, gate mechanics). This report
makes no Android, `EMULATOR`, or `DEVICE` claim and no SC-004/005/006 claim.

## Result in one sentence

`flutter test --platform chrome` was never environment-blocked: the suite
compiles, boots and connects, but the app's test bootstrap awaited
`initializeFieldTextMeasure()`, whose `rootBundle` load of
`assets/fonts/metrics.json` **never completes and never throws** on the web test
platform (the harness runs with `ignorePlatformMessages = true`, so even a served
bundle would not resolve it); guarding the load with `kIsWeb` unblocks the lane, and T072 (2/2), T087 (3/3), T101 (3/3), T121 (3/3)
and T127 (8/8) now pass in Chrome, while T111 stays `NOT_RUN` because its suite
is `@TestOn('vm')` and T131/T132 stay `NOT_RUN` because Chrome test roots are
`<project>/test` and no chromedriver/`test_driver` exists.

## Environment and admission

| | |
| --- | --- |
| Host | Linux x86_64, CachyOS kernel 7.2.7, 4 vCPU, 23 GB RAM; no proxy variables |
| Toolchain | Flutter 3.47.7 stable, Dart 3.13.5, `flutter test --platform chrome` (dartdevc, canvaskit) |
| Browser | Google Chrome for Testing 156.0.8078.4 (Playwright `chromium-1248`) via `tools/browser/chrome_launch.sh`; no system Chrome/Chromium/chromedriver on `PATH` |
| Viewport | Flutter's test host page, `2400 x 1800`, DPR 1 |
| Input | committed synthetic fixtures under `apps/feldexa_app/assets/fixtures/` |
| Product code | unchanged; one test bootstrap, three suite headers, one new launcher shim |

## 1. Root cause (measured)

The earlier finding (`run-tscn02hu/reports/findings/2026-11-27-flutter-browser-lane-hang.md`)
suspected the Chrome sandbox or a renderer start failure. Both are falsified:

1. **Sandbox is not the blocker.** `chrome --headless=new --dump-dom about:blank`
   exits 0 **with and without** `--no-sandbox`.
2. **WebGL is not the blocker.** Chrome 137+ refuses the automatic
   software-WebGL fallback; without `--enable-unsafe-swiftshader` it logs that
   refusal instead of creating a context. With the flag a WebGL2 context exists
   in the suite frame — and the suite still hung. The flag stays in the shim
   because the refusal is a live risk for CanvasKit, but its necessity was not
   isolated by this run.
3. **The suite is not the blocker.** A two-line canary widget test hangs the
   same way: this is harness-wide.
4. **Where it hangs.** CDP on the hanging page: all **537** dartdevc modules
   load, `main.dart` starts, `flt-glass-pane` exists, **no** JavaScript
   exception, **no** failed request, renderer CPU idle; the last browser message
   is `Connecting channel for suite …`, and marker prints in the test
   entrypoint's `main()` never appear — `main()` is never entered.
5. **Why.** `apps/feldexa_app/test/flutter_test_config.dart` ran
   `await initializeFieldTextMeasure()` before `testMain()`. That awaits
   `rootBundle.loadString('assets/fonts/metrics.json')`. The web test harness
   runs with `TestEnvironment.flutterTester()` and
   `ignorePlatformMessages = true` (`_test_selector_web.dart` /
   `testing.dart`); `PlatformDispatcher._sendPlatformMessage` therefore
   returns without a reply and `PlatformAssetBundle.load` waits forever — even
   a served bundle would not resolve it (the 404 asset route exists but the
   app never requests it; CDP showed no failed request). The load future never
   settles and does not throw, so the `try/catch` inside
   `initializeFieldTextMeasure` cannot degrade it — and every test declaration
   is starved.

Proof by isolation: bootstrap moved aside → canary **PASS** (`All tests passed!`,
33 s); bootstrap restored → hang; bootstrap guarded with `if (!kIsWeb)` →
canary **PASS** (37 s) and all §3 suites run.

## 2. Fix

1. `apps/feldexa_app/test/flutter_test_config.dart`: the FLD-001 text-fit table
   is now loaded only off the web (`if (!kIsWeb) { … await
   initializeFieldTextMeasure(); }`), with the measured reason documented in the
   file. Host-VM tests keep the production advance table.
2. `tools/browser/chrome_launch.sh` (new): `CHROME_EXECUTABLE` shim that adds
   `--no-sandbox --disable-dev-shm-usage --disable-gpu
   --enable-unsafe-swiftshader --use-angle=swiftshader` and forwards every
   Flutter argument. It also removes the "binary not on the gate search path"
   part of the old blocker.
3. `apps/feldexa_app/test/web_uncertainty_browser_entry_test.dart`: the suite
   carried a lane-refusing guard (`expect(kIsWeb, isFalse, reason: 'this run is
   the host-VM lane')`). The test's subject — `FeldexaApp`'s default
   `simulatedShell` — is `kIsWeb` (see `lib/main.dart`), so the guard was
   replaced by the lane-independent assertion
   `expect(shell.simulatedShell, equals(kIsWeb))`, plus an explicit-override
   check. Header updated.
4. Headers of T121 and T111 updated: the T121 browser row is no longer
   `NOT_RUN`; T111 is `NOT_RUN` because the suite is VM-only (`dart:io` PDF
   work), not because the lane is broken.
5. `apps/feldexa_app/test/release_manifest_audit_test.dart`: the T138
   release-manifest audit reads the repository tree through `dart:io` but
   carried no platform tag, so the chrome lane picked it up and failed with
   `Unsupported operation: _Namespace` (`Directory.current`). It is now
   `@TestOn('vm')`, which is what it always was in practice (it runs in gate
   check 5 on the host VM).

`dart format` on the four touched Dart files: **0 changed**. `flutter analyze
--no-pub` on the touched files: **No issues found** (exit 0).

## 3. Browser-lane results (Chrome 156, dartdevc, canvaskit)

| Task | Suite | Tests | Outcome | Wall |
| --- | --- | ---: | --- | ---: |
| T072 | `test/web_review_browser_entry_test.dart` | 2 | **PASS 2/2** | 90 s |
| T087 | `test/web_fill_browser_entry_test.dart` | 3 | **PASS 3/3** | 67 s |
| T101 | `test/web_persistence_browser_entry_test.dart` | 3 | **PASS 3/3** | 104 s |
| T111 | `test/web_export_browser_entry_test.dart` | — | `NOT_RUN` — `@TestOn('vm')`, runner reports "No tests were found" (exit 79) | 69 s |
| T121 | `test/web_template_browser_entry_test.dart` | 3 | **PASS 3/3** | 85 s |
| T127 | `test/web_uncertainty_browser_entry_test.dart` | 8 | **PASS 8/8** (7/8 before the lane guard was fixed) | 138 s |
| T131 | `integration_test/web_viewport_test.dart` | — | `NOT_RUN` — not loadable from the web test root | 73 s |
| T132 | `integration_test/geometry_parity_test.dart` | — | `NOT_RUN` — same | 30 s |

Same lane, suites outside the task list (they matter for the gate's all-files
browser check):

| Suite | Tests | Outcome |
| --- | ---: | --- |
| `test/web_import_browser_entry_test.dart` | 6 | **FAIL 1/6** — the suite reads fixtures from the loopback server `127.0.0.1:8765`; the server was not running for this gate invocation, so five tests fail on `ProgressEvent` |
| `test/web_recognition_browser_entry_test.dart` | 4 | **FAIL 0/4** — same missing loopback fixture server |
| `test/web_fixtures_browser_test.dart` | 4 | all self-skip (`Skip: requires the fixture server: …`) |
| `test/release_manifest_audit_test.dart` | 1 | skipped by the chrome lane after the `@TestOn('vm')` fix; runs in gate check 5 |
| `test/stored_list_50_test.dart` | 2 | **FAIL 1/2** — flaky in the browser lane: the same 500 ms host-budget test passed in an earlier gate run and failed once after ~18 s under dartdevc; the lazy-rendering test passes |

Wall times include the per-file dartdevc build (about 30-40 s of each run).

## 4. Local gate (`tools/gate.sh`, no `--allow-unavailable`)

`tools/gate.sh` from the repository root, `CHROME_EXECUTABLE` pointing at the
shim, **without** `--allow-unavailable` and without `--allow-absent`: exit **1**.

| Check | Result | Numbers |
| --- | --- | --- |
| dependency resolution (`pub get`) | PASS | `pubspec.lock` unchanged |
| formatting (`dart format`, width 80) | PASS | 385 files, 0 changed |
| static analysis (`flutter analyze`) | PASS | no issues |
| shared packages (9 `flutter test` runs) | PASS | **1,903** passed, 6 skipped (adapters_android 21, adapters_simulated 113, application 216, core 612, export 121, ports 138, recognition 411, testkit 154, ui 117) |
| app unit/widget (`flutter test`) | PASS | **716/716** |
| SIMULATED app browser (`flutter test --platform chrome`) | **FAIL** (exit 1) | **58** passed, **4** skipped, **10** failed in 3 suites |
| SIMULATED browser integration driver | ABSENT | `test_driver/integration_test.dart` missing; 4 `integration_test/web_*` suites present |
| repository guards (`python3` unittest) | PASS | 19/19 |

Gate summary: **14 passed, 1 failed, 0 unavailable, 1 absent planned layer** —
`GATE FAILED`, exit 1. Compared with the T145 baseline
(`specs/001-scanned-form-workflow/reports/2026-11-27-t145-t134-t138.md`:
14 passed, 0 failed, 1 unavailable, 1 absent, exit 3), the browser lane moved
from `UNAVAILABLE` to **executed**: nothing is unavailable any more, and the
single executed failure is the browser check.

The 10 browser-check failures, per suite:

| Suite | Failures | Cause |
| --- | ---: | --- |
| `test/web_import_browser_entry_test.dart` | 5 of 6 | reads fixtures from the loopback server `http://127.0.0.1:8765/fixtures/…` (`dart:html.HttpRequest`); the server was not running for this gate invocation (`ProgressEvent`) |
| `test/web_recognition_browser_entry_test.dart` | 4 of 4 | same missing loopback fixture server |
| `test/stored_list_50_test.dart` | 1 of 2 | the ratified **500 ms** host build/layout budget under dartdevc — flaky in the browser lane: the same test passed in an earlier gate run and failed once after ~18 s. The suite declares itself "Evidence class: NONE (host widget test)" |

The two fixture suites only need the existing `test_web_fixtures.sh` server
(`serve_web_fixtures.dart --root apps/feldexa_app/web --port 8765`) started
before the chrome check — the gate does not start it; that is a repository
robustness decision, not a drive-lane requirement. `stored_list_50` is a
host-budget test the chrome lane picks up because the file carries no platform
tag (flaky there). Both are repository-structure decisions — the environment
block is gone — see §5.

## 5. Limitations and owner decisions

1. **FLD-001 measurement is disabled on the browser lane.** The web test
   harness never resolves `rootBundle` asset loads
   (`ignorePlatformMessages = true`), so `metrics.json` is unreachable there by
   construction. Browser suites must not assert overflow behaviour derived from
   that table; the host-VM lane keeps it.
2. **Fixture-reading suites need the loopback server on the chrome lane.**
   `web_import` and `web_recognition` read `http://127.0.0.1:8765/fixtures/…`
   via `dart:html.HttpRequest`; the gate does not start
   `tools/corpus/synthetic/serve_web_fixtures.dart` (the existing
   `test_web_fixtures.sh` wrapper shows the way). Starting that server before
   the chrome check should make them pass; the drive lane with
   `test_driver/integration_test.dart` is only needed for the
   `integration_test/` suites (T131/T132).
3. **`integration_test/` suites cannot run in the chrome test lane.**
   `flutter test --platform chrome` roots suites at `<project>/test`; a path
   under `integration_test/` fails to compile (`Error when reading
   'org-dartlang-app:///integration_test/…': File not found`). T131/T132 need
   either a `test/`-rooted mirror (the pattern T072/T087/T101 already use) or
   the chromedriver lane. `chromedriver` and `apps/feldexa_app/test_driver/` are
   both absent on this host.
4. **`stored_list_50_test.dart` runs outside its declared evidence class.**
   Its header calls it a host widget test with a host build/layout bound
   (500 ms, OD-4/Q10=A), but the file has no platform tag, so the chrome lane
   runs it and the budget was flaky there under dartdevc (passed once, failed
   once after ~18 s). Either tag the file
   `@TestOn('vm')` or skip only the budget test with `kIsWeb`; the lazy-rendering
   assertion is valid on both lanes and passes.
5. **Owner decisions required** — the environment-side block is gone; what
   remains is repository structure:
   - start the existing loopback fixture server (`test_web_fixtures.sh`) for the
     fixture-reading suites in the chrome check, or keep them out of it by an
     explicit, documented mechanism; the drive lane
     (`test_driver/integration_test.dart` + `chromedriver`) is only for the
     `integration_test/` mirrors;
   - decide T131/T132: `test/`-rooted mirror or chromedriver lane.
6. No `EMULATOR` or `DEVICE` run is part of this report. T128 (Chrome editing
   journey with the fixture server) remains a separate slice, as the brief
   allows.

## 6. Changed artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Chrome launcher shim (new) | `tools/browser/chrome_launch.sh` | 2083 | `87d6f467bc1903e2f0efdd91e437f6cb42333f87258722894f44a8fc45374af1` |
| Test bootstrap, web-guarded metric load | `apps/feldexa_app/test/flutter_test_config.dart` | 5985 | `6c2b5769d573b8d58666c3a3d8d19e0a795a48f623618200f6a77e174331b557` |
| T127 suite, lane guard replaced | `apps/feldexa_app/test/web_uncertainty_browser_entry_test.dart` | 7073 | `094d6cbd9bb04c85117c96ccd37b475aadf7f7981686d8a66c9ff4e1e7b08a11` |
| T121 suite header | `apps/feldexa_app/test/web_template_browser_entry_test.dart` | 5906 | `9f6af70ab616ca8484a8e647c04311f2c7b7b0ed0b7e751b4f0c70c1bb091587` |
| T111 suite header | `apps/feldexa_app/test/web_export_browser_entry_test.dart` | 12298 | `981c3e38d5fa83a4440c419e0ef60b89d784d429ba60e2f1f2e934b877b8f9fa` |
| T138 manifest audit, `@TestOn('vm')` added | `apps/feldexa_app/test/release_manifest_audit_test.dart` | 890 | `c8c0e87459d5af77c30c253ad9aceef1e95d82a1b51c7f09aaa331cdf7c467d5` |

Run logs are host-local and not retained in the candidate commit; §7
regenerates every number above. The evidence was produced at candidate
`aa3878d` (code `abcd808`); all later commits in this PR are report/docs-only.

## 7. Reproducibility

1. Start from the candidate commit `aa3878d` (code commit `abcd808`; the unguarded base cannot reproduce steps 3–5).
2. `cd apps/feldexa_app && flutter pub get`.
3. Export `CHROME_EXECUTABLE=<repo-root>/tools/browser/chrome_launch.sh` (or any
   Chrome 137+ binary plus `--enable-unsafe-swiftshader`).
4. `flutter test --no-pub --platform chrome test/web_review_browser_entry_test.dart`
   → `All tests passed!` (2 tests) in about 90 s including the dartdevc build.
5. Repeat for `web_fill` (3), `web_persistence` (3), `web_template` (3),
   `web_uncertainty` (8) → all pass.
6. `flutter test --no-pub --platform chrome test/web_export_browser_entry_test.dart`
   → `No tests were found` (exit 79): the suite is `@TestOn('vm')`.
7. `flutter test --no-pub --platform chrome integration_test/web_viewport_test.dart`
   → compile error `File not found`: expected, the web test root is `test/`.
8. From the repository root, with `CHROME_EXECUTABLE` exported:
   `tools/gate.sh` (no `--allow-unavailable`) — see §4.
9. Cleanup: the shim keeps no state; Chrome profiles live in the run's
   temporary directory.
