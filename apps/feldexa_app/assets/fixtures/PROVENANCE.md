# Fixture provenance and rights record (T009)

- **Catalog version**: `fixtures-1.1.0` (adds `sf-005` in T263; `fixtures-1.0.0` fixture bytes and SHA-256 pins are unchanged)
- **Generator**: `tools/corpus/synthetic/generate.dart` version `1.0.0`, seed `0`
- **Generation date**: 2026-11-12 (fixed for byte reproducibility)
- **Evidence class**: `SIMULATED` development input only
- **Repository**: `xxammaxx/Feldexa_2.0`
- **AcroForm reference fixture**: `sf-acroform-001.pdf` (1424 bytes, SHA-256 `7f4e0144…2af9a`) is registered in `catalog-acroform.json` in this directory, deliberately not in `catalog.json`; that register carries its rights, personal-data, and determinism record (issue #344 part B, FR-069).

## Rights statement

| Item | Value |
| --- | --- |
| Content origin | Fictional forms authored in `tools/corpus/synthetic/fixtures.dart` and rendered by the repository's own PDF writer. |
| Third-party content | None. No scanned form, photograph, logo, map, or illustration is included. |
| Third-party font outlines | `sf-001`…`sf-004`, `sf-protected`, `sf-truncated`, and `sf-not-a-pdf` reference the base-14 Helvetica family by name; no TTF is embedded. `sf-005` embeds the project-bundled **Noto Sans Regular** (`apps/feldexa_app/assets/fonts/NotoSans-Regular.ttf`, SHA-256 `97eaf07030b89da4eceace86b12f4d7debb3cb212082c3938803eac7111221c9`) verbatim as a Type0/CIDFontType2 font, which is covered by SIL OFL 1.1 and by `apps/feldexa_app/assets/fonts/PROVENANCE.md`. |
| Personal data | None. All field values are blank; names, authorities, and addresses are invented (`Musterstadt`, `Musteramt für Bürgerdienste`). |
| Rights status | Project-generated synthetic content; cleared for repository and product development use. No reliance on § 5 UrhG or any real authority's form licence. |
| Visible marker | Every page carries `SYNTHETISCHES TESTDOKUMENT – kein amtliches Formular` and a footer with `keine personenbezogenen Daten`. |
| Legal basis recorded in catalog | `synthetic; project-generated fictional content, no third-party work.` |

No real German authority form is mimicked closely enough to create a rights or
misrepresentation concern; the layouts are generic and the authority is
fictional. The real rights-cleared corpus required by FR-086/SC-001 is a
separate artifact (`corpus-1.0.0`, task T033) and is not replaced by these
fixtures.

## German OCR reference fixture (`sf-005`, T263)

`sf-005.pdf` is the additive German OCR special-character reference used by the
T263 Unicode/Label regression suite (issue #263).

| Item | Value |
| --- | --- |
| Purpose | Qualify Ä Ö Ü ä ö ü ß ẞ, €, m²/m³, punctuation, German authority terms, and fictional names on the real bundled ML Kit OCR path with per-line ground truth and separate raw-text and semantic metrics |
| Writer | `tools/corpus/de-ocr/ttf_embed.dart` (embedded TrueType, `Identity-H`, `ToUnicode` CMap) emitted by `tools/corpus/synthetic/generate.dart` |
| Font | Bundled Noto Sans Regular, embedded verbatim; the generator rejects any other SHA-256 and every printed code point is resolved through the font's own `cmap` (coverage proof) |
| Why not base-14 | `/WinAnsiEncoding` has no code point for U+1E9E (ẞ); the base-14 writer would have to print a substituted or missing glyph |
| Ground truth | `tools/corpus/de-ocr/reference-de.ground-truth.json` (generated from the same declaration): per printed line the verbatim NFC text, NFD spelling, display-space rectangle, role, and special-character inventory, plus the declared label/field roles |
| Expected OCR | `sf-005.expected-ocr.json` — declared SIMULATED expectations only, not ML Kit output |
| Changed existing pins | None. `sf-001` remains `22c939cc…`, `sf-004` remains `009c3bab…`; only the catalogue version and the new entries changed |

## Protected fixture disclosure

`sf-protected.pdf` is a genuine PDF Standard Security Handler file, revision 2
(40-bit RC4), generated for import-rejection testing only:

| Item | Value |
| --- | --- |
| User password | `feldexa-user` (non-empty; empty and wrong passwords are rejected) |
| Owner password | `feldexa-owner` |
| Handler | `/Filter /Standard /V 1 /R 2 /Length 40`, `/P -44` |
| Purpose | Prove `IMP-001` rejection without a password prompt and without creating a document |
| Independent check | `tools/corpus/synthetic/verify_protected_fixture.sh` uses Poppler to prove empty/wrong rejection and user/owner success |
| Product use | None. Legacy RC4 is fixture-only and never used for product storage or transport. |

## Determinism record

The generator is deterministic by construction:

- no `Random`, wall clock, locale-dependent formatting, filesystem order, or
  network access;
- fixed object ordering, fixed `/ID`
  `FELDEXAFIXTURE01`, fixed generation date, no `/CreationDate`, `/ModDate`,
  `/Producer`, or `/Creator`;
- declared layout is the single source for PDF drawing, expected OCR, and
  ground-truth rectangles;
- `dart run tools/corpus/synthetic/generate.dart --check` regenerates in memory
  and fails on any byte drift or missing file;
- `apps/feldexa_app/test/synthetic_fixtures_test.dart` independently hashes
  every PDF and compares the canonical `assets/fixtures/` file with the
  `web/fixtures/` delivery mirror and the `tools/corpus/synthetic/` copy.
- Fixtures are not pubspec assets. The canonical directory is undeclared; the
  Web mirror is served from `web/`; Android receives test files only through
  `adb push`, never through an APK.

## Change policy

Any change to a fixture, its expected OCR, its ground truth, or the catalog
requires:

1. a deliberate generator change (not a hand edit of generated files);
2. a catalog version bump and regenerated SHA-256 pins;
3. a fresh run of `--check` and the fixture-integrity test;
4. an explicit review note in the task evidence report.

Generated files must never be patched in place. The catalog is the source of
truth for hashes and page geometry.
