# 2026-11-15 `NONE` — T026 pruning contract gap after `3197ca3`

| Field | Value |
| --- | --- |
| Evidence class | `NONE` (contract/model analysis and host checks) |
| Result | `FAIL` for the §3.1 step 8 retention requirement; the analysis and deterministic tests are delivered, but the policy remains open pending a contract/ownership decision |
| Task / issue | `T026` / `#26` |
| Date / timezone | `2026-11-15 Europe/Berlin` |
| Revision | post-review target `3197ca34f4036f80b92a853733e2711d7d65e46f`; implementation `84f2276a4ccf9ae7345a56861cad9d82c1d39e80`; this work adds tests and this report only, with no production-code change; final candidate SHA in the external attestation |
| External attestation | `worker_done` transport record (candidate SHA, changed files, report bytes/SHA-256); not part of the candidate commit |
| Build identity | app/test APK hashes unchanged from `84f2276`/`3197ca3`: app `0941b1764b39a83953bfb70470227f790df2c279e7ac03596fe90c1f5fb1c32e` (216,359,341 bytes); test `82711d4215d6fa24d754f5b26490effec216bf6db8155ff105f2d7768890d8a2` (399,814 bytes) |
| Toolchain | JDK `17.0.20.1` (Temurin); Gradle `9.3.1`; AGP `9.1.0`; Kotlin `2.4.0`; Flutter `3.47.7`; Dart `3.13.5` |
| Input | synthetic UUIDv4 ids, synthetic canonical JSON/PDF bytes; no corpus or user data |

## 1. Question

The post-review of `3197ca3` confirms the evidence bundle and the
head-protected `pruneRevisions(keep)` primitive, but rates §3.1 step 8 `FAIL`:
the save path does not prune, and the keep policy is not assigned. This report
answers the requested question precisely:

> Do the existing canonical data (`RevisionContent`, `RevisionKind`), the
> storage/port/channel contracts, and T090 determine the keep policy
> unambiguously?

**Answer: no.** The current canonical storage persists no per-revision kind or
revision sequence for older revisions. The only persisted kind is the current
head's; `DocumentMeta`, `DurablePointer`, the store DTOs, and the channel expose
only current state, and T090 is unimplemented. An automatic save-path policy
would therefore be a product/format decision, not an inference from existing
data.

## 2. Exact contract and model evidence

| Evidence | Path / lines | What it proves |
| --- | --- | --- |
| Disk payload is `RevisionContent` | `contracts/storage-format.md:126` — `rev/<id>.fx1` → `Canonical JSON RevisionContent` | The persisted revision is the content-only type; `kind` is not part of it |
| Pruning obligation | `contracts/storage-format.md:148` — §3.1 step 8 | Pruning is required **after** read-back; policy is last 3 autosave + newest explicit + recovery |
| Bounded retention | `contracts/storage-format.md:235` — §6 | At most 5 revision objects by default; explicit saves retained until superseded |
| Canonical `Revision` has `kind` | `data-model.md:313–327`; `packages/feldexa_core/lib/src/model/persistence.dart:672–842`; `Revision.toJson` at `:834` | The in-memory/JSON `Revision` contains `id`, `documentId`, `parentRevisionId`, `kind`, `createdAt`, `plaintextSha256`, `content` |
| Canonical `RevisionContent` has no `kind` | `data-model.md:327`; `persistence.dart:275`; `RevisionContent.toJson` at `:598` | `RevisionContent` is exactly pages/suggestions/fields/order/values/signatures/verification/templateOrigin; no provenance |
| Head has only the current kind | `contracts/storage-format.md` §3.1 step 5; `EncryptedStore.CommittedHead` | `head.fx1` stores `{revisionId, plaintextSha256, committedAt, parentRevisionId, kind}` for the current revision only |
| Meta has only the latest pointer | `packages/feldexa_core/lib/src/model/document.dart:683`, `:830`, `:833` | `DocumentMeta` has `latestRevisionId` and `lastDurableAt`; no revision list or kinds |
| Durable pointer has only the current kind | `packages/feldexa_core/lib/src/model/durable_pointer.dart:150` | `kind` is the current durable revision's provenance, not a history |
| Ports request has kind but no history | `contracts/ports.md:386–391` (`SaveRevisionRequest.kind`) and `:222–223` (`saveRevision`, `loadDocument`) | The caller supplies the current save's kind; the port returns no revision history or pruning method |
| Channel request has kind but no history | `contracts/platform-channel.md:130`, `:133`, `:136` | `store.saveRevision` receives the current `kind`; `store.loadDocument` returns `{meta, revision, head}`; no `listRevisions`, history, or prune method |
| T090 is not implemented and has no retention clause | `tasks.md:307`; `packages/feldexa_application/lib/src/persistence/save_document.dart` absent | The natural policy owner does not exist yet and is not explicitly assigned pruning |
| Android adapter/channel is absent | `packages/feldexa_adapters_android/lib/` contains only `.gitkeep`; `FeldexaPlugin.kt` is not implemented | No other layer persists a revision kind or history today |

The canonical `Revision` type (with `kind`) is not the disk payload. Persisting
it instead of `RevisionContent` would be a storage-format change, not an
existing-data inference. Likewise, writing `kind` into
`RevisionContent.unknownFields` would be a new extension convention; no
contract defines it.

## 3. Why a conservative policy cannot be derived either

- Keeping the newest 5 revisions is **not** a superset of the policy: if the
  newest 5 are explicit/recovery revisions, the last 3 autosaves can be older.
- Deleting the oldest revision is **not** safe: it may be a recovery revision
  the policy retains, or an autosave in the last three when many explicit
  revisions follow.
- Keeping all revisions avoids data loss but violates §3.1 step 8 and the §6
  bounded-retention expectation; it is not an implementation of the policy.
- Using mtime/creation time gives commit order (already used by T026 recovery)
  but not **kind**; order alone cannot distinguish autosave, explicit, and
  recovery, which is exactly what the keep policy needs.

## 4. Deterministic tests

New file:
`apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/storage/EncryptedStoreRetentionTest.kt`.

| Test | Result | What it proves |
| --- | --- | --- |
| `persistedRevisionPayloadCarriesNoKindWhileHeadCarriesCurrentKind` | `PASS` | `rev/<id>.fx1` plaintext contains no `kind`; only `head.fx1` carries the current kind/parent |
| `identicalPersistedPayloadsCanRequireDifferentKeepSets` | `PASS` | Two histories with identical revision payloads and identical heads require different keep sets: A keeps `{rev2,rev3,rev4,rev5}` and deletes `rev1`; B also keeps the recovery `rev2` and deletes nothing. `pruneRevisions` returns `1` vs `0` on identical canonical state |
| `saveRevisionDoesNotGuessAPolicy` | `PASS` | Six autosave revisions remain until a caller/contract policy exists; this is a deliberate guard against silent data loss from a guessed policy |

The exact inputs are synthetic; no production code changed. Full host suite:
**112 tests** (49 `EncryptedStoreTest`, 9 `EncryptedStoreFaultTest`, 8
`EncryptedStoreReviewTest`, 3 `EncryptedStoreRetentionTest`, 40
`KeystoreServiceTest`, 3 `InstrumentedKeystoreAliasSafetyTest`), 0 failures,
0 errors, 0 skipped.

## 5. Concrete contract paths and minimal options

These are options, not a product decision. Option B and Option D are the
smallest paths; B is needed for a durable cross-restart policy, D avoids a
format change but cannot reconstruct history after a restart.

| Option | Minimal concrete changes | Pros | Costs / risks |
| --- | --- | --- | --- |
| **A. Persist full `Revision`** instead of `RevisionContent` | `storage-format.md` §2.4/§3.1 (payload schema); `data-model.md` §3.12; `ports.md` §2.4/§2.10; `platform-channel.md` §4; T020 `Revision` already has `kind`/`parentRevisionId`/`createdAt` | Kind and parent/order are durable; one canonical type | Changes the revision payload and hash/migration/read compatibility; duplicates head fields; larger payload; security/format review |
| **B. Bounded `history` in `head.fx1`** | `storage-format.md` §3.1 step 5 and §4 step 2; `data-model.md` §3.13/§4.1; ports `RecoveryStamp` may expose the recovered order | No new files/object kinds; atomic head rewrite; also makes recovery order exact; old heads without history can fail closed/conservative | Head grows with history (bound it); head rewritten each save; contract and security review; old revision kinds are unknown until a new history is built |
| **C. Encrypted revision index/sidecar** (`rev/index.fx1` or `rev/<id>.kind`) | `storage-format.md` §1 layout, §2.4, §3, §4 sweep; `data-model.md` §3.12 | Keeps revision payload/head stable; full history possible | New object kind/layout; atomic index+revision consistency; crash ordering; sweep/GC; more code |
| **D. Caller-supplied keep set on save** | `ports.md` §2.4/§2.10, `platform-channel.md` §4, T090; store calls `pruneRevisions` after step 7 | No storage-format change; reuses the existing head-safe primitive | T090 must own in-memory history; across restart it cannot reconstruct old kinds, so it must be conservative (no prune) until history exists; explicit T090 assignment needed |
| **E. Separate retention task/owner decision** | New task/decision record; keep the primitive | No unowned semantic change | §3.1 step 8 remains open until the task is scheduled |

Recommended for discussion: **B** if a durable cross-restart policy is required
without adding a new object, otherwise **D** if no format change is acceptable
and restart conservatism is acceptable. The author does not select either;
the owner/coordinator must decide.

## 6. What changed and what did not

- **Changed:** three deterministic tests and this report, plus the task/index
  status note. No production code, no contract, and no T090 change.
- **Unchanged:** `EncryptedStore.pruneRevisions(keep)` remains head-protected
  and fail-closed; `saveRevision` still does not invent a policy; the app and
  instrumentation APKs are byte-identical to `84f2276`/`3197ca3`.
- **No emulator rerun:** the production app code is unchanged. The `EMULATOR`
  evidence in `2026-11-15-emulator-t026-review-corrections-pixel7-api35.md`
  remains bound to the same APK hashes. Host tests are the relevant new
  evidence for a test-only change.
- **No push, merge, or self-review.**

## 7. Host checks

| # | Command (repo root) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | Gradle `:app:testDebugUnitTest --tests ...EncryptedStoreRetentionTest` | `0` | `build/t026-work/logs/postreview-retention-gap.log` | `PASS` (3/3) |
| 2 | Gradle `:app:testDebugUnitTest` (full) | `0` | `build/t026-work/logs/postreview-jvm-full.log` | `PASS` (112/112) |
| 3 | Contract/model evidence capture | `0` | `build/t026-work/logs/postreview-contract-evidence.log` | `PASS` |
| 4 | APK identity recheck | `0` | `build/t026-work` local | `PASS` (hashes unchanged) |

### 7.1 Test totals

| Suite | Tests | Skipped | Failures | Errors |
| --- | ---: | ---: | ---: | ---: |
| `EncryptedStoreTest` | 49 | 0 | 0 | 0 |
| `EncryptedStoreFaultTest` | 9 | 0 | 0 | 0 |
| `EncryptedStoreReviewTest` | 8 | 0 | 0 | 0 |
| `EncryptedStoreRetentionTest` (new) | 3 | 0 | 0 | 0 |
| `KeystoreServiceTest` (T025) | 40 | 0 | 0 | 0 |
| `InstrumentedKeystoreAliasSafetyTest` (T025) | 3 | 0 | 0 | 0 |
| **Total** | **112** | **0** | **0** | **0** |

## 8. Artifacts

| Path | Bytes | SHA-256 |
| --- | ---: | --- |
| `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/storage/EncryptedStoreRetentionTest.kt` | 7,847 | `19df888173462fb491f79f55d69d818092a47ba48ec7f46bf381280ba01b44db` |
| `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.EncryptedStoreRetentionTest.xml` | 781 | `780c29a448401dae4276e3e1fa0770f59da96feae6d1fb6e5357d92b1e766f8c` |
| `build/t026-work/logs/postreview-retention-gap.log` | 22,269 | `5dd861f5e56aae2d4d4d0388982ff417968af3ad107956a918751440ca8cdbfb` |
| `build/t026-work/logs/postreview-jvm-full.log` | 16,253 | `b6a95d55ef60428f42a8f17812c24011f0ba3b6cfc1fbabee6da5756e4868e8c` |
| `build/t026-work/logs/postreview-contract-evidence.log` | 3,708 | `9ea73e0a6698e90989b351e09df53164ca81df5d7952e351f246d8c9da0f6972` |
| `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 216,359,341 | `0941b1764b39a83953bfb70470227f790df2c279e7ac03596fe90c1f5fb1c32e` |
| `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 399,814 | `82711d4215d6fa24d754f5b26490effec216bf6db8155ff105f2d7768890d8a2` |

The report itself is omitted from the table; its bytes/SHA-256 are recorded in
the external attestation.

## 9. Limitations

- This is contract/model analysis, not a runtime or acceptance claim. The
  production app code and APKs are unchanged, so the existing `EMULATOR`
  evidence remains the runtime record.
- No owner decision was made. Options B/D are recommendations for discussion,
  not an implementation choice.
- `RevisionContent.unknownFields` could technically carry a `kind` extension,
  but no contract defines that convention; using it would itself be a contract
  decision and is not counted as existing data.
- No push, merge, or self-review.

## 10. Reproducibility

1. Check out `3197ca34f4036f80b92a853733e2711d7d65e46f` and apply this
   test/documentation change.
2. Use the toolchain in the header table; run `flutter pub get --offline` and
   `:app:testDebugUnitTest`. Expected: 112 tests, zero failures.
3. Inspect the exact contract lines in §2 and the three tests in §4.
4. Rebuild the app: the APK hashes in §8 must remain
   `0941...`/`8271...` because no production code changed.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
