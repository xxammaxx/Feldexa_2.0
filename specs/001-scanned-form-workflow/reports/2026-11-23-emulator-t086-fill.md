# 2026-11-23 EMULATOR — T086 two-page touch fill journey (page 1 PASS, page 2 blocked)

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` (host checks `NONE`; `DEVICE` `NOT_RUN`) |
| Result | `FAIL` for the journey and `PARTIAL` for this class-run (page 1 `PASS`, page 2 `FAIL`); US4 acceptance not reached |
| Task / issue | `T086` / `#86` |
| Date / timezone | `2026-11-23 17:07 Europe/Berlin` (run 2 admission; run 1 in the same afternoon) |
| Revision | base commit `ddd3fd4` (predecessor), journey HEAD `a91ec0e`; tree clean except the pre-existing `apps/feldexa_app/android/gradlew.bat` line-ending change, which is never staged |
| External attestation | none; the candidate SHA and this report's own bytes/hash are not asserted here |
| Build identity | `de.feldexa.app` debug APK `apps/feldexa_app/build/app/outputs/flutter-apk/app-debug.apk`, 173616889 bytes, SHA-256 `4397d9968aa3f34cc90a0dcdb1b60ff94d170307b120bc943ac883895c96273e` |
| Toolchain | Flutter 3.47.7 stable, Dart 3.13, AGP/Gradle 9.3.1 via the Flutter toolchain, JDK 17.0.20.1 |
| Input | committed fixture `apps/feldexa_app/assets/fixtures/sf-001.pdf`, 5956 bytes, SHA-256 `22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038`, 2 pages |

## 1. Scope

This report records the two T086 emulator attempts for the US4 Independent Test
(issue #86): the existing two-page `sf-001.pdf` journey in
`apps/feldexa_app/integration_test/android_fill_test.dart` driven by
`tools/android/t086_drive_fill.sh`.

It proves page 1 of the journey on a real Pixel 7 API 35 emulator and records
why page 2 was not reached. It claims no PASS: US4 is not demonstrated, the T086
row in `tasks.md` stays `[ ]`, and `DEVICE` remains `NOT_RUN`.

Work in this task was limited to the test file and this evidence bundle: no
production file, package, dependency, or driver behaviour changed.

## 2. Revision and build

| Item | Value |
| --- | --- |
| Predecessor (run 1) HEAD | `ddd3fd4e7c4f20a77a986bac6262b9ab4a37801b` / tree recorded in run 1 `git-identity` output |
| Journey HEAD (run 2) | `a91ec0eddb0609d064abf20c7fb849cae900a325`, subject `fix(T086): keep overflow sheet state and continue the journey` |
| Journey tree | `4dabde5b2b21b04e6b73519c902e78f0d5725281` |
| Test file SHA-256 at run 2 | `1da45b8023afa35f8125630af02e997aa6f9c8f7b5054675873990751191c511` |
| Driver SHA-256 at run 2 | `5a271fd9902b331865078456b51351eb7f63206e5c37c0b52f912aaa997a87f7` |
| Build command | `flutter test --no-pub integration_test/android_fill_test.dart -d emulator-5554` (Gradle `assembleDebug`, 105.9 s, incremental) |
| Dirty files | none at run start; the driver's commit-before-run gate passed |

The driver refuses to run on a dirty tree except for the pre-existing
`gradlew.bat` line-ending change, so the recorded hashes belong to a committed
revision.

## 3. Environment

```text
EMULATOR: Pixel 7 API 35, run label t086-fill-run2 (no Orca command, no Orca allocation);
          serial emulator-5554, AVD T025_Pixel7_API35_KVM_20261115;
          system image google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925 userdebug;
          1080 x 2400 at 420 dpi; RAM 4014392 kB; qemu=1; boot_completed=1;
          APK apps/feldexa_app/build/app/outputs/flutter-apk/app-debug.apk SHA-256 4397d996…;
          build mode debug, no flags; no physical device addressed
```

The emulator was not connected before this task and was started by this task:

```text
emulator -avd T025_Pixel7_API35_KVM_20261115 -port 5554 -no-window -no-audio \
         -no-boot-anim -no-snapshot -gpu swiftshader_indirect -no-metrics
```

and stopped afterwards with `adb -s emulator-5554 emu kill`. The wirelessly
attached Samsung S23 transport (`adb-RFCW80SMY4J-…`) is recorded in
`device-binding.txt` as an attached transport and was never addressed
(`non_emulator_transports_addressed=none`).

The whole run executed inside the shared heavy-work permit:

```text
python3 <orca-maintainer-skill>/scripts/compute_slot.py --wait -- \
  env T086_COMPUTE_LOCK_HELD=1 T086_RUN_DIR=<fresh tmp run directory> \
  bash tools/android/t086_drive_fill.sh
```

`compute-lock.txt` records `ACQUIRED` at `2026-11-23T16:07:49Z`, the lock path
`<tmp>/orca-maintainer-heavy-<uid>.lock`, `orca_command_used=0`, and — after the
run — `SETTLED`.

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `dart format --output=none --set-exit-if-changed integration_test/android_fill_test.dart` (`apps/feldexa_app`) | 0 | `Formatted 1 file (0 changed)` on the console | `PASS` |
| 2 | `flutter analyze` (`apps/feldexa_app`) | 0 | `No issues found!` on the console | `PASS` |
| 3 | `flutter test --no-pub test/field_value_sheet_test.dart test/field_overflow_sheet_test.dart` (`apps/feldexa_app`) | 0 | `+42: All tests passed!` on the console | `PASS` |
| 4 | `tools/android/t086_drive_fill.sh` inside `compute_slot.py --wait` (`<repo-root>`) | 1 | `reports/artifacts/2026-11-23-t086-fill/integration-android-t086.log` | `FAIL` |
| 5 | `python3 tools/evaluation/check_evidence_docs.py --report specs/001-scanned-form-workflow/reports/2026-11-23-emulator-t086-fill.md` (`<repo-root>`) | 0 | `PASS artifacts`, `PASS report binding`, `18 artifact rows`, `OK: evidence documents and attestation are consistent` on the console | `PASS` |
| 6 | `dart tools/evaluation/validate_report.dart` on this report | - | - | `ABSENT` (the validator targets the strict class-run template; every T086 emulator sibling report is hand-written and does not pass it either) |

Checks 1-3 are the host gates for the changed test file. The focused pair is the
product seam the fix relies on: `field_overflow_sheet_test.dart` pins both the
pop-on-normal-save path ("a text that still fits commits without a warning and
closes") and the stay-open FLD-001 path ("the FLD-001 warning is visible
immediately after the commit").

## 5. Results

### 5.1 Run 1 (`ddd3fd4`, run directory `feldexa-t086-run.Q1km22`)

Reached the FLD-001 case on page 1 and failed at
`android_fill_test.dart:728` in `_commitTextLike` (`Iterable.single` →
`Bad state: No element`) via `_fillField:773` and `main:1021`.

Cause: the assertion "the complete draft is still in the control"
(`android_fill_test.dart:727-731`) ran after `_waitForCommit` for every
text-like field, but `FieldValueSheet._save()` pops the sheet after a successful
save that does not overflow
(`apps/feldexa_app/lib/features/editor/field_value_sheet.dart:529-538`), so the
`fieldTextControlInputKey` control was already unmounted. The overflow field
itself passed (marker `VALUE_SAVED:TYPE=text:RUNES=215:OVERFLOW=1`); the next
seeded text field hit the empty finder.

The earlier working hypothesis — "the overflow case leaves the value sheet open,
so the following field finds no fresh control" — is refuted: `ddd3fd4` already
closed the sheet explicitly after the overflow phase
(`android_fill_test.dart:1018-1019`) and run 2 shows the following field opening,
committing and storing its value.

### 5.2 The fix (`a91ec0e`)

One file, 9 insertions / 5 deletions, no production change: the post-commit
draft-control assertion moved into the `expectOverflow` branch, where the
production sheet deliberately stays on the field. The non-overflow branch keeps
its existing guarantees: the committed value is asserted from
`state.content` immediately after the verified revision, the sheet-closed
condition is asserted, and the reopened control is verified later in the journey
(`_expectFieldEditableAndPreserved`, the `page1-preserved` screenshot, and the
post-navigation edit). No FLD-001 assertion was removed and no field, page, or
scenario was dropped.

### 5.3 Run 2 (`a91ec0e`, run directory `feldexa-t086-run.20261123T160541Z-b`)

Device gate passed (exactly one attached emulator transport, expected serial,
AVD, API 35, `qemu=1`, boot completed), the fixture matched on host and device,
and the app started with cleared data.

Authoritative marker sequence (`markers-integration.txt`):

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
```

Proven on the real emulator, the real encrypted store, and the production
composition:

| Scenario | Expected | Observed | Verdict |
| --- | --- | --- | --- |
| Import + two-page analysis of the committed fixture | 2 pages, terminal analysis | `SUGGESTIONS=80`, both pages complete | `PASS` |
| One real machine text field confirmed per page through the production review surface | 2 confirmed | `TWO_MACHINE_FIELDS_CONFIRMED:PAGES=2` | `PASS` |
| Seven typed fields seeded through `addField`, one verified revision, reopen with analysis skipped | 9 fields, 5 on page 1 / 4 on page 2 | `FIELDS=9:PAGES=2:ANALYSIS=skipped` | `PASS` |
| FLD-001: entered text larger than the recognised region keeps every rune | warning visible, `TRUNCATED=0` | `ENTERED_RUNES=215:STORED_RUNES=215:TRUNCATED=0` + `overflow-warning` screenshot | `PASS` |
| Page-1 touch fill: text, number, date, checkbox | committed values, canonical forms | 4 markers, `NUMBER_CANONICAL:MATCH=1`, `DATE_CANONICAL:MATCH=1`, `CHECKED=1` | `PASS` |
| Page-1 completion screenshot | 5 filled fields | `PAGE1_FILLED:FIELDS=5` + `page1-values` screenshot | `PASS` |
| Page-2 touch fill (text, multiline, drawn signature) | three committed values | no sheet opened on the first page-2 field | `FAIL` |
| Page round trip, every reopened control, verified store read-back | preserved, editable, no truncation | not reached | `ABSENT` |
| Cleanup marker `CLEANUP_DONE` | present | not reached (the driver stops the app and clears its data on exit) | `ABSENT` |

Screenshots captured: 2 of the 4 phases, both distinct
(`overflow-warning` 211257 bytes `a2d1e46c…`, `page1-values` 189245 bytes
`ba15a1b0…`). `page2-signed` and `page1-preserved` do not exist because the
journey did not reach them.

### 5.4 The blocker

```text
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞
The following TestFailure was thrown running a test:
tapping the text field did not open the value sheet (bounded wait 120s expired)
#1 _pumpUntil (android_fill_test.dart:169)
#2 _openValueSheet (android_fill_test.dart:344)
#3 _fillField (android_fill_test.dart:771)
#4 main.<anonymous closure> (android_fill_test.dart:1055)
```

`main:1055` is the first page-2 fill
(`_fillField(..., seeded[_SeededRole.pageTwoText]!, _pageTwoTextValue)`),
immediately after `T086_PAGE_VISIBLE:PAGE=2`. The page strip did bring page 2
into view (its scale-1 raster completed:
`PAGE_RENDER_START/OK:P=1:W=1563:H=2210`), and the tap then produced no sheet,
no visible error, and no exception for 120 s. The driver aborted at the missing
`T086_SCREENSHOT_PAGE2_SIGNED` marker and exited 1.

Established facts:

- the tap point is derived from the live mapping (`_screenPoint` = page-view
  top-left plus `PageViewMapping.displayToView`), i.e. it is the field centre for
  the transform that was current when the point was computed;
- both fixture pages are identical A4 boxes (`MediaBox [0 0 595.28 841.89]`, no
  CropBox, rotation 0), so page 2 has no coordinate-origin difference that could
  offset the field rectangle;
- the post-run logcat probe shows no Flutter engine exception and no app crash
  (0 `E/flutter`, 0 `FATAL EXCEPTION`, `logcat-probe.txt`).

Candidate mechanisms, each a silent path in the product; the run evidence cannot
distinguish them and the journey exposes no observable state at the tap:

1. the tap reached no selection surface, i.e. the point left the page view's
   clipped area between `_screenPoint` and the pointer dispatch. The live binding
   renders real frames between awaits, and the `page1-values` phase queues
   platform-driven relayouts (the sheet closes, the IME hides) that re-run
   `PageViewController.setViewportSize` and re-clamp the pan
   (`page_view.dart:978-1004`, `_clampPanFor` `:1179-1199`). The screenshot of
   that phase shows the review panel and the open IME, i.e. the page viewport is
   squeezed while the content is 595 × 1684 logical points;
2. a miss inside the page: `hitTestFieldSelection` returns null and the surface
   selects nothing without feedback
   (`packages/feldexa_ui/lib/src/field_selection.dart:88-105`, `:360-375`);
3. the tap was accepted but `_openFieldValueSheet` returned early because
   `_valueSheetOpen` was still true
   (`apps/feldexa_app/lib/features/editor/editor_screen.dart:1497-1502`).

Nothing was weakened to move past the blocker: the assertion, the scenario, the
fields, and the driver handshake are unchanged. The journey needs one more
emulator run with the observable state at that seam (viewport size, both page
rects, selection, `_valueSheetOpen`, tap point) dumped into the failure message —
the diagnostic pattern `ff74c62` established for the T086D journey.

## 6. Performance

No performance claim.

## 7. Limitations

- Not reached (`ABSENT`): page-2 fills, the drawn signature, the page round
  trip, the reopened-control pass, the verified encrypted-store read-back, and
  the `CLEANUP_DONE` marker. US4 is therefore not demonstrated.
- `DEVICE` acceptance, TalkBack traversal, stylus/IME variants and any
  performance claim are `NOT_RUN`.
- The emulator run proves wiring and real touch behaviour, not silicon-specific
  behaviour; emulator timings are never the SC-004 device claim.
- The two allowed emulator attempts are spent (run 1 and run 2). A third run is
  outside this task's budget.
- The driver reports `SCREENSHOT`-marker handshakes only; it captures no
  screenshot at an arbitrary failure point, so the blocking moment itself is not
  imaged.
- Because the driver exits through `fail()` before its evidence step, several
  bundle files were collected after the abort; `collection-note.txt` lists which
  file came from the driver and which was collected afterwards, and no
  driver-attributed claim rests on the latter.

## 8. Evidence classes

| Class | Result | Basis |
| --- | --- | --- |
| `EMULATOR` | `FAIL` (page 1 `PASS`, page 2 `FAIL`) | Pixel 7 API 35 KVM emulator `emulator-5554`, run 2 |
| `DEVICE` | `NOT_RUN` | no physical device addressed; the wireless S23 transport was recorded only |
| `SIMULATED` | `NOT_RUN` | not part of this task |

The classes are never merged: the host gates in §4 are `NONE` (not a runtime
class) and prove nothing about Android behaviour.

## 9. Artifacts

All paths are repository-relative; sizes and digests are of the committed bytes.
Every file came from the driver at run time or was collected afterwards exactly
as `collection-note.txt` describes.

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Emulator run log | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/integration-android-t086.log` | 7982 | `c8c00f0e37105d4b03b156eb5101e541a641ad3978f6498e7d2d122d7e96352f` |
| Journey markers | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/markers-integration.txt` | 1416 | `f35d0d10c0470e4204934d4c400e1fe1b97125c6f6cf5c6bb0fc89a4d6618b56` |
| Screenshot phase records | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/marker-sequence.txt` | 186 | `2e0fe26a0d1d38d71f606a52127a4727c05ffa4689a20dc5e31e6cea6849b601` |
| Screenshot `overflow-warning` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/screenshots/overflow-warning.png` | 211257 | `a2d1e46cc298bf05ebcfa57edc4f5537475ec82fa21eed381d3ff976dca9a5a4` |
| Screenshot `page1-values` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/screenshots/page1-values.png` | 189245 | `ba15a1b09f91fb0dfbf2c58454d0e3c39d5da0a179c20a421241590e5f3c613e` |
| Screenshot digests | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/screenshot-hashes.txt` | 325 | `d9b23007016db1231780f5d01de19d47ff7fb03a6ed1bff9364e59ea3130ef51` |
| Run status | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/run-status.txt` | 293 | `e893173d9488a8441e2dd9c493b411cfda6f2823744a9863d4ff351bdff631fd` |
| Device identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/device-identity.txt` | 298 | `265c299fe643739f0c63d2fc73f638d221a7aa9322b021641ab53bc0fedbbf56` |
| Device binding | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/device-binding.txt` | 205 | `6258b3334daf5630f35df414a604c37fb8b45b1fd6bcf72233c6108d482543c1` |
| Compute permit | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/compute-lock.txt` | 328 | `bfc4ae48a6af960836383abecfec73ee77cb377f9e7d922cf510a0dbc94a52f5` |
| Fixture identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/fixture-sha256.txt` | 410 | `0384ec26a4d239d57a63e23348d8047198668433e96286ab9b68c28b1b300f73` |
| APK identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/apk-sha256.txt` | 154 | `63f60d796a25c7b0dbbfdefc37bc678f943805022f240177fcafd6485b740ee2` |
| Git identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/git-identity.txt` | 690 | `3d584a296a382c106c534bb8844300274769a8691b5144264e3f2ac9fa084444` |
| Privacy, source | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/privacy-source-check.txt` | 74 | `349ad38e994e846dbaaac218d4543d30c53d3c2748c73c4045b4b16cbfa07f91` |
| Privacy, log | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/privacy-log-check.txt` | 86 | `c8788b6c946cf31fa9ef2a69434003014c67b76875156db2c8d0bed7fa3fb815` |
| Logcat probe | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/logcat-probe.txt` | 475 | `f6ce0f5cfc18fa63f58d678e7370fbc5cbb173d05fcc3ab0afb39dd822ebfb90` |
| Host `flutter pub get --offline` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/host-flutter-pub-get.log` | 397 | `349e3d1082e7dfafb1e16ab71e5a3499ef4482e1eb38bea8538dd0d7122b8fd8` |
| Collection provenance | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-23-t086-fill/collection-note.txt` | 1270 | `8b42d3189e46473a83ed40aa686117e3addadd8813ca75db17f05621ac4b6bc7` |

Privacy: `privacy-source-check.txt` PASS (no network API in the test file) and
`privacy-log-check.txt` PASS (no entered value, display name, or fixture path in
the integration log). Markers carry phase names, types and rune counts only.

Evidence hygiene: the raw driver output keeps the trailing padding of `wm size`
and `wm density` in `device-identity.txt` and Flutter's Gradle progress line in
`integration-android-t086.log`. Those trailing spaces were stripped so that
`git diff --check` stays clean; no value changed, `markers-integration.txt` is
byte-identical to the marker lines of the stripped log, and the sizes and
digests above are the committed (stripped) bytes.

The checker binds these rows to a committed tree. It was first executed while
this report and bundle were still untracked (it then validated the pre-existing
reports only) and was executed again against the evidence commit that adds this
report and bundle, where it verified all 18 recorded rows and the report binding
(`PASS artifacts: HEAD`, `PASS report binding`, `18 artifact rows`). Every size
and digest above is the committed byte content.

## 10. Reproducibility

1. Start from journey HEAD `a91ec0e` (branch `<owner>/t086`) with a clean tree.
2. Host gates (`apps/feldexa_app`): `dart format --output=none
   --set-exit-if-changed integration_test/android_fill_test.dart`,
   `flutter analyze`,
   `flutter test --no-pub test/field_value_sheet_test.dart test/field_overflow_sheet_test.dart`
   — expected 0 changed, no issues, 42/42 passed.
3. Start the AVD `T025_Pixel7_API35_KVM_20261115` only if `emulator-5554` is not
   attached, then wait for `sys.boot_completed=1`.
4. `python3 <orca-maintainer-skill>/scripts/compute_slot.py --wait -- env
   T086_COMPUTE_LOCK_HELD=1 T086_RUN_DIR=<fresh directory> bash
   tools/android/t086_drive_fill.sh` — expected `PASS` only when the journey
   completes; this run stops at the first page-2 field.
5. Cleanup: the driver removes the pushed fixture and acknowledgements and clears
   the app data; `adb -s emulator-5554 emu kill` stops an emulator that this task
   started.

## 11. External attestation

None. This report records base commit `ddd3fd4`, journey HEAD `a91ec0e` and tree
`4dabde5b2b21b04e6b73519c902e78f0d5725281`; the evidence commit that adds this
report cannot embed its own SHA.

## 12. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
