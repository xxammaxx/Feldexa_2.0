# T263 correction-4 authoritative metrics report

This directory holds the **authoritative** frame-correct metrics report for the
T263 qualification at commit `310255750fc6f828d5236f04c3e05a50f74b50ea`
(correction-3 code HEAD, tree `22dbc94098134e0d25240b6a407fb109587a0ad8`).

- `t263-report.json` and `t263-report.md` were generated with
  `tools/metrics/de_ocr_qualification.dart --require-device-evidence` (current
  frame-correct scorer, which rotates a variant's own annotation into its
  input-raster frame when the recorded raster carries a known skew injection) from
  the **byte-unchanged** raw run files of `../2026-11-22-t263-emulator-c3/`:
  - `../2026-11-22-t263-emulator-c3/t263-run-emulator.json` (SHA-256
    `d2524d1c7736fd9d33f90bff1f62688514f04108158e9c71077ae9855e3d00a2`)
  - `../2026-11-22-t263-emulator-c3/t263-run-injected.json` (SHA-256
    `44b9c043e30ff4898f5f34c706f5139ff991e62829bd7a978c54936b51c579d9`)
- `c3` stays the raw-run source of record (device identity, APK hash, driver hash,
  marker sequence, pull logs) and keeps its **frozen** run-time report
  (`t263-report.json` SHA-256 `557e9155…`, skew `FAIL` 43.51 % / 30-of-51 as
  measured then). It is never overwritten by a re-score.
- This directory is the **authoritative** report: `requireDeviceEvidence: true`,
  skew `PASS` 51/51, CER 2.33 %,
  `groundTruthTransform: {skewDegrees: 3.0, annotationTransformed: true}`. It adds
  the re-scored report only; it contains no device execution of its own.
- Skew measurement: `scan-200dpi-skew-3deg` is **PASS** with 51/51 associated
  lines, CER 2.33 % and special-character recall 92.31 %
  (`groundTruthTransform: {skewDegrees: 3.0, annotationTransformed: true}`). The
  upright-annotation score of the same run (43.51 %, 30/51) is the explicitly
  non-comparable measurement and is not the result.
- Overall verdict stays **FAIL**: the `clean-200dpi` reference variant misses its
  pre-declared ceilings (CER 2.33 % > 2.00 %, special-character recall 93.27 % <
  100 %, 5 critical lines not exact, label accuracy 76.92 % < 100 %) because the
  special-character losses are bundled-ML-Kit model limits.
- No threshold, ground-truth, expected-text or run-file value was changed to
  produce this report.
