# T027 final Android store `EMULATOR` evidence

**Class**: `EMULATOR` | **Result**: `PASS`
**Date**: 2026-11-16 (Europe/Berlin)
**Task**: issue #27 / T027
**Base**: `origin/main` `15aab0c55c7e77df0d4c4fe199e89c6661ea3db2`
**Candidate code commit**: `d45f4df8ec27a91d141bd2d86df77255f8fc7865`
**Candidate tree**: `22a68776dcbc13ea673d3b20a2822c122777fb86`
**Branch**: `xxammaxx/feldexa-t027`
**Superseded reports**: [2026-11-16-t027-emulator-store-evidence.md](./2026-11-16-t027-emulator-store-evidence.md)
and [2026-11-16-t027-host-evidence.md](./2026-11-16-t027-host-evidence.md)
**Host support report**: [2026-11-16-t027-host-evidence-final.md](./2026-11-16-t027-host-evidence-final.md)
(`NONE`; not aggregated with this runtime result)

This report proves Android-runtime behavior only for the exclusively allocated
Pixel 7 API 35 AVD below. It does not claim `DEVICE`, physical-silicon key
strength, release-heap, performance, full UI/T031/product behavior, or
physical-device acceptance. The code correction was committed **before** this
build and run; the report itself is in a later docs-only commit.

## 1. Environment and exclusive allocation

```text
EMULATOR: Pixel 7 API 35, exclusive Orca allocation
          T025_Pixel7_API35_KVM_20261115
          serial emulator-5554
          system image android-35/google_apis/x86_64
          RAM 3072 MB; 2 vCPU; x86_64
          AVD PlayStore.enabled=no
          guest model sdk_gphone64_x86_64
          ro.build.version.sdk=35, ro.build.version.release=15
          ro.boot.qemu.avd_name=T025_Pixel7_API35_KVM_20261115
          ro.kernel.qemu=1, ro.boot.qemu=1
          sys.boot_completed=1, init.svc.bootanim=stopped
```

Allocation checks before attach:

- `orca emulator list --worktree all --json` returned `sessions: []`;
- `orca emulator devices` listed `T025_Pixel7_API35_KVM_20261115` as
  `shutdown` and no session owned it;
- `adb devices -l` listed no device.

`orca emulator attach T025_Pixel7_API35_KVM_20261115 --json` returned
`attached: true`, `deviceUdid: emulator-5554`. After attach, `orca emulator
list --worktree all --json` showed exactly one session bound to this worktree
and `adb devices -l` showed exactly one `emulator-5554` device. No phone,
physical device, or unrelated AVD was used. The guest was fully booted before
any test.

**KVM limitation.** The AVD is the named, KVM-provisioned T025 profile and
prior T025/T026 `EMULATOR` runs on this same AVD recorded KVM/open KVM
device-node evidence. This DSH sandbox does not expose host `/dev/kvm` or the
host emulator process, so a new host `-accel`/`/dev/kvm` probe was
`UNAVAILABLE`; no TCG/software-fallback boot was observed. The KVM statement is
therefore limited to the named AVD/session and prior evidence, not a fresh
host-probe result.

## 2. What ran and what it proves

### 2.1 Native channel and real Keystore instrumentation

`FeldexaPluginInstrumentedTest.realStoreServiceCreatesSavesLoadsListsAndPreservesState`
attaches the real `FeldexaPlugin` to an in-process `FlutterEngine`/
`BinaryMessenger`, registers the real `StoreService` over a unique
`EncryptedStore` root and `KeystoreService.forAndroid`, and drives the real
`MethodChannel`/`StandardMethodCodec` boundary. It stages a synthetic source,
creates a document, lists, loads meta/revision/head, reads the decrypted source,
saves a revision through the start/result protocol, verifies the new head,
rejects duplicate create and wrong-head save with `SAVE-006` while preserving
the head, writes a signature, rejects a second write for the same asset id
with `PLT-002` while preserving the prior bytes/head, checks `PLT-002` on a
wrong delete title, deletes with the exact title, and verifies the alias is
gone. The revision content includes a native canonical-JSON probe
`1.0000000000000002e-7`.

Command (working directory `apps/feldexa_app/android`, `ANDROID_SERIAL=emulator-5554`):

```text
./gradlew :app:connectedDebugAndroidTest --offline --no-daemon --console=plain \
  -Pkotlin.compiler.execution.strategy=in-process \
  -Pandroid.testInstrumentationRunnerArguments.class=de.feldexa.app.FeldexaPluginInstrumentedTest
```

Result: `PASS` 19/19 tests, 0 failures, 0 errors.

The real-Keystore storage regression (`EncryptedStoreInstrumentedTest` and
`KeystoreServiceInstrumentedTest`) was run with the same runner and serial:

```text
./gradlew :app:connectedDebugAndroidTest --offline --no-daemon --console=plain \
  -Pkotlin.compiler.execution.strategy=in-process \
  -Pandroid.testInstrumentationRunnerArguments.class=de.feldexa.app.storage.EncryptedStoreInstrumentedTest,de.feldexa.app.storage.KeystoreServiceInstrumentedTest
```

Result: `PASS` 31/31 tests, 0 failures, 0 errors. This preserves the T025/T026
real `AndroidKeyStore` coverage after the T027 corrections.

The first connected-test attempt (before the pinned UTP runner was cached)
failed offline only with “No cached version of
`com.android.tools.utp:android-test-plugin-host-additional-test-output:32.1.0`”.
The pinned artifact was resolved once and both final connected runs above
executed offline.

### 2.2 Real Dart → MethodChannel → native/Keystore journey

`apps/feldexa_app/integration_test/t027_store_test.dart` runs in the app process
with the production `MainActivity` registration and uses `AndroidStoreClient`
from the adapter package. It stages a synthetic source, creates a document with
the approved `CreateDocumentRequest`, loads source/content/head, lists the
committed `StoredMeta`, saves a revision, verifies the head, asserts duplicate
create and wrong-head save are `SAVE-006` with the head unchanged, reads
`recoveryStamp`, writes/reads a synthetic signature, rejects a duplicate
signature asset with `PLT-002` while preserving the prior bytes/head, calls
`runStartupRecovery`, deletes with the explicit title, and verifies the list no
longer contains the document. The revision contains an unknown-field canonical
probe `1.0000000000000002e-7`; the test reads it back and checks the native
receipt/head hash against Dart `canonicalJsonBytes`.

Command (working directory `apps/feldexa_app`):

```text
flutter test integration_test/t027_store_test.dart -d emulator-5554 --no-pub
```

Result: `PASS` 1/1 test, 0 failures. Flutter installed the integration-harness
APK, ran the journey, and removed it during teardown. The exact local harness
hash is recorded below.

## 3. APK identity and installed in-guest hashes

| Artifact | Bytes | SHA-256 |
| --- | --- | --- |
| `build/t027-evidence-final/apks/app-debug.apk` (standalone debug) | 240,765,509 | `c4d0b2258ad3dba9de570552b16ae160ade9530925c01f22f1aa326547c64dd0` |
| `build/t027-evidence-final/apks/app-debug-androidTest.apk` | 115,548 | `555171ca8ff0d4f0e63fe1717ab7b6e7362d95948b43fa615020ee197faa5431` |
| `build/t027-evidence-final/apks/app-debug-integration.apk` (journey harness) | 217,937,973 | `41df822b4c61a99659452f64bc1e0e230fe8bb4c562b9b04eb2e7636349d2d10` |

In-guest `pm path` + `sha256sum` checks:

| Phase | Package | In-guest SHA-256 | Match |
| --- | --- | --- | --- |
| before tests | `de.feldexa.app` | `c4d0b2258ad3dba9de570552b16ae160ade9530925c01f22f1aa326547c64dd0` | exact |
| before tests | `de.feldexa.app.test` | `555171ca8ff0d4f0e63fe1717ab7b6e7362d95948b43fa615020ee197faa5431` | exact |
| integration harness | `de.feldexa.app` | `41df822b4c61a99659452f64bc1e0e230fe8bb4c562b9b04eb2e7636349d2d10` | exact |
| final restore | `de.feldexa.app` | `c4d0b2258ad3dba9de570552b16ae160ade9530925c01f22f1aa326547c64dd0` | exact |
| final restore | `de.feldexa.app.test` | `555171ca8ff0d4f0e63fe1717ab7b6e7362d95948b43fa615020ee197faa5431` | exact |

The AVD already held packages signed by an older debug key. They were
uninstalled before installing the exact APKs; the old packages were synthetic
T027 app/test data only. After the integration harness was removed by Flutter,
the standalone app and test APKs were reinstalled from the evidence directory
and the in-guest hashes matched exactly.

## 4. Bound test evidence

| Artifact | Bytes | SHA-256 |
| --- | --- | --- |
| `junit/channel-19-tests.xml` (19 tests, 0 failures, 0 errors) | 3,430 | `ea6eaa127ae8eef36139938f020c4853e5416e7d77703143859d05273a788ffb` |
| `junit/storage-31-tests.xml` (31 tests, 0 failures, 0 errors) | 5,539 | `1e662a19f38de176a52e2829ca5e427a09f850d203ba31f2163a7790074160fd` |
| `logs/gradle-connected-channel.log` | 23,494 | `4041f91ec8a725c27cac8eb2fcc4668744b8b1983a404085c0cba2f6e67f515f` |
| `logs/gradle-connected-storage.log` | 23,407 | `617dc234eabb83a20cc6a0d7e77eeecf4f7696dd103f3d6074adc98a4e98f3e2` |
| `logs/integration-store.log` | 6,983 | `34c7da6c14294b6e1e7054b6eb25434f0bb09d1aa2ac3e2e42c151bc83a175d8` |
| `logs/installed-hashes-before-tests.log` | 770 | `98ee07c5cb7f9965f1e146e0a8c57797606518f1570c961ae464feb82466e6a5` |
| `logs/installed-hashes-after-integration.log` | 585 | `b088ed38eaa2477233b8d89752e3754fe6a6fc024f6e0cf1679b49b109924ede` |
| `logs/installed-hashes-final.log` | 562 | `c39eb6ea6324b8c238271e61aaea37f11eba4b186a9ef4e0493d6ca41b2caa0c` |
| `logs/logcat-filtered-after-final.txt` | 322,361 | see `manifest.json` |

Paths are relative to
`specs/001-scanned-form-workflow/reports/artifacts/t027-final-d45f4df/`;
committed logs are path-redacted copies and JUnit XML is unmodified. The raw
APKs remain local, git-ignored build outputs; the committed `apk-sha256.txt`
and `manifest.json` bind their exact bytes.

## 5. Reproducibility

1. Start from `15aab0c`, check out `d45f4df`; the later docs-only commit adds
   only this report and the artifact copies.
2. Ensure the Orca runtime exposes `T025_Pixel7_API35_KVM_20261115` and no
   other session owns it. `orca emulator attach T025_Pixel7_API35_KVM_20261115
   --json`; verify `sys.boot_completed=1`, `init.svc.bootanim=stopped`,
   `ro.boot.qemu.avd_name=T025_Pixel7_API35_KVM_20261115`.
3. Clean generated state (`flutter clean`, `flutter pub get --offline
   --enforce-lockfile`, remove Android build dirs), then run
   `flutter build apk --debug --no-pub` and the Gradle assemble/test commands
   in the host report.
4. Run the three runtime commands in §2.1–§2.2 with
   `ANDROID_SERIAL=emulator-5554`.
5. Install the exact APKs from `build/t027-evidence-final/apks/` and compare
   `pm path` + in-guest `sha256sum` with `apk-sha256.txt`.
6. Cleanup: the integration test deletes its own synthetic aggregate and
   signature; no user data is read or deleted. After evidence capture the
   Orca helper was released with `orca emulator kill`; the AVD definition and
   its synthetic test data remain available for independent revalidation.

## 6. Limitations

- No `DEVICE`, release-build, performance, StrongBox, or physical-silicon
  claim. The KVM acceleration itself is not freshly probed from this sandbox;
  see §1.
- Full UI, T031 startup composition, product behavior, OCR/import quality, and
  export-artifact behavior remain unproven by T027.
- Android template channel operations remain fail-closed (`PLT-001`) because
  their payload is still unspecified; native import/OCR/export/delivery engines
  are future tasks. `OcrRequest` still lacks the source-page size, so production
  composition must supply `OcrPageSizeResolver` (accepted seam limitation).
- This is author evidence. Independent Review A and Review B must revalidate the
  exact `d45f4df` candidate; no self-review, push, PR, or remote merge was
  performed.
