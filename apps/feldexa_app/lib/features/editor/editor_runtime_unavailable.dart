// Issue #217 Phase B1 fail-closed editor runtime for non-Android targets.
//
// Owner: `apps/feldexa_app/lib/features/editor/editor_runtime_unavailable.dart`
// (Phase B1). This is the default branch of `editor_runtime.dart` and also the
// explicit `dart.library.js_interop` branch. It imports no adapter package and
// constructs no simulated substitute.
//
// The app's Web surface is a development surface, not a production editor
// target. Loading or saving a revision therefore fails closed with the typed
// `UnsupportedOperationException`. The editor keeps the already-imported
// viewer available through its separate source-bytes closure and exposes only
// a content-free internal state; no document, suggestion, revision, or
// evidence claim is fabricated. This file is not an evidence claim of any
// class.

import 'package:feldexa_ports/feldexa_ports.dart';

import 'editor_runtime.dart';

/// Builds the fail-closed non-Android editor runtime.
EditorRuntime createEditorRuntime() => const _UnavailableEditorRuntime();

/// Builds the same fail-closed runtime for callers that need an explicit
/// default, such as an `ImportRuntime` composed without an editor factory.
EditorRuntime createUnavailableEditorRuntime() =>
    const _UnavailableEditorRuntime();

final class _UnavailableEditorRuntime implements EditorRuntime {
  const _UnavailableEditorRuntime();

  static Never _unavailable() => throw UnsupportedOperationException();

  @override
  PageRasterPort get raster => _unavailable();

  @override
  OcrPort? get ocr => _unavailable();

  @override
  SecureStorePort get store => _unavailable();

  @override
  IdPort get ids => _unavailable();

  @override
  ClockPort get clock => _unavailable();

  @override
  Future<LoadedDocument> loadDocument(String documentId) async =>
      _unavailable();

  @override
  Future<StoredMeta> saveRevision(SaveRevisionRequest request) async =>
      _unavailable();

  @override
  Future<void> dispose() async {}

  @override
  String toString() => 'EditorRuntime.unavailable';
}
