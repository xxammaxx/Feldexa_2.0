// T086D document overview host tests.
//
// Evidence class: NONE. These are host-VM unit and widget tests over synthetic
// read models. They create no document, open no editor, call no store or
// network, and make no Android, device, screen-reader, or visual claim.
//
// They prove the T086D overview contract:
//   * the completion counts use exactly the T085 semantics (optional-empty and
//     warning count as complete; blocking-error and incompatible do not);
//   * every T085 state has one visible German label, so per-field completion is
//     visible and never colour-only;
//   * the same durability status surface as the editor is rendered and unsaved
//     work is never shown with a check;
//   * „Weiter ausfüllen“ returns to the editor without a field, and a field row
//     returns the selected field id so filling can continue;
//   * the overview composes at 200 % text scale without a RenderFlex overflow.

@TestOn('vm')
library;

import 'package:feldexa_app/features/editor/document_overview.dart';
import 'package:feldexa_app/features/editor/durability_status.dart';
import 'package:feldexa_app/features/editor/field_completion.dart';
import 'package:feldexa_app/features/editor/field_order.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _editedAt = DateTime.utc(2026, 11, 22, 9, 30);
final AppLocalizations _de = lookupAppLocalizations(const Locale('de'));

const String _fieldOneId = '11111111-1111-4111-8111-111111111111';
const String _fieldTwoId = '22222222-2222-4222-8222-222222222222';
const String _fieldThreeId = '33333333-3333-4333-8333-333333333333';
const String _fieldFourId = '44444444-4444-4444-8444-444444444444';
const String _fieldFiveId = '55555555-5555-4555-8555-555555555555';

FieldOrderEntry _entry({
  required String id,
  required int position,
  required FieldCompletionState completion,
  int pageIndex = 0,
  core.FieldType type = core.FieldType.text,
}) {
  return FieldOrderEntry(
    fieldId: id,
    position: position,
    pageIndex: pageIndex,
    label: 'Feld $position',
    type: type,
    provenance: core.Provenance.user,
    confidence: null,
    conflicting: false,
    completion: completion,
  );
}

/// One entry per T085 state: complete, optionalEmpty, blockingError, warning,
/// incompatible. Optional-empty and warning count as filled (T085), so three
/// of the five fields are complete and two are blocking.
List<FieldOrderEntry> _allStates() {
  return <FieldOrderEntry>[
    _entry(
      id: _fieldOneId,
      position: 0,
      completion: FieldCompletionState.complete,
    ),
    _entry(
      id: _fieldTwoId,
      position: 1,
      completion: FieldCompletionState.optionalEmpty,
      pageIndex: 1,
    ),
    _entry(
      id: _fieldThreeId,
      position: 2,
      completion: FieldCompletionState.blockingError,
    ),
    _entry(
      id: _fieldFourId,
      position: 3,
      completion: FieldCompletionState.warning,
    ),
    _entry(
      id: _fieldFiveId,
      position: 4,
      completion: FieldCompletionState.incompatible,
      pageIndex: 1,
      type: core.FieldType.number,
    ),
  ];
}

/// A host that pushes the overview route and records its popped outcome.
class _OverviewLauncher extends StatelessWidget {
  const _OverviewLauncher({
    required this.entries,
    required this.status,
    required this.onOutcome,
    this.lastDurableAt,
  });

  final List<FieldOrderEntry> entries;
  final core.DurabilityStatus status;
  final DateTime? lastDurableAt;
  final ValueChanged<DocumentOverviewOutcome?> onOutcome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Builder(
        builder: (BuildContext inner) {
          return Center(
            child: ElevatedButton(
              key: const ValueKey<String>('open-overview'),
              onPressed: () async {
                final DocumentOverviewOutcome? outcome =
                    await Navigator.of(inner).push<DocumentOverviewOutcome>(
                      MaterialPageRoute<DocumentOverviewOutcome>(
                        builder: (BuildContext context) =>
                            DocumentOverviewScreen(
                              entries: entries,
                              durabilityStatus: status,
                              lastDurableAt: lastDurableAt,
                            ),
                      ),
                    );
                onOutcome(outcome);
              },
              child: const Text('open'),
            ),
          );
        },
      ),
    );
  }
}

Future<void> _pumpOverview(
  WidgetTester tester, {
  required List<FieldOrderEntry> entries,
  required core.DurabilityStatus status,
  required ValueChanged<DocumentOverviewOutcome?> onOutcome,
  DateTime? lastDurableAt,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const <Locale>[Locale('de')],
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        );
      },
      home: _OverviewLauncher(
        entries: entries,
        status: status,
        lastDurableAt: lastDurableAt,
        onOutcome: onOutcome,
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey<String>('open-overview')));
  await tester.pumpAndSettle();
}

void main() {
  group('DocumentOverviewCounts', () {
    test('counts total, filled, and blocking with T085 semantics', () {
      final DocumentOverviewCounts counts = DocumentOverviewCounts.fromEntries(
        _allStates(),
      );

      expect(counts.total, 5);
      // complete + optionalEmpty + warning count as complete.
      expect(counts.filled, 3);
      // blockingError + incompatible do not.
      expect(counts.blocking, 2);
    });

    test('an empty overview is empty and has zero counts', () {
      final DocumentOverviewCounts counts = DocumentOverviewCounts.fromEntries(
        const <FieldOrderEntry>[],
      );

      expect(counts.isEmpty, isTrue);
      expect(counts.total, 0);
      expect(counts.filled, 0);
      expect(counts.blocking, 0);
    });
  });

  testWidgets('shows every T085 completion state and the count summary', (
    tester,
  ) async {
    await _pumpOverview(
      tester,
      entries: _allStates(),
      status: core.DurabilityStatus.unsaved,
      onOutcome: (_) {},
    );

    expect(find.byKey(documentOverviewScreenKey), findsOneWidget);
    expect(find.text(_de.fieldCount(5, 3)), findsOneWidget);
    expect(find.text(_de.fieldCompletionComplete), findsNWidgets(1));
    expect(find.text(_de.fieldCompletionOptionalEmpty), findsNWidgets(1));
    expect(find.text(_de.fieldCompletionBlockingError), findsNWidgets(1));
    expect(find.text(_de.fieldCompletionWarning), findsNWidgets(1));
    expect(find.text(_de.fieldCompletionIncompatible), findsNWidgets(1));
    // Page grouping keeps the two-page document readable.
    expect(find.text(_de.suggestionPage(1)), findsWidgets);
    expect(find.text(_de.suggestionPage(2)), findsWidgets);
    // One visible completion label node per field, keyed for the screen.
    expect(
      find.byKey(
        const ValueKey<String>(
          '$documentOverviewCompletionKeyPrefix$_fieldOneId',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'shows the same durability status and never checks unsaved work',
    (tester) async {
      await _pumpOverview(
        tester,
        entries: _allStates(),
        status: core.DurabilityStatus.unsaved,
        onOutcome: (_) {},
      );

      expect(find.byKey(durabilityStatusLabelKey), findsOneWidget);
      expect(find.text(_de.durabilityUnsaved), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    },
  );

  testWidgets('continue returns to the editor without a field', (tester) async {
    DocumentOverviewOutcome? outcome;
    await _pumpOverview(
      tester,
      entries: _allStates(),
      status: core.DurabilityStatus.unsaved,
      onOutcome: (DocumentOverviewOutcome? value) => outcome = value,
    );

    await tester.tap(find.byKey(documentOverviewContinueKey));
    await tester.pumpAndSettle();

    expect(outcome, isNotNull);
    expect(outcome!.fieldId, isNull);
    expect(find.byKey(documentOverviewScreenKey), findsNothing);
  });

  testWidgets('a field row returns the selected field id to continue filling', (
    tester,
  ) async {
    DocumentOverviewOutcome? outcome;
    await _pumpOverview(
      tester,
      entries: _allStates(),
      status: core.DurabilityStatus.unsaved,
      onOutcome: (DocumentOverviewOutcome? value) => outcome = value,
    );

    final Finder row = find.byKey(
      const ValueKey<String>('$documentOverviewRowKeyPrefix$_fieldFourId'),
    );
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(outcome, isNotNull);
    expect(outcome!.fieldId, _fieldFourId);
  });

  testWidgets('lays out at 200 percent text scale without overflow', (
    tester,
  ) async {
    await _pumpOverview(
      tester,
      entries: _allStates(),
      status: core.DurabilityStatus.saved(lastDurableAt: _editedAt),
      lastDurableAt: _editedAt,
      textScale: 2,
      onOutcome: (_) {},
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(documentOverviewScreenKey), findsOneWidget);
  });
}
