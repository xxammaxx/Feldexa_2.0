# 2026-11-14 NONE — T022 correction: normative formulas and artifactless blocking

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `PASS` |
| Task / issue | `T022` / #22 |
| Date / timezone | `2026-11-14 22:21 Europe/Berlin` |
| Revision | base commit `c11af916ce8377f762c48bc65728ccb782b875eb`; superseded candidate `951629f3edf3ba5fae7ecdf248ddf4059f925853`; tree `clean`; correction candidate SHA in the external attestation |
| External attestation | `refs/heads/t022-attestation-v2` and the `worker_done` transport record; correction candidate SHA, report bytes/SHA-256, and changed-file hashes are recorded outside this report |
| Build identity | pure Dart contract-model package; no APK, Web build, or Android artifact produced |
| Toolchain | Flutter `3.47.7` (framework `abaf9c5237`), Dart `3.13.5` |
| Input | no corpus or fixtures; validator input: `tasks.md` T022, `data-model.md` §3.15, `contracts/export-plan.md` §2.2, `contracts/ports.md` §1 and §2.5, FR-068, FR-072 |

## 1. Scope

This correction covers **T022 / issue #22 only**. It follows the requirement
review of candidate `951629f3edf3ba5fae7ecdf248ddf4059f925853` and changes only
`packages/feldexa_export/lib/src/model/export_plan.dart`,
`packages/feldexa_export/lib/src/model/export_artifact.dart`, and their two
T022 test files. T102 (schema contract test), T103 (layout builder), and T106
(preview lifecycle) remain untouched; this report does not implement or
pre-approve them.

Boundary check:

- **T022** owns the export contract models and the artifact state machine. The
  model must therefore reject a plan value that contradicts the normative
  `contracts/export-plan.md` §2.2 formula and must not invent an artifact for
  the artifactless `blocked` outcome.
- **T102** is a schema contract test over the T022 models. It does not own the
  formulas or the state machine; it must use formula-correct values. Because the
  published §2 example conflicts with §2.2 (see §5.3), T102 cannot copy the
  example's `8.1` baseline unchanged.
- **T103** computes text layout and clip detection and builds the T022 plan.
  It remains the producer of the normalized font, line-height, baseline, inset,
  and stroke values; T022 is the acceptance boundary that refuses a
  nonconforming plan before an applier sees it.
- **T106** consumes the artifact lifecycle for the ephemeral preview. A blocked
  validation produces no `ExportArtifact`; T106 must show the German blocking
  result from `ExportValidation` and must not start preview cleanup for an
  artifact that was never created.

The custom `checklists/precision-testability.md` has 36 intentionally unchecked
reviewer-owned requirements-quality items; its companion assessment directs
`speckit-implement` not to mark them. They were left untouched. This report
claims no checklist or reviewer approval. `.specify/extensions.yml` declares
`hooks: {}`, so no extension hook was registered or executed.

## 2. Revision and build

The original base remains integrated `origin/main`
`c11af916ce8377f762c48bc65728ccb782b875eb`. The superseded T022 candidate is
`951629f3edf3ba5fae7ecdf248ddf4059f925853`, whose report is
`specs/001-scanned-form-workflow/reports/2026-11-14-t022-evidence.md`. This
correction is a new commit on top of that candidate; it does not rewrite the
superseded commit or its report.

The correction candidate SHA, its parent and tree, the bytes and SHA-256 of
this report, and every changed-file hash are in
`refs/heads/t022-attestation-v2` and the `worker_done` transport record. The
report cannot contain its own commit SHA or hash without changing them. No app,
Web, APK, or Android artifact was built, and `pubspec.lock` is unchanged.

## 3. Environment

Host VM and static analysis only, `NONE` evidence. The installed SDK home is
read-only in this worker sandbox, so the git-ignored local shim at
`.dart_tool/t022-tooling/` supplies a writable `HOME`, `FLUTTER_ROOT`, and
`PUB_CACHE` while delegating to the installed Flutter snapshot. No source file,
dependency version, SDK content, or lockfile byte changed.

```text
Flutter 3.47.7 stable, framework abaf9c5237, engine content hash d8a2d6c768c334d53e16277f837970ffa1e2de81
Dart 3.13.5 stable, linux_x64
Android SDK: not used
```

No Android runtime and no browser run was performed for this task.

## 4. Checks

All commands ran from the repository root unless the working directory is
stated. Exit code 0 is a pass. Logs are git-ignored, regenerable support
artifacts; the candidate does not contain them.

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | prerequisite check with `SPECIFY_FEATURE_DIRECTORY` (root) | 0 | `.dart_tool/t022-corr-final-logs/00-prereq.log` | PASS |
| 2 | `flutter pub get --offline` (root) | 0 | `.dart_tool/t022-corr-final-logs/00b-pub-get.log` | PASS |
| 3 | `dart format --output=none --set-exit-if-changed .` (root) | 0 | `.dart_tool/t022-corr-final-logs/01-format.log` | PASS |
| 4 | `flutter analyze --no-pub` (root) | 0 | `.dart_tool/t022-corr-final-logs/02-analyze.log` | PASS |
| 5 | `flutter test --no-pub packages/feldexa_export` (root) | 0 | `.dart_tool/t022-corr-final-logs/03-test-feldexa_export.log` | PASS |
| 6 | `flutter test --no-pub packages/feldexa_core` (root) | 0 | `.dart_tool/t022-corr-final-logs/03-test-feldexa_core.log` | PASS |
| 7 | `flutter test --no-pub packages/feldexa_ports` (root) | 0 | `.dart_tool/t022-corr-final-logs/03-test-feldexa_ports.log` | PASS |
| 8 | `flutter test --no-pub packages/feldexa_testkit` (root) | 0 | `.dart_tool/t022-corr-final-logs/03-test-feldexa_testkit.log` | PASS |
| 9 | `flutter test --no-pub packages/feldexa_ui` (root) | 0 | `.dart_tool/t022-corr-final-logs/03-test-feldexa_ui.log` | PASS |
| 10 | `flutter test --no-pub` (`apps/feldexa_app`) | 0 | `.dart_tool/t022-corr-final-logs/04-app-tests.log` | PASS |
| 11 | `git diff --check` (root) | 0 | `.dart_tool/t022-corr-final-logs/05-diff-check.log` | PASS |
| 12 | `dart run tools/evaluation/validate_report.dart specs/001-scanned-form-workflow/reports/2026-11-14-t022-correction-evidence.md` (root) | 0 | console only (not retained) | PASS |
| 13 | `python3 tools/evaluation/check_evidence_docs.py` (root) | 0 | console only (not retained) | PASS |

The export suite now has 29 passing tests (up from 25), including the four new
formula cases and the artifactless-blocking cases. The full host suite is 582
passing tests: `feldexa_core` 337, `feldexa_export` 29, `feldexa_ports` 33,
`feldexa_testkit` 110, `feldexa_ui` 17, and the app 56. No test is skipped or
marked expected-failure. The repository-local `tools/gate.sh` was not run:
its browser layer is `SIMULATED` and its Android layer is out of scope for a
`NONE` model task.

## 5. Results

### 5.1 Confirmed formula defect and correction

The review finding was reproduced before the fix. The pre-fix candidate
accepted `fontSizePt: 8.6` for a 14.5 pt field, `lineHeightPt: 10.43` for an
8.7 pt font, and checkbox `insetPt: 1.4`/`strokeWidthPt: 0.9` for a 10 × 10 pt
box. The intentionally red run recorded five failures in
`.dart_tool/t022-corr-logs/01-reproduce.log`; three are the formula defects.

The corrected `ExportTextOp` now requires:

- `fontSizePt == round(clamp(0.6 × rect.height, 7.0, 12.0), 0.1)`;
- `lineHeightPt == round(1.2 × fontSizePt, 0.01)`;
- `baselineFromTopPt == 1.5 + 0.8 × fontSizePt`, still bounded by
  `rect.height`;
- the existing `#000000`, non-empty line, no trailing-space, no-materialized-
  newline, and `overflow == false` rules.

The corrected `ExportCheckboxOp` now requires:

- `insetPt == clamp(0.15 × min(width, height), 0.5, 3.0)`;
- `strokeWidthPt == round(clamp(0.08 × min(width, height), 0.6, 1.4), 0.1)`.

`ExportTextOp` is the acceptance boundary, not a second layout engine: T103
still computes the normalized values and remains responsible for line breaking,
glyph metrics, and clip detection. T102 must construct formula-correct values.

### 5.2 Confirmed blocked-state defect and correction

The review finding was reproduced. The pre-fix candidate allowed
`ExportArtifact.start(...).fail(failureCode: 'EXP-001')` and exposed
`isBlocked`; that created an `ExportArtifact` for an outcome that
`data-model.md` §3.15 explicitly calls artifactless (`blocked (German message;
no artifact)`). The same red run recorded the artifactless-blocking failure.

The correction:

- removes `ExportArtifact.isBlocked` and the public blocked-code set;
- refuses `ExportArtifact.fail` from `validating` with `StateError`;
- allows `fail` only from `rendering` or `verifying`;
- refuses `EXP-001`, `EXP-003`, `EXP-004`, `EXP-005`, and `EXP-006` as failed
  artifact codes with `ArgumentError`;
- re-applies both rules in `ExportArtifact.fromJson`, so a hand-written or
  legacy `failed` record with a blocking code is refused;
- leaves blocking exclusively in `ExportValidation`, which already carries the
  seven blocking codes and the German catalog mapping.

`EXP-002` and `SAVE-001` remain valid `failed` codes from `rendering` or
`verifying`, matching the diagram's I/O, key, space, and verification failure
paths. No additional persisted state was invented.

### 5.3 The documented example contradiction

`contracts/export-plan.md` §2.2 is explicit normative text:
`baselineFromTopPt = 1.5 + 0.8 × fontSizePt`. For its own example values
(`fontSizePt: 8.7`), that is `8.46`. The §2 JSON example still says `8.1`.
The correction does **not** hide or silently resolve this:

- the normative §2.2 formula is enforced; `8.1` is refused;
- a regression test pins `8.46` as accepted and the stale `8.1` example as
  rejected;
- a second test feeds a complete plan JSON with the stale example baseline and
  requires `FormatException`;
- this report records the decision and the documentation defect explicitly.

The contract example remains a live documentation defect. If the owner decides
that the example is authoritative, §2.2 must be changed; this task does not
amend the contract and does not invent an exception that accepts both values.
T102 must not copy the stale example unchanged.

### 5.4 State machine now

```text
validating --startRendering--> rendering
rendering  --startVerification--> verifying
rendering/verifying --fail (EXP-002, SAVE-001, ...)--> failed
verifying  --succeed (all checks pass)--> succeeded
succeeded  --markDeleted--> deleted
```

`validating` has no failure transition and no artifact record for blocking.
`failed` and `deleted` are terminal; `succeeded` can only be entered from
`verifying` with an all-passing `ArtifactVerification`.

## 6. Performance

No performance claim.

## 7. Limitations

- This is host-VM and static-analysis evidence only (`NONE`). It cannot prove
  PDFBox flattening, Android export, preview lifecycle, save/share/print,
  storage-pressure behavior, or acceptance evidence.
- T102, T103, and T106 remain unimplemented. Their boundary obligations are
  documented in §1; this report does not claim their tests or behavior.
- The formula check uses the model's existing `1e-6` geometry tolerance. It is
  not a pixel/PDFBox tolerance and does not validate rendered output.
- The §2 example conflict is explicitly decided in favor of the normative
  §2.2 rule, but the documentation still needs an owner correction. No contract
  file was changed by this task.
- The pre-existing host-SDK read-only condition was handled with the
  git-ignored shim; no toolchain installation or network access changed the
  candidate.

## 8. Artifacts

This report omits its own row by construction; its bytes and SHA-256 are in the
external attestation. Logs are git-ignored, regenerable support artifacts.

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Corrected plan model | `packages/feldexa_export/lib/src/model/export_plan.dart` | 56602 | `2e27b9341be40f4d8dcd522280f94a40de0466e0d7c96c177d501d55cff0631c` |
| Corrected artifact model | `packages/feldexa_export/lib/src/model/export_artifact.dart` | 23773 | `24cc89fe4ee1de93b56d9c21daa7a76c826f9272f84685b9c567ee52f473227b` |
| Corrected contract tests | `packages/feldexa_export/test/export_contract_models_test.dart` | 23174 | `dc90600f3f40af76edc942f320302d2e148615193008a7a5596f7288bc1f981e` |
| Corrected artifact tests | `packages/feldexa_export/test/export_artifact_test.dart` | 14348 | `4dd7442dc63ea3a75aa83111405d63aada678e4db246e496cd951dfd79cc202b` |
| Evidence index | `specs/001-scanned-form-workflow/reports/README.md` | 19007 | `edf07d27062cd8578e31eb5fd9e675d6f9af49252df1e7fb4f3955dba6e39ba6` |
| Pre-fix reproduction log | `.dart_tool/t022-corr-logs/01-reproduce.log` | 10587 | `6cf49071f71d0819cede1227f94d44779d4f739956e7244ceb3876736c68ef54` |
| Prerequisite log | `.dart_tool/t022-corr-final-logs/00-prereq.log` | 192 | `17be56fad8197482d23b193a1fa803702564ed4bfd9bb9ca54e287006359aec8` |
| Pub-get log | `.dart_tool/t022-corr-final-logs/00b-pub-get.log` | 221 | `bf43ac2d8521495d0a1eff3ece869a5550c2a9554d10b078ce5c40b5e84985cc` |
| Format log | `.dart_tool/t022-corr-final-logs/01-format.log` | 48 | `73b2d8ee89e89dd153c1990235ecac618c272b8be9fd710794ffcce7b5a83f95` |
| Analyze log | `.dart_tool/t022-corr-final-logs/02-analyze.log` | 96 | `36252ac2d2e3ac8b2233441469e947f039636290dcfaf207d7034635adfeaa02` |
| Core test log | `.dart_tool/t022-corr-final-logs/03-test-feldexa_core.log` | 60951 | `f7bb6bbde777cbf3e98f0a47405f11a80bc724827ca6526e8e8398fb9043d6de` |
| Export test log | `.dart_tool/t022-corr-final-logs/03-test-feldexa_export.log` | 5876 | `c7e1a1d93368ef0ab8d5ace38435adf5b79045fcfaf4510e85563cf51bf5dfd6` |
| Ports test log | `.dart_tool/t022-corr-final-logs/03-test-feldexa_ports.log` | 6274 | `d1b92942beb889983266e03caa78567e1aafbcdba5ff1de52a9b7876b6fcfe2e` |
| Testkit test log | `.dart_tool/t022-corr-final-logs/03-test-feldexa_testkit.log` | 20742 | `a026ce00428dd1e1da38b94cda7794a1f010a7558729e8ceeb9418cc323050f8` |
| UI test log | `.dart_tool/t022-corr-final-logs/03-test-feldexa_ui.log` | 1850 | `1a9b8358ef56f6a254c0bdb896041959c97f82310794727fd792d738da6034b1` |
| App test log | `.dart_tool/t022-corr-final-logs/04-app-tests.log` | 10941 | `d5091e8e9a0990b1e863833eeed10d27e884743365e0bf4c465220534498efd5` |
| Diff-check log | `.dart_tool/t022-corr-final-logs/05-diff-check.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |

## 9. Reproducibility

1. Check out the superseded candidate
   `951629f3edf3ba5fae7ecdf248ddf4059f925853`.
2. Add the formula and artifactless-blocking regression tests; the intentional
   red run must report five failures as recorded in
   `.dart_tool/t022-corr-logs/01-reproduce.log`.
3. Apply the correction and run `flutter pub get --offline`; `pubspec.lock`
   must stay byte-identical.
4. Run `dart format --output=none --set-exit-if-changed .`.
5. Run `flutter analyze --no-pub`; expect `No issues found!`.
6. Run `flutter test --no-pub packages/feldexa_export`; expect 29 passing tests.
7. Run the other host suites: `feldexa_core` 337, `feldexa_ports` 33,
   `feldexa_testkit` 110, and `feldexa_ui` 17 passing tests.
8. From `apps/feldexa_app`, run `flutter test --no-pub`; expect 56 passing
   tests.

## 10. External attestation

The correction candidate SHA, candidate parent and tree, this report's bytes and
SHA-256, every changed-file hash, the reproduction log hash, and the toolchain
record are stored in the local Git ref `refs/heads/t022-attestation-v2` and in
the `worker_done` transport record. The ref is not pushed and is not part of
the candidate commit. Inspect it locally with
`git show refs/heads/t022-attestation-v2`.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
