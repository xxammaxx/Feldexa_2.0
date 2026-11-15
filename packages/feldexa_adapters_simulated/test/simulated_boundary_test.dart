// T028 dependency-boundary and determinism-source tests.
//
// The package must stay platform-free so the same sources compile for the Web
// development surface, and it must never reach into the Android adapter stack.
// It also must not contain wall-clock or randomness reads: determinism is a
// port obligation, not a code-review promise.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final Directory packageRoot = Directory.current;
  final Directory lib = Directory('${packageRoot.path}/lib');

  List<File> dartFiles() {
    return lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((File file) => file.path.endsWith('.dart'))
        .toList(growable: false);
  }

  test('the simulated package has no platform or Android-adapter imports', () {
    final RegExp forbidden = RegExp(
      r'''(^|\n)\s*(import|export)\s+['"](dart:io|dart:html|dart:js|dart:js_interop|'''
      r'''package:flutter|package:pdfrx|package:feldexa_adapters_android|'''
      r'''package:feldexa_application|package:feldexa_ui|package:feldexa_testkit)''',
    );
    for (final File file in dartFiles()) {
      final String source = file.readAsStringSync();
      expect(
        forbidden.hasMatch(source),
        isFalse,
        reason: '${file.path} must stay platform-free and test-free',
      );
    }
  });

  test('library sources never read the wall clock or randomness', () {
    final RegExp nondeterministic = RegExp(
      r'DateTime\.now\(|Stopwatch\(|Random\(|Random\.secure\(|math\.Random',
    );
    for (final File file in dartFiles()) {
      final String source = file.readAsStringSync();
      expect(
        nondeterministic.hasMatch(source),
        isFalse,
        reason: '${file.path} must not read time or randomness',
      );
    }
  });

  test('the Android registry never imports the simulated package', () {
    final File androidRegistry = File(
      '${packageRoot.path}/../../apps/feldexa_app/lib/platform/'
      'registry_android.dart',
    );
    expect(androidRegistry.existsSync(), isTrue);
    final String source = androidRegistry.readAsStringSync();
    final RegExp imported = RegExp(
      r'''^\s*(import|export)\s+['"][^'"]*feldexa_adapters_simulated''',
      multiLine: true,
    );
    expect(imported.hasMatch(source), isFalse);
  });

  test(
    'the package barrel exports every adapter and the evidence contract',
    () {
      final String barrel = File('${lib.path}/feldexa_adapters_simulated.dart')
          .readAsStringSync();
      for (final String export in <String>[
        'src/simulated_import_adapter.dart',
        'src/simulated_raster_adapter.dart',
        'src/simulated_ocr_adapter.dart',
        'src/simulated_store_adapter.dart',
        'src/simulated_export_adapter.dart',
        'src/simulated_delivery_adapter.dart',
        'src/simulated_contract.dart',
      ]) {
        expect(barrel.contains(export), isTrue, reason: export);
      }
    },
  );
}
