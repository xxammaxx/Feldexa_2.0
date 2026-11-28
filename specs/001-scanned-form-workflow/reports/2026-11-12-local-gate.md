# Local acceptance gate (T145) — 2026-11-12-local-gate

**Date**: 2026-11-28 · **Branch**: `xxammaxx/t110-t146-drive` · **Base**:
`c4753fc` (current `origin/main` at the start of the completion wave) ·
**Role**: build (worker) · **Evidence classes**: `NONE` (static/unit/guards),
`SIMULATED` (Chrome lanes). No `EMULATOR`/`DEVICE` check is executed by the
gate.

## Result

`tools/gate.sh` completes without any escape hatch:

```
Checks passed: 19; failed: 0; unavailable: 0; absent planned layers: 0
GATE PASSED
```

Exit **0**. All per-check logs are retained in `/tmp/feldexa-gate-final`.

## Command

```bash
TMPDIR=/home/xxammaxx/fdgate \
CHROME_EXECUTABLE="$PWD/tools/browser/chrome_launch.sh" \
CHROMEDRIVER=/tmp/feldexa-cd/chromedriver-linux64/chromedriver \
bash tools/gate.sh --log-dir /tmp/feldexa-gate-final
```

`TMPDIR` is a short path outside the worktree because Chrome refuses a
`SingletonSocket` path longer than its 108-byte limit; the worktree path plus
`build/tmpdir` exceeded it and Chrome aborted before the first test. The short
temp path changes no product or repository path. `chromedriver` 156.0.8078.4
matches the Chrome for Testing 156 that `tools/browser/chrome_launch.sh`
selects; it is a local tool and is not committed.

## Per-check results

| # | Check | Result | Numbers |
| --- | --- | --- | --- |
| 1 | dependency resolution | PASS | lockfile unchanged |
| 2 | formatting (width 80) | PASS | **391** files, 0 changed |
| 3 | static analysis | PASS | no issues |
| 4 | shared packages (9) | PASS | **1,903** passed, 6 skipped (adapters_android 21, adapters_simulated 113, application 216, core 612, export 121, ports 138, recognition 411, testkit 154, ui 117) |
| 5 | app unit/widget | PASS | **722/722** |
| 6 | SIMULATED app browser/interaction | PASS | **75 passed / 4 skipped / 0 failed**; the 4 skips are `test/web_fixtures_browser_test.dart` (needs `FIXTURE_RUNTIME`) |
| 7 | SIMULATED browser integration driver | PASS | 4 suites through `flutter drive` + chromedriver: `web_import_test.dart` (6), `web_journey_test.dart` (1), `web_persistence_test.dart` (3), `web_viewport_test.dart` (1, three viewports inside the case) — each “All tests passed.” |
| 8 | repository guards | PASS | **19/19** |
| — | EMULATOR/DEVICE integration tests | NOT RUN | 29 present, deliberately outside this gate |

## What check 7 changed

- `apps/feldexa_app/test_driver/integration_test.dart` exists and forwards the
  `integration_test` results; a suite that never reports fails the check.
- The check starts the loopback fixture server (`127.0.0.1:8765`) around the
  drive runs, because the web import journey fetches the committed fixture
  mirror. It reuses a listener only if it serves the committed catalogue.
- Chromedriver readiness uses a `python3` socket connect instead of `/dev/tcp`
  (this bash build has no `/dev/tcp`; the old probe reported a live
  chromedriver as dead and made check 7 `UNAVAILABLE`).
- `integration_test/web_import_test.dart` and
  `integration_test/web_persistence_test.dart` now use
  `IntegrationTestWidgetsFlutterBinding`; with a plain test binding the driver
  had no result channel. No assertion changed.

## Evidence separation

Static analysis, formatting, host-VM tests and guards produce no runtime class.
The browser and drive checks are `SIMULATED` and are labelled as such. The
29 emulator/device integration tests were not executed here; the T110/T146
emulator runs are separate `EMULATOR` evidence
(`2026-11-28-completion-wave.md`, `2026-11-28-quickstart-validation.md`).

## Reproducibility

Run the command above from the candidate commit with Chrome for Testing 156
(selected by the shim), a matching chromedriver on `CHROMEDRIVER`, and a short
`TMPDIR`. Expected: 19 passed, 0 failed, exit 0. The gate starts and stops its
own fixture server and chromedriver; only the retained log directory persists.
