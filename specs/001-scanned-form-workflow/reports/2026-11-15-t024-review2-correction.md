# 2026-11-15 NONE — T024 second quality-review correction

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `PASS` |
| Task / issue | `T024` / #24 |
| Date / timezone | `2026-11-15 03:00 Europe/Berlin` |
| Revision | base commit `96b6e89b52657a7cbaf6a934b70132942e573d9d`; tree `dirty`; dirty files: `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/FeldexaPlugin.kt` SHA-256 `dc552bb9727bdbd7d8e50fcdec513c75f92e9c85feb56e2489ceeb79c7304abc`; `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/FeldexaPluginTest.kt` SHA-256 `44c1765422b65ec08a645e3467060b051941ade57fe2d3ebebc34ef60f12d846`; `specs/001-scanned-form-workflow/reports/README.md` SHA-256 `8a3c85ea15783b7b614a0830666164e6d9bb2160e9fabd3a60975f36b97d0297`; `apps/feldexa_app/android/gradlew.bat` SHA-256 `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62` (pre-existing line-ending change, preserved and not part of this correction). This report's own path is excluded from its dirty-file list by construction. The commit containing this report is recorded in the external attestation. |
| External attestation | `worker_done` transport record for this dispatch; it records the candidate SHA, this report's bytes and SHA-256, and the changed-file list. No attestation ref was created. |
| Build identity | Debug APK built from the corrected tree; `app-debug.apk` 225285451 bytes, SHA-256 `c2997f4657807014318e9de86867b79e43fae06a3561e63d5e5591c266f7f35c`; `Lde/feldexa/app/FeldexaPlugin;` confirmed in the APK DEX by `dexdump` |
| Toolchain | Flutter `3.47.7` (framework `abaf9c5237`), Dart `3.13.5`, Kotlin `2.4.0` in Gradle, Gradle wrapper `9.3.1`, JetBrains Runtime `21.0.11` (the host JDK 27 is incompatible with the pinned Gradle 9.3.1), Android SDK platform 36/build-tools 35 for the app, JUnit `4.13.2` |
| Input | validator inputs: `contracts/platform-channel.md` §2.1, §2.2, §8, §9, §10 and §12; `contracts/storage-format.md` §3.1 and §5; `contracts/ports.md` §3 and SaveRevisionRequest; `contracts/error-catalog.de.md`; `tasks.md` T024/T026; no corpus and no fixtures |

## 1. Scope

This report covers the second quality-review correction of T024 at
`96b6e89b52657a7cbaf6a934b70132942e573d9d`. Four reported cases were audited
against the normative channel/storage contracts and the actual task ownership:

1. The per-aggregate `ArrayDeque` was unbounded, bypassing the §9 bounded-executor
   backpressure; a waiting cancellation only set a flag.
2. The `PlatformFailure` regular expressions accepted content-shaped values such as
   `antrag.secret` or `documentTitle`, contrary to §2.2.
3. The operation id existed only on the §8 progress stream, which is coalesced and
   may be missed, so cancellation reliability had to be examined.
4. Same-document saves were serialized but there was no `SAVE-006` proof as required
   by §9/§12.

Cases 1, 2, and 4 were confirmed and corrected. Case 3 is a real but **unresolved
contract collision**, not something to patch by inventing a result signature: §2.1
and the method tables in §3–§7 define no `operationId` in the method result, while
§8 says progress events may be duplicated or missed and §9 makes cancellation depend
on the id. The facade now emits a **non-coalesced** `operation.progress` start event
before dispatch, which removes the coalescing loss and makes cancellation reliable
whenever the Dart listener is attached before the call. If the listener is not
attached before the call, only the terminal result is authoritative and the id can
still be missed; resolving that would require an authorized result-field or event
contract change, which this task did not invent.

No import, OCR, storage, export, or delivery capability was added. T025/T026/
T038–T040 retain their service ownership. No push, merge, or self-review was
performed.

The built-in `checklists/requirements.md` is fully checked (16/16). The custom
`checklists/precision-testability.md` remains reviewer-owned with 36 intentionally
unchecked markers and was not modified.

`.specify/extensions.yml` declares `hooks: {}`; no before/after implementation hook
was registered or executed.

## 2. Revision and build

The correction starts from the reviewed T024 candidate
`96b6e89b52657a7cbaf6a934b70132942e573d9d`. The only intended source changes are
`FeldexaPlugin.kt` and its host-JVM test file. This report and its README index row
are the documentation changes. The pre-existing unstaged `gradlew.bat` line-ending
change is preserved and excluded from this correction.

The debug APK was rebuilt from the corrected tree and contains
`de.feldexa.app.FeldexaPlugin`.

### 2.1 Corrections applied

| Case | Contract basis | Correction |
| --- | --- | --- |
| 1 | §9: method handlers dispatch to a bounded executor with at most two workers; cancellation is cooperative | `KeyedSerialExecutor` now caps pending work at 8 per aggregate and 32 total. Overflow rejects with the existing `PLT-001`/`capacity` fail-closed result (no new catalog code). A queued operation is removed by `cancel.operation` through `OperationHandle`'s cancel action; the original call returns `PLT-004` and frees the queue slot. |
| 2 | §2.2: `message` is a stable machine key, not a path/name; error details must not contain document content | `PlatformFailure` now has a closed category allowlist and a closed machine-message namespace allowlist in addition to the catalog-code allowlist. `antrag.secret`, `documentTitle`, single-token messages, content-bearing categories, and negative counters are rejected; all current facade/domain categories and namespaces remain accepted. |
| 3 | §2.1/method tables: no result `operationId`; §8: progress may be coalesced/missed; §9: cancellation uses an id | Added non-coalesced `PlatformEventPublisher.emitOperationStarted` with `operation.progress`, `phase:"queued"`, `fraction:0.0`, before dispatch. The id is available to an attached listener before the service starts. No result field was added. The residual listener-not-attached case is recorded as a contract collision above. |
| 4 | §9: a second save for the same document is rejected with `SAVE-006`; §12: two simultaneous same-`expectedHead` saves yield one success and one `SAVE-006` | The facade tracks in-flight `store.saveRevision` calls by `documentId`; a second call is rejected immediately with `SAVE-006` (`concurrentWrite`, retryable) and is not queued. The in-flight marker is released on completion, error, queued cancellation, executor rejection, and dispose. T026 still owns the storage-level `expectedHead` comparison; the facade gate is the §9 channel-level proof. |

### 2.2 Ownership boundaries

- The serialization gate and cancellation registry are channel concerns from §9;
  the storage protocol and `expectedHead` comparison remain T026.
- Per-document OCR still cannot be keyed at the facade: `ocr.recognize` has no
  document identifier in §5. The facade therefore uses one conservative OCR key to
  prevent interleaving; true per-document OCR ordering remains T056/T027.
- Import has no document id before staging, so it uses one import key. This is
  stricter than per-document and is recorded rather than inventing a request field.
- The `SAVE-006` gate is an early channel-level rejection; it does not replace the
  atomic commit/read-back protocol owned by T026.

## 3. Environment

Host: Linux x86_64. The executed checks are Kotlin/JVM compilation, JUnit,
Gradle configuration, Android debug APK assembly, and DEX inspection. Android
emulator and physical-device runtime checks are NOT_RUN: no exclusively allocated
instrumentation session was used and no physical device is attached. No runtime
class block is claimed.

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
| 1 | `./gradlew :app:testDebugUnitTest :app:assembleDebug --offline --no-daemon --no-configuration-cache --no-watch-fs --console=plain` (`apps/feldexa_app/android`) | `0` | `.dart_tool/t024-kotlin/gradle-review2-final.log` | `PASS` |
| 2 | `dexdump -f apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk \| grep Lde/feldexa/app/FeldexaPlugin;` (`.`) | `0` | `console only (not retained)` | `PASS` |

The Gradle run again logged a Kotlin daemon start failure because the daemon state
directory is read-only; Gradle fell back to in-process Kotlin compilation and
completed successfully. This is an environment limitation, not a code result.

## 5. Results

| Area | Observed result |
| --- | --- |
| Backpressure | Eight same-key OCR calls are accepted and the ninth is rejected with `PLT-001`/`capacity`; two keys are accepted and a third distinct key is rejected with the total bound of two; all queues are bounded |
| Queued cancellation | Cancelling a waiting OCR operation removes it, returns `PLT-004` on that operation, frees a queue slot, and the replacement is accepted without exceeding the bound |
| Privacy allowlist | `antrag.secret`, `documentTitle`, single-token messages, content-bearing categories, unknown catalog codes, and negative counters are rejected; accepted domain namespaces/categories remain constructible |
| Start-event reliability | `emitOperationStarted` produces a non-coalesced start event; a queued start plus a drawing update yields two events, not one |
| SAVE-006 | A second `store.saveRevision` for the same document returns `SAVE-006` immediately while the first is in flight; the first completes successfully, the marker is released, and a subsequent save is accepted |
| Existing behavior | Success envelopes, error details/durations, OCR raster lengths, import/export/OCR serialization, service detachment, and lifecycle tests remain green |
| Test suite | 70/70 host-JVM tests pass; Gradle XML records `tests="70" skipped="0" failures="0" errors="0"` |
| Pre-fix reproduction | The `96b6e89` facade compiled against the new suite produced 5 failures in 68 runnable tests: `documentTitleCategoryIsRejected`, `sensitiveMachineMessageNamespaceIsRejected`, `serialQueuesAreBoundedPerAggregate`, `queuedCancellationRemovesTaskAndFreesCapacity`, and `sameDocumentSecondSaveReturnsSave006` |
| Coalescing probe | Against `96b6e89`, a queued progress event followed by a drawing event produced `events=1`; with the new start path the same scenario produces `events=2` |
| Android build | `:app:assembleDebug` succeeds; the APK contains `de.feldexa.app.FeldexaPlugin` |
| Runtime | Android emulator and physical-device checks are NOT_RUN; no Android runtime claim is made |

## 6. Performance

No performance claim. The added bounds change rejection behavior, not measured
throughput; no SC-004 or acceptance timing was attempted.

## 7. Limitations

- **Android emulator is NOT_RUN.** No exclusively allocated instrumentation run was used. No instrumentation evidence is claimed.
- **Physical device is NOT_RUN.** No device is attached; no acceptance or performance claim is made.
- **Host-only proof.** The JUnit suite exercises the Kotlin facade through injected threading/event/reply seams. It does not prove Flutter engine registration, Android lifecycle delivery, Keystore, SAF, PDFBox, ML Kit, or PDFium behavior.
- **No service capability.** T025/T026/T038–T040 still own the services; all non-cancel methods fail closed with `PLT-001` until registered.
- **Contract collision remains.** If the Dart listener is not attached before the call, the non-coalesced start event can still be missed; §2.1/method tables authorize no result `operationId`, so an absolute guarantee requires a contract amendment. No result signature was invented.
- **SAVE-006 scope.** The facade rejects a concurrent same-document save; the storage-level `expectedHead` comparison and atomic commit are T026.
- **OCR per-document ordering.** The facade can only use a conservative global OCR key because the OCR request has no document id.
- The Gradle Kotlin-daemon path was blocked by the read-only home directory; in-process compilation succeeded. The toolchain shadows are environment-only and not part of the candidate.
- No checklist item was changed; the custom checklist remains reviewer-owned.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Facade | `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/FeldexaPlugin.kt` | 55861 | `dc552bb9727bdbd7d8e50fcdec513c75f92e9c85feb56e2489ceeb79c7304abc` |
| Host tests | `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/FeldexaPluginTest.kt` | 44280 | `44c1765422b65ec08a645e3467060b051941ade57fe2d3ebebc34ef60f12d846` |
| Evidence index | `specs/001-scanned-form-workflow/reports/README.md` | 26019 | `8a3c85ea15783b7b614a0830666164e6d9bb2160e9fabd3a60975f36b97d0297` |
| Debug APK | `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 225285451 | `c2997f4657807014318e9de86867b79e43fae06a3561e63d5e5591c266f7f35c` |
| Gradle JUnit XML | `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.FeldexaPluginTest.xml` | 8232 | `9c64700167be990e58a61a0038ccc79356c3b7d4138428f03c157014ef74113c` |
| Gradle combined log | `.dart_tool/t024-kotlin/gradle-review2-final.log` | 25736 | `4b65d8cbbfd6a9757d5834073cac27ed7978b3094fd605bfc0b12f10aec5985d` |
| Standalone JUnit log | `.dart_tool/t024-kotlin/junit-final4.log` | 120 | `e08acc73ac3a23fcb0577dcdd0fc9f0cf2597cd5aa6d27db042b885bca0e0573` |
| Pre-fix JUnit log | `.dart_tool/t024-review2-old/junit-old.log` | 2513 | `858cb79fb141365585e22249cf389dcf1d20d5f1c461c4562731e6d5c99ee185` |
| Pre-fix coalescing probe | `.dart_tool/t024-review2-old/probe-old.log` | 9 | `c29a59d9f724b6d1fd357cd3573b21beb93ec80d88689781351219781d662fe9` |
| Post-fix coalescing probe | `.dart_tool/t024-review2-old/probe-new.log` | 9 | `3f3a75936964da1e74a49c1740bc629cbd1acf2eb0c88b521e1af0f787fb2d53` |

This report's own row is omitted by construction. The pre-existing
`apps/feldexa_app/android/gradlew.bat` change is listed as a dirty file but is not
part of this correction.

## 9. Reproducibility

1. Start from base commit `96b6e89b52657a7cbaf6a934b70132942e573d9d` in the isolated worktree.
2. Run `./gradlew :app:testDebugUnitTest :app:assembleDebug` in `apps/feldexa_app/android`; expect `BUILD SUCCESSFUL` and `tests="70" skipped="0" failures="0" errors="0"` for `de.feldexa.app.FeldexaPluginTest`.
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
