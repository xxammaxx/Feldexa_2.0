// ignore_for_file: implementation_imports

// A private field cannot use an initializing formal with a public named
// parameter; the explicit initializers in the private state constructor are
// intentional.
// ignore_for_file: prefer_initializing_formals
//
// Issue #217 Phase B1 Android editor runtime composition.
//
// Owner: `apps/feldexa_app/lib/features/editor/editor_runtime_android.dart`
// (Phase B1). Selected only by the conditional import in
// `editor_runtime.dart` on `dart.library.io` targets; the Web build never
// resolves this file or the `feldexa_adapters_android` package.
//
// This file composes the existing T027 thin clients; it does not create a
// second platform channel, store, or orchestrator:
//   * one `AndroidOperationClient` owns the result stream;
//   * `AndroidStoreClient` is the verified revision/source path;
//   * `AndroidPdfrxRasterClient` renders the analysis raster from source bytes
//     that were loaded through that store;
//   * `AndroidOcrClient` receives the same `RasterImage` object when the Phase A
//     pipeline has a tight raster, so its page-size resolver can use
//     `AndroidPdfrxRasterClient.pageSizeOf(image)` identity;
//   * `AndroidIdClient` supplies the analysis-run UUIDv4;
//   * `AndroidPdfExportClient`/`AndroidDeliveryClient` are the export and
//     delivery ports of the same session, sharing this operation client;
//   * `platform.sensitiveRoute` (contract §11 point 7) sets or clears
//     `FLAG_SECURE` on the host window.
//
// Source bytes are resolved only from the in-memory cache populated by
// `loadDocument`. Before a document is loaded, or for any other source id, the
// resolver returns null and rendering fails closed. No path, URI, title, or
// source content is logged or retained after `dispose`.
//
// `createEditorRuntime()` creates and owns its operation client. The import
// composition may instead call `createAndroidEditorRuntime()` with its existing
// operation client and store; the runtime then leaves those shared clients
// alive when the editor closes.

import 'dart:typed_data';

import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:feldexa_application/src/recognition/raster_page_stage_runner.dart'
    show RecognitionExecution;
import 'package:feldexa_core/feldexa_core.dart' show PageGeometry;
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:pdfrx/pdfrx.dart';

import 'editor_runtime.dart';

/// Content-free integration diagnostic marker for the T071A editor runtime.
///
/// Only the marker name, page index, raster dimensions, and a stable error type
/// name are printed. No source id, path, URI, dictionary key, or document
/// content can pass through this helper.
void _runtimeDiagnostic(String message) {
  if (kDebugMode) {
    debugPrint('T071A_DIAG_$message');
  }
}

/// Builds a standalone Android editor runtime.
///
/// The runtime owns the operation client it creates and disposes it from
/// [EditorRuntime.dispose].
EditorRuntime createEditorRuntime() {
  final AndroidOperationClient operations = AndroidOperationClient();
  final AndroidStoreClient store = AndroidStoreClient(operations: operations);
  return createAndroidEditorRuntime(
    operations: operations,
    store: store,
    ownsOperations: true,
  );
}

/// Builds an Android editor runtime over already-composed shared clients.
///
/// [ownsOperations] must be false when [operations] is owned by a longer-lived
/// composition such as the import runtime. The editor then disposes only its
/// own raster and OCR state.
EditorRuntime createAndroidEditorRuntime({
  required AndroidOperationClient operations,
  required AndroidStoreClient store,
  bool ownsOperations = false,
}) {
  final Map<String, Uint8List> sourceBytes = <String, Uint8List>{};
  late final AndroidPdfrxRasterClient raster;
  raster = AndroidPdfrxRasterClient(
    sourceBytes: (String sourceId) async => sourceBytes[sourceId],
  );
  final AndroidOcrClient ocr = AndroidOcrClient(
    operations: operations,
    pageSizeResolver: (RasterImage image) {
      // Identity lookup only: the Phase A pipeline passes the rendered object
      // unchanged for a tight raster. A rebuilt padded raster has no entry, so
      // the client fails closed instead of inventing a page size.
      final ({double widthPt, double heightPt})? size = raster.pageSizeOf(
        image,
      );
      if (size == null) {
        throw UnsupportedOperationException();
      }
      return size;
    },
  );
  return _AndroidEditorRuntime(
    operations: operations,
    store: store,
    raster: kDebugMode ? _DiagnosticRasterPort(raster) : raster,
    ocr: kDebugMode ? _DiagnosticOcrPort(ocr) : ocr,
    export: AndroidPdfExportClient(operations: operations),
    delivery: AndroidDeliveryClient(),
    ids: AndroidIdClient(),
    clock: const AndroidClockClient(),
    sourceBytes: sourceBytes,
    ownsOperations: ownsOperations,
  );
}

/// Debug-only raster decorator that reports content-free analysis stage calls.
final class _DiagnosticRasterPort implements PageRasterPort {
  const _DiagnosticRasterPort(this._inner);

  final PageRasterPort _inner;

  @override
  CapabilityDescriptor get descriptor => _inner.descriptor;

  @override
  Future<PageGeometry> pageDimensions(String sourceId, int pageIndex) {
    return _inner.pageDimensions(sourceId, pageIndex);
  }

  @override
  Future<RasterImage> renderPage(RasterRequest request) async {
    _runtimeDiagnostic(
      'RASTER_START:P=${request.pageIndex}:SCALE=${request.scale}:FORMAT=${request.format.name}',
    );
    try {
      final RasterImage image = await _inner.renderPage(request);
      _runtimeDiagnostic(
        'RASTER_OK:P=${request.pageIndex}:W=${image.width}:H=${image.height}',
      );
      return image;
    } catch (error) {
      _runtimeDiagnostic(
        'RASTER_FAIL:P=${request.pageIndex}:TYPE=${error.runtimeType}',
      );
      rethrow;
    }
  }

  @override
  Future<void> evict(String sourceId) => _inner.evict(sourceId);
}

/// Debug-only OCR decorator that reports content-free analysis stage calls.
final class _DiagnosticOcrPort implements OcrPort {
  const _DiagnosticOcrPort(this._inner);

  final OcrPort _inner;

  @override
  CapabilityDescriptor get descriptor => _inner.descriptor;

  @override
  Future<List<OcrBlock>> recognize(OcrRequest request) async {
    _runtimeDiagnostic('OCR_START:P=${request.pageIndex}');
    try {
      final List<OcrBlock> blocks = await _inner.recognize(request);
      _runtimeDiagnostic(
        'OCR_OK:P=${request.pageIndex}:BLOCKS=${blocks.length}',
      );
      return blocks;
    } catch (error) {
      _runtimeDiagnostic(
        'OCR_FAIL:P=${request.pageIndex}:TYPE=${error.runtimeType}',
      );
      rethrow;
    }
  }

  @override
  Future<void> dispose() => _inner.dispose();
}

final class _AndroidEditorRuntime implements EditorRuntime {
  _AndroidEditorRuntime({
    required AndroidOperationClient operations,
    required AndroidStoreClient store,
    required PageRasterPort raster,
    required OcrPort ocr,
    required PdfExportPort export,
    required DeliveryPort delivery,
    required AndroidIdClient ids,
    required AndroidClockClient clock,
    required Map<String, Uint8List> sourceBytes,
    required bool ownsOperations,
  }) : _operations = operations,
       _store = store,
       _raster = raster,
       _ocr = ocr,
       _export = export,
       _delivery = delivery,
       _ids = ids,
       _clock = clock,
       _sourceBytes = sourceBytes,
       _ownsOperations = ownsOperations;

  final AndroidOperationClient _operations;
  final AndroidStoreClient _store;
  final PageRasterPort _raster;
  final OcrPort _ocr;
  final PdfExportPort _export;
  final DeliveryPort _delivery;
  final AndroidIdClient _ids;
  final AndroidClockClient _clock;
  final Map<String, Uint8List> _sourceBytes;
  final bool _ownsOperations;
  bool _disposed = false;

  static const MethodChannel _sensitiveRouteChannel = MethodChannel(
    'de.feldexa/platform',
  );

  @override
  PageRasterPort get raster => _raster;

  @override
  OcrPort? get ocr => _ocr;

  @override
  SecureStorePort get store => _store;

  @override
  IdPort get ids => _ids;

  @override
  ClockPort get clock => _clock;

  @override
  PdfExportPort get export => _export;

  @override
  DeliveryPort get delivery => _delivery;

  /// Sets or clears `FLAG_SECURE` through the existing platform channel.
  ///
  /// The native side applies the flag on the main thread and answers with the
  /// flag state it read back; this method returns that answer unchanged. A
  /// reply without a boolean `secure` field is a malformed contract answer and
  /// throws [FormatException], so an unknown state is never reported as
  /// "protected".
  @override
  Future<bool> setSensitiveRoute(SensitiveRoute route) async {
    _ensureOpen();
    final Map<String, Object?> data = androidEnvelopeData(
      await _sensitiveRouteChannel.invokeMethod<Object?>(
        'platform.sensitiveRoute',
        <String, Object?>{'schemaVersion': 1, 'route': route.wireName},
      ),
      method: 'platform.sensitiveRoute',
    );
    final Object? secure = data['secure'];
    if (secure is! bool) {
      throw const FormatException('Invalid platform.sensitiveRoute reply');
    }
    return secure;
  }

  /// The production Android composition runs the recognition stage in a worker
  /// isolate, so the synchronous detector cannot block the UI isolate.
  @override
  RecognitionExecution get recognitionExecution =>
      RecognitionExecution.offIsolate;

  @override
  Future<LoadedDocument> loadDocument(String documentId) async {
    _ensureOpen();
    // T071A correction: initialize pdfrx/PDFium once before the first
    // protected load completes. The viewer and the raster analysis both open
    // the loaded bytes, so this keeps engine startup on the existing load
    // path. It is defensive and idempotent, not the proven root cause of the
    // observed stall; that is a synchronous recognition detector.
    _runtimeDiagnostic('RUNTIME_LOAD_START');
    try {
      await pdfrxFlutterInitialize();
    } catch (error) {
      _runtimeDiagnostic('RUNTIME_LOAD_FAIL:TYPE=${error.runtimeType}');
      rethrow;
    }
    _runtimeDiagnostic('RUNTIME_PDFRX_READY');
    final LoadedDocument loaded = await _store.loadDocument(documentId);
    // The raster port receives the immutable source id; the store receives the
    // document id. Remember only the loaded source's decrypted bytes in memory
    // so the already-open document can be rendered and analyzed. No path is
    // accepted or returned.
    _sourceBytes[loaded.meta.source.id] = loaded.sourceBytes;
    _runtimeDiagnostic(
      'RUNTIME_LOAD_OK:PAGES=${loaded.content.pageCount}:BYTES=${loaded.sourceBytes.isEmpty ? 0 : 1}:SUGGESTIONS=${loaded.content.suggestions.length}',
    );
    return loaded;
  }

  @override
  Future<StoredMeta> saveRevision(SaveRevisionRequest request) async {
    _ensureOpen();
    return _store.saveRevision(request);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final List<String> sourceIds = _sourceBytes.keys.toList(growable: false);
    _sourceBytes.clear();
    for (final String sourceId in sourceIds) {
      try {
        await _raster.evict(sourceId);
      } catch (_) {
        // Teardown must not fail because one document handle was already gone.
      }
    }
    try {
      await _ocr.dispose();
    } catch (_) {
      // The channel service owns the recognizer lifetime.
    }
    if (_ownsOperations) {
      try {
        await _operations.dispose();
      } catch (_) {
        // Teardown must not throw into the widget lifecycle.
      }
    }
  }

  void _ensureOpen() {
    if (_disposed) {
      throw StateError('Editor runtime is disposed');
    }
  }

  @override
  String toString() => 'EditorRuntime.android';
}
