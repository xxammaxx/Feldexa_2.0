@TestOn('vm')
library;

import 'dart:io';

import 'package:feldexa_app/features/editor/page_state.dart';
import 'package:feldexa_app/features/start/import_error_mapper.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_app/l10n/app_localizations_de.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/package_root.dart';

/// T049 German import-message and error-semantics tests (FR-006–FR-008,
/// FR-094).
///
/// These are host-VM tests. They do not duplicate the two existing suites
/// wholesale: `import_error_mapper_test.dart` owns the mapper's internal state
/// flags and branches, `german_strings_test.dart` owns ARB/catalog parity, and
/// `page_state_test.dart` owns the editor-level `IMP-006` projection. This file
/// pins what a user actually sees and what the flow actually does:
///
///   * the exact committed German catalog sentence for every import-reachable
///     code, asserted character-for-character and cross-checked against the
///     committed catalog rows;
///   * FR-007 truthfulness: only the positive password diagnosis may claim
///     password protection, and the canonical unsupported-encryption path
///     presents the truthful `IMP-004` text;
///   * FR-094: no catalog code, machine key, path, URI, file name, or document
///     content appears in user text or in mapper identities;
///   * FR-009 flow semantics: rejected, cancelled, and untyped failures never
///     reach document creation; `IMP-006` is a success with a warning and
///     ascending 1-based pages, consistent with T044's page state;
///   * German-only user text with no English fallback.
///
/// The tests produce no `SIMULATED`, `EMULATOR`, or `DEVICE` evidence. No
/// emulator, device, browser, Android build, or platform channel is used.
const String _catalogRelativePath =
    'specs/001-scanned-form-workflow/contracts/error-catalog.de.md';

const String _documentId = '5f0c3a52-3a6a-4f0b-9c2d-1b7e4d8a6c01';
const String _sourceId = '7b2d4c1e-5f3a-4b8c-8a9d-2e6f0c1b3d42';
final String _sha256 = List<String>.filled(64, 'a').join();

// Exact `apps/feldexa_app/lib/l10n/app_de.arb` values, pinned here so a
// changed ARB, a changed getter selection, or a paraphrase fails this test.
// The catalog test below also proves each pinned sentence is exactly the
// committed `contracts/error-catalog.de.md` row.
const String _imp001Message =
    'Diese PDF-Datei ist passwortgeschützt. Feldexa kann geschützte Dateien '
    'nicht öffnen, und Ihr Passwort wird weder abgefragt noch gespeichert.';
const String _imp001Recovery =
    'Bitte entfernen Sie den Schutz in einem PDF-Programm, das Sie dafür '
    'verwenden dürfen, und importieren Sie die Datei erneut.';
const String _imp002Message =
    'Die Datei konnte nicht gelesen werden. Sie ist möglicherweise '
    'unvollständig oder beschädigt.';
const String _imp002Recovery =
    'Bitte öffnen Sie die Datei in einem PDF-Programm, speichern Sie sie '
    'erneut und versuchen Sie es noch einmal.';
const String _imp003Message =
    'Die ausgewählte Datei ist nicht mehr verfügbar. Möglicherweise wurde sie '
    'verschoben, umbenannt oder gelöscht.';
const String _imp003Recovery = 'Bitte wählen Sie die Datei erneut aus.';
const String _imp004Message =
    'Diese Datei ist kein unterstütztes PDF. Feldexa kann nur PDF-Dokumente '
    'importieren.';
const String _imp004Recovery = 'Bitte wählen Sie eine PDF-Datei aus.';
const String _imp005Message =
    'Die Datei konnte nicht gelesen werden. Die Ursache lässt sich nicht '
    'sicher feststellen.';
const String _imp005Recovery =
    'Bitte versuchen Sie es erneut. Wenn das Problem bleibt, öffnen und '
    'speichern Sie die Datei in einem PDF-Programm.';
const String _imp006Template =
    'Einige Seiten konnten nicht gelesen werden: {pages}. Die übrigen Seiten '
    'sind nutzbar. Ein Export des vollständigen Dokuments ist dadurch '
    'beeinträchtigt.';
const String _imp006Recovery =
    'Sie können die betroffenen Seiten prüfen und das Dokument trotzdem '
    'weiterbearbeiten.';
const String _imp007Message =
    'Die Datei ist zu groß. Feldexa kann PDF-Dateien bis 80 MiB '
    '(83.886.080 Bytes) importieren.';
const String _imp007Recovery =
    'Bitte verkleinern Sie die Datei, zum Beispiel durch eine niedrigere '
    'Scan-Auflösung, und importieren Sie sie erneut.';
const String _save001Message =
    'Der Speicherplatz reicht nicht aus. Der letzte gespeicherte Stand ist '
    'erhalten; die neuesten Änderungen sind noch nicht dauerhaft gespeichert.';
const String _save001Recovery =
    'Bitte geben Sie Speicherplatz frei und versuchen Sie es erneut. Feldexa '
    'löscht keine Ihrer Dokumente.';
const String _save002Message =
    'Die gespeicherten Daten können nicht entschlüsselt werden, weil der '
    'zugehörige Schlüssel nicht mehr verfügbar ist; das betroffene Dokument '
    'oder die betroffene Vorlage kann nicht geöffnet werden. Andere Dokumente '
    'und Vorlagen sind davon nicht betroffen.';
const String _save002Recovery =
    'Eine Wiederherstellung ist nicht möglich. Bitte wenden Sie sich an den '
    'Gerätehersteller, wenn der Schlüssel durch einen Gerätefehler verloren '
    'gegangen ist.';
const String _save003Message =
    'Speichern ist fehlgeschlagen. Der zuletzt erfolgreich gespeicherte Stand '
    'bleibt erhalten.';
const String _save003Recovery =
    'Bitte versuchen Sie es erneut. Wenn der Fehler bleibt, prüfen Sie den '
    'freien Speicherplatz.';
const String _save005Message =
    'Dieses Dokument wurde mit einer neueren Version von Feldexa gespeichert. '
    'Bitte aktualisieren Sie die App, um es zu öffnen. Die Daten bleiben '
    'unverändert.';
const String _save005Recovery =
    'Öffnen Sie das Dokument erst nach dem Update wieder.';
const String _save006Message =
    'Das Speichern konnte nicht abgeschlossen werden. Bitte versuchen Sie es '
    'erneut.';
const String _save007Message =
    'Die Änderung konnte nicht gespeichert werden, weil die Daten ungültig '
    'sind. Der letzte gespeicherte Stand bleibt erhalten.';
const String _save007Recovery =
    'Bitte prüfen Sie sehr lange Eingaben und versuchen Sie es erneut.';
const String _save008Message =
    'Die Schlüssel des Geräts sind nicht verfügbar; alle gespeicherten '
    'Dokumente und Vorlagen können vorübergehend oder dauerhaft nicht '
    'geöffnet werden. Bitte entsperren Sie das Gerät und versuchen Sie es '
    'erneut.';
const String _save008Recovery =
    'Wenn das Problem bleibt, starten Sie das Gerät neu; verlorene Schlüssel '
    'können nicht wiederhergestellt werden.';

/// Fills the `IMP-006` `{pages}` placeholder exactly as the mapper does.
String _imp006(String pages) => _imp006Template.replaceAll('{pages}', pages);

CapabilityEvidence _evidence() =>
    CapabilityEvidence.android(adapterId: 'test.fake.import.v1');

ImportedSource _source({
  int pageCount = 3,
  List<PageFailure> pageFailures = const <PageFailure>[],
}) {
  return ImportedSource(
    documentId: _documentId,
    sourceId: _sourceId,
    sha256: _sha256,
    sizeBytes: 4096,
    pageCount: pageCount,
    pages: <PageGeometry>[
      for (int index = 0; index < pageCount; index++)
        PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595.28, 841.89)),
    ],
    pageFailures: pageFailures,
    displayName: 'antrag.pdf',
    evidence: _evidence(),
  );
}

PageFailure _pageFailure(int pageIndex) => PageFailure(
  pageIndex: pageIndex,
  category: PageFailureCategory.unreadable,
  messageKey: 'IMP-006',
);

/// A raw catalog code with a machine key, like an adapter code the mapper has
/// no dedicated branch for.
final class _RawCodeException extends FeldexaException {
  _RawCodeException(String code, String message)
    : super(
        code: code,
        messageKey: 'IMP-005',
        message: message,
        retryable: true,
        severity: ErrorSeverity.error,
      );
}

final class _FakeImportPort implements DocumentImportPort {
  _FakeImportPort(this._respond);

  final Future<ImportedSource> Function() _respond;
  int calls = 0;

  @override
  Future<ImportedSource> pickAndImport(ImportRequest request) {
    calls++;
    return _respond();
  }

  @override
  Future<SourceIntegrity> verifySource(String sourceId) async =>
      throw UnimplementedError('verifySource is not part of T049');

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  static final CapabilityDescriptor _descriptor = CapabilityDescriptor(
    kind: CapabilityKind.documentImport,
    adapterId: 'test.fake.import.v1',
    version: '1',
    isSimulated: false,
    evidence: _evidence(),
    supportedFeatures: const <String>['fake'],
  );
}

/// One import-reachable failure and the exact German presentation it must
/// produce.
final class _FailureCase {
  const _FailureCase({
    required this.label,
    required this.error,
    required this.presentationCode,
    required this.message,
    required this.recovery,
    this.catalogCode,
    this.passwordProtectionConfirmed = false,
    this.isCancellation = false,
    this.isUnrecognized = false,
  });

  final String label;
  final FeldexaException error;
  final String presentationCode;
  final String? message;
  final String? recovery;

  /// Catalog row whose sentence must be presented, or `null` for a row with no
  /// user text.
  final String? catalogCode;
  final bool passwordProtectionConfirmed;
  final bool isCancellation;
  final bool isUnrecognized;
}

/// Every import-reachable code from `contracts/platform-channel.md` §2.2/§2.3
/// and §3 plus the storage codes T041 documents as import-reachable.
List<_FailureCase> _failureCases() {
  return <_FailureCase>[
    _FailureCase(
      label: 'IMP-001 password-protected',
      error: ImportRejectedException(ImportRejectionKind.passwordProtected),
      presentationCode: 'IMP-001',
      message: _imp001Message,
      recovery: _imp001Recovery,
      catalogCode: 'IMP-001',
      passwordProtectionConfirmed: true,
    ),
    _FailureCase(
      label: 'IMP-001 unsupported encryption (typed)',
      error: ImportRejectedException(ImportRejectionKind.unsupportedEncryption),
      presentationCode: 'IMP-004',
      message: _imp004Message,
      recovery: _imp004Recovery,
      catalogCode: 'IMP-004',
    ),
    _FailureCase(
      label: 'IMP-001 unsupported encryption (raw canonical key)',
      error: _RawCodeException(
        'IMP-001',
        ImportRejectionKind.unsupportedEncryption.machineMessage,
      ),
      presentationCode: 'IMP-004',
      message: _imp004Message,
      recovery: _imp004Recovery,
      catalogCode: 'IMP-004',
    ),
    _FailureCase(
      label: 'IMP-002 unreadable',
      error: ImportRejectedException(ImportRejectionKind.unreadable),
      presentationCode: 'IMP-002',
      message: _imp002Message,
      recovery: _imp002Recovery,
      catalogCode: 'IMP-002',
    ),
    _FailureCase(
      label: 'IMP-002 truncated',
      error: ImportRejectedException(ImportRejectionKind.truncated),
      presentationCode: 'IMP-002',
      message: _imp002Message,
      recovery: _imp002Recovery,
      catalogCode: 'IMP-002',
    ),
    _FailureCase(
      label: 'IMP-003 missing',
      error: ImportRejectedException(ImportRejectionKind.missing),
      presentationCode: 'IMP-003',
      message: _imp003Message,
      recovery: _imp003Recovery,
      catalogCode: 'IMP-003',
    ),
    _FailureCase(
      label: 'IMP-004 not a PDF',
      error: ImportRejectedException(ImportRejectionKind.notPdf),
      presentationCode: 'IMP-004',
      message: _imp004Message,
      recovery: _imp004Recovery,
      catalogCode: 'IMP-004',
    ),
    _FailureCase(
      label: 'IMP-004 unsupported structure',
      error: ImportRejectedException(ImportRejectionKind.unsupportedStructure),
      presentationCode: 'IMP-004',
      message: _imp004Message,
      recovery: _imp004Recovery,
      catalogCode: 'IMP-004',
    ),
    _FailureCase(
      label: 'IMP-005 unknown reason',
      error: ImportRejectedException(ImportRejectionKind.unknownReason),
      presentationCode: 'IMP-005',
      message: _imp005Message,
      recovery: _imp005Recovery,
      catalogCode: 'IMP-005',
    ),
    _FailureCase(
      label: 'IMP-007 too large',
      error: ImportRejectedException(ImportRejectionKind.tooLarge),
      presentationCode: 'IMP-007',
      message: _imp007Message,
      recovery: _imp007Recovery,
      catalogCode: 'IMP-007',
    ),
    _FailureCase(
      label: 'unmapped code',
      error: _RawCodeException('XYZ-999', 'future.unknownFailure'),
      presentationCode: 'IMP-005',
      message: _imp005Message,
      recovery: _imp005Recovery,
      catalogCode: 'IMP-005',
      isUnrecognized: true,
    ),
    _FailureCase(
      label: 'IMP-000 cancellation',
      error: ImportCancelledException(),
      presentationCode: 'IMP-000',
      message: null,
      recovery: null,
      isCancellation: true,
    ),
    _FailureCase(
      label: 'PLT-004 cancellation',
      error: _RawCodeException('PLT-004', 'platform.cancelled'),
      presentationCode: 'PLT-004',
      message: null,
      recovery: null,
      isCancellation: true,
    ),
    _FailureCase(
      label: 'SAVE-001 storage full',
      error: StorageFullException(),
      presentationCode: 'SAVE-001',
      message: _save001Message,
      recovery: _save001Recovery,
      catalogCode: 'SAVE-001',
    ),
    _FailureCase(
      label: 'SAVE-002 aggregate key unavailable',
      error: KeyUnavailableException(),
      presentationCode: 'SAVE-002',
      message: _save002Message,
      recovery: _save002Recovery,
      catalogCode: 'SAVE-002',
    ),
    _FailureCase(
      label: 'SAVE-003 write failed',
      error: StorageWriteException(),
      presentationCode: 'SAVE-003',
      message: _save003Message,
      recovery: _save003Recovery,
      catalogCode: 'SAVE-003',
    ),
    _FailureCase(
      label: 'SAVE-003 corrupt data',
      error: CorruptDataException(),
      presentationCode: 'SAVE-003',
      message: _save003Message,
      recovery: _save003Recovery,
      catalogCode: 'SAVE-003',
    ),
    _FailureCase(
      label: 'SAVE-005 schema too new',
      error: SchemaTooNewException(),
      presentationCode: 'SAVE-005',
      message: _save005Message,
      recovery: _save005Recovery,
      catalogCode: 'SAVE-005',
    ),
    _FailureCase(
      label: 'SAVE-006 concurrent write',
      error: _RawCodeException('SAVE-006', 'storage.concurrentWrite'),
      presentationCode: 'SAVE-006',
      message: _save006Message,
      recovery: null,
      catalogCode: 'SAVE-006',
    ),
    _FailureCase(
      label: 'SAVE-007 invalid data',
      error: _RawCodeException('SAVE-007', 'storage.invalidData'),
      presentationCode: 'SAVE-007',
      message: _save007Message,
      recovery: _save007Recovery,
      catalogCode: 'SAVE-007',
    ),
    _FailureCase(
      label: 'SAVE-008 global keystore unavailable',
      error: KeystoreUnavailableException(),
      presentationCode: 'SAVE-008',
      message: _save008Message,
      recovery: _save008Recovery,
      catalogCode: 'SAVE-008',
    ),
  ];
}

/// The catalog code, message, and recovery parsed from one table row.
final class _CatalogRow {
  const _CatalogRow(this.message, this.recovery);

  final String? message;
  final String? recovery;
}

List<String> _cells(String line) {
  final String trimmed = line.trim();
  return trimmed
      .substring(1, trimmed.length - 1)
      .split('|')
      .map((String cell) => cell.trim())
      .toList();
}

/// German catalog text is wrapped in „…“; a row with no text has no pair.
String? _quoted(String cell) {
  final int start = cell.indexOf('„');
  final int end = cell.lastIndexOf('“');
  if (start < 0 || end <= start) {
    return null;
  }
  return cell.substring(start + 1, end);
}

/// Parsed rows from catalog §1 (import) and §3 (storage), which are the only
/// sections whose codes the import surface may present.
Map<String, _CatalogRow> _importCatalogRows(String catalog) {
  final Map<String, _CatalogRow> rows = <String, _CatalogRow>{};
  String? section;
  for (final String line in catalog.split('\n')) {
    if (line.startsWith('## ')) {
      section = RegExp(r'^## ([0-9]+)\.').firstMatch(line)?.group(1);
      continue;
    }
    if (section != '1' && section != '3') {
      continue;
    }
    if (!line.startsWith('|')) {
      continue;
    }
    final List<String> cells = _cells(line);
    if (cells.length < 3) {
      continue;
    }
    final RegExpMatch? match = RegExp(r'^`([A-Z]{2,6}-[0-9]{3})`$')
        .firstMatch(cells[0]);
    if (match == null) {
      continue;
    }
    rows[match.group(1)!] = _CatalogRow(
      _quoted(cells[2]),
      cells.length > 3 ? _quoted(cells[3]) : null,
    );
  }
  return rows;
}

final RegExp _catalogCodePattern = RegExp(
  r'\b(?:IMP|SAVE|PLT|PAGE|REC|EXP|DEL|TPL|DATE|NUM|FLD|PRIV)-[0-9]{3}\b',
);
final RegExp _pdfFileNamePattern = RegExp(r'\.pdf\b', caseSensitive: false);

/// Asserts that [text] carries no internal or document-derived material.
void _expectNoInternals(String? text, String reason) {
  if (text == null) {
    return;
  }
  expect(text, isNot(matches(_catalogCodePattern)), reason: reason);
  expect(text, isNot(contains('IMP-')), reason: reason);
  expect(text, isNot(contains('SAVE-')), reason: reason);
  expect(text, isNot(contains('PLT-')), reason: reason);
  expect(text, isNot(contains('/')), reason: reason);
  expect(text, isNot(contains(r'\')), reason: reason);
  expect(text, isNot(contains('content://')), reason: reason);
  expect(text, isNot(contains('file://')), reason: reason);
  expect(text, isNot(contains('://')), reason: reason);
  expect(text, isNot(matches(_pdfFileNamePattern)), reason: reason);
  expect(text, isNot(contains('antrag.pdf')), reason: reason);
  expect(text, isNot(contains('import.rejected')), reason: reason);
  expect(text, isNot(contains('storage.')), reason: reason);
  expect(text, isNot(contains('Sehr geehrte')), reason: reason);
  expect(text, isNot(contains('Max Mustermann')), reason: reason);
  expect(text, isNot(contains('Musterstraße 1')), reason: reason);
}

void main() {
  final AppLocalizations l10n = AppLocalizationsDe();
  final ImportErrorMapper mapper = ImportErrorMapper(l10n);

  group('exact German catalog messages per failure class', () {
    test('presents the pinned message and recovery for every import code', () {
      for (final _FailureCase failureCase in _failureCases()) {
        final ImportFailurePresentation presentation = mapper.describe(
          failureCase.error,
        );
        expect(
          presentation.code,
          failureCase.error.code,
          reason: '${failureCase.label} observed code',
        );
        expect(
          presentation.presentationCode,
          failureCase.presentationCode,
          reason: '${failureCase.label} presented catalog row',
        );
        expect(
          presentation.message,
          failureCase.message,
          reason: '${failureCase.label} German message',
        );
        expect(
          presentation.recovery,
          failureCase.recovery,
          reason: '${failureCase.label} German recovery guidance',
        );
        expect(
          presentation.hasMessage,
          failureCase.message != null,
          reason: failureCase.label,
        );
        expect(
          presentation.isCancellation,
          failureCase.isCancellation,
          reason: failureCase.label,
        );
        expect(
          presentation.passwordProtectionConfirmed,
          failureCase.passwordProtectionConfirmed,
          reason: failureCase.label,
        );
        expect(
          presentation.isUnrecognized,
          failureCase.isUnrecognized,
          reason: failureCase.label,
        );
      }
    });

    test('an unclassified exception presents the IMP-005 German text', () {
      final ImportFailurePresentation presentation = mapper.unclassified();
      expect(presentation.code, 'IMP-005');
      expect(presentation.presentationCode, 'IMP-005');
      expect(presentation.message, _imp005Message);
      expect(presentation.recovery, _imp005Recovery);
      expect(presentation.isUnrecognized, isTrue);
      expect(presentation.passwordProtectionConfirmed, isFalse);
    });

    test('pinned sentences are exactly the committed catalog rows', () {
      final Map<String, _CatalogRow> rows = _importCatalogRows(
        File('${repositoryRoot.path}/$_catalogRelativePath').readAsStringSync(),
      );

      for (final _FailureCase failureCase in _failureCases()) {
        final String? catalogCode = failureCase.catalogCode;
        if (catalogCode == null) {
          continue;
        }
        final _CatalogRow? row = rows[catalogCode];
        expect(
          row,
          isNotNull,
          reason: 'catalog row $catalogCode for ${failureCase.label}',
        );
        expect(
          failureCase.message,
          row!.message,
          reason: '${failureCase.label} pinned catalog message',
        );
        expect(
          failureCase.recovery,
          row.recovery,
          reason: '${failureCase.label} pinned catalog recovery',
        );
      }

      final _CatalogRow imp006 = rows['IMP-006']!;
      expect(_imp006Template, imp006.message);
      expect(_imp006Recovery, imp006.recovery);
      expect(_imp006Template, contains('{pages}'));
    });

    test('the mapper resolves the same text through AppLocalizations', () {
      // The ARB getters are the runtime source; the pinned literals above and
      // `german_strings_test.dart` bind them to the catalog. This guard catches
      // a getter swap inside the mapper even if a literal was edited with it.
      expect(
        mapper
            .describe(
              ImportRejectedException(ImportRejectionKind.passwordProtected),
            )
            .message,
        l10n.imp001,
      );
      expect(
        mapper
            .describe(
              ImportRejectedException(ImportRejectionKind.passwordProtected),
            )
            .recovery,
        l10n.imp001Recovery,
      );
      expect(
        mapper
            .describe(ImportRejectedException(ImportRejectionKind.unreadable))
            .message,
        l10n.imp002,
      );
      expect(
        mapper
            .describe(ImportRejectedException(ImportRejectionKind.missing))
            .message,
        l10n.imp003,
      );
      expect(
        mapper
            .describe(ImportRejectedException(ImportRejectionKind.notPdf))
            .message,
        l10n.imp004,
      );
      expect(
        mapper
            .describe(
              ImportRejectedException(ImportRejectionKind.unknownReason),
            )
            .message,
        l10n.imp005,
      );
      expect(
        mapper
            .describe(ImportRejectedException(ImportRejectionKind.tooLarge))
            .message,
        l10n.imp007,
      );
      expect(mapper.describe(StorageFullException()).message, l10n.save001);
      expect(mapper.describe(KeyUnavailableException()).message, l10n.save002);
      expect(mapper.describe(StorageWriteException()).message, l10n.save003);
      expect(mapper.describe(SchemaTooNewException()).message, l10n.save005);
      expect(
        mapper
            .describe(_RawCodeException('SAVE-006', 'storage.concurrentWrite'))
            .message,
        l10n.save006,
      );
      expect(
        mapper
            .describe(_RawCodeException('SAVE-007', 'storage.invalidData'))
            .message,
        l10n.save007,
      );
      expect(
        mapper.describe(KeystoreUnavailableException()).message,
        l10n.save008,
      );
      expect(_imp006('1, 3'), l10n.imp006('1, 3'));
      expect(_imp006Recovery, l10n.imp006Recovery);
    });
  });

  group('FR-007 truthful password diagnosis', () {
    test('only the positive password diagnosis claims password protection', () {
      int confirmed = 0;
      for (final _FailureCase failureCase in _failureCases()) {
        final ImportFailurePresentation presentation = mapper.describe(
          failureCase.error,
        );
        if (failureCase.passwordProtectionConfirmed) {
          confirmed++;
          expect(presentation.code, 'IMP-001');
          expect(presentation.presentationCode, 'IMP-001');
          expect(presentation.message, _imp001Message);
          expect(presentation.recovery, _imp001Recovery);
          expect(presentation.message, contains('passwortgeschützt'));
          continue;
        }
        expect(
          presentation.passwordProtectionConfirmed,
          isFalse,
          reason: failureCase.label,
        );
        for (final String text in <String>[
          presentation.message ?? '',
          presentation.recovery ?? '',
        ]) {
          expect(
            text.toLowerCase(),
            isNot(contains('passwortgeschützt')),
            reason: failureCase.label,
          );
          expect(
            text.toLowerCase(),
            isNot(contains('passwort')),
            reason: failureCase.label,
          );
        }
      }
      expect(confirmed, 1);
      expect(mapper.unclassified().passwordProtectionConfirmed, isFalse);
    });

    test(
      'canonical unsupported encryption presents IMP-004 with a false flag',
      () {
        final List<ImportFailurePresentation> presentations =
            <ImportFailurePresentation>[
              mapper.describe(
                ImportRejectedException(
                  ImportRejectionKind.unsupportedEncryption,
                ),
              ),
              mapper.describe(
                _RawCodeException(
                  'IMP-001',
                  ImportRejectionKind.unsupportedEncryption.machineMessage,
                ),
              ),
            ];
        for (final ImportFailurePresentation presentation in presentations) {
          expect(presentation.code, 'IMP-001');
          expect(presentation.presentationCode, 'IMP-004');
          expect(presentation.message, _imp004Message);
          expect(presentation.recovery, _imp004Recovery);
          expect(presentation.message, isNot(_imp001Message));
          expect(
            presentation.message!.toLowerCase(),
            isNot(contains('passwortgeschützt')),
          );
          expect(
            presentation.recovery!.toLowerCase(),
            isNot(contains('passwort')),
          );
          expect(presentation.passwordProtectionConfirmed, isFalse);
          expect(presentation.isUnrecognized, isFalse);
        }
      },
    );
  });

  group('FR-094 no internals in user text', () {
    test('rendered text and mapper identity contain no internals', () {
      for (final _FailureCase failureCase in _failureCases()) {
        final ImportFailurePresentation presentation = mapper.describe(
          failureCase.error,
        );
        _expectNoInternals(presentation.message, failureCase.label);
        _expectNoInternals(presentation.recovery, failureCase.label);
        for (final String text in <String>[
          presentation.message ?? '',
          presentation.recovery ?? '',
        ]) {
          expect(
            text,
            isNot(contains(failureCase.error.message)),
            reason: '${failureCase.label} text leaks the machine key',
          );
        }

        final String identity = presentation.toString();
        expect(identity, startsWith('ImportFailurePresentation('));
        _expectNoInternals(identity, '${failureCase.label} identity');
        expect(
          identity,
          isNot(contains(failureCase.error.message)),
          reason: '${failureCase.label} identity leaks the machine key',
        );
        if (failureCase.message != null) {
          expect(
            identity,
            isNot(contains(failureCase.message!)),
            reason: '${failureCase.label} identity leaks the message',
          );
        }
      }

      final ImportFailurePresentation unclassified = mapper.unclassified();
      _expectNoInternals(unclassified.message, 'unclassified');
      _expectNoInternals(unclassified.recovery, 'unclassified');
      _expectNoInternals(unclassified.toString(), 'unclassified identity');
    });

    test('partial warning text and identity contain no internals', () {
      final ImportPartialWarning warning = mapper.partialWarning(
        _source(pageFailures: <PageFailure>[_pageFailure(0), _pageFailure(2)]),
      )!;
      _expectNoInternals(warning.message, 'IMP-006 message');
      _expectNoInternals(warning.recovery, 'IMP-006 recovery');
      _expectNoInternals(warning.toString(), 'IMP-006 identity');
      expect(warning.message, contains('1, 3'));
      expect(warning.toString(), 'ImportPartialWarning(pageNumbers: 1, 3)');
    });

    test(
      'accepted candidate and source identities omit the display name',
      () async {
        final _FakeImportPort port = _FakeImportPort(() async => _source());
        final ImportFlow flow = ImportFlow(
          localizations: l10n,
          createDocument: (ImportedDocumentCandidate document) async {},
        );
        final ImportOutcome outcome = await flow.run(
          port: port,
          request: ImportRequest(),
        );
        final ImportAccepted accepted = outcome as ImportAccepted;
        for (final String identity in <String>[
          accepted.document.toString(),
          accepted.document.source.toString(),
          accepted.toString(),
        ]) {
          _expectNoInternals(identity, 'accepted identity');
          expect(identity, isNot(contains('antrag.pdf')));
          expect(identity, isNot(contains(_documentId)));
          expect(identity, isNot(contains(_sourceId)));
          expect(identity, isNot(contains(_sha256)));
        }
      },
    );
  });

  group('FR-009 error semantics at the flow level', () {
    test('every rejected or cancelled failure creates no document', () async {
      for (final _FailureCase failureCase in _failureCases()) {
        final _FakeImportPort port = _FakeImportPort(
          () async => throw failureCase.error,
        );
        final List<ImportedDocumentCandidate> created =
            <ImportedDocumentCandidate>[];
        final ImportFlow flow = ImportFlow(
          localizations: l10n,
          createDocument: (ImportedDocumentCandidate document) async {
            created.add(document);
          },
        );

        final ImportOutcome outcome = await flow.run(
          port: port,
          request: ImportRequest(),
        );

        expect(port.calls, 1, reason: failureCase.label);
        expect(created, isEmpty, reason: failureCase.label);
        if (failureCase.isCancellation) {
          expect(outcome, isA<ImportCancelled>(), reason: failureCase.label);
          continue;
        }
        expect(outcome, isA<ImportRejected>(), reason: failureCase.label);
        final ImportRejected rejected = outcome as ImportRejected;
        expect(
          rejected.failure.message,
          failureCase.message,
          reason: failureCase.label,
        );
        expect(
          rejected.failure.recovery,
          failureCase.recovery,
          reason: failureCase.label,
        );
        expect(
          rejected.failure.presentationCode,
          failureCase.presentationCode,
          reason: failureCase.label,
        );
        expect(
          rejected.failure.passwordProtectionConfirmed,
          failureCase.passwordProtectionConfirmed,
          reason: failureCase.label,
        );
      }
    });

    test(
      'an untyped failure is rejected with IMP-005 and creates nothing',
      () async {
        final _FakeImportPort port = _FakeImportPort(
          () async => throw const FormatException('not an import result'),
        );
        final List<ImportedDocumentCandidate> created =
            <ImportedDocumentCandidate>[];
        final ImportFlow flow = ImportFlow(
          localizations: l10n,
          createDocument: (ImportedDocumentCandidate document) async {
            created.add(document);
          },
        );

        final ImportOutcome outcome = await flow.run(
          port: port,
          request: ImportRequest(),
        );

        expect(outcome, isA<ImportRejected>());
        final ImportRejected rejected = outcome as ImportRejected;
        expect(rejected.failure.message, _imp005Message);
        expect(rejected.failure.recovery, _imp005Recovery);
        expect(rejected.failure.isUnrecognized, isTrue);
        expect(rejected.failure.passwordProtectionConfirmed, isFalse);
        expect(created, isEmpty);
        expect(port.calls, 1);
      },
    );

    test(
      'IMP-006 succeeds with a warning and ascending 1-based pages',
      () async {
        final _FakeImportPort port = _FakeImportPort(
          () async => _source(
            pageFailures: <PageFailure>[_pageFailure(2), _pageFailure(0)],
          ),
        );
        final List<ImportedDocumentCandidate> created =
            <ImportedDocumentCandidate>[];
        final ImportFlow flow = ImportFlow(
          localizations: l10n,
          createDocument: (ImportedDocumentCandidate document) async {
            created.add(document);
          },
        );

        final ImportOutcome outcome = await flow.run(
          port: port,
          request: ImportRequest(),
        );

        expect(outcome, isA<ImportAccepted>());
        final ImportAccepted accepted = outcome as ImportAccepted;
        final ImportPartialWarning warning = accepted.warning!;
        expect(accepted.isPartial, isTrue);
        expect(warning.pageNumbers, <int>[1, 3]);
        expect(warning.message, _imp006('1, 3'));
        expect(warning.recovery, _imp006Recovery);
        expect(created, hasLength(1));
        expect(identical(created.single, accepted.document), isTrue);
        expect(created.single.source.pageFailures, hasLength(2));
        expect(port.calls, 1);
        _expectNoInternals(warning.message, 'IMP-006 message');
        _expectNoInternals(warning.recovery, 'IMP-006 recovery');
      },
    );

    test(
      'the flow warning matches T044 page state for the same pages',
      () async {
        final _FakeImportPort port = _FakeImportPort(
          () async => _source(
            pageFailures: <PageFailure>[_pageFailure(0), _pageFailure(2)],
          ),
        );
        final ImportFlow flow = ImportFlow(
          localizations: l10n,
          createDocument: (ImportedDocumentCandidate document) async {},
        );
        final ImportAccepted accepted = await flow.run(
          port: port,
          request: ImportRequest(),
        ) as ImportAccepted;

        final PageStateResult result = derivePageStates(
          pages: <PageStateInput>[
            PageStateInput(
              index: 0,
              analysis: PageAnalysisStatus.failed,
              unreadable: true,
              failureMessageKey: imp006MessageKey,
            ),
            PageStateInput(
              index: 1,
              analysis: PageAnalysisStatus.pending,
              reportedDisplaySize: PageDisplaySize(
                widthPt: 595.28,
                heightPt: 841.89,
              ),
            ),
            PageStateInput(
              index: 2,
              analysis: PageAnalysisStatus.failed,
              unreadable: true,
              failureMessageKey: imp006MessageKey,
            ),
          ],
          localizations: l10n,
        );

        expect(result, isA<PageStateSuccess>());
        final PageStateWarning pageWarning =
            (result as PageStateSuccess).warning!;
        expect(pageWarning.pageNumbers, accepted.warning!.pageNumbers);
        expect(pageWarning.message, accepted.warning!.message);
        expect(pageWarning.recovery, accepted.warning!.recovery);
        expect(pageWarning.message, _imp006('1, 3'));
        expect(pageWarning.recovery, _imp006Recovery);
      },
    );
  });

  group('German-only user surface', () {
    test('every asserted sentence is German catalog text, not a fallback', () {
      expect(l10n.localeName, 'de');

      final List<String> texts = <String>[
        for (final _FailureCase failureCase in _failureCases()) ...<String>[
          if (failureCase.message != null) failureCase.message!,
          if (failureCase.recovery != null) failureCase.recovery!,
        ],
        _imp006('1, 3'),
        _imp006Recovery,
        _imp005Message,
        _imp005Recovery,
      ];

      final RegExp germanCue = RegExp(
        r'\b(?:Die|Der|Das|Bitte|Sie|Ihr|Feldexa|Einige|Diese|Wenn|Öffnen|'
        r'nicht|keine|kann|konnte|wurde|sind|ist)\b',
      );
      final RegExp englishFallback = RegExp(
        r'\b(?:an error occurred|something went wrong|please try again|'
        r'failed to open|could not be opened|the file|the document|you can|'
        r'try again|file not found)\b',
        caseSensitive: false,
      );

      for (final String text in texts) {
        expect(text.trim(), text, reason: text);
        expect(text, isNotEmpty, reason: text);
        expect(text, matches(germanCue), reason: text);
        expect(text, isNot(matches(englishFallback)), reason: text);
      }
    });
  });
}
