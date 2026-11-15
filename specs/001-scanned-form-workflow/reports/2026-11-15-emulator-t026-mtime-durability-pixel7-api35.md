# 2026-11-15 `EMULATOR` — T026 mtime durability on Pixel 7 API 35

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` |
| Result | `PASS` |
| Task / issue | `T026` / `#26` |
| Date / timezone | `2026-11-15 Europe/Berlin` |
| Revision | base `d78114fdb703c405fe4692fe287e71095b50fc59`; correction commit `53ffe78e0f9c7ed1939fc1ec0846c3e391927588`; this report, its host companion, the index rows, the task note, and the mtime bundle are the later documentation changes; final candidate SHA in the external attestation |
| External attestation | `worker_done` transport record (candidate SHA, changed files, this report's bytes/SHA-256); not part of the candidate commit |
| Supersedes for the changed code | `2026-11-15-emulator-t026-review-corrections-pixel7-api35.md` remains frozen evidence for `84f2276`/`3197ca3` |
| Allocation label | `T026-MTIME-PIXEL7-API35-20261115` (non-sensitive; no raw Orca session or terminal id) |
| Build identity | `versionName 1.0` (`versionCode 1`), `debug`; app APK `93b92c585e3a5b401c5e0dbd14d322fcfdc171216b1f7760f799672d8b0e0ac5` (216,359,664 bytes); test APK `82711d4215d6fa24d754f5b26490effec216bf6db8155ff105f2d7768890d8a2` (399,814 bytes, unchanged) |
| Toolchain | JDK `17.0.20.1`; Gradle `9.3.1`; AGP `9.1.0`; Kotlin `2.4.0`; Flutter `3.47.7`; Dart `3.13.5`; Android Emulator `37.2.12.0`; adb `1.0.41` |
| Input | synthetic UUIDv4 ids, random 32-byte DEKs, synthetic JSON/PDF bytes; no corpus or user data |

## 1. Scope

This rerun covers the T026 instrumentation suite after the mtime durability
correction `53ffe78`: the real `AndroidKeyStore` container/commit/delete/sweep
tests, the parallel-save serialization test, head-safe pruning, equal-timestamp
recovery, and the unchanged T025 regression. It does not claim `DEVICE`,
performance, StrongBox, or independent host KVM.

## 2. Environment and allocation

```text
EMULATOR: Pixel 7 profile, API 35 (Android 15), AVD T025_Pixel7_API35_KVM_20261115
          allocation label T026-MTIME-PIXEL7-API35-20261115
          serial EMULATOR37X2X12X0
          fingerprint google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys
          abi x86_64, hardware ranchu, ro.kernel.qemu=1, sys.boot_completed=1
          package service: found
          guest CPU flags include hypervisor, avx, f16c
          app APK SHA-256 93b92c585e3a5b401c5e0dbd14d322fcfdc171216b1f7760f799672d8b0e0ac5
          test APK SHA-256 82711d4215d6fa24d754f5b26490effec216bf6db8155ff105f2d7768890d8a2
```

Before the run, `orca emulator list --worktree all --json` returned
`sessions: []` and `adb devices -l` listed no device. The worktree attached the
AVD through Orca (`attached: true`); exactly one adb device was present during
the run. After the run, Orca shut the device down, the session list returned
`sessions: []`, and adb showed no device. The redacted allocation record is in
the mtime bundle.

`emulator -accel-check` is `UNAVAILABLE` in the worker sandbox (no `/dev/kvm`);
this record makes no independent host-KVM claim. The guest reports
`hypervisor`/`avx`/`f16c` and uses the T025-provisioned Pixel 7 API 35 AVD.

## 3. Checks

| # | Command (repo root) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `orca emulator list --worktree all --json` (before) | `0` | `build/t026-work/logs/mtime-orca-sessions-before.json` | `PASS` (`sessions: []`) |
| 2 | `adb devices -l` (before) | `0` | `build/t026-work/logs/mtime-adb-before.log` | `PASS` (no device) |
| 3 | `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current --json` | `0` | `build/t026-work/logs/mtime-orca-attach.json` | `PASS` (`attached: true`) |
| 4 | `getprop sys.boot_completed` | `0` | `build/t026-work/logs/mtime-device-profile.log` | `PASS` (`1`) |
| 5 | `service check package` | `0` | `build/t026-work/logs/mtime-device-profile.log` | `PASS` (`found`) |
| 6 | API/fingerprint/AVD/ABI/CPU flags | `0` | `build/t026-work/logs/mtime-device-profile.log` | `PASS` (API 35, Pixel 7 image, `x86_64`, hypervisor/avx/f16c) |
| 7 | install app and test APKs | `0` | `build/t026-work/logs/mtime-install-app.log`, `...-install-test.log` | `PASS` |
| 8 | pull installed APKs and compare SHA-256 | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t026-mtime-2026-11-15/apk-sha256.txt` | `PASS` (both match) |
| 9 | `am instrument` T026 class | `0` | `build/t026-work/logs/mtime-instrumentation-t026.log` | `PASS` (`OK (13 tests)`, 8.127 s) |
| 10 | `am instrument` T025+T026 classes | `0` | `build/t026-work/logs/mtime-instrumentation-both.log` | `PASS` (`OK (25 tests)`, 3.956 s) |
| 11 | logcat FATAL scan | `0` | `build/t026-work/logs/mtime-logcat-t026.log`, `...both.log` | `PASS` (0 FATAL EXCEPTION) |
| 12 | `orca emulator shutdown --device emulator-5554 --worktree current --json` | `0` | `build/t026-work/logs/mtime-orca-shutdown.json` | `PASS` |
| 13 | `orca emulator list --worktree all --json` (after) | `0` | `build/t026-work/logs/mtime-orca-sessions-after.json` | `PASS` (`sessions: []`) |
| 14 | `adb devices -l` (after) | `0` | `build/t026-work/logs/mtime-adb-after.log` | `PASS` (no device) |
| 15 | host `emulator -accel-check` | — | — | `UNAVAILABLE` (no `/dev/kvm`; not claimed) |

## 4. Results

- T026: `OK (13 tests)` in 8.127 s. The list is unchanged from the review
  correction run: container round-trip, boundary sizes, tamper, key-loss
  `SAVE-002`/`SAVE-008`, deletion, startup sweep, head fallback, fsync fault,
  no plaintext residue, parallel-save serialization, head-safe pruning, and
  equal-timestamp fail-closed recovery.
- T025+T026: `OK (25 tests)` in 3.956 s.
- Post-run logcat contains zero `FATAL EXCEPTION` lines.
- Installed app/test APK hashes match the local build byte-for-byte (the app
  APK changed to `93b92c...` for the mtime fix; the test APK remains
  `82711d...`).

This rerun proves the mtime-fix build still passes the real-Keystore suite; it
does not prove physical power-loss durability, which remains a syscall-order
argument and a host-level ordering test.

## 5. Artifacts

| Path | Bytes | SHA-256 |
| --- | ---: | --- |
| `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 216,359,664 | `93b92c585e3a5b401c5e0dbd14d322fcfdc171216b1f7760f799672d8b0e0ac5` |
| `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 399,814 | `82711d4215d6fa24d754f5b26490effec216bf6db8155ff105f2d7768890d8a2` |
| `build/t026-work/guest-mtime/app-debug-installed.apk` | 216,359,664 | `93b92c585e3a5b401c5e0dbd14d322fcfdc171216b1f7760f799672d8b0e0ac5` |
| `build/t026-work/guest-mtime/app-debug-androidTest-installed.apk` | 399,814 | `82711d4215d6fa24d754f5b26490effec216bf6db8155ff105f2d7768890d8a2` |
| `build/t026-work/logs/mtime-instrumentation-t026.log` | 8,777 | `84b259bf13ff0a8a0c82bafbfb65aef72158ebffb8416d696260bf0989ef195b` |
| `build/t026-work/logs/mtime-instrumentation-both.log` | 16,943 | `0e4f75f3d3344530709fd16dc56e58df006e878f3ed5ff3cbfd977f2da0c762f` |
| `build/t026-work/logs/mtime-device-profile.log` | 260 | `5930b874c0df18754af6616413ed97d573ef71a975183d919460628a0ac691dd` |
| `specs/001-scanned-form-workflow/reports/artifacts/t026-mtime-2026-11-15/manifest.json` | 8,531 | `9780389e248d1fb44e886c77204bafab52170c4c53c9c1a948754299e05c15c9` |

The committed mtime bundle contains redacted copies of the instrumentation and
device logs, the seven JUnit XMLs, the allocation record, and the manifest.
Raw logcat is not published; its size, SHA-256, and zero FATAL count are bound
in the manifest.

## 6. Limitations

- No `DEVICE` acceptance, performance, StrongBox, or silicon key-strength
  claim. Emulator timings are not the SC-004 device claim.
- Host KVM is not independently verified; the guest hypervisor/AVX/F16C flags
  and the T025-provisioned AVD are the available evidence.
- Physical power-loss durability is not simulated; the mtime fix is proven at
  the syscall-order level and by an injected-failure test.
- Retention remains with the owner; no format decision was made.
- No push, merge, or self-review.

## 7. Reproducibility

1. Build both APKs from `53ffe78e0f9c7ed1939fc1ec0846c3e391927588` in debug mode.
2. Confirm no other Orca session and no adb device.
3. `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current --json`;
   wait for `sys.boot_completed=1` and `service check package` = `found`.
4. Install both APKs, pull the installed base APKs, compare SHA-256 with §5.
5. Run the T026 class; expected `OK (13 tests)`. Run T025+T026; expected
   `OK (25 tests)`. Scan logcat; expected no `FATAL EXCEPTION`.
6. `orca emulator shutdown --device emulator-5554 --worktree current --json`;
   confirm `sessions: []` and no adb device.
7. Run the mtime bundle `verify.sh`; expected `EVIDENCE VERIFY: OK`.

## 8. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
