// ignore_for_file: implementation_imports

// Issue #217 Phase B1 fail-closed editor runtime for non-Android targets.
//
// Owner: `apps/feldexa_app/lib/features/editor/editor_runtime_unavailable.dart`
// (Phase B1). This is the default branch of `editor_runtime.dart` and also the
// explicit `dart.library.js_interop` branch. It imports no adapter package and
// constructs no simulated substitute.
//
// The app's Web surface is a development surface, not a production editor
// target. Loading or saving a revision therefore fails closed with the typed
// `UnsupportedOperationException`. The export/delivery ports and the
// `platform.sensitiveRoute` capability fail closed the same way: this runtime
// cannot produce a verified artifact, cannot hand one to the platform, and must
// never report a screenshot protection it did not apply. The editor keeps the
// already-imported viewer available through its separate source-bytes closure
// and exposes only a content-free internal state; no document, suggestion,
// revision, or evidence claim is fabricated. This file is not an evidence claim
// of any class.

import 'package:feldexa_application/src/recognition/raster_page_stage_runner.dart'
    show RecognitionExecution;
import 'package:feldexa_ports/feldexa_ports.dart';

import '../export/export_progress.dart';
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
  PdfExportPort get export => _unavailable();

  /// Reports no progress and cancels nothing instead of throwing: the export
  /// surface of `§10` point 3 must stay renderable, and this runtime has no
  /// operation to cancel anyway (its export port fails closed first).
  @override
  ExportOperationControl get exportOperation =>
      const UnavailableExportOperationControl();

  @override
  DeliveryPort get delivery => _unavailable();

  /// Fail-closed by design: there is no window to protect on this target, so
  /// the runtime reports "not protected" by throwing instead of returning
  /// `false` or, worse, `true`.
  @override
  Future<bool> setSensitiveRoute(SensitiveRoute route) async => _unavailable();

  /// The browser build has no worker isolates and no productive editor; the
  /// stage runner's browser variant runs the entry on the single web isolate.
  /// The mode stays `offIsolate` so no composition claims an inline production
  /// path.
  @override
  RecognitionExecution get recognitionExecution =>
      RecognitionExecution.offIsolate;

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
