#!/usr/bin/env python3
"""Regression tests for tools/evaluation/check_evidence_docs.py.

These tests build throwaway Git repositories. They prove that:
  * a current tree can be checked directly;
  * a later task change is accepted only by verifying a reachable historical
    revision where every recorded artifact hash matches;
  * a forged hash that no revision contains is rejected;
  * an attestation candidate is verified at its own commit even when HEAD has
    moved on;
  * attestation tampering, a missing candidate, and path escapes fail;
  * output does not leak the temporary checkout path.

Run:
  python3 -m unittest tools/evaluation/test_check_evidence_docs.py
  python3 tools/evaluation/test_check_evidence_docs.py
"""
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import check_evidence_docs as checker  # noqa: E402


def sha256(data):
    return hashlib.sha256(data).hexdigest()


class CheckerFixture:
    def __init__(self, root):
        self.root = pathlib.Path(root)
        self.rows = [
            ("Stable", "stable.txt", b"stable\n"),
            ("Tasks", "tasks.md", b"- [x] T010\n- [ ] T011\n"),
        ]

    def git(self, *args):
        subprocess.run(
            ["git", "-C", str(self.root), *args],
            check=True,
            capture_output=True,
        )

    def write(self, path, data):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(data, str):
            target.write_text(data, encoding="utf-8")
        else:
            target.write_bytes(data)

    def commit(self, message):
        self.git("add", "-A")
        self.git(
            "-c",
            "user.name=Checker Test",
            "-c",
            "user.email=checker@example.test",
            "commit",
            "-q",
            "-m",
            message,
        )
        return self.rev("HEAD")

    def rev(self, ref):
        return subprocess.check_output(
            ["git", "-C", str(self.root), "rev-parse", ref]
        ).decode().strip()

    def report(self, rows=None):
        rows = self.rows if rows is None else rows
        lines = [
            "# T010 Fixture Evidence Report",
            "",
            "| Task / issue | `T010` |",
            "",
            "PARTIAL",
            "",
            "## 9. Artifacts",
            "",
            "| Artifact | Path | Bytes | SHA-256 |",
            "| --- | --- | ---: | --- |",
        ]
        for label, path, data in rows:
            lines.append(
                f"| {label} | `{path}` | {len(data):,} | `{sha256(data)}` |"
            )
        lines.extend(["", "## 10. External attestation", "", "External record.", ""])
        return "\n".join(lines)


class CheckerTests(unittest.TestCase):
    ATTESTATION_PATH = (
        "specs/001-scanned-form-workflow/reports/"
        "2026-11-12-t010-candidate-attestation.json"
    )

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.fx = CheckerFixture(self.temp.name)
        self.fx.git("init", "-q")
        self.fx.git("config", "user.name", "Checker Test")
        self.fx.git("config", "user.email", "checker@example.test")
        self.fx.write("README.md", "\n".join(checker.TOKENS) + "\n")
        self.fx.write("stable.txt", b"stable\n")
        self.fx.write("tasks.md", b"- [x] T010\n- [ ] T011\n")
        self.report_text = self.fx.report()
        self.report_bytes = self.report_text.encode("utf-8")
        self.fx.write("report.md", self.report_text)
        self.base = self.fx.commit("base")

    def tearDown(self):
        self.temp.cleanup()

    def run_checker(self, *extra):
        command = [
            sys.executable,
            str(pathlib.Path(checker.__file__)),
            "--repo",
            str(self.fx.root),
            "--readme",
            "README.md",
            "--report",
            "report.md",
            *extra,
        ]
        return subprocess.run(command, capture_output=True, text=True)

    def later_task_change(self):
        self.fx.write("tasks.md", b"- [x] T010\n- [x] T011\n")
        return self.fx.commit("later task")

    def later_task_change(self):
        self.fx.write("tasks.md", b"- [x] T010\n- [x] T011\n")
        return self.fx.commit("later task")

    def attestation(self, report_sha256=None):
        changed_files = [
            {
                "path": path,
                "bytes": len(data),
                "sha256": sha256(data),
            }
            for _, path, data in self.fx.rows
        ]
        return {
            "candidate": {
                "commit": self.base,
                "changed_files": changed_files,
            },
            "report_self": {
                "bytes": len(self.report_bytes),
                "sha256": report_sha256 or sha256(self.report_bytes),
            },
        }

    def install_attestation_ref(self, attestation):
        self.fx.write(self.ATTESTATION_PATH, json.dumps(attestation))
        self.fx.commit("attestation")
        self.fx.git("update-ref", "refs/heads/attestation", "HEAD")

    def tamper_report_title(self):
        self.fx.write(
            "report.md",
            self.report_text.replace(
                "# T010 Fixture Evidence Report",
                "# Tampered Evidence Report",
            ),
        )

    def test_current_tree_matches(self):
        result = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS artifacts: HEAD", result.stdout)
        self.assertNotIn("historical", result.stdout)

    def test_later_task_change_verifies_historical_revision(self):
        self.later_task_change()
        result = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS historical artifacts:", result.stdout)
        self.assertIn("later task changes accepted", result.stdout)

    def test_uncommitted_change_does_not_rewrite_committed_evidence(self):
        self.fx.write("tasks.md", b"- [x] T010\n- [x] T011\n")  # not committed
        result = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS artifacts: HEAD", result.stdout)

    def test_explicit_revision_pins_history(self):
        self.later_task_change()
        result = self.run_checker("--revision", self.base)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS artifacts: revision", result.stdout)

        result = self.run_checker("--revision", "HEAD")
        self.assertEqual(result.returncode, 1)
        self.assertIn("SHA-256 mismatch", result.stdout)

    def test_forged_historical_hash_is_rejected(self):
        forged = b"never committed\n"
        rows = [
            self.fx.rows[0],
            ("Tasks", "tasks.md", forged),
        ]
        self.fx.write("report.md", self.fx.report(rows))
        self.fx.commit("forge report")
        result = self.run_checker()
        self.assertEqual(result.returncode, 1)
        self.assertIn("no reachable historical revision", result.stdout)
        self.assertIn("SHA-256 mismatch", result.stdout)

    def test_artifact_path_escape_is_rejected(self):
        rows = [
            self.fx.rows[0],
            ("Escape", "../outside.txt", b"outside\n"),
        ]
        self.fx.write("report.md", self.fx.report(rows))
        self.fx.commit("escape")
        result = self.run_checker()
        self.assertEqual(result.returncode, 1)
        self.assertIn("artifact path escapes repository", result.stdout)

    def test_attestation_candidate_not_head_is_verified_at_candidate(self):
        report_bytes = (self.fx.root / "report.md").read_bytes()
        attestation = {
            "candidate": {
                "commit": self.base,
                "changed_files": [
                    {
                        "path": path,
                        "bytes": len(data),
                        "sha256": sha256(data),
                    }
                    for _, path, data in self.fx.rows
                ],
            },
            "report_self": {
                "bytes": len(report_bytes),
                "sha256": sha256(report_bytes),
            },
        }
        self.fx.write("attestation.json", json.dumps(attestation))
        self.later_task_change()
        result = self.run_checker("--attestation-file", "attestation.json")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS attestation: candidate", result.stdout)
        self.assertIn("PASS artifacts: attestation candidate", result.stdout)

    def test_attestation_changed_file_tamper_is_rejected(self):
        report_bytes = (self.fx.root / "report.md").read_bytes()
        attestation = {
            "candidate": {
                "commit": self.base,
                "changed_files": [
                    {
                        "path": "tasks.md",
                        "bytes": 1,
                        "sha256": "0" * 64,
                    }
                ],
            },
            "report_self": {
                "bytes": len(report_bytes),
                "sha256": sha256(report_bytes),
            },
        }
        self.fx.write("attestation.json", json.dumps(attestation))
        result = self.run_checker("--attestation-file", "attestation.json")
        self.assertEqual(result.returncode, 1)
        self.assertIn("changed file mismatch", result.stdout)

    def test_attestation_missing_candidate_is_rejected(self):
        report_bytes = (self.fx.root / "report.md").read_bytes()
        attestation = {
            "candidate": {
                "commit": "0" * 40,
                "changed_files": [],
            },
            "report_self": {
                "bytes": len(report_bytes),
                "sha256": sha256(report_bytes),
            },
        }
        self.fx.write("attestation.json", json.dumps(attestation))
        result = self.run_checker("--attestation-file", "attestation.json")
        self.assertEqual(result.returncode, 1)
        self.assertIn("candidate commit missing", result.stdout)

    def test_attestation_revision_conflict_is_rejected(self):
        report_bytes = (self.fx.root / "report.md").read_bytes()
        attestation = {
            "candidate": {
                "commit": self.base,
                "changed_files": [],
            },
            "report_self": {
                "bytes": len(report_bytes),
                "sha256": sha256(report_bytes),
            },
        }
        self.fx.write("attestation.json", json.dumps(attestation))
        self.later_task_change()
        result = self.run_checker(
            "--attestation-file",
            "attestation.json",
            "--revision",
            "HEAD",
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("differs from --revision", result.stdout)

    def test_working_report_tamper_with_attestation_ref_fails(self):
        self.later_task_change()
        self.install_attestation_ref(self.attestation())
        result = self.run_checker(
            "--attestation-ref", "refs/heads/attestation"
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS report binding:", result.stdout)

        self.tamper_report_title()
        result = self.run_checker(
            "--attestation-ref", "refs/heads/attestation"
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("working report differs from checked revision", result.stdout)

    def test_working_report_tamper_with_attestation_file_fails(self):
        self.later_task_change()
        self.fx.write("attestation.json", json.dumps(self.attestation()))
        self.tamper_report_title()
        result = self.run_checker(
            "--attestation-file", "attestation.json"
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("working report differs from checked revision", result.stdout)

    def test_working_report_tamper_with_explicit_revision_fails(self):
        self.later_task_change()
        self.tamper_report_title()
        result = self.run_checker("--revision", self.base)
        self.assertEqual(result.returncode, 1)
        self.assertIn("working report differs from checked revision", result.stdout)

    def test_working_report_tamper_with_default_history_fails(self):
        self.later_task_change()
        self.tamper_report_title()
        result = self.run_checker()
        self.assertEqual(result.returncode, 1)
        self.assertIn("working report differs from checked revision", result.stdout)

    def test_attestation_report_self_tamper_is_rejected(self):
        self.later_task_change()
        attestation = self.attestation(report_sha256="0" * 64)
        self.fx.write("attestation.json", json.dumps(attestation))
        result = self.run_checker(
            "--attestation-file", "attestation.json"
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("report SHA-256 mismatch", result.stdout)

    def test_readme_and_tasks_may_evolve_with_attestation(self):
        self.fx.write(
            "README.md",
            "\n".join(checker.TOKENS) + "\nupdated template\n",
        )
        self.fx.write("tasks.md", b"- [x] T010\n- [x] T011\n")
        self.fx.commit("later task and template update")
        self.install_attestation_ref(self.attestation())
        result = self.run_checker(
            "--attestation-ref", "refs/heads/attestation"
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS report binding:", result.stdout)

    def test_output_does_not_leak_checkout_path(self):
        self.later_task_change()
        result = self.run_checker()
        self.assertNotIn(str(self.fx.root), result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
