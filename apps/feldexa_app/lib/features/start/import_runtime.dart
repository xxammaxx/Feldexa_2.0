// T148 app-level import composition selector; issue #217 Phase B1 adds the
// editor runtime.
//
// Owner: `apps/feldexa_app/lib/features/start/import_runtime.dart` (T148,
// Phase B1).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/contracts/platform-channel.md` §2.2,
//     §3, §4, and §5;
//   * `specs/001-scanned-form-workflow/spec.md` FR-001, FR-003, FR-009,
//     FR-010, FR-014, and FR-017–FR-020;
//   * constitution Principles II, III, VI, VIII, and X.
//
// The selector mirrors `apps/feldexa_app/lib/platform/registry.dart`: the
// `dart.library.io` branch is the real Android composition and the other
// branches fail closed. The Android adapter package is therefore never part of
// a Web build, and no simulated adapter stands in for it.
//
// [ImportRuntime] is the UI's single capability seam. The start screen runs
// `ImportFlow` against [importPort], resolves protected source bytes through
// [readSourceBytes], and asks [createEditorRuntime] for the platform's editor
// composition. No file path, URI, display name, or source content is accepted
// or returned by this seam.
//
// The editor runtime is created per editor session. That keeps the adapter
// lifecycle honest: the editor disposes the runtime it opened, while a shared
// import operation client owned by the import composition stays alive. When no
// factory is injected (host tests, non-Android targets), the fail-closed editor
// runtime is used and no analysis or save is invented.

import 'dart:typed_data';

import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/features/editor/editor_runtime_unavailable.dart';
import 'package:feldexa_ports/feldexa_ports.dart';

import 'import_runtime_unavailable.dart'
    if (dart.library.io) 'import_runtime_android.dart'
    if (dart.library.js_interop) 'import_runtime_unavailable.dart'
    as platform;

/// The production platform capabilities needed by the US1/US2 surfaces.
final class ImportRuntime {
  /// Creates the runtime seam.
  ///
  /// [editorRuntimeFactory] is optional so existing host compositions and
  /// tests keep their import/read-back behavior. A composition that omits it
  /// fails closed on editor analysis and save.
  const ImportRuntime({
    required this.importPort,
    required this.readSourceBytes,
    this.editorRuntimeFactory,
  });

  /// The real platform document-import capability.
  final DocumentImportPort importPort;

  /// Resolves the protected source bytes for an imported `documentId`.
  ///
  /// Returns `null` when the protected source is unavailable. Implementations
  /// must not open a filesystem path and must not log the id or the bytes.
  final Future<Uint8List?> Function(String documentId) readSourceBytes;

  /// Optional factory for the platform editor composition.
  ///
  /// Null selects the fail-closed runtime.
  final EditorRuntime Function()? editorRuntimeFactory;

  /// Creates the editor composition for one editor session.
  ///
  /// Construction is a composition boundary: any thrown `Object` (including
  /// `Error` subtypes such as `StateError`, `ArgumentError`, or an
  /// `AssertionError` from adapter construction) is treated as a construction
  /// failure and replaced by the fail-closed runtime. The already-imported
  /// viewer remains available through [readSourceBytes], but no analysis or
  /// revision save claims to have run. This catch is deliberately limited to
  /// construction; later [EditorRuntime.loadDocument] and
  /// [EditorRuntime.saveRevision] failures are surfaced by the editor's own
  /// content-free state. The caller owns the returned runtime and should
  /// dispose it when the editor closes.
  EditorRuntime createEditorRuntime() {
    final EditorRuntime Function() factory =
        editorRuntimeFactory ?? createUnavailableEditorRuntime;
    try {
      return factory();
    } catch (_) {
      return createUnavailableEditorRuntime();
    }
  }
}

/// Creates the composition selected for the current compile target.
///
/// On `dart:io` targets this is the real Android composition; every other
/// target receives a fail-closed runtime whose import attempt surfaces the
/// catalog `IMP-005` text and creates nothing.
ImportRuntime createImportRuntime() => platform.createImportRuntime();
