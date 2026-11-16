// Shared T028 test support.
//
// Test-only helpers load the committed SIMULATED fixture catalogue through the
// canonical T011 loader and compose the six adapters over one backend. Nothing
// here claims EMULATOR or DEVICE evidence.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:feldexa_testkit/io.dart';

/// The committed fixture catalogue plus the adapter world used by a test.
final class SimulatedTestWorld {
  SimulatedTestWorld._({
    required this.catalog,
    required this.backend,
    required this.importAdapter,
    required this.rasterAdapter,
    required this.ocrAdapter,
    required this.storeAdapter,
    required this.exportAdapter,
    required this.deliveryAdapter,
  });

  /// Loads the canonical fixtures and creates one backend.
  static Future<SimulatedTestWorld> create({int? maxTotalBytes}) async {
    final SimulatedFixtureCatalog catalog = await loadCatalog();
    final SimulatedBackend backend = SimulatedBackend(
      maxTotalBytes: maxTotalBytes,
    );
    return SimulatedTestWorld._(
      catalog: catalog,
      backend: backend,
      importAdapter: SimulatedDocumentImportAdapter(
        backend: backend,
        catalog: catalog,
      ),
      rasterAdapter: SimulatedPageRasterAdapter(backend: backend),
      ocrAdapter: SimulatedOcrAdapter(backend: backend, catalog: catalog),
      storeAdapter: SimulatedSecureStoreAdapter(backend: backend),
      exportAdapter: SimulatedPdfExportAdapter(backend: backend),
      deliveryAdapter: SimulatedDeliveryAdapter(backend: backend),
    );
  }

  /// Parsed fixture catalogue.
  final SimulatedFixtureCatalog catalog;

  /// Shared deterministic state.
  final SimulatedBackend backend;

  /// Fixture-backed import adapter.
  final SimulatedDocumentImportAdapter importAdapter;

  /// Deterministic raster adapter.
  final SimulatedPageRasterAdapter rasterAdapter;

  /// Pre-authored OCR adapter.
  final SimulatedOcrAdapter ocrAdapter;

  /// In-memory store adapter.
  final SimulatedSecureStoreAdapter storeAdapter;

  /// Preview export adapter.
  final SimulatedPdfExportAdapter exportAdapter;

  /// Simulated delivery adapter.
  final SimulatedDeliveryAdapter deliveryAdapter;

  /// Imports [fixtureId] and returns the verified result.
  Future<ImportedSource> importFixture(String fixtureId) async {
    importAdapter.picker.enqueueFixture(fixtureId);
    return importAdapter.pickAndImport(ImportRequest());
  }

  /// Creates a source reference for an imported fixture.
  SourceFileRef sourceRefFor(ImportedSource imported) {
    return SourceFileRef(
      id: imported.sourceId,
      sha256: imported.sha256,
      sizeBytes: imported.sizeBytes,
      pageCount: imported.pageCount,
      originalName: imported.displayName,
      importedAt: backend.context.nowUtc(),
    );
  }

  /// Creates the document aggregate for [imported] and saves one revision.
  Future<({String documentId, String revisionId})> createSavedDocument(
    ImportedSource imported, {
    String title = 'Simulierte Meldebescheinigung',
  }) async {
    final SourceFileRef source = sourceRefFor(imported);
    final StoredMeta created = await storeAdapter.createDocument(
      CreateDocumentRequest(title: title, source: source),
    );
    final RevisionContent content = simpleRevisionContent(imported);
    final StoredMeta saved = await storeAdapter.saveRevision(
      SaveRevisionRequest(
        documentId: created.id,
        content: content,
        kind: RevisionKind.explicit,
      ),
    );
    return (documentId: saved.id, revisionId: saved.latestRevisionId!);
  }

  /// A minimal valid revision snapshot matching the imported page geometry.
  RevisionContent simpleRevisionContent(ImportedSource imported) {
    return RevisionContent(
      pages: <Page>[
        for (int index = 0; index < imported.pageCount; index++)
          Page(index: index, geometry: imported.pages[index]),
      ],
      fieldOrder: const <String>[],
    );
  }

  /// Builds a one-page export plan against a saved document revision.
  ExportPlan buildExportPlan({
    required ImportedSource imported,
    required String documentId,
    required String revisionId,
    required List<ExportOp> ops,
    String? sourceSha256,
  }) {
    return ExportPlan(
      documentId: documentId,
      revisionId: revisionId,
      sourceSha256: sourceSha256 ?? imported.sha256,
      pageCount: 1,
      evidenceClass: 'simulated',
      font: ExportFont(
        family: 'NotoSans',
        regularAsset: 'assets/fonts/NotoSans-Regular.ttf',
        boldAsset: 'assets/fonts/NotoSans-Bold.ttf',
        metricsVersion: 'noto-sans-2.013-v1',
      ),
      pages: <ExportPage>[
        ExportPage(index: 0, geometry: imported.pages.first, ops: ops),
      ],
      info: ExportPlanInfo(emptyFieldCount: 0, unresolvedSuggestionCount: 0),
    );
  }
}

/// Loads and parses the committed SIMULATED fixture catalogue.
Future<SimulatedFixtureCatalog> loadCatalog() async {
  final FixtureCheckout checkout = FixtureCheckout.locate();
  final loader = await checkout.openLoader();
  final Map<String, Uint8List> pdfBytes = <String, Uint8List>{};
  final Map<String, Map<String, Object?>> expectedOcr =
      <String, Map<String, Object?>>{};
  for (final descriptor in loader.catalog.fixtures) {
    pdfBytes[descriptor.id] = (await loader.load(descriptor.id)).bytes;
    if (descriptor.expectedOcr != null) {
      expectedOcr[descriptor.id] = await loader.loadExpectedOcr(descriptor.id);
    }
  }
  final String catalogJson = await File(
    '${checkout.canonicalDevDirectory}/catalog.json',
  ).readAsString();
  return SimulatedFixtureCatalog.parse(
    catalogJson: catalogJson,
    pdfBytesById: pdfBytes,
    expectedOcrById: expectedOcr,
  );
}

/// Loads the bundled Noto Sans Regular bytes for an export preview test.
Future<Uint8List> loadNotoSansRegular() async {
  final FixtureCheckout checkout = FixtureCheckout.locate();
  return File(
    '${checkout.rootDirectory}/apps/feldexa_app/assets/fonts/'
    'NotoSans-Regular.ttf',
  ).readAsBytes();
}
