# 2026-11-16 EMULATOR — T024 §10 BigInteger sizing and fixed-limit boundary correction

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` |
| Result | `PASS` |
| Task / issue | `T024` / `#24` |
| Date / timezone | `2026-11-16 11:44 Europe/Berlin` |
| Revision | base commit `2d793adc8296ca2025285be0deb853c16b3f5e05`; pre-correction candidate `bd78dcae7ad93f48f174645037aef533108263ab`; the corrected candidate is the commit that contains this report, and its exact SHA, tree, changed-file hashes and report hash are bound in `refs/heads/t024-biginteger-attestation` (local, not pushed) and in the `worker_done` transport record. The only uncommitted file is the pre-existing line-ending phantom `apps/feldexa_app/android/gradlew.bat` SHA-256 `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62`, which is not staged and not part of the candidate |
| Supersedes | `2026-11-16-emulator-t024-total-payload-boundary.md` as the current T024 §10 evidence record. Its total-envelope result stands, but it missed the payload-sized `BigInteger.toString(16)` allocation and its boundary test held the payload fixed while changing the limit |
| External attestation | `refs/heads/t024-biginteger-attestation` (local, not pushed) plus the `worker_done` transport record |
| Build identity | version `1.0` (versionCode `1`); mode `debug`; debug-only `android:largeHeap=true`; app `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` SHA-256 `fe5fe0d200ce04803c85c0f4a882bf8a5c2ce6d4720b877d5c25bb3d079caf98`; instrumentation `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` SHA-256 `48de28ca13344ae0321c75c740ed4b1372af87fb985a347949d0e212ebdd3d1d`; main and release manifest sources unchanged versus base `2d793ad` |
| Toolchain | Flutter `3.47.7` (framework `abaf9c5237`, engine `deb287481e`), Dart `3.13.5`, Gradle `9.3.1`, Kotlin `2.4.0`, Temurin JDK `21.0.13`, Android SDK platform `36`, build-tools `36.0.0` and `35.0.0`, Android Emulator `37.2.12.0`, adb `1.0.41` (`37.0.1`) |
| Input | no corpus; synthetic UUIDv4 aggregate ids, in-memory fake services, synthetic payloads including one 64 Mi-bit `BigInteger` and one 96 MiB + 1 byte array per method; no user document, Keystore alias, file, URI, or device data |

## 1. Scope

This run corrects the accepted Review A finding for T024 #24 in the preserved
recovery worktree. The pre-correction candidate was
`bd78dcae7ad93f48f174645037aef533108263ab` on base
`2d793adc8296ca2025285be0deb853c16b3f5e05`. Review A confirmed the exact
code/report/APK/log evidence and the total-envelope codec count/alignment
formula, but failed `FeldexaPlugin.kt:1483-1485` because the `BigInteger`
branch called `value.toString(16)` before the budget comparison. For a
payload-sized `BigInteger`, that materializes a hexadecimal `String` several
times larger than the magnitude and defeats the guard's bounded-allocation
claim.

The correction derives the exact `StandardMessageCodec` hexadecimal byte
length without materializing the text or any other payload-sized copy. It also
corrects the two other payload-sized copies introduced by the same sizing
implementation: `CharSequence.toString()` and `Iterable.toList()`. The method
count/alignment rules, the 24-method coverage, the per-object caps, the
debug-only large heap, T025/T026 storage, and T028 adapters are unchanged.

The Review request for genuine below/exact/above inputs under one fixed
total-envelope limit is addressed by new host and real Android `MethodChannel`
regressions that keep the limit at 112 bytes and grow only the payload:
111 bytes (accept), 112 bytes (accept, exact), 113 bytes (reject).

This record covers host-JVM regressions, real-codec comparisons, the full
Android instrumentation suite on the Orca-allocated Pixel 7 API 35 KVM AVD,
and source/log/APK identity. It is not a `DEVICE` acceptance, not a full
Dart/Flutter UI journey, not a product acceptance and not a performance claim.

## 2. Revision and build

The correction started at pre-correction candidate
`bd78dcae7ad93f48f174645037aef533108263ab`. The working tree contains the
following T024 changes:

- `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/FeldexaPlugin.kt`
- `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/FeldexaPluginTest.kt`
- `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/FeldexaPluginInstrumentedTest.kt`
- this report, the report-index row and the T024 note in `tasks.md`

The pre-existing `apps/feldexa_app/android/gradlew.bat` line-ending phantom is
not staged and is not part of the candidate. T025/T026 storage code and tests
and the T028 simulated adapters are byte-identical to base
(`git diff --quiet 2d793ad -- apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/storage packages/feldexa_adapters_simulated`
exits `0`). The debug manifest overlay (debug-only `largeHeap`) and the main
and release manifest sources are also byte-identical to candidate `bd78dca`.

The host build used the workspace-local, gitignored shadows
`build/toolchain-flutter` (Flutter `3.47.7`), `build/gradle-home` (Gradle
`9.3.1` with Temurin JDK `21.0.13`), `build/android-sdk` and `build/home`
(writable Flutter/Dart user home). `local.properties` points at those shadows;
a normal writable checkout needs no shadow. From `apps/feldexa_app/android`:

```sh
./gradlew --offline --no-daemon :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest
```

The build finished `BUILD SUCCESSFUL`. The host-JVM suite was then rerun with
`--rerun-tasks` against the final source bytes: **219 tests, 0 failures, 0
errors, 0 skipped**. The app APK is 223362067 bytes SHA-256
`fe5fe0d200ce04803c85c0f4a882bf8a5c2ce6d4720b877d5c25bb3d079caf98`; the
instrumentation test APK is 412601 bytes SHA-256
`48de28ca13344ae0321c75c740ed4b1372af87fb985a347949d0e212ebdd3d1d`.

### 2.1 Codec accounting

The sizing counter mirrors the encoder in the actual Flutter engine
(`flutter_embedding_debug` `1.0.0-deb287481e3ce9468f3434937ced4240a70539ca`)
whose bytecode writes a `BigInteger` as `BIGINT` followed by
`writeBytes(value.toString(16).getBytes(UTF_8))`, and a `CharSequence` as
`STRING` followed by `writeBytes(value.toString().getBytes(UTF_8))`.

The corrected `BigInteger` path computes the length of `toString(16)` from the
number itself:

- zero -> one digit (`"0"`);
- positive -> `ceil(bitLength / 4)` digits;
- negative -> one leading `-` plus the digits of `|value|`. For negatives
  `bitLength()` describes `|value| - 1`, so the magnitude gains one
  significant bit only when it is a power of two; `bitCount() == bitLength()`
  identifies that case without allocating `abs()` or the hex text.

The ASCII result is also the UTF-8 byte length, so the counter adds the type
byte, the variable-width size prefix and that length. A tiny remaining budget
is decided from the type byte and the minimum one-byte text before `bitLength`
or `bitCount` is consulted, so a payload-sized magnitude is never scanned for
a one-byte budget.

`CharSequence` values are measured by scanning code units in place; the
`CharSequence.toString()` contract preserves the characters, so the result is
identical to the codec without materializing the copy. `Collection` values
reached through the `Iterable` branch use `size` and their iterator instead of
`toList()`; only a non-Collection `Iterable` (which `StandardMessageCodec`
does not encode at all) still needs a one-pass snapshot.

The rest of the accounting is unchanged: the method-name string, root map
marker/count, every key, every value recursively, 4/8-byte alignment for typed
numeric arrays and doubles, the 1/3/5-byte size prefixes, and the
`MAX_DEPTH = 64` guard. Per-field limits are unchanged, and every failure is
still the content-free `PLT-003` / `platform.payloadTooLarge` error. No method,
field or error message was added, removed or renamed.

## 3. Environment

```text
EMULATOR: Pixel 7 API 35, exclusive allocation T025_Pixel7_API35_KVM_20261115;
          system image system-images;android-35;google_apis;x86_64 revision 9;
          build fingerprint google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys;
          RAM 3072 MB; APK apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk SHA-256 fe5fe0d200ce04803c85c0f4a882bf8a5c2ce6d4720b877d5c25bb3d079caf98;
          build mode debug, debug-only largeHeap overlay, no rebuild during the instrumentation run.
```

The installed Android guide (`orca skills get orca-emulator-android`) was read
before touching the device. Before attach, `orca emulator list --worktree all
--json` returned no sessions, `orca emulator devices --json` showed every AVD
`shutdown`, and `adb devices -l` listed no device. `orca emulator attach
T025_Pixel7_API35_KVM_20261115 --worktree current --json` returned `attached:
true` for `emulator-5554`. Exactly one Orca session and exactly one adb device
existed before, during and after the run; every other AVD stayed `shutdown`.
The guest reported `ro.boot.qemu.avd_name=T025_Pixel7_API35_KVM_20261115`, API
35, Android 15, `sys.boot_completed=1`, and `service check package` found. With
temporary root adbd (disabled again immediately), the active clocksource was
`kvm-clock` and the available clocksources were `kvm-clock hpet`. The guest
heap properties were `dalvik.vm.heapgrowthlimit=192m` and
`dalvik.vm.heapsize=576m`.

`dumpsys package de.feldexa.app` reported
`pkgFlags=[ DEBUGGABLE HAS_CODE ALLOW_CLEAR_USER_DATA LARGE_HEAP ]`, and
`aapt2 dump xmltree` of the debug APK reports `largeHeap=true`. The release and
main manifest sources are unchanged versus base and candidate, so the large
heap stays confined to the debug harness and is not a release-heap claim.

The AVD retained the previous run's debug-signed `de.feldexa.app` package, so
the first `adb install -r -t` was refused with
`INSTALL_FAILED_UPDATE_INCOMPATIBLE` (the debug signing identity differed
between the old and current writable home). The run removed only
`de.feldexa.app.test` and `de.feldexa.app` and installed both fresh; no other
package, document, URI, file, Keystore alias, or AVD was read, created,
changed, or deleted. Both APKs were installed with `adb install -r -t`; the
pulled installed base APKs are byte-identical to the built APKs. The AVD was
shut down, not wiped.

The dispatched worker runs inside a sandbox that does not expose the host KVM
device node or the host emulator process, so no host file-descriptor claim is
made. The positive runtime evidence is the Orca allocation label, the guest AVD
name and the guest `kvm-clock` clocksource; that limitation is repeated in §7.

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `git rev-parse HEAD` = `bd78dca`; `git rev-parse 2d793ad` = base (`<repo-root>`) | `0` | console only (not retained) | `PASS` |
| 2 | `./gradlew --offline --no-daemon :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest` (`apps/feldexa_app/android`) | `0` | `build/t024-biginteger/logs/gradle-build.log` | `PASS` |
| 3 | `./gradlew --offline --no-daemon :app:testDebugUnitTest --rerun-tasks` (`apps/feldexa_app/android`) | `0` | `build/t024-biginteger/logs/gradle-jvm-final.log` | `PASS` |
| 4 | `orca emulator list --worktree all --json`; `orca emulator devices --json`; `adb devices -l` (`<repo-root>`) | `0` | `build/t024-biginteger/logs/exclusivity-before.log` | `PASS` |
| 5 | `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current --json` (`<repo-root>`) | `0` | `build/t024-biginteger/logs/orca-attach.json` | `PASS` |
| 6 | boot, guest AVD identity, `kvm-clock` clocksource, heap and `service check package` (`<repo-root>`) | `0` | `build/t024-biginteger/logs/device-boot.log` | `PASS` |
| 7 | `adb uninstall` of only the two stale test packages; `adb install -r -t` app and test APKs; `dumpsys package` flags; pull installed APKs and `cmp`/`sha256sum`; `aapt2` largeHeap check (`<repo-root>`) | `0` | `build/t024-biginteger/logs/device-install.log`, `device-apk-identity.log` | `PASS` |
| 8 | `adb shell am instrument -w -r -e class de.feldexa.app.FeldexaPluginInstrumentedTest de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner` (`<repo-root>`) | `0` | `build/t024-biginteger/logs/instrument-t024-class.log` | `PASS` |
| 9 | `adb shell am instrument -w -r de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner` (`<repo-root>`) | `0` | `build/t024-biginteger/logs/instrument-full.log` | `PASS` |
| 10 | test-class/test-name inventory parse of the full run (`<repo-root>`) | `0` | `build/t024-biginteger/logs/test-inventory.log` | `PASS` |
| 11 | `adb logcat -d`; `grep -e "FATAL EXCEPTION" -e OutOfMemoryError` (no matching lines) (`<repo-root>`) | `0` | `build/t024-biginteger/logs/logcat-fatal-scan.log` | `PASS` |
| 12 | `orca emulator list --worktree all --json`; `orca emulator devices --json`; `adb devices -l` during the run (`<repo-root>`) | `0` | `build/t024-biginteger/logs/exclusivity-during.log`, `exclusivity-during-posttest.log` | `PASS` |
| 13 | `orca emulator shutdown --device emulator-5554 --worktree current --json`; then settled session/device/AVD verification (`<repo-root>`) | `0` | `build/t024-biginteger/logs/orca-shutdown.json`, `exclusivity-after.log` | `PASS` |

## 5. Results

### 5.1 Host JVM and build

- `:app:testDebugUnitTest`: **219 tests, 0 failures, 0 errors, 0 skipped**:
  - `FeldexaPluginTest` 96 (T024), including five new regressions:
    `payloadSizeMatchesCodecHexadecimalBigIntegerEncoding`,
    `payloadSizeMatchesCodecBigIntegerEncodingAcrossPowersAndSigns`,
    `payloadSizeMeasuresCharSequenceWithoutMaterializingToString`,
    `largeBigIntegerIsMeasuredWithinTinyBudgetsWithoutHexadecimalCopy`, and
    `fixedTotalEnvelopeAcceptsBelowAndExactPayloadAndRejectsAbove`;
  - `KeystoreServiceTest` 40 and `InstrumentedKeystoreAliasSafetyTest` 3
    (T025, 43);
  - `EncryptedStoreTest` 49, `EncryptedStoreFaultTest` 9,
    `EncryptedStoreHeadHistoryTest` 7, `EncryptedStoreOrderingTest` 2,
    `EncryptedStorePruneRecoveryTest` 5, `EncryptedStoreReviewTest` 8
    (T026, 80).
- `:app:assembleDebug` and `:app:assembleDebugAndroidTest`: `BUILD SUCCESSFUL`.
- The pulled installed app/test base APKs are byte-identical to the built APKs
  (`fe5fe0d2…` and `48de28ca…`).

### 5.2 Android instrumentation

The T024 class run finished **`OK (17 tests)`** in 9.805 s. The full suite
finished **`OK (48 tests)`** in 14.772 s with all status codes `0`:

- `FeldexaPluginInstrumentedTest` **17/17** — the real
  `de.feldexa/platform`/`events`/`results` channel boundary, start/result
  separation, one safe `PLT-001` for `AssertionError`, `SAVE-006` before start,
  cancellation/replay/teardown, the complete §12 payload round-trip, the
  original exact-envelope boundary test, the new fixed-112-byte
  below/exact/above payload regression
  (`fixedTotalEnvelopeBoundaryTracksActualCodecAsPayloadGrows`), and the new
  real-codec `BigInteger`/`CharSequence` comparison
  (`payloadSizeMatchesRealMessageCodecForBigIntegerAndCharSequence`).
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

- The pre-correction `BigInteger` branch was
  `writeBytes(value.toString(16).length.toLong())`. It allocated a
  payload-sized hexadecimal text purely to count it.
- The correction computes the same length from `signum`, `bitLength` and
  `bitCount` only. The host powers/signs test compares the counter with
  `BigInteger.toString(16)` for `2^k`, `-2^k`, `2^k - 1`, `-(2^k - 1)`,
  `2^k + 1` and `-(2^k + 1)` for `k = 0..512`, plus `Long.MAX_VALUE` and
  `Long.MIN_VALUE`; the explicit cases cover zero, `-1`, `0x80`, `0xff`,
  `0x100`, `2^63`, `2^64`, `2^64 - 1` and their negatives.
- The large-value regression uses `2^(64 Mi)` (an 8 MiB magnitude whose hex
  text is 16,777,217 bytes under a 5-byte size prefix). The exact host result
  is 16,777,223 bytes; the negative result adds the `-` byte. Budgets of one
  and two bytes return 2 and 3 without consulting `bitLength` or `bitCount`.
- The Android regression encodes zero, positive, negative, power-of-two and
  adjacent values plus `StringBuilder` instances with the real
  `StandardMessageCodec` and requires the counter to equal the real encoded
  byte count for every value.
- The fixed-limit three-way host regression holds the total-envelope limit at
  112 bytes and changes only `titleHint` (`N`, 39/40/41): the measured method
  call is 111/112/113 bytes, and the facade accepts 111 and 112 and rejects 113
  with `PLT-003` / `platform.payloadTooLarge`. The Android regression takes the
  same 111/112/113 bytes from the real `StandardMethodCodec`, asserts all three
  exact lengths, then drives the real `MethodChannel` and plugin: 111 accepted,
  112 accepted, 113 rejected.
- `CharSequence` is scanned in place and `Collection` Iterables use
  `size`/`iterator`, removing the other two payload-sized copies introduced by
  the sizing implementation. A `StringBuilder` case is compared with the real
  `StandardMessageCodec`.
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
- The debug-only large heap overlay is unchanged, the release and main manifest
  sources are unchanged, and no release-heap behavior is claimed.
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
- Bounded allocation is established by the implementation path (no
  `toString(16)`, `abs()` or `toString()` called for sizing) and by the
  tiny-budget early exit, not by a heap profiler. No allocation-profiler number
  is claimed.
- The sandbox does not expose the host KVM device node or the host emulator
  process, so no host KVM file-descriptor claim is made. Guest `kvm-clock`, the
  AVD name and one-session/one-adb-device observations are the runtime
  allocation evidence.
- The T028 Dart/SIMULATED suites were not rerun; their files are byte-identical
  to base and the correction does not touch them.
- Performance, release build, physical-device and full acceptance claims remain
  `NOT_RUN`.
- The prior Review A/Review B records and the `214 JVM + 46 Android` counts
  apply to the superseded old candidate. The same two review roles must
  revalidate this corrected candidate; this report is author evidence, not
  approval.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Debug app APK | `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 223362067 | `fe5fe0d200ce04803c85c0f4a882bf8a5c2ce6d4720b877d5c25bb3d079caf98` |
| Instrumentation test APK | `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 412601 | `48de28ca13344ae0321c75c740ed4b1372af87fb985a347949d0e212ebdd3d1d` |
| T024 main source | `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/FeldexaPlugin.kt` | 71810 | `bb464bae250751ed49b4b28ce7fcf3425296e54c47a433601587c741292a31da` |
| T024 host tests | `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/FeldexaPluginTest.kt` | 72743 | `04ad0205dcd340dd83a2f6f99f66401f9a2c7cb048095dcac926ee7e06f0a2b2` |
| T024 instrumentation | `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/FeldexaPluginInstrumentedTest.kt` | 31109 | `365320fa41ba82cd2d3be71523eb7071851a751f7be69dddf74c53b9716511d0` |
| Host build | `build/t024-biginteger/logs/gradle-build.log` | 22048 | `d1cca1431cb01878b0c208282c23c7cf10cc057319598ee7baeedee1ee1e583a` |
| Final JVM rerun | `build/t024-biginteger/logs/gradle-jvm-final.log` | 24229 | `b6531c723071a44f0aabd312b36b05706a9cf17cab2679c8cc7f5644ebfe9276` |
| T024 class run | `build/t024-biginteger/logs/instrument-t024-class.log` | 11630 | `d005ae79ace4e380892e183fdd6f5e87899724d1ba7423616266277585a6525d` |
| Full instrumentation | `build/t024-biginteger/logs/instrument-full.log` | 32543 | `a70cadeedd5af32022413b9dadc511d96e1ac10ec3beccdf247784b941cf530e` |
| Test inventory | `build/t024-biginteger/logs/test-inventory.log` | 1176 | `52676d77e179f28ed14b58e55f5de99062de4251d3992eb62f088be3d084d8bd` |
| Device boot/identity | `build/t024-biginteger/logs/device-boot.log` | 1808 | `250cc9a4b0fe1838817ba5088e66a00e4f7b72235c2bf323ccff347428384f48` |
| Install/package evidence | `build/t024-biginteger/logs/device-install.log` | 1589 | `488662f046ae278cc8ceed2685d536c3898e2592bfd09ccfb604455c0e615f64` |
| In-guest APK identity | `build/t024-biginteger/logs/device-apk-identity.log` | 1360 | `220b0b9b80e9ef73a46960cd6fb7b98a0815f47158092657b9defd6f730cbbac` |
| Exclusivity before | `build/t024-biginteger/logs/exclusivity-before.log` | 2169 | `1fe66b8cf62e404e5c20b9415684c31870734e61467a5c0ca701ec310ae61d07` |
| Exclusivity during | `build/t024-biginteger/logs/exclusivity-during.log` | 1269 | `18e3e7a27c1b4e65e0f131695f74281a84963b155f5e00dc586173ae4237d151` |
| Exclusivity during (post-test) | `build/t024-biginteger/logs/exclusivity-during-posttest.log` | 1169 | `7573fc2ac663abe4e001a78577a2ee6c1f825326718db7839bd76a8ce0e1cc66` |
| Exclusivity after | `build/t024-biginteger/logs/exclusivity-after.log` | 766 | `03a77774fd6a88766344673a6499fdd0dfa20fd12194453037fe76995a9640bc` |
| Orca attach | `build/t024-biginteger/logs/orca-attach.json` | 357 | `537bdb37f44d213960f5b4be1f812dbf6d2061ffb4c06b41275203f6ad31b0d8` |
| Orca shutdown | `build/t024-biginteger/logs/orca-shutdown.json` | 208 | `d8ecaec33682fa72d3e6f202c8efad52230599d428ec37ea957cb6d55af96158` |
| Logcat fatal scan (empty) | `build/t024-biginteger/logs/logcat-fatal-scan.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| Full logcat | `build/t024-biginteger/logs/logcat-full.log` | 5284180 | `8f55b0d8468434aca3706cb7b2d636bdb0d8bfc74211cf0f996e058d09fe7840` |

## 9. Reproducibility

1. Start from base commit `2d793adc8296ca2025285be0deb853c16b3f5e05`, or from
   pre-correction candidate `bd78dcae7ad93f48f174645037aef533108263ab`.
2. Apply the T024 sizing correction to `FeldexaPlugin.kt`, add the five host
   regressions to `FeldexaPluginTest.kt`, and add the two real-codec Android
   regressions to `FeldexaPluginInstrumentedTest.kt`; add this report, the
   README index row and the T024 task note. The `gradlew.bat` phantom is not
   staged.
3. From `apps/feldexa_app/android`, run
   `./gradlew --offline --no-daemon :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest`
   with workspace-local Flutter/Gradle/Android shadows and a writable home.
   Expected: `BUILD SUCCESSFUL`, 219 JVM tests pass, and the two APK SHA-256
   values match §8.
4. Verify no other emulator session, no other adb device and every AVD in
   `shutdown`; `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree
   current --json`; wait for `sys.boot_completed=1`, `service check package`
   found, and guest clocksource `kvm-clock`.
5. Remove only stale `de.feldexa.app.test`/`de.feldexa.app` packages if the
   debug signing identity changed; `adb install -r -t` both APKs; verify
   `dumpsys package de.feldexa.app` shows `LARGE_HEAP`, pull the installed base
   APKs, and compare their SHA-256 with §8.
6. Run the T024 class and then the full suite:
   `adb shell am instrument -w -r -e class de.feldexa.app.FeldexaPluginInstrumentedTest de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner`
   and `adb shell am instrument -w -r de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner`.
   Expected: 17/17 T024 and `OK (48 tests)` (17 T024 + 12 T025 + 19 T026).
7. Scan logcat for `FATAL EXCEPTION` or `OutOfMemoryError`, then
   `orca emulator shutdown --device emulator-5554 --worktree current --json`
   and verify no session, no adb device and every AVD `shutdown`.

## 10. External attestation

`refs/heads/t024-biginteger-attestation` (local, not pushed) is a commit whose
parent is the final candidate and whose JSON file names the final candidate
SHA and tree, the pre-correction candidate `bd78dca`, the base `2d793ad`, this
report's path/bytes/SHA-256, the changed-file hashes, the APK hashes and the
host/Android test results. The `worker_done` transport record repeats the final
candidate SHA and the report hash. The attestation is created after the final
candidate commit and is not part of the candidate tree.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
