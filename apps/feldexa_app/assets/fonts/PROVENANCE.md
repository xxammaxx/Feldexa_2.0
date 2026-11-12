# Noto Sans font bundle provenance (T006)

This directory is the single bundled text-font source for Feldexa 2.0. It is
consumed by `feldexa_export` for text layout and clipping detection
(FR-067/FR-068), by the plan's one-metrics decision (plan.md §Architecture
Decisions 6; research.md D-11), and by the export-plan contract's
`regularAsset`, `boldAsset`, and family `NotoSans`
(`specs/001-scanned-form-workflow/contracts/export-plan.md` §2).

## Pinned upstream release

| Item | Value |
| --- | --- |
| Upstream project | Noto Sans, `notofonts/latin-greek-cyrillic` |
| Release tag | `NotoSans-v2.013` |
| Release published (UTC) | 2023-09-30T10:47:34Z |
| Release URL | https://github.com/notofonts/latin-greek-cyrillic/releases/tag/NotoSans-v2.013 |
| Archive | `NotoSans-v2.013.zip` |
| Archive size | 124,008,613 bytes |
| Archive SHA-256 | `9fd595dd701d7ea103a9ba8a9cfdcf0c35c5574ef754fecabe718eadad8bccde` |
| Archive digest source | Computed locally from the downloaded release asset on 2026-11-12 (Europe/Berlin). The GitHub release asset has no published digest, so this is a local pin, not an upstream attestation. |
| Extracted from | `NotoSans/googlefonts/ttf/` and the archive-root `OFL.txt` |
| Retrieved | 2026-11-12 (Europe/Berlin) |

The archive contains both `googlefonts` and `full` trees, including variable
and OTF files. T006 deliberately bundles only the two **static TrueType**
Google Fonts files above, because PDFBox embeds TrueType outlines and the
metrics table is generated from these exact static bytes.

## Bundled files

| File | Bytes | SHA-256 | Role |
| --- | ---: | --- | --- |
| `NotoSans-Regular.ttf` | 790,500 | `97eaf07030b89da4eceace86b12f4d7debb3cb212082c3938803eac7111221c9` | Regular 400, export text and UI family |
| `NotoSans-Bold.ttf` | 802,504 | `53b53721b1910c7e058c4f012126b41273d493b04d69c1ac50924f7eff8e8039` | Bold 700 |
| `OFL.txt` | 4,396 | `cee9892f9f0cc8fe882c9e9537ee6a89621d86ee7ceaf70b02e2b2b1c25c061a` | Unmodified SIL OFL 1.1 licence |
| `metrics.json` | 129,971 | `d3306e4a08ffdf534f88a49a7b0f1a7f880b2513e39b791035b68a98340cadab` | T007 generated advance table (schema v1, `noto-sans-2.013-v1`) |

Observed metadata (verified by `tools/fonts/verify_fonts.py`): 4,671 glyphs
each, 17 tables, `unitsPerEm` 1000, ascender 1069, descender −293, cmap formats
4 and 12, `usWeightClass` 400/700, `usWidthClass` 5, `fsType` `0x0000`
(installable embedding), no `fvar` table, name version
`Version 2.013; ttfautohint (v1.8.4.7-5d5b)`.

## Licence

Copyright 2022 The Noto Project Authors
(https://github.com/notofonts/latin-greek-cyrillic). The fonts are licensed
under the **SIL Open Font License, Version 1.1**. The unmodified `OFL.txt` is
bundled here and declared as a Flutter asset so the later third-party licence
surface (T003 constraint C-T003-3) can expose the exact bundled text. This
release's OFL text declares no Reserved Font Name. The licence permits
bundling, embedding, and redistribution of the font software; it does not
permit selling the fonts by themselves. The licence UI and the complete
third-party notice surface remain later tasks.

## Reproduction and verification

```sh
# Re-download the pinned release, verify archive and per-file SHA-256, and
# replace the bundled files with byte-identical copies:
bash tools/fonts/fetch_noto_sans.sh

# Reuse an already-downloaded archive instead of downloading 124 MiB again:
NOTO_SANS_ZIP=/path/to/NotoSans-v2.013.zip bash tools/fonts/fetch_noto_sans.sh

# Static verification: pinned bytes, sfnt/table checksums, required tables,
# German glyph coverage and advances, OFL text, and the Flutter declaration:
python3 tools/fonts/verify_fonts.py

# T007: fail unless metrics.json is byte-for-byte current with these TTFs:
dart run tools/metrics/generate_font_metrics.dart --check

# T007: independent cross-check of the committed table against the TTF bytes:
(cd apps/feldexa_app && flutter test --no-pub test/font_metrics_bundle_test.dart)
```

The fetch script never resolves "latest"; it is hard-pinned to the release tag
and archive hash above. The verifier is dependency-free (Python standard
library only) and fails closed.

## Flutter registration

`apps/feldexa_app/pubspec.yaml` declares family `NotoSans` with weight 400
(`NotoSans-Regular.ttf`) and weight 700 (`NotoSans-Bold.ttf`) at the contract
paths, and declares `assets/fonts/OFL.txt` and the generated
`assets/fonts/metrics.json` as assets. The host-VM tests
`apps/feldexa_app/test/font_bundle_test.dart` and
`apps/feldexa_app/test/font_metrics_bundle_test.dart` load both fonts, the
licence, and the advance table through `rootBundle`, asserting the pinned byte
sizes, TrueType sfnt header, required/absent tables, OFL markers, and the full
codepoint-to-advance agreement with the TTF bytes. `flutter build web` produced
a `FontManifest.json` entry for `NotoSans` with both weights and packaged the
font and licence files with the exact SHA-256 values above.

## What this does not prove

Byte, configuration, and metrics validity is not rendering evidence. T007
generates `metrics.json` from these TTFs and cross-checks it against the same
bytes; T030 owns the `feldexa_export` Dart/PDFBox metric contract; PDFBox
embedding and PDF rendering are later export tasks. This directory produces no
`SIMULATED`, `EMULATOR`, or `DEVICE` evidence class and does not satisfy any
Android or device acceptance criterion.
