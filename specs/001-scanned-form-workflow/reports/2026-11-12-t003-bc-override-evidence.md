# T003 Follow-up Evidence — BouncyCastle Override and Android Build

- **Repository**: `xxammaxx/Feldexa_2.0`
- **Worktree**: `/home/xxammaxx/Schreibtisch/Feldexa_2.0/feldexa-t003`
- **Task**: T003 / issue #3 (OD-T003-1 resolution)
- **Worker task ID**: `task_f1e45aeda697`
- **Dispatch ID**: `ctx_f8addee62339`
- **Coordinator session**: `orca_session_id:codex_c47f7c54_2eef_4baa_a246_5426e6043cd4`
- **Base revision**: `6a5f705844d661ed882a2233c87f3b39763028b2` (integrated `main`)
- **Date**: 2026-11-12 (Europe/Berlin)
- **Result**: OD-T003-1 resolved with a pinned, OSV-clean BouncyCastle 1.87 override; real Flutter debug and release APKs built; the release merged manifest was corrected to remove ML Kit's DataTransport network permissions and the release APK check passes. No push, merge or self-approval; the exact candidate is a local self-contained commit in `.dsh-git`/`.dsh-t003-candidate.bundle`.

This report is the follow-up to `2026-11-12-t003-evidence.md` and is the authoritative evidence for the Android/BC part of T003. The review is `tools/dependency_review.md`.

## 1. Installed workflow and model evidence

The work continued under the installed DSH `speckit-implement` T003 scope. No new Spec Kit stage, subagent or helper worker was started.

| Item | Observed value |
| --- | --- |
| DSH session ID | `7185afbd-69f9-441e-9d2a-991499db18f3` |
| Provider | `deepseek-official` |
| Model | `deepseek-flash` |
| Reasoning effort | `high` |
| Session metadata | `cwd=/home/xxammaxx/Schreibtisch/Feldexa_2.0/feldexa-t003`, `agentPreset=standard` |
| Session transcript | `/home/xxammaxx/.dsh/sessions/--home-xxammaxx-Schreibtisch-Feldexa_2.0-feldexa-t003--/7185afbd-69f9-441e-9d2a-991499db18f3/session.v4.jsonl.zstd` |

Decoded session header excerpt (sanitised; credentials and message contents omitted):

```json
{"header":{"config":{"provider":"deepseek-official","model":"deepseek-flash","reasoningEffort":"high","maxTokens":256000}}}
```

Session metadata:

```json
{"id":"7185afbd-69f9-441e-9d2a-991499db18f3","createdAt":1794507836195,"cwd":"/home/xxammaxx/Schreibtisch/Feldexa_2.0/feldexa-t003","agentPreset":"standard"}
```

The executing model is therefore `deepseek-flash` via `deepseek-official`.

## 2. Decision: override BouncyCastle to 1.87

`pdfbox-android 2.0.27.0` is the latest published Android port (Maven Central metadata; GitHub release `v2.0.27.0`, 2023-01-02; repository last push 2024-03-18). Its POM pins `bcprov-jdk15to18`, `bcpkix-jdk15to18` and `bcutil-jdk15to18` to `1.72`.

OSV reports 12 advisories for BC 1.72 (10 `bcprov`, 2 `bcpkix`) and **no known advisories** for BC 1.87. Maven Central confirms 1.87 is the latest published line; its POM licence is the Bouncy Castle Licence (MIT-style); the jar manifest reports `Implementation-Version: 1.87.0`; the three local jar SHA-256 values match Maven Central's published `.sha256` files.

### Compatibility / applicability evidence

- PDFBox 2.0.27's only BouncyCastle imports are in `org/apache/pdfbox/pdmodel/encryption/PublicKeySecurityHandler.java` and `SecurityProvider.java` (certificate/public-key-encrypted PDFs, CMS enveloped data). PDFBox does not use BC for ordinary password encryption, text, fonts or flattening in the planned path.
- Feldexa rejects encrypted inputs and does not verify or create signatures; it uses Android Keystore AES-256-GCM for storage. The OSV advisories are **not asserted to be exploitable in Feldexa**. The override is defense-in-depth and removes the flagged version regardless.
- A JVM regression exercised the actual BC path: PDFBox 2.0.27 created a PDF, encrypted it with a self-signed certificate (`PublicKeyProtectionPolicy`), then loaded/decrypted it with the private key. It passed with BC 1.87 and with BC 1.72:
  - `BC_PDFBOX_TEST_OK pages=1 encryptedBytes=1916 decryptedBytes=854 text=Feldexa T003 BC compatibility test`.
- BC 1.87 jars are Java 5+ bytecode (class-file major 49) and the Android `assembleDebug`/dex step succeeded with compileSdk 36/minSdk 26.
- Upstream PDFBox 2.0.37 is not an Android replacement: `jdeps` finds 59 `java.desktop`/AWT references, and Android has no `java.desktop`. No newer `pdfbox-android` release exists. Excluding BouncyCastle would remove classes PDFBox's CMS path references, so the version override is the compatible maintained option.
- Android has no `javax.naming` classes. BC 1.87's manifest treats `javax.naming` imports as optional; PDFBox's CMS path does not use JNDI. The Android build/dex passed; this is a residual optional-class note, not a warm-path failure.

### Implemented pin

`apps/feldexa_app/android/app/build.gradle.kts` now contains:

- `implementation("com.tom-roush:pdfbox-android:2.0.27.0")`.
- Constraints for `bcprov/bcpkix/bcutil-jdk15to18:1.87`.
- A `resolutionStrategy.eachDependency` rule that selects `1.87` for those three modules with the reason recorded in Gradle's `dependencyInsight`.

## 3. Build and test evidence

### 3.1 Scratch Android probe (AGP 9.1.0, compileSdk 36, minSdk 26)

Commands (Gradle 9.3.1, JDK 21, writable Android SDK overlay):

```sh
gradle :app:dependencies --configuration debugRuntimeClasspath
gradle :app:dependencyInsight --dependency bcprov-jdk15to18 --configuration debugRuntimeClasspath
gradle :app:assembleDebug
```

Results:

- `pdfbox-android:2.0.27.0` requested `bcprov/bcpkix/bcutil-jdk15to18:1.72`; Gradle selected `1.87` (`Selected by rule: T003 security pin...` and `By constraint`).
- `assembleDebug` succeeded; debug APK 8.1 MB, SHA-256 `c68967464f88774e42d7c5d4492d63df6e087047e1151682af3948289628bc97`.
- `dexdump` found `Lorg/bouncycastle/cms/CMSEnvelopedData;`, `Lcom/tom_roush/pdfbox/pdmodel/PDDocument;`, and the BC 1.87-only classes `Lorg/bouncycastle/pqc/crypto/sqisign/SQIsignSigner;` and `Lorg/bouncycastle/pqc/crypto/xwing/XWingKEMGenerator;` (both absent from the 1.72 jars).

### 3.2 Real Flutter app build

Command:

```sh
flutter --no-version-check build apk --debug --target-platform android-x64
```

Result: **success**; `✓ Built build/app/outputs/flutter-apk/app-debug.apk`. First full build 246.9 s; final incremental build 36.3 s. Debug APK 118 MB (multi-ABI debug payload), SHA-256 `af79a9a4b6aa044d9da2dfc1c6dd5bdbccd4b4e9e04f0453dc82b097b37e6407`.

Real-app Gradle evidence:

```text
org.bouncycastle:bcprov-jdk15to18:1.72 -> 1.87
  Selection reasons:
    - Selected by rule: T003 security pin: pdfbox-android 2.0.27.0 requests BC 1.72; BC 1.87 is the maintained OSV-clean line
    - By constraint
```

The real APK contains `Lorg/bouncycastle/cms/CMSEnvelopedData;`, `Lcom/tom_roush/pdfbox/pdmodel/PDDocument;`, `Lorg/bouncycastle/pqc/crypto/sqisign/SQIsignSigner;` and `Lorg/bouncycastle/pqc/crypto/xwing/XWingKEMGenerator;` in its DEX.

### 3.3 App tests and analysis

```text
flutter --no-version-check test      -> 4 tests passed
flutter --no-version-check analyze   -> No issues found! (ran in 11.6s)
flutter --no-version-check pub get   -> Changed 75 dependencies
```

## 4. Release merged-manifest privacy finding and correction

The build revealed a pre-existing privacy defect that the source-manifest review had missed:

- `processReleaseMainManifest` initially produced `INTERNET` and `ACCESS_NETWORK_STATE` plus three DataTransport scheduling components (`TransportBackendDiscovery`, `JobInfoSchedulerService`, `AlarmManagerSchedulerBroadcastReceiver`).
- The manifest-merger blame report attributed both permissions and the components to `com.google.android.datatransport:transport-backend-cct:2.3.3`, pulled by `com.google.mlkit:common`/`vision-common`. DataTransport CCT is Google's telemetry transport backend.
- This violates FR-079 and the plan's "release manifest must not request INTERNET" constraint, and it contradicts the earlier "no telemetry" assumption.

Correction: added `apps/feldexa_app/android/app/src/release/AndroidManifest.xml` (release-only) with `tools:node="remove"` for `INTERNET`, `ACCESS_NETWORK_STATE`, and the three DataTransport components. This keeps debug/profile `INTERNET` for Flutter tooling.

Verification:

```text
Before fix (release merged manifest): INTERNET + ACCESS_NETWORK_STATE + 3 DataTransport components
After fix (release merged manifest):  only de.feldexa.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
                                      no INTERNET, no ACCESS_NETWORK_STATE, no DataTransport components
Release merged manifest SHA-256:      6129b31211489284e4d96d48305685c88bed21c57d9de8a8182c899b3d93285c
Debug merged manifest SHA-256:        0c59e366fe8b9ebde03a5aacdfb0d0f1de7abe0337655cb3d341b328c05f2e5e
                                      (debug retains INTERNET for the Flutter tool)
```

DataTransport classes remain on the classpath (removing them could break ML Kit logging classes); without permissions/components they cannot open a socket or schedule a network job. T056 must prove bundled ML Kit OCR with radios disabled and no sockets after this removal (C-T003-1). The automated merged-manifest check is implemented at `tools/android/check_release_manifest.sh`; wiring it into the local gate remains C-T003-11.

## 5. Toolchain notes

- Flutter 3.47.7 / Dart 3.13.5.
- Gradle 9.3.1 / AGP 9.1.0 / Kotlin 2.4.0.
- Gradle must run on **JDK 21 (JBR 21.0.11)**. The default OpenJDK 27 fails the Flutter Gradle plugin's Groovy build scripts with `Unsupported class file major version 71`. The app compile target remains Java 17. This is an environment finding for T002/T024.
- The Android SDK is read-only; a workspace overlay was used and `platforms;android-34` installed there for the `printing` plugin. The repo's SDK config is unchanged.
- The Flutter SDK is read-only; the build used a workspace mirror with a writable `bin/cache` and a writable copy of `packages/flutter_tools/gradle` (the include build needs a writable `.gradle`). The installed SDK was not modified.

## 6. Exact local candidate

Base revision: `6a5f705844d661ed882a2233c87f3b39763028b2`. The shared worktree git metadata is read-only, so the candidate is prepared in a self-contained `.dsh-git` repository (alternates to the shared object store) and exported as `.dsh-t003-candidate.bundle`; the exact candidate commit/tree and bundle hashes are in `.dsh-git/T003-CANDIDATE-EVIDENCE.md` and the worker_done message. No push or merge.

| File | Change | SHA-256 |
| --- | --- | --- |
| `apps/feldexa_app/pubspec.yaml` | Exact Dart pins from T003 | `3fc7f2a408b7ae481fbbb5d46c395e5244613934b4bbd8a80d56baea8f0d4aa7` |
| `pubspec.lock` | Regenerated lockfile | `00a5b9fbc59e6038a1a93fd4cd2c24244f63dffa99b0b44a12f7e8f0d1a21163` |
| `apps/feldexa_app/android/app/build.gradle.kts` | PDFBox pin + BC 1.87 constraint/rule | `6f59795de7cdf2c69253034198280f92bb96a0d6e02322ac83d3245e37d4c8db` |
| `apps/feldexa_app/android/app/src/release/AndroidManifest.xml` | Release-only DataTransport permission/service removal | `d0e486133dde1eed950bb3064766aae6c0e09dae4cc356892158a7af1cbc15fc` |
| `apps/feldexa_app/android/app/proguard-rules.pro` | Exactly the eight AGP-generated `-dontwarn` rules for optional compile-only non-Latin ML Kit classes | `76cab1040628705c1ee6e231ed1d772987c57364d8d39017f053d33df9629b0b` |
| `tools/android/check_release_manifest.sh` | Automated release-manifest privacy check (self-test + merged manifest/APK modes) | `7056eb42198e05a56256b404b8edd103081ec0b8037a77e1de1e24a1112da9f1` |
| `tools/dependency_review.md` | Review updated with BC resolution, build evidence, DataTransport correction, release build and check | `13a80f17dce751dfa5ee4764cf0c11ff0cc1b2a6aca853f515cf08e55df911e4` |
| `specs/001-scanned-form-workflow/tasks.md` | T003 checkbox `[x]`; no other task changed | `286784a9ae3e9a2d420ee5967f62b8e7600edc4fc92ab080811f2c6e67787d69` |
| `specs/001-scanned-form-workflow/reports/2026-11-12-t003-evidence.md` | Prior T003 execution report; historical follow-up note added | `9dfa965c384977f8635e7f8ac63b489befd78b4807cf0989af05d745c2aec15f` |
| `specs/001-scanned-form-workflow/reports/2026-11-12-t003-bc-override-evidence.md` | This report | `—` (self hash omitted) |

Candidate content fingerprint (SHA-256 of the eight sorted `path:sha256` lines for pubspec, lock, Gradle, release manifest, ProGuard rules, manifest-check script, review and tasks): `80e9fc66bde9f4a2f93d4fcb00d7460dcc13eef7a304f4bac1fb5308320d9e1c`. The same value is recorded in `.dsh-git/T003-CANDIDATE-EVIDENCE.md` after the candidate is frozen.

Working-tree status at the time of writing: `M apps/feldexa_app/android/app/build.gradle.kts`, `M apps/feldexa_app/android/gradlew.bat` (pre-existing, not T003), `M apps/feldexa_app/pubspec.yaml`, `M pubspec.lock`, `M specs/001-scanned-form-workflow/tasks.md`, `?? apps/feldexa_app/android/app/proguard-rules.pro`, `?? apps/feldexa_app/android/app/src/release/`, `?? tools/android/check_release_manifest.sh`, `?? tools/dependency_review.md`, `?? specs/001-scanned-form-workflow/reports/2026-11-12-t003-evidence.md`, `?? specs/001-scanned-form-workflow/reports/2026-11-12-t003-bc-override-evidence.md`. Temporary `.tmp-t003bc/`, `.tmp-t003fix/`, `.dsh-git/` and `.dsh-t003-candidate.bundle` are outside the candidate source tree.

## 7. Pre-existing `gradlew.bat` line-ending issue

Preserved byte-for-byte; not staged, restored, renormalized or discarded:

```text
HEAD blob:                 aec99730b4e8fcd90b57a0e8e01544fea7c31a89
index blob:                aec99730b4e8fcd90b57a0e8e01544fea7c31a89
worktree raw hash:         aec99730b4e8fcd90b57a0e8e01544fea7c31a89
worktree filtered hash:    8a0b282aa6885fb573c106b3551f7275c5f17e8e
git diff --numstat:        90  90  apps/feldexa_app/android/gradlew.bat
git diff --ignore-space-at-eol --stat: (empty)
cmp(index blob, worktree): 0
.gitattributes:            *.bat text eol=crlf whitespace=cr-at-eol
```

The committed/index blob is CRLF; the `text` attribute makes `git diff` compare a clean-filtered LF view against the CRLF index, so all 90 lines appear changed although the raw worktree bytes are identical (`cmp` 0). The correct maintenance fix is a one-time `git add --renormalize -- apps/feldexa_app/android/gradlew.bat` commit; T003 does not perform it.

## 8. Release build and manifest regression check

### 8.1 Root cause and minimal fix

The wrapper's `android/build.gradle` declares `com.google.mlkit:text-recognition:16.0.1` (Latin) as `implementation` and the Chinese/Devanagari/Japanese/Korean artifacts as `compileOnly`. Its Kotlin `TextRecognizer.initialize` switches on the script index (0 = Latin, 1–4 = optional scripts); the Dart API defaults to `TextRecognitionScript.latin`. The plugin README and the official ML Kit Text Recognition v2 documentation say the base Android package bundles Latin only and that the other scripts are separate implementation dependencies (about 4 MB per script per architecture), to be added only if needed. Feldexa is German/Latin-only.

The smallest safe fix is `apps/feldexa_app/android/app/proguard-rules.pro` with exactly the eight `-dontwarn` rules AGP generated for those optional classes. Flutter's Gradle plugin automatically adds `app/proguard-rules.pro` to the release build when present (`FlutterPlugin.kt` lines 224–226). No language dependency, keep rule, broad wildcard or network permission was added.

### 8.2 Release build result

```sh
flutter --no-version-check build apk --release --target-platform android-x64
```

Result: **success after 526.2 s**; `✓ Built build/app/outputs/flutter-apk/app-release.apk (57.0MB)`. `missing_rules.txt` is absent after the fix.

- APK: 57,015,925 bytes (Flutter reports 57.0 MB), SHA-256 `3a4c4b6d32fcf37404baea71beffe6836983835c1a3bdd8ccfef1bc5e6346cdc`.
- Three ABI payloads: arm64-v8a, armeabi-v7a, x86_64. This is below the plan's 120 MB release budget for this artifact.
- `apksigner verify --print-certs`: `DOES NOT VERIFY`, `ERROR: Missing META-INF/MANIFEST.MF` — the release artifact is unsigned, as T002 intentionally configures no production signing identity. Production signing remains an owner-supplied release step.

### 8.3 APK and manifest inspection

- Release merged manifest: `apps/feldexa_app/build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml`, SHA-256 `6129b31211489284e4d96d48305685c88bed21c57d9de8a8182c899b3d93285c`. It contains only `de.feldexa.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`; no `INTERNET`, no `ACCESS_NETWORK_STATE`, no DataTransport component.
- `tools/android/check_release_manifest.sh`:
  - `--self-test` → `SELF-TEST PASS: clean manifest accepted; INTERNET, ACCESS_NETWORK_STATE and DataTransport manifests rejected.`
  - release merged manifest → `PASS`.
  - release APK → `PASS`.
- APK DEX audit: the optional non-Latin option classes are **referenced** (`C r`, e.g. `ChineseTextRecognizerOptions$Builder`) but **not defined** (`C d` absent); the wrapper's non-Latin branches are not used. The Latin ML Kit model assets and `libmlkit_google_ocr_pipeline.so` are present. R8 strips the currently unused PDFBox/BC classes (`PDDocument`, `CMSEnvelopedData`, `XWingKEMGenerator`, `SQIsignSigner` are not defined in the release APK).
- `flutter test`: 4/4 passed; `flutter analyze`: no issues (14.7 s).

## 9. Residual risk and no self-approval

- PDFBox-Android 2.0.27.0 is old (upstream PDFBox is 2.0.37) and has no newer Android port. BC 1.87 was proven on PDFBox's actual BC path (public-key CMS), not every BC API. T039/T143 must run the full PDFBox regression and re-scan advisories (C-T003-10).
- ML Kit's DataTransport classes remain packaged; release permissions/services are removed. T056 must prove offline OCR after the removal (C-T003-1).
- The release APK is built and its manifest is clean, but it is unsigned; production signing remains an owner-supplied release step (C-T003-9).
- C-T003-12 is resolved for the current wrapper: the exactly eight AGP-generated `-dontwarn` rules are in `apps/feldexa_app/android/app/proguard-rules.pro`, and `missing_rules.txt` is absent. Keep the rules in sync if the wrapper changes; add a non-Latin implementation dependency only if that script is actually needed.
- No push, merge, tag, PR, issue edit/close or self-approval was performed. The local candidate commit exists only in `.dsh-git` and `.dsh-t003-candidate.bundle`. Gate 7 independent review, gate 8 integration and gate 9 convergence remain outside T003.
