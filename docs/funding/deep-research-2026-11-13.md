# Feldexa 2.0 / ProofLayer – Deep Research zur Förderung und technischen Neuheit

**Recherche- und Bewertungsstand:** 13. November 2026 (Europe/Berlin)  
**Status:** RESEARCH / EVIDENCE REVIEW / KEIN ANTRAG / KEINE PRODUKTFREIGABE  
**Bezugsdokument:** docs/funding/prototype-fund-2027-feldexa-concept-v0.3.md (Draft-PR #152)  
**Forschungs-Issue:** https://github.com/xxammaxx/Feldexa_2.0/issues/151

> Diese Recherche ist ein Entscheidungspapier, keine rechtliche Förderzusage und kein Nachweis technischer Neuheit. Informationen aus offiziellen Quellen und eigene Bewertungen sind getrennt. Das bestehende MVP, die Produktverfassung und seine Tasks bleiben unverändert. Vor einer Einreichung sind Programmeignung, persönliche Berechtigung, Lizenzierung, Pilotverfahren und aktuelle Portalbedingungen nachzuweisen.

## 1. Executive Decision

**A-Priorität: Deutscher Prototype Fund, Jahrgang 03, Förderlinie Innovation.** Das gemeinwohlorientierte FOSS-Werkzeug passt thematisch zu Datensicherheit und Software-Infrastruktur, sofern die Förderskizze die neue, unabhängig nutzbare Verifikationsinfrastruktur statt allgemeiner OCR-/Formularentwicklung in den Mittelpunkt stellt. Bewerbungsschluss **30.11.2026, 15:00 Uhr MEZ**; die Ausschreibung nennt die Förderlinien Innovation, Resilienz, Up and Coming. Regulärer Förderzeitraum: **01.06.–30.11.2027**. Finanzrahmen als Einzelperson bis **47.500 EUR Förderung**, Eigenanteil von mindestens 5 % des Gesamtaufwands (vorläufiges Modell 47.500 + 2.500 EUR Eigenleistung). Die persönliche Förderfähigkeit und Mehrfachbewerbungen neben RepairProbe sind NICHT abschließend geklärt.

**B-Priorität: NLnet Restack, nur konditional.** Open-Internet-/Local-first-Profil, Anträge von Einzelpersonen, Fördergrößen **5.000–50.000 EUR**, zweite Runde veröffentlicht, Frist **03.01.2027, 12:00 CET**. **Ausschlussrisiko:** NLnet-GenAI-Policy v2.0 seit 20.10.2026: Bei geförderter Entwicklung dürfen GenAI-Agenten nicht Code, Dokumentation, Design oder Tests erzeugen; KI als Coding-Partner ist nicht zulässig. Bereits vorhandene KI-Artefakte können bei Offenlegung bestehen bleiben. Anträge müssen grundsätzlich selbst von Menschen verfasst werden. Nur sinnvoll, falls der geförderte Scope tatsächlich vollständig regelkonform und menschlich implementiert werden kann. **Dieser KI-generierte Forschungsbericht darf nicht als NLnet-Antragstext übernommen werden.**

**Nachrangig:** EXIST-Gründungsstipendium ausschließlich bei einschlägigem Hochschul-/Forschungsbezug und Gründungsabsicht; ZIM im Regelfall nur bei antragsberechtigtem Unternehmen und kommerzieller FuE. NRW MID-Gutschein-Portal nimmt seit 01.01.2026 keine neuen MID-Gutschein-Anträge an. Die vorangegangene BMDS Digital-Tech-to-Product-Erstrunde endete am 11.10.2026, daher keine laufende Alternative.

**Gesamtbewertung:** PTF-Kandidatur plausibel, aber noch **QUALIFICATION_PENDING**, keine gesicherte Förderung und kein nachgewiesener Alleinstellungsanspruch.

## 2. Der Fördergegenstand und die harte Abgrenzung

### Bereits bekannt, spezifiziert oder in Entwicklung; NICHT erneut als neue Förderleistung verkaufen

- Lokale PDF-Importfunktion, OCR, Formularfeld-Geometrie und Formularwerte.
- Unveränderte Kopie der PDF-Originalbytes mit SHA-256.
- Separate lokale Bearbeitungs-/Overlay-Repräsentation.
- Export einer neuen, ausgefüllten und ggf. sichtbar mit dem Finger unterschriebenen PDF-Datei.
- Basis-Hashprüfung des Originals, grundlegende PDF-Exporttests.
- Sichtbare Fingerzeichnung ist weder QES noch unabhängig authentifizierte Unterschrift.

### Potenziell neuer Förderumfang – enger und prüfbar

1. **Offene, versionierte Nachweisrelation:** Formal spezifizierte Bindung von unveränderter Eingangsdatei, konkreter Overlay-/Wertrevision, Exportbytefolge und Prüfergebnissen; semantisch klare Aussagen, Datenschutzbehandlung und Bedrohungsmodell.
2. **App-unabhängiger Open-Source-Verifier:** Dritte können die im Paket enthaltenen Artefakte ohne Feldexa-App offline auf die spezifizierte Konsistenz prüfen.
3. **PDF-spezifische zulässige Änderungserkennung:** Vergleich von Dokument-/Renderstruktur mit benannten zulässigen Overlay-Zonen, transparenten Renderer-Toleranzen sowie Fehleranalysen, einschließlich signierter/inkrementell geänderter PDF-Eingänge.
4. **Signatur- und Herkunftsrisiko-Prüfung:** Bestehende PAdES-/elektronische Siegel und Vertrauensketten mit etablierten Bibliotheken validieren, nicht selbst Signaturkryptographie neu erfinden. Grenzen bei Offline-Sperrstatus, bereits signierter Ursprungs-PDF und nachträglichem Export explizit kennzeichnen.
5. **Eng begrenzte Prozessregel-Interoperabilität:** Offenes Schema für versionierte, mit amtlichen Quellen belegte Form-/Empfangswegregeln anhand maximal zweier positiver Pilotfälle plus eines Negativkontrollfalls; kein allgemeiner KI-Rechtsautomat.

Forschungshypothese: Eine offline verwendbare, unabhängig implementierbare PDF-Formular-Nachweiskette kann in einem definierten, veröffentlichten Testkorpus Manipulationen an einzelnen Artefakten und unzulässige Darstellungsänderungen besser nachvollziehbar machen als die bisherigen unabhängigen Standardwerkzeuge allein. **Das ist zu testen, nicht bereits bewiesen.**

## 3. Prior-Art / Standards und Innovationsgrenze

| System/Standard | Belegtes vorhandenes Können | Folge für Feldexa |
| --- | --- | --- |
| C2PA Content Credentials 2.5 | Standardisierte Inhaltsprovenienz, signierte Manifestketten, PDF-Medientyp application/pdf samt Einbettungsregeln | Keinesfalls universell „erstes PDF-Provenienzformat“ behaupten; C2PA-Interoperabilität und Wiederverwendung prüfen. |
| EU Digital Signature Services (DSS) | Offene EU-Bibliothek für digitale Signaturen, PAdES, Signaturvalidierung und EU-Trust-Kontext | Signaturprüfung auf bestehender Technologie aufsetzen; Versions-/Lizenz-/Android-Verträglichkeit evaluieren. |
| pyHanko | PDF-Signaturvalidierung, Trust-Prüfung, Analyse inkrementeller PDF-Updates (eigene Doku warnt bei Difference Analysis vor experimentellem Status) | Gegenprobe und Referenzfälle; nicht die alleinige Sicherheitserklärung. |
| W3C PROV-O | Standardisierte Modellierung von Entity, Activity und Agent für Provenienz | Metadaten auf etabliertes Modell abbilden, nicht semantisch neu erfinden. |
| RFC 8785 (JCS) | Kanonische JSON-Serialisierung für reproduzierbares Hashing/Signieren | Als kanonische Serialisierung untersuchen statt ad-hoc JSON-Hashes. |
| qpdf / veraPDF | PDF-Verarbeitung bzw. Prüfung von PDF-Konformität/PDF-A | In Testkorpus einbeziehen; weder qpdf noch PDF/A allein liefern ProofLayer-Gesamtnachweis. |

**Abzuleitende Neuheitsprüfung (noch nicht erbracht):**
- Ein Mini-Referenzfall mit „Original → Overlay v1/v2 → Export → Prüfreport“ wird als C2PA-Manifest, als einfache Hashliste und als ProofLayer-Kandidat modelliert.
- Die Unterschiede werden messbar dokumentiert: unabhängige Portabilität, Datenschutz, Fehlerberichte, Änderungszone, Signaturrisiken, Komplexität, Größe, Laufzeit, Integrationsaufwand.
- Falls C2PA + bestehende PDF-Werkzeuge alles Benötigte bereits ermöglichen, auf einen **offenen Integrationsadapter und reproduzierbaren Konformitätskorpus** umschwenken; keinen künstlich neuen Standard entwickeln.
- Keine Alleinstellung „Rechtsgültigkeit“ oder „amtliche Echtheit“, sondern engere überprüfbare technische Aussagen.

**Technische Bedrohungsgrenze:** Ein unsigniertes Hashmanifest ist nur Konsistenznachweis. Wer Original, Overlay, Export und Manifest zusammen neu erzeugt, kann korrekte zueinander passende Hashes herstellen. Auch ein Signaturbeweis kann Herkunft nur relativ zum validierten Vertrauensanker und zum tatsächlich signierten Bytebereich behaupten. Renderer-Vergleich entdeckt möglicherweise nicht sämtliche versteckten PDF-Elemente oder semantischen Manipulationen. Offline-Verifikation kann externe Widerrufsdaten ohne aktuelle Evidenz nicht abschließend bewerten.

## 4. Rechts- und Behördenforschung: drei Pilot-/Kontrollfälle

| Fall | Gesicherte amtliche Aussage | Beabsichtigter Feldexa-Test | Noch ungeklärt |
| --- | --- | --- | --- |
| **Grundsicherungsgeld (Jobcenter, ehemals Bürgergeld)** | Die Bundesagentur nennt den Antrag ausdrücklich **formfrei** und nennt Online-, persönlichen, telefonischen und schriftlichen Antrag. Sie bestätigt außerdem die Umstellung auf Grundsicherungsgeld zum **01.07.2026**. | Prüfen, dass die Oberfläche nicht allein wegen eines Unterschriftsfelds QES erzwingt. | Konkrete PDF-Dateiannahme und tatsächlicher offener elektronischer Empfangsweg je Jobcenter. |
| **BAföG** | § 46 BAföG ermöglicht einen **schriftlichen oder elektronischen Antrag**; für erforderliche Tatsachen gelten vorgesehene Formblätter. | Quellenbasiertes Profil, das „elektronisch möglich“ nicht fälschlich mit „beliebige PDF per E-Mail akzeptiert“ verwechselt. | Zuständiges Amt, aktuell akzeptierte Formate, Identifikation und konkreter Übermittlungsweg. |
| **ELSTER / Besteuerung (Negativkontrolle)** | § 87a Abs. 1 AO begrenzt E-Mail/QES-/beBPo-Alternativen, wenn ein sicheres amtliches Übermittlungsverfahren bereitsteht; Ausnahmen gelten. | Unbekannte oder unzulässige PDF-Abgabe nicht mit „QES macht alles gültig“ beschönigen; offizielles Verfahren zeigen. | Welcher konkrete Steuervorgang und welche Spezialausnahmen zutreffen. |

**Zentraler Rechtsbefund:** § 36a Abs. 2c SGB I: Ein vorgeschriebenes Formular mit Unterschriftsfeld begründet nicht schon allein eine gesetzliche Schriftformpflicht. § 3a VwVfG / § 36a SGB I / § 87a AO setzen für elektronische Abgabe regelmäßig einen eröffneten Empfangsweg voraus. Die eIDAS-Gleichstellung einer QES mit handschriftlicher Unterschrift heilt nicht jeden unzulässigen Transportweg.

**Statuslogik für Pilot:** „belegt elektronisch möglich“, „belegt gesonderte elektronische Form/Identifizierung nötig“, „belegt Portalweg“, „Papierweg nach konkreten Regeln“ oder als Standard „NICHT GEKLÄRT“. Keine automatische Einzelfallrechtsberatung und kein Button „rechtsgültig“.

Quellen: https://www.arbeitsagentur.de/grundsicherung/finanziell-absichern/antrag-bescheid ; https://www.gesetze-im-internet.de/baf_g/__46.html ; https://www.gesetze-im-internet.de/sgb_1/__36a.html ; https://www.gesetze-im-internet.de/vwvfg/__3a.html ; https://www.gesetze-im-internet.de/ao_1977/__87a.html .

## 5. Förderprogramme – Eignung und Ausschlussrisiken

| Programm | Aktueller Stand zum Recherchetag | Projekt-Fit | Entscheidendes Gate |
| --- | --- | --- | --- |
| **Prototype Fund Deutschland / Innovation (PTF)** | Jahrgang 03; 30.11.2026, 15:00 MEZ; bis 47.500 EUR als Einzelperson, 6 Monate ab Juni 2027; ggf. Second Stage bei späterer Auswahl | **HOCH, aber zu verifizieren** | Neuheit gegenüber C2PA/DSS, persönlicher Status, FOSS-Lizenz, getrennte Vorarbeit, zweiter Antrag RepairProbe |
| **PTF / Resilienz** | Derselbe laufende Jahrgang und Stichtag | MITTEL | Vergleichbar mit bestehenden zentralisierten/proprietären Formular-Diensten konkret benennen und gesellschaftliche Resilienz belegen |
| **NLnet / Restack** | Zweiter Aufruf, 03.01.2027 12:00 CET; 5.000–50.000 EUR | THEMATISCH HOCH; **METHODISCH KRITISCH** | Strikte GenAI-Policy 2.0 für Antrag und Entwicklung; bei beibehaltener Agenten-Implementierung nicht geeignet |
| **EXIST Gründungsstipendium** | Hochschul-/Forschungseinrichtungsgebundene Gründerförderung | NIEDRIG bis MITTEL | Hochschulzugehörigkeit, Gründungsabsicht, antragsberechtigte Trägerinstitution |
| **ZIM FuE** | Unternehmensbezogene wirtschaftsnahe FuE | NIEDRIG für derzeitige Einzelpersonen-FOSS-Forschung | Antragsberechtigtes Unternehmen und kommerzielle FuE-Scope |
| **NRW MID-Gutscheine** | Neue Gutscheinanträge im bisherigen Portal seit 01.01.2026 nicht mehr möglich | NICHT AKTUELL ANTRAGBAR | Keine offene Bewerbungsroute dort |
| **BMDS Digital-Tech-to-Product, erster Förderaufruf** | Skizzenfrist war 11.10.2026; abgeschlossen | MÖGLICHER FUTURE-FIT | Erst bei späterem, thematisch geeignetem Neuaufruf und dessen Antragsfähigkeit |

**Mehrfachantrag RepairProbe + Feldexa:** **OFFEN.** FAQ des **schweizerischen** Prototype Fund betreffen eine andere Organisation und sind hierfür keine belastbare Grundlage. Vor Einreichung beim **deutschen** PTF-Team schriftlich klären: zwei Anträge zulässig, parallele Bewilligungen, Förderzeiten-/Stundenüberschneidung, Auswahlkonflikte.

**FOSS-/Lizenz-Gate:** Öffentlich zugänglicher GitHub-Code ist ohne eingeräumte Nutzungsrechte keine FOSS. Beim Repository-Precheck war eine Wurzeldatei LICENSE über GitHub nicht auffindbar; das beweist nicht, dass nirgendwo eine Lizenz existiert. Urheber-/Fremdcodeinventar und gültige OSI-FOSS-Lizenz vor Einreichung bzw. spätestens in den geltenden Förderfristen klären; für **geförderten Code** verlangt PTF öffentliche FOSS-Veröffentlichung. Produktlizenz nicht automatisch aufgrund dieses Berichts ändern.

**Formale Gates:** Volljährigkeit, Wohnsitz/Steuer in Deutschland, Selbstständigkeit/Freiberuflichkeit oder erforderliche Arbeitgeberfreistellung, tatsächliche 6-Monats-Kapazität und Finanzierungs-/Eigenanteils-Nachweis sind beim tatsächlichen Antragsteller zu prüfen; hier keine personenbezogene Förderberechtigung behauptet.

**Kapazität:** Das Modell 1.000 Stunden / sechs Monate bedeutet etwa 167 Stunden pro Monat. Das ist ein fast voller Arbeitsumfang. ProofLayer-MVP + Signaturen + visuelle Konformität + 2 Verwaltungs-Profile + Veröffentlichung sind nur mit strikter Priorisierung realistisch. QES-Produktintegration und allgemeine Rechtsautomatik nicht in die sechs Monate aufnehmen.

## 6. Empfohlener überprüfbarer 6-Monats-Plan

1. **Juni / Gate G1:** C2PA- und DSS-Gap-Demonstration, Rechte-/Lizenzprüfung, Bedrohungsmodell, zwei Pilotprofile und Negativkontrolle. Entscheidung: Standardintegration vs. neues Manifest.
2. **Juni–Juli / G2:** versioniertes interoperables Proof-Bundle-Schema, Testvektoren, Datensparsamkeitsregeln, Referenztest mit zwei Im-/Exporttechnologien.
3. **Juli–August / G3:** unabhängiger Offline-CLI-Verifier mit robustem Statusmodell und Negativtests; manipulierte Einzelartefakte erkennen, vollständigen Bündeltaustausch als Trust-Grenze kennzeichnen.
4. **August–September / G4:** vorhandene Signaturen/Siegel vor dem Export klassifizieren, PDF-Rendervergleich im veröffentlichten Korpus, Pilotregelprofile quellenbasiert modellieren. QES nur als dokumentierte externe Machbarkeitsstudie.
5. **September–Oktober / G5:** lokale Integration in Feldexa, Android-Reallauf, extern mit CLI reproduzierbare Prüfläufe. Simulation und echte Android-Tests strikt trennen.
6. **November / G6:** freie Veröffentlichung von Verifier, Schema, Testdaten, Benchmarks und dokumentierten Abdeckungs-/Fehlergrenzen sowie unabhängigem Reproduktionsleitfaden.

**Prüfkriterien:** reproduzierbare Einzelartefakt-Manipulationsfälle, konsistente positive Validierung, Renderdifferenzen mit publizierten Fehlerraten, keine automatische Dokumentübertragung, unabhängige Verifier-Ausführung, ausdrücklich keine QES-Verwechslung. Keine vorab behaupteten Erfolgsquoten ohne Tests.

## 7. PTF-Antragsbotschaft – nicht 1:1 als Portaltext

**Bürgernutzen:** „Behördenformulare am Smartphone ausfüllen, ohne auszudrucken und ohne persönliche Angaben an einen Cloud-Dienst abgeben zu müssen.“

**Technischer Förderbeitrag:** „Wir entwickeln einen frei nutzbaren Prüfbaustein, mit dem sich bei ausgefüllten Behörden-PDFs unabhängig nachvollziehen lässt, welches Original, welche Bearbeitungsmaske und welche Exportversion zusammengehören. Der Prüfer erkennt Manipulationen und zeigt die technischen Grenzen des Nachweises offen an – insbesondere bei vorhandenen digitalen Signaturen.“

**Transparenz:** Die zugrunde liegende Formular-App und grundlegendes Overlay/Hashing sind Vorarbeiten. Die neue Fördersumme betrifft ausschließlich den separat nachprüfbaren, offenen Verifikationsbaustein und seine Forschungsvalidierung. Weder allgemeine behördliche Anerkennung noch QES oder rechtswirksamer Versand werden zugesagt.

## 8. Entscheidungen und offene Verifikation vor Bewerbung

- [ ] **PTF:** Beim deutschen Förderteam Mehrfachbewerbung neben RepairProbe und mögliche parallele Förderung schriftlich klären.
- [ ] **PTF:** Grundsätzliches Förder-Okay für isolierten, neuen Prüfkern in bereits bestehender App klären.
- [ ] **PTF:** Individuelle Antragsberechtigung, Eigenanteil und Zeitkapazität nachweisen.
- [ ] **Repo:** OSI-Lizenz, Copyright-/Dependency-Inventar und Förder-Baseline (SHA plus Datum) vollständig feststellen; Änderungen nur nach separatem Produktentscheid.
- [ ] **Technik:** C2PA-Machbarkeit für spezifische Original/Overlay/Export-Relation mit Minidatensatz beweisen oder falsifizieren.
- [ ] **Technik:** DSS/pyHanko-Signaturklassen und visuelle Differenzfälle als reproduzierbares Testkorpus skizzieren.
- [ ] **Recht:** Konkrete zwei Pilotbehörden und deren aktuelle Übermittlungs-/Dateiformatregeln mit amtlichen Quellen prüfen; Status bei fehlender Evidenz UNKNOWN.
- [ ] **Bewerbung:** Tatsächliche Fragen, Zeichenlimits und Abgabefenster im Live-Portal prüfen; keine frühere Formularfassung übernehmen.
- [ ] **NLnet:** Nur nach bewusster Entscheidung gegen agentengenerierte Förderarbeit und bei selbstverfasstem Antrag erneut prüfen.

## 9. Quellenregister (Primärquellen zuerst)

**Förderung**
- Deutsches PTF-Bewerbungsportal (laufende Linien/Datum): https://bewerben.prototypefund.de/
- PTF-Förderablauf und Kontakt: https://wiki.prototypefund.de/index.php?title=%C3%9Cber_den_PTF_sprechen
- PTF FOSS-Veröffentlichung: https://wiki.prototypefund.de/index.php?title=Ver%C3%B6ffentlichung_des_Codes_w%C3%A4hrend_und_nach_der_F%C3%B6rderung
- PTF FOSS-/Urheberrechtswissen: https://kb.prototypefund.de/books/rechtliche-grundlagen/page/lizenzierung-und-urheberrecht
- Bundesregierung/Land Brandenburg, Jahrgang 2026/27 und 15:00-Frist: https://esf.brandenburg.de/esf/de/ansicht/~12-10-2026-brandaktuell-prototype-fund-foerdert-talente-in-der-softwareentwicklung
- NLnet Restack (Beträge und Datum): https://nlnet.nl/restack/
- NLnet Restack FAQ/Eligibility: https://nlnet.nl/restack/faq/
- NLnet GenAI-Policy FAQ (entscheidendes Ausschlussrisiko): https://nlnet.nl/foundation/policies/generativeAI/faq/
- EXIST Gründungsstipendium: https://exist.de/programm/gruendungsstipendium/
- NRW MID: https://www.mittelstand-innovativ-digital.nrw/foerderportale
- BMDS erster Digital-Tech-to-Product-Aufruf: https://bmds.bund.de/themen/digitalpolitik/foerderprogramm-digital-tech-to-product

**Stand der Technik**
- C2PA Content Credentials 2.5: https://spec.c2pa.org/specifications/specifications/2.5/specs/ContentCredentials.html
- EU Digital Signature Services: https://ec.europa.eu/digital-building-blocks/sites/spaces/DIGITAL/pages/467109107/Digital%2BSignature%2BService%2B-%2BDSS
- pyHanko: https://docs.pyhanko.eu/en/latest/cli-guide/validation.html
- W3C PROV-O: https://www.w3.org/TR/prov-o/
- RFC 8785 JCS: https://www.rfc-editor.org/rfc/rfc8785.html
- veraPDF: https://verapdf.org/project/index.html
- qpdf: https://qpdf.sourceforge.io/

**Recht und Pilotverfahren**
- Sozialrecht: https://www.gesetze-im-internet.de/sgb_1/__36a.html
- Verwaltungsrecht: https://www.gesetze-im-internet.de/vwvfg/__3a.html
- Steuerrecht: https://www.gesetze-im-internet.de/ao_1977/__87a.html
- BAföG: https://www.gesetze-im-internet.de/baf_g/__46.html
- Grundsicherungsgeld / Bundesagentur: https://www.arbeitsagentur.de/grundsicherung/finanziell-absichern/antrag-bescheid
- Bundesnetzagentur Vertrauenslisten: https://www.bundesnetzagentur.de/EVD/DE/Anbieter/DeutscheVertrauensliste/start.html

## 10. Änderungs- und Entscheidungsgrenzen

Dieses Papier wurde ausschließlich als zusätzliche Forschungsdokumentation für den bestehenden Draft-PR-Zweig vorgesehen. Es ändert keine Produktverfassung, keine Implementierung, keine Tests, keine Releaseplanung und keine bereits bestehenden Spezifikationen. **Keine Bewerbung abgesendet, keine Förderung beantragt, kein PR gemergt.**
