# 2026-11-22 EMULATOR — T263 German OCR special characters and Unicode qualification

| Field | Value |
| --- | --- |
| Evidence class | `EMULATOR` |
| Result | `FAIL` |
| Task / issue | `T263 / #263` |
| Date / timezone | `2026-11-22 13:56 Europe/Berlin` |
| Revision | base commit `2a1452b378660940d70f99f0ead88da6a933da28`; tree `dirty`: `apps/feldexa_app/android/gradlew.bat` SHA-256 `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62` (pre-existing line-ending-only working-tree change, never staged); the candidate commit SHA is recorded in the external attestation |
| External attestation | Coordinator-held worker_done transport attestation for this T263 dispatch; it records the candidate commit, the final HEAD and tree, and this report's byte size and SHA-256 after the report commit. No push, PR, or merge was performed |
| Build identity | `apps/feldexa_app` debug build produced by the integration-test build (`flutter test` device mode, Gradle `assembleDebug`), APK SHA-256 `7ad9da233991eb80fcb482036ae5f2e23d3b7201998046238039e4746f6af500`; no release/profile build, no shrinking, no signing change |
| Toolchain | Flutter `3.47.7` stable (framework `abaf9c5237`), Dart `3.13.5`; bundled ML Kit `text-recognition:16.0.1` (latin, on-device); Poppler `pdftoppm 26.10.0`; ImageMagick `7.1.2-34`; Python `3.14`; `dart:io` on Android 15 |
| Input | fixture `sf-005.pdf` (2 pages, embedded Noto Sans Regular, SIL OFL 1.1) SHA-256 `671dd6b8b30cd46910e1bab5e0c7a69cfbb5d22efe0000520a25108f38e08e45`; pre-declared ground truth `tools/corpus/de-ocr/reference-de.ground-truth.json` SHA-256 `b557323c346f9d8422b93706e75425a0dcc9b9de9bde7c887712a46803d23881`; variant manifest SHA-256 `19b351b43f2cb33c1cc91d14fa5473f105662097bebe8f059239faf70078440c`; fixture catalog `fixtures-1.1.0` SHA-256 `b26ed212f1ceefd3e07da0f739f7c09833a5fe00816e88f10693ddce639edcbc` |

## 1. Scope

This report covers the runtime half of issue #263 (`T263`): German special
characters and Unicode regressions measured on the real Android production
path, on the Orca-allocated Pixel 7 API 35 emulator, with the pre-declared
seven variants of the additive `sf-005` reference suite `de-ocr-1.0.0`.

What it proves, per pre-declared variant: raw OCR character fidelity (CER,
special-character precision/recall, confusion matrix), Unicode representation
findings (NFC/NFD, case, `ae/oe/ue/ss`, missing umlaut dots, `ß`→`B`), semantic
label/type assignment from the production `AnalyzeDocument` suggestions, and one
`confirmSuggestion` plus encrypted-store label takeover round trip.

All three corrections of this task were executed on the device: §5.7 records the
correction-1 label/type fix, §5.8 the correction-2 deskew stage and §5.9 the
correction-3 review fixes. §5.1–§5.6 remain the *pre-fix baseline* by design; the
current runtime results are §5.9 (committed HEAD `3102557`).

What it does **not** prove: physical-device behaviour (`DEVICE`), performance or
the SC-004 claim, corpus `corpus-1.0.0`/`metric-definition.v1` figures (those
belong to T033/T034/T059/T060/T142), or any SC-001/SC-003 claim. The measured
result is `FAIL`: the reference variant exceeds its pre-declared ceilings, so
T263 is **not** an acceptance PASS. Thresholds were declared before the run and
were not changed afterwards.

## 2. Revision and build

- Base: `origin/main` commit `2a1452b378660940d70f99f0ead88da6a933da28`; the
  rebased T263 branch is built from it (previous T263 HEAD
  `7409fbb540123ce79ac0a21fe10a5925f5b89f28`, old base
  `1a141cdac586238021ade8a18e40c08883a9d1a6`).
- Run-time HEAD/tree as recorded by the driver before the evidence commit:
  `a1718363747b16bb842d1cbaa43af9efb79e5382` / tree
  `90ea067abaff1d72d07d75fbba0c5966649fdc82`, with the two tooling files of
  this task modified in the working tree:
  `tools/android/t263_drive_de_ocr.sh` SHA-256
  `720c7521d6444de94f03159bfac142de1e22c779aa51739dd7dd22bef784e576` and
  `apps/feldexa_app/integration_test/android_de_ocr_test.dart` SHA-256
  `8b32bfd5fa6481bb8686746160dbfc1908f8837c0daf8807de51f6d0e49d9411`.
- Build: `flutter test --no-pub integration_test/android_de_ocr_test.dart -d
  emulator-5554` in `apps/feldexa_app` (Gradle `assembleDebug`), APK
  `build/app/outputs/flutter-apk/app-debug.apk` SHA-256
  `7ad9da233991eb80fcb482036ae5f2e23d3b7201998046238039e4746f6af500`.
- The candidate commit SHA, the final HEAD/tree, and this report's own bytes and
  SHA-256 are recorded in the external attestation, not here.

## 3. Environment

```text
EMULATOR: Pixel 7 API 35, exclusive allocation AVD T025_Pixel7_API35_KVM_20261115, serial emulator-5554;
          system image google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys, Android 15, x86_64;
          RAM 3920 MB (4014392 kB), 1080x2400 @ 420 dpi; boot_completed 1;
          APK apps/feldexa_app/build/app/outputs/flutter-apk/app-debug.apk SHA-256 7ad9da233991eb80fcb482036ae5f2e23d3b7201998046238039e4746f6af500;
          build mode/flags debug, dart debug, no shrinking; Orca emulator session attached to this worktree (stream scrcpy)
```

The host carried a second, physical device (a Samsung handset) during the run.
It was never addressed: every device command in the driver is scoped with
`-s emulator-5554`, `T263_SERIAL` was fixed to that serial, and the driver now
refuses a non-emulator serial. The physical device is not part of this
evidence and was not touched.

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `dart run tools/corpus/synthetic/generate.dart --check` (repository root) | 0 | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/host-generate-check.log` | PASS |
| 2 | `bash tools/corpus/de-ocr/verify.sh` (repository root) | 0 | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/host-suite-verify.log` | PASS |
| 3 | serial/AVD/API-35/boot check plus `orca emulator devices --json` inside `tools/android/t263_drive_de_ocr.sh` (repository root) | 0 | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/orca-emulator-devices.json` | PASS |
| 4 | fixture, ground-truth and variant SHA-256 verification on host and device (driver) | 0 | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/fixture-sha256.txt` | PASS |
| 5 | `flutter test --no-pub integration_test/android_de_ocr_test.dart -d emulator-5554` (`apps/feldexa_app`) | 0 | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/integration-android-t263.log` | PASS |
| 6 | run-file pull through `adb exec-out run-as` while the test was still running (repository root) | 0 | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/marker-sequence.txt` | PASS |
| 7 | `dart run tools/metrics/de_ocr_qualification.dart --run specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/t263-run-emulator.json --run specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/t263-run-injected.json --require-device-evidence` (repository root) | 1 | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/metrics-emulator.log` | FAIL |
| 8 | `python3 tools/metrics/build_text_layer_run.py` followed by `dart run tools/metrics/de_ocr_qualification.dart --run specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/t263-text-layer-run.json` (repository root) | 1 | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/metrics-text-layer.log` | FAIL |
| 9 | privacy: recognized text/fixture labels absent from the integration log (driver) | 0 | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/privacy-log-check.txt` | PASS |
| 10 | privacy: no network API in the integration test (driver) | 0 | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/privacy-source-check.txt` | PASS |

Check 7 is the task gate and it failed: the reference variant does not meet its
pre-declared ceiling. Check 8 covers the PDF text-layer control, which itself
passed at CER 0.00 % (2/2 pages, 0 missing/extra code points); the scorer's
process exit is 1 because the same report file lists the seven device variants
as `NOT_RUN`, which is the designed behaviour of that control run.

## 5. Results

Raw-text normalization is `none` throughout: ground truth and OCR text are
compared as Unicode code points, so nothing is silently repaired.

| Variant | Class | Status | CER | Special P | Special R | Field P | Field R | Type acc. | Unresolved labels |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `clean-200dpi` (reference) | `EMULATOR` | FAIL | 2.33 | 97.98 | 93.27 | 17.81 | 100.00 | 15.38 | 8 |
| `clean-150dpi` | `EMULATOR` | FAIL | 2.21 | 98.98 | 93.27 | 17.81 | 100.00 | 15.38 | 8 |
| `clean-300dpi` | `EMULATOR` | FAIL | 2.27 | 97.96 | 92.31 | 17.81 | 100.00 | 15.38 | 8 |
| `scan-150dpi-low-contrast` | `EMULATOR_INJECTED_RASTER` | PASS | 2.21 | 99.01 | 96.15 | 25.49 | 100.00 | 69.23 | 8 |
| `scan-200dpi-shadow` | `EMULATOR_INJECTED_RASTER` | PASS | 2.63 | 97.96 | 92.31 | 13.13 | 100.00 | 15.38 | 8 |
| `scan-200dpi-skew-3deg` | `EMULATOR_INJECTED_RASTER` | FAIL | 48.48 | 72.45 | 68.27 | 0.37 | 7.69 | 0.00 | 0 |
| `scan-200dpi-jpeg-q35` | `EMULATOR_INJECTED_RASTER` | PASS | 2.27 | 97.98 | 93.27 | 15.66 | 100.00 | 15.38 | 8 |

Pre-declared thresholds against the observed values:

| Variant | Class | Exact critical lines required | CER ceiling | Special-recall floor | Observed CER | Observed special recall | Verdict |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| `clean-200dpi` | `EMULATOR` | yes | 2 % | 100 % | 2.33 % | 93.27 % | FAIL |
| `clean-150dpi` | `EMULATOR` | no | 8 % | 80 % | 2.21 % | 93.27 % | FAIL |
| `clean-300dpi` | `EMULATOR` | no | 5 % | 90 % | 2.27 % | 92.31 % | FAIL |
| `scan-150dpi-low-contrast` | `EMULATOR_INJECTED_RASTER` | no | 18 % | 60 % | 2.21 % | 96.15 % | PASS |
| `scan-200dpi-shadow` | `EMULATOR_INJECTED_RASTER` | no | 15 % | 70 % | 2.63 % | 92.31 % | PASS |
| `scan-200dpi-skew-3deg` | `EMULATOR_INJECTED_RASTER` | no | 20 % | 60 % | 48.48 % | 68.27 % | FAIL |
| `scan-200dpi-jpeg-q35` | `EMULATOR_INJECTED_RASTER` | no | 15 % | 70 % | 2.27 % | 93.27 % | PASS |

**Reference verdict.** `clean-200dpi` is `FAIL`: CER 2.33 % exceeds the 2.00 %
ceiling, special-character recall 93.27 % is below the required 100 %, five
critical lines are not exactly recognised, eight reference fields have no
credible label, and label accuracy is 0.00 % on the reference variant.

### 5.1 Raw critical lines that are not exact (reference `clean-200dpi`)

| Line | Expected | Observed |
| --- | --- | --- |
| `p0-l07` | `Ä Ö Ü ä ö ü ß ẞ` | `ÄÖüä ö üßB` |
| `p0-l08` | `Ärger Öffnung Übung Äußerst` | `Ärger Öffnung Übung Ảußerst` |
| `p0-l12` | `Gebühr: 12,50 € · Fläche: 45 m² · Raum: 7 m³` | `Gebühr: 12,50 €· Fläche: 45 m² Raum: 7 m` |
| `p0-l13` | `„Deutsch“ – Gedankenstrich — Auslassung … § 5` | `„Deutsch" - Gedankenstrich– Auslassung ... S5` |
| `p0-l22` | `Zeichen: ẞ ß Ä Ö Ü ä ö ü € m² m³` | `Zeichen: BBÄÖÜä ö ü € m² m²` |

### 5.2 Special-character confusion matrices

`clean-200dpi` (reference):

| Expected | Observed | Kind | Count |
| --- | --- | --- | ---: |
| `ẞ` | `B` | substitution | 1 |
| `ẞ` | ∅ | deletion | 1 |
| `ß` | `B` | substitution | 1 |
| `Ä` | `Ả` | substitution | 1 |
| `Ü` | ∅ | deletion | 1 |
| `³` | `²` | substitution | 1 |
| `³` | ∅ | deletion | 1 |
| ∅ | `ü` | insertion | 1 |

`clean-150dpi`: `ẞ`→`B`, `ẞ`→∅, `ß`→`B`, `Ä`→`Â`, `Ü`→∅, `³`→`?`, `³`→∅, `ü` inserted.
`clean-300dpi`: `ẞ`→`B`, `ẞ`→∅, `ß`→`B`, `Ü`→∅, `²`→`?`, `²`→∅, `³`→`²`, `³`→∅, `ü` inserted.
`scan-150dpi-low-contrast`: `ẞ`→`B`, `ẞ`→∅, `ß`→`B`, `³`→`²`.
`scan-200dpi-shadow`: `ß`→`B` ×2, `ẞ`→`B`, `ẞ`→∅, `Ä`→`Å`, `Ü`→∅, `³`→`²`, `³`→∅, `ü` inserted.
`scan-200dpi-jpeg-q35`: `ß`→`B` ×2, `ẞ`→`B`, `ẞ`→∅, `³`→`²` ×2, `²`→∅.
`scan-200dpi-skew-3deg` (CER 48.48, geometry association collapses to 30/51
lines): 20 confusion entries dominated by shifted-line insertions/deletions
(`ä`/`ö`/`ü`/`ß` insertions against deletions at the same positions), plus
`³`→∅, `²`→`?`, `²`→∅.

### 5.3 Unicode findings

- **U+1E9E capital sharp S is not produced by the bundled ML Kit latin model on
  any variant.** It is read as `B` or dropped (`Zeichen: BBÄÖÜä ö ü…`). This is
  the single most reproducible special-character loss (7 of 7 variants).
- **Superscripts are confused and dropped.** `m³` reads as `m²`, `m` or `m?`;
  `m²` survives in most variants and is lost in the 300 dpi and JPEG variants.
- **`ß` is read as `B`** in 5 of 7 variants, including the clean reference; there
  is no variant in which `ß` is always correct.
- **Typographic punctuation degrades to ASCII**: `“`→`"`, `–`/`—`→`-`, `…`→
  `...`, `§`→`S`. `€` is recognised in every variant that recognises the line.
- **No silent normalization.** The production `labelText` keeps the OCR spelling
  verbatim; the scorer flags non-verbatim labels and found 0 in five variants
  and 3 in `clean-150dpi`/`clean-300dpi` (the 3 are header lines whose OCR text
  differs from the typed ground truth, not a repair).
- **NFC/NFD.** The host-side RED/GREEN fix in `TypeInference._normalizeForMatching`
  (recorded in `2026-11-22-t263-evidence.md`) is not contradicted by any runtime
  finding: ML Kit emits precomposed characters in every variant that recognises
  the line, and no combining mark (U+0300–U+036F) appeared in the OCR output.

### 5.4 Semantic assignment (production `AnalyzeDocument`)

Field recall is 100 % in six variants (all 13 ground-truth fields matched under
`IoU ≥ 0.5`), but field precision is poor (13.13 %–25.49 %) because the detector
emits many extra candidates (29–69 suggestions per page). Type accuracy is
15.38 % (2/13) in five variants and 69.23 % (9/13) in
`scan-150dpi-low-contrast`; **label accuracy is 0.00 % on the reference
variant** and 8 of 13 field labels are `unresolved` in six variants. On the
reference page 2, 24 of 32 suggestions carry a label, but the labels are drawn
from document headings (`Musteramt für Bürgerdienste`, `1. Felder mit deutschen
Bezeichnungen`, `2. Mehrzeilige Erklärung`) rather than from the field labels the
fixture prints, so the semantic label metric cannot reach 100 % on this fixture.
No forced-type violation (`keyword_*` cue without a label) and no auto-resolved
suggestion were observed in any variant.

`scan-200dpi-skew-3deg` loses the semantic association almost entirely (1/13
fields matched, type accuracy 0.00 %), consistent with its 30/51 line
association rate.

### 5.5 Label takeover (production `confirmSuggestion` + encrypted store)

PASS. From the `clean-200dpi` page 2 analysis the test took the first
production suggestion whose `labelText` carries a real German special
character: label `Musteramt für Bürgerdienste` (type `multiline`, rect
x 56.875 / y 43.5 / w 481.625 / h 18 pt, confidence 0.47, resolution
`unresolved`), confirmed it through the production `confirmSuggestion` command,
wrote the document through the real Android encrypted store, reloaded it and
compared code point by code point: the label survived verbatim (Ä/ü intact) and
the stored source PDF stayed byte-identical (SHA-256
`671dd6b8b30cd46910e1bab5e0c7a69cfbb5d22efe0000520a25108f38e08e45`).
The label is a document header, not a field label: the round trip proves the
character-faithful takeover path, not a correct label assignment (§5.4).

### 5.6 Device and artifact identity

- Serial `emulator-5554`, AVD `T025_Pixel7_API35_KVM_20261115`, API 35, Android
  15, `google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043/12960925:userdebug/dev-keys`,
  x86_64, 3 920 MB RAM, 1080×2400 @ 420 dpi, `boot_completed=1`.
- APK SHA-256 `7ad9da233991eb80fcb482036ae5f2e23d3b7201998046238039e4746f6af500`.
- Fixture SHA-256 identical on host, on device, and in the ground truth:
  `671dd6b8b30cd46910e1bab5e0c7a69cfbb5d22efe0000520a25108f38e08e45`;
  ground truth SHA-256 identical on host and device:
  `b557323c346f9d8422b93706e75425a0dcc9b9de9bde7c887712a46803d23881`.
- Run-file SHA-256: `t263-run-emulator.json`
  `1ee7648fcb28c30a3cd40b56fcb68781c6b9d83bbb419b808257a385748d7ff0`,
  `t263-run-injected.json`
  `4cab7b85d7dde49e611c2ef1a08bc999886c24031a795a1a1799895912177140`.

### 5.7 T263 correction-1 — defect fix status (executed; measured in §5.8/§5.9)

The label/type defect in §5.4 has a proven root cause and a verified fix. The
correction-1 rerun itself could not be executed at the time (Orca runtime
outage, no device evidence, no device command issued); the fix is measured in the
later executed runs — label accuracy 69.23 % in §5.8 and 76.92 % in §5.9 against
the 0.00 % baseline of §5.4.

- **Root cause.** `TypeInference` accepted a label only inside a 24 pt Euclidean
  gap, but this fixture — like a typical authority form — prints each field
  label in a left column and its input region in a second column, so the
  label-to-field gap is 14–90 pt depending on the label's own length. 9 of the
  13 reference fields therefore got no label at all and the rest took the
  nearest heading. That is why label accuracy was 0.00 % and 8 field labels were
  unresolved, and it is also why 12 of 13 suggestions fell back to `multiline`.
- **Fix.** A label printed on the candidate's own row (overlapping vertical
  spans, not printed inside the candidate region) is now associated by layout,
  and a same-row label outranks a nearer line above or below. This is the
  documented cue semantics of `ocr_alignment_right` ("the candidate is to the
  right of an OCR label line"). No threshold, golden datum, ground truth,
  expected text, or recognized character was changed, and no recognized text is
  rewritten or normalized.
- **RED/GREEN.** Three new regression tests fail at the pre-fix bytes of
  `packages/feldexa_recognition/lib/src/type_inference.dart` (commit `40a4260`)
  and pass after the fix; the focused suite is 58/58 green. The RED and GREEN
  console logs, the exact tests, and the file hashes are recorded in
  `2026-11-22-t263-evidence.md` (class `NONE`).
- **Rerun status (superseded).** The correction-1 rerun was blocked by an Orca
  runtime outage and produced no device evidence at the time. It was executed
  later: §5.8 is the correction-2 run and §5.9 the correction-3 run. The numbers
  in §5.1–§5.6 remain the *pre-fix* baseline by design and are cited as such.
- **Special characters remain unfixed.** `ß`/`ẞ`→`B`, `m³`→`m²`, `§`→`S` and the
  ASCII-folded punctuation are limitations of the bundled ML Kit Latin model.
  Removing them would require a different engine or character-substitution
  post-processing, and both are forbidden by this correction's rules, so those
  cases stay `FAIL` as measured.
- **Skew: fixed, and the variant is re-classified.** At the correction-1 state
  the pipeline had no deskew stage, so a tilted raster reached the recognizer
  as-is (30/51 lines associated). Correction-2 added the verified deskew stage
  (§5.8) and correction-3 corrected its inverse rectangle mapping (§5.9). The
  variant's remaining `FAIL` (CER 43.51 % in §5.9) is **not** a missing deskew
  stage: the product reports boxes in the raster frame it was given, while the
  suite annotates the upright page, so the measurement is not frame-comparable —
  see §5.9 for the decision that is still open.

### 5.8 T263 correction-2 — deskew stage, post-fix run (Orca runtime ready)

Correction-2 adds a verified deskew preprocessing stage and re-measures all
seven pre-declared variants at the new candidate. **Orca visibility: observed.**
The driver's Orca allocation gate passed (`orca emulator devices --json` →
`ok: true`, one `emulator-5554` entry, `T025_Pixel7_API35_KVM_20261115`, API 35,
state `booted`; session attached to this worktree). The run is
`2026-11-22-t263-emulator-c2`; the pre-fix `2026-11-22-t263-emulator/` evidence is
unchanged.

**Skew root cause and fix.** At the pre-correction state the pipeline had no
deskew stage, so the injected 3° raster reached the recognizer tilted: lines merged or were dropped (30/51
associated) and the resulting boxes were too tall and too far from the annotated
rows. `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/ocr/SkewCorrection.kt`
now estimates the dominant row skew with a projection-profile search
(±5°, 0.25° steps, ink-thresholded, subsampled), rotates the raster upright with
bilinear sampling on a white background, and maps the recognizer's rectangles
back into the original raster frame so the page-point mapping is unchanged. An
upright page (estimate below 1.0°) is passed through untouched, which is why
every non-skew variant keeps its exact pre-fix values.

**RED/GREEN (host JVM, `NONE` class).** `SkewCorrectionTest` fails at the
pre-fix baseline (`correctionFor` returned no correction; exactly the 3
deskew/symmetry tests fail, the 3 no-op/identity tests pass) and passes after the
fix. `./gradlew --no-daemon :app:testDebugUnitTest --tests
'de.feldexa.app.ocr.SkewCorrectionTest' --tests
'de.feldexa.app.ocr.MlKitOcrServiceTest'` → `BUILD SUCCESSFUL` (RED log:
`…-c2/host-jvm-skew-red.log`, GREEN log: `…-c2/host-jvm-skew-green.log`). The
Gradle daemon was stopped afterwards.

**Before/after, all seven pre-declared variants (thresholds unchanged).**

| Variant | Class | CER before → after | Special recall before → after | Label acc. before → after | Type acc. before → after | Unres. labels before → after | Result before → after |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `clean-200dpi` (reference) | `EMULATOR` | 2.33 % → 2.33 % | 93.27 % → 93.27 % | 0.00 % → 69.23 % | 15.38 % → 15.38 % | 8 → 1 | FAIL → FAIL |
| `clean-150dpi` | `EMULATOR` | 2.21 % → 2.21 % | 93.27 % → 93.27 % | 0.00 % → 69.23 % | 15.38 % → 15.38 % | 8 → 1 | FAIL → FAIL |
| `clean-300dpi` | `EMULATOR` | 2.27 % → 2.27 % | 92.31 % → 92.31 % | 0.00 % → 69.23 % | 15.38 % → 15.38 % | 8 → 1 | FAIL → FAIL |
| `scan-150dpi-low-contrast` | `EMULATOR_INJECTED_RASTER` | 2.21 % → 2.21 % | 96.15 % → 96.15 % | 7.69 % → 84.62 % | 69.23 % → 69.23 % | 8 → 1 | PASS → PASS |
| `scan-200dpi-shadow` | `EMULATOR_INJECTED_RASTER` | 2.63 % → 2.63 % | 92.31 % → 92.31 % | 7.69 % → 84.62 % | 15.38 % → 15.38 % | 8 → 1 | PASS → PASS |
| `scan-200dpi-skew-3deg` | `EMULATOR_INJECTED_RASTER` | 48.48 % → **15.42 %** | 68.27 % → **87.50 %** | 0.00 % → 0.00 % | 0.00 % → **100.00 %** | 0 → 0 | FAIL → **PASS** |
| `scan-200dpi-jpeg-q35` | `EMULATOR_INJECTED_RASTER` | 2.27 % → 2.27 % | 93.27 % → 93.27 % | 7.69 % → 84.62 % | 15.38 % → 15.38 % | 8 → 1 | PASS → PASS |

The deskew fixes the skew case (CER 48.48 % → 15.42 %, special recall 68.27 % →
87.50 %, now inside the pre-declared ceiling 20 % / floor 60 %) and changes
nothing on upright pages. The label/type fix from correction-1 is now measured
on device: label accuracy 0.00 % → 69.23 % on the clean variants and 7.69 % →
84.62 % on the degraded ones, unresolved labels 8 → 1. Field precision/recall,
CER and special-character recall on the clean variants are unchanged, because
neither fix touches the raster of an upright page or the character model.

**Remaining FAILs (unchanged thresholds, no substitutions).**

- `clean-200dpi` (reference): CER 2.33 % > 2.00 %, special recall 93.27 % < 100 %,
  5 critical lines not exactly recognised, label accuracy 69.23 % < 100 %.
- `clean-150dpi`: CER 2.21 % (inside its 8 % ceiling) but special recall 93.27 %
  and 4 critical lines unresolved keep it FAIL; `clean-300dpi`: same at 2.27 % /
  92.31 %.
- Special characters (`ß`/`ẞ`→`B`, `m³`→`m²`, `§`→`S`, ASCII-folded punctuation)
  remain a bundled-ML-Kit Latin model limit. A fix would need a different engine
  or character-substitution post-processing, both forbidden here, so they stay
  FAIL as measured.

**Correction-2 artifacts.**

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c2/host-jvm-skew-red.log` | 22585 | `a6ace6f9e9a5ad33e9b1dc5ebb6f46a492578a4ecd7961e13f6d778dc47848b1` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c2/host-jvm-skew-green.log` | 17839 | `e29d478331dc199ad5774356280218d25759a743b83be5d630e7a0e1e816f73e` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c2/t263-report.md` | 11934 | `82be2bc9f7cee5b320c16b265b601202b22665baab98d48ffd9f149ff95badb4` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c2/t263-report.json` | 108234 | `a09f9fbddf19c007aba7fe0fa106b5cad437a91fadbc97b54c39dc07bb4ec709` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c2/t263-run-emulator.json` | 174866 | `2d1f38ca46dddcab7de7e911712c10ea7bbe03f78feea9a16b0c3b32ffd9227f` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c2/t263-run-injected.json` | 347991 | `e3dfff338d8d6427696fbbb77e635f89638df740a6fd9049164cebbdd8ecf0df` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c2/metrics-emulator.log` | 715 | `db0dbb65452fbb2a878be520516588c7dc23bf779866dac8c8d45eaf9f8e4c6f` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c2/marker-sequence.txt` | 530 | `624f5e7ca6678036b833855a174ca724caf4090cb7c0e901688f59cf39672441` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c2/device-identity.txt` | 298 | `265c299fe643739f0c63d2fc73f638d221a7aa9322b021641ab53bc0fedbbf56` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c2/git-identity.txt` | 771 | `04d83eddc026474edb84652c027589016ccd8caaadbbeb6f8e7406b82bf2893f` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c2/orca-emulator-devices.json` | 2151 | `3ac64d4e93ab2258fd006a98d9b4f60760f6bfd7b4fc17cfc372ee15ebbdbc79` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c2/orca-emulator-sessions.json` | 484 | `0040ae70cc95df319e96d81c87b7046d8a1f46dfa34a8a6e4e51a185ab783b25` |

### 5.9 T263 correction-3 — review fixes, post-fix run at a committed HEAD

Both independent reviews failed the correction-2 candidate. Correction-3 fixes
the code findings and re-runs all seven variants **at the committed code HEAD**
(commit `310255750fc6f828d5236f04c3e05a50f74b50ea`, tree
`22dbc94098134e0d25240b6a407fb109587a0ad8`), so the run record and the
candidate now agree.

**Fixes.**

- *A1 (inverse rect mapping).* `mapRectBack` used `R(-correction)`, the same
  direction `rotate` already applies, so boxes were rotated twice. It now uses
  `R(+correction)`; a known-point round-trip test failed before and passes after
  (host JVM RED/GREEN in the evidence directory).
- *A3 (AABB clamp).* The mapped axis-aligned box is clamped to
  `[0,width] x [0,height]`; an edge-rectangle test failed before and passes after.
- *A2 (label direction).* `_sharesRow` accepted any label with any vertical
  overlap on any side. It now requires the label's right edge at or before the
  candidate's left edge (2 pt tolerance) and at least half of the shorter box
  overlapping; a right-side value line, a one-point top sliver and a tall
  multiline candidate are pinned by tests (Dart RED 59+2 failed → 61/61 GREEN).
- *B4 (verbatim scope).* The scorer counted any label differing from the run
  record's OCR lines as "silent normalization". Those lines come from the test's
  own OCR call at the variant's capture DPI while `AnalyzeDocument` always
  recognises its own 200 DPI raster, so for the 150/300 DPI variants it compared
  two different recognitions. In the correction-2 run **three** labels differed
  per 150/300 DPI variant (`Straße und Hausnummner`, `TT.MM.JJ`,
  `D Einverständnis erteilt`); in the correction-3 run **two** differ per
  variant (the checkbox label now comes from the merged line), and both are
  **content** differences caused by that second raster — not whitespace, and not
  a product normalization. The check now applies only to 200 DPI captures and
  classifies the rest as not comparable (`nonVerbatimNotComparable: 2` in
  correction-3), never as a FAIL reason. Covered by a Python regression test that
  also pins the 200 DPI positive control (a relabelled 200 DPI suggestion must
  still raise the verbatim FAIL reason, so the guard cannot silently stop
  firing).
- *B7 (provenance).* The run below was executed at committed HEAD
  `3102557` (tree `22dbc94`) with a deliberately dirty tree containing only
  `apps/feldexa_app/android/gradlew.bat` (CRLF artifact, SHA-256
  `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62`) and the
  driver's pull-poller fix, which is committed in this correction. The run-time
  driver bytes are `tools/android/t263_drive_de_ocr.sh` (21675 B, SHA-256
  `4dc7833c3368f9c3214fe820a1fca4baa9297be3dcbb5a1551d413e754404c5c`); APK SHA-256
  `a8e460e2723da4159dd47d4998525063108d2dee2a47e8daad8d268e5f42c5f6`; the
  evidence directory holds 27 files (not 31) and `fixture-sha256.txt` now labels
  the fixture hash `fixture_pdf_sha256` instead of `ground_truth_sha256`.

**Before/after, all seven pre-declared variants (thresholds unchanged; before =
§5.8 at correction-2, after = this run).**

| Variant | CER before → after | Special recall before → after | Label acc. before → after | Result before → after |
| --- | --- | --- | --- | --- |
| `clean-200dpi` (reference) | 2.33 % → 2.33 % | 93.27 % → 93.27 % | 69.23 % → 76.92 % | FAIL → FAIL |
| `clean-150dpi` | 2.21 % → 2.21 % | 93.27 % → 93.27 % | 69.23 % → 76.92 % | FAIL → **PASS** |
| `clean-300dpi` | 2.27 % → 2.27 % | 92.31 % → 92.31 % | 69.23 % → 76.92 % | FAIL → **PASS** |
| `scan-150dpi-low-contrast` | 2.21 % → 2.21 % | 96.15 % → 96.15 % | 84.62 % → 92.31 % | PASS → PASS |
| `scan-200dpi-shadow` | 2.63 % → 2.63 % | 92.31 % → 92.31 % | 84.62 % → 92.31 % | PASS → PASS |
| `scan-200dpi-skew-3deg` | 43.51 % (upright annotation, non-comparable) | 62.50 % (same) | 0.00 % → 100 % (1/1) | FAIL → **PASS frame-correct** (51/51, CER 2.33 %; §5.9) |
| `scan-200dpi-jpeg-q35` | 2.27 % → 2.27 % | 93.27 % → 93.27 % | 84.62 % → 92.31 % | PASS → PASS |

`clean-150dpi` and `clean-300dpi` now pass because their only FAIL reason was the
invalid verbatim comparison (B4); their own thresholds were met before and after
(2.21 %/2.27 % against 8 %/5 % CER, 93.27 %/92.31 % against 80 %/90 % special
recall). They still record 5 and 6 critical lines that are not exact, which the
`EMULATOR` class does not gate for those variants; the reference variant is the
one that requires them.

**Field metrics and denominators (no broad semantic claim).** On the reference
variant: 13 ground-truth fields, 13 matched, precision 17.81 %
(13 / 73 suggestions across both pages, and page 1 of the fixture prints no
fields at all), recall 100 %, type accuracy 23.08 % (3/13), label accuracy
76.92 % (10/13), 1 unresolved label. The skew variant's `type accuracy 100 %`
is **1/1 matched field** with field precision 0.37 % and recall 7.69 % (1/13):
it is not evidence of a broad semantic improvement.

**Remaining FAILs.**

- `clean-200dpi` (reference): CER 2.33 % > 2.00 %, special recall 93.27 % <
  100 %, 5 critical lines not exact, label accuracy 76.92 % < 100 %. The
  character losses are bundled-ML-Kit model limits (`ß`/`ẞ`→`B`, `m³`→`m²`,
  `§`→`S`, ASCII-folded punctuation); fixing them needs a different engine or
  forbidden character substitution.
- `scan-200dpi-skew-3deg`: **frame-correct PASS** (correction-4). The scorer now
  rotates the annotation into the input-raster frame for exactly the variant that
  records a known skew injection (`raster.degradations: ["skew-3deg"]`, with
  `evidence.skewDegrees` honoured when present), using the same mapping as
  `make_variants.skew`. Re-scoring this same c3 run file that way gives
  **51/51 associated lines, CER 2.33 %, special-character recall 92.31 %, PASS** —
  identical to the reference capture, which is what a correct deskew plus a
  correct map-back must produce. The upright-annotation score of the same run
  (CER 43.51 %, 30/51 associations) is kept only as the explicitly
  **non-comparable** measurement. The transform is not a free pass: the Python
  regression test shows that no transform, the wrong sign and a doubled angle all
  lose association. Field-level semantics of this variant remain unreliable
  (precision 0.74 %, recall 15.38 %) because field matching uses axis-aligned IoU
  across two frames — a property of the metric, not of the reading.

**Correction-3 artifacts (this run).**

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c3/t263-report.md` | 12623 | `89dac4b69e7712d46973469ccc8ee5edb7c66e8b610cf33e3ee12e8adc4237a0` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c3/t263-report.json` | 113927 | `557e9155c9a76667d367506fe601e50d83117099bfcc8c0fb4831f9b7bc39300` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c3/t263-run-emulator.json` | 175100 | `d2524d1c7736fd9d33f90bff1f62688514f04108158e9c71077ae9855e3d00a2` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c3/t263-run-injected.json` | 340591 | `44b9c043e30ff4898f5f34c706f5139ff991e62829bd7a978c54936b51c579d9` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c3/metrics-emulator.log` | 715 | `39892a0723814ece4aa8806e4edafefd02839880e8d1879860f3f0fec63b2214` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c3/marker-sequence.txt` | 427 | `b7fcf8569dd7639d64af7724dc7caee446e3c2d9ddbdc1584f4f9fcc6e269628` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c3/device-identity.txt` | 298 | `265c299fe643739f0c63d2fc73f638d221a7aa9322b021641ab53bc0fedbbf56` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c3/git-identity.txt` | 511 | `4554517f936e812199d77297b1b448c93219879157100c1ceea68b59fced091a` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c3/apk-sha256.txt` | 183 | `3eac809d8cb7e0fcd117abf48a4db27d573cfa76a7a569d4855fdb9cbc2824dd` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c3/fixture-sha256.txt` | 541 | `ccafa20140f8d65b59d9211cdac94dd7fe9797df72b9741f19fdb591887bfcf3` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c3/orca-emulator-devices.json` | 1898 | `63957772a64a08729e50223ad4c2becc9af92f01c728a62c1f8d8adaa6b68398` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c3/orca-emulator-sessions.json` | 484 | `394a10428f8261ce3767e08f158587d67cc26fb5988d1e77b77171ce69b65b16` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c3/host-jvm-mapback-red.log` | 21983 | `66bd23960b2a5f886d7fd5055180ffba43c463bb762a3f734ca51ecb443436e4` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c3/host-jvm-mapback-green.log` | 17692 | `e1e936354782787717abcda000a11e45dc36d217fc66b27e899c7fa002e0b62d` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c3/host-dart-label-direction-red.log` | 7229 | `c78cf04b2f81d62e03ddee361ee684e88e32dadf14f9914c37dacaca1a6c88b1` |
| `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator-c3/host-dart-label-direction-green.log` | 5875 | `4ec0c71009b98c6a444a76008233be3998c8f79ed09ab503c60b92090ff70037` |

## 6. Performance

No performance claim.

## 7. Limitations

- One executed run per variant (single pass, no repeats, no warm-up study), so
  the numbers are one observation each, not a distribution; the class cannot
  prove physical-device behaviour, silicon-specific timing, or the SC-004
  three-second claim.
- Variant classes are not interchangeable: the three `clean-*` variants exercise
  the production raster port (PDFium) and are `EMULATOR`; the four degraded
  variants feed host-built `gray8` rasters into the same production OCR and
  analysis ports and are `EMULATOR_INJECTED_RASTER`, never clean
  production-path evidence.
- `clean-150dpi`/`clean-300dpi` qualify the DPI effect on **raw text only**:
  `AnalyzeDocument` always analyses its own fixed 200 DPI raster.
- `scan-200dpi-skew-3deg` is a declared degradation, not a product failure. Its
  **pre-fix** CER 48.48 % (commit `40a4260`, no deskew stage) is superseded: the
  frame-correct score of the correction-3 run is 51/51 associated lines at
  CER 2.33 % with special-character recall 92.31 % — identical to the reference
  capture (§5.9). The upright-annotation score of that same run (43.51 %) is
  reported only as the explicitly non-comparable measurement.
- The semantic label/type weakness in §5.4 **was** addressed here: the
  `type_inference.dart` label-association fix (same-row label, documented
  `ocr_alignment_right` direction) landed and lifted label accuracy from 0.00 %
  to 76.92 % on the reference variant (§5.9). The residual weakness is different
  and remains open: reference field precision is 17.81 % (13/73 suggestions) and
  type accuracy 23.08 % (3/13) because the fixture's character page yields many
  candidates and the closed keyword lexicon has no entry for some labels
  (`Größe`, `Gebühr`). That inventory/lexicon work belongs to issue #264; T263
  qualifies, it does not redesign detection.
- §5.1–§5.6 are the pre-fix baseline run at commit `40a4260`. Current status is
  §5.8 (correction-2) and §5.9 (correction-3); §5.9 supersedes everything
  before it. Host JVM and Dart RED/GREEN logs are in `2026-11-22-t263-evidence.md`
  and in the correction evidence directories.
- Not run here: `DEVICE` acceptance, TalkBack/accessibility, browser
  (`flutter test --platform chrome`) suites, character-faithful PDF export (no
  field-to-PDF renderer exists yet), and any `corpus-1.0.0` /
  `metric-definition.v1` claim (blocked on T033/T034/T059/T060/T142).
- Absolutely no claim is made about the physical handset that was attached to
  the host during the run; it was never addressed.
- Two independent reviews of the final candidate are pending and are not part of
  this report.

## 8. Artifacts

Every row is repository-relative, with byte size and SHA-256 at the reported
revision. This report's own row is omitted by design (self-reference rule); its
bytes and SHA-256 live in the external attestation. Trailing whitespace only was
stripped from `device-identity.txt` and `integration-android-t263.log` in the
follow-up hygiene commit, so the byte sizes and SHA-256 values below are the
post-hygiene values; no measured value, verdict, variant result, label-takeover
evidence, or device identity changed.

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Driver marker sequence | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/marker-sequence.txt` | 427 | `683f3a8bc9e525669219e618ef276d07a8bbb194f1b845e334a06bf46b3d3cfa` |
| Integration test log (content-free markers) | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/integration-android-t263.log` | 3009 | `673bfbae661d968b0f67be2dccf608f5abe63ef983a1ec4bd4004f84d2de6ff0` |
| Device identity | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/device-identity.txt` | 298 | `265c299fe643739f0c63d2fc73f638d221a7aa9322b021641ab53bc0fedbbf56` |
| APK SHA-256 | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/apk-sha256.txt` | 183 | `6af70a090a6458f16d976b1f7435d27954d72cea9127f20ffad2d6c17935ef53` |
| Fixture and ground-truth SHA-256 | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/fixture-sha256.txt` | 542 | `7a869b854d8cd816339a0f9e84a41202c17b7ded810f5689dd4960f87dfda96d` |
| Git identity of the run | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/git-identity.txt` | 573 | `67170fc74edc9844405a4f01fe71554820f54ca432bb7f76e52f54567135d859` |
| Orca device inventory | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/orca-emulator-devices.json` | 1898 | `34d517ef37580015cac10d6d20e9c961a8eecfce41c01de8600169a9ce51f3c2` |
| Orca emulator session | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/orca-emulator-sessions.json` | 484 | `514fcc2f0b4addb0736fa7da31c0750289ae33512656012ab791771d7dea8540` |
| Variant manifest | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/t263-variants.json` | 3144 | `19b351b43f2cb33c1cc91d14fa5473f105662097bebe8f059239faf70078440c` |
| EMULATOR run file | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/t263-run-emulator.json` | 173125 | `1ee7648fcb28c30a3cd40b56fcb68781c6b9d83bbb419b808257a385748d7ff0` |
| EMULATOR_INJECTED_RASTER run file | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/t263-run-injected.json` | 336096 | `4cab7b85d7dde49e611c2ef1a08bc999886c24031a795a1a1799895912177140` |
| Scorer report (JSON) | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/t263-report.json` | 114369 | `e9effee9147b7567bfda1fe4129105de41f8510bf8c60d7d13abee9daafbd640` |
| Scorer report (Markdown) | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/t263-report.md` | 11953 | `4276aad529cbbed0d8ce29a800de43c35e1183cc8cf2d5411fc698ccbb2de770` |
| Scorer console log | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/metrics-emulator.log` | 715 | `907f46ab3adfe4fc5f87b28ceb0a372aba15618c73058c4bbd55aad7458c99c1` |
| Text-layer control run | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/t263-text-layer-run.json` | 13325 | `49691f09e7f432e88f218a017d91a20277a46d87dc249b2e0e14337d584676e9` |
| Text-layer control report | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/t263-text-layer-report.json` | 4620 | `8ec5ac2acf2a54e2bf2904c9ba82bf24cb0a915a1a9545e943251a6e7f605e2d` |
| Text-layer control console log | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/metrics-text-layer.log` | 591 | `a2583be58502af72584e0afc05be95f1626104dca511fe1f904320d5b23e1cfc` |
| Generator check log | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/host-generate-check.log` | 134 | `dfd059599c8a93aec3b01de0af34e632f43391882593863d6a057470b3af7b0b` |
| Suite verification log | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/host-suite-verify.log` | 226 | `b25939279a28f58c7d2a541bcff8461e99a5de4e75d9a29e80ca514d6a910146` |
| Privacy log check | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/privacy-log-check.txt` | 74 | `daba805507b9e32ec490084c17e86af3dbd25754b09eacd32b72e326ba9e9132` |
| Privacy source check | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/privacy-source-check.txt` | 76 | `ca1d33e83fe69020e1888df08302f88f23fa745ac3cdbc63c127cc2ab6731dac` |
| Executed command list | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/commands.txt` | 679 | `94f840d57aecb6a3df11dff879b36407daa8b8e4f4be73e4e92fda471bde5606` |
| Logcat marker dump | `specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator/logcat-t263-markers.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |

## 9. Reproducibility

1. Start from base commit `2a1452b378660940d70f99f0ead88da6a933da28` with the
   T263 candidate commit from the external attestation checked out, and the
   Orca-visible emulator `emulator-5554` (AVD `T025_Pixel7_API35_KVM_20261115`)
   booted and attached to this worktree.
2. Host prerequisites: Flutter `3.47.7`, Android SDK with `adb`, Poppler
   `pdftoppm`, ImageMagick `magick`, Python 3.14, and the shared host compute
   permit.
3. `python3 compute_slot.py --wait -- tools/android/t263_drive_de_ocr.sh`
   from the repository root with `T263_SERIAL=emulator-5554`,
   `T263_AVD=T025_Pixel7_API35_KVM_20261115`, and
   `T263_EVIDENCE_DIR=specs/001-scanned-form-workflow/reports/artifacts/2026-11-22-t263-emulator`
   — expected: generator check and suite verification PASS, all seven variants
   executed, run files pulled, scorer verdict `FAIL` for the reference variant.
4. The driver removes its staging directory and the app output directory, stops
   the app, and never touches a second attached device. The evidence directory
   is refused if non-empty unless `T263_REPLACE_EVIDENCE=1` (which backs up
   first).

## 10. External attestation

The candidate commit, the final HEAD and tree, and this report's byte size and
SHA-256 are recorded in the coordinator-held `worker_done` transport attestation
for this dispatch. There is no `t263-attestation` ref: the task forbids pushing,
so no remote attestation ref exists, and this report deliberately contains no
self-referential hash.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
|  |  |  |  |
