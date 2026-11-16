# 2026-11-16 NONE — T027 Review-B correction host evidence

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `PASS` |
| Task / issue | `T027` / `#27` |
| Date / timezone | `2026-11-16 17:23 Europe/Berlin` |
| Revision | base commit `15aab0c55c7e77df0d4c4fe199e89c6661ea3db2`; candidate code commit `94ef57b059c71fad01b0f3d46743996325a08dc7` (tree `0444e300e6a4bb0d7b7e21705cc65d635c98c5d0`). The only working-tree change is the pre-existing, deliberately uncommitted `apps/feldexa_app/android/gradlew.bat` phantom (SHA-256 `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62`), which is not part of the candidate. The later docs-only commit carries this report and the artifact bundle; its final branch SHA is named in the active `worker_done` attestation, not self-derived here |
| External attestation | `worker_done` transport record for task `task_496c6c5f2c6e` / dispatch `ctx_0782d0f510af`; it records the candidate code SHA/tree, base, final branch SHA, checks/counts, report bytes/hash, and limitations. No attestation ref was created |
| Build identity | version `0.1.0` (versionCode `1`); mode `debug`; standalone `build/t027-review3/apks/app-debug.apk` 240765509 bytes SHA-256 `37074ddc12cc0ee1349f3ffdcefc651743728a5c1434e6993d574ff9f1d1e110`; AndroidTest `build/t027-review3/apks/app-debug-androidTest.apk` 126352 bytes SHA-256 `2b236f82700f67692b1ad2f3c4bfccda39a135c819f17e5845340b80ff7ff4fb`; Dart integration harness `build/t027-review3/apks/app-debug-integration.apk` 217937973 bytes SHA-256 `8ab95d2e6d915f47d7350082eb0cbad7cd5f2e0f7b7c3cd886714eeb1bbad419` |
| Toolchain | Flutter `3.47.7` (framework `abaf9c5237`), Dart `3.13.5`, Gradle `9.3.1` (wrapper distribution SHA-256 pinned in `gradle-wrapper.properties`), Temurin JDK `17.0.20.1`, Android SDK platforms 34/35/36/37.0, build-tools `35.0.0`/`36.0.0` |
| Input | no corpus; synthetic UUIDv4 aggregate ids, synthetic PDF/source bytes, and synthetic PNG fixtures: native alpha colour types 4/6; tRNS-backed colour types 0/2/3; opaque colour types 0/2/3; malformed/duplicate/out-of-order tRNS; 1024/1025 px, CRC/IHDR/IDAT/filter-bomb and palette cases. No user document, Keystore alias, URI, or device data |

`NONE` is not a runtime class. This report proves host analysis, formatting, Dart
host tests, JVM tests, and exact-source build/input binding for `94ef57b`.
Android runtime evidence is in the separate `EMULATOR` report
[2026-11-16-emulator-t027-store-evidence-94ef57b.md](./2026-11-16-emulator-t027-store-evidence-94ef57b.md);
the two reports must not be aggregated into a `DEVICE` claim.

## 1. Scope

Independent Review A (`ctx_31016c16cdf7`) passed `db8ce0f` and closed the earlier
store-root, PNG-structure, state-preservation, and evidence findings. Independent
Review B (`ctx_8c196ae5cd9a` / `msg_af5c6c94d32d`) then failed that revision on
one remaining point: `SignaturePng.validColorType` accepted RGB colour type 2
and indexed colour type 3 without requiring an alpha channel or a valid `tRNS`
chunk, while `contracts/storage-format.md` §2.4 line 129 requires signature PNG
bytes with an alpha channel. This report covers the accepted correction at
`94ef57b`, committed before the evidence build.

The correction keeps the bounded structural/IDAT decoder and adds the canonical
alpha/transparency requirement during validation:

- Native alpha colour types 4 (gray+alpha) and 6 (RGBA) remain accepted. An
  RGBA image whose pixels are all opaque is still accepted because the alpha
  channel is the requirement, not a pixel-level aesthetic.
- Opaque colour types 0 (gray), 2 (RGB) and 3 (indexed) are accepted only with
  a validation-passing `tRNS` transparency chunk. For type 0 the chunk must be
  exactly two bytes and its gray sample must fit the declared bit depth; for
  type 2 it must be exactly six bytes with R/G/B samples in order and in range;
  for type 3 it must contain 1…PLTE-entry alpha bytes after `PLTE` and before
  `IDAT`.
- `tRNS` is rejected on native-alpha types, when duplicated, when placed after
  `IDAT`, before `PLTE`, or when `PLTE` follows it. Truly alpha-free 0/2/3
  images now fail with canonical `SAVE-007` before staging.
- Validation never transcodes or mutates the signed source bytes; an existing
  asset id still fails `PLT-002` before the PNG check, and prior bytes/head/
  revisions stay unchanged.

The correction changed 9 files (687 insertions, 9 deletions):
`SignaturePng.kt`; unit helpers/tests `TestPng.kt`, `SignaturePngTest.kt`,
`EncryptedStoreTest.kt`, `StoreServiceTest.kt`; instrumentation helpers/tests
`AndroidTestPng.kt`, `EncryptedStoreInstrumentedTest.kt`,
`FeldexaPluginInstrumentedTest.kt`; and the Dart/native journey
`integration_test/t027_store_test.dart`.

## 2. Revision and build

The build was started only after `git rev-parse HEAD` returned `94ef57b`,
`git status --porcelain` showed only the pre-existing `gradlew.bat` phantom, and
`git diff --check` was clean. `flutter clean` was run from `apps/feldexa_app`
(removing the app build and app-local generated state), then
`flutter pub get --offline --enforce-lockfile` restored the lock from the
workspace root, and the Android project cache (`apps/feldexa_app/android/.gradle`)
was removed. A per-source/input manifest covered all 281 tracked files under
`apps/`, `packages/`, `pubspec.yaml`, `pubspec.lock`, and
`specs/001-scanned-form-workflow/contracts/`; the before- and after-run
manifests are byte-identical:

| Manifest | SHA-256 | Result |
| --- | --- | --- |
| source/input before build | `dd96bdf1d56fb30a81cf3efc46c6a0f0f19a44d8d1be22fe80bc2125e50853c5` | identical after run |
| source/input after run | `dd96bdf1d56fb30a81cf3efc46c6a0f0f19a44d8d1be22fe80bc2125e50853c5` | 0-line diff |

The generated state used by the build is recorded in
`generated-config-sha256.txt` (SHA-256
`64843c679a8760fc590e7053cdccbe66621f9ee6270033f0174229cbe16a60d3`); a second
offline `pub get` reproduced it byte-for-byte, and the build did not change it.
`local.properties`, `.dart_tool/package_config.json`, and
`GeneratedPluginRegistrant.java` remained identical.

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
| 1 | `flutter analyze --no-pub` (repo root) | `0` | `logs/host-analyze.log` | `PASS` |
| 2 | `dart format --output=none --set-exit-if-changed packages apps tools` (repo root) | `0` | `logs/host-format.log` | `PASS` |
| 3 | `flutter test --no-pub` (`packages/feldexa_core`) | `0` | `logs/host-test-packages_feldexa_core.log` | `PASS` |
| 4 | `flutter test --no-pub` (`packages/feldexa_export`) | `0` | `logs/host-test-packages_feldexa_export.log` | `PASS` |
| 5 | `flutter test --no-pub` (`packages/feldexa_ports`) | `0` | `logs/host-test-packages_feldexa_ports.log` | `PASS` |
| 6 | `flutter test --no-pub` (`packages/feldexa_adapters_android`) | `0` | `logs/host-test-packages_feldexa_adapters_android.log` | `PASS` |
| 7 | `flutter test --no-pub` (`packages/feldexa_adapters_simulated`) | `0` | `logs/host-test-packages_feldexa_adapters_simulated.log` | `PASS` |
| 8 | `flutter test --no-pub` (`packages/feldexa_ui`) | `0` | `logs/host-test-packages_feldexa_ui.log` | `PASS` |
| 9 | `flutter test --no-pub` (`packages/feldexa_testkit`) | `0` | `logs/host-test-packages_feldexa_testkit.log` | `PASS` |
| 10 | `flutter test --no-pub` (`apps/feldexa_app`) | `0` | `logs/host-test-apps_feldexa_app.log` | `PASS` |
| 11 | `./gradlew :app:testDebugUnitTest --offline --no-daemon --console=plain -Pkotlin.compiler.execution.strategy=in-process` (`apps/feldexa_app/android`) | `0` | `logs/gradle-jvm-test.log` | `PASS` |
| 12 | `flutter build apk --debug --no-pub` (`apps/feldexa_app`) | `0` | `logs/flutter-build-apk.log` | `PASS` |
| 13 | `./gradlew :app:assembleDebug :app:assembleDebugAndroidTest --offline --no-daemon --console=plain -Pkotlin.compiler.execution.strategy=in-process` (`apps/feldexa_app/android`) | `0` | `logs/gradle-assemble-test-apk.log` | `PASS` |

The JVM XML set is 13 files with 260 tests, 0 failures, 0 errors. The Dart host
total is 994 tests: core 462, export 56, ports 108, Android adapters 20,
simulated adapters 97, UI 17, testkit 154, app 80.

## 5. Results

| Area | Observed result |
| --- | --- |
| Alpha requirement | Native alpha types 4/6 are accepted; opaque types 0/2/3 require a valid `tRNS` chunk; truly alpha-free 0/2/3 are rejected with canonical `SAVE-007` |
| tRNS validation | Type 0 length/sample range, type 2 length/order/RGB sample ranges, type 3 length versus PLTE entries, `PLTE`-before-`tRNS`, `tRNS`-before-`IDAT`, single `tRNS`, and no `tRNS` on types 4/6 are enforced; empty/excess/duplicate/misordered chunks are rejected |
| Signed bytes | Validation is read-only; `validationDoesNotMutateSignedBytes` and the store round-trip compare exact bytes. No transcode or normalisation is introduced |
| Rejection state | Opaque and malformed-transparency fixtures fail `SAVE-007`; the rejected asset file is not created and kept signature bytes, head, revisions, and signature-directory bytes remain unchanged |
| Immutability/duplicate | A repeated asset id still fails `PLT-002` before validation, unchanged from `db8ce0f` |
| Boundary/limits | 1024 px long edge remains accepted and 1025 px remains `SAVE-007`; the 2 MiB cap, CRC, IHDR, IDAT/Adam7, palette, filter-bomb, and trailing-byte cases remain covered |
| Existing behavior | Production root `filesDir/feldexa`, cryptography, authenticated read-back, source ownership, canonical JSON, raster eviction, state, and privacy rules are unchanged |
| JVM suite | 260/260 tests pass in 13 XML files, including 21 `SignaturePngTest` cases, 53 `EncryptedStoreTest` cases, 10 `StoreServiceTest` cases, and the existing root/fault/review/prune suites |
| APK builds | Standalone debug and AndroidTest APKs build successfully from the clean candidate |
| Runtime | Android emulator/device runtime is in the separate `EMULATOR` report; this report makes no runtime claim |

## 6. Performance

No performance claim.

## 7. Limitations

- Host checks cannot prove Android Keystore, channel, storage, startup, or
  Dart→native behavior; those are in the separate `EMULATOR` report.
- No `DEVICE`, release-build, physical-silicon, performance, full UI, T031
  startup/product-behavior, export-artifact, OCR-quality, or acceptance claim.
- The other part of `contracts/storage-format.md` §2.4's signature row, "trimmed",
  is a capture-side ink-bounds property with no byte-level definition or
  tolerance in the contracts. T027 validates the stored PNG's structural,
  dimension, and alpha/transparency representation; it does not invent a pixel
  transparency or crop policy.
- Template channel operations remain fail-closed (`PLT-001`) because their
  payload is still unspecified in `contracts/platform-channel.md` §4.
- Native import/OCR/export/delivery engines remain future tasks; the accepted
  OCR page-size seam limitation is unchanged.
- This is author evidence. The same independent Review A and Review B roles
  must revalidate the final new branch SHA; no self-review, push, PR, or remote
  merge was performed.

## 8. Artifacts

Artifact paths are relative to
`specs/001-scanned-form-workflow/reports/artifacts/t027-review-b-94ef57b/`.
The committed bundle excludes APKs and unredacted raw logs; the local raw bytes
are bound by `raw-evidence-sha256.txt` under the git-ignored `build/t027-review3/`.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| standalone debug APK | 240765509 | `37074ddc12cc0ee1349f3ffdcefc651743728a5c1434e6993d574ff9f1d1e110` |
| AndroidTest APK | 126352 | `2b236f82700f67692b1ad2f3c4bfccda39a135c819f17e5845340b80ff7ff4fb` |
| integration-harness APK | 217937973 | `8ab95d2e6d915f47d7350082eb0cbad7cd5f2e0f7b7c3cd886714eeb1bbad419` |
| JVM signature XML | 2803 | `591885225f446b10a4abd73ca221dffd4c85c1725e77b7bf169d8e088dac8f33` |
| JVM store XML | 7145 | `f068435ee414750486de527eec43b9d2ba80234148fb23d48b960ccdbd26bf80` |
| JVM service XML | 1705 | `6c4426afc5824222da2ec974ba8491b1cafa1ef73253a6be47ba23f7c114560b` |
| storage instrumentation XML | 6016 | `52109e333a4087f1cac0d491cacbbc37e6957bb9b5e5aa35c5634c567ac19018` |
| channel instrumentation XML | 3572 | `345ad8a7a33ab60aa697a535a34f2a75aea9f5e8ca9f4b7e1848e42deb33c156` |
| JVM run log | 20659 | `537833df8a34d2fe5fb2b08e2680042495a2bb52a3abb9ef5e9dc1126836c42b` |
| storage run log | 23412 | `7b60ecfd23af27fe0a23666d2e40295da437fadf90456827204c95baa8e51a17` |
| channel run log | 23499 | `00ac3db13233f4a1c13a8349c8e83ab312829d01c23f8f82e7022c49e03f44b5` |
| integration log | 1225 | `c09b75ad3ea9ee098a50ec3d4deb52eb4207a247dfb86e4cf5be49f8377d7a2f` |
| source manifest | 34413 | `dd96bdf1d56fb30a81cf3efc46c6a0f0f19a44d8d1be22fe80bc2125e50853c5` |
| generated config manifest | 477 | `64843c679a8760fc590e7053cdccbe66621f9ee6270033f0174229cbe16a60d3` |
| raw evidence hashes | 6692 | `0255420eac7bec53546e6162a3d3852e370d3a1cb73b2be65c6566014bcaf62e` |
| artifact manifest | 15043 | see `manifest.json`; it lists 55 committed artifact rows |
| flat artifact listing | 10332 | `final-artifacts.txt`; 56 rows including `manifest.json` |
| toolchain | 1982 | `24eac9fcd3d3ded9ed0a8d814258f92638715d50c44e75ba1001f670ab97cc61` |
| bundle README | 2160 | `1957fe418030536b6761629ce3ea824f79a529eae73d1715e53219f9929f7a8a` |
| verification script | 669 | `625f6f47782386532c3764e1e7015d392ac2fac369d2b1082f1fdf435ae617cd` |

## 9. Reproducibility

1. Start from `15aab0c`, check out `94ef57b`; the later docs-only commit adds
   only this report, its companion, the index/task rows, and artifact copies.
2. Run `flutter clean` from `apps/feldexa_app`, then
   `flutter pub get --offline --enforce-lockfile` from the repository root.
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
