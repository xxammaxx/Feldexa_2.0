# T105 — export-artifact verification harness (complete)

**Date**: 2026-11-27 · **Candidate**: `6963a64` (main) · **Evidence class**: `NONE` (host tooling)
**Supersedes**: `reports/2026-11-27-t105-harness.md` (partial, qpdf/MuPDF absent)

## Tools present

- `qpdf` **12.4.2** (`/usr/bin/qpdf`)
- `mutool` (MuPDF) **1.28.5** (`/usr/bin/mutool`)
- Poppler (`pdfinfo`, `pdftotext`, `pdftoppm`), Python 3 stdlib

## Harness coverage (`tools/pdf_verify/verify_artifact.py`)

| §6 row | Implementation |
| --- | --- |
| Structural validity | `qpdf --check`, exit 0 = PASS |
| Page count and order | `pdfinfo` counts + page-size sequence (order proxy; uniform pages disclosed) |
| Page geometry | per-page MediaBox size and rotation ≤ 0.01 pt |
| Original appearance | source vs artifact rendered at 72 dpi; pixel-identical outside `masks` |
| Value placement | `pdftotext -bbox` word box inside rect + 1 mm, ascent ≤ 0.61 mm (Q3=B) |
| Text content | extraction + German glyphs + expected values |
| No clipping | every word box inside the page; expected values inside rect + 1 mm |
| Checkbox states | rendered ink-density comparison against the source inside the mark rect |
| Signatures | same rendered comparison, `expected: marked` |
| No interactive controls | `/AcroForm` + `/Widget` bytes + `pdfinfo Form:` |
| Printability | Poppler and MuPDF render every page at 300 dpi |
| Source integrity | SHA-256 of the source vs `--source-sha256` |
| Artifact isolation | task-owned (T108/T334 driver), reported `NOT_RUN` |

## Evidence

Committed pair `tools/corpus/synthetic/sf-001.pdf` + `export-artifact-1.pdf`, with the
committed expectations `reports/artifacts/2026-11-26-t344-export-proof-depth/expectations-artifact-1.json`
(rect and value from the T344 placement record):

Command and receipt:

```
python3 tools/pdf_verify/verify_artifact.py \
  --source tools/corpus/synthetic/sf-001.pdf \
  --artifact specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t344-export-proof-depth/export-artifact-1.pdf \
  --expectations specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t344-export-proof-depth/expectations-artifact-1.json \
  --source-sha256 "$(sha256sum tools/corpus/synthetic/sf-001.pdf | cut -d' ' -f1)"
```

**10 PASS, 0 FAIL, 3 NOT_RUN** (checkbox/signature expectations absent for this artifact;
artifact isolation task-owned), exit 0. Without the expectations file: **7 PASS, 0 FAIL,
6 NOT_RUN** (appearance/placement/no-clipping/marks cannot be judged without rects).

Unit tests: `tools/pdf_verify/test_verify_artifact.py` — **17/17 PASS**, including the
qpdf/mutool availability branches, the expectations-enabled appearance/clipping/placement
run, PPM/ink helpers, a synthetic mark PASS/FAIL pair and the 13-row inventory.

## Disposition

- **T105 closed**: the independent harness uses qpdf, Poppler and MuPDF and reports the
  §6 rows with real tool output.
- **T109 stays open**: the Android test must still assert checkbox states and signatures
  and cite this harness; the mark comparison is implemented but unexercised by the current
  artifact.
- No product code changed.
