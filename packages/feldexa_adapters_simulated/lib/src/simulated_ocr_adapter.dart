// T028 SIMULATED OCR adapter.
//
// `research.md` D-16: OCR returns the pre-authored blocks from the fixture's
// expected-OCR document instead of running live recognition in the browser.
// That isolates UI validation from detector variance and keeps the result
// deterministic.
//
// The adapter only recognizes a raster that the simulated page-raster adapter
// produced: it looks the raster's SHA-256 fingerprint up in the shared backend
// and returns the expected blocks for that fixture page. Any other input is a
// recoverable `OcrUnavailableException` (`REC-001`) so the pipeline can fall
// back to geometry-only detection (`contracts/ports.md` §2.3).
//
// OCR text is document content. It is returned to the caller and never logged.
library;

import 'package:feldexa_ports/feldexa_ports.dart';

import 'simulated_backend.dart';
import 'simulated_contract.dart';
import 'simulated_digest.dart';
import 'simulated_fixtures.dart';

/// Fixture-backed deterministic `OcrPort`.
final class SimulatedOcrAdapter implements OcrPort {
  /// Creates the OCR adapter.
  SimulatedOcrAdapter({required this.backend, required this.catalog});

  /// Shared simulated backend.
  final SimulatedBackend backend;

  /// Validated fixture catalogue.
  final SimulatedFixtureCatalog catalog;

  bool _disposed = false;

  static final CapabilityDescriptor _descriptor = simulatedDescriptor(
    kind: CapabilityKind.ocr,
    adapterId: simulatedOcrAdapterId,
    supportedFeatures: const <String>['fixture-expected-ocr', 'german'],
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  /// Evidence label carried by this adapter.
  CapabilityEvidence get evidence => _descriptor.evidence;

  /// Whether [dispose] has released the adapter.
  bool get isDisposed => _disposed;

  @override
  Future<List<OcrBlock>> recognize(OcrRequest request) async {
    if (_disposed) {
      throw OcrUnavailableException();
    }
    if (request.languageHint.toLowerCase() != 'de') {
      // The committed expected OCR is German-only. A different hint cannot be
      // served from the fixture catalogue, so it stays a recoverable failure.
      throw OcrUnavailableException();
    }
    final SimulatedRasterOrigin? origin = backend.rasterOrigin(
      sha256Hex(request.image.bytes),
    );
    if (origin == null || origin.pageIndex != request.pageIndex) {
      throw OcrUnavailableException();
    }
    final SimulatedFixture fixture;
    try {
      fixture = catalog.fixture(origin.fixtureId);
    } on ArgumentError {
      throw OcrUnavailableException();
    }
    if (origin.pageIndex >= fixture.expectedOcr.length) {
      throw OcrUnavailableException();
    }
    final SimulatedOcrPage page = fixture.expectedOcr[origin.pageIndex];
    return List<OcrBlock>.unmodifiable(
      page.blocks.map((SimulatedOcrBlock block) {
        return OcrBlock(
          rect: block.rect,
          text: block.text,
          confidence: block.confidence,
          lines: block.lines.map((SimulatedOcrLine line) {
            return OcrLine(
              rect: line.rect,
              text: line.text,
              confidence: line.confidence,
            );
          }),
        );
      }),
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}
