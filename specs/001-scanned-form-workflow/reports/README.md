# Evidence Reports — Classes, Template, and Index

- **Scope**: `specs/001-scanned-form-workflow/reports/` is the single evidence
  root for task-produced run reports (dry run, recognition, export
  verification, gate, quickstart, usability, performance, acceptance, device).
- **Authority**: constitution Principle VIII, `spec.md` §Evidence and
  Verification Rules, `plan.md` §Evidence Plan, `quickstart.md` §14.
- **Status**: T010 created this index and template; T032 adds the
  machine-readable schema and validator. Gates 7–9 are independent. A report
  here is execution evidence, never approval.

## 1. Single evidence root

- Every report belongs here and is listed in the [index](#9-index) in the same
  change. `tools/evaluation/` holds only code, schemas, protocols, and
  benchmarks — never a second report root.
- `backups/` holds pre-edit snapshots and is not evidence.
- A reviewed run is frozen. Corrections are new dated reports that name the
  superseded report; results are never re-scored and presented as the same run.

## 2. Evidence classes

| Class | Runtime | Can prove | Can never prove |
| --- | --- | --- | --- |
| `SIMULATED` | Chrome/Chromium, deterministic fixtures, simulated adapter registry, Web build | Editor interaction, overlay geometry, navigation, responsive layout, filling, accessibility semantics, state logic | Android runtime behavior, real OCR quality, real storage/encryption, real export validity, device performance |
| `EMULATOR` | Orca-allocated Pixel 7 API 35, exclusive per run; Android build | SAF import, Keystore crypto, ML Kit offline OCR, PDFBox export, lifecycle, storage faults, save/share/print flows | Physical-device performance, silicon-specific key strength, device acceptance |
| `DEVICE` | Samsung Galaxy A54 5G (Exynos 1380, 6 GB, Android 14, One UI 6.1) or T141-approved equivalent; release build | The 3 s A4 claim on that device, real touch journey, device acceptance, offline journey | Anything beyond the tested device, build, and corpus |

`NONE` is not a runtime class. Use it only for implementation provenance or
host checks (formatting, analysis, host-VM tests, code generation, schema
validation); it cannot satisfy a runtime gate or acceptance.

Import, recognition, secure storage, permissions, and final PDF handling must
be verified on a real Android runtime. Emulator timings are never the SC-004
three-second device claim.

## 3. Separation rules

1. **One class and one revision per report.** Never merge classes or revisions
   in one result or headline; do not aggregate pass counts or timings.
2. **Failed targets stay failed.** Report `FAIL` or `PARTIAL`; a green suite is
   not product completion and no failed scenario may be hidden.
3. **Artifact-level export claims.** Verify the produced PDF in independent
   software, not app state; record the verifier and version.
4. **Performance claims cite conditions.** State build mode, device/emulator
   profile, corpus, page set, warm-up/runs, and scope; otherwise claim none.
5. **Simulated is labelled everywhere.** A simulated result is `SIMULATED` in
   the UI, logs, and report; do not call it verified.
6. **No self-approval.** The author records the run; independent review is a
   separate record or gate artifact.
7. **Status vocabulary is fixed.** Results are `PASS`, `FAIL`, or `PARTIAL`;
   check outcomes may also be `UNAVAILABLE` or `ABSENT`. Never invent a
   compound `PASS` label; an incomplete gate is `PARTIAL`.

## 4. Required fields

| Field | Required content |
| --- | --- |
| Class and result | Exactly one class; result `PASS`, `FAIL`, or `PARTIAL`; check outcomes `PASS`, `FAIL`, `PARTIAL`, `UNAVAILABLE`, or `ABSENT`; task/issue; date with timezone |
| Revision | Base commit, tree state (clean, or dirty files with per-file SHA-256); candidate SHA via external attestation (§4.1) |
| Build identity | App version/build ID, build mode and flags, APK/Web build SHA-256, toolchain versions |
| Environment | Class-specific profile (§5); adapter versions for `SIMULATED`; non-sensitive allocation label for `EMULATOR` (never a raw session ID); build fingerprint for `DEVICE` |
| Input | Frozen corpus version and manifest SHA-256, or fixture IDs and hashes |
| Checks / tests | Command, working directory, exit code, log path; scenario, expected, observed, verdict; unavailable/absent checks explicit |
| Performance | Conditions above, plus median/p95 and per-stage values when claimed |
| Limitations | What the class cannot prove; skipped/unavailable/absent checks; nondeterminism |
| Artifacts | Path, byte size, SHA-256 for non-self logs, screenshots, APKs, PDFs, reports |
| Reproducibility | Numbered steps from the named revision: prerequisites, setup, commands, expected output, cleanup |
| Review | Reviewer, date, verdict, notes — left blank by the author |

### 4.1 Self-reference and attestation

A report cannot contain the SHA of the commit that contains it, or its own
byte size and SHA-256, without changing them.

- Record base commit and tree state in the report. Record the exact candidate
  SHA, the report's own bytes/hash, and post-report transport hashes (patch,
  bundle) in an external attestation that is not part of the candidate commit.
- Name the attestation by path or Git ref. Prefer a separate
  `refs/heads/tNNN-attestation` included in the same bundle; a bundle hash
  itself can only live in an external transport attestation or `worker_done`.
- Omit the report's own row from the artifact table. Every other row must have
  path, byte size, and SHA-256; never leave blank size/hash cells.
- Do not assert your own commit SHA, own hash, or a bundle hash that depends on
  it. Say "recorded in the external attestation" instead.

### 4.2 Privacy and logs

- Use repository-relative paths only. Do not include absolute home, worktree,
  SDK, cache, or transcript paths, or raw session, terminal, task, or dispatch
  identifiers. Use `<repo-root>`, `<redacted>`, and role labels instead.
- Retain model/provider, tool versions, commands, and hashes; withhold exact
  session identity and transcript content. Record an emulator run label, not a
  raw Orca allocation/session ID.
- Every log row needs path, byte size, and SHA-256. Label interactive checks
  `console only (not retained)`; a check that did not run
  (`UNAVAILABLE`/`ABSENT`) has no log file, and the report must say so.
- Git-ignored logs are local, regenerable support artifacts, not candidate or
  bundle contents.

## 5. Environment blocks

Use only the block matching the class.

```text
SIMULATED: browser <name/version>; viewport <w x h, DPR>; Web build <path> SHA-256 <hash>;
           simulated adapters <versions>; fixtures <IDs/manifest SHA-256>; network <state>
```

```text
EMULATOR: Pixel 7 API 35, exclusive allocation <non-sensitive label>; system image <id/fingerprint>;
          RAM <MB>; APK <path> SHA-256 <hash>; build mode/flags <...>
```

```text
DEVICE: Samsung Galaxy A54 5G (Exynos 1380, 6 GB, Android 14, One UI 6.1)
        or approved equivalent <T141 record>; build fingerprint <...>;
        APK <path> SHA-256 <hash>; build mode/flags <...>; network <state>
```

## 6. Report template

````markdown
# <YYYY-MM-DD> <CLASS> — <short title>

| Field | Value |
| --- | --- |
| Evidence class | `<SIMULATED \| EMULATOR \| DEVICE \| NONE>` |
| Result | `<PASS \| FAIL \| PARTIAL>` |
| Task / issue | `T###` / `#NN` |
| Date / timezone | `<YYYY-MM-DD HH:MM Europe/Berlin>` |
| Revision | base commit `<sha>`; tree `<clean or dirty files + per-file SHA-256>`; candidate SHA in external attestation |
| External attestation | `<path or git ref>` |
| Build identity | version `<...>`; mode `<debug\|profile\|release>`; artifact `<path>` SHA-256 `<hash>` |
| Toolchain | Flutter `<ver>`, Dart `<ver>`, `<others>` |
| Input | corpus `<version>`/fixtures `<IDs>`; manifest SHA-256 `<hash>` |

## 1. Scope
<What this run proves; requirement/scenario IDs.>

## 2. Revision and build
<Base commit, build command, artifact hash, dirty files. Do not claim the candidate SHA here.>

## 3. Environment
```text
<one class block from §5>
```

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `<command>` (`<cwd>`) | `<0>` | `<path or console only>` | `<PASS/FAIL/PARTIAL/UNAVAILABLE/ABSENT>` |

## 5. Results
<Per-criterion outcomes; no cross-class aggregation.>

## 6. Performance
<Conditions and values, or "No performance claim.">

## 7. Limitations
<Class limits, skipped/unavailable/absent checks, nondeterminism.>

## 8. Artifacts
<Omit this report's own row. Every row: path, bytes, SHA-256.>

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `<artifact>` | `<path>` | `<bytes>` | `<hash>` |

## 9. Reproducibility
1. Start from base commit `<sha>`.
2. `<setup>`
3. `<command>` — expected `<result>`
4. Cleanup/allocation notes.

## 10. External attestation
<Path/ref; records candidate SHA, report bytes/hash, patch/bundle hashes, verification. Fetch command.>

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
````

## 7. Naming and storage

- Class run reports: `YYYY-MM-DD-<class>-<slug>.md`; task-provenance reports:
  `YYYY-MM-DD-tNNN-evidence.md` with class `NONE`.
- Review records: `YYYY-MM-DD-tNNN-review.md`, written by the reviewer.
- Attestations: `YYYY-MM-DD-tNNN-candidate-attestation.json` on a separate
  `tNNN-attestation` ref and/or an external transport attestation. They are
  transport evidence, not reports, and are not indexed.
- Artifacts live under `reports/artifacts/<date>-<class>-<slug>/` or a stable
  path; never store secrets, keys, personal data, or unredacted fixture content.

## 8. Pre-review checks

Run the committed checks from the repository root:

```sh
python3 tools/evaluation/check_evidence_docs.py
python3 tools/evaluation/check_evidence_docs.py --revision <commit>
python3 tools/evaluation/check_evidence_docs.py --attestation-ref refs/remotes/origin/t010-attestation

dart tools/evaluation/validate_report.dart --schema-check
dart tools/evaluation/validate_report.dart specs/001-scanned-form-workflow/reports/<report>.md
dart tools/evaluation/validate_report_test.dart
```

Artifact rows are historical records. The checker verifies them against a
committed Git tree, never against a later working-tree edit. When a later task
has changed a listed file, it accepts the rows only if a revision reachable
from `HEAD` matches every recorded size and SHA-256; `--revision` pins that
revision explicitly. An attestation candidate is verified at its own commit
even when `HEAD` has moved on. A changed file that no recorded revision
contains still fails.

The checked report is bound to the same revision or attestation candidate: a
working-copy report edit fails, even if only a title changed. README, tasks.md,
and the checker are allowed to evolve; their historical values are still
verified at that revision through the artifact rows and attestation changed
files.

The attestation form runs inside a fresh bundle clone. `tools/evaluation/report_schema.json`
is the machine-readable schema; `tools/evaluation/validate_report.dart` parses
this template into the schema's normalized model and fails closed on mixed
evidence classes, compound `PASS` labels, missing class-environment evidence,
unconditioned performance claims, privacy leaks, artifact byte/hash drift,
self-reference, naming/date drift, and a missing index row. In a fresh clone
where ignored logs are absent, pass `--allow-missing-artifacts` to downgrade
only those absent files to warnings.

A check that did not run (`UNAVAILABLE` or `ABSENT`) records `-` for its exit
code; an executed check records an integer, where `PASS` requires 0 and `FAIL`
requires a non-zero code. Artifact and dirty-file paths must resolve inside the
repository root; a symbolic link that escapes it is a validation failure even
when its target bytes match the recorded hash.

A performance section is a no-claim statement only when its entire normalized
text is `No performance claim.`; mixing that phrase with a timing result is a
contradiction and fails. Dates and times must be real calendar and clock
values, not merely shape-valid, and absolute system paths such as `/etc/` are
forbidden anywhere in a report.

Performance detection uses the schema's SC-004 trigger list, including `3 s`,
`3 seconds`, `three seconds`, and `3-second`, so worded forms cannot bypass the
conditions. Output paths are always repository-relative or, for a report
outside the root, basename-only; raw absolute report paths are never emitted,
and an unreadable or escaping index is a structured `index.unreadable` finding.

Metadata tables accept only the template's named fields; an unknown field is a
`parse.metadata.unknown` finding and is never silently dropped before schema
validation.

Artifact, dirty-file, metadata-key, and index diagnostics are content-free:
they name the rule and outcome but never echo report-supplied paths, labels, or
index class values.

Privacy also covers Windows absolute paths: drive-letter forms such as `D:\`
or `D:/`, UNC forms such as `\\server\share`, forward-slash UNC and
scheme-relative forms such as `//host/share`, and Windows file URLs.
Scheme-relative URLs are ambiguous with UNC paths and are rejected
conservatively; write an explicit `http://` or `https://` URL instead.
Explicit HTTP(S) URLs and relative backslash paths remain valid and are
covered by false-positive regressions.

Extended-length, device, and NT object namespace prefixes such as `\\?\`,
`\\.\`, and `\??\`, plus their forward-slash variants, are also rejected
as absolute namespace paths.

Rooted Windows/NT object paths with a single leading backslash and at least
one backslash-separated segment, such as device, registry, GLOBALROOT, or
DosDevices paths, are rejected as absolute. Isolated escape sequences such as
`\n` or `\alpha` and relative backslash paths remain valid.

- [ ] One class, one revision; no cross-class aggregation.
- [ ] Base commit, tree state, and candidate attestation are named; no false
      self SHA.
- [ ] Class environment identifiers are exact; unavailable/absent checks are
      explicit.
- [ ] Every check has command, cwd, exit, and a log path or honest no-log label.
- [ ] Every non-self artifact row has path, bytes, and SHA-256.
- [ ] No absolute home/worktree/SDK/transcript paths or raw session/terminal/
      task/dispatch identifiers.
- [ ] Failures/partials are visible; performance claims cite conditions; no
      compound `PASS` labels.
- [ ] Attestation is fetchable; review table is blank; index lists the report.

## 9. Index

The task-to-issue mapping files are dated historical snapshots and are not live
issue state; use the GitHub issue tracker for live status. They are external to
the git bundle and are not bundle-verifiable.

| Report | Class | Kind | Notes |
| --- | --- | --- | --- |
| [README.md](./README.md) | — | Index and template | This file; T010 |
| [2026-11-12-analysis.md](./2026-11-12-analysis.md) | `NONE` | Gate-5 analysis | Pre-implementation consistency analysis |
| [2026-11-12-command-receipts.md](./2026-11-12-command-receipts.md) | `NONE` | Command provenance | Installed Spec Kit command execution |
| [2026-11-12-plan-correction-receipt.md](./2026-11-12-plan-correction-receipt.md) | `NONE` | Process receipt | Plan correction |
| [2026-11-12-t003-evidence.md](./2026-11-12-t003-evidence.md) | `NONE` | Task evidence | T003 dependency pins |
| [2026-11-12-t003-bc-override-evidence.md](./2026-11-12-t003-bc-override-evidence.md) | `NONE` | Task evidence | T003 build-config override |
| [2026-11-12-t005-evidence.md](./2026-11-12-t005-evidence.md) | `NONE` | Task evidence | T005 German scaffold |
| [2026-11-12-t006-evidence.md](./2026-11-12-t006-evidence.md) | `NONE` | Task evidence | T006 Noto Sans/OFL |
| [2026-11-12-t007-evidence.md](./2026-11-12-t007-evidence.md) | `NONE` | Task evidence | T007 font metrics |
| [2026-11-13-t010-evidence.md](./2026-11-13-t010-evidence.md) | `NONE` | Task evidence | T010 template/index; created 2026-11-12 23:51 |
| [2026-11-13-t012-evidence.md](./2026-11-13-t012-evidence.md) | `NONE` | Task evidence | T012 shared `SIMULATED` widget; Chrome widget run is `SIMULATED` |
| [2026-11-13-t013-blocker-correction.md](./2026-11-13-t013-blocker-correction.md) | `NONE` | Gate-5 correction | T013 canonical-type ordering, descriptor/DTO ownership, export boundary; issue mapping external, live states unavailable from the bundle |
| [2026-11-13-t014-evidence.md](./2026-11-13-t014-evidence.md) | `NONE` | Task evidence | T014 error taxonomy and evidence classes; v2 privacy correction after quality review; host-VM only |
| [2026-11-14-t013-evidence.md](./2026-11-14-t013-evidence.md) | `NONE` | Task evidence | T013 capability descriptors, all 10 port interfaces, `AdapterRegistry`, and port-local DTOs; canonical core/export/T014 types consumed without duplicates; host-VM only; gate browser layer is `SIMULATED`, not T013 evidence |
| [2026-11-14-t013-evidence-review-correction.md](./2026-11-14-t013-evidence-review-correction.md) | `NONE` | Task evidence | T013 requirement-review correction: `SourceIntegrity` carries `CapabilityEvidence` per §1; `PdfExportPort.validate` / T022 `ExportValidation` ownership collision documented instead of inventing a duplicate result type; host-VM only |
| [2026-11-14-t013-export-options-flatten-correction.md](./2026-11-14-t013-export-options-flatten-correction.md) | `NONE` | Task evidence | T013 flattening correction: `ExportOptions(flatten: false)` rejected per §2.5/FR-069; positive/negative regressions added; `ExportValidation` evidence collision preserved unchanged; host-VM only |
| [2026-11-15-t013-export-validation-wrapper.md](./2026-11-15-t013-export-validation-wrapper.md) | `NONE` | Task evidence | T013 owner decision: `PdfExportPort.validate` returns the T013-owned `ExportValidationResult` carrying canonical T022 `ExportValidation` + `CapabilityEvidence`; `feldexa_export` remains ports-free; host-VM only |
| [2026-11-13-t015-evidence.md](./2026-11-13-t015-evidence.md) | `NONE` | Task evidence | T015 geometry value objects; host-VM only |
| [2026-11-13-t015-merge-evidence.md](./2026-11-13-t015-merge-evidence.md) | `NONE` | Task evidence | T015 merge of corrected main `31c75e8`; local merge only, diff vs main recorded |
| [2026-11-13-t016-evidence.md](./2026-11-13-t016-evidence.md) | `NONE` | Task evidence | T016 `PageGeometry` display box, rotation, CropBox mapping; host-VM only; gate browser layer is `SIMULATED`, not T016 evidence |
| [2026-11-14-t019-evidence.md](./2026-11-14-t019-evidence.md) | `NONE` | Task evidence | T019 reclassification compatibility rules and explicit resolve flow; host-VM only; no runtime or acceptance evidence |
| [2026-11-14-t019-contract-correction.md](./2026-11-14-t019-contract-correction.md) | `NONE` | Contract correction | Confirms and fixes the data-model §3.5 parse-error persistence and §6 validation-extension loss in `b90c767`; records Document/RevisionContent roundtrips; host-VM only; supersedes the error/warning section of the T019 evidence report |
| [2026-11-14-t020-evidence.md](./2026-11-14-t020-evidence.md) | `NONE` | Task evidence | T020 persistence types (`DurabilityStatus`, `RevisionKind`, `RevisionContent`, `Revision`); host-VM only; no access to runtime or acceptance evidence |
| [2026-11-14-t022-evidence.md](./2026-11-14-t022-evidence.md) | `NONE` | Task evidence | T022 export contract models (`ExportPlan`, `ExportValidation`, `ExportArtifact`, `ArtifactVerification`) and the strict artifact state machine; host-VM only; no runtime or Android claim |
| [2026-11-14-t022-correction-evidence.md](./2026-11-14-t022-correction-evidence.md) | `NONE` | Task evidence | T022 correction after requirement review: exact §2.2 formula invariants, artifactless `blocked`, explicit stale-example decision, and regression tests; host-VM only; supersedes the 951629f candidate report only |
| [2026-11-14-t022-privacy-correction-evidence.md](./2026-11-14-t022-privacy-correction-evidence.md) | `NONE` | Task evidence | T022 privacy correction: recursive warning/unknown-field/metadata gate for URIs, absolute paths, device names, and user identifiers while preserving safe extensions; host-VM only; follows 6daad88 |
| [2026-11-15-t023-evidence.md](./2026-11-15-t023-evidence.md) | `NONE` | Task evidence | T023 explicit adapter registry (`registry_android`, `registry_web`, `registry_unsupported`), evidence-policy separation, and `SIM-001` release assertion; host-VM/static checks only; the separately labelled Chrome selection check is `SIMULATED` and not Android evidence |
| [2026-11-15-t024-evidence.md](./2026-11-15-t024-evidence.md) | `NONE` | Task evidence | T024 `FeldexaPlugin` MethodChannel/EventChannel facade, validation/envelope/error/cancellation/event/lifecycle machinery, 51 host-JVM contract tests, and a debug APK/DEX build; `EMULATOR` and `DEVICE` are `NOT_RUN` (no KVM acceleration, no attached device), so no Android runtime claim |
| [2026-11-15-t024-review-correction.md](./2026-11-15-t024-review-correction.md) | `NONE` | Task correction | T024 quality-review correction of `b1eadd6`: catalog/machine-key allowlist for `PlatformFailure`, pre-dispatch cancellable-operation progress ID, exact OCR raster byte-length validation, and keyed per-aggregate serialization; 64 host-JVM tests and debug APK/DEX pass; `EMULATOR`/`DEVICE` remain `NOT_RUN`; supersedes the affected findings in the original T024 evidence report |
| [2026-11-15-t024-review2-correction.md](./2026-11-15-t024-review2-correction.md) | `NONE` | Task correction | T024 second quality-review correction of `96b6e89`: bounded per-key/total serial queues with removable queued cancellation, closed category/message namespace allowlists, non-coalesced operation-start ID with the §2.1/§8/§9 collision documented, and facade-level same-document `SAVE-006`; 70 host-JVM tests and debug APK/DEX pass; `EMULATOR`/`DEVICE` remain `NOT_RUN`; supersedes the affected T024 review-correction claims |
| [2026-11-15-t024-review3-correction.md](./2026-11-15-t024-review3-correction.md) | `NONE` | Task correction | T024 third review correction of `155e307`: exact closed machine-message allowlist replaces namespace-only matching, rejecting `save.antrag`/`save.documentTitle` while preserving legitimate mappings; 72 host-JVM tests, pre-fix 155e307 failure, and debug APK/DEX pass; `EMULATOR`/`DEVICE` remain `NOT_RUN`; supersedes the namespace-only allowlist claim |
| [2026-11-15-t024-start-result-protocol.md](./2026-11-15-t024-start-result-protocol.md) | `NONE` | Owner-decision implementation | T024 owner decision on `e69781d`: asynchronous methods return a reliable `{operationId}` start reply, terminal data arrives on the new `de.feldexa/results` channel with bounded replay, and race/cancel/missing-listener/error/lifecycle semantics are specified; 80 host-JVM tests and debug APK/DEX pass; `EMULATOR`/`DEVICE` remain `NOT_RUN` |
| [2026-11-15-t024-race-correction.md](./2026-11-15-t024-race-correction.md) | `NONE` | Task correction | T024 race correction of `1f16f44`: terminal success/error publication and cancel are linearized on one operation state, queued/running cancellation publishes exactly one `PLT-004`, and result-store dispose is synchronized with publish/replay so no post-teardown event or refill; 84 host-JVM tests, 1f16f44 pre-fix failure reproduction, and debug APK/DEX pass; `EMULATOR`/`DEVICE` remain `NOT_RUN` |
| [2026-11-15-t024-service-error-correction.md](./2026-11-15-t024-service-error-correction.md) | `NONE` | Task correction | T024 service-Error correction of `b92789f`: accepted async services throwing `AssertionError`/`Error` now yield one content-free `PLT-001`/`internalError` terminal result (or `PLT-004` if cancellation wins), with sync, cancel, and dispose regressions; 88 host-JVM tests, b92789f pre-fix 3-failure reproduction, and debug APK/DEX pass; `EMULATOR`/`DEVICE` remain `NOT_RUN` |
| [2026-11-15-emulator-t024-main-integration.md](./2026-11-15-emulator-t024-main-integration.md) | `EMULATOR` | Integration and instrumentation | Main `d78114f` merged without rewrite into T024 candidate `8d4821f`; two minimal conflicts resolved, T025 code/tests/reports/task marker preserved; 11 new T024 platform-channel instrumentation tests and the 12 preserved T025 Keystore tests ran 23/23 `PASS` on the Orca-allocated Pixel 7 API 35 AVD with `kvm-clock`, one Orca session and one adb device; 131 JVM tests pass, app/test APKs and both test classes verified; no DEVICE or performance claim |
| [2026-11-16-emulator-t024-payload-roundtrip.md](./2026-11-16-emulator-t024-payload-roundtrip.md) | `EMULATOR` | Payload round-trip coverage | Completes `contracts/platform-channel.md` §12:406 for every method after the `7e13ad0` review: unknown fields 24/24, strict UUID regex for 21 field instances across 16 methods with six malformed shapes each, and 96 MiB + 1 total payloads 24/24; 14/14 T024 and 26/26 with T025 `PASS` on the Orca-allocated Pixel 7 API 35 KVM AVD with `kvm-clock`, one Orca session and one adb device; 131 JVM tests pass; debug-only largeHeap harness documented; no DEVICE, release-heap, or performance claim |
| [2026-11-16-emulator-t024-main-2d793ad-integration.md](./2026-11-16-emulator-t024-main-2d793ad-integration.md) | `EMULATOR` | Main integration and merged runtime | Normal merge of `origin/main` `2d793ad` into T024 candidate `dac5e40` as `fc23b6c`; the two conflicts were resolved minimally (keep T024 async start/result and add T026 `prunedRevisions`/head-history; keep all T024 report rows and add T028); T025/T026 storage and T028 adapters are byte-identical to main; 211 JVM tests and 45/45 Android tests (14 T024 + 12 T025 + 19 T026) pass on the Orca Pixel 7 API 35 KVM AVD, app/test APKs match in-guest, debug-only largeHeap and release manifest unchanged, no DEVICE/Dart/performance claim |
| [2026-11-16-emulator-t024-total-payload-boundary.md](./2026-11-16-emulator-t024-total-payload-boundary.md) | `EMULATOR` | Review-A correction and boundary runtime | Corrects the accepted Review A finding: the §10 96 MiB guard now counts the method-name string, root map marker/count and every key in addition to all values, matching `StandardMethodCodec` byte-for-byte and allocation-free; host below/exact/above regressions prove the values-fit/envelope-over case, and a real `StandardMethodCodec` + `MethodChannel` test accepts the exact encoded size and rejects one byte over; existing unknown-field, UUID and 96 MiB + 1 method-spanning tests preserved; 214 JVM and 46/46 Android tests (15 T024 + 12 T025 + 19 T026) pass on the Orca Pixel 7 API 35 KVM AVD with one session/one adb device, app/test APKs match in-guest, debug-only largeHeap and release manifest unchanged, no DEVICE/Dart/performance claim |
| [2026-11-16-emulator-t024-biginteger-sizing-correction.md](./2026-11-16-emulator-t024-biginteger-sizing-correction.md) | `EMULATOR` | Review-A bounded-allocation correction and fixed-limit boundary runtime | Corrects the accepted Review A finding on `bd78dca`: the §10 `BigInteger` branch no longer calls `toString(16)` and derives the exact `StandardMessageCodec` hexadecimal byte length from `signum`/`bitLength`/`bitCount` (zero, positive, negative, power-of-two semantics), `CharSequence` is scanned without `toString()`, and Collection Iterables no longer copy via `toList()`; host codec-equivalence, 64 Mi-bit `BigInteger` tiny-budget and fixed-112-byte payload-below/exact/above regressions, plus real `StandardMessageCodec`/`StandardMethodCodec` Android regressions, pass as 219 JVM and 48/48 Android tests (17 T024 + 12 T025 + 19 T026) on the Orca Pixel 7 API 35 KVM AVD with one session/one adb device, app/test APKs match in-guest, debug-only largeHeap and release manifest unchanged, no DEVICE/Dart/performance claim; supersedes the old `214 JVM + 46 Android` evidence for the current candidate, which the same two review roles must revalidate |
| [2026-11-16-emulator-t024-negative-lower-bound-correction.md](./2026-11-16-emulator-t024-negative-lower-bound-correction.md) | `EMULATOR` | Review-A negative disambiguation correction and runtime | Corrects the accepted Review A finding on `41b005d`: the §10 `BigInteger` branch now derives a cheap sign/`bitLength` representation-length lower bound and checks it before the exact negative power-of-two `bitCount()` disambiguation, so an oversized negative magnitude rejects without a full magnitude scan while accepted values stay byte-exact (zero/sign/powers, 1/3/5-byte prefixes); a `BitCountTrackingBigInteger` double proves zero `bitCount()` at budgets above 1/2 bytes and far below the encoded size, and exact acceptance/rejection at the 254- and 65,536-byte text boundaries plus `export.validate`; 221 JVM and 49/49 Android tests (18 T024 + 12 T025 + 19 T026) pass on the Orca Pixel 7 API 35 KVM AVD with one session/one adb device, app/test APKs match in-guest, debug-only largeHeap and release manifest unchanged, no DEVICE/Dart/performance claim; supersedes the `219 JVM + 48 Android` evidence, which the same two review roles must revalidate |
| [2026-11-15-t028-evidence.md](./2026-11-15-t028-evidence.md) | `SIMULATED` | Task evidence | T028 deterministic Web substitutes for import, raster, OCR, storage, export, and delivery; fixture-catalogue projection, verified revision read-back/retention, import-created document aggregate, shared logical `SAVE-001` quota refused before any visible import source/aggregate, reference-safe source cleanup on delete, global `SAVE-008` gating for new aggregates, actual-source SHA-256 re-verification in export, revision-bound signature mark and SHA-256 verification before drawing, immutable signature assets with `PLT-002` on an overwrite attempt and a 2 MiB cap with `SAVE-007` before hashing/copying/storing, request/plan identity and byte-derived verification flags, canonical `ExportBlockedException`/`ExportFailedException` mapping with exact codes retained in `validate`, hard-capped raster dimensions, preview PDF with `SIMULATED` watermark and deterministic trailer; 97 host-VM tests and 1 adapter-level Chrome `SIMULATED` journey pass (FR-086/T128 full editor journey remains open); host checks are `NONE` and remain separate; no `EMULATOR`, `DEVICE`, encryption, PDFBox, print-fidelity, or performance claim |
| [2026-11-13-t032-evidence.md](./2026-11-13-t032-evidence.md) | `NONE` | Task evidence | T032 evidence report schema and validator; host-only checks |
| [2026-11-13-t035-evidence.md](./2026-11-13-t035-evidence.md) | `NONE` | Task evidence | T035 manual-baseline protocol; v2 per-form SC-003 correction; no measurements recorded; SC-003 execution remains T142 |
| [2026-11-15-t029-priv001-key-loss-collision.md](./2026-11-15-t029-priv001-key-loss-collision.md) | `NONE` | Contract collision analysis | `PRIV-001`/`SAVE-002` per-document usability promise vs one shared Keystore KEK; all normative occurrences and five options recorded; owner decision later resolved by the per-aggregate decision report |
| [2026-11-15-t029-per-aggregate-keystore-decision.md](./2026-11-15-t029-per-aggregate-keystore-decision.md) | `NONE` | Decision and impact record | Owner decision applied: one Keystore KEK per document and per template; storage/ports/platform/data-model/plan/research/quickstart/catalog/ARB/tasks updated; T025/T026 ownership clarified; host-VM only, Android implementation remains open |
| [2026-11-15-t029-main-integration.md](./2026-11-15-t029-main-integration.md) | `NONE` | Integration record | Normal merge of `origin/main` `406389f` into T029 candidate `8e52c27`; no textual conflicts; T013 `StoreStatus.keyAvailable` retained as summary, `StoredMeta` title uses the "Nicht lesbar" placeholder; host tests 65/107/110 and analysis clean; no Android runtime claim |
| [2026-11-15-t029-t023-integration.md](./2026-11-15-t029-t023-integration.md) | `NONE` | Integration record | Normal merge of `origin/main` `d4344ec` into T029 candidate `dfb4707`; no textual conflicts; T023 registry/tests/evidence preserved; host tests 79/107/110 and analysis clean; T023 browser check `UNAVAILABLE` (no Chrome); no Android runtime claim |
| [2026-11-15-t029-key-availability-correction.md](./2026-11-15-t029-key-availability-correction.md) | `NONE` | Contract correction | Fixes the stale `storage-format.md:117` "no store-global key flag" sentence against T013's implemented `StoreStatus.keyAvailable` summary; one sentence changed, no per-aggregate promise or owner decision changed; host tests 79/107/110 and analysis clean |
| [2026-11-15-t029-save002-global-context.md](./2026-11-15-t029-save002-global-context.md) | `NONE` | Contract correction | Splits aggregate-scoped `SAVE-002` from global `SAVE-008`/`KeystoreUnavailableException` for provider outage or device-wide reset; catalog/ARB/generated text and tests aligned; host tests 79/108/110 and analysis clean; no new security decision |
| [2026-11-15-t029-priv001-global-disclosure.md](./2026-11-15-t029-priv001-global-disclosure.md) | `NONE` | Contract correction | Adds the device/Keystore reset exception to the pre-loss `PRIV-001` disclosure while preserving aggregate isolation; catalog/ARB/generated text and test aligned; host tests 80/108/110 and analysis clean; no architecture or owner-decision change |
| [2026-11-15-t029-save008-port-testkit.md](./2026-11-15-t029-save008-port-testkit.md) | `NONE` | Contract correction | Propagates global `SAVE-008` into `SecureStorePort`/`StoreStatus` docs and the testkit fault taxonomy; `keystoreUnavailable` is SAVE-008, `corruptKeyMaterial` stays SAVE-002; ports/testkit tests updated; host tests 80/108/110 and analysis clean; no runtime implementation |
| [2026-11-15-t025-keystore-evidence.md](./2026-11-15-t025-keystore-evidence.md) | `NONE` | Task evidence | T025 per-document/per-template Keystore KEK service, alias lifecycle, DEK wrap/unwrap, `SAVE-002`/`SAVE-008` mapping; 36 JVM tests pass in the real AGP `testDebugUnitTest`; 9 real-Keystore instrumentation tests compiled and the test APK assembled; Android runtime checks are `NOT_RUN` (no connected device, no KVM) |
| [2026-11-15-t025-iv-correction.md](./2026-11-15-t025-iv-correction.md) | `NONE` | Task correction | Fixes the reviewed caller-IV/randomized-encryption defect: Android Keystore generates the 12-byte wrap IV on encryption, `wrapIv` keeps the FXC1 format, provider output is length-checked, and decrypt still uses the stored IV; 40 JVM tests pass; 10 instrumentation tests compile; the software-emulated TCG guest crash-loops its system server, so the real Android run remains `NOT_RUN` |
| [2026-11-15-t025-unwrap-tag-decision.md](./2026-11-15-t025-unwrap-tag-decision.md) | `NONE` | Decision analysis | Audits the `storage-format` §2.3 versus §5/§7/ports/errors collision for unwrap tag mismatch (`SAVE-002` versus `SAVE-003`); confirms no owner decision covers it, keeps the current §5/§7/ports `SAVE-003` behavior, and records options/impacts for the owner with T025 Android instrumentation `NOT_RUN` |
| [2026-11-15-t025-unwrap-tag-resolution.md](./2026-11-15-t025-unwrap-tag-resolution.md) | `NONE` | Task correction | Applies the owner decision that unwrap authentication/tag mismatch is integrity damage `SAVE-003`: §2.3, the listing reason codes in storage-format/ports/data-model, and the testkit fault taxonomy now align with §5 and the implementation; aggregate key loss stays `SAVE-002`, global provider/reset `SAVE-008`; 40 JVM, 108 ports, and 111 testkit tests pass; Android remains `NOT_RUN` |
| [2026-11-15-t025-instrumented-alias-isolation.md](./2026-11-15-t025-instrumented-alias-isolation.md) | `NONE` | Security correction | Replaces the instrumented test's global `deleteAllAggregateAliases` sweep with a unique `feldexa.test.v1.<runToken>.` alias namespace and exact-only tracked cleanup; adds a JVM static guard and an Android foreign-test-alias regression; 43 JVM tests pass and 12 instrumentation tests compile; Android remains `NOT_RUN` |
| [2026-11-15-emulator-t025-keystore.md](./2026-11-15-emulator-t025-keystore.md) | `EMULATOR` | Superseded historical run record | 12/12 T025 tests ran on an isolated `Feldexa_API31` google_apis x86_64 software-TCG AVD; the `EMULATOR`/`PASS` class is invalid under §2 because the run was not an Orca-allocated Pixel 7 API 35. The file is preserved as the frozen historical run record per §1 and is not acceptance; see the evidence-governance correction. |
| [2026-11-15-t025-api31-evidence-governance.md](./2026-11-15-t025-api31-evidence-governance.md) | `NONE` | Evidence-governance collision | No currently allowed class represents an actual Android run outside the Orca-allocated Pixel 7 API 35 profile: `NONE` cannot classify runtime, while `EMULATOR`/`DEVICE` would be false. The old report is preserved as superseded, the false `NONE` replacement is withdrawn, and options are documented; no convention change and no acceptance. |
| [2026-11-15-t025-pixel7-api35-not-run.md](./2026-11-15-t025-pixel7-api35-not-run.md) | `NONE` | NOT_RUN blocker | Orca reports no attached T025 emulator session; installed AVDs are API 31/36 only and no `system-images;android-35` package is installed; `attach` can make an existing AVD active but provides no exclusive worktree reservation. The Pixel 7 API 35 EMULATOR gate is `NOT_RUN`; no Android tests were run and no API 35, DEVICE, or performance claim is made. |
| [2026-11-15-t025-pixel7-api35-tcg-not-run.md](./2026-11-15-t025-pixel7-api35-tcg-not-run.md) | `NONE` | NOT_RUN boot failure | A temporary official API 35 google_apis x86_64 image and Pixel 7 AVD were created only under `/tmp`; under TCG the guest reached adb but `sys.boot_completed` stayed empty, the package service was absent, system_server never started, and emulator logs showed missing AVX/F16C plus QEMU CPU hangs. No Orca attach or tests; no API 35, DEVICE, or performance claim. |
| [2026-11-15-emulator-t025-pixel7-api35-kvm-keystore.md](./2026-11-15-emulator-t025-pixel7-api35-kvm-keystore.md) | `EMULATOR` | Pixel 7 API 35 KVM run | T025 Keystore instrumentation 12/12 PASS on a uniquely provisioned Pixel 7 API 35 AVD started and assigned through Orca; the emulator process held an open KVM device node and KVM vCPU descriptors, the guest completed boot with the package service, and the unchanged app/test APKs were installed byte-identically; one Orca session and one adb device were observed before and during the run. No DEVICE or performance claim. |
| [2026-11-15-t025-main-merge.md](./2026-11-15-t025-main-merge.md) | `NONE` | Integration record | Merged `origin/main` `fe310402` into `e9fd6d6` as merge `8d377f6` (parents `e9fd6d6`, `fe310402`); only the `fault_kind.dart` conflict was resolved, preserving T036 `keystoreReset` and T025 `corruptKeyMaterial` SAVE-003 and updating T036's mapping/tests; JVM 43/43, testkit 153/153, T030 font metrics 20/20, targeted analysis clean; the API31 run is preserved only in the superseded historical report, with no valid evidence class, no project EMULATOR, API 35, DEVICE, or performance claim; see the evidence-governance correction |
| [2026-11-15-t025-save002-fault-correction.md](./2026-11-15-t025-save002-fault-correction.md) | `NONE` | Integration correction | Restores `FaultKind.aggregateKeyUnavailable` → `KeyUnavailableException` (`SAVE-002`), keeps `corruptKeyMaterial` → `CorruptDataException` (`SAVE-003`), corrects the testkit README and the API 31 wording (one read-only `containsAlias` check on a random production-form alias, no production key created/deleted), and adds host regressions; 154 testkit, 43 JVM; Android code/APK identity unchanged, no runtime rerun; evidence governance remains open |
| [2026-11-15-t026-encrypted-store-evidence.md](./2026-11-15-t026-encrypted-store-evidence.md) | `NONE` | Task evidence | T026 `FXC1` v1 container, per-aggregate KEK commit/read-back, deletion, stale-temp/orphan-alias sweep, head fallback, and native fault injection; 49 store/container/recovery + 9 fault JVM tests and the full 101-test JVM suite pass; no runtime claim here (see the EMULATOR companion) |
| [2026-11-15-emulator-t026-pixel7-api35-kvm-encrypted-store.md](./2026-11-15-emulator-t026-pixel7-api35-kvm-encrypted-store.md) | `EMULATOR` | Pixel 7 API 35 run | T026 10/10 and T025+T026 22/22 PASS on an Orca-allocated exclusive Pixel 7 API 35 AVD with the real `AndroidKeyStore`; installed app/test APK hashes matched the build; no `DEVICE`, performance, StrongBox, or independent host-KVM claim |
| [2026-11-15-t026-review-corrections-evidence.md](./2026-11-15-t026-review-corrections-evidence.md) | `NONE` | Task correction | T026 review response for `365b384`: serialized compare-and-commit, chunk-bounded verification, monotonic/fail-closed recovery order, and a head-protected pruning primitive; 109 JVM tests; retention-policy ownership options recorded; committed evidence bundle with hash manifest; host-KVM probe `UNAVAILABLE` |
| [2026-11-15-emulator-t026-review-corrections-pixel7-api35.md](./2026-11-15-emulator-t026-review-corrections-pixel7-api35.md) | `EMULATOR` | Pixel 7 API 35 review rerun | T026 13/13 and T025+T026 25/25 PASS on an Orca-allocated exclusive Pixel 7 API 35 AVD with the real `AndroidKeyStore` after `84f2276`; installed APK hashes match; no `DEVICE`, performance, StrongBox, or independent host-KVM claim |
| [artifacts/t026-review-2026-11-15/README.md](./artifacts/t026-review-2026-11-15/README.md) | `NONE` | Committed evidence bundle | Redacted T026 review-correction evidence: hash manifest, JUnit XMLs, instrumentation/device logs, reproduction summaries, and `verify.sh`; raw logcat and 216 MiB APK binaries are intentionally not published |
| [2026-11-15-t026-pruning-contract-gap.md](./2026-11-15-t026-pruning-contract-gap.md) | `NONE` | Contract-gap analysis | Post-review of `3197ca3`: §3.1 step 8 retention cannot be derived from the canonical persisted state (`rev/<id>.fx1` is `RevisionContent` without `kind`; only current head/meta/pointer carry kind); exact contract paths and five options recorded, three deterministic tests (112 JVM total) prove identical histories can need different keep sets; app/test APK hashes unchanged; no product decision |
| [2026-11-15-t026-mtime-durability-evidence.md](./2026-11-15-t026-mtime-durability-evidence.md) | `NONE` | Security correction | T026 revision-order mtime durability after `3197ca3`: explicit `setLastModified -> fsync(file) -> rename -> fsync(parent)`, `ORDERING_FSYNC` fault point, two deterministic ordering tests, 114 JVM tests; retention remains owner-blocked; committed mtime bundle |
| [2026-11-15-emulator-t026-mtime-durability-pixel7-api35.md](./2026-11-15-emulator-t026-mtime-durability-pixel7-api35.md) | `EMULATOR` | Pixel 7 API 35 mtime rerun | T026 13/13 and T025+T026 25/25 PASS after `53ffe78` on an Orca-allocated exclusive Pixel 7 API 35 AVD with the real `AndroidKeyStore`; app APK `93b92c...`, test APK unchanged; no `DEVICE`, performance, StrongBox, or independent host-KVM claim |
| [artifacts/t026-mtime-2026-11-15/README.md](./artifacts/t026-mtime-2026-11-15/README.md) | `NONE` | Committed evidence bundle | Hash manifest, seven JUnit XMLs, redacted instrumentation/device logs, allocation record, ordering finding, and `verify.sh` for the mtime correction; raw logcat and APK binaries intentionally not published |
| [2026-11-15-t026-head-history-evidence.md](./2026-11-15-t026-head-history-evidence.md) | `NONE` | Task correction | Owner decision implemented: bounded known-kind history in `head.fx1`, automatic last-3-autosave/newest-explicit/newest-recovery retention after verified commit, conservative legacy handling, startup reconciliation; 118 JVM tests; supersedes the pruning contract-gap report |
| [2026-11-15-emulator-t026-head-history-pixel7-api35.md](./2026-11-15-emulator-t026-head-history-pixel7-api35.md) | `EMULATOR` | Pixel 7 API 35 head-history run | T026 16/16 and T025+T026 28/28 PASS after `c30cb66` on an Orca Pixel 7 API 35 AVD with the real `AndroidKeyStore`; app/test APK hashes match; no `DEVICE`, performance, StrongBox, or independent host-KVM claim |
| [artifacts/t026-head-history-2026-11-15/README.md](./artifacts/t026-head-history-2026-11-15/README.md) | `NONE` | Committed evidence bundle | Hash manifest, seven JUnit XMLs, redacted instrumentation/device logs, allocation record, policy summary, and `verify.sh` for the head-history implementation; raw logcat and APK binaries intentionally not published |
| [2026-11-15-t026-prune-durability-evidence.md](./2026-11-15-t026-prune-durability-evidence.md) | `NONE` | Security correction | T026 prune-delete durability after `ff8f7fb`: history is trimmed only after the revision-directory delete fsync succeeds; fsync failure keeps full history and retries on startup/save; two deterministic crash-resurrection tests; 120 JVM tests |
| [2026-11-15-emulator-t026-prune-durability-pixel7-api35.md](./2026-11-15-emulator-t026-prune-durability-pixel7-api35.md) | `EMULATOR` | Pixel 7 API 35 prune rerun | T026 17/17 and T025+T026 29/29 PASS after `0c75c57` on an Orca Pixel 7 API 35 AVD with the real `AndroidKeyStore`; app/test APK hashes match; no `DEVICE`, performance, StrongBox, or independent host-KVM claim |
| [artifacts/t026-prune-durability-2026-11-15/README.md](./artifacts/t026-prune-durability-2026-11-15/README.md) | `NONE` | Committed evidence bundle | Hash manifest, eight JUnit XMLs, redacted instrumentation/device logs, allocation record, prune-durability summary, and `verify.sh`; raw logcat and APK binaries intentionally not published |
| [2026-11-15-t026-prune-retry-evidence.md](./2026-11-15-t026-prune-retry-evidence.md) | `NONE` | Security correction | T026 retry after `0785e5c`: a prune retry with no new deletes still confirms directory durability before dropping a missing history entry; save-side rebuild retains unconfirmed entries; deterministic repeated-fsync/no-resurrection tests; 122 JVM tests |
| [2026-11-15-emulator-t026-prune-retry-pixel7-api35.md](./2026-11-15-emulator-t026-prune-retry-pixel7-api35.md) | `EMULATOR` | Pixel 7 API 35 retry rerun | T026 18/18 and T025+T026 30/30 PASS after `57ce38b` on an Orca Pixel 7 API 35 AVD with the real `AndroidKeyStore`; app/test APK hashes match; no `DEVICE`, performance, StrongBox, or independent host-KVM claim |
| [artifacts/t026-prune-retry-2026-11-15/README.md](./artifacts/t026-prune-retry-2026-11-15/README.md) | `NONE` | Committed evidence bundle | Hash manifest, eight JUnit XMLs, redacted instrumentation/device logs, allocation record, retry summary, and `verify.sh`; raw logcat and APK binaries intentionally not published |
| [2026-11-15-t026-prune-cap-evidence.md](./2026-11-15-t026-prune-cap-evidence.md) | `NONE` | Security correction | T026 capacity after `e2775f8`: before the 16-entry cap, a missing known history entry is fsync-confirmed; otherwise the save is refused with retryable `SAVE-003` before any head change. >16-attempt and resurrection tests; 123 JVM tests; alternative options documented |
| [2026-11-15-emulator-t026-prune-cap-pixel7-api35.md](./2026-11-15-emulator-t026-prune-cap-pixel7-api35.md) | `EMULATOR` | Pixel 7 API 35 capacity rerun | T026 19/19 and T025+T026 31/31 PASS after `df625d7` on an Orca Pixel 7 API 35 AVD with the real `AndroidKeyStore`; app/test APK hashes match; no `DEVICE`, performance, StrongBox, or independent host-KVM claim |
| [artifacts/t026-prune-cap-2026-11-15/README.md](./artifacts/t026-prune-cap-2026-11-15/README.md) | `NONE` | Committed evidence bundle | Hash manifest, eight JUnit XMLs, redacted instrumentation/device logs, allocation record, capacity/options summary, and `verify.sh`; raw logcat and APK binaries intentionally not published |
| [2026-11-16-t027-host-evidence-94ef57b.md](./2026-11-16-t027-host-evidence-94ef57b.md) | `NONE` | Task evidence (Review-B correction) | T027 accepted Review-B correction `94ef57b`: native alpha colour types 4/6 remain accepted, opaque 0/2/3 require a validated `tRNS` chunk, and truly alpha-free 0/2/3 fail with canonical `SAVE-007` without transcoding/mutating bytes; 994 Dart host tests and a 260-test JVM suite (21 `SignaturePng`, 53 `EncryptedStore`, 10 `StoreService`); exact 281-file source manifest identical before/after; no Android runtime claim; supersedes `db8ce0f` for final acceptance |
| [2026-11-16-emulator-t027-store-evidence-94ef57b.md](./2026-11-16-emulator-t027-store-evidence-94ef57b.md) | `EMULATOR` | Task evidence (Review-B correction) | T027 `94ef57b` on an exclusively allocated Pixel 7 API 35 AVD with real `EncryptedStore`/`AndroidKeyStore`: 34/34 storage, 20/20 channel, and 1/1 Dart→MethodChannel→native PASS; real gray+alpha and `tRNS`-backed PNGs accepted and round-tripped, real opaque RGB rejected with `SAVE-007` while prior bytes/head/revisions stayed unchanged, malformed `tRNS` rejected, 1024/1025 and `PLT-002` unchanged; canonical root and exact APK/in-guest hashes; no DEVICE, release-heap, performance, full UI/T031, or independent host-KVM probe claim |
| [artifacts/t027-review-b-94ef57b/README.md](./artifacts/t027-review-b-94ef57b/README.md) | `NONE` | Committed evidence bundle | T027 `94ef57b` source/generated manifests, 260-test JVM XML, 34/34 storage + 20/20 channel XML, build/integration/canonical-root/host/logcat logs (path-redacted), exact APK hashes, raw-evidence hashes, and `verify.sh`; raw APKs and raw logs are not published |
| [2026-11-16-t027-host-evidence-db8ce0f.md](./2026-11-16-t027-host-evidence-db8ce0f.md) | `NONE` | Historical/superseded | T027 corrected candidate `db8ce0f`; retained only as history. Superseded for final acceptance by the `94ef57b` Review-B correction of the accepted signature alpha/`tRNS` finding |
| [2026-11-16-emulator-t027-store-evidence-db8ce0f.md](./2026-11-16-emulator-t027-store-evidence-db8ce0f.md) | `EMULATOR` | Historical/superseded | T027 corrected candidate `db8ce0f`; retained only as history. Superseded for final acceptance by the `94ef57b` Review-B correction |
| [artifacts/t027-review-a-db8ce0f/README.md](./artifacts/t027-review-a-db8ce0f/README.md) | `NONE` | Historical/superseded | T027 `db8ce0f` evidence bundle retained as history; superseded by `artifacts/t027-review-b-94ef57b/` for final acceptance |
| [2026-11-16-t027-host-evidence-final.md](./2026-11-16-t027-host-evidence-final.md) | `NONE` | Historical/superseded | Corrected candidate `d45f4df`; retained only as history. Superseded by the `db8ce0f` and `94ef57b` corrections; must not be used for final acceptance |
| [2026-11-16-t027-emulator-store-evidence-final.md](./2026-11-16-t027-emulator-store-evidence-final.md) | `EMULATOR` | Historical/superseded | Corrected candidate `d45f4df`; retained only as history. Superseded by the `db8ce0f` and `94ef57b` corrections; must not be used for final acceptance |
| [artifacts/t027-final-d45f4df/README.md](./artifacts/t027-final-d45f4df/README.md) | `NONE` | Historical/superseded | T027 `d45f4df` evidence bundle retained as history; superseded by `artifacts/t027-review-a-db8ce0f/` and `artifacts/t027-review-b-94ef57b/` |
| [2026-11-16-t027-host-evidence.md](./2026-11-16-t027-host-evidence.md) | `NONE` | Historical/superseded | Pre-correction run recorded `HEAD=3a3202c` before the code commit `5b4c295`; retained only as history and must not be used for final acceptance |
| [2026-11-16-t027-emulator-store-evidence.md](./2026-11-16-t027-emulator-store-evidence.md) | `EMULATOR` | Historical/superseded | Pre-correction run recorded `HEAD=3a3202c` before the code commit `5b4c295`; retained only as history and must not be used for final acceptance |
| [2026-11-17-t038-evidence.md](./2026-11-17-t038-evidence.md) | `NONE` | Task evidence | T038 SAF streaming import (host-JVM tests, `flutter analyze`), correction rounds 1-3, no emulator/device evidence, no channel wiring (T040/T041) |
| [2026-11-18-t039-evidence.md](./2026-11-18-t039-evidence.md) | `NONE` | Task evidence | T039 PDF preflight page geometry and encryption/damage classification; host-JVM only; 25 new tests; 304 at the T039 candidate, 325 on the merged base; 0 failures; page-count bound review correction; debug build compiles; no Android runtime, emulator or device evidence; no channel wiring (T040/T041) |
| [2026-11-18-t040-evidence.md](./2026-11-18-t040-evidence.md) | `NONE` | Task evidence | T040 two-pass streaming encrypted source copy (64 KiB hash, 1 MiB FXC1 write), decrypting seek reader for preflight, atomic verified initial revision/meta commit, duplicate rejection, source-of-truth read-back, failure/cancellation cleanup; review-correction round 1 removes the lifecycle/handle deadlock, owns the second provider stream, propagates aggregate/key cleanup failures, and adds commit/stream/cleanup interleaving tests; round 2 makes provider-stream ownership single and explicit (`writeContainer` non-owning, caller `use`, caller-owned `countPass`), removes the double close, and adds close-count tests with a deterministic RED on `e788367`; host-JVM only; 357 tests / 17 suites / 0 failures; `flutter analyze --no-pub` clean; debug APK compiles; no Android runtime, emulator or device evidence; German mapping/viewer/integration remain T041/T042/T044/T046/T048 |
| [2026-11-18-t041-evidence.md](./2026-11-18-t041-evidence.md) | `NONE` | Task evidence | T041 German import-failure mapping and FR-009 rejection gate; 22 new host-VM tests (153 total, 0 failures); every `IMP-*`, `IMP-000`, `PLT-004` and import-reachable `SAVE-*` code resolved through `AppLocalizations`; unknown codes fall back to `IMP-005`; `isUnrecognized` is explicit state true only for the unknown-cause fallback; the password predicate derives from the canonical `import.rejected.passwordProtected` ports key; `import.rejected.unsupportedEncryption` keeps the observed `IMP-001` code but renders the truthful `IMP-004` text (FR-007 Review A corrections); no Android runtime, emulator or device evidence; no Kotlin change |
| [2026-11-18-t042-evidence.md](./2026-11-18-t042-evidence.md) | `NONE` | Task evidence | T042 pdfrx page viewer and source-point geometry mapping; 41 new host-VM/widget tests (194 total, 14 files, 0 failures); `PageGeometry.displaySize` is the only page geometry input; view ↔ display mapping at 0.5×–8×, rotations 0/90/180/270 and CropBox offsets; DPR-independent; lazy pages; injected source-bytes/renderer seams; no Android runtime, emulator or device evidence; no rendering-quality claim |
| [2026-11-18-t043-evidence.md](./2026-11-18-t043-evidence.md) | `NONE` | Task evidence | T043 page-strip navigation before analysis finishes; 15 new host-VM widget tests (209 total, 15 files, 0 failures); all four analysis states plus unreadable/uncertain markers with all-pending navigation; tap delegates to `PageViewController.scrollToPage`; exposed selection and lazy 100-page reveal; compact indicator below 600 dp and full strip at 600 dp; German semantic labels/hints and ≥ 48 dp targets; 200 % text scale; no Android runtime, emulator, browser or device evidence; no `page_view.dart`/`page_state.dart` change |
| [2026-11-18-t045-evidence.md](./2026-11-18-t045-evidence.md) | `NONE` | Task evidence | T045 80 MiB import cap and IMP-007 wording verification; cap enforcement and the corrected German text were already present, so no production Kotlin, catalog, ARB, generated-localization, or mapper change was needed; 6 new host-JVM tests (363 total / 17 suites / 0 failures) cover cap−1/cap/cap+1 at the service seam, the clamp above the cap, the 83,886,080-byte constant/store binding, and the real store's exact 1,000-byte boundary; 1 new host-VM test (210 total / 16 files) compares catalog §1 IMP-007, ARB, generated `AppLocalizationsDe`, and the T041 mapper character-for-character for „80 MiB (83.886.080 Bytes)“ and rejects „80 MB“; no Android runtime, emulator or device evidence; no performance claim; provenance correction: the first pass read the skill file without invoking the registered command (documented Principle IX deviation), and the correction round invoked it for verification only with no code or test change |
| [2026-11-18-t044-evidence.md](./2026-11-18-t044-evidence.md) | `NONE` | Task evidence | T044 partially unreadable page state and the `IMP-006` warning; 34 new host-VM tests (228 total, 15 files, 0 failures); `unreadable == true` or a failed analysis with the `IMP-006` key marks a page unreadable and non-renderable; the T040 1x1 placeholder is parsed from persisted JSON and suppressed; a partial document stays a success with catalog-only `imp006`/`imp006Recovery` text and ascending 1-based pages; an all-unreadable input returns the explicit error state; no Android runtime, emulator or device evidence; no page strip, viewer wiring or UI; provenance correction: the first pass read the skill file without invoking the registered command (documented Principle IX deviation), and the correction round invoked it for verification only with no code or test change |
| [2026-11-18-emulator-t046-evidence.md](./2026-11-18-emulator-t046-evidence.md) | `EMULATOR` | Android import integration runtime | T046 US1/SC-011: 8/8 integration tests PASS on the exclusively allocated Pixel 7 API 35 AVD `T025_Pixel7_API35_KVM_20261115` (serial `emulator-5554`); single-page, five-page, and mixed-geometry imports match catalogue page count/order/geometry/rotation, source bytes and modification time stay unchanged, the picked source is deleted before protected-store read-back, and every readable page is PDFium pixel-identical between original and decrypted stored bytes; protected/truncated/non-PDF/unknown inputs produce the exact German `IMP-001`/`IMP-002`/`IMP-004`/`IMP-005` text with zero documents created, and the deterministic partial-damage input succeeds with the `IMP-006` page-2 warning and a usable readable page; one declared debug-only picker/forced-unknown seam is inert in release and flagged for review; host-only checks are separate (244 tests, analyze, release Kotlin compile); no `DEVICE`, pixel-scan, or performance claim |
| [2026-11-18-emulator-t048-evidence.md](./2026-11-18-emulator-t048-evidence.md) | `EMULATOR` | Android source-integrity runtime | T048 US1/SC-019: 2/2 trials PASS on the exclusively allocated Pixel 7 API 35 AVD `T025_Pixel7_API35_KVM_20261115` (serial `emulator-5554`); synthetic `sf-003` and `sf-001` imports keep byte identity and modification time, the picked file is moved to another directory and then deleted, and the saved document is reopened from storage, read back through `store.readSource`, and re-rendered with PDFium from the decrypted protected copy with identical page digests before and after the deletion; the export clause is `PARTIAL`/`UNAVAILABLE` through the capability-conditional check: the `export.validate` probe returned the documented `PLT-001`/`platform.unsupported` signature, the unavailable branch skipped the clause and asserted that no success payload, verification record, or artifact exists, and the real artifact/verification/render assertions activate automatically once T104 lands; no new seam; host-only checks are separate (244 tests, analyze, release Kotlin compile); no `DEVICE`, pixel-scan, or performance claim |
| [2026-11-21-emulator-t071a-composition.md](./2026-11-21-emulator-t071a-composition.md) | `EMULATOR` (host checks `NONE`) | Task evidence | T071A editor review/fill composition, correction 4 candidate `f342cc4` (tree `cc996d8`, base `127f978`): `PageView` per-page overlay hook, T069/T077 overlays with an always-present selection surface, type-appropriate `FieldValueSheet` with pre-validated text limits and a shared save/focus-loss/Enter/done commit path, `setFieldValue` with compatible-incompatibility resolution, T091 status/PRIV-001, and T095 start-list reopen; unreadable stored rows are disabled. Host `NONE`: focused combined 21/21 (editor-only 12/12; pre-test candidate 430/430 app and 20/20 focused in `correction-4-host-gates.txt`), app 431/431, application 177/177, analyze/format/diff clean (`correction-4-regression-host-gates.txt`); Y adds one test-only F9 regression and production app source remains identical to `f342cc4`. Real Pixel 7 API 35 journey PASS on `emulator-5554` (AVD `T025_Pixel7_API35_KVM_20261115`): APK 173200893 bytes SHA-256 `4780e50d...`, damaged fixture `57c1ade1...`, `T071A_CLEANUP_DONE`, privacy PASS. Five distinct screenshots: `overlay-selection` = settled editor with selection, no sheet; `value-sheet` = sheet with entered German value above the real IME; `saved-status` = sheet reopened after the verified save prefilled from the store read-back with the T091 saved label; `document-list` = start list after leaving; `reopened-value` = reopened document's sheet prefilled from the reopened read-back. T071A markers are host-side (`markers-integration.txt`), not device logcat. T071 remains blocked; T097/OD-4 blocked; signature/TalkBack/DEVICE `NOT_RUN`. |
| [2026-11-21-emulator-t071-touch.md](./2026-11-21-emulator-t071-touch.md) | `EMULATOR` (host checks `NONE`) | Task evidence | T071 Android touch move/resize review test on the composed T071A/T071B editor: base `d53fb57`, **evidence candidate `44eb3e4` (tree `2747c4ea`, the commit that ran)**, correction-1 evidence and final head `de39679` (tree `e910aa43`); correction 1 closes Review A findings 1-8 and correction 2 is documentation/evidence only on top of `de39679` (marker-contract claim corrected to 27 exact shapes + 3 occurrence counts, post-commit diff-check gate record `host-gates-post-commit.txt`, two expected `pm clear` exit=1 lines stated, candidate and head named consistently). Exactly-one-revision proof: a counting facade around the real editor runtime of the production `createImportRuntime()` composition counts real `saveRevision` calls; each of the 14 committed gestures asserts 0 real calls during a hold window longer than the fastest measured commit latency (holds 1160-1991 ms, latencies 618-1114 ms), exactly 1 call for the gesture, and per held frame an active gesture, a painted preview, `reviewBusy` false and unchanged head/content; a pure negative control rejects 2/held/0 saves and a real double-commit injection (same request forwarded twice, recorded `SECOND_SAVE=REJECTED`) must fail the assertion. Stale acknowledgements fail closed (`T071_HANDSHAKE_FAIL`) and the driver removes them with a checked exit code plus verified empty result (`handshake-preflight.txt`); the resize zoom margin is asserted and recorded (`20 pt * 3 * fit = 41.47 px > 36 px` pan slop); screenshot markers carry one `T071_` prefix and the driver matches 27 exact anchored shapes plus 3 occurrence counts (= 30 exact checks: 14 commits, 12 screenshots, 12 acks) and rejects doubled prefixes, while `T071_SHOT` (12 observed) is not contract-checked and is reported as an artifact count; `CLEANUP_DONE` moved into `tearDownAll` after verified cleanup and the driver verifies the device cleanup (`cleanup-verification.txt`, `verified=1`); the field is selected through the real tap -> value sheet -> close path; every committed log is URL-redacted and the privacy scan covers the integration log, `logcat-flutter.log`, `commands.txt` and `git-identity.txt` (8/8 PASS). Journey: body drags at 0.5x/1x/3x/8x fit-width with the gesture-start delta divided by the view scale once, one 8x drag clamped exactly to the page edge, all four corner and all four edge handles with every non-dragged edge bit-for-bit fixed and a free aspect ratio, the `centerLeft` handle claimed 8.29 dp outside the stored rectangle (24 dp is the contract constant, not a measurement), the 4 x 4 pt minimum against the anchor, a pointer cancel with zero commits, a bit-exact T067 undo, and two-finger pan/pinch that never edits geometry while still zooming (1.382 -> 2.791) and panning. Host `NONE`: app 469/469, focused geometry+composition 22/22, `feldexa_ui` geometry 31/31, analyze/format/diff clean. Real Pixel 7 API 35 PASS on `emulator-5554` (AVD `T025_Pixel7_API35_KVM_20261115`, 1080x2400 at 420 dpi, 411 x 206 dp page viewport): APK 173421516 bytes SHA-256 `1d12363b...`, fixture 5956 bytes `22c939cc...` and damaged `57c1ade1...`, 107-line authoritative host-side marker sequence, twelve distinct screenshots, twelve observed `SHOT` markers, privacy 8/8 PASS, `T071_CLEANUP_DONE`, `verified=1` handshake/cleanup gates, and a post-commit `git diff --check` exit 0 at `de39679` (the historical gate-6 exit=2 was the pre-commit dirty evidence bundle). Superseded bundle: first-pass candidate `398f4e4`. **Integrated 2026-11-21 as PR #265 (merge `d562fb8`) from final candidate `3f8401c` (tree `753944ac`) after two independent read-only PASS reviews (A2 code/closure, B2 fulfillment/evidence; Codex quota-unavailable, approved DeepSeek Flash fallback via OpenCode `plan`); executed evidence candidate `44eb3e4` (tree `2747c4ea`), evidence head `de39679` (tree `e910aa43`).** `DEVICE` acceptance, TalkBack, stylus, export of the resized geometry and any performance claim remain `NOT_RUN`. |
| [artifacts/2026-11-21-t071a-composition/README.md](./artifacts/2026-11-21-t071a-composition/README.md) | `EMULATOR` | Committed evidence bundle | Historical preflight/correction-2/3 files plus the correction-4 run bundle: host gates (app 431/431, application 177/177, focused combined 21/21; pre-test 430/430 and 20/20 in `correction-4-host-gates.txt`), APK/device/fixture hashes, 57-line authoritative host-side marker sequence, integration log, privacy checks, run status, and five distinct journey screenshots (overlay/selection without sheet, value sheet above the IME, saved-status sheet prefilled from the store read-back, start list, reopened-value sheet); no APK binary or raw full logcat |

| [2026-11-12-task-issue-mapping.md](./2026-11-12-task-issue-mapping.md) | `NONE` | Historical snapshot | 2026-11-12T15:50Z all-open mapping; not live issue state |
| [2026-11-12-task-issue-mapping.json](./2026-11-12-task-issue-mapping.json) | `NONE` | Historical snapshot | Machine-readable dated snapshot; do not overwrite with current state |
| `backups/` | — | Not evidence | Pre-edit snapshots |
| [2026-11-18-t049-evidence.md](./2026-11-18-t049-evidence.md) | `NONE` | Task evidence | T049 German import-message and error-semantics tests; 14 new host-VM tests (258 total, 16 VM suites, 0 failures); exact catalog text for 21 import-reachable cases, FR-007 password truthfulness including the truthful `IMP-004` unsupported-encryption rendering, FR-094 no codes/paths/URIs/content in text or identities, FR-009 zero document creation for every rejection/cancellation/untyped failure, and `IMP-006` success with ascending 1-based pages matching T044; no Android runtime, emulator, browser or device evidence; no production, ARB or Gradle change |
| [2026-11-18-simulated-t047-evidence.md](./2026-11-18-simulated-t047-evidence.md) | `SIMULATED` | Task evidence | T047 deterministic Chrome import journey over the committed synthetic fixtures and the T028 `SIMULATED` adapters; 6/6 browser tests pass (`sf-003` five-page order/rotation/display geometry/display name, exact German `IMP-001`/`IMP-002`/`IMP-004` rejections with no stored record, cancellation, `SIMULATED` registry/evidence labels and banner rendering); 258/16 host suite and analyze/format/validator pass separately; no Android runtime, emulator, device, APK, or performance claim |
| [2026-11-18-t148-evidence.md](./2026-11-18-t148-evidence.md) | `NONE` | Task evidence | T148 Phase 13 US1 composition; German start surface, real `AndroidImportClient`/`ImportFlow` composition with `AndroidStoreClient` read-back, editor route with `PageView`/`PageStrip`, `derivePageStates` `IMP-006` warning, and catalog-backed rejection/cancellation; 5 new host-VM tests (263 total, 17 VM suites, 0 failures); `page_view.dart`/`page_strip.dart`/`page_state.dart`, ARB, Gradle, and `tasks.md` unchanged; no Android runtime, emulator, browser, or device evidence; T149 journey and T150 strip vocabulary remain |
| [2026-11-18-t150-evidence.md](./2026-11-18-t150-evidence.md) | `NONE` | Task evidence | T150 page-strip analysis-state vocabulary moved from hard-coded Dart into catalog §8 and the ARB (`pageAnalysisPending`…`pageAnalysisFailedHint`); one new exact catalog/ARB/generated-text test (259 total, 17 VM suites / 19 test files, 0 failures), 15 unchanged strip tests, analyze/format/validator pass; host-VM only, no Android/UI runtime, visual, or TalkBack claim |
| [2026-11-18-emulator-t149-evidence.md](./2026-11-18-emulator-t149-evidence.md) | `EMULATOR` | Real system-picker US1 journey | T149 Phase 13 convergence, no GitHub issue: the production start surface opens the real `ACTION_OPEN_DOCUMENT` picker, and the host driver navigates `DocumentsUI` to Downloads and taps the exact rows. Round 1 imports synthetic `sf-001` (2 pages), reaches the editor route, asserts both strip pages and the German `Seite 1 von 2` / `Seite 2 von 2` semantics, navigates to page 2, mounts the real pdfrx `PageView` with a rendered first page, and verifies exactly one committed document by SHA-256 and page-1 render digest. Round 2 imports `sf-protected` and asserts the exact `IMP-001` text and recovery, no editor, no extra document, and no machine text. Cleanup deletes the document and restores the store set. Debug build on Pixel 7 API 35 `emulator-5554`; no `DEVICE`, performance, TalkBack, or pixel-fidelity claim. |
| [2026-11-18-t050-evidence.md](./2026-11-18-t050-evidence.md) | `NONE` | Task evidence | T050 recognition-output §1–§2 suggestion-envelope contract test, Review A correction round 1, delta-review correction 2, review-corrections 3–4, and documentation-only correction 5; production pure-Dart `lib/src/suggestion_schema.dart` encodes the envelope/suggestion/evidence/failure/timings key sets, ranges, id grammar, rect grid/bounds, cues, conflicts, failure shape, §5.2 comparator, strict integer guards, content-free `<unknown-field>` diagnostics, and the §5-item-5 canonical projection (excludes `analysisRunId`, `timings`, `evidenceClass`); the refactored test uses it as the only oracle, every negative asserts exact finding count/code(s)/no masked other-path violation, and invalid-cue fixtures include `underline`; 48 schema tests and `+109` package tests (0 failures), analyze/format/validator/diff pass on the identical code tree, with no Flutter rerun for the documentation-only correction 5; ascending cue order and §6 conflict completeness are enforced; `raster_test.dart` was changed by T050 correction 3 (dependency/suppression cleanup), so T051 production files are untouched; current artifacts: schema 49237 bytes / SHA-256 `26e404704da71f5ae3318dbc24619021ee4dec55ccbac227ce3d101f5e51d703`, test 60962 bytes / SHA-256 `34dac38fda3fa6fbf57a2d1c283383e363ff94bf20f1e4a1ddd190c39aa2df3b`, report 79195 bytes / SHA-256 `7370f07198c6355a56a4b33c7e76d1a47a10f9639e8f56cafbe72006e73a48e1`; correction 4 added content-free diagnostics, strict `schemaVersion`/suggestion-`pageIndex` types, and run-ID-excluded canonical projection; correction 5 aligns the attestation wording with the preserved coordinator handoff JSON, records that the `worker_done` was rejected (`consumer_fenced`, no delivery, dispatch stopped/released), and corrects the unknown-key multiplicity wording; no detector/raster/OCR/persistence/runtime evidence; T057/T058 must import `src/suggestion_schema.dart`; `pageUncertain == false` may carry a valid reason |
| [2026-11-18-t051-evidence.md](./2026-11-18-t051-evidence.md) | `NONE` | Task evidence | T051 200 DPI grayscale page raster analysis primitives and host-VM tests; Review A correction makes `InkCoverage.exceedsPercent` overflow-free with `BigInt`, adds a documented 40,000-px/1.6e9-pixel extent cap with fail-closed `ArgumentError`s, and adds nine boundary/overflow tests (61 tests / 1 test file / 0 failures; RED captured before the fix); `RasterSize`, `GrayRaster`, `PixelRect`, `InkCoverage`, `IntegralImage`, and `RasterAnalysis` implement `coordinates-and-geometry.md` §4 and the `recognition-output.md` §2.1 ink measurement; analyze/format/validator pass; synthetic buffers only, no OCR, detector, platform rasterizer, Android, or performance claim; temporary T050 dev-dependency suppression disclosed |
| [2026-11-20-us2-integration-emulator.md](./2026-11-20-us2-integration-emulator.md) | `EMULATOR` | US2 integration convergence (issue #217, PR #221) | Real system-picker import of synthetic `sf-001` on Pixel 7 API 35 `emulator-5554`; editor analysis produced 80 suggestions (28/52), conflict markers, confirm/reject/undo and store read-back; enabled `Rückgängig` asserted before the after-review capture; host gates app 291, application 135, core 533, recognition 316, Android host 383; page-failure isolation, below-0.50 marker, signature type and privacy socket observation explicitly UNVERIFIED |
| [2026-11-20-emulator-t061-recognition.md](./2026-11-20-emulator-t061-recognition.md) | `EMULATOR` | T061 US2 recognition failure isolation | Deterministically damaged synthetic `sf-001` (page 2 `/MediaBox` neutralized) imported through the debug import hook on Pixel 7 API 35 `emulator-5554`; page 1 complete with 28 suggestions, page 2 failed with `IMP-006`/`unsupportedStructure` and zero suggestions; navigation and store read-back preserve the isolation; corpus 1.0.0 `NOT_RUN` (T033/T034); no DEVICE/performance/accessibility claim |
New reports append a row here in the same change. Results are run outcomes, not
approval.

