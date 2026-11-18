// T042 pdfrx page viewer and source-point geometry mapping.
//
// Owner: `apps/feldexa_app/lib/features/editor/page_view.dart` (T042,
// issue #42).
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/contracts/coordinates-and-geometry.md`
//     sections 1–3 and 6 (the single geometry source of truth);
//   * `specs/001-scanned-form-workflow/spec.md` FR-003 (all pages, original
//     order, dimensions, orientation, and appearance), FR-018, and FR-024;
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// Coordinate spaces used by this file
// -----------------------------------
// * **Page display space** — PDF points, origin at the top-left of the visible
//   page box after `/Rotate`, y down. `PageGeometry` owns it in
//   `packages/feldexa_core` and implements the normative display ↔ PDF
//   user-space formulas, including CropBox offsets for rotations 0/90/180/270.
//   This file consumes only `PageGeometry.displaySize` and never re-derives
//   rotation or CropBox. Every point or rectangle returned by the hit-testing
//   API is in page display space (PDF points, top-left origin, y down), even
//   though it is carried in Flutter's [Offset]/[Rect] containers.
// * **Content space** — a private implementation detail of [PageViewLayout]:
//   page display points translated by the page's position in the vertical
//   document strip, before the view transform. One content unit is one PDF
//   point and one Flutter logical pixel at scale 1. It is never persisted and
//   never converted to device pixels by this file.
// * **View space** — Flutter logical pixels, origin at the top-left of the
//   viewport. The only transform is `view = pan + scale × content`, the exact
//   section 3 formula of the contract, applied with one uniform scale. Device
//   pixel ratio is deliberately absent: rendering may use it, geometry never
//   does.
// * **PDF user space** — PDF points, origin at the bottom-left, y up. This
//   file deliberately does not duplicate the conversion: a caller passes the
//   display-space point returned by [PageViewMapping.viewToDisplay] to the
//   page's canonical `PageGeometry.displayToPdf`.
//
// Rendering
// ---------
// The production renderer opens the protected source bytes with pdfrx/PDFium
// exactly once per source and renders each original page through the custom
// `_PdfrxPage` widget, which calls `PdfPage.renderForDisplay` directly.
// No page is re-laid-out, rewritten, cropped to anything smaller than its
// contract display box, or reconstructed from OCR or a bitmap cache. The page
// list is lazy: only pages intersecting the viewport (plus a small overscan
// margin) are built, so a 100-page document does not allocate 100 page
// renderers at once.
//
// Privacy
// -------
// Source bytes are supplied by the injected [PageViewSourceBytes] function.
// This file creates no temporary file, no on-disk cache, and no log entry. It
// never logs the source id, a path, a URI, a document title, page content, or
// raw renderer errors. [PageViewLoadException] carries only a stable
// [PageViewLoadFailure] value. pdfrx/PDFium may retain the source bytes and
// rendered page images in process memory for the lifetime of the open
// document; that is the only cache, and it is released on
// [PageViewRenderer.dispose] or when the viewer is disposed.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/widgets.dart' hide PageView;
import 'package:pdfrx/pdfrx.dart';

/// Resolves the protected original PDF bytes for one opaque [sourceId].
///
/// The callback returns the decrypted bytes or `null` when the source is not
/// available. It must be supplied by the protected document store; the viewer
/// never opens a path and never caches the bytes on disk. The viewer releases
/// its reference as soon as the renderer has accepted the bytes, but
/// pdfrx/PDFium may retain them in process memory for the document lifetime.
typedef PageViewSourceBytes = Future<Uint8List?> Function(String sourceId);

/// The minimum accepted page display extent in PDF points.
///
/// 0.001 pt is the same three-decimal quantum used by persisted `Rect`
/// serialization (`packages/feldexa_core/src/geometry/rect.dart`). It is far
/// below any real page, rejects the `1e-320` degenerate sizes whose reciprocal
/// overflows the raster floor, and keeps `1 / max(widthPt, heightPt)` finite
/// (at most 1000).
const double minimumPageExtentPt = 0.001;

/// The contract's fixed UI raster cap on the long edge, in pixels.
const int maximumRasterLongEdgePx = 4096;

/// One page's display size in PDF points, derived only from
/// `PageGeometry.displaySize`.
///
/// The type exists so a size in page display points cannot be confused with a
/// [Size] in view logical pixels. It carries no rotation or CropBox formula:
/// `PageGeometry.displaySize` already applied both. It is never persisted.
final class PageViewPageSize {
  /// Creates a page display size measured in PDF points.
  ///
  /// [widthPt] and [heightPt] must be finite and at least
  /// [minimumPageExtentPt].
  factory PageViewPageSize({
    required double widthPt,
    required double heightPt,
  }) {
    if (!widthPt.isFinite || widthPt < minimumPageExtentPt) {
      throw ArgumentError.value(
        widthPt,
        'widthPt',
        'must be finite and at least $minimumPageExtentPt pt',
      );
    }
    if (!heightPt.isFinite || heightPt < minimumPageExtentPt) {
      throw ArgumentError.value(
        heightPt,
        'heightPt',
        'must be finite and at least $minimumPageExtentPt pt',
      );
    }
    return PageViewPageSize._(widthPt, heightPt);
  }

  const PageViewPageSize._(this.widthPt, this.heightPt);

  /// Page display width in PDF points (after rotation and CropBox).
  final double widthPt;

  /// Page display height in PDF points (after rotation and CropBox).
  final double heightPt;

  /// The display size as a [Size] in content space (PDF points at scale 1).
  Size get contentSize => Size(widthPt, heightPt);

  @override
  bool operator ==(Object other) {
    return other is PageViewPageSize &&
        other.widthPt == widthPt &&
        other.heightPt == heightPt;
  }

  @override
  int get hashCode => Object.hash(widthPt, heightPt);

  @override
  String toString() => 'PageViewPageSize(${widthPt}pt, ${heightPt}pt)';
}

/// The bounded raster plan for one visible page.
///
/// The plan is derived from the page display box, the current view size, the
/// device pixel ratio, the 300-DPI UI limit, and the contract's 4096-pixel
/// long-edge cap. [effectiveScale] is raster pixels per PDF point; it is
/// reported to the painter only and never feeds [PageViewController] or any
/// stored geometry.
final class PageViewRasterPlan {
  /// Computes the bounded raster dimensions for one page.
  ///
  /// [viewSize] is the page's view-space box in logical pixels, [page] is the
  /// immutable display size, and [devicePixelRatio] is the renderer DPR.
  /// [maxLongEdgePx] defaults to the contract's 4096-pixel cap and may not
  /// exceed [maximumRasterLongEdgePx]; larger values are rejected so callers
  /// cannot bypass the public contract. The result is always at least 1x1 and
  /// never exceeds [maxLongEdgePx] on either edge.
  factory PageViewRasterPlan.forPage({
    required PageViewPageSize page,
    required Size viewSize,
    required double devicePixelRatio,
    int maxLongEdgePx = 4096,
    double maxDpi = 300,
  }) {
    if (!viewSize.width.isFinite ||
        !viewSize.height.isFinite ||
        viewSize.width <= 0 ||
        viewSize.height <= 0) {
      throw ArgumentError.value(
        viewSize,
        'viewSize',
        'must be finite and positive',
      );
    }
    if (!devicePixelRatio.isFinite || devicePixelRatio <= 0) {
      throw ArgumentError.value(
        devicePixelRatio,
        'devicePixelRatio',
        'must be finite and positive',
      );
    }
    if (maxLongEdgePx < 1 || maxLongEdgePx > maximumRasterLongEdgePx) {
      throw ArgumentError.value(
        maxLongEdgePx,
        'maxLongEdgePx',
        'must be between 1 and $maximumRasterLongEdgePx',
      );
    }
    if (!maxDpi.isFinite || maxDpi <= 0) {
      throw ArgumentError.value(
        maxDpi,
        'maxDpi',
        'must be finite and positive',
      );
    }
    final double logicalScale = viewSize.width / page.widthPt;
    final double desiredScale = logicalScale * devicePixelRatio;
    final double dpiScale = maxDpi / 72;
    final double longEdgePt = math.max(page.widthPt, page.heightPt);
    // A finite positive ratio can still underflow to 0.0 when a tiny view is
    // divided by a huge page. The floor 1 / longEdgePt guarantees a 1-pixel
    // long edge, so effectiveScale is always positive and the plan stays sane.
    final double minEffectiveScale = 1 / longEdgePt;
    final double effectiveScale = math.max(
      minEffectiveScale,
      math.min(desiredScale, math.min(dpiScale, maxLongEdgePx / longEdgePt)),
    );
    final int widthPx = (page.widthPt * effectiveScale).round().clamp(
      1,
      maxLongEdgePx,
    );
    final int heightPx = (page.heightPt * effectiveScale).round().clamp(
      1,
      maxLongEdgePx,
    );
    return PageViewRasterPlan._(
      widthPx: widthPx,
      heightPx: heightPx,
      effectiveScale: effectiveScale,
      desiredScale: desiredScale,
      maxLongEdgePx: maxLongEdgePx,
    );
  }

  const PageViewRasterPlan._({
    required this.widthPx,
    required this.heightPx,
    required this.effectiveScale,
    required this.desiredScale,
    required this.maxLongEdgePx,
  });

  /// Raster width in pixels; at least 1 and at most [maxLongEdgePx].
  final int widthPx;

  /// Raster height in pixels; at least 1 and at most [maxLongEdgePx].
  final int heightPx;

  /// Effective raster pixels per PDF point, reduced when a cap applies.
  final double effectiveScale;

  /// The unconstrained DPR-aware raster scale before any cap.
  final double desiredScale;

  /// The long-edge cap applied to this plan.
  final int maxLongEdgePx;

  /// Whether either cap reduced [desiredScale].
  bool get isCapped => effectiveScale < desiredScale;

  @override
  bool operator ==(Object other) =>
      other is PageViewRasterPlan &&
      other.widthPx == widthPx &&
      other.heightPx == heightPx &&
      other.effectiveScale == effectiveScale &&
      other.desiredScale == desiredScale &&
      other.maxLongEdgePx == maxLongEdgePx;

  @override
  int get hashCode => Object.hash(
    widthPx,
    heightPx,
    effectiveScale,
    desiredScale,
    maxLongEdgePx,
  );
}

/// One opened, immutable source document that can paint its original pages.
///
/// This is the narrow seam between [PageView] and pdfrx. Production uses
/// [openPdfrxPageRenderer]; tests inject a fake so the widget and the geometry
/// are exercisable on the host VM without a platform view or PDFium.
abstract interface class PageViewRenderer {
  /// Number of pages in original document order.
  int get pageCount;

  /// Builds the original page [pageIndex] (zero-based) for its display box.
  ///
  /// The returned widget is given tight constraints equal to the page's
  /// display box multiplied by the current view scale. Implementations must
  /// paint the unchanged original page and must never rewrite its content.
  Widget buildPage(
    BuildContext context,
    int pageIndex, {
    required ValueChanged<PageViewLoadException> onFailure,
  });

  /// Releases the underlying document and its in-memory page caches.
  ///
  /// [PageView] calls this exactly once per opened renderer. Implementations
  /// must be idempotent and must not log document content or paths.
  Future<void> dispose();
}

/// Opens a [PageViewRenderer] from already-decrypted source bytes.
///
/// The factory is called once per source id. It must not write the bytes to a
/// file and must not log them.
typedef PageViewRendererFactory = Future<PageViewRenderer> Function(
  Uint8List bytes,
);

/// Opens the production pdfrx/PDFium renderer for [bytes].
///
/// The returned renderer owns one [PdfDocument] for its entire lifetime; page
/// objects are taken from that document and are never recreated per build.
/// No file path, URI, document title, or source id is passed to pdfrx: the
/// neutral `sourceName` keeps diagnostic output content-free. pdfrx keeps the
/// document's bytes and page images in process memory until [dispose].
Future<PageViewRenderer> openPdfrxPageRenderer(Uint8List bytes) async {
  final PdfDocument document = await PdfDocument.openData(
    bytes,
    sourceName: 'feldexa-viewer-${_nextViewerSourceNumber++}',
  );
  return _PdfrxPageRenderer(document);
}

int _nextViewerSourceNumber = 0;

final class _PdfrxPageRenderer implements PageViewRenderer {
  _PdfrxPageRenderer(this._document);

  final PdfDocument _document;
  bool _disposed = false;

  @override
  int get pageCount => _document.pages.length;

  @override
  Widget buildPage(
    BuildContext context,
    int pageIndex, {
    required ValueChanged<PageViewLoadException> onFailure,
  }) {
    return RepaintBoundary(
      child: _PdfrxPage(
        document: _document,
        pageIndex: pageIndex,
        onFailure: onFailure,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _document.dispose();
  }
}

/// Renders one pdfrx page with an explicit raster cap and sanitized failures.
///
/// This deliberately does not use pdfrx's `PdfPageView`: that widget catches
/// asynchronous render errors and writes the raw exception text through
/// `developer.log`, bypassing the viewer's content-free failure contract. This
/// widget calls `PdfPage.renderForDisplay` itself, cancels stale renders, and
/// converts every failure to [PageViewLoadFailure.renderFailed].
class _PdfrxPage extends StatefulWidget {
  const _PdfrxPage({
    required this.document,
    required this.pageIndex,
    required this.onFailure,
  });

  final PdfDocument document;
  final int pageIndex;
  final ValueChanged<PageViewLoadException> onFailure;

  @override
  State<_PdfrxPage> createState() => _PdfrxPageState();
}

class _PdfrxPageState extends State<_PdfrxPage> {
  ui.Image? _image;
  PageViewRasterPlan? _plan;
  PdfPageRenderCancellationToken? _token;
  bool _scheduled = false;

  @override
  void dispose() {
    _token?.cancel();
    _image?.dispose();
    super.dispose();
  }

  void _schedule(PageViewRasterPlan plan) {
    if (_plan == plan || _scheduled) return;
    _plan = plan;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final PageViewRasterPlan? current = _plan;
      if (current != null) unawaited(_render(current));
    });
  }

  Future<void> _render(PageViewRasterPlan plan) async {
    if (widget.pageIndex < 0 ||
        widget.pageIndex >= widget.document.pages.length) {
      widget.onFailure(
        const PageViewLoadException(PageViewLoadFailure.renderFailed),
      );
      return;
    }
    _token?.cancel();
    final PdfPageRenderCancellationToken token = widget
        .document
        .pages[widget.pageIndex]
        .createCancellationToken();
    _token = token;
    try {
      final ui.Image? image = await widget.document.pages[widget.pageIndex]
          .renderForDisplay(
            fullWidth: plan.widthPx.toDouble(),
            fullHeight: plan.heightPx.toDouble(),
            cancellationToken: token,
            pixelSizeThreshold: plan.maxLongEdgePx,
          );
      if (!mounted || token.isCanceled) {
        image?.dispose();
        return;
      }
      if (image == null) {
        widget.onFailure(
          const PageViewLoadException(PageViewLoadFailure.renderFailed),
        );
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
      });
    } catch (_) {
      if (mounted && !token.isCanceled) {
        widget.onFailure(
          const PageViewLoadException(PageViewLoadFailure.renderFailed),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size viewSize = constraints.biggest;
        final PageViewPageSize page = PageViewPageSize(
          widthPt: widget.document.pages[widget.pageIndex].width,
          heightPt: widget.document.pages[widget.pageIndex].height,
        );
        final PageViewRasterPlan plan = PageViewRasterPlan.forPage(
          page: page,
          viewSize: viewSize,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        );
        _schedule(plan);
        final ui.Image? image = _image;
        return ColoredBox(
          color: const Color(0xFFFFFFFF),
          child: image == null
              ? const SizedBox.expand()
              : RawImage(image: image, fit: BoxFit.fill),
        );
      },
    );
  }
}

/// A stable, content-free reason why a [PageView] could not show its pages.
enum PageViewLoadFailure {
  /// The injected source callback returned `null` or an empty byte buffer.
  sourceUnavailable,

  /// The opened renderer's page count differs from the document model.
  ///
  /// Rendering is refused rather than placing pages at geometry that belongs
  /// to a different page.
  pageCountMismatch,

  /// pdfrx/PDFium could not open the supplied bytes.
  unreadableSource,

  /// A page raster could not be rendered; the raw error was discarded.
  renderFailed,
}

/// A content-free viewer failure.
///
/// The viewer deliberately discards raw renderer exceptions so a message that
/// contains a path, URI, or document text can never reach a log through this
/// type. Hosts may map [failure] to a German message in a later task.
final class PageViewLoadException implements Exception {
  /// Creates a failure with a stable reason.
  const PageViewLoadException(this.failure);

  /// The stable failure reason.
  final PageViewLoadFailure failure;

  @override
  String toString() => 'PageViewLoadException($failure)';
}

/// The fixed vertical layout of every page in its original order.
///
/// [pageRects] and [contentSize] are in content space: PDF points, top-left
/// origin, y down, one unit per logical pixel at scale 1. The page boxes use
/// `PageGeometry.displaySize` exactly, so rotation and CropBox are already
/// applied and never recomputed here. The horizontal gap is intentionally
/// zero: the widest page defines the content width and narrower pages are
/// centered, which makes `fitWidthScale = viewportWidth / widestDisplayWidth`
/// exact for every page. [pageGap] is UI spacing between pages in the same
/// unscaled units; it is not part of page geometry and is never persisted.
final class PageViewLayout {
  /// Builds the page strip for [pages] with [pageGap] between adjacent pages.
  ///
  /// Throws [ArgumentError] when [pages] is empty or when [pageGap] is not a
  /// finite non-negative number. Each [PageViewPageSize] already rejects a
  /// non-positive display size.
  factory PageViewLayout({
    required List<PageViewPageSize> pages,
    double pageGap = 8,
  }) {
    if (pages.isEmpty) {
      throw ArgumentError.value(pages, 'pages', 'must contain one page');
    }
    if (!pageGap.isFinite || pageGap < 0) {
      throw ArgumentError.value(
        pageGap,
        'pageGap',
        'must be finite and non-negative',
      );
    }
    final List<PageViewPageSize> owned = List<PageViewPageSize>.unmodifiable(
      pages,
    );
    double contentWidth = 0;
    for (final PageViewPageSize page in owned) {
      contentWidth = math.max(contentWidth, page.widthPt);
    }
    double top = 0;
    final List<Rect> rects = <Rect>[];
    for (int index = 0; index < owned.length; index++) {
      final PageViewPageSize page = owned[index];
      rects.add(
        Rect.fromLTWH(
          (contentWidth - page.widthPt) / 2,
          top,
          page.widthPt,
          page.heightPt,
        ),
      );
      final double nextTop =
          top + page.heightPt + (index != owned.length - 1 ? pageGap : 0);
      if (!nextTop.isFinite) {
        throw ArgumentError.value(
          pages,
          'pages',
          'accumulated page-strip height must be finite',
        );
      }
      top = nextTop;
    }
    return PageViewLayout._(
      pages: owned,
      pageRects: List<Rect>.unmodifiable(rects),
      contentSize: Size(contentWidth, top),
      pageGap: pageGap,
    );
  }

  const PageViewLayout._({
    required this.pages,
    required this.pageRects,
    required this.contentSize,
    required this.pageGap,
  });

  /// Page display sizes in original document order.
  final List<PageViewPageSize> pages;

  /// Page display boxes in content space, in original document order.
  final List<Rect> pageRects;

  /// Total content size in content space, including the page gap.
  final Size contentSize;

  /// Vertical gap between adjacent page boxes, in content space.
  final double pageGap;

  /// Number of pages in original document order.
  int get pageCount => pages.length;

  /// The display size of page [pageIndex] (zero-based), in PDF points.
  PageViewPageSize pageSizeFor(int pageIndex) {
    _checkPageIndex(pageIndex, pageCount);
    return pages[pageIndex];
  }

  /// The page box of [pageIndex] in content space.
  Rect pageRectFor(int pageIndex) {
    _checkPageIndex(pageIndex, pageCount);
    return pageRects[pageIndex];
  }
}

/// One page's view-space ↔ page-display-space mapping.
///
/// All methods are pure: they consult only the immutable page size, the page's
/// content-space box, and the current `scale`/`pan` snapshot. They never depend
/// on the device pixel ratio and never mutate any value. A returned [Offset]
/// or [Rect] is in page display space (PDF points, top-left origin, y down)
/// unless the method name says view space. For PDF user space, pass the result
/// of [viewToDisplay] to the page's canonical `PageGeometry.displayToPdf`.
final class PageViewMapping {
  const PageViewMapping._({
    required this.pageIndex,
    required this.pageSize,
    required this.pageRect,
    required this.scale,
    required this.pan,
  });

  /// Zero-based page index in original document order.
  final int pageIndex;

  /// The page display size derived from `PageGeometry.displaySize`.
  final PageViewPageSize pageSize;

  /// The page box in content space (PDF points, before the view transform).
  final Rect pageRect;

  /// View logical pixels per content unit (= per PDF point).
  final double scale;

  /// Translation of the content origin into view space, in logical pixels.
  final Offset pan;

  /// The page display box in view space, in logical pixels.
  ///
  /// This is the exact area in which the untouched original page is painted.
  Rect get pageRectInViewport {
    final double left = pan.dx + pageRect.left * scale;
    final double top = pan.dy + pageRect.top * scale;
    final double width = pageRect.width * scale;
    final double height = pageRect.height * scale;
    final double right = left + width;
    final double bottom = top + height;
    if (!left.isFinite ||
        !top.isFinite ||
        !width.isFinite ||
        !height.isFinite ||
        !right.isFinite ||
        !bottom.isFinite) {
      throw ArgumentError.value(
        pageIndex,
        'pageIndex',
        'derived page rectangle must be finite',
      );
    }
    return Rect.fromLTWH(left, top, width, height);
  }

  /// Converts a content-space offset to view space: `view = pan + scale × c`.
  Offset contentToView(Offset content) {
    return _checkedOffset(
      Offset(pan.dx + content.dx * scale, pan.dy + content.dy * scale),
      'derived view offset must be finite',
    );
  }

  /// Converts a view-space offset to content space: `(view − pan) / scale`.
  Offset viewToContent(Offset viewportOffset) {
    return _checkedOffset(
      Offset(
        (viewportOffset.dx - pan.dx) / scale,
        (viewportOffset.dy - pan.dy) / scale,
      ),
      'derived content offset must be finite',
    );
  }

  /// Converts a viewport offset (logical pixels) to page display space (points).
  ///
  /// The result is `(x, y)` measured from the top-left of the page's contract
  /// display box, x right, y down, in PDF points after rotation. It may lie
  /// outside `[0, 0, displayWidth, displayHeight]` when the pointer is outside
  /// the page; clamping or rejecting is the caller's decision.
  Offset viewToDisplay(Offset viewportOffset) {
    final Offset content = viewToContent(viewportOffset);
    return _checkedOffset(
      Offset(content.dx - pageRect.left, content.dy - pageRect.top),
      'derived display offset must be finite',
    );
  }

  /// Converts a page display-space point (PDF points, top-left origin, y down)
  /// to a viewport offset in logical pixels.
  Offset displayToView(Offset displayPoint) {
    return contentToView(
      _checkedOffset(
        Offset(pageRect.left + displayPoint.dx, pageRect.top + displayPoint.dy),
        'derived content offset must be finite',
      ),
    );
  }

  /// Maps a viewport rectangle to a page display-space rectangle.
  ///
  /// [viewportRect] is in logical pixels. The result is in PDF points with the
  /// display top-left origin and positive width and height. The transform has
  /// no rotation, so the result is axis-aligned. Throws [ArgumentError] when
  /// the mapped rectangle has no positive area.
  Rect viewRectToDisplay(Rect viewportRect) {
    final Offset topLeft = viewToContent(viewportRect.topLeft);
    final Offset bottomRight = viewToContent(viewportRect.bottomRight);
    final double left = math.min(topLeft.dx, bottomRight.dx) - pageRect.left;
    final double top = math.min(topLeft.dy, bottomRight.dy) - pageRect.top;
    final double right = math.max(topLeft.dx, bottomRight.dx) - pageRect.left;
    final double bottom = math.max(topLeft.dy, bottomRight.dy) - pageRect.top;
    final double width = right - left;
    final double height = bottom - top;
    if (!left.isFinite ||
        !top.isFinite ||
        !right.isFinite ||
        !bottom.isFinite ||
        !width.isFinite ||
        !height.isFinite) {
      throw ArgumentError.value(
        viewportRect,
        'viewportRect',
        'mapped display rectangle must be finite',
      );
    }
    if (!(right > left) || !(bottom > top)) {
      throw ArgumentError.value(
        viewportRect,
        'viewportRect',
        'must map to a display rectangle with positive width and height',
      );
    }
    return Rect.fromLTWH(left, top, width, height);
  }

  /// Maps a page display-space rectangle to a viewport rectangle.
  ///
  /// [displayRect] is in PDF points with the display top-left origin. The
  /// result is in logical pixels. Throws [ArgumentError] when the mapped
  /// rectangle has no positive area.
  Rect displayRectToView(Rect displayRect) {
    final Offset topLeft = displayToView(displayRect.topLeft);
    final Offset bottomRight = displayToView(displayRect.bottomRight);
    final double left = math.min(topLeft.dx, bottomRight.dx);
    final double top = math.min(topLeft.dy, bottomRight.dy);
    final double right = math.max(topLeft.dx, bottomRight.dx);
    final double bottom = math.max(topLeft.dy, bottomRight.dy);
    final double width = right - left;
    final double height = bottom - top;
    if (!left.isFinite ||
        !top.isFinite ||
        !right.isFinite ||
        !bottom.isFinite ||
        !width.isFinite ||
        !height.isFinite) {
      throw ArgumentError.value(
        displayRect,
        'displayRect',
        'mapped view rectangle must be finite',
      );
    }
    if (!(right > left) || !(bottom > top)) {
      throw ArgumentError.value(
        displayRect,
        'displayRect',
        'must map to a view rectangle with positive width and height',
      );
    }
    return Rect.fromLTWH(left, top, width, height);
  }
}

/// Owns the page strip layout and the single view transform.
///
/// State is exactly the contract's section 3 state: [scale] (logical pixels
/// per PDF point) and [pan] (the view-space translation of the content origin).
/// The same [scale] and [pan] are returned for every page; each page gets its
/// own [PageViewMapping] because its content-space origin differs.
///
/// All geometry is independent of the device pixel ratio. The controller does
/// not know or store a DPR, a raster size, or a device-pixel value.
///
/// The controller is owned by the caller. [PageView] never disposes a supplied
/// controller. Listeners are notified when the viewport, scale, or pan changes.
final class PageViewController extends ChangeNotifier {
  /// Creates a controller for [pages] in original document order.
  ///
  /// [pageGap] is UI spacing in content space and is not persisted.
  PageViewController({
    required List<PageViewPageSize> pages,
    double pageGap = 8,
  }) : layout = PageViewLayout(pages: pages, pageGap: pageGap);

  /// Creates a controller from an imported source's page geometry.
  ///
  /// Each page size is read from `PageGeometry.displaySize` exactly once; this
  /// is the only geometry input. Rotation, CropBox intersection, and display
  /// orientation are already encoded in that value. No pdfrx page dimension,
  /// device pixel, or file metadata participates in the layout.
  factory PageViewController.fromImportedSource(
    ImportedSource source, {
    double pageGap = 8,
  }) {
    return PageViewController(
      pages: <PageViewPageSize>[
        for (final page in source.pages)
          PageViewPageSize(
            widthPt: page.displaySize.width,
            heightPt: page.displaySize.height,
          ),
      ],
      pageGap: pageGap,
    );
  }

  /// The immutable page strip layout built from the document display sizes.
  final PageViewLayout layout;

  Size? _viewportSize;
  double _scale = 1;
  Offset _pan = Offset.zero;

  /// Number of pages in original document order.
  int get pageCount => layout.pageCount;

  /// Current viewport size in logical pixels, or `null` before first layout.
  Size? get viewportSize => _viewportSize;

  /// Whether a non-empty viewport has been reported by [PageView].
  bool get hasViewport => _viewportSize != null;

  /// Logical pixels per PDF point. Never a device-pixel value.
  double get scale => _scale;

  /// Translation of the content origin into view space, in logical pixels.
  Offset get pan => _pan;

  /// The scale that fits the widest page width exactly into the viewport.
  ///
  /// This is the contract's `fitWidthScale = viewportWidth / displayWidth`
  /// applied to the document's widest page, which is the content width. It is
  /// `1` before a viewport is known.
  double get fitWidthScale {
    final Size? viewport = _viewportSize;
    if (viewport == null || viewport.width <= 0) {
      return 1;
    }
    return viewport.width / layout.contentSize.width;
  }

  /// Lower zoom bound: `0.5 × fitWidthScale` (contract section 3).
  double get minScale => fitWidthScale * 0.5;

  /// Upper zoom bound: `8 × fitWidthScale` (contract section 3).
  double get maxScale => fitWidthScale * 8;

  /// The viewport rectangle in view space, or zero before layout.
  Rect get viewportRect {
    final Size? viewport = _viewportSize;
    return viewport == null
        ? Rect.zero
        : Rect.fromLTWH(0, 0, viewport.width, viewport.height);
  }

  /// The visible part of the page strip in content space.
  Rect get visibleContentRect {
    final Size? viewport = _viewportSize;
    if (viewport == null) {
      return Rect.fromLTWH(
        0,
        0,
        layout.contentSize.width,
        layout.contentSize.height,
      );
    }
    final Offset topLeft = viewToContent(Offset.zero);
    return Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      viewport.width / _scale,
      viewport.height / _scale,
    );
  }

  /// Records the viewport size and initializes or clamps the view transform.
  ///
  /// The first non-empty viewport selects fit-width and top alignment. A later
  /// resize keeps the current absolute scale unless the previous scale was
  /// exactly fit-width, in which case the view follows the new fit width. The
  /// page geometry itself is never changed. Identical sizes are ignored.
  ///
  /// Throws [ArgumentError] for a non-finite or non-positive size.
  void setViewportSize(Size viewport) {
    if (!viewport.width.isFinite ||
        !viewport.height.isFinite ||
        viewport.width <= 0 ||
        viewport.height <= 0) {
      throw ArgumentError.value(
        viewport,
        'viewport',
        'must be finite and strictly positive',
      );
    }
    if (_viewportSize == viewport) {
      return;
    }
    final bool firstViewport = _viewportSize == null;
    final bool followedFitWidth =
        firstViewport || (_scale - fitWidthScale).abs() <= 1e-9;
    _viewportSize = viewport;
    if (firstViewport || followedFitWidth) {
      _scale = fitWidthScale;
      _pan = _clampPan(Offset.zero);
    } else {
      _scale = _clampDouble(_scale, minScale, maxScale);
      _pan = _clampPan(_pan);
    }
    notifyListeners();
  }

  /// Sets the exact view transform, optionally clamping to the viewport.
  ///
  /// This is the test and caller entry point for a known transform. Gesture
  /// handling passes `clampToViewport: true` so a pinch cannot leave the page
  /// strip unreachable. The values must be finite and [scale] must be strictly
  /// positive.
  void setView({
    required double scale,
    required Offset pan,
    bool clampToViewport = false,
  }) {
    if (!scale.isFinite || scale <= 0) {
      throw ArgumentError.value(
        scale,
        'scale',
        'must be finite and strictly positive',
      );
    }
    if (!pan.dx.isFinite || !pan.dy.isFinite) {
      throw ArgumentError.value(pan, 'pan', 'must be finite');
    }
    final Offset nextPan = clampToViewport ? _clampPanFor(pan, scale) : pan;
    if (_scale == scale && _pan == nextPan) {
      return;
    }
    _scale = scale;
    _pan = nextPan;
    notifyListeners();
  }

  /// Selects fit-width for the widest page and aligns the strip to the top.
  ///
  /// Does nothing before a viewport is known.
  void fitWidth() {
    if (_viewportSize == null) {
      return;
    }
    final double targetScale = fitWidthScale;
    setView(scale: targetScale, pan: _clampPanFor(Offset.zero, targetScale));
  }

  /// Fits page [pageIndex] entirely into the viewport and centers it.
  ///
  /// The scale is `min(viewportWidth / pageWidth, viewportHeight / pageHeight)`
  /// from the contract. Does nothing before a viewport is known.
  void fitPage(int pageIndex) {
    final Size? viewport = _viewportSize;
    if (viewport == null) {
      return;
    }
    final Rect pageRect = layout.pageRectFor(pageIndex);
    final double scale = math.min(
      viewport.width / pageRect.width,
      viewport.height / pageRect.height,
    );
    final Offset center = pageRect.center;
    setView(
      scale: scale,
      pan: Offset(
        viewport.width / 2 - center.dx * scale,
        viewport.height / 2 - center.dy * scale,
      ),
    );
  }

  /// Scrolls page [pageIndex] to the top of the viewport and centers it.
  ///
  /// The page top edge is placed at viewport y = 0 and the page is centered
  /// horizontally. The current scale is preserved. This is the navigation seam
  /// for the T043 page strip; it changes no geometry.
  void scrollToPage(int pageIndex) {
    final Size? viewport = _viewportSize;
    if (viewport == null) {
      return;
    }
    final Rect pageRect = layout.pageRectFor(pageIndex);
    setView(
      scale: _scale,
      pan: _clampPan(
        Offset(
          viewport.width / 2 - (pageRect.left + pageRect.width / 2) * _scale,
          -pageRect.top * _scale,
        ),
      ),
    );
  }

  /// Pans by [delta] logical pixels, clamped so the strip stays reachable.
  void panBy(Offset delta) {
    if (!delta.dx.isFinite || !delta.dy.isFinite) {
      throw ArgumentError.value(delta, 'delta', 'must be finite');
    }
    if (_viewportSize == null) {
      return;
    }
    setView(scale: _scale, pan: _clampPan(_pan + delta));
  }

  /// The complete mapping for page [pageIndex] at the current transform.
  ///
  /// Throws [RangeError] when [pageIndex] is outside the document.
  PageViewMapping mappingFor(int pageIndex) {
    return PageViewMapping._(
      pageIndex: pageIndex,
      pageSize: layout.pageSizeFor(pageIndex),
      pageRect: layout.pageRectFor(pageIndex),
      scale: _scale,
      pan: _pan,
    );
  }

  /// Converts a viewport offset plus [pageIndex] to page display space.
  ///
  /// The result is in PDF points, top-left display origin, y down, after
  /// rotation and CropBox application. It is the hit-testing entry point for
  /// the overlay editor and the T043 page strip. To reach PDF user space, pass
  /// it to the page's `PageGeometry.displayToPdf`.
  Offset viewToDisplay(int pageIndex, Offset viewportOffset) {
    return mappingFor(pageIndex).viewToDisplay(viewportOffset);
  }

  /// Converts a page display-space point back to a viewport offset.
  Offset displayToView(int pageIndex, Offset displayPoint) {
    return mappingFor(pageIndex).displayToView(displayPoint);
  }

  /// Maps a viewport rectangle to a page display-space rectangle.
  Rect viewRectToDisplay(int pageIndex, Rect viewportRect) {
    return mappingFor(pageIndex).viewRectToDisplay(viewportRect);
  }

  /// Maps a page display-space rectangle to a viewport rectangle.
  Rect displayRectToView(int pageIndex, Rect displayRect) {
    return mappingFor(pageIndex).displayRectToView(displayRect);
  }

  /// The topmost page whose display box contains [viewportOffset], or `null`.
  ///
  /// This is a pure hit test: it does not change selection, geometry, or the
  /// view transform. The inter-page gap is not part of any page.
  int? pageIndexAt(Offset viewportOffset) {
    final Offset content = viewToContent(viewportOffset);
    for (int index = 0; index < layout.pageCount; index++) {
      if (layout.pageRects[index].contains(content)) {
        return index;
      }
    }
    return null;
  }

  /// Converts a viewport offset to content space.
  Offset viewToContent(Offset viewportOffset) {
    return _checkedOffset(
      Offset(
        (viewportOffset.dx - _pan.dx) / _scale,
        (viewportOffset.dy - _pan.dy) / _scale,
      ),
      'derived content offset must be finite',
    );
  }

  /// Converts a content-space offset to view space.
  Offset contentToView(Offset content) {
    return _checkedOffset(
      Offset(_pan.dx + content.dx * _scale, _pan.dy + content.dy * _scale),
      'derived view offset must be finite',
    );
  }

  Offset _clampPan(Offset pan) {
    return _clampPanFor(pan, _scale);
  }

  Offset _clampPanFor(Offset pan, double scale) {
    final Size? viewport = _viewportSize;
    if (viewport == null) {
      return pan;
    }
    final double contentWidth = layout.contentSize.width * scale;
    final double contentHeight = layout.contentSize.height * scale;
    final double x;
    if (contentWidth <= viewport.width) {
      x = (viewport.width - contentWidth) / 2;
    } else {
      x = _clampDouble(pan.dx, viewport.width - contentWidth, 0);
    }
    final double y;
    if (contentHeight <= viewport.height) {
      y = (viewport.height - contentHeight) / 2;
    } else {
      y = _clampDouble(pan.dy, viewport.height - contentHeight, 0);
    }
    return Offset(x, y);
  }
}

/// The pdfrx page viewer with the source-point geometry mapping.
///
/// The widget renders every page of [controller]'s document in original order
/// and original display dimensions through [rendererFactory]. It opens the
/// source bytes exactly once per [sourceId] and reuses the resulting document
/// and page objects across builds. It creates no file, cache, or log entry.
///
/// [controller] is owned by the caller and is never disposed here. The page
/// strip can share the same controller (T043), and overlay hit testing uses
/// [PageViewController.viewToDisplay].
///
/// Gestures pan with one finger and zoom with a two-finger pinch around the
/// focal point. The zoom range is the contract's `0.5 × fitWidthScale` …
/// `8 × fitWidthScale`. No gesture mutates document geometry.
class PageView extends StatefulWidget {
  /// Creates a viewer for [controller]'s pages.
  ///
  /// [sourceId] is an opaque document/source identifier passed only to
  /// [sourceBytes]; it is never logged. [sourceBytes] is the protected-store
  /// seam. [rendererFactory] defaults to [openPdfrxPageRenderer] and exists so
  /// host-VM tests can inject a fake without a platform view.
  const PageView({
    required this.sourceId,
    required this.sourceBytes,
    required this.controller,
    this.rendererFactory = openPdfrxPageRenderer,
    this.loadingBuilder,
    this.errorBuilder,
    this.onLoadError,
    this.backgroundColor = const Color(0xFF525659),
    super.key,
  });

  /// Opaque source identifier for [sourceBytes]; never logged.
  ///
  /// This value is the document identity. Changing it disposes the old
  /// renderer and opens the new source. Changing [sourceBytes] or
  /// [rendererFactory] for the same id does not reopen an already open
  /// document, so a rebuild cannot create a second document object.
  final String sourceId;

  /// Protected-store resolver for the original PDF bytes.
  final PageViewSourceBytes sourceBytes;

  /// Layout and view transform shared with the rest of the editor.
  final PageViewController controller;

  /// Opens the renderer once per source. Defaults to pdfrx/PDFium.
  final PageViewRendererFactory rendererFactory;

  /// Optional content-free loading placeholder.
  final WidgetBuilder? loadingBuilder;

  /// Optional content-free failure placeholder.
  ///
  /// The builder receives only [PageViewLoadException]; the viewer never
  /// exposes raw renderer text. Hosts must not log document content here.
  final WidgetBuilder? errorBuilder;

  /// Called with the sanitized [PageViewLoadException] when opening fails.
  ///
  /// Intended for a later German error surface; this callback must not log the
  /// source id or document content.
  final ValueChanged<PageViewLoadException>? onLoadError;

  /// Viewport background behind the pages. No page content is drawn here.
  final Color backgroundColor;

  @override
  State<PageView> createState() => _PageViewState();
}

class _PageViewState extends State<PageView> {
  static const double _pageOverscanContent = 64;

  PageViewRenderer? _renderer;
  PageViewLoadException? _error;
  int _generation = 0;
  Size? _lastReportedViewport;
  double _gestureStartScale = 1;
  Offset _gestureStartPan = Offset.zero;
  Offset _gestureStartFocal = Offset.zero;
  bool _gestureActive = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void didUpdateWidget(covariant PageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _lastReportedViewport = null;
      final PageViewRenderer? renderer = _renderer;
      if (renderer != null &&
          renderer.pageCount != widget.controller.pageCount) {
        unawaited(_open());
      }
    }
    if (oldWidget.sourceId != widget.sourceId) {
      unawaited(_open());
    }
  }

  @override
  void dispose() {
    _generation++;
    final PageViewRenderer? renderer = _renderer;
    _renderer = null;
    if (renderer != null) {
      unawaited(renderer.dispose());
    }
    super.dispose();
  }

  Future<void> _open() async {
    final int generation = ++_generation;
    final PageViewRenderer? previous = _renderer;
    if (_renderer != null || _error != null) {
      setState(() {
        _renderer = null;
        _error = null;
      });
    }
    if (previous != null) {
      await previous.dispose();
    }
    if (!mounted || generation != _generation) {
      return;
    }
    try {
      final Uint8List? bytes = await widget.sourceBytes(widget.sourceId);
      if (!mounted || generation != _generation) {
        return;
      }
      if (bytes == null || bytes.isEmpty) {
        throw const PageViewLoadException(
          PageViewLoadFailure.sourceUnavailable,
        );
      }
      final PageViewRenderer renderer = await widget.rendererFactory(bytes);
      if (!mounted || generation != _generation) {
        await renderer.dispose();
        return;
      }
      if (renderer.pageCount != widget.controller.pageCount) {
        await renderer.dispose();
        throw const PageViewLoadException(
          PageViewLoadFailure.pageCountMismatch,
        );
      }
      setState(() {
        _renderer = renderer;
        _error = null;
      });
    } on PageViewLoadException catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _renderer = null;
        _error = error;
      });
      widget.onLoadError?.call(error);
    } catch (_) {
      if (!mounted || generation != _generation) {
        return;
      }
      const PageViewLoadException error = PageViewLoadException(
        PageViewLoadFailure.unreadableSource,
      );
      setState(() {
        _renderer = null;
        _error = error;
      });
      widget.onLoadError?.call(error);
    }
  }

  void _reportRenderFailure(PageViewLoadException error) {
    if (!mounted || _error != null) return;
    final PageViewRenderer? renderer = _renderer;
    setState(() {
      _renderer = null;
      _error = error;
    });
    if (renderer != null) unawaited(renderer.dispose());
    widget.onLoadError?.call(error);
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _gestureActive = true;
    _gestureStartScale = widget.controller.scale;
    _gestureStartPan = widget.controller.pan;
    _gestureStartFocal = details.localFocalPoint;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (!_gestureActive) {
      return;
    }
    final double nextScale = _clampDouble(
      _gestureStartScale * details.scale,
      widget.controller.minScale,
      widget.controller.maxScale,
    );
    final Offset contentAtFocal = Offset(
      (_gestureStartFocal.dx - _gestureStartPan.dx) / _gestureStartScale,
      (_gestureStartFocal.dy - _gestureStartPan.dy) / _gestureStartScale,
    );
    widget.controller.setView(
      scale: nextScale,
      pan: Offset(
        details.localFocalPoint.dx - contentAtFocal.dx * nextScale,
        details.localFocalPoint.dy - contentAtFocal.dy * nextScale,
      ),
      clampToViewport: true,
    );
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _gestureActive = false;
  }

  void _reportViewport(Size viewport) {
    if (!viewport.width.isFinite ||
        !viewport.height.isFinite ||
        viewport.width <= 0 ||
        viewport.height <= 0 ||
        viewport == _lastReportedViewport) {
      return;
    }
    _lastReportedViewport = viewport;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lastReportedViewport != viewport) {
        return;
      }
      widget.controller.setViewportSize(viewport);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size viewport = constraints.biggest;
        _reportViewport(viewport);
        return ColoredBox(
          color: widget.backgroundColor,
          child: ClipRect(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _handleScaleStart,
              onScaleUpdate: _handleScaleUpdate,
              onScaleEnd: _handleScaleEnd,
              child: AnimatedBuilder(
                animation: widget.controller,
                builder: (BuildContext context, Widget? child) {
                  final PageViewLoadException? error = _error;
                  if (error != null) {
                    return widget.errorBuilder?.call(context) ??
                        const SizedBox.expand();
                  }
                  final PageViewRenderer? renderer = _renderer;
                  if (renderer == null) {
                    return widget.loadingBuilder?.call(context) ??
                        const SizedBox.expand();
                  }
                  return _buildPages(context, renderer);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPages(BuildContext context, PageViewRenderer renderer) {
    final PageViewLayout layout = widget.controller.layout;
    final Rect visibleContent = widget.controller.visibleContentRect.inflate(
      _pageOverscanContent,
    );
    final List<Widget> pages = <Widget>[];
    for (int index = 0; index < layout.pageCount; index++) {
      final Rect pageRect = layout.pageRects[index];
      if (!pageRect.overlaps(visibleContent)) {
        continue;
      }
      final Rect viewportRect = widget.controller
          .mappingFor(index)
          .pageRectInViewport;
      pages.add(
        Positioned(
          key: ValueKey<int>(index),
          left: viewportRect.left,
          top: viewportRect.top,
          width: viewportRect.width,
          height: viewportRect.height,
          child: renderer.buildPage(
            context,
            index,
            onFailure: _reportRenderFailure,
          ),
        ),
      );
    }
    return Stack(clipBehavior: Clip.hardEdge, children: pages);
  }
}

Offset _checkedOffset(Offset value, String message) {
  if (!value.dx.isFinite || !value.dy.isFinite) {
    throw ArgumentError(message);
  }
  return value;
}

double _clampDouble(double value, double min, double max) {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

void _checkPageIndex(int pageIndex, int pageCount) {
  if (pageIndex < 0 || pageIndex >= pageCount) {
    throw RangeError.range(pageIndex, 0, pageCount - 1, 'pageIndex');
  }
}
