# 2026-11-15 `EMULATOR` — T026 Pixel 7 API 35 encrypted-store run

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` |
| Result | `PASS` |
| Task / issue | `T026` / `#26` |
| Date / timezone | `2026-11-15 Europe/Berlin` |
| Revision | base `d78114fdb703c405fe4692fe287e71095b50fc59`; implementation candidate `1361bc6560ba9c6569a4cfdd3154d306c65f20b5`; this report, its companion, the README row, and the `tasks.md` note are the only later changes; final candidate SHA in the external attestation |
| External attestation | `worker_done` transport record (candidate SHA, changed files, this report's bytes/SHA-256); not part of the candidate commit |
| Allocation label | `T026-PIXEL7-API35-20261115` (non-sensitive; no raw Orca session or terminal id) |
| Build identity | `versionName 1.0` (`versionCode 1`), mode `debug`; app APK `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` SHA-256 `8883c5bce2cae6643f5c77b52637b0f9b1183dc12754fe04ed3862e61318ceb1` (216,277,143 bytes); instrumentation test APK `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` SHA-256 `1cc8fcf8701cc1fbd9703bcb7ed025e262228f69ea70c4deca8116917523dfed` (395,491 bytes) |
| Toolchain | JDK `17.0.20.1` (Temurin); Gradle `9.3.1`; Android Gradle Plugin `9.1.0`; Kotlin `2.4.0`; Flutter `3.47.7` (engine `deb287481e3c`); Dart `3.13.5`; Android platform `35`; build-tools `36.0.0`; Android Emulator `37.2.12.0`; adb `1.0.41` |
| Input | synthetic UUIDv4 ids, random 32-byte DEKs, synthetic canonical-JSON payloads, and synthetic PDF bytes; no corpus, user data, real title, or signature |

## 1. Scope

This record answers one question: do the T026 `FXC1` encrypted-store
instrumentation tests pass on an Orca-allocated Pixel 7 API 35 runtime with
the real `AndroidKeyStore`, an exclusive per-run assignment, a completed boot,
a working package service, and in-guest APK identity matching the reviewed
build?

The run covers the FXC1 container round-trip at boundary sizes, the
per-aggregate KEK binding, `SAVE-002`/`SAVE-003`/`SAVE-008`, atomic commit and
read-back, deletion, the startup stale-temp/orphan-alias sweep, head fallback,
native fsync-fault behavior, and the absence of plaintext residue. It does not
claim `DEVICE` acceptance, performance, StrongBox, or silicon-specific key
strength.

## 2. Revision and build

The source tree was clean at implementation candidate
`1361bc6560ba9c6569a4cfdd3154d306c65f20b5` before the emulator run. The two
APKs were built from that revision:

- app APK `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk`,
  216,277,143 bytes, SHA-256
  `8883c5bce2cae6643f5c77b52637b0f9b1183dc12754fe04ed3862e61318ceb1`;
- test APK `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk`,
  395,491 bytes, SHA-256
  `1cc8fcf8701cc1fbd9703bcb7ed025e262228f69ea70c4deca8116917523dfed`.

Both files were pulled back from the guest after installation and matched these
hashes byte-for-byte (`build/t026-work/guest/app-debug-installed.apk`,
`build/t026-work/guest/app-debug-androidTest-installed.apk`).

### 2.1 Superseded attempt

An earlier test-APK build had SHA-256
`fa23235be360772c184bb2e666fb05b4dc604bb5025feb68b5358ba958bb9b3c`. Its run
executed 10 tests with 1 failure in
`lostAggregateKeyIsSave002WhileSiblingLoads`: the test asserted the sibling
title `Zweites` while the helper had created it with the default `Dokument`.
That was a test-only assertion error; no production code changed. The test was
corrected, the test APK was rebuilt (`1cc8...`), and the PASS below is on the
rebuilt APK. The failed first-run log was overwritten by the rerun and is not
claimed as evidence.

## 3. Environment

```text
EMULATOR: Pixel 7 profile, API 35 (Android 15), AVD T025_Pixel7_API35_KVM_20261115
          allocation label T026-PIXEL7-API35-20261115
          serial EMULATOR37X2X12X0
          fingerprint google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys
          abi x86_64, hardware ranchu, ro.kernel.qemu=1, sys.boot_completed=1
          package service: found
          guest CPU flags include hypervisor, avx, f16c
          app APK SHA-256 8883c5bce2cae6643f5c77b52637b0f9b1183dc12754fe04ed3862e61318ceb1
          test APK SHA-256 1cc8fcf8701cc1fbd9703bcb7ed025e262228f69ea70c4deca8116917523dfed
```

The AVD is the Pixel 7 / API 35 image provisioned for T025; its image
provenance and hardware-acceleration record remain in
`2026-11-15-emulator-t025-pixel7-api35-kvm-keystore.md`. This run did not create
or adopt a second device and did not modify another worktree.

### 3.1 Allocation and exclusivity

At the pre-run inventory, `orca emulator list --worktree all --json` returned
`sessions: []` and `adb devices -l` listed exactly one device,
`emulator-5554`, which was the Pixel 7 API 35 AVD already booted from a prior
run without a worktree session. The worktree then attached that AVD through
Orca (`orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current
--json`, `attached: true`). During the run, `adb devices -l` still listed
exactly one device. After the run, Orca shut the device down, the session list
returned `sessions: []`, and adb showed no device once shutdown completed.
No other emulator or adb device was read, installed on, or controlled.

The pre-existing package pair was installed from an earlier run and had
different signing identities, so the update install was rejected
(`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). The pair was pulled and hashed first
(`build/t026-work/guest/pre-t026-app.apk` 225,292,375 bytes,
`0e99ae2ad3b3c2d404671c52f0e99848821ea6465164583a068d32017784bb1f`;
`build/t026-work/guest/pre-t026-test.apk` 499,184 bytes,
`08e688ef503d8a1ca12332578ff94a852a2c248de103238b284c76336f1069ba`), then
uninstalled from this exclusively attached device and replaced with the T026
APKs. No other package was removed.

### 3.2 Host-acceleration check

`emulator -accel-check` was `UNAVAILABLE` in the worker sandbox because the
sandbox exposes no `/dev/kvm` node; it is not claimed as PASS. The guest
reported `hypervisor`, `avx`, and `f16c` CPU flags and the read-only AVD is the
same KVM-provisioned Pixel 7 API 35 AVD recorded by T025. This record therefore
claims the `EMULATOR` runtime and real `AndroidKeyStore`, not independent host
KVM verification.

## 4. Checks

| # | Command (repo root) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `orca emulator devices --json` (before) | `0` | `build/t026-work/logs/t026-api35-orca-devices-before.json` | `PASS` |
| 2 | `orca emulator list --worktree all --json` (before) | `0` | `build/t026-work/logs/t026-api35-orca-sessions-before.json` | `PASS` (`sessions: []`) |
| 3 | `adb devices -l` (before) | `0` | `build/t026-work/logs/t026-api35-adb-before.log` | `PASS` (one device) |
| 4 | `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current --json` | `0` | `build/t026-work/logs/t026-api35-orca-attach.json` | `PASS` (`attached: true`) |
| 5 | `adb -s emulator-5554 shell getprop sys.boot_completed` | `0` | `build/t026-work/logs/t026-api35-device-profile.log` | `PASS` (`1`) |
| 6 | `adb -s emulator-5554 shell service check package` | `0` | `build/t026-work/logs/t026-api35-device-profile.log` | `PASS` (`found`) |
| 7 | `adb -s emulator-5554 shell getprop ro.build.version.sdk` / fingerprint / AVD / ABI | `0` | `build/t026-work/logs/t026-api35-device-profile.log` | `PASS` (API 35, Pixel 7 image, `x86_64`) |
| 8 | `adb -s emulator-5554 install -r -t <app APK>` | `0` | `build/t026-work/logs/t026-api35-install-app.log` | `PASS` |
| 9 | `adb -s emulator-5554 install -r -t <test APK>` | `0` | `build/t026-work/logs/t026-api35-install-test2.log` | `PASS` |
| 10 | pull installed base APKs and compare SHA-256 | `0` | `build/t026-work/logs/t026-api35-pm-path.log` | `PASS` (both hashes match) |
| 11 | `adb -s emulator-5554 shell am instrument -w -r -e class de.feldexa.app.storage.EncryptedStoreInstrumentedTest de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner` | `0` | `build/t026-work/logs/t026-api35-instrumentation.log` | `PASS` (`OK (10 tests)`) |
| 12 | same runner with `KeystoreServiceInstrumentedTest,EncryptedStoreInstrumentedTest` | `0` | `build/t026-work/logs/t026-api35-instrumentation-both.log` | `PASS` (`OK (22 tests)`) |
| 13 | `adb -s emulator-5554 logcat -d -v threadtime` and FATAL scan | `0` | `build/t026-work/logs/t026-api35-logcat-both.log` | `PASS` (0 FATAL EXCEPTION) |
| 14 | `orca emulator shutdown --device emulator-5554 --worktree current --json` | `0` | `build/t026-work/logs/t026-api35-shutdown.json` | `PASS` |
| 15 | `orca emulator list --worktree all --json` (after) | `0` | `build/t026-work/logs/t026-api35-orca-sessions-after.json` | `PASS` (`sessions: []`) |
| 16 | `adb devices -l` (after shutdown) | `0` | `build/t026-work/logs/t026-api35-adb-after.log` | `PASS` (no device) |
| 17 | host `emulator -accel-check` | — | — | `UNAVAILABLE` (no `/dev/kvm` in worker sandbox; not claimed) |

## 5. Results

### 5.1 T026 instrumentation

`OK (10 tests)` in 3.377 s. The executed tests were:

1. `realKeystoreCreateSaveLoadAndReadBack` — real Keystore create, explicit save,
   head/revision/source read-back, no master alias.
2. `boundarySizesRoundTripOnRealKeystore` — `1`, `65,535`, `65,536`, and
   `1,048,577`-byte sources round-trip byte-identically.
3. `tamperedCiphertextIsSave003OnDevice` — a flipped ciphertext byte is
   `CorruptDataException` (`SAVE-003`).
4. `lostAggregateKeyIsSave002WhileSiblingLoads` — one deleted aggregate alias is
   `SAVE-002`; the sibling document still loads.
5. `everyAliasLostIsGlobalSave008` — deleting every aggregate alias is
   `KeystoreUnavailableException` (`SAVE-008`), not `SAVE-002`.
6. `deleteRemovesObjectsAndAliasAndSiblingSurvives` — objects and directory are
   removed, the alias is removed last, the sibling survives.
7. `startupSweepRemovesStaleTempAndOrphanAlias` — stale temp and an orphan alias
   are removed.
8. `missingHeadFallsBackToNewestRevisionOnDevice` — the newest verifiable
   revision is adopted (`fellBackToOlderRevision`).
9. `injectedFsyncFailureLeavesTheOldHeadReadable` — an injected fsync failure is
   `StorageWriteException` (`SAVE-003`) and the previous head stays readable.
10. `noPlaintextResidueInTheAggregateDirectory` — no `%PDF-`, title, or marker
    plaintext appears in the aggregate files.

### 5.2 T025 regression in the same runtime

The combined run executed the T025 `KeystoreServiceInstrumentedTest` and the
T026 suite in one instrumentation process: `OK (22 tests)`. This is a
regression signal for the shared `KeystoreService`, not a second T026 result.

### 5.3 Logcat

The post-run logcat (`build/t026-work/logs/t026-api35-logcat-both.log`,
74,649 bytes) contains zero `FATAL EXCEPTION` lines and no test failure. The
suite itself is the authority for the pass/fail result.

## 6. Limitations

- No `DEVICE` acceptance, performance measurement, StrongBox, or
  silicon-specific key-strength claim. Emulator timings are not the SC-004
  three-second device claim.
- Host KVM was not independently verified in the worker sandbox
  (`/dev/kvm` unavailable); the guest reports hypervisor/AVX/F16C and uses the
  T025 KVM-provisioned Pixel 7 API 35 AVD.
- The AVD was reused from T025 and was already booted before attach; this run
  attached it exclusively through Orca, replaced the prior package pair, and
  shut it down afterwards.
- The T026 suite covers the named T026 scope; revision pruning (`§3.1` step 8)
  and export-artifact cleanup (`§4` step 4) remain with their separate owners.
  Signature-reference discovery for `§4` step 3 is a T031 input.
- No self-review, push, or merge was performed by the author.

## 7. Artifacts

| Path | Bytes | SHA-256 |
| --- | ---: | --- |
| `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 216,277,143 | `8883c5bce2cae6643f5c77b52637b0f9b1183dc12754fe04ed3862e61318ceb1` |
| `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 395,491 | `1cc8fcf8701cc1fbd9703bcb7ed025e262228f69ea70c4deca8116917523dfed` |
| `build/t026-work/guest/app-debug-installed.apk` | 216,277,143 | `8883c5bce2cae6643f5c77b52637b0f9b1183dc12754fe04ed3862e61318ceb1` |
| `build/t026-work/guest/app-debug-androidTest-installed.apk` | 395,491 | `1cc8fcf8701cc1fbd9703bcb7ed025e262228f69ea70c4deca8116917523dfed` |
| `build/t026-work/guest/pre-t026-app.apk` | 225,292,375 | `0e99ae2ad3b3c2d404671c52f0e99848821ea6465164583a068d32017784bb1f` |
| `build/t026-work/guest/pre-t026-test.apk` | 499,184 | `08e688ef503d8a1ca12332578ff94a852a2c248de103238b284c76336f1069ba` |
| `build/t026-work/logs/t026-api35-orca-devices-before.json` | 1,850 | `22c118cd84c438246e60eb6b6c766a402a6cb5914a6c6f699f68ad9a13b1344e` |
| `build/t026-work/logs/t026-api35-orca-sessions-before.json` | 177 | `bf038acca46c11255d51bdfee3111267e93527651b48aba86f0f8e6b7292fb92` |
| `build/t026-work/logs/t026-api35-adb-before.log` | 140 | `54d441009efe1a98a08b9ef2fb9e61d2187a2cce7c6d6077a1e520fcfd6ae36e` |
| `build/t026-work/logs/t026-api35-orca-attach.json` | 357 | `4dd218d9be76b088619d8e7299fcf874d43c5e8fb3bd3642cb2f3cb01a532c70` |
| `build/t026-work/logs/t026-api35-device-profile.log` | 256 | `25a80074ecef2d1805c0e440e73c28ff03864351904c2fc140fc8442e5ca7b58` |
| `build/t026-work/logs/t026-api35-device-final.log` | 222 | `e33b02e979497657f8b96966b2e7fc886a17da931f150dcd0f63fe837fd89a22` |
| `build/t026-work/logs/t026-api35-install-app.log` | 36 | `781a31c82430c97897af612ece5e0ca2205e301cb5ff121ce2660541ea5182c7` |
| `build/t026-work/logs/t026-api35-install-test2.log` | 36 | `781a31c82430c97897af612ece5e0ca2205e301cb5ff121ce2660541ea5182c7` |
| `build/t026-work/logs/t026-api35-pm-path.log` | 193 | `ebd91e051733d98dc03b5c95844e608bda6ff7ca620365474baa1585b5431293` |
| `build/t026-work/logs/t026-api35-instrumentation.log` | 6,806 | `283706c3df63c0f8981bce303bd5b097adfe6614f5cb826030654bbed1a47b9c` |
| `build/t026-work/logs/t026-api35-instrumentation-both.log` | 14,972 | `a22347e65847e1b8ddfa888ec7fac3d5a949ff2c1fbef9681c9ee4079f5c8f2b` |
| `build/t026-work/logs/t026-api35-logcat.log` | 79,975 | `f08d719427c1b407d8acf688467e2bea6d8f95910f790e53398a8fd621be825b` |
| `build/t026-work/logs/t026-api35-logcat-both.log` | 74,649 | `c7abe570901318012334c14104b230196ca41d3a0bb89dfa8e223cd0e9017151` |
| `build/t026-work/logs/t026-api35-adb-during.log` | 140 | `54d441009efe1a98a08b9ef2fb9e61d2187a2cce7c6d6077a1e520fcfd6ae36e` |
| `build/t026-work/logs/t026-api35-orca-devices-after-run.json` | 1,850 | `86cb59c80ce0bb113547c0ea88100c3513d8d3eb730ebba1ae3672ed1b8d1d9f` |
| `build/t026-work/logs/t026-api35-shutdown.json` | 208 | `f43129a5178505306fd52c93e4649f497be3c54b5dbea0eb0d008a04c13e4609` |
| `build/t026-work/logs/t026-api35-orca-sessions-after.json` | 177 | `ed9f5b3f50cee4e82a00fa92a2ba7518db155ce0e756066c013e173a60b90d56` |
| `build/t026-work/logs/t026-api35-adb-after.log` | 26 | `36f15c2fe32964a6fbe902e914a47739d4e6304b0d3e812bf08096ff0419b7ae` |

The report itself and the companion host report are omitted; their bytes and
SHA-256 are recorded in the external attestation. `build/t026-work/` is local,
git-ignored support output, not candidate content.

## 8. Reproducibility

1. Build the app and test APKs from implementation candidate `1361bc6` in debug
   mode with the toolchain in §1.
2. Confirm no other Orca emulator session and no second adb device.
3. `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current --json`
   and wait for `sys.boot_completed=1` and `service check package` = `found`.
4. Install both APKs with `adb install -r -t`, pull the installed base APKs,
   and compare their SHA-256 with §2.
5. Run the T026 class with `am instrument -w -r`; expected `OK (10 tests)`.
6. Run the T025+T026 classes together; expected `OK (22 tests)`.
7. Capture logcat; expected no `FATAL EXCEPTION`.
8. `orca emulator shutdown --device emulator-5554 --worktree current --json`;
   confirm `sessions: []` and no adb device.
9. Cleanup: the git-ignored `build/t026-work/` area is local and not candidate
   content.

## 9. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
