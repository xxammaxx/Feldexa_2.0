// T031 startup-wiring host tests.
//
// Evidence class: NONE. These are host-VM checks of the bounded startup
// wrapper and of the shell's localized recovery notice surface. They are not
// Android/emulator/device evidence and they do not exercise a real channel.
//
// T031-B1 requires the production app to invoke the sweep without hanging,
// crashing, or claiming a success it did not achieve. The timeout and throw
// cases below pin those guarantees; the widget cases pin that the German text
// shown to the user comes from the committed ARB through the sweep notice.

@TestOn('vm')
library;

import 'dart:async';

import 'package:feldexa_app/bootstrap/session_end_sweep.dart';
import 'package:feldexa_app/bootstrap/startup_sweep.dart';
import 'package:feldexa_app/bootstrap/startup_sweep_app.dart';
import 'package:feldexa_app/bootstrap/startup_sweep_io.dart';
import 'package:feldexa_app/bootstrap/startup_sweep_bootstrap.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_app/main.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, Locale, SizedBox;
import 'package:flutter_test/flutter_test.dart';

final AppLocalizations _de = lookupAppLocalizations(const Locale('de'));

StartupSweepResult _result({
  required StartupSweepStatus status,
  List<StartupSweepNotice> notices = const <StartupSweepNotice>[],
}) {
  return StartupSweepResult(
    status: status,
    nativeRecovery: const StartupRecoveryCounts.none(),
    temporary: StartupSweepRemoval.empty,
    exportPreviews: StartupSweepRemoval.empty,
    aggregates: const <AggregateRecovery>[],
    notices: notices,
    issues: const <StartupSweepIssue>[],
    boundReached: false,
  );
}

void main() {
  group('production composition', () {
    test(
      'the platform selector builds the real Android store and io adapter',
      () {
        final StartupSweep? sweep = createAppStartupSweep();

        expect(sweep, isNotNull);
        expect(sweep!.store, isNotNull);
        expect(sweep.nativeRecovery, isNotNull);
        expect(sweep.files, isA<IoStartupSweepFileSystem>());
      },
    );
  });

  group('bounded startup runner', () {
    test(
      'a hang becomes a bounded timeout, never a crash or success',
      () async {
        final StartupSweepStartup startup = await runStartupSweepBounded(
          run: () => Completer<StartupSweepResult>().future,
          timeout: const Duration(milliseconds: 20),
        );

        expect(startup.timedOut, isTrue);
        expect(startup.failed, isFalse);
        expect(startup.result, isNull);
        expect(startup.isDegraded, isTrue);
        expect(startup.notices, isEmpty);
      },
    );

    test('a thrown sweep becomes a degraded failure, never a crash', () async {
      final StartupSweepStartup startup = await runStartupSweepBounded(
        run: () async => throw StateError('startup sweep failed'),
      );

      expect(startup.timedOut, isFalse);
      expect(startup.failed, isTrue);
      expect(startup.result, isNull);
      expect(startup.isDegraded, isTrue);
      expect(startup.notices, isEmpty);
    });

    test('a clean result stays complete', () async {
      final StartupSweepResult result = _result(
        status: StartupSweepStatus.clean,
      );
      final StartupSweepStartup startup = await runStartupSweepBounded(
        run: () async => result,
      );

      expect(startup.result, same(result));
      expect(startup.timedOut, isFalse);
      expect(startup.failed, isFalse);
      expect(startup.isDegraded, isFalse);
    });

    test('a degraded result is not reported as success', () async {
      final StartupSweepResult result = _result(
        status: StartupSweepStatus.degraded,
      );
      final StartupSweepStartup startup = await runStartupSweepBounded(
        run: () async => result,
      );

      expect(startup.result, same(result));
      expect(startup.isDegraded, isTrue);
      expect(startup.result?.isComplete, isFalse);
    });
  });

  group('shell recovery notice surface', () {
    testWidgets('renders the localized SAVE-004 guidance', (tester) async {
      final StartupSweepNotice notice = StartupSweepNotice(
        code: 'SAVE-004',
        statusLabel: _de.durabilityRecoveryFallback,
        message: _de.save004,
        recovery: _de.save004Recovery,
      );

      await tester.pumpWidget(
        FeldexaApp(
          startup: StartupSweepStartup(
            result: _result(
              status: StartupSweepStatus.recovered,
              notices: <StartupSweepNotice>[notice],
            ),
          ),
        ),
      );

      expect(find.text(_de.startTitle), findsOneWidget);
      expect(find.text(_de.durabilityRecoveryFallback), findsOneWidget);
      expect(find.text(_de.save004), findsOneWidget);
      expect(find.text(_de.save004Recovery), findsOneWidget);
      // A specific catalog notice is not replaced by the generic notice.
      expect(find.text(_de.startupRecoveryIncomplete), findsNothing);
    });

    testWidgets('keeps the plain shell when startup is absent', (tester) async {
      await tester.pumpWidget(const FeldexaApp());

      expect(find.text(_de.startTitle), findsOneWidget);
      expect(find.text(_de.save004), findsNothing);
      expect(find.text(_de.durabilityRecoveryFallback), findsNothing);
      expect(find.text(_de.startupRecoveryIncomplete), findsNothing);
    });

    testWidgets('keeps the plain shell for a clean startup', (tester) async {
      final StartupSweepStartup startup = await runStartupSweepBounded(
        run: () async => _result(status: StartupSweepStatus.clean),
      );

      await tester.pumpWidget(FeldexaApp(startup: startup));

      expect(find.text(_de.startTitle), findsOneWidget);
      expect(find.text(_de.startupRecoveryIncomplete), findsNothing);
    });

    testWidgets('a timed-out startup shows the ARB recovery notice', (
      tester,
    ) async {
      // A real bounded wait cannot be awaited inside `testWidgets` (the fake
      // clock only advances on `pump`), so this pins the shell surface for the
      // state the runner returns. The runner's own timeout behaviour is pinned
      // by the `bounded startup runner` tests above.
      const StartupSweepStartup startup = StartupSweepStartup(timedOut: true);

      expect(startup.isDegraded, isTrue);
      expect(startup.hasNoNotices, isTrue);

      await tester.pumpWidget(FeldexaApp(startup: startup));

      expect(find.text(_de.startTitle), findsOneWidget);
      expect(find.text(_de.startupRecoveryIncomplete), findsOneWidget);
      expect(find.text(_de.startupRecoveryIncompleteRecovery), findsOneWidget);
    });

    testWidgets('a thrown startup shows the ARB recovery notice', (
      tester,
    ) async {
      const StartupSweepStartup startup = StartupSweepStartup(failed: true);

      expect(startup.isDegraded, isTrue);
      expect(startup.hasNoNotices, isTrue);

      await tester.pumpWidget(FeldexaApp(startup: startup));

      expect(find.text(_de.startTitle), findsOneWidget);
      expect(find.text(_de.startupRecoveryIncomplete), findsOneWidget);
    });

    testWidgets('a degraded result without notices shows the ARB notice', (
      tester,
    ) async {
      final StartupSweepStartup startup = await runStartupSweepBounded(
        run: () async => _result(status: StartupSweepStatus.degraded),
      );

      expect(startup.isDegraded, isTrue);
      expect(startup.hasNoNotices, isTrue);

      await tester.pumpWidget(FeldexaApp(startup: startup));

      expect(find.text(_de.startTitle), findsOneWidget);
      expect(find.text(_de.startupRecoveryIncomplete), findsOneWidget);
    });
  });

  group('session-end wiring', () {
    testWidgets('the shell sweeps export previews at session end', (
      tester,
    ) async {
      addTearDown(() {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      final _RecordingFileSystem files = _RecordingFileSystem();
      final StartupSweep sweep = StartupSweep(
        store: null,
        clock: const StartupSweepWallClock(),
        files: files,
      );

      await tester.pumpWidget(
        FeldexaApp(startup: const StartupSweepStartup(), sweep: sweep),
      );
      expect(files.deletedExports, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(files.listCalls, 1);
      expect(files.deletedExports, <String>['preview.pdf']);
    });

    testWidgets('the shell also sweeps when the engine detaches', (
      tester,
    ) async {
      addTearDown(() {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      final _RecordingFileSystem files = _RecordingFileSystem();
      final StartupSweep sweep = StartupSweep(
        store: null,
        clock: const StartupSweepWallClock(),
        files: files,
      );

      await tester.pumpWidget(FeldexaApp(sweep: sweep));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
      await tester.pump();

      expect(files.deletedExports, <String>['preview.pdf']);
    });

    testWidgets('a transient inactive state does not sweep', (tester) async {
      final _RecordingFileSystem files = _RecordingFileSystem();
      final StartupSweep sweep = StartupSweep(
        store: null,
        clock: const StartupSweepWallClock(),
        files: files,
      );

      await tester.pumpWidget(FeldexaApp(sweep: sweep));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(files.listCalls, 0);
      expect(files.deletedExports, isEmpty);
    });

    testWidgets('the shell stops observing after it is disposed', (
      tester,
    ) async {
      final _RecordingFileSystem files = _RecordingFileSystem();
      final StartupSweep sweep = StartupSweep(
        store: null,
        clock: const StartupSweepWallClock(),
        files: files,
      );

      await tester.pumpWidget(FeldexaApp(sweep: sweep));
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(files.listCalls, 0);
      expect(files.deletedExports, isEmpty);
    });

    test('only paused and detached are session-end states', () {
      expect(SessionEndSweepBinding.sessionEndStates, <AppLifecycleState>{
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      });
    });
  });
}

/// Minimal recording filesystem for the session-end wiring tests.
final class _RecordingFileSystem implements StartupSweepFileSystem {
  int listCalls = 0;
  final List<String> deletedExports = <String>[];
  List<StartupSweepEntry> entries = <StartupSweepEntry>[
    StartupSweepEntry(
      name: 'preview.pdf',
      lastModifiedUtc: DateTime.utc(2026, 11, 15, 12),
    ),
  ];

  @override
  Future<List<StartupSweepEntry>> listTemporaryEntries() async {
    return const <StartupSweepEntry>[];
  }

  @override
  Future<void> deleteTemporaryEntry(StartupSweepEntry entry) async {}

  @override
  Future<List<StartupSweepEntry>> listExportArtifacts() async {
    listCalls++;
    return List<StartupSweepEntry>.unmodifiable(entries);
  }

  @override
  Future<void> deleteExportArtifact(StartupSweepEntry entry) async {
    deletedExports.add(entry.name);
    entries = entries
        .where((StartupSweepEntry value) => value.name != entry.name)
        .toList();
  }
}
