# Phase 1 Data Model: Scanned Form to Completed PDF Workflow

**Feature**: `001-scanned-form-workflow` | **Date**: 2026-11-12 | **Plan**: [plan.md](./plan.md) | **Contracts**: [contracts/](./contracts/)

This model is UI-independent: `feldexa_core` has no Flutter widget, rendering, file-system, or platform imports. Every entity is immutable-by-convention with explicit copy methods, JSON-serializable, and versioned. All persistence is encrypted (see [contracts/storage-format.md](./contracts/storage-format.md)); the JSON below describes plaintext structure inside the encrypted container and must never be written to logs.

Coordinate types (`Rect`, `Size`, `Point`) are defined in [contracts/coordinates-and-geometry.md](./contracts/coordinates-and-geometry.md): PDF points, origin top-left of the page display box, y-axis down, after `/Rotate`.

---

## 1. Aggregate overview

```text
Document (aggregate root) 1 ── * Page
                          1 ── * ConfirmedField ── 0..1 FieldValue
                          1 ── * SignatureMark
                          1 ── 1 SourceFileRef
                          1 ── * FieldSuggestion        (analysis output, pre-confirmation)
                          1 ── * Revision (durable history)
                          0..1 TemplateOrigin ── 1 TemplateVersion

Template (aggregate root) 1 ── * Page
                          1 ── * ConfirmedField (layout only, no values)
                          1 ── * TemplateVersion

StoredItem (read-model for the start list) = DocumentSummary | TemplateSummary

ExportArtifact (transient, per export attempt)
OperationRecord (transient, per long-running operation)
EvaluationRecord (tooling only, never in app storage)
```

**Aggregate invariants**
1. A `Document` never mutates `SourceFileRef` or its encrypted source object (FR-004/FR-096).
2. `Template` contains zero `FieldValue`s and zero `SignatureMark`s (FR-057/SC-013).
3. `Document.templateOrigin` pins an immutable `TemplateVersion.id`; new template versions never re-point existing documents (FR-104).
4. A `FieldSuggestion` is never treated as a `ConfirmedField` and never contributes export content (FR-015).
5. A `Document` in `ImportRejected` state has no stored record; rejection happens before aggregate creation (FR-009).
6. Page content is immutable. Printed values already present in a scanned form are page content: the app never edits, removes, or claims to recognize them as its own values, and user values are overlays only (spec edge case "Pre-filled scanned forms", FR-096).
7. Ordering values are unique and contiguous per document/template after normalization; ties are broken by page index then reading order.

---

## 2. Core value objects

### 2.1 `PageGeometry`

| Field | Type | Rules |
| --- | --- | --- |
| `mediaBox` | `Rect` | PDF user space, points; `width > 0`, `height > 0` |
| `cropBox` | `Rect` | Intersection with `mediaBox`; defaults to `mediaBox` |
| `rotation` | `int` | Exactly `0`, `90`, `180`, or `270` |
| `displaySize` | `Size` | Derived: `rotation ∈ {0,180} ? (cropW, cropH) : (cropH, cropW)` |

Invariant: all stored field rectangles are within `[0,0,displaySize.width,displaySize.height]`. A rectangle outside by more than 0.5 pt is a validation error; clamping is never silent.

### 2.2 `Rect`, `Size`, `Point`

- Double precision, points, rounded to 3 decimals only at serialization.
- `Rect` requires `width > 0`, `height > 0`, finite coordinates.
- Minimum interactive render size is a UI concern; the model accepts small rectangles (e.g., 6 pt checkboxes).

### 2.3 `FieldType`

`text | number | date | checkbox | multiline | signature`

Type-specific rules:
- `text`: free text, German characters allowed, line breaks removed.
- `number`: German decimal input, optional thousands separators, stored normalized with `.` decimal; no exponent.
- `date`: canonical storage `YYYY-MM-DD`; display/input `dd.MM.yyyy`; only real calendar dates; leading zeros optional on input (FR-107/FR-108).
- `checkbox`: boolean only.
- `multiline`: text with preserved `\n`; trailing whitespace trimmed per line on commit.
- `signature`: reference to a `SignatureMark`; no text value.

### 2.4 `Provenance`

`machine | user | template`

- `machine`: came from a suggestion and was confirmed; keeps `suggestionConfidence`.
- `user`: created manually by the user.
- `template`: inherited from the pinned template version.
Provenance survives save, reopen, template derivation, and export planning (Principle IV).

### 2.5 `DurabilityStatus`

`clean | saving | unsaved(risk) | saved | saveFailed(errorCode) | recoveryFallback(revisionId)`

`clean` means no changes since the last durable state; `saved` means a verified commit completed at `lastDurableAt`. Only `saved`/`clean` may be presented as durable.

---

## 3. Entities

### 3.1 `Document`

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `schemaVersion` | `int` | yes | starts at `1`; migrations explicit |
| `id` | `String` | yes | UUIDv4, generated by secure RNG |
| `kind` | `"document"` | yes | discriminator |
| `title` | `String` | yes | default from source filename without extension, user-renamable; 1–200 chars |
| `createdAt` / `updatedAt` | `DateTime` (UTC) | yes | ISO-8601 ms precision |
| `source` | `SourceFileRef` | yes | immutable encrypted source |
| `pages` | `List<Page>` | yes | length ≥ 1 |
| `suggestions` | `List<FieldSuggestion>` | yes | may be empty; not part of confirmed structure |
| `fields` | `List<ConfirmedField>` | yes | may be empty; export uses only these |
| `fieldOrder` | `List<String>` | yes | field IDs in user-visible order |
| `values` | `Map<String, FieldValue>` | yes | keyed by confirmed field ID |
| `signatures` | `Map<String, SignatureMark>` | yes | keyed by field ID; at most one per signature field |
| `verification` | `Map<String, FieldVerification>` | yes | per-field confirmed/validated state and warnings |
| `templateOrigin` | `TemplateOrigin?` | no | template ID + pinned version ID + version number |
| `lastDurable` | `DurablePointer` | yes | revision ID, timestamp, SHA-256 |
| `preferences` | `DocumentPreferences` | yes | zoom preference, current page, review order mode |
| `status` | `DocumentStatus` | derived | never persisted as an optimistic claim |

**Validation**
- At most one value per confirmed field; no value for a field not in `fields`.
- `fieldOrder` is a permutation of `fields` IDs after normalization (all IDs present exactly once).
- `pages.length` equals preflight page count.
- `title` is non-empty after trimming; control characters rejected.
- Signature asset IDs must be unique within the document.

**Derived read-model `DocumentSummary`**: `id`, `title`, `updatedAt`, `stateLabel` (`Neu`, `In Bearbeitung`, `Exportbereit`, `Gespeichert`, `Nicht lesbar`), `fieldCount`, `filledCount`, `thumbnailRef?` (none in v1 to avoid plaintext thumbnails; list uses a generic icon), `durability` (`saved`/`unsaved`).

**State machine — document lifecycle**

```text
(no record) --import validated--> Draft
Draft --autosave/save verified--> Saved
Saved --committed edit--> Dirty
Dirty --autosave/save verified--> Saved
Dirty --save failed--> SaveFailed --retry--> Dirty
Saved/Dirty --export verified--> ExportReady (status label only; no data change)
any readable state --source/key unreadable--> Unreadable (isolated; no deletion)
any state --user delete confirmed--> Deleted (record removed)
```

`Unreadable` is per document and never transitions other documents. `ExportReady` is a derived label, not a stored state.

### 3.2 `SourceFileRef`

| Field | Type | Rules |
| --- | --- | --- |
| `id` | `String` | UUIDv4; names the encrypted source object |
| `sha256` | `String` | 64 lowercase hex chars of the original bytes |
| `sizeBytes` | `int` | 1 … 83,886,080 (80 MiB) |
| `pageCount` | `int` | 1 … 100 |
| `originalName` | `String?` | display only; never logged; ≤ 255 chars; may be cleared by user |
| `importedAt` | `DateTime` | UTC |
| `integrity` | `"verified" \| "unreadable"` | set after read-back verification |

### 3.3 `Page`

| Field | Type | Rules |
| --- | --- | --- |
| `index` | `int` | 0-based, contiguous, stable for document lifetime |
| `geometry` | `PageGeometry` | from preflight |
| `analysis` | `AnalysisState` | `pending \| running \| complete \| failed` |
| `failure` | `PageFailure?` | required iff `analysis == failed` |
| `unreadable` | `bool` | page content could not be decoded at import |
| `renderCacheKey` | `String?` | derived, not persisted content |

**State machine — page analysis**

```text
pending --start--> running --success--> complete
running --failure--> failed(category, messageKey)
failed --retry--> running
complete --reanalysis--> running
```

A page failure never removes suggestions from other pages (FR-017). A `failed` page is still renderable and manually editable (FR-018/FR-020).

### 3.4 `FieldSuggestion`

| Field | Type | Rules |
| --- | --- | --- |
| `id` | `String` | deterministic within a run: `s_<page>_<ordinal>`; stable until reanalysis |
| `pageIndex` | `int` | valid page |
| `rect` | `Rect` | within page display bounds |
| `proposedType` | `FieldType` | no `signature` unless matched to signature cues; allowed |
| `confidence` | `double` | `0.0 … 1.0`; uncertainty = `1 − confidence` |
| `labelText` | `String?` | nearest label, trimmed, ≤ 200 chars; encrypted at rest, never logged |
| `evidence` | `SuggestionEvidence` | cue flags + source (`line`, `box`, `grid`, `whitespace`, `ocr_alignment`, `keyword`) |
| `conflictsWith` | `List<String>` | IDs with IoU ≥ 0.5; both remain resolvable |
| `resolution` | `unresolved \| confirmed \| rejected` | `rejected` is reversible |

**State machine — suggestion resolution**

```text
unresolved --confirm--> confirmed (creates ConfirmedField, provenance=machine)
unresolved --reject--> rejected
rejected --undo--> unresolved
confirmed --undo--> unresolved (removes the generated field if untouched)
```

Confirmation copies geometry/type; later field edits do not rewrite the suggestion record (audit trail). Reanalysis creates a new suggestion set; previously confirmed fields are never removed automatically.

### 3.5 `ConfirmedField`

| Field | Type | Rules |
| --- | --- | --- |
| `id` | `String` | UUIDv4 (or deterministic template field ID) |
| `pageIndex` | `int` | valid |
| `rect` | `Rect` | within page bounds |
| `type` | `FieldType` | current type |
| `provenance` | `Provenance` | `machine \| user \| template` |
| `sourceSuggestionId` | `String?` | required iff `provenance == machine` |
| `suggestionConfidence` | `double?` | required iff machine |
| `label` | `String` | user-visible name; default from suggestion label or `Feld <n>`; 1–120 chars; German characters preserved |
| `order` | `int` | ≥ 0; normalized contiguous |
| `createdAt` / `updatedAt` | `DateTime` | UTC |
| `validation` | `FieldValidation` | `ok \| warning(code, messageKey) \| error(code)` |

**Reclassification rules (FR-029)**
- `text ⇄ multiline`: content preserved; line breaks preserved for multiline, joined with spaces when moving to text only after explicit user confirmation; otherwise flagged.
- `text → number/date`: content preserved but marked `error` if it does not parse under the new type; value is not discarded.
- `number/date → text`: content preserved, error cleared.
- `text/number/date → checkbox`: existing content preserved in a separate `incompatibleContent` field and flagged; export uses the checkbox state only after the user resolves the warning.
- `→ signature`: text content flagged as incompatible; checkbox state cleared.
- Warnings never auto-delete content (FR-038).

### 3.6 `FieldValue`

Tagged union on `type`:

| Variant | Payload | Rules |
| --- | --- | --- |
| `TextValue` | `String text` | ≤ 10,000 chars; no control chars except `\n` in multiline |
| `NumberValue` | `String canonical`, `String rawGerman` | canonical matches `-?\d+(\.\d+)?`; raw kept for display |
| `DateValue` | `String canonical` (`YYYY-MM-DD`) | must be a real calendar date |
| `CheckboxValue` | `bool checked` | default `false` |
| `MultilineValue` | `String text` | `\n` preserved; ≤ 10,000 chars |
| `SignatureValue` | `String signatureAssetId` | points to a `SignatureMark` |
| `IncompatibleValue` | `String preservedText`, `String reasonCode` | keeps content after an incompatible reclassification |

Every value carries `lastEditedAt` and `overflow: bool` (derived at layout time, stored for status display). Overflow never alters content.

**Validation timing**: value validation runs on commit to the model (not per keystroke) and again before export. Invalid date/number is rejected at the control level with the German message and is never stored (FR-108/SC-022).

### 3.7 `SignatureMark`

| Field | Type | Rules |
| --- | --- | --- |
| `assetId` | `String` | UUIDv4; encrypted PNG object in the same document |
| `fieldId` | `String` | must reference a `signature` field |
| `pageIndex` | `int` | same page as the field |
| `rect` | `Rect` | ink bounds in page display points |
| `widthPx` / `heightPx` | `int` | ≤ 1024 on long edge; > 0 |
| `capturedAt` | `DateTime` | UTC |
| `sha256` | `String` | plaintext PNG hash for integrity |

Not reusable across documents (FR-036); template creation excludes it (FR-057). Deleting the field deletes its signature asset after the next verified commit.

### 3.8 `FieldVerification`

| Field | Type | Rules |
| --- | --- | --- |
| `state` | `unreviewed \| confirmed \| corrected \| rejected` | per confirmed field |
| `reviewedAt` | `DateTime?` | required for confirmed/corrected |
| `warnings` | `List<WarningCode>` | e.g., `overflow`, `incompatible_content`, `low_confidence`, `conflict` |

### 3.9 `TemplateOrigin`

| Field | Type | Rules |
| --- | --- | --- |
| `templateId` | `String` | exists at creation |
| `templateVersionId` | `String` | immutable; pinned forever |
| `templateVersionNumber` | `int` | ≥ 1, display only |

### 3.10 `Template`

| Field | Type | Rules |
| --- | --- | --- |
| `schemaVersion` | `int` | `1` |
| `id` | `String` | UUIDv4 |
| `kind` | `"template"` | discriminator |
| `title` | `String` | 1–200 chars |
| `createdAt` / `updatedAt` | `DateTime` | UTC |
| `source` | `SourceFileRef` | immutable encrypted original pages |
| `pages` | `List<Page>` | same geometry rules; no analysis state requirement |
| `fields` | `List<ConfirmedField>` | layout only; `provenance` may be `template` |
| `fieldOrder` | `List<String>` | permutation |
| `latestVersion` | `TemplateVersionPointer` | version ID + number + timestamp |
| `versions` | `List<TemplateVersionPointer>` | newest first; at least 1 |

**Invariants**: zero values, zero signatures, zero text content beyond field labels. Saving template changes writes a new immutable version; existing versions are never modified (FR-103/FR-104). `TemplateVersion` content = pages (source ref) + field definitions + order + schema version. Creating a document from a template **copies** the template's encrypted source into the new document's own source object; a derived document never references template storage, so deleting the template or any of its versions cannot break derived documents (FR-059/FR-060/FR-099). New documents always use the template's latest version (FR-105).

### 3.11 `TemplateVersion`

| Field | Type | Rules |
| --- | --- | --- |
| `id` | `String` | UUIDv4 |
| `templateId` | `String` | parent |
| `versionNumber` | `int` | 1-based, strictly increasing |
| `createdAt` | `DateTime` | UTC |
| `fieldSnapshot` | `List<ConfirmedField>` | no values |
| `pageSnapshot` | `List<Page>` | geometry + source refs |
| `sha256` | `String` | hash of canonical plaintext JSON |

### 3.12 `Revision`

| Field | Type | Rules |
| --- | --- | --- |
| `id` | `String` | UUIDv4 |
| `documentId` | `String` | parent |
| `parentRevisionId` | `String?` | null for first revision |
| `kind` | `autosave \| explicit \| recovery` | provenance of the commit |
| `createdAt` | `DateTime` | UTC |
| `plaintextSha256` | `String` | verified before head update |
| `content` | `{pages, suggestions, fields, fieldOrder, values, signatures, verification, templateOrigin}` | full snapshot, no source bytes |

Retention: keep last 3 autosave revisions + the newest explicit revision + a recovery revision if present; pruning only after a verified commit.

### 3.13 `DurablePointer`

`revisionId`, `parentRevisionId?`, `kind`, `committedAt`, `sha256`, `verifyReadBack: true`.

### 3.14 `EditCommand` and `CommandHistory` (transient)

| Field | Type | Rules |
| --- | --- | --- |
| `id` | `String` | UUIDv4 |
| `kind` | enum | `addField \| removeField \| move \| resize \| reclassify \| setValue \| confirmSuggestion \| rejectSuggestion \| reorder \| addSignature \| removeSignature` |
| `fieldId` | `String?` | required for field-scoped commands |
| `before` / `after` | canonical JSON | only the affected sub-state; values and geometry only |
| `at` | `DateTime` | UTC, from `ClockPort` |
| `merged` | `bool` | true when coalesced with the previous command of the same kind/field within 500 ms (drag/resize/typing) |

`CommandHistory` keeps bounded undo/redo stacks (100 commands) per open document. Undo/redo mutates only the in-memory model and marks it dirty; autosave persists the result. It never bypasses validation.

**Durable restore (FR-027)**: the user can open the saved revision history (last 3 autosaves + newest explicit save). Selecting an older revision loads it as a **preview** without modifying the current head; confirming „Diesen Stand wiederherstellen“ writes a new revision whose parent is the current head and whose `kind` is `recovery`. The newer revisions remain on disk until normal pruning; nothing is deleted as part of restore.

### 3.15 `ExportArtifact`

| Field | Type | Rules |
| --- | --- | --- |
| `id` | `String` | UUIDv4 |
| `documentId` | `String` | parent |
| `revisionId` | `String` | revision exported |
| `state` | `validating \| rendering \| verifying \| succeeded \| failed` | optimistic states forbidden |
| `pageCount` | `int?` | compared with source before success |
| `byteSize` | `int?` | > 0 on success |
| `sha256` | `String?` | output hash |
| `verification` | `ArtifactVerification?` | page count, media boxes, font/glyph check, no form fields, overlay bounds |
| `failureCode` | `String?` | e.g., `EXP-001`, `EXP-002`, `SAVE-001` |
| `createdAt` | `DateTime` | UTC |

A failed artifact is deleted before the operation reports failure in the place a successful artifact would occupy (`EXP-002`).

**State machine — export**

```text
idle --start--> validating
validating --overflow/errors--> blocked (German message; no artifact)
validating --ok--> rendering
rendering --io/key/space failure--> failed (temp removed)
rendering --ok--> verifying
verifying --mismatch--> failed (artifact removed)
verifying --ok--> succeeded (preview available)
succeeded --preview dismissed/delivered--> deleted
```

### 3.16 `FieldSuggestionSet` (analysis output envelope)

`pageIndex`, `analysisRunId`, `status`, `pageUncertain`, `uncertaintyReason?`, `failure?`, `suggestions[]`, `timings {rasterMs, ocrMs, detectMs}`, `evidenceClass`. See [contracts/recognition-output.md](./contracts/recognition-output.md).

### 3.17 `OperationRecord` (transient)

`operationId`, `kind` (`import | analyze | save | export | delete`), `startedAt`, `finishedAt?`, `result` (`success | failure | cancelled`), `code?`, `progress` (0..1). Never persisted; drives UI and German messages. Must not include document content.

### 3.18 `RecognitionEvaluationRecord` (tooling only)

`metricDefinitionVersion`, `corpusVersion`, `formId`, `deviceProfile`, `buildMode`, `conditions`, `tp`, `fp`, `fn`, `precision`, `recall`, `typeAccuracy`, `meanPositionIoU`, `perField[]`, `manualBaseline` (where measured), `timestamp`. Stored under `tools/evaluation/reports/`, never in app storage; contains no personal data.

---

## 4. Storage mapping

| Entity | Location | Mutability |
| --- | --- | --- |
| `Document` metadata | `docs/<id>/meta.fx1` | mutable via atomic replace |
| Revision snapshot | `docs/<id>/rev/<revisionId>.fx1` | immutable |
| Head pointer | `docs/<id>/head.fx1` | atomic replace |
| Source PDF | `docs/<id>/src/<sourceId>.fxc` | immutable after import |
| Signature PNG | `docs/<id>/sig/<assetId>.fxs` | immutable |
| `Template` metadata | `templates/<id>/meta.fx1` | atomic replace |
| Template version | `templates/<id>/ver/<versionId>.fx1` | immutable |
| Head pointer | `templates/<id>/head.fx1` | atomic replace |
| Export artifact | `cacheDir/feldexa_exports/<id>.pdf.tmp` → `<id>.pdf` | ephemeral, swept |
| Diagnostics | `filesDir/diagnostics/redacted.jsonl` | redacted, size-capped, optional |

The start list reads only `meta.fx1` files (documents and templates in separate directories) plus their heads; it never decrypts source PDFs or revision bodies.

---

## 5. Cross-cutting validation rules

| Rule | Source |
| --- | --- |
| Every confirmed field's page exists and rectangle lies inside display bounds | FR-014/FR-024 |
| Field order is a permutation of field IDs; unique, contiguous | FR-026 |
| Values exist only for confirmed fields and match the field's type or are flagged incompatible | FR-029/FR-038 |
| Signatures exist only for signature fields of the same document/page | FR-036 |
| Templates contain no values/signatures and at least one version | FR-057/FR-102 |
| Derived documents pin an existing immutable template version | FR-104 |
| Imported source hash and size match `SourceFileRef` at open; mismatch → `SAVE-002`/`IMP-002` isolated | FR-096 |
| Date values are real calendar dates in canonical form | FR-107/FR-108 |
| Export plan contains only confirmed fields with exportable values | FR-062/FR-063 |
| No entity stores a device pixel coordinate or a cached plaintext path | Principle V |
| Schema versions are monotonic; unknown newer version → `SAVE-005` (app too old) without data loss | FR-044 |

---

## 6. Serialization and migration

- Canonical JSON: sorted object keys, UTF-8, no insignificant whitespace, ISO-8601 UTC timestamps; SHA-256 is computed over canonical bytes.
- `schemaVersion` is per aggregate root. Readers accept `1`; a reader encountering a higher version refuses to save and shows a German message, leaving the data untouched.
- Migration functions are pure Dart, unit-tested with golden fixtures for v1 and any future version; migrations run inside a new revision, never in place.
- Unknown JSON fields are preserved on read/write rounds only within the same schema version (forward-compatibility guard) and dropped on migration with a recorded warning.

---

## 7. Determinism requirements

- IDs in production come from a secure RNG; tests and fixtures inject a deterministic `IdGenerator`.
- Suggestion IDs are derived from page and ordering, not random, so golden analysis output is stable.
- Timestamps come from `ClockPort`; tests use a fixed clock.
- Selection, conflict detection, and ordering use stable sorts with explicit tie-breakers (page index, y, x, ID).
- No map iteration order may affect serialized output or UI ordering; lists are canonicalized before hashing or display.
