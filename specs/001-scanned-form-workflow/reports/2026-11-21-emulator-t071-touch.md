# T071 Android touch move/resize review test — Pixel 7 API 35 emulator PASS

- **Task / issue**: T071 / <https://github.com/xxammaxx/Feldexa_2.0/issues/71>
- **Feature**: `specs/001-scanned-form-workflow` US3/US4
- **Date**: 2026-11-21 (local)
- **Host evidence class**: `NONE` (host-VM analyze, format, widget/unit tests)
- **Emulator evidence class**: `EMULATOR` — **`PASS`**
- **Overall result**: `PASS` — the candidate `398f4e4` is host-green and the real
  twelve-phase Android touch journey passed on the Orca-attached Pixel 7 API 35
  emulator against the composed T071A/T071B editor.
- **Dependency**: T071B integrated as PR #258 (merge `a5f3bae`); T071A integrated
  as PR #246 (merge `11675f3`). Base commit of this branch: `d53fb57`.

## 0. Machine-first handoff

```json
{
  "task": "T071",
  "issue": 71,
  "branch": "xxammaxx/t071",
  "base_commit": "d53fb57",
  "candidate_commit": "398f4e4b5c87b9951f9061c7b8f00d93167f52a0",
  "candidate_tree": "8db4a556e03bc839bcb8464e53a46e5768568a5a",
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
    "integration_log_end": "03:29 +1: All tests passed!",
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
      "bytes": 173401132,
      "sha256": "2eb859c99399f8bd7120c5fe11361d29a904b1203cee67e0e4ebdb9e62f02888"
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
    "screenshot_count": 12,
    "screenshot_hashes_distinct": true,
    "privacy_checks": "PASS (log and source)",
    "command_receipts": "commands.txt (host and emulator commands with exit codes)"
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

## 1. Revision, scope, and command binding

- Branch `xxammaxx/t071`, base `d53fb57` (T071B integrated).
- Commits on the branch, in order:
  1. `3b5e0bb` — the integration test plus the host driver plus the command
     binding artifact.
  2. `03c1ced` — driver: gate on the real `pub get` result.
  3. `b400140` — fit the touch phases to the real confirmed field (run 1
     finding).
  4. `fc48c0c` — compare the preserved drag size within double noise (run 2
     finding).
  5. `e1e8d9d` — driver: exact minimum-size marker prefix (run 3 finding; the
     run's test itself passed).
  6. `398f4e4` — capture each phase at its evidence-bearing view (evidence
     quality), **the commit that ran**.
- Changed paths vs the base: the new
  `apps/feldexa_app/integration_test/android_review_test.dart`, the new test-only
  `tools/android/t071_drive_touch.sh`, and the evidence bundle under
  `specs/001-scanned-form-workflow/reports/artifacts/2026-11-21-t071-touch/`
  (plus this report and the reports index / task row).
- No production app source, `feldexa_core`, `feldexa_ports`,
  `feldexa_recognition`, `feldexa_ui`, ARB/localization, Gradle, or
  `pubspec.yaml` file is changed. The pre-existing unstaged
  `apps/feldexa_app/android/gradlew.bat` line-ending change was never staged.
- No force/rebase/reset/stash, no new worktree, no new branch.

### 1.1 Command binding before the first edit

`command:speckit.implement` was resolved in this worktree before the first file
was written. Route: MCP `spec-kit` (`specify mcp`, JSON-RPC
`tools/call specify_artifact_info` with `identifier=command:speckit.implement`,
`isError: false`) → JSON CLI confirmation
(`specify artifact info command:speckit.implement --json`, identical record) →
the existing project artifact `.opencode/commands/speckit.implement.md` with
SHA-256 `e036ce63702db93e656e1c91ee6c02a8dc3d4a4f8624f8ba4adc69027fe68983`
(matches the expected digest). Execution receipt:

```
MCP specify_artifact_info(command:speckit.implement) -> active command "speckit.implement" ->
JSON CLI specify artifact info --json -> identical record ->
.opencode/commands/speckit.implement.md sha256 e036ce63702db93e656e1c91ee6c02a8dc3d4a4f8624f8ba4adc69027fe68983 (match) -> BOUND before first edit.
```

The full record (including the note that the harness did not materialise the
`mcp__spec_kit` tools and the same stdio server was therefore driven directly)
is `artifacts/2026-11-21-t071-touch/command-binding.txt`.

## 2. What the test proves

`apps/feldexa_app/integration_test/android_review_test.dart` drives the
production `main()` composition end to end:

1. the start list loads; the debug-only `de.feldexa/test.import` hook arms the
   deterministic T061 damaged-page-2 source derived in-test from the committed
   `sf-001.pdf` (5956 bytes, SHA-256 `57c1ade1…`);
2. the production import action performs the real encrypted staging, preflight,
   and verified commit; the real analysis run produces 28 suggestions and
   reaches `analysis-ready`;
3. the largest unresolved text suggestion on page 0 is confirmed through the
   production T066 confirm command (one durable revision);
4. the confirmed field is selected through the composed T077
   `FieldSelectionController` (no value sheet), and the real T071B touch
   geometry layer then edits it.

Contract sources: `contracts/editor-interactions.md` §4 and §11,
`contracts/coordinates-and-geometry.md` §3 and §6, FR-023/FR-024/FR-094,
SC-017.

| # | Phase | Proof |
| --- | --- | --- |
| A | `resize-corners` | all four corner handles resize; only the two dragged edges move; the diagonally opposite corner is bit-for-bit fixed; the aspect ratio stays free |
| B | `resize-edges` | all four edge handles resize; only the dragged edge moves; the opposite edge is bit-for-bit fixed; the `centerLeft` gesture starts 8.29 dp **outside** the stored rectangle and still claims the handle, so the hit band there is at least 16.6 dp thick and extends beyond the stored geometry (the contract reference value is the 24 dp region); the bottom edge grows and the right edge narrows the field for the body drags |
| C | `move-0.5x`, `move-1x`, `move-3x`, `move-8x` | the body drag commits exactly `pointerDelta / scale` on each axis at 0.5×, 1×, 3×, and 8× fit-width; the size is preserved; the rectangle stays inside the page |
| C′ | `move-clamped` | an 8× drag of 162.77 pt overshoots the page; the committed rectangle keeps its size and stops exactly at `pageBox.right = 595.28 pt` |
| D | `undo` | the T067 undo restores the exact pre-clamp rectangle (object equality, not re-derived) and writes one verified revision |
| E | `cancel` | a pointer cancel discards the preview: no head change, no content change, unchanged rectangle |
| F | `two-finger-pinch`, `two-finger-pan` | the first pointer claims a geometry drag, the second pointer cancels it, the page still zooms (scale 1.382 → 2.791) and pans, and geometry is untouched with zero commits |
| G | `min-size` | a resize dragged far past the anchor stops at exactly 4 × 4 pt with the top-left anchor fixed |
| H | read-back | the persisted field rectangle and head revision match the visible state |

### 2.1 Exactly one commit per gesture

Every gesture asserts, while the pointer is down:

- `state.headRevisionId` unchanged,
- the canonical `RevisionContent` snapshot unchanged,
- the stored rectangle unchanged,

on ≥ 2 pumped frames after the first move (`HELD_FRAMES=3` in every
`T071_COMMIT` marker, `MID_WRITE=0`), and after the pointer up exactly one new
head revision plus the T091 `saved` durability state (`NEW_HEAD=1`). The three
no-commit phases (`pointer-cancel`, `two-finger-pinch`, `two-finger-pan`) assert
`COMMITS=0` with the same head and content comparison.

### 2.2 Marker and rectangle evidence (1/8 pt)

`T071_FIELD_CONFIRMED` records the starting rectangle `455:348:3853:144`
(= 56.875, 43.5, 481.625, 18 pt). The resize chain, in 1/8 pt:

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

Body drags, with the committed rectangle after each commit:

| Phase | Scale (milli) | Pointer delta | Committed delta | Rect after |
| --- | --- | --- | --- | --- |
| `move-0.5x` | 346 | (44, 14) px | (+127.375, +40.5) pt | `1314:512:2733:1824` |
| `move-1x` | 691 | (−44, −14) px | (−63.625, −20.25) pt | `804:350:2733:1824` |
| `move-3x` | 2073 | (44, 14) px | (+21.25, +6.75) pt | `974:404:2733:1824` |
| `move-8x` | 5529 | (−44, −14) px | (−8.0, −2.5) pt | `910:384:2733:1824` |
| `move-clamped` | 5529 | (+900, 0) px | +162.75 pt → clamped | `2029:384:2733:1824` (`CLAMPED=1`; `RECT_8TH` rounds to 1/8 pt, the assertion compares the committed right edge to `pageBox.right = 595.28` pt within 1e-9) |
| `undo` | — | — | exact restore | `910:384:2733:1824` (`RESTORED_EXACT=1`) |
| `min-size` | 1037 | (−2000, −2000) px | clamped to 4 × 4 pt | `910:384:32:32` (`PT=4.0`, `ANCHOR_FIXED=1`) |

`T071_VIEW_READY` records `FIT_MILLI=691`, `MIN_MILLI=346`, `MAX_MILLI=5529`,
`VIEWPORT_W=411`, `VIEWPORT_H=206`; `T071_HIT_REGION` records
`OUTSIDE_PT=4.0`, `OUTSIDE_DP=8.29`, `MIN_BAND_DP=24.0`, `CLAIMED=1`.
`T071_TWO_FINGER:pinch` reached `SCALE_MILLI=2791` with `COMMITS=0`, and
`T071_TWO_FINGER:pan` recorded `PAN_CHANGED=1` with `COMMITS=0`.

The authoritative marker sequence is
`artifacts/2026-11-21-t071-touch/markers-integration.txt` (86 lines, extracted
from the integration log); `marker-contract.txt` lists the 18 required phase
markers and reports `missing=0`.

## 3. Host gates (evidence class `NONE`)

All commands ran in this worktree on the candidate working tree; the exact
terminal lines are in `artifacts/2026-11-21-t071-touch/host-gates.txt`.

| # | Command | Exit | Result |
| ---: | --- | ---: | --- |
| 1 | `cd apps/feldexa_app && flutter analyze --no-pub` | 0 | No issues found! (114.9 s) |
| 2 | `cd apps/feldexa_app && dart format --output=none --set-exit-if-changed integration_test/android_review_test.dart` | 0 | 1 file, 0 changed |
| 3 | `cd apps/feldexa_app && flutter test --no-pub test/editor_geometry_test.dart test/editor_composition_test.dart` | 0 | **22/22** passed (focused T071B composition + T071A composition) |
| 4 | `cd packages/feldexa_ui && flutter test --no-pub test/field_geometry_test.dart` | 0 | **31/31** passed (the T071B geometry unit layer used by the test) |
| 5 | `cd apps/feldexa_app && flutter test --no-pub` | 0 | **469/469** passed |
| 6 | `git diff --check` (repo root) | 0 | clean |

No new production helper was added, so gate 3/4 covers the composed geometry
behavior the new test drives; the new test file itself is exercised only by the
emulator run (an integration test cannot run on the host VM).

## 4. Emulator acceptance — `EMULATOR` `PASS`

### 4.1 Run and result

- Driver: `tools/android/t071_drive_touch.sh`.
- Command (repo root, exclusive Orca session bound to this worktree):
  `T071_REPLACE_EVIDENCE=1 tools/android/t071_drive_touch.sh`.
- Driver `PASS`; `run-status.txt` = `result=PASS`, `flutter_test_exit=0`; the
  integration log ends `03:29 +1: All tests passed!`.
- The journey contains no `RenderFlex`, overflow, or exception line.
- Privacy: `privacy-log-check.txt` PASS (no document content or fixture path in
  the integration log) and `privacy-source-check.txt` PASS (no network API
  reference in the integration test).
- All twelve screenshot hashes are distinct (`screenshot-hashes.txt`).

### 4.2 Device, build, and fixture identity

- Device: serial `emulator-5554`, AVD `T025_Pixel7_API35_KVM_20261115`,
  Android 15 / SDK 35, `x86_64`, fingerprint
  `google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys`,
  1080x2400 at density 420; the page viewport on the composed editor screen is
  411 × 206 dp (the open suggestion panel is header content).
- The Orca worktree-bound session is recorded in
  `orca-emulator-sessions.json`; the Orca device inventory in
  `orca-emulator-devices.json`.
- APK: `app-debug.apk`, **173401132 bytes**, SHA-256
  `2eb859c99399f8bd7120c5fe11361d29a904b1203cee67e0e4ebdb9e62f02888`.
- Fixture: host and device copy both 5956 bytes / SHA-256
  `22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038`; the
  in-test T061 damaged derivation is 5956 bytes / SHA-256
  `57c1ade1ab2c00375ac61703db3d4ce5d27b996ea067647aba585866dc6ec221`.
- Git identity at run time: HEAD `398f4e4`, tree `8db4a55`, branch
  `xxammaxx/t071`, only the pre-existing `gradlew.bat` line-ending change
  present.

### 4.3 Commands and exit codes

`commands.txt` records every host and emulator command with its exit code:
`adb devices`, `orca emulator devices --json`,
`orca emulator list --worktree path:<worktree> --json`, the fixture push, the
`adb exec-out screencap` calls (twelve), `flutter pub get --offline`, and
`flutter test --no-pub integration_test/android_review_test.dart -d
emulator-5554` (exit 0). One recorded non-zero code is expected and explained:
the pre-run `adb shell pm clear de.feldexa.app` returns 1 because the test
package is not installed at that moment (`flutter test` uninstalls the app when a
run ends), so `/data/data/de.feldexa.app` does not exist and `pm clear` reports
`Failed`. The integration-test install therefore starts from a fresh app with no
stored data, which is the state the journey needs; no stale store state was
carried into the run.

### 4.4 Markers and screenshot semantics

Markers are emitted by the integration-test process through the test harness,
not by the app process, so device logcat never contains them;
`markers-integration.txt` and `integration-android-t071.log` are the
authoritative records, and `logcat-t071-markers.log` holds only Android
lifecycle lines.

The page viewport is 411 × 206 dp while the tested field grows to 341.6 × 228 pt,
so a capture centred on the field interior shows no selection outline at 3× and
above. Each capture therefore centres on the phase's evidence-bearing point and
`T071_SHOT` records the capture scale, the focus kind, the fit flag, and the
asserted rectangle:

| Phase | Capture | What the image actually shows |
| --- | --- | --- |
| `resize-corners` | 0.691, corner focus | the composed editor after the four corner resizes, with the German suggestion panel, the T091 „Gespeichert um …“ label and the wide selected rectangle |
| `resize-edges` | 0.864, corner focus | the same document after the four edge resizes |
| `move-0.5x` | 0.346, whole rect | the 0.5× page with the small moved field fully visible |
| `move-1x` | 0.691, whole rect | the 1× page with the moved field fully visible |
| `move-3x` | 2.073, corner focus | the 3× page with the field's selection corner at the viewport centre |
| `move-8x` | 5.529, corner focus | the 8× page with the field's selection corner and its two edges |
| `move-clamped` | 3.110, clamped edge focus | the field's right edge flush against the page's right edge at the clamp |
| `undo` | 1.728, corner focus | the restored rectangle after the T067 undo |
| `cancel` | 1.210, corner focus | the unchanged rectangle after the discarded preview |
| `two-finger-pinch` | 2.791, corner focus | the page after the two-finger zoom, geometry unchanged |
| `two-finger-pan` | 1.382, corner focus | the panned page, geometry unchanged |
| `min-size` | 5.529 (`maxScale`), whole rect | the 8× view of the clamped 4 × 4 pt field |

All twelve hashes are distinct (see §6.2).

## 5. Deviations and corrections (documented, no weakened assertion)

The task's own acceptance shape required four measured corrections; each is a
separate commit and none removes or softens a contract claim:

1. **Phase deltas fitted to the real field (`b400140`).** The first real run
   confirmed the field as 481.625 × 18 pt at (56.875, 43.5) — not the narrower
   line in the T061 anchor list — on a 411 × 206 dp viewport. Fixed ±60 pt corner
   deltas would have overshot the page, so the resize phases now move 20 pt per
   dragged edge at a documented 3× fit-width gesture zoom, the bottom edge grows
   the field so the 0.5× body drag has a real body (48 dp minimum), and the right
   edge narrows it so the body drags keep page room. Every phase keeps an
   explicit "expected rectangle lies inside the page" precondition, so a future
   fixture change fails loudly instead of silently proving a clamp.
2. **Size-preservation tolerance (`fc48c0c`).** A committed body move re-derives
   an edge as `(right + dx) − (left + dx)`, so the preserved width can differ
   from the previous width in the last bits (observed
   `341.625` vs `341.62500000000006`). The assertion uses a `1e-9 pt` tolerance,
   three orders of magnitude below the persisted `0.001 pt` quantization and far
   below the 1/8 pt evidence grid. This is an observation about double
   arithmetic, not a behavior change; no production code is touched.
3. **Screenshot focus (`398f4e4`).** See §4.4. The assertions are unchanged; only
   the capture view and the added `T071_SHOT` marker changed.
4. **Driver marker prefix (`e1e8d9d`).** The test prints the contract value as a
   double (`PT=4.0`); the driver's required prefix is `T071_MIN_SIZE:PT=4`. Run
   3's test itself passed every phase (`All tests passed!`); only the driver's
   post-hoc marker contract failed, and the fix is driver-only.

Three aborted runs preceded the PASS run. Each one self-cleaned (staging removed,
app force-stopped, settings restored) and each is named here rather than hidden:

| Run | Commit | Outcome |
| --- | --- | --- |
| 1 | `3b5e0bb` | reached the editor and the first corner phase; failed the inside-page precondition (finding 1) |
| 2 | `b400140` | passed corners, edges and three move phases; failed the exact width comparison (finding 2) |
| 3 | `fc48c0c` | **test PASS** (`All tests passed!`); driver failed its marker contract only (finding 4) |
| 4 | `398f4e4` | **test and driver PASS** — the evidence recorded above |

## 6. Artifacts

Directory `artifacts/2026-11-21-t071-touch/`. Every byte count and SHA-256 below
was recomputed from the committed file.

### 6.1 Files

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `command-binding.txt` | 2356 | `8c592417ca704e6e3277d44a8ebcb0ffba5b8ad3ae0172ec5c36c346cecdebc7` |
| `apk-sha256.txt` | 213 | `1d2796e036b5ec05594129b05f7c524c2ad6b3b3d1eb922011e3bf341e22217a` |
| `commands.txt` | 1562 | `199eee32e568328cd48176080d183bcdb534a933bbf665e9512c47589e721096` |
| `device-identity.txt` | 300 | `2ac7e85ab159fbb83398cb9eeeb4301fb8613bda5b4133a7ad9e82ab3d36fa54` |
| `fixture-sha256.txt` | 510 | `ae13daf5c2e23ab38c631bb54efeea1078415b14e8f821b20b648277bc2fa60b` |
| `git-identity.txt` | 324 | `d91724adba8c1912e997a745ca07e751d68cb8193c3833d833c3bc152c07d591` |
| `host-flutter-pub-get.log` | 349 | `3c23abfe9ee53ae785ef9119e4040c124b3fcb72a71e53fbbfc77d5414315680` |
| `host-gates.txt` | 3045 | `c04f9fd5f00d9f011717db8a3c975833f1477c3146a1fa032123590de5ec2b62` |
| `integration-android-t071.log` | 12493 | `b59b1691c9fc27ea5cfddc8e4b93fab621574ff85e2736381d60f057954a8e8f` |
| `logcat-flutter.log` | 315 | `f5daffbbbca8aef1e5f1e02289170e9bfac1aa3a412476f8e62d7bde8e7b75a9` |
| `logcat-t071-markers.log` | 775 | `1476c4e299f9945fbe0033a0c9c2d5e473ea9e9e2a4f5dc3998d41c5c1d4e2d7` |
| `marker-contract.txt` | 655 | `fe1efc5c44e3bbd80ed6dcc387a4ffe335e15e01154acd27bd563eac5876d006` |
| `marker-sequence.txt` | 1186 | `5b5452f56b291a2d1b3709d248cf430b8e16fcc35818436214a1a3ddeab32af2` |
| `markers-integration.txt` | 8174 | `108f9304aa16f97a1fccb37cf595900bfe761f9c3b18b9442738eb1f6c4ec243` |
| `orca-emulator-devices.json` | 1898 | `b1301644c6417643f05c6fb5ebd4ce3525e4f9dcad59da9dcf2ccf3ec15203f7` |
| `orca-emulator-sessions.json` | 487 | `068c7585cc06a5e5a110648abc79724dbaefe1ed9e8b033993d884afeac1be30` |
| `privacy-log-check.txt` | 65 | `7c1bcbf4be8b5984e329ec2afbf1f30214982fc899c13e17f3346fc1c0be22ea` |
| `privacy-source-check.txt` | 76 | `41a0e0e059f3dad7ae90044e3a2e4acfc186422b4bcc0b1a0a68e3a05361d877` |
| `run-status.txt` | 32 | `7fd607f90d24581a4b9b797cff3d71e0f238dc52f3f869fd23b88a688a94f0b3` |
| `screenshot-hashes.txt` | 1148 | `1e48f14cd56d591b43d0de9b0930eb3c094a7373a621f69478c5c5c96c12bee0` |
| `host-gates.txt` (recomputed after the emulator run) | 3045 | see above |

### 6.2 Screenshots

| Phase | Bytes | SHA-256 |
| --- | ---: | --- |
| `resize-corners` | 266628 | `81c5913618d71697c648dac605c1e16ab4dc8fa6910e0f6106cf98693a333be3` |
| `resize-edges` | 276127 | `77ce5515d29c85e4d450d25e3703668c67c873d35ffb8b084df9820b3c549339` |
| `move-0.5x` | 239458 | `233c35570b6d54827e7b0dfa26ef8d59321f7fd469ea866b317e3c8e913a0a91` |
| `move-1x` | 265774 | `31f0909708f0d1d5d8cdd5938a288feef61c1bca8cc0ad244cfa5bd642f4f527` |
| `move-3x` | 270238 | `1d5771b9d40ebdfb8d97ba227c90118c59b1799a73d63c4d6d49f922e0b14b2d` |
| `move-8x` | 274206 | `ab2a05d5a546fdc8e38a831f43c09e0ec3395f1dab196f9aa59a4c8c04ce87e3` |
| `move-clamped` | 219697 | `6d3abd5c694e81b909f519a8bdf49630ff79a232cd16ea479d88fd717dd38635` |
| `undo` | 277180 | `efa5269d7cc960ba27d8dbc667a74e1d0d436249a01a62c2a529099cc807b745` |
| `cancel` | 271918 | `54c48a51bcd4fbbd338f4c9b68b1756fb0cee0d1cbc21aa321bf50f81c6955e5` |
| `two-finger-pinch` | 275012 | `e96f3c9ccf416a3ee03bdc0c9e57740d45d947ca8e8227966d8a5b6a3a398b8a` |
| `two-finger-pan` | 268827 | `8d8623d6498bc5857f1d539f61a41588b12eea366dcb730881c140aecb43fd7e` |
| `min-size` | 276715 | `a201475a713ab339d4634be798144fb661ff6711c5cc74c15594278bdcda26d9` |

The screenshots necessarily show the synthetic fixture; no text is transcribed.
No APK binary, raw full logcat, or key material is stored.

## 7. `NOT_RUN` register

- `DEVICE` acceptance and any performance claim (emulator evidence only).
- TalkBack/accessibility traversal of the eight handle regions and visual/golden
  inspection of the handles.
- Stylus/pen input, multi-window and split-screen touch input.
- Signature asset editing through T083.
- Export/share/print of a resized and moved geometry.
- Touch editing on a template route.
- Physical-device touch latency or frame-cost measurement of the geometry
  preview (the T071B code still rebuilds the screen once per pointer move).

## 8. Reproducibility

1. Check out `398f4e4` (tree `8db4a55`) on the `xxammaxx/t071` worktree plus this
   evidence commit.
2. `flutter pub get --offline` at the repository root.
3. Run the host gates in §3.
4. Attach an exclusive Orca Pixel 7 API 35 session to this worktree
   (`orca emulator list --worktree path:<worktree>` must show `emulator-5554`).
5. Run `T071_REPLACE_EVIDENCE=1 tools/android/t071_drive_touch.sh` from the repo
   root. The driver enforces the commit-before-run gate, verifies the fixture,
   captures the twelve phases, verifies the marker contract and the twelve
   distinct hashes, and writes the bundle to
   `specs/001-scanned-form-workflow/reports/artifacts/2026-11-21-t071-touch/`.
6. Verify `run-status.txt`, `markers-integration.txt`, `screenshot-hashes.txt`,
   `apk-sha256.txt`, `device-identity.txt`, and `commands.txt` against §4 and §6.
7. Cleanup: the driver removes the pushed fixtures and acknowledgements,
   force-stops the app, and restores the device settings it changed. It never
   rebinds or steals another worktree's emulator session.

## 9. Review

- Reviewer:
- Date:
- Verdict:
- Notes:
