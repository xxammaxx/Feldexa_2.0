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
// other. The fallback below answers only the assets and bundled font files
// declared in `pubspec.yaml` (the `assets:` and `fonts:` entries under
// `assets/fonts/`) from the package directory; every other key returns null. It is a channel mock, so it
// answers before the default bundle rather than after it, and it is not
// installed on the web, where `dart:io` is unavailable.
//
// Evidence class: NONE. This file only wires test state; it makes no Android,
// device, screen-reader, or visual claim.

import 'dart:async';
import 'dart:io';

import 'package:feldexa_app/features/fill/field_text_fit.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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

/// The assets and bundled font files declared in `apps/feldexa_app/pubspec.yaml`.
///
/// Parsed instead of hard-coded so a new font or asset cannot silently fall out
/// of the fallback. The fallback must not make undeclared files loadable:
/// `assets/fixtures/**` and `assets/fonts/PROVENANCE.md` are deliberately not
/// declared, and a negative test for that property must keep failing here.
Set<String> _declaredAssetKeys(Directory app) {
  final File pubspec = File('${app.path}/pubspec.yaml');
  if (!pubspec.existsSync()) {
    return const <String>{};
  }
  final RegExp fontAsset = RegExp(r'^\s*- asset:\s*(\S+)\s*$');
  final RegExp listedAsset = RegExp(r'^\s*- (assets/\S+)\s*$');
  final Set<String> keys = <String>{};
  for (final String line in pubspec.readAsLinesSync()) {
    final RegExpMatch? font = fontAsset.firstMatch(line);
    final String? candidate =
        font?.group(1) ?? listedAsset.firstMatch(line)?.group(1);
    if (candidate != null && candidate.startsWith('assets/')) {
      keys.add(candidate);
    }
  }
  return keys;
}

/// Serves the declared asset files from the package directory as a fallback.
///
/// Only the keys from [_declaredAssetKeys] are answered; every other returns null,
/// so the framework keeps its normal behavior and no test can load an
/// undeclared or escaping path through this mock.
void _installAppAssetFallback() {
  final Directory? app = _appDirectory();
  if (app == null) {
    return;
  }
  final Set<String> declaredAssets = _declaredAssetKeys(app);
  const String assetChannel = 'flutter/assets';
  Future<ByteData?> onAsset(ByteData? message) async {
    if (message == null) {
      return null;
    }
    final String? key = const StringCodec().decodeMessage(message);
    if (key == null || !declaredAssets.contains(key) || key.contains('..')) {
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
  // `dart:io` is unavailable on the web test platform; the channel fallback is
  // host-only and the browser layer must keep its real bundle.
  if (!kIsWeb) {
    _installAppAssetFallback();
    // A missing or unreadable table degrades to "no FLD-001 warning"; it must
    // never fail a host test that does not care about overflow.
    await initializeFieldTextMeasure();
  }
  // Browser lane: Flutter 3.47.7's web test harness runs with
  // `TestEnvironment.flutterTester()` and `ignorePlatformMessages = true`
  // (`_test_selector_web.dart` / `testing.dart`), so
  // `PlatformDispatcher._sendPlatformMessage` returns without a reply and
  // `rootBundle.loadString` never settles — even a served bundle would not
  // resolve it. The failure does not throw, so the catch in
  // `initializeFieldTextMeasure` cannot rescue it, and awaiting the table
  // kept every browser suite from reaching `testMain` (measured 2026-11-28:
  // suite loads, `main` never runs, `No tests ran` after the timeout). The
  // table is therefore unavailable on the browser lane by construction;
  // browser suites run with FLD-001 measurement disabled.
  await testMain();
}
