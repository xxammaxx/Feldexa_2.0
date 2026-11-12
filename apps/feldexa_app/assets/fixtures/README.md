# Synthetic development fixtures (`SIMULATED`)

These files are the deterministic, fictional documents used by the Web
development surface (Spec Kit task T009 / issue #9; user story US9; FR-086).
They let the editor, review tools, filling, persistence, and export preview run
in a local browser without an Android device.

**They are deliberately not Flutter assets.** Pubspec `assets` entries are
packaged into every Android build, including release. Instead:

| Location | Role |
| --- | --- |
| `apps/feldexa_app/assets/fixtures/` | Canonical generated dev files. Not declared in `pubspec.yaml`, so Android packaging never sees them. |
| `apps/feldexa_app/web/fixtures/` | Byte-identical Web delivery mirror. The Flutter Web dev server and `flutter build web` serve it at `/fixtures/...`. |
| `tools/corpus/synthetic/sf-*.pdf` | Byte-identical PDF copies for the Android test workflow (`adb push`). |

The Web loader contract is `GET /fixtures/<file>` relative to the app origin;
the catalog is `GET /fixtures/catalog.json`. No fixture bytes are requested
from, or packaged into, a production Android build.

They are **not** an acceptance corpus and **not** evidence about Android
runtime behavior. Browser results must be labelled `SIMULATED` and reported
separately from `EMULATOR`/`DEVICE` results (FR-087, FR-088). The authoritative
real-form corpus is `corpus-1.0.0` under `tools/corpus/` (task T033), not this
directory.

## Contents

| Fixture | Role | Pages | Purpose |
| --- | --- | ---: | --- |
| `sf-001.pdf` | editor | 2 | Municipal application with underlined fields, date mask, checkbox group, fee table, multiline reason, signature lines. |
| `sf-002.pdf` | navigation | 5 | Five-page information sheet; page-strip navigation and one different field per page. |
| `sf-003.pdf` | geometry | 5 | A4 portrait/landscape, `/Rotate` 90/180, and A5 `/Rotate` 270 with corner fields and a centered checkbox. |
| `sf-004.pdf` | fields | 1 | All six field types, German special characters, narrow overflow field, multiline area. |
| `sf-protected.pdf` | import failure | 1 | Genuine RC4 40-bit PDF with non-empty user password `feldexa-user` for `IMP-001`; empty/wrong passwords are rejected. |
| `sf-truncated.pdf` | import failure | – | Deterministic 60 % prefix of `sf-001.pdf` for `IMP-002`. |
| `sf-not-a-pdf.pdf` | import failure | – | UTF-8 text with a `.pdf` name for `IMP-004`. |

`catalog.json` is the machine-readable index; each `<id>.expected-ocr.json`
contains the deterministic OCR blocks the simulated OCR adapter returns for
that fixture.

The canonical directory is the source of truth; every generated file is
mirrored byte-for-byte to `web/fixtures/`, and the PDFs are also written to
`tools/corpus/synthetic/` for the Android `adb push` workflow in
`quickstart.md` §2/§4. The integrity test requires all three copies to match.

## Catalog schema

`catalog.json` (`schemaVersion: 1`, `catalogVersion: fixtures-1.0.0`):

| Field | Meaning |
| --- | --- |
| `evidenceClass` | Always `simulated`. |
| `rights` | Synthetic rights statement: no third-party content, no personal data. |
| `generator` | Generator path, version, seed `0`, `deterministic: true`, check command. |
| `fixtures[].id` | Stable fixture ID; matches the file name. |
| `fixtures[].role` | `editor`, `navigation`, `geometry`, `fields`, or `import-failure`. |
| `fixtures[].status` | `valid`, `encrypted`, `truncated`, or `not-a-pdf`. |
| `fixtures[].sha256`, `sizeBytes` | Integrity pins for the exact PDF bytes. |
| `fixtures[].pages` | Display-space `widthPt`, `heightPt`, and `rotation` per page. |
| `fixtures[].groundTruth.fields` | Blank input regions: stable `id`, `type`, `pageIndex`, `rect` (`xPt`/`yPt`/`widthPt`/`heightPt`), `label`, `required`. |
| `fixtures[].expectedOcr` | Reference to the expected-OCR file, page count, and block count. |
| `fixtures[].expectedError` | German catalog code for the failure fixtures (`IMP-001`, `IMP-002`, `IMP-004`), otherwise `null`. |
| `fixtures[].provenance` | Source, generation date, legal basis, rights-cleared flag, personal-data flag. |
| `fixtures[].synthetic` | Generator path and seed. |

The ground-truth field shape intentionally matches
`tools/corpus/manifest.schema.json` `$defs/field` (display-space points), so the
same scorer can consume synthetic and real forms later.

## Expected OCR schema

Each `<id>.expected-ocr.json`:

```json
{
  "schemaVersion": 1,
  "fixtureId": "sf-001",
  "language": "de",
  "evidenceClass": "simulated",
  "generatorVersion": "1.0.0",
  "pages": [
    {
      "pageIndex": 0,
      "widthPt": 595.28,
      "heightPt": 841.89,
      "rotation": 0,
      "blocks": [
        {
          "rect": { "x": 56.7, "y": 148, "width": 62.4, "height": 12 },
          "text": "Familienname",
          "confidence": 0.97,
          "lines": [
            {
              "rect": { "x": 56.7, "y": 148, "width": 62.4, "height": 12 },
              "text": "Familienname",
              "confidence": 0.97
            }
          ]
        }
      ]
    }
  ]
}
```

`rect` values are page display points (top-left origin, y down), matching
`contracts/coordinates-and-geometry.md`. Blocks are sorted by rounded
`(top, left, text)`. The OCR text is pre-authored from the same layout
declarations as the PDF, so UI tests do not depend on live ML Kit variance;
live recognition is exercised separately in unit tests and on Android.

## Rights and provenance

See [`PROVENANCE.md`](PROVENANCE.md). In short: every name, authority, address,
form text, and layout is fictional and generated by this repository. There is
no scanned real form, no third-party artwork, no embedded third-party font
(base-14 Helvetica is referenced by name), and no personal data.

## Regenerate and verify

From the repository root, with a writable Dart/Flutter toolchain:

```bash
dart run tools/corpus/synthetic/generate.dart          # write all 31 files
dart run tools/corpus/synthetic/generate.dart --check  # fail on any byte drift
flutter test apps/feldexa_app/test/synthetic_fixtures_test.dart
```

The generator has no randomness, wall-clock, locale, or network input. It uses
fixed object order, a fixed document ID, and a fixed generation date, so a
second run is byte-identical. The integrity test proves the canonical files,
the `web/fixtures/` mirror, and the `tools/corpus/synthetic/` PDF copies are
byte-identical, and that `pubspec.yaml` declares no fixture assets. The
browser runtime test fetches the Web mirror over HTTP and re-verifies every
hash and page marker in Chrome (`tools/corpus/synthetic/test_web_fixtures.sh`).

## Limits

- These are development inputs, not a frozen evaluation corpus. Changing any
  generated byte requires regenerating the catalog and hash pins.
- Expected OCR is authored, not produced by the Android ML Kit engine.
- The PDFs use base-14 Helvetica; they do not exercise the bundled Noto Sans
  export path (T006/T007/T103 own that).
- No partially damaged multi-page page-render fixture is generated here;
  page-failure behavior belongs to the import/preflight tasks (T039/T046).
- T009 adds one browser runtime check of fixture delivery (hash/geometry/OCR
  fetch determinism). It does not add the editor journey tests; T047/T062/
  T072/T087/T128 own those and must label their evidence `SIMULATED`.
- The Web loader (`T011`/`T028`) must fetch `/fixtures/...`; fixtures are not
  reachable through `rootBundle` by design.
