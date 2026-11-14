// T013 `PageRasterPort` interface.
//
// Owner: `packages/feldexa_ports/lib/src/ports/page_raster_port.dart` (T013).
// Normative source: `contracts/ports.md` §2.2.
//
// Implementations live only in adapter packages. Analysis uses `gray8` at
// 200 dpi equivalent; the UI uses RGBA. A render failure maps to
// `RenderException` and never mutates stored data.

import 'package:feldexa_core/feldexa_core.dart';

import '../descriptor.dart';
import '../dto/raster_dto.dart';

/// Reports page geometry and renders source pages to pixels
/// (`contracts/ports.md` §2.2).
abstract interface class PageRasterPort implements PlatformCapability {
  /// Returns the display geometry of one source page.
  Future<PageGeometry> pageDimensions(String sourceId, int pageIndex);

  /// Renders one source page according to [request].
  ///
  /// Rendering is byte-faithful to the source page; no rotation or crop beyond
  /// PDFium's standard rendering of the declared display box.
  Future<RasterImage> renderPage(RasterRequest request);

  /// Releases cached page and document handles for [sourceId].
  ///
  /// Decrypted bytes are never cached outside process memory.
  Future<void> evict(String sourceId);
}
