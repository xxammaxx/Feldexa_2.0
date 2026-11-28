# Completion wave — T110 print, T146 quickstart, T145 drive layer, T111 browser

**Date**: 2026-11-28 · **Branch**: `xxammaxx/t110-t146-drive` · **Base**:
`c4753fc` (current `origin/main` at the start of the slice) · **Role**: build
(worker) · **Evidence classes**: `EMULATOR` (`emulator-5554`), `SIMULATED`
(Chrome + fixtures), `NONE` (host, gate). No `DEVICE` claim.

## Result in one sentence

The completion wave closes the three open lanes: the T110 print run passes on
`emulator-5554` (real print-spooler preview, artifact picked up at 12,029
bytes, T105 harness 7 PASS / 0 FAIL / 6 NOT_RUN, Poppler vs MuPDF 0.41 % /
0.47 % per page), the T146 quickstart scenarios pass wherever this host offers
the lane (Chrome fill/review/watermark suites, emulator import 8/8,
failure-injection 5/5) with the corpus-inventory and `DEVICE` gaps recorded,
the T145 drive layer is built and all four `integration_test/web_*` suites run
through `flutter drive` in Chrome, and the T111 watermark/determinism
assertions now execute in Chrome (**3/3**). The full gate completes with
**19 passed / 0 failed / 0 unavailable / 0 absent**.

## Environment and admission

| | |
| --- | --- |
| Host | Linux x86_64 (CachyOS), Flutter 3.47.7 stable, Dart 3.13 |
| Emulator | `emulator-5554`, AVD `T025_Pixel7_API35_KVM_20261115`, Pixel 7 / API 35 / x86_64 / 4 GB, boot completed; started for this slice and stopped after the device runs |
| Browser | Chrome for Testing **156.0.8078.4** via `tools/browser/chrome_launch.sh`; `chromedriver` **156.0.8078.4** (Chrome-for-Testing `linux64` build, local, not committed) |
| Fixtures | committed `fixtures-1.1.0`, 8 PDFs + `sf-not-a-pdf.pdf`; `sf-001.pdf` 5,956 bytes, SHA-256 `22c939cc…a038` |
| Host temp | gate ran with `TMPDIR=/home/xxammaxx/fdgate` because the worktree path exceeds Chrome's 108-byte Unix-socket limit under `$PWD/build/tmpdir`; the short temp path does not change any product path |

## T110 — Android print preview and two-engine printability (SC-005; CHK019)

`python3 tools/android/t108_t110_drive.py print` re-executes itself under
`compute_slot.py --wait --resource build --resource emulator` and passed:

| Step | Evidence |
| --- | --- |
| fixture | staged `sf-001.pdf`, 5,956 bytes, SHA-256 match on host and device |
| journey | import → both pages analysed (`T110_ANALYSIS_READY:PAGES=2`) → `Familienname` confirmed → `Müller` saved (6 runes) → export verified (`T110_EXPORT_VERIFIED:PAGES=2:ALL_CHECKS_PASSED=1`) |
| print UI | `T110_PRINT_REQUESTED`, print-spooler activity found (`print_activity_present=1`), screenshot 15,580 bytes (`c35bacdb…f514`), preview closed with BACK, `T110_PRINT_PREVIEW_OBSERVED`, `T110_PRINT_COMPLETED:DELIVERY_FAILED=0` |
| artifact | `12,029` bytes, SHA-256 `05e37ee7…0379`, picked up through `run-as` while the preview was open |
| harness | **7 PASS / 0 FAIL / 6 NOT_RUN / 0 UNAVAILABLE** (`qpdf`, page count/order, geometry, no interactive controls, text, printability, source integrity) |
| two engines | Poppler vs MuPDF at 300 dpi: page 1 `35,545 / 8,703,348 px = 0.4084 %`, page 2 `41,261 / 8,703,348 px = 0.4741 %` (tolerance 5 % fuzz / 2 % max) |
| cleanup | `T110_ARTIFACT_DELETED_AFTER_PREVIEW_CLOSE:CODE=EXP-002`, `T110_CLEANUP_DONE`, privacy check PASS; `flutter test` “All tests passed!” (1/1) |

The six `NOT_RUN` harness rows are appearance/clipping/checkbox/signature/
placement/artifact-isolation checks that need supplied expected values; they
belong to the T109 artifact run and are not claimed here. The print claim is
the system print preview and the verified artifact, not a completed physical
print job.

The wrapper process kept the Gradle daemon’s inherited stdout pipe open after
the driver printed `DRIVER: PASS mode=print …`; it was stopped after the PASS
line and the complete evidence set, which is why the shell job reports signal
137. No test step was interrupted.

## T146 — quickstart validation

Full scenario table with numbers and evidence classes:
`2026-11-28-quickstart-validation.md`.

| Quickstart § | Result |
| --- | --- |
| §1–2 tools/fixtures | PASS for toolchain and synthetic fixtures; `tools/corpus/manifest.json` absent, so the 20-form real corpus and `tools/corpus/verify.sh` stay `NOT_RUN` |
| §3 web journey (`SIMULATED`) | Chrome: fill **3/3**, review **2/2**, watermark/determinism **3/3** in this slice; journey 1/1 and viewport 3/3 cited from `2026-11-28-browser-complete.md` |
| §4 emulator setup | PASS — one transport, QEMU, API 35, boot completed; nine fixture files staged |
| §5 import (`EMULATOR`) | **8/8 PASS** — single/five-page/mixed geometry plus `IMP-001`, `IMP-002`, `IMP-004`, `IMP-005`, `IMP-006` |
| §6 journey up to export (`EMULATOR`) | PASS via T110; autosave/force-stop sub-steps cited from T092–T101 and not rerun (PARTIAL section) |
| §7 export artifact | PASS — harness 7/0/6 and two-engine comparison above |
| §8 failure injection | **5/5 PASS** — `SAVE-001` blocked save and untouched objects (2), passwordless open (1, EMULATOR), key-loss isolation and `SAVE-008` (2, SIMULATED seams) |
| §9 offline/privacy | not rerun; cited T138 zero-outbound observation and 139-check manifest audit |
| §10 performance (`DEVICE`) | `NOT_RUN` — no A54-class device; no emulator timing cited as SC-004 |
| §11 recognition evaluation (`DEVICE`) | `NOT_RUN` — no scored corpus run, no threshold change |
| §12 accessibility | Chrome 200 % review overflow PASS; numeric 200 % audit cited from T134 (`EMULATOR`) |
| §13 templates | not rerun; cited from T114–T121 |

## T145 — drive layer and complete gate

- `apps/feldexa_app/test_driver/integration_test.dart` added (standard
  `integrationDriver()`; a suite that never reports fails instead of silently
  passing).
- `tools/gate.sh` check 7 now starts/stops the loopback fixture server around
  the drive runs (the web import journey fetches the committed mirror) and uses
  a `python3` TCP probe for chromedriver readiness instead of `/dev/tcp`, which
  this bash build does not provide — the previous probe made a running
  chromedriver look dead.
- Two `integration_test/web_*` suites used a plain test binding, which leaves
  `flutter drive` without a verdict; they now call
  `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` (no assertion
  changed).
- `chromedriver` 156.0.8078.4 matches the Chrome for Testing 156 the lane
  already uses. It is a local tool, not committed; the gate finds it through
  `CHROMEDRIVER`.

Individual drive runs before the final gate: `web_viewport` PASS,
`web_import` PASS, `web_persistence` PASS. The final gate runs all four.

## T111 — SIMULATED watermark and determinism in Chrome

`test/web_export_browser_entry_test.dart` stays `@TestOn('vm')` (it reads and
writes real PDF files through `dart:io`). Its watermark and determinism
assertions were copied to `test/web_export_watermark_browser_test.dart`
(`@TestOn('browser')`), which loads the same committed catalogue through the
loopback fixture mirror instead of the filesystem:

- descriptor is a SIMULATED export adapter;
- every preview page carries `SIMULATED`, the German footer words, `42 Tf`
  watermark, `Quellseite`, two A4 page objects, no `/AcroForm`, no `/Widget`;
- two exports are byte-identical (SHA-256 equality and `orderedEquals`).

Result in real Chrome: **3/3 PASS, 0 failed** (≈2 s). The browser row is now
`SIMULATED` evidence; the VM suite remains the host entry and still makes no
Android claim.

## Gate

Final acceptance gate (no escape hatches), retained under
`/tmp/feldexa-gate-final`:

```
TMPDIR=/home/xxammaxx/fdgate \
CHROME_EXECUTABLE="$PWD/tools/browser/chrome_launch.sh" \
CHROMEDRIVER=/tmp/feldexa-cd/chromedriver-linux64/chromedriver \
bash tools/gate.sh --log-dir /tmp/feldexa-gate-final
```

Per-check numbers are in `2026-11-12-local-gate.md`; the summary line is
`Checks passed: 19; failed: 0; unavailable: 0; absent planned layers: 0`,
exit **0** (`GATE PASSED`).

## Limitations

- `DEVICE` work (A54 performance, five first-time users, scored recognition
  evaluation) stays `NOT_RUN`; no threshold changed.
- The T110 harness value/appearance rows stay `NOT_RUN`; the print proof is a
  system print preview plus the verified artifact, not a physical print job.
- The real 20-form corpus is absent (`tools/corpus/manifest.json` missing);
  only the synthetic catalogue is validated.
- Gate browser lanes are `SIMULATED`; the emulator/device integration tests are
  never executed by the gate.
- The drive layer runs each `integration_test/web_*` suite through a real
  Chrome with chromedriver 156; it makes no claim about other Chrome versions.

## Artifacts

Committed: the drive entrypoint, the gate changes, the two binding changes,
the T111 browser entry, T110 receipts (`print-preview-proof.txt`,
`print-preview-dumpsys-print.txt`, `print-preview-activities.txt`,
`print-preview.png`, `harness-report.json`, `harness-console.txt`,
`engine-pixel-comparison.txt`, `integration.log`, `markers.txt`, `device.txt`,
`git.txt`, `readme-note.txt`), and the three reports. The picked-up PDF and
engine renders were deleted by the driver after verification. Gate logs stay in
`/tmp/feldexa-gate-final`.

## Reproducibility

1. `flutter pub get` at the base commit.
2. Gate command above with a short `TMPDIR` (Chrome socket-path limit) and
   `chromedriver` 156 on `CHROMEDRIVER`.
3. T110: emulator boot → `python3 tools/android/t108_t110_drive.py print`.
4. T146 device runs: stage `/data/local/tmp/t046-fixtures`, then the import and
   failure-injection commands in the quickstart report.
5. T111: fixture server on `127.0.0.1:8765`, then
   `flutter test --no-pub --platform chrome
   test/web_export_watermark_browser_test.dart`.

## External attestation

None: local candidate branch, no push, PR, or attestation ref. Commit SHAs are
recorded by the integration owner.
