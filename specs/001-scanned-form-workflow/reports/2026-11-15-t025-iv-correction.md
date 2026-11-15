# 2026-11-15 NONE — T025 provider-generated wrap IV correction

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `PARTIAL` |
| Task / issue | `T025` / `#25` |
| Date / timezone | `2026-11-15 03:03 Europe/Berlin` |
| Revision | base commit `96a3bbb45c23eb42b98be56f0bfc0c061d2891f7`; tree `dirty` `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage/KeystoreService.kt` SHA-256 `f8d2c4062183bf5725d2fad37a6b9a675261498fe87cd3bbfc037e8bd90e87d0`; `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/storage/KeystoreServiceTest.kt` SHA-256 `0bbf9f740a441635b8a6e85ec7028656628b72fb3559513ec0ab25e3d268df43`; `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/storage/KeystoreServiceInstrumentedTest.kt` SHA-256 `b71a1c32e52e380b75db0abeebe317ba48da9f3448af23237f79a58949cb3718`; candidate SHA in external attestation |
| External attestation | worker_done transport attestation (candidate SHA, report bytes and hash); not part of the candidate commit |
| Build identity | app debug unit tests; mode `debug`; instrumentation test APK `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` SHA-256 `a1d136a8419af4c76791719e9d457c06e32a3290265475f906d178976f5ffd89` |
| Toolchain | Flutter 3.47.7 (stable, framework `abaf9c5237`), Dart 3.13.5, Gradle 9.3.1, Android Gradle Plugin 9.1.0, Kotlin 2.4.0, Temurin JDK 17.0.21, Android SDK 36 |
| Input | no corpus; synthetic UUIDv4 aggregate ids and random 32-byte DEKs only; no user data |

## 1. Scope

This report covers the T025 correction after the independent review of
`96a3bbb`. The review found that `KeystoreService.kt:658` enabled
`setRandomizedEncryptionRequired(true)` while `:689-694` initialized the
encryption `Cipher` with a caller-supplied `GCMParameterSpec`, which Android
Keystore rejects for GCM encryption. The fix uses a provider-generated IV and
keeps the FXC1 12-byte `wrapIv` format. T026, contracts, German text, and the
prior T025 evidence report are untouched. No push, merge, or self-review was
performed.

Normative basis: `contracts/storage-format.md` §2.1/§2.3 (wrap IV length 12,
random IV, AES-GCM AAD `FXC1-DEK`), `KeyGenParameterSpec.Builder`
documentation in the installed Android SDK sources
(`android/security/keystore/KeyGenParameterSpec.java`), and the 2026-11-15
per-aggregate key decision.

## 2. Revision and build

Base for this correction is `96a3bbb45c23eb42b98be56f0bfc0c061d2891f7`
(the prior T025 implementation). The reported working tree is dirty only with
the three T025 source/test files named in the metadata, this report, and its
index row.

Commands: `gradle -p apps/feldexa_app/android :app:testDebugUnitTest`
(40/40 tests), then
`gradle -p apps/feldexa_app/android :app:compileDebugAndroidTestKotlin
:app:assembleDebugAndroidTest` (both successful). The instrumentation test APK
hash is in the metadata and artifacts tables. The candidate SHA is recorded
externally; this report does not assert it.

## 3. Environment

```text
NONE: host Linux x86_64, 4 logical CPUs; Gradle 9.3.1 Android build with
      JVM unit tests; JDK 17.0.21; Android SDK 36; no accepted Android
      runtime evidence. A software-emulated AVD probe was attempted and is
      reported as NOT_RUN for the reasons in §5/§7.
```

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `gradle -p apps/feldexa_app/android :app:testDebugUnitTest` (`.`) | `0` | `build/t025-work/logs/iv-fix-test.log` | `PASS` |
| 2 | `gradle -p apps/feldexa_app/android :app:compileDebugAndroidTestKotlin :app:assembleDebugAndroidTest` (`.`) | `0` | `build/t025-work/logs/iv-fix-androidtest.log` | `PASS` |
| 3 | `gradle -p apps/feldexa_app/android :app:connectedDebugAndroidTest` (`.`) | `1` | `build/t025-work/logs/iv-fix-connected-emulator-2.log` | `FAIL` |
| 4 | `real-Keystore instrumentation (10 scenarios)` (`apps/feldexa_app/android`) | `-` | `not run` | `UNAVAILABLE` |

Check 3 failed in the test harness because the software-emulated guest lost
its package service; check 4 therefore did not execute and is reported as
**`NOT_RUN`**. No `EMULATOR` or `DEVICE` result is claimed.

## 5. Results

### 5.1 Review finding confirmed

The installed Android SDK documentation for
`KeyGenParameterSpec.Builder.setRandomizedEncryptionRequired` states that when
IND-CPA is required, "in block modes which use an IV, such as GCM, CBC, and
CTR, caller-provided IVs are rejected when encrypting". It directs callers to
initialize the cipher for encryption without an IV and read the generated IV
from `Cipher.getIV()`. The reviewed code did the opposite: it generated a
random IV in `KeystoreService.wrapDek` and passed it via `GCMParameterSpec` to
`Cipher.init(ENCRYPT_MODE, ...)`. That is rejected by Android Keystore while
`setRandomizedEncryptionRequired(true)` remains in force.

### 5.2 Minimal safe fix

- `KeystoreBackend.encrypt` no longer accepts an IV. The production backend
  initializes GCM encryption without `GCMParameterSpec`, lets Android Keystore
  generate the random IV, and reads it back from `cipher.iv`.
- `KeystoreService.wrapDek` returns that provider-generated IV in
  `WrappedDek.wrapIv`; it no longer calls `SecureRandom` itself. The wrapper
  validates exactly 12 IV bytes and 48 wrapped-key bytes before returning, and
  fails closed with `SAVE-008` if the provider returned malformed material.
- `KeystoreService.unwrapDek` still passes the stored 12-byte IV to the
  decrypt `Cipher`; caller-provided IVs are only prohibited on encryption.
- `setRandomizedEncryptionRequired(true)` is retained, so the provider keeps
  enforcing IND-CPA and fresh IVs. The FXC1 header fields `wrapIvLength = 12`
  and `wrapIv` are unchanged; no on-disk format change or contract edit is
  needed.

### 5.3 Tests

| Test group | Count | Evidence |
| --- | ---: | --- |
| Existing T025 policy tests (aliases, lifecycle, StrongBox, SAVE-002/008, store status) | 36 | still pass |
| New: `wrap uses the provider-generated iv` | 1 | returned `wrapIv` equals the backend-generated IV |
| New: `unwrap uses the stored wrap iv` | 1 | decrypt receives the stored `wrapIv` |
| New: `wrap rejects a provider iv that is not twelve bytes` | 1 | malformed provider output fails closed with `SAVE-008` |
| New: `wrap rejects a provider wrapped key of the wrong length` | 1 | 48-byte invariant enforced |
| **JVM total** | **40** | 0 failures, 0 errors, 0 skipped |
| Instrumentation regression `providerGeneratesFreshTwelveByteIvForEveryWrap` | 1 of 10 | compiled into the test APK; execution `NOT_RUN` |

The JVM fake now mirrors the provider contract: its `encrypt` method has no IV
parameter, generates the IV itself, and returns it with the ciphertext. This
makes a caller-IV regression impossible to express through the service API.
The instrumentation test would fail on the reviewed implementation because
`wrapDek` would throw on the caller IV; it is the Android runtime guard for the
fix.

### 5.4 Emulator probe

The available AVD was copied into the gitignored work area; the original AVDs
were not modified. The probe used an isolated copy of
`Feldexa_E2E_ATD31` (API 31, x86_64, ATD image), 4 vCPUs, 4 GiB, no snapshot,
read-only, and software TCG (`-no-accel`).

- KVM is unavailable: the emulator acceleration check exited 8 with "KVM ...
  not found", and the KVM device node is absent.
- The guest did boot under TCG; the emulator log records
  `Boot completed in 622502 ms` (about 10m 22s).
- The guest then crash-looped: `adb logcat -b crash` showed
  `FATAL EXCEPTION IN SYSTEM PROCESS` with
  `java.lang.IllegalStateException: Lost network stack` in
  `com.android.server.SystemServer`. The `package` and `activity` services
  disappeared repeatedly; the package service was observed as `found` for
  roughly one minute and then `not found` again.
- `connectedDebugAndroidTest` failed with
  `Failed to install split APK(s)` and
  `cmd: Can't find service: package`. Manual push/install attempts also
  failed because ADB went offline during the push/install window.

This is an emulator-runtime instability, not a T025 test failure. The real
Android run is `NOT_RUN` with the exact reason above; no `EMULATOR` evidence is
claimed.

## 6. Performance

No performance claim. T025 has no timing target in this correction.

## 7. Limitations

- The 40 passing tests are JVM policy tests with a fake backend. They prove
  the provider-IV API shape, FXC1 12/48 invariants, and failure mapping; they
  do not prove AndroidKeyStore behavior.
- The 10 instrumentation tests compile and their APK assembles, but they are
  **`NOT_RUN`** on a real Android runtime because the only available
  software-emulated guest crash-loops its system server and loses the package
  service. Check 3's `FAIL` is this environmental failure, not a T025 test
  failure.
- Real StrongBox/TEE behavior, hardware-backed key generation, provider
  outage, and device reset remain unproven on Android and are not claimed.
- The guest log buffer was cleared by the system-server restart before the
  crash stack could be retained as a file; the quoted stack is the observed
  `logcat -b crash` output from the probe, while the install failure is
  retained in the check log.
- No release APK, device acceptance, or independent review is claimed. The
  second review remains external.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| unit-test XML | `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.KeystoreServiceTest.xml` | 5934 | `77f6e8ee86eb6ab31880a82a4b1fa829861b3863d92188c564719bef74d2a2e7` |
| instrumentation test APK | `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 373019 | `a1d136a8419af4c76791719e9d457c06e32a3290265475f906d178976f5ffd89` |
| unit-test log | `build/t025-work/logs/iv-fix-test.log` | 28264 | `1ef08ab060eaf8aa0d0d6652c7a33767f57ae5d9ea30d5fa80da3b4d47961ecd` |
| instrumentation compile/APK log | `build/t025-work/logs/iv-fix-androidtest.log` | 26656 | `9f92608a65fc8ee895857fce3851d28291bc77aa0774721e1db8dde81e9c323d` |
| connected-test failure log | `build/t025-work/logs/iv-fix-connected-emulator-2.log` | 30962 | `6221d723f10a369b1d4f6caa918ae097676301a70da29006120cd13c4b7b9f79` |
| emulator toolchain/probe log | `build/t025-work/logs/emulator-not-run-iv.log` | 610 | `9ebe0bcadfe687bf3bdcba89d17853641b903c1fe8034ec02a6dfe09a4f7217f` |
| TCG boot log | `build/t025-work/logs/emulator-tcg-3.log` | 10739 | `2dbe4178b0872db7f707ef3dcf0e24386d8d5da1788a6ca3a2df8589a84d0408` |

Git-ignored logs are local, regenerable support artifacts and are not
candidate contents. This report is intentionally not listed in its own
artifacts table.

## 9. Reproducibility

1. Start from base commit `96a3bbb45c23eb42b98be56f0bfc0c061d2891f7`.
2. Provide a writable Temurin JDK 17 and the project's Gradle/Flutter/Android
   toolchain as described in the prior T025 report; keep the committed
   `pubspec.lock` unchanged.
3. Run check 1. Expected: 40 tests, 0 failures. The four new tests are the
   provider-IV/malformed-output regressions.
4. Run check 2. Expected: instrumentation sources compile and
   `app-debug-androidTest.apk` is produced.
5. For the runtime probe, copy an AVD into the gitignored work area and start
   it read-only with software TCG (`-no-accel`, no snapshot). On this host the
   guest reaches `Boot completed` but the system server crashes with "Lost
   network stack" and the package service is lost; check 4 therefore remains
   `NOT_RUN`.
6. Cleanup: delete the gitignored work area and the copied AVD. No original
   AVD, device, or worktree was modified.

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
