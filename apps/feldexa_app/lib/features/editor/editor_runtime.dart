// ignore_for_file: implementation_imports

// Issue #217 Phase B1 app-level editor runtime seam.
//
// Owner: `apps/feldexa_app/lib/features/editor/editor_runtime.dart` (Phase B1).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/contracts/platform-channel.md` §2.2,
//     §3, §4, §5, §6, §7, and §11 point 7;
//   * `specs/001-scanned-form-workflow/contracts/ports.md` §2.2, §2.3, §2.4,
//     §2.5, and §2.6;
//   * `specs/001-scanned-form-workflow/spec.md` FR-014, FR-017, FR-018,
//     FR-019, and FR-020;
//   * constitution Principles II, III, VI, VIII, and X.
//
// This is the editor's single platform-capability seam. It exposes the existing
// raster, OCR, secure-store, and id ports plus the two editor operations that
// must go through the same composed adapter set: loading the current revision
// and saving a new revision. The export flow adds the existing
// `PdfExportPort`/`DeliveryPort` and the `platform.sensitiveRoute` capability of
// §11 point 7; the export preview is reached from the editor session, so it
// reads the same composed adapters instead of composing a second set. It adds
// no second runtime, store, orchestrator, contract, or platform channel.
//
// The Android implementation is selected only on `dart.library.io` targets and
// composes the existing T027 thin clients. Every other target receives the
// fail-closed implementation: an editor can still show the imported viewer
// through the separate source-bytes closure, but no analysis or save is
// invented. There is no simulated substitute and no evidence claim here.
//
// No implementation accepts or returns a file path, URI, display name, or
// source bytes by path, and nothing in this seam logs document content.

import 'package:feldexa_application/src/recognition/raster_page_stage_runner.dart'
    show RecognitionExecution;
import 'package:feldexa_ports/feldexa_ports.dart';

import '../export/export_progress.dart';
import 'editor_runtime_unavailable.dart'
    if (dart.library.io) 'editor_runtime_android.dart'
    if (dart.library.js_interop) 'editor_runtime_unavailable.dart'
    as platform;

/// The document routes that must block screenshots and Recents thumbnails
/// (`contracts/platform-channel.md` §11 point 7).
///
/// The wire values are the exact `route` payload tokens of
/// `platform.sensitiveRoute`; [none] clears the protection.
enum SensitiveRoute {
  /// The editor route with a decrypted document on screen.
  editor('editor'),

  /// The export preview route showing a produced PDF.
  export('export'),

  /// No sensitive document route is visible; the platform flag is cleared.
  none('none');

  const SensitiveRoute(this.wireName);

  /// Stable channel token.
  final String wireName;

  /// The protection state this route requires.
  bool get requiresProtection => this != SensitiveRoute.none;
}

/// The platform capabilities the editor composition needs.
///
/// [raster] and [ocr] are the analysis ports consumed by the Phase A
/// `AnalyzeDocument` use case. [store] is the existing encrypted store; it is
/// exposed for later review/save work but this seam's [loadDocument] and
/// [saveRevision] are the editor's supported paths. [ids] supplies UUIDv4
/// identities such as the analysis-run id.
///
/// [recognitionExecution] is the capability the analysis pipeline consumes to
/// choose where the synchronous geometry/typing stage runs (T086B-R, issue
/// #270). It is not a port: it describes the composition this seam already
/// owns. Every production composition resolves
/// [RecognitionExecution.offIsolate] so the detector can never block the UI
/// isolate; only a test harness without worker-isolate delivery may resolve
/// [RecognitionExecution.inline].
///
/// Implementations are fail-closed: unavailable capabilities throw
/// [UnsupportedOperationException] rather than fabricating data.
abstract interface class EditorRuntime {
  /// Page rasterization capability used by analysis.
  PageRasterPort get raster;

  /// On-device OCR capability, or null when OCR is unavailable.
  OcrPort? get ocr;

  /// Encrypted document store.
  SecureStorePort get store;

  /// UUID/id source.
  IdPort get ids;

  /// UTC wall clock used for review timestamps (Phase B2).
  ClockPort get clock;

  /// Where the recognition pipeline runs the bytes-level geometry/typing
  /// stage.
  ///
  /// Production compositions resolve [RecognitionExecution.offIsolate].
  RecognitionExecution get recognitionExecution;

  /// Plan validation and flattened PDF export (`contracts/ports.md` §2.5).
  PdfExportPort get export;

  /// Progress phases and the cancel action of the running export
  /// (`contracts/editor-interactions.md` §10 point 3).
  ///
  /// This is not a port: the Android composition adapts the existing
  /// `export.progress` events and the existing `cancel.operation` call of
  /// `contracts/platform-channel.md` §6/§9 of the same channel onto it. A
  /// composition without a cancellable export resolves
  /// [UnavailableExportOperationControl], which reports no progress and cancels
  /// nothing.
  ExportOperationControl get exportOperation;

  /// Save, share, and print hand-off (`contracts/ports.md` §2.6).
  DeliveryPort get delivery;

  /// Applies or clears the screenshot/screen-recording protection for the
  /// current document route (`contracts/platform-channel.md` §11 point 7).
  ///
  /// Returns the protection state the platform reports after the request:
  /// `true` only when the window demonstrably carries `FLAG_SECURE`. The
  /// implementation never returns `true` for a request it could not apply, so
  /// a caller can distinguish "protected" from "not protected" instead of
  /// assuming protection.
  ///
  /// A fail-closed runtime throws [UnsupportedOperationException]; a rejected
  /// channel request throws a `FeldexaException`. Both mean *not protected*:
  /// a caller keeps the editor usable and must never claim protection.
  Future<bool> setSensitiveRoute(SensitiveRoute route);

  /// Loads the current verified revision for [documentId].
  ///
  /// The returned [LoadedDocument] contains the decrypted source bytes owned by
  /// the caller; implementations must not retain a path or file handle.
  Future<LoadedDocument> loadDocument(String documentId);

  /// Saves one verified revision through the composed store.
  Future<StoredMeta> saveRevision(SaveRevisionRequest request);

  /// Releases adapter resources owned by this runtime.
  ///
  /// Implementations must be idempotent. A runtime that shares adapter clients
  /// with a longer-lived import composition must not dispose those shared
  /// clients here.
  Future<void> dispose();
}

/// Creates the editor runtime selected for the current compile target.
///
/// On `dart:library.io` this is the real Android composition; every other
/// target receives the fail-closed runtime.
EditorRuntime createEditorRuntime() => platform.createEditorRuntime();
