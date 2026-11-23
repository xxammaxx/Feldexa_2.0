// ignore_for_file: implementation_imports

/// Calling-isolate execution of the bytes-level raster stage (browser targets).
///
/// Selected by `raster_page_stage_runner.dart` on targets without worker
/// isolates. The browser build is a development surface with a fail-closed
/// editor (`editor_runtime_unavailable.dart`), so there is nothing to keep
/// responsive here: the same entry runs on the single web isolate and returns
/// the identical outcome. This file makes no performance or evidence claim.
///
/// [deadline] is accepted for API parity with the VM runner but cannot preempt
/// the work: a single-isolate target has no way to interrupt a running
/// function, and the editor's own analysis timeout bounds the page instead.
library;

import 'raster_page_stage.dart';

/// Runs the geometry/typing stage for [task] on the calling isolate.
///
/// The API mirrors `raster_page_stage_runner_vm.dart`; on a single-isolate
/// target the stage simply runs where it was called.
Future<RasterPageStageOutcome> runRasterPageStageOffIsolate(
  RasterPageStageTask task, {
  RasterPageStageWork work = runRasterPageStage,
  Duration deadline = defaultPageAnalysisDeadline,
}) async {
  return work(task);
}
