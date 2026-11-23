// ignore_for_file: implementation_imports

/// Execution mode of the bytes-level raster stage for `AnalyzeDocument`.
///
/// [offIsolate] runs the stage in a worker isolate, so the synchronous
/// T051/T052 detector can never block the calling (UI) isolate. [inline] runs
/// the very same entry on the calling isolate.
///
/// [inline] exists only for harnesses that cannot await a real isolate — a
/// `testWidgets` fake-async zone never delivers an isolate message — and for
/// targets without worker isolates. It is not a production mode: the platform
/// composition (`EditorRuntime.recognitionExecution`) resolves [offIsolate],
/// and every inline choice must be justified at its call site.
library;

export 'raster_page_stage_runner_vm.dart'
    if (dart.library.js_interop) 'raster_page_stage_runner_inline.dart';

/// How `AnalyzeDocument` executes [runRasterPageStage].
enum RecognitionExecution {
  /// Worker-isolate execution: the production mode.
  offIsolate,

  /// Calling-isolate execution: test-only and browser fallback.
  inline,
}
