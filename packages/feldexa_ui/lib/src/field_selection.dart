// Field selection state, hit testing, and highlight (T077).
//
// Selection is transient view state only: selecting a field never mutates the
// model, stored geometry, or provenance. Stored page-display rectangles are
// mapped to view space through `layoutFieldOverlay`, so hit testing and
// painting use the same normative mapping as the T069 overlay.
//
// Contract sources: `contracts/editor-interactions.md` §2, §4, and §11,
// FR-031/FR-034/FR-094, and SC-017.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'field_overlay.dart';

/// Owns the currently selected field id for one editor surface.
///
/// This is transient view state only. Selecting or clearing never mutates a
/// field, its geometry, or the document model; a controller is created,
/// listened to, and disposed by the composing widget (T071).
class FieldSelectionController extends ChangeNotifier {
  String? _selectedId;

  /// The selected field id, or null when nothing is selected.
  String? get selectedId => _selectedId;

  /// Whether [id] is the currently selected field.
  bool isSelected(String id) => _selectedId == id;

  /// Selects [id], or clears the selection when [id] is null.
  ///
  /// Notifies listeners only when the value actually changes, so selecting the
  /// already-selected field does not schedule a rebuild.
  void select(String? id) {
    if (_selectedId == id) {
      return;
    }
    _selectedId = id;
    notifyListeners();
  }

  /// Clears the selection; equivalent to `select(null)`.
  void clear() => select(null);

  /// Clears the selection when its field is no longer present.
  ///
  /// Builds a `Set<String>` from [presentIds] once. A present selection is
  /// kept, an absent one is cleared, and listeners are notified only when the
  /// selection actually changes. With nothing selected this is a no-op. This
  /// reconciles view state only and never writes to the model.
  void reconcile(Iterable<String> presentIds) {
    final String? selectedId = _selectedId;
    if (selectedId == null) {
      return;
    }
    final Set<String> present = presentIds.toSet();
    if (present.contains(selectedId)) {
      return;
    }
    _selectedId = null;
    notifyListeners();
  }
}

/// Returns the topmost visible field under [viewPoint], or null on a miss.
///
/// Items are mapped to view space with [layoutFieldOverlay] using the same
/// [pageSize] and [pageRect] as the overlay painter; the mapping formula is
/// never reimplemented here. Only layouts with a non-empty `clippedRect` are
/// candidates, and only the clipped rectangle is tested, so a partly clipped
/// field is hit only where it is actually visible on the page.
///
/// Paint order decides overlaps: later items are on top, so the last matching
/// item in input order wins. Containment is half-open (`Rect.contains`), which
/// means the right and bottom page/field edges are outside; a tap exactly on
/// those edges is a miss.
///
/// Returns null when there are no items, [pageSize] is non-positive or
/// non-finite, [pageRect] is empty or non-finite, or [viewPoint] is outside the
/// page. The function is pure: it mutates no item, `core.Rect`, or list, and
/// performs no controller or model writes.
FieldOverlayItem? hitTestFieldSelection({
  required Iterable<FieldOverlayItem> items,
  required Size pageSize,
  required Rect pageRect,
  required Offset viewPoint,
}) {
  if (!_isUsablePage(pageSize: pageSize, pageRect: pageRect)) {
    return null;
  }
  if (!pageRect.contains(viewPoint)) {
    return null;
  }
  final List<FieldOverlayLayout> layouts = layoutFieldOverlay(
    items: items,
    pageSize: pageSize,
    pageRect: pageRect,
  );
  FieldOverlayItem? topmost;
  for (final FieldOverlayLayout layout in layouts) {
    if (layout.isVisible && layout.clippedRect.contains(viewPoint)) {
      topmost = layout.item;
    }
  }
  return topmost;
}

/// Paints the selected field's accent outline and four corner handles.
///
/// The painter is presentation-only and resolves the selected item through
/// [layoutFieldOverlay], then paints only that item's visible `clippedRect`.
/// The 2 logical-pixel accent outline follows the clipped rectangle (not the
/// unclipped view rectangle), and the four filled 6 × 6 handles are centered
/// on its corners and clamped fully inside [pageRect] so a clipped selection
/// keeps every handle on the page. It paints no provenance outline, conflict
/// marker, dashes, or text; T069 owns provenance painting.
///
/// The painter no-ops when [selectedId] is null, no item matches it, the
/// selected item is not visible, [items] is empty, [pageSize] is non-positive
/// or non-finite, or [pageRect] is empty or non-finite.
class FieldSelectionPainter extends CustomPainter {
  /// Creates a painter and copies [items] to an unmodifiable list.
  FieldSelectionPainter({
    required Iterable<FieldOverlayItem> items,
    required this.selectedId,
    required this.pageSize,
    required this.pageRect,
    required this.accentColor,
    super.repaint,
  }) : items = List<FieldOverlayItem>.unmodifiable(items);

  /// Items in paint order (later items on top).
  final List<FieldOverlayItem> items;

  /// The selected field id, or null when nothing is selected.
  final String? selectedId;

  /// Page display size in model points.
  final Size pageSize;

  /// Current page rectangle in view space.
  final Rect pageRect;

  /// Accent for the selected outline and the four corner handles.
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final FieldOverlayItem? selected = _findById(items, selectedId);
    if (selected == null ||
        items.isEmpty ||
        !_isUsablePage(pageSize: pageSize, pageRect: pageRect)) {
      return;
    }
    final FieldOverlayLayout layout = layoutFieldOverlay(
      items: <FieldOverlayItem>[selected],
      pageSize: pageSize,
      pageRect: pageRect,
    ).single;
    if (!layout.isVisible) {
      return;
    }
    canvas.save();
    try {
      canvas.clipRect(pageRect);
      _paintSelection(canvas, layout.clippedRect);
    } finally {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant FieldSelectionPainter oldDelegate) {
    return selectedId != oldDelegate.selectedId ||
        accentColor != oldDelegate.accentColor ||
        pageSize != oldDelegate.pageSize ||
        pageRect != oldDelegate.pageRect ||
        !listEquals(items, oldDelegate.items);
  }

  void _paintSelection(Canvas canvas, Rect rect) {
    final Paint outline = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(rect, outline);

    final Paint handle = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(_handleRect(rect.topLeft), handle);
    canvas.drawRect(_handleRect(rect.topRight), handle);
    canvas.drawRect(_handleRect(rect.bottomLeft), handle);
    canvas.drawRect(_handleRect(rect.bottomRight), handle);
  }

  /// Centers a 6 × 6 handle on [corner] and clamps it fully inside the page.
  ///
  /// A page narrower or shorter than one handle cannot contain it; the handle
  /// is then anchored to the page's left/top edge instead of overshooting it.
  Rect _handleRect(Offset corner) {
    return Rect.fromLTWH(
      _clampHandle(
        corner.dx - _handleSize / 2,
        pageRect.left,
        pageRect.right - _handleSize,
      ),
      _clampHandle(
        corner.dy - _handleSize / 2,
        pageRect.top,
        pageRect.bottom - _handleSize,
      ),
      _handleSize,
      _handleSize,
    );
  }

  static double _clampHandle(double value, double lower, double upper) {
    if (upper < lower) {
      return lower;
    }
    return value.clamp(lower, upper).toDouble();
  }
}

/// Rebuilds a pointer-inert highlight for the controller's selected field.
///
/// The widget listens to [controller], looks the selected item up by
/// [FieldSelectionController.selectedId], and paints only that item through
/// [FieldSelectionPainter]. A missing, deleted, or invisible selection paints
/// nothing and does not throw. The accent comes from
/// `Theme.of(context).colorScheme.primary`, consistent with [FieldOverlay].
///
/// When a visible selection exists, exactly one widget-level [Semantics] node
/// carries `selected: true`, [semanticLabel] verbatim, and
/// `TextDirection.ltr`. No painter semantics are added, so a screen reader
/// never announces the same selection twice. [semanticLabel] is caller-owned:
/// this package composes no user-facing text and imports no ARB. T069 owns
/// provenance painting; T071 composes this highlight with pan/zoom.
class FieldSelectionHighlight extends StatelessWidget {
  /// Creates a selection highlight.
  const FieldSelectionHighlight({
    super.key,
    required this.controller,
    required this.items,
    required this.pageSize,
    required this.pageRect,
    this.semanticLabel,
  });

  /// Selection source of truth.
  final FieldSelectionController controller;

  /// Items in paint order (later items on top).
  final Iterable<FieldOverlayItem> items;

  /// Page display size in model points.
  final Size pageSize;

  /// Current page rectangle in view space.
  final Rect pageRect;

  /// Caller-supplied label for the selected-field semantic node.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) {
        final FieldOverlayItem? selected = _findById(
          items,
          controller.selectedId,
        );
        final bool visible =
            selected != null &&
            _hasVisibleLayout(
              item: selected,
              pageSize: pageSize,
              pageRect: pageRect,
            );
        final Widget painted = IgnorePointer(
          child: CustomPaint(
            painter: FieldSelectionPainter(
              items: selected == null
                  ? const <FieldOverlayItem>[]
                  : <FieldOverlayItem>[selected],
              selectedId: selected?.id,
              pageSize: pageSize,
              pageRect: pageRect,
              accentColor: Theme.of(context).colorScheme.primary,
            ),
            child: const SizedBox.expand(),
          ),
        );
        if (!visible) {
          return painted;
        }
        return Semantics(
          container: true,
          selected: true,
          label: semanticLabel,
          textDirection: TextDirection.ltr,
          child: painted,
        );
      },
    );
  }
}

/// Composes a pointer-inert highlight and a page-sized tap surface over a
/// caller-rendered page.
///
/// The [Stack] keeps [child] visible and interactive. The tap surface is
/// constrained to [pageRect], so pointer events outside the page pass through
/// to [child] instead of being swallowed; when [pageRect] is empty the surface
/// is omitted entirely. A tap hit-tests the page with
/// [hitTestFieldSelection], selects the resulting item (including
/// `select(null)` on a miss), then calls [onSelected] exactly once with that
/// item or null.
///
/// This widget never mutates the model, stored geometry, or provenance.
/// T071 composes it with pan/zoom and owns final Android touch behavior; T069
/// owns provenance painting. No user-facing text or ARB entry is added here.
class FieldSelectionSurface extends StatelessWidget {
  /// Creates a selection surface.
  const FieldSelectionSurface({
    super.key,
    required this.controller,
    required this.items,
    required this.pageSize,
    required this.pageRect,
    this.onSelected,
    required this.child,
  });

  /// Selection source of truth.
  final FieldSelectionController controller;

  /// Items in paint order (later items on top).
  final Iterable<FieldOverlayItem> items;

  /// Page display size in model points.
  final Size pageSize;

  /// Current page rectangle in view space.
  final Rect pageRect;

  /// Called once after every tap with the selected item, or null on a miss.
  final ValueChanged<FieldOverlayItem?>? onSelected;

  /// Caller-rendered page content beneath the highlight and tap surface.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        child,
        if (!pageRect.isEmpty)
          Positioned.fromRect(
            rect: pageRect,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (TapUpDetails details) {
                final FieldOverlayItem? item = hitTestFieldSelection(
                  items: items,
                  pageSize: pageSize,
                  pageRect: pageRect,
                  viewPoint: pageRect.topLeft + details.localPosition,
                );
                controller.select(item?.id);
                onSelected?.call(item);
              },
            ),
          ),
        FieldSelectionHighlight(
          controller: controller,
          items: items,
          pageSize: pageSize,
          pageRect: pageRect,
        ),
      ],
    );
  }
}

const double _handleSize = 6;

FieldOverlayItem? _findById(Iterable<FieldOverlayItem> items, String? id) {
  if (id == null) {
    return null;
  }
  for (final FieldOverlayItem item in items) {
    if (item.id == id) {
      return item;
    }
  }
  return null;
}

bool _hasVisibleLayout({
  required FieldOverlayItem item,
  required Size pageSize,
  required Rect pageRect,
}) {
  if (!_isUsablePage(pageSize: pageSize, pageRect: pageRect)) {
    return false;
  }
  return layoutFieldOverlay(
    items: <FieldOverlayItem>[item],
    pageSize: pageSize,
    pageRect: pageRect,
  ).single.isVisible;
}

bool _isUsablePage({required Size pageSize, required Rect pageRect}) {
  return pageSize.width.isFinite &&
      pageSize.width > 0 &&
      pageSize.height.isFinite &&
      pageSize.height > 0 &&
      !pageRect.isEmpty &&
      pageRect.left.isFinite &&
      pageRect.top.isFinite &&
      pageRect.right.isFinite &&
      pageRect.bottom.isFinite;
}
