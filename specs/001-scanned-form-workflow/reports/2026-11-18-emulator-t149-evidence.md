# 2026-11-18 EMULATOR — T149 real system-picker US1 journey

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` |
| Result | `PASS` |
| Task / issue | `T149` / `#149` |
| Date / timezone | `2026-11-18 18:02 Europe/Berlin` |
| Revision | base commit `c09dbe59d4b8eeabd5ecdf5f1421c5853d3e0c69`; implementation commit `e6aa38f00334595216d3c951034cc5ba937b6f6b`, tree `06732125f2c290ccdb030c8f136572d43be3b567`; tree `dirty` because of the pre-existing, unstaged modification `apps/feldexa_app/android/gradlew.bat` SHA-256 `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62`, excluded from every commit; the report and index row are in a later docs-only commit whose SHA is recorded in the external attestation |
| External attestation | the active `worker_done` transport record for this dispatched worker (role label; raw task/dispatch identifiers withheld per `reports/README.md` §4.2); it records the base and implementation SHA/tree, checks/counts, report bytes/hash, and limitations. No attestation ref or bundle was created |
| Build identity | version `0.1.0+1`; mode `debug`; APK `apps/feldexa_app/build/app/outputs/flutter-apk/app-debug.apk`, 172337679 bytes, SHA-256 `370bec2f4e966580bf73847dab61220ac83ec6ce487c822d604ff79ce4e9e163`; built and installed by the exact `flutter test` command in §4; no release or release-signing claim |
| Toolchain | Flutter `3.47.7` stable (framework `abaf9c5237`), Dart `3.13.5`; JDK `25.0.3` (the Android Studio JBR selected by Flutter); Gradle `9.3.1`, AGP `9.1.0`, Kotlin `2.4.0`; Android SDK platform `36`, build-tools `36.0.0`; adb `1.0.41` (`37.0.1`); emulator `37.2.13.0`; pdfrx `2.12.0` (PDFium); PDFBox-Android `2.0.27.0` |
| Input | synthetic fixture catalogue `fixtures-1.0.0`: `sf-001` (2 pages, SHA-256 `22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038`) and `sf-protected` (RC4 40-bit, non-empty user password, SHA-256 `090290f77e77d904a11870951b06f0139c5abd1d263ad862b60a7b15ff69f221`); no real or personal document |

## 1. Scope

T149 is a Phase 13 convergence task with no dedicated GitHub issue; the schema-mandated `#149` label is the task-ID mapping label, not a live issue or PR claim.

This is a real Android-emulator acceptance run of US1 through the **real
`ACTION_OPEN_DOCUMENT` system picker**, the in-app import action, and the
editor route. It is the T149 answer to the T046 residual: T046 used a declared
debug-only picker seam and explicitly made no SAF-picker UI claim. T149 uses no
seam — no `de.feldexa/test.import`, no `ImportTestHooks`, no injected runtime,
and no fake renderer.

The exercised production path is:

- `app.main()` → German start surface from the committed ARB →
  `StartScreen` import action → `ImportFlow` → `AndroidImportClient` →
  `import.pickAndImport` → `MainActivity` `ActivityResultContracts.OpenDocument`
  → `DocumentsUI` → native `ImportService` streaming encrypted staging, real
  `PdfPreflight`, verified initial commit → terminal result →
  `AndroidStoreClient.loadDocument` read-back → `EditorScreen` →
  `PageView` (real pdfrx/PDFium) + `PageStrip` + `PageState`.

Acceptance covered:

- Round 1: `sf-001` (2 pages) through the real picker; editor route; both strip
  pages; the German `a11yPageNavigation` text; page-2 navigation; a mounted
  `PageView` reporting two pages; a genuinely rendered first page; exactly one
  new committed document; protected-store read-back with matching SHA-256 and
  page-1 PDFium render digest.
- Round 2: `sf-protected` through the real picker; the exact German `IMP-001`
  message and recovery; no editor route; no visible code, path, URI, or source
  name; no additional document.
- Cleanup: the created document is deleted through `AndroidStoreClient`, the
  store returns to its pre-run set, and every pushed fixture and device dump is
  removed.

Host-only checks are reported separately in §4 and are not runtime evidence.

### Spec Kit implementation provenance

- **Command:** `/speckit.implement Implement ONLY task T149 (Phase 13 convergence, US1): Add an EMULATOR US1 acceptance test ...` was invoked through the registered OpenCode `speckit-implement` skill before any code change; the scope argument limited execution to T149 and forbade editing `tasks.md` checkboxes. Model/provider: `deepseek/deepseek-flash` (DeepSeek V4.1 Flash 1017).
- **Prerequisite output/exit:** the first invocation without `SPECIFY_FEATURE_DIRECTORY` exited `1` with `ERROR: Feature directory not found. Set SPECIFY_FEATURE_DIRECTORY or run the specify command to create .specify/feature.json.` and `ERROR: Failed to resolve feature paths`; `.specify/feature.json` is absent in this worktree. The explicit invocation `SPECIFY_FEATURE_DIRECTORY=specs/001-scanned-form-workflow .specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` exited `0` with `FEATURE_DIR` pointing at the dispatched worktree's `specs/001-scanned-form-workflow` and `AVAILABLE_DOCS=[research.md, data-model.md, contracts/, quickstart.md, tasks.md]`.
- **Extension hooks:** `.specify/extensions.yml` exists with `hooks: {}`; no before/after hook was registered or executed.
- **Checklist gate (observed read-only, not modified):** `checklists/requirements.md` is 16/16 checked (`PASS`); `checklists/precision-testability.md` has 36 unchecked reviewer-owned markers (`FAIL` as a reviewer gate); `checklists/precision-testability-assessment.md` contains no checkbox items. The dispatch explicitly scoped T149, forbade checklist edits, and pre-authorized proceeding, so no checklist marker was changed and no reviewer approval is claimed.
- **Task marker:** `tasks.md` was not edited; the T149 checkbox remains reviewer/coordinator-owned.

## 2. Revision and build

The run started from base commit
`c09dbe59d4b8eeabd5ecdf5f1421c5853d3e0c69` and the implementation commit
`e6aa38f00334595216d3c951034cc5ba937b6f6b`
(tree `06732125f2c290ccdb030c8f136572d43be3b567`). The two delivered files are
the new integration test `apps/feldexa_app/integration_test/android_us1_journey_test.dart`
and the new test-only host driver `tools/android/t149_drive_picker.sh`. No
production file, ARB, generated localization, Kotlin file, Android resource,
Gradle file, dependency, `tasks.md`, checklist, spec, plan, or contract was
changed.

`flutter test integration_test/android_us1_journey_test.dart -d emulator-5554`
ran Gradle `assembleDebug`, built `app-debug.apk` from this tree, installed it,
and executed the single integration test. The APK is a git-ignored build output
bound by `apk-sha256.txt`; it is not committed. This `flutter test -d`
invocation produced no separate test APK; the two `app-debug.apk` output paths
are the same file.

### No declared production or test seam

T149 adds no debug channel, no injected adapter, and no production change. The
T046 `ImportTestHooks` and the `de.feldexa/test.import` channel remain in the
tree for the historical T046 test only; they were neither invoked nor armed in
this run. The test starts `app.main()` with its production default factories:
`createImportRuntime` (real `AndroidImportClient`/`AndroidStoreClient`) and
`openPdfrxPageRenderer` (real pdfrx/PDFium).

### Picker automation boundary

The Flutter widget tester cannot tap another app's window. The host driver
therefore performs the only non-Dart steps:

1. pushes the two synthetic fixtures to the device shared-storage Downloads
   directory and makes them visible to `DocumentsUI` with
   `am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file://...`
   for each file (the exact on-device paths and SHA-256 values are in
   `fixture-sha256.txt`, and both rows are visible in `picker-round1-roots.xml`);
2. pushes the same bytes to an app-readable device staging directory for the
   expected-hash and render-digest comparison;
3. sets the emulator to landscape and starts the integration test;
4. waits for `T149_PICKER_READY:1` / `T149_PICKER_READY:2` in the host test output, waits for
   `DocumentsUI` to be the resumed activity, dumps the accessibility tree with
   `uiautomator dump`, and taps the exact nodes with `input tap`;
5. restores the device settings and removes the pushed fixtures and dumps.

The test emits markers through `debugPrint`; `flutter test -d` streams them to
the host log, not to Android logcat. The driver therefore reads the host test
log first and falls back to `adb logcat`. The real `ACTION_OPEN_DOCUMENT`
launch and the picker close/resume transitions are independently recorded in
the sanitized logcat excerpts (§8). No result is inferred from a screenshot.

## 3. Environment

```text
EMULATOR: Pixel 7 API 35, exclusive allocation T149 2026-11-18
          AVD T025_Pixel7_API35_KVM_20261115
          serial emulator-5554; exactly one adb device attached before the run
          system image google/sdk_gphone64_x86_64/emu64xa (API 35, userdebug)
          fingerprint google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys
          guest model sdk_gphone64_x86_64; ro.build.version.sdk=35
          ro.build.version.release=15; ro.product.cpu.abi=x86_64
          ro.kernel.qemu=1; ro.boot.qemu.avd_name=T025_Pixel7_API35_KVM_20261115
          sys.boot_completed=1
          4 vCPU; RAM 4096 MB (MemTotal 4014392 kB)
          1080x2400 at density 420; landscape during the run (2400x1080)
          build mode debug
          APK apps/feldexa_app/build/app/outputs/flutter-apk/app-debug.apk
          APK SHA-256 370bec2f4e966580bf73847dab61220ac83ec6ce487c822d604ff79ce4e9e163
```

Device identity is recorded in `device-identity.txt`; the fixture hashes and
both device locations are recorded in `fixture-sha256.txt`. The AVD was already
booted and attached; this task did not start, wipe, reset, snapshot, or kill it.
KVM acceleration was not freshly probed from this sandbox; the guest reports
the expected QEMU/AVD properties and a completed boot. No physical-device,
silicon, or performance claim follows.

The host driver disabled accelerometer rotation and set `user_rotation` to `1`
for the run so the real logical width crosses the contract's 600 dp page-strip
boundary. The test asserts the effective logical width is at least 600 dp
(observed 2400 / 2.625 = 914.3 dp). Portrait would select the compact
indicator, which has no `page-strip-page-N` keys. This is real device UI, not
a simulated viewport. The driver restored the pre-run rotation settings after
the run.

## 4. Checks

### 4.1 EMULATOR runtime checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `tools/android/t149_drive_picker.sh` (repository root; stages fixtures, starts the integration test, drives `DocumentsUI`, captures evidence, cleans up) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t149-2026-11-18/integration-android-us1.log` | `PASS` |
| 2 | `flutter test integration_test/android_us1_journey_test.dart -d emulator-5554` (`apps/feldexa_app`; invoked by check 1 with Flutter and platform-tools on `PATH`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t149-2026-11-18/integration-android-us1.log` | `PASS` |
| 3 | `adb devices -l`; `adb -s emulator-5554 shell getprop`; `adb -s emulator-5554 shell wm size`; `adb -s emulator-5554 shell wm density` (repository root) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t149-2026-11-18/device-identity.txt` | `PASS` |
| 4 | `adb -s emulator-5554 shell uiautomator dump`; `adb -s emulator-5554 pull`; `adb -s emulator-5554 shell input tap` / `input swipe` (inside check 1) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t149-2026-11-18/picker-sequence.txt` | `PASS` |

The run log shows `00:31 +1: All tests passed!`; teardown began at `00:29`. The nine markers are, in order:

```text
T149_PICKER_READY:1
T149_ROUND1_EDITOR
T149_ROUND1_OK
T149_PICKER_READY:2
T149_ROUND2_REJECTED
T149_STORE_COUNTS:before=0,after=1
T149_RENDER_DIGEST:008f1e501fbdf9df9f5f7f1cee20cd69d123209280ae3d26858e20baf9f37a4b
T149_STORE_VERIFIED
T149_CLEANUP_DONE
```

(The `ROUND1_OK` and `PICKER_READY:2` markers are consecutive phases; the list
above is the observed order.)

The picker sequence, copied from `picker-sequence.txt`, was:

```text
round 1 attempt 1 tab roots at 209,137
round 1 attempt 2 tab downloads at 577,588
round 1 attempt 3 tab file at 405,850
round 2 attempt 1 tab file at 836,850
```

Round 1 tapped `Show roots`, then the `Downloads` root, then the
`t149-sf-001.pdf` row (`item_root` bounds `[200,621][610,1080]`, center
`405,850`) in `Downloads`. Round 2 reopened `DocumentsUI` in `Downloads`
(the picker remembered the last folder), so the driver tapped the
`t149-sf-protected.pdf` row directly (`item_root` bounds
`[632,621][1041,1080]`, center `836,850`). The dumps are committed; a reviewer
can replay the same taps against this exact system image.

`adb logcat` independently shows both `OPEN_DOCUMENT` launches and both
`CLOSE`/`TO_FRONT` transitions back to `de.feldexa.app`:

```text
17:58:40.878 ActivityTaskManager: START u0 {act=android.intent.action.OPEN_DOCUMENT ... cmp=com.google.android.documentsui/com.android.documentsui.picker.PickActivity ...}
17:58:54.990 WindowManagerShell: ... {id=73 t=CLOSE ... PickActivity ... {null m=TO_FRONT ... component=de.feldexa.app/.MainActivity}}
17:58:59.636 ActivityTaskManager: START u0 {act=android.intent.action.OPEN_DOCUMENT ... PickActivity ...}
17:59:04.873 WindowManagerShell: ... {id=75 t=CLOSE ... PickActivity ... {null m=TO_FRONT ... component=de.feldexa.app/.MainActivity}}
```

### 4.2 Host-only checks (`NONE` class; not runtime evidence)

These checks are deliberately separate from §4.1. They do not prove Android
behaviour and are not aggregated with the `EMULATOR` result.

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `flutter analyze --no-pub` (`apps/feldexa_app`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t149-2026-11-18/host-flutter-analyze.log` | `PASS` |
| 2 | `flutter test --no-pub` (`apps/feldexa_app`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t149-2026-11-18/host-flutter-test.log` | `PASS` |
| 3 | `dart format --output=none --set-exit-if-changed integration_test/android_us1_journey_test.dart` (`apps/feldexa_app`) | `0` | console only (not retained); `Formatted 1 file (0 changed)` | `PASS` |
| 4 | `dart tools/evaluation/validate_report.dart specs/001-scanned-form-workflow/reports/2026-11-18-emulator-t149-evidence.md` (repository root) | `0` | console only (not retained); `PASS … 1/1 report(s) valid` | `PASS` |
| 5 | `git diff --check` (repository root, final tree) | `0` | console only (not retained) | `PASS` |

`flutter analyze` reported `No issues found!`. The full host run ended with
`00:15 +264: All tests passed!` and no failure line: 264 tests, 0 failures.
Those 264 tests are the 17 VM suites among the 20 test files at this base; the
other three files are browser-only (`platform_registry_web_test.dart`,
`web_fixtures_browser_test.dart`, `web_import_browser_entry_test.dart`). The
captured progress text is lossy — the runner rewrites progress lines and omits
`android_backup_rules_test.dart`'s three tests from the text while the final
counter remains 264 — so a file-name count in that log is not a suite count.

### 4.3 Conditional checks not run

The following were not run and are **not** presented as passes:

- `DEVICE` runtime on a physical Samsung Galaxy A54 5G or owner-approved
  equivalent: `ABSENT`; no physical device was allocated, so there is no device
  acceptance or SC-004 performance claim.
- Performance measurement: `ABSENT`; T149 is a correctness journey, and the
  test duration is not a performance result.
- TalkBack traversal, text-scale, and contrast review: `ABSENT`; the German
  labels are asserted in the semantics tree, not announced through TalkBack.
- Release build/APK run: `ABSENT`; only the debug APK from the `flutter test`
  build was installed.
- T046 debug picker seam: `NOT USED`; the real picker was driven and the seam
  was neither armed nor invoked.

## 5. Results

| Scenario | Input / action | Observed | Verdict |
| --- | --- | --- | --- |
| Round 1 accepted import through the real system picker | In-app `PDF importieren` action; `DocumentsUI` → `Downloads` → `t149-sf-001.pdf` | Picker opened as `ACTION_OPEN_DOCUMENT`; the selection returned to the app; the editor route appeared; `EditorScreen.source.pageCount == 2`; no page failures (therefore no `IMP-006` warning); both `page-strip-page-1` and `page-strip-page-2` are present | `PASS` |
| German navigation text and page strip | Full strip in landscape (914.3 dp) | Page 1 semantics label `Seite 1 von 2`, page 2 label `Seite 2 von 2`, both from `AppLocalizations.a11yPageNavigation`; page 1 selected, page 2 not selected | `PASS` |
| Page navigation | Tap the page-2 strip control | Page 2 selected; page 1 no longer selected; `PageViewController.mappingFor(1).pageRectInViewport.top` is 0 (±1 logical pixel) and page 1 is above the viewport | `PASS` |
| Viewer composition and real render | Mounted `PageView` | Controller reports 2 pages; a `RawImage` with a non-null `ui.Image` exists inside the page-1 slot after the production pdfrx renderer completes | `PASS` |
| Round 2 rejected import through the real system picker | In-app action; `DocumentsUI` reopened in `Downloads` → `t149-sf-protected.pdf` | Start surface remains; no editor route; `import-failure` is present; exact `AppLocalizations.imp001` and `imp001Recovery` text; no `IMP-`, `content://`, `file://`, `.pdf`, or `sf-protected` text in any `Text` widget | `PASS` |
| Commit count | `AndroidStoreClient.list(StoreKind.document)` before and after both rounds | `T149_STORE_COUNTS:before=0,after=1`; exactly one new id; no baseline id disappeared | `PASS` |
| Protected-store read-back | `loadDocument` for the new document after both rounds | 2 pages; `sha256(sourceBytes)` equals the pushed `sf-001` SHA-256; `sourceBytes` byte-equal the pushed fixture | `PASS` |
| Page-1 pixel fidelity | PDFium raster of pushed bytes vs decrypted protected copy at the page display size | Digests equal; `T149_RENDER_DIGEST:008f1e501fbdf9df9f5f7f1cee20cd69d123209280ae3d26858e20baf9f37a4b` | `PASS` |
| Cleanup | `AndroidStoreClient.delete` for the created document; host fixture removal | Store set returns exactly to the pre-run set; the driver removes both pushed fixtures, the staging directory, and every device dump; rotation is restored; no document remains | `PASS` |

**What the render comparison proves.** The protected copy is byte-identical to
the pushed fixture, and PDFium renders page 1 from both byte strings to the
same 64-hex digest at the page's display size (72 DPI). This is a renderer
equality check, not a screenshot or UI-golden comparison. The fixtures are
synthetic vector PDFs; no scanner-pixel or visual-fidelity claim is made.

**No seam substitution.** The acceptance path contains no
`de.feldexa/test.import`, no `ImportTestHooks`, no simulated adapter, and no
injected page renderer. The only host involvement is navigation of the real
`DocumentsUI` window and fixture delivery, both recorded in §4.1 and the
committed dumps.

## 6. Performance

No performance claim.

## 7. Limitations

- **Picker automation is image- and locale-dependent.** The host driver finds
  nodes by exact text (`Downloads`, fixture file names) and taps bounds from
  `uiautomator dump`. Coordinates and drawer labels can change with a different
  `DocumentsUI` version, system language, display size, or theme. The committed
  dumps and `picker-sequence.txt` make this run replayable on the same image,
  but they are not a cross-version UI contract. The device locale was English
  (`persist.sys.locale` empty); the app itself is German.
- **Landscape is imposed for the strip assertion.** The host sets
  `user_rotation=1` so the real 914.3 dp width selects the full strip with
  `page-strip-page-N` keys. Portrait would use the compact indicator with
  different keys. The app's own orientation behavior is unchanged and was not
  tested here.
- **German navigation text is a semantic label.** In the full strip, the
  visible control shows the page number and analysis state; `Seite 1 von 2` /
  `Seite 2 von 2` is the `Semantics.label` from `a11yPageNavigation`. The test
  asserts that label and the selected state, not a separate visible sentence.
  No TalkBack announcement, focus order, contrast, or 200 % text-scale claim.
- **No `DEVICE` or performance claim.** This is an emulator run on
  `emulator-5554`, debug build, KVM not freshly probed from the host sandbox.
  It cannot prove physical-device performance, silicon-backed key strength, or
  device acceptance.
- **No pixel-level UI fidelity claim.** The only pixel comparison is the
  PDFium page-1 raster equality described in §5. No screenshot or golden-image
  comparison exists.
- **Store scope.** The count is the `StoreKind.document` list before and after
  the journey. `flutter test` uninstalls the app after the run, so the installed
  store does not persist beyond the test; the in-test delete and the exact
  return to the pre-run set are the cleanup evidence. No other `StoreKind` is
  claimed.
- **T148 follow-up observation.** The T148 note about two
  `AndroidOperationClient` instances did not affect this run. In production
  `createImportRuntime` shares one operation client between import and store
  read-back; the test creates its own client only for the pre-run baseline and
  again after both rounds, after which no app import remains. No hang, lost
  result, or production change was observed.
- **Evidence is author-produced.** Independent review of this exact candidate
  is outside T149 and is not claimed.
- **Log sanitization.** Committed text artifacts have host path prefixes
  replaced with placeholders, the ephemeral VM-service token redacted, and
  trailing whitespace removed; no result, marker, count, tap, device identity,
  or logcat transition line was changed.

## 8. Artifacts

All paths are repository-relative and committed with this report. The APK is a
git-ignored local build output bound by `apk-sha256.txt`; it is not committed.

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `apk-sha256.txt` | `specs/001-scanned-form-workflow/reports/artifacts/t149-2026-11-18/apk-sha256.txt` | 138 | `81e270e772c8c9639586cf6625090ed46eb23ada774d5515ec483fd061c345e3` |
| `device-identity.txt` | `specs/001-scanned-form-workflow/reports/artifacts/t149-2026-11-18/device-identity.txt` | 349 | `ad61e0db0a95c665b1f6e564acbe2b84157e2fa9a11f983fe568947c8f66f04d` |
| `fixture-sha256.txt` | `specs/001-scanned-form-workflow/reports/artifacts/t149-2026-11-18/fixture-sha256.txt` | 614 | `9683d107e9d7d317f7d8b8baeab859c0b90721043d580081467406f1ed609795` |
| `host-flutter-analyze.log` | `specs/001-scanned-form-workflow/reports/artifacts/t149-2026-11-18/host-flutter-analyze.log` | 57 | `838765bc5857efee778e3cbcc75b29cbcf1698f516fccd177876c32120d5b287` |
| `host-flutter-test.log` | `specs/001-scanned-form-workflow/reports/artifacts/t149-2026-11-18/host-flutter-test.log` | 40103 | `cfef1692d7097eb9772caa6bd360b67ebc4277a0518c8c60a466429583133fd2` |
| `integration-android-us1.log` | `specs/001-scanned-form-workflow/reports/artifacts/t149-2026-11-18/integration-android-us1.log` | 3032 | `2bb338919a5f6ed929be304698311629f8fc8bfd3f289507b1f21b0b3fde56bf` |
| `logcat-flutter.log` | `specs/001-scanned-form-workflow/reports/artifacts/t149-2026-11-18/logcat-flutter.log` | 310 | `b98ebc960fb6b8db3f09fb0373d15a8ece0196211c6171adc3e8a4e6efb16534` |
| `logcat-picker-markers.log` | `specs/001-scanned-form-workflow/reports/artifacts/t149-2026-11-18/logcat-picker-markers.log` | 1783 | `ace5fa302ff14f1dce610974704d79078ec8d2032bdc9b070c8473f2f7996f2f` |
| `logcat-picker-transitions.log` | `specs/001-scanned-form-workflow/reports/artifacts/t149-2026-11-18/logcat-picker-transitions.log` | 6694 | `4b89d50e5e05a847bda17e1128d3032f3489a3856f22c1fff010025b98b3373c` |
| `picker-round1-roots.xml` | `specs/001-scanned-form-workflow/reports/artifacts/t149-2026-11-18/picker-round1-roots.xml` | 23377 | `49c06e4f65fa9da87eb3d6ce782b920ba81ebf2bc1e351f3d94987287820b2d7` |
| `picker-round1-drawer.xml` | `specs/001-scanned-form-workflow/reports/artifacts/t149-2026-11-18/picker-round1-drawer.xml` | 32918 | `8a74862af5047f66ed4876f835c0fec56c31d5b1530851cf4cb9636097a38349` |
| `picker-round1-downloads.xml` | `specs/001-scanned-form-workflow/reports/artifacts/t149-2026-11-18/picker-round1-downloads.xml` | 24624 | `edee402391aa312120a78709ae6f207ae88235060d0c6a41370bcae6c28784cc` |
| `picker-round2-downloads.xml` | `specs/001-scanned-form-workflow/reports/artifacts/t149-2026-11-18/picker-round2-downloads.xml` | 24624 | `edee402391aa312120a78709ae6f207ae88235060d0c6a41370bcae6c28784cc` |
| `picker-sequence.txt` | `specs/001-scanned-form-workflow/reports/artifacts/t149-2026-11-18/picker-sequence.txt` | 158 | `77b29cafe987b101fbc4f8d9d1fa0f997d8d8e162d1b22cf16b1f2d8227b784c` |

The `logcat-picker-transitions.log` excerpt was extracted from the still-live
device logcat buffer immediately after the run; its lines are unmodified except
trailing-space removal. The two `picker-round*-downloads.xml` files are byte-identical because
`DocumentsUI` reopened the same `Downloads` view; round 2 targeted the other
row in the same dump. The dumps contain synthetic file names, node bounds, resource
identifiers, and system UI labels; no document content.

## 9. Reproducibility

1. Start from base commit `c09dbe59d4b8eeabd5ecdf5f1421c5853d3e0c69` and check
   out implementation commit `e6aa38f00334595216d3c951034cc5ba937b6f6b`;
   confirm tree `06732125f2c290ccdb030c8f136572d43be3b567`. The pre-existing
   `apps/feldexa_app/android/gradlew.bat` modification is unrelated to this
   task and must not be committed with it.
2. Use the pre-booted, exclusively allocated `T025_Pixel7_API35_KVM_20261115`
   AVD on serial `emulator-5554`; do not boot, wipe, reset, snapshot, or kill
   it. Confirm exactly one adb device and `sys.boot_completed=1`.
3. From the repository root, with Flutter `3.47.7` and Android platform-tools
   on `PATH`, run `tools/android/t149_drive_picker.sh`. The driver resolves the
   worktree, app, APK, a fresh `mktemp` run directory, and serial; it writes
   pulled dumps, intermediates, logs, and the working sequence there, pushes
   the two committed synthetic fixtures to the device Downloads and staging
   directories, verifies both SHA-256 values, sets landscape, clears the
   logcat buffer, and starts the test. A rerun must not overwrite report-bound
   artifacts: the driver writes to a fresh `mktemp` run directory by default
   and only replaces an explicitly bound `T149_EVIDENCE_DIR` after a full
   backup with `T149_REPLACE_EVIDENCE=1`.
4. Wait for `T149_PICKER_READY:1`; after `DocumentsUI` is resumed, the driver
   taps `Show roots` at `209,137`, `Downloads` at `577,588`, and the
   `t149-sf-001.pdf` row at `405,850`. After `T149_PICKER_READY:2`, it taps the
   `t149-sf-protected.pdf` row at `836,850` (the picker is already in
   `Downloads`). The expected test output is `00:31 +1: All tests passed!`,
   exit `0`, with markers through `T149_CLEANUP_DONE`.
5. The test asserts the editor route, strip keys, German labels, navigation,
   mounted viewer, rendered page, exact rejection text, store counts 0 → 1,
   read-back SHA-256, page-1 render digest, and deletion. Its final cleanup
   returns the `document` set to the pre-run set; the driver removes the pushed
   fixtures, staging directory, device dumps, and temporary host dumps, and
   restores rotation.
6. Host-only reproduction: from `apps/feldexa_app` run
   `flutter analyze --no-pub`, `flutter test --no-pub`, and
   `dart format --output=none --set-exit-if-changed integration_test/android_us1_journey_test.dart`;
   from the repository root run
   `dart tools/evaluation/validate_report.dart specs/001-scanned-form-workflow/reports/2026-11-18-emulator-t149-evidence.md`
   and `git diff --check`.

## 10. External attestation

The active `worker_done` transport record (role label; raw task/dispatch
identifiers withheld) names the base and implementation SHA/tree, the report's
byte size and SHA-256, the checks and counts above, and the limitations. No
attestation ref or bundle was created for this task. The report itself is not
part of the implementation commit and does not assert its own commit SHA.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
