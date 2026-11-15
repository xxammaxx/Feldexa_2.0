# 2026-11-15 NONE — T025 unwrap-tag SAVE-003 resolution

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `PARTIAL` |
| Task / issue | `T025` / `#25` |
| Date / timezone | `2026-11-15 10:06 Europe/Berlin` |
| Revision | base commit `61c8aa83395b157c152dc1cb7c74ec9913a7a89d`; tree `dirty` `specs/001-scanned-form-workflow/contracts/storage-format.md` SHA-256 `e71bad434e098d50d28d5a57db147a880ec2cb74880e670281adfdae51e79616`; `specs/001-scanned-form-workflow/contracts/ports.md` SHA-256 `2e1e6acb742aa26f2c1bd521eacedda5af3ea702120032f1d0b10e547a1577d3`; `specs/001-scanned-form-workflow/data-model.md` SHA-256 `8ea21a4f55e31d86e366b6e051d79b8d21a1139cdd0ab911d59ef8108cc8cd45`; `specs/001-scanned-form-workflow/tasks.md` SHA-256 `ae21519f570bb1bab43c5d877557c9efd1e49d7e597f91d6473b06b1ce34bfb0`; `packages/feldexa_testkit/lib/src/faults/fault_kind.dart` SHA-256 `30e16a2bf9ddd72d9835796f6bb53f675e9c8e9c9fbd8104ef172b7f775c7a9c`; `packages/feldexa_testkit/test/fault_hooks_test.dart` SHA-256 `8165191eefbcf3ca5c785b1ceec5e40b270944de30400d381948830d5414b6c3`; `packages/feldexa_ports/lib/src/ports/secure_store_port.dart` SHA-256 `ac3b418048dcfce73bdc3035092fee231f73f7d9bc1413b023fe92aaf0530817`; `packages/feldexa_ports/test/dto_contract_test.dart` SHA-256 `97190789f7f779e5897d45257d70bf90cc7e1a35152225e82322be7833b405e8`; `apps/feldexa_app/android/app/src/test/kotlin/de/feldexa/app/storage/KeystoreServiceTest.kt` SHA-256 `82391fd0f0c88684ecfd2574e0580a3fe6721ea8e967e1304fb16fbfdc09c9da`; `specs/001-scanned-form-workflow/reports/README.md` SHA-256 `465400558f5825c536b4a112088416c7dc4cb74996afbd3475be7246e9ab3b80`; candidate SHA in external attestation |
| External attestation | worker_done transport attestation (candidate SHA, report bytes and hash); not part of the candidate commit |
| Build identity | debug JVM unit tests; no APK rebuild; 40/40 Keystore tests, 108/108 ports tests, 111/111 testkit tests |
| Toolchain | Flutter 3.47.7 (stable), Dart 3.13.5, Gradle 9.3.1, Android Gradle Plugin 9.1.0, Kotlin 2.4.0, Temurin JDK 17.0.21, Android SDK 36 |
| Input | no corpus; synthetic UUIDv4 aggregate ids and random 32-byte DEKs only; no user data |

## 1. Scope

This report applies the owner decision on T025: an unwrap authentication or
tag mismatch is integrity damage and maps to `CorruptDataException`
(`SAVE-003`), not to aggregate key loss `SAVE-002`. It aligns
`storage-format.md` §2.3 and the testkit fault taxonomy with §5, `ports.md`
§3, the error taxonomy, and the existing `KeystoreService` implementation.
Aggregate key loss remains `SAVE-002`; global provider/reset remains
`SAVE-008`.

The change is contract/test alignment only. The T025 unwrap implementation was
already `SAVE-003` for a usable KEK; its JVM regression is strengthened to
prove the KEK remains available. No push, merge, or self-review was performed.

## 2. Revision and build

Base is `61c8aa83395b157c152dc1cb7c74ec9913a7a89d` (the decision-analysis
commit). The dirty tree contains only the contract, testkit/ports, test, task,
and index changes listed in the metadata plus this new report.

Check 1 is the real Android Gradle `:app:testDebugUnitTest` run (JVM, no
Android runtime); check 2 and check 3 are the affected Dart packages; check 4
is targeted static analysis of the four changed Dart files. The candidate SHA
is recorded externally; this report does not assert it.

## 3. Environment

```text
NONE: host Linux x86_64, 4 logical CPUs; Gradle 9.3.1 and Flutter 3.47.7
      host tests; JDK 17.0.21; Android SDK 36; no accepted Android runtime
      evidence. Android instrumentation remains NOT_RUN.
```

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `gradle -p apps/feldexa_app/android :app:testDebugUnitTest` (`.`) | `0` | `build/t025-work/logs/t025-save003-jvm-test.log` | `PASS` |
| 2 | `flutter test --no-pub` (`packages/feldexa_ports`) | `0` | `build/t025-work/logs/t025-save003-ports-test.log` | `PASS` |
| 3 | `flutter test --no-pub` (`packages/feldexa_testkit`) | `0` | `build/t025-work/logs/t025-save003-testkit-test.log` | `PASS` |
| 4 | `dart analyze packages/feldexa_ports/lib/src/ports/secure_store_port.dart packages/feldexa_ports/test/dto_contract_test.dart packages/feldexa_testkit/lib/src/faults/fault_kind.dart packages/feldexa_testkit/test/fault_hooks_test.dart` (`.`) | `0` | `build/t025-work/logs/t025-save003-analyze-targeted.log` | `PASS` |
| 5 | `real-Keystore instrumentation (10 scenarios)` (`apps/feldexa_app/android`) | `-` | `not run` | `UNAVAILABLE` |

Check 5 remains **`NOT_RUN`**: no stable assigned emulator or device is
available. The prior software-emulated TCG probe booted but crash-looped its
system server (`Lost network stack`) and lost the package service before APK
install; no `EMULATOR` or `DEVICE` evidence is claimed.

## 5. Results

### 5.1 Owner decision applied

| Surface | Before | After |
| --- | --- | --- |
| `storage-format.md` §2.3 | "Alias missing / key invalidated / unwrap tag mismatch" → `SAVE-002` | Alias missing/invalidated → `SAVE-002`; usable KEK plus wrapped-DEK tag mismatch → `CorruptDataException` `SAVE-003`, explicitly not `SAVE-002` |
| `storage-format.md` key-availability/listing text | Listing reasons named only `SAVE-002`/`SAVE-008` | Listing reasons include `SAVE-003` for authentication failure |
| `ports.md` `StoredMeta.unreadableReasonCode` | `SAVE-002`/`SAVE-008` only | `SAVE-002`, `SAVE-003`, or `SAVE-008`; load contract names `CorruptDataException` (`SAVE-003`) |
| `data-model.md` `Unreadable` | `SAVE-002`/`SAVE-008` only | Adds `SAVE-003` for wrapped-DEK/stored-object authentication failure; the key is not unavailable |
| `FaultKind.corruptKeyMaterial` | `SAVE-002` "Aggregate key material is corrupt or unreadable" | `SAVE-003` "Aggregate key material failed authentication or is corrupt" |
| `FaultKind.keystoreUnavailable` | `SAVE-008` | unchanged |
| `KeyUnavailableException` path | `SAVE-002` for missing/invalidated aggregate key | unchanged |
| `KeystoreService.unwrapDek` | `SAVE-003` for a usable KEK with tag mismatch | unchanged behavior; regression now proves the key stays available |

The storage failure table (§5) already mapped "DEK unwrap tag mismatch /
corrupt chunk" to `SAVE-003`; §2.3 now agrees. No exception class, no FXC1
format, and no German text changed.

### 5.2 Tests

| Layer | Result |
| --- | --- |
| Android Gradle JVM Keystore tests | 40/40 passed, 0 failures/errors/skipped. The strengthened `usable kek with a tampered wrapped key is integrity SAVE-003 not key loss` asserts `SAVE-003` and then successfully wraps/unwraps again with the same KEK |
| `packages/feldexa_ports` | 108/108 passed, including a `StoredMeta` unreadable entry with `unreadableReasonCode = SAVE-003` |
| `packages/feldexa_testkit` | 111/111 passed, including the changed `corruptKeyMaterial` code and an explicit SAVE-003-versus-SAVE-002 regression |
| Static analysis | No issues in the four changed Dart files |
| Formatting | `dart format --set-exit-if-changed` on the four changed Dart files: 0 changed |

The contract/testkit regressions are:
- testkit catalogue assertion `corruptKeyMaterial == SAVE-003` and
  `!= SAVE-002`;
- testkit description no longer claims "unavailable" key material;
- ports DTO acceptance of `SAVE-003` as an unreadable reason;
- JVM proof that a tag mismatch is integrity damage, not a lost KEK.

### 5.3 T025 status and evidence

`tasks.md` CR-15 now records the owner decision as resolved. T025 remains
`[x]` for the host implementation only and explicitly states that Android
instrumentation is `NOT_RUN` with no `EMULATOR`/`DEVICE` acceptance. The earlier
decision report `2026-11-15-t025-unwrap-tag-decision.md` remains the historical
options record; this report applies the owner choice.

### 5.4 Residual limits

The `SAVE-003` German catalog text remains write-oriented ("Speichern ist
fehlgeschlagen ...") even though the same code now covers read-side
authentication failure. This report does not change German catalog/ARB text;
that read-side message and its UI wiring remain a T029/T091 follow-up.
`platform-channel.md` `storage.status` remains a key-availability event
(`SAVE-002`/`SAVE-008`); `SAVE-003` surfaces through `list` and load
exceptions, not as a key-availability transition.

## 6. Performance

No performance claim.

## 7. Limitations

- The T025 implementation is unchanged; this is a contract/test alignment and
  regression task.
- JVM tests use a fake backend and do not prove Android Keystore behavior.
- Android instrumentation is **`NOT_RUN`**; the prior TCG guest instability is
  the exact reason.
- The SAVE-003 read-side German message and the catalog/ARB wiring are not
  changed here.
- No independent review is claimed; the second review remains external.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| unit-test XML | `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.KeystoreServiceTest.xml` | 5966 | `07be97af393e357e3eec0d860b953e743479043f77bdb097a47c7f374e296d1d` |
| JVM test log | `build/t025-work/logs/t025-save003-jvm-test.log` | 22123 | `46a98b649d576d14c4a5f3310ed853a8b5a5d00e859d6da1f5159f686cc8f7ae` |
| ports test log | `build/t025-work/logs/t025-save003-ports-test.log` | 20234 | `5590dbf70cb15253f1508e55ffd122f5ed55de2ae23dff2e68c4361af2f62062` |
| testkit test log | `build/t025-work/logs/t025-save003-testkit-test.log` | 20600 | `5e024d7c5c15771421be6706506cff761ad48876ee0773765315ad8a45440cb0` |
| targeted analysis log | `build/t025-work/logs/t025-save003-analyze-targeted.log` | 117 | `a105e0fa8f296c6cbabd19d5414afa2f8fd6c1bfbcf5def81346026d746c3fba` |
| prior connected-test failure log | `build/t025-work/logs/iv-fix-connected-emulator-2.log` | 30962 | `6221d723f10a369b1d4f6caa918ae097676301a70da29006120cd13c4b7b9f79` |
| prior TCG boot log | `build/t025-work/logs/emulator-tcg-3.log` | 10739 | `2dbe4178b0872db7f707ef3dcf0e24386d8d5da1788a6ca3a2df8589a84d0408` |

Git-ignored logs are local, regenerable support artifacts and are not
candidate contents. This report is intentionally not listed in its own
artifacts table.

## 9. Reproducibility

1. Start from base commit `61c8aa83395b157c152dc1cb7c74ec9913a7a89d`.
2. Use the writable JDK 17/Gradle/Flutter/Android toolchain described in the
   prior T025 report; keep `pubspec.lock` unchanged.
3. Run check 1. Expected: 40 tests, 0 failures.
4. Run checks 2 and 3 in the named package directories with the same Flutter
   toolchain. Expected: 108 and 111 tests, 0 failures.
5. Run check 4. Expected: "No issues found!".
6. Android runtime verification remains `NOT_RUN`; do not report the host tests
   as `EMULATOR`/`DEVICE` evidence. Cleanup: delete the gitignored work area.

## 10. External attestation

The `worker_done` transport record is the external attestation: it names the
exact candidate SHA, this report's bytes and SHA-256, and the T025 task and
dispatch identity. No separate attestation ref was created or pushed. The
candidate commit contains this report; it therefore cannot contain its own
SHA-256.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
