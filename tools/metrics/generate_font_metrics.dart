// T007 font-advance metrics generator.
//
// Reads the pinned static Noto Sans Regular/Bold TTFs, derives the advance
// table, and writes `apps/feldexa_app/assets/fonts/metrics.json` (or verifies
// that the committed file is byte-for-byte current with `--check`).
//
// Usage:
//   dart run tools/metrics/generate_font_metrics.dart
//   dart run tools/metrics/generate_font_metrics.dart --check
//
// Exit codes: 0 success (or current with --check), 1 font/output error,
// 2 usage error.
//
// This is a host build tool. It produces no `SIMULATED`, `EMULATOR`, or
// `DEVICE` evidence and does not render text.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'font_metrics.dart';

Future<void> main(List<String> arguments) async {
  try {
    final _Options options = _parseArguments(arguments);
    if (options.help) {
      stdout.write(_usage);
      return;
    }

    final Directory fontDirectory = options.fontDirectory ?? _defaultFontDir();
    final File output =
        options.outputFile ??
        File.fromUri(
          _repositoryRoot().uri.resolve(
            'apps/feldexa_app/assets/fonts/metrics.json',
          ),
        );

    stdout.writeln('T007 font metrics generator');
    stdout.writeln('  font directory: ${fontDirectory.path}');
    final ParsedFont regular = _readFont(
      fontDirectory,
      'NotoSans-Regular.ttf',
      'regular',
      400,
    );
    final ParsedFont bold = _readFont(
      fontDirectory,
      'NotoSans-Bold.ttf',
      'bold',
      700,
    );
    final String json = renderMetricsJson(<ParsedFont>[regular, bold]);
    final String jsonDigest = sha256Hex(utf8.encode(json));

    _printFont(regular);
    _printFont(bold);

    if (options.check) {
      if (!output.existsSync()) {
        throw FontMetricsException(
          '${output.path} does not exist; run the generator without --check',
        );
      }
      final String existing = output.readAsStringSync();
      if (existing != json) {
        throw FontMetricsException(
          '${output.path} is stale or was edited by hand '
          '(${existing.length} bytes on disk, ${json.length} bytes '
          'regenerated)',
        );
      }
      stdout.writeln(
        '  OK ${output.path} is byte-for-byte current '
        '(SHA-256 $jsonDigest)',
      );
      return;
    }

    output.parent.createSync(recursive: true);
    final File temporary = File('${output.path}.tmp');
    temporary.writeAsStringSync(json, flush: true);
    temporary.renameSync(output.path);
    stdout.writeln(
      '  wrote ${output.path} (${json.length} bytes, SHA-256 $jsonDigest)',
    );
    stdout.writeln('PASS: metrics.json generated from the pinned font bytes');
  } on _UsageException catch (error) {
    stderr.writeln('FAIL: ${error.message}');
    stderr.write(_usage);
    exitCode = 2;
  } on FontMetricsException catch (error) {
    stderr.writeln('FAIL: ${error.message}');
    exitCode = 1;
  } on FileSystemException catch (error) {
    stderr.writeln('FAIL: ${error.message} (${error.path})');
    exitCode = 1;
  }
}

ParsedFont _readFont(
  Directory directory,
  String fileName,
  String style,
  int weight,
) {
  final File file = File('${directory.path}/$fileName');
  if (!file.existsSync()) {
    throw FontMetricsException('missing bundled font ${file.path}');
  }
  final Uint8List bytes = file.readAsBytesSync();
  final String asset = 'assets/fonts/$fileName';
  return parseFont(
    bytes: bytes,
    asset: asset,
    style: style,
    weight: weight,
    pinnedSha256: pinnedFontSha256[fileName],
  );
}

void _printFont(ParsedFont font) {
  stdout.writeln(
    '  ${font.style}: ${font.advances.length} codepoints, '
    '${font.glyphCount} glyphs, unitsPerEm ${font.unitsPerEm}, '
    'ascender ${font.ascender}, descender ${font.descender}, '
    'cmap format ${font.cmapFormat}, SHA-256 ${font.sha256}',
  );
}

Directory _defaultFontDir() {
  return Directory.fromUri(
    Platform.script.resolve('../../apps/feldexa_app/assets/fonts/'),
  );
}

Directory _repositoryRoot() {
  return Directory.fromUri(Platform.script.resolve('../../'));
}

_Options _parseArguments(List<String> arguments) {
  bool check = false;
  bool help = false;
  Directory? fontDirectory;
  File? outputFile;
  for (int index = 0; index < arguments.length; index++) {
    final String argument = arguments[index];
    switch (argument) {
      case '--check':
        check = true;
        break;
      case '--help' || '-h':
        help = true;
        break;
      case '--font-dir':
        index++;
        if (index >= arguments.length) {
          throw _UsageException('--font-dir requires a value');
        }
        fontDirectory = Directory(arguments[index]);
        break;
      case '--output':
        index++;
        if (index >= arguments.length) {
          throw _UsageException('--output requires a value');
        }
        outputFile = File(arguments[index]);
        break;
      default:
        if (argument.startsWith('--font-dir=')) {
          fontDirectory = Directory(argument.substring('--font-dir='.length));
        } else if (argument.startsWith('--output=')) {
          outputFile = File(argument.substring('--output='.length));
        } else {
          throw _UsageException('unknown argument "$argument"');
        }
        break;
    }
  }
  return _Options(
    check: check,
    help: help,
    fontDirectory: fontDirectory,
    outputFile: outputFile,
  );
}

class _UsageException implements Exception {
  _UsageException(this.message);

  final String message;
}

class _Options {
  const _Options({
    required this.check,
    required this.help,
    required this.fontDirectory,
    required this.outputFile,
  });

  final bool check;
  final bool help;
  final Directory? fontDirectory;
  final File? outputFile;
}

const String _usage = '''
T007 font-advance metrics generator

Usage:
  dart run tools/metrics/generate_font_metrics.dart [options]

Options:
  --check            Do not write; fail unless the committed metrics.json is
                     byte-for-byte identical to a fresh generation.
  --font-dir DIR     Read NotoSans-Regular.ttf and NotoSans-Bold.ttf from DIR
                     instead of apps/feldexa_app/assets/fonts.
  --output FILE      Write metrics JSON to FILE instead of the bundled asset.
  -h, --help         Show this help.

The generator is fail-closed: it verifies the T006 SHA-256 pins, rejects
variable/CFF fonts, requires the FR-067 German glyph coverage, and emits a
deterministic document (schema v1, metricsVersion noto-sans-2.013-v1).
''';
