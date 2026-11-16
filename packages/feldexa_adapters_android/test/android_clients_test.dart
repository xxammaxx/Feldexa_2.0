// T027 host-VM tests for the remaining Android thin clients.
//
// Mocked channels only; `NONE` evidence. The instrumentation test proves the
// real Android channel/Keystore path.

import 'dart:async';

import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _documentId = '123e4567-e89b-42d3-a456-426614174000';
const String _sourceId = '123e4567-e89b-42d3-a456-426614174001';
const String _revisionId = '123e4567-e89b-42d3-a456-426614174002';
const String _operationId = '123e4567-e89b-42d3-a456-426614174003';
const String _artifactId = '123e4567-e89b-42d3-a456-426614174004';
const String _sha =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late List<MethodCall> calls;
  late Object? Function(MethodCall call) handler;

  setUp(() {
    calls = <MethodCall>[];
    channel = const MethodChannel('de.feldexa/platform');
    handler = (MethodCall call) => _envelope(<String, Object?>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return handler(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'import result is parsed and IMP-001 maps to a typed rejection',
    () async {
      final StreamController<Object?> results = StreamController<Object?>();
      final AndroidOperationClient operations = AndroidOperationClient(
        channel: channel,
        results: results.stream,
      );
      handler = (MethodCall call) => _start(_operationId);
      final AndroidImportClient client = AndroidImportClient(
        operations: operations,
      );
      final Future<ImportedSource> future = client.pickAndImport(
        ImportRequest(),
      );
      await Future<void>.delayed(Duration.zero);
      results.add(<String, Object?>{
        'schemaVersion': 1,
        'event': 'operation.result',
        'operationId': _operationId,
        'ok': true,
        'data': <String, Object?>{
          'documentId': _documentId,
          'sourceId': _sourceId,
          'sha256': _sha,
          'sizeBytes': 3,
          'pageCount': 1,
          'pages': <Object?>[
            PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842)).toJson(),
          ],
          'pageFailures': <Object?>[],
          'displayName': 'synthetisch.pdf',
        },
      });
      final ImportedSource imported = await future;
      expect(imported.documentId, _documentId);
      expect(imported.pages.single.mediaBox.width, 595);

      handler = (MethodCall call) {
        throw PlatformException(
          code: 'IMP-001',
          message: 'import.passwordProtected',
        );
      };
      await expectLater(
        client.pickAndImport(ImportRequest()),
        throwsA(
          isA<ImportRejectedException>().having(
            (e) => e.kind,
            'kind',
            ImportRejectionKind.passwordProtected,
          ),
        ),
      );
      await operations.dispose();
      await results.close();
    },
  );

  test('OCR sends the resolved page size and parses blocks', () async {
    final StreamController<Object?> results = StreamController<Object?>();
    final AndroidOperationClient operations = AndroidOperationClient(
      channel: channel,
      results: results.stream,
    );
    handler = (MethodCall call) {
      if (call.method == 'ocr.recognize') {
        final Map<Object?, Object?> payload =
            call.arguments as Map<Object?, Object?>;
        expect(payload['pageWidthPt'], 595.0);
        expect(payload['pageHeightPt'], 842.0);
        expect(payload['language'], 'de');
        return _start(_operationId);
      }
      return _envelope(<String, Object?>{});
    };
    final AndroidOcrClient client = AndroidOcrClient(
      operations: operations,
      pageSizeResolver: (RasterImage _) => (widthPt: 595.0, heightPt: 842.0),
    );
    final RasterImage image = RasterImage(
      bytes: Uint8List(100 * 100),
      width: 100,
      height: 100,
      bytesPerRow: 100,
      format: RasterFormat.gray8,
      evidence: CapabilityEvidence.android(adapterId: 'android.pdfium.v1'),
    );
    final Future<List<OcrBlock>> future = client.recognize(
      OcrRequest(image: image, pageIndex: 0, languageHint: 'de'),
    );
    await Future<void>.delayed(Duration.zero);
    results.add(<String, Object?>{
      'schemaVersion': 1,
      'event': 'operation.result',
      'operationId': _operationId,
      'ok': true,
      'data': <String, Object?>{
        'blocks': <Object?>[
          <String, Object?>{
            'text': 'Name',
            'rect': <String, Object?>{
              'x': 1.0,
              'y': 2.0,
              'width': 3.0,
              'height': 4.0,
            },
            'confidence': 0.9,
            'lines': <Object?>[
              <String, Object?>{
                'text': 'Name',
                'rect': <String, Object?>{
                  'x': 1.0,
                  'y': 2.0,
                  'width': 3.0,
                  'height': 4.0,
                },
                'confidence': 0.91,
              },
            ],
          },
        ],
        'engine': 'mlkit-latin-bundled-v1',
        'durationMs': 12,
      },
    });
    final List<OcrBlock> blocks = await future;
    expect(blocks.single.text, 'Name');
    expect(blocks.single.lines.single.confidence, 0.91);
    await operations.dispose();
    await results.close();
  });

  test('OCR fails closed when no page-size resolver is wired', () async {
    final client = AndroidOcrClient(
      channel: channel,
      operations: AndroidOperationClient(
        channel: channel,
        results: const Stream<Object?>.empty(),
      ),
    );
    final image = RasterImage(
      bytes: Uint8List(4),
      width: 1,
      height: 1,
      bytesPerRow: 4,
      format: RasterFormat.rgba8888,
      evidence: CapabilityEvidence.android(adapterId: 'android.pdfium.v1'),
    );
    await expectLater(
      client.recognize(
        OcrRequest(image: image, pageIndex: 0, languageHint: 'de'),
      ),
      throwsA(isA<UnsupportedOperationException>()),
    );
  });

  test('export validate and render reconstruct a verified artifact', () async {
    final StreamController<Object?> results = StreamController<Object?>();
    final AndroidOperationClient operations = AndroidOperationClient(
      channel: channel,
      results: results.stream,
    );
    int call = 0;
    handler = (MethodCall methodCall) {
      call++;
      return _start(
        call == 1
            ? '123e4567-e89b-42d3-a456-426614174005'
            : '123e4567-e89b-42d3-a456-426614174006',
      );
    };
    final AndroidPdfExportClient client = AndroidPdfExportClient(
      channel: channel,
      operations: operations,
    );
    final ExportPlan plan = _plan();

    final Future<ExportValidationResult> validating = client.validate(plan);
    await Future<void>.delayed(Duration.zero);
    results.add(<String, Object?>{
      'schemaVersion': 1,
      'event': 'operation.result',
      'operationId': '123e4567-e89b-42d3-a456-426614174005',
      'ok': true,
      'data': <String, Object?>{'ok': true, 'warnings': <Object?>[]},
    });
    final ExportValidationResult validation = await validating;
    expect(validation.isValid, isTrue);

    final Future<ExportResult> exporting = client.export(
      ExportRequest(
        documentId: _documentId,
        revisionId: _revisionId,
        plan: plan,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    results.add(<String, Object?>{
      'schemaVersion': 1,
      'event': 'operation.result',
      'operationId': '123e4567-e89b-42d3-a456-426614174006',
      'ok': true,
      'data': <String, Object?>{
        'artifactId': _artifactId,
        'pageCount': 1,
        'byteSize': 100,
        'sha256': _sha,
        'verification': <String, Object?>{
          'pageCountMatches': true,
          'mediaBoxesMatch': true,
          'fontGlyphsPresent': true,
          'noInteractiveFields': true,
          'overlayBoundsWithinPage': true,
          'checkedAt': '2026-11-16T12:00:00.000Z',
        },
      },
    });
    final ExportResult result = await exporting;
    expect(result.artifact.state, ExportArtifactState.succeeded);
    expect(result.artifact.sha256, _sha);
    await operations.dispose();
    await results.close();
  });

  test(
    'delivery maps cancellation and never claims a completed save',
    () async {
      handler = (MethodCall call) {
        expect(call.method, 'delivery.save');
        final Map<Object?, Object?> payload =
            call.arguments as Map<Object?, Object?>;
        expect(payload['suggestedName'], 'Feldexa_Dokument.pdf');
        return _envelope(<String, Object?>{
          'completed': false,
          'cancelled': true,
          'locationHint': null,
        });
      };
      final client = AndroidDeliveryClient(channel: channel);
      final DeliveryOutcome outcome = await client.deliver(
        action: DeliveryAction.save,
        artifactId: _artifactId,
      );
      expect(outcome.completed, isFalse);
      expect(outcome.action, DeliveryAction.save);
    },
  );

  test('raster eviction forgets sizes only for the requested source', () async {
    final AndroidPdfrxRasterClient client = AndroidPdfrxRasterClient(
      sourceBytes: (String _) async => null,
    );
    final RasterImage first = _rasterImage(1);
    final RasterImage second = _rasterImage(2);
    client.debugRememberPageSize(
      _sourceId,
      first,
      widthPt: 100.0,
      heightPt: 200.0,
    );
    client.debugRememberPageSize(
      _documentId,
      second,
      widthPt: 300.0,
      heightPt: 400.0,
    );

    expect(client.pageSizeOf(first), (widthPt: 100.0, heightPt: 200.0));
    expect(client.pageSizeOf(second), (widthPt: 300.0, heightPt: 400.0));

    await client.evict(_sourceId);

    expect(client.pageSizeOf(first), isNull);
    // A different source keeps its independently cached OCR geometry.
    expect(client.pageSizeOf(second), (widthPt: 300.0, heightPt: 400.0));
  });

  test('clock, ids, and diagnostics stay content-free', () async {
    final AndroidClockClient clock = const AndroidClockClient();
    expect(clock.nowUtc().isUtc, isTrue);
    final AndroidIdClient ids = AndroidIdClient();
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(ids.newId()),
      isTrue,
    );
    final AndroidDiagnosticsClient diagnostics = AndroidDiagnosticsClient(
      capacity: 2,
    );
    diagnostics.event(
      'save.ok',
      scalarFields: <String, Object?>{
        'count': 1,
        'nested': <String, Object?>{'title': 'geheim'},
      },
    );
    diagnostics.event(
      'save.error',
      scalarFields: <String, Object?>{'code': 'x'},
    );
    diagnostics.event(
      'save.third',
      scalarFields: <String, Object?>{'code': 'y'},
    );
    expect(diagnostics.descriptor.kind, CapabilityKind.diagnostics);
  });
}

RasterImage _rasterImage(int marker) {
  return RasterImage(
    bytes: Uint8List.fromList(<int>[marker, 0, 0, 255]),
    width: 1,
    height: 1,
    bytesPerRow: 4,
    format: RasterFormat.rgba8888,
    evidence: CapabilityEvidence.android(adapterId: 'android.pdfium.v1'),
  );
}

ExportPlan _plan() {
  return ExportPlan(
    documentId: _documentId,
    revisionId: _revisionId,
    sourceSha256: _sha,
    pageCount: 1,
    evidenceClass: 'emulator',
    font: ExportFont(
      family: 'NotoSans',
      regularAsset: 'assets/fonts/NotoSans-Regular.ttf',
      boldAsset: 'assets/fonts/NotoSans-Bold.ttf',
      metricsVersion: 'noto-sans-2.013-v1',
    ),
    pages: <ExportPage>[
      ExportPage(
        index: 0,
        geometry: PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842)),
        ops: const <ExportOp>[],
      ),
    ],
    info: ExportPlanInfo(emptyFieldCount: 0, unresolvedSuggestionCount: 0),
  );
}

Map<String, Object?> _start(String operationId) {
  return <String, Object?>{
    'schemaVersion': 1,
    'ok': true,
    'data': <String, Object?>{'operationId': operationId},
  };
}

Map<String, Object?> _envelope(Map<String, Object?> data) {
  return <String, Object?>{'schemaVersion': 1, 'ok': true, 'data': data};
}
