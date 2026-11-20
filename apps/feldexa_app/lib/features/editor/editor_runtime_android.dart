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
//   * `AndroidIdClient` supplies the analysis-run UUIDv4.
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
import 'package:feldexa_ports/feldexa_ports.dart';

import 'editor_runtime.dart';

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
    raster: raster,
    ocr: ocr,
    ids: AndroidIdClient(),
    sourceBytes: sourceBytes,
    ownsOperations: ownsOperations,
  );
}

final class _AndroidEditorRuntime implements EditorRuntime {
  _AndroidEditorRuntime({
    required AndroidOperationClient operations,
    required AndroidStoreClient store,
    required AndroidPdfrxRasterClient raster,
    required AndroidOcrClient ocr,
    required AndroidIdClient ids,
    required Map<String, Uint8List> sourceBytes,
    required bool ownsOperations,
  }) : _operations = operations,
       _store = store,
       _raster = raster,
       _ocr = ocr,
       _ids = ids,
       _sourceBytes = sourceBytes,
       _ownsOperations = ownsOperations;

  final AndroidOperationClient _operations;
  final AndroidStoreClient _store;
  final AndroidPdfrxRasterClient _raster;
  final AndroidOcrClient _ocr;
  final AndroidIdClient _ids;
  final Map<String, Uint8List> _sourceBytes;
  final bool _ownsOperations;
  bool _disposed = false;

  @override
  PageRasterPort get raster => _raster;

  @override
  OcrPort? get ocr => _ocr;

  @override
  SecureStorePort get store => _store;

  @override
  IdPort get ids => _ids;

  @override
  Future<LoadedDocument> loadDocument(String documentId) async {
    _ensureOpen();
    final LoadedDocument loaded = await _store.loadDocument(documentId);
    // The raster port receives the immutable source id; the store receives the
    // document id. Remember only the loaded source's decrypted bytes in memory
    // so the already-open document can be rendered and analyzed. No path is
    // accepted or returned.
    _sourceBytes[loaded.meta.source.id] = loaded.sourceBytes;
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
