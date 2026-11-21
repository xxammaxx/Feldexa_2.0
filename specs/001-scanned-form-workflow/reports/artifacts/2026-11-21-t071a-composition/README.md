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
| `host-gates.txt` | Original-delivery analyze and full host-suite results |
| `correction-2-host-gates.txt` | Correction-2 analyze, format, focused guard, and full suite results with exit codes |
| `correction-2-fixture-damage.txt` | Content-free T061 damaged-page-2 derivation: source/damaged bytes and SHA-256 |

## Not included

No screenshots, logcat, APK hash, or on-device fixture hash exists yet for the
correction-2 journey because the coordinator's exclusive emulator run is
pending. Those checks are `NOT_RUN` and are never reconstructed from host
tests.
