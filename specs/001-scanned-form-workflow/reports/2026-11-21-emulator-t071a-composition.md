# T071A editor review/fill composition — host evidence and emulator NOT_RUN

- **Task / issue**: T071A / <https://github.com/xxammaxx/Feldexa_2.0/issues/244>
- **Feature**: `specs/001-scanned-form-workflow` US3/US4
- **Date**: 2026-11-21 (local)
- **Host evidence class**: `NONE` (host-VM analyze, format, widget/unit tests)
- **Emulator evidence class**: `EMULATOR` — **`NOT_RUN`**
- **Overall result**: `PARTIAL` — host composition and the correction-2 guard
  are green; the real emulator journey after correction 2 is pending the
  coordinator's exclusive `emulator-5554` run, and no `EMULATOR` PASS is
  claimed in this commit.

## 0. Machine-first handoff

```json
{
  "task": "T071A",
  "issue": 244,
  "base_commit": "127f978f44911ef7a8c53b7c696bf5218915ae6c",
  "correction_base_commit": "e83ac25e7c177a455812204b7f12279f40bade71",
  "branch": "xxammaxx/t071a",
  "candidate_commit": "the correction-2 commit that updates this report; recorded in the external dispatch handoff",
  "candidate_tree": "recorded in the external dispatch handoff",
  "host_evidence_class": "NONE",
  "emulator_evidence_class": "EMULATOR_NOT_RUN",
  "overall_result": "PARTIAL",
  "correction": 2,
  "host_counts": {
    "app_baseline": 419,
    "app_candidate": 420,
    "app_new": 1,
    "focused_editor_analysis": 22,
    "application_baseline": 174,
    "application_candidate": 174,
    "application_new": 0
  },
  "fixture": {
    "original_bytes": 5956,
    "original_sha256": "22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038",
    "damaged_bytes": 5956,
    "damaged_sha256": "57c1ade1ab2c00375ac61703db3d4ce5d27b996ea067647aba585866dc6ec221",
    "damaged_source": "T061 second /MediaBox replaced by 29 spaces"
  },
  "emulator_steps_pending": [
    "exclusive Orca emulator-5554 allocation preflight",
    "APK build/install and app-data clear",
    "staging of the committed sf-001.pdf and in-test derivation of the T061 damaged source",
    "analysis-ready on the damaged fixture (page 1 usable, page 2 unreadable/IMP-006)",
    "suggestion confirmation, field selection, value sheet, verified save, saved read-back",
    "leave, start-list reload, reopen, reopened read-back",
    "five-screenshot handshake and marker-filtered logcat",
    "APK SHA-256, device identity, cleanup"
  ],
  "emulator_evidence_paths": [],
  "not_run": [
    "EMULATOR real journey after correction 2 (coordinator run pending)",
    "five screenshots and screenshot acknowledgement handshake",
    "runtime logcat markers and privacy log check",
    "APK build and APK SHA-256",
    "on-device fixture SHA-256 and app-data reset",
    "signature asset editing",
    "layout overflow measurement",
    "template open route",
    "TalkBack and visual inspection",
    "T071 Android touch drag/resize test",
    "DEVICE acceptance"
  ]
}
```

## 1. Revision and scope

- Base: `127f978f44911ef7a8c53b7c696bf5218915ae6c` (`main`, T071A
  authorization docs).
- Correction-1 base: `e83ac25e7c177a455812204b7f12279f40bade71`; correction 1
  (`8a51b8e`, `e83ac25`) fixed only the driver's app-package selection and
  worktree-bound Orca session resolution.
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

Correction-2 gates run from the correction base `e83ac25`:

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

## 6. Emulator acceptance — `NOT_RUN`

Correction 2 does **not** execute the emulator, adb, screenshots, installs, or
the driver. The real journey after this commit is the coordinator's run of
`tools/android/t071a_drive_composition.sh` against `emulator-5554`.

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

## 7. `NOT_RUN` register

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

1. Check out the correction-2 candidate branch on the worktree.
2. `flutter pub get --offline` at the repository root.
3. Verify the committed fixture: 5956 bytes, SHA-256
   `22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038`;
   the in-test damage helper then yields the 5956-byte T061 source with SHA-256
   `57c1ade1ab2c00375ac61703db3d4ce5d27b996ea067647aba585866dc6ec221`.
4. Run the host gates in §5.
5. Request/attach an exclusive Orca Pixel 7 API 35 session to this worktree.
6. Run `tools/android/t071a_drive_composition.sh`.
7. Verify the five screenshots, `marker-sequence.txt`, `run-status.txt`,
   `apk-sha256.txt`, `fixture-sha256.txt` (including the
   `expected_damaged_sha256=` line), `device-identity.txt`, and the
   marker-filtered logcat in the evidence directory.
8. Cleanup: the driver removes staging and clears test app data; it never
   modifies another worktree's allocation.

## 9. Artifacts

Directory `artifacts/2026-11-21-t071a-composition/`:

- `NOT-RUN.md` (historical correction-1 preflight blocker)
- `README.md`
- `device-identity-preflight.txt` (historical)
- `orca-emulator-devices.json` (historical)
- `orca-emulator-sessions.json` (historical)
- `git-identity-base.txt`
- `host-gates.txt` (original delivery)
- `correction-2-host-gates.txt` — 1466 bytes, SHA-256
  `54b04c586313a233c0a5a04ceb378d2fbcde402f68aa82917d410e067c2077bb`
- `correction-2-fixture-damage.txt` — 790 bytes, SHA-256
  `f9c236f1965a50d88cf810ccd59307d26c73ea94f6925ae6ec5155200cf6ac9f`

No APK, screenshot, logcat, or document content is stored.

## 10. Review

- Reviewer:
- Date:
- Verdict:
- Notes:
