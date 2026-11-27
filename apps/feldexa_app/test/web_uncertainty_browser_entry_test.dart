// T127 `SIMULATED` uncertainty presentation (FR-086/FR-087; US8/US9).
//
// Evidence class: NONE (this run). This file composes the shipped
// `SimulatedBanner` (T026/T047) and the T122 `UncertaintyBadge` and asserts
// the presentation contract on the host VM. The actual Chrome run of the
// web uncertainty presentation is NOT_RUN: the browser lane on this host is
// blocked by the documented Chrome-for-Testing hang
// (`run-tscn02hu/reports/findings/2026-11-27-flutter-browser-lane-hang.md`,
// task T121 briefing). Per that finding the browser attempt was not
// retried; a skipped or faked browser run is not evidence.
//
// What is asserted, and only that, on the host VM:
//   * the global banner shows the exact untranslated token `SIMULATED`,
//     the German context line, and the complete semantics label from the
//     error catalog §9;
//   * a low-confidence suggestion carries the dashed „unsicher“ badge
//     while a confident one does not (recognition-output §3.4);
//   * the composed surface reports `evidenceClass: SIMULATED` and never
//     presents itself as `EMULATOR`/`DEVICE` Android evidence (FR-087/
//     FR-088, constitution Principle VIII).

// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:feldexa_app/features/start/start_screen.dart';
import 'package:feldexa_app/main.dart';
import 'package:feldexa_ui/feldexa_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({required bool showBanner, required Widget child}) {
  return MaterialApp(
    theme: ThemeData.light(),
    home: Scaffold(
      body: Column(
        children: <Widget>[if (showBanner) const SimulatedBanner(), child],
      ),
    ),
  );
}

void main() {
  group('the SIMULATED banner is mounted on the simulated shell (T129)', () {
    testWidgets('FeldexaApp(simulatedShell: true) shows the global banner', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(FeldexaApp(simulatedShell: true));
      await tester.pump();
      // The persistent, non-dismissible banner sits above the surface.
      expect(find.byType(SimulatedBanner), findsOneWidget);
      expect(find.text(SimulatedEvidence.token), findsOneWidget);
      expect(find.textContaining('Entwicklungsansicht'), findsOneWidget);
    });

    testWidgets('the banner stays mounted above the pushed editor route', (
      WidgetTester tester,
    ) async {
      // FR-087: the banner wraps the Navigator (`MaterialApp.builder`), so
      // a pushed MaterialPageRoute cannot remove the labeling.
      await tester.pumpWidget(FeldexaApp(simulatedShell: true));
      await tester.pump();
      final BuildContext context = tester.element(find.byType(StartScreen));
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext routeContext) =>
                const Scaffold(body: SizedBox()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SimulatedBanner), findsOneWidget);
      expect(find.text(SimulatedEvidence.token), findsOneWidget);
    });

    testWidgets('FeldexaApp(simulatedShell: false) shows no banner', (
      WidgetTester tester,
    ) async {
      // Android shells never label themselves SIMULATED.
      await tester.pumpWidget(const FeldexaApp(simulatedShell: false));
      await tester.pump();
      expect(find.byType(SimulatedBanner), findsNothing);
    });

    test('the shell default follows the platform evidence class', () {
      // Production wiring: the Web build is the SIMULATED surface.
      expect(kIsWeb, isFalse, reason: 'this run is the host-VM lane');
      const FeldexaApp androidShell = FeldexaApp();
      expect(androidShell.simulatedShell, isFalse);
    });
  });

  group('the SIMULATED banner keeps the exact catalog surface (§9)', () {
    testWidgets('token, context line, and semantics label are exact', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(showBanner: true, child: const SizedBox()));
      expect(find.text(SimulatedEvidence.token), findsOneWidget);
      expect(find.textContaining('Entwicklungsansicht'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.byType(SimulatedBanner))
            .label
            .contains('SIMULATED'),
        isTrue,
      );
      expect(find.textContaining('EMULATOR'), findsNothing);
      expect(find.textContaining('DEVICE'), findsNothing);
    });

    test('the banner descriptor denies Android verification', () {
      expect(SimulatedEvidence.banner.isAndroidVerification, isFalse);
      expect(
        SimulatedEvidence.banner.toReportFields()['evidenceClass'],
        'SIMULATED',
      );
      expect(SimulatedEvidence.report.marker, 'evidenceClass: SIMULATED');
    });
  });

  group('uncertainty presentation under the SIMULATED surface', () {
    testWidgets('a low-confidence suggestion carries the uncertainty badge', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          showBanner: true,
          child: const Row(
            children: <Widget>[
              Expanded(
                child: UncertaintyBadge(
                  confidence: 0.30,
                  label: 'unsicher',
                  semanticsLabel: 'Vorschlag unsicher, bitte prüfen',
                ),
              ),
            ],
          ),
        ),
      );
      expect(find.text('unsicher'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.byType(UncertaintyBadge))
            .label
            .contains('unsicher'),
        isTrue,
      );
      // The composed surface is labeled SIMULATED and never as Android
      // runtime evidence.
      expect(find.text(SimulatedEvidence.token), findsOneWidget);
      expect(find.textContaining('EMULATOR'), findsNothing);
    });

    testWidgets('a confident suggestion carries no uncertainty badge', (
      WidgetTester tester,
    ) async {
      // The presentation rule §3.4: the badge exists only below 0.50; the
      // threshold helper is the single decision point shared with the
      // T071A outlines. Callers gate the badge on it.
      const double confident = 0.90;
      await tester.pumpWidget(
        _host(
          showBanner: false,
          child: UncertaintyThresholds.badgeRequired(confident)
              ? const UncertaintyBadge(confidence: confident, label: 'unsicher')
              : const SizedBox.shrink(),
        ),
      );
      expect(find.byType(UncertaintyBadge), findsNothing);
      expect(find.text('unsicher'), findsNothing);
    });
  });
}
