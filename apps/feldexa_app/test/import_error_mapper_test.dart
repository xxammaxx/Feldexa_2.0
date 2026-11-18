@TestOn('vm')
library;

import 'package:feldexa_app/features/start/import_error_mapper.dart';
import 'package:feldexa_app/l10n/app_localizations_de.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';

/// T041 German import-failure mapping and FR-009 rejection gate.
///
/// These are host-VM tests. They prove the mapping from typed platform
/// failures to the committed German catalog text, the FR-007 rule that an
/// uncertain cause never claims password protection, the `IMP-006` warning for
/// a successful partial import, and that a rejected import never reaches
/// document creation. They produce no `SIMULATED`, `EMULATOR`, or `DEVICE`
/// evidence.
const String _documentId = '5f0c3a52-3a6a-4f0b-9c2d-1b7e4d8a6c01';
const String _sourceId = '7b2d4c1e-5f3a-4b8c-8a9d-2e6f0c1b3d42';

final String _sha256 = List<String>.filled(64, 'a').join();

CapabilityEvidence _evidence() =>
    CapabilityEvidence.android(adapterId: 'test.fake.import.v1');

ImportedSource _source({
  List<PageFailure> pageFailures = const <PageFailure>[],
}) {
  return ImportedSource(
    documentId: _documentId,
    sourceId: _sourceId,
    sha256: _sha256,
    sizeBytes: 4096,
    pageCount: 3,
    pages: <PageGeometry>[
      for (int index = 0; index < 3; index++)
        PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595.28, 841.89)),
    ],
    pageFailures: pageFailures,
    displayName: 'antrag.pdf',
    evidence: _evidence(),
  );
}

PageFailure _failure(int pageIndex) => PageFailure(
  pageIndex: pageIndex,
  category: PageFailureCategory.unreadable,
  messageKey: 'IMP-006',
);

/// The catalog row a failure is expected to present.
///
/// T039 reports `import.unsupportedEncryption` with the observed `IMP-001`
/// code; T041 renders it with the truthful `IMP-004` sentence (FR-007). Every
/// other failure presents the row named by its own code.
String _presentedCode(FeldexaException error) {
  if (error is ImportRejectedException &&
      error.kind == ImportRejectionKind.unsupportedEncryption) {
    return 'IMP-004';
  }
  return error.code;
}

/// A typed failure with an arbitrary catalog code, like a future adapter code
/// the mapper has not seen yet.
final class _CodeException extends FeldexaException {
  _CodeException(String code, {super.message = 'platform.unknown'})
    : super(
        code: code,
        messageKey: 'IMP-005',
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
      throw UnimplementedError('verifySource is not part of T041');

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

void main() {
  final AppLocalizationsDe l10n = AppLocalizationsDe();
  final ImportErrorMapper mapper = ImportErrorMapper(l10n);

  group('catalog mapping', () {
    test('maps every import and import-reachable storage code exactly', () {
      final List<(FeldexaException, String, String?)>
      cases = <(FeldexaException, String, String?)>[
        (
          ImportRejectedException(ImportRejectionKind.passwordProtected),
          l10n.imp001,
          l10n.imp001Recovery,
        ),
        (
          ImportRejectedException(ImportRejectionKind.unsupportedEncryption),
          l10n.imp004,
          l10n.imp004Recovery,
        ),
        (
          ImportRejectedException(ImportRejectionKind.unreadable),
          l10n.imp002,
          l10n.imp002Recovery,
        ),
        (
          ImportRejectedException(ImportRejectionKind.truncated),
          l10n.imp002,
          l10n.imp002Recovery,
        ),
        (
          ImportRejectedException(ImportRejectionKind.missing),
          l10n.imp003,
          l10n.imp003Recovery,
        ),
        (
          ImportRejectedException(ImportRejectionKind.notPdf),
          l10n.imp004,
          l10n.imp004Recovery,
        ),
        (
          ImportRejectedException(ImportRejectionKind.unsupportedStructure),
          l10n.imp004,
          l10n.imp004Recovery,
        ),
        (
          ImportRejectedException(ImportRejectionKind.unknownReason),
          l10n.imp005,
          l10n.imp005Recovery,
        ),
        (
          ImportRejectedException(ImportRejectionKind.tooLarge),
          l10n.imp007,
          l10n.imp007Recovery,
        ),
        (StorageFullException(), l10n.save001, l10n.save001Recovery),
        (KeyUnavailableException(), l10n.save002, l10n.save002Recovery),
        (StorageWriteException(), l10n.save003, l10n.save003Recovery),
        (CorruptDataException(), l10n.save003, l10n.save003Recovery),
        (SchemaTooNewException(), l10n.save005, l10n.save005Recovery),
        (
          _CodeException('SAVE-006', message: 'storage.concurrentWrite'),
          l10n.save006,
          null,
        ),
        (
          _CodeException('SAVE-007', message: 'storage.invalidData'),
          l10n.save007,
          l10n.save007Recovery,
        ),
        (KeystoreUnavailableException(), l10n.save008, l10n.save008Recovery),
      ];

      for (final (FeldexaException error, String message, String? recovery)
          in cases) {
        final ImportFailurePresentation presentation = mapper.describe(error);
        expect(
          presentation.message,
          message,
          reason: '${error.code} primary message',
        );
        expect(
          presentation.recovery,
          recovery,
          reason: '${error.code} recovery guidance',
        );
        expect(
          presentation.presentationCode,
          _presentedCode(error),
          reason: '${error.code} catalog presentation',
        );
        expect(presentation.isCancellation, isFalse, reason: error.code);
      }
    });

    test('IMP-000 and PLT-004 are cancellations without a message', () {
      for (final FeldexaException error in <FeldexaException>[
        ImportCancelledException(),
        _CodeException('PLT-004', message: 'platform.cancelled'),
      ]) {
        final ImportFailurePresentation presentation = mapper.describe(error);
        expect(presentation.code, error.code);
        expect(presentation.isCancellation, isTrue, reason: error.code);
        expect(presentation.hasMessage, isFalse, reason: error.code);
        expect(presentation.message, isNull, reason: error.code);
        expect(presentation.recovery, isNull, reason: error.code);
        expect(presentation.passwordProtectionConfirmed, isFalse);
      }
    });

    test(
      'an unknown code falls back to IMP-005, never to a password claim',
      () {
        final ImportFailurePresentation presentation = mapper.describe(
          _CodeException('XYZ-999', message: 'future.unknownFailure'),
        );
        expect(presentation.code, 'XYZ-999');
        expect(presentation.presentationCode, 'IMP-005');
        expect(presentation.isUnrecognized, isTrue);
        expect(presentation.message, l10n.imp005);
        expect(presentation.recovery, l10n.imp005Recovery);
        expect(presentation.message, isNot(contains('passwortgeschützt')));
        expect(presentation.passwordProtectionConfirmed, isFalse);
      },
    );

    test('an unknown exception maps to IMP-005 semantics', () {
      final ImportFailurePresentation presentation = mapper.unclassified();
      expect(presentation.code, 'IMP-005');
      expect(presentation.presentationCode, 'IMP-005');
      expect(presentation.message, l10n.imp005);
      expect(presentation.recovery, l10n.imp005Recovery);
      expect(presentation.isUnrecognized, isTrue);
      expect(presentation.passwordProtectionConfirmed, isFalse);
    });

    test('isUnrecognized is true only for the unknown-cause fallback', () {
      final List<FeldexaException> mapped = <FeldexaException>[
        ImportRejectedException(ImportRejectionKind.passwordProtected),
        ImportRejectedException(ImportRejectionKind.unsupportedEncryption),
        _CodeException('IMP-001', message: 'import.unsupportedEncryption'),
        ImportRejectedException(ImportRejectionKind.unreadable),
        ImportRejectedException(ImportRejectionKind.truncated),
        ImportRejectedException(ImportRejectionKind.missing),
        ImportRejectedException(ImportRejectionKind.notPdf),
        ImportRejectedException(ImportRejectionKind.unsupportedStructure),
        ImportRejectedException(ImportRejectionKind.unknownReason),
        ImportRejectedException(ImportRejectionKind.tooLarge),
        ImportCancelledException(),
        _CodeException('PLT-004', message: 'platform.cancelled'),
        StorageFullException(),
        KeyUnavailableException(),
        StorageWriteException(),
        CorruptDataException(),
        SchemaTooNewException(),
        _CodeException('SAVE-006', message: 'storage.concurrentWrite'),
        _CodeException('SAVE-007', message: 'storage.invalidData'),
        KeystoreUnavailableException(),
      ];
      for (final FeldexaException error in mapped) {
        expect(
          mapper.describe(error).isUnrecognized,
          isFalse,
          reason: '${error.code} is a mapped failure',
        );
      }
      expect(
        mapper
            .describe(_CodeException('XYZ-999', message: 'future.unknown'))
            .isUnrecognized,
        isTrue,
      );
      expect(mapper.unclassified().isUnrecognized, isTrue);
    });
  });

  group('FR-007 truthfulness', () {
    test('only a positive password diagnosis claims password protection', () {
      final ImportFailurePresentation password = mapper.describe(
        ImportRejectedException(ImportRejectionKind.passwordProtected),
      );
      expect(password.presentationCode, 'IMP-001');
      expect(password.message, l10n.imp001);
      expect(password.message, contains('passwortgeschützt'));
      expect(password.isUnrecognized, isFalse);
      expect(password.passwordProtectionConfirmed, isTrue);
    });

    test('unsupported encryption uses the truthful IMP-004 text with a false '
        'exactness flag', () {
      final ImportFailurePresentation presentation = mapper.describe(
        ImportRejectedException(ImportRejectionKind.unsupportedEncryption),
      );
      expect(presentation.code, 'IMP-001');
      expect(presentation.presentationCode, 'IMP-004');
      expect(presentation.message, l10n.imp004);
      expect(presentation.recovery, l10n.imp004Recovery);
      expect(presentation.isUnrecognized, isFalse);
      expect(presentation.passwordProtectionConfirmed, isFalse);
    });

    test(
      'a raw IMP-001 code with the unsupported-encryption key renders IMP-004',
      () {
        final ImportFailurePresentation presentation = mapper.describe(
          _CodeException('IMP-001', message: 'import.unsupportedEncryption'),
        );
        expect(presentation.code, 'IMP-001');
        expect(presentation.presentationCode, 'IMP-004');
        expect(presentation.message, l10n.imp004);
        expect(presentation.recovery, l10n.imp004Recovery);
        expect(presentation.isUnrecognized, isFalse);
        expect(presentation.passwordProtectionConfirmed, isFalse);
      },
    );

    test(
      'regression: unsupported encryption never renders the password sentence',
      () {
        final ImportFailurePresentation presentation = mapper.describe(
          ImportRejectedException(ImportRejectionKind.unsupportedEncryption),
        );
        expect(presentation.message, l10n.imp004);
        expect(presentation.recovery, l10n.imp004Recovery);
        expect(presentation.message, isNot(l10n.imp001));
        expect(presentation.isUnrecognized, isFalse);
        expect(presentation.passwordProtectionConfirmed, isFalse);
        expect(presentation.message, isNot(contains('passwortgeschützt')));
        expect(presentation.recovery, isNot(contains('passwortgeschützt')));
      },
    );

    test('uncertain and structural failures never say password protected', () {
      final List<FeldexaException> errors = <FeldexaException>[
        ImportRejectedException(ImportRejectionKind.unsupportedStructure),
        ImportRejectedException(ImportRejectionKind.notPdf),
        ImportRejectedException(ImportRejectionKind.unreadable),
        ImportRejectedException(ImportRejectionKind.truncated),
        ImportRejectedException(ImportRejectionKind.missing),
        ImportRejectedException(ImportRejectionKind.unknownReason),
        ImportRejectedException(ImportRejectionKind.tooLarge),
        StorageFullException(),
        KeyUnavailableException(),
        StorageWriteException(),
        _CodeException('XYZ-999'),
      ];
      for (final FeldexaException error in errors) {
        final ImportFailurePresentation presentation = mapper.describe(error);
        expect(
          presentation.message,
          isNot(contains('passwortgeschützt')),
          reason: error.code,
        );
        expect(presentation.passwordProtectionConfirmed, isFalse);
      }
    });
  });

  group('tone and privacy', () {
    test('rendered text contains no code, path, URI, or document title', () {
      final RegExp catalogCode = RegExp(
        r'\b(?:IMP|SAVE|PLT|PAGE|REC|EXP)-[0-9]{3}\b',
      );
      final List<FeldexaException> errors = <FeldexaException>[
        ImportRejectedException(ImportRejectionKind.passwordProtected),
        ImportRejectedException(ImportRejectionKind.unsupportedEncryption),
        ImportRejectedException(ImportRejectionKind.unreadable),
        ImportRejectedException(ImportRejectionKind.missing),
        ImportRejectedException(ImportRejectionKind.notPdf),
        ImportRejectedException(ImportRejectionKind.unsupportedStructure),
        ImportRejectedException(ImportRejectionKind.unknownReason),
        ImportRejectedException(ImportRejectionKind.tooLarge),
        StorageFullException(),
        KeyUnavailableException(),
        StorageWriteException(),
        SchemaTooNewException(),
        _CodeException('SAVE-006'),
        _CodeException('SAVE-007'),
        KeystoreUnavailableException(),
        _CodeException('XYZ-999'),
      ];
      for (final FeldexaException error in errors) {
        final ImportFailurePresentation presentation = mapper.describe(error);
        for (final String text in <String>[
          presentation.message ?? '',
          presentation.recovery ?? '',
        ]) {
          expect(text, isNot(matches(catalogCode)), reason: error.code);
          expect(text, isNot(contains('content://')));
          expect(text, isNot(contains('file://')));
          expect(text, isNot(contains('/')));
          expect(text, isNot(contains(r'\')));
          expect(text, isNot(contains('antrag.pdf')));
        }
      }
    });
  });

  group('IMP-006 partial import', () {
    test('a partial source yields the warning with 1-based page numbers', () {
      final ImportPartialWarning? warning = mapper.partialWarning(
        _source(pageFailures: <PageFailure>[_failure(0), _failure(2)]),
      );
      expect(warning, isNotNull);
      expect(warning!.pageNumbers, <int>[1, 3]);
      expect(warning.message, l10n.imp006('1, 3'));
      expect(warning.recovery, l10n.imp006Recovery);
      expect(warning.message, isNot(contains('IMP-')));
    });

    test('a single failed page uses its 1-based number', () {
      final ImportPartialWarning? warning = mapper.partialWarning(
        _source(pageFailures: <PageFailure>[_failure(1)]),
      );
      expect(warning, isNotNull);
      expect(warning!.pageNumbers, <int>[2]);
      expect(warning.message, l10n.imp006('2'));
    });

    test('a fully readable source has no warning', () {
      expect(mapper.partialWarning(_source()), isNull);
    });
  });

  group('FR-009 rejection gate', () {
    test('a rejected import never reaches document creation', () async {
      final _FakeImportPort port = _FakeImportPort(
        () async => throw ImportRejectedException(
          ImportRejectionKind.passwordProtected,
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

      expect(outcome, isA<ImportRejected>());
      final ImportRejected rejected = outcome as ImportRejected;
      expect(rejected.failure.message, l10n.imp001);
      expect(created, isEmpty);
      expect(port.calls, 1);
    });

    test(
      'storage, too-large, and unknown failures also create nothing',
      () async {
        final List<FeldexaException> rejections = <FeldexaException>[
          StorageFullException(),
          ImportRejectedException(ImportRejectionKind.tooLarge),
          ImportRejectedException(ImportRejectionKind.unsupportedStructure),
          _CodeException('SAVE-006', message: 'storage.concurrentWrite'),
        ];
        for (final FeldexaException rejection in rejections) {
          final _FakeImportPort port = _FakeImportPort(
            () async => throw rejection,
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

          expect(outcome, isA<ImportRejected>(), reason: rejection.code);
          expect(created, isEmpty, reason: rejection.code);
        }
      },
    );

    test(
      'cancellation returns to the previous screen and creates nothing',
      () async {
        for (final FeldexaException cancellation in <FeldexaException>[
          ImportCancelledException(),
          _CodeException('PLT-004', message: 'platform.cancelled'),
        ]) {
          final _FakeImportPort port = _FakeImportPort(
            () async => throw cancellation,
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

          expect(outcome, isA<ImportCancelled>(), reason: cancellation.code);
          expect(created, isEmpty, reason: cancellation.code);
        }
      },
    );

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
        expect(rejected.failure.message, l10n.imp005);
        expect(rejected.failure.isUnrecognized, isTrue);
        expect(created, isEmpty);
      },
    );

    test(
      'an accepted partial import creates the document with a warning',
      () async {
        final _FakeImportPort port = _FakeImportPort(
          () async => _source(pageFailures: <PageFailure>[_failure(1)]),
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
        expect(accepted.isPartial, isTrue);
        expect(accepted.warning!.pageNumbers, <int>[2]);
        expect(accepted.document.source.pageCount, 3);
        expect(created, hasLength(1));
        expect(identical(created.single, accepted.document), isTrue);
      },
    );

    test(
      'a fully readable import creates the document without a warning',
      () async {
        final _FakeImportPort port = _FakeImportPort(() async => _source());
        int createCalls = 0;
        final ImportFlow flow = ImportFlow(
          localizations: l10n,
          createDocument: (ImportedDocumentCandidate document) async {
            createCalls++;
          },
        );

        final ImportOutcome outcome = await flow.run(
          port: port,
          request: ImportRequest(),
        );

        expect(outcome, isA<ImportAccepted>());
        expect((outcome as ImportAccepted).isPartial, isFalse);
        expect(createCalls, 1);
      },
    );
  });
}
