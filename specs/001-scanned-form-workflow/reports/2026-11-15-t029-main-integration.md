# T029 Main Integration: T013 + Per-Aggregate Keystore Contracts

- **Task**: T029 follow-up integration of actual GitHub `main`
- **Date**: 2026-11-15, Europe/Berlin
- **Class**: `NONE` (host-VM tests, analysis, and contract checks)
- **Result**: `PASS` for the local merge and host checks; no Android runtime claim
- **Candidate before merge**: `8e52c273dcfac921a9405a3f0ae9ca89918a7c02`
- **Upstream merged**: `406389fcc257453d2d23c961482ab6a29c471311`
  (`origin/main`, T013 reviewed)
- **Merge type**: normal two-parent merge; no rebase, amend, squash, push, or
  remote merge
- **Merge commit**: recorded in the external `worker_done` attestation; this
  report cannot contain its own commit SHA
- **Pre-existing tree state**: `apps/feldexa_app/android/gradlew.bat` was
  modified before this task and remains untouched/uncommitted

## 1. Scope

The merge integrates the reviewed T013 implementation (`packages/feldexa_ports`
ports, DTOs, registry, and T013 evidence) with the T029 per-document/template
Keystore decision. It preserves:

- T013's implemented contract, task mark, and evidence reports;
- T029's ARB/catalog work, source-of-truth correction, owner decision,
  evidence, and task mark;
- T025/T026 open ownership with per-aggregate key wording;
- CR-11 and the per-aggregate decision report.

## 2. Merge and conflict result

`git merge origin/main` produced **no textual conflicts**. It auto-merged
`contracts/ports.md`, `reports/README.md`, and `tasks.md`. A semantic
reconciliation was still required because T013 implements `StoreStatus` from
the pre-decision contract:

- `StoreStatus.keyAvailable` is retained as a T013-compatible store-level
  summary. It is false when at least one known aggregate key is unavailable; it
  never throws for the whole store and never hides unaffected aggregates.
  Per-aggregate authority remains `StoredMeta.readable`,
  `unreadableReasonCode`, and `KeyUnavailableException`.
- `StoredMeta.title` remains non-empty as T013 validates (`1–200` characters).
  For an aggregate whose key is unavailable, the contract now uses the German
  catalog placeholder "Nicht lesbar" instead of an empty title. The UI does not
  derive a title from ciphertext, and deletion confirmation matches that
  placeholder.
- No T013 code or test was changed. The T029 contract, platform-channel,
  data-model, research, and decision report were adjusted to the retained T013
  API.
- `spec.md` remains unchanged: FR-052 and acceptance scenario 7 already require
  the isolation the per-aggregate model provides.

No other conflict or foreign change was introduced.

## 3. Preserved contracts and ownership

| Item | State |
| --- | --- |
| T013 task | `[x]`, implementation and four T013 evidence reports preserved |
| T029 task | `[x]`, ARB/catalog/source-correction/decision evidence preserved |
| T025/T026 | Open, now owned as per-document/template KEK creation, lifecycle, deletion, and orphan-alias sweep |
| CR-11 | Present, records the 2026-11-15 owner decision |
| `PRIV-001`/`SAVE-002` | Consistent German catalog and ARB texts; `german_strings_test.dart` verifies both |
| `IMP-007`/`FLD-001` | Corrected verbatim texts preserved |
| T013 `StoreStatus` | Retained; per-aggregate summary semantics documented |
| T029 per-aggregate keys | One non-exportable Keystore KEK per document and per template; no shared `feldexa.master.v1` |

## 4. Host checks on the merged tree

Toolchain: Flutter 3.47.7 (stable), Dart 3.13.5, workspace `pubspec.yaml` and
committed `pubspec.lock`. Logs were console-only and are not retained.

| Command | Working directory | Exit | Observed |
| --- | --- | --- | --- |
| `flutter pub get --offline` | repository root | 0 | merged workspace resolved from the lockfile |
| `flutter test` | `apps/feldexa_app` | 0 | 65 tests passed, including 9 `german_strings_test.dart` tests |
| `flutter test` | `packages/feldexa_ports` | 0 | 107 tests passed, including T013 type-ownership and port-contract tests |
| `flutter test` | `packages/feldexa_testkit` | 0 | 110 tests passed |
| `flutter analyze --no-pub` | repository root | 0 | No issues found |

Contract consistency checks performed:

- `german_strings_test.dart` parses `contracts/error-catalog.de.md` and verifies
  exact catalog→ARB text plus the complete bidirectional key mapping.
- T013 `type_ownership_test.dart` verifies canonical types, no duplicate
  declarations, ports independence, and every T013-owned file.
- Targeted greps confirm `StoreStatus.keyAvailable` exists in both the T013 DTO
  and the merged ports contract; the "Nicht lesbar" placeholder is documented
  for `StoredMeta.title`; no shared `feldexa.master.v1` alias remains in the
  key architecture (only the rejected-alternative/test-vector references).
- `tasks.md` still marks T013 and T029 `[x]`, T025/T026 open, and CR-11 present.

## 5. Remaining limits

- T025/T026 are unimplemented: no `KeystoreService.kt`/`EncryptedStore.kt`, so
  no `EMULATOR` or `DEVICE` key-loss, listing, or deletion proof exists.
- A whole-Keystore or device reset invalidates every alias and remains a
  device-wide loss case.
- An affected aggregate's encrypted metadata is unreadable; the list uses the
  "Nicht lesbar" placeholder and cannot recover the original title.
- No push, remote merge, or self-review is claimed.

## 6. Files changed by this integration

- `specs/001-scanned-form-workflow/contracts/ports.md`
- `specs/001-scanned-form-workflow/contracts/platform-channel.md`
- `specs/001-scanned-form-workflow/contracts/storage-format.md`
- `specs/001-scanned-form-workflow/data-model.md`
- `specs/001-scanned-form-workflow/research.md`
- `specs/001-scanned-form-workflow/reports/2026-11-15-t029-per-aggregate-keystore-decision.md`
- this report and `reports/README.md`
- plus the full T013 upstream file set and T029 candidate files already present
  in the two merge parents

## 7. Review

Reviewer: _(blank; independent review required)_

Date:

Verdict:
