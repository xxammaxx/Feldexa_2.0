# 2026-11-15 `EMULATOR` — T026 prune retry on Pixel 7 API 35

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` |
| Result | `PASS` |
| Task / issue | `T026` / `#26` |
| Date / timezone | `2026-11-15 Europe/Berlin` |
| Revision | base `d78114fdb703c405fe4692fe287e71095b50fc59`; correction commit `57ce38bf0d1f9487926c8b7d775397604f7f125d`; this report, its host companion, the index rows, the task note, and the committed bundle are the later documentation changes; final candidate SHA in the external attestation |
| External attestation | `worker_done` transport record (candidate SHA, changed files, this report's bytes/SHA-256); not part of the candidate commit |
| Supersedes for the changed code | `2026-11-15-emulator-t026-prune-durability-pixel7-api35.md` remains frozen evidence for `0c75c57` |
| Allocation label | `T026-PRUNERETRY-PIXEL7-API35-20261115` (non-sensitive; no raw Orca session or terminal id) |
| Build identity | `versionName 1.0` (`versionCode 1`), `debug`; app APK `518a0a37fe50e956482d0d313b16c953843f6519b18eb22700ede9c920d51860` (216,366,594 bytes); test APK `00f73e17e6f734a8260baa139f3e4880e056b8979038041d44d5723b5e6e3452` (403,990 bytes) |
| Toolchain | JDK `17.0.20.1`; Gradle `9.3.1`; AGP `9.1.0`; Kotlin `2.4.0`; Flutter `3.47.7`; Dart `3.13.5`; Android Emulator `37.2.12.0`; adb `1.0.41` |
| Input | synthetic UUIDv4 ids, random 32-byte DEKs, synthetic JSON/PDF bytes; no corpus or user data |

## 1. Scope

This run executes the T026 instrumentation suite after the no-resurrection
retry correction `57ce38b` with the real `AndroidKeyStore`, including the new
device regression `pruneFsyncFailureWithoutResurrectionRetriesOnDevice`. It
also covers the unchanged container/commit/delete/sweep, parallel-save,
ordering-fsync, head-history, pruning, and equal-timestamp recovery tests.

## 2. Environment and allocation

```text
EMULATOR: Pixel 7 profile, API 35 (Android 15), AVD T025_Pixel7_API35_KVM_20261115
          allocation label T026-PRUNERETRY-PIXEL7-API35-20261115
          serial EMULATOR37X2X12X0
          fingerprint google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys
          abi x86_64, hardware ranchu, ro.kernel.qemu=1, sys.boot_completed=1
          package service: found
          guest CPU flags include hypervisor, avx, f16c
          app APK SHA-256 518a0a37fe50e956482d0d313b16c953843f6519b18eb22700ede9c920d51860
          test APK SHA-256 00f73e17e6f734a8260baa139f3e4880e056b8979038041d44d5723b5e6e3452
```

Before the run, `orca emulator list --worktree all --json` returned
`sessions: []` and adb listed no device. The worktree attached the AVD through
Orca (`attached: true`); exactly one adb device was used. After the run Orca
shut it down, the session list returned `sessions: []`, and adb showed no
device.

`emulator -accel-check` remains `UNAVAILABLE` in the worker sandbox (no
`/dev/kvm`); no independent host-KVM claim is made. The guest reports
`hypervisor`/`avx`/`f16c` and `ro.kernel.qemu=1`.

## 3. Checks

| # | Command (repo root) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `orca emulator list --worktree all --json` (before) | `0` | `build/t026-work/logs/prunefsync2-orca-sessions-before.json` | `PASS` (`sessions: []`) |
| 2 | `adb devices -l` (before) | `0` | `build/t026-work/logs/prunefsync2-adb-before.log` | `PASS` (no device) |
| 3 | `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current --json` | `0` | `build/t026-work/logs/prunefsync2-orca-attach.json` | `PASS` (`attached: true`) |
| 4 | `getprop sys.boot_completed` | `0` | `build/t026-work/logs/prunefsync2-device-profile.log` | `PASS` (`1`) |
| 5 | `service check package` | `0` | `build/t026-work/logs/prunefsync2-device-profile.log` | `PASS` (`found`) |
| 6 | API/fingerprint/AVD/ABI/CPU flags | `0` | `build/t026-work/logs/prunefsync2-device-profile.log` | `PASS` (API 35, Pixel 7 image, `x86_64`, hypervisor/avx/f16c) |
| 7 | install app and test APKs | `0` | `build/t026-work/logs/prunefsync2-install-app.log`, `...-install-test.log` | `PASS` |
| 8 | pull installed APKs and compare SHA-256 | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t026-prune-retry-2026-11-15/apk-sha256.txt` | `PASS` (both match) |
| 9 | `am instrument` T026 class | `0` | `build/t026-work/logs/prunefsync2-instrumentation-t026.log` | `PASS` (`OK (18 tests)`, 8.865 s) |
| 10 | `am instrument` T025+T026 classes | `0` | `build/t026-work/logs/prunefsync2-instrumentation-both.log` | `PASS` (`OK (30 tests)`, 4.777 s) |
| 11 | logcat FATAL scan | `0` | `build/t026-work/logs/prunefsync2-logcat-t026.log`, `...both.log` | `PASS` (0 FATAL EXCEPTION) |
| 12 | `orca emulator shutdown --device emulator-5554 --worktree current --json` | `0` | `build/t026-work/logs/prunefsync2-orca-shutdown.json` | `PASS` |
| 13 | `orca emulator list --worktree all --json` (after) | `0` | `build/t026-work/logs/prunefsync2-orca-sessions-after.json` | `PASS` (`sessions: []`) |
| 14 | `adb devices -l` (after) | `0` | `build/t026-work/logs/prunefsync2-adb-after.log` | `PASS` (no device) |
| 15 | host `emulator -accel-check` | — | — | `UNAVAILABLE` (no `/dev/kvm`; not claimed) |

## 4. Results

- T026: `OK (18 tests)` in 8.865 s. This includes
  `pruneFsyncFailureWithoutResurrectionRetriesOnDevice`, which injects a
  `PRUNE_FSYNC` failure, leaves the file missing (no resurrection), verifies
  the entry stays in history after a second failed retry, and confirms only a
  successful directory fsync trims it.
- T025+T026: `OK (30 tests)` in 4.777 s.
- Installed app/test APKs match the local build hashes byte-for-byte.
- Post-run logcat contains zero `FATAL EXCEPTION` lines.

This is runtime evidence that the retry path remains safe on the real
`AndroidKeyStore`; physical power-loss durability remains an injected-fault
claim, not an emulator power-loss claim.

## 5. Artifacts

| Path | Bytes | SHA-256 |
| --- | ---: | --- |
| `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 216,366,594 | `518a0a37fe50e956482d0d313b16c953843f6519b18eb22700ede9c920d51860` |
| `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 403,990 | `00f73e17e6f734a8260baa139f3e4880e056b8979038041d44d5723b5e6e3452` |
| `build/t026-work/guest-prunefsync2/app-debug-installed.apk` | 216,366,594 | `518a0a37fe50e956482d0d313b16c953843f6519b18eb22700ede9c920d51860` |
| `build/t026-work/guest-prunefsync2/app-debug-androidTest-installed.apk` | 403,990 | `00f73e17e6f734a8260baa139f3e4880e056b8979038041d44d5723b5e6e3452` |
| `build/t026-work/logs/prunefsync2-instrumentation-t026.log` | 12,130 | `25ca6f5e559fe4d19519b4b1aae9cc10a2d22f479b42bc8be907c5639e5c30db` |
| `build/t026-work/logs/prunefsync2-instrumentation-both.log` | 20,296 | `45c4fb76860a9d889f5f5171b4d1577829254dc9d39072ed257ee3f39acf51de` |
| `build/t026-work/logs/prunefsync2-device-profile.log` | 260 | `5930b874c0df18754af6616413ed97d573ef71a975183d919460628a0ac691dd` |
| `specs/001-scanned-form-workflow/reports/artifacts/t026-prune-retry-2026-11-15/manifest.json` | 9,013 | `6432a24060a20d4553a3bb65eed7ad2b45e838f389b762b860e8fd1589eec11e` |

The committed prune-retry bundle contains redacted copies of the
instrumentation/device logs, eight JUnit XMLs, the allocation record, and the
retry summary. Raw logcat is not published; its size, SHA-256, and zero FATAL
count are bound in the manifest.

## 6. Limitations

- No `DEVICE` acceptance, performance, StrongBox, or silicon key-strength
  claim. Emulator timings are not the SC-004 device claim.
- Physical power-loss durability is not simulated; the no-resurrection state
  is simulated with injected repeated prune-fsync failures.
- Host KVM is not independently verified; the guest hypervisor/AVX/F16C flags
  and the T025-provisioned AVD are the available evidence.
- Legacy/unknown-kind revisions remain conservatively retained and can exceed
  the five-known-revision target after an upgrade.
- No push, merge, or self-review.

## 7. Reproducibility

1. Build both APKs from `57ce38bf0d1f9487926c8b7d775397604f7f125d` in debug mode.
2. Confirm no other Orca session and no adb device.
3. Attach the AVD through Orca; wait for `sys.boot_completed=1` and
   `service check package` = `found`.
4. Install both APKs, pull the installed base APKs, compare SHA-256 with §5.
5. Run the T026 class; expected `OK (18 tests)`. Run T025+T026; expected
   `OK (30 tests)`. Scan logcat; expected no `FATAL EXCEPTION`.
6. `orca emulator shutdown --device emulator-5554 --worktree current --json`;
   confirm `sessions: []` and no adb device.
7. Run the bundle `verify.sh`; expected `EVIDENCE VERIFY: OK`.

## 8. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
