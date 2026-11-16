# T027 host evidence (`NONE`)

**Class**: `NONE` | **Result**: `PASS` (host checks only)
**Date**: 2026-11-16 (Europe/Berlin)
**Task**: issue #27 / T027
**Base**: `origin/main` `15aab0c55c7e77df0d4c4fe199e89c6661ea3db2`
**Candidate code commit**: `5b4c295014bf63bb7f673fc492e40c8bdfe4ddee`
**Merge commit**: `3a3202cc6ad73fa6303587b185be818e4cbbc0ac`
**Branch**: `xxammaxx/feldexa-t027`
**Tree state**: code candidate committed; only the pre-existing unrelated
`apps/feldexa_app/android/gradlew.bat` modification and the ignored local
toolchain/cache directories remained outside the commit.

`NONE` is not a runtime class. This report proves host analysis, formatting, Dart
host tests, and JVM host tests only. Android runtime evidence is in
[2026-11-16-t027-emulator-store-evidence.md](./2026-11-16-t027-emulator-store-evidence.md);
this report must not be aggregated with it.

## 1. Scope

T027 completed the Android thin clients and the native `StoreService` over the T026
`EncryptedStore`/T025 `KeystoreService`. This `NONE` report covers the reproducible
host checks for that change. It does not claim Keystore, MethodChannel, emulator,
device, export-artifact, OCR-quality, or performance behavior.

## 2. Commands and results

Working directory: repository root unless stated. Flutter/Dart were the
workspace-local toolchain copies; Gradle used the workspace-local user home and the
existing Android SDK. The exact commands are recorded in the bound logs below.

| Check | Command | Result |
| --- | --- | --- |
| Analysis | `flutter analyze --no-pub` | `PASS` — “No issues found!” |
| Format | `dart format --output=none --set-exit-if-changed packages apps tools` | `PASS` — 148 files, 0 changed |
| Core | `flutter test` in `packages/feldexa_core` | `PASS` 461/461 |
| Export | `flutter test` in `packages/feldexa_export` | `PASS` 56/56 |
| Ports | `flutter test` in `packages/feldexa_ports` | `PASS` 108/108 |
| Android adapters | `flutter test` in `packages/feldexa_adapters_android` | `PASS` 19/19 |
| Simulated adapters | `flutter test` in `packages/feldexa_adapters_simulated` | `PASS` 97/97 |
| UI | `flutter test` in `packages/feldexa_ui` | `PASS` 17/17 |
| Testkit | `flutter test` in `packages/feldexa_testkit` | `PASS` 154/154 |
| App | `flutter test` in `apps/feldexa_app` | `PASS` 80/80 |
| JVM | `./gradlew :app:testDebugUnitTest` | `PASS` 228/228, 0 failures |

`feldexa_recognition` and `feldexa_application` contain no test directory in this
candidate; the runner reports “no test files” rather than a failed test. That is
unchanged by T027 and is not counted as evidence.

The 228-test JVM suite includes 7 dedicated `StoreServiceTest` cases: stage/create/
load/list/save with identity/head/source/metadata; duplicate create; staged-source
hash mismatch; parented initial revision; expected-head mismatch; wrong delete title;
and startup-recovery reachability.

## 3. Bound artifacts

All paths are repository-relative. The logs are git-ignored local, regenerable
support artifacts, not candidate contents.

| Artifact | Bytes | SHA-256 |
| --- | --- | --- |
| `build/t027-evidence/analyze_final.log` | 97 | `6c698e115ff18ee78533a8740481006ff336c9208e920463e103a5d46b771102` |
| `build/t027-evidence/format_final.log` | 49 | `0c654ab8d38f9b6de3ec5d2deba726b2d7448ffcce2401107fc031ef8448ace3` |
| `build/t027-evidence/gradle-jvm-full-final.log` | 17,838 | `6f4850069b397066a4dae113f1d01b05a145a7daffb93e7b4664423e9be0a26e` |
| `build/t027-evidence/test_logs/feldexa_core.log` | 84,677 | `b11ca23dfd6a15d90ea46416760bde787873d94f57489d9e22a63d3ef9481035` |
| `build/t027-evidence/test_logs/feldexa_export.log` | 11,544 | `279e7a14582fcb14251fa8b6223ddcaebe603abfd9de1b4462595ad3c7a6f789` |
| `build/t027-evidence/test_logs/feldexa_ports.log` | 20,233 | `04ab76fc5793a097ef0545e9a3dca7d986e8a480d6f2f549fbdb59c533076342` |
| `build/t027-evidence/test_logs/adapters_final3.log` | 3,735 | `77c686257889eb6b30910c7c0cb578ba78ae87e044a882983bb11562a8fbeaad` |
| `build/t027-evidence/test_logs/feldexa_adapters_simulated.log` | 20,596 | `3e8e294b4508ade78ef51b064324323543d31c5c583afd6be3ddc7dae9ef404c` |
| `build/t027-evidence/test_logs/feldexa_ui.log` | 1,850 | `bdace5218c1eeb4d07621d559f62adc5dd37e6f4d74e47ded83ec4399b58c659` |
| `build/t027-evidence/test_logs/feldexa_testkit.log` | 28,823 | `a27ad29196ef032a4c15819da830da27d95125ac8a40969ab59744016f6963ba` |
| `build/t027-evidence/test_logs/app_final.log` | 15,552 | `8f37e064bfd20bc5a92f3acb3fea22e7d192262059034d31b5b337d893df3445` |

## 4. Source diff

`git diff --stat 15aab0c..5b4c295`: 38 files changed, 4,800 insertions, 45
deletions. The implementation commit `5b4c295` contains the native service, store and
channel changes, Dart clients/tests, T028 consumer corrections, contracts/tasks, and
the app composition/dependency changes. The unrelated
`apps/feldexa_app/android/gradlew.bat` modification was deliberately not committed.

## 5. Limitations

- Host checks cannot prove Android Keystore, channel, storage, or startup behavior;
  those are in the separate `EMULATOR` report.
- No `DEVICE`, release-build, performance, or acceptance claim.
- Template channel operations remain fail-closed because their payload is still
  unspecified; native import/OCR/export/delivery engines remain future tasks.
- No push, PR, merge, or self-review was performed by the author.
