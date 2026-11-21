# T071A composition artifacts

This directory is the evidence bundle for the T071A report
`../../2026-11-21-emulator-t071a-composition.md`.

## Included

| File | Purpose |
| --- | --- |
| `NOT-RUN.md` | Exact exclusive-allocation blocker and the unexecuted emulator steps |
| `device-identity-preflight.txt` | Read-only booted device properties (not a run) |
| `orca-emulator-devices.json` | Orca device inventory at preflight |
| `orca-emulator-sessions.json` | Orca worktree session list; empty |
| `git-identity-base.txt` | Base/HEAD/tree during evidence collection |
| `host-gates.txt` | Analyze and full host-suite results copied from the gate runs |

## Not included

No screenshots, logcat, APK hash, or on-device fixture hash exists because the
exclusive emulator journey was not executed. Those checks are `NOT_RUN` and are
never reconstructed from host tests.
