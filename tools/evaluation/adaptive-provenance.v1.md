# Adaptive variant provenance v1.0.0 — frozen before any adaptive run

| Field | Value |
| --- | --- |
| Artifact | `tools/evaluation/adaptive-provenance.v1.json` |
| Status | `frozen-before-run`; implementation **BLOCKED** |
| Task / issue | T264P / [#264](https://github.com/xxammaxx/Feldexa_2.0/issues/264) |
| Prerequisite for | T264C (adaptive pass), T264D (benchmark) |
| Consumes | `tools/evaluation/adaptive-policy.v1.json` (hash-bound, never edited) |
| Evidence class | `NONE` (contract text only; no runtime behaviour, no raster measured) |
| Contract test | `tools/evaluation/test_adaptive_provenance.py` |

## 1. What this file decides

An adaptive second pass analyses a *variant* of the same page, and the tempting
error is to treat two variants as two independent pieces of evidence. They are
not: `clean-200dpi` plus a contrast stretch of it are the same pixels, and
`scan-200dpi-shadow` plus `scan-200dpi-jpeg-q35` are one capture twice.

Every variant therefore declares `derivedFrom`, a `correlationGroup`, and
`independent`. Correlated variants share one evidence slot, so
`twoIndependentOcrLinesAgree` stays `false` for every same-rendering pair.

## 2. Groups (one rendering = one group)

| Group | Rendering | Members | Representative |
| --- | --- | --- | --- |
| `group-pdfium-200` | production PDFium, 200 DPI | `clean-200dpi`, `contrastStretch-200dpi`, `deskew-200dpi` | `clean-200dpi` |
| `group-pdfium-150` | production PDFium, 150 DPI | `clean-150dpi` | `clean-150dpi` |
| `group-pdfium-300` | production PDFium, 300 DPI | `clean-300dpi` | `clean-300dpi` |
| `group-poppler-150` | host Poppler capture, 150 DPI upsampled to the 200 DPI grid | `scan-150dpi-low-contrast` | `scan-150dpi-low-contrast` |
| `group-poppler-200` | host Poppler capture, 200 DPI | `scan-200dpi-shadow`, `scan-200dpi-skew-3deg`, `scan-200dpi-jpeg-q35` | `scan-200dpi-shadow` |

Two traps the table settles:

* **scaling.** `scan-150dpi-low-contrast` is delivered on the same 200 DPI grid as
  the reference, but its pixel source is a 150 DPI capture that was upsampled.
  Upsampling restores the grid, not the resolution, so the variant stays in its
  own group and never becomes a second 200 DPI rendering.
* **different DPI is not the same rendering.** `clean-150dpi`/`clean-300dpi` are
  separate renderings and therefore separate raster-level groups — but they are
  still the same document (§4).

## 3. Counting rule for T264C

```
independentGroups = |{ correlationGroup(v) : v selected }|
```

* `decisionRule.minIndependentGroups = 2`, and an agreement claim needs at least
  that many distinct groups;
* at most one observation per correlation group
  (`maxObservationsPerCorrelationGroup = 1`), so repeating a group adds nothing;
* fewer than two groups is reported as *correlation-limited*: no
  `twoIndependentOcrLinesAgree`, no independent-OCR confidence bonus, no
  auto-confirmation, and no extra pass justified by the repeat alone;
* a variant whose raster hash is `PENDING_RUN`, or whose `derivedFrom` does not
  resolve, produces no evidence row at all (fail-closed).

## 4. Glyph-level collapse

All nine variants render `reference-de` (`sf-005`, SHA-256
`671dd6b8b30cd46910e1bab5e0c7a69cfbb5d22efe0000520a25108f38e08e45`). A character
the font, the encoding, or the bundled model cannot produce fails in every
variant, so a special-character, umlaut, currency, or content claim has exactly
**one** independent group per document, whatever the raster-level group count
says. This is the same conclusion T263 reached from measurement: the residual
`ß`/`ẞ`/`m³`/`§` losses are model limits, not variant noise.

## 5. Hash binding

Per variant: `sourceDocumentSha256` (the PDF, recomputed by the contract test),
`sourceRasterSha256`, and `variantRasterSha256`. The two raster hashes are
`null` + `PENDING_RUN` because no variant raster is committed; they are recorded
when the first run produces the bytes, and nothing is filled in from memory or
from a later re-render.

## 6. What this file does not do

No trigger, threshold, hysteresis value, pass/time/memory bound, or A/B/C
acceptance value is set or changed here — those stay in
`tools/evaluation/adaptive-policy.v1.json`, which is bound by hash. No
implementation exists. No glyph, DPI, or SC claim is made: SC-001/SC-003 remain
with T142, and SC-004 with T136/T141.

`NOT_RUN`: adaptive implementation, cross-pass merge and `SuggestionSchema`
bump, A/B/C benchmark with correlated-group counting, every raster hash, Android
`EMULATOR` evidence for the adaptive path.
