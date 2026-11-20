// T074 provenance-badge widget and accessibility contract tests.
//
// These are host-VM widget tests (evidence class NONE). They pin the visual
// provenance mapping from `contracts/editor-interactions.md` §3 and §11,
// `data-model.md` §2.4/§3.4/§3.5, FR-028, and FR-094:
//   * each kind renders its exact color, icon, text, and stable default key;
//   * an opaque, solid 1.5 px outlined pill is used (never color alone);
//   * exactly one non-interactive semantic node exposes the caller label and
//     the visual text is excluded from semantics;
//   * every outline/text color clears the WCAG 3:1 floor against white;
//   * empty and whitespace-only labels throw content-free `ArgumentError`s;
//   * compact padding and typography are smaller, and several badges survive
//     200 % text scale in a narrow `Wrap`;
//   * labels are synthetic and caller-supplied, never built into the package.
//
// No Android, TalkBack, device, browser, or visual evidence is claimed.

import 'dart:math' as math;

import 'package:feldexa_ui/feldexa_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

const String _suggestionLabel = 'Machine proposal';
const String _confirmedLabel = 'Confirmed field';
const String _userCreatedLabel = 'Created by user';
const String _templateLabel = 'Template layout';

String _labelFor(ProvenanceBadgeKind kind) => switch (kind) {
  ProvenanceBadgeKind.suggestion => _suggestionLabel,
  ProvenanceBadgeKind.confirmed => _confirmedLabel,
  ProvenanceBadgeKind.userCreated => _userCreatedLabel,
  ProvenanceBadgeKind.template => _templateLabel,
};

void main() {
  group('ProvenanceBadgeKind mapping', () {
    test('pins the four contract colors and icons', () {
      expect(ProvenanceBadgeKind.suggestion.color, const Color(0xFF1565C0));
      expect(ProvenanceBadgeKind.suggestion.icon, Icons.auto_awesome);

      expect(ProvenanceBadgeKind.confirmed.color, const Color(0xFF2E7D32));
      expect(ProvenanceBadgeKind.confirmed.icon, Icons.verified);

      expect(ProvenanceBadgeKind.userCreated.color, const Color(0xFFE65100));
      expect(ProvenanceBadgeKind.userCreated.icon, Icons.edit);

      expect(ProvenanceBadgeKind.template.color, const Color(0xFF7B1FA2));
      expect(ProvenanceBadgeKind.template.icon, Icons.dashboard_customize);
    });

    test('every outline and text color meets 3:1 contrast against white', () {
      for (final ProvenanceBadgeKind kind in ProvenanceBadgeKind.values) {
        expect(
          _contrastAgainstWhite(kind.color),
          greaterThanOrEqualTo(3.0),
          reason: '${kind.name} must meet the WCAG 3:1 non-text floor',
        );
      }
    });
  });

  group('ProvenanceBadge rendering', () {
    for (final ProvenanceBadgeKind kind in ProvenanceBadgeKind.values) {
      testWidgets('renders ${kind.name} text, icon, outline, and default key', (
        WidgetTester tester,
      ) async {
        final String label = _labelFor(kind);

        await _pumpBadge(tester, ProvenanceBadge(kind: kind, text: label));

        expect(find.text(label), findsOneWidget);
        expect(find.byIcon(kind.icon), findsOneWidget);

        final ProvenanceBadge badge = tester.widget<ProvenanceBadge>(
          find.byType(ProvenanceBadge),
        );
        final ValueKey<String> defaultKey = ValueKey<String>(
          'provenance-badge-${kind.name}',
        );
        expect(badge.key, defaultKey);
        expect(find.byKey(defaultKey), findsOneWidget);

        final Text textWidget = tester.widget<Text>(find.text(label));
        expect(textWidget.data, label);
        expect(textWidget.style?.color, kind.color);
        expect(textWidget.style?.fontSize, ProvenanceBadge.fontSize);

        final Icon iconWidget = tester.widget<Icon>(find.byIcon(kind.icon));
        expect(iconWidget.color, kind.color);
        expect(iconWidget.size, ProvenanceBadge.iconSize);

        final DecoratedBox box = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.byType(ProvenanceBadge),
            matching: find.byType(DecoratedBox),
          ),
        );
        final BoxDecoration decoration = box.decoration as BoxDecoration;
        expect(decoration.color, ProvenanceBadge.backgroundColor);
        expect(decoration.borderRadius, ProvenanceBadge.borderRadius);

        final Border border = decoration.border! as Border;
        expect(border.top.color, kind.color);
        expect(border.top.width, ProvenanceBadge.outlineWidth);
        expect(border.top.style, BorderStyle.solid);
      });
    }

    testWidgets('caller-supplied key overrides the stable default', (
      WidgetTester tester,
    ) async {
      const ValueKey<String> customKey = ValueKey<String>('custom-badge');

      await _pumpBadge(
        tester,
        ProvenanceBadge(
          kind: ProvenanceBadgeKind.suggestion,
          text: _suggestionLabel,
          key: customKey,
        ),
      );

      expect(find.byKey(customKey), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('provenance-badge-suggestion')),
        findsNothing,
      );
    });

    testWidgets('uses only caller-supplied, non-German labels', (
      WidgetTester tester,
    ) async {
      const String first = 'Synthetic provenance A';
      const String second = 'Synthetic provenance B';

      await _pumpBadge(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ProvenanceBadge(kind: ProvenanceBadgeKind.suggestion, text: first),
            ProvenanceBadge(
              kind: ProvenanceBadgeKind.suggestion,
              text: second,
              key: ValueKey<String>('second-suggestion'),
            ),
          ],
        ),
      );

      expect(find.text(first), findsOneWidget);
      expect(find.text(second), findsOneWidget);
      expect(tester.widget<Text>(find.text(first)).data, first);
      expect(tester.widget<Text>(find.text(second)).data, second);
    });
  });

  group('ProvenanceBadge semantics', () {
    testWidgets('falls back to text in one non-interactive semantic node', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await _pumpBadge(
        tester,
        ProvenanceBadge(
          kind: ProvenanceBadgeKind.suggestion,
          text: _suggestionLabel,
        ),
      );

      final SemanticsNode node = tester.getSemantics(
        find.byType(ProvenanceBadge),
      );
      final SemanticsData data = node.getSemanticsData();

      expect(data.label, _suggestionLabel);
      expect(node.childrenCount, 0);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(data.flagsCollection.isButton, isFalse);
      expect(find.bySemanticsLabel(_suggestionLabel), findsOneWidget);
      handle.dispose();
    });

    testWidgets('exposes semanticsLabel and excludes duplicate visual text', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      const String semanticLabel = 'Provenance: confirmed machine field';

      await _pumpBadge(
        tester,
        ProvenanceBadge(
          kind: ProvenanceBadgeKind.confirmed,
          text: _confirmedLabel,
          semanticsLabel: semanticLabel,
        ),
      );

      final SemanticsNode node = tester.getSemantics(
        find.byType(ProvenanceBadge),
      );
      final SemanticsData data = node.getSemanticsData();

      expect(data.label, semanticLabel);
      expect(data.label, isNot(_confirmedLabel));
      expect(node.childrenCount, 0);
      expect(find.bySemanticsLabel(semanticLabel), findsOneWidget);
      expect(find.bySemanticsLabel(_confirmedLabel), findsNothing);
      handle.dispose();
    });
  });

  group('ProvenanceBadge validation', () {
    test('empty and whitespace-only text throw content-free errors', () {
      const List<String> whitespaceInputs = <String>[
        '   ',
        '\t\t',
        '\n\n  ',
        ' \t\n ',
      ];

      expect(
        () => ProvenanceBadge(kind: ProvenanceBadgeKind.userCreated, text: ''),
        throwsArgumentError,
      );

      for (final String input in whitespaceInputs) {
        Object? error;
        try {
          ProvenanceBadge(kind: ProvenanceBadgeKind.userCreated, text: input);
        } on Object catch (caught) {
          error = caught;
        }

        expect(error, isA<ArgumentError>(), reason: 'input ${input.runes}');
        final String message = error.toString();
        expect(message, contains('must not be empty'));
        expect(
          message,
          isNot(contains(input)),
          reason: 'the error must not echo the supplied text',
        );
      }
    });
  });

  group('ProvenanceBadge compact and text scaling', () {
    testWidgets('compact uses smaller padding, icon, and typography', (
      WidgetTester tester,
    ) async {
      await _pumpBadge(
        tester,
        ProvenanceBadge(
          kind: ProvenanceBadgeKind.suggestion,
          text: _suggestionLabel,
        ),
      );
      final Size normalSize = tester.getSize(find.byType(ProvenanceBadge));
      expect(
        tester.widget<Text>(find.text(_suggestionLabel)).style?.fontSize,
        ProvenanceBadge.fontSize,
      );

      await _pumpBadge(
        tester,
        ProvenanceBadge(
          kind: ProvenanceBadgeKind.suggestion,
          text: _suggestionLabel,
          compact: true,
        ),
      );
      final Size compactSize = tester.getSize(find.byType(ProvenanceBadge));
      expect(
        tester.widget<Text>(find.text(_suggestionLabel)).style?.fontSize,
        ProvenanceBadge.compactFontSize,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.auto_awesome)).size,
        ProvenanceBadge.compactIconSize,
      );

      expect(
        ProvenanceBadge.compactPadding.horizontal,
        lessThan(ProvenanceBadge.padding.horizontal),
      );
      expect(
        ProvenanceBadge.compactPadding.vertical,
        lessThan(ProvenanceBadge.padding.vertical),
      );
      expect(
        ProvenanceBadge.compactFontSize,
        lessThan(ProvenanceBadge.fontSize),
      );
      expect(
        ProvenanceBadge.compactIconSize,
        lessThan(ProvenanceBadge.iconSize),
      );
      expect(compactSize.height, lessThan(normalSize.height));
    });

    testWidgets('several badges reflow in a narrow Wrap at 200% text scale', (
      WidgetTester tester,
    ) async {
      await _pumpBadge(
        tester,
        SizedBox(
          width: 300,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final ProvenanceBadgeKind kind in ProvenanceBadgeKind.values)
                ProvenanceBadge(kind: kind, text: _labelFor(kind)),
            ],
          ),
        ),
        textScaler: const TextScaler.linear(2),
        size: const Size(320, 640),
      );

      expect(tester.takeException(), isNull);
      for (final ProvenanceBadgeKind kind in ProvenanceBadgeKind.values) {
        final Finder badgeFinder = find.byKey(
          ValueKey<String>('provenance-badge-${kind.name}'),
        );
        expect(badgeFinder, findsOneWidget);
        expect(find.text(_labelFor(kind)), findsOneWidget);

        final Rect rect = tester.getRect(badgeFinder);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
      }
    });
  });
}

Future<void> _pumpBadge(
  WidgetTester tester,
  Widget child, {
  TextScaler textScaler = TextScaler.noScaling,
  Size size = const Size(320, 240),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: Scaffold(
          body: SingleChildScrollView(child: Center(child: child)),
        ),
      ),
    ),
  );
}

double _contrastAgainstWhite(Color color) {
  const Color white = Color(0xFFFFFFFF);
  final double lighter = math.max(
    white.computeLuminance(),
    color.computeLuminance(),
  );
  final double darker = math.min(
    white.computeLuminance(),
    color.computeLuminance(),
  );
  return (lighter + 0.05) / (darker + 0.05);
}
