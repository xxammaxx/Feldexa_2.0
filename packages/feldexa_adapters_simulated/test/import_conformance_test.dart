// T037 import-contract conformance runner for the REAL T028 adapter.
//
// This test wires the reusable `feldexa_testkit` import-conformance suite to
// the shipped `SimulatedDocumentImportAdapter` and the real `SimulatedBackend`.
// The fixture catalogue is built IN MEMORY through the existing
// `SimulatedFixtureCatalog.parse` injection seam, so this runner is independent
// of `Directory.current` and of the checkout layout. Unlike the previous fake
// in `feldexa_ports/test/import_port_test.dart`, a change to the adapter's
// acceptance, cleanup, source-copying, or verification behaviour can make this
// runner fail.
//
// Host-VM only. Every result is `SIMULATED`; no Android, SAF, PDF-parser,
// encryption, emulator, or device evidence is produced.

import 'dart:convert';
import 'dart:typed_data';

import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:feldexa_testkit/feldexa_testkit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final SimulatedFixtureCatalog catalog = _inMemoryCatalog();
  final _T028ImportConformanceSubject subject = _T028ImportConformanceSubject(
    catalog,
  );

  for (final ImportConformanceCheck check in importConformanceChecks(subject)) {
    final String label =
        '${check.expectation.id} — ${check.expectation.description}';
    switch (check.status) {
      case ImportConformanceStatus.satisfied:
        test(label, () async {
          await check.run!();
        });
      case ImportConformanceStatus.notCovered:
        test(
          '${check.expectation.id} — NOT COVERED by ${subject.adapterLabel}',
          () {},
          skip: 'NOT COVERED: ${check.reason}',
        );
      case ImportConformanceStatus.nonConforming:
        test(
          '${check.expectation.id} — NON-CONFORMING in ${subject.adapterLabel}',
          () async {
            await check.run!();
          },
        );
    }
  }
}

/// Builds a deterministic catalogue for the fixture ids this runner needs.
///
/// The bytes are synthetic and PDF-shaped; T028 never parses them. All page
/// geometry, status, hash, and size values are pinned by the parser, so the
/// runner still exercises the real catalogue validation path without touching
/// the filesystem.
SimulatedFixtureCatalog _inMemoryCatalog() {
  final Map<String, Uint8List> pdfBytesById = <String, Uint8List>{};
  final Map<String, Map<String, Object?>> expectedOcrById =
      <String, Map<String, Object?>>{};
  final List<Map<String, Object?>> fixtures = <Map<String, Object?>>[];

  void addFixture({
    required String id,
    required String role,
    required String status,
    required List<Map<String, Object?>> pages,
    String? expectedError,
    int byteLength = 512,
  }) {
    final Uint8List bytes = _fixtureBytes(id, byteLength);
    pdfBytesById[id] = bytes;
    final Map<String, Object?> fixture = <String, Object?>{
      'id': id,
      'kind': 'synthetic',
      'role': role,
      'status': status,
      'title': 'T037 in-memory $id',
      'path': '$id.pdf',
      'sha256': sha256Hex(bytes),
      'sizeBytes': bytes.length,
      'pageCount': pages.length,
      'pages': pages,
    };
    if (expectedError != null) {
      fixture['expectedError'] = expectedError;
    }
    fixtures.add(fixture);
    if (status == 'valid') {
      expectedOcrById[id] = <String, Object?>{
        'schemaVersion': 1,
        'fixtureId': id,
        'language': 'de',
        'evidenceClass': 'SIMULATED',
        'pages': <Map<String, Object?>>[
          for (final Map<String, Object?> page in pages)
            <String, Object?>{
              'pageIndex': page['index'],
              'widthPt': page['widthPt'],
              'heightPt': page['heightPt'],
              'rotation': page['rotation'],
              'blocks': const <Object?>[],
            },
        ],
      };
    }
  }

  addFixture(
    id: 'sf-004',
    role: 'fields',
    status: 'valid',
    pages: <Map<String, Object?>>[_a4Page(0)],
  );
  addFixture(
    id: 'sf-003',
    role: 'geometry',
    status: 'valid',
    pages: <Map<String, Object?>>[
      _a4Page(0),
      _page(1, 841.89, 595.28, 0),
      _page(2, 841.89, 595.28, 90),
      _page(3, 595.28, 841.89, 180),
      _page(4, 595.28, 419.53, 270),
    ],
  );
  addFixture(
    id: 'sf-002',
    role: 'navigation',
    status: 'valid',
    byteLength: 4096,
    pages: <Map<String, Object?>>[
      for (int index = 0; index < 5; index++) _a4Page(index),
    ],
  );
  addFixture(
    id: 'sf-protected',
    role: 'import-failure',
    status: 'encrypted',
    pages: <Map<String, Object?>>[_a4Page(0)],
    expectedError: 'IMP-001',
  );
  addFixture(
    id: 'sf-truncated',
    role: 'import-failure',
    status: 'truncated',
    pages: const <Map<String, Object?>>[],
    expectedError: 'IMP-002',
  );
  addFixture(
    id: 'sf-not-a-pdf',
    role: 'import-failure',
    status: 'not-a-pdf',
    pages: const <Map<String, Object?>>[],
    expectedError: 'IMP-004',
  );

  return SimulatedFixtureCatalog.parse(
    catalogJson: jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'catalogVersion': 't037-r2-in-memory',
      'evidenceClass': 'SIMULATED',
      'rights': <String, Object?>{
        'thirdPartyContent': false,
        'containsPersonalData': false,
        'rightsCleared': true,
      },
      'generator': <String, Object?>{
        'path': 't037-in-memory',
        'version': '1',
        'deterministic': true,
      },
      'fixtureCount': fixtures.length,
      'fixtures': fixtures,
    }),
    pdfBytesById: pdfBytesById,
    expectedOcrById: expectedOcrById,
  );
}

Map<String, Object?> _a4Page(int index) => _page(index, 595.28, 841.89, 0);

Map<String, Object?> _page(
  int index,
  double widthPt,
  double heightPt,
  int rotation,
) {
  return <String, Object?>{
    'index': index,
    'widthPt': widthPt,
    'heightPt': heightPt,
    'rotation': rotation,
  };
}

Uint8List _fixtureBytes(String id, int length) {
  final Uint8List bytes = Uint8List(length);
  const List<int> header = <int>[
    0x25,
    0x50,
    0x44,
    0x46,
    0x2d,
    0x31,
    0x2e,
    0x37,
    0x0a,
  ];
  final List<int> idBytes = id.codeUnits;
  for (int index = 0; index < length; index++) {
    if (index < header.length) {
      bytes[index] = header[index];
    } else {
      bytes[index] = idBytes[(index - header.length) % idBytes.length];
    }
  }
  return bytes;
}

/// T028-specific coverage declarations and scenario wiring.
final class _T028ImportConformanceSubject implements ImportConformanceSubject {
  _T028ImportConformanceSubject(this._catalog);

  final SimulatedFixtureCatalog _catalog;

  @override
  String get adapterLabel => 'SIMULATED T028 SimulatedDocumentImportAdapter';

  /// Expectations the shipped T028 adapter cannot exercise.
  ///
  /// These are declared, named, and skipped with these exact reasons. They are
  /// never reported as passing protection.
  static const Map<ImportConformanceExpectation, String> _notCovered =
      <ImportConformanceExpectation, String>{
        ImportConformanceExpectation.initialRevisionCommittedAndVerified:
            'T028 import creates SimulatedDocumentRecord(head: null) with an '
            'empty revisions map at simulated_import_adapter.dart:196-206; '
            'the initial revision is committed later by store.createDocument. '
            'contracts/platform-channel.md §3/§4 and '
            'contracts/storage-format.md §3.2 require the import commit to '
            'write and verify the initial revision and head before it returns. '
            'Owner: T038 channel import / T040 encrypted copy.',
        ImportConformanceExpectation.imageOnlyPdfAccepted:
            'the in-memory catalogue contains no image-only PDF; T028 selects '
            'whole fixtures and exposes no text/form-field metadata. '
            'Owner: T038/T039.',
        ImportConformanceExpectation.imp006PartialPages:
            'T028 always returns an empty pageFailures list; no fixture models '
            'a partially readable source. Owner: T038/T044.',
        ImportConformanceExpectation.imp004UnsupportedStructure:
            'the in-memory catalogue has no unsupported-structure fixture; '
            'T028 distinguishes only not-a-pdf (IMP-004 notPdf). '
            'Owner: T038/T039.',
        ImportConformanceExpectation.save003StagedWriteFailure:
            'SimulatedBackend.stageSource has no write-fault hook and '
            'SimulatedDocumentImportAdapter exposes no staged-write fault '
            'injection. Owner: T038/T040.',
        ImportConformanceExpectation.realSafPickerAndPasswordEntry:
            'T028 uses SimulatedImportPicker over the in-memory catalogue; it '
            'cannot launch Android SAF or accept/deny a password. '
            'Owner: T038.',
      };

  @override
  ImportConformanceDeclaration declare(
    ImportConformanceExpectation expectation,
  ) {
    final String? reason = _notCovered[expectation];
    if (reason != null) {
      return ImportConformanceDeclaration.notCovered(reason);
    }
    return const ImportConformanceDeclaration.satisfied();
  }

  @override
  Future<ImportConformanceObservation> observe(
    ImportConformanceExpectation expectation,
  ) async {
    switch (expectation) {
      case ImportConformanceExpectation.singlePageTextImport:
        return _importFixture('sf-004');
      case ImportConformanceExpectation.fivePageGeometryImport:
        return _importFixture('sf-003');
      case ImportConformanceExpectation.sourceImmutabilityAndVerification:
        return _immutabilityAndVerification();
      case ImportConformanceExpectation.verifyDetectsStagedCorruption:
        return _injectedStagedCorruption();
      case ImportConformanceExpectation.evidenceLabelledSimulated:
        return _importFixture('sf-004', includeDescriptor: true);
      case ImportConformanceExpectation.imp001PasswordProtected:
        return _importFixture('sf-protected');
      case ImportConformanceExpectation.imp002TruncatedInput:
        return _importFixture('sf-truncated');
      case ImportConformanceExpectation.imp004NotPdf:
        return _importFixture('sf-not-a-pdf');
      case ImportConformanceExpectation.imp005UnknownReason:
        return _importFixture('sf-does-not-exist');
      case ImportConformanceExpectation.imp007TooLarge:
        return _importFixture('sf-002', request: ImportRequest(maxBytes: 1024));
      case ImportConformanceExpectation.imp000Cancelled:
        return _cancelled();
      case ImportConformanceExpectation.save001StorageFull:
        return _importFixture('sf-002', maxTotalBytes: 1024);
      case ImportConformanceExpectation.save003StagedIntegrityMismatch:
        return _stagedIntegrityMismatch();
      case ImportConformanceExpectation.noRecordAfterRejection:
        return _noRecordAfterRejections();
      case ImportConformanceExpectation.initialRevisionCommittedAndVerified:
      case ImportConformanceExpectation.imageOnlyPdfAccepted:
      case ImportConformanceExpectation.imp006PartialPages:
      case ImportConformanceExpectation.imp004UnsupportedStructure:
      case ImportConformanceExpectation.save003StagedWriteFailure:
      case ImportConformanceExpectation.realSafPickerAndPasswordEntry:
        // The suite skips every one of these after `declare`; reaching here
        // would be a runner bug, not a pass.
        throw StateError(
          'not-covered expectation was executed: ${expectation.id}',
        );
    }
  }

  ({SimulatedBackend backend, SimulatedDocumentImportAdapter adapter}) _world({
    int? maxTotalBytes,
  }) {
    final SimulatedBackend backend = SimulatedBackend(
      maxTotalBytes: maxTotalBytes,
    );
    return (
      backend: backend,
      adapter: SimulatedDocumentImportAdapter(
        backend: backend,
        catalog: _catalog,
      ),
    );
  }

  Future<ImportConformanceObservation> _importFixture(
    String fixtureId, {
    ImportRequest? request,
    int? maxTotalBytes,
    bool includeDescriptor = false,
  }) async {
    final ({SimulatedBackend backend, SimulatedDocumentImportAdapter adapter})
    world = _world(maxTotalBytes: maxTotalBytes);
    final SimulatedFixture? fixture = _fixtureOrNull(fixtureId);
    world.adapter.picker.enqueueFixture(fixtureId);
    try {
      final ImportedSource source = await world.adapter.pickAndImport(
        request ?? ImportRequest(),
      );
      final SimulatedStagedSource? staged = world.backend.stagedSource(
        source.sourceId,
      );
      return _observation(
        world.backend,
        source: source,
        pickedBytes: fixture?.bytes,
        stagedBytes: staged?.bytes,
        stagedIsDistinctBuffer:
            fixture != null &&
            staged != null &&
            !identical(staged.bytes, fixture.bytes),
        expectedPages: fixture?.geometries ?? const <Object>[],
        expectedPageHashes: fixture == null
            ? const <int>[]
            : _pageHashes(fixture),
        descriptor: includeDescriptor ? world.adapter.descriptor : null,
      );
    } on Object catch (error) {
      return _observation(
        world.backend,
        error: error,
        pickedBytes: fixture?.bytes,
        expectedPages: fixture?.geometries ?? const <Object>[],
        expectedPageHashes: fixture == null
            ? const <int>[]
            : _pageHashes(fixture),
      );
    }
  }

  SimulatedFixture? _fixtureOrNull(String fixtureId) {
    try {
      return _catalog.fixture(fixtureId);
    } on ArgumentError {
      return null;
    }
  }

  Future<ImportConformanceObservation> _immutabilityAndVerification() async {
    final ({SimulatedBackend backend, SimulatedDocumentImportAdapter adapter})
    world = _world();
    final SimulatedFixture fixture = _catalog.fixture('sf-004');
    world.adapter.picker.enqueueFixture('sf-004');
    try {
      final ImportedSource source = await world.adapter.pickAndImport(
        ImportRequest(),
      );
      final SimulatedStagedSource? staged = world.backend.stagedSource(
        source.sourceId,
      );
      final SourceIntegrity integrity = await world.adapter.verifySource(
        source.sourceId,
      );
      final SourceIntegrity second = await world.adapter.verifySource(
        source.sourceId,
      );
      return _observation(
        world.backend,
        source: source,
        pickedBytes: fixture.bytes,
        stagedBytes: staged?.bytes,
        stagedIsDistinctBuffer:
            staged != null && !identical(staged.bytes, fixture.bytes),
        expectedPages: fixture.geometries,
        expectedPageHashes: _pageHashes(fixture),
        integrity: integrity,
        secondIntegrity: second,
        descriptor: world.adapter.descriptor,
      );
    } on Object catch (error) {
      return _observation(world.backend, error: error);
    }
  }

  Future<ImportConformanceObservation> _injectedStagedCorruption() async {
    final ({SimulatedBackend backend, SimulatedDocumentImportAdapter adapter})
    world = _world();
    final SimulatedFixture fixture = _catalog.fixture('sf-004');
    world.adapter.picker.enqueueFixture('sf-004');
    try {
      final ImportedSource source = await world.adapter.pickAndImport(
        ImportRequest(),
      );
      final SimulatedStagedSource? staged = world.backend.stagedSource(
        source.sourceId,
      );
      if (staged == null || staged.bytes.isEmpty) {
        throw StateError('T028 did not stage the imported source');
      }
      // Actually write corruption into the stored bytes; the suite asserts the
      // observed bytes differ from the picked bytes before trusting the result.
      staged.bytes[0] = staged.bytes[0] ^ 0xFF;
      final SourceIntegrity integrity = await world.adapter.verifySource(
        source.sourceId,
      );
      final SourceIntegrity second = await world.adapter.verifySource(
        source.sourceId,
      );
      return _observation(
        world.backend,
        source: source,
        pickedBytes: fixture.bytes,
        stagedBytes: staged.bytes,
        stagedIsDistinctBuffer: !identical(staged.bytes, fixture.bytes),
        expectedPages: fixture.geometries,
        expectedPageHashes: _pageHashes(fixture),
        integrity: integrity,
        secondIntegrity: second,
      );
    } on Object catch (error) {
      return _observation(world.backend, error: error);
    }
  }

  Future<ImportConformanceObservation> _stagedIntegrityMismatch() async {
    final ({SimulatedBackend backend, SimulatedDocumentImportAdapter adapter})
    world = _world();
    final SimulatedFixture fixture = _catalog.fixture('sf-004');
    // Inject storage authentication damage into the read-back copy; the stored
    // bytes stay unchanged. The adapter must map this to SAVE-003.
    world.backend.corruptNextStagedReadBack();
    world.adapter.picker.enqueueFixture('sf-004');
    try {
      final ImportedSource source = await world.adapter.pickAndImport(
        ImportRequest(),
      );
      return _observation(
        world.backend,
        source: source,
        pickedBytes: fixture.bytes,
        expectedPages: fixture.geometries,
        expectedPageHashes: _pageHashes(fixture),
      );
    } on Object catch (error) {
      return _observation(
        world.backend,
        error: error,
        pickedBytes: fixture.bytes,
        expectedPages: fixture.geometries,
        expectedPageHashes: _pageHashes(fixture),
      );
    }
  }

  Future<ImportConformanceObservation> _cancelled() async {
    final ({SimulatedBackend backend, SimulatedDocumentImportAdapter adapter})
    world = _world();
    world.adapter.picker.enqueueCancel();
    try {
      final ImportedSource source = await world.adapter.pickAndImport(
        ImportRequest(),
      );
      return _observation(world.backend, source: source);
    } on Object catch (error) {
      return _observation(world.backend, error: error);
    }
  }

  Future<ImportConformanceObservation> _noRecordAfterRejections() async {
    int documentCount = 0;
    int revisionCount = 0;
    int templateCount = 0;
    int artifactCount = 0;
    int stagedSourceCount = 0;

    Future<void> attempt(
      String fixtureId, {
      ImportRequest? request,
      int? maxTotalBytes,
      bool cancel = false,
    }) async {
      final ({SimulatedBackend backend, SimulatedDocumentImportAdapter adapter})
      world = _world(maxTotalBytes: maxTotalBytes);
      if (cancel) {
        world.adapter.picker.enqueueCancel();
      } else {
        world.adapter.picker.enqueueFixture(fixtureId);
      }
      try {
        await world.adapter.pickAndImport(request ?? ImportRequest());
      } on FeldexaException {
        // Expected: every attempt is a typed rejection or cancellation.
      }
      documentCount += world.backend.documents.length;
      revisionCount += world.backend.documents.values.fold<int>(
        0,
        (int sum, SimulatedDocumentRecord document) =>
            sum + document.revisions.length,
      );
      templateCount += world.backend.templates.length;
      artifactCount += world.backend.artifacts.length;
      stagedSourceCount += world.backend.stagedSources.length;
    }

    await attempt('sf-protected');
    await attempt('sf-truncated');
    await attempt('sf-not-a-pdf');
    await attempt('sf-does-not-exist');
    await attempt('sf-002', request: ImportRequest(maxBytes: 1024));
    await attempt('sf-002', maxTotalBytes: 1024);
    await attempt('', cancel: true);

    return ImportConformanceObservation(
      documentCount: documentCount,
      revisionCount: revisionCount,
      templateCount: templateCount,
      artifactCount: artifactCount,
      stagedSourceCount: stagedSourceCount,
    );
  }

  List<int> _pageHashes(SimulatedFixture fixture) => fixture.geometries
      .map((Object page) => page.hashCode)
      .toList(growable: false);

  ImportConformanceObservation _observation(
    SimulatedBackend backend, {
    ImportedSource? source,
    Object? error,
    List<int>? pickedBytes,
    List<int>? stagedBytes,
    bool? stagedIsDistinctBuffer,
    List<Object> expectedPages = const <Object>[],
    List<int> expectedPageHashes = const <int>[],
    SourceIntegrity? integrity,
    SourceIntegrity? secondIntegrity,
    CapabilityDescriptor? descriptor,
  }) {
    return ImportConformanceObservation(
      source: source,
      error: error,
      pickedBytes: pickedBytes,
      stagedBytes: stagedBytes,
      stagedIsDistinctBuffer: stagedIsDistinctBuffer,
      expectedPages: expectedPages,
      expectedPageHashes: expectedPageHashes,
      documentCount: backend.documents.length,
      revisionCount: backend.documents.values.fold<int>(
        0,
        (int sum, SimulatedDocumentRecord document) =>
            sum + document.revisions.length,
      ),
      headPresent: source == null
          ? null
          : backend.document(source.documentId)?.head != null,
      templateCount: backend.templates.length,
      artifactCount: backend.artifacts.length,
      stagedSourceCount: backend.stagedSources.length,
      integrity: integrity,
      secondIntegrity: secondIntegrity,
      descriptor: descriptor,
    );
  }
}
