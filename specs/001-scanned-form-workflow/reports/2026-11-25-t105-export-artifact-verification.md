# T105 — external verification of one exported artifact

**Date**: 2026-11-25 (Europe/Berlin)
**Branch**: `xxammaxx/export-evidence`, base `origin/main` = `323d89c`
**Device**: emulator only — `emulator-5554` (AVD `T025_Pixel7_API35_KVM_20261115`,
API 35, x86_64). No physical device was addressed, `adb kill-server` was never
run, and the emulator was not restarted.
**Scope**: E2 of the release brief
(`reports/release/TASK-BRIEF-export-evidence.md`). No product code changed; the
only tracked change besides this note is
`apps/feldexa_app/e2e/export_journey.yaml`.

Everything below distinguishes **belegt** (proven by a command run here) from
**nicht belegt** (not proven). Nothing that was not measured is claimed.

## 0. Tool inventory (checked before building anything)

| Tool | Status |
| --- | --- |
| `tools/pdf_verify/` | contains only `.gitkeep` — **nothing to reuse**, no harness existed |
| `tools/corpus/verify.sh` | verifies corpus checksums/manifests only, not exported PDFs |
| `pdftotext`, `pdftoppm`, `pdfinfo` (Poppler) | present |
| `qpdf`, PyMuPDF (`fitz`), `pdfminer`, `pikepdf`, `PyPDF2` | **absent** |
| ImageMagick `compare` / `magick` | present |

Consequence: page count, page size, text, and AcroForm presence were verified
with Poppler; the render comparison with `pdftoppm` + ImageMagick. No new
verification tool was written.

## 1. How the artifact was captured

The app deletes the artifact when the preview is left
(`contracts/editor-interactions.md` §10 point 6, `ExportArtifactStore`), so the
file was read **while the preview was open**. The committed flow
`apps/feldexa_app/e2e/export_journey.yaml` was copied to a throwaway variant
with the `- tapOn: "Schließen"` command after `05-export-preview` replaced by a
long `extendedWaitUntil`. That variant is **not** committed; the committed flow
is unchanged in this respect.

```bash
export PATH="$HOME/Android/Sdk/platform-tools:$HOME/.local/bin:$PATH"

# capture variant: same flow, but it holds while the preview is open
maestro --device emulator-5554 test /tmp/e2e/capture.yaml
#   ... Assert that "Vorschau der erzeugten PDF-Datei" is visible... COMPLETED
#   ... Assert that "Seiten: 2" is visible... COMPLETED
#   ... Assert that "HOLD-FOR-ARTIFACT-CAPTURE" is visible... (still running)

adb -s emulator-5554 shell run-as de.feldexa.app ls -l cache/feldexa_exports
# total 12
# -rw------- 1 u0_a213 u0_a213_cache 7265 2026-11-25 19:14 \
#   eed3bbeb-c9f8-448a-9074-52ed48fbea76.pdf

adb -s emulator-5554 exec-out run-as de.feldexa.app cat \
  cache/feldexa_exports/eed3bbeb-c9f8-448a-9074-52ed48fbea76.pdf \
  > /tmp/e2e/artifacts/eed3bbeb-c9f8-448a-9074-52ed48fbea76.pdf
```

`exec-out` (not `shell cat`) was used so no CR/LF translation touches the
binary. After the copy the run was terminated with `kill`; the app process was
not restarted, no state was cleared.

Artifact: **7265 bytes**,
`sha256 e644ddebcd9fcb49e425c90e60b0977329c4d008082a8c156114b88be81e9678`,
`md5 36a4df0c0a58f1c46feb3e43e6454bbe`, id
`eed3bbeb-c9f8-448a-9074-52ed48fbea76`.

Source: `tools/corpus/synthetic/sf-001.pdf`, **5956 bytes**,
`sha256 22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038`
— the identical bytes are on the device
(`adb -s emulator-5554 exec-out cat /sdcard/Download/sf-001.pdf | sha256sum`
returns the same hash), so the exported document is the fixture and nothing
else.

Files kept as evidence in `reports/artifacts/2026-11-25-t105-export-artifact/`:
`artifact.pdf`, `artifact.txt`, `source.txt`, `hashes.txt`,
`pdfinfo-artifact.txt`, `pdfinfo-source.txt`, `artifact-listing.txt`.
All content is from the synthetic fixture; no user content appears here.

## 2. Point 1 — page count and page size against the source: **belegt**

```bash
pdfinfo artifact.pdf; pdfinfo tools/corpus/synthetic/sf-001.pdf
```

| Property | source `sf-001.pdf` | artifact | equal |
| --- | --- | --- | --- |
| `Pages` | 2 | 2 | yes |
| `Page size` | 595.28 x 841.89 pts (A4) | 595.28 x 841.89 pts (A4) | yes |
| `Page rot` | 0 | 0 | yes |
| `PDF version` | 1.7 | 1.7 | yes |
| `Encrypted` | no | no | yes |
| `Creator` / `Producer` | (none) | Feldexa | intended |
| `Form` | none | none | yes (see point 3) |

The preview's own `Seiten: 2` assertion of the flow (`extendedWaitUntil`,
`05-export-preview`/`09-second-export-preview`) agrees with the external count.

## 3. Point 2 — text of the entered value and German umlauts: **teilweise belegt**

```bash
pdftotext -layout artifact.pdf artifact.txt
pdftotext -layout tools/corpus/synthetic/sf-001.pdf source.txt
diff source.txt artifact.txt      # no output -> identical
grep -c 'ü\|ä\|ö\|ß\|Ä\|Ö\|Ü' artifact.txt   # 11
grep -o '?' artifact.txt | wc -l              # 0
```

**belegt**: the extracted text of the artifact is *identical* to the extracted
text of the source. Umlauts survive the export pipeline unharmed:
`Musteramt für Bürgerdienste`, `Straße und Hausnummer`, `Gebühren`,
`Synthetisches Testdokument – kein amtliches Formular – keine
personenbezogenen Daten`. Not a single `?` replacement character occurs in the
extracted text, i.e. no glyph fell back to a substitution.

**nicht belegt**: *no entered value is present in this artifact*. The flow
confirms the first suggestion of the fixture (review action „Übernehmen“) and
that confirmed field is still empty at export time — see §7 for why filling it
was not possible here. Therefore the sub-claim „der eingegebene Wert steht im
Text“ has no object in this run and is **not** claimed.

## 4. Point 2b — original pages unchanged outside overlays: **belegt**

```bash
pdftoppm -r 150 -png tools/corpus/synthetic/sf-001.pdf render/src
pdftoppm -r 150 -png artifact.pdf render/art
compare -metric AE  render/src-1.png render/art-1.png null:   # 0 (0)
compare -metric RMSE render/src-1.png render/art-1.png null:  # 0 (0)
compare -metric AE  render/src-2.png render/art-2.png null:   # 0 (0)
compare -metric RMSE render/src-2.png render/art-2.png null:  # 0 (0)
```

The rendered pages are not merely close, they are byte-identical:

```
b279d225cb1b8e50ca8b9fe6ccc008f8a1294e39224aa0af129256130f1af26c  src-1.png == art-1.png
b9d6e23e15d9b69203419ff1a0f3694df33742bf27c053c1e7b633b57013c904  src-2.png == art-2.png
```

**Documented mask**: none was needed. The only confirmed field of this run is
empty, so the exporter draws no overlay on either page; the expectation is
therefore exact equality over the *entire* page, and exact equality is what the
measurement returns (AE = 0 differing pixels, RMSE = 0). A mask would only be
required for a run with a drawn overlay (see §6, open point).

## 5. Point 3 — no AcroForm fields remain: **belegt (weak-to-strong combination)**

```bash
pdfinfo artifact.pdf | grep Form      # Form:            none
grep -c AcroForm artifact.pdf         # 0
```

Two independent checks agree: Poppler reports `Form: none` for the artifact,
and the byte stream contains no `/AcroForm` key at all. Note the limit of this
evidence: **the source fixture itself carries no AcroForm** (`pdfinfo
sf-001.pdf` → `Form: none`), so this run proves that the artifact does not
*introduce* a form — it does **not** prove that an existing AcroForm is
flattened. `contracts/export-plan.md` §5 step 2a remains unproven by this run
(see §6).

## 6. Point 4 — placement tolerance 1 mm (2.835 pt): **nicht belegt**

No overlay text exists in this artifact (the confirmed field is empty, §3), so
there is no glyph whose position could be measured against the field
rectangle. A tolerance check without a drawn overlay would be a fabricated
number, so none is reported.

A second reason why no measurement was produced: the tool set has no PDF object
inspector (`qpdf` and PyMuPDF are absent, `tools/pdf_verify/` is an empty
placeholder), so the CTM/`Tm` values of the drawn text cannot be read directly.
A future run with a drawn overlay can close this gap in two ways — extract the
text position from `pdftotext -bbox` (Poppler, available) and compare the glyph
box against the plan rectangle, or the 150 dpi masked pixel comparison the
brief names.

## 7. Observation from the attempt to fill a field (not a verdict)

To satisfy the entered-value half of point 2, the value sheet was driven by
hand on `emulator-5554`: `Dokumentübersicht` → row `MUSTERSTADT` → value sheet →
`Müller` → `Jetzt speichern`. The sheet answered with `FLD-001` („Der Text ist
länger als das Feld…“) and stayed open; the sheet's own layout guard therefore
classifies the value as overflow. Replacing the text with a single character
(`M`) and saving again produced the same `FLD-001` answer.

Observed, and nothing more: the value sheet
(`FieldValueSheet` → `fieldTextOverflows`,
`apps/feldexa_app/lib/features/fill/field_text_fit.dart`) answered `FLD-001`
for `Müller` on the confirmed field `Feld MUSTERSTADT, Typ Text, Seite 1`. A
second attempt with the single character `M` left the sheet open with the same
`FLD-001` warning in the observed hierarchy, so the value stayed uncommitted
without overflow. The exact field rectangle was **not** measured (no PDF
object inspector, and the suggestion rect is not exposed in the UI), so this
report does not judge whether the rectangle is right for the fixture. Recorded
as an open point because it is what blocked the value-bearing leg of E2 with
this fixture and this selector path. A document exported with such a value
would additionally be blocked with `EXP-001` (`FieldOverflowWarning` is the
same gate the export validation uses).

Consequence for the flow: `apps/feldexa_app/e2e/export_journey.yaml` asserts
the *confirmed, empty* field state (`Feld MUSTERSTADT, Typ Text, Seite 1, leer,
bestätigt`) before and after the reopen, and does not fake a value. The
limitation is written into the flow header.

## 8. Open points (explicitly not closed)

1. **Entered value in the artifact** — no value was exported; see §3 and §7.
   Closing it needs a confirmed field whose rectangle holds text, i.e. a
   suggestion-selection step in the flow (the panel virtualises its rows, so
   the second text suggestion is not reachable by the currently used
   `Übernehmen` index selector without a scroll step).
2. **1 mm placement tolerance** — unmeasured, see §6.
3. **AcroForm flattening** — the fixture has no AcroForm, see §5.
4. **Second artifact after the reopen** — the flow exports twice and asserts
   the second preview (`Seiten: 2`), but the second artifact was not pulled out
   of the cache and hashed; only the first one is verified here.

## 9. Reproduce

```bash
export PATH="$HOME/Android/Sdk/platform-tools:$HOME/.local/bin:$PATH"
adb devices -l                       # emulator-5554 only

# committed flow, twice (both green on 2026-11-25, see the worker report)
maestro --device emulator-5554 test \
  apps/feldexa_app/e2e/export_journey.yaml

# artifact capture: copy the flow, replace the first `- tapOn: "Schließen"`
# after `05-export-preview` with
#   - extendedWaitUntil: {visible: "HOLD", timeout: 300000}
# then, while it holds:
adb -s emulator-5554 shell run-as de.feldexa.app ls -l cache/feldexa_exports
adb -s emulator-5554 exec-out run-as de.feldexa.app cat \
  cache/feldexa_exports/<id>.pdf > /tmp/<id>.pdf
```
