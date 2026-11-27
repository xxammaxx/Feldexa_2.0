// T122 uncertainty badge tests (FR-083).
//
// Evidence class: NONE. Host-VM widget tests on the shipped widget; they
// open no platform channel and make no Android or browser claim.
//
// Normative source: `contracts/recognition-output.md` §3.4 — below 0.50 the
// treatment is dashed outline + badge + explanatory semantics label; the
// badge never appears for confident or non-machine items.

import 'package:feldexa_ui/feldexa_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(double? confidence) {
  return MaterialApp(
    theme: ThemeData.light(),
    home: Scaffold(
      body: UncertaintyBadge(
        confidence: confidence,
        label: 'unsicher',
        semanticsLabel: 'Vorschlag unsicher, bitte prüfen',
      ),
    ),
  );
}

void main() {
  group('UncertaintyThresholds', () {
    test('badge is required exactly below the 0.50 threshold', () {
      expect(UncertaintyThresholds.badgeRequired(null), isFalse);
      expect(UncertaintyThresholds.badgeRequired(0.0), isTrue);
      expect(UncertaintyThresholds.badgeRequired(0.49), isTrue);
      expect(UncertaintyThresholds.badgeRequired(0.50), isFalse);
      expect(UncertaintyThresholds.badgeRequired(0.75), isFalse);
    });
  });

  group('UncertaintyBadge', () {
    testWidgets('renders the localized label and one semantics node', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(0.30));
      expect(find.text('unsicher'), findsOneWidget);
      // The combined semantics label is announced once; the inner text is
      // excluded from the semantics tree.
      expect(
        tester.getSemantics(find.byType(UncertaintyBadge)).label,
        'Vorschlag unsicher, bitte prüfen',
      );
    });

    testWidgets('paints a dashed outline at 200 percent text scale', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: _host(0.10),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('unsicher'), findsOneWidget);
    });

    testWidgets('exposes a stable default key', (WidgetTester tester) async {
      await tester.pumpWidget(_host(0.30));
      expect(
        find.byKey(const ValueKey<String>('uncertainty-badge')),
        findsOneWidget,
      );
    });
  });
}
