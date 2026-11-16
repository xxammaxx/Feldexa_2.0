# 2026-11-16 EMULATOR — T024 Main integration of `2d793ad` with T024/T025/T026 Android evidence

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` |
| Result | `PASS` |
| Task / issue | `T024` / `#24` |
| Date / timezone | `2026-11-16 10:34–10:44 Europe/Berlin` |
| Base / merge | pre-merge T024 candidate `dac5e40d6075a172a5a93759a69b49d0d460548b`; `origin/main` `2d793adc8296ca2025285be0deb853c16b3f5e05` (exact target, no drift); normal merge commit `fc23b6c2170e86012888d2d7e6bb702cc7e3ece6` with parents `dac5e40` and `2d793ad` |
| Revision | final candidate is the HEAD commit that contains this report; tree at validation time was merge commit `fc23b6c` plus the pending report/task/index edits named in §3; tree state of the working copy also contains the pre-existing `gradlew.bat` line-ending phantom (not staged, not part of the candidate); exact candidate SHA and this report's bytes/hash are in the external attestation |
| External attestation | `refs/heads/t024-main-2d793ad-attestation` (local, not pushed) plus the `worker_done` transport record; they record the final candidate SHA, merge parents, this report's bytes and SHA-256, the changed-file list, APK hashes, and the test results |
| Build identity | versionName `1.0` (versionCode `1`), mode `debug`, `android:largeHeap="true"` in the debug overlay only; app `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` 225374593 bytes SHA-256 `300f4d52cfef3b167e38ab5ad4831a1eb57b3db02a29df190d65a829c5024e6c`; instrumentation test `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` 506094 bytes SHA-256 `991276a7d52ed8109e09cecc326aca61554af3ceea79a14ce07de6a0a57eacf4` |
| Toolchain | Flutter `3.47.7` (framework `abaf9c5237`), Dart `3.13.5`, Gradle wrapper `9.3.1`, Kotlin `2.4.0`, JetBrains Runtime `21.0.11`, Android SDK platform `36`/build-tools `35` (shadow also carries platform `34`), Android Emulator `37.2.12.0`, adb `1.0.41` (`37.0.1`) |
| Input | no corpus; synthetic UUIDv4 aggregate ids, in-memory fake services, synthetic OCR bytes, one synthetic 96 MiB + 1 payload per method, and synthetic T026 store documents/aliases; no user document, Keystore, file, URI, or device data |

## 1. Scope

The coordinator supplied the next stage for issue #24: normal-merge the actual
current `origin/main` into the accepted T024 handoff candidate without history
rewrite, preserve all T025/T026 storage work and T028 adapters, resolve
conflicts minimally, revalidate the merged source and contracts, and produce
real Android evidence for the merged tree on the Orca-allocated Pixel 7 API 35
AVD. The task also required the genuine installed `speckit-implement` workflow
scoped to T024, the installed `orca-emulator-android` guide, and the canonical
report root.

This record covers the merge, the host JVM/build checks, the Android channel,
Keystore and encrypted-store instrumentation, and the exact APK/source
bindings. It is not a `DEVICE` acceptance, not a full Dart UI journey, not a
release-heap claim, and not a performance claim. Independent review remains
with the two existing review roles and the Maintainer.

## 2. Normative context and readings

The following were read before acting:

- `.specify/memory/constitution.md` v1.0.0 in full (Principles I–X,
  architecture constraints, gates, governance, non-weakenable guarantees).
- `.specify/scripts/bash/check-prerequisites.sh` resolved
  `FEATURE_DIR=specs/001-scanned-form-workflow` with
  `AVAILABLE_DOCS=research.md, data-model.md, contracts/, quickstart.md,
  tasks.md` after setting `SPECIFY_FEATURE_DIRECTORY` (the workspace has no
  `.specify/feature.json`).
- `specs/001-scanned-form-workflow/plan.md`, including the ports/adapters
  architecture, storage design, delivery phases, architecture decisions, risks,
  evidence plan, and complexity tracking.
- `specs/001-scanned-form-workflow/tasks.md` scoped to T024; the task's T025,
  T026, T027 and T028 lines were read but no non-T024 task was implemented.
- The changed contracts: `platform-channel.md` (T024 async start/result
  protocol plus T026 retention additions), `storage-format.md`, and
  `ports.md`; the canonical report template/rules in
  `specs/001-scanned-form-workflow/reports/README.md`.
- Installed `speckit-implement` skill from
  `.dsh/skills/speckit-implement`; installed `orca-emulator-android` guide via
  `orca skills get orca-emulator-android`.
- `.specify/extensions.yml` contains `hooks: {}`; there were no
  `before_implement` or `after_implement` hooks to run.
- Checklist status: `checklists/requirements.md` is 16/16 checked;
  `checklists/precision-testability.md` is reviewer-owned with 36 unchecked
  items and its assessment is recorded in
  `checklists/precision-testability-assessment.md`. The markers were not
  edited. The coordinator's explicit instruction authorized continuing the
  T024 integration scoped by this task; no other checklist conclusion is
  claimed.

## 3. Merge and conflict decisions

`origin/main` was fetched and compared first: it points exactly at
`2d793adc8296ca2025285be0deb853c16b3f5e05`, whose first parent is `99f63df` and
whose second parent is `19b0983` (T028 PR #184). The merge base with the T024
candidate was `d78114f`.

The merge was a normal `git merge --no-ff origin/main` (no rebase,
cherry-pick, amend, or force). Two files conflicted; both were resolved
minimally:

1. `specs/001-scanned-form-workflow/contracts/platform-channel.md`
   - `store.saveRevision` response: kept the T024 asynchronous shape ("start
     reply, then …") and added T026's `prunedRevisions` to the terminal result
     data.
   - Rules: kept T024's exact optimistic-concurrency sentence (same-document
     save rejected before the start reply; post-start `expectedHead` mismatch is
     a terminal `SAVE-006` result) and added T026's retention rule
     (last 3 autosave + newest explicit + newest recovery + protected head) and
     the bounded `head.history` rule.
   - T024's §1 channel split, §2.4 async start/result protocol, §8.2 result
     replay, §9 threading/cancellation and §12 contract-test table remain
     intact. No T024 test requirement was weakened.
2. `specs/001-scanned-form-workflow/reports/README.md`
   - Kept all nine T024 evidence rows (including the payload-round-trip report)
     and added the T028 evidence row from main. Main's T026 report rows are
     preserved in the same index.

`tasks.md` auto-merged: the T024 `[x]` note is preserved, and T026/T028 carry
main's `[x]` text. No task other than T024 was implemented or re-marked.

Preservation was verified after the merge: `git diff --quiet origin/main HEAD
-- apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage
apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/storage/EncryptedStoreInstrumentedTest.kt
packages/feldexa_adapters_simulated` exits `0`, so T025 `KeystoreService`,
T026 `EncryptedStore` and the T026 instrumentation/tests, and all T028
simulated adapters/tests are byte-identical to `origin/main`. The T024 facade,
payload instrumentation, debug-only largeHeap overlay, and evidence reports are
the only product changes the branch adds on top of main.

The final delta against `origin/main` is limited to the T024 implementation
files, the T024 instrumentation, the debug manifest overlay, the T024 evidence
reports, and the three documentation files updated by this task. The T026
storage contract additions are present in the merged `platform-channel.md`,
`storage-format.md`, `ports.md`, and `data-model.md`.

## 4. Revision and build

The build used the same workspace-local, gitignored shadows required by the
worker's read-only sandbox as the previous T024 run: `build/toolchain-flutter`
(Flutter `3.47.7`), `build/gradle-home` (Gradle `9.3.1` with JBR 21),
`build/pub-cache` with the ignored `.dart_tool/package_config.json` and
`apps/feldexa_app/.flutter-plugins-dependencies` rewritten to that copy, and
`build/android-sdk` with SDK Platform 34 added from
`platform-34-ext7_r03.zip` (SHA-1 `1f2e9478d6a7601425ceaa553311dc43191f103d`).
`local.properties` is gitignored and points at those shadows. A normal writable
checkout needs no shadow.

From `apps/feldexa_app/android`:

```sh
./gradlew --offline --no-daemon -Dorg.gradle.java.home=$JAVA_HOME \
  :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest
```

`BUILD SUCCESSFUL` in 1m07s; both APKs produced and the test APK contains the
three instrumentation classes.

## 5. Environment

```text
EMULATOR: Pixel 7 API 35, exclusive allocation T025-PIXEL7-API35-KVM-20261115;
          system image system-images;android-35;google_apis;x86_64 revision 9;
          build fingerprint google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys;
          RAM 3072 MB; app APK SHA-256 300f4d52cfef3b167e38ab5ad4831a1eb57b3db02a29df190d65a829c5024e6c;
          build mode debug, debug-only largeHeap overlay, no rebuild during the run.
```

Before attach, `orca emulator list --worktree all --json` returned no sessions,
`orca emulator devices --json` showed every AVD `shutdown`, and `adb devices -l`
listed no device. `orca emulator attach T025_Pixel7_API35_KVM_20261115
--worktree current --json` returned `attached: true` for `emulator-5554`.
Exactly one Orca session for this T024 worktree and exactly one adb device were
observed before, during, and after the run; every other AVD stayed `shutdown`.

The guest reported `ro.boot.qemu.avd_name=T025_Pixel7_API35_KVM_20261115`, API
35, Android 15, `sys.boot_completed=1`, and `service check package` found. With
temporary root adbd (disabled again immediately), the active clocksource was
`kvm-clock` and the available clocksources were `kvm-clock tsc hpet`; guest CPU
flags included `avx`, `f16c`, and `hypervisor`. The guest heap properties were
`dalvik.vm.heapgrowthlimit=192m` and `dalvik.vm.heapsize=576m`.

`dumpsys package de.feldexa.app` reported
`pkgFlags=[ DEBUGGABLE HAS_CODE ALLOW_CLEAR_USER_DATA LARGE_HEAP ]`, and
`aapt2 dump xmltree` of the rebuilt debug APK reports `largeHeap=true`. The
release and main manifest sources are unchanged versus `origin/main`
(`git diff --quiet` on `src/main/AndroidManifest.xml` and
`src/release/AndroidManifest.xml`), so the large heap stays confined to the
debug harness and is not a release-heap claim.

No package-level signature mismatch occurred; both APKs were installed with
`adb install -r -t`. No other package, document, URI, file, Keystore alias, or
AVD was read, created, changed, or deleted. The AVD was shut down, not wiped.

## 6. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `git fetch origin main`; `git rev-parse origin/main` = `2d793ad…` (repo root) | `0` | console only | `PASS` |
| 2 | `git merge --no-ff origin/main` reported two conflicts (exit `1`); minimal resolution then commit `fc23b6c` (repo root) | `1` → `0` | `git show fc23b6c` | `PASS` after resolution |
| 3 | `git diff --quiet origin/main HEAD -- apps/.../storage apps/.../EncryptedStoreInstrumentedTest.kt packages/feldexa_adapters_simulated` (repo root) | `0` | console only | `PASS` |
| 4 | `./gradlew --offline … :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest` (`apps/feldexa_app/android`) | `0` | `build/t024-main-2d793ad/logs/gradle-build.log` | `PASS` |
| 5 | aggregate `TEST-*.xml` under `apps/feldexa_app/build/app/test-results/testDebugUnitTest` (repo root) | `0` | `build/t024-main-2d793ad/logs/jvm-summary.log` | `PASS` |
| 6 | `orca emulator list --worktree all --json`, `orca emulator devices --json`, `adb devices -l` (repo root) | `0` | `build/t024-main-2d793ad/logs/exclusivity-before.log` | `PASS` |
| 7 | `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current --json` (repo root) | `0` | `build/t024-main-2d793ad/logs/orca-attach.json` | `PASS` |
| 8 | boot, identity, `service check package`, heap, CPU flags, root clocksource readback (repo root) | `0` | `build/t024-main-2d793ad/logs/device-evidence.log` | `PASS` |
| 9 | `adb install -r -t` app and test APKs; `dumpsys package` and `aapt2` largeHeap check (repo root) | `0` | `build/t024-main-2d793ad/logs/device-evidence.log` | `PASS` |
| 10 | `am instrument -w -r de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner` (repo root) | `0` | `build/t024-main-2d793ad/logs/instrument-full.log` | `PASS` |
| 11 | test-class/test-name inventory parse (repo root) | `0` | `build/t024-main-2d793ad/logs/test-inventory.log` | `PASS` |
| 12 | pull installed base APKs and SHA-256 compare (repo root) | `0` | `build/t024-main-2d793ad/logs/apk-hashes.log` | `PASS` |
| 13 | `adb logcat -d` fatal/OOM scan (repo root) | `0` (no lines) | `build/t024-main-2d793ad/logs/logcat-fatal-scan.log` | `PASS` |
| 14 | `orca emulator shutdown --device emulator-5554 --worktree current --json`, then session/device/AVD verification | `0` | `build/t024-main-2d793ad/logs/exclusivity-after.log` | `PASS` |

## 7. Results

### 7.1 Host JVM and build

- `:app:testDebugUnitTest`: **211 tests, 0 failures, 0 errors, 0 skipped**:
  - `FeldexaPluginTest` 88 (T024);
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
  (`300f4d52…` and `991276a7…`).

### 7.2 Android instrumentation

The full suite finished **`OK (45 tests)`** in 17.949 s with all status codes
`0`:

- `FeldexaPluginInstrumentedTest` **14/14** — the real
  `de.feldexa/platform`/`events`/`results` channel boundary, start/result
  separation, one safe `PLT-001` for `AssertionError`, `SAVE-006` before start,
  cancellation/replay/teardown, and the complete §12 payload round-trip:
  24/24 unknown-field rejections, 126 strict-UUID rejections across 21 field
  instances in 16 methods, and 24/24 96 MiB + 1 total-payload rejections.
- `KeystoreServiceInstrumentedTest` **12/12** — real `AndroidKeyStore`
  round-trip, per-aggregate alias isolation, non-exportability, exact-only
  test cleanup and foreign-alias guard.
- `EncryptedStoreInstrumentedTest` **19/19** — real-keystore create/save/load,
  read-back, head history and retention/pruning, prune-fsync retry and
  no-resurrection behavior, aggregate key loss `SAVE-002` vs global `SAVE-008`,
  tamper `SAVE-003`, legacy-head retention, parallel-save serialization,
  boundary sizes, and no plaintext residue.

Logcat contained no `FATAL EXCEPTION` or `OutOfMemoryError` for
`de.feldexa.app`.

### 7.3 Contract and source compatibility

- The merged `platform-channel.md` keeps the T024 async start/result protocol
  and adds the T026 `prunedRevisions` field and bounded `head.history` rules.
- The merged `storage-format.md`, `ports.md`, and `data-model.md` retain main's
  T026 retention/durability text (auto-merged; no T024 edit overwrote them).
- T025/T026 Kotlin sources and tests and all T028 simulated adapters/tests are
  byte-identical to `origin/main`; the T026 additions compile and pass their
  JVM and real-device suites on the merged tree.
- No T027 or non-T024 task was started; T028's full Dart editor journey
  (T128) remains outside this task.

### 7.4 Allocation and cleanup

Exactly one Orca session (`emulator-5554`) and one adb device existed before,
during, and after the run. The only device mutation was installing the two
T024/T025/T026 test packages. Orca shutdown returned success, the session list
was empty, adb listed no device, and all AVDs were `shutdown`. The dedicated
AVD remains in place and was not wiped.

## 8. Limitations and `NOT_RUN`

- This is `EMULATOR` evidence, not `DEVICE` acceptance and not a physical-device
  journey.
- The T024 tests attach the real plugin to an in-process `BinaryMessenger` and
  real channels; they do not start a Dart isolate or run the Flutter app UI.
- The 96 MiB payload rejection uses the debug-only largeHeap harness; the
  release manifest is unchanged and no release-heap behavior is claimed.
- No full Dart/Flutter UI, SAF import, OCR, export, delivery, or product
  acceptance journey was run; those remain `NOT_RUN`.
- The T026 tests exercise the storage core and real Keystore directly, not a
  full app-level persistence journey.
- The T028 Dart/SIMULATED suites were not rerun; their files are byte-identical
  to main's reviewed state and the merge did not touch them.
- Performance, release build, physical-device, and accessibility claims remain
  `NOT_RUN`.
- Independent review by the two existing review roles and Maintainer
  integration/acceptance decisions remain pending; this report is author
  evidence, not approval.

## 9. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Debug app APK | `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 225374593 | `300f4d52cfef3b167e38ab5ad4831a1eb57b3db02a29df190d65a829c5024e6c` |
| Instrumentation test APK | `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 506094 | `991276a7d52ed8109e09cecc326aca61554af3ceea79a14ce07de6a0a57eacf4` |
| T024 instrumentation source | `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/FeldexaPluginInstrumentedTest.kt` | 25875 | `b9af0ca6acf62f6226dd3bc90681a5d871154b2990d65b6099a51d30f2c4841f` |
| T025 instrumentation source | `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/storage/KeystoreServiceInstrumentedTest.kt` | 13494 | `3d85f02a002fbd296f6582c1989596eb06de32f54e3e25bc39a020aa8c280228` |
| T026 instrumentation source | `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/storage/EncryptedStoreInstrumentedTest.kt` | 30732 | `fad5ec5e29874473788e197a16d3b73b87e7ad90dca1cb9aa20dcb88f5646c27` |
| Debug manifest overlay | `apps/feldexa_app/android/app/src/debug/AndroidManifest.xml` | 896 | `0b8fdc86353bc245b248439529586f221aa01a2b72d3982b7a6dd1e2e9cda1dc` |
| Gradle build and JVM tests | `build/t024-main-2d793ad/logs/gradle-build.log` | 22299 | `65baedd15b4d54da84a5bd8d5d795a81b1c223fccdf89728e073868480f87bdc` |
| JVM test summary | `build/t024-main-2d793ad/logs/jvm-summary.log` | 998 | `acb5211039c354ed5e3dc60c0e93871ca6a2b975c8b665c3135632194005fd7b` |
| Test inventory | `build/t024-main-2d793ad/logs/test-inventory.log` | 4526 | `b5b772617fb274820853ddb8b26cc13d24b87d00b887b91d3244257426bccb4f` |
| Full instrumentation | `build/t024-main-2d793ad/logs/instrument-full.log` | 30468 | `9d0064a50e886b2c2756a053f177ffa83a78293d36b85977bfa5b16c6aab7055` |
| APK identity | `build/t024-main-2d793ad/logs/apk-hashes.log` | 782 | `07c55f35e082daaee2fe3c8513f56c0ea1518607280984c1d815459c8438f53f` |
| Exclusivity baseline | `build/t024-main-2d793ad/logs/exclusivity-before.log` | 2154 | `b8684bd8be685c1a0a3e313240b58007f91f4d5f49a6b7dc555363ab2f62ccb7` |
| Orca attach | `build/t024-main-2d793ad/logs/orca-attach.json` | 357 | `4a21dc54685c2f7a65183d5a68839967cbdbbbabe1d44c708255d84c2eb7d3df` |
| Device/heap/KVM evidence | `build/t024-main-2d793ad/logs/device-evidence.log` | 2288 | `154040ec84225915e17412b668bad52301b59f3c8087727618fe33790b3c559f` |
| Logcat fatal scan (empty) | `build/t024-main-2d793ad/logs/logcat-fatal-scan.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| Cleanup verification | `build/t024-main-2d793ad/logs/exclusivity-after.log` | 2155 | `ba8a464aca7e0cc16334d63ded7c85bcc7613fa6783b06a450e5ad9ead6072f9` |
| Orca shutdown | `build/t024-main-2d793ad/logs/orca-shutdown.json` | 208 | `95b8d4137ae08c1107438ee31e1e75fc77c15b4645db610ce635e595cc08705e` |
| Pre-merge candidate | `dac5e40d6075a172a5a93759a69b49d0d460548b` | — | git commit |
| Main target | `2d793adc8296ca2025285be0deb853c16b3f5e05` | — | git commit |
| Merge commit | `fc23b6c2170e86012888d2d7e6bb702cc7e3ece6` | — | git commit |

## 10. Reproducibility

1. Fetch `origin/main`; verify it is exactly
   `2d793adc8296ca2025285be0deb853c16b3f5e05`. Check out the pre-merge candidate
   `dac5e40d6075a172a5a93759a69b49d0d460548b`.
2. `git merge --no-ff origin/main` and resolve only
   `contracts/platform-channel.md` (keep T024 async start/result and add
   `prunedRevisions` + retention/history rules) and
   `reports/README.md` (keep all T024 rows, add the T028 row). Expected merge
   parents: `dac5e40` and `2d793ad`.
3. Verify `git diff --quiet origin/main HEAD -- apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage packages/feldexa_adapters_simulated` and the T026 instrumentation file.
4. From `apps/feldexa_app/android`, build with Gradle `9.3.1` and JBR 21:
   `./gradlew --offline --no-daemon :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest`.
   Expected: 211 JVM tests pass; APK SHA-256 values match §9.
5. Verify exclusivity (`orca emulator list --worktree all --json`, `orca emulator devices --json`, `adb devices -l`), then
   `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current --json`; wait for `sys.boot_completed=1` and `service check package` found.
6. Install both APKs with `adb -s emulator-5554 install -r -t`; verify
   `dumpsys package de.feldexa.app` shows `LARGE_HEAP`, and pull the installed
   base APKs to compare SHA-256 with §9.
7. `adb -s emulator-5554 shell am instrument -w -r de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner`.
   Expected: `OK (45 tests)`: 14 T024, 12 T025, 19 T026.
8. `orca emulator shutdown --device emulator-5554 --worktree current --json`;
   verify no session, no adb device, all AVDs `shutdown`.

## 11. External attestation

`refs/heads/t024-main-2d793ad-attestation` (local, not pushed) and the
`worker_done` transport record name the final candidate SHA, the merge parents,
this report's bytes and SHA-256, the changed-file list, and the APK/test
results. The attestation is created after the final candidate commit and is not
part of the candidate tree.

## 12. Independent review (author leaves blank)

| Reviewer | Role | Date | Verdict | Notes |
| --- | --- | --- | --- | --- |
|  | Review role 1 |  |  |  |
|  | Review role 2 |  |  |  |

Exactly two existing independent review roles are to assess this final
candidate; the author does not review or approve this work.
