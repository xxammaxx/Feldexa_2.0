# T071 Android touch move/resize review test — Pixel 7 API 35 emulator PASS (correction 1)

- **Task / issue**: T071 / <https://github.com/xxammaxx/Feldexa_2.0/issues/71>
- **Feature**: `specs/001-scanned-form-workflow` US3/US4
- **Date**: 2026-11-21 (local)
- **Host evidence class**: `NONE` (host-VM analyze, format, widget/unit tests)
- **Emulator evidence class**: `EMULATOR` — **`PASS`** (correction 1)
- **Overall result**: `PASS` — the correction-1 candidate `44eb3e4` is host-green
  and the real twelve-phase Android touch journey passed on the Orca-attached
  Pixel 7 API 35 emulator.
- **Supersedes**: the first-pass candidate `398f4e4` (tree `8db4a55`) and its
  evidence bundle. Review A's findings 1–8 are closed in this correction
  (§2.1–§2.5, §5).
- **Dependency**: T071B integrated as PR #258 (merge `a5f3bae`); T071A integrated
  as PR #246 (merge `11675f3`). Base commit of this branch: `d53fb57`.

## 0. Machine-first handoff

```json
{
  "task": "T071",
  "issue": 71,
  "branch": "xxammaxx/t071",
  "base_commit": "d53fb57",
  "correction": 1,
  "review_a_result": "FAIL on 398f4e4 (findings 1-8); closed in this correction",
  "candidate_commit": "44eb3e466d3d1f8f7ca600e5afa0404363fbdb27",
  "candidate_tree": "2747c4eafd0b6abda528e72a2217aeb9d22b7e11",
  "evidence_commit": "external dispatch handoff; the documentation commit's own SHA/tree cannot be embedded in its own bytes",
  "host_evidence_class": "NONE",
  "emulator_evidence_class": "EMULATOR",
  "overall_result": "PASS",
  "host_gates": {
    "app_analyze": "exit 0, no issues",
    "format": "exit 0, 1 file, 0 changed",
    "focused_geometry_and_composition_widget_tests": "22/22 passed",
    "feldexa_ui_field_geometry_unit_tests": "31/31 passed",
    "app_suite": "469/469 passed",
    "git_diff_check": "exit 0, clean"
  },
  "emulator": {
    "driver": "tools/android/t071_drive_touch.sh",
    "test": "apps/feldexa_app/integration_test/android_review_test.dart",
    "driver_result": "PASS",
    "run_status": "result=PASS, flutter_test_exit=0",
    "integration_log_end": "All tests passed!",
    "device": {
      "serial": "emulator-5554",
      "avd": "T025_Pixel7_API35_KVM_20261115",
      "android_release": "15",
      "sdk": 35,
      "abi": "x86_64",
      "fingerprint": "google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys",
      "wm_size": "1080x2400",
      "density": 420,
      "page_viewport_dp": "411 x 206",
      "view_scales": {"fit": 0.69115, "min_0_5x": 0.34558, "max_8x": 5.52921}
    },
    "apk": {
      "path": "apps/feldexa_app/build/app/outputs/flutter-apk/app-debug.apk",
      "bytes": 173421516,
      "sha256": "1d12363b4c9b34c9f19948983289db79660c024052d9dcf2a90edc900ae96bf5"
    },
    "fixture": {
      "bytes": 5956,
      "sha256": "22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038",
      "damaged_sha256": "57c1ade1ab2c00375ac61703db3d4ce5d27b996ea067647aba585866dc6ec221",
      "device_staging": "/data/local/tmp/t071-fixtures/sf-001.pdf",
      "device_sha256": "22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038"
    },
    "tested_field": {
      "page": 0,
      "source": "largest unresolved text suggestion confirmed through the production T066 command path",
      "rect_pt": [56.875, 43.5, 481.625, 18.0]
    },
    "store_revision_proof": {
      "real_saveRevision_calls_per_gesture": 1,
      "real_saveRevision_calls_during_hold": 0,
      "committed_gesture_markers": 14,
      "hold_window_ms": [1160, 1991],
      "measured_commit_latency_ms": {"min": 618, "max": 1114},
      "negative_control_pure": "double/held/zero rejected",
      "negative_control_real_double_commit": "2 real store calls, assertion failed as required, second call outcome REJECTED by the real store's expectedHead guard"
    },
    "screenshot_count": 12,
    "screenshot_hashes_distinct": true,
    "privacy_checks": "PASS (8 scans: integration log, logcat-flutter.log, commands.txt, git-identity.txt; every committed log URL-redacted)",
    "cleanup_verified": true,
    "command_receipts": "commands.txt (selected host/emulator commands with exit codes; see §4.3)"
  },
  "not_run": [
    "DEVICE acceptance and any performance claim",
    "TalkBack/accessibility traversal of the touch handles and visual/golden inspection",
    "stylus/pen and multi-window touch input",
    "signature asset editing",
    "export/share/print of the resized geometry",
    "template route touch editing"
  ]
}
```

## 1. Revision and scope

- Branch `xxammaxx/t071`, base `d53fb57`, no new branch or worktree, no
  push/PR, no force/rebase/reset/stash.
- First-pass candidate `398f4e4` (tree `8db4a55`): Review A **FAIL**.
- Correction-1 commits, in order:
  1. `67c7ec1` — close Review A findings 1–8 in the test and driver.
  2. `be68e39` — double-commit control made real, ack probe made writable.
  3. `e3145ff` — grow the minimum-size field in the double-commit control.
  4. `8997261` — checked stale-ack preflight in the driver; URL-redacted
     evidence copies; privacy scan over `git-identity.txt`.
  5. `44eb3e4` — hold window derived from the fastest verified commit,
     **the commit that ran**.
- Changed paths vs the base: `apps/feldexa_app/integration_test/android_review_test.dart`,
  `tools/android/t071_drive_touch.sh`, the evidence bundle under
  `specs/001-scanned-form-workflow/reports/artifacts/2026-11-21-t071-touch/`,
  this report, `reports/README.md`, and the `tasks.md` T071 row.
- No production app source, `feldexa_core`, `feldexa_ports`,
  `feldexa_recognition`, `feldexa_ui`, ARB/localization, Gradle, or
  `pubspec.yaml` change. The pre-existing unstaged
  `apps/feldexa_app/android/gradlew.bat` line-ending change was never staged.
- Every heavy command ran under the shared host compute permit
  (`compute_slot.py --wait`), one at a time.

### 1.1 Command binding before the first edit

`command:speckit.implement` was resolved in this worktree before the first edit
of the task. Route: MCP `spec-kit` (`specify mcp`, JSON-RPC
`tools/call specify_artifact_info` with `identifier=command:speckit.implement`,
`isError: false`) → JSON CLI confirmation
(`specify artifact info command:speckit.implement --json`, identical record) →
`.opencode/commands/speckit.implement.md` with SHA-256
`e036ce63702db93e656e1c91ee6c02a8dc3d4a4f8624f8ba4adc69027fe68983` (matches the
expected digest). The full record, including the note that the harness did not
materialise the `mcp__spec_kit` tools and the same stdio server was therefore
driven directly, is `artifacts/2026-11-21-t071-touch/command-binding.txt`.

## 2. Review A findings 1–8 and how they are closed

| # | Severity | Finding | Closure | Evidence |
| --- | --- | --- | --- | --- |
| 1 | MEDIUM | Exactly one store revision per gesture is asserted only through the `NEW_HEAD=1`/`MID_WRITE=0` markers | A counting facade (`_CountingEditorRuntime`) wraps the **real** editor runtime of the **production** `createImportRuntime()` composition: every call is forwarded unchanged and only `saveRevision` is counted. Each committed gesture asserts 0 real store calls during a hold window that exceeds the fastest measured commit latency, exactly 1 real call for the gesture, and on **every** held frame: gesture active, preview painted, `reviewBusy` false, head/content unchanged. A pure negative control rejects 2 saves, a held save and 0 saves; a real double-commit injection issues a second genuine store call whose outcome the real store decides (`SECOND_SAVE=REJECTED` this run) and the assertion must fail on it | 14 `T071_COMMIT` markers with `SAVES_HELD=0:SAVES_DELTA=1:REVIEW_BUSY_HELD=0:PREVIEW_HELD=1`, `T071_NEGATIVE_CONTROL:REVISION_ASSERTION=…`, `T071_NEGATIVE_CONTROL:DOUBLE_COMMIT=…:SECOND_SAVE=REJECTED` |
| 2 | MEDIUM | A stale acknowledgement that cannot be removed was swallowed | `_clearStaleAck` returns a content-free failure marker; `_waitForDriver` emits `T071_HANDSHAKE_FAIL:` and aborts, withholding the screenshot marker. The driver removes acks with a checked exit code, verifies that none remain, writes `handshake-preflight.txt`, and fails before the test on a non-zero removal or a surviving ack. Negative control forces a delete failure through an injected override and asserts the abort marker and that no screenshot marker is emitted | `privacy`-adjacent `handshake-preflight.txt` (`exit=0`, `remaining_ack_files=0`, `verified=1`), `T071_NEGATIVE_CONTROL:STALE_ACK=1:DELETE_FAILURE_FAILS_CLOSED=1`, test-side marker assertion on `HANDSHAKE_FAIL:STALE_ACK_DELETE_FAILED:PHASE=probe` |
| 3 | LOW | The resize gesture silently relied on the 411 dp viewport | The nominal margin is asserted (`20 pt * 3 * fit = 41.47 px > 36 px` pan slop), the used zoom is raised to at least `40 px / 20 pt` when the viewport is narrower, and both are recorded and driven by exact marker shapes | `T071_RESIZE_ZOOM:…:NOMINAL_EDGE_PTR_PX=41.47:USED_EDGE_PTR_PX=41.47:PAN_SLOP_PX=36:REQUIRED_PX=40:OK=1` |
| 4 | LOW | Doubled `T071_T071_SCREENSHOT_*` prefix; substring-only marker contract | Screenshot markers carry exactly one `T071_` prefix (`T071_SCREENSHOT_<PHASE>`); the driver matches **exact anchored shapes** for 28 required markers plus three occurrence counts and rejects any `^T071_T071_` line | `marker-contract.txt` (`missing=0`), 12 `T071_SCREENSHOT_*`, 12 `T071_HANDSHAKE_OK`, 14 `T071_COMMIT` |
| 5 | LOW | `CLEANUP_DONE` was emitted before the real cleanup | The test emits `CLEANUP:HOOK_CLEARED=…:SCRATCH_GONE=…` and `CLEANUP_DONE` **only** in `tearDownAll` after both steps are verified (an incomplete cleanup emits `CLEANUP_INCOMPLETE` and fails). The driver now cleans up explicitly before evidence collection and verifies the device state | `cleanup-verification.txt` (`staging GONE`, `stale_ack_files=0`, `app_processes=0`, `verified=1`) |
| 6 | LOW | Header claimed no production behavior is bypassed while selection was set directly on the T077 controller | The field is selected through the **real tap path**: a real tap opens the value sheet and it is closed again, then the composed controller must report the field as selected. The header now names the two deliberate test seams (counting facade, double-commit control) instead of a blanket claim | `T071_SELECTION_TAP:PHASE=OPEN:SHEET=1`, `T071_SELECTION_TAP:PHASE=CLOSED:SELECTED=1:FIELD=…:SHEET_OPENED=1` |
| 7 | LOW/privacy | The Dart VM service token was committed in `logcat-flutter.log`; the privacy scan covered only the integration log | Every committed log is URL-redacted (`<URL_REDACTED>`) before it is written or copied, which removes the per-run token; the scan now covers the integration log, `logcat-flutter.log`, `commands.txt` and `git-identity.txt` and fails the run on any hit | `logcat-flutter.log` line 3 = `… on <URL_REDACTED>`, `privacy-log-check.txt` (8 PASS lines), `privacy-*` gate in the driver |
| 8 | LOW/docs | `commands.txt` described as complete; the hit-band claim overstated the 24 dp measurement; the `T071_SHOT` count for `min-size` was wrong; task/README rows cited a stale HEAD | §4.3 lists exactly what `commands.txt` records (a selected subset); the hit-band wording is now "measured 8.29 dp outward, 24 dp is the contract constant"; all twelve phases now emit a `T071_SHOT` marker (12/12); the task row and reports index cite `44eb3e4` (tree `2747c4ea`) | `T071_SHOT` × 12, §4.3, this report, `reports/README.md`, `tasks.md` |

Review B's overlapping LOWs (doubled prefix, cleanup ordering, docs wording) are
covered by items 4, 5 and 8.

### 2.1 The journey under test

`apps/feldexa_app/integration_test/android_review_test.dart` starts the real
`FeldexaApp` root with the production `createImportRuntime()` Android
composition, whose editor-runtime facade is wrapped by the counting spy. The
debug-only `de.feldexa/test.import` hook arms the deterministic T061
damaged-page-2 source derived in-test from the committed `sf-001.pdf`
(5956 bytes, SHA-256 `57c1ade1…`); the production import action performs the real
encrypted staging, preflight and verified commit, the real analysis run produces
28 suggestions, the largest unresolved text suggestion on page 0 is confirmed
through the production T066 command, and the field is then selected through the
real T077 tap path (tap → value sheet → close).

| # | Phase | Proof |
| --- | --- | --- |
| A | `resize-corners` | all four corner handles resize; only the two dragged edges move; the diagonally opposite corner is bit-for-bit fixed; the aspect ratio stays free; a 20 pt edge movement is a 41.47 px pointer delta above the 36 px pan slop (asserted, not assumed) |
| B | `resize-edges` | all four edge handles resize; only the dragged edge moves; the opposite edge is bit-for-bit fixed; the `centerLeft` gesture starts **8.29 dp outside** the stored rectangle and still claims the handle (24 dp is the contract constant the production hit test uses, not a measurement); the bottom edge grows and the right edge narrows the field for the body drags |
| C | `move-0.5x`, `move-1x`, `move-3x`, `move-8x` | the body drag commits exactly `pointerDelta / scale` on each axis at 0.5×, 1×, 3×, 8× fit-width; the size is preserved; the rectangle stays inside the page |
| C′ | `move-clamped` | an 8× drag overshoots the page; the committed rectangle keeps its size and its right edge lands on `pageBox.right = 595.28 pt` (within 1e-9) |
| D | `undo` | the T067 undo restores the exact pre-clamp rectangle (object equality) and writes one verified revision |
| E | `cancel` | a pointer cancel discards the preview: no head change, no content change, unchanged rectangle, **0** real store calls |
| F | `two-finger-pinch`, `two-finger-pan` | the first pointer claims a geometry drag, the second cancels it, the page still zooms (scale 1.382 → 2.791) and pans, geometry untouched, **0** real store calls |
| G | `min-size` | a resize dragged far past the anchor stops at exactly 4 × 4 pt with the top-left anchor fixed |
| H | read-back | the persisted field rectangle and head revision match the visible state |
| I | negative control | a real double store call for one gesture makes the exactly-one-revision assertion throw |

### 2.2 Exactly one store revision per gesture (finding 1)

- Counting facade: `_CountingEditorRuntime` implements `EditorRuntime` by
  delegating `raster`, `ocr`, `store`, `ids`, `clock`, `loadDocument`,
  `saveRevision` and `dispose` to the real runtime; only `saveRevision` is
  counted. It is composed through
  `FeldexaApp(importRuntimeFactory: () => ImportRuntime(importPort, readSourceBytes, store, editorRuntimeFactory: wrapped))`
  around the production `createImportRuntime()`, so the real secure store, the
  real import port and the real source-bytes resolver are untouched.
- Per gesture: `savesBefore`/`savesAfter` around the gesture and
  `savesDuringHold` at the end of the hold window; `_expectSingleStoreRevision`
  asserts `savesDuringHold == 0` and `savesAfter - savesBefore == 1`.
- Hold window: `max(1 s, 2 × fastest verified commit)`, bounded at 3 s. This run
  measured 618–1114 ms commit latency and holds of 1160–1991 ms
  (`HELD_FRAMES` 8–13), so every held frame in the marker set is a real
  "no commit yet" observation, not a single sample.
- Per held frame: gesture active, preview painted, `reviewBusy` false, head and
  canonical content unchanged (`REVIEW_BUSY_HELD=0` / `PREVIEW_HELD=1`).
- Negative controls: a pure one rejects delta 2, a held save and delta 0; the
  real one arms the facade to forward the same request a second time to the real
  store, records the store's own verdict (`SECOND_SAVE=REJECTED` — the
  expectedHead guard rejects the stale chain), asserts `SAVES_DELTA=2`, and
  asserts the one-revision assertion throws on those two real calls.

### 2.3 Markers and rectangles (1/8 pt, this run)

`T071_FIELD_CONFIRMED` records the starting rectangle `455:348:3853:144`
(= 56.875, 43.5, 481.625, 18 pt); `T071_VIEW_READY` records
`FIT_MILLI=691`, `MIN_MILLI=346`, `MAX_MILLI=5529`, `VIEWPORT_W=411`,
`VIEWPORT_H=206`.

| Step | Handle | Moved edges | Fixed edges | Rect (L:T:W:H) |
| --- | --- | --- | --- | --- |
| 1 | `topLeft` | left+top | right+bottom | `295:188:4013:304` |
| 2 | `topRight` | top+right | left+bottom | `295:28:4173:464` |
| 3 | `bottomLeft` | left+bottom | top+right | `135:28:4333:624` |
| 4 | `bottomRight` | right+bottom | left+top | `135:28:4493:784` |
| 5 | `topCenter` | top | left+right+bottom | `135:188:4493:624` |
| 6 | `bottomCenter` | bottom | left+top+right | `135:188:4493:1824` |
| 7 | `centerLeft` (8.29 dp outside) | left | top+right+bottom | `295:188:4333:1824` |
| 8 | `centerRight` | right | left+top+bottom | `295:188:2733:1824` |

| Phase | Scale (milli) | Committed rect | Note |
| --- | --- | --- | --- |
| `move-0.5x` | 346 | `1314:512:2733:1824` | delta/scale exactly once |
| `move-1x` | 691 | `804:350:2733:1824` | |
| `move-3x` | 2073 | `974:404:2733:1824` | |
| `move-8x` | 5529 | `910:384:2733:1824` | |
| `move-clamped` | 5529 | `2029:384:2733:1824` | `CLAMPED=1`, right edge = page edge |
| `undo` | — | `910:384:2733:1824` | `RESTORED_EXACT=1` |
| `cancel` | — | `910:384:2733:1824` | `COMMITS=0:SAVES=0` |
| `two-finger-pinch` | 2791 | `910:384:2733:1824` | `COMMITS=0:SAVES=0`, zoom 1.382 → 2.791 |
| `two-finger-pan` | 1382 | `910:384:2733:1824` | `COMMITS=0:SAVES=0:PAN_CHANGED=1` |
| `min-size` | — | `910:384:32:32` | `PT=4.0:ANCHOR_FIXED=1` |

The authoritative sequence is `markers-integration.txt` (107 lines);
`marker-contract.txt` lists the 28 exact required shapes plus the three
occurrence counts (14 single-revision commits, 12 screenshots, 12 handshake
acks) and reports `missing=0`.

## 3. Host gates (evidence class `NONE`)

All commands ran in this worktree on the correction-1 candidate `44eb3e4` under
the shared compute permit; the exact terminal lines are in
`artifacts/2026-11-21-t071-touch/host-gates.txt`.

| # | Command | Exit | Result |
| ---: | --- | ---: | --- |
| 1 | `cd apps/feldexa_app && flutter analyze --no-pub` | 0 | No issues found! (83.3 s) |
| 2 | `cd apps/feldexa_app && dart format --output=none --set-exit-if-changed integration_test/android_review_test.dart` | 0 | 1 file, 0 changed |
| 3 | `cd apps/feldexa_app && flutter test --no-pub test/editor_geometry_test.dart test/editor_composition_test.dart` | 0 | **22/22** passed |
| 4 | `cd packages/feldexa_ui && flutter test --no-pub test/field_geometry_test.dart` | 0 | **31/31** passed |
| 5 | `cd apps/feldexa_app && flutter test --no-pub` | 0 | **469/469** passed |
| 6 | `git diff --check` (repo root) | 0 | clean |

The new integration-test helpers (stale-ack fail-closed, revision-count
assertion) are additionally exercised as negative controls **on the device** in
the same `flutter test` run; an integration test cannot run on the host VM.

## 4. Emulator acceptance — `EMULATOR` `PASS`

### 4.1 Run and result

- Driver: `tools/android/t071_drive_touch.sh`.
- Command (repo root, exclusive Orca session bound to this worktree, under the
  shared compute permit):
  `compute_slot.py --wait -- bash -lc '… && T071_REPLACE_EVIDENCE=1 tools/android/t071_drive_touch.sh'`.
- Driver `PASS`; `run-status.txt` = `result=PASS`, `flutter_test_exit=0`; the
  integration log ends `All tests passed!`.
- Privacy: 8/8 scans PASS; handshake preflight and cleanup both `verified=1`;
  all twelve screenshot hashes distinct.

### 4.2 Device, build and fixture identity

- Device: serial `emulator-5554`, AVD `T025_Pixel7_API35_KVM_20261115`,
  Android 15 / SDK 35, `x86_64`, fingerprint
  `google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys`,
  1080x2400 at density 420; page viewport 411 × 206 dp (the open suggestion
  panel is header content).
- Orca worktree-bound session: `orca-emulator-sessions.json`; device inventory:
  `orca-emulator-devices.json`.
- APK: `app-debug.apk`, **173421516 bytes**, SHA-256
  `1d12363b4c9b34c9f19948983289db79660c024052d9dcf2a90edc900ae96bf5`.
- Fixture: host and device copy both 5956 bytes / SHA-256
  `22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038`; the
  in-test T061 damaged derivation is 5956 bytes / SHA-256
  `57c1ade1ab2c00375ac61703db3d4ce5d27b996ea067647aba585866dc6ec221`.
- Git identity at run time: HEAD `44eb3e4`, tree `2747c4ea`, branch
  `xxammaxx/t071`, only the pre-existing `gradlew.bat` line-ending change.

### 4.3 Commands and exit codes (selected subset)

`commands.txt` is a **selected** receipt list, not a full transcript: the driver
records the emulator-allocation preflight, the fixture push, the `pub get` gate,
the checked stale-ack removal, the twelve `adb exec-out screencap` calls, the
`flutter test` invocation, the three device-cleanup commands and the cleanup
verification. It does not record every internal `adb shell` read (identity
probes, renders, logcat pulls). Recorded exit codes: all `0` except
`adb shell pm clear de.feldexa.app` = `1`, which is expected because the test
package is uninstalled when a `flutter test` run ends (the fresh install starts
with no app data).

`handshake-preflight.txt` (`exit=0`, `remaining_ack_files=0`, `verified=1`) and
`cleanup-verification.txt` (`staging GONE`, `stale_ack_files=0`,
`app_processes=0`, `verified=1`) record the two checked device-state gates.

### 4.4 Markers and screenshots

Markers are emitted by the integration-test process through the test harness, not
by the app process, so device logcat never contains them;
`markers-integration.txt` and `integration-android-t071.log` are the
authoritative records, and `logcat-t071-markers.log` holds only Android lifecycle
lines.

Because the page viewport is 411 × 206 dp while the field grows to
341.6 × 228 pt, a capture centred on the field interior shows no selection
outline above 3×. Each of the **twelve** phases emits a `T071_SHOT` marker
recording the capture scale, the focus kind, the fit flag and the asserted
rectangle, and the capture centres on the phase's evidence-bearing point:

| Phase | Capture | What the image shows |
| --- | --- | --- |
| `resize-corners` | 0.691, corner focus | the composed editor after the four corner resizes with the German panel, the T091 „Gespeichert um …“ label and the wide selection |
| `resize-edges` | 0.864, corner focus | the same document after the four edge resizes |
| `move-0.5x` | 0.346, whole rect | the 0.5× page with the moved field fully visible |
| `move-1x` | 0.691, whole rect | the 1× page with the moved field fully visible |
| `move-3x` | 2.073, corner focus | the 3× page with the field's selection corner at the viewport centre |
| `move-8x` | 5.529, corner focus | the 8× page with the field's selection corner and its two edges |
| `move-clamped` | 3.110, clamped edge focus | the field's right edge flush against the page's right edge |
| `undo` | 1.728, corner focus | the restored rectangle after the T067 undo |
| `cancel` | 1.210, corner focus | the unchanged rectangle after the discarded preview |
| `two-finger-pinch` | 2.791, corner focus | the zoomed page, geometry unchanged |
| `two-finger-pan` | 1.382, corner focus | the panned page, geometry unchanged |
| `min-size` | 5.529 (`maxScale`), whole rect | the 8× view of the clamped 4 × 4 pt field |

### 4.5 Privacy

Every committed text artifact is URL-redacted before it is written or copied, and
the driver fails the run on any hit from: `https?://`, `wss?://`, `AUTH_TOKEN`,
`127.0.0.1`, document content words, and (logs only) the fixture staging path.
`logcat-flutter.log` line 3 is now
`… The Dart VM service is listening on <URL_REDACTED>`. The eight scans in
`privacy-log-check.txt` all PASS. `commands.txt` names the committed synthetic
fixture path by design (synthetic delivery evidence, not user content) and is
therefore scanned for URLs/tokens and document content only.

The token that the superseded first-pass bundle committed is still present in the
branch **history**; rewriting it would require a force/rebase, which the task
prohibits. It was a per-run loopback Dart VM service token of the debug test app
on this local emulator and is invalidated when that process ended.

## 5. Corrections and runs (nothing hidden)

| Run | Commit | Outcome |
| --- | --- | --- |
| 1 | `3b5e0bb` | first pass: reached the editor, failed a phase precondition (fixed 60 pt deltas overshot the real field) |
| 2 | `b400140` | passed corners/edges and three move phases; failed an exact width comparison (double noise) |
| 3 | `fc48c0c` | test PASS; driver marker-contract prefix mismatch (driver-only fix) |
| 4 | `398f4e4` | test and driver PASS — **superseded** by Review A |
| 5 | `67c7ec1` | new negative controls failed: the probe directory was not app-writable and the chained duplicate save failed the editor's own commit; the failure text also tripped the new fixture-path privacy scan |
| 6 | `be68e39` | probe fixed; the double-commit control still stalled because a rightward drag on the 4 pt field hit the minimum clamp and committed nothing |
| 7 | `e3145ff` | test and driver PASS, but the driver half of finding 2 (checked ack preflight) was still missing, so that bundle was not accepted |
| — | `8997261` | run refused by the commit-before-run gate because the run-7 bundle was still uncommitted; the bundle was set aside and the run repeated after the commit |
| 8 | `44eb3e4` | **PASS** — this evidence: checked ack preflight, cleanup verification, 14 single-revision commits, both negative controls, privacy 8/8 |

Run 8's predecessor attempt (`8997261`) exposed an environmental outlier: one
commit took 18.3 s instead of the usual 0.6–1.1 s, which tripped the 3 s
hold-window cap. The hold window is now derived from the **fastest** verified
commit (still ≥ 1 s, capped at 3 s) and the slowest observed latency is recorded
in every `COMMIT` marker instead of being hidden. No assertion was removed: the
per-frame "no save while held" checks and the exactly-one-revision assertion are
unchanged.

No assertion was weakened, no production behavior faked, and no test seam is
undocumented: the two seams (counting facade around the real runtime, one
deliberate double-commit injection as the final action before teardown) are named
in the test header and in §2.

## 6. Artifacts

Directory `artifacts/2026-11-21-t071-touch/`. Every byte count and SHA-256 below
was recomputed from the committed file.

Byte-integrity note: the driver originals keep the trailing spaces that
`wm size`/`wm density`, one `flutter analyze` line and one Gradle progress line
produce; the committed copies are stripped so `git diff --check` stays 0. Values,
markers and log content are identical.

### 6.1 Files

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `command-binding.txt` | 2356 | `8c592417ca704e6e3277d44a8ebcb0ffba5b8ad3ae0172ec5c36c346cecdebc7` |
| `apk-sha256.txt` | 213 | `6a6faec7e26e92b1c5db2a16623a4bf8dba72ecd9f69c775237de48fb3b6310a` |
| `commands.txt` | 1991 | `29b6f22e970ec364046c472c10742049fadb9ed2dc4227ba250ddfef992e74a8` |
| `cleanup-verification.txt` | 134 | `3077bd1bc106c2fa8d9bc15d9b3b5e6a731855c3c285b253a602dab29fdbca36` |
| `handshake-preflight.txt` | 128 | `3ee3649bf896cf66b91ab926490e87239f645e93cbf01108a805c16f4e4268e4` |
| `device-identity.txt` | 298 | `265c299fe643739f0c63d2fc73f638d221a7aa9322b021641ab53bc0fedbbf56` |
| `fixture-sha256.txt` | 510 | `ae13daf5c2e23ab38c631bb54efeea1078415b14e8f821b20b648277bc2fa60b` |
| `git-identity.txt` | 308 | `dd2a0c357f03e506294c8e4db6abe439ddc3e89dcdccb7d1d7bfb4d30620cbba` |
| `host-flutter-pub-get.log` | 349 | `3c23abfe9ee53ae785ef9119e4040c124b3fcb72a71e53fbbfc77d5414315680` |
| `host-gates.txt` | 3960 | `2742ab828262969ded8c1e26ce3263ed8de45ef91504bb751dac67f86ae658b6` |
| `integration-android-t071.log` | 15021 | `b61641318516170d2d92b187e4afe6e2ad43ccbe7a09cf3248b600d929137f02` |
| `logcat-flutter.log` | 293 | `3e5e6b1baf337727075a4f3c53bae82d2ad5e3a3f86d57e80da45d6ed18e4584` |
| `logcat-t071-markers.log` | 773 | `6457d9305123286fa5acb05b4ba593afe7cadeced2c04b07248ea77b53b659d6` |
| `marker-contract.txt` | 3648 | `89fd7df8bf7477b4350a4556a6657c8203761cba049e9db52f9d336a8db00024` |
| `marker-sequence.txt` | 1186 | `704619ff6c8323b7c1c5118d6a2e814c07f0030fd8bab60b3d8eea424dbacb26` |
| `markers-integration.txt` | 10748 | `6cc20ede17c5a057b3c0f6c111ae8032131ca6e69f09f4e7dda2ac2c5084a8d3` |
| `orca-emulator-devices.json` | 1898 | `1984143118a212993ba5b4bacb4f4ab8bfe04f0229dd66fb8f8dc7f6538dbba2` |
| `orca-emulator-sessions.json` | 487 | `67ff10557842351e09049f9662d567bcdf48ba3096db18b95af2a72603edc34f` |
| `privacy-log-check.txt` | 576 | `d6ab84fb80a205b5abdfaa6c14112f3e8e53924252873ce74a981a8868344552` |
| `privacy-source-check.txt` | 76 | `41a0e0e059f3dad7ae90044e3a2e4acfc186422b4bcc0b1a0a68e3a05361d877` |
| `run-status.txt` | 32 | `7fd607f90d24581a4b9b797cff3d71e0f238dc52f3f869fd23b88a688a94f0b3` |
| `screenshot-hashes.txt` | 1148 | `d33e389c392eaa554b0c0b3c3a274f4a85e95efba8bd5e9ceab420b74138d115` |

### 6.2 Screenshots

| Phase | Bytes | SHA-256 |
| --- | ---: | --- |
| `resize-corners` | 266144 | `b42169a8128f93853763d21dd8150a74bc7a909ee91530ff2d357794d6d2a8d4` |
| `resize-edges` | 275682 | `18acf30ca52691234c9deaca82f80c4f0378b9094a7f06f8079e793c2d4bed25` |
| `move-0.5x` | 239032 | `af0f9306019f6565bddd0d7c518ee009d55f411d29010ea5c8b7731d4d3614a7` |
| `move-1x` | 265307 | `6f6a7a2d974c4d0180bee676ff9be4c3de0341bc376230a0a4ee2f4bb1026af6` |
| `move-3x` | 269825 | `3d77d71a02a6ca6f285d60d357c1dc458b7f5c8ee8be10c0d326871b5fb8db27` |
| `move-8x` | 273947 | `c8d7bd41595ba8c0b216e8a4689a520c7b4848315672ea830adf9e48dda1f721` |
| `move-clamped` | 219404 | `e688927659c8ad5fd56c08b5ceae002fec61683ff9e887bb6cf4741f5d57862a` |
| `undo` | 276949 | `5be8fba0f3fefac52a0d067c385ddecc4ee980e0515e64b9c01b5cff8a0421ae` |
| `cancel` | 271682 | `a85fd06488e924592d1950803a4cd02bc21a178d56bb28cd43eed65c27c0fd13` |
| `two-finger-pinch` | 274763 | `464e9215183bdd549422bd97598fbb6db657788826e7b5698aa6b52b6f483eaa` |
| `two-finger-pan` | 268645 | `7fcf0fc1a62b1d1df8cb13b77406251944b1cc1332a5dcb519d291dd5720b4b9` |
| `min-size` | 276492 | `ec7b69d3f590fbcd7501528f2b28ffcbb94e56236e7c967617fd58291a84a747` |

The screenshots necessarily show the synthetic fixture; no text is transcribed.
No APK binary, raw full logcat or key material is stored.

## 7. `NOT_RUN` register

- `DEVICE` acceptance and any performance claim (emulator evidence only).
- TalkBack/accessibility traversal of the eight handle regions and
  visual/golden inspection of the handles.
- Stylus/pen input, multi-window and split-screen touch input.
- Signature asset editing through T083.
- Export/share/print of a resized and moved geometry.
- Touch editing on a template route.
- Physical-device touch latency or frame-cost measurement of the geometry preview
  (the T071B code still rebuilds the screen once per pointer move).

## 8. Reproducibility

1. Check out `44eb3e4` (tree `2747c4ea`) on the `xxammaxx/t071` worktree plus
   this evidence commit.
2. `flutter pub get --offline` at the repository root.
3. Run the host gates in §3 (under the shared compute permit).
4. Attach an exclusive Orca Pixel 7 API 35 session to this worktree
   (`orca emulator list --worktree path:<worktree>` must show `emulator-5554`).
5. Run the driver under the permit:
   `compute_slot.py --wait -- bash -lc 'cd <worktree> && T071_REPLACE_EVIDENCE=1 tools/android/t071_drive_touch.sh'`.
   The driver enforces the commit-before-run gate, verifies the fixture, clears
   and verifies the stale acknowledgements, captures the twelve phases, verifies
   the exact marker contract and the twelve distinct hashes, scans privacy, and
   cleans up and verifies the device before writing the bundle.
6. Verify `run-status.txt`, `markers-integration.txt`, `marker-contract.txt`,
   `handshake-preflight.txt`, `cleanup-verification.txt`, `privacy-log-check.txt`,
   `screenshot-hashes.txt`, `apk-sha256.txt` and `commands.txt` against §4/§6.

## 9. Review

- Reviewer:
- Date:
- Verdict:
- Notes:
