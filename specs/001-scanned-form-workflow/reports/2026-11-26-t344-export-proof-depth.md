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

> **Durch §8 überholt (Issue #344 Teil A2).** Dieser Abschnitt bleibt als Historie
> stehen: er hält fest, was die im Brief vorgegebene Mittelpunkts-Metrik gemessen
> hat und warum sie das Ergebnis nicht tragen kann. Das gültige Verdikt steht in §8.

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
| 1-mm-Platzierung am **Rect-Mittelpunkt** | **NICHT belegt** (durch §8 überholte Metrik) | §2: `dx=-132.140 pt`, `dy=-3.050 pt` > `2.835 pt`; Ursache: linksbündiges Layout nach §3.1 |
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

## 8. Korrektur der Platzierungsmetrik (A2) — 1-mm-Platzierung **belegt**

Nachtrag zu Issue #344 Teil A2. Kein neuer Emulatorlauf, kein neues Artefakt: gerechnet
wird auf den bereits committeten PDFs aus `162baa9` (Digests unverändert
`8da0ce1f…` / `dcf302e2…`, siehe `export-artifact-{1,2}.pdf`). Der Lauf `162baa9`, der
Treiber-Hash und alle Evidenzdateien aus §1–§7 bleiben unangetastet; §2 steht als
Historie (als überholt markiert).

### 8.1 Fehler der alten Metrik

Die alte Messung verglich den **Mittelpunkt der Wert-Box** mit dem **Mittelpunkt des
Feldes**:

```
rect                     = x 190.125, y 147.625, w 299.875, h 18.000
value bbox               = x 191.625 … 224.219   (Breite 32.594)
rect  Mittelpunkt x      = 190.125 + 299.875 / 2 = 340.0625
value Mittelpunkt x      = 191.625 +  32.594 / 2 = 207.922
Differenz                                        = −132.1405   (protokolliert: −132.140)
halber Feldüberhang      = (299.875 − 32.594) / 2 =  133.640
```

`−132.140` ist damit fast vollständig der **halbe Feldüberhang** (133.640 pt) abzüglich
des 1,5-pt-Paddings: die Zahl misst Feldbreite und Werte-Länge, nicht die Position des
Werts. Vertikal gilt dasselbe — der Rect-Mittelpunkt trägt keine Information darüber,
wohin die Baseline gehört; ein Mittelpunkt-`dy` misst Ascent/Descent-Geometrie. Der
Export zeichnet aber laut `contracts/export-plan.md` §3.1 **linksbündig und oben
ausgerichtet**; eine Mittelpunkts-Aussage ist für dieses Layout strukturell
unerfüllbar. Die `NICHT belegt`-Aussage aus §2 war damit ein Defekt der Prüfmethode,
kein Produktbefund.

### 8.2 Neue, aus dem Code abgeleitete Definition

Werkzeug: `tools/pdf_verify/placement.py` (neu; Verzeichnis war bisher nur `.gitkeep`,
in Issue #334 Kriterium 5 als fehlend benannt).
`sha256 1e1a6e6f0d2462d759160a3b1e6e8027d1a2001689e4570844900af58cc53259`.

Gemessene Größe: die Glyph-Box des exportierten Werts, wie Poppler sie mit
`pdftotext -bbox` meldet (Display-Space: Ursprung linke obere Seitenecke, x nach rechts,
y nach unten, PDF-Point) — dieselbe Konvention wie `core.ConfirmedField.rect`.

Sollgröße: der Ursprung, an den der Layout-Code den Wert zeichnet. Die Zahlen werden
zur Laufzeit aus ihren normativen Quellen gelesen, nicht eingetippt:

| Größe | Quelle | Wert |
| --- | --- | --- |
| `exportFieldPaddingPt` | `packages/feldexa_export/lib/src/layout.dart` | 1.5 pt |
| `_baselineAscenderFactor` | dito | 0.8 |
| `_fontSizeHeightFactor`, Clamp 7.0 … 12.0 | dito | 0.6 |
| Padding, vertikale Ausrichtung „top“, horizontale „left“ | `contracts/export-plan.md` §3.1 | normativ |
| `ascender`, `descender`, `unitsPerEm` (Noto Sans) | `apps/feldexa_app/assets/fonts/metrics.json` | 1069, −293, 1000 |

```
fontSizePt = round(clamp(0.6 * rect.height, 7.0, 12.0), 1)
origin x   = rect.x + padding
baseline y = rect.y + padding + 0.8 * fontSizePt
```

Drei getrennte Punkte, jeder mit Zahl und eigenem `pass`/`fail`:

1. `horizontal_origin` — gemessene Box-Oberkante/`xMin` gegen `origin x` (Toleranz 2,835 pt).
2. `vertical_baseline` — gemessene Baseline gegen `baseline y`. Poppler meldet die
   Ascent/Descent-Box der Schrift, nicht die Baseline; deshalb wird die Baseline von
   **beiden** Box-Kanten genähert (`yMin + ascender` und `yMax + descender`) und
   **beide** Näherungen müssen halten. Die Streuung zwischen ihnen wird mitprotokolliert.
3. `containment` — die horizontale Lage der Box im Feld (linker Rand ≥ `rect.x`, rechter
   Rand ≤ `rect.x + w`). Vertikal wird dieselbe Box nur **berichtet**, nicht gewertet:
   die Box ist die Ascent/Descent-Box der Schrift, und §3.1 legt die Baseline fest, nicht
   die Font-Box; die Ascent (1,069 em) ist größer als der Abstand Rect-Oberkante →
   Baseline (1,5 pt + 0,8 em = 10,14 pt bei 10,8 pt Schrift), sodass die Ascent-Kante
   konstruktionsbedingt über die Rect-Oberkante ragt. Beide vertikalen Überstände und
   die Herleitung stehen als `informational.*`-Zeilen in der Evidenz.

1-mm-Verdikt = `PROVEN`, wenn Punkt 1 und 2 halten. Exit 0 = alle Punkte `pass`,
Exit 1 = ein Punkt `fail`, Exit 2 … 6 = **kein Verdikt** (Aufruffehler, Worttreffer
fehlt, Worttreffer mehrdeutig, unlesbare Eingabe, Poppler-Fehler). Fehlt der Worttreffer
oder ist die Achsenlage unklar (`axes_check`: Box außerhalb der Seite oder außerhalb
eines aus dem Rect abgeleiteten Fensters — fängt 180°-Dreher und y-up-Lesart), gibt es
kein „provisorisches“ Ergebnis, sondern Exit ≠ 0 mit Grund.

### 8.3 Zahlen beider Artefakte

Beide PDFs liefern identische Messwerte (Diff der Evidenzdateien bis auf den Dateinamen
leer). Wörtlich aus `artifact-1-placement-v2.txt` (Kommandozeile und volle Ausgabe in der
Datei; `artifact-2-placement-v2.txt` ist inhaltsgleich):

```
rect_pt=190.125,147.625,299.875,18.000
font_size_pt=10.800
glyph_box_pt=191.625000,146.219790,224.219400,160.929390
glyph_box_width_pt=32.594400
glyph_box_height_pt=14.709600
font_box_height_expected_pt=14.709600
target_origin_pt=191.625,157.765
baseline_from_ascent_pt=157.764990
baseline_from_descent_pt=157.764990
baseline_estimate_spread_pt=0.000000
tolerance_pt=2.835
axes_check=consistent
check.horizontal_origin.measured_pt=191.625000 target_pt=191.625000 deviation_pt=0.000000 tolerance_pt=2.835 result=pass
check.vertical_baseline.measured_pt=157.764990 target_pt=157.765000 deviation_pt=-0.000010 tolerance_pt=2.835 result=pass
check.containment.measured_pt=-1.500000 target_pt=0.000000 deviation_pt=-1.500000 tolerance_pt=0.000 result=pass
informational.font_box_overflow_top_pt=1.405210
informational.font_box_overflow_bottom_pt=-4.695610
placement_verdict=PROVEN
containment_verdict=PASS
exit_code=0
reason=origin deviation +0.000000 pt and baseline deviation -0.000010 pt are within 2.835 pt
```

Rechnung zu den Zahlen: `fontSizePt = round(0.6 · 18.000, 1) = 10.8`;
`origin x = 190.125 + 1.5 = 191.625` (gemessen `191.625`, Abweichung `0.000000`);
`baseline = 147.625 + 1.5 + 0.8 · 10.8 = 157.765`; gemessen
`146.219790 + 1.069 · 10.8 = 157.764990` bzw. `160.929390 − 0.293 · 10.8 = 157.764990`
(Abweichung `−0.000010`). Die gemessene Box-Höhe `14.709600` ist exakt
`(1069 + 293)/1000 · 10.8` — die Box ist die Ascent/Descent-Box der Schrift und die
Schriftmetriken sind die aus `metrics.json`. Keine Zahl ist geschätzt oder umgerechnet;
alle Werte stammen aus der Poppler-Ausgabe bzw. aus den gelesenen Konstanten.

### 8.4 1-mm-Verdikt

**Belegt.** Der gezeichnete Wert liegt `0.000000 pt` (horizontal) und `0.000010 pt`
(vertikal) von der Sollposition entfernt, die der Layout-Code berechnet; Toleranz
`2.835 pt` (1 mm) — beide Punkte halten um mehr als drei Größenordnungen. Die
Kontrollgröße `containment` ist mit `−1.500 pt` (links) und `−265.781 pt` (rechts)
innerhalb des Feldes.

Nicht Teil dieses Verdikts, sondern berichtet: die **Ascent/Descent-Box** der Schrift ragt
`1.405210 pt` über die Rect-Oberkante (und `−4.696 pt`, also innerhalb, unter die
Rect-Unterkante). Das folgt aus §3.1 selbst (`1.069 em − (1,5 pt + 0,8 em) > 0` für jede
erlaubte Schriftgröße) und ist Font-Geometrie, keine Fehlplatzierung; offener Punkt 2 in
§8.6.

### 8.5 Selbsttest des Werkzeugs (ohne Netz, ohne Emulator, ohne Poppler)

`python3 -m unittest discover -s tools/pdf_verify -p 'test_*.py'` (Exit 0), wörtlich
— nur die Laufzeitangabe variiert von Lauf zu Lauf:

```
............................
----------------------------------------------------------------------
Ran 28 tests in 0.063s

OK
```

Die Tests bauen die Poppler-Seite synthetisch aus denselben Layout-Zahlen und decken ab:
exakter Treffer, 1-mm-Grenzfall (2,835 pt hält, 2,836 pt reißt), vertikaler Verstoß,
Containment links/rechts, Ascent-Überstand als Zahl, fehlender Worttreffer (Exit 3),
mehrdeutiger Worttreffer (Exit 4), Mehr-Wort-Argument (Exit 2), unlesbarer Marker
(Exit 5), `--page`-Widerspruch (Exit 2), fehlendes `pdftotext` (Exit 6), fehlende
Layout-Konstante (Exit 5), y-gespiegelte Box (Achsen-Check), sowie die Arithmetik der
alten Mittelpunkts-Metrik (`−132.1405` gegen `133.6405`). `test_layout_constants_match_source`
liest die echte `layout.dart`, damit eine geänderte Konstante die Suite bricht statt den
Sollursprung still zu verschieben.

### 8.6 Geänderte Dateien und offene Punkte

Neu: `tools/pdf_verify/placement.py`, `tools/pdf_verify/test_placement.py`,
`artifacts/2026-11-26-t344-export-proof-depth/artifact-{1,2}-placement-v2.txt`.
Unverändert: `apps/**`, `packages/**`, `tools/android/t334_drive_export.sh`, beide PDFs und
alle Evidenzdateien aus §1–§7 (inklusive der alten `artifact-{1,2}-placement.txt`).
Dieser Report ist um §8 ergänzt und in §2/§5 als überholt markiert.

1. **Toleranz unverändert** bei `2.835 pt` Default; `--tolerance-pt` existiert nur, um
   strenger messen zu können. Es wurde keine Schwelle gelockert.
2. **Ascent-Überstand (neu, Owner).** Die Ascent/Descent-Box der Schrift ist höher als
   der Abstand von der Rect-Oberkante zur Baseline, den §3.1 vorschreibt; sie ragt bei
   diesem Feld 1,405 pt (~0,5 mm) über die Rect-Oberkante. Das ist kein
   Platzierungsfehler und verändert keine Ziffer dieser Messung, kann aber für Felder
   relevant sein, über denen Inhalt steht. Ob §3.1 (Padding/Baseline-Faktor) angepasst
   wird, ist eine Owner-Entscheidung und **nicht** Teil von A2.
3. **Werkzeug nur auf diesen Lauf angewandt** — es ist generisch (`--pdf`,
   `--value-word`, `--field-rect-marker`, `--layout`, `--font-metrics`, `--pdftotext`),
   aber weitere Artefakte wurden nicht gemessen.
4. **Kein Emulator-/Gradle-/`flutter test`-Lauf** in A2; der Beleg-Lauf `162baa9` bleibt
   byte-identisch gebunden (PDF-Digests in §8.3 geprüft).

### 8.7 Reproduktion

```
python3 -m unittest discover -s tools/pdf_verify -p 'test_*.py'
python3 tools/pdf_verify/placement.py \
  --pdf specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t344-export-proof-depth/export-artifact-1.pdf \
  --value-word Müller \
  --field-rect-marker T334_FIELD_RECT:PAGE=1:X_MPT=190125:Y_MPT=147625:W_MPT=299875:H_MPT=18000
# exit 0, placement_verdict=PROVEN, containment_verdict=PASS
```
