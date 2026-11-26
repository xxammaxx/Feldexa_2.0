# Issue #344 Teil B — AcroForm-Fixture und Flattening-Beleg (`EMULATOR`)

**Lauf**: `run-tscn02hu`, Worktree `t344-acroform-fixture`, Branch
`xxammaxx/t344-acroform-fixture`, Basis `cc37254`.
**Gerät**: `emulator-5554`, AVD `T025_Pixel7_API35_KVM_20261115`, API 35 (das
physische S23 wurde nicht adressiert).
**Treiber**: `tools/android/t334_drive_export.sh` (Selbst-Admission über
`compute_slot.py --wait --resource build --resource emulator`, kein äußerer
Wrapper).
**Evidenz**: `specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t344-acroform/`.

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

Ein vollständiger Treiberlauf auf Commit `742d47c` (Baum sauber), Ausgabe
`run-status.txt`:

```
result=PASS
flutter_test_exit=0
artifact_1_sha256=c9cad5aadfb09e892f2ce98df38243476ca9f358d0a03c4cd7a687fdf29705f3
artifact_1_bytes=12029
artifact_2_sha256=63e47315ae004be8eb167b7757286572568b7b07d4f36be86a71ae72916064eb
artifact_2_bytes=12029
artifact_3_sha256=3b5360dccb0a970863062649581e304fce558a51ea9b1165f92ddb9478c147cb
artifact_3_bytes=2388
```

Wörtliche PASS-Zeile des Treibers:

```
T334 DRIVER: PASS (flutter test exit 0; cleanup marker observed; three artifacts picked up with matching digests; poppler and byte-search proof for all three; AcroForm flattening proved for artifact 3 (no /AcroForm, /Widget, /FT /Tx; field value survives in the text layer); static gates clean; privacy checks PASS; 1 mm placement claim NOT_PROVEN)
```

Drei Pickups mit Digest-Match gegen den Marker, Poppler für alle drei,
AcroForm-Beleg für Artefakt 3. Statische Gates im Lauf:
`gate-analyze.txt` → „No issues found!", `gate-format.txt` → „Formatted 121
files (0 changed)".

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
| `pdftotext` Feldwert | `Feldwert` **1×** vorhanden |
| Position des Werts | `pdftotext -bbox`: `xMin=59.000 yMin=139.820 xMax=97.340 yMax=149.070` — **identisch** zur Quelle |

Das Flattening hat also die interaktive Struktur entfernt (`Form: none`, drei
Marker auf 0) und den sichtbaren Inhalt erhalten: der Feldwert liegt nach dem
Export an derselben Stelle im Textlayer wie die Appearance der Quelle
(`xMin/yMin/xMax/yMax` byte-gleich). Ein Flattening, das die Appearance
verworfen hätte, würde den Wert verlieren — er steht nirgends sonst im
Seiteninhalt.

Ehrliche Einschränkung: Poppler extrahiert den Appearance-Text bereits aus dem
**Quell**-PDF. Der `pdftotext`-Beleg allein unterscheidet daher nicht zwischen
„Appearance blieb Annotation" und „Appearance wurde Seiteninhalt". Diese
Unterscheidung leisten die drei Byte-Suchen zusammen mit `pdfinfo "Form: none"`
und der identischen `-bbox`-Position.

## Nicht belegt / offen

- **1-mm-Platzierungsclaim**: `placement_verdict=NOT_PROVEN` für Artefakte 1
  und 2 (`dx=-132.140 pt`, `dy=-3.050 pt` gegen 2.835 pt Toleranz). Das ist
  **kein** Regress dieses Teils: der vorherige Lauf
  (`artifacts/2026-11-26-t344-export-proof-depth/run-status.txt`) verzeichnet
  exakt dieselben Abweichungen. Die Ursache (der gezeichnete Wert sitzt
  linksbündig am Rect-Anfang statt zentriert) gehört zu #344 Punkt 1 und bleibt
  dort offen; dieser Teil ändert weder Layout noch Schwelle.
- Artefakt 3 hat bewusst **keinen** Platzierungsmesswert
  (`artifact-3-placement.txt` → `verdict=NOT_APPLICABLE`): es wurde kein Wert
  gezeichnet.
- Der Lauf beweist die Flattening-Kette auf `EMULATOR`; eine Aussage über
  physische Endgeräte ist damit nicht verbunden.
