// T007 host-VM test: the generated `metrics.json` must agree with the actual
// bundled Noto Sans bytes.
//
// This test deliberately re-parses `head`, `hhea`, `maxp`, `hmtx`, and the
// Unicode cmap from the TTF assets instead of importing the generator. It
// therefore cross-checks the generated artifact against font data through a
// second implementation, and it proves the JSON is reachable through Flutter's
// real asset bundle.
//
// It is a static/host check. It performs no rendering and produces no
// `SIMULATED`, `EMULATOR`, or `DEVICE` evidence. T030 owns the later
// `feldexa_export` layout/PDFBox parity contract.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _metricsAsset = 'assets/fonts/metrics.json';
const String _regularAsset = 'assets/fonts/NotoSans-Regular.ttf';
const String _boldAsset = 'assets/fonts/NotoSans-Bold.ttf';

const Map<String, int> _expectedBytes = <String, int>{
  _regularAsset: 790500,
  _boldAsset: 802504,
};

const Map<String, String> _expectedSha256 = <String, String>{
  _regularAsset:
      '97eaf07030b89da4eceace86b12f4d7debb3cb212082c3938803eac7111221c9',
  _boldAsset:
      '53b53721b1910c7e058c4f012126b41273d493b04d69c1ac50924f7eff8e8039',
};

const Map<String, int> _expectedWeight = <String, int>{
  _regularAsset: 400,
  _boldAsset: 700,
};

// FR-067: German form values and typographic punctuation.
const Map<String, int> _requiredCodepoints = <String, int>{
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

// Expected widths in points at 10 pt, computed once from the pinned TTFs in a
// separate Python probe. The literal values make this test fail if a
// unitsPerEm, advance, or scaling regression changes layout.
const Map<int, Map<String, double>> _expectedWidthsAt10Pt =
    <int, Map<String, double>>{
      400: <String, double>{
        'Müller-Lüdenscheidt': 96.54,
        'Größenänderung – 1.234,56 €': 140.01,
        'äöüßÄÖÜ € „“”–—…': 90.83,
      },
      700: <String, double>{
        'Müller-Lüdenscheidt': 103.11,
        'Größenänderung – 1.234,56 €': 144.96,
        'äöüßÄÖÜ € „“”–—…': 96.83,
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> metrics;
  late Map<String, Uint8List> fontBytes;

  setUpAll(() async {
    final ByteData metricsData = await rootBundle.load(_metricsAsset);
    metrics = jsonDecode(
      utf8.decode(
        metricsData.buffer.asUint8List(
          metricsData.offsetInBytes,
          metricsData.lengthInBytes,
        ),
      ),
    ) as Map<String, dynamic>;

    fontBytes = <String, Uint8List>{};
    for (final String asset in _expectedBytes.keys) {
      final ByteData data = await rootBundle.load(asset);
      fontBytes[asset] = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
    }
  });

  test('metrics.json is a schema-v1 document for both weights', () {
    expect(metrics['schemaVersion'], 1);
    expect(metrics['metricsVersion'], 'noto-sans-2.013-v1');
    expect(metrics['family'], 'NotoSans');
    expect(metrics['fontRelease'], 'NotoSans-v2.013');
    expect(metrics['unitsPerEm'], 1000);

    final Map<String, dynamic> fonts = metrics['fonts'] as Map<String, dynamic>;
    expect(fonts.keys.toSet(), <String>{'400', '700'});
    for (final int weight in <int>[400, 700]) {
      final Map<String, dynamic> font =
          fonts['$weight'] as Map<String, dynamic>;
      final String asset = font['asset'] as String;
      expect(_expectedWeight[asset], weight);
      expect(_expectedBytes.containsKey(asset), isTrue);
      expect(font['family'], 'NotoSans');
      expect(font['weight'], weight);
      expect(font['sha256'], _expectedSha256[asset]);
      expect(font['bytes'], _expectedBytes[asset]);
      expect(font['unitsPerEm'], 1000);
      expect(font['cmapFormat'], 12);
      expect(
        font['codepointCount'],
        (font['advances'] as Map<String, dynamic>).length,
      );
    }
  });

  for (final String asset in <String>[_regularAsset, _boldAsset]) {
    test('metrics for $asset match head/hhea/maxp/hmtx/cmap', () {
      final Map<String, dynamic> font = _fontForAsset(metrics, asset);
      final Uint8List bytes = fontBytes[asset]!;

      expect(bytes.length, _expectedBytes[asset]);
      final _Ttf ttf = _Ttf(bytes);
      final Map<int, int> measured = <int, int>{
        for (final MapEntry<int, int> entry in ttf.cmap12().entries)
          entry.key: ttf.advanceForGlyph(entry.value),
      };
      final Map<int, int> emitted = <int, int>{
        for (final MapEntry<String, dynamic> entry
            in (font['advances'] as Map<String, dynamic>).entries)
          int.parse(entry.key): entry.value as int,
      };

      expect(ttf.unitsPerEm, font['unitsPerEm']);
      expect(ttf.glyphCount, font['glyphCount']);
      expect(ttf.numberOfHMetrics, font['numberOfHMetrics']);
      expect(ttf.advanceWidthMax, font['advanceWidthMax']);
      expect(ttf.ascender, font['ascender']);
      expect(ttf.descender, font['descender']);
      expect(ttf.lineGap, font['lineGap']);
      expect(ttf.typoAscender, font['typoAscender']);
      expect(ttf.typoDescender, font['typoDescender']);
      expect(ttf.typoLineGap, font['typoLineGap']);
      expect(ttf.winAscent, font['winAscent']);
      expect(ttf.winDescent, font['winDescent']);
      expect(ttf.xHeight, font['xHeight']);
      expect(ttf.capHeight, font['capHeight']);
      expect(font['codepointCount'], measured.length);
      expect(font['firstCodepoint'], measured.keys.first);
      expect(font['lastCodepoint'], measured.keys.last);

      expect(emitted.keys.toSet(), measured.keys.toSet());
      final List<String> mismatches = <String>[];
      for (final int codepoint in measured.keys) {
        if (emitted[codepoint] != measured[codepoint]) {
          mismatches.add(
            'U+${codepoint.toRadixString(16).toUpperCase().padLeft(4, '0')}: '
            'metrics=${emitted[codepoint]} ttf=${measured[codepoint]}',
          );
        }
      }
      expect(mismatches, isEmpty);
    });

    test('$asset covers the FR-067 German codepoints', () {
      final Map<String, dynamic> font = _fontForAsset(metrics, asset);
      final Map<String, dynamic> advances =
          font['advances'] as Map<String, dynamic>;
      for (final MapEntry<String, int> required
          in _requiredCodepoints.entries) {
        final int? advance = advances['${required.value}'] as int?;
        expect(
          advance,
          isNotNull,
          reason: 'missing ${required.key} (U+${required.value})',
        );
        expect(advance, greaterThan(0), reason: required.key);
      }
    });
  }

  test('advance keys are emitted in ascending numeric order', () {
    final Map<String, dynamic> fonts = metrics['fonts'] as Map<String, dynamic>;
    for (final String weight in fonts.keys) {
      final Map<String, dynamic> font = fonts[weight] as Map<String, dynamic>;
      final Map<String, dynamic> advances =
          font['advances'] as Map<String, dynamic>;
      final List<int> keys = advances.keys
          .map((String key) => int.parse(key))
          .toList();
      final List<int> sorted = List<int>.of(keys)..sort();
      expect(keys, sorted);
    }
  });

  test('sample strings measure to the pinned point widths', () {
    for (final int weight in <int>[400, 700]) {
      final Map<String, dynamic> font = _fontForWeight(metrics, weight);
      final Map<int, int> advances = <int, int>{
        for (final MapEntry<String, dynamic> entry
            in (font['advances'] as Map<String, dynamic>).entries)
          int.parse(entry.key): entry.value as int,
      };
      final int unitsPerEm = font['unitsPerEm'] as int;
      final Map<String, double> expected = _expectedWidthsAt10Pt[weight]!;
      for (final MapEntry<String, double> sample in expected.entries) {
        final double at10 = _measure(
          advances: advances,
          unitsPerEm: unitsPerEm,
          text: sample.key,
          fontSizePt: 10,
        );
        expect(at10, closeTo(sample.value, 0.0001), reason: sample.key);
        expect(
          _measure(
            advances: advances,
            unitsPerEm: unitsPerEm,
            text: sample.key,
            fontSizePt: 7,
          ),
          closeTo(sample.value * 0.7, 0.0001),
        );
        expect(
          _measure(
            advances: advances,
            unitsPerEm: unitsPerEm,
            text: sample.key,
            fontSizePt: 12,
          ),
          closeTo(sample.value * 1.2, 0.0001),
        );
      }
    }
  });

  test('missing glyphs stay absent and zero-width marks stay available', () {
    for (final int weight in <int>[400, 700]) {
      final Map<String, dynamic> font = _fontForWeight(metrics, weight);
      final Map<String, dynamic> advances =
          font['advances'] as Map<String, dynamic>;
      // U+0378 is unassigned and is not in Noto Sans; absence must be
      // observable so the layout can emit EXP-004 instead of a blank glyph.
      expect(advances.containsKey('${0x0378}'), isFalse);
      // U+0301 COMBINING ACUTE ACCENT is a real, zero-advance glyph.
      expect(advances['${0x0301}'], 0);
    }
    final _Ttf regular = _Ttf(fontBytes[_regularAsset]!);
    expect(regular.cmap12().containsKey(0x0378), isFalse);
    expect(regular.cmap12()[0x0301], isNotNull);
  });
}

Map<String, dynamic> _fontForWeight(Map<String, dynamic> metrics, int weight) {
  final Map<String, dynamic> fonts = metrics['fonts'] as Map<String, dynamic>;
  return fonts['$weight'] as Map<String, dynamic>;
}

Map<String, dynamic> _fontForAsset(Map<String, dynamic> metrics, String asset) {
  final Map<String, dynamic> fonts = metrics['fonts'] as Map<String, dynamic>;
  for (final dynamic value in fonts.values) {
    final Map<String, dynamic> font = value as Map<String, dynamic>;
    if (font['asset'] == asset) {
      return font;
    }
  }
  throw StateError('metrics.json has no font for $asset');
}

double _measure({
  required Map<int, int> advances,
  required int unitsPerEm,
  required String text,
  required double fontSizePt,
}) {
  int units = 0;
  for (final int codepoint in text.runes) {
    units += advances[codepoint]!;
  }
  return units * fontSizePt / unitsPerEm;
}

class _Table {
  const _Table(this.offset, this.length);

  final int offset;
  final int length;
}

class _Ttf {
  _Ttf(this.bytes) : _data = ByteData.sublistView(bytes) {
    if (_u32(0) != 0x00010000) {
      throw StateError('not a static TrueType sfnt');
    }
    final int count = _u16(4);
    for (int index = 0; index < count; index++) {
      final int base = 12 + index * 16;
      final String tag = String.fromCharCodes(bytes.sublist(base, base + 4));
      _tables[tag] = _Table(_u32(base + 8), _u32(base + 12));
    }
  }

  final Uint8List bytes;
  final ByteData _data;
  final Map<String, _Table> _tables = <String, _Table>{};

  int get unitsPerEm => _u16(_table('head').offset + 18);

  int get glyphCount => _u16(_table('maxp').offset + 4);

  int get numberOfHMetrics => _u16(_table('hhea').offset + 34);

  int get advanceWidthMax => _u16(_table('hhea').offset + 10);

  int get ascender => _s16(_table('hhea').offset + 4);

  int get descender => _s16(_table('hhea').offset + 6);

  int get lineGap => _s16(_table('hhea').offset + 8);

  int get typoAscender => _s16(_table('OS/2').offset + 68);

  int get typoDescender => _s16(_table('OS/2').offset + 70);

  int get typoLineGap => _s16(_table('OS/2').offset + 72);

  int get winAscent => _u16(_table('OS/2').offset + 74);

  int get winDescent => _u16(_table('OS/2').offset + 76);

  int get xHeight => _s16(_table('OS/2').offset + 86);

  int get capHeight => _s16(_table('OS/2').offset + 88);

  int advanceForGlyph(int glyph) {
    final _Table hmtx = _table('hmtx');
    final int full = numberOfHMetrics;
    if (glyph < full) {
      return _u16(hmtx.offset + glyph * 4);
    }
    return _u16(hmtx.offset + (full - 1) * 4);
  }

  Map<int, int> cmap12() {
    final _Table cmap = _table('cmap');
    final int count = _u16(cmap.offset + 2);
    int? subtable;
    for (int index = 0; index < count; index++) {
      final int record = cmap.offset + 4 + index * 8;
      final int platform = _u16(record);
      final int encoding = _u16(record + 2);
      final bool unicode =
          platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10));
      if (!unicode) {
        continue;
      }
      final int offset = cmap.offset + _u32(record + 4);
      if (_u16(offset) == 12) {
        subtable = offset;
        break;
      }
    }
    if (subtable == null) {
      throw StateError('no Unicode cmap format 12 in this font');
    }
    final int groups = _u32(subtable + 12);
    final Map<int, int> glyphs = <int, int>{};
    for (int group = 0; group < groups; group++) {
      final int base = subtable + 16 + group * 12;
      final int start = _u32(base);
      final int end = _u32(base + 4);
      final int startGlyph = _u32(base + 8);
      for (int codepoint = start; codepoint <= end; codepoint++) {
        glyphs[codepoint] = startGlyph + (codepoint - start);
      }
    }
    return glyphs;
  }

  _Table _table(String tag) {
    final _Table? table = _tables[tag];
    if (table == null) {
      throw StateError('missing table "$tag"');
    }
    return table;
  }

  int _u16(int offset) => _data.getUint16(offset, Endian.big);

  int _s16(int offset) => _data.getInt16(offset, Endian.big);

  int _u32(int offset) => _data.getUint32(offset, Endian.big);
}
