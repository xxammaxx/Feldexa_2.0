# Fixture provenance and rights record (T009)

- **Catalog version**: `fixtures-1.0.0`
- **Generator**: `tools/corpus/synthetic/generate.dart` version `1.0.0`, seed `0`
- **Generation date**: 2026-11-12 (fixed for byte reproducibility)
- **Evidence class**: `SIMULATED` development input only
- **Repository**: `xxammaxx/Feldexa_2.0`

## Rights statement

| Item | Value |
| --- | --- |
| Content origin | Fictional forms authored in `tools/corpus/synthetic/fixtures.dart` and rendered by the repository's own PDF writer. |
| Third-party content | None. No scanned form, photograph, logo, map, or illustration is included. |
| Third-party font outlines | None. The PDFs reference the base-14 Helvetica family by name; no TTF is embedded. The separately bundled Noto Sans assets are covered by `apps/feldexa_app/assets/fonts/PROVENANCE.md`. |
| Personal data | None. All field values are blank; names, authorities, and addresses are invented (`Musterstadt`, `Musteramt für Bürgerdienste`). |
| Rights status | Project-generated synthetic content; cleared for repository and product development use. No reliance on § 5 UrhG or any real authority's form licence. |
| Visible marker | Every page carries `SYNTHETISCHES TESTDOKUMENT – kein amtliches Formular` and a footer with `keine personenbezogenen Daten`. |
| Legal basis recorded in catalog | `synthetic; project-generated fictional content, no third-party work.` |

No real German authority form is mimicked closely enough to create a rights or
misrepresentation concern; the layouts are generic and the authority is
fictional. The real rights-cleared corpus required by FR-086/SC-001 is a
separate artifact (`corpus-1.0.0`, task T033) and is not replaced by these
fixtures.

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
