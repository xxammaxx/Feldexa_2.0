# PR-#341-Review-Nachträge: P2-Dokumentationskorrekturen + T335-Integration (2026-11-27)

**Art**: Review-Nachtrag (Doku/Test/Kommentar, kein Produktverhalten) + Integration des
T335-Entscheidungsdokuments
**Kandidat**: `bbae22d` (3 Commits auf `5aa93cf`), Tree beim Gate `09845ac57200df9c8154dd8b1640b82891a645a4`
**Evidenzklassen**: `NONE` (Host: Format/Analyse/Tests/Messwerkzeug) + `EMULATOR`
(Maestro-Gate auf `emulator-5554`)
**Reviews der ursprünglichen Findings**: `run-tscn02hu/reports/release/reviews/2026-11-25-pr341-full-a-e0d35f7.md`,
`…pr341-full-b-e0d35f7.md`

## 1. Umsetzung der P2-Findings aus den PR-#341-Reviews

| Finding (Review) | Klasse | Umsetzung in `bbae22d` |
| --- | --- | --- |
| A-P2 „Multiline-Grenze nicht bis zur Vertragskante abgeleitet" | Doku | Bibliothekskopf `fillable_geometry.dart`: multiline-Vertikalregel (`lines.length × lineHeightPt ≤ rect.height − 3.0`, `EXP-001`/`too_many_lines` in `layout.dart:412-414`) als ausdrückliches Residual dokumentiert; die Aussage „A candidate that cannot is not offered" auf die abgeleiteten single-line-Regeln qualifiziert. Keine Verhaltensänderung. |
| A-P2 „`signature` ohne abgeleitetes Minimum" ist durch `layout.dart` widerlegt | Doku | Bullet korrigiert: §3.3 pad 1,0 pt je Seite, `signature_too_small` bei `min(w,h) ≤ 2.0 pt` (`layout.dart:45` `exportSignaturePaddingPt`, Block `:495-499`); label-erzwungenes `signature` ohne `signature_area`-Cue als #340-Klasse benannt; Enforcen als dokumentiertes Residual markiert. Filter bleibt `default: true`. |
| A-P2 + B-P2 „Typ-Tokens sind Literale / Default-Zweig ungetestet" | Test | Neu in `fillable_geometry_test.dart`: `schema coverage` — iteriert `SuggestionSchema.proposedTypes` und pinn, dass **genau** `signature` in den `default` fällt (Rename schlägt den Test), plus Fail-open-Pin für einen unbekannten Typ (`future_type`). |
| A-P2 „Flow-Kopfzeile verspricht Vor-Reopen-Assertion" | Doku | `export_journey.yaml` Header: vor dem Reload nur Undo/Durability (`Rückgängig`, `Gespeichert um`) und Zeilentitel; die Feldzustandszeile wird ausschließlich nach dem Reopen geprüft. Kommentar-only. |
| A-P2 + B-P2 „Gate-Receipt prozess-, nicht installationsbelegend" | Beleg | Dieser Gate-Lauf wurde mit vollständiger Installations-Provenanz gefahren (§2): Build aus `bbae22d`, Byte-Gleichheit lokal ↔ Gerät vor dem Lauf belegt und hier zusammen mit dem Receipt zitiert. |

Nicht umgesetzt (bewusst, mit Grund): das Ableiten/Erzwingen der Signatur-Untergrenze und
der multiline-Vertikalregel als **Filterverhalten** ist eine Produktentscheidung und gehört
zur #335-Entscheidung (Optionen B/D in `2026-11-26-t335-decision.md`), nicht in einen
Doku-Nachtrag.

## 2. Gate- und Installationsbeleg (zusammen zitiert — schließt A-P2/B-P2 Receipt)

- **Build**: `flutter build apk --debug` aus dem Kandidaten-Worktree (`bbae22d`),
  APK 232.001.811 B, lokal SHA-256 `ff2a43ef00598085bbd53ac3cae040a990623ea119f59bc2577d51b913c9156a`.
- **Installation**: `adb -s emulator-5554 install -r` → `Success`; Pfad
  `/data/app/~~RZRfLNydF-pa7CwLjjgPaQ==/de.feldexa.app-Prze7J7j5ys7RPzCcXi0Kg==/base.apk`;
  zurückgezogen und gemessen: **dieselbe SHA-256 `ff2a43ef…` (bytegleich)**.
- **Maestro-Gate** (`android_e2e_gate.py run` + `verify`, unter
  `compute_slot --resource build --resource emulator`):
  `result: PASS`, `exit_code: 0`, `duration_seconds: 103.854`,
  `candidate_commit: bbae22d889175f7dc83201b20afec9d1753a5c3d`,
  `candidate_tree: 09845ac57200df9c8154dd8b1640b82891a645a4`,
  `flow_sha256: 84715a2dff0bd493a04c0255cf96e902d37ddbc22f0f7e6fa0cc142dccce1518`
  (neu — der korrigierte Header-Kommentar),
  `log_sha256: 89506cad99c61b5da7f555b2a44c0a009d8130f518103d3eeadce71864241316`
  (identisch zu den Läufen auf `89506cad`-Vorgängern: deterministischer Log-Inhalt),
  Gerät `emulator-5554` / AVD `T025_Pixel7_API35_KVM_20261115`, Maestro 2.12.1,
  Receipt: `run-tscn02hu/reports/release/e2e-gate/run-t335-p2-bbae22d/receipt.json`.
- Der `installed_apk_identity: UNVERIFIED` des Receipts ist design-bedingt; er wird hier
  durch den separaten Pull+SHA-256-Vergleich oben geschlossen — beide Belege zusammen
  belegen Flow **und** installierte APK-Identität auf dem Kandidaten.
- `bbae22d` ändert keinen kompilierten Produktcode (Kommentare, Test, YAML-Kommentar,
  Doku/Artifacts); die installierte APK gilt damit für den PR-Head modulo der Docs-Commits
  (Commit 2 fügt nur diesen Report und README-Zeilen hinzu).

## 3. Host-Gates (Kandidat `bbae22d`)

- `dart format --output=none --set-exit-if-changed` über alle berührten Dart-Dateien: 0
  Änderungen (das Messwerkzeug wurde einmal formatiert; Ausgabe vorher/nachher
  byte-identisch, gegen gemessen).
- `flutter analyze --no-pub` (Workspace): **No issues found**.
- `packages/feldexa_recognition`: `flutter test test/fillable_geometry_test.dart` →
  **15/15 PASS** (inkl. der beiden neuen Schema-Coverage-Pins); Paket-Suite **411/411 PASS**.
- Repo-Guards: `python3 -m unittest discover -s tools/repo -p 'test_*.py'` — Ergebnis in
  Commit 2 geprüft (Index-Zeilen sind Teil von Commit 2).

## 4. T335-Integration (gleicher Kandidaten-Branch)

- `2026-11-26-t335-decision.md`: Entscheidungsvorlage zu #335, Neumessung 2026-11-27 auf
  `5aa93cf` (Erstlauf-Basis `8196e04` bleibt als Vergleichsartifact). Kernzahlen: 55
  Vorschläge / 23 deklarierte Felder, 23 `real_field`, 7 Typfehler; `a12afc9` hat
  `Betrag 1` korrigiert und `Summe` regressioniert (§5.3), `optionA` unverändert (8).
- **Bindung**: auf dem kommittierten Baum reproduziert `dart run
  tools/evaluation/t335_suggestion_inventory.dart` die committete
  `artifacts/2026-11-27-t335/suggestions.json` **byte-identisch** (`cmp`-Beleg, 2026-11-27).
- Evidenzklasse der Vorlage: `NONE` (Host). Keine Schwellenänderung, keine Umsetzung;
  Review offen, Owner-Entscheidung steht aus (§8 der Vorlage).

## 5. Offene Punkte

- Owner-Entscheidung zu #335 (Optionen A/B/C/D) steht aus — die Vorlage ist dafür der Input.
- Die beiden Residuale (Signatur-Bilduntergrenze, multiline-Vertikalregel) sind dokumentiert,
  aber nicht als Filterverhalten umgesetzt (bewusst, §1).
