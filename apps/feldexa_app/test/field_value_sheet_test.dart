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
  List<FieldValueSheetOutcome?>? outcomes,
  bool Function(FieldValueNavigation)? onNavigate,
  bool canGoPrevious = false,
  bool canGoNext = false,
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
                          field: _field(type),
                          currentValue: currentValue,
                          onNavigate: onNavigate,
                          canGoPrevious: canGoPrevious,
                          canGoNext: canGoNext,
                          onCommit: (core.FieldValue value) async {
                            commits?.add(value);
                            return result?.call(value) ??
                                const FieldValueCommitResult.saved();
                          },
                        );
                      },
                    ).then((FieldValueSheetOutcome? value) {
                      outcomes?.add(value);
                    }),
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

  testWidgets('the per-field reorder action commits and hands off', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    final List<FieldValueSheetOutcome?> outcomes = <FieldValueSheetOutcome?>[];
    await _pumpSheet(
      tester,
      type: core.FieldType.text,
      commits: commits,
      outcomes: outcomes,
    );

    await tester.enterText(find.byKey(fieldTextControlInputKey), 'Neu');
    await tester.tap(find.byKey(fieldValueReorderKey));
    await tester.pumpAndSettle();

    expect(commits, hasLength(1));
    expect(outcomes, <FieldValueSheetOutcome?>[FieldValueSheetOutcome.reorder]);
    expect(find.byKey(fieldValueSheetKey), findsNothing);
  });

  testWidgets('the reorder action keeps the sheet open on a failed commit', (
    tester,
  ) async {
    final List<FieldValueSheetOutcome?> outcomes = <FieldValueSheetOutcome?>[];
    await _pumpSheet(
      tester,
      type: core.FieldType.text,
      outcomes: outcomes,
      result: (core.FieldValue value) =>
          FieldValueCommitResult.failed(_de.save003),
    );

    await tester.enterText(find.byKey(fieldTextControlInputKey), 'Neu');
    await tester.tap(find.byKey(fieldValueReorderKey));
    await tester.pumpAndSettle();

    expect(outcomes, isEmpty);
    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    expect(find.text(_de.save003), findsOneWidget);
  });

  testWidgets('previous/next are disabled at the order boundaries', (
    tester,
  ) async {
    final List<FieldValueNavigation> navigations = <FieldValueNavigation>[];
    await _pumpSheet(
      tester,
      type: core.FieldType.text,
      onNavigate: (FieldValueNavigation direction) {
        navigations.add(direction);
        return true;
      },
    );

    final TextButton previous = tester.widget<TextButton>(
      find.byKey(fieldValuePreviousKey),
    );
    final TextButton next = tester.widget<TextButton>(
      find.byKey(fieldValueNextKey),
    );
    expect(previous.onPressed, isNull);
    expect(next.onPressed, isNull);
    expect(navigations, isEmpty);
  });

  testWidgets('next commits once, moves focus, and keeps the sheet open', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    final List<FieldValueNavigation> navigations = <FieldValueNavigation>[];
    await _pumpSheet(
      tester,
      type: core.FieldType.text,
      commits: commits,
      onNavigate: (FieldValueNavigation direction) {
        navigations.add(direction);
        return true;
      },
      canGoNext: true,
    );

    await tester.enterText(find.byKey(fieldTextControlInputKey), 'Erika');
    await tester.tap(find.byKey(fieldValueNextKey));
    // The host callback keeps this sheet open and busy (the real editor swaps
    // the field), so settle the commit without waiting for the spinner.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(commits, hasLength(1));
    expect(navigations, <FieldValueNavigation>[FieldValueNavigation.next]);
    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
  });

  testWidgets('a failed next commit does not move to the next field', (
    tester,
  ) async {
    final List<FieldValueNavigation> navigations = <FieldValueNavigation>[];
    await _pumpSheet(
      tester,
      type: core.FieldType.text,
      onNavigate: (FieldValueNavigation direction) {
        navigations.add(direction);
        return true;
      },
      canGoNext: true,
      result: (core.FieldValue value) =>
          FieldValueCommitResult.failed(_de.save003),
    );

    await tester.enterText(find.byKey(fieldTextControlInputKey), 'Erika');
    await tester.tap(find.byKey(fieldValueNextKey));
    await tester.pumpAndSettle();

    expect(navigations, isEmpty);
    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    expect(find.text(_de.save003), findsOneWidget);
  });

  testWidgets('untouched empty number navigates without NUM-001 or a commit', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    final List<FieldValueNavigation> navigations = <FieldValueNavigation>[];
    await _pumpSheet(
      tester,
      type: core.FieldType.number,
      commits: commits,
      onNavigate: (FieldValueNavigation direction) {
        navigations.add(direction);
        return true;
      },
      canGoNext: true,
    );

    await tester.tap(find.byKey(fieldValueNextKey));
    await tester.pumpAndSettle();

    expect(commits, isEmpty);
    expect(navigations, <FieldValueNavigation>[FieldValueNavigation.next]);
    expect(find.byKey(fieldValueErrorKey), findsNothing);
  });

  testWidgets('untouched empty date navigates without DATE-001 or a commit', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    final List<FieldValueNavigation> navigations = <FieldValueNavigation>[];
    await _pumpSheet(
      tester,
      type: core.FieldType.date,
      commits: commits,
      onNavigate: (FieldValueNavigation direction) {
        navigations.add(direction);
        return true;
      },
      canGoNext: true,
    );

    await tester.tap(find.byKey(fieldValueNextKey));
    await tester.pumpAndSettle();

    expect(commits, isEmpty);
    expect(navigations, <FieldValueNavigation>[FieldValueNavigation.next]);
    expect(find.byKey(fieldValueErrorKey), findsNothing);
  });

  testWidgets('untouched checkbox navigates without a commit', (tester) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    final List<FieldValueNavigation> navigations = <FieldValueNavigation>[];
    await _pumpSheet(
      tester,
      type: core.FieldType.checkbox,
      commits: commits,
      onNavigate: (FieldValueNavigation direction) {
        navigations.add(direction);
        return true;
      },
      canGoNext: true,
    );

    await tester.tap(find.byKey(fieldValueNextKey));
    await tester.pumpAndSettle();

    expect(commits, isEmpty);
    expect(navigations, <FieldValueNavigation>[FieldValueNavigation.next]);
    expect(find.byKey(fieldValueErrorKey), findsNothing);
  });

  testWidgets('untouched signature navigates without a commit', (tester) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    final List<FieldValueNavigation> navigations = <FieldValueNavigation>[];
    await _pumpSheet(
      tester,
      type: core.FieldType.signature,
      commits: commits,
      onNavigate: (FieldValueNavigation direction) {
        navigations.add(direction);
        return true;
      },
      canGoNext: true,
    );

    await tester.tap(find.byKey(fieldValueNextKey));
    await tester.pumpAndSettle();

    expect(commits, isEmpty);
    expect(navigations, <FieldValueNavigation>[FieldValueNavigation.next]);
  });

  testWidgets('untouched text with an existing value adds no setValue', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    final List<FieldValueNavigation> navigations = <FieldValueNavigation>[];
    await _pumpSheet(
      tester,
      type: core.FieldType.text,
      currentValue: core.TextValue(text: 'Ada', lastEditedAt: _createdAt),
      commits: commits,
      onNavigate: (FieldValueNavigation direction) {
        navigations.add(direction);
        return true;
      },
      canGoNext: true,
    );

    await tester.tap(find.byKey(fieldValueNextKey));
    await tester.pumpAndSettle();

    expect(commits, isEmpty);
    expect(navigations, <FieldValueNavigation>[FieldValueNavigation.next]);
  });

  testWidgets('untouched incompatible text is not converted by navigation', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    final List<FieldValueNavigation> navigations = <FieldValueNavigation>[];
    await _pumpSheet(
      tester,
      type: core.FieldType.text,
      currentValue: core.IncompatibleValue(
        preservedText: '31.02.2025',
        reasonCode: 'reclassified_to_text',
        lastEditedAt: _createdAt,
      ),
      commits: commits,
      onNavigate: (FieldValueNavigation direction) {
        navigations.add(direction);
        return true;
      },
      canGoNext: true,
    );

    await tester.tap(find.byKey(fieldValueNextKey));
    await tester.pumpAndSettle();

    expect(commits, isEmpty);
    expect(navigations, <FieldValueNavigation>[FieldValueNavigation.next]);
    expect(find.text('31.02.2025'), findsWidgets);
  });

  testWidgets('unchanged text reorder opens the review without a commit', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    final List<FieldValueSheetOutcome?> outcomes = <FieldValueSheetOutcome?>[];
    await _pumpSheet(
      tester,
      type: core.FieldType.text,
      currentValue: core.TextValue(text: 'Ada', lastEditedAt: _createdAt),
      commits: commits,
      outcomes: outcomes,
    );

    await tester.tap(find.byKey(fieldValueReorderKey));
    await tester.pumpAndSettle();

    expect(commits, isEmpty);
    expect(outcomes, <FieldValueSheetOutcome?>[FieldValueSheetOutcome.reorder]);
  });

  for (final core.FieldType type in <core.FieldType>[
    core.FieldType.number,
    core.FieldType.date,
    core.FieldType.checkbox,
    core.FieldType.signature,
  ]) {
    testWidgets('untouched ${type.name} reorder opens the review, no commit', (
      tester,
    ) async {
      final List<core.FieldValue> commits = <core.FieldValue>[];
      final List<FieldValueSheetOutcome?> outcomes =
          <FieldValueSheetOutcome?>[];
      await _pumpSheet(
        tester,
        type: type,
        commits: commits,
        outcomes: outcomes,
      );

      await tester.tap(find.byKey(fieldValueReorderKey));
      await tester.pumpAndSettle();

      expect(commits, isEmpty);
      expect(outcomes, <FieldValueSheetOutcome?>[
        FieldValueSheetOutcome.reorder,
      ]);
      expect(find.byKey(fieldValueErrorKey), findsNothing);
    });
  }

  testWidgets('changed invalid number blocks next with NUM-001', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    final List<FieldValueNavigation> navigations = <FieldValueNavigation>[];
    await _pumpSheet(
      tester,
      type: core.FieldType.number,
      commits: commits,
      onNavigate: (FieldValueNavigation direction) {
        navigations.add(direction);
        return true;
      },
      canGoNext: true,
    );

    await tester.enterText(find.byKey(fieldTextControlInputKey), 'abc');
    await tester.tap(find.byKey(fieldValueNextKey));
    await tester.pumpAndSettle();

    expect(commits, isEmpty);
    expect(navigations, isEmpty);
    expect(find.text(_de.num001), findsOneWidget);
    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
  });

  testWidgets('changed invalid date blocks next with DATE-001', (tester) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    final List<FieldValueNavigation> navigations = <FieldValueNavigation>[];
    await _pumpSheet(
      tester,
      type: core.FieldType.date,
      commits: commits,
      onNavigate: (FieldValueNavigation direction) {
        navigations.add(direction);
        return true;
      },
      canGoNext: true,
    );

    await tester.enterText(find.byKey(fieldTextControlInputKey), 'abc');
    await tester.tap(find.byKey(fieldValueNextKey));
    await tester.pumpAndSettle();

    expect(commits, isEmpty);
    expect(navigations, isEmpty);
    expect(find.text(_de.date001), findsOneWidget);
  });

  testWidgets('changed valid number commits once and then navigates', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    final List<FieldValueNavigation> navigations = <FieldValueNavigation>[];
    await _pumpSheet(
      tester,
      type: core.FieldType.number,
      commits: commits,
      onNavigate: (FieldValueNavigation direction) {
        navigations.add(direction);
        return true;
      },
      canGoNext: true,
    );

    await tester.enterText(find.byKey(fieldTextControlInputKey), '12,5');
    await tester.tap(find.byKey(fieldValueNextKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(commits, hasLength(1));
    expect((commits.single as core.NumberValue).canonical, '12.5');
    expect(navigations, <FieldValueNavigation>[FieldValueNavigation.next]);
  });

  testWidgets('a vanished target re-enables the sheet after the commit', (
    tester,
  ) async {
    final List<core.FieldValue> commits = <core.FieldValue>[];
    await _pumpSheet(
      tester,
      type: core.FieldType.text,
      commits: commits,
      onNavigate: (FieldValueNavigation direction) => false,
      canGoNext: true,
    );

    await tester.enterText(find.byKey(fieldTextControlInputKey), 'Erika');
    await tester.tap(find.byKey(fieldValueNextKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(commits, hasLength(1));
    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.widget<TextButton>(find.byKey(fieldValueNextKey)).onPressed,
      isNotNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.byKey(fieldValueReorderKey)).onPressed,
      isNotNull,
    );
  });

  testWidgets('a checkbox control receives focus when the sheet opens', (
    tester,
  ) async {
    await _pumpSheet(tester, type: core.FieldType.checkbox);

    final Focus focus = tester.widget<Focus>(
      find.byKey(fieldValueNonTextFocusKey),
    );
    expect(focus.focusNode!.hasFocus, isTrue);
  });

  testWidgets('a signature control receives focus when the sheet opens', (
    tester,
  ) async {
    await _pumpSheet(tester, type: core.FieldType.signature);

    final Focus focus = tester.widget<Focus>(
      find.byKey(fieldValueNonTextFocusKey),
    );
    expect(focus.focusNode!.hasFocus, isTrue);
  });
}
