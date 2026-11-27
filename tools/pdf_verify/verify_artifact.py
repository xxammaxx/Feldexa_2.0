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
* per-page MediaBox size and page rotation equality within 0.01 pt,
* absence of ``/AcroForm`` and ``/Widget`` in the artifact bytes,
* text extraction and German glyph presence,
* a 150 dpi render of page 1 and 300 dpi renders of every page (Poppler; MuPDF
  is executed when present and otherwise reported PARTIAL),
* SHA-256 of the source file (unchanged).

Rows that need ``--expectations FIELD_JSON`` (values, field rects, checkbox and
signature states, appearance masks):
* text content against expected values,
* value placement (delegated to ``placement.py`` semantics where a rect and a
  value word are supplied),
* checkbox state and signature presence.
The masked appearance comparison and the no-clipping measurement are NOT
implemented; they report ``NOT_RUN`` with that reason (not with a missing input).

Usage:
  verify_artifact.py --source SRC.pdf --artifact ART.pdf [--expectations F.json]
                     [--source-sha256 HEX] [--out report.json] [--print-dpi 300]

Exit codes: 0 no row FAILed (PARTIAL/NOT_RUN/UNAVAILABLE rows may be present and
are listed in the JSON summary), 1 at least one row FAIL, 2 usage/input error.
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


def parse_page_sizes(text: str, pages: int) -> list[tuple[float, float, int]]:
    """(width, height, rotation) per page parsed from pdfinfo text."""
    sizes: list[tuple[float, float, int]] = []
    blocks = re.findall(
        r"^Page\s+(\d+)\s+size:\s+([\d.]+)\s+x\s+([\d.]+)\s+pts.*$",
        text,
        re.M,
    )
    rotations = {
        int(m.group(1)): int(m.group(2))
        for m in re.finditer(r"^Page\s+(\d+)\s+rot:\s+(-?\d+)", text, re.M)
    }
    for page, width, height in blocks:
        sizes.append((float(width), float(height), rotations.get(int(page), 0)))
    if not sizes:
        single = re.search(r"^Page size:\s+([\d.]+)\s+x\s+([\d.]+)\s+pts", text, re.M)
        rot = re.search(r"^Page rot:\s+(-?\d+)", text, re.M)
        if single:
            sizes = [
                (float(single.group(1)), float(single.group(2)), int(rot.group(1)) if rot else 0)
            ] * pages
    return sizes


def page_sizes(path: Path, pages: int) -> list[tuple[float, float, int]]:
    out = run(["pdfinfo", "-f", "1", "-l", str(pages), str(path)]).stdout
    return parse_page_sizes(out, pages)


def sizes_equal(
    src: list[tuple[float, float, int]], art: list[tuple[float, float, int]]
) -> tuple[bool, str]:
    if len(src) != len(art) or not src:
        return False, f"parsed {len(src)} source and {len(art)} artifact page sizes"
    for index, (a, b) in enumerate(zip(src, art), start=1):
        if (
            abs(a[0] - b[0]) > GEOMETRY_TOLERANCE_PT
            or abs(a[1] - b[1]) > GEOMETRY_TOLERANCE_PT
            or a[2] != b[2]
        ):
            return False, (
                f"page {index}: source {a[0]:.2f}x{a[1]:.2f} rot {a[2]}, "
                f"artifact {b[0]:.2f}x{b[1]:.2f} rot {b[2]}"
            )
    return True, ""


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
    equal, detail = sizes_equal(src, art)
    if equal:
        report.add(
            "page geometry",
            "PASS",
            f"{source_pages} pages, sizes and rotations equal within "
            f"{GEOMETRY_TOLERANCE_PT} pt (pdfinfo MediaBox/rot)",
        )
    else:
        report.add("page geometry", "FAIL", detail)


def check_page_count(report: Report, source: Path, artifact: Path) -> None:
    if shutil.which("pdfinfo") is None:
        report.add("page count and order", "UNAVAILABLE", "pdfinfo not on PATH")
        return
    a, b = pdf_pages(source), pdf_pages(artifact)
    if a != b:
        report.add("page count and order", "FAIL", f"source {a} pages, artifact {b}")
        return
    src, art = page_sizes(source, a), page_sizes(artifact, b)
    if [s[:2] for s in src] == [s[:2] for s in art]:
        report.add(
            "page count and order",
            "PASS",
            f"{a} pages; order proxy (page-size sequence) equal. Uniform-size pages "
            "cannot prove order; a per-page content hash is not implemented",
        )
    else:
        report.add(
            "page count and order",
            "FAIL",
            "page-size sequence differs; page order or geometry changed",
        )


def check_interactive_controls(report: Report, artifact: Path) -> None:
    data = artifact.read_bytes()
    acroform = data.count(b"/AcroForm")
    widget = data.count(b"/Widget")
    form_line = ""
    if shutil.which("pdfinfo"):
        info = run(["pdfinfo", str(artifact)]).stdout
        match = re.search(r"^Form:\s+(.+)$", info, re.M)
        form_line = match.group(1).strip() if match else ""
    if not shutil.which("pdfinfo"):
        if acroform == 0 and widget == 0:
            report.add(
                "no interactive controls",
                "PARTIAL",
                "byte scan found no /AcroForm or /Widget; pdfinfo unavailable, so no structural cross-check",
            )
        else:
            report.add(
                "no interactive controls",
                "FAIL",
                f"/AcroForm x{acroform}, /Widget x{widget}",
            )
        return
    structural_says_none = form_line.lower() in {"none", ""}
    if acroform == 0 and widget == 0 and structural_says_none:
        report.add(
            "no interactive controls",
            "PASS",
            "no /AcroForm and no /Widget in the bytes; pdfinfo Form: none. "
            "Byte scan is not a full structural parse",
        )
    elif acroform or widget or not structural_says_none:
        report.add(
            "no interactive controls",
            "FAIL",
            f"/AcroForm x{acroform}, /Widget x{widget}, pdfinfo Form: {form_line or 'absent'}",
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
        mutool = shutil.which("mutool")
        if mutool is None:
            report.add(
                "printability",
                "PARTIAL",
                f"Poppler rendered all {pages} pages at {dpi} dpi; muPDF absent, "
                "second engine NOT_RUN",
            )
            return
        for page in range(1, pages + 1):
            proc = run(
                [mutool, "draw", "-r", str(dpi), "-o", f"{tmp}/m{page:03d}.png",
                 str(artifact), str(page)],
                timeout=300,
            )
            if proc.returncode != 0:
                report.add(
                    "printability",
                    "FAIL",
                    f"MuPDF failed on page {page} at {dpi} dpi: {proc.stderr.strip()[:160]}",
                )
                return
        rendered = [p for p in Path(tmp).glob("*") if p.stat().st_size > 0]
        if len(rendered) < 2 * pages:
            report.add(
                "printability",
                "FAIL",
                f"only {len(rendered)} non-empty renders for {pages} pages x 2 engines",
            )
            return
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
        "page 1 renders at 150 dpi; the masked pixel comparison is not implemented "
        "(no ImageMagick compare wiring), so no appearance PASS is claimed",
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


def check_clipping(report: Report) -> None:
    report.add(
        "no clipping",
        "NOT_RUN",
        "not implemented: needs the pdftotext -bbox / ascender-tolerance measurement "
        "from placement.py; no clipping PASS is claimed",
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
    except (ValueError, OSError, subprocess.SubprocessError) as exc:
        report.add("input readable", "FAIL", f"source PDF unreadable: {exc}")
        return report
    try:
        pdf_pages(artifact)
    except (ValueError, OSError, subprocess.SubprocessError) as exc:
        report.add("input readable", "FAIL", f"artifact not a readable PDF: {exc}")
        return report
    def guarded(check: str, run_check) -> None:
        try:
            run_check()
        except Exception as exc:  # noqa: BLE001 - a crashed row must not become a traceback
            report.add(check, "FAIL", f"check crashed: {type(exc).__name__}: {exc}")

    guarded("structural validity", lambda: check_structural(report))
    guarded("page count and order", lambda: check_page_count(report, source, artifact))
    guarded("page geometry", lambda: check_geometry(report, source, artifact))
    guarded("no interactive controls", lambda: check_interactive_controls(report, artifact))
    guarded("text content", lambda: check_text(report, artifact, expectations))
    guarded("original appearance", lambda: check_render(report, artifact))
    guarded("no clipping", lambda: check_clipping(report))
    guarded("checkbox states", lambda: check_marks(report, expectations, "checkbox"))
    guarded("signatures", lambda: check_marks(report, expectations, "signature"))
    guarded("value placement", lambda: check_placement(report, artifact, expectations))
    guarded("printability", lambda: check_printability(report, artifact, print_dpi))
    guarded("source integrity", lambda: check_source_integrity(report, source, expected_sha))
    report.add(
        "artifact isolation",
        "NOT_RUN",
        "task-owned: a failed export must leave no artifact (T108/T334 driver)",
    )
    return report
    try:
        pdf_pages(artifact)
    except (ValueError, OSError, subprocess.SubprocessError) as exc:
        report.add("input readable", "FAIL", f"artifact not a readable PDF: {exc}")
        return report
    check_structural(report)
    check_page_count(report, source, artifact)
    check_geometry(report, source, artifact)
    check_interactive_controls(report, artifact)
    check_text(report, artifact, expectations)
    check_render(report, artifact)
    check_clipping(report)
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
