// T082 reusable checkbox control host widget tests.
//
// Evidence class: NONE. These are host-VM widget tests with synthetic labels
// and values. They build no platform channel, open no document, invoke no
// editor, store, or localization code, and make no Android, device,
// screen-reader, or visual claim.
//
// They prove the pinned T082 behaviour:
//   * unchecked and checked states render and expose checked semantics;
//   * the caller label or the semantic override names one accessible control;
//   * a tap toggles false to true to false, reporting each new value once;
//   * the hit region is at least 48 by 48 dp, edge taps toggle, outside taps
//     do not;
//   * the drawn box stays smaller than the hit region;
//   * disabled and read-only controls neither toggle nor call back;
//   * two controls keep independent caller-owned values;
//   * a long label builds at 200 % text scale without overflow or exception;
//   * the production source imports no ARB, localization, editor, or
//     persistence module and contains no German or Japanese literal.

@TestOn('vm')
library;

import 'dart:io';

import 'package:feldexa_app/features/fill/checkbox_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/package_root.dart';

Widget _host(Widget child, {double width = 360, double textScale = 1.0}) {
  return MaterialApp(
    builder: (BuildContext context, Widget? widget) {
      return MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: widget!,
      );
    },
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

Finder _control([int index = 0]) {
  return find.byKey(fieldCheckboxControlKey).at(index);
}

Finder _box([int index = 0]) {
  return find.byKey(fieldCheckboxBoxKey).at(index);
}

void main() {
  testWidgets('renders unchecked and checked states with the caller label', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();

    await tester.pumpWidget(
      _host(
        FieldCheckboxControl(
          label: 'Synthetic consent',
          value: false,
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Synthetic consent'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
    expect(
      tester.getSemantics(_control()),
      matchesSemantics(
        label: 'Synthetic consent',
        hasCheckedState: true,
        isChecked: false,
        hasEnabledState: true,
        isEnabled: true,
        isReadOnly: false,
        hasTapAction: true,
      ),
    );

    await tester.pumpWidget(
      _host(
        FieldCheckboxControl(
          label: 'Synthetic consent',
          value: true,
          semanticLabel: 'Synthetic accessible consent',
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Synthetic consent'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(
      tester.getSemantics(_control()),
      matchesSemantics(
        label: 'Synthetic accessible consent',
        hasCheckedState: true,
        isChecked: true,
        hasEnabledState: true,
        isEnabled: true,
        isReadOnly: false,
        hasTapAction: true,
      ),
    );

    handle.dispose();
  });

  testWidgets('tap toggles false to true to false, once per tap', (
    WidgetTester tester,
  ) async {
    final List<bool> changes = <bool>[];
    late StateSetter setHostState;
    bool current = false;

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            setHostState = setState;
            return FieldCheckboxControl(
              label: 'Synthetic toggle',
              value: current,
              onChanged: (bool next) {
                changes.add(next);
                setHostState(() {
                  current = next;
                });
              },
            );
          },
        ),
      ),
    );

    expect(find.byIcon(Icons.check), findsNothing);

    await tester.tap(_box());
    await tester.pump();

    expect(changes, <bool>[true]);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(_box());
    await tester.pump();

    expect(changes, <bool>[true, false]);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('hit region is at least 48 by 48 dp and edges toggle', (
    WidgetTester tester,
  ) async {
    final List<bool> changes = <bool>[];

    await tester.pumpWidget(
      _host(
        FieldCheckboxControl(
          label: 'Synthetic edge',
          value: false,
          onChanged: changes.add,
        ),
      ),
    );

    final Size size = tester.getSize(_control());
    expect(size.width, greaterThanOrEqualTo(48.0));
    expect(size.height, greaterThanOrEqualTo(48.0));

    final Rect rect = tester.getRect(_control());
    await tester.tapAt(Offset(rect.right - 2, rect.bottom - 2));
    await tester.pump();
    expect(changes, <bool>[true]);

    await tester.tapAt(Offset(rect.right + 20, rect.center.dy));
    await tester.pump();
    expect(changes, <bool>[true]);
  });

  testWidgets('drawn box stays smaller than the hit region', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        FieldCheckboxControl(
          label: 'Synthetic geometry',
          value: true,
          onChanged: (_) {},
        ),
      ),
    );

    final Size box = tester.getSize(_box());
    final Size control = tester.getSize(_control());

    expect(box.width, lessThan(48.0));
    expect(box.height, lessThan(48.0));
    expect(box.width, 24.0);
    expect(box.height, 24.0);
    expect(control.width, greaterThan(box.width));
    expect(control.height, greaterThan(box.height));
  });

  testWidgets('disabled and read-only controls neither toggle nor call back', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final List<bool> changes = <bool>[];

    await tester.pumpWidget(
      _host(
        FieldCheckboxControl(
          label: 'Synthetic disabled',
          value: false,
          enabled: false,
          onChanged: changes.add,
        ),
      ),
    );

    expect(
      tester.getSemantics(_control()),
      matchesSemantics(
        label: 'Synthetic disabled',
        hasCheckedState: true,
        isChecked: false,
        hasEnabledState: true,
        isEnabled: false,
        isReadOnly: false,
        hasTapAction: false,
      ),
    );

    await tester.tap(_box(), warnIfMissed: false);
    await tester.pump();
    expect(changes, isEmpty);

    await tester.pumpWidget(
      _host(
        FieldCheckboxControl(
          label: 'Synthetic read-only',
          value: true,
          readOnly: true,
          onChanged: changes.add,
        ),
      ),
    );

    expect(
      tester.getSemantics(_control()),
      matchesSemantics(
        label: 'Synthetic read-only',
        hasCheckedState: true,
        isChecked: true,
        hasEnabledState: true,
        isEnabled: true,
        isReadOnly: true,
        hasTapAction: false,
      ),
    );

    await tester.tap(_box(), warnIfMissed: false);
    await tester.pump();
    expect(changes, isEmpty);

    handle.dispose();
  });

  testWidgets('two controls keep independent caller-owned values', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final List<bool> values = <bool>[false, false];
    final List<int> changes = <int>[];
    late StateSetter setHostState;

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            setHostState = setState;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                FieldCheckboxControl(
                  label: 'Synthetic first',
                  value: values[0],
                  onChanged: (bool next) {
                    changes.add(0);
                    setHostState(() {
                      values[0] = next;
                    });
                  },
                ),
                FieldCheckboxControl(
                  label: 'Synthetic second',
                  value: values[1],
                  onChanged: (bool next) {
                    changes.add(1);
                    setHostState(() {
                      values[1] = next;
                    });
                  },
                ),
              ],
            );
          },
        ),
      ),
    );

    await tester.tap(_box(0));
    await tester.pump();

    expect(changes, <int>[0]);
    expect(values, <bool>[true, false]);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(
      tester.getSemantics(_control(0)),
      matchesSemantics(
        label: 'Synthetic first',
        hasCheckedState: true,
        isChecked: true,
        hasEnabledState: true,
        isEnabled: true,
        isReadOnly: false,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(_control(1)),
      matchesSemantics(
        label: 'Synthetic second',
        hasCheckedState: true,
        isChecked: false,
        hasEnabledState: true,
        isEnabled: true,
        isReadOnly: false,
        hasTapAction: true,
      ),
    );

    handle.dispose();
  });

  testWidgets('renders a long label at 200 percent text scale', (
    WidgetTester tester,
  ) async {
    const String longLabel =
        'Synthetic label long enough to wrap across several lines at large '
        'text scale without hiding any part of the caller text';

    await tester.pumpWidget(
      _host(
        FieldCheckboxControl(label: longLabel, value: true, onChanged: (_) {}),
        width: 240,
        textScale: 2,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text(longLabel), findsOneWidget);

    final Size control = tester.getSize(_control());
    expect(control.width, greaterThanOrEqualTo(48.0));
    expect(control.height, greaterThanOrEqualTo(48.0));
  });

  test('production source imports only the Flutter presentation framework', () {
    final File file = File(
      '${packageRoot.path}/lib/features/fill/checkbox_control.dart',
    );
    expect(file.existsSync(), isTrue);

    final String source = file.readAsStringSync();
    final List<String> imports = RegExp(
      r"^import '([^']+)';",
      multiLine: true,
    ).allMatches(source).map((Match match) => match.group(1)!).toList();

    expect(imports, <String>['package:flutter/material.dart']);
    expect(source, isNot(contains('AppLocalizations')));
    expect(source, isNot(contains('features/editor')));
    expect(source, isNot(contains('feldexa_ports')));
    expect(source, isNot(contains('feldexa_application')));
    expect(source, isNot(contains('shared_preferences')));
    expect(source, isNot(contains('dart:io')));
    expect(
      RegExp(r'[\u00e4\u00f6\u00fc\u00c4\u00d6\u00dc\u00df]').hasMatch(source),
      isFalse,
    );
    expect(RegExp(r'[\u3040-\u30ff\u4e00-\u9fff]').hasMatch(source), isFalse);
  });
}
