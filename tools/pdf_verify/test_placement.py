#!/usr/bin/env python3
"""Unit tests for `tools/pdf_verify/placement.py` (Issue #344 A2).

The tests run without network, without an emulator, and without Poppler: the
page the tool would read from `pdftotext -bbox` is synthesised from the same
layout numbers the tool reads from the repository, so every expectation is
derived, not typed in. `test_layout_constants_match_source` reads the real
`layout.dart`, so a changed constant breaks the suite instead of silently
changing the target origin.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import placement  # noqa: E402

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
LAYOUT_PATH = REPOSITORY_ROOT / "packages/feldexa_export/lib/src/layout.dart"
FONT_METRICS_PATH = REPOSITORY_ROOT / "apps/feldexa_app/assets/fonts/metrics.json"

# The field rect of the recorded run, as the `T334_FIELD_RECT` marker carries it.
FIELD_RECT_MARKER = (
    "T334_FIELD_RECT:PAGE=1:X_MPT=190125:Y_MPT=147625:W_MPT=299875:H_MPT=18000"
)
VALUE_WORD = "Müller"
PAGE_WIDTH_PT = 595.28
PAGE_HEIGHT_PT = 841.89

#: Width of the synthetic value box; the recorded artifact measures 32.5944 pt.
VALUE_BOX_WIDTH_PT = 32.5944


def bbox_document(words: list[tuple[str, float, float, float, float]]) -> str:
    """Render one page of `pdftotext -bbox` output from word tuples."""
    body = "\n".join(
        f'    <word xMin="{x_min:.6f}" yMin="{y_min:.6f}" '
        f'xMax="{x_max:.6f}" yMax="{y_max:.6f}">{text}</word>'
        for text, x_min, y_min, x_max, y_max in words
    )
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" '
        '"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">\n'
        "<html><body><doc>\n"
        f'  <page width="{PAGE_WIDTH_PT:.6f}" height="{PAGE_HEIGHT_PT:.6f}">\n'
        f"{body}\n"
        "  </page>\n"
        "</doc></body></html>\n"
    )


class PlacementTestCase(unittest.TestCase):
    """Shared fixtures: the recorded rect and the derived target box."""

    def setUp(self) -> None:
        self.layout = placement.read_layout_constants(LAYOUT_PATH)
        self.font = placement.read_font_vertical_metrics(FONT_METRICS_PATH)
        self.rect = placement.parse_field_rect_marker(FIELD_RECT_MARKER)
        self.font_size_pt = placement.font_size_pt(self.rect, self.layout)
        self.origin_x_pt = placement.expected_origin_x_pt(self.rect, self.layout)
        self.baseline_y_pt = placement.expected_baseline_y_pt(
            self.rect, self.layout, self.font_size_pt
        )

    def box(
        self,
        *,
        dx: float = 0.0,
        dy: float = 0.0,
        width_pt: float = VALUE_BOX_WIDTH_PT,
    ) -> tuple[float, float, float, float]:
        """A value box that sits exactly on the derived target, shifted by dx/dy."""
        x_min = self.origin_x_pt + dx
        y_min = self.baseline_y_pt + dy - self.font.ascender_pt(self.font_size_pt)
        y_max = self.baseline_y_pt + dy + abs(self.font.descender_pt(self.font_size_pt))
        return x_min, y_min, x_min + width_pt, y_max

    def report(
        self, box: tuple[float, float, float, float], *, word: str = VALUE_WORD
    ):
        document = bbox_document([(word, *box)])
        return placement.evaluate(
            page_box=placement.parse_page(document),
            pdf=Path("synthetic.pdf"),
            value_word=word,
            rect=self.rect,
            layout=self.layout,
            font=self.font,
            tolerance_pt=placement.DEFAULT_TOLERANCE_PT,
        )


class DerivedTargetTest(PlacementTestCase):
    """The target origin is the number the layout code computes."""

    def test_font_size_is_the_clamped_height_factor(self) -> None:
        # 0.6 * 18.0 pt rect height, inside the 7.0 … 12.0 pt clamp.
        self.assertAlmostEqual(self.font_size_pt, 10.8, places=6)

    def test_target_origin_is_padding_left_of_the_rect(self) -> None:
        self.assertAlmostEqual(self.origin_x_pt, 191.625, places=6)

    def test_target_baseline_is_padding_plus_ascender_factor(self) -> None:
        # 147.625 + 1.5 + 0.8 * 10.8
        self.assertAlmostEqual(self.baseline_y_pt, 157.765, places=6)

    def test_font_size_clamp_bounds(self) -> None:
        small = placement.FieldRect(1, 0.0, 0.0, 10.0, 2.0)
        large = placement.FieldRect(1, 0.0, 0.0, 10.0, 400.0)
        self.assertAlmostEqual(
            placement.font_size_pt(small, self.layout), 7.0, places=6
        )
        self.assertAlmostEqual(
            placement.font_size_pt(large, self.layout), 12.0, places=6
        )

    def test_layout_constants_match_source(self) -> None:
        self.assertEqual(self.layout.field_padding_pt, 1.5)
        self.assertEqual(self.layout.baseline_ascender_factor, 0.8)
        self.assertEqual(self.layout.font_size_height_factor, 0.6)
        self.assertEqual(self.layout.min_font_size_pt, 7.0)
        self.assertEqual(self.layout.max_font_size_pt, 12.0)

    def test_font_vertical_metrics_match_source(self) -> None:
        self.assertEqual(self.font.units_per_em, 1000)
        self.assertEqual(self.font.ascender, 1069)
        self.assertEqual(self.font.descender, -293)


class ExactHitTest(PlacementTestCase):
    """A value drawn at the contract origin passes both placement points."""

    def test_exact_hit_proves_placement(self) -> None:
        report = self.report(self.box())
        self.assertTrue(report.horizontal.passed)
        self.assertTrue(report.vertical.passed)
        self.assertAlmostEqual(report.horizontal.deviation_pt, 0.0, places=6)
        self.assertAlmostEqual(report.vertical.deviation_pt, 0.0, places=6)
        self.assertTrue(report.axes_consistent)
        self.assertTrue(report.placement_proven)

    def test_baseline_is_bracketed_from_both_box_edges(self) -> None:
        report = self.report(self.box())
        self.assertAlmostEqual(
            report.baseline_from_ascent_pt, self.baseline_y_pt, places=6
        )
        self.assertAlmostEqual(
            report.baseline_from_descent_pt, self.baseline_y_pt, places=6
        )


class MillimetreBoundaryTest(PlacementTestCase):
    """The tolerance is exactly one millimetre, boundary inclusive."""

    def test_default_tolerance_is_one_millimetre(self) -> None:
        self.assertEqual(placement.DEFAULT_TOLERANCE_PT, 2.835)

    def test_origin_deviation_of_exactly_one_millimetre_passes(self) -> None:
        report = self.report(self.box(dx=placement.DEFAULT_TOLERANCE_PT))
        self.assertAlmostEqual(
            report.horizontal.deviation_pt, placement.DEFAULT_TOLERANCE_PT, places=6
        )
        self.assertTrue(report.horizontal.passed)
        self.assertTrue(report.placement_proven)

    def test_origin_deviation_beyond_one_millimetre_fails(self) -> None:
        report = self.report(self.box(dx=placement.DEFAULT_TOLERANCE_PT + 0.001))
        self.assertFalse(report.horizontal.passed)
        self.assertFalse(report.placement_proven)
        self.assertEqual(report.exit_code, placement.EXIT_CHECK_FAILED)

    def test_baseline_deviation_beyond_one_millimetre_fails(self) -> None:
        report = self.report(self.box(dy=5.0))
        self.assertTrue(report.horizontal.passed)
        self.assertFalse(report.vertical.passed)
        self.assertAlmostEqual(report.vertical.deviation_pt, 5.0, places=6)
        self.assertFalse(report.placement_proven)


class ContainmentTest(PlacementTestCase):
    """Containment judges the horizontal edges; the vertical font box is reported."""

    def test_value_inside_the_rect_passes_containment(self) -> None:
        report = self.report(self.box())
        self.assertTrue(report.containment.passed)
        self.assertTrue(report.all_checks_passed)
        self.assertEqual(report.exit_code, placement.EXIT_OK)

    def test_value_starting_left_of_the_rect_fails_containment(self) -> None:
        x_min, y_min, x_max, y_max = self.box()
        report = self.report((x_min - 3.0, y_min, x_max - 3.0, y_max))
        self.assertFalse(report.containment.passed)
        self.assertEqual(report.exit_code, placement.EXIT_CHECK_FAILED)

    def test_value_overrunning_the_right_edge_fails_containment(self) -> None:
        x_min, y_min, x_max, y_max = self.box()
        wide = self.rect.right_pt - x_min + 1.0
        report = self.report((x_min, y_min, x_min + wide, y_max))
        self.assertFalse(report.containment.passed)

    def test_font_ascent_box_protrudes_above_the_rect(self) -> None:
        report = self.report(self.box())
        # (1069/1000 - 0.8) * 10.8 - 1.5 = 1.4052 pt of ascent above the rect top.
        self.assertAlmostEqual(report.box_overflow_top_pt, 1.4052, places=3)
        self.assertLess(report.box_overflow_bottom_pt, 0.0)
        self.assertAlmostEqual(report.ascent_above_baseline_pt, 11.5452, places=3)
        self.assertAlmostEqual(
            report.expected_baseline_y_pt - self.rect.y_pt, 10.14, places=3
        )

    def test_ascent_overflow_follows_from_the_layout_formula(self) -> None:
        # The ascent alone exceeds the contract offset for every allowed font
        # size: 1.069 em - (1.5 pt + 0.8 em) > 0 for fontSizePt >= 7.0.
        for size_pt in (self.layout.min_font_size_pt, self.layout.max_font_size_pt):
            offset_pt = (
                self.layout.field_padding_pt
                + self.layout.baseline_ascender_factor * size_pt
            )
            self.assertGreater(self.font.ascender_pt(size_pt), offset_pt)


class RefusalTest(PlacementTestCase):
    """Missing or ambiguous data refuses a verdict instead of guessing."""

    def test_missing_word_refuses(self) -> None:
        page = placement.parse_page(bbox_document([(VALUE_WORD, *self.box())]))
        with self.assertRaises(placement.PlacementError) as context:
            placement.match_value_word(page, "Musteramt")
        self.assertEqual(context.exception.exit_code, placement.EXIT_WORD_NOT_FOUND)

    def test_ambiguous_word_refuses(self) -> None:
        document = bbox_document(
            [("Familienname", 56.7, 150.82, 119.49, 160.07), (VALUE_WORD, *self.box())]
        ).replace(
            "</page>",
            '    <word xMin="191.625000" yMin="300.000000" '
            'xMax="224.219400" yMax="314.709600">Müller</word>\n  </page>',
        )
        with self.assertRaises(placement.PlacementError) as context:
            placement.match_value_word(placement.parse_page(document), VALUE_WORD)
        self.assertEqual(context.exception.exit_code, placement.EXIT_WORD_AMBIGUOUS)

    def test_multi_word_argument_refuses(self) -> None:
        with self.assertRaises(placement.PlacementError) as context:
            placement.match_value_word(
                placement.parse_page(bbox_document([(VALUE_WORD, *self.box())])),
                "Max Müller",
            )
        self.assertEqual(context.exception.exit_code, placement.EXIT_USAGE)

    def test_malformed_marker_refuses(self) -> None:
        with self.assertRaises(placement.PlacementError) as context:
            placement.parse_field_rect_marker("T334_FIELD_RECT:PAGE=1:X_MPT=190125")
        self.assertEqual(context.exception.exit_code, placement.EXIT_UNREADABLE_INPUT)

    def test_marker_round_trip(self) -> None:
        rect = placement.parse_field_rect_marker(FIELD_RECT_MARKER)
        self.assertEqual(rect.page, 1)
        self.assertAlmostEqual(rect.x_pt, 190.125, places=6)
        self.assertAlmostEqual(rect.y_pt, 147.625, places=6)
        self.assertAlmostEqual(rect.width_pt, 299.875, places=6)
        self.assertAlmostEqual(rect.height_pt, 18.0, places=6)

    def test_page_contradicting_the_marker_refuses(self) -> None:
        with self.assertRaises(placement.PlacementError) as context:
            placement.verify(
                pdf=Path("synthetic.pdf"),
                value_word=VALUE_WORD,
                marker=FIELD_RECT_MARKER,
                page=2,
                tolerance_pt=placement.DEFAULT_TOLERANCE_PT,
                layout_path=LAYOUT_PATH,
                font_metrics_path=FONT_METRICS_PATH,
                pdftotext="pdftotext",
            )
        self.assertEqual(context.exception.exit_code, placement.EXIT_USAGE)

    def test_missing_pdftotext_refuses(self) -> None:
        with self.assertRaises(placement.PlacementError) as context:
            placement.verify(
                pdf=Path("synthetic.pdf"),
                value_word=VALUE_WORD,
                marker=FIELD_RECT_MARKER,
                page=None,
                tolerance_pt=placement.DEFAULT_TOLERANCE_PT,
                layout_path=LAYOUT_PATH,
                font_metrics_path=FONT_METRICS_PATH,
                pdftotext="feldexa-no-such-pdftotext",
            )
        self.assertEqual(context.exception.exit_code, placement.EXIT_POPPLER_FAILED)

    def test_unknown_layout_constant_refuses(self) -> None:
        with self.assertRaises(placement.PlacementError) as context:
            placement.read_layout_constants(LAYOUT_PATH.parent / "model/export_plan.dart")
        self.assertEqual(context.exception.exit_code, placement.EXIT_UNREADABLE_INPUT)


class AxisConventionTest(PlacementTestCase):
    """A flipped reading of the y axis must not produce a numbers-only pass."""

    def test_flipped_box_fails_the_axis_check(self) -> None:
        x_min, y_min, x_max, y_max = self.box()
        flipped = (x_min, PAGE_HEIGHT_PT - y_max, x_max, PAGE_HEIGHT_PT - y_min)
        report = self.report(flipped)
        self.assertFalse(report.axes_consistent)
        self.assertFalse(report.placement_proven)

    def test_box_outside_the_page_fails_the_axis_check(self) -> None:
        x_min, y_min, x_max, y_max = self.box()
        report = self.report((x_min, -20.0, x_max, -5.0))
        self.assertFalse(report.axes_consistent)


class LegacyCentreMetricTest(unittest.TestCase):
    """The docstring's arithmetic about the invalid centre metric holds."""

    def test_centre_deviation_is_the_half_field_overhang(self) -> None:
        rect_x_pt, rect_width_pt = 190.125, 299.875
        box_x_min_pt, box_width_pt = 191.625, 32.594
        rect_centre_pt = rect_x_pt + rect_width_pt / 2
        box_centre_pt = box_x_min_pt + box_width_pt / 2
        self.assertAlmostEqual(rect_centre_pt, 340.0625, places=4)
        self.assertAlmostEqual(box_centre_pt, 207.922, places=3)
        self.assertAlmostEqual(box_centre_pt - rect_centre_pt, -132.1405, places=4)
        self.assertAlmostEqual(
            (rect_width_pt - box_width_pt) / 2, 133.6405, places=4
        )


if __name__ == "__main__":
    unittest.main()
