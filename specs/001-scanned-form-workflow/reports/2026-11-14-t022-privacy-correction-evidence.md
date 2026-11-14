# 2026-11-14 NONE — T022 privacy correction: warnings, unknown fields, and metadata

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `PASS` |
| Task / issue | `T022` / #22 |
| Date / timezone | `2026-11-14 22:50 Europe/Berlin` |
| Revision | base commit `c11af916ce8377f762c48bc65728ccb782b875eb`; follow-up candidate `6daad883d19566110ed32c225eb652bd4d2f9673`; tree `clean`; privacy candidate SHA in the external attestation |
| External attestation | `refs/heads/t022-attestation-v3` and the `worker_done` transport record; candidate SHA, report bytes/SHA-256, and changed-file hashes are recorded outside this report |
| Build identity | pure Dart contract-model package; no APK, Web build, or Android artifact produced |
| Toolchain | Flutter `3.47.7` (framework `abaf9c5237`), Dart `3.13.5` |
| Input | no corpus or fixtures; validator input: `tasks.md` T022, `data-model.md` §3.15 and §6, `contracts/export-plan.md` §2.3, `contracts/ports.md` §1 and §2.5, FR-068, FR-072 |

## 1. Scope

This report covers the open privacy review finding on `ExportPlan.warnings`
and same-schema unknown fields for follow-up candidate
`6daad883d19566110ed32c225eb652bd4d2f9673`. It changes only
`packages/feldexa_export/lib/src/model/export_plan.dart` and its T022 contract
test. `ExportArtifact`, the formula correction, T102, T103, and T106 are
untouched. Main has advanced to `bb779820102f02de48462782a298b290faaa713f`;
integrating that revision is deliberately a separate task and is not claimed
here.

Boundary check:

- **T022** owns the plan contract and must refuse plan metadata that violates
  `contracts/export-plan.md` §2.3. The confirmed bypasses were model-level and
  are closed in T022.
- **T102** remains a schema contract test; it must use plans that pass this
  privacy gate and must not weaken or duplicate the gate.
- **T103** remains the layout producer and must not generate warnings carrying
  locations or identities. Its confirmed field values remain export content.
- **T106** is unaffected; it consumes the artifact lifecycle, not the plan
  privacy gate.

The custom `checklists/precision-testability.md` has 36 intentionally unchecked
reviewer-owned requirements-quality items; its companion assessment directs
`speckit-implement` not to mark them. They were left untouched. This report
claims no checklist or reviewer approval. `.specify/extensions.yml` declares
`hooks: {}`, so no extension hook was registered or executed.

## 2. Revision and build

The original base remains integrated `origin/main`
`c11af916ce8377f762c48bc65728ccb782b875eb`. The follow-up candidate for this
privacy correction is built on `6daad883d19566110ed32c225eb652bd4d2f9673`,
whose report is `specs/001-scanned-form-workflow/reports/2026-11-14-t022-correction-evidence.md`.
This correction does not rewrite that commit or its formula/blocked report.

The privacy candidate SHA, its parent and tree, the bytes and SHA-256 of this
report, and every changed-file hash are in `refs/heads/t022-attestation-v3` and
the `worker_done` transport record. The report cannot contain its own commit SHA
or hash without changing them. `pubspec.lock` is byte-identical and no app, Web,
APK, or Android artifact was built.

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
| 1 | prerequisite check with `SPECIFY_FEATURE_DIRECTORY` (root) | 0 | `.dart_tool/t022-privacy-final-logs/00-prereq.log` | PASS |
| 2 | `flutter pub get --offline` (root) | 0 | `.dart_tool/t022-privacy-final-logs/00b-pub-get.log` | PASS |
| 3 | `dart format --output=none --set-exit-if-changed .` (root) | 0 | `.dart_tool/t022-privacy-final-logs/01-format.log` | PASS |
| 4 | `flutter analyze --no-pub` (root) | 0 | `.dart_tool/t022-privacy-final-logs/02-analyze.log` | PASS |
| 5 | `flutter test --no-pub packages/feldexa_export` (root) | 0 | `.dart_tool/t022-privacy-final-logs/03-test-feldexa_export.log` | PASS |
| 6 | `flutter test --no-pub packages/feldexa_core` (root) | 0 | `.dart_tool/t022-privacy-final-logs/03-test-feldexa_core.log` | PASS |
| 7 | `flutter test --no-pub packages/feldexa_ports` (root) | 0 | `.dart_tool/t022-privacy-final-logs/03-test-feldexa_ports.log` | PASS |
| 8 | `flutter test --no-pub packages/feldexa_testkit` (root) | 0 | `.dart_tool/t022-privacy-final-logs/03-test-feldexa_testkit.log` | PASS |
| 9 | `flutter test --no-pub packages/feldexa_ui` (root) | 0 | `.dart_tool/t022-privacy-final-logs/03-test-feldexa_ui.log` | PASS |
| 10 | `flutter test --no-pub` (`apps/feldexa_app`) | 0 | `.dart_tool/t022-privacy-final-logs/04-app-tests.log` | PASS |
| 11 | `git diff --check` (root) | 0 | `.dart_tool/t022-privacy-final-logs/05-diff-check.log` | PASS |
| 12 | `dart run tools/evaluation/validate_report.dart specs/001-scanned-form-workflow/reports/2026-11-14-t022-privacy-correction-evidence.md` (root) | 0 | console only (not retained) | PASS |
| 13 | `python3 tools/evaluation/check_evidence_docs.py` (root) | 0 | console only (not retained) | PASS |

The export suite has 36 passing tests, including six new privacy cases and the
metadata-privacy case. The full host suite is 589 passing tests:
`feldexa_core` 337, `feldexa_export` 36, `feldexa_ports` 33,
`feldexa_testkit` 110, `feldexa_ui` 17, and the app 56. No test is skipped or
marked expected-failure. The repository-local `tools/gate.sh` was not run: its
browser layer is `SIMULATED` and its Android layer is out of scope for a `NONE`
model task.

## 5. Results

### 5.1 Confirmed bypasses and reproduction

The review finding was reproduced before the fix. The follow-up candidate
accepted `ExportPlan.warnings: ['https://example.com/private']`,
`warnings: ['<absolute-path>']`, device and user strings in warnings, and
unknown fields such as `{'externalUri': 'https://example.com/private'}` or
`{'note': '<absolute-path>'}`; recursive checks looked only at exact map keys.
A pre-fix red run recorded five failing privacy tests in
`.dart_tool/t022-corr-logs/02-privacy-reproduce.log`.

### 5.2 Corrected plan privacy gate

The gate now applies to the plan content classes that are not otherwise
constrained by the schema:

- **`ExportPlan.warnings`**: each warning string is checked for absolute paths,
  URIs, device names, user identifiers, and user handles.
- **Unknown fields**: all nested keys and string values are checked at every
  modeled level, including unknown fields on `ExportPlan`, `ExportFont`,
  `ExportPlanInfo`, `ExportPage`, `ExportCtm`, every `ExportOp`, and the core
  `PageGeometry`/`Rect` extension maps.
- **Known metadata strings**: `font.family`, `font.regularAsset`,
  `font.boldAsset`, `font.metricsVersion`, each `fieldId`, and each `assetId`
  are checked because they are plan metadata, not user content.
- **Not scanned**: confirmed field `lines` are the user's export content; they
  remain exportable. §2.3's location/identity list is enforced on plan metadata,
  not by refusing the document the user asked to export.

The check refuses:

- URI schemes, including `file:`, `content:`, `http:`, `mailto:`, `package:`,
  and scheme tokens embedded after separators;
- Unix absolute paths, Windows drive paths, UNC paths, `~` paths, and embedded
  path tokens after `:`, `=`, `,`, `;`, `<`, `>`, and `|`;
- email addresses and at-sign user handles;
- `user`/`owner`/`author`/`userId`/`email`/`device`/`deviceName`/
  `buildFingerprint`/`serial`/`hostname` and related identity keys;
- project device patterns (`Pixel`, `Samsung`, `Galaxy`, `SM-…`, `Exynos`,
  `emulator-N`).

### 5.3 Preserved same-schema extensions

The fix does not reject unknown fields as a class. Relative values, ordinary
labels, numeric/bool extensions, nested maps, and relative path-like metadata
remain retained. The regression tests cover:

```text
futureRoot: {nested: 1}
futureLabel: Name
futureRelative: assets/fonts/NotoSans-Regular.ttf
futureNote: Hinweis: assets/fonts/NotoSans-Regular.ttf
future/label: Name
Feld A / B: Name
uri: relative-token
filepath: assets/fonts/NotoSans-Regular.ttf
```

The same tests reject `externalUri`, absolute paths, `deviceName`, `userId`,
`user`, `device`, path-like or URI-like keys, nested URI values, and private
values on `Rect`, `PageGeometry`, `ExportFont`, `ExportPlanInfo`, and
`ExportCtm` extensions.

### 5.4 Limitations of identity detection

Device names and user identifiers are open-ended strings. The gate combines
schema-key denial with concrete patterns for the project profiles and common
identity forms; it cannot prove that an arbitrary opaque string such as
`note: "my phone"` is or is not a device name. Such values remain possible in a
free-form extension, and a plan warning that is only a person's name is not
detectable without a closed warning grammar. This is recorded as a residual
limitation rather than hidden; a future schema change should narrow `warnings`
and free-form extensions if the owner wants a closed allowlist.

## 6. Performance

No performance claim.

## 7. Limitations

- This is host-VM and static-analysis evidence only (`NONE`). It cannot prove
  Android export, PDFBox behavior, preview lifecycle, or acceptance evidence.
- Main `bb779820102f02de48462782a298b290faaa713f` is not integrated; this report
  is bound to the T022 follow-up branch, not to main.
- T102, T103, and T106 remain unimplemented; their boundary obligations are
  documented in §1 and are not claimed as tested.
- The privacy gate is pattern/key based as described in §5.4; it does not claim
  a general device-name or person-name classifier.
- The pre-existing host-SDK read-only condition was handled with the
  git-ignored shim; no toolchain installation or network access changed the
  candidate.

## 8. Artifacts

This report omits its own row by construction; its bytes and SHA-256 are in the
external attestation. Logs are git-ignored, regenerable support artifacts.

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Corrected plan model | `packages/feldexa_export/lib/src/model/export_plan.dart` | 62088 | `93617e47458dec604050587db557cdef41d0f5434ff5442f0049f49300defa0a` |
| Corrected contract tests | `packages/feldexa_export/test/export_contract_models_test.dart` | 30009 | `9c010086add118e23ca8a01a1040f8b08fbb04d6fdc7ae75ed2a4baac012590e` |
| Evidence index | `specs/001-scanned-form-workflow/reports/README.md` | 19333 | `1aa020ff8e0d3ca24332c57366ecc95ad24b9c255c9167faf31128ce3295d849` |
| Pre-fix reproduction log | `.dart_tool/t022-corr-logs/02-privacy-reproduce.log` | 11354 | `ef1cf06160daff92b71a222b1ef82cacabfcb7854a955079dafb7451450a1da4` |
| Prerequisite log | `.dart_tool/t022-privacy-final-logs/00-prereq.log` | 192 | `17be56fad8197482d23b193a1fa803702564ed4bfd9bb9ca54e287006359aec8` |
| Pub-get log | `.dart_tool/t022-privacy-final-logs/00b-pub-get.log` | 221 | `bf43ac2d8521495d0a1eff3ece869a5550c2a9554d10b078ce5c40b5e84985cc` |
| Format log | `.dart_tool/t022-privacy-final-logs/01-format.log` | 48 | `fb707ee2f63e6874e2ad20fecd6629b06ca7d48d9b70ddbf75dfa4ba10dff502` |
| Analyze log | `.dart_tool/t022-privacy-final-logs/02-analyze.log` | 96 | `5be0250d2e846a4123841153d75fa3bf1ee00a8ab2613419a78dcafe6a631f86` |
| Core test log | `.dart_tool/t022-privacy-final-logs/03-test-feldexa_core.log` | 61313 | `c33747c6f994aeb8a492540af3ed17db6107513769d5031de38ab0726a36a6a8` |
| Export test log | `.dart_tool/t022-privacy-final-logs/03-test-feldexa_export.log` | 7341 | `ab453c6facc162072808077db92c348fd7aecae98e88ef0eef2fa56d4fd85f1e` |
| Ports test log | `.dart_tool/t022-privacy-final-logs/03-test-feldexa_ports.log` | 6210 | `069561d689830086fad39201dfebf32be56ca00017f1f55330707a88be53b3d4` |
| Testkit test log | `.dart_tool/t022-privacy-final-logs/03-test-feldexa_testkit.log` | 20441 | `c15d1c8a8084170bd803981f46ea9e91f4b0600f9a837b4c511fc286484b0e8e` |
| UI test log | `.dart_tool/t022-privacy-final-logs/03-test-feldexa_ui.log` | 1850 | `63c1bed2d9549e4500d3a82d801ef5a15cfad74443892e55d47a94440ae565ea` |
| App test log | `.dart_tool/t022-privacy-final-logs/04-app-tests.log` | 10789 | `77fcd24bbb9a6231173bab153e8bec28cf1e344e425e3164cc0ad6716449915e` |
| Diff-check log | `.dart_tool/t022-privacy-final-logs/05-diff-check.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |

## 9. Reproducibility

1. Check out follow-up candidate
   `6daad883d19566110ed32c225eb652bd4d2f9673`.
2. Add the privacy regression tests; the intentional red run must report five
   failures as recorded in `.dart_tool/t022-corr-logs/02-privacy-reproduce.log`.
3. Apply the privacy gate and run `flutter pub get --offline`; `pubspec.lock`
   must stay byte-identical.
4. Run `dart format --output=none --set-exit-if-changed .`.
5. Run `flutter analyze --no-pub`; expect `No issues found!`.
6. Run `flutter test --no-pub packages/feldexa_export`; expect 36 passing tests.
7. Run the other host suites: `feldexa_core` 337, `feldexa_ports` 33,
   `feldexa_testkit` 110, and `feldexa_ui` 17 passing tests.
8. From `apps/feldexa_app`, run `flutter test --no-pub`; expect 56 passing
   tests.

## 10. External attestation

The privacy candidate SHA, candidate parent and tree, this report's bytes and
SHA-256, every changed-file hash, the reproduction log hash, and the toolchain
record are stored in the local Git ref `refs/heads/t022-attestation-v3` and in
the `worker_done` transport record. The ref is not pushed and is not part of
the candidate commit. Inspect it locally with
`git show refs/heads/t022-attestation-v3`.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
