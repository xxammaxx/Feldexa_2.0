# Referenzfall: Fürther Wohngeld-PDF ↔ FIM S00000159 v1.4 — vollständiger Quellen- und Validierungstest

**Datum:** 13.11.2026 · **Status:** DURCHGEFÜHRT (erstmals vollständig, inkl. XSD-Parsing und Schema-Validierung)
**Bezug:** Issue #167 (Recherche), Issue #165 (Pilot), ersetzt die dortigen `NOT_RUN`/`BLOCKED`-Befunde vom selben Tag (Netzzugriff war im vorherigen Container nicht gegeben).

## 1. Quellen, Hashes, Retrieval

| Artefakt | URL | Abruf (UTC+1) | SHA-256 | Ergebnis |
|---|---|---|---|---|
| Amtlicher Wohngeldantrag (nicht ausfüllbar), Stadt Fürth | https://www.fuerth.de/fileadmin/redaktion/01-Rathaus/Formulare/Nicht-Ausfuellbar/2026-02-13-Vordruck-Wohngeldantrag.pdf | 13.11.2026 | `57f4f3f98671a3c659f131cfd6d58abf5eb80a0a2c585ddd575761fe60c21463` | PDF 1.6, 8 Seiten A4 (595,32 × 841,92 pt), Creator: Bayer. Staatsministerium für Wohnen, Bau und Verkehr (Word 2010), Erzeugt 2018-04-13, Modifiziert 2022-12-05 |
| FIM-Strukturschema S00000159 v1.4 (immutable) | https://schema.fim.fitko.net/immutable/schemas/S00000159V1.4_2024-01-22-1705942219513.xsd | 13.11.2026 | `36250e69a5954b6e233f49a75c021e5cf2cf69a6f26a72c59829fc496ecda6d3` | XSD, targetNamespace `urn:xoev-de:xfall:standard:fim-s00000159_1.4`, version="1.4", Root-Element-Name „Wohngeld Mietzuschuss - Erstantrag", id `fim.S00000159V1.4` |

**Hinweise zur rechtlichen/technischen Zugänglichkeit:** Beide Quellen wurden über die offiziellen, öffentlich veröffentlichten URLs ohne Login/Bypass bezogen. Das PDF ist mit Owner-Passwort vs. Kopieren (AES, `copy:no`) versehen; der Textlayer ist dennoch mit Standard-Tooling (`pdftotext`, poppler) extrahierbar — die Beschränkung ist dokumentiert, nicht umgangen. Die PDF-Bytes werden **nicht** in dieses Repository committet; Referenz erfolgt über URL+SHA-256. **Archivierungslücke (offen):** Fällt die Fürther URL oder ändert sich die Datei, verliert der Goldstandard seine Quelle — vor Antragstellung sollte der Maintainer eine rechtssichere Archivierung (z. B. eigenes Rights-cleared Deposit / Webarchiv-Snapshot mit Hash-Nachweis) veranlassen. Die bearbeitete XSD-Kopie unter `docs/funding/evidence/` dient der Reproduzierbarkeit (FIM-Schemata werden von FITKO als frei nutzbare Verwaltungsartefakte via immutable-URL bereitgestellt; Lizenzangabe im Schema-Artefakt selbst nicht vorhanden — vor Weiterverbreitung im Förderfall nochmal klären).

## 2. PDF-Analyse: tatsächlich statisch, keine Scan-Verarbeitung nötig

- `/AcroForm`-Marker 1× vorhanden, aber **0 Widget-Annotationen, 0 Formularfelder** (`/Tx` 0, `/Annots` 0) → der Vordruck ist ein echter **statischer, nicht ausfüllbarer** PDF-Druckbogen (der AcroForm-Marker ist ein Word-Export-Rest ohne Felder).
- **Born-digital mit Textlage:** Text in 8 Seiten extrahierbar (23.624 Zeichen inkl. Leerzeichen/Umbrüche, gemessen als `pdftotext <pdf> - | wc -c`; ~20.100 Nicht-Leerzeichen); Wort-/Zeilenkoordinaten via `pdftotext -bbox-layout` reproduzierbar (A4-Punktraster). Für die hier geprüfte Referenzdatei ist **kein OCR** nötig; OCR bleibt Produktpfad für echte Scans (separates Risiko, hier nicht bewertet).

## 3. XSD-Analyse: Struktur, Abdeckung — und drei schwerwiegende Generator-Defekte

Inhaltlich (extrahiert nach `docs/funding/evidence/fim-fields-S00000159V1.4.json`):
640 Knoten, davon 185 Gruppen (G*) und 88 Datenfelder (F*) mit FIM-Labels; Elementnamen sind die FIM-Feld-IDs. 10 Top-Level-Pflichtabschnitte (Gesetzl. Vertreter, Antragsteller, Wohnung, Haushaltsmitglieder, Veränderungen, Miete, zusätzliche Nutzung, Zahlung, Hinweise, Signatur). 226 von 420 Elementdeklarationen sind per Default (`minOccurs`-Default 1) **pflicht**, 191 optional, 3 explizit required.

**Fachliche Deckung PDF ↔ Schema (Details: `reference-dataset.json`, 30 Referenzfelder):**
- **7/30 eindeutig mappbar** (z. B. IBAN → `F60000288V1.2`, Heizkosten → `F00001720V1.3`)
- **7 CONTEXT_REQUIRED** — gleiche Feld-IDs in ≥6 Abschnitten (Name/Vorname für Antragsteller, gesetzl. Vertreter, Betreuer, Haushaltsmitglieder, Unterhalt, Verpflichtungserklärung); die Seitenposition im PDF entscheidet über den Zielpfad
- **4 VALUE_CODELIST** — PDF-Checkboxen/Freitext → FIM-Enums (Geschlecht `{d,m,w,x}`, Staatsangehörigkeit ISO-numerisch `276`, Familienstand `{001..007}`, Mietverhältnis)
- **4 STRUCTURAL_*** (Expansion/Mismatch) — z. B. PDF-Zeile „Anschrift" → 4 FIM-Felder; PDF „Geburtsdatum" (1 Datum) → 3 Integer-Felder
- **2 AMBIGUOUS_SEMANTIC** — „Warmmiete" ↔ `F00000240V1.5 „Höhe der Miete"` (Kalt/Warm-Semantik im Schema nicht ausgewiesen); genutzte Teilfläche ↔ `F00000563V1.5 „Größe der Wohnung"`
- **3 COVERAGE_GAP (fachlich relevant):** Vermieter-Identität (Name/Anschrift) ist **nicht repräsentierbar** (Schema kennt nur G00001522 Verwandtschaftsverhältnis); Antragstyp (Erst-/Weiterleistungs-/Erhöhungsantrag) fehlt als Feld; „geminderte Kaltmiete" fehlt
- **3 UNMATCHED** — Wohngeldnummer, Eingangsstempel/Behördenanschrift (Behörden-Metadaten, bewusst kein Fachdaten)

**Technische Schema-Defekte (reproduzierbar mit `xmllint --noout --schema`):**

| Defekt | Anzahl | Beispiel/Evidenz |
|---|---|---|
| D1: Root-Element-Name kein NCName (Leerzeichen/Bindestrich) | 1 | `name="Wohngeld Mietzuschuss - Erstantrag"` → „not a valid value of the atomic type 'xs:NCName'" |
| D2: `type`-Attribut **und** inline `<xs:simpleType>` gleichzeitig (verboten) | 169 | z. B. `<xs:element minOccurs="0" name="F00000646V1.2" type="xs:string"><xs:annotation>…</xs:annotation><xs:simpleType>…` |
| D3: Referenzierte Typ-Definitionen fehlen komplett | 21 | `F00002098V1.2`, `F00002599V1.1`, `F00000655V1.3`, `F00001851V1.3`, `F00002495V1.1`, `F00002578V1.2`, `F00002579V1.2`, `F00002582V1.0`, `F00002616V1.1`, `F00002484V1.1`, `F00000650/651/652/656/657/658…` |
| D4: PCRE-Anker (`$`/`^`) in XSD-Regex-Facetten — unter XSD-Semantik **literale Zeichen** | 4 | E-Mail-Pattern `…{1,63}$` verwirft gültige Adresse `max@example.com` |

**Konsequenz:** Das offizielle immutable XSD ist mit einem standardkonformen XSD-1.0-Prozessor **nicht kompilierbar** (170 Parser-Fehler mit libxml2/xmllint; Anzahl kann je nach Prozessorgeneration minimal variieren). „Schema-validen Output gegen die Original-XSD" kann kein Adapter leisten. Nach **dokumentierter, deterministischer Normalisierung** (D1: Root umbenennen; D2: `type`-Attribut bei inline simpleType entfernen; D3: 21 fehlende Typen als `xs:string`-Stubs; D4: Anker entfernen) kompiliert das Schema — Reproduktion: `docs/funding/evidence/S00000159V1.4-repaired.xsd` + `synthetic-instance.xml` (`xmllint --noout --schema S00000159V1.4-repaired.xsd synthetic-instance.xml` → valid).

**Ergebnis der End-to-End-Synthese-Validierung:** Eine synthetische XML-Instanz (nur Fantasiedaten, u. a. alle 10 Pflichtabschnitte, 30 Referenzfelder) wurde generiert und validiert → **PASS** (gegen normalisiertes Schema, nicht gegen das Original — das Original ist defekt). Alle Werte sind synthetisch; keine personenbezogenen Echtdaten.

## 4. Beweisbare Aussagen und Grenzen

**Verifiziert (durchgeführte Befehle, Artefakte im evidence-Ordner):**
- PDF statisch, Textlage, 8 Seiten, Hashes (siehe §1)
- XSD-Defekte D1–D4 mit Fehlerzahlen; Normalisierung deterministisch; Instanz-Validierung PASS
- FIM-Feldbaum und Abdeckungsanalyse gegen tatsächliche PDF-Textkoordinaten (`pdftotext -bbox-layout`)

**Nicht behauptet werden darf:**
- „Schema-valid" gegen die **Original**-XSD (defekt) — nur gegen dokumentiert normalisierte Variante
- Vollständigkeit: 30 Referenzfelder sind eine Stichprobe von ~200+ Formularfeldern des Vordrucks
- Fachliche Korrektheit der FIM-Labels: Codelisten (z. B. Staatsangehörigkeit 276, Geschlecht `m`) wurden aus den Schema-Facetten übernommen, **nicht** gegen FIM-Portalfachtenweisungen verifiziert
- Der Fürther Vordruck (Stand „Januar 2023", Bayer. Ministerium als Autor) ist eine **Landes-/Kommunalausprägung** des bundeseinheitlichen Wohngeld-Vordrucks; die FIM-Abdeckung gilt für diese Ausprägung, nicht pauschal für alle Bundesländer-Varianten

## 5. Konsequenz für Issue #165 (separat autorisierter Produkt-Pilot)

Die Feldexa-2.0-Produktpipeline bleibt für den echten App-E2E-Pilot **NOT_RUN** (Recognition-/Export-Packages sind auf main weiterhin `.gitkeep`; kein Flutter-SDK in dieser Umgebung). Dieser Bericht ändert daran nichts und implementiert keine Produktfunktion; er liefert aber den **Referenzdatensatz + Validierungsartefakte**, die der Pilot nach dessen Freigabe direkt wiederverwenden kann.
