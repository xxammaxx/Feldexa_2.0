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

Run the committed minimal check from the repository root:

```sh
python3 tools/evaluation/check_evidence_docs.py
python3 tools/evaluation/check_evidence_docs.py --revision <commit>
python3 tools/evaluation/check_evidence_docs.py --attestation-ref refs/remotes/origin/t010-attestation
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

The attestation form runs inside a fresh bundle clone. T032 still owns the
machine-readable schema and full validator.

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

The task-to-issue mapping is a dated historical snapshot. Its `OPEN` states
reflect `2026-11-12T15:50:00Z` and are not updated when issues later close; use
the GitHub issue for live state.

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
| [2026-11-12-task-issue-mapping.md](./2026-11-12-task-issue-mapping.md) | `NONE` | Historical snapshot | 2026-11-12T15:50Z all-open mapping; not live issue state |
| [2026-11-12-task-issue-mapping.json](./2026-11-12-task-issue-mapping.json) | `NONE` | Historical snapshot | Machine-readable dated snapshot; do not overwrite with current state |
| `backups/` | — | Not evidence | Pre-edit snapshots |

New reports append a row here in the same change. Results are run outcomes, not
approval.
