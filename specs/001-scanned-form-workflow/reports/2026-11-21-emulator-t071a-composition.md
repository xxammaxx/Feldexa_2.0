# T071A editor review/fill composition — host evidence and Pixel 7 API 35 emulator PASS

- **Task / issue**: T071A / <https://github.com/xxammaxx/Feldexa_2.0/issues/244>
- **Feature**: `specs/001-scanned-form-workflow` US3/US4
- **Date**: 2026-11-21 (local)
- **Host evidence class**: `NONE` (host-VM analyze, format, widget/unit tests)
- **Emulator evidence class**: `EMULATOR` — **`PASS`** (correction 3)
- **Overall result**: `PASS` — the correction-3 layout/test fix is host-green and
  the full five-phase real journey passed on the Orca-attached Pixel 7 API 35
  emulator. T071 stays blocked for its separate Android touch test.

## 0. Machine-first handoff

```json
{
  "task": "T071A",
  "issue": 244,
  "base_commit": "127f978f44911ef7a8c53b7c696bf5218915ae6c",
  "correction_2_base_commit": "e83ac25e7c177a455812204b7f12279f40bade71",
  "correction_3_base_commit": "771abede9c847693c9f520cbe8c4312984b1165b",
  "branch": "xxammaxx/t071a",
  "candidate_commit": "the correction-3 commit that updates this report; exact SHA and tree are recorded in the external dispatch handoff",
  "host_evidence_class": "NONE",
  "emulator_evidence_class": "EMULATOR",
  "overall_result": "PASS",
  "correction": 3,
  "host_counts": {
    "app_candidate": 420,
    "app_new": 0,
    "focused_editor_composition": 10,
    "application_candidate": 174,
    "application_new": 0
  },
  "host_gates": {
    "app_analyze": "exit 0, no issues",
    "application_analyze": "exit 0, no issues",
    "format": "exit 0, 0 changed",
    "git_diff_check": "exit 0, clean"
  },
  "emulator": {
    "driver": "tools/android/t071a_drive_composition.sh",
    "driver_result": "PASS",
    "run_status": "result=PASS, flutter_test_exit=0",
    "device": {
      "serial": "emulator-5554",
      "avd": "T025_Pixel7_API35_KVM_20261115",
      "android_release": "15",
      "sdk": 35,
      "abi": "x86_64",
      "fingerprint": "google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys",
      "wm_size": "1080x2400",
      "density": 420
    },
    "apk_sha256": "cbfb3b1eaef8ea46f0425269296ffd4fe26136b9ff93e761b52033b491c65fd3",
    "fixture": {
      "bytes": 5956,
      "sha256": "22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038",
      "damaged_sha256": "57c1ade1ab2c00375ac61703db3d4ce5d27b996ea067647aba585866dc6ec221"
    },
    "markers_observed": [
      "T071A_FIXTURE_READY:BYTES=5956:MATCH=1",
      "T071A_DAMAGED_FIXTURE_READY:BYTES=5956:MATCH=1",
      "T071A_START_LIST_READY",
      "T071A_IMPORT_ARMED",
      "T071A_EDITOR_READY",
      "T071A_ANALYSIS_READY:STATE=analysis-ready:PAGES=2:SUGGESTIONS=28:CONFIRMED=0",
      "T071A_FIELD_CONFIRMED",
      "T071A_T071A_SCREENSHOT_OVERLAY_SELECTION",
      "T071A_T071A_SCREENSHOT_VALUE_SHEET",
      "T071A_VALUE_SAVED",
      "T071A_SAVED_READBACK:OK",
      "T071A_T071A_SCREENSHOT_SAVED_STATUS",
      "T071A_START_LIST_RELOADED",
      "T071A_T071A_SCREENSHOT_DOCUMENT_LIST",
      "T071A_REOPENED_READBACK:OK",
      "T071A_T071A_SCREENSHOT_REOPENED_VALUE",
      "T071A_CLEANUP_DONE"
    ],
    "screenshots": {
      "screenshots/overlay-selection.png": "254904 bytes, SHA-256 f3e37e1b661081041711f85b5179d03edb533e4c81d3c9dd161081747588f46e",
      "screenshots/value-sheet.png": "222662 bytes, SHA-256 20b756717f9ec68dbfa48491d960af0e85f242a7255895ef460bc36d0a7fbc03",
      "screenshots/saved-status.png": "254904 bytes, SHA-256 f3e37e1b661081041711f85b5179d03edb533e4c81d3c9dd161081747588f46e",
      "screenshots/document-list.png": "102207 bytes, SHA-256 e9f0d368e89a7654293f209d44ec64c6cecdc4f2aeb408006d6163f497013461",
      "screenshots/reopened-value.png": "213494 bytes, SHA-256 e6d2b002ab910f287c55dfedce6a3b489c6f9e536276b2a320e1d6ab661a148e"
    },
    "privacy_checks": "PASS (log and source checks)",
    "no_renderflex_overflow_in_journey_log": true
  },
  "not_run": [
    "signature asset editing (still visibly NOT_RUN in the value sheet)",
    "layout overflow measurement beyond the journey and host no-overflow checks",
    "template open route (no template editor route in T071A)",
    "TalkBack/accessibility traversal and visual/golden inspection",
    "T071 Android touch drag/resize test (T071 remains blocked)",
    "DEVICE acceptance and any performance claim"
  ]
}
```

Historical correction-2 state remains in §2; the correction-2 machine handoff is
preserved in git history and is superseded by this block.

## 1. Revision and scope

- Base: `127f978f44911ef7a8c53b7c696bf5218915ae6c` (`main`, T071A
  authorization docs).
- Correction-1 base: `e83ac25e7c177a455812204b7f12279f40bade71`; correction 1
  (`8a51b8e`, `e83ac25`) fixed only the driver's app-package selection and
  worktree-bound Orca session resolution.
- Correction-3 base: `771abede9c847693c9f520cbe8c4312984b1165b` (correction-2
  candidate). Correction 3 changes only the editor body layout, the integration
  route-removal wait, this report/artifacts, the index, and the T071A task row.
- Worktree: `<repo-root>` (`t071a-composition`).
- Branch: `xxammaxx/t071a`.
- The report is committed on the candidate branch. Its own commit SHA/tree
  cannot be embedded in its bytes; the dispatch handoff carries those values
  externally.
- The pre-existing unstaged `apps/feldexa_app/android/gradlew.bat` line-ending
  change was not touched, staged, or committed.
- No push, PR, merge, `main` edit, Gradle file, core, ports, recognition,
  recognition-output, ARB, or generated-localization change was made.
- Correction 2 changes only the authorized editor/viewer diagnostics, the
  bounded first-analysis guard, the integration test, the driver wording, and
  the guard test. No recognition change is made.

## 2. Correction 2 — synchronous analysis stall and damaged fixture

Correction 1 made the real emulator journey proceed past the driver preflight.
That run exposed the actual composition stall described below. Correction 2
does not re-run the emulator; the coordinator runs it after this commit.

### 2.1 Proven root cause

On `e83ac25` the real journey reached `T071A_EDITOR_READY`, the viewer rendered,
and analysis reached page-1 raster/OCR. It then blocked synchronously on the
undamaged `sf-001` page 2 inside `GeometryDetector._detectBoxes`
(`packages/feldexa_recognition/lib/src/geometry_detector.dart`): a CPU-bound
quadruple rule loop (`horizontals` × `horizontals` × `verticals` × `verticals`)
with corner/ink checks. Because that work is synchronous on the UI isolate,
`Future.timeout` and the widget-test pump loop cannot preempt it; the app stays
in „Analyse ausstehend“ and the journey never reaches `T071A_ANALYSIS_READY`.
Recognition performance and any recognition change are outside T071A scope.

### 2.2 Bounded guard and its limitation

- `EditorScreen` wraps the single `AnalyzeDocument.run` call in
  `editorAnalysisTimeout` (5 minutes) and maps an unanswered future to the
  existing `analysis-failed` state with the stable reason
  `analysis-timeout`. `_markFailed` accepts a content-free `reason` that is
  only printed as a diagnostic marker.
- The guard is a fail-closed diagnostic, not a retry, performance, or
  architecture policy. It covers asynchronous port waits only. It **cannot**
  preempt the synchronous CPU-bound detector in §2.1; that limitation is
  documented in the code comment next to `editorAnalysisTimeout`.
- Idempotent `pdfrxFlutterInitialize()` calls were added on the Android editor
  load path and in the production viewer factory. This is defensive engine
  startup, **not** the proven root cause of the stall, and it is not claimed
  as a fix for the synchronous detector.

### 2.3 T061 damaged-page-2 fixture

- The committed `sf-001.pdf` is still loaded from the app-readable device
  staging directory and verified as 5956 bytes with SHA-256
  `22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038`.
- The integration test derives the deterministic T061 damaged variant by
  replacing the second `/MediaBox [0 0 595.28 841.89]` occurrence (29 bytes)
  with 29 spaces, using the helper copied from
  `android_recognition_test.dart` `_damageSecondPageMediaBox`.
- Derived identity: 5956 bytes, different from the original, SHA-256
  `57c1ade1ab2c00375ac61703db3d4ce5d27b996ea067647aba585866dc6ec221`,
  marker `T071A_DAMAGED_FIXTURE_READY:BYTES=5956:MATCH=1`. The same values are
  recorded in `artifacts/2026-11-21-t071a-composition/correction-2-fixture-damage.txt`.
- Rationale: T061 proved this source imports with page 1 usable and page 2 as
  `IMP-006`/`unsupportedStructure` `unreadable`, and T061 reached
  `analysis-ready` with it. Page 2 is therefore excluded from analysis and the
  synchronous detector never sees it. Page-1 suggestions remain the journey
  target; no page-2 suggestion is asserted.
- The damaged bytes are written to the existing scratch source and armed. The
  original bytes are not used for the journey. No damaged PDF is committed,
  pushed, or added to the APK.
- The host test `a partially unreadable first import still analyzes readable
  pages` already proves the existing page filtering and identity/geometry
  acceptance for a document with an unreadable page. Proving the same for the
  real damaged import on Android is part of the coordinator's pending run.

### 2.4 Diagnostics

Content-free `T071A_DIAG_*` markers (debug builds only) now cover:

- editor runtime load: `RUNTIME_LOAD_START`, `RUNTIME_PDFRX_READY`,
  `RUNTIME_LOAD_FAIL`, `RUNTIME_LOAD_OK`;
- editor load/content/analysis: `LOAD_*`, `CONTENT_SET`, `ANALYSIS_START`,
  `ANALYSIS_RESULT`, `ANALYSIS_PAGE` (complete or failed with category/key),
  `ANALYSIS_APPLY_FAIL`, `ANALYSIS_APPLIED`, `ANALYSIS_SAVE_*`,
  `ANALYSIS_STATE`, and typed `LOAD_FAIL`/`ANALYSIS_FAIL` reasons;
- raster/OCR adapter decorators: `RASTER_START/OK/FAIL` and
  `OCR_START/OK/FAIL` with page index, dimensions, block count, or error type;
- viewer/source: `VIEW_INIT_*`, `VIEW_DOCUMENT_OPEN_OK`, `VIEW_OPEN_*`,
  `VIEW_BYTES`, `VIEW_FAIL`, `VIEW_PAGE_FAIL`, `VIEW_PAGE_COUNT_MISMATCH`, and
  `PAGE_RENDER_START/OK/FAIL/CANCELLED`.

Markers contain only names, page indexes, counts, byte presence, booleans,
dimensions, stable categories/keys, and error type names. No id, path, URI,
title, label, OCR text, entered value, or hash of document content is printed.
The integration test waiter fails immediately with `T071A_ANALYSIS_FAILED`
plus per-page `T071A_ANALYSIS_PAGE:P=<n>:STATE=<state>:KEY=<key>` markers; its
bound is the 5-minute editor guard plus one minute of slack.

### 2.5 Correction-2 changed files

1. `apps/feldexa_app/lib/features/editor/editor_runtime_android.dart` —
   idempotent pdfrx initialization and debug-only raster/OCR/load diagnostics.
2. `apps/feldexa_app/lib/features/editor/editor_screen.dart` — 5-minute
   analysis guard, stable failure reasons, and content-free diagnostics.
3. `apps/feldexa_app/lib/features/editor/page_view.dart` — idempotent pdfrx
   initialization and content-free viewer/render diagnostics; no geometry or
   gesture change.
4. `apps/feldexa_app/integration_test/android_review_composition_test.dart` —
   terminal analysis waiter, damaged-fixture derivation, and diagnostics.
5. `tools/android/t071a_drive_composition.sh` — fixture/diagnostic wording and
   expected damaged SHA; allocation, screenshot, and cleanup logic unchanged.
6. `apps/feldexa_app/test/editor_analysis_test.dart` — the bounded-analysis
   guard test.
7. This report, its correction-2 artifacts, `reports/README.md`, and the T071A
   line in `tasks.md`.

## 2A. Correction 3 — IME overflow and editor-route wait

Start HEAD: `771abede9c847693c9f520cbe8c4312984b1165b` (correction-2 candidate,
host green: app 420, application 174). The correction-2 journey reached
analysis with 28 suggestions, suggestion confirmation, the overlay/selection
screenshot, the value sheet, a verified value save with store read-back, and
the saved-status screenshot. It then failed on two defects.

### 2A.1 Root causes

1. **Editor body overflow with the IME open.** The body `Column` kept
   `PageStrip`, the optional `IMP-006` warning, and up to 320 dp
   `SuggestionReviewPanel` as fixed children, followed by one
   `Expanded(PageView)`. With the keyboard open, the Scaffold shrinks the body
   until the fixed children exceed it; the `Expanded` page is forced to 0 and
   the `Column` overflows (`RenderFlex overflowed by 59 px`). The same failure
   class exists at 200 % text scale.
2. **Test/route race.** The post-pop `_pumpUntil` returned as soon as the start
   list and stored item appeared. The popped `EditorScreen` route can still be
   present for a reverse-transition frame, so the immediately following
   `expect(find.byType(EditorScreen), findsNothing)` failed. This is a
   test-observation defect, not app behavior.

### 2A.2 Fix

- `editor_screen.dart`: `PageStrip` stays fixed under the app bar. The warning
  and review panel moved into the trailing `Expanded` region, which now uses
  `LayoutBuilder` and computes
  `maxHeaderHeight = (constraints.maxHeight - _minPageViewportHeight).clamp(0.0, double.infinity)`
  with a documented `const double _minPageViewportHeight = 160`.
  The header is a `ConstrainedBox(maxHeight: maxHeaderHeight)` +
  `SingleChildScrollView` + `Column(mainAxisSize: MainAxisSize.min)` holding
  the warning and panel; the unchanged `PageView` follows as the only flex
  child and fills the rest. With room, the header keeps its natural height and
  the panel its 320 dp cap, so the normal layout is unchanged. With the IME or
  200 % scale, the header scrolls inside its bound and the page keeps at least
  160 dp (or all remaining space on smaller bodies). No `PageView` geometry,
  gesture, overlay, or value-sheet semantics changed.
- `android_review_composition_test.dart`: the post-pop `_pumpUntil` condition
  now also requires `find.byType(EditorScreen).evaluate().isEmpty`; a
  `tester.pumpAndSettle()` runs before the unchanged
  `expect(find.byType(EditorScreen), findsNothing)`, and the timeout reason
  mentions the popped route. No assertion was weakened and no app behavior was
  changed.

### 2A.3 Diff summary

| File | Lines | Change |
| --- | --- | --- |
| `apps/feldexa_app/lib/features/editor/editor_screen.dart` | +81 / −27 | `_minPageViewportHeight = 160`; header moved into a bounded scrollable inside the trailing `Expanded`; `PageView` unchanged |
| `apps/feldexa_app/integration_test/android_review_composition_test.dart` | +5 / −1 | post-pop wait includes editor-route removal; `pumpAndSettle` before assertion; reason text |

### 2A.4 Correction-3 host gates (evidence `NONE`)

All commands ran in the worktree on the correction-3 working tree before the
emulator run.

| # | Command | Exit | Result |
| ---: | --- | ---: | --- |
| 1 | `cd apps/feldexa_app && flutter analyze --no-pub` | 0 | No issues found |
| 2 | `cd packages/feldexa_application && dart analyze` | 0 | No issues found |
| 3 | `cd apps/feldexa_app && dart format --output=none --set-exit-if-changed lib/features/editor/editor_screen.dart integration_test/android_review_composition_test.dart` | 0 | 2 files, 0 changed |
| 4 | `cd apps/feldexa_app && flutter test --no-pub test/editor_composition_test.dart` | 0 | **10/10** passed |
| 5 | `cd apps/feldexa_app && flutter test --no-pub` | 0 | **420/420** passed |
| 6 | `cd packages/feldexa_application && flutter test --no-pub` | 0 | **174/174** passed |
| 7 | `git diff --check` (repo root) | 0 | clean |

The exact terminal lines are in
`artifacts/2026-11-21-t071a-composition/correction-3-host-gates.txt`.

### 2A.5 Correction-3 emulator run (`EMULATOR`, `PASS`)

Command (repo root, exclusive Orca `emulator-5554` session attached to this
worktree):

```sh
T071A_REPLACE_EVIDENCE=1 tools/android/t071a_drive_composition.sh
```

The driver exited `PASS`; `run-status.txt` records `result=PASS` and
`flutter_test_exit=0`. The integration log ends with `All tests passed!`
(`+1` test) and contains **no** `RenderFlex`, overflow, or exception line.

Marker sequence observed in `integration-android-t071a.log` (the test's
`_marker` prepends `T071A_`, so the screenshot markers appear with a doubled
prefix):

```text
T071A_FIXTURE_READY:BYTES=5956:MATCH=1
T071A_DAMAGED_FIXTURE_READY:BYTES=5956:MATCH=1
T071A_START_LIST_READY
T071A_IMPORT_ARMED
T071A_EDITOR_READY
T071A_DIAG_ANALYSIS_PAGE:P=0:STATUS=complete:SUGGESTIONS=28:UNCERTAIN=0
T071A_ANALYSIS_READY:STATE=analysis-ready:PAGES=2:SUGGESTIONS=28:CONFIRMED=0
T071A_FIELD_CONFIRMED
T071A_T071A_SCREENSHOT_OVERLAY_SELECTION
T071A_T071A_SCREENSHOT_VALUE_SHEET
T071A_VALUE_SAVED
T071A_SAVED_READBACK:OK
T071A_T071A_SCREENSHOT_SAVED_STATUS
T071A_START_LIST_RELOADED
T071A_T071A_SCREENSHOT_DOCUMENT_LIST
T071A_REOPENED_READBACK:OK
T071A_T071A_SCREENSHOT_REOPENED_VALUE
T071A_CLEANUP_DONE
```

The driver's `marker-sequence.txt` records the five screenshot
markers/acknowledgements and `PASS (flutter test exit 0; cleanup marker
observed; privacy checks PASS)`.

Build, device, and fixture identity:

- APK: `apps/feldexa_app/build/app/outputs/flutter-apk/app-debug.apk`,
  SHA-256 `cbfb3b1eaef8ea46f0425269296ffd4fe26136b9ff93e761b52033b491c65fd3`.
- Device: serial `emulator-5554`, AVD `T025_Pixel7_API35_KVM_20261115`,
  Android 15 / SDK 35, `x86_64`, fingerprint
  `google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys`,
  1080x2400 at density 420.
- Fixture: committed host and staged bytes 5956, SHA-256
  `22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038`;
  the in-test T061 damaged derivation is 5956 bytes with SHA-256
  `57c1ade1ab2c00375ac61703db3d4ce5d27b996ea067647aba585866dc6ec221`.
- Privacy: `privacy-log-check.txt` PASS (no document content or fixture path
  in the integration log) and `privacy-source-check.txt` PASS (no network API
  reference in the integration test).

### 2A.6 Correction-3 assumption

`_minPageViewportHeight = 160` is a new documented layout constant, not a
behavior or contract value. It reserves a usable page viewport on phone
heights while allowing the warning/review header to scroll under the IME. On a
body smaller than 160 dp the header collapses completely and the page takes
the remaining height; no overflow is possible because the header is bounded
and the page is the only flex child.

### 2A.7 Correction-3 `NOT_RUN`

- Signature asset editing (still visibly `NOT_RUN` in the value sheet).
- Layout overflow measurement beyond the host no-overflow composition test and
  the real journey log.
- Opening a stored template (no template editor route in T071A).
- TalkBack/accessibility traversal and visual/golden inspection.
- T071 Android touch drag/resize acceptance; T071 stays blocked.
- `DEVICE` acceptance and any performance claim.

## 3. Changed files

Original-delivery files; correction-2 changes are listed in §2.5.

Production/composition:

1. `apps/feldexa_app/lib/features/editor/page_view.dart` — optional
   `overlayBuilder`; visible pages are wrapped in a `Stack` with their page
   content. Geometry, gestures, and pan/zoom are unchanged.
2. `apps/feldexa_app/lib/features/editor/editor_screen.dart` — per-page T069
   overlay items, T077 `FieldSelectionSurface`, confirmed-field tap →
   value-sheet route, suggestion tap → highlight only, T091 app-bar status,
   PRIV-001 dialog, verified value save, review-save durability updates.
3. `apps/feldexa_app/lib/features/editor/field_value_sheet.dart` (new) —
   type-appropriate T079/T082 sheet, T080/T081 parsers + catalog errors,
   T084 warning when the stored value is already marked overflowing, signature
   editing visibly `NOT_RUN`.
4. `packages/feldexa_application/lib/src/review/set_value.dart` (new) —
   `setFieldValue` and `SetValueChange`.
5. `apps/feldexa_app/lib/features/start/start_screen.dart` — store-backed
   `StoredItemsView` document/template groups, readable-document load through
   the existing store, `ImportedSource` reconstruction, editor open, reload on
   return, unreadable-entry refusal.
6. `apps/feldexa_app/lib/features/start/import_runtime.dart` — optional
   existing `SecureStorePort` exposure.
7. `apps/feldexa_app/lib/features/start/import_runtime_android.dart` — passes
   the already-composed `AndroidStoreClient`.

Tests and evidence:

8. `packages/feldexa_application/test/set_value_test.dart` (new).
9. `apps/feldexa_app/test/editor_composition_test.dart` (new).
10. `apps/feldexa_app/integration_test/android_review_composition_test.dart`
    (new; not executed).
11. `tools/android/t071a_drive_composition.sh` (new; exclusive-allocation
    preflight stops at `EMULATOR NOT_RUN`).
12. `specs/001-scanned-form-workflow/reports/2026-11-21-emulator-t071a-composition.md`
    (this report).
13. `specs/001-scanned-form-workflow/reports/artifacts/2026-11-21-t071a-composition/`
    (new host/preflight bundle; no runtime artifacts).
14. `specs/001-scanned-form-workflow/reports/README.md` (index).
15. `specs/001-scanned-form-workflow/tasks.md` (T071A status/docs; checkbox
    intentionally remains open until integration and the emulator journey).

No `apps/feldexa_app/pubspec.yaml` change was authorized. The app therefore
consumes the existing `feldexa_ui` workspace package through the workspace
package config and carries a documented
`// ignore_for_file: depend_on_referenced_packages` on the editor import. A
later dependency-declaration task should add the app path dependency.

## 4. Delivered behavior

### 4.1 Overlay and selection

- Every visible page receives `overlayBuilder(pageIndex, viewportRect, mapping)`
  inside its page box. The builder composes `FieldOverlay` and
  `FieldSelectionSurface`; it does not mutate geometry or the view transform.
- Overlay items are filtered explicitly by `pageIndex`; confirmed fields use
  `FieldOverlayItem.fromConfirmedField` and only `unresolved` suggestions use
  `FieldOverlayItem.fromSuggestion`.
- `FieldOverlayItem.selected` stays false; the selection accent is painted only
  by T077, so there is no double accent.
- A tap on a confirmed field selects it and opens `FieldValueSheet`; a tap on a
  suggestion selects/highlights it and never invents a value; a tap on empty
  page space clears the selection.

### 4.2 `setFieldValue`

- Requires an existing field and the exact matching concrete value:
  text, multiline, number, date, checkbox, signature. `IncompatibleValue` is
  rejected as a new edit.
- Stamps the caller-supplied UTC `lastEditedAt`.
- Replaces only `values[fieldId]`; copies pages, suggestions, fields, order,
  signatures, verification, template origin, and unknown JSON fields.
- Returns `SetValueChange` with the previous snapshot/value. Failures are
  content-free `ArgumentError`s.

### 4.3 Value sheet and save

- T079 text/multiline; T080 `parseGermanNumber`; T081 `parseGermanDate` with
  the catalog `NUM-001`/`DATE-001`/`DATE-002` sentences; T082 checkbox; T084
  warning when the stored value already carries `overflow`.
- Invalid number/date input remains in the open sheet and is never handed to
  the command.
- Commit runs `setFieldValue`, then `runtime.saveRevision` with
  `expectedHead = _headRevisionId` and `kind = autosave`. `_content`,
  `_headRevisionId`, `_lastDurableAt`, and the T091 saved state are updated
  only from the verified `StoredMeta`.
- A failed save keeps the sheet and prior content editable, shows the
  content-free `SAVE-*` sentence, and shows
  `DurabilityStatus.saveFailed(code)`; no optimistic saved claim is made.
- The app bar hosts `DurabilityStatusLabel`. PRIV-001 is available through the
  existing `PrivacyKeyDisclosure` in an app-bar action dialog.
- Signature editing is visibly `NOT_RUN`; no signature asset is fabricated.

### 4.4 Start list and reopen

- When `ImportRuntime.store` is non-null, the start surface always renders T095
  `StoredItemsView` for `StoreKind.document` and `StoreKind.template`.
- A readable document is loaded through the existing store; metadata/source
  identity and persisted page geometry build an `ImportedSource`; the editor
  opens with those verified bytes.
- Returning from the editor re-reads both list groups.
- Unreadable entries remain visible with the T095 unreadable status and are
  refused before any store load. A template row is visible when present but
  has no template editor route in T071A.
- Without a store, the previous import-only start surface is unchanged.

## 5. Host gates (evidence `NONE`)

Correction-3 gates and results are in §2A.4. Correction-2 gates ran from the
correction base `e83ac25`:

| Gate | Command | Result |
| --- | --- | --- |
| App analyze | `cd apps/feldexa_app && flutter analyze --no-pub` | exit 0, no issues |
| Application analyze | `cd packages/feldexa_application && dart analyze` | exit 0, no issues |
| Format | `cd apps/feldexa_app && dart format --output=none --set-exit-if-changed lib/features/editor/editor_runtime_android.dart lib/features/editor/editor_screen.dart lib/features/editor/page_view.dart integration_test/android_review_composition_test.dart test/editor_analysis_test.dart` | exit 0, 0 changed |
| Driver syntax | `bash -n tools/android/t071a_drive_composition.sh` (repo root) | exit 0 |
| Diff check | `git diff --check` before commit (and `git diff --check e83ac25..HEAD` after commit) | clean |
| Focused analysis guard | `cd apps/feldexa_app && flutter test --no-pub test/editor_analysis_test.dart` | **22/22** passed (21 baseline + 1 guard) |
| Full app suite | `cd apps/feldexa_app && flutter test --no-pub` | **420/420** passed (419 baseline + 1 guard) |
| Full application suite | `cd packages/feldexa_application && flutter test --no-pub` | **174/174** passed |

The exact terminal lines and exit codes are recorded in
`artifacts/2026-11-21-t071a-composition/correction-2-host-gates.txt`.

The original composition coverage remains in the 420-test app suite:
`editor_composition_test.dart` covers the overlay hook page/rect/mapping, a
confirmed-field tap opening the sheet, a suggestion tap without a sheet, the
T080/T081 number/date parser rejection and successful German input, the verified
save updating content/head/status, a failed save keeping the sheet and old
content with `SAVE-003`, the start-list load/reopen/reload path, unreadable
refusal, and 200 % text scale without a RenderFlex overflow. `set_value_test.dart`
covers all six types, mismatch rejection, missing field, non-UTC rejection,
unchanged sibling values, preserved suggestions/fields/order/signatures/
verification/template origin/unknown fields, previous value/content, and
untruncated text.

The new guard test gates a raster render, uses a 100 ms `analysisTimeout`, and
asserts that the editor reaches `editorAnalysisFailedKey`, keeps the loaded
content pending, saves no revision, shows the failed key, and raises no
exception.

## 6. Emulator acceptance — `NOT_RUN` at correction 2 (historical)

Correction 2 did **not** execute the emulator, adb, screenshots, installs, or
the driver. The real journey after that commit was left to the coordinator's
run of `tools/android/t071a_drive_composition.sh` against `emulator-5554`.
Correction 3 executed that run; see §2A.5 for the current `EMULATOR` `PASS`.

The correction-1 preflight blocker (no worktree-bound Orca session) was fixed by
`8a51b8e`/`e83ac25`; the earlier `NOT-RUN.md`,
`device-identity-preflight.txt`, `orca-emulator-devices.json`, and
`orca-emulator-sessions.json` remain as historical preflight evidence only. The
subsequent real run of `e83ac25` reached `T071A_EDITOR_READY`, rendered the
viewer, and then stalled in the synchronous page-2 geometry detector described
in §2.1; that observation is dispatch input to this correction, not a run
performed by this worker.

Consequently this commit contains **no** T071A screenshots, logcat markers,
APK SHA-256, on-device fixture hash, runtime AVD/serial run record, saved-status
visual confirmation, or reopened-document visual confirmation. None of the host
checks above is presented as emulator evidence. **No emulator PASS is claimed
in this commit.**

## 7. `NOT_RUN` register (historical, correction 2)

- `EMULATOR` journey after correction 2 (coordinator run pending):
  import/analysis/suggestion-confirmation/selection/value-sheet/save/leave/
  reopen.
- Five required screenshots and the screenshot acknowledgement handshake.
- APK build/install (no artifact or hash is claimed in this commit).
- Runtime logcat markers and privacy log check.
- On-device fixture SHA-256 and runtime device identity for a run.
- On-device derivation of the damaged fixture and proof that page 2 is
  `IMP-006`/`unreadable` during this journey.
- Analysis-ready after the damaged-fixture swap (host-side preparation only).
- Signature asset editing through T083 (shown as `NOT_RUN` in the sheet).
- Overflow layout measurement (T084 only shows an already-marked overflow).
- Opening a stored template from the list (no template editor route).
- TalkBack/accessibility traversal and visual/golden inspection.
- T071 Android touch drag/resize acceptance; T071 stays blocked.
- `DEVICE` acceptance and any performance claim.
- Text-scale visual rendering beyond the host RenderFlex check.

## 8. Reproducibility

1. Check out the correction-3 candidate branch on the worktree.
2. `flutter pub get --offline` at the repository root.
3. Verify the committed fixture: 5956 bytes, SHA-256
   `22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038`;
   the in-test damage helper then yields the 5956-byte T061 source with SHA-256
   `57c1ade1ab2c00375ac61703db3d4ce5d27b996ea067647aba585866dc6ec221`.
4. Run the host gates in §2A.4.
5. Request/attach an exclusive Orca Pixel 7 API 35 session to this worktree.
6. Run `T071A_REPLACE_EVIDENCE=1 tools/android/t071a_drive_composition.sh`.
7. Verify the five screenshots, `marker-sequence.txt`, `run-status.txt`,
   `apk-sha256.txt`, `fixture-sha256.txt` (including the
   `expected_damaged_sha256=` line), `device-identity.txt`, and the integration
   log marker sequence in the evidence directory.
8. Cleanup: the driver removes staging and clears test app data; it never
   modifies another worktree's allocation.

## 9. Artifacts

Directory `artifacts/2026-11-21-t071a-composition/`.

Historical files retained:

- `NOT-RUN.md` (historical correction-1 preflight blocker)
- `device-identity-preflight.txt` (historical)
- `orca-emulator-devices.json` (historical)
- `orca-emulator-sessions.json` (historical)
- `git-identity-base.txt`
- `host-gates.txt` (original delivery)
- `correction-2-host-gates.txt` — 1466 bytes, SHA-256
  `54b04c586313a233c0a5a04ceb378d2fbcde402f68aa82917d410e067c2077bb`
- `correction-2-fixture-damage.txt` — 790 bytes, SHA-256
  `f9c236f1965a50d88cf810ccd59307d26c73ea94f6925ae6ec5155200cf6ac9f`

Correction-3 run bundle:

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Bundle README | `artifacts/2026-11-21-t071a-composition/README.md` | 3097 | `ba6f223232fc5d12e1a2f058727a7609af9b44bf8e1081fda34606bf38b51b0d` |
| Host gates | `artifacts/2026-11-21-t071a-composition/correction-3-host-gates.txt` | 1208 | `b3b1a989f26902425b97b1c80820a9ece3a62c1e04d9ff06de519e4f5a4d79f3` |
| Git identity | `artifacts/2026-11-21-t071a-composition/git-identity.txt` | 344 | `431532ee9977e34725ce5aea65dcf3c5baf0014f6d53e8a6dba8f1d8e35e7c63` |
| APK hash | `artifacts/2026-11-21-t071a-composition/apk-sha256.txt` | 185 | `7e264a00f413affeef6e568c167789cbd4060a58270ac64c66e48eb83eab6409` |
| Device identity | `artifacts/2026-11-21-t071a-composition/device-identity.txt` | 298 | `265c299fe643739f0c63d2fc73f638d221a7aa9322b021641ab53bc0fedbbf56` |
| Fixture hashes | `artifacts/2026-11-21-t071a-composition/fixture-sha256.txt` | 510 | `86d2d2601208813244b65a065198f8b284da92683ea237b608ce2c122188d7b8` |
| Pub get log | `artifacts/2026-11-21-t071a-composition/host-flutter-pub-get.log` | 347 | `39e8b11c6d3c7aaf75f7af8ed55924e7b6c7eb89054116096fdb6b61470ea329` |
| Integration log | `artifacts/2026-11-21-t071a-composition/integration-android-t071a.log` | 3968 | `6493e9f492fbb6551f074652d3f4abb1163603f5d5f056ec4a28391bf7a40b31` |
| Flutter logcat | `artifacts/2026-11-21-t071a-composition/logcat-flutter.log` | 315 | `e6495a5ad731d79d429d214f09768ad26af206f65d21c15badb4c0e54366d5ee` |
| Lifecycle logcat | `artifacts/2026-11-21-t071a-composition/logcat-t071a-markers.log` | 899 | `541eb6a563e31cff5057d5c5d9a0b203546c284d4b811427b1848f8eb378c8eb` |
| Marker sequence | `artifacts/2026-11-21-t071a-composition/marker-sequence.txt` | 534 | `05a6d92df9a866cef59c7d0fa9d79c163e11e05ea85739dccdcbed3851e24a84` |
| Privacy log check | `artifacts/2026-11-21-t071a-composition/privacy-log-check.txt` | 65 | `7c1bcbf4be8b5984e329ec2afbf1f30214982fc899c13e17f3346fc1c0be22ea` |
| Privacy source check | `artifacts/2026-11-21-t071a-composition/privacy-source-check.txt` | 88 | `cff8cea0e7fea22b0c7ce47cfd57f6a616e7145653d2af07fde7d7b9be5b7005` |
| Run status | `artifacts/2026-11-21-t071a-composition/run-status.txt` | 32 | `7fd607f90d24581a4b9b797cff3d71e0f238dc52f3f869fd23b88a688a94f0b3` |
| Overlay screenshot | `artifacts/2026-11-21-t071a-composition/screenshots/overlay-selection.png` | 254904 | `f3e37e1b661081041711f85b5179d03edb533e4c81d3c9dd161081747588f46e` |
| Value-sheet screenshot | `artifacts/2026-11-21-t071a-composition/screenshots/value-sheet.png` | 222662 | `20b756717f9ec68dbfa48491d960af0e85f242a7255895ef460bc36d0a7fbc03` |
| Saved-status screenshot | `artifacts/2026-11-21-t071a-composition/screenshots/saved-status.png` | 254904 | `f3e37e1b661081041711f85b5179d03edb533e4c81d3c9dd161081747588f46e` |
| Document-list screenshot | `artifacts/2026-11-21-t071a-composition/screenshots/document-list.png` | 102207 | `e9f0d368e89a7654293f209d44ec64c6cecdc4f2aeb408006d6163f497013461` |
| Reopened-value screenshot | `artifacts/2026-11-21-t071a-composition/screenshots/reopened-value.png` | 213494 | `e6d2b002ab910f287c55dfedce6a3b489c6f9e536276b2a320e1d6ab661a148e` |

`overlay-selection.png` and `saved-status.png` are pixel-identical because both
acknowledged handshakes captured the same settled editor frame; they remain
distinct documented phases with separate markers and acknowledgements.

No APK binary, raw full logcat, key material, or separate document-content
extract is stored. The screenshots necessarily show the synthetic fixture; no
text is transcribed.

## 10. Review

- Reviewer:
- Date:
- Verdict:
- Notes:
