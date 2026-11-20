// T084 field-overflow warning host widget tests.
//
// Evidence class: NONE. These are host-VM widget tests with synthetic hosts
// and the committed German ARB/catalog. They build no platform channel, open
// no document, invoke no editor, store, file, network, or localization service,
// and make no Android, device, screen-reader, or visual claim.
//
// They prove the pinned T084 behaviour:
//   * `visible: false` renders a zero-height placeholder with no key, text,
//     error icon, or live-region semantics;
//   * `visible: true` renders exactly the `fld001` and `fld001Recovery` ARB
//     sentences, an error icon, the stable key, and one live-region node that
//     carries both sentences;
//   * the FLD-001 row matches the generated German text and the ARB, states
//     that export is stopped, and does not contradict the EXP-001 row;
//   * the warning has no dismiss control and disappears only when the caller
//     rebuilds with `visible: false`;
//   * 200 % text scale in a narrow bounded width reflows both untruncated
//     sentences without exception or overflow;
//   * the production source imports only Flutter and the generated
//     localization, with no file, store, network, or editor access.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:feldexa_app/features/fill/overflow_warning.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

const String _catalogPath =
    '../../specs/001-scanned-form-workflow/contracts/error-catalog.de.md';
const String _arbPath = 'lib/l10n/app_de.arb';

/// Narrow bounded width used to force wrapping at 200 % text scale.
const double _narrowWidth = 280;

final AppLocalizations _de = lookupAppLocalizations(const Locale('de'));

Widget _host({required bool visible, double textScale = 1.0}) {
  return MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (BuildContext context, Widget? child) {
      return MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      );
    },
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          child: SizedBox(
            width: _narrowWidth,
            child: FieldOverflowWarning(visible: visible),
          ),
        ),
      ),
    ),
  );
}

Iterable<SemanticsNode> _traversal(WidgetTester tester) {
  return tester.semantics.simulatedAccessibilityTraversal();
}

Iterable<SemanticsNode> _liveRegions(WidgetTester tester) {
  return _traversal(tester).where(
    (SemanticsNode node) =>
        node.getSemanticsData().flagsCollection.isLiveRegion,
  );
}

/// German quotes wrap every catalog text; nested quotes make the match greedy
/// from the first opening to the last closing quote.
String? _quoted(String cell) {
  final int start = cell.indexOf('„');
  final int end = cell.lastIndexOf('“');
  if (start < 0 || end <= start) {
    return null;
  }
  return cell.substring(start + 1, end);
}

List<String> _cells(String line) {
  final String trimmed = line.trim();
  return trimmed
      .substring(1, trimmed.length - 1)
      .split('|')
      .map((String cell) => cell.trim())
      .toList();
}

/// Reads the message and recovery cells for [code] from the catalog tables.
({String message, String recovery}) _catalogRow(String catalog, String code) {
  for (final String line in catalog.split('\n')) {
    if (!line.startsWith('|')) {
      continue;
    }
    final List<String> cells = _cells(line);
    if (cells.length < 4 || cells[0] != '`$code`') {
      continue;
    }
    final String? message = _quoted(cells[2]);
    final String? recovery = _quoted(cells[3]);
    if (message == null || recovery == null) {
      break;
    }
    return (message: message, recovery: recovery);
  }
  fail('contracts/error-catalog.de.md has no quoted $code row');
}

void main() {
  testWidgets('visible false renders nothing and reserves no space', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();

    await tester.pumpWidget(_host(visible: false));

    expect(find.byType(FieldOverflowWarning), findsOneWidget);
    expect(tester.getSize(find.byType(FieldOverflowWarning)).height, 0);
    expect(find.byKey(fieldOverflowWarningKey), findsNothing);
    expect(find.text(_de.fld001), findsNothing);
    expect(find.text(_de.fld001Recovery), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(_liveRegions(tester), isEmpty);
    expect(
      _traversal(tester).where((SemanticsNode node) {
        final String label = node.getSemanticsData().label;
        return label.contains(_de.fld001) || label.contains(_de.fld001Recovery);
      }),
      isEmpty,
    );

    handle.dispose();
  });

  testWidgets(
    'visible true renders the exact FLD-001 texts and one live region',
    (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpWidget(_host(visible: true));

      expect(find.byKey(fieldOverflowWarningKey), findsOneWidget);
      expect(find.text(_de.fld001), findsOneWidget);
      expect(find.text(_de.fld001Recovery), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.error_outline)).semanticLabel,
        isNull,
      );

      final SemanticsNode warning = tester.getSemantics(
        find.byKey(fieldOverflowWarningKey),
      );
      final SemanticsData data = warning.getSemanticsData();
      expect(data.flagsCollection.isLiveRegion, isTrue);
      expect(data.label, contains(_de.fld001));
      expect(data.label, contains(_de.fld001Recovery));

      final Iterable<SemanticsNode> liveRegions = _liveRegions(tester);
      expect(liveRegions, hasLength(1));
      expect(liveRegions.single.id, warning.id);

      // The visible text is not a second set of semantic nodes; the warning is
      // announced once with both sentences.
      final Iterable<SemanticsNode> messageNodes = _traversal(tester).where(
        (SemanticsNode node) =>
            node.getSemanticsData().label.contains(_de.fld001),
      );
      expect(messageNodes, hasLength(1));
      expect(messageNodes.single.id, warning.id);

      handle.dispose();
    },
  );

  test('FLD-001 and EXP-001 rows agree with the ARB and stop export', () {
    final String catalog = File(_catalogPath).readAsStringSync();
    final Map<String, dynamic> arb =
        jsonDecode(File(_arbPath).readAsStringSync()) as Map<String, dynamic>;

    final ({String message, String recovery}) fld = _catalogRow(
      catalog,
      'FLD-001',
    );
    final ({String message, String recovery}) exp = _catalogRow(
      catalog,
      'EXP-001',
    );

    expect(fld.message, _de.fld001);
    expect(fld.recovery, _de.fld001Recovery);
    expect(fld.message, arb['fld001']);
    expect(fld.recovery, arb['fld001Recovery']);

    // CHK030: the FLD-001 surface promises that export is stopped, not that
    // the text may merely be clipped or lost.
    expect(fld.message, contains('Export wird gestoppt'));
    for (final String clippedWording in <String>[
      'abgeschnitten',
      'beschnitten',
      'möglicherweise',
      'eventuell',
      'könnte',
      'ggf.',
    ]) {
      expect(
        fld.message,
        isNot(contains(clippedWording)),
        reason: 'FLD-001 must not use possibly-clipped wording.',
      );
    }

    expect(exp.message, contains('Der Export wurde gestoppt'));
    expect(exp.message, contains('Es wurde keine PDF-Datei erstellt.'));

    // Both rows instruct the user to shorten the text and/or enlarge the
    // field, and neither promises that export continues unchanged.
    for (final String row in <String>[
      '${fld.message} ${fld.recovery}',
      '${exp.message} ${exp.recovery}',
    ]) {
      expect(row, contains('kürzen'));
      expect(row, contains('vergrößern'));
      expect(row, isNot(contains('fortgesetzt')));
      expect(row, isNot(contains('weiterhin exportiert')));
      expect(row, isNot(contains('trotzdem')));
    }
  });

  testWidgets('no dismiss control and a rebuild with visible false clears it', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();

    await tester.pumpWidget(_host(visible: true));

    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(Dismissible), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byIcon(Icons.cancel), findsNothing);

    final SemanticsData data = tester
        .getSemantics(find.byKey(fieldOverflowWarningKey))
        .getSemanticsData();
    expect(data.hasAction(SemanticsAction.dismiss), isFalse);
    expect(data.hasAction(SemanticsAction.tap), isFalse);

    await tester.pumpWidget(_host(visible: false));

    expect(find.byKey(fieldOverflowWarningKey), findsNothing);
    expect(find.text(_de.fld001), findsNothing);
    expect(find.text(_de.fld001Recovery), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(_liveRegions(tester), isEmpty);
    expect(tester.getSize(find.byType(FieldOverflowWarning)).height, 0);

    handle.dispose();
  });

  testWidgets('200 percent scale reflows in a narrow width without overflow', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(visible: true));
    final double regularHeight = tester
        .getSize(find.byKey(fieldOverflowWarningKey))
        .height;
    final double regularRecoveryHeight = tester
        .getSize(find.text(_de.fld001Recovery))
        .height;
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_host(visible: true, textScale: 2.0));

    expect(tester.takeException(), isNull);
    expect(find.byKey(fieldOverflowWarningKey), findsOneWidget);
    expect(find.text(_de.fld001), findsOneWidget);
    expect(find.text(_de.fld001Recovery), findsOneWidget);

    final Rect warningRect = tester.getRect(
      find.byKey(fieldOverflowWarningKey),
    );
    expect(warningRect.width, lessThanOrEqualTo(_narrowWidth));
    expect(
      tester.getSize(find.byKey(fieldOverflowWarningKey)).height,
      greaterThan(regularHeight),
    );
    expect(
      tester.getSize(find.text(_de.fld001Recovery)).height,
      greaterThan(regularRecoveryHeight),
    );

    final Text message = tester.widget<Text>(find.text(_de.fld001));
    final Text recovery = tester.widget<Text>(find.text(_de.fld001Recovery));
    for (final Text text in <Text>[message, recovery]) {
      expect(text.maxLines, isNull);
      expect(text.overflow, isNull);
    }
    expect(
      tester.getRect(find.text(_de.fld001)).left,
      greaterThanOrEqualTo(warningRect.left),
    );
    expect(
      tester.getRect(find.text(_de.fld001Recovery)).right,
      lessThanOrEqualTo(warningRect.right),
    );
  });

  test('production source stays presentation-only', () {
    final File file = File('lib/features/fill/overflow_warning.dart');
    expect(file.existsSync(), isTrue);

    final String source = file.readAsStringSync();
    final List<String> imports = RegExp(
      r"^import '([^']+)';",
      multiLine: true,
    ).allMatches(source).map((Match match) => match.group(1)!).toList();

    expect(imports, <String>[
      'package:feldexa_app/l10n/app_localizations.dart',
      'package:flutter/material.dart',
    ]);
    expect(source, contains('l10n.fld001'));
    expect(source, contains('l10n.fld001Recovery'));
    for (final String forbidden in <String>[
      'dart:io',
      'dart:convert',
      'HttpClient',
      'File(',
      'Directory(',
      'Uint8List',
      'path_provider',
      'shared_preferences',
      'sqflite',
      'feldexa_ports',
      'feldexa_application',
      'features/editor',
    ]) {
      expect(
        source,
        isNot(contains(forbidden)),
        reason: 'The warning must not import or call $forbidden.',
      );
    }
  });
}
