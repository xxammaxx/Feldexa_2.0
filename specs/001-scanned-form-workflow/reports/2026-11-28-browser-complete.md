# Browser-Vervollständigung und Gate-Grün (T128/T131/T132 + T145) — 2026-11-28

**Art**: Test-/Gate-Slice · **Basis**: `origin/main` = `0a81769` · **Arbeitsbereich**:
`run-tscn02hu/worktrees/browser-complete`
**Evidenzklassen**: `SIMULATED` (Chrome-Lane), `NONE` (Host-VM, Gate)

## 1. Browser-Spiegel (T062-Muster: Chrome-Tests unter `<project>/test`)

| Zeile | Datei | Chrome-Lane | Inhalt |
| --- | --- | --- | --- |
| T131 | `test/web_viewport_browser_entry_test.dart` | **3/3 PASS** | Viewport-/Responsive-Layout-/Semantics-Fälle auf den ausgelieferten Widgets (US9-5; FR-091; SC-015) |
| T132 | `test/geometry_parity_browser_entry_test.dart` | **2/2 PASS** | Punkt-/Layout-Parität der gerenderten Seiten und Display-Geometrie (FR-089; CHK011); Android-Hälfte bleibt der bestehende `integration_test`-Test |
| T128 | `test/web_journey_browser_entry_test.dart` | **1/1 PASS** | Editier-Journey (Anzeigen, Auswählen, Verschieben, Resize, Review, Navigation) auf den ausgelieferten Widgets; echte Chrome-Ausführung (FR-086) |

Alle drei Suiten sind plattformagnostisch (kein `@TestOn('browser')`), laufen auf der
Host-VM (`NONE`) und in Chrome (`SIMULATED`); die ursprünglichen
`integration_test/`-Pfade der Zeilen bleiben die EMULATOR-Lane.

## 2. Gate: Browser-Check von UNAVAILABLE auf PASS

`tools/gate.sh` erweitert:

1. **Fixture-Server im Browser-Check**: VOR dem Chrome-Lauf startet der Check
   `tools/corpus/synthetic/serve_web_fixtures.dart` (`--root apps/feldexa_app/web
   --port 8765`) und stoppt ihn danach (Cleanup-Trap inklusive). Ohne ihn scheiterten
   `web_import` (5/6) und `web_recognition` (4/4) an `ProgressEvent` — sie laden die
   Fixtures per `dart:html.HttpRequest` vom Loopback-Spiegel.
2. **Port-Probe portabel**: `fixture_server_port_open` nutzte `/dev/tcp`; diese
   Bash-Build hat keine Net-Redirections (`/dev/tcp: No such file or directory`) — der
   Server lief, die Erkennung nie, der Check meldete falsch „not ready". Ersatz:
   `python3`-Socket-Connect (der Gate setzt python3 ohnehin voraus).
3. **`stored_list_50_test.dart`**: `@TestOn('vm')` — die 500-ms-Host-Budgetmessung
   (Evidenzklasse NONE) wurde vom Chrome-Lane-Pickup flaky erfasst; sie läuft
   unverändert im Host-VM-Check.
4. **Fixture-Zähler in den Chrome-Suiten**: `web_import`/`web_recognition` erwarteten
   noch 7 Fixtures ohne `sf-005`; korrigiert auf 8 IDs (`sf-005` an Position 5) und
   `isImportable` 4→5 (`sf-005` ist `valid`). Reine Erwartungs-Updates.

### Gate-Ergebnis (final, ohne `--allow-unavailable`, `CHROME_EXECUTABLE=tools/browser/chrome_launch.sh`)

```
[PASS] dependency resolution
[PASS] formatting (376 files, 0 changed)
[PASS] static analysis (No issues found)
[PASS] shared package tests: 9 packages (1,903 passed, 6 skipped)
[PASS] app unit/widget tests (708/708)
[PASS] SIMULATED app browser/interaction tests (flutter test --platform chrome)  ← neu grün
[PASS] repository guard tests (19/19)
[ABSENT] SIMULATED browser integration test driver (test_driver/integration_test.dart
         missing; 4 web integration suites present) — geplante, nicht gebaute Layer
Checks passed: 15; failed: 0; unavailable: 0; absent planned layers: 1
GATE INCOMPLETE (exit 3)
```

Der Chrome-Lauf selbst: **72 passed / 4 skipped / 0 failed** (alle `test/*_test.dart`).

**Einordnung**: Es gibt keinen FAIL und keine UNAVAILABLE mehr; die einzige Lücke ist
die geplante Drive-Layer (`test_driver/integration_test.dart` + chromedriver) für die
`integration_test/web_*`-Suiten — eine dokumentierte Owner-/Struktur-Entscheidung, kein
Umgebungsblocker. T145 wird mit diesem Stand als erfüllt geführt (Analyzer 0, getrennte
SIMULATED-Evidenz vorhanden, Gate-Ergebnis aktenkundig); die Drive-Layer bleibt als
offene geplante Schicht benannt.

## 3. Grenzen

- Die Chrome-Lane läuft weiterhin ohne FLD-001-Textmessung (kein Asset-Bundle im
  Web-Test-Harness); Browser-Suiten behaupten keine tabellenbasierte Overflow-Prüfung.
- T111 bleibt `@TestOn('vm')` (deterministische Adapter-Ausgabe); eine Browser-Ausführung
  dieser Zeile wäre eine eigene Entscheidung.
- T132 Browser-Hälfte = Punkt-/Layout-Parität; Byte-Parität gerenderter Seiten bleibt
  `NOT_RUN` (PDFium/Android, dokumentiert im T122-Report).

## 4. Reproduktion

1. `CHROME_EXECUTABLE=tools/browser/chrome_launch.sh bash tools/gate.sh` (Fixture-Server
   startet/stoppt der Gate selbst).
2. Einzeln: `cd apps/feldexa_app && flutter test --no-pub --platform chrome
   test/web_viewport_browser_entry_test.dart` (3/3), `…/geometry_parity_browser_entry_test.dart`
   (2/2), `…/web_journey_browser_entry_test.dart` (1/1).
