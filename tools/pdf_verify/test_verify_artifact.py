#!/usr/bin/env python3
"""Tests for the export-artifact verification harness (T105)."""

from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import verify_artifact as va

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tools/corpus/synthetic/sf-001.pdf"
ARTIFACT = (
    ROOT
    / "specs/001-scanned-form-workflow/reports/artifacts"
    / "2026-11-26-t344-export-proof-depth/export-artifact-1.pdf"
)
HAS_POPPLER = all(shutil.which(b) for b in ("pdfinfo", "pdftotext", "pdftoppm"))


def rows(report: va.Report) -> dict[str, va.Row]:
    return {row.check: row for row in report.rows}


class ParseTest(unittest.TestCase):
    def test_per_page_sizes_and_rotation(self) -> None:
        text = (
            "Page    1 size:  595.28 x 841.89 pts (A4)\n"
            "Page    1 rot:   0\n"
            "Page    2 size:  841.89 x 595.28 pts (A4)\n"
            "Page    2 rot:   90\n"
        )
        self.assertEqual(
            [(595.28, 841.89, 0), (841.89, 595.28, 90)], va.parse_page_sizes(text, 2)
        )

    def test_single_size_fallback_reads_page_rot(self) -> None:
        text = (
            "Page size:       595.28 x 841.89 pts (A4)\n"
            "Page rot:        90\n"
        )
        self.assertEqual([(595.28, 841.89, 90)] * 2, va.parse_page_sizes(text, 2))

    def test_rotation_mismatch_is_detected(self) -> None:
        ok, detail = va.sizes_equal([(595.0, 842.0, 0)], [(595.0, 842.0, 90)])
        self.assertFalse(ok)
        self.assertIn("rot 0", detail)

    def test_size_boundary(self) -> None:
        ok, _ = va.sizes_equal([(595.0, 842.0, 0)], [(595.01, 842.0, 0)])
        self.assertTrue(ok)
        ok, _ = va.sizes_equal([(595.0, 842.0, 0)], [(595.02, 842.0, 0)])
        self.assertFalse(ok)


class GeometryFailureTest(unittest.TestCase):
    def test_page_count_mismatch_fails(self) -> None:
        report = va.Report(source="s", artifact="a")
        with mock.patch.object(va.shutil, "which", return_value="/usr/bin/pdfinfo"), \
             mock.patch.object(va, "pdf_pages", side_effect=[2, 1]):
            va.check_geometry(report, SOURCE, ARTIFACT)
        self.assertEqual("FAIL", rows(report)["page geometry"].status)

    def test_truncated_parse_is_partial(self) -> None:
        report = va.Report(source="s", artifact="a")
        with mock.patch.object(va.shutil, "which", return_value="/usr/bin/pdfinfo"), \
             mock.patch.object(va, "pdf_pages", return_value=2), \
             mock.patch.object(
                 va, "page_sizes", side_effect=[[(595.0, 842.0, 0)] * 2, [(595.0, 842.0, 0)]]
             ):
            va.check_geometry(report, SOURCE, ARTIFACT)
        self.assertEqual("PARTIAL", rows(report)["page geometry"].status)


class SourceIntegrityTest(unittest.TestCase):
    def test_match_and_mismatch(self) -> None:
        report = va.Report(source="s", artifact="a")
        va.check_source_integrity(report, SOURCE, va.sha256(SOURCE))
        self.assertEqual("PASS", rows(report)["source integrity"].status)
        report = va.Report(source="s", artifact="a")
        va.check_source_integrity(report, SOURCE, "0" * 64)
        self.assertEqual("FAIL", rows(report)["source integrity"].status)


class PrintabilityTest(unittest.TestCase):
    def test_second_engine_runs_and_can_fail(self) -> None:
        def ok(cmd, timeout=120):
            target = cmd[cmd.index("-o") + 1] if "-o" in cmd else f"{cmd[-1]}.png"
            Path(target).write_bytes(b"png")
            return mock.Mock(returncode=0, stdout="", stderr="")

        def fail(cmd, timeout=120):
            return mock.Mock(returncode=1, stdout="", stderr="boom")

        state = {"n": 0}

        def poppler_then_fail(cmd, timeout=120):
            state["n"] += 1
            return ok(cmd) if state["n"] == 1 else fail(cmd)

        report = va.Report(source="s", artifact="a")
        with mock.patch.object(va.shutil, "which", return_value="/usr/bin/tool"), \
             mock.patch.object(va, "pdf_pages", return_value=1), \
             mock.patch.object(va, "run", new=poppler_then_fail):
            va.check_printability(report, ARTIFACT, 300)
        self.assertEqual("FAIL", rows(report)["printability"].status)

        report = va.Report(source="s", artifact="a")
        with mock.patch.object(va.shutil, "which", return_value="/usr/bin/tool"), \
             mock.patch.object(va, "pdf_pages", return_value=1), \
             mock.patch.object(va, "run", new=ok):
            va.check_printability(report, ARTIFACT, 300)
        self.assertEqual("PASS", rows(report)["printability"].status)

    def test_missing_second_engine_is_partial_not_pass(self) -> None:
        report = va.Report(source="s", artifact="a")
        ok = mock.Mock(returncode=0, stdout="", stderr="")

        def which(name: str):
            return "/usr/bin/pdftoppm" if name == "pdftoppm" else None

        with mock.patch.object(va.shutil, "which", side_effect=which), \
             mock.patch.object(va, "pdf_pages", return_value=1), \
             mock.patch.object(va, "run", return_value=ok):
            va.check_printability(report, ARTIFACT, 300)
        self.assertEqual("PARTIAL", rows(report)["printability"].status)


@unittest.skipUnless(HAS_POPPLER, "Poppler tools not on PATH")
class HarnessTest(unittest.TestCase):
    def test_committed_pair_verifies_core_rows(self) -> None:
        self.assertTrue(SOURCE.is_file(), "fixture sf-001.pdf missing")
        self.assertTrue(ARTIFACT.is_file(), "artifact fixture missing")
        report = va.build_report(
            SOURCE, ARTIFACT, va.sha256(SOURCE), None, print_dpi=150
        )
        by_check = rows(report)
        self.assertEqual("PASS", by_check["page count and order"].status)
        self.assertEqual("PASS", by_check["page geometry"].status)
        self.assertEqual("PASS", by_check["no interactive controls"].status)
        self.assertEqual("PASS", by_check["text content"].status)
        self.assertEqual("PASS", by_check["source integrity"].status)
        self.assertIn("NOT_RUN", by_check["no clipping"].status)
        self.assertNotEqual("FAIL", by_check["printability"].status)
        self.assertEqual(0, report.exit_code())

    def test_interactive_control_scan_fails_on_acroform_bytes(self) -> None:
        report = va.Report(source="s", artifact="a")
        with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as handle:
            handle.write(b"%PDF-1.7\n/AcroForm /Widget\n")
            temp = Path(handle.name)
        try:
            va.check_interactive_controls(report, temp)
        finally:
            temp.unlink()
        self.assertEqual("FAIL", rows(report)["no interactive controls"].status)

    def test_expected_text_value_pass_and_fail(self) -> None:
        report = va.Report(source="s", artifact="a")
        va.check_text(report, ARTIFACT, {"fields": [{"value": "MUSTERSTADT"}]})
        self.assertEqual("PASS", rows(report)["text content"].status)
        report = va.Report(source="s", artifact="a")
        va.check_text(report, ARTIFACT, {"fields": [{"value": "ZZZ-NOT-THERE"}]})
        self.assertEqual("FAIL", rows(report)["text content"].status)

    def test_unreadable_artifact_fails_closed(self) -> None:
        with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as handle:
            handle.write(b"not a pdf at all\n")
            temp = Path(handle.name)
        try:
            report = va.build_report(SOURCE, temp, None, None, print_dpi=72)
        finally:
            temp.unlink()
        self.assertEqual("FAIL", rows(report)["input readable"].status)
        self.assertEqual(1, report.exit_code())


class UsageTest(unittest.TestCase):
    def test_missing_inputs_exit_two(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            missing = Path(tmp) / "nope.pdf"
            self.assertEqual(2, va.main(["--source", str(missing), "--artifact", str(missing)]))


if __name__ == "__main__":
    unittest.main()
