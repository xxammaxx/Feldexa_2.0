// Deterministic, dependency-free PDF writer for synthetic Feldexa fixtures.
//
// The writer is intentionally small and boring: base-14 Helvetica, uncompressed
// content streams, fixed object order, no timestamps, no random IDs, and a
// fixed `/ID`. Two invocations therefore produce byte-identical files.
//
// Geometry is authored in **page display space** (points, top-left origin,
// y down) and converted with the exact rotation formulas from
// `contracts/coordinates-and-geometry.md` §2. Text on rotated pages is drawn
// with the inverse rotation matrix so it reads upright after `/Rotate` is
// applied by a viewer.

import 'dart:convert';
import 'dart:typed_data';

import 'crypto.dart';

/// One page of a synthetic PDF.
class PdfPage {
  PdfPage({required this.widthPt, required this.heightPt, this.rotation = 0}) {
    if (rotation != 0 && rotation != 90 && rotation != 180 && rotation != 270) {
      throw ArgumentError('rotation must be 0, 90, 180, or 270');
    }
    if (widthPt <= 0 || heightPt <= 0) {
      throw ArgumentError('page dimensions must be positive');
    }
  }

  /// MediaBox width in points (unrotated PDF user space).
  final double widthPt;

  /// MediaBox height in points (unrotated PDF user space).
  final double heightPt;

  /// Page `/Rotate` value.
  final int rotation;

  final List<String> _operations = <String>[];

  /// Width of the page as displayed after `/Rotate`.
  double get displayWidth =>
      rotation == 90 || rotation == 270 ? heightPt : widthPt;

  /// Height of the page as displayed after `/Rotate`.
  double get displayHeight =>
      rotation == 90 || rotation == 270 ? widthPt : heightPt;

  void text({
    required double x,
    required double yTop,
    required double size,
    required String text,
    bool bold = false,
    double gray = 0,
  }) {
    if (size <= 0) {
      throw ArgumentError('font size must be positive');
    }
    final double baseline = yTop + size * 0.8;
    final _Point origin = _displayToPdf(x, baseline);
    final String matrix = _textMatrix(origin);
    final String font = bold ? '/F2' : '/F1';
    _operations.add(
      '${_color(gray)} BT $font ${_n(size)} Tf $matrix '
      '(${_pdfString(text)}) Tj ET',
    );
  }

  void line(
    double x1,
    double y1,
    double x2,
    double y2, {
    double width = 0.6,
    double gray = 0,
  }) {
    final _Point start = _displayToPdf(x1, y1);
    final _Point end = _displayToPdf(x2, y2);
    _operations.add(
      '${_color(gray)} ${_n(width)} w ${_n(start.x)} ${_n(start.y)} m '
      '${_n(end.x)} ${_n(end.y)} l S',
    );
  }

  void rect(
    double x,
    double y,
    double width,
    double height, {
    double strokeWidth = 0.6,
    double gray = 0,
    bool fill = false,
    double fillGray = 0.92,
  }) {
    final _PdfRect pdfRect = _displayRectToPdf(x, y, width, height);
    final String path =
        '${_n(pdfRect.x)} ${_n(pdfRect.y)} ${_n(pdfRect.width)} '
        '${_n(pdfRect.height)} re';
    if (fill) {
      _operations.add('q ${_color(fillGray)} $path f Q');
    } else {
      _operations.add('${_color(gray)} ${_n(strokeWidth)} w $path S');
    }
  }

  /// Builds the page's content stream bytes.
  List<int> contentBytes() {
    return utf8.encode('${_operations.join('\n')}\n');
  }

  _Point _displayToPdf(double x, double y) {
    switch (rotation) {
      case 0:
        return _Point(x, heightPt - y);
      case 90:
        return _Point(y, x);
      case 180:
        return _Point(widthPt - x, y);
      case 270:
        return _Point(widthPt - y, heightPt - x);
    }
    throw StateError('unreachable rotation');
  }

  _PdfRect _displayRectToPdf(double x, double y, double width, double height) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('rectangle dimensions must be positive');
    }
    switch (rotation) {
      case 0:
        return _PdfRect(x, heightPt - y - height, width, height);
      case 90:
        return _PdfRect(y, x, height, width);
      case 180:
        return _PdfRect(widthPt - x - width, y, width, height);
      case 270:
        return _PdfRect(
          widthPt - y - height,
          heightPt - x - width,
          height,
          width,
        );
    }
    throw StateError('unreachable rotation');
  }

  String _textMatrix(_Point origin) {
    switch (rotation) {
      case 0:
        return '1 0 0 1 ${_n(origin.x)} ${_n(origin.y)} Tm';
      case 90:
        return '0 1 -1 0 ${_n(origin.x)} ${_n(origin.y)} Tm';
      case 180:
        return '-1 0 0 -1 ${_n(origin.x)} ${_n(origin.y)} Tm';
      case 270:
        return '0 -1 1 0 ${_n(origin.x)} ${_n(origin.y)} Tm';
    }
    throw StateError('unreachable rotation');
  }
}

/// Assembles pages into a deterministic PDF byte sequence.
class PdfDocument {
  PdfDocument({required List<PdfPage> pages, this.encryption})
    : _pages = List<PdfPage>.unmodifiable(pages) {
    if (_pages.isEmpty) {
      throw ArgumentError('a PDF must have at least one page');
    }
  }

  final List<PdfPage> _pages;
  final PdfEncryption? encryption;

  /// Fixed document ID. A fixed ID keeps output byte-identical across runs.
  static const List<int> documentId = <int>[
    0x46,
    0x45,
    0x4C,
    0x44,
    0x45,
    0x58,
    0x41,
    0x46,
    0x49,
    0x58,
    0x54,
    0x55,
    0x52,
    0x45,
    0x30,
    0x31,
  ];

  Uint8List build() {
    final int pageCount = _pages.length;
    // Object numbers: 1 = Catalog, 2 = Pages, 3 = F1, 4 = F2, then two
    // objects per page (page, content), then the encryption dictionary.
    final int firstPageObject = 5;
    final int encryptionObject = encryption == null
        ? -1
        : firstPageObject + pageCount * 2;
    final int objectCount = encryption == null
        ? firstPageObject + pageCount * 2 - 1
        : encryptionObject;

    final List<List<int>> objects = List<List<int>>.filled(
      objectCount + 1,
      <int>[],
    );

    objects[1] = _ascii('<< /Type /Catalog /Pages 2 0 R >>');
    final StringBuffer kids = StringBuffer();
    for (int index = 0; index < pageCount; index++) {
      final int pageObject = firstPageObject + index * 2;
      kids.write('$pageObject 0 R ');
    }
    objects[2] = _ascii(
      '<< /Type /Pages /Count $pageCount /Kids [${kids.toString().trim()}] >>',
    );
    objects[3] = _ascii(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
      '/Encoding /WinAnsiEncoding >>',
    );
    objects[4] = _ascii(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold '
      '/Encoding /WinAnsiEncoding >>',
    );

    for (int index = 0; index < pageCount; index++) {
      final PdfPage page = _pages[index];
      final int pageObject = firstPageObject + index * 2;
      final int contentObject = pageObject + 1;
      objects[pageObject] = _ascii(
        '<< /Type /Page /Parent 2 0 R '
        '/MediaBox [0 0 ${_n(page.widthPt)} ${_n(page.heightPt)}] '
        '/Rotate ${page.rotation} '
        '/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> '
        '/Contents $contentObject 0 R >>',
      );

      List<int> content = page.contentBytes();
      if (encryption != null) {
        content = encryption!.encryptStream(contentObject, 0, content);
      }
      objects[contentObject] = _streamObject(content);
    }

    if (encryption != null) {
      final PdfEncryption handler = encryption!;
      objects[encryptionObject] = _ascii(
        '<< /Filter /Standard /V 1 /R 2 /Length 40 '
        '/P ${PdfEncryption.permissions} '
        '/O <${handler.ownerEntryHex}> /U <${handler.userEntryHex}> >>',
      );
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

    final StringBuffer trailer = StringBuffer();
    trailer.write('<< /Size ${objectCount + 1} /Root 1 0 R ');
    final String idHex = _hexUpper(documentId);
    trailer.write('/ID [<$idHex> <$idHex>] ');
    if (encryption != null) {
      trailer.write('/Encrypt $encryptionObject 0 R ');
    }
    trailer.write('>>');
    builder.add(_ascii('trailer\n$trailer\nstartxref\n$xrefOffset\n%%EOF\n'));

    return builder.takeBytes();
  }

  static List<int> _streamObject(List<int> data) {
    final BytesBuilder builder = BytesBuilder(copy: false);
    builder.add(_ascii('<< /Length ${data.length} >>\nstream\n'));
    builder.add(data);
    builder.add(_ascii('\nendstream'));
    return builder.takeBytes();
  }
}

class _Point {
  const _Point(this.x, this.y);
  final double x;
  final double y;
}

class _PdfRect {
  const _PdfRect(this.x, this.y, this.width, this.height);
  final double x;
  final double y;
  final double width;
  final double height;
}

List<int> _ascii(String value) {
  return latin1.encode(value);
}

String _color(double gray) {
  return '${_n(gray)} g';
}

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
    buffer.write(byte.toRadixString(16).padLeft(2, '0').toUpperCase());
  }
  return buffer.toString();
}

/// Escapes [text] as a WinAnsi PDF literal string.
///
/// Non-ASCII bytes are written as octal escapes so the unencrypted content
/// stream stays valid 7-bit ASCII and diffable.
String _pdfString(String text) {
  final StringBuffer buffer = StringBuffer();
  for (final int rune in text.runes) {
    final int byte = _winAnsi(rune);
    if (byte == 0x28 || byte == 0x29 || byte == 0x5C) {
      buffer.write('\\');
      buffer.writeCharCode(byte);
    } else if (byte < 0x20 || byte > 0x7E) {
      buffer.write('\\');
      buffer.write(byte.toRadixString(8).padLeft(3, '0'));
    } else {
      buffer.writeCharCode(byte);
    }
  }
  return buffer.toString();
}

int _winAnsi(int rune) {
  switch (rune) {
    case 0x20AC:
      return 0x80;
    case 0x201A:
      return 0x82;
    case 0x0192:
      return 0x83;
    case 0x201E:
      return 0x84;
    case 0x2026:
      return 0x85;
    case 0x2020:
      return 0x86;
    case 0x2021:
      return 0x87;
    case 0x02C6:
      return 0x88;
    case 0x2030:
      return 0x89;
    case 0x0160:
      return 0x8A;
    case 0x2039:
      return 0x8B;
    case 0x0152:
      return 0x8C;
    case 0x017D:
      return 0x8E;
    case 0x2018:
      return 0x91;
    case 0x2019:
      return 0x92;
    case 0x201C:
      return 0x93;
    case 0x201D:
      return 0x94;
    case 0x2022:
      return 0x95;
    case 0x2013:
      return 0x96;
    case 0x2014:
      return 0x97;
    case 0x02DC:
      return 0x98;
    case 0x2122:
      return 0x99;
    case 0x0161:
      return 0x9A;
    case 0x203A:
      return 0x9B;
    case 0x0153:
      return 0x9C;
    case 0x017E:
      return 0x9E;
    case 0x0178:
      return 0x9F;
  }
  if (rune >= 0x20 && rune <= 0xFF) {
    return rune;
  }
  throw ArgumentError(
    'U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')} has no '
    'WinAnsi representation in the synthetic fixture font set',
  );
}

/// Approximate Helvetica advance width in points.
///
/// The fixtures only need stable, plausible text boxes; exact Base-14 metrics
/// are not part of the fixture contract. Ground truth is carried explicitly in
/// the catalog, not inferred from this estimate.
double approxTextWidth(String text, double size, {bool bold = false}) {
  double factor = 0;
  for (final int rune in text.runes) {
    factor += _charFactor(rune);
  }
  return factor * size * (bold ? 1.03 : 1.0);
}

double _charFactor(int rune) {
  if (rune == 0x20) {
    return 0.28;
  }
  if (rune == 0x49 || rune == 0x69 || rune == 0x6C) {
    return 0.25;
  }
  if (rune == 0x6D || rune == 0x4D || rune == 0x57) {
    return 0.86;
  }
  if (rune >= 0x30 && rune <= 0x39) {
    return 0.56;
  }
  if (rune >= 0x41 && rune <= 0x5A) {
    return 0.66;
  }
  if (rune == 0xE4 ||
      rune == 0xF6 ||
      rune == 0xFC ||
      rune == 0xDF ||
      rune == 0xC4 ||
      rune == 0xD6 ||
      rune == 0xDC ||
      rune == 0x20AC) {
    return 0.56;
  }
  if (rune == 0x2E || rune == 0x2C || rune == 0x3A || rune == 0x3B) {
    return 0.28;
  }
  return 0.52;
}
