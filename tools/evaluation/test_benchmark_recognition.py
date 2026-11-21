#!/usr/bin/env python3
"""Host regression test for the T063 recognition timing benchmark.

Covers the T063 contract in
`specs/001-scanned-form-workflow/tasks.md` (SC-004; research.md D-20):
mode A records supplied raster/OCR/detection timings and rejects invalid
input, mode B measures the real `GeometryDetector.detect` on a deterministic
host-synthetic raster with raster/OCR `NOT_RUN`, and neither mode invents a
timing or claims device performance.

The test shells out to the Dart CLI, so it needs only a Dart SDK on the host
and no Flutter, Gradle, emulator, or device.

Run:
  python3 -m unittest tools/evaluation/test_benchmark_recognition.py
  python3 tools/evaluation/test_benchmark_recognition.py
"""
import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "evaluation" / "benchmark_recognition.dart"
DART = os.environ.get("DART") or shutil.which("dart")

RECORDED_REQUIRED = {
    "schemaVersion",
    "mode",
    "generatedAtUtc",
    "formId",
    "pageCount",
    "dpi",
    "buildMode",
    "deviceProfile",
    "thermalState",
    "appVersion",
    "evidenceClass",
    "pages",
}
PAGE_REQUIRED = {"pageIndex", "rasterMs", "ocrMs", "detectMs", "totalMs"}
TIMING_KEYS = ("rasterMs", "ocrMs", "detectMs")
BASE_RECORDED = (
    "--form-id",
    "sf-001",
    "--device-profile",
    "host-vm",
    "--build-mode",
    "host",
)


class BenchmarkRecognitionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if DART is None:
            raise unittest.SkipTest("dart SDK is not available on PATH")
        if not TOOL.is_file():
            raise AssertionError(f"missing tool: {TOOL}")

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp = pathlib.Path(self._tmp.name)

    def run_tool(self, *args):
        return subprocess.run(
            [DART, "run", str(TOOL), *args],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=180,
        )

    def write_json(self, name, payload):
        path = self.tmp / name
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def read_json(self, path):
        return json.loads(path.read_text(encoding="utf-8"))

    def run_recorded(self, input_path, output_path, *extra):
        return self.run_tool(
            "--input",
            str(input_path),
            "--output",
            str(output_path),
            *BASE_RECORDED,
            *extra,
        )

    def test_help_documents_both_modes_and_exit_codes(self):
        result = self.run_tool("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        text = result.stdout
        self.assertIn("record a supplied run", text)
        self.assertIn("--synthetic", text)
        self.assertIn("deterministic host synthetic detection", text)
        self.assertIn("Exit codes:", text)
        for code in ("0", "1", "2"):
            self.assertIn(code, text)
        self.assertIn("no performance claim", text)

    def test_recorded_mode_writes_schema_and_totals(self):
        input_path = self.write_json(
            "run.json",
            [
                {
                    "pageIndex": 2,
                    "timings": {
                        "rasterMs": 210,
                        "ocrMs": 1180,
                        "detectMs": 430,
                        "ignored": 99,
                    },
                    "ignored": True,
                },
                {
                    "pageIndex": 0,
                    "timings": {"rasterMs": 0, "ocrMs": 0, "detectMs": 0},
                },
                {
                    "pageIndex": 1,
                    "timings": {"rasterMs": 5, "ocrMs": 6, "detectMs": 7},
                },
            ],
        )
        output_path = self.tmp / "report.json"
        result = self.run_recorded(input_path, output_path)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

        report = self.read_json(output_path)
        self.assertTrue(RECORDED_REQUIRED.issubset(report.keys()))
        self.assertEqual(report["schemaVersion"], 1)
        self.assertEqual(report["mode"], "recorded")
        self.assertEqual(report["formId"], "sf-001")
        self.assertEqual(report["pageCount"], 3)
        self.assertEqual(report["dpi"], 200)
        self.assertEqual(report["buildMode"], "host")
        self.assertEqual(report["deviceProfile"], "host-vm")
        self.assertIsNone(report["thermalState"])
        self.assertIsNone(report["appVersion"])
        self.assertEqual(report["evidenceClass"], "NONE")
        self.assertTrue(report["generatedAtUtc"].endswith("Z"))
        self.assertEqual(len(report["pages"]), 3)
        self.assertEqual([p["pageIndex"] for p in report["pages"]], [0, 1, 2])
        for page in report["pages"]:
            self.assertTrue(PAGE_REQUIRED.issubset(page.keys()))
            for key in TIMING_KEYS:
                self.assertIsInstance(page[key], int)
                self.assertGreaterEqual(page[key], 0)
            self.assertEqual(
                page["totalMs"],
                page["rasterMs"] + page["ocrMs"] + page["detectMs"],
            )
        self.assertEqual(report["pages"][2]["totalMs"], 210 + 1180 + 430)

    def test_recorded_mode_echoes_metadata(self):
        input_path = self.write_json(
            "run.json",
            [{"pageIndex": 0, "timings": dict.fromkeys(TIMING_KEYS, 1)}],
        )
        output_path = self.tmp / "report.json"
        result = self.run_recorded(
            input_path,
            output_path,
            "--thermal",
            "nominal",
            "--app-version",
            "0.1.0",
            "--evidence-class",
            "EMULATOR",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        report = self.read_json(output_path)
        self.assertEqual(report["thermalState"], "nominal")
        self.assertEqual(report["appVersion"], "0.1.0")
        self.assertEqual(report["evidenceClass"], "EMULATOR")

    def test_recorded_output_is_deterministic_apart_from_timestamp(self):
        input_path = self.write_json(
            "run.json",
            [
                {"pageIndex": 1, "timings": dict.fromkeys(TIMING_KEYS, 2)},
                {"pageIndex": 0, "timings": dict.fromkeys(TIMING_KEYS, 3)},
            ],
        )
        first = self.tmp / "first.json"
        second = self.tmp / "second.json"
        for output in (first, second):
            result = self.run_recorded(input_path, output)
            self.assertEqual(result.returncode, 0, result.stderr)
        left = self.read_json(first)
        right = self.read_json(second)
        self.assertNotEqual(left["generatedAtUtc"], "")
        left.pop("generatedAtUtc")
        right.pop("generatedAtUtc")
        self.assertEqual(left, right)

    def test_recorded_mode_rejects_invalid_input(self):
        cases = {
            "missing-timing": [
                {"pageIndex": 0, "timings": {"rasterMs": 1, "detectMs": 2}}
            ],
            "negative": [
                {
                    "pageIndex": 0,
                    "timings": {"rasterMs": -1, "ocrMs": 1, "detectMs": 2},
                }
            ],
            "non-integer": [
                {
                    "pageIndex": 0,
                    "timings": {"rasterMs": 1.5, "ocrMs": 1, "detectMs": 2},
                }
            ],
            "string-timing": [
                {
                    "pageIndex": 0,
                    "timings": {"rasterMs": "1", "ocrMs": 1, "detectMs": 2},
                }
            ],
            "empty": [],
            "not-an-array": {"pages": []},
            "non-object-page": [1],
            "invalid-page-index": [
                {
                    "pageIndex": -1,
                    "timings": {"rasterMs": 1, "ocrMs": 1, "detectMs": 2},
                }
            ],
            "duplicate-page-index": [
                {
                    "pageIndex": 0,
                    "timings": {"rasterMs": 1, "ocrMs": 1, "detectMs": 2},
                },
                {
                    "pageIndex": 0,
                    "timings": {"rasterMs": 1, "ocrMs": 1, "detectMs": 2},
                },
            ],
        }
        for name, payload in cases.items():
            with self.subTest(case=name):
                input_path = self.write_json(f"{name}.json", payload)
                output_path = self.tmp / f"{name}-out.json"
                result = self.run_recorded(input_path, output_path)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(result.stderr.startswith("error: "), result.stderr)
                self.assertFalse(output_path.exists())

    def test_recorded_mode_rejects_bad_metadata_and_class(self):
        input_path = self.write_json(
            "run.json",
            [{"pageIndex": 0, "timings": dict.fromkeys(TIMING_KEYS, 1)}],
        )
        cases = {
            "unknown-class": ("--evidence-class", "device"),
            "non-finite-metadata": ("--app-version", "1e999"),
            "blank-metadata": ("--thermal", ""),
        }
        for name, (flag, value) in cases.items():
            with self.subTest(case=name):
                output_path = self.tmp / f"{name}-out.json"
                result = self.run_recorded(input_path, output_path, flag, value)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(result.stderr.startswith("error: "), result.stderr)
                self.assertFalse(output_path.exists())

    def test_unreadable_input_and_usage_errors(self):
        output_path = self.tmp / "never.json"
        missing = self.run_recorded(self.tmp / "absent.json", output_path)
        self.assertEqual(missing.returncode, 1)
        self.assertEqual(missing.stderr, "error: input-unreadable\n")
        self.assertFalse(output_path.exists())

        input_path = self.write_json(
            "run.json",
            [{"pageIndex": 0, "timings": dict.fromkeys(TIMING_KEYS, 1)}],
        )
        usage_cases = {
            "missing-input": (
                "--output",
                str(output_path),
                *BASE_RECORDED,
            ),
            "unknown-argument": (
                "--input",
                str(input_path),
                "--output",
                str(output_path),
                *BASE_RECORDED,
                "--bogus",
                "x",
            ),
            "duplicate-argument": (
                "--input",
                str(input_path),
                "--output",
                str(output_path),
                *BASE_RECORDED,
                "--form-id",
                "sf-002",
            ),
        }
        for name, args in usage_cases.items():
            with self.subTest(case=name):
                result = self.run_tool(*args)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertTrue(result.stderr.startswith("error: "), result.stderr)
                self.assertFalse(output_path.exists())

    def run_synthetic(self, output_path, *extra):
        return self.run_tool(
            "--synthetic",
            "--output",
            str(output_path),
            *BASE_RECORDED,
            *extra,
        )

    def test_synthetic_mode_reports_host_only_conditions(self):
        output_path = self.tmp / "synthetic.json"
        result = self.run_synthetic(output_path)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = self.read_json(output_path)

        self.assertTrue(RECORDED_REQUIRED.issubset(report.keys()))
        self.assertEqual(report["schemaVersion"], 1)
        self.assertEqual(report["mode"], "synthetic")
        self.assertEqual(report["formId"], "sf-001")
        self.assertEqual(report["pageCount"], 1)
        self.assertEqual(report["dpi"], 200)
        self.assertEqual(report["deviceProfile"], "host-vm")
        self.assertEqual(report["buildMode"], "host")
        self.assertEqual(report["evidenceClass"], "SIMULATED")
        self.assertTrue(report["generatedAtUtc"].endswith("Z"))

        synthetic = report["synthetic"]
        self.assertIn("host-only", synthetic["description"])
        self.assertIn("not a device", synthetic["description"])
        self.assertEqual(synthetic["pageWidthPt"], 595.0)
        self.assertEqual(synthetic["pageHeightPt"], 842.0)
        self.assertEqual(synthetic["rasterWidthPx"], 1653)
        self.assertEqual(synthetic["rasterHeightPx"], 2339)
        self.assertGreaterEqual(synthetic["candidateCount"], 2)
        self.assertIn("GeometryDetector.detect", synthetic["timingScope"])
        self.assertIn("one warm-up", synthetic["timingScope"])

        page = report["pages"][0]
        self.assertEqual(page["pageIndex"], 0)
        self.assertIsNone(page["rasterMs"])
        self.assertIsNone(page["ocrMs"])
        self.assertIsNone(page["totalMs"])
        self.assertIsInstance(page["detectMs"], int)
        self.assertGreaterEqual(page["detectMs"], 0)
        self.assertEqual(
            page["stageStatus"],
            {
                "rasterMs": "NOT_RUN",
                "ocrMs": "NOT_RUN",
                "detectMs": "MEASURED",
            },
        )

    def test_synthetic_output_is_structurally_deterministic(self):
        first = self.tmp / "first.json"
        second = self.tmp / "second.json"
        for output in (first, second):
            result = self.run_synthetic(output)
            self.assertEqual(result.returncode, 0, result.stderr)
        left = self.read_json(first)
        right = self.read_json(second)
        for report in (left, right):
            report.pop("generatedAtUtc")
            for page in report["pages"]:
                page.pop("detectMs")
        self.assertEqual(left, right)

    def test_synthetic_mode_rejects_conflicting_evidence_and_input(self):
        output_path = self.tmp / "conflict.json"
        result = self.run_synthetic(output_path, "--evidence-class", "DEVICE")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr, "error: unknown-evidence-class\n")
        self.assertFalse(output_path.exists())

        input_path = self.write_json(
            "run.json",
            [{"pageIndex": 0, "timings": dict.fromkeys(TIMING_KEYS, 1)}],
        )
        result = self.run_synthetic(output_path, "--input", str(input_path))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(
            result.stderr, "error: input-not-allowed-with-synthetic\n"
        )
        self.assertFalse(output_path.exists())


if __name__ == "__main__":
    unittest.main()
