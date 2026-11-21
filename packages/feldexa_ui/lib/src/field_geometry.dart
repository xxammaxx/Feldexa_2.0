// Touch move/resize geometry for the selected confirmed field (T071B).
//
// This is the stateful gesture layer that `contracts/editor-interactions.md`
// §4 requires: a body drag moves the field, a corner or edge drag resizes it
// from the opposite anchor, and the pointer delta is divided by the current
// view scale exactly once. Everything here is presentation-only geometry: the
// stored model rectangle is never changed, no command is committed per frame,
// and nothing is persisted. The caller owns the T066 `moveField`/`resizeField`
// commit at gesture end and the T067 `CommandHistory` entry.
//
// Coordinate spaces (unchanged from T069/T077):
//   * view space — logical pixels inside the page viewport;
//   * page-display space — PDF points from the page's display top-left, the
//     same space as `core.ConfirmedField.rect` and `core.PageGeometry.displayBox`.
//
// The normative view mapping is reused from [layoutFieldOverlay]; this library
// only converts deltas (`mapViewDeltaToDisplay`) and rectangles
// (`moveFieldRect`, `resizeFieldRect`, [clampFieldRectToPage]).
//
// Contract sources: `contracts/editor-interactions.md` §4 and §11,
// `contracts/coordinates-and-geometry.md` §3 and §6, FR-023/FR-024/FR-094,
// data-model §3.4.

import 'dart:math' as math;

import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/material.dart';

import 'field_overlay.dart';
import 'field_selection.dart';

/// Minimum committed field size in page-display points (§4: 4 × 4 pt).
const double fieldGeometryMinSize = 4;

/// Minimum corner and edge hit region in view logical pixels (§4: 24 dp).
///
/// This is hit slop only: it never widens the stored rectangle, and the 6 px
/// visual handles painted by [FieldSelectionPainter] stay pointer-inert.
const double fieldGeometryHandleHitSize = 24;

/// One pointer-inert geometry target on the selected field.
///
/// The eight handles resize from the opposite edge or corner; [body] moves the
/// whole field. Resizing is corner/edge based with a free aspect ratio (§4).
enum FieldGeometryHandle {
  /// The field body: a drag moves the whole rectangle.
  body,

  /// Upper-left corner: moves the left and top edges.
  topLeft,

  /// Upper edge: moves the top edge.
  topCenter,

  /// Upper-right corner: moves the right and top edges.
  topRight,

  /// Left edge: moves the left edge.
  centerLeft,

  /// Right edge: moves the right edge.
  centerRight,

  /// Lower-left corner: moves the left and bottom edges.
  bottomLeft,

  /// Lower edge: moves the bottom edge.
  bottomCenter,

  /// Lower-right corner: moves the right and bottom edges.
  bottomRight;

  /// Whether this target is the field body (a move rather than a resize).
  bool get isBody => this == FieldGeometryHandle.body;

  /// Whether a drag on this target changes the left edge.
  bool get movesLeftEdge =>
      this == FieldGeometryHandle.topLeft ||
      this == FieldGeometryHandle.centerLeft ||
      this == FieldGeometryHandle.bottomLeft;

  /// Whether a drag on this target changes the top edge.
  bool get movesTopEdge =>
      this == FieldGeometryHandle.topLeft ||
      this == FieldGeometryHandle.topCenter ||
      this == FieldGeometryHandle.topRight;

  /// Whether a drag on this target changes the right edge.
  bool get movesRightEdge =>
      this == FieldGeometryHandle.topRight ||
      this == FieldGeometryHandle.centerRight ||
      this == FieldGeometryHandle.bottomRight;

  /// Whether a drag on this target changes the bottom edge.
  bool get movesBottomEdge =>
      this == FieldGeometryHandle.bottomLeft ||
      this == FieldGeometryHandle.bottomCenter ||
      this == FieldGeometryHandle.bottomRight;
}

/// The kind of geometry change one gesture produced.
enum FieldGeometryEditKind {
  /// The field kept its size and changed its position.
  move,

  /// The field kept its opposite anchor and changed its size.
  resize,
}

/// Returns the geometry target under [viewPoint] for [viewRect], or null.
///
/// [viewRect] is the selected field's view-space rectangle as resolved by
/// [layoutFieldOverlay]; [hitSize] is the side of a corner region and the
/// thickness of an edge region, so every handle region is at least
/// [fieldGeometryHandleHitSize] (24 dp) in view space (§4). Corner regions are
/// tested before edge regions, and edge regions before [FieldGeometryHandle.body],
/// so a small field still resolves to a handle rather than to the body. The
/// body is only tested when [includeBody] is true.
///
/// Returns null for a non-finite or empty [viewRect], a non-finite
/// [viewPoint], a non-finite or non-positive [hitSize], and for a point outside
/// every region. The function is pure: it mutates nothing.
FieldGeometryHandle? hitTestFieldGeometry({
  required Rect viewRect,
  required Offset viewPoint,
  double hitSize = fieldGeometryHandleHitSize,
  bool includeBody = true,
}) {
  if (!hitSize.isFinite || hitSize <= 0) {
    throw ArgumentError.value(
      hitSize,
      'hitSize',
      'must be finite and positive',
    );
  }
  if (!_isFiniteRect(viewRect) ||
      viewRect.width <= 0 ||
      viewRect.height <= 0 ||
      !viewPoint.dx.isFinite ||
      !viewPoint.dy.isFinite) {
    return null;
  }
  final double half = hitSize / 2;
  Rect corner(Offset center) =>
      Rect.fromCenter(center: center, width: hitSize, height: hitSize);
  if (corner(viewRect.topLeft).contains(viewPoint)) {
    return FieldGeometryHandle.topLeft;
  }
  if (corner(viewRect.topRight).contains(viewPoint)) {
    return FieldGeometryHandle.topRight;
  }
  if (corner(viewRect.bottomLeft).contains(viewPoint)) {
    return FieldGeometryHandle.bottomLeft;
  }
  if (corner(viewRect.bottomRight).contains(viewPoint)) {
    return FieldGeometryHandle.bottomRight;
  }
  if (Rect.fromLTRB(
    viewRect.left,
    viewRect.top - half,
    viewRect.right,
    viewRect.top + half,
  ).contains(viewPoint)) {
    return FieldGeometryHandle.topCenter;
  }
  if (Rect.fromLTRB(
    viewRect.left,
    viewRect.bottom - half,
    viewRect.right,
    viewRect.bottom + half,
  ).contains(viewPoint)) {
    return FieldGeometryHandle.bottomCenter;
  }
  if (Rect.fromLTRB(
    viewRect.left - half,
    viewRect.top,
    viewRect.left + half,
    viewRect.bottom,
  ).contains(viewPoint)) {
    return FieldGeometryHandle.centerLeft;
  }
  if (Rect.fromLTRB(
    viewRect.right - half,
    viewRect.top,
    viewRect.right + half,
    viewRect.bottom,
  ).contains(viewPoint)) {
    return FieldGeometryHandle.centerRight;
  }
  if (includeBody && viewRect.contains(viewPoint)) {
    return FieldGeometryHandle.body;
  }
  return null;
}

/// Divides a view-space drag delta by the current view [scale] exactly once.
///
/// [scale] is view logical pixels per page-display point, so the result is a
/// page-display delta in points. The gesture start is mapped once by the
/// caller; only the delta passes through here, which keeps a pan or zoom that
/// happens during the gesture from being folded into the geometry twice (§4).
///
/// Throws [ArgumentError] for a non-finite [viewDelta], or a [scale] that is
/// not finite and strictly positive.
Offset mapViewDeltaToDisplay({
  required Offset viewDelta,
  required double scale,
}) {
  if (!viewDelta.dx.isFinite || !viewDelta.dy.isFinite) {
    throw ArgumentError.value(viewDelta, 'viewDelta', 'must be finite');
  }
  if (!scale.isFinite || scale <= 0) {
    throw ArgumentError.value(scale, 'scale', 'must be finite and positive');
  }
  final Offset display = Offset(viewDelta.dx / scale, viewDelta.dy / scale);
  if (!display.dx.isFinite || !display.dy.isFinite) {
    throw ArgumentError.value(viewDelta, 'viewDelta', 'maps to a finite delta');
  }
  return display;
}

/// Keeps [rect] inside [pageBox] without changing its size.
///
/// A rectangle that already fits is translated by the smallest offset that
/// puts it back inside; a rectangle larger than the page is shrunk to the page
/// only as a defensive fallback, which cannot happen for a stored field
/// because T066 rejects out-of-page geometry.
///
/// Throws [ArgumentError] for non-finite input.
Rect clampFieldRectToPage(Rect rect, Rect pageBox) {
  _requireFiniteRect(rect, 'rect');
  _requireFiniteRect(pageBox, 'pageBox');
  final double width = math.min(rect.width, pageBox.width);
  final double height = math.min(rect.height, pageBox.height);
  double left = rect.left;
  double top = rect.top;
  if (left + width > pageBox.right) {
    left = pageBox.right - width;
  }
  if (left < pageBox.left) {
    left = pageBox.left;
  }
  if (top + height > pageBox.bottom) {
    top = pageBox.bottom - height;
  }
  if (top < pageBox.top) {
    top = pageBox.top;
  }
  return Rect.fromLTWH(left, top, width, height);
}

/// Moves [startRect] by [displayDelta] and clamps the result to [pageBox].
///
/// The size is preserved exactly, so a body drag never resizes the field. The
/// clamp uses the smallest translation back onto the page, which keeps the
/// pointer-to-field relationship intact at a page edge (§4).
Rect moveFieldRect({
  required Rect startRect,
  required Offset displayDelta,
  required Rect pageBox,
}) {
  if (!displayDelta.dx.isFinite || !displayDelta.dy.isFinite) {
    throw ArgumentError.value(displayDelta, 'displayDelta', 'must be finite');
  }
  return clampFieldRectToPage(startRect.shift(displayDelta), pageBox);
}

/// Resizes [startRect] by dragging [handle] with [displayDelta].
///
/// The opposite edge or corner is the fixed anchor: only the edges selected by
/// [handle] move, so a corner drag keeps the diagonally opposite corner
/// exactly in place and the aspect ratio stays free (§4). Each moved edge is
/// clamped to [pageBox]; [minSize] (`4` pt by default) is the minimum width and
/// height, enforced against the anchor so a drag past the anchor stops at
/// 4 × 4 pt instead of inverting the rectangle.
///
/// A [FieldGeometryHandle.body] handle is the move rule and delegates to
/// [moveFieldRect]. Throws [ArgumentError] for non-finite input or a
/// non-finite/negative [minSize].
Rect resizeFieldRect({
  required Rect startRect,
  required FieldGeometryHandle handle,
  required Offset displayDelta,
  required Rect pageBox,
  double minSize = fieldGeometryMinSize,
}) {
  if (!displayDelta.dx.isFinite || !displayDelta.dy.isFinite) {
    throw ArgumentError.value(displayDelta, 'displayDelta', 'must be finite');
  }
  if (!minSize.isFinite || minSize < 0) {
    throw ArgumentError.value(minSize, 'minSize', 'must be finite and >= 0');
  }
  if (handle.isBody) {
    return moveFieldRect(
      startRect: startRect,
      displayDelta: displayDelta,
      pageBox: pageBox,
    );
  }
  _requireFiniteRect(startRect, 'startRect');
  _requireFiniteRect(pageBox, 'pageBox');

  double left = _movedEdge(
    startRect.left,
    moves: handle.movesLeftEdge,
    delta: displayDelta.dx,
  );
  double top = _movedEdge(
    startRect.top,
    moves: handle.movesTopEdge,
    delta: displayDelta.dy,
  );
  double right = _movedEdge(
    startRect.right,
    moves: handle.movesRightEdge,
    delta: displayDelta.dx,
  );
  double bottom = _movedEdge(
    startRect.bottom,
    moves: handle.movesBottomEdge,
    delta: displayDelta.dy,
  );

  // Clamp each moved edge to the page before enforcing the minimum size.
  if (handle.movesLeftEdge) {
    left = math.max(left, pageBox.left);
  }
  if (handle.movesRightEdge) {
    right = math.min(right, pageBox.right);
  }
  if (handle.movesTopEdge) {
    top = math.max(top, pageBox.top);
  }
  if (handle.movesBottomEdge) {
    bottom = math.min(bottom, pageBox.bottom);
  }

  // Enforce the minimum size against the fixed anchor.
  if (handle.movesLeftEdge) {
    left = math.min(left, math.max(right - minSize, pageBox.left));
  }
  if (handle.movesRightEdge) {
    right = math.max(right, math.min(left + minSize, pageBox.right));
  }
  if (handle.movesTopEdge) {
    top = math.min(top, math.max(bottom - minSize, pageBox.top));
  }
  if (handle.movesBottomEdge) {
    bottom = math.max(bottom, math.min(top + minSize, pageBox.bottom));
  }

  return Rect.fromLTRB(left, top, right, bottom);
}

/// One finished geometry gesture: the field, the kind, and both rectangles.
///
/// [rect] is the previewed page-display rectangle to commit through T066;
/// [previousRect] is the stored rectangle the gesture started from, so the
/// caller can record an exact T067 `before` snapshot.
@immutable
final class FieldGeometryChange {
  /// Creates a geometry receipt.
  const FieldGeometryChange({
    required this.fieldId,
    required this.kind,
    required this.rect,
    required this.previousRect,
  });

  /// The confirmed field the gesture edited.
  final String fieldId;

  /// Whether the gesture moved or resized the field.
  final FieldGeometryEditKind kind;

  /// The previewed page-display rectangle.
  final Rect rect;

  /// The unchanged stored rectangle the gesture started from.
  final Rect previousRect;

  @override
  bool operator ==(Object other) {
    return other is FieldGeometryChange &&
        other.fieldId == fieldId &&
        other.kind == kind &&
        other.rect == rect &&
        other.previousRect == previousRect;
  }

  @override
  int get hashCode => Object.hash(fieldId, kind, rect, previousRect);

  @override
  String toString() =>
      'FieldGeometryChange(kind: ${kind.name}, changed: ${rect != previousRect})';
}

/// One in-flight move or resize gesture on the selected field.
///
/// The gesture is opened once at pointer start with the stored rectangle, the
/// page display box, and the current view scale. Every [update] maps the
/// cumulative view delta by [mapViewDeltaToDisplay] and recomputes the preview
/// from the *start* rectangle, so no per-frame error accumulates and no
/// command, store write, or model change happens before [commit].
///
/// [commit] returns one [FieldGeometryChange], or null when the gesture ended on
/// an unchanged rectangle (a tap-like drag), so exactly zero or one T066
/// command is issued per gesture. [cancel] discards the preview.
final class FieldGeometrySession {
  /// Opens a session for [fieldId] on [handle].
  ///
  /// [startRect] is the stored page-display rectangle, [pageBox] the page's
  /// display box used for clamping, and [scale] the current view scale in
  /// logical pixels per point (never zero).
  FieldGeometrySession.start({
    required this.fieldId,
    required this.handle,
    required Rect startRect,
    required Rect pageBox,
    required double scale,
    double minSize = fieldGeometryMinSize,
  }) : _startRect = startRect,
       _previewRect = startRect,
       pageBox = pageBox,
       scale = scale,
       minSize = minSize {
    _requireFiniteRect(startRect, 'startRect');
    _requireFiniteRect(pageBox, 'pageBox');
    if (!scale.isFinite || scale <= 0) {
      throw ArgumentError.value(scale, 'scale', 'must be finite and positive');
    }
    if (!minSize.isFinite || minSize < 0) {
      throw ArgumentError.value(minSize, 'minSize', 'must be finite and >= 0');
    }
  }

  /// The confirmed field the gesture edits.
  final String fieldId;

  /// The pointer-inert handle that opened the gesture.
  final FieldGeometryHandle handle;

  /// The page-display box of the edited field's page.
  final Rect pageBox;

  /// View logical pixels per page-display point, fixed for the gesture.
  final double scale;

  /// Minimum width and height of a resize in points.
  final double minSize;

  final Rect _startRect;
  Rect _previewRect;

  /// The stored page-display rectangle the gesture started from.
  Rect get startRect => _startRect;

  /// The previewed page-display rectangle for the current pointer position.
  Rect get previewRect => _previewRect;

  /// Whether the preview currently differs from [startRect].
  bool get hasChanged => _previewRect != _startRect;

  /// The edit kind implied by [handle].
  FieldGeometryEditKind get kind =>
      handle.isBody ? FieldGeometryEditKind.move : FieldGeometryEditKind.resize;

  /// Recomputes the preview from the cumulative [viewDelta] and returns it.
  ///
  /// [viewDelta] is measured from the gesture start in view space, so the
  /// division by [scale] happens exactly once per update and the result is
  /// always derived from [startRect].
  Rect update(Offset viewDelta) {
    final Offset displayDelta = mapViewDeltaToDisplay(
      viewDelta: viewDelta,
      scale: scale,
    );
    _previewRect = resizeFieldRect(
      startRect: _startRect,
      handle: handle,
      displayDelta: displayDelta,
      pageBox: pageBox,
      minSize: minSize,
    );
    return _previewRect;
  }

  /// Discards the preview and restores the stored rectangle.
  void cancel() {
    _previewRect = _startRect;
  }

  /// Returns the one committed change, or null when nothing changed.
  FieldGeometryChange? commit() {
    if (_previewRect == _startRect) {
      return null;
    }
    return FieldGeometryChange(
      fieldId: fieldId,
      kind: kind,
      rect: _previewRect,
      previousRect: _startRect,
    );
  }
}

/// Paints the in-gesture preview of one move or resize.
///
/// [previewRect] is a page-display rectangle; it is mapped through
/// [layoutFieldOverlay], so the preview uses the same normative view mapping as
/// the field overlay and the selection highlight. The widget is pointer-inert
/// (the gesture belongs to the page view), paints nothing when [previewRect] is
/// null or the page is unusable, and is expected to exist only while a gesture
/// is active.
class FieldGeometryPreview extends StatelessWidget {
  /// Creates a geometry preview for [previewRect] (page-display space).
  const FieldGeometryPreview({
    super.key,
    required this.previewRect,
    required this.pageSize,
    required this.pageRect,
    required this.accentColor,
  });

  /// The previewed page-display rectangle, or null when no gesture is active.
  final Rect? previewRect;

  /// Page display size in model points.
  final Size pageSize;

  /// Current page rectangle in view space.
  final Rect pageRect;

  /// Accent for the preview outline and handles.
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final Rect? rect = previewRect;
    if (rect == null) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: CustomPaint(
        painter: FieldSelectionPainter(
          items: <FieldOverlayItem>[
            FieldOverlayItem(
              id: _previewItemId,
              pageIndex: 0,
              rect: core.Rect.fromLTWH(
                rect.left,
                rect.top,
                rect.width,
                rect.height,
              ),
              provenance: FieldOverlayProvenance.user,
            ),
          ],
          selectedId: _previewItemId,
          pageSize: pageSize,
          pageRect: pageRect,
          accentColor: accentColor,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Synthetic overlay id for the preview; never a stored field id.
const String _previewItemId = 'field-geometry-preview';

/// Moves one edge by [delta] when [moves] is true; otherwise keeps it fixed.
double _movedEdge(double value, {required bool moves, required double delta}) {
  return moves ? value + delta : value;
}

void _requireFiniteRect(Rect rect, String name) {
  if (!_isFiniteRect(rect)) {
    throw ArgumentError.value(rect, name, 'must be finite');
  }
}

bool _isFiniteRect(Rect rect) {
  return rect.left.isFinite &&
      rect.top.isFinite &&
      rect.right.isFinite &&
      rect.bottom.isFinite;
}
