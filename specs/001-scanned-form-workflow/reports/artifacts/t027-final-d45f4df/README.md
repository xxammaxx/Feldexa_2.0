# T027 final evidence bundle (`d45f4df`)

This bundle binds the T027 `NONE` and `EMULATOR` evidence to the exact
committed candidate, not to a later report commit.

```text
Task:                 issue #27 / T027
Candidate code commit: d45f4df8ec27a91d141bd2d86df77255f8fc7865
Candidate tree:       22a68776dcbc13ea673d3b20a2822c122777fb86
Base:                 15aab0c55c7e77df0d4c4fe199e89c6661ea3db2
Branch:               xxammaxx/feldexa-t027
Runtime:              Orca Pixel 7 API 35 KVM AVD
                      T025_Pixel7_API35_KVM_20261115, serial emulator-5554
```

The candidate code was committed **before** the clean build and runtime run.
The reports and this bundle are in a later **docs-only** commit. That later
commit did not rebuild or retest; it only adds evidence. There is deliberately
no self-referential “final build SHA” or final repository SHA in the manifests.

## Contents

| Path | Meaning |
| --- | --- |
| `manifest.json` | Machine-readable candidate/tree/base, source and generated-config manifest hashes, APK hashes/sizes, test counts, artifact hashes, and limitations |
| `final-artifacts-final.txt` | Flat human-readable binding manifest |
| `source-sha256.txt` | SHA-256 of all 276 tracked source/test/input files under `apps/`, `packages/`, root `pubspec.yaml`/`pubspec.lock`, and the T027 contracts; identical before and after the run |
| `generated-config-sha256.txt` | `local.properties`, `.flutter-plugins-dependencies`, `.dart_tool/package_config.json`, and `GeneratedPluginRegistrant.java`; identical before and after the run |
| `toolchain.txt` | Flutter/Dart, Gradle wrapper, JDK, Android SDK, wrapper jar, and initial guest data |
| `apk-sha256.txt` | Exact local APK bytes (APKs themselves are not committed) |
| `junit/channel-19-tests.xml` | Real channel/Keystore instrumentation: 19 tests, 0 failures, 0 errors |
| `junit/storage-31-tests.xml` | Real T025/T026 storage/Keystore instrumentation: 31 tests, 0 failures, 0 errors |
| `junit/jvm/` | 11 JVM XML files, 233 tests, 0 failures, 0 errors |
| `logs/` | Build, JVM, connected-test, Dart-integration, host-suite, format/analyze, install-hash, and filtered logcat evidence |

Committed logs are path-redacted copies of the raw local logs (home paths
replaced by `<HOME>`/`<REPO>`/`<T026_WORK>`); their committed hashes are the
ones in `manifest.json`. JUnit XML is unmodified. The raw local logs remain
under `build/t027-evidence-final/logs/`.

The APKs are local, git-ignored build outputs; the committed hashes bind them:

```text
c4d0b2258ad3dba9de570552b16ae160ade9530925c01f22f1aa326547c64dd0  app-debug.apk
555171ca8ff0d4f0e63fe1717ab7b6e7362d95948b43fa615020ee197faa5431  app-debug-androidTest.apk
41df822b4c61a99659452f64bc1e0e230fe8bb4c562b9b04eb2e7636349d2d10  app-debug-integration.apk
```

Installed `pm path` + in-guest `sha256sum` checks matched those exact bytes
before the tests, for the integration harness, and for the final restored
app/test packages. The integration harness was removed by `flutter test`
teardown; the standalone app and test APKs were then reinstalled and rehashed.

## Verify

From the repository root:

```sh
bash specs/001-scanned-form-workflow/reports/artifacts/t027-final-d45f4df/verify.sh
```

The script checks `HEAD` and `sha256sum -c source-sha256.txt`. If the local
`build/t027-evidence-final/apks/` outputs still exist, it also checks the APK
hashes.

## Boundaries

- `NONE` host checks and `EMULATOR` runtime evidence are separate; this bundle
  does not claim `DEVICE`, physical-silicon, release-heap, performance, full
  UI/T031/product, export-artifact, or OCR-quality acceptance.
- The named AVD is the KVM-provisioned T025 profile, but this DSH sandbox does
  not expose host `/dev/kvm` or the host emulator process; no fresh host KVM
  probe exists and no TCG fallback was observed. Prior T025/T026 evidence on
  the same AVD supplies the KVM history.
- Template channel payloads remain fail-closed (`PLT-001`); native
  import/OCR/export/delivery engines are future tasks.
- This is author evidence. Independent Review A and Review B must revalidate
  the exact `d45f4df` candidate. No push, PR, remote merge, or self-review was
  performed.
