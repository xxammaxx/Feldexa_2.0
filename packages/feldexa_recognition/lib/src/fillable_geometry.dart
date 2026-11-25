// Value-fit admission for detected field candidates (issue #340).
//
// Normative sources:
//  * `specs/001-scanned-form-workflow/contracts/export-plan.md` §2.2 (text
//    layout: `fontSizePt = clamp(0.6 × rect.height, 7.0, 12.0)`,
//    `baselineFromTopPt = 1.5 + 0.8 × fontSizePt`, and the normative op rule
//    `baselineFromTopPt ≤ rect.height`) and §3.1 (1.5 pt padding on all four
//    sides, so available width is `rect.width − 3.0`; a single-line field has
//    exactly one line and overflows when it is wider than that);
//  * `specs/001-scanned-form-workflow/contracts/coordinates-and-geometry.md`
//    §3 (minimum field size in the model is 4 pt × 4 pt);
//  * `specs/001-scanned-form-workflow/contracts/recognition-output.md` §3.1
//    (`small_square` is a near-square region of 4–20 pt) and §2.1 (a candidate
//    must be empty background, never printed text);
//  * `specs/001-scanned-form-workflow/spec.md` FR-016 (printed text MUST NOT be
//    proposed as user input).
//
// Why this exists
// ---------------
// The detector reports every geometrically consistent empty region, including
// the counters inside printed glyphs. Such a region is a legitimate *candidate*
// — it is empty background enclosed by four ink edges — but it is not a field:
// it is enclosed by a printed letter, so FR-016 forbids proposing it, and its
// rectangle cannot hold a value under the export layout rules. Issue #340 is
// that case on a shipped fixture: confirming the suggestion produced a field
// that rejected a single character with `FLD-001` and blocked the export with
// `EXP-001`.
//
// This module answers one question for the suggestion path, and answers it from
// the contract instead of from a tuned value:
//
//   can a rectangle of this geometry hold a value of this type?
//
// A candidate that cannot is not offered. Nothing here changes the detected
// geometry, a threshold of the measurement, or the layout: `field_text_fit` and
// `layout.dart` keep measuring what they measure, and a *user-drawn* field of
// any size remains allowed by the model minimum above.
//
// The limits are derived, not chosen:
//
//  * text-bearing types (`text`, `number`, `date`, `multiline`) need
//    `rect.height ≥ minimumValueHeightPt`. §2.2 clamps the font size up to the
//    documented minimum of 7.0 pt, so the first baseline sits
//    `1.5 + 0.8 × 7.0 = 7.1 pt` below the rect top; a shorter rect violates the
//    normative `baselineFromTopPt ≤ rect.height` and can never render a glyph
//    at any font size.
//  * they also need `rect.width > minimumValueWidthPt`. §3.1 subtracts 1.5 pt
//    of padding per side, so a rect of 3.0 pt or less has no available width at
//    all and every value overflows.
//  * `checkbox` needs `min(rect.width, rect.height) ≥ minCheckboxSidePt`. The
//    `small_square` cue of §3.1 starts at 4 pt, and 4 pt is also the model's
//    minimum field size; a smaller region is a glyph counter, not a box the
//    user could mark.
//  * `signature` has no derived minimum: its cue (`signature_area`) requires a
//    large low-ink region and the export only fits a captured image into the
//    rect, so no rect can be "unfillable" for that reason.
//
// The residual case this deliberately does not decide: a text-bearing rect that
// is tall enough but so narrow that only a few glyphs fit at the minimum font
// size. That is ordinary overflow (`FLD-001`/`EXP-001`), which the contract
// keeps as a visible warning for user-confirmed fields (FR-037/FR-038); it is
// not a candidate-quality defect, because the user can shorten the value.
library;

import 'dart:math' as math;

import 'geometry_detector.dart';

/// Smallest field height that can render one line of the smallest contract font.
///
/// `contracts/export-plan.md` §2.2: `baselineFromTopPt = 1.5 + 0.8 × fontSizePt`
/// and the op rule `baselineFromTopPt ≤ rect.height`, with
/// `fontSizePt = clamp(0.6 × rect.height, 7.0, 12.0)`. The smallest font size
/// therefore needs `1.5 + 0.8 × 7.0 = 7.1 pt` of height.
const double minimumValueHeightPt = 7.1;

/// Smallest field width with a positive available text width.
///
/// `contracts/export-plan.md` §3.1 pads 1.5 pt on all four sides, so
/// `availableWidth = rect.width − 3.0`. At 3.0 pt or below it is not positive
/// and no value can be drawn.
const double minimumValueWidthPt = 3.0;

/// Smallest checkbox side, matching `FieldInventory.minCheckboxSidePt`.
///
/// `contracts/recognition-output.md` §3.1 defines `small_square` as a
/// near-square region of 4–20 pt, and
/// `contracts/coordinates-and-geometry.md` §3 sets the model's minimum field
/// size to 4 pt × 4 pt. Below that the region is a printed glyph counter
/// (`FieldInventory` reports it as `letterInterior`), not a markable box.
const double minCheckboxSidePt = 4;

/// Whether [rect] can hold a value of [proposedType] under the export layout.
///
/// [proposedType] is one of `SuggestionSchema.proposedTypes`. Types without a
/// derived minimum (today only `signature`) are always admitted, so a new type
/// is never silently dropped by this rule.
bool admitsValueOfType({
  required DisplayRect rect,
  required String proposedType,
}) {
  switch (proposedType) {
    case 'checkbox':
      return math.min(rect.width, rect.height) >= minCheckboxSidePt;
    case 'text':
    case 'number':
    case 'date':
    case 'multiline':
      return rect.height >= minimumValueHeightPt &&
          rect.width > minimumValueWidthPt;
    default:
      return true;
  }
}
