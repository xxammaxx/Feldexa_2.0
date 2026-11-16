# 2026-11-16 EMULATOR — T027 Review-A correction Android store evidence

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` |
| Result | `PASS` |
| Task / issue | `T027` / `#27` |
| Date / timezone | `2026-11-16 16:38 Europe/Berlin` |
| Revision | base commit `15aab0c55c7e77df0d4c4fe199e89c6661ea3db2`; tree clean at candidate code commit `db8ce0f91e364f64107f860bd69c8dc8cacddb3c` (tree `c7c8bcf096f5a1517c65f5a02e5ef3906af89914`) except the pre-existing, deliberately uncommitted `apps/feldexa_app/android/gradlew.bat` phantom SHA-256 `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62`, which is not part of the candidate; candidate SHA and this report's bytes/hash are in the external attestation |
| External attestation | `worker_done` transport record for this dispatch; it records the candidate code SHA/tree, base, final branch SHA, checks/counts, limitations, and report bytes/hash. No attestation ref was created |
| Build identity | version `0.1.0` (versionCode `1`); mode `debug`; standalone `build/t027-review2/apks/app-debug.apk` 240765509 bytes SHA-256 `6ad46474ac6115c8fa5f56725c51a1ecda35c21e0e473c528e1ec09cf51c5e0a`; AndroidTest `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/app-debug-androidTest.apk` 123828 bytes SHA-256 `1fff9293bbb9640fed01669146f5d279d8d63484943f572299c2830af3288fd9`; Dart integration harness `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/app-debug-integration.apk` 217937973 bytes SHA-256 `93525519dc149e452cb82b579b62fcffed5cb0633db74b651b08062899f98de3` |
| Toolchain | Flutter `3.47.7` (framework `abaf9c5237`), Dart `3.13.5`, Gradle `9.3.1`, Temurin JDK `17.0.20.1`, Android SDK platforms 34/35/36/37.0, build-tools `35.0.0`/`36.0.0`, adb `1.0.41` (`37.0.1`) |
| Input | no corpus; synthetic UUIDv4 aggregate ids, synthetic PDF/source bytes, and synthetic valid PNG fixtures (2×2, 3×3, 1024×1024, 1024×1, 1025×1024, 1025×1) plus malformed/truncated/corrupt variants; no user document, URI, or unrelated device data |

This report proves Android-runtime behavior only for the exclusively allocated
Pixel 7 API 35 AVD below. It does not claim `DEVICE`, physical-silicon key
strength, release-heap, performance, full UI/T031/product behavior, or
physical-device acceptance. The code correction was committed **before** this
build and run; the report itself is in a later docs-only commit.

## 1. Scope

Review A accepted the prior three corrections but failed only two points on
`d45f4df`: the production store root used `filesDir/feldexa_store` instead of
the normative `filesDir/feldexa/`, and a signature upload was checked only for
size and caller hash rather than being a real bounded PNG. This run exercises
both corrections on the real Android runtime:

- `MainActivity` composes `EncryptedStore` on the canonical root; launching the
  standalone app created only `files/feldexa/{docs,templates,tmp,diagnostics}`
  and no `feldexa_store` directory.
- `EncryptedStore.writeSignature` now runs `SignaturePng` before staging;
  invalid/non-PNG/truncated/corrupt/oversized-long-edge uploads fail with
  `SAVE-007`, a repeated asset id still fails with `PLT-002`, and prior
  signature bytes, head, and revision files stay unchanged.

The prior `d45f4df` emulator report remains historical and is superseded for the
corrected candidate. Host support is in
[2026-11-16-t027-host-evidence-db8ce0f.md](./2026-11-16-t027-host-evidence-db8ce0f.md)
(`NONE`; not aggregated with this runtime result).

## 2. Revision and build

The correction is the 12-file commit `db8ce0f` described in the host report.
The APKs below were built from the clean tree after `flutter clean`,
`flutter pub get --offline --enforce-lockfile`, and removal of the Android
project cache. The source/input manifest is identical before and after the run
(SHA-256 `30ea34f9e86baa655f5cb743dac7519c9a10e9773ec069a5a334eb276d91bc3c`).
The standalone APK was installed and compared in-guest before tests; the Dart
integration harness replaced it during the journey and was hash-checked too;
the standalone/test APKs were restored and compared again afterwards.

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
          sys.boot_completed=1, init.svc.bootanim=stopped
          2 vCPU; RAM 3072 MB (MemTotal 3048512 kB)
          APK build/t027-review2/apks/app-debug.apk
          APK SHA-256 6ad46474ac6115c8fa5f56725c51a1ecda35c21e0e473c528e1ec09cf51c5e0a
          build mode debug
```

Allocation checks before attach:

- `orca emulator list --worktree all --json` returned `sessions: []`;
- `orca emulator devices` listed `T025_Pixel7_API35_KVM_20261115` as `booted`
  and every other listed AVD as `shutdown`;
- `orca emulator attach T025_Pixel7_API35_KVM_20261115 --json` returned
  `attached: true`, `deviceUdid: emulator-5554`;
- after attach, `orca emulator list --worktree all --json` showed exactly one
  session bound to this worktree and `adb devices -l` showed exactly one
  `emulator-5554` device. No physical phone or unrelated AVD was used. The
  guest was fully booted before any test.

**KVM limitation.** The AVD is the named, KVM-provisioned T025 profile and prior
T025/T026 `EMULATOR` runs on this same AVD recorded KVM device-node evidence.
This DSH sandbox does not expose the host KVM device node or the host emulator
process, so a new host acceleration probe was `UNAVAILABLE`; no
software-fallback boot was observed. The KVM statement is therefore limited to
the named AVD/session and prior evidence, not a fresh host-probe result.

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `orca emulator attach T025_Pixel7_API35_KVM_20261115 --json` (repo root) | `0` | `console only (not retained)` | `PASS` |
| 2 | `./gradlew :app:connectedDebugAndroidTest --offline --no-daemon --console=plain -Pkotlin.compiler.execution.strategy=in-process -Pandroid.testInstrumentationRunnerArguments.class=de.feldexa.app.storage.EncryptedStoreInstrumentedTest,de.feldexa.app.storage.KeystoreServiceInstrumentedTest` (`apps/feldexa_app/android`, `ANDROID_SERIAL=emulator-5554`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/gradle-connected-storage.log` | `PASS` |
| 3 | `./gradlew :app:connectedDebugAndroidTest --offline --no-daemon --console=plain -Pkotlin.compiler.execution.strategy=in-process -Pandroid.testInstrumentationRunnerArguments.class=de.feldexa.app.FeldexaPluginInstrumentedTest` (same) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/gradle-connected-channel.log` | `PASS` |
| 4 | `env ORG_GRADLE_PROJECT_kotlin.compiler.execution.strategy=in-process flutter test integration_test/t027_store_test.dart -d emulator-5554 --no-pub` (`apps/feldexa_app`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/integration-store.log` | `PASS` |
| 5 | `adb install -r` both APKs; `pm path` + in-guest `sha256sum` (repo root) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/installed-hashes-before-tests.log` | `PASS` |
| 6 | restore both APKs; `pm path` + in-guest `sha256sum` (repo root) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/installed-hashes-final.log` | `PASS` |
| 7 | `am start -n de.feldexa.app/.MainActivity`; `run-as de.feldexa.app ls/find files`; force-stop (repo root) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/canonical-root-runtime.log` | `PASS` |

The storage run passed 33/33 tests, 0 failures, 0 errors; the channel run passed
20/20; the Dart integration journey passed 1/1.

## 5. Results

| Area | Observed result |
| --- | --- |
| Storage instrumentation | `invalidSignaturePngIsRejectedAndPreservesPriorStateOnDevice` rejects non-PNG, truncated, and CRC-corrupt payloads with `SAVE-007` while kept bytes/head/revisions/signature files stay unchanged; `signatureBoundary1024IsAcceptedAnd1025IsSave007OnDevice` accepts a real 1024×1024 Android-encoded PNG and rejects a real 1025×1024 PNG |
| Channel instrumentation | `realStoreSignaturePngValidationThroughChannel` accepts a valid Android PNG, rejects non-PNG/truncated/corrupt payloads with terminal `SAVE-007` and unchanged prior state, accepts 1024×1024, and rejects 1025×1024; the existing large journey now uses valid PNGs for the original and `PLT-002` repeated-asset paths |
| Dart/native journey | Real valid PNG constants (2×2, 3×3, 1024×1) are written/read; non-PNG and truncated uploads throw `AndroidInvalidDataException` (`SAVE-007`) without changing kept bytes/head; 1024×1 is accepted and a valid 1025×1 is rejected; the duplicate asset still throws `SecurityException`/`PLT-002` |
| Production root | The standalone app launched from the candidate APK and created exactly `files/feldexa/{docs,templates,tmp,diagnostics}`; no `files/feldexa_store` was created |
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

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| standalone debug APK | `build/t027-review2/apks/app-debug.apk` | 240765509 | `6ad46474ac6115c8fa5f56725c51a1ecda35c21e0e473c528e1ec09cf51c5e0a` |
| AndroidTest APK | `build/t027-review2/apks/app-debug-androidTest.apk` | 123828 | `1fff9293bbb9640fed01669146f5d279d8d63484943f572299c2830af3288fd9` |
| integration-harness APK | `build/t027-review2/apks/app-debug-integration.apk` | 217937973 | `93525519dc149e452cb82b579b62fcffed5cb0633db74b651b08062899f98de3` |
| storage JUnit XML | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/junit/storage-33-tests.xml` | 5862 | `ad2450623de6e0ca5a88ba4c10df18e1c8dd7192b47c15ca65278f1c7d44a192` |
| channel JUnit XML | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/junit/channel-20-tests.xml` | 3568 | `654701ef1dd2c20350f4be016583d97470393308c2b2ad52189ca42c4a925750` |
| storage run log | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/gradle-connected-storage.log` | 23412 | `1e7a88f59b04839f8ff49367c43b3d7c75486382cd311032dc5292c4fe630db9` |
| channel run log | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/gradle-connected-channel.log` | 23499 | `f5c58141946e680089c40a9958c9d298403dea9d0f1c8bf4855d5ca110819ef0` |
| integration log | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/integration-store.log` | 1225 | `9a50e59091ef3b16aa929b0bb0f0ac66a3c5f7eb0843521ad4d9e122a53e0a64` |
| before-test hashes | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/installed-hashes-before-tests.log` | 305 | `d33825ab3cde6891106410b61ee48b08ff8ad02017eaafd860fa37816408c381` |
| harness hashes | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/installed-hashes-after-integration.log` | 177 | `2d93c648a68d30f009543d5c54b06cf7ca3e0ee2bbf4b9f5ff63f9492016a92c` |
| final hashes | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/installed-hashes-final.log` | 306 | `df6f1c4f1dcee4b51614d460702f276f1b7848334365cfcfc25f0e4da9201391` |
| canonical-root log | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/canonical-root-runtime.log` | 417 | `6decb1b520d88f7af3aa8b1a4e82b95d9e94f7a10591ab6b404094262a853aec` |
| filtered logcat | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/logcat-filtered-after-final.txt` | 1073027 | `11df2127010d829083b297be1431a622c8ec85a5126708b2a427096493acf444` |
| APK hash manifest | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/apk-sha256.txt` | 264 | `3fe193003783f809afde2b7dc80897865e97e78f00fda5ae9d32954bc36781d7` |
| artifact manifest | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/manifest.json` | 13187 | `56400057212cdd3cf1099a7195ee2d962e1ca1e394d24486e19fe5c3775005aa` |
| flat artifact listing | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/final-artifacts.txt` | 8810 | `a9c74123a1f91aa7fa6e3c2962e4ef324f91be0eb96e52b40a82355bbf5458d1` |

Committed logs are path-redacted copies; JUnit XML is unmodified. Raw APKs and
raw logs remain local, git-ignored build outputs; `apk-sha256.txt`,
`manifest.json`, and `raw-evidence-sha256.txt` bind their exact bytes.

## 9. Reproducibility

1. Start from `15aab0c`, check out `db8ce0f`; verify the source manifest with
   `verify.sh`.
2. Ensure the Orca runtime exposes `T025_Pixel7_API35_KVM_20261115` and no
   other session owns it. Attach it and verify the guest properties in §3.
3. Build the standalone and test APKs from the host report; install both and
   compare `pm path` + in-guest `sha256sum` with `apk-sha256.txt`.
4. Run the two connected-test commands and the integration command in §4 with
   `ANDROID_SERIAL=emulator-5554`.
5. Install the standalone APK, launch `de.feldexa.app/.MainActivity`, confirm
   `files/feldexa/{docs,templates,tmp,diagnostics}` and no `feldexa_store`,
   then force-stop it.
6. Restore the standalone app/test APKs and compare the in-guest hashes again.
7. Cleanup: the integration test deletes its own aggregate/signature and the app
   is force-stopped. The AVD definition and synthetic installed test packages
   remain available for independent revalidation.

## 10. External attestation

The active `worker_done` transport record names the candidate code SHA/tree,
base, final branch SHA, checks/counts, limitations, and report bytes/hash. No
attestation ref was created.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
