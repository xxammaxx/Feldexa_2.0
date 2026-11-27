#!/usr/bin/env python3
"""Tests for the export-artifact verification harness (T105)."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import verify_artifact as va

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tools/corpus/synthetic/sf-001.pdf"
ARTIFACT = (
    ROOT
    / "specs/001-scanned-form-workflow/reports/artifacts"
    / "2026-11-26-t344-export-proof-depth/export-artifact-1.pdf"
)


def rows(report: va.Report) -> dict[str, va.Row]:
    return {row.check: row for row in report.rows}


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

    def test_missing_inputs_exit_two(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            missing = Path(tmp) / "nope.pdf"
            self.assertEqual(2, va.main(["--source", str(missing), "--artifact", str(missing)]))

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

    def test_expected_text_value_pass_and_fail(self) -> None:
        report = va.Report(source="s", artifact="a")
        va.check_text(report, ARTIFACT, {"fields": [{"value": "MUSTERSTADT"}]})
        self.assertEqual("PASS", rows(report)["text content"].status)
        report = va.Report(source="s", artifact="a")
        va.check_text(report, ARTIFACT, {"fields": [{"value": "ZZZ-NOT-THERE"}]})
        self.assertEqual("FAIL", rows(report)["text content"].status)


if __name__ == "__main__":
    unittest.main()
