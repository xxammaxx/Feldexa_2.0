# 2026-11-15 NONE — T025 Pixel 7 API 35 TCG boot NOT_RUN

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `FAIL` |
| Task / issue | `T025` / `#25` |
| Date / timezone | `2026-11-15 14:04 Europe/Berlin` |
| Revision | base commit `1468869a49689a719e8306df8959c89f62a6933b`; tree `dirty` `specs/001-scanned-form-workflow/tasks.md` SHA-256 `5a372a69e784b46bbd4fbba30385969e66f772cc570a584a7fc0da8c3fea7708`; `specs/001-scanned-form-workflow/reports/README.md` SHA-256 `7c4619128953ba66b4cbed2113589d7211534081284578616bde1f752eaccf45`; candidate SHA in external attestation |
| External attestation | worker_done transport attestation (candidate SHA, report bytes and hash); not part of the candidate commit |
| Build identity | no rebuild; unchanged T025 debug app APK SHA-256 `672b15363d2eeb415a15e8f2e7999b716f4263a96807e4bdddaeb7fe3ab88077`; instrumentation test APK SHA-256 `ddf7284644361e0f7afdb10f704062230fd9f2e157e5348ebbb312d68b23e9d3` |
| Toolchain | Orca CLI 1.4.253; Dart 3.13.5; Android emulator 37.2.12.0; official `system-images;android-35;google_apis;x86_64` revision 9; host QEMU TCG without KVM |
| Input | no corpus; synthetic UUIDv4 aggregate ids and random 32-byte DEKs only; no user data |

## 1. Scope

The owner authorized a temporary system image/AVD for the required Pixel 7/API
35 check. This attempt provisioned the official API 35 google_apis x86_64
image and a Pixel 7 API 35 AVD entirely in an isolated temporary directory, without changing global
SDK/AVD configuration or any existing image/device/data. The emulator reached
adb, but the Android runtime never completed boot: `system_server` and the
package manager did not start, so the required profile cannot be considered
stably started and the 12 instrumentation tests are **NOT_RUN**.

This is a `NONE` gate record, not Android evidence. No `EMULATOR` acceptance is
claimed.

## 2. Revision and build

Base is `1468869a49689a719e8306df8959c89f62a6933b`. Only the task/index notes
and this report are dirty. The app/test APK hashes are unchanged from the
tested T025 identity.

## 3. Environment

```text
NONE: host Linux x86_64, 4 logical CPUs; temporary SDK and Pixel 7 API 35 AVD
      under /tmp; Android emulator 37.2.12.0 with software TCG (-no-accel).
      No KVM; no global SDK/AVD changes.
```

The official image archive was
`x86_64-35_r09.zip` from the Google API system-image repository, SHA-1
`0103e6dab21290c4b9d16550a3ce99476f884eef`, downloaded with the already
accepted `android-sdk-license`; no new license was accepted.

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `orca-ide emulator list --worktree current --json` (`.`) | `0` | `build/t025-work/logs/t025-pixel7-api35-tcg-sessions.json` | `PASS` |
| 2 | `orca-ide emulator devices --json` (`.`) | `0` | `build/t025-work/logs/t025-pixel7-api35-tcg-devices.json` | `PASS` |
| 3 | `curl official x86_64-35_r09.zip; sha1sum -c` (`.`) | `0` | `build/t025-work/logs/t025-pixel7-api35-run.log` | `PASS` |
| 4 | `unzip image into temporary SDK; create Pixel 7 API 35 AVD config` (`.`) | `0` | `build/t025-work/logs/t025-pixel7-api35-run.log` | `PASS` |
| 5 | `guest boot probe: sys.boot_completed / service check package` (`.`) | `1` | `build/t025-work/logs/t025-pixel7-api35-boot-diagnosis.log` | `FAIL` |
| 6 | `Orca attach and 12 alias-isolated instrumentation tests` (`.`) | `-` | `none` | `ABSENT` |

Checks 1–4 show that the official image and temporary AVD were available and
provisioned. Check 5 failed: after more than 20 minutes the guest still had no
completed boot. Check 6 was not attempted because there was no stable boot to
assign or test.

## 5. Results

### 5.1 Temporary profile provisioning

- Downloaded the official API 35 google_apis x86_64 r09 image (1,738,815,903
  bytes; SHA-1 verified).
- Extracted it directly into the temporary SDK and generated the local package
  metadata there.
- Created the temporary AVD `T025_Pixel7_API35` with
  `hw.device.name=pixel_7`, `image.sysdir.1=system-images/android-35/google_apis/x86_64/`,
  `tag.id=google_apis`, 3072 MB RAM, x86_64.
- Symlinked the installed emulator/platform-tools/platforms and copied the
  accepted licenses into the temporary SDK. No existing image, AVD, device,
  data, or global SDK/AVD configuration was changed or wiped.

### 5.2 Boot failure

The guest reached adb (`emulator-5586`, `state=device`) and reported API 35,
but:

- `sys.boot_completed` remained empty;
- `init.svc.bootanim` was `stopped`;
- `service check package` returned `Service package: not found`;
- `ps -A` showed only `init` and kernel threads, no `system_server`/zygote;
- logcat repeatedly showed `Could not find 'aidl/activity'` and
  servicemanager waiting for the activity service;
- the emulator log reported
  `TCG doesn't support requested feature: CPUID.01H:ECX.avx [bit 28]` and
  `...f16c [bit 29]`, plus
  `detected a hanging thread 'QEMU2 CPU0/CPU1 thread'`.

The guest therefore never reached a stable Android runtime. Orca attach and
the 12 tests were not attempted, because attaching an unbooted guest would not
produce valid profile evidence. No foreign device/session was touched.

### 5.3 Exclusivity and acceptance status

No Orca session was created and no device was adopted. The profile-specific
exclusivity question was not reached because the guest failed to boot. This is
`FAIL` for stable boot and `NOT_RUN` for the Android gate; it is not a profile
pass, and no `EMULATOR`, API 35, `DEVICE`, or performance acceptance is
claimed.

### 5.4 Options

1. Run on a host with KVM/AVX/F16C support, or an Orca-provisioned Pixel 7 API
   35, so the system image can boot stably.
2. Retry with an Orca-managed device/image that already satisfies the profile
   and exclusivity requirements.
3. Keep the gate `NOT_RUN` until such a host/allocation is available.

No convention, image, AVD, or emulator setting was changed.

## 6. Performance

No performance claim. The guest did not complete boot, so there is no valid
timing result.

## 7. Limitations

- This `NONE` report is a gate/boot record, not Android evidence.
- The temporary API 35 image booted the kernel/adb but not the Android
  framework; `system_server` never started.
- No Orca attach, no instrumentation run, and no APK installation was
  attempted.
- The cause is host virtualisation capability (TCG lacks AVX/F16C and reports
  QEMU CPU hangs), not a T025 code result.
- No API 35, `DEVICE`, or performance acceptance is claimed.
- No self-review is claimed.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| provisioning/boot run log | `build/t025-work/logs/t025-pixel7-api35-run.log` | 4086 | `7c53bbdfd6345f4fe2a3a08bd53fc765adc3d91c80085ded892ead6739a66d40` |
| emulator log | `build/t025-work/logs/t025-pixel7-api35-emulator.log` | 7200 | `d17626af8883f1a41e6aebd51b27d24db6e2e9ba38fc9baef6ae81704492bd51` |
| boot diagnosis | `build/t025-work/logs/t025-pixel7-api35-boot-diagnosis.log` | 9816 | `a0446be22515ad4d35b9578d41fa15e2434c8cb7158f918b0e1e842861f23ff0` |
| official API 35 image archive | `build/t025-work/api35/x86_64-35_r09.zip` | 1738815903 | `c67b9ba0ff5bc0eb6d046871bfa228af14d4d47b02f0cdae94f048e511b7566e` |
| sessions (empty) | `build/t025-work/logs/t025-pixel7-api35-tcg-sessions.json` | 177 | `32c502409bc5d38a08407c39c789d463f49b3270c3861175bf161577a1294d65` |
| devices (no temp AVD registered) | `build/t025-work/logs/t025-pixel7-api35-tcg-devices.json` | 1604 | `01948ff223e7005e6572e3cd9d700dc8b0da0b6d20436e2d64fc019fd26e308c` |
| debug app APK (unchanged) | `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 216211073 | `672b15363d2eeb415a15e8f2e7999b716f4263a96807e4bdddaeb7fe3ab88077` |
| instrumentation test APK (unchanged) | `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 376065 | `ddf7284644361e0f7afdb10f704062230fd9f2e157e5348ebbb312d68b23e9d3` |

Git-ignored logs and the temporary image archive are local support artifacts,
not candidate contents. This report is intentionally not listed in its own
artifacts table.

## 9. Reproducibility

1. Start from `1468869a49689a719e8306df8959c89f62a6933b`.
2. Download the official API 35 google_apis x86_64 r09 image and verify its
   SHA-1 `0103e6dab21290c4b9d16550a3ce99476f884eef`.
3. Extract it into a temporary SDK in an isolated temporary directory, create a Pixel 7 API 35 AVD
   with the temporary `ANDROID_AVD_HOME`, and start it with
   `-no-window -no-audio -no-boot-anim -no-snapshot -read-only -no-accel`.
4. Probe `sys.boot_completed` and `service check package`; on this TCG host
   they never become ready and the emulator logs AVX/F16C and QEMU hangs.
5. Do **not** attach or run tests; use a KVM/AVX-capable host or an
   Orca-provisioned Pixel 7 API 35 for a valid run.
6. Do not classify this attempt as `EMULATOR`/API 35/`DEVICE` evidence.

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
