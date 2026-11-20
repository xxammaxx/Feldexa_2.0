// T069 field-overlay painting tests.
//
// These are host-VM tests (evidence class NONE). They pin the normative
// mapping and presentation rules from `contracts/editor-interactions.md`
// §2–§4/§11, `contracts/coordinates-and-geometry.md` §2/§6, `data-model.md`
// §3.4–§3.5, FR-024/FR-083/FR-094, and SC-017:
//   * display-space rects map to view space by the §3 formula, linearly and
//     without mutating the stored item or its `core.Rect`;
//   * visible items are clipped to the page and fully outside items remain in
//     the result but contribute no paint or semantics;
//   * provenance, confidence, conflict, and selection resolve to the pinned
//     style values with inclusive thresholds;
//   * invalid page input throws `ArgumentError`;
//   * `shouldRepaint` uses value equality over all painter inputs;
//   * semantics expose exactly the visible labelled items, in input order,
//     with labels verbatim and `TextDirection.ltr`;
//   * the widget is pointer-inert, exception-free at 200% text scale, and
//     paints no text.

import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_ui/feldexa_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _firstId = '00000000-0000-4000-8000-000000000001';

DateTime _at() => DateTime.utc(2026, 11, 20, 12);

core.Rect _storedRect({
  double left = 10,
  double top = 20,
  double width = 30,
  double height = 40,
}) {
  return core.Rect.fromLTWH(left, top, width, height);
}

core.FieldSuggestion _suggestion({
  core.Rect? rect,
  double confidence = 0.82,
  String? labelText = 'Name',
  Iterable<String> conflictsWith = const <String>[],
}) {
  return core.FieldSuggestion(
    id: 's_p0_0001',
    pageIndex: 0,
    rect: rect ?? _storedRect(),
    proposedType: core.FieldType.text,
    confidence: confidence,
    labelText: labelText,
    evidence: core.SuggestionEvidence(
      cues: const <core.SuggestionCue>[core.SuggestionCue.line],
    ),
    conflictsWith: conflictsWith,
  );
}

core.ConfirmedField _confirmedField({
  required core.Provenance provenance,
  String label = 'Feld',
  String? sourceSuggestionId,
  double? suggestionConfidence,
  core.Rect? rect,
}) {
  return core.ConfirmedField(
    id: provenance == core.Provenance.template ? 'template-field-1' : _firstId,
    pageIndex: 0,
    rect: rect ?? _storedRect(),
    type: core.FieldType.text,
    provenance: provenance,
    sourceSuggestionId: sourceSuggestionId,
    suggestionConfidence: suggestionConfidence,
    label: label,
    order: 0,
    createdAt: _at(),
    updatedAt: _at(),
  );
}

FieldOverlayItem _overlayItem({
  String id = 'item',
  core.Rect? rect,
  FieldOverlayProvenance provenance = FieldOverlayProvenance.machineSuggestion,
  double? confidence = 0.80,
  bool conflicting = false,
  bool selected = false,
  String? semanticLabel = 'Name',
}) {
  return FieldOverlayItem(
    id: id,
    pageIndex: 0,
    rect: rect ?? _storedRect(),
    provenance: provenance,
    confidence: confidence,
    conflicting: conflicting,
    selected: selected,
    semanticLabel: semanticLabel,
  );
}

FieldOverlayPainter _painter({
  List<FieldOverlayItem>? items,
  Size pageSize = const Size(100, 100),
  Rect pageRect = const Rect.fromLTWH(0, 0, 100, 100),
  Color selectionColor = Colors.pink,
}) {
  return FieldOverlayPainter(
    items: items ?? <FieldOverlayItem>[_overlayItem()],
    pageSize: pageSize,
    pageRect: pageRect,
    selectionColor: selectionColor,
  );
}

void main() {
  group('FieldOverlayItem factories', () {
    test('fromSuggestion copies model values without writing back', () {
      final core.FieldSuggestion suggestion = _suggestion(
        rect: _storedRect(left: 12, top: 34, width: 56, height: 78),
        confidence: 0.82,
        labelText: 'Name',
        conflictsWith: const <String>['s_p0_0002'],
      );
      final Map<String, Object?> snapshot = suggestion.toJson();

      final FieldOverlayItem item = FieldOverlayItem.fromSuggestion(
        suggestion,
        selected: true,
      );

      expect(item.id, 's_p0_0001');
      expect(item.pageIndex, 0);
      expect(item.rect, suggestion.rect);
      expect(identical(item.rect, suggestion.rect), isTrue);
      expect(item.provenance, FieldOverlayProvenance.machineSuggestion);
      expect(item.confidence, 0.82);
      expect(item.conflicting, isTrue);
      expect(item.selected, isTrue);
      expect(item.semanticLabel, 'Name');

      expect(suggestion.toJson(), snapshot);
      expect(suggestion.resolution, core.SuggestionResolution.unresolved);
      expect(item.selected, isTrue);
    });

    test('fromSuggestion honours an explicit semanticLabel override', () {
      final FieldOverlayItem item = FieldOverlayItem.fromSuggestion(
        _suggestion(labelText: 'Name'),
        semanticLabel: 'Benutzerdefiniert',
      );

      expect(item.semanticLabel, 'Benutzerdefiniert');
    });

    test('fromConfirmedField maps machine, user, and template provenance', () {
      final core.ConfirmedField machine = _confirmedField(
        provenance: core.Provenance.machine,
        sourceSuggestionId: 's_p0_0001',
        suggestionConfidence: 0.82,
        label: 'Bestätigt',
      );
      final core.ConfirmedField user = _confirmedField(
        provenance: core.Provenance.user,
        label: 'Selbst erstellt',
      );
      final core.ConfirmedField template = _confirmedField(
        provenance: core.Provenance.template,
        label: 'Vorlage',
      );
      final Map<String, Object?> machineSnapshot = machine.toJson();
      final Map<String, Object?> userSnapshot = user.toJson();
      final Map<String, Object?> templateSnapshot = template.toJson();

      final FieldOverlayItem machineItem = FieldOverlayItem.fromConfirmedField(
        machine,
        selected: true,
      );
      final FieldOverlayItem userItem = FieldOverlayItem.fromConfirmedField(
        user,
      );
      final FieldOverlayItem templateItem = FieldOverlayItem.fromConfirmedField(
        template,
      );

      expect(machineItem.id, _firstId);
      expect(machineItem.provenance, FieldOverlayProvenance.confirmedMachine);
      expect(machineItem.confidence, 0.82);
      expect(machineItem.conflicting, isFalse);
      expect(machineItem.selected, isTrue);
      expect(machineItem.semanticLabel, 'Bestätigt');

      expect(userItem.provenance, FieldOverlayProvenance.user);
      expect(userItem.confidence, isNull);
      expect(userItem.semanticLabel, 'Selbst erstellt');

      expect(templateItem.provenance, FieldOverlayProvenance.template);
      expect(templateItem.confidence, isNull);
      expect(templateItem.semanticLabel, 'Vorlage');

      expect(machine.toJson(), machineSnapshot);
      expect(user.toJson(), userSnapshot);
      expect(template.toJson(), templateSnapshot);
    });

    test('fromConfirmedField honours an explicit semanticLabel override', () {
      final FieldOverlayItem item = FieldOverlayItem.fromConfirmedField(
        _confirmedField(
          provenance: core.Provenance.user,
          label: 'Modell-Label',
        ),
        semanticLabel: 'Aufrufer-Label',
      );

      expect(item.semanticLabel, 'Aufrufer-Label');
    });

    test('items and styles are value objects', () {
      expect(_overlayItem(id: 'a'), _overlayItem(id: 'a'));
      expect(_overlayItem(id: 'a').hashCode, _overlayItem(id: 'a').hashCode);
      expect(_overlayItem(id: 'a') == _overlayItem(id: 'b'), isFalse);
      expect(
        _overlayItem(id: 'a') == _overlayItem(id: 'a', selected: true),
        isFalse,
      );

      final FieldOverlayStyle style = fieldOverlayStyle(
        _overlayItem(),
        selectionColor: Colors.pink,
      );
      expect(
        style,
        fieldOverlayStyle(_overlayItem(), selectionColor: Colors.red),
      );
    });
  });

  group('layoutFieldOverlay', () {
    test('maps exact positions and sizes on both axes with linearity', () {
      final core.Rect storedA = _storedRect(
        left: 60,
        top: 80,
        width: 120,
        height: 40,
      );
      final core.Rect storedB = _storedRect(
        left: 120,
        top: 160,
        width: 240,
        height: 80,
      );
      final core.FieldSuggestion suggestion = _suggestion(
        rect: storedA,
        labelText: 'Name',
      );
      final FieldOverlayItem itemA = FieldOverlayItem.fromSuggestion(
        suggestion,
      );
      final FieldOverlayItem itemB = _overlayItem(id: 'b', rect: storedB);
      final List<FieldOverlayItem> items = <FieldOverlayItem>[itemA, itemB];
      final Map<String, Object?> snapshot = suggestion.toJson();

      final List<FieldOverlayLayout> layouts = layoutFieldOverlay(
        items: items,
        pageSize: const Size(600, 800),
        pageRect: const Rect.fromLTWH(30, 40, 300, 400),
        selectionColor: Colors.pink,
      );

      expect(layouts, hasLength(2));
      expect(layouts[0].item.id, 's_p0_0001');
      expect(layouts[1].item.id, 'b');

      final Rect viewA = layouts[0].viewRect;
      expect(viewA.left, closeTo(60, 1e-9));
      expect(viewA.top, closeTo(80, 1e-9));
      expect(viewA.width, closeTo(60, 1e-9));
      expect(viewA.height, closeTo(20, 1e-9));
      expect(viewA.right, closeTo(120, 1e-9));
      expect(viewA.bottom, closeTo(100, 1e-9));

      final Rect viewB = layouts[1].viewRect;
      expect(viewB.left, closeTo(90, 1e-9));
      expect(viewB.top, closeTo(120, 1e-9));
      expect(viewB.width, closeTo(120, 1e-9));
      expect(viewB.height, closeTo(40, 1e-9));

      // Doubling the model offsets and extents doubles the view deltas.
      expect(viewB.left - 30, closeTo(2 * (viewA.left - 30), 1e-9));
      expect(viewB.top - 40, closeTo(2 * (viewA.top - 40), 1e-9));
      expect(viewB.width, closeTo(2 * viewA.width, 1e-9));
      expect(viewB.height, closeTo(2 * viewA.height, 1e-9));

      expect(layouts[0].clippedRect, viewA);
      expect(identical(itemA.rect, suggestion.rect), isTrue);
      expect(itemA.rect, storedA);
      expect(storedA.left, 60);
      expect(storedA.top, 80);
      expect(storedA.width, 120);
      expect(storedA.height, 40);
      expect(items, hasLength(2));
      expect(identical(items[0], itemA), isTrue);
      expect(suggestion.toJson(), snapshot);
    });

    test('maps the page origin and survives a non-1 scale', () {
      final List<FieldOverlayLayout> layouts = layoutFieldOverlay(
        items: <FieldOverlayItem>[
          _overlayItem(
            rect: _storedRect(left: 0, top: 0, width: 10, height: 10),
          ),
        ],
        pageSize: const Size(200, 100),
        pageRect: const Rect.fromLTWH(25, 35, 100, 300),
        selectionColor: Colors.pink,
      );

      final Rect view = layouts.single.viewRect;
      expect(view.left, closeTo(25, 1e-9));
      expect(view.top, closeTo(35, 1e-9));
      expect(view.width, closeTo(5, 1e-9));
      expect(view.height, closeTo(30, 1e-9));
    });

    test('clips partly outside items and keeps fully outside items', () {
      final FieldOverlayItem partial = _overlayItem(
        id: 'partial',
        rect: _storedRect(left: 50, top: 60, width: 100, height: 100),
        semanticLabel: 'Teilweise',
      );
      final FieldOverlayItem outside = _overlayItem(
        id: 'outside',
        rect: _storedRect(left: 150, top: 150, width: 10, height: 10),
        semanticLabel: 'Außerhalb',
      );
      final List<FieldOverlayItem> items = <FieldOverlayItem>[partial, outside];

      final List<FieldOverlayLayout> layouts = layoutFieldOverlay(
        items: items,
        pageSize: const Size(100, 100),
        pageRect: const Rect.fromLTWH(0, 0, 100, 100),
        selectionColor: Colors.pink,
      );

      expect(
        layouts.map((FieldOverlayLayout layout) => layout.item.id),
        <String>['partial', 'outside'],
      );
      expect(layouts[0].viewRect, const Rect.fromLTWH(50, 60, 100, 100));
      expect(layouts[0].clippedRect, const Rect.fromLTWH(50, 60, 50, 40));
      expect(layouts[0].isVisible, isTrue);
      expect(layouts[1].viewRect, const Rect.fromLTWH(150, 150, 10, 10));
      expect(layouts[1].clippedRect.isEmpty, isTrue);
      expect(layouts[1].isVisible, isFalse);
      expect(items, hasLength(2));
    });

    test('never paints or labels a fully outside item', () {
      final FieldOverlayItem partial = _overlayItem(
        id: 'partial',
        rect: _storedRect(left: 50, top: 60, width: 100, height: 100),
        semanticLabel: 'Teilweise',
      );
      final FieldOverlayItem outside = _overlayItem(
        id: 'outside',
        rect: _storedRect(left: 150, top: 150, width: 10, height: 10),
        semanticLabel: 'Außerhalb',
      );
      final FieldOverlayPainter painter = _painter(
        items: <FieldOverlayItem>[partial, outside],
      );

      final _RecordingCanvas canvas = _RecordingCanvas();
      painter.paint(canvas, const Size(100, 100));

      final List<_RecordedInvocation> drawRects = canvas.calls
          .where((_RecordedInvocation call) => call.memberName == #drawRect)
          .toList();
      expect(drawRects, hasLength(1));
      expect(
        drawRects.single.positionalArguments[0],
        const Rect.fromLTWH(50, 60, 100, 100),
      );

      final List<CustomPainterSemantics> semantics = painter.semanticsBuilder(
        const Size(100, 100),
      );
      expect(semantics, hasLength(1));
      expect(semantics.single.properties.label, 'Teilweise');
      expect(semantics.single.rect, const Rect.fromLTWH(50, 60, 50, 40));
    });

    test('accepts a finite zero-area page rectangle without clamping', () {
      final List<FieldOverlayLayout> layouts = layoutFieldOverlay(
        items: <FieldOverlayItem>[_overlayItem()],
        pageSize: const Size(100, 100),
        pageRect: const Rect.fromLTWH(50, 50, 0, 0),
        selectionColor: Colors.pink,
      );

      expect(layouts, hasLength(1));
      expect(layouts.single.viewRect, const Rect.fromLTWH(50, 50, 0, 0));
      expect(layouts.single.clippedRect.isEmpty, isTrue);
    });

    test('throws ArgumentError for invalid page sizes', () {
      final List<FieldOverlayItem> items = <FieldOverlayItem>[_overlayItem()];
      const Rect pageRect = Rect.fromLTWH(0, 0, 100, 100);
      final List<Size> invalidSizes = <Size>[
        Size.zero,
        const Size(-1, 10),
        const Size(10, -1),
        const Size(double.nan, 10),
        const Size(10, double.nan),
        const Size(double.infinity, 10),
        const Size(10, double.negativeInfinity),
      ];

      for (final Size pageSize in invalidSizes) {
        expect(
          () => layoutFieldOverlay(
            items: items,
            pageSize: pageSize,
            pageRect: pageRect,
            selectionColor: Colors.pink,
          ),
          throwsArgumentError,
          reason: '$pageSize must be rejected',
        );
      }
    });

    test('throws ArgumentError for non-finite page rectangles', () {
      final List<FieldOverlayItem> items = <FieldOverlayItem>[_overlayItem()];
      const Size pageSize = Size(100, 100);
      final List<Rect> invalidRects = <Rect>[
        Rect.fromLTRB(double.nan, 0, 100, 100),
        Rect.fromLTRB(0, double.nan, 100, 100),
        Rect.fromLTRB(0, 0, double.infinity, 100),
        Rect.fromLTRB(0, 0, 100, double.negativeInfinity),
      ];

      for (final Rect pageRect in invalidRects) {
        expect(
          () => layoutFieldOverlay(
            items: items,
            pageSize: pageSize,
            pageRect: pageRect,
            selectionColor: Colors.pink,
          ),
          throwsArgumentError,
          reason: '$pageRect must be rejected',
        );
      }
    });
  });

  group('fieldOverlayStyle', () {
    test('machine confidence thresholds are inclusive', () {
      final FieldOverlayStyle solid = fieldOverlayStyle(
        _overlayItem(confidence: 0.80),
        selectionColor: Colors.pink,
      );
      expect(solid.outlineColor, Colors.blue);
      expect(solid.dashed, isFalse);
      expect(solid.uncertain, isFalse);
      expect(solid.strokeWidth, 1.5);

      final FieldOverlayStyle solidAtBoundary = fieldOverlayStyle(
        _overlayItem(confidence: 0.75),
        selectionColor: Colors.pink,
      );
      expect(solidAtBoundary.dashed, isFalse);
      expect(solidAtBoundary.uncertain, isFalse);

      final FieldOverlayStyle dashed = fieldOverlayStyle(
        _overlayItem(confidence: 0.74),
        selectionColor: Colors.pink,
      );
      expect(dashed.outlineColor, Colors.blue);
      expect(dashed.dashed, isTrue);
      expect(dashed.uncertain, isFalse);
      expect(dashed.strokeWidth, 1.5);

      final FieldOverlayStyle certainAtBoundary = fieldOverlayStyle(
        _overlayItem(confidence: 0.50),
        selectionColor: Colors.pink,
      );
      expect(certainAtBoundary.dashed, isTrue);
      expect(certainAtBoundary.uncertain, isFalse);

      final FieldOverlayStyle uncertain = fieldOverlayStyle(
        _overlayItem(confidence: 0.49),
        selectionColor: Colors.pink,
      );
      expect(uncertain.dashed, isTrue);
      expect(uncertain.uncertain, isTrue);
      expect(uncertain.strokeWidth, 1.5);

      final FieldOverlayStyle unknown = fieldOverlayStyle(
        _overlayItem(confidence: null),
        selectionColor: Colors.pink,
      );
      expect(unknown.outlineColor, Colors.blue);
      expect(unknown.dashed, isTrue);
      expect(unknown.uncertain, isTrue);
    });

    test('confirmed, user, and template provenance are solid and certain', () {
      for (final (FieldOverlayProvenance provenance, Color color)
          in <(FieldOverlayProvenance, Color)>[
            (FieldOverlayProvenance.confirmedMachine, Colors.green),
            (FieldOverlayProvenance.user, Colors.amber),
            (FieldOverlayProvenance.template, Colors.purple),
          ]) {
        final FieldOverlayStyle style = fieldOverlayStyle(
          _overlayItem(
            provenance: provenance,
            confidence: 0.49,
            conflicting: true,
          ),
          selectionColor: Colors.pink,
        );

        expect(style.outlineColor, color, reason: '$provenance');
        expect(style.dashed, isFalse, reason: '$provenance');
        expect(style.uncertain, isFalse, reason: '$provenance');
        expect(style.strokeWidth, 1.5, reason: '$provenance');
        expect(style.conflicting, isTrue, reason: '$provenance');
        expect(style.selected, isFalse, reason: '$provenance');
      }
    });

    test('conflict and selection flags are carried through', () {
      final FieldOverlayStyle style = fieldOverlayStyle(
        _overlayItem(conflicting: true, selected: true),
        selectionColor: Colors.pink,
      );

      expect(style.conflicting, isTrue);
      expect(style.selected, isTrue);
    });
  });

  group('FieldOverlayPainter', () {
    test('shouldRepaint compares items, page size, page rect, and accent', () {
      final FieldOverlayItem item = _overlayItem(id: 'a');
      final FieldOverlayPainter original = _painter(
        items: <FieldOverlayItem>[item],
      );

      expect(
        _painter(items: <FieldOverlayItem>[item]).shouldRepaint(original),
        isFalse,
      );
      expect(original.shouldRepaint(original), isFalse);

      expect(
        _painter(
          items: <FieldOverlayItem>[_overlayItem(id: 'a', confidence: 0.4)],
        ).shouldRepaint(original),
        isTrue,
      );
      expect(
        _painter(
          items: <FieldOverlayItem>[item],
          pageSize: const Size(101, 100),
        ).shouldRepaint(original),
        isTrue,
      );
      expect(
        _painter(
          items: <FieldOverlayItem>[item],
          pageRect: const Rect.fromLTWH(1, 0, 100, 100),
        ).shouldRepaint(original),
        isTrue,
      );
      expect(
        _painter(
          items: <FieldOverlayItem>[item],
          selectionColor: Colors.orange,
        ).shouldRepaint(original),
        isTrue,
      );
      expect(
        _painter(
          items: <FieldOverlayItem>[
            item,
            _overlayItem(id: 'b'),
          ],
        ).shouldRepaint(original),
        isTrue,
      );
    });

    test('no-ops an empty or zero-area page without touching the canvas', () {
      final _RecordingCanvas canvas = _RecordingCanvas();

      _painter(
        pageSize: Size.zero,
        pageRect: const Rect.fromLTWH(0, 0, 100, 100),
      ).paint(canvas, Size.zero);
      expect(canvas.calls, isEmpty);

      _painter(
        pageSize: const Size(100, 100),
        pageRect: const Rect.fromLTWH(0, 0, 0, 100),
      ).paint(canvas, const Size(100, 100));
      expect(canvas.calls, isEmpty);

      expect(
        _painter(
          pageSize: Size.zero,
          pageRect: const Rect.fromLTWH(0, 0, 100, 100),
        ).semanticsBuilder(Size.zero),
        isEmpty,
      );
    });

    test('uses deterministic dashes for a low-confidence suggestion', () {
      final FieldOverlayPainter painter = _painter(
        items: <FieldOverlayItem>[_overlayItem(confidence: 0.49)],
      );
      final _RecordingCanvas first = _RecordingCanvas();
      final _RecordingCanvas second = _RecordingCanvas();

      painter.paint(first, const Size(100, 100));
      painter.paint(second, const Size(100, 100));

      expect(first.calls, isNotEmpty);
      expect(
        first.calls.map((_RecordedInvocation call) => call.memberName),
        second.calls.map((_RecordedInvocation call) => call.memberName),
      );
      expect(
        first.calls.where(
          (_RecordedInvocation call) => call.memberName == #drawLine,
        ),
        isNotEmpty,
      );
      expect(
        first.calls.where(
          (_RecordedInvocation call) => call.memberName == #drawRect,
        ),
        isEmpty,
      );
    });

    test('draws the selection accent and corner handle', () {
      final FieldOverlayPainter painter = _painter(
        items: <FieldOverlayItem>[_overlayItem(selected: true)],
        selectionColor: Colors.pink,
      );
      final _RecordingCanvas canvas = _RecordingCanvas();

      painter.paint(canvas, const Size(100, 100));

      final List<_RecordedInvocation> drawRects = canvas.calls
          .where((_RecordedInvocation call) => call.memberName == #drawRect)
          .toList();
      // Base outline + 2 dp accent outline + 6x6 corner handle.
      expect(drawRects, hasLength(3));
      expect(
        drawRects[1].positionalArguments[0],
        const Rect.fromLTWH(10, 20, 30, 40),
      );
      expect(
        drawRects[2].positionalArguments[0],
        const Rect.fromLTWH(34, 54, 6, 6),
      );
    });

    test('draws a shape conflict marker for conflicting items', () {
      final FieldOverlayPainter painter = _painter(
        items: <FieldOverlayItem>[_overlayItem(conflicting: true)],
      );
      final _RecordingCanvas canvas = _RecordingCanvas();

      painter.paint(canvas, const Size(100, 100));

      final List<_RecordedInvocation> drawPaths = canvas.calls
          .where((_RecordedInvocation call) => call.memberName == #drawPath)
          .toList();
      expect(drawPaths, hasLength(2));
    });
  });

  group('semanticsBuilder', () {
    test(
      'emits visible labelled items in input order with verbatim labels',
      () {
        final FieldOverlayPainter painter = _painter(
          items: <FieldOverlayItem>[
            _overlayItem(
              id: 'first',
              rect: _storedRect(left: 10, top: 10, width: 20, height: 20),
              semanticLabel: 'Name',
            ),
            _overlayItem(
              id: 'unlabelled',
              rect: _storedRect(left: 30, top: 10, width: 10, height: 10),
              semanticLabel: null,
            ),
            _overlayItem(
              id: 'empty-label',
              rect: _storedRect(left: 40, top: 10, width: 10, height: 10),
              semanticLabel: '',
            ),
            _overlayItem(
              id: 'outside',
              rect: _storedRect(left: 150, top: 150, width: 10, height: 10),
              semanticLabel: 'Außerhalb',
            ),
            _overlayItem(
              id: 'second',
              rect: _storedRect(left: 20, top: 40, width: 25, height: 25),
              semanticLabel: 'Straße & Nr. 7',
            ),
          ],
        );

        final List<CustomPainterSemantics> semantics = painter.semanticsBuilder(
          const Size(100, 100),
        );

        expect(semantics, hasLength(2));
        expect(semantics[0].properties.label, 'Name');
        expect(semantics[0].rect, const Rect.fromLTWH(10, 10, 20, 20));
        expect(semantics[0].properties.textDirection, TextDirection.ltr);
        expect(semantics[1].properties.label, 'Straße & Nr. 7');
        expect(semantics[1].rect, const Rect.fromLTWH(20, 40, 25, 25));
        expect(semantics[1].properties.textDirection, TextDirection.ltr);
      },
    );

    test('emits nothing for a zero-area page', () {
      final FieldOverlayPainter painter = _painter(
        items: <FieldOverlayItem>[_overlayItem(semanticLabel: 'Name')],
        pageRect: const Rect.fromLTWH(0, 0, 0, 0),
      );

      expect(painter.semanticsBuilder(const Size(100, 100)), isEmpty);
    });
  });

  group('FieldOverlay widget', () {
    testWidgets('is pointer-inert, paint-only, and exception-free', (
      WidgetTester tester,
    ) async {
      await _pumpOverlay(tester, items: const <FieldOverlayItem>[]);
      expect(tester.takeException(), isNull);

      await _pumpOverlay(
        tester,
        items: <FieldOverlayItem>[
          _overlayItem(selected: true, conflicting: true),
        ],
      );
      expect(tester.takeException(), isNull);

      final Finder fieldOverlay = find.byType(FieldOverlay);
      final Finder ignoreFinder = find.descendant(
        of: fieldOverlay,
        matching: find.byType(IgnorePointer),
      );
      expect(ignoreFinder, findsOneWidget);
      final IgnorePointer ignorePointer = tester.widget<IgnorePointer>(
        ignoreFinder,
      );
      expect(ignorePointer.ignoring, isTrue);
      expect(ignorePointer.child, isA<CustomPaint>());

      final Finder customPaintFinder = find.descendant(
        of: fieldOverlay,
        matching: find.byType(CustomPaint),
      );
      expect(customPaintFinder, findsOneWidget);
      final CustomPaint customPaint = tester.widget<CustomPaint>(
        customPaintFinder,
      );
      expect(customPaint.painter, isA<FieldOverlayPainter>());
      expect(customPaint.child, isA<SizedBox>());
      expect(customPaint.child, isNot(isA<Text>()));

      expect(
        find.descendant(of: fieldOverlay, matching: find.byType(Text)),
        findsNothing,
      );
    });

    testWidgets('paints an empty overlay at 200% text scale', (
      WidgetTester tester,
    ) async {
      await _pumpOverlay(tester, items: const <FieldOverlayItem>[]);

      expect(tester.takeException(), isNull);
      expect(find.byType(FieldOverlay), findsOneWidget);
      expect(find.text('SIMULATED'), findsNothing);
    });
  });
}

Future<void> _pumpOverlay(
  WidgetTester tester, {
  required List<FieldOverlayItem> items,
}) async {
  tester.view.physicalSize = const Size(400, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: const TextScaler.linear(2)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 400,
              child: FieldOverlay(
                items: items,
                pageSize: const Size(300, 400),
                pageRect: const Rect.fromLTWH(0, 0, 300, 400),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _RecordedInvocation {
  const _RecordedInvocation(this.memberName, this.positionalArguments);

  final Symbol memberName;
  final List<dynamic> positionalArguments;
}

final class _RecordingCanvas implements Canvas {
  final List<_RecordedInvocation> calls = <_RecordedInvocation>[];

  @override
  void noSuchMethod(Invocation invocation) {
    calls.add(
      _RecordedInvocation(
        invocation.memberName,
        invocation.positionalArguments,
      ),
    );
  }
}
