# T013 ExportOptions Flattening Correction — Mandatory Flattening and the ExportValidation Boundary

> **Owner decision (2026-11-15):** The `ExportValidation` collision referenced
> below was resolved after this report by a T013-owned
> `ExportValidationResult` carrying canonical T022 `ExportValidation` plus
> `CapabilityEvidence`. The flattening result above is unchanged, and
> `feldexa_export` remains ports-free. See
> [2026-11-15-t013-export-validation-wrapper.md](./2026-11-15-t013-export-validation-wrapper.md).

| Field | Value |
| --- | --- |
| Repository | `xxammaxx/Feldexa_2.0` |
| Task / issue | T013 / #13 |
| Evidence class | `NONE` (static analysis and host-VM tests only) |
| Result | `PASS` for the flattening correction; the local gate is qualified because future test layers are absent |
| Date / timezone | 2026-11-14 (Europe/Berlin) |
| Base revision | `7557991e51cc3a795289706fe330e97cb4ffea0d` (`origin/main`) |
| Superseded T013 candidates | `1ad5382d9ca0ec625c7f249a4f764edbb5e51331` (reviewed candidate) and `6b838da666350ce2578a876a5a0eda2bead63916` (evidence correction) |
| Worktree branch | `xxammaxx/feldexa-t013-ports` |
| Worktree | isolated Orca worktree `feldexa-t013-ports` |
| Candidate revision | the local commit on `xxammaxx/feldexa-t013-ports` that contains this report; the exact SHA is recorded in `worker_done` and is reproducible with `git rev-parse HEAD` |
| Toolchain | Flutter `3.47.7`, Dart `3.13.5` |
| Runtime evidence | none; no `SIMULATED`, `EMULATOR`, or `DEVICE` T013 result is claimed |

## 0. Review finding and scope

The quality review of candidate `1ad5382` reported that
`packages/feldexa_ports/lib/src/dto/export_dto.dart` accepts
`ExportOptions(flatten: false)`, although `contracts/ports.md` §2.5 (lines
271–275 in the current file) requires the export to be flattened with no
interactive form fields, and FR-069 requires a flattened, self-contained PDF
without interactive form controls.

This correction:

- audits the normative §2.5/§2.10 and `contracts/export-plan.md` requirements;
- confirms the deviation inside T013's owned `ExportOptions` DTO;
- fixes it minimally without changing `ExportPlan`, `ExportValidation`, or any
  other T022 canonical type;
- adds positive and negative regressions;
- leaves the previously documented `ExportValidation` evidence collision and
  its three owner options unchanged, as instructed.

No other task is selected, implemented, or marked complete. `tasks.md` already
marks T013 `[x]`; its line is unchanged.

## 1. Normative audit

### 1.1 Flattening is mandatory, not optional

`contracts/ports.md` §2.5 states:

- `export` writes to a temp name, verifies by reopening, checks page count and
  media boxes, **confirms no interactive form fields**, then atomically renames
  (FR-072).
- The produced file is self-contained and **flattened**; the exported PDF is a
  normal PDF with **no AcroForm widgets** (FR-069).

`contracts/export-plan.md` §5 repeats the applier algorithm: flatten any
pre-existing AcroForm in memory, remove residual field dictionaries or widget
annotations, and assert `getAcroForm()` is null or empty before adding overlays.
The verification table lists “No interactive controls” as a required zero-count
criterion.

FR-069 is a MUST: the exported PDF must be flattened, self-contained, and free
of interactive form controls. Accepting a request that explicitly disables
flattening would make the port contract impossible to satisfy, so
`flatten: false` is not a valid export request.

### 1.2 T013 ownership and the contract snippet

`contracts/ports.md` §2.10 declares `ExportOptions` with `final bool flatten;`
and the comment `// default true`. T013 owns `lib/src/dto/export_dto.dart`; no
T022 canonical type is involved in this finding.

The snippet's “default true” does not make false valid; the binding §2.5 and
FR-069 requirements do. Removing the `flatten` field would be a contract change
and was not authorized, so the field remains and the constructor enforces the
only value the contract permits. `ExportOptions` is no longer `const`; the
runtime guard must execute in release builds, following the T014
`CapabilityEvidence` precedent.

## 2. Minimal correction

`ExportOptions` is now a factory that rejects `flatten: false` with a safe
`ArgumentError`:

```dart
factory ExportOptions({bool flatten = true, bool embedFonts = true}) {
  if (!flatten) {
    throw ArgumentError(
      'flatten must be true; the exported PDF is always flattened',
    );
  }
  return ExportOptions._(flatten: flatten, embedFonts: embedFonts);
}
```

- `flatten` remains a `final bool` field required by §2.10 and is always true
  for a constructed value.
- The private const `_defaults` keeps `ExportRequest`'s optional-options
  default without exposing a new public API.
- No core, export, or T014 canonical type changed; no second `ExportOptions`
  or export result type was declared.
- `embedFonts` is unchanged. The review did not raise it, and the contract
  states only a default, so making it mandatory would be a separate owner
  decision rather than this correction.

## 3. Regressions

`test/dto_contract_test.dart` now covers both directions:

- **positive:** `ExportOptions()` and `ExportOptions(flatten: true)` expose
  `flatten: true` and `embedFonts: true`; `ExportRequest` keeps its working
  default;
- **negative:** `ExportOptions(flatten: false)` throws an `ArgumentError`
  whose message states the mandatory rule and does not echo a content value.

The test count in `feldexa_ports` rises from 104 to **105** (one new negative
test; the existing positive test was tightened).

## 4. What changed

All paths are relative to the repository root. The report's own row is omitted
by construction.

| File | Change | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `packages/feldexa_ports/lib/src/dto/export_dto.dart` | `ExportOptions` factory rejects `flatten: false`; private const default; docs cite §2.5/FR-069 | 3795 | `bc9a888f66aa73a3a63b8b476e7d4a535030a9c7db458b62a556cecd6f3d8b1a` |
| `packages/feldexa_ports/test/dto_contract_test.dart` | positive default/true coverage and negative false rejection | 27574 | `4a56c7f7f6fd3f77c404f03c647eb427a77f017fa3e6981a8a5b4841340feb11` |
| `specs/001-scanned-form-workflow/reports/2026-11-14-t013-evidence-review-correction.md` | correction banner; test count 104 superseded by 105 | 20043 | `9e7a99c9e85f868c8f4932119947b2813f39adf3d1e6ed7f77afdea5ef640d3e` |
| `specs/001-scanned-form-workflow/reports/README.md` | index row for this correction | 20911 | `df357cb407eb7811c3d83f1d6a6df0d73985008934ccddb04607ee14a57cd305` |

`contracts/ports.md` was **not** changed by this correction: §2.5 already
requires flattened output, and editing the §2.10 field list/option semantics
would be an unauthorized contract decision. `pubspec.lock` remains
byte-identical
(`00a5b9fbc59e6038a1a93fd4cd2c24244f63dffa99b0b44a12f7e8f0d1a21163`,
22638 bytes). The pre-existing `gradlew.bat` line-ending artifact remains
uncommitted and unstaged (§8).

The previously documented `ExportValidation` evidence collision in
`2026-11-14-t013-evidence-review-correction.md` §3 is unchanged: T022 still owns
`ExportValidation`, `feldexa_export` still does not import `feldexa_ports`, and
the three owner options are not decided here. `ExportResult` still carries the
export acceptance evidence.

## 5. Verification

| # | Command | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `flutter pub get --offline` | 0 | `.dart_tool/gate-t013-flatten/01-pub-get.log` | PASS; lockfile byte-identical |
| 2 | `dart format --output=none --set-exit-if-changed .` | 0 | `.dart_tool/gate-t013-flatten/02-format.log` | PASS, 101 files, 0 changed |
| 3 | `flutter analyze --no-pub` | 0 | `.dart_tool/gate-t013-flatten/03-analyze.log` | PASS, `No issues found!` |
| 4 | `flutter test --no-pub packages/feldexa_ports` | 0 | `.dart_tool/gate-t013-flatten/05-shared-feldexa_ports.log` | PASS, 105/105 |
| 5 | `flutter test --no-pub packages/feldexa_core` | 0 | `.dart_tool/gate-t013-flatten/05-shared-feldexa_core.log` | PASS, 461/461 |
| 6 | `flutter test --no-pub packages/feldexa_export` | 0 | `.dart_tool/gate-t013-flatten/05-shared-feldexa_export.log` | PASS, 36/36 |
| 7 | `flutter test --no-pub packages/feldexa_testkit` | 0 | `.dart_tool/gate-t013-flatten/05-shared-feldexa_testkit.log` | PASS, 110/110 |
| 8 | `tools/gate.sh --offline --allow-absent --log-dir .dart_tool/gate-t013-flatten` | 0 | per-check logs below | Qualified pass: 10 passed, 0 failed, 0 unavailable, 1 absent planned layer |
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
| `.dart_tool/gate-t013-flatten/01-pub-get.log` | 221 | `bf43ac2d8521495d0a1eff3ece869a5550c2a9554d10b078ce5c40b5e84985cc` |
| `.dart_tool/gate-t013-flatten/02-format.log` | 49 | `a36eb48272861385800448524ec72afc9e66f84fe62a4af985081d26c5940044` |
| `.dart_tool/gate-t013-flatten/03-analyze.log` | 96 | `b7f2849d62d29ee0edec32199cd86fbb8e988442018c95be94124c5cb110024f` |
| `.dart_tool/gate-t013-flatten/04-app-unit.log` | 11139 | `e1076eebd63743f5c56e818959001d02470b2647e8ba1763f27a16e6272f5ca9` |
| `.dart_tool/gate-t013-flatten/05-shared-feldexa_core.log` | 87133 | `0c02b7ad9d69dca3a0e334136cb32155b1c4c5912c2b982494e1ea3822626ab1` |
| `.dart_tool/gate-t013-flatten/05-shared-feldexa_export.log` | 7508 | `5896cbde3183a9280a6de58c7a511a3a67a01652341f17d67c198bbad2736bd9` |
| `.dart_tool/gate-t013-flatten/05-shared-feldexa_ports.log` | 20374 | `10fca6d5e048a252c91386cc71d1046f3acdab653c301310eff0e1e41e29e0d7` |
| `.dart_tool/gate-t013-flatten/05-shared-feldexa_testkit.log` | 20378 | `1783951db5e192524e72a0abad0ee22bd690892724ebffac8bfa97fa7536152b` |
| `.dart_tool/gate-t013-flatten/05-shared-feldexa_ui.log` | 1856 | `d50e277dc02bb3a4c8c54a9a64d4668f106d7b75d59670deb06b85b2a65f9d74` |
| `.dart_tool/gate-t013-flatten/06-app-browser.log` | 1154 | `c5220a3d4416c0de8f3b3d0d745c08416543c6809648e4d44809de2fd181037f` |

Retained logs are git-ignored support artifacts under `.dart_tool/` and are not
in the candidate tree.

## 6. Evidence class

- Static analysis, formatting, and every T013 test produce **no runtime
  evidence class** (`NONE`). They prove compile-time contracts and host-VM
  behavior only.
- The gate's Chrome layer is **`SIMULATED`** browser evidence for the existing
  app suite. It is not T013 evidence.
- **No `EMULATOR` or `DEVICE` command was run.** No Android PDFBox, storage,
  preview, share, or print behavior is claimed.
- The guard proves that an unflattened export request cannot be constructed;
  it does not prove an adapter's flattening implementation, which remains a
  later adapter/EMULATOR/DEVICE gate.

## 7. Reproducibility

1. Start from base commit `7557991e51cc3a795289706fe330e97cb4ffea0d` and the
   reviewed candidates `1ad5382` / `6b838da`.
2. Apply this correction commit on `xxammaxx/feldexa-t013-ports`.
3. Use Flutter `3.47.7` / Dart `3.13.5` and run
   `flutter pub get --offline`. The lockfile must remain
   `00a5b9fbc59e6038a1a93fd4cd2c24244f63dffa99b0b44a12f7e8f0d1a21163`.
4. Run `dart format --output=none --set-exit-if-changed .`; expect zero changed
   files.
5. Run `flutter analyze --no-pub`; expect `No issues found!`.
6. Run `flutter test --no-pub packages/feldexa_ports`; expect
   `+105: All tests passed!`.
7. Run `flutter test --no-pub packages/feldexa_core`,
   `packages/feldexa_export`, and `packages/feldexa_testkit`; expect 461, 36,
   and 110 tests.
8. Run `tools/gate.sh --offline --allow-absent` with `CHROME_EXECUTABLE` set;
   expect 10 passed, 0 failed, 0 unavailable, 1 absent planned layer. This is a
   qualified pass, not acceptance.
9. Confirm `git diff --check` is clean and
   `apps/feldexa_app/android/gradlew.bat` remains an unstaged, pre-existing
   line-ending artifact.

## 8. Preserved checkout artifact

`apps/feldexa_app/android/gradlew.bat` was already modified before T013. It is
the same pure CRLF/LF line-ending artifact recorded by earlier tasks:

| Item | Value |
| --- | --- |
| Diff | 90 insertions / 90 deletions |
| Working-file SHA-256 | `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62` |

It was never staged, reverted, or committed and is excluded from this
correction candidate. All other existing worktrees and uncommitted owner
changes were left untouched.

## 9. Exact candidate and transport

- **Base revision**: `7557991e51cc3a795289706fe330e97cb4ffea0d`.
- **Superseded T013 candidates**:
  `1ad5382d9ca0ec625c7f249a4f764edbb5e51331` and
  `6b838da666350ce2578a876a5a0eda2bead63916`.
- **Correction candidate**: the local commit on `xxammaxx/feldexa-t013-ports`
  that contains this report. Its exact SHA is recorded in `worker_done` and
  equals `git rev-parse HEAD` on the branch.
- **Not done**: no push, no pull request, no merge, no branch deletion, no
  GitHub issue closure, no signing/release action, and no self-approval.
  Independent quality review and integration remain external gates.

## 10. Limits

- The `flatten: false` guard is a host-VM/interface proof only; no Android
  adapter exists yet, so actual PDFBox flattening remains T023+ evidence.
- The `ExportValidation` evidence collision and its three owner options are
  intentionally unchanged. This correction did not modify `ExportValidation`,
  `ExportPlan`, `ExportArtifact`, or any other T022 type.
- `embedFonts` remains default-true and is not made mandatory here; the review
  did not raise it and the contract states only a default, so changing it would
  be a separate owner decision.
- No ARB entries, German rendering, adapter evidence propagation, or platform
  guard are verified here. `SIM-001` enforcement at bootstrap remains a later
  registry/bootstrap task.
- The reviewer-owned `precision-testability.md` checklist remains unchecked;
  this report claims no requirements-quality approval.
