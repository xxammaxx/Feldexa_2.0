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
| [2026-11-15-t028-evidence.md](./2026-11-15-t028-evidence.md) | `SIMULATED` | Task evidence | T028 deterministic Web substitutes for import, raster, OCR, storage, export, and delivery; fixture-catalogue projection, verified revision read-back/retention, import-created document aggregate, global `SAVE-008` gating for new aggregates, actual-source SHA-256 re-verification in export, request/plan identity and byte-derived verification flags, canonical `ExportBlockedException`/`ExportFailedException` mapping with exact codes retained in `validate`, hard-capped raster dimensions, preview PDF with `SIMULATED` watermark and deterministic trailer; 86 host-VM tests and 1 adapter-level Chrome `SIMULATED` journey pass (FR-086/T128 full editor journey remains open); host checks are `NONE` and remain separate; no `EMULATOR`, `DEVICE`, encryption, PDFBox, print-fidelity, or performance claim |
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
| [2026-11-12-task-issue-mapping.md](./2026-11-12-task-issue-mapping.md) | `NONE` | Historical snapshot | 2026-11-12T15:50Z all-open mapping; not live issue state |
| [2026-11-12-task-issue-mapping.json](./2026-11-12-task-issue-mapping.json) | `NONE` | Historical snapshot | Machine-readable dated snapshot; do not overwrite with current state |
| `backups/` | — | Not evidence | Pre-edit snapshots |

New reports append a row here in the same change. Results are run outcomes, not
approval.
