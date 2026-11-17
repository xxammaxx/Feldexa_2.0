# FormBridge — Technische Forschungsspezifikation (eigenständiges Modul)

**Datum:** 13.11.2026 · **Charakter:** Spezifikation für ein künftig zu entwickelndes, unabhängiges Infrastruktur-Modul. **KEINE Implementierungsanweisung** für das Feldexa-2.0-Produkt und keine Vorab-Förderleistung. Referenzhypothesen: `innovation-assessment-formbridge-2026-11-13.md`.

## 0. Abgrenzung

- Eigenständige Codebasis (eigenes Repo), keine Abhängigkeit von der Feldexa-App, keine UI-Pflicht (CLI + Library + maschinenlesbare Artefakte).
- **Nicht** im Förderzeitraum erbrachte Vorarbeit (Feldexa-Produkt, OCR-PoCs, dieser Recherchebericht) wird nicht als Förderleistung deklariert; bis Förderbeginn (01.06.2027) unabhängig entstehender Produktcode bleibt separater Produktentwicklung.
- RepairProbe unberührt.

## 1. Modulzweck und Forschungsfragen (RF)

Lokal betreibbare FOSS-Komponente, die sichtbare Felder statischer (nicht ausfüllbarer) Behörden-PDFs mit versionierten FIM-Datenfeld-Identifikatoren verbindet — mit nachprüfbarer Unsicherheit, menschlicher Freigabe und maschinenlesbarer Provenienz.

- **RF1 (Disambiguierung):** Wie genau kann Abschnitts-Kontext (Seitenregion, Überschriften, Frage-Antwort-Blöcke) semantische Zuordnungen auf FIM-Feldpfade auflösen? Messgrößen: Feld-Precision/Recall vs. Goldstandard, Anteil korrekt als UNKNOWN markierter Fälle.
- **RF2 (Schema-Hygiene):** Lassen sich defekte amtliche XSD-Artefakte (Nachweis: Referenzfall §3, 170 Parser-Fehler in S00000159v1.4) deterministisch normalisieren und die Normalisierung maschinenprüfbar dokumentieren? Messgrößen: Compile-Erfolg über einen Korpus von N FIM-Schemata, 100 % nachvollziehbare Reparaturprotokolle.
- **RF3 (Provenienz):** Reicht ein offenes Provenienz-Artefakt (Hashes, Koordinaten, Zielpfade, Schema-Variante, Review-Entscheid) aus, um jede Ausgabe unabhängig zu reproduzieren und jede manuelle Änderung zu erkennen? Messgrößen: Reproduzierbarkeitsrate, Manipulations-Erkennungsrate im Negativtest.
- **RF4 (Aufwand):** Welcher menschliche Review-Aufwand (Zeit/Korrektur je Feld) bleibt bei Ziel-Precision ≥ 0,95 gegenüber vollautomatischer Zuordnung?

## 2. Ein-/Ausgaben

**Eingaben**
1. Statisches PDF (nicht ausfüllbar, born-digital mit Textlage). **Scans/OCR sind im Förderzeitraum vollständig außerhalb des Scopes** (siehe Risiken); das Adapter-Interface ist so entworfen, dass ein späterer OCR-Adapter andocken kann, ohne das Kernmodul zu ändern.
2. FIM-Schema-Referenz: XSD-URL (immutable) **oder** lokale XDF/XSD-Datei + Zielversion; das Modul lädt, hash't und normalisiert.
3. Optional: Referenz-Goldstandard (JSON, siehe `docs/funding/evidence/reference-dataset.json` als Formatvorlage).

**Ausgaben**
1. **Mapping-Kandidaten** (JSON): je erkanntem Feld → Feld-ID (lokal), Seite+Koordinaten, sichtbares Label, 0..n Kandidaten `{fim_path, fim_id, schema_version, confidence, rule_ids, state: PROPOSED|UNKNOWN|REJECTED}`.
2. **Review-Entscheid-Datei** (JSON): je Kandidat `{accepted/rejected/corrected, actor, timestamp}` — human-in-the-loop-Pflicht für alle Zustände ≠ eindeutig-hoch.
3. **Provenienz-Artefakt (FormBridge Manifest, versioniertes JSON-Format FB-1):** SHA-256 von Quell-PDF, Schema-Datei(en), Normalisierungsprotokoll (Struktur-Diff), verwendete Regelversion(en), alle Review-Entscheid-Hashes.
4. **Strukturierter Datensatz** (XML gegen normalisiertes XSD; optional JSON gegen FITKO-JSON-Schema) + Validierungsprotokoll (Validator, Fehlerliste, Ergebnis).
5. **Abdeckungsbericht:** nicht abbildbare PDF-Felder (COVERAGE_GAP), Schema-Felder ohne PDF-Gegenstück, Codelisten-Abbildungsprotokoll.

## 3. Schnittstellen (vorschlag, nicht Implementation)

```
formbridge map     --pdf <file> --schema <uri|file> [--profile <formfamilie>] --out <dir>
formbridge review  --candidates <dir> [--interactive|--batch <decisions.json>]
formbridge emit    --reviewed <dir> --validate [--xsd-normalized <file>]
formbridge verify  --manifest <fb-1.json> [--inputs-dir <dir>]   # unabhängiger Prüfer
formbridge schema  normalize --in <xsd> --out <xsd> --report <json>   # Schema-Hygiene (RF2)
```
Bibliotheks-API: `load_pdf()`, `detect_fields()`, `propose_mapping()`, `apply_review()`, `emit()`, `verify()` — jeder Schritt einzeln aufrufbar, IO-Konventionen wie oben; keine versteckten Zustände.

## 4. Architektur-Grenzen

```
[PDF]→(1 Erkennung: Textlage-Extraktion + Layout-Segmentierung; Scan: externes OCR-Adapter)
     →(2 Kontext-Analyse: Abschnitte/Überschriften/Frageblöcke)
     →(3 Zuordnungs-Engine: Regelkatalog + Codelisten + optionales kleines lokales ML-Modell;
        Ausgabe ausschließlich Kandidaten+Confidence, nie stillschweigende Entscheidung)
     →(4 Review-Gate [menschlich])
     →(5 Emit: Datensatz + FB-1-Manifest + Abdeckungsbericht)
     →(6 Validate: normalisiertes XSD / FITKO JSON-Schema)
     →(7 Verify: unabhängiger Manifest-Prüfer, ohne Feldexa-Abhängigkeit)
```
Regeln (3) werden als **datengetriebener, versionierter Regelkatalog** (YAML/JSON) geführt — nachprüfbar, nicht in Code versteckt. Regelkatalog enthält pro Regel: Auslöser (Label-/Kontextmuster), Ziel-Muster (FIM-Pfad-Muster), Confidence-Beitrag, Belegbeispiele (Referenzdatei+Koordinate).

## 5. Technische Risiken (offen, ehrlich)

| Risiko | Bewertung | Gegenmaßnahme |
|---|---|---|
| Keine lizenzsichere, offene Feld-Detektionsbasis (CommonForms ohne LICENSE) | hoch | Eigenes Detektionminimum (regelbasiert auf Textlage für Vordruckklasse A „born-digital mit Linien/Unterstreichungen"); Detektion für reine Scans bewusst **außerhalb** des 6-Monats-Scope |
| FIM-Schemata weiterer Verfahren sind ebenfalls defekt (unbekannte Defektklassen) | mittel-hoch | RF2-Korpus über ≥5 Verfahrensschemata; Normalisierer als eigenständiges, unabhängig nützliches Ergebnis |
| Fachliche Falschzuordnung (Geldbeträge, Identitäten) mit Realwirkung | hoch | Kritische Kategorien (Betrag/Identität/Pflichtfeld) erhalten hartes Review-Gate + UNKNOWN-Default; Fehlzuordnungen werden im Goldstandard doppelt gewichtet |
| Codelisten-Mapping fachlich falsch (z. B. Staatscodes) | mittel | Codelisten werden aus Schema-Facetten + FIM-Portal-Referenzen gebunden und im Manifest ausgewiesen; keine improvisierten Zuordnungen |
| Schema-/Verfahrens-Vielfalt (Landesausprägungen) sprengt Scope | hoch | Scope bewusst: **1 Verfahrens-Familie (Wohngeld Mietzuschuss Erstantrag)** + Nachweis der Generalisierbarkeit über Schema-API (nicht über viele Verfahren) |
| „LLM-Magie" untergräbt Reproduzierbarkeit | mittel | ML optional und nur lokal; jede Zuordnung über regel_id-Nachvollziehbarkeit aufführbar; Cloud-Abhängigkeit ausgeschlossen |
| **Einwand „das lässt sich in einem Wochenende mit GPT bauen"** | mittel | Widerlegung per Messziel: Kontext-Disambiguierung (≥6 Mehrfachkontexte im Referenzfall), Codelisten-Fehlerkritik, deterministische Schema-Normalisierung (170 Fehler-Klassen) und manipulationsfestes Provenienz-Format sind messbare Qualitätsanforderungen, die ein Ad-hoc-Skript nicht erfüllt — die 6 Monate sind auf diese Messungen verpflichtet, nicht auf Funktionsumfang |
| **Einwand „FITKO liefert doch bereits JSON-Schemata mit FIM-IDs — wozu XSD normalisieren?"** | mittel | JSON-Schema-Pfad bleibt als Ausgabeformat (§2.4) erhalten und wird genutzt; die XSD-Normalisierung ist ein **eigenständiger, unabhängig nützlicher Beitrag** (RF2), weil viele Verwaltungs-XML-Toolchains und Fachverfahren XSD-basiert sind und das amtliche Artefakt nachweislich nicht kompilierbar ist — kein „XSD statt JSON", sondern „beides, mit dokumentierter Hygiene" |

## 6. Messbare Abnahmekriterien (Ende der 6 Monate)

1. Referenzfall Fürth ↔ S00000159v1.4: Feld-Precision ≥ 0,95 / Recall ≥ 0,90 auf ≥ 200 annotierten Feldern (Goldstandard synthetisch; Referenz-PDF wiederbeschaffbar via URL+Hash) **und auf ≥ 1 zurückgehaltenem Dokument** (Wohngeld-Variante eines anderen Landes, gegen das der Regelkatalog nicht entwickelt wurde); **0 unbeabsichtigte** kritische Fehlzuordnungen (Identität/Betrag/Pflichtfeld) in der Endausgabe; alle Restrisiken als UNKNOWN/Review ausgeflaggt.
2. Schema-Hygiene: Normalisierer kompiliert ≥ 5 amtliche FIM-XSDs inkl. S00000159v1.4 (vorher: 0/5) mit vollständigen, maschinenlesbaren Reparaturprotokollen.
3. Emit+Validate: synthetische Datensätze validieren gegen normalisiertes XSD; Manifest-Verifikation reproduziert 100 % der Artefakte; ≥ 10 dokumentierte Manipulations-Negativfälle werden zuverlässig erkannt.
4. Review-Messung (RF4): Median-Review-Zeit je Feld dokumentiert, gemessen durch **2–3 externe Testpersonen** (nicht durch die Entwickler); Ziel < 15 s/Feld für UNKNOWN-freie Restmenge (Messung, kein Leistungsversprechen).
5. FOSS: Modul + Regelkatalog + Goldstandard-Format unter offener Lizenz (OSI, kompatibel zu MPL-2.0/Apache-2.0-Ökosystem); CI mit reproduzierbaren Tests; Dokumentation auf Deutsch+Englisch.
6. **Negativabgrenzung:** Der Prototyp läuft ohne Feldexa-App, ohne Cloud-Dienst, ohne Behördenübertragung — nachweisbar in CI.

## 7. Sechs-Monatsplan (Standalone-Modul, unabhängig vom Produkt)

| Monat | Fokus | Meilenstein |
|---|---|---|
| 1 | Format FB-1, PDF-Textlage-Extraktion, Schema-Laden+Hash+Normalisierung (RF2-Kern) | FB-1-Spezifikation v1; S00000159 normalisiert+kompiliert in CI |
| 2 | Regelkatalog v1 (Antragsteller-/Wohnung-Abschnitte), Kandidaten-Engine, Confidence-Modell | Erste End-to-End-Kandidaten auf Referenz-PDF, UNKNOWN-Mechanik |
| 3 | Goldstandard ≥ 200 Felder (synthetisch), Review-CLI, Codelisten-Bindung; **Rekrutierung von 2–3 externen Testpersonen** | Precision/Recall-Baseline veröffentlicht |
| 4 | Disambiguierung mit Abschnittskontext (RF1), kritische Kategorien-Hard-Gates, Erarbeitung des **Held-out-Dokuments** (andere Landes-Variante) | RF1-Messung, Fehlkategorien-Analyse |
| 5 | Emit+Validate+Verify (RF3), Manipulations-Negativtests, ≥ 5 FIM-Schemata (RF2-Korpus) | Reproduzierbarkeits-/Erkennungsraten |
| 6 | Review-Zeit-Messung (RF4), Dokumentation, FOSS-Release, Bericht zu allen RFs | Abnahmekriterien §6 geprüft; Demo ohne Produkt/App |

Jeder Meilenstein erzeugt nachprüfbare Artefakte (Tests, Berichte, Messwerte). Keine Behördenübermittlung, keine Echtdaten, keine App-Abhängigkeit.
