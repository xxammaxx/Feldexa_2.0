# 2026-11-23 EMULATOR — T086 two-page touch fill journey (PASS after the overlap repair)

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` (host checks `NONE`; `DEVICE` `NOT_RUN`; `SIMULATED` `NOT_RUN`) |
| Result | `PASS` for the run-5 EMULATOR journey (run 4 also passed; run 5 used the derived markers) (every step of the recorded journey completed; §7 lists the US4 scenarios this journey does not execute); `PARTIAL` for T086 as a whole, because `DEVICE`, TalkBack, stylus, and the visual/export halves are `NOT_RUN` and the acceptance row stays with the owner |
| Task / issue | `T086` / `#86` |
| Date / timezone | `2026-11-23 18:50 Europe/Berlin` (run 5; runs 1-4 in the same afternoon) |
| Revision | run-5 HEAD `71d63d5dddd26dd1582c2af35c4d0eb2e01e019e` (tree from `git-identity.txt`, branch `<owner>/t086-cleanup`), `git status --porcelain` empty at run start; run 4 ran `69827d5` and is kept below |
| External attestation | none; the candidate SHA and this report's own bytes/hash are not asserted here |
| Build identity | run 5: `de.feldexa.app` debug APK, 135314022 bytes, SHA-256 `beac871b0a28fe2d1d09c915630832ce3cc9e04a245697ba6db70a15ed2ed24a`; run 4 built 173624809 bytes, SHA-256 `1b6462932d0a2b190c3b3f5fba3695d60bec8fa47e750812115e8509ce67d610` |
| Toolchain | Flutter 3.47.7 stable, Dart 3.13, AGP/Gradle 9.3.1 via the Flutter toolchain, JDK 17.0.20.1 |
| Input | committed fixture `apps/feldexa_app/assets/fixtures/sf-001.pdf`, 5956 bytes, SHA-256 `22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038`, 2 pages |

## 1. Scope

This report covers the T086 emulator work for the US4 Independent Test (issue #86):
the two-page `sf-001.pdf` journey in
`apps/feldexa_app/integration_test/android_fill_test.dart`, driven by
`tools/android/t086_drive_fill.sh`.

It records four runs of that journey in one afternoon:

| Run | HEAD | Outcome |
| --- | --- | --- |
| 1 | `ddd3fd4` | page 1 reached the FLD-001 field, then failed on a test-side stale control assertion |
| 2 | `a91ec0e` | page 1 `PASS`, page 2 `FAIL` on the first tap with no sheet, no error, no exception |
| 3 | `ad5ddac` | same failure, decisive `T086_DIAG_SHEET_*` diagnosis of the tap seam |
| 4 | `69827d5` | `PASS`: both pages filled by touch, round trip, reopening, edit, and verified store read-back |

The run-4 result is the claim of this report. Runs 1-3 are kept because they are
why the journey was blocked and why a production file changed at all. No claim is
made beyond the emulator: `DEVICE`, TalkBack, stylus, visual/golden, export, and
performance are `NOT_RUN`.

## 2. Revision and build

| Item | Value |
| --- | --- |
| Run-1 HEAD | `ddd3fd4e7c4f20a77a986bac6262b9ab4a37801b` |
| Run-2 HEAD | `a91ec0eddb0609d064abf20c7fb849cae900a325` (tree `4dabde5b2b21b04e6b73519c902e78f0d5725281`) |
| Run-3 HEAD | `ad5ddac608e1d20e7e4afb77c20385eb80d6ca85` (tree `ec254f3414e7102824471fb5083eeafdf80fdbf0`), subject `test(T086): diagnose the page-2 tap seam` |
| Run-4 HEAD | `69827d5c221ae10fd3840da9943bba9a3e478d51` (tree `a91d5700a118eed3a8ecde35d988b48705904831`), subject `docs(T086): keep the diagnostic emulator run beside the fill evidence` |
| Commits of this task | `ad5ddac` diagnostic instrumentation, `c150f64` overlap host test (RED), `0b80ce6` overlap repair (GREEN), `69827d5` diagnostic evidence preserved |
| Integration test at run 4 | SHA-256 `c3a25fc8c38f1eec7a1a34ff67b71ebfb4dc2326f1a9132f260bb90c427434dd` |
| Driver at run 4 | SHA-256 `5a271fd9902b331865078456b51351eb7f63206e5c37c0b52f912aaa997a87f7` |
| Build command | `flutter test --no-pub integration_test/android_fill_test.dart -d emulator-5554` (Gradle `assembleDebug`, incremental) |
| Dirty files | none at run start; the driver's commit-before-run gate passed |

Three source files changed in this task (the test-only driver `tools/android/t086_drive_fill.sh`,
this report, and its artifact bundle are additional, non-behavioural additions): `apps/feldexa_app/integration_test/android_fill_test.dart`
(test-only instrumentation plus the untouched journey), `apps/feldexa_app/test/editor_composition_test.dart`
(RED regression test), and `apps/feldexa_app/lib/features/editor/editor_screen.dart`
(the minimal repair, 20 added lines in one composition method). No core, ports,
recognition, ARB, Gradle, or pubspec change.

## 3. Environment

```text
EMULATOR: Pixel 7 API 35, run labels t086-fill-run3 (diagnosis) and t086-fill-run4 (verification);
          serial emulator-5554, AVD T025_Pixel7_API35_KVM_20261115;
          system image google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925 userdebug;
          1080 x 2400 at 420 dpi; RAM 4014392 kB; qemu=1; boot_completed=1;
          APK apps/feldexa_app/build/app/outputs/flutter-apk/app-debug.apk SHA-256 1b646293…;
          build mode debug, no flags; no physical device addressed
```

The emulator for runs 3 and 4 was already running with a window, prepared by the
owner's environment; this task neither restarted, reset, nor stopped it
(`adb emu kill` was never issued and the emulator is still running after run 4).
Every command addressed `-s emulator-5554`. The wirelessly attached Samsung S23
transport (`adb-RFCW80SMY4J-…`) appears in `device-binding.txt` only as an
attached transport and was never addressed
(`non_emulator_transports_addressed=none`).

Both runs executed inside the shared heavy-work permit:

```text
python3 <orca-maintainer-skill>/scripts/compute_slot.py --wait -- \
  env T086_COMPUTE_LOCK_HELD=1 T086_RUN_DIR=<fresh tmp run directory> \
      T086_REPLACE_EVIDENCE=1 bash tools/android/t086_drive_fill.sh
```

`compute-lock.txt` records `mode=shared-heavy-work-lock`, the lock path
`<tmp>/orca-maintainer-heavy-<uid>.lock`, `orca_command_used=0`, and
`admitted_at_utc=2026-11-23T16:45:16Z` for run 4. The permit settled with
`exit_code: 0`.

## 4. Checks

| # | Command (cwd) | Exit | Outcome |
| ---: | --- | ---: | --- |
| 1 | `dart format --output=none --set-exit-if-changed lib test integration_test` (`apps/feldexa_app`) | 0 | `Formatted 109 files (0 changed)` |
| 2 | `flutter analyze` (`apps/feldexa_app`) | 0 | `No issues found!` |
| 3 | `flutter test --no-pub test/editor_composition_test.dart` after the fix (`apps/feldexa_app`) | 0 | `+23: All tests passed!` (22 before the new test) |
| 4 | same focused file at the RED step, with the test and without the fix (`apps/feldexa_app`) | 1 | `Expected: '11111111-1111-4111-8111-111111111111' / Actual: 's_p0_0002'` in `a confirmed field keeps its tap where an unresolved suggestion overlaps` |
| 5 | `flutter test --no-pub` full app suite (`apps/feldexa_app`) | 0 | `+589: All tests passed!` |
| 6 | `tools/android/t086_drive_fill.sh` inside `compute_slot.py --wait` (`<repo-root>`, run 4) | 0 | driver `PASS`, `flutter_test_exit=0`, `CLEANUP_DONE` observed, privacy 2/2 |
| 7 | `python3 tools/evaluation/check_evidence_docs.py --report specs/001-scanned-form-workflow/reports/2026-11-23-emulator-t086-fill.md` (`<repo-root>`) | 0 | validates the artifact rows and the report binding against the committed tree |

Checks 1-5 are the host gates for the production change; checks 6-7 bind the
runtime evidence. `dart tools/evaluation/validate_report.dart` remains `ABSENT`:
it targets the strict class-run template, which every hand-written T086 sibling
report also does not satisfy.

## 5. Results

### 5.1 Run 1 (`ddd3fd4`) and run 2 (`a91ec0e`), documented history

Run 1 failed at `android_fill_test.dart:728` because a post-commit draft-control
assertion ran for a value whose sheet the production save had already popped; the
fix in `a91ec0e` moved that assertion into the FLD-001 branch. Run 2 then proved
page 1 completely (`T086_PAGE1_FILLED:FIELDS=5`, overflow, number, date, checkbox,
two distinct screenshots) and failed on the first page-2 fill with

```text
TestFailure: tapping the text field did not open the value sheet (bounded wait 120s expired)
#2 _openValueSheet (android_fill_test.dart:344)
#3 _fillField (android_fill_test.dart:771)
#4 main.<anonymous closure> (android_fill_test.dart:1055)
```

That run left three candidate mechanisms — a tap point leaving the clipped page
viewport, a selection miss inside the page, or the `_valueSheetOpen` re-entry gate
— and no way to distinguish them. Run 2's bytes are preserved under
`run-2-before-diagnosis/` (integration log `c8c00f0e…`, markers `f35d0d10…`).

### 5.2 Run 3 (`ad5ddac`): instrumenting the tap seam

`_openValueSheet` now emits, immediately after the tap and again when its bound
expires, a content-free dump of that seam: viewport/media/IME size, scale and pan,
the page-view and page rectangles, the tap point in screen, page-view, and page
coordinates, the selection identity (this field / none / other), the value-sheet
and text-input finder state, the modal-barrier count, whether the field is still
in the live content, the per-page overlay item state, the result of the production
`hitTestFieldSelection` for the tapped point, the top of the binding hit-test path,
and a deduction. `_pumpUntil` gained an optional `diagnosis` callback so the failure
message carries the same dump at the moment it expires. The dump is wrapped so a
throwing observation degrades to a note and can never change the journey's outcome.

The failing page-2 tap produced (verbatim, one line):

```text
T086_DIAG_SHEET_GEOM_TAP:PAGE=2:TYPE=text:VIEWPORT=411.4x317.7:MEDIA=411.4x914.3:IME_BOTTOM=0.0:SCALE=1.000:PAN=-183.9,-1048.9:PAGEVIEW=0.0,572.6,411.4,890.3:TAP=262.6,731.4:TAP_IN_PAGEVIEW=1:PAGE_IN_VIEW=-183.9,-199.0,411.4,642.9:TAP_IN_PAGE=1:TAP_PAGE_LOCAL=446.5,357.8:FIELD=327.4,336.8,565.5,378.9
T086_DIAG_SHEET_STATE_TAP:SELECTION=OTHER:SHEET=CLOSED:TEXT_INPUT=EMPTY:BARRIERS=1:FIELD_IN_CONTENT=1:PAGE_SUGGESTIONS=51:SURFACES=1:SURF0=IN1/ITEMS55/HASFIELD1/HIT:SUGGESTION@56.5,345.6,539.3,363.6:HITPATH=RenderPointerListener>RenderSemanticsGestureHandler>RenderStack>RenderStack>RenderPointerListener>RenderStack:DEDUCED=OTHER_ITEM_ON_TOP
```

What that rules out and what it proves:

| Candidate from run 2 | Evidence | Verdict |
| --- | --- | --- |
| tap point leaves the clipped page viewport | `TAP_IN_PAGEVIEW=1`, `TAP_IN_PAGE=1`, page rect `-183.9,-199.0,411.4,642.9` around the point `262.6,731.4` | refuted |
| selection miss inside the page | `SELECTION=OTHER` — the surface received the tap and changed the selection; all six page-1 taps show `HIT:TARGET` | refuted |
| `_valueSheetOpen` re-entry gate | `SHEET=CLOSED` with `SELECTION=OTHER`; the gate is never reached because `_handleOverlaySelection` does not call `_openFieldValueSheet` at all | refuted |
| field vanished from the live revision | `FIELD_IN_CONTENT=1`, `HASFIELD1`, `ITEMS55` unchanged | refuted |
| mechanism | the tapped point resolves to an **unresolved machine candidate** `56.5,345.6 → 539.3,363.6` that overlaps the confirmed field `327.4,336.8 → 565.5,378.9` | confirmed |

`DEDUCED` is only meaningful in the `TIMEOUT` dump: right after the tap the sheet
route is pushed asynchronously (`unawaited(_openFieldValueSheet(field))`), so the
`TAP` dump still reports `SHEET=CLOSED` for taps that succeed.

The cause is the composition order, not the geometry: `_overlayItemsForPage`
appends the confirmed fields first and the unresolved suggestions after, and
`hitTestFieldSelection` resolves the last matching item, so a machine candidate
always wins an overlap. `_handleOverlaySelection` then finds no confirmed field for
that candidate id and returns without any feedback — no sheet, no error, no log.
A user could not select the field by touching its position, which contradicts
FR-031 (“Users MUST be able to select a field by touching or clicking its position
on the page”) and FR-032; `contracts/editor-interactions.md` §2 does not state a
precedence for overlaps.

### 5.3 The repair (`c150f64` RED, `0b80ce6` GREEN)

The owner decision for this seam was the hit-order variant: keep the painted and
semantic item order byte-identical (so the T069/T077/T086A evidence and every
visual record stay valid) and give the selection surface its own order with the
confirmed fields last.

- `c150f64` adds `a confirmed field keeps its tap where an unresolved suggestion overlaps`
  to `apps/feldexa_app/test/editor_composition_test.dart`: a suggestion
  `40,65 → 180,85` overlaps the field `40,60 → 140,90`; a tap on the field centre
  must select the field and open its sheet, and a tap on the candidate-only part
  must still select the candidate without a sheet. Against the composition as it
  stood the first expectation failed with `Actual: 's_p0_0002'`.
- `0b80ce6` gives `FieldSelectionSurface` a `hitItems` list built from the same
  items with the machine suggestions first and everything else after, so the
  topmost hit at an overlap is the document datum. The comment at that list records
  the reason and states that confirming or rejecting a candidate stays on the
  suggestion/review list rather than on an overlapping tap area. `_overlayItemsForPage`,
  `FieldOverlay`, `hitTestFieldSelection`, and the semantics order are unchanged.

No assertion, scenario, field, or driver behaviour was weakened, and no new
production API was added.

### 5.4 Run 4 (`69827d5`): the journey passes

`run-status.txt` records `result=PASS`, `flutter_test_exit=0`; the driver logged
`PASS (flutter test exit 0; cleanup marker observed; privacy checks PASS)`. A
marker is printed only after the `expect` that proves its fact, so the marker
sequence is a trace of the assertions, never their replacement. The marker
sequence recorded from the integration log (`markers-integration.txt`, 90 lines
including the 38 `T086_DIAG_SHEET_*` lines) contains, in order:

```text
T086_FIXTURE_READY:BYTES=5956:MATCH=1
T086_ANALYSIS_READY:STATE=analysis-ready:PAGES=2:SUGGESTIONS=80
T086_TWO_MACHINE_FIELDS_CONFIRMED:PAGES=2
T086_TYPED_FIELDS_SEEDED:COUNT=7:HEAD_CHANGED=1
T086_DOCUMENT_REOPENED:FIELDS=9:PAGES=2:ANALYSIS=skipped
T086_PAGE_VISIBLE:PAGE=1
T086_VALUE_OVERFLOW:TYPE=text:ENTERED_RUNES=215:STORED_RUNES=215:TRUNCATED=0
T086_VALUE_SAVED:TYPE=text:RUNES=215:OVERFLOW=1
T086_T086_SCREENSHOT_OVERFLOW_WARNING
T086_VALUE_SAVED:TYPE=text:RUNES=14:OVERFLOW=0
T086_VALUE_SAVED:TYPE=number:RUNES=8:OVERFLOW=0
T086_NUMBER_CANONICAL:MATCH=1
T086_VALUE_SAVED:TYPE=date:RUNES=10:OVERFLOW=0
T086_DATE_CANONICAL:MATCH=1
T086_VALUE_SAVED:TYPE=checkbox:CHECKED=1
T086_PAGE1_FILLED:FIELDS=5
T086_T086_SCREENSHOT_PAGE1_VALUES
T086_PAGE_VISIBLE:PAGE=2
T086_VALUE_SAVED:TYPE=text:RUNES=6:OVERFLOW=0
T086_VALUE_SAVED:TYPE=multiline:RUNES=38:OVERFLOW=0
T086_MULTILINE_STORED:LINES=2:TRUNCATED=0
T086_VALUE_SAVED:TYPE=signature:BOUND=1:WIDTH_LE_1024=1:HEIGHT_LE_1024=1
T086_PAGE2_FILLED:FIELDS=3
T086_T086_SCREENSHOT_PAGE2_SIGNED
T086_PAGE_VISIBLE:PAGE=1
T086_VALUES_SURVIVED_NAVIGATION:PAGE1=5:PAGE2=3
T086_FIELD_REOPENED:TYPE=text:PAGE=1:PRESERVED=1:EDITABLE=1
T086_FIELD_REOPENED:TYPE=number:PAGE=1:PRESERVED=1:EDITABLE=1
T086_FIELD_REOPENED:TYPE=date:PAGE=1:PRESERVED=1:EDITABLE=1
T086_FIELD_REOPENED:TYPE=checkbox:PAGE=1:PRESERVED=1:EDITABLE=1
T086_T086_SCREENSHOT_PAGE1_PRESERVED
T086_PAGE_VISIBLE:PAGE=2
T086_FIELD_REOPENED:TYPE=text:PAGE=2:PRESERVED=1:EDITABLE=1
T086_FIELD_REOPENED:TYPE=multiline:PAGE=2:PRESERVED=1:EDITABLE=1
T086_FIELD_REOPENED:TYPE=signature:PAGE=2:PRESERVED=1:EDITABLE=1
T086_PAGE_VISIBLE:PAGE=1
T086_VALUE_SAVED:TYPE=text:RUNES=19:OVERFLOW=0
T086_FIELD_EDITED_AFTER_NAVIGATION:TYPE=text:RUNES=19:TRUNCATED=0
T086_STORE_READBACK:VALUES=7:SIGNATURE=1:DIGEST_MATCH=1:PNG=1:TRUNCATED=0
T086_CLEANUP_DONE
```

The repaired seam on the same geometry that failed in run 3 (verbatim):

```text
T086_DIAG_SHEET_STATE_TAP:SELECTION=THIS:SHEET=CLOSED:TEXT_INPUT=EMPTY:BARRIERS=1:FIELD_IN_CONTENT=1:PAGE_SUGGESTIONS=51:SURFACES=1:SURF0=IN1/ITEMS55/HASFIELD1/HIT:TARGET@327.4,336.8,565.5,378.9:HITPATH=RenderPointerListener>RenderSemanticsAnnotations>RenderSemanticsAnnotations>RenderSemanticsAnnotations>RenderSemanticsAnnotations>RenderTapRegionSurface:DEDUCED=GATE_STUCK_OPEN
```

`ITEMS55` and `HASFIELD1` are unchanged from run 3, which shows that the item set
and therefore the painted overlay are identical; only the hit resolution now
returns the field (`HIT:TARGET`) instead of the candidate. All 19 taps of the run
report `HIT:TARGET`.

Proven on the real emulator, the real encrypted store, and the production
composition:

| Scenario | Expected | Observed | Verdict |
| --- | --- | --- | --- |
| Import + two-page analysis of the committed fixture | 2 pages, terminal analysis | `SUGGESTIONS=80`, both pages complete | `PASS` |
| One real machine text field confirmed per page through the production review surface | 2 confirmed | `TWO_MACHINE_FIELDS_CONFIRMED:PAGES=2` | `PASS` |
| Seven typed fields seeded through `addField`, one verified revision, reopen with analysis skipped | 9 fields, 5 page 1 / 4 page 2 | `FIELDS=9:PAGES=2:ANALYSIS=skipped` | `PASS` |
| FLD-001: entered text larger than the recognised region keeps every rune | warning visible, `TRUNCATED=0` | `RUNES=215:STORED_RUNES=215:TRUNCATED=0` + `overflow-warning` screenshot | `PASS` |
| Page-1 touch fill: text, number, date, checkbox | committed values, canonical forms | 4 markers, `NUMBER_CANONICAL:MATCH=1`, `DATE_CANONICAL:MATCH=1`, `CHECKED=1` | `PASS` |
| Page-1 completion screenshot | 5 filled fields | `PAGE1_FILLED:FIELDS=5` marker printed after the asserting check (`_filledFieldCount` on page 1 equals 5) + `page1-values` screenshot (captured during the IME transition, so the sheet header is visible but the value row sits behind the keyboard) | `PASS`; the marker trace, the screenshot is illustrative |
| Page-2 touch fill: text, multiline, drawn signature | three committed values | `RUNES=6`, `MULTILINE_STORED:LINES=2:TRUNCATED=0`, `signature:BOUND=1:WIDTH_LE_1024=1:HEIGHT_LE_1024=1` | `PASS` |
| Page-2 completion screenshot | 3 filled fields | `PAGE2_FILLED:FIELDS=3` marker printed after the asserting check (`_filledFieldCount` on page 2 equals 3) + `page2-signed` screenshot | `PASS`; the marker trace, the screenshot is illustrative |
| Page round trip: every page-1 value unchanged | 5 values | `VALUES_SURVIVED_NAVIGATION:PAGE1=5:PAGE2=3` | `PASS` |
| Every filled field reopened on both pages | preserved and editable | 7 `FIELD_REOPENED` markers + `page1-preserved` screenshot | `PASS` |
| Real edit after the round trip | updated value committed | `FIELD_EDITED_AFTER_NAVIGATION:TYPE=text:RUNES=19:TRUNCATED=0` | `PASS` |
| Verified encrypted-store read-back | 7 values, signature asset, no truncation | `VALUES=7:SIGNATURE=1:DIGEST_MATCH=1:PNG=1:TRUNCATED=0` | `PASS` |
| Cleanup marker | present | `CLEANUP_DONE` | `PASS` |

Screenshots captured: 4 of 4 phases, all distinct — `overflow-warning` 211058 bytes,
`page1-values` 192205 bytes, `page2-signed` 177435 bytes, `page1-preserved`
195993 bytes (`screenshot-hashes.txt`, `marker-sequence.txt`).

`logcat-flutter.log` holds two informational engine lines and no `flutter` error;
`logcat-t086-markers.log` shows the app start and, after the journey, the process
end that the driver's `pm clear` forces. No `E/flutter` and no `FATAL EXCEPTION`
appear in the run log or in logcat.

## 6. Performance

No performance claim. Emulator timings are never a device claim.

## 7. Limitations

- `DEVICE`, TalkBack traversal, stylus, visual/golden, export of the filled
  document, and every performance claim are `NOT_RUN`.
- **US4 acceptance scenarios this journey does not execute** (the journey covers
  scenarios 1, 3, 5, 6 and 7 of `spec.md` §US4; "every step" in the result row
  refers to the journey's own steps, not to all ten scenarios):
  - scenario 2 (zoom brings the field region into a readable view) — the journey
    sets the view itself (`_setScaleOnPoint`/`_centreAndTapField`) and asserts no
    app-driven zoom; `zoomToFieldScale` has no caller under `apps/`.
  - scenario 4 (next/previous field focus) — `fieldValueNextKey`/
    `fieldValuePreviousKey` are not used; covered by host widget tests
    (`test/field_value_sheet_test.dart`, the next-focus case in
    `test/editor_composition_test.dart`).
  - scenario 8 (overview completion state) — the journey leaves and reopens the
    document but does not assert completion; covered by host tests
    (`test/editor_composition_test.dart`, the overview completion case).
  - scenario 9 (impossible date rejected) — only a valid date is entered; covered
    by host tests (the impossible-date case in `test/editor_composition_test.dart`).
  - scenario 10 (reclassify a date field as text) — no `changeType` UI exists in
    `apps/feldexa_app/lib`; not demonstrated anywhere.
- **8 of 9 seeded confirmed fields are filled**: the machine-confirmed text field on
  page 2 (`machinePageTwo`) is measured and left untouched, so "entirely by touch"
  holds for the 8 filled fields, not for every field on both pages.
- The emulator proves wiring, real touch behaviour, and the production store, not
  silicon-specific behaviour.
- The repair changes the hit precedence only. A machine candidate that overlaps a
  confirmed field is still painted above it, so at an overlap the topmost painted
  item and the tapped item differ; the candidate stays reachable outside the
  field and through the suggestion/review list. This is recorded in the code
  comment and is a deliberate, owner-approved trade-off to keep the visual
  evidence valid.
- The journey creates the page-2 text, multiline, and signature fields through the
  existing `addField` command (the documented T086 scope boundary: the committed
  detector produces no such suggestions and T086 may not add a field-creation UI).
  The overlap that exposed the defect is therefore seeded, but the same overlap is
  reachable by a user through FR-023 move/resize over a detected candidate.
- The `T086_DIAG_SHEET_*` diagnostics stay in the integration test. They are
  test-only, content-free, and wrapped so they cannot change the journey's outcome;
  the `TAP` dump reports `DEDUCED=UNDECIDED` and only the `TIMEOUT` dump deduces,
  because the sheet route is pushed asynchronously after the tap.
- The journey needs one emulator run per verification (about 4 minutes of journey
  plus build); a re-run is not part of this task's budget.
- The T086 row in `tasks.md` is unchanged: US4 is now demonstrated on the
  emulator, but acceptance and the remaining evidence classes are the owner's call.

## 8. Evidence classes

| Class | Result | Basis |
| --- | --- | --- |
| `EMULATOR` | `PASS` | Pixel 7 API 35 KVM emulator `emulator-5554`, run 4; runs 1-3 are the recorded failures that led to the repair |
| `DEVICE` | `NOT_RUN` | no physical device addressed; the wireless S23 transport was recorded only |
| `SIMULATED` | `NOT_RUN` | not part of this task |

The classes are never merged. The host gates in §4 are `NONE` (not a runtime class)
and prove nothing about Android behaviour; the emulator run proves nothing about
the browser or a physical device.

## 9. Artifacts

All paths are repository-relative; sizes and digests are of the committed bytes.

### 9.1 Run 5 (the current verification run this report binds to)

Written entirely by `tools/android/t086_drive_fill.sh`; host paths were rewritten on
the way into this committed bundle (see `collection-note.txt`).

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Emulator run log | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/integration-android-t086.log` | 19868 | `d4bd7269ab875ff71cf0240ef440a5e8abdcade38d35fa442ced59628cc63e2b` |
| Journey markers | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/markers-integration.txt` | 15226 | `c337a95b65f1df3934aae11485cdb7840fb06a9100520c90a6fb688bb0117bf8` |
| Screenshot phase records | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/marker-sequence.txt` | 442 | `9c84cd24d849b6cfac73c8eb00279d0dc9df9240c254ac769cc8c30851ab255a` |
| Screenshot digests | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/screenshot-hashes.txt` | 399 | `7b92514249794fe0889375e6cb86b9432434b1fe0241ca69fddad4cbe212770c` |
| Run status | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/run-status.txt` | 32 | `7fd607f90d24581a4b9b797cff3d71e0f238dc52f3f869fd23b88a688a94f0b3` |
| Device identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/device-identity.txt` | 300 | `2ac7e85ab159fbb83398cb9eeeb4301fb8613bda5b4133a7ad9e82ab3d36fa54` |
| Device binding | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/device-binding.txt` | 202 | `844bed2e374c4bcfa531a32893e586a887aa307e29dd119d68f5636c33e98efd` |
| Compute permit | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/compute-lock.txt` | 315 | `9682186e4c43adc2f1dd3db2aa954f5bd162f4780ea6be53fc072d3a6fbee3d6` |
| Fixture identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/fixture-sha256.txt` | 327 | `b96ca888eb5169ed84f793c53e522d7981d513933ee121dcda2d534f3ee2dd33` |
| APK identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/apk-sha256.txt` | 154 | `5fcc9c707f30de690cf06e1100564244dda2181f2a0666e935b551076c6a8e67` |
| Git identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/git-identity.txt` | 450 | `04b81313caabc208d36d138e8b6b0309039f0f91604d5d0a5daa132fed0fdf6e` |
| Privacy, source | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/privacy-source-check.txt` | 74 | `349ad38e994e846dbaaac218d4543d30c53d3c2748c73c4045b4b16cbfa07f91` |
| Privacy, log | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/privacy-log-check.txt` | 80 | `08b97bb2972b873de14efa6d826023c6cf88d87105f62dc1e77006c2a171ea8a` |
| Engine log | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/logcat-flutter.log` | 315 | `56dd9fb8fe2c5aad9241dbcedc2c3df1b7e353c50b4e7e96dec5fc033038baa3` |
| Activity log | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/logcat-t086-markers.log` | 773 | `59bb8de81d9139e17a20299f09fb6940451aedace0bfd2ff3d0e686915906607` |
| Host `flutter pub get --offline` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/host-flutter-pub-get.log` | 235 | `ca8a31e8d3a8e09e9613cc7cf03b3b074336ba53fcfd722c769ea6df66588675` |
| Collection provenance | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/collection-note.txt` | 643 | `ed49cef8ccd9492093dacd8aed65bcceebae2cb4d9046d9e62d8d608edb60560` |
| Screenshot `overflow-warning` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/screenshots/overflow-warning.png` | 210028 | `4e6f5bb40388ba1e84667b300be745835cbbe1fcdc1dd1047938c95f50fb3518` |
| Screenshot `page1-values` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/screenshots/page1-values.png` | 191863 | `a8a2e1edd3be5bd596371f2a3da6ae2a0541693965ed571b6ed40e411b73363d` |
| Screenshot `page2-signed` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/screenshots/page2-signed.png` | 177094 | `498b960b8bc242f9744738fb700355ffb2c35e6648fa7872628bd06ad5f55a45` |
| Screenshot `page1-preserved` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill-run5/screenshots/page1-preserved.png` | 197121 | `3bf1213d63ee75786f9eb6c354ab77f4de023fa91391b7b5c28ca750f93dcd65` |

### 9.2 Run 4 (the verification run this report binds to)

Every file below was written by the driver in step 7 except `collection-note.txt`.

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Emulator run log | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/integration-android-t086.log` | 19765 | `b437dfc4183d892fc531362669181ba79b59b63450fac34b6682b73691aa972e` |
| Journey markers | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/markers-integration.txt` | 15352 | `c85971df4e445dba7717853f9e5bc0b928d10b06249f39de56a3854f4173fa19` |
| Screenshot phase records | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/marker-sequence.txt` | 442 | `9c84cd24d849b6cfac73c8eb00279d0dc9df9240c254ac769cc8c30851ab255a` |
| Screenshot `overflow-warning` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/screenshots/overflow-warning.png` | 211058 | `282fe77cccb1dae74cd621c4775c7f107cee16005a9cf22c0a14c2520c15e890` |
| Screenshot `page1-values` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/screenshots/page1-values.png` | 192205 | `a8158a39cc5cdcdd643c10f5ca88a69f43ec0381ac1b185bf6efa2768f4fb182` |
| Screenshot `page2-signed` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/screenshots/page2-signed.png` | 177435 | `ee5df7d6b66c4b8f3d9e285bf98ef33f1262c814345ed8656a0c6a49afbeccc5` |
| Screenshot `page1-preserved` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/screenshots/page1-preserved.png` | 195993 | `574c7f118f23cb69df50077a5b10dd155883f333ece15bff385a2eddcb04984f` |
| Screenshot digests | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/screenshot-hashes.txt` | 399 | `c532dc6a3a269c24dd67b05d930e382558ea977018b7c2cac176b203a0c27472` |
| Run status | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-status.txt` | 32 | `7fd607f90d24581a4b9b797cff3d71e0f238dc52f3f869fd23b88a688a94f0b3` |
| Device identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/device-identity.txt` | 298 | `265c299fe643739f0c63d2fc73f638d221a7aa9322b021641ab53bc0fedbbf56` |
| Device binding | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/device-binding.txt` | 205 | `6258b3334daf5630f35df414a604c37fb8b45b1fd6bcf72233c6108d482543c1` |
| Compute permit | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/compute-lock.txt` | 328 | `252befce74489cba1bc329981f132276b20b464828c6e107f6065c62be9ff573` |
| Fixture identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/fixture-sha256.txt` | 410 | `0384ec26a4d239d57a63e23348d8047198668433e96286ab9b68c28b1b300f73` |
| APK identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/apk-sha256.txt` | 237 | `28d145f348f4c429e5358d27ae7d4263fdf48998f1318f8fcffdece61924d225` |
| Git identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/git-identity.txt` | 450 | `02c9483f203e96e8beadfc772a4b8c6a8760f57d8e593d75bcaf6efdd5ba70e7` |
| Privacy, source | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/privacy-source-check.txt` | 74 | `349ad38e994e846dbaaac218d4543d30c53d3c2748c73c4045b4b16cbfa07f91` |
| Privacy, log | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/privacy-log-check.txt` | 80 | `08b97bb2972b873de14efa6d826023c6cf88d87105f62dc1e77006c2a171ea8a` |
| Engine log | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/logcat-flutter.log` | 315 | `092326f05e5300c3e5059442667fec871af8ded12a490087240b986936daf3f8` |
| Activity log | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/logcat-t086-markers.log` | 901 | `b76391371feaee657ce32ab66494f10d6bbdef75171d5579562a3ff42832d6f0` |
| Host `flutter pub get --offline` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/host-flutter-pub-get.log` | 397 | `349e3d1082e7dfafb1e16ab71e5a3499ef4482e1eb38bea8538dd0d7122b8fd8` |
| Collection provenance | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/collection-note.txt` | 1692 | `9b9a3c94d89d83f8bbb0d0536c4ba4a945dd1123e36d639d7b475fd3006e1c48` |

### 9.3 Run 3 (the diagnostic run, kept unchanged)

The driver aborted in step 6 of that run, so stage-1 files come from the driver and
the stage-2 files were collected afterwards exactly as
`failed-run-3-diagnosis/collection-note.txt` describes.

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Emulator run log | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/failed-run-3-diagnosis/integration-android-t086.log` | 13314 | `67af5e86fae51a4c92e54e4c9036779ba1423c27f55e03bbbc3a232b7cbb6e44` |
| Journey and diagnostic markers | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/failed-run-3-diagnosis/markers-integration.txt` | 6112 | `67a2c192ea3d41a304fd8511df120bbf36de9a8b7e50bd5463b75c047cf053cd` |
| Screenshot phase records | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/failed-run-3-diagnosis/marker-sequence.txt` | 186 | `2e0fe26a0d1d38d71f606a52127a4727c05ffa4689a20dc5e31e6cea6849b601` |
| Screenshot `overflow-warning` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/failed-run-3-diagnosis/screenshots/overflow-warning.png` | 210873 | `b1e48b7ff5a367c714a0feb81a364985861e97dd85f23dad50950ea839ecb536` |
| Screenshot `page1-values` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/failed-run-3-diagnosis/screenshots/page1-values.png` | 206376 | `c8f2bb312291aa0ce412d3176c9bb5316c2126a0c22699c9c0b25f994026f3af` |
| Screenshot digests | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/failed-run-3-diagnosis/screenshot-hashes.txt` | 325 | `23e5839638dfbe3fc763a4125672784d75be3115c8d92395b2fbfdafd3f9ebb1` |
| Run status | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/failed-run-3-diagnosis/run-status.txt` | 293 | `e893173d9488a8441e2dd9c493b411cfda6f2823744a9863d4ff351bdff631fd` |
| Device identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/failed-run-3-diagnosis/device-identity.txt` | 298 | `265c299fe643739f0c63d2fc73f638d221a7aa9322b021641ab53bc0fedbbf56` |
| Device binding | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/failed-run-3-diagnosis/device-binding.txt` | 205 | `6258b3334daf5630f35df414a604c37fb8b45b1fd6bcf72233c6108d482543c1` |
| Compute permit | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/failed-run-3-diagnosis/compute-lock.txt` | 328 | `e627940e5245f8814b9d24605680044425f3d05f5f23e4fcaebfbff57f98b7fa` |
| Fixture identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/failed-run-3-diagnosis/fixture-sha256.txt` | 410 | `0384ec26a4d239d57a63e23348d8047198668433e96286ab9b68c28b1b300f73` |
| APK identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/failed-run-3-diagnosis/apk-sha256.txt` | 154 | `a32010dc6a1fc0477cdc4b931c3ee112cf9f8cc1a6536b9c423c9b31af92b8d6` |
| Git identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/failed-run-3-diagnosis/git-identity.txt` | 1292 | `aecc9c7c5a7920b8b70b565bb1bac143aca2b744037cbc1087d58d0d163054a3` |
| Privacy, source | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/failed-run-3-diagnosis/privacy-source-check.txt` | 74 | `349ad38e994e846dbaaac218d4543d30c53d3c2748c73c4045b4b16cbfa07f91` |
| Privacy, log | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/failed-run-3-diagnosis/privacy-log-check.txt` | 80 | `08b97bb2972b873de14efa6d826023c6cf88d87105f62dc1e77006c2a171ea8a` |
| Logcat probe | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/failed-run-3-diagnosis/logcat-probe.txt` | 474 | `a19a64923dacefb8e72d04f8f6588358b2042e1e110dbb5418bc8720a09be91c` |
| Host `flutter pub get --offline` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/failed-run-3-diagnosis/host-flutter-pub-get.log` | 397 | `349e3d1082e7dfafb1e16ab71e5a3499ef4482e1eb38bea8538dd0d7122b8fd8` |
| Collection provenance | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/failed-run-3-diagnosis/collection-note.txt` | 1528 | `098a4fdac28fccfdf2f824831ab013a55a102e0a459b1f30f1f55cca773fe2e4` |

### 9.4 Run 2 (the failure this report's repair was derived from, kept unchanged)

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Directory note | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-2-before-diagnosis/README.txt` | 618 | `9072c7c935727202b6704d1b1c6c66a2ff0b85627a4981f99942b0182fc0e0b9` |
| Emulator run log | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-2-before-diagnosis/integration-android-t086.log` | 7982 | `c8c00f0e37105d4b03b156eb5101e541a641ad3978f6498e7d2d122d7e96352f` |
| Journey markers | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-2-before-diagnosis/markers-integration.txt` | 1416 | `f35d0d10c0470e4204934d4c400e1fe1b97125c6f6cf5c6bb0fc89a4d6618b56` |
| Screenshot phase records | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-2-before-diagnosis/marker-sequence.txt` | 186 | `2e0fe26a0d1d38d71f606a52127a4727c05ffa4689a20dc5e31e6cea6849b601` |
| Screenshot `overflow-warning` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-2-before-diagnosis/screenshots/overflow-warning.png` | 211257 | `a2d1e46cc298bf05ebcfa57edc4f5537475ec82fa21eed381d3ff976dca9a5a4` |
| Screenshot `page1-values` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-2-before-diagnosis/screenshots/page1-values.png` | 189245 | `ba15a1b09f91fb0dfbf2c58454d0e3c39d5da0a179c20a421241590e5f3c613e` |
| Screenshot digests | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-2-before-diagnosis/screenshot-hashes.txt` | 325 | `d9b23007016db1231780f5d01de19d47ff7fb03a6ed1bff9364e59ea3130ef51` |
| Run status | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-2-before-diagnosis/run-status.txt` | 293 | `e893173d9488a8441e2dd9c493b411cfda6f2823744a9863d4ff351bdff631fd` |
| Device identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-2-before-diagnosis/device-identity.txt` | 298 | `265c299fe643739f0c63d2fc73f638d221a7aa9322b021641ab53bc0fedbbf56` |
| Device binding | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-2-before-diagnosis/device-binding.txt` | 205 | `6258b3334daf5630f35df414a604c37fb8b45b1fd6bcf72233c6108d482543c1` |
| Compute permit | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-2-before-diagnosis/compute-lock.txt` | 328 | `bfc4ae48a6af960836383abecfec73ee77cb377f9e7d922cf510a0dbc94a52f5` |
| Fixture identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-2-before-diagnosis/fixture-sha256.txt` | 410 | `0384ec26a4d239d57a63e23348d8047198668433e96286ab9b68c28b1b300f73` |
| APK identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-2-before-diagnosis/apk-sha256.txt` | 154 | `63f60d796a25c7b0dbbfdefc37bc678f943805022f240177fcafd6485b740ee2` |
| Git identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-2-before-diagnosis/git-identity.txt` | 690 | `3d584a296a382c106c534bb8844300274769a8691b5144264e3f2ac9fa084444` |
| Privacy, source | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-2-before-diagnosis/privacy-source-check.txt` | 74 | `349ad38e994e846dbaaac218d4543d30c53d3c2748c73c4045b4b16cbfa07f91` |
| Privacy, log | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-2-before-diagnosis/privacy-log-check.txt` | 86 | `c8788b6c946cf31fa9ef2a69434003014c67b76875156db2c8d0bed7fa3fb815` |
| Logcat probe | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-2-before-diagnosis/logcat-probe.txt` | 475 | `f6ce0f5cfc18fa63f58d678e7370fbc5cbb173d05fcc3ab0afb39dd822ebfb90` |
| Host `flutter pub get --offline` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-2-before-diagnosis/host-flutter-pub-get.log` | 397 | `349e3d1082e7dfafb1e16ab71e5a3499ef4482e1eb38bea8538dd0d7122b8fd8` |
| Collection provenance | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-2-before-diagnosis/collection-note.txt` | 1270 | `8b42d3189e46473a83ed40aa686117e3addadd8813ca75db17f05621ac4b6bc7` |

Privacy: `privacy-source-check.txt` `PASS` (no network API in the test file) and
`privacy-log-check.txt` `PASS` (no entered value, display name, or fixture path in
the integration log) in every run. Markers carry phase names, types, counts, and
geometry only; the diagnostic lines add sizes, rectangles, finder states, and
comparison flags, never document content.

Evidence hygiene: the driver's raw output keeps the trailing padding of `wm size`
and `wm density` and Flutter's Gradle progress line. Those trailing spaces were
stripped from the bundle's text files so that `git diff --check` stays clean; no
value changed, `markers-integration.txt` is byte-identical to the `T086_` lines of
the stripped log, and every size and digest above is of the committed bytes.

## 10. Reproducibility

1. Start from HEAD `69827d5` (branch `<owner>/t086`) with a clean tree.
2. Host gates (`apps/feldexa_app`): `dart format --output=none
   --set-exit-if-changed lib test integration_test`, `flutter analyze`,
   `flutter test --no-pub test/editor_composition_test.dart` (23/23), and
   `flutter test --no-pub` (589/589).
3. Start the AVD `T025_Pixel7_API35_KVM_20261115` only if `emulator-5554` is not
   attached, then wait for `sys.boot_completed=1`.
4. `python3 <orca-maintainer-skill>/scripts/compute_slot.py --wait -- env
   T086_COMPUTE_LOCK_HELD=1 T086_RUN_DIR=<fresh directory> T086_REPLACE_EVIDENCE=1
   bash tools/android/t086_drive_fill.sh` — expected `PASS` with
   `flutter_test_exit=0`, four distinct screenshots, and `T086_CLEANUP_DONE`.
5. Cleanup: the driver removes the pushed fixture and acknowledgements and clears
   the app data; this task neither restarted nor stopped the owner's emulator.

## 11. External attestation

None. This report records run-3 HEAD `ad5ddac` and run-4 HEAD `69827d5` with tree
`a91d5700a118eed3a8ecde35d988b48705904831`; the evidence commit that adds this
report cannot embed its own SHA.

## 12. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
