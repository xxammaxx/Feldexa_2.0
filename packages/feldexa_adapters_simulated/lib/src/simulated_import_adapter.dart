// T028 SIMULATED document-import adapter.
//
// `research.md` D-16: import uses the fixed synthetic fixture catalogue,
// selected by fixture id; there is no real browser file upload. The adapter
// stages the fixture bytes into the simulated backend, reads them back, and
// returns only after the SHA-256 match succeeds, mirroring the real import
// port's "written, read back, hash-verified" contract (`contracts/ports.md`
// §2.1).
//
// Rejections use the canonical T014 exceptions:
//   * encrypted fixture  -> `ImportRejectedException(passwordProtected)`
//     (`IMP-001`);
//   * truncated fixture  -> `ImportRejectedException(truncated)` (`IMP-002`);
//   * non-PDF fixture    -> `ImportRejectedException(notPdf)` (`IMP-004`);
//   * picker cancellation -> `ImportCancelledException` (`IMP-000`) without
//     leaving any staged object.
//
// Every result is labelled `SIMULATED`. No claim of Android SAF behavior is
// made here.
library;

import 'dart:collection';
import 'dart:typed_data';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';

import 'simulated_backend.dart';
import 'simulated_contract.dart';
import 'simulated_digest.dart';
import 'simulated_fixtures.dart';

/// Deterministic fixture picker for the SIMULATED import adapter.
///
/// A real Web picker is a development affordance (a fixture list). This queue
/// is the deterministic seam: each [pick] returns the next queued fixture id,
/// or null for a user cancellation. An empty queue is a cancellation, so an
/// unconfigured adapter never invents an import.
final class SimulatedImportPicker {
  /// Creates an empty picker.
  SimulatedImportPicker();

  /// Pending selections in caller order; null is an explicit cancellation.
  final Queue<String?> _selections = Queue<String?>();

  /// Queues one fixture selection.
  void enqueueFixture(String fixtureId) {
    if (fixtureId.trim().isEmpty) {
      throw ArgumentError('fixtureId must not be empty');
    }
    _selections.add(fixtureId);
  }

  /// Queues one explicit user cancellation.
  void enqueueCancel() {
    _selections.add(null);
  }

  /// Whether no selection is pending.
  bool get isEmpty => _selections.isEmpty;

  /// Number of pending selections, including cancellations.
  int get pendingCount => _selections.length;

  /// Returns the next fixture id, or null for a cancellation.
  ///
  /// An empty queue is also a cancellation: an unconfigured adapter never
  /// invents an import.
  Future<String?> pick() async =>
      _selections.isEmpty ? null : _selections.removeFirst();

  /// Drops every pending selection.
  void clear() {
    _selections.clear();
  }
}

/// Initial user-visible title for an imported fixture aggregate.
///
/// The catalogue title is already synthetic metadata; a pathological title is
/// replaced by the stable fixture id so the document meta stays valid.
String _initialTitle(SimulatedFixture fixture) {
  final String title = fixture.title.trim();
  if (title.isNotEmpty && title.length <= 200) {
    return title;
  }
  return fixture.id;
}

/// Fixture-backed deterministic `DocumentImportPort`.
final class SimulatedDocumentImportAdapter implements DocumentImportPort {
  /// Creates the import adapter.
  SimulatedDocumentImportAdapter({
    required this.backend,
    required this.catalog,
    SimulatedImportPicker? picker,
  }) : picker = picker ?? SimulatedImportPicker();

  /// Shared simulated backend.
  final SimulatedBackend backend;

  /// Validated fixture catalogue.
  final SimulatedFixtureCatalog catalog;

  /// Deterministic fixture selection queue.
  final SimulatedImportPicker picker;

  static final CapabilityDescriptor _descriptor = simulatedDescriptor(
    kind: CapabilityKind.documentImport,
    adapterId: simulatedImportAdapterId,
    supportedFeatures: const <String>[
      'fixture-catalog',
      'hash-verified-source',
      'typed-rejections',
    ],
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  /// Evidence label carried by every result of this adapter.
  CapabilityEvidence get evidence => _descriptor.evidence;

  @override
  Future<ImportedSource> pickAndImport(ImportRequest request) async {
    final String? fixtureId = await picker.pick();
    if (fixtureId == null) {
      // FR-009 / `contracts/ports.md` §2.1: cancellation leaves no meta, head,
      // rev, src, or list entry. Nothing is staged before this point.
      throw ImportCancelledException();
    }
    final SimulatedFixture fixture;
    try {
      fixture = catalog.fixture(fixtureId);
    } on ArgumentError {
      // A selected id outside the committed catalogue is not a file error; it
      // is reported through the catalog's unknown-failure category.
      throw ImportRejectedException(ImportRejectionKind.unknownReason);
    }
    if (fixture.sizeBytes > request.maxBytes) {
      throw ImportRejectedException(ImportRejectionKind.tooLarge);
    }
    switch (fixture.status) {
      case SimulatedFixtureStatus.encrypted:
        throw ImportRejectedException(ImportRejectionKind.passwordProtected);
      case SimulatedFixtureStatus.truncated:
        throw ImportRejectedException(ImportRejectionKind.truncated);
      case SimulatedFixtureStatus.notAPdf:
        throw ImportRejectedException(ImportRejectionKind.notPdf);
      case SimulatedFixtureStatus.valid:
        break;
    }

    if (backend.globalKeyUnavailable) {
      // A document aggregate cannot become visible without its key material;
      // `SAVE-008` is the canonical global key-provider failure.
      throw KeystoreUnavailableException();
    }

    // `contracts/ports.md` §2.1 makes storage exhaustion a
    // `StorageFullException` (`SAVE-001`), and
    // `contracts/storage-format.md` §6 requires the capacity preflight before
    // the import writes anything. The shared backend model refuses before the
    // source or its document aggregate becomes visible, so existing sources
    // and aggregates are preserved.
    backend.ensureCapacityFor(fixture.sizeBytes);

    final String documentId = backend.context.newId();
    final String sourceId = backend.context.newId();
    final SimulatedStagedSource staged = backend.stageSource(
      sourceId: sourceId,
      fixture: fixture,
    );

    // Read back exactly what the store would return and verify the hash again.
    final Uint8List? readBack = backend.readStagedSource(sourceId);
    if (readBack == null ||
        readBack.length != fixture.sizeBytes ||
        sha256Hex(readBack) != staged.sha256) {
      // A failed read-back must not leave an orphaned source behind.
      backend.removeSourceIfUnreferenced(sourceId);
      throw ImportRejectedException(ImportRejectionKind.unreadable);
    }

    // Import creates the document aggregate so `ImportedSource.documentId` is
    // a real aggregate id (contract `ports.md` §2.1). A later
    // `createDocument` for the same source only applies its title.
    final SourceFileRef sourceRef = SourceFileRef(
      id: sourceId,
      sha256: staged.sha256,
      sizeBytes: readBack.length,
      pageCount: staged.pageCount,
      originalName: fixture.displayName,
      importedAt: staged.importedAt,
    );
    backend.putDocument(
      SimulatedDocumentRecord(
        id: documentId,
        title: _initialTitle(fixture),
        createdAt: staged.importedAt,
        updatedAt: staged.importedAt,
        source: sourceRef,
        head: null,
        lastDurableAt: null,
      ),
    );

    return ImportedSource(
      documentId: documentId,
      sourceId: sourceId,
      sha256: staged.sha256,
      sizeBytes: readBack.length,
      pageCount: staged.pageCount,
      pages: staged.pages,
      pageFailures: const <PageFailure>[],
      displayName: fixture.displayName,
      evidence: evidence,
    );
  }

  @override
  Future<SourceIntegrity> verifySource(String sourceId) async {
    final SimulatedStagedSource? staged = backend.stagedSource(sourceId);
    if (staged == null) {
      return SourceIntegrity(readable: false, evidence: evidence);
    }
    final Uint8List? bytes = backend.readStagedSource(sourceId);
    if (bytes == null) {
      return SourceIntegrity(
        readable: false,
        pageCount: staged.pageCount,
        evidence: evidence,
      );
    }
    final String actual = sha256Hex(bytes);
    final bool readable =
        actual == staged.sha256 && bytes.length == staged.bytes.length;
    return SourceIntegrity(
      readable: readable,
      actualSha256: actual,
      pageCount: staged.pageCount,
      evidence: evidence,
    );
  }
}
