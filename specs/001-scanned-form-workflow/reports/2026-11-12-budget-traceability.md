# 2026-11-12 plan-budget traceability (T140/CHK027)

| Field | Value |
| --- | --- |
| Task / check | `T140` / `CHK027` |
| Report date | 2026-11-27, Europe/Berlin |
| Revision basis | `origin/main` merge `ef01083` (merge of PR #369); report authored in a docs/tests-only candidate branch |
| Working tree | clean at start; this report and the T133 test are the only worker changes |
| Evidence class | `NONE` (documentation traceability; no runtime evidence is produced or claimed) |
| Purpose | Trace every quantitative performance/size budget in `plan.md` to a binding requirement, or label it as a non-binding engineering budget, per CHK027; supports the SC-004 and SC-016 budget evidence chain |

## 1. Method

Every quantitative budget in [plan.md](../../plan.md) §Performance Goals,
§Constraints, §Delivery Phases, and §Risks was extracted and checked against
`spec.md`, the contracts, and the task list. A value is:

- **binding (SC)** when an acceptance criterion in `spec.md` states it;
- **binding (FR/contract)** when a functional requirement or contract states it;
- **non-binding engineering budget** when only `plan.md` (or research/design
  prose) states it; it guides implementation and review but is not an
  acceptance threshold.

Plan-only values are not deleted or re-worded by this record; they are labelled
so that no later report can present one as a ratified acceptance claim. No
threshold was changed and no code was touched.

## 2. Traceability table

| # | Budget (value) | Plan source | Binding source | Class | Evidence/owner task | Current evidence |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Field detection **≤ 3 s median** per typical A4 page, 200 DPI analysis raster, release build, named Galaxy A54 5G (or T141-approved equivalent) | plan §Performance Goals L51; also §Risks L205 | `spec.md` **SC-004** (L762–765) | **Binding (SC)** | T135 (protocol, absent), T136 (device run, absent), T141 (equivalence rule) | Not measured in this phase. `tools/evaluation/performance_protocol.md` and the device-performance report do not exist; SC-004 remains open. T264D must not substitute for it. |
| 2 | First page visible after document open **≤ 700 ms** on the same device | plan §Performance Goals L52 | none | **Non-binding engineering budget** | T135/T136 measurement set | No dedicated test or report; only specified here. |
| 3 | Page-turn render **≤ 400 ms** at fit-width zoom | plan §Performance Goals L52 | none | **Non-binding engineering budget** | T135/T136 measurement set | No dedicated test or report; only specified here. |
| 4 | Overlay drag/resize **60 fps (16.7 ms frame budget)** | plan §Performance Goals L52 | none | **Non-binding engineering budget** | Editor interaction tests (T064–T075) exercise behaviour, not frame timing | No frame-timing measurement exists; interaction tests prove behaviour only. |
| 5 | Autosave commit (typical **≤ 2 MB** revision) **≤ 300 ms** | plan §Performance Goals L53; §Risks L207 | FR-045 / SC-020 bind the **2 s debounce** and the final-2-second loss bound, not the 300 ms commit step; `plan.md` calls 300 ms an engineering budget | **Non-binding engineering budget** (the 2 s debounce is binding separately) | T089/T092 autosave and durability tests | Autosave correctness is tested; the 300 ms commit time is not an acceptance claim. |
| 6 | Two-page export including verification **≤ 5 s** on the same device | plan §Performance Goals L54 | none | **Non-binding engineering budget** | T104–T109 export tests/artifact verification | Export correctness/artifact verification is tested; no timing report claims 5 s. |
| 7 | Peak memory **≤ 300 MB** for a five-page A4 document at 200 DPI analysis plus fit-width rendering | plan §Performance Goals L55 | none | **Non-binding engineering budget** | T135/T136 and T264D memory measurements | No measured peak-memory report for this workload. |
| 8 | Hard import cap **80 MiB** per PDF | plan §Performance Goals L55; §Constraints | FR-005 and `contracts/error-catalog.de.md` IMP-007 (`80 MiB (83.886.080 Bytes)`) | **Binding (FR/contract)** | T045 (closed) | `T045` verifies the 83,886,080-byte cap in `ImportService.kt` and the catalogue wording. |
| 9 | Release APK budget **≤ 120 MB** (bundled ML Kit, PDFium, PDFBox, Noto Sans) | plan §Constraints L63 | none (product constraint stated in plan only) | **Non-binding engineering budget** (recorded as a release guidance value) | T002/T003 dependency and release review | `tools/dependency_review.md` records a **57,015,925-byte** release APK, below 120 MB; the review is not an acceptance gate and the APK was unsigned. |
| 10 | 200 DPI analysis raster (not 300) | plan §Risks L205; §Performance Goals L51 | SC-004 measurement condition; recognition contracts | **Binding measurement condition** (not a pass/fail budget) | T063/T264A benchmark harness | Recorded as the analysis-raster condition in recognition evidence; no new run here. |
| 11 | Two-page reference journey: import, review, fill, save, export in **≤ 10 min median** for a user familiar with the form | plan §Delivery Phases H L184 | `spec.md` **SC-016** (L792–793) | **Binding (SC)** | T137 | Blocked on OD-2 (protocol and observation details); neither the timed run nor the usability run is executed. Not claimed. |
| 12 | Stored list: at least **50** documents/templates without search | plan §Scale/Scope L67; §Performance Goals context | FR-100 / OD-4 (Q10=A): 50 entries, **open-to-first-frame ≤ 500 ms** host widget test, lazy viewport, no pagination | **Binding (FR/OD-4)** | T097 | `apps/feldexa_app/test/stored_list_50_test.dart` measures the 500 ms host bound with 50 entries. |
| 13 | Scale: typical **1–10 pages / 20–150 fields**, supported up to **100 pages / 500 fields** | plan §Scale/Scope L67 | data model/contracts bounds | **Non-binding engineering scope budget** | model/recognition tests | Covered structurally; no separate acceptance measurement. |
| 14 | Corpus of at least **20 rights-cleared real German authority forms** plus synthetic CI fixtures | plan §Scale/Scope L67; Principle IV L78 | constitution Principle IV; SC-001/SC-002 | **Binding when scored evaluation is claimed** | T033/T034 (deferred by Q4/Q9=B), T142 | Corpus is not in the tree; SC-001/SC-002/SC-005 are excluded from this phase's claims. |
| 15 | Export placement tolerance **1 mm** at A4 print scale | plan §Risks L206 | `spec.md` **SC-017** | **Binding (SC)** | T109/export artifact verification | **Partial only.** `2026-11-26-t344-export-proof-depth.md` records the text origin/baseline within tolerance but explicitly `1 mm placement claim NOT_PROVEN` for the stronger rect-midpoint reading; not re-measured here. |
| 16 | 2 s autosave debounce with final-2-second loss bound | plan §Delivery Phases E L181; §Risks L207 | FR-045, SC-020, CR-1 | **Binding (FR/SC)** | T089/T092 | Covered by autosave/durability tests. |

## 3. Untraceable plan-only values (explicitly non-binding)

The following values appear only in `plan.md` and have no FR, SC, or contract
definition, so they are recorded here as **non-binding engineering budgets**:
first-page visibility 700 ms, page-turn 400 ms, 60 fps/16.7 ms interaction
frame budget, autosave commit 300 ms (the 2 s debounce is separately binding),
two-page export 5 s, peak memory 300 MB, release APK 120 MB, and the
1–10/20–150 typical and 100/500 maximum scale figures. They may guide
implementation and future measurement tasks but cannot be cited as passed or
failed acceptance criteria.

Two further values are binding but **not measured in this phase**: SC-004
(3 s median detection) and SC-016 (10 min median journey). Their evidence tasks
(T135/T136/T137 and the T141 equivalence rule) remain open; this record makes
no performance claim.

## 4. Conclusion

- Binding SC budgets: **SC-004** (3 s), **SC-016** (10 min), **SC-017** (1 mm);
  only SC-017 has partial artifact-level evidence (`NOT_PROVEN` for the full
  1 mm rect-midpoint reading in the T344 report), while SC-004 and SC-016 have
  no current measurement.
- Binding FR/contract budgets: 80 MiB import cap (T045 verified), FR-100/
  OD-4 500 ms host bound (T097 test present), 2 s debounce (tests present).
- Every other plan number is recorded as a **non-binding engineering budget**.
- No threshold was changed and no run was invented. Evidence class `NONE`.
