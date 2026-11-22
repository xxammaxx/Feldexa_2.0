// T263 German OCR character and Unicode qualification on the real Android
// production path (issue #263, US2).
//
// Run only on the exclusively allocated emulator through the host driver,
// which stages the additive reference fixture, the pre-annotated ground truth,
// and the pre-built scan variants:
//
//   tools/android/t263_drive_de_ocr.sh
//
// What this test executes:
//   * the committed synthetic `reference-de.pdf` (embedded Noto Sans, real
//     `ẞ`/`€`/`²`/`³`) is imported byte-identically from the staging directory
//     and its SHA-256 is compared with the ground truth before any work;
//   * clean variants render every page through the **production** raster port
//     (`AndroidPdfrxRasterClient`, PDFium) and recognize it with the
//     **production** bundled ML Kit OCR port (`AndroidOcrClient`) — evidence
//     class `EMULATOR`;
//   * degraded variants feed a host-built scan simulation (contrast, shadow,
//     three-degree skew, JPEG q35) as a `gray8` raster into the same production
//     OCR port and the same production pipeline — evidence class
//     `EMULATOR_INJECTED_RASTER`, never claimed as clean production-path
//     evidence;
//   * raw OCR lines and the production `AnalyzeDocument` suggestions (label
//     text, proposed type, cues, confidence, uncertainty, resolution) are
//     recorded per page;
//   * one German-labelled suggestion from the clean page 2 analysis is
//     confirmed with the production `confirmSuggestion` command, written to the
//     real encrypted Android store, reloaded, and compared code point by code
//     point, together with the unchanged source PDF hash.
//
// Privacy: the document is synthetic and self-generated. Markers carry phase
// names, content-free counts, page indexes, types, geometry, and confidence
// only; recognized text is written to the staging directory the host driver
// owns and pulled into the report artifacts, never to a log. The test opens no
// network socket.
//
// ignore_for_file: implementation_imports

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:feldexa_application/src/recognition/analyze_document.dart';
import 'package:feldexa_application/src/review/confirm_suggestion.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:feldexa_recognition/src/suggestion_schema.dart'
    show PageDisplaySize;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Host-owned input staging directory prepared by the driver.
const String _staging = '/data/local/tmp/t263-fixtures';

/// App-private external output directory the driver pulls the run files from.
///
/// `/data/local/tmp` is not reliably writable for an app under SELinux, while
/// `Android/data/<package>/files` is written by the app itself and can be
/// pulled by `adb` for a debuggable build.
const String _outputRoot = '/storage/emulated/0/Android/data/de.feldexa/files/t263';

/// Fixed document identity for the recognition run.
const String _sourceId = '7d0f8b1c-3a2e-4f66-9c15-6b0e2d4a8f31';
const String _analysisRunId = 'b2c4d6e8-0a1b-4c3d-9e5f-7a8b9c0d1e2f';

/// OCR language hint used by production.
const String _language = 'de';

void _marker(String phase) {
  debugPrint('T263_$phase');
}

final class _InjectedRasterPort implements PageRasterPort {
  _InjectedRasterPort({
    required this.images,
    required this.pageSizes,
    required CapabilityEvidence evidence,
  }) : _evidence = evidence {
    _descriptor = CapabilityDescriptor(
      kind: CapabilityKind.pageRaster,
      adapterId: evidence.adapterId,
      version: '1',
      isSimulated: false,
      evidence: evidence,
      supportedFeatures: const <String>['injected-gray8', 'test-seam'],
    );
  }

  final Map<int, RasterImage> images;
  final Map<int, ({double widthPt, double heightPt})> pageSizes;
  final CapabilityEvidence _evidence;
  late final CapabilityDescriptor _descriptor;

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  /// Evidence label of the injected raster seam.
  CapabilityEvidence get evidence => _evidence;

  @override
  Future<core.PageGeometry> pageDimensions(String sourceId, int pageIndex) async {
    final ({double widthPt, double heightPt}) size = pageSizes[pageIndex]!;
    return core.PageGeometry(
      mediaBox: core.Rect.fromLTWH(0, 0, size.widthPt, size.heightPt),
    );
  }

  @override
  Future<RasterImage> renderPage(RasterRequest request) async {
    final RasterImage? image = images[request.pageIndex];
    if (image == null) {
      throw StateError('no injected raster for page ${request.pageIndex}');
    }
    return image;
  }

  @override
  Future<void> evict(String sourceId) async {}
}

core.PageGeometry _a4Geometry() {
  return core.PageGeometry(mediaBox: core.Rect.fromLTWH(0, 0, 595.28, 841.89));
}

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('German OCR characters and label takeover on Android', (
    WidgetTester tester,
  ) async {
    final Directory staging = Directory(_staging);
    expect(
      staging.existsSync(),
      isTrue,
      reason: 'host driver must stage the T263 fixtures',
    );
    final Uint8List pdf = File('$_staging/reference-de.pdf').readAsBytesSync();
    final String pdfSha256 = crypto.sha256.convert(pdf).toString();
    final Map<String, Object?> groundTruth =
        jsonDecode(
              File('$_staging/reference-de.ground-truth.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    final Map<String, Object?> pdfInfo =
        groundTruth['pdf']! as Map<String, Object?>;
    expect(pdfSha256, pdfInfo['sha256']);
    expect(pdf.length, pdfInfo['sizeBytes']);
    _marker('FIXTURE_VERIFIED');

    final Map<String, Object?> variantsManifest =
        jsonDecode(
              File('$_staging/t263-variants.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    final List<Object?> variants =
        variantsManifest['variants']! as List<Object?>;

    final List<Map<String, Object?>> production =
        <Map<String, Object?>>[];
    final List<Map<String, Object?>> injected = <Map<String, Object?>>[];
    Map<String, Object?>? cleanPageOneSuggestions;

    for (final Object? entry in variants) {
      final Map<String, Object?> variant = entry! as Map<String, Object?>;
      final String id = variant['id']! as String;
      final String kind = variant['kind']! as String;
      final int dpi = variant['dpi']! as int;
      final double pageWidthPt = (variant['pageWidthPt']! as num).toDouble();
      final double pageHeightPt = (variant['pageHeightPt']! as num).toDouble();
      final bool productionRaster = kind == 'production-raster';

      final Map<RasterImage, ({double widthPt, double heightPt})> sizes =
          <RasterImage, ({double widthPt, double heightPt})>{};
      final Map<int, RasterImage> injectedImages = <int, RasterImage>{};
      final Map<int, ({double widthPt, double heightPt})> injectedSizes =
          <int, ({double widthPt, double heightPt})>{};
      final CapabilityEvidence injectedEvidence = CapabilityEvidence.android(
        adapterId: 't263.injected.raster',
      );

      final AndroidPdfrxRasterClient? pdfrx = productionRaster
          ? AndroidPdfrxRasterClient(sourceBytes: (String _) async => pdf)
          : null;
      final PageRasterPort rasterPort;
      if (pdfrx != null) {
        rasterPort = pdfrx;
      } else {
        for (final Object? pageEntry in variant['pages']! as List<Object?>) {
          final Map<String, Object?> page = pageEntry! as Map<String, Object?>;
          final int pageIndex = page['index']! as int;
          final int widthPx = page['widthPx']! as int;
          final int heightPx = page['heightPx']! as int;
          final Uint8List bytes = File(
            '$_staging/${page['file']! as String}',
          ).readAsBytesSync();
          expect(bytes.length, widthPx * heightPx);
          final RasterImage image = RasterImage(
            bytes: bytes,
            width: widthPx,
            height: heightPx,
            bytesPerRow: widthPx,
            format: RasterFormat.gray8,
            evidence: injectedEvidence,
          );
          injectedImages[pageIndex] = image;
          injectedSizes[pageIndex] = (
            widthPt: pageWidthPt,
            heightPt: pageHeightPt,
          );
        }
        rasterPort = _InjectedRasterPort(
          images: injectedImages,
          pageSizes: injectedSizes,
          evidence: injectedEvidence,
        );
      }

      final AndroidOcrClient ocr = AndroidOcrClient(
        pageSizeResolver: (RasterImage image) {
          final ({double widthPt, double heightPt})? size = sizes[image];
          if (size == null) {
            throw StateError('unknown raster page size');
          }
          return size;
        },
      );

      final List<Map<String, Object?>> pages = <Map<String, Object?>>[];
      final Map<String, Object?> timings = <String, Object?>{};
      for (final int pageIndex in <int>[0, 1]) {
        final RasterImage image;
        final int rasterMs;
        if (pdfrx != null) {
          final Stopwatch rasterClock = Stopwatch()..start();
          image = await pdfrx.renderPage(
            RasterRequest(
              sourceId: _sourceId,
              pageIndex: pageIndex,
              scale: dpi / 72.0,
              format: RasterFormat.gray8,
            ),
          );
          sizes[image] = pdfrx.pageSizeOf(image)!;
          rasterMs = rasterClock.elapsedMilliseconds;
        } else {
          image = injectedImages[pageIndex]!;
          sizes[image] = injectedSizes[pageIndex]!;
          rasterMs = 0;
        }

        final Stopwatch ocrClock = Stopwatch()..start();
        final List<OcrBlock> blocks = await ocr.recognize(
          OcrRequest(
            image: image,
            pageIndex: pageIndex,
            languageHint: _language,
          ),
        );
        final int ocrMs = ocrClock.elapsedMilliseconds;

        final DocumentAnalysisResult analysis = await AnalyzeDocument.run(
          DocumentAnalysisRequest(
            sourceId: _sourceId,
            analysisRunId: _analysisRunId,
            pages: <DocumentAnalysisPage>[
              DocumentAnalysisPage(
                pageIndex: pageIndex,
                pageSizePt: PageDisplaySize(
                  sizes[image]!.widthPt,
                  sizes[image]!.heightPt,
                ),
              ),
            ],
            evidenceClass: 'emulator',
            rasterPort: rasterPort,
            ocrPort: ocr,
          ),
        );
        expect(analysis.pages, hasLength(1));
        final List<Map<String, Object?>> suggestions = <Map<String, Object?>>[
          for (final Map<String, Object?> suggestion
              in analysis.pages.first.suggestions)
            <String, Object?>{
              'rect': suggestion['rect'],
              'proposedType': suggestion['proposedType'],
              'labelText': suggestion['labelText'],
              'confidence': suggestion['confidence'],
              'uncertainty': suggestion['uncertainty'],
              'cues': (suggestion['evidence']! as Map<String, Object?>)['cues'],
              'resolution': suggestion['resolution'],
            },
        ];
        pages.add(<String, Object?>{
          'index': pageIndex,
          'widthPt': sizes[image]!.widthPt,
          'heightPt': sizes[image]!.heightPt,
          'lines': <Object>[
            for (final OcrBlock block in blocks)
              for (final OcrLine line in block.lines)
                <String, Object?>{
                  'text': line.text,
                  'rect': <String, Object?>{
                    'x': line.rect.left,
                    'y': line.rect.top,
                    'width': line.rect.width,
                    'height': line.rect.height,
                  },
                  'confidence': line.confidence,
                },
          ],
          'suggestions': suggestions,
        });
        timings['rasterMs-$pageIndex'] = rasterMs;
        timings['ocrMs-$pageIndex'] = ocrMs;
        _marker(
          'VARIANT_PAGE_DONE id=$id page=$pageIndex '
          'lines=${blocks.fold<int>(0, (int sum, OcrBlock block) => sum + block.lines.length)} '
          'suggestions=${suggestions.length}',
        );
        if (productionRaster && id == 'clean-200dpi' && pageIndex == 1) {
          // Keep the unmodified production suggestion maps for the takeover
          // journey so the confirmed field reuses the recorded evidence.
          cleanPageOneSuggestions = <String, Object?>{
            'suggestions': analysis.pages.first.suggestions,
          };
        }
      }

      final Map<String, Object?> runVariant = <String, Object?>{
        'id': id,
        'raster': <String, Object?>{
          'source': productionRaster
              ? 'production-raster-port'
              : 'injected-scan-simulation',
          'dpi': dpi,
          'degradations': variant['degradations'],
        },
        'pages': pages,
        'timings': timings,
      };
      (productionRaster ? production : injected).add(runVariant);
      await ocr.dispose();
      await pdfrx?.evict(_sourceId);
    }
    _marker('VARIANTS_DONE');

    final Directory output = Directory(_outputRoot);
    output.createSync(recursive: true);

    void writeRun(String name, String evidenceClass, List<Map<String, Object?>> variants) {
      final Map<String, Object?> run = <String, Object?>{
        'schemaVersion': 1,
        'suiteId': groundTruth['suiteId'],
        'fixtureId': groundTruth['fixtureId'],
        'fixtureSha256': pdfSha256,
        'engine': 'mlkit-latin-bundled-v1',
        'evidenceClass': evidenceClass,
        'runner': <String, Object?>{
          'kind': 'android-integration-test',
          'test': 'integration_test/android_de_ocr_test.dart',
          'device': Platform.operatingSystemVersion,
        },
        'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'variants': variants,
      };
      File('${output.path}/$name').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(run)}\n',
      );
    }

    writeRun('t263-run-emulator.json', 'EMULATOR', production);
    writeRun(
      't263-run-injected.json',
      'EMULATOR_INJECTED_RASTER',
      injected,
    );
    _marker('RUN_FILES_WRITTEN');

    // --- Label takeover: production confirm command plus real store round trip.
    final Map<String, Object?>? pageOne = cleanPageOneSuggestions;
    expect(pageOne, isNotNull, reason: 'clean page 2 analysis must be recorded');
    final List<Object?> pageOneSuggestions =
        pageOne!['suggestions']! as List<Object?>;
    Map<String, Object?>? german;
    for (final Object? entry in pageOneSuggestions) {
      final Map<String, Object?> suggestion = entry! as Map<String, Object?>;
      final String? label = suggestion['labelText'] as String?;
      if (label == null) {
        continue;
      }
      if (label.contains('ß') ||
          label.contains('ä') ||
          label.contains('ö') ||
          label.contains('ü') ||
          label.contains('Ä') ||
          label.contains('Ö') ||
          label.contains('Ü')) {
        german = suggestion;
        break;
      }
    }
    expect(
      german,
      isNotNull,
      reason: 'at least one German-labelled suggestion is expected on page 2',
    );
    final String verbatimLabel = german!['labelText']! as String;
    final core.FieldSuggestion suggestion = core.FieldSuggestion.fromJson(
      german,
    );
    expect(suggestion.labelText, verbatimLabel);
    expect(
      suggestion.rect.width,
      (german['rect']! as Map<String, Object?>)['width'],
    );
    final core.RevisionContent content = core.RevisionContent(
      pages: <core.Page>[
        core.Page(index: 0, geometry: _a4Geometry()),
        core.Page(index: 1, geometry: _a4Geometry()),
      ],
      suggestions: <core.FieldSuggestion>[suggestion],
      fieldOrder: const <String>[],
    );
    final SuggestionReviewChange confirmed = confirmSuggestion(
      content,
      suggestion.id,
      '0d1e2f3a-4b5c-4d6e-8f90-1a2b3c4d5e6f',
      verbatimLabel,
      DateTime.now().toUtc(),
    );
    final core.ConfirmedField field = confirmed.confirmedField!;
    expect(field.label, verbatimLabel);
    expect(field.label.runes.toList(), verbatimLabel.runes.toList());

    final AndroidStoreClient store = AndroidStoreClient();
    final AndroidIdClient ids = AndroidIdClient();
    final String documentId = ids.newId();
    final String revisionId = ids.newId();
    final String contentSha256 = crypto.sha256
        .convert(core.canonicalJsonBytes(confirmed.content.toJson()))
        .toString();
    bool created = false;
    try {
      await store.stageSource(
        documentId: documentId,
        sourceId: _sourceId,
        bytes: pdf,
        sha256: pdfSha256,
      );
      await store.createDocument(
        CreateDocumentRequest(
          documentId: documentId,
          title: 'T263 Zeichensatz-Referenz',
          source: core.SourceFileRef(
            id: _sourceId,
            sha256: pdfSha256,
            sizeBytes: pdf.length,
            pageCount: 2,
            importedAt: DateTime.now().toUtc(),
          ),
          initialRevision: core.Revision(
            id: revisionId,
            documentId: documentId,
            kind: core.RevisionKind.explicit,
            createdAt: DateTime.now().toUtc(),
            plaintextSha256: contentSha256,
            content: confirmed.content,
          ),
        ),
      );
      created = true;
      final LoadedDocument loaded = await store.loadDocument(documentId);
      expect(loaded.content.fields, hasLength(1));
      final core.ConfirmedField storedField = loaded.content.fields.single;
      expect(storedField.label, verbatimLabel);
      expect(
        storedField.label.runes.toList(),
        verbatimLabel.runes.toList(),
        reason: 'the German label must survive the encrypted store verbatim',
      );
      expect(
        crypto.sha256.convert(loaded.sourceBytes).toString(),
        pdfSha256,
        reason: 'the imported PDF source must stay byte-identical',
      );
      _marker('LABEL_TAKEOVER_STORE_VERIFIED');
    } finally {
      if (created) {
        await store.delete(
        StoreKind.document,
        documentId,
        DeleteConfirmation(
          title: 'T263 Zeichensatz-Referenz',
          acknowledged: true,
        ),
      );
      }
    }
    _marker('CLEANUP_DONE');
  });
}
