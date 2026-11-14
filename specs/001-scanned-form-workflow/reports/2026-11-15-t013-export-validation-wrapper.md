# T013 Owner Decision — Evidence-Bearing ExportValidationResult

| Field | Value |
| --- | --- |
| Repository | `xxammaxx/Feldexa_2.0` |
| Task / issue | T013 / #13 |
| Evidence class | `NONE` (static analysis and host-VM tests only) |
| Result | `PASS` for the owner-decision implementation; the local gate is qualified because future test layers are absent |
| Date / timezone | 2026-11-15 (Europe/Berlin) |
| Base revision | `46f80a3e7e537f98b5fc79bb9ef913d0061700d9` (T013 flattening correction on `7557991e51cc3a795289706fe330e97cb4ffea0d`) |
| Worktree branch | `xxammaxx/feldexa-t013-ports` |
| Worktree | isolated Orca worktree `feldexa-t013-ports` |
| Candidate revision | the local commit on `xxammaxx/feldexa-t013-ports` that contains this report; the exact SHA is recorded in `worker_done` and is reproducible with `git rev-parse HEAD` |
| Toolchain | Flutter `3.47.7`, Dart `3.13.5` |
| Runtime evidence | none; no `SIMULATED`, `EMULATOR`, or `DEVICE` T013 result is claimed |

## 0. Owner decision and scope

The quality review had documented a genuine collision: `contracts/ports.md` §1
requires `CapabilityEvidence` on every acceptance-relevant result, while
`PdfExportPort.validate` returned the canonical T022 `ExportValidation`, which
cannot carry a ports type because `feldexa_export` must not import
`feldexa_ports`.

The owner decided to resolve that collision with a **ports-owned wrapper**:
`PdfExportPort.validate` now returns an `ExportValidationResult` containing the
canonical `ExportValidation` plus `CapabilityEvidence`; the contract signature is
updated accordingly. This task implements that decision on candidate `46f80a3`.

Scope boundaries:

- `ExportValidation` remains canonical T022 data and is **not** modified or
  duplicated.
- `feldexa_export` remains free of any `feldexa_ports` dependency.
- `ExportResult` and the flattening guard from `46f80a3` are unchanged.
- No push, merge, self-review, PR, or issue closure is performed.

## 1. Normative and ownership analysis

| Requirement / boundary | Effect |
| --- | --- |
| `contracts/ports.md` §1 | Every acceptance-relevant result, including the preflight validation result, carries `CapabilityEvidence` |
| `contracts/ports.md` §2.5 (old) | `Future<ExportValidation> validate(ExportPlan plan)` returned only canonical T022 data |
| `contracts/ports.md` §1 type ownership | `ExportValidation` is T022-owned in `feldexa_export`; ports must consume it, not redeclare it |
| `contracts/export-plan.md` line 5 | `feldexa_export` does not import `feldexa_ports`; `ExportPlan.evidenceClass` is a string token, not a ports type |
| One-way dependency | core → export → ports; `feldexa_export` must stay innermost relative to ports |
| Owner decision 2026-11-15 | Add a T013-owned wrapper that holds canonical `ExportValidation` + `CapabilityEvidence`; update §2.5 |

The wrapper is therefore a result type, not a second validation model: it has no
warning fields of its own and no serialized copy of the canonical validation. It
delegates `isValid`, `isBlocking`, and `warnings` to the canonical instance.

## 2. Implementation

### 2.1 `ExportValidationResult`

Added to `packages/feldexa_ports/lib/src/dto/export_dto.dart`:

```dart
final class ExportValidationResult {
  const ExportValidationResult({
    required this.validation,
    required this.evidence,
  });

  final ExportValidation validation;   // canonical T022 type
  final CapabilityEvidence evidence;

  bool get isValid => validation.isValid;
  bool get isBlocking => validation.isBlocking;
  List<ExportValidationWarning> get warnings => validation.warnings;
}
```

- `validation` is the exact canonical T022 object; no copy, wrapper-specific
  warning shape, or second `ExportValidation` declaration exists.
- `evidence` is the canonical T014 `CapabilityEvidence`.
- `warnings` returns the canonical unmodifiable warning list; `fieldLabel`
  content is never emitted by `toString()`.
- `toString()` reports only `isValid` and the warning count.

### 2.2 Interface and contract

- `PdfExportPort.validate` now returns
  `Future<ExportValidationResult> validate(ExportPlan plan)`.
- `contracts/ports.md` §2.5 shows the wrapper and the updated signature, states
  that it is T013-owned, keeps `ExportValidation` T022-owned, and records that
  `feldexa_export` still does not import `feldexa_ports`.
- The Foundational Type Ownership table in `tasks.md` lists
  `ExportValidationResult` as a T013-owned type.
- `export_dto.dart` and `pdf_export_port.dart` comments now describe the
  allowed wrapper instead of the former "no wrapper" wording.
- `ExportRequest`, `ExportOptions`, `ExportResult`, `ExportPlan`,
  `ExportValidation`, `ExportArtifact`, and `ArtifactVerification` are unchanged
  except for the signature/contract references.

### 2.3 Fakes and tests

- The fake `PdfExportPort` in `ports_contract_test.dart` returns
  `ExportValidationResult`, so the interface shape is compile-time enforced.
- `fixtures.dart` adds non-blocking and blocking canonical validations plus a
  wrapper fixture.
- `dto_contract_test.dart` proves:
  - a non-blocking wrapper exposes the canonical validation, `isValid: true`,
    `isBlocking: false`, and the adapter evidence;
  - a blocking wrapper preserves the canonical `EXP-001`/`too_wide` warning,
    `isBlocking: true`, the page index, and a `SIMULATED` evidence label;
  - `toString()` does not echo the warning label.
- `type_ownership_test.dart` proves the canonical `ExportValidation` remains
  T022-owned, `feldexa_export` still has no `CapabilityEvidence` or
  `package:feldexa_ports` reference, the wrapper holds the exact canonical
  object, and `ExportResult` still carries evidence.
- The existing “no canonical type redeclared” scan still matches every T013 file.

## 3. What changed

All paths are relative to the repository root. The report's own row is omitted
by construction.

| File | Change | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `packages/feldexa_ports/lib/src/dto/export_dto.dart` | adds `ExportValidationResult`; documents the allowed wrapper | 5307 | `4e3a6d89d24fd339be7939e6b04d748af0738ebab822f8b71518f18bbb3ed909` |
| `packages/feldexa_ports/lib/src/ports/pdf_export_port.dart` | `validate` returns `ExportValidationResult`; docs cite evidence and FR-068 | 2106 | `2219f3ea8f2f9e7c7543deda7d21511259d1039aef8c6368b2f4a4f4abd53ed6` |
| `packages/feldexa_ports/test/fixtures.dart` | blocking/non-blocking validations and wrapper fixture | 7164 | `c9c68ab70ef3755bd4144b76ecc280e96c9624a3481131cebbcc255a9e6b8c54` |
| `packages/feldexa_ports/test/dto_contract_test.dart` | wrapper evidence, blocking preservation, and privacy regressions | 29045 | `fa45116a1b4805935554912e59a603d905cbe6bcca00c6a701484e790a052e4d` |
| `packages/feldexa_ports/test/ports_contract_test.dart` | fake and interface test use the wrapper; evidence/blocking assertions | 22567 | `65ad3839f8d511b7a0156df4ea17757d2ed259faeef5048f8ce65fac5e6cc721` |
| `packages/feldexa_ports/test/type_ownership_test.dart` | owner-decision boundary test; canonical object identity and export isolation | 12644 | `e7bb53fee26dcae4f283e8993abfd4018b23044bbda0b8f7f022d8329961603a` |
| `specs/001-scanned-form-workflow/contracts/ports.md` | §2.5 wrapper class, new signature, ownership/evidence clarification | 21731 | `a884ff135867d448e83bdace818f779424bfc7b9148317dc279c0f5f30fc74f2` |
| `specs/001-scanned-form-workflow/tasks.md` | T013 ownership row includes `ExportValidationResult` | 65116 | `ed273ffe115bbd0dd3e49e16d35d7924ccedb82e6471ea106aca027214d1acea` |
| `specs/001-scanned-form-workflow/reports/2026-11-14-t013-evidence-review-correction.md` | owner-decision banner; historical options retained for audit | 20556 | `3d378534b4b21a3b7307bec8e190d1cfe8d983e9f6bb38bd91b35e8c3db084c4` |
| `specs/001-scanned-form-workflow/reports/2026-11-14-t013-export-options-flatten-correction.md` | owner-decision banner; flattening result unchanged | 15666 | `66824da3f5e6a495cdbec3fd20e7b8d54193986c84df20851ff4fa2ea31b7460` |
| `specs/001-scanned-form-workflow/reports/README.md` | index row for this decision report | 21248 | `8d549e2237cd22f1d0a1c2f90faad5032ccc673a5190bca69f97b6001164e722` |

`pubspec.lock` remains byte-identical
(`00a5b9fbc59e6038a1a93fd4cd2c24244f63dffa99b0b44a12f7e8f0d1a21163`,
22638 bytes). `feldexa_export` source was not modified and still does not import
`feldexa_ports`. The pre-existing `gradlew.bat` line-ending artifact remains
uncommitted and unstaged (§8).

## 4. Tests and verification

| Suite | Tests | Result | What it pins |
| --- | ---: | --- | --- |
| `test/descriptor_test.dart` | 12 | PASS | unchanged descriptor vocabulary |
| `test/dto_contract_test.dart` | 38 | PASS | wrapper evidence, blocking preservation, privacy, plus previous DTO coverage |
| `test/ports_contract_test.dart` | 16 | PASS | fake/interface signature, wrapper evidence, export result evidence |
| `test/type_ownership_test.dart` | 8 | PASS | canonical `ExportValidation` ownership, no export→ports dependency, exact object identity |
| `test/errors_test.dart` (T014, unchanged) | 17 | PASS | existing error taxonomy |
| `test/evidence_test.dart` (T014, unchanged) | 16 | PASS | existing evidence vocabulary |
| **`packages/feldexa_ports` total** | **107** | **PASS** | 105 before the owner decision; two wrapper regressions |

Affected adjacent suites remain green: `feldexa_core` 461, `feldexa_export` 36,
and `feldexa_testkit` 110. The export suite is unchanged because the T022 model
was deliberately not modified.

| # | Command | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `flutter pub get --offline` | 0 | `.dart_tool/gate-t013-wrapper/01-pub-get.log` | PASS; lockfile byte-identical |
| 2 | `dart format --output=none --set-exit-if-changed .` | 0 | `.dart_tool/gate-t013-wrapper/02-format.log` | PASS, 101 files, 0 changed |
| 3 | `flutter analyze --no-pub` | 0 | `.dart_tool/gate-t013-wrapper/03-analyze.log` | PASS, `No issues found!` |
| 4 | `flutter test --no-pub packages/feldexa_ports` | 0 | `.dart_tool/gate-t013-wrapper/05-shared-feldexa_ports.log` | PASS, 107/107 |
| 5 | `flutter test --no-pub packages/feldexa_core` | 0 | `.dart_tool/gate-t013-wrapper/05-shared-feldexa_core.log` | PASS, 461/461 |
| 6 | `flutter test --no-pub packages/feldexa_export` | 0 | `.dart_tool/gate-t013-wrapper/05-shared-feldexa_export.log` | PASS, 36/36 |
| 7 | `flutter test --no-pub packages/feldexa_testkit` | 0 | `.dart_tool/gate-t013-wrapper/05-shared-feldexa_testkit.log` | PASS, 110/110 |
| 8 | `tools/gate.sh --offline --allow-absent --log-dir .dart_tool/gate-t013-wrapper` | 0 | per-check logs below | Qualified pass: 10 passed, 0 failed, 0 unavailable, 1 absent planned layer |
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
| `.dart_tool/gate-t013-wrapper/01-pub-get.log` | 221 | `bf43ac2d8521495d0a1eff3ece869a5550c2a9554d10b078ce5c40b5e84985cc` |
| `.dart_tool/gate-t013-wrapper/02-format.log` | 49 | `038a9b0aea2152c797e96e46ebaf991076fa35694e7fdec10709e179b1845f41` |
| `.dart_tool/gate-t013-wrapper/03-analyze.log` | 96 | `5f670de782757782671e8958662e2c5f4282c77a24294b29f68e89caf1f26330` |
| `.dart_tool/gate-t013-wrapper/04-app-unit.log` | 11139 | `fa4bd9ef579caab0a2de86af13d7700bceeabe48308f05f351098ff64bd21608` |
| `.dart_tool/gate-t013-wrapper/05-shared-feldexa_core.log` | 87193 | `c4e2fabfc04edeb3f4adfa742a9225c644b1f04984e60528c58a5be508ac2bbb` |
| `.dart_tool/gate-t013-wrapper/05-shared-feldexa_export.log` | 7508 | `6d1f279e570b9b8b589c634dc1f3db55e82b82bed11c0880d5727055147fa1cd` |
| `.dart_tool/gate-t013-wrapper/05-shared-feldexa_ports.log` | 20630 | `13ec5ff48d25fa46299f30f3143b1907e3e92ed5ad6fa02eddb0e5fbd19b5461` |
| `.dart_tool/gate-t013-wrapper/05-shared-feldexa_testkit.log` | 20855 | `e191fcaba6892704ead99e8c745fd52c84a72d878a6de6bf317de15882a9fac9` |
| `.dart_tool/gate-t013-wrapper/05-shared-feldexa_ui.log` | 1856 | `64c3d2008847e56ab1b9620271814d6edd0d2afeb489de25571d027d5d9c4338` |
| `.dart_tool/gate-t013-wrapper/06-app-browser.log` | 1154 | `2ddc0002b4e8cfea94c08fa59e0c64aa5e85a2cfa360027e6d28f83601414cc2` |

Retained logs are git-ignored support artifacts under `.dart_tool/` and are not
in the candidate tree.

## 5. Evidence class

- Static analysis, formatting, and every T013 test produce **no runtime
  evidence class** (`NONE`). They prove compile-time contracts and host-VM
  behavior only.
- The gate's Chrome layer is **`SIMULATED`** browser evidence for the existing
  app suite. It is not T013 evidence.
- **No `EMULATOR` or `DEVICE` command was run.** No Android PDFBox, storage,
  preview, share, or print behavior is claimed.
- The wrapper proves the preflight result is evidence-bearing and preserves
  blocking semantics; it does not prove an adapter's validation implementation,
  which remains a later adapter/EMULATOR/DEVICE gate.

## 6. Reproducibility

1. Start from base `46f80a3e7e537f98b5fc79bb9ef913d0061700d9` on
   `7557991e51cc3a795289706fe330e97cb4ffea0d`.
2. Apply this owner-decision commit on `xxammaxx/feldexa-t013-ports`.
3. Use Flutter `3.47.7` / Dart `3.13.5` and run
   `flutter pub get --offline`. The lockfile must remain
   `00a5b9fbc59e6038a1a93fd4cd2c24244f63dffa99b0b44a12f7e8f0d1a21163`.
4. Run `dart format --output=none --set-exit-if-changed .`; expect zero changed
   files.
5. Run `flutter analyze --no-pub`; expect `No issues found!`.
6. Run `flutter test --no-pub packages/feldexa_ports`; expect
   `+107: All tests passed!`.
7. Run `flutter test --no-pub packages/feldexa_core`,
   `packages/feldexa_export`, and `packages/feldexa_testkit`; expect 461, 36,
   and 110 tests.
8. Run `tools/gate.sh --offline --allow-absent` with `CHROME_EXECUTABLE` set;
   expect 10 passed, 0 failed, 0 unavailable, 1 absent planned layer. This is a
   qualified pass, not acceptance.
9. Confirm `git diff --check` is clean and
   `apps/feldexa_app/android/gradlew.bat` remains an unstaged, pre-existing
   line-ending artifact.

## 7. Preserved checkout artifact

`apps/feldexa_app/android/gradlew.bat` was already modified before T013. It is
the same pure CRLF/LF line-ending artifact recorded by earlier tasks:

| Item | Value |
| --- | --- |
| Diff | 90 insertions / 90 deletions |
| Working-file SHA-256 | `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62` |

It was never staged, reverted, or committed and is excluded from this
owner-decision candidate. All other existing worktrees and uncommitted owner
changes were left untouched.

## 8. Exact candidate and transport

- **Base revision**: `7557991e51cc3a795289706fe330e97cb4ffea0d`.
- **Superseded T013 candidates**:
  `1ad5382d9ca0ec625c7f249a4f764edbb5e51331`,
  `6b838da666350ce2578a876a5a0eda2bead63916`, and
  `46f80a3e7e537f98b5fc79bb9ef913d0061700d9`.
- **Owner-decision candidate**: the local commit on
  `xxammaxx/feldexa-t013-ports` that contains this report. Its exact SHA is
  recorded in `worker_done` and equals `git rev-parse HEAD` on the branch.
- **Not done**: no push, no pull request, no merge, no branch deletion, no
  GitHub issue closure, no signing/release action, and no self-approval.
  Independent quality review and integration remain external gates.

## 9. Limits

- The wrapper is a host-VM/interface proof only; no Android adapter exists yet,
  so actual PDFBox validation remains T023+ evidence.
- `ExportValidation` remains canonical T022 data. This change did not modify
  `ExportPlan`, `ExportValidation`, `ExportArtifact`, or `ArtifactVerification`,
  and `feldexa_export` still does not import `feldexa_ports`.
- The flattening guard from `46f80a3` and the documented `ExportOptions`
  behavior are unchanged; `embedFonts` remains default-true and is not made
  mandatory here.
- No ARB entries, German rendering, adapter evidence propagation, or platform
  guard are verified here. `SIM-001` enforcement at bootstrap remains a later
  registry/bootstrap task.
- The reviewer-owned `precision-testability.md` checklist remains unchecked;
  this report claims no requirements-quality approval.
