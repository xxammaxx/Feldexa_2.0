#!/usr/bin/env python3
"""Build the T263 raster variants for the German OCR reference suite.

The clean variants are rendered on the device by the production raster port
(PDFium through pdfrx). The degraded variants are simulated **scan captures**:
this host script renders the same reference PDF with Poppler, applies a
documented pixel degradation, and writes a raw `gray8` raster that the device
then feeds to the **production** ML Kit OCR port. Nothing here replaces the OCR
engine; the injected part is only the pixel buffer, which is why those run
variants carry the evidence class `EMULATOR_INJECTED_RASTER`.

Every injected raster is normalised to the fixed 200 DPI analysis raster size
(1654 x 2339 pixels for A4), because the production pipeline maps pixels to
page points with the fixed `200 / 72` analysis scale. A 150 DPI capture is
therefore upsampled to that pixel grid; the resolution loss stays in the
content, while the geometry mapping the pipeline assumes stays valid. The
declared `dpi` records the capture resolution, `rasterDpi` the grid actually
delivered.

Degradations (declared before the run):
  low-contrast   luminance is compressed linearly into [70, 200] and shifted
  shadow         a multiplicative shadow gradient darkens the top-left corner
  skew-3deg      the page content is rotated by three degrees about the centre
  jpeg-q35       a JPEG round trip at quality 35 (ImageMagick)

Usage:
  python3 tools/corpus/de-ocr/make_variants.py \
    --pdf tools/corpus/de-ocr/reference-de.pdf \
    --output <directory> [--only <variant-id> ...]

Outputs `<directory>/t263-variants.json` plus one `.gray8` file per page.

Exit codes: 0 written, 1 rendering/degradation failure, 2 usage error.
"""
from __future__ import annotations

import argparse
import json
import math
import pathlib
import shutil
import subprocess
import sys

PAGE_WIDTH_PT = 595.28
PAGE_HEIGHT_PT = 841.89

CLEAN_VARIANTS = (
    ("clean-200dpi", 200),
    ("clean-150dpi", 150),
    ("clean-300dpi", 300),
)

DEGRADED_VARIANTS = (
    ("scan-150dpi-low-contrast", 150, "low-contrast"),
    ("scan-200dpi-shadow", 200, "shadow"),
    ("scan-200dpi-skew-3deg", 200, "skew-3deg"),
    ("scan-200dpi-jpeg-q35", 200, "jpeg-q35"),
)


def run(command: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(command, check=True, capture_output=True)


ANALYSIS_DPI = 200


def analysis_size(dpi: int) -> tuple[int, int]:
    return (
        round(PAGE_WIDTH_PT / 72.0 * dpi),
        round(PAGE_HEIGHT_PT / 72.0 * dpi),
    )


def resample_pgm(path: pathlib.Path, width: int, height: int) -> None:
    """Resamples a PGM to the fixed analysis raster size (bilinear filter)."""
    magick = shutil.which("magick") or shutil.which("convert")
    if magick is None:
        raise SystemExit("error: ImageMagick is required for resampling")
    run(
        [
            magick,
            str(path),
            "-filter",
            "Triangle",
            "-resize",
            f"{width}x{height}!",
            str(path),
        ]
    )


def render_pages(pdf: pathlib.Path, dpi: int, directory: pathlib.Path) -> list[pathlib.Path]:
    """Renders the PDF to one binary PGM per page with Poppler."""
    pdftoppm = shutil.which("pdftoppm")
    if pdftoppm is None:
        raise SystemExit("error: pdftoppm (Poppler) is required")
    prefix = directory / f"render-{dpi}"
    run(
        [
            pdftoppm,
            "-r",
            str(dpi),
            "-gray",
            "-png",
            str(pdf),
            str(prefix),
        ]
    )
    pngs = sorted(directory.glob(f"render-{dpi}-*.png"))
    if not pngs:
        raise SystemExit(f"error: poppler produced no pages for {dpi} dpi")
    pages: list[pathlib.Path] = []
    magick = shutil.which("magick") or shutil.which("convert")
    if magick is None:
        raise SystemExit("error: ImageMagick is required for the gray8 conversion")
    for index, png in enumerate(pngs, start=1):
        pgm = directory / f"render-{dpi}-page{index}.pgm"
        run([magick, str(png), "-colorspace", "Gray", "-depth", "8", str(pgm)])
        pages.append(pgm)
    return pages


def read_pgm(path: pathlib.Path) -> tuple[int, int, bytearray]:
    data = path.read_bytes()
    tokens: list[bytes] = []
    index = 0
    while len(tokens) < 4 and index < len(data):
        if data[index : index + 1] == b"#":
            while index < len(data) and data[index : index + 1] not in (b"\n", b"\r"):
                index += 1
            continue
        if data[index : index + 1].isspace():
            index += 1
            continue
        start = index
        while index < len(data) and not data[index : index + 1].isspace():
            index += 1
        tokens.append(data[start:index])
    if len(tokens) < 4 or tokens[0] != b"P5":
        raise SystemExit(f"error: {path} is not a binary PGM (P5)")
    width = int(tokens[1])
    height = int(tokens[2])
    maxval = int(tokens[3])
    index += 1  # single whitespace after maxval
    pixels = bytearray(data[index : index + width * height])
    if len(pixels) != width * height:
        raise SystemExit(f"error: {path} has an unexpected pixel count")
    if maxval != 255:
        raise SystemExit(f"error: {path} is not 8-bit")
    return width, height, pixels


def write_gray8(path: pathlib.Path, width: int, height: int, pixels: bytearray) -> None:
    """Writes the raw gray8 buffer the device OCR port expects."""
    path.write_bytes(bytes(pixels))


def write_pgm(path: pathlib.Path, width: int, height: int, pixels: bytearray) -> None:
    """Writes a binary PGM (P5) for the ImageMagick round trip."""
    path.write_bytes(b"P5\n%d %d\n255\n" % (width, height) + bytes(pixels))


def low_contrast(pixels: bytearray) -> bytearray:
    return bytearray(min(255, max(0, 70 + (value * 130) // 255)) for value in pixels)


def shadow(width: int, height: int, pixels: bytearray) -> bytearray:
    radius = math.hypot(width, height) * 0.75
    result = bytearray(len(pixels))
    for y in range(height):
        for x in range(width):
            distance = math.hypot(x, y)
            factor = 1.0 - 0.45 * max(0.0, 1.0 - distance / radius)
            result[y * width + x] = min(255, max(0, int(pixels[y * width + x] * factor)))
    return result


def skew(width: int, height: int, pixels: bytearray, degrees: float = 3.0) -> bytearray:
    """Rotates the content about the page centre with bilinear sampling.

    Every destination pixel samples its source pixel as
    ``source = c + R(-degrees)(dest - c)`` with ``R(a) = [[cos a, -sin a],
    [sin a, cos a]]`` and ``c`` the page centre. Equivalently the content itself
    sits at ``dest = c + R(+degrees)(source - c)``, i.e. a positive ``degrees``
    turns the content counter-clockwise in the screen frame. The T263 scorer
    annotation transform and `test_de_ocr_qualification.rotate_about_page_centre`
    use this same pair; a wrong sign there is caught by the transform
    sensitivity test.
    """
    radians = math.radians(degrees)
    cos_a = math.cos(radians)
    sin_a = math.sin(radians)
    centre_x = width / 2.0
    centre_y = height / 2.0
    result = bytearray(b"\xff" * len(pixels))
    for y in range(height):
        dy = y - centre_y
        for x in range(width):
            dx = x - centre_x
            source_x = centre_x + dx * cos_a + dy * sin_a
            source_y = centre_y - dx * sin_a + dy * cos_a
            if source_x < 0 or source_y < 0 or source_x >= width - 1 or source_y >= height - 1:
                continue
            x0 = int(source_x)
            y0 = int(source_y)
            fx = source_x - x0
            fy = source_y - y0
            top_left = pixels[y0 * width + x0]
            top_right = pixels[y0 * width + x0 + 1]
            bottom_left = pixels[(y0 + 1) * width + x0]
            bottom_right = pixels[(y0 + 1) * width + x0 + 1]
            value = (
                top_left * (1 - fx) * (1 - fy)
                + top_right * fx * (1 - fy)
                + bottom_left * (1 - fx) * fy
                + bottom_right * fx * fy
            )
            result[y * width + x] = int(value)
    return result


def jpeg_round_trip(
    directory: pathlib.Path, width: int, height: int, pixels: bytearray
) -> bytearray:
    magick = shutil.which("magick") or shutil.which("convert")
    if magick is None:
        raise SystemExit("error: ImageMagick is required for the JPEG variant")
    source = directory / "jpeg-source.pgm"
    encoded = directory / "jpeg-q35.jpg"
    decoded = directory / "jpeg-decoded.pgm"
    write_pgm(source, width, height, pixels)
    run([magick, str(source), "-quality", "35", str(encoded)])
    run([magick, str(encoded), "-colorspace", "Gray", "-depth", "8", str(decoded)])
    out_width, out_height, out_pixels = read_pgm(decoded)
    if (out_width, out_height) != (width, height):
        raise SystemExit("error: JPEG round trip changed the raster size")
    for path in (source, encoded, decoded):
        path.unlink(missing_ok=True)
    return out_pixels


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pdf", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--only", nargs="*", default=None)
    arguments = parser.parse_args()
    pdf = pathlib.Path(arguments.pdf)
    if not pdf.is_file():
        print(f"error: missing {pdf}", file=sys.stderr)
        return 2
    output = pathlib.Path(arguments.output)
    output.mkdir(parents=True, exist_ok=True)
    rendered: dict[int, list[pathlib.Path]] = {}
    variants: list[dict] = []
    selected = set(arguments.only) if arguments.only else None

    for variant_id, dpi in CLEAN_VARIANTS:
        if selected is not None and variant_id not in selected:
            continue
        variants.append(
            {
                "id": variant_id,
                "kind": "production-raster",
                "dpi": dpi,
                "degradations": [],
                "pageWidthPt": PAGE_WIDTH_PT,
                "pageHeightPt": PAGE_HEIGHT_PT,
            }
        )

    for variant_id, dpi, degradation in DEGRADED_VARIANTS:
        if selected is not None and variant_id not in selected:
            continue
        if dpi not in rendered:
            rendered[dpi] = render_pages(pdf, dpi, output)
        pages = []
        target_width, target_height = analysis_size(ANALYSIS_DPI)
        for page_index, pgm in enumerate(rendered[dpi]):
            width, height, _ = read_pgm(pgm)
            if (width, height) != (target_width, target_height):
                resample_pgm(pgm, target_width, target_height)
            width, height, pixels = read_pgm(pgm)
            if degradation == "low-contrast":
                degraded = low_contrast(pixels)
            elif degradation == "shadow":
                degraded = shadow(width, height, pixels)
            elif degradation == "skew-3deg":
                degraded = skew(width, height, pixels)
            elif degradation == "jpeg-q35":
                degraded = jpeg_round_trip(output, width, height, pixels)
            else:  # pragma: no cover - declared table above
                raise SystemExit(f"error: unknown degradation {degradation}")
            name = f"{variant_id}.p{page_index}.gray8"
            write_gray8(output / name, width, height, degraded)
            pages.append(
                {
                    "index": page_index,
                    "file": name,
                    "widthPx": width,
                    "heightPx": height,
                    "rasterDpi": ANALYSIS_DPI,
                }
            )
        variants.append(
            {
                "id": variant_id,
                "kind": "injected-raster",
                "dpi": dpi,
                "degradations": [degradation],
                "pageWidthPt": PAGE_WIDTH_PT,
                "pageHeightPt": PAGE_HEIGHT_PT,
                "pages": pages,
            }
        )

    for pgm in output.glob("render-*.pgm"):
        pgm.unlink()
    for png in output.glob("render-*.png"):
        png.unlink()

    manifest = {
        "schemaVersion": 1,
        "description":
            "T263 raster variants. Clean variants are rendered on the device by "
            "the production raster port; degraded variants inject a host-made "
            "scan simulation into the production ML Kit OCR port.",
        "variants": variants,
    }
    (output / "t263-variants.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(f"wrote {output / 't263-variants.json'} ({len(variants)} variants)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
