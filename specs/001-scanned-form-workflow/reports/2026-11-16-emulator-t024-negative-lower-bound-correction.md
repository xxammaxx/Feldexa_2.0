# 2026-11-16 EMULATOR — T024 §10 negative `BigInteger` lower-bound correction

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` |
| Result | `PASS` |
| Task / issue | `T024` / `#24` |
| Date / timezone | `2026-11-16 12:06 Europe/Berlin` |
| Revision | base commit `2d793adc8296ca2025285be0deb853c16b3f5e05`; pre-correction candidate `41b005d79ccbbe3af2ee687b1b1da8ed5190a361`; the final candidate is the commit that contains this report, and its exact SHA, tree, changed-file hashes, report hash, APK hashes and test results are bound in `refs/heads/t024-negative-boundary-attestation` (local, not pushed) and in the `worker_done` transport record. The only uncommitted file is the pre-existing line-ending phantom `apps/feldexa_app/android/gradlew.bat` SHA-256 `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62`, which is not staged and not part of the candidate |
| Supersedes | `2026-11-16-emulator-t024-biginteger-sizing-correction.md` as the current T024 §10 evidence record. Its exact codec formula, total-envelope accounting, `CharSequence`/`Iterable` corrections and fixed-112-byte below/exact/above result stand, but it short-circuited only the one-byte minimum and then called `bitCount()` on a negative magnitude before rejecting an obviously over-budget representation |
| External attestation | `refs/heads/t024-negative-boundary-attestation` (local, not pushed) plus the `worker_done` transport record |
| Build identity | version `1.0` (versionCode `1`); mode `debug`; debug-only `android:largeHeap=true`; app `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` SHA-256 `a42b68b26d8b1591e6995cbaff208d3e4e102840ee1f25676afc70f776cd7dc5`; instrumentation `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` SHA-256 `66c8df518a3ae495199e365695c7c2076e3e003c79dd878ee57f853f1ada8047`; main and release manifest sources unchanged versus base `2d793ad`; the debug manifest overlay is unchanged versus pre-correction candidate `41b005d` |
| Toolchain | Flutter `3.47.7` (framework `abaf9c5237`, engine `deb287481e`), Dart `3.13.5`, Gradle `9.3.1`, Kotlin Gradle plugin `2.4.0`, Temurin JDK `21.0.13`, Android SDK platforms `34`/`35`/`36`, build-tools `35.0.0`/`36.0.0`, Android Emulator `37.2.12.0`, adb `1.0.41` (`37.0.1`) |
| Input | no corpus; synthetic UUIDv4 aggregate ids, in-memory fake services, synthetic payloads including one 8 Mi-bit host `BigInteger`, one 1 Mi-bit Android `BigInteger` and one 96 MiB + 1 byte array per method; no user document, Keystore alias, file, URI, or device data |

## 1. Scope

This run corrects the accepted Review A finding for T024 #24 in the preserved
recovery worktree on candidate
`41b005d79ccbbe3af2ee687b1b1da8ed5190a361` over base
`2d793adc8296ca2025285be0deb853c16b3f5e05`. Review A
(`ctx_0bad3464293e`, maintainer-verified) confirmed the exact codec
formula/evidence/merge preservation but failed `FeldexaPlugin.kt:1453-1457`:
after the type byte, the `BigInteger` branch only ruled out a one-byte text
budget, then the negative branch of `hexStringLength()` called
`value.bitCount()` across the full magnitude to distinguish a power-of-two
magnitude from `|value| - 1`, before rejecting an integer whose encoded length
was already far above the remaining budget.

The correction adds a cheap representation-length lower bound derived only
from `signum` and `bitLength()` and checks it before the exact negative
disambiguation. `bitLength()` reads the leading magnitude word (constant
time), whereas `bitCount()` is the only operation that scans every magnitude
word. The lower bound is safe: it never overstates the exact
`toString(16)` byte length, so a payload rejected by the bound is also
rejected by the exact count. The exact path, the codec equivalence for
accepted values, the zero/sign/power-of-two and size-prefix semantics, the
per-object caps, the 24-method coverage, the debug-only large heap,
T025/T026 storage and T028 adapters remain unchanged.

This record covers host-JVM regressions, real-codec Android regressions, the
full Android instrumentation suite on the Orca-allocated Pixel 7 API 35 KVM
AVD, and source/log/APK identity. It is not a `DEVICE` acceptance, not a full
Dart/Flutter UI journey, not a product acceptance and not a performance claim.

## 2. Revision and build

The correction started at pre-correction candidate
`41b005d79ccbbe3af2ee687b1b1da8ed5190a361`. The working tree contains the
following T024 changes:

- `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/FeldexaPlugin.kt`
- `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/FeldexaPluginTest.kt`
- `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/FeldexaPluginInstrumentedTest.kt`
- this report, the report-index row and the T024 note in `tasks.md`

The pre-existing `apps/feldexa_app/android/gradlew.bat` line-ending phantom is
not staged and is not part of the candidate. T025/T026 storage code and tests
and the T028 simulated adapters are byte-identical to base
(`git diff --quiet 2d793ad -- apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/storage packages/feldexa_adapters_simulated`
exits `0`). The main and release manifest sources are byte-identical to base
`2d793ad`; the debug manifest overlay (debug-only `largeHeap`) and every other
file outside the three T024 files are byte-identical to pre-correction
candidate `41b005d`.

The host build used the workspace-local, gitignored shadows
`build/toolchain-flutter` (Flutter `3.47.7`), `build/gradle-home` (Gradle
`9.3.1` with Temurin JDK `21.0.13`), `build/android-sdk` and `build/home`
(writable Flutter/Dart user home). `local.properties` points at those shadows;
a normal writable checkout needs no shadow. From `apps/feldexa_app/android`:

```sh
./gradlew --offline --no-daemon :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest
```

The build finished `BUILD SUCCESSFUL`. The host-JVM suite was then rerun with
`--rerun-tasks` against the final source bytes: **221 tests, 0 failures, 0
errors, 0 skipped**. The app APK is 223362067 bytes SHA-256
`a42b68b26d8b1591e6995cbaff208d3e4e102840ee1f25676afc70f776cd7dc5`; the
instrumentation test APK is 413997 bytes SHA-256
`66c8df518a3ae495199e365695c7c2076e3e003c79dd878ee57f853f1ada8047`.

### 2.1 Codec accounting

The sizing counter still mirrors the encoder in the actual Flutter engine
(`flutter_embedding_debug` `1.0.0-deb287481e3ce9468f3434937ced4240a70539ca`)
whose bytecode writes a `BigInteger` as `BIGINT` followed by
`writeBytes(value.toString(16).getBytes(UTF_8))`. The exact formula is
unchanged:

- zero -> one digit (`"0"`);
- positive -> `ceil(bitLength / 4)` digits;
- negative -> one leading `-` plus the digits of `|value|`; for negatives
  `bitLength()` describes `|value| - 1`, so the magnitude gains one
  significant bit only when it is a power of two, identified exactly by
  `bitCount() == bitLength()`.

The new cheap lower bound is computed before that exact disambiguation:

- `digits = ceil(bitLength / 4)`;
- zero -> `1`; positive -> `digits`; negative -> `digits + 1` (the `-`).

For positives the bound is exact. For negatives, `|value|` is at most one bit
wider than `|value| - 1`, so `ceil(bitLength / 4)` digits cannot exceed the
exact digit count; adding the `-` keeps the bound below or equal to the exact
text length. The `StandardMessageCodec` size prefix is monotonic in the text
length, so `type byte + prefix(lowerBound) + lowerBound` is itself a lower
bound of the exact encoded size. If that lower bound exceeds the remaining
budget, the exact representation cannot fit, and the branch rejects with
`size = limit + 1` without calling `bitCount()`. Otherwise the unchanged exact
`hexStringLength()` computes the precise length and the existing
`writeBytes()` accounting is applied.

The one- and two-byte minimum check remains first, so those budgets are
decided without even calling `bitLength()`. No serialized copy, `toString(16)`,
`abs()`, `toString()` or magnitude-wide scan is added; `bitLength()` is
constant time and `bitCount()` is reached only when the lower bound leaves
room for a possible fit. The rest of the accounting is unchanged: the
method-name string, root map marker/count, every key, every value recursively,
4/8-byte alignment for typed numeric arrays and doubles, the 1/3/5-byte size
prefixes, the `MAX_DEPTH = 64` guard, and every per-object cap. Failure remains
the content-free `PLT-003` / `platform.payloadTooLarge` error. No method, field
or error message was added, removed or renamed.

## 3. Environment

```text
EMULATOR: Pixel 7 API 35, exclusive allocation T025_Pixel7_API35_KVM_20261115;
          system image system-images;android-35;google_apis;x86_64;
          build fingerprint google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys;
          APK apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk SHA-256 a42b68b26d8b1591e6995cbaff208d3e4e102840ee1f25676afc70f776cd7dc5;
          build mode debug, debug-only largeHeap overlay, no rebuild during the instrumentation run.
```

The installed Android emulator guide (`orca-emulator-android`, saved as
`build/t024-emulator-android-guide.txt`) was consulted before touching the
device. Before attach, `orca emulator list --worktree all --json` returned no
sessions, `orca emulator devices --json` showed every AVD `shutdown`, and
`adb devices -l` listed no device. `orca emulator attach
T025_Pixel7_API35_KVM_20261115 --worktree current --json` returned
`attached: true` for `emulator-5554`. Exactly one Orca session and exactly one
adb device existed before, during and after the run; every other AVD stayed
`shutdown`. The guest reported
`ro.boot.qemu.avd_name=T025_Pixel7_API35_KVM_20261115`, API 35, Android 15,
`sys.boot_completed=1`, and `service check package` found. With temporary root
adbd (disabled again immediately and the shell user restored), the active
clocksource was `kvm-clock` and the available clocksources were
`kvm-clock tsc hpet`. The guest heap properties were
`dalvik.vm.heapgrowthlimit=192m` and `dalvik.vm.heapsize=576m`.

`dumpsys package de.feldexa.app` reported
`pkgFlags=[ DEBUGGABLE HAS_CODE ALLOW_CLEAR_USER_DATA LARGE_HEAP ]`, and
`aapt2 dump xmltree` of the debug APK reports `largeHeap=true`. The release and
main manifest sources are unchanged versus base, so the large heap stays
confined to the debug harness and is not a release-heap claim.

The AVD retained the previous run's debug-signed `de.feldexa.app` package. The
run removed only `de.feldexa.app.test` and `de.feldexa.app` and installed both
fresh; no other package, document, URI, file, Keystore alias, or AVD was read,
created, changed, or deleted. Both APKs were installed with `adb install -r
-t`; the pulled installed base and test APKs are byte-identical to the built
APKs (`cmp` exits `0` and the SHA-256 values match). The AVD was shut down, not
wiped.

The dispatched worker runs inside a sandbox that does not expose the host KVM
device node or the host emulator process, so no host file-descriptor claim is
made. The positive runtime evidence is the Orca allocation label, the guest AVD
name and the guest `kvm-clock` clocksource; that limitation is repeated in §7.

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `git rev-parse HEAD` = `41b005d`; `git rev-parse 2d793ad` = base (`<repo-root>`) | `0` | console only (not retained) | `PASS` |
| 2 | `./gradlew --offline --no-daemon :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest` (`apps/feldexa_app/android`) | `0` | `build/t024-negative/logs/gradle-build.log` | `PASS` |
| 3 | `./gradlew --offline --no-daemon :app:testDebugUnitTest --rerun-tasks` (`apps/feldexa_app/android`) | `0` | `build/t024-negative/logs/gradle-jvm-final.log` | `PASS` |
| 4 | Test-result XML inventory, 9 classes (`<repo-root>`) | `0` | `build/t024-negative/logs/jvm-test-inventory.log` | `PASS` (221 tests, 0 failures/errors/skipped) |
| 5 | `orca emulator list --worktree all --json`; `orca emulator devices --json`; `adb devices -l` (`<repo-root>`) | `0` | `build/t024-negative/logs/exclusivity-before.log` | `PASS` |
| 6 | `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current --json` (`<repo-root>`) | `0` | `build/t024-negative/logs/orca-attach.json` | `PASS` |
| 7 | boot, guest AVD identity, `kvm-clock` clocksource, heap and `service check package` (`<repo-root>`) | `0` | `build/t024-negative/logs/device-boot.log` | `PASS` |
| 8 | `adb uninstall` of only the two stale test packages; `adb install -r -t` app and test APKs; `dumpsys package` flags; pull installed APKs and `cmp`/`sha256sum`; `aapt2` largeHeap check (`<repo-root>`) | `0` | `build/t024-negative/logs/device-install.log`, `device-apk-identity.log` | `PASS` |
| 9 | `adb shell am instrument -w -r -e class de.feldexa.app.FeldexaPluginInstrumentedTest de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner` (`<repo-root>`) | `0` | `build/t024-negative/logs/instrument-t024-class.log` | `PASS` (`OK (18 tests)`) |
| 10 | `adb shell am instrument -w -r de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner` (`<repo-root>`) | `0` | `build/t024-negative/logs/instrument-full.log` | `PASS` (`OK (49 tests)`) |
| 11 | test-class/test-name inventory parse of the full run (`<repo-root>`) | `0` | `build/t024-negative/logs/test-inventory.log` | `PASS` (18 T024 + 12 T025 + 19 T026) |
| 12 | `adb logcat -d`; `grep -e "FATAL EXCEPTION" -e OutOfMemoryError` (no matching lines) (`<repo-root>`) | `0` | `build/t024-negative/logs/logcat-full.log`, `logcat-fatal-scan.log` | `PASS` |
| 13 | `orca emulator list --worktree all --json`; `orca emulator devices --json`; `adb devices -l` during the run (`<repo-root>`) | `0` | `build/t024-negative/logs/exclusivity-during.log`, `exclusivity-during-posttest.log` | `PASS` |
| 14 | toolchain version capture: Flutter, JDK, Gradle, adb, emulator, Kotlin plugin (`<repo-root>`) | `0` | `build/t024-negative/logs/toolchain.log` | `PASS` |
| 15 | `orca emulator shutdown --device emulator-5554 --worktree current --json`; then settled session/device/AVD verification (`<repo-root>`) | `0` | `build/t024-negative/logs/orca-shutdown.json`, `exclusivity-after.log` | `PASS` |

## 5. Results

### 5.1 Host JVM and build

- `:app:testDebugUnitTest`: **221 tests, 0 failures, 0 errors, 0 skipped**:
  - `FeldexaPluginTest` 98 (T024), including the two new Review-A regressions
    `hugeNegativeBigIntegerRejectsBeforeNegativeBitCountDisambiguation` and
    `acceptedNearBoundaryNegativeBigIntegersStayExact`;
  - `KeystoreServiceTest` 40 and `InstrumentedKeystoreAliasSafetyTest` 3
    (T025, 43);
  - `EncryptedStoreTest` 49, `EncryptedStoreFaultTest` 9,
    `EncryptedStoreHeadHistoryTest` 7, `EncryptedStoreOrderingTest` 2,
    `EncryptedStorePruneRecoveryTest` 5, `EncryptedStoreReviewTest` 8
    (T026, 80).
- `:app:assembleDebug` and `:app:assembleDebugAndroidTest`: `BUILD SUCCESSFUL`.
- The pulled installed app/test base APKs are byte-identical to the built APKs
  (`a42b68b2…` and `66c8df51…`).

### 5.2 Android instrumentation

The T024 class run finished **`OK (18 tests)`** in 10.094 s. The full suite
finished **`OK (49 tests)`** in 14.54 s with all status codes `0`:

- `FeldexaPluginInstrumentedTest` **18/18** — the real
  `de.feldexa/platform`/`events`/`results` channel boundary, start/result
  separation, one safe `PLT-001` for `AssertionError`, `SAVE-006` before start,
  cancellation/replay/teardown, the complete §12 payload round-trip, the
  original exact-envelope boundary test, the fixed-112-byte below/exact/above
  payload regression, the real-codec `BigInteger`/`CharSequence` comparison
  (now also covering the negative 254-byte and 65,536-byte text boundaries),
  and the new ART-level
  `hugeNegativeBigIntegerRejectsBeforeBitCountOnAndroidRuntime`.
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

- The pre-correction negative path was:
  `if (size + 1 + 1 > limit) reject; writeBytes(hexStringLength(value))`, and
  `hexStringLength()` called `value.bitCount()` for negatives. A negative
  magnitude far larger than the remaining budget therefore paid a full
  magnitude scan before the obvious rejection.
- The correction extracts the pure `sizePrefixBytes()` helper (a behavioural
  no-op for every existing caller) and adds
  `hexStringLengthLowerBound()`: `ceil(bitLength / 4)` digits, plus one for
  the negative sign, with zero handled as one digit. The guard checks
  `size + sizePrefixBytes(lowerBound) + lowerBound > limit` before calling
  the exact `hexStringLength()`.
- `hugeNegativeBigIntegerRejectsBeforeNegativeBitCountDisambiguation` uses a
  `BitCountTrackingBigInteger` test double over `|value| = 2^8_388_608`
  (a 1 MiB magnitude whose exact negative text is 2,097,154 bytes and whose
  exact encoded size is 2,097,160 bytes). At budgets 3, 4, 253, 254, 65,535,
  65,536 and `exact - 2`, the counter returns `budget + 1` with
  `bitCountCalls == 0` and at least one `bitLength` call. At `exact - 1` the
  lower bound leaves room, exactly one `bitCount()` runs and the exact path
  still rejects; at `Long.MAX_VALUE` the exact size is returned with one
  `bitCount()`. At budgets 1 and 2 neither `bitLength()` nor `bitCount()` is
  called. This is deterministic instrumentation, not a timing assertion.
- `acceptedNearBoundaryNegativeBigIntegersStayExact` covers negative text
  lengths 253/254/255 and 65,535/65,536 (both size-prefix transitions) with
  non-power-of-two "all ones" magnitudes, plus power-of-two magnitudes with
  text lengths 254 and 16,386. Every case matches `toString(16).length`, is
  measured exactly, is accepted at a budget equal to its exact encoded size,
  and is rejected at one byte less. The power-of-two case at text length 254
  has a lower bound exactly one byte short of exact, so its facade test
  (`export.validate`, `-(2^1008)` nested in the plan) accepts the exact total
  method envelope and rejects `envelope - 1` with `PLT-003` /
  `platform.payloadTooLarge` only after the exact disambiguation.
- The Android test double repeats the 1 Mi-bit case on ART: budget 1024
  returns 1025 with zero `bitCount()` calls and at least one `bitLength()`
  call; `exact - 1` returns the exact size after one `bitCount()`; the exact
  budget is accepted. A plain `-(2^1_048_576)` is encoded by the real
  `StandardMessageCodec` and matches the counter. The existing real-codec
  comparison also encodes the new negative 254-byte and 65,536-byte boundary
  values.
- Exact codec equivalence is preserved: the existing powers/signs sweep
  (`2^k`, `-2^k`, `2^k - 1`, `-(2^k - 1)`, `2^k + 1`, `-(2^k + 1)` for
  `k = 0..512`, plus `Long.MAX_VALUE`/`Long.MIN_VALUE`), the explicit zero,
  `-1`, `0x80`, `0xff`, `0x100`, `2^63`, `2^64`, `2^64 - 1` cases and the real
  `StandardMessageCodec` Android comparison all pass. No narrower type,
  value or payload restriction was introduced.
- Per-object limits are preserved and still enforced: signature 2 MiB maps to
  `SAVE-007`, revision 32 MiB maps to `SAVE-007`, and export plan 8 MiB maps to
  `PLT-003`; the existing host tests for those limits pass.
- Failure remains content-free: no payload bytes, keys, values, titles, paths
  or URIs are placed in the error or details. The accounting never allocates a
  second serialized copy; large byte arrays contribute their length directly,
  text is scanned by code unit, and `BigInteger` contributes a derived length.
- The existing method-spanning tests remain: unknown fields 24/24, strict UUID
  regex across 16 methods with 21 field instances and six malformed shapes
  each, and 96 MiB + 1 values 24/24.

### 5.4 Scope preservation

- T025/T026 storage Kotlin sources and tests and the T028 simulated adapters
  are byte-identical to base; the T025 12/12 and T026 19/19 Android tests pass
  unchanged on the same AVD.
- The T024 async start/result protocol, error mapping, cancellation, replay and
  lifecycle behavior are unchanged except for the sizing fix.
- The debug-only large heap overlay is byte-identical to the pre-correction
  candidate, and the main and release manifest sources are byte-identical to
  base; no release-heap behavior is claimed.
- `apps/feldexa_app/android/gradlew.bat` was not touched; its pre-existing
  line-ending difference remains uncommitted and outside the candidate.

## 6. Performance

No performance claim.

## 7. Limitations

- This is `EMULATOR` evidence, not `DEVICE` acceptance and not a physical-device
  journey.
- The T024 instrumentation attaches the real plugin to an in-process
  `BinaryMessenger` and real channels; it does not start a Dart isolate or run
  the Flutter app UI. No full Dart/Flutter UI, SAF import, OCR, export,
  delivery, or product acceptance journey was run.
- The exact fixed-limit boundary is proven at 111/112/113 bytes through the real
  codec and channel; the suite does not allocate an exact 96 MiB accepted
  payload.
- The absence of `bitCount()` on the early-rejection path is proven by the
  deterministic `BitCountTrackingBigInteger` override, not by a heap profiler
  or a wall-clock measurement. No allocation-profiler or timing number is
  claimed.
- The sandbox does not expose the host KVM device node or the host emulator
  process, so no host KVM file-descriptor claim is made. Guest `kvm-clock`, the
  AVD name and one-session/one-adb-device observations are the runtime
  allocation evidence.
- The T028 Dart/SIMULATED suites were not rerun; their files are byte-identical
  to base and the correction does not touch them.
- Performance, release build, physical-device and full acceptance claims remain
  `NOT_RUN`.
- The prior Review A/Review B records and the `219 JVM + 48 Android` counts
  apply to the superseded pre-correction candidate. The same two review roles
  must revalidate this corrected candidate; this report is author evidence, not
  approval.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Debug app APK | `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 223362067 | `a42b68b26d8b1591e6995cbaff208d3e4e102840ee1f25676afc70f776cd7dc5` |
| Instrumentation test APK | `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 413997 | `66c8df518a3ae495199e365695c7c2076e3e003c79dd878ee57f853f1ada8047` |
| T024 main source | `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/FeldexaPlugin.kt` | 73462 | `7e5b0b222c9d8a02f73af912694aeccf22327276ba3811152bb0895b705d14c9` |
| T024 host tests | `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/FeldexaPluginTest.kt` | 78857 | `47a088d5a44650acd4201b326a3f156d3a706cc5b2219becab597e124cb03610` |
| T024 instrumentation | `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/FeldexaPluginInstrumentedTest.kt` | 33556 | `2283f09bbb47f172357a5c195b42c7dd9d8bcd6e4f88eefff3c96779ef537212` |
| Host build | `build/t024-negative/logs/gradle-build.log` | 34410 | `85379693dde98bea5bb8975e47a45cd17da73f7e6ff723083877064c50a58397` |
| Final JVM rerun | `build/t024-negative/logs/gradle-jvm-final.log` | 71184 | `339b17514b0a6d12dd04dc0293e7d3b971cb69e4fc7e845b9ae8c532dce2a9ae` |
| JVM test inventory | `build/t024-negative/logs/jvm-test-inventory.log` | 830 | `0b1af022c9fd4b766d8606f77fd0af5a4c103f39dc1a1b943fe0fd5329ab9d9d` |
| T024 class run | `build/t024-negative/logs/instrument-t024-class.log` | 12320 | `f35d5062b520c0789ddfb8f412c2673912580a449f8f9d9106d0ef369b0b8406` |
| Full instrumentation | `build/t024-negative/logs/instrument-full.log` | 33231 | `3afcf7b364d3ae407483e7102f1207a3f88b406a38d19499d6d698e6b221000e` |
| Test inventory | `build/t024-negative/logs/test-inventory.log` | 1234 | `8857d7752c7738dc27ee0c8e76617f8013f51a769d3a3d529c14da0ffd8de054` |
| Device boot/identity | `build/t024-negative/logs/device-boot.log` | 428 | `4219860ea30e4699e0a359e9158d4c07b1964b8971b288d7229590eddba11fce` |
| Install/package evidence | `build/t024-negative/logs/device-install.log` | 291 | `8e22eaa0b3f897b115b5025589be66e954cba7f4f2d3dbe4c80e3407e6a16388` |
| In-guest APK identity | `build/t024-negative/logs/device-apk-identity.log` | 1552 | `db4f72aba6355ffe09a9d18638f77e21e14cd94c8743bdeede82db461ca82a43` |
| Exclusivity before | `build/t024-negative/logs/exclusivity-before.log` | 2161 | `3dbe96f7915ac9cd150f358b9f1fd6e5d9a30ca3421c612454eac16bf97cc2da` |
| Exclusivity during | `build/t024-negative/logs/exclusivity-during.log` | 2590 | `9fdf5e93ff537e9f57a19f7b3d2b51f05b729426e30d90cc55976d4e26a605b4` |
| Exclusivity during (post-test) | `build/t024-negative/logs/exclusivity-during-posttest.log` | 2605 | `53f3aa89c180e8a4903b18dd57425a1a62307395bf1329488df54986bd79913b` |
| Exclusivity after | `build/t024-negative/logs/exclusivity-after.log` | 2148 | `c2891775f207681ca17cbfb9eddea1df9fa04abce8fe15cb4a64e12cb0918e61` |
| Orca attach | `build/t024-negative/logs/orca-attach.json` | 357 | `45a753b78af550ecc190ba9804456c49b72611b92cdd901ac59daa02f0c267a0` |
| Orca shutdown | `build/t024-negative/logs/orca-shutdown.json` | 208 | `9bbf26c4eaaa91d1efb8fa7cd90d8d64abca3f0c44ac540bd7e9e8520c45c330` |
| Toolchain versions | `build/t024-negative/logs/toolchain.log` | 1903 | `c743414a045f7b93ed6dc42536d4e8a02113b0b488fed93abfb9dd712da29932` |
| Logcat fatal scan (empty) | `build/t024-negative/logs/logcat-fatal-scan.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| Full logcat | `build/t024-negative/logs/logcat-full.log` | 436423 | `513548936131b5c7c13bc49ac06a0a61118c4619efe7aec28c60335b235472d1` |

## 9. Reproducibility

1. Start from base commit `2d793adc8296ca2025285be0deb853c16b3f5e05`, or from
   pre-correction candidate `41b005d79ccbbe3af2ee687b1b1da8ed5190a361`.
2. Apply the T024 negative lower-bound correction to `FeldexaPlugin.kt`, add
   the two host regressions and the `BitCountTrackingBigInteger` double to
   `FeldexaPluginTest.kt`, and add the ART-level large-negative regression and
   boundary values to `FeldexaPluginInstrumentedTest.kt`; add this report, the
   README index row and the T024 task note. The `gradlew.bat` phantom is not
   staged.
3. From `apps/feldexa_app/android`, run
   `./gradlew --offline --no-daemon :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest`
   with workspace-local Flutter/Gradle/Android shadows and a writable home.
   Expected: `BUILD SUCCESSFUL`, 221 JVM tests pass, and the two APK SHA-256
   values match §8. Rerun the unit test task with `--rerun-tasks` for the final
   JVM byte confirmation.
4. Verify no other emulator session, no other adb device and every AVD in
   `shutdown`; `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree
   current --json`; wait for `sys.boot_completed=1`, `service check package`
   found, and guest clocksource `kvm-clock`.
5. Remove only stale `de.feldexa.app.test`/`de.feldexa.app` packages if the
   signing identity changed; `adb install -r -t` both APKs; verify
   `dumpsys package de.feldexa.app` shows `LARGE_HEAP`, pull the installed base
   and test APKs, and compare their SHA-256 with §8.
6. Run the T024 class and then the full suite:
   `adb shell am instrument -w -r -e class de.feldexa.app.FeldexaPluginInstrumentedTest de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner`
   and `adb shell am instrument -w -r de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner`.
   Expected: 18/18 T024 and `OK (49 tests)` (18 T024 + 12 T025 + 19 T026).
7. Scan logcat for `FATAL EXCEPTION` or `OutOfMemoryError`, then
   `orca emulator shutdown --device emulator-5554 --worktree current --json`
   and verify no session, no adb device and every AVD `shutdown`.

## 10. External attestation

`refs/heads/t024-negative-boundary-attestation` (local, not pushed) is a commit
whose parent is the final candidate and whose JSON file names the final
candidate SHA and tree, the pre-correction candidate `41b005d`, the base
`2d793ad`, this report's path/bytes/SHA-256, the changed-file hashes, the APK
hashes and the host/Android test results. The `worker_done` transport record
repeats the final candidate SHA and the report hash. The attestation is created
after the final candidate commit and is not part of the candidate tree.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
