# 2026-11-15 EMULATOR — T024 Main integration and platform-channel instrumentation

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` |
| Result | `PASS` |
| Task / issue | `T024` / `#24` |
| Date / timezone | `2026-11-15 16:22 Europe/Berlin` |
| Revision | base commit `2a3797bed8cfe5c0f1036063ec31ca2d60592dea` (merge of T024 candidate `8d4821f975229fac955b0a16622adc832d74311d` and Main `d78114fdb703c405fe4692fe287e71095b50fc59`); tree dirty: `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/FeldexaPluginInstrumentedTest.kt` SHA-256 `bcf393c4e4e3c79ec4153bc1476aebe11fcdb4144b1d85d08a09e72e001a4931`; the pre-existing `apps/feldexa_app/android/gradlew.bat` line-ending state is local tooling noise and excluded; candidate SHA in external attestation |
| External attestation | `refs/heads/t024-attestation` (local, not pushed) plus the `worker_done` transport record; they record the candidate SHA, this report's bytes and SHA-256, and the changed-file list |
| Build identity | versionName `1.0` (versionCode `1`), mode `debug`; app `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` 225292375 bytes SHA-256 `0e99ae2ad3b3c2d404671c52f0e99848821ea6465164583a068d32017784bb1f`; instrumentation test `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` 499184 bytes SHA-256 `08e688ef503d8a1ca12332578ff94a852a2c248de103238b284c76336f1069ba` |
| Toolchain | Flutter `3.47.7` (framework `abaf9c5237`), Dart `3.13.5`, Gradle wrapper `9.3.1`, Kotlin `2.4.0`, JetBrains Runtime `21.0.11`, Android SDK platform `36`/build-tools `35`, Android Emulator `37.2.12.0`, adb `1.0.41` (`37.0.1`) |
| Input | no corpus; synthetic UUIDv4 aggregate ids, in-memory fake services, and synthetic OCR bytes only; no user document, Keystore, file, URI, or device data |

## 1. Scope

This record answers two questions:

1. Was the actual Main state `d78114f` integrated into the verified T024
   candidate `8d4821f` without rewriting history, with T025 preserved?
2. Do the T024 platform-channel scenarios required by
   `contracts/platform-channel.md` §12 pass on the Orca-allocated Pixel 7 API 35
   runtime, and does the preserved T025 Keystore suite still pass on the same
   merged tree?

The run covers the T024 `FeldexaPlugin` MethodChannel/EventChannel facade
(FR-001, FR-013, FR-095) and re-runs the T025 Keystore instrumentation as a
regression check. It does not claim a live Dart-engine end-to-end journey,
physical-device behavior, or performance.

## 2. Revision and build

The integration is a normal merge commit with first parent
`8d4821f975229fac955b0a16622adc832d74311d` and second parent
`d78114fdb703c405fe4692fe287e71095b50fc59`. No cherry-pick, rebase, amend, or
history rewrite was used.

Two files conflicted and were resolved minimally:

- `apps/feldexa_app/android/app/build.gradle.kts`: kept the T024 host-JVM test
  dependency and both T025 instrumentation dependencies;
- `specs/001-scanned-form-workflow/tasks.md`: kept T024 `[x]` and the complete
  T025 `[x]` text from Main.

`specs/001-scanned-form-workflow/reports/README.md` auto-merged. T025 source,
instrumentation, reports, contract changes, and task marker are present in the
merged tree. The merge audit is
`build/t024-merge/logs/t024-merge-audit.log`.

The merged tree was built with the pinned Gradle wrapper and the workspace-local
toolchain shadows. `:app:testDebugUnitTest`, `:app:assembleDebug`, and
`:app:assembleDebugAndroidTest` succeeded. The final test APK contains both
`FeldexaPluginInstrumentedTest` and `KeystoreServiceInstrumentedTest`; the debug
app APK contains `Lde/feldexa/app/FeldexaPlugin;` in `classes10.dex`.

## 3. Environment

```text
EMULATOR: Pixel 7 API 35, exclusive allocation T025-PIXEL7-API35-KVM-20261115;
          system image system-images;android-35;google_apis;x86_64 revision 9;
          build fingerprint google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys;
          RAM 3072 MB; app APK apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk SHA-256 0e99ae2ad3b3c2d404671c52f0e99848821ea6465164583a068d32017784bb1f;
          build mode debug, no rebuild during the run.
```

Before the device action, `orca emulator list --worktree all` returned no
sessions, `orca emulator devices` showed every AVD `shutdown`, and
`adb devices -l` listed no device. Exactly one Orca session for this T024
worktree and exactly one adb device (`emulator-5554`) were observed before,
during, and after the run; every other AVD stayed `shutdown`. The guest reported
`ro.boot.qemu.avd_name=T025_Pixel7_API35_KVM_20261115`, API 35, Android 15,
`sys.boot_completed=1`, and `service check package` found.

`kvm-clock` was the active guest clocksource and `kvm-clock tsc hpet` were
available; guest CPU flags included `avx`, `f16c`, and `hypervisor`. Root adbd
was enabled only to read that read-only clocksource evidence and was disabled
again before installation.

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `git merge --no-ff origin/main` (repo root) | `0` | console only (not retained) | `PASS` |
| 2 | `git log -1 --format='%H %P %s'` and `git diff --name-status origin/main..HEAD` (repo root) | `0` | `build/t024-merge/logs/t024-merge-audit.log` | `PASS` |
| 3 | `./gradlew --no-daemon -Dorg.gradle.java.home=$JAVA_HOME :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest` (`apps/feldexa_app/android`) | `0` | `build/t024-merge/logs/gradle-merge-build3.log` | `PASS` |
| 4 | `./gradlew --no-daemon -Dorg.gradle.java.home=$JAVA_HOME :app:assembleDebugAndroidTest` after the test-only fix (`apps/feldexa_app/android`) | `0` | `build/t024-merge/logs/gradle-androidtest-rebuild2.log` | `PASS` |
| 5 | aggregate `TEST-*.xml` under `apps/feldexa_app/build/app/test-results/testDebugUnitTest` (repo root) | `0` | `build/t024-merge/logs/t024-unit-tests.log` | `PASS` |
| 6 | `dexdump` scan of both APKs (repo root) | `0` | `build/t024-merge/logs/t024-dex-check.log` | `PASS` |
| 7 | `orca emulator list --worktree all --json`, `orca emulator devices --json`, `adb devices -l` (repo root) | `0` | `build/t024-merge/logs/t024-exclusivity-before.log` | `PASS` |
| 8 | `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current --json` (repo root) | `0` | `build/t024-merge/logs/t024-orca-attach.json` | `PASS` |
| 9 | `adb -s emulator-5554 shell getprop sys.boot_completed`, `service check package`, API/AVD properties (repo root) | `0` | console only (not retained) | `PASS` |
| 10 | `adb -s emulator-5554 shell` read of the guest `current_clocksource` and CPU-flags pseudo-files (sysfs/procfs) (repo root) | `0` | `build/t024-merge/logs/t024-device-evidence-root.log` | `PASS` |
| 11 | `adb -s emulator-5554 install -r -t` app and test APKs, then `am instrument -w -r de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner` (repo root) | `0` | `build/t024-merge/logs/t024-instrumentation-final.log` | `PASS` |
| 12 | `orca emulator shutdown --device emulator-5554 --worktree current --json`, then session/device/AVD verification (repo root) | `0` | `build/t024-merge/logs/t024-shutdown-clean.log` | `PASS` |

Check 9's live property output is recorded in the final instrumentation log's
device identity and in the environment block; it was not written to a separate
file.

## 5. Results

### 5.1 Integration

The merged tree has parents `8d4821f` and `d78114f` and is three commits ahead of
Main in content only through T024 files and reports; no T025 code, test, contract,
report, or task marker was removed. Conflict resolution was limited to the two
files named in §2. T024 remains `[x]`; T025 remains `[x]` with its Pixel 7 API 35
KVM evidence note.

### 5.2 Host checks

- `:app:testDebugUnitTest`: 131 tests, 0 failures, 0 errors, 0 skipped
  (`FeldexaPluginTest` 88, `KeystoreServiceTest` 40,
  `InstrumentedKeystoreAliasSafetyTest` 3).
- `:app:assembleDebug` and `:app:assembleDebugAndroidTest`: `BUILD SUCCESSFUL`.
- App DEX contains `de.feldexa.app.FeldexaPlugin`; test DEX contains both
  `de.feldexa.app.FeldexaPluginInstrumentedTest` and
  `de.feldexa.app.storage.KeystoreServiceInstrumentedTest`.
- The pulled installed app and test base APKs matched the local APK files
  byte-for-byte (`0e99ae2a…` and `08e688ef…`).

### 5.3 Instrumentation

The full suite finished `OK (23 tests)` with 23 test status `0` results and 0
failures. The 11 T024 tests were:

- `platformChannelIsRegisteredAndSyncCallReturnsSuccessEnvelope`
- `everyContractMethodAcceptsMinimalPayloadThroughRealChannels`
- `asyncCallReturnsOperationIdAndPublishesOneTerminalResult`
- `asyncFailureIsPublishedAsResultNotMethodException`
- `serviceAssertionErrorPublishesOneSafeInternalResult`
- `validationFailureRejectsWithFlutterExceptionAndEmitsNoResult`
- `missingServiceRejectsWithUnsupportedAndEmitsNoResult`
- `concurrentSaveForSameDocumentRejectsBeforeStart`
- `runningCancellationPublishesOnlyCancellationAndTerminalCancelReturnsFalse`
- `resultCompletedBeforeListenerAttachIsReplayed`
- `teardownRemovesChannelHandlersAndFailsClosed`

These exercise the real `MethodChannel`/`EventChannel` registration and
`StandardMethodCodec` envelopes, the Android main `Looper`, the bounded
executor, start/result separation, one safe `PLT-001`/`platform.internal` result
for an `AssertionError` including no throwable text/class/stack/path,
`PLT-003`/`PLT-001` rejections with no operation and no result, `SAVE-006`
before start, running cancellation with exactly one `PLT-004`, `false` after the
terminal state, late-listener replay, and handler removal on teardown.

The 12 preserved T025 tests also passed, including the real Android Keystore
round-trip, per-aggregate alias isolation, exact-only test cleanup, and the
foreign-test-alias guard. The T024 tests only drive in-memory fake services and
do not create, read, or delete document files, URIs, or production Keystore
aliases.

### 5.4 Allocation and cleanup

The prior test-only `de.feldexa.app` and `de.feldexa.app.test` packages on this
dedicated T025 AVD were replaced because the debug signing key differed between
the T025 and T024 workspace shadows. No user document or production data was
present on the AVD; the only actions were the two test-package uninstalls and
installs. After the run, Orca shutdown returned success, the session list was
empty, adb listed no device, and all eight AVDs were `shutdown`. The AVD remains
in place and was not wiped.

## 6. Performance

No performance claim.

## 7. Limitations

- This is `EMULATOR` evidence on the Orca-allocated Pixel 7 API 35 profile, not
  `DEVICE` acceptance and not a physical-device journey.
- The T024 tests attach the real plugin to an in-process `BinaryMessenger` and
  real channels; they do not start a Dart isolate or run the Flutter app UI.
  They prove the Android channel boundary, codec, main-Looper, executor, and
  lifecycle, not a live Dart end-to-end call path.
- T025's suite was re-run as a regression check; its independent review is still
  separate and is not claimed here.
- No SAF import, OCR, export, delivery, full app navigation, or lifecycle journey
  was exercised.
- The host KVM device descriptor was not visible from this worker's namespace;
  acceleration is evidenced by the guest `kvm-clock` clocksource and the
  `avx`/`f16c`/`hypervisor` CPU flags, consistent with the earlier T025 host
  KVM record.
- The pre-existing `gradlew.bat` line-ending state is local tooling noise and is
  not part of the candidate.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Debug app APK | `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 225292375 | `0e99ae2ad3b3c2d404671c52f0e99848821ea6465164583a068d32017784bb1f` |
| Instrumentation test APK | `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 499184 | `08e688ef503d8a1ca12332578ff94a852a2c248de103238b284c76336f1069ba` |
| T024 instrumentation source | `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/FeldexaPluginInstrumentedTest.kt` | 20291 | `bcf393c4e4e3c79ec4153bc1476aebe11fcdb4144b1d85d08a09e72e001a4931` |
| Merge audit | `build/t024-merge/logs/t024-merge-audit.log` | 3225 | `280d8219debd8e0b6a2ec8691b9c56bcd6c9950b988fefe375d4f57b5e5ec7d4` |
| Merged build and JVM tests | `build/t024-merge/logs/gradle-merge-build3.log` | 27737 | `4f7222e5a045112e41d3e04902f3fadf3b8ffd1389944ce17084ca7766e11c6a` |
| Final test-APK build | `build/t024-merge/logs/gradle-androidtest-rebuild2.log` | 26430 | `d3264d514fa87f53a53be87d9c06fbfdb025a89266997c1a19a9de5b788ea258` |
| JVM test summary | `build/t024-merge/logs/t024-unit-tests.log` | 294 | `07439004ac4f4a2bbddbd59461912d92ea72d24e57c7de27046707033cdfc900` |
| DEX identity check | `build/t024-merge/logs/t024-dex-check.log` | 175 | `c2972b1b9347d9d5c8e7ccdf5cfa6c239ace28a2265bad30dbe22f717ea62e77` |
| Exclusivity baseline | `build/t024-merge/logs/t024-exclusivity-before.log` | 3808 | `3047a491034bb3ec4d43db596a22d06bee8a02e352a91f9d600f1ca66763ab76` |
| Orca attach | `build/t024-merge/logs/t024-orca-attach.json` | 357 | `531c74925682f3dc4d4781e76e093be2b6b7791e65d54c92fab01133432e4bf6` |
| Device identity and flags | `build/t024-merge/logs/t024-device-evidence.log` | 994 | `661f8b17cadf6c9b1ca17421e2cbc1ca857be39fb03e7f4a0c322c1617e4dac7` |
| Guest clocksource and CPU evidence | `build/t024-merge/logs/t024-device-evidence-root.log` | 576 | `2d1aee506e28c9e7451468b649caca3dd0e9fef328e34afb8c1d0d78deb31413` |
| Full instrumentation run | `build/t024-merge/logs/t024-instrumentation-final.log` | 17393 | `db90a2db0d633e9254bfc083486186ddbf9737754da1d1737ee22f5d91251280` |
| Cleanup verification | `build/t024-merge/logs/t024-shutdown-clean.log` | 788 | `83b4f7766d2e6ad3d262bd50d25472176a05560eb96f0888e7ccd6d264f3d5ab` |

## 9. Reproducibility

1. Start from base commit `2a3797bed8cfe5c0f1036063ec31ca2d60592dea`.
2. Verify the Orca inventory: no emulator sessions, all AVDs `shutdown`, no adb
   device. Do not start, wipe, or adopt any other AVD or device.
3. Build from `apps/feldexa_app/android` with Gradle 9.3.1 and JBR 21:
   `./gradlew --no-daemon :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest`.
   Expected: 131 JVM tests pass, both APKs assemble, and their SHA-256 values
   match §8.
4. `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current --json`.
   Expected: `attached: true` for `emulator-5554`; wait for
   `sys.boot_completed=1` and `service check package` found.
5. Install both APKs with `adb -s emulator-5554 install -r -t`, then run
   `adb -s emulator-5554 shell am instrument -w -r de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner`.
   Expected: `OK (23 tests)`.
6. Shut down with
   `orca emulator shutdown --device emulator-5554 --worktree current --json`;
   verify no session, no adb device, and all AVDs `shutdown`.

## 10. External attestation

`refs/heads/t024-attestation` (local, not pushed) and the `worker_done`
transport record name the candidate SHA, this report's bytes and SHA-256, and the
changed-file list. The attestation is created after the candidate commit and is
not part of the candidate tree.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
