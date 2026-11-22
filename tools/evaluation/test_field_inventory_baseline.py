#!/usr/bin/env python3
"""Host regression test for the T264 field-inventory baseline tool.

Covers `tasks.md` T264A/T264B and the pre-declared synthetic corpus contract:
the tool draws a deterministic rights-free corpus, declares the ground truth at
draw time, runs the real `RasterAnalysis`/`GeometryDetector`/`TypeInference` plus
the T264 `FieldInventory` and `StructureComparison`, and writes

  * a run report with host-only timings and memory diagnostics labelled
    `SIMULATED`, plus the fixture/corpus/ground-truth/golden hashes, and
  * a canonical, timing-free golden snapshot that must stay byte-identical and
    that freezes the per-page/per-field projection (rects, kinds, labels, cue
    sets, per-page candidates, section grouping), not only aggregate metrics.

The test shells out to the Dart CLI, so it needs only a Dart SDK on the host and
no Flutter, Gradle, emulator, or device. A missing Dart SDK is a hard failure,
never a green skip: the byte-equality gate is the regression contract.

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
import sys
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
    "memory",
    "hashes",
    "snapshot",
}
PAGE_REQUIRED = {
    "id",
    "scenario",
    "description",
    "pageSizePt",
    "fixture",
    "groundTruth",
    "declaredGroundTruth",
    "photometricQuality",
    "candidateCount",
    "inventoryCoverage",
    "sections",
    "fields",
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
    "fixture",
    "noRegressionGate",
    "totals",
    "pages",
}
FORBIDDEN_KEYS = ("generatedAtUtc", "timings", "timingsMs", "memory")
FIELD_KEYS = {
    "expected",
    "candidates",
    "typeObservations",
    "inventory",
    "baselineMatches",
    "inventoryMatches",
}
ALL_KINDS = (
    "checkbox",
    "text",
    "number",
    "multiline",
    "date",
    "signature",
    "table_field",
    "unknown",
)
def is_sha256(value):
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


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
        # A missing toolchain must never turn the frozen-golden gate green.
        if DART is None:
            raise RuntimeError(
                "dart SDK not found on PATH: the T264A golden byte-equality "
                "gate cannot run. Install the Flutter/Dart SDK or set "
                "DART=/path/to/dart. A skip would hide a missing gate."
            )
        if not pathlib.Path(DART).exists():
            raise RuntimeError(f"DART={DART} does not exist")
        if not TOOL.is_file():
            raise RuntimeError(f"tool not found: {TOOL}")
        if not GOLDEN.is_file():
            raise RuntimeError(f"golden not found: {GOLDEN}")

    @classmethod
    def _run_once(cls):
        directory = tempfile.mkdtemp()
        run_path = pathlib.Path(directory) / "run.json"
        snapshot_path = pathlib.Path(directory) / "snapshot.json"
        result = run_tool(
            "--output",
            str(run_path),
            "--snapshot",
            str(snapshot_path),
        )
        if result.returncode != 0:
            raise AssertionError(result.stderr or result.stdout)
        report = json.loads(run_path.read_text(encoding="utf-8"))
        snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
        snapshot_bytes = snapshot_path.read_bytes()
        shutil.rmtree(directory, ignore_errors=True)
        return report, snapshot, snapshot_bytes

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
        directory = tempfile.mkdtemp()
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
        self.assertTrue(RUN_REQUIRED.issubset(report), RUN_REQUIRED - set(report))
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
        shutil.rmtree(directory, ignore_errors=True)

    def test_golden_freezes_the_per_field_projection(self):
        """The frozen artifact must carry rects, kinds, labels, cues, candidates.

        Aggregate counts cannot prove that a field kept its geometry, its type,
        its label or its cue set, which is what T086B-R/T264D must diff.
        """
        report, snapshot, _ = self._run_once()
        run_pages = {page["id"]: page for page in report["pages"]}
        for page in snapshot["pages"]:
            identifier = page["id"]
            fields = page["fields"]
            self.assertEqual(FIELD_KEYS, set(fields), identifier)
            declared = page["declaredGroundTruth"]["fieldCount"]
            self.assertEqual(declared, len(fields["expected"]), identifier)
            self.assertEqual(
                page["candidateCount"],
                len(fields["candidates"]),
                identifier,
            )
            self.assertEqual(
                len(fields["inventory"]),
                page["inventoryCoverage"]["entriesOut"],
                identifier,
            )
            for expected in fields["expected"]:
                self.assertEqual(
                    {"index", "id", "sectionId", "rect", "kind", "labelText"},
                    set(expected),
                    identifier,
                )
                self.assertEqual(
                    {"x", "y", "width", "height"},
                    set(expected["rect"]),
                    identifier,
                )
                self.assertIn(expected["kind"], ALL_KINDS)
            for observation in fields["typeObservations"]:
                self.assertEqual(
                    {"index", "rect", "proposedType", "labelText", "addedCues"},
                    set(observation),
                    identifier,
                )
                self.assertEqual(
                    observation["addedCues"],
                    sorted(set(observation["addedCues"])),
                    f"{identifier}: type-observation cues must be sorted",
                )
            for candidate in fields["candidates"]:
                self.assertEqual(
                    {"index", "sectionId", "rect", "cues", "inkCoverage"},
                    set(candidate),
                    identifier,
                )
                self.assertEqual(
                    candidate["cues"],
                    sorted(set(candidate["cues"])),
                    f"{identifier}: candidate cues must be sorted",
                )
            for entry in fields["inventory"]:
                self.assertEqual(
                    {
                        "index",
                        "id",
                        "sectionId",
                        "rect",
                        "kind",
                        "role",
                        "labelText",
                        "cues",
                        "inkCoverage",
                        "collapsedDuplicateCount",
                    },
                    set(entry),
                    identifier,
                )
                self.assertEqual(
                    entry["cues"],
                    sorted(set(entry["cues"])),
                    f"{identifier}: inventory cues must be sorted",
                )
            for branch in ("baselineMatches", "inventoryMatches"):
                for match in fields[branch]:
                    self.assertEqual(
                        {
                            "expectedIndex",
                            "observedIndex",
                            "iou",
                            "centerDistancePt",
                            "geometryOk",
                            "kindOk",
                            "labelOk",
                        },
                        set(match),
                        f"{identifier}:{branch}",
                    )
                    self.assertLess(
                        match["expectedIndex"],
                        declared,
                        f"{identifier}:{branch}",
                    )
            # The projection must be frozen in the golden, not only in run.json.
            self.assertEqual(
                fields,
                run_pages[identifier]["fields"],
                f"{identifier}: run.json and golden disagree",
            )
        # At least one page must carry real cue and label evidence.
        cues = {
            cue
            for page in snapshot["pages"]
            for entry in page["fields"]["inventory"]
            for cue in entry["cues"]
        }
        self.assertIn("underline", cues)
        labels = {
            observation["labelText"]
            for page in snapshot["pages"]
            for observation in page["fields"]["typeObservations"]
            if observation["labelText"]
        }
        self.assertIn("Straße", labels)

    def test_golden_binds_fixture_corpus_and_ground_truth_identity(self):
        report, snapshot, snapshot_bytes = self._run_once()
        fixture = snapshot["fixture"]
        self.assertEqual(
            {
                "corpusId",
                "pageCount",
                "fixtureSha256",
                "corpusSha256",
                "groundTruthSha256",
            },
            set(fixture),
        )
        self.assertEqual(fixture["corpusId"], snapshot["corpusId"])
        self.assertEqual(fixture["pageCount"], len(snapshot["pages"]))
        for key in ("fixtureSha256", "corpusSha256", "groundTruthSha256"):
            self.assertTrue(is_sha256(fixture[key]), key)
        page_hashes = set()
        for page in snapshot["pages"]:
            self.assertEqual(
                {"rasterSha256", "rasterWidthPx", "rasterHeightPx", "rasterBytes"},
                set(page["fixture"]),
            )
            self.assertTrue(is_sha256(page["fixture"]["rasterSha256"]))
            self.assertEqual(
                page["fixture"]["rasterBytes"],
                page["fixture"]["rasterWidthPx"]
                * page["fixture"]["rasterHeightPx"],
            )
            self.assertEqual(
                {"fieldCount", "groundTruthSha256"},
                set(page["groundTruth"]),
            )
            self.assertTrue(is_sha256(page["groundTruth"]["groundTruthSha256"]))
            page_hashes.add(page["fixture"]["rasterSha256"])
        self.assertEqual(len(page_hashes), len(snapshot["pages"]))
        # The run report binds the same identities and the produced golden.
        hashes = report["hashes"]
        self.assertEqual(
            {"goldenSha256", "corpusSha256", "fixtureSha256", "groundTruthSha256"},
            set(hashes),
        )
        self.assertEqual(
            hashes["goldenSha256"],
            hashlib.sha256(snapshot_bytes).hexdigest(),
        )
        self.assertEqual(
            hashes["goldenSha256"],
            hashlib.sha256(GOLDEN.read_bytes()).hexdigest(),
        )
        for key in ("corpusSha256", "fixtureSha256", "groundTruthSha256"):
            self.assertEqual(hashes[key], fixture[key], key)

    def test_run_report_records_a_real_memory_measurement(self):
        report, snapshot, _ = self._run_once()
        memory = report["memory"]
        self.assertEqual(
            {
                "note",
                "unit",
                "kernelPeakResidentKb",
                "kernelResidentKb",
                "processInfoMaxRss",
                "peakResidentSetBytes",
            },
            set(memory),
        )
        self.assertIsInstance(memory["kernelPeakResidentKb"], int)
        self.assertGreater(memory["kernelPeakResidentKb"], 0)
        self.assertGreaterEqual(
            memory["kernelPeakResidentKb"],
            memory["kernelResidentKb"],
        )
        self.assertEqual(
            memory["peakResidentSetBytes"],
            memory["kernelPeakResidentKb"] * 1024,
        )
        self.assertGreater(memory["processInfoMaxRss"], 0)
        self.assertIn("linux", memory["unit"].lower())
        # Memory is host diagnostics only and never part of the frozen golden.
        self.assertNotIn("memory", snapshot)
        for page in snapshot["pages"]:
            self.assertNotIn("memory", page)

    def test_declared_no_regression_gate_holds(self):
        report, _, _ = self._run_once()
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
        # The gate counters are extra + duplicateUnmatched, on both branches.
        totals = report["totals"]
        for branch, key in (
            ("baseline", "baselineFalsePositives"),
            ("inventory", "inventoryFalsePositives"),
        ):
            self.assertEqual(
                gate[key],
                totals[branch]["extra"] + totals[branch]["duplicateUnmatched"],
                branch,
            )

    def test_truthful_failures_and_numeric_kinds(self):
        report, snapshot, _ = self._run_once()
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
        self.assertEqual(kinds["number"]["inventory"]["typeAccuracy"], 1.0)
        self.assertEqual(kinds["table_field"]["inventory"]["typeAccuracy"], 1.0)

        # No page may claim a pass on equal counts with wrong geometry.
        for page in report["pages"]:
            for branch in ("baseline", "inventory"):
                comparison = page[branch]
                if comparison["sameCountWrongGeometry"]:
                    self.assertEqual(comparison["verdict"], "fail")

    def test_numeric_value_variant_cases_are_typed(self):
        """Negative, percentage, leading zeros and numeric/date ambiguity.

        The decimal-comma/thousands/currency labels of the `numeric-formats`
        page stay asserted as number, so the residual cannot be implied
        complete in one direction or the other.
        """
        report, snapshot, _ = self._run_once()
        report_pages = {page["id"]: page for page in report["pages"]}
        variant = report_pages["numeric-variants"]
        self.assertEqual(variant["declaredGroundTruth"]["fieldCount"], 4)
        self.assertEqual(variant["inventory"]["verdict"], "pass", variant["inventory"])

        golden = {page["id"]: page for page in snapshot["pages"]}
        fields = golden["numeric-variants"]["fields"]
        expected = [(field["id"], field["kind"]) for field in fields["expected"]]
        self.assertEqual(
            expected,
            [
                ("betrag-negativ", "number"),
                ("summe-prozent", "number"),
                ("kundennummer-nullen", "text"),
                ("datum-oder-betrag", "date"),
            ],
        )
        self.assertEqual(
            [(entry["kind"]) for entry in fields["inventory"]],
            ["number", "number", "text", "date"],
        )
        observations = {
            observation["index"]: observation
            for observation in fields["typeObservations"]
        }
        # The negative amount keeps its number typing.
        self.assertEqual(observations[0]["proposedType"], "number")
        self.assertIn("keyword_betrag", observations[0]["addedCues"])
        # The percentage keeps its number typing.
        self.assertEqual(observations[1]["proposedType"], "number")
        self.assertIn("keyword_summe", observations[1]["addedCues"])
        # Leading zeros stay text, so the value grammar cannot eat them.
        self.assertEqual(observations[2]["proposedType"], "text")
        self.assertNotIn("keyword_kundennummer", observations[2]["addedCues"])
        # The numeric/date ambiguity resolves by the documented precedence and
        # keeps both keyword cues visible, so the ambiguity is auditable.
        self.assertEqual(observations[3]["proposedType"], "date")
        self.assertIn("keyword_datum", observations[3]["addedCues"])
        self.assertIn("keyword_betrag", observations[3]["addedCues"])

        # The decimal-comma/thousands/currency label stays a number field.
        formats = golden["numeric-formats"]["fields"]
        by_label = {
            observation["labelText"]: observation["proposedType"]
            for observation in formats["typeObservations"]
        }
        self.assertEqual(by_label["Betrag (1.234,56 €)"], "number")
        self.assertEqual(by_label["Kundennummer"], "text")

    def test_per_kind_coverage_covers_all_eight_kinds(self):
        report, snapshot, _ = self._run_once()
        kinds = report["totals"]["byKind"]
        self.assertEqual(set(ALL_KINDS), set(kinds))
        for kind, row in kinds.items():
            self.assertEqual(
                {"baseline", "inventory", "corpusInstances", "absence"},
                set(row),
                kind,
            )
        # A real multiline instance is in the corpus.
        self.assertGreater(kinds["multiline"]["corpusInstances"], 0)
        self.assertGreater(kinds["multiline"]["inventory"]["matched"], 0)
        self.assertIsNone(kinds["multiline"]["absence"])
        # Kinds without a corpus instance say so instead of disappearing.
        for kind in ("signature", "unknown"):
            self.assertEqual(kinds[kind]["corpusInstances"], 0)
            self.assertIsInstance(kinds[kind]["absence"], str)
            self.assertTrue(kinds[kind]["absence"].strip())
        for kind in ALL_KINDS:
            if kinds[kind]["corpusInstances"] > 0:
                self.assertIsNone(kinds[kind]["absence"])
            else:
                self.assertIsInstance(kinds[kind]["absence"], str)
        # The corpus really declares the new multiline kind.
        declared = {
            field["kind"]
            for page in snapshot["pages"]
            for field in page["fields"]["expected"]
        }
        self.assertIn("multiline", declared)

    def test_section_dimension_is_derived_from_declared_regions(self):
        report, snapshot, _ = self._run_once()
        report_pages = {page["id"]: page for page in report["pages"]}
        for page in snapshot["pages"]:
            identifier = page["id"]
            sections = page["sections"]
            self.assertGreaterEqual(len(sections), 1, identifier)
            section_ids = [section["id"] for section in sections]
            self.assertEqual(
                len(section_ids),
                len(set(section_ids)),
                f"{identifier}: section ids must be unique",
            )
            declared_total = 0
            observed_total = 0
            for section in sections:
                self.assertEqual(
                    {"id", "label", "rect", "declared", "inventory"},
                    set(section),
                    identifier,
                )
                self.assertEqual(
                    {"fieldCount", "kinds"}, set(section["declared"])
                )
                self.assertEqual(
                    {"candidateCount", "kinds"}, set(section["inventory"])
                )
                declared_total += section["declared"]["fieldCount"]
                observed_total += section["inventory"]["candidateCount"]
                self.assertEqual(
                    sum(section["declared"]["kinds"].values()),
                    section["declared"]["fieldCount"],
                    f"{identifier}/{section['id']}",
                )
            self.assertEqual(
                declared_total,
                page["declaredGroundTruth"]["fieldCount"],
                f"{identifier}: every declared field belongs to exactly one section",
            )
            self.assertLessEqual(
                observed_total,
                page["inventoryCoverage"]["entriesOut"],
                f"{identifier}: observed entries are grouped, never invented",
            )
            for field in page["fields"]["expected"]:
                self.assertIn(
                    field["sectionId"],
                    {section["id"] for section in sections},
                    identifier,
                )
            # The projection is frozen in the golden and matches run.json.
            self.assertEqual(sections, report_pages[identifier]["sections"])
        # One page must really split into several declared sections.
        multi = [
            page["id"]
            for page in snapshot["pages"]
            if len(page["sections"]) > 1
        ]
        self.assertTrue(multi, "no page declares more than one section")

    def test_missing_dart_fails_instead_of_skipping(self):
        environment = dict(os.environ)
        environment["DART"] = "/nonexistent/dart-for-t264-gate"
        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "unittest",
                "tools/evaluation/test_field_inventory_baseline.py",
            ],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            env=environment,
            timeout=600,
        )
        self.assertNotEqual(
            result.returncode,
            0,
            "a missing Dart SDK must fail the gate, not skip it green",
        )
        self.assertNotIn("skipped", result.stderr.lower())


if __name__ == "__main__":
    unittest.main()
