// T076 type-control contract tests (FR-031/FR-032).
//
// Evidence class: NONE. These are host-VM widget tests around the existing
// `FieldValueSheet` composition and the existing T079/T082 controls. The T083
// signature path is exercised through its T086A wiring: the sheet opens the
// full-screen signature surface instead of the former `NOT_RUN` placeholder and
// reports the captured draft through the caller callback. They open no store,
// PDF, platform channel, emulator, or device and make no Android, IME,
// screen-reader, or visual claim.
//
// Normative sources: `spec.md` FR-031/FR-032 (a selected field is edited with a
// control appropriate to its type), FR-035 (line breaks preserved), FR-038 (no
// silent truncation), FR-042 (checkbox state), FR-036 (a handwritten signature
// belongs only to the current document), and the German catalog
// `contracts/error-catalog.de.md` §6 (`NUM-001`, `DATE-001`, `DATE-002`).
//
// The sheet is not modified here. Every assertion runs against the production
// widget and the shipped German localization:
//   * text accepts German text and preserves it verbatim (no truncation);
//   * multiline preserves newlines and does not truncate;
//   * a valid German number is accepted and stored canonically, invalid input
//     stays in the control and commits nothing;
//   * a valid German date is accepted and stored canonically, invalid dates
//     stay in the control and commit nothing;
//   * the checkbox control toggles the committed value;
//   * signature editing opens the T083 sheet, invents no value on cancel, and
//     reports exactly one captured draft on apply.

@TestOn('vm')
library;

import 'dart:async';

import 'package:feldexa_app/features/editor/field_value_sheet.dart';
import 'package:feldexa_app/features/fill/checkbox_control.dart';
import 'package:feldexa_app/features/fill/signature_sheet.dart';
import 'package:feldexa_app/features/fill/text_control.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _fieldId = '11111111-1111-4111-8111-111111111111';
const ValueKey<String> _openSheetKey = ValueKey<String>('open-value-sheet');
final DateTime _createdAt = DateTime.utc(2026, 11, 20, 8);

/// The shipped German catalog; every user-visible expectation is read here.
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
  List<core.FieldValue>? commits,
  List<SignatureDraft>? signatureDrafts,
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
                          currentValue: null,
                          onCommit: (core.FieldValue value) async {
                            commits?.add(value);
                            return const FieldValueCommitResult.saved();
                          },
                          onSignatureCommit: (SignatureDraft draft) async {
                            signatureDrafts?.add(draft);
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

void main() {
  group('text control', () {
    testWidgets('the selected text field presents the text control', (
      tester,
    ) async {
      await _pumpSheet(tester, type: core.FieldType.text);

      expect(find.byType(FieldTextControl), findsOneWidget);
      expect(find.byType(FieldCheckboxControl), findsNothing);
      expect(find.byKey(fieldTextControlInputKey), findsOneWidget);
      expect(find.text(_de.suggestionTypeText), findsOneWidget);
      expect(find.byKey(fieldValueSignatureActionKey), findsNothing);
    });

    testWidgets('German text is accepted and preserved without truncation', (
      tester,
    ) async {
      final List<core.FieldValue> commits = <core.FieldValue>[];
      await _pumpSheet(tester, type: core.FieldType.text, commits: commits);

      // 251 runes of German text: umlauts, sharp s, and a long sentence.
      const String german =
          'Grüße aus München — Straße, Ärztin, Ölgemälde, Überweisung, '
          'Prüfungsordnung, Fußgängerzone, Größe, Müllabfuhr, Zählerstand, '
          'Kühlschrank, Brötchen, Löwenzahn, Schäfchenwolke, Tagesordnung, '
          'Behördenweg, Güterverkehr, Wörterbuch, Übungssatz, Anhängerzahl';
      await tester.enterText(find.byKey(fieldTextControlInputKey), german);
      await tester.tap(find.byKey(fieldValueSaveKey));
      await tester.pumpAndSettle();

      expect(commits, hasLength(1));
      final core.TextValue saved = commits.single as core.TextValue;
      expect(saved.text, german);
      expect(saved.text.runes.length, german.runes.length);
      expect(saved.text, isNot(endsWith('…')));
      expect(find.byKey(fieldValueSheetKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the entered text is still shown in the control before save', (
      tester,
    ) async {
      await _pumpSheet(tester, type: core.FieldType.text);

      const String german = 'Ärztliche Bescheinigung für Herrn Müller';
      await tester.enterText(find.byKey(fieldTextControlInputKey), german);

      expect(
        tester
            .widget<TextField>(find.byKey(fieldTextControlInputKey))
            .controller
            ?.text,
        german,
      );
      expect(find.byKey(fieldValueErrorKey), findsNothing);
    });
  });

  group('multiline control', () {
    testWidgets('the selected multiline field presents the multiline control', (
      tester,
    ) async {
      await _pumpSheet(tester, type: core.FieldType.multiline);

      expect(find.byType(FieldTextControl), findsOneWidget);
      expect(find.byKey(fieldTextControlDoneKey), findsOneWidget);
      expect(find.text(_de.suggestionTypeMultiline), findsOneWidget);
      final TextField input = tester.widget<TextField>(
        find.byKey(fieldTextControlInputKey),
      );
      expect(input.maxLines, isNull);
      expect(input.keyboardType, TextInputType.multiline);
    });

    testWidgets('line breaks are preserved and the text is not truncated', (
      tester,
    ) async {
      final List<core.FieldValue> commits = <core.FieldValue>[];
      await _pumpSheet(
        tester,
        type: core.FieldType.multiline,
        commits: commits,
      );

      const String multiline =
          'Zeile 1: Grüße\n'
          'Zeile 2: Müller Straße 5\n'
          'Zeile 3: 80331 München\n'
          'Zeile 4: Überweisung\n'
          'Zeile 5: Ende';
      await tester.enterText(find.byKey(fieldTextControlInputKey), multiline);
      await tester.tap(find.byKey(fieldValueSaveKey));
      await tester.pumpAndSettle();

      expect(commits, hasLength(1));
      final core.MultilineValue saved = commits.single as core.MultilineValue;
      expect(saved.text, multiline);
      expect('\n'.allMatches(saved.text), hasLength(4));
      expect(saved.text.runes.length, multiline.runes.length);
      expect(find.byKey(fieldValueSheetKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('number control', () {
    testWidgets('the selected number field presents the number control', (
      tester,
    ) async {
      await _pumpSheet(tester, type: core.FieldType.number);

      expect(find.byType(FieldTextControl), findsOneWidget);
      expect(find.byType(FieldCheckboxControl), findsNothing);
      expect(find.text(_de.suggestionTypeNumber), findsOneWidget);
      final TextField input = tester.widget<TextField>(
        find.byKey(fieldTextControlInputKey),
      );
      expect(input.maxLines, 1);
    });

    testWidgets('1.234,56 is accepted and stored canonically', (tester) async {
      final List<core.FieldValue> commits = <core.FieldValue>[];
      await _pumpSheet(tester, type: core.FieldType.number, commits: commits);

      await tester.enterText(find.byKey(fieldTextControlInputKey), '1.234,56');
      await tester.tap(find.byKey(fieldValueSaveKey));
      await tester.pumpAndSettle();

      expect(commits, hasLength(1));
      final core.NumberValue saved = commits.single as core.NumberValue;
      expect(saved.canonical, '1234.56');
      expect(saved.rawGerman, '1.234,56');
      expect(saved.type, core.FieldType.number);
      expect(find.byKey(fieldValueSheetKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a German comma decimal is accepted and stored canonically', (
      tester,
    ) async {
      final List<core.FieldValue> commits = <core.FieldValue>[];
      await _pumpSheet(tester, type: core.FieldType.number, commits: commits);

      await tester.enterText(find.byKey(fieldTextControlInputKey), '-12,5');
      await tester.tap(find.byKey(fieldValueSaveKey));
      await tester.pumpAndSettle();

      expect(commits, hasLength(1));
      final core.NumberValue saved = commits.single as core.NumberValue;
      expect(saved.canonical, '-12.5');
      expect(saved.rawGerman, '-12,5');
    });

    testWidgets('invalid number input is not accepted and not stored', (
      tester,
    ) async {
      final List<core.FieldValue> commits = <core.FieldValue>[];
      await _pumpSheet(tester, type: core.FieldType.number, commits: commits);

      await tester.enterText(find.byKey(fieldTextControlInputKey), '12,34,56');
      await tester.tap(find.byKey(fieldValueSaveKey));
      await tester.pumpAndSettle();

      expect(commits, isEmpty);
      expect(find.byKey(fieldValueSheetKey), findsOneWidget);
      expect(find.byKey(fieldValueErrorKey), findsOneWidget);
      expect(find.text(_de.num001), findsOneWidget);
      expect(find.byKey(fieldValueSaveKey), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(fieldTextControlInputKey))
            .controller
            ?.text,
        '12,34,56',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('date control', () {
    testWidgets('the selected date field presents the date control', (
      tester,
    ) async {
      await _pumpSheet(tester, type: core.FieldType.date);

      expect(find.byType(FieldTextControl), findsOneWidget);
      expect(find.byType(FieldCheckboxControl), findsNothing);
      expect(find.text(_de.suggestionTypeDate), findsOneWidget);
      expect(find.byKey(fieldValueSignatureActionKey), findsNothing);
    });

    testWidgets('31.12.2025 is accepted and stored canonically', (
      tester,
    ) async {
      final List<core.FieldValue> commits = <core.FieldValue>[];
      await _pumpSheet(tester, type: core.FieldType.date, commits: commits);

      await tester.enterText(
        find.byKey(fieldTextControlInputKey),
        '31.12.2025',
      );
      await tester.tap(find.byKey(fieldValueSaveKey));
      await tester.pumpAndSettle();

      expect(commits, hasLength(1));
      final core.DateValue saved = commits.single as core.DateValue;
      expect(saved.canonical, '2025-12-31');
      expect(saved.type, core.FieldType.date);
      expect(find.byKey(fieldValueSheetKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an impossible calendar date is not accepted and not stored', (
      tester,
    ) async {
      final List<core.FieldValue> commits = <core.FieldValue>[];
      await _pumpSheet(tester, type: core.FieldType.date, commits: commits);

      await tester.enterText(
        find.byKey(fieldTextControlInputKey),
        '31.02.2025',
      );
      await tester.tap(find.byKey(fieldValueSaveKey));
      await tester.pumpAndSettle();

      expect(commits, isEmpty);
      expect(find.byKey(fieldValueSheetKey), findsOneWidget);
      expect(find.byKey(fieldValueErrorKey), findsOneWidget);
      expect(find.text(_de.date002), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(fieldTextControlInputKey))
            .controller
            ?.text,
        '31.02.2025',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a malformed date is not accepted and not stored', (
      tester,
    ) async {
      final List<core.FieldValue> commits = <core.FieldValue>[];
      await _pumpSheet(tester, type: core.FieldType.date, commits: commits);

      await tester.enterText(
        find.byKey(fieldTextControlInputKey),
        'kein Datum',
      );
      await tester.tap(find.byKey(fieldValueSaveKey));
      await tester.pumpAndSettle();

      expect(commits, isEmpty);
      expect(find.byKey(fieldValueSheetKey), findsOneWidget);
      expect(find.text(_de.date001), findsOneWidget);
      expect(find.byKey(fieldValueSaveKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('checkbox control', () {
    testWidgets('the selected checkbox field presents the checkbox control', (
      tester,
    ) async {
      await _pumpSheet(tester, type: core.FieldType.checkbox);

      expect(find.byType(FieldCheckboxControl), findsOneWidget);
      expect(find.byType(FieldTextControl), findsNothing);
      expect(find.byKey(fieldCheckboxControlKey), findsOneWidget);
      expect(find.text(_de.suggestionTypeCheckbox), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(fieldCheckboxControlKey)),
        matchesSemantics(
          isChecked: false,
          hasCheckedState: true,
          hasEnabledState: true,
          isEnabled: true,
          isReadOnly: false,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('toggling the checkbox updates the committed value', (
      tester,
    ) async {
      final List<core.FieldValue> commits = <core.FieldValue>[];
      await _pumpSheet(tester, type: core.FieldType.checkbox, commits: commits);

      await tester.tap(find.byKey(fieldCheckboxControlKey));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byKey(fieldCheckboxControlKey)),
        matchesSemantics(
          isChecked: true,
          hasCheckedState: true,
          hasEnabledState: true,
          isEnabled: true,
          isReadOnly: false,
          hasTapAction: true,
        ),
      );

      await tester.tap(find.byKey(fieldValueSaveKey));
      await tester.pumpAndSettle();

      expect(commits, hasLength(1));
      final core.CheckboxValue saved = commits.single as core.CheckboxValue;
      expect(saved.checked, isTrue);
      expect(find.byKey(fieldValueSheetKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('toggling the checkbox twice commits the unchecked state', (
      tester,
    ) async {
      final List<core.FieldValue> commits = <core.FieldValue>[];
      await _pumpSheet(tester, type: core.FieldType.checkbox, commits: commits);

      await tester.tap(find.byKey(fieldCheckboxControlKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(fieldCheckboxControlKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(fieldValueSaveKey));
      await tester.pumpAndSettle();

      expect(commits, hasLength(1));
      expect((commits.single as core.CheckboxValue).checked, isFalse);
    });
  });

  group('signature control', () {
    testWidgets('signature editing opens the sheet and invents no value', (
      tester,
    ) async {
      final List<core.FieldValue> commits = <core.FieldValue>[];
      final List<SignatureDraft> drafts = <SignatureDraft>[];
      await _pumpSheet(
        tester,
        type: core.FieldType.signature,
        commits: commits,
        signatureDrafts: drafts,
      );

      // The type-appropriate signature surface is the capture action plus the
      // signed/unsigned state, not a `NOT_RUN` placeholder.
      expect(find.byKey(fieldValueSignatureActionKey), findsOneWidget);
      expect(find.byKey(fieldValueSignatureStateKey), findsOneWidget);
      expect(find.text(_de.a11ySignatureUnsigned), findsOneWidget);
      expect(find.text(_de.suggestionTypeSignature), findsOneWidget);
      expect(find.text('NOT_RUN'), findsNothing);

      // No inline value control and no inline save action exist: the asset and
      // the revision are written together by the caller, never one without the
      // other.
      expect(find.byType(FieldTextControl), findsNothing);
      expect(find.byType(FieldCheckboxControl), findsNothing);
      expect(find.byKey(fieldValueSaveKey), findsNothing);
      expect(find.byKey(fieldTextControlInputKey), findsNothing);
      expect(commits, isEmpty);
      expect(tester.takeException(), isNull);

      // Opening the capture surface shows the real T083 sheet, and cancelling
      // it returns to the value sheet without a draft or a value.
      await tester.tap(find.byKey(fieldValueSignatureActionKey));
      await tester.pumpAndSettle();
      expect(find.byType(SignatureSheet), findsOneWidget);
      expect(drafts, isEmpty);
      await tester.tap(find.byKey(signatureSheetCancelKey));
      await tester.pumpAndSettle();
      expect(find.byType(SignatureSheet), findsNothing);
      expect(find.byKey(fieldValueSheetKey), findsOneWidget);
      expect(drafts, isEmpty);
      expect(commits, isEmpty);

      // Closing the signature surface reports no signature value either.
      await tester.tap(find.byKey(fieldValueCloseKey));
      await tester.pumpAndSettle();
      expect(find.byKey(fieldValueSheetKey), findsNothing);
      expect(commits, isEmpty);
      expect(drafts, isEmpty);
    });

    testWidgets('applying ink reports exactly one hint-bearing draft', (
      tester,
    ) async {
      final List<core.FieldValue> commits = <core.FieldValue>[];
      final List<SignatureDraft> drafts = <SignatureDraft>[];
      await _pumpSheet(
        tester,
        type: core.FieldType.signature,
        commits: commits,
        signatureDrafts: drafts,
      );

      await tester.tap(find.byKey(fieldValueSignatureActionKey));
      await tester.pumpAndSettle();
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byKey(signatureSheetCanvasKey)),
      );
      await gesture.moveBy(const Offset(40, 12));
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(signatureSheetApplyKey));
      await tester.pumpAndSettle();

      expect(drafts, hasLength(1));
      expect(drafts.single.isEmpty, isFalse);
      expect(drafts.single.strokes.single.points, hasLength(2));
      expect(commits, isEmpty, reason: 'no inline value is invented');
      expect(find.byKey(fieldValueSheetKey), findsNothing);
    });

    testWidgets('an empty apply stores nothing and keeps the sheet open', (
      tester,
    ) async {
      final List<SignatureDraft> drafts = <SignatureDraft>[];
      await _pumpSheet(
        tester,
        type: core.FieldType.signature,
        signatureDrafts: drafts,
      );

      await tester.tap(find.byKey(fieldValueSignatureActionKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(signatureSheetApplyKey));
      await tester.pumpAndSettle();

      expect(drafts, isEmpty, reason: 'empty ink is never stored');
      expect(find.byType(SignatureSheet), findsNothing);
      expect(find.byKey(fieldValueSheetKey), findsOneWidget);
      expect(find.byKey(fieldValueErrorKey), findsNothing);
    });
  });
}
