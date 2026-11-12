// T007 font-advance metrics library.
//
// Parses the bundled static TrueType fonts and renders the deterministic
// `metrics.json` table consumed by `feldexa_export` for text layout and clip
// detection (FR-064, FR-067, FR-068; plan.md §Architecture Decisions 6;
// research.md D-11).
//
// The parser is intentionally dependency-free: it reads only the sfnt tables
// that the metrics need (`head`, `hhea`, `maxp`, `hmtx`, `cmap`, `OS/2`) and
// rejects variable/CFF fonts. The emitted schema is documented in
// `tools/metrics/README.md`; presence of a codepoint key in `advances` means
// the glyph exists in the font's Unicode cmap. A missing key is a font
// coverage failure (`EXP-004`), not a zero width.
//
// This is a host-side build tool. It produces no runtime, render, Android,
// PDFBox, or device evidence.

import 'dart:convert';
import 'dart:typed_data';

/// Version of the emitted JSON document shape.
const int metricsSchemaVersion = 1;

/// Stable version string used by the export plan contract's `font` block.
const String metricsVersion = 'noto-sans-2.013-v1';

/// Contract font family (contracts/export-plan.md §2).
const String fontFamily = 'NotoSans';

/// Pinned upstream release that the bundled bytes belong to (T006).
const String fontRelease = 'NotoSans-v2.013';

/// SHA-256 values pinned by T006; the generator refuses other bytes.
const Map<String, String> pinnedFontSha256 = <String, String>{
  'NotoSans-Regular.ttf':
      '97eaf07030b89da4eceace86b12f4d7debb3cb212082c3938803eac7111221c9',
  'NotoSans-Bold.ttf':
      '53b53721b1910c7e058c4f012126b41273d493b04d69c1ac50924f7eff8e8039',
};

/// FR-067 coverage required for German form values in both weights.
const Map<String, int> requiredCodepoints = <String, int>{
  'space': 0x0020,
  'A': 0x0041,
  'z': 0x007A,
  '0': 0x0030,
  '9': 0x0039,
  'A-umlaut': 0x00C4,
  'O-umlaut': 0x00D6,
  'U-umlaut': 0x00DC,
  'a-umlaut': 0x00E4,
  'o-umlaut': 0x00F6,
  'u-umlaut': 0x00FC,
  'sharp-s': 0x00DF,
  'euro': 0x20AC,
  'quotedblleft': 0x201C,
  'quotedblright': 0x201D,
  'quotedblbase': 0x201E,
  'endash': 0x2013,
  'emdash': 0x2014,
  'ellipsis': 0x2026,
  'no-break-space': 0x00A0,
};

/// Error raised for malformed, unsupported, or incomplete font input.
class FontMetricsException implements Exception {
  /// Creates an error with a human-readable [message].
  FontMetricsException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'FontMetricsException: $message';
}

/// Metrics extracted from one static TrueType font.
class ParsedFont {
  /// Creates a font metric record. Call [parseFont] instead of this directly.
  ParsedFont({
    required this.style,
    required this.weight,
    required this.asset,
    required this.byteLength,
    required this.sha256,
    required this.unitsPerEm,
    required this.glyphCount,
    required this.numberOfHMetrics,
    required this.advanceWidthMax,
    required this.ascender,
    required this.descender,
    required this.lineGap,
    required this.typoAscender,
    required this.typoDescender,
    required this.typoLineGap,
    required this.winAscent,
    required this.winDescent,
    required this.xHeight,
    required this.capHeight,
    required this.cmapFormat,
    required Map<int, int> advances,
  }) : advances = Map<int, int>.unmodifiable(_sorted(advances));

  /// `regular` or `bold`.
  final String style;

  /// OS/2 weight class, 400 or 700.
  final int weight;

  /// Flutter asset path from the export-plan contract.
  final String asset;

  /// Source byte length.
  final int byteLength;

  /// Source SHA-256, lowercase hex.
  final String sha256;

  /// Font design units per em (1000 for Noto Sans).
  final int unitsPerEm;

  /// Number of glyphs from `maxp`.
  final int glyphCount;

  /// Number of full advance records in `hmtx`.
  final int numberOfHMetrics;

  /// Maximum advance width from `hhea`.
  final int advanceWidthMax;

  /// Horizontal ascender in design units.
  final int ascender;

  /// Horizontal descender in design units (negative).
  final int descender;

  /// Horizontal line gap in design units.
  final int lineGap;

  /// OS/2 typographic ascender, if available.
  final int? typoAscender;

  /// OS/2 typographic descender, if available.
  final int? typoDescender;

  /// OS/2 typographic line gap, if available.
  final int? typoLineGap;

  /// OS/2 Windows ascent, if available.
  final int? winAscent;

  /// OS/2 Windows descent (positive), if available.
  final int? winDescent;

  /// OS/2 x-height, if the table version exposes it.
  final int? xHeight;

  /// OS/2 cap height, if the table version exposes it.
  final int? capHeight;

  /// cmap subtable format that supplied the Unicode mapping.
  final int cmapFormat;

  /// Unicode codepoint to advance width in font design units.
  final Map<int, int> advances;

  /// JSON object for this font, in a stable field order.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'family': fontFamily,
      'style': style,
      'weight': weight,
      'asset': asset,
      'sha256': sha256,
      'bytes': byteLength,
      'unitsPerEm': unitsPerEm,
      'glyphCount': glyphCount,
      'numberOfHMetrics': numberOfHMetrics,
      'advanceWidthMax': advanceWidthMax,
      'ascender': ascender,
      'descender': descender,
      'lineGap': lineGap,
      'typoAscender': typoAscender,
      'typoDescender': typoDescender,
      'typoLineGap': typoLineGap,
      'winAscent': winAscent,
      'winDescent': winDescent,
      'xHeight': xHeight,
      'capHeight': capHeight,
      'cmapFormat': cmapFormat,
      'codepointCount': advances.length,
      'firstCodepoint': advances.isEmpty ? null : advances.keys.first,
      'lastCodepoint': advances.isEmpty ? null : advances.keys.last,
      'advances': <String, int>{
        for (final MapEntry<int, int> entry in advances.entries)
          '${entry.key}': entry.value,
      },
    };
  }
}

/// Renders the complete `metrics.json` document for [fonts].
///
/// Fonts are sorted by weight, and every codepoint map is emitted in ascending
/// numeric order, so regeneration is byte-for-byte deterministic.
String renderMetricsJson(Iterable<ParsedFont> fonts) {
  final List<ParsedFont> ordered = fonts.toList()
    ..sort((ParsedFont a, ParsedFont b) => a.weight.compareTo(b.weight));
  if (ordered.isEmpty) {
    throw FontMetricsException('cannot render an empty font list');
  }
  final int unitsPerEm = ordered.first.unitsPerEm;
  for (final ParsedFont font in ordered) {
    if (font.unitsPerEm != unitsPerEm) {
      throw FontMetricsException(
        'mixed unitsPerEm values (${ordered.first.style}=$unitsPerEm, '
        '${font.style}=${font.unitsPerEm}); the schema has one '
        'top-level unitsPerEm',
      );
    }
  }
  final Map<String, Object?> document = <String, Object?>{
    'schemaVersion': metricsSchemaVersion,
    'metricsVersion': metricsVersion,
    'family': fontFamily,
    'fontRelease': fontRelease,
    'unitsPerEm': unitsPerEm,
    'fonts': <String, Object?>{
      for (final ParsedFont font in ordered) '${font.weight}': font.toJson(),
    },
  };
  return '${const JsonEncoder.withIndent('  ').convert(document)}\n';
}

/// Parses [bytes] as a static TrueType font and extracts layout metrics.
///
/// [asset] is recorded verbatim in the output; [style] and [weight] describe
/// the bundle slot. The bytes are hashed and checked against [pinnedSha256]
/// when provided.
ParsedFont parseFont({
  required Uint8List bytes,
  required String asset,
  required String style,
  required int weight,
  String? pinnedSha256,
}) {
  final String digest = sha256Hex(bytes);
  if (pinnedSha256 != null && digest != pinnedSha256) {
    throw FontMetricsException(
      '$asset: SHA-256 $digest does not match the T006 pin $pinnedSha256; '
      'restore the bundled bytes with tools/fonts/fetch_noto_sans.sh',
    );
  }
  final Map<String, _Table> tables = _readTableDirectory(bytes, asset);
  _rejectUnsupported(tables, asset);

  final _Table head = _require(tables, 'head', asset);
  if (head.length < 54) {
    throw FontMetricsException('$asset: head table is shorter than 54 bytes');
  }
  final int unitsPerEm = _u16(
    bytes,
    head.offset + 18,
    '$asset head unitsPerEm',
  );
  if (unitsPerEm < 16 || unitsPerEm > 16384) {
    throw FontMetricsException('$asset: implausible unitsPerEm $unitsPerEm');
  }

  final _Table hhea = _require(tables, 'hhea', asset);
  if (hhea.length < 36) {
    throw FontMetricsException('$asset: hhea table is shorter than 36 bytes');
  }
  final int ascender = _s16(bytes, hhea.offset + 4, '$asset hhea ascender');
  final int descender = _s16(bytes, hhea.offset + 6, '$asset hhea descender');
  final int lineGap = _s16(bytes, hhea.offset + 8, '$asset hhea lineGap');
  final int advanceWidthMax = _u16(
    bytes,
    hhea.offset + 10,
    '$asset hhea advanceWidthMax',
  );
  final int numberOfHMetrics = _u16(
    bytes,
    hhea.offset + 34,
    '$asset hhea numberOfHMetrics',
  );

  final _Table maxp = _require(tables, 'maxp', asset);
  if (maxp.length < 6) {
    throw FontMetricsException('$asset: maxp table is shorter than 6 bytes');
  }
  final int glyphCount = _u16(bytes, maxp.offset + 4, '$asset maxp numGlyphs');
  if (glyphCount == 0) {
    throw FontMetricsException('$asset: maxp reports zero glyphs');
  }
  if (numberOfHMetrics < 1 || numberOfHMetrics > glyphCount) {
    throw FontMetricsException(
      '$asset: hhea numberOfHMetrics $numberOfHMetrics is outside 1..$glyphCount',
    );
  }

  final _Table hmtx = _require(tables, 'hmtx', asset);
  final int hmtxMinimum =
      numberOfHMetrics * 4 + (glyphCount - numberOfHMetrics) * 2;
  if (hmtx.length < hmtxMinimum) {
    throw FontMetricsException(
      '$asset: hmtx length ${hmtx.length} is below the required $hmtxMinimum',
    );
  }
  final List<int> glyphAdvances = List<int>.filled(glyphCount, 0);
  for (int glyph = 0; glyph < numberOfHMetrics; glyph++) {
    glyphAdvances[glyph] = _u16(
      bytes,
      hmtx.offset + glyph * 4,
      '$asset hmtx advance $glyph',
    );
  }
  final int lastAdvance = glyphAdvances[numberOfHMetrics - 1];
  for (int glyph = numberOfHMetrics; glyph < glyphCount; glyph++) {
    glyphAdvances[glyph] = lastAdvance;
  }

  final _CmapMapping cmap = _readUnicodeCmap(bytes, tables, asset, glyphCount);
  final Map<int, int> advances = <int, int>{};
  for (final MapEntry<int, int> entry in cmap.glyphs.entries) {
    if (entry.value < 0 || entry.value >= glyphCount) {
      throw FontMetricsException(
        '$asset: cmap maps U+${_hex(entry.key)} to out-of-range glyph '
        '${entry.value}',
      );
    }
    advances[entry.key] = glyphAdvances[entry.value];
  }
  if (advances.isEmpty) {
    throw FontMetricsException('$asset: Unicode cmap produced no codepoints');
  }
  for (final MapEntry<String, int> required in requiredCodepoints.entries) {
    final int? advance = advances[required.value];
    if (advance == null) {
      throw FontMetricsException(
        '$asset: required FR-067 glyph ${required.key} '
        '(U+${_hex(required.value)}) is missing from the Unicode cmap',
      );
    }
    if (advance == 0) {
      throw FontMetricsException(
        '$asset: required FR-067 glyph ${required.key} '
        '(U+${_hex(required.value)}) has a zero advance',
      );
    }
  }

  final _Os2Metrics os2 = _readOs2(bytes, tables, asset, weight);

  return ParsedFont(
    style: style,
    weight: weight,
    asset: asset,
    byteLength: bytes.length,
    sha256: digest,
    unitsPerEm: unitsPerEm,
    glyphCount: glyphCount,
    numberOfHMetrics: numberOfHMetrics,
    advanceWidthMax: advanceWidthMax,
    ascender: ascender,
    descender: descender,
    lineGap: lineGap,
    typoAscender: os2.typoAscender,
    typoDescender: os2.typoDescender,
    typoLineGap: os2.typoLineGap,
    winAscent: os2.winAscent,
    winDescent: os2.winDescent,
    xHeight: os2.xHeight,
    capHeight: os2.capHeight,
    cmapFormat: cmap.format,
    advances: advances,
  );
}

Map<int, int> _sorted(Map<int, int> source) {
  final List<int> keys = source.keys.toList()..sort();
  return <int, int>{for (final int key in keys) key: source[key]!};
}

String _hex(int value) => value.toRadixString(16).toUpperCase().padLeft(4, '0');

class _Table {
  const _Table(this.tag, this.offset, this.length);

  final String tag;
  final int offset;
  final int length;
}

class _CmapMapping {
  const _CmapMapping(this.format, this.glyphs);

  final int format;
  final Map<int, int> glyphs;
}

class _Os2Metrics {
  const _Os2Metrics({
    required this.typoAscender,
    required this.typoDescender,
    required this.typoLineGap,
    required this.winAscent,
    required this.winDescent,
    required this.xHeight,
    required this.capHeight,
  });

  final int? typoAscender;
  final int? typoDescender;
  final int? typoLineGap;
  final int? winAscent;
  final int? winDescent;
  final int? xHeight;
  final int? capHeight;
}

Map<String, _Table> _readTableDirectory(Uint8List bytes, String asset) {
  if (bytes.length < 12) {
    throw FontMetricsException('$asset: file is too short to be sfnt');
  }
  final int version = _u32(bytes, 0, '$asset sfnt version');
  if (version != 0x00010000) {
    throw FontMetricsException(
      '$asset: sfnt version 0x${version.toRadixString(16)} is not static '
      'TrueType (0x10000)',
    );
  }
  final int numTables = _u16(bytes, 4, '$asset numTables');
  if (numTables == 0 || numTables > 512) {
    throw FontMetricsException('$asset: implausible table count $numTables');
  }
  final Map<String, _Table> tables = <String, _Table>{};
  for (int index = 0; index < numTables; index++) {
    final int base = 12 + index * 16;
    final int offset = _u32(bytes, base + 8, '$asset table offset $index');
    final int length = _u32(bytes, base + 12, '$asset table length $index');
    if (base + 16 > bytes.length) {
      throw FontMetricsException('$asset: truncated table directory');
    }
    if (offset + length > bytes.length) {
      throw FontMetricsException(
        '$asset: table $index extends past the file end',
      );
    }
    final String tag = String.fromCharCodes(bytes.sublist(base, base + 4));
    if (tables.containsKey(tag)) {
      throw FontMetricsException('$asset: duplicate table "$tag"');
    }
    tables[tag] = _Table(tag, offset, length);
  }
  return tables;
}

void _rejectUnsupported(Map<String, _Table> tables, String asset) {
  if (tables.containsKey('fvar')) {
    throw FontMetricsException(
      '$asset: variable font (fvar) found; the plan pins static TTFs',
    );
  }
  if (tables.containsKey('CFF ')) {
    throw FontMetricsException(
      '$asset: CFF outlines found; the plan pins TrueType outlines',
    );
  }
  for (final String required in <String>['glyf', 'loca']) {
    if (!tables.containsKey(required)) {
      throw FontMetricsException('$asset: required table "$required" missing');
    }
  }
}

_Table _require(Map<String, _Table> tables, String tag, String asset) {
  final _Table? table = tables[tag];
  if (table == null) {
    throw FontMetricsException('$asset: required table "$tag" missing');
  }
  return table;
}

_Os2Metrics _readOs2(
  Uint8List bytes,
  Map<String, _Table> tables,
  String asset,
  int expectedWeight,
) {
  final _Table? table = tables['OS/2'];
  if (table == null || table.length < 78) {
    return const _Os2Metrics(
      typoAscender: null,
      typoDescender: null,
      typoLineGap: null,
      winAscent: null,
      winDescent: null,
      xHeight: null,
      capHeight: null,
    );
  }
  final int version = _u16(bytes, table.offset, '$asset OS/2 version');
  final int weightClass = _u16(
    bytes,
    table.offset + 4,
    '$asset OS/2 usWeightClass',
  );
  if (weightClass != expectedWeight) {
    throw FontMetricsException(
      '$asset: OS/2 usWeightClass $weightClass does not match bundle weight '
      '$expectedWeight',
    );
  }
  final int typoAscender = _s16(
    bytes,
    table.offset + 68,
    '$asset OS/2 sTypoAscender',
  );
  final int typoDescender = _s16(
    bytes,
    table.offset + 70,
    '$asset OS/2 sTypoDescender',
  );
  final int typoLineGap = _s16(
    bytes,
    table.offset + 72,
    '$asset OS/2 sTypoLineGap',
  );
  final int winAscent = _u16(
    bytes,
    table.offset + 74,
    '$asset OS/2 usWinAscent',
  );
  final int winDescent = _u16(
    bytes,
    table.offset + 76,
    '$asset OS/2 usWinDescent',
  );
  int? xHeight;
  int? capHeight;
  if (version >= 2 && table.length >= 90) {
    xHeight = _s16(bytes, table.offset + 86, '$asset OS/2 sxHeight');
    capHeight = _s16(bytes, table.offset + 88, '$asset OS/2 sCapHeight');
  }
  return _Os2Metrics(
    typoAscender: typoAscender,
    typoDescender: typoDescender,
    typoLineGap: typoLineGap,
    winAscent: winAscent,
    winDescent: winDescent,
    xHeight: xHeight,
    capHeight: capHeight,
  );
}

_CmapMapping _readUnicodeCmap(
  Uint8List bytes,
  Map<String, _Table> tables,
  String asset,
  int glyphCount,
) {
  final _Table cmap = _require(tables, 'cmap', asset);
  if (cmap.length < 4) {
    throw FontMetricsException('$asset: cmap table is too short');
  }
  final int count = _u16(bytes, cmap.offset + 2, '$asset cmap numTables');
  final List<_CmapCandidate> candidates = <_CmapCandidate>[];
  for (int index = 0; index < count; index++) {
    final int record = cmap.offset + 4 + index * 8;
    if (record + 8 > cmap.offset + cmap.length) {
      throw FontMetricsException('$asset: cmap encoding record is truncated');
    }
    final int platform = _u16(bytes, record, '$asset cmap platform');
    final int encoding = _u16(bytes, record + 2, '$asset cmap encoding');
    final int offset = _u32(bytes, record + 4, '$asset cmap offset');
    if (offset + 2 > cmap.length) {
      throw FontMetricsException(
        '$asset: cmap subtable offset $offset is outside the table',
      );
    }
    final int subtable = cmap.offset + offset;
    final int format = _u16(bytes, subtable, '$asset cmap format');
    final int score = _cmapScore(platform, encoding, format);
    if (score >= 0) {
      candidates.add(_CmapCandidate(score, format, subtable));
    }
  }
  candidates.sort((_CmapCandidate a, _CmapCandidate b) {
    final int byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.format.compareTo(b.format);
  });
  for (final _CmapCandidate candidate in candidates) {
    // Do not downgrade past a malformed best subtable: a corrupt format 12
    // must fail closed, not silently fall back to BMP-only coverage.
    final Map<int, int> glyphs = switch (candidate.format) {
      12 => _parseCmapFormat12(bytes, candidate.offset, cmap, glyphCount),
      4 => _parseCmapFormat4(bytes, candidate.offset, cmap, glyphCount),
      _ => <int, int>{},
    };
    if (glyphs.isNotEmpty) {
      return _CmapMapping(candidate.format, glyphs);
    }
  }
  throw FontMetricsException(
    '$asset: no usable Unicode cmap subtable (format 4 or 12)',
  );
}

int _cmapScore(int platform, int encoding, int format) {
  final bool unicode =
      platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10));
  if (!unicode) {
    return -1;
  }
  return switch (format) {
    12 => 3,
    4 => 2,
    _ => -1,
  };
}

class _CmapCandidate {
  const _CmapCandidate(this.score, this.format, this.offset);

  final int score;
  final int format;
  final int offset;
}

Map<int, int> _parseCmapFormat12(
  Uint8List bytes,
  int subtable,
  _Table cmap,
  int glyphCount,
) {
  final int subtableLength = _u32(bytes, subtable + 4, 'cmap format 12 length');
  if (subtableLength < 16 ||
      subtable + subtableLength > cmap.offset + cmap.length) {
    throw FontMetricsException('cmap format 12 subtable is out of bounds');
  }
  final int groups = _u32(bytes, subtable + 12, 'cmap format 12 groups');
  if (subtable + 16 + groups * 12 > subtable + subtableLength) {
    throw FontMetricsException('cmap format 12 group array is truncated');
  }
  final Map<int, int> glyphs = <int, int>{};
  for (int group = 0; group < groups; group++) {
    final int base = subtable + 16 + group * 12;
    final int start = _u32(bytes, base, 'cmap format 12 start');
    final int end = _u32(bytes, base + 4, 'cmap format 12 end');
    final int startGlyph = _u32(bytes, base + 8, 'cmap format 12 glyph');
    if (start > end || end > 0x10FFFF) {
      throw FontMetricsException(
        'cmap format 12 group $group has an invalid range '
        '0x${start.toRadixString(16)}..0x${end.toRadixString(16)}',
      );
    }
    if (startGlyph + (end - start) >= glyphCount) {
      throw FontMetricsException(
        'cmap format 12 group $group maps past glyph $glyphCount',
      );
    }
    for (int codepoint = start; codepoint <= end; codepoint++) {
      glyphs[codepoint] = startGlyph + (codepoint - start);
    }
  }
  return glyphs;
}

Map<int, int> _parseCmapFormat4(
  Uint8List bytes,
  int subtable,
  _Table cmap,
  int glyphCount,
) {
  final int subtableLength = _u16(bytes, subtable + 2, 'cmap format 4 length');
  if (subtableLength < 16 ||
      subtable + subtableLength > cmap.offset + cmap.length) {
    throw FontMetricsException('cmap format 4 subtable is out of bounds');
  }
  final int segCountX2 = _u16(bytes, subtable + 6, 'cmap format 4 segCountX2');
  if (segCountX2 == 0 || segCountX2.isOdd) {
    throw FontMetricsException('cmap format 4 has an invalid segCountX2');
  }
  final int segCount = segCountX2 ~/ 2;
  final int endBase = subtable + 14;
  final int startBase = subtable + 16 + segCount * 2;
  final int deltaBase = startBase + segCount * 2;
  final int rangeBase = deltaBase + segCount * 2;
  if (rangeBase + segCount * 2 > subtable + subtableLength) {
    throw FontMetricsException('cmap format 4 segment arrays are truncated');
  }
  final Map<int, int> glyphs = <int, int>{};
  for (int segment = 0; segment < segCount; segment++) {
    final int end = _u16(bytes, endBase + segment * 2, 'cmap endCode');
    final int start = _u16(bytes, startBase + segment * 2, 'cmap startCode');
    if (start > end) {
      throw FontMetricsException('cmap format 4 segment $segment is inverted');
    }
    // 0xFFFF is the required sentinel segment, not a real character.
    if (start == 0xFFFF && end == 0xFFFF) {
      continue;
    }
    final int delta = _s16(bytes, deltaBase + segment * 2, 'cmap idDelta');
    final int rangeOffset = _u16(
      bytes,
      rangeBase + segment * 2,
      'cmap idRangeOffset',
    );
    for (int codepoint = start; codepoint <= end; codepoint++) {
      int glyph;
      if (rangeOffset == 0) {
        glyph = (codepoint + delta) & 0xFFFF;
      } else {
        final int address =
            rangeBase + segment * 2 + rangeOffset + (codepoint - start) * 2;
        if (address + 2 > subtable + subtableLength) {
          throw FontMetricsException('cmap format 4 glyph index is truncated');
        }
        glyph = _u16(bytes, address, 'cmap glyph index');
        if (glyph != 0) {
          glyph = (glyph + delta) & 0xFFFF;
        }
      }
      if (glyph == 0) {
        continue;
      }
      if (glyph >= glyphCount) {
        throw FontMetricsException(
          'cmap format 4 maps U+${_hex(codepoint)} past glyph $glyphCount',
        );
      }
      glyphs[codepoint] = glyph;
    }
  }
  return glyphs;
}

int _u16(Uint8List bytes, int offset, String context) {
  if (offset < 0 || offset + 2 > bytes.length) {
    throw FontMetricsException('$context: truncated u16 read at $offset');
  }
  return (bytes[offset] << 8) | bytes[offset + 1];
}

int _s16(Uint8List bytes, int offset, String context) {
  final int value = _u16(bytes, offset, context);
  return value >= 0x8000 ? value - 0x10000 : value;
}

int _u32(Uint8List bytes, int offset, String context) {
  if (offset < 0 || offset + 4 > bytes.length) {
    throw FontMetricsException('$context: truncated u32 read at $offset');
  }
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

const List<int> _sha256K = <int>[
  0x428a2f98,
  0x71374491,
  0xb5c0fbcf,
  0xe9b5dba5,
  0x3956c25b,
  0x59f111f1,
  0x923f82a4,
  0xab1c5ed5,
  0xd807aa98,
  0x12835b01,
  0x243185be,
  0x550c7dc3,
  0x72be5d74,
  0x80deb1fe,
  0x9bdc06a7,
  0xc19bf174,
  0xe49b69c1,
  0xefbe4786,
  0x0fc19dc6,
  0x240ca1cc,
  0x2de92c6f,
  0x4a7484aa,
  0x5cb0a9dc,
  0x76f988da,
  0x983e5152,
  0xa831c66d,
  0xb00327c8,
  0xbf597fc7,
  0xc6e00bf3,
  0xd5a79147,
  0x06ca6351,
  0x14292967,
  0x27b70a85,
  0x2e1b2138,
  0x4d2c6dfc,
  0x53380d13,
  0x650a7354,
  0x766a0abb,
  0x81c2c92e,
  0x92722c85,
  0xa2bfe8a1,
  0xa81a664b,
  0xc24b8b70,
  0xc76c51a3,
  0xd192e819,
  0xd6990624,
  0xf40e3585,
  0x106aa070,
  0x19a4c116,
  0x1e376c08,
  0x2748774c,
  0x34b0bcb5,
  0x391c0cb3,
  0x4ed8aa4a,
  0x5b9cca4f,
  0x682e6ff3,
  0x748f82ee,
  0x78a5636f,
  0x84c87814,
  0x8cc70208,
  0x90befffa,
  0xa4506ceb,
  0xbef9a3f7,
  0xc67178f2,
];

/// Lowercase hex SHA-256 of [input].
///
/// Implemented locally so the generator needs no package dependency and can
/// fail closed on bytes that differ from the T006 pins.
String sha256Hex(List<int> input) {
  final int paddedLength = ((input.length + 9 + 63) ~/ 64) * 64;
  final Uint8List data = Uint8List(paddedLength);
  data.setRange(0, input.length, input);
  data[input.length] = 0x80;
  int bitLength = input.length * 8;
  for (int index = 0; index < 8; index++) {
    data[paddedLength - 1 - index] = bitLength & 0xFF;
    bitLength >>= 8;
  }

  int h0 = 0x6a09e667;
  int h1 = 0xbb67ae85;
  int h2 = 0x3c6ef372;
  int h3 = 0xa54ff53a;
  int h4 = 0x510e527f;
  int h5 = 0x9b05688c;
  int h6 = 0x1f83d9ab;
  int h7 = 0x5be0cd19;
  final Uint32List schedule = Uint32List(64);

  for (int block = 0; block < paddedLength; block += 64) {
    for (int index = 0; index < 16; index++) {
      final int base = block + index * 4;
      schedule[index] =
          (data[base] << 24) |
          (data[base + 1] << 16) |
          (data[base + 2] << 8) |
          data[base + 3];
    }
    for (int index = 16; index < 64; index++) {
      final int s0 =
          _rotr(schedule[index - 15], 7) ^
          _rotr(schedule[index - 15], 18) ^
          (schedule[index - 15] >> 3);
      final int s1 =
          _rotr(schedule[index - 2], 17) ^
          _rotr(schedule[index - 2], 19) ^
          (schedule[index - 2] >> 10);
      schedule[index] =
          (schedule[index - 16] + s0 + schedule[index - 7] + s1) & 0xFFFFFFFF;
    }

    int a = h0;
    int b = h1;
    int c = h2;
    int d = h3;
    int e = h4;
    int f = h5;
    int g = h6;
    int h = h7;
    for (int index = 0; index < 64; index++) {
      final int sum1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final int choose = (e & f) ^ ((~e & 0xFFFFFFFF) & g);
      final int temp1 =
          (h + sum1 + choose + _sha256K[index] + schedule[index]) & 0xFFFFFFFF;
      final int sum0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final int majority = (a & b) ^ (a & c) ^ (b & c);
      final int temp2 = (sum0 + majority) & 0xFFFFFFFF;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xFFFFFFFF;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xFFFFFFFF;
    }

    h0 = (h0 + a) & 0xFFFFFFFF;
    h1 = (h1 + b) & 0xFFFFFFFF;
    h2 = (h2 + c) & 0xFFFFFFFF;
    h3 = (h3 + d) & 0xFFFFFFFF;
    h4 = (h4 + e) & 0xFFFFFFFF;
    h5 = (h5 + f) & 0xFFFFFFFF;
    h6 = (h6 + g) & 0xFFFFFFFF;
    h7 = (h7 + h) & 0xFFFFFFFF;
  }

  final StringBuffer buffer = StringBuffer();
  for (final int word in <int>[h0, h1, h2, h3, h4, h5, h6, h7]) {
    buffer.write(word.toRadixString(16).padLeft(8, '0'));
  }
  return buffer.toString();
}

int _rotr(int value, int amount) {
  return ((value >> amount) | (value << (32 - amount))) & 0xFFFFFFFF;
}
