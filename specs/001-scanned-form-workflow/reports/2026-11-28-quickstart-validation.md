# Quickstart validation (T146) — 2026-11-28

**Date**: 2026-11-28 · **Branch**: `xxammaxx/t110-t146-drive` · **Base**:
`c4753fc` (current `origin/main` at the start of the slice) · **Role**: build
(worker) · **Evidence classes**: `SIMULATED` (Chrome + fixtures), `EMULATOR`
(`emulator-5554`), `NONE` (host tooling); no `DEVICE` claim.

## Result in one sentence

The executable quickstart scenarios pass on the lanes this host offers: the
Chrome (`SIMULATED`) fill/review/watermark suites are green, the emulator
import journey passes **8/8** including all five German rejection codes, the
failure-injection pair passes **5/5** (executed; no retained log — `PARTIAL`, see §Environment), and the export/print artifact passes the
T105 harness (**7 PASS / 0 FAIL / 6 NOT_RUN**) with Poppler and MuPDF agreeing
within **0.41 %** and **0.47 %** of pixels per page; the `DEVICE`-only
performance and recognition-evaluation sections are honestly `NOT_RUN`.

## Environment

| | |
| --- | --- |
| Host | Linux x86_64 (CachyOS, kernel 7.2.7), Flutter 3.47.7 stable |
| Emulator | `emulator-5554`, AVD `T025_Pixel7_API35_KVM_20261115`, Pixel 7 / API 35 / x86_64, boot completed (release 15, `google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys`) |
| Browser | Chrome for Testing **156.0.8078.4** via `tools/browser/chrome_launch.sh`; `chromedriver` **156.0.8078.4` |
| Fixtures | committed `fixtures-1.1.0`, 8 catalogue fixtures (incl. the `sf-not-a-pdf.pdf` negative) plus `sf-acroform-001.pdf` = 9 PDFs in `assets/fixtures/`; `sf-001.pdf` 5,956 bytes, SHA-256 `22c939cc…a038` |
| Host PDF tools | `qpdf`, `pdfinfo`, `pdftoppm`, `pdftotext`, `mutool`, `compare`, `identify` present (the T110 driver fails closed on a missing tool) |

## Scenario results

### §1–2 Prerequisites and fixtures (`NONE`)

The gate's dependency-resolution, formatting, analysis and guard checks cover
the toolchain (see `2026-11-12-local-gate.md`). The emulator profile, boot
state and serial binding were verified by the T110 driver (`qemu=1`,
`boot_completed=1`, no non-emulator transport addressed); the synthetic
fixtures are parsed and hash-pinned by `SimulatedFixtureCatalog.parse` on both
the host and Chrome lanes.

**Gap found:** `tools/corpus/manifest.json` is not in the tree (only
`manifest.schema.json`, `synthetic/`, `de-ocr/`, `verify.sh`), so
`bash tools/corpus/verify.sh` reports `FAIL: manifest not found` (1 problem).
The quickstart's "at least 20 rights-cleared real German authority forms" is
therefore **NOT_RUN**: the committed corpus is the synthetic
`fixtures-1.1.0` catalogue (8 PDFs plus `sf-not-a-pdf.pdf`) in
`apps/feldexa_app/assets/fixtures`, and the 20-form real corpus stays deferred
per `2026-11-12-budget-traceability.md`. This is an inventory gap, not a test
failure; no fixture or threshold was changed.

### §3 Web development journey (`SIMULATED`)

Run in real Chrome (fixture mirror on `127.0.0.1:8765`):

| Suite | Result | What it asserts |
| --- | --- | --- |
| `test/web_fill_browser_entry_test.dart` | **3/3 PASS** | single-line input rejects line breaks and Enter commits; multiline keeps breaks; checkbox toggles once and never fires when read-only |
| `test/web_review_browser_entry_test.dart` | **2/2 PASS** | confirm/reject/undo report the exact suggestion; review panel does not overflow at **200 %** text scale |
| `test/web_export_watermark_browser_test.dart` (new, T111) | **3/3 PASS** | SIMULATED export descriptor, per-page watermark/footer counts, byte determinism |
| `test/web_journey_browser_entry_test.dart` | 1/1 PASS (documented in `2026-11-28-browser-complete.md`) | display → select → move → resize → review → navigation |
| `test/web_viewport_browser_entry_test.dart` | 3/3 PASS (same report) | 360×640, 768×1024, 1280×800 layout/semantics |

`test/editor_geometry_test.dart` is a `@TestOn('vm')` host suite, so it is not
part of the Chrome count; its host-VM run is covered by the gate's app check.
The manual browser steps (status „Gespeichert“, reload recovery, export
preview) are modelled by the persistence and export suites above; no manual
click-through claim is made here.

### §4 Android emulator setup (`EMULATOR`)

PASS: exactly one emulator transport (`emulator-5554`), QEMU, API 35, boot
completed. Nine fixture files were pushed to `/data/local/tmp/t046-fixtures`
(9 PDFs in `assets/fixtures/`: the 8 catalogue fixtures incl. the not-a-PDF negative, plus `sf-acroform-001.pdf`), mode 755/644.

### §5 Import and source integrity (`EMULATOR`)

`flutter test integration_test/android_import_test.dart -d emulator-5554` →
**All tests passed, 8/8** (executed; the later emulator loss left no retained log, so this sub-result is `PARTIAL` until a rerun retains one):

| Assertion | Code |
| --- | --- |
| single-page valid fixture imports with catalog geometry | FR-002/FR-003 |
| five-page fixture imports all pages in order | FR-002/FR-018 |
| mixed-geometry fixture preserves rotations and display sizes | FR-003 |
| protected fixture rejected with exact `IMP-001` text | FR-005/FR-006/FR-009 |
| truncated fixture rejected with exact `IMP-002` text | FR-007/FR-008 |
| non-PDF fixture rejected with exact `IMP-004` text | FR-008 |
| unknown preflight cause rejected with exact `IMP-005` text | FR-007 |
| partially damaged fixture imports with `IMP-006` and a usable page | FR-010 |

The suite runs the native import service through the debug-only
`de.feldexa/test.import` seam and reads the committed document back from the
protected store; it deletes only the documents it creates.

### §6 Recognition, review, filling, saving (`EMULATOR`)

The T110 emulator run (`integration_test/print_test.dart`) exercises the
production journey up to export: import → both pages analysed
(`PAGES=2`, 59 suggestions, 0 uncertain) → `Familienname` confirmed →
`Müller` saved (6 runes) → export verified (`PAGES=2`, all checks passed) →
print preview. Autosave/force-stop recovery (`§6.8–10`) was **not rerun** in
this slice; the committed evidence is `2026-11-27-t092-t101-lifecycle.md`
(autosave/recovery and unsaved-risk on the real store). This section is
therefore **PARTIAL**: journey up to export PASS on the new run, lifecycle
sub-steps cited from the prior device run.

### §7 Export artifact verification (`EMULATOR`)

The T110 driver picked the exported artifact out of the app data
(`12,029` bytes, SHA-256 `05e37ee7…0379`) and ran
`tools/pdf_verify/verify_artifact.py` against the committed two-page
`sf-001.pdf`:

| Harness row | Result |
| --- | --- |
| structural validity (`qpdf --check`) | **PASS** |
| page count and order | **PASS** (2 pages; order proxy equal) |
| page geometry | **PASS** (sizes/rotations equal within 0.01 pt) |
| no interactive controls (`/AcroForm`, `/Widget`) | **PASS** |
| text content (incl. German glyphs) | **PASS** |
| printability | **PASS** |
| source integrity | **PASS** |
| appearance, clipping, checkbox states, signatures, placement, artifact isolation | **NOT_RUN** (6 rows; supplied-value checks belong to the T109 run) |

Summary: **7 PASS / 0 FAIL / 6 NOT_RUN / 0 UNAVAILABLE**. Two independent
engines were rendered at 300 dpi: Poppler vs MuPDF differ in **35,545 /
8,703,348 px (0.4084 %)** on page 1 and **41,261 / 8,703,348 px (0.4741 %)**
on page 2, inside the 5 % fuzz / 2 % max-difference tolerance. The Android
print preview was observed as a real print-spooler activity
(`print_activity_present=1`); the captured 15,580-byte screenshot is the known
uniform black frame (SHA `c35bacdb…f514`) taken while `PrintActivity` reported
`INITIALIZING`, so the pixel-level preview is `NOT_PROVEN` (T110 stays
OPEN/PARTIAL); closing the preview deleted the artifact (`EXP-002`).

### §8 Failure injection (`EMULATOR` device run, `SIMULATED` seams)

`flutter test integration_test/storage_full_test.dart
integration_test/key_loss_test.dart -d emulator-5554` → **All tests passed,
5/5**:

| Case | Result |
| --- | --- |
| blocked save reports `SAVE-001`, never success | PASS (1/1) |
| exhaustion leaves staged source and aggregate objects untouched | PASS (1/1) |
| saved document opens without app password/biometrics | PASS (EMULATOR, 1/1) |
| key loss isolated to one aggregate; other documents readable | PASS (SIMULATED, 1/1) |
| global key-provider outage → `SAVE-008`, ciphertext preserved | PASS (SIMULATED, 1/1) |

Interrupted write/export injection was **not rerun**; the committed device
evidence is `2026-11-27-t108-t111-us7-tests.md` (real IO-fault `EXP-002`,
preflight `EXP-001`) and `2026-11-27-t092-t101-lifecycle.md`.

### §9 Offline and privacy (`EMULATOR` / `DEVICE`)

Not rerun in this slice. Committed evidence: T138 observed **0** non-loopback
outbound sockets over 89 successful reads with an app-UID loopback positive
control, and the 139-check release-manifest audit
(`2026-11-27-t145-t134-t138.md`). No `DEVICE` release-APK permission claim is
made here.

### §10 Performance (`DEVICE` only) — `NOT_RUN`

No Samsung Galaxy A54 5G / owner-approved device was available. Emulator
timings are not cited as the SC-004 3 s claim; the section stays `NOT_RUN`.
Budget traceability is recorded in `2026-11-12-budget-traceability.md`.

### §11 Recognition evaluation (`DEVICE`, frozen) — `NOT_RUN`

No `DEVICE` run and no scored corpus run in this slice; no threshold changed.

### §12 Accessibility (`EMULATOR` + `SIMULATED`)

The Chrome review suite asserts no overflow at 200 % text scale (2/2 above).
The numeric 200 % audit (contrast, 48 dp targets, semantics) is the committed
T134 `EMULATOR` result: start 7 text runs min **6.441:1**, editor 4 runs min
**8.882:1**, 0 contrast/target/semantics failures
(`2026-11-27-t145-t134-t138.md`). The TalkBack walkthrough was not rerun, so
no manual screen-reader claim is added.

### §13 Template independence (`EMULATOR`)

Not rerun in this slice. Committed evidence:
`2026-11-27-t114-t121-us6-templates.md` (immutable versions, per-document
independence, template deletion).

## Limitations

- `DEVICE` sections (§10, §11) are `NOT_RUN`; no A54 profile, no scored
  corpus run, no 3 s detection claim.
- §6/§8/§9/§13 cite prior committed runs instead of repeating every device
  journey; each citation is named and is not re-labelled as new evidence.
- The T110 harness leaves six value/appearance rows `NOT_RUN` because the
  print run does not supply expected values; those rows were covered for the
  T109 artifact earlier and are not claimed here.
- The print preview is proven by the system print-spooler activity and its
  job state, not by a completed physical print job and not by the captured
  (uniform black) screenshot; the pixel-level preview is `NOT_PROVEN`.

## Artifacts

T110 receipts, the named black preview frame and the failed-recapture log
(`rerun-2026-11-28-emulator-5556.log`) live in
`reports/artifacts/2026-11-27-t110-print/`; the picked-up PDF and engine
renders were deleted by the driver after verification. No device data or host
paths are stored (driver privacy check PASS).

## Reproducibility

1. Start the emulator `T025_Pixel7_API35_KVM_20261115` on `emulator-5554`.
2. `python3 tools/android/t108_t110_drive.py print` (re-executes under
   `compute_slot.py --wait --resource build --resource emulator`).
3. Stage fixtures, then
   `flutter test integration_test/android_import_test.dart -d emulator-5554`.
4. `flutter test integration_test/storage_full_test.dart
   integration_test/key_loss_test.dart -d emulator-5554`.
5. Chrome: start `dart run tools/corpus/synthetic/serve_web_fixtures.dart
   --root apps/feldexa_app/web --port 8765`, then
   `CHROME_EXECUTABLE=$PWD/tools/browser/chrome_launch.sh flutter test
   --no-pub --platform chrome test/web_fill_browser_entry_test.dart
   test/web_review_browser_entry_test.dart
   test/web_export_watermark_browser_test.dart`.
