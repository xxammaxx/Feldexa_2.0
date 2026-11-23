# T086C productive FLD-001 overflow warning — host evidence and Pixel 7 API 35 emulator PASS

- **Task / issue**: T086C / <https://github.com/xxammaxx/Feldexa_2.0/issues/281>
- **Feature**: `specs/001-scanned-form-workflow` US4
- **Date**: 2026-11-22 (local)
- **Branch**: `xxammaxx/t086c` (created from `origin/main` `a84dec7ce5c17630e1b65253fb5936a31dac3a96`, no rebase)
- **Host evidence class**: `NONE` (host-VM analyze, format, unit/widget tests)
- **Emulator evidence class**: `EMULATOR` — **`PASS`**
- **Overall result**: `PASS` for this task's own scope. T086 (two-page US4
  acceptance) and T086D remain open and are not claimed; the T086C row remained
  `[ ]` at evidence time; the integration docs mark it `[x]` after review/merge.

## 0. Machine-first handoff

```json
{
  "task": "T086C",
  "issue": 281,
  "branch": "xxammaxx/t086c",
  "base_commit": "a84dec7ce5c17630e1b65253fb5936a31dac3a96",
  "code_commit": "68038580ba4578741190f675fdac4f87a8ef469c",
  "code_tree": "4d57d91dfeb4ff7e575ba17d0c7d101db87d050a",
  "tooling_commit": "95000461f27e2d344750c180022d78f9492828f0",
  "journey_head": "c7a3ca73eb5a597cf3803b028e22467b367f3e34",
  "journey_tree": "662916860ece2100133f84aacc1d56dc3b9772bb",
  "evidence_bundle": "specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t086c-overflow",
  "host_evidence_class": "NONE",
  "emulator_evidence_class": "EMULATOR",
  "overall_result": "PASS",
  "command_binding": {
    "requested": "command:speckit.implement",
    "file": ".opencode/commands/speckit.implement.md",
    "sha256": "e036ce63702db93e656e1c91ee6c02a8dc3d4a4f8624f8ba4adc69027fe68983",
    "mode": "artifact_adapted",
    "env": {
      "SPECIFY_FEATURE_DIRECTORY": "specs/001-scanned-form-workflow",
      "SPECIFY_FEATURE_NO_PERSIST": "1"
    },
    "prerequisites": ".specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks -> exit 0, AVAILABLE_DOCS research.md, data-model.md, contracts/, quickstart.md, tasks.md",
    "extensions": ".specify/extensions.yml read: installed=[github], settings.auto_execute_hooks=true, hooks={}",
    "checklists": "specs/001-scanned-form-workflow/checklists/* read-only (precision-testability-assessment.md, precision-testability.md, requirements.md)",
    "scope_argument": "T086C only; T086, T086D, T263, T264 and every other task untouched"
  },
  "host_counts": {
    "field_text_fit_unit": 16,
    "field_overflow_sheet_widget": 11,
    "editor_composition": 21,
    "focused_total": 48,
    "app_suite": 580,
    "application_suite": 187
  },
  "host_gates": {
    "format": "105 files, 0 changed (lib, test, integration_test)",
    "analyze": "exit 0, no issues",
    "app_suite": "580/580 passed",
    "application_suite": "187/187 passed",
    "report_validator": "NOT_RUN (not applicable; see §6)"
  },
  "emulator": {
    "driver": "tools/android/t086c_drive_overflow.sh",
    "device_gate": "tools/android/t086c_device_gate.py",
    "test": "integration_test/android_overflow_warning_test.dart",
    "driver_result": "PASS",
    "run_status": "result=PASS, flutter_test_exit=0",
    "serial": "emulator-5554",
    "avd": "T025_Pixel7_API35_KVM_20261115",
    "android_release": "15",
    "sdk": 35,
    "abi": "x86_64",
    "wm_size": "1080x2400",
    "wm_density": 420,
    "qemu": 1,
    "orca_worktree_sessions": 0,
    "orca_global_sessions": 0,
    "orca_device_is_available": true,
    "physical_device_touched": false,
    "screenshots": 3,
    "distinct_screenshot_hashes": 3,
    "apk_bytes": 173480454,
    "apk_sha256": "8f3202a94f6a6300cb4b07da108008263f4cf1886ffa4de0747d11d006e962cb",
    "fixture_sha256": "22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038",
    "derived_damaged_fixture_sha256": "57c1ade1ab2c00375ac61703db3d4ce5d27b996ea067647aba585866dc6ec221",
    "privacy_checks": "PASS (2/2)",
    "cleanup_marker": "T086C_CLEANUP_DONE",
    "compute_permit": "python3 tools/.../compute_slot.py --wait -- tools/android/t086c_drive_overflow.sh -> ACQUIRED then SETTLED, exit 0"
  }
}
```

## 1. What changed

### 1.1 Production paths (3 files)

| Path | Change |
| --- | --- |
| `apps/feldexa_app/lib/features/fill/field_text_fit.dart` | **New.** The FLD-001 decision: `fieldTextOverflows(...)` implements `contracts/export-plan.md` §2.2/§3.1 (1.5 pt padding, `fontSizePt = clamp(0.6 × rect.height, 7.0, 12.0)`, `lineHeightPt = 1.2 × fontSizePt`, baseline `1.5 + 0.8 × fontSizePt`, single line for text/number/date, explicit `\n` plus greedy word wrap for multiline, an unbreakable long word overflows, `lines × lineHeight > availableHeight` overflows). `FieldTextMetrics` parses the bundled `assets/fonts/metrics.json` advance table and `initializeFieldTextMeasure()` caches it; `fieldTextMeasure` is the synchronous seam. |
| `apps/feldexa_app/lib/features/editor/field_value_sheet.dart` | Sets the existing `FieldValue.overflow` flag from the measurement for text/multiline/number (stored German form) and date (`dd.MM.yyyy`); checkbox and signature stay `false`. An overflowing commit keeps the sheet open so the existing `FieldOverflowWarning` is read immediately after the commit, a second save of the same draft writes no duplicate revision, and shortening the draft clears the warning. |
| `apps/feldexa_app/lib/main.dart` | `await initializeFieldTextMeasure()` before `runApp`, so the commit path measures synchronously with the export metrics. A missing table degrades to "no warning" and never blocks a save. |

No recognition, ARB, `pubspec.yaml`, core model, port, application command, or
Gradle change. The full value is never truncated: the measurement only sets a
flag on the value that is stored.

### 1.2 Why the bundled metrics table and not a widget-level text layout

`plan.md` decision 6 (D-11) requires one text layout engine: the bundled Noto
Sans plus the generated glyph-advance table, so Dart layout and PDF drawing use
identical metrics. `assets/fonts/metrics.json` is exactly that table (T007
generated it from the pinned `NotoSans-Regular.ttf` bytes and the pubspec
already declares it as a bundle asset). Measuring with it is integer font-unit
arithmetic, so the host tests assert exact widths and the device decision equals
the host decision; a `TextPainter` measurement would have used the test font on
a host and the real font on a device.

### 1.3 Test paths (5 new files, 4 updated)

- `apps/feldexa_app/test/field_text_fit_test.dart` (16 tests): the font-size,
  line-height, baseline and padding rules; single-line fit/overflow including
  the exact available width; multiline explicit newlines, greedy wrap, an
  unbreakable long word, and an empty paragraph as a rendered line; checkbox
  and signature never overflow; empty/whitespace text never overflows; boxes
  with no inner area or a baseline taller than the box overflow; the injected
  measure is the single metrics seam. All expectations are exact arithmetic over
  a synthetic 0.5 em/rune measure.
- `apps/feldexa_app/test/field_overflow_sheet_test.dart` (11 tests): a
  too-long entry sets `overflow`, shows the warning immediately, keeps the sheet
  open and the complete value; a fitting text closes without a warning; a stored
  overflowing value reopens with the warning and the full text; a repeated save
  adds no commit; shortening clears the warning; multiline line counting, a
  long number in its stored German form, a long date, and a checkbox each behave
  per the same rule.
- `apps/feldexa_app/test/flutter_test_config.dart` (new bootstrap): every app
  test loads the same metrics table the production startup loads, so no test
  silently runs with the measurement disabled.
- `apps/feldexa_app/test/editor_composition_test.dart` (+1 test): the
  overflowing value is persisted with the flag through the real editor/save
  path, and closing and reopening the stored field shows the warning and the
  same complete text with no second revision.
- `apps/feldexa_app/test/field_controls_test.dart` and
  `field_value_sheet_test.dart`: three existing tests entered texts that
  genuinely do not fit their 100 × 20 pt test field (251 runes; five lines; two
  lines). They now assert the truthful behaviour — `overflow == true`, the
  FLD-001 warning visible, the sheet staying open, and the explicit close —
  while keeping every original text-preservation assertion unchanged.
- `apps/feldexa_app/integration_test/android_overflow_warning_test.dart` and
  `tools/android/t086c_drive_overflow.sh` + `tools/android/t086c_device_gate.py`:
  the real journey and its host driver.

### 1.4 Tooling

`9500046` adds `/.kotlin` to `apps/feldexa_app/android/.gitignore`: the Kotlin
Gradle plugin writes that session directory while building the debug APK, and it
must never be committed.

## 2. Host gates

```text
format (lib, test, integration_test)  105 files, 0 changed
flutter analyze                       No issues found! (exit 0)
app suite                             580/580 passed
application suite (unmodified)        187/187 passed
focused new/updated files             48/48 (16 + 11 + 21)
```

Every heavy command ran under
`<orca-maintainer-skill>/scripts/compute_slot.py --wait -- …` (absolute host paths redacted).

## 3. Emulator journey

Driver `tools/android/t086c_drive_overflow.sh` on the Orca-managed Pixel 7 API 35
emulator `emulator-5554` (AVD `T025_Pixel7_API35_KVM_20261115`, 1080 × 2400 at
420 dpi, `qemu=1`). Journey:

1. import the deterministic T061 damaged-page-2 variant of the committed
   `sf-001.pdf` (page 1 stays the real, readable page);
2. first analysis reaches `analysis-ready` with 28 suggestions, identical to the
   US2 baseline — no recognition change;
3. confirm one real **machine** text suggestion through the production review
   surface, so the field under test carries a real recognised rectangle
   (2.5 × 4.25 pt);
4. open its value sheet on the real page and enter a 215-rune German text, which
   cannot be drawn in that rectangle under the export rules;
5. save: one verified revision is committed, the FLD-001 warning is visible
   immediately, the sheet stays on the field, and the complete text is still in
   the control;
6. close the sheet, leave the editor, reopen the stored document from the start
   list, tap the same field: the persisted warning and the same 215-rune text
   are shown, and the value read back from the real encrypted store carries
   `overflow = true` with no truncation.

Authoritative marker sequence (`markers-integration.txt`):

```text
T086C_FIXTURE_READY:BYTES=5956:MATCH=1
T086C_DAMAGED_FIXTURE_READY:BYTES=5956:MATCH=1
T086C_START_LIST_READY
T086C_IMPORT_ARMED
T086C_EDITOR_READY
T086C_ANALYSIS_READY:STATE=analysis-ready:PAGES=2:SUGGESTIONS=28
T086C_MACHINE_FIELD_CONFIRMED:OVERLAY=1:W_MILLI=2500:H_MILLI=4250
T086C_SHEET_OPEN:OVERFLOW_BEFORE=0
T086C_OVERFLOW_WARNING_VISIBLE:OVERFLOW=1:SHEET_OPEN=1:RUNES=215:ENTERED_RUNES=215:W_MILLI=2500:H_MILLI=4250
T086C_VALUE_RETAINED:IN_CONTROL=1:RUNES=215
T086C_SCREENSHOT_OVERFLOW_WARNING
T086C_SHEET_CLOSED
T086C_SCREENSHOT_OVERFLOW_CLOSED
T086C_OVERFLOW_REOPENED:OK:WARNING=1:RUNES=215:OVERFLOW=1
T086C_SCREENSHOT_OVERFLOW_REOPENED
T086C_OVERFLOW_PERSISTED:STORED=1:RUNES=215:OVERFLOW=1:TRUNCATED=0
T086C_CLEANUP_DONE
```

`RUNES=215` equals `ENTERED_RUNES=215`, and the terminal marker states
`TRUNCATED=0`: the entered value is stored and reopened in full, with no
truncation, ellipsis, or shrink (FR-038).

Screenshots (3, all distinct, `screenshot-hashes.txt`): `overflow-warning`
(209058 bytes, `a425fd89…`), `overflow-closed` (257624 bytes, `865d704b…`),
`overflow-reopened` (252542 bytes, `b5ba1840…`).

Artifacts: APK `8f3202a9…` (173480454 bytes), fixture `22c939cc…`, derived
damaged fixture `57c1ade1…`, device identity, device binding, Orca device and
session inventories, marker-filtered logcat, privacy checks (2/2 PASS) and
`T086C_CLEANUP_DONE`.

Evidence hygiene: the raw driver output keeps the trailing padding space of
`wm size`/`wm density` and Flutter's Gradle progress line. Those trailing
spaces were stripped in `device-identity.txt` and `integration-android-t086c.log`
so `git diff --check` is clean; every value and every other byte is unchanged,
and no recorded hash covers either file (the APK, fixture and screenshot digests
are untouched).

### 3.1 Device binding and the compute permit

Orca reports `emulator-5554` as a booted `emulator` device with
`isAvailable: true` and **no** Orca emulator session for this or any other
worktree (`worktree_orca_sessions=0`, `global_orca_sessions=0`, see
`device-binding.txt` and the two session inventories). The journey therefore
bound the device by explicit serial and `tools/android/t086c_device_gate.py`
proved: exactly one attached adb device equals the serial, the Orca inventory
names the expected AVD at API 35, `detail=emulator`, `isAvailable=true`, and no
other worktree holds a session referencing it. The physical device
(`adb-RFCW80SMY4J-lidiWY`) was never addressed.

An earlier attempt was stopped because it ran outside the shared compute permit;
the accepted run is the one that printed `ACQUIRED` … `SETTLED` and exited 0, and
only its evidence is committed.

### 3.2 Marker caveats

- The `T086C_*` markers are printed by the integration-test harness, not by the
  app process, so `logcat-t086c-markers.log` contains no `T086C_` marker; the
  authoritative sequence is `markers-integration.txt`, extracted from
  `integration-android-t086c.log`.
- Markers carry phase names, geometry in milli-points, and rune counts only. No
  label, OCR text, title, path, entered value, or digest is printed; the driver's
  privacy check asserts that neither the entered text nor the fixture path
  appears in the integration log.
- The FLD-001 decision is a pure function of the field rectangle and the stored
  text under the export metrics. The journey proves it end to end on the device;
  the exact wrap arithmetic is covered by the host unit tests.

**Evidence-strength caveat.** The confirmed field is 2.5 × 4.25 pt. Its height alone makes the entered text overflow, so this device run proves wiring, warning visibility, full-value retention, persistence and reopen. The width boundary is proven by the host tests using the bundled Noto Sans metrics; the device run is not a width-arithmetic acceptance.

**Residual.** After shortening a draft below the limit, the warning for the last committed overflow remains visible until the next save; it describes the stored value.

## 4. Requirement mapping

| Requirement (tasks.md T086C) | Evidence |
| --- | --- |
| Measure entered text against the field display region in the editor/value-sheet commit path | `fieldTextOverflows` in `field_text_fit.dart`, called from `FieldValueSheet._buildValue`; unit tests 16/16; emulator `OVERFLOW_WARNING_VISIBLE` on a real 2.5 × 4.25 pt recognised field |
| Use existing layout/geometry components, no new field model, no new architecture | reuses `core.Rect`, the existing `FieldValue.overflow` flag, the existing `FieldOverflowWarning`, the existing `setFieldValue`/`saveRevision` path, the bundled `metrics.json` and the export-plan §2.2/§3.1 rules; no model, port, command, ARB or pubspec change |
| Set the existing value `overflow` flag | `TextValue/MultilineValue/NumberValue/DateValue(overflow:)`; `OVERFLOW_PERSISTED:STORED=1:OVERFLOW=1` |
| Show the existing `FieldOverflowWarning` when the value overflows | widget tests (`fieldOverflowWarningKey`), editor composition test, emulator `OVERFLOW_WARNING_VISIBLE` + `screenshot overflow-warning` |
| No silent truncation; the full value is stored and reopens | `RUNES=215` = `ENTERED_RUNES=215`, `TRUNCATED=0`, control text equality, store read-back equality; `overflow-reopened` screenshot |
| Persist the flag with the value | `OVERFLOW_REOPENED:OK:WARNING=1:OVERFLOW=1` after leaving and reopening the stored document |
| Host tests for warning, retention, reopening, no truncation | §1.3 (16 + 11 + 1 + adapted control tests) |
| Real emulator evidence on `emulator-5554` | §3 |

## 5. Residual risks and `NOT_RUN`

- **`DEVICE` acceptance, TalkBack traversal of the warning, stylus/IME variants,
  golden/visual comparison, and any performance claim are `NOT_RUN`.**
- **Measurement model.** The decision uses the export layout rules and the
  bundled metrics, not the on-screen widget metrics: a field can look "full" at
  a high zoom while still fitting the page. That is intentional (FLD-001 is about
  what the export would clip) and documented in the file header.
- **Missing glyphs.** A code point the table does not cover is measured with the
  font's `advanceWidthMax`, i.e. fail-closed toward the warning; such a glyph
  already blocks export with `EXP-004`.
- **Metrics asset unavailable.** If `assets/fonts/metrics.json` cannot be read,
  the measurement returns null, no warning is fabricated, and the save still
  stores the complete value. The host bootstrap asserts that the real asset
  loads, so this path is covered by construction, not by a device test.
- **Sheet stays open on overflow.** `editor-interactions.md` §5 requires the
  warning immediately after the commit, so an overflowing commit keeps the sheet
  open instead of closing it. Three existing host tests were adapted for texts
  that genuinely overflow their test field (§1.3).
- **T084 report text.** `reports/…t084…` still records layout measurement as
  `NOT_RUN`; this report supersedes that residual for the productive path.
- T086 owns the two-page US4 acceptance, T086D the remaining US4 work; neither is
  claimed here.

## 6. Command binding, commits and trees

| Item | Value |
| --- | --- |
| `command:speckit.implement` | `.opencode/commands/speckit.implement.md`, SHA-256 `e036ce63702db93e656e1c91ee6c02a8dc3d4a4f8624f8ba4adc69027fe68983` (`artifact_adapted`) |
| Prerequisites | `SPECIFY_FEATURE_DIRECTORY=specs/001-scanned-form-workflow SPECIFY_FEATURE_NO_PERSIST=1 .specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` → exit 0 |
| Extensions | `.specify/extensions.yml`: `installed: [github]`, `auto_execute_hooks: true`, `hooks: {}` |
| Checklists | three feature checklists read, not modified |
| Base | `a84dec7ce5c17630e1b65253fb5936a31dac3a96` (`origin/main`, no rebase) |
| Code commit / tree | `68038580ba4578741190f675fdac4f87a8ef469c` / `4d57d91dfeb4ff7e575ba17d0c7d101db87d050a` |
| Tooling commit | `95000461f27e2d344750c180022d78f9492828f0` |
| Journey HEAD / tree (evidence commit parent) | `c7a3ca73eb5a597cf3803b028e22467b367f3e34` / `662916860ece2100133f84aacc1d56dc3b9772bb` |
| Evidence commit | the commit that adds this report and the bundle; it cannot embed its own SHA |
| Pre-existing dirty file | `apps/feldexa_app/android/gradlew.bat` (CRLF) — never staged |
| Push / PR / merge | none (local branch only) |
| Report validator | `tools/evaluation/validate_report.dart` targets the `YYYY-MM-DD--<slug>.md` class-run template; this hand-written report fails it exactly like its T086 siblings, so that gate is `NOT_RUN` (not applicable) |
| T086C task row | stays `[ ]`; T086 and T086D untouched |
