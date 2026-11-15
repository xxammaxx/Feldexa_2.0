# T029 Correction: SAVE-008 in Ports and Testkit

- **Task**: T029 second-review follow-up after candidate `0ac8d3f`
- **Date**: 2026-11-15, Europe/Berlin
- **Class**: `NONE` (contract, host-VM tests, and analysis)
- **Result**: `PASS` for the propagation correction and host checks; no runtime
  claim
- **Base revision**: `992d3e14180fa772ec82c9832f235d90bc96965e`
- **Correction commit**: recorded in the external `worker_done` attestation
- **Pre-existing tree state**: `apps/feldexa_app/android/gradlew.bat` was
  modified before this task and remains untouched/uncommitted

## 1. Review finding

The `SAVE-008` split was present in the storage/catalog contracts, but two code
surfaces still described global Keystore failure as aggregate `SAVE-002`:

- `secure_store_port.dart:21-41` and `store_dto.dart:34-35` documented only
  `SAVE-002`/isolated loads;
- `FaultKind.keystoreUnavailable` in `fault_kind.dart:22-26` and
  `fault_hooks_test.dart:364-367` expected `SAVE-002`, although
  `storage-format.md:110` maps global provider unavailability to `SAVE-008`.

`FaultKind.corruptKeyMaterial` remains aggregate-scoped `SAVE-002`; it is not
the global provider case.

## 2. Correction applied

- `secure_store_port.dart` now documents the store-level `keyAvailable` summary
  as potentially false for aggregate `SAVE-002` or global `SAVE-008`, with
  `saveRevision`, `loadDocument`, and `loadTemplate` naming the matching typed
  exception and the aggregate-only load-isolation limit.
- `store_dto.dart` updates `StoreStatus` and `StoredMeta.unreadableReasonCode`
  documentation to the two contexts.
- `FaultKind.keystoreUnavailable` now maps to `SAVE-008` with a global
  description; `FaultKind.corruptKeyMaterial` remains `SAVE-002` with an
  aggregate description.
- The testkit taxonomy test asserts both codes and descriptions.
- The ports DTO test additionally accepts `SAVE-008` as an unreadable reason.

T025/T026 remain the runtime implementation tasks; this change does not add a
storage implementation, change the key architecture, or introduce another
owner decision.

## 3. Relation to the PRIV-001 correction

The PRIV-001 global-reset disclosure was corrected in
`992d3e14180fa772ec82c9832f235d90bc96965e` and remains in this candidate's
history. This report covers only the separate ports/testkit propagation finding.

## 4. Verification

Toolchain: Flutter 3.47.7 (stable), Dart 3.13.5, workspace `pubspec.yaml` and
committed `pubspec.lock`. Logs were console-only and are not retained.

| Command / check | Working directory | Exit | Observed |
| --- | --- | --- | --- |
| `flutter pub get --offline` | repository root | 0 | workspace resolved |
| `flutter test` | `packages/feldexa_ports` | 0 | 108 tests passed, including the SAVE-008 unreadable DTO case |
| `flutter test` | `packages/feldexa_testkit` | 0 | 110 tests passed, including the global/aggregate taxonomy assertion |
| `flutter test` | `apps/feldexa_app` | 0 | 80 tests passed |
| `flutter analyze --no-pub` | repository root | 0 | No issues found |
| Dart formatting check | changed ports/testkit files | 0 | 0 files changed |
| `flutter gen-l10n` | `apps/feldexa_app` | 0 | no generated-file drift |

## 5. Remaining limits

- T025/T026 are unimplemented: global detection, retry, and per-aggregate/global
  presentation remain contract-level; no `EMULATOR` or `DEVICE` proof exists.
- The T023 browser registry check remains `UNAVAILABLE` (no Chrome), unrelated
  to this correction.
- No push, remote merge, or self-review is claimed.

## 6. Review

Reviewer: _(blank; independent review required)_

Date:

Verdict:
