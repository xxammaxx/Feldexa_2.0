# Assessment: Precision and Testability Checklist

**Feature**: `001-scanned-form-workflow` | **Assessed**: 2026-11-12
**Subject**: [checklists/precision-testability.md](./precision-testability.md)
**Inputs**: [spec.md](../spec.md), [plan.md](../plan.md), [data-model.md](../data-model.md), [research.md](../research.md), [quickstart.md](../quickstart.md), [contracts/](../contracts/), `.specify/memory/constitution.md` (v1.0.0, unchanged)
**Assessment class**: requirements-quality review of the checklist, not an implementation review and not independent approval of the feature.

## Method

1. Read all 36 checklist items and traced every citation to the current artifact text.
2. Applied the authority order stated by the constitution: constitution → spec → plan → contracts. A dependent artifact that contradicts a higher one is a defect in the dependent artifact.
3. Distinguished:
   - **RESOLVED** — the checklist concern is already answered by an approved artifact (the item is a false positive or a citation error).
   - **GAP** — a real precision, coverage, or traceability gap, but not a contradiction; it can be closed by a verification task or by explicitly recording an existing plan/engineering constraint.
   - **CONTRADICTION** — two approved statements cannot both be true as written; the governing resolution is named.
   - **OWNER** — resolution changes product acceptance or requires owner authority; not decided here.
4. Did not edit the checklist markers, the spec, the constitution, the five settled clarifications, or the plan. The checklist is reviewer-owned; `speckit-implement` must not mark its items.
5. Did not run `speckit-clarify` again: a further clarification session could reopen settled product decisions, and several apparent conflicts are constitution-determined or owner decisions rather than new clarifications.

## Result Summary

| Verdict | Count | Checklist IDs |
| --- | ---: | --- |
| RESOLVED (already answered) | 14 | CHK002, CHK003, CHK004, CHK005, CHK006, CHK007, CHK010, CHK012, CHK013, CHK015, CHK019, CHK022, CHK029, CHK034 |
| GAP (real, non-contradictory) | 14 | CHK008, CHK011, CHK014, CHK016, CHK018, CHK020, CHK021, CHK023, CHK024, CHK027, CHK032, CHK033, CHK035, CHK036 |
| CONTRADICTION (resolved by authority) | 6 | CHK001, CHK025, CHK028, CHK030, CHK031, CHK026* |
| OWNER decision required | 2 primary (+2 bounded approvals) | CHK009, CHK017; CHK024 and CHK026 also need owner sign-off on a bound or equivalence rule |
| **Total** | **36** | |

\* CHK026 is a contradiction only in the weak sense: the plan names the required device and also permits an owner-approved equivalent. The constitution permits owner authorization but requires the named profile to be fixed and cited. The missing piece is a recorded equivalence rule, which needs owner approval.

## Item-by-Item Findings

| ID | Verdict | Finding and evidence |
| --- | --- | --- |
| CHK001 | CONTRADICTION (resolved) | FR-045 says "approximately 2 seconds"; SC-020 permits loss of only edits committed in the final 2 seconds. An "approximately" interval longer than 2 s would violate SC-020. Resolution: the autosave debounce is a 2 s timer and must never exceed 2 s; plan's ≤300 ms commit budget is the commit step, not the debounce. This conforms to settled clarification 2 ("roughly 2 seconds") without changing it. Implemented by T089. |
| CHK002 | RESOLVED | "Committed change" is defined operationally: geometry commits on gesture end (`contracts/editor-interactions.md` §4); values commit on focus loss, „Fertig“, or Enter (§5); autosave starts at commit. No spec wording change is needed. |
| CHK003 | RESOLVED | FR-024's "exactly" is a model-preservation invariant: round-trip within `1e-6 pt` and drag/resize within `0.01 pt` (`contracts/coordinates-and-geometry.md` §6). SC-017's 1 mm is the artifact measurement tolerance (`contracts/export-plan.md` §6). These are different quantities, not conflicting ones. |
| CHK004 | RESOLVED | "Readable size" is quantified by `fontSizePt = clamp(0.6 × rect.height, 7.0, 12.0)` (`contracts/export-plan.md` §2.2) and verified by the artifact checks in §6. |
| CHK005 | RESOLVED | Zoom-to-field has a measurable target: `target = clamp(min(0.7 × viewportHeight / fieldHeightPt, 0.9 × viewportWidth / fieldWidthPt, 8 × fitWidthScale), fitWidthScale, 8 × fitWidthScale)` (`contracts/coordinates-and-geometry.md` §3). The checklist cites the wrong contract section. |
| CHK006 | RESOLVED | Verification state is enumerated as `unreviewed \| confirmed \| corrected \| rejected` with warnings (`data-model.md` §3.8), distinct from durability state `clean \| saving \| saved \| unsaved \| saveFailed \| recoveryFallback` (§2.5). |
| CHK007 | RESOLVED | Number rules exist: German decimal comma, optional thousands separators, canonical storage `-?\d+(\.\d+)?`, no exponent (`data-model.md` §2.3, §3.6). Negative sign and decimal separator are therefore specified; the error catalog need not restate the full grammar. |
| CHK008 | GAP | Per-field completion is visible (FR-041; `data-model.md` §3.8; overview count), but the semantics for an empty optional text field, an unchecked checkbox, and a validation-rejected value are not stated in one place. No contradiction; close with T085 and its test. |
| CHK009 | **OWNER** | FR-025 says the system MUST require the user to resolve overlapping suggestions. `contracts/export-plan.md` §3.4 says unresolved suggestions are excluded, warned about, and do **not** block export. Both cannot be the final export policy. Owner must choose: (A) block export until every conflict is resolved, or (B) allow export with unresolved suggestions excluded and warned. Current plan behavior is (B); T113 implements it only provisionally and must not be treated as settled until the owner decides. |
| CHK010 | RESOLVED | FR-010 requires readable pages to remain usable and says a full export is "affected". EXP-006 blocks only when the applier cannot copy a page; it never silently drops or replaces it (`contracts/export-plan.md` §3.4). The statements are complementary, not divergent. |
| CHK011 | GAP | "Exact same" geometry/interaction parity (FR-089) is operationalized by the same model coordinates, the shared test matrix (`contracts/editor-interactions.md` §12), and SC-017's 1 mm artifact tolerance. The named interaction set and zoom levels are partly listed; density/viewport enumeration remains incomplete. Close with T132 and T070. |
| CHK012 | RESOLVED | The disclosure trigger is testable: first-run help and before the first save (`contracts/error-catalog.de.md` PRIV-001). |
| CHK013 | RESOLVED | Strict matching is defined as exactly one suggestion per ground-truth field with `IoU ≥ 0.5` and identical type (`contracts/recognition-output.md` §8). |
| CHK014 | GAP | The performance protocol exists: ≥20 page runs after one warm-up, per-stage timers, corpus form ID, build mode, device profile (`research.md` measurement decision; `quickstart.md` §10). "Typical single A4 page" is still not defined as a corpus subset. Close with T135/T136 by naming the representative page set. |
| CHK015 | RESOLVED | The manual baseline is defined as add/move/resize/reclassify actions by the same operator against fully manual placement (`research.md` D-18), which excludes confirmation, rejection, and reordering by construction. |
| CHK016 | GAP | Trial counts and stopping rules are absent for the 100%-of-trials criteria SC-009/010/011/012/019/021/022. `quickstart.md` gives single-scenario force-stop and storage tests, not a sampling rule. Close with T092–T094, T118–T120 and the failure-injection harness (T036). |
| CHK017 | **OWNER** | SC-016/SC-018 specify participant familiarity and 5/5 first-time completion, but recruitment, prior familiarity, observation protocol, and timing start/end are not defined. `quickstart.md` §10 only says "observe five first-time users". This requires an owner-approved usability protocol (including any consent/ethics handling). T137 is blocked on that decision. |
| CHK018 | GAP | "Full export verification set" (SC-006) has no membership or size. SC-005 covers every corpus form, so the set can be defined as all corpus forms plus the two-page reference form. Close explicitly in T112. |
| CHK019 | RESOLVED | Printability has a method distinct from file-open validation: print/`pdftoppm` at 300 dpi on two independent engines without errors (`contracts/export-plan.md` §6), plus Android print preview (`quickstart.md` §7). |
| CHK020 | GAP | Airplane mode (SC-007) prevents traffic and makes SC-008 trivial; the observation method is not specified. The plan's risk table promises a network-disabled test asserting OCR success and zero sockets. Close with T138 (socket/process observation plus manifest audit), not by treating airplane mode as proof. |
| CHK021 | GAP | Zoom levels are enumerated (`0.5, 1, 1.75, 3, 8` and `0.5×, 1×, 3×, 8×`), and viewport examples exist (360 dp, 800 dp, 1440 px), but screen densities and the exact measurement method for every tested condition are not enumerated. Close with T070 and T132. |
| CHK022 | RESOLVED (operationally) | Numeric thresholds exist: 48 × 48 dp touch targets, 4.5:1 text contrast, 3:1 large-text/control contrast, 200 % text scale (`contracts/editor-interactions.md` §11; `research.md` accessibility decision). SC-015 still says "applicable minimum", so record the numbers at the acceptance step (T134); no contradiction. |
| CHK023 | GAP | `contracts/error-catalog.de.md` §11 defines the audit (ARB key parity, English-string test, allowlist, typography, dialog-action rules), but release-only scope and system-provided UI are not explicit. Close with T133. |
| CHK024 | GAP | FR-100 says the list must remain "usable" with ≥50 items without search; the plan has a 50-item evidence row but no interaction/latency bound. This is a small acceptance threshold that needs a defined measure (e.g., reach any item within a stated number of interactions or seconds). T097 defines and tests it; the numeric bound is an owner/UX decision. |
| CHK025 | CONTRADICTION (resolved) | SC-014 says 100 % of user-facing strings are German; FR-087 mandates the untranslated `SIMULATED` token. The constitution (Principles II and VIII) requires that token, so SC-014 must be read as applying to translatable strings, with `SIMULATED` as the allowlisted evidence marker already documented in `contracts/error-catalog.de.md` §9 and §11. T133 enforces that reading. No clarification is reopened. |
| CHK026 | CONTRADICTION (owner-approved) | SC-004 requires a named representative device; the plan names the Galaxy A54 5G but the Evidence Plan also allows an "owner-approved equivalent" without an equivalence rule. The constitution permits owner authorization for significant decisions but requires every performance claim to cite the fixed profile. Record an equivalence rule and owner sign-off (T141); until then, only the Galaxy A54 5G satisfies SC-004. |
| CHK027 | GAP | Plan budgets (700 ms, 400 ms, 60 fps, 300 ms, 5 s, 300 MB, 120 MB, 100 pages, 500 fields) are not each traceable to an FR/SC and are not labeled non-binding. Some are traceable (300 ms to FR-045/SC-020; 3 s to SC-004), others are engineering budgets. Close by recording a traceability table and labeling untraceable values as non-binding engineering budgets (T140). |
| CHK028 | CONTRADICTION (resolved) | The cap is 80 MiB in the plan and `data-model.md` (`83,886,080` bytes), but `IMP-007` says "80 MB". The unit mismatch is a real inconsistency. Resolution: state 80 MiB (83,886,080 bytes) in the catalog and in the import test; do not add a new scope requirement. Implemented by T045. |
| CHK029 | RESOLVED | FR-082 forbids plaintext caches "beyond what the user explicitly exports or shares"; the export preview is the user-requested artifact. The plan defines location, session lifetime, startup/session-end sweep, `allowBackup=false`, and no thumbnails/logging (`plan.md` Constraints). That satisfies constitution Principle VI. T106 verifies the lifecycle. |
| CHK030 | CONTRADICTION (resolved) | FLD-001 says overflowing text "beim Export kann er abgeschnitten werden", but FR-068/EXP-001 stop the export when content would be clipped. The blocking rule governs; the warning must say the export will be stopped until the value is shortened or the field enlarged. Implemented by T084; no product scope change. |
| CHK031 | CONTRADICTION (resolved) | The plan's Phase C exit evidence includes a "frozen metric dry run", while the spec requires the metric definition and corpus to be frozen before the first scoring run. Resolution: corpus `corpus-1.0.0` and `metric-definition.v1.md` are frozen in T033/T034 **before** any run; the Phase C dry run is explicitly unscored and uses those frozen identifiers (T060); the first scored run is Phase H. |
| CHK032 | GAP | The checklist's specific examples are partly accurate: FR-077 (retry after freeing storage), FR-081 (diagnostics exclusion), FR-082 (no plaintext cache), FR-100 (50-item usability), and FR-106 (template-save atomicity) have no direct SC counterpart. FR-106 does have an implementation rule (FR-106 itself), and FR-082 is covered by plan constraints. These are traceability/verification gaps, not contradictions; T098–T100 and T118 close them, and the traceability matrix in `tasks.md` records the mapping. |
| CHK033 | GAP | Corpus provenance, legal basis, retrieval date, and SHA-256 are required in the manifest (`research.md` D-18), and `tools/corpus/` is the stated location. "Diverse" is not defined by strata. Close with T139 by recording strata (issuer/authority, layout family, page count, scan quality) in the manifest; no new product scope. |
| CHK034 | RESOLVED | Template deletion effects are covered by the aggregate invariant that a derived document copies the source and never references template storage (`data-model.md` §3.10; FR-060/FR-099), by SC-012, and by the explicit quickstart deletion step (`quickstart.md` §13.4). DEL-003 is a user-facing consequence, not the only coverage. |
| CHK035 | GAP | FR-106 requires template-save atomicity, but no acceptance scenario or SC states it. FR-106 itself is the requirement; add an explicit verification task (T118) equivalent to the document-save criterion. |
| CHK036 | GAP | Reclassification preservation is required (FR-029; `data-model.md` §3.5), and `contracts/export-plan.md` §3.2 says an incompatible checkbox value must be resolved or explicitly accepted before export. The user-visible resolution path is not in an acceptance scenario. Close with T066/T084 and the FLD-002 test; no contradiction. |

## Resolution Rules Applied

1. **Constitution first.** SC-014 cannot override the constitutionally mandated `SIMULATED` evidence label; the label is an allowlisted technical token, not a translatable user string.
2. **Spec first for product behavior.** Where a contract message contradicts a blocking requirement (FLD-001 vs EXP-001), the message is corrected, not the blocking requirement.
3. **Plan first for engineering budgets.** Plan-level targets that are not in an FR/SC remain engineering budgets and must be labeled non-binding; they do not become product acceptance criteria by implication.
4. **No new scope.** The 80 MiB cap, the preview cache, the 50-item list, and the corpus strata are existing plan/engineering facts. Recording them as verification or traceability does not add a feature.
5. **No invented owner decisions.** Conflict-export gating (CHK009), usability protocol (CHK017), device equivalence (CHK026), and the 50-item usability bound (CHK024) are left for the owner and are marked as such in `tasks.md`.

## Relation to the Next Stage

`tasks.md` was generated by the installed official `speckit-tasks` workflow after this assessment. The checklist's scope note that `tasks.md` did not exist describes its generation snapshot; `tasks.md` now exists and this assessment covers it. The checklist remains reviewer-owned and **all 36 markers remain unchecked**; task generation did not mark them and must not be read as reviewer approval. `speckit-implement` must not modify those markers.

The five settled clarifications (protected internal copy, debounced autosave, minimal "Meine Dokumente" list, editable template versions, strict German date validation) and constitution v1.0.0 remain unchanged. No constitutional amendment, scope expansion, commit, or publication was performed.

## Official `speckit-analyze` Pass (Read-Only, After Tasks)

Command context: `.specify/scripts/bash/check-prerequisites.sh --json --require-spec --require-tasks --include-tasks` returned FEATURE_DIR `specs/001-scanned-form-workflow` and AVAILABLE_DOCS including `tasks.md`. The installed official `speckit-analyze` workflow (openCode integration, model `deepseek/deepseek-flash`, DeepSeek V4.1 Flash 1017) was dispatched read-only after `tasks.md` existed. It modified no files, consistent with its operating constraint.

**Coverage:** 110/110 functional requirements and 22/22 success criteria have at least one explicit task reference in `tasks.md`. Setup, Foundational, and Polish tasks without an FR/SC token are plan/constitution-enabled infrastructure, not unmapped product work.

**Critical issues:** 0 constitution violations. The evidence-class, Android-authority, offline/privacy, encryption, artifact-verification, German-language, and independent-review obligations are mapped to tasks.

**High/Medium findings carried into the task plan:**

| ID | Category | Severity | Finding | Resolution |
| --- | --- | --- | --- | --- |
| AN-01 | Ambiguity | HIGH | FR-045 "approximately 2 seconds" vs SC-020's strict 2 s bound | CR-1; T089/T092 |
| AN-02 | Ambiguity | HIGH | FR-024 "exactly" vs SC-017's 1 mm tolerance | Different quantities; model exactness and artifact tolerance documented in CHK003; T070/T109 |
| AN-03 | Inconsistency | HIGH | FR-025 conflict resolution vs non-blocking export in `export-plan.md` §3.4 | Owner decision OD-1; T113 provisional |
| AN-04 | Inconsistency | HIGH | SC-014 "100 % German" vs FR-087's mandatory `SIMULATED` token | Constitution Principles II/VIII; CR-2; T133 |
| AN-05 | Ambiguity | HIGH | SC-015 "applicable minimum" lacks numbers in the spec | Numeric thresholds in `editor-interactions.md` §11; T134 |
| AN-06 | Inconsistency | MEDIUM | Plan names Galaxy A54 5G but allows an unruled "owner-approved equivalent" | Owner decision OD-3; T141 |
| AN-07 | Inconsistency | MEDIUM | FLD-001 says overflow may be clipped; EXP-001 blocks export | CR-4; T084 |
| AN-08 | Inconsistency | MEDIUM | 80 MiB plan cap vs "80 MB" in IMP-007 | CR-3; T045 |
| AN-09 | Traceability | MEDIUM | Several plan budgets are neither traced to FR/SC nor labeled non-binding | T140 |
| AN-10 | Ambiguity | MEDIUM | SC-004 "typical A4 page" has no named corpus subset | T135/T136 |
| AN-11 | Ambiguity | MEDIUM | SC-006 "full export verification set" has no membership | T112 |
| AN-12 | Ambiguity | MEDIUM | SC-008 observation method is not defined; airplane mode alone is insufficient | T138 |
| AN-13 | Ambiguity | MEDIUM | FR-100 "usable" 50-item list lacks a bound | Owner decision OD-4; T097 |
| AN-14 | Coverage | MEDIUM | SC-016/SC-018 participant protocol is undefined | Owner decision OD-2; T137 |
| AN-15 | Ambiguity | LOW | "Diverse" corpus is not defined by strata | T139 |
| AN-16 | Duplication | LOW | FR-024 and SC-017 restate geometry acceptance at different levels | Acceptable: model invariant vs artifact measurement; documented in CHK003 |
| AN-17 | Terminology | LOW | "Verification states" (FR-044) and "durability status" are different concepts | `data-model.md` §2.5 vs §3.8 distinguishes them; T091 |
| AN-18 | Coverage | LOW | FR-051 disclosure has no dedicated acceptance scenario | T091 and the German audit T133 |

**Next action:** Proceed to the implementation gate with OD-1 through OD-4 visible. Do not mark the precision checklist approved; do not implement OD-1/OD-2/OD-3/OD-4 as if settled.
