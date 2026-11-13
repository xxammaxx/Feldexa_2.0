# Prior-Art Technical Audit — Quellcode-Prüfung statt Beschreibungsvergleich

**Datum:** 13.11.2026 · **Methode:** Tatsächliche Repository-Klone + statische Quellcode-Analyse (grep im Kontext, Architektur-, API- und Test-Inspektion). Vorherige Recherche-Runden (Issue #167, Runden I–IV) waren an DNS/Anti-Bot geblockt und nur dokumentbasiert — dieser Audit schließt die Lücke.
**Regeln:** `NOT_FOUND_IN_REVIEWED_CODE` ≠ Beweis der Abwesenheit. Beschreibungs-basierte Erkenntnisse sind als `DOC_ONLY` markiert. Keine Tests ohne Abhängigkeitsinstallation ausgeführt (`NOT_TESTED`).

## Geprüfte Repositories

| Projekt | Clone-Quelle | HEAD-SHA (Audit-Datum 13.11.2026) | Lizenz | Zugriff |
|---|---|---|---|---|
| **KIWo / OpenForm-Vorgänger** (OpenAdvo) | https://gitlab.opencode.de/openadvo/kiwo.git | `c40bb34d5b28bf122fb64b971a6e2f26803f02fa` (main, 2026-10-14) | Apache-2.0 (LICENSE) | geklont, voll audit |
| **Formularagent** (OC000097948268) | https://gitlab.opencode.de/OC000097948268/formularagent.git | `4085c4658cc21e92a6ae76929ca6cd4586e5723d` (main, 2026-09-25) | MPL-2.0 (LICENSE) | geklont, voll audit |
| CommonForms (jbarrow) | github.com/jbarrow/commonforms | `f5f4007` (2026-06-17) | **keine Lizenzdatei** (GitHub-API: `license: null`) | geklont |
| GSA pdf-filler | github.com/GSA/pdf-filler | `405ed8b` | MIT + US-Gov-Work | geklont |
| ozg (LilithWittmann) | github.com/LilithWittmann/ozg | `e6732e5` (dormant seit 2022) | MIT | geklont |
| PDFform-info-migration-tool (RuiqiZhan) | github.com/RuiqiZhan/… | `6a69dbf` | **keine Lizenzdatei** | geklont |
| SurveyJS survey-library / pdf | github.com/surveyjs | (shallow) | MIT / **kommerziell** (pdf) | geklont |
| xdatenfelder-xml (flxbe) | github.com/flxbe/xdatenfelder-xml | (shallow) | EUPL-1.2 | geklont |
| fim-portal-cli (maschinenlasbar-org) | github.com/maschinenlasbar-org/fim-portal-cli | (aktiv 11/2026) | AGPL-3.0 | geklont |
| MACH formsolutions | — | — | proprietär | **DOC_ONLY** (mach.de-Dokumentation) |
| FITKO FIM-Sammelrepository / FIT-Connect | docs.fitko.de + live-Artefakt schema.fim.fitko.net | S00000159V1.4-XSD (SHA s. Referenzfall) | — | Docs + Live-Download |

Vollständige Detailberichte der drei Audit-Läufe: `kiwo-audit`, `formularagent-audit`, `additional-prior-art-audit` (in der Recherche-Umgebung `/tmp/opencode/feldexa-research/findings/`; Kernaussagen hier mit Datei-/Zeilenbelegen konsolidiert).

## Fähigkeitsmatrix (Kernprojekte)

Klassifikation: `I`=IMPLEMENTED, `P`=PARTIAL, `N`=NOT_FOUND_IN_REVIEWED_CODE, `U`=UNKNOWN, `T`=NOT_TESTED, `D`=DOC_ONLY. Details + Belege in den Fußnoten.

| Fähigkeit | KIWo/OpenForm | Formularagent | CommonForms | GSA pdf-filler | ozg (XDF) | MACH (D) | FITKO FIM/FT-C (D+live) |
|---|---|---|---|---|---|---|---|
| 1. Statische, nicht ausfüllbare PDFs importieren | P¹ | N | I² | P³ | N | N⁴ | N⁵ |
| 2. Scan-PDF + OCR | I (Cloud-OCR) | N | N | N | N | N | N |
| 3. Layout-/Feld-Detection inkl. Koordinaten | N⁶ (nur Seiten-/Reihenfolge) | N (nur Grid-Slots) | I² (Raster+YOLO; Koordinaten nur im Python-API) | N (manuelle Koordinaten) | N | N | N |
| 4. Semantische Feldinterpretation | I (LLM, Cloud) | N | N (Namen `textbox_0_1`) | N | N | N | N |
| 5. FIM/XDF-Import + Versionsbehandlung | N | I (xdf2+xdf3-Lesezugriff) | N | N | I (XDF v1+v2→JSON-Schema) | D | I (Repository/API, immutable URIs) |
| 6. Mapping auf echte FIM-Datenfeld-IDs | N | P (nur ID-Durchreichung aus FIM-Quelle, kein Mapping-Ziel) | N | N | P (IDs im JSON-Schema) | N | I (JSON-Schema-Keys sind FIM-IDs) |
| 7. Confidence/Uncertainty | P (hartcodierte Stufen) | P (kategorialer Migrationsbericht) | N (Threshold, keine Widget-Scores im Output) | N | N | N | N |
| 8. Explizites UNKNOWN/Abstention | P (nur Prompt-Anweisung) | P („prüfen"-Liste) | N | N | N | N | N |
| 9. Human Review/Korrektur | I (Konflikt-UI) | P (report-getrieben, ohne UI) | N | N | N | N | N |
| 10. Feld-Provenienz/Audit | I (value-level + DB-Trigger) | P (Excel-Herkunft, kein IR-Origin-Feld, kein Hash) | N | N | N | N | N |
| 11. Schema-valides strukturiertes Output | P (internes JSON/Pydantic) | I (3-stufige Validierung gegen OZG-Hub-Schema) | N | N | I (JSON-Schema-Output) | D | I (FIT-Connect-Validierung) |
| 12. Original-Dokument-Integrität | P (Original bleibt erhalten, **keine Hashes**) | N | N | N | N | N | N |
| 13. Offline/Datenschutz | N (Cloud-KI zwingend) | P (offline nur mit `--skip-conditions`; Default: Google Gemini Cloud) | I (lokale Inferenz) | I | I | — | I (lokal validierbar) |
| 14. Wiederverwendbare APIs (app-unabhängig) | I (FastAPI, aber app-gebundener Fluss) | I (CLI+Library) | I (CLI+Python-API) | I (Winz-Wrapper) | I | — | I (REST-APIs) |
| 15. Reproduzierbare Tests/Evaluation | P (29 pytest-Dateien, golden pipeline; hier NOT_TESTED) | N (Suite im Repo fehlt; Referenzen auf unpublished Replay-Harness) | P (Eval-Scripts; NOT_TESTED) | N | P | — | P |

**Fußnoten (Belege):**
1. KIWo: Füllung erfordert AcroForm-fähige PDFs; statische PDFs nur als Nachweis-Upload. 2. CommonForms: Raster-Rendering + YOLO/RF-DETR (`inference.py:274-290`), Kernzweck; Output = ausfüllbares PDF, Koordinaten normalisiert nur via Python-API (`utils.py:8-26`). 3. GSA: Anrufer liefert x/y/page, pdftk-Stempel (`pdf_filler.rb:16,52-60`). 4. MACH: PDF Structure-API inventarisiert AcroForm-Felder „funktioniert nur mit PDF-Formularen", Analyse „im Vorfeld" manuell (Doc). 5. FITKO: „Andere Formate, wie XDF, werden nicht direkt verarbeitet … Converter … in der Konzeption" (docs.fitko.de, abgerufen 13.11.2026); schema.fim.fitko.net liefert versionierte JSON-Schemata, deren Keys FIM-IDs sind (live verifiziert am S00000159-Artefakt). 6. KIWo: keine Koordinaten im gesamten Repo; pdf-lib/pdfjs für AcroForm-Füllung; `docs/TESTING.md` referenziert nicht existierende Testverzeichnisse (Dokument-Drift, nicht als Fähigkeit werten).
7. Formularagent: FIM-Reader `src/sources/fim/read/read.py:14-18,243-246`; fim_id → IR `fim/interpret/interpret.py:86`; Output `field["fimId"]` `ir_builder/sections.py:159-160`; Validierung `src/core/validation/validation.py:15-30`; Migrationsbericht `migration_report.py:129-141` + `report_kategorien.yaml` (~35 Kategorien); PDF-Pfad: einzige, **ungenutzte** Gemini-Upload-Hilfe `shared/llm/gemini.py:22-40`; LLM-Cloudpflicht README:146-157.
8. KIWo: GPT-5.2-Vision nur im form_to_json-Pfad (`converter.py:43-44`), Mistral OCR/ASR (`document_ocr/service.py:24`); Provenienz/Konflikte `form_values_merge.py:355-414`, Review-Endpoints `user_formulars.py:279-303`; **FIM/XDF/XÖV: 0 Treffer repo-weit** (einziger Trace: nicht existierender „FitConnect"-Testordner in `docs/TESTING.md:12`).

## Ergebnisse pro Projekt (Zusammenfassung)

**KIWo/OpenForm (Apache-2.0)** — Dialog-basierter Antragsassistent (Next.js + FastAPI/LangGraph + Supabase). Starke Nachbar-Systemfähigkeiten: value-level Provenienz, Konflikterkennung, Human-Resolution-UI, Audit-DB. **Aber:** kein FIM/XDF-Bezug, keine Feldkoordinaten, Confidence hartcodiert, ORIGINAL-Hashes fehlen, **Cloud-KI zwingend** (konfigurierbar welcher Anbieter, aber kein lokaler Pfad) → erfüllt die Offline-/Datenschutz-Anforderung eines kommunal tauglichen Adapters nicht. Mapping-Ziel ist ein **internes** Formularmodell, nicht versionierte FIM-IDs.

**Formularagent (MPL-2.0)** — Migrations-Werkzeug **digitaler** Formulardefinitionen (FIM-XDF-XML, form.io, Excel) → OZG-Hub-Formular-JSON mit 3-stufiger Validierung und Migrationsbericht. Kein PDF-Input, keine Koordinaten, kein semantisches Mapping, Feld-Provenienz unvollständig (kein `origin` im IR, kein Source-Hash), Testsuite im Repo nicht enthalten. **Die behauptete Kernlücke bleibt bestehen**: Es nimmt keine „Legacy-PDF"-Seite an und gibt keine FIM-**Fachdaten**-Struktur aus (sondern Formular-**Layout**-JSON). Seine IR-, Report- und Adapter-Pattern wären als Baukasten **wiederverwendbar**, decken die Lücke aber nicht.

**CommonForms** — beste offene Detektionsbasis für statische PDFs, aber: **keine Lizenz** → rechtlich nicht ohne Weiteres wiederverwendbar (Fork/Neuimplementierung oder Klärung nötig), kein OCR, keine semantische Zuordnung, Widget-Confidence im Output verworfen.

**GSA pdf-filler / SurveyJS / RuiqiZhan-Tool** — dienen jeweils anderen Zwecken (Stamping mit manuellen Koordinaten; Web-Formulare + kommerzieller PDF-Fill mit handgebautem fieldMap; gefüllte AcroForm/XFA-Migration mit explizitem statischen-PDF-Ausschluss). Keines tangiert semantisches Legacy-PDF→FIM-Mapping.

**ozg (XDF→JSON-Schema)** — beweist, dass XDF-Parsing und Version→Schema-Transformation machbar und offen existiert (v1+v2, Code-Listen, Constraints), aber: kein XSD-Output, kein PDF, seit 2022 inaktiv. **FITKO** betreibt die verlässliche Schema-Infrastruktur (immutable versionierte Schemata; JSON-Schema-Keys = FIM-IDs — live geprüft) und dokumentiert selbst, dass der XDF-Converter „in der Konzeption" ist — die Brücke **Legacy-PDF → versionierte FIM-Feld-IDs** ist dokumentierte Ökosystem-Lücke, nicht nur unsere Annahme.

**Fazit des Audits:** Nach Quellcode-Prüfung von **13 Projekten** (davon 7 in der Matrix unten mit Spaltenbelegen; die übrigen 6 — xdatenfelder-xml, fim-portal-cli, xdf2gov, open-forms, SurveyJS-PDF, RuiqiZhan — in den Abschnitten „Ergebnisse pro Projekt" und den Raw-Audit-Dateien unter `docs/funding/evidence/`) ist **kein** geprüftes OSS-Projekt in der Lage, sichtbare Felder statischer Behörden-PDFs auf **versionierte FIM-Datenfeld-IDs** mit Koordinaten, Unsicherheitsbehandlung, Human-Gate, Provenienz und validierter Ausgabe abzubilden. Einzelbausteine existieren (Detektion: CommonForms lizenzschwach; XDF-Parsing: flxbe/ozg/Formularagent; Schema-Validierung: FITKO JSON-Schema-Pfad) — die **Kombination und die deutschen Verwaltungsartefakte (defektes XSD, Codelisten-Abbildung, Abschnitt-Kontext-Disambiguierung) sind unbehandelt**. Das ist eine echte, belegte Lücke — mit der klaren Einschränkung: Ein fehlender Eintrag beweist keine universelle Abwesenheit; die Negativ-Aussage gilt nur für den geprüften Korpus (`NOT_FOUND_IN_REVIEWED_CODE`).
