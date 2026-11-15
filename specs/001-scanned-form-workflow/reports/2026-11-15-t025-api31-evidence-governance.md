# 2026-11-15 NONE — T025 API 31 evidence-governance collision

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `PARTIAL` |
| Task / issue | `T025` / `#25` |
| Date / timezone | `2026-11-15 12:56 Europe/Berlin` |
| Revision | base commit `3f86b9365e968e9828dfafe48c6cf267fb4da494`; tree `dirty` `specs/001-scanned-form-workflow/tasks.md` SHA-256 `c12770285fe3336fa24c94a72c9a26ba03ba38bd5e97c5d8728e4b66635c2fca`; `specs/001-scanned-form-workflow/reports/README.md` SHA-256 `2bc63753f1bd5540f8e8a168e95136a22c3b869de099161b83eefc927e7d448a`; `specs/001-scanned-form-workflow/reports/2026-11-15-emulator-t025-keystore.md` SHA-256 `d0c4d8e5b314885af5eb8b18f987bd6ce2a3d4779264263ee0b5dbaa246b3984`; candidate SHA in external attestation |
| External attestation | worker_done transport attestation (candidate SHA, report bytes and hash); not part of the candidate commit |
| Build identity | no rebuild; T025 debug app APK SHA-256 `672b15363d2eeb415a15e8f2e7999b716f4263a96807e4bdddaeb7fe3ab88077`; instrumentation test APK SHA-256 `ddf7284644361e0f7afdb10f704062230fd9f2e157e5348ebbb312d68b23e9d3` |
| Toolchain | Flutter 3.47.7 (stable), Dart 3.13.5, Gradle 9.3.1, Android Gradle Plugin 9.1.0, Kotlin 2.4.0, Temurin JDK 17.0.21, Android SDK 36 |
| Input | no corpus; synthetic UUIDv4 aggregate ids and random 32-byte DEKs only; no user data |

## 1. Scope

This report documents an evidence-governance collision; it is a `NONE`
provenance/analysis record, not an evidence class for the Android run. The
actual API 31 execution is preserved only in the historical report
`2026-11-15-emulator-t025-keystore.md`. That report's `EMULATOR`/`PASS`
classification is invalid under `reports/README.md` §2 because the run was not
an Orca-allocated Pixel 7 API 35. The attempted replacement that classified the
run as `NONE` is withdrawn: §2 reserves `NONE` for implementation provenance
and host checks, so it also cannot represent an Android runtime.

No convention, schema, validator, contract, or production code is changed.
The raw execution data is retained; no acceptance is claimed.

## 2. Revision and build

Base is `3f86b9365e968e9828dfafe48c6cf267fb4da494`. The historical report was
restored from the pre-reclassification revision and is preserved verbatim as a
frozen superseded record. The withdrawn `NONE` replacement
`2026-11-15-t025-api31-observation.md` is removed from the tree; Git history
retains it. The candidate SHA is recorded externally.

## 3. Environment

```text
NONE: host Linux x86_64, 4 logical CPUs; evidence-governance analysis.
      No evidence class is assigned to the actual API 31 run by this report.
```

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `gradle -p apps/feldexa_app/android :app:testDebugUnitTest` (`.`) | `0` | `build/t025-work/logs/t025-save002-fault-jvm.log` | `PASS` |
| 2 | `valid evidence class for an unallocated API 31 Android run` (`.`) | `-` | `not run` | `UNAVAILABLE` |
| 3 | `project EMULATOR profile (Orca-allocated Pixel 7 API 35)` (`.`) | `-` | `not run` | `UNAVAILABLE` |
| 4 | `DEVICE acceptance` (`.`) | `-` | `not run` | `UNAVAILABLE` |

Check 1 confirms the host suite is still green after the evidence-only
correction. Checks 2–4 are deliberately `UNAVAILABLE`: the current schema and
README §2 expose no class that can truthfully carry this run.

## 5. Results

### 5.1 Binding rules examined

- `reports/README.md` §1: a reviewed run is frozen; corrections are new dated
  reports that name the superseded report; results are never re-scored as the
  same run.
- `reports/README.md` §2: `EMULATOR` is an Orca-allocated Pixel 7 API 35,
  exclusive per run; `NONE` is **not** a runtime class and covers only
  implementation provenance or host checks; `SIMULATED` and `DEVICE` do not
  apply.
- The validator accepts exactly `SIMULATED`, `EMULATOR`, `DEVICE`, or `NONE`;
  its `EMULATOR` profile check is textual (it looks for the profile labels in
  the environment text), so it cannot authenticate the actual device identity.

### 5.2 Concrete collision

The API 31 run is a real Android execution, so `NONE` is false. It is not the
project `EMULATOR` profile, so `EMULATOR` is false. It is not a physical
`DEVICE`, and it is not `SIMULATED`. There is therefore **no allowed evidence
class** for this run in the current schema. Reclassifying it as `NONE` would
hide a real runtime run behind a provenance class; classifying it as `EMULATOR`
would falsely claim the Orca Pixel 7 API 35 profile. Neither is acceptable.

The historical report is preserved unchanged as the frozen run record; its
class remains invalid and is marked superseded in the index. The raw logs,
device identity (`sdk=31`, `sdk_gphone64_x86_64`, userdebug/dev-keys), and APK
hashes remain available for audit, but they are **not** accepted evidence and
cannot satisfy the Android gate.

### 5.3 Options (owner decision required)

1. **Add an explicit non-accepting observation class/status** to
   `reports/README.md` and the validator, for example an `OBSERVATION` class or
   a `class: NONE` plus `runtime: android-unallocated` qualifier that is
   explicitly barred from gates. This is a convention/schema change and
   requires owner authorization.
2. **Allow a profile-qualified `EMULATOR` record**, for example
   `EMULATOR` with `acceptance: false` and an explicit
   `allocation: not Orca Pixel 7 API 35` field. This also changes §2 and the
   validator and must not be introduced unilaterally.
3. **Move unallocated Android runs out of the evidence root** into a
   non-evidence technical note (for example a docs/run-log area), keeping
   `reports/` restricted to schema-valid classes. This changes storage
   convention and needs authorization.
4. **Re-run the same 12 tests on an Orca-allocated Pixel 7 API 35** to produce
   valid `EMULATOR` evidence. This is the only option that closes the gateway
   without changing conventions, but no such allocation was available.

None of these options is implemented here. The collision is documented so an
owner can choose a convention rather than have an agent invent one.

### 5.4 State retained

- The historical `2026-11-15-emulator-t025-keystore.md` file is restored
  verbatim and indexed as a superseded, invalid-class run record.
- The withdrawn `NONE` replacement is removed; this report names it so the
  correction protocol remains traceable.
- The 12/12 API 31 run, logs, and APK hashes are retained for audit, but carry
  no acceptance class.
- T025 remains `[x]` for the host implementation only; the Android gate,
  Pixel 7/API 35 profile, and `DEVICE` acceptance remain open.

## 6. Performance

No performance claim.

## 7. Limitations

- This `NONE` report is governance analysis; it is not evidence for the
  Android run.
- The historical report's `EMULATOR`/`PASS` class is invalid and is not
  revalidated as acceptance. Its revision hashes reference the older tree, as
  expected for a frozen superseded record.
- No new Android runtime run was made.
- No convention, schema, validator, or contract was changed.
- No self-review is claimed.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| historical superseded report | `specs/001-scanned-form-workflow/reports/2026-11-15-emulator-t025-keystore.md` | 10712 | `d0c4d8e5b314885af5eb8b18f987bd6ce2a3d4779264263ee0b5dbaa246b3984` |
| JVM test log | `build/t025-work/logs/t025-save002-fault-jvm.log` | 16264 | `22c8d3e51ec4e797fc9d6260268266491758929323877318ea72accb5e11f66f` |
| Keystore unit-test XML | `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.KeystoreServiceTest.xml` | 5973 | `35369161a30402aa6053e6eb766477983b35e44d4702ac914365d1c0eeb2d077` |
| alias-safety unit-test XML | `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.InstrumentedKeystoreAliasSafetyTest.xml` | 803 | `f81b83615d5c033c932f2339bc31dbada94ea0fa0e5f8f19ee78c13919757ce5` |
| debug app APK (unchanged) | `apps/feldexa_app/build/app/outputs/apk/debug/app-debug.apk` | 216211073 | `672b15363d2eeb415a15e8f2e7999b716f4263a96807e4bdddaeb7fe3ab88077` |
| instrumentation test APK (unchanged) | `apps/feldexa_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 376065 | `ddf7284644361e0f7afdb10f704062230fd9f2e157e5348ebbb312d68b23e9d3` |

Git-ignored logs are local support artifacts and are not candidate contents.
This report is intentionally not listed in its own artifacts table.

## 9. Reproducibility

1. Start from `3f86b9365e968e9828dfafe48c6cf267fb4da494`.
2. Restore `2026-11-15-emulator-t025-keystore.md` from the pre-reclassification
   revision and remove the false `NONE` replacement; confirm Git history
   retains the withdrawn record.
3. Read `reports/README.md` §1/§2 and the schema/validator class set; confirm
   that no allowed class represents a real Android run outside an
   Orca-allocated Pixel 7 API 35.
4. Run the host JVM suite; expected 43/43.
5. Do not classify the API 31 run as `NONE` or `EMULATOR`; retain its logs and
   APK hashes as an unclassified, non-accepting observation and wait for an
   owner convention decision.

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
