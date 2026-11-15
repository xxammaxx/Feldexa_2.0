# 2026-11-15 NONE — T025 SAVE-002 fault restoration

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `PASS` |
| Task / issue | `T025` / `#25` |
| Date / timezone | `2026-11-15 12:49 Europe/Berlin` |
| Revision | base commit `3731b5f8068371a187f453001204e15e1a76647b`; tree `dirty` `packages/feldexa_testkit/lib/src/faults/fault_kind.dart` SHA-256 `a3a395e22f8117c49c8f32a1c7681e50ddd3f492488c0943c0cecffc1a337cb6`; `packages/feldexa_testkit/lib/src/faults.dart` SHA-256 `4c7ad7a6270ba573c1491fefa40df47b9d26660d446390a5fc8b913a6bd43c89`; `packages/feldexa_testkit/test/faults_test.dart` SHA-256 `8955a95eb3b1ec97d0bdbf0f6efaa6cbbba8d65a96a3e8f87a7c3c12f4ca1c40`; `packages/feldexa_testkit/test/fault_hooks_test.dart` SHA-256 `525326c93253e5dc352926bc1d593d0b8e1033fe80fd84a40024860d86585781`; `packages/feldexa_testkit/README.md` SHA-256 `f98dee2f391914d415f1818d1cf20799b89272a327b5a697042b14bacf409f1c`; `specs/001-scanned-form-workflow/tasks.md` SHA-256 `c12770285fe3336fa24c94a72c9a26ba03ba38bd5e97c5d8728e4b66635c2fca`; `specs/001-scanned-form-workflow/reports/README.md` SHA-256 `2bc63753f1bd5540f8e8a168e95136a22c3b869de099161b83eefc927e7d448a`; `specs/001-scanned-form-workflow/reports/2026-11-15-t025-api31-evidence-governance.md` SHA-256 `a0c05ed7634572d5084ef4fd6cffd72305dee97dd7001facc039a8d0023e04a6`; `specs/001-scanned-form-workflow/reports/2026-11-15-t025-main-merge.md` SHA-256 `be3509292022283a71371ac7e414ce958508d5789a44004db548cb92b92b4f6d`; candidate SHA in external attestation |
| External attestation | worker_done transport attestation (candidate SHA, report bytes and hash); not part of the candidate commit |
| Build identity | unchanged T025 debug app APK SHA-256 `672b15363d2eeb415a15e8f2e7999b716f4263a96807e4bdddaeb7fe3ab88077`; instrumentation test APK SHA-256 `ddf7284644361e0f7afdb10f704062230fd9f2e157e5348ebbb312d68b23e9d3` |
| Toolchain | Flutter 3.47.7 (stable), Dart 3.13.5, Gradle 9.3.1, Android Gradle Plugin 9.1.0, Kotlin 2.4.0, Temurin JDK 17.0.21, Android SDK 36 |
| Input | no corpus; synthetic UUIDv4 aggregate ids and random 32-byte DEKs only; no user data |

## 1. Scope

This correction fixes three integration-review findings on the T036/T025 merge:

1. the merge removed the separate aggregate-scoped key-loss injection
   (`SAVE-002`); `corruptKeyMaterial` correctly remained integrity damage
   (`SAVE-003`);
2. `packages/feldexa_testkit/README.md` still described `corruptKeyMaterial`
   with the old `SAVE-002`/`KeyUnavailableException` mapping;
3. the API 31 observation said no production alias was addressed even though
   the isolation test performs a read-only `keyStore.containsAlias` on a
   random production-form alias.

The fix restores a distinct `FaultKind.aggregateKeyUnavailable` mapped to
`KeyUnavailableException` (`SAVE-002`), keeps `corruptKeyMaterial` mapped to
`CorruptDataException` (`SAVE-003`), updates the README and observation
wording, and adds host regressions. It does not change Android source, the
instrumentation test, or either APK.

No push, remote merge, or self-review was performed.

## 2. Revision and build

Base is `3731b5f8068371a187f453001204e15e1a76647b`. The dirty tree contains
only the testkit fault/tests/README, `tasks.md` (CR-17), the report index, the
corrected API 31 governance wording, the corrected merge wording, and this
report.

The app/test APK hashes are unchanged from the tested T025 identity. No new
Android runtime was run; this is a host-only correction.

## 3. Environment

```text
NONE: host Linux x86_64, 4 logical CPUs; Flutter 3.47.7 and Gradle 9.3.1 host
      tests; JDK 17.0.21; Android SDK 36. No Android runtime claim.
```

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `flutter test --no-pub` (`packages/feldexa_testkit`) | `0` | `build/t025-work/logs/t025-save002-fault-testkit.log` | `PASS` |
| 2 | `gradle -p apps/feldexa_app/android :app:testDebugUnitTest` (`.`) | `0` | `build/t025-work/logs/t025-save002-fault-jvm.log` | `PASS` |
| 3 | `dart analyze packages/feldexa_testkit/lib/src/faults/fault_kind.dart packages/feldexa_testkit/lib/src/faults.dart packages/feldexa_testkit/test/faults_test.dart packages/feldexa_testkit/test/fault_hooks_test.dart` (`.`) | `0` | `build/t025-work/logs/t025-save002-fault-analyze.log` | `PASS` |

## 5. Results

### 5.1 Restored SAVE-002 injection

`FaultKind.aggregateKeyUnavailable` is a distinct kind with catalog code
`SAVE-002` and a content-free description. `faultExceptionFor` maps it to
`KeyUnavailableException`, while `corruptKeyMaterial` remains
`CorruptDataException` (`SAVE-003`). The two SAVE-008 contexts
(`keystoreUnavailable` retryable and `keystoreReset` non-retryable) are
unchanged.

The T036 README now states the complete mapping explicitly:
`aggregateKeyUnavailable` → `SAVE-002`/`KeyUnavailableException`,
`corruptKeyMaterial` → `SAVE-003`/`CorruptDataException`, and both SAVE-008
contexts → `KeystoreUnavailableException`.

### 5.2 Host regressions

| Layer | Result |
| --- | --- |
| `packages/feldexa_testkit` | 154/154 passed, including the new aggregate SAVE-002 mapping, unwrap-point, and taxonomy assertions |
| Android Gradle JVM | 43/43 passed (40 Keystore + 3 alias safety) |
| Targeted analysis | No issues found |
| Formatting | 0 files changed |

The new regressions assert:
- `FaultKind.aggregateKeyUnavailable` maps to `KeyUnavailableException` with
  `SAVE-002` and `retryable == false`;
- `FaultKind.corruptKeyMaterial` still maps to `CorruptDataException` with
  `SAVE-003`;
- `FaultingSecureStore` surfaces the aggregate SAVE-002 exception at
  `keystore.unwrap` before any delegate read;
- both SAVE-008 contexts remain distinct.

### 5.3 API 31 evidence governance

The wording now states precisely that the isolation test performs one
read-only `keyStore.containsAlias(documentOne.alias)` on a random
production-form alias to assert that the production alias was not created. It
does not enumerate or delete production aliases and does not create, read, or
delete production key material.

The historical run report `2026-11-15-emulator-t025-keystore.md` is preserved
as a frozen superseded record; its `EMULATOR`/`PASS` class is invalid under
`reports/README.md` §2 because the run was not an Orca-allocated Pixel 7 API
35. The attempted `NONE` replacement is withdrawn, because `NONE` is not a
runtime class. No currently allowed class represents this unallocated run;
the collision and options are documented in the evidence-governance report.
It is not acceptance.

### 5.4 Android identity

`git diff --stat 3a96054a1bd1e40b20f9c43606ace8aa6542748c HEAD --
apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage
apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/storage
apps/feldexa_app/android/app/src/androidTest/kotlin/de/feldexa/app/storage`
is empty and both APK hashes are unchanged. The 12/12 API 31 run is
therefore still bound to the same T025 code/APK identity, but has no valid
evidence class; it is not project `EMULATOR`, API 35, `DEVICE`, or performance
evidence.

### 5.5 Validators

The evidence-governance report, merge record, and this correction report all
validate under `tools/evaluation/validate_report.dart`. The superseded
historical report is not revalidated as valid evidence because its class is
invalid under §2. No convention, schema, or validator change was made.

## 6. Performance

No performance claim.

## 7. Limitations

- This is a host-only correction; no new Android runtime run was made.
- The API 31 run remains an unclassified non-accepting TCG run; it has no
  valid evidence class and is not project `EMULATOR`/API 35 or `DEVICE`
  evidence.
- Android source and APK identity were intentionally kept unchanged.
- The testkit fault harness is test scaffolding; it does not itself prove
  production Keystore behavior.
- No self-review is claimed.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| testkit test log | `build/t025-work/logs/t025-save002-fault-testkit.log` | 28044 | `2ff12261bfb6705fbc2adbe3d1312318efd4ea5075fce84d323f26d10bfb17d6` |
| JVM test log | `build/t025-work/logs/t025-save002-fault-jvm.log` | 16264 | `22c8d3e51ec4e797fc9d6260268266491758929323877318ea72accb5e11f66f` |
| targeted analysis log | `build/t025-work/logs/t025-save002-fault-analyze.log` | 100 | `ca7727e78458072e6f9d7e03bf7cc8f66aac7a306e8272152c698ba7280a8303` |
| Keystore unit-test XML | `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.KeystoreServiceTest.xml` | 5973 | `35369161a30402aa6053e6eb766477983b35e44d4702ac914365d1c0eeb2d077` |
| alias-safety unit-test XML | `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.InstrumentedKeystoreAliasSafetyTest.xml` | 803 | `f81b83615d5c033c932f2339bc31dbada94ea0fa0e5f8f19ee78c13919757ce5` |
| debug app APK (unchanged) | `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 216211073 | `672b15363d2eeb415a15e8f2e7999b716f4263a96807e4bdddaeb7fe3ab88077` |
| instrumentation test APK (unchanged) | `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 376065 | `ddf7284644361e0f7afdb10f704062230fd9f2e157e5348ebbb312d68b23e9d3` |

Git-ignored logs are local support artifacts and are not candidate contents.
This report is intentionally not listed in its own artifacts table.

## 9. Reproducibility

1. Start from `3731b5f8068371a187f453001204e15e1a76647b`.
2. Run check 1. Expected: 154 testkit tests, 0 failures.
3. Run check 2. Expected: 43 JVM tests, 0 failures.
4. Run check 3. Expected: no analyzer issues.
5. Verify `FaultKind.aggregateKeyUnavailable → KeyUnavailableException`
   (`SAVE-002`) and `FaultKind.corruptKeyMaterial → CorruptDataException`
   (`SAVE-003`), and that both SAVE-008 contexts remain.
6. Do not run or claim a new Android acceptance run; the app/test APK hashes
   above are unchanged and the API 31 run remains unclassified and
   non-accepting.

## 10. External attestation

The `worker_done` transport record is the external attestation: it names the
exact correction commit, this report's bytes and SHA-256, and the T025 task and
dispatch identity. No separate attestation ref was created or pushed. The
candidate commit contains this report; it therefore cannot contain its own
SHA-256.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
