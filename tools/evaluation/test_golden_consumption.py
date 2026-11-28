#!/usr/bin/env python3
"""Host test for the T086B-R golden-consumption gate.

The committed golden `tools/evaluation/goldens/field-inventory-baseline.v1.json`
is produced and frozen by `tools/evaluation/field_inventory_baseline.dart`. Its
own regression test regenerates the snapshot and compares bytes, which proves
the producer is stable but does not prove that a *consumer* of the committed
artifact still sees the productive recognition path.

This test therefore consumes the committed bytes through
`tools/evaluation/golden_consumption_check.dart`:

  * the consumed file's SHA-256 is bound to the brief hash
    `508ed9be...5e6`; any byte change is red before any projection is read;
  * the productive bytes-level stage (`runRasterPageStage`, the entry
    `AnalyzeDocument` executes) is run over the declared synthetic corpus
    (`buildSyntheticCorpus()`), and the canonical per-page/per-field projection
    (identity, rects, proposed types, labels, cue sets, comparison counters and
    totals) must equal the golden's frozen projection byte for byte;
  * drift controls prove the gate is not vacuous: a changed rect or cue in a
    copy of the golden is red even when that copy's own hash is accepted, while
    a comment-only change to a non-projection field stays green under an
    accepted hash and red under the default binding;
  * the run is read-only: the committed golden's bytes and mtime do not change
    and no new artifacts appear next to it.

A missing Dart SDK is a hard failure, never a green skip.

Run:
  python3 -m unittest tools/evaluation/test_golden_consumption.py
  python3 tools/evaluation/test_golden_consumption.py
"""

import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "evaluation" / "golden_consumption_check.dart"
GOLDEN = (
    ROOT
    / "tools"
    / "evaluation"
    / "goldens"
    / "field-inventory-baseline.v1.json"
)
BOUND_GOLDEN_SHA256 = (
    "508ed9beed5a3844aa3ce101d378f7243b47e259cbcda72a412bbe6067f205e6"
)
DART = os.environ.get("DART") or shutil.which("dart")


def run_tool(*args, cwd=ROOT):
    return subprocess.run(
        [DART, "run", str(TOOL), *args],
        cwd=str(cwd),
        capture_output=True,
        text=True,
        timeout=600,
    )


def golden_sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class GoldenConsumptionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if DART is None:
            raise RuntimeError(
                "dart SDK not found on PATH: the T086B-R golden-consumption "
                "gate cannot run. Install the Flutter/Dart SDK or set "
                "DART=/path/to/dart. A skip would hide a missing gate."
            )
        if not pathlib.Path(DART).exists():
            raise RuntimeError(f"DART={DART} does not exist")
        if not TOOL.is_file():
            raise RuntimeError(f"tool not found: {TOOL}")
        if not GOLDEN.is_file():
            raise RuntimeError(f"golden not found: {GOLDEN}")

    def _mutated_golden(self, mutate):
        """Writes a mutated copy and returns (path, tempdir, new_sha256)."""
        directory = tempfile.mkdtemp()
        copy = pathlib.Path(directory) / "golden.json"
        payload = json.loads(GOLDEN.read_text(encoding="utf-8"))
        mutate(payload)
        copy.write_text(
            json.dumps(payload, separators=(",", ":"), ensure_ascii=False),
            encoding="utf-8",
        )
        return copy, pathlib.Path(directory), golden_sha256(copy)

    def test_consumes_the_committed_golden_and_proves_projection_equality(self):
        golden_bytes = GOLDEN.read_bytes()
        self.assertEqual(
            hashlib.sha256(golden_bytes).hexdigest(),
            BOUND_GOLDEN_SHA256,
            "the committed golden bytes no longer match the brief binding",
        )
        before_mtime = GOLDEN.stat().st_mtime_ns
        before_entries = sorted(p.name for p in GOLDEN.parent.iterdir())

        report_path = pathlib.Path(tempfile.mkdtemp()) / "consumption.json"
        result = run_tool("--json", str(report_path))
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        self.assertIn(BOUND_GOLDEN_SHA256, result.stdout)
        self.assertIn("projection EQUAL", result.stdout)
        self.assertIn("12 pages", result.stdout)

        report = json.loads(report_path.read_text(encoding="utf-8"))
        self.assertTrue(report["equal"], report["differences"])
        self.assertEqual(report["goldenSha256"], BOUND_GOLDEN_SHA256)
        self.assertEqual(report["pages"], 12)
        self.assertGreater(report["typedFields"], 0)

        # Consumption, not regeneration: nothing was rewritten or added.
        self.assertEqual(GOLDEN.read_bytes(), golden_bytes)
        self.assertEqual(GOLDEN.stat().st_mtime_ns, before_mtime)
        self.assertEqual(
            sorted(p.name for p in GOLDEN.parent.iterdir()),
            before_entries,
        )
        shutil.rmtree(report_path.parent, ignore_errors=True)

    def test_a_changed_field_rect_is_red_even_with_an_accepted_hash(self):
        def mutate(payload):
            rect = payload["pages"][0]["fields"]["candidates"][0]["rect"]
            rect["x"] = round(rect["x"] + 1.0, 6)

        copy, directory, sha = self._mutated_golden(mutate)
        try:
            report_path = pathlib.Path(directory) / "report.json"
            result = run_tool(
                "--golden",
                str(copy),
                "--golden-sha",
                sha,
                "--json",
                str(report_path),
            )
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn("projection DRIFT", result.stdout)
            report = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertFalse(report["equal"])
            self.assertTrue(report["differences"], report)
            self.assertTrue(
                any("typed field" in item for item in report["differences"]),
                report["differences"],
            )
        finally:
            shutil.rmtree(directory, ignore_errors=True)

    def test_a_changed_cue_set_is_red_even_with_an_accepted_hash(self):
        def mutate(payload):
            cues = payload["pages"][0]["fields"]["candidates"][0]["cues"]
            cues.append("golden_drift_cue")

        copy, directory, sha = self._mutated_golden(mutate)
        try:
            result = run_tool("--golden", str(copy), "--golden-sha", sha)
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn("projection DRIFT", result.stdout)
        finally:
            shutil.rmtree(directory, ignore_errors=True)

    def test_the_default_sha_binding_reds_any_byte_change(self):
        def mutate(payload):
            payload["note"] = payload["note"] + " (comment drift)"

        copy, directory, _ = self._mutated_golden(mutate)
        try:
            # The projection is untouched, so only the byte binding can catch
            # this: the default hash must reject the copy.
            result = run_tool("--golden", str(copy))
            self.assertEqual(result.returncode, 1, result.stdout)
            output = result.stdout + result.stderr
            self.assertIn("DRIFT goldenSha256", output)
            self.assertNotIn("projection EQUAL", output)
        finally:
            shutil.rmtree(directory, ignore_errors=True)

    def test_a_comment_change_stays_green_under_an_accepted_hash(self):
        """The checker consumes the projection; it does not regenerate it."""

        def mutate(payload):
            payload["note"] = payload["note"] + " (comment drift)"

        copy, directory, sha = self._mutated_golden(mutate)
        try:
            result = run_tool("--golden", str(copy), "--golden-sha", sha)
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            self.assertIn("projection EQUAL", result.stdout)
        finally:
            shutil.rmtree(directory, ignore_errors=True)

    def test_an_invalid_golden_is_an_error_not_a_pass(self):
        directory = pathlib.Path(tempfile.mkdtemp())
        try:
            broken = directory / "broken.json"
            broken.write_text("{", encoding="utf-8")
            result = run_tool(
                "--golden",
                str(broken),
                "--golden-sha",
                hashlib.sha256(broken.read_bytes()).hexdigest(),
            )
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertNotIn("projection EQUAL", result.stdout + result.stderr)

            missing = directory / "missing.json"
            result = run_tool(
                "--golden",
                str(missing),
                "--golden-sha",
                BOUND_GOLDEN_SHA256,
            )
            self.assertEqual(result.returncode, 1, result.stdout)
        finally:
            shutil.rmtree(directory, ignore_errors=True)

    def test_help_exits_zero(self):
        result = run_tool("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("golden_consumption_check.dart", result.stdout)
        self.assertIn("Evidence class: NONE", result.stdout)

    def test_usage_errors_exit_two(self):
        self.assertEqual(run_tool("--nonsense").returncode, 2)
        self.assertEqual(run_tool("--golden").returncode, 2)
        self.assertEqual(run_tool("--golden-sha", "not-a-hash").returncode, 2)

    def test_golden_sha_matches_the_brief_binding(self):
        self.assertEqual(golden_sha256(GOLDEN), BOUND_GOLDEN_SHA256)


if __name__ == "__main__":
    unittest.main()
