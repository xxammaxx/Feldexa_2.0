// Deterministic PDF writer with one embedded TrueType font (T263).
//
// Why this writer exists: the shared synthetic writer
// (`../synthetic/pdf_writer.dart`) draws with base-14 Helvetica and
// `/WinAnsiEncoding`. WinAnsi cannot encode U+1E9E (LATIN CAPITAL LETTER
// SHARP S), so a German character reference that must print `ẞ` cannot use it.
// This writer instead embeds the project's bundled Noto Sans Regular
// (`apps/feldexa_app/assets/fonts/NotoSans-Regular.ttf`, OFL) as a Type0 /
// CIDFontType2 font with `/Identity-H` encoding, `CIDToGIDMap /Identity`, and a
// `ToUnicode` CMap. Consequences:
//
//  * every required glyph (Ä Ö Ü ä ö ü ß ẞ € ² ³ „ “ – — … §) is drawn from
//    the same outlines the app bundles, so a rasterized page shows the real
//    glyph and not a fallback;
//  * the text layer is character-faithful: `pdftotext` extracts the exact
//    Unicode code points written here, which makes the text layer usable as a
//    control path (`TEXT_LAYER`) without any normalization;
//  * output stays byte-deterministic: fixed object order, no timestamps, no
//    random IDs, fixed `/ID`, un-compressed streams, and the whole font file is
//    embedded verbatim (no subsetting, so no outline rewriting can drift).
//
// The font bytes are never modified; the generator pins their SHA-256. This
// module has no I/O, clock, randomness, or locale dependency.

import 'dart:convert';
import 'dart:typed_data';

/// A parsed TrueType font: glyph ids, advance widths, and vertical metrics.
final class TrueTypeFont {
  TrueTypeFont._({
    required this.bytes,
    required this.unitsPerEm,
    required this.numGlyphs,
    required this.ascender,
    required this.descender,
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
    required Map<int, int> codePointsToGlyph,
    required List<int> advanceWidths,
    // The private fields are assigned explicitly so the constructor keeps
    // named parameters with plain identifiers.
  }) : _codePointsToGlyph = codePointsToGlyph,
       _advanceWidths = advanceWidths;

  /// The unmodified font file bytes that are embedded verbatim.
  final Uint8List bytes;

  /// Font design units per em.
  final int unitsPerEm;

  /// Number of glyphs declared by `maxp`.
  final int numGlyphs;

  /// `hhea` ascender in design units.
  final int ascender;

  /// `hhea` descender (negative) in design units.
  final int descender;

  /// `head` font bounding box in design units.
  final int xMin;
  final int yMin;
  final int xMax;
  final int yMax;

  // ignore_for_file: prefer_initializing_formals
  final Map<int, int> _codePointsToGlyph;
  final List<int> _advanceWidths;

  /// Parses a TrueType font file.
  ///
  /// Throws a content-free [FormatException] when a required table is missing
  /// or malformed. Only `head`, `hhea`, `maxp`, `hmtx`, and `cmap` are read.
  static TrueTypeFont parse(Uint8List bytes) {
    if (bytes.length < 12) {
      throw const FormatException('font file is too short');
    }
    final ByteData data = ByteData.sublistView(bytes);
    final int version = data.getUint32(0);
    if (version != 0x00010000 && version != 0x74727565) {
      throw const FormatException('unsupported font sfntVersion');
    }
    final int numTables = data.getUint16(4);
    final Map<String, ({int offset, int length})> tables =
        <String, ({int offset, int length})>{};
    for (int index = 0; index < numTables; index++) {
      final int record = 12 + index * 16;
      if (record + 16 > bytes.length) {
        throw const FormatException('font table directory is truncated');
      }
      final String tag = String.fromCharCodes(
        bytes.sublist(record, record + 4),
      );
      final int offset = data.getUint32(record + 8);
      final int length = data.getUint32(record + 12);
      if (offset + length > bytes.length) {
        throw const FormatException('font table extends past the file');
      }
      tables[tag] = (offset: offset, length: length);
    }
    for (final String required in <String>[
      'head',
      'hhea',
      'maxp',
      'hmtx',
      'cmap',
    ]) {
      if (!tables.containsKey(required)) {
        throw const FormatException('font is missing a required table');
      }
    }

    final ({int offset, int length}) head = tables['head']!;
    final int unitsPerEm = data.getUint16(head.offset + 18);
    if (unitsPerEm < 16 || unitsPerEm > 16384) {
      throw const FormatException('font unitsPerEm is out of range');
    }
    final ({int offset, int length}) hhea = tables['hhea']!;
    final int ascender = data.getInt16(hhea.offset + 4);
    final int descender = data.getInt16(hhea.offset + 6);
    final int numberOfHMetrics = data.getUint16(hhea.offset + 34);
    final int numGlyphs = data.getUint16(tables['maxp']!.offset + 4);
    if (numberOfHMetrics < 1 || numberOfHMetrics > numGlyphs) {
      throw const FormatException('font hhea numberOfHMetrics is invalid');
    }

    final ({int offset, int length}) hmtx = tables['hmtx']!;
    final List<int> advances = List<int>.filled(numGlyphs, 0);
    int lastAdvance = 0;
    for (int glyph = 0; glyph < numGlyphs; glyph++) {
      if (glyph < numberOfHMetrics) {
        lastAdvance = data.getUint16(hmtx.offset + glyph * 4);
      }
      advances[glyph] = lastAdvance;
    }

    final Map<int, int> codePoints = _readCmap(data, tables['cmap']!);

    return TrueTypeFont._(
      bytes: bytes,
      unitsPerEm: unitsPerEm,
      numGlyphs: numGlyphs,
      ascender: ascender,
      descender: descender,
      xMin: data.getInt16(head.offset + 36),
      yMin: data.getInt16(head.offset + 38),
      xMax: data.getInt16(head.offset + 40),
      yMax: data.getInt16(head.offset + 42),
      codePointsToGlyph: codePoints,
      advanceWidths: advances,
    );
  }

  static Map<int, int> _readCmap(
    ByteData data,
    ({int offset, int length}) cmap,
  ) {
    final int subtableCount = data.getUint16(cmap.offset + 2);
    ({int offset, int format})? chosen;
    for (int index = 0; index < subtableCount; index++) {
      final int record = cmap.offset + 4 + index * 8;
      final int platform = data.getUint16(record);
      final int encoding = data.getUint16(record + 2);
      final int subtableOffset = data.getUint32(record + 4);
      final int offset = cmap.offset + subtableOffset;
      final int format = data.getUint16(offset);
      final bool unicodeFull =
          (platform == 3 && encoding == 10) || (platform == 0 && encoding == 4);
      final bool unicodeBmp =
          (platform == 3 && encoding == 1) || (platform == 0 && encoding == 3);
      if (unicodeFull && format == 12) {
        chosen = (offset: offset, format: 12);
        break;
      }
      if (unicodeBmp && format == 4 && chosen == null) {
        chosen = (offset: offset, format: 4);
      }
    }
    if (chosen == null) {
      throw const FormatException('font has no usable Unicode cmap subtable');
    }
    final Map<int, int> mapping = <int, int>{};
    if (chosen.format == 12) {
      final int groups = data.getUint32(chosen.offset + 12);
      for (int group = 0; group < groups; group++) {
        final int record = chosen.offset + 16 + group * 12;
        final int start = data.getUint32(record);
        final int end = data.getUint32(record + 4);
        final int startGlyph = data.getUint32(record + 8);
        if (end < start || end - start > 0x10000) {
          throw const FormatException('font cmap group is invalid');
        }
        for (int codePoint = start; codePoint <= end; codePoint++) {
          mapping[codePoint] = startGlyph + (codePoint - start);
        }
      }
      return mapping;
    }
    final int segmentCount = data.getUint16(chosen.offset + 6) ~/ 2;
    final int endCodes = chosen.offset + 14;
    final int startCodes = endCodes + segmentCount * 2 + 2;
    final int deltas = startCodes + segmentCount * 2;
    final int rangeOffsets = deltas + segmentCount * 2;
    for (int segment = 0; segment < segmentCount; segment++) {
      final int end = data.getUint16(endCodes + segment * 2);
      final int start = data.getUint16(startCodes + segment * 2);
      if (start > end) {
        continue;
      }
      final int delta = data.getInt16(deltas + segment * 2);
      final int rangeOffset = data.getUint16(rangeOffsets + segment * 2);
      for (int codePoint = start; codePoint <= end; codePoint++) {
        final int glyph;
        if (rangeOffset == 0) {
          glyph = (codePoint + delta) & 0xFFFF;
        } else {
          final int address =
              rangeOffsets + segment * 2 + rangeOffset + (codePoint - start) * 2;
          if (address + 2 > data.lengthInBytes) {
            continue;
          }
          final int raw = data.getUint16(address);
          glyph = raw == 0 ? 0 : (raw + delta) & 0xFFFF;
        }
        if (glyph != 0 && codePoint != 0xFFFF) {
          mapping[codePoint] = glyph;
        }
      }
    }
    return mapping;
  }

  /// Returns the glyph id for [codePoint] or throws a content-free error.
  int glyphIdFor(int codePoint) {
    final int? glyph = _codePointsToGlyph[codePoint];
    if (glyph == null) {
      throw FormatException(
        'embedded font does not cover U+${codePoint.toRadixString(16).toUpperCase().padLeft(4, '0')}',
      );
    }
    return glyph;
  }

  /// Glyph ids for every Unicode code point of [text].
  List<int> glyphIds(String text) {
    return <int>[for (final int rune in text.runes) glyphIdFor(rune)];
  }

  /// Advance width of one glyph in 1/1000 text-space units.
  int widthUnits(int glyphId) {
    final int advance = _advanceWidths[glyphId];
    return (advance * 1000 / unitsPerEm).round();
  }

  /// Advance width of [text] in PDF points at [sizePt].
  double advancePt(String text, double sizePt) {
    int total = 0;
    for (final int glyph in glyphIds(text)) {
      total += _advanceWidths[glyph];
    }
    return total / unitsPerEm * sizePt;
  }

  /// Reverse glyph-to-code-point map for the given glyph ids.
  Map<int, int> codePointsForGlyphs(Iterable<int> glyphIds) {
    final Map<int, int> result = <int, int>{};
    final Set<int> wanted = glyphIds.toSet();
    final List<int> sorted = _codePointsToGlyph.keys.toList()..sort();
    for (final int codePoint in sorted) {
      final int glyph = _codePointsToGlyph[codePoint]!;
      if (wanted.contains(glyph) && !result.containsKey(glyph)) {
        result[glyph] = codePoint;
      }
    }
    return result;
  }
}

/// One page drawn with the embedded font, in display space (top-left origin).
final class FontPdfPage {
  FontPdfPage({required this.widthPt, required this.heightPt}) {
    if (widthPt <= 0 || heightPt <= 0) {
      throw ArgumentError('page dimensions must be positive');
    }
  }

  /// Page width in points.
  final double widthPt;

  /// Page height in points.
  final double heightPt;

  final List<String> _operations = <String>[];

  /// Draws [text] with its top-left corner at ([x], [yTop]).
  ///
  /// Returns the advance width in points. [bold] uses text render mode 2
  /// (fill plus stroke) so the same font file can print a heavier line without
  /// embedding a second font.
  double text({
    required double x,
    required double yTop,
    required double size,
    required String text,
    TrueTypeFont? font,
    bool bold = false,
    double gray = 0,
  }) {
    if (size <= 0) {
      throw ArgumentError('font size must be positive');
    }
    final TrueTypeFont drawingFont = font ?? _drawingFont;
    final double baseline = yTop + size * 0.8;
    final double pdfY = heightPt - baseline;
    final String hex = _glyphHex(drawingFont, text);
    final String render = bold
        ? '${_n(size / 30)} w 2 Tr'
        : '0 Tr';
    _operations.add(
      '${_color(gray)} BT /F1 ${_n(size)} Tf $render '
      '1 0 0 1 ${_n(x)} ${_n(pdfY)} Tm <$hex> Tj ET',
    );
    return drawingFont.advancePt(text, size);
  }

  /// Draws a horizontal rule in display space.
  void line(
    double x1,
    double y1,
    double x2,
    double y2, {
    double width = 0.6,
    double gray = 0,
  }) {
    _operations.add(
      '${_color(gray)} ${_n(width)} w ${_n(x1)} ${_n(heightPt - y1)} m '
      '${_n(x2)} ${_n(heightPt - y2)} l S',
    );
  }

  /// Draws a rectangle outline in display space.
  void rect(
    double x,
    double y,
    double width,
    double height, {
    double strokeWidth = 0.6,
    double gray = 0,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('rectangle dimensions must be positive');
    }
    _operations.add(
      '${_color(gray)} ${_n(strokeWidth)} w '
      '${_n(x)} ${_n(heightPt - y - height)} ${_n(width)} ${_n(height)} re S',
    );
  }

  /// Content stream bytes for this page.
  List<int> contentBytes() {
    return utf8.encode('${_operations.join('\n')}\n');
  }

  /// The font used when [text] does not pass one explicitly.
  ///
  /// Set by [EmbeddedFontPdf] before assembly so page declarations stay short.
  TrueTypeFont get _drawingFont {
    final TrueTypeFont? font = _font;
    if (font == null) {
      throw StateError('page must be assembled before drawing');
    }
    return font;
  }

  TrueTypeFont? _font;

  void attachFont(TrueTypeFont font) {
    _font = font;
  }
}

/// Assembles embedded-font pages into a deterministic PDF 1.7 byte sequence.
final class EmbeddedFontPdf {
  EmbeddedFontPdf({
    required this.font,
    required List<FontPdfPage> pages,
    this.fontName = 'NotoSans-Regular',
  }) : _pages = List<FontPdfPage>.unmodifiable(pages) {
    if (_pages.isEmpty) {
      throw ArgumentError('a PDF must have at least one page');
    }
    for (final FontPdfPage page in _pages) {
      page.attachFont(font);
    }
  }

  /// The embedded font.
  final TrueTypeFont font;

  /// Base font name written into the font dictionaries.
  final String fontName;

  final List<FontPdfPage> _pages;

  /// Fixed document id, identical to the shared synthetic writer
  /// (`FELDEXAFIXTURE01`) so every synthetic fixture follows one convention.
  static const List<int> documentId = <int>[
    0x46, 0x45, 0x4C, 0x44, 0x45, 0x58, 0x41, 0x46, 0x49, 0x58, 0x54, 0x55,
    0x52, 0x45, 0x30, 0x31,
  ];

  /// Builds the complete PDF bytes.
  Uint8List build() {
    final int pageCount = _pages.length;
    // 1 catalog, 2 pages, 3 Type0 font, 4 CIDFont, 5 descriptor, 6 font file,
    // 7 ToUnicode, then page/content pairs.
    const int firstPageObject = 8;
    final int objectCount = firstPageObject + pageCount * 2 - 1;
    final List<List<int>> objects = List<List<int>>.filled(
      objectCount + 1,
      <int>[],
    );

    // Collect the glyphs actually used so /W and ToUnicode stay small.
    final Set<int> usedGlyphs = <int>{};
    final List<List<int>> contents = <List<int>>[];
    for (final FontPdfPage page in _pages) {
      final List<String> operations = page._operations;
      for (final String operation in operations) {
        final RegExpMatch? match = _hexTextPattern.firstMatch(operation);
        if (match == null) {
          continue;
        }
        final String hex = match.group(1)!;
        for (int index = 0; index + 4 <= hex.length; index += 4) {
          usedGlyphs.add(int.parse(hex.substring(index, index + 4), radix: 16));
        }
      }
      contents.add(page.contentBytes());
    }
    final List<int> sortedGlyphs = usedGlyphs.toList()..sort();
    final Map<int, int> reverse = font.codePointsForGlyphs(sortedGlyphs);
    for (final int glyph in sortedGlyphs) {
      if (!reverse.containsKey(glyph)) {
        throw StateError('no Unicode mapping for a used glyph');
      }
    }

    objects[1] = _ascii('<< /Type /Catalog /Pages 2 0 R >>');
    final StringBuffer kids = StringBuffer();
    for (int index = 0; index < pageCount; index++) {
      kids.write('${firstPageObject + index * 2} 0 R ');
    }
    objects[2] = _ascii(
      '<< /Type /Pages /Count $pageCount /Kids [${kids.toString().trim()}] >>',
    );
    objects[3] = _ascii(
      '<< /Type /Font /Subtype /Type0 /BaseFont /$fontName '
      '/Encoding /Identity-H /DescendantFonts [4 0 R] /ToUnicode 7 0 R >>',
    );
    objects[4] = _ascii(
      '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /$fontName '
      '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) '
      '/Supplement 0 >> /FontDescriptor 5 0 R /DW 556 '
      '/W [${_widthArray(sortedGlyphs)}] /CIDToGIDMap /Identity >>',
    );
    objects[5] = _ascii(
      '<< /Type /FontDescriptor /FontName /$fontName /Flags 4 '
      '/FontBBox [${font.xMin} ${font.yMin} ${font.xMax} ${font.yMax}] '
      '/ItalicAngle 0 /Ascent ${font.ascender} /Descent ${font.descender} '
      '/CapHeight ${(font.unitsPerEm * 0.7).round()} /StemV 80 '
      '/FontFile2 6 0 R >>',
    );
    objects[6] = _streamObject(
      font.bytes,
      extra: ' /Length1 ${font.bytes.length}',
    );
    objects[7] = _streamObject(
      _toUnicodeCMap(sortedGlyphs, reverse),
    );

    for (int index = 0; index < pageCount; index++) {
      final FontPdfPage page = _pages[index];
      final int pageObject = firstPageObject + index * 2;
      final int contentObject = pageObject + 1;
      objects[pageObject] = _ascii(
        '<< /Type /Page /Parent 2 0 R '
        '/MediaBox [0 0 ${_n(page.widthPt)} ${_n(page.heightPt)}] '
        '/Rotate 0 /Resources << /Font << /F1 3 0 R >> >> '
        '/Contents $contentObject 0 R >>',
      );
      objects[contentObject] = _streamObject(contents[index]);
    }

    final BytesBuilder builder = BytesBuilder(copy: false);
    builder.add(_ascii('%PDF-1.7\n'));
    builder.add(_ascii('%FELDEXA-SYNTHETIC-FIXTURE\n'));

    final List<int> offsets = List<int>.filled(objectCount + 1, 0);
    for (int number = 1; number <= objectCount; number++) {
      offsets[number] = builder.length;
      builder.add(_ascii('$number 0 obj\n'));
      builder.add(objects[number]);
      builder.add(_ascii('\nendobj\n'));
    }

    final int xrefOffset = builder.length;
    final StringBuffer xref = StringBuffer();
    xref.write('xref\n0 ${objectCount + 1}\n');
    xref.write('0000000000 65535 f \n');
    for (int number = 1; number <= objectCount; number++) {
      xref.write('${offsets[number].toString().padLeft(10, '0')} 00000 n \n');
    }
    builder.add(_ascii(xref.toString()));

    final String idHex = _hexUpper(documentId);
    builder.add(
      _ascii(
        'trailer\n<< /Size ${objectCount + 1} /Root 1 0 R '
        '/ID [<$idHex> <$idHex>] >>\nstartxref\n$xrefOffset\n%%EOF\n',
      ),
    );
    return builder.takeBytes();
  }

  String _widthArray(List<int> glyphs) {
    final StringBuffer buffer = StringBuffer();
    for (final int glyph in glyphs) {
      if (buffer.isNotEmpty) {
        buffer.write(' ');
      }
      buffer.write('$glyph [${font.widthUnits(glyph)}]');
    }
    return buffer.toString();
  }

  static List<int> _toUnicodeCMap(List<int> glyphs, Map<int, int> reverse) {
    final StringBuffer buffer = StringBuffer();
    buffer.write(
      '/CIDInit /ProcSet findresource begin\n'
      '12 dict begin\n'
      'begincmap\n'
      '/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> '
      'def\n'
      '/CMapName /Adobe-Identity-UCS def\n'
      '/CMapType 2 def\n'
      '1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n',
    );
    for (int start = 0; start < glyphs.length; start += 100) {
      final List<int> chunk = glyphs.sublist(
        start,
        start + 100 > glyphs.length ? glyphs.length : start + 100,
      );
      buffer.write('${chunk.length} beginbfchar\n');
      for (final int glyph in chunk) {
        buffer.write(
          '<${_hexUpper(<int>[glyph >> 8, glyph & 0xFF])}> '
          '<${_utf16BeHex(reverse[glyph]!)}>\n',
        );
      }
      buffer.write('endbfchar\n');
    }
    buffer.write(
      'endcmap\n'
      'CMapName currentdict /CMap defineresource pop\n'
      'end\nend\n',
    );
    return latin1.encode(buffer.toString());
  }

  static List<int> _streamObject(List<int> data, {String extra = ''}) {
    final BytesBuilder builder = BytesBuilder(copy: false);
    builder.add(_ascii('<< /Length ${data.length}$extra >>\nstream\n'));
    builder.add(data);
    builder.add(_ascii('\nendstream'));
    return builder.takeBytes();
  }
}

final RegExp _hexTextPattern = RegExp(r'<([0-9A-F]+)> Tj');

String _glyphHex(TrueTypeFont font, String text) {
  final StringBuffer buffer = StringBuffer();
  for (final int glyph in font.glyphIds(text)) {
    buffer.write(_hexUpper(<int>[glyph >> 8, glyph & 0xFF]));
  }
  return buffer.toString();
}

String _utf16BeHex(int codePoint) {
  if (codePoint <= 0xFFFF) {
    return _hexUpper(<int>[codePoint >> 8, codePoint & 0xFF]);
  }
  final int offset = codePoint - 0x10000;
  final int high = 0xD800 + (offset >> 10);
  final int low = 0xDC00 + (offset & 0x3FF);
  return _hexUpper(<int>[
    high >> 8,
    high & 0xFF,
    low >> 8,
    low & 0xFF,
  ]);
}

List<int> _ascii(String value) => latin1.encode(value);

String _color(double gray) => '${_n(gray)} g';

String _n(double value) {
  if (!value.isFinite) {
    throw ArgumentError('PDF numbers must be finite');
  }
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  String text = value.toStringAsFixed(4);
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

String _hexUpper(List<int> bytes) {
  final StringBuffer buffer = StringBuffer();
  for (final int byte in bytes) {
    buffer.write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
  }
  return buffer.toString();
}
