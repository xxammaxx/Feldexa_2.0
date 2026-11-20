// ignore_for_file: implementation_imports

// Phase A US2 integration tests for the production recognition pipeline.
//
// These are host-VM tests (evidence class NONE). They pin the issue #217
// Phase A use case in
// `packages/feldexa_application/lib/src/recognition/analyze_document.dart`
// against `contracts/recognition-output.md` §1–§6, `contracts/ports.md`
// §2.2/§2.3, FR-011…FR-020, FR-083, and FR-085:
//   * a synthetic underline page with an OCR label yields the expected type,
//     label, confidence, cues, and one validated suggestion;
//   * ids and order are deterministic, including shuffled page input;
//   * conflicts are symmetric and both candidates are retained;
//   * OCR absence/failure is recoverable, geometry-only, and page-isolated;
//   * OCR receives the tight source object unchanged and a rebuilt tight
//     width-by-height raster only when the source has row padding;
//   * raster failures isolate one page and mismatch is `rasterization`, while
//     post-render strip/analysis failures are `internal`;
//   * detector preconditions are `internal`; only an explicit structure signal
//     preserves `unsupported_structure`;
//   * same-family cues collapse to one `cueAgreement`, partial drafts are
//     counted on failure, and rotation propagates into the envelope;
//   * cancellation excludes only the matching page and never fails it;
//   * timings are non-negative, envelopes round-trip through T057, no label
//     text is logged, and caller lists are never mutated.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:feldexa_application/src/recognition/analyze_document.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:feldexa_recognition/src/page_analysis.dart';
import 'package:feldexa_recognition/src/raster.dart';
import 'package:feldexa_recognition/src/suggestion_schema.dart';
import 'package:flutter_test/flutter_test.dart';

const double _pageWidthPt = 144;
const double _pageHeightPt = 144;
const int _rasterWidth = 400;
const int _rasterHeight = 400;
const String _sourceId = '11111111-1111-4111-8111-111111111111';
const String _analysisRunId = '22222222-2222-4222-8222-222222222222';
const String _evidenceClass = 'simulated';

/// A deterministic synthetic grayscale page builder.
///
/// 144 x 144 pt maps to exactly 400 x 400 px at the contract's 200 DPI
/// analysis scale (`coordinates-and-geometry.md` §4).
final class _Canvas {
  _Canvas({int background = 255})
    : _bytes = Uint8List(_rasterWidth * _rasterHeight) {
    _bytes.fillRange(0, _bytes.length, background);
  }

  final Uint8List _bytes;

  void fillRect(int left, int top, int right, int bottom, {int value = 0}) {
    for (int y = top; y < bottom; y++) {
      for (int x = left; x < right; x++) {
        _bytes[y * _rasterWidth + x] = value;
      }
    }
  }

  Uint8List build() => Uint8List.fromList(_bytes);
}

final class _RasterSpec {
  _RasterSpec({
    required this.bytes,
    this.width = _rasterWidth,
    this.bytesPerRow,
    this.format = RasterFormat.gray8,
    this.fail = false,
  });

  final Uint8List bytes;
  final int width;
  final int? bytesPerRow;
  final RasterFormat format;
  final bool fail;
}

final CapabilityDescriptor _rasterDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.pageRaster,
  adapterId: 'test.raster.v1',
  version: '1',
  isSimulated: false,
  evidence: CapabilityEvidence(
    evidenceClass: EvidenceClass.none,
    adapterId: 'test.raster.v1',
  ),
);

final CapabilityDescriptor _ocrDescriptor = CapabilityDescriptor(
  kind: CapabilityKind.ocr,
  adapterId: 'test.ocr.v1',
  version: '1',
  isSimulated: false,
  evidence: CapabilityEvidence(
    evidenceClass: EvidenceClass.none,
    adapterId: 'test.ocr.v1',
  ),
);

final class _FakeRaster implements PageRasterPort {
  _FakeRaster(this.specs);

  final Map<int, _RasterSpec> specs;
  final List<RasterRequest> requests = <RasterRequest>[];
  final List<RasterImage> renderedImages = <RasterImage>[];

  @override
  CapabilityDescriptor get descriptor => _rasterDescriptor;

  @override
  Future<PageGeometry> pageDimensions(String sourceId, int pageIndex) async {
    return PageGeometry(
      mediaBox: Rect.fromLTWH(0, 0, _pageWidthPt, _pageHeightPt),
    );
  }

  @override
  Future<RasterImage> renderPage(RasterRequest request) async {
    requests.add(request);
    final _RasterSpec spec = specs[request.pageIndex]!;
    if (spec.fail) {
      throw RenderException(pageIndex: request.pageIndex);
    }
    final RasterImage image = RasterImage(
      bytes: spec.bytes,
      width: spec.width,
      height: _rasterHeight,
      bytesPerRow: spec.bytesPerRow ?? spec.width * spec.format.bytesPerPixel,
      format: spec.format,
      evidence: CapabilityEvidence(
        evidenceClass: EvidenceClass.none,
        adapterId: 'test.raster.v1',
      ),
    );
    renderedImages.add(image);
    return image;
  }

  @override
  Future<void> evict(String sourceId) async {}
}

final class _FakeOcr implements OcrPort {
  _FakeOcr({
    this.blocksByPage = const <int, List<OcrBlock>>{},
    this.failingPages = const <int>{},
  });

  final Map<int, List<OcrBlock>> blocksByPage;
  final Set<int> failingPages;
  final List<OcrRequest> requests = <OcrRequest>[];

  @override
  CapabilityDescriptor get descriptor => _ocrDescriptor;

  @override
  Future<List<OcrBlock>> recognize(OcrRequest request) async {
    requests.add(request);
    if (failingPages.contains(request.pageIndex)) {
      throw OcrUnavailableException();
    }
    return blocksByPage[request.pageIndex] ?? const <OcrBlock>[];
  }

  @override
  Future<void> dispose() async {}
}

DocumentAnalysisPage _page([int index = 0]) {
  return DocumentAnalysisPage(
    pageIndex: index,
    pageSizePt: PageDisplaySize(_pageWidthPt, _pageHeightPt),
  );
}

DocumentAnalysisRequest _request({
  required PageRasterPort raster,
  OcrPort? ocr,
  List<DocumentAnalysisPage>? pages,
}) {
  return DocumentAnalysisRequest(
    sourceId: _sourceId,
    analysisRunId: _analysisRunId,
    pages: pages ?? <DocumentAnalysisPage>[_page()],
    evidenceClass: _evidenceClass,
    rasterPort: raster,
    ocrPort: ocr,
  );
}

_RasterSpec _underlinePage({int top = 200, int left = 100, int right = 200}) {
  final _Canvas canvas = _Canvas()
    ..fillRect(left, top, right, top + 2, value: 0);
  return _RasterSpec(bytes: canvas.build());
}

_RasterSpec _paddedRaster(_RasterSpec base, {int padding = 4}) {
  final int stride = _rasterWidth + padding;
  final Uint8List padded = Uint8List(stride * _rasterHeight);
  for (int row = 0; row < _rasterHeight; row++) {
    padded.setRange(
      row * stride,
      row * stride + _rasterWidth,
      base.bytes,
      row * _rasterWidth,
    );
    padded.fillRange(row * stride + _rasterWidth, (row + 1) * stride, 0xAB);
  }
  return _RasterSpec(bytes: padded, bytesPerRow: stride);
}

OcrBlock _ocrBlock({
  required String text,
  required Rect rect,
  double confidence = 0.95,
}) {
  return OcrBlock(
    rect: rect,
    text: text,
    confidence: confidence,
    lines: <OcrLine>[OcrLine(rect: rect, text: text, confidence: confidence)],
  );
}

Map<String, Object?> _evidence(Map<String, Object?> suggestion) {
  return suggestion['evidence']! as Map<String, Object?>;
}

Map<String, Object?> _rect(Map<String, Object?> suggestion) {
  return suggestion['rect']! as Map<String, Object?>;
}

void main() {
  test(
    'an underline page with a Betrag label yields one typed suggestion',
    () async {
      final _FakeRaster raster = _FakeRaster(<int, _RasterSpec>{
        0: _underlinePage(),
      });
      final _FakeOcr ocr = _FakeOcr(
        blocksByPage: <int, List<OcrBlock>>{
          0: <OcrBlock>[
            _ocrBlock(text: 'Betrag', rect: Rect.fromLTWH(10, 56, 22, 10)),
          ],
        },
      );

      final DocumentAnalysisResult result = await AnalyzeDocument.run(
        _request(raster: raster, ocr: ocr),
      );

      expect(result.analysisRunId, _analysisRunId);
      expect(result.isComplete, isTrue);
      expect(result.pages, hasLength(1));
      final FieldSuggestionSet set = result.pages.single;
      expect(set.isComplete, isTrue);
      expect(set.pageIndex, 0);
      expect(set.analysisRunId, _analysisRunId);
      expect(set.pageSizePt.width, _pageWidthPt);
      expect(set.pageSizePt.height, _pageHeightPt);
      expect(set.rotation, 0);
      expect(set.evidenceClass, _evidenceClass);
      expect(set.suggestions, hasLength(1));

      final Map<String, Object?> suggestion = set.suggestions.single;
      expect(suggestion['id'], 's_p0_0001');
      expect(suggestion['pageIndex'], 0);
      expect(_rect(suggestion), <String, Object?>{
        'x': 36.0,
        'y': 54.0,
        'width': 36.0,
        'height': 18.0,
      });
      expect(suggestion['proposedType'], 'number');
      expect(suggestion['confidence'], 0.93);
      expect(suggestion['uncertainty'], 0.07);
      expect(suggestion['labelText'], 'Betrag');
      expect(suggestion['conflictsWith'], isEmpty);
      expect(suggestion['resolution'], 'unresolved');

      final Map<String, Object?> evidence = _evidence(suggestion);
      expect(evidence['cues'], <String>[
        'keyword_betrag',
        'numeric_context',
        'ocr_alignment_right',
        'underline',
      ]);
      expect(evidence['cueAgreement'], 4);
      expect(evidence['skewDegrees'], 0.0);
      expect(evidence['contrast'], 'normal');
      expect(evidence['ocrUsed'], isTrue);

      final PageAnalysisTimings timings = set.timings;
      expect(timings.rasterMs, greaterThanOrEqualTo(0));
      expect(timings.ocrMs, greaterThanOrEqualTo(0));
      expect(timings.detectMs, greaterThanOrEqualTo(0));

      expect(raster.requests, hasLength(1));
      final RasterRequest renderRequest = raster.requests.single;
      expect(renderRequest.sourceId, _sourceId);
      expect(renderRequest.pageIndex, 0);
      expect(renderRequest.scale, closeTo(200 / 72, 1e-12));
      expect(renderRequest.format, RasterFormat.gray8);
      expect(ocr.requests, hasLength(1));
      expect(ocr.requests.single.pageIndex, 0);
      expect(ocr.requests.single.languageHint, 'de');
    },
  );

  test('page descriptors derive display size and rotation from geometry', () {
    final PageGeometry geometry = PageGeometry(
      mediaBox: Rect.fromLTWH(0, 0, 595, 842),
      rotation: 90,
    );

    final DocumentAnalysisPage page = DocumentAnalysisPage.fromGeometry(
      pageIndex: 3,
      geometry: geometry,
    );

    expect(page.pageIndex, 3);
    expect(page.rotation, 90);
    expect(page.pageSizePt.width, 842);
    expect(page.pageSizePt.height, 595);
  });

  test('page rotation propagates into the envelope', () async {
    final DocumentAnalysisPage page = DocumentAnalysisPage.fromGeometry(
      pageIndex: 0,
      geometry: PageGeometry(
        mediaBox: Rect.fromLTWH(0, 0, _pageWidthPt, _pageHeightPt),
        rotation: 90,
      ),
    );

    final DocumentAnalysisResult result = await AnalyzeDocument.run(
      _request(
        raster: _FakeRaster(<int, _RasterSpec>{0: _underlinePage()}),
        pages: <DocumentAnalysisPage>[page],
      ),
    );

    expect(result.pages.single.rotation, 90);
    expect(result.pages.single.isComplete, isTrue);
  });

  test('a duplicate page index is rejected before analysis', () {
    expect(
      () => _request(
        raster: _FakeRaster(<int, _RasterSpec>{0: _underlinePage()}),
        pages: <DocumentAnalysisPage>[_page(0), _page(0)],
      ),
      throwsArgumentError,
    );
  });

  test(
    'an empty page yields a complete envelope with no suggestions',
    () async {
      final DocumentAnalysisResult result = await AnalyzeDocument.run(
        _request(
          raster: _FakeRaster(<int, _RasterSpec>{
            0: _RasterSpec(bytes: _Canvas().build()),
          }),
        ),
      );

      final FieldSuggestionSet set = result.pages.single;
      expect(set.isComplete, isTrue);
      expect(set.failure, isNull);
      expect(set.suggestions, isEmpty);
      expect(set.timings.rasterMs, greaterThanOrEqualTo(0));
      expect(set.timings.ocrMs, greaterThanOrEqualTo(0));
      expect(set.timings.detectMs, greaterThanOrEqualTo(0));
    },
  );

  test('an OCR block without lines contributes its block text', () async {
    final OcrBlock block = OcrBlock(
      rect: Rect.fromLTWH(10, 56, 22, 10),
      text: 'Geburtsdatum',
      confidence: 0.9,
    );
    final DocumentAnalysisResult result = await AnalyzeDocument.run(
      _request(
        raster: _FakeRaster(<int, _RasterSpec>{0: _underlinePage()}),
        ocr: _FakeOcr(
          blocksByPage: <int, List<OcrBlock>>{
            0: <OcrBlock>[block],
          },
        ),
      ),
    );

    final Map<String, Object?> suggestion =
        result.pages.single.suggestions.single;
    expect(suggestion['proposedType'], 'date');
    expect(suggestion['labelText'], 'Geburtsdatum');
    expect(suggestion['confidence'], 0.81);
    expect(_evidence(suggestion)['cues'], <String>[
      'keyword_geburtsdatum',
      'ocr_alignment_right',
      'underline',
    ]);
  });

  test('two cues of one family count once in cueAgreement', () async {
    final DocumentAnalysisResult result = await AnalyzeDocument.run(
      _request(
        raster: _FakeRaster(<int, _RasterSpec>{0: _underlinePage()}),
        ocr: _FakeOcr(
          blocksByPage: <int, List<OcrBlock>>{
            0: <OcrBlock>[
              _ocrBlock(
                text: 'Betrag TT.MM.JJJJ',
                rect: Rect.fromLTWH(10, 56, 22, 10),
              ),
            ],
          },
        ),
      ),
    );

    final Map<String, Object?> suggestion =
        result.pages.single.suggestions.single;
    final Map<String, Object?> evidence = _evidence(suggestion);
    final List<String> cues = (evidence['cues']! as List<Object?>)
        .cast<String>();
    expect(cues, containsAll(<String>['numeric_context', 'date_context']));
    expect(cues, hasLength(5));
    expect(evidence['cueAgreement'], 4);
    expect(suggestion['proposedType'], 'number');
  });

  test('suggestion ids and order are deterministic', () async {
    final _Canvas canvas = _Canvas()
      ..fillRect(100, 100, 200, 102)
      ..fillRect(100, 200, 200, 202);
    final _RasterSpec spec = _RasterSpec(bytes: canvas.build());

    final DocumentAnalysisResult first = await AnalyzeDocument.run(
      _request(raster: _FakeRaster(<int, _RasterSpec>{0: spec})),
    );
    final DocumentAnalysisResult second = await AnalyzeDocument.run(
      _request(raster: _FakeRaster(<int, _RasterSpec>{0: spec})),
    );

    final List<Map<String, Object?>> suggestions =
        first.pages.single.suggestions;
    expect(suggestions.length, greaterThanOrEqualTo(2));
    expect(
      suggestions.map((Map<String, Object?> item) => item['id']).toList(),
      <String>['s_p0_0001', 's_p0_0002'],
    );
    expect(_rect(suggestions[0])['y'], 18.0);
    expect(_rect(suggestions[1])['y'], 54.0);
    expect(
      first.pages.single.canonicalJson(),
      second.pages.single.canonicalJson(),
    );
  });

  test('overlapping candidates keep a symmetric conflict graph', () async {
    final _Canvas canvas = _Canvas()
      ..fillRect(100, 200, 200, 202)
      ..fillRect(100, 210, 200, 212);

    final DocumentAnalysisResult result = await AnalyzeDocument.run(
      _request(
        raster: _FakeRaster(<int, _RasterSpec>{
          0: _RasterSpec(bytes: canvas.build()),
        }),
      ),
    );

    final List<Map<String, Object?>> suggestions =
        result.pages.single.suggestions;
    expect(suggestions, hasLength(2));
    final Map<String, Object?> first = suggestions[0];
    final Map<String, Object?> second = suggestions[1];
    expect(first['conflictsWith'], <String>[second['id']! as String]);
    expect(second['conflictsWith'], <String>[first['id']! as String]);
    expect(first['resolution'], 'unresolved');
    expect(second['resolution'], 'unresolved');
    expect(_evidence(first)['cues'], contains('underline'));
    expect(_evidence(second)['cues'], contains('underline'));
  });

  test(
    'a missing OCR port keeps the page complete and geometry-only',
    () async {
      final DocumentAnalysisResult result = await AnalyzeDocument.run(
        _request(raster: _FakeRaster(<int, _RasterSpec>{0: _underlinePage()})),
      );

      final FieldSuggestionSet set = result.pages.single;
      expect(set.isComplete, isTrue);
      expect(set.failure, isNull);
      final Map<String, Object?> suggestion = set.suggestions.single;
      expect(suggestion['labelText'], isNull);
      final Map<String, Object?> evidence = _evidence(suggestion);
      expect(evidence['ocrUsed'], isFalse);
      expect(evidence['cues'], <String>['underline']);
      expect(evidence['cueAgreement'], 1);
      expect(suggestion['confidence'], 0.32);
      expect(suggestion['uncertainty'], 0.68);
    },
  );

  test('a failing OCR port is recoverable and never fails the page', () async {
    final DocumentAnalysisResult result = await AnalyzeDocument.run(
      _request(
        raster: _FakeRaster(<int, _RasterSpec>{0: _underlinePage()}),
        ocr: _FakeOcr(failingPages: <int>{0}),
      ),
    );

    final FieldSuggestionSet set = result.pages.single;
    expect(set.isComplete, isTrue);
    expect(set.failure, isNull);
    expect(_evidence(set.suggestions.single)['ocrUsed'], isFalse);
  });

  test(
    'an OCR failure stays on its page while another page yields suggestions',
    () async {
      final _FakeOcr ocr = _FakeOcr(
        failingPages: <int>{0},
        blocksByPage: <int, List<OcrBlock>>{
          1: <OcrBlock>[
            _ocrBlock(text: 'Betrag', rect: Rect.fromLTWH(10, 56, 22, 10)),
          ],
        },
      );
      final DocumentAnalysisResult result = await AnalyzeDocument.run(
        _request(
          raster: _FakeRaster(<int, _RasterSpec>{
            0: _underlinePage(top: 100),
            1: _underlinePage(),
          }),
          ocr: ocr,
          pages: <DocumentAnalysisPage>[_page(0), _page(1)],
        ),
      );

      expect(result.pages, hasLength(2));
      final FieldSuggestionSet first = result.pages[0];
      final FieldSuggestionSet second = result.pages[1];
      expect(first.isComplete, isTrue);
      expect(first.isFailed, isFalse);
      expect(first.failure, isNull);
      expect(_evidence(first.suggestions.single)['ocrUsed'], isFalse);

      expect(second.isComplete, isTrue);
      expect(second.failure, isNull);
      final Map<String, Object?> suggestion = second.suggestions.single;
      expect(suggestion['labelText'], 'Betrag');
      expect(suggestion['proposedType'], 'number');
      expect(_evidence(suggestion)['ocrUsed'], isTrue);
      expect(ocr.requests.map((OcrRequest request) => request.pageIndex), <int>[
        0,
        1,
      ]);
    },
  );

  test('a render failure isolates exactly one page', () async {
    final _FakeRaster raster = _FakeRaster(<int, _RasterSpec>{
      0: _underlinePage(),
      1: _RasterSpec(
        bytes: Uint8List(_rasterWidth * _rasterHeight),
        fail: true,
      ),
    });

    final DocumentAnalysisResult result = await AnalyzeDocument.run(
      _request(
        raster: raster,
        pages: <DocumentAnalysisPage>[_page(0), _page(1)],
      ),
    );

    expect(result.pages, hasLength(2));
    final FieldSuggestionSet healthy = result.pages[0];
    final FieldSuggestionSet failed = result.pages[1];
    expect(healthy.pageIndex, 0);
    expect(healthy.isComplete, isTrue);
    expect(healthy.suggestions, hasLength(1));
    expect(failed.pageIndex, 1);
    expect(failed.isFailed, isTrue);
    expect(failed.suggestions, isEmpty);
    expect(failed.failure!.category, PageAnalysisFailure.rasterization);
    expect(failed.failure!.messageKey, 'PAGE-001');
    expect(failed.failure!.suggestionCount, 0);
    expect(failed.timings.rasterMs, greaterThanOrEqualTo(0));
    expect(raster.requests.map((RasterRequest r) => r.pageIndex), <int>[0, 1]);
  });

  test('a dimension mismatch is a rasterization failure', () async {
    final Uint8List bytes = Uint8List((_rasterWidth - 1) * _rasterHeight);
    final DocumentAnalysisResult result = await AnalyzeDocument.run(
      _request(
        raster: _FakeRaster(<int, _RasterSpec>{
          0: _RasterSpec(bytes: bytes, width: _rasterWidth - 1),
        }),
      ),
    );

    final FieldSuggestionSet set = result.pages.single;
    expect(set.isFailed, isTrue);
    expect(set.failure!.category, PageAnalysisFailure.rasterization);
    expect(set.failure!.messageKey, 'PAGE-001');
    expect(set.suggestions, isEmpty);
  });

  test('row padding is stripped before analysis', () async {
    final _RasterSpec base = _underlinePage();
    final _RasterSpec padded = _paddedRaster(base);

    final DocumentAnalysisResult result = await AnalyzeDocument.run(
      _request(raster: _FakeRaster(<int, _RasterSpec>{0: padded})),
    );

    final FieldSuggestionSet set = result.pages.single;
    expect(set.isComplete, isTrue);
    final Map<String, Object?> suggestion = set.suggestions.single;
    expect(_rect(suggestion), <String, Object?>{
      'x': 36.0,
      'y': 54.0,
      'width': 36.0,
      'height': 18.0,
    });
    expect(_evidence(suggestion)['ocrUsed'], isFalse);
    expect(suggestion['confidence'], 0.32);
  });

  test('OCR receives the tight source object unchanged and a rebuilt tight '
      'raster only when the source has row padding', () async {
    final _RasterSpec base = _underlinePage();

    // Tight source: the very object returned by the raster port must reach
    // OCR so an identity-keyed page-size resolver still resolves it.
    final _FakeRaster tightRaster = _FakeRaster(<int, _RasterSpec>{0: base});
    final _FakeOcr tightOcr = _FakeOcr();
    final DocumentAnalysisResult tightResult = await AnalyzeDocument.run(
      _request(raster: tightRaster, ocr: tightOcr),
    );
    expect(tightResult.pages.single.isComplete, isTrue);
    expect(tightOcr.requests, hasLength(1));
    final RasterImage tightImage = tightOcr.requests.single.image;
    expect(identical(tightImage, tightRaster.renderedImages.single), isTrue);
    expect(tightImage.width, _rasterWidth);
    expect(tightImage.height, _rasterHeight);
    expect(tightImage.format, RasterFormat.gray8);
    expect(tightImage.bytesPerRow, _rasterWidth);
    expect(tightImage.bytes, base.bytes);

    // Padded source: OCR still gets a tight width-by-height raster, but it
    // is deliberately a new object and keeps the source evidence.
    final _FakeRaster paddedRaster = _FakeRaster(<int, _RasterSpec>{
      0: _paddedRaster(base),
    });
    final _FakeOcr paddedOcr = _FakeOcr();
    final DocumentAnalysisResult paddedResult = await AnalyzeDocument.run(
      _request(raster: paddedRaster, ocr: paddedOcr),
    );
    expect(paddedResult.pages.single.isComplete, isTrue);
    expect(paddedOcr.requests, hasLength(1));
    final RasterImage paddedImage = paddedOcr.requests.single.image;
    expect(identical(paddedImage, paddedRaster.renderedImages.single), isFalse);
    expect(paddedImage.width, _rasterWidth);
    expect(paddedImage.height, _rasterHeight);
    expect(paddedImage.format, RasterFormat.gray8);
    expect(paddedImage.bytesPerRow, _rasterWidth);
    expect(paddedImage.bytes.length, _rasterWidth * _rasterHeight);
    expect(paddedImage.bytes, base.bytes);
    expect(
      identical(
        paddedImage.evidence,
        paddedRaster.renderedImages.single.evidence,
      ),
      isTrue,
    );
    expect(paddedImage.width / (200 / 72), closeTo(_pageWidthPt, 1e-12));
    expect(paddedImage.height / (200 / 72), closeTo(_pageHeightPt, 1e-12));
  });

  test('a non-gray8 render is a rasterization failure', () async {
    final Uint8List rgba = Uint8List(
      _rasterWidth * RasterFormat.rgba8888.bytesPerPixel * _rasterHeight,
    );
    final DocumentAnalysisResult result = await AnalyzeDocument.run(
      _request(
        raster: _FakeRaster(<int, _RasterSpec>{
          0: _RasterSpec(bytes: rgba, format: RasterFormat.rgba8888),
        }),
      ),
    );

    final FieldSuggestionSet set = result.pages.single;
    expect(set.isFailed, isTrue);
    expect(set.failure!.category, PageAnalysisFailure.rasterization);
    expect(set.failure!.messageKey, 'PAGE-001');
  });

  test('a post-render analysis failure maps to internal', () async {
    // A valid RasterImage already guarantees the strip's preconditions, so the
    // injectable analysis builder is the deterministic way to exercise the
    // shared post-render strip/analysis catch.
    final DocumentAnalysisResult result = await AnalyzeDocument.run(
      _request(raster: _FakeRaster(<int, _RasterSpec>{0: _underlinePage()})),
      rasterAnalysis: (GrayRaster raster) {
        throw StateError('synthetic analysis failure');
      },
    );

    final FieldSuggestionSet set = result.pages.single;
    expect(set.isFailed, isTrue);
    expect(set.failure!.category, PageAnalysisFailure.internal);
    expect(set.failure!.messageKey, 'REC-002');
    expect(set.suggestions, isEmpty);
  });

  test(
    'detector preconditions map to internal, not unsupported structure',
    () async {
      final DocumentAnalysisResult result = await AnalyzeDocument.run(
        _request(raster: _FakeRaster(<int, _RasterSpec>{0: _underlinePage()})),
        geometryDetection:
            (
              RasterAnalysis analysis, {
              required double pageWidthPt,
              required double pageHeightPt,
            }) {
              throw ArgumentError('synthetic detector precondition');
            },
      );

      expect(
        result.pages.single.failure!.category,
        PageAnalysisFailure.internal,
      );
      expect(result.pages.single.failure!.messageKey, 'REC-002');
    },
  );

  test('an explicit detector structure signal preserves REC-003', () async {
    final DocumentAnalysisResult result = await AnalyzeDocument.run(
      _request(raster: _FakeRaster(<int, _RasterSpec>{0: _underlinePage()})),
      geometryDetection:
          (
            RasterAnalysis analysis, {
            required double pageWidthPt,
            required double pageHeightPt,
          }) {
            throw PageAnalysisFailure.forCategory(
              PageAnalysisFailure.unsupportedStructure,
            );
          },
    );

    expect(
      result.pages.single.failure!.category,
      PageAnalysisFailure.unsupportedStructure,
    );
    expect(result.pages.single.failure!.messageKey, 'REC-003');
  });

  test('a failed page reports discarded partial suggestion drafts', () async {
    final GeometryCandidate synthetic = GeometryCandidate(
      rect: DisplayRect(x: 36, y: 54, width: 36, height: 18),
      cues: const <String>['signature_area'],
      inkCoverage: 0,
    );
    final DocumentAnalysisResult result = await AnalyzeDocument.run(
      _request(raster: _FakeRaster(<int, _RasterSpec>{0: _underlinePage()})),
      geometryDetection:
          (
            RasterAnalysis analysis, {
            required double pageWidthPt,
            required double pageHeightPt,
          }) {
            return <GeometryCandidate>[synthetic];
          },
    );

    final FieldSuggestionSet set = result.pages.single;
    expect(set.isFailed, isTrue);
    expect(set.failure!.category, PageAnalysisFailure.internal);
    expect(set.failure!.messageKey, 'REC-002');
    expect(set.failure!.suggestionCount, 1);
    expect(set.suggestions, isEmpty);
  });

  test(
    'cancellation excludes only the matching page and keeps it pending',
    () async {
      final _FakeRaster raster = _FakeRaster(<int, _RasterSpec>{
        0: _underlinePage(),
        1: _underlinePage(top: 100),
      });

      final DocumentAnalysisResult result = await AnalyzeDocument.run(
        _request(
          raster: raster,
          pages: <DocumentAnalysisPage>[_page(0), _page(1)],
        ),
        isCancelled: (int pageIndex) => pageIndex == 0,
      );

      expect(result.isComplete, isFalse);
      expect(result.cancelledPageIndexes, <int>[0]);
      expect(result.pages, hasLength(1));
      expect(result.pages.single.pageIndex, 1);
      expect(result.pages.single.isComplete, isTrue);
      expect(result.pages.single.isFailed, isFalse);
      expect(
        raster.requests.map((RasterRequest request) => request.pageIndex),
        <int>[1],
      );
    },
  );

  test('envelopes round-trip through the T057 validator', () async {
    final DocumentAnalysisResult result = await AnalyzeDocument.run(
      _request(raster: _FakeRaster(<int, _RasterSpec>{0: _underlinePage()})),
    );

    final FieldSuggestionSet set = result.pages.single;
    final FieldSuggestionSet reparsed = FieldSuggestionSet.fromJson(
      set.toJson(),
    );
    expect(reparsed.canonicalJson(), set.canonicalJson());
    expect(
      SuggestionSchema.validateEnvelope(
        set.toJson(),
        displaySize: PageDisplaySize(_pageWidthPt, _pageHeightPt),
      ),
      isEmpty,
    );
    final Map<String, Object?> projection = set.canonicalProjection();
    expect(projection.containsKey('analysisRunId'), isFalse);
    expect(projection.containsKey('timings'), isFalse);
    expect(projection.containsKey('evidenceClass'), isFalse);
  });

  test('analysis never logs label text', () async {
    final List<String> printed = <String>[];
    late DocumentAnalysisResult result;
    await runZoned(
      () async {
        result = await AnalyzeDocument.run(
          _request(
            raster: _FakeRaster(<int, _RasterSpec>{0: _underlinePage()}),
            ocr: _FakeOcr(
              blocksByPage: <int, List<OcrBlock>>{
                0: <OcrBlock>[
                  _ocrBlock(
                    text: 'StrengGeheim',
                    rect: Rect.fromLTWH(10, 56, 22, 10),
                  ),
                ],
              },
            ),
          ),
        );
      },
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
          printed.add(line);
        },
      ),
    );

    expect(printed, isEmpty);
    expect(result.pages.single.suggestions.single['labelText'], 'StrengGeheim');
  });

  test('request and caller page lists are never mutated', () async {
    final List<DocumentAnalysisPage> pages = <DocumentAnalysisPage>[
      _page(1),
      _page(0),
    ];
    final List<DocumentAnalysisPage> snapshot = List<DocumentAnalysisPage>.of(
      pages,
    );
    final DocumentAnalysisRequest request = _request(
      raster: _FakeRaster(<int, _RasterSpec>{
        0: _underlinePage(),
        1: _underlinePage(top: 100),
      }),
      pages: pages,
    );

    await AnalyzeDocument.run(request);

    expect(pages, orderedEquals(snapshot));
    expect(request.pages, orderedEquals(snapshot));
  });

  test('shuffled page input returns sorted, stable results', () async {
    final _RasterSpec page0 = _underlinePage();
    final _RasterSpec page1 = _underlinePage(top: 100);

    final DocumentAnalysisResult forward = await AnalyzeDocument.run(
      _request(
        raster: _FakeRaster(<int, _RasterSpec>{0: page0, 1: page1}),
        pages: <DocumentAnalysisPage>[_page(0), _page(1)],
      ),
    );
    final DocumentAnalysisResult shuffled = await AnalyzeDocument.run(
      _request(
        raster: _FakeRaster(<int, _RasterSpec>{0: page0, 1: page1}),
        pages: <DocumentAnalysisPage>[_page(1), _page(0)],
      ),
    );

    expect(
      shuffled.pages.map((FieldSuggestionSet set) => set.pageIndex).toList(),
      <int>[0, 1],
    );
    expect(shuffled.pages[0].canonicalJson(), forward.pages[0].canonicalJson());
    expect(shuffled.pages[1].canonicalJson(), forward.pages[1].canonicalJson());
  });
}
