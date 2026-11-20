// Issue #217 Phase B1 app-level editor runtime seam.
//
// Owner: `apps/feldexa_app/lib/features/editor/editor_runtime.dart` (Phase B1).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/contracts/platform-channel.md` §2.2,
//     §3, §4, and §5;
//   * `specs/001-scanned-form-workflow/contracts/ports.md` §2.2, §2.3, and
//     §2.4;
//   * `specs/001-scanned-form-workflow/spec.md` FR-014, FR-017, FR-018,
//     FR-019, and FR-020;
//   * constitution Principles II, III, VI, VIII, and X.
//
// This is the editor's single platform-capability seam. It exposes the existing
// raster, OCR, secure-store, and id ports plus the two editor operations that
// must go through the same composed adapter set: loading the current revision
// and saving a new revision. It adds no second runtime, store, orchestrator,
// contract, or platform channel.
//
// The Android implementation is selected only on `dart.library.io` targets and
// composes the existing T027 thin clients. Every other target receives the
// fail-closed implementation: an editor can still show the imported viewer
// through the separate source-bytes closure, but no analysis or save is
// invented. There is no simulated substitute and no evidence claim here.
//
// No implementation accepts or returns a file path, URI, display name, or
// source bytes by path, and nothing in this seam logs document content.

import 'package:feldexa_ports/feldexa_ports.dart';

import 'editor_runtime_unavailable.dart'
    if (dart.library.io) 'editor_runtime_android.dart'
    if (dart.library.js_interop) 'editor_runtime_unavailable.dart'
    as platform;

/// The platform capabilities the editor composition needs.
///
/// [raster] and [ocr] are the analysis ports consumed by the Phase A
/// `AnalyzeDocument` use case. [store] is the existing encrypted store; it is
/// exposed for later review/save work but this seam's [loadDocument] and
/// [saveRevision] are the editor's supported paths. [ids] supplies UUIDv4
/// identities such as the analysis-run id.
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
