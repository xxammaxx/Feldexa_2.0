// T086B per-page detection benchmark over an externally rasterized page.
//
// Normative sources:
//  * specs/001-scanned-form-workflow/research.md D-20 (measurement method),
//  * specs/001-scanned-form-workflow/contracts/recognition-output.md sections
//    1 (`timings`) and 2 (candidates), and
//  * spec.md SC-004 (analysis time per typical A4 page).
//
// This tool measures the *detector only* on a 200 DPI grayscale page raster
// that another program produced. It exists because `GeometryDetector.detect`
// is synchronous and therefore cannot be measured through the analysis
// timeout on a host without an Android runtime: the timeout cannot preempt it.
// The raster is supplied as binary PGM (`P5`, maxval 255) so the host needs no
// image dependency; it is produced by an external rasterizer, for example
//
//   pdftoppm -gray -r 200 -f <page> -l <page> <input>.pdf <out>
//
// which writes `<out>-<page>.pgm` with the same `round(size x 200/72)`
// dimensions `RasterSize.fromDisplaySize` requires.
//
// Usage:
//   dart run tools/evaluation/benchmark_detection_pgm.dart \
//     <page.pgm> <pageWidthPt> <pageHeightPt> [candidates.json]
//
// It prints one JSON line with the raster dimensions, the `RasterAnalysis`
// build time, the measured `GeometryDetector.detect` time in milliseconds, and
// the candidate count. With a fourth argument it also writes the detected
// candidates (rect, sorted cues, measured ink coverage) as JSON, which is what
// a before/after equivalence comparison diffs.
//
// The output is deterministic except the two measured timings. This tool makes
// no device, emulator, or acceptance claim and produces no evidence class on
// its own: a host-VM measurement is `NONE` class provenance, never the SC-004
// three-second device claim.
// `feldexa_recognition` is a workspace package and intentionally not a root
// `pubspec.yaml` dependency; the root workspace resolves it for `dart run`.
// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:feldexa_recognition/src/raster.dart';

const int _exitInvalid = 1;
const int _exitUsage = 2;

void main(List<String> args) {
  if (args.length == 1 && (args.single == '--help' || args.single == '-h')) {
    stdout.writeln(
      'usage: dart run tools/evaluation/benchmark_detection_pgm.dart '
      '<page.pgm> <pageWidthPt> <pageHeightPt> [candidates.json]',
    );
    return;
  }
  if (args.length < 3 || args.length > 4) {
    stderr.writeln(
      'usage: dart run tools/evaluation/benchmark_detection_pgm.dart '
      '<page.pgm> <pageWidthPt> <pageHeightPt> [candidates.json]',
    );
    exit(_exitUsage);
  }

  final double? pageWidthPt = double.tryParse(args[1]);
  final double? pageHeightPt = double.tryParse(args[2]);
  if (pageWidthPt == null || pageHeightPt == null) {
    stderr.writeln('page size arguments must be numbers');
    exit(_exitUsage);
  }

  final Uint8List pageBytes;
  try {
    pageBytes = File(args[0]).readAsBytesSync();
  } on FileSystemException catch (error) {
    stderr.writeln('cannot read raster: ${error.message}');
    exit(_exitInvalid);
  }

  final _PgmHeader header;
  final GrayRaster raster;
  try {
    header = _parsePgmHeader(pageBytes);
    raster = GrayRaster.fromGrayBytes(
      width: header.width,
      height: header.height,
      bytes: Uint8List.sublistView(
        pageBytes,
        header.dataOffset,
        header.dataOffset + header.width * header.height,
      ),
    );
  } on FormatException catch (error) {
    stderr.writeln('invalid raster: ${error.message}');
    exit(_exitInvalid);
  } on ArgumentError catch (error) {
    stderr.writeln('invalid raster: ${error.message}');
    exit(_exitInvalid);
  }

  final Stopwatch analysisWatch = Stopwatch()..start();
  final RasterAnalysis analysis = RasterAnalysis(raster);
  analysisWatch.stop();

  final Stopwatch detectWatch = Stopwatch()..start();
  final List<GeometryCandidate> candidates = GeometryDetector.detect(
    analysis,
    pageWidthPt: pageWidthPt,
    pageHeightPt: pageHeightPt,
  );
  detectWatch.stop();

  print(
    jsonEncode(<String, Object?>{
      'page': args[0],
      'raster': '${header.width} x ${header.height}',
      'analysisMs': analysisWatch.elapsedMilliseconds,
      'detectMs': detectWatch.elapsedMilliseconds,
      'candidates': candidates.length,
    }),
  );

  if (args.length == 4) {
    File(args[3]).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(
        candidates
            .map(
              (GeometryCandidate candidate) => <String, Object?>{
                'x': candidate.rect.x,
                'y': candidate.rect.y,
                'width': candidate.rect.width,
                'height': candidate.rect.height,
                'cues': candidate.cues,
                'inkCoverage': candidate.inkCoverage,
              },
            )
            .toList(),
      ),
    );
  }
}

final class _PgmHeader {
  const _PgmHeader(this.width, this.height, this.dataOffset);

  final int width;
  final int height;
  final int dataOffset;
}

/// Parses a binary PGM (`P5`) header with maxval 255.
_PgmHeader _parsePgmHeader(Uint8List bytes) {
  int index = 0;

  String nextToken() {
    while (index < bytes.length) {
      final int code = bytes[index];
      if (code == 0x23) {
        while (index < bytes.length && bytes[index] != 0x0A) {
          index++;
        }
      } else if (code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D) {
        index++;
      } else {
        break;
      }
    }
    final int start = index;
    while (index < bytes.length) {
      final int code = bytes[index];
      if (code == 0x20 ||
          code == 0x09 ||
          code == 0x0A ||
          code == 0x0D ||
          code == 0x23) {
        break;
      }
      index++;
    }
    if (start == index) {
      throw const FormatException('truncated PGM header');
    }
    return String.fromCharCodes(bytes.sublist(start, index));
  }

  int parseIntToken(String label) {
    final int? value = int.tryParse(nextToken());
    if (value == null) {
      throw FormatException('non-numeric PGM $label');
    }
    return value;
  }

  if (nextToken() != 'P5') {
    throw const FormatException('expected binary PGM (P5)');
  }
  final int width = parseIntToken('width');
  final int height = parseIntToken('height');
  if (parseIntToken('maxval') != 255) {
    throw const FormatException('expected maxval 255');
  }
  if (index < bytes.length && bytes[index] == 0x0D) {
    index++;
  }
  if (index < bytes.length && bytes[index] == 0x0A) {
    index++;
  }
  if (bytes.length - index != width * height) {
    throw const FormatException('pixel data length does not match the header');
  }
  return _PgmHeader(width, height, index);
}
