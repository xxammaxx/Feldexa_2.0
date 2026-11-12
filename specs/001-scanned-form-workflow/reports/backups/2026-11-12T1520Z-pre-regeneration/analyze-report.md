I'll start by loading the analysis skill and checking for extension hooks.

No `.specify/extensions.yml` (only an `.specify/extensions` directory). Let me check contexts and run prerequisites.

Prerequisites pass. Loading artifacts (spec, plan, tasks, constitution).

Now let me verify structural claims and cross-references in the supporting artifacts.

## Specification Analysis Report

**Feature**: `specs/001-scanned-form-workflow` · **Artifacts analyzed**: `spec.md` (861 lines, 110 FR, 22 SC, 9 user stories), `plan.md` (248 lines), `tasks.md` (485 lines, 147 tasks), plus `.specify/memory/constitution.md` v1.0.0 and the referenced contracts/data model.  
**Mode**: read-only — no files were modified. Prerequisites script resolved the feature directory successfully.

### Findings

| ID | Category | Severity | Location(s) | Summary | Recommendation |
|----|----------|----------|-------------|---------|----------------|
| C1 | Constitution | **CRITICAL** | tasks.md:L361, L472; constitution.md:L364-383 | The consistency-analysis pass is scheduled as T144 "after implementation and evidence exist". The constitution requires gate 5 (consistency analysis) to pass **before** gate 6 (implementation). This inverts a mandatory gate order. | Correct the T144 note and scope: the pre-implementation analysis is this run; T144 should only *record* it, with a separate post-implementation convergence check (gate 9). |
| I1 | Inconsistency | **HIGH** | spec.md:L497-498 (FR-025); contracts/export-plan.md:L195-203; tasks.md:L38 | FR-025 requires the user to resolve overlapping suggestions; the export contract excludes unresolved suggestions non-blockingly. Both cannot be final policy (OD-1). | Owner must choose block-vs-warn. Until then, mark the contract as provisional and keep T113 explicitly non-settling (already done). |
| G1 | Coverage | **HIGH** | tasks.md:L90, L354; spec.md:L775-780 | SC-016 (≤10 min median) and SC-018 (5/5 first-time users) have no executing task. T137 only records a protocol and is blocked on OD-2; the matrix presents it as the verification task. | Add execution tasks for the journey-timing and 5/5 usability runs after OD-2, or explicitly mark both SCs as deferred acceptance gates. |
| G2 | Coverage | **HIGH** | tasks.md:L168 (T048); spec.md:L781-782, L661-663 | SC-019 / FR-095 require a document to open, render, and export after the picked source file is moved/deleted. T048 tests only byte identity and modification time — a different property. | Add a test that imports, saves, deletes the picked file, then reopens, renders, and exports; keep T048 for source immutability. |
| G3 | Coverage | **HIGH** | spec.md:L570 (FR-059); tasks.md:L303, L306 | "Using a template creates a new independent document with empty values" has a test (T120) but no implementation task. T117 covers versions/pinning only; no task implements the "new document from template" flow. | Add a US6 implementation task for the start-template flow (empty values, copied source, pinned version). |
| A1 | Ambiguity | **HIGH** | spec.md:L578-579 (FR-062) vs L832-834 | FR-062 says export is possible "once its fields are confirmed and filled", while the assumptions say empty fields never block export. The normative precondition is unclear. | Reword FR-062 to "regardless of empty fields; unfinished suggestions are excluded and warned" and align with `export-plan` §3.4. |
| A2 | Ambiguity | **HIGH** | spec.md:L674-675 (FR-100); tasks.md:L41, L261 | "The list MUST remain usable" with ≥50 items has no measurable bound; OD-4 leaves the numeric criterion undefined. Acceptance is untestable until T097 defines a bound. | Record a concrete bound (e.g., reach any item within N interactions/seconds) as an owner-approved threshold before implementation. |
| I2 | Inconsistency | **HIGH** | spec.md:L669-670 (FR-097) vs L229-231 (US5-9), L17 (Clarification 3) | The list must show "title, last-edited date, and status" in the story and settled clarification, but FR-097 requires only title and date; T095 implements FR-097. Status could silently disappear. | Add "status" to FR-097 and T095, or explicitly drop it via a new clarification. |
| I3 | Inconsistency | MEDIUM | contracts/error-catalog.de.md:L120 (FLD-001); spec.md:L590-591 (FR-068); tasks.md:L237 | FLD-001 still tells the user text "can be clipped during export", while FR-068/EXP-001 block export on clipping. Contradiction is acknowledged and deferred to T084. | Apply the wording fix before implementation; do not ship the current string. |
| I4 | Inconsistency | MEDIUM | contracts/error-catalog.de.md:L27 (IMP-007); tasks.md:L51 (CR-3) | The condition says 80 MiB but the German message says "80 MB". CR-3 claims "the catalog and test use MiB consistently", which is not true. | Align the catalog message and test to 80 MiB (83,886,080 bytes); correct the CR-3 statement. |
| I5 | Inconsistency | MEDIUM | spec.md:L769-770 (SC-014) vs L641 (FR-087); tasks.md:L50 | SC-014 demands 100 % German strings; FR-087 requires the untranslated `SIMULATED` token. The allowlist resolution exists only in `tasks.md`/checklist, not in the spec. | Amend SC-014 to exclude the mandated evidence token, so the spec itself records the resolution. |
| I6 | Inconsistency | MEDIUM | spec.md:L539-540 (FR-045) vs L783-784 (SC-020) | "Approximately 2 seconds" versus a strict "final 2 seconds" loss bound. CR-1 resolves it in tasks (debounce never exceeds 2 s) but the spec still says "approximately". | Change FR-045 to "2 s debounce, never longer than 2 s" (commit budget remains separate). |
| U1 | Underspecification | MEDIUM | spec.md:L563-564 (FR-055); tasks.md:L301 | "A document whose field structure has been reviewed" is never defined. `data-model` §3.8 has verification states, but no rule says when the template action becomes available. | Define the enablement predicate (e.g., no `unreviewed` fields) in the plan/contract and reference it from FR-055/T115. |
| U2 | Underspecification | MEDIUM | spec.md:L501-502 (FR-027); tasks.md:L209 | "Revise or restore previous corrections for a field or document" has no depth, persistence, or reopen semantics; T067 invents bounded history with 500 ms coalescing. | Specify the undo/restore scope (per-session vs persisted, depth, document-level restore) in the data model/contract. |
| U3 | Underspecification | MEDIUM | spec.md:L399-401 | The edge case requires overlaying values on pre-filled scanned content, but there is no FR and no task/test for this behavior. | Add an FR or explicit acceptance step and a test for overlaying a value over printed content. |
| U4 | Inconsistency | MEDIUM | tasks.md:L104, L362 (`tool/gate.sh`) vs plan.md:L48, L160 (`tools/`) | Gate script path is singular `tool/`, but the monorepo root is `tools/`; the plan never defines this path. | Choose one location (likely `tools/gate.sh`) and update T004/T145 and the plan structure. |
| U7 | Inconsistency | MEDIUM | tasks.md:L103 (T029) vs L165 (T045), L237 (T084) | T029 generates ARB keys from the error catalog in Foundational, then T045 and T084 change catalog wording later. ARB strings are guaranteed to drift, with no task to regenerate them. | Move the FLD-001/IMP-007 alignments before T029, or require T045/T084 to update `app_de.arb` and rerun the string tests. |
| C2 | Constitution | MEDIUM | tasks.md:L364, L464; constitution.md:L384-389 | No task covers gates 7–9 (independent review at the exact commit, integration, post-merge verification, convergence), although T147 cites Principle X/Definition of Done. "Separate gates" is asserted but no owner/handoff is defined. | Add an explicit handoff/review/convergence task or state which external workflow owns gates 7–9 before T147. |
| U8 | Constitution | MEDIUM | constitution.md:L130-134; tasks.md:L189 (T058), L284 (T109) | Principle IV requires provenance to survive "saving, reopening, and export". Save/reopen is covered; export retention is neither defined for a flattened artifact nor verified, and FR-069 forbids interactive controls. | Clarify that provenance survives in the working model across export (FR-073), and add an assertion to T109. |
| U5 | Inconsistency | LOW | tasks.md:L191 (T060), L353 (T136), L360-364 | Evidence reports are split between `tools/evaluation/reports/` and `specs/.../reports/` with no single index. | Standardize on one evidence root (T010 already creates `specs/.../reports/`) and link from the other. |
| U6 | Ambiguity | LOW | plan.md:L60; spec.md:L625-627 (FR-082) | FR-082 forbids plaintext in "caches"; the plan deliberately keeps the export preview in app-private cache. The checklist resolves this, but the spec wording does not. | State in FR-082 that the user-requested ephemeral export preview is the permitted exception with a defined lifetime. |
| I7 | Inconsistency | LOW | tasks.md:L64, L72 | The requirement matrix omits actual coverage: FR-049/FR-050 are implemented by T025 (not T088–T096); FR-058 is T095; FR-061 is T115. | Correct the matrix rows so traceability is auditable. |
| D1 | Duplication | LOW | spec.md:L476-477 (FR-015), L503-504 (FR-028), L633-634 (FR-085) | Three requirements all demand distinguishing unconfirmed suggestions from confirmed fields; FR-085 adds only the summary surface. | Merge FR-085 into FR-028 or make FR-085 explicitly the "summary surface" clause. |
| D2 | Duplication | LOW | spec.md:L450-451 (FR-004) vs L661-663 (FR-095/096); L448-449 vs L580-581 | Source immutability and page fidelity are each stated twice with slightly different scope. | Keep FR-004/FR-003 as the invariants and make FR-096/FR-063 explicit references to them. |
| M1 | Traceability | LOW | tasks.md:L357-364, L120-145 | T140, T145–T147 and several foundational tasks (T002, T007, T015–T018, T024, T027, T030) cite only constitution/contracts/data-model, not FR/SC. | Add a one-line trace rationale per task (Principle I) or map to the enabling FR cluster. |
| M2 | Traceability | LOW | tasks.md:L84, L92, L283 | T108 (failed export) is mapped to SC-010 (storage-failure trials); its direct criterion is FR-072. | Re-map T108 to FR-072; keep SC-010 on T094 and the export-under-storage-pressure path. |
| M3 | Coverage | LOW | spec.md:L550-551 (FR-050); tasks.md:L134 | "No app password, no mandatory biometric" is implemented (T025) but no test asserts it. | Add a small assertion to the save/reopen integration test. |
| M4 | Quality | LOW | spec.md:L7 | Spec status remains "Draft" while plan/tasks claim completed gates and a ratified feature. | Set an explicit status (e.g., "Ready for implementation") once HIGH findings are closed. |

### Coverage Summary

All 110 FR and 22 SC identifiers are mentioned in `tasks.md`; the table below groups them and flags substantive gaps.

| Requirement Key | Has Task? | Task IDs | Notes |
|---|---|---|---|
| FR-001–FR-010 (import/integrity) | Yes | T037–T049 | SC-019 verification incomplete (G2) |
| FR-011–FR-020 (detection) | Yes | T050–T063 | Strong; frozen dry run unscored (CR-5 honored) |
| FR-021–FR-030 (review/correction) | Yes | T064–T075 | FR-025 export policy unresolved (I1) |
| FR-031–FR-042 (filling) | Yes | T076–T087 | Date/number/checkbox coverage solid |
| FR-043–FR-053 (saving/recovery) | Yes | T088–T096, T025 | FR-049/050 covered by T025, omitted from matrix (I7) |
| FR-054–FR-061 (templates) | Yes | T114–T121 | FR-059 has test-only coverage (G3) |
| FR-062–FR-073 (export) | Yes | T102–T113 | FR-062 precondition ambiguous (A1); T108 mis-mapped (M2) |
| FR-074–FR-077 (storage exhaustion) | Yes | T094, T100 | Adequate |
| FR-078–FR-082 (privacy/offline) | Yes | T098, T099, T138 | FR-082 wording tension (U6) |
| FR-083–FR-085 (recognition honesty) | Yes | T122–T125 | Overlaps FR-028 (D1) |
| FR-086–FR-089 (browser surface) | Yes | T128–T132 | Evidence separation covered |
| FR-090–FR-094 (a11y/language) | Yes | T005, T029, T049, T131, T133, T134 | SC-014 contradiction (I5) |
| FR-095–FR-096 (source retention) | Yes | T040, T048 | Deletion-reopen test missing (G2) |
| FR-097–FR-100 (stored access) | Yes | T095–T097 | Status field missing (I2); "usable" unbounded (A2) |
| FR-101–FR-106 (template versions) | Yes | T115–T120 | FR-106 atomicity test exists (T118) |
| FR-107–FR-110 (dates) | Yes | T081 | Complete |
| SC-001–SC-003 | Yes | T035, T142 | Manual baseline executed only in T142 |
| SC-004 | Yes | T135, T136 | Device equivalence pending (OD-3) |
| SC-005–SC-006 | Yes | T109, T112, T143 | Artifact-level verification defined |
| SC-007–SC-008 | Yes | T138 | Socket/manifest audit is the right method |
| SC-009, SC-020 | Yes | T092 | Two-second bound resolved in tasks only (I6) |
| SC-010 | Yes | T094, T108 | See M2 |
| SC-011 | Yes | T046 | Exact German behavior and no-record asserted |
| SC-012, SC-013, SC-021 | Yes | T114, T120 | Template independence suite |
| SC-014 | Yes | T133 | Contradiction with FR-087 (I5) |
| SC-015 | Yes | T134 | Numeric thresholds recorded |
| SC-016, SC-018 | **Partial** | T137 (protocol only) | No execution task (G1) |
| SC-017 | Yes | T070, T109 | Zoom/rotation property tests |
| SC-019 | **Mismatch** | T048 | Tests immutability, not deletion recovery (G2) |
| SC-022 | Yes | T081 | Complete |

### Constitution Alignment Issues

- **C1 (CRITICAL)**: Gate order inversion — analysis scheduled after implementation. The constitution says each gate MUST pass before the next stage.
- **C2 (MEDIUM)**: Gates 7–9 (independent review at exact commit, integration, convergence) have no tasks or named handoff; T147 invokes the Definition of Done without them.
- **U8 (MEDIUM)**: Principle IV's "provenance survives export" is not defined or verified for a flattened artifact (FR-069 forbids form controls).
- No architecture or principle violation was found in the plan itself; the Plan's constitution table remains accurate (Flutter Web-first, Android authority, offline, encryption, corpus freeze, evidence classes all map to tasks).

### Unmapped / Weakly Mapped Tasks

- **Constitution/DoD-only**: T140, T145, T146, T147 (acceptable, but add an explicit trace note).
- **Contract/model-only**: T002, T007, T015–T018, T024, T027, T030 (prerequisites with no FR/SC reference).
- **Mis-mapped**: T108 → SC-010 instead of FR-072.

### Metrics

- **Total requirements**: 132 (110 FR + 22 SC); 9 user stories
- **Total tasks**: 147 (24 `[P]`; T001–T147 sequential, all with exact paths; phase counts match the summary)
- **FR coverage**: 110/110 mapped (100 %); 1 is test-only (FR-059)
- **SC coverage**: 22/22 mapped; **19/22 substantively verified (86 %)** — SC-016, SC-018, SC-019 deficient
- **Ambiguity count**: 4 (A1, A2, U1, U2)
- **Duplication count**: 2 (D1, D2)
- **Severity totals**: 1 CRITICAL · 7 HIGH · 11 MEDIUM · 9 LOW
- **Open owner decisions**: 4 (OD-1 export gating, OD-2 usability protocol, OD-3 device equivalence, OD-4 list bound)

### Next Actions

1. **Fix C1 before `/speckit.implement`.** This analysis satisfies gate 5; rewrite T144 as "record this report" and add a separate post-implementation convergence check. The current note "scheduled after implementation" contradicts the constitution.
2. **Close the HIGH gaps**: add an implementation task for FR-059, a deletion-reopen/export test for SC-019, execution tasks for SC-016/SC-018, and align FR-062, FR-097, and FR-100 wording.
3. **Owner decisions required**: OD-1 (export conflict gating) and OD-2 (usability protocol) block acceptance evidence; OD-3/OD-4 need recorded thresholds. Do not let T113/T097/T137 imply a settled answer.
4. **Medium clean-up**: apply FLD-001 and IMP-007 corrections (or move T045/T084 before T029 and regenerate ARB), update SC-014/FR-045 spec wording, standardize `tools/gate.sh`, and fix the traceability matrix rows.
5. **Then proceed**: `/speckit.implement` for MVP (Setup → Foundational → US1 → US2 → US3 → US4 → US5 → US7); keep US6/US8/US9 as P2. Re-run `/speckit.tasks` if spec/plan wording changes, then re-analyze.

### Remediation Offer

Would you like me to suggest concrete remediation edits for the top 8 issues (C1, I1, G1, G2, G3, A1, A2, I2)? I can draft exact wording and task-table changes for your approval — I will not modify any file.