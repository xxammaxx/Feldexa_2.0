// T027 Android `OcrPort` thin client.
//
// The on-device ML Kit service belongs to its own task; this client validates
// the channel request/response and maps terminal failures. With no service
// registered the facade returns `PLT-001` and the client fails closed.

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/services.dart';

import 'android_channel.dart';
import 'android_operation_client.dart';

// A private field cannot use an initializing formal with a public named
// parameter; the explicit initializer is intentional.
// ignore_for_file: prefer_initializing_formals

/// Resolves the source-page display size for one rendered raster.
///
/// `contracts/ports.md` §2.3 does not put the page size in `OcrRequest`, while
/// `contracts/platform-channel.md` §5 requires `pageWidthPt`/`pageHeightPt`.
/// The production composition supplies this resolver from the same page
/// geometry the raster was rendered with. Without it the client fails closed
/// instead of inventing a page size.
typedef OcrPageSizeResolver = ({double widthPt, double heightPt}) Function(
  RasterImage image,
);

/// Android `OcrPort` channel client.
final class AndroidOcrClient implements OcrPort {
  AndroidOcrClient({
    MethodChannel? channel,
    AndroidOperationClient? operations,
    CapabilityEvidence? evidence,
    OcrPageSizeResolver? pageSizeResolver,
  }) : _pageSizeResolver = pageSizeResolver,
       _operations =
           operations ??
           AndroidOperationClient(
             channel: channel ?? const MethodChannel('de.feldexa/platform'),
           ),
       _evidence =
           evidence ??
           CapabilityEvidence.android(adapterId: 'android.ocr.mlkit.v1');

  final AndroidOperationClient _operations;
  final CapabilityEvidence _evidence;
  final OcrPageSizeResolver? _pageSizeResolver;

  static final CapabilityDescriptor _descriptor = CapabilityDescriptor(
    kind: CapabilityKind.ocr,
    adapterId: 'android.ocr.mlkit.v1',
    version: '1',
    isSimulated: false,
    evidence: CapabilityEvidence.android(adapterId: 'android.ocr.mlkit.v1'),
    supportedFeatures: const <String>[
      'on-device',
      'mlkit-latin',
      'german-language',
      'geometry-only-fallback',
    ],
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  CapabilityEvidence get evidence => _evidence;

  @override
  Future<List<OcrBlock>> recognize(OcrRequest request) async {
    final OcrPageSizeResolver? resolver = _pageSizeResolver;
    if (resolver == null) {
      throw UnsupportedOperationException();
    }
    final ({double widthPt, double heightPt}) pageSize = resolver(
      request.image,
    );
    try {
      final Object? raw = await _operations.invoke(
        'ocr.recognize',
        <String, Object?>{
          'pageIndex': request.pageIndex,
          'imageWidth': request.image.width,
          'imageHeight': request.image.height,
          'pageWidthPt': pageSize.widthPt,
          'pageHeightPt': pageSize.heightPt,
          'format': request.image.format.name,
          'bytes': request.image.bytes,
          'language': request.languageHint,
        },
      );
      final Map<String, Object?> data = androidMap(raw, 'ocr result');
      final Object? blocks = data['blocks'];
      if (blocks is! List) throw const FormatException('Invalid OCR blocks');
      return List<OcrBlock>.unmodifiable(<OcrBlock>[
        for (final Object? block in blocks)
          _block(androidMap(block, 'OCR block')),
      ]);
    } catch (error) {
      throwAndroidChannelError(error);
    }
  }

  OcrBlock _block(Map<String, Object?> data) {
    final Object? text = data['text'];
    final Object? confidence = data['confidence'];
    final Object? rect = data['rect'];
    final Object? lines = data['lines'];
    if (text is! String ||
        confidence is! num ||
        rect is! Map ||
        lines is! List) {
      throw const FormatException('Invalid OCR block');
    }
    try {
      return OcrBlock(
        rect: Rect.fromJson(androidMap(rect, 'OCR rect')),
        text: text,
        confidence: confidence.toDouble(),
        lines: <OcrLine>[
          for (final Object? line in lines) _line(androidMap(line, 'OCR line')),
        ],
      );
    } on ArgumentError {
      throw const FormatException('Invalid OCR block');
    }
  }

  OcrLine _line(Map<String, Object?> data) {
    final Object? text = data['text'];
    final Object? confidence = data['confidence'];
    final Object? rect = data['rect'];
    if (text is! String || confidence is! num || rect is! Map) {
      throw const FormatException('Invalid OCR line');
    }
    try {
      return OcrLine(
        rect: Rect.fromJson(androidMap(rect, 'OCR rect')),
        text: text,
        confidence: confidence.toDouble(),
      );
    } on ArgumentError {
      throw const FormatException('Invalid OCR line');
    }
  }

  @override
  Future<void> dispose() async {
    // The channel service owns the ML Kit recognizer lifetime. The facade
    // closes it on engine detach; the Dart client holds no native handle.
  }
}
