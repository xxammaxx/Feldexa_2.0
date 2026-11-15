# 2026-11-15 EMULATOR — T025 Pixel 7 API 35 KVM Keystore run

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` |
| Result | `PASS` |
| Task / issue | `T025` / `#25` |
| Date / timezone | `2026-11-15 15:42 Europe/Berlin` |
| Revision | base commit `4952f7875905212818101a147566d16de206c0ed`; tree `dirty` `specs/001-scanned-form-workflow/tasks.md` SHA-256 `e08a05c6ebb9010d7992eb4cfd0793df39e7a9347edfb70aefa5dbe16484dc9b`; `specs/001-scanned-form-workflow/reports/README.md` SHA-256 `85147b2ded442184b00e933937bfc2d09f93f7a40e42f575f4ca43a3a09dc1e2`; candidate SHA in external attestation |
| External attestation | `worker_done` transport attestation records the candidate SHA, this report's bytes and SHA-256, and the changed files; not part of the candidate commit |
| Build identity | versionName `1.0` (versionCode `1`), mode `debug`, no rebuild; app APK `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` SHA-256 `672b15363d2eeb415a15e8f2e7999b716f4263a96807e4bdddaeb7fe3ab88077`; instrumentation test APK `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` SHA-256 `ddf7284644361e0f7afdb10f704062230fd9f2e157e5348ebbb312d68b23e9d3` |
| Toolchain | Orca CLI `1.4.253`; Android Emulator `37.2.12.0`; adb `1.0.41` (`37.0.1`); Android SDK Platform `35`; Dart `3.13.5`; JDK `17.0.21` |
| Input | no corpus; synthetic UUIDv4 aggregate ids and random 32-byte DEKs only; no user data |

## 1. Scope

The owner authorized Pixel 7/API 35 profile provisioning with the installed
official SDK tools after the BIOS correction that made KVM usable. This record
answers one question: do the already alias-isolated T025 Keystore
instrumentation tests pass on an Orca-attached Pixel 7 API 35 runtime with
hardware acceleration, full boot, and a working package service, under an
exclusively observed assignment?

This run covers T025 per-document/per-template Keystore KEK creation, alias
lifecycle, DEK wrap/unwrap, provider-generated IVs, and the `SAVE-002`,
`SAVE-003`, and `SAVE-008` distinctions (FR-049/FR-050/FR-052). It supersedes
the runtime `NOT_RUN` outcome of
`2026-11-15-t025-pixel7-api35-tcg-not-run.md`; that boot-failure record and the
earlier non-accepting API 31 TCG observation remain frozen historical records
and are not used as acceptance.

This record does not claim physical-device acceptance, device performance,
full app end-to-end behavior, or independent review.

## 2. Revision and build

Base is `4952f7875905212818101a147566d16de206c0ed`. At run start the source
tree was clean at that commit. The only candidate changes are documentation:
this report, its index row, and the T025 task note. No Android source, test,
dependency, asset, or APK was rebuilt or changed.

The tested APKs are the unchanged T025 debug artifacts:

- app: `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk`, SHA-256
  `672b15363d2eeb415a15e8f2e7999b716f4263a96807e4bdddaeb7fe3ab88077`;
- instrumentation test: `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk`,
  SHA-256 `ddf7284644361e0f7afdb10f704062230fd9f2e157e5348ebbb312d68b23e9d3`.

The test source at this revision is
`apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/storage/KeystoreServiceInstrumentedTest.kt`
SHA-256 `3d85f02a002fbd296f6582c1989596eb06de32f54e3e25bc39a020aa8c280228`;
the service source is
`apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage/KeystoreService.kt`
SHA-256 `f8d2c4062183bf5725d2fad37a6b9a675261498fe87cd3bbfc037e8bd90e87d0`.
The installed app and test base APKs were pulled back from the guest and
matched these file hashes byte-for-byte.

## 3. Environment

```text
EMULATOR: Pixel 7 API 35; exclusive allocation label T025-PIXEL7-API35-KVM-20261115
          (operationally verified: one Orca session, one adb device, all other AVDs shutdown);
          system image system-images;android-35;google_apis;x86_64 revision 9;
          build fingerprint google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys;
          hardware profile pixel_7, 1080x2400, 420 dpi; RAM 3072 MB; 2 vCPU;
          APK apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk SHA-256 672b15363d2eeb415a15e8f2e7999b716f4263a96807e4bdddaeb7fe3ab88077;
          test APK apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk SHA-256 ddf7284644361e0f7afdb10f704062230fd9f2e157e5348ebbb312d68b23e9d3;
          build mode debug, no rebuild.
```

The AVD is `T025_Pixel7_API35_KVM_20261115`, created from the official
`system-images;android-35;google_apis;x86_64` revision 9 image with the
`pixel_7` hardware profile. The image archive is
`build/t025-work/api35/x86_64-35_r09.zip` (SHA-1
`0103e6dab21290c4b9d16550a3ce99476f884eef`, SHA-256
`c67b9ba0ff5bc0eb6d046871bfa228af14d4d47b02f0cdae94f048e511b7566e`).
The image was installed additively as a new package; no existing system image,
AVD, device, or data was changed, adopted, or wiped.

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `emulator -accel-check` (`.`) | `0` | `build/t025-work/logs/t025-api35-kvm-host-process.log` | `PASS` |
| 2 | `orca emulator devices --json` (`.`) | `0` | `build/t025-work/logs/t025-api35-orca-devices-before.json` | `PASS` |
| 3 | `orca emulator list --worktree all --json` (`.`) | `0` | `build/t025-work/logs/t025-api35-orca-sessions-before.json` | `PASS` |
| 4 | `adb devices -l` (`.`) | `0` | `build/t025-work/logs/t025-api35-adb-before.log` | `PASS` |
| 5 | `sdkmanager --list_installed` (`.`) | `0` | `build/t025-work/logs/t025-api35-sdkmanager-installed-before.log` | `PASS` |
| 6 | `extract official API 35 image and create isolated Pixel 7 AVD` (`.`) | `0` | `build/t025-work/logs/t025-api35-kvm-provision.log` | `PASS` |
| 7 | `orca emulator devices --json` (`.`) | `0` | `build/t025-work/logs/t025-api35-orca-devices-provisioned.json` | `PASS` |
| 8 | `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current --json` (`.`) | `0` | `build/t025-work/logs/t025-api35-orca-attach.json` | `PASS` |
| 9 | `adb -s emulator-5554 shell getprop sys.boot_completed` (`.`) | `0` | `build/t025-work/logs/t025-api35-boot-complete-watch.log` | `PASS` |
| 10 | `adb -s emulator-5554 shell service check package` (`.`) | `0` | `build/t025-work/logs/t025-api35-device-profile.log` | `PASS` |
| 11 | `adb -s emulator-5554 shell getprop ro.build.version.sdk` (`.`) | `0` | `build/t025-work/logs/t025-api35-device-profile.log` | `PASS` |
| 12 | `adb -s emulator-5554 install -r -t app APK and instrumentation test APK` (`.`) | `0` | `build/t025-work/logs/t025-api35-install.log` | `PASS` |
| 13 | `adb -s emulator-5554 shell am instrument -w -r -e class de.feldexa.app.storage.KeystoreServiceInstrumentedTest de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner` (`.`) | `0` | `build/t025-work/logs/t025-api35-instrumentation.log` | `PASS` |
| 14 | `orca emulator shutdown --device emulator-5554 --worktree current --json` (`.`) | `0` | `build/t025-work/logs/t025-api35-shutdown.log` | `PASS` |
| 15 | `orca emulator list --worktree all --json` (`.`) | `0` | `build/t025-work/logs/t025-api35-cleanup.log` | `PASS` |

Checks 1–8 establish host acceleration, the inventory, the new profile, and
the Orca assignment. Checks 9–11 establish full boot, package service, and API
identity. Checks 12–13 install the unchanged APKs and execute the suite.
Checks 14–15 establish release of the session and device.

## 5. Results

### 5.1 KVM and host process

`emulator -accel-check` exited `0` and reported `KVM (version 12) is installed
and usable.` The Orca-started emulator process ran
`qemu-system-x86_64-headless -avd T025_Pixel7_API35_KVM_20261115 -no-window`
and held an open KVM device node plus `kvm-vm` and two `kvm-vcpu` descriptors.
The guest CPU flags included `avx`, `f16c`, and `hypervisor`. This is direct
host/emulator evidence of hardware acceleration; it is not the software-TCG
failure mode recorded for the earlier boot attempt.

### 5.2 Full boot, package service, and profile

The guest reached a stable Android runtime:

- `sys.boot_completed=1`, `dev.bootcomplete=1`, `init.svc.bootanim=stopped`;
- `init.svc.zygote=running`, `init.svc.surfaceflinger=running`;
- `system_server` and `zygote64` were present in the process list;
- `service check package` returned `Service package: found`;
- `pm path android` resolved to the framework resource APK and `pm list
  packages` returned 241 packages;
- `ro.build.version.sdk=35`, `ro.build.version.release=15`,
  `ro.build.version.incremental=12960925`;
- `ro.product.cpu.abi=x86_64`, `ro.product.manufacturer=Google`;
- `ro.boot.qemu.avd_name=T025_Pixel7_API35_KVM_20261115`;
- `wm size` was `1080x2400` and `wm density` was `420`.

The Pixel 7 identity is the AVD hardware profile (`hw.device.name=pixel_7`,
1080x2400, 420 dpi, 3072 MB RAM, 2 vCPU). The actual system image build reports
`ro.product.model=sdk_gphone64_x86_64` and
`ro.product.device=emu64xa`; those are the real guest properties and are
recorded without relabeling them as a physical Pixel 7.

### 5.3 Orca assignment and exclusivity

Before provisioning, `orca emulator list --worktree all --json` returned no
sessions and `adb devices -l` listed no device. After provisioning,
`orca emulator devices --json` listed the new AVD as API 35 with state
`shutdown`, and all seven pre-existing AVDs remained `shutdown`.

`orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current --json`
returned `attached: true` for `emulator-5554`. Immediately before and during
the instrumentation run:

- `orca emulator list --worktree all --json` returned exactly one session,
  for the T025 worktree and `emulator-5554`;
- `adb devices -l` listed only `emulator-5554` in state `device`;
- every other AVD remained `shutdown`.

No foreign device, session, image, or AVD was adopted or wiped. Orca exposes
attachment/activation rather than a formal reservation lease; exclusivity was
therefore verified from the observed session and device state, not asserted
from an allocation API.

After the run, `orca emulator shutdown --device emulator-5554 --worktree
current --json` returned success. The immediate post-shutdown listing showed a
transient offline adb row; within seconds the emulator process exited, the
cleanup log recorded no Orca sessions, no adb devices, and all AVDs
`shutdown`. The new AVD was left in place, shutdown, and not wiped.

### 5.4 APK identity and installation

The app and test APKs were installed with `adb install -r -t` and both returned
`Success`. The installed packages were `de.feldexa.app` (versionName `1.0`,
versionCode `1`, minSdk `26`, targetSdk `36`) and `de.feldexa.app.test`
(versionCode `0`, minSdk `26`, targetSdk `36`). The instrumentation entry was
`de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner
(target=de.feldexa.app)`.

The installed base APKs were pulled back from the guest and hashed:

- app installed base APK SHA-256
  `672b15363d2eeb415a15e8f2e7999b716f4263a96807e4bdddaeb7fe3ab88077`,
  216211073 bytes;
- test installed base APK SHA-256
  `ddf7284644361e0f7afdb10f704062230fd9f2e157e5348ebbb312d68b23e9d3`,
  376065 bytes.

Both match the repository APK files exactly.

### 5.5 Instrumentation result

The suite ran on `emulator-5554` and finished with `OK (12 tests)`; the runner
log recorded `run finished: 12 tests, 0 failed, 0 ignored`. The 12 test methods
were:

`cleanupDoesNotDeleteForeignTestAlias`,
`eachAggregateUsesItsOwnDistinctAlias`,
`keyIsNonExportableAndDoesNotRequireUserAuthentication`,
`deleteRemovesOnlyTheTargetAlias`,
`storeStatusReportsPerAggregateAndGlobalCases`,
`oneLostAliasIsAggregateSave002AndSiblingsStillLoad`,
`sweepRemovesOnlyAliasesWithoutAnAggregateDirectory`,
`realKeystoreWrapUnwrapRoundTripAndNoMasterAlias`,
`deletingEveryAliasIsGlobalSave008`,
`createIsIdempotentAgainstTheRealKeystore`,
`providerGeneratesFreshTwelveByteIvForEveryWrap`,
`testAliasesAreIsolatedFromProductionAliases`.

The suite exercised the TEE path (`strongBoxSupported = false`), exact-only
test-alias cleanup, and the foreign-test-alias guard. It did not use a
`KeyStore.aliases()` sweep and did not create or delete production-prefix
aliases.

### 5.6 Scope boundary

This is `EMULATOR` evidence for the T025 Keystore service only. It does not
prove SAF import, OCR, export, app lifecycle, the complete user journey,
physical-device behavior, silicon-specific key strength, or any performance
target.

## 6. Performance

No performance claim.

## 7. Limitations

- This is emulator evidence, not physical-device acceptance.
- The AVD hardware profile is Pixel 7; the guest build reports
  `sdk_gphone64_x86_64` as its system-image model. No physical Pixel 7 model
  string is claimed.
- Orca provides attachment/activation, not a documented exclusive lease.
  Exclusivity was verified from one Orca session, one adb device, and all other
  AVDs being shutdown before and during the run; a concurrent actor could in
  principle have attempted another attach, and none occurred during this run.
- The suite covers Keystore behavior only; no full app, SAF, OCR, export,
  lifecycle, or device journey was run.
- No timing or performance result is claimed.
- No independent review or self-approval is claimed.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Orca worktree baseline | `build/t025-work/logs/t025-api35-worktree-current.json` | 3422 | `c65a78c473485da88220d2a9aed8ff27e501f1593aa47a8a85b84fd31c4e03be` |
| Orca devices before | `build/t025-work/logs/t025-api35-orca-devices-before.json` | 1604 | `2cd2f779b398b5581355092ea9447534f9a028bbf42ca4e145d5c6e5f770ef34` |
| Orca sessions before | `build/t025-work/logs/t025-api35-orca-sessions-before.json` | 177 | `0257bf4a4464d0ba2c2ebcaffb727783c519f991ebfd651819444ba99b7ad81a` |
| adb baseline | `build/t025-work/logs/t025-api35-adb-before.log` | 26 | `36f15c2fe32964a6fbe902e914a47739d4e6304b0d3e812bf08096ff0419b7ae` |
| SDK inventory before | `build/t025-work/logs/t025-api35-sdkmanager-installed-before.log` | 2397 | `400926e2716c2e87931062658fdc50db220e09fd1b07f4b7bdd9fd306bfcd13a` |
| image and AVD provisioning | `build/t025-work/logs/t025-api35-kvm-provision.log` | 2519 | `62475b9bf6e6ee90b0b6cf07d3f332099e43dba9299da4882879fe53eed4ed48` |
| Orca devices after provisioning | `build/t025-work/logs/t025-api35-orca-devices-provisioned.json` | 1839 | `ae09f2bc4ded4f330acfcad75098b7baf5ceb62566b928429648b54faf82abda` |
| Orca attach | `build/t025-work/logs/t025-api35-orca-attach.json` | 357 | `bcf7d0fc71ff14955d88863624ebcb4e1ccea41a0f0c2927f98b28b08b991fbd` |
| KVM host process evidence | `build/t025-work/logs/t025-api35-kvm-host-process.log` | 3123 | `6a4a127a14604790ab721a0cd71d19f4bca55ccba6d885a1b64f27f24ef919a1` |
| KVM guest CPU/property evidence | `build/t025-work/logs/t025-api35-kvm-guest-evidence.log` | 1775 | `957064aa677fdedb94b804965425ac666df199986747f0bb447eff93aa5de803` |
| boot completion watch | `build/t025-work/logs/t025-api35-boot-complete-watch.log` | 425 | `837d68ba7c6f75fa8f44250f79f1c5a3719cf3395abeb07d5926b05902217c2b` |
| device profile/boot/package | `build/t025-work/logs/t025-api35-device-profile.log` | 1165 | `14e4190a9d7193999d4c1d4e79c03bb4135c9ca1243cfcd4f987539d6d1da9d8` |
| APK installation and pull hashes | `build/t025-work/logs/t025-api35-install.log` | 1453 | `cbc34190e297c3643a524dadaea449aefad8948f5bf054b9fbcbd0b6c576b49b` |
| instrumentation run | `build/t025-work/logs/t025-api35-instrumentation.log` | 45410 | `55e0dcc3c8511d08be7f4946b584fa11d17320a7322c4578b813739993117009` |
| Orca shutdown | `build/t025-work/logs/t025-api35-shutdown.log` | 3727 | `472d4fdc3b3eb17e468861ef3ec3321ad98bab51c60fa29f27bb6fc8d0964dd3` |
| final cleanup verification | `build/t025-work/logs/t025-api35-cleanup.log` | 2550 | `c71d6c7095e05e99bcf8e1e82866d32c95c42c014a1cb26420aefa9c317da42b` |
| debug app APK | `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 216211073 | `672b15363d2eeb415a15e8f2e7999b716f4263a96807e4bdddaeb7fe3ab88077` |
| instrumentation test APK | `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 376065 | `ddf7284644361e0f7afdb10f704062230fd9f2e157e5348ebbb312d68b23e9d3` |
| official API 35 image archive | `build/t025-work/api35/x86_64-35_r09.zip` | 1738815903 | `c67b9ba0ff5bc0eb6d046871bfa228af14d4d47b02f0cdae94f048e511b7566e` |

Git-ignored logs and the image archive are local support artifacts, not
candidate contents. This report is intentionally not listed in its own
artifacts table.

## 9. Reproducibility

1. Start from base commit `4952f7875905212818101a147566d16de206c0ed` with the
   unchanged T025 app/test APKs named in §2.
2. Verify the official image archive:
   `sha1sum build/t025-work/api35/x86_64-35_r09.zip` must be
   `0103e6dab21290c4b9d16550a3ce99476f884eef`; its SHA-256 is
   `c67b9ba0ff5bc0eb6d046871bfa228af14d4d47b02f0cdae94f048e511b7566e`.
3. Extract `x86_64-35_r09.zip` additively into a new
   `system-images/android-35/google_apis/x86_64` package and generate its
   `package.xml` from the installed API 31 template. Do not change or delete
   any existing system image, AVD, or device data.
4. Create the unique AVD
   `T025_Pixel7_API35_KVM_20261115` with
   `avdmanager create avd -n T025_Pixel7_API35_KVM_20261115 -k system-images;android-35;google_apis;x86_64 -d pixel_7`,
   then set `hw.ramSize=3072`, `hw.cpu.ncore=2`, and
   `disk.dataPartition.size=6G` in its `config.ini`.
5. Confirm `orca emulator devices --json` lists the new AVD as API 35
   `shutdown`, `orca emulator list --worktree all --json` has no sessions, and
   `adb devices -l` has no device.
6. Start and assign it with
   `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current --json`.
   Wait until `adb -s emulator-5554 shell getprop sys.boot_completed` is `1`,
   `adb -s emulator-5554 shell service check package` reports
   `Service package: found`, and `adb -s emulator-5554 shell getprop
   ro.build.version.sdk` is `35`.
7. Confirm hardware acceleration: `emulator -accel-check` exits `0`, the
   Orca-started qemu process is present with the `-avd` argument, and its open
   file descriptors include the KVM device node, `kvm-vm`, and KVM vCPU
   entries.
8. Install the exact APKs with
   `adb -s emulator-5554 install -r -t apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk`
   and the test APK path from §2. Pull both installed base APKs and confirm the
   hashes in §5.4.
9. Run
   `adb -s emulator-5554 shell am instrument -w -r -e class de.feldexa.app.storage.KeystoreServiceInstrumentedTest de.feldexa.app.test/androidx.test.runner.AndroidJUnitRunner`;
   expect `OK (12 tests)` and `0 failed, 0 ignored`.
10. Finish with
    `orca emulator shutdown --device emulator-5554 --worktree current --json`;
    confirm no Orca sessions, no adb devices, and all AVDs `shutdown`. Leave the
    new AVD in place; do not wipe it.
11. Run `python3 tools/evaluation/check_evidence_docs.py` and
    `dart tools/evaluation/validate_report.dart
    specs/001-scanned-form-workflow/reports/2026-11-15-emulator-t025-pixel7-api35-kvm-keystore.md`.

## 10. External attestation

The `worker_done` transport record is the external attestation: it names the
candidate commit SHA, this report's byte size and SHA-256, the changed files,
and the T025 task identity. No attestation Git ref was created, and nothing was
pushed, merged, or self-reviewed.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
