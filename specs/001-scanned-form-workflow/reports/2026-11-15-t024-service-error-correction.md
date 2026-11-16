# 2026-11-15 NONE — T024 service-Error terminal correction

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `PASS` |
| Task / issue | `T024` / #24 |
| Date / timezone | `2026-11-15 10:48 Europe/Berlin` |
| Revision | base commit `b92789f19354244cdfe34e50dd3022c7f36b5715`; tree `dirty`; dirty files: `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/FeldexaPlugin.kt` SHA-256 `9d93f93654e363ed0ddcca70482a4b0b803ccc9e8c32e8eb3ca0007e0c1dbccb`; `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/FeldexaPluginTest.kt` SHA-256 `4410b40a1e224bf57607ab179193006d9a6b84665869a096b520f6b52cddb3fe`; `specs/001-scanned-form-workflow/contracts/platform-channel.md` SHA-256 `e38b0f39111227d2ba1349ee96ef48f329fc903daedbb3f4bf2e11b8bbdecda8`; `specs/001-scanned-form-workflow/reports/README.md` SHA-256 `937631a6d507c22b3c3a241d438e5c62c5e86a31d4cb87b001d09dc3937a1a59`; `apps/feldexa_app/android/gradlew.bat` SHA-256 `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62` (pre-existing line-ending change, preserved and not part of this correction). This report's own path is excluded from its dirty-file list by construction. The commit containing this report is recorded in the external attestation. |
| External attestation | `worker_done` transport record for this dispatch; it records the candidate SHA, this report's bytes and SHA-256, and the changed-file list. No attestation ref was created. |
| Build identity | Debug APK built from the corrected tree; `app-debug.apk` 225292316 bytes, SHA-256 `8e2c0d452bdce1cebc852b1bdd51ca6b023a4db86273ab05d0424d3d4552ddfd`; `Lde/feldexa/app/FeldexaPlugin;` confirmed in the APK DEX by `dexdump` |
| Toolchain | Flutter `3.47.7` (framework `abaf9c5237`), Dart `3.13.5`, Kotlin `2.4.0` in Gradle, Gradle wrapper `9.3.1`, JetBrains Runtime `21.0.11` (the host JDK 27 is incompatible with the pinned Gradle 9.3.1), Android SDK platform 36/build-tools 35 for the app, JUnit `4.13.2` |
| Input | validator inputs: quality review of `b92789f`; owner decision and protocol in `contracts/platform-channel.md` §2.4/§9; `contracts/error-catalog.de.md`; `contracts/storage-format.md` §3.1; `tasks.md` T024; no corpus and no fixtures |

## 1. Scope

This report records the quality-review correction of T024 at
`b92789f19354244cdfe34e50dd3022c7f36b5715`. The review found that an accepted
asynchronous service throwing an `Error` such as `AssertionError` escaped
`runOperation`'s `Exception` catches, was rethrown, and was then swallowed by
`KeyedSerialExecutor.drain`; the handle was removed in `finally` without a
terminal `operation.result`. That violated the §2.4/§9 guarantee that every
accepted operation produces exactly one terminal result.

The fix:

- `runOperation` catches `Error` after the specific `Exception` mappings and sends
  the existing content-free `PlatformFailure.internal()` (`PLT-001`,
  `platform.internal`, `internalError`) through the atomic terminal transition.
  The `Error` message, class, stack, and cause are never copied into the result.
- The same safe mapping covers synchronous services, whose reply is a
  `PlatformException` rather than a result event.
- Terminal publication still uses `OperationHandle`'s locked
  `ACTIVE`/`CANCELLED`/`COMPLETED` transition. If cancellation won before the
  Error was handled, the only result is `PLT-004`; if the Error terminal wins,
  cancel returns `false`; exactly one result is produced. The handle is removed
  only after publication.
- Disposal suppresses delivery/replay through the synchronized result store; a
  service Error racing with teardown emits nothing after teardown.
- `KeyedSerialExecutor.drain` keeps its queue-stability catch as a safety net, but
  accepted service `Throwable`s no longer reach it.
- The contract now specifies the service-Error mapping and adds a §12 regression
  row.

The chat protocol, exact machine-message allowlist, bounded queues, SAVE-006 gate,
and start/result channel shape are unchanged. No service capability was added. No
push, merge, or self-review was performed.

The built-in `checklists/requirements.md` is fully checked (16/16). The custom
`checklists/precision-testability.md` remains reviewer-owned with 36 intentionally
unchecked markers and was not modified.

`.specify/extensions.yml` declares `hooks: {}`; no before/after implementation hook
was registered or executed.

## 2. Revision and build

The correction starts at `b92789f19354244cdfe34e50dd3022c7f36b5715` and changes
`FeldexaPlugin.kt`, its host-JVM tests, the channel contract, and this evidence
index. The pre-existing unstaged `gradlew.bat` line-ending change is preserved and
excluded.

The debug APK was rebuilt from the corrected tree and contains
`de.feldexa.app.FeldexaPlugin`.

## 3. Environment

Host: Linux x86_64. The executed checks are Kotlin/JVM compilation, JUnit, Gradle
configuration, Android debug APK assembly, and DEX inspection. Android emulator and
physical-device runtime checks are NOT_RUN: no exclusively allocated instrumentation
session was used and no physical device is attached. No runtime class block is
claimed.

The DSH sandbox mounts everything outside the session workspace read-only. The
Android toolchain run used workspace-local shadow copies of the Flutter SDK, pub
cache, Gradle user home, and Android SDK, plus JBR 21 for Gradle 9.3.1. The host JDK
27 fails the pinned Gradle Kotlin DSL with `Unsupported class file major version 71`.
These shadows, `local.properties`, and the 34-labelled platform shim for the
`printing` plugin are environment-only and are not committed.

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `./gradlew :app:testDebugUnitTest :app:assembleDebug --offline --no-daemon --no-configuration-cache --no-watch-fs --console=plain` (`apps/feldexa_app/android`) | `0` | `.dart_tool/t024-kotlin/gradle-error-final.log` | `PASS` |
| 2 | `dexdump -f apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk \| grep Lde/feldexa/app/FeldexaPlugin;` (`.`) | `0` | `console only (not retained)` | `PASS` |

The Gradle run again logged a Kotlin daemon start failure because the daemon state
directory is read-only; Gradle fell back to in-process Kotlin compilation and
completed successfully. This is an environment limitation, not a code result.

## 5. Results

| Area | Observed result |
| --- | --- |
| Async `AssertionError` | Accepted `ocr.recognize` throws `AssertionError`; start reply is success, then exactly one `operation.result` error `PLT-001`/`platform.internal`/`internalError`; the result contains no `secret` or `/private` text |
| Sync `AssertionError` | `store.status` throwing `AssertionError` returns one safe `PlatformException` `PLT-001`/`internalError`; the throwable text is absent |
| Cancel-before-Error | A running Error service is cancelled before it throws; the only result is `PLT-004`, not `PLT-001` or success |
| Error-before-cancel | Terminal Error publication uses the locked state; a later cancel returns `false` and no second result appears |
| Dispose race | Disposing while the Error service is blocked produces no post-teardown event or replay |
| Exactly one result | Every Error regression asserts a single sink event; success/error/cancel interleavings remain green |
| Existing behavior | Start reply, result channel, exact message allowlist, bounded queues, SAVE-006, cancellation, and lifecycle tests remain green |
| Test suite | 88/88 host-JVM tests pass; Gradle XML records `tests="88" skipped="0" failures="0" errors="0"` |
| Pre-fix reproduction | The `b92789f` facade compiled against the new suite failed 3 tests: `assertionErrorIsPublishedAsSafeInternalResult`, `syncAssertionErrorReturnsSafePlatformException`, and `assertionErrorAfterCancelPublishesOnlyCancellation` |
| Android build | `:app:assembleDebug` succeeds; the APK contains `de.feldexa.app.FeldexaPlugin` |
| Runtime | Android emulator and physical-device checks are NOT_RUN; no Android runtime claim is made |

## 6. Performance

No performance claim. The added `Error` catch is a constant-time mapping; no SC-004
or acceptance timing was attempted.

## 7. Limitations

- **Android emulator is NOT_RUN.** No exclusively allocated instrumentation run was used; no engine-level Error behavior is claimed.
- **Physical device is NOT_RUN.** No device is attached; no acceptance or performance claim is made.
- **Host-only proof.** The JUnit suite exercises the Kotlin facade through injected threading, event, reply, and result seams. It does not prove Flutter engine EventChannel registration, Android lifecycle delivery, Keystore, SAF, PDFBox, ML Kit, or PDFium behavior.
- **No service capability.** T025/T026/T038–T040 still own the services; all non-cancel methods fail closed with `PLT-001` until registered.
- **Result retention is bounded.** An evicted result is unrecoverable; the start reply remains the acceptance proof.
- **Fatal Error caveat.** `Error` includes fatal conditions such as `OutOfMemoryError`; the mapping is the contract's safe terminal fallback, but no guarantee is made that the process can continue allocating after such a condition.
- The Gradle Kotlin-daemon path was blocked by the read-only home directory; in-process compilation succeeded. The toolchain shadows are environment-only and not part of the candidate.
- No checklist item was changed; the custom checklist remains reviewer-owned.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Facade | `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/FeldexaPlugin.kt` | 64465 | `9d93f93654e363ed0ddcca70482a4b0b803ccc9e8c32e8eb3ca0007e0c1dbccb` |
| Host tests | `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/FeldexaPluginTest.kt` | 62952 | `4410b40a1e224bf57607ab179193006d9a6b84665869a096b520f6b52cddb3fe` |
| Channel contract | `specs/001-scanned-form-workflow/contracts/platform-channel.md` | 28685 | `e38b0f39111227d2ba1349ee96ef48f329fc903daedbb3f4bf2e11b8bbdecda8` |
| Evidence index | `specs/001-scanned-form-workflow/reports/README.md` | 27959 | `937631a6d507c22b3c3a241d438e5c62c5e86a31d4cb87b001d09dc3937a1a59` |
| Debug APK | `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 225292316 | `8e2c0d452bdce1cebc852b1bdd51ca6b023a4db86273ab05d0424d3d4552ddfd` |
| Gradle JUnit XML | `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.FeldexaPluginTest.xml` | 10453 | `173193000382cbdfa61fa2d41582603a2e4d3560e7a71d01ff4267b7ea8ba5c6` |
| Gradle combined log | `.dart_tool/t024-kotlin/gradle-error-final.log` | 31700 | `9f9dd4dda49d9926cb09cc99adb1f7c4a5528db4cbac0810ab8669a56919a907` |
| Standalone JUnit log | `.dart_tool/t024-kotlin/junit-error2.log` | 138 | `ce85275005e309af3083cef0d36ad4b418beef71183219f2818e20ae8e91b844` |
| Pre-fix JUnit log | `.dart_tool/t024-error-old/junit-old.log` | 1117 | `b398fd43a0b28839b3c05a1f026e0ab0586dc0ceb50c831599335bb39f3fabbd` |

This report's own row is omitted by construction. The pre-existing
`apps/feldexa_app/android/gradlew.bat` change is listed as a dirty file but is not
part of this correction.

## 9. Reproducibility

1. Start from base commit `b92789f19354244cdfe34e50dd3022c7f36b5715` in the isolated worktree.
2. Run `./gradlew :app:testDebugUnitTest :app:assembleDebug` in `apps/feldexa_app/android`; expect `BUILD SUCCESSFUL` and `tests="88" skipped="0" failures="0" errors="0"` for `de.feldexa.app.FeldexaPluginTest`.
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
