# 2026-11-18 EMULATOR — T046 Android import integration (US1/SC-011)

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` |
| Result | `PASS` |
| Task / issue | `T046` / `#46` |
| Date / timezone | `2026-11-18 14:32 Europe/Berlin` |
| Revision | base commit `0ad1b3b4a493d599770609fdde424ecd071d1b8f`; candidate code commit `cddd0dbafb7f498e65c1597371018e0e096c159e` (tree `81fe13903a822074450b1c1219ff1cc1c9219c00`); working tree clean for the run; the report is in a later docs-only commit whose SHA is recorded in the external attestation |
| External attestation | the active `worker_done` transport record for this dispatched worker (role label; raw task/dispatch identifiers withheld per `reports/README.md` §4.2); it records the base and candidate code SHA/tree, checks/counts, report bytes/hash, and limitations. No attestation ref was created |
| Build identity | version `0.1.0+1`; mode `debug`; APK `apps/feldexa_app/build/app/outputs/flutter-apk/app-debug.apk`, 172014914 bytes, SHA-256 `9a14164cad99e77fb28e4dbccc5466612843f0b21585cec6abbfb05b05b4d928`; built and installed by the exact `flutter test` command in §4; no release or release-signing claim |
| Toolchain | Flutter `3.47.7` stable (framework `abaf9c5237`), Dart `3.13.5`; Gradle `9.3.1`, AGP `9.1.0`, Kotlin `2.4.0`, Temurin JDK `17.0.20.1`; Android SDK platform `36`, build-tools `36.0.0`; PDFBox-Android `2.0.27.0`; pdfrx `2.12.0` (PDFium) |
| Input | synthetic fixture catalogue `fixtures-1.0.0` (`sf-001` 2 pages, `sf-002` 5 pages, `sf-003` 5 pages mixed geometry, `sf-004` 1 page, `sf-protected`, `sf-truncated`, `sf-not-a-pdf`); exact device-side SHA-256 values equal the committed catalogue and are recorded in `fixture-sha256.txt`; no real or personal document |

## 1. Scope

This is a real Android-emulator run of the T046 US1 Independent Test
(`spec.md` US1; SC-011; FR-004, FR-095, FR-096, FR-009) through the production
import pipeline on the exclusively allocated device described in §3:

- `AndroidImportClient` → `import.pickAndImport` → native `ImportService` →
  streaming encrypted staging → real `PdfPreflight` → verified commit →
  `ImportErrorMapper`/`ImportFlow` → `AndroidStoreClient` read-back.
- Single-page (`sf-004`) and five-page (`sf-002`) synthetic PDFs: page count,
  document order, rotation, MediaBox/CropBox-derived display size, source
  integrity, protected-copy read-back after the picked source is deleted, and
  exact PDFium pixel equality between the original fixture bytes and the
  decrypted protected copy.
- Mixed-geometry (`sf-003`, rotations 0/0/90/180/270) as an additional
  orientation/dimension probe.
- Protected (`IMP-001`), truncated (`IMP-002`), non-PDF (`IMP-004`),
  unknown-cause (`IMP-005`), and partially damaged (`IMP-006`) behaviour with
  the exact German catalogue text, the FR-009 no-document gate, and an
  unchanged picked source.
- A partially damaged input is created deterministically from committed
  `sf-001`; the one cause that cannot be produced deterministically from a
  crafted PDF (`IMP-005`) uses the declared debug-only seam described in §2.

Host-only checks are reported separately in §4 and are not runtime evidence.

### Spec Kit implementation provenance

- **Command:** `/speckit.implement Implement ONLY task T046 (GitHub issue #46) ...` was invoked through the installed OpenCode `speckit-implement` skill before any code change; the scope argument limited execution to T046. Model/provider: `deepseek/deepseek-flash` (DeepSeek V4.1 Flash 1017).
- **Prerequisite output/exit:** `SPECIFY_FEATURE_DIRECTORY=specs/001-scanned-form-workflow .specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` exited `0` with `FEATURE_DIR=<repo-root>/specs/001-scanned-form-workflow` and `AVAILABLE_DOCS=[research.md, data-model.md, contracts/, quickstart.md, tasks.md]`. The first invocation without `SPECIFY_FEATURE_DIRECTORY` exited `1` with `Feature directory not found. Set SPECIFY_FEATURE_DIRECTORY ...`; the repository `.specify/feature.json` names the same feature, and the corrected invocation above is the recorded prerequisite.
- **Extension hooks:** `.specify/extensions.yml` exists and registers no hooks (`hooks: {}`); no before/after hook was executed.
- **Checklist gate:** `checklists/requirements.md` is 16/16 checked (`PASS`); `checklists/precision-testability.md` has 36 unchecked reviewer-owned markers and is intentionally untouched (the custom checklist gate is therefore `FAIL` as a reviewer gate, not a product or runtime result). The dispatch explicitly scoped T046 and forbade checklist edits, so implementation proceeded on that instruction with no claim of reviewer approval.
- **Task marker:** `tasks.md` was not edited, as required by T046's scope; the T046 checkbox remains reviewer/coordinator-owned.

## 2. Revision and build

The run started from base commit `0ad1b3b4a493d599770609fdde424ecd071d1b8f`
and the candidate code commit `cddd0dbafb7f498e65c1597371018e0e096c159e`
(tree `81fe13903a822074450b1c1219ff1cc1c9219c00`). `git status` was clean at
the final run; the report and its artifact directory were added afterwards in
a docs-only commit. `flutter test` resolved dependencies, ran
`assembleDebug`, and installed `app-debug.apk` from this tree. The APK is a
git-ignored build output; its byte size and SHA-256 are recorded in
`apk-sha256.txt`.

### Declared test-only seam (flagged for independent review)

The real Android `ACTION_OPEN_DOCUMENT` picker cannot be driven from a Flutter
`integration_test`. One minimal, debug-gated seam was added; it does not
replace or change staging, encryption, preflight, commit, rollback, the
German catalogue, or FR-009 semantics:

1. `ImportTestHooks` (new file,
   `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/ImportTestHooks.kt`)
   registers `de.feldexa/test.import` only when the installed application is
   debuggable (`ApplicationInfo.FLAG_DEBUGGABLE`). Release builds never
   register it. The test explicitly arms one local file path with `armFile`
   and clears it with `clear`; nothing is armed by default.
2. `MainActivity` asks the debug-only gate whether a fixture is armed. If yes,
   it delivers a file-backed `PickedDocument` whose `openStream()` opens a
   fresh read-only stream; otherwise it launches the unchanged production SAF
   picker. The native `ImportService` consumes the delivered source through the
   same production `PickedDocument.openStream` seam and the same real
   encryption/preflight/commit path.
3. `PdfPreflight`'s PDFBox loader object changed from `private` to `internal`
   (visibility only, no behaviour change). In debug builds only, the
   `MainActivity` loader wrapper throws a generic `IllegalStateException` when
   the test has armed `forceUnknownPreflight`; the real production
   `PdfPreflight` catch classifies that as `IMP-005`. Release builds construct
   the plain `PdfPreflight()` and cannot take this branch.

`./gradlew :app:compileReleaseKotlin` passes (§4), so the release variant
compiles with the seam inert. The seam is test-only infrastructure and is
flagged for review: it accepts an app-readable path on a debug-only channel
and is not part of production import behaviour.

```diff
diff --git a/apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/MainActivity.kt b/apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/MainActivity.kt
index b5e02fc..f1874dd 100644
--- a/apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/MainActivity.kt
+++ b/apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/MainActivity.kt
@@ -1,6 +1,7 @@
 package de.feldexa.app
 
 import android.content.Intent
+import android.content.pm.ApplicationInfo
 import android.net.Uri
 import android.os.Bundle
 import android.provider.OpenableColumns
@@ -17,6 +18,8 @@ import de.feldexa.app.import.SourceStaging
 import de.feldexa.app.import.StagedCommit
 import de.feldexa.app.import.StagedDiscard
 import de.feldexa.app.import.StagedPreflight
+import de.feldexa.app.pdf.PdfBoxDocumentLoader
+import de.feldexa.app.pdf.PdfDocumentLoader
 import de.feldexa.app.pdf.PdfPreflight
 import de.feldexa.app.storage.AggregateKind
 import de.feldexa.app.storage.DeleteConfirmation
@@ -89,6 +92,10 @@ class MainActivity : FlutterActivity() {
     private lateinit var importPickerLauncher: ActivityResultLauncher<Array<String>>
     private var pendingImportPicker: ((PickedDocument?) -> Unit)? = null
 
+    /** True only for a debug/development build; release is not debuggable. */
+    private fun isDebuggableBuild(): Boolean =
+        (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
+
     /**
      * FlutterActivity is not a ComponentActivity, so it has no
      * `registerForActivityResult`. This registry provides the same
@@ -139,6 +146,15 @@ class MainActivity : FlutterActivity() {
         flutterEngine.plugins.add(plugin)
         plugin.registerImportChannel(flutterEngine.dartExecutor.binaryMessenger)
 
+        // T046: debug-only fixture gate for the import integration test. This
+        // is a declared test seam: the handler exists only in debug builds and
+        // delivers a source only after the test explicitly arms one. Release
+        // builds never register it, and the production import semantics below
+        // are unchanged.
+        if (isDebuggableBuild()) {
+            ImportTestHooks.register(flutterEngine.dartExecutor.binaryMessenger)
+        }
+
         val store = EncryptedStore(
             root = File(filesDir, STORE_ROOT_DIR).absoluteFile,
             keystore = KeystoreService.forAndroid(this),
@@ -151,11 +167,38 @@ class MainActivity : FlutterActivity() {
         // worker. The store streams the encrypted copy, preflight reads the
         // staged ciphertext through a decrypting range reader, and only a
         // verified commit makes the document visible.
-        val pdfPreflight = PdfPreflight()
+        // T046: in debug builds the test may force the real preflight
+        // classifier's synthetic-unknown branch. The loader is otherwise the
+        // production PDFBox loader; release builds construct the plain
+        // PdfPreflight() and cannot reach this branch.
+        val pdfPreflight = if (isDebuggableBuild()) {
+            PdfPreflight(
+                loader = PdfDocumentLoader { stream ->
+                    if (ImportTestHooks.forceUnknownPreflight) {
+                        throw IllegalStateException("t046 synthetic unknown preflight")
+                    }
+                    PdfBoxDocumentLoader.load(stream)
+                },
+            )
+        } else {
+            PdfPreflight()
+        }
         plugin.registerService(
             "import",
             ImportService(
                 picker = DocumentPicker { onResult ->
+                    // T046: a declared debug-only seam for the integration
+                    // test. Without an armed fixture the ordinary system
+                    // picker below is launched exactly as in production.
+                    val armed = if (isDebuggableBuild()) {
+                        ImportTestHooks.takePickedDocument()
+                    } else {
+                        null
+                    }
+                    if (armed != null) {
+                        onResult(armed)
+                        return@DocumentPicker
+                    }
                     runOnUiThread {
                         if (!::importPickerLauncher.isInitialized || pendingImportPicker != null) {
                             // No parallel picker and no result before registration.
diff --git a/apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/pdf/PdfPreflight.kt b/apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/pdf/PdfPreflight.kt
index 4609f67..fc1b3c0 100644
--- a/apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/pdf/PdfPreflight.kt
+++ b/apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/pdf/PdfPreflight.kt
@@ -416,7 +416,7 @@ internal fun interface PdfDocumentLoader {
     fun load(stream: InputStream): PDDocument
 }
 
-private object PdfBoxDocumentLoader : PdfDocumentLoader {
+internal object PdfBoxDocumentLoader : PdfDocumentLoader {
     override fun load(stream: InputStream): PDDocument =
         // Main-memory-only keeps PDFBox's working copy off disk: preflight
         // must not create a plaintext scratch file for a private document.
```

The complete diff, including the new `ImportTestHooks.kt`, is committed as
`specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t046-emulator/seam.diff`
(artifact row in §8).

## 3. Environment

```text
EMULATOR: Pixel 7 API 35, exclusive allocation T046 2026-11-18
          AVD T025_Pixel7_API35_KVM_20261115
          serial emulator-5554
          system image google/sdk_gphone64_x86_64/emu64xa (API 35, userdebug)
          fingerprint google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys
          guest model sdk_gphone64_x86_64; ro.build.version.sdk=35; ro.build.version.release=15
          ro.boot.qemu.avd_name=T025_Pixel7_API35_KVM_20261115
          ro.kernel.qemu=1; ro.boot.qemu=1; sys.boot_completed=1
          4 vCPU; RAM 4096 MB (MemTotal 4014392 kB); 1080x2400 at density 420
          APK apps/feldexa_app/build/app/outputs/flutter-apk/app-debug.apk
          APK SHA-256 9a14164cad99e77fb28e4dbccc5466612843f0b21585cec6abbfb05b05b4d928
          build mode debug
```

Device identity and boot properties are recorded in `device-identity.txt`.
`adb devices -l` showed exactly one Android device, `emulator-5554`, before and
after the run; no other emulator or physical phone was used, and no AVD was
booted, created, wiped, reset, or snapshotted by this task.

**Owner-confirmed observation surface (not agent-verified).** The project
owner confirmed on 2026-11-18 Europe/Berlin that the Orca emulator pane is
visible and showing current frames, the Orca accessibility tree is live, and a
live stream is attached as `scrcpy://emulator-5554`. This owner observation is
the live observation surface for the run; it is not an agent verification and
did not change any assertion or verdict. Every `EMULATOR` result below still
comes only from the real integration-test run on that serial.

**KVM limitation.** The AVD is the named KVM-provisioned Pixel 7 API 35
profile used by earlier T025/T026 `EMULATOR` runs. This sandbox does not expose
the host KVM device node or host emulator process, so no fresh host
acceleration probe was possible; the guest reports the expected QEMU/AVD
properties and boot state. No software-fallback boot was observed. This report
does not claim physical-device or silicon-specific behavior.

## 4. Checks

### 4.1 EMULATOR runtime checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `flutter test integration_test/android_import_test.dart -d emulator-5554` (`apps/feldexa_app`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t046-emulator/integration-android-import.log` | `PASS` |
| 2 | `adb devices -l`; `adb -s emulator-5554 shell getprop`; `adb -s emulator-5554 shell wm size`; `adb -s emulator-5554 shell wm density` (repo root) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t046-emulator/device-identity.txt` | `PASS` |

The runtime command ran with Temurin JDK 17 as `JAVA_HOME` and with Flutter and
Android platform-tools on `PATH`. Fixture staging into the device-local
temporary directory was setup, not a separate test: the exact `adb push` and
`chmod` commands are in the integration-test file header, and the resulting
device-side hashes are recorded in `fixture-sha256.txt`. The integration run
passed 8 of 8 tests with 0 failures: single, five-page, mixed-geometry,
protected, truncated, non-PDF, unknown-cause, and partially damaged. The log
shows `00:09 +8: All tests passed!`.

### 4.2 Host-only checks (`NONE` class; not runtime evidence)

These checks are deliberately separate from §4.1. They do not prove Android
behaviour and are not aggregated with the `EMULATOR` result.

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `flutter analyze --no-pub` (`apps/feldexa_app`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t046-emulator/host-flutter-analyze.log` | `PASS` |
| 2 | `flutter test --no-pub` (`apps/feldexa_app`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t046-emulator/host-flutter-test.log` | `PASS` (244 tests, 0 failures) |
| 3 | `./gradlew :app:compileReleaseKotlin --console=plain` (`apps/feldexa_app/android`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t046-emulator/host-release-compile.log` | `PASS` |
| 4 | `git diff --check` (repo root) | `0` | console only (not retained) | `PASS` |
| 5 | `dart tools/evaluation/validate_report.dart specs/001-scanned-form-workflow/reports/2026-11-18-emulator-t046-evidence.md` (repo root) | `0` | console only (not retained) | `PASS` |

`flutter analyze` reported `No issues found!`. The host test run ended with
`00:34 +244: All tests passed!`; the browser-only fixture test is skipped by
its documented `FIXTURE_RUNTIME` gate and is not counted here. The release
Kotlin compile passed with the seam present but unreachable.

## 5. Results

| Scenario | Input | Observed | Verdict |
| --- | --- | --- | --- |
| Single-page valid import | `sf-004` (1 page, A4 portrait, rotation 0) | `ImportAccepted` with no warning; page count 1; MediaBox 595.28 × 841.89 pt, display size 595.28 × 841.89 pt, rotation 0; picked source bytes and modification time unchanged; source deleted; decrypted stored source SHA-256 equals the fixture; every page rendered byte-identically (PDFium BGRA raster SHA-256) from the original and stored bytes; document deleted after the test | `PASS` |
| Five-page valid import | `sf-002` (5 pages, A4 portrait) | Page count 5 in document order; every page MediaBox/display 595.28 × 841.89 pt, rotation 0; source bytes and modification time unchanged; source deleted; stored source SHA-256 and bytes equal the fixture; all five pages rendered byte-identically from original and stored bytes | `PASS` |
| Mixed geometry (additional) | `sf-003` (5 pages) | Rotations `[0, 0, 90, 180, 270]`; display sizes `[595.28×841.89, 841.89×595.28, 841.89×595.28, 595.28×841.89, 595.28×419.53]` match the catalogue; MediaBox values are unswapped PDF user-space boxes; source unchanged, source deleted, protected copy hash equal, all five pages pixel-identical | `PASS` |
| Protected source | `sf-protected` (RC4 40-bit, non-empty user password) | `ImportRejected` with code `IMP-001`, `passwordProtectionConfirmed == true`, `isUnrecognized == false`; exact German message and recovery guidance asserted against both the literal catalogue text and `AppLocalizations`; create-document callback not called; document-id set in the store unchanged; picked source bytes and modification time unchanged; no password was requested or stored | `PASS` |
| Truncated source | `sf-truncated` (60 % prefix, no xref/EOF) | `ImportRejected` with code `IMP-002`; exact German message/recovery; no password claim (`passwordProtectionConfirmed == false`); no document created; source unchanged | `PASS` |
| Non-PDF source | `sf-not-a-pdf` (UTF-8 text with `.pdf` extension) | `ImportRejected` with code `IMP-004`; exact German message/recovery; no password claim; no document created; source unchanged | `PASS` |
| Unknown cause | valid `sf-004` bytes with the declared debug-only forced loader failure | Production `PdfPreflight` mapped the generic loader failure to `IMP-005`; exact German message/recovery; `isUnrecognized == false` because the native layer reported a mapped `IMP-005` code (the mapper's explicit unmapped-code flag stays false); no password claim; no document created; source unchanged | `PASS` |
| Partially damaged source | deterministic mutation of committed `sf-001`: the second page's MediaBox array is replaced by same-length spaces, preserving all xref offsets | `ImportAccepted` with the `IMP-006` warning for page `2`; exact German warning/recovery; document created; page 1 readable; page 2 marked unreadable with `IMP-006` and the documented 1×1 placeholder; source bytes and modification time unchanged; source deleted; protected-copy read-back succeeded; page 1 rendered byte-identically from original and stored bytes | `PASS` |

**Fidelity actually asserted.** The picked source is compared byte-for-byte
before and after each import; the decrypted protected copy is compared
byte-for-byte with the source and re-hashed; page count, order, rotation,
MediaBox, and display size come from the production preflight and match the
committed catalogue; and for every readable page of `sf-004`, `sf-002`,
`sf-003`, and page 1 of the partial input, the PDFium BGRA raster rendered from
the original bytes is SHA-256-identical to the raster rendered from the
protected copy at the page's display size (72 DPI). The fixtures are synthetic
vector forms, not scanned raster images, so this report makes no scanner
pixel-fidelity claim beyond exact byte identity plus identical PDFium
rendering; it also makes no OCR or visual-acceptance claim.

## 6. Performance

No performance claim.

## 7. Limitations

- No `DEVICE`, release-runtime, physical-silicon, StrongBox, or performance
  claim. KVM acceleration was not freshly probed from this sandbox; see §3.
- The system SAF picker UI itself was not driven. The declared debug-only seam
  replaces only the picker's delivery of a local file-backed source; the
  production `ImportService`, encrypted staging, preflight, commit, cleanup,
  German mapper, and store read-back are the real implementations. No SAF
  content-resolver or picker-result UI claim is made.
- The fixtures are synthetic vector PDFs, and the pixel check compares PDFium
  renders of identical bytes. It proves the protected copy and source render
  identically; it does not prove fidelity against an external scanner or a
  real authority form.
- `IMP-005` cannot be produced deterministically from a crafted PDF across the
  supported PDFBox version. It uses the declared debug-only generic
  `IllegalStateException` loader path; the `IMP-005` classification and German
  presentation are real production code. This is flagged for review.
- The test stages fixtures in a device-local temporary directory outside the
  app sandbox (mode 755/644) so the debug app can read them. Fixtures remain
  undeclared Flutter assets and are not packaged into release builds.
- The debug-only test channel is compiled into debug builds but is registered
  only when the app is debuggable and is inert until explicitly armed. The
  release variant compiles; no release-runtime registration was run.
- This is author evidence. The seam, the test, and the report require
  independent review; no self-approval is claimed.

## 8. Artifacts

All paths are repository-relative and committed with this report unless the
row says otherwise. The APK is a git-ignored local build output bound by
`apk-sha256.txt`; it is not committed.

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `seam.diff` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t046-emulator/seam.diff` | 9714 | `3a0f6834d37a5b8108daf56a5af5ce590663f223e2cf2ed4cf17a736f7044ea3` |
| `apk-sha256.txt` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t046-emulator/apk-sha256.txt` | 310 | `7c72d9b4ead7b353f488392f73ac2b45e5b596f1c6e82818f4c160dee43c7e30` |
| `device-identity.txt` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t046-emulator/device-identity.txt` | 779 | `316d45f40f4089331cc4c7628676615cf400d1b1bd81efb49c9a1710b31ccecd` |
| `fixture-sha256.txt` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t046-emulator/fixture-sha256.txt` | 1008 | `860c6fc7be20eaf154e39367a53d2f5e233403bf43d5e0e0550e24cae3102de7` |
| `host-flutter-analyze.log` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t046-emulator/host-flutter-analyze.log` | 97 | `884d6044564384cd1e7c0469f04bac83ca8f7a7d3ff674ed14e37f737ef92c98` |
| `host-flutter-test.log` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t046-emulator/host-flutter-test.log` | 36722 | `227ac7bd00361f1256833b64d60926ff0e47cd14a1f3d7c7174be1e1b9fd6755` |
| `host-release-compile.log` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t046-emulator/host-release-compile.log` | 15203 | `e47c9306159833bc025ff4d09b6bf6afd11b3dae90df436e3133377be8e60144` |
| `integration-android-import.log` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t046-emulator/integration-android-import.log` | 3291 | `b96325fbc84aab03978e18eefa6c1502b05ea4369172d493a4472812e6b9bff8` |

## 9. Reproducibility

1. Start from base commit `0ad1b3b4a493d599770609fdde424ecd071d1b8f` and check
   out candidate code commit `cddd0dbafb7f498e65c1597371018e0e096c159e`; confirm
   tree `81fe13903a822074450b1c1219ff1cc1c9219c00` and a clean working tree.
2. Use the pre-booted, exclusively allocated `T025_Pixel7_API35_KVM_20261115`
   AVD on serial `emulator-5554`; do not boot, wipe, reset, or snapshot it.
3. Stage the seven committed synthetic PDF fixtures with the `adb push` and
   `chmod` commands in the integration-test file header, then verify the
   device-side hashes against `fixture-sha256.txt`.
4. From `apps/feldexa_app`, with Flutter `3.47.7`, Temurin JDK 17, and Android
   platform-tools on `PATH`, run
   `flutter test integration_test/android_import_test.dart -d emulator-5554`;
   expected `00:09 +8: All tests passed!` and exit `0`.
5. Host-only reproduction: `flutter analyze --no-pub` and
   `flutter test --no-pub` from `apps/feldexa_app`; release seam check:
   `./gradlew :app:compileReleaseKotlin --console=plain` from
   `apps/feldexa_app/android` with `JAVA_HOME` set to Temurin 17.
6. Cleanup: the test deletes every document it creates and the scratch source
   copies it writes; `flutter test` removes the installed app/test packages.
   The AVD definition and staged synthetic fixtures may remain for independent
   revalidation.

## 10. External attestation

The active `worker_done` transport record (role label; raw task/dispatch
identifiers withheld) names the base and candidate code SHA/tree, this file's
byte size and SHA-256, the checks and counts above, and the limitations. No
attestation ref or bundle was created for this task. The report itself is not
part of the candidate code commit and does not assert its own commit SHA.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
