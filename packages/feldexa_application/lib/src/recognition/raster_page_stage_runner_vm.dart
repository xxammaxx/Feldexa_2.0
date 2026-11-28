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
///
/// The stage entry is synchronous and cannot observe a caller-side token, so a
/// page is bounded twice: the optional [cancellation] signal ends the worker as
/// soon as it completes, and [deadline] remains the fail-closed backstop for a
/// page nothing cancels. Either way the worker is killed with
/// [Isolate.immediate] and joined before this future completes, so no zombie
/// isolate and no partial suggestion survives the page. A cancelled page
/// returns [RasterPageStageOutcome.cancelled] - the existing cancelled-page
/// category (REC-004), never a failure.
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

/// Marks a stage run that outlived [defaultPageAnalysisDeadline].
final class _DeadlineElapsed {
  const _DeadlineElapsed();
}

/// Marks a stage run ended by the caller's cancellation signal.
final class _Cancelled {
  const _Cancelled();
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
/// worker. [deadline] bounds this one page's run; when it elapses the worker is
/// killed immediately and joined, and the result is
/// [RasterPageStageOutcome.timedOut]. When [cancellation] completes - and it
/// therefore does not have to wait for [deadline] - the worker is killed just
/// as immediately and the result is [RasterPageStageOutcome.cancelled], a
/// content-free outcome that is neither complete nor failed. A signal that
/// fails counts as a cancellation, so a broken signal can never pin a page to
/// its deadline. The worker isolate is always terminated and joined before this
/// future completes.
Future<RasterPageStageOutcome> runRasterPageStageOffIsolate(
  RasterPageStageTask task, {
  RasterPageStageWork work = runRasterPageStage,
  Duration deadline = defaultPageAnalysisDeadline,
  Future<void>? cancellation,
}) async {
  // One port carries both the outcome and the spawn-level exit notification, so
  // the exit listener is registered before the worker can exit and the two
  // messages stay ordered per sender.
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

  final Completer<void> workerGone = Completer<void>();
  final Completer<Object?> terminal = Completer<Object?>();
  final StreamSubscription<Object?> subscription = replies.listen(
    (Object? message) {
      if (message is RasterPageStageOutcome) {
        if (!terminal.isCompleted) {
          terminal.complete(message);
        }
        return;
      }
      if (message == null) {
        // Spawn-level exit notification: the worker is gone.
        if (!workerGone.isCompleted) {
          workerGone.complete();
        }
        return;
      }
      // A fatal worker error: no outcome will follow.
      if (!terminal.isCompleted) {
        terminal.complete(null);
      }
    },
    onDone: () {
      if (!terminal.isCompleted) {
        terminal.complete(null);
      }
    },
  );
  final Timer deadlineTimer = Timer(deadline, () {
    if (!terminal.isCompleted) {
      terminal.complete(const _DeadlineElapsed());
    }
  });
  if (cancellation != null) {
    // The signal is a caller-side decision: it is observed in the calling
    // isolate and translates into an immediate kill, so the worker never needs
    // to poll anything. Both a value and an error complete the race, and the
    // error is swallowed because it cannot change the page outcome.
    unawaited(
      cancellation.then<void>(
        (void _) {
          if (!terminal.isCompleted) {
            terminal.complete(const _Cancelled());
          }
        },
        onError: (Object _) {
          if (!terminal.isCompleted) {
            terminal.complete(const _Cancelled());
          }
        },
      ),
    );
  }

  try {
    final Object? message = await terminal.future;
    if (message is RasterPageStageOutcome) {
      return message;
    }
    if (message is _DeadlineElapsed) {
      return RasterPageStageOutcome.timedOut();
    }
    if (message is _Cancelled) {
      return RasterPageStageOutcome.cancelled();
    }
    return RasterPageStageOutcome.failed(
      category: PageAnalysisFailure.internal,
    );
  } finally {
    deadlineTimer.cancel();
    if (!workerGone.isCompleted) {
      // The deadline path reaches this branch with the worker still busy.
      worker.kill(priority: Isolate.immediate);
    }
    // Join: the port stays open until the worker's exit notification arrived,
    // so a killed worker leaves no zombie isolate behind.
    await workerGone.future;
    await subscription.cancel();
    replies.close();
  }
}
