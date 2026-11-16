# 2026-11-16 EMULATOR — T024 §12 payload round-trip coverage

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` |
| Result | `PASS` |
| Task / issue | `T024` / `#24` |
| Date / timezone | `2026-11-16 10:17–10:24 Europe/Berlin` |
| Revision | base commit `7e13ad0d533bd9897f02c72cdacd266877cb1aa8`; tree state: dirty before the candidate commit with `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/FeldexaPluginInstrumentedTest.kt` SHA-256 `b9af0ca6acf62f6226dd3bc90681a5d871154b2990d65b6099a51d30f2c4841f` (25875 bytes) and `apps/feldexa_app/android/app/src/debug/AndroidManifest.xml` SHA-256 `0b8fdc86353bc245b248439529586f221aa01a2b72d3982b7a6dd1e2e9cda1dc` (896 bytes); the pre-existing `gradlew.bat` line-ending state is local tooling noise and excluded; candidate SHA in external attestation |
| External attestation | `refs/heads/t024-payload-attestation` (local, not pushed) plus the `worker_done` transport record; they record the candidate SHA, this report's bytes and SHA-256, and the changed-file list |
| Build identity | versionName `1.0` (versionCode `1`), mode `debug`, `android:largeHeap="true"` in the debug overlay only; app `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` 225265706 bytes SHA-256 `55acd60f9ec6a68748b2330ab4e4f775c9012581b26be2d455f6abb10d67942e`; instrumentation test `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` 506094 bytes SHA-256 `5315ae033028c4220d8c4e1e1581eb9598583f55bcbc21b12fb42ff09ee30771` |
| Toolchain | Flutter `3.47.7` (framework `abaf9c523780a608bd46686fd5e53740a07077f8`), Dart `3.13.5`, Gradle wrapper `9.3.1`, Kotlin `2.4.0`, JetBrains Runtime `21.0.11`, Android SDK platform `36`/build-tools `35`, Android Emulator `37.2.12.0`, adb `1.0.41` (`37.0.1`) |
| Input | no corpus; synthetic UUIDv4 aggregate ids, in-memory fake services, synthetic OCR bytes, and one synthetic 96 MiB + 1 byte payload per method; no user document, Keystore, file, URI, or device data |

## 1. Scope

The T024 requirement review of `7e13ad0` reported that
`contracts/platform-channel.md` §12:406 requires emulator instrumentation for
unknown fields, invalid UUIDs, and oversized payloads for **every** method
payload, while `FeldexaPluginInstrumentedTest` only exercised one unknown key
at `store.status`. This record answers:

1. What exactly is normative in §12, §10, and §1?
2. Which of the 24 contract methods actually declare UUID-bearing or
   size-bearing fields?
3. Does the completed instrumentation reject unknown fields, strict-regex UUID
   violations, and a payload above the 96 MiB total limit for every applicable
   method on the Orca-allocated Pixel 7 API 35 runtime?

This is `EMULATOR` evidence for the Android channel boundary. It is not
`DEVICE` acceptance, a Dart-engine end-to-end journey, or a performance claim.

## 2. Normative obligation and method inventory

`contracts/platform-channel.md` §12 line 406 is the reviewed row:

> `Payload round-trip` | `Emulator instrumentation` | `every method accepts a
> minimal valid payload and rejects unknown fields, bad UUIDs, oversized
> payloads`

The supporting normative rules are:

- §1: "Unknown **top-level** fields are rejected with `PLT-003` to catch version
  drift early."
- §10: `Method payload` ≤ `96 MiB` total → `PLT-003`; `UUID strings` use a
  strict regex → `PLT-002`.

The facade's method catalog contains 24 methods: 3 `import`, 12 `store`, 1
`ocr`, 4 `export`, 3 `delivery`, and 1 `cancel`. Sixteen methods declare 21
top-level UUID field instances (nine distinct names). The eight methods without
a top-level UUID field are `import.pickAndImport`, `import.discardStaged`
(`txnId` is a 128-character token, not a UUID), `store.status`, `store.list`,
`store.createTemplate`, `ocr.recognize`, `export.validate`, and `export.render`.
The 96 MiB total limit applies to all 24 methods.

| Method | Top-level UUID fields | Size-relevant fields / limits |
| --- | --- | --- |
| `import.pickAndImport` | — | `maxBytes` 1..80 MiB, `titleHint` ≤ 200 chars |
| `import.verifySource` | `sourceId` | — |
| `import.discardStaged` | — (`txnId` token) | `txnId` ≤ 128 chars, token regex |
| `store.status` | — | — |
| `store.list` | — | `kind` enum |
| `store.readSource` | `documentId` | — |
| `store.readSignature` | `documentId`, `assetId` | — |
| `store.writeSignature` | `documentId`, `assetId` | `bytes` ≤ 2 MiB (`SAVE-007`), `sha256` 64 hex |
| `store.saveRevision` | `documentId`, `expectedHead` (optional, nullable) | `revision` ≤ 32 MiB (`SAVE-007`) |
| `store.createTemplate` | — (nested maps are size/type checked only) | `template`, `revision` ≤ 32 MiB |
| `store.saveTemplateVersion` | `templateId`, `expectedHead` (optional, nullable) | `version` map |
| `store.loadDocument` | `documentId` | — |
| `store.loadTemplate` | `templateId`, `versionId` (optional, nullable) | — |
| `store.delete` | `id` | `confirm.title` ≤ 200 chars |
| `store.recoveryStamp` | `id` | — |
| `ocr.recognize` | — | edge ≤ 4096 px, raster `bytes` ≤ 64 MiB, `language` = `de` |
| `export.validate` | — | `plan` ≤ 8 MiB |
| `export.render` | — | `plan` ≤ 8 MiB |
| `export.readArtifact` | `artifactId` | — |
| `export.deleteArtifact` | `artifactId` | — |
| `delivery.save` | `artifactId` | `suggestedName` ≤ 120 chars, no path separators |
| `delivery.share` | `artifactId` | `mimeType` exactly `application/pdf` |
| `delivery.print` | `artifactId` | `jobName` ≤ 200 chars |
| `cancel.operation` | `operationId` | — |

## 3. Revision and build

No production Kotlin or contract file changed. The candidate adds the
method-spanning assertions to the existing instrumentation class and one
debug-only manifest attribute:

- `FeldexaPluginInstrumentedTest.kt`: three new tests (unknown field for every
  method, every declared UUID field against six malformed shapes, 96 MiB + 1
  total payload for every method), an explicit UUID inventory with two-way
  guards against the minimal-payload table, machine-message assertions, a
  24-method inventory assertion, and shared `registerAllServices`/`withSchema`
  helpers.
- `app/src/debug/AndroidManifest.xml`: `android:largeHeap="true"` only in the
  debug overlay. The 96 MiB default `ChannelLimits` is unchanged; the attribute
  compensates for the harness holding the payload and its encoded copy in one
  process (see §6). The release manifest source is unchanged.

The worker's file sandbox mounts the checked-out Flutter SDK, pub cache,
Gradle user home, and Android SDK read-only. The build therefore used
workspace-local, gitignored byte copies under `build/`: `toolchain-flutter`
(Flutter `3.47.7`), `gradle-home` (Gradle `9.3.1` cache), `pub-cache` with the
ignored `.dart_tool/package_config.json` and
`apps/feldexa_app/.flutter-plugins-dependencies` rewritten to that copy, and
`android-sdk` with SDK Platform 34 added from
`platform-34-ext7_r03.zip` (SHA-1 `1f2e9478d6a7601425ceaa553311dc43191f103d`).
`local.properties` was pointed at those shadows; it is gitignored and not part
of the candidate. A normal writable checkout builds with the standard Gradle
command and the installed SDK.

## 4. Environment

```text
EMULATOR: Pixel 7 API 35, exclusive allocation T025-PIXEL7-API35-KVM-20261115;
          system image system-images;android-35;google_apis;x86_64 revision 9;
          build fingerprint google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys;
          RAM 3072 MB; app APK apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk SHA-256 55acd60f9ec6a68748b2330ab4e4f775c9012581b26be2d455f6abb10d67942e;
          build mode debug, largeHeap debug overlay, no rebuild during the run.
```

Before the device action, `orca emulator list --worktree all --json` returned no
sessions, `orca emulator devices --json` showed every AVD `shutdown`, and
`adb devices -l` listed no device. Exactly one Orca session for this T024
worktree and exactly one adb device (`emulator-5554`) were observed before,
during, and after the run; every other AVD stayed `shutdown`. The guest reported
`ro.boot.qemu.avd_name=T025_Pixel7_API35_KVM_20261115`, API 35, Android 15,
`sys.boot_completed=1`, and `service check package` found.

`kvm-clock` was the active guest clocksource and `kvm-clock hpet` were
available; guest CPU flags included `avx`, `f16c`, and `hypervisor`. Root adbd
was enabled only to read that read-only clocksource evidence and was disabled
again before cleanup. The guest heap properties were `dalvik.vm.heapgrowthlimit=192m`
and `dalvik.vm.heapsize=576m`; `dumpsys package de.feldexa.app` reported
`pkgFlags=[ DEBUGGABLE HAS_CODE ALLOW_CLEAR_USER_DATA LARGE_HEAP ]` for the
debug APK.

An earlier T024/T025 debug key had installed `de.feldexa.app` and
`de.feldexa.app.test` on this dedicated AVD; both packages were uninstalled and
the new APKs installed because the signatures differed. No other package,
document, URI, file, or production Keystore alias was read, created, changed, or
deleted. The AVD was shut down, not wiped.

## 5. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `git rev-parse HEAD`, `git diff --name-status`, source/APK SHA-256 (repo root) | `0` | console only | `PASS` |
| 2 | `./gradlew --no-daemon :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest` (`apps/feldexa_app/android`) | `0` | `build/t024-payload/logs/gradle-build2.log` | `PASS` |
| 3 | `./gradlew --offline --no-daemon :app:testDebugUnitTest --rerun-tasks` (`apps/feldexa_app/android`) | `0` | `build/t024-payload/logs/gradle-jvm-rerun.log` | `PASS` |
| 4 | aggregate `TEST-*.xml` under `apps/feldexa_app/build/app/test-results/testDebugUnitTest` (repo root) | `0` | `build/t024-payload/logs/jvm-summary.log` | `PASS` |
| 5 | `dexdump` scan of both APKs (repo root) | `0` | `build/t024-payload/logs/dex-check.log` | `PASS` |
| 6 | `orca emulator list --worktree all --json`, `orca emulator devices --json`, `adb devices -l` (repo root) | `0` | `build/t024-payload/logs/exclusivity-before.log` | `PASS` |
| 7 | `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current --json` (repo root) | `0` | `build/t024-payload/logs/orca-attach.json` | `PASS` |
| 8 | `adb -s emulator-5554 shell getprop`, `service check package`, `dumpsys package`, clocksource/CPU readback (repo root) | `0` | `build/t024-payload/logs/device-evidence.log` | `PASS` |
| 9 | replace only `de.feldexa.app.test` and `de.feldexa.app`, `adb install -r -t` both APKs (repo root) | `0` | console only | `PASS` |
| 10 | `am instrument -e class …#everyMethodRejectsPayloadExceedingGlobalLimit` **before** the largeHeap harness change | `1` | `build/t024-payload/logs/instrument-oversize-probe.log` | `FAIL` (diagnostic only: `OutOfMemoryError` in the harness encoder; superseded by #12) |
| 11 | rebuild app/test APKs with the debug-only largeHeap overlay; `aapt2 dump xmltree` confirms `largeHeap=true` | `0` | `build/t024-payload/logs/gradle-build2.log` | `PASS` |
| 12 | `am instrument -e class …#everyMethodRejectsPayloadExceedingGlobalLimit` after the harness change | `0` | `build/t024-payload/logs/instrument-oversize-after-largeheap.log` | `PASS` |
| 13 | `am instrument -w -r -e class de.feldexa.app.FeldexaPluginInstrumentedTest` (repo root) | `0` | `build/t024-payload/logs/instrument-t024-class.log` | `PASS` |
| 14 | `am instrument -w -r de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner` (repo root) | `0` | `build/t024-payload/logs/instrument-full.log` | `PASS` |
| 15 | pull installed base APKs and SHA-256 compare (repo root) | `0` | `build/t024-payload/logs/apk-hashes.log` | `PASS` |
| 16 | `adb logcat -d` scan for `FATAL EXCEPTION`/`OutOfMemoryError` (repo root) | `0` | console only | `PASS` |
| 17 | `orca emulator shutdown --device emulator-5554 --worktree current --json`, then session/device/AVD verification | `0` | `build/t024-payload/logs/exclusivity-after.log`, `exclusivity-after-recheck.log` | `PASS` |

## 6. Results

### 6.1 Host checks

- `:app:testDebugUnitTest`: **131 tests, 0 failures, 0 errors, 0 skipped**
  (`FeldexaPluginTest` 88, `KeystoreServiceTest` 40,
  `InstrumentedKeystoreAliasSafetyTest` 3), rerun with `--rerun-tasks`.
- `:app:assembleDebug` and `:app:assembleDebugAndroidTest`: `BUILD SUCCESSFUL`.
- The debug APK contains `de.feldexa.app.FeldexaPlugin`; the test APK contains
  both `FeldexaPluginInstrumentedTest` and
  `KeystoreServiceInstrumentedTest`.
- The pulled installed app/test base APKs are byte-identical to the built
  APKs (`55acd60f…` and `5315ae03…`).

### 6.2 Instrumentation — method-spanning payload round-trip

`FeldexaPluginInstrumentedTest` ran **14/14 `PASS`** in 8.602 s. The four
payload-round-trip tests are:

- `everyContractMethodAcceptsMinimalPayloadThroughRealChannels` — all 24 minimal
  payloads accepted through the real `de.feldexa/platform` channel; the test
  additionally asserts the inventory is 24.
- `everyMethodRejectsAnUnknownField` — 24/24 methods reject an extra top-level
  key with `PLT-003`/`platform.unknownField` and emit no accepted operation.
- `everyDeclaredUuidFieldRejectsStrictRegexViolations` — 16 methods × 21 UUID
  field instances × 6 malformed shapes = **126 rejections**, each
  `PLT-002`/`platform.identifier`: `invalid-uuid`, empty string, truncated id,
  no hyphens, version nibble `0`, and variant nibble `7`. The explicit inventory
  is guarded against the minimal-payload table in both directions; optional
  nullable ids (`expectedHead` twice, `versionId`) are still tested with invalid
  non-null values.
- `everyMethodRejectsPayloadExceedingGlobalLimit` — 24/24 methods reject a
  payload whose total measured size is 96 MiB + 1 with
  `PLT-003`/`platform.payloadTooLarge`. The oversized value is placed under
  `schemaVersion`, the only field every method declares, so the total-size guard
  is the rejection reason and not a field rule.

The other ten T024 tests (start/result separation, safe `PLT-001` mapping,
`SAVE-006` before start, cancellation, replay, teardown) remain green.

### 6.3 The largeHeap harness decision

The first probe of the 96 MiB test **failed** with the unmodified debug APK:

```text
java.lang.OutOfMemoryError: Failed to allocate a 100663384 byte allocation
with 25165824 free bytes and 93MB until OOM, target footprint 128358592,
growth limit 201326592
    at java.util.Arrays.copyOf
    at io.flutter.plugin.common.StandardMessageCodec.writeBytes
    at io.flutter.plugin.common.StandardMethodCodec.encodeMethodCall
    at FeldexaPluginInstrumentedTest.dispatch
```

The in-process harness encodes the payload and then lets the Java channel decode
it, so it holds the 96 MiB payload plus its encoded copy in one 192 MiB app
heap. A production Dart call has only the Java-side decoded copy in that heap.
The debug-only `android:largeHeap="true"` overlay removes that harness artifact;
it does not change the 96 MiB contract limit, the validator, or any release
manifest. The alternative of injecting a smaller test limit was rejected
because it would no longer assert the documented 96 MiB threshold.

### 6.4 Full suite

The complete instrumentation run finished **`OK (26 tests)`** in 9.217 s:
14 T024 tests plus the 12 preserved T025 Keystore tests. Every test status code
was `0`; no failure or error was reported. Logcat contained no
`FATAL EXCEPTION`, `OutOfMemoryError`, or process death for `de.feldexa.app`.

### 6.5 Allocation and cleanup

Exactly one Orca session and one adb device existed before, during, and after the
run. The only device mutation was replacing the two dedicated test packages; no
foreign device, app data, document, Keystore alias, or AVD was touched. Orca
shutdown returned success, the session list was empty, adb listed no device, and
all eight AVDs were `shutdown`. The AVD remains in place and was not wiped.

## 7. Performance

No performance claim. The instrumentation wall times above are test-run
durations, not product performance.

## 8. Limitations

- This is `EMULATOR` evidence on the Orca-allocated Pixel 7 API 35 profile, not
  `DEVICE` acceptance and not a physical-device journey.
- The tests attach the real plugin to an in-process `BinaryMessenger` and real
  channels; they do not start a Dart isolate or run the Flutter app UI. They
  prove the Android channel boundary, codec, main `Looper`, executor, and
  lifecycle, not a live Dart end-to-end call path.
- The 96 MiB rejection runs with the debug-only largeHeap harness. The release
  build still inherits the normal 192 MiB growth limit; no release-heap claim is
  made, and no release APK was built for this run.
- T025's suite was re-run as a regression check; its independent review is still
  separate and is not claimed here.
- No SAF import, OCR, export, delivery, full app navigation, or lifecycle journey
  was exercised.
- `DEVICE` acceptance, the physical-device journey, and the full
  SAF/OCR/export/delivery journeys are `NOT_RUN`.
- The `gradlew.bat` line-ending phantom is pre-existing local tooling state and
  is not part of the candidate.

## 9. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Debug app APK | `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 225265706 | `55acd60f9ec6a68748b2330ab4e4f775c9012581b26be2d455f6abb10d67942e` |
| Instrumentation test APK | `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 506094 | `5315ae033028c4220d8c4e1e1581eb9598583f55bcbc21b12fb42ff09ee30771` |
| Instrumentation source | `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/FeldexaPluginInstrumentedTest.kt` | 25875 | `b9af0ca6acf62f6226dd3bc90681a5d871154b2990d65b6099a51d30f2c4841f` |
| Debug manifest overlay | `apps/feldexa_app/android/app/src/debug/AndroidManifest.xml` | 896 | `0b8fdc86353bc245b248439529586f221aa01a2b72d3982b7a6dd1e2e9cda1dc` |
| Final Gradle build | `build/t024-payload/logs/gradle-build2.log` | 22377 | `6e8c3aba7b8226828bfbdd4d35aec00f839b2d1192512a7bf50334fa0a9a5ecc` |
| Forced JVM rerun | `build/t024-payload/logs/gradle-jvm-rerun.log` | 24228 | `eecc005ebd3e57782bbd2b5963fa4b34dd31dd40b0df9b1a1e7875cdae323012` |
| JVM test summary | `build/t024-payload/logs/jvm-summary.log` | 390 | `7d067b8ce8f562e760ec1198e4c877ad2829a7753ecd0fc52fee3267b9d03a00` |
| DEX identity check | `build/t024-payload/logs/dex-check.log` | 129 | `3475d8cec93b8a3e82a04a5754a7a548fe6bcdc1f331b95d8494fd3fd983bedf` |
| APK identity | `build/t024-payload/logs/apk-hashes.log` | 827 | `5aeacfdf40d2a7ec82fe00616c2d1d873de1e52cf09b575ad60dac51eb060dad` |
| Exclusivity baseline | `build/t024-payload/logs/exclusivity-before.log` | 2154 | `c0c75a0258aeb9e997ebd66c0d4f9217048c8e94ed1bb46d8dde8d194cdb213e` |
| Orca attach | `build/t024-payload/logs/orca-attach.json` | 357 | `bfb15136635368a232bbaf8d920e4c06d93bb5ccb2376d314737b27e2efcca2b` |
| Device identity, heap, and KVM evidence | `build/t024-payload/logs/device-evidence.log` | 2750 | `de7492778c3194560d0146674f4b45a0ff6756608d61a94576b4e7c5e2f2fa23` |
| Pre-fix oversized probe (OOM) | `build/t024-payload/logs/instrument-oversize-probe.log` | 4488 | `caf279215cc96d737131dd139eef8ae32f4ab98204d62aa0bce708fefc1f4577` |
| Single oversized test after largeHeap | `build/t024-payload/logs/instrument-oversize-after-largeheap.log` | 788 | `815d5f105e01d37f24be29e18ea4d1d7f4da76ba82641c5779a98a3d08f7d4d2` |
| T024 instrumentation class | `build/t024-payload/logs/instrument-t024-class.log` | 9555 | `d95931c56b62afcea420cb69af5aad32d1d3dd1e93ba7bb543c89aed01f42203` |
| Full instrumentation suite | `build/t024-payload/logs/instrument-full.log` | 17721 | `d26259cc246b9ef42428f97207417f0554a0e733dfcaeebba87c00af8553d37d` |
| Cleanup verification | `build/t024-payload/logs/exclusivity-after.log` | 2456 | `837b9b634e1cdcc05be14ebfc753317ffbf68da67a7882c4ac63c5dccc7e80ed` |
| Cleanup recheck | `build/t024-payload/logs/exclusivity-after-recheck.log` | 259 | `dc850c82dbe0295b95785d05d3b979e13a944f69135db920f9f7f80e892494f0` |
| Orca shutdown | `build/t024-payload/logs/orca-shutdown.json` | 208 | `234a752f3b8d8f251afde4cce72cffab00918078bc39b3ed08e994ed515ffb00` |

The forced-rerun and JVM-summary logs are self-generated run logs and are not
part of the candidate.

## 10. Reproducibility

1. Start from base commit `7e13ad0d533bd9897f02c72cdacd266877cb1aa8` and apply the
   candidate (or check out the attested candidate SHA). Verify the two changed
   files against §9.
2. Verify the Orca inventory: no emulator sessions, all AVDs `shutdown`, no adb
   device. Do not start, wipe, or adopt any other AVD or device.
3. From `apps/feldexa_app/android`, build with Gradle `9.3.1` and JBR 21:
   `./gradlew --no-daemon :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest`.
   Expected: 131 JVM tests pass, both APKs assemble, and their SHA-256 values
   match §9. (In the worker's read-only sandbox, use the gitignored workspace
   shadows described in §3; a normal writable checkout needs no shadow.)
4. `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current --json`;
   wait for `sys.boot_completed=1` and `service check package` found. Verify one
   Orca session, one adb device, and `kvm-clock` with root readback.
5. Install both APKs with `adb -s emulator-5554 install -r -t`. On this dedicated
   AVD only, uninstall `de.feldexa.app.test` then `de.feldexa.app` first if the
   earlier debug signing key differs.
6. `adb -s emulator-5554 shell am instrument -w -r de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner`.
   Expected: `OK (26 tests)`. The oversized test alone can be re-run with
   `-e class de.feldexa.app.FeldexaPluginInstrumentedTest#everyMethodRejectsPayloadExceedingGlobalLimit`.
7. Pull the installed base APKs and compare SHA-256 with §9. Scan logcat for
   fatal/OOM entries.
8. Shut down with
   `orca emulator shutdown --device emulator-5554 --worktree current --json`;
   verify no session, no adb device, and all AVDs `shutdown`.

## 11. External attestation

`refs/heads/t024-payload-attestation` (local, not pushed) and the `worker_done`
transport record name the candidate SHA, this report's bytes and SHA-256, and the
changed-file list. The attestation is created after the candidate commit and is
not part of the candidate tree.

## 12. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
