# 2026-11-18 EMULATOR — T048 source integrity after move/delete (US1/SC-019)

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` |
| Result | `PARTIAL` |
| Task / issue | `T048` / `#48` |
| Date / timezone | `2026-11-18 15:20 Europe/Berlin` |
| Revision | base commit `e8c29cf3795e798ed9ce35efc9ac2d5f6ec70bf9`; candidate code commit `4374414273e7b7a74c18c0870bd4a07bfdd003c4` (tree `4eab0570efad290fb1d3008616930623b0e47384`); working tree clean for the run; the report and its artifacts are in a later docs-only commit whose SHA is recorded in the external attestation |
| External attestation | the active `worker_done` transport record for this dispatched worker (role label; raw task/dispatch identifiers withheld per `reports/README.md` §4.2); it records the base and candidate code SHA/tree, checks/counts, report bytes/hash, and limitations. No attestation ref was created |
| Build identity | version `0.1.0+1`; mode `debug`; APK `apps/feldexa_app/build/app/outputs/flutter-apk/app-debug.apk`, 172000078 bytes, SHA-256 `2cebf916987238c25b7107a723fd4e34d50d737e025262ba5b3e573fc5689888`; built and installed by the exact `flutter test` command in §4; no release or release-signing claim |
| Toolchain | Flutter `3.47.7` stable (framework `abaf9c5237`), Dart `3.13.5`; Gradle `9.3.1`, AGP `9.1.0`, Kotlin `2.4.0`, Temurin JDK `17.0.20.1`; Android SDK platform `36`, build-tools `36.0.0`; PDFBox-Android `2.0.27.0`; pdfrx `2.12.0` (PDFium) |
| Input | synthetic fixture catalogue `fixtures-1.0.0` (`sf-001` 2 pages A4 portrait, `sf-003` 5 pages mixed geometry/rotation); exact device-side SHA-256 values equal the committed catalogue and are recorded in `fixture-sha256.txt`; no real or personal document |

## 1. Scope

This is a real Android-emulator run of the T048 source-integrity test
(`spec.md` US1; SC-019; FR-004, FR-095, FR-096) on the exclusively allocated
device described in §3, through the production path:

- `AndroidImportClient` → `import.pickAndImport` → native `ImportService` →
  streaming encrypted staging → real `PdfPreflight` → verified commit →
  `ImportFlow`;
- `AndroidStoreClient.loadDocument` and an explicit `store.readSource` channel
  read of the committed document from the protected internal store;
- `pdfrx` (real PDFium) rendering of the decrypted protected bytes.

The test asserts the SC-019 lifecycle in two independent trials
(`sf-003` mixed geometry and `sf-001` two pages):

1. import the synthetic fixture and record its byte SHA-256, byte length, and
   modification time;
2. assert the picked file was not rewritten in place (bytes, SHA-256, size, and
   modification time unchanged);
3. move the picked file to a different directory, assert the original path is
   gone and the moved file still carries the identical bytes and modification
   time;
4. reopen the saved document from the protected store, read it back through
   `store.readSource`, and render every page with PDFium;
5. delete the moved file, assert no filesystem copy remains, and reopen and
   re-render the document again;
6. exercise the production export surface (`export.validate` and
   `export.render`).

The export clause of SC-019 is **not verified**. The Kotlin `export/`
implementation directory contains only `.gitkeep`, no `export` service is
registered by `MainActivity`, and T104's `PdfExportService.kt` does not exist.
The test therefore asserts that the production facade fails closed with
`PLT-001`/`platform.unsupported` and records that blocker; it does not fake an
export result. This is why the report result is `PARTIAL`.

Host-only checks are reported separately in §4.2 and are not runtime evidence.

### Spec Kit implementation provenance

- **Command:** `/speckit.implement Implement ONLY task T048 (GitHub issue #48)
  ...` was invoked through the installed OpenCode `speckit-implement` skill
  before any code change; the scope argument limited execution to T048.
  Model/provider: `deepseek/deepseek-flash` (DeepSeek V4.1 Flash 1017).
- **Prerequisite output/exit:**
  `SPECIFY_FEATURE_DIRECTORY=specs/001-scanned-form-workflow
  .specify/scripts/bash/check-prerequisites.sh --json --require-tasks
  --include-tasks` exited `0` with `FEATURE_DIR` = the feature directory and
  `AVAILABLE_DOCS = [research.md, data-model.md, contracts/, quickstart.md,
  tasks.md]`. The first invocation without `SPECIFY_FEATURE_DIRECTORY` exited
  `1` with `Feature directory not found`; the corrected invocation above is the
  recorded prerequisite.
- **Extension hooks:** `.specify/extensions.yml` exists and registers no hooks
  (`hooks: {}`); no before/after hook was executed.
- **Checklist gate:** `checklists/requirements.md` is 16/16 checked (`PASS`);
  `checklists/precision-testability.md` has 36 unchecked reviewer-owned
  markers and was intentionally untouched, so the custom checklist gate is
  `FAIL` as a reviewer gate, not a product or runtime result. The dispatch
  explicitly scoped T048 and forbade checklist edits, so implementation
  proceeded on that instruction with no claim of reviewer approval.
- **Task marker:** `tasks.md` was not edited, as required by T048's scope; the
  T048 checkbox remains reviewer/coordinator-owned.

## 2. Revision and build

The run started from base commit `e8c29cf3795e798ed9ce35efc9ac2d5f6ec70bf9`.
The only code change is the new test file
`apps/feldexa_app/integration_test/source_integrity_test.dart`, committed as
`4374414273e7b7a74c18c0870bd4a07bfdd003c4` (tree
`4eab0570efad290fb1d3008616930623b0e47384`). `git status --porcelain` was
empty before the `EMULATOR` run. The report, `README.md` index row, and the
artifact directory are added afterwards in a docs-only commit.

**No production or test seam was added.** The test reuses the T046 declared
debug-only seam unchanged: `ImportTestHooks` (`de.feldexa/test.import`) and
its `FLAG_DEBUGGABLE` gating in `MainActivity`. That seam is unchanged by this
task, is inert in release builds, and was already flagged for review in the
T046 evidence report. Moving and deleting the picked file are ordinary
filesystem operations by the test process on its own synthetic fixture copy;
no production import, storage, or export semantics were modified.

`flutter test` resolved dependencies, ran `assembleDebug`, and installed
`app-debug.apk` from this tree. The APK is a git-ignored build output; its byte
size and SHA-256 are recorded in `apk-sha256.txt`.

## 3. Environment

```text
EMULATOR: Pixel 7 API 35, exclusive allocation T048 2026-11-18
          AVD T025_Pixel7_API35_KVM_20261115
          serial emulator-5554
          system image google/sdk_gphone64_x86_64/emu64xa (API 35, userdebug)
          fingerprint google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys
          guest model sdk_gphone64_x86_64; ro.build.version.sdk=35; ro.build.version.release=15
          ro.boot.qemu.avd_name=T025_Pixel7_API35_KVM_20261115
          ro.kernel.qemu=1; ro.boot.qemu=1; sys.boot_completed=1
          vCPU 2; RAM 4096 MB (MemTotal 4014392 kB); 1080x2400 at density 420
          APK apps/feldexa_app/build/app/outputs/flutter-apk/app-debug.apk
          APK SHA-256 2cebf916987238c25b7107a723fd4e34d50d737e025262ba5b3e573fc5689888
          build mode debug
```

Device identity and boot properties are recorded in `device-identity.txt`.
`adb devices -l` showed exactly one Android device, `emulator-5554`, before and
after the run; no other emulator or physical phone was used, and no AVD was
booted, created, wiped, reset, or snapshotted by this task. The observed guest
`nproc` value was 2; no vCPU or memory value is claimed beyond what the guest
reported.

**KVM limitation.** The AVD is the named KVM-provisioned Pixel 7 API 35
profile used by earlier `EMULATOR` runs. This sandbox does not expose the host
KVM device node or host emulator process, so no fresh host acceleration probe
was possible; the guest reports the expected QEMU/AVD properties and boot
state. No software-fallback boot was observed. This report does not claim
physical-device or silicon-specific behavior.

## 4. Checks

### 4.1 EMULATOR runtime checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `flutter test integration_test/source_integrity_test.dart -d emulator-5554` (`apps/feldexa_app`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t048-emulator/integration-android-source-integrity.log` | `PASS` |
| 2 | `adb devices -l`; `adb -s emulator-5554 shell getprop`; `adb -s emulator-5554 shell wm size`; `adb -s emulator-5554 shell wm density` (repo root) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t048-emulator/device-identity.txt` | `PASS` |
| 3 | Export the saved document from the protected copy after the move/delete (`export.validate` and `export.render` on `emulator-5554`) | `-` | not run | `UNAVAILABLE` |

The runtime command ran with Temurin JDK 17 as `JAVA_HOME` and with Flutter and
Android platform-tools on `PATH`. Fixture staging into the device-local
temporary directory was setup, not a separate test: the `adb push` and `chmod`
commands are in the integration-test file header, and the resulting
device-side hashes are recorded in `fixture-sha256.txt`. The integration run
passed 2 of 2 trials with 0 failures. The log shows
`00:06 +2: All tests passed!`.

### 4.2 Host-only checks (`NONE` class; not runtime evidence)

These checks are deliberately separate from §4.1. They do not prove Android
behaviour and are not aggregated with the `EMULATOR` result.

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `flutter analyze --no-pub` (`apps/feldexa_app`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t048-emulator/host-flutter-analyze.log` | `PASS` |
| 2 | `flutter test --no-pub` (`apps/feldexa_app`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t048-emulator/host-flutter-test.log` | `PASS` |
| 3 | `./gradlew :app:compileReleaseKotlin --console=plain` (`apps/feldexa_app/android`) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t048-emulator/host-release-compile.log` | `PASS` |
| 4 | `git ls-tree -r --name-only HEAD -- .../app/export`; `grep -n -A 1 'registerService(' .../MainActivity.kt`; `grep -n 'export.validate\|export.render' .../FeldexaPlugin.kt`; `grep -n 'T104' .../tasks.md` (repo root) | `0` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t048-emulator/export-blocker.txt` | `PASS` |
| 5 | `git diff --check`; `git diff --cached --check` (repo root, staged docs change) | `0` | console only (not retained) | `PASS` |
| 6 | `dart tools/evaluation/validate_report.dart specs/001-scanned-form-workflow/reports/2026-11-18-emulator-t048-evidence.md` (repo root) | `0` | console only (not retained) | `PASS` |

`flutter analyze` reported `No issues found!`. The host test run ended with
`00:16 +244: All tests passed!` (244 tests, 0 failures); the browser-only
fixture test is skipped by its documented `FIXTURE_RUNTIME` gate and is not
counted here. The release Kotlin compile passed with the unchanged T046 seam
present but unreachable; the host working tree contains no production change
from T048.

The committed log artifacts were sanitized before commit: absolute host paths
were replaced with `<repo-root>`, `<flutter-sdk>`, `<gradle-home>`, or
`<redacted-home>`, and trailing spaces were removed so the branch passes
`git diff --check`. This is a textual normalization only; no result, claim,
count, device identity, command, or exit code changed.

## 5. Results

| Scenario | Input | Observed | Verdict |
| --- | --- | --- | --- |
| Import through the production pipeline | `sf-003` (5 pages), `sf-001` (2 pages), two trials | `ImportAccepted` with no warning in both trials; one document created per trial; page count 5 and 2; no page failures; display name preserved; document id present in `store.list` | `PASS` |
| Source byte identity and unchanged mtime at import | both picked files | bytes, SHA-256, byte length, and modification time identical before and after import; SHA-256 equals the committed catalogue value | `PASS` |
| Move the picked file to another directory | both trials | original path no longer exists; moved file exists; bytes, SHA-256, length, and modification time unchanged at the new path | `PASS` |
| Reopen the saved document while the picked path is gone | both trials | `store.loadDocument` returns the committed metadata and revision; title `t048-sf-003` / `t048-sf-001`; page count, order, rotation, MediaBox, and display size match the catalogue | `PASS` |
| Protected source read-back | both trials | explicit `store.readSource` returns bytes whose SHA-256 and byte content equal the original fixture | `PASS` |
| Render from the protected copy | both trials | PDFium renders every page at its display size; page raster SHA-256 values are identical between the fixture bytes and the decrypted stored bytes (5 digests for `sf-003`, 2 for `sf-001`) | `PASS` |
| Delete the moved file and reopen again | both trials | both filesystem paths are gone and both trial directories are empty; the document is still listed; `store.loadDocument` succeeds; re-render digests equal the pre-delete digests | `PASS` |
| Export the saved document from the protected copy | both trials | `export.validate` and `export.render` both fail closed with `PLT-001`/`platform.unsupported` (details `category=unsupported`, `retryable=false`); no export service is registered and no applier exists | `UNAVAILABLE` |

**Export blocker (exact dependency).** The production applier is owned by
**T104**, which is still unchecked in `tasks.md`:
`apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/export/PdfExportService.kt`.
The `export/` directory contains only `.gitkeep`; `MainActivity` registers only
the `store` and `import` services; the facade still validates, routes, and
serializes `export.validate`/`export.render`, so the call reaches the
fail-closed `PLT-001` branch instead of a service. The test attempted both
methods with a contract-shaped plan built from the reopened document
(`documentId`, `revisionId`, `sourceSha256`, page count, per-page geometry, font
contract) and asserted the fail-closed code, category, and non-retryable flag.
No export assertion is passed and no artifact is fabricated. SC-019's export
clause is therefore **not verified / blocked**, and the overall report result is
`PARTIAL`.

**Rendered page digests (PDFium BGRA raster SHA-256 at the page display size).**

```text
sf-003 (5 pages): 079ff02eed3e5b25ac9b82ed3fdd04b2f631c347eb1267fbb2eb32db306d5b6d
                  ded794256561b7ae73b7bf233801f279738c8265f2fc66aabd51c38b06151f45
                  50e84d3a5ab1963da07be9d9feeeff3b39568305bdd5ec5cc2c4fce2c8568594
                  6ac15c6a5f6de138f59ca435bb22f1becaf1f5347553be217d2941cdc04219ee
                  36db069bbd9eb71814ad20d34fa4bdf3b67f9d6fced39caa08f137ab58009137
sf-001 (2 pages): 008f1e501fbdf9df9f5f7f1cee20cd69d123209280ae3d26858e20baf9f37a4b
                  2326f6df44633c1b2d62eac40e1895f8fc1e896f1da3b56cabb3b685cf5ca31a
```

The same digests were produced before the deletion and after it, and the
stored-source SHA-256 equalled the fixture SHA-256 in both trials
(`c19afcf6…` for `sf-003`, `22c939cc…` for `sf-001`).

**Fidelity actually asserted.** The picked file is compared byte-for-byte and
by modification time before and after import and after the move; the moved
file is compared the same way; the decrypted protected copy is compared
byte-for-byte with the fixture and re-hashed through `store.readSource`; page
count, order, rotation, MediaBox, and display size come from the production
preflight/store and match the committed catalogue; and every page is rendered
by PDFium from the protected bytes with a SHA-256-identical raster to the
fixture bytes. Before the second reopen/render, both filesystem copies were
deleted and the trial directories were asserted empty, so those bytes can only
come from the protected internal copy.

## 6. Performance

No performance claim.

## 7. Limitations

- **SC-019 export clause is unverified.** T104's production PDFBox applier does
  not exist yet. The test records the precise `PLT-001` blocker; it does not
  prove that a saved document exports after its source was moved or deleted.
  This report's `PARTIAL` result is caused by that missing dependency.
- No `DEVICE`, release-runtime, physical-silicon, StrongBox, or performance
  claim. KVM acceleration was not freshly probed from this sandbox; see §3.
- The system SAF picker UI itself was not driven. The unchanged T046
  debug-only seam replaces only the picker's delivery of a local file-backed
  source; the production `ImportService`, encrypted staging, preflight, commit,
  cleanup, mapper, and store read-back are the real implementations. No SAF
  content-resolver or picker-result UI claim is made.
- The move and the deletion are ordinary filesystem operations performed by the
  test process on its own synthetic fixture copy. This proves the requirement's
  observable outcome (the document no longer depends on the picked file), not
  that a specific external storage provider behaves identically.
- The fixtures are synthetic vector PDFs. The pixel check compares PDFium
  renders of identical bytes at 72 DPI; it does not prove fidelity against an
  external scanner or a real authority form.
- Two trials are reported as two of two trials. This is not a statistical
  "100 % of all users" claim and does not satisfy the SC-019 trial population
  by itself.
- The integration test runs in an installed debug build and deletes the
  document it creates; `flutter test` removes the app afterwards, so no
  independent post-run store inspection was performed.
- This is author evidence. The test and this report require independent review;
  no self-approval is claimed.

## 8. Artifacts

All paths are repository-relative and committed with this report unless the
row says otherwise. The APK is a git-ignored local build output bound by
`apk-sha256.txt`; it is not committed.

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `apk-sha256.txt` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t048-emulator/apk-sha256.txt` | 320 | `2b68070d0223cd71d4f3462e96a31e5a22d7f981c1ea3685d7f96632d6db0d55` |
| `device-identity.txt` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t048-emulator/device-identity.txt` | 722 | `728e4ac37cf26a81d4347bfa1f79e36157cb59264b18f02a3736c8b6b52e02ae` |
| `export-blocker.txt` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t048-emulator/export-blocker.txt` | 1701 | `ffbdd204b524e466370a02309e255514347b7d78a5df1efa17abdd8e141aa5e9` |
| `fixture-sha256.txt` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t048-emulator/fixture-sha256.txt` | 648 | `9f2e684a66c066ff6136703a83c57f67120c88343399049e21b3f7bfb75fda94` |
| `host-flutter-analyze.log` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t048-emulator/host-flutter-analyze.log` | 57 | `ec8ef7b261ed2d9fc47b15354b019a8447823b6a86b4d3f4d88c2eaa51c420a1` |
| `host-flutter-test.log` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t048-emulator/host-flutter-test.log` | 36545 | `66de12fc9c0ef882cff94ed2bfca78525d41dff73fb862439c2a0a226c88e996` |
| `host-release-compile.log` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t048-emulator/host-release-compile.log` | 15322 | `169433692321df4bc8b7afb1f467dd1480bb74d378692b777618bbeaa60a2090` |
| `integration-android-source-integrity.log` | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-18-t048-emulator/integration-android-source-integrity.log` | 4409 | `377e21c9bdde620d65088cb5825cc7d1726c4976deb49d981aea9e8dfdc1541e` |

## 9. Reproducibility

1. Start from base commit `e8c29cf3795e798ed9ce35efc9ac2d5f6ec70bf9` and check
   out candidate code commit `4374414273e7b7a74c18c0870bd4a07bfdd003c4`;
   confirm tree `4eab0570efad290fb1d3008616930623b0e47384` and a clean working
   tree.
2. Use the pre-booted, exclusively allocated `T025_Pixel7_API35_KVM_20261115`
   AVD on serial `emulator-5554`; do not boot, wipe, reset, or snapshot it.
3. Stage the two committed synthetic PDF fixtures (`sf-001.pdf`, `sf-003.pdf`)
   with the `adb push` and `chmod` commands in the integration-test file
   header, then verify the device-side hashes against `fixture-sha256.txt`.
4. From `apps/feldexa_app`, with Flutter `3.47.7`, Temurin JDK 17, and Android
   platform-tools on `PATH`, run
   `flutter test integration_test/source_integrity_test.dart -d emulator-5554`;
   expected `00:06 +2: All tests passed!` and exit `0`. The test logs one
   `PLT-001` export-blocker line per trial; that is the expected outcome while
   T104 is unimplemented.
5. Host-only reproduction: `flutter analyze --no-pub` and `flutter test
   --no-pub` from `apps/feldexa_app`; release check:
   `./gradlew :app:compileReleaseKotlin --console=plain` from
   `apps/feldexa_app/android` with `JAVA_HOME` set to Temurin 17.
6. Cleanup: the test deletes every document it creates, deletes and removes its
   two trial directories, and clears the debug hook; `flutter test` removes the
   installed app/test packages. The AVD definition and staged synthetic
   fixtures may remain for independent revalidation.

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
