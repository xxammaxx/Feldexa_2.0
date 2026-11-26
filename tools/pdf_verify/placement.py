#!/usr/bin/env python3
"""Placement verification of an exported field value in a Feldexa PDF artifact.

Issue #344 part A2. The tool replaces the centre-to-centre measurement of the
first run with a metric derived from the layout code that draws the value.

What the 1 mm claim measures
----------------------------
Measured quantity: the glyph box of the exported value as Poppler reports it
(``pdftotext -bbox``). Poppler reports display space, the same convention the
field rect uses: origin at the page's top-left corner, x to the right, y
downwards, unit PDF point (1/72 in). No axis flip is applied, and
``axes_check`` fails closed if the reported box and the rect do not sit in the
same place on the page.

Target quantity: the origin the layout code puts that value at. The numbers are
read from their normative sources at run time, never typed in:

* ``apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/export/``
  ``ExportPlanValidation.kt`` — ``TEXT_PADDING_PT`` (1.5 pt), the padding of the
  code that actually draws the value (``PdfExportService`` takes it from
  ``ExportPlanValidator``);
* ``packages/feldexa_export/lib/src/layout.dart`` — ``exportFieldPaddingPt``
  (1.5 pt, the plan builder's own copy of that padding),
  ``_baselineAscenderFactor`` (0.8), ``_fontSizeHeightFactor`` (0.6), the
  ``fontSizePt`` clamp (7.0 … 12.0);
* ``specs/001-scanned-form-workflow/contracts/export-plan.md`` §3.1 —
  "padding 1.5 pt on all sides", "vertical alignment: top, baseline
  ``= rect.y + baselineFromTopPt``", "horizontal alignment: left";
* ``apps/feldexa_app/assets/fonts/metrics.json`` — ``ascender`` (1069),
  ``descender`` (-293), ``unitsPerEm`` (1000) of the bundled Noto Sans, needed
  only to place the baseline inside the box Poppler reports.

The padding exists twice, as two independent constants in two languages, and
neither is derived from the other. The horizontal target is therefore taken from
the constant the drawing code uses, and the layout copy is read as well: if the
two disagree, or either cannot be read, the tool refuses a verdict with exit 5,
because a drifted applier constant would move the drawn value away from a target
derived from the other copy while the deviation stayed inside the 1 mm tolerance.

From those the tool computes

    fontSizePt = round(clamp(0.6 * rect.height, 7.0, 12.0), 1)
    origin x   = rect.x + TEXT_PADDING_PT                     (drawing code)
    baseline y = rect.y + baselineFromTopPt                   (§3.1 op field)
               = rect.y + exportFieldPaddingPt + _baselineAscenderFactor * fontSizePt

Four named points are reported, each with its number and its own
``pass``/``fail``:

1. ``horizontal_origin`` — measured glyph-box left edge against ``origin x``.
2. ``vertical_baseline`` — measured baseline against ``baseline y``. Poppler
   reports the font's ascent/descent box, not the baseline, so the baseline is
   an *inference*: it is reconstructed from the two reported box edges through
   the font metrics (``yMin + ascender``, ``yMax + descender``) and is never
   measured directly. Both reconstructions have to stay within the tolerance.
   They are not independent evidence: the spread between them

       from_descent - from_ascent = (yMax - yMin) + (descender - ascender)
                                  = box height - font box height

   is algebraically forced to zero as soon as the reported box height equals the
   font box height, which is the case for the recorded artifact (``14.709600``
   both ways). ``baseline_estimate_spread_pt`` is reported because a *non-zero*
   spread diagnoses a box that is not the font's ascent/descent box; a zero
   spread confirms nothing, so point 4 carries the assumption instead.
3. ``containment`` — the reported glyph box against the field rect, left and
   right edge: the left-aligned value must start inside the rect and must not
   overrun its right edge. Vertically the same box is only reported, not judged:
   the box is the font's ascent/descent box (Noto Sans: ascender 1.069 em,
   descender -0.293 em), while §3.1 constrains the baseline, and the ascent is
   taller than the space the formula leaves above the baseline (1.5 pt + 0.8 em
   = 10.14 pt at 10.8 pt against an ascent of 11.545 pt). The ascent edge of the
   font box therefore protrudes above the rect top for every value drawn with
   this formula — 1.405 pt at the recorded field — which is font geometry, not a
   placement error. The tool prints both vertical overflows together with the
   two numbers the allowance follows from
   (``informational.ascent_above_baseline_pt`` and
   ``informational.baseline_offset_from_rect_top_pt``), so the number is
   checkable and the judgement stays with the reader.
4. ``font_box.height`` — the reported box height against
   ``(ascender - descender) * fontSizePt``. This is the check that carries the
   font-metric assumption the baseline reconstruction of point 2 rests on: it
   verifies that the ascent/descent pair read from ``metrics.json`` is the pair
   the PDF's own font reports. It is read at the printer's resolution
   (``BOX_HEIGHT_TOLERANCE_PT``), not at the 1 mm placement tolerance, because
   it compares two computations of one font metric rather than two positions.

The 1 mm verdict is ``PROVEN`` when points 1 and 2 pass and point 4 confirms
the font-metric basis of the baseline inference, ``NOT_PROVEN`` otherwise. Exit
code 0 means every point passed (containment included), 1 means a point failed,
and 2 … 6 mean the tool refused to produce a verdict (usage error, word not
found, ambiguous word match, unreadable input, Poppler failure).

Why a centre-to-centre comparison is invalid here
-------------------------------------------------
The first run measured the box centre against the *rect* centre over a
300 pt wide, left-aligned field and reported ``dx = -132.140 pt`` with the rect
``x 190.125, w 299.875`` and the value box ``191.625 … 224.219`` (width
32.594):

    rect  centre x = 190.125 + 299.875 / 2 = 340.0625
    value centre x = 191.625 + 32.594 / 2   = 207.922
    difference     =                       -132.1405

The difference is the half field overhang the layout leaves empty by contract,
``(299.875 - 32.594) / 2 = 133.640 pt``, minus the 1.5 pt padding offset. It
measures the field width and the value length, not the position of the value.
The same holds vertically: the rect centre carries no information about where
the baseline belongs, so a centre-to-centre ``dy`` measures ascent/descent
geometry. A left-aligned, top-aligned layout can therefore never satisfy a
centre-to-centre claim, and a metric that reports "not proven" for a correct
artifact is the defect the metric carries, not the product's.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import shlex
import subprocess
import sys
import xml.etree.ElementTree as ElementTree
from dataclasses import dataclass
from pathlib import Path

#: One millimetre in PDF points: 72 pt/in divided by 25.4 mm/in.
MILLIMETER_PT = 72.0 / 25.4

#: Placement tolerance, 1 mm rounded to three decimals (Issue #344 names
#: 2.835 pt). The default is never widened at run time; `--tolerance-pt` exists
#: only so a stricter run can be made.
DEFAULT_TOLERANCE_PT = round(MILLIMETER_PT, 3)

#: Floating-point comparison guard around the tolerance, mirroring
#: `_comparisonTolerancePt` in `layout.dart`. It is a guard, not a tolerance: it
#: absorbs representation noise so a deviation of exactly 2.835 pt passes.
_COMPARISON_TOLERANCE_PT = 1e-9

#: Tolerance of the ``font_box.height`` assumption check, in points. Poppler
#: prints six decimals, so its rounding stays at or below 1e-6 pt; one design
#: unit of the bundled font is 0.007 pt at the smallest allowed size (7 pt /
#: 1000). A thousandth of a point sits between the two: it absorbs the reader's
#: rounding and still catches a change of the ascent or descent by a single font
#: unit. This is a resolution bound, not a placement tolerance.
BOX_HEIGHT_TOLERANCE_PT = 0.001

_REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
_DEFAULT_LAYOUT = _REPOSITORY_ROOT / "packages/feldexa_export/lib/src/layout.dart"
_DEFAULT_APPLIER = (
    _REPOSITORY_ROOT
    / "apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/export"
    / "ExportPlanValidation.kt"
)
_DEFAULT_FONT_METRICS = (
    _REPOSITORY_ROOT / "apps/feldexa_app/assets/fonts/metrics.json"
)

EXIT_OK = 0
EXIT_CHECK_FAILED = 1
EXIT_USAGE = 2
EXIT_WORD_NOT_FOUND = 3
EXIT_WORD_AMBIGUOUS = 4
EXIT_UNREADABLE_INPUT = 5
EXIT_POPPLER_FAILED = 6

_FIELD_RECT_MARKER = re.compile(
    r"^T334_FIELD_RECT:PAGE=(?P<page>[0-9]+)"
    r":X_MPT=(?P<x>-?[0-9]+):Y_MPT=(?P<y>-?[0-9]+)"
    r":W_MPT=(?P<width>-?[0-9]+):H_MPT=(?P<height>-?[0-9]+)$"
)

#: `const val TEXT_PADDING_PT = 1.5` in the applier's `ExportPlanValidator`.
_TEXT_PADDING = re.compile(
    r"const\s+val\s+TEXT_PADDING_PT\s*(?::\s*Double)?\s*=\s*"
    r"(-?[0-9]+(?:\.[0-9]+)?)\s*$",
    re.MULTILINE,
)


class PlacementError(Exception):
    """A condition that forbids a verdict; carries its exit code."""

    def __init__(self, exit_code: int, reason: str) -> None:
        super().__init__(reason)
        self.exit_code = exit_code
        self.reason = reason


@dataclass(frozen=True)
class FieldRect:
    """The field rect from the `T334_FIELD_RECT` marker, in points."""

    page: int
    x_pt: float
    y_pt: float
    width_pt: float
    height_pt: float

    @property
    def right_pt(self) -> float:
        return self.x_pt + self.width_pt

    @property
    def bottom_pt(self) -> float:
        return self.y_pt + self.height_pt


@dataclass(frozen=True)
class LayoutConstants:
    """The layout numbers the target origin is derived from."""

    field_padding_pt: float
    baseline_ascender_factor: float
    font_size_height_factor: float
    min_font_size_pt: float
    max_font_size_pt: float


@dataclass(frozen=True)
class FontVerticalMetrics:
    """The bundled font's ascent/descent box, in design units."""

    units_per_em: int
    ascender: int
    descender: int

    def ascender_pt(self, font_size_pt: float) -> float:
        return self.ascender * font_size_pt / self.units_per_em

    def descender_pt(self, font_size_pt: float) -> float:
        return self.descender * font_size_pt / self.units_per_em

    def box_height_pt(self, font_size_pt: float) -> float:
        return (self.ascender - self.descender) * font_size_pt / self.units_per_em


@dataclass(frozen=True)
class GlyphBox:
    """A word box as Poppler reports it, display space."""

    x_min_pt: float
    y_min_pt: float
    x_max_pt: float
    y_max_pt: float

    @property
    def width_pt(self) -> float:
        return self.x_max_pt - self.x_min_pt

    @property
    def height_pt(self) -> float:
        return self.y_max_pt - self.y_min_pt

    @property
    def centre_x_pt(self) -> float:
        return (self.x_min_pt + self.x_max_pt) / 2

    @property
    def centre_y_pt(self) -> float:
        return (self.y_min_pt + self.y_max_pt) / 2


@dataclass(frozen=True)
class Page:
    """One page of the `pdftotext -bbox` document."""

    width_pt: float
    height_pt: float
    words: tuple[tuple[str, GlyphBox], ...]


@dataclass(frozen=True)
class CheckPoint:
    """One named pass/fail point with its measured and target numbers."""

    name: str
    measured_pt: float
    target_pt: float
    deviation_pt: float
    tolerance_pt: float
    passed: bool
    detail: str


@dataclass(frozen=True)
class PlacementReport:
    """Everything one verification run establishes."""

    pdf: Path
    page: int
    field_rect: FieldRect
    layout: LayoutConstants
    applier_padding_pt: float
    font: FontVerticalMetrics
    font_size_pt: float
    expected_origin_x_pt: float
    expected_baseline_y_pt: float
    glyph_box: GlyphBox
    page_box: Page
    value_word_length: int
    word_matches: int
    horizontal: CheckPoint
    vertical: CheckPoint
    containment: CheckPoint
    font_box_height: CheckPoint
    box_overflow_top_pt: float
    box_overflow_bottom_pt: float
    ascent_above_baseline_pt: float
    baseline_from_ascent_pt: float
    baseline_from_descent_pt: float
    axes_consistent: bool

    @property
    def placement_proven(self) -> bool:
        return (
            self.horizontal.passed
            and self.vertical.passed
            and self.font_box_height.passed
            and self.axes_consistent
        )

    @property
    def all_checks_passed(self) -> bool:
        return (
            self.placement_proven
            and self.containment.passed
        )

    @property
    def exit_code(self) -> int:
        return EXIT_OK if self.all_checks_passed else EXIT_CHECK_FAILED


def round_to(value: float, decimals: int) -> float:
    """Round half away from zero, mirroring Dart's `roundToDouble`."""
    factor = 10**decimals
    scaled = value * factor
    rounded = math.floor(scaled + 0.5) if scaled >= 0 else math.ceil(scaled - 0.5)
    return rounded / factor


def parse_field_rect_marker(marker: str) -> FieldRect:
    """Parse the numeric `T334_FIELD_RECT` marker into a [FieldRect].

    The marker carries milli-point integers and no text, so nothing from the
    document enters the measurement.
    """
    match = _FIELD_RECT_MARKER.match(marker.strip())
    if match is None:
        raise PlacementError(
            EXIT_UNREADABLE_INPUT,
            f"field rect marker does not match T334_FIELD_RECT:PAGE=…:X_MPT=…"
            f":Y_MPT=…:W_MPT=…:H_MPT=…: {marker.strip()!r}",
        )
    rect = FieldRect(
        page=int(match.group("page")),
        x_pt=int(match.group("x")) / 1000.0,
        y_pt=int(match.group("y")) / 1000.0,
        width_pt=int(match.group("width")) / 1000.0,
        height_pt=int(match.group("height")) / 1000.0,
    )
    if rect.width_pt <= 0 or rect.height_pt <= 0:
        raise PlacementError(
            EXIT_UNREADABLE_INPUT,
            f"field rect must have a positive extent: {rect.width_pt} x "
            f"{rect.height_pt} pt",
        )
    return rect


def read_layout_constants(path: Path) -> LayoutConstants:
    """Read the layout numbers from `layout.dart`.

    The constants are the normative source of the target origin, so the tool
    reads them instead of restating them; a renamed or retyped constant makes
    the run refuse to produce a verdict.
    """
    try:
        source = path.read_text(encoding="utf-8")
    except OSError as error:
        raise PlacementError(
            EXIT_UNREADABLE_INPUT, f"cannot read layout source {path}: {error}"
        ) from error

    def constant(name: str) -> float:
        pattern = re.compile(
            rf"const\s+double\s+{re.escape(name)}\s*=\s*(-?[0-9]+(?:\.[0-9]+)?)\s*;"
        )
        match = pattern.search(source)
        if match is None:
            raise PlacementError(
                EXIT_UNREADABLE_INPUT,
                f"layout source {path} does not declare `double {name}`",
            )
        return float(match.group(1))

    return LayoutConstants(
        field_padding_pt=constant("exportFieldPaddingPt"),
        baseline_ascender_factor=constant("_baselineAscenderFactor"),
        font_size_height_factor=constant("_fontSizeHeightFactor"),
        min_font_size_pt=constant("exportMinFontSizePt"),
        max_font_size_pt=constant("exportMaxFontSizePt"),
    )


def require_matching_padding(
    layout_pt: float, applier_pt: float, layout_path: Path, applier_path: Path
) -> None:
    """Refuse when the two padding copies disagree.

    `layout.dart` and the applier's `ExportPlanValidator` each carry the 1.5 pt
    field padding as an independent constant, and nothing derives one from the
    other. The horizontal target origin is the padding of the code that draws,
    so a drifted layout copy would make the tool measure against the wrong
    number without leaving the tolerance.
    """
    if abs(layout_pt - applier_pt) <= _COMPARISON_TOLERANCE_PT:
        return
    raise PlacementError(
        EXIT_UNREADABLE_INPUT,
        f"field padding differs: layout source {layout_path} declares "
        f"{layout_pt} pt, applier source {applier_path} declares "
        f"{applier_pt} pt; the target origin would be derived from a constant "
        f"the drawing code does not use",
    )


def read_applier_padding_pt(path: Path) -> float:
    """Read `TEXT_PADDING_PT` from the applier's `ExportPlanValidator`."""
    try:
        source = path.read_text(encoding="utf-8")
    except OSError as error:
        raise PlacementError(
            EXIT_UNREADABLE_INPUT, f"cannot read applier source {path}: {error}"
        ) from error
    match = _TEXT_PADDING.search(source)
    if match is None:
        raise PlacementError(
            EXIT_UNREADABLE_INPUT,
            f"applier source {path} does not declare `const val TEXT_PADDING_PT`",
        )
    return float(match.group(1))


def read_font_vertical_metrics(path: Path) -> FontVerticalMetrics:
    """Read the bundled regular font's vertical metrics from `metrics.json`."""
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
        regular = document["fonts"]["400"]
        return FontVerticalMetrics(
            units_per_em=int(regular["unitsPerEm"]),
            ascender=int(regular["ascender"]),
            descender=int(regular["descender"]),
        )
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise PlacementError(
            EXIT_UNREADABLE_INPUT,
            f"cannot read font vertical metrics from {path}: {error}",
        ) from error


def font_size_pt(rect: FieldRect, layout: LayoutConstants) -> float:
    """The `fontSizePt` clamp of `contracts/export-plan.md` §2.2."""
    clamped = min(
        max(layout.font_size_height_factor * rect.height_pt, layout.min_font_size_pt),
        layout.max_font_size_pt,
    )
    return round_to(clamped, 1)


def expected_origin_x_pt(rect: FieldRect, applier_padding_pt: float) -> float:
    """The left edge the drawing code uses: `rect.x + TEXT_PADDING_PT`."""
    return rect.x_pt + applier_padding_pt


def expected_baseline_y_pt(
    rect: FieldRect, layout: LayoutConstants, font_size: float
) -> float:
    """The baseline §3.1 draws the value on: `rect.y + baselineFromTopPt`.

    `baselineFromTopPt` is built by the plan builder from the layout copy of the
    padding (`layout.dart`), and the applier draws the baseline the op carries.
    `require_matching_padding` guarantees both copies are the same number, so the
    horizontal and the vertical target rest on the same 1.5 pt.
    """
    return (
        rect.y_pt
        + layout.field_padding_pt
        + layout.baseline_ascender_factor * font_size
    )


def run_pdftotext_bbox(pdf: Path, page: int, executable: str) -> str:
    """Run `pdftotext -bbox` for one page and return its XHTML."""
    command = [executable, "-bbox", "-f", str(page), "-l", str(page), str(pdf), "-"]
    try:
        completed = subprocess.run(
            command, capture_output=True, text=True, check=False
        )
    except OSError as error:
        raise PlacementError(
            EXIT_POPPLER_FAILED, f"cannot run {executable}: {error}"
        ) from error
    if completed.returncode != 0:
        raise PlacementError(
            EXIT_POPPLER_FAILED,
            f"{shlex.join(command)} exited {completed.returncode}: "
            f"{completed.stderr.strip()}",
        )
    if not completed.stdout.strip():
        raise PlacementError(
            EXIT_POPPLER_FAILED, f"{shlex.join(command)} produced no output"
        )
    return completed.stdout


def parse_page(document: str) -> Page:
    """Parse the XHTML of a single-page `pdftotext -bbox` run into a [Page]."""
    try:
        root = ElementTree.fromstring(document)
    except ElementTree.ParseError as error:
        raise PlacementError(
            EXIT_POPPLER_FAILED, f"pdftotext -bbox output is not XML: {error}"
        ) from error
    pages = [element for element in root.iter() if _local_name(element) == "page"]
    if not pages:
        raise PlacementError(EXIT_POPPLER_FAILED, "pdftotext -bbox reports no page")
    if len(pages) > 1:
        raise PlacementError(
            EXIT_POPPLER_FAILED,
            f"pdftotext -bbox reports {len(pages)} pages for a single-page request",
        )
    element = pages[0]
    try:
        width_pt = float(element.attrib["width"])
        height_pt = float(element.attrib["height"])
        words = tuple(
            (
                "".join(word.itertext()),
                GlyphBox(
                    x_min_pt=float(word.attrib["xMin"]),
                    y_min_pt=float(word.attrib["yMin"]),
                    x_max_pt=float(word.attrib["xMax"]),
                    y_max_pt=float(word.attrib["yMax"]),
                ),
            )
            for word in element
            if _local_name(word) == "word"
        )
    except (KeyError, ValueError) as error:
        raise PlacementError(
            EXIT_POPPLER_FAILED, f"pdftotext -bbox reports a malformed word box: {error}"
        ) from error
    return Page(width_pt=width_pt, height_pt=height_pt, words=words)


def _local_name(element: ElementTree.Element) -> str:
    tag = element.tag
    return tag.rsplit("}", 1)[-1] if isinstance(tag, str) else ""


def match_value_word(page: Page, value_word: str) -> GlyphBox:
    """Return the one box whose text equals [value_word] exactly.

    The word text has to match as a whole word; a partial match would measure a
    different glyph run. Zero matches and more than one match both refuse a
    verdict instead of guessing.
    """
    if not value_word or value_word.split() != [value_word]:
        raise PlacementError(
            EXIT_USAGE,
            "--value-word must be exactly one word without whitespace",
        )
    matches = [box for text, box in page.words if text == value_word]
    if not matches:
        raise PlacementError(
            EXIT_WORD_NOT_FOUND,
            "the exported value is not present as one word on the requested page",
        )
    if len(matches) > 1:
        raise PlacementError(
            EXIT_WORD_AMBIGUOUS,
            f"the exported value appears {len(matches)} times on the requested "
            "page, so the match does not identify the field",
        )
    return matches[0]


def axis_check(
    page: Page, rect: FieldRect, box: GlyphBox, page_number: int
) -> tuple[bool, str]:
    """Decide whether the box and the rect share one coordinate convention.

    Two conditions have to hold: the box lies inside the page, and the box
    centre lies within the rect extended by one rect extent on each side. A 180°
    flip or a y-up reading moves the box to the mirrored side of the page, far
    beyond one rect extent; a placement difference of the size this tool
    measures cannot leave that window. The window is derived from the rect, so
    the check carries no constant of its own.
    """
    inside_page = (
        0.0 <= box.x_min_pt < box.x_max_pt <= page.width_pt
        and 0.0 <= box.y_min_pt < box.y_max_pt <= page.height_pt
    )
    if not inside_page:
        return (
            False,
            f"glyph box {_format_box(box)} lies outside page {page_number} "
            f"({page.width_pt} x {page.height_pt} pt)",
        )
    window = (
        rect.x_pt - rect.width_pt,
        rect.x_pt + 2 * rect.width_pt,
        rect.y_pt - rect.height_pt,
        rect.y_pt + 2 * rect.height_pt,
    )
    if not (
        window[0] <= box.centre_x_pt <= window[1]
        and window[2] <= box.centre_y_pt <= window[3]
    ):
        return (
            False,
            f"glyph box centre ({box.centre_x_pt:.3f}, {box.centre_y_pt:.3f}) "
            f"lies outside the rect window "
            f"x {window[0]:.3f}..{window[1]:.3f}, y {window[2]:.3f}..{window[3]:.3f}",
        )
    return (
        True,
        "box inside the page and within the rect window x "
        f"{window[0]:.3f}..{window[1]:.3f}, y {window[2]:.3f}..{window[3]:.3f}",
    )


def check_horizontal_origin(
    box: GlyphBox, expected_pt: float, tolerance_pt: float
) -> CheckPoint:
    """Compare the measured glyph-box left edge with the contract origin."""
    deviation = box.x_min_pt - expected_pt
    return CheckPoint(
        name="horizontal_origin",
        measured_pt=box.x_min_pt,
        target_pt=expected_pt,
        deviation_pt=deviation,
        tolerance_pt=tolerance_pt,
        passed=abs(deviation) <= tolerance_pt + _COMPARISON_TOLERANCE_PT,
        detail="glyph-box xMin against rect.x + padding (left alignment)",
    )


def check_vertical_baseline(
    box: GlyphBox,
    font: FontVerticalMetrics,
    font_size: float,
    expected_pt: float,
    tolerance_pt: float,
) -> tuple[CheckPoint, float, float]:
    """Compare the measured baseline with the contract baseline.

    Poppler reports the font's ascent/descent box, not the baseline, so the
    baseline is reconstructed from both box edges through the font metrics.
    Both reconstructions have to hold. They agree by construction as soon as the
    box height equals the font box height (`from_descent - from_ascent` equals
    the height difference), so the pair is not independent evidence; the
    assumption they share is checked by [check_font_box_height]. The reported
    deviation is the ascent-side one, the tighter reconstruction for a line of
    text.
    """
    from_ascent = box.y_min_pt + font.ascender_pt(font_size)
    from_descent = box.y_max_pt + font.descender_pt(font_size)
    deviations = (from_ascent - expected_pt, from_descent - expected_pt)
    return (
        CheckPoint(
            name="vertical_baseline",
            measured_pt=from_ascent,
            target_pt=expected_pt,
            deviation_pt=max(deviations, key=abs),
            tolerance_pt=tolerance_pt,
            passed=all(
                abs(deviation) <= tolerance_pt + _COMPARISON_TOLERANCE_PT
                for deviation in deviations
            ),
            detail=(
                "baseline approximations yMin + ascender and yMax + descender "
                "against rect.y + padding + 0.8 * fontSizePt"
            ),
        ),
        from_ascent,
        from_descent,
    )


def check_font_box_height(
    box: GlyphBox, font: FontVerticalMetrics, font_size: float
) -> CheckPoint:
    """Check the reported box height against the font's ascent/descent height.

    This is the check that carries the font-metric assumption of the baseline
    reconstruction: it holds exactly when the ascent/descent pair the tool reads
    from `metrics.json` is the pair the PDF's own font reports. It is read at
    the printer's resolution (`BOX_HEIGHT_TOLERANCE_PT`) and not at the 1 mm
    placement tolerance, because it compares two computations of one font metric
    rather than two positions.
    """
    expected_pt = font.box_height_pt(font_size)
    deviation = box.height_pt - expected_pt
    return CheckPoint(
        name="font_box.height",
        measured_pt=box.height_pt,
        target_pt=expected_pt,
        deviation_pt=deviation,
        tolerance_pt=BOX_HEIGHT_TOLERANCE_PT,
        passed=abs(deviation) <= BOX_HEIGHT_TOLERANCE_PT + _COMPARISON_TOLERANCE_PT,
        detail=(
            "glyph box height against (ascender - descender) * fontSizePt, the "
            "font-metric basis of the baseline reconstruction; resolution bound, "
            "not the placement tolerance"
        ),
    )


def check_containment(
    box: GlyphBox, rect: FieldRect
) -> tuple[CheckPoint, float, float]:
    """Compare the reported glyph box horizontally with the field rect.

    The left-aligned value has to start inside the rect and must not overrun its
    right edge. The vertical overflows of the same box are returned alongside,
    not judged: they are font ascent/descent geometry against a baseline the
    contract places, so they are informational numbers.
    """
    left_overflow = rect.x_pt - box.x_min_pt
    right_overflow = box.x_max_pt - rect.right_pt
    worst = max(left_overflow, right_overflow)
    point = CheckPoint(
        name="containment",
        measured_pt=float(worst),
        target_pt=0.0,
        deviation_pt=float(worst),
        tolerance_pt=0.0,
        passed=worst <= _COMPARISON_TOLERANCE_PT,
        detail=(
            "glyph box inside the field rect horizontally, exact containment by "
            "design (tolerance 0); outward overflow "
            f"left={left_overflow:.3f}, right={right_overflow:.3f} "
            "(positive means outside the rect)"
        ),
    )
    return point, rect.y_pt - box.y_min_pt, box.y_max_pt - rect.bottom_pt


def evaluate(
    *,
    page_box: Page,
    pdf: Path,
    value_word: str,
    rect: FieldRect,
    layout: LayoutConstants,
    applier_padding_pt: float,
    font: FontVerticalMetrics,
    tolerance_pt: float,
) -> PlacementReport:
    """Derive every number of the report from a parsed page and the layout."""
    if tolerance_pt <= 0:
        raise PlacementError(EXIT_USAGE, "--tolerance-pt must be positive")
    box = match_value_word(page_box, value_word)
    size_pt = font_size_pt(rect, layout)
    origin_x = expected_origin_x_pt(rect, applier_padding_pt)
    baseline_y = expected_baseline_y_pt(rect, layout, size_pt)
    horizontal = check_horizontal_origin(box, origin_x, tolerance_pt)
    vertical, baseline_from_ascent, baseline_from_descent = check_vertical_baseline(
        box, font, size_pt, baseline_y, tolerance_pt
    )
    font_box_height = check_font_box_height(box, font, size_pt)
    containment, box_overflow_top, box_overflow_bottom = check_containment(box, rect)
    axes_consistent, _ = axis_check(page_box, rect, box, rect.page)
    return PlacementReport(
        pdf=pdf,
        page=rect.page,
        field_rect=rect,
        layout=layout,
        applier_padding_pt=applier_padding_pt,
        font=font,
        font_size_pt=size_pt,
        expected_origin_x_pt=origin_x,
        expected_baseline_y_pt=baseline_y,
        glyph_box=box,
        page_box=page_box,
        value_word_length=len(value_word),
        word_matches=1,
        horizontal=horizontal,
        vertical=vertical,
        containment=containment,
        font_box_height=font_box_height,
        box_overflow_top_pt=box_overflow_top,
        box_overflow_bottom_pt=box_overflow_bottom,
        ascent_above_baseline_pt=font.ascender_pt(size_pt),
        baseline_from_ascent_pt=baseline_from_ascent,
        baseline_from_descent_pt=baseline_from_descent,
        axes_consistent=axes_consistent,
    )


def verify(
    *,
    pdf: Path,
    value_word: str,
    marker: str,
    page: int | None,
    tolerance_pt: float,
    layout_path: Path,
    applier_path: Path,
    font_metrics_path: Path,
    pdftotext: str,
) -> PlacementReport:
    """Measure one artifact and derive every number of the report."""
    if tolerance_pt <= 0:
        raise PlacementError(EXIT_USAGE, "--tolerance-pt must be positive")
    layout = read_layout_constants(layout_path)
    applier_padding_pt = read_applier_padding_pt(applier_path)
    require_matching_padding(
        layout.field_padding_pt, applier_padding_pt, layout_path, applier_path
    )
    font = read_font_vertical_metrics(font_metrics_path)
    rect = parse_field_rect_marker(marker)
    if page is not None and page != rect.page:
        raise PlacementError(
            EXIT_USAGE,
            f"--page {page} contradicts PAGE={rect.page} in the field rect marker",
        )
    document = run_pdftotext_bbox(pdf, rect.page, pdftotext)
    return evaluate(
        page_box=parse_page(document),
        pdf=pdf,
        value_word=value_word,
        rect=rect,
        layout=layout,
        applier_padding_pt=applier_padding_pt,
        font=font,
        tolerance_pt=tolerance_pt,
    )


def sha256_of(path: Path) -> str:
    """Hex SHA-256 of the measured file, so the evidence is bound to its bytes."""
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as error:
        raise PlacementError(
            EXIT_UNREADABLE_INPUT, f"cannot hash {path}: {error}"
        ) from error


def _format_box(box: GlyphBox) -> str:
    return (
        f"{box.x_min_pt:.6f},{box.y_min_pt:.6f},"
        f"{box.x_max_pt:.6f},{box.y_max_pt:.6f}"
    )


def format_report(report: PlacementReport, command: list[str]) -> list[str]:
    """Render the report as `key=value` lines, one measurement per line."""
    rect = report.field_rect
    box = report.glyph_box
    _, axes_detail = axis_check(
        report.page_box, rect, box, report.page
    )
    lines = [
        f"command={shlex.join(command)}",
        f"pdf={report.pdf}",
        f"pdf_sha256={sha256_of(report.pdf)}",
        f"page={report.page}",
        f"value_word_matches={report.word_matches}",
        f"value_word_length={report.value_word_length}",
        f"axis_convention=display space; origin at the page's top-left corner, "
        f"x to the right, y downwards; Poppler -bbox reports the same origin and "
        f"direction, so no flip is applied",
        f"page_width_pt={report.page_box.width_pt:.3f}",
        f"page_height_pt={report.page_box.height_pt:.3f}",
        f"rect_pt={rect.x_pt:.3f},{rect.y_pt:.3f},"
        f"{rect.width_pt:.3f},{rect.height_pt:.3f}",
        f"rect_centre_pt_unused={rect.x_pt + rect.width_pt / 2:.3f},"
        f"{rect.y_pt + rect.height_pt / 2:.3f}",
        f"layout_source_field_padding_pt={report.layout.field_padding_pt:.3f}",
        f"applier_text_padding_pt={report.applier_padding_pt:.3f}",
        f"layout_source_baseline_ascender_factor="
        f"{report.layout.baseline_ascender_factor:.3f}",
        f"layout_source_font_size_height_factor="
        f"{report.layout.font_size_height_factor:.3f}",
        f"layout_source_font_size_clamp_pt={report.layout.min_font_size_pt:.1f}"
        f"..{report.layout.max_font_size_pt:.1f}",
        f"font_ascender_units={report.font.ascender} "
        f"font_descender_units={report.font.descender} "
        f"font_units_per_em={report.font.units_per_em}",
        f"font_size_pt={report.font_size_pt:.3f}",
        f"glyph_box_pt={_format_box(box)}",
        f"glyph_box_width_pt={box.width_pt:.6f}",
        f"glyph_box_height_pt={box.height_pt:.6f}",
        f"font_box_height_expected_pt="
        f"{report.font.box_height_pt(report.font_size_pt):.6f}",
        f"target_origin_pt={report.expected_origin_x_pt:.3f},"
        f"{report.expected_baseline_y_pt:.3f}",
        f"informational.font_box_overflow_top_pt={report.box_overflow_top_pt:.6f}",
        f"informational.font_box_overflow_bottom_pt="
        f"{report.box_overflow_bottom_pt:.6f}",
        f"informational.ascent_above_baseline_pt="
        f"{report.ascent_above_baseline_pt:.6f}",
        f"informational.baseline_offset_from_rect_top_pt="
        f"{report.expected_baseline_y_pt - rect.y_pt:.6f}",
        f"baseline_from_ascent_pt={report.baseline_from_ascent_pt:.6f}",
        f"baseline_from_descent_pt={report.baseline_from_descent_pt:.6f}",
        f"baseline_estimate_spread_pt="
        f"{abs(report.baseline_from_ascent_pt - report.baseline_from_descent_pt):.6f}",
        f"tolerance_pt={report.horizontal.tolerance_pt:.3f}",
        f"axes_check={'consistent' if report.axes_consistent else 'inconsistent'}",
    ]
    for point in (
        report.horizontal,
        report.vertical,
        report.containment,
        report.font_box_height,
    ):
        lines.append(
            f"check.{point.name}.measured_pt={point.measured_pt:.6f} "
            f"target_pt={point.target_pt:.6f} "
            f"deviation_pt={point.deviation_pt:.6f} "
            f"tolerance_pt={point.tolerance_pt:.3f} "
            f"result={'pass' if point.passed else 'fail'}"
        )
        lines.append(f"check.{point.name}.definition={point.detail}")
    lines.append(f"check.axes.definition={axes_detail}")
    lines.append(
        f"placement_verdict={'PROVEN' if report.placement_proven else 'NOT_PROVEN'}"
    )
    lines.append(f"containment_verdict={'PASS' if report.containment.passed else 'FAIL'}")
    lines.append(f"exit_code={report.exit_code}")
    reason = (
        f"origin deviation {report.horizontal.deviation_pt:+.6f} pt and "
        f"baseline deviation {report.vertical.deviation_pt:+.6f} pt are within "
        f"{report.horizontal.tolerance_pt:.3f} pt"
        if report.horizontal.passed and report.vertical.passed
        else f"placement deviation origin {report.horizontal.deviation_pt:+.6f} pt / "
        f"baseline {report.vertical.deviation_pt:+.6f} pt exceeds "
        f"{report.horizontal.tolerance_pt:.3f} pt"
    )
    if not report.font_box_height.passed:
        reason += (
            f"; font box height check failed: "
            f"{report.font_box_height.deviation_pt:+.6f} pt against "
            f"{report.font_box_height.target_pt:.6f} pt exceeds "
            f"{report.font_box_height.tolerance_pt:.3f} pt"
        )
    if not report.axes_consistent:
        reason += f"; axis check failed: {axes_detail}"
    lines.append(f"reason={reason}")
    return lines


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Verify the placement of an exported field value against the origin "
            "the Feldexa layout code draws it at (Issue #344 A2)."
        )
    )
    parser.add_argument("--pdf", required=True, type=Path, help="artifact PDF")
    parser.add_argument(
        "--value-word",
        required=True,
        help="the exported value as one word, located with pdftotext -bbox",
    )
    parser.add_argument(
        "--field-rect-marker",
        required=True,
        help="the T334_FIELD_RECT marker of the field in milli-point",
    )
    parser.add_argument(
        "--page",
        type=int,
        default=None,
        help="page number; defaults to PAGE=… of the marker and must agree",
    )
    parser.add_argument(
        "--tolerance-pt",
        type=float,
        default=DEFAULT_TOLERANCE_PT,
        help=f"placement tolerance in points (default {DEFAULT_TOLERANCE_PT}, 1 mm)",
    )
    parser.add_argument(
        "--layout",
        type=Path,
        default=_DEFAULT_LAYOUT,
        help="layout source the plan builder's numbers are read from",
    )
    parser.add_argument(
        "--applier-source",
        type=Path,
        default=_DEFAULT_APPLIER,
        help=(
            "applier source whose TEXT_PADDING_PT the value is drawn with; its "
            "padding must agree with the layout source"
        ),
    )
    parser.add_argument(
        "--font-metrics",
        type=Path,
        default=_DEFAULT_FONT_METRICS,
        help="bundled font metrics carrying ascender/descender",
    )
    parser.add_argument(
        "--pdftotext", default="pdftotext", help="pdftotext executable"
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    arguments = build_parser().parse_args(argv)
    command = [sys.executable, *sys.argv] if argv is None else [sys.executable, *argv]
    try:
        report = verify(
            pdf=arguments.pdf,
            value_word=arguments.value_word,
            marker=arguments.field_rect_marker,
            page=arguments.page,
            tolerance_pt=arguments.tolerance_pt,
            layout_path=arguments.layout,
            applier_path=arguments.applier_source,
            font_metrics_path=arguments.font_metrics,
            pdftotext=arguments.pdftotext,
        )
        lines = format_report(report, command)
    except PlacementError as error:
        print(f"verdict=REFUSED exit_code={error.exit_code}")
        print(f"reason={error.reason}")
        return error.exit_code
    for line in lines:
        print(line)
    return report.exit_code


if __name__ == "__main__":
    sys.exit(main())
