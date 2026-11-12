// T011 SHA-256 tests.
//
// Published FIPS 180-4 vectors plus the committed fixture digest. This is the
// independent check the fixture loader relies on; it is not a security claim.

import 'dart:convert';

import 'package:feldexa_testkit/feldexa_testkit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sha256Hex', () {
    test('matches the empty-message vector', () {
      expect(
        sha256Hex(const <int>[]),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('matches the "abc" vector', () {
      expect(
        sha256Hex(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('matches the quick-brown-fox vector', () {
      expect(
        sha256Hex(utf8.encode('The quick brown fox jumps over the lazy dog')),
        'd7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592',
      );
    });

    test('matches a 1,000,000-byte vector (multi-block boundary)', () {
      expect(
        sha256Hex(List<int>.filled(1000000, 0x61)),
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
      );
    });

    test('hashes UTF-8 German text as bytes, not as UTF-16 code units', () {
      expect(
        sha256Hex(utf8.encode('Grüße aus Musterstadt')),
        '697479f53608f9940e6ba58a0cba24af5d5c718d24111d9b207d17955aa28580',
      );
    });

    test('matches an additional ASCII vector', () {
      expect(
        sha256Hex(utf8.encode('Feldexa T011')),
        'c23ccb1dca91dd7bcdb7d43391c615c23477c34fe826a65c2d9f5e923e26ee8e',
      );
    });

    test('distinguishes one-byte changes', () {
      expect(
        sha256Hex(utf8.encode('abc')),
        isNot(sha256Hex(utf8.encode('abd'))),
      );
    });
  });
}
