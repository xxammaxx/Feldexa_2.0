# Prototype-Fund-Machbarkeit (Förderlinie Innovation) — quellenbasierte Einschätzung

**Datum:** 13.11.2026 · Alle Förderangaben am 13.11.2026 aus offiziellen Quellen abgerufen und hier zitiert. Interpretationen sind als solche markiert. **Keine Förderzusage oder Förderfähigkeit wird behauptet.**

## 1. Verifizierte Rahmenbedingungen (offizielle Quellen)

| Punkt | Verifiziert (Quelle, abgerufen 13.11.2026) |
|---|---|
| Bewerbungsfenster Innovation | **01.10.–30.11.2026, 15:00 CET**; Portal: https://bewerben.prototypefund.de/ ; Details: https://www.prototypefund.de/bewerbung/details |
| Förderlinie Innovation | „innovative Softwareideen in den Bereichen Datensicherheit und Software-Infrastruktur" (https://www.prototypefund.de/innovation) |
| Förderperiode regulär | **01.06.2027–30.11.2027** (6 Monate) (details-Seite) |
| Second Stage (optional) | 01.12.2027–31.03.2028 (4 Monate); Konzept muss **zur initialen Bewerbung** vorliegen (details-Seite) |
| Fördersumme | bis 47.500 € Einzelperson / 95.000 € Team (≤4, GbR) + 31.667 €/63.333 € Second Stage (details-Seite) |
| Antragsteller | über 18; solo: Wohnsitz Deutschland; Team: GbR-Sitz Deutschland (innovation-Seite) |
| Lizenz | Veröffentlichung unter Freier/Open-Source-Lizenz **Pflicht** (innovation-Seite) |
| Sprechstunden | 16.11.2026 17:00 (allgemein), 19.11.2026 (FLINTA*) (details-Seite) |
| Bestehende Projekte | **ausdrücklich zulässig**: „Einige Geförderte arbeiten schon lange an dem Projekt … völlig in Ordnung"; **ABER**: „deutlich zu machen, wie sich der zu fördernde Teil klar vom Projekt abgrenzt. Es kann sich z. B. um ein neues Feature oder Modul handeln — eine ‚Verbesserung der bestehenden Software' ist nicht ausreichend" (Handbuch Jahrgang 03: https://www.prototypefund.de/uploads/Publikationen_und_Onepager/PTF_Handbuch_2026.pdf, S. „Stand des Projektes") |
| Entwicklungsanteil | „nur Projekte mit einem hohen Entwicklungsanteil … ‚nur' Dokumentation, Release und Marketing … nicht förderfähig" (Handbuch 2026) |
| Innovationsbegriff | schließt ausdrücklich „ein neues Modul für eine bestehende Software entwickeln" und „bereits Bestehendes in neuen Kontexten einsetzen" ein (https://www.prototypefund.de/innovativ) |
| Innovationskriterien | Datensparsamkeit, Anwendungsfreundlichkeit, Adaptierbarkeit, Open Source (innovativ-Seite) |
| Träger | OKF Deutschland, gefördert vom BMFTR (FKZ 16IS24086) |

## 2. Passung der FormBridge-Hypothese zur Linie Innovation

**Passung hoch (begründet, nicht garantiert):**
- **Software-Infrastruktur:** FormBridge ist app-unabhängiges, wiederverwendbares Modul mit CLI/Library/Verify — Kernbegriff der Linie (innovation-Seite).
- **Datensparsamkeit/Datenschutz:** lokal betreibbar, keine Cloud-Pflicht, keine Behördenübermittlung, UNKNOWN-Default statt aggressiver Auto-Zuordnung (innovativ-Seite-Kriterien 1–3).
- **Neues Modul für bestehende Software:** genau der vom Handbuch/innovativ-Seite benannte zulässige Fall; Abgrenzung dokumentiert (`innovation-assessment-…`, Modul-Spezifikation §0).
- **Gesellschaftlicher Nutzen:** Medienbruch-Abbau bei Sozialleistungsanträgen (Wohngeld) — eGovernment MONITOR 2026 (D21): 50 % letztes Anliegen vollständig offline; 24 % mit Medienbruch (bereits in Issue #165 belegt; wird nicht neu erfunden, sondern zitiert).
- **Hoher Entwicklungsanteil:** 6-Monatsplan ist 100 % Software-Entwicklung inkl. Forschungsmessung; kein Marketing/Docs--only-Projekt (Handbuch-Anforderung erfüllt).

**Interpretationen / offene Fragen (nicht verifizierbar aus Quellen, vor Einreichung klären):**
1. Ob die Jury „Verwaltungs-/Formularinfrastruktur" explizit als gewünschten Schwerpunkt sieht (Interpretation: Infrastruktur für Zivilgesellschaft — Bürgerseite — ist gemeint; FormBridge bedient Primärnutzer Entwickler/Communities, Endnutzen über Produkte wie Feldexa).
2. Formaler Antragstellerstatus (Einzelperson vs. GbR) und Wohnsitzkriterium — persönliche Angabe, nicht recherchierbar.
3. Ob eine **zweite** Bewerbung desselben Maintainers (Feldexa-Kontext öffentlich sichtbar) oder die Parallelprüfung gegen RepairProbe jury-seitig relevant ist — aus Quellen nicht ableitbar; Entscheidung zwischen den beiden Projekten bleibt beim Maintainer (RepairProbe bleibt unverändert, nur Referenz für die finale Wahl).
4. Handbuch-Version-Drift: Kriterien können sich zwischen Jahrgängen ändern; vor Einreichung aktuellen Stand im Portal gegenprüfen (Bewerbungssprechstunde 16.11. nutzbar).
5. Lizenzwahl für das neue Modul (kompatibel zu genutzten Bausteinen: MPL-2.0-Formularagent-Bausteine wären Copy-left-kompatibel zu MPL; Apache-2.0-KIWo-Prinzipien nicht code-tangierend) — Empfehlung erst zur Implementierung fixieren.
6. **Aufwands-/Budgetmodell:** Wie verteilt sich der Arbeitsumfang (FTE je Monat) auf Erkenntnis, Regelkatalog, Evaluation, FOSS-Pflege? Das Handbuch verlangt bei Einzelpersonen realistische Planung; noch nicht ausgearbeitet.
7. **DSGVO/Rechtsrolle:** Das Modul verarbeitet nur synthetische Daten in der Förderphase; sobald Dritte es mit echten Antragsdaten nutzen, entstehen Rechtsfragen (Auftragsverarbeitung, „Beschäftigtendaten", Parteien am Prozess). Für die Bewerbung: Datenschutz-by-design beschreiben (lokal, UNKNOWN-Default); rechtliche Rolle bewusst **nicht** behaupten. Dazu: der Referenz-PDF ist kopierbeschränkt (`copy:no`) — die rechtmäßige Weiterverwendung (Goldstandard-Annotierung) ist vor Förderbeginn zu klären.
8. **Barrierefreiheit:** PTF-Kriterium „Anwendungsfreundlichkeit" — für eine CLI/Bibliothek gilt es anders (Dokumentations-, Installer- und Output-Verständlichkeit) als für eine UI; konkretisieren, statt zu schweigen.
9. **Pflege nach Förderende + Quellendrift:** Wer wartet Regelkataloge und Schemata-Korpus, wenn S00000159 v1.5 erscheint oder PDF-URLs sich ändern? Second-Stage-Konzept (Bausteine §8) adressiert Nutzung, nicht Wartung — offene Planungsaufgabe.

## 3. Abgrenzung zum Bestandsprojekt (förderrelevante Dokumentation)

- **Vor Förderbeginn vorhanden (Produkt):** Feldexa-2.0-App (Flutter/Dart-Monorepo), bestehende MVP-Spezifikation, Evidence-/Test-Struktur — bleibt reguläre Produktentwicklung, wird nicht umdeklariert.
- **Bis Förderbeginn unabhängig entstehend:** alle Produkt-Tasks (T0xx), die Recognition/Export implementieren — transparent nach Issue #167 führen („Änderungen am geplanten Modul vor Förderbeginn nachführen").
- **Fördergegenstand (neu):** eigenständiges Repo/Modul „FormBridge" gemäß `formbridge-module-spec-2026-11-13.md` — eigene Codebasis, keine App-Abhängigkeit, eigene Lizenz, eigener Release. Keine Zeile Produktcode im Förderumfang.
- **Vorarbeit-Ehrlichkeit:** Diese Recherche (Prior-Art-Audit, Referenzfall, Spec) ist Vorarbeit — im Antrag als „Vorkenntnis" einordnen, nicht als geförderte Leistung. Sie beginnt **nicht** mit Implementierung des Moduls (erfolgt nicht vor Bewerbung/Förderbeginn ohne separate Freigabe).

## 4. Risiken der Förderfähigkeit

| Risiko | Einstufung | Umgang |
|---|---|---|
| Jury sieht Verwaltungs-Adapter als „Behörden-IT" statt Zivilgesellschaft-Infrastruktur | mittel | Antragstext konsequent von Bürger-/Community-Nutzen her erzählen (siehe Bewerbungsbausteine) |
| Neuheitsangriff: „das macht doch MACH/SurveyJS/open-formulieren" | mittel | Audit + Matrix + doc-only-Kennzeichnung als Anhang; Narrow-Hypothesis-Formulierung |
| Scope-Risiko 6 Monate (Detektion ohne Lizenzbasis) | hoch→mittel | Spec §5: Detektionsminimum auf Vordruckklasse; Scans out-of-scope;RF-abhängige Messziele statt Feature-Versprechen |
| Second-Stage-Konzept-Pflicht | niedrig | Konzept (Nutzung/Community) in Bewerbung mitdenken; optional deklarieren |

## 5. Fazit

Förderlinie Innovation ist nach verifizierten Kriterien **passungsfähig** (Infrastruktur + Datensparsamkeit + zulässiger „neues Modul"-Fall + hoher Entwicklungsanteil). Verbleibende Unklarheiten sind vor Einreichung durch Sprechstunde/Portal-Check zu klären. Eine Aussage zur **Bewerbungserfolgswahrscheinlichkeit** wird bewusst nicht getroffen.
