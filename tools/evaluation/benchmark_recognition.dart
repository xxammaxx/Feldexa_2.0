// T063 per-stage recognition timing benchmark and recorder (host-only).
//
// Normative sources:
//  * specs/001-scanned-form-workflow/research.md D-20 (measurement method),
//  * specs/001-scanned-form-workflow/contracts/recognition-output.md section 1
//    (`timings`), and
//  * spec.md SC-004 (median analysis time per typical A4 page).
//
// This tool records raster/OCR/detection timings for later SC-004 measurement.
// It never invents a timing, never claims device performance, and produces no
// SIMULATED/EMULATOR/DEVICE evidence on its own.
//
// Mode A records timings that another run (for example an Android/device run)
// supplied:
//
//   dart run tools/evaluation/benchmark_recognition.dart \
//     --input <input.json> --output <output.json> --form-id <id> \
//     --device-profile <profile> --build-mode <mode> \
//     [--thermal <state>] [--app-version <v>] \
//     [--evidence-class SIMULATED|EMULATOR|DEVICE|NONE]
//
// The input is a JSON array of page objects shaped like the
// `FieldSuggestionSet` `timings` field:
//
//   [
//     {"pageIndex": 0,
//      "timings": {"rasterMs": 210, "ocrMs": 1180, "detectMs": 430}}
//   ]
//
// Extra keys are ignored. Missing, negative, or non-integer timings, an empty
// input, a duplicate page index, an unknown evidence class, or non-finite
// metadata are rejected with a content-free error and a non-zero exit.
//
// Mode B is a deterministic host synthetic detection:
//
//   dart run tools/evaluation/benchmark_recognition.dart --synthetic \
//     --output <out.json> --form-id <id> --device-profile host-vm \
//     --build-mode host
//
// It builds a deterministic grayscale A4 raster containing one rectangle,
// one small square, and one underline, runs the real `RasterAnalysis` and
// `GeometryDetector.detect`, and records the measured detection time.
// Rasterization and OCR are `NOT_RUN`/null because this host tool performs
// neither, and the evidence class is `SIMULATED`. The output documents the
// synthetic host-only conditions; it is not a device, emulator, or
// performance claim.
//
// Exit codes:
//   0  report written (or `--help` printed)
//   1  invalid input, unknown evidence class, non-finite metadata, or I/O
//      failure; no report is written
//   2  usage error (unknown/missing/duplicate argument)
//
// The JSON output is deterministic except `generatedAtUtc` and measured
// times. This tool has no Flutter, Gradle, device, or network dependency.
//
// `feldexa_recognition` is a workspace package and intentionally not a root
// `pubspec.yaml` dependency; the root workspace resolves it for `dart run`.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:feldexa_recognition/src/raster.dart';

const int _schemaVersion = 1;

const int _exitOk = 0;
const int _exitInvalid = 1;
const int _exitUsage = 2;

const Set<String> _evidenceClasses = <String>{
  'SIMULATED',
  'EMULATOR',
  'DEVICE',
  'NONE',
};

final class _Failure implements Exception {
  const _Failure(this.exitCode, this.code);

  final int exitCode;
  final String code;
}

const String _help = '''
T063 per-stage recognition timing benchmark (host-only).

Usage:
  benchmark_recognition.dart --input <input.json> --output <output.json>
      --form-id <id> --device-profile <profile> --build-mode <mode>
      [--thermal <state>] [--app-version <v>]
      [--evidence-class SIMULATED|EMULATOR|DEVICE|NONE]
  benchmark_recognition.dart --synthetic --output <output.json>
      --form-id <id> --device-profile <profile> --build-mode <mode>
      [--thermal <state>] [--app-version <v>]
  benchmark_recognition.dart --help

Mode A - record a supplied run:
  --input is a JSON array of page objects
  {"pageIndex": int, "timings": {"rasterMs": int, "ocrMs": int,
  "detectMs": int}}. Extra keys are ignored. Timings must be present,
  integer, and non-negative; the input must be non-empty; pageIndex values
  must be unique. The report adds totalMs = rasterMs + ocrMs + detectMs.
  --evidence-class defaults to NONE.

Mode B - deterministic host synthetic detection:
  --synthetic builds a deterministic grayscale A4 raster with one rectangle,
  one small square, and one underline, runs the real RasterAnalysis and
  GeometryDetector.detect, and records the measured detection time.
  Rasterization and OCR are NOT_RUN/null, totalMs is null, and evidenceClass
  is SIMULATED. Conditions are host-only; there is no device, emulator, or
  performance claim.

Options:
  --input PATH            Supplied-run timings JSON (mode A, required).
  --output PATH           Destination report JSON (required).
  --form-id ID            Corpus form identifier (required).
  --device-profile NAME   Device/emulator/host profile (required).
  --build-mode MODE       Build mode, for example release or debug (required).
  --thermal STATE         Thermal state, if the run recorded one.
  --app-version VERSION   App version, if the run recorded one.
  --evidence-class CLASS  SIMULATED, EMULATOR, DEVICE, or NONE. Mode A only;
                          mode B is always SIMULATED.
  --synthetic             Select mode B.
  --help, -h              Show this help and exit 0.

Output:
  A versioned JSON object with formId, pageCount, dpi (200), buildMode,
  deviceProfile, thermalState, appVersion, evidenceClass, generatedAtUtc, and
  pages. Each page carries rasterMs, ocrMs, detectMs, and totalMs. Output is
  deterministic except generatedAtUtc and measured times.

Exit codes:
  0  report written, or help printed
  1  invalid input, unknown evidence class, non-finite metadata, or I/O
     failure; no report is written
  2  usage error (unknown, missing, or duplicate argument)

This tool writes no evidence and makes no performance claim.
''';

void main(List<String> arguments) {
  try {
    _run(arguments);
  } on _Failure catch (failure) {
    stderr.writeln('error: ${failure.code}');
    exitCode = failure.exitCode;
    return;
  }
}

void _run(List<String> arguments) {
  final _Options options = _parseArguments(arguments);
  if (options.help) {
    stdout.write(_help);
    exitCode = _exitOk;
    return;
  }

  final String formId = _metadata('form-id', options.formId);
  final String deviceProfile = _metadata(
    'device-profile',
    options.deviceProfile,
  );
  final String buildMode = _metadata('build-mode', options.buildMode);
  final String? thermalState = options.thermalState == null
      ? null
      : _metadata('thermal', options.thermalState!);
  final String? appVersion = options.appVersion == null
      ? null
      : _metadata('app-version', options.appVersion!);
  final String outputPath = _requiredPath('output', options.output);

  final Map<String, Object?> report;
  if (options.synthetic) {
    if (options.input != null) {
      throw const _Failure(_exitUsage, 'input-not-allowed-with-synthetic');
    }
    final String evidenceClass = _evidenceClass(
      options.evidenceClass,
      synthetic: true,
    );
    report = _syntheticReport(
      formId: formId,
      deviceProfile: deviceProfile,
      buildMode: buildMode,
      thermalState: thermalState,
      appVersion: appVersion,
      evidenceClass: evidenceClass,
    );
  } else {
    final String inputPath = _requiredPath('input', options.input);
    final String evidenceClass = _evidenceClass(
      options.evidenceClass,
      synthetic: false,
    );
    report = _recordedReport(
      pages: _loadSuppliedRun(inputPath),
      formId: formId,
      deviceProfile: deviceProfile,
      buildMode: buildMode,
      thermalState: thermalState,
      appVersion: appVersion,
      evidenceClass: evidenceClass,
    );
  }

  _writeReport(outputPath, report);
  exitCode = _exitOk;
}

Map<String, Object?> _recordedReport({
  required List<_PageTimings> pages,
  required String formId,
  required String deviceProfile,
  required String buildMode,
  required String? thermalState,
  required String? appVersion,
  required String evidenceClass,
}) {
  return <String, Object?>{
    'schemaVersion': _schemaVersion,
    'mode': 'recorded',
    'generatedAtUtc': _utcNow(),
    'formId': formId,
    'pageCount': pages.length,
    'dpi': analysisDpi,
    'buildMode': buildMode,
    'deviceProfile': deviceProfile,
    'thermalState': thermalState,
    'appVersion': appVersion,
    'evidenceClass': evidenceClass,
    'pages': pages
        .map(
          (_PageTimings page) => <String, Object?>{
            'pageIndex': page.pageIndex,
            'rasterMs': page.rasterMs,
            'ocrMs': page.ocrMs,
            'detectMs': page.detectMs,
            'totalMs': page.rasterMs + page.ocrMs + page.detectMs,
          },
        )
        .toList(),
  };
}

Map<String, Object?> _syntheticReport({
  required String formId,
  required String deviceProfile,
  required String buildMode,
  required String? thermalState,
  required String? appVersion,
  required String evidenceClass,
}) {
  final _SyntheticPage page = _buildSyntheticPage();
  // The raster and its analysis tables are synthetic host inputs, so building
  // them is not a rasterization measurement. Only the detector call is timed.
  final RasterAnalysis analysis = RasterAnalysis(page.raster);
  // One untimed warm-up keeps JIT compilation out of the measured call. This
  // follows the D-20 warm-up convention without turning the single host run
  // into a performance claim.
  GeometryDetector.detect(
    analysis,
    pageWidthPt: page.widthPt,
    pageHeightPt: page.heightPt,
  );
  final Stopwatch stopwatch = Stopwatch()..start();
  final List<GeometryCandidate> candidates = GeometryDetector.detect(
    analysis,
    pageWidthPt: page.widthPt,
    pageHeightPt: page.heightPt,
  );
  stopwatch.stop();
  final int detectMs = stopwatch.elapsedMilliseconds;

  return <String, Object?>{
    'schemaVersion': _schemaVersion,
    'mode': 'synthetic',
    'generatedAtUtc': _utcNow(),
    'formId': formId,
    'pageCount': 1,
    'dpi': analysisDpi,
    'buildMode': buildMode,
    'deviceProfile': deviceProfile,
    'thermalState': thermalState,
    'appVersion': appVersion,
    'evidenceClass': evidenceClass,
    'synthetic': <String, Object?>{
      'description':
          'host-only deterministic grayscale A4 raster with one rectangle, '
          'one small square, and one underline; this is not a device, '
          'emulator, or production measurement',
      'pageWidthPt': page.widthPt,
      'pageHeightPt': page.heightPt,
      'rasterWidthPx': page.raster.width,
      'rasterHeightPx': page.raster.height,
      'candidateCount': candidates.length,
      'timingScope':
          'GeometryDetector.detect only; one warm-up, then one measured run',
    },
    'pages': <Object?>[
      <String, Object?>{
        'pageIndex': 0,
        'rasterMs': null,
        'ocrMs': null,
        'detectMs': detectMs,
        'totalMs': null,
        'stageStatus': <String, Object?>{
          'rasterMs': 'NOT_RUN',
          'ocrMs': 'NOT_RUN',
          'detectMs': 'MEASURED',
        },
      },
    ],
  };
}

final class _SyntheticPage {
  const _SyntheticPage(this.raster, this.widthPt, this.heightPt);

  final GrayRaster raster;
  final double widthPt;
  final double heightPt;
}

/// Builds the deterministic synthetic page: a white A4 raster with a
/// rectangle border, a small square border, and an underline.
_SyntheticPage _buildSyntheticPage() {
  const double widthPt = 595;
  const double heightPt = 842;
  final RasterSize size = RasterSize.fromDisplaySize(
    widthPt: widthPt,
    heightPt: heightPt,
  );
  final int width = size.widthPx;
  final int height = size.heightPx;
  final Uint8List pixels = Uint8List(width * height)
    ..fillRange(0, width * height, 255);

  void ink(int x, int y) {
    if (x >= 0 && x < width && y >= 0 && y < height) {
      pixels[y * width + x] = 0;
    }
  }

  void horizontal(int left, int right, int top, int thickness) {
    for (int y = top; y < top + thickness; y++) {
      for (int x = left; x < right; x++) {
        ink(x, y);
      }
    }
  }

  void vertical(int left, int top, int bottom, int thickness) {
    for (int y = top; y < bottom; y++) {
      for (int x = left; x < left + thickness; x++) {
        ink(x, y);
      }
    }
  }

  void border(int left, int top, int side, int thickness) {
    final int right = left + side;
    final int bottom = top + side;
    horizontal(left, right, top, thickness);
    horizontal(left, right, bottom - thickness, thickness);
    vertical(left, top, bottom, thickness);
    vertical(right - thickness, top, bottom, thickness);
  }

  const int thickness = 2;
  // Rectangle: outer 600x60 px (216 x 21.6 pt) at 200 DPI.
  const int boxLeft = 300;
  const int boxTop = 420;
  const int boxWidth = 600;
  const int boxHeight = 60;
  horizontal(boxLeft, boxLeft + boxWidth, boxTop, thickness);
  horizontal(
    boxLeft,
    boxLeft + boxWidth,
    boxTop + boxHeight - thickness,
    thickness,
  );
  vertical(boxLeft, boxTop, boxTop + boxHeight, thickness);
  vertical(
    boxLeft + boxWidth - thickness,
    boxTop,
    boxTop + boxHeight,
    thickness,
  );

  // Small square: outer 22 px (7.92 pt), inside the detector's 4-20 pt cue
  // range.
  border(300, 560, 22, thickness);

  // Underline: 700 px (252 pt) long and 3 px thick, with an empty band above.
  horizontal(300, 1000, 700, 3);

  return _SyntheticPage(
    GrayRaster.fromGrayBytes(width: width, height: height, bytes: pixels),
    widthPt,
    heightPt,
  );
}

final class _PageTimings {
  const _PageTimings(this.pageIndex, this.rasterMs, this.ocrMs, this.detectMs);

  final int pageIndex;
  final int rasterMs;
  final int ocrMs;
  final int detectMs;
}

List<_PageTimings> _loadSuppliedRun(String path) {
  final String text;
  try {
    text = File(path).readAsStringSync();
  } on FileSystemException {
    throw const _Failure(_exitInvalid, 'input-unreadable');
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const _Failure(_exitInvalid, 'invalid-input-json');
  }
  if (decoded is! List<Object?> || decoded.isEmpty) {
    throw const _Failure(_exitInvalid, 'invalid-input');
  }

  final List<_PageTimings> pages = <_PageTimings>[];
  final Set<int> seen = <int>{};
  for (final Object? entry in decoded) {
    if (entry is! Map<String, Object?>) {
      throw const _Failure(_exitInvalid, 'invalid-input');
    }
    final Object? pageIndex = entry['pageIndex'];
    if (pageIndex is! int || pageIndex < 0 || !seen.add(pageIndex)) {
      throw const _Failure(_exitInvalid, 'invalid-input');
    }
    final Object? timings = entry['timings'];
    if (timings is! Map<String, Object?>) {
      throw const _Failure(_exitInvalid, 'invalid-input');
    }
    final int? rasterMs = _timing(timings['rasterMs']);
    final int? ocrMs = _timing(timings['ocrMs']);
    final int? detectMs = _timing(timings['detectMs']);
    if (rasterMs == null || ocrMs == null || detectMs == null) {
      throw const _Failure(_exitInvalid, 'invalid-input');
    }
    pages.add(_PageTimings(pageIndex, rasterMs, ocrMs, detectMs));
  }
  pages.sort(
    (_PageTimings left, _PageTimings right) =>
        left.pageIndex.compareTo(right.pageIndex),
  );
  return pages;
}

int? _timing(Object? value) {
  if (value is int && value >= 0) {
    return value;
  }
  return null;
}

void _writeReport(String path, Map<String, Object?> report) {
  final String text = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
  try {
    File(path).writeAsStringSync(text);
  } on FileSystemException {
    throw const _Failure(_exitInvalid, 'output-unwritable');
  }
}

String _utcNow() => DateTime.now().toUtc().toIso8601String();

String _evidenceClass(String? raw, {required bool synthetic}) {
  final String value = raw ?? (synthetic ? 'SIMULATED' : 'NONE');
  if (!_evidenceClasses.contains(value)) {
    throw const _Failure(_exitInvalid, 'unknown-evidence-class');
  }
  if (synthetic && value != 'SIMULATED') {
    throw const _Failure(_exitInvalid, 'unknown-evidence-class');
  }
  return value;
}

/// Validates one metadata string without echoing its content.
///
/// A numeric-looking value must parse to a finite double, so `1e999` cannot
/// smuggle a non-finite metadata value into the report.
String _metadata(String name, String? value) {
  if (value == null ||
      value.isEmpty ||
      value.trim() != value ||
      value.length > 256) {
    throw _Failure(_exitInvalid, 'invalid-metadata-$name');
  }
  for (final int unit in value.codeUnits) {
    if (unit < 0x20 || unit == 0x7F) {
      throw _Failure(_exitInvalid, 'invalid-metadata-$name');
    }
  }
  final double? numeric = double.tryParse(value);
  if (numeric != null && !numeric.isFinite) {
    throw _Failure(_exitInvalid, 'invalid-metadata-$name');
  }
  return value;
}

String _requiredPath(String name, String? value) {
  if (value == null || value.isEmpty) {
    throw _Failure(_exitUsage, 'missing-$name');
  }
  return value;
}

final class _Options {
  bool help = false;
  bool synthetic = false;
  String? input;
  String? output;
  String? formId;
  String? deviceProfile;
  String? buildMode;
  String? thermalState;
  String? appVersion;
  String? evidenceClass;
}

_Options _parseArguments(List<String> arguments) {
  final _Options options = _Options();
  for (int index = 0; index < arguments.length; index++) {
    final String argument = arguments[index];
    if (argument == '--help' || argument == '-h') {
      if (options.help) {
        throw const _Failure(_exitUsage, 'duplicate-help');
      }
      options.help = true;
      continue;
    }
    if (argument == '--synthetic') {
      if (options.synthetic) {
        throw const _Failure(_exitUsage, 'duplicate-synthetic');
      }
      options.synthetic = true;
      continue;
    }
    if (!argument.startsWith('--')) {
      throw const _Failure(_exitUsage, 'unknown-argument');
    }

    String name = argument;
    String? value;
    final int equals = argument.indexOf('=');
    if (equals >= 0) {
      name = argument.substring(0, equals);
      value = argument.substring(equals + 1);
    } else {
      if (index + 1 >= arguments.length) {
        throw const _Failure(_exitUsage, 'missing-argument-value');
      }
      value = arguments[++index];
    }

    switch (name) {
      case '--input':
        options.input = _once(options.input, value);
      case '--output':
        options.output = _once(options.output, value);
      case '--form-id':
        options.formId = _once(options.formId, value);
      case '--device-profile':
        options.deviceProfile = _once(options.deviceProfile, value);
      case '--build-mode':
        options.buildMode = _once(options.buildMode, value);
      case '--thermal':
        options.thermalState = _once(options.thermalState, value);
      case '--app-version':
        options.appVersion = _once(options.appVersion, value);
      case '--evidence-class':
        options.evidenceClass = _once(options.evidenceClass, value);
      default:
        throw const _Failure(_exitUsage, 'unknown-argument');
    }
  }
  return options;
}

String _once(String? existing, String value) {
  if (existing != null) {
    throw const _Failure(_exitUsage, 'duplicate-argument');
  }
  return value;
}
