// Shared Flutter test bootstrap for the app's host-VM tests.
//
// T086C adds one production-like startup step: the FLD-001 text-fit
// measurement reads the bundled `assets/fonts/metrics.json` advance table
// (`initializeFieldTextMeasure`), exactly as `main()` does before `runApp`.
// Loading it here means every app test measures with the same Noto Sans
// metrics the export layout uses, instead of silently running with the
// measurement disabled or with a test-font approximation.
//
// Issue #318: `flutter test apps/feldexa_app/test` from the repository root
// roots the asset bundle at the workspace root, where `assets/fonts/*` is not
// declared, so every test that needs the advance table failed with
// "Unable to load asset: assets/fonts/metrics.json". Package-relative runs
// worked, which made the suite look green in one invocation and red in the
// other. The fallback below serves the app's declared asset files from the
// package directory when the default bundle cannot resolve them; the default
// bundle stays authoritative wherever it already works.
//
// Evidence class: NONE. This file only wires test state; it makes no Android,
// device, screen-reader, or visual claim.

import 'dart:async';
import 'dart:io';

import 'package:feldexa_app/features/fill/field_text_fit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Directory that contains `assets/fonts/metrics.json`, or null.
///
/// Checked in order: the current directory (package-relative run), the
/// workspace `apps/feldexa_app` directory (repository-root run), and the
/// ancestors of the test script.
Directory? _appDirectory() {
  final List<Directory> candidates = <Directory>[
    Directory.current,
    Directory('${Directory.current.path}/apps/feldexa_app'),
  ];
  Directory? script = File(Platform.script.toFilePath()).parent;
  for (int depth = 0; depth < 6 && script != null; depth++) {
    candidates.add(script);
    final Directory parent = script.parent;
    script = parent.path == script.path ? null : parent;
  }
  for (final Directory candidate in candidates) {
    if (File('${candidate.path}/assets/fonts/metrics.json').existsSync()) {
      return candidate;
    }
  }
  return null;
}

/// Serves declared asset files from the package directory as a fallback.
///
/// Only keys that resolve to an existing file under `<app>/assets/` are
/// answered; every other key returns null, so the framework keeps its normal
/// behavior and no test sees a silently empty asset.
void _installAppAssetFallback() {
  final Directory? app = _appDirectory();
  if (app == null) {
    return;
  }
  const String assetChannel = 'flutter/assets';
  Future<ByteData?> onAsset(ByteData? message) async {
    if (message == null) {
      return null;
    }
    final String? key = const StringCodec().decodeMessage(message);
    if (key == null || !key.startsWith('assets/')) {
      return null;
    }
    final File file = File('${app.path}/$key');
    if (!file.existsSync()) {
      return null;
    }
    final Uint8List bytes = file.readAsBytesSync();
    return ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
  }

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(assetChannel, onAsset);
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  _installAppAssetFallback();
  // A missing or unreadable table degrades to "no FLD-001 warning"; it must
  // never fail a host test that does not care about overflow.
  await initializeFieldTextMeasure();
  await testMain();
}
