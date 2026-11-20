// Field-overlay painting from model coordinates (T069).
//
// Presentation only: stored page-display-space rectangles are mapped to the
// current page rectangle in view space and painted with provenance,
// uncertainty, conflict, and selection styling. Nothing here persists,
// mutates geometry, handles pointers, or composes user-facing text.
//
// Contract sources: `contracts/editor-interactions.md` §2–§4 and §11,
// `contracts/coordinates-and-geometry.md` §2 and §6, `data-model.md`
// §3.4–§3.5, FR-024/FR-083/FR-094, SC-017.

import 'dart:math' as math;

import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Visual provenance of one field overlay.
///
/// The values mirror the review treatment in
/// `contracts/editor-interactions.md` §3: a machine suggestion is blue
/// (dashed while uncertain), a confirmed machine field is green, a
/// user-created field is amber, and a template field is purple.
enum FieldOverlayProvenance {
  /// An unresolved recognition candidate.
  machineSuggestion,

  /// A field confirmed from a machine suggestion.
  confirmedMachine,

  /// A field created manually by the user.
  user,

  /// A layout-only field inherited from a pinned template version.
  template,
}

/// One paintable field in page-display space.
///
/// [rect] is the stored model rectangle in page-display points (top-left
/// origin, after page rotation and CropBox correction). Painting never mutates
/// it; the view rectangle is derived by [layoutFieldOverlay].
///
/// [pageIndex] is descriptive metadata, not a filter: every supplied item is
/// laid out and painted on the supplied page. The caller must pass only the
/// current page's items.
@immutable
final class FieldOverlayItem {
  /// Creates an overlay item.
  const FieldOverlayItem({
    required this.id,
    required this.pageIndex,
    required this.rect,
    required this.provenance,
    this.confidence,
    this.conflicting = false,
    this.selected = false,
    this.semanticLabel,
  });

  /// Creates an overlay item from a stored recognition suggestion.
  ///
  /// Copies values only; the suggestion is never written back. The model
  /// always supplies [core.FieldSuggestion.confidence]; a null confidence is
  /// defensive and is painted as uncertain. When [semanticLabel] is omitted or
  /// null, the suggestion's [core.FieldSuggestion.labelText] is used verbatim;
  /// an explicit value overrides it.
  factory FieldOverlayItem.fromSuggestion(
    core.FieldSuggestion suggestion, {
    bool selected = false,
    String? semanticLabel,
  }) {
    return FieldOverlayItem(
      id: suggestion.id,
      pageIndex: suggestion.pageIndex,
      rect: suggestion.rect,
      provenance: FieldOverlayProvenance.machineSuggestion,
      confidence: suggestion.confidence,
      conflicting: suggestion.conflictsWith.isNotEmpty,
      selected: selected,
      semanticLabel: semanticLabel ?? suggestion.labelText,
    );
  }

  /// Creates an overlay item from a stored confirmed field.
  ///
  /// Copies values only; the field is never written back. Only a machine field
  /// carries [core.ConfirmedField.suggestionConfidence]. When [semanticLabel]
  /// is omitted or null, the field's [core.ConfirmedField.label] is used
  /// verbatim; an explicit value overrides it.
  factory FieldOverlayItem.fromConfirmedField(
    core.ConfirmedField field, {
    bool selected = false,
    String? semanticLabel,
  }) {
    return FieldOverlayItem(
      id: field.id,
      pageIndex: field.pageIndex,
      rect: field.rect,
      provenance: switch (field.provenance) {
        core.Provenance.machine => FieldOverlayProvenance.confirmedMachine,
        core.Provenance.user => FieldOverlayProvenance.user,
        core.Provenance.template => FieldOverlayProvenance.template,
      },
      confidence: field.suggestionConfidence,
      conflicting: false,
      selected: selected,
      semanticLabel: semanticLabel ?? field.label,
    );
  }

  /// Stable field or suggestion id.
  final String id;

  /// Zero-based page index. This is metadata only, not a filter: the painter
  /// paints every supplied item on the supplied page, so callers must pass one
  /// page's items.
  final int pageIndex;

  /// Stored page-display-space rectangle in points; never mutated.
  final core.Rect rect;

  /// How the field came into existence.
  final FieldOverlayProvenance provenance;

  /// Suggestion confidence on `0.0 … 1.0`; null for non-machine fields and as
  /// a defensive fallback.
  final double? confidence;

  /// Whether the field is part of a conflict pair; draws a shape marker.
  final bool conflicting;

  /// Whether the field currently carries the selection accent.
  final bool selected;

  /// Optional caller/model label exposed through semantics verbatim.
  final String? semanticLabel;

  @override
  bool operator ==(Object other) {
    return other is FieldOverlayItem &&
        other.id == id &&
        other.pageIndex == pageIndex &&
        other.rect == rect &&
        other.provenance == provenance &&
        other.confidence == confidence &&
        other.conflicting == conflicting &&
        other.selected == selected &&
        other.semanticLabel == semanticLabel;
  }

  @override
  int get hashCode => Object.hash(
    id,
    pageIndex,
    rect,
    provenance,
    confidence,
    conflicting,
    selected,
    semanticLabel,
  );
}

/// Resolved paint treatment for one overlay item.
///
/// The selection accent is deliberately not stored: the painter receives
/// [FieldOverlayPainter.selectionColor] and draws the accent itself. The
/// textual `unsicher` badge is owned by the review panel/T074 and is not
/// composed by this presentation layer; [uncertain] only selects the shorter
/// dash pattern.
@immutable
final class FieldOverlayStyle {
  /// Creates a style.
  const FieldOverlayStyle({
    required this.outlineColor,
    required this.dashed,
    required this.strokeWidth,
    required this.uncertain,
    required this.conflicting,
    required this.selected,
  });

  /// Base outline color for the item's provenance.
  final Color outlineColor;

  /// Whether the base outline is dashed.
  final bool dashed;

  /// Base outline width in logical pixels.
  final double strokeWidth;

  /// Whether the item carries the uncertainty signal.
  final bool uncertain;

  /// Whether the item carries the conflict signal.
  final bool conflicting;

  /// Whether the item carries the selection signal.
  final bool selected;

  @override
  bool operator ==(Object other) {
    return other is FieldOverlayStyle &&
        other.outlineColor == outlineColor &&
        other.dashed == dashed &&
        other.strokeWidth == strokeWidth &&
        other.uncertain == uncertain &&
        other.conflicting == conflicting &&
        other.selected == selected;
  }

  @override
  int get hashCode => Object.hash(
    outlineColor,
    dashed,
    strokeWidth,
    uncertain,
    conflicting,
    selected,
  );
}

/// Maps one overlay item to its view-space rectangle and style.
@immutable
final class FieldOverlayLayout {
  /// Creates a layout result.
  const FieldOverlayLayout({
    required this.item,
    required this.viewRect,
    required this.clippedRect,
    required this.style,
  });

  /// The source item, unchanged.
  final FieldOverlayItem item;

  /// Unclipped view-space rectangle derived from the stored model rect.
  final Rect viewRect;

  /// Intersection of [viewRect] with the page rectangle; empty when the item
  /// lies fully outside the page.
  final Rect clippedRect;

  /// Resolved paint treatment.
  final FieldOverlayStyle style;

  /// Whether any part of the item lies inside the page rectangle.
  bool get isVisible => !clippedRect.isEmpty;
}

/// Resolves the paint treatment for [item] under
/// `contracts/editor-interactions.md` §3.
///
/// Boundaries are inclusive: a machine suggestion is solid at confidence
/// `>= 0.75` and uncertain below `0.50`. Outlines use 3:1-contrast colors
/// against white, and [FieldOverlayStyle.uncertain] selects the shorter
/// uncertainty dash pattern. The selection accent is painted by
/// [FieldOverlayPainter] and is intentionally not stored in the six-field
/// style. The textual `unsicher` badge is owned by the review panel/T074, not
/// this package.
FieldOverlayStyle fieldOverlayStyle(FieldOverlayItem item) {
  switch (item.provenance) {
    case FieldOverlayProvenance.machineSuggestion:
      final double? confidence = item.confidence;
      return FieldOverlayStyle(
        outlineColor: _machineOutlineColor,
        dashed: confidence == null || confidence < 0.75,
        strokeWidth: 1.5,
        uncertain: confidence == null || confidence < 0.50,
        conflicting: item.conflicting,
        selected: item.selected,
      );
    case FieldOverlayProvenance.confirmedMachine:
      return FieldOverlayStyle(
        outlineColor: _confirmedOutlineColor,
        dashed: false,
        strokeWidth: 1.5,
        uncertain: false,
        conflicting: item.conflicting,
        selected: item.selected,
      );
    case FieldOverlayProvenance.user:
      return FieldOverlayStyle(
        outlineColor: _userOutlineColor,
        dashed: false,
        strokeWidth: 1.5,
        uncertain: false,
        conflicting: item.conflicting,
        selected: item.selected,
      );
    case FieldOverlayProvenance.template:
      return FieldOverlayStyle(
        outlineColor: _templateOutlineColor,
        dashed: false,
        strokeWidth: 1.5,
        uncertain: false,
        conflicting: item.conflicting,
        selected: item.selected,
      );
  }
}

/// Maps stored page-display-space rectangles to the current page rectangle.
///
/// Each axis is mapped independently with the normative formula from
/// `contracts/coordinates-and-geometry.md` §3:
///
/// ```text
/// view = pageRect.origin + model / pageSize * pageRect.size
/// ```
///
/// Display space is already rotation- and CropBox-corrected, so no page
/// rotation or crop offset is re-derived here. The returned list preserves
/// input order and includes fully outside items with an empty [clippedRect].
/// [FieldOverlayItem.pageIndex] is not a filter: every supplied item is laid
/// out against [pageRect], so the caller must pass one page's items.
///
/// Throws [ArgumentError] when [pageSize] is non-finite or not strictly
/// positive, or when any edge of [pageRect] is non-finite. A finite page
/// rectangle with zero or negative area is accepted; the painter no-ops it.
List<FieldOverlayLayout> layoutFieldOverlay({
  required Iterable<FieldOverlayItem> items,
  required Size pageSize,
  required Rect pageRect,
}) {
  _checkPageSize(pageSize);
  _checkPageRect(pageRect);
  return <FieldOverlayLayout>[
    for (final FieldOverlayItem item in items)
      _layoutItem(item: item, pageSize: pageSize, pageRect: pageRect),
  ];
}

/// Paints field overlays from stored display-space coordinates.
///
/// The painter is presentation-only: it never mutates items, geometry, or the
/// model. Visible base outlines are drawn on the unclipped view rectangle and
/// cut by the page clip, so a crop edge never introduces a false border.
/// [FieldOverlayItem.pageIndex] is not a filter: every supplied item is painted
/// on the supplied page, so the caller must pass one page's items.
///
/// Uncertainty uses a shorter 2/3 dash pattern than the ordinary 6/4 dashed
/// outline. The textual `unsicher` badge is owned by the review panel/T074 and
/// is not painted here.
class FieldOverlayPainter extends CustomPainter {
  /// Creates a painter and copies [items] to an unmodifiable list.
  FieldOverlayPainter({
    required Iterable<FieldOverlayItem> items,
    required this.pageSize,
    required this.pageRect,
    required this.selectionColor,
    super.repaint,
  }) : items = List<FieldOverlayItem>.unmodifiable(items);

  /// Items in paint order (later items on top).
  final List<FieldOverlayItem> items;

  /// Page display size in model points.
  final Size pageSize;

  /// Current page rectangle in view space.
  final Rect pageRect;

  /// Accent for the selected outline and corner handle.
  final Color selectionColor;

  bool get _paintsNothing =>
      items.isEmpty ||
      pageSize.width <= 0 ||
      pageSize.height <= 0 ||
      pageRect.isEmpty;

  @override
  void paint(Canvas canvas, Size size) {
    if (_paintsNothing) {
      return;
    }
    canvas.save();
    canvas.clipRect(pageRect);
    try {
      final List<FieldOverlayLayout> layouts = layoutFieldOverlay(
        items: items,
        pageSize: pageSize,
        pageRect: pageRect,
      );
      for (final FieldOverlayLayout layout in layouts) {
        if (!layout.isVisible) {
          continue;
        }
        _paintLayout(canvas, layout);
      }
    } finally {
      canvas.restore();
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder {
    return (Size size) {
      if (_paintsNothing) {
        return const <CustomPainterSemantics>[];
      }
      final List<FieldOverlayLayout> layouts = layoutFieldOverlay(
        items: items,
        pageSize: pageSize,
        pageRect: pageRect,
      );
      return <CustomPainterSemantics>[
        for (final FieldOverlayLayout layout in layouts)
          if (layout.isVisible &&
              (layout.item.semanticLabel?.isNotEmpty ?? false))
            CustomPainterSemantics(
              rect: layout.clippedRect,
              properties: SemanticsProperties(
                label: layout.item.semanticLabel,
                textDirection: TextDirection.ltr,
              ),
            ),
      ];
    };
  }

  @override
  bool shouldRepaint(covariant FieldOverlayPainter oldDelegate) {
    return !listEquals(items, oldDelegate.items) ||
        pageSize != oldDelegate.pageSize ||
        pageRect != oldDelegate.pageRect ||
        selectionColor != oldDelegate.selectionColor;
  }

  void _paintLayout(Canvas canvas, FieldOverlayLayout layout) {
    final FieldOverlayStyle style = layout.style;
    final Paint outline = Paint()
      ..color = style.outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.strokeWidth;
    if (style.dashed) {
      _paintDashedRect(
        canvas,
        layout.viewRect,
        outline,
        dashLength: style.uncertain ? _uncertainDashLength : _dashLength,
        gapLength: style.uncertain ? _uncertainDashGap : _dashGap,
      );
    } else {
      canvas.drawRect(layout.viewRect, outline);
    }

    if (style.conflicting) {
      _paintConflictMarker(canvas, layout.clippedRect);
    }

    if (style.selected) {
      final Paint selectionOutline = Paint()
        ..color = selectionColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(layout.viewRect, selectionOutline);

      final Paint handle = Paint()
        ..color = selectionColor
        ..style = PaintingStyle.fill;
      canvas.drawRect(_selectionHandleRect(layout.viewRect), handle);
    }
  }

  /// Draws a deterministic dash walk around [rect] in edge order:
  /// top, right, bottom, left. Ordinary dashed outlines use 6/4; uncertain
  /// outlines use the shorter 2/3 pattern.
  void _paintDashedRect(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    required double dashLength,
    required double gapLength,
  }) {
    final double perimeter = 2 * (rect.width + rect.height);
    if (perimeter <= 0 || !perimeter.isFinite) {
      return;
    }
    double distance = 0;
    bool drawing = true;
    while (distance < perimeter) {
      final double step = drawing ? dashLength : gapLength;
      final double end = math.min(perimeter, distance + step);
      if (drawing) {
        canvas.drawLine(
          _perimeterPoint(rect, distance),
          _perimeterPoint(rect, end),
          paint,
        );
      }
      distance = end;
      drawing = !drawing;
    }
  }

  static Offset _perimeterPoint(Rect rect, double distance) {
    final double width = rect.width;
    final double height = rect.height;
    if (distance <= width) {
      return Offset(rect.left + distance, rect.top);
    }
    distance -= width;
    if (distance <= height) {
      return Offset(rect.right, rect.top + distance);
    }
    distance -= height;
    if (distance <= width) {
      return Offset(rect.right - distance, rect.bottom);
    }
    distance -= width;
    return Offset(rect.left, rect.bottom - distance);
  }

  /// Draws the red conflict triangle at the visible top-right corner so a
  /// partly outside item keeps a marker inside the page clip.
  void _paintConflictMarker(Canvas canvas, Rect visibleRect) {
    final Path triangle = Path()
      ..moveTo(visibleRect.right - _conflictSize, visibleRect.top)
      ..lineTo(visibleRect.right, visibleRect.top)
      ..lineTo(visibleRect.right, visibleRect.top + _conflictSize)
      ..close();
    canvas.drawPath(
      triangle,
      Paint()
        ..color = _conflictColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      triangle,
      Paint()
        ..color = _conflictStrokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  Rect _selectionHandleRect(Rect viewRect) {
    final double left = _clampHandle(
      viewRect.right - _handleSize,
      pageRect.left,
      pageRect.right - _handleSize,
    );
    final double top = _clampHandle(
      viewRect.bottom - _handleSize,
      pageRect.top,
      pageRect.bottom - _handleSize,
    );
    return Rect.fromLTWH(left, top, _handleSize, _handleSize);
  }

  static double _clampHandle(double value, double lower, double upper) {
    if (upper < lower) {
      return lower;
    }
    return value.clamp(lower, upper).toDouble();
  }
}

/// Paint-only field overlay for the current page.
///
/// The widget ignores pointers (T071 owns touch handling), expands to its
/// parent, and exposes one semantic node per visible labelled item. It paints
/// no text and composes no user-facing literal; labels come verbatim from the
/// model or caller. [FieldOverlayItem.pageIndex] is not a filter: pass only the
/// current page's items. The textual `unsicher` badge is owned by the review
/// panel/T074.
class FieldOverlay extends StatelessWidget {
  /// Creates a field overlay.
  const FieldOverlay({
    super.key,
    required this.items,
    required this.pageSize,
    required this.pageRect,
  });

  /// Items in paint order (later items on top).
  final Iterable<FieldOverlayItem> items;

  /// Page display size in model points.
  final Size pageSize;

  /// Current page rectangle in view space.
  final Rect pageRect;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: FieldOverlayPainter(
          items: items,
          pageSize: pageSize,
          pageRect: pageRect,
          selectionColor: Theme.of(context).colorScheme.primary,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

const double _dashLength = 6;
const double _dashGap = 4;
const double _uncertainDashLength = 2;
const double _uncertainDashGap = 3;
const double _conflictSize = 8;
const double _handleSize = 6;

// Every outline clears the 3:1 non-text contrast floor against white:
// blue800, green800, orange900, purple700, and red700.
const Color _machineOutlineColor = Color(0xFF1565C0);
const Color _confirmedOutlineColor = Color(0xFF2E7D32);
const Color _userOutlineColor = Color(0xFFE65100);
const Color _templateOutlineColor = Color(0xFF7B1FA2);
const Color _conflictColor = Color(0xFFD32F2F);
const Color _conflictStrokeColor = Color(0xFFB71C1C);

FieldOverlayLayout _layoutItem({
  required FieldOverlayItem item,
  required Size pageSize,
  required Rect pageRect,
}) {
  final double viewLeft =
      pageRect.left + item.rect.left / pageSize.width * pageRect.width;
  final double viewTop =
      pageRect.top + item.rect.top / pageSize.height * pageRect.height;
  final double viewWidth = item.rect.width / pageSize.width * pageRect.width;
  final double viewHeight =
      item.rect.height / pageSize.height * pageRect.height;
  final Rect viewRect = Rect.fromLTWH(viewLeft, viewTop, viewWidth, viewHeight);
  return FieldOverlayLayout(
    item: item,
    viewRect: viewRect,
    clippedRect: viewRect.intersect(pageRect),
    style: fieldOverlayStyle(item),
  );
}

void _checkPageSize(Size pageSize) {
  if (!pageSize.width.isFinite || pageSize.width <= 0) {
    throw ArgumentError.value(
      pageSize.width,
      'pageSize.width',
      'must be finite and greater than 0',
    );
  }
  if (!pageSize.height.isFinite || pageSize.height <= 0) {
    throw ArgumentError.value(
      pageSize.height,
      'pageSize.height',
      'must be finite and greater than 0',
    );
  }
}

void _checkPageRect(Rect pageRect) {
  if (!pageRect.left.isFinite) {
    throw ArgumentError.value(pageRect.left, 'pageRect.left', 'must be finite');
  }
  if (!pageRect.top.isFinite) {
    throw ArgumentError.value(pageRect.top, 'pageRect.top', 'must be finite');
  }
  if (!pageRect.right.isFinite) {
    throw ArgumentError.value(
      pageRect.right,
      'pageRect.right',
      'must be finite',
    );
  }
  if (!pageRect.bottom.isFinite) {
    throw ArgumentError.value(
      pageRect.bottom,
      'pageRect.bottom',
      'must be finite',
    );
  }
}
