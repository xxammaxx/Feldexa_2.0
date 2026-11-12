// T009 SIMULATED browser runtime check for the dev-only Web fixtures.
//
// This test runs in a real Chrome browser and fetches the fixture files from
// the same `/fixtures/...` URL layout the Flutter Web dev server uses. It
// proves that the Web delivery mirror is reachable, byte-deterministic, and
// consistent with the catalog and expected OCR.
//
// It is skipped unless `--dart-define=FIXTURE_RUNTIME=true` is supplied by
// `tools/corpus/synthetic/test_web_fixtures.sh`, because the normal Flutter
// browser suite has no fixture HTTP server. A skipped run is not evidence.
//
// Evidence class: SIMULATED browser runtime (fixture delivery determinism
// only). It is not an editor journey, not a real OCR run, and not Android
// acceptance evidence (FR-087, FR-088).
//
// `dart:html` is used intentionally: this file only compiles for the browser,
// and the app does not take a dependency on a web interop package.

// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

@TestOn('browser')
library;

import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'support/sha256_reference.dart';

const bool _runtimeEnabled = bool.fromEnvironment('FIXTURE_RUNTIME');
const String _baseUrl = String.fromEnvironment(
  'FIXTURE_BASE_URL',
  defaultValue: 'http://127.0.0.1:8765',
);
const String _skipReason =
    'requires the fixture server: run '
    'tools/corpus/synthetic/test_web_fixtures.sh';

Map<String, dynamic> _map(Object? value) {
  return (value as Map<Object?, Object?>).cast<String, dynamic>();
}

List<dynamic> _list(Object? value) {
  return value as List<dynamic>;
}

Future<Uint8List> _fetch(String fixturePath) async {
  final html.HttpRequest request = await html.HttpRequest.request(
    '$_baseUrl/fixtures/$fixturePath',
    method: 'GET',
    responseType: 'arraybuffer',
  );
  if (request.status != 200) {
    throw StateError('GET $fixturePath failed with HTTP ${request.status}');
  }
  final Object? response = request.response;
  if (response is ByteBuffer) {
    return response.asUint8List();
  }
  if (response is Uint8List) {
    return response;
  }
  throw StateError(
    'GET $fixturePath returned unexpected ${response.runtimeType}',
  );
}

Future<Map<String, dynamic>> _fetchJson(String fixturePath) async {
  return _map(jsonDecode(utf8.decode(await _fetch(fixturePath))));
}

String _pdfText(Uint8List bytes) => latin1.decode(bytes);

Map<String, dynamic> _fixture(Map<String, dynamic> catalog, String id) {
  return _list(catalog['fixtures'])
      .map((dynamic value) => _map(value))
      .firstWhere((Map<String, dynamic> value) => value['id'] == id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'serves the SIMULATED catalog and dev-only delivery policy in Chrome',
    () async {
      final Map<String, dynamic> catalog = await _fetchJson('catalog.json');
      expect(catalog['schemaVersion'], 1);
      expect(catalog['evidenceClass'], 'simulated');
      expect(catalog['fixtureCount'], 7);
      expect(catalog['description'], contains('not evidence about Android'));

      final Map<String, dynamic> delivery = _map(catalog['delivery']);
      expect(delivery['webBaseUrl'], '/fixtures');
      expect(delivery['flutterAssetsDeclared'], isFalse);
      expect(delivery['androidRelease'], contains('never packaged'));
    },
    skip: _runtimeEnabled ? false : _skipReason,
  );

  test(
    'serves every valid fixture with matching hashes and page geometry',
    () async {
      final Map<String, dynamic> catalog = await _fetchJson('catalog.json');
      final List<Map<String, dynamic>> valid = _list(catalog['fixtures'])
          .map((dynamic value) => _map(value))
          .where((Map<String, dynamic> fixture) => fixture['status'] == 'valid')
          .toList();
      expect(valid.length, 4);

      for (final Map<String, dynamic> fixture in valid) {
        final String id = fixture['id'] as String;
        final Uint8List bytes = await _fetch('$id.pdf');
        expect(
          referenceSha256(bytes),
          fixture['sha256'],
          reason: '$id hash differs from the catalog',
        );
        expect(bytes.length, fixture['sizeBytes']);
        final String text = _pdfText(bytes);
        expect(text.startsWith('%PDF-1.7'), isTrue);
        expect(text.trimRight().endsWith('%%EOF'), isTrue);
        expect(text, contains('%FELDEXA-SYNTHETIC-FIXTURE'));
        final int pageCount = RegExp(r'/Type\s*/Page\b')
            .allMatches(text)
            .length;
        expect(pageCount, fixture['pageCount']);

        final Uint8List again = await _fetch('$id.pdf');
        expect(
          again,
          bytes,
          reason: '$id bytes changed between two browser fetches',
        );

        final Map<String, dynamic> expectedOcr = _map(fixture['expectedOcr']);
        final Map<String, dynamic> ocr = await _fetchJson(
          expectedOcr['path'] as String,
        );
        expect(ocr['schemaVersion'], 1);
        expect(ocr['fixtureId'], id);
        expect(ocr['evidenceClass'], 'simulated');
        final List<dynamic> pages = _list(ocr['pages']);
        expect(pages.length, fixture['pageCount']);
        int blocks = 0;
        for (final dynamic pageValue in pages) {
          blocks += _list(_map(pageValue)['blocks']).length;
        }
        expect(blocks, expectedOcr['blockCount']);
      }
    },
    skip: _runtimeEnabled ? false : _skipReason,
  );

  test(
    'serves the three import-failure fixtures with their expected shapes',
    () async {
      final Map<String, dynamic> catalog = await _fetchJson('catalog.json');

      final Map<String, dynamic> protected = _fixture(catalog, 'sf-protected');
      expect(protected['expectedError'], 'IMP-001');
      final Map<String, dynamic> protectedEncryption = _map(
        protected['encryption'],
      );
      expect(protectedEncryption['userPassword'], isNotEmpty);
      expect(protectedEncryption['userPassword'], 'feldexa-user');
      final String protectedText = _pdfText(await _fetch('sf-protected.pdf'));
      expect(protectedText, contains('/Filter /Standard'));
      expect(protectedText, contains('/V 1 /R 2 /Length 40'));

      final Map<String, dynamic> truncated = _fixture(catalog, 'sf-truncated');
      expect(truncated['expectedError'], 'IMP-002');
      final Uint8List full = await _fetch('sf-001.pdf');
      final Uint8List short = await _fetch('sf-truncated.pdf');
      expect(short.length, lessThan(full.length));
      expect(short, full.sublist(0, short.length));
      expect(_pdfText(short), isNot(contains('%%EOF')));

      final Map<String, dynamic> notPdf = _fixture(catalog, 'sf-not-a-pdf');
      expect(notPdf['expectedError'], 'IMP-004');
      final String text = utf8.decode(await _fetch('sf-not-a-pdf.pdf'));
      expect(text, startsWith('Dies ist keine PDF-Datei.'));
      expect(text, contains('IMP-004'));
    },
    skip: _runtimeEnabled ? false : _skipReason,
  );

  test(
    'serves German text and OCR content deterministically in Chrome',
    () async {
      final Map<String, dynamic> catalog = await _fetchJson('catalog.json');
      final StringBuffer allText = StringBuffer();
      for (final Map<String, dynamic> fixture
          in _list(catalog['fixtures'])
              .map((dynamic value) => _map(value))
              .where(
                (Map<String, dynamic> value) => value['expectedOcr'] != null,
              )) {
        final Map<String, dynamic> expectedOcr = _map(fixture['expectedOcr']);
        final Map<String, dynamic> ocr = await _fetchJson(
          expectedOcr['path'] as String,
        );
        for (final dynamic pageValue in _list(ocr['pages'])) {
          for (final dynamic blockValue in _list(_map(pageValue)['blocks'])) {
            allText.write(_map(blockValue)['text'] as String);
            allText.write('\n');
          }
        }
      }
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
          allText.toString(),
          contains(character),
          reason: 'missing German character $character in browser fetch',
        );
      }
      expect(allText.toString(), contains('MUSTERSTADT'));
    },
    skip: _runtimeEnabled ? false : _skipReason,
  );
}
