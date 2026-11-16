# 2026-11-16 NONE — T027 Review-A correction host evidence

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `PASS` |
| Task / issue | `T027` / `#27` |
| Date / timezone | `2026-11-16 16:38 Europe/Berlin` |
| Revision | base commit `15aab0c55c7e77df0d4c4fe199e89c6661ea3db2`; tree clean at candidate code commit `db8ce0f91e364f64107f860bd69c8dc8cacddb3c` (tree `c7c8bcf096f5a1517c65f5a02e5ef3906af89914`) except the pre-existing, deliberately uncommitted `apps/feldexa_app/android/gradlew.bat` phantom SHA-256 `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62`, which is not part of the candidate; candidate SHA and this report's bytes/hash are in the external attestation |
| External attestation | `worker_done` transport record for this dispatch; it records the candidate code SHA/tree, final branch SHA, changed files, report bytes/hash, and limitations. No attestation ref was created |
| Build identity | version `0.1.0` (versionCode `1`); mode `debug`; standalone `build/t027-review2/apks/app-debug.apk` 240765509 bytes SHA-256 `6ad46474ac6115c8fa5f56725c51a1ecda35c21e0e473c528e1ec09cf51c5e0a`; AndroidTest `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/app-debug-androidTest.apk` 123828 bytes SHA-256 `1fff9293bbb9640fed01669146f5d279d8d63484943f572299c2830af3288fd9`; Dart integration harness `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/app-debug-integration.apk` 217937973 bytes SHA-256 `93525519dc149e452cb82b579b62fcffed5cb0633db74b651b08062899f98de3` |
| Toolchain | Flutter `3.47.7` (framework `abaf9c5237`), Dart `3.13.5`, Gradle `9.3.1` (wrapper distribution SHA-256 pinned), Temurin JDK `17.0.20.1`, Android SDK platforms 34/35/36/37.0, build-tools `35.0.0`/`36.0.0` |
| Input | no corpus; synthetic aggregate ids, synthetic PDF/source bytes, and synthetic valid PNG fixtures (2×2, 3×3, 1024×1024, 1024×1, 1025×1024, 1025×1) produced by an independent Python zlib/CRC encoder or the test encoder; no user document, Keystore alias, URI, or device data |

`NONE` is not a runtime class. This report proves host analysis, formatting,
Dart host tests, JVM tests, and exact-source build/input binding for `db8ce0f`.
Android runtime evidence is in the separate `EMULATOR` report
[2026-11-16-emulator-t027-store-evidence-db8ce0f.md](./2026-11-16-emulator-t027-store-evidence-db8ce0f.md);
the two reports must not be aggregated into a `DEVICE` claim.

## 1. Scope

Review A (independent reviewer message) independently verified the prior three
corrections and the committed-source evidence, but failed only two points on
`d45f4df`:

1. `MainActivity.kt:38` composed the store on `filesDir/feldexa_store`; the
   normative path in `contracts/storage-format.md` §1 is `filesDir/feldexa/`.
2. `StoreService.kt:294-309` / `EncryptedStore.kt:832-849` checked only size
   and caller hash, so arbitrary/non-PNG bytes and oversized dimensions were
   accepted; `contracts/platform-channel.md` §10 and `data-model.md` §3.7
   require a Signature PNG at most 2 MiB with a positive long edge at most
   1024 px, while `SignatureMark` requires real decodable PNG data.

This report covers the correction at `db8ce0f`, committed before the evidence
build. The report and its artifacts are in a later docs-only commit; they do
not rerun or rebrand the build. The prior `d45f4df` host report remains
historical and is superseded for the corrected candidate.

## 2. Revision and build

The correction changed 12 files (1459 insertions, 34 deletions):

- `MainActivity.kt` — canonical `STORE_ROOT_DIR = "feldexa"` root; the legacy
  `feldexa_store` directory is not deleted, renamed, or silently migrated;
- `EncryptedStore.kt` — calls `SignaturePng.requireValid` after the immutable
  asset check and before staging;
- `SignaturePng.kt` — new bounded PNG structure/decode validator;
- `SignaturePngTest.kt`, `TestPng.kt`, `MainActivityStoreRootTest.kt`,
  `EncryptedStoreTest.kt`, `StoreServiceTest.kt` — host regressions;
- `FeldexaPluginInstrumentedTest.kt`, `EncryptedStoreInstrumentedTest.kt`,
  `AndroidTestPng.kt` — real Android PNG cases;
- `integration_test/t027_store_test.dart` — real Dart/native PNG fixtures and
  invalid-image refusal.

The build was started only after `git rev-parse HEAD` returned the candidate,
`git status --porcelain` showed only the pre-existing `gradlew.bat` phantom,
and `git diff --check` was clean. `flutter clean` removed generated app state,
then `flutter pub get --offline --enforce-lockfile` restored the lock, and the
Android project cache was removed. A per-source/input manifest covered all 281
tracked files under `apps/`, `packages/`, `pubspec.yaml`, `pubspec.lock`, and
`specs/001-scanned-form-workflow/contracts/`; the before- and after-run
manifests are byte-identical:

| Manifest | SHA-256 | Result |
| --- | --- | --- |
| source/input before build | `30ea34f9e86baa655f5cb743dac7519c9a10e9773ec069a5a334eb276d91bc3c` | identical after run |
| source/input after run | `30ea34f9e86baa655f5cb743dac7519c9a10e9773ec069a5a334eb276d91bc3c` | 0-line diff |

`flutter clean` deleted the generated `.flutter-plugins-dependencies`, and
`flutter pub get` regenerated it. The generated state used by the build is
recorded in `generated-config-sha256.txt` (SHA-256
`4f6f9cc7bf7fb7fb584ac171b2f30b234e4631ef970d8db52f60a7ea0c9a3b4f`); a second
offline `pub get` reproduced it byte-for-byte, and the build did not change it.
`local.properties`, `.dart_tool/package_config.json`, and
`GeneratedPluginRegistrant.java` were identical before and after the run.

## 3. Environment

Host: Linux x86_64. The executed checks are Dart analysis/format/tests,
Kotlin/JVM compilation, JUnit, Gradle, Flutter debug APK assembly, and Android
test-APK assembly. No Android emulator or physical device is claimed by this
`NONE` report; the Android runtime is in the separate `EMULATOR` report.

The DSH sandbox mounts most of the host filesystem read-only. The checks used
workspace-local shadows of the Flutter SDK, pub cache, Gradle user home, Android
SDK, and JDK; these shadows, `local.properties`, and the generated plugin files
are environment-only and are not committed.

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `flutter analyze --no-pub` (repo root) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/host-analyze.log` | `PASS` |
| 2 | `dart format --output=none --set-exit-if-changed packages apps tools` (repo root) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/host-format.log` | `PASS` |
| 3 | `flutter test --no-pub` (`packages/feldexa_core`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/host-test-packages_feldexa_core.log` | `PASS` |
| 4 | `flutter test --no-pub` (`packages/feldexa_export`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/host-test-packages_feldexa_export.log` | `PASS` |
| 5 | `flutter test --no-pub` (`packages/feldexa_ports`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/host-test-packages_feldexa_ports.log` | `PASS` |
| 6 | `flutter test --no-pub` (`packages/feldexa_adapters_android`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/host-test-packages_feldexa_adapters_android.log` | `PASS` |
| 7 | `flutter test --no-pub` (`packages/feldexa_adapters_simulated`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/host-test-packages_feldexa_adapters_simulated.log` | `PASS` |
| 8 | `flutter test --no-pub` (`packages/feldexa_ui`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/host-test-packages_feldexa_ui.log` | `PASS` |
| 9 | `flutter test --no-pub` (`packages/feldexa_testkit`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/host-test-packages_feldexa_testkit.log` | `PASS` |
| 10 | `flutter test --no-pub` (`apps/feldexa_app`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/host-test-apps_feldexa_app.log` | `PASS` |
| 11 | `./gradlew :app:testDebugUnitTest --offline --no-daemon --console=plain -Pkotlin.compiler.execution.strategy=in-process` (`apps/feldexa_app/android`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/gradle-jvm-test.log` | `PASS` |
| 12 | `flutter build apk --debug --no-pub` (`apps/feldexa_app`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/flutter-build-apk.log` | `PASS` |
| 13 | `./gradlew :app:assembleDebug :app:assembleDebugAndroidTest --offline --no-daemon --console=plain -Pkotlin.compiler.execution.strategy=in-process` (`apps/feldexa_app/android`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/gradle-assemble-test-apk.log` | `PASS` |

The JVM XML set is 13 files with 252 tests, 0 failures, 0 errors. The Dart host
total is 994 tests: core 462, export 56, ports 108, Android adapters 20,
simulated adapters 97, UI 17, testkit 154, app 80.

## 5. Results

| Area | Observed result |
| --- | --- |
| Production store root | `MainActivity` uses the `STORE_ROOT_DIR = "feldexa"` constant; `MainActivityStoreRootTest` pins `filesDir/feldexa`. The legacy `feldexa_store` directory is not deleted, renamed, or silently migrated, and no migration is introduced |
| PNG structure | `SignaturePng` checks the signature, every chunk length/type/CRC/order, IHDR width/height (`> 0`, `<= 1024`), colour/bit-depth/compression/filter/interlace, palette rules, contiguous IDAT, exact bounded inflate, and scanline unfiltering including Adam7 |
| Invalid image/limit | `InvalidDataException` maps to canonical `SAVE-007`; non-PNG, truncated, bad-CRC, corrupt-IDAT, missing-IEND, trailing bytes, decompression bomb, invalid filter/IHDR, palette-missing, unknown critical chunk, and 1025 px cases are rejected |
| Immutability | A repeated asset id still fails `PLT-002`; a rejected invalid image never stages, and prior bytes/head/revisions/signature files stay unchanged |
| Existing behavior | Cryptography, authenticated read-back, source ownership, canonical JSON, raster eviction, state, and privacy rules remain unchanged |
| JVM suite | 252/252 tests pass in 13 XML files, including 14 `SignaturePngTest`, 1 root test, 2 store regressions, and 2 service regressions |
| APK builds | Debug standalone and test APKs build successfully from the clean candidate |
| Runtime | Android emulator/device runtime is in the separate `EMULATOR` report; this report makes no runtime claim |

Old arbitrary byte fixtures in native tests were replaced with valid PNGs;
malformed and fault-injection cases remain explicit. The simulated adapter keeps
signature bytes opaque by design and was not changed.

## 6. Performance

No performance claim.

## 7. Limitations

- Host checks cannot prove Android Keystore, channel, storage, startup, or
  Dart→native behavior; those are in the separate `EMULATOR` report.
- No `DEVICE`, release-build, physical-silicon, performance, full UI, T031
  startup/product-behavior, export-artifact, OCR-quality, or acceptance claim.
- Template channel operations remain fail-closed (`PLT-001`) because their
  payload is still unspecified in `contracts/platform-channel.md` §4.
- Native import/OCR/export/delivery engines remain future tasks; the accepted
  OCR page-size seam limitation is unchanged.
- This is author evidence. The same independent Review A and Review B roles
  must revalidate the final new branch SHA; no self-review, push, PR, or remote
  merge was performed.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| standalone debug APK | `build/t027-review2/apks/app-debug.apk` | 240765509 | `6ad46474ac6115c8fa5f56725c51a1ecda35c21e0e473c528e1ec09cf51c5e0a` |
| AndroidTest APK | `build/t027-review2/apks/app-debug-androidTest.apk` | 123828 | `1fff9293bbb9640fed01669146f5d279d8d63484943f572299c2830af3288fd9` |
| integration-harness APK | `build/t027-review2/apks/app-debug-integration.apk` | 217937973 | `93525519dc149e452cb82b579b62fcffed5cb0633db74b651b08062899f98de3` |
| JVM signature XML | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/junit/TEST-de.feldexa.app.storage.SignaturePngTest.xml` | 1931 | `c96dd2bcecfa8ce7fa5f42c095af7b3d8106617b8ec2e2775fefe1718e63fc59` |
| JVM run log | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/gradle-jvm-test.log` | 17822 | `a01d6b7d8a9c4fdce14356f8c98392891da4ba35f57189ccccb2e3122669299b` |
| core test log | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/host-test-packages_feldexa_core.log` | 65470 | `8424b469d9bcd9cb50f2d79eca731bfcc361af4279434351f9065df7f7b2b6ed` |
| export test log | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/host-test-packages_feldexa_export.log` | 9125 | `db8226536f756fee1a9ee2f924775110afd2b005374d1d13cb2e051d791fcc31` |
| ports test log | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/host-test-packages_feldexa_ports.log` | 15764 | `66a1ed5780a6508374070872ff10d8d51eeac18a32bce4562399bdac15b98056` |
| Android adapter test log | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/host-test-packages_feldexa_adapters_android.log` | 3064 | `90d27f6399d9d0885d39db1112f2aac086020a71b5c72b10db6b362a861e5bcf` |
| simulated adapter test log | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/host-test-packages_feldexa_adapters_simulated.log` | 16044 | `51c266181b89cdbfb3858c98d5cd8f12b3a00e6b5f7b4d54d596e8e59c7e0f90` |
| UI test log | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/host-test-packages_feldexa_ui.log` | 1809 | `007b1acbfdc77e7c7d6395f955b8438961f7edc6dd18413093b7e0b5e725e430` |
| testkit test log | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/host-test-packages_feldexa_testkit.log` | 21803 | `0cd8c47a97cd92253cd7bcb512c38d89fadfe65849caf66d153d3df0659412de` |
| app test log | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/host-test-apps_feldexa_app.log` | 12101 | `569364739875ea7dfa11b909ba1f6e5205c4180eb30eb2b4c844b9e9821e3233` |
| APK build log | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/flutter-build-apk.log` | 29761 | `907c29a1af382a860d59d4b6ef7070a7160f5132ae3fa767d4ce67b8533ddd47` |
| test-APK assembly log | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/gradle-assemble-test-apk.log` | 22887 | `984ff9b047879365f84b8da73b2d8df8de641974944596b609130e90e4e1ccc2` |
| analysis log | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/host-analyze.log` | 97 | `5ff7de70625eb548f27e4ee20c458da6c444752a9d3e20e9e4c09b3eddcfc4b1` |
| format log | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/logs/host-format.log` | 49 | `4a1ce5295676be12df62e187decde1da8f19e87e51bdca700f9796cbee77ff9e` |
| source manifest | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/source-sha256.txt` | 34413 | `30ea34f9e86baa655f5cb743dac7519c9a10e9773ec069a5a334eb276d91bc3c` |
| generated config manifest | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/generated-config-sha256.txt` | 477 | `4f6f9cc7bf7fb7fb584ac171b2f30b234e4631ef970d8db52f60a7ea0c9a3b4f` |
| artifact manifest | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/manifest.json` | 13187 | `56400057212cdd3cf1099a7195ee2d962e1ca1e394d24486e19fe5c3775005aa` |
| flat artifact listing | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/final-artifacts.txt` | 8810 | `a9c74123a1f91aa7fa6e3c2962e4ef324f91be0eb96e52b40a82355bbf5458d1` |
| toolchain | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/toolchain.txt` | 1990 | `0c7368076219e7a5bc66a2ca2ff14a9e5fb6c5c7907fbefb2e1edb91a641c200` |
| bundle README | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/README.md` | 2055 | `317ef4620c4cc8cb52111a020d9f04539d6a49c685a95bb7e3d8851deaf07912` |
| verification script | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/verify.sh` | 671 | `93b4d572ba3250bd71e1b9a50acd32e3f395213bf53b6330a09f3d8ba2ac707d` |
| raw evidence hashes | `specs/001-scanned-form-workflow/reports/artifacts/t027-review-a-db8ce0f/raw-evidence-sha256.txt` | 5807 | `d36a6459efa8dc22bdbf203e96b20ca67f5215031557c62a75768e6c4af98959` |

`manifest.json` lists 47 committed bundle artifact rows (excluding
`manifest.json` itself and `final-artifacts.txt`) with path, byte size, and
SHA-256. Raw, unredacted logs are local git-ignored copies under
`build/t027-review2/`; their exact SHA-256 values are in
`raw-evidence-sha256.txt`.

## 9. Reproducibility

1. Start from `15aab0c`, check out `db8ce0f`; the later docs-only commit adds
   only this report, its companion, the index/task rows, and artifact copies.
2. Run `flutter clean`, then `flutter pub get --offline --enforce-lockfile`.
3. Run the host commands in §4 from the named working directories; expect the
   counts shown.
4. Build the APKs with `flutter build apk --debug --no-pub` and the Gradle
   assemble command in §4.
5. Verify `source-sha256.txt` and `apk-sha256.txt` with `verify.sh`.

## 10. External attestation

The active `worker_done` transport record names the candidate code SHA/tree,
base, final branch SHA, checks/counts, limitations, and report bytes/hash. No
attestation ref was created.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
