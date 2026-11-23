#!/usr/bin/env python3
"""Guard the Git index against CRLF blobs for text-normalized tracked files.

Cause and purpose: apps/feldexa_app/android/gradlew.bat was committed with raw
CRLF bytes although .gitattributes normalizes ``*.bat`` to ``text eol=crlf``, so
every fresh clone or worktree started permanently dirty. This test parses
``git ls-files --eol`` and fails as soon as a normalized file stores CRLF in the
index again.

The index is the contract, because the index blob is what a clone reproduces.
Two workspace values are legitimate and therefore not violations: ``none`` for a
file without any EOL byte (for example a one-line ``.bat`` without a trailing
newline) and ``-text`` for a file Git classifies as binary even though an
attribute rule selected it. An index assertion is decided by the index column
alone: only ``i/-text`` makes an index blob binary, a ``w/-text`` worktree state
does not excuse a CRLF blob in the index.

Checkout ownership is not corrected for the run: on a checkout owned by another
user Git refuses the commands (``safe.directory``) and the test fails loudly with
that Git error instead of reporting an unverified index.

Run with:
    python3 -m unittest discover -s tools/repo -p 'test_*.py' -v
"""

from __future__ import annotations

import os
import subprocess
import unittest
from dataclasses import dataclass
from pathlib import Path

TEST_DIR = Path(__file__).resolve().parent

NORMALIZED_EOLS = frozenset({"lf", "none"})
NORMALIZED_EOL_ATTRIBUTES = frozenset({"crlf", "lf"})

# Variables that point Git at another repository, index, or attribute source.
# They are inherited from whatever launched the tests, so they have to be
# removed: with GIT_DIR or GIT_INDEX_FILE set the guard would inspect a
# different repository and report a verdict about the wrong index.
REPO_POINTER_VARIABLES = frozenset(
    {
        "GIT_DIR",
        "GIT_WORK_TREE",
        "GIT_INDEX_FILE",
        "GIT_COMMON_DIR",
        "GIT_CONFIG_COUNT",
    }
)
REPO_POINTER_PREFIXES = ("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_")

# The verdict must describe the repository, not the machine: a developer's
# global ``* text=auto`` (core.attributesFile) would otherwise turn
# attribute-free CRLF blobs into reported violations of a rule they never had.
# GIT_ATTR_NOSYSTEM keeps a system-wide gitattributes file out of the same
# verdict.
def isolated_git_env() -> dict[str, str]:
    env = {
        key: value
        for key, value in os.environ.items()
        if key not in REPO_POINTER_VARIABLES
        and not key.startswith(REPO_POINTER_PREFIXES)
    }
    env["GIT_CONFIG_GLOBAL"] = os.devnull
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env["GIT_ATTR_NOSYSTEM"] = "1"
    return env


ISOLATED_GIT_ENV = isolated_git_env()


def run_git(*args: str, cwd: Path) -> str:
    try:
        completed = subprocess.run(
            ["git", *args],
            cwd=cwd,
            capture_output=True,
            check=True,
            env=ISOLATED_GIT_ENV,
        )
    except (subprocess.CalledProcessError, OSError) as error:
        stderr = getattr(error, "stderr", b"") or b""
        detail = stderr.decode("utf-8", "replace").strip() or str(error)
        raise AssertionError(
            f"git {' '.join(args)} failed in {cwd}: {detail}"
        ) from error
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
        """True when Git applies text conversion, i.e. ``text`` is set or ``text=auto``.

        ``git ls-files --eol`` already reports the ``text`` attribute implied by
        an ``eol`` rule; the explicit ``eol`` check only guards Git versions
        that omit it.
        """
        return (
            self.attributes.get("text") not in (None, False)
            or self.attributes.get("eol") is not None
        )

    def is_binary_in_index(self) -> bool:
        """True when the index blob is binary, so Git never converted it.

        Only the index column decides an index assertion. A ``-text`` worktree
        value must not excuse an index blob that stores CRLF.
        """
        return self.index_eol == "-text"

    def is_binary(self) -> bool:
        """True when Git refuses text conversion in the index or the worktree.

        Only the checkout test uses this: a binary worktree copy cannot carry
        the CRLF checkout conversion, so it is not a violation there.
        """
        return "-text" in (self.index_eol, self.worktree_eol)

    def stores_normalized_index(self) -> bool:
        """True when the index blob holds no CRLF, accepting an EOL-free file."""
        return self.index_eol in NORMALIZED_EOLS


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

    def test_eol_rule_files_store_lf_in_index(self) -> None:
        eol_files = [
            entry
            for entry in self.tracked_files
            if entry.attributes.get("eol") in NORMALIZED_EOL_ATTRIBUTES
            and not entry.is_binary_in_index()
        ]
        self.assertTrue(
            eol_files,
            "no tracked file carries an eol=crlf or eol=lf rule, so this test "
            "would silently pass; check .gitattributes",
        )
        violations = [
            entry.describe()
            for entry in eol_files
            if not entry.stores_normalized_index()
        ]
        self.assertEqual(
            [],
            violations,
            "files with an eol rule must be stored as LF in the index; run "
            "'git add --renormalize <path>' for each offending file:\n"
            + "\n".join(violations),
        )

    def test_eol_crlf_files_are_checked_out_with_crlf(self) -> None:
        crlf_files = [
            entry
            for entry in self.tracked_files
            if entry.attributes.get("eol") == "crlf"
            and entry.index_eol != "none"
            and not entry.is_binary()
        ]
        self.assertTrue(
            crlf_files,
            "no tracked file carries the eol=crlf attribute, so this test would "
            "silently pass; check .gitattributes",
        )
        violations = [
            entry.describe()
            for entry in crlf_files
            if entry.worktree_eol != "crlf"
        ]
        self.assertEqual(
            [],
            violations,
            "files with eol=crlf must be checked out with CRLF line endings; a "
            "different worktree state means the checkout conversion was never "
            "applied - run 'git checkout -- <path>' for each offending file:\n"
            + "\n".join(violations),
        )

    def test_text_files_store_lf_in_index(self) -> None:
        text_files = [
            entry
            for entry in self.tracked_files
            if entry.has_text_attribute() and not entry.is_binary_in_index()
        ]
        self.assertTrue(
            text_files,
            "no tracked file carries the text attribute, so this rule would "
            "silently pass; check .gitattributes",
        )
        violations = [
            entry.describe()
            for entry in text_files
            if not entry.stores_normalized_index()
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
