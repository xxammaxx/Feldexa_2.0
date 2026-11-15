# 2026-11-15 NONE — T025 API 31 non-accepting observation

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `PARTIAL` |
| Task / issue | `T025` / `#25` |
| Date / timezone | `2026-11-15 12:45 Europe/Berlin` |
| Revision | base commit `3a96054a1bd1e40b20f9c43606ace8aa6542748c`; tree `dirty` `specs/001-scanned-form-workflow/tasks.md` SHA-256 `ff2e6673e1ae31bb5bbc990ec9b85f3309dcdc63c0fd58a89d21c99f9dadfe0c`; `specs/001-scanned-form-workflow/reports/README.md` SHA-256 `5488f0feea4571967988caadf8ea36e65ffab8f95d665f4e94be8cd6915c9b26`; candidate SHA in external attestation |
| External attestation | worker_done transport attestation (candidate SHA, report bytes and hash); not part of the candidate commit |
| Build identity | debug app APK `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` SHA-256 `672b15363d2eeb415a15e8f2e7999b716f4263a96807e4bdddaeb7fe3ab88077`; instrumentation test APK `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` SHA-256 `ddf7284644361e0f7afdb10f704062230fd9f2e157e5348ebbb312d68b23e9d3`; build mode `debug` |
| Toolchain | Flutter 3.47.7 (stable), Dart 3.13.5, Gradle 9.3.1, Android Gradle Plugin 9.1.0, Kotlin 2.4.0, Temurin JDK 17.0.21, Android emulator 37.2.12.0, Android SDK 36 |
| Input | no corpus; synthetic UUIDv4 aggregate ids and random 32-byte DEKs only; no user data |

## 1. Scope

This record corrects the evidence classification of the earlier API 31 run. It
preserves the real execution data, but it is **not** project `EMULATOR`
evidence and does not satisfy the Android runtime gate. `reports/README.md` §2
defines project `EMULATOR` as an Orca-allocated Pixel 7 API 35, exclusive per
run; the run used a copied API 31 google_apis AVD under software TCG. `NONE` is
not a runtime class, so this report is explicitly an additional non-accepting
observation, not acceptance.

No convention, schema, validator, contract, or production code was changed.
No push, merge, or self-review was performed.

## 2. Revision and build

The observed run was produced on candidate
`3a96054a1bd1e40b20f9c43606ace8aa6542748c` with the debug app/test APKs whose
SHA-256 values are in the metadata. The T025 storage source, unit test, and
androidTest file are unchanged from that candidate through the later main
merge; the observation is bound only to that T025 code/APK identity.

The correction's dirty tree contains `tasks.md` (taskmark wording) and the
report index. The candidate SHA is recorded externally; this report does not
assert it.

## 3. Environment

```text
NONE: host Linux x86_64, 4 logical CPUs; additional non-accepting Android
      observation on an isolated read-only API 31 google_apis x86_64
      software-TCG AVD (2 vCPU, 3072 MB, unique port 5580). The project
      EMULATOR profile (Orca-allocated Pixel 7 API 35) and a physical DEVICE
      were not available.
```

Actual observation identity:

```text
sdk=31 release=12 abi=x86_64 model=sdk_gphone64_x86_64
fingerprint=google/sdk_gphone64_x86_64/emulator64_x86_64_arm64:12/SE1A.220826.008/10564458:userdebug/dev-keys
```

This is API 31, not the project's Pixel 7 API 35 profile; no API 35 claim is
made.

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `gradle -p apps/feldexa_app/android :app:testDebugUnitTest` (`.`) | `0` | `build/t025-work/logs/merge-final-jvm.log` | `PASS` |
| 2 | `project EMULATOR profile (Orca-allocated Pixel 7 API 35)` (`.`) | `-` | `not run` | `UNAVAILABLE` |
| 3 | `DEVICE acceptance` (`.`) | `-` | `not run` | `UNAVAILABLE` |

Checks 2 and 3 are the project acceptance gates. They are deliberately
`UNAVAILABLE`: the executed API 31 TCG observation cannot satisfy either.

## 5. Results

### 5.1 Validation rule examined

`reports/README.md` §2 defines `EMULATOR` as an Orca-allocated Pixel 7 API 35,
exclusive per run. The report validator's `classEnvironment.EMULATOR` check
only verifies that the environment text contains the profile labels; passing
that validator is not proof that the actual device is a Pixel 7 API 35. The
normative class definition remains authoritative. Because no allowed runtime
class fits an unallocated API 31 copy, the correct record is a `NONE` report
with `PARTIAL` result and an explicit non-accepting observation.

### 5.2 Real execution retained as an observation

The API 31 suite was actually executed on the isolated read-only copy:

- 12/12 T025 instrumentation tests passed, `Time: 54.096`,
  `OK (12 tests)`.
- Actual device: API 31, x86_64, `sdk_gphone64_x86_64`, userdebug/dev-keys.
- Host JVM suite: 43/43 (40 Keystore tests plus 3 alias-safety tests).
- The AVD was a copy started read-only on unique port 5580 with
  `-no-accel`, `-gpu swiftshader_indirect`, 2 vCPU and 3072 MB; no wipe,
  snapshot write, or foreign-device adoption was used.
- The testnamespace isolation and foreign-test-alias regressions passed. The
  suite does not enumerate or delete production aliases; the isolation test
  performs one read-only `keyStore.containsAlias(documentOne.alias)` on a
  random production-form alias to assert that it was not created. No
  production key material is created, read, or deleted.

This observation is useful evidence that the T025 code path runs on an API 31
Android runtime, but it is not project `EMULATOR`/API 35 evidence and cannot
be used as Android acceptance.

### 5.3 Taskmark and evidence status

`tasks.md` no longer claims an `EMULATOR` pass. T025 remains `[x]` for the host
implementation only, with the API 31 run recorded as an additional
non-accepting observation. The project `EMULATOR` profile (Pixel 7 API 35) and
`DEVICE` acceptance remain open. No API 35, `DEVICE`, or performance claim is
derived.

## 6. Performance

No performance claim. `Time: 54.096` is a software-TCG test duration, not a
product performance measurement.

## 7. Limitations

- `NONE` is not a runtime class; this report cannot satisfy the Android
  runtime gate or acceptance.
- The run is API 31 google_apis x86_64 under software TCG, not the
  Orca-allocated Pixel 7 API 35 profile.
- No physical `DEVICE` run exists.
- No new Android run was made for this classification correction; the raw run
  logs and APK hashes are retained.
- The report validator cannot establish profile authenticity from text alone;
  the normative class definition and actual device identity were checked
  manually.
- No self-review is claimed.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| instrumentation output | `build/t025-work/logs/t025-safe-emulator-instrumentation.log` | 8236 | `e9381665e1cc5efa387b2cae862cf4c594be013800905a4714240a4234e33af6` |
| device identity log | `build/t025-work/logs/t025-safe-emulator-device.log` | 280 | `b989e88b5a0b4e8f181e79399bafdb481634855009cd399d67aeab2e65e34ed9` |
| emulator boot/run log | `build/t025-work/logs/emulator-api31-tcg.log` | 9850 | `9924a68c4f2d3f79b5fa546638bc541db69e7190b058941bcca45fdc4eaf0b3c` |
| JVM test log | `build/t025-work/logs/merge-final-jvm.log` | 16264 | `ac86bd71c750fa6e19386f59c27f5ef68ea0902ce9a1f672a77ebe26c11d5358` |
| Keystore unit-test XML | `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.KeystoreServiceTest.xml` | 5973 | `35369161a30402aa6053e6eb766477983b35e44d4702ac914365d1c0eeb2d077` |
| alias-safety unit-test XML | `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.InstrumentedKeystoreAliasSafetyTest.xml` | 803 | `f81b83615d5c033c932f2339bc31dbada94ea0fa0e5f8f19ee78c13919757ce5` |

Git-ignored logs are local support artifacts and are not candidate contents.
This report is intentionally not listed in its own artifacts table.

## 9. Reproducibility

1. Start from the T025 code identity
   `3a96054a1bd1e40b20f9c43606ace8aa6542748c`.
2. Use the debug app/test APKs with the SHA-256 values above.
3. The API 31 observation used a read-only copy of the installed
   `Feldexa_API31` AVD, unique port 5580, `-no-accel`, `-gpu
   swiftshader_indirect`, 2 vCPU, 3072 MB, no wipe/snapshot write.
4. Install the APKs and run the instrumentation suite; expected `OK (12
   tests)`. The suite performs one read-only `containsAlias` check on a random
   production-form alias and deletes no production alias.
5. Run the host JVM suite; expected 43/43.
6. Validate this report with `tools/evaluation/validate_report.dart`; expected
   valid `NONE`/`PARTIAL` report.
7. Do not classify this run as project `EMULATOR`/API 35 or `DEVICE`, and do
   not derive a performance claim.

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
