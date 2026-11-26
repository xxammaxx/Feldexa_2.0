# Issue #342 — Nachzug: die zwei P2-Wrong-PASS-Fenster geschlossen (Beleg)

**Datum**: 2026-11-26 · **Branch**: `xxammaxx/t342-driver-hardening` · **Basis**: `0e1d7e2`
(Kandidat des ersten Treiberlaufs, Reviews PASS) · **Scope**: nur Werkzeug/Harness, kein
Produktcode, keine Änderung an `apps/feldexa_app/e2e/export_journey.yaml`, keine Schwellenwerte.
**Der alte Report `2026-11-26-t342-driver-hardening.md` bleibt unverändert** und bleibt an
Treiber `c065ad3e…` / Lauf-Commit `b4c86ae…` gebunden.

## Ergebnis in einem Satz

Die beiden von Review B gefundenen Restfenster (AcroForm-Byte-Suche, Ergebnisfixierung vor dem
Home-Pfad-Scan) und die sieben von Review A gelisteten Stellen derselben Klasse enden jetzt bei
einem Werkzeugfehler in `fail`; `flutter analyze`, `dart format` und der Store-Proben-Selbsttest
liegen als Evidenzdateien im Bundle, und der Beleg ist an den neuen Treiber-Hash gebunden.

| | |
| --- | --- |
| neuer Treiber-Hash (`tools/android/t334_drive_export.sh`) | `9d9ca77a2b0b580188bd29f9ff13e2e3c552bda3187e22e1dd5de8320ba2728b` (vorher `c065ad3e…`) |
| Lauf-Commit (`head`) | `b26c9bf79edd92e269f3a355193dd5cf91e02f23`, tree `9521dc0c9fdb6de7905ad0c822f5c8827a8f38aa` |
| Test-Hash (unverändert) | `fe9b21433e4df4d18a705cc3f766e01a8dbab3b63d2c5d0bd82466071a03fd99` |
| Evidenzverzeichnis | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t342b-driver-hardening/` (22 Dateien) |
| Gerät | `emulator-5554`, AVD `T025_Pixel7_API35_KVM_20261115`, API 35, `qemu=1`, boot completed, `non_emulator_transports=0` |
| Ergebnis | `result=PASS`, `flutter_test_exit=0`, `All tests passed!`, Artefakt `12029` Bytes `sha256 713776f48f20ee7ed1ba8c12b311d785988fc8ef7908f4c8ffccbca9ec18c974` |

Wörtliche Treiberausgabe des Laufs (`/tmp/t342b-driver-console2.log`, 12:08:12–12:12:12 UTC),
Host-Pfade wie beim Commit üblich auf `<ROOT>` normalisiert:

```
T334 DRIVER: PASS (flutter test exit 0; cleanup marker observed; artifact picked up; poppler proof; static gates clean; privacy checks PASS)
T334 DRIVER: evidence written to <ROOT>/specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t342b-driver-hardening
T334 DRIVER: PASS
```

Der Treiber selbst gibt das Evidenzverzeichnis **absolut** aus (`$ROOT/…`, `:155`); die
Normalisierung ist hier offengelegt, damit keine Zeile als „wörtlich“ ausgegeben wird, die es
nicht ist (Review B P3-5 am Vorgänger-Report).

## Die neun Nachzug-Punkte → Änderung

Zeilenangaben beziehen sich auf den neuen Treiber (885 Zeilen). `bash -n` ist Exit 0, das
Executable-Bit ist `755`, `grep -n "|| true"` liefert **keinen** Treffer.

**1. AcroForm-Byte-Suche prüft den Grep-Exit (Review B P2-2).** `:796–808`. Der Exit der
Pipeline (`pipefail`, `grep -a -o -F '/AcroForm' … | wc -l`) wird in `ACROFORM_GREP_EXIT`
(`:797`) getrennt gelesen und dreiwertig ausgewertet: `1` = keine Treffer (Ziel), `0` = Treffer
(→ `fail`, `:809–810`), `≥2` = Werkzeugfehler (→ `fail`, `:807–808`). Die Evidenzdatei
`artifact-bytes-acroform.txt` protokolliert alle drei Fälle unterscheidbar
(`acroform_grep_exit=… (0=hits, 1=no match, >=2=tool error)`, `:798–804`). Im Lauf:
`acroform_grep_exit=1`, `acroform_byte_occurrences=0`.

**2. Ergebnisfixierung nach dem Integritätscheck (Review B P3-1).** `:293–306` (neue Funktion
`scan_evidence_home_paths`, Rückgabe 0/1/2 statt `fail` im Inneren) und `:859–880`. Reihenfolge
jetzt: `collect_evidence` → Scan → `record "PASS …"` (`:866`) → `run-status.txt` (`:867–868`) →
`collect_evidence` → Scan. Ein fehlschlagender erster Scan beendet den Lauf, **bevor**
`result=PASS` existiert; scheitert der zweite Scan (er deckt die nachkopierten `run-status.txt`
und `marker-sequence.txt`), wird `result=FAIL` zurückgeschrieben, erneut gesammelt und erst dann
`fail` (`:872–876`). Ein Bundle mit `result=PASS` neben einem fehlgeschlagenen Check ist damit
nicht mehr konstruierbar.

**3. `flutter analyze` / `dart format` fail-closed belegt (Review A P2).** `:569–583`. Beide
Kommandos laufen im Gate-Abschnitt vor dem Test, jeweils mit `timeout` (900 s / 300 s),
`cd "$APP" || exit 1`, Exit ≠ 0 ⇒ `fail` (`:576–577`, `:581–582`); die wörtliche Ausgabe steht in
`gate-analyze.txt` („No issues found! (ran in 59.2s)“, Exit 0) und `gate-format.txt`
(„Formatted 120 files (0 changed) in 1.17 seconds.“, Exit 0). Beide Dateien sind Teil der
Sammelliste (`:273–274`) und im Bundle vorhanden. Damit ist die Report-Behauptung des
Vorgänger-Reports belegt. `DART` wird aus `$FLUTTER` abgeleitet (`:64`) und auf Existenz geprüft
(`:317–319`).

**4. Store-Probe belegt (Review A P2).** `:399–467`. Die Probelogik ist jetzt ein
parameterisierter Geräte-Shell-Body (`STORE_PROBE_BODY`, `:402`), den der Lauf mit
`run-as … sh files/feldexa` auf dem echten Store-Root (`STORE_ROOT_ON_DEVICE`, `:401`, = als
`MainActivity.STORE_ROOT_DIR`) und der Selbsttest (`:436–467`) mit derselben Logik auf einem
Scratch-Baum unter `$STAGING/store-probe-selftest` ausführt. `store-probe.txt` enthält Body,
Root, erwartete Exits und die drei Fälle: leer → Exit 0 `STORE_EMPTY_OK`, ein Aggregat →
Exit 1 `leftover entries in …/leftover/docs`, fehlende Wurzel → Exit 0 `STORE_EMPTY_OK`
(alle drei im Lauf beobachtet). Der Scratch-Baum wird im Cleanup-Trap mit `$STAGING` entfernt
(`:198`, `rm -rf "$STAGING"`).

**5. Privacy-Quell-Grep ohne `cd`-Konflation (Review A P3).** `:491–495`. Der Test wird absolut
adressiert (`"$APP/$TEST_FILE"`), es gibt keinen `cd`-Subshell-Aufruf mehr; Exit 1 = kein Treffer
(→ PASS), Exit 2 = Werkzeugfehler (→ `fail`, `:506–512`). `collect_evidence` normalisiert den
absoluten Pfad beim Kopieren (`:277–279`). Im Lauf: `PASS: no network API reference in
integration_test/android_export_test.dart`.

**6. `pm list packages | grep -qx` dreiwertig (Review A P3, zusätzlich Review B P2-1).**
Prä-Lauf: `:406–413` — `adb_shell pm list packages` mit `|| fail` (`:406–407`), dann
`printf … | grep -qx` mit `INSTALLED_GREP_EXIT` (`:408–409`) und `[[ … -le 1 ]] || fail`
(`:411–412`). Post-Pickup: `:723–736` — `am force-stop … || fail` (`:723–724`), die Abfrage mit
`|| fail` (`:729–730`), der Grep dreiwertig (`:731–734`) und die Verzweigung auf den Exit
(`:735`). Ein adb- oder Grep-Fehler kann damit weder vor noch nach dem Lauf als „nicht
installiert“ gelesen werden. Im Lauf: Prä-Lauf „package not installed, no stored state exists“
(echter Zustand, `marker-sequence.txt:1`), Post-Pickup „app is no longer installed after the
test“ (`marker-sequence.txt:7`) — beide Zweige sind jetzt an einen geprüften Exit gebunden.

**7. `ls -A` der Store-Probe prüft den Exit (Review A P3).** `:402`: `entries="$(ls -A "$d")"`
mit `|| { echo "PROBE_TOOL_ERROR ls -A $d"; exit 3; }`; Exit 3 wird im Lauf als
`ls_tool_error=3` dokumentiert (`:447`) und ist von „leer“ (Exit 0) und „Leftover“ (Exit 1)
unterscheidbar.

**8. Ungeprüfte Schreib-/Rechte-/`rm`-Operationen (Review B P3-3).** `:170–171`
(`: >"$SEQUENCE"`, `: >"$ADB_STDERR_LOG"` je `|| fail`), `:427–430` (`chmod 755` /
`chmod 644` je `|| fail`), `:471–472` und `:646–647` (`rm -f` des Alt-Acks je `|| fail`),
`:437–443` (Scratch-Baum `rm -rf` / `mkdir -p` / `touch` je `|| fail`). Der `force-stop` im
Cleanup-Trap bleibt absichtlich ungeprüft: der Trap läuft unter `set +e` (`:193`).

**9. Timeouts/Liveness (Review B P3-4).** `adb_shell` ist über `ADB_SHELL_TIMEOUT` (Default
120 s) gebunden (`:176–180`); die direkten adb-Aufrufe haben `timeout 60` (`adb devices`,
`:332–333`) und `timeout 300` (`push`, `:425`); `flutter pub get` `timeout 900` (`:565`);
`analyze`/`format` `timeout 900`/`300` (`:575`, `:580`). Die Wake/Keyguard-Schleife hat eine
harte Deadline von 120 s und je Aufruf nur 20 s (`:525–551`; Deadline `:526`, Aufruflimit `:529`), so dass ein toter Transport die
Iteration nicht mehr auf 4×120 s streckt; die Marker- und Testende-Schleifen behalten ihre
Deadlines (2400 s / 1800 s, `:604–619`, `:664–671`).

## Belegkette des neuen Laufs

- Marker: 18 Zeilen in `markers-integration.txt`, identisch mit dem Integrationslog
  (`integration-android-t334.log`): `T334_ARTIFACT_STORED:…BYTES=12029:SHA256=713776f4…` →
  `T334_WAITING_FOR_HOST_PICKUP` → `T334_HOST_PICKUP_ACKED` → … → `T334_CLEANUP_DONE`,
  danach `00:36 +1: All tests passed!`.
- Pickup: `artifact-pickup.txt` `sha256=713776f4…`, `bytes=12029`, `sha256_matches_marker=1` =
  `run-status.txt` = `export-artifact.pdf` (nachgerechnet: `sha256sum` = `713776f4…`).
- Poppler: `poppler-pdfinfo.txt` Quelle 2 Seiten A4 5956 B / Artefakt 2 Seiten A4 12029 B;
  `poppler-pdftotext.txt`: `entered_value_occurrences=1`, `12:Müller`,
  `umlaut_replaced_by_question_mark=0`.
- Fixture: `fixture-sha256.txt` Gerät und Host `22c939cc…` / 5956 B.
- APK: `apk-sha256.txt` `app-debug.apk` `25b02c7c…` / 173 865 306 B (nicht leer, `nullglob`-Pfad
  `:815–819`).
- Git-Bindung: `git-identity.txt` `head=b26c9bf79edd…`, `tree=9521dc0c…`, `status_porcelain:`
  leer, `driver_sha256=9d9ca77a…`, `test_sha256=fe9b2143…` — Treiber- und Test-Hash sind auf dem
  Arbeitsbaum nachgerechnet.
- Permit: `compute-lock.txt` `mode=shared-heavy-work-permits`, `orca_command_used=0`,
  `detached_jobs=0`; Konsole belegt genau eine Admission
  (`{"compute_slot": "ACQUIRED", "resources": [heavy, emulator, io]}`) und einen
  `SETTLED`-Abschluss mit `exit_code: 0`. Kein äußerer Wrapper, kein zweiter `--wait`.
- Privacy: `privacy-log-check.txt` `PASS: no document content, field label, display name, or
  fixture path in the integration log`.

## Grenzen / nicht belegt

- **Der Clear-Zweig des Prä-Lauf-Probe wurde erneut nicht durchlaufen**: das Paket war vor dem
  Lauf nicht installiert (`marker-sequence.txt:1`). Die Probelogik selbst ist jetzt über den
  Drei-Fälle-Selbsttest belegt (`store-probe.txt`), der **run-as-Pfad auf `files/feldexa`** ist
  in diesem Lauf nicht ausgeführt.
- **`STORE_PROBE_BODY` ist ein Geräte-Shell-String**; toybox/`mksh` unterstützt die verwendeten
  Konstrukte (im Selbsttest dreifach ausgeführt), ein Zweig „`ls` schlägt fehl“ (Exit 3) ist
  deklariert, nicht provoziert.
- **Poppler-Aufrufe (`pdfinfo`, `pdftotext`) haben weiterhin kein `timeout`** (nicht Teil der
  neun Punkte, keine Warteschleife, kein Wrong-PASS-Risiko) — offen für den laufenden Betrieb.
- Der Home-Pfad-Scan läuft zweimal; die zweite Runde deckt nur die nachkopierten Dateien
  `run-status.txt` und `marker-sequence.txt` (Treiber-eigene, pfadfreie Inhalte).
- Eine `flutter analyze`-Kaltmessung dauerte 59.2 s (Limit 900 s) — kein Risiko, aber das
  Gate verlangsamt den Lauf um ~1 Minute.

## Verifikationskommandos

```
bash -n tools/android/t334_drive_export.sh            # Exit 0
test -x tools/android/t334_drive_export.sh            # 755
grep -n '|| true' tools/android/t334_drive_export.sh  # keine Treffer
sha256sum tools/android/t334_drive_export.sh          # 9d9ca77a…
sha256sum apps/feldexa_app/integration_test/android_export_test.dart  # fe9b2143…
git status --porcelain specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t342-driver-hardening \
  specs/001-scanned-form-workflow/reports/artifacts/2026-11-26-t334-export   # leer: alte Belege unberührt
```

## Bekannt-latent: eine Zeilentrennung im Treiber (Delta-Review A2, P2)

Review A2 hat eine **durch diesen Nachzug eingeführte** Zeilentrennung gefunden, die `bash -n`
nicht fangen kann:

```bash
# tools/android/t334_drive_export.sh:646–647 (Stand 9d9ca77a…)
adb_shell rm -f "$STAGING/ack-artifact-picked-up" >/dev/null ||
  fail "cannot remove a stale pickup acknowledgement before the pickup retry"PICKUP_OK=0
```

Im Elternstand (`0e1d7e2`, `:547–548`) waren das zwei Zeilen. Bash verkettet Meldung und
Zuweisung zu einem Wort, die Datei bleibt syntaktisch gültig, `PICKUP_OK` wird nicht mehr
initialisiert. **Beide** denkbaren Ausgänge sind fail-closed (`set -u`-Abbruch oder
`[[ "" -eq 1 ]]` → `fail`), und der belegte Lauf erreicht die Stelle nicht (Pickup gelang im
ersten Versuch, `PICKUP_OK=1` wird vor der Prüfung gesetzt).

Bewusste Entscheidung: **nicht** in einem eigenen Commit geheilt, weil jede Treiberänderung den
belegten Lauf von `driver_sha256=9d9ca77a…` entbindet und einen weiteren Emulatorlauf erzwingen
würde — für einen Zeilenumbruch, der keinen falschen `PASS` erzeugen kann. Die Heilung (Zeile
teilen) erfolgt mit dem **nächsten ohnehin fälligen Treiberlauf** im Rahmen von Issue #344.
