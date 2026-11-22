# Adaptive OCR policy v1.0.0 — pre-declared, not implemented

| Field | Value |
| --- | --- |
| Artifact | `tools/evaluation/adaptive-policy.v1.json` |
| Status | frozen before any scored run; implementation **BLOCKED** |
| Task / issue | T264A / [#264](https://github.com/xxammaxx/Feldexa_2.0/issues/264) (owner-decision task: T264P) |
| Frozen by | T264A after the 2026-11-22 planning reviews A/B FAIL |
| Evidence class | `NONE` (policy text and numbers only; proves no runtime behaviour) |

## 1. Why this file exists

The owner-approved T264 scope contains an adaptive second analysis. Two
independent planning reviews rejected implementing it directly:

1. a second pass needs **pass/observation provenance** before it can write into a
   suggestion set, because `SuggestionSchema` v1 and `recognition-output` §6 only
   collapse exact duplicates *within one pass* (`same type`, `same detectorPass`,
   `IoU > 0.98`). A cross-pass near-duplicate would today appear as a conflict;
2. a *structure mismatch* cannot be computed at runtime without a declared ground
   truth, so it cannot be a production trigger;
3. the raster contract is fixed at 200 DPI with an exact `RasterSize`, no
   `RasterRequest` crop, and a documented 4096 px cap that silently downscales, so
   a "2x crop" would either change the analysis scale or silently lose resolution.

The JSON artifact therefore freezes the *decisions and numbers* now and marks the
implementation `BLOCKED`. No code below the evaluation layer exists yet.

## 2. Blocking prerequisites

| ID | State | Content |
| --- | --- | --- |
| P1 | `NOT_MERGED` | `packages/feldexa_recognition/lib/src/geometry_detector.dart` is T086B-owned until T086B merges. T264 reads it only. |
| P2 | `UNDECIDED` | Schema/provenance decision: `SuggestionSchema` version bump, T058 migration, and a cross-pass merge rule with an explicit `detectorPass` identity. Registered as T264P; owner decision required. |
| P3 | `DECIDED` | Runtime triggers use measurable page/pipeline state only; the structure comparison stays evaluation-only. |

## 3. Runtime signals (fixed order, numeric)

| Signal | Metric | Enter | Leave |
| --- | --- | --- | --- |
| low contrast | `p95 − p05` on the photometric original | `< 96` | `> 112` |
| skew | caller-supplied absolute degrees | `> 0.5` | `< 0.25` |
| OCR failure | port threw or zero usable lines | `true` | — |
| missing label | unlabelled candidates / candidates (≥ 3 candidates) | `≥ 0.5` | — |
| conflict | conflict-graph pairs with `IoU ≥ 0.5` | `≥ 1` | — |
| structure mismatch | evaluation only | `runtimeTrigger: false` | — |

The 16-point contrast hysteresis and the 0.25° skew exit threshold exist so a
page at the boundary cannot oscillate between one and two passes.

## 4. Bounds and render strategy

* at most **2** passes per page, at most **4,000 ms** per page, at most
  **8,000,000** variant pixels, one variant raster in memory at a time;
* a failed adaptive pass returns the pass-1 result unchanged (page-failure
  isolation is preserved);
* v1 allows only the two same-DPI variants (`contrastStretch`, `deskew`). The
  higher-resolution crop is excluded with the reason above and needs its own
  contract change plus a pixel-identity proof before any 2x claim.

## 5. Independence rule

Every variant is derived from the same original scan, so its observations are
**correlated**. `twoIndependentOcrLinesAgree` stays `false`, and no confidence
bonus for two independent OCR lines may be raised by an adaptive pass.

## 6. Acceptance thresholds (pre-declared, A/B/C)

Mode A = single pass, mode B = full second pass, mode C = targeted adaptive, on
identical inputs. Mode C must not be worse than A on recall, precision, type
accuracy, mean matched IoU, missing fields, extra fields, or review rate
(+0.05 tolerance), must use fewer passes than B, and must not exceed
`2 ×` the mode-A median latency or the mode-B median latency. Nothing is
auto-confirmed, so the false-accept count must be `0`. If mode C is not strictly
better than mode A on at least one metric, the conservative baseline stays and the
report must say so. No existing SC gate is lowered.

## 7. Corpus, holdout, and NOT_RUN

Dev pages: `clean-text`, `numeric-formats`, `checkbox-row`, `missing-checkbox`,
`duplicate-checkbox`, `table`. Holdout scored once: `furniture-only`,
`low-contrast`, `broken-frame`, `shadow`. The synthetic corpus is declared; no
rights-cleared real authority form exists yet.

`NOT_RUN`: adaptive implementation, schema/provenance change, A/B/C benchmark,
Android `EMULATOR` production-path evidence, real-corpus qualification.
