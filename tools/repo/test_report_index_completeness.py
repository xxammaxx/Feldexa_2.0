#!/usr/bin/env python3
"""Guard the single-evidence-root index in ``reports/README.md``.

Cause and purpose: review M1 (2026-11-26) found 14 committed report files that
were absent from the index required by ``reports/README.md`` section 1 ("Every
report belongs here and is listed in the index in the same change"),
including all export evidence reports of 2026-11-25/26. A report that is not
indexed is not discoverable from the evidence root, so the index is treated as
a repository contract: every ``*.md`` report except ``README.md`` must be
linked, and every relative link in the index must resolve.

The check is deliberately path-based only. It does not judge report quality,
evidence class, or result wording; those remain review concerns.

Run with:
    python3 -m unittest discover -s tools/repo -p 'test_*.py' -v
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

TEST_DIR = Path(__file__).resolve().parent
ROOT = TEST_DIR.parents[1]
REPORTS = ROOT / "specs" / "001-scanned-form-workflow" / "reports"
README = REPORTS / "README.md"

LINK = re.compile(r"\]\(\./([^)#]+)(?:#[^)]*)?\)")


def indexed_targets() -> set[str]:
    text = README.read_text(encoding="utf-8")
    return {name.strip() for name in LINK.findall(text)}


class ReportIndexCompletenessTest(unittest.TestCase):
    def test_readme_exists(self) -> None:
        self.assertTrue(README.is_file(), f"missing index: {README}")

    def test_every_report_is_indexed(self) -> None:
        targets = indexed_targets()
        reports = sorted(
            p.name for p in REPORTS.glob("*.md") if p.name != README.name
        )
        self.assertGreater(len(reports), 100, "the evidence root looks truncated")
        missing = [name for name in reports if name not in targets]
        self.assertEqual(
            [],
            missing,
            "reports committed without an index row in reports/README.md: "
            + ", ".join(missing),
        )

    def test_every_index_link_resolves(self) -> None:
        dangling = [
            name
            for name in sorted(indexed_targets())
            if not (REPORTS / name).exists()
        ]
        self.assertEqual(
            [],
            dangling,
            "reports/README.md links to files that do not exist: "
            + ", ".join(dangling),
        )


if __name__ == "__main__":
    unittest.main()
