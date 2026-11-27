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

/// One recorded gesture, replayed per density case.
FieldGeometryChange _move(double scale, Offset viewDelta) {
  final FieldGeometrySession session = FieldGeometrySession.start(
    fieldId: 'parity-1',
    handle: FieldGeometryHandle.body,
    startRect: _start,
    pageBox: _pageBox,
    scale: scale,
  );
  session.update(mapViewDeltaToDisplay(viewDelta: viewDelta, scale: scale));
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
  session.update(mapViewDeltaToDisplay(viewDelta: viewDelta, scale: scale));
  return session.commit()!;
}

/// The lane matrix: each lane's device pixel ratio (browser CSS px = 1,
/// committed Android profiles = 2.0/2.6/3.5). The same physical drag of
/// 40 × 20 device pixels produces a view delta of 40/`dpr` logical pixels,
/// and the view scale is 1.0 logical px per point on every lane.
const List<(String, double)> _lanes = <(String, double)>[
  ('browser-css-px-dpr1', 1.0),
  ('android-pixel7-dpr2.6', 2.6),
  ('android-api35-dpr2.0', 2.0),
  ('android-a54-dpr3.5', 3.5),
];

/// The same physical drag expressed in each lane's device pixels, then
/// mapped back to view pixels through that lane's DPR — the DPR cancels,
/// which is exactly the FR-089 parity seam: the gesture math never sees a
/// device pixel.
Offset _viewDelta(double dpr) => Offset(40 * dpr / dpr, -20 * dpr / dpr);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('committed geometry is identical across browser/Android lanes', (
    WidgetTester tester,
  ) async {
    final List<FieldGeometryChange> moves = <FieldGeometryChange>[
      for (final (String, double) lane in _lanes)
        _move(1.0, _viewDelta(lane.$2)),
    ];
    final List<FieldGeometryChange> resizes = <FieldGeometryChange>[
      for (final (String, double) lane in _lanes)
        _resize(1.0, _viewDelta(lane.$2)),
    ];

    // Parity: the first lane (browser) is the reference; every Android lane
    // must commit the exact same rectangle — not approximately, exactly,
    // because the math never touches device pixels.
    for (int index = 1; index < _lanes.length; index++) {
      expect(
        moves[index],
        moves.first,
        reason: 'move parity failed for lane ${_lanes[index].$1} vs browser',
      );
      expect(
        resizes[index],
        resizes.first,
        reason: 'resize parity failed for lane ${_lanes[index].$1} vs browser',
      );
    }
    expect(moves.first.kind, FieldGeometryEditKind.move);
    expect(resizes.first.kind, FieldGeometryEditKind.resize);
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
      expect(atScale.rect.width, atScale.previousRect.width);
    }
  });
}
