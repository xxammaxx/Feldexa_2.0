# Feldexa 2.0 FormBridge – erster echter Formular-Pilot: Wohngeld Mietzuschuss

**Stand:** 13.11.2026 · **Status:** PARTIAL_PASS / EXTERNAL_DOWNLOAD_BLOCKED / FIM_VALIDATION_NOT_RUN  
**Forschungs-Issue:** #165 · **Forschungs-PR:** #152 (Draft, nicht gemergt)  
**Art der Arbeit:** Recherche, visuelle Dokumentprüfung, deterministischer *Offline-Text-Smoke-Test*. Keine neue App-Funktion, kein Versand an eine Behörde, keine Antragstellung.

## 1. Gewählte echte, nicht ausfüllbare Behördenvorlage

- **Herausgeber:** Stadt Fürth, amtliche Website `fuerth.de`.
- **PDF:** [Antrag auf Wohngeld – Mietzuschuss, Erstantrag/Weiterleistungsantrag](https://www.fuerth.de/fileadmin/redaktion/01-Rathaus/Formulare/Nicht-Ausfuellbar/2026-02-13-Vordruck-Wohngeldantrag.pdf)
- **Dokumenteigenschaften:** acht Seiten (sichtbar in Seitenzählung), offizieller Veröffentlichungsordner „Nicht-Ausfuellbar“. Im PDF selbst steht „Stand: Januar 2023“, während der veröffentlichte URL-Pfad `2026-02-13` enthält; diese beiden Daten nicht gleichsetzen. Im Browser war die reale PDF-Vorlage lesbar und wurden die Seiten 1, 2, 6 und 8 visuell angesehen. In dieser Ausführungsumgebung konnte die PDF-Binärdatei **nicht** lokal gespeichert werden. Deshalb **kein** aus der Datei ermittelter SHA-256, keine gesicherte PDF-AcroForm-Strukturanalyse, kein lokaler PDF-Parser-Lauf und keine OCR-Geschwindigkeits-/Positionsmessung.
- **Warum geeignet:** typische Alt-PDF-Struktur mit Formularfeldern und Mehrfachvorkommen identischer Feldnamen in unterschiedlichen Kontexten (Antragsteller, weitere Haushaltsmitglieder, Vermieter, Zahlbetrag und Nachweispflicht).
- **Warnung zu Zuständigkeit und Form:** Fürth liegt in Bayern. Die zentrale FIM-Schema-ID „Wohngeld Mietzuschuss – Erstantrag“ ist bundesweit dokumentiert; eine *identische* Feldstruktur der lokalen PDF mit dem FIM-Referenzdatenschema ist **nicht** belegt.

## 2. FIM-Zielquelle: offiziell benannt, aber nicht geladen

- FITKO-Dokumentation zum Sammelrepository: https://docs.fitko.de/fim/docs/schema-repository/schemarepository-for-group-4/
- Referenzschema: `S00000159`, Version `1.4`; offiziell im Anwendungsbeispiel bezeichnet als „Wohngeld Mietzuschuss – Erstantrag“.
- Belegter URL-Verweis: https://schema.fim.fitko.net/immutable/schemas/S00000159V1.4_2024-01-22-1705942219513.xsd
- **Blocker:** Der Webindex verweigert diesen Host für automatisches Nachladen (robots.txt); der Container scheitert an externer DNS-Auflösung. Es wurde **kein** XSD-XML-Inhalt inspiziert, geparst oder kompiliert.
- **Unzulässige Behauptungen:** Kein Abgleich mit wirklichen FIM-Datenfeld-IDs, keine XML-Schema-Validierung und keine gültige maschinenlesbare Antragsdatei nachgewiesen.

## 3. Sichtprüfung der realen PDF-Seiten

| Seite | Direkt erkennbare Bereiche | Besonderheit |
| --- | --- | --- |
| 1 | Antragsteller: Name, Vorname, Geschlecht, Geburtsname, Geburtsdatum, Geburtsort, Staatsangehörigkeit, Anschrift, Telefon, E-Mail, Familienstand, Tätigkeit; Wohnraum | Keine eindeutige FIM-ID aus bloßer Beschriftung; adress- und kontextabhängige Unterfelder |
| 2 | Weitere Haushaltsmitglieder (tabellarisch); Namens- und Geburtsfelder wiederholt; Verwandtschaftsverhältnis; weitere Haushalts-/Betreuungsfragen | Das gleiche Wort „Name“ hat hier andere fachliche Rolle als auf S. 1 |
| 6 | Vermietung, Fläche in m², monatliche Warmmiete in Euro, Heizkosten, Zusatzkosten, Untermiete | Beträge sind abhängig von Auswahl- und Unterfeldlogik; Einheiten und Kostenbestandteile müssen getrennt werden |
| 8 | Erklärungen, Datum, Unterschrift und nachträgliche Änderungen | Sichtbare Unterschrift ist keine QES; Erklärung ist kein frei extrahierbares Zahlenfeld |

## 4. Ausgeführte Testschritte und Resultat

Ein lokales Python-Forschungs-Skript wurde mit **manuell ausgewählten, nachprüfbaren Textauszügen der amtlichen PDF-Webansicht** ausgeführt; es ist kein Test auf hochgeladenem oder heruntergeladenem PDF-Binärinhalt.

### R1 – Feldkonzept-Suchlauf: PASS, nur Offline-Text-Smoke
- Für 18 kuratierte Feldkonzepte (z. B. Vorname, Geburtsdatum, Warmmiete, Wohnfläche) fanden simple reguläre Ausdrücke mindestens eine passende Textstelle in den gezielt ausgewählten Auszügen: **18 von 18**.
- Der Wert beweist ausschließlich, dass die **handverlesenen** Auszüge die zuvor definierten Labels enthalten und der Skript-RegEx-Lauf funktioniert. Es ist **keine** Precision-/Recall-/OCR-Messung und kein belastbarer Beleg für automatische Feldkennung über acht Seiten.

### R2 – Kontext-/Mehrdeutigkeitsprüfung: POSITIVE DETECTION OF RISK
- **7 der 18 Konzepte** haben im Auszug mehrere Fundstellen und werden vom Test explizit als **REVIEW_CONTEXT_REQUIRED** gekennzeichnet.
- Beispiele: `Name`, `Vorname`, `Geburtsdatum`, `Geburtsort`, `Staatsangehörigkeit` auf Antragsteller- und Haushaltsmitgliedseiten; `Warmmiete/Miete` in unterschiedlichen Textkontexten.
- **Forschungsbefund:** Wortabgleich darf niemals stillschweigend den Antragsteller als Empfänger aller gleichnamigen Felder behandeln. Es braucht Abschnitts-/Rollenbezug, Zeilen-/Gruppenposition, Kardinalität und Nutzerfreigabe. `UNKNOWN` ist im Zweifelsfall korrekt.

### R3 – Negativtests: PASS, nur Skript-Invarianten
- Ein Auszug ohne Felder führt zu **0 erkannten Konzepten**.
- Ohne geladenes echtes XSD werden **keine erfundenen FIM-Datenfeld-IDs** zugeordnet.

### R4 – Tatsächlicher End-to-End-Lauf: **NOT_RUN / BLOCKED**
- Amtliche PDF-Binärdatei konnte nicht in die lokale Testumgebung heruntergeladen werden; daher keine PDF-Formfeld-/Text-Layer-/OCR- oder Geometrieprüfung, kein Datei-Hash.
- Amtliche FIM-XSD-Datei konnte ebenfalls nicht geladen werden; daher keine XSD-Auswertung, kein echter FIM-Feld-ID-Abgleich, keine XSD-/JSON-Schema-Validierung.
- Es wurden weder gefüllte PDF-Kopie noch strukturierte, amtlich schema-valide Daten erzeugt. Es gab keine FIT-Connect-Übermittlung und keine Antragsstellung.

## 5. Reproduktionsanleitung für Internet-fähigen Orca/Linux-Host

Voraussetzungen: Python 3, `requests`, `pymupdf`, `lxml`.

```bash
mkdir -p /tmp/feldexa-formbridge-wohngeld && cd /tmp/feldexa-formbridge-wohngeld
curl -fL --retry 3 --connect-timeout 15 \
  'https://www.fuerth.de/fileadmin/redaktion/01-Rathaus/Formulare/Nicht-Ausfuellbar/2026-02-13-Vordruck-Wohngeldantrag.pdf' -o antrag.pdf
curl -fL --retry 3 --connect-timeout 15 \
  'https://schema.fim.fitko.net/immutable/schemas/S00000159V1.4_2024-01-22-1705942219513.xsd' -o wohngeld.xsd
sha256sum antrag.pdf wohngeld.xsd
pdfinfo antrag.pdf | grep -E 'Pages:|Form:|File size:'
pdftotext -layout antrag.pdf antrag.txt
python - <<'PYTHON'
from lxml import etree
doc = etree.parse('wohngeld.xsd', parser=etree.XMLParser(resolve_entities=False,no_network=True))
print('XSD root:',doc.getroot().tag)
print('XSD elements:',len(doc.findall('.//{http://www.w3.org/2001/XMLSchema}element')))
try:
  etree.XMLSchema(doc)
  print('XSD compilation: PASS')
except Exception as e:
  print('XSD compilation: FAIL', repr(e))
PYTHON
```

Erst nach diesen echten Quell- und Schema-Prüfungen: Quelle/FIM-Zielgenauigkeit belegen, 15–30 Feldreferenzen mit konkreter FIM-ID und Kontext erstellen, negative Fehlzuordnungen testen, synthetischen Datensatz gegen wirkliches XSD prüfen, erst dann ein PDF/JSON-Exportexperiment bewerten. **Eine XSD-Kompilation ist noch keine Schema-Validierung eines Antrags.**

## 6. Förderrelevante Bewertung

1. **Bürgerproblem und möglicher Workflow sind greifbar:** Das nicht ausfüllbare Formular ist reale Verwaltungsinfrastruktur und keine erfundene Testaufgabe.
2. **Neuheitsrisiko bleibt:** Regex-Felderkennung, PDF-Overlays, Hashes oder JSON-Ausgabe sind keine Neuheit.
3. **Forschungshypothese wird präziser:** lokale, kontext-/rollenbewusste Extraktion und nachvollziehbarer Abgleich mit einer verifizierten amtlichen Schema-Version, inklusive Fehler-/Unbestimmtheitslogik.
4. **Noch kein GO für einen Förderantrag auf Basis eines bestandenen technischen PoC:** Die automatische, richtige Zuordnung zu *wirklichen* FIM-Feld-IDs ist offen.
5. **Keine Aussage über Behördenentlastung:** Weder reale Bearbeitungszeiten noch Rückfragen oder Integrationsaufwand wurden gemessen.

## 7. Befund / nächster zwingender Nachweis

**Status:** `PARTIAL_PASS_SOURCE_DOCUMENT_INSPECTED`; `PASS_OFFLINE_TEXT_SMOKE`; `EXTERNAL_DOWNLOAD_BLOCKED`; `REAL_FIM_MAPPING_NOT_RUN`.

Auf einem Host mit Netzberechtigung zuerst beide Originaldateien herunterladen, hashen und ihre Echtheit prüfen, dann ein echtes Mapping gegen die Schema-Elemente durchführen. Falls das PDF fachlich oder in seiner Formularversion nicht zur FIM-Referenzstruktur passt, dies als **SCHEMA_MISMATCH**, nicht als automatischen Feldexa-Fehler behandeln. Einen solchen Unterschied kann man als Forschungsfall nutzen, darf aber keine falsche Schemakonformität ausgeben.

**Referenzen**
- Amtliche Stadt-Fürth-PDF: https://www.fuerth.de/fileadmin/redaktion/01-Rathaus/Formulare/Nicht-Ausfuellbar/2026-02-13-Vordruck-Wohngeldantrag.pdf
- FIM-Schemarepository: https://docs.fitko.de/fim/docs/schema-repository/schemarepository-for-group-4/
- Bundesportal Verwaltungsweg: https://verwaltung.bund.de/leistungsverzeichnis/DE/leistung/99107023037000/herausgeber/BY-24752/region/090000000000
