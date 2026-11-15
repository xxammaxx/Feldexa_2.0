# 2026-11-15 NONE — T025 Pixel 7 API 35 EMULATOR NOT_RUN

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `PARTIAL` |
| Task / issue | `T025` / `#25` |
| Date / timezone | `2026-11-15 13:32 Europe/Berlin` |
| Revision | base commit `4cdff666d235b197f69fe3409d608389ae211beb`; tree `dirty` `specs/001-scanned-form-workflow/tasks.md` SHA-256 `461c6ebdfc75212d47ff6e8ff06449bbfcb26dcaa3aed677f99b6c3a32ee1363`; `specs/001-scanned-form-workflow/reports/README.md` SHA-256 `7133beb9f4d3b9d69ab54519bd68a1e552c4907c9d9bf5a2669a37b9f010a7c5`; candidate SHA in external attestation |
| External attestation | worker_done transport attestation (candidate SHA, report bytes and hash); not part of the candidate commit |
| Build identity | no rebuild; unchanged T025 debug app APK SHA-256 `672b15363d2eeb415a15e8f2e7999b716f4263a96807e4bdddaeb7fe3ab88077`; instrumentation test APK SHA-256 `ddf7284644361e0f7afdb10f704062230fd9f2e157e5348ebbb312d68b23e9d3` |
| Toolchain | Orca CLI 1.4.253; Dart 3.13.5; Android SDK Platform 35, emulator 37.2.12.0, cmdline-tools with `sdkmanager`/`avdmanager`; adb reports no connected devices |
| Input | no corpus; synthetic UUIDv4 aggregate ids and random 32-byte DEKs only; no user data |

## 1. Scope

This record answers whether a Pixel 7/API 35 profile can be safely and
exclusively assigned to this T025 worktree and stably started, using the
installed official Orca and Android SDK documentation/tools. No Android
runtime was started, no existing AVD or image was modified, and no foreign
session was adopted. Because the required profile cannot be guaranteed, the
instrumentation suite is **NOT_RUN** and no `EMULATOR` evidence is claimed.

This is a `NONE` gate/provenance record, not an Android evidence class.

## 2. Revision and build

Base is `4cdff666d235b197f69fe3409d608389ae211beb`. The tree contains only
the task/index notes and this report. The app/test APK hashes are unchanged
from the tested T025 identity; no Android source was changed.

## 3. Environment

```text
NONE: host Linux x86_64; read-only Orca/SDK inventory.
      No Android device was booted, attached, or instrumented.
```

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `orca-ide emulator list --worktree current --json` (`.`) | `0` | `build/t025-work/logs/t025-pixel7-emulator-list.json` | `PASS` |
| 2 | `orca-ide emulator devices --json` (`.`) | `0` | `build/t025-work/logs/t025-pixel7-emulator-devices.json` | `PASS` |
| 3 | `sdkmanager --list_installed` (`.`) | `0` | `build/t025-work/logs/t025-pixel7-sdkmanager-installed.log` | `PASS` |
| 4 | `avdmanager list avd` (`.`) | `0` | `build/t025-work/logs/t025-pixel7-avdmanager-avd.log` | `PASS` |
| 5 | `exclusive Orca worktree allocation for a Pixel 7 API 35 AVD` (`.`) | `-` | `none` | `UNAVAILABLE` |
| 6 | `12 alias-isolated instrumentation tests` (`.`) | `-` | `none` | `ABSENT` |

Checks 1–4 are read-only inventories that ran successfully; their contents
record the findings: no attached session, no API 35 AVD, no installed API 35
system image, and no Pixel 7/API 35 AVD entry. Checks 5–6 are
unavailable/absent, so the report result is `PARTIAL`, not a profile pass.

## 5. Results

### 5.1 Orca allocation behavior

`orca-ide emulator --help` exposes `list`, `devices`, `attach`, and device
actions, but no `allocate`, `reserve`, or exclusive-lease command.
`orca-ide emulator attach --help` only offers `--worktree`, `--focus`, and a
device selector. The version-matched Android emulator guide says `attach`
boots an AVD and makes it active for the worktree; it does not state that the
AVD is reserved against another worktree. A global `devices` listing is
shared across worktrees.

Therefore Orca can make an existing device active for this worktree, but it
does not provide the requested **exclusive** assignment guarantee. Starting
an existing AVD could also collide with another worktree's active session.

### 5.2 Android image/AVD inventory

- `sdkmanager --list_installed` includes `platforms;android-35` but **no**
  `system-images;android-35` package.
- `avdmanager list avd` lists only API 31 and API 36 AVDs
  (`Feldexa_API31`, `Feldexa_API36`, `Feldexa_ATD31`, `Feldexa_E2E_ATD31`,
  `Feldexa_Phone31`, `SpecKitWerkbank_QA`, `SpecKitWerkbank_QA_ATD`).
- The `pixel_7` hardware profile exists in `avdmanager list device`, but no
  API 35 system image is installed, so a Pixel 7/API 35 AVD cannot be created
  from installed assets.
- `orca-ide emulator devices` consequently has no API 35 row.

### 5.3 Why the suite is NOT_RUN

Running any installed API 31/36 AVD would not satisfy the project `EMULATOR`
profile and would risk touching a device another worktree may use. Installing
an API 35 system image and creating a new AVD would add external SDK assets,
and would still not establish Orca's exclusive worktree ownership. The task
requires safe exclusivity; neither condition is met. Therefore the 12
alias-isolated tests were not run, no device was attached, and no profile was
started or mislabeled.

This is `NOT_RUN` with the concrete causes above; it is not `PASS` and not a
profile claim.

### 5.4 Options (owner decision required)

1. Install an official API 35 system image and create a dedicated Pixel 7 AVD,
   then obtain an explicit Orca/owner allocation that prevents other
   worktrees from attaching it.
2. Use an Orca-provisioned Pixel 7 API 35 device if the Orca host exposes
   one; none was listed.
3. Authorize a documented shared-AVD protocol (with device-state isolation
   and no data loss), which would require a convention decision.
4. Keep the gate `NOT_RUN` until one of the above is authorized.

No option was implemented and no convention was changed.

## 6. Performance

No performance claim. The suite did not run, so no timing is available.

## 7. Limitations

- This `NONE` report is a gate/provenance record, not Android evidence.
- No Android device was booted, attached, or instrumented.
- The hardware profile `pixel_7` alone is not an API 35 system image.
- Orca `attach` is an activation operation, not an exclusive reservation.
- No API 35, `DEVICE`, or performance acceptance is claimed.
- No self-review is claimed.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Orca sessions JSON | `build/t025-work/logs/t025-pixel7-emulator-list.json` | 177 | `54303c9c1f044e34d0e6cb1ec4a46e26db0707a2773e9bb346ed452909a7ac4d` |
| Orca devices JSON | `build/t025-work/logs/t025-pixel7-emulator-devices.json` | 1604 | `dec9f423cb44021f5e7f4bd21bf0621713ba37dd44eea6f5417928354181ea2a` |
| SDK installed packages | `build/t025-work/logs/t025-pixel7-sdkmanager-installed.log` | 2397 | `400926e2716c2e87931062658fdc50db220e09fd1b07f4b7bdd9fd306bfcd13a` |
| AVD list | `build/t025-work/logs/t025-pixel7-avdmanager-avd.log` | 1624 | `5e1076c4ef3d92b21e252396e8bbb840c797fa46e0b5d1e73c8b2c81e0649cde` |
| device profiles | `build/t025-work/logs/t025-pixel7-avdmanager-devices.log` | 5265 | `982e902d7431b7d6279e89062100ad7fcb9b52d5cbef3d7656378e8d033ba518` |
| Orca emulator help | `build/t025-work/logs/t025-pixel7-orca-emulator-help.log` | 1305 | `9941f6657a25375f43a905839db68d03aea87b0dc77a6d2a0670285ef6d8f950` |
| Orca attach help | `build/t025-work/logs/t025-pixel7-orca-attach-help.log` | 763 | `f9824bce70803e81a60eccc669bce297dbc46f053b4f75f86febb4f34fa0d536` |
| debug app APK (unchanged) | `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 216211073 | `672b15363d2eeb415a15e8f2e7999b716f4263a96807e4bdddaeb7fe3ab88077` |
| instrumentation test APK (unchanged) | `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 376065 | `ddf7284644361e0f7afdb10f704062230fd9f2e157e5348ebbb312d68b23e9d3` |

Git-ignored logs are local support artifacts and are not candidate contents.
This report is intentionally not listed in its own artifacts table.

## 9. Reproducibility

1. Start from `4cdff666d235b197f69fe3409d608389ae211beb`.
2. Run check 1; expected `sessions: []` for the exact worktree id.
3. Run check 2; expected only API 31/36 AVD rows and no API 35 row.
4. Run check 3; expected `platforms;android-35` but no
   `system-images;android-35` entry.
5. Run check 4; expected no Pixel 7/API 35 AVD.
6. Read the version-matched Orca Android guide and `attach --help`; confirm
   `attach` activates/boots an AVD but provides no exclusive reservation.
7. Do **not** start or attach an existing AVD and do not install/wipe assets.
   The correct outcome remains `NOT_RUN` until an API 35 image and an
   owner-approved exclusive allocation exist.

## 10. External attestation

The `worker_done` transport record is the external attestation: it names the
exact candidate/report commit, this report's bytes and SHA-256, and the T025
task and dispatch identity. No separate attestation ref was created or pushed.
The candidate commit contains this report; it therefore cannot contain its own
SHA-256.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
