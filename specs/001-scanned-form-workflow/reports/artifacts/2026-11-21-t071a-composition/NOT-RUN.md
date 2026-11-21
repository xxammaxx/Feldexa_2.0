# T071A emulator preflight — NOT_RUN

Date: 2026-11-21 (local)
Base commit: `127f978f44911ef7a8c53b7c696bf5218915ae6c`
Worktree: `/home/xxammaxx/Schreibtisch/Feldexa_2.0/t071a-composition`
Branch: `xxammaxx/t071a`

## Result

`EMULATOR` real journey: **NOT_RUN**.

The Pixel 7 API 35 AVD `T025_Pixel7_API35_KVM_20261115` is booted on
`emulator-5554`, but the Orca CLI exposes no emulator session attached to this
worktree. The coordinator explicitly instructed this worker not to rebind or
reuse another worktree's allocation. The T071A driver therefore stops at its
exclusive-allocation preflight before installing, clearing app data, or running
the integration test.

```text
$ T071A_RUN_DIR=/tmp/opencode/t071a-preflight-run tools/android/t071a_drive_composition.sh
T071A DRIVER: run directory /tmp/opencode/t071a-preflight-run
no Orca emulator session is attached to this worktree for emulator-5554
T071A EMULATOR NOT_RUN: emulator-5554 is booted but no exclusively allocated Orca session is attached to this worktree; do not reuse another worktree's allocation
exit=2
```

## Read-only preflight evidence

- `device-identity-preflight.txt`: serial, AVD name, API, fingerprint, boot flag.
- `orca-emulator-devices.json`: Orca device inventory (AVD found, booted).
- `orca-emulator-sessions.json`: Orca worktree session list (empty `sessions`).
- `git-identity-base.txt`: base/HEAD/tree at evidence creation.

## What was not executed

- Android debug APK build (the attempted build was interrupted; no APK hash is
  claimed).
- Installation, app-data reset, fixture staging on device, real import/analysis,
  suggestion confirmation, page selection, value entry, save, start-list
  reload, reopen, and all five screenshots.
- Logcat markers, runtime logcat, APK SHA-256, on-device fixture SHA-256, and
  runtime AVD/serial evidence.

No host test, preflight capture, or artifact above is presented as `EMULATOR`
evidence.
