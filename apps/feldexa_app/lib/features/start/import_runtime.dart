// T148 app-level import composition selector.
//
// Owner: `apps/feldexa_app/lib/features/start/import_runtime.dart` (T148).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/contracts/platform-channel.md` §2.2,
//     §3, and §4;
//   * `specs/001-scanned-form-workflow/spec.md` FR-001, FR-003, FR-009, and
//     FR-010;
//   * constitution Principles II, III, VI, VIII, and X.
//
// The selector mirrors `apps/feldexa_app/lib/platform/registry.dart`: the
// `dart.library.io` branch is the real Android composition and the other
// branches fail closed. The Android adapter package is therefore never part of
// a Web build, and no simulated adapter stands in for it.
//
// [ImportRuntime] is the UI's single capability seam. The start screen runs
// `ImportFlow` against [importPort]; the editor resolves protected source bytes
// through [readSourceBytes], keyed by the imported `documentId`. No file path,
// URI, display name, or source content is accepted or returned by this seam.

import 'dart:typed_data';

import 'package:feldexa_ports/feldexa_ports.dart';

import 'import_runtime_unavailable.dart'
    if (dart.library.io) 'import_runtime_android.dart'
    if (dart.library.js_interop) 'import_runtime_unavailable.dart'
    as platform;

/// The production platform capabilities needed by the US1 import surface.
///
/// The composition is deliberately narrow: T148 composes import and source
/// read-back only. Raster, OCR, export, delivery, and the rest of the adapter
/// set stay owned by their existing registries and later editor tasks.
final class ImportRuntime {
  /// Creates the runtime seam.
  const ImportRuntime({
    required this.importPort,
    required this.readSourceBytes,
  });

  /// The real platform document-import capability.
  final DocumentImportPort importPort;

  /// Resolves the protected source bytes for an imported `documentId`.
  ///
  /// Returns `null` when the protected source is unavailable. Implementations
  /// must not open a filesystem path and must not log the id or the bytes.
  final Future<Uint8List?> Function(String documentId) readSourceBytes;
}

/// Creates the composition selected for the current compile target.
///
/// On `dart:io` targets this is the real Android composition; every other
/// target receives a fail-closed runtime whose import attempt surfaces the
/// catalog `IMP-005` text and creates nothing.
ImportRuntime createImportRuntime() => platform.createImportRuntime();
