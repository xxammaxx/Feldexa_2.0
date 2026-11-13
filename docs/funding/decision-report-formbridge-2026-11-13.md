# Entscheidungsbericht FormBridge → Prototype Fund 2027 (Jahrgang 03, Innovation)

**Datum:** 13.11.2026 · **Bezug:** Issue #167 · Basis: `prior-art-audit-2026-11-13.md`, `innovation-assessment-2026-11-13.md`, `reference-wohngeld-fim-2026-11-13.md`, `formbridge-module-spec-2026-11-13.md`, `prototypefund-feasibility-2026-11-13.md`

## Empfehlung: **CONDITIONAL_GO**

FormBridge (eng gefasst, als app-unabhängiges Infrastrukturmodul) ist nach Quellcode-Audit und Referenzfall-Validierung eine **tragfähige, abrechnungsehrliche** Bewerbungshypothese für die Förderlinie Innovation (Frist 30.11.2026, 15:00 CET). Die GO gilt unter den Bedingungen B1–B4 unten; solange sie offen sind, ist der Status **conditional**, nicht go.

## Evidenz in Kürze

1. **Kein geprüftes OSS-Projekt** implementiert die Kette statisches Behörden-PDF → versionierte FIM-Datenfeld-IDs mit Koordinaten, Confidence/UNKNOWN, Human-Gate, Provenienz und Validierung (13 Repos geprüft; die beiden kritischen deutschen Projekte KIWO und Formularagent erstmals im Quellcode, nicht nur nach Beschreibung).
2. **Die Lücke ist Ökosystem-dokumentiert:** FITKO dokumentiert den XDF-Konvertierungspfad als „in der Konzeption" (docs.fitko.de, 13.11.2026).
3. **Neu entdecktes, belegbares Problem:** Das offizielle immutable XSD S00000159v1.4 ist standardkonform nicht kompilierbar (170 Parser-Fehler, libxml2/xmllint); Reparatur + Instanz-Validierung im Repo dokumentiert — Substanz für RF2 und für Ökosystem-Nutzen.
4. **Referenzfall real:** Fürth-PDF (Hash, 8 Seiten, Textlage) ↔ FIM-Schema: nur 7/30 Referenzfelder trivial mappbar; 7 Kontext-Mehrdeutigkeiten, 4 Codelisten, 4 Strukturtransformationen, 3 fachliche Deckungslücken (u. a. Vermieter-Identität nicht repräsentierbar) — die Forschungsfragen sind real, nicht konstruiert.
5. **Förderpassung verifiziert:** Innovation erlaubt ausdrücklich „neues Modul für bestehende Software"; Bestandsprojekte zulässig bei klarer Abgrenzung; hoher Entwicklungsanteil; FOSS-Pflicht — alles offiziell belegt.

## Bedingungen (B1–B4) für echtes GO

| # | Bedingung | Fälligkeit |
|---|---|---|
| B1 | **Formale Klärung Antragsteller** (Einzelperson Wohnsitz DE / Team-GbR) + Portal-Check aktueller Kriterien + Teilnahme an Sprechstunde 16.11.2026 | vor Einreichung |
| B2 | **Entscheid Feldexa vs. RepairProbe** für genau eine Bewerbung (RepairProbe bleibt unverändert; Vergleichskriterien lt. Issue #165 G5) | vor Einreichung |
| B3 | **Modul-Repo-Isolierung beschließen** (eigenes Repo/Lizenz; kein Produktcode im Förderumfang; bis Förderbeginn keine Modul-Implementierung, um Vorab-Leistungs-Problematik zu vermeiden) | vor Einreichung |
| B4 | **Falsifikations-Fortlauf:** Suche nach konkurrierenden Projekten (incl. FITKO-Announcements) bis Abgabedatum; bei fundierter Widerlegung → PIVOT (Alternative: Schema-Hygiene-Tool + Provenienzformat als schmaleres Vorhaben) | bis 30.11.2026 |
| B5 | **De-Overclaim-Pass auf Bewerbungstext** (keine universalen Negativbehauptungen; Nutzenkette nicht über das Modul hinaus) | vor Einreichung — in Revisionsstufe 2 (13.11.2026) vorab umgesetzt, vor Einreichung final prüfen |
| B6 | **Kein Zirkel-Evaluationsszenario:** Held-out-Dokument (andere Landes-Variante) + externe Testpersonen für RF4 in Spec §6/§7 verankert | vor Einreichung — in Revisionsstufe 2 verankert; konkrete Beschaffung des Held-out-PDFs klären |

## Unbeantwortete Fragen (ehrlich offen)

- Jury-Perspektive auf Verwaltungs-Infrastruktur (keine Quelle; Risikominderung über Bürger-Nutzen-Erzählung).
- Genauigkeit der Codelisten-Zuordnungen fachlich (FIM-Portal-Referenzcheck steht aus — Modul-Arbeit, nicht Recherche-Rest).
- Ob weitere amtliche XSDs dieselben Defektklassen zeigen (RF2-Korpus erst im Förderzeitraum).
- Feldexa-Produkt-E2E-Pilot (#165) bleibt NOT_RUN bis separate Freigabe; nicht Bedingung dieser Bewerbung, aber wertvoller Messlieferant.

## Nächste Aktionen (konkret)

1. B1–B3 durch Maintainer entscheiden (keine Agentur-Aktion möglich).
2. Falls GO bestätigt: Bewerbungsbausteine (E) finalisieren, Portal-Felder ausfüllen, Audit-Matrix als Anhang exportieren, Einreichung vor 30.11.2026 15:00 CET.
3. Issue #165 (Produkt-Pilot) bleibt separat; Issue #151/#167-Verweise pflegen.
4. Falls PIVOT/NO_GO: Schema-Hygiene + Provenienzformat als eigenständige, kleinere FOSS-Beitragsoption dokumentieren (keine Förderabhängigkeit).

## Was diese Empfehlung NICHT ist

Keine Förderzusage, keine Erfolgsprognose, keine Freigabe von Implementierung oder Produktaufgaben, kein Merge. Proposal PR bleibt Draft.
