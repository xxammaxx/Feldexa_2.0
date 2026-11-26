# Issue #342 — `t334_drive_export.sh` fail-closed nachgeschärft (Beleg)

**Datum**: 2026-11-26 · **Branch**: `xxammaxx/t342-driver-hardening` · **Basis**: `0ba4f00`
(Merge PR #343) · **Scope**: nur Werkzeug/Harness, kein Produktcode, keine Änderung an
`apps/feldexa_app/e2e/export_journey.yaml`, keine Schwellenwerte im Produkt.

## Ergebnis in einem Satz

Alle sechs Restbefunde aus Issue #342 enden jetzt bei einem Werkzeug- oder Zustandsfehler in
`fail` statt in `PASS`; der unveränderte Integrationstest
`apps/feldexa_app/integration_test/android_export_test.dart`
(SHA-256 `fe9b21433e4df4d18a705cc3f766e01a8dbab3b63d2c5d0bd82466071a03fd99`) ist mit dem
gehärteten Treiber auf `emulator-5554` grün, und der Beleg ist an den neuen Treiber-Hash
gebunden.

| | |
| --- | --- |
| neuer Treiber-Hash (`tools/android/t334_drive_export.sh`) | `c065ad3e9d7742c8841013237bee5475d692bcd8daae2e792331470c63ac7b23` (vorher `79ac6e84…`) |
| Lauf-Commit (`head`) | `b4c86ae1640c24fbd63e42314ce575f8a4a4d394`, tree `3a0e3be6c8471696a32929005f0245236fa3ce7a` |
| Test-Hash (unverändert) | `fe9b21433e4df4d18a705cc3f766e01a8dbab3b63d2c5d0bd82466071a03fd99` |
| Evidenzverzeichnis | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t342-driver-hardening/` |
| Gerät | `emulator-5554`, AVD `T025_Pixel7_API35_KVM_20261115`, API 35, `qemu=1`, boot completed |
| Ergebnis | `result=PASS`, `flutter_test_exit=0`, `All tests passed!`, Artefakt `12029` Bytes `sha256 6d0619f905e89cf60e32124e1c1d671f69d41a580639ae1e119728add6354fd0` |

Wörtliche Treiber-Ausgabe des Laufs:

```
T334 DRIVER: PASS (flutter test exit 0; cleanup marker observed; artifact picked up; poppler proof; privacy checks PASS)
T334 DRIVER: evidence written to specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t342-driver-hardening
T334 DRIVER: PASS
```

## Der #334-Beleg bleibt unverändert gebunden

`specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t334-export/` und
`specs/001-scanned-form-workflow/reports/2026-11-26-t334-android-export-verification.md` sind in
diesem Slice **nicht** angefasst (kein Diff-Eintrag, `git status` zeigt sie nicht). Sie bleiben
an Treiber-SHA-256 `79ac6e84c6519c3758c571e4812db309e283a787692dd71ec7cae37359210e03`
gebunden; der Treiber-Default für das Evidenzverzeichnis zeigt jetzt auf das neue Verzeichnis
(`tools/android/t334_drive_export.sh:152`), damit ein Lauf den alten Beleg nicht überschreiben
kann.

## Die sechs Befunde → Änderung

Alle Zeilenangaben beziehen sich auf den neuen Treiber
`tools/android/t334_drive_export.sh` @ `c065ad3e…`.

### 1. P2 (Review B): Prä-Lauf-`pm clear` prüfte den Rückgabewert nicht

`:361–386`. Der Clear läuft jetzt nur, wenn das Paket installiert ist, und sein Rückgabewert
wird geprüft (`:376–377`, `|| fail`). Zusätzlich wird der Store-Zustand **nach** dem Clear auf
dem Gerät bewiesen (`:369`, `:378–380`): ein `run-as`-Probe liest die Aggregat-Container des
App-Stores (`MainActivity.STORE_ROOT_DIR` = `files/feldexa`, also `docs` und `templates`) und
antwortet nur dann mit `STORE_EMPTY_OK`, wenn dort kein Eintrag liegt; fehlt die Wurzel, ist sie
weggewischt (leer), ein gelisteter Eintrag ist `fail`. Das ist keine Teständerung: derselbe
unveränderte Integrationstest startet damit nachweislich ohne Altzustand. Ist das Paket noch
nicht installiert (erster Lauf; `flutter test` installiert selbst), gibt es keinen Altzustand —
das wird als Zustand protokolliert (`:382–383`), nicht stillschweigend angenommen.

Belegt durch `markers-integration.txt` / `marker-sequence.txt`: `pre-run: package not installed,
no stored state exists` (in diesem Lauf war das Paket aus dem vorherigen #334-Lauf deinstalliert).
Der Zweig "installiert → Clear + leerer Store" ist in diesem Lauf **nicht** durchlaufen worden;
seine Probelogik ist separat auf dem Gerät gegen einen Scratch-Baum geprüft (leer → `STORE_EMPTY_OK`,
ein Aggregat → `leftover entries in …` mit Exit 1, fehlende Wurzel → `STORE_EMPTY_OK`).

### 2. P3 (Review B): `find … || true` in `prepare_evidence_dir`

`:228–233`. `find` läuft ohne `2>/dev/null`-und-`|| true`; ein Fehler ist jetzt
`fail "cannot scan the existing evidence directory …"` (`:231–232`) und kann den Backup-Schutz
nicht mehr als "leeres Verzeichnis" umgehen.

### 3. P3 (Review B): feste `sleep 2`-Wartezeit nach Wake/Keyguard

`:440–471`. Die Wartezeit ist durch einen Zustands-Check mit Deadline (60 s, Poll 1 s) ersetzt:
`mWakefulness=Awake` aus `dumpsys power` plus `mAwake=true`, `mScreenOnFully=true` und
`isKeyguardShowing=false` aus `dumpsys window` (`:455–462`). Ein fehlendes Zustandsfeld, ein
leerer/fehlerhafter Dump oder ein Ablauf der Deadline ist `fail` (`:451–454`, `:469–470`) und
protokolliert die tatsächlich beobachteten Felder (`:466`).

### 4. P3 (Review B): `T334_SERIAL`/`T334_AVD`/`T334_API` erlaubten ein anderes Gerät als die Arbeitsbereichsvorgabe

`:53–61` und `:109–126`. Die Sollwerte sind auf die AGENTS.md-Vorgabe fixiert (`emulator-5554`,
`T025_Pixel7_API35_KVM_20261115`, API 35). Ein Override wirkt nur noch mit deutlicher
`WARNING`-Zeile vor der Permit-Admission (`:113–126`), und ein Serial, der kein
Emulator-Transport ist, wird hart abgelehnt (`:114–115`): das physische S23
(`adb-RFCW…`) kann nicht adressiert werden. Der bestehende Serial-Guard
(`^emulator-[0-9]+$`) sowie die AVD/API/`qemu`/Boot-Bindung bleiben unverändert bestehen.

### 5. P3 (Review B): `adb_shell` verschluckte stderr

`:168–176`. `adb_shell` schreibt stderr nach `$RUN_DIR/adb-stderr.log` statt nach `/dev/null`
(`:174`) und gibt den Exit-Code des adb-Aufrufs explizit über `PIPESTATUS[0]` zurück (`:175`).
`adb-stderr.log` ist Teil des Evidenzbundles (`:251`) und wird beim Sammeln wie alle
Evidenzdateien pfad-normalisiert. Der Run-as-Pickup (`:551`) schreibt ebenfalls dorthin.

### 6. P3-2 (Review A): APK-Schleife und Privacy-Greps behandelten Fehler wie "kein Treffer"

- APK-Schleife (`:697–711`): `nullglob`-Array, `fail` bei null Treffern (`:703–704`); es kann
  keine leere `apk-sha256.txt` mehr entstehen.
- Privacy-Quell-Grep (`:413–431`): Exit 1 (kein Treffer) → `PASS`, Exit 2 (Werkzeugfehler) →
  `FAIL`-Zeile plus `fail` (`:428`).
- Privacy-Log-Grep (`:725–742`): gleiche Unterscheidung; Exit 2 setzt `PRIVACY_PASS=0` und
  schreibt `FAIL: the privacy log grep failed with exit …` (`:738–740`).
- Gleiche Fehlerklasse, gleiche Behandlungsart (im Ergebnis-Pfad): Wert-Grep im PDF-Text
  (`:663–671`, ersetzt `grep -c … || true`), Umlaut-Grep (`:672–677`, ersetzt das
  fail-offene `if grep -q …`), Marker-Extraktion (`:578–584`, ersetzt `|| true`) und der
  `/home/`-Scan des Evidenzbundles (`:749–758`, ersetzt `if grep -rl …`).

## Fail-closed-Invarianten im Ergebnis-Pfad

- `bash -n tools/android/t334_drive_export.sh` → grün; Datei bleibt `-rwxr-xr-x`.
- Keine `|| true`-Reste mehr in der Datei (`grep -n '|| true'` → leer).
- `set +e` nur im Cleanup-Trap (`:188`) und dort erst nach der Ergebnisfixierung; der Trap darf
  weiterhin `adb_shell`/`kill` best-effort ausführen.
- `sleep 2` nur noch als Retry-Backoff (Pickup-Versuche, Testende-Poll), nicht mehr als
  Zustandsersatz.

## Verifikation

| Prüfung | Ergebnis |
| --- | --- |
| `bash -n tools/android/t334_drive_export.sh` | grün |
| Treiber-Lauf (`bash tools/android/t334_drive_export.sh`, Selbstadmission `compute_slot.py --resource build --resource emulator`, kein äußerer Wrapper) | `PASS`, Exit 0 |
| `run-status.txt` | `result=PASS`, `flutter_test_exit=0`, `artifact_bytes=12029` |
| `integration-android-t334.log` | `00:37 +1: All tests passed!` |
| `pdfinfo` Artefakt vs. Fixture | 2 Seiten, `595.28 x 841.89 pts (A4)` = Quellgröße |
| `pdftotext -enc UTF-8` | `entered_value_occurrences=1` (`12:Müller`), `umlaut_replaced_by_question_mark=0` |
| `/AcroForm`-Bytesuche | 0 Treffer im Artefakt |
| `privacy-source-check.txt` | `PASS: no network API reference in integration_test/android_export_test.dart` |
| `privacy-log-check.txt` | `PASS: no document content, field label, display name, or fixture path in the integration log` |
| `device-binding.txt` | `addressed_serial=emulator-5554`, `non_emulator_transports=0` |
| Artefakt-Pickup | Marker-Digest `6d0619f9…54fd0`, 12029 Bytes, `sha256_matches_marker=1` |
| `flutter analyze --no-pub` (App) | `No issues found!` |
| `dart format --set-exit-if-changed` (App) | `120 files (0 changed)` |

Zusätzlich zur Laufzeit geprüft (der gehärtete Treiber selbst verlangt es jetzt): der Pre-Run-Clear,
der Store-Leerbeweis, der Awake/Unlocked-Zustand, die Werkzeug-Existenz und der
`/home/`-Scan des Evidenzbundles — jeder dieser Punkte war im Lauf Teil der PASS-Kette, nicht
eine Annahme danach.

## Grenzen dieses Belegs

- Aussagekräftig für `emulator-5554` (API 35, KVM); das physische S23 ist per Treiber-Guard
  ausgeschlossen und wurde nicht angefasst.
- Der Zweig "Paket war vor dem Lauf installiert" (Clear + Store-Leerbeweis) ist in diesem Lauf
  nicht durchlaufen worden; nur die Probelogik wurde separat auf dem Gerät geprüft.
- Die app-weite `flutter test`-Suite war nicht Teil des Slices.
- Ein erster Laufversuch (vor diesem Beleg-Commit) endete in `fail` beim neuen
  Wake/Keyguard-Zustands-Check, ohne dass der Test gestartet wurde; die Diagnosezeile
  (`:466`) wurde daraufhin ergänzt, danach lief der Check im nächsten Lauf im ersten Versuch
  grün. Ein Treiber-/Testfehler war daran nicht beteiligt.
