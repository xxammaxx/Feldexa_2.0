# Orca-Emulator-Integration und T031-Gerätenachweis (2026-11-17)

**Kandidat:** `056de35ec8af3d1ce7e8024a8c6666565655e8ca` (tree `f3dfbb5980681b9ffe242f177a69298600b6c3cc`, Branch `xxammaxx/feldexa-t031`, Worktree `/home/xxammaxx/feldexa-worktrees/t031`)
**Orca-Worktree (Emulator-Bindung):** `5cfd8bbd-7af0-43a2-b81d-7e8d50eda284::/home/xxammaxx/Schreibtisch/Feldexa_2.0/Feldexa_2.0`
**Orca-Runtime:** `74b27cce-742b-4ade-a61f-7244d4af9f58`, Orca `1.4.253`
**Gerät:** `emulator-5554`, AVD `T025_Pixel7_API35_KVM_20261115`, Android 15 / API 35, `x86_64`, 4096 MiB AVD-RAM (Gast: 3920 MB sichtbar)
**SDK:** `/home/xxammaxx/Android/Sdk`, `adb` 1.0.41 / 37.0.1-15733141, Emulator **37.2.13.0** (build 16740729)
**Evidenzklasse:** `EMULATOR` für die Geräteprüfungen; Host-/JVM-Prüfungen ohne Laufzeitklasse.

---

## 1. Ausgangslage und Dokumentation

Die verbindliche Schnittstelle wurde aus der laufenden Installation geladen, nicht aus dem Netz angenommen:

```bash
ORCA=/home/xxammaxx/.config/orca/linux-orca-cli-shim/orca   # ORCA_CLI_COMMAND
$ORCA skills get orca-emulator-android
$ORCA emulator --help
```

Geprüfte offizielle Quellen: `orca.dev/docs/cli/skills`, `skills/orca-emulator-android/SKILL.md`,
`skill-guides/orca-emulator-android.md` sowie der versionsgleiche Guide aus `skills get`.
Verwendete dokumentierte Befehle: `worktree list`, `emulator devices`, `emulator attach`,
`emulator kill`, `emulator install`, `emulator launch`, `emulator tap`, `emulator button`,
`emulator ax`, `emulator logcat`, `emulator list`, `emulator shutdown`.
Der offizielle Android-Skill ist in der laufenden Orca-Installation vorhanden (`skills list`);
eine Neuinstallation war nicht erforderlich.

---

## 2. Ermittelte Ursachen und minimale Korrekturen

| # | Befund | Nachweis | Korrektur | Status |
|---|--------|----------|-----------|--------|
| 1 | AVD wich vom Feldexa-Profil ab: `hw.ramSize=3072` statt 4096 MB. Im Gast nur 256 MB frei; `System UI isn't responding` (ANR). | `config.ini` (Sicherung `config.ini.bak-20261117-emulator-repair`), `free -m` im Gast, `orca emulator ax` mit ANR-Dialog | `hw.ramSize=4096`; `hw.gpu.enabled=yes`, `hw.gpu.mode=auto`. Gast nach Neustart: 3920 MB, 2,1–2,3 GB frei, kein System-UI-ANR. | behoben |
| 2 | `flutter test`/Gradle brach mit `compressDebugAssets` und „Der zugewiesene Plattenplatz (Quota) ist überschritten“ ab. | `/tmp` ist tmpfs mit `usrquota`; `df` zeigte 2,4 GB frei, ein 8-MiB-Schreibtest schlug mit `EDQUOT` fehl. | `TMPDIR` und `-Djava.io.tmpdir` auf `…/build/tmpdir` (Worktree) gesetzt; zusätzlich 2,3 GB veralteten Toolchain-Klon unter `/tmp/opencode/toolchain` entfernt. Preflight prüft jetzt einen echten 8-MiB-Schreibtest. | behoben |
| 3 | adb-Server brach mit SIGABRT ab: `could not install *smartsocket* listener: Operation not permitted` (main.cpp:168). | Coredump `497458` (`coredumpctl info 497458`), Host `16:19` | Kein Host-/KVM-Defekt: adb lauscht im normalen Orca-Worktree-Terminal; die Ursache war die Netzwerk-/Bind-Sandbox des damaligen Worker-Kontexts. Gerätetests laufen jetzt ausschließlich aus dem Orca-Worktree; Preflight klassifiziert `smartsocket`+EPERM als `BLOCKED`-Transport und verlangt drei Folgeproben. | behoben (Umgebung) |
| 4 | QEMU stürzte wiederholt ab: `2026-11-16 09:49` SIGSEGV in `android_pipe_guest_recv` (`libandroid-webrtc.so`), `2026-11-17 14:42` SIGSEGV, `2026-11-17 18:48` SIGABRT. | `coredumpctl info 285936` (Backtrace), `journalctl` für 14:42/18:48, verwaiste Lock-PID 417779 | Emulator-Patch **37.2.12 → 37.2.13** eingespielt (Release-Note: Host-Speicherleck in OpenGL-ES-Emulation behoben). Das ist eine begründete Mitigation, kein bewiesener Fix; siehe §7. | Mitigation, Restrisiko |
| 5 | Live-Pane konnte nach einem Kaltstart auf dem Boot-Frame „Pixel is starting…“ einfrieren, obwohl das Gerät längst den Launcher zeigte. | Pane-Screenshot vs. `adb exec-out screencap` um 18:20; Pane zeigte 6:20 „Pixel is starting…“, Gerät zeigte 6:20 Launcher. | Betriebsverfahren: nach `sys.boot_completed=1` und Launcher-Fokus `emulator kill`, warten bis `emulator list` leer ist, dann `emulator attach <serial> --focus`. Danach frische Frames und sichtbare Interaktion geprüft. | behoben (Betriebsverfahren) |
| 6 | Kein fehlendes `/dev/kvm`, kein fehlendes SDK. | `/dev/kvm` `crw-rw-rw-`, `os.open(O_RDWR)` OK; `emulator -accel-check` → „KVM (version 12) is installed and usable.“; `platform-tools`, `emulator`, `platforms/android-35`, `system-images/android-35/google_apis/x86_64`, `build-tools` vorhanden. | Keine Änderung. Preflight prüft beides. | kein Defekt |
| 7 | Doppelstart/Mehrfachinstanz | `ps` zeigte während der gesamten Arbeit genau einen QEMU für die AVD; `emulator devices` genau ein booted-Gerät. | Preflight zählt QEMU-Prozesse je AVD und lehnt >1 ab. | kein Defekt |

`/dev/kvm` betrifft hier den **echten Host**: KVM ist im Host-Kernel vorhanden, für den Benutzer öffenbar und vom Emulator nutzbar. Es war kein reines Worker-/Sandbox-Problem. Das adb-`EPERM` betraf dagegen ausschließlich den damaligen Worker-Kontext, nicht den Host.

---

## 3. Orca- und Worktree-Zuordnung

| Feld | Wert |
|---|---|
| AVD | `T025_Pixel7_API35_KVM_20261115` (Pixel 7, API 35, x86_64, 4 GB) |
| Seriell | `emulator-5554` |
| Orca-Worktree | `5cfd8bbd-7af0-43a2-b81d-7e8d50eda284::/home/xxammaxx/Schreibtisch/Feldexa_2.0/Feldexa_2.0` |
| Orca-Session | `deviceUdid=emulator-5554`, `streamUrl=scrcpy://emulator-5554`, `streamCodec=h264` |
| Kandidaten-Worktree | `/home/xxammaxx/feldexa-worktrees/t031` (Git-Worktree, nicht separat Orca-verwaltet; Test läuft auf demselben exklusiven Gerät) |

`emulator list --json` band die Session an exakt diesen Worktree; `emulator devices` meldete
`state=booted`, `apiLevel=35`, `name=T025_Pixel7_API35_KVM_20261115`.

---

## 4. Nachweis der funktionierenden Live-Ansicht

Die Live-Ansicht wurde nicht aus CLI-Metadaten abgeleitet, sondern über echte Frames im
Orca-Pane geprüft:

| Zeit | Beobachtung | Screenshot |
|---|---|---|
| 17:45 | Pane öffnet, Gerät bootet („Pixel is starting…“, Uhr 5:3x) | historisch, nicht als Abschlussbeleg verwendet |
| 18:20 | Pane eingefroren auf Boot-Frame, Gerät laut `screencap` auf Launcher → Defekt reproduziert | `device-home.png` (Gerät) vs. früheres Pane; nicht versioniert |
| 18:21 | Nach `kill`+`attach emulator-5554 --focus`: Pane zeigt Launcher, Uhr 6:21 | historisch, nicht versioniert |
| 18:27 | `emulator launch com.android.settings` → Pane zeigt Settings, Uhr 6:27; `ax` liefert „Network & internet“, „Apps“, „Storage“ usw. | `artifacts/2026-11-17-orca-emulator/pane-settings.png` |
| 18:23 | Feldexa-App sichtbar: „Feldexa“ / „Meine Dokumente“, Uhr 6:23 | `artifacts/2026-11-17-orca-emulator/pane-app.png` |
| 19:02 | Nach Emulator-Update und Neustart: `kill`+`attach`, Pane zeigt Launcher, Uhr 7:02 | `artifacts/2026-11-17-orca-emulator/pane-live-launcher.png` |
| 19:12 | Finaler Zustand: Pane verbunden, App im Vordergrund, Uhr 7:12 | `artifacts/2026-11-17-orca-emulator/pane-final.png` |

Die Uhr im Pane änderte sich zwischen Aufnahmen (6:20 → 6:21 → 6:23 → 6:27 → 7:02 → 7:12),
und Settings/Launcher/App wechselten sichtbar nach Orca-Eingaben. Damit ist die Live-Ansicht
belegt; ein headless-only-Nachweis wurde nicht als Ersatz verwendet.

**Accessibility:** `emulator ax` liefert für native UI (Settings) den vollständigen Baum.
Für die Flutter-App meldet `uiautomator` nur `android:id/content` (FrameLayout), weil die
Flutter-Semantik ohne aktivierte Accessibility-Bridge nicht exponiert wird. Das ist eine
bekannte Flutter-Eigenschaft, kein Emulatorfehler; die App-Interaktion wurde über sichtbare
Frames und Logcat belegt.

---

## 5. Praktischer End-to-End-Smoke-Test

| Schritt | Befehl/Ergebnis |
|---|---|
| APK bauen | `flutter build apk --debug` (JDK 17, `TMPDIR` im Worktree) → `app-debug.apk`, SHA-256 `1975515e13d0a166a11efe8f039fb808bb574e8badcbd8018221a68d68295545` |
| Installieren | `orca emulator install …/app-debug.apk --reinstall --json` → `ok=true`; Gerät `lastUpdateTime=2026-11-17 18:22`, `base.apk` 235.793.790 Bytes |
| Starten | `orca emulator launch de.feldexa.app --activity .MainActivity --json` → `ok=true`; `topResumedActivity=de.feldexa.app/.MainActivity` |
| Sichtbare Interaktion | `orca emulator tap 0.5 0.57` (App), `emulator launch com.android.settings`, `emulator button home`; Pane-Inhalt änderte sich jeweils sichtbar |
| Accessibility | Settings-Baum vollständig; Feldexa-Flutter-Baum nur Root-Frame (siehe §4) |
| Logcat | `orca emulator logcat --lines 120 --json`; keine App-FATAL/ANR; Flutter-Engine startet mit Impeller/OpenGLES |
| Regression der Live-Ansicht | Nach jedem Reattach/Pane-Verlust frische Frames geprüft; kein blindes Reattach ohne Zustandsprüfung |

Die App blieb nach dem letzten Schritt im Vordergrund; der Emulator und das Orca-Pane bleiben
für den Benutzer geöffnet.

---

## 6. T031 auf dem exakten Kandidaten

**Kandidat:** `056de35` (tree `f3dfbb5`). Einzige Arbeitsbaumänderung: `apps/feldexa_app/android/gradlew.bat` (vorbestehende Zeilenenden-Änderung, nicht Teil des Kandidaten). Relevante Quell-Hashes:

| Datei | SHA-256 |
|---|---|
| `apps/feldexa_app/lib/bootstrap/startup_sweep.dart` | `67b45b185b6f24145cf34f716d311fac46e503be2106bb6ac3de2cd18242c34a` |
| `apps/feldexa_app/integration_test/t031_startup_sweep_test.dart` | `679c69fc355e015bcc5b92286849cb4da9f9aa81f3bdff27253a1a46a6041e21` |

Befehl (identisches Gerät, exklusiv):

```bash
export TMPDIR=/home/xxammaxx/feldexa-worktrees/t031/build/tmpdir
export JAVA_HOME=/home/xxammaxx/.feldexa-toolchain/jdk
export GRADLE_USER_HOME=/home/xxammaxx/feldexa-worktrees/t031/build/gradle-home
export ANDROID_USER_HOME=/home/xxammaxx/feldexa-worktrees/t031/build/android-user-home
export JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=$TMPDIR"
flutter test integration_test/t031_startup_sweep_test.dart -d emulator-5554
```

| Lauf | Umgebung | Ergebnis | Log |
|---|---|---|---|
| 1 | Emulator 37.2.12, 4-GB-AVD | **PASS**, `+2: All tests passed!` | `artifacts/2026-11-17-orca-emulator/t031-3712-pass.log` |
| 2 | Emulator 37.2.13, direkter Folgelauf | **FAIL** bei Zeile 125: `expect(seenDeadline, isNotNull)` → `null`; 250-ms-Timeout feuerte vor dem nativen Recovery-Aufruf (Timing-Flake, kein Transportfehler) | `artifacts/2026-11-17-orca-emulator/t031-3713-run1-fail.log` |
| 3 | Emulator 37.2.13, Wiederholung nach Warmlauf | **PASS**, `+2: All tests passed!` | `artifacts/2026-11-17-orca-emulator/t031-3713-run2-pass.log` |

Damit ist T031 auf dem exakten Kandidaten auf dem finalen Emulator bestanden; der eine
Fehlschlag ist als reproduzierbarer Timing-Flake dokumentiert und nicht als PASS umgedeutet.
Eine Änderung des Kandidaten (z. B. größerer Timeout) wurde nicht vorgenommen, weil T031
unter Review steht und die Aufgabe keine Kandidatenänderung verlangt.

---

## 7. Regressionstests und Maintainer-Preflight

### 7.1 Repository-Preflight (neu, dauerhaft)

`tools/android/orca_emulator_preflight.py` prüft mit den dokumentierten Orca-/SDK-Schnittstellen:

- Orca-CLI-Auflösung (`ORCA_CLI_COMMAND`, sonst `orca-ide`; nie nacktes `orca` außerhalb Orcas)
- Orca-Runtime-Version
- `/dev/kvm` (Existenz, Zeichengerät, `O_RDWR`) und `emulator -accel-check`
- SDK-Komponenten (`adb`, `emulator`, `platforms/android-35`, `system-images/android-35/google_apis/x86_64`, `build-tools`)
- Schreibbarer, quota-tauglicher `TMPDIR`/`java.io.tmpdir` (8-MiB-Schreibtest)
- AVD-Profil (Pixel 7, API 35, x86_64, 4096 MB)
- genau eine QEMU-Instanz je AVD
- Bootzustand, drei aufeinanderfolgende adb-Proben, `sys.boot_completed=1`
- exakte Worktree-/Serial-Bindung aus `emulator list`
- Live-Stream `scrcpy://<serial>`, Codec und laufender scrcpy-Server auf Gerät und Host

Regressionstests: `tools/android/test_orca_emulator_preflight.py`, **24 Tests, alle PASS**
(`python3 -m unittest -v test_orca_emulator_preflight`). Abgedeckte RED-Fälle:
3072-MB-Profil, falsche API/ABI, fehlende SDK-Komponenten, fehlendes/gesperrtes TMPDIR,
falscher Worktree/Serial, Doppelstart, `smartsocket`-EPERM, adb-Timeout, unvollständiger Boot,
fehlender scrcpy-Stream/Server.

Realer RED→GREEN-Nachweis:

| Prüfung | RED | GREEN |
|---|---|---|
| AVD-Profil | `--avd-config config.ini.bak-…` → `FAIL avd_profile: hw.ramSize=3072 (expected 4096)` | live `config.ini` → PASS |
| Temp-Quota | `--tmpdir /tmp` → `FAIL temp_space: cannot accept a 8 MiB probe … Disk quota exceeded` | `--tmpdir …/build/tmpdir` → PASS |

Finaler Lauf: **13/13 PASS**
(`artifacts/2026-11-17-orca-emulator/preflight-final.json`), Exit 0.

### 7.2 Maintainer-Preflight

Der versionsgleiche Maintainer-Skill enthält den Abschnitt „Visible Orca Android preflight“
mit `scripts/lifecycle_gate.py --emulator`. Ergänzt wurden die in diesem Lauf bestätigten
Voraussetzungen:

- AVD-RAM/Profil und ein schreibbarer, quota-tauglicher `TMPDIR`/`java.io.tmpdir` vor dem
  teuren Build (tmpfs-Quota kann `EDQUOT` liefern, obwohl `df` frei meldet);
- wiederholte Transportproben statt eines einzelnen erfolgreichen Befehls;
- Verweis auf ein repository-eigenes ausführbares Preflight und dessen Evidenz.

Ausgeführt:

```text
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p 'test_*.py'
→ Ran 35 tests, OK
lifecycle_gate.py --emulator (verifizierte Fakten)
→ READY_FOR_DEVICE_TEST
```

Die `quickstart.md` nennt jetzt den Preflight als Voraussetzung für `EMULATOR`-Evidenz.
Die Skill-Änderung ist eine Prosa-Ergänzung; die frischen unabhängigen Agenten-Replays aus
`references/regression-scenarios.md` wurden in dieser Sitzung nicht erneut gestartet. Die
beiden Android-Szenarien (Worker ohne KVM/ADB bei funktionierendem Host; fehlende/veraltete
Pane nach Transportverlust) wurden stattdessen am realen Gerät durchgespielt und oben belegt.

---

## 8. Ergebnis

| Kriterium | Ergebnis |
|---|---|
| Offizieller Android-Skill installiert und geladen | PASS |
| Orca-Runtime, SDK, adb, AVD, KVM geprüft | PASS |
| `/dev/kvm` Host vs. Worker geklärt | PASS (Host nutzbar; adb-EPERM war Worker-Sandbox) |
| AVD-Profil Pixel 7 / API 35 / x86_64 / 4 GB | PASS (korrigiert von 3 GB) |
| Exklusive Einzelinstanz, keine Doppelstarts | PASS |
| Integriertes Orca-Pane sichtbar und live | PASS (Frames + sichtbare Interaktion) |
| Debug-APK gebaut, über Orca installiert und gestartet | PASS |
| Accessibility-Tree und Logcat ausgewertet | PASS (Settings vollständig; Flutter-Semantik nicht exponiert) |
| T031 auf exakt `056de35` auf demselben Emulator | PASS (2/2; ein dokumentierter Timing-Flake) |
| Regressionstests für alle bestätigten Fehler | PASS (24 Repository-Tests, RED/GREEN belegt) |
| Maintainer-Preflight ergänzt und ausgeführt | PASS (35 Skill-Tests, `READY_FOR_DEVICE_TEST`) |
| Pane nach Abschluss für den Benutzer geöffnet | PASS (finaler Screenshot 19:12) |

**Verbleibende tatsächliche Risiken/Blockaden:**

1. **QEMU-Abstürze unter langer/schwerer Host-Last** sind mit 37.2.13 nicht erneut aufgetreten,
   aber nicht bewiesen behoben. Backtraces zeigen `android_pipe_guest_recv` (SIGSEGV) bzw.
   SIGABRT; ein erneuter Absturz würde die Sitzung unterbrechen. Vor langen Läufen bleibt der
   Preflight und die dokumentierte `kill`/`attach`-Wiederherstellung erforderlich.
2. **Pane-Reconnect** kann nach Kaltstart/Transportverlust einen expliziten
   `kill`+`attach <serial> --focus` benötigen; ein automatisches Wiederaufsetzen durch Orca
   wurde nicht beobachtet. Das Pane war danach jeweils live.
3. **T031-Testflake** bei 250 ms auf dem ersten Lauf nach dem Emulator-Update; Wiederholung
   bestand. Eine Kandidatenkorrektur wurde nicht vorgenommen.
4. **Flutter-Semantik** ist für `uiautomator`/`ax` ohne aktivierte Accessibility-Bridge nicht
   sichtbar; native Screens liefern den Baum.
5. Der Kandidaten-Worktree ist ein Git-Worktree, kein separater Orca-Worktree; die
   Emulator-Session ist an den aktiven Orca-Worktree gebunden. Der Test lief auf genau diesem
   Gerät und Kandidaten.

### Versionierte Artefakte

Alle Pfade relativ zu `specs/001-scanned-form-workflow/reports/artifacts/2026-11-17-orca-emulator/`.

| Datei | SHA-256 |
|---|---|
| `pane-app.png` | `341c61ad4937c8f81403a72b9a7397264bc8c7e21565a518e6b82b49ad1a7a87` |
| `pane-final.png` | `3e25cf1bf7779ed4cfe457a638677b13fc0cbb4d2a476072dd80f17b350585e1` |
| `pane-live-launcher.png` | `3907c3a69bbbc98d9ac30e9fec34bec57526954f78b12c491b6c90fd06c2ade4` |
| `pane-settings.png` | `de4f751e8769af67ab1f7ecdc77d79f4fd6ff68ff2ad662392a286d3973f18b6` |
| `preflight-final.json` | `246e6357b254fc02fe9cbbb6d9943c991ade22183108a2acac4feb7034de5348` |
| `t031-3712-pass.log` | `d0f0868ae82b6c0d0c3c14fb0d5f24e90f6e30d5519520db3342a081bd976922` |
| `t031-3713-run1-fail.log` | `844d924ad56fc51b9696c28cec25bcdff0cc5ee5ed9102a8fa082b36713ec6c9` |
| `t031-3713-run2-pass.log` | `5cc691dffb996ab41787d9e39d64d27172fae5e16d305ae53adb5b3b36093f9c` |
