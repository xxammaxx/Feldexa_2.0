// T012 widget and accessibility contract for the shared SIMULATED evidence
// surface (FR-087; constitution Principle II; error-catalog.de.md §9).
//
// These tests are host-VM tests. The separate `--platform chrome` run of the
// same file is SIMULATED browser evidence; neither run is Android evidence.

import 'dart:math' as math;

import 'package:feldexa_ui/feldexa_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SimulatedEvidence shared production logic', () {
    test('every surface carries the exact untranslated SIMULATED token', () {
      expect(SimulatedEvidence.token, 'SIMULATED');
      expect(SimulatedEvidence.logPrefix, '[SIMULATED]');
      expect(SimulatedEvidence.reportField, 'evidenceClass: SIMULATED');
      expect(SimulatedEvidence.evidenceClass, 'SIMULATED');

      for (final SimulatedSurface surface in SimulatedSurface.values) {
        final SimulatedEvidence evidence = SimulatedEvidence.of(surface);

        expect(evidence.surface, surface);
        expect(evidence.marker, contains(SimulatedEvidence.token));
        expect(evidence.marker, isNot(contains('SIMULIERT')));
        expect(SimulatedEvidence.evidenceClass, SimulatedEvidence.token);
        expect(evidence.toReportFields(), <String, Object?>{
          'evidenceClass': 'SIMULATED',
        });
      }
    });

    test('catalogued German contexts match error-catalog.de.md §9 exactly', () {
      expect(
        SimulatedEvidence.of(SimulatedSurface.globalBanner).germanContext,
        'Entwicklungsansicht: Plattformfunktionen sind simuliert. '
        'Ergebnisse gelten nicht als Android-Nachweis.',
      );
      expect(
        SimulatedEvidence.of(SimulatedSurface.exportFooter).germanContext,
        'Simuliertes PDF – kein Produktionsartefakt.',
      );
      expect(
        SimulatedEvidence.of(SimulatedSurface.storage).germanContext,
        'Simulierter Speicher – keine echte Verschlüsselung.',
      );
      expect(SimulatedEvidence.of(SimulatedSurface.log).germanContext, isNull);
      expect(
        SimulatedEvidence.of(SimulatedSurface.report).germanContext,
        isNull,
      );
    });

    test(
      'markers distinguish the banner, log, report, and overlay surfaces',
      () {
        expect(
          SimulatedEvidence.of(SimulatedSurface.globalBanner).marker,
          'SIMULATED',
        );
        expect(
          SimulatedEvidence.of(SimulatedSurface.log).marker,
          '[SIMULATED]',
        );
        expect(
          SimulatedEvidence.of(SimulatedSurface.exportFooter).marker,
          'SIMULATED',
        );
        expect(
          SimulatedEvidence.of(SimulatedSurface.report).marker,
          'evidenceClass: SIMULATED',
        );
        expect(
          SimulatedEvidence.of(SimulatedSurface.storage).marker,
          'SIMULATED',
        );
      },
    );

    test('the banner accessibility label is the contract string', () {
      expect(
        SimulatedEvidence.bannerSemanticsLabel,
        'SIMULATED – Entwicklungsansicht mit simulierten '
        'Plattformfunktionen. Keine Android-Prüfung.',
      );
      expect(
        SimulatedEvidence.of(SimulatedSurface.globalBanner).semanticsLabel,
        SimulatedEvidence.bannerSemanticsLabel,
      );
    });

    test('no surface claims Android verification or production status', () {
      for (final SimulatedSurface surface in SimulatedSurface.values) {
        final SimulatedEvidence evidence = SimulatedEvidence.of(surface);

        expect(evidence.isAndroidVerification, isFalse);
        expect(evidence.isProductionArtifact, isFalse);
        expect(evidence.semanticsLabel, startsWith('SIMULATED'));
        expect(evidence.semanticsLabel, contains('Android'));
        expect(
          evidence.semanticsLabel.toLowerCase(),
          contains('kein'),
          reason: '$surface must explicitly deny Android evidence',
        );
      }
    });

    test('descriptors are stable value objects per surface', () {
      for (final SimulatedSurface surface in SimulatedSurface.values) {
        expect(
          identical(
            SimulatedEvidence.of(surface),
            SimulatedEvidence.of(surface),
          ),
          isTrue,
        );
      }
    });
  });

  group('SimulatedBanner widget', () {
    testWidgets('renders the token and German context exactly', (
      WidgetTester tester,
    ) async {
      await _pumpSurface(tester, const SimulatedBanner());

      expect(find.text('SIMULATED'), findsOneWidget);
      expect(
        find.text(
          'Entwicklungsansicht: Plattformfunktionen sind simuliert. '
          'Ergebnisse gelten nicht als Android-Nachweis.',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.science_outlined), findsOneWidget);
    });

    testWidgets('exposes the full accessibility label as one semantic node', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await _pumpSurface(tester, const SimulatedBanner());

      final SemanticsNode node = tester.getSemantics(
        find.byType(SimulatedBanner),
      );
      expect(node.label, SimulatedEvidence.bannerSemanticsLabel);
      expect(node.label, contains('Keine Android-Prüfung'));
      handle.dispose();
    });

    testWidgets('has no dismiss control that could hide the marker', (
      WidgetTester tester,
    ) async {
      await _pumpSurface(tester, const SimulatedBanner());

      expect(find.byType(IconButton), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('schließen|ausblenden')),
        findsNothing,
      );
    });

    testWidgets('stays readable at 200% text scale on a narrow screen', (
      WidgetTester tester,
    ) async {
      await _pumpSurface(
        tester,
        const SimulatedBanner(),
        textScaler: const TextScaler.linear(2),
        size: const Size(320, 640),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('SIMULATED'), findsOneWidget);
      expect(find.text(SimulatedEvidence.bannerContext), findsOneWidget);

      final Rect tokenRect = tester.getRect(find.text('SIMULATED'));
      final Rect contextRect = tester.getRect(
        find.text(SimulatedEvidence.bannerContext),
      );
      expect(tokenRect.right, lessThanOrEqualTo(320));
      expect(contextRect.right, lessThanOrEqualTo(320));
    });

    testWidgets('meets 4.5:1 contrast for token and context text', (
      WidgetTester tester,
    ) async {
      await _pumpSurface(tester, const SimulatedBanner());

      final double tokenContrast = _contrastRatio(
        SimulatedBanner.tokenColor,
        SimulatedBanner.backgroundColor,
      );
      final double contextContrast = _contrastRatio(
        SimulatedBanner.contextColor,
        SimulatedBanner.backgroundColor,
      );

      expect(tokenContrast, greaterThanOrEqualTo(4.5));
      expect(contextContrast, greaterThanOrEqualTo(4.5));
    });
  });

  group('SimulatedEvidenceLabel widget', () {
    for (final SimulatedSurface surface in SimulatedSurface.values) {
      testWidgets('renders the $surface marker and semantic label', (
        WidgetTester tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();

        final SimulatedEvidence evidence = SimulatedEvidence.of(surface);
        await _pumpSurface(
          tester,
          SizedBox(width: 360, child: SimulatedEvidenceLabel(surface: surface)),
        );

        expect(find.text(evidence.marker), findsOneWidget);
        if (evidence.germanContext != null) {
          expect(find.text(evidence.germanContext!), findsOneWidget);
        } else {
          expect(find.byType(Text), findsOneWidget);
        }

        final SemanticsNode node = tester.getSemantics(
          find.byType(SimulatedEvidenceLabel),
        );
        expect(node.label, evidence.semanticsLabel);
        expect(node.label, contains('SIMULATED'));
        handle.dispose();
      });
    }

    testWidgets('wraps the longest context at 200% text scale', (
      WidgetTester tester,
    ) async {
      await _pumpSurface(
        tester,
        const SizedBox(
          width: 280,
          child: SimulatedEvidenceLabel(surface: SimulatedSurface.exportFooter),
        ),
        textScaler: const TextScaler.linear(2),
        size: const Size(320, 640),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('SIMULATED'), findsOneWidget);
      expect(
        find.text('Simuliertes PDF – kein Produktionsartefakt.'),
        findsOneWidget,
      );
    });
  });
}

Future<void> _pumpSurface(
  WidgetTester tester,
  Widget child, {
  TextScaler textScaler = TextScaler.noScaling,
  Size size = const Size(400, 240),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

double _contrastRatio(Color foreground, Color background) {
  final double lighter = math.max(
    foreground.computeLuminance(),
    background.computeLuminance(),
  );
  final double darker = math.min(
    foreground.computeLuminance(),
    background.computeLuminance(),
  );
  return (lighter + 0.05) / (darker + 0.05);
}
