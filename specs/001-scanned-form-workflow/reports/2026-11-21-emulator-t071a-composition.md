# T071A editor review/fill composition — host evidence and emulator NOT_RUN

- **Task / issue**: T071A / <https://github.com/xxammaxx/Feldexa_2.0/issues/244>
- **Feature**: `specs/001-scanned-form-workflow` US3/US4
- **Date**: 2026-11-21 (local)
- **Host evidence class**: `NONE` (host-VM analyze, format, widget/unit tests)
- **Emulator evidence class**: `EMULATOR` — **`NOT_RUN`**
- **Overall result**: `PARTIAL` — host composition delivered and green; the
  required real emulator journey did not execute because no Orca emulator
  session is attached to this worktree.

## 0. Machine-first handoff

```json
{
  "task": "T071A",
  "issue": 244,
  "base_commit": "127f978f44911ef7a8c53b7c696bf5218915ae6c",
  "branch": "xxammaxx/t071a",
  "candidate_commit": "the commit that adds this report; see external dispatch handoff",
  "candidate_tree": "see external dispatch handoff",
  "host_evidence_class": "NONE",
  "emulator_evidence_class": "EMULATOR_NOT_RUN",
  "overall_result": "PARTIAL",
  "host_counts": {
    "app_baseline": 409,
    "app_candidate": 419,
    "app_new": 10,
    "application_baseline": 164,
    "application_candidate": 174,
    "application_new": 10
  },
  "emulator_evidence_paths": [],
  "not_run": [
    "EMULATOR real journey and screenshots",
    "logcat markers and runtime logcat",
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
- Worktree: `/home/xxammaxx/Schreibtisch/Feldexa_2.0/t071a-composition`.
- Branch: `xxammaxx/t071a`.
- The report is committed on the candidate branch. Its own commit SHA/tree
  cannot be embedded in its bytes; the dispatch handoff carries those values
  externally.
- The pre-existing unstaged `apps/feldexa_app/android/gradlew.bat` line-ending
  change was not touched, staged, or committed.
- No push, PR, merge, `main` edit, Gradle file, core, ports, recognition,
  recognition-output, ARB, or generated-localization change was made.

## 2. Changed files

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

## 3. Delivered behavior

### 3.1 Overlay and selection

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

### 3.2 `setFieldValue`

- Requires an existing field and the exact matching concrete value:
  text, multiline, number, date, checkbox, signature. `IncompatibleValue` is
  rejected as a new edit.
- Stamps the caller-supplied UTC `lastEditedAt`.
- Replaces only `values[fieldId]`; copies pages, suggestions, fields, order,
  signatures, verification, template origin, and unknown JSON fields.
- Returns `SetValueChange` with the previous snapshot/value. Failures are
  content-free `ArgumentError`s.

### 3.3 Value sheet and save

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

### 3.4 Start list and reopen

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

## 4. Host gates (evidence `NONE`)

| Gate | Command | Result |
| --- | --- | --- |
| App analyze | `cd apps/feldexa_app && flutter analyze --no-pub` | exit 0, no issues |
| Application analyze | `cd packages/feldexa_application && dart analyze` | exit 0, no issues |
| Format | `dart format --output=none --set-exit-if-changed <changed Dart files>` | exit 0, 0 changed |
| Diff check | `git diff --check` (and `base..HEAD` after commit) | clean |
| Focused app composition | `flutter test --no-pub test/editor_composition_test.dart` | 8/8 passed |
| Focused value command | `flutter test --no-pub test/set_value_test.dart` | 10/10 passed |
| Full app suite | `flutter test --no-pub` in `apps/feldexa_app` | **419/419** passed (409 baseline + 10) |
| Full application suite | `flutter test --no-pub` in `packages/feldexa_application` | **174/174** passed (164 baseline + 10) |

`editor_composition_test.dart` covers the overlay hook page/rect/mapping, a
confirmed-field tap opening the sheet, a suggestion tap without a sheet, the
T080/T081 number/date parser rejection and successful German input, the verified
save updating content/head/status, a failed save keeping the sheet and old
content with `SAVE-003`, the start-list load/reopen/reload path, unreadable
refusal, and 200 % text scale without a RenderFlex overflow.

`set_value_test.dart` covers all six types, mismatch rejection, missing field,
non-UTC rejection, unchanged sibling values, preserved suggestions/fields/
order/signatures/verification/template origin/unknown fields, previous value/
content, and untruncated text.

## 5. Emulator acceptance — `NOT_RUN`

The real journey in `integration_test/android_review_composition_test.dart` and
`tools/android/t071a_drive_composition.sh` was **not executed**.

Reason: the Pixel 7 API 35 AVD `T025_Pixel7_API35_KVM_20261115` is booted on
`emulator-5554`, but `orca emulator list --json` reports no session attached to
this worktree. The coordinator instructed this worker not to rebind or reuse
another worktree's allocation. The driver stops at the preflight with exit 2
before clearing app data, installing, staging, or running anything.

Evidence: `artifacts/2026-11-21-t071a-composition/NOT-RUN.md`,
`device-identity-preflight.txt`, `orca-emulator-devices.json`, and
`orca-emulator-sessions.json`.

Consequently there are **no** T071A screenshots, logcat markers, APK SHA-256,
on-device fixture hash, runtime AVD/serial run record, saved-status visual
confirmation, or reopened-document visual confirmation. None of the host checks
above is presented as emulator evidence.

## 6. `NOT_RUN` register

- `EMULATOR` import/analysis/suggestion-confirmation/selection/value-sheet/
  save/leave/reopen journey.
- Five required screenshots and the screenshot acknowledgement handshake.
- APK build (attempted once and interrupted; no artifact or hash is claimed).
- Runtime logcat markers and privacy log check.
- On-device fixture SHA-256 and runtime device identity for a run.
- Signature asset editing through T083 (shown as `NOT_RUN` in the sheet).
- Overflow layout measurement (T084 only shows an already-marked overflow).
- Opening a stored template from the list (no template editor route).
- TalkBack/accessibility traversal and visual/golden inspection.
- T071 Android touch drag/resize acceptance; T071 stays blocked.
- `DEVICE` acceptance and any performance claim.
- Text-scale visual rendering beyond the host RenderFlex check.

## 7. Reproducibility

1. Check out the candidate branch on the worktree.
2. `flutter pub get --offline` at the repository root.
3. Run the four host gates in §4.
4. Request/attach an exclusive Orca Pixel 7 API 35 session to this worktree.
5. Run `tools/android/t071a_drive_composition.sh`.
6. Verify the five screenshots, `marker-sequence.txt`, `run-status.txt`,
   `apk-sha256.txt`, `fixture-sha256.txt`, `device-identity.txt`, and the
   marker-filtered logcat in the evidence directory.
7. Cleanup: the driver removes staging and clears test app data; it never
   modifies another worktree's allocation.

## 8. Artifacts

Directory `artifacts/2026-11-21-t071a-composition/`:

- `NOT-RUN.md`
- `README.md`
- `device-identity-preflight.txt`
- `orca-emulator-devices.json`
- `orca-emulator-sessions.json`
- `git-identity-base.txt`
- `host-gates.txt`

No APK, screenshot, logcat, or document content is stored.

## 9. Review

- Reviewer:
- Date:
- Verdict:
- Notes:
