# Font-advance metrics (T007)

`metrics.json` is the generated, deterministic advance table for the bundled
Noto Sans Regular/Bold static TTFs. `feldexa_export` uses it to lay out values
and detect clipping in Dart without measuring text through Flutter, Android, or
PDFBox (plan.md §Architecture Decisions 6; research.md D-11; FR-064,
FR-067, FR-068).

This is a host build tool. It produces no rendering, `SIMULATED`, `EMULATOR`,
or `DEVICE` evidence. T030 owns the later `feldexa_export` contract test and
PDFBox parity; T103/T108 own the export layout and clip verification.

## Regenerate and verify

```sh
# Rewrite apps/feldexa_app/assets/fonts/metrics.json from the bundled TTFs:
dart run tools/metrics/generate_font_metrics.dart

# Fail unless the committed file is byte-for-byte current:
dart run tools/metrics/generate_font_metrics.dart --check

# Independent cross-check of the committed JSON against the TTF bytes:
cd apps/feldexa_app && flutter test --no-pub test/font_metrics_bundle_test.dart
```

The generator is fail-closed. It verifies the T006 SHA-256 pins for both TTFs,
rejects variable/CFF fonts, requires the FR-067 German codepoint coverage, and
refuses to emit a document when a required font table is malformed.

## Schema version 1

Top level:

| Field | Meaning |
| --- | --- |
| `schemaVersion` | `1`; bump for an incompatible shape change |
| `metricsVersion` | `noto-sans-2.013-v1`, the value used by `contracts/export-plan.md` §2 |
| `family` | `NotoSans` (contract family) |
| `fontRelease` | `NotoSans-v2.013` (T006 pinned release) |
| `unitsPerEm` | Shared design units per em (1000) |
| `fonts` | Object keyed by weight (`"400"`, `"700"`) |

Per font:

| Field | Meaning |
| --- | --- |
| `style`, `weight` | `regular`/400 and `bold`/700 |
| `asset` | Bundled TTF path from the export-plan contract |
| `sha256`, `bytes` | SHA-256 and byte length of that exact TTF |
| `unitsPerEm`, `glyphCount`, `numberOfHMetrics`, `advanceWidthMax` | Raw `head`/`maxp`/`hhea` values |
| `ascender`, `descender`, `lineGap` | `hhea` horizontal metrics in design units |
| `typoAscender`, `typoDescender`, `typoLineGap`, `winAscent`, `winDescent`, `xHeight`, `capHeight` | `OS/2` metrics; `null` only when the table/version does not expose them |
| `cmapFormat` | Unicode cmap subtable format used (`12` for this bundle) |
| `codepointCount`, `firstCodepoint`, `lastCodepoint` | Coverage bounds of `advances` |
| `advances` | Object mapping decimal Unicode codepoint (`"228"`) to advance width in design units |

## Semantics

- A text width in points is
  `sum(advances[codepoint] for codepoint in text.runes) * fontSizePt / unitsPerEm`.
  Iterate Unicode code points (`runes`), not UTF-16 code units.
- The key's presence means the bundled font has a Unicode cmap entry for that
  code point; its value is the `hmtx` advance. A **missing key is a font
  coverage failure** (`EXP-004`), not a zero width. Zero-valued keys are real
  zero-advance glyphs such as combining marks.
- The table contains every codepoint mapped by the font's Unicode cmap, which
  is broader than the FR-067 German subset.
- Schema v1 carries no kerning or ligature adjustments. Plain advance sums are
  intentional for parity with PDFBox `getStringWidth`; adding shaping later
  requires a new `metricsVersion` and an explicit contract change.
- `lineHeightPt` and `baselineFromTopPt` remain the export-plan contract's
  proportions (`1.2 × fontSizePt`, `1.5 + 0.8 × fontSizePt`). The raw
  ascender/descender/line-gap values are exposed so later layout work can
  justify or revise those proportions with evidence.
