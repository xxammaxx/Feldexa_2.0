# Dependency Review Refresh — 2026-11-24

Companion record to `tools/dependency_review.md` (the T003 review) and to its §10.
Scope: technology and dependency audit on integrated `main` = `1d6afea0` (after PR #305)
and `e81060f` (after PR #306). Machine-readable form: `dependency_review_refresh_2026-11-24.json`.
This record changes no pin, no threshold and no contract.

- **Repository**: `xxammaxx/Feldexa_2.0`
- **Basis**: integriertes `main` = `1d6afea0516a300c21442f6e2361e4c9ac2b795b` (nach PR #305)
- **Werkzeug**: `technology-refresh` v1.0.0 unter Pi 1.6.0 / pi-maintainer v6.2.0
- **Auditzeitpunkt**: 2026-11-24, Abrufe 16:28–16:34 UTC
- **Maschinenlesbare Fassung**: `2026-11-24-dependency-refresh.json`
- **Beschluss-Lage**: siehe `tools/dependency_review.md` §10 (D-19-Gate bleibt unverändert gültig)
- **OCR-Teil**: `2026-11-24-ocr-lab-t263.md`

## 1. Fähigkeitsstand (getrennt belegt, keine Behauptung)

| Fähigkeit | Status |
| --- | --- |
| Vollständiger HTTPS-Abruf offizieller Registries/APIs/Seiten | **verfügbar**, 30+ vollständige Abrufe mit HTTP-Status und SHA-256 |
| Allgemeine Websuche / Discovery | **BLOCKED** — im ausführenden Harness existiert kein Suchwerkzeug; ein Research-Kind mit nur `read`/`write`/`contact_supervisor` antwortete `BLOCKED_NO_SEARCH` und lieferte bewusst keine Quellen aus dem Modellgedächtnis |
| Echte Modellaufrufe | `deepseek/deepseek-flash` und `zai-coding-cn/glm-5.3-flash` durch tatsächliche Aufrufe verifiziert; `anthropic/claude-haiku-4-5` per Auth-Check bereit |

Konsequenz: Paket-, Release- und Advisory-Fakten sind belegt. Sekundärliteratur, Marktvergleich
oder Rechtsquellen sind in dieser Session **nicht** recherchierbar und werden nicht als
gesichtet ausgegeben.

## 2. Bestandsaufnahme

| Bereich | Ist-Stand |
| --- | --- |
| Flutter / Dart | 3.47.7 stable (Framework `abaf9c5237`, 2026-10-08) / Dart 3.13.5 |
| Dart-Workspace | 11 `pubspec.yaml`, ein `pubspec.lock`, 104 gelöste Pakete (96 versioniert) |
| SDK-Constraints | Dart `^3.13.0`, Flutter `>=3.47.0 <4.0.0` |
| Gradle / AGP / KGP | 9.3.1 (mit `distributionSha256Sum`) / 9.1.0 / 2.4.0 |
| Android | compile+targetSdk 36, minSdk 26, build-tools 36.0.0 |
| Native Pins | `com.tom-roush:pdfbox-android:2.0.27.0`, `com.google.mlkit:text-recognition:16.0.1`, BouncyCastle 1.87 (Override) |
| CI | keine `.github/workflows`; `tools/gate.sh` ist das Gate |

## 3. Entscheidungen

| Komponente | installiert | neueste stabil | neueste kompatibel | Entscheidung | Grund |
| --- | --- | --- | --- | --- | --- |
| Flutter / Dart | 3.47.7 / 3.13.5 | 3.50.1 / 3.14.0 | 3.47.9 / 3.13.7 | DEFER | SDK-Wechsel ist host-global → Owner-Entscheidung |
| Gradle | 9.3.1 | 9.9.2 | 9.9.2 | DEFER | Build-Toolchain, kein Advisory, volle Verifikation nötig |
| AGP | 9.1.0 | 9.5.2 | 9.5.2 | DEFER | dito |
| KGP | 2.4.0 | 2.4.21 | 2.4.21 | DEFER | dito |
| Android-Platform | 36 | 36 | 36 | KEEP | 37.x nur Preview (`-beta`/`DEV`) |
| `pdf` / `printing` / `intl` / `crypto` | 3.13.1 / 5.15.1 / 0.20.3 / 3.0.8 | identisch | identisch | KEEP | aktuell |
| `image` | 4.12.0 | 4.13.1 | 4.13.1 | DEFER | Raster-Pfad der OCR-Kette; T263/T264-Baseline bliebe nicht vergleichbar |
| `google_mlkit_text_recognition` | 1.0.2 | 1.0.3 | 1.0.3 | DEFER | Wrapper ist laut T056 ungenutzt (App nutzt das AAR direkt) → entfernen statt aktualisieren |
| `flutter_riverpod` | 2.6.1 | 3.5.0 | 3.5.0 | DEFER | Major-Migration |
| `go_router` | 16.3.0 | 18.1.4 | 18.1.4 | DEFER | zwei Major-Sprünge |
| `share_plus` | 12.0.2 | 13.3.1 | 13.3.1 | DEFER | Major-Migration |
| `pdfrx` | 2.12.0 | 3.1.0 | 3.0.0 | DEFER | 3.1.0 verlangt Dart `^3.14.0`/Flutter `>=3.50.0` |
| `pdfbox-android` | 2.0.27.0 | 2.0.27.0 | 2.0.27.0 | KEEP | neueste, OSV-clean |
| BouncyCastle (3 Artefakte) | 1.87 | 1.87 | 1.87 | KEEP | neueste der Linie, OSV-clean |

Transitive, die innerhalb der heutigen Constraints auflösbar wären (`archive`, `cupertino_ui`,
`material_ui`, `jni`, `jni_flutter`, `pdfium_dart`, `pdfium_flutter`, `pdfrx_engine`,
`url_launcher_android`, `google_mlkit_commons`), bleiben in diesem Zyklus absichtlich
unangetastet: teils renderpfad-relevant, alle ohne Advisory-Zwang und ohne D-19-Neuprüfung
nicht zu ändern.

## 4. Advisory-Lage (echte Abfragen)

| Ziel | Umfang | Ergebnis |
| --- | --- | --- |
| OSV, Ökosystem Pub | 96 versionierte Koordinaten aus `pubspec.lock` | **0 Advisories** |
| OSV, Ökosystem Maven | BouncyCastle 1.87 (`bcprov`/`bcpkix`/`bcutil-jdk15to18`), `pdfbox-android` 2.0.27.0 | **0 Advisories** |

## 5. Ergebnis

- **Sicherheitsgetriebene Updates: 0. Kompatibilitätsgetriebene Updates: 0.**
- **Umgesetzte Updates: 0** — es gibt in diesem Stand nichts, was ohne Evidenzverlust oder
  Owner-Entscheidung *notwendig* wäre.
- **11 Aufschübe** (Tranchen U1–U5), **9 unveränderte Komponenten**.
- Keine Pin-, Lockfile-, Gradle- oder SDK-Änderung; Specs, D-19, Constitution und alle
  bestehenden Nachweise bleiben unberührt.

## 6. Vorgeschlagene Tranchen (nicht ausgeführt)

| Tranche | Inhalt | Bedingung |
| --- | --- | --- |
| U1 | Flutter 3.47.7 → 3.47.9 (Dart 3.13.7) | Owner-Freigabe; volles Gate + `flutter build apk --debug` + Emulator-E2E |
| U2 | `image` 4.13.1, `google_mlkit_*` 1.0.3, transitive Patches | **erst nach** T263-ACCEPTANCE; Baselines neu einfrieren |
| U3 | Gradle 9.9.2, AGP 9.5.2, KGP 2.4.21 | voller Gradle-Build, Release-Manifest-/APK-Prüfung, Emulator-Smoke |
| U4 | `pdfrx` 3.x | nach Flutter 3.50.1; Render-/PDFium-Vergleich auf dem Emulator |
| U5 | `flutter_riverpod` 3.x, `go_router` 18.x, `share_plus` 13.x | je eigener Migrationsplan mit Regressionstests |

## 7. Zwei Fehlquellen (dokumentiert, weil sie sonst zu falschen Schlüssen führen)

1. `https://api.github.com/repos/flutter/flutter/releases/latest` liefert `3.19.0-0.1.pre`
   (2024-01-11) und ist **nicht** der aktuelle Flutter-stable-Stand. Autoritativ ist
   `releases_linux.json` (`current_release.stable`).
2. `repo1.maven.org` für `com.android.tools.build:gradle` zeigt nur 2.x; AGP ist auf
   **Google Maven** (`dl.google.com/dl/android/maven2`) publiziert.

## 8. Nicht durchgeführt (ausdrücklich)

- Keine allgemeine Websuche (BLOCKED, siehe §1).
- Keine Release-Note-/Migrationsprosa für Flutter 3.50.x und die Majors — für KEEP/DEFER nicht
  erforderlich, für U4/U5 zwingend nachzuholen.
- Kein Android-Build, kein Gradle-Lauf, kein Emulator-Lauf: reines Lese-Audit. Der
  Android-UI-Gate ist für diesen Record `NOT_APPLICABLE`, weil keine UI-, Interaktions-,
  A11y- oder Visual-Änderung entsteht.
- T263-ACCEPTANCE bleibt offen; keine Schwelle wurde gesenkt.

## 9. Quellenbelege (vollständige Abrufe)

| UTC | URL | SHA-256 |
| --- | --- | --- |
| 2026-11-24T16:30:16Z | https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json | `d148d115bcb472f7eab4890695af2cb28023ebabad23b1559248d11abce96ad7` |
| 2026-11-24T16:30:17Z | https://pub.dev/api/packages/flutter_riverpod | `b21a4c1625b0495a6da58e1760592900c0c65e74d0c331491b81785a3cd9455d` |
| 2026-11-24T16:30:17Z | https://pub.dev/api/packages/go_router | `db7b6fb03363e9580902127acb539f38719eaae01e5cd11512fb9d8b8447eef2` |
| 2026-11-24T16:30:18Z | https://pub.dev/api/packages/pdfrx | `bd9e2e15145535328f45f360b3c30aa3ef1b7c98cf0b9ebfbd71a64c11a0b5dc` |
| 2026-11-24T16:30:18Z | https://pub.dev/api/packages/image | `dd7d8fb0815d788194eb55366bbdccada5e607c05b0768b847f5a97974dab82b` |
| 2026-11-24T16:30:18Z | https://pub.dev/api/packages/pdf | `c8757cdb1a5c078acf67adb4d959f1935a4d47fd7343e64fb1dfef18cfb1fe84` |
| 2026-11-24T16:30:19Z | https://pub.dev/api/packages/printing | `74daf564d85bc666ff21336cab2455d88e5c6fcd81cad68a9550daef21862eaa` |
| 2026-11-24T16:30:19Z | https://pub.dev/api/packages/share_plus | `f701feabbbc367e76464a730e61973b10b5fe982f94a366821cd58d6c8ed77d9` |
| 2026-11-24T16:30:20Z | https://pub.dev/api/packages/google_mlkit_text_recognition | `94fdb9ba48d60f3d669dce8bfb03ab9c3104fab18adf26f3befc9b037f50db4a` |
| 2026-11-24T16:30:20Z | https://pub.dev/api/packages/intl | `4fd4dbd3bce96c8b976b6e9962423018bf24699063a7825b07903b47d4a11091` |
| 2026-11-24T16:30:20Z | https://pub.dev/api/packages/crypto | `97799206d0a711723478194fa2f966202c423403d4b2d5cae038443d34c6ac70` |
| 2026-11-24T16:31:17Z | https://repo1.maven.org/maven2/org/bouncycastle/bcprov-jdk15to18/maven-metadata.xml | `cf480c6810f21c47ae1c5def95533480397eca10bf2c3c278aa1994d6dfa47db` |
| 2026-11-24T16:31:17Z | https://repo1.maven.org/maven2/org/bouncycastle/bcpkix-jdk15to18/maven-metadata.xml | `cae3b11069f131d1df6e5fd8ce6f26ec536c6b28756ebb7613b2eebdd8b02628` |
| 2026-11-24T16:31:17Z | https://repo1.maven.org/maven2/org/bouncycastle/bcutil-jdk15to18/maven-metadata.xml | `dfb32174c3a105757c5815ebd3946c933f50738fd07cb37aecf47e4b8b475f68` |
| 2026-11-24T16:31:25Z | https://services.gradle.org/versions/current | `317993f21f397031c2b666a24ed0b55773f82a6c1ad4a1b51295d515db37b922` |
| 2026-11-24T16:31:26Z | https://repo1.maven.org/maven2/org/jetbrains/kotlin/kotlin-gradle-plugin/maven-metadata.xml | `204d2a1383449e6e38858b2700fbb5184a8f6d0a58b2dd0b5eea024183feca89` |
| 2026-11-24T16:31:26Z | https://dl.google.com/android/repository/repository2-3.xml | `035ec4b3f1d7304cf0b073fca3960d8a4a382c6f7efe2142ff8d5f42753373e4` |
| 2026-11-24T16:31:31Z | https://dl.google.com/dl/android/maven2/com/android/tools/build/gradle/maven-metadata.xml | `c72c9590ccdf7d9ce426c163bf45e0d39e40ab4d15d7822c0298a12e1f96694e` |
| 2026-11-24T16:31:08Z | https://search.maven.org/solrsearch/select?q=g:"com.tom-roush"+AND+a:"pdfbox-android"&core=gav&rows=8&wt=json | `abcb55acc721fe77b64fa30f58edb0257bffabd46f21619faf6de972eade1ee3` |

Advisory-Abfragen (POST `https://api.osv.dev/v1/querybatch`):

| UTC | Umfang | Ergebnis |
| --- | --- | --- |
| 2026-11-24T16:30Z | 96 Pub-Koordinaten | 0 Advisories (Antwort-sha256 `6fca6e58061f8620ecd526cf3beeec67…`) |
| 2026-11-24T16:31Z | 4 Maven-Koordinaten (BC 1.87 ×3, pdfbox-android) | 0 Advisories (Antwort-sha256 `8ad79079fd9aff33d25ee88b444368b3…`) |

## 10. Echter Auflösungsvergleich (`flutter pub outdated`)

Direkte Abhängigkeiten mit Abweichung: `flutter_riverpod` 2.6.1 (auflösbar 3.5.0),
`go_router` 16.3.0 (18.1.4), `google_mlkit_text_recognition` 1.0.2 (1.0.3),
`image` 4.12.0 (4.13.1), `pdfrx` 2.12.0 (**auflösbar nur 3.0.0**, weil 3.1.0 Dart 3.14
verlangt), `share_plus` 12.0.2 (13.3.1). `pdf`, `printing`, `intl`, `crypto`: aktuell.


## 11. mindloop-ocr-lab — Einbeziehung für T263 (Stand 2026-11-24)


Quelle: `https://github.com/xxammaxx/mindloop-ocr-lab`, gelesen über die GitHub-API und
`raw.githubusercontent.com`. Abrufe: 2026-11-24, 16:33–16:34 UTC (GitHub-API und `raw.githubusercontent.com`).

## 1. Gepinnter Stand

| Feld | Wert |
| --- | --- |
| Vertrauenswürdiger Hauptzweig | `main` = `6eda1af7e5525b94615b747c410be662a14ba774` (Commit-Datum 2026-11-22T17:51:50Z) |
| Zweige | `main`, `research/region-crop-retry` = `1a6d33762daa7b401d828c0bd07aad5175a3d8a4` |
| README (Vertrag) | sha256 `74dbf52487d917955f1c27b275261fde5265ed667f77f0e4e8f1a348b7d7682a` |
| Ergebnis-Kontexte unter `results/` | 6 (`0b5c5be6`, `381c1d4f`, `66ebc28a`, `7842ea09`, `833f8552`, `b9409d19`) |
| Consumer-Engine | **`com.google.mlkit:text-recognition:16.0.1`** (Lab: `environment.engine`; Feldexa: `apps/feldexa_app/android/app/build.gradle.kts:61`) — **identisch** |
| Feldexa-Pfad im Lab | `feldexa-gray-bitmap` (gray8→ARGB, `max_source_side` 2400) |
| Feldexa-Kohorte | `fixtures/feldexa/` — byte-identische `sf-001`–`sf-004` aus Feldexa-Commit `be606263…`, 13 Seiten, 63 deklarierte Feldlabels |

## 2. Was die vertrauenswürdigen Ledgers tatsächlich sagen

Nur Kontexte auf `main` zählen als Lab-Beleg. Die **zwei neuesten** ML-Kit-Läufe
(2026-11-24 15:46Z = `failure`, 16:00Z = `success`) liefen auf **`research/region-crop-retry`**,
nicht auf `main`; im erfolgreichen Lauf wurden die Jobs `research` und `continue`
**übersprungen**. Diese Läufe sind **kein** trusting-main-Beleg und werden hier nicht verwendet.

| Kontext | vollständig | Engine | gemessene Kandidaten | Status auf `feldexa-gray-bitmap` |
| --- | --- | --- | --- | --- |
| `7842ea09…` | ja | ML Kit 16.0.1 | `contrast1`, `sharpen`, `contrast`, `threshold`, `scale2` | alle **REJECTED_DEV** |
| `0b5c5be6…` | ja | ML Kit 16.0.1 | `contrast1-fusion` (2 Pässe, spatial-add-only) | **REJECTED_DEV** |
| `66ebc28a…` | nein (2 Records) | ML Kit 16.0.1 | `contrast1`, `sharpen` | beide **REJECTED_DEV** |
| `381c1d4f…`, `833f8552…`, `b9409d19…` | nein | Tesseract 5.3.4 / 5.5.0 | Tesseract-Kandidaten | Legacy-Referenz, **keine** App-Aussage |

Im neuesten vollständigen Kontext (`0b5c5be6`) zeigt die Diagnostik für den Feldexa-Pfad
`added_lines = 0` bei allen Seiten und Konflikte auf `dev-0` (1), `dev-2` (1), `dev-4` (3) —
der Fusion-Pass fügt also nichts hinzu, was die Baseline-Hits erhält.

**Ergebnis:** 7 gemessene ML-Kit-Kandidaten über die vertrauenswürdigen Kontexte, **kein
einziger** mit einem verwertbaren, verlustfreien Gewinn auf dem Feldexa-Pfad. Es gibt
derzeit **keinen `LAB_CANDIDATE`**, den Feldexa übernehmen könnte.

## 3. Einordnung nach `technology-refresh` §Optional OCR lab source

- `LAB_CANDIDATE` = Hypothese, **nie** App-Akzeptanz. Hier gibt es nicht einmal eine Hypothese,
  also auch nichts zu reproduzieren.
- Engine-Identität stimmt (16.0.1, latin, bundled), Adapter-Pfad `feldexa-gray-bitmap`
  entspricht dem realen Feldexa-Konvertierungspfad (gray8→ARGB).
- Die Kohorte ist synthetisch/dev+validation mit **fixem** Validierungssplit (README nennt die
  Übergeneralisierungsgefahr selbst). Sie ist Explorationsbeleg, nicht unabhängige
  Endkunden-Akzeptanz; Feldexa #33 (echtes, rechtsgeklärtes Korpus) ist weiterhin offen.
- Keine privaten Scans, kein privater Code und keine Produktionsausgabe liegen im öffentlichen
  Lab; Roh-OCR-Text bleibt ephemer.

## 4. Konsequenz für T263-ACCEPTANCE

1. Die Lab-Beleglage **stützt** die bisherige Diagnose: für den gebündelten ML-Kit-16.0.1-Pfad
   ist mit den untersuchten Vorverarbeitungs-/Fusionsvarianten kein verlustfreier Gewinn
   erzielbar; der Clean-200-dpi-FAIL (CER 2,33 % > 2,00 %, Special-Recall 93,27 % < 100 %,
   Label 76,92 % < 100 %) ist eine Grenze des gebündelten Engine-Modells, keine
   Vorverarbeitungs-Lücke und keine Schwellen-Frage.
2. **T263-ACCEPTANCE bleibt offen** und ist weiterhin eine Owner-Entscheidung. Es werden
   **keine** Erfolgsschwellen nachträglich gesenkt, und es wird kein Lab-Ergebnis als
   App-Akzeptanz umgedeutet.
3. Ein neuer Lab-Lauf auf `research/region-crop-retry` ist **in Arbeit, aber nicht auf `main`**
   und damit nicht als Beleg verwendbar. Er darf nicht als „quasi fertig" zitiert werden.
4. Nächster belastbarer Schritt wäre eine **consumer-seitige** Messung auf Feldexa-Seite mit
   gepinntem Lab-Commit, nicht eine weitere Lab-Variantenrunde ohne neue Hypothese (Katalog
   ist endlich; README: „Add new hypotheses through a reviewed change").

## 5. Nebenbefund (nicht in diesem Zyklus umgesetzt)

`google_mlkit_text_recognition` (Dart-Wrapper 1.0.2) ist laut T056-Abschlussnotiz in
`tasks.md` ein **vorbestehend ungenutztes Plugin**: die App spricht die native
Kotlin-Service-Schicht und das `text-recognition:16.0.1`-AAR direkt an. Ein Wrapper-Bump
ändert daher nichts am Laufzeit-OCR — als eigenes Aufräum-Issue aber sinnvoll (entfernen
statt aktualisieren). Das entwertet die Defer-Begründung in `AUDIT.md` nicht, präzisiert sie.
