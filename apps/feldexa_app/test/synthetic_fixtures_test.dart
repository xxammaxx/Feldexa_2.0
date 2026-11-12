// T009 fixture-integrity test.
//
// Proves that the committed synthetic fixture catalogue is complete,
// internally consistent, byte-identical to its Android/corpus copies, and
// free of third-party or personal content. It also proves the expected OCR
// and ground truth agree with the PDF page geometry.
//
// The test reads the canonical files, the Web delivery mirror, and the
// Android/corpus copies from the checkout. It deliberately re-implements
// SHA-256 in `test/support/sha256_reference.dart` instead of importing the
// generator, so a generator hashing bug cannot validate itself.
//
// This is a static/host check. The fixtures are SIMULATED development inputs;
// the test produces no SIMULATED, EMULATOR, or DEVICE runtime evidence and
// makes no Android claim (FR-086, FR-088).

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'support/sha256_reference.dart';

const String _canonicalFixtureDirectory = 'apps/feldexa_app/assets/fixtures';
const String _webFixtureDirectory = 'apps/feldexa_app/web/fixtures';
const String _corpusFixtureDirectory = 'tools/corpus/synthetic';
const String _pubspecPath = 'apps/feldexa_app/pubspec.yaml';
const Set<String> _fieldTypes = <String>{
  'text',
  'number',
  'date',
  'checkbox',
  'multiline',
  'signature',
};
const Set<String> _roles = <String>{
  'editor',
  'navigation',
  'geometry',
  'fields',
  'import-failure',
};

late Map<String, dynamic> _catalog;
late List<Map<String, dynamic>> _fixtures;
late Map<String, Map<String, dynamic>> _ocr;
late Map<String, Uint8List> _pdfBytes;
late Directory _repositoryRoot;

Map<String, dynamic> _map(Object? value) {
  return (value as Map<Object?, Object?>).cast<String, dynamic>();
}

List<dynamic> _list(Object? value) {
  return value as List<dynamic>;
}

Uint8List _readBytes(String repositoryRelativePath) {
  return File('${_repositoryRoot.path}/$repositoryRelativePath')
      .readAsBytesSync();
}

Map<String, dynamic> _readJson(String repositoryRelativePath) {
  return _map(
    jsonDecode(
      File('${_repositoryRoot.path}/$repositoryRelativePath')
          .readAsStringSync(),
    ),
  );
}

String _pdfText(Uint8List bytes) {
  // The unencrypted fixtures are deliberately ASCII; the protected fixture's
  // encrypted streams are still safe to inspect with a Latin-1 view because
  // its dictionaries remain plaintext.
  return latin1.decode(bytes);
}

bool _insidePage(Map<String, dynamic> rect, Map<String, dynamic> page) {
  final double x = (rect['x'] as num).toDouble();
  final double y = (rect['y'] as num).toDouble();
  final double width = (rect['width'] as num).toDouble();
  final double height = (rect['height'] as num).toDouble();
  final double pageWidth = (page['widthPt'] as num).toDouble();
  final double pageHeight = (page['heightPt'] as num).toDouble();
  return x >= 0 &&
      y >= 0 &&
      width > 0 &&
      height > 0 &&
      x + width <= pageWidth + 0.01 &&
      y + height <= pageHeight + 0.01;
}

bool _insideManifestRect(Map<String, dynamic> rect, Map<String, dynamic> page) {
  final double x = (rect['xPt'] as num).toDouble();
  final double y = (rect['yPt'] as num).toDouble();
  final double width = (rect['widthPt'] as num).toDouble();
  final double height = (rect['heightPt'] as num).toDouble();
  final double pageWidth = (page['widthPt'] as num).toDouble();
  final double pageHeight = (page['heightPt'] as num).toDouble();
  return x >= 0 &&
      y >= 0 &&
      width > 0 &&
      height > 0 &&
      x + width <= pageWidth + 0.01 &&
      y + height <= pageHeight + 0.01;
}

int _roundEighth(double value) => (value * 8).round();

void main() {
  _repositoryRoot = Directory.current.parent.parent;

  // Test registration happens synchronously before `setUpAll`. Read the
  // canonical catalogue from the checkout to declare one test per fixture.
  _catalog = _readJson('$_canonicalFixtureDirectory/catalog.json');
  _fixtures = _list(_catalog['fixtures'])
      .map((dynamic value) => _map(value))
      .toList(growable: false);

  setUpAll(() async {
    expect(
      File('${_repositoryRoot.path}/pubspec.yaml').readAsStringSync(),
      contains('feldexa_workspace'),
      reason: 'test must run from apps/feldexa_app inside the monorepo',
    );

    _ocr = <String, Map<String, dynamic>>{};
    _pdfBytes = <String, Uint8List>{};
    for (final Map<String, dynamic> fixture in _fixtures) {
      final String id = fixture['id'] as String;
      _pdfBytes[id] = _readBytes('$_canonicalFixtureDirectory/$id.pdf');
      final Map<String, dynamic>? expectedOcr = fixture['expectedOcr'] == null
          ? null
          : _map(fixture['expectedOcr']);
      if (expectedOcr != null) {
        _ocr[id] = _readJson(
          '$_canonicalFixtureDirectory/${expectedOcr['path'] as String}',
        );
      }
    }
  });

  group('catalog and provenance', () {
    test('catalog is a SIMULATED, deterministic fixture catalogue', () {
      expect(_catalog['schemaVersion'], 1);
      expect(
        _catalog['catalogVersion'],
        matches(RegExp(r'^fixtures-\d+\.\d+\.\d+$')),
      );
      expect(_catalog['evidenceClass'], 'simulated');

      final Map<String, dynamic> generator = _map(_catalog['generator']);
      expect(generator['path'], 'tools/corpus/synthetic/generate.dart');
      expect(generator['seed'], 0);
      expect(generator['deterministic'], isTrue);
      expect(
        generator['checkCommand'],
        'dart run tools/corpus/synthetic/generate.dart --check',
      );

      final Map<String, dynamic> rights = _map(_catalog['rights']);
      expect(rights['kind'], 'synthetic');
      expect(rights['thirdPartyContent'], isFalse);
      expect(rights['containsPersonalData'], isFalse);
      expect(rights['rightsCleared'], isTrue);
      expect(rights['legalBasis'], contains('synthetic'));
      expect(_catalog['description'], contains('not evidence about Android'));

      final Map<String, dynamic> delivery = _map(_catalog['delivery']);
      expect(delivery['canonicalDevDirectory'], _canonicalFixtureDirectory);
      expect(delivery['webDirectory'], _webFixtureDirectory);
      expect(delivery['corpusDirectory'], _corpusFixtureDirectory);
      expect(delivery['flutterAssetsDeclared'], isFalse);
      expect(delivery['webBaseUrl'], '/fixtures');
      expect(delivery['androidRelease'], contains('never packaged'));
    });

    test(
      'catalogue contains the four editor forms and three failure fixtures',
      () {
        final Set<String> ids = _fixtures
            .map((Map<String, dynamic> fixture) => fixture['id'] as String)
            .toSet();
        expect(
          ids,
          containsAll(<String>[
            'sf-001',
            'sf-002',
            'sf-003',
            'sf-004',
            'sf-protected',
            'sf-truncated',
            'sf-not-a-pdf',
          ]),
        );
        expect(_catalog['fixtureCount'], _fixtures.length);
        final Set<String> roles = _fixtures
            .map((Map<String, dynamic> fixture) => fixture['role'] as String)
            .toSet();
        expect(roles.difference(_roles), isEmpty);
      },
    );

    for (final Map<String, dynamic> fixture in _fixtures) {
      test('${fixture['id']} carries complete synthetic provenance', () {
        expect(fixture['kind'], 'synthetic');
        expect(fixture['title'], isNotEmpty);
        expect(fixture['description'], isNotEmpty);
        expect(fixture['strata'], isNotEmpty);

        final Map<String, dynamic> provenance = _map(fixture['provenance']);
        expect(provenance['source'], contains('Generated by'));
        expect(provenance['retrievalDate'], '2026-11-12');
        expect(provenance['legalBasis'], contains('synthetic'));
        expect(provenance['rightsCleared'], isTrue);
        expect(provenance['containsPersonalData'], isFalse);
        expect(provenance['rightsReference'], contains('Principle VI'));

        final Map<String, dynamic> synthetic = _map(fixture['synthetic']);
        expect(synthetic['generator'], 'tools/corpus/synthetic/generate.dart');
        expect(synthetic['seed'], 0);
      });
    }
  });

  group('valid fixtures', () {
    final List<Map<String, dynamic>> valid = _fixtures
        .where((Map<String, dynamic> fixture) => fixture['status'] == 'valid')
        .toList(growable: false);

    test(
      'four valid forms cover every field type, rotation, and page-count need',
      () {
        expect(valid.length, 4);
        expect(
          valid.map((Map<String, dynamic> f) => f['role'] as String).toSet(),
          <String>{'editor', 'navigation', 'geometry', 'fields'},
        );

        final Set<String> types = <String>{};
        final Set<int> rotations = <int>{};
        final Set<String> sizes = <String>{};
        int maxPages = 0;
        for (final Map<String, dynamic> fixture in valid) {
          for (final dynamic pageValue in _list(fixture['pages'])) {
            final Map<String, dynamic> page = _map(pageValue);
            rotations.add((page['rotation'] as num).toInt());
            sizes.add('${page['widthPt']}x${page['heightPt']}');
          }
          maxPages = (fixture['pageCount'] as int) > maxPages
              ? fixture['pageCount'] as int
              : maxPages;
          final Map<String, dynamic> groundTruth = _map(fixture['groundTruth']);
          for (final dynamic fieldValue in _list(groundTruth['fields'])) {
            types.add(_map(fieldValue)['type'] as String);
          }
        }
        expect(types, _fieldTypes);
        expect(rotations, containsAll(<int>[0, 90, 180, 270]));
        expect(sizes.length, greaterThanOrEqualTo(3));
        expect(maxPages, greaterThanOrEqualTo(5));
        expect(
          valid.map((Map<String, dynamic> f) => f['pageCount'] as int),
          contains(2),
        );
      },
    );

    for (final Map<String, dynamic> fixture in valid) {
      final String id = fixture['id'] as String;

      test('$id PDF bytes, page geometry, and fixed metadata are valid', () {
        final Uint8List bytes = _pdfBytes[id]!;
        expect(bytes.length, fixture['sizeBytes']);
        expect(referenceSha256(bytes), fixture['sha256']);
        expect(bytes.length, greaterThan(1000));

        final String text = _pdfText(bytes);
        expect(text.startsWith('%PDF-1.7'), isTrue);
        expect(text.trimRight().endsWith('%%EOF'), isTrue);
        expect(text, contains('%FELDEXA-SYNTHETIC-FIXTURE'));
        expect(
          text,
          contains(
            '/ID [<46454C44455841464958545552453031> '
            '<46454C44455841464958545552453031>]',
          ),
        );
        expect(text, isNot(contains('/CreationDate')));
        expect(text, isNot(contains('/ModDate')));
        expect(text, isNot(contains('/Producer')));
        expect(text, isNot(contains('/Creator')));

        final RegExp pageMarker = RegExp(r'/Type\s*/Page\b');
        final int pdfPageCount = pageMarker.allMatches(text).length;
        expect(pdfPageCount, fixture['pageCount']);

        final List<dynamic> pages = _list(fixture['pages']);
        expect(pages.length, fixture['pageCount']);
        final List<RegExpMatch> boxes = RegExp(
          r'/MediaBox \[0 0 ([\d.]+) ([\d.]+)\]',
        ).allMatches(text).toList();
        expect(boxes.length, pages.length);
        for (int index = 0; index < pages.length; index++) {
          final Map<String, dynamic> page = _map(pages[index]);
          final double mediaWidth = double.parse(boxes[index].group(1)!);
          final double mediaHeight = double.parse(boxes[index].group(2)!);
          final double displayWidth = (page['widthPt'] as num).toDouble();
          final double displayHeight = (page['heightPt'] as num).toDouble();
          final int rotation = (page['rotation'] as num).toInt();
          if (rotation == 90 || rotation == 270) {
            expect(displayWidth, closeTo(mediaHeight, 0.01));
            expect(displayHeight, closeTo(mediaWidth, 0.01));
          } else {
            expect(displayWidth, closeTo(mediaWidth, 0.01));
            expect(displayHeight, closeTo(mediaHeight, 0.01));
          }
          expect(text, contains('/Rotate $rotation'));
        }
      });

      test('$id ground truth is unique, typed, and inside page bounds', () {
        final Map<String, dynamic> groundTruth = _map(fixture['groundTruth']);
        final List<dynamic> fields = _list(groundTruth['fields']);
        expect(fields, isNotEmpty);
        final Set<String> ids = <String>{};
        final List<dynamic> pages = _list(fixture['pages']);
        for (final dynamic fieldValue in fields) {
          final Map<String, dynamic> field = _map(fieldValue);
          final String fieldId = field['id'] as String;
          expect(ids.add(fieldId), isTrue, reason: 'duplicate GT id $fieldId');
          expect(_fieldTypes, contains(field['type']));
          expect(field['label'], isNotEmpty);
          final int pageIndex = field['pageIndex'] as int;
          expect(pageIndex, inInclusiveRange(0, pages.length - 1));
          final Map<String, dynamic> page = _map(pages[pageIndex]);
          expect(
            _insideManifestRect(_map(field['rect']), page),
            isTrue,
            reason: '$fieldId is outside page $pageIndex',
          );
        }
      });

      test('$id expected OCR is sorted, bounded, and matches assertions', () {
        final Map<String, dynamic> expectedOcr = _map(fixture['expectedOcr']);
        final Map<String, dynamic> ocr = _ocr[id]!;
        expect(ocr['schemaVersion'], 1);
        expect(ocr['fixtureId'], id);
        expect(ocr['language'], 'de');
        expect(ocr['evidenceClass'], 'simulated');
        expect(ocr['generatorVersion'], _map(_catalog['generator'])['version']);

        final List<dynamic> ocrPages = _list(ocr['pages']);
        final List<dynamic> pages = _list(fixture['pages']);
        expect(ocrPages.length, pages.length);
        expect(expectedOcr['pageCount'], pages.length);
        expect(expectedOcr['blockCount'], greaterThan(0));

        int blockCount = 0;
        for (int index = 0; index < ocrPages.length; index++) {
          final Map<String, dynamic> ocrPage = _map(ocrPages[index]);
          final Map<String, dynamic> page = _map(pages[index]);
          expect(ocrPage['pageIndex'], index);
          expect(
            (ocrPage['widthPt'] as num).toDouble(),
            closeTo((page['widthPt'] as num).toDouble(), 0.01),
          );
          expect(
            (ocrPage['heightPt'] as num).toDouble(),
            closeTo((page['heightPt'] as num).toDouble(), 0.01),
          );
          expect(ocrPage['rotation'], page['rotation']);

          final List<dynamic> blocks = _list(ocrPage['blocks']);
          expect(blocks, isNotEmpty);
          blockCount += blocks.length;
          int previousTop = -1;
          int previousLeft = -1;
          for (final dynamic blockValue in blocks) {
            final Map<String, dynamic> block = _map(blockValue);
            expect(block['text'], isNotEmpty);
            final double confidence = (block['confidence'] as num).toDouble();
            expect(confidence, inInclusiveRange(0, 1));
            final Map<String, dynamic> rect = _map(block['rect']);
            expect(
              _insidePage(rect, ocrPage),
              isTrue,
              reason: 'OCR block overflow',
            );

            final int top = _roundEighth((rect['y'] as num).toDouble());
            final int left = _roundEighth((rect['x'] as num).toDouble());
            expect(
              top > previousTop || (top == previousTop && left >= previousLeft),
              isTrue,
              reason: 'OCR blocks are not sorted at page $index',
            );
            previousTop = top;
            previousLeft = left;

            final List<dynamic> lines = _list(block['lines']);
            expect(lines, hasLength(1));
            expect(_map(lines.single)['text'], block['text']);
          }
        }
        expect(blockCount, expectedOcr['blockCount']);
      });

      test('$id OCR labels support every ground-truth field', () {
        final Map<String, dynamic> ocr = _ocr[id]!;
        final List<dynamic> ocrPages = _list(ocr['pages']);
        final Map<String, dynamic> groundTruth = _map(fixture['groundTruth']);
        for (final dynamic fieldValue in _list(groundTruth['fields'])) {
          final Map<String, dynamic> field = _map(fieldValue);
          final int pageIndex = field['pageIndex'] as int;
          final String label = field['label'] as String;
          final List<dynamic> blocks = _list(
            _map(ocrPages[pageIndex])['blocks'],
          );
          final bool labelled = blocks.any((dynamic blockValue) {
            final String text = _map(blockValue)['text'] as String;
            return text == label || label.startsWith(text);
          });
          expect(labelled, isTrue, reason: 'no OCR label for ${field['id']}');
        }
      });

      test('$id canonical, Web, and corpus copies are byte-identical', () {
        final Uint8List canonical = _pdfBytes[id]!;
        expect(_readBytes('$_canonicalFixtureDirectory/$id.pdf'), canonical);
        expect(_readBytes('$_webFixtureDirectory/$id.pdf'), canonical);
        expect(_readBytes('$_corpusFixtureDirectory/$id.pdf'), canonical);
        expect(
          fixture['assetPath'],
          'apps/feldexa_app/assets/fixtures/$id.pdf',
        );
        expect(fixture['webPath'], 'apps/feldexa_app/web/fixtures/$id.pdf');
        expect(fixture['corpusPath'], 'tools/corpus/synthetic/$id.pdf');
        expect(fixture['path'], '$id.pdf');
      });
    }
  });

  group('dev-only delivery policy', () {
    test('pubspec declares fonts but never fixture assets', () {
      final String pubspec = File('${_repositoryRoot.path}/$_pubspecPath')
          .readAsStringSync();
      expect(
        RegExp(
          r'^\s+-\s+assets/fixtures/?\s*$',
          multiLine: true,
        ).hasMatch(pubspec),
        isFalse,
        reason: 'fixture assets would be packaged into Android release builds',
      );
      expect(
        RegExp(
          r'^\s+-\s+assets/fonts/metrics\.json\s*$',
          multiLine: true,
        ).hasMatch(pubspec),
        isTrue,
      );

      final Directory androidAssets = Directory(
        '${_repositoryRoot.path}/apps/feldexa_app/android/app/src/main/assets',
      );
      if (androidAssets.existsSync()) {
        expect(
          androidAssets.listSync(recursive: true).where((
            FileSystemEntity entity,
          ) {
            return entity.path.contains('/fixtures') ||
                entity.uri.pathSegments.contains('fixtures');
          }).toList(),
          isEmpty,
        );
      }
    });

    test('canonical and Web fixture trees are byte-identical', () {
      final Directory canonical = Directory(
        '${_repositoryRoot.path}/$_canonicalFixtureDirectory',
      );
      final Directory web = Directory(
        '${_repositoryRoot.path}/$_webFixtureDirectory',
      );
      expect(canonical.existsSync(), isTrue);
      expect(web.existsSync(), isTrue);

      final List<String> generatedNames =
          canonical
              .listSync()
              .whereType<File>()
              .map((File file) => file.uri.pathSegments.last)
              .where(
                (String name) =>
                    name == 'catalog.json' ||
                    name.endsWith('.pdf') ||
                    name.endsWith('.expected-ocr.json'),
              )
              .toList()
            ..sort();
      expect(generatedNames, isNotEmpty);
      final List<String> webNames =
          web
              .listSync()
              .whereType<File>()
              .map((File file) => file.uri.pathSegments.last)
              .toList()
            ..sort();
      expect(webNames, generatedNames);
      for (final String name in generatedNames) {
        expect(
          _readBytes('$_webFixtureDirectory/$name'),
          _readBytes('$_canonicalFixtureDirectory/$name'),
          reason: '$name differs between canonical and Web mirror',
        );
      }
    });

    test('the Web delivery mirror is outside Flutter asset directories', () {
      expect(
        _webFixtureDirectory.startsWith('apps/feldexa_app/assets/'),
        isFalse,
      );
      expect(_webFixtureDirectory, 'apps/feldexa_app/web/fixtures');
      for (final Map<String, dynamic> fixture in _fixtures) {
        final String webPath = fixture['webPath'] as String;
        expect(webPath, startsWith('apps/feldexa_app/web/fixtures/'));
        expect(File('${_repositoryRoot.path}/$webPath').existsSync(), isTrue);
      }
    });
  });

  group('failure fixtures', () {
    test('sf-protected is a genuine encrypted PDF for IMP-001', () {
      final Map<String, dynamic> fixture = _fixtures.firstWhere(
        (Map<String, dynamic> value) => value['id'] == 'sf-protected',
      );
      expect(fixture['status'], 'encrypted');
      expect(fixture['expectedError'], 'IMP-001');
      expect(fixture['pageCount'], 1);
      final Map<String, dynamic> encryption = _map(fixture['encryption']);
      expect(encryption['handler'], 'Standard');
      expect(encryption['version'], 1);
      expect(encryption['revision'], 2);
      expect(encryption['keyLengthBits'], 40);
      expect(encryption['userPassword'], 'feldexa-user');
      expect(encryption['ownerPassword'], 'feldexa-owner');
      expect(encryption['userPassword'], isNotEmpty);

      final Uint8List bytes = _pdfBytes['sf-protected']!;
      expect(referenceSha256(bytes), fixture['sha256']);
      final String text = _pdfText(bytes);
      expect(text, contains('/Encrypt'));
      expect(text, contains('/Filter /Standard'));
      expect(text, contains('/V 1 /R 2 /Length 40'));
      expect(text, contains('/O <'));
      expect(text, contains('/U <'));
      // The page content stream is encrypted, so the readable dictionaries
      // must not expose the fixture text.
      expect(text, isNot(contains('Geschütztes synthetisches Dokument')));
      expect(text, isNot(contains('Benutzerkennwort gesetzt')));
    });

    test('sf-truncated is a deterministic prefix without EOF for IMP-002', () {
      final Map<String, dynamic> fixture = _fixtures.firstWhere(
        (Map<String, dynamic> value) => value['id'] == 'sf-truncated',
      );
      expect(fixture['status'], 'truncated');
      expect(fixture['expectedError'], 'IMP-002');
      final Uint8List full = _pdfBytes['sf-001']!;
      final Uint8List truncated = _pdfBytes['sf-truncated']!;
      expect(truncated.length, lessThan(full.length));
      expect(truncated, full.sublist(0, truncated.length));
      expect(_pdfText(truncated), isNot(contains('%%EOF')));
      expect(latin1.decode(truncated.sublist(0, 5)), '%PDF-');

      final Map<String, dynamic> truncation = _map(fixture['truncation']);
      expect(truncation['sourceFixture'], 'sf-001');
      expect(truncation['sourceBytes'], full.length);
      expect(truncation['retainedBytes'], truncated.length);
    });

    test('sf-not-a-pdf is text with a .pdf name for IMP-004', () {
      final Map<String, dynamic> fixture = _fixtures.firstWhere(
        (Map<String, dynamic> value) => value['id'] == 'sf-not-a-pdf',
      );
      expect(fixture['status'], 'not-a-pdf');
      expect(fixture['expectedError'], 'IMP-004');
      final Uint8List bytes = _pdfBytes['sf-not-a-pdf']!;
      expect(referenceSha256(bytes), fixture['sha256']);
      expect(latin1.decode(bytes.sublist(0, 4)), isNot('%PDF'));
      final String text = utf8.decode(bytes);
      expect(text, startsWith('Dies ist keine PDF-Datei.'));
      expect(text, contains('IMP-004'));
    });
  });

  group('German content and synthetic marker', () {
    test('OCR text exercises German characters and quotation marks', () {
      final String allText = _ocr.values
          .map((Map<String, dynamic> ocr) {
            final StringBuffer buffer = StringBuffer();
            for (final dynamic pageValue in _list(ocr['pages'])) {
              for (final dynamic blockValue in _list(
                _map(pageValue)['blocks'],
              )) {
                buffer.write(_map(blockValue)['text'] as String);
                buffer.write('\n');
              }
            }
            return buffer.toString();
          })
          .join('\n');
      for (final String character in <String>[
        'ä',
        'ö',
        'ü',
        'ß',
        '€',
        '„',
        '“',
      ]) {
        expect(
          allText,
          contains(character),
          reason: 'missing German character $character',
        );
      }
      expect(allText, contains('MUSTERSTADT'));
      expect(allText, contains('SYNTHETISCHES TESTDOKUMENT'));
      expect(allText, contains('kein amtliches Formular'));
    });
  });
}
