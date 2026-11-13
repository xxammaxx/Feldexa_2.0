# Manual-Baseline Protocol — SC-003 Add/Move/Resize/Reclassify Comparison

| Field | Value |
| --- | --- |
| Protocol | `manual-baseline-protocol.v1.0.0` |
| Task / issue | T035 / #35 |
| Status | Normative protocol, frozen before the first scored baseline run. No measurements are recorded in this file. |
| Execution owner | T142, in `specs/001-scanned-form-workflow/reports/2026-11-12-recognition.md` |
| Evidence class of this file | `NONE` (protocol and method only; it proves no runtime behavior) |
| Date | 2026-11-13 (Europe/Berlin) |

## 0. Purpose, scope, and non-goals

This protocol defines the only permitted way to measure SC-003: the reduction
in manual placement work for detection-assisted field placement relative to
fully manual placement, using the add/move/resize/reclassify comparison fixed by
`research.md` D-18.

It exists so that T142 can execute a reproducible, fair comparison and so that a
reader can tell, before seeing any result, exactly which actions count, which
conditions must be equal, how the reduction is calculated, and which practices
are prohibited. It deliberately contains **no measured values, no placeholder
results presented as data, and no estimate of the expected reduction**. Every
numeric parameter below is either quoted from a normative artifact or labelled
as a protocol choice that is frozen before the first run.

Non-goals:

- This is not the recognition evaluation (T060 dry run, T142 scored run), not a
  type/position accuracy report, and not a substitute for TP/FP/FN reporting.
- This is not a timing or performance protocol. Elapsed time may be recorded as
  a secondary observation, but it cannot replace the action comparison and it
  creates no performance claim (SC-004 is owned by T141).
- This is not a usability protocol (SC-016/SC-018 are owned by T137), not an
  export protocol, and not device acceptance.
- This protocol does not choose, infer, or report any owner decision. OD-1
  through OD-4 in `tasks.md` remain open.

## 1. Normative sources and precedence

| Source | What it fixes | Use in this protocol |
| --- | --- | --- |
| `.specify/memory/constitution.md` | Principles IV (frozen corpus and data) and VIII (separated, measured evidence; no unmeasured claims) | Freeze rules, evidence class, no invented results |
| `spec.md` SC-003 | "Manual placement work drops by at least 80% relative to fully manual placement, measured as the share of a form's fields that need no manual add, move, resize, or type change after the user's review." | Field-share measure and 80% threshold |
| `research.md` D-18 | "for each corpus form, record the number of fields a reference operator must add/move/resize/reclassify after detection; compare against fully manual placement with the same operator and tool. Reduction = 1 − (manual actions after detection / fully manual actions)." | Action classes, same-operator/same-tool rule, reduction formula |
| `tasks.md` T035 and T142 | T035 records this protocol; T142 executes the frozen evaluation on the authoritative Android runtime and records the manual baseline in the recognition report | Scope and execution owner |
| `metric-definition.v1.md` (frozen by T034) | Matching rule: same type and IoU ≥ 0.5, one-to-one, extras are false positives, unmatched GT fields are false negatives | Quality-parity predicate |
| `corpus-1.0.0` manifest and ground truth (frozen by T033/T034) | The forms, field rectangles, types, and relevance flags | Population, ground truth, and form identity |
| `reports/README.md` | Evidence classes, required report fields, no self-approval, single evidence root | T142 report format and limitations |

Precedence, highest first: constitution → `spec.md` → `plan.md` →
`research.md` → this protocol. If two normative sources conflict on a point that
affects the SC-003 decision, the run stops and the conflict is escalated; the
operator, analyst, or T142 author must not silently choose the more favourable
reading. A protocol conflict is not resolved by changing this file after data
collection.

## 2. Terms and counting rules

### 2.1 Population

- **Form** means one PDF in the authoritative real-form subset of the frozen
  `corpus-1.0.0`, identified by its manifest form ID and SHA-256. The synthetic
  CI subset is never a substitute for a real form and is not part of the SC-003
  population. The population is fixed before the first run.
- **Ground-truth field (GT field)** means one field rectangle and field type in
  the frozen ground truth for that form, including its frozen relevance flag.
  Only GT fields marked relevant by the frozen manifest are counted. No field is
  added to, removed from, or reinterpreted in the GT after any run begins.
- **Reference operator** means the single trained person who produces the field
  layouts in both conditions. The operator works from the rendered form only,
  not from GT, the detection output's internal diagnostics, or a previous
  layout.
- **Manual condition (`M`)** means fully manual placement: the operator starts
  with an empty field set on the same tool and adds every accepted field.
  Detection is disabled at build/runtime, not merely hidden in the UI; a runtime
  assertion or log must show that no detection adapter ran and no suggestion was
  present.
- **Detection-assisted condition (`D`)** means the production recognition
  pipeline runs once on the same form, device, and build, and the operator
  reviews its suggestions and corrects them.
- **Accepted layout** means the field set the operator accepts for filling after
  review, before any value is entered. It is exported in the tool's canonical
  layout form with stable field IDs, origin (`suggestion` or `manual`), page
  index, geometry in source points, and type.

### 2.2 The four counted operation classes

Only these four classes count toward the primary comparison. They are the four
classes named by D-18 and SC-003.

| Class | Definition | Count per form and condition |
| --- | --- | --- |
| **add** | A final accepted field that the operator created and that has no originating suggestion in the initial state of that condition. The initial type choice made while creating the field is part of the add. | 1 per such field |
| **move** | A final accepted field that derives from an initial suggestion or from the operator's just-added field, and whose final position differs from its initial committed position in that condition. A single committed command that moves several fields counts once for each field. | 1 per such field |
| **resize** | A final accepted field whose final width or height differs from its initial committed size in that condition. One committed resize command that changes both axes counts once for that field; two separate committed resize commands on the same field still count once in the primary net count, and the committed-command secondary count exposes both. | 1 per such field |
| **reclassify** | A final accepted field whose final type differs from its initial type in that condition. The initial type of an added field is chosen during the add; a later type change is a reclassify. | 1 per such field |

This is D-18's "number of fields a reference operator must add/move/resize/
reclassify", operationalized per field and per operation class. A field can
contribute at most one count to each of the four classes, so a form's primary
count is bounded by four times its GT field count. The net comparison is
deliberately based on the final accepted state, not on how many times the
operator changed their mind.

### 2.3 What is not in the primary count

The following are recorded separately and never added to the D-18 primary
count. They must still be reported so that excluded work is visible and cannot
be hidden.

| Observation | Why it is separate | Reporting |
| --- | --- | --- |
| confirm | Accepting a correct suggestion without geometry or type change is zero placement work under D-18. | Count per form and condition |
| reject | Rejecting a false-positive suggestion is real work but is not one of the four D-18 classes. | Count per form and condition |
| remove | Removing an accepted field, including a mistaken add or a false positive, is real work but is not one of the four D-18 classes. | Count per form and condition |
| reorder | Changing field order/tab order is excluded by the D-18 wording, as recorded by the precision-testability assessment for CHK015. | Count if performed |
| set value / signature | Value entry and signatures are outside placement. | Must not be performed; see §3.4 |
| navigation (scroll, pan, zoom, page change) | Not a placement operation. | Count and record zoom/pan policy |
| selection, undo/redo bookkeeping | Selection is not placement; undo/redo is not a negative action. | Secondary committed-operation count |
| save/export of the layout | Administrative, not placement. | Not counted; hashed as an artifact |

**Undo/redo rule.** The primary count is net: it compares the condition's
initial state with the final accepted state and does not subtract an action
because it was undone, nor add it again because it was redone. The secondary
committed-operation count records every committed action, including actions
later undone, so trial-and-error cannot be hidden. A redo produces a new
committed event in the secondary count. An undone action that leaves no net
change contributes nothing to the primary count and is visible only in the
secondary count.

**No epsilon.** "Differs" means the canonical serialized geometry or type is not
equal to the initial canonical value. The tool's persisted coordinate precision
is used; no tolerance is invented to turn a real change into no change or a
rounding difference into an action. Quality parity (§4.3) separately applies the
frozen metric's IoU ≥ 0.5 matching rule; that is a quality predicate, not an
action-count tolerance.

## 3. Conditions that must be identical

Except for the presence of detection suggestions, the two conditions are the
same experiment. The following are equal for a given form and operator.

| Dimension | Required equality |
| --- | --- |
| Operator | Same reference operator for both conditions of the form, with the qualification in §4.1 |
| Tool and build | Same application source, build identity, and APK/bundle SHA-256. Detection is disabled at runtime through the pre-frozen measurement flag; if the tool cannot disable it at runtime, two builds from the same source differing only in that flag may be used, with both hashes recorded and a diff proving no other change. No product behavior other than detection seeding may differ. |
| Device / runtime | The same authoritative Android device/profile T142 uses; same OS/build fingerprint, display size, density, font scale, input method, and orientation policy. Any approved device equivalence is recorded by T141 under OD-3 and is not asserted or invented here. `SIMULATED` and `EMULATOR` runs may explore but cannot satisfy SC-003. |
| Input | Same PDF bytes and SHA-256, same page order, same form ID, same app-data reset before each condition |
| Ground truth and metric | Same frozen `corpus-1.0.0` GT, same `metric-definition.v1.md` version and hash, same scorer build |
| Instructions | Same written operator instructions (§3.4), same acceptance definition, same no-time-limit rule |
| Zoom / pan | Same default zoom and the same permission to zoom and pan; all navigation is logged but not counted in the primary action count |
| Values | No field values are entered in either condition; no signatures are created; no export for printing is performed |
| Environment | Offline/airplane mode, no notifications, same date/time window rules, no app update or OS update between the paired conditions |
| Measurement | Same logger schema/version and same final-layout export format |

### 3.1 Manual condition procedure

1. Clear app data for the form so no prior layout, suggestion, template, or
   autosave is restored.
2. Confirm at runtime that detection did not run and that the initial field set
   is empty.
3. Starting from the rendered form, add one field for every printed field area
   the operator judges relevant, choose its type, and adjust position/size until
   the operator would accept the layout for filling.
4. Do not use templates, prior layouts, OCR-assisted pre-placement, the GT
   overlay, saved document copies, or any hint that places or classifies a
   field. The operator may use the same ordinary viewer controls available in
   both conditions.
5. Accept the layout. Export the canonical layout and the action log.

A field that the operator adds at the exact final position/size/type costs one
add and no move/resize/reclassify. A field that is added and then adjusted costs
the corresponding additional classes. This is intentional: the comparison is
about the work the tool requires, not about a particular gesture sequence.

### 3.2 Detection-assisted condition procedure

1. Clear app data for the same form.
2. Import the same PDF bytes and run the frozen production detection pipeline
   exactly once with the frozen build and parameters. Do not pre-process the
   PDF, do not choose a different page, and do not tune detection per form.
3. Show the suggestions exactly as the product shows them. Do not add hidden
   suggestions, hints, counts, GT information, or diagnostics.
4. Review the suggestions. Confirm correct ones, reject false positives, add
   missing fields, move/resize misplaced fields, reclassify wrong types, and
   remove anything that is not an accepted field. Work until the operator would
   accept the layout for filling.
5. Accept the layout. Export the canonical layout and the action log.

If detection fails to produce suggestions for a form, that failure is part of
the measurement: the operator proceeds manually from the empty suggestion set
and the form is reported as a detection failure. The pipeline is not retried to
obtain a better suggestion set unless the failure is a documented infrastructure
failure that occurred before any operator action; even then, the original
attempt and the reason for the retry are retained and reported.

### 3.3 Order, washout, and learning control

- The condition order for each form is assigned by a pre-registered, balanced
  schedule: half the forms run `M` then `D`, the other half run `D` then `M`,
  with the assignment and random seed hashed before the first run. The schedule
  is not changed after any result is seen.
- The two conditions for the same form are separated by at least 24 hours. The
  operator does not review the earlier layout, action log, detection output, or
  notes during the washout.
- The operator may not discuss a form or its detection output with the analyst,
  the detector author, or another operator between conditions.
- The order assignment is recorded per form and analyzed as a possible order
  effect. A large order effect is reported as a limitation; it is not removed
  by dropping forms.

These are protocol choices, fixed before the first run. They mitigate, but do
not eliminate, within-operator memory and learning effects.

### 3.4 Operator instructions (verbatim basis)

The operator receives these instructions in both conditions, with only the
condition-specific seeding step differing:

> Produce the field layout you would accept for filling this form. Place one
> field for each printed field area you judge relevant, choose the field type you
> judge correct, and adjust position and size until you would accept the layout.
> You may zoom and pan; you may not enter field values or create signatures. Do
> not use a template, a previous layout, a ground-truth overlay, or any external
> hint. Work at your normal pace; there is no time limit. Stop when you accept
> the layout, not when you reach a target count.

The operator is not told the 80% threshold, the expected reduction, the GT field
count, or any running score. The analyst and scorer are blind to the condition
label until scoring is complete (§4.5).

## 4. Fair-comparison controls

### 4.1 Reference operator

- One reference operator performs both conditions for a given form, and the same
  operator performs the primary run across the corpus.
- The operator is trained on non-corpus practice forms and must complete one
  practice form in each condition with the same quality parity predicate before
  data collection. Practice forms are not counted, are not in `corpus-1.0.0`,
  and are not selected to resemble any particular corpus form.
- The operator must not be the detector author or tuner and must not have seen
  the GT or the detection implementation for the corpus forms. If the only
  available operator has seen the GT, that is a recorded bias limitation and the
  run cannot satisfy SC-003; it may be reported as `PARTIAL` only.
- A second operator may repeat a pre-registered, hash-selected subset as a
  robustness check. The second operator's results are reported separately and
  are never combined with, or substituted for, the primary operator's results.

### 4.2 Preregistration and freezing

Before the first form is measured, T142 records a run manifest containing at
least:

```json
{
  "run_id": "<opaque run identifier>",
  "task": "T142",
  "protocol": {"path": "tools/evaluation/manual-baseline.md", "sha256": "<sha256>"},
  "corpus": {"version": "corpus-1.0.0", "manifest_sha256": "<sha256>", "gt_sha256": "<sha256>"},
  "metric": {"version": "metric-definition.v1.md", "sha256": "<sha256>"},
  "scorer": {"path": "tools/evaluation/score.dart", "sha256": "<sha256>"},
  "build": {"version": "<version>", "apk_sha256": "<sha256>", "build_mode": "<mode>"},
  "device": {"profile": "<authoritative device profile>", "fingerprint": "<build fingerprint>"},
  "operator": {"pseudonymous_id": "<id>", "qualification_record": "<path or ref>"},
  "schedule": {"seed": "<seed>", "sha256": "<sha256>"},
  "logger": {"version": "<version>", "schema_sha256": "<sha256>"},
  "started_at": "<ISO-8601 date/time with timezone>"
}
```

The protocol hash, corpus manifest hash, GT hash, metric hash, scorer hash,
build hash, device fingerprint, operator qualification, schedule hash, and
logger schema are all fixed before the first scored form. A change to any of
them creates a new run ID and a separately reported run; it does not edit the
existing run. The manifest is an input to the T142 report, not a result.

### 4.3 Quality parity (the anti-shortcut gate)

A work comparison is valid only if both conditions reach the same quality bar on
the same form. After each condition, an independent scorer applies the frozen
`metric-definition.v1.md` predicate to the accepted layout and the GT:

- every GT field is matched by exactly one accepted field of the same type with
  IoU ≥ 0.5;
- every accepted field matches exactly one GT field (no false positives, no
  extras);
- the matched count equals the GT field count, and type accuracy among matches
  is 100%.

In `metric-definition.v1.md` terms: for the accepted layout versus GT, TP equals
the GT field count, FP = 0, FN = 0, and every TP is same-type with IoU ≥ 0.5.
This is the same one-to-one matching rule used for the recognition evaluation;
no separate, weaker baseline tolerance is introduced.

If quality parity fails in either condition for a form, the work comparison for
that form is **invalid**. It is reported as `INVALID` with the reason; it is not
dropped, silently fixed, re-scored, or retried to obtain a better result. If a
form is invalid, the corpus run is `PARTIAL` or `FAIL` as appropriate for the
coverage rule in §6.4. Quality parity prevents the assisted condition from
"winning" by stopping early with fewer or worse fields than the manual
condition.

### 4.4 Instrumentation

The primary comparison requires an action log produced by the measurement build,
not a retrospective estimate. The logger records, at minimum:

- run ID, form ID, condition code (blinded), operator pseudonymous ID, and
  timestamp;
- stable field ID, page index, `origin` (`suggestion` or `manual`), event class
  (`add`, `move`, `resize`, `reclassify`, `confirm`, `reject`, `remove`,
  `reorder`, `navigate`, `undo`, `redo`), committed flag, and the field ID of an
  undo/redo link;
- before/after geometry in source points and before/after field type for every
  geometry or type change;
- the detection run metadata (build hash, device, frozen parameters) for `D`;
- the canonical accepted-layout export.

The measurement build must use the same production detection behavior as the
frozen build. Logging and the manual-condition detection-disable flag are the
only permitted differences; if a separate manual build is used, the source diff
and both build hashes are recorded. The logger schema and build hash are frozen
before the run.

If the action log is unavailable, a screen recording plus two independent coders
may be used only as a `PARTIAL` observation. It cannot satisfy SC-003, and the
report must say so. A single coder's recollection or a post-hoc reconstruction
is not evidence.

### 4.5 Blinding and scoring

- Condition labels are replaced with random codes before the scorer sees the
  layouts. The scorer does not know which layout is manual and which is
  assisted.
- The scorer is run after both conditions for the form (and preferably after
  the full corpus) are complete, using the frozen scorer, GT, and metric. The
  labels are decoded only after the per-form counts and quality checks are
  written to the run record.
- The analyst may verify arithmetic but may not adjust an action count, a
  match, a form, or a threshold. Any correction is a new dated run or a
  documented `FAIL` of the first run; it is never a silently edited result.

### 4.6 What the operator and analyst must not know during the run

- The operator does not see GT, GT field counts, detection internals, the 80%
  threshold, the expected reduction, or running totals.
- The analyst does not see the condition label attached to a layout until the
  blinding is opened.
- No one sees a per-form result and then changes the condition order, the
  action rules, the quality predicate, the corpus, or the metric.

## 5. Execution procedure

### 5.1 Preconditions

1. `corpus-1.0.0` and its GT are frozen by T033/T034, and the manifest and GT
   hashes are recorded.
2. `metric-definition.v1.md` and the scorer are frozen by T034, and their hashes
   are recorded.
3. The authoritative Android build and device are the ones T142 uses for the
   scored recognition evaluation; the APK/bundle hash and device fingerprint are
   recorded.
4. The measurement build, logger schema, action export, and manual-condition
   detection-disable assertion are verified on a non-corpus practice form.
5. The reference operator has completed the qualification in §4.1.
6. The run manifest in §4.2 is written and hashed before the first scored form.

If any precondition is missing, T142 records the check as `UNAVAILABLE` or
`ABSENT` and does not claim SC-003.

### 5.2 Per-form sequence

For each form in the frozen population, in the pre-registered order:

1. Verify the PDF SHA-256 against the manifest and the form ID.
2. Run the first condition assigned by the schedule, following §3.1 or §3.2.
3. Export the canonical accepted layout and action log; hash them.
4. Run the quality-parity check §4.3. Record `VALID` or `INVALID` and the reason.
5. Wait at least the washout period, then run the other condition on the same
   form, with the same operator, build, device, input, and instructions.
6. Export, hash, and check quality parity again.
7. Record both layouts, logs, hashes, order, timestamps, and any deviation. Do
   not look at the decoded condition result.

### 5.3 Scoring sequence

1. Freeze the corpus of layouts and logs; no further edits.
2. Decode condition labels only after the frozen layouts are copied for
   scoring.
3. Apply the canonical action mapping from §2.2 and the quality predicate from
   §4.3 to every form.
4. Compute per-form counts and ratios (§6), then the pooled values.
5. Write the T142 report with the full per-form table and the pooled result.
6. Retain raw logs under the evidence root or an attestation and record their
   byte sizes and SHA-256.

### 5.4 Invalid runs and reruns

- A run that fails a precondition before any scored form may be restarted with
  a new run ID and a recorded reason.
- A run with a protocol violation (wrong build, wrong operator, detection in
  `M`, GT access, changed threshold, missing logs, changed corpus/metric) is
  invalid. The original attempt is retained; a corrected attempt is a new run
  with a new ID. Individual forms are not cherry-picked or replaced.
- A form that fails quality parity is reported `INVALID` and is not rerun to
  obtain a valid result.
- A corpus, GT, metric, scorer, or matching-rule change creates a new corpus/
  metric version and a new, separately reported run. Earlier results are never
  re-scored as the same run.

## 6. Metrics and the SC-003 decision

### 6.1 Per-form counts

For form `f` and condition `c`, with `GT(f)` the frozen relevant GT fields:

```text
A_c(f) = Σ over g in GT(f) of [ add_c(g) + move_c(g) + resize_c(g) + reclassify_c(g) ]
```

Each term is 0 or 1 under §2.2. `M_f = A_M(f)` is the fully manual count and
`D_f = A_D(f)` is the detection-assisted count.

```text
R_f = 1 − (D_f / M_f)          (D-18 reduction for form f; requires M_f > 0)
U_f = untouched_D(f) / |GT(f)| (SC-003 field share for form f)
```

`untouched_D(f)` is the number of GT fields for which all four terms are zero in
the assisted condition, i.e. the fields that need no manual add, move, resize,
or type change after review.

### 6.2 Pooled values

```text
R_pooled = 1 − (Σ_f D_f / Σ_f M_f)
U_pooled = (Σ_f untouched_D(f)) / (Σ_f |GT(f)|)
```

`R_pooled` is a ratio of totals, not the mean of per-form ratios. `U_pooled` is
also a ratio of totals. Both are reported with the per-form rows; a pooled value
must never be reported alone.

### 6.3 Reporting precision and rounding

- Report integer counts exactly; never invent, interpolate, or estimate a
  missing count.
- Report ratios to four decimal places and percentages to one decimal place.
- Compare the unrounded value with the 0.80 threshold. Do not round a value up
  across the threshold and do not choose the rounding that turns a fail into a
  pass.
- Report the median, minimum, and maximum per-form `R_f` and the count of forms
  below the threshold. These are descriptive; they do not replace the pooled
  decision.
- Report the secondary counts (confirm, reject, remove, reorder, navigation,
  committed operations, elapsed time) separately. They are not added to
  `A_c(f)` and cannot be used to lower it.

### 6.4 SC-003 decision rule

SC-003 is satisfied only when **all** of the following hold:

1. The population contains at least 20 rights-cleared real forms from
   `corpus-1.0.0`, and every frozen form is reported; no form is missing,
   excluded, or replaced by a synthetic form.
2. Every reported form has `M_f > 0`, a valid quality-parity result in both
   conditions, and retained action logs.
3. `R_pooled ≥ 0.80` (the D-18 action reduction).
4. `U_pooled ≥ 0.80` (the SC-003 field-share wording).

The conjunction in items 3 and 4 is deliberate. D-18 defines the action-ratio
reduction and SC-003 defines the field-share measure; both are normative, so a
run that meets only one of them is `FAIL` or `PARTIAL`, and the divergence is
reported rather than resolved by choosing the more favourable measure. No
combined headline replaces the two values, the per-form rows, or the separated
TP/FP/FN/type/position results that belong to the recognition evaluation.

If any form is below 80% under either measure, the report must list it and must
not claim that every form met the target. The pooled decision stands only with
that disclosure; the per-form distribution is part of the result, not an
optional appendix.

### 6.5 Result vocabulary

Use `PASS`, `FAIL`, or `PARTIAL` only, plus per-check `UNAVAILABLE` or `ABSENT`.
A run with an invalid form, missing log, missing quality check, or missing
prerequisite is not `PASS`. A run that meets the numeric thresholds but has an
unresolved evidence defect is `PARTIAL`, not `PASS`. A failed target is reported
as `FAIL` and is never re-scored or relabelled.

## 7. Required T142 record

T142 records the result in
`specs/001-scanned-form-workflow/reports/2026-11-12-recognition.md` with at
least the following. Values in angle brackets are placeholders; they must be
replaced with the actual frozen values and measurements at execution time, not
before.

### 7.1 Run identity

| Field | Required content |
| --- | --- |
| Task / issue | T142 / #142 (with the manual-baseline portion attributed to T035 / #35) |
| Evidence class | `DEVICE` (authoritative Android runtime) |
| Protocol | `tools/evaluation/manual-baseline.md`, byte size and SHA-256 |
| Corpus | `corpus-1.0.0`, manifest SHA-256, GT SHA-256, form count |
| Metric / scorer | `metric-definition.v1.md` version and SHA-256; scorer path and SHA-256 |
| Build | App version, build mode, APK/bundle SHA-256, measurement logger version |
| Device | Authoritative device profile and build fingerprint |
| Operator | Pseudonymous ID and qualification record |
| Schedule | Condition-order seed and SHA-256 |
| Run window | Start/end date-time with timezone |
| Result | `PASS`, `FAIL`, or `PARTIAL`, with the SC-003 decision and all limitations |

### 7.2 Per-form table

| Form ID | GT fields | `M_f` | `D_f` | `R_f` | Untouched fields | `U_f` | Quality parity `M` / `D` | Order | Removes/rejects | Notes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- |
| `<form-id>` | `<n>` | `<n>` | `<n>` | `<ratio>` | `<n>` | `<ratio>` | `<VALID/INVALID>` | `<M→D / D→M>` | `<n>` | `<deviation>` |

### 7.3 Pooled summary

| Measure | Value | Decision |
| --- | ---: | --- |
| `R_pooled` | `<ratio>` | `<≥ 0.80?>` |
| `U_pooled` | `<ratio>` | `<≥ 0.80?>` |
| Forms reported / expected | `<n> / <n>` | `<complete?>` |
| Forms below 80% | `<n>` | `<listed?>` |
| Quality-parity failures | `<n>` | `<listed?>` |
| SC-003 | — | `<PASS / FAIL / PARTIAL>` |

### 7.4 Evidence and limitations

- Hash every retained action log and accepted-layout export with byte size and
  SHA-256; if a log is not retained, say so and explain why.
- State what the `DEVICE` class can and cannot prove, the order-effect
  observations, any operator/GT conflict, any invalid form, and any unavailable
  check.
- State explicitly that no `SIMULATED` or `EMULATOR` result was substituted for
  the `DEVICE` baseline.
- Leave the independent-review table blank; the author records the run and does
  not approve it.
- Do not include absolute home/worktree/SDK paths or raw session, terminal,
  task, or dispatch identifiers.

## 8. Prohibited practices (benchmark-integrity rules)

The following invalidate the comparison. A report that cannot show compliance
with this table is not evidence for SC-003.

| Prohibited practice | Why it is prohibited | Required record |
| --- | --- | --- |
| Running detection in the manual condition, or leaving a suggestion/template/previous layout in it | Makes the "fully manual" baseline not fully manual | Runtime assertion/log and empty initial state |
| Using GT, GT counts, GT overlays, or a previous layout during placement | Lets the operator target the scorer instead of doing the work | Operator declaration and environment check |
| Tuning detection, changing parameters, pre-processing the PDF, or choosing pages per form | Changes the measured system between forms | Frozen build/parameters and per-form invocation log |
| Changing condition order after seeing a result | Confounds order with outcome | Preregistered schedule hash and per-form order |
| Stopping before quality parity, or accepting fewer/worse fields in one condition | Creates an artificial reduction | Independent quality-parity check in both conditions |
| Dropping, replacing, retrying, or cherry-picking a form or an invalid result | Hides failures | Full frozen population; `INVALID` rows retained |
| Changing the action classes, the net/committed rule, the quality predicate, the threshold, or the rounding after results | Moves the target | Frozen protocol hash; new run for any change |
| Counting confirmation, rejection, removal, reordering, navigation, or value entry as an add/move/resize/reclassify | Inflates the manual baseline or hides assisted work | Separate secondary counts |
| Deducting undone actions from the primary count or adding a redo twice to the manual baseline | Manipulates net work | Net primary + full committed secondary count |
| Reporting only the pooled value, the mean of per-form ratios, or the best forms | Hides distribution and failures | Full per-form table and distribution |
| Merging `SIMULATED`, `EMULATOR`, and `DEVICE` results, or using an emulator for the SC-003 run | Violates evidence separation | One class and one runtime per run |
| Using fewer than 20 rights-cleared real forms or substituting synthetic forms | Violates D-18's corpus | Frozen manifest count |
| Changing operator, build, device, display, or instructions between paired conditions | Breaks the same-operator/same-tool comparison | Equality table and run manifest |
| Post-hoc re-scoring, relabelling a failure, or presenting a rerun as the original run | Violates the evidence rules | Original run retained; reruns separately dated |
| Deleting or editing raw logs or accepted layouts after scoring | Destroys reproducibility | Hashes and frozen copies |
| Claiming a result from this protocol document or from an expected value | Invents a measurement | No result in this file; T142 records actual values |

## 9. Reproducibility checklist

A reader must be able to repeat the method without asking the author:

- [ ] The protocol file hash in the T142 run manifest matches this file.
- [ ] The corpus manifest, GT, metric, scorer, build, device, operator,
      schedule, and logger hashes were recorded before the first form.
- [ ] The full frozen form list is in the report, with no omission or
      substitution.
- [ ] Both conditions used the same operator, tool/build, device, input,
      instructions, and no-time-limit rule, except for detection seeding.
- [ ] The manual condition has a runtime proof that detection did not run and
      the initial field set was empty.
- [ ] Every form has an action log, a canonical accepted layout, and a quality
      parity result for both conditions.
- [ ] The scorer is frozen and was run with condition labels blinded.
- [ ] Per-form `M_f`, `D_f`, `R_f`, untouched fields, `U_f`, quality parity,
      order, and secondary counts are present.
- [ ] `R_pooled` and `U_pooled` are computed from totals, not from a mean of
      per-form ratios.
- [ ] The 0.80 comparison uses unrounded values; no value is rounded across the
      threshold.
- [ ] Every invalid, missing, unavailable, or absent item is visible.
- [ ] The result is `PASS`, `FAIL`, or `PARTIAL`; no failure is hidden in prose.
- [ ] The independent-review table is blank for the author.
- [ ] No absolute home/worktree/SDK path or raw session/terminal/task/dispatch
      identifier appears in the report.

## 10. Limitations

- **No measurements here.** This document defines a method; it does not contain
  a baseline result, a detection result, or an estimate. SC-003 is unproven
  until T142 executes this protocol and records actual counts.
- **Action count is a proxy for placement work.** It does not measure effort,
  fatigue, elapsed time, or cognitive load. Elapsed time and navigation may be
  recorded secondarily, but they create no performance claim and cannot replace
  the action comparison.
- **Same-operator design.** Using one operator for both conditions controls
  inter-operator variance but not memory, learning, or fatigue. The 24-hour
  washout, balanced order, and order-effect reporting mitigate but do not
  eliminate these effects.
- **Tool dependence.** The manual baseline is specific to the named tool,
  build, device, and operator; it is not a universal manual-placement constant
  and must not be compared across different tools or builds as if it were.
- **Ground-truth dependence.** The result is only as good as the frozen
  `corpus-1.0.0` GT and metric. Disputed GT fields must be resolved before the
  first scored run, never after seeing results.
- **Quality parity is strict.** Requiring zero false positives and 100% same-
  type/IoU ≥ 0.5 matching in both conditions may invalidate forms that a real
  user would accept with minor differences. That strictness is intentional: it
  prevents a lower-quality assisted layout from producing a lower action count.
- **No runtime evidence from this file.** This file is `NONE`. It cannot prove
  Android behavior, detection quality, export validity, accessibility, or device
  performance.

## 11. Versioning and change control

- This is version `manual-baseline-protocol.v1.0.0`. Its SHA-256 is recorded in
  the T142 run manifest before the first scored form.
- Before the first scored run, a correction that changes the method requires a
  new protocol version and a new run manifest; the previous version is retained
  for audit.
- After the first scored run, any change to this protocol creates a new version
  and a new, separately reported run. Earlier results are never re-scored under
  the new version and are never presented as the same run.
- Editorial corrections that do not change the method still change the file
  hash. If they occur after the run, they are recorded as a new protocol
  version and do not retroactively bind the old run.
- The T142 report must name the protocol version and hash it used. A report that
  cannot be tied to a frozen protocol version is `PARTIAL` at best.

## 12. Compliance map

| Requirement | Where this protocol satisfies it |
| --- | --- |
| D-18 add/move/resize/reclassify comparison | §2.2, §6.1 |
| D-18 same operator and same tool | §3, §4.1 |
| D-18 per-form recording and reduction formula | §6.1, §7.2 |
| D-18 corpus of at least 20 rights-cleared real forms | §2.1, §6.4 |
| SC-003 80% reduction and field-share wording | §6.4 |
| SC-003 "after the user's review" | §2.1 accepted layout, §3.1/§3.2 |
| Constitution Principle IV (frozen corpus, GT, metric) | §4.2, §5.4 |
| Constitution Principle VIII (separated, measured evidence) | §3, §4.3, §6.5, §7 |
| T142 authoritative Android runtime | §3, §7.1 |
| No benchmark manipulation or invented measurements | §4.6, §5.4, §8, §10 |
| No self-approval | §7.4 |

## 13. No-results statement

This file contains no measured manual-baseline values. Any number in a T142
report that is not traceable to a retained action log, a frozen accepted layout,
and the frozen scorer/GT/metric is not a result under this protocol. The first
scored run is T142; until then, SC-003 remains unproven.
