# Contract: Export Plan and Flattened PDF

**Feature**: `001-scanned-form-workflow` | **Builder**: `packages/feldexa_export` | **Appliers**: `android/export/PdfExportService.kt` (production), `feldexa_adapters_simulated` (Web, `SIMULATED`)

The export plan is the complete, deterministic instruction set for producing the final PDF. It contains no PDF bytes and no platform calls. The Android applier must not make layout decisions; the shared builder must not write PDF operators. This separation is what makes Web layout validation meaningful and the artifact independently verifiable.

---

## 1. Pipeline

```text
confirmed fields + values
        │
        ▼
[1] Preflight validation (shared Dart)
    - unresolved suggestions excluded (provisional pending owner decision OD-1; see §3.4)
    - empty required-nothing policy: empty fields allowed, reported as info
    - type/value compatibility, date/number canonical form
    - geometry inside page bounds
        │
        ▼
[2] Layout (shared Dart, Noto Sans metrics)
    - per-field font size, line breaks, baselines, checkbox mark, signature fit
    - overflow detection → blocking warnings
        │
        ▼
[3] ExportPlan (canonical JSON)
        │
        ▼
[4] Android applier (PDFBox)
    - new PDF, import every original page unchanged
    - append overlay content stream per page under the display CTM
    - flatten pre-existing AcroForm if present
    - write temp, verify, atomic rename
        │
        ▼
[5] Verification (applier + independent external readers)
        │
        ▼
ExportArtifact (succeeded) ──► preview ──► save / share / print ──► delete
```

No artifact is presented before step 5 succeeds (FR-072).

---

## 2. Export plan schema (v1)

```json
{
  "schemaVersion": 1,
  "documentId": "1b4e28ba-2fa1-4d3b-a1f8-6f2a3c4d5e6f",
  "revisionId": "9c858901-8a57-4791-81fe-4c455b099bc9",
  "sourceSha256": "0f343b0931126a20f133d67c2b018a3c…",
  "pageCount": 2,
  "evidenceClass": "emulator",
  "font": {
    "family": "NotoSans",
    "regularAsset": "assets/fonts/NotoSans-Regular.ttf",
    "boldAsset": "assets/fonts/NotoSans-Bold.ttf",
    "metricsVersion": "noto-sans-2.013-v1"
  },
  "pages": [
    {
      "index": 0,
      "rotation": 0,
      "mediaBox": { "x": 0, "y": 0, "width": 595.28, "height": 841.89 },
      "cropBox": { "x": 0, "y": 0, "width": 595.28, "height": 841.89 },
      "displaySize": { "width": 595.28, "height": 841.89 },
      "ctm": { "a": 1, "b": 0, "c": 0, "d": -1, "e": 0, "f": 841.89 },
      "ops": [
        {
          "op": "text",
          "fieldId": "f1",
          "provenance": "machine",
          "rect": { "x": 148.5, "y": 302.0, "width": 210.0, "height": 14.5 },
          "pdfRect": { "x": 148.5, "y": 525.39, "width": 210.0, "height": 14.5 },
          "fontSizePt": 8.7,
          "lineHeightPt": 10.44,
          "baselineFromTopPt": 8.1,
          "color": "#000000",
          "lines": ["Müller-Lüdenscheidt"],
          "overflow": false
        },
        {
          "op": "checkbox",
          "fieldId": "f2",
          "provenance": "user",
          "rect": { "x": 420.0, "y": 210.0, "width": 10.0, "height": 10.0 },
          "pdfRect": { "x": 420.0, "y": 621.89, "width": 10.0, "height": 10.0 },
          "checked": true,
          "insetPt": 1.5,
          "strokeWidthPt": 0.8
        },
        {
          "op": "image",
          "fieldId": "f3",
          "provenance": "template",
          "rect": { "x": 320.0, "y": 720.0, "width": 180.0, "height": 50.0 },
          "pdfRect": { "x": 320.0, "y": 71.89, "width": 180.0, "height": 50.0 },
          "assetId": "d2a1…",
          "fit": "contain",
          "align": "center"
        }
      ]
    }
  ],
  "warnings": [],
  "info": { "emptyFieldCount": 3, "unresolvedSuggestionCount": 2 }
}
```

### 2.1 Page fields

| Field | Rule |
| --- | --- |
| `index` | 0-based, one entry per source page, ascending, no gaps; `pages.length == pageCount` |
| `rotation` | exactly from the stored page |
| `mediaBox`, `cropBox` | PDF user space, from preflight; `cropBox` is the effective visible box |
| `displaySize` | from the page geometry |
| `ctm` | display→PDF matrix from [coordinates-and-geometry.md](./coordinates-and-geometry.md) §5; recomputed and validated by the applier |
| `ops` | deterministic order: by field order; within a field, one op |

### 2.2 Op fields

Every op carries `provenance` (`machine | user | template`) so recognition provenance survives export planning and artifact verification (Principle IV). Provenance is never drawn onto the page and never includes labels.

**text**
| Field | Rule |
| --- | --- |
| `rect` | display points |
| `pdfRect` | display rect mapped to PDF user space; verification only |
| `fontSizePt` | `clamp(0.6 × rect.height, 7.0, 12.0)`, rounded to 0.1 |
| `lineHeightPt` | `1.2 × fontSizePt`, rounded to 0.01 |
| `baselineFromTopPt` | `1.5 + 0.8 × fontSizePt` (approx. ascender), ≤ rect.height |
| `color` | `#000000` only in v1 |
| `lines` | non-empty; single-line has exactly one entry; no trailing spaces; `\n` materialized into entries |
| `overflow` | must be `false`; if true the plan is not produced and export is blocked (`EXP-001`) |

**checkbox**
| Field | Rule |
| --- | --- |
| `checked` | honest boolean; unchecked emits no op or `checked:false` with no drawing (applier must draw nothing) |
| `insetPt` | `0.15 × min(width, height)`, clamped 0.5–3.0 |
| `strokeWidthPt` | `clamp(0.08 × min(width, height), 0.6, 1.4)`, rounded to 0.1 |

**image (signature)**
| Field | Rule |
| --- | --- |
| `assetId` | exists in the same document; referenced by the revision |
| `fit` | `contain` (aspect preserved) |
| `align` | `center` |
| Max scale | 2× the source pixel size at 72 dpi; never upscale beyond that |

### 2.3 Forbidden plan content

- No values for fields that are not confirmed.
- No unconfirmed suggestion content, no OCR text, no page screenshots, no field metadata such as labels beyond what is needed for warnings.
- No absolute file paths, URIs, device names, or user identifiers.
- No interactive widgets or AcroForm field definitions (FR-069).

---

## 3. Layout rules (normative)

### 3.1 Text

- Padding: 1.5 pt on all sides; available width `= rect.width − 3.0`; available height `= rect.height − 3.0`.
- Font: Noto Sans Regular at `fontSizePt`. No bold in v1 (values are user input, not headings).
- Single-line (`text`, `number`, `date`):
  - one line, no wrapping;
  - `number` displays German decimal comma, thousands separators are **not** inserted automatically (avoid surprising formatting);
  - `date` displays `dd.MM.yyyy`;
  - overflow when measured advance width > available width → blocking warning.
- Multiline:
  - explicit `\n` starts a new line;
  - greedy word wrap at spaces; a single word longer than the line is not broken — it overflows and blocks;
  - no hyphenation, no auto-shrink, no truncation, no ellipsis;
  - overflow when `lines.length × lineHeightPt > available height`.
- Trailing spaces at line ends are removed for rendering; interior spaces are preserved. This changes no visible content and is recorded as `trimmedTrailingSpaceCount` in info.
- German characters (`ä ö ü ß € „ “ ’ –`) are measured with the bundled metrics; glyphs missing from Noto Sans cause a blocking `EXP-004` (font coverage) rather than a substitute glyph.
- Vertical alignment: top. Baseline `= rect.y + baselineFromTopPt`, lines advance by `lineHeightPt`.
- Horizontal alignment: left. No centering in v1.

### 3.2 Checkbox

- Unchecked → no mark.
- Checked → two diagonal strokes forming an X between inset corners, round caps, black.
- A field whose type is `checkbox` renders only this mark, regardless of any preserved incompatible text (which must be resolved or explicitly accepted by the user before export).

### 3.3 Signature

- Transparent PNG, ink-trimmed at capture; `contain` fit inside `rect` with 1 pt padding; centered; no rotation beyond the page CTM; no color change.

### 3.4 Empty fields and unresolved suggestions

> **Provisional pending owner decision OD-1.** The unresolved-suggestion behavior below is the
> documented **provisional implementation behavior only**. FR-025 remains binding: the system must
> visibly surface overlapping or conflicting suggestions and must require the user to resolve them.
> No task or test may treat the non-blocking behavior as the settled export policy. The empty-field
> statement is not provisional: empty fields do not block export.

- Empty confirmed fields are allowed. `info.emptyFieldCount` is shown to the user before export ("N Felder sind noch leer") but does not block (spec assumption).
- Unresolved suggestions are **provisionally** excluded from the artifact and counted in `info.unresolvedSuggestionCount`; under the current provisional implementation the user is warned before export and is not blocked. This is not a settled policy (OD-1); FR-025 governs until the owner decides.
- Rejected suggestions and rejected fields never appear.
- Pages marked unreadable are still imported byte-for-byte. If the applier cannot copy such a page, the export is **blocked** with `EXP-006` naming the page; a page is never silently dropped, replaced, or re-rendered (FR-010, spec edge case "Missing or unreadable pages").

---

## 4. Validation and blocking warnings

`PdfExportPort.validate(plan)` (Android) and the shared preflight return the same code set:

| Code | Blocking | German summary | Trigger |
| --- | --- | --- | --- |
| `EXP-001` | yes | „Der Inhalt passt nicht in die Felder …“ | text overflow, signature outside bounds |
| `EXP-002` | yes | „Der Export ist fehlgeschlagen …“ | applier I/O/verification failure |
| `EXP-003` | yes | „Ein Feld liegt außerhalb der Seite …“ | rect outside display bounds > 0.5 pt |
| `EXP-004` | yes | „Ein Zeichen kann nicht dargestellt werden …“ | missing glyph |
| `EXP-005` | yes | „Die Quelldatei ist nicht mehr lesbar …“ | source hash/read failure |
| `EXP-006` | yes | „Seite {page} kann nicht übernommen werden …“ | unreadable page cannot be copied; export blocked instead of dropping it |
| `SAVE-001` | yes | storage message | insufficient space before/during export |

Warning payload includes `fieldId`, `pageIndex`, `fieldLabel`, and a machine `reason` (`too_wide`, `too_many_lines`, `glyph_missing`, …). Labels are user content and must not be logged; they appear only in the blocking dialog and are not included in diagnostics.

---

## 5. Android applier algorithm (PDFBox-Android)

Preconditions: source bytes decrypted in memory (bounded ≤80 MiB), plan validated, free space ≥ `2 × estimatedOutput + 32 MiB`.

1. Load source with `PDDocument.load(byteArray)`; assert page count equals plan and the source is not encrypted.
2. If the source has an `AcroForm` with fields, flatten it **in memory** on the source copy (`PDAcroForm.flatten()`) so existing field appearances become ordinary page content; the stored encrypted source bytes are never modified. Then create a new `PDDocument` and import every source page **unmodified** relative to that flattened working copy:
   - preferred: `PDFMergerUtility.appendDocument(output, source)` to copy pages, resources, and content streams without re-rendering;
   - never rasterize, re-flow, or rebuild pages.
3. Remove any residual field dictionaries or widget annotations from the output and assert `getAcroForm()` is null or empty before adding overlays (FR-069).
4. Embed Noto Sans Regular once per output document (`PDType0Font.load(doc, ttfStream, true)`), subsetting enabled.
5. For each page, for each op in plan order:
   - open `PDPageContentStream(doc, page, AppendMode.APPEND, /*compress*/ true, /*resetContext*/ true)`;
   - `transform(ctm)` with the plan matrix;
   - text: `beginText`, `setFont`, `setNonStrokingColor(0,0,0)`, `setTextMatrix(1,0,0,1, x, y)`, `showText` per line, `endText`; encode with the embedded font;
   - checkbox: `moveTo/lineTo/closePath/stroke` with round caps and the planned stroke width;
   - image: `drawImage` with the fitted rectangle and the decoded signature PNG (`LosslessFactory`).
   - close the stream (writes the `q … Q` wrapper).
6. Remove any document info title/author/subject/source metadata copied from the source; set only `Producer = Feldexa` and `Creator = Feldexa`. This prevents leaking a source document title into the artifact metadata. Write a compact non-sensitive provenance record as XMP/custom metadata `Feldexa/FieldProvenance` containing only `{page, ordinal, provenance}` tuples — no labels, values, or field IDs — so provenance survives the exported artifact itself. The verifier asserts the record exists, matches the plan counts, and contains no user content.
7. Save to `cacheDir/feldexa_exports/<artifactId>.pdf.tmp`; `flush`/close; fsync if supported.
8. **Verify**:
   - reopen the temp file; page count equals source; each page `MediaBox`/`CropBox` equals the plan within 0.01 pt; rotation equals the plan;
   - `document.getDocumentCatalog().getAcroForm()` is null or has zero fields;
   - extract text and assert each planned text value appears with correct German characters (normalized whitespace);
   - assert every op rect lies inside the page display box;
   - assert the source bytes hash still equals `sourceSha256` (source untouched).
9. Atomically rename temp → `<artifactId>.pdf`; fsync the directory; return `ExportResult` with artifact metadata.
10. On any failure: delete temp, leave the source/document untouched, throw `ExportFailedException` (`EXP-002`).

**Determinism**: output bytes need not be byte-identical across engines, but page order, geometry, text content, checkbox states, and signatures must be exact. Tests compare rendered pixels and extracted text, not file hashes.

---

## 6. Verification contract

An export may be reported successful only if all of the following hold:

| Check | Method | Tolerance |
| --- | --- | --- |
| Structural validity | `qpdf --check` (external), PDFBox reload (internal) | must pass |
| Page count and order | PDFBox + external renderer page iteration | exact |
| Page geometry | MediaBox/CropBox/rotation vs preflight | 0.01 pt |
| Original appearance | render source and output page at 150 dpi; masked comparison outside overlay rects | pixel-identical outside overlays |
| Value placement | overlay ink bounding box vs planned rect | ≤ 1 mm at A4 (2.835 pt) |
| Text content | extracted text contains each value with `ä ö ü ß € „ “` intact; multiline order preserved | exact content after whitespace normalization |
| No clipping | no ink outside field rect (except descenders within 0.5 pt) and none outside page | zero clipped values |
| Checkbox states | exactly the intended boxes show a mark; no other box marks | exact |
| Signatures | ink present at the planned rect, aspect preserved | present; no missing signature |
| No interactive controls | no AcroForm fields, no widget annotations | zero |
| Printability | print/`pdftoppm` at 300 dpi on two independent engines without errors | passes |
| Source integrity | SHA-256 of stored source before/after; original picked file unchanged | exact |
| Artifact isolation | failed run leaves no `.pdf` in the artifact location | zero |

Independent external verification commands are in [quickstart.md](../quickstart.md) §7.

---

## 7. Web (`SIMULATED`) applier

- Uses the Dart `pdf` package to compose a preview: each fixture page is rasterized by the real PDFium renderer at 144 dpi, embedded as a page image, overlay ops are drawn at the same display coordinates and font metrics, and every page carries a visible `SIMULATED` watermark plus a footer `SIMULATED – kein Produktions-PDF`.
- The plan and layout code are the same as production; only the applier differs.
- The artifact is reported with `evidenceClass: simulated`; it must never be used for SC-005/SC-006 or any Android acceptance claim.
- The simulated applier must not claim flattening verification, PDFBox compatibility, or print fidelity.

---

## 8. Requirement traceability

| Requirement | Mechanism |
| --- | --- |
| FR-062, FR-063 | plan generated only for confirmed fields; all source pages imported unchanged |
| FR-064 | per-field layout, font size clamp, baseline, 1 mm placement tolerance |
| FR-065 | vector X only for checked boxes; no other marks |
| FR-066 | signature PNG drawn at field position |
| FR-067 | Noto Sans glyph coverage, `\n` line materialization, German character checks |
| FR-068 | blocking `EXP-001` naming fields before any write |
| FR-069 | content-stream flattening, no AcroForm/widgets, self-contained |
| FR-070, FR-071 | preview + SAF save/share/print |
| FR-072 | temp→verify→rename, deletion on failure |
| FR-073 | source hash re-check, document revision untouched |
| FR-037, FR-038 | overflow blocks; no truncation/shrink/omission |
