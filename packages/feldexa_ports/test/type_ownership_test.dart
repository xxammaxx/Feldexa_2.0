// T013 type-ownership and dependency-direction tests (host VM, NONE evidence).
//
// These tests pin the Foundational Type Ownership table in `tasks.md` and
// `contracts/ports.md` §1:
//   * the T013 barrel re-exports the T014 `errors.dart` and `evidence.dart`
//     declarations instead of declaring them a second time;
//   * port DTO fields use the canonical `feldexa_core` and `feldexa_export`
//     types (a compile-time assignment proof);
//   * no T013-owned file declares a canonical type owned by another task;
//   * `feldexa_ports` has no platform or Flutter import, and neither
//     `feldexa_core` nor `feldexa_export` imports `feldexa_ports`;
//   * the barrel re-exports declarations only, never the core/export models.
//
// No test here produces SIMULATED, EMULATOR, or DEVICE runtime evidence.

import 'dart:io';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/errors.dart' as error_entry;
import 'package:feldexa_ports/evidence.dart' as evidence_entry;
import 'package:feldexa_ports/feldexa_ports.dart' as ports;
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// Canonical types that T013 may consume but must never redeclare.
const List<String> _canonicalTypes = <String>[
  // T014
  'EvidenceClass',
  'CapabilityEvidence',
  'FeldexaException',
  'ErrorSeverity',
  'ImportRejectionKind',
  // T015
  'Rect',
  'Size',
  'Point',
  // T016
  'PageGeometry',
  // T017
  'Document',
  'SourceFileRef',
  'Page',
  'PageFailure',
  'AnalysisState',
  'DocumentMeta',
  'DocumentStatus',
  'DocumentPreferences',
  'TemplateOrigin',
  'DurablePointer',
  // T018
  'FieldSuggestion',
  'ConfirmedField',
  'FieldValue',
  'FieldVerification',
  'SignatureMark',
  'FieldType',
  'Provenance',
  'SuggestionEvidence',
  'FieldValidation',
  'WarningCode',
  // T020
  'DurabilityStatus',
  'Revision',
  'RevisionKind',
  'RevisionContent',
  // T021
  'Template',
  'TemplateVersion',
  'TemplateVersionPointer',
  'TemplateMeta',
  'TemplateVersionContent',
  'StoredTemplate',
  // T022
  'ExportPlan',
  'ExportValidation',
  'ExportArtifact',
  'ArtifactVerification',
  // T057 and T095
  'FieldSuggestionSet',
  'DocumentSummary',
];

void main() {
  test(
    'the barrel re-exports the canonical T014 declarations exactly once',
    () {
      final evidence_entry.CapabilityEvidence fromEvidence = evidence_entry
          .CapabilityEvidence.android(adapterId: 'android.pdfbox.v1');
      final ports.CapabilityEvidence fromBarrel = fromEvidence;
      final ports.EvidenceClass evidenceClass =
          evidence_entry.EvidenceClass.none;

      final error_entry.ImportRejectionKind shimKind =
          error_entry.ImportRejectionKind.notPdf;
      final ports.ImportRejectionKind barrelKind = shimKind;

      final error_entry.FeldexaException shimError =
          error_entry.StorageFullException();
      final ports.FeldexaException barrelError = shimError;

      expect(identical(fromEvidence, fromBarrel), isTrue);
      expect(evidenceClass, ports.EvidenceClass.none);
      expect(barrelKind, ports.ImportRejectionKind.notPdf);
      expect(barrelError.code, 'SAVE-001');
    },
  );

  test('port DTOs consume the canonical core and export types', () {
    final ports.ImportedSource imported = ports.ImportedSource(
      documentId: fixtureUuid(2),
      sourceId: fixtureUuid(1),
      sha256: fixtureSha256,
      sizeBytes: 1234,
      pageCount: 1,
      pages: <PageGeometry>[fixtureGeometry()],
      evidence: fixtureAndroidEvidence(),
    );
    final ports.LoadedDocument loaded = ports.LoadedDocument(
      meta: fixtureDocumentMeta(),
      content: fixtureRevisionContent(),
      sourceBytes: fixtureBytes(8),
      evidence: fixtureAndroidEvidence(),
    );
    final ports.LoadedTemplate loadedTemplate = ports.LoadedTemplate(
      template: fixtureStoredTemplate(),
      sourceBytes: fixtureBytes(8),
      evidence: fixtureAndroidEvidence(),
    );
    final ports.SourceIntegrity integrity = ports.SourceIntegrity(
      readable: true,
      actualSha256: fixtureSha256,
      pageCount: 1,
      evidence: fixtureAndroidEvidence(adapterId: 'android.keystore.v1'),
    );
    final ports.ExportRequest exportRequest = ports.ExportRequest(
      documentId: fixtureUuid(2),
      revisionId: fixtureUuid(3),
      plan: fixtureExportPlan(),
    );
    final ports.ExportResult exportResult = ports.ExportResult(
      artifact: fixtureExportArtifact(),
      evidence: fixtureAndroidEvidence(),
    );

    final PageGeometry geometry = imported.pages.single;
    final DocumentMeta meta = loaded.meta;
    final RevisionContent content = loaded.content;
    final StoredTemplate storedTemplate = loadedTemplate.template;
    final ports.CapabilityEvidence integrityEvidence = integrity.evidence;
    final ExportPlan plan = exportRequest.plan;
    final ExportArtifact artifact = exportResult.artifact;

    expect(geometry.mediaBox.width, 595);
    expect(meta.title, 'Antrag');
    expect(content.pageCount, 1);
    expect(storedTemplate.version.versionNumber, 1);
    expect(integrityEvidence.evidenceClass, ports.EvidenceClass.none);
    expect(plan.pageCount, 1);
    expect(artifact.pageCount, 1);
  });

  test('PdfExportPort.validate wraps canonical validation with evidence', () {
    final Directory root = _packageRoot();
    final Directory repoRoot = root.parent.parent;
    final String exportPlanSource = File(
      '${repoRoot.path}/packages/feldexa_export/lib/src/model/export_plan.dart',
    ).readAsStringSync();

    // T022 still owns `ExportValidation`; the export package must not import
    // the ports evidence type. T013 owns only the wrapper that pairs the
    // canonical validation with `CapabilityEvidence` (owner decision of
    // 2026-11-15); it must not duplicate or reshape `ExportValidation`.
    expect(exportPlanSource, contains('final class ExportValidation'));
    expect(exportPlanSource, isNot(contains('CapabilityEvidence')));
    expect(exportPlanSource, isNot(contains('package:feldexa_ports')));

    final ExportValidation blocking = fixtureBlockingExportValidation();
    final ports.ExportValidationResult result = fixtureExportValidationResult(
      validation: blocking,
      evidence: fixtureSimulatedEvidence(adapterId: 'web.sim.export.v1'),
    );
    final ExportValidation canonical = result.validation;

    expect(canonical, same(blocking));
    expect(result.isValid, isFalse);
    expect(result.isBlocking, isTrue);
    expect(result.warnings, hasLength(1));
    expect(result.warnings.single.code, 'EXP-001');
    expect(result.evidence.evidenceClass, ports.EvidenceClass.simulated);
    expect(result.evidence.simulated, isTrue);

    final ports.ExportResult exportResult = ports.ExportResult(
      artifact: fixtureExportArtifact(),
      evidence: fixtureAndroidEvidence(adapterId: 'android.pdfbox.v1'),
    );
    expect(exportResult.evidence.evidenceClass, ports.EvidenceClass.none);
    expect(exportResult.evidence.simulated, isFalse);
  });

  test('T013 files declare no canonical type owned by another task', () {
    final Directory packageRoot = _packageRoot();
    final List<File> files = _t013Files(packageRoot);
    final RegExp declaration = RegExp(
      r'\b(?:class|enum|mixin|typedef|extension)\s+(?:type\s+)?(' +
          _canonicalTypes.join('|') +
          r')\b',
    );

    expect(files, isNotEmpty);
    for (final File file in files) {
      final String source = file.readAsStringSync();
      final RegExpMatch? match = declaration.firstMatch(source);
      expect(
        match,
        isNull,
        reason:
            '${file.path} redeclares ${match?.group(1)}, which is owned by '
            'another task',
      );
    }
  });

  test('feldexa_ports has no Flutter, platform, or plugin import', () {
    final Directory packageRoot = _packageRoot();
    final List<File> files = _dartFiles(Directory('${packageRoot.path}/lib'));
    final RegExp forbiddenImport = RegExp(
      r"""^\s*import\s+['"](dart:(?:io|ffi|html|js)|package:flutter/|"""
      r"""package:pdfrx/|package:path_provider/|"""
      r"""package:shared_preferences/)""",
      multiLine: true,
    );

    for (final File file in files) {
      final String source = file.readAsStringSync();
      final RegExpMatch? match = forbiddenImport.firstMatch(source);
      expect(
        match,
        isNull,
        reason:
            '${file.path} imports ${match?.group(0)}, which would make the '
            'ports package platform-dependent',
      );
    }
  });

  test('core and export never import feldexa_ports', () {
    final Directory root = _packageRoot();
    final Directory repoRoot = root.parent.parent;
    final List<Directory> packages = <Directory>[
      Directory('${repoRoot.path}/packages/feldexa_core/lib'),
      Directory('${repoRoot.path}/packages/feldexa_export/lib'),
    ];

    final RegExp portsDependency = RegExp(
      r"""(?:import|export)\s+['"]package:feldexa_ports""",
    );

    for (final Directory directory in packages) {
      for (final File file in _dartFiles(directory)) {
        final String source = file.readAsStringSync();
        expect(
          portsDependency.hasMatch(source),
          isFalse,
          reason: '${file.path} must not import or export feldexa_ports',
        );
      }
    }
  });

  test('the barrel re-exports declarations only, not canonical models', () {
    final Directory packageRoot = _packageRoot();
    final String barrel = File('${packageRoot.path}/lib/feldexa_ports.dart')
        .readAsStringSync();
    final RegExp forbiddenExport = RegExp(
      r"""export\s+['"]package:feldexa_(?:core|export)""",
    );

    expect(forbiddenExport.hasMatch(barrel), isFalse);
    expect(barrel, contains("export 'errors.dart';"));
    expect(barrel, contains("export 'evidence.dart';"));
    expect(barrel, contains("export 'src/descriptor.dart';"));
    expect(barrel, contains("export 'src/registry.dart';"));
  });

  test('every T013-owned file named by the task exists', () {
    final Directory root = _packageRoot();
    final List<String> expected = <String>[
      'lib/feldexa_ports.dart',
      'lib/src/descriptor.dart',
      'lib/src/registry.dart',
      'lib/src/ports/document_import_port.dart',
      'lib/src/ports/page_raster_port.dart',
      'lib/src/ports/ocr_port.dart',
      'lib/src/ports/secure_store_port.dart',
      'lib/src/ports/pdf_export_port.dart',
      'lib/src/ports/delivery_port.dart',
      'lib/src/ports/lifecycle_port.dart',
      'lib/src/ports/clock_port.dart',
      'lib/src/ports/id_port.dart',
      'lib/src/ports/diagnostics_port.dart',
      'lib/src/dto/import_dto.dart',
      'lib/src/dto/raster_dto.dart',
      'lib/src/dto/ocr_dto.dart',
      'lib/src/dto/store_dto.dart',
      'lib/src/dto/export_dto.dart',
      'lib/src/dto/delivery_dto.dart',
      'lib/src/dto/lifecycle_dto.dart',
    ];

    for (final String relative in expected) {
      expect(
        File('${root.path}/$relative').existsSync(),
        isTrue,
        reason: 'missing $relative',
      );
    }
  });
}

Directory _packageRoot() {
  Directory current = Directory.current.absolute;
  for (int depth = 0; depth < 12; depth++) {
    if (_isPortsPackage(current)) {
      return current;
    }
    final Directory candidate = Directory(
      '${current.path}/packages/feldexa_ports',
    );
    if (_isPortsPackage(candidate)) {
      return candidate;
    }
    final Directory parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }
  throw StateError('could not locate packages/feldexa_ports from the test');
}

bool _isPortsPackage(Directory directory) {
  final File pubspec = File('${directory.path}/pubspec.yaml');
  return pubspec.existsSync() &&
      pubspec.readAsStringSync().contains('name: feldexa_ports');
}

List<File> _t013Files(Directory packageRoot) {
  return <File>[
    File('${packageRoot.path}/lib/src/descriptor.dart'),
    File('${packageRoot.path}/lib/src/registry.dart'),
    ..._dartFiles(Directory('${packageRoot.path}/lib/src/ports')),
    ..._dartFiles(Directory('${packageRoot.path}/lib/src/dto')),
  ];
}

List<File> _dartFiles(Directory directory) {
  if (!directory.existsSync()) {
    return const <File>[];
  }
  return directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((File file) => file.path.endsWith('.dart'))
      .toList(growable: false)
    ..sort((File a, File b) => a.path.compareTo(b.path));
}
