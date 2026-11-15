# 2026-11-15 NONE — T025 unwrap-tag allocation decision

| Field | Value |
| --- | --- |
| Evidence class | `NONE` |
| Result | `PARTIAL` |
| Task / issue | `T025` / `#25` |
| Date / timezone | `2026-11-15 03:10 Europe/Berlin` |
| Revision | base commit `f1c80f4681f57c6b967ee760d71f29229962e77c`; tree `dirty` `specs/001-scanned-form-workflow/tasks.md` SHA-256 `b4c446e9dd6c1913ca74dc49d4aa0b0b947de09317fe14214fe76a0d2f4e165b`; `specs/001-scanned-form-workflow/reports/README.md` SHA-256 `aec0664d2281aaa6946fd881efb0011c178b89d7beca397e2d9598bc76c8c71d`; candidate SHA in external attestation |
| External attestation | worker_done transport attestation (candidate SHA, report bytes and hash); not part of the candidate commit |
| Build identity | debug JVM unit tests only; no APK rebuild for this analysis; 40/40 tests |
| Toolchain | Flutter 3.47.7 (stable), Dart 3.13.5, Gradle 9.3.1, Android Gradle Plugin 9.1.0, Kotlin 2.4.0, Temurin JDK 17.0.21, Android SDK 36 |
| Input | no corpus; synthetic UUIDv4 aggregate ids and random 32-byte DEKs only; no user data |

## 1. Scope

This report answers the second-review finding that `storage-format.md` §2.3
allocates an unwrap tag mismatch to `SAVE-002`, while §5 and the ports/error
taxonomy allocate a wrapped-DEK authentication failure to `SAVE-003`. It
audits every binding source, checks whether the existing owner decision already
resolves the distinction between key loss and authentication/integrity damage,
and records the collision and owner options. It also corrects T025's status
wording so the Android instrumentation result is not presented as Android
acceptance.

No T025 behavior, contract, catalog, testkit taxonomy, or German text was
changed. The current implementation keeps the §5/§7/ports reading and remains
covered by tests. No push, merge, or self-review was performed.

## 2. Revision and build

Base for this analysis is `f1c80f4681f57c6b967ee760d71f29229962e77c`.
The only dirty files are `tasks.md` (CR-15 and the T025 status note) and the
report index; the implementation and test sources are unchanged from the base.
`gradle -p apps/feldexa_app/android :app:testDebugUnitTest` ran 40 tests with
0 failures, 0 errors, 0 skipped. No APK or Android runtime was produced for
this analysis. The candidate SHA is recorded externally.

## 3. Environment

```text
NONE: host Linux x86_64, 4 logical CPUs; Gradle 9.3.1 JVM unit tests;
      JDK 17.0.21; Android SDK 36; no accepted Android runtime evidence.
```

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `gradle -p apps/feldexa_app/android :app:testDebugUnitTest` (`.`) | `0` | `build/t025-work/logs/t025-tag-decision-test.log` | `PASS` |
| 2 | `real-Keystore instrumentation (10 scenarios)` (`apps/feldexa_app/android`) | `-` | `not run` | `UNAVAILABLE` |

Check 2 remains **`NOT_RUN`**: the only available AVD is software-emulated
(no KVM) and its system server crash-loops before an APK install can complete,
as recorded in the prior T025 correction. No `EMULATOR` or `DEVICE` result is
claimed.

## 5. Results

### 5.1 Binding-source audit

| Source | Statement relevant to a tag mismatch | Allocation |
| --- | --- | --- |
| `contracts/storage-format.md` §2.3 | "Alias missing / key invalidated / **unwrap tag mismatch** for one aggregate while at least one other aggregate key remains available" | `KeyUnavailableException` (`SAVE-002`) |
| `contracts/storage-format.md` §5 | "**DEK unwrap tag mismatch** / corrupt chunk" | `CorruptDataException` (`SAVE-003`) |
| `contracts/storage-format.md` §7 test 2 | Flip one ciphertext byte, one header byte, reorder/truncate/change chunks or splice a chunk → all fail | `SAVE-003` |
| `contracts/storage-format.md` §2.1 | Tampering with `wrappedKey`/`wrapIv` makes DEK unwrap fail; header has no separate MAC | no code named |
| `contracts/storage-format.md` §2.2 | Every chunk tag is verified; missing/reordered/truncated chunks fail | `CorruptDataException` (`SAVE-003`) |
| `contracts/ports.md` §3 | `CorruptDataException` is the read-side "stored data is corrupt or fails authentication" cause | `SAVE-003` |
| `contracts/ports.md` §2.4 | `loadDocument`/`loadTemplate` may throw `KeyUnavailableException`, `KeystoreUnavailableException`, or `CorruptDataException` | three distinct causes |
| `packages/feldexa_ports/lib/src/errors.dart` | `CorruptDataException` is the read-side `SAVE-003` cause; `KeyUnavailableException` is an unavailable/invalidated aggregate key | `SAVE-003` for authentication failure |
| `contracts/error-catalog.de.md` | `SAVE-002` condition is aggregate key material unavailable/invalidated while other keys remain; `SAVE-003` is write failure or stored data corruption | tag mismatch with a usable KEK is data/authentication, not unavailable key material |
| `packages/feldexa_testkit/lib/src/faults/fault_kind.dart` | `corruptKeyMaterial` ("wrapped key material cannot be unwrapped or is corrupt") | `SAVE-002` (outlier) |
| `reports/2026-11-15-t029-priv001-key-loss-collision.md` | Lists "one object's wrapped DEK or ciphertext is corrupt" as one object with `SAVE-002` **or** `SAVE-003` | explicitly unresolved |
| `reports/2026-11-15-t029-per-aggregate-keystore-decision.md` | Applies the owner decision on per-document/per-template KEKs and global reset | does not mention tag mismatch |
| `reports/2026-11-15-t029-save008-port-testkit.md` | Keeps `corruptKeyMaterial` as aggregate `SAVE-002`; it is not the global provider case | `SAVE-002` for that fault, not a tag-mismatch decision |
| `specs/001-scanned-form-workflow/data-model.md` §3.1 | `Unreadable` is per aggregate; `SAVE-002` for aggregate loss, `SAVE-008` for global | no `SAVE-003` reason named |
| `contracts/ports.md` §2.4 / `store_dto.dart` | `unreadableReasonCode` examples are `SAVE-002`/`SAVE-008` | no `SAVE-003` reason named |
| T025 implementation | A usable KEK whose wrapped DEK fails GCM authentication | `CorruptDataException` (`SAVE-003`) |
| T025 tests | `tampered wrapped key is corrupt data SAVE-003`; `missing key with a usable sibling is aggregate SAVE-002` | pins the two distinguishable causes |

### 5.2 Is the distinction already decided?

No. The binding sources split into two coherent but incompatible readings:

- **Authentication/integrity reading (majority):** §5, §7 test 2, `ports.md`
  §3, `errors.dart`, and the `SAVE-003` catalog row describe a wrapped-DEK
  authentication failure as corrupt/authenticated-failing data. A usable KEK
  that rejects the wrapped DEK is an integrity/authentication failure, not an
  unavailable key.
- **Key-material reading (outlier):** §2.3 and the testkit
  `corruptKeyMaterial` fault allocate the same failure to `SAVE-002`.

The 2026-11-15 owner decision resolved a different question: one KEK per
document/template, isolation for loss/invalidation of one aggregate key, and
global `SAVE-008` for provider outage or device-wide reset. It does not state
whether a wrapped-DEK tag mismatch with an otherwise usable KEK is key loss or
data corruption. The historical collision report noted the ambiguity but
offered options only for the shared-versus-per-aggregate KEK architecture; it
did not resolve the tag allocation.

The condition is also cryptographically ambiguous: the same
`AEADBadTagException` can result from (a) a corrupted/tampered wrapped DEK or
IV, or (b) a KEK that was replaced under the same alias. The implementation
cannot distinguish these causes from ciphertext alone. It can, however,
distinguish an alias that is missing/invalidated from an alias that is usable
but rejects the wrapped DEK; that is the distinction T025 currently applies.

### 5.3 Current T025 behavior (unchanged)

- Alias missing or key invalidated while another aggregate key is usable →
  `KeyUnavailableException` (`SAVE-002`); no other key → global
  `KeystoreUnavailableException` (`SAVE-008`).
- Alias usable but the wrapped DEK fails GCM authentication → 
  `CorruptDataException` (`SAVE-003`).
- The two JVM regressions `missing key with a usable sibling is aggregate
  SAVE-002` and `tampered wrapped key is corrupt data SAVE-003` pin this
  distinction.
- The code and prior T025 reports explicitly call the §2.3/§5 reading open;
  T025 is not presented as Android acceptance.

### 5.4 Options and impacts for the owner

**Option A — Keep the majority reading: usable KEK + tag mismatch is
`SAVE-003` (current behavior).**
Correct §2.3 by removing "unwrap tag mismatch" from the `SAVE-002` bullet (or
splitting it), keep §5/§7/ports/errors, add a read-side `SAVE-003` German
message or clarify that the existing `SAVE-003` text covers both causes, and
allow `unreadableReasonCode = SAVE-003` in the data model/ports DTO. Change
testkit `corruptKeyMaterial` to `SAVE-003` or split it into a key-availability
fault (`SAVE-002`) and a wrapped-DEK corruption fault (`SAVE-003`).
Impacts: contract §2.3, ports/data-model reason codes, catalog/ARB German text,
testkit taxonomy and tests, T025 tests, T026 read-back/error mapping. This is
the smallest code change because T025 already behaves this way, but it changes
security-relevant user text and the testkit contract.

**Option B — Follow §2.3 literally: tag mismatch is `SAVE-002`.**
Change §5 and §7 test 2, `ports.md`/`errors.dart` read-side wording, and T025's
unwrap mapping/tests to `SAVE-002`. Keep testkit `corruptKeyMaterial` as is.
Impacts: a tampered or corrupted wrapped DEK would be reported as a lost key,
and the user message would say the key is unavailable and recovery impossible;
the actual cause could be data tampering. This conflicts with the read-side
`SAVE-003` authentication vocabulary and with the tamper test vector.

**Option C — Split by distinguishable cause (current code plus a consistent
contract/testkit split).**
Alias missing/invalidated → `SAVE-002` (or global `SAVE-008`); usable KEK with
a failed wrapped-DEK tag → `SAVE-003`. This is Option A made explicit: change
§2.3, split the testkit fault, and add a read-side `SAVE-003` reason/message.
Impacts are the same as Option A but with an explicit cause-based contract
statement; it requires T026/T014/T029 coordination and German catalog work.

**Option D — Defer the allocation, keep current behavior and the open
collision.**
Make no contract/catalog/testkit change; record CR-15 and this report; T025
remains host-complete with Android `NOT_RUN`. This avoids inventing a security
decision, but the normative collision remains and a later reviewer will find
it again.

No option is implemented by this report. The owner decision is required
because the choice changes whether tampered/corrupt stored key material is
presented as key loss or as data corruption, and whether `SAVE-003` needs a
read-side German message and an unreadable-reason code.

### 5.5 T025 status and evidence

`tasks.md` now annotates T025 as host-complete while stating explicitly that
Android instrumentation is `NOT_RUN` and that no `EMULATOR`/`DEVICE`
acceptance is claimed. The earlier T025 reports are `NONE`/`PARTIAL`; this
report makes the same limit explicit. The T025 task mark remains `[x]` for the
host implementation only, not for Android acceptance.

## 6. Performance

No performance claim.

## 7. Limitations

- No owner decision exists for the tag-mismatch allocation; this report
  deliberately does not choose one.
- No contract, catalog, testkit, or implementation file was changed for the
  allocation; the only edits are the CR/status note, this report, and its
  index row.
- The 40 JVM tests pass, but the JVM fake backend cannot prove Android
  Keystore behavior.
- Android instrumentation remains **`NOT_RUN`** because the available
  software-emulated AVD crash-loops its system server and loses the package
  service before APK install; the prior T025 correction records the exact
  failure.
- No independent review is claimed; the second review is external.

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| unit-test XML | `apps/feldexa_app/build/app/test-results/testDebugUnitTest/TEST-de.feldexa.app.storage.KeystoreServiceTest.xml` | 5934 | `77f6e8ee86eb6ab31880a82a4b1fa829861b3863d92188c564719bef74d2a2e7` |
| unit-test log | `build/t025-work/logs/t025-tag-decision-test.log` | 22136 | `bd30fd0767b7e8c1848c5d231bdc0d89682041065eda802af0b9426832ab4d77` |
| prior connected-test failure log | `build/t025-work/logs/iv-fix-connected-emulator-2.log` | 30962 | `6221d723f10a369b1d4f6caa918ae097676301a70da29006120cd13c4b7b9f79` |
| prior TCG boot log | `build/t025-work/logs/emulator-tcg-3.log` | 10739 | `2dbe4178b0872db7f707ef3dcf0e24386d8d5da1788a6ca3a2df8589a84d0408` |

Git-ignored logs are local, regenerable support artifacts and are not
candidate contents. This report is intentionally not listed in its own
artifacts table.

## 9. Reproducibility

1. Start from base commit `f1c80f4681f57c6b967ee760d71f29229962e77c`.
2. Use the writable JDK 17/Gradle/Flutter/Android toolchain described in the
   prior T025 report; keep `pubspec.lock` unchanged.
3. Run check 1. Expected: 40 tests, 0 failures. The two tests named in §5.3
   pin the key-loss versus authentication distinction.
4. Read the sources in §5.1. The collision is direct: §2.3 assigns
   "unwrap tag mismatch" to `SAVE-002`; §5 and §7 test 2 assign it to
   `SAVE-003`.
5. Run `dart tools/evaluation/validate_report.dart <this report>` from the
   repository root. Expected: valid report.
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
