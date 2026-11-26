# Issue #344 Teil B — AcroForm-Fixture und Flattening-Beleg (`EMULATOR`)

**Lauf**: `run-tscn02hu`, Worktree `t344-acroform-fixture`, Branch
`xxammaxx/t344-acroform-fixture`, Basis `cc37254`.
**Gerät**: `emulator-5554`, AVD `T025_Pixel7_API35_KVM_20261115`, API 35 (das
physische S23 wurde nicht adressiert).
**Treiber**: `tools/android/t334_drive_export.sh` (Selbst-Admission über
`compute_slot.py --wait --resource build --resource emulator`, kein äußerer
Wrapper).
**Evidenz**: `specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t344-acroform-final/`
(finaler Lauf; der Vorlauf-Bundle `…/2026-11-26-t344-acroform/` bleibt
unverändert und wird unten dort zitiert, wo er eine Aussage trägt).

## Warum

Punkt 2 von #344: `noInteractiveFields` war bisher nur über eine Byte-Suche und
`pdfinfo "Form: none"` des Quell-Fixtures gestützt — und `sf-001.pdf` enthält
gar keine AcroForm. `PdfExportService.flattenSourceAcroForm`
(`contracts/export-plan.md` §5 Schritt 2a/3, FR-069) war damit gegen **keine**
echte Quelle mit Formularfeldern geprüft.

## Fixture-Erzeugung

`tools/corpus/synthetic/make_acroform_fixture.py` schreibt deterministisch
(handgeschriebene PDF-Struktur, fixe Objekt- und XRef-Reihenfolge, fixe
Dokument-ID, kein `qpdf`/`reportlab` im Einsatz) ein einseitiges A4-PDF mit
genau **einem** AcroForm-Textfeld:

- `/AcroForm` im Catalog (`/Fields [7 0 R]`, `/NeedAppearances false`),
- `/FT /Tx` mit `/T (familienname)`, `/V (Feldwert)`,
- `/Subtype /Widget` mit `/Rect [56 690 356 708]` und `/AP << /N 6 0 R >>`,
- sichtbarer Feldwert `Feldwert` **nur** in der Widget-Appearance; der
  Seiteninhalt trägt Titel, Feldlabel `Familienname:` und den Footer
  „Synthetische Testdaten, keine personenbezogenen Daten." Der Wert existiert
  also ausschließlich in der Appearance — ein Flattening, das Appearances
  verwirft, würde ihn verlieren.

Bytes: **1424**, SHA-256
`7f4e014482425518058e28c497b9e8bcf4a4930dec1dbd5edb74cb8c8992af9a`, drei
byte-identische Kopien (kanonisch, Web-Spiegel, Corpus), geprüft durch
`python3 tools/corpus/synthetic/make_acroform_fixture.py --check`.

### Felder-Beleg (wörtlich, `fixture-acroform-proof.txt`)

```
command=pdfinfo apps/feldexa_app/assets/fixtures/sf-acroform-001.pdf
Form:            AcroForm
Pages:           1
Page size:       595 x 842 pts (A4)
File size:       1424 bytes
expected: Form: AcroForm
fixture_token '/AcroForm' occurrences=1
fixture_token '/Widget' occurrences=1
fixture_token '/FT /Tx' occurrences=1
```

Der Treiber macht diesen Nachweis fail-closed: `Form:` muss `AcroForm` sein und
jeder der drei Marker mindestens einmal vorkommen, sonst bricht der Lauf ab.

## Registrierung (dokumentierte Scope-Entscheidung)

Das Fixture ist **bewusst nicht** in `apps/feldexa_app/assets/fixtures/catalog.json`
registriert. Dieser Katalog wird von `tools/corpus/synthetic/generate.dart`
byte-geprüft erzeugt (`dart run tools/corpus/synthetic/generate.dart --check`)
und von `apps/feldexa_app/test/synthetic_fixtures_test.dart` pro Eintrag
gepinnt (Generatorpfad, `retrievalDate`, `%FELDEXA-SYNTHETIC-FIXTURE`-Header,
`/ID`, `valid.length`, Ground-Truth-/OCR-Pflichten). Ein handgeschriebener
Eintrag für ein Python-generiertes Fixture würde beide Invarianten rot machen.

Registriert ist es deshalb in `apps/feldexa_app/assets/fixtures/catalog-acroform.json`
(gleiches Entry-Schema, Rechte, Generator, `--check`-Kommando, SHA-256/Größe,
Seiten, Ground Truth). Dieser Register wird maschinell geprüft durch
`apps/feldexa_app/test/acroform_fixture_catalog_test.dart`: Existenz der drei
Kopien, Byte-Gleichheit, `sha256`/`sizeBytes` gegen die Bytes, Existenz des
Generatorpfads, strukturelle Marker (`/AcroForm`, `/Subtype /Widget`,
`/FT /Tx`), Seitenzahl/MediaBox — und dass die ID **nicht** im generierten
Katalog steht. Damit ist stille Drift rot statt unbemerkt.

Gegenprobe nach der Änderung: `generate.dart --check` meldet weiter
`OK all 37 generated files are byte-for-byte current`, der neue Unit-Test 5/5
grün, `flutter analyze --no-pub` „No issues found!".

## Dritter Beleg-Leg im Integrationstest

`apps/feldexa_app/integration_test/android_export_test.dart`, Leg 3 (die Legs 1
und 2 bleiben inhaltlich unverändert):

1. `sf-acroform-001.pdf` wird über den Debug-Hook `de.feldexa/test.import`
   armiert und über die produktive Import-Aktion importiert; Analyse bis zum
   terminalen Zustand.
2. Export über den produktiven `ExportController` (`prepare` + `run`) auf der
   importierten Revision — **ohne** Füllen. Der Leg hängt nicht davon ab, ob die
   Analyse ein Feld anbietet (siehe Marker `FIELDS=0` unten).
3. Artefakt als `e2e/export-artifact-3.pdf` in den app-internen Cache, Marker
   mit Index 3, Warten auf die Host-Ack-Datei, danach Preview öffnen/schließen
   und Löschung (`EXP-002`) belegen.
4. Assertions: `ArtifactVerification.noInteractiveFields == true`,
   `allChecksPassed == true`, Seitenzahl 1, und die Bytes enthalten kein
   `/AcroForm`, kein `/Widget`, kein `/FT /Tx`. Die drei Marker werden jetzt für
   **alle** Artefakte geprüft (einheitlich, ohne Sonderfall).

Markersequenz des Legs (Auszug aus `markers-integration.txt`):

```
T334_ACROFORM_FIXTURE_READY:BYTES=1424:MATCH=1
T334_ACROFORM_LEG_START
T334_ACROFORM_FIXTURE_ARMED
T334_ACROFORM_EDITOR_READY
T334_ACROFORM_ANALYSIS_READY:PAGES=1:FIELDS=0
T334_ARTIFACT_FIELD_TOKENS:INDEX=3:ACROFORM=0:WIDGET=0:FT_TX=0
T334_ARTIFACT_STORED:INDEX=3:PATH=/data/user/0/de.feldexa.app/code_cache/e2e/export-artifact-3.pdf:BYTES=2388:SHA256=3b5360dccb0a970863062649581e304fce558a51ea9b1165f92ddb9478c147cb
T334_HOST_PICKUP_ACKED:INDEX=3
T334_ARTIFACT_DELETED_AFTER_PREVIEW_CLOSE:INDEX=3:CODE=EXP-002
T334_ACROFORM_FLATTENING_PROVEN
```

`FIELDS=0` ist der Beleg, dass der dritte Leg unabhängig vom Analyse-Angebot
läuft: die Analyse hat kein Feld vorgeschlagen, der Export lief trotzdem.

## Lauf

Ein vollständiger Treiberlauf auf Commit `0e8a164` (Baum sauber), Evidenz in
`specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t344-acroform-final/`
(das frühere Verzeichnis `…/2026-11-26-t344-acroform/` bleibt byte-identisch),
Ausgabe `run-status.txt`:

```
result=PASS
flutter_test_exit=0
artifact_1_sha256=7a45c77a4acf3b42aa6aebace34dded3ddf95f1a59249226e63996fe3ea09dba
artifact_1_bytes=12029
artifact_1_placement_verdict=PROVEN
artifact_2_sha256=38262d6d119344baed69e9608aca5b845c5716949bb9ce70e329600a7c5f2779
artifact_2_bytes=12029
artifact_2_placement_verdict=PROVEN
artifact_3_sha256=749097023e1cf38fa855f40bf8c10359d5f744107a36a5bd91ca76960b42a91e
artifact_3_bytes=2388
artifact_3_placement_verdict=NOT_APPLICABLE
placement_verdict=PROVEN
placement_tolerance_pt=2.835
placement_metric=origin of the drawn value as the layout code places it (tools/pdf_verify/placement.py)
placement_drawn_value_legs=1,2
placement_reason=none (every drawn-value leg is PROVEN; the drawn-value legs are 1 2, every other leg drew no value)
```

Wörtliche PASS-Zeile des Treibers:

```
T334 DRIVER: PASS (flutter test exit 0; cleanup marker observed; three artifacts picked up with matching digests; poppler and byte-search proof for all three; AcroForm flattening proved for artifact 3 (no /AcroForm, /Widget, /FT /Tx; field value survives in the text layer); static gates clean; privacy checks PASS; 1 mm placement claim PROVEN (artifact_1=PROVEN artifact_2=PROVEN artifact_3=NOT_APPLICABLE))
```

Drei Pickups mit Digest-Match gegen den Marker, Poppler für alle drei,
AcroForm-Beleg für Artefakt 3. Statische Gates im Lauf:
`gate-analyze.txt` → „No issues found!", `gate-format.txt` → „Formatted 121
files (0 changed)".

## Eine Metrik statt zwei

**Warum die alte Messung weg musste.** Der Treiber trug bis hierher eine eigene
Platzierungsmessung (`pdftotext -bbox`, Wert-Box-Mittelpunkt gegen
Rect-Mittelpunkt). Für dieses Layout ist sie nachweislich falsch: der Wert wird
linksbündig und oben ausgerichtet gezeichnet, in einem Feld von 299.875 pt
Breite, der Wert selbst ist 32.594 pt breit. Der Mittelpunktvergleich misst
also den halben Feldüberhang
(`(299.875 − 32.594) / 2 = 133.640 pt`), nicht die Position des Werts, und
meldete `dx=-132.140 pt` / `dy=-3.050 pt` — jenseits der 2.835-pt-Toleranz. Mit
derselben Feld-Rect und derselben Glyph-Box meldet das geprüfte Werkzeug
`origin deviation +0.000000 pt`, `baseline deviation −0.000010 pt`. Zwei
Metriken im selben Bundle, die sich um 132 pt widersprechen: eine davon ist
der Defekt, und sie stand im Beleg.

**Was jetzt passiert.** Die inline-Mittelpunkt-Messung ist vollständig entfernt
(kein Duplikat, kein Toter-Code-Rest); der Treiber misst keine Position mehr
selbst. Er ruft `tools/pdf_verify/placement.py` auf
(`tools/android/t334_drive_export.sh:1098-1106`) mit `--pdf`,
`--value-word`, `--field-rect-marker`, `--layout`, `--applier-source`,
`--font-metrics` und `--tolerance-pt 2.835`. Das Werkzeug leitet die Soll-Position
aus dem Code ab, der den Wert zeichnet (`TEXT_PADDING_PT`, `exportFieldPaddingPt`,
`_baselineAscenderFactor`, `_fontSizeHeightFactor`, Font-Size-Clamp, Fontmetriken)
und verweigert ein Verdikt (exit 5), wenn die beiden Padding-Kopien auseinander-
laufen. Die Ausgabe landet wörtlich in `artifact-N-placement.txt`, inklusive
`pdf_sha256`; der Treiber prüft diesen Digest gegen den Pickup-Digest und
bricht bei Abweichung ab (`:1116`, `:1132-1133`).

**Fail-closed.** Exit 0 ist Pflicht: jede Rückkehr ungleich 0 beendet den Lauf
(1 = Prüfpunkt verfehlt, 2 = Nutzungsfehler, 3 = Wertwort nicht gefunden,
4 = mehrdeutiger Treffer, 5 = unlesbare Eingabe, 6 = Poppler-Fehler, `:1119-1127`),
und ein gezeichneter Wert ohne `placement_verdict=PROVEN` ist ebenfalls ein
Lauf-Fehler (`:1128-1129`).

**Neues Verdikt der beiden gezeichneten Artefakte** (identische Zahlen, weil
beide Legs dasselbe Dokument mit demselben Feld exportieren):

| Größe | Artefakt 1 | Artefakt 2 |
| --- | --- | --- |
| `placement_verdict` | `PROVEN` | `PROVEN` |
| `exit_code` | 0 | 0 |
| `pdf_sha256` | `7a45c77a4acf3b42aa6aebace34dded3ddf95f1a59249226e63996fe3ea09dba` | `38262d6d119344baed69e9608aca5b845c5716949bb9ce70e329600a7c5f2779` |
| `rect_pt` | `190.125,147.625,299.875,18.000` | `190.125,147.625,299.875,18.000` |
| `target_origin_pt` | `191.625,157.765` | `191.625,157.765` |
| `glyph_box_pt` | `191.625,146.219790,224.219400,160.929390` | `191.625,146.219790,224.219400,160.929390` |
| `check.horizontal_origin` | deviation `+0.000000 pt` → pass | deviation `+0.000000 pt` → pass |
| `check.vertical_baseline` | deviation `−0.000010 pt` → pass | deviation `−0.000010 pt` → pass |
| `check.font_box.height` | `14.709600` gegen `14.709600` → pass | `14.709600` gegen `14.709600` → pass |
| `containment_verdict` | `PASS` | `PASS` |
| `axes_check` | `consistent` | `consistent` |

Die Abweichung liegt damit vier Größenordnungen unter der 1-mm-Schwelle statt
132 pt darüber.

**Artefakt 3 bleibt `NOT_APPLICABLE` — und zwar begründet, nicht per
Index-Regel.** Die frühere Fassung entschied die Anwendbarkeit über eine
Fallunterscheidung auf den Leg-Index (`artifact_has_placement` `1 | 2) return 0`).
Diese Funktion ist entfernt. Der Treiber liest die Anwendbarkeit jetzt aus den
Markern des Tests selbst (`:909-956`): der Test gibt den Rect-Marker aus, wenn
ein Feld bestätigt wird, und öffnet den Flattening-Leg mit
`T334_ACROFORM_LEG_START` — ein Leg, der nichts bestätigt und nichts füllt und
daher keinen Rect-Marker ausgibt. Jeder Leg, dessen Artefakt vor diesem Marker
abgelegt wird, hat einen gezeichneten Wert; jeder Leg danach nicht, und im
Bereich danach darf kein Rect-Marker stehen (beides wird geprüft, der Lauf
bricht sonst ab). Ergebnis im Lauf: `DRAWN_LEGS=1 2`, ein Rect-Marker vor der
Grenze, null danach. Die Evidenzdatei des dritten Legs nennt den Grund wörtlich:

```
index=3
verdict=NOT_APPLICABLE
reason=artifact 3 exports the AcroForm fixture unchanged: T334_ACROFORM_LEG_START opens its leg, the leg confirms and fills nothing, so the test prints no T334_FIELD_RECT marker for it, no value is drawn, and there is no placement to measure
field_rect_marker=none (0 T334_FIELD_RECT markers after T334_ACROFORM_LEG_START at log line 109)
drawn_value_legs=1,2
artifact_sha256=749097023e1cf38fa855f40bf8c10359d5f744107a36a5bd91ca76960b42a91e
```

**Neue Hashes** (siehe `run-status.txt` oben): Artefakt 1
`7a45c77a…e09dba`, Artefakt 2 `38262d6d…f2779`, Artefakt 3
`74909702…42a91e`; die PDFs tragen Erzeugungszeitstempel, ihre Digests sind
daher laufabhängig und nicht mit dem Vorlauf vergleichbar. Der
`pdf_sha256`-Wert jedes Platzierungsbelegs ist der Pickup-Digest desselben
Artefakts.


## Flattening-Verdikt für Artefakt 3: **belegt**

Quelle `sf-acroform-001.pdf`: `Form: AcroForm`, `/AcroForm`=1, `/Widget`=1,
`/FT /Tx`=1, 1 Seite, 595 × 842 pt.

Artefakt 3 (`export-artifact-3.pdf`, 2388 Bytes):

| Prüfung | Ergebnis |
| --- | --- |
| `pdfinfo` `Form:` | `none` (Quelle: `AcroForm`) |
| Byte-Suche `/AcroForm` | 0 Treffer (grep exit 1) |
| Byte-Suche `/Widget` | 0 Treffer (grep exit 1) |
| Byte-Suche `/FT /Tx` | 0 Treffer (grep exit 1) |
| Seiten / Seitengröße | 1 / `595 x 842 pts` — wie die Quelle |
| `pdftotext` Feldwert | `Feldwert` vorhanden (`pdftotext`-Ausgabe: `4:Feldwert`) |
| Position des Werts | im Vorlauf-Bundle `artifacts/2026-11-26-t344-acroform/artifact-3-placement.txt`: `xMin=59.000 yMin=139.820 xMax=97.340 yMax=149.070` — **identisch** zur Quelle. Der neue Treiber erhebt für dieses Leg keine `-bbox`-Messung mehr: das Platzierungswerkzeug gilt nur für Legs mit gezeichnetem Wert |

Das Flattening hat also die interaktive Struktur entfernt (`Form: none`, drei
Marker auf 0) und den sichtbaren Inhalt erhalten: der Feldwert steht nach dem
Export im Textlayer (im Vorlauf-Bundle zusätzlich an derselben Stelle wie die
Appearance der Quelle, `xMin/yMin/xMax/yMax` byte-gleich). Ein Flattening, das
die Appearance verworfen hätte, würde den Wert verlieren — er steht nirgends
sonst im Seiteninhalt.

Ehrliche Einschränkung: Poppler extrahiert den Appearance-Text bereits aus dem
**Quell**-PDF. Der `pdftotext`-Beleg allein unterscheidet daher nicht zwischen
„Appearance blieb Annotation" und „Appearance wurde Seiteninhalt". Diese
Unterscheidung leisten die drei Byte-Suchen zusammen mit `pdfinfo "Form: none"`
und (im Vorlauf-Bundle) der identischen `-bbox`-Position.

## Nicht belegt / offen

- Nichts aus dem Platzierungsclaim bleibt offen: beide gezeichneten Artefakte
  sind `PROVEN` (Abschnitt „Eine Metrik statt zwei"). Der frühere Eintrag
  „`NOT_PROVEN`, `dx=-132.140 pt`" war der Defekt der alten Metrik, nicht des
  Produkts; er ist mit der Metrik entfallen.
- Artefakt 3 hat bewusst **keinen** Platzierungsmesswert
  (`artifact-3-placement.txt` → `verdict=NOT_APPLICABLE`): der Leg bestätigt und
  füllt nichts, der Test gibt für ihn keinen Rect-Marker aus, es wurde kein
  Wert gezeichnet.
- Der Lauf beweist die Flattening-Kette auf `EMULATOR`; eine Aussage über
  physische Endgeräte ist damit nicht verbunden.
