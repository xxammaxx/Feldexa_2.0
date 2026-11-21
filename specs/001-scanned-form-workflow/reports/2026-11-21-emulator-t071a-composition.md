# T071A editor review/fill composition — correction 4 host evidence and Pixel 7 API 35 emulator PASS

- **Task / issue**: T071A / <https://github.com/xxammaxx/Feldexa_2.0/issues/244>
- **Feature**: `specs/001-scanned-form-workflow` US3/US4
- **Date**: 2026-11-21 (local)
- **Host evidence class**: `NONE` (host-VM analyze, format, widget/unit tests)
- **Emulator evidence class**: `EMULATOR` — **`PASS`** (correction 4)
- **Overall result**: `PASS` — the correction-4 candidate `f342cc4` is
  host-green and the full five-phase real journey passed on the Orca-attached
  Pixel 7 API 35 emulator. T071 remains blocked for its separate Android touch
  test; T097/OD-4 remain blocked.

## 0. Machine-first handoff

```json
{
  "task": "T071A",
  "issue": 244,
  "branch": "xxammaxx/t071a",
  "base_commit": "127f978f44911ef7a8c53b7c696bf5218915ae6c",
  "correction_2_base_commit": "e83ac25e7c177a455812204b7f12279f40bade71",
  "correction_3_base_commit": "771abede9c847693c9f520cbe8c4312984b1165b",
  "correction_4_base_commit": "dabdef3be7c81adaa9176c4b50d327395a217593",
  "candidate_commit": "f342cc42583565f148ffbc1f11ab0b6b2ff2575f",
  "candidate_tree": "cc996d8768ad558422663b9c950e10c3e8f0f97f",
  "evidence_commit": "external dispatch handoff; the documentation commit's own SHA/tree cannot be embedded in its own bytes",
  "host_evidence_class": "NONE",
  "emulator_evidence_class": "EMULATOR",
  "overall_result": "PASS",
  "correction": 4,
  "host_counts": {
    "focused_combined_editor_composition_and_field_value_sheet": 21,
    "editor_composition_only": 12,
    "field_value_sheet": 9,
    "app": 431,
    "application": 177
  },
  "host_gates": {
    "app_analyze": "exit 0, no issues",
    "application_analyze": "exit 0, no issues",
    "format": "exit 0, 8 files, 0 changed (pre-test); regression test file 1 file, 0 changed",
    "focused": "21/21 passed (editor_composition 12 + field_value_sheet 9)",
    "app_suite": "431/431 passed",
    "application_suite": "177/177 passed",
    "git_diff_check": "exit 0, clean",
    "overall_exit": 0
  },
  "emulator": {
    "driver": "tools/android/t071a_drive_composition.sh",
    "driver_result": "PASS",
    "run_status": "result=PASS, flutter_test_exit=0",
    "integration_log_end": "03:26 +1: All tests passed!",
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
    "apk": {
      "path": "apps/feldexa_app/build/app/outputs/flutter-apk/app-debug.apk",
      "bytes": 173200893,
      "sha256": "4780e50dde80c7fd10409ddbcdc15c10489bb5c00c463e7292df00bc71a020fe"
    },
    "fixture": {
      "bytes": 5956,
      "sha256": "22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038",
      "damaged_sha256": "57c1ade1ab2c00375ac61703db3d4ce5d27b996ea067647aba585866dc6ec221"
    },
    "screenshots": {
      "overlay-selection": "254974 bytes, SHA-256 b58a8b584bfc9f67ccdcdae0dac60954180e5a866f321a814542be227e2431cc",
      "value-sheet": "183025 bytes, SHA-256 cd560fd34eb5290853d380431672bb3541a330f4f82eca59d919dbe6947c208c",
      "saved-status": "185182 bytes, SHA-256 6fa09bbed76007ba8078d9e91fd68a3612c2d009dc1d7a6fb6270d6a383c4d9c",
      "document-list": "102203 bytes, SHA-256 81275c2a0548e675bd8af0aec1bb703583b3e2ae3d3c46c7ca2d2d92886f4ecf",
      "reopened-value": "185135 bytes, SHA-256 ed9cd6dd4d651ad20295d9fae75d8ea626f135ae854280437f3dce611e12db57"
    },
    "screenshot_hashes_distinct": true,
    "markers_source": "artifacts/2026-11-21-t071a-composition/markers-integration.txt (57 lines)",
    "privacy_checks": "PASS (log and source checks)",
    "no_renderflex_overflow_in_journey_log": true
  },
  "not_run": [
    "signature asset editing (still visibly NOT_RUN in the value sheet)",
    "layout overflow measurement beyond the journey and host no-overflow checks",
    "template open route (no template editor route in T071A)",
    "TalkBack/accessibility traversal and visual/golden inspection",
    "T071 Android touch drag/resize test (T071 remains blocked)",
    "T097/OD-4 (remain blocked)",
    "DEVICE acceptance and any performance claim"
  ]
}
```

Historical correction-2 and correction-3 state remains in §2 and §2A. The
correction-2/3 machine handoffs are preserved in git history and are superseded
by this block.

## 1. Revision and scope

- Base: `127f978f44911ef7a8c53b7c696bf5218915ae6c` (`main`, T071A
  authorization docs).
- Correction-1 base: `e83ac25e7c177a455812204b7f12279f40bade71`; correction 1
  (`8a51b8e`, `e83ac25`) fixed only the driver's app-package selection and
  worktree-bound Orca session resolution.
- Correction-3 base: `771abede9c847693c9f520cbe8c4312984b1165b` (correction-2
  candidate). The correction-3 candidate was `dabdef3`.
- **Correction-4 candidate: `f342cc42583565f148ffbc1f11ab0b6b2ff2575f`, tree
  `cc996d8768ad558422663b9c950e10c3e8f0f97f`.**
- Worktree: `<repo-root>` (`t071a-composition`).
- Branch: `xxammaxx/t071a`.
- This evidence commit Y is documentation/evidence plus one test-only
  regression change: `apps/feldexa_app/test/editor_composition_test.dart` gains
  the F9 empty-page stale-selection test. Production app source remains
  identical to `f342cc4`; no other production or test file changes, and the
  application package/suite remains unchanged at 177/177.
- The report is committed on the candidate branch. Its own commit SHA/tree
  cannot be embedded in its bytes; the dispatch handoff carries those values
  externally.
- The pre-existing unstaged `apps/feldexa_app/android/gradlew.bat` line-ending
  change was not touched, staged, or committed.
- No push, PR, merge, `main` edit, Gradle file, core, ports, recognition,
  recognition-output, ARB, or generated-localization change was made.

### 1.1 Correction-4 scope record (F4)

The 2026-11-21 owner directive orders completion of correction 4's review
findings F1–F7. The correction depends on the explicitly listed files below.
This is the ratified T071A correction scope, not a new architecture:

- correction 1: `tools/android/t071a_drive_composition.sh`;
- correction 2: `apps/feldexa_app/lib/features/editor/editor_runtime_android.dart`,
  `apps/feldexa_app/lib/features/editor/editor_screen.dart`,
  `apps/feldexa_app/lib/features/editor/page_view.dart` (diagnostics only),
  `apps/feldexa_app/integration_test/android_review_composition_test.dart`,
  `apps/feldexa_app/test/editor_analysis_test.dart`,
  `tools/android/t071a_drive_composition.sh`;
- correction 3: `apps/feldexa_app/lib/features/editor/editor_screen.dart`,
  `apps/feldexa_app/integration_test/android_review_composition_test.dart`;
- correction 4: `packages/feldexa_application/lib/src/review/set_value.dart`,
  `packages/feldexa_application/test/set_value_test.dart`,
  `apps/feldexa_app/lib/features/editor/field_value_sheet.dart`,
  `apps/feldexa_app/lib/features/editor/editor_screen.dart`,
  `apps/feldexa_app/lib/features/start/stored_items.dart`,
  `apps/feldexa_app/test/editor_composition_test.dart`,
  `apps/feldexa_app/test/field_value_sheet_test.dart`,
  `apps/feldexa_app/integration_test/android_review_composition_test.dart`,
  `tools/android/t071a_drive_composition.sh`.

The original delivery additionally composed `start_screen.dart`. There is no
change to core, ports, recognition, ARB/localization sources, Gradle files, or
`pubspec.yaml`, and no new architecture, orchestrator, port, or store.

## 2. Correction 2 — historical (superseded by correction 4)

Correction 1 made the real emulator journey proceed past the driver preflight.
That run exposed the actual composition stall described below.

### 2.1 Proven root cause

On `e83ac25` the real journey reached `T071A_EDITOR_READY`, the viewer rendered,
and analysis reached page-1 raster/OCR. It then blocked synchronously on the
undamaged `sf-001` page 2 inside `GeometryDetector._detectBoxes`
(`packages/feldexa_recognition/lib/src/geometry_detector.dart`): a CPU-bound
quadruple rule loop (`horizontals` × `horizontals` × `verticals` × `verticals`)
with corner/ink checks. Because that work is synchronous on the UI isolate,
`Future.timeout` and the widget-test pump loop cannot preempt it; the app stayed
in „Analyse ausstehend“ and the journey never reached `T071A_ANALYSIS_READY`.
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

- The committed `sf-001.pdf` is loaded from the app-readable device staging
  directory and verified as 5956 bytes with SHA-256
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

### 2.4 Diagnostics

Content-free `T071A_DIAG_*` markers (debug builds only) cover editor runtime
load, editor load/content/analysis, raster/OCR adapters, and viewer/source
render state. Markers contain only names, page indexes, counts, byte presence,
booleans, dimensions, stable categories/keys, and error type names. No id,
path, URI, title, label, OCR text, entered value, or hash of document content
is printed. The integration test waiter fails immediately with
`T071A_ANALYSIS_FAILED` plus per-page
`T071A_ANALYSIS_PAGE:P=<n>:STATE=<state>:KEY=<key>` markers.

## 2A. Correction 3 — historical (superseded by correction 4)

Start HEAD: `771abede9c847693c9f520cbe8c4312984b1165b` (correction-2 candidate,
host green: app 420, application 174). The correction-2 journey reached
analysis with 28 suggestions, suggestion confirmation, the overlay/selection
screenshot, the value sheet, a verified value save with store read-back, and
the saved-status screenshot. It then failed on two defects.

### 2A.1 Root causes

1. **Editor body overflow with the IME open.** The body `Column` kept
   `PageStrip`, the optional `IMP-006` warning, and up to 320 dp
   `SuggestionReviewPanel` as fixed children, followed by one
   `Expanded(PageView)`. With the keyboard open, the Scaffold shrank the body
   until the fixed children exceeded it; the `Expanded` page was forced to 0
   and the `Column` overflowed (`RenderFlex overflowed by 59 px`). The same
   failure class existed at 200 % text scale.
2. **Test/route race.** The post-pop `_pumpUntil` returned as soon as the start
   list and stored item appeared. The popped `EditorScreen` route could still
   be present for a reverse-transition frame, so the immediately following
   `expect(find.byType(EditorScreen), findsNothing)` failed. This was a
   test-observation defect, not app behavior.

### 2A.2 Fix

- `editor_screen.dart`: `PageStrip` stays fixed under the app bar. The warning
  and review panel moved into the trailing `Expanded` region, which uses
  `LayoutBuilder` and computes
  `maxHeaderHeight = (constraints.maxHeight - _minPageViewportHeight).clamp(0.0, double.infinity)`
  with a documented `const double _minPageViewportHeight = 160`. The header is
  a `ConstrainedBox(maxHeight: maxHeaderHeight)` + `SingleChildScrollView` +
  `Column(mainAxisSize: MainAxisSize.min)` holding the warning and panel; the
  unchanged `PageView` follows as the only flex child.
- `android_review_composition_test.dart`: the post-pop `_pumpUntil` condition
  also requires `find.byType(EditorScreen).evaluate().isEmpty`; a
  `tester.pumpAndSettle()` runs before the unchanged
  `expect(find.byType(EditorScreen), findsNothing)`. No assertion was weakened
  and no app behavior was changed.

### 2A.3 Correction-3 host gates (historical)

| # | Command | Exit | Result |
| ---: | --- | ---: | --- |
| 1 | `cd apps/feldexa_app && flutter analyze --no-pub` | 0 | No issues found |
| 2 | `cd packages/feldexa_application && dart analyze` | 0 | No issues found |
| 3 | `cd apps/feldexa_app && dart format --output=none --set-exit-if-changed lib/features/editor/editor_screen.dart integration_test/android_review_composition_test.dart` | 0 | 2 files, 0 changed |
| 4 | `cd apps/feldexa_app && flutter test --no-pub test/editor_composition_test.dart` | 0 | **10/10** passed |
| 5 | `cd apps/feldexa_app && flutter test --no-pub` | 0 | **420/420** passed |
| 6 | `cd packages/feldexa_application && flutter test --no-pub` | 0 | **174/174** passed |
| 7 | `git diff --check` (repo root) | 0 | clean |

The correction-3 run passed on `emulator-5554`, but its `saved-status` capture
was pixel-identical to `overlay-selection`; correction 4 supersedes that
evidence defect (F5).

## 2B. Correction 4 — current candidate `f342cc4`

### 2B.1 Review findings and root causes

Correction 3 passed its host gates and the real journey but still had blocking
review findings F1/F3/F6/F7/F9 and evidence defects F2/F5/F8. The common thread
was state that was asserted or captured before it was actually true:

- a value save left the old incompatibility validation flag on the field, so
  the corrected revision violated the core invariant;
- unreadable rows relied on a defensive callback refusal instead of being
  disabled;
- the value sheet constructed text values without pre-checking the model
  limits, so invalid input threw instead of showing the catalog error;
- committed text edits from focus loss/Enter/done were not wired to the save
  path;
- an empty page omitted the selection surface, so an empty-space tap could not
  clear selection;
- the evidence phases captured before the asserted state (sheet before IME and
  entered value) and reused the same settled editor frame for two phases.

### 2B.2 F1 — compatible replacement resolves the incompatibility flag

`setFieldValue` replaced `values[fieldId]` but copied the field validation
unchanged. When the previous value was an `IncompatibleValue`, the new concrete
value still carried the `incompatible_content` warning or the blocking
number/date parse error. `RevisionContent` requires an `IncompatibleValue` to
carry that flag, so the corrected snapshot was invalid and the warning/error
survived a valid correction.

Fix (`packages/feldexa_application/lib/src/review/set_value.dart`): when the
previous value is an `IncompatibleValue` and it was flagged by
`WarningCode.incompatibleContent` or a blocking parse error, only that field's
validation is replaced by `FieldValidation.ok`, preserving the validation's
unknown JSON fields. Every other revision member stays copied unchanged. An
incompatible replacement, including an explicit `IncompatibleValue` for a typed
field, still throws the content-free `ArgumentError` and mutates nothing.

### 2B.3 F3 — unreadable stored rows are disabled

`_StoredItemEntry` wrapped every row in an `InkWell` with an `onTap` callback,
including rows whose status was `StoredItemStatus.unreadable`. The start screen
had a defensive refusal, but the row still produced a ripple and invoked the
open callback before that refusal.

Fix (`apps/feldexa_app/lib/features/start/stored_items.dart`): `onTap` is
`null` for an unreadable entry, so there is no tap handler, no ripple, and no
route into a store load. The visible unreadable status and the optional delete
action remain. The start screen keeps its own defensive refusal.

### 2B.4 F6 — text/multiline limits are validated before value construction

The sheet constructed `TextValue`/`MultilineValue` from raw input. Input over
10,000 runes or containing control characters made the core constructor throw
instead of showing the catalog sentence, and the sheet could not keep the user
in the open editor.

Fix (`apps/feldexa_app/lib/features/editor/field_value_sheet.dart`):
`_isTextWithinModelLimits` counts runes and rejects control characters
(`< 0x20`, `0x7F..0x9F`), allowing `\n` only for multiline. Invalid text never
reaches a value constructor: the sheet stays open, shows the German catalog
`SAVE-007` sentence via `fieldValueErrorKey`, stores nothing, and does not
truncate. The check mirrors the core constructor without calling a throwing
constructor.

### 2B.5 F7 — all commit triggers use the validated save path

`T079`'s `onCommitted` reports focus loss, single-line Enter, and the multiline
done action, but the sheet only saved through the explicit button. A text edit
could therefore be lost on focus loss, or a close could accidentally save.

Fix (`field_value_sheet.dart`): `_commit` assigns the current text and calls the
same validated `_save()` path used by the save button. `_closing` is set before
the explicit close pops the sheet, so the focus loss caused by closing is
ignored and cancels without saving. Busy handling, failure messages, and the
`saved` claim semantics are unchanged; a failed save keeps the sheet open and
editable.

### 2B.6 F9 — the selection surface exists on an empty page

The per-page overlay builder returned `SizedBox.shrink()` when a page had no
overlay items. That removed the `FieldSelectionSurface` as well, so a tap on
empty page space could not clear an existing selection.

Fix (`apps/feldexa_app/lib/features/editor/editor_screen.dart`): the `Stack`
and `FieldSelectionSurface` are always composed; only the painted
`FieldOverlay` is omitted when the item list is empty. Empty-page taps now
reach the selection surface and clear the selection.

### 2B.7 F2/F5/F8 — evidence fixes

- **F2 (value-sheet phase):** the test now waits for the sheet key and a real
  IME inset of at least 100 dp, enters the German value, and asserts the sheet
  box, input, and save button are above the keyboard before emitting the
  screenshot marker. The driver deletes a stale acknowledgement before waiting
  for a fresh one, so a screenshot cannot belong to an earlier state.
- **F5 (distinct, honest screenshots):** `saved-status` now reopens the sheet
  immediately after the verified save, prefilled from the store read-back, with
  the T091 saved label in the app bar behind it; `reopened-value` reopens the
  sheet on the reopened document. All five captures have distinct SHA-256
  values, and no phase claims a bare editor when it shows the sheet.
- **F8 (identity and marker binding):** `git-identity.txt` records HEAD
  `f342cc4` and tree `cc996d8`; `orca-emulator-sessions.json` shows the Orca
  Android session bound to this worktree; `markers-integration.txt` is the
  authoritative 57-line host-side marker sequence. T071A markers are emitted by
  the integration test process, not by the app process, so device logcat
  cannot contain them; `logcat-t071a-markers.log` holds only Android lifecycle
  lines.

### 2B.8 F4 — ratified correction scope

The 2026-11-21 owner directive orders completion of this correction round
(F1–F7), and correction 4 depends on the files listed in §1.1. The scope record
is therefore explicit: no core, ports, recognition, ARB/localization, Gradle,
or `pubspec.yaml` change, and no new architecture. The earlier unratified
deviation is replaced by this documented owner basis.

### 2B.9 New and updated tests

- `apps/feldexa_app/test/field_value_sheet_test.dart` (new, **9 tests**):
  text over 10,000 runes refused; text control character refused; multiline
  over 10,000 runes refused; single-line done commits once and closes; focus
  loss commits once and closes; multiline done commits once and closes;
  explicit save commits once and closes; failed save keeps the sheet open and
  editable; explicit close cancels without a focus-loss save.
- `apps/feldexa_app/test/editor_composition_test.dart` (**12 tests**: the 11
  correction-4 tests plus Y's one F9 regression test): adds the value sheet
  above the software keyboard assertion and the empty-page stale-selection
  regression; the existing overlay, suggestion, parser, verified save, failed
  save, start-list, unreadable, and 200 % text-scale coverage remains.
- F9 regression test: the content has no fields and no suggestions; the test
  selects `stale-selection`, taps empty page space, and expects
  `selectedId == null`. It fails on the pre-fix `items.isEmpty ->
  SizedBox.shrink` behavior, where no selection surface existed, and passes
  with the always-composed selection surface.
- `packages/feldexa_application/test/set_value_test.dart` (**13 tests**, +3):
  compatible text replacement clears the incompatible-content warning;
  compatible number replacement clears a blocking parse error; incompatible
  replacement keeps the warning and mutates nothing. The previous all-six-type,
  mismatch, preservation, previous-content, and untruncated-text coverage
  remains.
- Focused combined total: **21/21** (`editor_composition_test` 12 +
  `field_value_sheet_test` 9). Editor-only: **12/12**. Full app: **431/431**.
  Full application: **177/177**.

### 2B.10 Correction-4 host gates

All commands ran in this worktree on the correction-4 working tree. The exact
terminal lines are in `artifacts/2026-11-21-t071a-composition/correction-4-host-gates.txt`.
See §5 for the table.

### 2B.11 Correction-4 emulator run

Command (repo root, exclusive Orca `emulator-5554` session attached to this
worktree):

```sh
T071A_REPLACE_EVIDENCE=1 tools/android/t071a_drive_composition.sh
```

The driver exited `PASS`; `run-status.txt` records `result=PASS` and
`flutter_test_exit=0`. The integration log ends with `All tests passed!`
(`03:26 +1`). See §6 for device, APK, fixture, marker, and screenshot details.

### 2B.12 Screenshot semantics

| Phase | What the image actually shows |
| --- | --- |
| `overlay-selection` | Settled editor with the confirmed field selected; no value sheet. |
| `value-sheet` | Value sheet with the entered German value above the real IME. |
| `saved-status` | Value sheet reopened immediately after the verified save, prefilled from the store read-back; the T091 saved label is in the app bar behind it. |
| `document-list` | Start list after leaving the editor. |
| `reopened-value` | Reopened document's value sheet prefilled from the reopened store read-back. |

All five hashes are distinct (see §6.5 and `screenshot-hashes.txt`). No phase is
described as a bare editor when it shows the sheet.

### 2B.13 Correction-4 `NOT_RUN`

- Signature asset editing (still visibly `NOT_RUN` in the value sheet).
- Layout overflow measurement beyond the host no-overflow composition test and
  the real journey log.
- Opening a stored template (no template editor route in T071A).
- TalkBack/accessibility traversal and visual/golden inspection.
- T071 Android touch drag/resize acceptance; T071 stays blocked.
- T097/OD-4 remain blocked.
- `DEVICE` acceptance and any performance claim.

## 3. Changed files

Correction-4 code, test, integration, and driver files on `f342cc4`:

1. `packages/feldexa_application/lib/src/review/set_value.dart` — compatible
   replacement resolves the field's incompatibility validation; incompatible
   replacement remains content-free and non-mutating.
2. `packages/feldexa_application/test/set_value_test.dart` — three new tests.
3. `apps/feldexa_app/lib/features/editor/field_value_sheet.dart` — text limits,
   shared commit path, close-cancel guard, keyboard-safe sheet box.
4. `apps/feldexa_app/lib/features/editor/editor_screen.dart` — empty-page
   selection surface.
5. `apps/feldexa_app/lib/features/start/stored_items.dart` — unreadable rows
   disabled.
6. `apps/feldexa_app/test/editor_composition_test.dart` — IME sheet assertion.
7. `apps/feldexa_app/test/field_value_sheet_test.dart` — new sheet test file.
8. `apps/feldexa_app/integration_test/android_review_composition_test.dart` —
   asserted screenshot phases, IME wait, fresh acknowledgement.
9. `tools/android/t071a_drive_composition.sh` — evidence and handshake
   corrections.

This evidence commit changes only documentation and the artifact bundle:

10. `specs/001-scanned-form-workflow/reports/2026-11-21-emulator-t071a-composition.md`
    (this report).
11. `specs/001-scanned-form-workflow/reports/artifacts/2026-11-21-t071a-composition/`
    (updated run evidence, five screenshots, `markers-integration.txt`,
    `screenshot-hashes.txt`, `correction-4-host-gates.txt`,
    `correction-4-command-binding.txt`, bundle `README.md`).
12. `specs/001-scanned-form-workflow/reports/README.md` (index).
13. `specs/001-scanned-form-workflow/tasks.md` (T071A row only; checkbox stays
    open until integration).

No `apps/feldexa_app/pubspec.yaml` change was authorized. The app consumes the
existing `feldexa_ui` workspace package through the workspace package config and
carries a documented `// ignore_for_file: depend_on_referenced_packages` on the
editor import. A later dependency-declaration task should add the app path
dependency.

## 4. Delivered behavior (current)

### 4.1 Overlay and selection

- Every visible page receives `overlayBuilder(pageIndex, viewportRect, mapping)`
  inside its page box. The builder composes `FieldOverlay` when items exist and
  always composes `FieldSelectionSurface`; it does not mutate geometry or the
  view transform.
- Overlay items are filtered explicitly by `pageIndex`; confirmed fields use
  `FieldOverlayItem.fromConfirmedField` and only `unresolved` suggestions use
  `FieldOverlayItem.fromSuggestion`.
- `FieldOverlayItem.selected` stays false; the selection accent is painted only
  by T077, so there is no double accent.
- A tap on a confirmed field selects it and opens `FieldValueSheet`; a tap on a
  suggestion selects/highlights it and never invents a value; a tap on empty
  page space clears the selection (F9).

### 4.2 `setFieldValue`

- Requires an existing field and the exact matching concrete value: text,
  multiline, number, date, checkbox, signature. `IncompatibleValue` is
  rejected as a new edit.
- Stamps the caller-supplied UTC `lastEditedAt`.
- Replaces only `values[fieldId]`, plus the one validation flag that pointed at
  preserved incompatible content; pages, suggestions, other fields, order,
  signatures, verification, template origin, and unknown JSON fields are
  copied.
- A compatible concrete replacement of preserved incompatible content resolves
  the `incompatible_content` warning or blocking parse error to `ok` (F1).
- Returns `SetValueChange` with the previous snapshot/value. Failures are
  content-free `ArgumentError`s.

### 4.3 Value sheet and save

- T079 text/multiline; T080 `parseGermanNumber`; T081 `parseGermanDate` with the
  catalog `NUM-001`/`DATE-001`/`DATE-002` sentences; T082 checkbox; T084
  warning when the stored value already carries `overflow`.
- Invalid number/date input remains in the open sheet and is never handed to
  the command. Text/multiline input over 10,000 runes or with a control
  character is refused with the German `SAVE-007` sentence before a value is
  constructed; the sheet stays open and stores nothing (F6).
- The explicit save button, focus loss, single-line Enter, and the multiline
  done action all run the same validated save path. The explicit close cancels
  without a focus-loss save (F7).
- Commit runs `setFieldValue`, then `runtime.saveRevision` with
  `expectedHead = _headRevisionId` and `kind = autosave`. `_content`,
  `_headRevisionId`, `_lastDurableAt`, and the T091 saved state are updated only
  from the verified `StoredMeta`.
- A failed save keeps the sheet and prior content editable, shows the
  content-free `SAVE-*` sentence, and shows
  `DurabilityStatus.saveFailed(code)`; no optimistic saved claim is made.
- The sheet is keyboard-safe: the real IME inset lifts the visible sheet box,
  and its height is bounded so the title, control, save, and close actions stay
  reachable.
- The app bar hosts `DurabilityStatusLabel`. PRIV-001 is available through the
  existing `PrivacyKeyDisclosure` in an app-bar action dialog.
- Signature editing is visibly `NOT_RUN`; no signature asset is fabricated.

### 4.4 Start list and reopen

- When `ImportRuntime.store` is non-null, the start surface always renders T095
  `StoredItemsView` for `StoreKind.document` and `StoreKind.template`.
- A readable document is loaded through the existing store; metadata/source
  identity and persisted page geometry build an `ImportedSource`; the editor
  opens with those verified bytes.
- Unreadable entries remain visible with the T095 unreadable status, have no tap
  handler or ripple, and are refused before any store load (F3).
- Returning from the editor re-reads both list groups.
- A template row is visible when present but has no template editor route in
  T071A.
- Without a store, the previous import-only start surface is unchanged.

## 5. Host gates (evidence `NONE`)

All gates ran in this worktree on the correction-4 working tree. The pre-test
run is recorded verbatim (apart from one normalized trailing-padding line) in
`artifacts/2026-11-21-t071a-composition/correction-4-host-gates.txt`; the
post-review F9 regression run is recorded in
`artifacts/2026-11-21-t071a-composition/correction-4-regression-host-gates.txt`.

| # | Command | Exit | Result |
| ---: | --- | ---: | --- |
| 1 | `cd apps/feldexa_app && flutter analyze --no-pub` (post-test Y working-tree analyze, including the new `editor_composition_test.dart` regression test; log `/tmp/t071a-y-analyze.log`) | 0 | No issues found! (ran in 46.0s) |
| 2 | `cd packages/feldexa_application && dart analyze` | 0 | No issues found |
| 3 | `dart format --output=none --set-exit-if-changed` over the eight correction-4 Dart files | 0 | 8 files, 0 changed (pre-test) |
| 4 | `cd apps/feldexa_app && flutter test --no-pub test/editor_composition_test.dart test/field_value_sheet_test.dart` | 0 | **21/21** passed (editor_composition 12 + field_value_sheet 9) |
| 5 | `cd apps/feldexa_app && flutter test --no-pub` | 0 | **431/431** passed |
| 6 | `cd packages/feldexa_application && flutter test --no-pub` | 0 | **177/177** passed |
| 7 | `git diff --check` (repo root) | 0 | clean |

The pre-test host-gates file records the correction-4 candidate counts before
Y's regression test: focused 20/20 and app 430/430. Y adds exactly one test, so
the post-review counts are focused combined 21/21 (editor-only 12/12) and full
app 431/431; the application suite stays 177/177. `OVERALL_EXIT=0`.

The focused combined 21 tests are `editor_composition_test.dart` (12,
including Y's F9 regression) plus `field_value_sheet_test.dart` (9); the
editor-only command is 12/12. The full application suite includes
`set_value_test.dart` at 13 tests. The app suite retains the original
composition coverage: overlay hook page/rect/mapping, confirmed-field tap
opening the sheet, suggestion tap without a sheet, number/date parser rejection
and German input, verified save updating content/head/status, failed save
keeping the sheet with `SAVE-003`, start-list load/reopen/reload, unreadable
refusal, 200 % text scale without RenderFlex overflow, and the value sheet
above the IME. The F9 regression selects a stale id on a page with no overlay
items and proves an empty-page tap clears it.

## 6. Emulator acceptance — correction 4 `EMULATOR` `PASS`

### 6.1 Run and result

- Driver: `tools/android/t071a_drive_composition.sh` (exclusive Orca session
  bound to this worktree).
- Command: `T071A_REPLACE_EVIDENCE=1 tools/android/t071a_drive_composition.sh`.
- Result: driver `PASS`; `run-status.txt` = `result=PASS`,
  `flutter_test_exit=0`; integration log ends `03:26 +1: All tests passed!`.
- The journey log contains no `RenderFlex`, overflow, or exception line.
- Privacy: `privacy-log-check.txt` PASS (no document content or fixture path in
  the integration log) and `privacy-source-check.txt` PASS (no network API
  reference in the integration test).

### 6.2 Device and build identity

- Device: serial `emulator-5554`, AVD `T025_Pixel7_API35_KVM_20261115`,
  Android 15 / SDK 35, `x86_64`, fingerprint
  `google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys`,
  1080x2400 at density 420.
- APK: `apps/feldexa_app/build/app/outputs/flutter-apk/app-debug.apk`,
  **173200893 bytes**, SHA-256
  `4780e50dde80c7fd10409ddbcdc15c10489bb5c00c463e7292df00bc71a020fe`.
- Fixture: 5956 bytes, SHA-256
  `22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038`;
  in-test T061 damaged derivation 5956 bytes, SHA-256
  `57c1ade1ab2c00375ac61703db3d4ce5d27b996ea067647aba585866dc6ec221`.

### 6.3 Authoritative marker sequence

`artifacts/2026-11-21-t071a-composition/markers-integration.txt` (57 lines):

```text
T071A_FIXTURE_READY:BYTES=5956:MATCH=1
T071A_DAMAGED_FIXTURE_READY:BYTES=5956:MATCH=1
T071A_START_LIST_READY
T071A_IMPORT_ARMED
T071A_DIAG_LOAD_START
T071A_DIAG_RUNTIME_LOAD_START
T071A_DIAG_VIEW_OPEN_START
T071A_DIAG_RUNTIME_PDFRX_READY
T071A_EDITOR_READY
T071A_DIAG_RUNTIME_LOAD_OK:PAGES=2:BYTES=1:SUGGESTIONS=0
T071A_DIAG_LOAD_OK:PAGES=2:BYTES=1:SUGGESTIONS=0
T071A_DIAG_CONTENT_SET:PAGES=2:SUGGESTIONS=0:STRIP=2
T071A_DIAG_ANALYSIS_START:PAGES=1:UNREADABLE=1:SOURCE_BYTES=1:OCR=1
T071A_DIAG_RASTER_START:P=0:SCALE=2.7777777777777777:FORMAT=gray8
T071A_DIAG_VIEW_BYTES:PRESENT=1
T071A_DIAG_VIEW_INIT_START
T071A_DIAG_VIEW_INIT_OK
T071A_DIAG_VIEW_DOCUMENT_OPEN_OK:PAGES=2
T071A_DIAG_VIEW_OPEN_OK:PAGES=2:EXPECTED=2
T071A_DIAG_PAGE_RENDER_START:P=0:W=1080:H=1527
T071A_DIAG_RASTER_OK:P=0:W=1654:H=2339
T071A_DIAG_OCR_START:P=0
T071A_DIAG_PAGE_RENDER_OK:P=0:W=1080:H=1527
T071A_DIAG_OCR_OK:P=0:BLOCKS=25
T071A_DIAG_ANALYSIS_RESULT:PAGES=1:CANCELLED=0
T071A_DIAG_ANALYSIS_PAGE:P=0:STATUS=complete:SUGGESTIONS=28:UNCERTAIN=0
T071A_DIAG_ANALYSIS_APPLIED:PAGES=2:SUGGESTIONS=28:UNCERTAIN=0
T071A_DIAG_ANALYSIS_SAVE_START
T071A_DIAG_ANALYSIS_SAVE_OK
T071A_DIAG_ANALYSIS_STATE:ready
T071A_ANALYSIS_READY:STATE=analysis-ready:PAGES=2:SUGGESTIONS=28:CONFIRMED=0
T071A_FIELD_CONFIRMED
T071A_T071A_SCREENSHOT_OVERLAY_SELECTION
T071A_T071A_SCREENSHOT_VALUE_SHEET
T071A_VALUE_SAVED
T071A_SAVED_READBACK:OK
T071A_T071A_SCREENSHOT_SAVED_STATUS
T071A_START_LIST_RELOADED
T071A_T071A_SCREENSHOT_DOCUMENT_LIST
T071A_DIAG_LOAD_START
T071A_DIAG_RUNTIME_LOAD_START
T071A_DIAG_VIEW_OPEN_START
T071A_DIAG_RUNTIME_PDFRX_READY
T071A_DIAG_RUNTIME_LOAD_OK:PAGES=2:BYTES=1:SUGGESTIONS=28
T071A_DIAG_LOAD_OK:PAGES=2:BYTES=1:SUGGESTIONS=28
T071A_DIAG_CONTENT_SET:PAGES=2:SUGGESTIONS=28:STRIP=2
T071A_DIAG_ANALYSIS_STATE:skipped:PERSISTED=1
T071A_DIAG_VIEW_BYTES:PRESENT=1
T071A_DIAG_VIEW_INIT_START
T071A_DIAG_VIEW_INIT_OK
T071A_DIAG_VIEW_DOCUMENT_OPEN_OK:PAGES=2
T071A_DIAG_VIEW_OPEN_OK:PAGES=2:EXPECTED=2
T071A_DIAG_PAGE_RENDER_START:P=0:W=1080:H=1527
T071A_REOPENED_READBACK:OK
T071A_DIAG_PAGE_RENDER_OK:P=0:W=1080:H=1527
T071A_T071A_SCREENSHOT_REOPENED_VALUE
T071A_CLEANUP_DONE
```

The screenshot markers appear with a doubled `T071A_` prefix because the test's
`_marker` prepends `T071A_`. The driver's `marker-sequence.txt` records the five
screenshot handshakes and
`PASS (flutter test exit 0; cleanup marker observed; privacy checks PASS)`.

### 6.4 Marker/logcat limitation

T071A markers are emitted by the integration test process on the host side, not
by the app process. Device logcat cannot contain them; the captured
`logcat-t071a-markers.log` contains only `ActivityTaskManager` lifecycle lines
and `logcat-flutter.log` contains only engine/service lines. No absence of
markers in device logcat is evidence of a failed phase; `markers-integration.txt`
and `integration-android-t071a.log` are the authoritative records.

### 6.5 Screenshots

| Phase | Bytes | SHA-256 |
| --- | ---: | --- |
| `overlay-selection` | 254974 | `b58a8b584bfc9f67ccdcdae0dac60954180e5a866f321a814542be227e2431cc` |
| `value-sheet` | 183025 | `cd560fd34eb5290853d380431672bb3541a330f4f82eca59d919dbe6947c208c` |
| `saved-status` | 185182 | `6fa09bbed76007ba8078d9e91fd68a3612c2d009dc1d7a6fb6270d6a383c4d9c` |
| `document-list` | 102203 | `81275c2a0548e675bd8af0aec1bb703583b3e2ae3d3c46c7ca2d2d92886f4ecf` |
| `reopened-value` | 185135 | `ed9cd6dd4d651ad20295d9fae75d8ea626f135ae854280437f3dce611e12db57` |

All five hashes are distinct and match `screenshot-hashes.txt`. The phase
semantics are those in §2B.12; `saved-status` and `reopened-value` are sheet
captures, not bare-editor captures.

## 7. `NOT_RUN` register (correction 4)

- Signature asset editing through T083 (shown as `NOT_RUN` in the sheet).
- Layout overflow measurement beyond the host no-overflow composition test and
  the real journey log.
- Opening a stored template from the list (no template editor route).
- TalkBack/accessibility traversal and visual/golden inspection.
- T071 Android touch drag/resize acceptance; T071 stays blocked.
- T097/OD-4; both remain blocked.
- `DEVICE` acceptance and any performance claim.
- Text-scale visual rendering beyond the host RenderFlex check.
- Raw full logcat and the APK binary are not stored; T071A markers are not
  expected in device logcat (see §6.4).

## 8. Reproducibility

1. Check out the correction-4 candidate `f342cc4` (tree `cc996d8`) plus this
   evidence commit on the worktree.
2. `flutter pub get --offline` at the repository root.
3. Verify the committed fixture: 5956 bytes, SHA-256
   `22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038`;
   the in-test damage helper then yields the 5956-byte T061 source with SHA-256
   `57c1ade1ab2c00375ac61703db3d4ce5d27b996ea067647aba585866dc6ec221`.
4. Run the host gates in §5.
5. Request/attach an exclusive Orca Pixel 7 API 35 session to this worktree.
6. Run `T071A_REPLACE_EVIDENCE=1 tools/android/t071a_drive_composition.sh`.
7. Verify the five distinct screenshot hashes against `screenshot-hashes.txt`,
   the 57-line `markers-integration.txt`, `marker-sequence.txt`,
   `run-status.txt`, `apk-sha256.txt`, `fixture-sha256.txt`, `device-identity.txt`,
   and the marker sequence in `integration-android-t071a.log`.
8. Cleanup: the driver removes staging and clears test app data; it never
   modifies another worktree's allocation.

This documentation/evidence correction did not rerun the emulator or rebuild
the APK; the run evidence above is the recorded correction-4 run.

## 9. Artifacts

Directory `artifacts/2026-11-21-t071a-composition/`. Every byte count and
SHA-256 below was recomputed from the actual file in this worktree.

Byte-integrity note for the saved run evidence: the repository copy of
`device-identity.txt` is 298 bytes; the driver original at
`/tmp/t071a-fix4-run/device-identity.txt` is 300 bytes. The only difference is
trailing spaces stripped from the `wm_size` and `wm_density` lines; all values
are identical. The repository copy of `integration-android-t071a.log` is 3968
bytes; the driver original at `/tmp/t071a-fix4-run/integration-android-t071a.log`
is 3994 bytes. The only difference is trailing spaces stripped from one Gradle
progress line; all log content is identical. The repository copy of
`correction-4-host-gates.txt` is 140937 bytes; the handover original at
`/home/xxammaxx/Feldexa_Handover_2026-11-19/t071a-fix4-correction-4-host-gates.txt`
is 140977 bytes; the only difference is trailing padding stripped from one
`flutter analyze` line, with all commands, results, and exit codes identical.
The hashes below are computed from the committed repository copies, not from
the unstripped originals.

Historical and host files:

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `NOT-RUN.md` | 1928 | `e61be31e6648d8557e38efa6bc12045673cecf38af69ed8e860b048259e48a56` |
| `device-identity-preflight.txt` | 174 | `be687d5dd70a46e5714da039f9eca4b157ac512b7a848e6a1536e218d09e5630` |
| `orca-emulator-devices.json` | 1898 | `1232cfc05f1816d508467e39dc14ac2a5aa54350b4f5a83d84ef4e803d95ba37` |
| `git-identity-base.txt` | 165 | `11be89d1e1de17b9fe7bdd9ddbe8fa1cfab2a34bb2f5e2eb801d4e633898cb7a` |
| `host-gates.txt` | 1092 | `e129e71f839d4ffed9b2df60e673db4c99569428ba7f13335abdd1f5c985a491` |
| `correction-2-host-gates.txt` | 1466 | `54b04c586313a233c0a5a04ceb378d2fbcde402f68aa82917d410e067c2077bb` |
| `correction-2-fixture-damage.txt` | 790 | `f9c236f1965a50d88cf810ccd59307d26c73ea94f6925ae6ec5155200cf6ac9f` |
| `correction-3-host-gates.txt` | 1208 | `b3b1a989f26902425b97b1c80820a9ece3a62c1e04d9ff06de519e4f5a4d79f3` |

Correction-4 run bundle:

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `README.md` (bundle index) | 7359 | `305af26403e4d68a8837d2e6e58a23f9af7e296ebb7124f7493bb512770c5dba` |
| `correction-4-host-gates.txt` | 140937 | `209b0271a7a773e8c80aa2f568305d94a81a0b89622878ab54b7cbe0e011d9dd` |
| `correction-4-regression-host-gates.txt` | 2088 | `9cc74fcaedecc5b7d400174ab138e26b0f2c5a480f0e9bb0ee7ca151fa308936` |
| `correction-4-command-binding.txt` | 1086 | `3af12916081f69322da1eac3b555297e49d756104d95dadf0f14b8d284177209` |
| `git-identity.txt` | 355 | `1142cb341b9e738392709ff28e12dee06d906dec42cc9798d543dfe6bff88533` |
| `apk-sha256.txt` | 212 | `a315790811e0f76e71635a0f15a7dee8563f8e4fd2dfb769fe36b43dcdccdaaf` |
| `device-identity.txt` | 298 | `265c299fe643739f0c63d2fc73f638d221a7aa9322b021641ab53bc0fedbbf56` |
| `fixture-sha256.txt` | 510 | `86d2d2601208813244b65a065198f8b284da92683ea237b608ce2c122188d7b8` |
| `orca-emulator-sessions.json` | 486 | `03d694b2f924a006ce12c7e069a23bc449be42fdbfd85f3e9594c6457901eddd` |
| `host-flutter-pub-get.log` | 347 | `39e8b11c6d3c7aaf75f7af8ed55924e7b6c7eb89054116096fdb6b61470ea329` |
| `integration-android-t071a.log` | 3968 | `4ec5097c8a3cba2f92a1f6051fb91374fb086a68787d920c2425f58868a4ab89` |
| `logcat-flutter.log` | 315 | `214372c45c62ff9fe8292eeb1cd0fe6bff0e1b8cfcca9c1f3ecd81d72b3e558a` |
| `logcat-t071a-markers.log` | 901 | `aaa02ed6037c8ccba726a27230136010b3cb8aae5348b9a4507812315f7b4740` |
| `marker-sequence.txt` | 534 | `05a6d92df9a866cef59c7d0fa9d79c163e11e05ea85739dccdcbed3851e24a84` |
| `markers-integration.txt` | 2153 | `f808c353dc35c8b67051dd9ce874d1ba1a19fec104f0db9047c2411d1c1722e6` |
| `screenshot-hashes.txt` | 497 | `ee925b59c0899b4b95c028dec369c7dfd694d7c1bfbad8ed1bd5803805c01419` |
| `privacy-log-check.txt` | 65 | `7c1bcbf4be8b5984e329ec2afbf1f30214982fc899c13e17f3346fc1c0be22ea` |
| `privacy-source-check.txt` | 88 | `cff8cea0e7fea22b0c7ce47cfd57f6a616e7145653d2af07fde7d7b9be5b7005` |
| `run-status.txt` | 32 | `7fd607f90d24581a4b9b797cff3d71e0f238dc52f3f869fd23b88a688a94f0b3` |
| `screenshots/overlay-selection.png` | 254974 | `b58a8b584bfc9f67ccdcdae0dac60954180e5a866f321a814542be227e2431cc` |
| `screenshots/value-sheet.png` | 183025 | `cd560fd34eb5290853d380431672bb3541a330f4f82eca59d919dbe6947c208c` |
| `screenshots/saved-status.png` | 185182 | `6fa09bbed76007ba8078d9e91fd68a3612c2d009dc1d7a6fb6270d6a383c4d9c` |
| `screenshots/document-list.png` | 102203 | `81275c2a0548e675bd8af0aec1bb703583b3e2ae3d3c46c7ca2d2d92886f4ecf` |
| `screenshots/reopened-value.png` | 185135 | `ed9cd6dd4d651ad20295d9fae75d8ea626f135ae854280437f3dce611e12db57` |

No APK binary, raw full logcat, key material, or separate document-content
extract is stored. The screenshots necessarily show the synthetic fixture; no
text is transcribed.

## 10. Review

- Reviewer:
- Date:
- Verdict:
- Notes:
