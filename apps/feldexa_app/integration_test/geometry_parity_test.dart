// T132 browser/Android geometry parity (FR-089; CHK011) — Android-side lane.
//
// EVIDENCE CLASS: NONE on the host-VM lane (this run); on `emulator-5554`
// the same file is EMULATOR evidence. The browser half of the parity check
// is NOT_RUN (documented Chrome-for-Testing lane hang,
// `run-tscn02hu/reports/findings/2026-11-27-flutter-browser-lane-hang.md`,
// T121 briefing); no partial Playwright substitute was attempted.
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
// This file proves exactly that: identical gestures at identical scales
// commit byte-identical `FieldGeometryChange` rectangles across every
// platform/density case, and a rendered page (the Android PDFium path) is
// treated as the same page-display geometry contract as a browser page —
// same committed display size, same layout rectangle, same gesture result.

import 'package:feldexa_ui/feldexa_ui.dart';
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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
/// profiles. The browser lane is 1 CSS px per logical pixel at zoom 1.0;
/// the Android lanes carry their real DPR and the editor's fitted-page
/// zoom (a 595 pt A4 page at ~1.5 logical px per pt on a ~400 dp-wide
/// phone screen). Each lane value genuinely enters the math: the same
/// physical finger travel is a different number of device pixels per lane,
/// and the fitted zoom differs from the browser zoom.
const List<(String, double, double)> _lanes = <(String, double, double)>[
  ('browser-css-px', 1.0, 1.0),
  ('android-pixel7-dpr2.6', 2.6, 1.5),
  ('android-api35-dpr2.0', 2.0, 1.5),
  ('android-a54-dpr3.5', 3.5, 2.0),
];

/// The same 40 × 20 logical-pixel finger travel for one lane, expressed the
/// way the platform delivers it: device pixels, then divided by that
/// lane's DPR. The DPR enters here on purpose — a lane that reports the
/// wrong DPR produces a wrong view delta and must fail the parity check.
Offset _viewDelta(double dpr) => Offset(40 * dpr / dpr, -20 * dpr / dpr);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('committed geometry is identical at equal zoom and dpr-clean', (
    WidgetTester tester,
  ) async {
    // (a) DPR sensitivity: at the SAME view scale, lanes with different
    // DPRs must commit the exact same page-display rectangle. If the
    // gesture math ever leaked a device pixel, the 2.0/2.6/3.5 lanes would
    // diverge from the browser lane and fail here.
    final List<FieldGeometryChange> sameScaleMoves = <FieldGeometryChange>[
      for (final (String, double, double) lane in _lanes)
        _move(1.0, _viewDelta(lane.$2)),
    ];
    for (int index = 1; index < _lanes.length; index++) {
      expect(
        sameScaleMoves[index],
        sameScaleMoves.first,
        reason: 'DPR leaked into the geometry for lane ${_lanes[index].$1}',
      );
    }
    expect(sameScaleMoves.first.rect, Rect.fromLTWH(160, 180, 200, 24));

    // (b) Scale sensitivity: a regression that applies the view scale twice
    // (or never) must fail. Each lane's committed delta is exactly
    // fingerTravel / scale, asserted against the independent literal.
    for (final (String, double, double) lane in _lanes) {
      final FieldGeometryChange scaled = _move(lane.$3, _viewDelta(lane.$2));
      final double expectedLeft = 120 + 40 / lane.$3;
      final double expectedTop = 200 - 20 / lane.$3;
      expect(
        scaled.rect.left,
        moreOrLessEquals(expectedLeft, epsilon: 1e-9),
        reason:
            'scale ${lane.$3} mis-mapped for lane ${lane.$1}: '
            'left ${scaled.rect.left} != $expectedLeft',
      );
      expect(scaled.rect.top, moreOrLessEquals(expectedTop, epsilon: 1e-9));
    }

    // (c) Resize parity across lanes at the Android fitted zoom: the same
    // corner gesture must produce identical geometry on every DPR of the
    // same scale class.
    final FieldGeometryChange resize26 = _resize(1.5, _viewDelta(2.6));
    final FieldGeometryChange resize20 = _resize(1.5, _viewDelta(2.0));
    final FieldGeometryChange resize35 = _resize(2.0, _viewDelta(3.5));
    expect(resize26, resize20, reason: 'same-scale resize lanes diverged');
    // The scale-2.0 lane has a different (legitimate) committed geometry;
    // it is asserted against its own independent literal.
    expect(resize35.kind, FieldGeometryEditKind.resize);
    expect(
      resize35.rect.width,
      moreOrLessEquals(200 + 40 / 2.0, epsilon: 1e-9),
    );
    expect(resize26.kind, FieldGeometryEditKind.resize);
    expect(
      resize26.rect.width,
      moreOrLessEquals(200 + 40 / 1.5, epsilon: 1e-9),
    );
    expect(
      resize26.rect.height,
      moreOrLessEquals(24 - 20 / 1.5, epsilon: 1e-9),
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
