# T335 — Vorschlagsinventar `sf-001` (Neumessung 2026-11-27, maschinenlesbar erzeugt)

Erzeugt aus `suggestions.json` durch `tools/evaluation/t335_suggestion_inventory.dart`;
diese Markdown-Datei ist eine Ableitung derselben Zahlen, keine zweite Quelle.

- Basis: `origin/main` = `5aa93cf` (enthält `a12afc9`); Erstlauf-Stand: `../2026-11-26-t335/` (Basis `8196e04`)
- Fixture: `sf-001` (2 Seiten, `apps/feldexa_app/assets/fixtures/sf-001.pdf`, SHA-256 `22c939cc…a038`)
- Evidenzklasse: NONE (host: productive stage on a Poppler raster with committed fixture OCR)
- Klassifikationsregel: `{"realFieldIou": 0.5, "printedContentShare": 0.5, "samePlaceIou": 0.9, "categories": ["real_field", "duplicate_field", "partial_field", "printed_content", "inventory_rule", "undeclared_empty_region"]}`
- Deklarierte Felder (`catalog.json` → `groundTruth.fields`): **23**
- Vorschläge der produktiven Stufe: **55**

## Summe je Kategorie

| Kategorie | Anzahl | Bedeutung |
| --- | --- | --- |
| `real_field` | 23 | genau ein Vorschlag auf einem deklarierten Feld (IoU ≥ 0,5) |
| `duplicate_field` | 4 | weiterer Vorschlag auf demselben deklarierten Feld (IoU ≥ 0,5) |
| `partial_field` | 0 | Überlappung mit deklariertem Feld, aber IoU < 0,5 und Zentrum im Feld |
| `printed_content` | 26 | Vorschlag sitzt in einer Druckzeile oder enthält eine Druckzeile (≥ 50 %) |
| `inventory_rule` | 0 | FieldInventory-Rolle ≠ fieldCandidate oder Ausschlussgrund |
| `undeclared_empty_region` | 2 | leere Region ohne deklariertes Feld und ohne Druckinhalt (unentschieden) |

## Summe je Typ und Typfehler

| Vorgeschlagener Typ | Anzahl |
| --- | --- |
| `text` | 33 |
| `checkbox` | 13 |
| `date` | 5 |
| `multiline` | 2 |
| `number` | 2 |
| `signature` | 0 |

Typfehler auf den echten Feldern: **7**

| Vorschlag | Feld | deklariert | vorgeschlagen | Labeltext |
| --- | --- | --- | --- | --- |
| `s_p0_0005` | `p0-vorname` | `text` | `date` | Vorname |
| `s_p0_0007` | `p0-geburtsort` | `text` | `date` | Geburtsort |
| `s_p0_0017` | `p0-unterschrift` | `signature` | `text` | None |
| `s_p1_0018` | `p1-betrag-2` | `number` | `text` | None |
| `s_p1_0024` | `p1-betrag-3` | `number` | `text` | None |
| `s_p1_0029` | `p1-betrag-4` | `number` | `text` | None |
| `s_p1_0036` | `p1-unterschrift` | `signature` | `text` | None |

## je Seite

| Seite | Vorschläge | Kategorien |
| --- | --- | --- |
| None | 0 | {} |
| None | 0 | {} |

## Option A (nur `FieldInventory.fieldCandidates` anbieten)

- Messbarer Effekt: 55 → **47** (−8)
- IDs: `s_p0_0002`, `s_p0_0003`, `s_p0_0012`, `s_p1_0002`, `s_p1_0009`, `s_p1_0020`, `s_p1_0032`, `s_p1_0034`

Gegenprobe (`suggestions-without-date-mask.json`, `--drop-label-text "tt.mm.jjjj"`):
- Typfehler 7 → **5**, `byProposedType.date` 5 → 3.

Bei Abweichung zwischen dieser Datei und `suggestions.json` gilt das JSON.
