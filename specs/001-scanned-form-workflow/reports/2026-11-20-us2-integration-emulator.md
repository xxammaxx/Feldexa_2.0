# 2026-11-20 EMULATOR — Issue #217 Phase B2 visible suggestion review and US2 journey

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` |
| Result | `PASS` for the emulator journey and every claimed B2 criterion; conditional sub-checks are listed as `UNVERIFIED` in §7 |
| Task / issue | US2-INT-B2 / `#217` Phase B2 |
| Date / timezone | `2026-11-20 13:20–13:29 Europe/Berlin` (final run) |
| Revision | base `c1141470ad63c110ebe02277f0f98c70ee2cf26a`; implementation commit `5540d8a32aedfc6edb8003309429912e893c5397`, tree `80b1fbbb702ff86fc6e05f1d27ecdf33386ac310`; this report and its artifacts are in the following docs-only commit, whose SHA/tree are recorded in `handoff-us2-int-b2.json` |
| Build identity | version `0.1.0+1`; mode `debug`; APK `apps/feldexa_app/build/app/outputs/flutter-apk/app-debug.apk`, SHA-256 `5ed8ab4e32f51e1dc0f1484773df0bfbc72846ecf5e0784445129b2caded1913`; built and installed by the exact `flutter test` invocation in §5; no release or release-signing claim |
| Toolchain | Flutter `3.47.7` stable (framework `abaf9c5237`), Dart `3.13.5`; Gradle `9.3.1`; JDK `27.0.1` (default host Java); adb `1.0.41` (`37.0.1`); emulator `37.2.13.0`; pdfrx `2.12.0` (PDFium); Android SDK platforms 34/35/36 installed |
| Input | committed synthetic fixture `sf-001.pdf` (2 pages, SHA-256 `22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038`, 5,956 bytes); no real or personal document |

## 1. Scope

This is the Phase B2 acceptance run for issue #217. It proves the visible
suggestion review surface and the US2 journey on the real Android emulator
through the production `main()` composition:

- real `ACTION_OPEN_DOCUMENT` system picker → `AndroidImportClient` →
  protected initial revision → editor;
- first analysis through the Phase A `AnalyzeDocument` pipeline (200 DPI
  raster, geometry detectors, bundled ML Kit Latin OCR, typing, confidence,
  conflict graph) and one autosave revision;
- visible `SuggestionReviewPanel` grouped by page with German type names,
  one-based page numbers, 1/8 pt display positions, integer confidence,
  fallback labels, uncertainty and conflict markers;
- confirm, reject, undo-rejection, undo-confirmation, final confirm + reject,
  and a protected-store read-back proving suggestions, resolutions, and
  machine provenance persisted;
- screenshots at `editor-ready`, `suggestions-visible`, and `after-review`,
  plus device identity, fixture/APK hashes, test log, and marker-filtered
  logcat.

The panel is list-only in B2. Page-overlay painting (T069) and the full
conflict resolution sheet (T068) are explicitly not claimed. A user-facing
document list/reopen is T095 and is not claimed; persistence is proved through
`AndroidStoreClient.loadDocument`.

### Spec Kit implementation provenance

- The registered OpenCode `speckit-implement` skill was invoked before any file
  edit with the issue #217 Phase B2 scope in the invocation preamble. Exact
  invocation and pre-execution evidence are recorded in
  `artifacts/2026-11-20-us2-integration/spec-kit-invocation.txt`.
- `.specify/extensions.yml` exists with `hooks: {}`; no before/after hook was
  registered or executed.
- Checklist markers were observed read-only and not modified:
  `requirements.md` 16/16 checked (`PASS`), `precision-testability.md` 36
  reviewer-owned unchecked markers (`FAIL` as a reviewer gate), and
  `precision-testability-assessment.md` with no checkbox items. The dispatch
  pre-authorized proceeding; no reviewer approval is claimed.
- `tasks.md` was not edited; task markers remain reviewer/coordinator-owned.

## 2. Revision and build

The run started from base commit
`c1141470ad63c110ebe02277f0f98c70ee2cf26a` and delivered implementation commit
`5540d8a32aedfc6edb8003309429912e893c5397`
(tree `80b1fbbb702ff86fc6e05f1d27ecdf33386ac310`). The app/test/tool files in
the emulator run and this implementation commit are identical; only the report
and its artifacts were added afterwards.

The run's `flutter test integration_test/android_us2_journey_test.dart -d
emulator-5554` built and installed the debug APK from this tree. The APK is a
git-ignored build output bound by `apk-sha256.txt`; it is not committed.

### Single protected load and bounded failure

The earlier diagnostic run exposed a shared-store result-path hang: the editor
revision load and the viewer's source-bytes read-back both used the same
`AndroidStoreClient`/operation result stream. Phase B2 now loads the revision
and source **once** in `EditorScreen` and completes one in-memory
`Completer<Uint8List?>`; on the Android editor path the viewer awaits that same
protected bytes value and does not issue a second `store.loadDocument` for the
same document. A 30-second
`editorLoadTimeout` turns a hung load into the deterministic German
`analysis-failed` state instead of an infinite pending editor. The fail-closed
non-Android runtime preserves the existing US1 viewer read-back closure when no
editor runtime exists; it does not invent analysis or a persisted revision. Host
tests in `editor_analysis_test.dart` prove one store load and the bounded
failure.

### Deterministic panel interaction

The review panel is a non-lazy `Column` inside one `SingleChildScrollView`, so
every suggestion row stays built after a confirm/reject rebuild. The emulator
test targets each row with `ensureVisible` on the keyed row/button and then
taps the keyed control; it does not call `scrollUntilVisible` on a possibly
missing scrollable. This removes the post-confirm `Bad state: No element`
interaction failure observed in the earlier diagnostic run without weakening
any assertion.

## 3. Environment

```text
EMULATOR: Pixel 7 API 35, exclusive Orca allocation
          AVD T025_Pixel7_API35_KVM_20261115
          serial emulator-5554; exactly one adb device attached
          fingerprint google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys
          guest model sdk_gphone64_x86_64; ro.build.version.sdk=35
          ro.build.version.release=15; ro.product.cpu.abi=x86_64
          ro.kernel.qemu=1; ro.boot.qemu.avd_name=T025_Pixel7_API35_KVM_20261115
          sys.boot_completed=1
          RAM 4096 MB (MemTotal 4014392 kB)
          1080x2400 at density 420; portrait during the run
          Orca controller stream scrcpy://emulator-5554, codec h264
          build mode debug
          APK apps/feldexa_app/build/app/outputs/flutter-apk/app-debug.apk
          APK SHA-256 5ed8ab4e32f51e1dc0f1484773df0bfbc72846ecf5e0784445129b2caded1913
```

Device identity and the Orca session binding are recorded in
`device-identity.txt` and `orca-emulator-session.json`. The AVD was started and
attached through the Orca CLI for this worktree; this task did not wipe, reset,
snapshot, or reconfigure it. KVM acceleration was not freshly probed; the guest
reports the expected QEMU/AVD properties and a completed boot. No
physical-device, silicon, or performance claim follows.

The fixture was pushed to `/sdcard/Download/us2-sf-001.pdf` and
`/data/local/tmp/us2-fixtures/sf-001.pdf`; all three host/picker/staging
SHA-256 values match the committed fixture (`fixture-sha256.txt`).

## 4. Commands and checks

### 4.1 EMULATOR runtime checks

| # | Command (cwd) | Exit | Log / evidence | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `tools/android/us2_drive_journey.sh` (repository root; Orca/serial/API-35 preflight, fixture push, test start, real DocumentsUI drive, screenshot handshakes, evidence capture, cleanup) | `0` | `integration-android-us2.log`, `picker-sequence.txt`, `device-identity.txt`, `orca-emulator-session.json` | `PASS` |
| 2 | `flutter test integration_test/android_us2_journey_test.dart -d emulator-5554` (in `apps/feldexa_app`; invoked by check 1) | `0` | `integration-android-us2.log` | `PASS` |
| 3 | `adb -s emulator-5554 shell uiautomator dump` / `adb pull` / `input tap` (inside check 1) | `0` | `picker-round1-downloads.xml`, `picker-sequence.txt` | `PASS` |
| 4 | `adb -s emulator-5554 exec-out screencap -p` at the three test-driven handshakes (inside check 1) | `0` | `screenshots/editor-ready.png`, `suggestions-visible.png`, `after-review.png` | `PASS` |
| 5 | `adb -s emulator-5554 logcat -d -v threadtime` and marker filter (inside check 1) | `0` | `logcat-flutter.log`, `logcat-us2-markers.log` | `PASS` |

The real picker was driven in one attempt: `DocumentsUI` opened from the app's
import action and the exact `us2-sf-001.pdf` row was tapped at `296,983`. The
test log shows the full marker sequence:

```text
US2_PICKER_READY
US2_EDITOR_READY
US2_SUGGESTIONS_VISIBLE
US2_SUGGESTION_COUNT:80
US2_PAGE_COUNTS:28,52
US2_UNSURE_COUNT:0
US2_CONFLICT_COUNT:16
US2_PAGE_FAILURES:0
US2_LABEL_NULL_COUNT:13
US2_MIN_CONFIDENCE:0.59
US2_EXPECTED_FIELDS_ASSERTED:9
US2_FALLBACK_ROW_ASSERTED
US2_CONFLICT_MARKERS_ASSERTED
US2_UNSURE_MARKER_UNVERIFIED
US2_CONFIRM_TARGET:s_p0_0014:p0:text
US2_REJECT_TARGET:s_p0_0001:p0:text
US2_PANEL_ROW_METADATA_ASSERTED
US2_CONFIRMED_SAVED
US2_FALLBACK_LABEL_CONFIRMED
US2_REJECTED_SAVED
US2_REJECTION_UNDONE
US2_CONFIRMATION_UNDONE
US2_AFTER_REVIEW
US2_STORE_VERIFIED
US2_CLEANUP_DONE
```

The test process ended with `07:31 +1: All tests passed!` and exit `0`. The
screenshot handshakes are acknowledged by the driver through
`/data/local/tmp/us2-fixtures/ack-<phase>`, so each image is captured while the
journey is paused at the intended state rather than racing the test.

`logcat-us2-markers.log` records the activity transitions (app launch and
`ACTION_OPEN_DOCUMENT` `PickActivity`). Flutter `debugPrint` markers are streamed
to the host test log by `flutter test -d`, not to Android logcat; no document
content is logged in either artifact.

### 4.2 Host-only checks (`NONE` class; not runtime evidence)

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `flutter pub get --offline` (`apps/feldexa_app`) | `0` | `host-flutter-pub-get.log` | `PASS` |
| 2 | `flutter analyze --no-pub` (`apps/feldexa_app`) | `0` | `host-flutter-analyze.log` | `PASS` |
| 3 | `flutter test --no-pub` (`apps/feldexa_app`) | `0` | `host-flutter-test.log` | `PASS`, `291` tests, `0` failures |
| 4 | `dart format --output=none --set-exit-if-changed` on all 11 changed Dart files (`apps/feldexa_app`) | `0` | `host-dart-format.log` | `PASS`, `Formatted 11 files (0 changed)` |
| 5 | `flutter analyze --no-pub` (`packages/feldexa_application`) | `0` | `host-application-analyze.log` | `PASS` |
| 6 | `flutter test --no-pub` (`packages/feldexa_application`) | `0` | `host-application-test.log` | `PASS`, `135` tests, `0` failures |
| 7 | `git diff --check` and repository checks (worktree root) | `0` | `host-git-checks.log` | `PASS` |

The app suite finished with `00:28 +291: All tests passed!`; the stated B1
baseline was 281. The exact B2 delta is 10 tests: 6 in
`editor_review_panel_test.dart` and 4 in `editor_analysis_test.dart`. The
application package remains at its 135-test baseline.

The German-string gate required a coordinator-approved, test-only allowlist
update: exactly the 21 B2 review-panel ARB keys were added to
`_nonCodeArbKeys` in `test/german_strings_test.dart` with a comment. No
production catalog text changed and no audit check was weakened.

## 5. Results

### 5.1 Panel rendering and observed detector output

The first analysis completed and saved one autosave revision. `sf-001` yielded
**80** canonical suggestions: **28 on page 1** (page index 0) and **52 on
page 2** (page index 1). Type counts: 35 `text`, 35 `checkbox`, 4 `date`,
4 `number`, 2 `multiline`, 0 `signature`. Confidence range 0.59–0.93; no
suggestion was below 0.50. 13 suggestions had no credible label and exercised
the German „Feld“ fallback. 16 suggestions carried non-empty `conflictsWith`
(8 symmetric pairs on page 2).

The emulator test asserted these nine representative detector outputs with
their exact canonical 1/8 pt positions and confidence bands:

| Suggestion | Page (1-based) | Type | x / y / w / h (pt) | Confidence | Band asserted |
| --- | ---: | --- | --- | ---: | --- |
| `s_p0_0010` | 1 | text | 190.125 / 147.625 / 299.875 / 18 | 0.59 | 0.55–0.65 |
| `s_p0_0012` | 1 | date | 190.125 / 215.625 / 299.875 / 18 | 0.71 | 0.65–0.75 |
| `s_p0_0015` | 1 | text | 190.125 / 353.875 / 299.875 / 18 | 0.83 | 0.75–0.90 |
| `s_p0_0020` | 1 | checkbox | 190.5 / 502.5 / 9.25 / 9.375 | 0.83 | 0.75–0.90 |
| `s_p0_0022` | 1 | checkbox | 410.375 / 502.5 / 9.375 / 9.375 | 0.83 | 0.75–0.90 |
| `s_p1_0009` | 2 | multiline | 190.5 / 152.25 / 348 / 75.625 | 0.83 | 0.75–0.90 |
| `s_p1_0024` | 2 | number | 427 / 314.625 / 104 / 18 | 0.93 | 0.85–0.98 |
| `s_p1_0041` | 2 | checkbox | 190.5 / 480.25 / 9.25 / 9.75 | 0.83 | 0.75–0.90 |
| `s_p1_0047` | 2 | date | 190.125 / 553.625 / 299.875 / 18 | 0.93 | 0.85–0.98 |

The panel showed the visible row label, German type name, one-based page,
1/8 pt position, and integer confidence for the confirm target; the fallback
row and conflict marker were asserted after the deterministic
`ensureVisible` scroll. The host panel test additionally covers deterministic
page/position/type ordering, grouping, both empty states, all six German type
names (including `signature`), both action callbacks, undo, busy disabling, and
no overflow at 200 % text scale.

### 5.2 Confirm, reject, undo, and persistence

- **Confirm** `s_p0_0014` (page 0 text, no label, confidence 0.59): saved a new
  `RevisionKind.autosave`; the generated field label is `Feld 1` (fallback),
  provenance `machine`, page/rect/type copied exactly from the suggestion, and
  `suggestionConfidence` `0.59`; timestamps are UTC. The visible field count
  changed to `1 Feld bestätigt` and the row left the unresolved queue.
- **Reject** `s_p0_0001` (page 0 text, confidence 0.59): saved a new autosave;
  the suggestion resolution became `rejected`, no field was created, and the
  row left the unresolved queue. The undo affordance appeared.
- **Undo rejection**: restored `s_p0_0001` to `unresolved` and saved; the
  confirmed field remained.
- **Undo confirmation**: removed the untouched generated `Feld 1`, restored
  `s_p0_0014` to `unresolved`, and saved. No suggestion was duplicated or
  dropped.
- **Final state**: `s_p0_0014` confirmed and `s_p0_0001` rejected, then the
  editor returned to the start surface. A separate `AndroidStoreClient`
  `loadDocument` read-back proved: 2 pages; 80 unique suggestions with the same
  id set; `s_p0_0014 == confirmed`; `s_p0_0001 == rejected`; one field with
  machine provenance, the same id/label/rect/type/confidence; both pages
  `AnalysisState.complete`. The test then deleted the document and restored the
  pre-run document set.

`expectedHead` was advanced from each successful save's returned
`latestRevisionId` (host test asserts the sequence across confirm, reject, and
both undos); the emulator journey exercised the same path for its multiple
saves. No duplicate suggestions or lost confirmed fields were observed.

### 5.3 Conflict and page-failure sub-checks

- **Conflict**: verified. `sf-001` produced 8 symmetric overlapping pairs on
  page 2 (`s_p1_0007/0008`, `0013/0030`, `0017/0018`, `0022/0025`,
  `0023/0024`, `0028/0029`, `0034/0035`, `0039/0040`). The emulator test
  asserted both sides of a symmetric pair and the German `Konflikt` marker on
  the rows. This is the B2 list marker only; the full conflict sheet T068 and
  overlay T069 remain separate tasks.
- **Page failure**: `sf-001` has no unreadable/damaged page and the import
  reported `PAGE_FAILURES:0`; no page-failure assertion was executed in this
  journey. Page-failure isolation is therefore **UNVERIFIED on the emulator**
  in this run; T061/T062 remain open. The B1 host test still covers the
  isolated failure path, but it is not an emulator claim.

## 6. Screenshots

| State | Path | Observed |
| --- | --- | --- |
| `editor-ready` | `screenshots/editor-ready.png` | Editor route with `Seite 1 von 2`, `Analyse ausstehend`, page strip, and viewer before the first analysis completed |
| `suggestions-visible` | `screenshots/suggestions-visible.png` | `Vorschläge`, `80 offen`, `Keine Felder bestätigt`, first suggestion rows with German metadata, and the rendered page |
| `after-review` | `screenshots/after-review.png` | `78 offen`, `1 Feld bestätigt`, `1 bestätigt, 1 abgelehnt`, `Rückgängig`, and the remaining review rows after the final confirm + reject |

The screenshots are device framebuffer captures, not golden-image comparisons.
No pixel-fidelity, contrast, TalkBack, or 200 % text-scale claim is made from
them; the 200 % text-scale panel check is a host widget test.

## 7. UNVERIFIED / not claimed

The following were **not run or not observed** and are not presented as passes:

- **Uncertainty marker below 0.50 on the emulator**: `sf-001` produced
  `UNSURE_COUNT:0` (minimum confidence 0.59), so the emulator panel could not
  show `unsicher`. The host panel test covers the below-0.50 marker; the
  emulator sub-check remains `UNVERIFIED`.
- **Signature type suggestion on the emulator**: the detector produced 0
  `signature` suggestions; signature-line candidates were typed as `text`.
  This is a detector/type-inference gap (T053/T055/T061), not a B2 panel gap.
  The host panel test covers the German `Unterschrift` type rendering.
- **Page-failure isolation on the emulator**: no committed fixture used in this
  run has an unreadable/damaged page. T061/T062 remain open.
- **Full conflict sheet and field overlay**: T068/T069 are not in B2. Only the
  list row and conflict marker are claimed.
- **User-facing document list/reopen**: T095 is not implemented in this tree;
  persistence is proved through `AndroidStoreClient.loadDocument`, not a UI
  reopen.
- **TalkBack traversal, contrast review, 200 % device text scale, performance,
  release APK, physical device, and SC-004/SC-016/SC-018 measurements**:
  `ABSENT`. No such claim is made.
- **Full ground-truth field recall**: the nine asserted suggestions are real
  detector outputs, not a complete ground-truth match. The run does not claim
  that every expected form field was detected with the ground-truth type; that
  belongs to recognition quality tasks (T059/T060/T061/T063).
- **Independent review of this candidate**: not performed here; the review
  table in §11 is intentionally blank.

## 8. Limitations

- The picker driver finds `DocumentsUI` nodes by exact text and bounds; the
  committed `picker-round1-downloads.xml` and `picker-sequence.txt` make this
  run replayable on the same system image but are not a cross-version UI
  contract.
- The emulator run is debug, portrait, `emulator-5554`; it is not a physical
  device, release, performance, or silicon-backed key claim.
- `sf-001` is a synthetic fixture. The long OCR first-run latency is an
  emulator/toolchain observation, not a product performance result; the test
  uses a 900-second analysis bound and a 30-second load bound.
- The review panel is a bounded 320 dp list with non-lazy rows; this is
  intentional for deterministic B2 interaction, not a final overlay design.
- The pre-existing unstaged `apps/feldexa_app/android/gradlew.bat` CRLF/LF-only
  modification was present before this task and is excluded from every commit.

## 9. Artifacts

All paths are repository-relative and committed with this report. The APK is a
git-ignored local build output bound by `apk-sha256.txt`; it is not committed.

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `apk-sha256.txt` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration/apk-sha256.txt` | 178 | `e54314195f621427d16de074975ea49080718c9a1c80595adbc5c1fecb11cb43` |
| `device-identity.txt` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration/device-identity.txt` | 413 | `3282c1a074be5000297c19787e2c1aeb141b78de2407068c7a915de1ffb34ada` |
| `fixture-sha256.txt` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration/fixture-sha256.txt` | 457 | `50bc57114bfafb4e4faf94e73b2a5b794ff30cf9e0566dc8017b50f250cd9ba6` |
| `host-application-analyze.log` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration/host-application-analyze.log` | 96 | `f9ad4e6766f75f120ed321e8b8d0a597d09fb84165a3cd55311d338ce84787ee` |
| `host-application-test.log` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration/host-application-test.log` | 26632 | `1d4b8a6414faa4fa85bef3457677ad38bb62f166d5a9ec561678a149473f4722` |
| `host-dart-format.log` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration/host-dart-format.log` | 48 | `84d03ff6064fb8f68a8e67469536b6ae4b66c2d355623bcaa81f15b6ca8fd176` |
| `host-flutter-analyze.log` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration/host-flutter-analyze.log` | 96 | `cb48cdedf3c6ad69a6c07f1cc8fb6f64adf73d590670dca5d3d0797a07137e00` |
| `host-flutter-pub-get.log` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration/host-flutter-pub-get.log` | 333 | `30c4a53996ef24e0570a7e2e73ef530280d7156226af11ec49732f428804603e` |
| `host-flutter-test.log` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration/host-flutter-test.log` | 54699 | `9f4c3f829a6f0c624939aaea410fc4a83c380c631da4f01034dc35bd9f271b0e` |
| `host-git-checks.log` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration/host-git-checks.log` | 1099 | `ea1c4b6e53eccf1f92973f318e28d15bfd26cd4e916583754c83df3c4593fa58` |
| `integration-android-us2.log` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration/integration-android-us2.log` | 9058 | `ad3ae9958006b7df9924e757e3870daac5195f22542b154b041cadc56979e659` |
| `logcat-flutter.log` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration/logcat-flutter.log` | 315 | `c6bcf59dd9ab02d044b4d561365923d3607204de1b81b96d07607e6fb6c24e85` |
| `logcat-us2-markers.log` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration/logcat-us2-markers.log` | 1215 | `0e66f5ed10416995b22942213953111754c654979ff37cf71b1f036120517f43` |
| `orca-emulator-session.json` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration/orca-emulator-session.json` | 479 | `5745e9fd0ac7d3bf5b0a1e49a845086efd7d40a3871af6e814b77207d76a0be0` |
| `picker-round1-downloads.xml` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration/picker-round1-downloads.xml` | 20125 | `7a08ab9e56af8a0f7697baa970b53f1bcc4bbf24e5baeebc1cdb3cf4e88bebd3` |
| `picker-sequence.txt` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration/picker-sequence.txt` | 200 | `836714b7c433638775109b2a10bf93c7005757d8b7650bbb9efda5ddda510a18` |
| `screenshots/after-review.png` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration/screenshots/after-review.png` | 210243 | `3505bbabd139e59a576c28c5f3a7971d4770f18cbcb931e1dfd1d3c7e67d4882` |
| `screenshots/editor-ready.png` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration/screenshots/editor-ready.png` | 42265 | `3f0064d13ec25f21488a872c056ef7acec69ca4f980e326de6eeb9ad2f1d1171` |
| `screenshots/suggestions-visible.png` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration/screenshots/suggestions-visible.png` | 229358 | `e968e04b32cb97c6661056658c717387393081cecaaf78054d270db099d121e2` |
| `spec-kit-invocation.txt` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-20-us2-integration/spec-kit-invocation.txt` | 3206 | `ea93246f23300d13f29147d77797b48002a87ee58d7993377a188a08de46d2bd` |

## 10. Reproducibility

1. Start from base `c1141470ad63c110ebe02277f0f98c70ee2cf26a` and check out
   implementation commit `5540d8a32aedfc6edb8003309429912e893c5397`
   (tree `80b1fbbb702ff86fc6e05f1d27ecdf33386ac310`). Confirm the pre-existing
   `gradlew.bat` modification is not committed.
2. Attach the exclusively allocated `T025_Pixel7_API35_KVM_20261115` AVD
   through Orca (`orca emulator attach ... --json`), confirm exactly one adb
   device, serial `emulator-5554`, `ro.build.version.sdk=35`, and
   `sys.boot_completed=1`.
3. From the repository root run `tools/android/us2_drive_journey.sh`. The
   driver verifies the Orca session, pushes the committed `sf-001.pdf` fixture
   to both device locations, starts the integration test, drives the real
   picker, captures the three handshake screenshots, collects the evidence,
   and removes the pushed fixture/staging/dumps.
4. Expected test output: exit `0`, `07:31 +1: All tests passed!`, markers
   through `US2_CLEANUP_DONE`. A rerun must use a fresh
   `US2_EVIDENCE_DIR`/`US2_RUN_DIR` or explicitly set
   `US2_REPLACE_EVIDENCE=1`; the driver refuses to overwrite a non-empty
   evidence directory silently.
5. Host-only reproduction: from `apps/feldexa_app` run
   `flutter pub get --offline`, `flutter analyze --no-pub`,
   `flutter test --no-pub`, and `dart format --output=none
   --set-exit-if-changed` on the changed Dart files; from
   `packages/feldexa_application` run `flutter analyze --no-pub` and
   `flutter test --no-pub`; from the repository root run `git diff --check`.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
