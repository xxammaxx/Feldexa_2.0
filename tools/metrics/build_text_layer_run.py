#!/usr/bin/env python3
"""Build a TEXT_LAYER run file for the T263 German OCR reference suite.

This is the **control path** required by issue #263: it extracts the printed
code points from the PDF text layer with an independent tool (Poppler
`pdftotext -bbox-layout`) instead of ML Kit. It proves what the generated PDF
really contains; it is never OCR evidence and never device evidence.

Poppler reports word bounding boxes in PDF points with the top-left origin,
which is exactly the display space the ground truth uses, so words are grouped
back into lines by their vertical centre and the resulting lines carry their
measured rectangles.

Usage:
  python3 tools/metrics/build_text_layer_run.py \
    --pdf tools/corpus/de-ocr/reference-de.pdf \
    --ground-truth tools/corpus/de-ocr/reference-de.ground-truth.json \
    --output <run.json> \
    [--variant text-layer-200dpi]

Exit codes: 0 written, 1 extraction/parse failure, 2 usage error.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ElementTree

NS = {"x": "http://www.w3.org/1999/xhtml"}


def sha256_of(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 16), b""):
            digest.update(chunk)
    return digest.hexdigest()


def extract_pages(pdf: pathlib.Path) -> list[list[dict]]:
    pdftotext = shutil.which("pdftotext")
    if pdftotext is None:
        raise SystemExit("error: pdftotext (Poppler) is required")
    result = subprocess.run(
        [pdftotext, "-bbox-layout", "-enc", "UTF-8", str(pdf), "-"],
        check=True,
        capture_output=True,
    )
    root = ElementTree.fromstring(result.stdout)
    pages: list[list[dict]] = []
    for page in root.findall(".//x:page", NS):
        words: list[dict] = []
        for word in page.findall(".//x:word", NS):
            text = (word.text or "").strip()
            if not text:
                continue
            words.append(
                {
                    "text": text,
                    "x": float(word.get("xMin", "0")),
                    "y": float(word.get("yMin", "0")),
                    "right": float(word.get("xMax", "0")),
                    "bottom": float(word.get("yMax", "0")),
                }
            )
        pages.append(group_words(words))
    return pages


def group_words(words: list[dict]) -> list[dict]:
    """Groups words into lines by vertical overlap and orders them by position."""
    lines: list[dict] = []
    for word in sorted(words, key=lambda item: (item["y"], item["x"])):
        centre = (word["y"] + word["bottom"]) / 2
        target = None
        for line in lines:
            line_centre = (line["y"] + line["bottom"]) / 2
            if abs(line_centre - centre) <= max(2.0, (line["bottom"] - line["y"])):
                target = line
                break
        if target is None:
            lines.append(
                {
                    "words": [word],
                    "x": word["x"],
                    "y": word["y"],
                    "right": word["right"],
                    "bottom": word["bottom"],
                }
            )
        else:
            target["words"].append(word)
            target["x"] = min(target["x"], word["x"])
            target["y"] = min(target["y"], word["y"])
            target["right"] = max(target["right"], word["right"])
            target["bottom"] = max(target["bottom"], word["bottom"])
    lines.sort(key=lambda item: (item["y"], item["x"]))
    return [
        {
            "text": " ".join(word["text"] for word in line["words"]),
            "rect": {
                "x": round(line["x"], 3),
                "y": round(line["y"], 3),
                "width": round(line["right"] - line["x"], 3),
                "height": round(line["bottom"] - line["y"], 3),
            },
            "confidence": None,
        }
        for line in lines
    ]


def main() -> int:
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--pdf", required=True)
    parser.add_argument("--ground-truth", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--variant", default="text-layer")
    parser.add_argument(
        "--geometry",
        default="595.28x841.89",
        help="page size in points, used only as metadata",
    )
    arguments = parser.parse_args()
    pdf = pathlib.Path(arguments.pdf)
    ground_truth_path = pathlib.Path(arguments.ground_truth)
    for path in (pdf, ground_truth_path):
        if not path.is_file():
            print(f"error: missing input {path}", file=sys.stderr)
            return 2
    ground_truth = json.loads(ground_truth_path.read_text(encoding="utf-8"))
    expected_sha = ground_truth["pdf"]["sha256"]
    actual_sha = sha256_of(pdf)
    if actual_sha != expected_sha:
        print(
            f"error: {pdf} sha256 {actual_sha} is not the annotated {expected_sha}",
            file=sys.stderr,
        )
        return 1
    try:
        pages = extract_pages(pdf)
    except (subprocess.CalledProcessError, ElementTree.ParseError) as error:
        print(f"error: text-layer extraction failed: {error}", file=sys.stderr)
        return 1
    width, _, height = arguments.geometry.partition("x")
    run = {
        "schemaVersion": 1,
        "suiteId": ground_truth["suiteId"],
        "fixtureId": ground_truth["fixtureId"],
        "fixtureSha256": expected_sha,
        "engine": "pdftotext-text-layer",
        "evidenceClass": "TEXT_LAYER",
        "runner": {
            "kind": "host-text-layer",
            "tool": "pdftotext -bbox-layout",
            "pdf": str(pdf),
        },
        "generatedAtUtc": None,
        "variants": [
            {
                "id": arguments.variant,
                "raster": {
                    "source": "pdf-text-layer",
                    "dpi": None,
                    "degradations": [],
                },
                "timings": {},
                "pages": [
                    {
                        "index": index,
                        "widthPt": float(width),
                        "heightPt": float(height),
                        "lines": lines,
                    }
                    for index, lines in enumerate(pages)
                ],
            }
        ],
    }
    output = pathlib.Path(arguments.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(run, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"wrote {output} ({sum(len(page['lines']) for page in run['variants'][0]['pages'])} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
