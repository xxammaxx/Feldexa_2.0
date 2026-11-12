// T009 deterministic synthetic fixture generator.
//
// Writes the canonical dev fixture catalogue, expected OCR JSON, and valid
// synthetic PDFs under `apps/feldexa_app/assets/fixtures/`. That directory is
// deliberately **not** a Flutter asset: pubspec assets are packaged into every
// Android build. A byte-identical mirror is written to
// `apps/feldexa_app/web/fixtures/`, which the Flutter Web dev server and
// `flutter build web` serve at `/fixtures/`, and the PDFs are also copied to
// `tools/corpus/synthetic/` for the Android `adb push` workflow in
// `quickstart.md` §2. `--check` regenerates in memory and fails on any byte
// drift, so repeatability is executable rather than asserted.
//
// Usage:
//   dart run tools/corpus/synthetic/generate.dart
//   dart run tools/corpus/synthetic/generate.dart --check
//
// Exit codes: 0 success/current, 1 drift or I/O error, 2 usage error.
//
// This is a host build tool. It produces no SIMULATED, EMULATOR, or DEVICE
// evidence: the fixtures are SIMULATED development inputs, not runtime proof.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'crypto.dart';
import 'fixtures.dart';
import 'pdf_writer.dart';

const String generatorVersion = '1.0.0';
const String catalogVersion = 'fixtures-1.0.0';
const String generatorPath = 'tools/corpus/synthetic/generate.dart';
const String generationDate = '2026-11-12';
const String canonicalDirectory = 'apps/feldexa_app/assets/fixtures';
const String webDirectory = 'apps/feldexa_app/web/fixtures';
const String corpusDirectory = 'tools/corpus/synthetic';

Future<void> main(List<String> arguments) async {
  try {
    final _Options options = _parseArguments(arguments);
    if (options.help) {
      stdout.write(_usage);
      return;
    }
    final Directory root = _repositoryRoot(options.root);
    final _Outputs outputs = _buildOutputs(root);

    if (options.check) {
      final bool current = _check(root, outputs);
      if (!current) {
        exitCode = 1;
      }
      return;
    }
    _write(root, outputs);
  } on FormatException catch (error) {
    stderr.writeln('error: ${error.message}');
    exitCode = 2;
  } on _UsageException catch (error) {
    stderr.writeln('error: ${error.message}');
    stderr.write(_usage);
    exitCode = 2;
  } on FileSystemException catch (error) {
    stderr.writeln('error: ${error.message} (${error.path ?? ''})');
    exitCode = 1;
  }
}

class _Options {
  const _Options({required this.check, required this.help, required this.root});

  final bool check;
  final bool help;
  final String? root;
}

_Options _parseArguments(List<String> arguments) {
  bool check = false;
  bool help = false;
  String? root;
  for (int index = 0; index < arguments.length; index++) {
    final String argument = arguments[index];
    switch (argument) {
      case '--check':
        check = true;
      case '--help' || '-h':
        help = true;
      case '--root':
        index++;
        if (index >= arguments.length || arguments[index].isEmpty) {
          throw const _UsageException('--root requires a directory');
        }
        root = arguments[index];
      default:
        throw _UsageException('unknown argument "$argument"');
    }
  }
  return _Options(check: check, help: help, root: root);
}

Directory _repositoryRoot(String? override) {
  Directory directory = override == null
      ? Directory.current
      : Directory(override).absolute;
  while (!File('${directory.path}/pubspec.yaml').existsSync()) {
    final Directory parent = directory.parent;
    if (parent.path == directory.path) {
      throw const FileSystemException(
        'could not locate the repository root (no pubspec.yaml)',
      );
    }
    directory = parent;
  }
  return directory;
}

class _Outputs {
  _Outputs(this.files, this.catalogBytes);

  /// Repository-relative POSIX path -> bytes.
  final Map<String, Uint8List> files;
  final Uint8List catalogBytes;
}

_Outputs _buildOutputs(Directory root) {
  final List<FormFixture> forms = buildFormFixtures();
  final Map<String, Uint8List> files = <String, Uint8List>{};
  final List<Map<String, Object?>> fixtures = <Map<String, Object?>>[];

  for (final FormFixture form in forms) {
    final Uint8List pdf = form.document().build();
    final String sha256 = sha256Hex(pdf);
    final Map<String, Object?> ocr = <String, Object?>{
      'schemaVersion': 1,
      'fixtureId': form.id,
      'language': 'de',
      'evidenceClass': 'simulated',
      'generatorVersion': generatorVersion,
      'pages': form.ocrPages().map((OcrPage page) => page.toJson()).toList(),
    };
    final Uint8List ocrBytes = _jsonBytes(ocr);
    final int blockCount = form.ocrPages().fold<int>(
      0,
      (int total, OcrPage page) => total + page.blocks.length,
    );

    files['$canonicalDirectory/${form.id}.pdf'] = pdf;
    files['$corpusDirectory/${form.id}.pdf'] = pdf;
    files['$canonicalDirectory/${form.id}.expected-ocr.json'] = ocrBytes;

    fixtures.add(<String, Object?>{
      'id': form.id,
      'kind': 'synthetic',
      'role': form.role,
      'status': 'valid',
      'title': form.title,
      'description': form.description,
      'path': '${form.id}.pdf',
      'assetPath': '$canonicalDirectory/${form.id}.pdf',
      'corpusPath': '$corpusDirectory/${form.id}.pdf',
      'sha256': sha256,
      'sizeBytes': pdf.length,
      'pageCount': form.pages.length,
      'provenance': _provenance(form.title),
      'synthetic': _synthetic(),
      'strata': form.strata,
      'pages': _pageJson(form),
      'groundTruth': <String, Object?>{
        'notes':
            'Explicit display-space rectangles; independent of the generator '
            'layout estimate. Rects are the blank input regions, not labels.',
        'fields': form.pages
            .expand((FormPage page) => page.fields)
            .map((GtField field) => field.toJson())
            .toList(),
      },
      'expectedOcr': <String, Object?>{
        'path': '${form.id}.expected-ocr.json',
        'schemaVersion': 1,
        'language': 'de',
        'pageCount': form.pages.length,
        'blockCount': blockCount,
      },
      'expectedError': null,
    });
  }

  final _ProtectedFixture protected = _buildProtectedFixture();
  final Uint8List protectedPdf = protected.document.build();
  files['$canonicalDirectory/sf-protected.pdf'] = protectedPdf;
  files['$corpusDirectory/sf-protected.pdf'] = protectedPdf;
  fixtures.add(<String, Object?>{
    'id': 'sf-protected',
    'kind': 'synthetic',
    'role': 'import-failure',
    'status': 'encrypted',
    'title': 'Geschütztes synthetisches Dokument (RC4 40-bit)',
    'description':
        'Genuine V1/R2 Standard Security Handler PDF with a fixed owner '
        'password and the documented non-empty user password '
        '"feldexa-user". Used to prove IMP-001 rejection without a password '
        'prompt.',
    'path': 'sf-protected.pdf',
    'assetPath': '$canonicalDirectory/sf-protected.pdf',
    'corpusPath': '$corpusDirectory/sf-protected.pdf',
    'sha256': sha256Hex(protectedPdf),
    'sizeBytes': protectedPdf.length,
    'pageCount': 1,
    'provenance': _provenance('Protected import fixture'),
    'synthetic': _synthetic(),
    'strata': <String>['import:encrypted', 'security:rc4-40'],
    'pages': <Map<String, Object?>>[
      <String, Object?>{
        'index': 0,
        'widthPt': a4Width,
        'heightPt': a4Height,
        'rotation': 0,
      },
    ],
    'groundTruth': <String, Object?>{
      'notes': 'Import must be rejected before any document is created.',
      'fields': <Object>[],
    },
    'expectedOcr': null,
    'expectedError': 'IMP-001',
    'encryption': <String, Object?>{
      'handler': 'Standard',
      'version': 1,
      'revision': 2,
      'keyLengthBits': 40,
      'userPassword': 'feldexa-user',
      'ownerPassword': 'feldexa-owner',
      'note':
          'Fixture-only legacy encryption; never used for product data. '
          'A non-empty user password gates the content; the documented test '
          'password opens it, empty/wrong passwords are rejected.',
    },
  });

  final FormFixture? primary = forms.isEmpty ? null : forms.first;
  if (primary == null) {
    throw const FormatException('at least one form fixture is required');
  }
  final Uint8List primaryPdf = files['$canonicalDirectory/${primary.id}.pdf']!;
  final int retained = (primaryPdf.length * 6) ~/ 10;
  final Uint8List truncated = Uint8List.fromList(
    primaryPdf.sublist(0, retained),
  );
  final String truncatedPreview = latin1.decode(
    truncated.sublist(0, truncated.length > 8 ? 8 : truncated.length),
  );
  if (truncatedPreview.startsWith('%PDF-') == false) {
    throw const FormatException('truncated fixture lost its PDF header');
  }
  files['$canonicalDirectory/sf-truncated.pdf'] = truncated;
  files['$corpusDirectory/sf-truncated.pdf'] = truncated;
  fixtures.add(<String, Object?>{
    'id': 'sf-truncated',
    'kind': 'synthetic',
    'role': 'import-failure',
    'status': 'truncated',
    'title': 'Abgeschnittenes synthetisches Dokument',
    'description':
        'Deterministic 60 % prefix of sf-001. The xref/EOF trailer is absent, '
        'so a structural check must report IMP-002 and must not claim password '
        'protection.',
    'path': 'sf-truncated.pdf',
    'assetPath': '$canonicalDirectory/sf-truncated.pdf',
    'corpusPath': '$corpusDirectory/sf-truncated.pdf',
    'sha256': sha256Hex(truncated),
    'sizeBytes': truncated.length,
    'pageCount': 0,
    'provenance': _provenance('Truncated import fixture'),
    'synthetic': _synthetic(),
    'strata': <String>['import:truncated'],
    'pages': <Object>[],
    'groundTruth': <String, Object?>{
      'notes': 'No document may be created.',
      'fields': <Object>[],
    },
    'expectedOcr': null,
    'expectedError': 'IMP-002',
    'truncation': <String, Object?>{
      'sourceFixture': primary.id,
      'sourceBytes': primaryPdf.length,
      'retainedBytes': retained,
      'returnsTo': 'IMPORTANT: not a valid PDF; no %%EOF trailer',
    },
  });

  final Uint8List notPdf = _notAPdfBytes();
  files['$canonicalDirectory/sf-not-a-pdf.pdf'] = notPdf;
  files['$corpusDirectory/sf-not-a-pdf.pdf'] = notPdf;
  fixtures.add(<String, Object?>{
    'id': 'sf-not-a-pdf',
    'kind': 'synthetic',
    'role': 'import-failure',
    'status': 'not-a-pdf',
    'title': 'Synthetische Textdatei mit .pdf-Endung',
    'description':
        'UTF-8 text saved with a .pdf extension. Used for the IMP-004 '
        'not-a-PDF rejection path.',
    'path': 'sf-not-a-pdf.pdf',
    'assetPath': '$canonicalDirectory/sf-not-a-pdf.pdf',
    'corpusPath': '$corpusDirectory/sf-not-a-pdf.pdf',
    'sha256': sha256Hex(notPdf),
    'sizeBytes': notPdf.length,
    'pageCount': 0,
    'provenance': _provenance('Not-a-PDF import fixture'),
    'synthetic': _synthetic(),
    'strata': <String>['import:not-a-pdf'],
    'pages': <Object>[],
    'groundTruth': <String, Object?>{
      'notes': 'No document may be created.',
      'fields': <Object>[],
    },
    'expectedOcr': null,
    'expectedError': 'IMP-004',
    'mediaType': 'text/plain',
  });

  for (final Map<String, Object?> fixture in fixtures) {
    final String assetPath = fixture['assetPath'] as String;
    fixture['webPath'] = assetPath.replaceFirst(
      canonicalDirectory,
      webDirectory,
    );
  }

  final Map<String, Object?> catalog = <String, Object?>{
    'schemaVersion': 1,
    'catalogVersion': catalogVersion,
    'description':
        'Deterministic synthetic development fixtures for the SIMULATED Web '
        'editor surface (US9; FR-086). Not an acceptance corpus and not '
        'evidence about Android runtime behavior.',
    'evidenceClass': 'simulated',
    'rights': <String, Object?>{
      'kind': 'synthetic',
      'thirdPartyContent': false,
      'containsPersonalData': false,
      'legalBasis':
          'synthetic; project-generated fictional content, no third-party '
          'work.',
      'rightsCleared': true,
      'notes':
          'All names, authorities, addresses, and form text are fictional. '
          'No real person, real authority form, scan, or font outline is '
          'included. The forms use base-14 Helvetica and carry a visible '
          'synthetic marker.',
    },
    'generator': <String, Object?>{
      'path': generatorPath,
      'version': generatorVersion,
      'seed': 0,
      'deterministic': true,
      'checkCommand': 'dart run $generatorPath --check',
      'notes':
          'No randomness, wall clock, locale, or network input. Fixed object '
          'order, fixed document ID, fixed generation date.',
    },
    'generationDate': generationDate,
    'delivery': <String, Object?>{
      'canonicalDevDirectory': canonicalDirectory,
      'webDirectory': webDirectory,
      'corpusDirectory': corpusDirectory,
      'flutterAssetsDeclared': false,
      'webBaseUrl': '/fixtures',
      'androidRelease':
          'never packaged: the fixtures are not pubspec assets '
          'and web/ is not part of an Android build',
      'androidTestDelivery': 'adb push $corpusDirectory/sf-*.pdf',
    },
    'fixtureCount': fixtures.length,
    'fixtures': fixtures,
  };

  final Uint8List catalogBytes = _jsonBytes(catalog);
  files['$canonicalDirectory/catalog.json'] = catalogBytes;

  // The Web dev server and `flutter build web` serve files from `web/` at the
  // site root. Mirror every canonical generated file there so the browser can
  // fetch `/fixtures/...` without relying on global Flutter assets.
  for (final MapEntry<String, Uint8List> entry in files.entries.toList(
    growable: false,
  )) {
    if (!entry.key.startsWith('$canonicalDirectory/')) {
      continue;
    }
    final String name = entry.key.substring(canonicalDirectory.length + 1);
    files['$webDirectory/$name'] = entry.value;
  }

  _verifyDeterminism(forms, protected, primaryPdf, truncated, notPdf);
  return _Outputs(files, catalogBytes);
}

void _verifyDeterminism(
  List<FormFixture> forms,
  _ProtectedFixture protected,
  Uint8List primaryPdf,
  Uint8List truncated,
  Uint8List notPdf,
) {
  for (final FormFixture form in forms) {
    final Uint8List first = form.document().build();
    final Uint8List second = form.document().build();
    if (!_bytesEqual(first, second)) {
      throw FormatException('${form.id} is not deterministic across builds');
    }
  }
  if (!_bytesEqual(protected.document.build(), protected.document.build())) {
    throw const FormatException('sf-protected is not deterministic');
  }
  if (forms.isNotEmpty) {
    final Uint8List primaryAgain = forms.first.document().build();
    if (!_bytesEqual(primaryPdf, primaryAgain)) {
      throw const FormatException('primary fixture is not deterministic');
    }
  }
  if (truncated.length >= primaryPdf.length) {
    throw const FormatException('truncated fixture is not shorter');
  }
  if (notPdf.length < 16) {
    throw const FormatException('not-a-PDF fixture is too small');
  }
}

class _ProtectedFixture {
  _ProtectedFixture(this.document);
  final PdfDocument document;
}

_ProtectedFixture _buildProtectedFixture() {
  final PdfPage page = PdfPage(widthPt: a4Width, heightPt: a4Height);
  page.text(
    x: 56.7,
    yTop: 76,
    size: 15,
    text: 'Geschütztes synthetisches Dokument',
    bold: true,
  );
  page.text(
    x: 56.7,
    yTop: 110,
    size: 10,
    text: 'Dieses Dokument ist durch ein Benutzerkennwort geschützt.',
  );
  page.text(
    x: 56.7,
    yTop: 128,
    size: 10,
    text: 'Benutzerkennwort gesetzt; Testfixture für IMP-001.',
  );
  page.line(56.7, 160, a4Width - 56.7, 160, width: 1);
  page.text(
    x: 56.7,
    yTop: 176,
    size: 9,
    text: 'Synthetisches Testdokument – keine personenbezogenen Daten.',
  );
  return _ProtectedFixture(
    PdfDocument(
      pages: <PdfPage>[page],
      encryption: PdfEncryption(
        ownerPassword: 'feldexa-owner',
        userPassword: 'feldexa-user',
        documentId: PdfDocument.documentId,
      ),
    ),
  );
}

Uint8List _notAPdfBytes() {
  const String text =
      'Dies ist keine PDF-Datei.\n'
      'Synthetische Textdatei für die Importfehlerprüfung (IMP-004).\n'
      'Sie enthält keine personenbezogenen Daten und dient ausschließlich\n'
      'der Entwicklung und Prüfung des SIMULATED-Web-Editors.\n';
  return Uint8List.fromList(utf8.encode(text));
}

Map<String, Object?> _provenance(String sourceTitle) {
  return <String, Object?>{
    'source':
        'Generated by $generatorPath ($sourceTitle); fictional Musterstadt '
        'authority form.',
    'retrievalDate': generationDate,
    'legalBasis': 'synthetic; no third-party content',
    'rightsCleared': true,
    'containsPersonalData': false,
    'rightsReference':
        'specs/001-scanned-form-workflow/research.md D-16/D-18; '
        'constitution Principle VI',
    'notes':
        'Project-generated content only. Any change requires a new catalog '
        'version; regeneration is byte-checked.',
  };
}

Map<String, Object?> _synthetic() {
  return <String, Object?>{
    'generator': generatorPath,
    'seed': 0,
    'notes':
        'Deterministic layout source; ground truth and expected OCR are '
        'emitted from the same declarations.',
  };
}

List<Map<String, Object?>> _pageJson(FormFixture form) {
  return form.pages
      .map(
        (FormPage page) => <String, Object?>{
          'index': page.pageIndex,
          'widthPt': page.width,
          'heightPt': page.height,
          'rotation': page.page.rotation,
        },
      )
      .toList();
}

Uint8List _jsonBytes(Object? value) {
  const JsonEncoder encoder = JsonEncoder.withIndent('  ');
  return Uint8List.fromList(utf8.encode('${encoder.convert(value)}\n'));
}

bool _check(Directory root, _Outputs outputs) {
  bool current = true;
  for (final MapEntry<String, Uint8List> entry in outputs.files.entries) {
    final File file = File('${root.path}/${entry.key}');
    if (!file.existsSync()) {
      stdout.writeln('MISSING ${entry.key}');
      current = false;
      continue;
    }
    final Uint8List actual = file.readAsBytesSync();
    if (!_bytesEqual(actual, entry.value)) {
      stdout.writeln(
        'DRIFT ${entry.key} (expected ${entry.value.length} bytes '
        'sha256 ${sha256Hex(entry.value)}; actual ${actual.length} bytes '
        'sha256 ${sha256Hex(actual)})',
      );
      current = false;
    }
  }
  if (current) {
    stdout.writeln(
      'OK all ${outputs.files.length} generated files are byte-for-byte '
      'current (catalog sha256 ${sha256Hex(outputs.catalogBytes)})',
    );
  } else {
    stdout.writeln(
      'FAIL ${outputs.files.length} generated files checked; drift or missing '
      'files require regeneration.',
    );
  }
  return current;
}

void _write(Directory root, _Outputs outputs) {
  for (final MapEntry<String, Uint8List> entry in outputs.files.entries) {
    final File file = File('${root.path}/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(entry.value, flush: true);
    stdout.writeln(
      'wrote ${entry.key} (${entry.value.length} bytes, '
      'sha256 ${sha256Hex(entry.value)})',
    );
  }
  stdout.writeln(
    'T009 synthetic fixtures: ${outputs.files.length} files; '
    'catalog $catalogVersion; generator $generatorVersion.',
  );
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int index = 0; index < a.length; index++) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

class _UsageException implements Exception {
  const _UsageException(this.message);
  final String message;
}

const String _usage = '''
T009 deterministic synthetic fixture generator

Usage:
  dart run tools/corpus/synthetic/generate.dart [--check] [--root DIR]
  dart run tools/corpus/synthetic/generate.dart --help

Options:
  --check     Regenerate in memory and fail if any committed generated file
              differs byte-for-byte. Nothing is written.
  --root DIR  Repository root (default: the nearest ancestor with pubspec.yaml).
  --help, -h  Show this help.

Outputs:
  apps/feldexa_app/assets/fixtures/catalog.json
  apps/feldexa_app/assets/fixtures/sf-*.pdf
  apps/feldexa_app/assets/fixtures/sf-*.expected-ocr.json
    (canonical dev files; NOT declared as Flutter assets)
  apps/feldexa_app/web/fixtures/...       (byte-identical Web delivery mirror)
  tools/corpus/synthetic/sf-*.pdf         (byte-identical Android/corpus copies)

Exit codes: 0 success/current, 1 drift or I/O error, 2 usage error.
''';
