// T086B-R (#270) recognition execution mode of the composed editor runtimes.
//
// Evidence class: NONE. These are host-VM composition checks on which
// `RecognitionExecution` the app's editor runtimes resolve. They are not
// EMULATOR or DEVICE evidence, and they measure no performance: they only pin
// that no production composition claims the inline (calling-isolate) mode.

@TestOn('vm')
library;

import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:feldexa_app/features/editor/editor_runtime.dart' as editor;
import 'package:feldexa_app/features/editor/editor_runtime_android.dart'
    as android;
import 'package:feldexa_app/features/editor/editor_runtime_unavailable.dart'
    as unavailable;
import 'package:feldexa_application/src/recognition/raster_page_stage_runner.dart'
    show RecognitionExecution;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Android composition runs the raster stage off the UI isolate', () {
    final AndroidOperationClient operations = AndroidOperationClient(
      results: const Stream<Object?>.empty(),
    );
    final editor.EditorRuntime runtime = android.createAndroidEditorRuntime(
      operations: operations,
      store: AndroidStoreClient(operations: operations),
    );

    expect(runtime.recognitionExecution, RecognitionExecution.offIsolate);
  });

  test('the target-selected editor runtime never resolves inline', () {
    // On `dart.library.io` the conditional import selects the Android
    // composition of `editor_runtime.dart`.
    final editor.EditorRuntime selected = editor.createEditorRuntime();
    addTearDown(selected.dispose);

    expect(selected.recognitionExecution, RecognitionExecution.offIsolate);
  });

  test('the fail-closed editor runtime never resolves inline', () {
    final editor.EditorRuntime runtime = unavailable.createEditorRuntime();

    expect(runtime.recognitionExecution, RecognitionExecution.offIsolate);
  });
}
