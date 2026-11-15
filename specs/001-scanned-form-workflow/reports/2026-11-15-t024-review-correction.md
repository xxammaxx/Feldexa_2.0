# 2026-11-15 NONE — T024 quality-review correction

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `PASS` |
| Task / issue | `T024` / #24 |
| Date / timezone | `2026-11-15 02:44 Europe/Berlin` |
| Revision | base commit `b1eadd61cf80c124a7fee22c4028e3f40ffe01e3`; tree `dirty`; dirty files: `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/FeldexaPlugin.kt` SHA-256 `ec2108bdc3513e7dd7b38bb4c83ba0bc8ad4d4f45fc4b891dc39924a9a4370f8`; `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/FeldexaPluginTest.kt` SHA-256 `23630106ce390fe71a25566e772dc3cfefad68325ff128f4ec504ab772dc9ac3`; `specs/001-scanned-form-workflow/reports/README.md` SHA-256 `7b9762bf0315bbad23c58bed8bbd34f3163e068ae5cf6646e185099a2d57124c`; `apps/feldexa_app/android/gradlew.bat` SHA-256 `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62` (pre-existing line-ending change, preserved and not part of this correction). This report's own path is excluded from its dirty-file list by construction. The commit containing this report is recorded in the external attestation. |
| External attestation | `worker_done` transport record for this dispatch; it records the candidate SHA, this report's bytes and SHA-256, and the changed-file list. No attestation ref was created. |
| Build identity | Debug APK built from the corrected tree; `app-debug.apk` 225281665 bytes, SHA-256 `44c19b22b56596948d45a1840004276ff8c2537b4784259bfa90f5d3cdddeab3`; `Lde/feldexa/app/FeldexaPlugin;` confirmed in the APK DEX by `dexdump` |
| Toolchain | Flutter `3.47.7` (framework `abaf9c5237`), Dart `3.13.5`, Kotlin `2.4.0` in Gradle, Gradle wrapper `9.3.1`, JetBrains Runtime `21.0.11` (the host JDK 27 is incompatible with the pinned Gradle 9.3.1), Android SDK platform 36/build-tools 35 for the app, JUnit `4.13.2` |
| Input | validator inputs: `contracts/platform-channel.md` §1, §2.1, §5, §8, §9, §10 and §12; `contracts/error-catalog.de.md` §1–§11; `contracts/export-plan.md` §2.1 and §2.3; `contracts/ports.md` §3; `tasks.md` T024; no corpus and no fixtures |

## 1. Scope

This report covers the quality-review correction of T024 at
`b1eadd61cf80c124a7fee22c4028e3f40ffe01e3`. Four reported cases were audited
against `contracts/platform-channel.md` and the actual method/ownership boundaries:

1. `PlatformFailure` exposed freely constructible code, category, machine message,
   and detail counters.
2. The generated operation id was not in the method result, so cancellation had to
   rely on a progress event.
3. OCR accepted a byte array whose length did not match the declared raster size
   and format.
4. Per-document serialization was not implemented.

Cases 1, 3, and 4 were confirmed deviations and were corrected. Case 2's premise
that the id must appear in the method result is **not** a contract requirement:
§2.1 defines only `schemaVersion`, `ok`, and `data` in the success envelope, the
method response tables in §3–§7 contain no `operationId`, and §8/§9 designate the
progress stream as the place where `operationId` travels. The operational gap was
still fixed without inventing a result field: the facade now emits an
`operation.progress` event with `phase:"queued"` before dispatch for cancellable
long operations, so Dart can learn the id and call `cancel.operation` before the
service starts. A regression drives that exact sequence and observes `PLT-004`.

No import, OCR, storage, export, or delivery capability was added. The service
ownership boundary remains T025/T026/T038–T040; unregistered prefixes still fail
closed with `PLT-001`. No push, merge, or self-review was performed.

The built-in `checklists/requirements.md` is fully checked (16/16). The custom
`checklists/precision-testability.md` remains reviewer-owned with 36 intentionally
unchecked markers and was not modified.

`.specify/extensions.yml` declares `hooks: {}`; no before/after implementation hook
was registered or executed.

## 2. Revision and build

The correction starts from the reviewed T024 candidate
`b1eadd61cf80c124a7fee22c4028e3f40ffe01e3`. The only intended source changes are
`FeldexaPlugin.kt` and its host-JVM test file. This report and its README index row
are the documentation changes. The pre-existing unstaged `gradlew.bat` line-ending
change is preserved and excluded from this correction.

The debug APK was rebuilt from the corrected tree and contains
`de.feldexa.app.FeldexaPlugin`.

### 2.1 Corrections applied

| Case | Contract basis | Correction |
| --- | --- | --- |
| 1 | §2.2 requires a catalog `code`, a stable machine `message`, and the documented detail keys; §10 lists developer codes; §11 forbids content and paths | `PlatformFailure` now validates the code against the complete catalog allowlist, validates `category` as a lower-camel machine token, requires a namespaced machine message (at least one dot/separator, no spaces or paths, max 64), rejects negative counters, and keeps details to the six documented keys. Regression tests reject unknown codes, content-bearing messages/categories, single-token messages, and negative counters, while accepting every code family. |
| 2 | §2.1/§3–§7 have no result `operationId`; §8 events and §9 cancellation carry it | No method-result field was invented. `operationKind` emits an `operation.progress` `queued`/`0.0` event before dispatch for import, OCR, save, and export long operations; the id is then used by `cancel.operation` and the regression observes `PLT-004`. |
| 3 | §5 request carries `imageWidth`, `imageHeight`, `format`, and `bytes`; §10 caps OCR rasters and rejects invalid payloads with `PLT-003` | `ocr.recognize` now has a cross-field validator: `gray8` must be exactly `width × height` bytes and `rgba8888` exactly `width × height × 4`. Wrong sizes are `PLT-003`; valid sizes pass. |
| 4 | §9 requires at most two workers and import/export/OCR serialized per document, and a second same-document save to conflict | `KeyedSerialExecutor` serializes same aggregate keys while different keys still use the two-worker pool. Import uses one import key (no document id before staging), export uses `plan.documentId`, save/template/signature writes use their aggregate id, and OCR uses a conservative global OCR key because the contract gives OCR no document id. Per-document OCR remains the service/adapter owner (T056/T027). |

## 3. Environment

Host: Linux x86_64. The executed checks are Kotlin/JVM compilation, JUnit,
Gradle configuration, Android debug APK assembly, and DEX inspection. The Android
emulator and physical-device runtime checks are NOT_RUN: an emulator endpoint
appeared without an exclusively allocated session, no instrumentation test was
allocated, and no physical device is attached. No runtime class block is claimed.

The DSH sandbox mounts everything outside the session workspace read-only. The
Android toolchain run therefore used workspace-local shadow copies of the Flutter
SDK, pub cache, Gradle user home, and Android SDK, plus JBR 21 for Gradle 9.3.1.
The host JDK 27 fails the pinned Gradle Kotlin DSL with `Unsupported class file
major version 71`. These shadows, the generated `local.properties`, and the
34-labelled platform shim required by the `printing` plugin are environment-only
and are not committed.

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `./gradlew :app:testDebugUnitTest :app:assembleDebug --offline --no-daemon --no-configuration-cache --no-watch-fs --console=plain` (`apps/feldexa_app/android`) | `0` | `.dart_tool/t024-kotlin/gradle-review-final.log` | `PASS` |
| 2 | `dexdump -f apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk \| grep Lde/feldexa/app/FeldexaPlugin;` (`.`) | `0` | `console only (not retained)` | `PASS` |

The Gradle run again logged a Kotlin daemon start failure because the daemon state
directory is read-only; Gradle fell back to in-process Kotlin compilation and
completed successfully. This is an environment limitation, not a code result.

## 5. Results

| Area | Observed result |
| --- | --- |
| Error allowlist | Unknown catalog codes, content-bearing categories/messages, single-token messages, and negative counters are rejected at construction; the complete catalog code set remains constructible |
| Cancellation discoverability | Long operations publish `operation.progress` with `event`, `operationId`, `kind`, `phase:"queued"`, `fraction:0.0` before dispatch; the regression cancels that id and receives `PLT-004` on the terminal result |
| OCR raster validation | 100×100 `gray8` with 10000 bytes and 100×100 `rgba8888` with 40000 bytes pass; 100×100 `gray8` with 10 bytes and 100×100 `rgba8888` with 10000 bytes fail with `PLT-003` (`platform.invalidRaster`) |
| Serialization | Two same-document saves produce one executor wrapper and a maximum service concurrency of 1; two different documents produce two wrappers; two OCR calls share a conservative OCR key and run serially |
| Existing behavior | Success envelopes, error details/durations, payload limits, cancellation, events, service detachment, and lifecycle tests remain green |
| Test suite | 64/64 host-JVM tests pass; Gradle XML records `tests="64" skipped="0" failures="0" errors="0"` |
| Android build | `:app:assembleDebug` succeeds; the APK contains `de.feldexa.app.FeldexaPlugin` |
| Runtime | Android emulator and physical-device checks are NOT_RUN; no Android runtime claim is made |

### 5.1 Pre-fix reproduction

The reviewed `b1eadd6` facade was compiled against the new test suite and run on the
host JVM: 64 tests, 10 failures. The failures reproduce all four reported gaps:
`unknownCatalogCodeIsRejected`, `contentBearingFailureMessageIsRejected`,
`contentBearingFailureCategoryIsRejected`, `singleTokenFailureMessageIsRejected`, and
`negativeFailureCountersAreRejected` (case 1);
`longOperationPublishesCancellationIdBeforeDispatch` (case 2);
`ocrGrayBytesMustMatchDimensions` and `ocrRgbaBytesMustMatchDimensions` (case 3); and
`sameDocumentOperationsAreSerialized` and `ocrOperationsAreSerializedConservatively`
(case 4). After the corrections the same 64 tests pass, which is the regression
proof recorded in §5 and §8.

## 6. Performance

No performance claim. The added serialization gate changes ordering, not measured
throughput; no SC-004 or acceptance timing was attempted.

## 7. Limitations

- **Android emulator is NOT_RUN.** No exclusively allocated emulator/instrumentation run was available; the endpoint that appeared was not used. No instrumentation evidence is claimed.
- **Physical device is NOT_RUN.** No device is attached; no acceptance or performance claim is made.
- **Host-only proof.** The JUnit suite exercises the Kotlin facade through injected threading/event/reply seams. It does not prove Flutter engine registration, Android lifecycle delivery, Keystore, SAF, PDFBox, ML Kit, or PDFium behavior.
- **No capability implementation.** T025/T026/T038–T040 still own the services; all non-cancel methods fail closed with `PLT-001` until registered.
- **OCR serialization is conservative, not per document.** The contract's OCR request has no document id, so the facade uses one OCR key; true per-document OCR ordering remains with T056/T027. Import similarly uses one import key because no document exists before staging.
- The Gradle Kotlin-daemon path was blocked by the read-only home directory; in-process compilation succeeded. The toolchain shadows are environment-only and not part of the candidate.
- No checklist item was changed; the custom checklist remains reviewer-owned.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Facade | `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/FeldexaPlugin.kt` | 49827 | `ec2108bdc3513e7dd7b38bb4c83ba0bc8ad4d4f45fc4b891dc39924a9a4370f8` |
| Host tests | `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/FeldexaPluginTest.kt` | 40242 | `23630106ce390fe71a25566e772dc3cfefad68325ff128f4ec504ab772dc9ac3` |
| Evidence index | `specs/001-scanned-form-workflow/reports/README.md` | 25480 | `7b9762bf0315bbad23c58bed8bbd34f3163e068ae5cf6646e185099a2d57124c` |
| Debug APK | `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 225281665 | `44c19b22b56596948d45a1840004276ff8c2537b4784259bfa90f5d3cdddeab3` |
| Gradle JUnit XML | `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.FeldexaPluginTest.xml` | 7535 | `9c7832efcca53cd0830249e4da6e5df7ce3b3268a01a505bbe0ef320aa5f409b` |
| Gradle combined log | `.dart_tool/t024-kotlin/gradle-review-final.log` | 31698 | `4387bc0619969000c677f8ee7e0151fbdc75b87450a0caaedf33ad054ff211aa` |
| Standalone JUnit log | `.dart_tool/t024-kotlin/junit-review.log` | 114 | `5a66395be83dd2ec0acfe4ccfcb47e85031faf6ff5052a17d66c2144ac141007` |
| Pre-fix reproduction log | `.dart_tool/t024-review-old/junit-old.log` | 4092 | `01532892494bec0cd4ea46fe41e9c6597ccf3cf6daf857c88fb70d1b985c94bb` |

This report's own row is omitted by construction. The pre-existing
`apps/feldexa_app/android/gradlew.bat` change is listed as a dirty file but is not
part of this correction.

## 9. Reproducibility

1. Start from base commit `b1eadd61cf80c124a7fee22c4028e3f40ffe01e3` in the isolated worktree.
2. Run `./gradlew :app:testDebugUnitTest :app:assembleDebug` in `apps/feldexa_app/android`; expect `BUILD SUCCESSFUL` and `tests="64" skipped="0" failures="0" errors="0"` for `de.feldexa.app.FeldexaPluginTest`.
3. Inspect the APK with `dexdump -f`; expect `Lde/feldexa/app/FeldexaPlugin;`.
4. Run the emulator acceleration check on a KVM-capable host only; a host without KVM acceleration returns a non-zero code. Do not report that as EMULATOR evidence.
5. With an exclusively allocated emulator, run the §12 contract tests separately and label them EMULATOR; no such run is claimed here.

## 10. External attestation

The `worker_done` transport record for this dispatch records the candidate SHA, this
report's bytes and SHA-256, and the changed-file list. No attestation ref, push,
merge, or independent review was created or performed.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
