// T086C FLD-001 overflow-warning host tests (issue #281).
//
// Evidence class: NONE. These are host-VM widget tests with a caller-owned fake
// commit callback and the committed German ARB. They open no document, store,
// PDF, platform channel, emulator, or device, and make no Android,
// screen-reader, or visual claim.
//
// They prove the productive wiring:
//   * a text that no longer fits the field display region commits with the
//     existing `TextValue.overflow` flag set, shows the existing
//     `FieldOverflowWarning`, and leaves the sheet open immediately after the
//     commit (contract `editor-interactions.md` §5);
//   * the complete entered value is handed to the caller — nothing is
//     truncated, shortened, or dropped (FR-038);
//   * a value that still fits commits with `overflow == false` and closes the
//     sheet without a warning;
//   * reopening a stored overflowing value shows the warning and the full
//     text again, so the persisted flag is what the user sees;
//   * a second save of the already-committed overflowing draft adds no second
//     commit, and a shortened draft clears the warning;
//   * multiline line counting, number/date representation, and the
//     checkbox (no clipable text) behave per the same rule.
//
// The measurement uses the bundled `assets/fonts/metrics.json` advance table
// (`loadFieldTextMeasure`), so these expectations are the same on a host and on
// a device and do not depend on a test font.

@TestOn('vm')
library;

import 'dart:async';

import 'package:feldexa_app/features/editor/field_value_sheet.dart';
import 'package:feldexa_app/features/fill/field_text_fit.dart';
import 'package:feldexa_app/features/fill/overflow_warning.dart';
import 'package:feldexa_app/features/fill/signature_sheet.dart';
import 'package:feldexa_app/features/fill/text_control.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _fieldId = '11111111-1111-4111-8111-111111111111';
const ValueKey<String> _openSheetKey = ValueKey<String>('open-value-sheet');
final DateTime _createdAt = DateTime.utc(2026, 11, 22, 8);
final AppLocalizations _de = lookupAppLocalizations(const Locale('de'));

/// A field that is 100 × 20 display points: 97 × 17 pt of usable text area at
/// the 12 pt font size the export layout picks for this height.
final core.Rect _narrowRect = core.Rect.fromLTWH(20, 20, 100, 20);

/// A field that comfortably holds one or two short lines.
final core.Rect _wideRect = core.Rect.fromLTWH(20, 20, 300, 60);

core.ConfirmedField _field(core.FieldType type, {core.Rect? rect}) {
  return core.ConfirmedField(
    id: _fieldId,
    pageIndex: 0,
    rect: rect ?? _narrowRect,
    type: type,
    provenance: core.Provenance.user,
    label: 'Name',
    order: 0,
    createdAt: _createdAt,
    updatedAt: _createdAt,
  );
}

/// Pumps a host surface whose button opens the real modal bottom-sheet route.
Future<void> _pumpSheet(
  WidgetTester tester, {
  required core.FieldType type,
  core.Rect? rect,
  core.FieldValue? currentValue,
  List<core.FieldValue>? commits,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const <Locale>[Locale('de')],
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) {
            return Center(
              child: TextButton(
                key: _openSheetKey,
                onPressed: () {
                  unawaited(
                    showModalBottomSheet<FieldValueSheetOutcome>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (BuildContext context) {
                        return FieldValueSheet(
                          field: _field(type, rect: rect),
                          currentValue: currentValue,
                          onCommit: (core.FieldValue value) async {
                            commits?.add(value);
                            return const FieldValueCommitResult.saved();
                          },
                          onSignatureCommit: (SignatureDraft _) async {
                            return const FieldValueCommitResult.saved();
                          },
                        );
                      },
                    ),
                  );
                },
                child: const Text('Öffnen'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(_openSheetKey));
  await tester.pumpAndSettle();
  expect(find.byKey(fieldValueSheetKey), findsOneWidget);
}

String _enteredText(WidgetTester tester) {
  return tester
      .widget<TextField>(find.byKey(fieldTextControlInputKey))
      .controller!
      .text;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The production path reads the bundled advance table during startup; the
  // host tests do the same once, so every measurement below is the real
  // Noto Sans arithmetic and not a test-font approximation.
  setUpAll(() async {
    expect(await initializeFieldTextMeasure(), isTrue);
  });

  testWidgets('text longer than the field display region sets overflow', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    await _pumpSheet(tester, type: core.FieldType.text, commits: commits);

    // 200 characters: far wider than the 97 pt available width.
    final String tooLong = 'Müller-Lüdenscheid ${'x' * 180}';
    await tester.enterText(find.byKey(fieldTextControlInputKey), tooLong);
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();

    expect(commits, hasLength(1));
    final core.TextValue stored = commits.single as core.TextValue;
    expect(stored.overflow, isTrue);
    // No silent truncation: the complete value is committed.
    expect(stored.text, tooLong);
    expect(stored.text.runes.length, tooLong.runes.length);
  });

  testWidgets('the FLD-001 warning is visible immediately after the commit', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    await _pumpSheet(tester, type: core.FieldType.text, commits: commits);

    expect(find.byKey(fieldOverflowWarningKey), findsNothing);
    await tester.enterText(
      find.byKey(fieldTextControlInputKey),
      'Erika Mustermann und Maximilian Mustermann',
    );
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();

    // The sheet stays open on the overflowing value so the warning is read
    // immediately, not only after reopening the field.
    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    expect(find.byKey(fieldOverflowWarningKey), findsOneWidget);
    expect(find.text(_de.fld001), findsOneWidget);
    expect(find.text(_de.fld001Recovery), findsOneWidget);
    // The draft is still complete in the control.
    expect(_enteredText(tester), 'Erika Mustermann und Maximilian Mustermann');
  });

  testWidgets('a text that still fits commits without a warning and closes', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    await _pumpSheet(tester, type: core.FieldType.text, commits: commits);

    await tester.enterText(find.byKey(fieldTextControlInputKey), 'Erika');
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();

    expect(commits, hasLength(1));
    expect((commits.single as core.TextValue).overflow, isFalse);
    expect(find.byKey(fieldValueSheetKey), findsNothing);
    expect(find.byKey(fieldOverflowWarningKey), findsNothing);
  });

  testWidgets('a stored overflowing value reopens with warning and full text', (
    tester,
  ) async {
    final String tooLong = 'Zeile ${'M' * 120}';
    await _pumpSheet(
      tester,
      type: core.FieldType.text,
      currentValue: core.TextValue(
        text: tooLong,
        lastEditedAt: _createdAt,
        overflow: true,
      ),
    );

    expect(find.byKey(fieldOverflowWarningKey), findsOneWidget);
    expect(_enteredText(tester), tooLong);
    expect(find.text(_de.fld001), findsOneWidget);
  });

  testWidgets('saving the committed overflowing draft again commits nothing', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    await _pumpSheet(tester, type: core.FieldType.text, commits: commits);

    await tester.enterText(
      find.byKey(fieldTextControlInputKey),
      'Ein viel zu langer Wert für dieses schmale Feld',
    );
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();
    expect(commits, hasLength(1));

    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();
    expect(
      commits,
      hasLength(1),
      reason: 'no duplicate revision for the same draft',
    );
    expect(find.byKey(fieldOverflowWarningKey), findsOneWidget);
  });

  testWidgets(
    'shortening the overflowing draft clears the warning and closes',
    (tester) async {
      final List<core.FieldValue> commits = <core.FieldValue>[];
      await _pumpSheet(tester, type: core.FieldType.text, commits: commits);

      await tester.enterText(
        find.byKey(fieldTextControlInputKey),
        'Ein viel zu langer Wert für dieses schmale Feld',
      );
      await tester.tap(find.byKey(fieldValueSaveKey));
      await tester.pumpAndSettle();
      expect(find.byKey(fieldOverflowWarningKey), findsOneWidget);

      await tester.enterText(find.byKey(fieldTextControlInputKey), 'Kurz');
      await tester.tap(find.byKey(fieldValueSaveKey));
      await tester.pumpAndSettle();

      expect(commits, hasLength(2));
      expect((commits.last as core.TextValue).overflow, isFalse);
      expect((commits.last as core.TextValue).text, 'Kurz');
      expect(find.byKey(fieldValueSheetKey), findsNothing);
    },
  );

  testWidgets('multiline line counting drives the same flag', (tester) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    await _pumpSheet(tester, type: core.FieldType.multiline, commits: commits);

    // Five explicit lines do not fit a 17 pt high text area (one line).
    await tester.enterText(
      find.byKey(fieldTextControlInputKey),
      'eins\nzwei\ndrei\nvier\nfünf',
    );
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();

    expect(commits, hasLength(1));
    final core.MultilineValue stored = commits.single as core.MultilineValue;
    expect(stored.overflow, isTrue);
    expect(stored.text, 'eins\nzwei\ndrei\nvier\nfünf');
    expect(find.byKey(fieldOverflowWarningKey), findsOneWidget);
  });

  testWidgets('a multiline value that fits keeps the sheet closing path', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    await _pumpSheet(
      tester,
      type: core.FieldType.multiline,
      rect: _wideRect,
      commits: commits,
    );

    await tester.enterText(
      find.byKey(fieldTextControlInputKey),
      'Zeile eins\nZeile zwei',
    );
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();

    expect(commits, hasLength(1));
    expect((commits.single as core.MultilineValue).overflow, isFalse);
    expect(find.byKey(fieldValueSheetKey), findsNothing);
  });

  testWidgets('a long number is flagged against the stored German form', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    await _pumpSheet(tester, type: core.FieldType.number, commits: commits);

    await tester.enterText(
      find.byKey(fieldTextControlInputKey),
      '1234567890123,45',
    );
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();

    expect(commits, hasLength(1));
    final core.NumberValue stored = commits.single as core.NumberValue;
    expect(stored.overflow, isTrue);
    expect(stored.rawGerman, '1234567890123,45');
    expect(stored.canonical, '1234567890123.45');
    expect(find.byKey(fieldOverflowWarningKey), findsOneWidget);
  });

  testWidgets('a long date is flagged and kept verbatim', (tester) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    // A 40 × 20 pt box leaves 37 pt of width; '31.12.2025' needs ~61 pt.
    await _pumpSheet(
      tester,
      type: core.FieldType.date,
      rect: core.Rect.fromLTWH(20, 20, 40, 20),
      commits: commits,
    );
    await tester.enterText(find.byKey(fieldTextControlInputKey), '31.12.2025');
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();

    expect(commits, hasLength(1));
    final core.DateValue stored = commits.single as core.DateValue;
    expect(stored.overflow, isTrue);
    expect(stored.canonical, '2025-12-31');
    expect(find.byKey(fieldOverflowWarningKey), findsOneWidget);
  });

  testWidgets('a checkbox has no clipable text and never warns', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    await _pumpSheet(tester, type: core.FieldType.checkbox, commits: commits);

    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();

    expect(commits, hasLength(1));
    expect(commits.single.overflow, isFalse);
    expect(find.byKey(fieldValueSheetKey), findsNothing);
  });
}
