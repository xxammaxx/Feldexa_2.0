# T031 round 7 evidence — deadline guard at the durable commit boundary

Candidate base: `34b00234f946bb9268d8e2089788217e73ec4aed`
Branch/worktree: `xxammaxx/feldexa-t031` / `/home/xxammaxx/feldexa-worktrees/t031`
Scope: correction only (Review A residual race). No push, PR, merge, or other worker.
T037 PR #187 Merge-First state is untouched by this work.

## 1. Registered command invocation

Followed `.opencode/commands/speckit.implement.md` for this correction scope.

- Command sha256: `e036ce63702db93e656e1c91ee6c02a8dc3d4a4f8624f8ba4adc69027fe68983`
- Prerequisites: `bash .specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks`
  → `{"FEATURE_DIR":"…/specs/001-scanned-form-workflow","AVAILABLE_DOCS":["research.md","data-model.md","contracts/","quickstart.md","tasks.md"]}`
- Context loaded: `tasks.md`, `plan.md`, `.specify/memory/constitution.md`, relevant
  `contracts/storage-format.md` §4 and `contracts/platform-channel.md` §4 (`store.startupRecovery`).
- Extension hooks: `.specify/extensions.yml` contains `hooks: {}`; no `before_implement` or
  `after_implement` hook was registered, so none was executed or invented.
- Checklists (read-only gate, NOT modified):

  | Checklist | Total | Checked | Unchecked | Status |
  |-----------|------:|--------:|----------:|--------|
  | `requirements.md` | 16 | 16 | 0 | PASS |
  | `precision-testability.md` (reviewer-owned) | 36 | 0 | 36 | **FAIL** |
  | `precision-testability-assessment.md` | 0 | 0 | 0 | n/a |

  The registered command requires a stop-and-ask while the reviewer-owned
  checklist has unchecked items. Implementation proceeded only under the
  standing **owner decision** recorded in this dispatch authorizing continuation
  despite the 0/36 state. The checklist was NOT marked, edited, or reported as
  passed; overall gate remains **FAIL** on that artifact alone.
- `tasks.md`: T031 remains exactly `- [ ]`; no task state was altered.

## 2. Residual race and correction

Review A observation: the round-6 deadline checks sit *before* `commitHead`, but
`commitHead` stages and verifies the head before `promote`. Expiry during staging
could still reach `io.atomicMove` and durably promote the head after the deadline
in both the fallback-adoption and prune-history paths.

Correction (only these two paths thread a deadline; ordinary callers pass the
`null` default and are logically unchanged):

- `promote(...)` gains `deadlineEpochMs: Long? = null` and checks the clock as
  close as possible to `io.atomicMove` — after `stageObject` staging/verification,
  after the `PROMOTE` pre-move hook and `mkdirs`. On expiry it deletes the staged
  temp object and throws a dedicated `PromotionDeadlineReached`.
- `commitHead(...)` gains the same optional deadline and forwards it to `promote`.
  It rethrows `PromotionDeadlineReached` **without** calling `restoreHead` (which
  would rewrite the head after the deadline) and **without** mapping to SAVE-003.
- `PromotionDeadlineReached` is deliberately not a `StorageException`: it is a
  dedicated cancellation outcome, never a write/integrity error.
- `recoverAggregate` (fallback) and the prune shortened-head commit pass the
  deadline into `commitHead`. `startupRecovery` catches the dedicated outcome at
  both call sites and sets `deadlineReached = true` — no fallback count, no
  unreadable/SAVE-003 marking, no post-expiry head rewrite. Prune deletions that
  were already durable before the staging delay stay counted accurately.
- No contract, Dart, ARB, or l10n file changed; no `flutter gen-l10n` needed.

## 3. Non-tautological staging-delay regression

`EncryptedStoreTest.kt` adds two JVM tests. Each has a **control run with no
deadline that really commits** (fallback adopts a head; prune deletes 3 revisions
and rewrites the head), then injects a `StoreFaultInjector` that advances the
shared clock at `STAGE_CREATE` — i.e. *after* all pre-`commitHead` expiry checks
have passed. This deterministically simulates expiry during staging and proves
no post-expiry `atomicMove`.

- `stagingDelayCannotPromoteFallbackHeadAfterTheDeadline` — control adopts a
  fallback head; with the delay: `deadlineReached=true`, `fallbackAdoptions=0`,
  `unreadableAggregates=0`, no head file created, older revision byte-identical,
  staged temp cleaned, redacted event carries `deadlineReached:true` /
  `fallbackAdoptions:0`.
- `stagingDelayCannotCommitPrunedHeadAfterTheDeadline` — control prunes 3 and
  rewrites the head; with the delay the 3 durable deletions stay counted
  (`prunedRevisions=3`), no shortened head is committed (head byte-identical),
  staged temp cleaned, `deadlineReached=true`, `unreadableAggregates=0`, event
  carries `deadlineReached:true` / `prunedRevisions:3`.

On the unfixed candidate `promote` had no deadline parameter and always called
`atomicMove`, so both control-backed assertions would fail there; no separate
pre-fix run was captured because the first host runs were interrupted by the
harness and the environment then required the toolchain repair in §4. The
in-test controls, not an external assumption, establish non-tautology.

## 4. Host toolchain repair (environment, not product source)

The first focused runs exited before the test task:

1. `:gradle:jar` plugin-loader resolution failed because one transform-cache
   entry in **my git-ignored toolchain shadow** was a corrupt 924-byte
   `gradle-1.0.0.jar` with no classes. The on-disk included-build jar
   (`…/flutter_tools/gradle/build/libs/gradle-1.0.0.jar`, 200399 bytes, 93
   classes) and the compiled `FlutterAppPluginLoaderPlugin.class` (7243 bytes)
   were intact. I removed only `build/gradle-home/caches/9.3.1/transforms`
   (my shadow); no user Gradle cache and no product source was touched.
2. Regenerating transforms under JDK 27 then failed `JdkImageTransform`:
   JDK 27 `jlink` could not match the build signature of the SDK android-36
   `java.base.jmod` (German: „kann die Build-Signatur nicht im Modul java.base
   finden … Wahrscheinlich stammt es aus einem früheren Build"). No installed
   JDK 17/21 could read that JDK-27-built jmod either. Using the existing
   Temurin JDK 17 at `.feldexa-toolchain/jdk` as `JAVA_HOME` made AGP regenerate
   a consistent jmod/image; the build then completed successfully.

No JDK was downloaded or installed; no user cache was deleted; no product source
was edited for the repair.

## 5. Focused tests on final source

Command (cwd `apps/feldexa_app/android`):

```sh
JAVA_HOME=/home/xxammaxx/.feldexa-toolchain/jdk \
GRADLE_USER_HOME=/home/xxammaxx/feldexa-worktrees/t031/build/gradle-home \
ANDROID_USER_HOME=/home/xxammaxx/feldexa-worktrees/t031/build/android-user-home \
./gradlew :app:testDebugUnitTest --offline --no-daemon --console=plain \
  --tests "de.feldexa.app.storage.EncryptedStoreTest" \
  --tests "de.feldexa.app.FeldexaPluginTest"
```

Result: `BUILD SUCCESSFUL in 23m 52s`, exit `0`, `161 actionable tasks`
(28 executed, 133 up-to-date). Full log: `/tmp/opencode/t031-final-tests3.log`.

XML reports (`apps/feldexa_app/build/app/test-results/testDebugUnitTest/`):

| XML | tests | failures | errors | skipped |
|-----|------:|---------:|-------:|--------:|
| `TEST-de.feldexa.app.FeldexaPluginTest.xml` | 104 | 0 | 0 | 0 |
| `TEST-de.feldexa.app.storage.EncryptedStoreTest.xml` | 65 | 0 | 0 | 0 |
| **Total** | **169** | **0** | **0** | **0** |

Both new `stagingDelayCannot…` testcases are present in the `EncryptedStoreTest`
XML; neither XML contains a `<failure>` or `<error>` element.

The full JVM suite was not re-run in this round (only the two focused suites
above). The earlier pre-existing environment-sensitive memory-probe failure in
`EncryptedStoreReviewTest` is unchanged and out of this correction's scope.
No Android device/emulator run was attempted in this round.

## 6. Changed files (commit A)

Repository-relative; sha256 of the committed blob contents.

| File | Change | SHA-256 (working copy) |
|------|--------|------------------------|
| `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage/EncryptedStore.kt` | Pre-atomicMove deadline guard, dedicated cancellation outcome, both callers | `8375204d5d344d182e4d9d452572aff681ea56637e15f3c73a28377a7809fef9` |
| `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/storage/EncryptedStoreTest.kt` | 2 control-backed staging-delay regressions | `849fdea1c20a4e38cd2504c1fda8ddd0b69c6bcb030b4f7aa4d881eda76b5661` |

`apps/feldexa_app/android/gradlew.bat` carries a pre-existing line-ending-only
modification and is deliberately excluded from both commits.

## 7. Results

| Criterion | Observed | Verdict |
|-----------|----------|---------|
| Registered command followed | Hash, prereq JSON, `hooks: {}`, checklist table, owner authorization | PASS |
| Deadline before durable move | Check immediately before `io.atomicMove`, after staging/hooks | PASS |
| Dedicated cancellation outcome | `PromotionDeadlineReached`, not StorageException, no head rewrite, no SAVE-003 | PASS |
| Both callers covered | fallback + prune head commits thread deadline | PASS |
| Non-tautological regression | 2 control-backed staging-delay tests | PASS |
| Focused host suites | 104 + 65 = 169 tests, 0 failures/errors/skipped | PASS |
| Reviewer checklist | 0/36, unchanged, FAIL (owner-authorized proceed) | FAIL (not passed) |
| T037 PR #187 | Untouched | PASS |

## 8. Limitations

- Reviewer-owned `precision-testability.md` remains 0/36 unchecked; not altered or reported as passed.
- No device evidence; no performance claim.
- Full JVM suite not re-run this round; known pre-existing memory-probe failure unchanged.
- No push, PR, merge, or other worker; branch/worktree unchanged.
