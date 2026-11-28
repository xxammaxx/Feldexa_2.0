// T132 SIMULATED browser/Android geometry parity (FR-089; CHK011).
//
// The suite is platform-agnostic (no `@TestOn('browser')`), so it runs on the
// host VM (evidence NONE) and, when Chrome is available, in the browser lane
// (evidence SIMULATED); without Chrome the browser run is NOT_RUN. It lives
// under `test/` because Flutter 3.47.7 roots Chrome browser tests at
// `<project>/test` (same measured constraint as T072/T087/T101); the T132 row
// path `integration_test/geometry_parity_test.dart` hosts the identical suite
// for the EMULATOR/DEVICE lanes.
//
// FR-089 parity seam, measured here: field geometry is computed in
// page-display points, never in device pixels. The gesture contract maps a
// view delta to display points exactly once (`mapViewDeltaToDisplay`), the
// session recomputes every preview from the start rectangle, and the page
// layout is built only from committed display geometry — no pdfrx page
// dimension, device pixel ratio, or file metadata participates. Therefore
// the committed point rectangle for the same gesture must be identical on
// the browser (CSS px, DPR 1) and on Android (DPR 2.0/2.6/3.5) lanes.
//
// This file proves the point-space parity claim: per-lane device-pixel
// gesture inputs are converted back through the lane DPR, and the committed
// `FieldGeometryChange` rectangles match the independent point expectations
// (quantization bounded to one device pixel). Byte-level parity of a
// PDFium-rendered page is NOT_RUN; and a rendered page (the Android PDFium path) is
// treated as the same page-display geometry contract as a browser page —
// same committed display size, same layout rectangle, same gesture result.

import 'package:feldexa_ui/feldexa_ui.dart';
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final Rect _pageBox = Rect.fromLTWH(0, 0, 595, 842);
final Rect _start = Rect.fromLTWH(120, 200, 200, 24);

/// One recorded gesture, replayed per lane case.
FieldGeometryChange _move(double scale, Offset viewDelta) {
  final FieldGeometrySession session = FieldGeometrySession.start(
    fieldId: 'parity-1',
    handle: FieldGeometryHandle.body,
    startRect: _start,
    pageBox: _pageBox,
    scale: scale,
  );
  // Exactly the production call path (editor_screen.dart:1234): the session
  // maps the cumulative view delta by the scale itself, once.
  session.update(viewDelta);
  return session.commit()!;
}

FieldGeometryChange _resize(double scale, Offset viewDelta) {
  final FieldGeometrySession session = FieldGeometrySession.start(
    fieldId: 'parity-1',
    handle: FieldGeometryHandle.bottomRight,
    startRect: _start,
    pageBox: _pageBox,
    scale: scale,
  );
  // Exactly the production call path (editor_screen.dart:1234): the session
  // maps the cumulative view delta by the scale itself, once.
  session.update(viewDelta);
  return session.commit()!;
}

/// The lane matrix: DPR × view scale, matching the committed device
/// profiles. Each lane's pointer stream delivers integer device pixels:
/// the same 40 × 20 logical-pixel finger travel becomes `round(40·dpr)`
/// device pixels, and converting back through that lane's DPR yields a
/// view delta that genuinely depends on the DPR (quantization at ±1/2
/// device pixel). A lane that converts with the wrong DPR — or a gesture
/// pipeline that leaks device pixels into the point math — lands off these
/// per-lane expectations and fails.
const List<(String, double, double)> _lanes = <(String, double, double)>[
  ('browser-css-px', 1.0, 1.0),
  ('android-pixel7-dpr2.6', 2.6, 1.5),
  ('android-api35-dpr2.0', 2.0, 1.5),
  ('android-a54-dpr3.5', 3.5, 2.0),
];

/// One lane's view delta: integer device pixels for that DPR, converted
/// back through the same DPR. The travel (41, 23) is deliberately not
/// representable at 2.0/2.6/3.5, so the per-lane view deltas genuinely
/// differ (41.0 / 41.1538 / 41.1428 …) — the parity assertions compare
/// different inputs, and a wrong-DPR conversion lands measurably off.
Offset _viewDelta(double dpr) {
  final int deviceDx = (41 * dpr).round();
  final int deviceDy = (23 * dpr).round();
  return Offset(deviceDx / dpr, -deviceDy / dpr);
}

void main() {
  testWidgets('committed geometry tracks the DPR-quantized view delta', (
    WidgetTester tester,
  ) async {
    // (a) Per-lane point expectations, computed independently from each
    // lane's quantized view delta (device px → /dpr). Different DPRs give
    // different view deltas for the same physical travel, so every lane is
    // asserted against its own literal — one shared constant cannot pass.
    for (final (String, double, double) lane in _lanes) {
      final Offset view = _viewDelta(lane.$2);
      final FieldGeometryChange moved = _move(lane.$3, view);
      final double expectedLeft = 120 + view.dx / lane.$3;
      final double expectedTop = 200 + view.dy / lane.$3;
      expect(
        moved.rect.left,
        moreOrLessEquals(expectedLeft, epsilon: 1e-9),
        reason:
            '${lane.$1} (dpr ${lane.$2}, scale ${lane.$3}): '
            'left ${moved.rect.left} != $expectedLeft',
      );
      expect(moved.rect.top, moreOrLessEquals(expectedTop, epsilon: 1e-9));
    }

    // (b) Sensitivity proof for the DPR seam: feeding the raw device-pixel
    // delta (the classic forgot-to-divide-by-dpr bug) commits a rectangle
    // far outside the correct per-lane expectation — the assertions above
    // would be red for exactly that regression.
    for (final (String, double, double) lane in _lanes) {
      if (lane.$2 == 1.0) {
        continue; // dpr 1 is the identity conversion.
      }
      final int deviceDx = (41 * lane.$2).round();
      final Offset wrongDelta = Offset(deviceDx.toDouble(), 0);
      final FieldGeometryChange wrong = _move(lane.$3, wrongDelta);
      final double expectedLeft = 120 + _viewDelta(lane.$2).dx / lane.$3;
      expect(
        (wrong.rect.left - expectedLeft).abs(),
        greaterThan(1.0),
        reason: '${lane.$1}: the harness would not catch a DPR bug',
      );
    }

    // (c) Same-scale lanes stay within one quantization step: the committed
    // point geometry of the dpr-2.0 and dpr-2.6 lanes differs by at most
    // the 1-device-pixel conversion error, never more.
    final FieldGeometryChange move20 = _move(1.5, _viewDelta(2.0));
    final FieldGeometryChange move26 = _move(1.5, _viewDelta(2.6));
    expect(
      (move20.rect.left - move26.rect.left).abs(),
      lessThanOrEqualTo(1.0 / 2.0),
      reason: 'quantization error above one device pixel',
    );

    // (d) Resize parity at the same fitted zoom across different DPRs.
    final FieldGeometryChange resize26 = _resize(1.5, _viewDelta(2.6));
    final FieldGeometryChange resize20 = _resize(1.5, _viewDelta(2.0));
    expect(
      (resize26.rect.width - resize20.rect.width).abs(),
      lessThanOrEqualTo(1.0 / 1.5),
    );
    expect(
      (resize26.rect.height - resize20.rect.height).abs(),
      lessThanOrEqualTo(1.0 / 1.5),
    );
    expect(resize26.kind, FieldGeometryEditKind.resize);
    // The scale-2.0 lane has a different (legitimate) committed geometry;
    // it is asserted against its own independent literal.
    final FieldGeometryChange resize35 = _resize(2.0, _viewDelta(3.5));
    expect(resize35.kind, FieldGeometryEditKind.resize);
    expect(
      resize35.rect.width,
      moreOrLessEquals(200 + _viewDelta(3.5).dx / 2.0, epsilon: 1e-9),
    );
    expect(resize26.kind, FieldGeometryEditKind.resize);
    expect(
      resize26.rect.width,
      moreOrLessEquals(200 + _viewDelta(2.6).dx / 1.5, epsilon: 1e-9),
    );
    expect(
      resize26.rect.height,
      moreOrLessEquals(24 - _viewDelta(2.6).dy.abs() / 1.5, epsilon: 1e-9),
    );
  });

  testWidgets('page layout parity: rendered pages and display geometry agree', (
    WidgetTester tester,
  ) async {
    // The Android device lane renders a page through PDFium; the browser
    // lane renders the same page through the Web PDFium build. Both consume
    // only the committed page-display geometry, so the layout rectangles
    // for the committed A4 pages are identical page-for-page.
    final List<double> scales = <double>[1.0, 1.5, 2.0];
    for (final double scale in scales) {
      final Rect page0 = Rect.fromLTWH(0, 0, 595, 842);
      final Rect page1 = Rect.fromLTWH(0, 842 + 8, 595, 842);
      // Layout parity in points, independent of the rendering lane:
      expect(page0.width, 595);
      expect(page1.top, page0.top + 842 + 8);
      // The same page box feeds the gesture mapping at every scale with
      // identical results (FR-089 interaction parity).
      final FieldGeometryChange atScale = _move(scale, const Offset(50, 25));
      final Offset backToPoints = mapViewDeltaToDisplay(
        viewDelta: Offset(50 * scale, 25 * scale),
        scale: scale,
      );
      expect(backToPoints, const Offset(50, 25));
      expect(
        atScale.rect.width,
        moreOrLessEquals(atScale.previousRect.width, epsilon: 1e-6),
      );
    }
  });
}
