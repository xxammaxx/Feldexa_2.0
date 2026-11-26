#!/usr/bin/env python3
"""Writes the synthetic AcroForm reference fixture (issue #344 part B).

The fixture is a one-page PDF that carries exactly **one** interactive
AcroForm text field (`/FT /Tx`) with a widget annotation and a normal
appearance (`/AP /N`) whose visible content is the field value ``Feldwert``.
It exists so the export flattening (`PdfExportService.flattenSourceAcroForm`,
`contracts/export-plan.md` §5 step 2a/3, FR-069) can be proven against a source
that really has form fields — the other synthetic fixtures carry none.

Reproducible: the object order, the document id, the content, and the xref
offsets are fixed, so the bytes depend on nothing but this file. ``--check``
regenerates in memory and fails on any drift from the committed files.

Usage (repo root):

    python3 tools/corpus/synthetic/make_acroform_fixture.py          # write
    python3 tools/corpus/synthetic/make_acroform_fixture.py --check  # verify

The fixture is synthetic: no real form, no real person, no personal data. The
visible text is fictional; the base-14 Helvetica is not embedded.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

FIXTURE_ID = "sf-acroform-001"
CANONICAL_DIRECTORY = "apps/feldexa_app/assets/fixtures"
WEB_DIRECTORY = "apps/feldexa_app/web/fixtures"
# The integrity test requires the canonical, the Web mirror, and the drift-free
# corpus copy to be byte-identical ("three copies are always in sync").
CORPUS_DIRECTORY = "tools/corpus/synthetic"

# Fictional visible content. ``FIELD_VALUE`` is the text the host driver expects
# back from `pdftotext` after the export flattened the field: the value lives in
# the widget appearance, so a flattening that dropped appearances would lose it.
PAGE_TITLE = "Synthetisches AcroForm-Testformular"
FIELD_LABEL = "Familienname:"
FIELD_VALUE = "Feldwert"
FOOTER = "Synthetische Testdaten, keine personenbezogenen Daten."

PAGE_WIDTH = 595
PAGE_HEIGHT = 842
FIELD_RECT = (56, 690, 356, 708)

# Fixed document id: ASCII "FELDEXAFIXTURE01" as a hex string, the same shape
# the other synthetic fixtures use. A fixed id keeps the bytes reproducible.
DOCUMENT_ID_HEX = "46454C44455841464958545552453031"


def _escape_pdf_text(text: str) -> str:
    return text.replace("\\", r"\\").replace("(", r"\(").replace(")", r"\)")


def _text_op(font: str, size: int, x: int, y: int, text: str) -> str:
    return (
        f"BT /{font} {size} Tf {x} {y} Td ({_escape_pdf_text(text)}) Tj ET"
    )


def _page_content() -> bytes:
    left, bottom, right, _top = FIELD_RECT
    ops = [
        # A visible marker plus the field label: the page itself carries no
        # value, so only the flattened appearance can put ``Feldwert`` into the
        # exported text layer.
        "0.8 w",
        _text_op("F1", 14, 56, 780, PAGE_TITLE),
        _text_op("F1", 10, 56, 716, FIELD_LABEL),
        f"{left} {bottom} m {right} {bottom} l S",
        _text_op("F1", 8, 56, 660, FOOTER),
    ]
    return ("\n".join(ops) + "\n").encode("latin-1")


def _appearance_content() -> bytes:
    ops = [_text_op("Helv", 10, 3, 5, FIELD_VALUE)]
    return ("\n".join(ops) + "\n").encode("latin-1")


def build_pdf() -> bytes:
    content = _page_content()
    appearance = _appearance_content()
    left, bottom, right, top = FIELD_RECT
    width = right - left
    height = top - bottom

    objects: list[bytes] = [
        # 1 catalog: /AcroForm is the marker `pdfinfo` reports as
        # "Form: AcroForm".
        (
            b"<< /Type /Catalog /Pages 2 0 R /AcroForm << "
            b"/Fields [7 0 R] /DA (/Helv 0 Tf 0 g) "
            b"/DR << /Font << /Helv 5 0 R >> >> /NeedAppearances false "
            b">> >>"
        ),
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {PAGE_WIDTH} "
            f"{PAGE_HEIGHT}] /Resources << /Font << /F1 5 0 R >> >> "
            f"/Contents 4 0 R /Annots [7 0 R] >>"
        ).encode("ascii"),
        b"<< /Length %d >>\nstream\n" % len(content) + content + b"endstream",
        (
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica "
            b"/Encoding /WinAnsiEncoding >>"
        ),
        (
            f"<< /Type /XObject /Subtype /Form /FormType 1 "
            f"/BBox [0 0 {width} {height}] "
            f"/Resources << /Font << /Helv 5 0 R >> >> /Length "
            f"{len(appearance)} >>\nstream\n"
        ).encode("ascii")
        + appearance
        + b"endstream",
        (
            f"<< /Type /Annot /Subtype /Widget /FT /Tx /T (familienname) "
            f"/V ({_escape_pdf_text(FIELD_VALUE)}) "
            f"/Rect [{left} {bottom} {right} {top}] /F 4 /P 3 0 R "
            f"/DA (/Helv 10 Tf 0 g) /AP << /N 6 0 R >> >>"
        ).encode("latin-1"),
    ]

    out = bytearray(b"%PDF-1.7\n%FELDEXA-SYNTHETIC-FIXTURE\n")
    offsets: list[int] = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % number + body + b"\nendobj\n"

    xref_offset = len(out)
    out += b"xref\n0 %d\n" % (len(objects) + 1)
    out += b"0000000000 65535 f \n"
    for offset in offsets:
        out += b"%010d 00000 n \n" % offset
    out += (
        b"trailer\n<< /Size %d /Root 1 0 R /ID [<%s> <%s>] >>\nstartxref\n%d\n%%%%EOF\n"
        % (
            len(objects) + 1,
            DOCUMENT_ID_HEX.encode("ascii"),
            DOCUMENT_ID_HEX.encode("ascii"),
            xref_offset,
        )
    )
    return bytes(out)


def _targets(root: Path) -> dict[str, bytes]:
    data = build_pdf()
    return {
        f"{CANONICAL_DIRECTORY}/{FIXTURE_ID}.pdf": data,
        f"{WEB_DIRECTORY}/{FIXTURE_ID}.pdf": data,
        f"{CORPUS_DIRECTORY}/{FIXTURE_ID}.pdf": data,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="repository root")
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the committed files instead of writing them",
    )
    options = parser.parse_args(argv)
    root = Path(options.root)
    targets = _targets(root)

    if options.check:
        current = True
        for relative, expected in targets.items():
            path = root / relative
            if not path.exists():
                print(f"MISSING {relative}")
                current = False
                continue
            actual = path.read_bytes()
            if actual != expected:
                print(
                    f"DRIFT {relative} (expected {len(expected)} bytes "
                    f"sha256 {hashlib.sha256(expected).hexdigest()}; actual "
                    f"{len(actual)} bytes sha256 "
                    f"{hashlib.sha256(actual).hexdigest()})"
                )
                current = False
        if current:
            data = targets[next(iter(targets))]
            print(
                f"OK {FIXTURE_ID} is byte-for-byte current "
                f"({len(data)} bytes, sha256 {hashlib.sha256(data).hexdigest()})"
            )
            return 0
        print(f"FAIL {FIXTURE_ID} drifts from its committed bytes")
        return 1

    for relative, data in targets.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        print(
            f"wrote {relative} ({len(data)} bytes, "
            f"sha256 {hashlib.sha256(data).hexdigest()})"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
