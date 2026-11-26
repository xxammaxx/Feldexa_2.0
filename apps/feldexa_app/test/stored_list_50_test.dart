// T097 (FR-100, OD-4): the 50-entry stored list opens within the ratified
// budget and every entry stays reachable without pagination.
//
// Owner Decision Q10=A (2026-11-26) fixed the bound: 50 stored items, initial
// open-to-first-frame latency <= 500 ms, lazy viewport rendering, all 50
// entries scrollable/reachable without pagination.
//
// Evidence class: NONE (host widget test). It makes no Android, device, or
// performance claim about a real device; SC-004 remains a DEVICE measurement.
// The 500 ms measurement is a host build/layout smoke bound (it warms the
// harness first); the discriminating assertion for the lazy rendering is the
// second case, which requires fewer than 50 entry widgets and an unbuilt
// oldest entry.

import 'package:feldexa_app/features/start/stored_items.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const int _itemCount = 50;
const int _openBudgetMs = 500;

DocumentSummary _summary(int index) {
  return DocumentSummary(
    id: '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
    title: 'Gespeichertes Dokument ${index + 1}',
    updatedAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: index)),
    status: StoredItemStatus.saved,
  );
}

ValueKey<String> _entryKey(int index) {
  return ValueKey<String>(
    'stored-item-00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
  );
}

Widget _host(Widget child) {
  return MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 400, height: 700, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('50 stored items open within the ratified 500 ms budget', (
    WidgetTester tester,
  ) async {
    final List<DocumentSummary> documents = <DocumentSummary>[
      for (int index = 0; index < _itemCount; index++) _summary(index),
    ];

    // Warm the harness (localizations, theme, bindings) with the empty list,
    // then measure the transition to 50 entries. Measuring the very first
    // pumpWidget would include one-time test bootstrap, not the list open.
    await tester.pumpWidget(
      _host(
        StoredItemsView(
          documents: const <DocumentSummary>[],
          templates: const <DocumentSummary>[],
          onOpenDocument: (String _) {},
          onOpenTemplate: (String _) {},
        ),
      ),
    );
    await tester.pump();

    final Stopwatch stopwatch = Stopwatch()..start();
    await tester.pumpWidget(
      _host(
        StoredItemsView(
          documents: documents,
          templates: const <DocumentSummary>[],
          onOpenDocument: (String _) {},
          onOpenTemplate: (String _) {},
        ),
      ),
    );
    await tester.pump();
    stopwatch.stop();

    expect(tester.takeException(), isNull);
    expect(
      stopwatch.elapsedMilliseconds,
      lessThanOrEqualTo(_openBudgetMs),
      reason:
          'open-to-first-frame took ${stopwatch.elapsedMilliseconds} ms; '
          'the Q10=A budget is $_openBudgetMs ms',
    );
  });

  testWidgets('50 stored items render lazily and the last stays reachable', (
    WidgetTester tester,
  ) async {
    final List<DocumentSummary> documents = <DocumentSummary>[
      for (int index = 0; index < _itemCount; index++) _summary(index),
    ];

    await tester.pumpWidget(
      _host(
        StoredItemsView(
          documents: documents,
          templates: const <DocumentSummary>[],
          onOpenDocument: (String _) {},
          onOpenTemplate: (String _) {},
        ),
      ),
    );

    // Lazy viewport rendering: the newest entry is visible, the oldest is not
    // built, and fewer than 50 entries exist in the element tree.
    expect(find.byKey(_entryKey(_itemCount - 1)), findsOneWidget);
    expect(find.byKey(_entryKey(0)), findsNothing);
    expect(
      tester.widgetList(find.byType(InkWell)).length,
      lessThan(_itemCount),
    );

    await tester.scrollUntilVisible(
      find.byKey(_entryKey(0)),
      400,
      scrollable: find.byType(Scrollable),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(_entryKey(0)), findsOneWidget);
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      greaterThan(0),
    );
  });
}
