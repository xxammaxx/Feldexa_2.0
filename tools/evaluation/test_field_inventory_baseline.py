#!/usr/bin/env python3
"""Host regression test for the T264 field-inventory baseline tool.

Covers `tasks.md` T264A and the pre-declared synthetic corpus contract:
the tool draws a deterministic rights-free corpus, declares the ground truth at
draw time, runs the real `RasterAnalysis`/`GeometryDetector`/`TypeInference` plus
the T264 `FieldInventory` and `StructureComparison`, and writes

  * a run report with host-only timings labelled `SIMULATED`, and
  * a canonical, timing-free golden snapshot that must stay byte-identical.

The test shells out to the Dart CLI, so it needs only a Dart SDK on the host and
no Flutter, Gradle, emulator, or device.

Run:
  python3 -m unittest tools/evaluation/test_field_inventory_baseline.py
  python3 tools/evaluation/test_field_inventory_baseline.py
"""

import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "evaluation" / "field_inventory_baseline.dart"
GOLDEN = (
    ROOT
    / "tools"
    / "evaluation"
    / "goldens"
    / "field-inventory-baseline.v1.json"
)
DART = os.environ.get("DART") or shutil.which("dart")

RUN_REQUIRED = {
    "schemaVersion",
    "corpusId",
    "evidenceClass",
    "generatedAtUtc",
    "conditions",
    "noRegressionGate",
    "totals",
    "pages",
    "timings",
    "snapshot",
}
PAGE_REQUIRED = {
    "id",
    "scenario",
    "description",
    "pageSizePt",
    "declaredGroundTruth",
    "photometricQuality",
    "candidateCount",
    "inventoryCoverage",
    "baseline",
    "inventory",
}
COMPARISON_REQUIRED = {
    "verdict",
    "failureCodes",
    "expectedCount",
    "observedCount",
    "matchedCount",
    "missingCount",
    "extraCount",
    "duplicateCount",
    "sameCountWrongGeometry",
    "metrics",
    "buckets",
}
SNAPSHOT_KEYS = {
    "schemaVersion",
    "corpusId",
    "evidenceClass",
    "generator",
    "note",
    "noRegressionGate",
    "totals",
    "pages",
}
FORBIDDEN_KEYS = ("generatedAtUtc", "timings", "timingsMs")


def run_tool(*args, cwd=ROOT):
    return subprocess.run(
        [DART, "run", str(TOOL), *args],
        cwd=str(cwd),
        capture_output=True,
        text=True,
        timeout=600,
    )


class FieldInventoryBaselineTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if DART is None:
            raise unittest.SkipTest("dart SDK is not available on PATH")
        if not TOOL.is_file():
            raise unittest.SkipTest(f"tool not found: {TOOL}")
        if not GOLDEN.is_file():
            raise unittest.SkipTest(f"golden not found: {GOLDEN}")

    def test_help_exits_zero(self):
        result = run_tool("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("field_inventory_baseline.dart", result.stdout)
        self.assertIn("SIMULATED", result.stdout)

    def test_usage_errors_exit_two(self):
        self.assertEqual(run_tool("--nonsense").returncode, 2)
        self.assertEqual(run_tool("--output").returncode, 2)
        self.assertEqual(run_tool().returncode, 2)

    def test_run_matches_the_committed_golden_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            run_path = pathlib.Path(directory) / "run.json"
            snapshot_path = pathlib.Path(directory) / "snapshot.json"
            result = run_tool(
                "--output",
                str(run_path),
                "--snapshot",
                str(snapshot_path),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(run_path.is_file())
            self.assertTrue(snapshot_path.is_file())

            report = json.loads(run_path.read_text(encoding="utf-8"))
            self.assertTrue(RUN_REQUIRED.issubset(report))
            self.assertEqual(report["evidenceClass"], "SIMULATED")
            self.assertEqual(report["conditions"]["analysisDpi"], 200)
            self.assertIsNone(report["conditions"]["ocrEngine"])
            for page in report["pages"]:
                self.assertTrue(PAGE_REQUIRED.issubset(page), page.get("id"))
                for branch in ("baseline", "inventory"):
                    self.assertTrue(
                        COMPARISON_REQUIRED.issubset(page[branch]),
                        f"{page['id']}:{branch}",
                    )
                self.assertIn("timingsMs", page)

            snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
            self.assertEqual(SNAPSHOT_KEYS, set(snapshot))
            self.assertEqual(
                snapshot,
                json.loads(GOLDEN.read_text(encoding="utf-8")),
                "the canonical snapshot drifted from the committed golden",
            )
            for key in FORBIDDEN_KEYS:
                self.assertNotIn(
                    key,
                    snapshot,
                    f"the golden snapshot must not contain {key}",
                )
                for page in snapshot["pages"]:
                    self.assertNotIn(
                        key,
                        page,
                        f"{page['id']} must not contain {key}",
                    )
            self.assertEqual(
                hashlib.sha256(snapshot_path.read_bytes()).hexdigest(),
                hashlib.sha256(GOLDEN.read_bytes()).hexdigest(),
            )

    def test_declared_no_regression_gate_holds(self):
        with tempfile.TemporaryDirectory() as directory:
            run_path = pathlib.Path(directory) / "run.json"
            result = run_tool("--output", str(run_path))
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(run_path.read_text(encoding="utf-8"))
            gate = report["noRegressionGate"]
            self.assertTrue(gate["applies"])
            self.assertTrue(gate["passed"], gate)
            self.assertGreaterEqual(
                gate["inventoryMatched"],
                gate["baselineMatched"],
            )
            self.assertLessEqual(
                gate["inventoryFalsePositives"],
                gate["baselineFalsePositives"],
            )

    def test_truthful_failures_and_numeric_kinds(self):
        with tempfile.TemporaryDirectory() as directory:
            run_path = pathlib.Path(directory) / "run.json"
            result = run_tool("--output", str(run_path))
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(run_path.read_text(encoding="utf-8"))
            pages = {page["id"]: page for page in report["pages"]}

            # The deliberately incomplete corpus page must stay a failure.
            missing = pages["missing-checkbox"]["inventory"]
            self.assertEqual(missing["verdict"], "fail")
            self.assertIn("missing_fields", missing["failureCodes"])

            # The doubled checkbox must be a duplicate, not a silent pass.
            duplicate = pages["duplicate-checkbox"]["inventory"]
            self.assertIn("duplicate_fields", duplicate["failureCodes"])

            # The furniture-only page declares zero fields and must pass empty.
            furniture = pages["furniture-only"]["inventory"]
            self.assertEqual(furniture["verdict"], "pass")
            self.assertEqual(furniture["observedCount"], 0)

            # The faint page is a declared baseline gap, not a hidden pass.
            faint = pages["low-contrast"]["inventory"]
            self.assertEqual(faint["verdict"], "fail")
            self.assertIn("missing_fields", faint["failureCodes"])

            # Numeric fields are typed explicitly and PLZ/Telefon stay text.
            kinds = report["totals"]["byKind"]
            for kind in ("number", "date", "checkbox", "table_field", "text"):
                self.assertIn(kind, kinds)
            self.assertEqual(
                kinds["number"]["inventory"]["typeAccuracy"],
                1.0,
            )
            self.assertEqual(
                kinds["table_field"]["inventory"]["typeAccuracy"],
                1.0,
            )

            # No page may claim a pass on equal counts with wrong geometry.
            for page in report["pages"]:
                for branch in ("baseline", "inventory"):
                    comparison = page[branch]
                    if comparison["sameCountWrongGeometry"]:
                        self.assertEqual(comparison["verdict"], "fail")


if __name__ == "__main__":
    unittest.main()
