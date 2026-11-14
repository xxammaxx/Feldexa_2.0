# T019 Contract Correction — Persisted Parse Errors and Validation Extensions

| Field | Value |
| --- | --- |
| Repository | `Feldexa_2.0` |
| Task / issue | T019 review corrections (follow-up to issue #19), reviewing `b90c767` |
| Evidence class | `NONE` (static analysis and host-VM tests only) |
| Result | `PASS` for the correction scope; no runtime or acceptance evidence claimed |
| Date / timezone | 2026-11-14 22:27 Europe/Berlin |
| Base revision | `b90c767138ee949b2932a1c0a8a8e04e4c7aa922` (reviewed T019 candidate) |
| Candidate revision | recorded in the external attestation (`worker_done`); deliberately not asserted in this report |
| Branch | local worker worktree; not pushed, merged, or self-reviewed |
| Tree state | correction files, this report/index row; the pre-existing `apps/feldexa_app/android/gradlew.bat` modification is preserved and not committed |
| Build identity | pure Dart package; no app APK or Web build produced |
| Toolchain | Flutter `3.47.7` (framework `abaf9c5237`), Dart `3.13.5` |
| Input | `data-model.md` §3.5–§3.6, §5, and §6; FR-029, FR-038, FR-108, FR-110; `contracts/export-plan.md` §3.2 and §4; `contracts/error-catalog.de.md` §2; the review findings against `b90c767` |

This report supersedes the persisted-error/warning section of
`2026-11-14-t019-evidence.md`. That report remains the historical record for
`b90c767`; it is deliberately not rewritten.

## 1. Review findings and normative check

Two review findings were reported against `b90c767` and both were checked
against the normative documents.

### 1.1 Finding A — persisted parse-error status

`data-model.md` §3.5 requires an **`error`** status when text moved to
number/date does not parse. `b90c767` stored `FieldValidation.warning`
(`incompatible_content`, `FLD-002`) and exposed `NUM-001`/`DATE-001`/`DATE-002`
only in the transient result. `Document` and `RevisionContent` required the
warning for every `IncompatibleValue`, so the normative error state could not be
persisted.

### 1.2 Finding B — validation extensions dropped

`data-model.md` §6 requires unknown same-schema JSON fields to be preserved on
read/write rounds and dropped only on migration with a recorded warning.
`b90c767` replaced `FieldValidation` in the lossless-conversion and
preserved-content paths without carrying the previous validation's
`unknownFields`, so extensions on `ConfirmedField.validation` were lost on an
ordinary reclassification even though field-level and value-level extensions
were already preserved.

### 1.3 Normative check

| Source | Requirement | Consequence |
| --- | --- | --- |
| `data-model.md` §3.5 field table | `validation` is `ok \| warning(code, messageKey) \| error(code)` | A persisted field can carry a blocking error. |
| `data-model.md` §3.5 reclassification rules | text → number/date content that does not parse is "marked `error`"; number/date → text "error cleared" | The parse failure is a persisted field error, and moving back to text clears it. |
| `data-model.md` §3.5 checkbox rule | content is "flagged" until the user resolves the warning | Checkbox, signature, and line-join cases use the `incompatible_content` warning. |
| `data-model.md` §3.6 `IncompatibleValue` | keeps content after an incompatible reclassification | Parse-failure content is preserved as `IncompatibleValue`, not as an invalid `NumberValue`/`DateValue`. |
| `data-model.md` §3.6 validation timing | invalid date/number is rejected at the control level and never stored as a typed value | Preserving the old content as `IncompatibleValue` does not store an invalid typed value. |
| `data-model.md` §5 | values match the field type **or are flagged incompatible** | A blocking field error is a flag; the strict warning-only pairing is not stated. |
| `data-model.md` §6 | unknown same-schema JSON fields survive read/write; dropped only on migration with a recorded warning | A reclassification is an ordinary edit, so the replaced validation must carry its opaque extensions. |
| FR-029 / FR-038 | incompatible content is flagged, never silently discarded | Both the warning and the error may flag preserved content; an unflagged value remains invalid. |
| `contracts/export-plan.md` §3.2 and §4 | preserved checkbox text must be resolved or explicitly accepted; blocking warnings stop export | The flag must be persisted so export can block. `FieldValidation.error` is blocking by definition. |
| `contracts/error-catalog.de.md` §2 | `NUM-001`, `DATE-001`, `DATE-002` are the number/date failures; `FLD-002` is the type-change incompatibility message | The parse failure persists its type-specific code; the pending-resolution case persists `FLD-002`. |

**Verdict: both findings confirmed.**

1. `reclassification.dart` persisted `FLD-002` for a parse failure instead of
   the required blocking `NUM-001`/`DATE-001`/`DATE-002`.
2. The T017 `Document` and T020 `RevisionContent` invariants rejected the only
   state that satisfies §3.5 (`IncompatibleValue` plus a blocking field error),
   so even a corrected producer could not persist the normative state.
3. The validation replacement lost `FieldValidation.unknownFields`, contrary to
   §6, while the field and value extensions were preserved.

The warning-only invariant was an implementation constraint, not a normative
requirement. The fix removes that over-strict constraint and does not add a new
entity, field, type, or additional invariant. The extension carry is a §6
preservation rule, not a new invariant.

## 2. Reproduction before the fix

The correction tests were written first. Against `b90c767` they failed exactly
as the reviews predicted:

- Finding A: the parse-failure assertions failed with `Expected: true` /
  `Actual: false` for `field.validation.isError`; constructing a `Document` with
  an `IncompatibleValue` and `FieldValidation.error('NUM-001')` threw
  `Invalid argument(s): incompatible content and its incompatible_content warning must occur together`;
  no `Document` or `RevisionContent` round-trip could preserve the required
  error and its content.
- Finding B: the extension tests failed with
  `Expected: {'future.validation': 'kept'}` / `Actual: {}`. The loss occurred in
  the lossless-conversion path and the preserved-content path, which created a
  fresh `FieldValidation` without the previous `unknownFields`.

The old state was therefore internally consistent but normatively wrong for
both findings.

## 3. Fix

### 3.1 Persisted parse error (Finding A)

`reclassification.dart` now persists the validation state required by §3.5:

- a failed text/multiline → number parse stores
  `FieldValidation.error('NUM-001')`;
- a failed text/multiline → date parse stores
  `FieldValidation.error('DATE-001')` or `FieldValidation.error('DATE-002')`;
- checkbox preservation, signature preservation, line-break confirmation, and
  non-representable control content keep
  `FieldValidation.warning(WarningCode.incompatibleContent, 'FLD-002')`;
- a successful number/date → text or multiline conversion still clears a
  previous error, and `resolve()` clears either flag explicitly.

`ReclassificationResult.errorCode` remains a convenience mirror of the
persisted `FieldValidation.errorCode`; tests assert that the two are equal.

`Document` and `RevisionContent` now accept an `IncompatibleValue` when the
field is flagged by **either** the `incompatible_content` warning **or** a
blocking `FieldValidation.error`. The anti-silent-loss rules remain:

- an `IncompatibleValue` with `FieldValidation.ok` or an unrelated warning
  (for example `overflow`) is still rejected;
- an `incompatible_content` warning without an `IncompatibleValue` is still
  rejected;
- a value whose type does not match the field and is not an
  `IncompatibleValue` is still rejected.

No new invariant was introduced. The aggregate deliberately does not narrow
which error codes may flag preserved content: `data-model.md` §3.5 defines
`error(code)` as a blocking validation state and leaves code semantics to the
producer; T019 produces only the three documented parse codes.

### 3.2 Validation extensions (Finding B)

Every reclassification validation replacement now carries the previous state's
opaque `unknownFields` onto the new state:

- warning and error replacements use the public constructors' extension
  parameter;
- the valid state is reconstructed with the modeled `status` plus the opaque
  entries because `data-model.md` §3.5 has no separate constructor for an
  extended `ok`; the modeled keys win and no second validator type is added;
- an already-valid replacement returns the previous `ok` object unchanged.

The carry is applied in `_converted` (lossless conversion, empty content, and
cleared states), `_preserved` (warning/error preservation), `_validationAfter`
(the overflow-warning path, `_clearedSignature`, `_clearedCheckbox`, and
`resolve`). A same-type no-op returns the field unchanged and therefore keeps
its validation untouched.

The proposed values created for an explicit resolution also carry the source
value's `unknownFields`: the line-break join, the checkbox `Ja`/`Nein`
projection, and the proposed unchecked checkbox. Field-level extensions were
already preserved by `ConfirmedField.copyWith`; value-level extensions on
conversion and preservation were already preserved; validation extensions and
resolution proposals are now covered by the same rule.

### 3.3 “Separate incompatibleContent field”

`data-model.md` §3.5 describes checkbox content as preserved in a "separate
`incompatibleContent` field". The canonical core model represents that separate
preserved content as `IncompatibleValue` (`data-model.md` §3.6), not as a second
value slot. Neither review reported a defect in that representation, and this
correction does not reshape the entity. The checkbox warning and the proposed
unchecked state remain unchanged.

## 4. Persistence round-trip

The correction adds explicit round-trip coverage for the actual persistence
path:

1. `Document` with `FieldValidation.error('NUM-001')` and
   `IncompatibleValue('keine Zahl')`;
2. `Document.toJson` → `Document.fromJson` preserves the error code, the
   preserved text, the absence of a warning, and validation extensions;
3. `RevisionContent.fromDocument` → `RevisionContent.toJson` →
   `RevisionContent.fromJson` preserves the same state;
4. the same round-trip is covered for `DATE-002`;
5. the `FLD-002` warning path (checkbox content) still round-trips with the
   preserved value and extensions;
6. `resolve()` clears the error and the preserved value, keeps the validation
   extensions, and the cleared state round-trips;
7. `resolve()` for a line-break join, a checkbox projection, or a proposed
   checkbox keeps the source value's extensions, including through the
   `Document` round-trip.

## 5. What changed

| File | Change | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `packages/feldexa_core/lib/src/model/reclassification.dart` | Persists `NUM-001`/`DATE-001`/`DATE-002` as blocking field errors; carries validation and proposed-value extensions on every replacement; corrects the module documentation | 37659 | `98755c8a80466537b80446d958ad07b987b4c5a30e5d91a7df2a400a4833de74` |
| `packages/feldexa_core/test/reclassification_test.dart` | Adds proof-first contract and extension tests, Document/Revision round-trips, and updates parse-failure expectations | 52665 | `4af36cf7dd5aadd718008fea36ce134c452bca946c024f7c036369a96a25d141` |
| `packages/feldexa_core/lib/src/model/document.dart` | Accepts a blocking field error as the incompatible-content flag; keeps rejecting unflagged content and warnings without content | 60453 | `a523e4b71ffef392efa7bc327f14fb463cfe3ac600bed9a1f4702f0c36e224f9` |
| `packages/feldexa_core/lib/src/model/persistence.dart` | The same reconciliation for `RevisionContent`; documentation updated | 35443 | `b91edd5983ac3fc982536f336ef04828146c3f596b94ff69652b622ecccde027` |
| `packages/feldexa_core/lib/src/model/field.dart` | Documentation only: `acceptsValue` now names both flags; behavior unchanged | 100907 | `709f6e5603108240f0f7a3148d5b0e2414ffb3368c4693bb258d5fde1d50fbe6` |
| `specs/001-scanned-form-workflow/reports/README.md` | Adds this correction report to the index | 18968 | `9b23772c46979bcf47bec40c4e553d747bf07b8cfea0b19aa1032da6b1a2d889` |

This report's own byte size and SHA-256 are omitted by construction; they are
recorded in the external attestation. The pre-existing `gradlew.bat` modification
remains uncommitted and outside the correction.

## 6. Checks and results

All commands ran in the repository root. Exit code 0 is a pass. Logs are
git-ignored, regenerable support artifacts under
`.dart_tool/t019-correction-logs/`; they are not part of the candidate.

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `check-prerequisites.sh --json --require-tasks --include-tasks` (repo root, scoped feature directory) | 0 | `.dart_tool/t019-correction-logs/00-prereq.log` | PASS |
| 2 | `dart format --output=none --set-exit-if-changed .` (repo root) | 0 | `.dart_tool/t019-correction-logs/01-format.log` | PASS, 70 files, 0 changed |
| 3 | `flutter analyze --no-pub` (repo root) | 0 | `.dart_tool/t019-correction-logs/02-analyze.log` | PASS, `No issues found!` |
| 4 | `flutter test --no-pub packages/feldexa_core` (repo root) | 0 | `.dart_tool/t019-correction-logs/03-core-tests.log` | PASS, 461/461 |
| 5 | `git diff --check` (repo root) | 0 | `.dart_tool/t019-correction-logs/04-diff-check.log` | PASS, no whitespace errors |
| 6 | `sha256sum pubspec.lock` versus `git show HEAD:pubspec.lock` (repo root) | 0 | `.dart_tool/t019-correction-logs/05-lockfile.log` | PASS, byte-identical |

The reviewed candidate had 445 passing core tests. This correction adds sixteen
net tests and keeps all previous tests green: 461/461 pass, none skipped or
marked expected-failure. The full workspace analysis passes. No app, browser,
Android, emulator, or device test was run; the correction changes a pure Dart
model and its aggregate invariants.

### Retained local logs

These are git-ignored, regenerable support artifacts under `.dart_tool/`; the
candidate does not contain them.

| Log | Bytes | SHA-256 |
| --- | ---: | --- |
| `.dart_tool/t019-correction-logs/00-prereq.log` | 192 | `fe51d029eeeeccdccd8236a401a3b15c9eadf0f66b577e2ac6bc5aa303549e08` |
| `.dart_tool/t019-correction-logs/01-format.log` | 48 | `d61f98992727f81c91a63e70f09a6005ae299314efa6136f388c3eae04701335` |
| `.dart_tool/t019-correction-logs/02-analyze.log` | 96 | `59d00c5304b0e2f9e901347fd2e82129576a16c1e64b0629ac7af5f045774967` |
| `.dart_tool/t019-correction-logs/03-core-tests.log` | 84375 | `073e23f50f0223cb4af747aea3b2cbbf177bd217c1594502f55810dab39f78ab` |
| `.dart_tool/t019-correction-logs/04-diff-check.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `.dart_tool/t019-correction-logs/05-lockfile.log` | 148 | `881f94c2003a590934b496dcb2745b17aba374491def66e6d355ae43050c7c23` |

## 7. Limitations

- This is host-VM and static-analysis evidence only (`NONE`). It cannot prove
  Android runtime behavior, filling controls, export planning, persistence
  encryption, or device acceptance.
- T066 (reclassify command), T022 (export plan), and the review/fill UI are not
  implemented in this candidate. They must consume the persisted
  `FieldValidation.error`/`FLD-002` states and block export accordingly.
- No Android host, platform channel, storage, UI, export, or application file
  was changed. Android remains the product-truth platform for later runtime
  gates.
- The aggregate accepts any blocking `FieldValidation.error` as the flag for an
  `IncompatibleValue`; it does not semantically validate the error code. This is
  deliberate: the aggregate enforces "no unflagged incompatible content", while
  the producer owns which error code applies. T019 produces only `NUM-001`,
  `DATE-001`, and `DATE-002`.
- The validation-extension carry preserves opaque entries across a state change.
  The mapped validation state always wins; extension keys that collide with
  modeled keys are not expected because `unknownJsonFields` excludes modeled
  keys by construction.
- The second review is still running independently. This report is an author
  record, not a review verdict and not a self-review.
- The pre-existing `gradlew.bat` modification remains uncommitted and is not
  covered by any correction claim.

## 8. Reproducibility

1. Check out base revision
   `b90c767138ee949b2932a1c0a8a8e04e4c7aa922`.
2. Use the Flutter `3.47.7` / Dart `3.13.5` toolchain with a populated Pub cache
   and a writable local shim.
3. Run `dart format --output=none --set-exit-if-changed .`; expect 0 changed.
4. Run `flutter analyze --no-pub`; expect `No issues found!`.
5. Run `flutter test --no-pub packages/feldexa_core`; expect 461 passing tests.
6. Inspect the parse-failure result: `field.validation` is
   `FieldValidation.error('NUM-001'|'DATE-001'|'DATE-002')`, the value is an
   `IncompatibleValue` with the exact content, and no warning is set.
7. Attach a same-schema extension to the field validation, reclassify, and
   inspect the result: the mapped state wins but the extension entries remain.
8. Build a `Document`, serialize and reopen it, then capture `RevisionContent`
   and serialize/reopen it; the error code, preserved content, and validation
   extensions must survive.
9. Reclassify the same field to text or call `resolve`; the error and the
   preserved value must be cleared explicitly, never automatically.

## 9. Review

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
| — | — | — | Author record only; the independent second review remains external and is not claimed here. |
