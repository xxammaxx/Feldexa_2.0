# Bewerbungsbausteine (Deutsch) — FormBridge, Förderlinie Innovation

**Zweck:** Rohbausteine für das Bewerbungsformular (Handbuch Jahrgang 03). Verständliche Sprache, keine überzogenen Innovationssansprüche, klare Trennung von Bestehendem und Neuem. **Entwurf — kein eingereichter Antrag.**

## 1. Das Problem (ca. 120 Wörter)

Viele Behördenformulare gibt es nur als PDF zum Ausdrucken. Wer digital arbeiten will, muss Felder von Hand nachbauen oder Drittanbieter-Cloud-Dienste benutzen — bei Dokumenten mit hohen Einkommens- und Gesundheitsdaten ein reales Problem. Gleichzeitig gibt es mit FIM (Föderales Informationsmanagement) einen offiziellen Standard für Verwaltungsdaten, und es gibt offene Werkzeuge für Formular-Detektion oder Schema-Verwaltung. Was nach unserer Quellcodeprüfung relevanter freier Projekte (Stand 13.11.2026, siehe Anhang) **nicht gefunden wurde**, ist die Verbindung: ein freies Werkzeug, das die sichtbaren Felder eines alten Behörden-PDFs automatisch und **nachprüfbar** den versionierten FIM-Datenfeldern zuordnet. Fehler geschehen dabei dort, wo es weh tut: gleiche Feldnamen in mehreren Abschnitten („Name" für Antragsteller, Vermieter, Haushaltsmitglieder), Beträge, Codelisten. Solche Zuordnungen entscheiden heute Menschen stillschweigend — maschinenprüfbar dokumentiert ist das in keinem der geprüften Projekte.

## 2. Wer profitiert? (ca. 80 Wörter)

Direkt: Entwicklerinnen, Open-Source-Projekte und Kommunen/IT-Dienstleister, die Bürgeranträge digitalisieren, aber keine proprietäre Cloud einsetzen wollen. Das Modul ist eine Programmierbibliothek plus Kommandozeilen-Werkzeug; es läuft ohne Cloud-Dienst, sodass daraus gebaute Anwendungen datensparsam und offline-fähig sein können. Indirekt profitieren Bürgerinnen und Bürger: Anträge wie Wohngeld lassen sich ohne Medienbruch einreichen, ohne vertrauliche Daten an externe Dienste weiterzugeben. Perspektivisch hilft auch die Verwaltung: sauber strukturierte, schema-validierte Eingaben statt handschriftlich ausgefüllter und wieder eingescannter Papiervordrucke — das ist ein Ziel, das dieses Modul allein nicht liefern kann, sondern erst Produkte, die es einsetzen. Das Modul ist bewusst infrastrukturell, damit mehrere Projekte — auch die bestehende Feldexa-App — es unabhängig wiederverwenden können.

## 3. Warum reichen bestehende Lösungen nicht? (ca. 110 Wörter)

Wir haben die relevanten freien Projekte im **Quellcode** geprüft (Stand 13.11.2026): **Formularagent** (MPL-2.0) migriert bereits existierende Formulardefinitionen (FIM-XML, form.io, Excel) in valides Formular-JSON mit Migrationsbericht — nimmt aber keine PDFs an und misst Unsicherheit nur kategorial. **KIWo/OpenForm** (Apache-2.0) extrahiert Werte mit Cloud-KI und bietet Review-UI — aber ohne FIM-Bezug, ohne Feldkoordinaten, mit Pflicht-Cloud-Anbindung. **CommonForms** erkennt Felder gut — aber ohne Lizenz, ohne Semantik. **FITKO** betreibt die FIM-Schema-Infrastruktur — und dokumentiert selbst, dass der benötigte Konvertierungspfad „in der Konzeption" ist. Die Einzelbausteine existieren; die prüfbare Kette von einem amtlichen PDF bis zu versionierten FIM-Datenfeldern mit Unsicherheitsausweisung nicht.

## 4. Was wird konkret entwickelt? (ca. 120 Wörter)

**FormBridge** — ein eigenständiges, lokal lauffähiges Open-Source-Modul (eigene Codebasis, unabhängig von bestehenden Apps):
1. **Erkennung** von Feldern in statischen Behörden-PDFs mit Textlage (Position, sichtbare Beschriftung);
2. **Zuordnungs-Engine** mit versioniertem Regelkatalog: Kandidaten auf FIM-Datenfeld-IDs inkl. Konfidenz und explizitem „UNKNOWN" statt stillschweigendem Rätselraten; Abschnitts-Kontext löst Namens-Mehrdeutigkeiten auf;
3. **Review-Gate**: Menschen bestätigen/korrigieren Zuordnungen; Entscheidungen werden versioniert gespeichert;
4. **Provenienz-Manifest**: SHA-256 von Quell-PDF und Schema, Koordinate→Feldpfad, Schema-Variante und Normalisierungsschritte, Review-Entscheid — maschinenprüfbar durch einen unabhängigen Verifier;
5. **Validierte Ausgabe**: strukturierter Datensatz gegen (dokumentiert normalisiertes) amtliches Schema.
Referenzfall durchgehend: der amtliche Fürther Wohngeldantrag ↔ FIM S00000159 v1.4.

## 5. Warum als offene Infrastruktur? (ca. 70 Wörter)

Der Bedarf ist über Einzelprojekte hinweg gleich: Zuordnungen müssen prüfbar bleiben, weil Fehlzusendungen an Behörden echte Folgen haben. Als FOSS-Infrastruktur kann jede Kommune, jedes Projekt und jede Untersuchung die gleichen Prüfpfade benutzen; die Regelkataloge und Testkorpora sind dokumentiert und austauschbar. Im offiziellen XSD des Referenzverfahrens haben wir 170 Parser-Fehler nachgewiesen (libxml2/xmllint) — öffentlich aufgeräumte Normalisierungswerkzeuge helfen dem ganzen Ökosystem, nicht nur uns.

## 6. Was ist in sechs Monaten realistisch? (ca. 90 Wörter)

Realistisch und messbar: ein funktionierender Prototyp für **eine Verfahrensfamilie** (Wohngeld Mietzuschuss Erstantrag) mit ≥ 200 Feldern Goldstandard, Feld-Precision ≥ 0,95 und Recall ≥ 0,90 — gemessen sowohl am Referenzdokument als auch an **mindestens einem zurückgehaltenen Dokument** (andere Landes-Variante des Wohngeld-Vordrucks), gegen das der Regelkatalog nicht entwickelt wurde. Alle kritischen Fehlzuordnungen werden durch UNKNOWN + Review-Gate abgesichert. Dazu: validierende Ausgabe, unabhängiger Manifest-Verifier, Review-Zeit-Messung durch **zwei bis drei externe Testpersonen** (nicht durch die Entwickler selbst) und ein Schema-Hygiene-Werkzeug für ≥ 5 amtliche FIM-XSDs. Nicht versprochen wird: Scans/OCR-Qualität, viele Verfahren, Produkt-UI, Behördenanschluss. Scans sind als späterer Adapter-Ort ausgewiesen; die Infrastruktur bleibt auch damit wiederverwendbar.

## 7. Abgrenzung zum Bestandsprojekt (Formularfrage „Stand des Projekts")

Bestehend: die Feldexa-App (freie Android-App für nicht ausfüllbare Formulare, eigenständige Produktentwicklung, öffentliches Repo). Der Fördergegenstand ist **nicht** die App, sondern das oben beschriebene, app-unabhängige Zuordnungs- und Provenienz-Modul in eigener Codebasis mit eigener FOSS-Lizenz. Vorher existiert dieses Modul nicht; konkrete Vorarbeit ist die hier dokumentierte Quellcode- und Schemata-Analyse (Knowledge, kein Modulcode). Änderungen bis Förderbeginn werden transparent nachgeführt.

## 8. Second-Stage-Konzept (optional, falls angestrebt)

Nutzungsphase statt Technologiephase: 1–2 Pilot-Integrationen (z. B. in Feldexa-App und ein CLI-Werkzeug für kommunale Testumgebungen), Nutzung durch Dev-Communities (FIM-/OZG-Community, FITKO-Umfeld), Dokumentation von Integrationsrezepten, Evaluation mit Nutzenden (Review-Zeit, Verständlichkeit der UNKNOWN-Ausweisungen).

## 9. Formulierungshinweise

- Nie „weltweit erstmalig" o. ä.; stattdessen: „nach unserer Quellcodeprüfung vom 13.11.2026 nicht vorhanden" (Anhang: Prior-Art-Matrix).
- Defekte amtliche XSD neutral-sachlich formulieren (kooperativ, FITKO-sympathisierend; Ziel: Beitrag, nicht Anklage).
- Zahlen nur aus verifizierten Quellen (D21 eGov-Monitor 2026; eigene Messungen als Messziele, nicht als Ergebnisse).
