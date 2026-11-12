# Contract: Recognition Output

**Feature**: `001-scanned-form-workflow` | **Package**: `packages/feldexa_recognition` | **Persistence**: suggestions are part of the document revision, encrypted at rest

This contract defines what page analysis produces, how uncertainty is represented, how failures are isolated, and how the output maps to evaluation metrics. Detection is deterministic and geometry-first; OCR is an auxiliary signal (constitution Principle IV).

---

## 1. Envelope

One envelope per page per analysis run.

```json
{
  "schemaVersion": 1,
  "analysisRunId": "8f14e45f-ceea-467f-a2a0-1f2c3d4e5f60",
  "pageIndex": 0,
  "pageSizePt": { "width": 595.28, "height": 841.89 },
  "rotation": 0,
  "status": "complete",
  "pageUncertain": false,
  "uncertaintyReason": null,
  "failure": null,
  "suggestions": [],
  "timings": { "rasterMs": 210, "ocrMs": 1180, "detectMs": 430 },
  "evidenceClass": "emulator"
}
```

| Field | Type | Rules |
| --- | --- | --- |
| `schemaVersion` | int | `1` |
| `analysisRunId` | UUID | one per analysis invocation; all page envelopes of that run share it |
| `pageIndex` | int | valid page, 0-based |
| `pageSizePt` | object | must equal the page display size |
| `rotation` | 0/90/180/270 | from page geometry |
| `status` | `"complete" \| "failed"` | `failed` requires `failure` |
| `pageUncertain` | bool | true when orientation/skew/contrast prevent reliable placement; UI marks the page and relies on user correction |
| `uncertaintyReason` | string? | `skew`, `orientation`, `low_contrast`, `structure`; required when `pageUncertain` is true |
| `failure` | object or null | see §4 |
| `suggestions` | array | may be empty on success; sorted deterministically |
| `timings` | object | integers ≥ 0; diagnostics only, not part of the model hash |
| `evidenceClass` | `simulated \| emulator \| device` | propagated to test reports |

`timings` and `evidenceClass` are excluded from canonical revision hashing and from equality comparisons used by goldens.

---

## 2. Suggestion object

```json
{
  "id": "s_p0_0007",
  "pageIndex": 0,
  "rect": { "x": 148.5, "y": 302.0, "width": 210.0, "height": 14.5 },
  "proposedType": "text",
  "confidence": 0.82,
  "uncertainty": 0.18,
  "labelText": "Name",
  "evidence": {
    "cues": ["underline", "ocr_alignment_right", "keyword_name"],
    "cueAgreement": 3,
    "skewDegrees": 0.4,
    "contrast": "normal",
    "ocrUsed": true
  },
  "conflictsWith": [],
  "resolution": "unresolved"
}
```

| Field | Type | Rules |
| --- | --- | --- |
| `id` | string | `s_p<pageIndex>_<zero-padded ordinal>`; ordinal assigned after deterministic sort; stable for a given run |
| `pageIndex` | int | equals envelope page |
| `rect` | Rect | display-space points; inside page bounds; rounded to 1/8 pt for stability |
| `proposedType` | enum | `text \| number \| date \| checkbox \| multiline \| signature` |
| `confidence` | double | `0.0 … 1.0`, two decimals |
| `uncertainty` | double | `1 − confidence`, two decimals |
| `labelText` | string? | nearest label, trimmed, max 200 chars; null when no label is credible; never logged |
| `evidence.cues` | string[] | closed vocabulary in §3; sorted, unique |
| `evidence.cueAgreement` | int | number of independent cue families supporting the candidate, ≥ 1 |
| `evidence.skewDegrees` | double | estimated page skew, −10…+10 |
| `evidence.contrast` | `"normal" \| "low"` | low contrast caps confidence (see §3.4) |
| `evidence.ocrUsed` | bool | false when OCR failed and geometry-only detection ran |
| `conflictsWith` | string[] | IDs with IoU ≥ 0.5; symmetric; both remain |
| `resolution` | enum | `unresolved \| confirmed \| rejected`; suggestions are persisted with `unresolved`; resolution is stored on the suggestion for audit |

### 2.1 Forbidden outputs

- No suggestion may cover a region whose raster is predominantly printed text (FR-016). A candidate must be predominantly empty background; the detector measures ink density and rejects candidates above 12 % ink coverage unless the cue is a bordered small square (checkbox) or a detected table cell with a printed label outside.
- No suggestion may be generated from OCR text alone. At least one geometric cue (line, box, grid, whitespace, alignment) must be present.
- No suggestion is ever auto-confirmed, auto-exported, or used to overwrite an existing confirmed field.

---

## 3. Cue vocabulary and typing rules

### 3.1 Cues

| Cue | Meaning | Source |
| --- | --- | --- |
| `underline` | horizontal rule directly below a candidate region | raster line detection |
| `box` | closed rectangle enclosing the candidate | raster line detection |
| `grid_cell` | candidate is a cell of a detected table grid | grid detection |
| `whitespace` | bounded empty background region adjacent to printed content | connected components |
| `alignment_left` | candidate left edge aligns with sibling candidates/labels | layout analysis |
| `label_below` | label is directly below the candidate (e.g., signature line) | OCR alignment |
| `ocr_alignment_right` / `ocr_alignment_below` | candidate is to the right of / below an OCR label line | OCR alignment |
| `keyword_<key>` | label lexeme implies a type (closed list below) | OCR label classifier |
| `small_square` | near-square region 4–20 pt with low ink and equal sides | geometry |
| `table_cell` | cell addressable individually within a grid | geometry |
| `signature_area` | large low-ink region labelled as signature | OCR + geometry |
| `numeric_context` | adjacent label/printed pattern implies digits | OCR |
| `date_context` | adjacent label/printed date mask (`TT.MM.JJJJ`) | OCR |

Keyword lexicon v1 (case-insensitive, German, umlaut-normalized for matching, original text preserved for display): `name`, `vorname`, `nachname`, `familienname`, `geburtsdatum`, `geburtsort`, `datum`, `straße`, `strasse`, `hausnummer`, `plz`, `postleitzahl`, `ort`, `wohnort`, `telefon`, `telefax`, `e-mail`, `email`, `iban`, `bic`, `bank`, `konto`, `steuernummer`, `steuer-id`, `aktenzeichen`, `geschäftszeichen`, `antrag`, `betrag`, `summe`, `unterschrift`, `datum/unterschrift`, `monat`, `jahr`, `zeitraum`, `von`, `bis`.

### 3.2 Type inference precedence

1. Explicit closed cue: `small_square` → `checkbox`; `signature_area` → `signature`.
2. Label keyword: date keywords → `date`; numeric keywords (`betrag`, `summe`, `iban`, `steuernummer`, `plz`, `telefon`) → `number` except `plz`/`telefon`, which remain `text` (leading zeros, formatting); signature keywords → `signature`.
3. Geometry: height ≥ 2.2 × single-line median and width ≥ 80 pt → `multiline`; aspect ratio 0.75–1.33 and height ≤ 20 pt → `checkbox`; single-line otherwise.
4. OCR content of an adjacent printed sample (e.g., `TT.MM.JJJJ`) → `date`.
5. Default → `text`.

`date` is never forced on a region labelled `Monat`, `Zeitraum`, `von`, `bis`; those remain `text` so the user is not forced into a fake date (spec assumption).

### 3.3 Confidence model (normative inputs)

```text
base = 0.35
+ 0.12 per supporting cue family, capped at +0.48
+ 0.10 if a credible keyword matches the inferred type
+ 0.05 if geometry is well inside typical bounds for the type
- 0.25 if skewDegrees.abs() > 2.0
- 0.20 if contrast == low
- 0.15 if ocrUsed == false (geometry-only)
+ 0.10 if two independent OCR lines agree on the label
clamp(0.05 … 0.98), round to 2 decimals
```

`uncertainty = 1 − confidence`. Confidence is a UI/priority signal, not a probability claim; no surface may state a success rate from it.

### 3.4 Uncertainty presentation thresholds

| Confidence | UI treatment |
| --- | --- |
| ≥ 0.75 | solid suggestion outline |
| 0.50–0.74 | dashed suggestion outline |
| < 0.50 | dashed outline + "unsicher" badge + explanatory semantics label |

Confidence is never hidden for low-confidence suggestions (FR-083).

### 3.5 Page-level uncertainty

- `pageUncertain = true` when the deskew estimate is unreliable (`|skew| > 5°`, conflicting projections), orientation cannot be determined, contrast is very low despite a successful threshold, or the structure is partially unsupported.
- The page is **not** rotated or re-rendered to correct skew; its original appearance is preserved. Suggestions are placed on the unmodified page image, and the page is flagged in the page strip with a German explanation („Seite unsicher ausgerichtet – bitte Vorschläge prüfen“).
- Users can still confirm, reject, add, move, resize, and fill on an uncertain page (FR-020/FR-030).
- Page-level uncertainty is independent of per-suggestion confidence and never marks the page as failed.

---

## 4. Failure contract

```json
{
  "status": "failed",
  "failure": {
    "category": "ocr",
    "messageKey": "REC-002",
    "recoverable": true,
    "suggestionCount": 4
  }
}
```

| Category | Cause | Behavior |
| --- | --- | --- |
| `rasterization` | page could not be rendered for analysis | page marked failed; other pages unaffected; manual fields allowed |
| `ocr` | OCR engine unavailable/failed | geometry-only detection still runs; envelope may remain `complete` with `ocrUsed: false` and reduced confidence; `failed` only if geometry detection also fails |
| `unsupported_structure` | page is unreadable/damaged or has no analyzable structure | page marked failed with German explanation; manual fields allowed |
| `internal` | unexpected error | page marked failed; diagnostic code only (no content); retry offered |

Rules:
- A page failure never deletes suggestions from other pages (FR-017).
- Partial results on a failed page, if any, are discarded for that page only and reported as `suggestionCount` in the failure object for honesty.
- Failure messages are German and name the page and category, never a file name or content (FR-019/FR-084).
- Page analysis is cancellable; cancellation leaves the page `pending`, not `failed`.

---

## 5. Determinism

1. No randomness, no wall-clock input, no network, no locale-dependent collation.
2. Sort order: page index → rounded `y` → rounded `x` → type ordinal → ID. Ties after all keys are resolved by stable insertion order from the scan (top-left to bottom-right).
3. OCR blocks are sorted by `(roundedTop, roundedLeft)` before alignment matching.
4. Floating-point comparisons use epsilon `1e-6`; rectangles are rounded to 1/8 pt before IDs/conflicts are computed.
5. Same input bytes + same adapter versions + same parameters must produce byte-identical canonical JSON (`analysisRunId`, `timings`, and `evidenceClass` excluded).
6. Golden files are stored per fixture page; changes require an explicit review and a metric re-run note.

---

## 6. Overlap and conflict handling

- Conflict when `IoU(a, b) ≥ 0.5`, or when one rect contains the other's center and their centers are within 4 pt.
- Conflicts are symmetric and recorded in `conflictsWith`.
- Neither candidate is removed, merged, or auto-ranked out. The UI shows both with a conflict badge and requires per-candidate resolution (FR-025).
- Duplicate suppression is limited to exact duplicates (IoU > 0.98 and same type) produced by the same detector pass; such duplicates are collapsed deterministically, and the collapse is logged as a count in diagnostics (never content).

---

## 7. History and confirmed fields

- Confirming a suggestion creates a `ConfirmedField` with `provenance = machine`, `sourceSuggestionId`, and `suggestionConfidence`; the suggestion's `resolution` becomes `confirmed`.
- Rejecting sets `resolution = rejected`; undo restores `unresolved`. Rejected suggestions are excluded from review queues and export.
- Reanalysis generates a new `analysisRunId` and new suggestion IDs. Existing confirmed fields are preserved; new suggestions identical to an existing confirmed field (IoU ≥ 0.8 and same type) are marked `duplicate_of_confirmed` and default to hidden in the review stream, but remain auditable. They are never auto-confirmed.
- Suggestions and their resolution states are persisted in revisions so provenance survives reopening and export planning (Principle IV).

---

## 8. Evaluation mapping

| Metric | Rule |
| --- | --- |
| True positive | a GT field matches exactly one suggestion with `IoU ≥ 0.5` and identical type |
| False positive | suggestion matching no GT field, or a second suggestion matching an already-matched GT field |
| False negative | GT field with no matching suggestion |
| Type accuracy | correct type among matched pairs / matched pairs |
| Position accuracy | mean IoU among matched pairs; separately report the share with `IoU ≥ 0.75` |
| Relevant field | any GT input region in the frozen ground truth |
| Exclusion | none after scoring; excluded pages/forms must be declared before the run with a reason and reduce the reported denominator |

Evaluation uses the **production detector on the authoritative Android runtime**; Web results are `SIMULATED` and cannot feed SC-001. The metric definition version, corpus version, detector parameters, build mode, and device profile are recorded in the report.

---

## 9. Privacy

- `labelText` and OCR-derived labels are document content: encrypted at rest, never logged, never included in diagnostics, never sent anywhere (FR-079/FR-081).
- Timings, counts, cue names, and failure categories are non-sensitive and may appear in on-device diagnostics.
- Page images exist only in memory during analysis and are released after the page completes.
- Fixtures used for browser/unit tests are synthetic or rights-cleared; no real personal form data (Principle VI).
