# 2026-11-15 `NONE` — T026 bounded head history and automatic retention

| Field | Value |
| --- | --- |
| Evidence class | `NONE` (implementation provenance and host checks) |
| Result | `PASS` |
| Task / issue | `T026` / `#26` |
| Date / timezone | `2026-11-15 Europe/Berlin` |
| Revision | base `d78114fdb703c405fe4692fe287e71095b50fc59`; implementation commit `c30cb669c1a23f4eaea13ad9da42f775b4dd4935`; this report, its EMULATOR companion, the index rows, the task note, and the committed head-history bundle are the later documentation changes; final candidate SHA in the external attestation |
| External attestation | `worker_done` transport record (candidate SHA, changed files, report bytes/SHA-256); not part of the candidate commit |
| Supersedes for retention | `2026-11-15-t026-pruning-contract-gap.md` (contract-gap analysis for `3197ca3`) and the obsolete underdetermination tests are historical; the owner's decision resolves the gap and this report records the implementation |
| Build identity | `versionName 1.0` (`versionCode 1`), `debug`; app APK `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` SHA-256 `b35ba8609ba126ea70d914073f7183de7f6899231ba8dd8a03d596762cdc2535` (216,365,872 bytes); test APK `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` SHA-256 `b9102dd9cc89b9f1a07c706a8850eec0a855de53a304c7177af7045099f1058f` (401,996 bytes) |
| Toolchain | JDK `17.0.20.1`; Gradle `9.3.1`; AGP `9.1.0`; Kotlin `2.4.0`; Flutter `3.47.7`; Dart `3.13.5`; Android platforms `35`/`36`; build-tools `36.0.0`; NDK `28.2.13676358` |
| Input | synthetic UUIDv4 ids, random 32-byte DEKs, synthetic canonical JSON/PDF bytes; no corpus or user data |

## 1. Owner decision and scope

The owner decided: a **bounded history in `head.fx1`**, storing revision id,
kind, and order atomically with the head; entries without a known kind are
handled conservatively. After a durable, read-back-verified commit the store
applies **last 3 autosaves + newest explicit + newest recovery**, always
protecting the verified head. No further product decision was invented.

This report records the implementation, contract updates, deterministic host
tests, and the EMULATOR companion. It replaces the open contract-gap analysis
for `3197ca3`; the gap report remains as frozen historical evidence.

## 2. Head history and commit protocol

`head.fx1` gains:

```json
"history": [
  {"revisionId": "<uuid>", "kind": "autosave|explicit|recovery|null"}
]
```

- **Order:** oldest first.
- **Bound:** at most 16 entries (`EncryptedStore.MAX_HEAD_HISTORY`); the cap
  bounds head size. Older known entries that fall outside the cap become
  untracked and are therefore retained by the pruner.
- **Build:** previous head history (only entries whose revision files still
  exist) → the previous head's own `{revisionId, kind}` refreshed →
  the new revision's `{revisionId, kind}`.
- **Atomicity:** the history is part of the encrypted, checksum-protected head
  that is staged, verified, promoted, and read back by the existing protocol.
  The revision ordering mtime is flushed before the rename (previous
  correction); the head carries the durable order explicitly.
- **Legacy:** a head without `history` decodes to an empty history. It is valid
  and prunes nothing. An unknown kind token/null is retained as unknown, never
  inferred from content or file order.

### 2.1 Automatic retention

After step 7 read-back succeeds, `pruneDocumentFromHead`:

1. verifies the head revision hash itself;
2. computes
   `keep = last 3 known autosaves + newest known explicit + newest known recovery + head`;
3. deletes only `rev/<uuid>.fx1` files that are **recorded in history with a
   known kind** and not in `keep`;
4. never deletes the verified head, unknown-kind entries, or untracked legacy
   files;
5. atomically rewrites `head.fx1` with the surviving history entries (missing
   deleted entries removed); a failed trim keeps the full history and is
   reconciled on the next save/startup.

A legacy head without history deletes nothing; template versions are not pruned
by normal saves. `CommitReceipt.prunedRevisions` reports the count.

### 2.2 Crash, restart, and races

- Head and history are committed atomically; a crash before the head promote
  leaves the previous head intact.
- A crash after the durable head but before prune is reconciled by
  `startupRecovery`: readable documents apply the same policy from the
  verified head history, count deletions in `RecoveryReport.prunedRevisions`,
  and trim missing entries.
- A crash during deletion leaves a subset deleted; the next startup/save
  retries the remaining known non-kept files. A failed `delete` is
  conservative and retried; it never causes a false save failure.
- The per-aggregate JVM lock wraps commit + prune + load/delete/recovery, so
  save/prune/read races in this process are serialized. Cross-process writers
  are not claimed.
- The verified head is protected in every path: `computeKeepSet` adds it and
  the deletion loop explicitly skips it.

## 3. Contract and task updates

- `contracts/storage-format.md` §3.1 step 5 (head schema), step 8 (automatic
  policy, unknown/legacy retention, atomic history trim), §4 step 2 (startup
  reconciliation), §6 (bounded known retention; legacy can exceed five).
- `data-model.md` §3.12 retention note (head history, unknown conservative,
  templates unaffected).
- `contracts/ports.md` §2.4 (`saveRevision` maintains/applies the history and
  policy after verified read-back; no caller history).
- `contracts/platform-channel.md` §4 (`saveRevision` response
  `prunedRevisions`; `loadDocument.head.history` bounded and optional).
- `tasks.md` T026 marked complete for the owner decision; T090 remains save
  orchestration, not a retention owner.

No contract requires a new port method or a caller-supplied keep set. The
canonical `RevisionContent` payload is unchanged; provenance now lives in the
head, not in the revision plaintext.

## 4. Deterministic host tests

`EncryptedStoreHeadHistoryTest` (new, 7 tests):

| Test | Result | Coverage |
| --- | --- | --- |
| `headStoresBoundedKnownHistoryInCommitOrder` | `PASS` | ids/kinds/order in head, 16-entry bound, revision payload has no kind |
| `saveAppliesPolicyAfterVerifiedCommit` | `PASS` | last 3 autosave, newest explicit, newest recovery; older explicit deleted; head protected |
| `unknownHistoryEntriesAreRetainedConservatively` | `PASS` | null-kind entry survives prune |
| `legacyHeadWithoutHistoryKeepsUntrackedRevisions` | `PASS` | legacy head prunes nothing; next save learns only current + new |
| `crashBeforePruneIsReconciledOnStartup` | `PASS` | startup deletes stale known non-keep and keeps head/keep |
| `historyStaysBoundedAfterManyCommits` | `PASS` | 20 commits; history ≤16; only policy files survive |
| `deleteFailureIsConservativeAndRetriedOnNextCommit` | `PASS` | failed delete retains data and is retried |

Existing tests were adjusted for the now-real policy: the initial revision in
manual-prune tests is `autosave`, and the fallback test keeps all three
revisions. The obsolete `EncryptedStoreRetentionTest` underdetermination file
was removed because the owner decision makes kinds persisted.

Full host suite: **118 tests** (49 `EncryptedStoreTest`, 9
`EncryptedStoreFaultTest`, 8 `EncryptedStoreReviewTest`, 7
`EncryptedStoreHeadHistoryTest`, 2 `EncryptedStoreOrderingTest`, 40
`KeystoreServiceTest`, 3 `InstrumentedKeystoreAliasSafetyTest`), 0 failures,
0 errors, 0 skipped.

## 5. Evidence bundle

`specs/001-scanned-form-workflow/reports/artifacts/t026-head-history-2026-11-15/`
contains the manifest, seven JUnit XMLs, redacted instrumentation/device logs,
allocation record, policy summary, toolchain, and `verify.sh`. `./verify.sh`
returns `EVIDENCE VERIFY: OK`. Raw logcat, absolute paths, raw session/runtime
ids, and APK binaries are not published.

## 6. Host checks

| # | Command (repo root) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | Gradle `:app:testDebugUnitTest` | `0` | `build/t026-work/logs/headhistory-jvm-full.log` | `PASS` (118/118) |
| 2 | Gradle `:app:assembleDebug :app:assembleDebugAndroidTest` | `0` | `build/t026-work/logs/headhistory-assemble.log` | `PASS` |
| 3 | `./verify.sh` in the head-history bundle | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t026-head-history-2026-11-15/` | `PASS` |
| 4 | APK identity recheck | `0` | local build output | `PASS` |

## 7. Artifacts

| Path | Bytes | SHA-256 |
| --- | ---: | --- |
| `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage/EncryptedStore.kt` | 114,523 | `32d2650c470dade3d3f25155484c38c57509b94655de58dbe34524ac2f66309e` |
| `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/storage/EncryptedStoreHeadHistoryTest.kt` | 15,621 | `17d85d2c2e55323b08da5284c4007e85800e96a355acfc133b8edabf3cbc5a2a` |
| `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/storage/EncryptedStoreInstrumentedTest.kt` | 23,790 | `821acd4fa4e37e812db3f47d014d7e13adc8b593788060ffae6731e05aebfcfd` |
| `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 216,365,872 | `b35ba8609ba126ea70d914073f7183de7f6899231ba8dd8a03d596762cdc2535` |
| `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 401,996 | `b9102dd9cc89b9f1a07c706a8850eec0a855de53a304c7177af7045099f1058f` |
| `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.EncryptedStoreHeadHistoryTest.xml` | 1,333 | `fd5d5d20be6825d6fe3a1344f86a84aef77c1d4bc2decdcf7c73cab8c43a5f39` |
| `build/t026-work/logs/headhistory-jvm-full.log` | 16,255 | `9434126f8d8446e8adaa739fef77f9380b97bbdedd564b5dff5c41d4a39ade92` |
| `build/t026-work/logs/headhistory-instrumentation-t026.log` | 10,758 | `266e5a76f35f2c50eea081b28d6fab0be5cf0f52dd36cbdf349040dd3f00bd7a` |
| `build/t026-work/logs/headhistory-instrumentation-both.log` | 18,924 | `f2dda0ca40d2778f1cebfad4d558cdca1b6ee00b8c308ca04652ce56094f411f` |
| `specs/001-scanned-form-workflow/reports/artifacts/t026-head-history-2026-11-15/manifest.json` | 8,562 | `54b9756c9bb249c0630fb16c1b7f75f5fe5122581f0464142357a788a1fe83ac` |

The report itself and its companion are omitted; their bytes/SHA-256 are in
the external attestation.

## 8. Limitations

- The per-aggregate JVM lock serializes one process; cross-process writers are
  not claimed.
- Legacy/unknown-kind revisions are retained conservatively, so an upgraded
  document can exceed the five-known-revision target until those entries are
  classified by a future decision. This is intentional no-data-loss behavior.
- A JVM/emulator run cannot simulate physical power loss; crash reconciliation
  is tested through the durable-head/prune ordering and injected failures.
- Template versions are not pruned by normal saves.
- No `DEVICE`, performance, StrongBox, or silicon key-strength claim.
- Host `emulator -accel-check` remains `UNAVAILABLE` in the worker sandbox; the
  EMULATOR companion records the guest evidence and makes no host-KVM claim.
- No push, merge, or self-review.

## 9. Reproducibility

1. Check out base `d78114fdb703c405fe4692fe287e71095b50fc59` and apply
   `c30cb669c1a23f4eaea13ad9da42f775b4dd4935`.
2. Use the toolchain and writable build copies recorded in the bundle; run
   `flutter pub get --offline`.
3. Run the Gradle test/assemble commands in §6. Expected 118 tests, zero
   failures.
4. Run the bundle `verify.sh`. Expected `EVIDENCE VERIFY: OK`.
5. Run the EMULATOR steps in the companion report. Expected `16/16` T026 and
   `28/28` including T025.

## 10. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
