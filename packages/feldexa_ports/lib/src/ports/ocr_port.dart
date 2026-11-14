// T013 `OcrPort` interface.
//
// Owner: `packages/feldexa_ports/lib/src/ports/ocr_port.dart` (T013).
// Normative source: `contracts/ports.md` §2.3.
//
// Recognition is fully on-device; the adapter must not open sockets. OCR
// failure is recoverable: the pipeline continues with geometry-only detection
// and lowers confidence. OCR text is document content and is never logged.

import '../descriptor.dart';
import '../dto/ocr_dto.dart';

/// On-device text recognition over an analysis raster
/// (`contracts/ports.md` §2.3).
abstract interface class OcrPort implements PlatformCapability {
  /// Recognizes text blocks in [request].
  ///
  /// Output rectangles use the same page geometry as `PageRasterPort`.
  Future<List<OcrBlock>> recognize(OcrRequest request);

  /// Releases recognition resources held by the adapter.
  Future<void> dispose();
}
