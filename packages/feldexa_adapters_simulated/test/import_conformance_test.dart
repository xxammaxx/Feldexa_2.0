// T037 import-contract conformance runner for the REAL T028 adapter.
//
// This test wires the reusable `feldexa_testkit` import-conformance suite to
// the shipped `SimulatedDocumentImportAdapter`, the real `SimulatedBackend`,
// and the committed synthetic fixture catalogue. Unlike the previous fake in
// `feldexa_ports/test/import_port_test.dart`, a change to the adapter's
// acceptance, cleanup, source-copying, or verification behaviour can make this
// runner fail.
//
// Host-VM only. Every result is `SIMULATED`; no Android, SAF, PDF-parser,
// encryption, emulator, or device evidence is produced.

import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:feldexa_testkit/feldexa_testkit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/simulated_world.dart';

void main() {
  late SimulatedFixtureCatalog catalog;

  setUpAll(() async {
    catalog = await loadCatalog();
  });

  final _T028ImportConformanceSubject subject = _T028ImportConformanceSubject(
    () => catalog,
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

/// T028-specific coverage declarations and scenario wiring.
final class _T028ImportConformanceSubject implements ImportConformanceSubject {
  _T028ImportConformanceSubject(this._catalog);

  final SimulatedFixtureCatalog Function() _catalog;

  @override
  String get adapterLabel => 'SIMULATED T028 SimulatedDocumentImportAdapter';

  /// Expectations the shipped T028 adapter cannot exercise.
  ///
  /// These are declared, named, and skipped with these exact reasons. They are
  /// never reported as passing protection.
  static const Map<ImportConformanceExpectation, String> _notCovered =
      <ImportConformanceExpectation, String>{
        ImportConformanceExpectation.imageOnlyPdfAccepted:
            'the committed SIMULATED fixture catalogue contains no '
            'image-only PDF; T028 selects whole fixtures and exposes no '
            'text/form-field metadata.',
        ImportConformanceExpectation.imp006PartialPages:
            'T028 always returns an empty pageFailures list; no fixture '
            'models a partially readable source.',
        ImportConformanceExpectation.imp004UnsupportedStructure:
            'the committed catalogue has no unsupported-structure fixture; '
            'T028 distinguishes only not-a-pdf (IMP-004 notPdf).',
        ImportConformanceExpectation.save003StagedWriteFailure:
            'SimulatedBackend.stageSource has no write-fault hook and '
            'SimulatedDocumentImportAdapter is outside this correction scope.',
        ImportConformanceExpectation.save003StagedIntegrityMismatch:
            'KNOWN T028 NON-CONFORMANCE: simulated_import_adapter.dart:177-182 '
            'maps a staged read-back/hash mismatch to '
            'ImportRejectedException(unreadable) IMP-002 instead of '
            'CorruptDataException SAVE-003; SimulatedBackend exposes no '
            'corruption hook and the adapter is outside this scope.',
        ImportConformanceExpectation.realSafPickerAndPasswordEntry:
            'T028 uses SimulatedImportPicker over the fixture catalogue; it '
            'cannot launch Android SAF or accept/deny a password.',
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
      case ImportConformanceExpectation.noRecordAfterRejection:
        return _noRecordAfterRejections();
      case ImportConformanceExpectation.imageOnlyPdfAccepted:
      case ImportConformanceExpectation.imp006PartialPages:
      case ImportConformanceExpectation.imp004UnsupportedStructure:
      case ImportConformanceExpectation.save003StagedWriteFailure:
      case ImportConformanceExpectation.save003StagedIntegrityMismatch:
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
        catalog: _catalog(),
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
    // An unknown fixture id is a deliberate IMP-005 probe: resolve what exists,
    // then let the adapter classify the missing selection itself.
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
      return _catalog().fixture(fixtureId);
    } on ArgumentError {
      return null;
    }
  }

  Future<ImportConformanceObservation> _immutabilityAndVerification() async {
    final ({SimulatedBackend backend, SimulatedDocumentImportAdapter adapter})
    world = _world();
    final SimulatedFixture fixture = _catalog().fixture('sf-004');
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
      );
    } on Object catch (error) {
      return _observation(world.backend, error: error);
    }
  }

  Future<ImportConformanceObservation> _injectedStagedCorruption() async {
    final ({SimulatedBackend backend, SimulatedDocumentImportAdapter adapter})
    world = _world();
    final SimulatedFixture fixture = _catalog().fixture('sf-004');
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
      templateCount: backend.templates.length,
      artifactCount: backend.artifacts.length,
      stagedSourceCount: backend.stagedSources.length,
      integrity: integrity,
      secondIntegrity: secondIntegrity,
      descriptor: descriptor,
    );
  }
}
