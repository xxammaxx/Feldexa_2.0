// T083 full-screen signature sheet host widget tests.
//
// Evidence class: NONE. These are host-VM widget tests with synthetic labels
// and pointer gestures. They build no platform channel, open no document,
// invoke no editor, store, file, network, or localization code, and make no
// Android, device, stylus, screen-reader, or visual claim.
//
// They prove the pinned T083 behaviour:
//   * two drawn strokes keep their canvas-local first and last coordinates and
//     apply returns one non-empty draft with exactly those strokes;
//   * undo removes only the last stroke and clear removes all ink, while both
//     actions stay disabled when the sheet is empty;
//   * a tap becomes exactly one one-point stroke and a small drag stays in one
//     stroke with clamped canvas-local points;
//   * apply reports exactly once even when empty, cancel never applies, and
//     the sheet never navigates itself;
//   * stroke points and draft strokes are unmodifiable defensive copies, and a
//     delivered draft is unchanged by later drawing, undo, or clear;
//   * a fresh instance starts empty with no static or global ink;
//   * every label comes from the caller and a 200 % text-scale build reflows
//     without exception or overflow while keeping the canvas and actions;
//   * the production source imports only the Flutter presentation framework
//     and contains no ARB, localization, file, store, or network module.

@TestOn('vm')
library;

import 'dart:io';

import 'package:feldexa_app/features/fill/signature_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _title = 'Synthetic signature title';
const String _clearLabel = 'Synthetic clear ink';
const String _undoLabel = 'Synthetic undo stroke';
const String _applyLabel = 'Synthetic apply signature';
const String _cancelLabel = 'Synthetic cancel sheet';

Widget _host({
  required ValueChanged<SignatureDraft> onApply,
  required VoidCallback onCancel,
  double textScale = 1.0,
  Key? key,
}) {
  return MaterialApp(
    builder: (BuildContext context, Widget? widget) {
      return MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: widget!,
      );
    },
    home: SignatureSheet(
      key: key,
      title: _title,
      clearLabel: _clearLabel,
      undoLabel: _undoLabel,
      applyLabel: _applyLabel,
      cancelLabel: _cancelLabel,
      onApply: onApply,
      onCancel: onCancel,
    ),
  );
}

Rect _canvasRect(WidgetTester tester) {
  return tester.getRect(find.byKey(signatureSheetCanvasKey));
}

Future<TestGesture> _startStroke(
  WidgetTester tester,
  Offset localPosition,
) async {
  return tester.startGesture(_canvasRect(tester).topLeft + localPosition);
}

Future<void> _drawStroke(
  WidgetTester tester,
  Offset localStart,
  List<Offset> deltas,
) async {
  final TestGesture gesture = await _startStroke(tester, localStart);
  for (final Offset delta in deltas) {
    await gesture.moveBy(delta);
  }
  await gesture.up();
  await tester.pump();
}

Future<void> _tapApply(WidgetTester tester) async {
  await tester.tap(find.byKey(signatureSheetApplyKey));
  await tester.pump();
}

IconButton _iconButton(WidgetTester tester, Key key) {
  return tester.widget<IconButton>(find.byKey(key));
}

void main() {
  testWidgets('draws two strokes and applies their captured geometry', (
    WidgetTester tester,
  ) async {
    final List<SignatureDraft> applied = <SignatureDraft>[];
    await tester.pumpWidget(_host(onApply: applied.add, onCancel: () {}));

    final Rect canvas = _canvasRect(tester);
    expect(canvas.width, greaterThan(0));
    expect(canvas.height, greaterThan(0));

    await _drawStroke(tester, const Offset(40, 50), <Offset>[
      const Offset(60, 0),
      const Offset(0, 40),
    ]);
    await _drawStroke(tester, const Offset(120, 160), <Offset>[
      const Offset(-30, 20),
      const Offset(10, 10),
    ]);

    await _tapApply(tester);

    expect(applied, hasLength(1));
    final SignatureDraft draft = applied.single;
    expect(draft.isEmpty, isFalse);
    expect(draft.strokes, hasLength(2));
    expect(draft.canvasSize, canvas.size);

    final SignatureStroke first = draft.strokes[0];
    final SignatureStroke second = draft.strokes[1];
    expect(first.points.length, greaterThanOrEqualTo(2));
    expect(first.points.first, const Offset(40, 50));
    expect(first.points.last, const Offset(100, 90));
    expect(second.points.length, greaterThanOrEqualTo(2));
    expect(second.points.first, const Offset(120, 160));
    expect(second.points.last, const Offset(100, 190));
  });

  testWidgets('undo removes only the last stroke and clear removes all ink', (
    WidgetTester tester,
  ) async {
    final List<SignatureDraft> applied = <SignatureDraft>[];
    await tester.pumpWidget(_host(onApply: applied.add, onCancel: () {}));

    expect(_iconButton(tester, signatureSheetUndoKey).onPressed, isNull);
    expect(_iconButton(tester, signatureSheetClearKey).onPressed, isNull);

    await _drawStroke(tester, const Offset(20, 30), <Offset>[
      const Offset(40, 10),
    ]);
    await _drawStroke(tester, const Offset(60, 70), <Offset>[
      const Offset(10, 40),
    ]);

    expect(_iconButton(tester, signatureSheetUndoKey).onPressed, isNotNull);
    expect(_iconButton(tester, signatureSheetClearKey).onPressed, isNotNull);

    await tester.tap(find.byKey(signatureSheetUndoKey));
    await tester.pump();
    await _tapApply(tester);

    expect(applied, hasLength(1));
    expect(applied.single.strokes, hasLength(1));
    expect(applied.single.strokes.single.points.first, const Offset(20, 30));
    expect(applied.single.strokes.single.points.last, const Offset(60, 40));

    await _drawStroke(tester, const Offset(100, 120), <Offset>[
      const Offset(20, 0),
    ]);
    await tester.tap(find.byKey(signatureSheetClearKey));
    await tester.pump();
    await _tapApply(tester);

    expect(applied, hasLength(2));
    expect(applied.last.isEmpty, isTrue);
    expect(applied.last.strokes, isEmpty);
    expect(applied.last.canvasSize, _canvasRect(tester).size);
    expect(_iconButton(tester, signatureSheetUndoKey).onPressed, isNull);
    expect(_iconButton(tester, signatureSheetClearKey).onPressed, isNull);
  });

  testWidgets('a tap produces exactly one one-point stroke at the tap', (
    WidgetTester tester,
  ) async {
    final List<SignatureDraft> applied = <SignatureDraft>[];
    await tester.pumpWidget(_host(onApply: applied.add, onCancel: () {}));

    final Offset tapPosition =
        _canvasRect(tester).topLeft + const Offset(80, 60);
    await tester.tapAt(tapPosition);
    await tester.pump();
    await _tapApply(tester);

    final SignatureDraft draft = applied.single;
    expect(draft.strokes, hasLength(1));
    expect(draft.strokes.single.points, <Offset>[const Offset(80, 60)]);
  });

  testWidgets('a small drag stays one stroke with clamped points', (
    WidgetTester tester,
  ) async {
    final List<SignatureDraft> applied = <SignatureDraft>[];
    await tester.pumpWidget(_host(onApply: applied.add, onCancel: () {}));

    await _drawStroke(tester, const Offset(60, 60), <Offset>[
      const Offset(30, 0),
      const Offset(5, 5),
    ]);
    await _tapApply(tester);

    final SignatureDraft draft = applied.single;
    expect(draft.strokes, hasLength(1));
    expect(draft.strokes.single.points.first, const Offset(60, 60));
    expect(draft.strokes.single.points.last, const Offset(95, 65));

    await _drawStroke(tester, const Offset(100, 100), <Offset>[
      const Offset(-500, -500),
      const Offset(2000, 2000),
    ]);
    await _tapApply(tester);

    final SignatureDraft clamped = applied.last;
    final Size canvasSize = _canvasRect(tester).size;
    expect(clamped.strokes, hasLength(2));
    expect(clamped.strokes.last.points[1], Offset.zero);
    expect(
      clamped.strokes.last.points.last,
      Offset(canvasSize.width, canvasSize.height),
    );
  });

  testWidgets('cancel never applies and apply reports exactly once', (
    WidgetTester tester,
  ) async {
    final List<SignatureDraft> applied = <SignatureDraft>[];
    int cancelCount = 0;

    await tester.pumpWidget(
      _host(
        onApply: applied.add,
        onCancel: () {
          cancelCount++;
        },
      ),
    );

    await tester.tap(find.byKey(signatureSheetCancelKey));
    await tester.pump();

    expect(cancelCount, 1);
    expect(applied, isEmpty);
    expect(find.byKey(signatureSheetCanvasKey), findsOneWidget);

    await _tapApply(tester);

    expect(cancelCount, 1);
    expect(applied, hasLength(1));
    expect(applied.single.isEmpty, isTrue);
    expect(applied.single.canvasSize, _canvasRect(tester).size);
  });

  testWidgets('draft and stroke collections are unmodifiable snapshots', (
    WidgetTester tester,
  ) async {
    final SignatureStroke stroke = SignatureStroke(
      points: <Offset>[Offset.zero, const Offset(10, 10)],
    );
    expect(
      () => stroke.points.add(const Offset(20, 20)),
      throwsUnsupportedError,
    );
    expect(() => stroke.points[0] = const Offset(5, 5), throwsUnsupportedError);

    final SignatureDraft emptyDraft = SignatureDraft(
      strokes: <SignatureStroke>[stroke],
      canvasSize: const Size(320, 240),
    );
    expect(() => emptyDraft.strokes.add(stroke), throwsUnsupportedError);
    expect(() => emptyDraft.strokes.clear(), throwsUnsupportedError);

    final List<Offset> sourcePoints = <Offset>[Offset.zero];
    final SignatureStroke copiedStroke = SignatureStroke(points: sourcePoints);
    sourcePoints.add(const Offset(1, 1));
    expect(copiedStroke.points, <Offset>[Offset.zero]);

    final List<SignatureStroke> sourceStrokes = <SignatureStroke>[copiedStroke];
    final SignatureDraft copiedDraft = SignatureDraft(
      strokes: sourceStrokes,
      canvasSize: const Size(320, 240),
    );
    sourceStrokes.add(stroke);
    expect(copiedDraft.strokes, hasLength(1));

    final List<SignatureDraft> applied = <SignatureDraft>[];
    await tester.pumpWidget(_host(onApply: applied.add, onCancel: () {}));
    await _drawStroke(tester, const Offset(20, 20), <Offset>[
      const Offset(30, 30),
    ]);
    await _tapApply(tester);

    final SignatureDraft delivered = applied.single;
    expect(delivered.strokes, hasLength(1));
    final List<Offset> deliveredPoints = delivered.strokes.single.points;
    expect(deliveredPoints, <Offset>[
      const Offset(20, 20),
      const Offset(50, 50),
    ]);

    await _drawStroke(tester, const Offset(100, 100), <Offset>[
      const Offset(10, 10),
    ]);
    await tester.tap(find.byKey(signatureSheetUndoKey));
    await tester.pump();

    expect(delivered.strokes, hasLength(1));
    expect(delivered.strokes.single.points, deliveredPoints);
    expect(delivered.isEmpty, isFalse);

    await _drawStroke(tester, const Offset(140, 140), <Offset>[
      const Offset(10, 10),
    ]);
    await tester.tap(find.byKey(signatureSheetClearKey));
    await tester.pump();

    expect(delivered.strokes, hasLength(1));
    expect(delivered.strokes.single.points, deliveredPoints);
    expect(delivered.isEmpty, isFalse);

    await _tapApply(tester);
    expect(applied, hasLength(2));
    expect(applied.last.isEmpty, isTrue);
  });

  testWidgets('a fresh instance starts empty with no static ink', (
    WidgetTester tester,
  ) async {
    final List<SignatureDraft> firstApplied = <SignatureDraft>[];
    await tester.pumpWidget(
      _host(
        key: const ValueKey<String>('first-sheet'),
        onApply: firstApplied.add,
        onCancel: () {},
      ),
    );
    await _drawStroke(tester, const Offset(15, 25), <Offset>[
      const Offset(20, 20),
    ]);
    await _tapApply(tester);

    expect(firstApplied, hasLength(1));
    expect(firstApplied.single.isEmpty, isFalse);

    final List<SignatureDraft> secondApplied = <SignatureDraft>[];
    await tester.pumpWidget(
      _host(
        key: const ValueKey<String>('second-sheet'),
        onApply: secondApplied.add,
        onCancel: () {},
      ),
    );
    await _tapApply(tester);

    expect(secondApplied, hasLength(1));
    expect(secondApplied.single.isEmpty, isTrue);
    expect(secondApplied.single.strokes, isEmpty);
  });

  testWidgets('labels come from the caller and 200 percent scale reflows', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();

    await tester.pumpWidget(
      _host(
        key: const ValueKey<String>('labelled-sheet'),
        onApply: (_) {},
        onCancel: () {},
      ),
    );

    expect(find.text(_title), findsOneWidget);
    expect(find.text(_applyLabel), findsOneWidget);
    expect(find.byTooltip(_cancelLabel), findsOneWidget);
    expect(find.byTooltip(_undoLabel), findsOneWidget);
    expect(find.byTooltip(_clearLabel), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(signatureSheetCancelKey))
          .getSemanticsData()
          .tooltip,
      _cancelLabel,
    );
    expect(
      tester
          .getSemantics(find.byKey(signatureSheetUndoKey))
          .getSemanticsData()
          .tooltip,
      _undoLabel,
    );
    expect(
      tester
          .getSemantics(find.byKey(signatureSheetClearKey))
          .getSemanticsData()
          .tooltip,
      _clearLabel,
    );

    for (final Key key in <Key>[
      signatureSheetCancelKey,
      signatureSheetUndoKey,
      signatureSheetClearKey,
    ]) {
      final Size size = tester.getSize(find.byKey(key));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    expect(
      tester.getSize(find.byKey(signatureSheetApplyKey)).height,
      greaterThanOrEqualTo(48),
    );
    final double regularCanvasHeight = _canvasRect(tester).height;

    await tester.pumpWidget(
      _host(
        key: const ValueKey<String>('labelled-sheet'),
        onApply: (_) {},
        onCancel: () {},
        textScale: 2,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text(_title), findsOneWidget);
    expect(find.text(_applyLabel), findsOneWidget);
    expect(find.byKey(signatureSheetCanvasKey), findsOneWidget);
    expect(find.byKey(signatureSheetApplyKey), findsOneWidget);
    expect(find.byTooltip(_cancelLabel), findsOneWidget);
    expect(find.byTooltip(_undoLabel), findsOneWidget);
    expect(find.byTooltip(_clearLabel), findsOneWidget);
    expect(_canvasRect(tester).height, lessThan(regularCanvasHeight));
    expect(_canvasRect(tester).height, greaterThan(0));
    expect(
      tester.getSize(find.byKey(signatureSheetApplyKey)).height,
      greaterThanOrEqualTo(48),
    );

    handle.dispose();
  });

  test('production source imports only the Flutter presentation framework', () {
    final File file = File('lib/features/fill/signature_sheet.dart');
    expect(file.existsSync(), isTrue);

    final String source = file.readAsStringSync();
    final List<String> imports = RegExp(
      r"^import '([^']+)';",
      multiLine: true,
    ).allMatches(source).map((Match match) => match.group(1)!).toList();

    expect(imports, <String>['package:flutter/material.dart']);
    expect(source, isNot(contains('AppLocalizations')));
    expect(source, isNot(contains('app_localizations')));
    expect(source, isNot(contains('l10n/')));
    expect(source, isNot(contains('features/editor')));
    expect(source, isNot(contains('feldexa_ports')));
    expect(source, isNot(contains('feldexa_application')));
    expect(source, isNot(contains('shared_preferences')));
    expect(source, isNot(contains('sqflite')));
    expect(source, isNot(contains('path_provider')));
    expect(source, isNot(contains('dart:io')));
    expect(source, isNot(contains('dart:convert')));
    expect(source, isNot(contains('Uint8List')));
    expect(source, isNot(contains('HttpClient')));
    expect(source, isNot(contains('File(')));
    expect(
      RegExp(r'[\u00e4\u00f6\u00fc\u00c4\u00d6\u00dc\u00df]').hasMatch(source),
      isFalse,
    );
    expect(RegExp(r'[\u3040-\u30ff\u4e00-\u9fff]').hasMatch(source), isFalse);
  });
}
