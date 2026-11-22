#!/usr/bin/env python3
"""Host regression test for the T263 German OCR qualification scorer.

Covers the scorer contract from issue #263 and
`specs/001-scanned-form-workflow/research.md` D-18:

* raw-text metrics use no normalization and keep substitutions, deletions and
  insertions separate,
* the special-character confusion matrix records plausible OCR confusions
  (`StraBe` for `Straße`, missing umlaut dots) without repairing them,
* a clean reference variant must be EMULATOR production-path evidence; a
  SIMULATED run can never satisfy `--require-device-evidence`,
* an unresolved critical line is reported as UNRESOLVED and never as PASS,
* a run that does not describe the annotated PDF bytes is rejected,
* the PDF text layer is a control path that never counts as OCR evidence.

The test shells out to the Dart CLI and needs only a Dart SDK and, for the
text-layer case, Poppler `pdftotext`.

Run:
  python3 -m unittest tools/metrics/test_de_ocr_qualification.py
  python3 tools/metrics/test_de_ocr_qualification.py
"""
import json
import math
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "metrics" / "de_ocr_qualification.dart"
TEXT_LAYER_BUILDER = ROOT / "tools" / "metrics" / "build_text_layer_run.py"
GROUND_TRUTH = ROOT / "tools" / "corpus" / "de-ocr" / "reference-de.ground-truth.json"
REFERENCE_PDF = ROOT / "apps" / "feldexa_app" / "assets" / "fixtures" / "sf-005.pdf"
DART = os.environ.get("DART") or shutil.which("dart")


def load_ground_truth():
    return json.loads(GROUND_TRUTH.read_text(encoding="utf-8"))


def perfect_pages(ground_truth):
    """Builds recorded OCR lines and suggestions that exactly match the truth."""
    pages = {index: {"lines": [], "suggestions": []} for index in range(2)}
    for line in ground_truth["lines"]:
        rect = line["rect"]
        pages[line["pageIndex"]]["lines"].append(
            {
                "text": line["text"],
                "rect": {
                    "x": rect["xPt"],
                    "y": rect["yPt"] + 2,
                    "width": rect["widthPt"],
                    "height": max(2.0, rect["heightPt"] - 6),
                },
                "confidence": 0.95,
            }
        )
    for field in ground_truth["fields"]:
        rect = field["rect"]
        pages[field["pageIndex"]]["suggestions"].append(
            {
                "rect": {
                    "x": rect["xPt"],
                    "y": rect["yPt"],
                    "width": rect["widthPt"],
                    "height": rect["heightPt"],
                },
                "proposedType": field["type"],
                "labelText": field["label"],
                "cues": ["rule"],
                "resolution": "unresolved",
            }
        )
    return pages



def rotate_about_page_centre(ground_truth, page_index, x, y, degrees):
    """Maps a point from the upright page frame into the injected raster frame.

    Mirrors `tools/corpus/de-ocr/make_variants.py` `skew()`: the injector samples
    `source = c + R(-degrees)(dest - c)`, so the recorded content sits at
    `dest = c + R(+degrees)(source - c)`. That is the pair the scorer's annotation
    transform applies, and reversing it is exactly what the transform
    sensitivity test must reject.
    """
    page = next(p for p in ground_truth["pages"] if p["index"] == page_index)
    centre_x = page["widthPt"] / 2.0
    centre_y = page["heightPt"] / 2.0
    radians = math.radians(degrees)
    cos_a = math.cos(radians)
    sin_a = math.sin(radians)
    dx = x - centre_x
    dy = y - centre_y
    return (
        centre_x + dx * cos_a - dy * sin_a,
        centre_y + dx * sin_a + dy * cos_a,
    )


def build_run(ground_truth, evidence_class="SIMULATED", variant="clean-200dpi",
              mutate=None):
    pages = perfect_pages(ground_truth)
    if mutate is not None:
        mutate(pages)
    return {
        "schemaVersion": 1,
        "suiteId": ground_truth["suiteId"],
        "fixtureId": ground_truth["fixtureId"],
        "fixtureSha256": ground_truth["pdf"]["sha256"],
        "engine": "test-fixture",
        "evidenceClass": evidence_class,
        "runner": {"kind": "unit-test"},
        "generatedAtUtc": "2026-11-22T00:00:00Z",
        "variants": [
            {
                "id": variant,
                "raster": {"source": "test"},
                "timings": {},
                "pages": [
                    {
                        "index": index,
                        "widthPt": 595.28,
                        "heightPt": 841.89,
                        "lines": page["lines"],
                        "suggestions": page["suggestions"],
                    }
                    for index, page in sorted(pages.items())
                ],
            }
        ],
    }


class DeOcrQualificationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if DART is None:
            raise unittest.SkipTest("dart SDK is not available on PATH")

    def setUp(self):
        self.ground_truth = load_ground_truth()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = pathlib.Path(self.temp.name)

    def run_tool(self, *arguments):
        return subprocess.run(
            [DART, "run", str(TOOL), *arguments],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
        )

    def write_run(self, name, payload):
        path = self.directory / name
        path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        return path

    def score(self, run_path, *extra):
        report_path = self.directory / "report.json"
        result = self.run_tool(
            "--run", str(run_path), "--output", str(report_path), *extra
        )
        report = None
        if report_path.exists():
            report = json.loads(report_path.read_text(encoding="utf-8"))
        return result, report

    def test_perfect_emulator_run_scores_zero_cer(self):
        run = self.write_run(
            "perfect.json", build_run(self.ground_truth, evidence_class="EMULATOR")
        )
        result, report = self.score(run)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(report["overallVerdict"], "PASS")
        self.assertTrue(report["runs"][0]["deviceEvidence"])
        variant = report["variants"][0]
        self.assertEqual(variant["status"], "PASS")
        self.assertEqual(variant["raw"]["cer"], 0)
        self.assertEqual(
            variant["raw"]["criticalExact"], variant["raw"]["criticalLines"]
        )
        self.assertEqual(variant["raw"]["specialCharacterRecall"], 1)
        precision = {entry["character"]: entry for entry
                     in variant["raw"]["specialCharacters"]}
        for character in ("Ä", "Ö", "Ü", "ä", "ö", "ü", "ß", "ẞ", "€", "²", "³"):
            self.assertIn(character, precision)
            self.assertGreater(precision[character]["truePositives"], 0, character)
        self.assertEqual(variant["semantic"]["labelAccuracy"], 1)
        self.assertEqual(variant["semantic"]["typeAccuracy"], 1)

    def test_confusions_are_reported_and_never_repaired(self):
        def mutate(pages):
            for line in pages[0]["lines"]:
                if line["text"] == "Straße Größe Äußerung":
                    line["text"] = "StraBe GroBe AuBerung"
                if line["text"].startswith("Jürgen Mühlbach"):
                    line["text"] = line["text"].replace("ö", "o").replace("ü", "u")

        run = self.write_run("confusions.json", build_run(self.ground_truth, mutate=mutate))
        result, report = self.score(run)
        self.assertEqual(result.returncode, 1)
        variant = report["variants"][0]
        self.assertIn(variant["status"], ("FAIL", "UNRESOLVED"))
        self.assertEqual(variant["raw"]["unicode"]["sharpSAsCapitalB"], 3)
        self.assertGreater(variant["raw"]["unicode"]["missingUmlautDots"], 0)
        matrix = {
            (entry["expected"], entry["observed"], entry["kind"]): entry["count"]
            for entry in variant["raw"]["confusionMatrix"]
        }
        self.assertEqual(matrix[("ß", "B", "substitution")], 3)
        unresolved = {
            entry["lineId"]: entry for entry in variant["raw"]["criticalUnresolved"]
        }
        self.assertTrue(unresolved)
        for entry in unresolved.values():
            self.assertFalse(entry["exact"])
            self.assertIsNotNone(entry["observed"])
        # The label text stays the raw OCR text: no silent repair to Straße.
        observed_labels = [
            field["observedLabel"]
            for field in variant["semantic"]["fields"]
            if field["observedLabel"] is not None
        ]
        self.assertNotIn("Straße", observed_labels)

    def test_missing_label_keeps_uncertainty_and_is_not_a_pass(self):
        def mutate(pages):
            for suggestion in pages[1]["suggestions"]:
                if suggestion["labelText"] == "Geschäftszeichen":
                    suggestion["labelText"] = None

        run = self.write_run(
            "missing-label.json",
            build_run(self.ground_truth, evidence_class="EMULATOR", mutate=mutate),
        )
        result, report = self.score(run)
        self.assertEqual(result.returncode, 1)
        variant = report["variants"][0]
        self.assertEqual(variant["status"], "UNRESOLVED")
        self.assertEqual(variant["semantic"]["unresolvedLabels"], 1)
        unresolved = [field for field in variant["semantic"]["fields"]
                      if field["status"] == "unresolved"]
        self.assertEqual(len(unresolved), 1)
        self.assertEqual(unresolved[0]["id"], "p1-geschaeftszeichen")
        self.assertLess(variant["semantic"]["labelAccuracy"], 1)

    def test_forced_type_without_label_fails_the_variant(self):
        def mutate(pages):
            pages[1]["suggestions"].append(
                {
                    "rect": {"x": 500, "y": 700, "width": 40, "height": 18},
                    "proposedType": "date",
                    "labelText": None,
                    "cues": ["keyword_geburtsdatum"],
                    "resolution": "unresolved",
                }
            )

        run = self.write_run(
            "forced-type.json",
            build_run(self.ground_truth, evidence_class="EMULATOR", mutate=mutate),
        )
        result, report = self.score(run)
        self.assertEqual(result.returncode, 1)
        variant = report["variants"][0]
        self.assertEqual(variant["status"], "FAIL")
        self.assertEqual(variant["semantic"]["forcedTypeViolations"], 1)
        self.assertTrue(
            any("forced type" in reason for reason in variant["statusReasons"])
        )

    def test_simulated_run_never_satisfies_the_device_gate(self):
        run = self.write_run("simulated.json", build_run(self.ground_truth))
        result, report = self.score(run)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(report["overallVerdict"], "FAIL")
        self.assertFalse(report["runs"][0]["deviceEvidence"])
        self.assertTrue(
            any("not EMULATOR" in reason for reason in report["overallReasons"])
        )
        result, report = self.score(run, "--require-device-evidence")
        self.assertEqual(result.returncode, 1)
        self.assertTrue(
            any("not an on-emulator run" in reason for reason in report["overallReasons"])
        )

    def test_unexecuted_variants_are_not_run_and_never_pass(self):
        run = self.write_run(
            "partial.json", build_run(self.ground_truth, evidence_class="EMULATOR")
        )
        result, report = self.score(run)
        self.assertEqual(result.returncode, 0, result.stderr)
        statuses = {variant["id"]: variant["status"] for variant in report["variants"]}
        self.assertEqual(statuses["clean-200dpi"], "PASS")
        for variant_id, status in statuses.items():
            if variant_id != "clean-200dpi":
                self.assertEqual(status, "NOT_RUN")

    def test_run_must_describe_the_annotated_bytes(self):
        payload = build_run(self.ground_truth)
        payload["fixtureSha256"] = "0" * 64
        run = self.write_run("wrong-sha.json", payload)
        result, report = self.score(run)
        self.assertEqual(result.returncode, 2)
        self.assertIn("does not match the annotated", result.stderr)
        self.assertIsNone(report)

    def test_label_verbatimness_is_only_judged_on_the_analysis_raster(self):
        """Review B4: a label from another DPI capture is not "normalization".

        The run record's OCR lines come from the test's own call at the variant's
        capture DPI, while `AnalyzeDocument` always analyses its own 200 DPI
        raster. A differing label text therefore measures the second recognition,
        not a silent rewrite: it must be classified as not comparable and must
        never produce a FAIL reason. The reference variant is always part of the
        run so the scorer evaluates the full variant table.
        """
        def relabel(pages):
            for page in pages.values():
                for suggestion in page["suggestions"]:
                    if suggestion["labelText"] == "Geschäftszeichen":
                        suggestion["labelText"] = "Geschaeftszeichen"

        def with_variant(variant_id, dpi, mutate):
            payload = build_run(
                self.ground_truth, evidence_class="EMULATOR",
                variant=variant_id, mutate=mutate,
            )
            payload["variants"][0]["raster"] = {"source": "test", "dpi": dpi}
            return payload

        reference = with_variant("clean-200dpi", 200, None)
        for variant, dpi, expected_comparable in (
            ("clean-150dpi", 150, False),
            ("clean-300dpi", 300, False),
        ):
            with self.subTest(variant=variant):
                payload = json.loads(json.dumps(reference))
                payload["variants"].append(
                    with_variant(variant, dpi, relabel)["variants"][0]
                )
                run = self.write_run(f"{variant}.json", payload)
                result, report = self.score(run)
                variants = {v["id"]: v for v in report["variants"]}
                semantic = variants[variant]["semantic"]
                self.assertEqual(semantic["nonVerbatimLabels"], 0)
                self.assertEqual(semantic["nonVerbatimNotComparable"], 1)
                reasons = variants[variant].get("statusReasons") or []
                self.assertFalse(
                    any("verbatim" in reason for reason in reasons),
                    f"unexpected verbatim reason for {variant}: {reasons}",
                )

    def test_label_normalization_guard_fires_at_200_dpi(self):
        """B4-1: the anti-normalization guard must not silently stop firing.

        A 200 DPI capture (the raster AnalyzeDocument itself recognises) is the
        only frame where label verbatimness is comparable, so a relabelled
        suggestion there must raise the verbatim FAIL reason.
        """
        def relabel(pages):
            for page in pages.values():
                for suggestion in page["suggestions"]:
                    if suggestion["labelText"] == "Geschäftszeichen":
                        suggestion["labelText"] = "Geschaeftszeichen"

        payload = build_run(
            self.ground_truth, evidence_class="EMULATOR",
            variant="clean-200dpi", mutate=relabel,
        )
        payload["variants"][0]["raster"] = {"source": "test", "dpi": 200}
        run = self.write_run("positive-control.json", payload)
        result, report = self.score(run)
        variant = report["variants"][0]
        self.assertEqual(variant["semantic"]["nonVerbatimLabels"], 1)
        self.assertEqual(variant["semantic"]["nonVerbatimNotComparable"], 0)
        self.assertIn(
            "verbatim",
            " ".join(variant.get("statusReasons") or []),
            "the verbatim FAIL reason must fire for a 200 DPI capture",
        )
        self.assertEqual(result.returncode, 1)

    def test_skew_transform_is_frame_correct_and_sensitive(self):
        """The skew annotation transform must be right, and must stay sensitive.

        A tilted capture records OCR lines in the input-raster frame while the
        ground truth stays upright. The scorer rotates the annotation into the
        raster frame for a variant that records a known skew injection, which
        restores full line association. A wrong sign, a wrong angle or no
        transform at all must not reproduce that result.
        """
        degrees = 3.0
        payload = build_run(
            self.ground_truth, evidence_class="EMULATOR_INJECTED_RASTER",
            variant="scan-200dpi-skew-3deg",
        )
        # Move every recorded line to where the injector puts the content.
        for page in payload["variants"][0]["pages"]:
            for line in page["lines"]:
                rect = line["rect"]
                centre_x = rect["x"] + rect["width"] / 2.0
                centre_y = rect["y"] + rect["height"] / 2.0
                moved_x, moved_y = rotate_about_page_centre(
                    self.ground_truth, page["index"], centre_x, centre_y, degrees
                )
                rect["x"] = moved_x - rect["width"] / 2.0
                rect["y"] = moved_y - rect["height"] / 2.0
        payload["variants"][0]["raster"] = {
            "source": "injected-scan-simulation",
            "dpi": 200,
            "degradations": ["skew-3deg"],
        }
        run = self.write_run("skew.json", payload)

        # Frame-correct: the recorded injection drives the transform.
        result, report = self.score(run)
        variant = next(
            v for v in report["variants"] if v["id"] == "scan-200dpi-skew-3deg"
        )
        self.assertEqual(variant["groundTruthTransform"]["skewDegrees"], degrees)
        self.assertTrue(variant["groundTruthTransform"]["annotationTransformed"])
        self.assertEqual(variant["raw"]["associatedLines"], 51)
        self.assertEqual(variant["raw"]["cer"], 0.0)
        self.assertEqual(variant["status"], "PASS")

        # Sensitivity: no transform, wrong sign and a wrong angle must all lose
        # association, so the transform cannot be faked.
        for override, label in (
            ("0", "no transform"),
            (f"-{degrees}", "wrong sign"),
            (f"{degrees * 2}", "wrong angle"),
        ):
            with self.subTest(case=label):
                result, report = self.score(run, "--gt-skew-degrees", override)
                variant = next(
                    v
                    for v in report["variants"]
                    if v["id"] == "scan-200dpi-skew-3deg"
                )
                self.assertLess(
                    variant["raw"]["associatedLines"], 51,
                    f"{label} must not reproduce the frame-correct association",
                )

    def test_unknown_suite_is_rejected(self):
        payload = build_run(self.ground_truth)
        payload["suiteId"] = "de-ocr-9.9.9"
        run = self.write_run("wrong-suite.json", payload)
        result, _ = self.score(run)
        self.assertEqual(result.returncode, 2)
        self.assertIn("does not match ground-truth suite", result.stderr)

    def test_text_layer_is_a_control_path_only(self):
        if shutil.which("pdftotext") is None:
            self.skipTest("pdftotext is not available")
        text_layer_run = self.directory / "text-layer.json"
        build = subprocess.run(
            [
                "python3",
                str(TEXT_LAYER_BUILDER),
                "--pdf",
                str(REFERENCE_PDF),
                "--ground-truth",
                str(GROUND_TRUTH),
                "--output",
                str(text_layer_run),
            ],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
        )
        self.assertEqual(build.returncode, 0, build.stderr)
        result, report = self.score(text_layer_run, "--require-device-evidence")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(report["controls"]), 1)
        control = report["controls"][0]
        self.assertEqual(control["evidenceClass"], "TEXT_LAYER")
        self.assertEqual(control["status"], "PASS")
        self.assertEqual(control["cer"], 0)
        self.assertFalse(control["deviceEvidence"])
        self.assertEqual(control["missingCodePoints"], [])
        self.assertEqual(control["extraCodePoints"], [])


if __name__ == "__main__":
    unittest.main()
