// T014 error-taxonomy tests (host VM, evidence class NONE).
//
// These tests pin `contracts/ports.md` §3, `contracts/error-catalog.de.md`, and
// `contracts/storage-format.md` §5:
//   * every typed exception in the contract table exists with its code,
//     retryability, and internal severity;
//   * the two `SAVE-003` causes stay distinct;
//   * every import rejection kind maps to its catalog code;
//   * machine messages and `toString()` contain no German sentence, path, file
//     name, or document content.
//
// No test here produces SIMULATED, EMULATOR, or DEVICE runtime evidence.

import 'package:feldexa_ports/errors.dart';
import 'package:flutter_test/flutter_test.dart';

/// Concrete probe for the abstract base-class validation.
final class _ProbeException extends FeldexaException {
  _ProbeException({
    required super.code,
    required super.messageKey,
    required super.message,
  }) : super(retryable: false, severity: ErrorSeverity.error);
}

List<FeldexaException> _allContractExceptions() => <FeldexaException>[
  ImportRejectedException(ImportRejectionKind.passwordProtected),
  ImportCancelledException(),
  StorageFullException(),
  KeyUnavailableException(),
  CorruptDataException(),
  StorageWriteException(),
  SecurityException(),
  SchemaTooNewException(),
  ExportBlockedException(<String>['field-a']),
  ExportFailedException(),
  RenderException(pageIndex: 0),
  OcrUnavailableException(),
  SimulatedInProductionException(),
  UnsupportedOperationException(),
];

void main() {
  group('FeldexaException base contract', () {
    test('rejects non-catalog codes', () {
      expect(
        () => _ProbeException(
          code: 'sim-1',
          messageKey: 'sim-1',
          message: 'platform.unsupported',
        ),
        throwsArgumentError,
      );
      expect(
        () => _ProbeException(
          code: 'FELDEXA-SIM-001',
          messageKey: 'FELDEXA-SIM-001',
          message: 'platform.unsupported',
        ),
        throwsArgumentError,
      );
    });

    test('rejects a path-bearing or spaced ARB key', () {
      for (final String invalid in <String>[
        'import/password',
        'import password',
        '',
      ]) {
        expect(
          () => _ProbeException(
            code: 'IMP-001',
            messageKey: invalid,
            message: 'import.rejected.passwordProtected',
          ),
          throwsArgumentError,
          reason: invalid,
        );
      }
    });

    test('rejects German sentences, paths, and content in message', () {
      for (final String invalid in <String>[
        'Die Datei konnte nicht gelesen werden',
        'import/rejected',
        r'C:\Users\person\form.pdf',
        '/home/person/form.pdf',
        'IMP-001',
        'Import.Rejected',
      ]) {
        expect(
          () => _ProbeException(
            code: 'IMP-001',
            messageKey: 'IMP-001',
            message: invalid,
          ),
          throwsArgumentError,
          reason: invalid,
        );
      }
    });

    test('every contract exception is an Exception with a catalog code', () {
      for (final FeldexaException exception in _allContractExceptions()) {
        expect(exception, isA<Exception>());
        expect(exception.code, matches(RegExp(r'^[A-Z]{2,6}-[0-9]{3}$')));
        expect(exception.messageKey, exception.code);
        expect(
          exception.message,
          matches(RegExp(r'^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+$')),
        );
        expect(exception.severity, isA<ErrorSeverity>());
      }
    });

    test('toString is content-free and names the code and severity', () {
      for (final FeldexaException exception in _allContractExceptions()) {
        final String text = exception.toString();
        expect(text, contains(exception.code));
        expect(text, contains(exception.severity.label));
        expect(text, isNot(contains('/')));
        expect(text, isNot(contains(r'\')));
        expect(text, isNot(contains('.pdf')));
        expect(text, isNot(contains('\n')));
        expect(text, isNot(contains('Fehler')));
        expect(text, isNot(contains('Datei')));
      }
    });

    test('declares exactly the four internal severity levels', () {
      expect(
        ErrorSeverity.values.map((ErrorSeverity value) => value.label).toList(),
        <String>['INFO', 'WARNING', 'ERROR', 'FATAL'],
      );
    });
  });

  group('Ports §3 exception table', () {
    test('matches code, retryability, and severity for every row', () {
      final List<
        ({Type type, String code, bool retryable, ErrorSeverity severity})
      >
      rows =
          <({Type type, String code, bool retryable, ErrorSeverity severity})>[
            (
              type: ImportRejectedException,
              code: 'IMP-001',
              retryable: false,
              severity: ErrorSeverity.error,
            ),
            (
              type: ImportCancelledException,
              code: 'IMP-000',
              retryable: true,
              severity: ErrorSeverity.info,
            ),
            (
              type: StorageFullException,
              code: 'SAVE-001',
              retryable: true,
              severity: ErrorSeverity.error,
            ),
            (
              type: KeyUnavailableException,
              code: 'SAVE-002',
              retryable: false,
              severity: ErrorSeverity.fatal,
            ),
            (
              type: CorruptDataException,
              code: 'SAVE-003',
              retryable: false,
              severity: ErrorSeverity.fatal,
            ),
            (
              type: StorageWriteException,
              code: 'SAVE-003',
              retryable: true,
              severity: ErrorSeverity.error,
            ),
            (
              type: SecurityException,
              code: 'PLT-002',
              retryable: false,
              severity: ErrorSeverity.error,
            ),
            (
              type: SchemaTooNewException,
              code: 'SAVE-005',
              retryable: false,
              severity: ErrorSeverity.error,
            ),
            (
              type: ExportBlockedException,
              code: 'EXP-001',
              retryable: true,
              severity: ErrorSeverity.warning,
            ),
            (
              type: ExportFailedException,
              code: 'EXP-002',
              retryable: true,
              severity: ErrorSeverity.error,
            ),
            (
              type: RenderException,
              code: 'PAGE-001',
              retryable: true,
              severity: ErrorSeverity.warning,
            ),
            (
              type: OcrUnavailableException,
              code: 'REC-001',
              retryable: true,
              severity: ErrorSeverity.warning,
            ),
            (
              type: SimulatedInProductionException,
              code: 'SIM-001',
              retryable: false,
              severity: ErrorSeverity.fatal,
            ),
            (
              type: UnsupportedOperationException,
              code: 'PLT-001',
              retryable: false,
              severity: ErrorSeverity.error,
            ),
          ];

      expect(rows, hasLength(14));
      final List<FeldexaException> actual = _allContractExceptions();
      expect(actual, hasLength(rows.length));
      for (int index = 0; index < rows.length; index++) {
        final ({Type type, String code, bool retryable, ErrorSeverity severity})
        row = rows[index];
        final FeldexaException exception = actual[index];
        expect(exception.runtimeType, row.type);
        expect(exception.code, row.code, reason: row.type.toString());
        expect(exception.retryable, row.retryable, reason: row.type.toString());
        expect(exception.severity, row.severity, reason: row.type.toString());
      }
    });

    test('SAVE-003 keeps its two concrete causes distinct', () {
      final CorruptDataException corrupt = CorruptDataException();
      final StorageWriteException write = StorageWriteException();
      expect(corrupt.code, 'SAVE-003');
      expect(write.code, 'SAVE-003');
      expect(corrupt.message, isNot(write.message));
      expect(corrupt.retryable, isFalse);
      expect(write.retryable, isTrue);
      expect(corrupt.runtimeType, isNot(write.runtimeType));
    });
  });

  group('ImportRejectionKind', () {
    test('maps every kind to its catalog code and machine message', () {
      const Map<ImportRejectionKind, String> expectedCodes =
          <ImportRejectionKind, String>{
            ImportRejectionKind.passwordProtected: 'IMP-001',
            ImportRejectionKind.unsupportedEncryption: 'IMP-001',
            ImportRejectionKind.missing: 'IMP-003',
            ImportRejectionKind.unreadable: 'IMP-002',
            ImportRejectionKind.truncated: 'IMP-002',
            ImportRejectionKind.notPdf: 'IMP-004',
            ImportRejectionKind.unsupportedStructure: 'IMP-004',
            ImportRejectionKind.tooLarge: 'IMP-007',
            ImportRejectionKind.storageFull: 'SAVE-001',
            ImportRejectionKind.cancelled: 'IMP-000',
            ImportRejectionKind.unknownReason: 'IMP-005',
          };

      expect(expectedCodes.keys.toSet(), ImportRejectionKind.values.toSet());
      for (final MapEntry<ImportRejectionKind, String> entry
          in expectedCodes.entries) {
        expect(entry.key.catalogCode, entry.value, reason: entry.key.name);
        expect(
          entry.key.machineMessage,
          matches(RegExp(r'^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+$')),
        );
      }
    });

    test('rejected imports keep the fixed non-retryable contract row', () {
      for (final ImportRejectionKind kind in ImportRejectionKind.values) {
        if (kind == ImportRejectionKind.cancelled ||
            kind == ImportRejectionKind.storageFull) {
          // §2.1 routes these to their dedicated exception instead of the
          // `IMP-*` rejection type.
          expect(
            () => ImportRejectedException(kind),
            throwsArgumentError,
            reason: kind.name,
          );
          continue;
        }
        final ImportRejectedException exception = ImportRejectedException(kind);
        expect(exception.kind, kind);
        expect(exception.code, kind.catalogCode);
        expect(exception.retryable, isFalse);
      }
    });

    test('cancellation and full storage use their dedicated exceptions', () {
      expect(
        ImportRejectionKind.cancelled.catalogCode,
        ImportCancelledException().code,
      );
      expect(
        ImportRejectionKind.storageFull.catalogCode,
        StorageFullException().code,
      );
      expect(ImportCancelledException().retryable, isTrue);
      expect(StorageFullException().retryable, isTrue);
    });

    test('unsupported encryption is not reported as unknown reason', () {
      final ImportRejectedException password = ImportRejectedException(
        ImportRejectionKind.passwordProtected,
      );
      final ImportRejectedException unsupported = ImportRejectedException(
        ImportRejectionKind.unsupportedEncryption,
      );
      expect(unsupported.code, password.code);
      expect(unsupported.message, isNot(password.message));
      expect(unsupported.message, isNot('import.rejected.unknownReason'));
    });

    test('over-limit files map to IMP-007', () {
      final ImportRejectedException exception = ImportRejectedException(
        ImportRejectionKind.tooLarge,
      );
      expect(exception.code, 'IMP-007');
      expect(exception.severity, ErrorSeverity.warning);
    });
  });

  group('Typed payloads', () {
    test('ExportBlockedException keeps a defensive read-only field list', () {
      final List<String> fields = <String>['field-b', 'field-a'];
      final ExportBlockedException exception = ExportBlockedException(fields);
      fields.add('field-c');

      expect(exception.fieldIds, <String>['field-b', 'field-a']);
      expect(() => exception.fieldIds.add('field-d'), throwsUnsupportedError);
      expect(exception.retryable, isTrue);
    });

    test('ExportBlockedException rejects empty, blank, and duplicate ids', () {
      expect(() => ExportBlockedException(<String>[]), throwsArgumentError);
      expect(() => ExportBlockedException(<String>['']), throwsArgumentError);
      expect(
        () => ExportBlockedException(<String>['field-a', 'field-a']),
        throwsArgumentError,
      );
    });

    test('RenderException keeps a valid zero-based page index', () {
      expect(RenderException(pageIndex: 0).pageIndex, 0);
      expect(RenderException(pageIndex: 7).pageIndex, 7);
      expect(() => RenderException(pageIndex: -1), throwsArgumentError);
    });
  });
}
