# T071A composition artifacts

This directory is the evidence bundle for the T071A report
`../../2026-11-21-emulator-t071a-composition.md`.

## Included

| File | Purpose |
| --- | --- |
| `NOT-RUN.md` | Historical correction-1 exclusive-allocation blocker and unexecuted steps |
| `device-identity-preflight.txt` | Historical read-only booted device properties (not a run) |
| `orca-emulator-devices.json` | Historical preflight Orca device inventory |
| `orca-emulator-sessions.json` | Orca worktree session list at evidence collection |
| `git-identity-base.txt` | Historical base/HEAD/tree during first evidence collection |
| `host-gates.txt` | Original-delivery analyze and full host-suite results |
| `correction-2-host-gates.txt` | Correction-2 analyze, format, focused guard, and full suite results |
| `correction-2-fixture-damage.txt` | Content-free T061 damaged-page-2 derivation: source/damaged bytes and SHA-256 |
| `correction-3-host-gates.txt` | Correction-3 analyze, format, focused/full suites, diff check, and driver result |
| `git-identity.txt` | Correction-3 run HEAD, branch, tree status, and Flutter version |
| `apk-sha256.txt` | Built debug APK path and SHA-256 |
| `device-identity.txt` | Correction-3 emulator serial, AVD, fingerprint, API, ABI, size/density |
| `fixture-sha256.txt` | Host/staged fixture and expected damaged-derivation SHA-256s |
| `host-flutter-pub-get.log` | Driver `flutter pub get` output |
| `integration-android-t071a.log` | Integration test log with the T071A marker sequence and final `All tests passed!` |
| `logcat-flutter.log` | Filtered Flutter logcat from the run |
| `logcat-t071a-markers.log` | Lifecycle lines from the run; T071A marker sequence is authoritative in the integration log |
| `marker-sequence.txt` | Driver screenshot/marker handshake sequence and final PASS line |
| `privacy-log-check.txt` | Source-level log privacy check result |
| `privacy-source-check.txt` | Source-level network-API privacy check result |
| `run-status.txt` | `result=PASS` and `flutter_test_exit=0` |
| `screenshots/overlay-selection.png` | Editor overlay/selection phase after value-sheet close |
| `screenshots/value-sheet.png` | Type-appropriate value sheet with entered value |
| `screenshots/saved-status.png` | Editor after verified save and saved read-back |
| `screenshots/document-list.png` | Start list after leaving the editor |
| `screenshots/reopened-value.png` | Reopened document with the saved value |

`overlay-selection.png` and `saved-status.png` are pixel-identical
(SHA-256 `f3e37e1b...`) because both driver handshakes captured the same
settled editor frame before and after the value save. They are distinct
phases with distinct markers/acknowledgements, not a copied file.

## Not included

No APK binary, raw full logcat, key material, or separate document-content
extract is stored. The screenshots necessarily show the synthetic fixture; no
text is transcribed. The fixture is the committed synthetic
`apps/feldexa_app/assets/fixtures/sf-001.pdf`; the damaged variant is derived
in-test and never committed or pushed.
