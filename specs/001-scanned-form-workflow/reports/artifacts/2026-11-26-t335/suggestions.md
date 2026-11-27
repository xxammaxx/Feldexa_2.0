# T335 — Vorschlagsinventar `sf-001` (maschinenlesbar erzeugt)

Erzeugt aus `suggestions.json` durch `tools/evaluation/t335_suggestion_inventory.dart`;
diese Markdown-Datei ist eine Ableitung derselben Zahlen, keine zweite Quelle.

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
| `inventory_rule` | 0 | `FieldInventory`-Rolle ≠ `fieldCandidate` oder Ausschlussgrund |
| `undeclared_empty_region` | 2 | leere Region ohne deklariertes Feld und ohne Druckinhalt (unentschieden) |

## Summe je Typ und Typfehler

| Vorgeschlagener Typ | Anzahl |
| --- | --- |
| `text` | 33 |
| `checkbox` | 13 |
| `date` | 5 |
| `multiline` | 2 |
| `number` | 2 |

Typfehler auf deklarierten Feldern (echte Felder, Typ ≠ `groundTruth`): **7**

| Vorschlag | Feld | Label | deklariert | vorgeschlagen | nächstes OCR-Label |
| --- | --- | --- | --- | --- | --- |
| `s_p0_0005` | `p0-vorname` | Vorname | `text` | `date` | `Vorname` |
| `s_p0_0007` | `p0-geburtsort` | Geburtsort | `text` | `date` | `Geburtsort` |
| `s_p0_0017` | `p0-unterschrift` | Unterschrift | `signature` | `text` | `None` |
| `s_p1_0013` | `p1-betrag-1` | Betrag 1 | `number` | `text` | `Meldebescheinigung` |
| `s_p1_0018` | `p1-betrag-2` | Betrag 2 | `number` | `text` | `Beglaubigung einer Kopie` |
| `s_p1_0024` | `p1-betrag-3` | Betrag 3 | `number` | `text` | `Versand mit Rückumschlag` |
| `s_p1_0036` | `p1-unterschrift` | Unterschrift | `signature` | `text` | `None` |

Option A (`FieldInventory` nur `fieldCandidates`): **8** der 55 Vorschläge würden entfallen — `s_p0_0002`, `s_p0_0003`, `s_p0_0012`, `s_p1_0002`, `s_p1_0009`, `s_p1_0020`, `s_p1_0032`, `s_p1_0034`.

## Je Seite

| Seite | deklarierte Felder | Detektor-Kandidaten | Inventar-Einträge (davon Kandidaten) | Inventar-Ausschlüsse | Vorschläge | Felder ohne Vorschlag |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 13 | 22 | 19 (16) | 3 | 18 | 0 |
| 1 | 10 | 42 | 37 (32) | 5 | 37 | 0 |

## Seite 0 — alle 18 Vorschläge

| id | x | y | w | h | Typ | Label (nächstes OCR) | Kategorie | GT-Feld | IoU | Ink | innen | enthalten | Inventar | Typfehler |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `s_p0_0001` | 56.88 | 43.50 | 481.62 | 18.00 | `text` | Musteramt für Bürgerdienste | `printed_content` | — | 0.00 | 0.056 | 0.20 | 1.00 | fieldCandidate | — |
| `s_p0_0002` | 116.25 | 45.75 | 5.12 | 4.62 | `checkbox` | Musteramt für Bürgerdienste | `printed_content` | — | 0.00 | 0.275 | 1.00 | 0.02 | filledRegion | — |
| `s_p0_0003` | 58.38 | 99.75 | 5.00 | 4.62 | `checkbox` | Bitte in Druckbuchstaben ausfüllen. | `printed_content` | — | 0.00 | 0.275 | 1.00 | 0.01 | filledRegion | — |
| `s_p0_0004` | 190.12 | 147.62 | 299.88 | 18.00 | `text` | Familienname | `real_field` | `p0-familienname` | 0.96 | 0.000 | 0.00 | 0.00 | fieldCandidate | — |
| `s_p0_0005` | 190.12 | 181.75 | 299.88 | 18.00 | `date` | Vorname | `real_field` | `p0-vorname` | 0.97 | 0.000 | 0.00 | 0.00 | fieldCandidate | declared text != proposed date |
| `s_p0_0006` | 190.12 | 215.62 | 299.88 | 18.00 | `date` | Geburtsdatum | `real_field` | `p0-geburtsdatum` | 0.96 | 0.000 | 0.00 | 0.00 | fieldCandidate | — |
| `s_p0_0007` | 190.12 | 249.50 | 299.88 | 18.00 | `date` | Geburtsort | `real_field` | `p0-geburtsort` | 0.95 | 0.000 | 0.00 | 0.00 | fieldCandidate | declared text != proposed date |
| `s_p0_0008` | 190.12 | 283.62 | 299.88 | 18.00 | `text` | Staatsangehörigkeit | `real_field` | `p0-staatsangehoerigkeit` | 0.96 | 0.000 | 0.00 | 0.00 | fieldCandidate | — |
| `s_p0_0009` | 190.12 | 353.50 | 299.88 | 18.00 | `text` | Straße und Hausnummer | `real_field` | `p0-strasse` | 0.95 | 0.000 | 0.00 | 0.00 | fieldCandidate | — |
| `s_p0_0010` | 190.12 | 387.75 | 299.88 | 18.00 | `text` | Postleitzahl | `real_field` | `p0-plz` | 0.97 | 0.000 | 0.00 | 0.00 | fieldCandidate | — |
| `s_p0_0011` | 190.12 | 421.50 | 299.88 | 18.00 | `text` | Ort | `real_field` | `p0-ort` | 0.95 | 0.000 | 0.00 | 0.00 | fieldCandidate | — |
| `s_p0_0012` | 58.00 | 425.50 | 5.00 | 5.38 | `checkbox` | Ort | `printed_content` | — | 0.00 | 0.195 | 1.00 | 0.13 | filledRegion | — |
| `s_p0_0013` | 190.50 | 502.25 | 9.25 | 9.25 | `checkbox` | Geschlecht | `real_field` | `p0-geschlecht-weiblich` | 0.86 | 0.000 | 0.00 | 0.00 | fieldCandidate | — |
| `s_p0_0014` | 300.25 | 502.25 | 9.38 | 9.25 | `checkbox` | weiblich | `real_field` | `p0-geschlecht-maennlich` | 0.87 | 0.000 | 0.00 | 0.00 | fieldCandidate | — |
| `s_p0_0015` | 410.38 | 502.25 | 9.38 | 9.25 | `checkbox` | männlich | `real_field` | `p0-geschlecht-divers` | 0.87 | 0.000 | 0.00 | 0.00 | fieldCandidate | — |
| `s_p0_0016` | 190.12 | 547.50 | 299.88 | 18.00 | `date` | Datum | `real_field` | `p0-datum` | 0.95 | 0.000 | 0.00 | 0.00 | fieldCandidate | — |
| `s_p0_0017` | 190.12 | 623.50 | 299.88 | 18.00 | `text` | — | `real_field` | `p0-unterschrift` | 0.60 | 0.000 | 0.00 | 0.00 | fieldCandidate | declared signature != proposed text |
| `s_p0_0018` | 56.88 | 777.62 | 481.62 | 18.00 | `text` | Synthetisches Testdokument – kein amtliches Formular – keine personenbezogenen Daten | `undeclared_empty_region` | — | 0.00 | 0.000 | 0.00 | 0.00 | fieldCandidate | — |

## Seite 1 — alle 37 Vorschläge

| id | x | y | w | h | Typ | Label (nächstes OCR) | Kategorie | GT-Feld | IoU | Ink | innen | enthalten | Inventar | Typfehler |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `s_p1_0001` | 56.88 | 43.50 | 481.62 | 18.00 | `text` | Musteramt für Bürgerdienste | `printed_content` | — | 0.00 | 0.056 | 0.20 | 1.00 | fieldCandidate | — |
| `s_p1_0002` | 116.25 | 45.75 | 5.12 | 4.62 | `checkbox` | Musteramt für Bürgerdienste | `printed_content` | — | 0.00 | 0.275 | 1.00 | 0.02 | filledRegion | — |
| `s_p1_0003` | 190.50 | 152.25 | 347.75 | 75.62 | `multiline` | Begründung | `real_field` | `p1-grund` | 0.99 | 0.000 | 0.00 | 0.00 | fieldCandidate | — |
| `s_p1_0004` | 56.88 | 286.25 | 59.38 | 25.50 | `text` | Position | `printed_content` | — | 0.00 | 0.060 | 0.25 | 1.00 | fieldCandidate | — |
| `s_p1_0005` | 56.88 | 286.25 | 481.62 | 129.50 | `multiline` | Position | `printed_content` | `p1-betrag-1` | 0.03 | 0.041 | 0.02 | 1.00 | fieldCandidate | — |
| `s_p1_0006` | 117.00 | 286.25 | 301.62 | 25.50 | `text` | Position | `printed_content` | — | 0.00 | 0.012 | 0.05 | 1.00 | fieldCandidate | — |
| `s_p1_0007` | 419.38 | 286.25 | 119.12 | 25.50 | `text` | Leistung | `printed_content` | — | 0.00 | 0.027 | 0.11 | 1.00 | fieldCandidate | — |
| `s_p1_0008` | 56.50 | 293.75 | 482.75 | 18.00 | `text` | Position | `printed_content` | — | 0.00 | 0.036 | 0.05 | 1.00 | fieldCandidate | — |
| `s_p1_0009` | 449.25 | 297.00 | 4.38 | 5.00 | `checkbox` | Leistung | `printed_content` | — | 0.00 | 0.363 | 1.00 | 0.07 | filledRegion | — |
| `s_p1_0010` | 56.88 | 312.12 | 59.38 | 25.50 | `text` | 1 | `printed_content` | — | 0.00 | 0.005 | 0.04 | 1.00 | fieldCandidate | — |
| `s_p1_0011` | 117.00 | 312.12 | 301.62 | 25.50 | `text` | 1 | `printed_content` | — | 0.00 | 0.022 | 0.11 | 1.00 | fieldCandidate | — |
| `s_p1_0012` | 419.38 | 312.12 | 119.12 | 25.50 | `text` | Meldebescheinigung | `duplicate_field` | `p1-betrag-1` | 0.62 | 0.025 | 0.00 | 0.00 | fieldCandidate | — |
| `s_p1_0013` | 427.00 | 314.62 | 104.00 | 18.00 | `text` | Meldebescheinigung | `real_field` | `p1-betrag-1` | 0.86 | 0.000 | 0.00 | 0.00 | fieldCandidate | declared number != proposed text |
| `s_p1_0014` | 56.50 | 319.62 | 482.75 | 18.00 | `text` | 1 | `printed_content` | `p1-betrag-1` | 0.17 | 0.034 | 0.10 | 1.00 | fieldCandidate | — |
| `s_p1_0015` | 56.88 | 338.38 | 59.38 | 25.25 | `text` | 2 | `printed_content` | — | 0.00 | 0.006 | 0.04 | 1.00 | fieldCandidate | — |
| `s_p1_0016` | 117.00 | 338.38 | 301.62 | 25.25 | `text` | 2 | `printed_content` | — | 0.00 | 0.027 | 0.14 | 1.00 | fieldCandidate | — |
| `s_p1_0017` | 419.38 | 338.38 | 119.12 | 25.25 | `text` | Beglaubigung einer Kopie | `duplicate_field` | `p1-betrag-2` | 0.62 | 0.025 | 0.00 | 0.00 | fieldCandidate | — |
| `s_p1_0018` | 427.00 | 340.50 | 104.00 | 18.00 | `text` | Beglaubigung einer Kopie | `real_field` | `p1-betrag-2` | 0.85 | 0.000 | 0.00 | 0.00 | fieldCandidate | declared number != proposed text |
| `s_p1_0019` | 56.50 | 345.62 | 482.75 | 18.00 | `text` | 2 | `printed_content` | `p1-betrag-2` | 0.17 | 0.038 | 0.12 | 1.00 | fieldCandidate | — |
| `s_p1_0020` | 126.38 | 347.75 | 5.00 | 4.75 | `checkbox` | 2 | `printed_content` | — | 0.00 | 0.280 | 1.00 | 0.02 | filledRegion | — |
| `s_p1_0021` | 56.88 | 364.38 | 59.38 | 25.12 | `text` | 3 | `printed_content` | — | 0.00 | 0.007 | 0.04 | 1.00 | fieldCandidate | — |
| `s_p1_0022` | 117.00 | 364.38 | 301.62 | 25.12 | `text` | 3 | `printed_content` | — | 0.00 | 0.027 | 0.16 | 1.00 | fieldCandidate | — |
| `s_p1_0023` | 419.38 | 364.38 | 119.12 | 25.12 | `text` | Versand mit Rückumschlag | `duplicate_field` | `p1-betrag-3` | 0.62 | 0.012 | 0.00 | 0.00 | fieldCandidate | — |
| `s_p1_0024` | 427.00 | 366.88 | 104.00 | 18.00 | `text` | Versand mit Rückumschlag | `real_field` | `p1-betrag-3` | 0.88 | 0.000 | 0.00 | 0.00 | fieldCandidate | declared number != proposed text |
| `s_p1_0025` | 56.50 | 371.50 | 482.75 | 18.00 | `text` | 3 | `printed_content` | `p1-betrag-3` | 0.17 | 0.034 | 0.14 | 1.00 | fieldCandidate | — |
| `s_p1_0026` | 56.88 | 390.25 | 59.38 | 25.50 | `text` | 4 | `printed_content` | — | 0.00 | 0.006 | 0.04 | 1.00 | fieldCandidate | — |
| `s_p1_0027` | 117.00 | 390.25 | 301.62 | 25.50 | `text` | 4 | `printed_content` | — | 0.00 | 0.008 | 0.04 | 1.00 | fieldCandidate | — |
| `s_p1_0028` | 419.38 | 390.25 | 119.12 | 25.50 | `number` | Summe | `duplicate_field` | `p1-betrag-4` | 0.62 | 0.012 | 0.00 | 0.00 | fieldCandidate | — |
| `s_p1_0029` | 427.00 | 392.75 | 104.00 | 18.00 | `number` | Summe | `real_field` | `p1-betrag-4` | 0.87 | 0.000 | 0.00 | 0.00 | fieldCandidate | — |
| `s_p1_0030` | 190.50 | 480.25 | 9.25 | 9.38 | `checkbox` | Barzahlung | `real_field` | `p1-zahlung-bar` | 0.87 | 0.000 | 0.00 | 0.00 | fieldCandidate | — |
| `s_p1_0031` | 330.50 | 480.25 | 9.38 | 9.38 | `checkbox` | Barzahlung | `real_field` | `p1-zahlung-ueberweisung` | 0.88 | 0.000 | 0.00 | 0.00 | fieldCandidate | — |
| `s_p1_0032` | 70.88 | 532.12 | 4.38 | 5.38 | `checkbox` | 7. Ort, Datum und Unterschrift | `printed_content` | — | 0.00 | 0.178 | 1.00 | 0.01 | filledRegion | — |
| `s_p1_0033` | 190.12 | 553.62 | 299.88 | 18.00 | `text` | Ort | `real_field` | `p1-ort` | 0.96 | 0.000 | 0.00 | 0.00 | fieldCandidate | — |
| `s_p1_0034` | 58.00 | 557.62 | 5.00 | 5.38 | `checkbox` | Ort | `printed_content` | — | 0.00 | 0.195 | 1.00 | 0.13 | filledRegion | — |
| `s_p1_0035` | 190.12 | 587.50 | 299.88 | 18.00 | `date` | Datum | `real_field` | `p1-datum` | 0.95 | 0.000 | 0.00 | 0.00 | fieldCandidate | — |
| `s_p1_0036` | 190.12 | 637.50 | 299.88 | 18.00 | `text` | — | `real_field` | `p1-unterschrift` | 0.60 | 0.000 | 0.00 | 0.00 | fieldCandidate | declared signature != proposed text |
| `s_p1_0037` | 56.88 | 777.62 | 481.62 | 18.00 | `text` | Synthetisches Testdokument – kein amtliches Formular – keine personenbezogenen Daten | `undeclared_empty_region` | — | 0.00 | 0.000 | 0.00 | 0.00 | fieldCandidate | — |

