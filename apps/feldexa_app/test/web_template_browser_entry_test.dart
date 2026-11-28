// T121 SIMULATED browser template-entry suite (FR-054/FR-056/FR-057,
// FR-086/FR-087).
//
// Pattern: `test/web_review_browser_entry_test.dart` (PR #356). The suite is
// platform-agnostic: it runs on the host VM (evidence class NONE) and, with
// Chrome available, in the browser lane (evidence class SIMULATED). The lane
// was unblocked on 2026-11-28
// (`specs/001-scanned-form-workflow/reports/2026-11-28-browser-lane.md`); the
// suite runs there with FLD-001 text-fit measurement disabled because the
// Flutter web test platform serves no asset bundle.
//
// The suite exercises the real template-entry surfaces: the "Als Vorlage
// speichern" sheet with its exclusion notice and disabled confirm while the
// field structure is unreviewed (FR-055), and the layout-only editor's
// surfaces without any value/signature control (FR-102). All German copy is
// resolved from the generated ARB localizations.
//
// The suite lives under `test/` because Flutter roots Chrome browser tests
// at `<project>/test` (same measured constraint as T062/T072).

library;

import 'package:feldexa_app/features/templates/create_template.dart';
import 'package:feldexa_app/features/templates/template_editor.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({double textScale = 1.0}) {
  return MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (BuildContext context, Widget? inner) {
      return MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: inner!,
      );
    },
    home: const _SheetOpener(),
  );
}

class _SheetOpener extends StatelessWidget {
  const _SheetOpener();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () {
          showCreateTemplateSheet(
            context,
            reviewed: false,
            initialTitle: 'Antragsvorlage',
            onCreate: (String _) async {
              // The entry test never reaches a verified creation: the
              // sheet's confirm stays disabled while unreviewed.
              throw UnimplementedError();
            },
          );
        },
        child: const Text('vorlage-oeffnen'),
      ),
    );
  }
}

void main() {
  testWidgets('template entry shows the exclusion notice and keeps confirm '
      'disabled while unreviewed', (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('vorlage-oeffnen'));
    await tester.pumpAndSettle();

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
      find.byKey(const ValueKey<String>('create-template-pending')),
      findsOneWidget,
    );
    // Real assertion: confirm has no callback while the structure is
    // unreviewed, so no creation path can be triggered.
    final TextButton confirm = tester.widget<TextButton>(
      find.byKey(const ValueKey<String>(createTemplateConfirmKey)),
    );
    expect(confirm.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('create-template sheet has no overflow at 200 percent scale', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(textScale: 2.0));
    await tester.tap(find.text('vorlage-oeffnen'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the layout-only template editor exposes no value or '
      'signature control (FR-102)', (WidgetTester tester) async {
    await tester.pumpWidget(
      _hostChild(
        TemplateEditorView(
          pages: <TemplateEditorPage>[
            TemplateEditorPage(
              index: 0,
              geometry: core.PageGeometry(
                mediaBox: core.Rect.fromLTWH(0, 0, 595, 842),
              ),
            ),
          ],
          fields: <TemplateEditorField>[
            TemplateEditorField(
              id: 'f-1',
              label: 'Familienname',
              type: core.FieldType.text,
              rect: core.Rect.fromLTWH(60, 100, 200, 24),
            ),
            TemplateEditorField(
              id: 'f-2',
              label: 'Unterschrift',
              type: core.FieldType.signature,
              rect: core.Rect.fromLTWH(60, 200, 160, 40),
            ),
          ],
          currentPageIndex: 0,
          onLayoutChange: (_) {},
          onSaveVersion: () {},
        ),
      ),
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('Familienname'), findsOneWidget);
    expect(find.text('Unterschrift'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

// The editor test hosts an arbitrary child under the localized app.
Widget _hostChild(Widget child, {double textScale = 1.0}) {
  return MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (BuildContext context, Widget? inner) {
      return MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: inner!,
      );
    },
    home: Scaffold(body: child),
  );
}
