# Command Receipts and Correction Record — 2026-11-12

**Repository**: `xxammaxx/Feldexa_2.0`
**Feature**: `specs/001-scanned-form-workflow`
**Worker task**: `task_8a5aca75f5de` / dispatch `ctx_2d97751ebb9b`
**Status**: Corrective work completed; **no commit, push, merge, or publication** was performed.

## 1. Registered command dispatches (OpenCode server endpoint)

Every dispatch below used the supported OpenCode command endpoint
`POST /api/session/<sessionID>/command` with the registered command name and
`x-opencode-directory: /home/xxammaxx/Schreibtisch/Feldexa_2.0`. Times are UTC.

| # | Registered command | Session ID | Created (UTC) | Ended (UTC) | Outcome | Purpose |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `speckit.specify` | `ses_e2fdb6b2dffel8xHFjbuj63GiF` | 14:23:40 | 14:24:50 | `succeeded` | Correct six spec wording contradictions in place |
| 2 | `speckit.plan` | `ses_e2fd182f1ffeTCH4d1IuHohL9s` | 14:34:30 | 14:35:53 | `succeeded` | Correct contracts and plan provenance/gate order |
| 3 | `speckit.tasks` | `ses_e2fcf9527ffem08hzKF4tCaOuj` | 14:36:36 | 14:38:50 | `succeeded` | Corrective regeneration preserving T001–T147 |
| 4 | `speckit.analyze` | `ses_e2fcd0193ffeZ63I4Ds00hI4YO` | 14:39:25 | 14:42:16 | `succeeded` | Gate-5 re-analysis after corrections |
| 5 | `speckit.specify` | `ses_e2fc9f80affe0pHYN3xuz5tUTF` | 14:42:44 | 14:43:08 | `succeeded` | Final FR-062/FR-085 wording follow-up |
| 6 | `speckit.plan` | `ses_e2fc94bddffeaaYgfz2zNFNQf5` | 14:43:28 | 14:44:04 | `succeeded` | Final plan gate-table status correction |
| 7 | `speckit.analyze` | `ses_e2fc85fffffePd2lDTCaqfmhwn` | 14:44:28 | 14:47:03 | `succeeded` | Post-correction gate-5 re-analysis |
| 8 | `speckit.plan` | `ses_e2fc43980ffeWD03ywpv0NuWKf` | 14:49:00 | 14:49:41 | `succeeded` | Correct `quickstart.md` `tool/gate.sh` → `tools/gate.sh` |
| 9 | `speckit.analyze` | `ses_e2fc35545ffe4PyYh4ExvE7L85` | 14:49:59 | 14:51:13 | `succeeded` | Final gate-5 verification; gate 5 passes |

Command-source SHA-256 values (from `.opencode/commands/`):

```text
21634a45dfcf642fddb1645f4ad2980f98c89778442e47663df8a6c3a1eaf8bc  .opencode/commands/speckit.specify.md
3be8b011db9c6bb1cc77037f7d90756a6dbcbda1995cda2192818385732b27ff  .opencode/commands/speckit.plan.md
6754ae39649c8e73a5ed376ad5cfcf04422e321a10e07c5ccd92fd1b9bccf776  .opencode/commands/speckit.tasks.md
91fe16257ededdea9cc21d3cb27d539fcdd12d93ddcea52332cd4b68176b6a8d  .opencode/commands/speckit.analyze.md
```

The `speckit.tasks` hash matches `.specify/integrations/opencode.manifest.json`.
The registered command list was read from `GET /api/command`; all four names above
appear there. The deprecated `speckit.taskstoissues` was not used.

Raw session message captures: `reports/backups/2026-11-12T1550Z-command-receipts/`.

## 2. Backups taken before changes

Exact copies are preserved at
`specs/001-scanned-form-workflow/reports/backups/2026-11-12T1520Z-pre-regeneration/`:

- `tasks.md` — the complete pre-change task file (46,923 bytes).
- `issue-mapping.json` — 147 issue entries `T001`→#1 … `T147`→#147 with state and title.
- `issues-api-snapshot.json` — raw issue snapshot.
- `analyze-report.md` — the initial registered analyze report.
- `spec.md` — reconstructed pre-correction spec copy used for the exact diff.
- `sha256-before.txt` — hashes of `tasks.md`, `spec.md`, `plan.md`, constitution.

## 3. File changes and hashes

| File | Before SHA-256 | After SHA-256 | Change |
| --- | --- | --- | --- |
| `spec.md` | `af5a31db…` | `8949d7ea…` | 7 surgical wording corrections (FR-045, FR-055, FR-062, FR-082, FR-085, FR-097, SC-014) |
| `plan.md` | `eae33532…` | `0069d5b7…` | Provenance note, `speckit.tasks` references, gate-5 row, next-stage gate order |
| `tasks.md` | `0f0c0a7b…` | `6f20f7bc…` | Corrective regeneration; 147 IDs preserved; corrections C1/C2/G1–G3/A1/A2/I2–I4/I7/M2–M3/U4/U5/U7/U8 (M1 partial: four plan-only traces remain) |
| `.specify/memory/constitution.md` | `e487197f…` | `e487197f…` | **Unchanged** (byte-identical) |
| `contracts/error-catalog.de.md` | not snapshotted | `42e3c4b8…` | `IMP-007` now 80 MiB / 83.886.080 Bytes; `FLD-001` now blocks export; §4 provisional OD-1 note |
| `contracts/export-plan.md` | not snapshotted | `cb547914…` | §3.4 explicitly provisional pending OD-1; empty fields remain non-blocking |
| `research.md` | not snapshotted | `f6b421c8…` | Remaining `80 MB` cap wording corrected to `80 MiB` |
| `quickstart.md` | not snapshotted | `201f4ac5…` | `tool/gate.sh` → `tools/gate.sh` in both occurrences |

New reports created:

- `reports/2026-11-12-plan-correction-receipt.md` (created by the registered plan command).
- `reports/2026-11-12-analysis.md` — archived final registered analyze output plus a clearly marked archival note that closes N3 (SHA-256 `584cfcce…`).
- `reports/2026-11-12-task-issue-mapping.md` / `.json` — reconciliation (SHA-256 `c8fadb89…` / `ea8b1935…`).
- `reports/backups/2026-11-12T1520Z-pre-regeneration/` and `reports/backups/2026-11-12T1550Z-command-receipts/`.

No other pre-existing repository file was changed. `spec.md`, `plan.md`, `tasks.md`, `quickstart.md`, and
constitution SHA-256 values after the work are in
`reports/backups/2026-11-12T1550Z-command-receipts/sha256-after.txt`.

## 4. Exact spec diff

The exact diff is saved at
`reports/backups/2026-11-12T1550Z-command-receipts/spec-diff.patch` (75 lines).
It contains only these changes:

1. **FR-045** — autosave is a 2-second debounce, never longer than 2 seconds (aligns SC-020 and clarification 2).
2. **FR-055** — defines "reviewed" using the existing data-model states.
3. **FR-062** — empty fields never block export; unresolved overlapping suggestions stay under the provisional export preflight policy; OD-1 remains unresolved.
4. **FR-082** — adds the planned app-private export-preview exception with lifetime and sweep.
5. **FR-085** — scoped to the summary surface in addition to FR-028 (removes duplication).
6. **FR-097** — entries show title, last-edited date, and status (matches clarification 3).
7. **SC-014** — applies to translatable strings with the mandated `SIMULATED` token allowlisted.

The five settled clarifications are byte-identical. The constitution is byte-identical.

## 5. Tasks regeneration result

`spec.md`-independent checks against the pre-change backup:

- 147 task lines, exactly `T001`–`T147`, unique and in the same order.
- Phase membership is byte-for-byte equal to the backup in all 12 phases:
  Setup 12, Foundational 24, US1 13, US2 14, US3 12, US4 12, US5 14, US7 12,
  US6 8, US8 6, US9 5, Polish 15.
- No task added, removed, merged, renumbered, or reordered.
- 24 `[P]` markers preserved.
- `tasks.md` now records registered-command provenance, the manifest hash,
  gate-5-before-implementation order, gates 7–9 handoff, and the corrective receipt.

Key corrections:

| Finding | Resolution in `tasks.md` |
| --- | --- |
| C1 gate order (CRITICAL) | Gate 5 documented as pre-implementation; `T144` is record-only and cannot substitute for it |
| C2 gates 7–9 | `T147` hands the exact revision to gates 7/8/9 and does not self-approve |
| G1 SC-016/SC-018 | `T137` defines and, after OD-2, executes both runs; still blocked |
| G2 SC-019 | `T048` covers move/delete → reopen/render/export |
| G3 FR-059 | `T117` implements the use-template flow with empty values and pinned version |
| A1 OD-1 | `T113` cites the provisional §3.4/FR-062; OD-1 not settled |
| A2 OD-4 | `T097` stays blocked; no numeric bound invented |
| I2 | `T095` includes status |
| I3/I4 | `T045`/`T084` verify the corrected catalog; `T029` consumes it |
| U4 | `tools/gate.sh` used |
| U5 | Single evidence root under `specs/.../reports/` |
| I7/M2 | Traceability matrix and T108/FR-072 mapping corrected |
| M1 | **Partial**: T001/T003/T011/T031 still cite only plan sections; optional, non-blocking |
| M3 | `T093` asserts no app password / no mandatory biometric |
| U8 | `T109` asserts provenance across save/reopen/export with no controls in the artifact |
| U7 | Corrected catalog before `T029`; no ARB drift |

Task diff: `reports/backups/2026-11-12T1550Z-command-receipts/tasks-diff.patch`.

## 6. Issue reconciliation

Source: live `gh issue list -R xxammaxx/Feldexa_2.0 --state all --limit 200 --json number,title,state`.

- Issues: 147, numbers #1–#147, unique, **all OPEN**.
- Tasks: 147, IDs T001–T147, unique.
- Mapping remains **T001→#1 … T147→#147 by task ID**.
- Duplicate issues created: **0**.
- Issues closed, reopened, edited, or commented: **0**.
- Exact existing-title-to-current-description matches: **119**.
- Stale titles because descriptions were expanded: **28** (`T002, T004, T007, T015–T018, T024, T027, T029, T030, T045, T048, T060, T084, T093, T095, T097, T109, T113, T117, T137, T140, T142, T144–T147`).
- The stale titles do not break the mapping; the authoritative key is the task ID, and no issue was published or altered.

Full record: `reports/2026-11-12-task-issue-mapping.md` and `.json`.

## 7. Final analyze result

The final registered `speckit.analyze` run (session `ses_e2fc35545ffe4PyYh4ExvE7L85`)
reported:

- **0 CRITICAL** findings.
- **1 HIGH-class owner decision**: OD-1 export conflict gating.
- **4 MEDIUM**: G1/OD-2 (SC-016/SC-018 blocked), OD-3 device equivalence, A2/OD-4 50-item bound, U3 pre-filled-content documentation gap.
- **LOW**: D2 duplication, M1 residual trace notes for T001/T003/T011/T031, M4 Draft status, and U4-residual stale issue titles #4/#145 (consequence of the no-issue-edit rule).
- **0 constitution conflicts**.
- **FR coverage 110/110; SC mapped 22/22; substantively verifiable now 20/22 (SC-016/SC-018 deferred to OD-2).**
- **Gate 5 passes**; implementation may proceed only with the unresolved owner decisions recorded and non-settling tasks kept non-settling.

The full report is archived at `reports/2026-11-12-analysis.md`.

## 8. Unresolved findings / owner decisions (not settled here)

1. **OD-1** — export conflict gating: block until overlapping suggestions are resolved vs warn and exclude. `contracts/export-plan.md` §3.4 is explicitly provisional; `T113` must not settle it.
2. **OD-2** — recruitment, prior familiarity, observation protocol, and timing boundaries for SC-016 and SC-018. `T137` stays blocked until decided.
3. **OD-3** — written equivalence rule and owner approval for any device other than the Samsung Galaxy A54 5G. `T141` records it.
4. **OD-4** — numeric interaction/latency bound for the FR-100 50-item list. `T097` records measurements as unratified.
5. **U3 documentation gap** — overlaying a value on pre-filled scanned content has no FR, acceptance criterion, task, or test. It requires a future specification change, not an invented task.
6. **D2 / M1 / M4 / U4-residual** — low-severity duplication, four plan-only trace references, the deliberately retained `Draft` status, and two stale issue titles (#4/#145) that still carry the old `tool/gate.sh` spelling because no issue was edited; none blocks implementation.

## 9. Constraints honored

- No `git add`, commit, push, merge, tag, or release was performed.
- No GitHub issue was created, edited, closed, reopened, or commented on.
- No constitution text and no settled clarification was changed.
- No new task ID was invented; the existing issue mapping remains 1:1.
- Only the registered command endpoint was used for spec/plan/tasks/analyze changes.
