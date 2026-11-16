# 2026-11-16 EMULATOR — T024 §10 total method-payload boundary correction

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` |
| Result | `PASS` |
| Task / issue | `T024` / `#24` |
| Date / timezone | `2026-11-16 11:17 Europe/Berlin` |
| Revision | base commit `2d793adc8296ca2025285be0deb853c16b3f5e05`; tree `dirty`: the T024 source/test edits, this report, the README index row and the T024 task note are in the candidate commit; the only uncommitted file is the pre-existing line-ending phantom `apps/feldexa_app/android/gradlew.bat` SHA-256 `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62`, which is not part of the candidate; the candidate SHA and this report's bytes/hash are in the external attestation |
| External attestation | `refs/heads/t024-total-payload-attestation` (local, not pushed) plus the `worker_done` transport record |
| Build identity | version `1.0` (versionCode `1`); mode `debug`; debug-only `android:largeHeap=true`; app `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` SHA-256 `b6787739e1f221fc933c0de9c014e8dcfa2383e499b0dcde8edb715e91bf7f33`; instrumentation `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` SHA-256 `576419bddd659e3d9281d784891855b824d4631d380c5db362e416d262cbd3c9`; main and release manifest sources unchanged versus base |
| Toolchain | Flutter `3.47.7` (framework `abaf9c5237`), Dart `3.13.5`, Gradle `9.3.1`, Kotlin `2.4.0`, Temurin JDK `21.0.13`, Android SDK platform `36`, build-tools `36.0.0` and `35.0.0`, Android Emulator `37.2.12.0`, adb `1.0.41` (`37.0.1`) |
| Input | no corpus; synthetic UUIDv4 aggregate ids, in-memory fake services, synthetic payloads including one 96 MiB + 1 byte array per method; no user document, Keystore alias, file, URI, or device data |

## 1. Scope

This run corrects the accepted Review A finding for T024 #24 in the preserved
recovery worktree. The pre-correction candidate was
`206d109c69e7cd02835a0b6cb31f9f371e88ce74` on base
`2d793adc8296ca2025285be0deb853c16b3f5e05`. Review A found that
`FeldexaPlugin.kt` measured only the top-level values of a method payload, so
the field keys, the root map framing and the method-call framing were outside
the `contracts/platform-channel.md` §10 `Method payload ≤ 96 MiB total` guard.
The 24 per-method 96 MiB + 1 value tests proved per-value rejection but not the
total-envelope boundary.

The correction makes the guard mirror the actual Flutter codec on the entire
method call: the method-name string, the root arguments map marker and entry
count, every map key's own encoding, and every value recursively. It remains
allocation-free for large byte arrays and strings, so a near-96 MiB payload is
never serialized a second time. Per-field limits stay in place and every failure
is still the content-free `PLT-003` / `platform.payloadTooLarge` error.

This record covers the host-JVM regressions, a real-codec boundary test through
the actual `MethodChannel`, and the full Android instrumentation suite on the
Orca-allocated Pixel 7 API 35 KVM AVD. It is not a `DEVICE` acceptance, not a
full Dart/Flutter UI journey, not a product acceptance and not a performance
claim. Independent review remains with the two existing review roles.

## 2. Revision and build

The correction started at pre-correction candidate
`206d109c69e7cd02835a0b6cb31f9f371e88ce74` whose base is
`2d793adc8296ca2025285be0deb853c16b3f5e05`. The working tree contains the
following T024 changes:

- `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/FeldexaPlugin.kt`
- `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/FeldexaPluginTest.kt`
- `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/FeldexaPluginInstrumentedTest.kt`
- this report, the report-index row and the T024 note in `tasks.md`

The pre-existing `apps/feldexa_app/android/gradlew.bat` line-ending phantom is
not staged and is not part of the candidate; T025/T026 storage code and tests
and the T028 simulated adapters are byte-identical to base
(`git diff --quiet 2d793ad -- apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/storage packages/feldexa_adapters_simulated`
exits `0`).

The host build used the workspace-local, gitignored shadows
`build/toolchain-flutter` (Flutter `3.47.7`), `build/gradle-home` (Gradle
`9.3.1` with Temurin JDK `21.0.13`) and `build/android-sdk`; `local.properties`
points at those shadows and a normal writable checkout needs no shadow. From
`apps/feldexa_app/android`:

```sh
./gradlew --offline --no-daemon :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest
```

The build finished `BUILD SUCCESSFUL`. The host-JVM suite was then rerun with
`--rerun-tasks` against the final source bytes: **214 tests, 0 failures, 0
errors, 0 skipped**. The app APK is 223362067 bytes SHA-256
`b6787739e1f221fc933c0de9c014e8dcfa2383e499b0dcde8edb715e91bf7f33`; the
instrumentation test APK is 433255 bytes SHA-256
`576419bddd659e3d9281d784891855b824d4631d380c5db362e416d262cbd3c9`.

### 2.1 Codec accounting

`StandardMethodCodec.encodeMethodCall` concatenates the encoded method-name
string and the encoded arguments value; there is no result-envelope flag byte
on a method call. `StandardMessageCodec` encodes each value with one type byte;
strings, byte arrays, maps and lists carry a variable-width size prefix
(1, 3 or 5 bytes); doubles are aligned to an 8-byte boundary in the full
message; typed numeric arrays carry their own alignment; and every map entry
encodes the key in full before the value. `PayloadSize.measureMethodCall`
mirrors those rules exactly, including the method name and root map, using the
same traversal order as the encoder and without constructing the serialized
bytes.

For the boundary payload `import.pickAndImport` with
`schemaVersion=1`, `maxBytes=1024` and a 40-character `titleHint`, the old
value-only sum is 52 bytes (5 + 5 + 42). The real method call is 112 bytes:
method name 22, root map marker and count 2, keys 15 + 10 + 11, integer values
10, and the string 42. The new guard rejects at a 52-byte limit because the
envelope is 112 bytes, accepts at exactly 112, and rejects at 111. The Android
test obtains the 112-byte boundary from the real `StandardMethodCodec` and
drives the real `MethodChannel` and plugin at both limits.

## 3. Environment

```text
EMULATOR: Pixel 7 API 35, exclusive allocation T025_Pixel7_API35_KVM_20261115;
          system image system-images;android-35;google_apis;x86_64 revision 9;
          build fingerprint google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys;
          RAM 3072 MB; APK apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk SHA-256 b6787739e1f221fc933c0de9c014e8dcfa2383e499b0dcde8edb715e91bf7f33;
          build mode debug, debug-only largeHeap overlay, no rebuild during the instrumentation run.
```

Before attach, `orca emulator list --worktree all --json` returned no sessions,
`orca emulator devices --json` showed every AVD `shutdown`, and `adb devices -l`
listed no device. `orca emulator attach T025_Pixel7_API35_KVM_20261115
--worktree current --json` returned `attached: true` for `emulator-5554`.
Exactly one Orca session and exactly one adb device existed before, during and
after the run; every other AVD stayed `shutdown`. The guest reported
`ro.boot.qemu.avd_name=T025_Pixel7_API35_KVM_20261115`, API 35, Android 15,
`sys.boot_completed=1`, and `service check package` found. With temporary root
adbd (disabled again immediately), the active clocksource was `kvm-clock` and
the available clocksources were `kvm-clock tsc hpet`; guest CPU flags included
`avx`, `f16c` and `hypervisor`. The guest heap properties were
`dalvik.vm.heapgrowthlimit=192m` and `dalvik.vm.heapsize=576m`.

`dumpsys package de.feldexa.app` reported
`pkgFlags=[ DEBUGGABLE HAS_CODE ALLOW_CLEAR_USER_DATA LARGE_HEAP ]`, and
`aapt2 dump xmltree` of the debug APK reports `largeHeap=true`. The release and
main manifest sources are unchanged versus base, so the large heap stays
confined to the debug harness and is not a release-heap claim. Both APKs were
installed with `adb install -r -t`; the pulled installed base APKs are
byte-identical to the built APKs. No other package, document, URI, file,
Keystore alias, or AVD was read, created, changed, or deleted. The AVD was shut
down, not wiped.

The dispatched worker runs inside a sandbox that does not expose the host KVM
device node or the host emulator process, so no host file-descriptor claim is
made. The positive runtime evidence is the Orca allocation label, the guest AVD
name and the guest `kvm-clock` clocksource; that limitation is repeated in §7.

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `git rev-parse HEAD` = `206d109c69e7cd02835a0b6cb31f9f371e88ce74`; `git rev-parse 2d793ad` = base (`<repo-root>`) | `0` | console only (not retained) | `PASS` |
| 2 | `./gradlew --offline --no-daemon :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest` (`apps/feldexa_app/android`) | `0` | `build/t024-total-payload/logs/gradle-build-final.log` | `PASS` |
| 3 | `./gradlew --offline --no-daemon :app:testDebugUnitTest --rerun-tasks` (`apps/feldexa_app/android`) | `0` | `build/t024-total-payload/logs/gradle-jvm-final.log` | `PASS` |
| 4 | `orca emulator list --worktree all --json`; `orca emulator devices --json`; `adb devices -l` (`<repo-root>`) | `0` | `build/t024-total-payload/logs/exclusivity-before.log` | `PASS` |
| 5 | `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current --json` (`<repo-root>`) | `0` | `build/t024-total-payload/logs/orca-attach.json` | `PASS` |
| 6 | boot, guest AVD identity, `kvm-clock` clocksource, heap and `service check package` (`<repo-root>`) | `0` | `build/t024-total-payload/logs/device-evidence.log` | `PASS` |
| 7 | `adb install -r -t` app and test APKs; `dumpsys package` flags; dex class scan; `aapt2` largeHeap check (`<repo-root>`) | `0` | `build/t024-total-payload/logs/device-evidence.log` | `PASS` |
| 8 | `adb shell am instrument -w -r -e class de.feldexa.app.FeldexaPluginInstrumentedTest de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner` (`<repo-root>`) | `0` | `build/t024-total-payload/logs/instrument-t024-class.log` | `PASS` |
| 9 | `adb shell am instrument -w -r de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner` (`<repo-root>`) | `0` | `build/t024-total-payload/logs/instrument-full.log` | `PASS` |
| 10 | test-class/test-name inventory parse of the full run (`<repo-root>`) | `0` | `build/t024-total-payload/logs/test-inventory.log` | `PASS` |
| 11 | pull installed base APKs and `cmp`/`sha256sum` against the built APKs (`<repo-root>`) | `0` | `build/t024-total-payload/logs/device-evidence.log` | `PASS` |
| 12 | `adb logcat -d`; `grep -e "FATAL EXCEPTION" -e OutOfMemoryError` (no matching lines) (`<repo-root>`) | `0` | `build/t024-total-payload/logs/logcat-fatal-scan.log` | `PASS` |
| 13 | `orca emulator list --worktree all --json`; `orca emulator devices --json`; `adb devices -l` during the run (`<repo-root>`) | `0` | `build/t024-total-payload/logs/exclusivity-during.log` | `PASS` |
| 14 | `orca emulator shutdown --device emulator-5554 --worktree current --json`; then session/device/AVD verification (`<repo-root>`) | `0` | `build/t024-total-payload/logs/exclusivity-after.log` | `PASS` |

## 5. Results

### 5.1 Host JVM and build

- `:app:testDebugUnitTest`: **214 tests, 0 failures, 0 errors, 0 skipped**:
  - `FeldexaPluginTest` 91 (T024), including the three new §10 regressions
    `payloadSizeMatchesStandardMessageCodecByteAccounting`,
    `payloadAtExactTotalEnvelopeIsAcceptedAndOneByteOverIsRejected`, and
    `payloadIsRejectedWhenValuesFitButKeysAndRootExceedTheLimit`;
  - `KeystoreServiceTest` 40 and `InstrumentedKeystoreAliasSafetyTest` 3
    (T025);
  - `EncryptedStoreTest` 49, `EncryptedStoreFaultTest` 9,
    `EncryptedStoreHeadHistoryTest` 7, `EncryptedStoreOrderingTest` 2,
    `EncryptedStorePruneRecoveryTest` 5, `EncryptedStoreReviewTest` 8
    (T026, 80 tests).
- `:app:assembleDebug` and `:app:assembleDebugAndroidTest`: `BUILD SUCCESSFUL`.
- The debug APK contains `de.feldexa.app.FeldexaPlugin`; the test APK contains
  `FeldexaPluginInstrumentedTest`, `KeystoreServiceInstrumentedTest`, and
  `EncryptedStoreInstrumentedTest`.
- The pulled installed app/test base APKs are byte-identical to the built APKs
  (`b6787739…` and `576419bd…`).

### 5.2 Android instrumentation

The full suite finished **`OK (46 tests)`** in 13.923 s with all status codes
`0`:

- `FeldexaPluginInstrumentedTest` **15/15** — the real
  `de.feldexa/platform`/`events`/`results` channel boundary, start/result
  separation, one safe `PLT-001` for `AssertionError`, `SAVE-006` before start,
  cancellation/replay/teardown, the complete §12 payload round-trip, and the
  new `payloadLimitMatchesActualStandardMethodCodecEnvelopeAtBoundary`.
- `KeystoreServiceInstrumentedTest` **12/12** — real `AndroidKeyStore`
  round-trip, per-aggregate alias isolation, non-exportability, exact-only test
  cleanup and foreign-alias guard.
- `EncryptedStoreInstrumentedTest` **19/19** — real-keystore create/save/load,
  read-back, head history and retention/pruning, prune-fsync retry and
  no-resurrection behavior, aggregate key loss `SAVE-002` versus global
  `SAVE-008`, tamper `SAVE-003`, legacy-head retention, parallel-save
  serialization, boundary sizes, and no plaintext residue.

Logcat contained no `FATAL EXCEPTION` or `OutOfMemoryError` for
`de.feldexa.app`.

### 5.3 Review-A correction

- The old guard summed only top-level values. Its 24 method-spanning
  96 MiB + 1 tests still pass, but they did not exercise the total-envelope
  boundary.
- The new host regression constructs a payload whose values total 52 bytes and
  whose real method call is 112 bytes. At a 52-byte limit the new guard rejects
  with `platform.payloadTooLarge`; the old value-only logic would have
  accepted it. At exactly 112 bytes the payload is accepted, and at 111 bytes
  it is rejected.
- The Android regression encodes the same payload with the real
  `StandardMethodCodec`, asserts the encoded size is 112 bytes and equals
  `PayloadSize.measureMethodCall`, then drives the real `MethodChannel` and
  `FeldexaPlugin` with a 112-byte limit (success) and a 111-byte limit
  (`PLT-003` / `platform.payloadTooLarge`).
- Per-object limits are preserved and still enforced: signature 2 MiB maps to
  `SAVE-007`, revision 32 MiB maps to `SAVE-007`, and export plan 8 MiB maps to
  `PLT-003`; the existing host tests for those limits pass.
- Failure remains content-free: no payload bytes, keys, values, titles, paths or
  URIs are placed in the error or details. The accounting never allocates a
  second serialized copy; large byte arrays contribute their length directly
  and strings are scanned by code unit.
- The existing method-spanning tests remain: unknown fields 24/24, strict UUID
  regex across 16 methods with 21 field instances and six malformed shapes
  each, and 96 MiB + 1 values 24/24.

### 5.4 Scope preservation

- T025/T026 storage Kotlin sources and tests and the T028 simulated adapters
  are byte-identical to base; the T025 12/12 and T026 19/19 Android tests pass
  unchanged on the same AVD.
- The T024 async start/result protocol, error mapping, cancellation, replay and
  lifecycle behavior are unchanged except for the full-envelope accounting.
- The debug-only large heap overlay is unchanged, the release and main manifest
  sources are unchanged, and no release-heap behavior is claimed.

## 6. Performance

No performance claim.

## 7. Limitations

- This is `EMULATOR` evidence, not `DEVICE` acceptance and not a physical-device
  journey.
- The T024 instrumentation attaches the real plugin to an in-process
  `BinaryMessenger` and real channels; it does not start a Dart isolate or run
  the Flutter app UI. No full Dart/Flutter UI, SAF import, OCR, export,
  delivery, or product acceptance journey was run.
- The 96 MiB + 1 rejection uses the debug-only largeHeap harness. The release
  manifest is unchanged and no release-heap behavior is claimed.
- The exact-envelope boundary is proven at 112 bytes through the real codec and
  channel; the suite does not allocate an exact 96 MiB accepted payload.
- The sandbox does not expose the host KVM device node or the host emulator
  process, so no host KVM file-descriptor claim is made. Guest
  `kvm-clock`, the AVD name and one-session/one-adb-device observations are the
  runtime allocation evidence.
- The T028 Dart/SIMULATED suites were not rerun; their files are byte-identical
  to base and the correction does not touch them.
- Performance, release build, physical-device and full acceptance claims remain
  `NOT_RUN`.
- The two existing review roles (Review A and Review B) and the Maintainer must
  revalidate the final candidate; this report is author evidence, not approval.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Debug app APK | `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 223362067 | `b6787739e1f221fc933c0de9c014e8dcfa2383e499b0dcde8edb715e91bf7f33` |
| Instrumentation test APK | `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 433255 | `576419bddd659e3d9281d784891855b824d4631d380c5db362e416d262cbd3c9` |
| T024 main source | `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/FeldexaPlugin.kt` | 69756 | `e45ac89fd27e4ca4b983bc02071c5eaf85edff877be4680434b415ff3d973dbd` |
| T024 host tests | `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/FeldexaPluginTest.kt` | 67062 | `9b649ab0e3e8e7c22c139e67008ec97179e6f9c52b8e7df7f58efb9f2252d723` |
| T024 instrumentation | `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/FeldexaPluginInstrumentedTest.kt` | 28057 | `4e4933b4c7599977e9cbdecb80684ee05efdd1319622d4e2a236a4ecaf10a428` |
| Debug manifest overlay | `apps/feldexa_app/android/app/src/debug/AndroidManifest.xml` | 896 | `0b8fdc86353bc245b248439529586f221aa01a2b72d3982b7a6dd1e2e9cda1dc` |
| Gradle build and tests | `build/t024-total-payload/logs/gradle-build-final.log` | 28446 | `0f31ec5b68ad0be48307178975454ad5ce31e33d193ab9a423529ad1d67a2ba6` |
| Final JVM rerun | `build/t024-total-payload/logs/gradle-jvm-final.log` | 71181 | `41936e49d07db0261fedc92f4a8fabf97420be80cf514119d48babc11f571c46` |
| T024 class run | `build/t024-total-payload/logs/instrument-t024-class.log` | 10250 | `b0ef587309c18a993e172c09b954901dcfbead9409d2c6ba8f89038f0e16de87` |
| Full instrumentation | `build/t024-total-payload/logs/instrument-full.log` | 31163 | `475b69d164c30ca29e2f720dfc5bda60fd268c6d04e651027621ac3177e44f2e` |
| Test inventory | `build/t024-total-payload/logs/test-inventory.log` | 552 | `7f58cec0fb4faed675124e68bafca52a774a4c398097f8e3d235c7afa6b1bbe6` |
| Device and identity evidence | `build/t024-total-payload/logs/device-evidence.log` | 8982 | `7bbcf3b86fec1be097a91e5493c09b937d6f34e0eaf7dfa0fa40a972e43b0d5d` |
| Exclusivity before | `build/t024-total-payload/logs/exclusivity-before.log` | 2186 | `c3713a1ab7acec138c39818680924877987fc380d34f6efe5c14bb1c3ec70aa7` |
| Exclusivity during | `build/t024-total-payload/logs/exclusivity-during.log` | 2589 | `75462c6f85a9efa08dddcb767b7d5d66654fc72049b02c27d54cee868a2ef522` |
| Exclusivity after | `build/t024-total-payload/logs/exclusivity-after.log` | 2159 | `ac05079b8e3f2be86e1def16c049e4b87ef55e34bf7d69dd6e0b6f6616a6e1c9` |
| Orca attach | `build/t024-total-payload/logs/orca-attach.json` | 357 | `315ffbb167b54790f493a385c266d322a32580fecd79a61df4eb218b3c508d86` |
| Orca shutdown | `build/t024-total-payload/logs/orca-shutdown.json` | 208 | `3001339e33aafb6d130bb925299f90a31e087ce9b4616e423b0633ffdf0e380a` |
| Logcat fatal scan (empty) | `build/t024-total-payload/logs/logcat-fatal-scan.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| Full logcat | `build/t024-total-payload/logs/logcat-full.log` | 5763872 | `d0131e96663a9744841ddcb9372845c9e7513208622f55024c4a29cfe5124d50` |
| Host KVM visibility note | `build/t024-total-payload/logs/host-kvm-evidence.log` | 625 | `21e4e7cf116c5ef77c0e8aeae8f323575c95ea05c685a78008fd803e95247764` |

## 9. Reproducibility

1. Start from base commit `2d793adc8296ca2025285be0deb853c16b3f5e05`.
2. Apply the T024 total-envelope correction to `FeldexaPlugin.kt`, add the host
   regressions to `FeldexaPluginTest.kt`, and add the real-codec boundary test
   to `FeldexaPluginInstrumentedTest.kt`; add this report, the README index row
   and the T024 task note. The `gradlew.bat` phantom is not staged.
3. From `apps/feldexa_app/android`, run
   `./gradlew --offline --no-daemon :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest`
   with the workspace-local Flutter/Gradle/Android shadows. Expected:
   `BUILD SUCCESSFUL`, 214 JVM tests pass, and the two APK SHA-256 values match
   §8.
4. Verify no other emulator session, no other adb device and every AVD in
   `shutdown`; `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree
   current --json`; wait for `sys.boot_completed=1`, `service check package`
   found, and guest clocksource `kvm-clock`.
5. Install both APKs with `adb install -r -t`; verify
   `dumpsys package de.feldexa.app` shows `LARGE_HEAP`, pull the installed base
   APKs, and compare their SHA-256 with §8.
6. Run the T024 class and then the full suite:
   `adb shell am instrument -w -r -e class de.feldexa.app.FeldexaPluginInstrumentedTest de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner`
   and `adb shell am instrument -w -r de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner`.
   Expected: 15/15 T024 and `OK (46 tests)` (15 T024 + 12 T025 + 19 T026).
7. Scan logcat for `FATAL EXCEPTION` or `OutOfMemoryError`, then
   `orca emulator shutdown --device emulator-5554 --worktree current --json`
   and verify no session, no adb device and every AVD `shutdown`.

## 10. External attestation

`refs/heads/t024-total-payload-attestation` (local, not pushed) and the
`worker_done` transport record name the final candidate SHA, the pre-correction
candidate `206d109c69e7cd02835a0b6cb31f9f371e88ce74`, the base
`2d793adc8296ca2025285be0deb853c16b3f5e05`, this report's bytes and SHA-256, the
changed-file list, the APK hashes and the host/Android test results. The
attestation is created after the final candidate commit and is not part of the
candidate tree.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
