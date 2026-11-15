# 2026-11-15 EMULATOR — T025 isolated API 31 runtime evidence

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` |
| Result | `PASS` |
| Task / issue | `T025` / `#25` |
| Date / timezone | `2026-11-15 12:32 Europe/Berlin` |
| Revision | base commit `3a96054a1bd1e40b20f9c43606ace8aa6542748c`; tree `dirty` `specs/001-scanned-form-workflow/tasks.md` SHA-256 `a3af43b7bbf6015183268ab257c8bf9a7746d134c1c7b6b7e1649770493623a6`; `specs/001-scanned-form-workflow/reports/README.md` SHA-256 `809f0387a884a54846f69b3e0d82adf357534bc16e905127bdca1375b942d9ef`; candidate SHA in external attestation |
| External attestation | worker_done transport attestation (candidate SHA, report bytes and hash); not part of the candidate commit |
| Build identity | debug app APK `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` SHA-256 `672b15363d2eeb415a15e8f2e7999b716f4263a96807e4bdddaeb7fe3ab88077`; instrumentation test APK `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` SHA-256 `ddf7284644361e0f7afdb10f704062230fd9f2e157e5348ebbb312d68b23e9d3`; build mode `debug` |
| Toolchain | Flutter 3.47.7 (stable), Dart 3.13.5, Gradle 9.3.1, Android Gradle Plugin 9.1.0, Kotlin 2.4.0, Temurin JDK 17.0.21, Android emulator 37.2.12.0, Android SDK 36 |
| Input | no corpus; synthetic UUIDv4 aggregate ids and random 32-byte DEKs only; no user data |

## 1. Scope

This report records a real `EMULATOR` run of the T025 testnamespace-isolated
instrumentation suite after both reviews of `3a96054` passed. The suite was
executed on an already installed API 31 AVD copied into the gitignored work
area, started read-only on a private port with software TCG. No foreign state
was wiped, deleted, or adopted; no production Keystore alias was addressed.
The named Pixel 7/API 35 profile and physical `DEVICE` acceptance remain open.

## 2. Revision and build

Base is `3a96054a1bd1e40b20f9c43606ace8aa6542748c`. The dirty tree contains
only this report, its index row, and the T025 status note. No production code
or contract file was changed by this run.

The app and test APKs are the committed debug artifacts from that candidate;
their SHA-256 values are in the metadata and artifacts tables. The candidate
SHA is recorded externally; this report does not assert it.

## 3. Environment

```text
EMULATOR: requested Pixel 7 API 35 profile unavailable; actual exclusive allocation
          label t025-api31-5580: AVD Feldexa_API31 (isolated read-only copy),
          system image google_apis/x86_64 Android 12 API 31, RAM 3072 MB,
          2 vCPU, software TCG (-no-accel), GPU swiftshader_indirect, unique
          port 5580; app APK SHA-256 672b15363d2eeb415a15e8f2e7999b716f4263a96807e4bdddaeb7fe3ab88077,
          test APK SHA-256 ddf7284644361e0f7afdb10f704062230fd9f2e157e5348ebbb312d68b23e9d3;
          build mode debug.
```

Actual device identity recorded during the run:

```text
sdk=31 release=12 abi=x86_64 model=sdk_gphone64_x86_64
fingerprint=google/sdk_gphone64_x86_64/emulator64_x86_64_arm64:12/SE1A.220826.008/10564458:userdebug/dev-keys
```

The requested Pixel 7 API 35 profile was not available; this run does not claim
it. The host has no KVM device node, so the emulator used QEMU TCG software
execution.

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `gradle -p apps/feldexa_app/android :app:testDebugUnitTest` (`.`) | `0` | `build/t025-work/logs/t025-safe-emulator-jvm.log` | `PASS` |
| 2 | `adb -s emulator-5580 shell am instrument -w -r de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner` (`.`) | `0` | `build/t025-work/logs/t025-safe-emulator-instrumentation.log` | `PASS` |
| 3 | `adb -s emulator-5580 shell getprop` (`.`) | `0` | `build/t025-work/logs/t025-safe-emulator-device.log` | `PASS` |

Check 1 is the host JVM suite (40 Keystore tests plus 3 static alias-safety
tests). Check 2 is the real Android instrumentation run. Check 3 records the
actual API 31 device identity.

## 5. Results

### 5.1 Safe provisioning

- `adb devices` was empty before the run; no foreign device was adopted.
- The AVD was copied from the installed `Feldexa_API31` AVD into the
  gitignored work area; the original AVD was not modified.
- The copy was started with `-read-only -no-snapshot -no-accel -gpu
  swiftshader_indirect -cores 2 -memory 3072 -port 5580`. No `-wipe-data`,
  no snapshot write, no snapshot restore, and no shared port were used.
- The guest booted in 656,556 ms and remained stable; the package service was
  present before installation.
- The app and test APKs were installed from their committed debug artifacts.
  The test APK was installed with the host-path form of `adb install`; no
  production package data was removed.
- After the run, `adb emu kill` stopped the guest and `adb devices` returned to
  empty.

### 5.2 Instrumentation result

The suite reported:

```text
Time: 54.096
OK (12 tests)
```

All 12 T025 scenarios passed:

| Test | Result |
| --- | --- |
| `realKeystoreWrapUnwrapRoundTripAndNoMasterAlias` | PASS |
| `providerGeneratesFreshTwelveByteIvForEveryWrap` | PASS |
| `keyIsNonExportableAndDoesNotRequireUserAuthentication` | PASS |
| `eachAggregateUsesItsOwnDistinctAlias` | PASS |
| `oneLostAliasIsAggregateSave002AndSiblingsStillLoad` | PASS |
| `deletingEveryAliasIsGlobalSave008` | PASS |
| `createIsIdempotentAgainstTheRealKeystore` | PASS |
| `deleteRemovesOnlyTheTargetAlias` | PASS |
| `sweepRemovesOnlyAliasesWithoutAnAggregateDirectory` | PASS |
| `storeStatusReportsPerAggregateAndGlobalCases` | PASS |
| `testAliasesAreIsolatedFromProductionAliases` | PASS |
| `cleanupDoesNotDeleteForeignTestAlias` | PASS |

The isolation regressions are part of this real run:
`testAliasesAreIsolatedFromProductionAliases` confirms the physical alias is
under `feldexa.test.v1.` and the production alias was not created;
`cleanupDoesNotDeleteForeignTestAlias` creates a foreign test alias, runs the
exact-only cleanup, and confirms the foreign alias survives before explicitly
deleting that test-owned alias. No production alias is enumerated or deleted.

### 5.3 Host suite

`:app:testDebugUnitTest` passed 43/43: 40 `KeystoreServiceTest` tests and 3
`InstrumentedKeystoreAliasSafetyTest` static isolation tests.

### 5.4 Gate status

T025 now has real `EMULATOR` evidence on API 31 google_apis x86_64 under TCG.
This is not the named Pixel 7/API 35 profile and not a physical `DEVICE` run;
those acceptance gates remain open. The emulator timings are not used for any
performance claim.

## 6. Performance

No performance claim. The reported `Time: 54.096` is the instrumentation test
execution time under software TCG, not a product performance measurement.

## 7. Limitations

- The run used API 31 google_apis x86_64, not the named Pixel 7/API 35 profile.
  The report marks Pixel 7/API 35 only as the unavailable requested profile.
- Software TCG is much slower than KVM; it is sufficient for the Keystore
  lifecycle suite but not for performance claims.
- No physical `DEVICE` acceptance is claimed.
- The run installed the debug app/test APKs into a read-only emulator copy; it
  did not exercise a release build.
- The T025 suite covers the Keystore service only, not T026 store integration or
  the full product journey.
- The original AVD, other AVDs, worktrees, and production Keystore aliases were
  not modified or deleted.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| debug app APK | `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 216211073 | `672b15363d2eeb415a15e8f2e7999b716f4263a96807e4bdddaeb7fe3ab88077` |
| instrumentation test APK | `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 376065 | `ddf7284644361e0f7afdb10f704062230fd9f2e157e5348ebbb312d68b23e9d3` |
| instrumentation output | `build/t025-work/logs/t025-safe-emulator-instrumentation.log` | 8236 | `e9381665e1cc5efa387b2cae862cf4c594be013800905a4714240a4234e33af6` |
| device identity log | `build/t025-work/logs/t025-safe-emulator-device.log` | 280 | `b989e88b5a0b4e8f181e79399bafdb481634855009cd399d67aeab2e65e34ed9` |
| emulator boot/run log | `build/t025-work/logs/emulator-api31-tcg.log` | 9850 | `9924a68c4f2d3f79b5fa546638bc541db69e7190b058941bcca45fdc4eaf0b3c` |
| JVM test log | `build/t025-work/logs/t025-safe-emulator-jvm.log` | 16266 | `b30ffd3f7517e362160582111c641cb58e3bd05f7a97a0fd89ab05c8555152b2` |
| Keystore unit-test XML | `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.KeystoreServiceTest.xml` | 5973 | `35369161a30402aa6053e6eb766477983b35e44d4702ac914365d1c0eeb2d077` |
| alias-safety unit-test XML | `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.InstrumentedKeystoreAliasSafetyTest.xml` | 803 | `f81b83615d5c033c932f2339bc31dbada94ea0fa0e5f8f19ee78c13919757ce5` |

Git-ignored logs are local support artifacts and are not candidate contents.
This report is intentionally not listed in its own artifacts table.

## 9. Reproducibility

1. Start from base commit `3a96054a1bd1e40b20f9c43606ace8aa6542748c`.
2. Copy the installed `Feldexa_API31` AVD into a gitignored work directory;
   update the copied `.ini` path. Do not modify the original AVD and do not
   wipe it.
3. Start the copy with:
   `emulator -avd Feldexa_API31 -no-window -no-audio -no-boot-anim
   -no-snapshot -read-only -no-accel -gpu swiftshader_indirect -no-metrics
   -cores 2 -memory 3072 -port 5580`.
4. Wait for `sys.boot_completed=1` and a present package service. Confirm
   `adb devices` shows only `emulator-5580`.
5. Install the committed debug artifacts:
   `adb -s emulator-5580 install -r -t apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk`
   and the instrumented test APK from its host path.
6. Run:
   `adb -s emulator-5580 shell am instrument -w -r
   de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner`.
   Expected: `OK (12 tests)`.
7. Run the host suite:
   `gradle -p apps/feldexa_app/android :app:testDebugUnitTest`.
   Expected: 43 tests, 0 failures.
8. Stop the guest with `adb -s emulator-5580 emu kill`; confirm `adb devices`
   is empty. Delete only the gitignored work copy.

## 10. External attestation

The `worker_done` transport record is the external attestation: it names the
exact candidate SHA, this report's bytes and SHA-256, and the T025 task and
dispatch identity. No separate attestation ref was created or pushed. The
candidate commit contains this report; it therefore cannot contain its own
SHA-256.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
