// T013 `OcrPort` request and result DTOs.
//
// Owner: `packages/feldexa_ports/lib/src/dto/ocr_dto.dart` (T013).
// Normative source: `contracts/ports.md` §2.3 and §2.10.
//
// The canonical `Rect` used for source-page display points comes from
// `feldexa_core`; this file must not redeclare it. OCR text is document content
// and is never echoed in an error or in `toString()`.

import 'package:feldexa_core/feldexa_core.dart';

import 'raster_dto.dart';
import 'validation.dart';

/// One OCR request (`contracts/ports.md` §2.3).
final class OcrRequest {
  /// Creates an OCR request.
  ///
  /// [pageIndex] must be non-negative and [languageHint] a compact language tag
  /// such as `de`. Production always passes `de`. Invalid values throw a safe
  /// [ArgumentError].
  factory OcrRequest({
    required RasterImage image,
    required int pageIndex,
    required String languageHint,
  }) {
    final int checkedPageIndex = requireNonNegativeInt(pageIndex, 'pageIndex');
    final String checkedLanguage = requireLanguageTag(
      languageHint,
      'languageHint',
    );
    return OcrRequest._(
      image: image,
      pageIndex: checkedPageIndex,
      languageHint: checkedLanguage,
    );
  }

  const OcrRequest._({
    required this.image,
    required this.pageIndex,
    required this.languageHint,
  });

  /// The analysis raster to recognize.
  final RasterImage image;

  /// Zero-based page index of [image].
  final int pageIndex;

  /// Recognition language hint, `de` in production.
  final String languageHint;

  @override
  String toString() {
    return 'OcrRequest(pageIndex: $pageIndex, languageHint: $languageHint)';
  }
}

/// One recognized text line (`contracts/ports.md` §2.10).
///
/// [rect] is in source-page display points and [confidence] is a best-effort
/// value in the inclusive 0–1 interval.
final class OcrLine {
  /// Creates a recognized line.
  ///
  /// [confidence] must be finite and between 0 and 1. Invalid values throw a
  /// safe [ArgumentError] that does not echo the line text.
  factory OcrLine({
    required Rect rect,
    required String text,
    required double confidence,
  }) {
    final double checkedConfidence = requireUnitInterval(
      confidence,
      'confidence',
    );
    return OcrLine._(rect: rect, text: text, confidence: checkedConfidence);
  }

  const OcrLine._({
    required this.rect,
    required this.text,
    required this.confidence,
  });

  /// Bounding rectangle in source-page display points.
  final Rect rect;

  /// Recognized text; document content, never logged.
  final String text;

  /// Best-effort confidence in the inclusive 0–1 interval.
  final double confidence;

  @override
  String toString() {
    return 'OcrLine(textLength: ${text.length}, confidence: $confidence)';
  }
}

/// One recognized text block (`contracts/ports.md` §2.3).
///
/// [rect] is in source-page display points, and [lines] refines the block
/// without changing its text.
final class OcrBlock {
  /// Creates a recognized block.
  ///
  /// [confidence] must be finite and between 0 and 1. Invalid values throw a
  /// safe [ArgumentError] that does not echo block text.
  factory OcrBlock({
    required Rect rect,
    required String text,
    required double confidence,
    Iterable<OcrLine> lines = const <OcrLine>[],
  }) {
    final double checkedConfidence = requireUnitInterval(
      confidence,
      'confidence',
    );
    return OcrBlock._(
      rect: rect,
      text: text,
      confidence: checkedConfidence,
      lines: freezeList<OcrLine>(lines),
    );
  }

  const OcrBlock._({
    required this.rect,
    required this.text,
    required this.confidence,
    required this.lines,
  });

  /// Bounding rectangle in source-page display points.
  final Rect rect;

  /// Recognized block text; document content, never logged.
  final String text;

  /// Best-effort confidence in the inclusive 0–1 interval.
  final double confidence;

  /// Recognized lines inside the block, in reading order.
  final List<OcrLine> lines;

  @override
  String toString() {
    return 'OcrBlock(textLength: ${text.length}, lines: ${lines.length}, '
        'confidence: $confidence)';
  }
}
