# T027 Android store service and thin-client evidence

**Date**: 2026-11-16 (Europe/Berlin)
**Candidate code commit**: `5b4c295014bf63bb7f673fc492e40c8bdfe4ddee`
**Branch**: `xxammaxx/feldexa-t027`
**Base**: `origin/main` `15aab0c55c7e77df0d4c4fe199e89c6661ea3db2` (PR #185, issue #24 closed)
**Merge commit into the candidate**: `3a3202cc6ad73fa6303587b185be818e4cbbc0ac`
(new origin/main merged normally; no rewrite)
**Task**: issue #27 / `specs/001-scanned-form-workflow/tasks.md` T027
**Evidence classes**: `NONE` (host analysis/JVM/Dart), `EMULATOR` (Pixel 7 API 35). No `DEVICE`,
performance, push, PR, merge, or self-review claim is made.

## 1. What was completed

The Android adapter package previously contained only a partial `store.status` and a
partial save client. This candidate completes the T027 transport layer and wires it to
the real T026 store:

- **Native `StoreService`** (`storage/StoreService.kt`) implements the defined channel
  store surface over the real `EncryptedStore` + `KeystoreService`:
  `store.status`, `store.list`, `store.stageSource`, `store.createDocument`,
  `store.readSource`, `store.readSignature`, `store.writeSignature`,
  `store.saveRevision`, `store.loadDocument`, `store.delete`,
  `store.recoveryStamp`, and `store.startupRecovery`. It does not reimplement
  encryption, key lifecycle, commit/read-back, retention, or recovery.
- **Real production registration** in `MainActivity`: root
  `filesDir/feldexa_store`, `KeystoreService.forAndroid(this)`, `store` prefix
  registered with the T024 `FeldexaPlugin`. A launch check showed the four documented
  directories (`docs`, `templates`, `tmp`, `diagnostics`) and no crash.
- **Verified document create path**: the approved `CreateDocumentRequest`
  (`documentId`, `title`, `source`, `initialRevision`) is persisted exactly once.
  `EncryptedStore.stageSource` writes/read-back-verifies the encrypted source first;
  `createDocumentFromStagedSource` authenticates the staged source against the
  importer hash/size, rejects a parented or mismatched initial revision, writes the
  revision/head/meta, and returns `StoredMeta` only from the committed readable
  aggregate. A visible duplicate is rejected without overwriting.
- **`StoredMeta` projection** comes from the persisted meta plus the verified head
  (`latestRevisionId`, `updatedAt`, `lastDurableAt`). An unreadable aggregate uses the
  localized `Nicht lesbar` title and the observed directory mtime, never a
  ciphertext-derived title.
- **Dart thin clients** in `packages/feldexa_adapters_android/lib/src/`:
  `AndroidStoreClient` (full `SecureStorePort` document surface plus
  `stageSource`/`runStartupRecovery`), `AndroidImportClient`, `AndroidOcrClient`,
  `AndroidPdfExportClient`, `AndroidDeliveryClient`, `AndroidPdfrxRasterClient`,
  `AndroidClockClient`, `AndroidIdClient`, `AndroidDiagnosticsClient`,
  `AndroidLifecycleClient`, and the shared envelope/result/evidence/error mapper.
  `AndroidPlatformRuntime` is the Android composition root for T031.
- **T028 consumer correction**: the simulated store now persists the supplied
  document identity and initial revision, rejects a duplicate visible aggregate, and
  completes the import-created staged aggregate. Direct T028 tests were updated.
- **T031 prerequisite**: `store.startupRecovery` and
  `AndroidPlatformRuntime.runStartupRecovery()` are available. T031 must call the
  native recovery before its Dart `StartupSweep.run()`; the native sweep is not
  duplicated in Dart and is not auto-run out of order here.

## 2. Contract changes and explicit boundaries

- `contracts/platform-channel.md` records the previously approved
  `store.createDocument` request/response and adds the T027/T031 bridge methods
  `store.stageSource` and `store.startupRecovery` (both synchronous).
- `store.createDocument` requires source integrity `verified`; an unreadable source is
  rejected before visibility.
- **Unresolved template channel payload**: `store.createTemplate`,
  `store.saveTemplateVersion`, and `store.loadTemplate` still have only `{…}` in
  `contracts/platform-channel.md` §4. The Dart methods therefore fail closed with
  `PLT-001` (`UnsupportedOperationException`) rather than inventing a second wire
  contract. No template capability is claimed.
- **OCR page-size seam**: `contracts/ports.md` §2.3 does not carry the source-page size,
  while §5 of the channel contract requires `pageWidthPt`/`pageHeightPt`.
  `AndroidOcrClient` takes an explicit `OcrPageSizeResolver`; without it the client
  fails closed. The production raster/OCR composition must supply it.
- Import, OCR, PDF export, and delivery native engines belong to their own tasks. Their
  Dart clients are implemented and parse the defined responses, but with no native
  service registered they correctly fail closed with `PLT-001`.

## 3. Exact command provenance and results

All commands were run in this worktree with the workspace-local toolchain copies
(`.dart_tool/t027-work/flutter`, `.gradle-user-home`); no source or lockfile was
rewritten by the toolchain.

### 3.1 `NONE` — analysis, format, Dart host tests

| Command | Result |
| --- | --- |
| `flutter analyze --no-pub` (repo root) | PASS: “No issues found!” |
| `dart format --output=none --set-exit-if-changed packages apps tools` | PASS: 148 files, 0 changed |
| `flutter test` in `packages/feldexa_core` | PASS 461/461 |
| `flutter test` in `packages/feldexa_export` | PASS 56/56 |
| `flutter test` in `packages/feldexa_ports` | PASS 108/108 |
| `flutter test` in `packages/feldexa_adapters_android` | PASS 19/19 |
| `flutter test` in `packages/feldexa_adapters_simulated` | PASS 97/97 |
| `flutter test` in `packages/feldexa_ui` | PASS 17/17 |
| `flutter test` in `packages/feldexa_testkit` | PASS 154/154 |
| `flutter test` in `apps/feldexa_app` | PASS 80/80 |
| `./gradlew :app:testDebugUnitTest` | PASS 228/228 JVM tests, 0 failures |

`feldexa_recognition` and `feldexa_application` have no test directory in this
candidate; the runner reports “no test files” rather than a failure. That is unchanged
by T027 and is not counted as evidence.

The T027 native service has 7 dedicated JVM tests
(`de.feldexa.app.storage.StoreServiceTest`): stage/create/load/list/save with identity,
head, source and metadata; duplicate create; source-hash mismatch; parented initial
revision; expected-head mismatch; wrong delete title; startup recovery reachability.

### 3.2 `EMULATOR` — Pixel 7 / API 35

- AVD: `T025_Pixel7_API35_KVM_20261115`
  (`config.ini`: `hw.device.name=pixel_7`, `image.sysdir.1=system-images/android-35/google_apis/x86_64/`,
  `abi.type=x86_64`, `tag.id=google_apis`, `PlayStore.enabled=no`).
- Guest: `ro.product.model=sdk_gphone64_x86_64`, `ro.build.version.sdk=35`,
  `ro.build.version.release=15`, `ro.boot.qemu.avd_name=T025_Pixel7_API35_KVM_20261115`,
  `sys.boot_completed=1`, `init.svc.bootanim=stopped`.
- Orca session: no active device before attach; `orca emulator list --worktree all`
  returned `sessions: []`; `attach` succeeded and assigned `emulator-5554` to this
  worktree only. No phone and no unrelated AVD was touched.
- KVM: the AVD is the KVM-provisioned T025 profile and prior T025/T026 EMULATOR
  evidence on the same AVD records hardware acceleration. This DSH sandbox does not
  expose the host `/dev/kvm` or the host emulator process, so an independent host-side
  `-accel` probe was not possible from inside the task; no TCG/software-fallback boot
  was observed. The claim is limited to the named AVD/session evidence.

| Command | Result |
| --- | --- |
| `:app:connectedDebugAndroidTest` with `FeldexaPluginInstrumentedTest` | PASS 19/19, 0 failures |
| `:app:connectedDebugAndroidTest` with `EncryptedStoreInstrumentedTest,KeystoreServiceInstrumentedTest` | PASS 31/31, 0 failures |
| `flutter test integration_test/t027_store_test.dart -d emulator-5554 --no-pub` | PASS 1/1 |

The integration test is the required real Dart → `MethodChannel` → `FeldexaPlugin` →
`StoreService` → real `EncryptedStore`/`AndroidKeyStore` path. It stages a synthetic
source, creates a document, loads source/revision/head, lists, saves a revision,
verifies the new head, asserts duplicate create and wrong-head save are `SAVE-006` with
the head preserved, reads a recovery stamp, calls native startup recovery, deletes with
the explicit title, and verifies the list entry is gone.

### 3.3 APK identity and bound hashes

| Artifact | Size (bytes) | SHA-256 |
| --- | --- | --- |
| `apps/feldexa_app/build/app/outputs/flutter-apk/app-debug.apk` | 192,496,636 | `8db356c39c37bb5d175ba624ffcb801a3a4674f36e61bbb97b4d17cb025a1b46` |
| `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 233,336,111 | `83d902d8d5c20ceb406e7507b7102c204dbc79e9a8cb1f0b7824ce1daab7ff86` |
| `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 555,786 | `1d0a83b47793cacdb4b80e864b4e66ac389960ab6d41f34effc1f99bac58e11a` |

The final Flutter APK and test APK were reinstalled through Orca; in-guest
`sha256sum` matched exactly (`de.feldexa.app` base APK
`8db356c39c37bb5d175ba624ffcb801a3a4674f36e61bbb97b4d17cb025a1b46`;
`de.feldexa.app.test` base APK
`1d0a83b47793cacdb4b80e864b4e66ac389960ab6d41f34effc1f99bac58e11a`).
Launching `de.feldexa.app` created `files/feldexa_store/{docs,templates,tmp,diagnostics}`
and produced no fatal exception.

Bound evidence hashes (files live under ignored `build/t027-evidence/`):

| File | SHA-256 |
| --- | --- |
| `junit/channel-19-tests.xml` | `270a00881438809c0ab66927e1727deedcf15d2d5524d902856b76c93c201476` |
| `junit/storage-31-tests.xml` | `0b9054c0e607db52acee3ebb3e40f7a0ac611cfd70a765a52fe07f0758857e9d` |
| `gradle-connected-channel-final2.log` | `f96775d4e69b7cec7fb7fc301006037c3c5fc6876b4afea8dc5c38192da0cb5b` |
| `gradle-connected-storage-final2.log` | `85f97ffe1476a3f34fbb3941d3007d3a7e3e68c5b78743bb5cfd3f4d15bad5ea` |
| `gradle-jvm-full-final.log` | `6f4850069b397066a4dae113f1d01b05a145a7daffb93e7b4664423e9be0a26e` |
| `test_logs/integration_store_final2.log` | `de1e606111e58d270a75475d4be6f11c2df8dcb1f0a8b3f70b22a531907df449` |
| `analyze_final.log` | `6c698e115ff18ee78533a8740481006ff336c9208e920463e103a5d46b771102` |
| `format_final.log` | `0c654ab8d38f9b6de3ec5d2deba726b2d7448ffcce2401107fc031ef8448ace3` |

## 4. Source diff

`git diff --stat 15aab0c..5b4c295`: 38 files changed, 4,800 insertions, 45 deletions.
The implementation commit contains the native service/store changes, Dart clients and
tests, T028 consumer corrections, the channel/task contract changes, and the app
dependency/composition changes. `apps/feldexa_app/android/gradlew.bat` remains an
unrelated pre-existing modification and is deliberately not committed.

## 5. Honest limitations

- No `DEVICE` acceptance, release signing, performance claim, push, PR, remote merge,
  or self-review. Two independent read-only Codex reviews and owner approval at the
  exact landing gate remain external.
- Android templates are not part of this completion: their channel payload is still
  unspecified and the client fails closed (`PLT-001`).
- Native import, OCR, PDF export, and delivery services are future task-owned engines.
  Their thin clients are present and fail closed when the service is absent.
- `OcrRequest` still does not carry the source-page size; production composition must
  supply the explicit `OcrPageSizeResolver`.
- The sandbox could not probe host `/dev/kvm`; the emulator claim is bound to the named
  Orca AVD/session and the prior T025/T026 KVM evidence, not to a new host probe.
