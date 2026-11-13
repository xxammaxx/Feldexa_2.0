# Feldexa 2.0 – Deep Research: Legacy-PDF → Verwaltungsdaten (FormBridge)
**Stand:** 13.11.2026 · **Status:** RESEARCH / HYPOTHESE / KEIN PRODUKTAUFTRAG / KEIN FÖRDERANTRAG  
**Kontext:** Kandidat zum Vergleich mit RepairProbe für genau **eine** Prototype-Fund-Bewerbung.  
**Bezüge:** Forschungs-Issue #151, Draft-PR #152, docs/funding/prototype-fund-2027-feldexa-concept-v0.3.md.  
**Änderungsgrenze:** Nur Forschungsdokument. Keine Änderung an spec.md, plan.md, tasks.md, Produktverfassung oder Implementierung; keine Behördenkontakte, keine Datenübermittlung, keine Förderbeantragung.

## 1. Executive Finding
Die gesellschaftliche Problemstellung ist gut belegt; eine unmittelbare **Entlastungswirkung in Behörden ist bislang NICHT gemessen**. Die technische Neuheit liegt NICHT in OCR, PDF-Overlay, ausgefüllten PDFs, Hashes, JSON-Export, FIM-Schemata oder Standard-Signaturprüfung. Belastbare Förderhypothese ist eine **offene, offline arbeitende Interoperabilitäts-/Verifikationsbibliothek für ältere nicht ausfüllbare Verwaltungs-PDFs**, die Formularfelder nachvollziehbar mit einem konkreten amtlichen FIM/XDatenfelder-Schema abgleicht, Unsicherheit und manuelle Korrekturen transparent macht, schema-valide Daten und eine separat überprüfbare PDF-Kopie produziert.

Der Arbeitstitel **FormBridge** bezeichnet diese _zu prüfende_ Software-Infrastruktur innerhalb/nebem dem bestehenden ProofLayer, **keine beschlossen neue Produktmarke oder Roadmap**. Ein direkter, neu erfundener PDF-Provenienzstandard wäre angesichts C2PA keine starke Förderargumentation. Besser: Standards wiederverwenden, vorhandene Formulare mit Datenmodellen verbinden und die Grenze zwischen bestätigter Extraktion, Nutzeränderung und Verwaltungsregel offenlegen.

### Differenzierung der Behauptungen
- **BELEGT:** Deutschland 2026: 50 % zuletzt vollständig offline, 26 % vollständig online, 24 % gemischt; bei den Menschen mit Medienbruch hätten 68 % lieber alles digital erledigt (eGovernment MONITOR 2026).
- **BELEGT:** FIM liefert strukturierte Datenfeldschemata; ein offizielles Wohngeld-Schema ist dokumentiert. FIT-Connect bietet eine strukturierte Submission API und eine isolierte Testumgebung.
- **BELEGT:** Es existieren bereits konkurrierende Lösungen für PDF-Formularerkennung, Online-Antragsassistenten, PDF→JSON-Extraktion, regelbasierte Formularvalidierung und Integritätsnachweise.
- **NICHT BELEGT:** Feldexa reduziert real Behörden-Personalkosten, Bearbeitungsstau, Krankenstand, Rückfragen oder Durchlaufzeiten.
- **NICHT BELEGT:** Der vorgeschlagene Gesamtworkflow ist weltweit erstmalig, zuverlässig genug für die Verwaltung oder bereits rechtssicher einreichbar.
- **NICHT DURCHGEFÜHRT:** Schema-Download/Parsing, lokale Engine-Benchmarks, FIT-Connect-Submission-Test, Interviews, Nutzertest und Behörden-Pilot. Ein Webabruf des Wohngeld-XSD selbst war in der Rechercheumgebung nicht möglich; nur die offizielle FITKO-Dokumentation bestätigt die Schema-URL.

## 2. Nachfrage-/Problem-Evidenz
1. **eGovernment MONITOR 2026:** 50/26/24-Prozent-Verteilung und 68 % unfreiwillige Medienbrüche unter den Medienbruch-Betroffenen. Quelle: https://initiatived21.de/publikationen/egovernment-monitor/2026 ; zusätzliche Stichprobendetails: https://initiatived21.de/publikationen/egovernment-monitor/2026/material .
2. Der Bericht fordert ausdrücklich, medienbruchfreie interne Weiterverarbeitung statt Ausdruck oder manueller Übertragung. Das unterstützt den _Problembefund_, ist aber **keine Effektstudie zu Feldexa**.
3. Der Nationale Normenkontrollrat 2026 fordert weiterhin modernisierte und digitalisierte Verwaltungsverfahren und die Entlastung der Kommunen: https://www.bundestag.de/presse/hib/kurzmeldungen-1231602 .
4. Hoher Krankenstand oder Überlastung einzelner Ämter kann als Kontext dienen, jedoch **nicht** als prognostizierter Effekt von Feldexa ohne separat gemessene, kontrollierte Daten. Ziele als tatsächliche Prozesskennzahlen definieren: Minuten pro Antrag, Nachbearbeitungen, Fehlerfälle und Rückfragen.

## 3. Bestehende Standards sind unsere Bausteine (keine eigene Erfindung)

**FIM / XDatenfelder:** Standardisierte maschinenlesbare Datenfelder und -gruppen, Regeln und Ausfüllhilfen. FIM-Portal und Sammelrepository unterstützen XDF2/XDF3, Konvertierung zu JSON Schema/XSD und unveränderliche versionierte Schemakennungen:
https://docs.fitko.de/kompass/docs/grundlagen-und-rahmen/fim/ ;
https://docs.fitko.de/fim/docs/schema-repository/schemarepository-for-group-4/ .

**Konkretes Pilot-Schema:** FITKO nennt **„Wohngeld Mietzuschuss – Erstantrag“ S00000159 Version 1.4** als Beispiel:
https://schema.fim.fitko.net/immutable/schemas/S00000159V1.4_2024-01-22-1705942219513.xsd .
Die Verfügbarkeit dieser Datei und eine aktuell gültige veröffentlichte PDF-Vorlage sind im folgenden Preflight zu prüfen. Eine erfolgreiche Maschinenvalidierung ist nicht identisch mit rechtlicher Antragsfähigkeit.

**FIM-Regelübersetzung:** Das FIM-Portal übersetzt bereits bestimmte XDF-Freitextregeln KI-gestützt und typgeprüft in ein maschinenlesbares JSON-Format (v0/Beta). Das ist **keine Neuheit**, die Feldexa für sich beanspruchen darf:
https://docs.fitko.de/fim/docs/quer/fimportal/fim_portal_regel_uebersetzung_spezifikation/ .

**FIT-Connect:** Submission API mit verschlüsselten Fachdaten, Metadaten und Anhängen; Empfänger bestimmen akzeptiertes Schema. Öffentliche Testumgebung ohne Anmeldung für technische Grundtests; produktive Anbindung erfordert Identität/Berechtigungen und passende Empfänger:
https://docs.fitko.de/fit-connect/docs/getting-started/submission/structure/ ;
https://docs.fitko.de/fit-connect/docs/organisation-tasks/sender/ ;
https://docs.fitko.de/fit-connect/docs/ssp/ssp_zugang/ .
**Wichtig:** Eine ausgefüllte lokale PDF ist nicht automatisch in FIT-Connect einreichbar. Schema, Absenderberechtigung, Verwaltungsleistung, Zustellpunkt, Identifikation, Empfangsweg und Rechtsform separat belegen. V1 von FIT-Connect wurde am 27.10.2026 abgeschaltet; nur aktuelle V2-Dokumentation verwenden.

**Proof/Signaturen:** C2PA, DSS, pyHanko, PDF/A als vorhandene Werkzeuge und Formate betrachten, nicht neu erfinden. Originalbytes und Exportbytes bleiben getrennte Artefakte; Overlay + Fingerzeichnung machen keine QES und bestätigen keine amtliche Herkunft.

## 4. Stand der Technik: bewusst harte Konkurrenten

| System | Schon vorhanden | Was für unsere Hypothese übrig bleibt |
|---|---|---|
| CommonForms (offen) | Automatische PDF-Feld-Erkennung, CLI/API; wandelt PDF in ausfüllbare Formulare | Nicht als Neuheit verkaufen; feldbezogene FIM-Semantik und offline-validierte Prozessartefakte testen |
| MACH formsolutions (kommerziell) | Mobilfähige Antragsassistenten, PDF-Formulare, Fachverfahrensintegration, XÖV/FIM-kompatible Daten soweit möglich | Offener nutzerseitiger Offline-Workflow für *vorgegebene, alte* PDFs; nicht behaupten, dass Verwaltungsdatenübergabe neu sei |
| OZG Formulardesigner (offen) | Erstellung digitaler Verwaltungsformulare und Open-Source-Version | Bestandserkennung statt manuelle Neukonstruktion; aber offenen Formulardesigner zuerst als Alternative prüfen |
| US GSA pdf-filler (offen) | Auch nicht ausfüllbare / gescannte PDFs mit Koordinatenwerten ausfüllbar | PDF-Overlay ist Stand der Technik |
| SurveyJS AI Form Response Extractor (offen) | Scans und PDFs nach definierter Formularstruktur in JSON, lokal via Ollama möglich | „PDF zu strukturiertem JSON“ allein ist NICHT neu |
| FIM-Portal inkl. maschinenlesbarer Regelübersetzung | Amtliche Schemata und typgeprüfte Regelübersetzung | Regeln nutzen, nicht als neue KI-Regelengine vermarkten |
| C2PA + PDF-Signaturwerkzeuge | Provenienzketten und PDF-Signaturprüfungen | Spezifische Eingabe-/Feldkonsistenz und Behörden-Schema-Zuordnung als neue Integrations-/Testleistung prüfen |

Quellen:
- https://github.com/jbarrow/commonforms
- https://www.mach.de/de/loesungen/mach-formsolutions/formularverlage
- https://serviceportal-machbar.de/werkzeuge/formulardesigner/
- https://github.com/GSA/pdf-filler
- https://github.com/surveyjs/ai-form-response-extractor
- https://spec.c2pa.org/specifications/specifications/2.5/specs/ContentCredentials.html

**Neuheitsurteil:** Es gibt nach dieser gezielten Quellenprüfung **keinen belastbaren Nachweis einer exklusiven Alleinstellung**. Gegenüber existierenden Bausteinen ist die plausible offene Forschungsfrage, ob PDF-Feld-Erkennung → semantische FIM-Zuordnung → reproduzierbare Korrektur-/Konfidenzspur → schema-valide Ausgabe → freiwillig überprüfbarer Nachweis in einer interoperablen, nutzerseitigen Offline-Pipeline praktisch machbar und nützlich ist. Vor Förderwerbung einen Mini-Demonstrator gegen die stärksten Gegenbeispiele benchmarken.

## 5. Hypothesen und Messplan

### H1: Zuordnung
Ein Rechte-geklärtes, nicht interaktives PDF wird einem **konkret identifizierten und versionierten** FIM-Schema zugeordnet. Für jeden vorgeschlagenen Feld-Match dokumentieren: Quellseiten/Koordinaten, Originaltext, Ziel-FIM-ID, Schema-Version, Konfidenz/Begründung und Nutzerentscheidung. Nicht erkannte/mehrdeutige Felder müssen **UNKNOWN** bleiben. Bei fehlendem Schema keine erfundene FIM-Konformität.

Messung: Precision/Recall der Feld-Erkennung, Präzision/Recall der _semantischen_ Feldzuordnung getrennt, Anteil mehrdeutiger Fälle, Fehler bei Pflicht-/Enum-Feldern, Anteil menschlicher Korrekturen. „Schema-valid“ nur nach tatsächlicher Validierung.

### H2: Ausgabe und Kontrollierbarkeit
Nach freigegebenen Korrekturen werden erstellt: (a) eine neue, lesbare PDF, (b) strukturierte, zum *gewählten* FIM-Schema passende JSON/XML-Daten **falls** Schema/Mapping vorhanden und gültig, (c) minimaler auditierbarer lokaler Mapping-Report. Rohdaten und vertrauliche Eingaben bleiben lokal; geteilte Evidenzpakete nur mit bewusster Freigabe.

Messung: Schema-Validierungsfehler pro Formular, falsche Werte (besonders hochriskante Feldverwechslungen), unerkannte falsche Zuordnungen, PDF-Renderdifferenzen, manuelle Nacharbeit, Offline-Netzwerkprüfung, Datenoffenlegung im Manifest.

### H3: Bürger-Zeit und Fehler
Kleiner kontrollierter Vergleich derselben Aufgaben: bisheriger manueller PDF-/Druck-Workflow vs. Feldexa mit Korrekturansicht. Randomisierte Reihenfolge / dokumentierte Vorkenntnisse / vergleichbare Formulare. **Pilotplanung**: 8–12 freiwillige Personen, synthetische personenbezogene Testdaten, Aufgaben mit dokumentiertem Goldstandard. Hypothese: weniger Gesamtdauer und weniger Formfehler – **kein angenommener PASS**.

Messung: Nettozeit von Aufruf bis exportfertigem Dokument inklusive Korrekturen, Fehler pro Fall, nicht ausgefüllte Pflichtfelder, Aufgabenabbrüche, Nutzbarkeit.

### H4: Behörden-Bearbeitung
Ohne echte Amtskooperation nur **synthetischer Prozess-Simulationstest** möglich; keine Behauptung über Arbeitszeitersparnis in realen Behörden. Mit freiwilliger Zustimmung eines Amts/IT-Dienstleisters kann ein kleiner anonymisierter, nicht-produktiver „Bearbeitung in Sandbox“-Test entstehen: gleicher Antrag als PDF-only vs. vorvalidierter Datensatz + PDF.

Messung: manuelle Übertragungsschritte, validierungsbedingte Rückfragen, Bearbeitungsminuten je Fall, Nacharbeit. Kein Krankenstand- oder Personalkosten-Effekt aus solchem Kleintest ableiten.

### H5: Machbarkeit von FIT-Connect
Nur nach erfolgreicher H1/H2-Prüfung: SDK oder REST in FIT-Connect-**Test**umgebung mit **synthetischen** Datensätzen und Testempfänger; kein Versand an echte Ämter. Das ist eine optionale Forschungs-Evidenz, keine MVP-Pflicht und keine Zusage auf produktive Zulässigkeit.

### H6: Prior-Art-Falsifikation
Der gleiche Mini-Fall soll mit CommonForms + FIM-Standarddiensten + PDF-Prüftools und ggf. MACH-Dokumentation konzeptionell bzw. soweit frei testbar funktional verglichen werden. Wenn Standardkomponenten den ganzen Ablauf schon verlässlich anbieten, neu begründen: interoperabler Adapter, messbare Testbatterie oder **NO_GO** für eine eigenständige Förderinnovation.

## 6. Konkreter Forschungs-Sprint: Go/No-Go-Gates

**G0 – Quellen/Format (vor jeder Umsetzung):** amtliche, rechtegeklärte PDF-Vorlage eines Wohngeld-Antrags + exakt passende FIM-Schema-Version finden. *Nicht* annehmen, dass jede PDF zu jedem FIM-Schema passt. Wenn keine passende Version vorliegt: öffentliches synthetisches PDF mit dokumentierter Schema-Ableitung, klar als synthetic beschriftet.

**G1 – Mapping-Spezifikation (nur Forschungsartefakt):** 15–30 plausible Felder mit Goldstandard und 5–10 Fehl-/Mehrdeutigkeitsfällen; Zuordnungsmatrix und erlaubte UNKNOWN-Stati. Daten künstlich und nicht personenbezogen.

**G2 – Vergleiche:** dokumentierte Feature-Matrix von CommonForms, GSA pdf-filler, SurveyJS, OZG Formulardesigner, FIM-Regelübersetzung, FIT-Connect und MACH. Nicht bloß Behauptung „keiner hat das“.

**G3 – Experimentfreigabe:** erst nach G0–G2 Entscheidung, ob ein minimaler lokaler PoC (Parser/Validator/Mapping, kein App-Umbau) sinnvoll ist. Separat genehmigen; unter 2027-Förderung geplante Entwicklungsleistung nicht vorwegnehmen.

**G4 – Wirkung:** kleine Bürgervergleichsstudie und optional verwaltungsseitige, anonymisierte Prozessstudie, nur nach Einwilligung und sicherer Testdatenplanung. Primär Outcomes, keine erfundenen gesparten Minuten.

**G5 – Förderentscheidung:** RepairProbe gegen FormBridge nach (a) belegbarem Nutzwert, (b) technischer Neuheit gegenüber Produkten, (c) 6-Monats-Feasibility, (d) FOSS-Lizenz/Abhängigkeiten, (e) rechtlich/formal sauberem Scope bewerten. **Nur eine Bewerbung** anvisiert; nichts am RepairProbe-Antrag ändern, bis der Nutzer die Entscheidung trifft.

## 7. Förderpositionierung (Hypothese, nicht Werbeversprechen)
**Bürgersicht:** „Alte Behördenformulare am Smartphone ausfüllen, ohne Ausdruck und ohne verpflichtende Cloud. Wo ein passendes amtliches Datenschema vorliegt, können aus überprüften Eingaben zusätzlich maschinenlesbare Antragsdaten entstehen.“

**Geförderter FOSS-Infrastrukturkern:** „Wir untersuchen, ob sich nicht ausfüllbare Legacy-PDFs mit versionierten XDatenfelder/FIM-Schemata so verbinden lassen, dass Feldzuordnung, Nutzerkorrektur, Schema-Validierung und getrennte Ausgabe reproduzierbar und offline nachvollziehbar sind.“

**Nicht behaupten:** amtliche Anerkennung jedes PDFs, automatische vollständige FIM-Konformität, rechtssichere Einreichung, produktive FIT-Connect-Anbindung, QES, gemessene Einsparungen in Verwaltungsämtern.

**Formale Risiken:** Förderlinie Innovation verlangt tatsächlich neue FOSS-Software-Infrastruktur, nicht nur den normalen Feldexa-UI-/OCR-Bau; Lizenz des Kerncodes und ML-Kit-abhängige Nutzung getrennt behandeln (Root-Lizenz im derzeitigen Repo nicht bestätigt); klare Vorarbeitsbaseline. Das bislang geplante 1.000-Stunden-Modell ist zu breit. Vor Antrag maximal ein enges 6-Monats-Paket entlang Schema-Mapping/Offline-Prüfer/Tests; QES und allgemeine Rechtsberatung draußen.

## 8. Entscheidung zum Vergleich mit RepairProbe

- **RepairProbe derzeit antragsreifer:** 850-Stunden-Bewerbungsentwurf im deutschen PTF-Portal gespeichert (Stand letztem verifizierten Nachweis: Draft, nicht eingereicht); offenes Reparaturevidenz- und Sicherheitsmodell, bestehende Apache-2.0-Lizenz.
- **Feldexa möglicher breiterer gesellschaftlicher Nutzen:** direkte Hilfe bei Papier-/PDF-Medienbrüchen; offenes FIM-Mapping könnte spätere Verwaltungsweiterverarbeitung unterstützen. Doch Bürgernutzen und tatsächliche Amtsentlastung sind zwei unterschiedliche Hypothesen.
- **Jetzt keine Projektwahl durch Forschungsdokument:** Erst Machbarkeit und Vergleich der stärksten Konkurrenten prüfen; anschließend nur einen Antrag auswählen. Frist deutscher PTF Jahrgang 03: 30.11.2026.

## 9. Nachverfolgung / Änderungsstatus
Dieser Bericht enthält recherchierte Tatsachen, begrenzte Schlussfolgerungen, offenen Forschungsbedarf und testbare Hypothesen. **Keine** Softwareänderung, Testausführung, Behördenkontaktaufnahme, FIT-Connect-Sendung, Förderbewerbung oder Änderung am RepairProbe-Antrag erfolgte durch diese Dokumentation.
