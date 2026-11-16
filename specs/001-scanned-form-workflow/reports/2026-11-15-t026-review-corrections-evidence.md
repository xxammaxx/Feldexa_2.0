# 2026-11-15 `NONE` — T026 review corrections for `365b384`

| Field | Value |
| --- | --- |
| Evidence class | `NONE` (implementation provenance and host checks) |
| Result | `PASS` for the recorded host checks; no runtime or acceptance claim here |
| Task / issue | `T026` / `#26` |
| Date / timezone | `2026-11-15 Europe/Berlin` |
| Revision | base `d78114fdb703c405fe4692fe287e71095b50fc59`; correction commit `84f2276a4ccf9ae7345a56861cad9d82c1d39e80`; this report, its EMULATOR companion, the index rows, the task note, and the committed evidence bundle are the later documentation changes; final candidate SHA in the external attestation |
| External attestation | `worker_done` transport record (candidate SHA, changed files, report bytes/SHA-256); not part of the candidate commit |
| Supersedes for the changed code | `2026-11-15-t026-encrypted-store-evidence.md` and `2026-11-15-emulator-t026-pixel7-api35-kvm-encrypted-store.md` remain frozen historical evidence for `365b384`; this report and its companion are the evidence for `84f2276` |
| Build identity | `versionName 1.0` (`versionCode 1`), `debug`; app APK `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` SHA-256 `0941b1764b39a83953bfb70470227f790df2c279e7ac03596fe90c1f5fb1c32e` (216,359,341 bytes); test APK `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` SHA-256 `82711d4215d6fa24d754f5b26490effec216bf6db8155ff105f2d7768890d8a2` (399,814 bytes) |
| Toolchain | JDK `17.0.20.1` (Temurin); Gradle `9.3.1`; AGP `9.1.0`; Kotlin `2.4.0`; Flutter `3.47.7` (engine `deb287481e3c`); Dart `3.13.5`; Android platforms `35`/`36`; build-tools `36.0.0`; NDK `28.2.13676358` |
| Input | synthetic UUIDv4 ids, random 32-byte DEKs, synthetic canonical JSON/PDF bytes; no corpus or user data |

## 1. Review findings and verdicts

The two reviews of `365b384` were checked against the normative contracts and
task ownership. All four reported code/ownership findings are confirmed.

| # | Finding | Verdict | Normative basis | Correction |
| ---: | --- | --- | --- | --- |
| 1 | Compare-and-commit is not serialized; two parallel saves can accept the same `expectedHead`, and a read-back rollback can overwrite the other commit | **CONFIRMED** | `storage-format.md` §3.1 preconditions and steps 5–7; §5 `SAVE-006`; `ports.md` §2.4 `saveRevision` | Per-aggregate JVM-wide lock around the whole compare/commit/read-back/rollback critical section, including create/delete/load/recovery paths |
| 2 | `readContainer` buffers the full plaintext up to 96 MiB during verification, against the chunk-memory rule | **CONFIRMED** | `storage-format.md` §6 (one 1 MiB chunk + tag during encryption/decryption); §2.2 chunk records | `verifyContainer` streams chunk by chunk with reused ciphertext/plaintext buffers; commit read-back, recovery, and idempotent checks use it. `readContainer` remains only for APIs that return complete bytes |
| 3 | Recovery sorts equal-millisecond revisions by random UUID instead of actual commit order | **CONFIRMED** | `storage-format.md` §4 step 2; `data-model.md` §3.12/§3.13 (no persisted revision sequence) | Strictly increasing revision/version mtime assigned at commit; recovery sorts by nanosecond mtime and fails closed as `SAVE-003` on an unresolvable tie, never by UUID |
| 4 | §3.1 step 8 revision pruning is absent and T090 does not explicitly own it | **CONFIRMED** | `storage-format.md` §3.1 step 8 and §6; `data-model.md` §3.12 retention | Added safe `pruneRevisions(keep)` primitive with head protection; the policy ownership gap and concrete options are recorded in §5 instead of silently reassigning T090 |

The owner decisions on aggregate `SAVE-002`, integrity `SAVE-003`, and global
`SAVE-008` are unchanged by these corrections. The serialization and recovery
changes preserve the previous head on every failure path, and the ambiguous
recovery path deletes no file.

## 2. Finding 1 — compare-and-commit race

### 2.1 Reproduction

The test `twoSavesWithTheSameExpectedHeadMustNotBothCommit` starts two saves
with the same expected head. The first is paused at its revision staging point;
the second commits; the first then resumes. With the lock temporarily bypassed
to restore the `365b384` behavior, the test failed:

```text
java.lang.AssertionError: exactly one save may win expected:<1> but was:<2>
```

Both saves returned success, so the second head overwrote the first. The
committed reproduction summary is
`specs/001-scanned-form-workflow/reports/artifacts/t026-review-2026-11-15/logs/reproduction-race.txt`.

### 2.2 Correction

`EncryptedStore` now has a JVM-wide `ConcurrentHashMap<String, ReentrantLock>`
keyed by store root + aggregate kind + aggregate id. `withAggregateLock` wraps:

- `createDocument`/`createTemplate` (existence check, KEK creation, commit,
  cleanup);
- `saveRevision`/`saveTemplateVersion` (expected-head check, revision/version
  promote, head promote, read-back, rollback);
- `delete`, `writeSignature`, `readSignature`, `loadDocument`, `loadTemplate`,
  `recoveryStamp`, the per-aggregate `list` read, the startup recovery loop,
  and the signature sweep.

`commitHead`'s rollback therefore cannot overwrite a concurrent commit from
another store instance in the same process. Cross-process writers are not
claimed; the Android app uses one process. A persistent conflict still maps to
`SAVE-006` after one retry. The new test passes with the lock.

## 3. Finding 2 — full-plaintext verification buffer

### 3.1 Reproduction

`eightyMiBObjectVerifiesUnder128MiBHeap` runs a child JVM with `-Xmx128m` and
commits/verifies an 80 MiB object. With staged verification temporarily
restored to the pre-fix full-plaintext `readContainer` path, the probe failed:

```text
Exception in thread "main" java.lang.OutOfMemoryError: Java heap space
  at de.feldexa.app.storage.EncryptedStore.readContainerInternal(...)
```

The committed reproduction summary is
`specs/001-scanned-form-workflow/reports/artifacts/t026-review-2026-11-15/logs/reproduction-memory.txt`.

### 3.2 Correction

`readContainerInternal` now has two modes:

- `verifyContainer` (`keepPlaintext = false`) decrypts each chunk with GCM into
  one reused plaintext buffer, updates the digest, and discards the chunk.
  Only one ciphertext buffer, one plaintext chunk buffer, and the tag are live.
- `readContainer` (`keepPlaintext = true`) materializes the bytes only when the
  caller API returns them (`loadDocument`, `loadTemplate`, `readSignature`,
  source reads). The full materialization is a property of the port's
  `Uint8List`/`RevisionContent` return type, not of verification.

Commit staging/read-back, recovery, idempotent revision/version checks, and
head/meta small-object reads use the appropriate path. `OutOfMemoryError` and
other `Error`s now propagate instead of being mapped to `SAVE-003`; this was
also required for the memory reproduction to be visible.

## 4. Finding 3 — recovery order

### 4.1 Reproduction

`equalTimestampRecoveryMustNotPickByRandomUuid` gives two revisions equal
millisecond mtimes; the lexicographically higher UUID belongs to the older
revision. With the pre-fix UUID tie-break, the test failed at
`assertFalse(stamp.readable)` (`EncryptedStoreReviewTest.kt:245`): recovery
returned a readable older revision selected by UUID order. The committed
reproduction summary is
`specs/001-scanned-form-workflow/reports/artifacts/t026-review-2026-11-15/logs/reproduction-recovery.txt`.

### 4.2 Correction

- `saveRevision`/`saveTemplateVersion`/creation assign the new revision or
  version an mtime of `max(existing revision mtime + 1, clock)` before the
  atomic promote. This makes the commit order durable even when the clock has
  only millisecond precision.
- Recovery sorts by `StoreIo.lastModifiedNanos` (nanosecond where the
  filesystem provides it).
- If the newest timestamp group contains more than one revision, the actual
  order is unknowable from the persisted format. Recovery does not fall back to
  UUID order; it returns unreadable `SAVE-003`, sets
  `ambiguousRevisionOrder`, and deletes nothing. `RecoveryReport` and the
  redacted startup event count this condition.

`commitsPersistStrictlyIncreasingRevisionTimestamps` proves the monotonic mtime
and the newest-revision fallback. `equalTimestampRecoveryMustNotPickByRandomUuid`
proves the fail-closed tie behavior.

## 5. Finding 4 — §3.1 step 8 pruning and ownership

### 5.1 Evidence of the gap

At `365b384`, `EncryptedStore.kt` had no `pruneRevisions` API
(`git show 365b384:apps/.../EncryptedStore.kt | grep -c pruneRevisions` = `0`).
The contract requires pruning at `storage-format.md` §3.1 step 8 and repeats
the retention rule in §6; `data-model.md` §3.12 states the same policy. The
`tasks.md` T090 line does not mention pruning or retention, so the T026 note's
assignment to "the save-orchestration/revision-history owner (T090)" was not an
explicit task allocation. The committed evidence is
`specs/001-scanned-form-workflow/reports/artifacts/t026-review-2026-11-15/logs/reproduction-pruning.txt`.

### 5.2 Correction

T026 now exposes:

```kotlin
fun pruneRevisions(documentId: String, keepRevisionIds: Set<String>): Int
```

It verifies the current head and the head revision before deleting anything,
never deletes the head revision, only considers `rev/<uuid>.fx1`, and fsyncs
the revision directory after deletions. It returns the number of deleted
files. A corrupt/unverifiable head aborts without deleting anything.

### 5.3 Ownership options (not silently moved)

The policy "last 3 autosave + newest explicit + recovery" cannot be computed by
the store alone because the persisted `RevisionContent` carries no revision
kind and no commit sequence. The concrete options are:

1. **Assign the policy to T090 (recommended).** The save orchestration owns the
   in-memory revision kind/history, computes the keep set, and calls
   `pruneRevisions`. This needs an explicit line on T090 in a planning change;
   T026 only provides the safe primitive.
2. **Extend the persisted format** with revision kind/parent/sequence (a
   contract change reviewed under Principles V–VII), then let T026 prune
   automatically after read-back.
3. **Create a separate retention task with an owner decision** and keep the
   primitive as the only implementation now.

This correction does not change `tasks.md` T090 or the contract format; the
T026 note records the primitive and the open ownership. The coordinator/owner
can choose option 1, 2, or 3.

## 6. Evidence binding for the reviewer

The reviewer could not see the APKs/logs in its own checkout, and the host KVM
probe was unavailable. The correction therefore commits a small, redacted
evidence bundle at
`specs/001-scanned-form-workflow/reports/artifacts/t026-review-2026-11-15/`:

- `manifest.json` binds the base/implementation commits, APK and test-APK
  sizes/SHA-256, the five JUnit XML files, the redacted instrumentation logs
  (`13/13` and `25/25`), the device profile, the allocation record, and the
  toolchain;
- `junit/` contains the five result XML files (hostname redacted to `host`);
- `logs/` contains redacted instrumentation/device/toolchain logs and the four
  reproduction summaries;
- `apk-sha256.txt` and `source-sha256.txt` bind the artifacts and sources;
- raw logcat is **not** published; only its size, SHA-256, and zero FATAL count
  are in the manifest;
- `verify.sh` recomputes every committed bundle hash and checks the APKs when
  the local build output exists.

The app APK is 216 MiB and is not committed; its exact hash and toolchain are
bound, and the reviewer can rebuild/run the same suites. The bundle itself is
verified by `./verify.sh` (PASS). The host KVM probe remains `UNAVAILABLE`
because the worker sandbox exposes no `/dev/kvm`; no host-KVM claim is made. The
EMULATOR claim is bound to the Orca allocation, the Pixel 7 API 35 guest
profile, the APK hashes, and the instrumentation XML/logs.

## 7. Host checks

| # | Command (repo root) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | Gradle `:app:testDebugUnitTest` | `0` | `build/t026-work/logs/final-jvm-suite.log` | `PASS` |
| 2 | Gradle `:app:assembleDebug :app:assembleDebugAndroidTest` | `0` | `build/t026-work/logs/review-assemble-final.log` | `PASS` |
| 3 | `./verify.sh` in the evidence bundle | `0` | `specs/001-scanned-form-workflow/reports/artifacts/t026-review-2026-11-15/` | `PASS` |
| 4 | Lock-bypassed race reproduction | `1` (expected pre-fix failure) | `build/t026-work/logs/repro-race-lock-bypassed.log` | `REPRODUCED` |
| 5 | Buffered-path memory reproduction | `1` (expected pre-fix OOM) | `build/t026-work/logs/repro-memory-buffered.log` | `REPRODUCED` |
| 6 | UUID-tie-break recovery reproduction | `1` (expected pre-fix failure) | `build/t026-work/logs/repro-recovery-uuid.log` | `REPRODUCED` |
| 7 | Pruning ownership evidence | `0` | `build/t026-work/logs/review-pruning-ownership.log` | `CONFIRMED` |

### 7.1 Test totals

| Suite | Tests | Skipped | Failures | Errors |
| --- | ---: | ---: | ---: | ---: |
| `EncryptedStoreTest` | 49 | 0 | 0 | 0 |
| `EncryptedStoreFaultTest` | 9 | 0 | 0 | 0 |
| `EncryptedStoreReviewTest` | 8 | 0 | 0 | 0 |
| `KeystoreServiceTest` (T025) | 40 | 0 | 0 | 0 |
| `InstrumentedKeystoreAliasSafetyTest` (T025) | 3 | 0 | 0 | 0 |
| **Total** | **109** | **0** | **0** | **0** |

The eight new review tests cover the lock race, chunk-streaming order, the
80 MiB/128 MiB heap probe, monotonic timestamps, equal-timestamp fail-closed
recovery, head-protected pruning, pruning without the head in the keep set, and
pruning refusal on an unverifiable head.

## 8. Artifacts

| Path | Bytes | SHA-256 |
| --- | ---: | --- |
| `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage/EncryptedStore.kt` | 104,322 | `1f0ac92c009915cada28a4ecf5a9d2f28fc30c84b2c94edc7fb004050d4d9ee7` |
| `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/storage/EncryptedStoreReviewTest.kt` | 14,589 | `b71757b48c2b36247ae7ddde061818daa9338fe3bca9f0589f0ee05b74625036` |
| `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/storage/MemoryBoundedStoreProbe.kt` | 1,594 | `6114933a5eb476000edaaaeba7614706d9dcfdbb0f7f5fc4f2e4c860baa96a1e` |
| `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/storage/EncryptedStoreInstrumentedTest.kt` | 19,442 | `738ce773f3d14a2e6f5d79be2b6fd4b43ba0fb13ecd72bafde02d759b57ace5a` |
| `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 216,359,341 | `0941b1764b39a83953bfb70470227f790df2c279e7ac03596fe90c1f5fb1c32e` |
| `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 399,814 | `82711d4215d6fa24d754f5b26490effec216bf6db8155ff105f2d7768890d8a2` |
| `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.EncryptedStoreTest.xml` | 6,565 | `4b357163ebe9674e9a1d6046a85b8fec1da35bef017de475ae2d737824312072` |
| `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.EncryptedStoreFaultTest.xml` | 1,591 | `e4f9a930953228d7ece61588be3bba9bb90b67c02cbabbad28f148ef8972f70a` |
| `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.EncryptedStoreReviewTest.xml` | 1,441 | `83af3fc9e51772008f25d962f13ffb40369dd74bad3d1260350df574647fa230` |
| `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.KeystoreServiceTest.xml` | 5,937 | `3b68d390175d7ee9d50d91a35ad580615c7a662884a923134223cb7f6a198c95` |
| `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.InstrumentedKeystoreAliasSafetyTest.xml` | 802 | `fd8a2d4e235914ea31ae98afb343b63fe41da87dd5bd84686a0acc6d0205c14c` |
| `build/t026-work/logs/final-jvm-suite.log` | 28,261 | `4897d5404eab1e3d25bd98c6c46a630972ea9fcce1d487b810905d7abae5b8ab` |
| `build/t026-work/logs/final-instrumentation-t026.log` | 8,777 | `973f58df8cc0c098ddc2b50bd6dd74601cb254e1a675cb8c171a85609c85cc0b` |
| `build/t026-work/logs/final-instrumentation-both.log` | 16,943 | `1a7ab9f6e6f487c738cfb11a2eeb24972f1351905e4d19ae65ec4a38681fb51f` |
| `specs/001-scanned-form-workflow/reports/artifacts/t026-review-2026-11-15/manifest.json` | 7,931 | `b6855645cb04e13ba699068a5363ad70129590a6eb8656b36b72913cc90a2eb9` |

The committed bundle's `manifest.json` enumerates and hashes every other bundle
file, including the redacted logs and JUnit XMLs. Raw local logcat files are
intentionally not committed; their sizes/hashes and zero FATAL counts are in
the manifest.

## 9. Limitations

- JVM tests use a real AES-GCM fake Keystore backend, not `AndroidKeyStore`;
  the real Keystore run is the companion `EMULATOR` report.
- No `DEVICE`, performance, StrongBox, or silicon-specific key-strength claim.
- Host `emulator -accel-check` was `UNAVAILABLE` (no `/dev/kvm` in the worker
  sandbox); the guest reports `hypervisor`/`avx`/`f16c` and uses the
  T025-provisioned Pixel 7 API 35 AVD. No independent host-KVM claim.
- Cross-process compare-and-commit serialization is not claimed; the Android
  app uses one process.
- `loadDocument`/`loadTemplate` still materialize returned source/revision bytes
  because the port signatures return them; streaming delivery remains T040.
- Revision retention policy is open (options in §5); T026 provides only the
  head-protected primitive.
- No push, merge, or self-review was performed.

## 10. Reproducibility

1. Check out base `d78114fdb703c405fe4692fe287e71095b50fc59` and apply
   `84f2276a4ccf9ae7345a56861cad9d82c1d39e80`.
2. Provide writable Flutter/Android/pub/Gradle copies in the git-ignored
   `build/t026-work/` area and set `JAVA_HOME`, `HOME`, `PUB_CACHE`,
   `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `ANDROID_USER_HOME`,
   `GRADLE_USER_HOME`, and the read-only Gradle dependency cache as recorded in
   `specs/001-scanned-form-workflow/reports/artifacts/t026-review-2026-11-15/logs/toolchain-versions.log`.
3. Run `flutter pub get --offline`, then the two Gradle commands in §7.
   Expected: 109 tests, zero failures/errors/skips.
4. Run `specs/001-scanned-form-workflow/reports/artifacts/t026-review-2026-11-15/verify.sh`. Expected:
   `EVIDENCE VERIFY: OK`.
5. Run the EMULATOR steps in the companion report. Expected: `13/13` T026 and
   `25/25` including T025.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
