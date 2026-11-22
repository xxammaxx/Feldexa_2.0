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

The correction-1 label/type-association fix for this task is host-verified only
(§5.7); its post-fix emulator rerun is `NOT_RUN` and §5 stays the pre-fix run.

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

### 5.7 T263 correction-1 — defect fix status (host-verified only)

The label/type defect in §5.4 has a proven root cause and a verified fix. The
on-device rerun for this correction is **NOT_RUN**.

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
- **Rerun status.** The seven variants were **not** re-executed for this
  correction. The driver's mandatory Orca allocation gate
  (`orca emulator devices --json`) stopped answering (`runtime_timeout`, then no
  response at all), and the driver aborted before issuing any device command
  (its log records `orca emulator devices --json failed; no Orca allocation
  evidence`). The numbers in §5 are therefore still the pre-fix run at commit
  `40a4260`; they are not superseded and must not be read as post-fix results.
  No `DEVICE` or performance claim is affected.
- **Special characters remain unfixed.** `ß`/`ẞ`→`B`, `m³`→`m²`, `§`→`S` and the
  ASCII-folded punctuation are limitations of the bundled ML Kit Latin model.
  Removing them would require a different engine or character-substitution
  post-processing, and both are forbidden by this correction's rules, so those
  cases stay `FAIL` as measured.
- **Skew remains unfixed.** `scan-200dpi-skew-3deg` still fails because the
  pipeline has no deskew stage: a tilted raster reaches the recognizer as-is, and
  the resulting line boxes are too tall and too far from the annotated rows to be
  associated (30/51). A deskew implementation was drafted but reverted
  unverified — its host JVM test gate could not be executed — so no unverified
  production change was shipped.

### 5.8 T263 correction-2 — deskew stage, post-fix run (Orca runtime ready)

Correction-2 adds a verified deskew preprocessing stage and re-measures all
seven pre-declared variants at the new candidate. **Orca visibility: observed.**
The driver's Orca allocation gate passed (`orca emulator devices --json` →
`ok: true`, one `emulator-5554` entry, `T025_Pixel7_API35_KVM_20261115`, API 35,
state `booted`; session attached to this worktree). The run is
`2026-11-22-t263-emulator-c2`; the pre-fix `2026-11-22-t263-emulator/` evidence is
unchanged.

**Skew root cause and fix.** The pipeline had no deskew stage, so the injected
3° raster reached the recognizer tilted: lines merged or were dropped (30/51
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
- `scan-200dpi-skew-3deg` is a declared degradation, not a product failure; its
  CER 48.48 % is recorded, not treated as a regression gate.
- The semantic label/type weakness in §5.4 is a measured product observation. It
  was **not** fixed here (no production change): T263 qualifies, it does not
  repair `AnalyzeDocument`, and issue #264 owns the inventory/adaptive work.
- §5.1–§5.6 are the pre-fix run at commit `40a4260`; §5.8 is the correction-2
  run at the correction candidate and supersedes them for current status. The
  correction-1 label/type fix and the correction-2 deskew stage are both
  measured on device in §5.8; the host JVM and Dart RED/GREEN logs are in
  `2026-11-22-t263-evidence.md` and §5.8.
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
