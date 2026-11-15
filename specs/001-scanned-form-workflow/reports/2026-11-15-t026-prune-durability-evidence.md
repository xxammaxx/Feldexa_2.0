# 2026-11-15 `NONE` — T026 prune-delete durability

| Field | Value |
| --- | --- |
| Evidence class | `NONE` (implementation provenance and host checks) |
| Result | `PASS` |
| Task / issue | `T026` / `#26` |
| Date / timezone | `2026-11-15 Europe/Berlin` |
| Revision | base `d78114fdb703c405fe4692fe287e71095b50fc59`; correction commit `0c75c57fdaa592c8a5ec4ccf8339e8b31e800965`; this report, its EMULATOR companion, the index rows, the task note, and the committed prune-durability bundle are the later documentation changes; final candidate SHA in the external attestation |
| External attestation | `worker_done` transport record (candidate SHA, changed files, report bytes/SHA-256); not part of the candidate commit |
| Supersedes for the changed code | `2026-11-15-t026-head-history-evidence.md` and its EMULATOR companion remain frozen evidence for `c30cb66`/`ff8f7fb` |
| Build identity | `versionName 1.0` (`versionCode 1`), `debug`; app APK `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` SHA-256 `2a7b04d6e7394f29c2a8cccffd34d20eac8cd011159eb6ab8e1210bf2b43f04e` (216,366,371 bytes); test APK `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` SHA-256 `ce28c7357d4a0cbbac64c58b8d0ea47384bca4ba1772950589fe3b41e764ffe0` (403,147 bytes) |
| Toolchain | JDK `17.0.20.1`; Gradle `9.3.1`; AGP `9.1.0`; Kotlin `2.4.0`; Flutter `3.47.7`; Dart `3.13.5`; Android platforms `35`/`36`; build-tools `36.0.0`; NDK `28.2.13676358` |
| Input | synthetic UUIDv4 ids, random 32-byte DEKs, synthetic canonical JSON/PDF bytes; no corpus or user data |

## 1. Security finding

The review of `ff8f7fb` found that `pruneDocumentFromHead`
(`EncryptedStore.kt:1202–1209` at that revision) swallowed a
`fsyncDirectory` failure after deleting known non-kept revisions, then
filtered history by visible files. Save and startup wrote that shortened
history. After a crash, a non-durable delete could reappear as an untracked
file and bypass retention permanently.

The finding is confirmed:

- `io.delete(file)` is a namespace operation; the delete remains non-durable
  until the revision directory is fsynced;
- the old catch ignored that fsync failure and still returned `remaining`
  history computed from currently visible files;
- the next head write persisted that shortened history, so a resurrected file
  had no history entry and the conservative pruner would never delete it.

## 2. Correction

`PruneResult` now carries `deletesDurable`. The prune path is:

```text
delete known non-kept revision files
fault point PRUNE_FSYNC
fsync(revision directory)
  success → compute remaining history from visible files → trim head
  failure → return the complete head.history with deletesDurable=false
            → no trim, no durable-prune count, retry on next startup/save
```

Save and startup behavior:

- `saveRevision` passes its transaction id, uses
  `prunedRevisions = if (deletesDurable) deleted else 0`, and only rewrites the
  trimmed head when the history is durable-confirmed;
- `startupRecovery` uses the same rule; `RecoveryReport.prunedRevisions` counts
  only confirmed durable deletes;
- the verified head, policy keep set, unknown-kind history entries, and
  untracked legacy files remain protected;
- if the fsync fault is injected, the history stays complete even though the
  file is gone from the current namespace, so a simulated crash resurrection
  is still tracked and retried.

This is the minimal fix: no format change, no new retention decision, and the
owner's policy/head protection remain unchanged. `contracts/storage-format.md`
§3.1 step 8 and §4 step 2, plus `data-model.md` §3.12, now state that history
may be shortened only after the delete-directory fsync succeeds.

## 3. Deterministic tests

New `EncryptedStorePruneRecoveryTest` (2 tests):

| Test | Result | What it proves |
| --- | --- | --- |
| `pruneFsyncFailureKeepsFullHistoryAndStartupRetries` | `PASS` | A save-triggered prune deletes rev1, injects `PRUNE_FSYNC` failure, keeps full history, reports 0 pruned; rev1 bytes are restored to simulate crash resurrection; the next startup deletes rev1 and only then trims history |
| `pruneFsyncFailureDuringStartupIsRetryableWithoutTrimmingHistory` | `PASS` | A startup prune fails its fsync, reports 0 durable prunes and keeps the stale entry; restoring the file and running startup again retries, deletes, and trims |

The existing head-history tests (`crashBeforePruneIsReconciledOnStartup`,
`deleteFailureIsConservativeAndRetriedOnNextCommit`) still pass. Full host
suite: **120 tests** (49 `EncryptedStoreTest`, 9 `EncryptedStoreFaultTest`, 8
`EncryptedStoreReviewTest`, 7 `EncryptedStoreHeadHistoryTest`, 2
`EncryptedStoreOrderingTest`, 2 `EncryptedStorePruneRecoveryTest`, 40
`KeystoreServiceTest`, 3 `InstrumentedKeystoreAliasSafetyTest`), 0 failures,
0 errors, 0 skipped.

## 4. Evidence bundle

`specs/001-scanned-form-workflow/reports/artifacts/t026-prune-durability-2026-11-15/`
contains the manifest, eight JUnit XMLs, redacted instrumentation/device logs,
allocation record, prune-durability summary, toolchain, and `verify.sh`.
`./verify.sh` returns `EVIDENCE VERIFY: OK`. Raw logcat, absolute paths, raw
session/runtime ids, and APK binaries are not published.

## 5. Host checks

| # | Command (repo root) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | Gradle `:app:testDebugUnitTest --tests ...EncryptedStorePruneRecoveryTest` | `0` | `build/t026-work/logs/prunefsync-tests.log` | `PASS` (2/2) |
| 2 | Gradle `:app:testDebugUnitTest` (full) | `0` | `build/t026-work/logs/prunefsync-jvm-and-androidtest.log` | `PASS` (120/120) |
| 3 | Gradle `:app:assembleDebug :app:assembleDebugAndroidTest` | `0` | `build/t026-work/logs/prunefsync-assemble.log` | `PASS` |
| 4 | `./verify.sh` in the prune-durability bundle | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t026-prune-durability-2026-11-15/` | `PASS` |

## 6. Artifacts

| Path | Bytes | SHA-256 |
| --- | ---: | --- |
| `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage/EncryptedStore.kt` | 115,093 | `3c3c135ab3144f54157d54db311d6c10c17f80ce64f9e170705de4daa500bd68` |
| `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/storage/EncryptedStorePruneRecoveryTest.kt` | 7,391 | `57b8be735212e16ba40a50058dcf2c06a49794d9f62ee2a6654b0796f4e95a10` |
| `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/storage/EncryptedStoreInstrumentedTest.kt` | 25,980 | `6d575624f86ab3088c8c6959a2a4b53302effbc1fefbbd4d7ad377c12ba02420` |
| `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 216,366,371 | `2a7b04d6e7394f29c2a8cccffd34d20eac8cd011159eb6ab8e1210bf2b43f04e` |
| `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 403,147 | `ce28c7357d4a0cbbac64c58b8d0ea47384bca4ba1772950589fe3b41e764ffe0` |
| `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.EncryptedStorePruneRecoveryTest.xml` | 660 | `a7735be139e899636aca1e3dd83b37cb3f4cc19eade94abe63e9cf44d7e0b712` |
| `build/t026-work/logs/prunefsync-jvm-and-androidtest.log` | 22,657 | `2c363c59d6630c3e6aa02b9decd8bc0090f4dd085b14caa712ac5dea3dc54c86` |
| `build/t026-work/logs/prunefsync-instrumentation-t026.log` | 11,440 | `41b616958d2dcbf480161e5a5c264259a66e29ab628aa50680239824933d0309` |
| `build/t026-work/logs/prunefsync-instrumentation-both.log` | 19,605 | `b0ef4aa8de82b982e30db826838347d49c95dcfe09de066a20e856cfd6b3a40e` |
| `specs/001-scanned-form-workflow/reports/artifacts/t026-prune-durability-2026-11-15/manifest.json` | 9,036 | `baced669cfe8962674853a7145ca57e61b23ef996e24f4aa3b5993f48c7465a4` |

The report itself and its companion are omitted; their bytes/SHA-256 are in
the external attestation.

## 7. Limitations

- A JVM/emulator test cannot simulate physical power loss; the defect and fix
  are proven by injected fsync failure plus file resurrection and the enforced
  retry/trim order.
- The per-aggregate JVM lock serializes this process only; cross-process
  writers are not claimed.
- Legacy/unknown-kind revisions remain conservatively retained and can exceed
  the five-known-revision target after an upgrade.
- No `DEVICE`, performance, StrongBox, or silicon key-strength claim.
- Host `emulator -accel-check` remains `UNAVAILABLE` in the worker sandbox; the
  EMULATOR companion records the guest evidence and makes no host-KVM claim.
- No push, merge, or self-review.

## 8. Reproducibility

1. Check out base `d78114fdb703c405fe4692fe287e71095b50fc59` and apply
   `0c75c57fdaa592c8a5ec4ccf8339e8b31e800965`.
2. Use the toolchain and writable build copies recorded in the bundle; run
   `flutter pub get --offline`.
3. Run the Gradle test/assemble commands in §5. Expected 120 tests, zero
   failures.
4. Run the bundle `verify.sh`. Expected `EVIDENCE VERIFY: OK`.
5. Run the EMULATOR steps in the companion report. Expected `17/17` T026 and
   `29/29` including T025.

## 9. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
