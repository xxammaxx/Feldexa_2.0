// T071A `FieldValueSheet` host tests (correction 4).
//
// Evidence class: NONE. These are host-VM widget tests with a caller-owned
// fake commit callback. They open no store, PDF, platform channel, emulator, or
// device and make no Android, IME, screen-reader, or visual claim.
//
// They prove the sheet's correction-4 behavior:
//   * text and multiline input beyond 10,000 runes or containing control
//     characters is refused with the catalog `SAVE-007` sentence, keeps the
//     sheet open, and commits nothing;
//   * single-line Enter, focus loss, the multiline done action, and the
//     explicit save each run the validated commit path exactly once;
//   * a failed commit keeps the sheet open with the returned message;
//   * the explicit close button cancels without a focus-loss save.

@TestOn('vm')
library;

import 'dart:async';

import 'package:feldexa_app/features/editor/field_value_sheet.dart';
import 'package:feldexa_app/features/fill/text_control.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _fieldId = '11111111-1111-4111-8111-111111111111';
const ValueKey<String> _openSheetKey = ValueKey<String>('open-value-sheet');
final DateTime _createdAt = DateTime.utc(2026, 11, 20, 8);
final AppLocalizations _de = lookupAppLocalizations(const Locale('de'));

core.ConfirmedField _field(core.FieldType type) {
  return core.ConfirmedField(
    id: _fieldId,
    pageIndex: 0,
    rect: core.Rect.fromLTWH(20, 20, 100, 20),
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
  core.FieldValue? currentValue,
  List<core.FieldValue>? commits,
  FieldValueCommitResult Function(core.FieldValue value)? result,
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
                    showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (BuildContext context) {
                        return FieldValueSheet(
                          field: _field(type),
                          currentValue: currentValue,
                          onCommit: (core.FieldValue value) async {
                            commits?.add(value);
                            return result?.call(value) ??
                                const FieldValueCommitResult.saved();
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

void main() {
  testWidgets('text over 10,000 runes is refused in the open sheet', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    await _pumpSheet(tester, type: core.FieldType.text, commits: commits);

    await tester.enterText(find.byKey(fieldTextControlInputKey), 'ä' * 10001);
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();

    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    expect(find.text(_de.save007), findsOneWidget);
    expect(commits, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a text control character is refused in the open sheet', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    await _pumpSheet(tester, type: core.FieldType.text, commits: commits);

    await tester.enterText(find.byKey(fieldTextControlInputKey), 'a\u0001b');
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();

    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    expect(find.text(_de.save007), findsOneWidget);
    expect(commits, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiline over 10,000 runes is refused in the open sheet', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    await _pumpSheet(tester, type: core.FieldType.multiline, commits: commits);

    await tester.enterText(find.byKey(fieldTextControlInputKey), 'ä' * 10001);
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();

    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    expect(find.text(_de.save007), findsOneWidget);
    expect(commits, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single-line done commits once and closes the sheet', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    await _pumpSheet(tester, type: core.FieldType.text, commits: commits);

    await tester.enterText(find.byKey(fieldTextControlInputKey), 'Neu');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(commits, hasLength(1));
    expect((commits.single as core.TextValue).text, 'Neu');
    expect(find.byKey(fieldValueSheetKey), findsNothing);
  });

  testWidgets('focus loss commits once and closes the sheet', (tester) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    await _pumpSheet(tester, type: core.FieldType.text, commits: commits);

    await tester.enterText(find.byKey(fieldTextControlInputKey), 'Neu');
    FocusScope.of(tester.element(find.byKey(fieldTextControlInputKey)))
        .unfocus();
    await tester.pumpAndSettle();

    expect(commits, hasLength(1));
    expect((commits.single as core.TextValue).text, 'Neu');
    expect(find.byKey(fieldValueSheetKey), findsNothing);
  });

  testWidgets('the multiline done action commits once and closes', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    await _pumpSheet(tester, type: core.FieldType.multiline, commits: commits);

    expect(find.byKey(fieldTextControlDoneKey), findsOneWidget);
    await tester.enterText(
      find.byKey(fieldTextControlInputKey),
      'Zeile 1\nZeile 2',
    );
    await tester.tap(find.byKey(fieldTextControlDoneKey));
    await tester.pumpAndSettle();

    expect(commits, hasLength(1));
    expect((commits.single as core.MultilineValue).text, 'Zeile 1\nZeile 2');
    expect(find.byKey(fieldValueSheetKey), findsNothing);
  });

  testWidgets('the explicit save commits once and closes the sheet', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    await _pumpSheet(tester, type: core.FieldType.text, commits: commits);

    await tester.enterText(find.byKey(fieldTextControlInputKey), 'Neu');
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();

    expect(commits, hasLength(1));
    expect(find.byKey(fieldValueSheetKey), findsNothing);
  });

  testWidgets('a failed save keeps the sheet open and editable', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    await _pumpSheet(
      tester,
      type: core.FieldType.text,
      commits: commits,
      result: (core.FieldValue value) =>
          FieldValueCommitResult.failed(_de.save003),
    );

    await tester.enterText(find.byKey(fieldTextControlInputKey), 'Neu');
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();

    expect(commits, hasLength(1));
    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    expect(find.byKey(fieldValueErrorKey), findsOneWidget);
    expect(find.text(_de.save003), findsOneWidget);
  });

  testWidgets('explicit close cancels without a focus-loss save', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    await _pumpSheet(tester, type: core.FieldType.text, commits: commits);

    await tester.enterText(find.byKey(fieldTextControlInputKey), 'Neu');
    await tester.tap(find.byKey(fieldValueCloseKey));
    await tester.pumpAndSettle();

    expect(commits, isEmpty);
    expect(find.byKey(fieldValueSheetKey), findsNothing);
  });
}
