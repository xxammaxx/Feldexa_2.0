# 2026-11-15 `NONE` — T026 bounded-history cap safety

| Field | Value |
| --- | --- |
| Evidence class | `NONE` (implementation provenance and host checks) |
| Result | `PASS` |
| Task / issue | `T026` / `#26` |
| Date / timezone | `2026-11-15 Europe/Berlin` |
| Revision | base `d78114fdb703c405fe4692fe287e71095b50fc59`; correction commit `df625d7e938cdc34b2b893191a0dea9a0bbe426a`; this report, its EMULATOR companion, the index rows, the task note, and the committed capacity bundle are the later documentation changes; final candidate SHA in the external attestation |
| External attestation | `worker_done` transport record (candidate SHA, changed files, report bytes/SHA-256); not part of the candidate commit |
| Supersedes for the changed code | `2026-11-15-t026-prune-retry-evidence.md` and its EMULATOR companion remain frozen evidence for `57ce38b` |
| Build identity | `versionName 1.0` (`versionCode 1`), `debug`; app APK `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` SHA-256 `753c9e285b2a847a5d30940730b7321cd20a91f471f00ffe160d24daf2c4bf0d` (216,366,903 bytes); test APK `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` SHA-256 `290b1fca7ffca5913dc91e4bc54a6894723fc8e39672c1799cd0e39cdc338c18` (405,628 bytes) |
| Toolchain | JDK `17.0.20.1`; Gradle `9.3.1`; AGP `9.1.0`; Kotlin `2.4.0`; Flutter `3.47.7`; Dart `3.13.5`; Android platforms `35`/`36`; build-tools `36.0.0`; NDK `28.2.13676358` |
| Input | synthetic UUIDv4 ids, random 32-byte DEKs, synthetic canonical JSON/PDF bytes; no corpus or user data |

## 1. Review finding

The review of `e2775f8` found a capacity hole in the bounded history:
`buildHeadHistory` retained a missing known entry, but
`takeLast(MAX_HEAD_HISTORY = 16)` could evict it while repeated save attempts
followed a failed prune fsync, before `pruneDocumentFromHead` checked
`missingKnown`. If that delete was not durable, a crash could resurrect the
file as untracked and bypass retention permanently.

The finding is confirmed. The old path allowed the head to keep advancing
after a prune fsync failure; after enough saves the oldest missing entry fell
outside the 16-entry window and was written out of the head before the next
prune could confirm its absence.

## 2. Chosen minimal fix: confirm before cap, refuse on failure

`saveRevisionUnlocked` now calls `confirmPendingPruneDurability` **before**
staging the new revision:

```text
current verified head
if any known non-head history entry is missing:
    fsync(revision directory)
        success → cap may drop the confirmed-absent entry
        failure → throw retryable StorageWriteException (SAVE-003)
                  before staging, before any head change
```

Properties:

- the 16-entry bound is unchanged and is never applied to an
  unconfirmed-missing entry;
- the previous head and all revisions remain untouched on refusal;
- the verified head, keep set, unknown-kind entries, and untracked legacy
  files are protected;
- a save-side cap may still drop an **existing** old entry; that file remains
  on disk as a conservative untracked file, so no data is lost;
- the failure is `SAVE-003` with `retryable = true`, consistent with the
  existing write-side fsync vocabulary; the caller can retry once the
  underlying I/O condition clears.

This is the smallest safe change: no new format, no new retention rule, no
silent discard.

### 2.1 Capacity options

The failure condition is a genuine capacity conflict: the owner wants at most
16 history entries, while an unconfirmed delete must stay tracked until its
directory fsync succeeds. The options are documented rather than decided
silently:

| Option | Behavior | Trade-off |
| --- | --- | --- |
| **A (implemented)** | Refuse the save with retryable `SAVE-003` until the directory fsync confirms the missing entries; keep the 16-entry bound | No data loss, no new format, strict bound; autosave is unavailable while the I/O fault persists |
| B | Let `head.fx1` temporarily exceed 16 entries until the fsync succeeds | Preserves availability, but weakens the owner's bound and grows the head |
| C | Persist a separate bounded pending-deletion ledger | Keeps history at 16, but adds a format/owner decision and a second durability surface |
| D | Reserve cap slots for unconfirmed entries and evict only confirmed ones | May still exceed 16 or refuse saves under the same fault |

Option A is chosen because it preserves both safety and the existing bound
without inventing a new format or policy. B–D remain owner decisions if the
availability cost of A is unacceptable. The contract now states this
explicitly.

## 3. Deterministic tests

`EncryptedStorePruneRecoveryTest` has five tests; the new capacity test:

| Test | Result | What it proves |
| --- | --- | --- |
| `historyCapDoesNotEvictUnconfirmedMissingEntry` | `PASS` | One failed prune leaves rev1 missing with full history. **20 further save attempts** (>16) all fail with retryable `SAVE-003`, create no revision file, and leave rev1 in the head. Rev1 is then restored to simulate crash resurrection; a normal save deletes it under confirmed durability and trims. |
| `repeatedFsyncFailureWithoutResurrectionRetriesBeforeHistoryTrim` | `PASS` | Repeated fsync failure without resurrection keeps the entry; a successful retry trims only after confirmation |
| `nextSaveRetainsUnconfirmedMissingHistoryAndTrimsAfterConfirmation` | `PASS` | Save-side rebuild retains the missing entry and trims only after confirmation |
| `pruneFsyncFailureKeepsFullHistoryAndStartupRetries` | `PASS` | Existing resurrection variant remains green |
| `pruneFsyncFailureDuringStartupIsRetryableWithoutTrimmingHistory` | `PASS` | Existing startup variant remains green |

Full host suite: **123 tests** (49 `EncryptedStoreTest`, 9
`EncryptedStoreFaultTest`, 8 `EncryptedStoreReviewTest`, 7
`EncryptedStoreHeadHistoryTest`, 2 `EncryptedStoreOrderingTest`, 5
`EncryptedStorePruneRecoveryTest`, 40 `KeystoreServiceTest`, 3
`InstrumentedKeystoreAliasSafetyTest`), 0 failures, 0 errors, 0 skipped.

## 4. Evidence bundle

`specs/001-scanned-form-workflow/reports/artifacts/t026-prune-cap-2026-11-15/`
contains the manifest, eight JUnit XMLs, redacted instrumentation/device logs,
allocation record, capacity summary with the options table, toolchain, and
`verify.sh`. `./verify.sh` returns `EVIDENCE VERIFY: OK`. Raw logcat,
absolute paths, raw session/runtime ids, and APK binaries are not published.

## 5. Host checks

| # | Command (repo root) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | Gradle `:app:testDebugUnitTest --tests ...EncryptedStorePruneRecoveryTest` | `0` | `build/t026-work/logs/prunecap-tests.log` | `PASS` (5/5) |
| 2 | Gradle `:app:testDebugUnitTest` (full) | `0` | `build/t026-work/logs/prunecap-jvm-and-androidtest.log` | `PASS` (123/123) |
| 3 | Gradle `:app:assembleDebug :app:assembleDebugAndroidTest` | `0` | `build/t026-work/logs/prunecap-assemble.log` | `PASS` |
| 4 | `./verify.sh` in the prune-cap bundle | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t026-prune-cap-2026-11-15/` | `PASS` |

## 6. Artifacts

| Path | Bytes | SHA-256 |
| --- | ---: | --- |
| `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage/EncryptedStore.kt` | 117,326 | `a7788625ed2ab64f3067bb2a788fa971773ad1a79db31d4d99c65aee1fd23df8` |
| `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/storage/EncryptedStorePruneRecoveryTest.kt` | 15,363 | `a899a968fa3543c444c619642d2c0f9f44e825dea38985bf5b8f6573f5db751b` |
| `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/storage/EncryptedStoreInstrumentedTest.kt` | 30,732 | `fad5ec5e29874473788e197a16d3b73b87e7ad90dca1cb9aa20dcb88f5646c27` |
| `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 216,366,903 | `753c9e285b2a847a5d30940730b7321cd20a91f471f00ffe160d24daf2c4bf0d` |
| `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 405,628 | `290b1fca7ffca5913dc91e4bc54a6894723fc8e39672c1799cd0e39cdc338c18` |
| `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.EncryptedStorePruneRecoveryTest.xml` | 1,138 | `ac704406f5ec1fdd713b118fca8a70f98742f518045f8d66b60b8f486867f1e6` |
| `build/t026-work/logs/prunecap-jvm-and-androidtest.log` | 28,674 | `5bea49cd84ef981eed15926328f71e4e602021ef208fe1c0d794171f8ff73caa` |
| `build/t026-work/logs/prunecap-instrumentation-t026.log` | 12,816 | `2c48f5c260d195dd0ab16196f5399c92e44da0250849f38074ed4fba1f80f3a8` |
| `build/t026-work/logs/prunecap-instrumentation-both.log` | 20,981 | `3939316c809abdb35a5608789b9cca420ee9c5411452942f9ec774e77b385bfd` |
| `specs/001-scanned-form-workflow/reports/artifacts/t026-prune-cap-2026-11-15/manifest.json` | 9,032 | `025d459c120b44cc845efbb8277481015f336d7a1f6d9acc98adfa2f90930e05` |

The report itself and its companion are omitted; their bytes/SHA-256 are in
the external attestation.

## 7. Limitations

- A JVM/emulator test cannot simulate physical power loss; the defect and fix
  are proven with injected repeated fsync failures, >16 save attempts, and a
  simulated resurrection.
- The per-aggregate JVM lock serializes this process only; cross-process
  writers are not claimed.
- Option A deliberately refuses a save while the directory fsync cannot
  confirm a pending absence; this is a retryable availability cost, not data
  loss. B–D remain owner decisions.
- Legacy/unknown-kind revisions remain conservatively retained and can exceed
  the five-known-revision target after an upgrade.
- No `DEVICE`, performance, StrongBox, or silicon key-strength claim.
- Host `emulator -accel-check` remains `UNAVAILABLE` in the worker sandbox; the
  EMULATOR companion records the guest evidence and makes no host-KVM claim.
- No push, merge, or self-review.

## 8. Reproducibility

1. Check out base `d78114fdb703c405fe4692fe287e71095b50fc59` and apply
   `df625d7e938cdc34b2b893191a0dea9a0bbe426a`.
2. Use the toolchain and writable build copies recorded in the bundle; run
   `flutter pub get --offline`.
3. Run the Gradle test/assemble commands in §5. Expected 123 tests, zero
   failures.
4. Run the bundle `verify.sh`. Expected `EVIDENCE VERIFY: OK`.
5. Run the EMULATOR steps in the companion report. Expected `19/19` T026 and
   `31/31` including T025.

## 9. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
