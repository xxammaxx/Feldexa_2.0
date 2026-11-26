# T334 / Issue #334 E3 — Android-Export mit gefülltem Umlautwert (Emulator-Beleg)

**Slice**: `xxammaxx/t334-export-e2e` · **Rolle**: build/E2E (einziger Writer im Worktree)
**Erstellt**: 2026-11-26 · **Gerät**: ausschließlich `emulator-5554`

## 1. Zweck

Issue #334, Abnahmekriterium 5 verlangt: „`integration_test/android_export_test.dart` grün auf
`emulator-5554`; exportiertes PDF mit externem Verifier geprüft". Der Maestro-Flow
(`apps/feldexa_app/e2e/export_journey.yaml`) deckt die UI-Reise ab, aber **keinen gefüllten Wert**
(`reports/2026-11-25-t105-export-artifact-verification.md` §7/§8: Füllen scheiterte an einem
unbefüllbaren Kandidaten-Rect; mit #340 behoben).

Dieser Slice schließt den **Wert-behafteten** Beleg programmatisch (zuverlässig auch für Umlaute)
und zieht das Artefakt für einen **externen** Poppler-Beleg auf den Host.

## 2. Commits und Identität

| Feld | Wert |
| --- | --- |
| Branch | `xxammaxx/t334-export-e2e` |
| Basis | `baec0be` (`Merge pull request #341 … t340-field-rect`), Tree `0d65f70` |
| Slice-Commits | `dbe852f` (Test + Treiber), `fcc7d53` (Pickup-Pfad aus dem Marker), `76bec66` (Ack-Handshake), **`d790171`** (Post-Pickup-Cleanup, Lauf-Commit) |
| HEAD des belegten Laufs | `d79017101b61adc35a41a99133eea2aa1b2689ea` |
| Tree | `4ebc2f1ce14381d0fcb320eddc65a7b612bae13b` |
| `git status --porcelain` | leer — der Treiber bricht bei nicht-leerem Arbeitsbaum **vor** dem Lauf ab (`t334_drive_export.sh:298–307`); die committete `git-identity.txt` wurde nach dem Lauf erfasst und zeigt denselben leeren Status |
| Test-Datei SHA-256 | `fe9b21433e4df4d18a705cc3f766e01a8dbab3b63d2c5d0bd82466071a03fd99` |
| Treiber SHA-256 | `79ac6e84c6519c3758c571e4812db309e283a787692dd71ec7cae37359210e03` |
| Flutter | 3.47.7, stable |
| APK (debug) | `apps/feldexa_app/build/app/outputs/flutter-apk/app-debug.apk`, sha256 `00b4fa6d64adfd2999c644a6c0c5c13e15d156e3f9929bfe88819f111204d0d3`, 173 863 216 B |

### Dateien dieses Slices (Diff gegen Basis `baec0be`)

**Neu**

- `apps/feldexa_app/integration_test/android_export_test.dart` (708 Zeilen)
- `tools/android/t334_drive_export.sh` (629 Zeilen, ausführbar)
- `specs/001-scanned-form-workflow/reports/2026-11-26-t334-android-export-verification.md`
- `specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t334-export/` (20 Evidenzdateien)

**Geändert:** keine.

**Nicht berührt:** kein Produktcode (`apps/feldexa_app/lib`, `apps/feldexa_app/android`, `packages/*`),
`apps/feldexa_app/e2e/export_journey.yaml` unverändert. `git diff --name-only baec0be..<Kandidat>`
nent nur Dateien unter `apps/feldexa_app/integration_test/`, `tools/android/` und `specs/`.

## 3. Gerät (nur Emulator)

```
serial=emulator-5554
emulator_serials=emulator-5554
all_attached_transports_count=1
emulator_transports=1
non_emulator_transports=0
addressed_serial=emulator-5554
non_emulator_transports_addressed=none
---
avd=T025_Pixel7_API35_KVM_20261115
android_release=15
sdk=35
abi=x86_64
qemu=1
boot_completed=1
fingerprint=google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys
```

Das physische S23 (`adb-RFCW…`) war zum Laufzeitpunkt **nicht** als Transport verbunden
(`all_attached_transports_count=1`) und wurde nicht adressiert. Kein `adb kill-server`,
kein Emulator-Neustart, keine Eingaben von einem Beobachtungspfad.

## 4. Permits (compute_slot)

Der gesamte Lauf (Emulator, Gradle, Flutter-Test) lief in **einem** Permit-Abschnitt mit `build`(+`io`)
und `emulator`; der Treiber admitiert sich selbst (siehe §5). Die beobachteten `ACQUIRED`/`SETTLED`-
Zeilen von `compute_slot.py` liegen **nicht** als Evidenzdatei im Repository (Review-A P2-1), sondern
nur als Konsolenausgabe des Laufs; verbindlich committet ist der selbst deklarierte Admission-Block des
Treibers. Dessen Felder `inside_permits`, `orca_command_used` und `detached_jobs` sind **literale
Deklarationen** des Treibers, keine Messungen — belastbar sind `admitted_at_utc` und die
Ressourcenliste.

Der Treiber deklariert in seinem eigenen Admission-Block dieselben Ressourcen
(`specs/…/artifacts/2026-11-26-t334-export/compute-lock.txt`):

```
mode=shared-heavy-work-permits
admission=python3 ~/.pi/agent/skills/pi-maintainer/scripts/compute_slot.py --wait --resource build --resource emulator -- <driver>
resources=build(+io),emulator
inside_permits=1 (T334_COMPUTE_LOCK_HELD=1)
orca_command_used=0
detached_jobs=0
admitted_at_utc=2026-11-26T11:18:43Z
```

## 5. Kommando

```
export PATH="$HOME/flutter/bin:$HOME/Android/Sdk/platform-tools:$PATH"
cd <repo-root>
bash tools/android/t334_drive_export.sh
```

Der Treiber admitiert sich **selbst** über `compute_slot.py` (`--resource build --resource emulator`).
Ein zusätzlicher äußerer Wrapper auf dieselben Locks ist deshalb ein Selbst-Deadlock und war in einer
früheren Fassung dieses Reports falsch dokumentiert (Review-A P1-1); nur wenn bewusst von außen
gesetzt, muss `T334_COMPUTE_LOCK_HELD=1` mitgegeben werden.

Treiber-Ablauf: Permit-Admission → Gerätebindung (Serial/AVD/API/`qemu`/Boot) →
Commit-before-run-Gate → Fixture-Staging mit Host- und Geräte-Digest → `pm clear` →
`flutter test --no-pub integration_test/android_export_test.dart -d emulator-5554` im
Hintergrund → warten auf `T334_ARTIFACT_STORED` → Artefakt per `run-as` holen (Digest gegen
Marker) → Ack-Datei für den Test → auf Testende warten → Poppler-Beleg auf dem Host →
Evidenz + Privacy-Checks → fail-closed.

Lauf: Start `2026-11-26T11:18:50Z` (evidenziert in `marker-sequence.txt`). Ein End-Zeitpunkt und eine
Gesamtdauer sind **nicht** in der Evidenz erfasst (Review-A P2-3); `integration-android-t334.log`
zeigt für `assembleDebug` dieses Laufs `52,4 s`, der Build war durch die Vorläufe warm.

**Warum der Ack-Handshake nötig ist**: `flutter test` deinstalliert die App beim Beenden. Ein
`run-as`-Pickup **nach** dem Testende liest nur noch `run-as: unknown package` (40 B, beobachtet im
Vorlauf). Der Test schreibt die Bytes deshalb in sein App-internes Temp-Verzeichnis
(`Directory.systemTemp` → `code_cache`), druckt Pfad/Digest als Marker und wartet auf die
Ack-Datei des Hosts (frischegeprüft, veraltete Acks werden auf beiden Seiten entfernt). Deshalb
konnte der Post-Pickup-`pm clear`-Schritt im Vorlauf fehlschlagen; `d790171` behandelt „App ist
nach dem Test nicht mehr installiert" als Soll-Zustand statt als Fehler.

## 6. Marker-Sequenz (wörtlich aus dem Integrationstest-Log)

```
T334_FIXTURE_READY:BYTES=5956:MATCH=1
T334_START_LIST_READY
T334_IMPORT_ARMED
T334_EDITOR_READY
T334_ANALYSIS_READY:PAGES=2:SUGGESTIONS=59
T334_NAMED_SUGGESTION_FOUND:PAGE=1
T334_MACHINE_FIELD_CONFIRMED:PAGE=1:W_MILLI=299875:H_MILLI=18000
T334_VALUE_SAVED:RUNES=6:OVERFLOW=0
T334_EXPORT_PLAN_READY
T334_EXPORT_VERIFIED:PAGES=2:BOUND=1:BYTES_GT_0=1:ALL_CHECKS_PASSED=1
T334_ARTIFACT_BYTES:PATH_BYTES=12029:SHA256_MATCH=1
T334_ARTIFACT_STORED:PATH=/data/user/0/de.feldexa.app/code_cache/e2e/export-artifact.pdf:BYTES=12029:SHA256=1e24ac010a8fcef6f18852b4188b2f49cc958d5a37fa45281f2551b4fd534140
T334_WAITING_FOR_HOST_PICKUP
T334_HOST_PICKUP_ACKED
T334_PREVIEW_OPEN
T334_PREVIEW_CLOSED
T334_ARTIFACT_DELETED_AFTER_PREVIEW_CLOSE:CODE=EXP-002
T334_CLEANUP_DONE
00:35 +1: (tearDownAll)
00:37 +1: All tests passed!
```

Jeder Marker **mit Tatsachenbehauptung** steht nach dem `expect`, das sie beweist. Drei reine
Phasenmarker haben kein vorangehendes `expect` (Review-A P3-1): `T334_START_LIST_READY` (folgt einem
fail-closed `_pumpUntil`), `T334_WAITING_FOR_HOST_PICKUP` (kündigt eine Wartezeit an) und
`T334_CLEANUP_DONE` (reine Phase). Marker tragen nur
Phasennamen, zählende Größen, den Pickup-Pfad und den Hex-Digest — keinen Feldnamen, keinen
eingegebenen Wert, keinen OCR-Text.

Was die Marker belegen:

- `NAMED_SUGGESTION_FOUND:PAGE=1` — genau der fixture-deklarierte Vorschlag
  „Familienname" (`assets/fixtures/catalog.json`, `p0-familienname`) wurde per **Label**
  ausgewählt; der Test schlägt fehl, wenn nicht genau ein solcher unaufgelöster Textvorschlag
  existiert. Keine Positionsauswahl, keine Koordinatenwahl.
- `MACHINE_FIELD_CONFIRMED:W_MILLI=299875:H_MILLI=18000` — bestätigtes Rect 299,875 × 18 pt
  (Fixture-Deklaration: 300 × 18 pt bei x = 190, y = 148).
- `VALUE_SAVED:RUNES=6:OVERFLOW=0` — „Müller" (6 Runen) über das produktive `FieldValueSheet`
  gespeichert; `FLD-001` wurde per `expect(findsNothing)` **ausgeschlossen** (kein Kaschieren:
  wäre die Warnung gekommen, wäre der Test rot geworden).
- `EXPORT_VERIFIED:PAGES=2:BOUND=1:…:ALL_CHECKS_PASSED=1` — `ExportArtifact.state == succeeded`,
  `byteSize > 0`, `sha256` gesetzt (64 Hex), `artifact.pageCount == 2`, und alle fünf
  `ArtifactVerification`-Flags `true` (`pageCountMatches`, `mediaBoxesMatch`,
  `fontGlyphsPresent`, `noInteractiveFields`, `overlayBoundsWithinPage`).
- `ARTIFACT_BYTES:…:SHA256_MATCH=1` — die über `export.readArtifact` gelesenen Bytes sind
  byte-identisch zum `sha256`/`byteSize` des Artefakt-Records und beginnen mit `%PDF-`; die
  Byte-Suche nach `/AcroForm` im Test liefert **-1** (nicht gefunden).
- `ARTIFACT_DELETED_AFTER_PREVIEW_CLOSE:CODE=EXP-002` — nach dem Schließen der produktiven
  `ExportPreviewScreen` liefert `export.readArtifact` für dieselbe `artifactId` `EXP-002`
  (kein lesbares Session-Artefakt mehr; Kontraktregel `ExportArtifactStore`).

## 7. Artefakt

| Feld | Wert |
| --- | --- |
| SHA-256 | `1e24ac010a8fcef6f18852b4188b2f49cc958d5a37fa45281f2551b4fd534140` |
| Größe | 12 029 B |
| Marker-Digest/-Größe vs. Host-Pickup | identisch (`sha256_matches_marker=1`, `size_matches_marker=1`) |
| Ablage | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t334-export/export-artifact.pdf` |
| Herkunft | `adb exec-out run-as de.feldexa.app cat code_cache/e2e/export-artifact.pdf` (Pfad aus dem Marker abgeleitet, kein geratener Verzeichnisname) |

Der Digest ist **laufabhängig** (der Renderer schreibt u. a. Zeitstempel/IDs); Vorläufe ergaben
`65e4c9ea…` und `53a1f936…` bei gleicher Größe 12 029 B. Belegt ist der Bezug
Marker ↔ Pickup ↔ Poppler-Ausgabe **innerhalb dieses Laufs**, nicht die Reproduzierbarkeit des
Digests über Läufe hinweg (siehe §10).

## 8. Externer Beleg auf dem Host (Poppler + Byte-Suche)

Quelle: `apps/feldexa_app/assets/fixtures/sf-001.pdf`
sha256 `22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038` (Host **und** Gerät
identisch, 5 956 B).

`pdfinfo` (wörtlich, `poppler-pdfinfo.txt`):

```
command=pdfinfo apps/feldexa_app/assets/fixtures/sf-001.pdf
Custom Metadata: no
Metadata Stream: no
Tagged:          no
UserProperties:  no
Suspects:        no
Form:            none
JavaScript:      no
Pages:           2
Encrypted:       no
Page size:       595.28 x 841.89 pts (A4)
Page rot:        0
File size:       5956 bytes
Optimized:       no
PDF version:     1.7
command=pdfinfo <artifact>
Creator:         Feldexa
Producer:        Feldexa
Custom Metadata: no
Metadata Stream: yes
Tagged:          no
UserProperties:  no
Suspects:        no
Form:            none
JavaScript:      no
Pages:           2
Encrypted:       no
Page size:       595.28 x 841.89 pts (A4)
Page rot:        0
File size:       12029 bytes
Optimized:       no
PDF version:     1.7
```

Damit: Seitenzahl Artefakt = 2 = Quelle; Seitengröße Artefakt = `595.28 x 841.89 pts (A4)` =
Quelle; `Form: none` (kein AcroForm-Formular); `Encrypted: no`.

`pdftotext` (wörtlich, `poppler-pdftotext.txt`):

```
command=pdftotext -enc UTF-8 <artifact> <text>
entered_value_occurrences=1
value = `Müller` (synthetic fixture content entered by the journey)
umlaut_replaced_by_question_mark=0
extracted_text_lines=92
matched_lines:
12:Müller
```

Der eingegebene Wert steht also **mit Umlaut** im extrahierten Text; die Ersatzschreibweise
`M?ller` kommt nicht vor (`grep -F "M?ller"` → kein Treffer, sonst wäre der Lauf rot geworden).

Byte-Suche (wörtlich, `artifact-bytes-acroform.txt`):

```
command=LC_ALL=C grep -a -o -F '/AcroForm' <artifact> | wc -l
acroform_byte_occurrences=0
note=byte-level search only; this is not a structural PDF analysis
```

## 9. Privacy- und Identitätschecks (fail-closed im Treiber)

```
PASS: no network API reference in integration_test/android_export_test.dart
PASS: no document content, field label, display name, or fixture path in the integration log
```

Zusätzlich prüft der Treiber nach dem Sammeln, dass **keine** Evidenz-Textdatei einen absoluten
Home-Pfad enthält (Host-Pfade werden beim Kopieren auf `apps/…` bzw. `~/…` umgeschrieben;
`path=/tmp/…` in `artifact-pickup.txt` ist ein Laufverzeichnis, kein Home-Pfad). Evidenz-Ordner:
`specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t334-export/` (18 Dateien inkl.
Artefakt-PDF, 12 029 B, synthetisch, keine personenbezogenen Daten).

## 10. Belegt / nicht belegt

| Aussage | Status | Beleg |
| --- | --- | --- |
| `android_export_test.dart` grün auf `emulator-5554` | **belegt** | `All tests passed!`, exit 0, vollständige `T334_*`-Sequenz |
| Import der committeten Fixture `sf-001.pdf`, Analyse beider Seiten | **belegt** | `ANALYSIS_READY:PAGES=2:SUGGESTIONS=59`, Fixture-Digest Host = Gerät |
| Bestätigung des **benannten** Feldes „Familienname" (kein Positions-Index) | **belegt** | `NAMED_SUGGESTION_FOUND:PAGE=1` + `expect(matches.length, 1)` |
| Wert mit Umlaut über das produktive `FieldValueSheet`, ohne `FLD-001` | **belegt** | `VALUE_SAVED:RUNES=6:OVERFLOW=0` |
| Export über den produktiven `ExportController` (`prepare` + `run`) mit Live-Revision | **belegt** | `EXPORT_PLAN_READY`, `EXPORT_VERIFIED … ALL_CHECKS_PASSED=1` |
| `ArtifactVerification` vollständig all-pass | **belegt** | `T334_EXPORT_VERIFIED` (fünf Flags einzeln asserted) |
| `pageCount == 2`, Bytes beginnen mit `%PDF-` | **belegt** | Testassertion + `pdfinfo` „Pages: 2" |
| Seitenzahl/Seitengröße des Artefakts = Quelle | **belegt (extern)** | `pdfinfo` Artefakt vs. Quelle, §8 |
| Eingegebener Umlautwert steht im PDF-Text | **belegt (extern)** | `pdftotext`, Treffer Zeile 12 „Müller", kein `M?ller` |
| Kein `/AcroForm` im Artefakt | **belegt, aber nur als Byte-Beleg** | Byte-Suche = 0 Treffer + `pdfinfo` „Form: none" |
| Artefakt nach Schließen der Vorschau nicht mehr lesbar | **belegt** | `EXP-002` per `export.readArtifact` |
| 1-mm-Platzierungstoleranz (`pdftotext -bbox`-Messung) | **NICHT belegt** | bewusst ausgeklammert (Slice-Grenze) |
| AcroForm-Fixture / Verhalten bei interaktiven Feldern | **NICHT belegt** | kein AcroForm-Fixture in diesem Slice |
| Zweites Artefakt nach erneutem Öffnen des Dokuments | **NICHT belegt** | nur ein Artefakt in diesem Lauf |
| Digest-Reproduzierbarkeit des PDFs über Läufe hinweg | **NICHT belegt** | drei Läufe ergaben drei Digests bei identischer Größe |
| Export über die UI-Aktion `editor-export-action` (Bottom-Sheet + Fortschritt) | **NICHT belegt in diesem Slice** | der Lauf nutzt `ExportController.prepare`/`run` direkt (vom Auftrag zugelassen); die Vorschau-Route ist die produktive `ExportPreviewScreen` |

## 11. Reproduktion

```
export PATH="$HOME/flutter/bin:$HOME/Android/Sdk/platform-tools:$PATH"
cd apps/feldexa_app && flutter analyze --no-pub          # No issues found!  — Beleg: gate-analyze.txt
cd ../.. && dart format --output=none --set-exit-if-changed packages apps  # 0 changed — gate-format.txt
bash tools/android/t334_drive_export.sh                  # admitiert sich selbst, kein äußerer Wrapper
git status --porcelain                                   # nach dem Commit leer
```

Der Treiber ist fail-closed: fehlender Marker, Digest-Abweichung zwischen Marker und Pickup,
fehlende Poppler-Werkzeuge, Seitenzahl-/Seitengrößen-Abweichung, fehlender Umlauttreffer,
`/AcroForm`-Treffer, Privacy-Verstoß oder ein nicht-leerer Arbeitsbaum beenden den Lauf mit
einem Fehler, nie mit `PASS`. Ohne gebooteten `emulator-5554` endet er mit exit 2
(`EMULATOR NOT_RUN`).

## 12. Offene Punkte

1. **1-mm-Platzierungstoleranz** ist ungemessen; sie braucht `pdftotext -bbox` gegen die
   Fixture-Ground-Truth und bleibt ein offener Punkt aus dem Brief (§Grenzen).
2. **AcroForm-Fixture** fehlt; `noInteractiveFields` ist für dieses Fixture nur über den
   Byte-Beleg und `pdfinfo` „Form: none" gestützt.
3. **Zweites Artefakt** nach erneutem Öffnen ist nicht Teil dieses Slice (der Maestro-Flow
   `e2e/export_journey.yaml` deckt diesen Teil ab und wurde hier **nicht** verändert).
4. **Digest-Stabilität**: das exportierte PDF ist nicht byte-reproduzierbar (Zeitstempel/IDs);
   Belege binden sich an den jeweiligen Lauf-Digest.
5. Die drei Vorläufe dieses Slices waren rot (Pickup-Pfad `code_cache` vs. `cache`; `run-as`
   nach App-Deinstallation; `pm clear` bei deinstallierter App). Alle drei waren
   Treiber-Defekte, sind in `fcc7d53`, `76bec66`, `d790171` behoben und mit dem hier
   dokumentierten Lauf belegt; der Test selbst war bereits im ersten Lauf grün.

## 13. Review-Nachführung (A/B) und Supervisor-Gates

Zwei unabhängige Reviews auf demselben Kandidaten `77ec66d` (`reports/t334/review-a.md`, Reviewer
`deepseek/deepseek-flash`; `reports/t334/review-b.md`, Reviewer `zai-coding-cn/glm-5.3-flash`): beide
**PASS**, keines der Findings war substanzielle Beweisnot — sie betrafen Doku-Genauigkeit und
Fail-closed-Härte des Treibers.

Supervisor-Gates des Parents auf dem Kandidaten (nachgeholt, weil Reviewer B ohne Shell lief):

| Gate | Ergebnis |
| --- | --- |
| `flutter analyze --no-pub` (App) | `No issues found!`, exit 0 — `gate-analyze.txt` |
| `dart format --output=none --set-exit-if-changed packages apps` | `0 changed`, exit 0 — `gate-format.txt` |
| `bash -n` + Ausführbarkeit des Treibers | Syntax OK, ausführbar |
| Hashes gegen Evidenz | Test `fe9b2143…`, Treiber `79ac6e84…`, Artefakt `1e24ac01…` — alle identisch |
| `git diff --stat d790171..77ec66d` | nur Report + Evidenzdateien (docs-only), kein Code |

**In diesem Commit behoben** (Doku/Evidenz): P1-1 (Reproduktionskommando deadlockte gegen den
eigenen Permit), P2-1 (Wrapper-Events nicht Evidenz — Formulierung präzisiert), P2-2 (Dateiliste
ergänzt), P2-3 (unbelegte Zeitangaben neutralisiert), P3-1 (Marker-Formulierung präzisiert),
P3-3 (Analyze-/Format-Belege ergänzt), P3-4 (Commit-before-run-Zuordnung präzisiert).

**Bewusst nicht in diesem Slice behoben**: die Fail-open-Reste des Treibers (Review-A P3-2,
Review-B Findings 1–5: ungeprüftes Prä-Lauf-`pm clear`, `find || true`, festes `sleep`, Env-Overrides,
verschlucktes `adb`-stderr, leere `apk-sha256.txt` bei fehlendem APK, Privacy-Greps mit
Fehler-als-kein-Treffer). Ein Treiber-Patch würde den belegten Lauf von seinem Treiber-Hash
`79ac6e84…` entkoppeln. Nachführung mit erneutem, hash-gebundenem Treiberlauf: **Issue #342**.
