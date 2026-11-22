# T086A signature and field-overlay composition — host evidence and Pixel 7 API 35 emulator PASS

- **Task / issue**: T086A / <https://github.com/xxammaxx/Feldexa_2.0/issues/269>
- **Feature**: `specs/001-scanned-form-workflow` US4
- **Date**: 2026-11-22 (local)
- **Branch**: `xxammaxx/t086a`
- **Rebased base**: `1a141cdac586238021ade8a18e40c08883a9d1a6` (origin/main)
- **Host evidence class**: `NONE` (host-VM analyze, format, widget/unit tests)
- **Emulator evidence class**: `EMULATOR` — **`PASS`** (final candidate, second run)
- **Overall result**: `PASS` for this task's own scope. T086 (the two-page US4
  acceptance) and T086B (detector performance) remain open and are not claimed.

## 0. Machine-first handoff

```json
{
  "task": "T086A",
  "issue": 269,
  "branch": "xxammaxx/t086a",
  "requested_base_commit": "2ab14cc93f2452a0153e6ca28293573df8376f48",
  "rebased_onto": "1a141cdac586238021ade8a18e40c08883a9d1a6",
  "candidate_code_commit": "f72e9b9e584c5721425d9914610f47280693f01e",
  "candidate_code_tree": "18837b31a94fbdaa4485a84ea23fdb7428881390",
  "emulator_run_head": "ef65da35ea67fea3169365d037b62385c1300e86",
  "emulator_run_tree": "54994b64fc227afad92b91eafbdb03f3f231a432",
  "production_identical_to_candidate": true,
  "emulator_bound_test_identical_to_candidate": true,
  "host_test_identical_to_candidate": false,
  "host_test_difference": "apps/feldexa_app/test/field_value_sheet_test.dart — correction-1 removed three unused _pumpSheet parameters (canGoPrevious, signatureDrafts, signatureResult); host widget test, never compiled into the emulator run",
  "evidence_bundle": "specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t086a-signature",
  "host_evidence_class": "NONE",
  "emulator_evidence_class": "EMULATOR",
  "overall_result": "PASS",
  "command_binding": {
    "requested": "command:speckit.implement",
    "mcp": "mcp__spec_kit__specify_describe_command {command: 'speckit.implement'} -> unavailable_command (the experimental Spec Kit MCP server exposes only 'version')",
    "json_cli": "specify artifact info command:speckit.implement --json -> id=command:speckit.implement, kind=command, strategy=replace, single active stack layer",
    "file": ".opencode/commands/speckit.implement.md",
    "sha256": "e036ce63702db93e656e1c91ee6c02a8dc3d4a4f8624f8ba4adc69027fe68983",
    "resolved_at_utc": "2026-11-22T07:29:14Z",
    "resolved_before_first_edit": true
  },
  "host_counts": {
    "application_apply_signature": 10,
    "app_signature_png": 7,
    "app_editor_signature": 7,
    "app_field_controls_signature_group": 3,
    "focused_seven_file_run": 100,
    "app_suite": 546,
    "application_suite": 187
  },
  "host_gates": {
    "app_analyze": "exit 0, no issues",
    "application_analyze": "exit 0, no issues",
    "format": "exit 0, 115 files, 0 changed",
    "focused_seven_file_run": "100/100 passed",
    "app_suite": "546/546 passed",
    "application_suite": "187/187 passed",
    "git_diff_check": "exit 0",
    "overall_exit": 0
  },
  "emulator": {
    "driver": "tools/android/t086a_drive_signature.sh",
    "test": "integration_test/android_signature_overlay_test.dart",
    "driver_result": "PASS",
    "run_status": "result=PASS, flutter_test_exit=0",
    "screenshots": 6,
    "distinct_screenshot_hashes": 6,
    "apk_bytes": 173469607,
    "apk_sha256": "e7ced48bf485ebc419cca7c49ca2dbcc39357d557ab43d1382107293ccfe786a",
    "fixture_sha256": "22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038",
    "derived_damaged_fixture_sha256": "57c1ade1ab2c00375ac61703db3d4ce5d27b996ea067647aba585866dc6ec221",
    "device": {
      "serial": "emulator-5554",
      "avd": "T025_Pixel7_API35_KVM_20261115",
      "android_release": "15",
      "sdk": 35,
      "abi": "x86_64",
      "wm_size": "1080x2400",
      "wm_density": 420
    },
    "privacy_checks": "PASS (2/2)",
    "cleanup_marker": "T086A_CLEANUP_DONE"
  },
  "signature_detector_gap": {
    "observed": "0 signature suggestions on page 1 of sf-001 (28 suggestions total)",
    "baseline_agreement": "matches reports/2026-11-20-us2-integration-emulator.md §5.1 (0 signature)",
    "consequence": "the journey seeds one confirmed signature field through the existing addField command; no recognition, ARB, pubspec, Gradle, core, or ports change was made"
  }
}
```

## 1. What changed

### 1.1 Production paths (4 files, no new architecture)

| Path | Change |
| --- | --- |
| `packages/feldexa_application/lib/src/review/apply_signature.dart` | New pure command: `SignatureAsset.fromPng` (PNG validation, 1024 px long-edge bound, byte copy, SHA-256) and `applySignature` (one revision snapshot with the matching `SignatureValue` and `SignatureMark` for exactly one confirmed signature field/page). No clock, id, I/O, or global ink. |
| `apps/feldexa_app/lib/features/fill/signature_png.dart` | The single draft→PNG bridge: paints exactly the captured strokes with the sheet's 2.5 px rounded line, transparent background, long edge bounded by 1024 px, deterministic per draft. |
| `apps/feldexa_app/lib/features/editor/field_value_sheet.dart` | The signature branch no longer shows `NOT_RUN`. It shows the signed/unsigned state and an „Ausfüllen“ action that opens the existing T083 `SignatureSheet` full screen; apply hands one immutable draft to the new `onSignatureCommit`, an empty apply is an honest no-op, and a failure keeps the sheet open with the caller's content-free message. |
| `apps/feldexa_app/lib/features/editor/editor_screen.dart` | `_saveSignature`: encode → digest/dimensions → one `SecureStorePort.writeSignature` → `applySignature` → `_commitSnapshot(kind: addSignature, fieldId:)`, i.e. exactly one verified revision and one undo step. A failed asset write performs no revision write; a failed revision save leaves the document unsigned. |

`signature_sheet.dart` (T083) needed **no** change: the wiring reuses its
existing presentation-only contract (caller labels, immutable draft, no I/O).
No core, ports, recognition, ARB, Gradle, or `pubspec.yaml` file was modified.

### 1.2 Label decision (no ARB change permitted)

T086A may not add catalog text, so the sheet labels reuse committed ARB keys:
title `suggestionTypeSignature` („Unterschrift“), apply
`suggestionConfirmAction` („Übernehmen“, exactly the contract §5 wording),
undo `suggestionUndoAction` („Rückgängig“), cancel
`reviewConflictCloseAction` („Schließen“), the capture action `fillAction`
(„Ausfüllen“), and clear `suggestionRejectAction` („Ablehnen“). The clear action
is the one wording compromise: the catalog has no „Leeren“ action and adding
one is a contract change outside this task. It is disclosed here as a label
compromise only: in `signature_sheet.dart` the clear action is an `IconButton`
with `Icons.delete_outline` whose `tooltip` (tooltip plus accessibility label)
carries that text, so the „Ablehnen“ wording is **not** visible as text in the
`signature-sheet` screenshot — only the trash icon is.

### 1.3 Test paths (5 new files, 4 updated)

- `packages/feldexa_application/test/apply_signature_test.dart` (10 tests):
  FIPS 180-4 digests pinned against independently computed values for four
  padding shapes, asset validation and byte copy, field/page/rect binding,
  preservation of every other revision member, replacing an earlier signature,
  independence of two signature fields **within one document** (no global ink;
  the test never opens a second document), and content-free errors.
- `apps/feldexa_app/test/signature_png_test.dart` (7 tests): real PNG output,
  no upscaling, 1024 px cap, transparent background with dark ink only,
  determinism and buffer independence, unusable-canvas null, empty draft, and
  `package:crypto` cross-check of the command digest.
- `apps/feldexa_app/test/editor_signature_test.dart` (7 tests): one asset write
  plus one bound revision with the real digest and PNG dimensions, reopen and
  store read-back, exact undo restore, failed asset write (no revision), failed
  revision save (unsigned document, unreferenced asset), no shared ink across
  fields/commits, and a real-page overlay test that paints, selects, moves and
  resizes the confirmed signature field.
- `apps/feldexa_app/test/field_controls_test.dart` (signature group rewritten to
  three tests plus the unchanged type tests), `field_value_sheet_test.dart`
  (new `onSignatureCommit` plumbing), `editor_composition_test.dart`, and
  `review_degraded_test.dart` (constructor/wiring updates).
- `apps/feldexa_app/integration_test/android_signature_overlay_test.dart` and
  `tools/android/t086a_drive_signature.sh`: the real journey and its host
  driver (device identity, fixture staging, screenshot handshake, APK/git
  identity, privacy scan, cleanup verification).

## 2. Host gates (final candidate `f72e9b9`, tree `18837b3`)

```text
app analyze            no issues (0)
application analyze    no issues (0)
format gate            115 files, 0 changed
focused 7-file run     100/100 passed
app suite              546/546 passed
application suite      187/187 passed
git diff --check       exit 0
```

Every heavy command ran under
`python3 /home/xxammaxx/.agents/skills/orca-maintainer/scripts/compute_slot.py --wait -- …`,
one sequence at a time (shared with T086B).

## 3. Emulator journey (final candidate)

Driver `tools/android/t086a_drive_signature.sh` on the Orca-attached Pixel 7
API 35 device `emulator-5554` (AVD `T025_Pixel7_API35_KVM_20261115`, 1080 × 2400
at 420 dpi). Journey:

1. import the deterministic T061 damaged-page-2 variant of the committed
   `sf-001.pdf` (page 1 stays the real, readable page);
2. first analysis reaches `analysis-ready` with 28 suggestions and
   **0 signature suggestions** — identical to the T061/US2 baseline, so no
   recognition quality changed;
3. one confirmed *signature* field is seeded on the real page through the
   existing `addField` command and one verified revision (documented detector
   gap, see §5);
4. reopen the stored document from the start list (analysis skipped from the
   persisted suggestions), confirm one real machine suggestion, select it, and
   move/resize on the real page with one verified revision per gesture and no
   write while the pointer is held;
5. open the signature sheet from the confirmed field, draw two strokes, undo,
   clear, draw again, apply; the editor writes the PNG asset, then one revision
   with the value and the mark;
6. read the asset and value back from the real encrypted store and compare the
   digest, the PNG bytes, and the mark dimensions;
7. leave, reopen from the start list, and verify the signed state and the same
   asset id survive.

Authoritative marker sequence (`markers-integration.txt`):

```text
T086A_ANALYSIS_READY:STATE=analysis-ready:PAGES=2:SUGGESTIONS=28:SIGNATURE_SUGGESTIONS=0
T086A_SIGNATURE_FIELD_SEEDED:ON_REAL_PAGE=1
T086A_SIGNATURE_FIELD_LOADED:OVERLAY=1
T086A_MACHINE_FIELD_CONFIRMED:OVERLAY=1
T086A_OVERLAY_SELECTED:PAGE=0:FIELD_CONFIRMED=1
T086A_MACHINE_CENTRE_REGION:topLeft
T086A_MOVE_GESTURE:SCALE_MILLI=1000:DRAG_PX=120:STEPS=12
T086A_MOVE_DIAG:BEFORE_LEFT_MILLI=47622:AFTER_LEFT_MILLI=167622:BEFORE_TOP_MILLI=622999:AFTER_TOP_MILLI=622999
T086A_FIELD_MOVED:DELTA_MATCHES_SCALE=1:WIDTH_KEPT=1:HEIGHT_KEPT=1:SAVES=1:HEAD_CHANGED=1
T086A_FIELD_RESIZED:WIDTH_GREW=1:HEIGHT_GREW=1:LEFT_KEPT=1:TOP_KEPT=1:SAVES=1
T086A_SIGNATURE_SHEET_INK:DRAW=1:UNDO=1:CLEAR=1:REDRAW=1
T086A_SIGNATURE_STATE:BOUND=1:MARKS=1:WIDTH_LE=1024=1:HEIGHT_LE_1024=1
T086A_SIGNATURE_READBACK:OK:PNG=1:DIGEST_MATCH=1:DIMS_MATCH=1:VALUE_BOUND=1:MARK_BOUND=1
T086A_SIGNATURE_REOPENED_READBACK:OK:ASSET_SAME=1
T086A_CLEANUP_DONE
```

The move delta is exactly `120 px / 1.0` display points
(`47622 → 167622` milli-points) with the top unchanged, and the resize grows the
width and height while keeping the top-left anchor exact — real touches on the
real page, not a fixture unit test.

Two marker caveats (correction-1):

- The `SAVES=1` / `HEAD_CHANGED=1` suffixes above are **literal label text**
  printed by `android_signature_overlay_test.dart`, not measurements. What the
  run actually asserts is the head change after each gesture (`_waitForCommit`:
  a non-null head different from the pre-gesture head) and "no stored revision
  while the pointer is held" (the canonical content JSON is compared on every
  held frame). The exact one-save count is host-proven, not emulator-proven:
  `editor_signature_test`'s recording store shows exactly one asset write plus
  one verified revision, and `field_controls_test` shows exactly one applied
  draft.
- `logcat-t086a-markers.log` contains **no** `T086A_` marker. It holds five
  `ActivityTaskManager` lifecycle lines (start, displayed, fully drawn, force
  remove, no app thread) because the markers are printed by the integration-test
  harness, not by the app process. The authoritative marker sequence is
  `markers-integration.txt`, which the driver extracts from
  `integration-android-t086a.log`. That file also carries the fixture/readiness
  and screenshot-handshake lines, and its screenshot lines appear with a doubled
  `T086A_T086A_SCREENSHOT_*` prefix; the sequence quoted above is the subset the
  journey asserts.

Screenshots (6, all distinct, `screenshot-hashes.txt`):
`overlay-selection`, `field-moved`, `field-resized`, `signature-sheet`,
`signature-signed`, `signature-reopened`.

Artifacts: APK `e7ced48b…` (173 469 607 bytes), fixture `22c939cc…`, derived
damaged fixture `57c1ade1…`, device identity, Orca device/session inventory,
marker-filtered logcat, privacy checks (2/2 PASS) and `T086A_CLEANUP_DONE`.

### 3.1 Why there were two emulator runs

The first passing run was produced on the pre-format tree `5731161`. The
repository formatter then rewrote six of the new files (whitespace only), so the
tree no longer matched. The branch was rebased onto `origin/main` `1a141cd` and
the journey was rerun; the evidence above belongs to the final candidate. The
earlier run is preserved under `runs/run-2-preformat/` and the first, failing
run under `failed-run-1/`.

### 3.2 The diagnosed geometry failure (`failed-run-1`)

The first run failed with `expect(afterMove.left, greaterThan(beforeMove.left))`
→ `113.375` vs `114.875`. Cause: the drag started at the centre of the *thin*
confirmed text strip. At that view scale the strip's height is smaller than the
24 dp handle hit region, so the contract's corner/edge-before-body rule
(`hitTestFieldGeometry`) resolved the touch-down to the `topLeft` handle, and a
horizontal drag then committed a tiny edge resize instead of a move. The final
journey records that region (`T086A_MACHINE_CENTRE_REGION:topLeft`), centres the
48 pt signature field at 1×, *asserts* that its centre resolves to
`FieldGeometryHandle.body`, and only then performs the move and the corner
resize. The expectations were tightened (exact delta/scale and exact anchors),
not weakened. Two further runs fixed test-side-only defects: reading back
through a disposed runtime, and tapping a field that a route change had scrolled
out of the viewport (all field taps now centre through the documented
`setViewController.setView` seam).

## 4. Requirement mapping

| Requirement | Evidence |
| --- | --- |
| `SignatureSheet` in the real signature branch, draw/undo/clear/apply | `field_controls_test` signature group, `editor_signature_test` first and reopen tests, `signature-sheet` screenshot |
| Smallest command: draft → PNG asset → `writeSignature` + `SignatureMark`/`SignatureValue` in ONE verified revision | `apply_signature_test`, `signature_png_test`, `editor_signature_test`, `SIGNATURE_READBACK` marker |
| Bound to the current document/field, no library, no global/static ink | `applySignature` rejects missing/non-signature fields and binds field id + page; `keeps two documents and fields independent (no global ink)` (which exercises two signature fields of **one** document) and `two fields never share ink` tests; no static ink in `signature_sheet.dart`/`signature_png.dart` |
| Overlay/geometry on real pages | The emulator run confirms and selects one real **machine** suggestion on the real page (`MACHINE_FIELD_CONFIRMED` → `OVERLAY_SELECTED`) but does **not** move or resize it; the move (`FIELD_MOVED`) and the corner resize (`FIELD_RESIZED`) run on the seeded **signature** field, which is itself a confirmed field on the real page. `editor_signature_test` repeats paint/select/move/resize as a host test. Three screenshots. |
| Host tests for command/asset/revision/binding, sheet wiring, overlay/geometry, no global ink | 35 new/rewritten host tests listed in §1.3 |
| Real emulator evidence with screenshots/logs/APK SHA/commit SHA | §3 and the evidence bundle |
| No recognition performance/quality change (T086B) | no recognition file touched; analysis result identical to the US2 baseline (28 suggestions, 0 signature) |

## 5. Disclosed limitation and residuals (`NOT_RUN`)

- **Detector signature gap (out of scope, not fixed).** The committed detector
  produces 0 `signature` suggestions for the `sf-001` fixture (see
  `reports/2026-11-20-us2-integration-emulator.md` §5.1). T086A may not change
  recognition or add a field-creation UI, so the emulator journey seeds one
  confirmed signature field with the existing `addField` command and one
  verified revision before exercising the real sheet, commit, overlay, and
  store. The sheet/asset path itself is fully productive for any document that
  already has a signature field.
- **Clear-action wording.** No ARB change was authorized; the clear action
  reuses „Ablehnen“ (§1.2).
- **`DEVICE` acceptance, TalkBack traversal of the signature canvas, stylus
  input, golden/visual review, and any performance claim remain `NOT_RUN`.**
- **T086** owns the two-page US4 acceptance and the overflow decision; **T086B**
  owns the detector runtime. Neither is claimed here.
- Signature canvas semantics (no label/role) and undo-during-active-stroke are
  unchanged T083 residuals.

## 6. Command binding, commit and tree

| Item | Value |
| --- | --- |
| `command:speckit.implement` (MCP) | `unavailable_command` (server exposes only `version`) |
| `command:speckit.implement` (JSON CLI) | `specify artifact info … --json` → single active layer, `strategy: replace` |
| Resolved file | `.opencode/commands/speckit.implement.md` |
| SHA-256 | `e036ce63702db93e656e1c91ee6c02a8dc3d4a4f8624f8ba4adc69027fe68983` |
| Resolved (UTC) | `2026-11-22T07:29:14Z`, before the first edit |
| Rebased base | `1a141cdac586238021ade8a18e40c08883a9d1a6` |
| Candidate code commit / tree | `f72e9b9e584c5721425d9914610f47280693f01e` / `18837b31a94fbdaa4485a84ea23fdb7428881390` |
| Emulator run HEAD / tree | `ef65da35ea67fea3169365d037b62385c1300e86` / `54994b64fc227afad92b91eafbdb03f3f231a432` |
| Evidence commit | the commit that adds this report and the bundle; its own SHA/tree cannot be embedded in its own bytes |
| Pre-existing dirty file | `apps/feldexa_app/android/gradlew.bat` (CRLF normalization) — never staged or committed |
| Push / PR | none (local branch only) |

Two independent read-only reviews and the merge gates are owned by the
coordinator and were **`NOT_RUN`** at the time of writing.

## 7. Correction-1 (scoped documentation/evidence correction, issue #269)

Correction-1 changes no production behavior and no emulator-bound test byte. It
ran as the scoped Spec Kit implementation wrapper `command:speckit.implement`
(`.opencode/commands/speckit.implement.md`, SHA-256
`e036ce63702db93e656e1c91ee6c02a8dc3d4a4f8624f8ba4adc69027fe68983`) with
`SPECIFY_FEATURE_DIRECTORY=specs/001-scanned-form-workflow`,
`SPECIFY_FEATURE_NO_PERSIST=1`, `check-prerequisites.sh --json --require-tasks
--include-tasks` → exit 0, `.specify/extensions.yml` read (no hooks), the three
feature checklists left read-only, and the argument “T086A correction-1 only”
(T086, T086B, T263 and T264 untouched).

### 7.1 Trailing-whitespace normalization of the evidence bytes

`git diff --check 1a141cd..HEAD` reported trailing whitespace in six artifacts.
Only the trailing spaces/tabs were removed; every other byte of those files is
unchanged:

| Artifact | Lines | Bytes after | SHA-256 after |
| --- | --- | --- | --- |
| `device-identity.txt` | 9–10 | 298 | `265c299fe643739f0c63d2fc73f638d221a7aa9322b021641ab53bc0fedbbf56` |
| `failed-run-1/device-identity.txt` | 9–10 | 298 | `265c299fe643739f0c63d2fc73f638d221a7aa9322b021641ab53bc0fedbbf56` |
| `failed-run-1/integration-android-t086a.log` | 2, 99 | 5945 | `cbdb36136c2e7b23c760dddd1e5f0cbad5e6d8b0132e086439603b0c1d678fc0` |
| `integration-android-t086a.log` | 2 | 5751 | `fd64428c9b5ab1c979e52e646c848004bbf6084967f7d0258b8a503e666eb6c0` |
| `runs/run-2-preformat/device-identity.txt` | 9–10 | 298 | `265c299fe643739f0c63d2fc73f638d221a7aa9322b021641ab53bc0fedbbf56` |
| `runs/run-2-preformat/integration-android-t086a.log` | 2 | 5751 | `74e9241b8986dcf1662ea940ead6cd1cc85ad8e52b27f5a6e890838cd2726b01` |

All three runs now carry the same byte-identical device identity (serial, AVD,
build fingerprint, `wm_size` 1080x2400, `wm_density` 420), so the recorded device
fact is preserved; only the padding spaces and the one whitespace-only log line
are gone. No hash row in this report or in the bundle manifests
(`apk-sha256.txt`, `fixture-sha256.txt`, `screenshot-hashes.txt`,
`run-status.txt`, `git-identity.txt`, `markers-integration.txt`,
`marker-sequence.txt`) covers those six files, so no recorded hash needed
updating; the APK `e7ced48b…`, fixture `22c939cc…`, derived fixture `57c1ade1…`
and six screenshot digests are untouched.

The driver's own header line said
`# Usage (repo root): tools/android/t086a_drive_composition.sh`; it now names
the script that exists, `tools/android/t086a_drive_signature.sh`. That is a
comment-only change in host test tooling and changes no driver behavior.

### 7.2 Report accuracy corrections

1. `host_counts.app_field_controls_signature_group` is **3** (the `signature
   control` group in `field_controls_test.dart`), not 4; the 4 came from counting
   the type groups instead of the tests.
2. The clear action's „Ablehnen“ wording is a trash-`IconButton` tooltip plus
   accessibility label (`Icons.delete_outline`), so it is **not** visible as text
   in `signature-sheet.png` (§1.2, §3).
3. `logcat-t086a-markers.log` contains **no** `T086A_` marker — only five
   `ActivityTaskManager` lifecycle lines. The authoritative markers are in
   `markers-integration.txt`, extracted from the integration log (§3).
4. The driver usage line names `tools/android/t086a_drive_signature.sh` (§7.1).
5. The “two documents” independence claim is withdrawn: the
   `keeps two documents and fields independent (no global ink)` test exercises two
   signature fields of **one** document and never opens a second document (§1.3,
   §4).
6. The emulator markers `SAVES=1` / `HEAD_CHANGED=1` are literal label text, not
   measurements. The run proves the head change and the absence of a stored
   revision while the pointer is held; the exact one-save count is host-proven
   (§3).
7. The §4 overlay row now states that the machine-confirmed field is confirmed and
   selected but not moved or resized, and that the real move and corner resize run
   on the seeded signature field, which is itself a confirmed field.

### 7.3 Test hygiene and correction-1 gates

`apps/feldexa_app/test/field_value_sheet_test.dart` had three dead `_pumpSheet`
parameters (`canGoPrevious`, `signatureDrafts`, `signatureResult`) that no test
supplied; they are removed. This is a host widget test that is never compiled
into the emulator journey (`flutter test
integration_test/android_signature_overlay_test.dart`), so it is outside the
emulator-bound byte set. `integration_test/android_signature_overlay_test.dart`
was **not** touched.

```text
format (touched file)   dart format --output=none --set-exit-if-changed → 1 file, 0 changed
focused app 6-file run  signature_png, editor_signature, field_controls, field_value_sheet, editor_composition, review_degraded → 90/90
focused application run apply_signature_test.dart → 10/10 (focused seven-file total 100/100)
app analyze             No issues found!
git diff --check        exit 0
```

`tools/evaluation/validate_report.dart` does not cover this report: it validates
the `YYYY-MM-DD--<slug>.md` class-run template, and this hand-written T086A
report fails it in exactly the same way as its siblings
(e.g. `2026-11-21-emulator-t071a-composition.md`), before and after
correction-1. That gate is therefore `NOT_RUN` (not applicable), not `PASS`.

### 7.4 Emulator binding after correction-1

| Set | `f72e9b9` (candidate) → correction-1 HEAD | Binding |
| --- | --- | --- |
| Production: `apps/feldexa_app/lib/**`, `packages/**/lib/**`, `apps/feldexa_app/assets/**`, all `pubspec*` | identical (no diff) | holds |
| Emulator-bound test: `apps/feldexa_app/integration_test/android_signature_overlay_test.dart` | identical (no diff) | holds |
| Host test: `apps/feldexa_app/test/field_value_sheet_test.dart` | `77cb368bfcdbe9707f8cce96b6298e81c0b8f988ce19d29f6a412b0c472dbf74` → `ff1d401fda7a05d74b571155424bea4e83b76064ac659e947e0f386819ca8a6f` | outside the emulator run |
| Pre-existing dirty file | `apps/feldexa_app/android/gradlew.bat` (CRLF), never staged | unchanged |

The committed `EMULATOR` `PASS` therefore still binds: the APK `e7ced48b…`
built from the identical production bytes, and the only test-side byte change is
a host widget-test helper that the emulator run never compiles. The emulator
evidence itself was not rerun in correction-1.

## 8. Follow-ups (non-blocking code LOWs, not fixed here)

Correction-1 deliberately changes no production code. These LOWs from the two
independent reviews are recorded so they are not lost:

1. **Weak PNG validation.** `SignatureAsset.fromPng`
   (`packages/feldexa_application/lib/src/review/apply_signature.dart`) checks
   only the eight magic bytes plus the caller-supplied `widthPx`/`heightPx`; it
   parses no IHDR/CRC and never cross-checks the declared size against the
   encoded PNG, so a truncated stream with the right magic is accepted.
2. **Mutable asset bytes.** `SignatureAsset.bytes` is a public `final Uint8List`
   (same file). The factory copies the caller buffer once, but any later holder
   can mutate that buffer while `sha256` stays the digest from construction time,
   so the in-memory asset can stop matching its recorded digest.
3. **Stale `_content` across `await`.** `EditorScreenState._saveSignature`
   (`apps/feldexa_app/lib/features/editor/editor_screen.dart`) captures `_content`
   before `await encodeSignaturePng(draft)` and before
   `await store.writeSignature(...)`, then calls `applySignature` with that stale
   snapshot; a revision committed during those awaits would be silently dropped
   because the signature command is built from the pre-await base.
4. **Generic `save003`.** The same function returns
   `FieldValueCommitResult.failed(l10n.save003)` for “not mounted”, “busy”,
   encode failure and commit failure. The signature path cannot distinguish a
   failed asset write, a failed revision write and an unavailable screen, so the
   user message is generic where `SAVE-007`/a signature-specific code would be
   more accurate.
5. **Signed-field mark rect.** `applySignature` stores
   `SignatureMark(rect: field.rect, …)` at capture time, and
   `_translateField` in
   `packages/feldexa_application/lib/src/review/edit_field.dart` (the shared body
   of `moveField` and `resizeField`) copies `content.signatures` unchanged. Moving
   or resizing a signed field therefore leaves the mark rectangle stale. Nothing
   renders `mark.rect` yet, so the defect is latent.
6. **Orphaned assets.** In `_saveSignature`, a successful
   `store.writeSignature` followed by a failed `_commitSnapshot` leaves the asset
   in the encrypted store with no revision referencing it. The startup recovery
   (`apps/feldexa_app/lib/bootstrap/startup_sweep.dart`, native step 2/3
   “unreferenced signatures”) removes it on the next launch, but it persists for
   the rest of the session.
