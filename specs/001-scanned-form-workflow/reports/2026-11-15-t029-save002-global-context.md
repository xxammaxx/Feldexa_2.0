# T029 Correction: Global Keystore Failure vs Aggregate SAVE-002

- **Task**: T029 second-review follow-up after candidate `ae8237b`
- **Date**: 2026-11-15, Europe/Berlin
- **Class**: `NONE` (contract consistency, host-VM tests, and analysis)
- **Result**: `PASS` for the contract/catalog correction and host checks; no
  runtime claim
- **Base revision**: `41a26c04f678ba5fe4c62aa10d2e9b33cf2e47a0`
- **Correction commit**: recorded in the external `worker_done` attestation
- **Pre-existing tree state**: `apps/feldexa_app/android/gradlew.bat` was
  modified before this task and remains untouched/uncommitted

## 1. Review findings

This correction addresses two related global-error findings:

1. `contracts/storage-format.md` mapped an unavailable Keystore provider to
   `SAVE-002`, but the `SAVE-002` German text claims that other documents and
   templates are unaffected. A global provider outage affects every aggregate.
2. A whole-Keystore/device reset invalidates every alias, but that case was
   only an internal note; the user-facing `SAVE-002` text still implied
   aggregate isolation.

The owner decision (one Keystore KEK per document/template; isolation for
loss/invalidation of one aggregate key) remains unchanged. A global provider
or reset condition is not a per-aggregate key loss and must not reuse that
promise.

The previously reported `StoreStatus.keyAvailable` contradiction was already
corrected in `41a26c0`; this report covers the remaining `SAVE-002` finding.

## 2. Correction applied

- Added `SAVE-008` / `KeystoreUnavailableException` for global Keystore
  provider outage or device-wide key-store reset.
- `SAVE-002` is now explicitly aggregate-scoped: one aggregate key is missing
  while at least one other aggregate key remains available.
- The `SAVE-008` German text states that the device keys are unavailable and
  that all stored documents/templates may be temporarily or permanently
  unopenable. It makes no "other aggregates unaffected" claim.
- `SAVE-008` is retryable for a temporary provider outage and non-retryable
  after a device-wide reset. The same code/message covers both because the
  user message must explain both possibilities.
- `StoreStatus.keyAvailable` remains the non-fatal store-level summary; it does
  not identify scope. `StoredMeta.unreadableReasonCode` and the load exception
  distinguish `SAVE-002` from `SAVE-008`.
- A temporary provider outage is retried once before `SAVE-008`; a whole reset
  is detected as a global condition when the provider is available but no
  stored aggregate key can be unwrapped.

No key architecture, owner decision, German migration, or recovery promise was
changed. No new security decision was made.

## 3. Artifacts updated

- `contracts/error-catalog.de.md`: `SAVE-002` scope; new `SAVE-008` row; notes.
- `apps/feldexa_app/lib/l10n/app_de.arb` and generated l10n: `save008`,
  `save008Recovery`, updated `save002Recovery`.
- `contracts/storage-format.md`: failure mapping, lifecycle, failure table,
  key-loss listing, tests.
- `contracts/ports.md`: `KeystoreUnavailableException`, exception table,
  `StoredMeta`/load/save/status rules.
- `contracts/platform-channel.md`: `storage.status` scope and
  `SAVE-002`/`SAVE-008` reason codes; Keystore test.
- `data-model.md`, `research.md`, `quickstart.md`: aggregate vs global context.
- `packages/feldexa_ports/lib/src/errors.dart` and `test/errors_test.dart`.
- `tasks.md`: CR-12 records the resolution and affected tasks.

## 4. Verification

Toolchain: Flutter 3.47.7 (stable), Dart 3.13.5, workspace `pubspec.yaml` and
committed `pubspec.lock`. Logs were console-only and are not retained.

| Command / check | Working directory | Exit | Observed |
| --- | --- | --- | --- |
| `flutter pub get --offline` | repository root | 0 | workspace resolved |
| `flutter test test/german_strings_test.dart` | `apps/feldexa_app` | 0 | 9 tests passed, including the new SAVE-008 catalog/ARB mapping |
| `flutter test` | `apps/feldexa_app` | 0 | 79 tests passed |
| `flutter test test/errors_test.dart` | `packages/feldexa_ports` | 0 | 18 tests passed, including the SAVE-008 temporary/reset distinction |
| `flutter test` | `packages/feldexa_ports` | 0 | 108 tests passed |
| `flutter test` | `packages/feldexa_testkit` | 0 | 110 tests passed |
| `flutter analyze --no-pub` | repository root | 0 | No issues found |
| Dart formatting check | ports lib/test | 0 | 0 files changed |
| `flutter gen-l10n` | `apps/feldexa_app` | 0 | generated text matches the ARB; no drift |

## 5. Remaining limits

- T025/T026 are unimplemented: global detection, retry behavior, and
  per-aggregate/global presentation are contract-level only; no `EMULATOR` or
  `DEVICE` proof exists.
- A device-wide reset remains unrecoverable; `SAVE-008` only makes the message
  truthful, not the data recoverable.
- The T023 browser registry check remains `UNAVAILABLE` (no Chrome), unrelated
  to this correction.
- No push, remote merge, or self-review is claimed.

## 6. Review

Reviewer: _(blank; independent review required)_

Date:

Verdict:
