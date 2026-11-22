# T086B-P before/after candidate snapshots

This bundle is the committed evidence behind the T086B-P claim that the
rule-pair indexing in `GeometryDetector.detect` does not change detection
output. It is `NONE`-class host evidence: no emulator, no device, no product
build.

- `before/` — one JSON snapshot per page, produced with the **base-revision**
  detector (`2ab14cc93f2452a0153e6ca28293573df8376f48`,
  `packages/feldexa_recognition/lib/src/geometry_detector.dart`) during the
  T086B investigation. That detector enumerated every horizontal rule pair
  against every vertical rule pair (`O(h^2 * v^2)`).
- `after/` — the same pages sampled with the T086B-P detector, i.e. the
  indexed scan plus the shared `_considerBox` acceptance logic.
- `manifest.json` — per page: PDF SHA-256, page size, raster dimensions,
  candidate count, `detect` timings for both builds, and byte size plus SHA-256
  of both snapshots, with `allIdentical` asserting the byte comparison result.

Each snapshot is the tool's candidate export: `x`, `y`, `width`, `height`,
sorted `cues`, and measured `inkCoverage` per candidate, in detector order.

## Covered pages

12 pages, all with a contract-valid 200 DPI raster: `sf-001` pages 1-2,
`sf-002` pages 1-5, `sf-003` pages 1-4, `sf-004` page 1.

`sf-003` page 5 is excluded: the fixture catalogue says 595.28 x 419.53 pt with
rotation 270, so the contract raster is 1654 x 1165 px, while host Poppler
renders it as 1654 x 1166 px. The detector correctly rejects that mismatched
raster with a content-free `ArgumentError`. Editing the page to force a match
was not acceptable, so the page carries no snapshot and no claim.

## How to verify

1. Rasterize a page at the contract size with the host rasterizer:
   `pdftoppm -gray -r 200 -f PAGE -l PAGE PDF OUT`, then confirm the PGM header
   matches `round(widthPt * 200 / 72) x round(heightPt * 200 / 72)`.
2. Run the snapshot tool from the repository root:
   `dart run tools/evaluation/benchmark_detection_pgm.dart OUT-PAGE.pgm WIDTHPT HEIGHTPT RESULT.json`.
3. Compare `RESULT.json` with the committed `after/` snapshot of the same page
   (byte equality), and compare `before/` with `after/` to reproduce the
   no-regression result.
4. For the exhaustive reference used by the test suite, run
   `flutter test test/geometry_detector_index_equivalence_test.dart` in
   `packages/feldexa_recognition`; it compares the indexed scan against the
   retained exhaustive scan on adversarial rule sets.

Both `before/` and `after/` were produced on the host named in
`manifest.json`. Timings are single-shot host JIT measurements and are not the
SC-004 device claim and not a runtime performance claim.
