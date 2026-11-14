// T013 port-interface and registry tests (host VM, evidence class NONE).
//
// These tests pin `contracts/ports.md` §2 and §4:
//   * all ten port interfaces are `PlatformCapability`s with the contract
//     method signatures, implemented here by deterministic fakes;
//   * `AdapterRegistry` exposes exactly one interface per capability and one
//     descriptor per capability, in `CapabilityKind` order;
//   * failures travel as the T014 typed exceptions, never as `null` results;
//   * the development registry reports simulated capabilities so a release
//     build can refuse it.
//
// No test here produces SIMULATED, EMULATOR, or DEVICE runtime evidence; the
// fakes return host-VM values only.

import 'dart:typed_data';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

List<CapabilityDescriptor> _descriptors(CapabilityEvidence evidence) {
  return <CapabilityDescriptor>[
    for (final CapabilityKind kind in CapabilityKind.values)
      CapabilityDescriptor(
        kind: kind,
        adapterId: evidence.adapterId,
        version: '1',
        isSimulated: evidence.simulated,
        evidence: evidence,
      ),
  ];
}

RasterImage _rasterImage() {
  return RasterImage(
    bytes: fixtureBytes(16),
    width: 2,
    height: 2,
    bytesPerRow: 8,
    format: RasterFormat.rgba8888,
    evidence: fixtureAndroidEvidence(adapterId: 'android.pdfium.v1'),
  );
}

StoredMeta _storedMeta({StoreKind kind = StoreKind.document}) {
  return StoredMeta(
    id: fixtureUuid(kind == StoreKind.document ? 2 : 31),
    kind: kind,
    title: kind == StoreKind.document ? 'Antrag' : 'Vorlage',
    createdAt: fixtureAt(),
    updatedAt: fixtureAt(1),
    latestRevisionId: fixtureUuid(3),
  );
}

final class _FakeImport implements DocumentImportPort {
  _FakeImport(this.descriptor, {this.cancel = false});

  @override
  final CapabilityDescriptor descriptor;

  final bool cancel;

  @override
  Future<ImportedSource> pickAndImport(ImportRequest request) async {
    if (cancel) {
      throw ImportCancelledException();
    }
    return ImportedSource(
      documentId: fixtureUuid(2),
      sourceId: fixtureUuid(1),
      sha256: fixtureSha256,
      sizeBytes: 1234,
      pageCount: 1,
      pages: <PageGeometry>[fixtureGeometry()],
      evidence: fixtureAndroidEvidence(),
    );
  }

  @override
  Future<SourceIntegrity> verifySource(String sourceId) async {
    return SourceIntegrity(
      readable: true,
      actualSha256: fixtureSha256,
      pageCount: 1,
      evidence: fixtureAndroidEvidence(adapterId: 'android.keystore.v1'),
    );
  }
}

final class _FakeRaster implements PageRasterPort {
  _FakeRaster(this.descriptor, {this.failRender = false});

  @override
  final CapabilityDescriptor descriptor;

  final bool failRender;

  @override
  Future<PageGeometry> pageDimensions(String sourceId, int pageIndex) async {
    return fixtureGeometry();
  }

  @override
  Future<RasterImage> renderPage(RasterRequest request) async {
    if (failRender) {
      throw RenderException(pageIndex: request.pageIndex);
    }
    return _rasterImage();
  }

  @override
  Future<void> evict(String sourceId) async {}
}

final class _FakeOcr implements OcrPort {
  _FakeOcr(this.descriptor);

  @override
  final CapabilityDescriptor descriptor;

  @override
  Future<List<OcrBlock>> recognize(OcrRequest request) async {
    return <OcrBlock>[
      OcrBlock(
        rect: fixtureRect(),
        text: 'Müller',
        confidence: 0.9,
        lines: <OcrLine>[
          OcrLine(rect: fixtureRect(), text: 'Müller', confidence: 0.9),
        ],
      ),
    ];
  }

  @override
  Future<void> dispose() async {}
}

final class _FakeStore implements SecureStorePort {
  _FakeStore(this.descriptor, {this.failWrites = false});

  @override
  final CapabilityDescriptor descriptor;

  final bool failWrites;

  @override
  Future<StoreStatus> status() async {
    return StoreStatus(
      keyAvailable: true,
      objectCount: 1,
      totalBytes: 4096,
      evidence: fixtureAndroidEvidence(adapterId: 'android.keystore.v1'),
    );
  }

  @override
  Future<StoredMeta> createDocument(CreateDocumentRequest request) async {
    return _storedMeta();
  }

  @override
  Future<StoredMeta> saveRevision(SaveRevisionRequest request) async {
    if (failWrites) {
      throw StorageFullException();
    }
    return _storedMeta();
  }

  @override
  Future<LoadedDocument> loadDocument(String documentId) async {
    return LoadedDocument(
      meta: fixtureDocumentMeta(),
      content: fixtureRevisionContent(),
      sourceBytes: fixtureBytes(16),
      evidence: fixtureAndroidEvidence(),
    );
  }

  @override
  Future<Uint8List> readSignature(String documentId, String assetId) async {
    return fixtureBytes(8);
  }

  @override
  Future<void> writeSignature(WriteSignatureRequest request) async {}

  @override
  Future<List<StoredMeta>> list(StoreKind kind) async {
    return <StoredMeta>[_storedMeta(kind: kind)];
  }

  @override
  Future<void> delete(
    StoreKind kind,
    String id,
    DeleteConfirmation confirmation,
  ) async {}

  @override
  Future<StoredMeta> createTemplate(CreateTemplateRequest request) async {
    return _storedMeta(kind: StoreKind.template);
  }

  @override
  Future<StoredMeta> saveTemplateVersion(
    SaveTemplateVersionRequest request,
  ) async {
    return _storedMeta(kind: StoreKind.template);
  }

  @override
  Future<LoadedTemplate> loadTemplate(
    String templateId, {
    String? versionId,
  }) async {
    return LoadedTemplate(
      template: fixtureStoredTemplate(),
      sourceBytes: fixtureBytes(16),
      evidence: fixtureAndroidEvidence(),
    );
  }

  @override
  Future<RecoveryStamp> recoveryStamp(String id, StoreKind kind) async {
    return RecoveryStamp(
      verifiedRevisionId: fixtureUuid(3),
      committedAt: fixtureAt(),
      headCorrupt: false,
      fellBackToOlderRevision: false,
    );
  }
}

final class _FakeExport implements PdfExportPort {
  _FakeExport(this.descriptor, {this.failExport = false});

  @override
  final CapabilityDescriptor descriptor;

  final bool failExport;

  @override
  Future<ExportValidation> validate(ExportPlan plan) async {
    return fixtureExportValidation();
  }

  @override
  Future<ExportResult> export(ExportRequest request) async {
    if (failExport) {
      throw ExportFailedException();
    }
    return ExportResult(
      artifact: fixtureExportArtifact(),
      evidence: fixtureAndroidEvidence(adapterId: 'android.pdfbox.v1'),
    );
  }

  @override
  Future<Uint8List> readArtifact(String artifactId) async {
    return fixtureBytes(16);
  }

  @override
  Future<void> deleteArtifact(String artifactId) async {}
}

final class _FakeDelivery implements DeliveryPort {
  _FakeDelivery(this.descriptor);

  @override
  final CapabilityDescriptor descriptor;

  @override
  Future<DeliveryOutcome> deliver({
    required DeliveryAction action,
    required String artifactId,
  }) async {
    return DeliveryOutcome(
      action: action,
      completed: true,
      userVisibleLocationHint: 'In „Downloads“ gespeichert',
      evidence: fixtureAndroidEvidence(),
    );
  }
}

final class _FakeLifecycle implements LifecyclePort {
  _FakeLifecycle(this.descriptor);

  @override
  final CapabilityDescriptor descriptor;

  final List<AppLifecycleSignal> sequence = const <AppLifecycleSignal>[
    AppLifecycleSignal.resumed,
    AppLifecycleSignal.paused,
  ];

  @override
  Stream<AppLifecycleSignal> get signals {
    return Stream<AppLifecycleSignal>.fromIterable(sequence);
  }
}

final class _FakeClock implements ClockPort {
  _FakeClock(this.descriptor);

  @override
  final CapabilityDescriptor descriptor;

  @override
  DateTime nowUtc() => fixtureAt();
}

final class _FakeIds implements IdPort {
  _FakeIds(this.descriptor);

  @override
  final CapabilityDescriptor descriptor;

  int _next = 1;

  @override
  String newId() => fixtureUuid(_next++);

  @override
  String newIdempotencyKey() => 'idempotency-${_next++}';
}

final class _FakeDiagnostics implements DiagnosticsPort {
  _FakeDiagnostics(this.descriptor);

  @override
  final CapabilityDescriptor descriptor;

  final List<String> codes = <String>[];
  final List<Map<String, Object?>> fields = <Map<String, Object?>>[];

  @override
  void event(String code, {Map<String, Object?> scalarFields = const {}}) {
    codes.add(code);
    fields.add(scalarFields);
  }

  @override
  Future<void> clear() async {
    codes.clear();
    fields.clear();
  }
}

final class _FakeRegistry implements AdapterRegistry {
  _FakeRegistry({
    required this.isDevelopmentEnvironment,
    required List<CapabilityDescriptor> descriptors,
  }) : _descriptors = List<CapabilityDescriptor>.unmodifiable(descriptors) {
    if (_descriptors.length != CapabilityKind.values.length) {
      throw ArgumentError('a registry needs one descriptor per capability');
    }
    _import = _FakeImport(_descriptors[0]);
    _raster = _FakeRaster(_descriptors[1]);
    _ocr = _FakeOcr(_descriptors[2]);
    _store = _FakeStore(_descriptors[3]);
    _export = _FakeExport(_descriptors[4]);
    _delivery = _FakeDelivery(_descriptors[5]);
    _lifecycle = _FakeLifecycle(_descriptors[6]);
    _clock = _FakeClock(_descriptors[7]);
    _ids = _FakeIds(_descriptors[8]);
    _diagnostics = _FakeDiagnostics(_descriptors[9]);
  }

  @override
  final bool isDevelopmentEnvironment;

  final List<CapabilityDescriptor> _descriptors;

  late final _FakeImport _import;
  late final _FakeRaster _raster;
  late final _FakeOcr _ocr;
  late final _FakeStore _store;
  late final _FakeExport _export;
  late final _FakeDelivery _delivery;
  late final _FakeLifecycle _lifecycle;
  late final _FakeClock _clock;
  late final _FakeIds _ids;
  late final _FakeDiagnostics _diagnostics;

  @override
  DocumentImportPort get import => _import;

  @override
  PageRasterPort get raster => _raster;

  @override
  OcrPort get ocr => _ocr;

  @override
  SecureStorePort get store => _store;

  @override
  PdfExportPort get export => _export;

  @override
  DeliveryPort get delivery => _delivery;

  @override
  LifecyclePort get lifecycle => _lifecycle;

  @override
  ClockPort get clock => _clock;

  @override
  IdPort get ids => _ids;

  @override
  DiagnosticsPort get diagnostics => _diagnostics;

  @override
  bool get hasSimulatedCapabilities {
    return _descriptors.any((CapabilityDescriptor value) => value.isSimulated);
  }

  @override
  List<CapabilityDescriptor> get descriptors => _descriptors;
}

void main() {
  group('AdapterRegistry contract', () {
    test('exposes one interface and descriptor per capability in order', () {
      final _FakeRegistry registry = _FakeRegistry(
        isDevelopmentEnvironment: false,
        descriptors: _descriptors(fixtureAndroidEvidence()),
      );

      expect(registry.import, isA<DocumentImportPort>());
      expect(registry.raster, isA<PageRasterPort>());
      expect(registry.ocr, isA<OcrPort>());
      expect(registry.store, isA<SecureStorePort>());
      expect(registry.export, isA<PdfExportPort>());
      expect(registry.delivery, isA<DeliveryPort>());
      expect(registry.lifecycle, isA<LifecyclePort>());
      expect(registry.clock, isA<ClockPort>());
      expect(registry.ids, isA<IdPort>());
      expect(registry.diagnostics, isA<DiagnosticsPort>());
      expect(
        registry.descriptors.map((CapabilityDescriptor value) => value.kind),
        CapabilityKind.values,
      );
      expect(registry.descriptors, hasLength(10));
    });

    test('every port is a PlatformCapability with a matching descriptor', () {
      final _FakeRegistry registry = _FakeRegistry(
        isDevelopmentEnvironment: false,
        descriptors: _descriptors(fixtureAndroidEvidence()),
      );
      final List<PlatformCapability> capabilities = <PlatformCapability>[
        registry.import,
        registry.raster,
        registry.ocr,
        registry.store,
        registry.export,
        registry.delivery,
        registry.lifecycle,
        registry.clock,
        registry.ids,
        registry.diagnostics,
      ];

      expect(
        capabilities.map((PlatformCapability value) => value.descriptor.kind),
        CapabilityKind.values,
      );
      for (final PlatformCapability capability in capabilities) {
        expect(capability.descriptor.isSimulated, isFalse);
        expect(
          capability.descriptor.evidence.evidenceClass,
          EvidenceClass.none,
        );
      }
    });

    test('reports a development registry with simulated capabilities', () {
      final _FakeRegistry registry = _FakeRegistry(
        isDevelopmentEnvironment: true,
        descriptors: _descriptors(fixtureSimulatedEvidence()),
      );

      expect(registry.isDevelopmentEnvironment, isTrue);
      expect(registry.hasSimulatedCapabilities, isTrue);
      expect(
        registry.descriptors.every(
          (CapabilityDescriptor value) => value.isSimulated,
        ),
        isTrue,
      );
      expect(
        () => registry.descriptors.add(registry.descriptors.first),
        throwsUnsupportedError,
      );
    });
  });

  group('Port methods return contract values', () {
    late _FakeRegistry registry;

    setUp(() {
      registry = _FakeRegistry(
        isDevelopmentEnvironment: false,
        descriptors: _descriptors(fixtureAndroidEvidence()),
      );
    });

    test('DocumentImportPort stages a verified source', () async {
      final ImportedSource imported = await registry.import.pickAndImport(
        ImportRequest(),
      );
      final SourceIntegrity integrity = await registry.import.verifySource(
        fixtureUuid(1),
      );

      expect(imported.pageCount, 1);
      expect(imported.pages.single.mediaBox.width, 595);
      expect(integrity.readable, isTrue);
      expect(integrity.actualSha256, fixtureSha256);
      expect(integrity.evidence.evidenceClass, EvidenceClass.none);
      expect(integrity.evidence.simulated, isFalse);
    });

    test('PageRasterPort returns canonical geometry and pixels', () async {
      final PageGeometry geometry = await registry.raster.pageDimensions(
        fixtureUuid(1),
        0,
      );
      final RasterImage image = await registry.raster.renderPage(
        RasterRequest(
          sourceId: fixtureUuid(1),
          pageIndex: 0,
          scale: 200 / 72,
          format: RasterFormat.gray8,
        ),
      );
      await registry.raster.evict(fixtureUuid(1));

      expect(geometry.displaySize.width, greaterThan(0));
      expect(image.width, 2);
      expect(image.bytes, hasLength(16));
    });

    test('OcrPort returns blocks with canonical rectangles', () async {
      final List<OcrBlock> blocks = await registry.ocr.recognize(
        OcrRequest(image: _rasterImage(), pageIndex: 0, languageHint: 'de'),
      );
      await registry.ocr.dispose();

      final Rect rect = blocks.single.rect;
      expect(rect.width, 140);
      expect(blocks.single.lines, hasLength(1));
    });

    test('SecureStorePort reads, writes, lists, and recovers', () async {
      final StoreStatus status = await registry.store.status();
      final StoredMeta created = await registry.store.createDocument(
        CreateDocumentRequest(title: 'Antrag', source: fixtureSource()),
      );
      final StoredMeta saved = await registry.store.saveRevision(
        SaveRevisionRequest(
          documentId: fixtureUuid(2),
          content: fixtureRevisionContent(),
          kind: RevisionKind.autosave,
        ),
      );
      final LoadedDocument loaded = await registry.store.loadDocument(
        fixtureUuid(2),
      );
      final Uint8List signature = await registry.store.readSignature(
        fixtureUuid(2),
        fixtureUuid(40),
      );
      await registry.store.writeSignature(
        WriteSignatureRequest(
          documentId: fixtureUuid(2),
          assetId: fixtureUuid(40),
          bytes: fixtureBytes(8),
          sha256: fixtureSha256,
        ),
      );
      final List<StoredMeta> documents = await registry.store.list(
        StoreKind.document,
      );
      await registry.store.delete(
        StoreKind.document,
        fixtureUuid(2),
        DeleteConfirmation(title: 'Antrag', acknowledged: true),
      );
      final StoredMeta templateMeta = await registry.store.createTemplate(
        CreateTemplateRequest(
          title: 'Vorlage',
          source: fixtureSource(),
          pages: <Page>[fixturePage()],
          fieldOrder: <String>[],
        ),
      );
      final StoredMeta versionMeta = await registry.store.saveTemplateVersion(
        SaveTemplateVersionRequest(
          templateId: fixtureUuid(31),
          pageSnapshot: <Page>[fixturePage()],
        ),
      );
      final LoadedTemplate template = await registry.store.loadTemplate(
        fixtureUuid(31),
      );
      final RecoveryStamp stamp = await registry.store.recoveryStamp(
        fixtureUuid(2),
        StoreKind.document,
      );

      expect(status.keyAvailable, isTrue);
      expect(created.kind, StoreKind.document);
      expect(saved.kind, StoreKind.document);
      expect(loaded.meta.title, 'Antrag');
      expect(loaded.content.pageCount, 1);
      expect(signature, hasLength(8));
      expect(documents, hasLength(1));
      expect(templateMeta.kind, StoreKind.template);
      expect(versionMeta.kind, StoreKind.template);
      expect(template.template.version.versionNumber, 1);
      expect(stamp.headCorrupt, isFalse);
    });

    test(
      'PdfExportPort validates and returns the canonical artifact',
      () async {
        final ExportValidation validation = await registry.export.validate(
          fixtureExportPlan(),
        );
        final ExportResult result = await registry.export.export(
          ExportRequest(
            documentId: fixtureUuid(2),
            revisionId: fixtureUuid(3),
            plan: fixtureExportPlan(),
          ),
        );
        final Uint8List artifact = await registry.export.readArtifact(
          fixtureUuid(50),
        );
        await registry.export.deleteArtifact(fixtureUuid(50));

        expect(validation.warnings, isEmpty);
        expect(result.artifact.pageCount, 1);
        expect(result.evidence.evidenceClass, EvidenceClass.none);
        expect(result.evidence.simulated, isFalse);
        expect(artifact, hasLength(16));
      },
    );

    test('DeliveryPort reports a completed save', () async {
      final DeliveryOutcome outcome = await registry.delivery.deliver(
        action: DeliveryAction.save,
        artifactId: fixtureUuid(50),
      );

      expect(outcome.action, DeliveryAction.save);
      expect(outcome.completed, isTrue);
      expect(outcome.userVisibleLocationHint, 'In „Downloads“ gespeichert');
    });

    test('LifecyclePort emits the platform sequence', () async {
      await expectLater(
        registry.lifecycle.signals,
        emitsInOrder(<AppLifecycleSignal>[
          AppLifecycleSignal.resumed,
          AppLifecycleSignal.paused,
        ]),
      );
    });

    test('ClockPort and IdPort are deterministic seams', () {
      expect(registry.clock.nowUtc(), fixtureAt());
      expect(registry.clock.nowUtc().isUtc, isTrue);

      final String first = registry.ids.newId();
      final String second = registry.ids.newId();
      final String key = registry.ids.newIdempotencyKey();

      expect(first, fixtureUuid(1));
      expect(second, fixtureUuid(2));
      expect(key, 'idempotency-3');
    });

    test('DiagnosticsPort records only scalar fields', () async {
      final _FakeDiagnostics diagnostics =
          registry.diagnostics as _FakeDiagnostics;
      diagnostics.event(
        'save.completed',
        scalarFields: <String, Object?>{'durationMs': 12, 'pageCount': 1},
      );

      expect(diagnostics.codes, <String>['save.completed']);
      expect(diagnostics.fields.single, <String, Object?>{
        'durationMs': 12,
        'pageCount': 1,
      });

      await diagnostics.clear();
      expect(diagnostics.codes, isEmpty);
    });
  });

  group('Port failures use the T014 typed exceptions', () {
    test('cancellation throws ImportCancelledException, not null', () async {
      final _FakeImport port = _FakeImport(fixtureDescriptor(), cancel: true);

      await expectLater(
        port.pickAndImport(ImportRequest()),
        throwsA(isA<ImportCancelledException>()),
      );
    });

    test('a failed render throws RenderException', () async {
      final _FakeRaster port = _FakeRaster(
        fixtureDescriptor(kind: CapabilityKind.pageRaster),
        failRender: true,
      );

      await expectLater(
        port.renderPage(
          RasterRequest(
            sourceId: fixtureUuid(1),
            pageIndex: 2,
            scale: 1,
            format: RasterFormat.rgba8888,
          ),
        ),
        throwsA(
          isA<RenderException>().having(
            (RenderException error) => error.pageIndex,
            'pageIndex',
            2,
          ),
        ),
      );
    });

    test('a full store throws StorageFullException', () async {
      final _FakeStore port = _FakeStore(
        fixtureDescriptor(kind: CapabilityKind.secureStore),
        failWrites: true,
      );

      await expectLater(
        port.saveRevision(
          SaveRevisionRequest(
            documentId: fixtureUuid(2),
            content: fixtureRevisionContent(),
            kind: RevisionKind.explicit,
          ),
        ),
        throwsA(isA<StorageFullException>()),
      );
    });

    test('a failed export throws ExportFailedException', () async {
      final _FakeExport port = _FakeExport(
        fixtureDescriptor(kind: CapabilityKind.pdfExport),
        failExport: true,
      );

      await expectLater(
        port.export(
          ExportRequest(
            documentId: fixtureUuid(2),
            revisionId: fixtureUuid(3),
            plan: fixtureExportPlan(),
          ),
        ),
        throwsA(isA<ExportFailedException>()),
      );
    });
  });
}
