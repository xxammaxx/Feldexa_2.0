# 2026-11-15 `EMULATOR` — T026 review corrections on Pixel 7 API 35

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` |
| Result | `PASS` |
| Task / issue | `T026` / `#26` |
| Date / timezone | `2026-11-15 Europe/Berlin` |
| Revision | base `d78114fdb703c405fe4692fe287e71095b50fc59`; correction commit `84f2276a4ccf9ae7345a56861cad9d82c1d39e80`; this report, its host companion, the index rows, the task note, and the evidence bundle are the later documentation changes; final candidate SHA in the external attestation |
| External attestation | `worker_done` transport record (candidate SHA, changed files, this report's bytes/SHA-256); not part of the candidate commit |
| Supersedes for the changed code | `2026-11-15-emulator-t026-pixel7-api35-kvm-encrypted-store.md` remains frozen historical evidence for `365b384` |
| Allocation label | `T026-REVIEW-PIXEL7-API35-20261115` (non-sensitive; no raw Orca session or terminal id) |
| Build identity | `versionName 1.0` (`versionCode 1`), `debug`; app APK `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` SHA-256 `0941b1764b39a83953bfb70470227f790df2c279e7ac03596fe90c1f5fb1c32e` (216,359,341 bytes); test APK `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` SHA-256 `82711d4215d6fa24d754f5b26490effec216bf6db8155ff105f2d7768890d8a2` (399,814 bytes) |
| Toolchain | JDK `17.0.20.1` (Temurin); Gradle `9.3.1`; AGP `9.1.0`; Kotlin `2.4.0`; Flutter `3.47.7` (engine `deb287481e3c`); Dart `3.13.5`; Android Emulator `37.2.12.0`; adb `1.0.41` |
| Input | synthetic UUIDv4 ids, random 32-byte DEKs, synthetic JSON/PDF bytes; no corpus or user data |

## 1. Scope

This record re-runs the T026 instrumentation suite after the review
corrections in `84f2276` on an Orca-allocated Pixel 7 API 35 runtime with the
real `AndroidKeyStore`. It covers the original container/commit/delete/sweep
tests plus the new device tests for compare-and-commit serialization, safe
pruning, and equal-timestamp recovery fail-closed behavior.

It is not a `DEVICE`, performance, StrongBox, or silicon key-strength claim.

## 2. Environment

```text
EMULATOR: Pixel 7 profile, API 35 (Android 15), AVD T025_Pixel7_API35_KVM_20261115
          allocation label T026-REVIEW-PIXEL7-API35-20261115
          serial EMULATOR37X2X12X0
          fingerprint google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys
          abi x86_64, hardware ranchu, ro.kernel.qemu=1, sys.boot_completed=1
          package service: found
          guest CPU flags include hypervisor, avx, f16c
          app APK SHA-256 0941b1764b39a83953bfb70470227f790df2c279e7ac03596fe90c1f5fb1c32e
          test APK SHA-256 82711d4215d6fa24d754f5b26490effec216bf6db8155ff105f2d7768890d8a2
```

The AVD is the Pixel 7 / API 35 image provisioned for T025; its image
provenance and hardware-acceleration record remain in
`2026-11-15-emulator-t025-pixel7-api35-kvm-keystore.md`.

### 2.1 Allocation and exclusivity

Before the run, `orca emulator list --worktree all --json` returned
`sessions: []` and `adb devices -l` listed no device. The worktree attached the
AVD through Orca (`attached: true`). During the run exactly one adb device was
present. After the run, Orca shut the device down, the session list returned
`sessions: []`, and adb showed no device. No other emulator or adb device was
read, installed on, or controlled. The redacted allocation record is in
`specs/001-scanned-form-workflow/reports/artifacts/t026-review-2026-11-15/logs/allocation-redacted.json`.

### 2.2 Host-acceleration check

`emulator -accel-check` was `UNAVAILABLE` in the worker sandbox because no
`/dev/kvm` node is exposed. This is not claimed as PASS. The guest reports
`hypervisor`, `avx`, and `f16c`, `ro.kernel.qemu=1`, and uses the
T025-provisioned Pixel 7 API 35 AVD. This record claims the `EMULATOR` runtime
and real `AndroidKeyStore`, not independent host KVM verification.

## 3. Checks

| # | Command (repo root) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `orca emulator list --worktree all --json` (before) | `0` | `build/t026-work/logs/final-orca-sessions-before.json` | `PASS` (`sessions: []`) |
| 2 | `adb devices -l` (before) | `0` | `build/t026-work/logs/final-adb-before.log` | `PASS` (no device) |
| 3 | `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current --json` | `0` | `build/t026-work/logs/final-orca-attach.json` | `PASS` (`attached: true`) |
| 4 | `adb -s emulator-5554 shell getprop sys.boot_completed` | `0` | `build/t026-work/logs/final-device-profile.log` | `PASS` (`1`) |
| 5 | `adb -s emulator-5554 shell service check package` | `0` | `build/t026-work/logs/final-device-profile.log` | `PASS` (`found`) |
| 6 | API/fingerprint/AVD/ABI/CPU flags | `0` | `build/t026-work/logs/final-device-profile.log` | `PASS` (API 35, Pixel 7 image, `x86_64`, hypervisor/avx/f16c) |
| 7 | `adb -s emulator-5554 install -r -t <app APK>` | `0` | `build/t026-work/logs/final-install-app.log` | `PASS` |
| 8 | `adb -s emulator-5554 install -r -t <test APK>` | `0` | `build/t026-work/logs/final-install-test.log` | `PASS` |
| 9 | pull installed APKs and compare SHA-256 | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t026-review-2026-11-15/apk-sha256.txt` | `PASS` (both match) |
| 10 | `am instrument` T026 class | `0` | `build/t026-work/logs/final-instrumentation-t026.log` | `PASS` (`OK (13 tests)`, 8.128 s) |
| 11 | `am instrument` T025+T026 classes | `0` | `build/t026-work/logs/final-instrumentation-both.log` | `PASS` (`OK (25 tests)`, 6.189 s) |
| 12 | logcat FATAL scan | `0` | `build/t026-work/logs/final-logcat-t026.log`, `...both.log` | `PASS` (0 FATAL EXCEPTION) |
| 13 | `orca emulator shutdown --device emulator-5554 --worktree current --json` | `0` | `build/t026-work/logs/final-orca-shutdown.json` | `PASS` |
| 14 | `orca emulator list --worktree all --json` (after) | `0` | `build/t026-work/logs/final-orca-sessions-after.json` | `PASS` (`sessions: []`) |
| 15 | `adb devices -l` (after) | `0` | `build/t026-work/logs/final-adb-after.log` | `PASS` (no device) |
| 16 | host `emulator -accel-check` | — | — | `UNAVAILABLE` (no `/dev/kvm`; not claimed) |

The instrumented APKs were pulled from the guest after installation and matched
the local build hashes byte-for-byte.

## 4. Results

### 4.1 T026 suite — 13/13 PASS

`OK (13 tests)` in 8.128 s:

1. `realKeystoreCreateSaveLoadAndReadBack`
2. `boundarySizesRoundTripOnRealKeystore`
3. `tamperedCiphertextIsSave003OnDevice`
4. `lostAggregateKeyIsSave002WhileSiblingLoads`
5. `everyAliasLostIsGlobalSave008`
6. `deleteRemovesObjectsAndAliasAndSiblingSurvives`
7. `startupSweepRemovesStaleTempAndOrphanAlias`
8. `missingHeadFallsBackToNewestRevisionOnDevice`
9. `injectedFsyncFailureLeavesTheOldHeadReadable`
10. `noPlaintextResidueInTheAggregateDirectory`
11. `parallelSavesSerializeOnDevice` (new: same expected head, one commit wins)
12. `pruneRevisionsKeepsHeadOnDevice` (new: head-protected §3.1 pruning)
13. `equalTimestampRecoveryFailsClosedOnDevice` (new: equal timestamps are
    `SAVE-003` + `ambiguousRevisionOrder`, all files kept)

### 4.2 T025 regression — 25/25 PASS

The combined run executed the T025 `KeystoreServiceInstrumentedTest` and the
T026 suite in one process: `OK (25 tests)` in 6.189 s. This is a regression
signal for the shared `KeystoreService`, not a second T026 result.

### 4.3 Logcat

The post-run logcat files contain zero `FATAL EXCEPTION` lines. The runner
output is the authority for pass/fail.

## 5. Artifacts

| Path | Bytes | SHA-256 |
| --- | ---: | --- |
| `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 216,359,341 | `0941b1764b39a83953bfb70470227f790df2c279e7ac03596fe90c1f5fb1c32e` |
| `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 399,814 | `82711d4215d6fa24d754f5b26490effec216bf6db8155ff105f2d7768890d8a2` |
| `build/t026-work/guest-review/app-debug-installed.apk` | 216,359,341 | `0941b1764b39a83953bfb70470227f790df2c279e7ac03596fe90c1f5fb1c32e` |
| `build/t026-work/guest-review/app-debug-androidTest-installed.apk` | 399,814 | `82711d4215d6fa24d754f5b26490effec216bf6db8155ff105f2d7768890d8a2` |
| `build/t026-work/logs/final-instrumentation-t026.log` | 8,777 | `973f58df8cc0c098ddc2b50bd6dd74601cb254e1a675cb8c171a85609c85cc0b` |
| `build/t026-work/logs/final-instrumentation-both.log` | 16,943 | `1a7ab9f6e6f487c738cfb11a2eeb24972f1351905e4d19ae65ec4a38681fb51f` |
| `build/t026-work/logs/final-device-profile.log` | 260 | `5930b874c0df18754af6616413ed97d573ef71a975183d919460628a0ac691dd` |
| `build/t026-work/logs/final-device-final.log` | 177 | `837031b2975fc1c86c99cda40c0721e14d9e4de4142053e8c12f907d4e6584fa` |
| `build/t026-work/logs/final-orca-attach.json` | 357 | `7631310562d25df55de286064b92e4d69765aea8c1df8a5565daa9e7a931b53a` |
| `build/t026-work/logs/final-orca-shutdown.json` | 208 | `8cddb39bf2baeb216d7ac9508ab0b5cbedd6478e707c985069fb3f35b8e04233` |
| `specs/001-scanned-form-workflow/reports/artifacts/t026-review-2026-11-15/manifest.json` | 7,931 | `b6855645cb04e13ba699068a5363ad70129590a6eb8656b36b72913cc90a2eb9` |

The committed bundle `specs/001-scanned-form-workflow/reports/artifacts/t026-review-2026-11-15/` contains the
redacted copies of the instrumentation and device logs, the JUnit XMLs, the
allocation record, and a manifest that hashes every bundle file. Raw logcat is
not published; only its size, SHA-256, and zero FATAL count are bound.

## 6. Limitations

- No `DEVICE` acceptance, performance measurement, StrongBox, or
  silicon-specific key-strength claim. Emulator timings are not the SC-004
  device claim.
- Host KVM was not independently verified in the worker sandbox
  (`/dev/kvm` unavailable); the guest reports hypervisor/AVX/F16C and uses the
  T025-provisioned Pixel 7 API 35 AVD.
- The AVD was reused from T025 and started through Orca for this run; it was
  shut down and released afterwards.
- Revision retention policy remains open (ownership options in the host
  companion report); T026 provides the head-protected primitive.
- No push, merge, or self-review was performed.

## 7. Reproducibility

1. Build the app and test APKs from `84f2276a4ccf9ae7345a56861cad9d82c1d39e80`
   in debug mode with the toolchain above.
2. Confirm no other Orca emulator session and no adb device.
3. `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current --json`
   and wait for `sys.boot_completed=1` and `service check package` = `found`.
4. Install both APKs with `adb install -r -t`, pull the installed base APKs,
   and compare their SHA-256 with §5.
5. Run the T026 class with `am instrument -w -r`; expected `OK (13 tests)`.
6. Run the T025+T026 classes together; expected `OK (25 tests)`.
7. Capture logcat; expected no `FATAL EXCEPTION`.
8. `orca emulator shutdown --device emulator-5554 --worktree current --json`;
   confirm `sessions: []` and no adb device.
9. Run `specs/001-scanned-form-workflow/reports/artifacts/t026-review-2026-11-15/verify.sh`; expected
   `EVIDENCE VERIFY: OK`.

## 8. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
