#!/usr/bin/env python3
"""Guard the Git index against CRLF blobs for text-normalized tracked files.

Cause and purpose: apps/feldexa_app/android/gradlew.bat was committed with raw
CRLF bytes although .gitattributes normalizes ``*.bat`` to ``text eol=crlf``, so
every fresh clone or worktree started permanently dirty; this test parses
``git ls-files --eol`` and fails as soon as any text-normalized file stores CRLF
in the index again.

Run with:
    python3 -m unittest discover -s tools/repo -p 'test_*.py' -v
"""

from __future__ import annotations

import subprocess
import unittest
from dataclasses import dataclass
from pathlib import Path

TEST_DIR = Path(__file__).resolve().parent


def run_git(*args: str, cwd: Path) -> str:
    completed = subprocess.run(
        ["git", *args],
        cwd=cwd,
        capture_output=True,
        check=True,
    )
    return completed.stdout.decode("utf-8", "surrogateescape")


def find_repo_root() -> Path:
    root = run_git("rev-parse", "--show-toplevel", cwd=TEST_DIR).strip()
    if not root:
        raise AssertionError("git rev-parse --show-toplevel returned no path")
    return Path(root)


@dataclass(frozen=True)
class TrackedFile:
    path: str
    index_eol: str
    worktree_eol: str
    attributes: dict[str, str | bool]

    def describe(self) -> str:
        rendered = " ".join(
            key if value is True else f"-{key}" if value is False else f"{key}={value}"
            for key, value in self.attributes.items()
        )
        return (
            f"{self.path}: i/{self.index_eol} w/{self.worktree_eol} "
            f"attr/{rendered}".rstrip()
        )

    def has_text_attribute(self) -> bool:
        """True when Git applies text conversion, i.e. ``text`` is set or ``text=auto``."""
        return self.attributes.get("text") not in (None, False)


def parse_attributes(field: str) -> dict[str, str | bool]:
    attributes: dict[str, str | bool] = {}
    for item in field.split():
        if item.startswith("-"):
            attributes[item[1:]] = False
        elif "=" in item:
            key, _, value = item.partition("=")
            attributes[key] = value
        else:
            attributes[item] = True
    return attributes


def parse_ls_files_eol(raw: str) -> list[TrackedFile]:
    """Parse ``git ls-files --eol -z`` records: ``i/<eol> w/<eol> attr/<attrs>\\t<path>``."""
    entries: list[TrackedFile] = []
    for record in raw.split("\0"):
        if not record:
            continue
        meta, separator, path = record.partition("\t")
        if not separator:
            raise AssertionError(f"unparsable git ls-files --eol record: {record!r}")
        fields = meta.split()
        if len(fields) < 3 or not fields[0].startswith("i/") or not fields[1].startswith("w/"):
            raise AssertionError(f"unexpected git ls-files --eol columns: {meta!r}")
        attribute_field = " ".join(fields[2:])
        if not attribute_field.startswith("attr/"):
            raise AssertionError(f"unexpected git ls-files --eol attribute column: {meta!r}")
        entries.append(
            TrackedFile(
                path=path,
                index_eol=fields[0][len("i/"):],
                worktree_eol=fields[1][len("w/"):],
                attributes=parse_attributes(attribute_field[len("attr/"):]),
            )
        )
    return entries


class GitEolNormalizationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repo_root = find_repo_root()
        cls.tracked_files = parse_ls_files_eol(
            run_git("ls-files", "--eol", "-z", cwd=cls.repo_root)
        )

    def test_ls_files_eol_lists_tracked_files(self) -> None:
        self.assertTrue(
            self.tracked_files,
            f"git ls-files --eol returned no tracked files in {self.repo_root}",
        )

    def test_eol_crlf_files_are_lf_in_index_and_crlf_in_worktree(self) -> None:
        crlf_files = [
            entry for entry in self.tracked_files if entry.attributes.get("eol") == "crlf"
        ]
        self.assertTrue(
            crlf_files,
            "no tracked file carries the eol=crlf attribute, so this rule would "
            "silently pass; check .gitattributes",
        )
        violations = [
            entry.describe()
            for entry in crlf_files
            if entry.index_eol != "lf" or entry.worktree_eol != "crlf"
        ]
        self.assertEqual(
            [],
            violations,
            "files with eol=crlf must be stored as LF in the index and checked out "
            "as CRLF; offending files:\n" + "\n".join(violations),
        )

    def test_text_files_store_lf_in_index(self) -> None:
        text_files = [entry for entry in self.tracked_files if entry.has_text_attribute()]
        self.assertTrue(
            text_files,
            "no tracked file carries the text attribute, so this rule would "
            "silently pass; check .gitattributes",
        )
        violations = [
            entry.describe() for entry in text_files if entry.index_eol != "lf"
        ]
        self.assertEqual(
            [],
            violations,
            "text-normalized files must never be committed with CRLF line endings; "
            "run 'git add --renormalize <path>' for each offending file:\n"
            + "\n".join(violations),
        )


if __name__ == "__main__":
    unittest.main()
