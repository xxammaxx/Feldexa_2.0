# Feldexa 2.0 – Prototype Fund 2027: Förderkonzept v0.2

**Status:** ENTWURF v0.2 / NICHT EINGEREICHT / KEIN FÖRDERBESCHEID  
**Aktualisierung:** 12.11.2026, verständliche Nutzenbotschaft, Fingerunterschrift vs. QES/PAdES, optionales PDF/A-3-Archiv und Budgetklarstellung.  
**Stand der Bestandsaufnahme:** 12. November 2026, GitHub main: `6a5f705844d661ed882a2233c87f3b39763028b2`  
**Bewerbungsfrist:** 30. November 2026 (genaue Uhrzeit vor verbindlicher Einreichung im Portal kontrollieren)  
**Förderzeitraum:** geplant 1. Juni–30. November 2027  
**Förderlinie:** Innovation (Arbeitshypothese; Resilienz als Alternative prüfen)  
**Repo:** https://github.com/xxammaxx/Feldexa_2.0  
**Forschungs-Issue:** https://github.com/xxammaxx/Feldexa_2.0/issues/151

> Dieses Dokument ist eine eigenständige Förder-Skizze. Es verändert weder die Produktverfassung noch spec.md, plan.md, tasks.md oder den bereits vereinbarten Entwicklungsprozess. Es ist keine Freigabe zur Implementierung und darf nicht als eingereichter Antrag ausgegeben werden.

## 0. Die Bewerbung muss mit dem konkreten Nutzen beginnen

**Kernaussage (Bürgersicht):** Feldexa soll nicht ausfüllbare Behördenformulare direkt auf dem Smartphone ausfüllbar machen – ohne Ausdrucken und ohne Cloudzwang.

**Kurzer Erklärungstext:** Viele Formulare kommen als PDF, lassen sich aber nicht einfach ausfüllen. Feldexa soll die Felder erkennen, Angaben direkt am Handy ermöglichen und eine ausgefüllte PDF-Kopie erzeugen, die Nutzer auch mit dem Finger sichtbar unterschreiben können. Das ursprüngliche Formular bleibt unverändert gespeichert. Eine zusätzliche, frei überprüfbare Nachweistechnik soll zeigen, welche Dokumentversion und welche Ergänzungen zu der fertigen Kopie gehören. Für Fälle mit besonderen Formanforderungen soll eine optionale qualifizierte elektronische Signatur als spätere Erweiterung untersucht werden.

**Abgrenzung:** Dieser Absatz erklärt den **Nutzen der Gesamtanwendung**. Der **Fördergegenstand** ist enger: ein offenes Nachweisformat, die unabhängige Verifikation, die sichere Einordnung vorhandener Signaturen und ein dokumentierter Interoperabilitäts-/Machbarkeitstest. Keine Zusage, dass jede Behörde die ausgefüllte PDF akzeptiert. Noch nicht implementierte Funktionen stets als *geplant* kennzeichnen.

## 1. Titel und Kurzbeschreibung für die Bewerbung

**Arbeitstitel:** Feldexa ProofLayer – Prüffähige, lokale Digitalisierung von Behördenformularen

Feldexa 2.0 ist eine geplante freie Android-Anwendung, mit der sich gescannte, nicht ausfüllbare PDF-Formulare ohne Cloudverarbeitung in bearbeitbare Formulare überführen lassen. Der beantragte Forschungs- und Entwicklungsanteil geht über normale OCR, ein PDF-Overlay und einen Datei-Hash hinaus: Entwickelt werden sollen ein offenes, datensparsames Integritäts- und Provenienzformat, eine unabhängig prüfbare Verbindung zwischen Original, bearbeiteter Maske und Export sowie ein eigenständiger Open-Source-Verifier. Die Software soll dokumentieren, was beim Ausfüllen technisch verändert wurde – und was nicht. Das sichtbare Unterschreiben mit dem Finger und die Einbettung dieser Zeichnung in eine PDF-Kopie sind bereits MVP-Vorarbeiten und **keine** neue Förderinnovation. Ein separater qualifizierter Signaturvorgang kann – nur bei einschlägiger Formvorschrift und zulässigem Einreichungsweg – als zusätzliche optionale Forschungs-/Ausbaustufe geprüft werden. Sie bescheinigt **nicht** automatisch die Echtheit amtlicher Vorlagen oder die rechtliche Wirksamkeit einer Einreichung.

## 2. Gesellschaftliches Problem

Viele deutsche Verwaltungsformulare werden als PDFs bereitgestellt, lassen sich jedoch nicht unmittelbar digital ausfüllen. Nutzerinnen und Nutzer müssen drucken, handschriftlich ausfüllen, scannen oder mithilfe von Spezialwerkzeugen Felder manuell positionieren. Gerade bei Dokumenten mit persönlichen Daten sind Cloud-PDF-Dienste eine zusätzliche Hürde: Sie erfordern die Herausgabe vertraulicher Inhalte. Auch bei digital ausgefüllten Dateien ist oft schwer nachvollziehbar, ob die Vorlage erhalten blieb und wie das Ergebnis zustande kam.

Feldexa soll eine frei verfügbare lokale Alternative bieten. Der im Förderprojekt neu zu erforschende Beitrag ist die **technische Prüfbarkeit der Bearbeitung**: Anwenderinnen und Anwender sowie Dritte sollen mit offenen Werkzeugen Original, Ausfüllmaske und Ergebnis anhand klar benannter technischer Aussagen prüfen können. Dies ersetzt weder gesetzliche Formvorgaben noch einen zulässigen Übermittlungsweg.

## 3. Vorarbeit (explizit nicht als neue Förderleistung abrechnen)

Das öffentliche Repository ist ein Flutter-/Dart-Neuaufbau, Android ist die maßgebliche Zielplattform. Bereits spezifiziert bzw. teilweise vorbereitet sind:

- Unveränderte importierte PDF als geschützte, intern gespeicherte Kopie; SHA-256 der Quelldatei.
- Separates Dokumentmodell mit Feldgeometrie, Nutzerkorrekturen und eingegebenen Werten.
- Handschriftliche Unterschriftszeichnung auf dem Smartphone, die nur zum konkreten Dokument gehört, sowie sichtbare Einbettung in den PDF-Export sind bereits spezifiziert: `spec.md` FR-036/FR-066, `tasks.md` T083/T104, `contracts/export-plan.md`. **Kein neuer Fördergegenstand.**
- Flattened-PDF-Export als **neue Datei** mit Originalseiten und darübergelegten Werten; Export darf die gespeicherten Originalbytes nicht verändern.
- Quellintegritätsprüfung sowie unabhängig gerenderte PDF-Tests.
- Dokumentations- und Teststruktur mit Trennung zwischen simulierten Browser-Tests und echten Android-Tests.

**Quellen der Baseline:**  
- https://github.com/xxammaxx/Feldexa_2.0/blob/main/specs/001-scanned-form-workflow/spec.md  
- https://github.com/xxammaxx/Feldexa_2.0/blob/main/specs/001-scanned-form-workflow/contracts/storage-format.md  
- https://github.com/xxammaxx/Feldexa_2.0/blob/main/specs/001-scanned-form-workflow/contracts/export-plan.md  
- https://github.com/xxammaxx/Feldexa_2.0/issues/48  
- https://github.com/xxammaxx/Feldexa_2.0/issues/104  
- https://github.com/xxammaxx/Feldexa_2.0/issues/109  

**Grenze:** Ein einfacher SHA-256-Abgleich, eine Maske, ein neuer PDF-Export und die grundlegende App-Implementierung zählen bereits zur Vorarbeit bzw. bestehenden Entwicklungsroadmap. Werden sie vor dem 1. Juni 2027 fertiggestellt, dürfen sie nicht als neue Förderentwicklung beschrieben oder nochmals abgerechnet werden. Diese Förder-Skizze bleibt an den realen Code-Stand zum Förderbeginn anzupassen.

## 4. Neu zu entwickelnde, förderfähige Hypothese

**Forschungsfrage:** Kann eine lokale, offene Software in praxisrelevanten PDF-Fällen den Zusammenhang zwischen einer unveränderten Eingangsdatei, einer separaten Formularmaske und der ausgefüllten Ausgabedatei so nachweisen, dass eine unabhängige Prüfinstanz Manipulationen zuverlässig erkennt, ohne dass vertrauliche Formulardaten zur Überprüfung an einen zentralen Server übertragen werden müssen?

Die Förderleistung soll vier klar neue Softwarekomponenten umfassen:

1. **Proof Bundle (offenes Manifestformat):** Versioniertes, dokumentiertes Format mit Referenzen auf Eingangsdatei, Formularlayout-Revision, Export, Hashes und Prüfprofilen; datensparsame, optional verschlüsselte Metadaten; kanonische Serialisierung.
2. **Unabhängiger FOSS-Verifier:** CLI/Bibliothek ohne Abhängigkeit von der Feldexa-App. Überprüft Hash-Bindungen und Dokumentrelationen, meldet verifizierbar / verletzt / nicht prüfbar mit klarer Fehlerursache und demonstriert Angriffe durch Negativtests.
3. **PDF-Integritäts- und Signaturrisiko-Analyse:** Prüfen vorhandener PDF-Signaturen, Siegel, Zertifikate, Berechtigungen und Dokumentstrukturen vor Export; klarer Hinweis auf mögliche Signaturverletzungen und Verzicht auf rechtlich nicht gedeckte „Gültig“-Versprechen.
4. **Reproduzierbarer Konformitäts- und Manipulationskorpus:** Rechtegeklärte synthetische und reale Testfälle mit unterschiedlichen Engines, Schriftarten, Koordinatensystemen, Rotation, Mehrseitigkeit, PDF-Signaturen und absichtlichen Manipulationen.

5. **Verfahrens- und Signaturkompatibilität (eng begrenzte Forschung):** Anforderungen ausgewählter Behördenverfahren, Warnung bei vorhandenen PDF-Signaturen und Machbarkeit einer optionalen standardkonformen QES-/PAdES-Schnittstelle prüfen. Eine vollständige Vertrauensdienstintegration, Identitätsprüfung oder pauschale behördliche Annahme wird innerhalb der sechs Monate **nicht** zugesagt.

**Neuheitsprüfung offen:** Vor Antragstellung vergleichende Analyse mit bestehenden Dokument-Integritäts-, PDF-Signatur-/PAdES-, Provenienz- und Formularwerkzeugen sowie ggf. etablierten Standards. Der bloße Einsatz von SHA-256 oder PDF-Overlays ist **keine Innovation**.

## 5. Was der Nachweis leisten kann – und was nicht

### Technisch überprüfbare Aussagen

- Die als Original beigefügten Eingangsbytes stimmen mit dem im Manifest referenzierten Hash überein.
- Die tatsächlich vorliegende Exportdatei stimmt mit dem im Manifest referenzierten Export-Hash überein.
- Das Manifest verweist eindeutig auf die konkrete Version der Bearbeitungsmaske.
- Ein unabhängiger Validator meldet eine Veränderung in Original/Overlay/Export und kann unvollständige Nachweise erkennen.
- Eine getrennte, engine-übergreifende visuelle Prüfung untersucht, ob es außerhalb der vorgesehenen Overlay-Bereiche unzulässige Veränderungen gibt; zulässige Toleranzen müssen dokumentiert sein.

### Nicht ableitbare Aussagen

- Ein unsigniertes Manifest beweist **keine** vertrauenswürdige Urheberschaft oder fälschungssichere Historie. Ein Angreifer kann mehrere zusammengehörige Artefakte samt Hashes neu erstellen.
- Der Hash beweist **nicht**, dass eine Vorlage von einer Behörde stammt, amtlich echt ist oder zum Zeitpunkt der Einreichung aktuell war.
- Der Hash beweist **nicht**, dass die Formularwerte sachlich richtig sind.
- Die von Feldexa erzeugte PDF ist nicht byte-identisch mit dem ursprünglichen PDF; es handelt sich um eine neue Datei.
- Eine gezeichnete Unterschriftsabbildung ist keine qualifizierte elektronische Signatur.
- Die Einreichbarkeit hängt von Verfahren, Rechtsformanforderungen und zugelassenem Kommunikationsweg ab, etwa nach § 3a VwVfG sowie gegebenenfalls spezielleren Vorschriften.

**Zusätzliches Risiko:** Bereits signierte Original-PDFs können durch Export oder Änderungen ihre kryptografische Signaturprüfung verlieren. Für diese Eingänge muss eine sichere, explizite Produktstrategie entwickelt und getestet werden.

## 5a. Validierte Unterschrift- und PDF-Strategie

Drei voneinander getrennte Ausgaben:

| Modus | Was Feldexa technisch tut | Einordnung |
| --- | --- | --- |
| **Normales ausgefülltes PDF** | Bestehende Vorarbeit: Originalbytes unverändert speichern; Werte und ggf. mit dem Finger gezeichnete Signatur werden auf einer **neuen** PDF-Ausgabedatei sichtbar eingebettet. | Kann genügen, wenn keine strengere Form vorgeschrieben ist und der Empfangsweg eröffnet ist. Fingerzeichnung ist nicht automatisch rechtswirksame Unterschriftsersetzung. |
| **Nachweisbares PDF / Proof Bundle** | Neues, unabhängiges Prüfmanifest und FOSS-Verifier verknüpfen Eingangsdatei, Bearbeitungsmaske und Export anhand explizit begrenzter Integritätsaussagen. | Förderkandidat. Beweist weder amtliche Herkunft noch Authentizität eines unsignierten Manifests noch Rechtsgültigkeit. |
| **Optional QES-signiertes PDF** | Nach der finalen PDF-Erzeugung wird gegebenenfalls ein **separater**, qualifizierter Signaturprozess mit einem qualifizierten Vertrauensdiensteanbieter angeschlossen. Geeignete PDF-Signaturen können im PAdES-Format vorliegen. | Forschung/optionaler späterer Integrationspfad, **keine vorhandene Produktfunktion und keine zugesagte Erstförderungsleistung**. QES kann gesetzliche Schriftform ersetzen, sofern Verfahrensrecht und Übermittlungsweg dies zulassen. |

**Ablauf:** Original lokal importieren → getrennte Feld-/Wertmaske bearbeiten und optional Fingerunterschrift zeichnen → finale PDF-Kopie erzeugen und prüfen → falls erforderlich sowie rechtlich und technisch möglich **anschließend** qualifiziert signieren → signiertes PDF nicht mehr durch unzulässige Änderungen manipulieren. Bereits signierte Eingangs-PDFs zunächst als Risikofälle behandeln; Original unverändert halten, nicht blind erneut flatten.

**PDF/A-3 ist kein Signaturersatz:** Als optionales Archivformat kann es eingebettete Dateien, etwa ein Original oder ein Proof Bundle, aufnehmen. Es begründet **keine** automatische Rechtsgültigkeit und ist nicht automatisch von jedem Verwaltungsportal akzeptiert. PAdES bezeichnet PDF-Signaturformate; PAdES ist **nicht synonym** mit QES. Als interoperable Ausgabe zuerst eine möglichst kompatible Standard-PDF vorsehen, optional ein separates Nachweispaket und später Archiv-/Signaturvarianten.

**Rechtliche Grenzen:** eIDAS Art. 25 Abs. 1–2; § 3a VwVfG; im Sozialbereich § 36a SGB I. Nicht jede unterschriebene Erklärung verlangt eine QES. Wo schriftliche Form verlangt wird, können unter spezifischen Voraussetzungen auch andere gesetzlich zugelassene digitale Verfahren (z. B. ein Behördenformular mit elektronischem Identitätsnachweis) bestehen. Weder Fingerstrich noch Dateihash noch PDF/A machen eine unzulässig eingereichte Erklärung automatisch gültig. Vertragsrechtliche Fälle ggf. gesondert nach § 126a BGB prüfen.

**Datenschutz:** Die normale Feldexa-Verarbeitung bleibt ohne Cloudzwang. Ein freiwillig ausgelöster qualifizierter Signaturprozess kann Netzverbindung, Identitätsprüfung, Kosten und Offenlegung von Dokument- oder Signaturdaten an einen Vertrauensdiensteanbieter benötigen. Keine heimliche Datenübermittlung und keine unbelegte Behauptung einer vollständig offline nutzbaren QES.

**Nachweis-/Rechtsrisiken:** Ein neuer SHA-256-Wert kann auch für gefälschte Gesamtdokumentpakete berechnet werden. Ohne vertrauenswürdige Signatur und Zeitinformation kein beweissicheres Herkunfts- oder Historienzertifikat. Vorhandene signierte PDF-Dateien können durch neue Ausgabekopien oder nachträgliche Änderungen ungültig werden.

## 6. Architektur und Umsetzung

**Bestehender Stack (Produktplanung):** Flutter/Dart mit Android-Adapter (Kotlin), lokaler OCR-Engine, PDFium-basierter Anzeige und PDF-Export; keine Cloud zur Dokumentenverarbeitung. Der Verifier soll als eigenständige FOSS-Bibliothek/CLI unabhängig von Flutter und der mobilen App laufen.

**Vorgeschlagene Zusatzarchitektur:**

Eingangs-PDF (Originalbytes) → Feldmaske/Revision → exportierte PDF  
⇣                                            ⇣  
Hash + Referenzen → offenes Proof Bundle ← Export-Hash  
                                  ↓  
                        unabhängiger Validator  
                                  ↓  
                  differenzierter Prüfbericht

Die Gestaltung muss das Datenschutzprinzip **kein Zwang zum Hochladen** erhalten. Wenn die Prüfung vollständige Eingabedaten erfordert, müssen Nutzer diese kontrolliert bereitstellen; reine Hashes oder ausgeblendete Felder können keine semantische Korrektheit belegen. Die Ergebnisse sind explizit nach technischer Sicherheit und Aussagegrenze zu klassifizieren.

## 7. Geplante Arbeitspakete (Muster, 6 Monate)

| Paket | Zeitraum | Inhalt | Nachweisbarer Ausgang | Modellstunden |
| --- | --- | --- | --- | ---: |
| AP1 | Juni 2027 | Wettbewerbs-/Standardanalyse, Rechts- und Bedrohungsmodell, Profil- und Schnittstellendefinition | Veröffentlichte Anforderungsspezifikation + Testbedrohungen | 120 |
| AP2 | Juni–Juli | Datenmodell, kanonisches Proof-Bundle-Format, Testvektoren | Versionierter Formatentwurf + Referenzimplementierung | 220 |
| AP3 | Juli–August | Unabhängiger CLI-Verifier und Negativfälle | Reproduzierbare positive/negative Prüfsuite | 200 |
| AP4 | August–September | Erkennung von PDF-Signaturen, visueller Dokumentvergleich und begrenzte QES-/PAdES-Schnittstellenanalyse | Prüfsuite + Machbarkeitsbericht, ohne produktive QES-Zusage | 180 |
| AP5 | September–Oktober | Integration in Feldexa 2.0 und lokal ausgeführte Ende-zu-Ende-Tests | Demonstrierbarer Offline-Durchlauf | 150 |
| AP6 | November | Externe Verifier-Tests, Veröffentlichung, Dokumentation, technische Auswertung | Freier Code, CLI, Format, Ergebnisbericht | 130 |
| **Summe** | **Juni–November 2027** | | | **1.000** |

**Hinweis zur Kalkulation:** 1.000 Stunden sind ein **vorläufiges, nicht genehmigtes Gesamtarbeitsmodell**. Bei angenommenen 50 €/h ergeben sich 50.000 € rechnerischer Aufwand; davon **950 förderfinanzierte Stunden = 47.500 €** (95 %) und **50 Stunden Eigenleistung = 2.500 €** (5 %). Der Eigenanteil darf nicht gleichzeitig als förderfinanzierte Stunde angesetzt werden. Ob Stunden, Eigenanteil und persönliche Förderberechtigung im konkreten Fall passen, ist formal zu prüfen. Die gezeigte Stundenzahl setzt eine nahezu vollzeitige Tätigkeit über sechs Monate voraus; Verfügbarkeit und mögliche andere Förderprojekte sind abzuklären.

## 8. Messbare Abnahmehypothesen

1. **Proof-Bundle-Interoperabilität:** Manifest und Prüfreport sind für mindestens zwei unabhängige Implementierungen dokumentiert; eine davon ist ein separater CLI-Verifier.
2. **Manipulationserkennung:** Alle festgelegten Negativtestfälle für Einzelartefakt-Veränderungen, fehlende bzw. vertauschte Artefakte und unzulässige Revisionen werden erkannt. Grenzen bei gemeinsam manipulierten Artefakten sind ausdrücklich dokumentiert.
3. **Dokumenttreue:** Sichtbare Veränderungen außerhalb der erlaubten Overlay-Zonen werden mit mehreren PDF-Renderern unter veröffentlichten Toleranzen analysiert; bekannte falsch-positive/negative Fälle werden offengelegt.
4. **Signaturfälle:** PDF-Eingänge mit vorhandenen Signaturen/Siegeln werden vor Export klassifiziert; riskante Änderungen erhalten dokumentierte Warnungen bzw. sichere Alternativpfade.
5. **Offline- und Datenschutzverhalten:** Vollständiger Prüflauf ohne Netzwerkzugriff, ohne zentrale Verarbeitung und ohne automatische Veröffentlichung von Nutzereingaben.
6. **Offene Nachnutzung:** Veröffentlichung unter einer geeigneten OSI-anerkannten Lizenz, öffentlicher Versionsstand, reproduzierbare Tests, dokumentierte Schnittstellen und Beispieldaten mit überprüften Nutzungsrechten.

Die exakten Benchmarks und Akzeptanzschwellen sind AP1-Ergebnisse. Keine vorgetäuschten PASS-Zustände.

## 9. Abgrenzung von bestehenden Werkzeugen

Vergleich vor Einreichung ergänzen und belegen:

- Formulardetektion/Editoren: CommonForms, Stirling PDF, Formblatt.
- PDF-Validierung/Signaturen: qpdf, veraPDF, PDFBox, PAdES-geeignete Werkzeuge.
- Herkunfts-/Provenienzansätze: einschlägige offene Provenienzformate und digitale Signaturstandards.

**Differenzierungsbehauptung derzeit nur Hypothese:** Feldexa ProofLayer fokussiert die offline nachprüfbare Beziehung zwischen unveränderlichem Formulareingang, versionierter Feld-/Wertmaske und exportierter ausgefüllter PDF als wiederverwendbare FOSS-Infrastruktur für Verwaltungsdokumente. Vor Antragstellung prüfen, ob eine andere Lösung dies bereits vollständig anbietet und ob Wiederverwendung bestehender Standardbausteine vorzuziehen ist.

## 10. Gesellschaftliche Zielgruppen und Verwertung

- **Privatpersonen:** Gescanntes PDF ohne Cloudzwang ausfüllen und einen technischen Nachweis zur eigenen Archivierung erhalten.
- **Beratungsstellen und gemeinnützige Organisationen:** Datenschutzfreundliche Unterstützung bei Formularen.
- **Entwickler- und Civic-Tech-Community:** Unabhängiger Verifier und offenes Prüfmanifest als wiederverwendbare Bausteine.
- **Behördenkontakte:** Mögliche Pilotgespräche über akzeptierte Formate/Übermittlungswege; Zusammenarbeit bisher **nicht zugesagt**.

Feldexa 2.0 kann eine vollständig quelloffene Referenzanwendung werden. Das geförderte ProofLayer muss unabhängig von Feldexa weiterverwendbar sein und darf keine proprietären Komponenten zum Verifizieren erfordern.

## 11. Risiken und Alternativen

| Risiko | Gegenmaßnahme |
| --- | --- |
| Neuheitsanspruch bereits durch bestehende Standards abgedeckt | Stand-der-Technik-Vergleich, Standards wiederverwenden, Scope verengen oder Idee verwerfen |
| Signiertes PDF lässt sich nicht risikofrei ergänzen | Eingangssignatur erkennen; Warnung, separates Ergebnis, zulässigen Verfahrensweg dokumentieren |
| Sichtbare Fingerzeichnung wird mit qualifizierter Signatur verwechselt | Unterscheidung in Produkt und Antrag; keine QES ohne gesonderten qualifizierten Signaturvorgang |
| PDF/A-3 wird fälschlich als rechtsgültiges Behördenformat vermarktet | Nur optionales Archiv-/Nachweisformat, Empfängeranforderungen separat prüfen |
| Signaturdienst verlangt Identifizierung, Kosten oder Datenübermittlung | Nur freiwillige, transparente Integration nach Machbarkeitsprüfung; kein Offline-Versprechen für QES |
| Ein Hash-Manifest kann komplett neu gefälscht werden | Aussagegrenzen erklären; unabhängige Signatur-/Zeitstempeloptionen untersuchen, nicht Echtheit behaupten |
| Visuelle Vergleiche variieren nach Renderer | Mehrere Engines, definierte Overlay-Zonen, Toleranzen und Fehlerquoten |
| Offenlegung sensitiver Daten im Nachweis | Datenminimierung, lokale Verifikation, optionales Teilen, keine voreingestellten personenbezogenen Klartexte |
| Proprietäre OCR-Engine im Produktsystem | FOSS-Verifier OCR-unabhängig halten; lizenzierbare freie OCR-Alternativen separat bewerten |
| Projekt läuft vor Förderbeginn weiter | SHA-/Zeit-stempelte Baseline, klarer Förder-Scope, nur nach Förderbeginn neue Arbeitsleistungen |
| 1.000 Stunden/6 Monate unrealistisch | Kapazitätsabgleich, Förderung verringern oder AP-Priorität neu ordnen |

## 12. Ungeklärte formale Punkte – vor Einreichung beantworten

- Besteht Antragsberechtigung als Privatperson (Alter, Wohnsitz, Steuern, Erwerbssituation/Freistellung)?
- Ist eine zweite Bewerbung derselben Person neben dem bereits vorbereiteten RepairProbe-Antrag im deutschen Prototype Fund Jahrgang 03 zulässig? **Nicht** aus Regeln des Schweizer Prototype Fund ableiten.
- Welche konkrete Open-Source-Lizenz wird für Feldexa 2.0 und ProofLayer gewählt? Lizenz- und Urheberrechtsinventar vor Veröffentlichung.
- Förderlinie Innovation gegenüber Resilienz abschließend begründen.
- Wie lautet der dann erwartbare Baseline-Funktionsstand am 1. Juni 2027? Nicht vorhandene/FERTIGE Leistungen nicht vermischen.
- Soll eine viermonatige Second Stage bereits in der Erstbewerbung beantragt werden? Deren spätere Beantragung kann eingeschränkt sein.
- Ist die begrenzte QES-/PAdES-Schnittstellenstudie in der Linie Innovation fachlich plausibel, oder sollte sie als separate spätere Ausbaustufe außerhalb des Förderplans bleiben?
- Vor den Formularfeldern: Ausschreibung 2026 und **erste Online-Bewerbung** von der späteren formellen Projektantragstellung nach einer Juryauswahl unterscheiden; Zeichenlimits nicht aus älteren Antragsunterlagen übernehmen.
- Welche Fragen und Zeichen-/Wortgrenzen zeigt das aktuelle Antragsportal? Dieses Dokument ist **keine** 1:1-Feldkopie.
- Kann das Prototype-Fund-Team die grundsätzliche Förderfähigkeit eines neuen ProofLayer-Moduls im bestehenden Projekt bestätigen?

## 13. Fragen an das Förderteam (vorbereitet, noch nicht versendet)

1. Ist ein getrennt definierter, neu zu entwickelnder Open-Source-Prüfkern innerhalb einer bereits laufenden öffentlichen FOSS-Android-Anwendung grundsätzlich für die Linie Innovation geeignet, wenn der bisherige OCR-/Formular-MVP explizit als Vorarbeit offengelegt wird?
2. Sind zwei getrennte Projektbewerbungen derselben natürlichen Person im selben deutschen Jahrgang zulässig? Falls ja, können beide unabhängig bewertet werden, und welche Grenzen gelten bei eventueller Förderung?
3. Wie erwartet die Jury die Abgrenzung dokumentierter Vorarbeiten von den zum Förderbeginn neu ausgeführten Entwicklungspaketen?
4. Reicht für die Bewerbung die erklärte spätere FOSS-Lizenzierung, oder muss das bereits öffentliche Repository schon beim Einreichen vollständig unter einer FOSS-Lizenz stehen?
5. Ist die juristisch begrenzte Signatur-/Verfahrensprüfung als fachlich relevanter Teil der neu beantragten Integritätsinfrastruktur geeignet, ohne den Prototyp zu überladen?

## 13a. Rechts- und Standardquellen für den Signaturzusatz

- eIDAS Art. 25 (unterscheidet allgemeine elektronische Signaturen von QES): https://eur-lex.europa.eu/legal-content/DE/ALL/?uri=CELEX:32014R0910
- § 3a VwVfG: https://www.gesetze-im-internet.de/vwvfg/__3a.html
- § 36a SGB I: https://www.gesetze-im-internet.de/sgb_1/__36a.html
- PDF/A-3, ISO 19005-3: https://pdfa.org/resource/iso-19005-3-pdf-a-3/
- BSI-Handreichung zur PDF-Signatur-Validierung (PAdES): https://www.bsi.bund.de/SharedDocs/Downloads/DE/BSI/Oeffentliche_Verwaltung/Moderner-Staat/Handreichung-Digitale-Zeugnisse.pdf
- Prototype-Fund-Erstbewerbungsportal (Jahrgang 03): https://bewerben.prototypefund.de/
- Beachten: Prototype-Fund-Wiki "Antragstellung" beschreibt stellenweise den **formalen Folgeantrag eines Vorjahres**, nicht die aktuelle Erstbewerbung und deren Textlimits.

## 14. Quellen und Status

- Offizielles Portal / laufender Jahrgang 03: https://bewerben.prototypefund.de/
- Prototype-Fund-Förderlinien: https://www.prototypefund.de/innovation und https://www.prototypefund.de/resilienz
- Deutsches Prototype-Fund-Wiki Antragstellung (teils Unterlagen der Vorjahre; nicht als aktuelle Portalmaske missverstehen): https://wiki.prototypefund.de/index.php?title=Antragsstellung
- Allgemeine Programmlaufzeiten: https://wiki.prototypefund.de/index.php?title=%C3%9Cber_den_PTF_sprechen
- Quellen- und Entwicklungsstand Feldexa 2.0: https://github.com/xxammaxx/Feldexa_2.0

**Änderungspolitik:** Förderkonzept getrennt von Produkt-SSOT; Code, bestehende Issues, Spezifikationsverfassung und deren Entwicklungs-Governance bleiben unangetastet, bis gesonderte Entscheidungen vorliegen.
