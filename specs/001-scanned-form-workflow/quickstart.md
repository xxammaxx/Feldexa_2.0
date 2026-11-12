# Quickstart: Validation Guide

**Feature**: `001-scanned-form-workflow` | **Plan**: [plan.md](./plan.md) | **Contracts**: [contracts/](./contracts/)

This guide proves the feature works end to end in the three evidence classes. It contains commands and expected outcomes, not implementation code. Every result must be recorded with its class: `SIMULATED` (Chrome + fixtures), `EMULATOR` (Orca-allocated Android emulator), or `DEVICE` (Samsung Galaxy A54 5G or owner-approved equivalent). Classes are never merged.

---

## 1. Prerequisites

| Tool | Required | Check |
| --- | --- | --- |
| Flutter / Dart | 3.47 / 3.13 | `flutter --version` |
| Android SDK | platform 36, build-tools, `adb` | `sdkmanager --list_installed` |
| JDK | 17 | `java -version` |
| Chrome | 120+ | `google-chrome --version` |
| Orca emulator tooling | exclusive allocation | `orca --help` |
| PDF verification tools | `qpdf`, `pdfinfo`, `pdftoppm`, `pdftotext` (Poppler), `mutool` (MuPDF) | `qpdf --version`, `mutool -v` |
| Image comparison | ImageMagick `compare` (optional) | `compare -version` |

No paid hosted CI is needed. The full gate runs locally:

```bash
flutter pub get
flutter analyze
flutter test
flutter test --platform chrome
./tools/gate.sh          # analyze + unit + widget + browser suites, reports evidence class
```

Expected: zero analyzer issues; all suites pass; `tools/gate.sh` prints `evidence: SIMULATED` for browser tests and does **not** print an Android acceptance claim.

---

## 2. Deterministic fixtures and corpus

```bash
ls tools/corpus/synthetic/            # sf-001.pdf … sf-0NN.pdf
ls tools/corpus/manifest.json         # corpus-1.0.0, sha256, provenance, ground truth
ls apps/feldexa_app/assets/fixtures/  # dev fixtures + expected OCR JSON
```

Rules:
- All fixtures are synthetic or rights-cleared; no real personal data.
- `manifest.json` is committed and hashed; changing a fixture requires a new corpus version.
- Web tests use only `assets/fixtures/`; Android acceptance uses `corpus-1.0.0`.

Expected: at least 20 rights-cleared **real** German authority forms plus synthetic CI fixtures, each with provenance, page geometry, ground-truth fields, and types; checksums match (`tools/corpus/verify.sh`).

---

## 3. Web development journey (`SIMULATED`)

```bash
flutter run -d chrome --dart-define=FELDEXA_ENV=development
```

1. Open the app. Expected: „Meine Dokumente“ with the global `SIMULATED` banner and the German context line.
2. Choose fixture `sf-001` (multi-page synthetic authority form). Expected: pages appear in original order and geometry; every platform-derived result is labeled.
3. Select a suggestion, confirm one, reject one, undo, add a field, move/resize at 50 %, 100 %, 300 %, and fit-width. Expected: overlays stay on the printed area; geometry does not drift.
4. Reclassify a field and check that incompatible content is flagged, not discarded.
5. Fill text, number, date (valid and invalid `31.02.2025`), checkbox, multiline, and signature. Expected: invalid dates are rejected with the German `DATE-002` text; values survive page navigation.
6. Wait 2 s after an edit. Expected: status shows „Gespeichert“ only after the simulated commit; reload the browser and verify values return.
7. Export. Expected: a `SIMULATED` PDF preview with the watermark; the app never claims Android validation.
8. Resize the viewport to 360×640 and 1440×900. Expected: controls, overlays, and pages remain usable without overlap.

Automated equivalents:

```bash
flutter test --platform chrome test/editor_geometry_test.dart
flutter test --platform chrome test/fill_and_validate_test.dart
flutter test integration_test/web_journey_test.dart -d chrome
```

Expected report fields: `evidenceClass: SIMULATED`, `windowSize`, fixture ID, and zero Android claims.

---

## 4. Android emulator setup (`EMULATOR`)

```bash
# Allocate an emulator exclusively for this run through the configured Orca workflow.
# Never share the instance with another run; record the allocation ID in the evidence report.
flutter devices     # note the emulator id, e.g. emulator-5554
flutter run -d emulator-5554 --profile
```

Install a fixture into the device's Downloads so the SAF picker can see it:

```bash
adb push tools/corpus/synthetic/sf-001.pdf /sdcard/Download/
adb push tools/corpus/synthetic/sf-protected.pdf /sdcard/Download/   # synthetic, owner password known to the fixture generator
adb push tools/corpus/synthetic/sf-truncated.pdf /sdcard/Download/
```

Expected: the app asks for no storage permission; the system document picker opens.

---

## 5. Import and source-integrity scenarios

```bash
adb shell sha256sum /sdcard/Download/sf-001.pdf
flutter test integration_test/android_import_test.dart -d emulator-5554
```

Manual checks:

| Scenario | Action | Expected | Requirement |
| --- | --- | --- | --- |
| Single page | Import `sf-001` | All pages, order, orientation, dimensions identical to source | FR-002/FR-003 |
| Five pages | Import the multi-page fixture | All pages present; navigation works before analysis finishes | FR-002/FR-018 |
| Password-protected | Import `sf-protected.pdf` | German `IMP-001` message; no password prompt; **no document entry** | FR-005/FR-006/FR-009 |
| Truncated | Import `sf-truncated.pdf` | German `IMP-002`; no claim of password protection | FR-007/FR-008 |
| Not a PDF | Import a text file renamed `.pdf` | German `IMP-004` | FR-008 |
| Unknown failure | Use the fault-injection fixture | German `IMP-005`; no asserted cause | FR-007 |
| Partially damaged | Import the damaged-page fixture | Readable pages usable; damaged page marked; export warning | FR-010 |
| Source untouched | Compare SHA-256 before/after and modification time | Byte-identical, unchanged mtime | FR-004 |

Expected: after each rejection, „Meine Dokumente“ shows no new entry, and `adb shell run-as de.feldexa.app ls files/feldexa/docs` shows no new directory.

---

## 6. Recognition, review, filling, saving (`EMULATOR`)

```bash
flutter test integration_test/android_journey_test.dart -d emulator-5554
flutter test integration_test/android_autosave_recovery_test.dart -d emulator-5554
```

Expected, in order:

1. Suggestions appear with confidence-based outlines; low-confidence ones show „unsicher“; confirmed fields are visually distinct.
2. A failed page does not remove suggestions on other pages.
3. A conflict shows both candidates and requires per-candidate resolution.
4. Manual add works on any page, including failed ones.
5. Tap-to-fill selects and highlights the field, brings it into a readable view, and does not move it.
6. Typing `ä ö ü ß € „ “` survives entry, navigation, save, reopen, and export.
7. Date `31.02.2025` is rejected with `DATE-002`; reclassification to text accepts free text.
8. Autosave: edit, wait ≥ 2 s, confirm „Gespeichert um …“, force-stop (`adb shell am force-stop de.feldexa.app`), reopen. Expected: values returned.
9. Unsaved risk: edit, force-stop within < 2 s, reopen. Expected: last verified revision returns; the app does not claim the lost edit was saved.
10. Lifecycle: press Home after an edit, reopen. Expected: a verified commit was attempted and status is honest.

---

## 7. Export artifact verification (`EMULATOR` / `DEVICE`)

After exporting the two-page reference form:

```bash
# Pull the artifact from the app's cache (debug build; test-only command)
adb shell run-as de.feldexa.app ls cache/feldexa_exports
adb exec-out run-as de.feldexa.app cat cache/feldexa_exports/<artifact>.pdf > /tmp/feldexa/export.pdf

qpdf --check /tmp/feldexa/export.pdf
pdfinfo /tmp/feldexa/export.pdf
pdftotext -layout /tmp/feldexa/export.pdf - | grep -E 'Müller|Straße|31\.12\.2025'
pdftoppm -r 150 -png /tmp/feldexa/export.pdf /tmp/feldexa/pdfium
mutool draw -o /tmp/feldexa/mupdf-%d.png -r 150 /tmp/feldexa/export.pdf
compare -metric AE /tmp/feldexa/pdfium-1.png /tmp/feldexa/mupdf-1.png null:   # expect 0 or explain AA differences
```

Expected:

| Check | Expected |
| --- | --- |
| `qpdf --check` | no errors |
| Page count/order | equals source |
| Page size/rotation | equals source within 0.01 pt |
| Values | at planned positions; no clipping; German characters intact |
| Checkboxes | exactly the intended boxes marked |
| Signature | present at its field |
| AcroForm | none (`qpdf --json` shows no form fields) |
| Source unchanged | stored source hash unchanged; picked file hash unchanged |
| Two readers | opens, renders, and prints from PDFium and MuPDF |
| Print | Android print preview shows the same pages; printing completes |

Also verify in the app preview before sharing, and via the system share sheet and „In Dateien speichern“. A failed export must leave no `.pdf` in `cache/feldexa_exports` (only `.tmp` cleaned up).

---

## 8. Failure-injection scenarios (`EMULATOR`)

```bash
flutter test integration_test/key_loss_test.dart -d emulator-5554
flutter test integration_test/storage_full_test.dart -d emulator-5554
flutter test integration_test/interrupted_write_test.dart -d emulator-5554
```

| Injection | Expected |
| --- | --- |
| Delete the Keystore alias in the test app | `SAVE-002` on open; affected document not presented as intact; sibling document still opens |
| Quota/`ENOSPC` at stage, promote, head write | `SAVE-001`; no success reported; last head intact; no stored document/template deleted; retry succeeds after space is freed |
| Short write / fsync failure / process kill | `SAVE-003` or verified fallback (`SAVE-004`); never a half-written revision reported as saved |
| Interrupted export | `EXP-002`; no artifact in the final location |
| Unknown/newer schema | `SAVE-005`; data untouched, writes refused |
| Network disabled (airplane mode) | full journey from import to export succeeds; no outbound connections |

Additionally scan for plaintext leaks after failures:

```bash
adb shell run-as de.feldexa.app sh -c 'grep -R -l "%PDF" files cache 2>/dev/null'   # expect no output except an active preview artifact
adb logcat -d | grep -Ei 'Müller|Straße|%PDF|content://'                            # expect no matches
```

---

## 9. Offline and privacy validation (`EMULATOR` / `DEVICE`)

1. Enable airplane mode and disable Wi-Fi.
2. Run the complete journey: import → analyze → review → fill → save → reopen → export → print.
3. Expected: every step succeeds; no network error is shown; no retry loop.
4. Inspect the release manifest: `aapt dump permissions build/app/outputs/flutter-apk/app-release.apk` → no `android.permission.INTERNET`.
5. Verify Recents shows no document thumbnail (`FLAG_SECURE`), and `allowBackup` is false in the merged manifest.
6. Confirm no analytics/crash SDK appears in the dependency graph (`flutter pub deps --style=compact`).

---

## 10. Performance measurement (`DEVICE` only)

```bash
flutter run --profile -d <device-id>
# open the benchmark screen, run corpus form A4 pages ≥ 20 times after one warm-up
adb pull /sdcard/Android/data/de.feldexa.app/files/benchmark/latest.json /tmp/feldexa/
```

Expected report content: device profile (Samsung Galaxy A54 5G, Exynos 1380, 6 GB, Android 14), build mode, corpus version, page index, per-stage timings, median/p95. Acceptance: detection median ≤ 3 s per typical A4 page (SC-004). Emulator timings may be recorded as `EMULATOR` but must not be cited as the 3 s claim.

Other budgets to record: first page ≤ 700 ms, page turn ≤ 400 ms at fit width, autosave commit ≤ 300 ms, two-page export ≤ 5 s, peak memory ≤ 300 MB.

Journey acceptance on the same device: time a two-page reference form from import through review, fill, save, and export for a user familiar with the form; median must be ≤ 10 minutes (SC-016). Observe five first-time users with only the on-screen German guidance; 5 of 5 must complete the journey (SC-018). Record both as `DEVICE` evidence with the form ID and participant count (no personal data).

---

## 11. Recognition evaluation (frozen, `DEVICE`)

```bash
# Freeze before the first scored run; commit the version identifiers.
cat tools/evaluation/metric-definition.v1.md
cat tools/corpus/manifest.json | jq '.corpusVersion'

flutter test integration_test/recognition_eval_test.dart -d <device-id>
# or: dart run tools/evaluation/score.dart --run reports/run-001.json
```

Expected report: separate TP, FP, FN, precision, recall, type accuracy, mean position IoU, and per-form rows; manual-baseline action counts; device/build/corpus identifiers. Acceptance: ≥ 90 % strict-matched relevant fields (SC-001), with no combined headline replacing the separated classes (SC-002). A missed target is reported as a failure, not re-scored.

---

## 12. Accessibility validation (`EMULATOR` + `SIMULATED`)

```bash
flutter test test/accessibility_semantics_test.dart
flutter test --platform chrome test/text_scale_200_test.dart
```

Manual TalkBack walkthrough on the emulator: enable TalkBack, traverse the full journey. Expected: every control is reachable and announced in German; field overlays announce label, type, page, state, and provenance; errors are announced as live regions; 200 % text scale does not hide content; contrast meets 4.5:1 for text and 3:1 for controls; primary touch targets ≥ 48 dp.

---

## 13. Template independence (`EMULATOR`)

1. From a reviewed document, choose „Als Vorlage speichern“. Expected: template contains pages and confirmed fields but zero values and zero signatures (`TPL` checks).
2. Create documents A and B from the template; fill both differently. Expected: both start empty, independent.
3. Edit the template, save a new version. Expected: version number increases; A and B keep the pinned version and still fill/export; a new document C uses the new version.
4. Delete the template. Expected: A, B, and C remain unchanged and usable.

Automated: `flutter test integration_test/template_versions_test.dart -d emulator-5554`.

---

## 14. Evidence report template

Record every run in `specs/001-scanned-form-workflow/reports/<date>-<class>.md` (created by the implementation phase):

```text
Evidence class: SIMULATED | EMULATOR | DEVICE
Adapter versions: <registry descriptors>
App version / build id: <id>
Device or emulator profile: <exact name, RAM, API>
Corpus version: <corpus-1.0.0>
Result: PASS | FAIL | PARTIAL
Checks: <scenario IDs and outcomes>
Limitations: <what this class cannot prove>
Artifacts: <report paths, hashes, screenshots>
```

Rules: never merge classes; never report a green test suite as product completion; failed targets are reported as failures; every performance number cites its conditions.
