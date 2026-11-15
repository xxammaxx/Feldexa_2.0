# 2026-11-15 `NONE` — T026 revision-order mtime durability

| Field | Value |
| --- | --- |
| Evidence class | `NONE` (implementation provenance and host checks) |
| Result | `PASS` for the mtime-durability correction; T026 overall remains open on §3.1 step 8 retention (see the gap report) |
| Task / issue | `T026` / `#26` |
| Date / timezone | `2026-11-15 Europe/Berlin` |
| Revision | base `d78114fdb703c405fe4692fe287e71095b50fc59`; correction commit `53ffe78e0f9c7ed1939fc1ec0846c3e391927588`; this report, its EMULATOR companion, the index rows, the task note, and the committed mtime bundle are the later documentation changes; final candidate SHA in the external attestation |
| External attestation | `worker_done` transport record (candidate SHA, changed files, report bytes/SHA-256); not part of the candidate commit |
| Supersedes for the changed code | `2026-11-15-t026-review-corrections-evidence.md` and its EMULATOR companion remain the frozen evidence for `84f2276`/`3197ca3`; this report and companion cover `53ffe78` |
| Build identity | `versionName 1.0` (`versionCode 1`), `debug`; app APK `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` SHA-256 `93b92c585e3a5b401c5e0dbd14d322fcfdc171216b1f7760f799672d8b0e0ac5` (216,359,664 bytes); test APK `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` SHA-256 `82711d4215d6fa24d754f5b26490effec216bf6db8155ff105f2d7768890d8a2` (399,814 bytes, unchanged) |
| Toolchain | JDK `17.0.20.1` (Temurin); Gradle `9.3.1`; AGP `9.1.0`; Kotlin `2.4.0`; Flutter `3.47.7` (engine `deb287481e3c`); Dart `3.13.5`; Android platforms `35`/`36`; build-tools `36.0.0`; NDK `28.2.13676358` |
| Input | synthetic UUIDv4 ids, random 32-byte DEKs, synthetic canonical JSON/PDF bytes; no corpus or user data |

## 1. Security finding

The second security review of `3197ca3` reported that revision ordering uses
the file mtime, but `EncryptedStore.kt` at that revision called
`setLastModified` **after** the writer's `FileChannel.force` and before the
atomic rename, then fsynced only the parent directory (review lines
1005–1016, 1028–1039). The review correctly required the durability of the
ordering metadata to be established or a contract-compliant alternative order
proven.

The finding is confirmed as a durability-order defect:

- `setLastModified` changes the inode mtime via `utimensat`/equivalent;
- a parent-directory fsync persists the directory entry/rename, not
  necessarily the changed inode metadata;
- therefore the review's "not proven" is accurate for the old order.

## 2. Correction

The commit path now performs:

```text
stage data + header, fsync(file)
read-back verify staged ciphertext
setLastModified(staged, max(existing + 1, clock))
fault point ORDERING_FSYNC
fsync(file)                      # StoreIo.fsyncFile: FileChannel.force(true)
atomic rename to rev/<id>.fx1 or ver/<id>.fx1
fsync(parent directory)
read-back verify promoted object
```

`StoreIo.fsyncFile` opens the changed file and calls `FileChannel.force(true)`
before the rename. The parent-directory fsync remains after the rename. A new
`StoreFaultPoint.ORDERING_FSYNC` lets tests fail the metadata flush before any
promote.

The same order is used by `saveRevision`, `saveTemplateVersion`, and the
initial revision/version commits; non-revision objects (source, signature,
meta, head) do not carry ordering metadata and are unchanged. The JVM-wide
per-aggregate lock remains in place; it serializes this process only.

## 3. Deterministic tests

New file:
`apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/storage/EncryptedStoreOrderingTest.kt`.

| Test | Result | What it proves |
| --- | --- | --- |
| `revisionOrderingMetadataIsFsyncedBeforePromoteAndParentFsync` | `PASS` | A recording `StoreIo` observes the exact order: `mtime` → `file-fsync` → `move to rev/<id>.fx1` → `dir-fsync` of the revision directory |
| `orderingFsyncFailurePreventsPromoteAndKeepsOldHead` | `PASS` | Injecting `IOException` at `ORDERING_FSYNC` yields `SAVE-003`, does not promote the new revision, keeps the previous head, and removes the staged file |
| Existing monotonic/recovery tests | `PASS` | `commitsPersistStrictlyIncreasingRevisionTimestamps` and `equalTimestampRecoveryMustNotPickByRandomUuid` still pass; the new fsync sits before the existing monotonic mtime ordering |

Full host suite: **114 tests** (49 `EncryptedStoreTest`, 9
`EncryptedStoreFaultTest`, 8 `EncryptedStoreReviewTest`, 3
`EncryptedStoreRetentionTest`, 2 `EncryptedStoreOrderingTest`, 40
`KeystoreServiceTest`, 3 `InstrumentedKeystoreAliasSafetyTest`), 0 failures,
0 errors, 0 skipped.

## 4. Retention remains owner-blocked

The same review message states that the retention decision is with the owner
and asks not to make a format decision. This report does not change
`storage-format.md`, `data-model.md`, ports, channel, T090, or the retention
tests. T026 remains `[ ]` because §3.1 step 8 is still not fulfilled; the
concrete paths and five options remain in
`specs/001-scanned-form-workflow/reports/2026-11-15-t026-pruning-contract-gap.md`.
The mtime correction is independent of retention and does not choose a format.

## 5. Evidence bundle

`specs/001-scanned-form-workflow/reports/artifacts/t026-mtime-2026-11-15/`
contains:

- `manifest.json` binding the base/correction commits, APK/test-APK hashes,
  seven JUnit XML files, the redacted instrumentation logs, device profile,
  allocation record, toolchain, and raw-logcat hashes;
- redacted instrumentation/device logs and the ordering finding;
- `verify.sh`, which checks every committed bundle file and the APK hashes
  when the local build output exists.

`./verify.sh` returns `EVIDENCE VERIFY: OK`. Raw logcat, absolute paths, raw
Orca session/runtime ids, and the APK binaries are intentionally not
published.

## 6. Host checks

| # | Command (repo root) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | Gradle `:app:testDebugUnitTest --tests ...EncryptedStoreOrderingTest` | `0` | `build/t026-work/logs/mtime-ordering-tests.log` | `PASS` (2/2) |
| 2 | Gradle `:app:testDebugUnitTest` (full) | `0` | `build/t026-work/logs/mtime-jvm-full.log` | `PASS` (114/114) |
| 3 | Gradle `:app:assembleDebug :app:assembleDebugAndroidTest` | `0` | `build/t026-work/logs/mtime-assemble.log` | `PASS` |
| 4 | `./verify.sh` in the mtime bundle | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t026-mtime-2026-11-15/` | `PASS` |
| 5 | APK identity recheck | `0` | local build output | `PASS` |

## 7. Artifacts

| Path | Bytes | SHA-256 |
| --- | ---: | --- |
| `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage/EncryptedStore.kt` | 105,035 | `39aac7dc5e81d02bea6b17ec267baa467d1e175ac1ebfd78fbd27c139b147d46` |
| `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/storage/EncryptedStoreOrderingTest.kt` | 7,197 | `e828fcca26f9b645c6d86649cb29d1befc5365c69dbaa907866a12f2daf21733` |
| `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 216,359,664 | `93b92c585e3a5b401c5e0dbd14d322fcfdc171216b1f7760f799672d8b0e0ac5` |
| `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 399,814 | `82711d4215d6fa24d754f5b26490effec216bf6db8155ff105f2d7768890d8a2` |
| `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.EncryptedStoreOrderingTest.xml` | 641 | `7a012fb0600f57f2157f7a3575d9b89e1baa3dfe9da74ed7a8d98b1dde3e4349` |
| `build/t026-work/logs/mtime-jvm-full.log` | 16,253 | `a4344d6e5a0fb9e5633df149c5e29d68547d7879a69089a17aad72b8f71dbc68` |
| `build/t026-work/logs/mtime-instrumentation-t026.log` | 8,777 | `84b259bf13ff0a8a0c82bafbfb65aef72158ebffb8416d696260bf0989ef195b` |
| `build/t026-work/logs/mtime-instrumentation-both.log` | 16,943 | `0e4f75f3d3344530709fd16dc56e58df006e878f3ed5ff3cbfd977f2da0c762f` |
| `specs/001-scanned-form-workflow/reports/artifacts/t026-mtime-2026-11-15/manifest.json` | 8,531 | `9780389e248d1fb44e886c77204bafab52170c4c53c9c1a948754299e05c15c9` |

The committed bundle manifest enumerates every other bundle file. The report
itself and its companion are omitted; their bytes/SHA-256 are in the external
attestation.

## 8. Limitations

- A JVM/host test cannot prove physical power-loss behavior. The evidence is
  the enforced syscall order (`mtime` → file fsync → rename → parent fsync)
  and fail-closed behavior when the metadata fsync is injected to fail.
- The per-aggregate JVM lock serializes this process only; cross-process
  writers are not claimed.
- No `DEVICE`, performance, StrongBox, or silicon-specific key-strength claim.
- Host `emulator -accel-check` remains `UNAVAILABLE` in the worker sandbox; the
  EMULATOR companion records the guest evidence and explicitly makes no
  independent host-KVM claim.
- Retention remains open; no format decision was made.
- No push, merge, or self-review.

## 9. Reproducibility

1. Check out base `d78114fdb703c405fe4692fe287e71095b50fc59` and apply
   `53ffe78e0f9c7ed1939fc1ec0846c3e391927588`.
2. Use the toolchain and writable build copies in
   `specs/001-scanned-form-workflow/reports/artifacts/t026-mtime-2026-11-15/logs/toolchain-versions.log`;
   run `flutter pub get --offline`.
3. Run the two Gradle commands in §6. Expected: 114 tests, zero failures.
4. Run the mtime bundle `verify.sh`. Expected: `EVIDENCE VERIFY: OK`.
5. Run the EMULATOR steps in the companion report. Expected: `13/13` T026 and
   `25/25` including T025.

## 10. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
