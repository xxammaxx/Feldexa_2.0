# Contract: Coordinates and Geometry

**Feature**: `001-scanned-form-workflow` | **Package**: `packages/feldexa_core` (`PageGeometry`, `Rect`) | **Consumers**: viewer, overlay editor, recognition, export layout

Geometry correctness is a hard acceptance criterion (FR-024, SC-017). There is exactly one coordinate source of truth: **PDF points in the page display space**. Device pixels, CSS pixels, normalized fractions, and raster pixels are derived views and are never stored.

---

## 1. Coordinate spaces

| Space | Unit / origin | Used by | Persisted |
| --- | --- | --- | --- |
| **PDF user space** | points, origin bottom-left of the page, y up | PDFBox, content streams, `/MediaBox`, `/CropBox` | Page boxes only |
| **Page display space** | points, origin top-left of the display box, y down, after `/Rotate` | document model: field rects, suggestions, layout, hit testing | **Yes — the only persisted geometry** |
| **View space** | logical pixels (Flutter), origin top-left of the viewport | rendering, gestures, painting | No |
| **Raster space** | pixels of a rendered page bitmap | OCR and image analysis | No (only while processing) |
| **Export plan space** | PDF user space + explicit page index | exporter | Derived in the plan, never stored in the model |

### 1.1 Page display box

Given `CropBox = (cx0, cy0, cx1, cy1)` intersected with `MediaBox` (if CropBox is absent, equal to MediaBox):

```text
W0 = cx1 - cx0            H0 = cy1 - cy0
rotation 0   or 180:  displaySize = (W0, H0)
rotation 90  or 270:  displaySize = (H0, W0)
```

`displaySize` is in points. The display box's top-left corresponds to different PDF corners depending on rotation (see §2).

---

## 2. Model ↔ PDF user space

Let `(x, y, w, h)` be a rectangle in display space (top-left origin, y down) and `(u, v)` a point in PDF user space. All page rectangles are converted with these exact formulas.

### Rotation 0

```text
display → PDF point:   u = cx0 + dx          v = cy1 - dy
PDF → display point:   dx = u - cx0          dy = cy1 - v
display rect → PDF:    (u0, v0, ur, vr) = (cx0 + x, cy1 - y - h, w, h)
```

### Rotation 90 (clockwise when displayed)

Display top-left is the PDF bottom-left.

```text
display → PDF point:   u = cx0 + dy          v = cy0 + dx
PDF → display point:   dx = v - cy0          dy = u - cx0
display rect → PDF:    (u0, v0, ur, vr) = (cx0 + y, cy0 + x, h, w)
```

### Rotation 180

Display top-left is the PDF top-right.

```text
display → PDF point:   u = cx1 - dx          v = cy0 + dy
PDF → display point:   dx = cx1 - u          dy = v - cy0
display rect → PDF:    (u0, v0, ur, vr) = (cx1 - x - w, cy0 + y, w, h)
```

### Rotation 270 (clockwise when displayed; equivalent to 90 counter-clockwise)

Display top-left corresponds to the PDF top-right: display x increases as PDF y decreases, display y increases as PDF x decreases.

```text
display → PDF point:   u = cx1 - dy          v = cy1 - dx
PDF → display point:   dx = cy1 - v          dy = cx1 - u
display rect → PDF:    (u0, v0, ur, vr) = (cx1 - y - h, cy1 - x - w, h, w)
```

**Verification cases** (must be unit-tested for every rotation):

| Rotation | Display rect | Expected PDF rect (W0=595, H0=842, crop at origin) |
| --- | --- | --- |
| 0 | (0, 0, 595, 842) | (0, 0, 595, 842) |
| 90 | (0, 0, 842, 595) | (0, 0, 595, 842) |
| 180 | (0, 0, 595, 842) | (0, 0, 595, 842) |
| 270 | (0, 0, 842, 595) | (0, 0, 595, 842) |

And for a field at display `(100, 50, 120, 20)` on a 0-rotation page: PDF lower-left `(100, 772)`, size `(120, 20)`. On a 90-rotation page: PDF lower-left `(50, 100)`, size `(20, 120)`. These are normative.

### 2.1 CropBox offsets

CropBox offsets are always added/subtracted through `cx0`, `cy0`, `cx1`, `cy1`; no code may assume `cx0 = cy0 = 0`. Unit tests include crop boxes offset by (10, 20) and clipped against a smaller MediaBox.

---

## 3. View transform (zoom, pan, fit)

State: `scale` (view points per model point; Flutter logical pixels per point) and `Offset pan` (view-space translation of model origin).

```text
view = pan + scale × model
model = (view - pan) / scale
```

- `fitWidthScale = viewportWidth / displaySize.width`
- `fitPageScale = min(viewportWidth / displaySize.width, viewportHeight / displaySize.height)`
- Allowed zoom range: `0.5 × fitWidthScale … 8 × fitWidthScale`, clamped.
- Painting uses `canvas.scale(scale)` with a translation; rectangles are painted from model coordinates, never from accumulated pixel deltas.
- The scale factor is a `double` and is not persisted as integer zoom steps; the model stores an optional zoom preference as a ratio of `fitWidthScale`.

**Gesture rules**
- Drag/resize convert pointer deltas to model deltas by dividing by `scale` **once**, at gesture start, using the current transform; no incremental rounding.
- Minimum field size in the model: `4 pt × 4 pt`; resize clamps in model space, not view space.
- Snap-to-line (optional assistance) snaps in model space using detected line coordinates within `2 pt`; it never changes geometry without a pointer-driven commit.

**Hit testing**
- A pointer selects the topmost field whose rect (inflated by `max(4 pt, 12 viewPx / scale)`) contains the point; the inflation affects hit area only, never stored/exported geometry (edge case: very small checkboxes).
- Tapping the page background clears selection.
- Zoom-to-field computes a pure target scale
  `target = clamp(min(0.7 × viewportHeight / fieldHeightPt, 0.9 × viewportWidth / fieldWidthPt, 8 × fitWidthScale), fitWidthScale, 8 × fitWidthScale)`,
  then pans to center the field. It never mutates the field rect (FR-034).

---

## 4. Raster space (OCR and image analysis)

```text
rasterScale = dpi / 72
rasterWidthPx  = round(displaySize.width  × rasterScale)
rasterHeightPx = round(displaySize.height × rasterScale)
```

- Analysis DPI: 200 (`rasterScale = 2.777…`), grayscale, no alpha.
- UI rendering: device-pixel-ratio-aware, capped at 4096 px on the long edge; if the cap applies, the effective scale is reduced and reported to the painter, never to the model.
- OCR/analysis rectangles are converted from raster pixels to display points by `point = pixel / rasterScale`, with a documented half-pixel origin choice (pixel centers at `i + 0.5`). Rounding must not exceed 0.01 pt in the produced suggestion rect.
- Rotated pages are rendered by PDFium already rotated into display orientation; analysis never re-rotates.

---

## 5. Export mapping

The export plan carries, per op, both:
- `rect` — display-space rectangle (for verification and human inspection);
- `pdfRect` — PDF user-space rectangle produced by the §2 formulas (authoritative for drawing).

Rules:
- **Rendering orientation (normative)**: the export adapter draws all ops in **display space** by prepending the display→PDF affine CTM to the appended content stream. This neutralizes the page's `/Rotate`, so text, images, and marks appear upright exactly as in the editor, on all four rotations. The CTM for each rotation is derived from §2:

| Rotation | `a` | `b` | `c` | `d` | `e` | `f` | Meaning |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 1 | 0 | 0 | −1 | cx0 | cy1 | x right, y down |
| 90 | 0 | 1 | 1 | 0 | cx0 | cy0 | x right, y down |
| 180 | −1 | 0 | 0 | −1 | cx1 | cy0 | x right, y down |
| 270 | 0 | −1 | −1 | 0 | cx1 | cy1 | x right, y down |

  where `u = a·x + c·y + e` and `v = b·x + d·y + f`. Each matrix is verified by mapping the four display-box corners back to the PDF box corners, and by a golden render on each rotation.
- Text baselines are computed in display space (top padding + ascender) and drawn under the same CTM; glyphs are never mirrored or rotated relative to the editor view.
- The export plan also carries `pdfRect` per op (the display rect mapped by §2) for artifact verification. `pdfRect` is a verification value only; drawing uses display coordinates plus the CTM.
- Signature images are drawn upright in display space under the CTM. A signature captured while the page was displayed rotated is therefore already in display orientation and needs no additional rotation.
- Checkbox marks are drawn as vectors in display space (no text, no font dependency).
- A3/A4/A5 mixed pages use each page's own crop/rotation; no global page assumption.
- Conversion tolerance: 0.01 pt in plan generation; final artifact position tolerance is 1 mm at A4 scale (2.835 pt) per SC-017.

---

## 6. Invariants and tests

1. Every stored rect lies within `[0, 0, displayW, displayH]` after `PageGeometry.validate`; violations > 0.5 pt are rejected, smaller numerical noise is clamped once at import/serialization with a recorded warning.
2. Round-trip property: `pdfToDisplay(displayToPdf(r)) == r` within `1e-6 pt` for all rotations and crop offsets.
3. Zoom invariance: the same model rect maps to the same PDF rect for scales `0.5, 1, 1.75, 3, 8` (no dependence on view state).
4. Mixed pages: a document with A4 portrait, A4 landscape (via rotation), and A5 pages keeps each field on its own page and geometry.
5. Drag/resize: 1,000 randomized gestures at random scales produce model rects equal to the analytically expected rects within `0.01 pt`.
6. Hit test does not alter geometry; resizing a 6 pt checkbox with a 12 px hit area never changes its center unless the user drags.
7. Export plan `pdfRect` equals the §2 formula for every rotation, including non-zero crop offsets.
8. Device independence: the same document opened on a 360 dp phone, a 800 dp tablet, and a 1440 px browser produces identical model rects and equivalent visual placement.
