#!/usr/bin/env python3
"""Static verification of the T006 Noto Sans font bundle.

This is a host-side integrity and configuration check. It proves that the
committed bytes equal the pinned upstream release, that both files are
structurally valid static TrueType fonts with the German glyphs required by
FR-067, that ``OFL.txt`` is the SIL OFL 1.1 text, and that Flutter publishes
both font assets with the contract's family name and paths.

It is deliberately *not* runtime rendering evidence. It produces no
``SIMULATED``, ``EMULATOR``, or ``DEVICE`` evidence class and cannot prove that
Flutter, Android, PDFBox, or a PDF reader renders the glyphs correctly.

Usage:
    python3 tools/fonts/verify_fonts.py

Exit status: 0 when every check passes, 1 otherwise.
"""

from __future__ import annotations

import hashlib
import pathlib
import re
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
FONT_DIR = ROOT / "apps" / "feldexa_app" / "assets" / "fonts"
PUBSPEC = ROOT / "apps" / "feldexa_app" / "pubspec.yaml"

# Pinned by T006 evidence. The archive SHA-256 is in PROVENANCE.md and is
# verified by fetch_noto_sans.sh; per-file hashes are what the build consumes.
EXPECTED_FILES = {
    "NotoSans-Regular.ttf": {
        "sha256": "97eaf07030b89da4eceace86b12f4d7debb3cb212082c3938803eac7111221c9",
        "weight": 400,
        "subfamily": "Regular",
        "postscript": "NotoSans-Regular",
    },
    "NotoSans-Bold.ttf": {
        "sha256": "53b53721b1910c7e058c4f012126b41273d493b04d69c1ac50924f7eff8e8039",
        "weight": 700,
        "subfamily": "Bold",
        "postscript": "NotoSans-Bold",
    },
    "OFL.txt": {
        "sha256": "cee9892f9f0cc8fe882c9e9537ee6a89621d86ee7ceaf70b02e2b2b1c25c061a",
    },
}

# FR-067: multiline values, line breaks, and German special characters.
REQUIRED_CODEPOINTS = {
    "space": 0x0020,
    "A": 0x0041,
    "z": 0x007A,
    "0": 0x0030,
    "9": 0x0039,
    "A-umlaut": 0x00C4,
    "O-umlaut": 0x00D6,
    "U-umlaut": 0x00DC,
    "a-umlaut": 0x00E4,
    "o-umlaut": 0x00F6,
    "u-umlaut": 0x00FC,
    "sharp-s": 0x00DF,
    "euro": 0x20AC,
    "quotedblleft": 0x201C,
    "quotedblright": 0x201D,
    "quotedblbase": 0x201E,
    "endash": 0x2013,
    "emdash": 0x2014,
    "ellipsis": 0x2026,
    "no-break-space": 0x00A0,
}

REQUIRED_TABLES = {
    "head",
    "hhea",
    "hmtx",
    "maxp",
    "cmap",
    "name",
    "OS/2",
    "post",
    "loca",
    "glyf",
}

SFNT_TRUETYPE = 0x00010000
CHECKSUM_MAGIC = 0xB1B0AFBA
HEAD_MAGIC = 0x5F0F3CF5


class VerificationError(Exception):
    pass


def fail(message: str) -> None:
    raise VerificationError(message)


def u16(data: bytes, offset: int) -> int:
    if offset + 2 > len(data):
        fail(f"truncated u16 read at offset {offset}")
    return struct.unpack_from(">H", data, offset)[0]


def s16(data: bytes, offset: int) -> int:
    if offset + 2 > len(data):
        fail(f"truncated s16 read at offset {offset}")
    return struct.unpack_from(">h", data, offset)[0]


def u32(data: bytes, offset: int) -> int:
    if offset + 4 > len(data):
        fail(f"truncated u32 read at offset {offset}")
    return struct.unpack_from(">I", data, offset)[0]


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def table_checksum(data: bytes, offset: int, length: int, zero: tuple[int, int] | None = None) -> int:
    chunk = bytearray(data[offset : offset + length])
    if zero is not None:
        start, end = zero
        chunk[start:end] = b"\x00" * (end - start)
    chunk.extend(b"\x00" * ((-len(chunk)) % 4))
    return sum(struct.unpack(f">{len(chunk) // 4}I", chunk)) & 0xFFFFFFFF


def parse_tables(font: bytes, path: pathlib.Path) -> dict[str, tuple[int, int, int]]:
    if len(font) < 12:
        fail(f"{path.name}: file is too short to be an sfnt font")
    version = u32(font, 0)
    if version != SFNT_TRUETYPE:
        fail(
            f"{path.name}: sfnt version is 0x{version:08x}, expected a static "
            f"TrueType font (0x{SFNT_TRUETYPE:08x})"
        )
    num_tables = u16(font, 4)
    if not 1 <= num_tables <= 512:
        fail(f"{path.name}: implausible table count {num_tables}")

    tables: dict[str, tuple[int, int, int]] = {}
    for index in range(num_tables):
        record = 12 + index * 16
        if record + 16 > len(font):
            fail(f"{path.name}: truncated table directory at record {index}")
        tag = font[record : record + 4].decode("latin-1")
        checksum = u32(font, record + 4)
        offset = u32(font, record + 8)
        length = u32(font, record + 12)
        if tag in tables:
            fail(f"{path.name}: duplicate table {tag!r}")
        if offset % 4:
            fail(f"{path.name}: table {tag!r} is not 4-byte aligned")
        if offset + length > len(font):
            fail(f"{path.name}: table {tag!r} extends past the file end")
        tables[tag] = (offset, length, checksum)

    missing = REQUIRED_TABLES - tables.keys()
    if missing:
        fail(f"{path.name}: missing required TrueType tables: {sorted(missing)}")
    if "fvar" in tables:
        fail(f"{path.name}: variable font (fvar) found; the plan pins static TTFs")
    if "CFF " in tables:
        fail(f"{path.name}: CFF outlines found; the plan pins TrueType outlines")

    for tag, (offset, length, expected) in tables.items():
        zero = (8, 12) if tag == "head" else None
        actual = table_checksum(font, offset, length, zero)
        if actual != expected:
            fail(
                f"{path.name}: table {tag!r} checksum 0x{actual:08x} "
                f"does not match directory 0x{expected:08x}"
            )

    padded = font + b"\x00" * ((-len(font)) % 4)
    total = sum(struct.unpack(f">{len(padded) // 4}I", padded)) & 0xFFFFFFFF
    if total != CHECKSUM_MAGIC:
        fail(
            f"{path.name}: whole-font checksum is 0x{total:08x}, "
            f"expected 0x{CHECKSUM_MAGIC:08x}"
        )
    return tables


def decode_name_record(font: bytes, platform: int, encoding: int, raw: bytes) -> str | None:
    try:
        if platform in (0, 3):
            return raw.decode("utf-16-be")
        if platform == 1:
            return raw.decode("mac_roman")
    except UnicodeDecodeError:
        return None
    return raw.decode("latin-1", errors="replace")


def parse_names(font: bytes, tables: dict[str, tuple[int, int, int]]) -> dict[int, str]:
    offset, length, _ = tables["name"]
    name = font[offset : offset + length]
    count = u16(name, 2)
    string_offset = u16(name, 4)
    names: dict[int, str] = {}
    for index in range(count):
        record = 6 + index * 12
        if record + 12 > len(name):
            fail("name table directory is truncated")
        platform = u16(name, record)
        encoding = u16(name, record + 2)
        language = u16(name, record + 4)
        name_id = u16(name, record + 6)
        raw_length = u16(name, record + 8)
        raw_offset = u16(name, record + 10)
        start = string_offset + raw_offset
        raw = name[start : start + raw_length]
        if len(raw) != raw_length:
            fail(f"name record {name_id} extends past the name table")
        # Prefer Windows English (0x0409) / Unicode, then any decodable record.
        preferred = (platform == 3 and language in (0x0409, 0x0000)) or platform == 0
        decoded = decode_name_record(font, platform, encoding, raw)
        if decoded is None:
            continue
        if name_id not in names or preferred:
            names[name_id] = decoded
    return names


def parse_cmap_lookups(font: bytes, tables: dict[str, tuple[int, int, int]]) -> list[tuple[int, callable]]:
    offset, length, _ = tables["cmap"]
    cmap = font[offset : offset + length]
    count = u16(cmap, 2)
    lookups: list[tuple[int, callable]] = []
    seen_offsets: set[int] = set()

    for index in range(count):
        record = 4 + index * 8
        platform = u16(cmap, record)
        encoding = u16(cmap, record + 2)
        sub_offset = u32(cmap, record + 4)
        if sub_offset in seen_offsets:
            continue
        seen_offsets.add(sub_offset)
        if sub_offset + 2 > len(cmap):
            fail("cmap subtable offset is outside the cmap table")
        fmt = u16(cmap, sub_offset)
        is_unicode = platform == 0 or (platform == 3 and encoding in (1, 10))
        if not is_unicode:
            continue

        if fmt == 4:
            def lookup_fmt4(cp: int, sub: int = sub_offset) -> int:
                seg_count = u16(cmap, sub + 6) // 2
                end_base = sub + 14
                start_base = sub + 16 + 2 * seg_count
                delta_base = sub + 16 + 4 * seg_count
                range_base = sub + 16 + 6 * seg_count
                for segment in range(seg_count):
                    end = u16(cmap, end_base + 2 * segment)
                    if cp > end:
                        continue
                    start = u16(cmap, start_base + 2 * segment)
                    if cp < start:
                        return 0
                    delta = s16(cmap, delta_base + 2 * segment)
                    range_offset_pos = range_base + 2 * segment
                    range_offset = u16(cmap, range_offset_pos)
                    if range_offset == 0:
                        return (cp + delta) & 0xFFFF
                    glyph_pos = range_offset_pos + range_offset + 2 * (cp - start)
                    if glyph_pos + 2 > len(cmap):
                        return 0
                    glyph = u16(cmap, glyph_pos)
                    return (glyph + delta) & 0xFFFF if glyph else 0
                return 0

            lookups.append((4, lookup_fmt4))

        elif fmt == 12:
            def lookup_fmt12(cp: int, sub: int = sub_offset) -> int:
                groups = u32(cmap, sub + 12)
                for group in range(groups):
                    base = sub + 16 + group * 12
                    start = u32(cmap, base)
                    end = u32(cmap, base + 4)
                    if start <= cp <= end:
                        return u32(cmap, base + 8) + (cp - start)
                return 0

            lookups.append((12, lookup_fmt12))

    if not lookups:
        fail("no Unicode cmap subtable (format 4 or 12) found")
    return lookups


def verify_font(path: pathlib.Path, spec: dict) -> dict:
    font = path.read_bytes()
    digest = hashlib.sha256(font).hexdigest()
    if digest != spec["sha256"]:
        fail(f"{path.name}: SHA-256 {digest} != pinned {spec['sha256']}")
    if hashlib.sha256(font).hexdigest() != sha256(path):
        fail(f"{path.name}: streaming SHA-256 disagrees with in-memory SHA-256")

    tables = parse_tables(font, path)

    head_offset, head_length, _ = tables["head"]
    if head_length < 54:
        fail(f"{path.name}: head table is too short")
    if u32(font, head_offset + 12) != HEAD_MAGIC:
        fail(f"{path.name}: head magic number is wrong")
    units_per_em = u16(font, head_offset + 18)
    if units_per_em not in (1000, 2048):
        fail(f"{path.name}: unexpected unitsPerEm {units_per_em}")
    index_to_loc_format = s16(font, head_offset + 50)
    if index_to_loc_format not in (0, 1):
        fail(f"{path.name}: invalid indexToLocFormat {index_to_loc_format}")

    maxp_offset, _, _ = tables["maxp"]
    num_glyphs = u16(font, maxp_offset + 4)
    if num_glyphs == 0:
        fail(f"{path.name}: maxp reports zero glyphs")

    hhea_offset, _, _ = tables["hhea"]
    ascender = s16(font, hhea_offset + 4)
    descender = s16(font, hhea_offset + 6)
    line_gap = s16(font, hhea_offset + 8)
    num_h_metrics = u16(font, hhea_offset + 34)
    if not 0 < num_h_metrics <= num_glyphs:
        fail(f"{path.name}: invalid numberOfHMetrics {num_h_metrics}")

    os2_offset, os2_length, _ = tables["OS/2"]
    us_weight_class = u16(font, os2_offset + 4)
    us_width_class = u16(font, os2_offset + 6)
    fs_type = u16(font, os2_offset + 8)
    if us_weight_class != spec["weight"]:
        fail(f"{path.name}: usWeightClass {us_weight_class} != expected {spec['weight']}")
    if us_width_class != 5:
        fail(f"{path.name}: usWidthClass {us_width_class} is not normal (5)")
    if fs_type & 0x0002:
        fail(f"{path.name}: OS/2 fsType 0x{fs_type:04x} forbids embedding")
    if fs_type & 0x0200:
        fail(f"{path.name}: OS/2 fsType 0x{fs_type:04x} is bitmap-only embedding")

    names = parse_names(font, tables)
    family = names.get(1)
    subfamily = names.get(2)
    postscript = names.get(6)
    version = names.get(5, "")
    if family != "Noto Sans":
        fail(f"{path.name}: family name {family!r} != 'Noto Sans'")
    if subfamily != spec["subfamily"]:
        fail(f"{path.name}: subfamily {subfamily!r} != {spec['subfamily']!r}")
    if postscript != spec["postscript"]:
        fail(f"{path.name}: PostScript name {postscript!r} != {spec['postscript']!r}")
    if "2.013" not in version:
        fail(f"{path.name}: version string {version!r} does not name 2.013")

    loca_offset, loca_length, _ = tables["loca"]
    glyf_offset, glyf_length, _ = tables["glyf"]
    loca = font[loca_offset : loca_offset + loca_length]
    loca_width = 2 if index_to_loc_format == 0 else 4
    expected_loca = (num_glyphs + 1) * loca_width
    if loca_length < expected_loca:
        fail(f"{path.name}: loca length {loca_length} < required {expected_loca}")
    offsets = [
        (u16(loca, i * 2) * 2) if index_to_loc_format == 0 else u32(loca, i * 4)
        for i in range(num_glyphs + 1)
    ]
    if any(b < a for a, b in zip(offsets, offsets[1:])):
        fail(f"{path.name}: loca offsets are not non-decreasing")
    if offsets[-1] > glyf_length:
        fail(f"{path.name}: last loca offset {offsets[-1]} exceeds glyf length {glyf_length}")

    hmtx_offset, hmtx_length, _ = tables["hmtx"]
    minimum_hmtx = num_h_metrics * 4 + (num_glyphs - num_h_metrics) * 2
    if hmtx_length < minimum_hmtx:
        fail(f"{path.name}: hmtx length {hmtx_length} < required {minimum_hmtx}")

    lookups = parse_cmap_lookups(font, tables)
    missing: list[str] = []
    advances: dict[str, int] = {}
    for label, codepoint in REQUIRED_CODEPOINTS.items():
        glyph = 0
        for _fmt, lookup in lookups:
            glyph = lookup(codepoint)
            if glyph:
                break
        if not glyph:
            missing.append(f"{label} (U+{codepoint:04X})")
            continue
        advance = (
            u16(font, hmtx_offset + 4 * glyph)
            if glyph < num_h_metrics
            else u16(font, hmtx_offset + 4 * (num_h_metrics - 1))
        )
        if advance == 0:
            missing.append(f"{label} (U+{codepoint:04X}, zero advance)")
        advances[label] = advance
    if missing:
        fail(f"{path.name}: missing German glyph coverage: {', '.join(missing)}")

    return {
        "sha256": digest,
        "bytes": len(font),
        "tables": len(tables),
        "glyphs": num_glyphs,
        "units_per_em": units_per_em,
        "ascender": ascender,
        "descender": descender,
        "line_gap": line_gap,
        "weight_class": us_weight_class,
        "fs_type": fs_type,
        "cmap_formats": sorted({fmt for fmt, _ in lookups}),
        "name_version": version,
        "family": family,
        "subfamily": subfamily,
        "postscript": postscript,
        "required_glyphs": len(REQUIRED_CODEPOINTS),
    }


def verify_ofl(path: pathlib.Path) -> str:
    ofl = path.read_bytes()
    digest = hashlib.sha256(ofl).hexdigest()
    if digest != EXPECTED_FILES["OFL.txt"]["sha256"]:
        fail(f"{path.name}: SHA-256 {digest} != pinned {EXPECTED_FILES['OFL.txt']['sha256']}")
    try:
        text = ofl.decode("utf-8")
    except UnicodeDecodeError as error:
        fail(f"{path.name}: not valid UTF-8: {error}")
    required = [
        "Copyright 2022 The Noto Project Authors",
        "SIL Open Font License, Version 1.1",
        "PERMISSION & CONDITIONS",
        "TERMINATION",
        "DISCLAIMER",
        "https://scripts.sil.org/OFL",
    ]
    for marker in required:
        if marker not in text:
            fail(f"{path.name}: missing OFL marker {marker!r}")
    return digest


def indented_block(text: str, header: str) -> str:
    match = re.search(rf"(?m)^([ \t]*){re.escape(header)}:[ \t]*$", text)
    if not match:
        fail(f"pubspec.yaml: missing top-level {header!r} block")
    base_indent = len(match.group(1))
    lines: list[str] = []
    for line in text[match.end() :].splitlines():
        if not line.strip():
            lines.append(line)
            continue
        indent = len(line) - len(line.lstrip(" \t"))
        if indent <= base_indent:
            break
        lines.append(line)
    return "\n".join(lines)


def verify_pubspec(path: pathlib.Path) -> dict:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        fail(f"pubspec.yaml: not valid UTF-8: {error}")

    fonts = indented_block(text, "fonts")
    family_match = re.search(r"(?m)^\s*-\s*family:\s*(\S+)\s*$", fonts)
    if not family_match or family_match.group(1) != "NotoSans":
        fail("pubspec.yaml: flutter.fonts must declare family NotoSans")

    entries = re.findall(
        r"(?m)^\s*-\s*asset:\s*(\S+)\s*\n\s*weight:\s*(\d+)\s*$", fonts
    )
    expected_entries = [
        ("assets/fonts/NotoSans-Regular.ttf", "400"),
        ("assets/fonts/NotoSans-Bold.ttf", "700"),
    ]
    if entries != expected_entries:
        fail(
            "pubspec.yaml: font entries are "
            f"{entries!r}, expected {expected_entries!r}"
        )

    assets = indented_block(text, "assets")
    declared = re.findall(r"(?m)^\s*-\s*(\S+)\s*$", assets)
    if "assets/fonts/OFL.txt" not in declared:
        fail("pubspec.yaml: assets must include assets/fonts/OFL.txt")
    duplicated = [entry for entry in declared if entry.endswith(".ttf")]
    if duplicated:
        fail(f"pubspec.yaml: TrueType files must not be listed under assets too: {duplicated}")

    return {"family": "NotoSans", "entries": entries, "assets": declared}


def verify_expected_file_names() -> None:
    present = {path.name for path in FONT_DIR.iterdir() if path.is_file()}
    for name in EXPECTED_FILES:
        if name not in present:
            fail(f"missing bundled file: {FONT_DIR / name}")


def main() -> int:
    print("T006 Noto Sans bundle verification (static host check; no runtime evidence)")
    print(f"  asset root: {FONT_DIR.relative_to(ROOT)}")
    try:
        verify_expected_file_names()

        results = {}
        for name in ("NotoSans-Regular.ttf", "NotoSans-Bold.ttf"):
            path = FONT_DIR / name
            results[name] = verify_font(path, EXPECTED_FILES[name])
            info = results[name]
            print(
                f"  OK {name}: {info['bytes']} bytes, {info['glyphs']} glyphs, "
                f"{info['tables']} tables, weight {info['weight_class']}, "
                f"unitsPerEm {info['units_per_em']}, cmap {info['cmap_formats']}, "
                f"ascender {info['ascender']}, descender {info['descender']}, "
                f"fsType 0x{info['fs_type']:04x}, version {info['name_version']!r}"
            )
            print(
                f"     glyph coverage: {info['required_glyphs']} required FR-067 "
                f"codepoints present, SHA-256 {info['sha256']}"
            )

        ofl_digest = verify_ofl(FONT_DIR / "OFL.txt")
        print(f"  OK OFL.txt: SIL OFL 1.1 text verified, SHA-256 {ofl_digest}")

        pubspec = verify_pubspec(PUBSPEC)
        print(
            "  OK pubspec.yaml: flutter.fonts family "
            f"{pubspec['family']} -> {pubspec['entries']}; "
            "OFL.txt declared as an asset"
        )
    except VerificationError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1

    print("PASS: T006 font bytes, licence, glyph coverage, and Flutter asset configuration are valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
