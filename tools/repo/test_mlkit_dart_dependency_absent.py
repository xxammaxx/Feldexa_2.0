#!/usr/bin/env python3
"""Guard against a Dart ML Kit plugin re-entering the workspace.

Cause and purpose: apps/feldexa_app/pubspec.yaml declared
``google_mlkit_text_recognition: 1.0.2`` although no Dart file ever imported it.
On-device Latin OCR runs natively through
``com.google.mlkit:text-recognition:16.0.1`` (android/app/build.gradle.kts) and
``MlKitOcrService.kt``; the plugin only added a second, unused copy of that AAR
plus its own registration path (T309, issue #309). A wrapper cannot do anything
the native service does not already do, so a re-added declaration is either a
leftover or a duplicate OCR path - both are regressions this test refuses.

Two independent checks, because a plugin needs both halves to be effective:
a pubspec declaration and a Dart import.

The name patterns accept both spellings in circulation - ``google_mlkit`` and
``google_ml_kit`` - because either one ships the same plugin (issue #321).
A hyphenated variant needs no pattern work: pub rejects any package name that is
not a valid Dart identifier, so ``google-mlkit`` can never resolve. A dependency
key may be quoted - ``"google_ml_kit_text_recognition": 1.0.2`` - because pub's
YAML parser accepts single and double quotes around a plain key, so the key
pattern tolerates them (issue #323).

Deliberate limits, so a future reader does not mistake them for regressions:

* The explicit YAML key syntax (``? google_ml_kit_text_recognition``) is *not*
  covered. No pubspec in the workspace uses it, and it does not survive a copy
  of a real dependency block, so it stays documented-unhandled instead of
  growing the pattern into a YAML parser (issue #323).
* ``DART_MLKIT_IMPORT`` also matches a URI mentioned in a Dart comment or string
  literal. That is intended fail-closed behaviour, not a missing filter: such a
  mention is worth a look even when nothing imports it (issue #323 point 4).
* The quote tolerance of the key pattern also accepts one-sided quotes and a
  space before the colon (``"name: 1.0.2``, ``"name" : 1.0.2``), which is not
  valid YAML. That is fail-closed on purpose: the looser key pattern can only
  over-report a declaration, never hide one, and keeping it quote-agnostic is
  cheaper than parsing YAML (issue #325 point 2).

The scan is deliberately manifest- and source-driven instead of resolved through
``flutter pub deps`` so the guard needs no Flutter, Pub cache, or network. Paths
are derived from this file, so the verdict does not depend on the working
directory of the process that runs it.

Run with:
    python3 -m unittest discover -s tools/repo -p 'test_*.py' -v
"""

from __future__ import annotations

import re
import tempfile
import unittest
from pathlib import Path

TEST_DIR = Path(__file__).resolve().parent
REPO_ROOT = TEST_DIR.parents[1]

# ``ml_?kit`` covers ``google_mlkit`` and ``google_ml_kit`` alike.
MLKIT_DART_PACKAGE = re.compile(r"^google_ml_?kit[a-z0-9_]*$")
# A YAML key that declares a package dependency, for example
# ``  google_ml_kit_text_recognition: 1.0.2`` or its quoted form
# ``  "google_ml_kit_text_recognition": 1.0.2``. The explicit key syntax
# ``? name`` is a documented limit, see the module docstring. One-sided quotes
# and a space before the colon are tolerated on purpose (fail-closed, see the
# module docstring).
PUBSPEC_DEPENDENCY_KEY = re.compile(r"^[\s-]*[\"']?(?P<name>[A-Za-z0-9_]+)[\"']?\s*:")
# Any package: URI, so an import and an export are caught alike; ``ml_?kit``
# covers ``package:google_mlkit*`` and ``package:google_ml_kit*``.
DART_MLKIT_IMPORT = re.compile(r"""\bpackage:google_ml_?kit[a-z0-9_]*/""")

# Generated or vendored trees that can carry copies of upstream sources.
SKIPPED_DIRECTORIES = frozenset(
    {".git", ".dart_tool", ".gradle", "build", "node_modules", "ephemeral"}
)


def walk(pattern: str) -> list[Path]:
    """Return files matching ``pattern`` below the repository root."""
    found: list[Path] = []
    for path in REPO_ROOT.rglob(pattern):
        relative = path.relative_to(REPO_ROOT)
        if SKIPPED_DIRECTORIES.intersection(relative.parts[:-1]):
            continue
        if path.is_file():
            found.append(path)
    return sorted(found)


def yaml_value_without_comment(line: str) -> str:
    """Strip a trailing ``#`` comment from a YAML line, honouring quotes."""
    quote = ""
    for index, character in enumerate(line):
        if quote:
            if character == quote:
                quote = ""
            continue
        if character in {"'", '"'}:
            quote = character
            continue
        if character == "#":
            return line[:index]
    return line


def declared_mlkit_packages(pubspec: Path) -> list[str]:
    """Return every ``google_ml_?kit*`` dependency key declared in ``pubspec``."""
    declared: list[str] = []
    for line in pubspec.read_text(encoding="utf-8", errors="replace").splitlines():
        match = PUBSPEC_DEPENDENCY_KEY.match(yaml_value_without_comment(line))
        if match and MLKIT_DART_PACKAGE.match(match.group("name")):
            declared.append(match.group("name"))
    return declared


def importing_dart_files(source: Path) -> list[int]:
    """Return the 1-based line numbers of ``package:google_ml_?kit*`` URIs."""
    lines: list[int] = []
    for number, line in enumerate(
        source.read_text(encoding="utf-8", errors="replace").splitlines(), start=1
    ):
        if DART_MLKIT_IMPORT.search(line):
            lines.append(number)
    return lines


class MlKitDartDependencyAbsentTest(unittest.TestCase):
    def test_the_scan_reaches_the_workspace(self) -> None:
        self.assertTrue(
            pubspecs := walk("pubspec.yaml"),
            f"no pubspec.yaml found below {REPO_ROOT}, so this guard would "
            "silently pass",
        )
        self.assertIn(
            REPO_ROOT / "pubspec.yaml",
            pubspecs,
            "the workspace root pubspec.yaml must be part of the scanned set",
        )
        self.assertTrue(
            walk("*.dart"),
            f"no Dart source found below {REPO_ROOT}, so this guard would "
            "silently pass",
        )

    def test_no_pubspec_declares_an_mlkit_dart_package(self) -> None:
        violations = [
            f"{pubspec.relative_to(REPO_ROOT)}: {name}"
            for pubspec in walk("pubspec.yaml")
            for name in declared_mlkit_packages(pubspec)
        ]
        self.assertEqual(
            [],
            violations,
            "no Dart ML Kit package may be declared: the on-device OCR model "
            "ships through com.google.mlkit:text-recognition:16.0.1 in "
            "apps/feldexa_app/android/app/build.gradle.kts (T309). Remove the "
            "declaration:\n" + "\n".join(violations),
        )

    def test_no_dart_source_imports_an_mlkit_package(self) -> None:
        violations = [
            f"{source.relative_to(REPO_ROOT)}:{line}"
            for source in walk("*.dart")
            for line in importing_dart_files(source)
        ]
        self.assertEqual(
            [],
            violations,
            "no Dart source may import a package:google_ml_?kit* package; the "
            "native MlKitOcrService.kt is the only OCR path (T309):\n"
            + "\n".join(violations),
        )

    def test_the_patterns_cover_divergent_spellings(self) -> None:
        """Both spellings count as the plugin, and unrelated names do not."""
        for name in (
            "google_mlkit_text_recognition",
            "google_ml_kit_text_recognition",
            "google_ml_kit",
        ):
            with self.subTest(name=name):
                self.assertIsNotNone(MLKIT_DART_PACKAGE.match(name))
                self.assertTrue(
                    DART_MLKIT_IMPORT.search(f"import 'package:{name}/x.dart';")
                )
        for name in ("google_ml", "mlkit_text_recognition", "text_recognition"):
            with self.subTest(name=name):
                self.assertIsNone(MLKIT_DART_PACKAGE.match(name))
                self.assertIsNone(
                    DART_MLKIT_IMPORT.search(f"import 'package:{name}/x.dart';")
                )

    def test_the_key_pattern_accepts_quoted_dependency_keys(self) -> None:
        """Quoted keys count, an unrelated quoted key does not (issue #323)."""
        for line, expected in (
            ('  "google_ml_kit_text_recognition": 1.0.2',
             "google_ml_kit_text_recognition"),
            ("  'google_mlkit_text_recognition': 1.0.2",
             "google_mlkit_text_recognition"),
            ('  "google_mlkit": any', "google_mlkit"),
            ("- 'google_ml_kit_text_recognition': 1.0.2 # quoted list item",
             "google_ml_kit_text_recognition"),
            ('- "google_mlkit_text_recognition": 1.0.2',
             "google_mlkit_text_recognition"),
            ("  google_mlkit_text_recognition: 1.0.2",
             "google_mlkit_text_recognition"),
            ('  "google_mlkit_text_recognition" : 1.0.2',
             "google_mlkit_text_recognition"),
        ):
            with self.subTest(line=line):
                match = PUBSPEC_DEPENDENCY_KEY.match(yaml_value_without_comment(line))
                self.assertIsNotNone(match)
                self.assertEqual(expected, match.group("name"))
        # An unrelated quoted key still matches the key pattern; the package
        # pattern is what has to reject it (issue #325 point 3).
        for line, name in (
            ('  "description": "a quoted non-dependency key"', "description"),
            ("  'flutter':", "flutter"),
        ):
            with self.subTest(line=line):
                match = PUBSPEC_DEPENDENCY_KEY.match(yaml_value_without_comment(line))
                self.assertIsNotNone(match, f"{line!r} must still read as a YAML key")
                self.assertEqual(name, match.group("name"))
                self.assertIsNone(
                    MLKIT_DART_PACKAGE.match(match.group("name")),
                    f"{line!r} must not count as an ML Kit declaration",
                )
        # An empty quoted key is not a dependency key at all.
        with self.subTest(line='  "": empty'):
            self.assertIsNone(
                PUBSPEC_DEPENDENCY_KEY.match(yaml_value_without_comment('  "": empty'))
            )

    def test_a_quoted_declaration_is_reported(self) -> None:
        """The file-reading scan picks up a quoted declaration (issue #323)."""
        with tempfile.TemporaryDirectory() as directory:
            pubspec = Path(directory) / "pubspec.yaml"
            pubspec.write_text(
                "name: probe\ndependencies:\n"
                '  "google_ml_kit_text_recognition": 1.0.2\n',
                encoding="utf-8",
            )
            self.assertEqual(
                ["google_ml_kit_text_recognition"], declared_mlkit_packages(pubspec)
            )


if __name__ == "__main__":
    unittest.main()
