// T028 SIMULATED fixture catalogue.
//
// `research.md` D-16: the Web import adapter uses the fixed synthetic fixture
// catalogue from `apps/feldexa_app/assets/fixtures/`, selected by fixture id.
// The browser bootstrap fetches `catalog.json`, the PDF bytes, and the
// pre-authored expected-OCR documents, then constructs this catalogue. The
// adapter itself performs no network or file-system access.
//
// The canonical, full validation lives in `feldexa_testkit` (T011). This parser
// is the adapter-local projection of the same committed JSON: it validates
// exactly what the simulated import, raster, and OCR adapters consume (ids,
// status, SHA-256 and size pins, page geometry, expected error, expected OCR)
// and nothing else. Tests cross-check it against the canonical T011 loader.
//
// All values are SIMULATED development input. Parsing them never produces
// `EMULATOR` or `DEVICE` evidence.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/evidence.dart';

import 'simulated_digest.dart';

/// Fixture roles declared by the synthetic catalogue.
enum SimulatedFixtureRole {
  editor('editor'),
  navigation('navigation'),
  geometry('geometry'),
  fields('fields'),
  importFailure('import-failure');

  const SimulatedFixtureRole(this.wireName);

  /// Stable JSON token.
  final String wireName;

  /// Parses a catalogue role token.
  static SimulatedFixtureRole parse(String value) {
    for (final SimulatedFixtureRole role in values) {
      if (role.wireName == value) {
        return role;
      }
    }
    throw FormatException('Unknown fixture role.');
  }
}

/// Expected import status of one fixture.
enum SimulatedFixtureStatus {
  valid('valid'),
  encrypted('encrypted'),
  truncated('truncated'),
  notAPdf('not-a-pdf');

  const SimulatedFixtureStatus(this.wireName);

  /// Stable JSON token.
  final String wireName;

  /// Parses a catalogue status token.
  static SimulatedFixtureStatus parse(String value) {
    for (final SimulatedFixtureStatus status in values) {
      if (status.wireName == value) {
        return status;
      }
    }
    throw FormatException('Unknown fixture status.');
  }
}

/// One page's display geometry in PDF points.
final class SimulatedFixturePage {
  /// Creates one display-geometry declaration.
  const SimulatedFixturePage({
    required this.index,
    required this.widthPt,
    required this.heightPt,
    required this.rotation,
  });

  /// Zero-based page index.
  final int index;

  /// Visible width in display points after rotation.
  final double widthPt;

  /// Visible height in display points after rotation.
  final double heightPt;

  /// PDF `/Rotate` value, 0, 90, 180, or 270.
  final int rotation;

  /// Builds the canonical geometry for this page.
  ///
  /// The catalogue stores the visible (display) size. `PageGeometry` stores the
  /// PDF user-space MediaBox, so the quarter-turn rotations swap the box
  /// dimensions; `displaySize` then reproduces the catalogue values.
  PageGeometry toGeometry() {
    final bool quarterTurn = rotation == 90 || rotation == 270;
    final double mediaWidth = quarterTurn ? heightPt : widthPt;
    final double mediaHeight = quarterTurn ? widthPt : heightPt;
    return PageGeometry(
      mediaBox: Rect.fromLTWH(0, 0, mediaWidth, mediaHeight),
      rotation: rotation,
    );
  }
}

/// One validated expected-OCR line.
final class SimulatedOcrLine {
  /// Creates a fixture OCR line.
  const SimulatedOcrLine({
    required this.rect,
    required this.text,
    required this.confidence,
  });

  /// Display-space rectangle.
  final Rect rect;

  /// Pre-authored German text.
  final String text;

  /// Confidence in the inclusive 0–1 interval.
  final double confidence;
}

/// One validated expected-OCR block.
final class SimulatedOcrBlock {
  /// Creates a fixture OCR block.
  const SimulatedOcrBlock({
    required this.rect,
    required this.text,
    required this.confidence,
    required this.lines,
  });

  /// Display-space rectangle.
  final Rect rect;

  /// Pre-authored German text.
  final String text;

  /// Confidence in the inclusive 0–1 interval.
  final double confidence;

  /// Lines in reading order.
  final List<SimulatedOcrLine> lines;
}

/// Expected OCR output for one fixture page.
final class SimulatedOcrPage {
  /// Creates one page of expected OCR output.
  const SimulatedOcrPage({
    required this.pageIndex,
    required this.widthPt,
    required this.heightPt,
    required this.rotation,
    required this.blocks,
  });

  /// Zero-based page index.
  final int pageIndex;

  /// Declared display width in points.
  final double widthPt;

  /// Declared display height in points.
  final double heightPt;

  /// Declared PDF rotation.
  final int rotation;

  /// Validated blocks in catalogue order.
  final List<SimulatedOcrBlock> blocks;
}

/// One validated synthetic fixture.
final class SimulatedFixture {
  /// Creates a validated fixture.
  const SimulatedFixture({
    required this.id,
    required this.role,
    required this.status,
    required this.title,
    required this.displayName,
    required this.bytes,
    required this.sha256,
    required this.sizeBytes,
    required this.pages,
    required this.expectedOcr,
    required this.expectedErrorCode,
  });

  /// Stable fixture id such as `sf-001`.
  final String id;

  /// Catalogue role.
  final SimulatedFixtureRole role;

  /// Expected import status.
  final SimulatedFixtureStatus status;

  /// Human-readable fixture title from the catalogue (metadata only).
  final String title;

  /// User-visible file name; never a path.
  final String displayName;

  /// Defensive copy of the PDF bytes.
  final Uint8List bytes;

  /// Catalogue SHA-256 pin, re-verified while parsing.
  final String sha256;

  /// Catalogue size pin, re-verified while parsing.
  final int sizeBytes;

  /// Display geometry per page, ordered from index 0.
  final List<SimulatedFixturePage> pages;

  /// Pre-authored OCR output; empty for import-failure fixtures.
  final List<SimulatedOcrPage> expectedOcr;

  /// Expected catalog code for a failure fixture, else null.
  final String? expectedErrorCode;

  /// Whether this fixture is expected to import successfully.
  bool get isImportable => status == SimulatedFixtureStatus.valid;

  /// Display geometries in page order.
  List<PageGeometry> get geometries =>
      List<PageGeometry>.unmodifiable(pages.map((p) => p.toGeometry()));

  /// Page count from the catalogue.
  int get pageCount => pages.length;

  @override
  String toString() => 'SimulatedFixture($id, ${status.wireName})';
}

/// The committed SIMULATED fixture catalogue, projected for the adapters.
final class SimulatedFixtureCatalog {
  SimulatedFixtureCatalog._({
    required this.catalogVersion,
    required this.fixtures,
  }) : _byId = <String, SimulatedFixture>{
         for (final SimulatedFixture fixture in fixtures) fixture.id: fixture,
       };

  /// Parses and validates the catalogue plus the caller-supplied file bytes.
  ///
  /// [catalogJson] is the committed `catalog.json`; [pdfBytesById] maps each
  /// fixture id to the exact PDF bytes; [expectedOcrById] maps each fixture id
  /// to its decoded `<id>.expected-ocr.json` document. The three inputs are
  /// fetched by the Web bootstrap, not by this package.
  ///
  /// Throws [FormatException] for a drifting catalogue, a SHA-256/size
  /// mismatch, or malformed expected OCR. Messages name the JSON path but
  /// never echo document text, titles, or bytes.
  factory SimulatedFixtureCatalog.parse({
    required String catalogJson,
    required Map<String, Uint8List> pdfBytesById,
    required Map<String, Map<String, Object?>> expectedOcrById,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(catalogJson);
    } on FormatException {
      throw const FormatException('catalog.json is not valid JSON.');
    }
    final Map<String, Object?> catalog = _asMap(decoded, 'catalog');
    if (_asInt(catalog, 'schemaVersion', 'catalog') != 1) {
      throw const FormatException('catalog.schemaVersion must be 1.');
    }
    final Object? evidence = catalog['evidenceClass'];
    if (evidence is! String ||
        evidence.toUpperCase() != EvidenceClass.simulated.label) {
      throw const FormatException('catalog.evidenceClass must be SIMULATED.');
    }
    _validateRights(_asMap(catalog['rights'], 'catalog.rights'));
    _validateGenerator(_asMap(catalog['generator'], 'catalog.generator'));

    final String catalogVersion = _asString(
      catalog,
      'catalogVersion',
      'catalog',
    );
    final List<Object?> rawFixtures = _asList(
      catalog['fixtures'],
      'catalog.fixtures',
    );
    if (rawFixtures.isEmpty) {
      throw const FormatException('catalog.fixtures must not be empty.');
    }
    final int declaredCount = _asInt(catalog, 'fixtureCount', 'catalog');
    if (declaredCount != rawFixtures.length) {
      throw const FormatException(
        'catalog.fixtureCount must equal catalog.fixtures.length.',
      );
    }

    final List<SimulatedFixture> fixtures = <SimulatedFixture>[];
    final Set<String> ids = <String>{};
    for (int index = 0; index < rawFixtures.length; index++) {
      final Map<String, Object?> raw = _asMap(
        rawFixtures[index],
        'catalog.fixtures[$index]',
      );
      final String id = _asString(raw, 'id', 'catalog.fixtures[$index]');
      if (!ids.add(id)) {
        throw const FormatException('catalog.fixtures ids must be unique.');
      }
      final Uint8List? bytes = pdfBytesById[id];
      if (bytes == null) {
        throw FormatException('missing PDF bytes for fixture "$id".');
      }
      final Map<String, Object?>? ocr = expectedOcrById[id];
      fixtures.add(_parseFixture(raw, id: id, bytes: bytes, expectedOcr: ocr));
    }
    return SimulatedFixtureCatalog._(
      catalogVersion: catalogVersion,
      fixtures: List<SimulatedFixture>.unmodifiable(fixtures),
    );
  }

  /// Catalogue version token such as `fixtures-1.0.0`.
  final String catalogVersion;

  /// Fixtures in catalogue order.
  final List<SimulatedFixture> fixtures;

  final Map<String, SimulatedFixture> _byId;

  /// Looks up a fixture by id.
  ///
  /// Throws [ArgumentError] for an unknown id; the message lists known ids but
  /// never content.
  SimulatedFixture fixture(String id) {
    final SimulatedFixture? fixture = _byId[id];
    if (fixture == null) {
      final List<String> known = _byId.keys.toList()..sort();
      throw ArgumentError(
        'unknown SIMULATED fixture id; known ids: ${known.join(', ')}',
      );
    }
    return fixture;
  }

  /// All fixture ids in catalogue order.
  List<String> get ids => List<String>.unmodifiable(_byId.keys);

  @override
  String toString() =>
      'SimulatedFixtureCatalog($catalogVersion, ${fixtures.length} fixtures)';
}

SimulatedFixture _parseFixture(
  Map<String, Object?> raw, {
  required String id,
  required Uint8List bytes,
  required Map<String, Object?>? expectedOcr,
}) {
  final String path = 'catalog.fixtures[$id]';
  if (!RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(id)) {
    throw FormatException('$path.id is not a stable fixture id.');
  }
  if (_asString(raw, 'kind', path) != 'synthetic') {
    throw FormatException('$path.kind must be "synthetic".');
  }
  final SimulatedFixtureRole role = SimulatedFixtureRole.parse(
    _asString(raw, 'role', path),
  );
  final SimulatedFixtureStatus status = SimulatedFixtureStatus.parse(
    _asString(raw, 'status', path),
  );
  final String title = _asString(raw, 'title', path);
  final String fileName = _asString(raw, 'path', path);
  if (fileName != '$id.pdf') {
    throw FormatException('$path.path must be "$id.pdf".');
  }
  final String sha256 = _asString(raw, 'sha256', path);
  final int sizeBytes = _asInt(raw, 'sizeBytes', path);
  if (bytes.length != sizeBytes) {
    throw FormatException('$path bytes do not match sizeBytes.');
  }
  if (sha256Hex(bytes) != sha256) {
    throw FormatException('$path bytes do not match the SHA-256 pin.');
  }
  final int pageCount = _asInt(raw, 'pageCount', path);
  final List<Object?> rawPages = _asList(raw['pages'], '$path.pages');
  if (rawPages.length != pageCount) {
    throw FormatException('$path.pages must have pageCount entries.');
  }
  final List<SimulatedFixturePage> pages = <SimulatedFixturePage>[];
  for (int index = 0; index < rawPages.length; index++) {
    final Map<String, Object?> page = _asMap(
      rawPages[index],
      '$path.pages[$index]',
    );
    if (_asInt(page, 'index', '$path.pages[$index]') != index) {
      throw FormatException('$path.pages[$index].index must be $index.');
    }
    final double widthPt = _asDouble(page, 'widthPt', '$path.pages[$index]');
    final double heightPt = _asDouble(page, 'heightPt', '$path.pages[$index]');
    if (widthPt <= 0 || heightPt <= 0) {
      throw FormatException('$path.pages[$index] size must be positive.');
    }
    final int rotation = _asInt(page, 'rotation', '$path.pages[$index]');
    if (rotation != 0 && rotation != 90 && rotation != 180 && rotation != 270) {
      throw FormatException('$path.pages[$index].rotation is not supported.');
    }
    final SimulatedFixturePage declared = SimulatedFixturePage(
      index: index,
      widthPt: widthPt,
      heightPt: heightPt,
      rotation: rotation,
    );
    final Size display = declared.toGeometry().displaySize;
    if ((display.width - widthPt).abs() > 0.01 ||
        (display.height - heightPt).abs() > 0.01) {
      throw FormatException(
        '$path.pages[$index] display geometry does not match rotation.',
      );
    }
    pages.add(declared);
  }

  final String? expectedError = raw['expectedError'] == null
      ? null
      : _asString(raw, 'expectedError', path);
  final List<SimulatedOcrPage> ocrPages = <SimulatedOcrPage>[];
  if (role == SimulatedFixtureRole.importFailure) {
    if (status == SimulatedFixtureStatus.valid) {
      throw FormatException('$path import-failure fixtures must not be valid.');
    }
    final String requiredCode = switch (status) {
      SimulatedFixtureStatus.encrypted => 'IMP-001',
      SimulatedFixtureStatus.truncated => 'IMP-002',
      SimulatedFixtureStatus.notAPdf => 'IMP-004',
      SimulatedFixtureStatus.valid => throw StateError('unreachable'),
    };
    if (expectedError != requiredCode) {
      throw FormatException('$path.expectedError does not match its status.');
    }
    if (expectedOcr != null) {
      throw FormatException('$path failure fixtures must not carry OCR.');
    }
  } else {
    if (status != SimulatedFixtureStatus.valid || expectedError != null) {
      throw FormatException('$path must be a valid fixture without an error.');
    }
    if (expectedOcr == null) {
      throw FormatException('$path valid fixtures require expected OCR.');
    }
    ocrPages.addAll(
      _parseExpectedOcr(
        expectedOcr,
        fixtureId: id,
        pages: pages,
        path: '$path.expectedOcr',
      ),
    );
  }

  return SimulatedFixture(
    id: id,
    role: role,
    status: status,
    title: title,
    displayName: fileName,
    bytes: copyBytes(bytes),
    sha256: sha256,
    sizeBytes: sizeBytes,
    pages: List<SimulatedFixturePage>.unmodifiable(pages),
    expectedOcr: List<SimulatedOcrPage>.unmodifiable(ocrPages),
    expectedErrorCode: expectedError,
  );
}

List<SimulatedOcrPage> _parseExpectedOcr(
  Map<String, Object?> document, {
  required String fixtureId,
  required List<SimulatedFixturePage> pages,
  required String path,
}) {
  if (_asInt(document, 'schemaVersion', path) != 1) {
    throw FormatException('$path.schemaVersion must be 1.');
  }
  if (_asString(document, 'fixtureId', path) != fixtureId) {
    throw FormatException('$path.fixtureId does not match the fixture.');
  }
  if (_asString(document, 'language', path) != 'de') {
    throw FormatException('$path.language must be "de".');
  }
  final Object? evidence = document['evidenceClass'];
  if (evidence is! String ||
      evidence.toUpperCase() != EvidenceClass.simulated.label) {
    throw FormatException('$path.evidenceClass must be SIMULATED.');
  }
  final List<Object?> rawPages = _asList(document['pages'], '$path.pages');
  if (rawPages.length != pages.length) {
    throw FormatException('$path.pages must have one entry per page.');
  }
  final List<SimulatedOcrPage> result = <SimulatedOcrPage>[];
  for (int index = 0; index < rawPages.length; index++) {
    final Map<String, Object?> page = _asMap(
      rawPages[index],
      '$path.pages[$index]',
    );
    if (_asInt(page, 'pageIndex', '$path.pages[$index]') != index) {
      throw FormatException('$path.pages[$index].pageIndex must be $index.');
    }
    final double widthPt = _asDouble(page, 'widthPt', '$path.pages[$index]');
    final double heightPt = _asDouble(page, 'heightPt', '$path.pages[$index]');
    final int rotation = _asInt(page, 'rotation', '$path.pages[$index]');
    final SimulatedFixturePage declared = pages[index];
    if ((widthPt - declared.widthPt).abs() > 0.01 ||
        (heightPt - declared.heightPt).abs() > 0.01 ||
        rotation != declared.rotation) {
      throw FormatException(
        '$path.pages[$index] geometry must match the catalogue.',
      );
    }
    final List<Object?> rawBlocks = _asList(
      page['blocks'],
      '$path.pages[$index].blocks',
    );
    final List<SimulatedOcrBlock> blocks = <SimulatedOcrBlock>[];
    for (int blockIndex = 0; blockIndex < rawBlocks.length; blockIndex++) {
      blocks.add(
        _parseOcrBlock(
          _asMap(
            rawBlocks[blockIndex],
            '$path.pages[$index].blocks[$blockIndex]',
          ),
          pageWidth: widthPt,
          pageHeight: heightPt,
          path: '$path.pages[$index].blocks[$blockIndex]',
        ),
      );
    }
    result.add(
      SimulatedOcrPage(
        pageIndex: index,
        widthPt: widthPt,
        heightPt: heightPt,
        rotation: rotation,
        blocks: List<SimulatedOcrBlock>.unmodifiable(blocks),
      ),
    );
  }
  return result;
}

SimulatedOcrBlock _parseOcrBlock(
  Map<String, Object?> raw, {
  required double pageWidth,
  required double pageHeight,
  required String path,
}) {
  final Rect rect = _parseOcrRect(
    raw['rect'],
    pageWidth: pageWidth,
    pageHeight: pageHeight,
    path: '$path.rect',
  );
  final String text = _asString(raw, 'text', path);
  final double confidence = _parseConfidence(raw, path);
  final List<Object?> rawLines = _asList(raw['lines'], '$path.lines');
  if (rawLines.isEmpty) {
    throw FormatException('$path.lines must not be empty.');
  }
  final List<SimulatedOcrLine> lines = <SimulatedOcrLine>[];
  for (int index = 0; index < rawLines.length; index++) {
    final Map<String, Object?> line = _asMap(
      rawLines[index],
      '$path.lines[$index]',
    );
    lines.add(
      SimulatedOcrLine(
        rect: _parseOcrRect(
          line['rect'],
          pageWidth: pageWidth,
          pageHeight: pageHeight,
          path: '$path.lines[$index].rect',
        ),
        text: _asString(line, 'text', '$path.lines[$index]'),
        confidence: _parseConfidence(line, '$path.lines[$index]'),
      ),
    );
  }
  return SimulatedOcrBlock(
    rect: rect,
    text: text,
    confidence: confidence,
    lines: List<SimulatedOcrLine>.unmodifiable(lines),
  );
}

Rect _parseOcrRect(
  Object? value, {
  required double pageWidth,
  required double pageHeight,
  required String path,
}) {
  final Map<String, Object?> map = _asMap(value, path);
  final double x = _asDouble(map, 'x', path);
  final double y = _asDouble(map, 'y', path);
  final double width = _asDouble(map, 'width', path);
  final double height = _asDouble(map, 'height', path);
  if (width <= 0 || height <= 0) {
    throw FormatException('$path must be positive.');
  }
  const double tolerance = 0.01;
  if (x < -tolerance ||
      y < -tolerance ||
      x + width > pageWidth + tolerance ||
      y + height > pageHeight + tolerance) {
    throw FormatException('$path must lie inside the page.');
  }
  return Rect.fromLTWH(x, y, width, height);
}

double _parseConfidence(Map<String, Object?> raw, String path) {
  final Object? value = raw['confidence'];
  if (value is! num) {
    throw FormatException('$path.confidence must be a number.');
  }
  final double confidence = value.toDouble();
  if (!confidence.isFinite || confidence < 0 || confidence > 1) {
    throw FormatException('$path.confidence must be between 0 and 1.');
  }
  return confidence;
}

void _validateRights(Map<String, Object?> rights) {
  if (_asBool(rights, 'thirdPartyContent', 'catalog.rights') ||
      _asBool(rights, 'containsPersonalData', 'catalog.rights')) {
    throw const FormatException(
      'catalog.rights must describe synthetic, non-personal content.',
    );
  }
  if (!_asBool(rights, 'rightsCleared', 'catalog.rights')) {
    throw const FormatException('catalog.rights must be rights-cleared.');
  }
}

void _validateGenerator(Map<String, Object?> generator) {
  _asString(generator, 'path', 'catalog.generator');
  _asString(generator, 'version', 'catalog.generator');
  if (!_asBool(generator, 'deterministic', 'catalog.generator')) {
    throw const FormatException('catalog.generator must be deterministic.');
  }
}

Map<String, Object?> _asMap(Object? value, String path) {
  if (value is Map<Object?, Object?>) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        entry.key.toString(): entry.value,
    };
  }
  throw FormatException('$path must be a JSON object.');
}

List<Object?> _asList(Object? value, String path) {
  if (value is List) {
    return List<Object?>.from(value);
  }
  throw FormatException('$path must be a JSON array.');
}

String _asString(Map<String, Object?> map, String key, String path) {
  final Object? value = map[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('$path.$key must be a non-empty string.');
}

int _asInt(Map<String, Object?> map, String key, String path) {
  final Object? value = map[key];
  if (value is int) {
    return value;
  }
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  throw FormatException('$path.$key must be an integer.');
}

double _asDouble(Map<String, Object?> map, String key, String path) {
  final Object? value = map[key];
  if (value is num) {
    final double result = value.toDouble();
    if (result.isFinite) {
      return result;
    }
  }
  throw FormatException('$path.$key must be a finite number.');
}

bool _asBool(Map<String, Object?> map, String key, String path) {
  final Object? value = map[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('$path.$key must be a boolean.');
}
