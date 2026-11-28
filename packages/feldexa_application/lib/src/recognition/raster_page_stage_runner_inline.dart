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
/// [cancellation] keeps the same signature and the same outcome contract as the
/// VM runner, but a single isolate can observe it only between awaits: an
/// already-completed signal suppresses the work, and a signal that completes
/// while the synchronous work runs drops the finished result in favour of
/// [RasterPageStageOutcome.cancelled]. No partial suggestion is ever returned.
library;

import 'dart:async';

import 'raster_page_stage.dart';

/// Runs the geometry/typing stage for [task] on the calling isolate.
///
/// The API mirrors `raster_page_stage_runner_vm.dart`; on a single-isolate
/// target the stage simply runs where it was called. A completed
/// [cancellation] signal yields [RasterPageStageOutcome.cancelled] instead of a
/// result; the work itself cannot be preempted here.
Future<RasterPageStageOutcome> runRasterPageStageOffIsolate(
  RasterPageStageTask task, {
  RasterPageStageWork work = runRasterPageStage,
  Duration deadline = defaultPageAnalysisDeadline,
  Future<void>? cancellation,
}) async {
  if (cancellation == null) {
    return work(task);
  }
  bool cancelled = false;
  void observe() {
    if (!cancelled) {
      cancelled = true;
    }
  }

  unawaited(
    cancellation.then<void>(
      (void _) => observe(),
      onError: (Object _) => observe(),
    ),
  );
  // One microtask checkpoint settles an already-completed signal without
  // letting due timers run.
  await Future<void>.microtask(() {});
  if (cancelled) {
    return RasterPageStageOutcome.cancelled();
  }
  final RasterPageStageOutcome outcome = work(task);
  await Future<void>.microtask(() {});
  return cancelled ? RasterPageStageOutcome.cancelled() : outcome;
}
