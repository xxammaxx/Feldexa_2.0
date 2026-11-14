# T013 Evidence Review Correction — SourceIntegrity Evidence and the ExportValidation Boundary

| Field | Value |
| --- | --- |
| Repository | `xxammaxx/Feldexa_2.0` |
| Task / issue | T013 / #13 |
| Evidence class | `NONE` (static analysis and host-VM tests only) |
| Result | `PASS` for the correction; the local gate is qualified because future test layers are absent |
| Date / timezone | 2026-11-14 (Europe/Berlin) |
| Base revision | `7557991e51cc3a795289706fe330e97cb4ffea0d` (`origin/main`) |
| Superseded candidate | `1ad5382d9ca0ec625c7f249a4f764edbb5e51331` (T013 implementation reviewed against `contracts/ports.md` §1) |
| Worktree branch | `xxammaxx/feldexa-t013-ports` |
| Worktree | isolated Orca worktree `feldexa-t013-ports` |
| Candidate revision | the local commit on `xxammaxx/feldexa-t013-ports` that contains this report; the exact SHA is recorded in `worker_done` and is reproducible with `git rev-parse HEAD` |
| Toolchain | Flutter `3.47.7`, Dart `3.13.5` |
| Runtime evidence | none; no `SIMULATED`, `EMULATOR`, or `DEVICE` T013 result is claimed |

## 0. Review finding and scope

The requirement review of candidate `1ad5382` reported that
`contracts/ports.md` §1 line 12 requires `CapabilityEvidence` for every result
that can influence acceptance, while:

1. `SourceIntegrity` returned by `DocumentImportPort.verifySource` carries no
   evidence;
2. `PdfExportPort.validate` returns the canonical T022 `ExportValidation`,
   which carries no evidence.

This correction audits the normative contract, the existing
`CapabilityDescriptor`/result boundaries, and canonical type ownership before
changing anything. It reproduces the confirmed gap by requiring and asserting
the evidence field on the T013-owned result (the constructor did not accept it
before), fixes that type, and records the `ExportValidation` issue as a genuine
contract collision instead of inventing a duplicate type or changing another
task's canonical model.

No other task is selected, implemented, or marked complete. `tasks.md` already
marks T013 `[x]`; its line is unchanged.

## 1. Normative audit

`contracts/ports.md` line 12 is normative: “Every result that can influence
acceptance carries `CapabilityEvidence`.” The contract's §2 snippets attach
evidence to some result types and not to others; this table separates the
contract's explicit evidence-bearing results from projections, content, and
state reports that the contract does not label.

| Result type | Evidence in §2 | Can influence acceptance? | Action |
| --- | --- | --- | --- |
| `ImportedSource` | yes | yes (import/source retention) | unchanged |
| `SourceIntegrity` | **no** | yes (FR-095/FR-096 source retention) | **fixed** (T013-owned) |
| `RasterImage` | yes | yes (page rendering) | unchanged |
| `OcrBlock` / `OcrLine` | no | content output; recognition envelope carries `evidenceClass` | unchanged |
| `StoreStatus` | yes | yes (key/capacity acceptance) | unchanged |
| `StoredMeta` | no | list projection; not a capability result | unchanged |
| `LoadedDocument` | yes | yes (decrypted load) | unchanged |
| `LoadedTemplate` | yes | yes (decrypted template load) | unchanged |
| `RecoveryStamp` | no | durable-state report, not a capability result | unchanged |
| `ExportValidation` | **no** | preflight warnings; see §3 collision | **documented** |
| `ExportResult` | yes | yes (artifact acceptance) | unchanged |
| `DeliveryOutcome` | yes | yes (hand-off acceptance) | unchanged |
| raw bytes, `void`, primitive results | no | not acceptance results | unchanged |

The audit does not expand evidence to `StoredMeta`, `RecoveryStamp`, or OCR
content: the contract does not attach evidence to those types, and adding it
would be a new contract requirement rather than a correction of the review
finding. The two reviewed gaps are handled below.

## 2. Confirmed gap: `SourceIntegrity` now carries evidence

`DocumentImportPort.verifySource` returns a `SourceIntegrity` result that can
support the source-retention guarantees of FR-095/FR-096. A simulated Web
verification could otherwise be shown as a real source check. `SourceIntegrity`
is owned by T013 under `contracts/ports.md` §1 and §2.1, so this is a
T013-scoped correction with no canonical-type collision.

The fix is minimal:

- `packages/feldexa_ports/lib/src/dto/import_dto.dart` adds a required
  `CapabilityEvidence evidence` field to `SourceIntegrity`.
- The §2.1 contract snippet now shows the same field and cites §1; the
  accompanying sentence records that this is a clarification of the existing
  evidence rule, not a new type or requirement.
- No other DTO changed, and no canonical core/export/T014 type was duplicated.

Regression coverage:

- `dto_contract_test.dart` constructs a simulated and an Android
  `SourceIntegrity` and asserts `evidenceClass`/`simulated`; the invalid-value
  tests also pass the required evidence.
- `ports_contract_test.dart` asserts that the fake `verifySource` result carries
  Android (`NONE`) evidence.
- `type_ownership_test.dart` assigns `SourceIntegrity.evidence` to the canonical
  `ports.CapabilityEvidence` type.

## 3. Genuine contract collision: `PdfExportPort.validate` and `ExportValidation`

The second finding cannot be fixed inside T013 without violating another
normative boundary:

1. `contracts/ports.md` §2.5 explicitly defines
   `Future<ExportValidation> validate(ExportPlan plan)`.
2. `ExportValidation` is a canonical `feldexa_export` type owned by T022
   (`contracts/ports.md` §1 type ownership; `data-model.md` §3.15;
   `contracts/export-plan.md` line 5). It has `warnings` and `validatedAt`, but
   no evidence field.
3. `CapabilityEvidence` is owned by T014 in `feldexa_ports`
   (`lib/src/evidence.dart`). `contracts/ports.md` §1 and
   `contracts/export-plan.md` line 5 require that `feldexa_export` must not
   import `feldexa_ports`; the dependency direction is one-way
   (`plan.md` §Project Structure: core → export → ports).
4. Adding `CapabilityEvidence` to `ExportValidation` would invert that
   dependency and make `feldexa_export` depend on `feldexa_ports`.
5. Declaring a second `ExportValidation` (or a second evidence vocabulary) in
   `feldexa_ports` would duplicate a canonical T022 type and violate the
   Foundational Type Ownership table.

A T013-owned wrapper around `ExportValidation` would avoid the duplicate, but
it would change the explicit §2.5 return type and add a result type that §2.10
does not declare. That is a contract change, not a correction of the reviewed
implementation, so it was not invented here.

**Current boundary:** `validate` is the preflight that returns blocking
warnings before any file is written; the acceptance-relevant export result is
`ExportResult`, which does carry `CapabilityEvidence`. If the owner wants
`validate` itself labelled, the concrete options are:

| Option | Owner | Effect |
| --- | --- | --- |
| Add an `evidenceClass` string token to `ExportValidation` | T022 | Mirrors `ExportPlan.evidenceClass`; keeps `feldexa_export` free of ports types |
| Change §2.5 to return a T013-owned result carrying `ExportValidation` + `CapabilityEvidence` | contract owner + T013 | Changes the explicit signature and adds a result DTO |
| Scope §1 explicitly so preflight `validate` is not acceptance-relevant and relies on `ExportResult` evidence | contract owner | No type change; documents the intended boundary |

This report does not choose among them. The collision is recorded for the
quality review and a future owner/T022 decision.

Regression coverage documents the boundary without pretending to fix it:

- `type_ownership_test.dart` asserts that `ExportValidation` remains declared
  in `feldexa_export`, that the export source contains no `CapabilityEvidence`
  or `package:feldexa_ports`, and that `ExportResult.evidence` is a canonical
  ports `CapabilityEvidence`.
- `ports_contract_test.dart` asserts that `PdfExportPort.validate` returns the
  canonical `ExportValidation` and that `export` returns `ExportResult` with
  evidence.
- The existing dependency-direction test still proves that `feldexa_export`
  never imports `feldexa_ports`.

## 4. What changed

All paths are relative to the repository root. The report's own row is omitted
by construction.

| File | Change | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `packages/feldexa_ports/lib/src/dto/import_dto.dart` | `SourceIntegrity` gains required `CapabilityEvidence evidence`; docs cite §1 and FR-095/FR-096 | 8557 | `f9fb7c104c70b62061bd1d4a725bf0ad80457c7621ffcf31a62c419214d32fe4` |
| `packages/feldexa_ports/test/dto_contract_test.dart` | evidence regression and updated `SourceIntegrity` constructions | 27218 | `6fd8fa87c3ae83f4e589feda277ba605a9f9f69dd269c1f93f44a3a3ab24d1bc` |
| `packages/feldexa_ports/test/ports_contract_test.dart` | `verifySource` evidence and export-result evidence assertions | 22269 | `4cccc6d7c93fdd48303d6e64baea9cb3fdbe64d7adb6befd609e52e4c333a0ec` |
| `packages/feldexa_ports/test/type_ownership_test.dart` | `SourceIntegrity` evidence identity and `ExportValidation` boundary regression | 12003 | `84e98a89e4f1d44a8cc14cab5d5c6cb9e26c746336ae75077de91c14ee6feca1` |
| `specs/001-scanned-form-workflow/contracts/ports.md` | §2.1 snippet shows the §1-required evidence field and the clarification note | 21069 | `038bef0b0e43733c7244b0f6e93439bbc1ffe5fb3a656956b113b5493f988895` |
| `specs/001-scanned-form-workflow/reports/2026-11-14-t013-evidence.md` | correction banner; earlier results are not re-scored | 26029 | `fa3f45b34a9977f96b3e75853295069cbf6377bf68b3bda0cda783ac584ead9a` |
| `specs/001-scanned-form-workflow/reports/README.md` | index row for this correction | 20573 | `6bc0fa0fbf9993d05bc2cf5e2d5fe4e874a4b1e505f6b5104e6733edd610ff79` |

`pubspec.lock` remains byte-identical
(`00a5b9fbc59e6038a1a93fd4cd2c24244f63dffa99b0b44a12f7e8f0d1a21163`,
22638 bytes). No canonical core/export/T014 type changed, and no second
`CapabilityEvidence`, `ExportValidation`, or export result type was declared.
The pre-existing `gradlew.bat` line-ending artifact remains uncommitted and
unstaged (§9).

## 5. Tests and results

| Suite | Tests | Result | What changed |
| --- | ---: | --- | --- |
| `test/descriptor_test.dart` | 12 | PASS | unchanged |
| `test/dto_contract_test.dart` | 35 | PASS | +1 evidence regression; existing `SourceIntegrity` cases now require evidence |
| `test/ports_contract_test.dart` | 16 | PASS | `verifySource` and `ExportResult` evidence assertions |
| `test/type_ownership_test.dart` | 8 | PASS | +1 `ExportValidation` boundary regression; `SourceIntegrity` evidence identity |
| `test/errors_test.dart` (T014, unchanged) | 17 | PASS | existing error taxonomy |
| `test/evidence_test.dart` (T014, unchanged) | 16 | PASS | existing evidence vocabulary |
| **`packages/feldexa_ports` total** | **104** | **PASS** | 102 before the correction; two new regressions |

Affected adjacent suites remain green: `feldexa_core` 461, `feldexa_export` 36,
and `feldexa_testkit` 110. The export suite is unchanged because the T022 model
was deliberately not modified.

## 6. Verification commands and results

All commands ran in the repository root with the copied toolchain and
`PUB_CACHE=.dart_tool/pub-cache`. Exit code 0 is a pass.

| # | Command | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `flutter pub get --offline` | 0 | `.dart_tool/gate-t013-review/01-pub-get.log` | PASS; lockfile byte-identical |
| 2 | `dart format --output=none --set-exit-if-changed .` | 0 | `.dart_tool/gate-t013-review/02-format.log` | PASS, 101 files, 0 changed |
| 3 | `flutter analyze --no-pub` | 0 | `.dart_tool/gate-t013-review/03-analyze.log` | PASS, `No issues found!` |
| 4 | `flutter test --no-pub packages/feldexa_ports` | 0 | `.dart_tool/gate-t013-review/05-shared-feldexa_ports.log` | PASS, 104/104 |
| 5 | `flutter test --no-pub packages/feldexa_core` | 0 | `.dart_tool/gate-t013-review/05-shared-feldexa_core.log` | PASS, 461/461 |
| 6 | `flutter test --no-pub packages/feldexa_export` | 0 | `.dart_tool/gate-t013-review/05-shared-feldexa_export.log` | PASS, 36/36 |
| 7 | `flutter test --no-pub packages/feldexa_testkit` | 0 | `.dart_tool/gate-t013-review/05-shared-feldexa_testkit.log` | PASS, 110/110 |
| 8 | `tools/gate.sh --offline --allow-absent --log-dir .dart_tool/gate-t013-review` | 0 | per-check logs below | Qualified pass: 10 passed, 0 failed, 0 unavailable, 1 absent planned layer |
| 9 | `git diff --check` | 0 | console only | PASS, no whitespace errors |
| 10 | `sha256sum pubspec.lock` before/after | 0 | console only | PASS, byte-identical `00a5b9fb…d1a21163` |

### Gate detail

```text
[ PASS] dependency resolution (pub.dev or cache) (evidence: none)
[ PASS] formatting (dart format, page width 80) (evidence: none)
[ PASS] static analysis (flutter analyze) (evidence: none)
[ABSENT] shared package tests: feldexa_adapters_android has no test/*_test.dart
[ABSENT] shared package tests: feldexa_adapters_simulated has no test/*_test.dart
[ABSENT] shared package tests: feldexa_application has no test/*_test.dart
[ PASS] shared package tests: feldexa_core (flutter test) (evidence: none (host VM))
[ PASS] shared package tests: feldexa_export (flutter test) (evidence: none (host VM))
[ PASS] shared package tests: feldexa_ports (flutter test) (evidence: none (host VM))
[ABSENT] shared package tests: feldexa_recognition has no test/*_test.dart
[ PASS] shared package tests: feldexa_testkit (flutter test) (evidence: none (host VM))
[ PASS] shared package tests: feldexa_ui (flutter test) (evidence: none (host VM))
[ PASS] app unit/widget tests (flutter test) (evidence: none (host VM))
[ PASS] SIMULATED app browser/interaction tests (flutter test --platform chrome) (evidence: SIMULATED)
[ABSENT] SIMULATED browser integration test layer (no integration_test/web_*_test.dart)

Checks passed: 10; failed: 0; unavailable: 0; absent planned layers: 1
GATE PASSED WITH INCOMPLETE LAYERS (not a complete gate)
```

The absent layers belong to future adapter/application/recognition suites and
the browser integration suite (T128/T145), not to T013. The Chrome run belongs
to the existing app suite; it is `SIMULATED` and is not T013 evidence.

### Retained local logs

| Log | Bytes | SHA-256 |
| --- | ---: | --- |
| `.dart_tool/gate-t013-review/01-pub-get.log` | 221 | `bf43ac2d8521495d0a1eff3ece869a5550c2a9554d10b078ce5c40b5e84985cc` |
| `.dart_tool/gate-t013-review/02-format.log` | 49 | `4f81553bfae638102229552a54b309b6b97386c0c195c90d56b0d95928c61fee` |
| `.dart_tool/gate-t013-review/03-analyze.log` | 96 | `5d4b1053defe94496bd1b4bdde0167916d89b0cf926fc58612b629e7ef5ea643` |
| `.dart_tool/gate-t013-review/04-app-unit.log` | 11139 | `4cdd5b378a25780610df4b3b940c613f7108050b6aee9baf6a71aee7350b49b7` |
| `.dart_tool/gate-t013-review/05-shared-feldexa_core.log` | 87683 | `074db35af3e649094d25da48c01ada5c5f714df7946be5de04f96d01e6a9351e` |
| `.dart_tool/gate-t013-review/05-shared-feldexa_export.log` | 7508 | `7cb40a5444780ce04f73786170fa3e45c2addef9a8684ade68a937dd8992f10e` |
| `.dart_tool/gate-t013-review/05-shared-feldexa_ports.log` | 19946 | `f84891d41cc0048d3b642c85a6f87aacdd32fb4d6b43d9268014c1dc3654f866` |
| `.dart_tool/gate-t013-review/05-shared-feldexa_testkit.log` | 20555 | `d3cec7e04950c9ac241c8d2eff22253925695ff5fa47de9614f48856d2cc978a` |
| `.dart_tool/gate-t013-review/05-shared-feldexa_ui.log` | 1856 | `127c630d2d9fea7e67d5362aedcfca78fe5102d8c11960909d4c402491cc21f2` |
| `.dart_tool/gate-t013-review/06-app-browser.log` | 1154 | `6f7db5b5be3f64caf5f94fbceb74021b81bb14e22643439aa1ab0c4775f033c7` |

Retained logs are git-ignored support artifacts under `.dart_tool/` and are not
in the candidate tree.

## 7. Evidence class

- Static analysis, formatting, and every T013 test produce **no runtime
  evidence class** (`NONE`). They prove compile-time contracts and host-VM
  behavior only.
- The gate's Chrome layer is **`SIMULATED`** browser evidence for the existing
  app suite. It is not T013 evidence.
- **No `EMULATOR` or `DEVICE` command was run.** No Android import, Keystore,
  storage, OCR, PDFBox, export, lifecycle, or device behavior is claimed.
- T013 defines interfaces and DTOs only. It cannot prove adapter behavior,
  evidence propagation through a real registry, German user-visible behavior,
  or platform integration.

## 8. Reproducibility

1. Start from base commit `7557991e51cc3a795289706fe330e97cb4ffea0d` and
   candidate `1ad5382d9ca0ec625c7f249a4f764edbb5e51331`.
2. Apply this correction commit on `xxammaxx/feldexa-t013-ports`.
3. Use Flutter `3.47.7` / Dart `3.13.5` and run
   `flutter pub get --offline`. The lockfile must remain
   `00a5b9fbc59e6038a1a93fd4cd2c24244f63dffa99b0b44a12f7e8f0d1a21163`.
4. Run `dart format --output=none --set-exit-if-changed .`; expect zero changed
   files.
5. Run `flutter analyze --no-pub`; expect `No issues found!`.
6. Run `flutter test --no-pub packages/feldexa_ports`; expect
   `+104: All tests passed!`.
7. Run `flutter test --no-pub packages/feldexa_core`,
   `packages/feldexa_export`, and `packages/feldexa_testkit`; expect 461, 36,
   and 110 tests.
8. Run `tools/gate.sh --offline --allow-absent` with `CHROME_EXECUTABLE` set;
   expect 10 passed, 0 failed, 0 unavailable, 1 absent planned layer. This is a
   qualified pass, not acceptance.
9. Confirm `git diff --check` is clean and
   `apps/feldexa_app/android/gradlew.bat` remains an unstaged, pre-existing
   line-ending artifact.

## 9. Preserved checkout artifact

`apps/feldexa_app/android/gradlew.bat` was already modified before T013. It is
the same pure CRLF/LF line-ending artifact recorded by earlier tasks:

| Item | Value |
| --- | --- |
| Diff | 90 insertions / 90 deletions |
| Working-file SHA-256 | `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62` |

It was never staged, reverted, or committed and is excluded from this
correction candidate. All other existing worktrees and uncommitted owner
changes were left untouched.

## 10. Exact candidate and transport

- **Base revision**: `7557991e51cc3a795289706fe330e97cb4ffea0d`.
- **Superseded T013 candidate**: `1ad5382d9ca0ec625c7f249a4f764edbb5e51331`.
- **Correction candidate**: the local commit on `xxammaxx/feldexa-t013-ports`
  that contains this report. Its exact SHA is recorded in `worker_done` and
  equals `git rev-parse HEAD` on the branch.
- **Not done**: no push, no pull request, no merge, no branch deletion, no
  GitHub issue closure, no signing/release action, and no self-approval.
  Independent quality review and integration remain external gates.

## 11. Limits

- The `SourceIntegrity` field is a T013-owned correction; no adapter is
  implemented here, so the field is proven only at the interface/host-VM level.
- The `PdfExportPort.validate` / `ExportValidation` collision is **not**
  resolved by this correction. It requires an owner/T022 decision; the three
  concrete options are listed in §3. No duplicate canonical type or signature
  change was invented.
- The correction does not expand evidence to `StoredMeta`, `RecoveryStamp`,
  `OcrBlock`, raw bytes, or primitive results; the contract does not attach
  evidence to those types, and doing so would be a new requirement.
- No ARB entries, German rendering, adapter evidence propagation, or platform
  guard are verified here. `SIM-001` enforcement at bootstrap remains a later
  registry/bootstrap task.
- The reviewer-owned `precision-testability.md` checklist remains unchecked;
  this report claims no requirements-quality approval.
