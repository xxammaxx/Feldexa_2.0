# 2026-11-15 NONE — T024 start-reply and result-channel protocol

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `PASS` |
| Task / issue | `T024` / #24 |
| Date / timezone | `2026-11-15 10:06 Europe/Berlin` |
| Revision | base commit `e69781d89f7a738dc5f3ad1f23b8ab2b11698773`; tree `dirty`; dirty files: `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/FeldexaPlugin.kt` SHA-256 `a90a6faa6a1773eac40dd56316d1bc5f2a5e207ff88a328796be9e5a1697a0cc`; `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/FeldexaPluginTest.kt` SHA-256 `012611f2fd399d742e839c0588fc08a59289870a664d3e52e35ea885fd26933c`; `specs/001-scanned-form-workflow/contracts/platform-channel.md` SHA-256 `1d7700fc490e5f28a14166ad84cc5a2e2d5d88a24161bc5ef31a2349a523c006`; `specs/001-scanned-form-workflow/reports/README.md` SHA-256 `31e05b520feb4e3fd79ef6816897faac11b98ed4d01734938b768dcce8159b05`; `apps/feldexa_app/android/gradlew.bat` SHA-256 `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62` (pre-existing line-ending change, preserved and not part of this change). This report's own path is excluded from its dirty-file list by construction. The commit containing this report is recorded in the external attestation. |
| External attestation | `worker_done` transport record for this dispatch; it records the candidate SHA, this report's bytes and SHA-256, and the changed-file list. No attestation ref was created. |
| Build identity | Debug APK built from the changed tree; `app-debug.apk` 225289138 bytes, SHA-256 `b03ba021476fd13ddfb60147c837a75cf4a4f83ec28d8268430792364c9c6eb2`; `Lde/feldexa/app/FeldexaPlugin;` confirmed in the APK DEX by `dexdump` |
| Toolchain | Flutter `3.47.7` (framework `abaf9c5237`), Dart `3.13.5`, Kotlin `2.4.0` in Gradle, Gradle wrapper `9.3.1`, JetBrains Runtime `21.0.11` (the host JDK 27 is incompatible with the pinned Gradle 9.3.1), Android SDK platform 36/build-tools 35 for the app, JUnit `4.13.2` |
| Input | validator inputs: owner decision for T024 (2026-11-15); `contracts/platform-channel.md` §1–§12; `contracts/error-catalog.de.md`; `contracts/storage-format.md` §3.1/§5; `tasks.md` T024; no corpus and no fixtures |

## 1. Scope

This report records the T024 owner decision and its implementation on candidate
`e69781d89f7a738dc5f3ad1f23b8ab2b11698773`: a reliable start reply carries
`operationId`; progress follows on `de.feldexa/events`; terminal data follows on the
new `de.feldexa/results` EventChannel. The contract was updated completely rather
than silently changing method responses:

- Nine asynchronous methods: `import.pickAndImport`, `import.verifySource`,
  `store.saveRevision`, `store.writeSignature`, `store.createTemplate`,
  `store.saveTemplateVersion`, `ocr.recognize`, `export.validate`, `export.render`.
- All other methods remain synchronous and keep their existing direct results.
- Start reply: `{ schemaVersion:1, ok:true, data:{ operationId } }`, with no
  method-specific data.
- Terminal result: one `operation.result` map on `de.feldexa/results`, with success
  `data` or the complete `{code,message,details}` error object.
- Race, cancellation, missing listener/replay, error, retention, and lifecycle
  semantics are specified in §2.4, §8.2, §9, and §12 of the contract.
- The previous interpretation that no result-side id was authorized is explicitly
  superseded by the recorded owner decision in §2.4.

No service capability was added. T025/T026/T038–T040 retain their service
ownership. No push, merge, or self-review was performed.

The built-in `checklists/requirements.md` is fully checked (16/16). The custom
`checklists/precision-testability.md` remains reviewer-owned with 36 intentionally
unchecked markers and was not modified.

`.specify/extensions.yml` declares `hooks: {}`; no before/after implementation hook
was registered or executed.

## 2. Revision and build

The change starts at `e69781d89f7a738dc5f3ad1f23b8ab2b11698773` and changes the
facade, its host-JVM tests, the channel contract, and the evidence index. The
pre-existing unstaged `gradlew.bat` line-ending change is preserved and excluded.
The debug APK was rebuilt from the changed tree and contains
`de.feldexa.app.FeldexaPlugin`.

### 2.1 Channels and envelope

| Channel | Type | Role |
| --- | --- | --- |
| `de.feldexa/platform` | MethodChannel | start requests, synchronous results, cancellation |
| `de.feldexa/events` | EventChannel | lifecycle and coalesced progress; never terminal results |
| `de.feldexa/results` | EventChannel | one terminal `operation.result` per accepted async operation, bounded replay |
| `de.feldexa/import` | MethodChannel | activity-bound picker result |

### 2.2 Asynchronous lifecycle

- Start admission happens after payload validation, service lookup, SAVE-006
  admission, and bounded-queue admission. A rejection there is a `PlatformException`
  with no operation and no result event.
- An accepted operation gets exactly one start reply and one terminal result.
  Replay may deliver the same retained result more than once; Dart deduplicates by
  `operationId`.
- The terminal result may precede the start reply when the worker completes
  immediately; Dart buffers unknown ids and reconciles.
- Progress is best-effort/coalesced and never authoritative.
- A queued cancellation removes the task, frees its bounded slot, and publishes
  `PLT-004`; a running cancellation flags cooperative work and publishes `PLT-004`;
  cancellation after the terminal result returns `false`.
- Completed results are retained in a bounded in-memory store (64, oldest evicted),
  replayed on every result-listener attach, not persisted, and cleared on engine
  teardown. A result evicted before any listener attaches is unrecoverable; the
  start reply remains the acceptance proof.
- Activity configuration changes retain the result store; `onDestroy`/engine detach
  cancels workers, clears results, and stops emission. Process death loses in-memory
  results and remains a storage-recovery concern.

### 2.3 Error and result shape

Start rejections use the existing `PlatformException(code, message, details)`.
Post-start failures and cancellation never become `PlatformException`; they are
terminal result errors with `ok:false` and `error:{code,message,details}`. The
existing exact catalog-code, category, and machine-message allowlists still guard
the message and details, so no path, title, OCR text, value, or signature reaches
either channel.

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
| 1 | `./gradlew :app:testDebugUnitTest :app:assembleDebug --offline --no-daemon --no-configuration-cache --no-watch-fs --console=plain` (`apps/feldexa_app/android`) | `0` | `.dart_tool/t024-kotlin/gradle-startresult-final.log` | `PASS` |
| 2 | `dexdump -f apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk \| grep Lde/feldexa/app/FeldexaPlugin;` (`.`) | `0` | `console only (not retained)` | `PASS` |

The Gradle run again logged a Kotlin daemon start failure because the daemon state
directory is read-only; Gradle fell back to in-process Kotlin compilation and
completed successfully. This is an environment limitation, not a code result.

## 5. Results

| Area | Observed result |
| --- | --- |
| Start reply | Async methods return success envelope `data={operationId}` immediately after queue admission; `asyncStartReplyContainsOnlyOperationId` asserts the exact key set |
| Success result | Result channel receives `operation.result` with `schemaVersion`, `operationId`, `ok:true`, and method data |
| Error result | Post-start service failure is a result error `{ok:false,error:{code,message,details}}`; the start reply remains success, no `PlatformException` follows |
| Cancellation | Queued cancel publishes terminal `PLT-004` and frees the slot; cancellation after terminal returns `false` |
| Race | Direct executor result-before-start is retained and reconciled by id; late listener receives replay |
| Missing listener/replay | Result publisher retains bounded results, replays on attach, retains across detach, and clears on dispose |
| Start rejection | Queue overflow is a `PlatformException` with no result; SAVE-006 remains a pre-start rejection |
| Existing behavior | Synchronous methods, payload validation, exact message allowlist, bounded queues, SAVE-006, events, and lifecycle tests remain green |
| Test suite | 80/80 host-JVM tests pass; Gradle XML records `tests="80" skipped="0" failures="0" errors="0"` |
| Pre-change comparison | On `e69781d`, the same store.saveRevision probe printed `afterStart=false` and `afterRun=true data={revisionId=r}`; on the changed tree it prints `afterStart=true data={operationId=…}` and the terminal data moved to the result channel |
| Android build | `:app:assembleDebug` succeeds; the APK contains `de.feldexa.app.FeldexaPlugin` |
| Runtime | Android emulator and physical-device checks are NOT_RUN; no Android runtime claim is made |

## 6. Performance

No performance claim. The start/result split changes delivery, not measured
throughput; no SC-004 or acceptance timing was attempted.

## 7. Limitations

- **Android emulator is NOT_RUN.** No exclusively allocated instrumentation session was used; no engine-level start/result delivery is claimed.
- **Physical device is NOT_RUN.** No device is attached; no acceptance or performance claim is made.
- **Host-only proof.** The JUnit suite exercises the Kotlin facade and result publisher through injected threading/event/reply/result seams. It does not prove Flutter engine EventChannel registration, Android lifecycle delivery, Keystore, SAF, PDFBox, ML Kit, or PDFium behavior.
- **No service capability.** T025/T026/T038–T040 still own the services; all non-cancel methods fail closed with `PLT-001` until registered.
- **Result retention is bounded.** A result evicted before any listener attaches is unrecoverable; the start reply remains the acceptance proof. Results are session-memory only.
- **Synchronous methods unchanged.** Only the nine listed asynchronous methods changed response shape; the contract lists both sets and the Dart adapter owner (T027) must implement the start/result handshake.
- The Gradle Kotlin-daemon path was blocked by the read-only home directory; in-process compilation succeeded. The toolchain shadows are environment-only and not part of the candidate.
- No checklist item was changed; the custom checklist remains reviewer-owned.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Facade | `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/FeldexaPlugin.kt` | 60740 | `a90a6faa6a1773eac40dd56316d1bc5f2a5e207ff88a328796be9e5a1697a0cc` |
| Host tests | `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/FeldexaPluginTest.kt` | 53488 | `012611f2fd399d742e839c0588fc08a59289870a664d3e52e35ea885fd26933c` |
| Channel contract | `specs/001-scanned-form-workflow/contracts/platform-channel.md` | 26740 | `1d7700fc490e5f28a14166ad84cc5a2e2d5d88a24161bc5ef31a2349a523c006` |
| Evidence index | `specs/001-scanned-form-workflow/reports/README.md` | 26956 | `31e05b520feb4e3fd79ef6816897faac11b98ed4d01734938b768dcce8159b05` |
| Debug APK | `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 225289138 | `b03ba021476fd13ddfb60147c837a75cf4a4f83ec28d8268430792364c9c6eb2` |
| Gradle JUnit XML | `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.FeldexaPluginTest.xml` | 9397 | `e19ccfe149a30e0cd94c33783da783b8c10028bbff29b66817a54ef3a818045d` |
| Gradle combined log | `.dart_tool/t024-kotlin/gradle-startresult-final.log` | 31690 | `c5e882be2847a36baaf5b38b7e1583ffd005d038067a9092748fd15674fab89a` |
| Standalone JUnit log | `.dart_tool/t024-kotlin/junit-startresult2.log` | 130 | `5df24b7717d5a74b7e776aec01b014bd80756c476283314a2654a345e56109e2` |
| Pre-change probe log | `.dart_tool/t024-start-probe-old/run.log` | 61 | `dbf151f67e3b00083508df3ad352e2cabd348f146811c47fdc0772ff08615d95` |
| Post-change probe log | `.dart_tool/t024-start-probe-new/run.log` | 142 | `99f19a3614c867e84b8671b03ceeb7906df095a6be10783661060dccf7865e4c` |

This report's own row is omitted by construction. The pre-existing
`apps/feldexa_app/android/gradlew.bat` change is listed as a dirty file but is not
part of this change.

## 9. Reproducibility

1. Start from base commit `e69781d89f7a738dc5f3ad1f23b8ab2b11698773` in the isolated worktree.
2. Run `./gradlew :app:testDebugUnitTest :app:assembleDebug` in `apps/feldexa_app/android`; expect `BUILD SUCCESSFUL` and `tests="80" skipped="0" failures="0" errors="0"` for `de.feldexa.app.FeldexaPluginTest`.
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
