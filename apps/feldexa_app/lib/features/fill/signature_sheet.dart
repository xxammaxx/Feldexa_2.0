// T083 full-screen signature sheet for the filling surface.
//
// Owner: `apps/feldexa_app/lib/features/fill/signature_sheet.dart` (T083).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/contracts/editor-interactions.md`
//     section 5 (a signature field opens a full-screen signature sheet, drawn
//     with finger, stylus, or mouse, with clear and undo; the ink belongs only
//     to the current document) and section 11 (accessible labels, 48 x 48 dp
//     primary controls, and 200 % text scale reflows without clipping);
//   * `specs/001-scanned-form-workflow/spec.md` FR-036 (a handwritten
//     signature belongs only to the current document), FR-040 (entered values
//     remain editable before export), and FR-094 (state is readable text, not
//     colour or an icon alone);
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// What this file is
// -----------------
// A presentation-only full-screen sheet. It captures in-memory ink strokes
// and returns an immutable snapshot through `onApply`. It never writes a
// file, store, database, preference, or network, and it holds no document,
// field, path, editor, or byte-buffer handle. Binding the returned draft to
// the current document and field is the caller's responsibility.
//
// Gesture model
// -------------
// A pan starts a stroke at the canvas-local down point, appends clamped
// canvas-local points while the pointer moves, and finishes on pan end or pan
// cancel. A tap or a dot therefore becomes exactly one one-point stroke. A
// small drag stays in the same single stroke. Undo removes the last stroke;
// clear removes them all. A new instance always starts empty because all ink
// lives in this widget's state and no static or global ink exists.
//
// User-visible text
// -----------------
// Every visible label and tooltip comes from the constructor. This file
// imports no localization or generated ARB module and composes no literal
// user-facing sentence, so the application ARB remains the single source of
// German UI text.
//
// Evidence
// --------
// This widget is covered by host-VM widget tests only. It makes no Android,
// device, stylus, screen-reader, or visual claim, and its tests produce no
// evidence class above NONE.

import 'package:flutter/material.dart';

/// Stable key for the cancel action in the app bar.
const ValueKey<String> signatureSheetCancelKey = ValueKey<String>(
  'signature-sheet-cancel',
);

/// Stable key for the undo action in the app bar.
const ValueKey<String> signatureSheetUndoKey = ValueKey<String>(
  'signature-sheet-undo',
);

/// Stable key for the clear action in the app bar.
const ValueKey<String> signatureSheetClearKey = ValueKey<String>(
  'signature-sheet-clear',
);

/// Stable key for the drawing canvas.
const ValueKey<String> signatureSheetCanvasKey = ValueKey<String>(
  'signature-sheet-canvas',
);

/// Stable key for the apply action at the bottom of the sheet.
const ValueKey<String> signatureSheetApplyKey = ValueKey<String>(
  'signature-sheet-apply',
);

/// Width of a painted ink line and diameter of a painted one-point dot.
const double _inkStrokeWidth = 2.5;

/// One uninterrupted in-memory ink stroke on the signature canvas.
///
/// Points are logical pixels local to the canvas. The constructor copies the
/// supplied list into an unmodifiable list, so the caller cannot mutate the
/// captured ink afterwards and later changes to the caller's list never alter
/// this stroke.
class SignatureStroke {
  /// Creates an immutable stroke from canvas-local [points].
  SignatureStroke({required List<Offset> points})
    : points = List<Offset>.unmodifiable(points);

  /// Canvas-local points in drawing order.
  ///
  /// The list is unmodifiable; a one-point list represents a tap or dot.
  final List<Offset> points;
}

/// Immutable in-memory ink returned to the caller.
///
/// A draft carries only the captured [strokes] and the canvas [canvasSize]
/// that produced their coordinates. It has no document id, field id, path,
/// byte buffer, or persistence handle. The constructor copies the supplied
/// stroke list into an unmodifiable list, so later drawing, undo, or clear in
/// the sheet cannot change a delivered snapshot.
class SignatureDraft {
  /// Creates an immutable snapshot of the current sheet ink.
  SignatureDraft({
    required List<SignatureStroke> strokes,
    required this.canvasSize,
  }) : strokes = List<SignatureStroke>.unmodifiable(strokes);

  /// Captured strokes in drawing order.
  ///
  /// The list is unmodifiable.
  final List<SignatureStroke> strokes;

  /// Size of the drawing canvas when the draft was captured.
  final Size canvasSize;

  /// Whether no ink has been captured.
  bool get isEmpty => strokes.isEmpty;
}

/// A caller-labelled, presentation-only full-screen signature sheet.
///
/// The root is a full-screen [Scaffold] with the caller [title], a cancel
/// leading action, undo and clear actions, a canvas that fills the body, and a
/// bottom apply action. The sheet never pushes, pops, or otherwise navigates;
/// the caller owns routing and decides what to do with the returned draft.
///
/// [undoLabel], [clearLabel], and [cancelLabel] are the tooltips and
/// accessible labels of their icon actions. [title] and [applyLabel] are
/// rendered as caller text. Undo and clear are disabled while no ink exists.
/// Apply is available even when empty and reports an empty draft.
class SignatureSheet extends StatefulWidget {
  /// Creates a signature sheet with caller-supplied labels.
  const SignatureSheet({
    required this.title,
    required this.clearLabel,
    required this.undoLabel,
    required this.applyLabel,
    required this.cancelLabel,
    required this.onApply,
    required this.onCancel,
    super.key,
  });

  /// Caller-supplied title shown in the app bar.
  final String title;

  /// Caller-supplied tooltip and accessible label for the clear action.
  final String clearLabel;

  /// Caller-supplied tooltip and accessible label for the undo action.
  final String undoLabel;

  /// Caller-supplied text for the apply action.
  final String applyLabel;

  /// Caller-supplied tooltip and accessible label for the cancel action.
  final String cancelLabel;

  /// Called exactly once per apply tap with an immutable ink snapshot.
  final ValueChanged<SignatureDraft> onApply;

  /// Called exactly once per cancel tap. No draft is reported.
  final VoidCallback onCancel;

  @override
  State<SignatureSheet> createState() => _SignatureSheetState();
}

class _SignatureSheetState extends State<SignatureSheet> {
  final List<SignatureStroke> _strokes = <SignatureStroke>[];

  /// Points of the stroke that is currently being drawn, if any.
  ///
  /// The list is internal and mutable while the pointer moves; it is copied
  /// into an immutable [SignatureStroke] when the gesture finishes.
  List<Offset>? _activePoints;

  /// Actual size of the laid-out canvas, captured for the returned draft.
  Size _canvasSize = Size.zero;

  bool get _hasInk => _strokes.isNotEmpty || _activePoints != null;

  Offset _clampToCanvas(Offset point) {
    return Offset(
      point.dx.clamp(0.0, _canvasSize.width).toDouble(),
      point.dy.clamp(0.0, _canvasSize.height).toDouble(),
    );
  }

  void _beginStroke(Offset localPosition) {
    if (_activePoints != null) {
      return;
    }
    setState(() {
      _activePoints = <Offset>[_clampToCanvas(localPosition)];
    });
  }

  void _appendPoint(Offset localPosition) {
    final List<Offset>? activePoints = _activePoints;
    if (activePoints == null) {
      return;
    }
    setState(() {
      activePoints.add(_clampToCanvas(localPosition));
    });
  }

  void _finishStroke() {
    final List<Offset>? activePoints = _activePoints;
    if (activePoints == null) {
      return;
    }
    setState(() {
      _strokes.add(SignatureStroke(points: activePoints));
      _activePoints = null;
    });
  }

  void _handleUndo() {
    if (_strokes.isEmpty) {
      return;
    }
    setState(() {
      _strokes.removeLast();
    });
  }

  void _handleClear() {
    if (!_hasInk) {
      return;
    }
    setState(() {
      _strokes.clear();
      _activePoints = null;
    });
  }

  List<SignatureStroke> _currentStrokes() {
    final List<SignatureStroke> strokes = List<SignatureStroke>.of(_strokes);
    final List<Offset>? activePoints = _activePoints;
    if (activePoints != null) {
      strokes.add(SignatureStroke(points: activePoints));
    }
    return strokes;
  }

  void _handleApply() {
    widget.onApply(
      SignatureDraft(strokes: _currentStrokes(), canvasSize: _canvasSize),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasInk = _hasInk;
    final double textScale = MediaQuery.textScalerOf(context).scale(1);
    final double toolbarHeight = textScale > 1
        ? kToolbarHeight * textScale
        : kToolbarHeight;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: toolbarHeight,
        title: Text(widget.title),
        leading: IconButton(
          key: signatureSheetCancelKey,
          tooltip: widget.cancelLabel,
          onPressed: widget.onCancel,
          icon: const Icon(Icons.close),
        ),
        actions: <Widget>[
          IconButton(
            key: signatureSheetUndoKey,
            tooltip: widget.undoLabel,
            onPressed: hasInk ? _handleUndo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            key: signatureSheetClearKey,
            tooltip: widget.clearLabel,
            onPressed: hasInk ? _handleClear : null,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Size canvasSize = constraints.biggest;
          _canvasSize = canvasSize;
          return GestureDetector(
            key: signatureSheetCanvasKey,
            behavior: HitTestBehavior.opaque,
            onPanDown: (DragDownDetails details) =>
                _beginStroke(details.localPosition),
            onPanStart: (DragStartDetails details) =>
                _beginStroke(details.localPosition),
            onPanUpdate: (DragUpdateDetails details) =>
                _appendPoint(details.localPosition),
            onPanEnd: (DragEndDetails details) => _finishStroke(),
            onPanCancel: _finishStroke,
            child: CustomPaint(
              size: canvasSize,
              painter: _SignaturePainter(
                strokes: _currentStrokes(),
                color: theme.colorScheme.onSurface,
              ),
              child: const SizedBox.expand(),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton(
          key: signatureSheetApplyKey,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _handleApply,
          child: Text(widget.applyLabel, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// Paints the captured ink strokes.
class _SignaturePainter extends CustomPainter {
  _SignaturePainter({required this.strokes, required this.color});

  final List<SignatureStroke> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _inkStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (final SignatureStroke stroke in strokes) {
      final List<Offset> points = stroke.points;
      if (points.isEmpty) {
        continue;
      }
      if (points.length == 1) {
        canvas.drawCircle(points.single, _inkStrokeWidth / 2, dotPaint);
        continue;
      }
      final Path path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final Offset point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter oldDelegate) {
    return oldDelegate.strokes != strokes || oldDelegate.color != color;
  }
}
