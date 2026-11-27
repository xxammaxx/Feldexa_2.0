// T116 layout-only template editor host-VM widget tests
// (FR-101/FR-102; evidence class NONE).
//
// Pins: the German surfaces from the ARB, FR-102 (no value input and no
// signature capture surface anywhere in the editor), FR-101 (a completed
// drag reports exactly one layout change with the moved rectangle), the
// disabled version-save action, the 48 dp semantics floor of the drag
// handles, and no overflow at 200 percent text scale.

import 'package:feldexa_app/features/templates/template_editor.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double textScale = 1.0}) {
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
    home: child,
  );
}

TemplateEditorField _field({
  required String id,
  required String label,
  core.FieldType type = core.FieldType.text,
  required core.Rect rect,
}) => TemplateEditorField(id: id, label: label, type: type, rect: rect);

TemplateEditorView _editor({
  required ValueChanged<TemplateLayoutChange> onLayoutChange,
  bool saveVersionEnabled = false,
  List<TemplateEditorField>? fieldsOverride,
}) {
  return TemplateEditorView(
    key: const ValueKey<String>('editor-under-test'),
    pages: <TemplateEditorPage>[
      TemplateEditorPage(
        index: 0,
        geometry: core.PageGeometry(
          mediaBox: core.Rect.fromLTWH(0, 0, 595, 842),
        ),
      ),
    ],
    fields:
        fieldsOverride ??
        <TemplateEditorField>[
          _field(
            id: 'f-text',
            label: 'Familienname',
            rect: core.Rect.fromLTWH(60, 100, 200, 24),
          ),
          _field(
            id: 'f-signature',
            label: 'Unterschrift',
            type: core.FieldType.signature,
            rect: core.Rect.fromLTWH(60, 200, 160, 40),
          ),
        ],
    currentPageIndex: 0,
    onLayoutChange: onLayoutChange,
    onSaveVersion: () {},
    saveVersionEnabled: saveVersionEnabled,
  );
}

void main() {
  testWidgets('renders the German layout-only surfaces from the ARB', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(_editor(onLayoutChange: (_) {})));
    expect(
      find.byKey(const ValueKey<String>(templateEditorScaffoldKey)),
      findsOneWidget,
    );
    expect(find.text('Vorlage bearbeiten (nur Layout)'), findsOneWidget);
    expect(
      find.text(
        'Diese Vorlage kann nur im Layout bearbeitet werden. Werte und '
        'Unterschriften können in einer Vorlage nicht erfasst werden.',
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Als neue Version speichern'), findsOneWidget);
    expect(find.text('Familienname'), findsOneWidget);
    expect(find.text('Unterschrift'), findsOneWidget);
    // FR-102: no value input and no signature capture surface exists.
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the version-save action stays disabled by default (FR-103)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(_editor(onLayoutChange: (_) {}, saveVersionEnabled: false)),
    );
    // Real assertion: the save action's onPressed is null, so no save path
    // can be triggered at all.
    final IconButton button = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>(templateEditorSaveVersionKey)),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('a completed drag reports exactly one layout change (FR-101)', (
    WidgetTester tester,
  ) async {
    final List<TemplateLayoutChange> changes = <TemplateLayoutChange>[];
    await tester.pumpWidget(_host(_editor(onLayoutChange: changes.add)));
    final Offset start = tester.getCenter(
      find.byKey(ValueKey<String>(templateEditorFieldKey('f-text'))),
    );
    final TestGesture gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(30, 0)); // exceed the pan slop
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(10, -3));
    }
    await gesture.up();
    await tester.pump();
    expect(changes, hasLength(1));
    expect(changes.single.fieldId, 'f-text');
    // The layout rectangle moves in page coordinates; its size is unchanged.
    expect(changes.single.rect.width, closeTo(200, 0.01));
    expect(changes.single.rect.height, closeTo(24, 0.01));
    expect(changes.single.rect.left, greaterThan(60.0));
    expect(changes.single.rect.top, lessThan(100.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('drag handles keep a 48 dp semantics floor (FR-101)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _editor(
          onLayoutChange: (_) {},
          fieldsOverride: <TemplateEditorField>[
            _field(
              id: 'f-small',
              label: 'Klein',
              rect: core.Rect.fromLTWH(60, 100, 20, 8),
            ),
          ],
        ),
      ),
    );
    final Size size = tester.getSize(
      find.byKey(ValueKey<String>(templateEditorFieldKey('f-small'))),
    );
    expect(size.width, greaterThanOrEqualTo(47.0));
    expect(size.height, greaterThanOrEqualTo(47.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow at 200 percent text scale', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(
        _editor(
          onLayoutChange: (_) {},
          fieldsOverride: <TemplateEditorField>[
            _field(
              id: 'f-long',
              label:
                  'Sehr langer Bezeichner für ein gescanntes Layoutfeld im '
                  'Antragsformular',
              rect: core.Rect.fromLTWH(40, 90, 220, 24),
            ),
          ],
        ),
        textScale: 2.0,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
