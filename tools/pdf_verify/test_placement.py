#!/usr/bin/env python3
"""Unit tests for `tools/pdf_verify/placement.py` (Issue #344 A2).

The tests run without network, without an emulator, and without Poppler: the
page the tool would read from `pdftotext -bbox` is synthesised from the same
layout numbers the tool reads from the repository, so every expectation is
derived, not typed in. `test_layout_constants_match_source` reads the real
`layout.dart` and `test_applier_padding_matches_the_layout_source` reads the real
`ExportPlanValidation.kt`, so a changed constant breaks the suite instead of
silently changing the target origin. Both readers are also driven against
synthetic sources: a commented-out remnant must not shadow the declaration that
compiles, and two declarations with differing values must refuse a verdict
(Review B P1-1).
"""

from __future__ import annotations

import hashlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import placement  # noqa: E402

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
LAYOUT_PATH = REPOSITORY_ROOT / "packages/feldexa_export/lib/src/layout.dart"
APPLIER_PATH = (
    REPOSITORY_ROOT
    / "apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/export"
    / "ExportPlanValidation.kt"
)
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


def source_file(directory: str, name: str, body: str) -> Path:
    """Write one synthetic source file and return its path."""
    path = Path(directory) / name
    path.write_text(body, encoding="utf-8")
    return path


class PlacementTestCase(unittest.TestCase):
    """Shared fixtures: the recorded rect and the derived target box."""

    def setUp(self) -> None:
        self.layout = placement.read_layout_constants(LAYOUT_PATH)
        self.applier_padding_pt = placement.read_applier_padding_pt(APPLIER_PATH)
        self.font = placement.read_font_vertical_metrics(FONT_METRICS_PATH)
        self.rect = placement.parse_field_rect_marker(FIELD_RECT_MARKER)
        self.font_size_pt = placement.font_size_pt(self.rect, self.layout)
        self.origin_x_pt = placement.expected_origin_x_pt(
            self.rect, self.applier_padding_pt
        )
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
            applier_padding_pt=self.applier_padding_pt,
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

    def test_applier_padding_matches_the_layout_source(self) -> None:
        # The padding exists twice: in the plan builder (layout.dart) and in the
        # applier that draws the value (TEXT_PADDING_PT). Both are pinned here.
        self.assertEqual(self.applier_padding_pt, 1.5)
        self.assertEqual(self.applier_padding_pt, self.layout.field_padding_pt)

    def test_default_sources_are_absolute_and_readable(self) -> None:
        arguments = placement.build_parser().parse_args(
            [
                "--pdf",
                "synthetic.pdf",
                "--value-word",
                VALUE_WORD,
                "--field-rect-marker",
                FIELD_RECT_MARKER,
            ]
        )
        # Independent of the working directory: the defaults resolve against the
        # repository root, not against the process CWD.
        self.assertTrue(arguments.layout.is_absolute())
        self.assertTrue(arguments.applier_source.is_absolute())
        self.assertTrue(arguments.font_metrics.is_absolute())
        self.assertEqual(
            placement.read_layout_constants(arguments.layout).field_padding_pt, 1.5
        )
        self.assertEqual(
            placement.read_applier_padding_pt(arguments.applier_source), 1.5
        )

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

    def test_baseline_spread_is_forced_by_the_box_height(self) -> None:
        # The two reconstructions are not independent evidence: their distance is
        # exactly the height difference between the reported box and the font
        # box, so a matching height forces the spread to zero.
        x_min, y_min, x_max, y_max = self.box()
        report = self.report((x_min, y_min, x_max, y_max + 0.02))
        spread = abs(
            report.baseline_from_ascent_pt - report.baseline_from_descent_pt
        )
        self.assertAlmostEqual(spread, 0.02, places=9)
        self.assertAlmostEqual(
            abs(report.vertical.deviation_pt),
            report.font_box_height.deviation_pt,
            places=9,
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

    def test_containment_is_exact_by_design(self) -> None:
        # The zero tolerance of the containment point must not read as a washed
        # out threshold; the definition line says why it is zero.
        report = self.report(self.box())
        self.assertEqual(report.containment.tolerance_pt, 0.0)
        self.assertIn(
            "exact containment by design (tolerance 0)", report.containment.detail
        )

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


class FontBoxHeightTest(PlacementTestCase):
    """The box height carries the font-metric basis of the baseline inference."""

    def test_font_box_height_matches_the_metric(self) -> None:
        report = self.report(self.box())
        self.assertEqual(report.font_box_height.name, "font_box.height")
        self.assertAlmostEqual(
            report.font_box_height.measured_pt,
            (self.font.ascender - self.font.descender)
            * self.font_size_pt
            / self.font.units_per_em,
            places=9,
        )
        self.assertAlmostEqual(report.font_box_height.deviation_pt, 0.0, places=9)
        self.assertLess(
            placement.BOX_HEIGHT_TOLERANCE_PT, placement.DEFAULT_TOLERANCE_PT
        )
        self.assertTrue(report.font_box_height.passed)

    def test_box_height_mismatch_blocks_the_verdict(self) -> None:
        # A box that is not the font's ascent/descent box invalidates the
        # baseline reconstruction, so the 1 mm verdict must not be claimed.
        x_min, y_min, x_max, y_max = self.box()
        report = self.report((x_min, y_min, x_max, y_max + 0.05))
        self.assertTrue(report.horizontal.passed)
        self.assertTrue(report.vertical.passed)
        self.assertFalse(report.font_box_height.passed)
        self.assertFalse(report.placement_proven)
        self.assertEqual(report.exit_code, placement.EXIT_CHECK_FAILED)


class PaddingParityTest(PlacementTestCase):
    """Both padding copies are read; a drift refuses a verdict."""

    def test_padding_drift_between_the_two_sources_refuses(self) -> None:
        source = LAYOUT_PATH.read_text(encoding="utf-8")
        drifted = source.replace(
            "const double exportFieldPaddingPt = 1.5;",
            "const double exportFieldPaddingPt = 2.0;",
        )
        self.assertNotEqual(drifted, source)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "layout.dart"
            path.write_text(drifted, encoding="utf-8")
            with self.assertRaises(placement.PlacementError) as context:
                placement.verify(
                    pdf=Path("synthetic.pdf"),
                    value_word=VALUE_WORD,
                    marker=FIELD_RECT_MARKER,
                    page=None,
                    tolerance_pt=placement.DEFAULT_TOLERANCE_PT,
                    layout_path=path,
                    applier_path=APPLIER_PATH,
                    font_metrics_path=FONT_METRICS_PATH,
                    pdftotext="pdftotext",
                )
        self.assertEqual(context.exception.exit_code, placement.EXIT_UNREADABLE_INPUT)
        self.assertIn("field padding differs", context.exception.reason)

    def test_unreadable_applier_source_refuses(self) -> None:
        with self.assertRaises(placement.PlacementError) as context:
            placement.read_applier_padding_pt(APPLIER_PATH.parent / "NoSuchSource.kt")
        self.assertEqual(context.exception.exit_code, placement.EXIT_UNREADABLE_INPUT)

    def test_applier_source_without_the_padding_constant_refuses(self) -> None:
        # `layout.dart` carries the padding as `const double`, not as Kotlin.
        with self.assertRaises(placement.PlacementError) as context:
            placement.read_applier_padding_pt(LAYOUT_PATH)
        self.assertEqual(context.exception.exit_code, placement.EXIT_UNREADABLE_INPUT)


class SourceConstantShadowingTest(PlacementTestCase):
    """A comment or a second declaration must not shadow the compiled constant.

    The numbers come from source files, so each reader has to see exactly the
    declaration the compiler sees: a commented-out remnant is not a declaration,
    and two declarations with differing values identify nothing at all.
    """

    APPLIER_WITH_COMMENTED_REMNANT = (
        "object ExportPlanValidator {\n"
        "    /**\n"
        "     * const val TEXT_PADDING_PT = 1.5\n"
        "     */\n"
        "    // const val TEXT_PADDING_PT = 1.5\n"
        "    const val TEXT_PADDING_PT = 2.0\n"
        "}\n"
    )

    def test_commented_out_remnant_does_not_shadow_the_applier_constant(
        self,
    ) -> None:
        # The shape of Review B P1-1: the old line is kept as a comment and the
        # real constant moves to 2.0. Reading the comment would measure against
        # 1.5 and call the drift proven.
        with tempfile.TemporaryDirectory() as directory:
            path = source_file(
                directory,
                "ExportPlanValidation.kt",
                self.APPLIER_WITH_COMMENTED_REMNANT,
            )
            self.assertEqual(placement.read_applier_padding_pt(path), 2.0)
            with self.assertRaises(placement.PlacementError) as context:
                placement.verify(
                    pdf=Path("synthetic.pdf"),
                    value_word=VALUE_WORD,
                    marker=FIELD_RECT_MARKER,
                    page=None,
                    tolerance_pt=placement.DEFAULT_TOLERANCE_PT,
                    layout_path=LAYOUT_PATH,
                    applier_path=path,
                    font_metrics_path=FONT_METRICS_PATH,
                    pdftotext="pdftotext",
                )
        self.assertEqual(context.exception.exit_code, placement.EXIT_UNREADABLE_INPUT)
        self.assertIn("field padding differs", context.exception.reason)

    def test_commented_out_remnant_does_not_shadow_the_layout_constant(self) -> None:
        source = LAYOUT_PATH.read_text(encoding="utf-8")
        drifted = source.replace(
            "const double exportFieldPaddingPt = 1.5;",
            "// const double exportFieldPaddingPt = 1.5;\n"
            "/// const double exportFieldPaddingPt = 1.5;\n"
            "const double exportFieldPaddingPt = 2.0;",
        )
        self.assertNotEqual(drifted, source)
        with tempfile.TemporaryDirectory() as directory:
            path = source_file(directory, "layout.dart", drifted)
            self.assertEqual(
                placement.read_layout_constants(path).field_padding_pt, 2.0
            )
            with self.assertRaises(placement.PlacementError) as context:
                placement.verify(
                    pdf=Path("synthetic.pdf"),
                    value_word=VALUE_WORD,
                    marker=FIELD_RECT_MARKER,
                    page=None,
                    tolerance_pt=placement.DEFAULT_TOLERANCE_PT,
                    layout_path=path,
                    applier_path=APPLIER_PATH,
                    font_metrics_path=FONT_METRICS_PATH,
                    pdftotext="pdftotext",
                )
        self.assertEqual(context.exception.exit_code, placement.EXIT_UNREADABLE_INPUT)
        self.assertIn("field padding differs", context.exception.reason)

    def test_two_applier_declarations_with_differing_values_refuse(self) -> None:
        body = (
            "object ExportPlanValidator {\n"
            "    const val TEXT_PADDING_PT = 1.5\n"
            "}\n"
            "object ExportPlanValidatorLegacy {\n"
            "    const val TEXT_PADDING_PT = 2.0\n"
            "}\n"
        )
        with tempfile.TemporaryDirectory() as directory:
            path = source_file(directory, "ExportPlanValidation.kt", body)
            with self.assertRaises(placement.PlacementError) as context:
                placement.read_applier_padding_pt(path)
        self.assertEqual(context.exception.exit_code, placement.EXIT_UNREADABLE_INPUT)
        # Both declarations are named with their lines, so the refusal is
        # diagnosable instead of a silent first hit.
        self.assertIn("line 2: 1.5", context.exception.reason)
        self.assertIn("line 5: 2.0", context.exception.reason)

    def test_two_layout_declarations_with_differing_values_refuse(self) -> None:
        body = (
            "const double exportFieldPaddingPt = 1.5;\n"
            "const double exportMaxFontSizePt = 12.0;\n"
            "const double exportFieldPaddingPt = 2.0;\n"
        )
        with tempfile.TemporaryDirectory() as directory:
            path = source_file(directory, "layout.dart", body)
            with self.assertRaises(placement.PlacementError) as context:
                placement.read_layout_constants(path)
        self.assertEqual(context.exception.exit_code, placement.EXIT_UNREADABLE_INPUT)
        self.assertIn("line 1: 1.5", context.exception.reason)
        self.assertIn("line 3: 2.0", context.exception.reason)

    def test_two_applier_declarations_with_the_same_value_are_accepted(self) -> None:
        body = (
            "object ExportPlanValidator {\n"
            "    const val TEXT_PADDING_PT = 1.5\n"
            "}\n"
            "object ExportPlanValidatorAlias {\n"
            "    const val TEXT_PADDING_PT = 1.5\n"
            "}\n"
        )
        with tempfile.TemporaryDirectory() as directory:
            path = source_file(directory, "ExportPlanValidation.kt", body)
            self.assertEqual(placement.read_applier_padding_pt(path), 1.5)

    def test_two_layout_declarations_with_the_same_value_are_accepted(self) -> None:
        body = (
            "const double exportFieldPaddingPt = 1.5;\n"
            "const double _baselineAscenderFactor = 0.8;\n"
            "const double _fontSizeHeightFactor = 0.6;\n"
            "const double exportMinFontSizePt = 7.0;\n"
            "const double exportMaxFontSizePt = 12.0;\n"
            "const double exportFieldPaddingPt = 1.5;\n"
        )
        with tempfile.TemporaryDirectory() as directory:
            path = source_file(directory, "layout.dart", body)
            constants = placement.read_layout_constants(path)
        self.assertEqual(constants.field_padding_pt, 1.5)
        self.assertEqual(constants.max_font_size_pt, 12.0)

    def test_the_repository_sources_still_read_and_prove(self) -> None:
        # The unchanged normal case keeps its numbers and its exit code: the
        # anchoring must not turn the real files into a refusal.
        self.assertEqual(self.layout.field_padding_pt, 1.5)
        self.assertEqual(self.applier_padding_pt, 1.5)
        self.assertAlmostEqual(self.origin_x_pt, 191.625, places=6)
        self.assertAlmostEqual(self.baseline_y_pt, 157.765, places=6)
        self.assertEqual(self.report(self.box()).exit_code, placement.EXIT_OK)


class OutputContractTest(PlacementTestCase):
    """The report binds the measurement to the bytes it measured."""

    def measured_report(self, pdf: Path):
        return placement.evaluate(
            page_box=placement.parse_page(bbox_document([(VALUE_WORD, *self.box())])),
            pdf=pdf,
            value_word=VALUE_WORD,
            rect=self.rect,
            layout=self.layout,
            applier_padding_pt=self.applier_padding_pt,
            font=self.font,
            tolerance_pt=placement.DEFAULT_TOLERANCE_PT,
        )

    def test_report_binds_the_pdf_digest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            pdf = Path(directory) / "artifact.pdf"
            pdf.write_bytes(b"%PDF-1.7 synthetic artifact\n")
            digest = hashlib.sha256(pdf.read_bytes()).hexdigest()
            lines = placement.format_report(
                self.measured_report(pdf), ["placement.py", "--pdf", str(pdf)]
            )
        self.assertIn(f"pdf_sha256={digest}", lines)
        self.assertIn(f"pdf={pdf}", lines)

    def test_report_prints_both_padding_sources_and_the_height_check(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            pdf = Path(directory) / "artifact.pdf"
            pdf.write_bytes(b"%PDF-1.7 synthetic artifact\n")
            text = "\n".join(
                placement.format_report(self.measured_report(pdf), ["placement.py"])
            )
        self.assertIn("applier_text_padding_pt=1.500", text)
        self.assertIn("layout_source_field_padding_pt=1.500", text)
        # The whole line is pinned: measured and target height, and the
        # resolution bound (0.001 pt) instead of the placement tolerance.
        self.assertRegex(
            text,
            r"check\.font_box\.height\.measured_pt=14\.709600 "
            r"target_pt=14\.709600 deviation_pt=[-+]?0\.000000 "
            r"tolerance_pt=0\.001 result=pass",
        )


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
                applier_path=APPLIER_PATH,
                font_metrics_path=FONT_METRICS_PATH,
                pdftotext="pdftotext",
            )
        self.assertEqual(context.exception.exit_code, placement.EXIT_USAGE)

    def test_non_positive_tolerance_refuses(self) -> None:
        # --tolerance-pt <= 0 is a usage error, not a zero-width measurement.
        for tolerance_pt in (0.0, -1.0):
            with self.assertRaises(placement.PlacementError) as context:
                placement.verify(
                    pdf=Path("synthetic.pdf"),
                    value_word=VALUE_WORD,
                    marker=FIELD_RECT_MARKER,
                    page=None,
                    tolerance_pt=tolerance_pt,
                    layout_path=LAYOUT_PATH,
                    applier_path=APPLIER_PATH,
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
                applier_path=APPLIER_PATH,
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
