// T011 fixture catalogue model.
//
// Source of truth: `apps/feldexa_app/assets/fixtures/catalog.json`, generated
// and byte-checked by T009 (`tools/corpus/synthetic/generate.dart --check`).
// This parser validates the committed contract instead of trusting the JSON,
// so a drifting catalogue fails at the loader boundary with a precise message.
//
// The catalogue is SIMULATED development input. No delivery target turns it
// into Android runtime evidence.

import 'dart:convert';

import '../evidence/evidence.dart';
import 'fixture_path.dart';

/// Where a fixture's bytes are delivered.
///
/// All three copies are byte-identical by T009's contract. The target does not
/// change the evidence class of the bytes themselves; it changes which
/// consumer may read them. See `apps/feldexa_app/assets/fixtures/README.md`.
enum FixtureDeliveryTarget {
  /// Canonical generated development files; host tooling and tests.
  canonicalDev('canonical development directory'),

  /// Byte-identical mirror served by the Flutter Web dev server at
  /// `/fixtures/...`.
  web('Web delivery mirror'),

  /// Byte-identical PDF copies pushed with `adb` for Android tests.
  corpus('Android test transport copy');

  const FixtureDeliveryTarget(this.description);

  final String description;

  /// Repository-relative directory for this target.
  String directory(FixtureDeliveryPaths delivery) => switch (this) {
    canonicalDev => delivery.canonicalDevDirectory,
    web => delivery.webDirectory,
    corpus => delivery.corpusDirectory,
  };

  /// Fixtures are SIMULATED inputs in every target.
  ///
  /// The target is transport, not evidence: a Chrome test is SIMULATED, and an
  /// Android test is EMULATOR/DEVICE. The corpus copy alone proves nothing.
  EvidenceClass get inputEvidenceClass => EvidenceClass.simulated;
}

/// The catalogue's dev-only delivery declaration.
final class FixtureDeliveryPaths {
  const FixtureDeliveryPaths({
    required this.canonicalDevDirectory,
    required this.webDirectory,
    required this.corpusDirectory,
    required this.webBaseUrl,
    required this.flutterAssetsDeclared,
    required this.androidRelease,
    required this.androidTestDelivery,
  });

  factory FixtureDeliveryPaths.fromJson(Object? value, String path) {
    final Map<String, Object?> map = _asMap(value, path);
    final bool flutterAssetsDeclared = _asBool(
      map,
      'flutterAssetsDeclared',
      path,
    );
    if (flutterAssetsDeclared) {
      throw FormatException(
        '$path.flutterAssetsDeclared must be false: fixtures must never be '
        'packaged into an Android build (T009 dev-only delivery policy).',
      );
    }
    final String webBaseUrl = validateWebBasePath(
      _asString(map, 'webBaseUrl', path),
      label: '$path.webBaseUrl',
    );
    return FixtureDeliveryPaths(
      canonicalDevDirectory: _asRelativeDirectory(
        map,
        'canonicalDevDirectory',
        path,
      ),
      webDirectory: _asRelativeDirectory(map, 'webDirectory', path),
      corpusDirectory: _asRelativeDirectory(map, 'corpusDirectory', path),
      webBaseUrl: webBaseUrl,
      flutterAssetsDeclared: flutterAssetsDeclared,
      androidRelease: _asString(map, 'androidRelease', path),
      androidTestDelivery: _asString(map, 'androidTestDelivery', path),
    );
  }

  final String canonicalDevDirectory;
  final String webDirectory;
  final String corpusDirectory;
  final String webBaseUrl;
  final bool flutterAssetsDeclared;
  final String androidRelease;
  final String androidTestDelivery;

  @override
  String toString() =>
      'FixtureDeliveryPaths(canonical: $canonicalDevDirectory, '
      'web: $webDirectory, corpus: $corpusDirectory)';
}

/// Fixture roles declared by the synthetic catalogue.
enum FixtureRole {
  editor,
  navigation,
  geometry,
  fields,
  importFailure;

  String get wireName => this == importFailure ? 'import-failure' : name;

  static FixtureRole parse(String value) {
    for (final FixtureRole role in values) {
      if (role.wireName == value) {
        return role;
      }
    }
    throw FormatException('Unknown fixture role "$value".');
  }
}

/// Fixture expectation statuses declared by the catalogue.
enum FixtureStatus {
  valid,
  encrypted,
  truncated,
  notAPdf;

  String get wireName => this == notAPdf ? 'not-a-pdf' : name;

  static FixtureStatus parse(String value) {
    for (final FixtureStatus status in values) {
      if (status.wireName == value) {
        return status;
      }
    }
    throw FormatException('Unknown fixture status "$value".');
  }
}

/// One declared page geometry in display points.
final class FixturePage {
  const FixturePage({
    required this.index,
    required this.widthPt,
    required this.heightPt,
    required this.rotation,
  });

  final int index;
  final double widthPt;
  final double heightPt;
  final int rotation;

  Map<String, Object?> toJson() => <String, Object?>{
    'index': index,
    'widthPt': widthPt,
    'heightPt': heightPt,
    'rotation': rotation,
  };
}

/// Expected-OCR file reference from the catalogue.
final class FixtureOcrReference {
  const FixtureOcrReference({
    required this.path,
    required this.schemaVersion,
    required this.language,
    required this.pageCount,
    required this.blockCount,
  });

  final String path;
  final int schemaVersion;
  final String language;
  final int pageCount;
  final int blockCount;
}

/// One fixture entry from `catalog.json`.
final class FixtureDescriptor {
  const FixtureDescriptor({
    required this.id,
    required this.kind,
    required this.role,
    required this.status,
    required this.title,
    required this.description,
    required this.path,
    required this.assetPath,
    required this.webPath,
    required this.corpusPath,
    required this.sha256,
    required this.sizeBytes,
    required this.pageCount,
    required this.pages,
    required this.expectedOcr,
    required this.expectedError,
    required this.provenance,
    required this.raw,
  });

  final String id;

  /// Always `synthetic` for the committed SIMULATED catalogue.
  final String kind;
  final FixtureRole role;
  final FixtureStatus status;
  final String title;
  final String description;

  /// Delivery-relative file name, for example `sf-001.pdf`.
  final String path;
  final String assetPath;
  final String webPath;
  final String corpusPath;
  final String sha256;
  final int sizeBytes;
  final int pageCount;
  final List<FixturePage> pages;
  final FixtureOcrReference? expectedOcr;
  final String? expectedError;
  final Map<String, Object?> provenance;

  /// Deeply immutable copy of the catalogue entry.
  final Map<String, Object?> raw;

  bool get isImportFailure => role == FixtureRole.importFailure;

  bool get hasExpectedOcr => expectedOcr != null;

  /// Repository-relative path for [target].
  String pathFor(FixtureDeliveryTarget target) => switch (target) {
    FixtureDeliveryTarget.canonicalDev => assetPath,
    FixtureDeliveryTarget.web => webPath,
    FixtureDeliveryTarget.corpus => corpusPath,
  };

  /// Ground-truth map from the catalogue, kept raw because the typed model is
  /// owned by `feldexa_core` (T015/T018), not by the test toolkit.
  Map<String, Object?> get groundTruth =>
      _freezeMap(_asMap(raw['groundTruth'], 'fixtures[$id].groundTruth'));

  /// Ground-truth fields, in catalogue order.
  List<Object?> get groundTruthFields =>
      _asList(groundTruth['fields'], 'fixtures[$id].groundTruth.fields');

  @override
  String toString() => 'FixtureDescriptor($id, ${role.wireName})';
}

/// Parsed and validated `catalog.json`.
final class FixtureCatalog {
  FixtureCatalog._({
    required this.schemaVersion,
    required this.catalogVersion,
    required this.description,
    required this.evidenceClass,
    required this.generationDate,
    required this.delivery,
    required this.fixtures,
    required this.raw,
  }) : _byId = <String, FixtureDescriptor>{
         for (final FixtureDescriptor fixture in fixtures) fixture.id: fixture,
       };

  /// Parses [source] as a catalogue JSON document.
  factory FixtureCatalog.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('catalog.json is not valid JSON: ${error.message}');
    }
    return FixtureCatalog.fromJson(_asMap(decoded, r'catalog.json'));
  }

  /// Validates an already-decoded catalogue object.
  factory FixtureCatalog.fromJson(Map<String, Object?> source) {
    final int schemaVersion = _asInt(source, 'schemaVersion', 'catalog');
    if (schemaVersion != 1) {
      throw FormatException(
        'catalog.schemaVersion must be 1, found $schemaVersion.',
      );
    }

    final String catalogVersion = _asString(
      source,
      'catalogVersion',
      'catalog',
    );
    final String description = _asString(source, 'description', 'catalog');
    final String generationDate = _asString(
      source,
      'generationDate',
      'catalog',
    );

    final EvidenceClass evidenceClass = EvidenceClass.parse(
      _asString(source, 'evidenceClass', 'catalog'),
    );
    if (evidenceClass != EvidenceClass.simulated) {
      throw FormatException(
        'catalog.evidenceClass must be SIMULATED for the synthetic fixture '
        'catalogue, found ${evidenceClass.label}. Host checks and Android '
        'runs must not be reported through this catalogue.',
      );
    }

    _validateRights(_asMap(source['rights'], 'catalog.rights'));
    _validateGenerator(_asMap(source['generator'], 'catalog.generator'));

    final FixtureDeliveryPaths delivery = FixtureDeliveryPaths.fromJson(
      source['delivery'],
      'catalog.delivery',
    );

    final List<Object?> fixtureValues = _asList(
      source['fixtures'],
      'catalog.fixtures',
    );
    if (fixtureValues.isEmpty) {
      throw const FormatException('catalog.fixtures must not be empty.');
    }
    final int declaredCount = _asInt(source, 'fixtureCount', 'catalog');
    if (declaredCount != fixtureValues.length) {
      throw FormatException(
        'catalog.fixtureCount is $declaredCount but catalog.fixtures has '
        '${fixtureValues.length} entries.',
      );
    }

    final List<FixtureDescriptor> fixtures = <FixtureDescriptor>[];
    final Set<String> ids = <String>{};
    for (int index = 0; index < fixtureValues.length; index++) {
      final FixtureDescriptor fixture = _parseFixture(
        fixtureValues[index],
        'catalog.fixtures[$index]',
        delivery,
      );
      if (!ids.add(fixture.id)) {
        throw FormatException(
          'catalog.fixtures contains duplicate id "${fixture.id}".',
        );
      }
      fixtures.add(fixture);
    }

    return FixtureCatalog._(
      schemaVersion: schemaVersion,
      catalogVersion: catalogVersion,
      description: description,
      evidenceClass: evidenceClass,
      generationDate: generationDate,
      delivery: delivery,
      fixtures: List<FixtureDescriptor>.unmodifiable(fixtures),
      raw: _freezeMap(source),
    );
  }

  final int schemaVersion;
  final String catalogVersion;
  final String description;
  final EvidenceClass evidenceClass;
  final String generationDate;
  final FixtureDeliveryPaths delivery;
  final List<FixtureDescriptor> fixtures;
  final Map<String, Object?> raw;
  final Map<String, FixtureDescriptor> _byId;

  /// Looks up a fixture by its stable id.
  ///
  /// Throws [ArgumentError] with the known ids for an unknown id.
  FixtureDescriptor fixture(String id) {
    final FixtureDescriptor? descriptor = _byId[id];
    if (descriptor == null) {
      final List<String> known = _byId.keys.toList()..sort();
      throw ArgumentError.value(
        id,
        'id',
        'unknown fixture; known ids: ${known.join(', ')}',
      );
    }
    return descriptor;
  }

  /// Fixtures with [role], in catalogue order.
  Iterable<FixtureDescriptor> byRole(FixtureRole role) =>
      fixtures.where((FixtureDescriptor fixture) => fixture.role == role);

  /// Fixtures that must load successfully.
  Iterable<FixtureDescriptor> get validFixtures => fixtures.where(
    (FixtureDescriptor fixture) => fixture.status == FixtureStatus.valid,
  );

  /// Fixtures that intentionally fail import.
  Iterable<FixtureDescriptor> get importFailures =>
      fixtures.where((FixtureDescriptor fixture) => fixture.isImportFailure);

  @override
  String toString() =>
      'FixtureCatalog($catalogVersion, ${fixtures.length} SIMULATED fixtures)';
}

FixtureDescriptor _parseFixture(
  Object? value,
  String path,
  FixtureDeliveryPaths delivery,
) {
  final Map<String, Object?> map = _asMap(value, path);
  final String id = _asString(map, 'id', path);
  if (!RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(id)) {
    throw FormatException('$path.id "$id" must match [a-z0-9][a-z0-9-]*.');
  }

  final String kind = _asString(map, 'kind', path);
  if (kind != 'synthetic') {
    throw FormatException(
      '$path.kind must be "synthetic"; the committed catalogue is SIMULATED '
      'development input, not a rights-cleared corpus entry.',
    );
  }

  final FixtureRole role = FixtureRole.parse(_asString(map, 'role', path));
  final FixtureStatus status = FixtureStatus.parse(
    _asString(map, 'status', path),
  );
  final String title = _asString(map, 'title', path);
  final String description = _asString(map, 'description', path);

  final String filePath = _asString(map, 'path', path);
  if (filePath != '$id.pdf') {
    throw FormatException('$path.path must be "$id.pdf", found "$filePath".');
  }
  validatePortableRelativePath(filePath, label: '$path.path');
  final String assetPath = _asString(map, 'assetPath', path);
  final String webPath = _asString(map, 'webPath', path);
  final String corpusPath = _asString(map, 'corpusPath', path);
  final String expectedAsset = '${delivery.canonicalDevDirectory}/$filePath';
  final String expectedWeb = '${delivery.webDirectory}/$filePath';
  final String expectedCorpus = '${delivery.corpusDirectory}/$filePath';
  if (assetPath != expectedAsset) {
    throw FormatException(
      '$path.assetPath must be "$expectedAsset", found "$assetPath".',
    );
  }
  if (webPath != expectedWeb) {
    throw FormatException(
      '$path.webPath must be "$expectedWeb", found "$webPath".',
    );
  }
  if (corpusPath != expectedCorpus) {
    throw FormatException(
      '$path.corpusPath must be "$expectedCorpus", found "$corpusPath".',
    );
  }
  validatePortableRelativePath(assetPath, label: '$path.assetPath');
  validatePortableRelativePath(webPath, label: '$path.webPath');
  validatePortableRelativePath(corpusPath, label: '$path.corpusPath');

  final String sha256 = _asString(map, 'sha256', path);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
    throw FormatException(
      '$path.sha256 must be 64 lowercase hexadecimal characters.',
    );
  }
  final int sizeBytes = _asInt(map, 'sizeBytes', path);
  if (sizeBytes <= 0) {
    throw FormatException('$path.sizeBytes must be positive.');
  }
  final int pageCount = _asInt(map, 'pageCount', path);
  if (pageCount < 0) {
    throw FormatException('$path.pageCount must not be negative.');
  }

  final List<Object?> pageValues = _asList(map['pages'], '$path.pages');
  if (pageValues.length != pageCount) {
    throw FormatException(
      '$path.pageCount is $pageCount but pages has ${pageValues.length}.',
    );
  }
  final List<FixturePage> pages = <FixturePage>[];
  for (int index = 0; index < pageValues.length; index++) {
    final Map<String, Object?> page = _asMap(
      pageValues[index],
      '$path.pages[$index]',
    );
    final int declaredIndex = _asInt(page, 'index', '$path.pages[$index]');
    if (declaredIndex != index) {
      throw FormatException(
        '$path.pages[$index].index must be $index, found $declaredIndex.',
      );
    }
    final double widthPt = _asDouble(page, 'widthPt', '$path.pages[$index]');
    final double heightPt = _asDouble(page, 'heightPt', '$path.pages[$index]');
    if (widthPt <= 0 || heightPt <= 0) {
      throw FormatException(
        '$path.pages[$index] width and height must be positive.',
      );
    }
    final int rotation = _asInt(page, 'rotation', '$path.pages[$index]');
    if (!const <int>{0, 90, 180, 270}.contains(rotation)) {
      throw FormatException(
        '$path.pages[$index].rotation must be 0, 90, 180, or 270.',
      );
    }
    pages.add(
      FixturePage(
        index: index,
        widthPt: widthPt,
        heightPt: heightPt,
        rotation: rotation,
      ),
    );
  }

  final Object? expectedOcrValue = map['expectedOcr'];
  final FixtureOcrReference? expectedOcr = expectedOcrValue == null
      ? null
      : _parseOcrReference(
          expectedOcrValue,
          '$path.expectedOcr',
          pageCount,
          fixtureId: id,
        );
  final String? expectedError = _optionalString(map, 'expectedError', path);

  if (role == FixtureRole.importFailure) {
    if (status == FixtureStatus.valid) {
      throw FormatException(
        '$path import-failure fixtures must not have status "valid".',
      );
    }
    if (expectedOcr != null) {
      throw FormatException(
        '$path failure fixtures must not declare expectedOcr.',
      );
    }
    final String requiredCode = switch (status) {
      FixtureStatus.encrypted => 'IMP-001',
      FixtureStatus.truncated => 'IMP-002',
      FixtureStatus.notAPdf => 'IMP-004',
      FixtureStatus.valid => throw StateError('unreachable'),
    };
    if (expectedError != requiredCode) {
      throw FormatException(
        '$path.expectedError must be "$requiredCode" for status '
        '"${status.wireName}", found "$expectedError".',
      );
    }
    if (pageCount == 0 && status == FixtureStatus.encrypted) {
      throw FormatException('$path encrypted fixtures must declare a page.');
    }
    if ((status == FixtureStatus.truncated ||
            status == FixtureStatus.notAPdf) &&
        pageCount != 0) {
      throw FormatException(
        '$path unreadable failure fixtures must declare pageCount 0.',
      );
    }
  } else {
    if (status != FixtureStatus.valid) {
      throw FormatException(
        '$path role "${role.wireName}" must have status "valid".',
      );
    }
    if (expectedOcr == null) {
      throw FormatException('$path valid fixtures must declare expectedOcr.');
    }
    if (expectedError != null) {
      throw FormatException(
        '$path valid fixtures must not declare expectedError.',
      );
    }
    if (pageCount < 1) {
      throw FormatException('$path valid fixtures must declare a page.');
    }
  }

  final Map<String, Object?> provenance = _asMap(
    map['provenance'],
    '$path.provenance',
  );
  if (!_asBool(provenance, 'rightsCleared', '$path.provenance')) {
    throw FormatException('$path.provenance.rightsCleared must be true.');
  }
  if (_asBool(provenance, 'containsPersonalData', '$path.provenance')) {
    throw FormatException(
      '$path.provenance.containsPersonalData must be false for SIMULATED '
      'development fixtures.',
    );
  }

  final Map<String, Object?> groundTruth = _asMap(
    map['groundTruth'],
    '$path.groundTruth',
  );
  final List<Object?> groundTruthFields = _asList(
    groundTruth['fields'],
    '$path.groundTruth.fields',
  );
  if (status == FixtureStatus.valid && groundTruthFields.isEmpty) {
    throw FormatException(
      '$path valid fixtures must declare at least one ground-truth field.',
    );
  }
  if (status != FixtureStatus.valid && groundTruthFields.isNotEmpty) {
    throw FormatException(
      '$path failure fixtures must not declare ground-truth fields.',
    );
  }

  final Map<String, Object?> synthetic = _asMap(
    map['synthetic'],
    '$path.synthetic',
  );
  validatePortableRelativePath(
    _asString(synthetic, 'generator', '$path.synthetic'),
    label: '$path.synthetic.generator',
  );

  return FixtureDescriptor(
    id: id,
    kind: kind,
    role: role,
    status: status,
    title: title,
    description: description,
    path: filePath,
    assetPath: assetPath,
    webPath: webPath,
    corpusPath: corpusPath,
    sha256: sha256,
    sizeBytes: sizeBytes,
    pageCount: pageCount,
    pages: List<FixturePage>.unmodifiable(pages),
    expectedOcr: expectedOcr,
    expectedError: expectedError,
    provenance: _freezeMap(provenance),
    raw: _freezeMap(map),
  );
}

FixtureOcrReference _parseOcrReference(
  Object? value,
  String path,
  int fixturePageCount, {
  required String fixtureId,
}) {
  final Map<String, Object?> map = _asMap(value, path);
  final int schemaVersion = _asInt(map, 'schemaVersion', path);
  if (schemaVersion != 1) {
    throw FormatException('$path.schemaVersion must be 1.');
  }
  final String ocrPath = _asString(map, 'path', path);
  final String expectedOcrPath = '$fixtureId.expected-ocr.json';
  if (ocrPath != expectedOcrPath) {
    throw FormatException(
      '$path.path must be "$expectedOcrPath", found "$ocrPath".',
    );
  }
  validatePortableRelativePath(ocrPath, label: '$path.path');
  final String language = _asString(map, 'language', path);
  final int pageCount = _asInt(map, 'pageCount', path);
  if (pageCount != fixturePageCount) {
    throw FormatException(
      '$path.pageCount must match the fixture pageCount $fixturePageCount.',
    );
  }
  final int blockCount = _asInt(map, 'blockCount', path);
  if (blockCount <= 0) {
    throw FormatException('$path.blockCount must be positive.');
  }
  return FixtureOcrReference(
    path: ocrPath,
    schemaVersion: schemaVersion,
    language: language,
    pageCount: pageCount,
    blockCount: blockCount,
  );
}

void _validateRights(Map<String, Object?> rights) {
  if (_asBool(rights, 'thirdPartyContent', 'catalog.rights')) {
    throw const FormatException(
      'catalog.rights.thirdPartyContent must be false for the synthetic '
      'catalogue.',
    );
  }
  if (_asBool(rights, 'containsPersonalData', 'catalog.rights')) {
    throw const FormatException(
      'catalog.rights.containsPersonalData must be false.',
    );
  }
  if (!_asBool(rights, 'rightsCleared', 'catalog.rights')) {
    throw const FormatException('catalog.rights.rightsCleared must be true.');
  }
}

void _validateGenerator(Map<String, Object?> generator) {
  final String generatorPath = _asString(
    generator,
    'path',
    'catalog.generator',
  );
  validatePortableRelativePath(generatorPath, label: 'catalog.generator.path');
  _asString(generator, 'version', 'catalog.generator');
  if (!_asBool(generator, 'deterministic', 'catalog.generator')) {
    throw const FormatException(
      'catalog.generator.deterministic must be true.',
    );
  }
}

String _asRelativeDirectory(Map<String, Object?> map, String key, String path) {
  final String value = _asString(map, key, path);
  return validatePortableRelativePath(value, label: '$path.$key');
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

String? _optionalString(Map<String, Object?> map, String key, String path) {
  final Object? value = map[key];
  if (value == null) {
    return null;
  }
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('$path.$key must be null or a non-empty string.');
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
