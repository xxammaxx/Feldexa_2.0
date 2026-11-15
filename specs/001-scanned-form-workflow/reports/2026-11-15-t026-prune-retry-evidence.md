# 2026-11-15 `NONE` — T026 prune retry without resurrection

| Field | Value |
| --- | --- |
| Evidence class | `NONE` (implementation provenance and host checks) |
| Result | `PASS` |
| Task / issue | `T026` / `#26` |
| Date / timezone | `2026-11-15 Europe/Berlin` |
| Revision | base `d78114fdb703c405fe4692fe287e71095b50fc59`; correction commit `57ce38bf0d1f9487926c8b7d775397604f7f125d`; this report, its EMULATOR companion, the index rows, the task note, and the committed prune-retry bundle are the later documentation changes; final candidate SHA in the external attestation |
| External attestation | `worker_done` transport record (candidate SHA, changed files, report bytes/SHA-256); not part of the candidate commit |
| Supersedes for the changed code | `2026-11-15-t026-prune-durability-evidence.md` and its EMULATOR companion remain frozen evidence for `0c75c57` |
| Build identity | `versionName 1.0` (`versionCode 1`), `debug`; app APK `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` SHA-256 `518a0a37fe50e956482d0d313b16c953843f6519b18eb22700ede9c920d51860` (216,366,594 bytes); test APK `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` SHA-256 `00f73e17e6f734a8260baa139f3e4880e056b8979038041d44d5723b5e6e3452` (403,990 bytes) |
| Toolchain | JDK `17.0.20.1`; Gradle `9.3.1`; AGP `9.1.0`; Kotlin `2.4.0`; Flutter `3.47.7`; Dart `3.13.5`; Android platforms `35`/`36`; build-tools `36.0.0`; NDK `28.2.13676358` |
| Input | synthetic UUIDv4 ids, random 32-byte DEKs, synthetic canonical JSON/PDF bytes; no corpus or user data |

## 1. Review finding

The review of `0785e5c` found a second-order gap in the prune-durability fix:
after a `PRUNE_FSYNC` failure the history stayed complete, but the file was
already missing from the namespace. On the next retry, `deleted == 0`, so the
old code skipped the directory fsync, filtered the missing entry, and returned
`deletesDurable = true`; save/startup then trimmed the head. Without a crash
resurrection the unconfirmed delete was forgotten, so a later crash could
still resurrect an untracked file.

The finding is confirmed. A second path had the same effect: the save-side
`buildHeadHistory` dropped every entry whose file did not exist **before** the
prune, so the next save could also forget the unconfirmed delete before any
fsync.

## 2. Correction

Two minimal changes:

1. **Prune retry fsync.** `pruneDocumentFromHead` now computes `missingKnown`
   after the delete loop. It performs the revision-directory fsync when
   `deleted > 0` **or** any known non-head history entry is missing. If that
   fsync fails, or the revision directory is absent, it returns the complete
   history with `deletesDurable = false`; no trim and no durable-prune count.
2. **History rebuild.** `buildHeadHistory` retains every previous historical
   entry, including a missing file. Only the pruner drops a missing entry,
   and only after a successful directory durability confirmation.

The verified head, policy keep set, unknown-kind entries, and untracked legacy
files remain protected. The change is a confirmation-order fix, not a new
retention decision.

`contracts/storage-format.md` §3.1 step 8 and `data-model.md` §3.12 now state
that a retry which deletes nothing because the file is already missing still
confirms directory durability before dropping the entry, and that a save-side
rebuild retains unconfirmed entries.

## 3. Deterministic tests

`EncryptedStorePruneRecoveryTest` now has four tests; the two new ones cover
the exact no-resurrection path:

| Test | Result | What it proves |
| --- | --- | --- |
| `repeatedFsyncFailureWithoutResurrectionRetriesBeforeHistoryTrim` | `PASS` | Save prunes rev1 with an injected fsync failure; the file is **not** restored; a second startup with the same fault still keeps rev1 in history; a normal startup confirms the directory fsync and only then trims rev1 |
| `nextSaveRetainsUnconfirmedMissingHistoryAndTrimsAfterConfirmation` | `PASS` | After the failed prune, a normal next save rebuilds history with the still-missing rev1, prunes, confirms the fsync, and only then trims; the older non-kept autosave is also handled by policy |
| `pruneFsyncFailureKeepsFullHistoryAndStartupRetries` | `PASS` | Existing crash-resurrection variant remains green |
| `pruneFsyncFailureDuringStartupIsRetryableWithoutTrimmingHistory` | `PASS` | Existing startup-failure variant remains green |

Full host suite: **122 tests** (49 `EncryptedStoreTest`, 9
`EncryptedStoreFaultTest`, 8 `EncryptedStoreReviewTest`, 7
`EncryptedStoreHeadHistoryTest`, 2 `EncryptedStoreOrderingTest`, 4
`EncryptedStorePruneRecoveryTest`, 40 `KeystoreServiceTest`, 3
`InstrumentedKeystoreAliasSafetyTest`), 0 failures, 0 errors, 0 skipped.

## 4. Evidence bundle

`specs/001-scanned-form-workflow/reports/artifacts/t026-prune-retry-2026-11-15/`
contains the manifest, eight JUnit XMLs, redacted instrumentation/device logs,
allocation record, retry summary, toolchain, and `verify.sh`. `./verify.sh`
returns `EVIDENCE VERIFY: OK`. Raw logcat, absolute paths, raw session/runtime
ids, and APK binaries are not published.

## 5. Host checks

| # | Command (repo root) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | Gradle `:app:testDebugUnitTest --tests ...EncryptedStorePruneRecoveryTest` | `0` | `build/t026-work/logs/prunefsync-retry-tests.log` | `PASS` (4/4) |
| 2 | Gradle `:app:testDebugUnitTest` (full) | `0` | `build/t026-work/logs/prunefsync2-jvm-and-androidtest.log` | `PASS` (122/122) |
| 3 | Gradle `:app:assembleDebug :app:assembleDebugAndroidTest` | `0` | `build/t026-work/logs/prunefsync2-assemble.log` | `PASS` |
| 4 | `./verify.sh` in the prune-retry bundle | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t026-prune-retry-2026-11-15/` | `PASS` |

## 6. Artifacts

| Path | Bytes | SHA-256 |
| --- | ---: | --- |
| `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage/EncryptedStore.kt` | 115,701 | `aefe2d04453f365bbe17c4c018bed80cb99c2ac2274045a81dd9bdee262373f4` |
| `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/storage/EncryptedStorePruneRecoveryTest.kt` | 12,052 | `6741fd1bbd75adaa86c3b23503d02f1b53afdda08e82376309e73012f20d9c60` |
| `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/storage/EncryptedStoreInstrumentedTest.kt` | 28,077 | `85bc22a5589805f85c94f3ce1b6f28a563838a54045067cefa16a1baaebd9242` |
| `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 216,366,594 | `518a0a37fe50e956482d0d313b16c953843f6519b18eb22700ede9c920d51860` |
| `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 403,990 | `00f73e17e6f734a8260baa139f3e4880e056b8979038041d44d5723b5e6e3452` |
| `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.EncryptedStorePruneRecoveryTest.xml` | 991 | `714c967742d1b682aa60e1fa34f5ce76cda996160a9cdff213d64c8dabc5caff` |
| `build/t026-work/logs/prunefsync2-jvm-and-androidtest.log` | 22,655 | `72c0cddcb554de2481f4c3e28462e79454333db001b034e8c149cfd0cf8643c4` |
| `build/t026-work/logs/prunefsync2-instrumentation-t026.log` | 12,130 | `25ca6f5e559fe4d19519b4b1aae9cc10a2d22f479b42bc8be907c5639e5c30db` |
| `build/t026-work/logs/prunefsync2-instrumentation-both.log` | 20,296 | `45c4fb76860a9d889f5f5171b4d1577829254dc9d39072ed257ee3f39acf51de` |
| `specs/001-scanned-form-workflow/reports/artifacts/t026-prune-retry-2026-11-15/manifest.json` | 9,013 | `6432a24060a20d4553a3bb65eed7ad2b45e838f389b762b860e8fd1589eec11e` |

The report itself and its companion are omitted; their bytes/SHA-256 are in
the external attestation.

## 7. Limitations

- A JVM/emulator test cannot simulate physical power loss; the defect and fix
  are proven with injected repeated fsync failures and the no-resurrection
  state, not a power-cut.
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
   `57ce38bf0d1f9487926c8b7d775397604f7f125d`.
2. Use the toolchain and writable build copies recorded in the bundle; run
   `flutter pub get --offline`.
3. Run the Gradle test/assemble commands in §5. Expected 122 tests, zero
   failures.
4. Run the bundle `verify.sh`. Expected `EVIDENCE VERIFY: OK`.
5. Run the EMULATOR steps in the companion report. Expected `18/18` T026 and
   `30/30` including T025.

## 9. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
