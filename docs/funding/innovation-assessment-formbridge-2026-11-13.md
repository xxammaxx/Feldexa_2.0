# Innovationsbewertung FormBridge — aktive Falsifikation, Bilanz nach Quellcode-Audit

**Datum:** 13.11.2026 · **Bezug:** Issue #167 · Stand nach Prior-Art-Quellcode-Audit + Referenzfall-Validierung (gleiches Datum)

## 1. Was ist bereits gelöst? (mit Beleg)

| Baustein | Status | Beleg |
|---|---|---|
| PDF-Feld-Detektion in statischen PDFs | gelöst (technisch), **lizenzlich ungeklärt** | CommonForms `f5f4007` (Raster+YOLO/RF-DETR); keine LICENSE-Datei |
| OCR von Scans | gelöst (kommerziell/cloud) | KIWo bindet Mistral/GPT-Vision; kein lokaler offener Pfad geprüft |
| XDF/FIM-Schema-Import, versionierte Schemata | gelöst (Infrastruktur) | FITKO-Sammelrepository, immutable URIs; flxbe/xdatenfelder-xml (EUPL); Formularagent xdf2/3-Reader |
| XDF→JSON-Schema-Transformation | gelöst (drittanbieter, inaktiv) | LilithWittmann/ozg `e6732e5` (XDF v1+v2) |
| Schema-Validierung von Übermittlungen | gelöst (JSON-Schema-Pfad) | FIT-Connect-Dokumentation + live JSON-Schemata (Keys = FIM-IDs) |
| Migration digitaler Formulardefinitionen + Bericht | gelöst (digital↔digital) | Formularagent `4085c46` (FIM/form.io/Excel → valides Formular-JSON + Migrationsbericht) |
| PDF→PDF-Füllen mit manuellen Koordinaten | gelöst | GSA pdf-filler (MIT) |
| Human-Review-UI für Extraktionskonflikte | gelöst (app-gebunden) | KIWo (Apache-2.0) |

## 2. Was ist technisch ungelöst? (nach Audit + Referenzfall)

1. **Die Brücke selbst:** kein geprüftes Projekt mappt sichtbare Felder **statischer** Behörden-PDFs auf **versionierte FIM-Datenfeld-IDs** (Referenz: `prior-art-audit-2026-11-13.md`, Matrix). Formularagent nimmt kein PDF an und gibt Fachdaten-IDs nur durchreichend aus; KIWo hat null FIM-Bezug; FITKO dokumentiert den XDF-Converter als „in der Konzeption".
2. **Abschnitts-Kontext-Disambiguierung:** gleiche Labels (Name/Vorname/Geburtsdatum) treten im Fürth-Vordruck in ≥6 fachlichen Kontexten auf; im FIM-Schema sind es dieselben Feld-IDs an verschiedenen Pfaden (Referenzfall: 7/30 Felder `CONTEXT_REQUIRED`). Öffentliche Ansätze (LLM-Prompts bei KIWo) lösen das nur app-intern, ohne nachprüfbare Regel/Confidence.
3. **Strukturtransformation:** PDF-Zeile → Feld-Gruppen (Anschrift→4 Felder; Geburtsdatum→3 Integer; Tabellenzeilen→wiederholbare Gruppen) ist ungelöst und fehlerkritisch (4/30 `STRUCTURAL_*`).
4. **Codelisten-Abbildung:** PDF-Checkbox-Freitext ↔ FIM-Enums (Geschlecht `{d,m,w,x}`, ISO-Staatscodes, Familienstand `{001..007}`) — trivial klingend, aber fehlerkritisches Mapping ohne offene Referenzdaten (4/30).
5. **Defekte amtliche Schemata:** Das offizielle immutable XSD S00000159V1.4 ist standardkonform **nicht kompilierbar** (170 Parser-Fehler: NCName, 169× type+simpleType-Konflikt, 21 fehlende Typen, 4 PCRE-Anker). „Schema-validen Output" garantiert niemand — ein Adapter braucht eine dokumentierte Schema-Hygiene-/Normalisierungsschicht. Das ist ein **neu entdecktes, nachweisbares Problem im Ökosystem selbst** (Referenzfall §3).
6. **Fachliche Deckungslücken mit Entscheidungsrelevanz:** Vermieter-Identität, Antragstyp, geminderte Kaltmiete sind im Schema S00000159v1.4 nicht repräsentiert (3/30 `COVERAGE_GAP`) — ein Adapter muss „nicht abbildbar" **ausweisbar** machen statt stillschweigend zu verlieren.
7. **Maschinenprüfbare Provenienz über die Kette** (PDF-Bytes → Feldkoordinate → Zielpfad + Schema-Variante + Review-Entscheid): existiert in keinem geprüften Projekt als reproduzierbares, unabhängig validierbares Artefakt.
8. **Offline/Datenschutz:** KIWo (der einzige mit ähnlicher Zielrichtung) **erfordert Cloud-KI**; ein lokaler, freier Pfad ist unbelegt.

## 3. Welche Hypothese überlebt die Falsifikation?

**Verworfen (breit):** „Legacy-PDF → semantisches Modell → standardisierte Formulardaten ist neu" — nein, Einzelbausteine existieren; auch „ein FIM-Adapter mit Auditbericht" wäre gegen Formularagent nicht haltbar (dokumentierte Funktionen genügen bereits zur Abgrenzungspflicht).

**Überlebt (eng, als Forschungs- und Entwicklungsfrage — nicht als „es gibt noch nie"):**

> **FormBridge-Narrow:** Ein wiederverwendbares, lokal betreibbares FOSS-Modul, das für statische Behörden-PDFs (1) Feldgeometrie + sichtbare Labels extrahiert, (2) Kandidaten-Zuordnungen auf versionierte FIM-Datenfeld-IDs mit **Konfidenz und explizitem UNKNOWN** erzeugt, (3) Mehrdeutigkeiten über **Abschnitts-Kontext + reproduzierbare Regeln** auflöst und Restrisiken als Review-Gate ausweist, (4) ein **maschinenlesbares Provenienz-Artefakt** (PDF-Hash, Koordinate → Zielpfad, Schema-URI + Schema-Variante/Normalisierungsschritte, Review-Entscheid) erzeugt, (5) gegen eine **dokumentiert normalisierte** FIM-Schema-Variante validierte, strukturierte Ausgabe liefert — validiert am realen Referenzfall Fürth ↔ S00000159v1.4.

Der Unterschied zu allem Geprüften ist nicht „PDF lesen" oder „FIM kennen", sondern die **nachprüfbare Kette inkl. des amtlichen Schema-Defekt-Problems**, die öffentlich nirgends existiert. Formulierung bewusst ohne „Neuartigkeits"-Behauptung über das gesamte Feld; Negativ-Aussagen sind auf den geprüften Korpus begrenzt.

## 4. Was könnte die Hypothese (noch) widerlegen?

- Ein Projekt, das genau (2)–(5) umsetzt und wir übersehen haben (z. B. proprietary Govtech wie MACH-Internas, nicht-öffentliche Verwaltungscodebasen) → Gegenmaßnahme: Suche im openCode/EU-OSS-Katalog + FITKO-Kontext bis zur Antragstellung fortführen.
- FITKO liefert 2027 einen produktiven XDF-Converter + PDF-Seite → Teil der Lücke fällt weg → Gegenmaßnahme: Modulgrenzen so setzen, dass die Provenienz-/Review-/Normalisierungsschicht unabhängig davon Wert hat.
- CommonForms klärt Lizenz nicht → Detektion muss eigenständig (klein, regelbasiert + kleines lokales Modell) oder aus lizenzierter Quelle kommen — Machbarkeitsrisiko, siehe Modul-Spezifikation §Risiken.
- Feldexa-eigene Product-Roadmap implementiertRecognition zufällig vor Förderbeginn → Abgrenzungspflicht (Modul ist app-unabhängig, eigene Codebasis, eigentliche Repo-Trennung geplant).

## 5. Ist der verbleibende Beitrag substanziell genug?

**Ja, unter Bedingungen.** Die verbleibende Arbeit ist kein „Feature", sondern ein abgegrenzter Infrastruktur-Baustein mit messbaren Forschungsfragen (Disambiguierungs-Genauigkeit, UNKNOWN-Anteil, Review-Aufwand, Schema-Hygiene-Testkorpus). Substanz ergibt sich aus drei nachweisbaren Lücken: Kontext-Disambiguierung mit Provenienz, schema-hygienische Validierung (neu entdecktes amtliches Defekt-Problem), und offline-fähige FOSS-Kette. **Nicht** substanziell wäre: reines Verketten vorhandener CLIs ohne die Provenienz-/Confidence-/UNKNOWN-Architektur — das wäre integration, keine förderfähige Neuentwicklung; entsprechend eng ist die Spezifikation geschnitten (`formbridge-module-spec-2026-11-13.md`).

**Empfehlung hieraus:** `CONDITIONAL_GO` — Bedingungen in `decision-report-formbridge-2026-11-13.md`.
