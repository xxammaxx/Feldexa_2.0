#!/usr/bin/env python3
"""Export-artifact verification harness (T105, contracts/export-plan.md §6).

Runs every tool-executable §6 row against one artifact PDF and reports
PASS / FAIL / PARTIAL / NOT_RUN / UNAVAILABLE per row. Rows that need an input
the caller did not supply report NOT_RUN with the missing input; the harness
never invents a PASS.

Without extra inputs it verifies: structural validity (``qpdf --check``), page
count and page-size sequence, per-page size and rotation, absence of
``/AcroForm``/``/Widget``, text and German glyphs, 300 dpi printability with
Poppler and, when present, MuPDF, and the source SHA-256.

With ``--expectations FIELD_JSON`` it additionally verifies: a masked 72-dpi
appearance diff outside the mask rects, the no-clipping measurement (every word
box inside its page; expected values inside rect + 1 mm), value placement
inside rect + 1 mm with the 0.61 mm ascent allowance (Q3=B), checkbox and
signature marks by rendered ink density against the source, and expected text
values.

Expectations shape::

    {
      "fields": [{"page": 1, "rect": [x, y, w, h], "type": "text", "value": "..."}],
      "marks":  [{"page": 1, "rect": [x, y, w, h], "type": "checkbox|signature",
                  "expected": "marked"|"empty"}],
      "masks":  [{"page": 1, "rect": [x, y, w, h]}]
    }

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


def check_structural(report: Report, artifact: Path) -> None:
    qpdf = shutil.which("qpdf")
    if qpdf is None:
        report.add(
            "structural validity",
            "NOT_RUN",
            "qpdf absent and the PDFBox reload is an in-app check; neither is available here",
        )
        return
    proc = run([qpdf, "--check", str(artifact)], timeout=180)
    if proc.returncode == 0:
        report.add("structural validity", "PASS", "qpdf --check exit 0")
    else:
        detail = (proc.stdout + proc.stderr).strip().splitlines()
        report.add(
            "structural validity",
            "FAIL",
            "qpdf --check failed: " + (detail[-1][:180] if detail else f"exit {proc.returncode}"),
        )


def _read_ppm(path: Path) -> tuple[int, int, bytes]:
    data = path.read_bytes()
    if not data.startswith(b"P6"):
        raise ValueError(f"{path} is not a P6 PPM")
    fields: list[bytes] = []
    index = 2
    while len(fields) < 3:
        while index < len(data) and data[index : index + 1].isspace():
            index += 1
        if data[index : index + 1] == b"#":
            while index < len(data) and data[index] != 0x0A:
                index += 1
            continue
        start = index
        while index < len(data) and not data[index : index + 1].isspace():
            index += 1
        fields.append(data[start:index])
    index += 1
    width, height, maxval = (int(f) for f in fields)
    if maxval != 255:
        raise ValueError(f"unsupported PPM maxval {maxval}")
    payload = data[index : index + width * height * 3]
    if len(payload) != width * height * 3:
        raise ValueError(f"truncated PPM payload: {len(payload)} of {width * height * 3} bytes")
    return width, height, payload


def _render_page(path: Path, page: int, dpi: int, tmp: Path) -> tuple[int, int, bytes]:
    target = tmp / f"{path.stem}-{page}-{dpi}"
    proc = run(
        ["pdftoppm", "-r", str(dpi), "-f", str(page), "-l", str(page), "-singlefile", str(path), str(target)],
        timeout=300,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"pdftoppm failed on page {page}: {proc.stderr.strip()[:160]}")
    candidates = sorted(tmp.glob(f"{target.name}*.ppm"))
    if not candidates:
        raise RuntimeError(f"pdftoppm produced no PPM for page {page}")
    return _read_ppm(candidates[0])


def _rect_pixels(rect: list[float], dpi: int) -> tuple[int, int, int, int]:
    """Pixel coverage of a top-down point rect: floor(origin), ceil(far edge)."""
    import math

    scale = dpi / 72.0
    x, y, w, h = rect
    return (
        max(0, math.floor(x * scale)),
        max(0, math.floor(y * scale)),
        math.ceil((x + w) * scale),
        math.ceil((y + h) * scale),
    )


def _ink_pixels(raster: tuple[int, int, bytes], rect: list[float], dpi: int) -> int:
    width, height, pixels = raster
    x0, y0, x1, y1 = _rect_pixels(rect, dpi)
    ink = 0
    for y in range(max(0, y0), min(height, y1)):
        row = y * width * 3
        for x in range(max(0, x0), min(width, x1)):
            offset = row + x * 3
            if min(pixels[offset : offset + 3]) < 200:
                ink += 1
    return ink


def check_appearance(report: Report, source: Path, artifact: Path, expectations: dict | None) -> None:
    masks = (expectations or {}).get("masks")
    if not masks:
        report.add(
            "original appearance",
            "NOT_RUN",
            "masked pixel comparison needs --expectations masks (field rects); without them the value overlay cannot be excluded",
        )
        return
    total_pages = min(pdf_pages(source), pdf_pages(artifact))
    pages = min(total_pages, 10)
    with tempfile.TemporaryDirectory(prefix="feldexa-appearance-") as tmp:
        tmp_path = Path(tmp)
        for page in range(1, pages + 1):
            src = _render_page(source, page, 72, tmp_path)
            art = _render_page(artifact, page, 72, tmp_path)
            if src[:2] != art[:2] or src[2] != art[2]:
                differing = 0
                width, height, src_px = src
                _, _, art_px = art
                page_masks = [m["rect"] for m in masks if int(m.get("page", 1)) == page]
                for y in range(height):
                    for x in range(width):
                        if any(
                            x0 <= x < x1 and y0 <= y < y1
                            for x0, y0, x1, y1 in (_rect_pixels(r, 72) for r in page_masks)
                        ):
                            continue
                        offset = (y * width + x) * 3
                        if src_px[offset : offset + 3] != art_px[offset : offset + 3]:
                            differing += 1
                if differing:
                    report.add(
                        "original appearance",
                        "FAIL",
                        f"page {page}: {differing} pixels differ outside the masks",
                    )
                    return
    if pages < total_pages:
        report.add(
            "original appearance",
            "PARTIAL",
            f"{pages} of {total_pages} pages compared (cap 10), pixel-identical outside "
            f"{len(masks)} mask(s) at 72 dpi",
        )
    else:
        report.add(
            "original appearance",
            "PASS",
            f"{pages} page(s) pixel-identical outside {len(masks)} mask(s) at 72 dpi",
        )


def check_clipping(report: Report, artifact: Path, expectations: dict | None) -> None:
    if shutil.which("pdftotext") is None:
        report.add("no clipping", "UNAVAILABLE", "pdftotext not on PATH")
        return
    fields = [f for f in (expectations or {}).get("fields", []) if f.get("value") and f.get("rect")]
    if not fields:
        report.add(
            "no clipping",
            "NOT_RUN",
            "no value expectation (value + rect) supplied; page-bound checks alone do not prove clipping",
        )
        return
    out = run(["pdftotext", "-bbox", str(artifact), "-"]).stdout
    page_blocks = re.findall(
        r'<page width="([\d.]+)" height="([\d.]+)">(.*?)</page>', out, re.S
    )
    if not page_blocks:
        report.add("no clipping", "FAIL", "pdftotext -bbox reported no pages")
        return
    outside: list[str] = []
    tolerance = 2.835
    checked = 0
    for page_no, (page_width, page_height, body) in enumerate(page_blocks, start=1):
        width, height = float(page_width), float(page_height)
        for match in re.finditer(
            r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">',
            body,
        ):
            x0, y0, x1, y1 = (float(v) for v in match.groups())
            if x0 < -0.5 or y0 < -0.5 or x1 > width + 0.5 or y1 > height + 0.5:
                outside.append(f"p{page_no} word outside page")
        for field in fields:
            if int(field.get("page", 1)) != page_no:
                continue
            value = str(field["value"])
            x, y, w, h = (float(v) for v in field["rect"])
            matched = re.search(
                r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">'
                + re.escape(value),
                body,
            )
            if not matched:
                continue
            checked += 1
            x0, y0, x1, y1 = (float(v) for v in matched.groups())
            if (
                x0 < x - tolerance
                or y0 < y - tolerance
                or x1 > x + w + tolerance
                or y1 > y + h + tolerance
            ):
                outside.append(f"p{page_no} value {value!r} outside rect+tolerance")
    if outside:
        report.add("no clipping", "FAIL", "; ".join(outside[:4]))
        return
    if checked == 0:
        report.add("no clipping", "NOT_RUN", "expected values not found as words")
        return
    report.add(
        "no clipping",
        "PASS",
        f"all word boxes inside their page; {checked} value(s) inside rect+1 mm",
    )


def check_placement(report: Report, artifact: Path, expectations: dict | None) -> None:
    fields = [f for f in (expectations or {}).get("fields", []) if f.get("value") and f.get("rect")]
    if not fields:
        report.add(
            "value placement",
            "NOT_RUN",
            "no expectation with value + rect supplied",
        )
        return
    out = run(["pdftotext", "-bbox", str(artifact), "-"]).stdout
    blocks = {
        index: body
        for index, body in enumerate(
            re.findall(r"<page [^>]*>(.*?)</page>", out, re.S), start=1
        )
    }
    tolerance = 2.835
    ascent_tolerance = 0.61 * 72 / 25.4
    checked = 0
    worst_ascent = 0.0
    for field in fields:
        page = int(field.get("page", 1))
        body = blocks.get(page)
        if body is None:
            report.add("value placement", "NOT_RUN", f"page {page} not present in artifact")
            return
        value = str(field["value"])
        pattern = re.compile(
            r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">'
            + re.escape(value)
        )
        matches = pattern.findall(body)
        if len(matches) > 1:
            report.add(
                "value placement",
                "NOT_RUN",
                f"value {value!r} occurs {len(matches)} times on page {page}; placement is ambiguous",
            )
            return
        if not matches:
            continue
        checked += 1
        x0, y0, x1, y1 = (float(v) for v in matches[0])
        x, y, w, h = (float(v) for v in field["rect"])
        if (
            x0 < x - tolerance
            or x1 > x + w + tolerance
            or y1 > y + h + tolerance
            or y0 < y - ascent_tolerance
        ):
            report.add(
                "value placement",
                "FAIL",
                f"value {value!r} box {x0:.2f},{y0:.2f},{x1:.2f},{y1:.2f} outside rect+1 mm "
                f"(ascent 0.61 mm)",
            )
            return
        worst_ascent = max(worst_ascent, max(0.0, y - y0))
    if checked == 0:
        report.add("value placement", "NOT_RUN", "expected values not found as words")
        return
    report.add(
        "value placement",
        "PASS",
        f"{checked} value(s) inside rect+1 mm; max ascent overflow {worst_ascent:.2f} pt "
        "<= 0.61 mm",
    )


def check_marks(
    report: Report, source: Path, artifact: Path, expectations: dict | None, kind: str
) -> None:
    label = "checkbox states" if kind == "checkbox" else "signatures"
    marks = [m for m in (expectations or {}).get("marks", []) if m.get("type") == kind]
    if not marks:
        report.add(label, "NOT_RUN", f"no {kind} expectations supplied")
        return
    with tempfile.TemporaryDirectory(prefix=f"feldexa-{kind}-") as tmp:
        tmp_path = Path(tmp)
        for mark in marks:
            page = int(mark.get("page", 1))
            src = _render_page(source, page, 150, tmp_path)
            art = _render_page(artifact, page, 150, tmp_path)
            src_ink = _ink_pixels(src, mark["rect"], 150)
            art_ink = _ink_pixels(art, mark["rect"], 150)
            expected = mark.get("expected", "marked")
            if expected == "marked" and art_ink <= src_ink:
                report.add(label, "FAIL", f"expected a mark on page {page}, ink {src_ink}->{art_ink}")
                return
            if expected == "empty" and art_ink > src_ink + 50:
                report.add(label, "FAIL", f"expected no mark on page {page}, ink {src_ink}->{art_ink}")
                return
    report.add(label, "PASS", f"{len(marks)} {kind} expectation(s) matched at 150 dpi")


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
                "second engine not run",
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

    guarded("structural validity", lambda: check_structural(report, artifact))
    guarded("page count and order", lambda: check_page_count(report, source, artifact))
    guarded("page geometry", lambda: check_geometry(report, source, artifact))
    guarded("no interactive controls", lambda: check_interactive_controls(report, artifact))
    guarded("text content", lambda: check_text(report, artifact, expectations))
    guarded("original appearance", lambda: check_appearance(report, source, artifact, expectations))
    guarded("no clipping", lambda: check_clipping(report, artifact, expectations))
    guarded("checkbox states", lambda: check_marks(report, source, artifact, expectations, "checkbox"))
    guarded("signatures", lambda: check_marks(report, source, artifact, expectations, "signature"))
    guarded("value placement", lambda: check_placement(report, artifact, expectations))
    guarded("printability", lambda: check_printability(report, artifact, print_dpi))
    guarded("source integrity", lambda: check_source_integrity(report, source, expected_sha))
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
