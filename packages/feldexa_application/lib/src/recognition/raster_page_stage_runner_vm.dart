// ignore_for_file: implementation_imports

/// Off-isolate execution of the bytes-level raster stage (VM targets).
///
/// Selected by `raster_page_stage_runner.dart` on every target with worker
/// isolates. The browser variant of the same API is
/// `raster_page_stage_runner_inline.dart`.
///
/// The runner spawns one short-lived worker isolate per page, hands it the
/// task, the work closure, and one reply port, and returns the
/// [RasterPageStageOutcome] the worker sends. It adds no port, no persistent
/// worker, no scheduler, and no queue: page sequencing stays in
/// `AnalyzeDocument.run`, and one page's worker cannot affect another page.
///
/// Every failure of the mechanism itself is reported as a content-free
/// [PageAnalysisFailure.internal] outcome, so a spawn failure degrades to a
/// failed page instead of an unhandled error or a silently completed one.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:feldexa_recognition/src/page_analysis.dart';

import 'raster_page_stage.dart';

/// One worker request: the task, the work, and the reply port.
final class _RasterPageStageMessage {
  const _RasterPageStageMessage(this.task, this.work, this.reply);

  final RasterPageStageTask task;
  final RasterPageStageWork work;
  final SendPort reply;
}

/// Worker isolate entry point.
///
/// Runs the work and always replies with an outcome; a thrown page failure is
/// converted into the equivalent failed outcome so the reply never depends on
/// isolate error propagation.
void _rasterPageStageWorker(_RasterPageStageMessage message) {
  RasterPageStageOutcome outcome;
  try {
    outcome = message.work(message.task);
  } on PageAnalysisFailure catch (failure) {
    outcome = RasterPageStageOutcome.failed(category: failure.category);
  } catch (_) {
    outcome = RasterPageStageOutcome.failed(
      category: PageAnalysisFailure.internal,
    );
  }
  message.reply.send(outcome);
}

/// Runs the geometry/typing stage for [task] in a worker isolate.
///
/// [work] defaults to the production [runRasterPageStage]; a caller composes
/// its own fault-injection seams into it, a test substitutes it to observe the
/// worker. The worker isolate is always terminated before this future
/// completes.
Future<RasterPageStageOutcome> runRasterPageStageOffIsolate(
  RasterPageStageTask task, {
  RasterPageStageWork work = runRasterPageStage,
}) async {
  final ReceivePort replies = ReceivePort();
  final Isolate worker;
  try {
    worker = await Isolate.spawn<_RasterPageStageMessage>(
      _rasterPageStageWorker,
      _RasterPageStageMessage(task, work, replies.sendPort),
      debugName: 'feldexa-raster-page-stage',
      onExit: replies.sendPort,
      onError: replies.sendPort,
      errorsAreFatal: true,
    );
  } catch (_) {
    replies.close();
    return RasterPageStageOutcome.failed(
      category: PageAnalysisFailure.internal,
    );
  }
  try {
    final Object? message = await replies.first;
    if (message is RasterPageStageOutcome) {
      return message;
    }
    return RasterPageStageOutcome.failed(
      category: PageAnalysisFailure.internal,
    );
  } catch (_) {
    return RasterPageStageOutcome.failed(
      category: PageAnalysisFailure.internal,
    );
  } finally {
    replies.close();
    worker.kill(priority: Isolate.beforeNextEvent);
  }
}
