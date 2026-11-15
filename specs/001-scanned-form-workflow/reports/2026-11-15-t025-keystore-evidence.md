# 2026-11-15 NONE — T025 per-aggregate Keystore KEK service

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `PARTIAL` |
| Task / issue | `T025` / `#25` |
| Date / timezone | `2026-11-15 02:07 Europe/Berlin` |
| Revision | base commit `1f17ad5e590bb4cb99b16f536761f05111797944`; tree `dirty` `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage/KeystoreService.kt` SHA-256 `2d7f1234c675cd3e37c04c0ab2cdb6eb41eb1a6f23d8b9b8499179592be8177a`; `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage/StorageExceptions.kt` SHA-256 `42c7b25775dc28851a039d2904c69d3027141a183fba8bc81806bc520fdd0532`; `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/storage/KeystoreServiceTest.kt` SHA-256 `eb4ec0038e0c25ba0b2711a5032cd608bf83c8c4c8bba5d32dcf929ad317b891`; `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/storage/KeystoreServiceInstrumentedTest.kt` SHA-256 `5c53252cf021b3320b65d8b70f9721655adf5ad650fa7d192150eac9d54378b3`; `apps/feldexa_app/android/app/build.gradle.kts` SHA-256 `165c84f4ee8495f7b4ac8dde6b35591b5a62a2fee9d5265bea0d269eb97d7880`; candidate SHA in external attestation |
| External attestation | worker_done transport attestation (candidate SHA, report bytes and hash); not part of the candidate commit |
| Build identity | app debug unit tests; mode `debug`; instrumentation test APK `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` SHA-256 `3b0c355fcae0037605d8c157aa9224678938961ab91dd354b089d66055b71439` |
| Toolchain | Flutter 3.47.7 (stable, framework `abaf9c5237`), Dart 3.13.5, Gradle 9.3.1, Android Gradle Plugin 9.1.0, Kotlin 2.4.0, Temurin JDK 17.0.21, Android SDK platforms 35/36/37 |
| Input | no corpus; synthetic UUIDv4 aggregate ids and random 32-byte DEKs only; no user data |

## 1. Scope

T025 only: per-document/per-template Android Keystore KEK creation, alias
lifecycle, and DEK wrap/unwrap. The work implements `KeystoreService.kt` and
its content-free failure vocabulary; it does **not** implement
`EncryptedStore.kt`, the FXC1 container, atomic commit, recovery, or the
startup sweep orchestration owned by T026/T031. No push, merge, or self-review
was performed.

Normative sources: `tasks.md` T025; `contracts/storage-format.md` §2.3, §3.6,
§4 step 5, §5 and §7 tests 3/11/13/14; `contracts/ports.md` §3;
`contracts/error-catalog.de.md` §3; the authorized 2026-11-15 per-aggregate
decision; FR-049/FR-050/FR-052.

## 2. Revision and build

Base revision `1f17ad5e590bb4cb99b16f536761f05111797944` was clean before the
task. The reported working tree is dirty only with the T025 implementation,
tests, `app/build.gradle.kts` test dependencies, `tasks.md` status, this report,
and its index row.

Build command: `gradle -p apps/feldexa_app/android :app:testDebugUnitTest`.
The real Android Gradle build compiled the Kotlin source and ran 36 JVM tests
(0 failures, 0 errors, 0 skipped). A separate run compiled the instrumentation
source set and assembled the instrumentation test APK whose hash is in the
metadata and artifacts tables. The candidate SHA is recorded externally; this
report does not assert it.

## 3. Environment

```text
NONE: host Linux x86_64; Gradle 9.3.1 Android build with JVM unit tests;
      JDK 17.0.21; Android SDK compile/target 36; no Android runtime allocation
```

The host's default JDK 27 is rejected by the project's Groovy/AGP path
("Unsupported class file major version 71"), so a Temurin 17 JDK was placed in
the gitignored build work area. The Flutter SDK, Android SDK, pub cache, and
Gradle user home were copied or redirected into the same gitignored work area
because the host mounts them read-only. The project's committed toolchain
versions were not changed.

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `gradle -p apps/feldexa_app/android :app:testDebugUnitTest` (`.`) | `0` | `build/t025-work/logs/real-build-final.log` | `PASS` |
| 2 | `gradle -p apps/feldexa_app/android :app:compileDebugAndroidTestKotlin` (`.`) | `0` | `build/t025-work/logs/androidtest-compile-final.log` | `PASS` |
| 3 | `gradle -p apps/feldexa_app/android :app:assembleDebugAndroidTest` (`.`) | `0` | `build/t025-work/logs/androidtest-apk-final.log` | `PASS` |
| 4 | `gradle -p apps/feldexa_app/android :app:connectedDebugAndroidTest` (`.`) | `1` | `build/t025-work/logs/connected-not-run.log` | `FAIL` |
| 5 | `real-Keystore instrumentation (9 scenarios)` (`apps/feldexa_app/android`) | `-` | `not run` | `UNAVAILABLE` |

Check 4 failed only because no Android device or emulator was connected:
`DeviceException: No connected devices!`. The nine real-Keystore scenarios in
check 5 therefore did not execute and are reported as **`NOT_RUN`**; no
`EMULATOR` or `DEVICE` result is claimed.

## 5. Results

### 5.1 Executed JVM policy tests — 36/36 PASS

The tests use a fake Keystore backend with real AES-GCM (genuine AAD and tag
checks) and switches for provider outage, StrongBox failure, key invalidation,
and delete failure.

| Group | Tests | Proven behavior |
| --- | ---: | --- |
| Aliases and creation | 3 | exact `feldexa.doc.v1.` / `feldexa.tpl.v1.` aliases; one distinct key per aggregate; no `feldexa.master.v1`; idempotent creation never replaces a key |
| Id validation | 2 | invalid and uppercase UUIDv4 ids fail with `PLT-002` before any Keystore access |
| Provider retry | 2 | exactly one 250 ms retry then success; persistent outage is `SAVE-008` retryable with no partial key |
| Existing unusable key | 1 | `SAVE-002`; the existing key is not regenerated |
| StrongBox | 3 | StrongBox used when supported; failure retried in the TEE; TEE only when unsupported |
| Wrap/unwrap primitives | 4 | round-trip; 12/48-byte sizes; fresh IVs; `FXC1-DEK` AAD; 32-byte DEK invariant |
| Key-loss isolation | 4 | missing/invalidated key with a usable sibling → `SAVE-002`, sibling still works; no remaining key → `SAVE-008` retryable=false; unwrap follows the same mapping |
| Corrupt/tamper | 3 | flipped wrapped-key byte, wrong IV length, wrong wrapped length → `SAVE-003`; provider failure during unwrap → `SAVE-008` retryable |
| Delete/sweep | 6 | only the target alias deleted; absent alias idempotent; provider outage removes nothing; sweep deletes orphans only, keeps aliases with directories, ignores foreign aliases, fails closed during provider outage |
| Store status and errors | 8 | all-available, one-missing `SAVE-002`, all-missing/global `SAVE-008`, single-aggregate global rule, provider outage non-fatal, empty store, per-aggregate states, content-free exception text |

The full method names are in `KeystoreServiceTest.kt`; every name states the
behavior under test. The count comes from the AGP test XML, not from a manual
harness.

### 5.2 Contract mapping

| Contract item | Result |
| --- | --- |
| One non-exportable AES-256-GCM KEK per document and template | Implemented in `AndroidKeystoreBackend`; `setUserAuthenticationRequired(false)`, 256-bit, no API returns a `SecretKey` |
| StrongBox best effort, TEE otherwise, never software | StrongBox requested only when the device advertises it; any StrongBox generation failure retried with `strongBox=false`; TEE failure reported |
| DEK 32 bytes, AES-GCM, AAD `FXC1-DEK`, random 12-byte IV, 48-byte wrapped key | Implemented and tested |
| Create before first ciphertext; failure leaves no aggregate | API order documented; failed generation deletes any partial alias |
| Delete objects/directory first, alias last; no other alias touched | `deleteAggregateKey` deletes exactly `ref.alias`; false leaves the orphan for the sweep |
| Sweep only aliases without an aggregate directory | `sweepOrphanAliases` uses the T026-owned directory predicate; malformed prefixed aliases are orphans; foreign aliases untouched |
| `SAVE-002` for one lost key while another remains usable | Implemented and tested |
| `SAVE-008` for provider outage, retried once | Implemented and tested |
| `SAVE-008` for device-wide reset with no remaining key | Implemented and tested; no per-aggregate isolation claim |
| `StoreStatus.keyAvailable` is non-fatal | `storeKeyStatus` returns a status and never throws for a provider outage or missing key |
| No id/path/content in errors | exceptions carry only code, machine message, retry flag, severity |

### 5.3 Contract interpretation note

`contracts/storage-format.md` §2.3 currently groups "unwrap tag mismatch" with
`SAVE-002`, while §5 and `contracts/ports.md` §3 map "DEK unwrap tag
mismatch / corrupt chunk" to `CorruptDataException` (`SAVE-003`). The §2.3
sentence was introduced by `0ac8d3f` while splitting global `SAVE-008`; §5 has
been stable since the baseline.

T025 implements the §5/ports reading: a missing or invalidated KEK is key loss
(`SAVE-002`/`SAVE-008`), while a present KEK that cannot authenticate the
wrapped DEK is `CorruptDataException` (`SAVE-003`, read-side authentication
failure). Corrupt chunks remain T026's `SAVE-003` path. No contract file was
edited because contract correction is outside T025 and belongs to T029/owner
review. The tests pin the chosen behavior so the reviewer can decide.

Two further rules are deliberately literal. With no usable aggregate key left
(including a store with one aggregate), the result is global `SAVE-008`, not
`SAVE-002`, because the contract requires at least one *other* aggregate key
for `SAVE-002` and forbids a false isolation claim. `deleteAggregateKey`
returns false when the alias cannot be removed now; §3.6 explicitly allows the
startup sweep to remove the orphan after the objects are gone.

## 6. Performance

No performance claim. T025 has no timing target; listing-amortized Keystore
unwrap latency is T026/T097 work.

## 7. Limitations

- The 36 passing tests are JVM policy tests with a fake backend. They do not
  prove `AndroidKeyStore` internals, hardware backing, or StrongBox behavior.
- Nine real-Keystore instrumentation tests were written and compiled, and the
  instrumentation test APK was assembled, but they are **`NOT_RUN`**: the ADB
  device list was empty and the KVM device node is absent. Check 4's `FAIL` is
  this environmental prerequisite failure, not a T025 test failure.
- Real provider outage, locked-device boot, device-wide reset, and key
  invalidation remain unproven on Android and are explicitly not claimed.
- Non-exportability (`encoded == null`) was not observed on a runtime; it is
  covered by the compiled instrumentation assertion only.
- The `printing` plugin's platform 34 was synthesized from the installed
  platform 36 metadata because the sandbox could not reach the Google SDK
  package repository. This affects plugin compilation only, not T025 code.
- No release APK, device acceptance, or independent review is claimed.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| unit-test XML | `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.KeystoreServiceTest.xml` | 5413 | `1e6ce849fd3101362db459a96618cbe4d84ecf50f843754d89eaaeb174f820db` |
| instrumentation test APK | `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 366455 | `3b0c355fcae0037605d8c157aa9224678938961ab91dd354b089d66055b71439` |
| successful unit-test log | `build/t025-work/logs/real-build-final.log` | 22246 | `88e6db7475f3bf7f36efa24feb067929bb0ebcbd0aea0686e820962e195a4940` |
| instrumentation compile log | `build/t025-work/logs/androidtest-compile-final.log` | 15465 | `6395bd58a05143dacb45eb3f31bc41dc30fd3221c97f52bda4e5c29b5e43df8e` |
| instrumentation APK log | `build/t025-work/logs/androidtest-apk-final.log` | 20496 | `b9f3538a046c8ac3f2900dcb089950ea0380a543c574cf29994c757cf7ad8d0e` |
| no-device connected-test log | `build/t025-work/logs/connected-not-run.log` | 21642 | `50902e91e2c563fc52de14c3b3bccfa76a5e288a3c16ecdd02a38b0babe6581d` |
| device/KVM probe log | `build/t025-work/logs/emulator-not-run.log` | 401 | `872448f3676d42dac95c71972d294ca5c6c2c98f51090adf721ed2a148d55302` |

Git-ignored logs are local, regenerable support artifacts and are not
candidate contents. This report is intentionally not listed in its own
artifacts table.

## 9. Reproducibility

1. Start from base commit `1f17ad5e590bb4cb99b16f536761f05111797944`.
2. Provide a writable Temurin JDK 17 (17.0.21 was used) and set `JAVA_HOME`.
3. Make writable copies of the Flutter SDK, Android SDK, pub cache, and Gradle
   user home in the gitignored build work area; set `HOME`, `PUB_CACHE`,
   `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `ANDROID_USER_HOME`,
   `GRADLE_USER_HOME`, and the pre-existing read-only Gradle dependency cache.
   Create `apps/feldexa_app/android/local.properties` with `sdk.dir` and
   `flutter.sdk` pointing at the copies.
4. Run `flutter pub get --offline` from the repository root; `pubspec.lock`
   remains unchanged.
5. Run check 1. Expected: 36 tests, 0 failures.
6. Run checks 2 and 3. Expected: both succeed and produce the instrumentation
   test APK.
7. Run check 4 on a host with an allocated emulator/device. On this host it
   stops at `No connected devices!` and check 5 remains `NOT_RUN`.
8. Cleanup: delete the gitignored `build/t025-work/` work area.

## 10. External attestation

The `worker_done` transport record is the external attestation: it names the
exact candidate SHA, this report's bytes and SHA-256, and the T025 task and
dispatch identity. No separate `t025-attestation` ref was created or pushed.
The candidate commit contains this report; therefore it cannot contain its own
SHA-256.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
