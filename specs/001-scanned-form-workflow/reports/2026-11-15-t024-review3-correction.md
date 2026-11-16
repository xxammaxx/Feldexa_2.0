# 2026-11-15 NONE — T024 message allowlist correction

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `PASS` |
| Task / issue | `T024` / #24 |
| Date / timezone | `2026-11-15 03:08 Europe/Berlin` |
| Revision | base commit `155e307de2f861aa96c503558d4a504c9dc1d64e`; tree `dirty`; dirty files: `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/FeldexaPlugin.kt` SHA-256 `315618c949507db624bd14eadbe407cc9b354052c08c6e8fe3a006551bf68932`; `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/FeldexaPluginTest.kt` SHA-256 `f6b98bc811372c5a52554a4213c64aea7480e3aea843812f2bbf2a13246f8261`; `specs/001-scanned-form-workflow/reports/README.md` SHA-256 `36fe5f5eafcf9681e6dbe02a184a58a9239fce0d9dac73742a7f6baa7f5e57b8`; `apps/feldexa_app/android/gradlew.bat` SHA-256 `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62` (pre-existing line-ending change, preserved and not part of this correction). This report's own path is excluded from its dirty-file list by construction. The commit containing this report is recorded in the external attestation. |
| External attestation | `worker_done` transport record for this dispatch; it records the candidate SHA, this report's bytes and SHA-256, and the changed-file list. No attestation ref was created. |
| Build identity | Debug APK built from the corrected tree; `app-debug.apk` 225286223 bytes, SHA-256 `0b44bed45d817a48327db0f6d55225b7331eb94833ef96ea75d8973c5cc81067`; `Lde/feldexa/app/FeldexaPlugin;` confirmed in the APK DEX by `dexdump` |
| Toolchain | Flutter `3.47.7` (framework `abaf9c5237`), Dart `3.13.5`, Kotlin `2.4.0` in Gradle, Gradle wrapper `9.3.1`, JetBrains Runtime `21.0.11` (the host JDK 27 is incompatible with the pinned Gradle 9.3.1), Android SDK platform 36/build-tools 35 for the app, JUnit `4.13.2` |
| Input | validator inputs: `contracts/platform-channel.md` §2.1–§2.2; `contracts/error-catalog.de.md`; `contracts/storage-format.md` §5; `tasks.md` T024; no corpus and no fixtures |

## 1. Scope

This report covers the follow-up quality-review correction of T024 at
`155e307de2f861aa96c503558d4a504c9dc1d64e`. The review confirmed that bounded
queues and queued cancellation work, but showed that the machine-message check
validated only the namespace: `save.antrag` was accepted and then emitted through
`PlatformException.message` at the channel boundary. That violates the §2.2 rule
that `message` is a stable machine key and may not contain names, titles, paths, or
other document content.

The fix replaces namespace matching with a **closed exact-key allowlist**. A message
must still look like a machine key, and it must exist in a fixed set of
content-free keys. `save.antrag`, `save.documentTitle`, `antrag.secret`, arbitrary
single tokens, and unknown keys are rejected at construction; all current facade
validation keys and the legitimate catalog mappings tested below remain accepted.
No result or error signature was invented, and no service capability was added.

T025/T026/T038–T040 still own the service implementations. The pre-existing
bounded-queue, queued-cancellation, `SAVE-006`, OCR-raster, and non-coalesced start
behavior from the previous correction is unchanged. No push, merge, or self-review
was performed.

The built-in `checklists/requirements.md` is fully checked (16/16). The custom
`checklists/precision-testability.md` remains reviewer-owned with 36 intentionally
unchecked markers and was not modified.

`.specify/extensions.yml` declares `hooks: {}`; no before/after implementation hook
was registered or executed.

## 2. Revision and build

The correction starts from the reviewed T024 candidate
`155e307de2f861aa96c503558d4a504c9dc1d64e`. The only intended source changes are
`FeldexaPlugin.kt` and its host-JVM test file; this report and its README index row
are the documentation changes. The pre-existing unstaged `gradlew.bat` line-ending
change is preserved and excluded from this correction.

The debug APK was rebuilt from the corrected tree and contains
`de.feldexa.app.FeldexaPlugin`.

### 2.1 Correction

| Area | Correction |
| --- | --- |
| Exact message allowlist | `ALLOWED_MACHINE_MESSAGES` enumerates every accepted key: the facade's `platform.*` validation keys, `save.invalidData`, `save.concurrentWrite`, and the current legitimate catalog mappings (`save.storageFull`, `save.keyUnavailable`, `save.corruptData`, `save.schemaTooNew`, `save.keystoreUnavailable`, import/export/OCR/page/delivery/template/date/number/field/privacy keys). The constructor requires exact membership in addition to the machine-key shape. |
| Sensitive suffix rejection | `save.antrag` and `save.documentTitle` now fail construction instead of reaching `PlatformException.message`. `antrag.secret`, `documentTitle`, single-token messages, content-bearing categories, unknown catalog codes, and negative counters remain rejected. |
| Legitimate mappings | The new test constructs accepted failures for `platform.invalidPayload`, `save.storageFull`, `save.noSpace`, `save.keyUnavailable`, `save.corruptData`, `save.schemaTooNew`, `save.concurrentWrite`, `import.passwordProtected`, `import.unreadable`, `import.tooLarge`, `export.blocked`, `export.missingGlyph`, `ocr.unavailable`, `page.renderFailed`, and `delivery.cancelled`. |
| Bound preservation | The previous bounded per-aggregate/total queues, removable queued cancellation, non-coalesced start event, and same-document `SAVE-006` gate are retained unchanged. |

A future catalog mapping must add its exact key to the allowlist deliberately; it
cannot pass by sharing a namespace or suffix with an existing key.

## 3. Environment

Host: Linux x86_64. The executed checks are Kotlin/JVM compilation, JUnit, Gradle
configuration, Android debug APK assembly, and DEX inspection. Android emulator and
physical-device runtime checks are NOT_RUN: no exclusively allocated instrumentation
session was used and no physical device is attached. No runtime class block is
claimed.

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
| 1 | `./gradlew :app:testDebugUnitTest :app:assembleDebug --offline --no-daemon --no-configuration-cache --no-watch-fs --console=plain` (`apps/feldexa_app/android`) | `0` | `.dart_tool/t024-kotlin/gradle-review3-final.log` | `PASS` |
| 2 | `dexdump -f apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk \| grep Lde/feldexa/app/FeldexaPlugin;` (`.`) | `0` | `console only (not retained)` | `PASS` |

The Gradle run again logged a Kotlin daemon start failure because the daemon state
directory is read-only; Gradle fell back to in-process Kotlin compilation and
completed successfully. This is an environment limitation, not a code result.

## 5. Results

| Area | Observed result |
| --- | --- |
| Closed allowlist | Exact membership is required; a valid-looking namespace/suffix cannot pass |
| Sensitive values | `save.antrag` and `save.documentTitle` are rejected at `PlatformFailure` construction; `antrag.secret`, `documentTitle`, single-token messages, content-bearing categories, unknown codes, and negative counters also fail |
| Legitimate mappings | The 15 tested catalog mappings are accepted and preserve their exact machine message; all current facade validation keys remain constructible |
| Existing behavior | Success envelopes, error details/durations, OCR raster lengths, bounded queues, queued cancellation, `SAVE-006`, events, service detachment, and lifecycle tests remain green |
| Test suite | 72/72 host-JVM tests pass; Gradle XML records `tests="72" skipped="0" failures="0" errors="0"` |
| Pre-fix reproduction | The `155e307` facade compiled against the new suite failed exactly `sensitiveMessageSuffixIsRejected` (72 runnable tests, 1 failure), confirming the suffix leak; after the fix all 72 pass |
| Android build | `:app:assembleDebug` succeeds; the APK contains `de.feldexa.app.FeldexaPlugin` |
| Runtime | Android emulator and physical-device checks are NOT_RUN; no Android runtime claim is made |

## 6. Performance

No performance claim. The exact-set membership check adds constant-time validation;
no SC-004 or acceptance timing was attempted.

## 7. Limitations

- **Android emulator is NOT_RUN.** No exclusively allocated instrumentation run was used. No instrumentation evidence is claimed.
- **Physical device is NOT_RUN.** No device is attached; no acceptance or performance claim is made.
- **Host-only proof.** The JUnit suite exercises the Kotlin facade through injected threading/event/reply seams. It does not prove Flutter engine registration, Android lifecycle delivery, Keystore, SAF, PDFBox, ML Kit, or PDFium behavior.
- **No service capability.** T025/T026/T038–T040 still own the services; all non-cancel methods fail closed with `PLT-001` until registered.
- **Allowlist extension is deliberate.** New catalog mappings must add their exact key; a namespace alone is no longer accepted.
- The Gradle Kotlin-daemon path was blocked by the read-only home directory; in-process compilation succeeded. The toolchain shadows are environment-only and not part of the candidate.
- No checklist item was changed; the custom checklist remains reviewer-owned.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Facade | `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/FeldexaPlugin.kt` | 57434 | `315618c949507db624bd14eadbe407cc9b354052c08c6e8fe3a006551bf68932` |
| Host tests | `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/FeldexaPluginTest.kt` | 45647 | `f6b98bc811372c5a52554a4213c64aea7480e3aea843812f2bbf2a13246f8261` |
| Evidence index | `specs/001-scanned-form-workflow/reports/README.md` | 26484 | `36fe5f5eafcf9681e6dbe02a184a58a9239fce0d9dac73742a7f6baa7f5e57b8` |
| Debug APK | `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 225286223 | `0b44bed45d817a48327db0f6d55225b7331eb94833ef96ea75d8973c5cc81067` |
| Gradle JUnit XML | `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.FeldexaPluginTest.xml` | 8458 | `1c23598b937e3c1cb43f2789205d53a88309a9fd8cac2bd46db13d085e7500a1` |
| Gradle combined log | `.dart_tool/t024-kotlin/gradle-review3-final.log` | 31697 | `a3bc6a235ac6e30bdff0e52e2837785185189439e27518430a714228986356fe` |
| Standalone JUnit log | `.dart_tool/t024-kotlin/junit-allowlist.log` | 122 | `2ec913b973e7d4e451a1cc3fd2d3115bd7c9c1bac1c1268985ca35426bd1307a` |
| Pre-fix JUnit log | `.dart_tool/t024-review3-old/junit-old.log` | 546 | `d851cab1ffe8cbe732fb3adec5ec41fecb24134d80f2e196fb2fcc8ac7f5a119` |

This report's own row is omitted by construction. The pre-existing
`apps/feldexa_app/android/gradlew.bat` change is listed as a dirty file but is not
part of this correction.

## 9. Reproducibility

1. Start from base commit `155e307de2f861aa96c503558d4a504c9dc1d64e` in the isolated worktree.
2. Run `./gradlew :app:testDebugUnitTest :app:assembleDebug` in `apps/feldexa_app/android`; expect `BUILD SUCCESSFUL` and `tests="72" skipped="0" failures="0" errors="0"` for `de.feldexa.app.FeldexaPluginTest`.
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
