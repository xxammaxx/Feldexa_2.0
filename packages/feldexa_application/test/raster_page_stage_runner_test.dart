// T086B-R (#270) worker-isolate execution of the bytes-level raster stage.
//
// Evidence class: NONE. These are host-VM tests of the runner contract. They
// show that the stage work executes on a worker isolate, that the deadline
// backstop ends a stalled worker, and that a caller cancellation ends it
// earlier without a partial outcome; they measure no performance and they are
// not EMULATOR or DEVICE evidence.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:feldexa_application/src/recognition/raster_page_stage.dart';
import 'package:feldexa_application/src/recognition/raster_page_stage_runner.dart';
import 'package:feldexa_recognition/src/page_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

RasterPageStageTask _task() {
  return RasterPageStageTask(
    pageIndex: 0,
    pixels: Uint8List(4),
    width: 2,
    height: 2,
    pageWidthPt: 1,
    pageHeightPt: 1,
  );
}

void main() {
  test('the stage work runs on a worker isolate', () async {
    final RasterPageStageOutcome outcome = await runRasterPageStageOffIsolate(
      _task(),
      work: (RasterPageStageTask task) =>
          RasterPageStageOutcome.complete(<Map<String, Object?>>[
            <String, Object?>{
              'isolateName': Isolate.current.debugName ?? '<none>',
            },
          ]),
    );

    expect(outcome.isFailed, isFalse);
    // The caller isolate is unnamed here; the worker is spawned with a debug
    // name, so this value can only come from the worker.
    expect(
      outcome.suggestions.single['isolateName'],
      'feldexa-raster-page-stage',
    );
  });

  test(
    'a stalled worker ends at the deadline without partial suggestions',
    () async {
      final Stopwatch clock = Stopwatch()..start();
      final RasterPageStageOutcome outcome = await runRasterPageStageOffIsolate(
        _task(),
        work: (RasterPageStageTask task) {
          final int until = DateTime.now().millisecondsSinceEpoch + 3000;
          while (DateTime.now().millisecondsSinceEpoch < until) {
            // Worker stalled on purpose; only the deadline can end it.
          }
          return RasterPageStageOutcome.complete(<Map<String, Object?>>[]);
        },
        deadline: const Duration(milliseconds: 150),
      );
      clock.stop();

      expect(outcome.isFailed, isTrue);
      expect(outcome.timedOut, isTrue);
      expect(outcome.suggestions, isEmpty);
      expect(outcome.failure!.category, PageAnalysisFailure.internal);
      expect(outcome.failure!.messageKey, 'REC-002');
      expect(outcome.discardedSuggestions, 0);
      // The runner returns only after killing and joining the worker, so the
      // 3 s stall cannot be observed here.
      expect(clock.elapsedMilliseconds, lessThan(2000));
    },
  );

  test(
    'a cancellation ends a stalled worker well before the deadline',
    () async {
      final Completer<void> cancellation = Completer<void>();
      Timer(const Duration(milliseconds: 150), cancellation.complete);
      final Stopwatch clock = Stopwatch()..start();
      final RasterPageStageOutcome outcome = await runRasterPageStageOffIsolate(
        _task(),
        work: (RasterPageStageTask task) {
          final int until = DateTime.now().millisecondsSinceEpoch + 3000;
          while (DateTime.now().millisecondsSinceEpoch < until) {
            // Worker stalled on purpose; the cancellation must end it.
          }
          return RasterPageStageOutcome.complete(<Map<String, Object?>>[
            <String, Object?>{'id': 's_partial'},
          ]);
        },
        cancellation: cancellation.future,
        deadline: const Duration(seconds: 10),
      );
      clock.stop();

      // The cancellation is content-free: no envelope, no partial suggestion,
      // no failure, and no timeout. It is the existing cancelled-page category
      // (REC-004), never a page failure.
      expect(outcome.isCancelled, isTrue);
      expect(outcome.isFailed, isFalse);
      expect(outcome.timedOut, isFalse);
      expect(outcome.failure, isNull);
      expect(outcome.suggestions, isEmpty);
      // The 3 s stall is not awaited and the 10 s deadline is not reached.
      expect(clock.elapsedMilliseconds, lessThan(2000));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'a cancellation completed before the call spawns no observed outcome',
    () async {
      final RasterPageStageOutcome outcome = await runRasterPageStageOffIsolate(
        _task(),
        work: (RasterPageStageTask task) =>
            RasterPageStageOutcome.complete(<Map<String, Object?>>[
              <String, Object?>{'id': 's_stale'},
            ]),
        cancellation: Future<void>.value(),
      );

      expect(outcome.isCancelled, isTrue);
      expect(outcome.suggestions, isEmpty);
      expect(outcome.isFailed, isFalse);
    },
  );

  test('without a cancellation the projection is unchanged', () async {
    RasterPageStageOutcome work(RasterPageStageTask task) {
      return RasterPageStageOutcome.complete(<Map<String, Object?>>[
        <String, Object?>{'id': 's_p0_0001', 'pageIndex': 0},
      ]);
    }

    final RasterPageStageOutcome plain = await runRasterPageStageOffIsolate(
      _task(),
      work: work,
    );
    // A signal that never completes must be indistinguishable from no signal.
    final RasterPageStageOutcome watched = await runRasterPageStageOffIsolate(
      _task(),
      work: work,
      cancellation: Completer<void>().future,
    );

    expect(watched.isCancelled, isFalse);
    expect(watched.isFailed, isFalse);
    expect(watched.suggestions, plain.suggestions);
  });

  test('a never-firing signal leaves the deadline backstop intact', () async {
    final RasterPageStageOutcome outcome = await runRasterPageStageOffIsolate(
      _task(),
      work: (RasterPageStageTask task) {
        final int until = DateTime.now().millisecondsSinceEpoch + 3000;
        while (DateTime.now().millisecondsSinceEpoch < until) {
          // Only the deadline can end this worker.
        }
        return RasterPageStageOutcome.complete(<Map<String, Object?>>[]);
      },
      cancellation: Completer<void>().future,
      deadline: const Duration(milliseconds: 150),
    );

    expect(outcome.timedOut, isTrue);
    expect(outcome.isCancelled, isFalse);
    expect(outcome.isFailed, isTrue);
  });
}
