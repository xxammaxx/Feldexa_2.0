# Issue #344, Teil A — zweites Artefakt, Zeilenheilung, 1-mm-Platzierungsmessung

**Datum**: 2026-11-26 · **Branch**: `xxammaxx/t344-export-proof-depth` · **Basis**:
`14bf4ab` (Merge PR #345) · **Rolle**: build/E2E, einziger Writer im Worktree · **Scope**:
Test, Treiber, Evidenz, Doku. Kein Produktcode (`apps/feldexa_app/lib`,
`apps/feldexa_app/android`, `packages/*`), `apps/feldexa_app/e2e/export_journey.yaml`
unverändert, keine Schwellenwerte im Produkt.

## Ergebnis in einem Satz

Der Beleg-Treiber hat in **einem** vollständigen Lauf zwei Artefakte (Erstöffnung und
Wiederöffnung des Dokuments) mit je eigenem Digest, eigenem Host-Pickup und eigenem
Poppler-Beleg abgeholt und `PASS` gemeldet; die 1-mm-Platzierung ist in der im Brief
vorgegebenen **Mittelpunkts-Metrik** ehrlich **`NICHT belegt`** — die gemessene
Mittelpunkt-Abweichung beträgt `dx = -132.140 pt`, `dy = -3.050 pt` bei einer Toleranz von
`2.835 pt`, weil der Export-Vertrag den Wert linksbündig an die obere linke Rect-Ecke
zeichnet (§3.1) und nicht zentriert.

| | |
| --- | --- |
| Code-Commit (Lauf-Commit, `head`) | `162baa985aaac57b664269be38054e163658eca5`, tree `715777b8ffe88c5808bfbc2b050b979935a0c5ef` |
| Treiber-Hash | `c1cfde50dff7ce85e31f6a8a83c352cd6f5f30e5ca5a44227e6122b6a5b8905b` |
| Test-Hash | `c84ee5b994e46ea165727f19c776a38279f5fcaa1596a749338196d34687ff9c` |
| Evidenzverzeichnis | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t344-export-proof-depth/` (29 Dateien) |
| Artefakt 1 | `12029` B, `sha256 8da0ce1fcf11bd4cc16d3860c4fd04e7d2537fe0927acd87d9dfc340e11e9484` |
| Artefakt 2 | `12029` B, `sha256 dcf302e2bc6b2c0f58e28efcafced381896e9205a053d0d47114a49694a198ec` |
| Gerät | `emulator-5554`, AVD `T025_Pixel7_API35_KVM_20261115`, API 35, `qemu=1`, boot completed, `non_emulator_transports_addressed=none` |
| Ergebnis | `result=PASS`, `flutter_test_exit=0`, `All tests passed!`, Platzierung `NOT_PROVEN` |

Wörtliche Treiberausgabe des Laufs (`/tmp/t344a-driver-console2.log`, 12:38:23–12:42:2x UTC).
Der Treiber gibt das Evidenzverzeichnis **absolut** aus (`:155`); die beiden betroffenen
Zeilen sind auf `<ROOT>` normalisiert, damit keine Zeile als „wörtlich“ gilt, die es nicht ist:

```
T334 DRIVER: PASS (flutter test exit 0; cleanup marker observed; two artifacts picked up with matching digests; poppler proof for both; static gates clean; privacy checks PASS; 1 mm placement claim NOT_PROVEN)
T334 DRIVER: evidence written to <ROOT>/specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t344-export-proof-depth
T334 DRIVER: PASS
```

## 0. Bekannt-latenter Defekt geheilt (1 Zeile)

`tools/android/t334_drive_export.sh`: die in `2026-11-26-t342b-driver-hardening.md`
(„Bekannt-latent“) dokumentierte Zeilenverkettung ist getrennt. Stand jetzt:

```bash
adb_shell rm -f "$STAGING/ack-artifact-picked-up-$PICKUP_INDEX" >/dev/null ||
  fail "cannot remove a stale pickup acknowledgement before the pickup retry"
PICKUP_OK=0
```

`PICKUP_OK=0` ist eine eigene Zeile. Kein weiteres Refactoring an dieser Stelle.

## 1. Zweites Artefakt nach erneutem Öffnen (Issue #344 Punkt 3)

**Test-Seite** (`apps/feldexa_app/integration_test/android_export_test.dart`): Nach dem
ersten vollständigen Zyklus (Export → Digest-Storage → Host-Pickup → Vorschau schließen →
`EXP-002`) wird

1. die Editor-Route über den Navigator geschlossen (zurück auf die Startliste),
2. die Zeile des Dokuments in der Startliste (`stored-item-<documentId>`) angetippt und das
   Dokument über den produktiven `_openStoredDocument`-Pfad **erneut geöffnet**,
3. der bestätigte Feldzustand erneut geprüft: derselbe `ConfirmedField` (Id), **identisches
   Rect** (`expect(reopenedField.rect, field.rect)`), `TextValue` mit `overflow == false`
   und demselben Wert, `pageCount == 2` → Marker
   `T334_DOCUMENT_REOPENED:PAGES=2:FIELD_RECT_MATCH=1:VALUE_MATCH=1`,
4. ein **zweiter** Export über denselben produktiven `ExportController` (`prepare` + `run`,
   `_exportLiveRevision` ist für beide Zyklen dieselbe Funktion) gefahren, mit denselben
   Assertions (`_expectVerifiedArtifact`: `succeeded`, `byteSize > 0`, 64-hex-Digest,
   `pageCount == 2`, alle fünf `ArtifactVerification`-Flags),
5. die Bytes unter `e2e/export-artifact-2.pdf` im app-internen Verzeichnis abgelegt, mit
   Index, Bytes und SHA-256 als Marker, und auf die Host-Ack-Datei **dieses** Index
   (`ack-artifact-picked-up-2`) gewartet,
6. die produktive `ExportPreviewScreen` geöffnet, geschlossen und die Löschung über
   `export.readArtifact` → `EXP-002` erneut belegt (mit `INDEX=2`).

Der erste Zyklus bleibt inhaltlich unverändert funktionsfähig; er trägt nur zusätzlich
`INDEX=1` in seinen Markern (siehe Marker-Sequenz unten). Ack-Dateien sind indexiert:
`ack-artifact-picked-up-1`, `ack-artifact-picked-up-2`.

**Treiber-Seite**: Pickup-Schleife über Index 1..2 — je Index wird auf den Marker
`T334_ARTIFACT_STORED:INDEX=<n>` gewartet, der Marker geparst (Pfad/Bytes/SHA-256), der
Pfad-Suffix gegen den erwarteten Gerätepfad geprüft, per `run-as cat` mit Digest-Prüfung
gelesen (3 Versuche), die Ack-Datei **dieses** Index geschrieben und der Pickup protokolliert.
Nach Testende wird **jedes** Artefakt gegen **seinen** Marker geprüft (Bytes und Digest) und
**einzeln** extern belegt (`pdfinfo`, `pdftotext`, `/AcroForm`-Byte-Suche). Evidenzdateien je
Artefakt getrennt; die alten Dateinamen (`artifact-pickup.txt`, `poppler-pdfinfo.txt`,
`poppler-pdftotext.txt`, `artifact-bytes-acroform.txt`, `export-artifact.pdf`) sind bewusst
**nicht** beibehalten, weil sie ohne Index mehrdeutig wären:

| Artefakt 1 | Artefakt 2 | Inhalt |
| --- | --- | --- |
| `artifact-1-pickup.txt` | `artifact-2-pickup.txt` | Pfad, Gerätepfad, Bytes, Digest, Marker-Match |
| `artifact-1-pdfinfo.txt` | `artifact-2-pdfinfo.txt` | `pdfinfo` Quelle + Artefakt, Seiten/Seitenformat-Vergleich |
| `artifact-1-pdftotext.txt` | `artifact-2-pdftotext.txt` | Textextraktion, Umlaut-Treffer, `M?ller` = 0 |
| `artifact-1-acroform.txt` | `artifact-2-acroform.txt` | Byte-Suche `/AcroForm` mit Grep-Exit |
| `artifact-1-placement.txt` | `artifact-2-placement.txt` | 1-mm-Messung (siehe §2) |
| `export-artifact-1.pdf` | `export-artifact-2.pdf` | die abgeholten PDFs |

Beide Zyklen sind durch Marker, Marker-Digest, Host-Digest und Poppler-Ausgabe belegt:

```
T334 DRIVER: host pickup artifact 1: 12029 bytes, sha256 8da0ce1fcf11bd4cc16d3860c4fd04e7d2537fe0927acd87d9dfc340e11e9484 (marker matches)
T334 DRIVER: host pickup artifact 2: 12029 bytes, sha256 dcf302e2bc6b2c0f58e28efcafced381896e9205a053d0d47114a49694a198ec (marker matches)
```

`artifact-1-pickup.txt` / `artifact-2-pickup.txt`: `sha256_matches_marker=1`,
`size_matches_marker=1`; `artifact-1-pdfinfo.txt` / `artifact-2-pdfinfo.txt`: `Pages: 2`,
`Page size: 595.28 x 841.89 pts (A4)` = Quelle; `artifact-1-acroform.txt` /
`artifact-2-acroform.txt`: `acroform_byte_occurrences=0`, `acroform_grep_exit=1`;
`artifact-1-pdftotext.txt` / `artifact-2-pdftotext.txt`: `entered_value_occurrences=1`,
`12:Müller`, `umlaut_replaced_by_question_mark=0`.

Die beiden Digests unterscheiden sich (`8da0ce1f…` vs. `dcf302e2…`) bei identischer Größe
(12 029 B) und identischem Inhalt — dasselbe Verhalten wie in
`2026-11-26-t334-android-export-verification.md` §7 (nicht byte-reproduzierbar, siehe §5).

## 2. 1-mm-Platzierungstoleranz — **NICHT belegt** (mit Grund)

### Vorgehen (wie im Brief)

1. Der Test gibt das tatsächlich verwendete Feld-Rect als **reine Zahlen** aus:
   `T334_FIELD_RECT:PAGE=1:X_MPT=190125:Y_MPT=147625:W_MPT=299875:H_MPT=18000`
   (Milli-Punkt). Kein Label, kein Wert, kein Text im Marker.
   **Koordinatenkonvention** (im Code kommentiert und im Evidenzfile benannt):
   Display-Space — Ursprung in der **linken oberen Seitenecke**, x nach rechts, **y nach
   unten**, Einheit PDF-Point (1/72 in). Das ist dieselbe Konvention, die Poppler mit
   `pdftotext -bbox` ausgibt; die Rect-Werte stammen aus `core.ConfirmedField.rect`
   („display-space rectangle in PDF points“, `packages/feldexa_core/lib/src/model/field.dart`).
2. Host: `pdftotext -bbox -f <page> -l <page>` auf das abgeholte Artefakt, das
   `<word xMin=… yMin=… xMax=… yMax=…>`-Element des eingegebenen Werts per
   Attribut-Muster herausgegriffen (genau **ein** Treffer gefordert), Mittelpunkt gegen den
   Rect-Mittelpunkt gerechnet.
3. Toleranz 2,835 pt (1 mm), x- und y-Abweichung einzeln, Zahlen wörtlich unten.

### Zahlen (beide Artefakte identisch, `artifact-{1,2}-placement.txt`)

```
command=pdftotext -bbox -f 1 -l 1 <artifact-1> <xml>
field_rect_marker=T334_FIELD_RECT:PAGE=1:X_MPT=190125:Y_MPT=147625:W_MPT=299875:H_MPT=18000
axis_convention=display space; origin at the page's top-left corner, x to the right, y downwards; Poppler -bbox reports the same origin and direction, so no flip is applied
page_height_pt=841.89
page=1 value_word_matches=1
rect_pt=190.125,147.625,299.875,18.000
rect_center_pt=340.062,156.625
value_bbox_pt=191.625000,146.219790,224.219400,160.929390
value_bbox_center_pt=207.922,153.575
deviation_pt=dx=-132.140,dy=-3.050
tolerance_pt=2.835
axis_convention_check=consistent
verdict=NOT_PROVEN
reason=artifact 1: centre deviation dx=-132.140 pt / dy=-3.050 pt exceeds 2.835 pt
```

Die Achsen-Zuordnung ist zusätzlich gegen ein halbseitiges Kriterium geprüft
(`axis_convention_check=consistent`: Rect-Mittelpunkt und Wort-Box liegen auf derselben
Seitenhälfte); ein Achsen-Dreher hätte `NOT_PROVEN` mit Achsen-Grund ergeben, nicht eine
stille Zahl.

### Grund (warum „nicht belegt“ und nicht „Toleranz gerissen“)

Die Brief-Metrik ist die **Mittelpunkts-Abweichung gegen den Rect-Mittelpunkt**. Der
Export-Vertrag zeichnet den Wert aber nicht zentriert, sondern **linksbündig mit 1,5 pt
Padding** an der oberen linken Rect-Ecke (`contracts/export-plan.md` §3.1; Umsetzung:
`PdfExportService.drawText` — `val left = op.rect.x + TEXT_PADDING_PT`, Baseline
`rect.y + baselineFromTopPt`, `layout.dart`: `baselineFromTopPt = 1.5 + 0.8 · fontSizePt`).
Deshalb liegt der Messbefund genau dort, wo der Vertrag ihn haben will:

- `value_bbox xMin = 191.625` = `rect.x 190.125` **+ 1.500 pt** (exakt das Padding),
- der Rect-Mittelpunkt `340.062` ist bei einem 299,875 pt breiten Rect und einem ~32,6 pt
  breiten Wort konstruktionsgemäß ~132 pt entfernt (ein zentrierter Satz wäre die
  Ausnahme, nicht die Regel).
- `dy = -3.050` entsteht, weil die Poppler-Box die **Font-Ascent-Box** ist
  (`yMin = 146.220`, also 1,4 pt über dem Rect-Oberrand) und die Baseline oben sitzt; auch
  dieser Wert folgt aus §3.1, nicht aus einer Fehlplatzierung.

Damit ist die Aussage „gezeichneter Wert liegt innerhalb 1 mm am **Rect-Mittelpunkt**“
**nicht belegt** und mit diesem Layout auch nicht belegbar. Die Toleranz wurde **nicht**
verändert, es wurden **keine** Zahlen geschätzt oder umgerechnet, und es wurde **keine**
Ersatz-Metrik zur PASS-Erklärung erhoben: die Abweichung vom Vertragsanker (`xMin` gegen
`rect.x + 1.5`) ist oben nur als Beobachtung aus den bereits protokollierten Zahlen
genannt (0,000 pt), **nicht** als Ersatz-Verdikt. Welche Metrik Issue #344 Punkt 1
akzeptieren soll (Rect-Mittelpunkt vs. Vertragsanker), ist eine Owner-Entscheidung — siehe
§5 Punkt 1.

## 3. Marker-Sequenz (wörtlich aus `markers-integration.txt`)

```
T334_FIXTURE_READY:BYTES=5956:MATCH=1
T334_START_LIST_READY
T334_IMPORT_ARMED
T334_EDITOR_READY
T334_ANALYSIS_READY:PAGES=2:SUGGESTIONS=59
T334_NAMED_SUGGESTION_FOUND:PAGE=1
T334_MACHINE_FIELD_CONFIRMED:PAGE=1:W_MILLI=299875:H_MILLI=18000
T334_FIELD_RECT:PAGE=1:X_MPT=190125:Y_MPT=147625:W_MPT=299875:H_MPT=18000
T334_VALUE_SAVED:RUNES=6:OVERFLOW=0
T334_EXPORT_PLAN_READY:INDEX=1
T334_EXPORT_VERIFIED:INDEX=1:PAGES=2:BOUND=1:BYTES_GT_0=1:ALL_CHECKS_PASSED=1
T334_ARTIFACT_BYTES:INDEX=1:PATH_BYTES=12029:SHA256_MATCH=1
T334_ARTIFACT_STORED:INDEX=1:PATH=/data/user/0/de.feldexa.app/code_cache/e2e/export-artifact.pdf:BYTES=12029:SHA256=8da0ce1fcf11bd4cc16d3860c4fd04e7d2537fe0927acd87d9dfc340e11e9484
T334_WAITING_FOR_HOST_PICKUP:INDEX=1
T334_HOST_PICKUP_ACKED:INDEX=1
T334_PREVIEW_OPEN:INDEX=1
T334_PREVIEW_CLOSED:INDEX=1
T334_ARTIFACT_DELETED_AFTER_PREVIEW_CLOSE:INDEX=1:CODE=EXP-002
T334_DOCUMENT_REOPENED:PAGES=2:FIELD_RECT_MATCH=1:VALUE_MATCH=1
T334_EXPORT_PLAN_READY:INDEX=2
T334_EXPORT_VERIFIED:INDEX=2:PAGES=2:BOUND=1:BYTES_GT_0=1:ALL_CHECKS_PASSED=1
T334_ARTIFACT_BYTES:INDEX=2:PATH_BYTES=12029:SHA256_MATCH=1
T334_ARTIFACT_STORED:INDEX=2:PATH=/data/user/0/de.feldexa.app/code_cache/e2e/export-artifact-2.pdf:BYTES=12029:SHA256=dcf302e2bc6b2c0f58e28efcafced381896e9205a053d0d47114a49694a198ec
T334_WAITING_FOR_HOST_PICKUP:INDEX=2
T334_HOST_PICKUP_ACKED:INDEX=2
T334_PREVIEW_OPEN:INDEX=2
T334_PREVIEW_CLOSED:INDEX=2
T334_ARTIFACT_DELETED_AFTER_PREVIEW_CLOSE:INDEX=2:CODE=EXP-002
T334_CLEANUP_DONE
00:42 +1: (tearDownAll)
00:44 +1: All tests passed!
```

Marker tragen weiterhin nur Phasennamen, Zähler, Indizes, den Gerätepfad des Artefakts und
Hex-Digests; `T334_FIELD_RECT` trägt ausschließlich Zahlen. Die Privacy-Greps des Treibers
sind grün: `PASS: no document content, field label, display name, or fixture path in the
integration log`, `PASS: no network API reference in integration_test/…`.

## 4. Gates und Gerät

| Gate | Ergebnis | Beleg |
| --- | --- | --- |
| `bash -n tools/android/t334_drive_export.sh` | Exit 0 | lokal |
| `grep -n '|| true' tools/android/t334_drive_export.sh` | keine Treffer | lokal |
| `flutter analyze --no-pub` (App) | `No issues found! (ran in 101.7s)` | `gate-analyze.txt` |
| `dart format --output=none --set-exit-if-changed .` (App, im Lauf) | `Formatted 120 files (0 changed)` | `gate-format.txt` |
| `dart format --output=none --set-exit-if-changed packages apps` (zusätzlich, vor dem Lauf) | `Formatted 319 files (0 changed)`, Exit 0 | Konsolenausgabe |
| App-Testsuiten Export/Editor (`export_controller_test`, `export_preview_test`, `editor_export_action_test`, `editor_composition_test`) | `+62: All tests passed!` | Konsolenausgabe |
| `packages/feldexa_export` Testsuiten | `+121: All tests passed!` | Konsolenausgabe |
| Gerätebindung | `serial=emulator-5554`, `emulator_transports=1`, `all_attached_transports_count=2`, `non_emulator_transports=1`, `non_emulator_transports_addressed=none` | `device-binding.txt` |
| Permit | eine Admission `{"compute_slot": "ACQUIRED", …}`, `SETTLED exit_code: 0`, `orca_command_used=0`, `detached_jobs=0` | `compute-lock.txt` + Konsole |
| Store-Probe | drei Fälle (`empty`, `leftover`, `missing`) wie erwartet | `store-probe.txt` |
| APK | `app-debug.apk`, Digest/Größe protokolliert | `apk-sha256.txt` |
| Git-Bindung | `head=162baa98…`, `tree=715777b8…`, `status_porcelain:` leer, `test_sha256=c84ee5b9…`, `driver_sha256=c1cfde50…` | `git-identity.txt` |

Der Emulator war die ganze Zeit der einzige adressierte Transport (`adb -s emulator-5554`);
das physische S23 (`adb-RFCW80SMY4J-…`) war verbunden, wurde aber nicht adressiert
(`non_emulator_transports_addressed=none`), kein `adb kill-server`, kein Emulator-Neustart.

## 5. Belegt / nicht belegt und offene Punkte

| Aussage | Status | Beleg |
| --- | --- | --- |
| Zeilenverkettung `fail …PICKUP_OK=0` geheilt | **belegt** | Code-Stelle, `bash -n` Exit 0 |
| Zweiter Export nach erneutem Öffnen des Dokuments | **belegt** | `DOCUMENT_REOPENED` + 2 × `EXPORT_VERIFIED` + 2 × `ARTIFACT_STORED` mit verschiedenen Digests |
| Feldzustand nach Wiederöffnung unverändert (Rect + Wert) | **belegt** | `expect(reopenedField.rect, field.rect)`, `TextValue` = eingegebener Wert, `overflow == false` |
| Beide Artefakte extern belegt (Seiten, Seitengröße, Wert, kein `/AcroForm`) | **belegt** | `artifact-{1,2}-pdfinfo.txt`, `-pdftotext.txt`, `-acroform.txt` |
| Beide Vorschau-/Löschzyklen (`EXP-002`) | **belegt** | `ARTIFACT_DELETED_AFTER_PREVIEW_CLOSE:INDEX=1|2:CODE=EXP-002` |
| 1-mm-Platzierung am **Rect-Mittelpunkt** | **NICHT belegt** | §2: `dx=-132.140 pt`, `dy=-3.050 pt` > `2.835 pt`; Ursache: linksbündiges Layout nach §3.1 |
| Digest-Reproduzierbarkeit über Läufe | **NICHT belegt** (unverändert) | zwei Artefakte desselben Laufs, gleiche Größe, verschiedene Digests |
| AcroForm-Fixture / interaktives Feld | **NICHT belegt** (Teil B) | kein AcroForm-Fixture in diesem Slice |

Offene Punkte:

1. **Metrik-Entscheidung für Issue #344 Punkt 1 (Owner).** Die Brief-Metrik
   (Mittelpunkt gegen Rect-Mittelpunkt) ist mit dem vertraglich linksbündigen Layout
   strukturell nicht erfüllbar. Entweder wird die Abnahme auf den Vertragsanker
   (`rect.x + 1.5`, Baseline `rect.y + 1.5 + 0.8 · fontSizePt`) umgestellt — dann ist die
   Messung aus denselben Zahlen ableitbar —, oder die Anforderung selbst wird geändert.
   In diesem Lauf wurde **keine** der beiden Varianten als PASS erklärt und die Toleranz
   nicht angefasst.
2. **Evidenzdatei-Namen geändert** (`artifact-N-*` statt `artifact-pickup.txt` /
   `poppler-*` / `artifact-bytes-acroform.txt`; `export-artifact-1.pdf` statt
   `export-artifact.pdf`). Frühere Evidenzverzeichnisse bleiben byte-identisch, aber
   Werkzeuge/Reports, die die alten Namen greppen, müssen angepasst werden.
3. **Verworfener Vorlauf.** Die erste Fassung des Treibers dieser Sitzung
   (`sha256 251b3275…`) parste `H_MPT` (letztes Markerfeld, ohne abschließenden Doppelpunkt)
   nicht und rechnete `dy` gegen ein Rect der Höhe 0 (`dy=+5.950`). Der Fehler ist in
   `162baa9` behoben (Parse-Muster akzeptiert Zeilenende, jedes Rect-Feld wird auf
   `^-?[0-9]+$` geprüft), das Evidenzverzeichnis des verworfnen Laufs wurde **vor** dem
   neuen Lauf gelöscht. Die hier gebundene Evidenz stammt aus **genau einem** vollständigen
   Lauf auf `162baa9`.
4. **Store-Probe-`run-as`-Zweig** lief erneut nicht (Paket war vor dem Lauf nicht
   installiert, `marker-sequence.txt:1`); die Probelogik selbst ist über den
   Drei-Fälle-Selbsttest belegt.
5. **Poppler-Aufrufe ohne `timeout`** (unverändert aus dem Vorgängerstand; keine
   Warteschleife, kein Wrong-PASS-Risiko, weiterhin offen).
6. Der Lauf dauert jetzt länger (~4 min statt ~2 min: zwei Exporte, zwei Pickup-Handshakes
   inkl. `pub get`/`analyze`-Gate); die Marker-Deadline (2400 s) und die Testende-Deadline
   (1800 s) sind nicht angefasst.

## 6. Geänderte Dateien

- `apps/feldexa_app/integration_test/android_export_test.dart` — zweiter Export-Zyklus nach
  Wiederöffnung, indexierte Pickup-Acks, `T334_FIELD_RECT`-Marker, Zyklus-Helfer
  (`_reopenDocument`, `_exportLiveRevision`, `_expectVerifiedArtifact`,
  `_storeArtifactForHostPickup`, `_previewThenAssertDeleted`, `_runExportCycle`).
- `tools/android/t334_drive_export.sh` — Pickup-Schleife über beide Artefakte mit
  indexierten Acks, per-Artefakt-Poppler, 1-mm-Messung (`pdftotext -bbox`), Zeilenheilung
  `PICKUP_OK=0`, Evidenz-Sammelliste, `run-status.txt` mit beiden Digests und dem
  Platzierungs-Verdikt.
- `specs/001-scanned-form-workflow/reports/2026-11-26-t344-export-proof-depth.md` (dieser
  Report) und `specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t344-export-proof-depth/`
  (29 Evidenzdateien inkl. beider PDFs).

## 7. Reproduktion

```
export PATH="$HOME/flutter/bin:$HOME/Android/Sdk/platform-tools:$PATH"
cd apps/feldexa_app && flutter analyze --no-pub          # No issues found!
cd ../.. && dart format --output=none --set-exit-if-changed packages apps  # 0 changed
T334_EVIDENCE_DIR="$PWD/specs/001-scanned-form-workflow/reports/artifacts/<neues-dir>" \
  bash tools/android/t334_drive_export.sh                # admitiert sich selbst, kein Wrapper
git status --porcelain                                   # nach dem Commit leer
```

Der Treiber ist fail-closed: fehlender Marker je Index, Digest-Abweichung zwischen Marker
und Pickup (je Artefakt), fehlende Poppler-Werkzeuge, Seitenzahl-/Seitenformat-Abweichung,
fehlender Umlauttreffer, `/AcroForm`-Treffer, nicht lesbares Rect-Marker, Privacy-Verstoß
oder ein nicht-leerer Arbeitsbaum beenden den Lauf mit einem Fehler, nie mit `PASS`. Die
Platzierungsmessung ist davon bewusst ausgenommen: sie ist eine **Prüfgröße**, kein
Freigabekriterium; ihr Verdikt steht im PASS-Record (`1 mm placement claim NOT_PROVEN`),
in `run-status.txt` und in `artifact-{1,2}-placement.txt`.
