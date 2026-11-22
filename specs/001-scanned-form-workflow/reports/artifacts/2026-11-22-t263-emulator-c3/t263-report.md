# T263 German OCR qualification

- Suite: `de-ocr-1.0.0` (`sf-005`), reference PDF sha256 `671dd6b8b30cd46910e1bab5e0c7a69cfbb5d22efe0000520a25108f38e08e45`
- Metric definition: `metric-definition.v1`
- Raw-text normalization: none
- Overall verdict: **FAIL**
  - reference variant clean-200dpi is FAIL: CER 2.33% exceeds the pre-declared ceiling 2.00%; special-character recall 93.27% is below the pre-declared floor 100.00%; 5 critical line(s) are not exactly recognised; 1 reference field(s) have no credible label; uncertainty is kept instead of forcing a type; label accuracy 76.92% on the reference variant is not 100 %

| Variant | Evidence | Status | CER | Special P | Special R | Field P | Field R | Type acc. | Unresolved labels |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| clean-200dpi | EMULATOR | FAIL | 2.33 | 97.98 | 93.27 | 17.81 | 100.00 | 23.08 | 1 |
| clean-150dpi | EMULATOR | PASS | 2.21 | 98.98 | 93.27 | 17.81 | 100.00 | 23.08 | 1 |
| clean-300dpi | EMULATOR | PASS | 2.27 | 97.96 | 92.31 | 17.81 | 100.00 | 23.08 | 1 |
| scan-150dpi-low-contrast | EMULATOR_INJECTED_RASTER | PASS | 2.21 | 99.01 | 96.15 | 25.49 | 100.00 | 76.92 | 1 |
| scan-200dpi-shadow | EMULATOR_INJECTED_RASTER | PASS | 2.63 | 97.96 | 92.31 | 13.13 | 100.00 | 23.08 | 1 |
| scan-200dpi-skew-3deg | EMULATOR_INJECTED_RASTER | FAIL | 43.51 | 66.33 | 62.50 | 0.37 | 7.69 | 100.00 | 0 |
| scan-200dpi-jpeg-q35 | EMULATOR_INJECTED_RASTER | PASS | 2.27 | 97.98 | 93.27 | 15.66 | 100.00 | 23.08 | 1 |

## clean-200dpi

Clean reference render at the fixed 200 DPI analysis scale over the production raster and OCR ports; this is the reference variant for both raw text and semantic assignment.

Raw: 51/51 lines associated, 39 exact, 18 substitutions, 17 deletions, 4 insertions, CER 2.33.

Critical lines that are not exact (UNRESOLVED):

- `p0-l07`: expected `Ä Ö Ü ä ö ü ß ẞ`, observed `ÄÖüä ö üßB
- `p0-l08`: expected `Ärger Öffnung Übung Äußerst`, observed `Ärger Öffnung Übung Ảußerst
- `p0-l12`: expected `Gebühr: 12,50 € · Fläche: 45 m² · Raum: 7 m³`, observed `Gebühr: 12,50 €· Fläche: 45 m² Raum: 7 m
- `p0-l13`: expected `„Deutsch“ – Gedankenstrich — Auslassung … § 5`, observed `„Deutsch" - Gedankenstrich– Auslassung ... S5
- `p0-l22`: expected `Zeichen: ẞ ß Ä Ö Ü ä ö ü € m² m³`, observed `Zeichen: BBÄÖÜä ö ü € m² m²

Special-character confusion matrix:

| Expected | Observed | Kind | Count |
| --- | --- | --- | --- |
|   | ü | substitution | 1 |
| ³ | ∅ | deletion | 1 |
| ³ | ² | substitution | 1 |
| Ä | Ả | substitution | 1 |
| Ü | ∅ | deletion | 1 |
| ß | B | substitution | 1 |
| ẞ | B | substitution | 1 |
| ẞ | ∅ | deletion | 1 |

Semantic: 13/13 fields with a matching label, 1 unresolved label(s), 0 forced-type violation(s), 0 non-verbatim label(s) (0 not comparable: recorded OCR raster differs from the analysis raster), 0 auto-resolved suggestion(s).

## clean-150dpi

Raw OCR capture at 150 DPI through the production raster and OCR ports. The semantic pipeline keeps its fixed 200 DPI analysis raster, so this variant qualifies the DPI effect on raw text only.

Raw: 51/51 lines associated, 41 exact, 19 substitutions, 17 deletions, 1 insertions, CER 2.21.

Critical lines that are not exact (UNRESOLVED):

- `p0-l07`: expected `Ä Ö Ü ä ö ü ß ẞ`, observed `ÄÖüä ö üßB
- `p0-l12`: expected `Gebühr: 12,50 € · Fläche: 45 m² · Raum: 7 m³`, observed `Gebühr: 12,50 €· Fläche: 45 m² Raum: 7 m?
- `p0-l13`: expected `„Deutsch“ – Gedankenstrich — Auslassung … § 5`, observed `„Deutsch" - Gedankenstrich– Auslassung ... S5
- `p0-l21`: expected `MÜLLER-GRÄBER, SCHRÖDER-WEISS, BÄUERLE, ÖHMICHEN`, observed `MÜLLER-GRÄBER, SCHRÖDER-WEISS, BÂUERLE, ÖHMICHEN
- `p0-l22`: expected `Zeichen: ẞ ß Ä Ö Ü ä ö ü € m² m³`, observed `Zeichen: BBÄÖÜä ö ü € m² m

Special-character confusion matrix:

| Expected | Observed | Kind | Count |
| --- | --- | --- | --- |
|   | ü | substitution | 1 |
| ³ | ? | substitution | 1 |
| ³ | ∅ | deletion | 1 |
| Ä | Â | substitution | 1 |
| Ü | ∅ | deletion | 1 |
| ß | B | substitution | 1 |
| ẞ | B | substitution | 1 |
| ẞ | ∅ | deletion | 1 |

Semantic: 13/13 fields with a matching label, 1 unresolved label(s), 0 forced-type violation(s), 0 non-verbatim label(s) (2 not comparable: recorded OCR raster differs from the analysis raster), 0 auto-resolved suggestion(s).

## clean-300dpi

Raw OCR capture at 300 DPI through the production raster and OCR ports. The semantic pipeline keeps its fixed 200 DPI analysis raster, so this variant qualifies the DPI effect on raw text only.

Raw: 51/51 lines associated, 40 exact, 19 substitutions, 18 deletions, 1 insertions, CER 2.27.

Critical lines that are not exact (UNRESOLVED):

- `p0-l07`: expected `Ä Ö Ü ä ö ü ß ẞ`, observed `Ä Öüäö üßB
- `p0-l08`: expected `Ärger Öffnung Übung Äußerst`, observed `Ärger Öfnung Übung Äußerst
- `p0-l12`: expected `Gebühr: 12,50 € · Fläche: 45 m² · Raum: 7 m³`, observed `Gebühr: 12,50 € · Fläche: 45 m² Raum: 7 m²
- `p0-l13`: expected `„Deutsch“ – Gedankenstrich — Auslassung … § 5`, observed `„Deutsch" - Gedankenstrich - Auslassung ... S5
- `p0-l22`: expected `Zeichen: ẞ ß Ä Ö Ü ä ö ü € m² m³`, observed `Zeichen: BBÄÖÜ ä ö ü € m m
- `p1-l23`: expected `Beispiel: Müller-Gräber, Äußere Straße 12, 8 m²`, observed `Beispiel: Müller-Gräber, Äußere Straße 12, 8 m?

Special-character confusion matrix:

| Expected | Observed | Kind | Count |
| --- | --- | --- | --- |
|   | ü | substitution | 1 |
| ² | ? | substitution | 1 |
| ² | ∅ | deletion | 1 |
| ³ | ∅ | deletion | 1 |
| ³ | ² | substitution | 1 |
| Ü | ∅ | deletion | 1 |
| ß | B | substitution | 1 |
| ẞ | B | substitution | 1 |
| ẞ | ∅ | deletion | 1 |

Semantic: 13/13 fields with a matching label, 1 unresolved label(s), 0 forced-type violation(s), 0 non-verbatim label(s) (2 not comparable: recorded OCR raster differs from the analysis raster), 0 auto-resolved suggestion(s).

## scan-150dpi-low-contrast

150 DPI scan with reduced contrast and a light gray wash.

Raw: 51/51 lines associated, 42 exact, 21 substitutions, 16 deletions, 0 insertions, CER 2.21.

Critical lines that are not exact (UNRESOLVED):

- `p0-l07`: expected `Ä Ö Ü ä ö ü ß ẞ`, observed `ÄÖÜä ö üßB
- `p0-l12`: expected `Gebühr: 12,50 € · Fläche: 45 m² · Raum: 7 m³`, observed `Gebühr: 12,50 €· Fläche: 45 m² Raum: 7 m²
- `p0-l13`: expected `„Deutsch“ – Gedankenstrich — Auslassung … § 5`, observed `„Deutsch" - Gedankenstrich– Auslassung... S5
- `p0-l22`: expected `Zeichen: ẞ ß Ä Ö Ü ä ö ü € m² m³`, observed `Zeichen: BBÄÖÜä ö ü€ m² m³

Special-character confusion matrix:

| Expected | Observed | Kind | Count |
| --- | --- | --- | --- |
| ³ | ² | substitution | 1 |
| ß | B | substitution | 1 |
| ẞ | B | substitution | 1 |
| ẞ | ∅ | deletion | 1 |

Semantic: 13/13 fields with a matching label, 1 unresolved label(s), 0 forced-type violation(s), 0 non-verbatim label(s) (0 not comparable: recorded OCR raster differs from the analysis raster), 0 auto-resolved suggestion(s).

## scan-200dpi-shadow

200 DPI scan with a soft page shadow in one corner.

Raw: 51/51 lines associated, 38 exact, 21 substitutions, 22 deletions, 1 insertions, CER 2.63.

Critical lines that are not exact (UNRESOLVED):

- `p0-l07`: expected `Ä Ö Ü ä ö ü ß ẞ`, observed `ÄÖüäöüßB
- `p0-l08`: expected `Ärger Öffnung Übung Äußerst`, observed `Ärger Öfnung Übung Äußerst
- `p0-l10`: expected `Straße Größe Äußerung`, observed `Straße Größe Åußerung
- `p0-l12`: expected `Gebühr: 12,50 € · Fläche: 45 m² · Raum: 7 m³`, observed `Gebühr: 12,50 € Fläche: 45 m² Raum: 7 m²
- `p0-l13`: expected `„Deutsch“ – Gedankenstrich — Auslassung … § 5`, observed `„Deutsch" - Gedankenstrich– Auslassung ... S5
- `p0-l20`: expected `Jürgen Mühlbach, Bärbel Süßbier, Käthe Gröhnert, Matthäus Ölmüller`, observed `Jürgen Mühlbach, Bärbel SüBbier, Käthe Gröhnert, Matthäus Ölmüller
- `p0-l22`: expected `Zeichen: ẞ ß Ä Ö Ü ä ö ü € m² m³`, observed `Zeichen: BBÄÖÜä ö ü€ m² m

Special-character confusion matrix:

| Expected | Observed | Kind | Count |
| --- | --- | --- | --- |
| ß | B | substitution | 2 |
|   | ü | substitution | 1 |
| ³ | ∅ | deletion | 1 |
| ³ | ² | substitution | 1 |
| Ä | Å | substitution | 1 |
| Ü | ∅ | deletion | 1 |
| ẞ | B | substitution | 1 |
| ẞ | ∅ | deletion | 1 |

Semantic: 13/13 fields with a matching label, 1 unresolved label(s), 0 forced-type violation(s), 0 non-verbatim label(s) (0 not comparable: recorded OCR raster differs from the analysis raster), 0 auto-resolved suggestion(s).

## scan-200dpi-skew-3deg

200 DPI scan rotated by three degrees about the page centre on a white background.

Raw: 30/51 lines associated, 19 exact, 35 substitutions, 354 deletions, 339 insertions, CER 43.51.

Critical lines that are not exact (UNRESOLVED):

- `p0-l07`: expected `Ä Ö Ü ä ö ü ß ẞ`, observed `<no line associated>
- `p0-l08`: expected `Ärger Öffnung Übung Äußerst`, observed `Ärger Öfnung Übung Äußerst
- `p0-l12`: expected `Gebühr: 12,50 € · Fläche: 45 m² · Raum: 7 m³`, observed `Gebühr: 12,50 €· Fläche: 45 m² Raum: 7 m²
- `p0-l13`: expected `„Deutsch“ – Gedankenstrich — Auslassung … § 5`, observed `„Deutsch" - Gedankenstrich– Auslassung ... S5
- `p0-l15`: expected `Straße und Hausnummer`, observed `<no line associated>
- `p0-l18`: expected `Rückumschlag, Äußerung, Antragstellung, Bürgerdienste`, observed `Rückumschlag, Außerung, Antragstellung, Bürgerdienste
- `p0-l22`: expected `Zeichen: ẞ ß Ä Ö Ü ä ö ü € m² m³`, observed `<no line associated>
- `p1-l23`: expected `Beispiel: Müller-Gräber, Äußere Straße 12, 8 m²`, observed `Beispiel: Müller-Gräber, Äußere Straße 12, 8 m?

Special-character confusion matrix:

| Expected | Observed | Kind | Count |
| --- | --- | --- | --- |
| ∅ | ü | insertion | 8 |
| ü | ∅ | deletion | 7 |
| ß | ∅ | deletion | 6 |
| ∅ | ß | insertion | 5 |
| ∅ | ä | insertion | 5 |
| ä | ∅ | deletion | 5 |
| ∅ | ö | insertion | 4 |
| ö | ∅ | deletion | 4 |
| ∅ | Ä | insertion | 3 |
| Ä | ∅ | deletion | 3 |
| Ü | ∅ | deletion | 3 |
| ∅ | Ö | insertion | 2 |
| ∅ | Ü | insertion | 2 |
| ∅ | € | insertion | 2 |
| Ö | ∅ | deletion | 2 |
| ẞ | ∅ | deletion | 2 |
| € | ∅ | deletion | 2 |
| ∅ | ² | insertion | 1 |
| ² | ? | substitution | 1 |
| ² | ∅ | deletion | 1 |

Semantic: 1/13 fields with a matching label, 0 unresolved label(s), 0 forced-type violation(s), 0 non-verbatim label(s) (0 not comparable: recorded OCR raster differs from the analysis raster), 0 auto-resolved suggestion(s).

## scan-200dpi-jpeg-q35

200 DPI scan compressed as a low-quality JPEG and decoded back to gray8.

Raw: 51/51 lines associated, 40 exact, 17 substitutions, 19 deletions, 2 insertions, CER 2.27.

Critical lines that are not exact (UNRESOLVED):

- `p0-l07`: expected `Ä Ö Ü ä ö ü ß ẞ`, observed `Ä ÖÜä ö üßB
- `p0-l08`: expected `Ärger Öffnung Übung Äußerst`, observed `Ärger Öfnung Übung Äußerst
- `p0-l12`: expected `Gebühr: 12,50 € · Fläche: 45 m² · Raum: 7 m³`, observed `Gebühr: 12,50 € Fläche: 45 m² Raum: 7 m²
- `p0-l13`: expected `„Deutsch“ – Gedankenstrich — Auslassung … § 5`, observed `„Deutsch" - Gedankenstrich– Auslassung ... §5
- `p0-l20`: expected `Jürgen Mühlbach, Bärbel Süßbier, Käthe Gröhnert, Matthäus Ölmüller`, observed `Jürgen Mühlbach, Bärbel SüBbier, Käthe Gröhnert, Matthäus Ölmüller
- `p0-l22`: expected `Zeichen: ẞ ß Ä Ö Ü ä ö ü € m² m³`, observed `Zeichen: BBÄÖÜ ä ö ü€ m m²

Special-character confusion matrix:

| Expected | Observed | Kind | Count |
| --- | --- | --- | --- |
| ³ | ² | substitution | 2 |
| ß | B | substitution | 2 |
| ² | ∅ | deletion | 1 |
| ẞ | B | substitution | 1 |
| ẞ | ∅ | deletion | 1 |

Semantic: 13/13 fields with a matching label, 1 unresolved label(s), 0 forced-type violation(s), 0 non-verbatim label(s) (0 not comparable: recorded OCR raster differs from the analysis raster), 0 auto-resolved suggestion(s).

An UNRESOLVED case is reported as unresolved and never counted as an accuracy PASS.
