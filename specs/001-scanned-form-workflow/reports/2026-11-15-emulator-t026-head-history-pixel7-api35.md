# 2026-11-15 `EMULATOR` — T026 head history on Pixel 7 API 35

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` |
| Result | `PASS` |
| Task / issue | `T026` / `#26` |
| Date / timezone | `2026-11-15 Europe/Berlin` |
| Revision | base `d78114fdb703c405fe4692fe287e71095b50fc59`; implementation commit `c30cb669c1a23f4eaea13ad9da42f775b4dd4935`; this report, its host companion, the index rows, the task note, and the head-history bundle are the later documentation changes; final candidate SHA in the external attestation |
| External attestation | `worker_done` transport record (candidate SHA, changed files, this report's bytes/SHA-256); not part of the candidate commit |
| Supersedes for the changed code | `2026-11-15-emulator-t026-mtime-durability-pixel7-api35.md` remains frozen evidence for `53ffe78` |
| Allocation label | `T026-HEADHISTORY-PIXEL7-API35-20261115` (non-sensitive; no raw Orca session or terminal id) |
| Build identity | `versionName 1.0` (`versionCode 1`), `debug`; app APK `b35ba8609ba126ea70d914073f7183de7f6899231ba8dd8a03d596762cdc2535` (216,365,872 bytes); test APK `b9102dd9cc89b9f1a07c706a8850eec0a855de53a304c7177af7045099f1058f` (401,996 bytes) |
| Toolchain | JDK `17.0.20.1`; Gradle `9.3.1`; AGP `9.1.0`; Kotlin `2.4.0`; Flutter `3.47.7`; Dart `3.13.5`; Android Emulator `37.2.12.0`; adb `1.0.41` |
| Input | synthetic UUIDv4 ids, random 32-byte DEKs, synthetic JSON/PDF bytes; no corpus or user data |

## 1. Scope

This run executes the T026 instrumentation suite after the owner-decided head
history and automatic retention (`c30cb66`) with the real `AndroidKeyStore`:
the original container/commit/delete/sweep tests, the parallel-save lock, the
mtime-ordering fsync behavior, head-safe pruning, equal-timestamp recovery, and
three new head-history/legacy/unknown tests.

## 2. Environment and allocation

```text
EMULATOR: Pixel 7 profile, API 35 (Android 15), AVD T025_Pixel7_API35_KVM_20261115
          allocation label T026-HEADHISTORY-PIXEL7-API35-20261115
          serial EMULATOR37X2X12X0
          fingerprint google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys
          abi x86_64, hardware ranchu, ro.kernel.qemu=1, sys.boot_completed=1
          package service: found
          guest CPU flags include hypervisor, avx, f16c
          app APK SHA-256 b35ba8609ba126ea70d914073f7183de7f6899231ba8dd8a03d596762cdc2535
          test APK SHA-256 b9102dd9cc89b9f1a07c706a8850eec0a855de53a304c7177af7045099f1058f
```

An Orca session for this worktree was already present and the device was
booted; the worktree attached it (`attached: true`) and exactly one adb device
was used. This is the established Pixel 7 / API 35 AVD from T025; no second
device was touched. After the run Orca shut the device down, the session list
returned `sessions: []`, and adb showed no device.

`emulator -accel-check` remains `UNAVAILABLE` in the worker sandbox (no
`/dev/kvm`); no independent host-KVM claim is made. The guest reports
`hypervisor`/`avx`/`f16c` and `ro.kernel.qemu=1`.

## 3. Checks

| # | Command (repo root) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `orca emulator list --worktree all --json` (before) | `0` | `build/t026-work/logs/headhistory-orca-sessions-before.json` | `PASS` (one existing worktree session) |
| 2 | `adb devices -l` (before) | `0` | `build/t026-work/logs/headhistory-adb-before.log` | `PASS` (one device) |
| 3 | `orca emulator attach T025_Pixel7_API35_KVM_20261115 --worktree current --json` | `0` | `build/t026-work/logs/headhistory-orca-attach.json` | `PASS` (`attached: true`) |
| 4 | `getprop sys.boot_completed` | `0` | `build/t026-work/logs/headhistory-device-profile.log` | `PASS` (`1`) |
| 5 | `service check package` | `0` | `build/t026-work/logs/headhistory-device-profile.log` | `PASS` (`found`) |
| 6 | API/fingerprint/AVD/ABI/CPU flags | `0` | `build/t026-work/logs/headhistory-device-profile.log` | `PASS` (API 35, Pixel 7 image, `x86_64`, hypervisor/avx/f16c) |
| 7 | install app and test APKs | `0` | `build/t026-work/logs/headhistory-install-app.log`, `...-install-test.log` | `PASS` |
| 8 | pull installed APKs and compare SHA-256 | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t026-head-history-2026-11-15/apk-sha256.txt` | `PASS` (both match) |
| 9 | `am instrument` T026 class | `0` | `build/t026-work/logs/headhistory-instrumentation-t026.log` | `PASS` (`OK (16 tests)`, 4.102 s) |
| 10 | `am instrument` T025+T026 classes | `0` | `build/t026-work/logs/headhistory-instrumentation-both.log` | `PASS` (`OK (28 tests)`, 4.091 s) |
| 11 | logcat FATAL scan | `0` | `build/t026-work/logs/headhistory-logcat-t026.log`, `...both.log` | `PASS` (0 FATAL EXCEPTION) |
| 12 | `orca emulator shutdown --device emulator-5554 --worktree current --json` | `0` | `build/t026-work/logs/headhistory-orca-shutdown.json` | `PASS` |
| 13 | `orca emulator list --worktree all --json` (after) | `0` | `build/t026-work/logs/headhistory-orca-sessions-after.json` | `PASS` (`sessions: []`) |
| 14 | `adb devices -l` (after) | `0` | `build/t026-work/logs/headhistory-adb-after.log` | `PASS` (no device) |
| 15 | host `emulator -accel-check` | — | — | `UNAVAILABLE` (no `/dev/kvm`; not claimed) |

## 4. Results

- T026: `OK (16 tests)` in 4.102 s, including the three new device tests
  `headHistoryAndPolicyOnDevice`, `legacyHeadWithoutHistoryKeepsFilesOnDevice`,
  and `unknownHistoryEntryIsRetainedOnDevice`.
- T025+T026: `OK (28 tests)` in 4.091 s.
- The installed app/test APKs match the local build hashes byte-for-byte.
- Post-run logcat contains zero `FATAL EXCEPTION` lines.

This is runtime evidence for the policy/history behavior on the real
`AndroidKeyStore`; physical power-loss durability remains a syscall-order and
host-test argument, not an emulator claim.

## 5. Artifacts

| Path | Bytes | SHA-256 |
| --- | ---: | --- |
| `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 216,365,872 | `b35ba8609ba126ea70d914073f7183de7f6899231ba8dd8a03d596762cdc2535` |
| `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 401,996 | `b9102dd9cc89b9f1a07c706a8850eec0a855de53a304c7177af7045099f1058f` |
| `build/t026-work/guest-headhistory/app-debug-installed.apk` | 216,365,872 | `b35ba8609ba126ea70d914073f7183de7f6899231ba8dd8a03d596762cdc2535` |
| `build/t026-work/guest-headhistory/app-debug-androidTest-installed.apk` | 401,996 | `b9102dd9cc89b9f1a07c706a8850eec0a855de53a304c7177af7045099f1058f` |
| `build/t026-work/logs/headhistory-instrumentation-t026.log` | 10,758 | `266e5a76f35f2c50eea081b28d6fab0be5cf0f52dd36cbdf349040dd3f00bd7a` |
| `build/t026-work/logs/headhistory-instrumentation-both.log` | 18,924 | `f2dda0ca40d2778f1cebfad4d558cdca1b6ee00b8c308ca04652ce56094f411f` |
| `build/t026-work/logs/headhistory-device-profile.log` | 260 | `5930b874c0df18754af6616413ed97d573ef71a975183d919460628a0ac691dd` |
| `specs/001-scanned-form-workflow/reports/artifacts/t026-head-history-2026-11-15/manifest.json` | 8,562 | `54b9756c9bb249c0630fb16c1b7f75f5fe5122581f0464142357a788a1fe83ac` |

The committed head-history bundle contains redacted copies of the
instrumentation/device logs, seven JUnit XMLs, the allocation record, and the
policy summary. Raw logcat is not published; its size, SHA-256, and zero FATAL
count are bound in the manifest.

## 6. Limitations

- No `DEVICE` acceptance, performance, StrongBox, or silicon key-strength
  claim. Emulator timings are not the SC-004 device claim.
- Host KVM is not independently verified; the guest hypervisor/AVX/F16C flags
  and the T025-provisioned AVD are the available evidence.
- Physical power-loss durability is not simulated; crash reconciliation is
  tested through the durable head/prune ordering and injected failures.
- Legacy/unknown-kind revisions are retained conservatively and can exceed the
  five-known-revision target after an upgrade.
- No push, merge, or self-review.

## 7. Reproducibility

1. Build both APKs from `c30cb669c1a23f4eaea13ad9da42f775b4dd4935` in debug mode.
2. Confirm the Orca worktree session and one adb device.
3. Attach the AVD through Orca; wait for `sys.boot_completed=1` and
   `service check package` = `found`.
4. Install both APKs, pull the installed base APKs, compare SHA-256 with §5.
5. Run the T026 class; expected `OK (16 tests)`. Run T025+T026; expected
   `OK (28 tests)`. Scan logcat; expected no `FATAL EXCEPTION`.
6. `orca emulator shutdown --device emulator-5554 --worktree current --json`;
   confirm `sessions: []` and no adb device.
7. Run the bundle `verify.sh`; expected `EVIDENCE VERIFY: OK`.

## 8. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
