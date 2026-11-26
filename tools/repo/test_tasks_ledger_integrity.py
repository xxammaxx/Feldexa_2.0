#!/usr/bin/env python3
"""Guard the task ledger's own format and reference claims.

Cause and purpose: review M1 (2026-11-26) found three classes of drift in
``specs/001-scanned-form-workflow/tasks.md``:

* two checked rows used the uppercase ``- [X]`` marker while the file's own
  format validation claims only ``- [x]`` and ``- [ ]``;
* the completion summary still stated "Total tasks: 150" although the file
  carried 167 rows (150 base identifiers plus 17 extension rows);
* three rows named target files that do not exist (``tools/pdf_verify/
  verify.sh``, ``features/export/preview.dart``, ``features/export/
  preflight.dart``), and the T104 row had earlier been misquoted in review as
  ``PdfExportApplier.kt`` although it already named ``PdfExportService.kt``.

The guard enforces only what the file itself claims: the checkbox vocabulary,
the stated row/checked/open counts, that a checked row's cited report exists,
and that the four corrected export targets resolve. It does not decide whether
a row is functionally complete; open rows legitimately cite files that do not
exist yet.

Run with:
    python3 -m unittest discover -s tools/repo -p 'test_*.py' -v
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

TEST_DIR = Path(__file__).resolve().parent
ROOT = TEST_DIR.parents[1]
FEATURE = ROOT / "specs" / "001-scanned-form-workflow"
TASKS = FEATURE / "tasks.md"

ROW = re.compile(r"^- \[([ xX])\] (T\d{3}[A-Z]?(?:-[A-Z])?)\b")
COUNTS = re.compile(
    r"^- \*\*Task rows\*\*: (\d+) \(base T001\u2013T150: (\d+); "
    r"extension rows: (\d+)[^)]*\); checked: (\d+); open: (\d+)\.",
    re.MULTILINE,
)
REPORT = re.compile(r"reports/[0-9]{4}-[0-9]{2}-[0-9]{2}[A-Za-z0-9.\-_/]*\.md")
BACKTICK = re.compile(r"`([^`]+)`")
SKIP_PREFIXES = (
    "filesDir/",
    "origin/",
    "xxammaxx/",
    "runs/",
    "integration_test/",
    "test/",
)
SKIP_CHARS = set("*{}$<>|")
REPO_ROOTS = ("specs/", "tools/", "apps/", "packages/", "contracts/", "reports/", ".specify/")


def _resolve(ref: str) -> bool:
    """Resolve a backticked reference against the repo root and the feature dir."""
    ref = re.sub(r":\d+$", "", ref)
    if not ref or "..." in ref or " " in ref:
        return False
    if any(char in ref for char in SKIP_CHARS):
        return False
    if ref.startswith(SKIP_PREFIXES) or not ref.startswith(REPO_ROOTS):
        return False
    path = ref.rstrip("/")
    return (ROOT / path).exists() or (FEATURE / path).exists()

CORRECTED_TARGETS = (
    "tools/pdf_verify/placement.py",
    "apps/feldexa_app/lib/features/export/export_preview.dart",
    "packages/feldexa_export/lib/src/preflight.dart",
)


def rows() -> list[tuple[str, str, str]]:
    parsed = []
    for line in TASKS.read_text(encoding="utf-8").splitlines():
        match = ROW.match(line)
        if match:
            parsed.append((match.group(1), match.group(2), line))
    return parsed


class TasksLedgerIntegrityTest(unittest.TestCase):
    def test_checkbox_vocabulary(self) -> None:
        uppercase = [task_id for mark, task_id, _ in rows() if mark == "X"]
        self.assertEqual(
            [],
            uppercase,
            "tasks.md uses '- [X]' instead of the claimed '- [x]': "
            + ", ".join(uppercase),
        )

    def test_stated_counts_match_the_rows(self) -> None:
        text = TASKS.read_text(encoding="utf-8")
        match = COUNTS.search(text)
        self.assertIsNotNone(
            match, "tasks.md is missing the dated '*Task rows*' count line"
        )
        total, base, extension, checked, open_rows = (int(g) for g in match.groups())
        actual = rows()
        actual_checked = sum(1 for mark, _, _ in actual if mark in "xX")
        self.assertEqual(total, len(actual), "stated total task rows are stale")
        self.assertEqual(base + extension, total, "base + extension rows mismatch")
        self.assertEqual(checked, actual_checked, "stated checked count is stale")
        self.assertEqual(open_rows, len(actual) - actual_checked, "stated open count is stale")

    def test_checked_rows_cite_existing_reports(self) -> None:
        missing = []
        for mark, task_id, line in rows():
            if mark not in "xX":
                continue
            for cited in REPORT.findall(line):
                if not (FEATURE / cited).is_file():
                    missing.append(f"{task_id}: {cited}")
        self.assertEqual([], missing, "checked rows cite missing reports: " + "; ".join(missing))

    def test_corrected_export_targets_exist(self) -> None:
        for target in CORRECTED_TARGETS:
            self.assertTrue((ROOT / target).is_file(), f"missing corrected target: {target}")

    def test_checked_rows_resolve_or_are_superseded(self) -> None:
        violations = []
        for mark, task_id, line in rows():
            if mark not in "xX":
                continue
            refs = [
                ref
                for ref in BACKTICK.findall(line)
                if ref.startswith(REPO_ROOTS)
                and not any(c in ref for c in "{}")
                and " " not in ref
            ]
            unresolved = [ref for ref in refs if not _resolve(ref)]
            if not unresolved:
                continue
            if "superseded" in line.lower() and any(_resolve(ref) for ref in refs):
                continue
            violations.append(task_id + ": " + ", ".join(unresolved))
        self.assertEqual(
            [],
            violations,
            "checked rows cite missing targets without a supersession note: "
            + "; ".join(violations),
        )

    def test_t104_names_the_delivered_service(self) -> None:
        t104 = next(line for mark, task_id, line in rows() if task_id == "T104")
        self.assertIn("PdfExportService.kt", t104)
        self.assertNotIn("PdfExportApplier.kt", t104.split("**[Done")[0])


if __name__ == "__main__":
    unittest.main()
