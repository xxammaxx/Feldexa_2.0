// T027 Android `PageRasterPort` backed by pdfrx/PDFium.
//
// The encrypted source bytes are already released by the store only for the
// open document; this adapter never accepts a path or opens a file. Production
// composition supplies [SourceBytesResolver] from the loaded document cache.
// No raster bytes are written to disk or logged.

import 'dart:typed_data';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pdfrx/pdfrx.dart';

// A private field cannot use an initializing formal with a public named
// parameter; the explicit initializer is intentional.
// ignore_for_file: prefer_initializing_formals

/// Resolves the decrypted source bytes for one immutable `sourceId`.
typedef SourceBytesResolver = Future<Uint8List?> Function(String sourceId);

/// Android `PageRasterPort` using the bundled PDFium build through pdfrx.
final class AndroidPdfrxRasterClient implements PageRasterPort {
  AndroidPdfrxRasterClient({
    required SourceBytesResolver sourceBytes,
    CapabilityEvidence? evidence,
  }) : _sourceBytes = sourceBytes,
       _evidence =
           evidence ??
           CapabilityEvidence.android(adapterId: 'android.pdfium.v1');

  final SourceBytesResolver _sourceBytes;
  final CapabilityEvidence _evidence;
  final Map<String, PdfDocument> _documents = <String, PdfDocument>{};
  final Map<RasterImage, ({String sourceId, double widthPt, double heightPt})>
  _pageSizes =
      <RasterImage, ({String sourceId, double widthPt, double heightPt})>{};

  static final CapabilityDescriptor _descriptor = CapabilityDescriptor(
    kind: CapabilityKind.pageRaster,
    adapterId: 'android.pdfium.v1',
    version: '1',
    isSimulated: false,
    evidence: CapabilityEvidence.android(adapterId: 'android.pdfium.v1'),
    supportedFeatures: const <String>[
      'pdfium',
      'rgba8888',
      'gray8',
      'source-point-geometry',
      'bounded-memory',
    ],
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  CapabilityEvidence get evidence => _evidence;

  /// Page display size used to render [image], for the OCR page-size seam.
  ({double widthPt, double heightPt})? pageSizeOf(RasterImage image) {
    final ({String sourceId, double widthPt, double heightPt})? entry =
        _pageSizes[image];
    return entry == null
        ? null
        : (widthPt: entry.widthPt, heightPt: entry.heightPt);
  }

  /// Records one page size for a test without opening PDFium.
  @visibleForTesting
  void debugRememberPageSize(
    String sourceId,
    RasterImage image, {
    required double widthPt,
    required double heightPt,
  }) {
    _pageSizes[image] = (
      sourceId: sourceId,
      widthPt: widthPt,
      heightPt: heightPt,
    );
  }

  @override
  Future<PageGeometry> pageDimensions(String sourceId, int pageIndex) async {
    final PdfDocument document = await _open(sourceId);
    final PdfPage page = _page(document, pageIndex);
    return PageGeometry(mediaBox: Rect.fromLTWH(0, 0, page.width, page.height));
  }

  @override
  Future<RasterImage> renderPage(RasterRequest request) async {
    PdfDocument? document;
    PdfImage? image;
    try {
      document = await _open(request.sourceId);
      final PdfPage page = _page(document, request.pageIndex);
      double fullWidth = page.width * request.scale;
      double fullHeight = page.height * request.scale;
      final double longest = fullWidth > fullHeight ? fullWidth : fullHeight;
      if (longest > request.maxDimensionPx) {
        final double factor = request.maxDimensionPx / longest;
        fullWidth *= factor;
        fullHeight *= factor;
      }
      final int width = fullWidth.round().clamp(1, request.maxDimensionPx);
      final int height = fullHeight.round().clamp(1, request.maxDimensionPx);
      image = await page.render(
        fullWidth: width.toDouble(),
        fullHeight: height.toDouble(),
      );
      if (image == null) {
        throw RenderException(pageIndex: request.pageIndex);
      }
      final Uint8List bgra = image.pixels;
      final int expected = width * height * 4;
      if (bgra.length < expected) {
        throw RenderException(pageIndex: request.pageIndex);
      }
      final Uint8List bytes;
      final int channels;
      if (request.format == RasterFormat.rgba8888) {
        channels = 4;
        bytes = Uint8List(expected);
        for (int index = 0; index < expected; index += 4) {
          final int blue = bgra[index];
          final int green = bgra[index + 1];
          final int red = bgra[index + 2];
          final int alpha = bgra[index + 3];
          bytes[index] = red;
          bytes[index + 1] = green;
          bytes[index + 2] = blue;
          bytes[index + 3] = alpha;
        }
      } else {
        channels = 1;
        bytes = Uint8List(width * height);
        for (
          int pixel = 0, source = 0, target = 0;
          pixel < width * height;
          pixel++, source += 4, target++
        ) {
          final int blue = bgra[source];
          final int green = bgra[source + 1];
          final int red = bgra[source + 2];
          final int alpha = bgra[source + 3];
          // Rec. 601 luma on the white PDF background.
          final int luminance = (0.299 * red + 0.587 * green + 0.114 * blue)
              .round();
          final int blended = alpha == 255
              ? luminance
              : ((luminance * alpha + 255 * (255 - alpha)) ~/ 255);
          bytes[target] = blended.clamp(0, 255);
        }
      }
      final RasterImage result = RasterImage(
        bytes: bytes,
        width: width,
        height: height,
        bytesPerRow: width * channels,
        format: request.format,
        evidence: _evidence,
      );
      _pageSizes[result] = (
        sourceId: request.sourceId,
        widthPt: page.width,
        heightPt: page.height,
      );
      return result;
    } catch (error) {
      if (error is RenderException) rethrow;
      throw RenderException(pageIndex: request.pageIndex);
    } finally {
      image?.dispose();
    }
  }

  @override
  Future<void> evict(String sourceId) async {
    final PdfDocument? document = _documents.remove(sourceId);
    if (document != null) {
      await document.dispose();
    }
    // Page-size entries belong to the source that produced them. Evict only
    // that source: other cached documents must keep their OCR geometry.
    _pageSizes.removeWhere(
      (
        RasterImage _,
        ({String sourceId, double widthPt, double heightPt}) entry,
      ) => entry.sourceId == sourceId,
    );
  }

  Future<PdfDocument> _open(String sourceId) async {
    final PdfDocument? cached = _documents[sourceId];
    if (cached != null) return cached;
    final Uint8List? bytes = await _sourceBytes(sourceId);
    if (bytes == null || bytes.isEmpty) {
      throw RenderException(pageIndex: 0);
    }
    try {
      final PdfDocument document = await PdfDocument.openData(
        bytes,
        sourceName: sourceId,
      );
      _documents[sourceId] = document;
      return document;
    } catch (error) {
      throw RenderException(pageIndex: 0);
    }
  }

  PdfPage _page(PdfDocument document, int pageIndex) {
    if (pageIndex < 0 || pageIndex >= document.pages.length) {
      throw RenderException(pageIndex: pageIndex < 0 ? 0 : pageIndex);
    }
    return document.pages[pageIndex];
  }
}
