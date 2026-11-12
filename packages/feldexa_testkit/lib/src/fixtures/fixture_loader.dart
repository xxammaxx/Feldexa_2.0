// T011 fixture loader.
//
// Loads a committed fixture through a [FixtureSource], verifies its declared
// size and SHA-256, and checks the documented PDF shape for its status. The
// catalogue is always validated first; a drifting or non-SIMULATED catalogue
// fails before any bytes are returned.

import 'dart:convert';
import 'dart:typed_data';

import 'fixture_catalog.dart';
import 'fixture_source.dart';
import 'sha256.dart';

/// Computes the SHA-256 hex digest of fixture bytes.
typedef FixtureDigest = String Function(List<int> bytes);

/// A loaded fixture and its catalogue entry.
final class LoadedFixture {
  LoadedFixture({required this.descriptor, required Uint8List bytes})
    : bytes = Uint8List.fromList(bytes);

  final FixtureDescriptor descriptor;

  /// A defensive copy of the exact bytes from the source.
  final Uint8List bytes;

  int get sizeBytes => bytes.length;

  @override
  String toString() => 'LoadedFixture(${descriptor.id}, $sizeBytes bytes)';
}

/// A fixture load failure with catalogue context.
final class FixtureLoadException implements Exception {
  const FixtureLoadException({
    required this.fixtureId,
    required this.path,
    required this.message,
    this.cause,
  });

  final String fixtureId;
  final String path;
  final String message;
  final Object? cause;

  @override
  String toString() => 'FixtureLoadException($fixtureId, $path): $message';
}

/// Loads fixtures from a [FixtureSource] rooted at one delivery directory.
final class FixtureLoader {
  FixtureLoader({
    required this.catalog,
    required this.source,
    FixtureDigest? digest,
  }) : _digest = digest ?? sha256Hex;

  /// Reads and validates `catalog.json` from [source].
  static Future<FixtureLoader> open(
    FixtureSource source, {
    FixtureDigest? digest,
  }) async {
    final Uint8List catalogBytes;
    try {
      catalogBytes = await source.read('catalog.json');
    } on FixtureSourceException catch (error) {
      throw FixtureLoadException(
        fixtureId: 'catalog',
        path: 'catalog.json',
        message: error.message,
        cause: error,
      );
    }
    final FixtureCatalog catalog;
    try {
      catalog = FixtureCatalog.parse(utf8.decode(catalogBytes));
    } on FormatException catch (error) {
      throw FixtureLoadException(
        fixtureId: 'catalog',
        path: 'catalog.json',
        message: error.message,
        cause: error,
      );
    }
    return FixtureLoader(catalog: catalog, source: source, digest: digest);
  }

  final FixtureCatalog catalog;
  final FixtureSource source;
  final FixtureDigest _digest;

  /// Loads one fixture and verifies size, digest, and PDF shape.
  ///
  /// Set [verifyChecksum] to `false` only when a test deliberately supplies
  /// modified bytes and has already checked the expected failure through the
  /// checksum path.
  Future<LoadedFixture> load(String id, {bool verifyChecksum = true}) async {
    final FixtureDescriptor descriptor = _descriptor(id);
    final Uint8List bytes;
    try {
      bytes = await source.read(descriptor.path);
    } on FixtureSourceException catch (error) {
      throw FixtureLoadException(
        fixtureId: id,
        path: descriptor.path,
        message: error.message,
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw FixtureLoadException(
        fixtureId: id,
        path: descriptor.path,
        message: error.message?.toString() ?? 'invalid fixture path',
        cause: error,
      );
    }

    if (bytes.length != descriptor.sizeBytes) {
      throw FixtureLoadException(
        fixtureId: id,
        path: descriptor.path,
        message:
            'declared ${descriptor.sizeBytes} bytes but source returned '
            '${bytes.length}.',
      );
    }

    if (verifyChecksum) {
      final String actual = _digest(bytes);
      if (actual != descriptor.sha256) {
        throw FixtureLoadException(
          fixtureId: id,
          path: descriptor.path,
          message:
              'SHA-256 mismatch: catalogue ${descriptor.sha256}, '
              'bytes $actual.',
        );
      }
    }

    _validatePdfShape(descriptor, bytes);
    return LoadedFixture(descriptor: descriptor, bytes: bytes);
  }

  /// Loads every fixture in catalogue order.
  Future<List<LoadedFixture>> loadAll({bool verifyChecksum = true}) async {
    final List<LoadedFixture> loaded = <LoadedFixture>[];
    for (final FixtureDescriptor descriptor in catalog.fixtures) {
      loaded.add(await load(descriptor.id, verifyChecksum: verifyChecksum));
    }
    return List<LoadedFixture>.unmodifiable(loaded);
  }

  /// Loads and validates the fixture's expected-OCR document.
  ///
  /// The document is returned deeply immutable. Validation checks the schema,
  /// fixture id, German language, SIMULATED class, page count, and that the
  /// declared block count matches the sum of per-page blocks.
  Future<Map<String, Object?>> loadExpectedOcr(String id) async {
    final FixtureDescriptor descriptor = _descriptor(id);
    final FixtureOcrReference? reference = descriptor.expectedOcr;
    if (reference == null) {
      throw FixtureLoadException(
        fixtureId: id,
        path: descriptor.path,
        message: 'fixture ${descriptor.id} has no expected-OCR document.',
      );
    }

    final Uint8List bytes;
    try {
      bytes = await source.read(reference.path);
    } on FixtureSourceException catch (error) {
      throw FixtureLoadException(
        fixtureId: id,
        path: reference.path,
        message: error.message,
        cause: error,
      );
    }

    final Map<String, Object?> document;
    try {
      final Object? decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        throw const FormatException('expected OCR must be a JSON object');
      }
      document = <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in decoded.entries)
          entry.key.toString(): entry.value,
      };
    } on FormatException catch (error) {
      throw FixtureLoadException(
        fixtureId: id,
        path: reference.path,
        message: 'invalid expected-OCR JSON: ${error.message}',
        cause: error,
      );
    }

    final Map<String, Object?> validated;
    try {
      validated = _validateExpectedOcr(document, descriptor, reference);
    } on FormatException catch (error) {
      throw FixtureLoadException(
        fixtureId: id,
        path: reference.path,
        message: 'invalid expected-OCR content: ${error.message}',
        cause: error,
      );
    }
    return _freezeMap(validated);
  }

  FixtureDescriptor _descriptor(String id) {
    try {
      return catalog.fixture(id);
    } on ArgumentError catch (error) {
      throw FixtureLoadException(
        fixtureId: id,
        path: '',
        message: error.message?.toString() ?? 'unknown fixture',
        cause: error,
      );
    }
  }

  void _validatePdfShape(FixtureDescriptor descriptor, Uint8List bytes) {
    final bool hasPdfHeader = _startsWithAscii(bytes, '%PDF-');
    switch (descriptor.status) {
      case FixtureStatus.valid:
      case FixtureStatus.encrypted:
        if (!hasPdfHeader) {
          throw FixtureLoadException(
            fixtureId: descriptor.id,
            path: descriptor.path,
            message: 'declared a PDF but the bytes do not start with %PDF-.',
          );
        }
        if (!_endsWithEof(bytes)) {
          throw FixtureLoadException(
            fixtureId: descriptor.id,
            path: descriptor.path,
            message: 'declared a readable PDF but no %%EOF trailer was found.',
          );
        }
      case FixtureStatus.truncated:
        if (!hasPdfHeader) {
          throw FixtureLoadException(
            fixtureId: descriptor.id,
            path: descriptor.path,
            message: 'truncated fixture must still start with %PDF-.',
          );
        }
        if (_endsWithEof(bytes)) {
          throw FixtureLoadException(
            fixtureId: descriptor.id,
            path: descriptor.path,
            message: 'truncated fixture unexpectedly has an %%EOF trailer.',
          );
        }
      case FixtureStatus.notAPdf:
        if (hasPdfHeader) {
          throw FixtureLoadException(
            fixtureId: descriptor.id,
            path: descriptor.path,
            message: 'not-a-PDF fixture starts with %PDF-.',
          );
        }
    }
  }

  Map<String, Object?> _validateExpectedOcr(
    Map<String, Object?> document,
    FixtureDescriptor descriptor,
    FixtureOcrReference reference,
  ) {
    Object? require(String key) {
      if (!document.containsKey(key)) {
        throw FormatException('missing "$key"');
      }
      return document[key];
    }

    if (require('schemaVersion') != 1) {
      throw const FormatException('schemaVersion must be 1');
    }
    if (require('fixtureId') != descriptor.id) {
      throw FormatException(
        'fixtureId must be "${descriptor.id}", found '
        '"${document['fixtureId']}".',
      );
    }
    if (require('language') != 'de') {
      throw const FormatException('language must be "de"');
    }
    final String evidence = require('evidenceClass').toString();
    if (evidence.toLowerCase() != 'simulated') {
      throw FormatException(
        'expected OCR must stay SIMULATED, found "$evidence".',
      );
    }

    final Object? pagesValue = require('pages');
    if (pagesValue is! List) {
      throw const FormatException('pages must be a JSON array');
    }
    if (pagesValue.length != reference.pageCount) {
      throw FormatException(
        'declared ${reference.pageCount} OCR pages, found '
        '${pagesValue.length}.',
      );
    }

    int blockTotal = 0;
    for (int index = 0; index < pagesValue.length; index++) {
      final Object? pageValue = pagesValue[index];
      if (pageValue is! Map) {
        throw FormatException('pages[$index] must be an object');
      }
      final Object? pageIndex = pageValue['pageIndex'];
      if (pageIndex != index) {
        throw FormatException('pages[$index].pageIndex must be $index');
      }
      final Object? blocksValue = pageValue['blocks'];
      if (blocksValue is! List) {
        throw FormatException('pages[$index].blocks must be an array');
      }
      blockTotal += blocksValue.length;
    }

    if (blockTotal != reference.blockCount) {
      throw FormatException(
        'declared ${reference.blockCount} OCR blocks, found $blockTotal.',
      );
    }
    return document;
  }
}

bool _startsWithAscii(Uint8List bytes, String prefix) {
  if (bytes.length < prefix.length) {
    return false;
  }
  for (int index = 0; index < prefix.length; index++) {
    if (bytes[index] != prefix.codeUnitAt(index)) {
      return false;
    }
  }
  return true;
}

bool _endsWithEof(Uint8List bytes) {
  int end = bytes.length;
  while (end > 0) {
    final int value = bytes[end - 1];
    if (value != 0x0a && value != 0x0d && value != 0x20 && value != 0x09) {
      break;
    }
    end--;
  }
  const String marker = '%%EOF';
  if (end < marker.length) {
    return false;
  }
  for (int index = 0; index < marker.length; index++) {
    if (bytes[end - marker.length + index] != marker.codeUnitAt(index)) {
      return false;
    }
  }
  return true;
}

Object? _freeze(Object? value) {
  if (value is Map) {
    final Map<String, Object?> copy = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      copy[entry.key.toString()] = _freeze(entry.value);
    }
    return Map<String, Object?>.unmodifiable(copy);
  }
  if (value is List) {
    return List<Object?>.unmodifiable(
      value.map((Object? item) => _freeze(item)),
    );
  }
  return value;
}

Map<String, Object?> _freezeMap(Map<String, Object?> value) =>
    _freeze(value)! as Map<String, Object?>;
