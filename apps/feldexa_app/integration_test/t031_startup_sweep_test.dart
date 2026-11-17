// T031 EMULATOR runtime proof for the owner-decided §4 order.
//
// Run only on an exclusively allocated Android emulator:
//   flutter test integration_test/t031_startup_sweep_test.dart -d <device>
//
// The test seeds a stale plaintext export preview in the app's private cache
// directory (the same `Directory.systemTemp/feldexa_exports` location the
// production `createAppStartupSweep` uses on Android) and runs the production
// `StartupSweep` with the documented `nativeRecovery` failure seam. It covers
// both failure paths required by the owner decision:
//   1. native recovery throws;
//   2. native recovery times out under `runStartupSweepBounded`.
//
// In both cases the preview must be gone and the German
// `startupRecoveryIncomplete` notice must be produced. The test writes only
// into the dedicated cache export directory and removes its own file.

import 'dart:async';
import 'dart:io';

import 'package:feldexa_app/bootstrap/startup_sweep.dart';
import 'package:feldexa_app/bootstrap/startup_sweep_bootstrap.dart';
import 'package:feldexa_app/bootstrap/startup_sweep_io.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final AppLocalizations de = lookupAppLocalizations(const Locale('de'));

  // This is the same app-private cache directory the production Android
  // composition passes to `IoStartupSweepFileSystem`.
  Directory exportsDirectory() => Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}feldexa_exports',
  );

  Future<File> seedStalePreview(String name) async {
    final Directory directory = exportsDirectory();
    await directory.create(recursive: true);
    final File preview = File(
      '${directory.path}${Platform.pathSeparator}$name',
    );
    await preview.writeAsString('stale plaintext export preview');
    await preview.setLastModified(
      DateTime.now().subtract(const Duration(hours: 25)),
    );
    return preview;
  }

  testWidgets('stale preview is removed when native recovery throws', (
    WidgetTester tester,
  ) async {
    final File preview = await seedStalePreview('t031-throw.pdf');
    addTearDown(() async {
      if (await preview.exists()) {
        await preview.delete();
      }
    });

    final StartupSweep sweep = StartupSweep(
      store: null,
      clock: const StartupSweepWallClock(),
      files: IoStartupSweepFileSystem(exportDirectory: exportsDirectory()),
      nativeRecovery: () async =>
          throw StateError('injected native recovery failure'),
    );

    final StartupSweepResult result = await sweep.run();
    final List<StartupSweepNotice> notices = startupRecoveryNotices(
      StartupSweepStartup(result: result),
    );

    expect(await preview.exists(), isFalse);
    expect(result.status, StartupSweepStatus.degraded);
    expect(result.isComplete, isFalse);
    expect(result.exportPreviews.removed, 1);
    expect(notices.single.code, 'startupRecoveryIncomplete');
    expect(notices.single.message, de.startupRecoveryIncomplete);
    expect(notices.single.recovery, de.startupRecoveryIncompleteRecovery);
  });

  testWidgets('stale preview is removed when native recovery times out', (
    WidgetTester tester,
  ) async {
    final File preview = await seedStalePreview('t031-timeout.pdf');
    addTearDown(() async {
      if (await preview.exists()) {
        await preview.delete();
      }
    });

    final Completer<StartupRecoveryCounts> gate =
        Completer<StartupRecoveryCounts>();
    addTearDown(() {
      if (!gate.isCompleted) {
        gate.complete(const StartupRecoveryCounts.none());
      }
    });
    final StartupSweep sweep = StartupSweep(
      store: null,
      clock: const StartupSweepWallClock(),
      files: IoStartupSweepFileSystem(exportDirectory: exportsDirectory()),
      nativeRecovery: () => gate.future,
    );

    final Future<StartupSweepResult> operation = sweep.run();
    final StartupSweepStartup startup = await runStartupSweepBounded(
      run: () => operation,
      timeout: const Duration(milliseconds: 250),
      onTimeout: sweep.cancel,
    );

    expect(startup.timedOut, isTrue);
    expect(sweep.isCancelled, isTrue);
    // Step 4 ran before the native call, so the timeout cannot skip it.
    expect(await preview.exists(), isFalse);
    final StartupSweepNotice notice = startupRecoveryNotices(startup).single;
    expect(notice.code, 'startupRecoveryIncomplete');
    expect(notice.message, de.startupRecoveryIncomplete);

    gate.complete(const StartupRecoveryCounts.none());
    final StartupSweepResult result = await operation;
    expect(result.exportPreviews.removed, 1);
    expect(result.status, StartupSweepStatus.degraded);
  });
}
