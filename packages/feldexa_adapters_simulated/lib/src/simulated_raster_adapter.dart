// T028 SIMULATED page-raster adapter.
//
// The Web development surface substitutes a deterministic raster for a real
// PDFium render. The substitute keeps the contract-relevant properties: the
// pixel dimensions follow `displaySize × scale` (clamped by
// `maxDimensionPx`), the layout matches the requested format, and the bytes are
// reproducible for the same request. It intentionally does not claim visual
// fidelity to the source PDF; that is `SIMULATED`-only development behavior.
//
// Every raster registers its deterministic SHA-256 fingerprint with the shared
// backend so the pre-authored OCR adapter can find the fixture page that
// produced it. A raster the adapter did not produce cannot be recognized.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';

import 'simulated_backend.dart';
import 'simulated_contract.dart';
import 'simulated_digest.dart';

/// Deterministic `PageRasterPort` substitute.
final class SimulatedPageRasterAdapter implements PageRasterPort {
  /// Creates the raster adapter over [backend].
  SimulatedPageRasterAdapter({required this.backend});

  /// Shared simulated backend.
  final SimulatedBackend backend;

  static final CapabilityDescriptor _descriptor = simulatedDescriptor(
    kind: CapabilityKind.pageRaster,
    adapterId: simulatedRasterAdapterId,
    supportedFeatures: const <String>[
      'rgba8888',
      'gray8',
      'deterministic',
      'max-dimension-cap',
    ],
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  /// Evidence label carried by every rendered image.
  CapabilityEvidence get evidence => _descriptor.evidence;

  @override
  Future<PageGeometry> pageDimensions(String sourceId, int pageIndex) async {
    if (pageIndex < 0) {
      throw ArgumentError('pageIndex must be at least 0');
    }
    final SimulatedStagedSource? source = backend.stagedSource(sourceId);
    if (source == null || pageIndex >= source.pageCount) {
      throw RenderException(pageIndex: pageIndex);
    }
    return source.pages[pageIndex];
  }

  @override
  Future<RasterImage> renderPage(RasterRequest request) async {
    final SimulatedStagedSource? source = backend.stagedSource(
      request.sourceId,
    );
    if (source == null || request.pageIndex >= source.pageCount) {
      throw RenderException(pageIndex: request.pageIndex);
    }
    final PageGeometry geometry = source.pages[request.pageIndex];
    final Size display = geometry.displaySize;

    final _PixelSize pixels = _pixelSize(
      display,
      request.scale,
      request.maxDimensionPx,
    );
    final Uint8List bytes = _renderBytes(
      sourceId: request.sourceId,
      pageIndex: request.pageIndex,
      width: pixels.width,
      height: pixels.height,
      format: request.format,
    );
    backend.registerRasterOrigin(
      sha256Hex(bytes),
      SimulatedRasterOrigin(
        sourceId: request.sourceId,
        fixtureId: source.fixtureId,
        pageIndex: request.pageIndex,
        width: pixels.width,
        height: pixels.height,
        format: request.format,
      ),
    );

    return RasterImage(
      bytes: bytes,
      width: pixels.width,
      height: pixels.height,
      bytesPerRow: pixels.width * request.format.bytesPerPixel,
      format: request.format,
      evidence: evidence,
    );
  }

  @override
  Future<void> evict(String sourceId) async {
    backend.forgetRasterOrigins(sourceId);
  }

  /// Computes pixel dimensions without exceeding [maxDimensionPx].
  static _PixelSize _pixelSize(Size display, double scale, int maxDimensionPx) {
    int width = math.max(1, (display.width * scale).floor());
    int height = math.max(1, (display.height * scale).floor());
    final int largest = math.max(width, height);
    if (largest > maxDimensionPx) {
      final double factor = maxDimensionPx / largest;
      width = math.max(1, (width * factor).floor());
      height = math.max(1, (height * factor).floor());
    }
    return _PixelSize(width, height);
  }

  /// Fills a deterministic page placeholder.
  ///
  /// The page is white with a 1-pixel gray frame and a 16×16 marker whose
  /// values derive from the request. The marker makes two renders of different
  /// pages distinguishable without relying on randomness or a clock.
  static Uint8List _renderBytes({
    required String sourceId,
    required int pageIndex,
    required int width,
    required int height,
    required RasterFormat format,
  }) {
    final int bytesPerRow = width * format.bytesPerPixel;
    final Uint8List bytes = Uint8List(bytesPerRow * height);
    if (format == RasterFormat.gray8) {
      bytes.fillRange(0, bytes.length, 0xFF);
    } else {
      // Opaque white RGBA.
      for (int offset = 0; offset < bytes.length; offset += 4) {
        bytes[offset] = 0xFF;
        bytes[offset + 1] = 0xFF;
        bytes[offset + 2] = 0xFF;
        bytes[offset + 3] = 0xFF;
      }
    }

    final List<int> marker = _hexToBytes(
      sha256HexOfUtf8('$sourceId|$pageIndex|$width|$height|${format.name}'),
    );

    void setPixel(int x, int y, int r, int g, int b) {
      final int offset = y * bytesPerRow + x * format.bytesPerPixel;
      if (format == RasterFormat.gray8) {
        // Luma approximation; marker and frame are already grayscale.
        bytes[offset] = r;
      } else {
        bytes[offset] = r;
        bytes[offset + 1] = g;
        bytes[offset + 2] = b;
        bytes[offset + 3] = 0xFF;
      }
    }

    // 1-pixel frame.
    for (int x = 0; x < width; x++) {
      setPixel(x, 0, 0x80, 0x80, 0x80);
      setPixel(x, height - 1, 0x80, 0x80, 0x80);
    }
    for (int y = 0; y < height; y++) {
      setPixel(0, y, 0x80, 0x80, 0x80);
      setPixel(width - 1, y, 0x80, 0x80, 0x80);
    }

    // 16x16 deterministic marker in the top-left interior.
    final int markerWidth = math.min(16, math.max(0, width - 2));
    final int markerHeight = math.min(16, math.max(0, height - 2));
    for (int y = 0; y < markerHeight; y++) {
      for (int x = 0; x < markerWidth; x++) {
        final int value = marker[(y * markerWidth + x) % marker.length];
        setPixel(x + 1, y + 1, value, value, value);
      }
    }
    return bytes;
  }

  static List<int> _hexToBytes(String hex) {
    final List<int> result = <int>[];
    for (int index = 0; index + 1 < hex.length; index += 2) {
      result.add(int.parse(hex.substring(index, index + 2), radix: 16));
    }
    return result;
  }
}

final class _PixelSize {
  const _PixelSize(this.width, this.height);

  final int width;
  final int height;
}
