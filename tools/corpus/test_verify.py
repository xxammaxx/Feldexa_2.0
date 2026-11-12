#!/usr/bin/env python3
"""Local verification suite for the T008 corpus manifest verifier.

Run with:
    tools/corpus/verify_test.sh
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
VERIFY = SCRIPT_DIR / "verify.sh"
SCHEMA = SCRIPT_DIR / "manifest.schema.json"

# A tiny, deterministic synthetic PDF-shaped payload. The verifier checks bytes,
# not PDF validity; the real corpus is assembled under T033.
PDF_BYTES = b"""%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [] /Count 0 >>
endobj
trailer
<< /Root 1 0 R >>
%%EOF
"""


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class CorpusBuilder:
    """Build a manifest and matching files inside a temporary corpus root."""

    def __init__(self, root: Path) -> None:
        self.root = root
        (root / "forms").mkdir(parents=True, exist_ok=True)
        self.manifest = {
            "schemaVersion": "1.0.0",
            "corpusVersion": "corpus-1.0.0",
            "metricDefinitionVersion": "metric-definition.v1",
            "description": "Synthetic fixture corpus used to test the T008 verifier.",
            "freeze": {
                "frozenAt": "2026-03-01T00:00:00Z",
                "frozenBy": "T008 verification suite",
                "groundTruthIndependentOfDetector": True,
                "disputedFieldsResolvedBeforeScoring": True,
                "changePolicy": (
                    "Any change requires a new corpus version and a separately "
                    "reported evaluation."
                ),
            },
            "forms": [],
        }

    def add_form(
        self,
        kind: str = "synthetic",
        *,
        form_id: str | None = None,
        path: str | None = None,
        data: bytes | None = None,
        create_file: bool = True,
        **overrides: object,
    ) -> dict:
        index = len(self.manifest["forms"])
        form_id = form_id or f"{kind}-{index:03d}"
        relative_path = path or f"forms/{form_id}.pdf"
        payload = data if data is not None else PDF_BYTES + form_id.encode("utf-8")

        if create_file:
            target = self.root / relative_path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(payload)

        form = {
            "id": form_id,
            "kind": kind,
            "path": relative_path,
            "sha256": sha256(payload),
            "sizeBytes": len(payload),
            "pageCount": 1,
            "provenance": {
                "source": (
                    "Synthetic fixture generator"
                    if kind == "synthetic"
                    else "https://example.invalid/german-authority-form"
                ),
                "retrievalDate": "2026-01-15",
                "legalBasis": (
                    "synthetic; no third-party content"
                    if kind == "synthetic"
                    else "§ 5 UrhG"
                ),
                "rightsCleared": True,
                "containsPersonalData": False,
            },
            "pages": [
                {
                    "index": 0,
                    "widthPt": 595.0,
                    "heightPt": 842.0,
                    "rotation": 0,
                }
            ],
            "groundTruth": {
                "fields": [
                    {
                        "id": "field-1",
                        "type": "text",
                        "pageIndex": 0,
                        "rect": {
                            "xPt": 50.0,
                            "yPt": 60.0,
                            "widthPt": 120.0,
                            "heightPt": 18.0,
                        },
                    }
                ]
            },
        }
        if kind == "real":
            form["verification"] = {
                "verifiedBy": "Independent Reviewer",
                "verifiedAt": "2026-02-01T10:00:00Z",
                "method": "Independent manual field inventory against the rendered page.",
                "independentOfDetector": True,
                "disputedFieldsResolved": True,
            }
        else:
            form["synthetic"] = {
                "generator": "tools/corpus/synthetic/generate.dart",
                "seed": index,
            }
        form.update(overrides)
        self.manifest["forms"].append(form)
        return form

    def add_real_forms(self, count: int) -> None:
        for _ in range(count):
            self.add_form("real")

    def write(self, name: str = "manifest.json") -> Path:
        target = self.root / name
        target.write_text(json.dumps(self.manifest, indent=2) + "\n", encoding="utf-8")
        return target


class VerifyTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.mkdtemp(prefix="feldexa-corpus-")
        self.root = Path(self._tmp)
        self.addCleanup(shutil.rmtree, self._tmp, ignore_errors=True)
        self.builder = CorpusBuilder(self.root)
        self.manifest_path = self.builder.write()

    def run_verify(
        self,
        *args: str,
        manifest: Path | None = None,
        corpus_dir: Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        command = [
            "bash",
            str(VERIFY),
            "--manifest",
            str(manifest or self.manifest_path),
            "--corpus-dir",
            str(corpus_dir or self.root),
            *args,
        ]
        return subprocess.run(command, text=True, capture_output=True, check=False)

    def assert_fails(self, process: subprocess.CompletedProcess[str], needle: str) -> None:
        output = (process.stdout + process.stderr).lower()
        self.assertEqual(
            process.returncode,
            1,
            f"expected exit 1, got {process.returncode}\nstdout:\n{process.stdout}\nstderr:\n{process.stderr}",
        )
        self.assertIn(needle.lower(), output)
        self.assertIn("fail", output)

    # -- passing cases ------------------------------------------------------

    def test_valid_synthetic_corpus_passes(self) -> None:
        self.builder.add_form("synthetic")
        self.builder.write()
        process = self.run_verify("--min-real-forms", "0")
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        self.assertIn("PASS", process.stdout)

    def test_valid_frozen_real_corpus_passes(self) -> None:
        self.builder.add_real_forms(20)
        self.builder.write()
        process = self.run_verify("--min-real-forms", "20")
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        self.assertIn("20 real", process.stdout)

    def test_json_success_reports_counts(self) -> None:
        self.builder.add_form("synthetic")
        self.builder.write()
        process = self.run_verify("--min-real-forms", "0", "--json")
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        payload = json.loads(process.stdout)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["counts"]["forms"], 1)
        self.assertEqual(payload["counts"]["fields"], 1)
        self.assertEqual(payload["failures"], [])

    def test_help_exits_zero(self) -> None:
        process = subprocess.run(
            ["bash", str(VERIFY), "--help"], text=True, capture_output=True, check=False
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertIn("usage:", process.stdout.lower())

    # -- checksum and file-integrity failures -------------------------------

    def test_checksum_mismatch_fails(self) -> None:
        form = self.builder.add_form("synthetic")
        self.builder.write()
        (self.root / form["path"]).write_bytes(b"tampered bytes")
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "checksum mismatch")

    def test_size_mismatch_fails(self) -> None:
        form = self.builder.add_form("synthetic")
        form["sizeBytes"] = int(form["sizeBytes"]) + 1
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "size mismatch")

    def test_missing_form_file_fails(self) -> None:
        form = self.builder.add_form("synthetic")
        self.builder.write()
        (self.root / form["path"]).unlink()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "file not found")

    def test_duplicate_sha256_fails(self) -> None:
        payload = PDF_BYTES + b"same-content"
        self.builder.add_form("synthetic", data=payload)
        self.builder.add_form("synthetic", data=payload)
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "duplicate sha256")

    def test_symlink_form_path_fails(self) -> None:
        first = self.builder.add_form("synthetic")
        payload = (self.root / first["path"]).read_bytes()
        self.builder.add_form("synthetic", form_id="synthetic-link", path="forms/link.pdf", data=payload, create_file=False)
        self.builder.write()
        os.symlink(self.root / first["path"], self.root / "forms" / "link.pdf")
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "symlink")

    # -- manifest-structure failures ---------------------------------------

    def test_invalid_json_fails(self) -> None:
        self.manifest_path.write_text("{", encoding="utf-8")
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "not valid json")

    def test_missing_manifest_fails(self) -> None:
        missing = self.root / "does-not-exist.json"
        self.assert_fails(self.run_verify(manifest=missing), "manifest not found")

    def test_duplicate_form_id_fails(self) -> None:
        self.builder.add_form("synthetic", form_id="same-id")
        self.builder.add_form("synthetic", form_id="same-id")
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "duplicate id")

    def test_duplicate_form_path_fails(self) -> None:
        self.builder.add_form("synthetic")
        self.builder.add_form("synthetic", path="forms/synthetic-000.pdf")
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "duplicate path")

    def test_parent_traversal_path_fails(self) -> None:
        self.builder.add_form("synthetic", path="forms/../../escape.pdf", create_file=False)
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "parent traversal")

    def test_unknown_property_fails(self) -> None:
        form = self.builder.add_form("synthetic")
        form["unexpected"] = True
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "unexpected property")

    def test_page_indices_must_be_contiguous(self) -> None:
        form = self.builder.add_form("synthetic")
        form["pages"][0]["index"] = 1
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "page indices")

    def test_rectangle_outside_page_fails(self) -> None:
        form = self.builder.add_form("synthetic")
        form["groundTruth"]["fields"][0]["rect"] = {
            "xPt": 500.0,
            "yPt": 60.0,
            "widthPt": 200.0,
            "heightPt": 18.0,
        }
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "extends beyond")

    def test_empty_ground_truth_fails(self) -> None:
        form = self.builder.add_form("synthetic")
        form["groundTruth"]["fields"] = []
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "no ground-truth fields")

    # -- non-finite and overflowing numbers --------------------------------

    def test_nan_rectangle_fails(self) -> None:
        form = self.builder.add_form("synthetic")
        form["groundTruth"]["fields"][0]["rect"]["xPt"] = float("nan")
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "non-finite")

    def test_positive_infinity_rectangle_fails(self) -> None:
        form = self.builder.add_form("synthetic")
        form["groundTruth"]["fields"][0]["rect"]["widthPt"] = float("inf")
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "non-finite")

    def test_negative_infinity_rectangle_fails(self) -> None:
        form = self.builder.add_form("synthetic")
        form["groundTruth"]["fields"][0]["rect"]["yPt"] = float("-inf")
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "non-finite")

    def test_float_overflow_in_rectangle_fails(self) -> None:
        self.builder.add_form("synthetic")
        self.builder.write()
        text = self.manifest_path.read_text(encoding="utf-8")
        self.assertIn('"xPt": 50.0', text)
        self.manifest_path.write_text(
            text.replace('"xPt": 50.0', '"xPt": 1e400', 1), encoding="utf-8"
        )
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "non-finite")

    def test_huge_integer_rectangle_fails(self) -> None:
        form = self.builder.add_form("synthetic")
        form["groundTruth"]["fields"][0]["rect"]["xPt"] = 10**400
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "too large")

    def test_huge_integer_size_bytes_fails(self) -> None:
        form = self.builder.add_form("synthetic")
        form["sizeBytes"] = 10**400
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "too large")

    def test_nan_outside_geometry_fails(self) -> None:
        self.builder.add_form("synthetic")
        self.builder.manifest["description"] = float("nan")
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "non-finite")

    def test_nan_size_bytes_fails(self) -> None:
        form = self.builder.add_form("synthetic")
        form["sizeBytes"] = float("nan")
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "non-finite")

    # -- JSON type-aware const/enum equality -------------------------------

    def test_numeric_rights_cleared_fails(self) -> None:
        form = self.builder.add_form("real")
        form["provenance"]["rightsCleared"] = 1
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "rightsCleared")

    def test_numeric_contains_personal_data_fails(self) -> None:
        form = self.builder.add_form("real")
        form["provenance"]["containsPersonalData"] = 0
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "containsPersonalData")

    def test_numeric_freeze_independence_fails(self) -> None:
        self.builder.add_form("synthetic")
        self.builder.manifest["freeze"]["groundTruthIndependentOfDetector"] = 1
        self.builder.write()
        self.assert_fails(
            self.run_verify("--min-real-forms", "0"), "groundTruthIndependentOfDetector"
        )

    def test_numeric_freeze_dispute_resolution_fails(self) -> None:
        self.builder.add_form("synthetic")
        self.builder.manifest["freeze"]["disputedFieldsResolvedBeforeScoring"] = 0
        self.builder.write()
        self.assert_fails(
            self.run_verify("--min-real-forms", "0"),
            "disputedFieldsResolvedBeforeScoring",
        )

    def test_numeric_verification_independence_fails(self) -> None:
        form = self.builder.add_form("real")
        form["verification"]["independentOfDetector"] = 1
        self.builder.write()
        self.assert_fails(
            self.run_verify("--min-real-forms", "0"), "independentOfDetector"
        )

    def test_numeric_verification_dispute_resolution_fails(self) -> None:
        form = self.builder.add_form("real")
        form["verification"]["disputedFieldsResolved"] = 0
        self.builder.write()
        self.assert_fails(
            self.run_verify("--min-real-forms", "0"), "disputedFieldsResolved"
        )

    def test_boolean_rotation_zero_fails(self) -> None:
        form = self.builder.add_form("synthetic")
        form["pages"][0]["rotation"] = False
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "rotation")

    def test_boolean_page_count_fails(self) -> None:
        form = self.builder.add_form("synthetic")
        form["pageCount"] = True
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "expected integer")

    def test_boolean_size_bytes_fails(self) -> None:
        form = self.builder.add_form("synthetic")
        form["sizeBytes"] = True
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "expected integer")

    def test_unique_items_uses_numeric_json_equality(self) -> None:
        form = self.builder.add_form("synthetic")
        form["strata"] = [1, 1.0]
        self.builder.write()
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        schema["$defs"]["form"]["properties"]["strata"]["items"] = {"type": "number"}
        schema_path = self.root / "numeric-strata-schema.json"
        schema_path.write_text(json.dumps(schema), encoding="utf-8")
        process = subprocess.run(
            [
                "bash",
                str(VERIFY),
                "--manifest",
                str(self.manifest_path),
                "--corpus-dir",
                str(self.root),
                "--schema",
                str(schema_path),
                "--min-real-forms",
                "0",
            ],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assert_fails(process, "duplicate item")

    # -- provenance and freeze failures ------------------------------------

    def test_real_form_with_personal_data_fails(self) -> None:
        form = self.builder.add_form("real")
        form["provenance"]["containsPersonalData"] = True
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "containsPersonalData")

    def test_real_form_without_rights_clearance_fails(self) -> None:
        form = self.builder.add_form("real")
        form["provenance"]["rightsCleared"] = False
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "rightscleared")

    def test_real_form_missing_verification_fails(self) -> None:
        form = self.builder.add_form("real")
        del form["verification"]
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "verification")

    def test_verification_after_freeze_fails(self) -> None:
        form = self.builder.add_form("real")
        form["verification"]["verifiedAt"] = "2027-01-01T00:00:00Z"
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "after the corpus was frozen")

    def test_naive_verification_timestamp_fails(self) -> None:
        form = self.builder.add_form("real")
        form["verification"]["verifiedAt"] = "2026-02-01T10:00:00"
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "timezone")

    def test_retrieval_after_verification_fails(self) -> None:
        form = self.builder.add_form("real")
        form["provenance"]["retrievalDate"] = "2026-02-15"
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "retrievaldate is after")

    def test_too_few_real_forms_fails(self) -> None:
        self.builder.add_real_forms(19)
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "20"), "at least 20 required")

    def test_expected_corpus_version_mismatch_fails(self) -> None:
        self.builder.add_form("synthetic")
        self.builder.write()
        self.assert_fails(
            self.run_verify("--min-real-forms", "0", "--expected-corpus-version", "corpus-2.0.0"),
            "corpusversion mismatch",
        )

    def test_unsupported_schema_version_fails(self) -> None:
        self.builder.add_form("synthetic")
        self.builder.manifest["schemaVersion"] = "2.0.0"
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "must equal '1.0.0'")

    def test_non_positive_page_size_fails(self) -> None:
        form = self.builder.add_form("synthetic")
        form["pages"][0]["widthPt"] = 0
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "must be > 0")

    def test_negative_rect_origin_fails(self) -> None:
        form = self.builder.add_form("synthetic")
        form["groundTruth"]["fields"][0]["rect"]["xPt"] = -1
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "must be >=")

    def test_unknown_field_type_fails(self) -> None:
        form = self.builder.add_form("synthetic")
        form["groundTruth"]["fields"][0]["type"] = "radio"
        self.builder.write()
        self.assert_fails(self.run_verify("--min-real-forms", "0"), "must be one of")

    # -- machine-readable failure output -----------------------------------

    def test_json_failure_reports_failures(self) -> None:
        form = self.builder.add_form("synthetic")
        self.builder.write()
        (self.root / form["path"]).write_bytes(b"tampered")
        process = self.run_verify("--min-real-forms", "0", "--json")
        self.assertEqual(process.returncode, 1, process.stdout + process.stderr)
        payload = json.loads(process.stdout)
        self.assertFalse(payload["ok"])
        self.assertTrue(payload["failures"])

    # -- schema self-check --------------------------------------------------

    def test_schema_is_valid_json_and_declares_draft_2020_12(self) -> None:
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        self.assertIn("2020-12", schema["$schema"])
        self.assertIn("form", schema["$defs"])
        self.assertIn("forms", schema["required"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
