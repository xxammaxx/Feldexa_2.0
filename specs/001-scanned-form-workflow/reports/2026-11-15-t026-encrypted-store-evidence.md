# 2026-11-15 `NONE` — T026 `FXC1` encrypted store host evidence

| Field | Value |
| --- | --- |
| Evidence class | `NONE` (implementation provenance and host checks) |
| Result | `PASS` for the recorded host checks; no runtime or acceptance claim |
| Task / issue | `T026` / `#26` |
| Date / timezone | `2026-11-15 Europe/Berlin` |
| Revision | base `d78114fdb703c405fe4692fe287e71095b50fc59`; implementation candidate `1361bc6560ba9c6569a4cfdd3154d306c65f20b5`; this report, its companion, the README row, and the `tasks.md` note are the only later changes and are committed together; final candidate SHA in the external attestation |
| External attestation | `worker_done` transport record (candidate SHA, changed files, companion report bytes/SHA-256); not part of the candidate commit |
| Build identity | `versionName 1.0` (`versionCode 1`), mode `debug`; app APK `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` SHA-256 `8883c5bce2cae6643f5c77b52637b0f9b1183dc12754fe04ed3862e61318ceb1` (216,277,143 bytes); instrumentation test APK `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` SHA-256 `1cc8fcf8701cc1fbd9703bcb7ed025e262228f69ea70c4deca8116917523dfed` (395,491 bytes) |
| Toolchain | JDK `17.0.20.1` (Temurin); Gradle `9.3.1`; Android Gradle Plugin `9.1.0`; Kotlin `2.4.0`; Flutter `3.47.7` (engine `deb287481e3c`); Dart `3.13.5`; Android SDK platforms `35`/`36`; build-tools `36.0.0`; NDK `28.2.13676358` |
| Input | synthetic UUIDv4 aggregate/object ids, random 32-byte DEKs, synthetic canonical-JSON payloads, and synthetic PDF bytes only; no corpus, user data, real title, or signature |

## 1. Scope

This report records the host-side implementation and checks for T026:
the `FXC1` v1 encrypted container, per-aggregate Keystore KEK selection,
the staged/verified/atomic commit protocol, read-back verification, aggregate
deletion, stale-temp and orphan-alias recovery, and the native fault-injection
seam for stage/fsync/commit interruption.

The real Android Keystore run on the Orca-allocated Pixel 7 API 35 runtime is
recorded separately as `EMULATOR` in
`2026-11-15-emulator-t026-pixel7-api35-kvm-encrypted-store.md`. This report does
not claim Android runtime, `DEVICE`, hardware-key-strength, or performance
evidence.

Normative sources: `contracts/storage-format.md` §1–§5 and §7,
`contracts/ports.md` §2.4 and §3, `data-model.md` §3.12–§3.13, `tasks.md`
T026, and the owner decisions on aggregate-scoped `SAVE-002`, integrity
`SAVE-003`, and global `SAVE-008`.

## 2. Implementation

### 2.1 Container and object binding

- 160-byte `FXC1` v1 header with the documented offsets, magic, flags,
  key scheme, object kind, chunk size (`65,536` metadata, `1,048,576` large
  objects), plaintext length, chunk count, nonce prefix, wrapped-DEK lengths,
  plaintext SHA-256, 20-byte file id, and CRC-32 over bytes 0–155.
- AES-256-GCM per chunk with the normative
  `noncePrefix[0..7] ‖ uint32BE(chunkIndex)` IV and the normative AAD
  `FXC1|<hex fileId>|<objectKind>|<chunkIndex>|<chunkCount>|<plaintextLength>`.
- A fresh 32-byte DEK and 8-byte nonce prefix per object. The DEK is wrapped by
  the aggregate KEK (`FXC1-DEK` AAD) through T025 `KeystoreService`; the header
  stores the provider-generated 12-byte `wrapIv` and 48-byte wrapped key.
- Every read verifies magic, version, flags, reserved bytes, CRC-32, file id,
  chunk size, chunk count, wrapped-key length, exact file length, every GCM
  tag, and the complete plaintext SHA-256. Tampering and cross-object splicing
  fail with `CorruptDataException` (`SAVE-003`); a newer version fails with
  `SchemaTooNewException` (`SAVE-005`).
- Aggregate identity is derived from the validated UUIDv4 and the namespace;
  no public method accepts an arbitrary path. Invalid ids fail with
  `PlatformSecurityException` (`PLT-002`) before any I/O.

### 2.2 Atomic commit and read-back

`createDocument`, `createTemplate`, `saveRevision`, `saveTemplateVersion`, and
`writeSignature` use one protocol:

1. stage `tmp/<txnId>.<suffix>` with an exclusive create, write header and
   chunks, patch the digest/sha header, and `fsync`;
2. reopen the staged file, decrypt every chunk, and compare header and
   plaintext hash;
3. promote with an atomic rename and `fsync` the object directory;
4. stage, verify, promote, and `fsync` the head for revisions/versions;
5. read back the promoted head and referenced revision and compare hashes;
6. remove the staged entries.

A failure before head promotion leaves the previous head intact. A read-back
failure after head promotion restores the exact previous head ciphertext and
still reports `SAVE-003`. The expected-head check retries once and then reports
`SAVE-006`; the old head is preserved.

`createDocument` creates the aggregate KEK before the first ciphertext write.
A failure at any creation step removes the incomplete directory and the alias
best-effort; the startup sweep is the backstop. The document is visible only
after meta, head, revision, and source were read back. Only after a verified
commit may the caller treat the write as durable.

### 2.3 Deletion, recovery, and sweep

- Deletion removes the encrypted objects and the aggregate directory first and
  the KEK alias last. A failed alias delete returns
  `orphanAliasLeft = true`; the startup sweep removes it. A wrong confirmation
  title is rejected without touching data; an unreadable aggregate is deleted
  with the caller-supplied localized "Nicht lesbar" title.
- Startup recovery deletes `tmp/` entries older than 24 h or with unknown
  names, removes an aggregate without meta that contains only `src`/`rev`/
  `ver` (an import/template-create that never became visible), adopts the
  newest verifiable revision when the head or its revision is missing/corrupt,
  marks unreadable aggregates without deleting them, and writes one
  counts-only redacted recovery event.
- Orphan aliases under the document/template prefixes are removed only when
  the corresponding aggregate directory is absent; an alias with a directory
  is retained. A provider outage skips the alias sweep instead of failing
  startup.
- Unreferenced signature assets older than 24 h are swept through the
  optional T031 resolver; the store deliberately does not parse revision
  plaintext to invent references. Export-artifact cleanup belongs to T031
  (`cacheDir`, not this store).

### 2.4 Failure vocabulary

`StorageExceptions.kt` now also carries the write-side vocabulary reserved for
T026: `StorageFullException` (`SAVE-001`), `StorageWriteException`
(`SAVE-003` write), `SchemaTooNewException` (`SAVE-005`),
`ConcurrentSaveException` (`SAVE-006`, internal), and `InvalidDataException`
(`SAVE-007`). No exception carries a path, alias, id, title, plaintext, or key
byte.

### 2.5 Owner decisions

| Decision | Application in T026 | Tests |
| --- | --- | --- |
| `SAVE-002` aggregate-scoped key loss while another aggregate key remains usable | `KeyUnavailableException` only for the affected aggregate; sibling document/template stays readable; ciphertext untouched | `oneLostAggregateKeyIsSave002WhileSiblingLoads`, `listReportsSave002PlaceholderAndKeepsSiblingReadable` |
| `SAVE-003` integrity damage while the KEK works | Wrapped-DEK tag mismatch, corrupt/truncated/reordered/spliced chunks, changed hash, and write/fsync failures map to `SAVE-003`; no plaintext output | tamper matrix in §3.2, `perAggregateKekBindsObjectsToTheirAggregate`, `tamperedSourceCiphertextIsSave003` |
| `SAVE-008` global provider outage or device-wide reset | `KeystoreUnavailableException` when the provider is unavailable or no usable aggregate key remains; no per-aggregate isolation claim; data untouched | `noUsableAggregateKeyIsGlobalSave008`, `providerOutageIsSave008AndLeavesNoVisibleAggregate`, `listReportsGlobalSave008WhenEveryAliasIsGone`, `startupRecoverySurvivesAProviderOutageAndSkipsTheAliasSweep` |
| `SAVE-001` quota | `ENOSPC`/`EDQUOT` at stage/fsync/promote maps to `StorageFullException`; old head intact; staging removed | `quotaAtStageMapsToSave001AndKeepsOldHead`, `failedCreateLeavesNoVisibleAggregateAndNoAlias` |

## 3. Checks

All commands ran with the writable toolchain copies in the git-ignored
`build/t026-work/` area. Logs below are local, regenerable support artifacts,
not candidate contents.

| # | Command (repo root) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | Gradle `:app:assembleDebug :app:assembleDebugAndroidTest` | `0` | `build/t026-work/logs/t026-assemble-final.log` | `PASS` |
| 2 | Gradle `:app:testDebugUnitTest --rerun-tasks` | `0` | `build/t026-work/logs/t026-jvm-final.log` | `PASS` |
| 3 | `git diff --check` and `git status --porcelain` at `1361bc6` | `0` | `build/t026-work/logs/t026-diff-check.log` | `PASS` |
| 4 | Toolchain/version capture | `0` | `build/t026-work/logs/t026-toolchain-versions.log` | `PASS` |

### 3.1 Test totals

| Suite | Tests | Skipped | Failures | Errors |
| --- | ---: | ---: | ---: | ---: |
| `EncryptedStoreTest` (T026 store/container/recovery) | 49 | 0 | 0 | 0 |
| `EncryptedStoreFaultTest` (T026 native fault injection) | 9 | 0 | 0 | 0 |
| `KeystoreServiceTest` (T025 regression) | 40 | 0 | 0 | 0 |
| `InstrumentedKeystoreAliasSafetyTest` (T025 regression) | 3 | 0 | 0 | 0 |
| **Total** | **101** | **0** | **0** | **0** |

The XML results are listed in §5. Test counts are the runner's counts, not a
coverage claim.

### 3.2 Container, tamper, and commit coverage

`EncryptedStoreTest` covers:

- round-trip at `0`, `1`, `65,535`, `65,536`, `1,048,575`, `1,048,576`, and
  `1,048,577` bytes, plus the 64 KiB metadata chunk size;
- exact header offsets, CRC-32, file size, fresh nonce/wrap IV per object, and
  the absence of a master alias;
- tamper of the CRC, version, flags, reserved bytes, chunk size, wrapped-key
  length, chunk count, plaintext hash, file id, ciphertext, truncation,
  reordering, and cross-object chunk splicing;
- per-aggregate KEK binding, `SAVE-002` isolation, global `SAVE-008`, provider
  outage without a visible aggregate, `SAVE-006` expected-head conflict, clean
  temporary directory after a save, and read-back stamps;
- deletion objects-first/alias-last, wrong-title rejection, unreadable-title
  deletion, failed alias delete and orphan sweep;
- stale/unknown temp sweep, incomplete-import removal plus orphan alias sweep,
  retained visible alias, head fallback to the newest verified revision,
  fallback past a corrupt newest revision, unreadable-but-kept aggregate,
  missing-meta-with-signature handling, list reason codes, two-source
  rejection, no plaintext residue, counts-only diagnostics, stale signature
  sweep, immutable template versions, and signature round-trip/tamper.

### 3.3 Native fault-injection matrix

| Injected point | Expected result | Test |
| --- | --- | --- |
| `STAGE_CREATE` with `ENOSPC` | `SAVE-001`; old head intact; no visible aggregate or alias on create | `quotaAtStageMapsToSave001AndKeepsOldHead`, `failedCreateLeavesNoVisibleAggregateAndNoAlias` |
| `STAGE_WRITE` short write | `SAVE-003`; old head intact; staging removed | `stageWriteFailureIsSave003AndKeepsOldHead` |
| `STAGE_FSYNC` on the revision | `SAVE-003`; old head intact; staging removed | `stageFsyncFailureIsSave003AndKeepsOldHead` |
| `PROMOTE` rename failure | `SAVE-003`; old head intact; staging removed | `promoteFailureIsSave003AndKeepsOldHead` |
| `PROMOTE_FSYNC` directory failure | `SAVE-003`; old head intact | `promoteFsyncFailureIsSave003AndKeepsOldHead` |
| second `STAGE_FSYNC` (head) | `SAVE-003`; previous head readable | `headStageFsyncFailureLeavesPreviousHeadReadable` |
| `HEAD_PROMOTED` corruption | read-back detects `SAVE-003`; previous head ciphertext restored byte-for-byte | `corruptHeadAfterPromotionIsDetectedAndPreviousHeadRestored` |
| revision corruption after promote | read-back detects `SAVE-003`; old head intact | `corruptRevisionAfterPromotionFailsReadBackAndKeepsOldHead` |

## 4. Limitations

- This report's JVM tests use a real AES-256-GCM fake Keystore backend, not
  `AndroidKeyStore`; real Keystore behavior is claimed only in the companion
  `EMULATOR` report.
- No `DEVICE`, performance, StrongBox, or silicon-specific key-strength claim.
- Revision pruning (`storage-format.md` §3.1 step 8) is not implemented by
  T026. T026's named scope in `tasks.md` ends at atomic commit, read-back,
  deletion, and stale-temp/orphan-alias sweep; the store deliberately does not
  invent revision kinds it does not persist. Retention policy remains with the
  save orchestration/revision-history owner (T090).
- A post-save `meta.fx1` refresh is a caller-owned atomic object commit; T026's
  public create/load/delete/recovery surface is what is tested here.
- Signature-reference discovery for §4 step 3 and export-artifact cleanup are
  T031 inputs; without a resolver the store skips only the signature sweep and
  still removes stale temp and orphan aliases.
- No self-review, push, or merge was performed by the author.

## 5. Artifacts

| Path | Bytes | SHA-256 |
| --- | ---: | --- |
| `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage/EncryptedStore.kt` | 88,300 | `08ea2a0443562a783e95d0d022da86f35f0714078503ea6fe1ef1ef04d5fb0f7` |
| `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage/StorageExceptions.kt` | 5,684 | `6e7305bed2420265bbc8baa26bc00ed6afd3f6095e57ca8e0c467fb823e58fae` |
| `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/storage/EncryptedStoreTest.kt` | 34,546 | `506fe0bbb5a6a18dc51c4d48706409d72cefa30f91f24c1d9eca6d279b7c4e87` |
| `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/storage/EncryptedStoreFaultTest.kt` | 10,236 | `5a38ae7a9058e39448b84363a3be6557675e8432690cd26f990f66dc1f7854ee` |
| `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/storage/TestStoreKeystoreBackend.kt` | 3,390 | `4cc123a34b2cfd210c901dc04d3ff5db2af86895905a1328856c839442e6a1ba` |
| `apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/storage/EncryptedStoreInstrumentedTest.kt` | 14,095 | `9ccf0ed16bd171e7e23740ca4c3e72ec44f8910ca3464c645e5d4a097adcf1b1` |
| `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 216,277,143 | `8883c5bce2cae6643f5c77b52637b0f9b1183dc12754fe04ed3862e61318ceb1` |
| `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 395,491 | `1cc8fcf8701cc1fbd9703bcb7ed025e262228f69ea70c4deca8116917523dfed` |
| `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.EncryptedStoreTest.xml` | 6,569 | `e036aacd1146f930aef3f11dff20495254b379d1d3657da9504e0836cb0a1e1f` |
| `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.EncryptedStoreFaultTest.xml` | 1,591 | `a090fefa6860a209a12f7bab40677abd36479eb88b2ccdc1d35cda00b98a33bc` |
| `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.KeystoreServiceTest.xml` | 5,947 | `1f18bca03a169f467ac498a49446f28405ca0ab3422244a8fd921a851b4d129d` |
| `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.InstrumentedKeystoreAliasSafetyTest.xml` | 803 | `00877ff0cd7ba621fc920437f689083f258210d0f27e3f1f5747743bfddca66b` |
| `build/t026-work/logs/t026-assemble-final.log` | 21,519 | `daecb47e57a75135e7558e7629426d641dd5c402232f9deeab07c35f925b6381` |
| `build/t026-work/logs/t026-jvm-final.log` | 69,204 | `cb9b27ebc346b313c005f329af30ada8bb52d9058df2a3738521da49b4025dc3` |
| `build/t026-work/logs/t026-diff-check.log` | 58 | `85a4dc4b1c3f666edfd2d596e6aaf8b75991f79bd6830d13111b602609141fd7` |
| `build/t026-work/logs/t026-toolchain-versions.log` | 459 | `d6dc081afa6d749bf45c9484a4d6829631e1e12e7680ff347e307c7829cccd9b` |

The report itself and the companion EMULATOR report are omitted from this
table; their bytes and SHA-256 are recorded in the external attestation.

## 6. Reproducibility

1. Check out base `d78114fdb703c405fe4692fe287e71095b50fc59` and apply the
   implementation candidate `1361bc6560ba9c6569a4cfdd3154d306c65f20b5`.
2. Provide writable copies of the Flutter SDK, Android SDK, pub cache, and
   Gradle user home in the git-ignored `build/t026-work/` area; point
   `local.properties` `sdk.dir`/`flutter.sdk` at them and set `JAVA_HOME`,
   `HOME`, `PUB_CACHE`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`,
   `ANDROID_USER_HOME`, `GRADLE_USER_HOME`, and the pre-existing read-only
   Gradle dependency cache.
3. Run `flutter pub get --offline` from the repository root.
4. Run the two Gradle commands in §3. Expected: `BUILD SUCCESSFUL`, 101 tests,
   zero failures/errors/skips.
5. Run `git diff --check`. Expected: exit `0`.
6. Cleanup: the git-ignored `build/t026-work/` area is local and not part of
   the candidate.

## 7. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
