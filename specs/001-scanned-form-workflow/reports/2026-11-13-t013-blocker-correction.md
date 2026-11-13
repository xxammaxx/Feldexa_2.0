# 2026-11-13 NONE — T013 Blocker Correction and Issue-Mapping Reconciliation

| Field | Value |
| --- | --- |
| Evidence class | `NONE` (process/documentation correction; no runtime claim) |
| Result | `PASS` (gate-5 analysis after correction; no CRITICAL/HIGH remains) |
| Task / issue | `T013` (primary), `T014`, `T022`; issues `#13`, `#14`, `#22` (mapping only; no issue writes) |
| Date / timezone | 2026-11-13, Europe/Berlin |
| Revision | base `b3dbe29932c8a5bed13696406b6a2bcc80316ffa`; this report is one of the seven files in the local review candidate. Candidate commit/bundle SHAs are recorded in the external receipt `/tmp/opencode/t013-candidate-receipt.md`, not in this file (self-reference would change the candidate). |
| External attestation | `/tmp/opencode/t013-candidate-receipt.md` records the exact candidate commit, bundle path, and hashes; no push, merge, or release |

## 1. Scope

Investigate and correct the concrete T013 implementation blocker against the current `spec.md`, constitution v1.0.0, `plan.md`, `contracts/`, `data-model.md`, and `tasks.md`:

1. forward dependency inversion for canonical model types;
2. T013/T014 capability-descriptor, evidence, error, and DTO ownership;
3. unowned and undefined DTOs/canonical types;
4. the `ExportArtifact` core-versus-export package contradiction.

Owner-settled scope, the five clarifications, OD-1–OD-4, and every task identifier are preserved; issue mapping is addressed separately in §6. No specification was re-run through `speckit.specify` or `speckit.clarify`; no production code or issue write was made. The review candidate is a separate local commit/bundle; it was not pushed or merged.

## 2. Command receipts

All commands were dispatched through the installed OpenCode HTTP API against the repository root. Session identities are process identifiers for provenance only; they are not runtime evidence.

| # | Registered command | Session ID | Created (UTC) | Ended (UTC) | Outcome | Purpose |
| ---: | --- | --- | --- | --- | --- | --- |
| 1 | `speckit.analyze` | `ses_e2d99e6faffe1zDbzBKa1hRaUi` | 2026-11-13T00:54:28Z | 2026-11-13T00:58:25Z | `succeeded` | Read-only baseline analysis; found F1 (CRITICAL), F2/F3/F4/X2 (HIGH), X1/X3–X9 |
| 2 | `speckit.plan` | `ses_e2d95263affe8iKrmFBqpban3N` | 2026-11-13T00:59:40Z | 2026-11-13T01:02:02Z | `succeeded` | Correct `plan.md`, `data-model.md`, `contracts/ports.md`, `contracts/export-plan.md` |
| 3 | `speckit.tasks` | `ses_e2d928182fferYgcpbk1No6CLn` | 2026-11-13T01:02:33Z | 2026-11-13T01:06:06Z | `succeeded` | Correct `tasks.md` in place; preserve all 147 IDs/order/phases |
| 4 | `speckit.analyze` | `ses_e2d8e5e8fffei4aGMo840G3zby` | 2026-11-13T01:07:04Z | 2026-11-13T01:11:53Z | `succeeded` | Post-correction gate-5 verification: F1–F4/X1–X9 PASS; residual N1–N5 |
| 5 | `speckit.analyze` | `ses_e2d88a353fferPkUEGMTBGHUoQ` | 2026-11-13T01:13:20Z | 2026-11-13T01:15:29Z | `succeeded` | Residual N1–N5 closeout; found R1/L1, which were then corrected and structurally re-checked |

Command-source hashes (from `.specify/integrations/opencode.manifest.json` and `.opencode/commands/`):

```text
91fe16257ededdea9cc21d3cb27d539fcdd12d93ddcea52332cd4b68176b6a8d  .opencode/commands/speckit.analyze.md
3be8b011db9c6bb1cc77037f7d90756a6dbcbda1995cda2192818385732b27ff  .opencode/commands/speckit.plan.md
6754ae39649c8e73a5ed376ad5cfcf04422e321a10e07c5ccd92fd1b9bccf776  .opencode/commands/speckit.tasks.md
```

`.specify/extensions.yml` registers no hooks (`hooks: {}`), so no pre/post hooks were dispatched.

## 3. Findings and corrections

| ID | Severity before | Defect | Correction | Status |
| --- | --- | --- | --- | --- |
| **F1** | CRITICAL | T013 referenced canonical types created by later tasks (T015–T022) and by no task; the ports package lacked core/export dependencies and a barrel. | Phase 2 now has a normative execution order `T014 → T015/T016 → T018 → T017 → T020 → T021` (T019 after T018; T022 after T015/T016) `→ T013 → T023…`. T013 explicitly requires T014 and T015–T022, names its files and workspace dependencies, and the dependency/parallel notes were corrected. | **RESOLVED** |
| **F2** | HIGH | T013 “every capability interface” and T014 “evidence classes” both plausibly owned `CapabilityDescriptor`/`PlatformCapability`; `ImportRejectionKind` was circular. | File-level split: T014 owns `EvidenceClass`, `CapabilityEvidence`, `FeldexaException` + typed exceptions, and `ImportRejectionKind`; T013 owns `CapabilityKind`, `CapabilityDescriptor`, `PlatformCapability`, `AdapterRegistry`, 10 port interfaces, and all remaining DTOs/enums. T014 precedes T013. | **RESOLVED** |
| **F3/X2** | HIGH | 30 canonical/port types had no task owner; 11 port declarations were referenced but undefined. | Added the normative ownership table in `tasks.md`, type/package notes in `data-model.md`, and `contracts/ports.md` §2.10 with `OcrLine`, `LoadedTemplate`, `CreateDocumentRequest`, `SaveRevisionRequest`, `CreateTemplateRequest`, `SaveTemplateVersionRequest`, `WriteSignatureRequest`, `DeleteConfirmation`, `ExportOptions`, and `RasterFormat`; `PageDimensions` was replaced by core `PageGeometry`. Existing task scopes were extended (no new IDs). | **RESOLVED** |
| **F4** | HIGH | `ExportArtifact` was in `feldexa_core` in T022 but in `feldexa_export` in `contracts/ports.md` and the plan. | `feldexa_export` is authoritative: T022 now defines `ExportPlan`, `ExportValidation`, `ExportArtifact`, and `ArtifactVerification` in `packages/feldexa_export/lib/src/model/` and adds the core dependency. `plan.md`, `data-model.md`, `contracts/ports.md`, and `contracts/export-plan.md` agree; no core copy remains. `ExportPlan.evidenceClass` is a string token, so export never imports ports. | **RESOLVED** |
| X1 | MEDIUM | `PageFailure` was double-defined in core and ports. | Single core definition owned by T017 (`page_failure.dart`, `data-model.md` §3.3); ports keeps only the signature reference. | **RESOLVED** |
| X3 | MEDIUM | “The error taxonomy” omitted catalog families and conflated `SAVE-003` causes. | `contracts/ports.md` §3 now adds `StorageWriteException` (`SAVE-003`), the `PLT-002` `SecurityException` mapping, and an explicit statement that catalog-only codes are not separate exception classes; T014 cites the catalog and storage contract. | **RESOLVED** |
| X4 | MEDIUM | `code`/`messageKey`/`message` had three incompatible meanings. | `code` = catalog code, `messageKey` = ARB key, `message` = stable machine key; German text only via l10n. | **RESOLVED** |
| X5 | MEDIUM | Plan said “interfaces only” while the ports package must hold DTOs. | `plan.md` now says “interfaces and their contract DTOs/enums only” and records the one-way dependency direction. | **RESOLVED** |
| X6 | MEDIUM | `PageDimensions` duplicated and was undefined. | `PageRasterPort.pageDimensions` returns core `PageGeometry`; `PageDimensions` is gone. | **RESOLVED** |
| X7 | LOW/MEDIUM | `StoredMeta`, `DocumentMeta`, and `DocumentSummary` overlapped. | Distinct roles: `DocumentMeta`/`TemplateMeta` persisted envelopes (T017/T021), `StoredMeta` port list projection, `DocumentSummary` T095 UI projection with derived counts. Derivation is now stated. | **RESOLVED** |
| X8 | LOW | Format-validation text claimed every line was `- [ ]`. | Now states `- [x]`/`- [ ]` plus `T###`; T001–T012 checked, T008 remains `[X]`. | **RESOLVED** |
| X9 | LOW | T027/T028 prerequisite note omitted T014/T026. | Dependency and parallel notes now include T014 and T026. | **RESOLVED** |
| N1 | MEDIUM | Completed T011 toolkit already has a second `EvidenceClass`. | T014 now owns reconciliation: make the ports type canonical and have `feldexa_testkit` consume it (or rename the toolkit type) without changing T011's ID. | **RESOLVED (task-level)** |
| N2 | MEDIUM | `Document`/`Template` created a `T017`↔`T021` `TemplateOrigin` cycle; T017–T022 were called file-disjoint. | `TemplateOrigin` is now owned by T017 (`template_origin.dart`) as the document-side reference; T021 owns only the template aggregate types. The Phase 2 order is acyclic and the parallel note is qualified. | **RESOLVED** |
| R1 | MEDIUM | `Document.lastDurable` (T017) needs `DurablePointer` (T020), while `RevisionContent` (T020) needs `Page`/`TemplateOrigin` (T017): a weaker `T017`↔`T020` cycle. | `DurablePointer` is now owned by T017 (`durable_pointer.dart`); T020 owns `DurabilityStatus`, `Revision`, `RevisionKind`, and `RevisionContent` and does not redeclare the pointer. | **RESOLVED** |
| L1 | LOW | Parallel note omitted T020 from T021's prerequisites. | Parallel note now says T021 follows T017/T018/T020. | **RESOLVED** |
| N3 | LOW | The correction receipt cited a missing report. | This report is that receipt; the citation now resolves. | **RESOLVED** |
| N4 | LOW | Canonical-type lists omitted `Page`, `SourceFileRef`, `ConfirmedField`, `RevisionKind`. | Listed in `contracts/ports.md` §1/§2.10 and the ownership table. | **RESOLVED** |
| N5 | LOW | `StorageException` wording, `ExportBlockedException` payload, `FakeRegistry`, and T017 file list were inconsistent. | `StorageFullException`/`StorageWriteException` named; `ExportBlockedException(List<String> fieldIds)`; `FakeRegistry` assigned to T036; `page_failure.dart` added to T017. | **RESOLVED** |

## 4. Files changed

| File | Change |
| --- | --- |
| `specs/001-scanned-form-workflow/contracts/ports.md` | Dependency direction and type ownership; `PageFailure` core-only; `PageGeometry` dimensions; §2.10 DTO declarations; error-field semantics and §3 exceptions; list-read-model derivation; `AdapterRegistry` ownership |
| `specs/001-scanned-form-workflow/contracts/export-plan.md` | `feldexa_export` contract-model ownership; `evidenceClass` string token avoids a ports dependency |
| `specs/001-scanned-form-workflow/data-model.md` | Owners/definitions for `SourceFileRef`, `PageFailure`, `DocumentMeta`, `RevisionContent`/`RevisionKind`, `TemplateMeta`/`TemplateVersionContent`/`StoredTemplate`, `ArtifactVerification`, `DocumentSummary`, `FieldSuggestionSet`, and `TemplateOrigin` |
| `specs/001-scanned-form-workflow/plan.md` | `feldexa_export` responsibility and one-way package dependency direction |
| `specs/001-scanned-form-workflow/tasks.md` | Foundational Type Ownership table; normative Phase 2 order; scoped T013/T014/T015–T022/T036/T057/T095/T102/T103; CR-7–CR-10; corrected format validation; correction receipt |
| `specs/001-scanned-form-workflow/reports/README.md` | Index entry for this report |

Unchanged and verified from the candidate itself: `spec.md`, the five clarifications, OD-1–OD-4, `.specify/memory/constitution.md` (`e487197f…ddaa813`), and every source/package file. This is established by `git diff --name-status b3dbe29..HEAD`, which lists only the seven report/task/contract artifacts; no spec, constitution, or source path appears.

Before/after hashes. The "Before" side is reproducible with `git show b3dbe29:<path> | sha256sum`; the "After" side with `sha256sum <path>` in the candidate checkout.

| File | Before (base blob) | After (candidate) |
| --- | --- | --- |
| `tasks.md` | `26619c5d…c866a` | `a0aca6f0…967d` |
| `plan.md` | `0069d5b7…20d0` | `1f8fd4e6…b246` |
| `data-model.md` | `46d65f55…f612` | `599d5a2a…52043` |
| `contracts/ports.md` | `1746048a…a211` | `ef48c620…9b2` |
| `contracts/export-plan.md` | `cb547914…322e` | `06182bc2…211e` |

Verification commands that require no backup directory:

```sh
git diff --stat b3dbe29..HEAD
git diff --name-status b3dbe29..HEAD
git show --stat HEAD
git show b3dbe29:specs/001-scanned-form-workflow/tasks.md | sha256sum
sha256sum specs/001-scanned-form-workflow/tasks.md
```

Expected result: exactly seven paths and no other path. Exact insertion/deletion counts are recorded in the external receipt after the final candidate commit; they are not embedded here to avoid a self-referential report. Any authoring-time backup or patch material is intentionally **not** part of this candidate; it is not required for verification and is unavailable from the bundle. This report relies only on the base/candidate Git objects and does not cite unbundled material as evidence.

## 5. Structural verification

| Check | Result | Evidence |
| --- | --- | --- |
| Task lines | **PASS** | Exactly 147 lines matching `^- \[[ xX]\] T[0-9]{3} ` |
| IDs | **PASS** | `T001`–`T147`, unique, strictly sequential, no gaps/duplicates |
| Order and phase membership | **PASS** | Task-ID extraction from the candidate and `git diff b3dbe29..HEAD -- tasks.md`; no backup directory is used |
| Phase counts | **PASS** | 12/24/13/14/12/12/14/12/8/6/5/15 = 147 |
| `[P]` markers | **PASS** | 24, unchanged |
| Checkboxes | **PASS** | T001–T012 checked (T008 `[X]`), T013–T147 unchecked; sequence preserved |
| Changed task lines | **PASS** | 14 descriptions extended: T013, T014, T015, T016, T017, T018, T020, T021, T022, T036, T057, T095, T102, T103; no ID/order/phase change |
| Story labels | **PASS** | US1–US9 carried by their phases; Setup/Foundational/Polish unlabelled |
| Clarifications | **PASS** | Five intact in `spec.md` §Clarifications |
| Owner decisions | **PASS** | OD-1–OD-4 intact and unanswered |
| Constitution | **PASS** | v1.0.0 unchanged; no amendment requested or implied |

## 6. Issue-mapping reconciliation

**Bundle limitation.** A git bundle cannot establish live GitHub issue state. From the bundle, only the task-ID keys and mapping text in `tasks.md` are verifiable; issue states are external and are unavailable from the bundle.

**Externally scoped issue state.** Live GitHub issue state was not independently established from the candidate. A read-only external check was made on 2026-11-13T01:20Z with `gh issue list -R xxammaxx/Feldexa_2.0 --state all --limit 300 --json number,title,state`, but its result is not part of this candidate and is not asserted here; from the bundle, live issue state is **unavailable**. The candidate verifies only that `tasks.md` contains `T001`–`T147` and the documented task-ID mapping text.

- The candidate preserves every task identifier `T001`–`T147`; this is verifiable from `tasks.md`.
- The task-to-issue mapping is external to the candidate and is not bundle-verifiable.
- Issue titles may be older than corrected task descriptions; the authoritative key is the task ID.
- No issue was created, edited, closed, reopened, or commented on.
- Treat every live issue state as **unavailable from the bundle**, not as a claim made by this report.

## 7. Remaining blockers and open decisions

No CRITICAL or HIGH blocker remains for T013. T013 is unblocked by the corrected ownership and ordering.

Still open by owner scope (not settled here):

1. **OD-1** — export handling of unresolved overlapping suggestions (`contracts/export-plan.md` §3.4 remains provisional; T113).
2. **OD-2** — SC-016/SC-018 recruitment, protocol, and timing boundaries (T137).
3. **OD-3** — device-equivalence rule for anything other than the Samsung Galaxy A54 5G (T141).
4. **OD-4** — numeric interaction/latency bound for the FR-100 50-item list (T097).
5. **U3 documentation gap** — overlaying a value on pre-filled scanned content has no FR/acceptance criterion; it requires a future specification change, not an invented task.
6. **N1 implementation follow-up** — T014 must reconcile the already-implemented `feldexa_testkit` `EvidenceClass`; this is a task-level ownership instruction, not a production-code change made here.

`spec.md` remains **Draft**.

## 8. Constraints honored

- No `speckit.specify` or `speckit.clarify` was run.
- No production code was written.
- No issue was created or edited; the correction workflow itself did not commit, branch, merge, tag, or publish. The separate review candidate is a local commit/branch and bundle; it was not pushed or merged.
- No task ID was invented, removed, merged, renumbered, or reordered.
- No constitution text and no settled clarification was changed.
- The checkpoint is documentation/task-order repair only; implementation and independent review remain separate gates.

## 9. Final registered analysis

Residual closeout run: `speckit.analyze`, session `ses_e2d88a353fferPkUEGMTBGHUoQ`, created 2026-11-13T01:13:20Z, ended 2026-11-13T01:15:29Z, outcome `succeeded`, strictly read-only.

- **N1–N5: 5/5 PASS.** The testkit `EvidenceClass` duplicate is now a T014 migration item; `TemplateOrigin` is T017-owned; this report exists and resolves the citation; canonical-type lists are complete; error/test-seam/file consistency is fixed.
- **R1/L1:** the closeout found one weaker MEDIUM ordering cycle (`Document.lastDurable`/`DurablePointer`) and one LOW parallel-note omission. Both were corrected immediately by moving `DurablePointer` to T017 and adding T020 to T021's prerequisites; the final structural check remains 147 tasks, same order, same phase counts, 24 `[P]`, and unchanged checkboxes.
- **No CRITICAL/HIGH blocker for T013.** The prior post-correction run returned **PASS** on F1–F4 and X1–X9; the residual run returned **PASS — T013 is unblocked.**

Final verdict: **PASS for the T013 blocker**. Implementation may proceed only through the normal gate order, with OD-1–OD-4 and the U3 documentation gap still recorded as open. No push, merge, or publication was performed; the local review candidate is recorded in the external receipt.
