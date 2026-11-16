# 2026-11-15 NONE — T024 terminal/cancel race correction

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `PASS` |
| Task / issue | `T024` / #24 |
| Date / timezone | `2026-11-15 10:30 Europe/Berlin` |
| Revision | base commit `1f16f44e5665e662a1ef1dbea9fcebb1e00fa9f4`; tree `dirty`; dirty files: `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/FeldexaPlugin.kt` SHA-256 `3f5bb8178129b15b9fb9be1a0a272644b43de19384ee09d1672692878d79a38b`; `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/FeldexaPluginTest.kt` SHA-256 `254d32d1344a44a8e6e6c505af0b98497a206becfa8bbba9879025c19c332659`; `specs/001-scanned-form-workflow/contracts/platform-channel.md` SHA-256 `fdcbe14983c14f263e6d053478e13cdd0017edee20a6ed9720a54986ab96c1a1`; `specs/001-scanned-form-workflow/reports/README.md` SHA-256 `1c4de2441c20b43134d08c7150359285ff71d80717501eae84cfe47778e26dab`; `apps/feldexa_app/android/gradlew.bat` SHA-256 `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62` (pre-existing line-ending change, preserved and not part of this correction). This report's own path is excluded from its dirty-file list by construction. The commit containing this report is recorded in the external attestation. |
| External attestation | `worker_done` transport record for this dispatch; it records the candidate SHA, this report's bytes and SHA-256, and the changed-file list. No attestation ref was created. |
| Build identity | Debug APK built from the corrected tree; `app-debug.apk` 225292355 bytes, SHA-256 `b027929a2421a584616689697db895e582805fb2dfa30942452f8226b292bb9a`; `Lde/feldexa/app/FeldexaPlugin;` confirmed in the APK DEX by `dexdump` |
| Toolchain | Flutter `3.47.7` (framework `abaf9c5237`), Dart `3.13.5`, Kotlin `2.4.0` in Gradle, Gradle wrapper `9.3.1`, JetBrains Runtime `21.0.11` (the host JDK 27 is incompatible with the pinned Gradle 9.3.1), Android SDK platform 36/build-tools 35 for the app, JUnit `4.13.2` |
| Input | validator inputs: quality review of `1f16f44`; owner decision and protocol in `contracts/platform-channel.md` §2.4/§9; `contracts/error-catalog.de.md`; `contracts/storage-format.md` §3.1; `tasks.md` T024; no corpus and no fixtures |

## 1. Scope

This report records the quality-review correction of T024 at
`1f16f44e5665e662a1ef1dbea9fcebb1e00fa9f4`. The review identified two confirmed
concurrency defects:

1. Success removed the operation handle before publishing the terminal result,
   while errors published before handle removal. A concurrent `cancel.operation`
   could therefore return `false` before a published terminal state on success, or
   `true` after a published terminal state on error.
2. A result `publish` that passed the disposed check before `dispose` could later
   refill the cleared retention store; teardown could also be followed by a replay
   or event.

The fix introduces one atomic operation state and one result-store lock:

- `OperationHandle` is `ACTIVE`, `CANCELLED`, or `COMPLETED` under one lock.
  `complete(publish)` sets `COMPLETED` and publishes the success/error result while
  holding that lock; `cancel()` and `complete()` cannot interleave. A terminal
  result is published before the handle leaves the registry, and cancel returns
  `false` after the terminal transition. Cancellation wins before the terminal
  transition produces exactly one `PLT-004`; success/error is never published after
  cancellation won.
- `OperationRegistry.cancel` now returns the actual transition result instead of
  unconditionally returning `true`.
- The facade removes the handle and releases the in-flight save marker only after
  terminal publication; a queued cancel publishes `PLT-004` before removal.
- `PlatformResultPublisher.publish`, `attachSink`, and `dispose` share one lock;
  the disposed check is inside it, and a posted/replayed event re-checks teardown.
  `dispose` clears retention under that lock, so a racing publish cannot refill it
  and cannot deliver or replay after teardown.
- The contract now states the terminal/cancel linearization and synchronized
  dispose semantics in §2.4 and §9.

The start/result channel protocol, exact machine-message allowlist, bounded queues,
SAVE-006 gate, and synchronous-method behavior are unchanged. No service
capability was added. No push, merge, or self-review was performed.

The built-in `checklists/requirements.md` is fully checked (16/16). The custom
`checklists/precision-testability.md` remains reviewer-owned with 36 intentionally
unchecked markers and was not modified.

`.specify/extensions.yml` declares `hooks: {}`; no before/after implementation hook
was registered or executed.

## 2. Revision and build

The correction starts at `1f16f44e5665e662a1ef1dbea9fcebb1e00fa9f4` and changes
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
| 1 | `./gradlew :app:testDebugUnitTest :app:assembleDebug --offline --no-daemon --no-configuration-cache --no-watch-fs --console=plain` (`apps/feldexa_app/android`) | `0` | `.dart_tool/t024-kotlin/gradle-race-final.log` | `PASS` |
| 2 | `dexdump -f apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk \| grep Lde/feldexa/app/FeldexaPlugin;` (`.`) | `0` | `console only (not retained)` | `PASS` |

The Gradle run again logged a Kotlin daemon start failure because the daemon state
directory is read-only; Gradle fell back to in-process Kotlin compilation and
completed successfully. This is an environment limitation, not a code result.

## 5. Results

| Area | Observed result |
| --- | --- |
| Terminal/cancel linearization | Cancel blocks during a terminal publish and returns `false` after it; it never returns `true` after a terminal result. Cancel before service completion produces exactly one `PLT-004` result, not success |
| Success race | Deterministic blocking-publisher test: result publish holds the operation state; cancel waits and returns `false` |
| Error race | Same deterministic test with a failing service: error publish holds the state; cancel waits and returns `false` |
| Cancel-wins race | A blocking service is cancelled while running; releasing it publishes only `PLT-004`, no success result |
| Dispose race | `dispose` while a result is blocked in its sink post; a listener attached after dispose receives no event and no replay |
| Replay | Retained-result replay and bounded retention remain green |
| Existing behavior | Start reply, result channel, exact message allowlist, bounded queues, SAVE-006, synchronous methods, and lifecycle tests remain green |
| Test suite | 84/84 host-JVM tests pass; Gradle XML records `tests="84" skipped="0" failures="0" errors="0"` |
| Pre-fix reproduction | The `1f16f44` facade compiled against the new suite failed 4 tests: `cancelAfterSuccessTerminalWaitsForPublishAndReturnsFalse`, `cancelAfterErrorTerminalWaitsForPublishAndReturnsFalse`, `cancelWinsBeforeServiceReturnsAndPublishesOnlyCancellation`, and `disposeDuringResultPublishDoesNotDeliverOrReplay` |
| Android build | `:app:assembleDebug` succeeds; the APK contains `de.feldexa.app.FeldexaPlugin` |
| Runtime | Android emulator and physical-device checks are NOT_RUN; no Android runtime claim is made |

## 6. Performance

No performance claim. The state lock and result-store lock add short critical
sections; no SC-004 or acceptance timing was attempted.

## 7. Limitations

- **Android emulator is NOT_RUN.** No exclusively allocated instrumentation run was used; no engine-level concurrency behavior is claimed.
- **Physical device is NOT_RUN.** No device is attached; no acceptance or performance claim is made.
- **Host-only proof.** The JUnit suite exercises the Kotlin facade/result publisher through injected threading, event, reply, and result seams. It does not prove Flutter engine EventChannel registration, Android lifecycle delivery, Keystore, SAF, PDFBox, ML Kit, or PDFium behavior.
- **No service capability.** T025/T026/T038–T040 still own the services; all non-cancel methods fail closed with `PLT-001` until registered.
- **Result retention is bounded.** An evicted result is unrecoverable; the start reply remains the acceptance proof.
- The Gradle Kotlin-daemon path was blocked by the read-only home directory; in-process compilation succeeded. The toolchain shadows are environment-only and not part of the candidate.
- No checklist item was changed; the custom checklist remains reviewer-owned.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Facade | `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/FeldexaPlugin.kt` | 64078 | `3f5bb8178129b15b9fb9be1a0a272644b43de19384ee09d1672692878d79a38b` |
| Host tests | `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/FeldexaPluginTest.kt` | 58504 | `254d32d1344a44a8e6e6c505af0b98497a206becfa8bbba9879025c19c332659` |
| Channel contract | `specs/001-scanned-form-workflow/contracts/platform-channel.md` | 27947 | `fdcbe14983c14f263e6d053478e13cdd0017edee20a6ed9720a54986ab96c1a1` |
| Evidence index | `specs/001-scanned-form-workflow/reports/README.md` | 27461 | `1c4de2441c20b43134d08c7150359285ff71d80717501eae84cfe47778e26dab` |
| Debug APK | `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 225292355 | `b027929a2421a584616689697db895e582805fb2dfa30942452f8226b292bb9a` |
| Gradle JUnit XML | `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.FeldexaPluginTest.xml` | 9951 | `486e0fa4dba2ceaf2ae42bc7d9f642f22181b391e6072253ad4d982e3d9a412e` |
| Gradle combined log | `.dart_tool/t024-kotlin/gradle-race-final.log` | 31690 | `71d0e4c9053dc359f555325fce368beafea6b546cd651937b60fc7242e8567ca` |
| Standalone JUnit log | `.dart_tool/t024-kotlin/junit-race4.log` | 134 | `3113de58934f0754eb027d69b06949f5cff6abf6ddedfe2dd179206eff4ac510` |
| Pre-fix JUnit log | `.dart_tool/t024-race-old/junit-old.log` | 2054 | `5e2fa37904b7f89f318ff090efacc90dd468348d98a4b9a7502b07df8b720bdb` |

This report's own row is omitted by construction. The pre-existing
`apps/feldexa_app/android/gradlew.bat` change is listed as a dirty file but is not
part of this correction.

## 9. Reproducibility

1. Start from base commit `1f16f44e5665e662a1ef1dbea9fcebb1e00fa9f4` in the isolated worktree.
2. Run `./gradlew :app:testDebugUnitTest :app:assembleDebug` in `apps/feldexa_app/android`; expect `BUILD SUCCESSFUL` and `tests="84" skipped="0" failures="0" errors="0"` for `de.feldexa.app.FeldexaPluginTest`.
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
