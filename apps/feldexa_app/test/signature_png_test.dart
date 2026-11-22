// T086A signature ink → PNG encoder host tests.
//
// Evidence class: NONE. These are host-VM widget tests over the pure encoder.
// They open no store, PDF, platform channel, emulator, or device and make no
// Android, screen-reader, or visual claim.
//
// They prove:
//   * the encoded bytes are a real PNG stream of the bounded canvas size;
//   * the long edge is capped at 1024 px and a small canvas is never upscaled;
//   * only ink is painted: the background is transparent and the drawn stroke
//     is dark and opaque;
//   * the encoding is deterministic for the same draft, so the stored
//     `SignatureMark.sha256` is stable for the same ink;
//   * different ink produces different bytes (no cached or global image), and
//     each call returns a fresh buffer;
//   * an unusable canvas returns null instead of a fabricated image;
//   * the derived `SignatureAsset` digest equals `package:crypto` for exactly
//     these bytes.

@TestOn('vm')
library;

import 'dart:typed_data';
import 'dart:ui';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_app/features/fill/signature_png.dart';
import 'package:feldexa_app/features/fill/signature_sheet.dart';
import 'package:feldexa_application/src/review/apply_signature.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

SignatureDraft _draft({
  required Size canvas,
  required List<List<Offset>> strokes,
}) {
  return SignatureDraft(
    strokes: <SignatureStroke>[
      for (final List<Offset> points in strokes)
        SignatureStroke(points: points),
    ],
    canvasSize: canvas,
  );
}

void main() {
  testWidgets('encodes a real PNG at the drawn size', (WidgetTester tester) async {
    final SignatureDraft draft = _draft(
      canvas: const Size(300, 120),
      strokes: <List<Offset>>[
        <Offset>[const Offset(20, 60), const Offset(120, 30)],
        <Offset>[const Offset(60, 90)],
      ],
    );

    final SignaturePng? png = await tester.runAsync<SignaturePng?>(
      () => encodeSignaturePng(draft),
    );

    expect(png, isNotNull);
    expect(png!.widthPx, 300);
    expect(png.heightPx, 120);
    expect(
      png.bytes.sublist(0, 8),
      orderedEquals(<int>[137, 80, 78, 71, 13, 10, 26, 10]),
    );
    final img.Image decoded = img.decodePng(png.bytes)!;
    expect(decoded.width, 300);
    expect(decoded.height, 120);
  });

  testWidgets('never upscales and caps the long edge at 1024 px', (
    WidgetTester tester,
  ) async {
    final SignaturePng? small = await tester.runAsync<SignaturePng?>(
      () => encodeSignaturePng(
        _draft(
          canvas: const Size(120, 40),
          strokes: <List<Offset>>[
            <Offset>[const Offset(10, 20), const Offset(80, 20)],
          ],
        ),
      ),
    );
    expect(small!.widthPx, 120);
    expect(small.heightPx, 40);

    final SignaturePng? large = await tester.runAsync<SignaturePng?>(
      () => encodeSignaturePng(
        _draft(
          canvas: const Size(2400, 1200),
          strokes: <List<Offset>>[
            <Offset>[const Offset(100, 600), const Offset(2000, 600)],
          ],
        ),
      ),
    );
    expect(large!.widthPx, signaturePngMaxEdgePx);
    expect(large.heightPx, 512);
  });

  testWidgets('paints only ink on a transparent background', (
    WidgetTester tester,
  ) async {
    final SignaturePng? png = await tester.runAsync<SignaturePng?>(
      () => encodeSignaturePng(
        _draft(
          canvas: const Size(200, 100),
          strokes: <List<Offset>>[
            <Offset>[const Offset(20, 50), const Offset(180, 50)],
          ],
        ),
      ),
    );
    final img.Image decoded = img.decodePng(png!.bytes)!;

    // A corner is background; the middle row of the stroke is ink.
    expect(decoded.getPixel(1, 1).a, 0);
    expect(decoded.getPixel(decoded.width - 2, decoded.height - 2).a, 0);
    int opaque = 0;
    for (int x = 0; x < decoded.width; x++) {
      for (int y = 0; y < decoded.height; y++) {
        final img.Pixel pixel = decoded.getPixel(x, y);
        if (pixel.a > 0) {
          opaque++;
          expect(pixel.r, lessThan(128));
          expect(pixel.g, lessThan(128));
          expect(pixel.b, lessThan(128));
        }
      }
    }
    expect(opaque, greaterThan(0));
    expect(opaque, lessThan(decoded.width * decoded.height));
  });

  testWidgets('is deterministic and independent per call', (
    WidgetTester tester,
  ) async {
    final SignatureDraft draft = _draft(
      canvas: const Size(160, 80),
      strokes: <List<Offset>>[
        <Offset>[const Offset(10, 40), const Offset(60, 20)],
        <Offset>[const Offset(100, 60), const Offset(150, 30)],
      ],
    );
    final SignaturePng? first = await tester.runAsync<SignaturePng?>(
      () => encodeSignaturePng(draft),
    );
    final SignaturePng? second = await tester.runAsync<SignaturePng?>(
      () => encodeSignaturePng(draft),
    );
    expect(first!.bytes, orderedEquals(second!.bytes));
    expect(identical(first.bytes, second.bytes), isFalse);

    final SignaturePng? other = await tester.runAsync<SignaturePng?>(
      () => encodeSignaturePng(
        _draft(
          canvas: const Size(160, 80),
          strokes: <List<Offset>>[
            <Offset>[const Offset(10, 20), const Offset(150, 60)],
          ],
        ),
      ),
    );
    expect(other!.bytes, isNot(orderedEquals(first.bytes)));
  });

  testWidgets('an unusable canvas yields no image', (WidgetTester tester) async {
    expect(
      await tester.runAsync<SignaturePng?>(
        () => encodeSignaturePng(
          _draft(canvas: Size.zero, strokes: const <List<Offset>>[]),
        ),
      ),
      isNull,
    );
    expect(
      await tester.runAsync<SignaturePng?>(
        () => encodeSignaturePng(
          _draft(
            canvas: const Size(double.nan, 40),
            strokes: const <List<Offset>>[],
          ),
        ),
      ),
      isNull,
    );
  });

  testWidgets('an empty draft stays a valid, fully transparent image', (
    WidgetTester tester,
  ) async {
    final SignaturePng? png = await tester.runAsync<SignaturePng?>(
      () => encodeSignaturePng(
        _draft(canvas: const Size(64, 32), strokes: const <List<Offset>>[]),
      ),
    );
    expect(png, isNotNull);
    final img.Image decoded = img.decodePng(png!.bytes)!;
    for (int x = 0; x < decoded.width; x++) {
      for (int y = 0; y < decoded.height; y++) {
        expect(decoded.getPixel(x, y).a, 0);
      }
    }
  });

  testWidgets('the derived asset digest equals package:crypto', (
    WidgetTester tester,
  ) async {
    final SignaturePng? png = await tester.runAsync<SignaturePng?>(
      () => encodeSignaturePng(
        _draft(
          canvas: const Size(220, 90),
          strokes: <List<Offset>>[
            <Offset>[const Offset(15, 45), const Offset(120, 25)],
          ],
        ),
      ),
    );
    final SignatureAsset asset = SignatureAsset.fromPng(
      bytes: Uint8List.fromList(png!.bytes),
      widthPx: png.widthPx,
      heightPx: png.heightPx,
    );
    expect(
      asset.sha256,
      crypto.sha256.convert(png.bytes).toString(),
      reason: 'the application command digest must match package:crypto',
    );
  });
}
