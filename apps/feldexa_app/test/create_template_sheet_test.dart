// T115 "Als Vorlage speichern" sheet host-VM widget tests (FR-054–FR-057,
// FR-061). Evidence class NONE.
//
// Pins: the German sheet surfaces and exclusion notice from the ARB, the
// FR-055 disabled confirm while the structure is unreviewed, one explicit
// create call with the trimmed title on confirm, and the content-free success
// path (the sheet closes only after the verified success).

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_adapters_simulated/feldexa_adapters_simulated.dart';
import 'package:feldexa_app/features/templates/create_template.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_application/src/templates/create_template_from_document.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required bool reviewed,
  required void Function(String title) onCreated,
}) async {
  await tester.pumpWidget(
    _host(
      Builder(
        builder: (BuildContext context) => Center(
          child: TextButton(
            onPressed: () {
              showCreateTemplateSheet(
                context,
                reviewed: reviewed,
                initialTitle: 'Antrag',
                onCreate: (String title) async {
                  onCreated(title);
                  return createTemplateFromDocument(
                    store: _store(),
                    title: title,
                    source: _source(),
                    content: _content(),
                  );
                },
              );
            },
            child: const Text('oeffnen'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('oeffnen'));
  await tester.pumpAndSettle();
}

core.SourceFileRef _source() => core.SourceFileRef(
  id: '00000000-0000-4000-8000-000000000001',
  sha256: crypto.sha256
      .convert(Uint8List.fromList(List<int>.filled(64, 37)))
      .toString(),
  sizeBytes: 64,
  pageCount: 1,
  importedAt: DateTime.utc(2026, 11, 27, 9),
);

core.RevisionContent _content() => core.RevisionContent(
  pages: <core.Page>[
    core.Page(
      index: 0,
      geometry: core.PageGeometry(mediaBox: core.Rect.fromLTWH(0, 0, 595, 842)),
    ),
  ],
  fieldOrder: const <String>[],
);

// The sheet test only needs a store that verifies the returned metadata, so
// the simulated store backs the callback on the deterministic lane.
SimulatedSecureStoreAdapter? _cachedStore;
SimulatedSecureStoreAdapter _store() {
  final Uint8List bytes = Uint8List.fromList(List<int>.filled(64, 37));
  final SimulatedBackend backend = SimulatedBackend(
    context: SimulatedAdapterContext(),
  );
  backend.stageSource(
    sourceId: _source().id,
    fixture: SimulatedFixture(
      id: 'sf-sheet',
      role: SimulatedFixtureRole.editor,
      status: SimulatedFixtureStatus.valid,
      title: 'sf-sheet',
      displayName: 'sheet.pdf',
      bytes: bytes,
      sha256: crypto.sha256.convert(bytes).toString(),
      sizeBytes: bytes.length,
      pages: <SimulatedFixturePage>[
        SimulatedFixturePage(
          index: 0,
          widthPt: 595,
          heightPt: 842,
          rotation: 0,
        ),
      ],
      expectedOcr: const <SimulatedOcrPage>[],
      expectedErrorCode: null,
    ),
  );
  _cachedStore = SimulatedSecureStoreAdapter(backend: backend);
  return _cachedStore!;
}

void main() {
  testWidgets('shows the German exclusion notice and title input', (
    WidgetTester tester,
  ) async {
    await _pumpSheet(tester, reviewed: true, onCreated: (_) {});
    expect(
      find.byKey(const ValueKey<String>(createTemplateSheetKey)),
      findsOneWidget,
    );
    expect(find.text('Vorlage erstellen'), findsOneWidget);
    expect(
      find.text(
        'Werte und Unterschriften werden nicht in die Vorlage übernommen.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>(createTemplateTitleFieldKey)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'confirm stays disabled while the structure is unreviewed and shows the '
    'pending notice (FR-055)',
    (WidgetTester tester) async {
      var calls = 0;
      await _pumpSheet(tester, reviewed: false, onCreated: (_) => calls++);
      expect(
        find.byKey(const ValueKey<String>('create-template-pending')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>(createTemplateConfirmKey)),
      );
      await tester.pump();
      expect(calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirm calls the create action once with the trimmed title and closes '
    'after the verified success',
    (WidgetTester tester) async {
      final List<String> titles = <String>[];
      await _pumpSheet(tester, reviewed: true, onCreated: titles.add);
      await tester.enterText(
        find.byKey(const ValueKey<String>(createTemplateTitleFieldKey)),
        '  Antragsvorlage  ',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>(createTemplateConfirmKey)),
      );
      await tester.pumpAndSettle();
      expect(titles, <String>['Antragsvorlage']);
      // The verified success closed the sheet; the failure notice never
      // appeared.
      expect(
        find.byKey(const ValueKey<String>(createTemplateStatusKey)),
        findsNothing,
      );
      expect(find.text('Vorlage erstellen'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
