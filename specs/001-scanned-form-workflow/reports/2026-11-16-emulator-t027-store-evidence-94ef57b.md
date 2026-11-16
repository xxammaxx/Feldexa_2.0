# 2026-11-16 EMULATOR — T027 Review-B correction Android store evidence

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` |
| Result | `PASS` |
| Task / issue | `T027` / `#27` |
| Date / timezone | `2026-11-16 17:23 Europe/Berlin` |
| Revision | base commit `15aab0c55c7e77df0d4c4fe199e89c6661ea3db2`; candidate code commit `94ef57b059c71fad01b0f3d46743996325a08dc7` (tree `0444e300e6a4bb0d7b7e21705cc65d635c98c5d0`). The only working-tree change is the pre-existing, deliberately uncommitted `apps/feldexa_app/android/gradlew.bat` phantom (SHA-256 `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62`), which is not part of the candidate. The later docs-only commit carries this report and the artifact bundle; its final branch SHA is named in the active `worker_done` attestation |
| External attestation | the active `worker_done` transport record for the dispatched T027 evidence worker (role label; raw task/dispatch identifiers withheld per `reports/README.md` §4.2); it records the candidate code SHA/tree, base, final branch SHA, checks/counts, report bytes/hash, and limitations. No attestation ref was created |
| Build identity | version `0.1.0` (versionCode `1`); mode `debug`; standalone `build/t027-review3/apks/app-debug.apk` 240765509 bytes SHA-256 `37074ddc12cc0ee1349f3ffdcefc651743728a5c1434e6993d574ff9f1d1e110`; AndroidTest `build/t027-review3/apks/app-debug-androidTest.apk` 126352 bytes SHA-256 `2b236f82700f67692b1ad2f3c4bfccda39a135c819f17e5845340b80ff7ff4fb`; Dart integration harness `build/t027-review3/apks/app-debug-integration.apk` 217937973 bytes SHA-256 `8ab95d2e6d915f47d7350082eb0cbad7cd5f2e0f7b7c3cd886714eeb1bbad419` |
| Toolchain | Flutter `3.47.7` (framework `abaf9c5237`), Dart `3.13.5`, Gradle `9.3.1`, Temurin JDK `17.0.20.1`, Android SDK platforms 34/35/36/37.0, build-tools `35.0.0`/`36.0.0`, adb `1.0.41` (`37.0.1`) |
| Input | no corpus; synthetic UUIDv4 aggregate ids, synthetic PDF/source bytes, and synthetic PNG fixtures: native alpha colour types 4/6; tRNS-backed RGB/gray/indexed; opaque RGB; malformed tRNS; 1024/1025 px; non-PNG/truncated/CRC-corrupt variants. No user document, URI, or unrelated device data |

This report proves Android-runtime behavior only for the exclusively allocated
Pixel 7 API 35 AVD below. It does not claim `DEVICE`, physical-silicon key
strength, release-heap, performance, full UI/T031/product behavior, or
physical-device acceptance. The code correction was committed **before** this
build and run; the report itself is in a later docs-only commit.

## 1. Scope

Review A worker passed `db8ce0f`; Review B worker failed it only because
`SignaturePng` accepted opaque RGB/indexed colour types without an alpha
channel or valid `tRNS` while `contracts/storage-format.md` §2.4 line 129
requires signature alpha. This run exercises the accepted correction on the
real Android runtime:

- `EncryptedStore.writeSignature` accepts a native gray+alpha PNG and a
  RGB+tRNS PNG generated independently of the production parser, stores the
  exact bytes, and reads them back unchanged.
- A real opaque RGB PNG (no alpha, no `tRNS`) is rejected with `SAVE-007` while
  the prior signature bytes, head, revision files, and signature-directory
  bytes stay unchanged.
- The Dart→MethodChannel→native/Keystore journey accepts native gray+alpha and
  valid tRNS-backed RGB, rejects opaque RGB and a malformed five-byte `tRNS`
  payload with `AndroidInvalidDataException` (`SAVE-007`), keeps the prior
  signature/head, and still rejects a duplicate asset with `PLT-002`.
- The 1024 px accepted / 1025 px rejected boundary remains unchanged.

Host support is in
[2026-11-16-t027-host-evidence-94ef57b.md](./2026-11-16-t027-host-evidence-94ef57b.md)
(`NONE`; not aggregated with this runtime result).

## 2. Revision and build

The correction is the 9-file commit `94ef57b` described in the host report.
The APKs below were built from the clean tree after `flutter clean`,
`flutter pub get --offline --enforce-lockfile`, and removal of the Android
project cache. The source/input manifest is identical before and after the run
(SHA-256 `dd96bdf1d56fb30a81cf3efc46c6a0f0f19a44d8d1be22fe80bc2125e50853c5`).
The standalone APK was installed and compared in-guest before tests; the Dart
integration harness replaced it during the journey and its copied bytes were
re-installed and hash-checked afterwards; the standalone/test APKs were
restored and compared again at the end.

## 3. Environment

```text
EMULATOR: Pixel 7 API 35, exclusive Orca allocation
          T025_Pixel7_API35_KVM_20261115
          serial emulator-5554
          system image google/sdk_gphone64_x86_64/emu64xa (API 35, userdebug)
          fingerprint google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys
          guest model sdk_gphone64_x86_64
          ro.build.version.sdk=35, ro.build.version.release=15
          ro.boot.qemu.avd_name=T025_Pixel7_API35_KVM_20261115
          ro.kernel.qemu=1, ro.boot.qemu=1
          sys.boot_completed=1
          2 vCPU; RAM 3072 MB (MemTotal 3048512 kB)
          APK build/t027-review3/apks/app-debug.apk
          APK SHA-256 37074ddc12cc0ee1349f3ffdcefc651743728a5c1434e6993d574ff9f1d1e110
          build mode debug
```

Allocation checks before attach (recorded in `logs/emulator-allocation.log`):

- `orca emulator list --worktree all --json` returned exactly one session,
  bound to this worktree, with `deviceUdid: emulator-5554`;
- `orca emulator devices` listed `T025_Pixel7_API35_KVM_20261115` as `booted`
  and every other listed AVD as `shutdown`;
- `adb devices -l` showed exactly one `emulator-5554` device;
- the guest reported the named AVD, API 35, and `sys.boot_completed=1`.
  No physical phone or unrelated AVD was used.

**KVM limitation.** The AVD is the named, KVM-provisioned T025 profile and prior
T025/T026 `EMULATOR` runs on this same AVD recorded KVM device-node evidence.
This DSH sandbox does not expose the host KVM device node or the host emulator
process, so a new host acceleration probe was `UNAVAILABLE`; no
software-fallback boot was observed. The KVM statement is therefore limited to
the named AVD/session and prior evidence, not a fresh host-probe result.

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `orca emulator list --worktree all --json`; `orca emulator devices`; `adb devices -l`; guest props (repo root) | `0` | `logs/emulator-allocation.log` | `PASS` |
| 2 | `adb -s emulator-5554 install -r` both APKs; `pm path` + in-guest `sha256sum` (repo root) | `0` | `logs/installed-hashes-before-tests.log` | `PASS` |
| 3 | `./gradlew :app:connectedDebugAndroidTest --offline --no-daemon --console=plain -Pkotlin.compiler.execution.strategy=in-process -Pandroid.testInstrumentationRunnerArguments.class=de.feldexa.app.storage.EncryptedStoreInstrumentedTest,de.feldexa.app.storage.KeystoreServiceInstrumentedTest` (`apps/feldexa_app/android`, `ANDROID_SERIAL=emulator-5554`) | `0` | `logs/gradle-connected-storage.log` | `PASS` |
| 4 | `./gradlew :app:connectedDebugAndroidTest --offline --no-daemon --console=plain -Pkotlin.compiler.execution.strategy=in-process -Pandroid.testInstrumentationRunnerArguments.class=de.feldexa.app.FeldexaPluginInstrumentedTest` (same) | `0` | `logs/gradle-connected-channel.log` | `PASS` |
| 5 | `env ORG_GRADLE_PROJECT_kotlin.compiler.execution.strategy=in-process flutter test integration_test/t027_store_test.dart -d emulator-5554 --no-pub` (`apps/feldexa_app`) | `0` | `logs/integration-store.log` | `PASS` |
| 6 | install the captured integration-harness APK; `pm path` + in-guest `sha256sum` (repo root) | `0` | `logs/installed-hashes-after-integration.log` | `PASS` |
| 7 | restore both APKs; `pm path` + in-guest `sha256sum` (repo root) | `0` | `logs/installed-hashes-final.log` | `PASS` |
| 8 | `pm clear de.feldexa.app`; `am start -W -n de.feldexa.app/.MainActivity`; `run-as` `ls`/`find files`; force-stop (repo root) | `0` | `logs/canonical-root-runtime.log` | `PASS` |
| 9 | `adb logcat -d -v threadtime` filtered to the app/runtime/keystore tags (repo root) | `0` | `logs/logcat-filtered-after-final.txt` (raw bytes bound by `raw-evidence-sha256.txt`) | `PASS` |

The storage run passed 34/34 tests, 0 failures, 0 errors; the channel run
passed 20/20; the Dart integration journey passed 1/1. `flutter test` removes
the app/test packages after the journey, so the copied harness APK was
installed again to bind its in-guest hash; the copied bytes
(`8ab95d2e…`) match the installed `base.apk` exactly.

## 5. Results

| Area | Observed result |
| --- | --- |
| Storage instrumentation | `signatureAlphaRepresentationsAreAcceptedOnDevice` accepts and round-trips an Android-decodable native gray+alpha PNG and a real `tRNS`-backed RGB PNG; `invalidSignaturePngIsRejectedAndPreservesPriorStateOnDevice` now also rejects a real opaque RGB PNG with `SAVE-007` while kept bytes/head/revisions/signature-directory bytes stay unchanged |
| Channel instrumentation | `realStoreSignaturePngValidationThroughChannel` accepts native alpha and `tRNS`-backed images, rejects opaque RGB (plus non-PNG/truncated/corrupt) with terminal `SAVE-007` and unchanged prior state, and still accepts 1024×1024 / rejects 1025×1024 |
| Dart/native journey | Native gray+alpha and valid `tRNS` RGB are written and read byte-for-byte; opaque RGB and a malformed 5-byte `tRNS` throw `AndroidInvalidDataException` (`SAVE-007`) without changing the kept signature/head; the duplicate asset still throws `SecurityException`/`PLT-002`; 1024×1 is accepted and 1025×1 is rejected |
| Production root | After `pm clear`, the standalone app launched from the candidate APK and created exactly `files/feldexa/{docs,templates,tmp,diagnostics}`; no `files/feldexa_store` directory was created (`files/profileInstalled` is an ART profile artifact, not store data) |
| APK identity | Standalone, AndroidTest, and harness APKs match their recorded hashes and the in-guest `pm path` + `sha256sum` values in every phase |
| Runtime class | This is `EMULATOR` evidence only; no `DEVICE`, release, performance, or product acceptance is claimed |

## 6. Performance

No performance claim.

## 7. Limitations

- No `DEVICE`, release-build, performance, StrongBox, physical-silicon, or
  acceptance claim. KVM acceleration is not freshly probed from this sandbox;
  see §3.
- Full UI, T031 startup composition, product behavior, OCR/import quality, and
  export-artifact behavior remain unproven by T027.
- Android template channel operations remain fail-closed (`PLT-001`) because
  their payload is still unspecified; native import/OCR/export/delivery engines
  are future tasks. `OcrRequest` still lacks the source-page size, so production
  composition must supply `OcrPageSizeResolver` (accepted seam limitation).
- This is author evidence. The same independent Review A and Review B roles
  must revalidate the final new branch SHA; no self-review, push, PR, or remote
  merge was performed.

## 8. Artifacts

Artifact paths are relative to
`specs/001-scanned-form-workflow/reports/artifacts/t027-review-b-94ef57b/`.
Committed logs are path-redacted copies; JUnit XML is unmodified. Raw APKs and
raw logs remain local, git-ignored build outputs; `apk-sha256.txt`,
`manifest.json`, and `raw-evidence-sha256.txt` bind their exact bytes.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| standalone debug APK | 240765509 | `37074ddc12cc0ee1349f3ffdcefc651743728a5c1434e6993d574ff9f1d1e110` |
| AndroidTest APK | 126352 | `2b236f82700f67692b1ad2f3c4bfccda39a135c819f17e5845340b80ff7ff4fb` |
| integration-harness APK | 217937973 | `8ab95d2e6d915f47d7350082eb0cbad7cd5f2e0f7b7c3cd886714eeb1bbad419` |
| storage JUnit XML | 6016 | `52109e333a4087f1cac0d491cacbbc37e6957bb9b5e5aa35c5634c567ac19018` |
| channel JUnit XML | 3572 | `345ad8a7a33ab60aa697a535a34f2a75aea9f5e8ca9f4b7e1848e42deb33c156` |
| storage run log | 23412 | `7b60ecfd23af27fe0a23666d2e40295da437fadf90456827204c95baa8e51a17` |
| channel run log | 23499 | `00ac3db13233f4a1c13a8349c8e83ab312829d01c23f8f82e7022c49e03f44b5` |
| integration log | 1225 | `c09b75ad3ea9ee098a50ec3d4deb52eb4207a247dfb86e4cf5be49f8377d7a2f` |
| before-test hashes | 305 | `ada3d268912b5d37b75211f63bcafea1c22a75276e00d65687ebe8a3b1bb8391` |
| harness hashes | 217 | `4e465a2a8027d8ca5a7738b66aef11006b514cc4f5a8184228e3978552355231` |
| final hashes | 306 | `9385c51fae9051b5773d81791cd866e4e9ae3b02fcd2ce5eef7345041323c425` |
| canonical-root log | 616 | `3f9965946ca91594322e2b200a4939cac5aa24753e7d2976c7e335e3b244d518` |
| filtered logcat | 1509147 | `e3bc07eef704695ce589a229cf90c450537612fccbe3966ebe1add25cf4a13fd` |
| APK hash manifest | 264 | `09efe674d40739edfcd8c153008ada47a5e91943fcab79423a72ade771485c8c` |
| raw evidence hashes | 6692 | `0255420eac7bec53546e6162a3d3852e370d3a1cb73b2be65c6566014bcaf62e` |

`manifest.json` lists 55 committed bundle artifact rows (excluding
`manifest.json` itself and `final-artifacts.txt`) with path, byte size, and
SHA-256.

## 9. Reproducibility

1. Start from `15aab0c`, check out `94ef57b`; verify the source manifest with
   `verify.sh`.
2. Ensure the Orca runtime exposes `T025_Pixel7_API35_KVM_20261115` and no
   other session owns it. Verify the guest properties in §3.
3. Build the standalone and test APKs from the host report; install both and
   compare `pm path` + in-guest `sha256sum` with `apk-sha256.txt`.
4. Run the two connected-test commands and the integration command in §4 with
   `ANDROID_SERIAL=emulator-5554`.
5. Install the copied harness APK to compare its in-guest hash; restore the
   standalone/test APKs and compare again.
6. Clear the app data, launch `de.feldexa.app/.MainActivity`, confirm
   `files/feldexa/{docs,templates,tmp,diagnostics}` and no `feldexa_store`,
   then force-stop it.
7. Cleanup: the integration test deletes its own aggregate/signature and the
   app is force-stopped. The AVD definition and synthetic installed test
   packages remain available for independent revalidation.

## 10. External attestation

The active `worker_done` transport record names the candidate code SHA/tree,
base, final branch SHA, checks/counts, limitations, and report bytes/hash. No
attestation ref was created.

A later docs-only privacy correction replaced raw worker task/dispatch
identifiers in this report and the T027 row in `tasks.md` with role labels; no candidate
code, source, log, XML, or APK byte changed and no test was rerun.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
