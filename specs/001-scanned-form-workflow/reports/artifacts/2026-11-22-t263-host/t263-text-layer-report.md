# T263 German OCR qualification

- Suite: `de-ocr-1.0.0` (`sf-005`), reference PDF sha256 `671dd6b8b30cd46910e1bab5e0c7a69cfbb5d22efe0000520a25108f38e08e45`
- Metric definition: `metric-definition.v1`
- Raw-text normalization: none
- Overall verdict: **FAIL**
  - reference variant clean-200dpi was not executed

| Variant | Evidence | Status | CER | Special P | Special R | Field P | Field R | Type acc. | Unresolved labels |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| clean-200dpi | EMULATOR | NOT_RUN | n/a | n/a | n/a | n/a | n/a | n/a | n/a |
| clean-150dpi | EMULATOR | NOT_RUN | n/a | n/a | n/a | n/a | n/a | n/a | n/a |
| clean-300dpi | EMULATOR | NOT_RUN | n/a | n/a | n/a | n/a | n/a | n/a | n/a |
| scan-150dpi-low-contrast | EMULATOR_INJECTED_RASTER | NOT_RUN | n/a | n/a | n/a | n/a | n/a | n/a | n/a |
| scan-200dpi-shadow | EMULATOR_INJECTED_RASTER | NOT_RUN | n/a | n/a | n/a | n/a | n/a | n/a | n/a |
| scan-200dpi-skew-3deg | EMULATOR_INJECTED_RASTER | NOT_RUN | n/a | n/a | n/a | n/a | n/a | n/a | n/a |
| scan-200dpi-jpeg-q35 | EMULATOR_INJECTED_RASTER | NOT_RUN | n/a | n/a | n/a | n/a | n/a | n/a | n/a |

## Control paths (never OCR or device evidence)

| Control | Evidence | Status | CER | Exact lines |
| --- | --- | --- | --- | --- |
| text-layer | TEXT_LAYER | PASS | 0.00 | 2/2 pages |

An UNRESOLVED case is reported as unresolved and never counted as an accuracy PASS.
