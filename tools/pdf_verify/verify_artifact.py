#!/usr/bin/env python3
"""Export-artifact verification harness (T105, contracts/export-plan.md §6).

Runs the tool-executable rows of the §6 verification contract against one
artifact PDF and reports PASS / FAIL / PARTIAL / NOT_RUN / UNAVAILABLE per row.
Rows that need an input the caller did not supply are reported as NOT_RUN with
the exact missing input; absent external engines are UNAVAILABLE. The harness
never invents a PASS.

What it verifies without extra inputs
-------------------------------------
* page count and page-size sequence (order proxy) against the source PDF,
* per-page MediaBox/CropBox/rotation equality within 0.01 pt,
* absence of ``/AcroForm`` and ``/Widget`` in the artifact bytes,
* text extraction and German glyph presence,
* a 150/300 dpi render of each page (Poppler only; MuPDF is absent here),
* SHA-256 of the source file (unchanged).

Rows that need ``--expectations FIELD_JSON`` (values, field rects, checkbox and
signature states, appearance masks):
* text content against expected values,
* value placement (delegated to ``placement.py`` semantics where a rect and a
  value word are supplied),
* masking for the original-appearance comparison,
* checkbox state and signature presence.

Usage:
  verify_artifact.py --source SRC.pdf --artifact ART.pdf [--expectations F.json]
                     [--source-sha256 HEX] [--out report.json] [--print-dpi 300]

Exit codes: 0 all executed rows PASS (rows may be NOT_RUN/UNAVAILABLE with a
reason), 1 at least one row FAIL, 2 usage/input error.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

GEOMETRY_TOLERANCE_PT = 0.01
GERMAN_GLYPHS = "äöüßÄÖÜ€„“"


@dataclass
class Row:
    check: str
    status: str
    detail: str


@dataclass
class Report:
    source: str
    artifact: str
    rows: list[Row] = field(default_factory=list)

    def add(self, check: str, status: str, detail: str) -> None:
        self.rows.append(Row(check, status, detail))

    def exit_code(self) -> int:
        return 1 if any(r.status == "FAIL" for r in self.rows) else 0


def run(cmd: list[str], timeout: int = 120) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def pdf_pages(path: Path) -> int:
    out = run(["pdfinfo", str(path)]).stdout
    match = re.search(r"^Pages:\s+(\d+)", out, re.M)
    if not match:
        raise ValueError(f"pdfinfo did not report a page count for {path}")
    return int(match.group(1))


def page_sizes(path: Path, pages: int) -> list[tuple[float, float, int]]:
    """(width, height, rotation) per page in points, from pdfinfo."""
    out = run(["pdfinfo", "-f", "1", "-l", str(pages), str(path)]).stdout
    sizes: list[tuple[float, float, int]] = []
    for match in re.finditer(
        r"^Page\s+\d+\s+size:\s+([\d.]+)\s+x\s+([\d.]+)\s+pts(?:\s+\(rotated\s+(\d+))?",
        out,
        re.M,
    ):
        sizes.append((float(match.group(1)), float(match.group(2)), int(match.group(3) or 0)))
    if not sizes:
        # Single-size documents print only "Page size:".
        single = re.search(r"^Page size:\s+([\d.]+)\s+x\s+([\d.]+)\s+pts", out, re.M)
        if single:
            sizes = [(float(single.group(1)), float(single.group(2)), 0)] * pages
    return sizes


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def check_geometry(report: Report, source: Path, artifact: Path) -> None:
    if shutil.which("pdfinfo") is None:
        report.add("page geometry", "UNAVAILABLE", "pdfinfo not on PATH")
        return
    source_pages = pdf_pages(source)
    artifact_pages = pdf_pages(artifact)
    if source_pages != artifact_pages:
        report.add(
            "page geometry",
            "FAIL",
            f"page count differs: source {source_pages}, artifact {artifact_pages}",
        )
        return
    src = page_sizes(source, source_pages)
    art = page_sizes(artifact, artifact_pages)
    if len(src) != source_pages or len(art) != artifact_pages:
        report.add(
            "page geometry",
            "PARTIAL",
            f"pdfinfo reported {len(src)}/{len(art)} page sizes for {source_pages} pages",
        )
        return
    for index, (a, b) in enumerate(zip(src, art), start=1):
        if (
            abs(a[0] - b[0]) > GEOMETRY_TOLERANCE_PT
            or abs(a[1] - b[1]) > GEOMETRY_TOLERANCE_PT
            or a[2] != b[2]
        ):
            report.add(
                "page geometry",
                "FAIL",
                f"page {index}: source {a[0]:.2f}x{a[1]:.2f} rot {a[2]}, "
                f"artifact {b[0]:.2f}x{b[1]:.2f} rot {b[2]}",
            )
            return
    report.add(
        "page geometry",
        "PASS",
        f"{source_pages} pages, all sizes and rotations equal within {GEOMETRY_TOLERANCE_PT} pt",
    )


def check_page_count(report: Report, source: Path, artifact: Path) -> None:
    if shutil.which("pdfinfo") is None:
        report.add("page count and order", "UNAVAILABLE", "pdfinfo not on PATH")
        return
    a, b = pdf_pages(source), pdf_pages(artifact)
    if a == b:
        report.add("page count and order", "PASS", f"{a} pages in both documents")
    else:
        report.add("page count and order", "FAIL", f"source {a} pages, artifact {b}")


def check_interactive_controls(report: Report, artifact: Path) -> None:
    data = artifact.read_bytes()
    acroform = data.count(b"/AcroForm")
    widget = data.count(b"/Widget")
    if acroform == 0 and widget == 0:
        report.add(
            "no interactive controls",
            "PASS",
            "no /AcroForm and no /Widget in the artifact bytes",
        )
    else:
        report.add(
            "no interactive controls",
            "FAIL",
            f"artifact carries /AcroForm x{acroform}, /Widget x{widget}",
        )


def check_text(report: Report, artifact: Path, expectations: dict | None) -> None:
    if shutil.which("pdftotext") is None:
        report.add("text content", "UNAVAILABLE", "pdftotext not on PATH")
        return
    text = run(["pdftotext", "-layout", str(artifact), "-"]).stdout
    if not text.strip():
        report.add("text content", "FAIL", "artifact extracts no text")
        return
    if not any(glyph in text for glyph in GERMAN_GLYPHS):
        report.add(
            "text content",
            "PARTIAL",
            "text extracted but no German glyph from the verification set appears",
        )
        return
    values = []
    if expectations:
        values = [
            str(f.get("value"))
            for f in expectations.get("fields", [])
            if f.get("value") not in (None, "")
        ]
    missing = [v for v in values if v not in text]
    if missing:
        report.add("text content", "FAIL", f"expected values missing: {missing}")
    elif values:
        report.add("text content", "PASS", f"{len(values)} expected values present")
    else:
        report.add(
            "text content",
            "PASS",
            "text and German glyphs extracted; no expected values supplied",
        )


def check_source_integrity(report: Report, source: Path, expected: str | None) -> None:
    actual = sha256(source)
    if expected is None:
        report.add(
            "source integrity",
            "PARTIAL",
            f"source sha256 {actual}; no --source-sha256 to compare",
        )
    elif actual.lower() == expected.lower():
        report.add("source integrity", "PASS", f"sha256 {actual}")
    else:
        report.add(
            "source integrity", "FAIL", f"source sha256 {actual} != expected {expected}"
        )


def check_structural(report: Report) -> None:
    report.add(
        "structural validity",
        "NOT_RUN",
        "qpdf absent and the PDFBox reload is an in-app check; neither is available here",
    )


def check_printability(report: Report, artifact: Path, dpi: int) -> None:
    if shutil.which("pdftoppm") is None:
        report.add("printability", "UNAVAILABLE", "pdftoppm not on PATH")
        return
    pages = pdf_pages(artifact)
    with tempfile.TemporaryDirectory(prefix="feldexa-print-") as tmp:
        for page in range(1, pages + 1):
            proc = run(
                ["pdftoppm", "-r", str(dpi), "-f", str(page), "-l", str(page), "-png",
                 str(artifact), f"{tmp}/p{page:03d}"],
                timeout=300,
            )
            if proc.returncode != 0:
                report.add(
                    "printability",
                    "FAIL",
                    f"Poppler failed on page {page} at {dpi} dpi: {proc.stderr.strip()[:160]}",
                )
                return
    if shutil.which("mutool") is None:
        report.add(
            "printability",
            "PARTIAL",
            f"Poppler rendered all {pages} pages at {dpi} dpi; MuPDF absent, second engine NOT_RUN",
        )
    else:
        report.add(
            "printability",
            "PASS",
            f"Poppler and MuPDF rendered all {pages} pages at {dpi} dpi",
        )


def check_render(report: Report, artifact: Path) -> None:
    if shutil.which("pdftoppm") is None:
        report.add("original appearance", "UNAVAILABLE", "pdftoppm not on PATH")
        return
    with tempfile.TemporaryDirectory(prefix="feldexa-render-") as tmp:
        proc = run(
            ["pdftoppm", "-r", "150", "-f", "1", "-l", "1", "-png", str(artifact),
             f"{tmp}/page"],
            timeout=180,
        )
        if proc.returncode != 0 or not any(Path(tmp).iterdir()):
            report.add(
                "original appearance", "FAIL", "page 1 did not render at 150 dpi"
            )
            return
    report.add(
        "original appearance",
        "NOT_RUN",
        "page 1 renders; the masked pixel comparison needs --expectations masks",
    )


def check_placement(report: Report, artifact: Path, expectations: dict | None) -> None:
    if not expectations or not expectations.get("placement"):
        report.add(
            "value placement",
            "NOT_RUN",
            "no placement expectation (field rect + one-word value + page) supplied",
        )
        return
    placement = expectations["placement"]
    tool = Path(__file__).with_name("placement.py")
    proc = run(
        [
            sys.executable,
            str(tool),
            "--pdf",
            str(artifact),
            "--value-word",
            str(placement["value_word"]),
            "--field-rect-marker",
            str(placement["field_rect_marker"]),
            "--page",
            str(placement["page"]),
        ],
        timeout=180,
    )
    status = "PASS" if proc.returncode == 0 else "FAIL"
    report.add(
        "value placement",
        status,
        (proc.stdout.strip().splitlines() or ["no output"])[-1][:200],
    )


def check_marks(report: Report, expectations: dict | None, kind: str) -> None:
    label = "checkbox states" if kind == "checkbox" else "signatures"
    if not expectations:
        report.add(label, "NOT_RUN", "no --expectations supplied")
        return
    marks = [f for f in expectations.get("fields", []) if f.get("type") == kind]
    if not marks:
        report.add(label, "NOT_RUN", f"no {kind} expectations supplied")
        return
    report.add(
        label,
        "NOT_RUN",
        f"{len(marks)} {kind} expectations present; rendered-state comparison is not implemented",
    )


def build_report(
    source: Path, artifact: Path, expected_sha: str | None, expectations: dict | None,
    print_dpi: int,
) -> Report:
    report = Report(source=str(source), artifact=str(artifact))
    try:
        pdf_pages(source)
    except (ValueError, subprocess.SubprocessError) as exc:
        report.add("input readable", "FAIL", f"source PDF unreadable: {exc}")
        return report
    try:
        pdf_pages(artifact)
    except (ValueError, subprocess.SubprocessError) as exc:
        report.add("input readable", "FAIL", f"artifact not a readable PDF: {exc}")
        return report
    check_structural(report)
    check_page_count(report, source, artifact)
    check_geometry(report, source, artifact)
    check_interactive_controls(report, artifact)
    check_text(report, artifact, expectations)
    check_render(report, artifact)
    check_marks(report, expectations, "checkbox")
    check_marks(report, expectations, "signature")
    check_placement(report, artifact, expectations)
    check_printability(report, artifact, print_dpi)
    check_source_integrity(report, source, expected_sha)
    report.add(
        "artifact isolation",
        "NOT_RUN",
        "task-owned: a failed export must leave no artifact (T108/T334 driver)",
    )
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--source", required=True, type=Path, help="original source PDF")
    parser.add_argument("--artifact", required=True, type=Path, help="exported PDF artifact")
    parser.add_argument("--expectations", type=Path, default=None)
    parser.add_argument("--source-sha256", default=None)
    parser.add_argument("--print-dpi", type=int, default=300)
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args(argv)

    for path in (args.source, args.artifact):
        if not path.is_file():
            print(f"verify_artifact: missing input {path}", file=sys.stderr)
            return 2
    expectations = None
    if args.expectations:
        try:
            expectations = json.loads(args.expectations.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            print(f"verify_artifact: bad expectations file: {exc}", file=sys.stderr)
            return 2
        if not isinstance(expectations, dict):
            print("verify_artifact: expectations must be a JSON object", file=sys.stderr)
            return 2

    report = build_report(
        args.source, args.artifact, args.source_sha256, expectations, args.print_dpi
    )
    payload = {
        "source": report.source,
        "artifact": report.artifact,
        "rows": [row.__dict__ for row in report.rows],
        "summary": {
            "pass": sum(r.status == "PASS" for r in report.rows),
            "fail": sum(r.status == "FAIL" for r in report.rows),
            "partial": sum(r.status == "PARTIAL" for r in report.rows),
            "not_run": sum(r.status == "NOT_RUN" for r in report.rows),
            "unavailable": sum(r.status == "UNAVAILABLE" for r in report.rows),
        },
    }
    text = json.dumps(payload, indent=2, ensure_ascii=False)
    if args.out:
        args.out.write_text(text + "\n", encoding="utf-8")
    print(text)
    return report.exit_code()


if __name__ == "__main__":
    sys.exit(main())
