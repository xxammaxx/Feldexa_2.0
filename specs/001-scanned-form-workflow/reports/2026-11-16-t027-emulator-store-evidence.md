# T027 Android store `EMULATOR` evidence

> **Historical / superseded 2026-11-16:** This evidence was produced at
> `HEAD=3a3202c` while the T027 code was still the uncommitted change that
> became `5b4c295`. Review B blocked exact committed-source binding, and
> Review A found three defects (signature immutability, raster eviction, and
> canonical-double/parser divergence). The corrected candidate is
> `d45f4df8ec27a91d141bd2d86df77255f8fc7865`; canonical final evidence is
> [2026-11-16-t027-emulator-store-evidence-final.md](./2026-11-16-t027-emulator-store-evidence-final.md)
> with the companion
> [2026-11-16-t027-host-evidence-final.md](./2026-11-16-t027-host-evidence-final.md).
> This file is retained only as history and must not be used for final
> acceptance.

**Class**: `EMULATOR` | **Result**: `PASS`
**Date**: 2026-11-16 (Europe/Berlin)
**Task**: issue #27 / T027
**Base**: `origin/main` `15aab0c55c7e77df0d4c4fe199e89c6661ea3db2`
**Candidate code commit**: `5b4c295014bf63bb7f673fc492e40c8bdfe4ddee`
**Merge commit**: `3a3202cc6ad73fa6303587b185be818e4cbbc0ac`
**Branch**: `xxammaxx/feldexa-t027`
**Host support report**: [2026-11-16-t027-host-evidence.md](./2026-11-16-t027-host-evidence.md)
(`NONE`; not aggregated with this runtime result)

This report proves Android-runtime behavior only for the Pixel 7 API 35 AVD below.
It does not claim `DEVICE`, physical-silicon key strength, release-heap, performance,
or physical-device acceptance.

## 1. Environment

```text
EMULATOR: Pixel 7 API 35, exclusive allocation T025_Pixel7_API35_KVM_20261115;
          system image android-35/google_apis/x86_64; RAM 3072 MB; 2 vCPU;
          APK apps/feldexa_app/build/app/outputs/flutter-apk/app-debug.apk
          SHA-256 8db356c39c37bb5d175ba624ffcb801a3a4674f36e61bbb97b4d17cb025a1b46;
          build mode debug; flags: Flutter debug, android.newDsl=false,
          android.builtInKotlin=false; test APK
          SHA-256 1d0a83b47793cacdb4b80e864b4e66ac389960ab6d41f34effc1f99bac58e11a
```

- AVD config: `hw.device.name=pixel_7`, `hw.device.manufacturer=Google`,
  `image.sysdir.1=system-images/android-35/google_apis/x86_64/`, `abi.type=x86_64`,
  `tag.id=google_apis`, `PlayStore.enabled=no`, `hw.ramSize=3072`,
  `hw.cpu.ncore=2`.
- Guest: `ro.product.model=sdk_gphone64_x86_64`, `ro.build.version.sdk=35`,
  `ro.build.version.release=15`, `ro.boot.qemu.avd_name=T025_Pixel7_API35_KVM_20261115`,
  `sys.boot_completed=1`, `init.svc.bootanim=stopped`.
- Allocation: `orca emulator list --worktree all` returned `sessions: []` before
  attach; `attach T025_Pixel7_API35_KVM_20261115` succeeded and assigned
  `emulator-5554` to this worktree only. One Orca session and one adb device were
  observed. No phone or unrelated AVD was used.
- KVM: the AVD is the KVM-provisioned T025 profile, and prior T025/T026 `EMULATOR`
  runs on the same AVD recorded `kvm-clock`/open KVM device-node evidence. This DSH
  sandbox does not expose host `/dev/kvm` or the host emulator process, so a new host
  `-accel` probe was `UNAVAILABLE`; no TCG/software-fallback boot was observed. The
  KVM statement is limited to the named AVD/session and prior evidence.

## 2. What ran and what it proves

### 2.1 Native channel/real Keystore E2E

`apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/FeldexaPluginInstrumentedTest.kt`
now contains `realStoreServiceCreatesSavesLoadsListsAndPreservesState`. It attaches
the real `FeldexaPlugin` to an in-process `FlutterEngine`/`BinaryMessenger`, registers
the real `StoreService` over a unique `EncryptedStore` root and
`KeystoreService.forAndroid`, and drives the real `MethodChannel`/`StandardMethodCodec`
boundary. The test stages a synthetic source, creates a document, lists, loads
meta/revision/head, reads the decrypted source, saves a revision through the
start/result protocol, verifies the new head, rejects duplicate create and wrong-head
save with `SAVE-006` while preserving the head, checks `PLT-002` on a wrong delete
title, deletes with the exact title, and verifies the alias is gone.

Command (working directory `apps/feldexa_app/android`):
`./gradlew :app:connectedDebugAndroidTest --offline --no-daemon --console=plain -Pkotlin.compiler.execution.strategy=in-process -Pandroid.testInstrumentationRunnerArguments.class=de.feldexa.app.FeldexaPluginInstrumentedTest`
Result: `PASS` 19/19 tests, 0 failures.

### 2.2 Real Dart → MethodChannel → native/Keystore journey

`apps/feldexa_app/integration_test/t027_store_test.dart` runs in the app process with
the production `MainActivity` registration and uses `AndroidStoreClient` from the
adapter package. It stages a synthetic source, creates a document with the approved
`CreateDocumentRequest`, loads source/content/head, lists the committed `StoredMeta`,
saves a revision, verifies the head, asserts duplicate create and wrong-head save are
`SAVE-006` with the head unchanged, reads `recoveryStamp`, calls
`runStartupRecovery`, deletes with the explicit title, and verifies the list no longer
contains the document.

Command (working directory `apps/feldexa_app`):
`flutter test integration_test/t027_store_test.dart -d emulator-5554 --no-pub`
Result: `PASS` 1/1 test.

### 2.3 Real-Keystore storage regression

Command (working directory `apps/feldexa_app/android`):
`./gradlew :app:connectedDebugAndroidTest --offline --no-daemon --console=plain -Pkotlin.compiler.execution.strategy=in-process -Pandroid.testInstrumentationRunnerArguments.class=de.feldexa.app.storage.EncryptedStoreInstrumentedTest,de.feldexa.app.storage.KeystoreServiceInstrumentedTest`
Result: `PASS` 31/31 tests, 0 failures. This preserves the T025/T026 real
`AndroidKeyStore` coverage after the T027 store/channel additions.

## 3. APK identity

| Artifact | Bytes | SHA-256 |
| --- | --- | --- |
| `apps/feldexa_app/build/app/outputs/flutter-apk/app-debug.apk` | 192,496,636 | `8db356c39c37bb5d175ba624ffcb801a3a4674f36e61bbb97b4d17cb025a1b46` |
| `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 233,336,111 | `83d902d8d5c20ceb406e7507b7102c204dbc79e9a8cb1f0b7824ce1daab7ff86` |
| `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 555,786 | `1d0a83b47793cacdb4b80e864b4e66ac389960ab6d41f34effc1f99bac58e11a` |

The final Flutter APK and test APK were reinstalled through Orca and the in-guest
`sha256sum` matched exactly. Launching `de.feldexa.app` created
`files/feldexa_store/{docs,templates,tmp,diagnostics}` and produced no fatal
exception.

## 4. Bound test evidence

| Artifact | Bytes | SHA-256 |
| --- | --- | --- |
| `build/t027-evidence/junit/channel-19-tests.xml` (19 tests, 0 failures) | 3,406 | `270a00881438809c0ab66927e1727deedcf15d2d5524d902856b76c93c201476` |
| `build/t027-evidence/junit/storage-31-tests.xml` (31 tests, 0 failures) | 5,493 | `0b9054c0e607db52acee3ebb3e40f7a0ac611cfd70a765a52fe07f0758857e9d` |
| `build/t027-evidence/gradle-connected-channel-final2.log` | 23,209 | `f96775d4e69b7cec7fb7fc301006037c3c5fc6876b4afea8dc5c38192da0cb5b` |
| `build/t027-evidence/gradle-connected-storage-final2.log` | 23,242 | `85f97ffe1476a3f34fbb3941d3007d3a7e3e68c5b78743bb5cfd3f4d15bad5ea` |
| `build/t027-evidence/test_logs/integration_store_final2.log` | 1,386 | `de1e606111e58d270a75475d4be6f11c2df8dcb1f0a8b3f70b22a531907df449` |

All paths are repository-relative. The logs are git-ignored local, regenerable
support artifacts, not candidate or bundle contents.

## 5. Reproducibility

1. Start from `15aab0c` and check out the candidate `5b4c295` (or final branch head;
   the evidence commit adds docs only).
2. Ensure the Orca runtime exposes the `T025_Pixel7_API35_KVM_20261115` AVD and no
   other session owns it.
3. `orca emulator attach T025_Pixel7_API35_KVM_20261115 --json`; verify
   `sys.boot_completed=1` and `init.svc.bootanim=stopped`.
4. Run the three commands in §2.1–§2.3 with the recorded working directories.
5. Optionally reinstall the APKs in §3 and compare the in-guest `sha256sum`.
6. Cleanup: the integration test deletes its own synthetic aggregate; no user data is
   read or deleted. The emulator helper can be stopped with `orca emulator kill`.

## 6. Limitations

- No `DEVICE`, release-build, performance, StrongBox, or physical-silicon claim.
- KVM acceleration is bound to the named AVD/session and prior T025/T026 evidence;
  the sandbox could not perform an independent host `/dev/kvm`/`-accel` probe.
- Android templates remain fail-closed (`PLT-001`) because their channel payload is
  still unspecified; native import/OCR/export/delivery engines are future tasks.
- `OcrRequest` still lacks the source-page size; production composition must supply
  `OcrPageSizeResolver`.
- No push, PR, remote merge, or self-review. Two independent read-only Codex reviews
  and owner approval at the exact landing gate remain external.

## 7. Review

Author review: not applicable (author evidence). Independent reviewer, date, verdict,
and notes: **blank** — reserved for the two read-only Codex reviews.
