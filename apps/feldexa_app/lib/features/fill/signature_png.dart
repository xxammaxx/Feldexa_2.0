// T086A ink-to-PNG adapter for the T083 signature sheet.
//
// Owner: `apps/feldexa_app/lib/features/fill/signature_png.dart` (T086A).
//
// Normative sources:
//   * `spec.md` FR-036 (a handwritten signature belongs only to the current
//     document) and FR-047 (only a verified revision is durable);
//   * `contracts/editor-interactions.md` §5 — the signature field opens a
//     full-screen sheet, „Übernehmen“ stores ink only for this document, and
//     there is no reuse library and no import from files;
//   * `data-model.md` §3.12 — a signature asset is a PNG whose long edge is at
//     most 1024 px;
//   * constitution Principles III, V, VI, VIII, and X.
//
// What this file is
// -----------------
// The single bridge from the presentation-only [SignatureDraft] to PNG bytes.
// It rasterizes exactly the strokes the sheet returned: same rounded 2.5 px
// line, same one-point dot, transparent background, no anti-alias setting that
// differs from the on-screen painter. Nothing is stored, cached, or shared
// between calls, so two drafts — and two documents — can never share ink.
//
// The encoding is deterministic for the same strokes and canvas size. The
// sheet's logical canvas is scaled so the long edge is at most
// [signaturePngMaxEdgePx] (never upscaled), which keeps a phone-sized sheet at
// its drawn resolution and bounds the stored asset.
//
// Evidence: host widget tests only (`NONE`). Android rendering is exercised by
// the T086A integration journey, which claims `EMULATOR` evidence only when the
// host driver verifies the attached device.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:feldexa_app/features/fill/signature_sheet.dart';
import 'package:flutter/material.dart';

/// Longest edge of an encoded signature PNG in pixels (`data-model.md` §3.12).
const int signaturePngMaxEdgePx = 1024;

/// Painted ink line width in logical pixels; identical to the sheet painter.
const double signaturePngStrokeWidth = 2.5;

/// A rasterized signature image plus the pixel size a `SignatureMark` records.
@immutable
final class SignaturePng {
  /// Creates an encoded signature image.
  const SignaturePng({
    required this.bytes,
    required this.widthPx,
    required this.heightPx,
  });

  /// PNG bytes, exactly as encoded.
  final Uint8List bytes;

  /// Encoded width in pixels.
  final int widthPx;

  /// Encoded height in pixels.
  final int heightPx;
}

/// Rasterizes [draft] to a PNG, or returns null for an unusable canvas.
///
/// A canvas that is not finite or smaller than one pixel, and a picture the
/// engine cannot encode, return null; the caller then reports the existing
/// content-free save failure instead of storing a fabricated image. An empty
/// draft is encoded honestly as a fully transparent image — the caller decides
/// whether empty ink is storable (the editor treats it as "nothing to apply").
Future<SignaturePng?> encodeSignaturePng(SignatureDraft draft) async {
  final Size canvas = draft.canvasSize;
  if (!canvas.width.isFinite ||
      !canvas.height.isFinite ||
      canvas.width < 1 ||
      canvas.height < 1) {
    return null;
  }
  final double longEdge = math.max(canvas.width, canvas.height);
  final double factor = longEdge > signaturePngMaxEdgePx
      ? signaturePngMaxEdgePx / longEdge
      : 1.0;
  final int widthPx = math.max(1, (canvas.width * factor).round());
  final int heightPx = math.max(1, (canvas.height * factor).round());

  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas paintCanvas = Canvas(recorder);
  paintCanvas.scale(factor);
  _paintStrokes(paintCanvas, draft.strokes, const Color(0xFF000000));
  final ui.Picture picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(widthPx, heightPx);
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (data == null) {
      return null;
    }
    return SignaturePng(
      bytes: Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      ),
      widthPx: widthPx,
      heightPx: heightPx,
    );
  } on Object {
    // A rasterization/encoding failure must never be reported as a saved
    // signature; the caller converts null into the existing save error.
    return null;
  } finally {
    image?.dispose();
    picture.dispose();
  }
}

/// Paints [strokes] exactly like the sheet's on-screen painter.
void _paintStrokes(Canvas canvas, List<SignatureStroke> strokes, Color color) {
  final Paint linePaint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = signaturePngStrokeWidth
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
      canvas.drawCircle(
        points.single,
        signaturePngStrokeWidth / 2,
        dotPaint,
      );
      continue;
    }
    final Path path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final Offset point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, linePaint);
  }
}
