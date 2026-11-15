// T030 font-metrics contract test.
//
// This host-VM test (`NONE` evidence) is the `feldexa_export` contract for the
// bundled Noto Sans advance table. It re-parses the static TTFs with a second,
// independent Dart sfnt implementation and compares every Unicode cmap entry,
// glyph advance, and font-wide metric against
// `apps/feldexa_app/assets/fonts/metrics.json`.
//
// FR-067: German values, line breaks, and typographic punctuation must be
// renderable, so every required German codepoint must be mapped with a usable
// advance in both bundled weights.
// FR-068: Clip detection is only correct when Dart layout and the PDF renderer
// use the same advance values. The test pins point widths, rune iteration, and
// the single-line padding boundary from `contracts/export-plan.md` §3.1.
//
// Not covered here: PDFBox `getStringWidth` parity (requires the Android
// runtime), Flutter shaping/kerning, physical PDF rendering, and the T103/T108
// layout and artifact checks. Schema v1 intentionally contains no kerning or
// ligatures, so the plain advance sum is the complete contract.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:feldexa_export/feldexa_export.dart';
import 'package:flutter_test/flutter_test.dart';

const String _metricsRelativePath =
    'apps/feldexa_app/assets/fonts/metrics.json';
const String _regularAsset = 'assets/fonts/NotoSans-Regular.ttf';
const String _boldAsset = 'assets/fonts/NotoSans-Bold.ttf';
const String _metricsVersion = 'noto-sans-2.013-v1';

/// T006 pins for the bundled bytes. The generator re-hashes the TTF bytes and
/// fails closed on a mismatch; this test pins the contract value that T103/T108
/// will report in the export plan.
const Map<String, String> _pinnedSha256 = <String, String>{
  _regularAsset:
      '97eaf07030b89da4eceace86b12f4d7debb3cb212082c3938803eac7111221c9',
  _boldAsset:
      '53b53721b1910c7e058c4f012126b41273d493b04d69c1ac50924f7eff8e8039',
};

const Map<int, String> _expectedStyle = <int, String>{
  400: 'regular',
  700: 'bold',
};

const Map<int, String> _expectedAsset = <int, String>{
  400: _regularAsset,
  700: _boldAsset,
};

/// FR-067 coverage required for German form values in both weights.
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

/// Independent point widths at 10 pt for representative German form values.
///
/// The values were produced by a separate Python probe that reads `hmtx` and
/// the Unicode cmap directly from the pinned TTFs. Hard-coded literals make a
/// scaling, `unitsPerEm`, or advance regression fail even if JSON and TTF were
/// regenerated together from the same broken source.
const Map<int, Map<String, double>> _pinnedWidthsAt10Pt =
    <int, Map<String, double>>{
      400: <String, double>{
        'Müller-Lüdenscheidt': 96.54,
        'Größenänderung – 1.234,56 €': 140.01,
        'äöüßÄÖÜ € „“”–—…': 90.83,
        'Straße': 30.79,
        'Bäckerei': 40.24,
        'Schönhauser Allee 42': 100.70,
        '01.01.2026': 51.12,
        'Auftragsnummer: 1234567890': 143.61,
        'Zusammenfassung: 1.234,56 €': 143.24,
      },
      700: <String, double>{
        'Müller-Lüdenscheidt': 103.11,
        'Größenänderung – 1.234,56 €': 144.96,
        'äöüßÄÖÜ € „“”–—…': 96.83,
        'Straße': 33.45,
        'Bäckerei': 43.51,
        'Schönhauser Allee 42': 106.04,
        '01.01.2026': 51.46,
        'Auftragsnummer: 1234567890': 149.44,
        'Zusammenfassung: 1.234,56 €': 148.60,
      },
    };

/// Values that a 7–12 pt value in a scanned German form actually uses.
const List<String> _representativeGermanValues = <String>[
  'Müller-Lüdenscheidt',
  'Größenänderung – 1.234,56 €',
  'äöüßÄÖÜ € „“”–—…',
  'Straße',
  'Bäckerei',
  'Schönhauser Allee 42',
  '01.01.2026',
  'Auftragsnummer: 1234567890',
  'Zusammenfassung: 1.234,56 €',
];

late final Map<String, dynamic> _metrics;
late final Map<int, _BundledFont> _bundled;
late final Map<int, _SfntFont> _dartFonts;

void main() {
  setUpAll(() {
    final File metricsFile = File(_repoPath(_metricsRelativePath));
    if (!metricsFile.existsSync()) {
      throw StateError(
        'Metrics bundle not found at ${metricsFile.path}; run the test from '
        'the repository or set FELDEXA_REPO_ROOT.',
      );
    }
    _metrics = _object(
      jsonDecode(metricsFile.readAsStringSync()),
      'metrics.json',
    );

    final Map<String, dynamic> fonts = _object(_metrics['fonts'], 'fonts');
    expect(fonts.keys.toSet(), <String>{'400', '700'});

    _bundled = <int, _BundledFont>{};
    _dartFonts = <int, _SfntFont>{};
    for (final int weight in <int>[400, 700]) {
      final Map<String, dynamic> fontJson = _object(
        fonts['$weight'],
        'fonts.$weight',
      );
      _bundled[weight] = _BundledFont(
        weight: weight,
        json: fontJson,
        advances: _readAdvances(fontJson),
      );
      final String asset = _string(fontJson['asset'], 'fonts.$weight.asset');
      _dartFonts[weight] = _SfntFont(
        File(_repoPath(_appAssetPath(asset))).readAsBytesSync(),
      );
    }
  });

  group('bundled metrics document', () {
    test('declares schema v1 and the two bundled Noto Sans weights', () {
      expect(_metrics['schemaVersion'], 1);
      expect(_metrics['metricsVersion'], _metricsVersion);
      expect(_metrics['family'], 'NotoSans');
      expect(_metrics['fontRelease'], 'NotoSans-v2.013');
      expect(_metrics['unitsPerEm'], 1000);

      for (final int weight in <int>[400, 700]) {
        final _BundledFont font = _bundled[weight]!;
        expect(font.style, _expectedStyle[weight]);
        expect(font.weight, weight);
        expect(font.asset, _expectedAsset[weight]);
        expect(font.unitsPerEm, 1000);
        expect(font.cmapFormat, 12);
        expect(font.glyphCount, 4671);
        expect(font.numberOfHMetrics, 4665);
        expect(font.advanceWidthMax, 2840);
        expect(font.ascender, 1069);
        expect(font.descender, -293);
        expect(font.lineGap, 0);
        expect(font.advances.length, 3094);
        expect(font.codepointCount, font.advances.length);
        expect(font.firstCodepoint, 0);
        expect(font.lastCodepoint, 0x1DF1E);
      }
    });

    test('asset size and declared SHA-256 pin match the bundle contract', () {
      // The generator re-hashes the TTF bytes and fails closed (T007). This
      // export-side test pins the contract value and proves the bytes still
      // parse to the advances the table declares.
      for (final int weight in <int>[400, 700]) {
        final _BundledFont font = _bundled[weight]!;
        final File assetFile = File(_repoPath(_appAssetPath(font.asset)));
        expect(assetFile.existsSync(), isTrue, reason: font.asset);
        expect(assetFile.lengthSync(), font.byteLength);
        expect(font.sha256, _pinnedSha256[font.asset]);
      }
    });

    test('advance maps are ordered, bounded, and canonical', () {
      for (final int weight in <int>[400, 700]) {
        final _BundledFont font = _bundled[weight]!;
        final Map<String, dynamic> raw = _object(
          font.json['advances'],
          'fonts.$weight.advances',
        );
        final List<int> keys = raw.keys.map(int.parse).toList();
        final List<int> sorted = List<int>.of(keys)..sort();
        expect(keys, sorted, reason: 'advances must be in numeric order');
        expect(keys.toSet().length, keys.length, reason: 'no duplicate keys');
        expect(keys.first, font.firstCodepoint);
        expect(keys.last, font.lastCodepoint);

        for (final MapEntry<int, int> entry in font.advances.entries) {
          expect(entry.key, inInclusiveRange(0, 0x10FFFF));
          expect(entry.value, greaterThanOrEqualTo(0));
          expect(entry.value, lessThanOrEqualTo(font.advanceWidthMax));
        }
      }
    });

    test('regular and bold expose identical glyph coverage', () {
      expect(
        _bundled[400]!.advances.keys.toSet(),
        _bundled[700]!.advances.keys.toSet(),
      );
    });
  });

  group('Dart advances and glyph coverage', () {
    test('Dart cmap coverage equals the bundled advance keys', () {
      for (final int weight in <int>[400, 700]) {
        final _BundledFont bundled = _bundled[weight]!;
        final _SfntFont dart = _dartFonts[weight]!;
        final Map<int, int> dartAdvances = dart.advances;
        expect(dart.cmapFormat, bundled.cmapFormat);
        expect(dartAdvances.length, bundled.advances.length);
        expect(
          dartAdvances.keys.toSet(),
          bundled.advances.keys.toSet(),
          reason: 'coverage differs for weight $weight',
        );
        expect(dartAdvances.keys.first, bundled.firstCodepoint);
        expect(dartAdvances.keys.last, bundled.lastCodepoint);
      }
    });

    test('every bundled advance equals the Dart hmtx advance', () {
      for (final int weight in <int>[400, 700]) {
        final Map<int, int> bundled = _bundled[weight]!.advances;
        final Map<int, int> dart = _dartFonts[weight]!.advances;
        final List<String> mismatches = <String>[];
        for (final int codepoint in dart.keys) {
          if (bundled[codepoint] != dart[codepoint]) {
            mismatches.add(
              'U+${codepoint.toRadixString(16).toUpperCase().padLeft(4, '0')}: '
              'bundled=${bundled[codepoint]} dart=${dart[codepoint]}',
            );
          }
        }
        expect(mismatches, isEmpty, reason: 'weight $weight');
      }
    });

    test('Dart font-wide metrics match the bundled header values', () {
      for (final int weight in <int>[400, 700]) {
        final _BundledFont bundled = _bundled[weight]!;
        final _SfntFont dart = _dartFonts[weight]!;
        expect(dart.unitsPerEm, bundled.unitsPerEm);
        expect(dart.glyphCount, bundled.glyphCount);
        expect(dart.numberOfHMetrics, bundled.numberOfHMetrics);
        expect(dart.advanceWidthMax, bundled.advanceWidthMax);
        expect(dart.ascender, bundled.ascender);
        expect(dart.descender, bundled.descender);
        expect(dart.lineGap, bundled.lineGap);
        expect(dart.typoAscender, bundled.typoAscender);
        expect(dart.typoDescender, bundled.typoDescender);
        expect(dart.typoLineGap, bundled.typoLineGap);
        expect(dart.winAscent, bundled.winAscent);
        expect(dart.winDescent, bundled.winDescent);
        expect(dart.xHeight, bundled.xHeight);
        expect(dart.capHeight, bundled.capHeight);
        expect(dart.weightClass, weight);
      }
    });
  });

  group('FR-067 German typography', () {
    test('required German codepoints have positive advances', () {
      for (final int weight in <int>[400, 700]) {
        final Map<int, int> advances = _bundled[weight]!.advances;
        for (final MapEntry<String, int> required
            in _requiredCodepoints.entries) {
          final int? advance = advances[required.value];
          expect(
            advance,
            isNotNull,
            reason: '${required.key} missing from weight $weight',
          );
          expect(
            advance,
            greaterThan(0),
            reason: '${required.key} must not be zero-width',
          );
        }
      }
    });

    test('representative German values are fully renderable', () {
      for (final int weight in <int>[400, 700]) {
        final Map<int, int> advances = _bundled[weight]!.advances;
        for (final String value in _representativeGermanValues) {
          final List<int> missing = <int>[
            for (final int rune in value.runes)
              if (!advances.containsKey(rune)) rune,
          ];
          expect(
            missing,
            isEmpty,
            reason: 'weight $weight cannot render "$value"',
          );
          expect(
            _measure(advances, 1000, value, 9.7, weight: weight),
            greaterThan(0),
          );
        }
      }
    });

    test('point widths match independent pinned values at 7/10/12 pt', () {
      for (final int weight in <int>[400, 700]) {
        final Map<int, int> advances = _bundled[weight]!.advances;
        final Map<String, double> pinned = _pinnedWidthsAt10Pt[weight]!;
        for (final MapEntry<String, double> sample in pinned.entries) {
          final double at10 = _measure(
            advances,
            1000,
            sample.key,
            10,
            weight: weight,
          );
          expect(at10, closeTo(sample.value, 1e-9), reason: sample.key);
          expect(
            _measure(advances, 1000, sample.key, 7, weight: weight),
            closeTo(sample.value * 0.7, 1e-9),
          );
          expect(
            _measure(advances, 1000, sample.key, 12, weight: weight),
            closeTo(sample.value * 1.2, 1e-9),
          );
        }
      }
    });

    test('200 deterministic sample strings agree with the bundled table', () {
      final List<String> samples = _sampleStrings(200);
      expect(samples.length, 200);
      expect(samples.toSet().length, greaterThan(150));

      for (final int weight in <int>[400, 700]) {
        final Map<int, int> bundled = _bundled[weight]!.advances;
        final Map<int, int> dart = _dartFonts[weight]!.advances;
        for (final String sample in samples) {
          for (final double size in <double>[7, 9.7, 12]) {
            final double bundledWidth = _measure(
              bundled,
              1000,
              sample,
              size,
              weight: weight,
            );
            final double dartWidth = _measure(
              dart,
              1000,
              sample,
              size,
              weight: weight,
            );
            expect(bundledWidth, dartWidth, reason: sample);
            expect(bundledWidth.isFinite, isTrue);
            expect(bundledWidth, greaterThanOrEqualTo(0));
          }
        }
      }
    });

    test('zero-advance combining marks stay covered without width', () {
      for (final int weight in <int>[400, 700]) {
        final _BundledFont bundled = _bundled[weight]!;
        // U+0301 COMBINING ACUTE ACCENT is a real mapped glyph with advance 0.
        expect(bundled.advances[0x0301], 0);
        expect(_dartFonts[weight]!.cmap.containsKey(0x0301), isTrue);
        expect(
          _measure(bundled.advances, 1000, 'A\u0301', 10, weight: weight),
          _measure(bundled.advances, 1000, 'A', 10, weight: weight),
        );
      }
    });

    test('measurement iterates runes, including non-BMP codepoints', () {
      // U+10780 is mapped by the bundled font but needs two UTF-16 code units.
      const int nonBmp = 0x10780;
      final String text = String.fromCharCode(nonBmp);
      expect(text.length, 2);
      expect(text.runes.length, 1);
      for (final int weight in <int>[400, 700]) {
        final int advance = _bundled[weight]!.advances[nonBmp]!;
        expect(
          _measure(_bundled[weight]!.advances, 1000, text, 10, weight: weight),
          advance * 10 / 1000,
        );
      }
    });
  });

  group('FR-068 clip detection', () {
    test('single-line padding boundary honors the 1.5 pt inset', () {
      for (final int weight in <int>[400, 700]) {
        final Map<int, int> advances = _bundled[weight]!.advances;
        final double widthAt10 = _measure(
          advances,
          1000,
          'M',
          10,
          weight: weight,
        );
        final double rectForWidth = widthAt10 + 3.0;
        expect(
          _overflows(advances, 'M', rectForWidth + 0.001, 10, weight: weight),
          isFalse,
        );
        expect(
          _overflows(advances, 'M', rectForWidth - 0.001, 10, weight: weight),
          isTrue,
        );
      }
    });

    test('long German value is clipped while the wider field fits', () {
      for (final int weight in <int>[400, 700]) {
        final Map<int, int> advances = _bundled[weight]!.advances;
        const String value = 'Größenänderung – 1.234,56 €';
        final double widthAt7 = _measure(
          advances,
          1000,
          value,
          7,
          weight: weight,
        );
        expect(
          _overflows(advances, value, widthAt7 + 3.0 - 0.01, 7, weight: weight),
          isTrue,
        );
        expect(
          _overflows(advances, value, widthAt7 + 3.0 + 0.01, 7, weight: weight),
          isFalse,
        );
      }
    });

    test('unrenderable characters fail as coverage, not zero width', () {
      for (final int weight in <int>[400, 700]) {
        final Map<int, int> advances = _bundled[weight]!.advances;
        expect(advances.containsKey(0x1F600), isFalse);
        expect(
          () => _measure(advances, 1000, 'A\u{1F600}B', 10, weight: weight),
          throwsA(
            isA<_MissingGlyphException>().having(
              (_MissingGlyphException error) => error.codepoints,
              'codepoints',
              <int>[0x1F600],
            ),
          ),
        );
      }
    });
  });

  group('ExportFont contract', () {
    test('the bundled identity satisfies the ExportFont contract', () {
      final ExportFont font = ExportFont(
        family: _string(_metrics['family'], 'family'),
        regularAsset: _bundled[400]!.asset,
        boldAsset: _bundled[700]!.asset,
        metricsVersion: _string(_metrics['metricsVersion'], 'metricsVersion'),
      );

      expect(font.toJson(), <String, Object?>{
        'family': 'NotoSans',
        'regularAsset': _regularAsset,
        'boldAsset': _boldAsset,
        'metricsVersion': _metricsVersion,
      });
      expect(ExportFont.fromJson(font.toJson()), font);
    });
  });
}

/// Bundled `metrics.json` entry plus its decoded advance table.
final class _BundledFont {
  const _BundledFont({
    required this.weight,
    required this.json,
    required this.advances,
  });

  final int weight;
  final Map<String, dynamic> json;
  final Map<int, int> advances;

  String get style => _string(json['style'], 'style');
  String get asset => _string(json['asset'], 'asset');
  String get sha256 => _string(json['sha256'], 'sha256');
  int get byteLength => _int(json['bytes'], 'bytes');
  int get unitsPerEm => _int(json['unitsPerEm'], 'unitsPerEm');
  int get glyphCount => _int(json['glyphCount'], 'glyphCount');
  int get numberOfHMetrics =>
      _int(json['numberOfHMetrics'], 'numberOfHMetrics');
  int get advanceWidthMax => _int(json['advanceWidthMax'], 'advanceWidthMax');
  int get ascender => _int(json['ascender'], 'ascender');
  int get descender => _int(json['descender'], 'descender');
  int get lineGap => _int(json['lineGap'], 'lineGap');
  int? get typoAscender => _nullableInt(json['typoAscender']);
  int? get typoDescender => _nullableInt(json['typoDescender']);
  int? get typoLineGap => _nullableInt(json['typoLineGap']);
  int? get winAscent => _nullableInt(json['winAscent']);
  int? get winDescent => _nullableInt(json['winDescent']);
  int? get xHeight => _nullableInt(json['xHeight']);
  int? get capHeight => _nullableInt(json['capHeight']);
  int get cmapFormat => _int(json['cmapFormat'], 'cmapFormat');
  int get codepointCount => _int(json['codepointCount'], 'codepointCount');
  int get firstCodepoint => _int(json['firstCodepoint'], 'firstCodepoint');
  int get lastCodepoint => _int(json['lastCodepoint'], 'lastCodepoint');
}

/// Thrown when a value contains a codepoint the bundled font does not map.
///
/// `EXP-004` is a blocking coverage failure; treating a missing key as a zero
/// advance would silently produce a blank glyph instead.
final class _MissingGlyphException implements Exception {
  const _MissingGlyphException(this.codepoints, this.weight);

  final List<int> codepoints;
  final int weight;

  @override
  String toString() {
    final String formatted = codepoints
        .map((int value) => 'U+${value.toRadixString(16).toUpperCase()}')
        .join(', ');
    return 'MissingGlyphException(weight $weight: $formatted)';
  }
}

double _measure(
  Map<int, int> advances,
  int unitsPerEm,
  String text,
  double fontSizePt, {
  required int weight,
}) {
  final List<int> missing = <int>[
    for (final int rune in text.runes)
      if (!advances.containsKey(rune)) rune,
  ];
  if (missing.isNotEmpty) {
    throw _MissingGlyphException(missing, weight);
  }
  int units = 0;
  for (final int rune in text.runes) {
    units += advances[rune]!;
  }
  return units * fontSizePt / unitsPerEm;
}

bool _overflows(
  Map<int, int> advances,
  String text,
  double rectWidth,
  double fontSizePt, {
  required int weight,
}) {
  // contracts/export-plan.md §3.1: 1.5 pt padding on all sides.
  final double availableWidth = rectWidth - 3.0;
  return _measure(advances, 1000, text, fontSizePt, weight: weight) >
      availableWidth;
}

List<String> _sampleStrings(int count) {
  const String alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzÄÖÜäöüß'
      '0123456789 .,:;/-€„“”–—…()';
  final List<int> runes = alphabet.runes.toList();
  final Random random = Random(30030);
  final List<String> samples = <String>[];
  for (int index = 0; index < count; index++) {
    final int length = 1 + random.nextInt(120);
    final StringBuffer buffer = StringBuffer();
    for (int position = 0; position < length; position++) {
      buffer.writeCharCode(runes[random.nextInt(runes.length)]);
    }
    samples.add(buffer.toString());
  }
  return samples;
}

Map<int, int> _readAdvances(Map<String, dynamic> fontJson) {
  final Map<String, dynamic> raw = _object(fontJson['advances'], 'advances');
  return Map<int, int>.unmodifiable(<int, int>{
    for (final MapEntry<String, dynamic> entry in raw.entries)
      int.parse(entry.key): _int(entry.value, 'advance ${entry.key}'),
  });
}

String _appAssetPath(String bundleAsset) {
  // The contract names Flutter bundle paths (`assets/fonts/...`), but the
  // files live under the app package so Flutter can bundle them.
  return bundleAsset.startsWith('assets/')
      ? 'apps/feldexa_app/$bundleAsset'
      : bundleAsset;
}

String _repoPath(String relativePath) {
  final String? configured = Platform.environment['FELDEXA_REPO_ROOT'];
  final List<String> starts = <String>[
    if (configured != null && configured.isNotEmpty) configured,
    Directory.current.absolute.path,
  ];
  for (final String start in starts) {
    Directory directory = Directory(start).absolute;
    while (true) {
      final File candidate = File('${directory.path}/$relativePath');
      if (candidate.existsSync()) {
        return candidate.path;
      }
      final Directory parent = directory.parent;
      if (parent.path == directory.path) {
        break;
      }
      directory = parent;
    }
  }
  throw StateError(
    'Cannot locate $relativePath from ${starts.join(', ')}; run the test from '
    'the repository or set FELDEXA_REPO_ROOT.',
  );
}

Map<String, dynamic> _object(Object? value, String context) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  throw StateError('$context must be a JSON object, got ${value.runtimeType}');
}

int _int(Object? value, String context) {
  if (value is int) {
    return value;
  }
  throw StateError('$context must be an int, got ${value.runtimeType}');
}

int? _nullableInt(Object? value) {
  return value == null ? null : _int(value, 'value');
}

String _string(Object? value, String context) {
  if (value is String) {
    return value;
  }
  throw StateError('$context must be a String, got ${value.runtimeType}');
}

final class _Table {
  const _Table(this.offset, this.length);

  final int offset;
  final int length;
}

/// Minimal, dependency-free static TrueType reader used as the independent
/// Dart side of the advance and coverage comparison.
///
/// It reads only `head`, `hhea`, `maxp`, `hmtx`, `cmap`, and `OS/2`, and it
/// fails closed on malformed offsets rather than falling back to zero widths.
final class _SfntFont {
  _SfntFont(this.bytes) : _data = ByteData.sublistView(bytes) {
    final int version = _u32(0);
    if (version != 0x00010000) {
      throw StateError(
        'expected static TrueType sfnt, got 0x${version.toRadixString(16)}',
      );
    }
    final int tableCount = _u16(4);
    for (int index = 0; index < tableCount; index++) {
      final int base = 12 + index * 16;
      final String tag = String.fromCharCodes(bytes.sublist(base, base + 4));
      final int offset = _u32(base + 8);
      final int length = _u32(base + 12);
      if (offset + length > bytes.length) {
        throw StateError('table "$tag" extends past the font end');
      }
      _tables[tag] = _Table(offset, length);
    }
  }

  final Uint8List bytes;
  final ByteData _data;
  final Map<String, _Table> _tables = <String, _Table>{};

  late final Map<int, int> cmap = _readCmapFormat12();
  late final Map<int, int> advances = <int, int>{
    for (final MapEntry<int, int> entry in cmap.entries)
      entry.key: advanceForGlyph(entry.value),
  };

  int get unitsPerEm => _u16(_table('head').offset + 18);

  int get glyphCount => _u16(_table('maxp').offset + 4);

  int get numberOfHMetrics => _u16(_table('hhea').offset + 34);

  int get advanceWidthMax => _u16(_table('hhea').offset + 10);

  int get ascender => _s16(_table('hhea').offset + 4);

  int get descender => _s16(_table('hhea').offset + 6);

  int get lineGap => _s16(_table('hhea').offset + 8);

  int get cmapFormat => 12;

  int get weightClass => _u16(_table('OS/2').offset + 4);

  int? get typoAscender => _os2Signed(68);

  int? get typoDescender => _os2Signed(70);

  int? get typoLineGap => _os2Signed(72);

  int? get winAscent => _os2Unsigned(74);

  int? get winDescent => _os2Unsigned(76);

  int? get xHeight {
    final _Table table = _table('OS/2');
    if (table.length < 90 || _u16(table.offset) < 2) {
      return null;
    }
    return _s16(table.offset + 86);
  }

  int? get capHeight {
    final _Table table = _table('OS/2');
    if (table.length < 90 || _u16(table.offset) < 2) {
      return null;
    }
    return _s16(table.offset + 88);
  }

  int advanceForGlyph(int glyph) {
    if (glyph < 0 || glyph >= glyphCount) {
      throw StateError('glyph $glyph is outside 0..$glyphCount');
    }
    final _Table hmtx = _table('hmtx');
    final int required =
        numberOfHMetrics * 4 + (glyphCount - numberOfHMetrics) * 2;
    if (hmtx.length < required) {
      throw StateError('hmtx table is shorter than $required bytes');
    }
    if (glyph < numberOfHMetrics) {
      return _u16(hmtx.offset + glyph * 4);
    }
    return _u16(hmtx.offset + (numberOfHMetrics - 1) * 4);
  }

  int? _os2Signed(int offset) {
    final _Table table = _table('OS/2');
    if (table.length < offset + 2) {
      return null;
    }
    return _s16(table.offset + offset);
  }

  int? _os2Unsigned(int offset) {
    final _Table table = _table('OS/2');
    if (table.length < offset + 2) {
      return null;
    }
    return _u16(table.offset + offset);
  }

  Map<int, int> _readCmapFormat12() {
    final _Table cmapTable = _table('cmap');
    final int count = _u16(cmapTable.offset + 2);
    for (int index = 0; index < count; index++) {
      final int record = cmapTable.offset + 4 + index * 8;
      final int platform = _u16(record);
      final int encoding = _u16(record + 2);
      final bool unicode =
          platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10));
      if (!unicode) {
        continue;
      }
      final int offset = _u32(record + 4);
      if (offset + 2 > cmapTable.length) {
        throw StateError('cmap subtable $index is outside the table');
      }
      final int subtable = cmapTable.offset + offset;
      if (_u16(subtable) != 12) {
        continue;
      }
      final int length = _u32(subtable + 4);
      if (length < 16 ||
          subtable + length > cmapTable.offset + cmapTable.length) {
        throw StateError('cmap format 12 subtable is out of bounds');
      }
      final int groups = _u32(subtable + 12);
      final Map<int, int> glyphs = <int, int>{};
      for (int group = 0; group < groups; group++) {
        final int base = subtable + 16 + group * 12;
        final int start = _u32(base);
        final int end = _u32(base + 4);
        final int startGlyph = _u32(base + 8);
        if (start > end || end > 0x10FFFF) {
          throw StateError('invalid cmap group $group');
        }
        if (startGlyph + (end - start) >= glyphCount) {
          throw StateError('cmap group $group maps past the glyph count');
        }
        for (int codepoint = start; codepoint <= end; codepoint++) {
          glyphs[codepoint] = startGlyph + (codepoint - start);
        }
      }
      return glyphs;
    }
    throw StateError('no Unicode cmap format 12 subtable');
  }

  _Table _table(String tag) {
    final _Table? table = _tables[tag];
    if (table == null) {
      throw StateError('missing required font table "$tag"');
    }
    return table;
  }

  int _u16(int offset) {
    if (offset < 0 || offset + 2 > bytes.length) {
      throw StateError('truncated u16 read at $offset');
    }
    return _data.getUint16(offset, Endian.big);
  }

  int _s16(int offset) {
    if (offset < 0 || offset + 2 > bytes.length) {
      throw StateError('truncated s16 read at $offset');
    }
    return _data.getInt16(offset, Endian.big);
  }

  int _u32(int offset) {
    if (offset < 0 || offset + 4 > bytes.length) {
      throw StateError('truncated u32 read at $offset');
    }
    return _data.getUint32(offset, Endian.big);
  }
}
