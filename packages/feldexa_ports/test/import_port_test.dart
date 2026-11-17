// T037 `DocumentImportPort` surface contract tests (host VM, NONE evidence).
//
// This file intentionally does NOT contain a fake importer or behavioural
// import scenarios. The executable import contract now lives in the reusable
// `feldexa_testkit` conformance suite and is executed against the REAL T028
// `SimulatedDocumentImportAdapter` by
// `packages/feldexa_adapters_simulated/test/import_conformance_test.dart`.
//
// What remains here genuinely exercises canonical production types only:
//   * `ImportRequest`, `ImportedSource`, and `SourceIntegrity` invariants;
//   * the `ImportRejectionKind` catalog codes and §11.1 ARB `messageKey`
//     mapping, including the two dedicated storage/cancellation exceptions;
//   * the `CapabilityEvidence` / `EvidenceClass` vocabulary;
//   * the `DocumentImportPort` method signatures and capability descriptor.
//
// The signature test proves parameter TYPES only. `verifySource` takes a
// `String`, so a path or URI represented as a string still compiles; content
// validation is an adapter obligation, not a type-level guarantee.
//
// Host VM only. No SIMULATED, EMULATOR, or DEVICE runtime evidence is produced.

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';

const String _sha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _otherSha256 =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

String _uuid([int value = 1]) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

PageGeometry _geometry() =>
    PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842));

CapabilityEvidence _simulatedEvidence() => CapabilityEvidence.simulated(
  adapterId: 'web.sim.import.v1',
  simulatedReason: 'web.simulated-adapter',
);

CapabilityEvidence _androidEvidence() =>
    CapabilityEvidence.android(adapterId: 'android.pdfbox.v1');

PageFailure _failure({int pageIndex = 0}) => PageFailure(
  pageIndex: pageIndex,
  category: PageFailureCategory.unreadable,
  messageKey: 'IMP-006',
);

ImportedSource _source({
  String? documentId,
  String? sourceId,
  String? sha256,
  int sizeBytes = 1234,
  int pageCount = 1,
  Iterable<PageGeometry>? pages,
  Iterable<PageFailure> pageFailures = const <PageFailure>[],
  String? displayName = 'formular.pdf',
  CapabilityEvidence? evidence,
}) {
  return ImportedSource(
    documentId: documentId ?? _uuid(1),
    sourceId: sourceId ?? _uuid(2),
    sha256: sha256 ?? _sha256,
    sizeBytes: sizeBytes,
    pageCount: pageCount,
    pages: pages ?? <PageGeometry>[_geometry()],
    pageFailures: pageFailures,
    displayName: displayName,
    evidence: evidence ?? _simulatedEvidence(),
  );
}

/// The catalog rows that deliberately have no committed German ARB entry.
const Set<String> _codesWithoutArbEntry = <String>{
  'IMP-000',
  'SIM-001',
  'PLT-001',
  'PLT-002',
};

/// Mirrors `contracts/error-catalog.de.md` §11.1 and the committed ARB.
String _expectedMessageKey(String code) {
  if (_codesWithoutArbEntry.contains(code)) {
    return code;
  }
  return code.toLowerCase().replaceAll('-', '');
}

void main() {
  group('ImportRequest invariants', () {
    test('defaults to the 80 MiB cap and cannot exceed it', () {
      expect(maxSourceSizeBytes, 83886080);
      expect(ImportRequest().maxBytes, 83886080);
      expect(ImportRequest(maxBytes: 83886080).maxBytes, 83886080);
      expect(ImportRequest(maxBytes: 1).maxBytes, 1);
      expect(() => ImportRequest(maxBytes: 0), throwsArgumentError);
      expect(() => ImportRequest(maxBytes: 83886081), throwsArgumentError);
    });

    test('toString carries no path or content', () {
      expect(ImportRequest().toString(), 'ImportRequest(maxBytes: 83886080)');
      expect(ImportRequest().toString(), isNot(contains('/')));
    });
  });

  group('ImportedSource invariants', () {
    test('exposes the documented verified-source shape', () {
      final ImportedSource source = _source(
        pageCount: 2,
        pages: <PageGeometry>[_geometry(), _geometry()],
      );

      expect(source.documentId, _uuid(1));
      expect(source.sourceId, _uuid(2));
      expect(source.sha256, _sha256);
      expect(source.sizeBytes, 1234);
      expect(source.pageCount, 2);
      expect(source.pages.length, 2);
      expect(source.pageFailures, isEmpty);
      expect(source.displayName, 'formular.pdf');
      expect(source.evidence.evidenceClass, EvidenceClass.simulated);
    });

    test('rejects invalid ids, hashes, sizes, and page counts', () {
      for (final String invalid in <String>[
        '00000000-0000-4000-8000-00000000000A',
        '00000000-0000-1000-8000-000000000001',
        '',
      ]) {
        expect(
          () => _source(documentId: invalid),
          throwsArgumentError,
          reason: 'documentId $invalid',
        );
        expect(
          () => _source(sourceId: invalid),
          throwsArgumentError,
          reason: 'sourceId $invalid',
        );
      }
      for (final String invalid in <String>[
        _otherSha256.toUpperCase(),
        _sha256.substring(0, 63),
        '',
      ]) {
        expect(
          () => _source(sha256: invalid),
          throwsArgumentError,
          reason: invalid,
        );
      }
      expect(() => _source(sizeBytes: 0), throwsArgumentError);
      expect(() => _source(sizeBytes: 83886081), throwsArgumentError);
      expect(() => _source(pageCount: 0), throwsArgumentError);
    });

    test('requires pages.length == pageCount', () {
      expect(
        () => _source(pageCount: 2, pages: <PageGeometry>[_geometry()]),
        throwsArgumentError,
      );
      expect(
        () => _source(
          pageCount: 1,
          pages: <PageGeometry>[_geometry(), _geometry()],
        ),
        throwsArgumentError,
      );
    });

    test('page failures must name a unique page inside the source', () {
      expect(
        () => _source(
          pageCount: 1,
          pageFailures: <PageFailure>[_failure(pageIndex: 1)],
        ),
        throwsArgumentError,
      );
      expect(
        () => _source(
          pageCount: 2,
          pages: <PageGeometry>[_geometry(), _geometry()],
          pageFailures: <PageFailure>[_failure(), _failure()],
        ),
        throwsArgumentError,
      );
      final ImportedSource partial = _source(
        pageCount: 2,
        pages: <PageGeometry>[_geometry(), _geometry()],
        pageFailures: <PageFailure>[_failure(pageIndex: 1)],
      );
      expect(partial.pageFailures.single.pageIndex, 1);
      expect(partial.pageFailures.single.messageKey, 'IMP-006');
    });

    test('displayName is a trimmed file name, never a path', () {
      expect(
        _source(displayName: '  formular.pdf  ').displayName,
        'formular.pdf',
      );
      for (final String invalid in <String>[
        'ordner/formular.pdf',
        r'ordner\formular.pdf',
        'form\u0000ular.pdf',
        '',
      ]) {
        expect(
          () => _source(displayName: invalid),
          throwsArgumentError,
          reason: invalid,
        );
      }
    });

    test('toString omits the display name and source bytes', () {
      final String text = _source().toString();
      expect(text, contains('pageCount: 1'));
      expect(text, contains('sizeBytes: 1234'));
      expect(text, isNot(contains('formular.pdf')));
      expect(text, isNot(contains(_sha256)));
    });
  });

  group('SourceIntegrity invariants', () {
    test('records an unreadable source without inventing a hash', () {
      final SourceIntegrity integrity = SourceIntegrity(
        readable: false,
        evidence: _simulatedEvidence(),
      );
      expect(integrity.readable, isFalse);
      expect(integrity.actualSha256, isNull);
      expect(integrity.pageCount, isNull);
      expect(integrity.pageFailures, isEmpty);
      expect(integrity.evidence.evidenceClass, EvidenceClass.simulated);
    });

    test('rejects a bad hash, page count, or out-of-range failure', () {
      expect(
        () => SourceIntegrity(
          readable: true,
          actualSha256: _otherSha256.toUpperCase(),
          evidence: _simulatedEvidence(),
        ),
        throwsArgumentError,
      );
      expect(
        () => SourceIntegrity(
          readable: true,
          pageCount: 0,
          evidence: _simulatedEvidence(),
        ),
        throwsArgumentError,
      );
      expect(
        () => SourceIntegrity(
          readable: false,
          pageCount: 2,
          pageFailures: <PageFailure>[_failure(pageIndex: 2)],
          evidence: _simulatedEvidence(),
        ),
        throwsArgumentError,
      );
    });

    test('toString is content-free', () {
      final SourceIntegrity integrity = SourceIntegrity(
        readable: true,
        actualSha256: _sha256,
        pageCount: 1,
        evidence: _simulatedEvidence(),
      );
      expect(integrity.toString(), contains('pageCount: 1'));
      expect(integrity.toString(), isNot(contains(_sha256)));
    });
  });

  group('typed error taxonomy', () {
    test(
      'every ImportRejectionKind maps to its catalog code and machine key',
      () {
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
        const Map<ImportRejectionKind, String> expectedMessages =
            <ImportRejectionKind, String>{
              ImportRejectionKind.passwordProtected:
                  'import.rejected.passwordProtected',
              ImportRejectionKind.unsupportedEncryption:
                  'import.rejected.unsupportedEncryption',
              ImportRejectionKind.missing: 'import.rejected.missing',
              ImportRejectionKind.unreadable: 'import.rejected.unreadable',
              ImportRejectionKind.truncated: 'import.rejected.truncated',
              ImportRejectionKind.notPdf: 'import.rejected.notPdf',
              ImportRejectionKind.unsupportedStructure:
                  'import.rejected.unsupportedStructure',
              ImportRejectionKind.tooLarge: 'import.rejected.tooLarge',
              ImportRejectionKind.storageFull: 'import.rejected.storageFull',
              ImportRejectionKind.cancelled: 'import.rejected.cancelled',
              ImportRejectionKind.unknownReason:
                  'import.rejected.unknownReason',
            };

        expect(expectedCodes.keys.toSet(), ImportRejectionKind.values.toSet());
        expect(
          expectedMessages.keys.toSet(),
          ImportRejectionKind.values.toSet(),
        );
        for (final ImportRejectionKind kind in ImportRejectionKind.values) {
          expect(kind.catalogCode, expectedCodes[kind], reason: kind.name);
          expect(
            kind.machineMessage,
            expectedMessages[kind],
            reason: kind.name,
          );
        }
      },
    );

    test(
      'rejections carry the §11.1 ARB message key, not the catalog code',
      () {
        for (final ImportRejectionKind kind in ImportRejectionKind.values) {
          if (kind == ImportRejectionKind.cancelled ||
              kind == ImportRejectionKind.storageFull) {
            continue;
          }
          final ImportRejectedException rejection = ImportRejectedException(
            kind,
          );
          expect(
            rejection.messageKey,
            _expectedMessageKey(rejection.code),
            reason: kind.name,
          );
          expect(rejection.message, kind.machineMessage, reason: kind.name);
          expect(rejection.retryable, isFalse, reason: kind.name);
        }
        final ImportRejectedException encrypted = ImportRejectedException(
          ImportRejectionKind.passwordProtected,
        );
        expect(encrypted.messageKey, 'imp001');
        expect(encrypted.code, 'IMP-001');
      },
    );

    test('cancelled and storageFull are not ImportRejectedException kinds', () {
      for (final ImportRejectionKind kind in <ImportRejectionKind>[
        ImportRejectionKind.cancelled,
        ImportRejectionKind.storageFull,
      ]) {
        expect(
          () => ImportRejectedException(kind),
          throwsArgumentError,
          reason: kind.name,
        );
      }
      expect(ImportCancelledException(), isNot(isA<ImportRejectedException>()));
      expect(StorageFullException(), isNot(isA<ImportRejectedException>()));
      expect(StorageWriteException(), isNot(isA<ImportRejectedException>()));
    });

    test(
      'dedicated exceptions keep their codes, ARB keys, and retryability',
      () {
        final ImportCancelledException cancelled = ImportCancelledException();
        expect(cancelled.code, 'IMP-000');
        expect(cancelled.messageKey, 'IMP-000');
        expect(cancelled.retryable, isTrue);

        final StorageFullException full = StorageFullException();
        expect(full.code, 'SAVE-001');
        expect(full.messageKey, 'save001');
        expect(full.retryable, isTrue);

        final StorageWriteException write = StorageWriteException();
        expect(write.code, 'SAVE-003');
        expect(write.messageKey, 'save003');
        expect(write.retryable, isTrue);

        // SAVE-003 has two concrete causes that must not collapse.
        final CorruptDataException corrupt = CorruptDataException();
        expect(corrupt.code, 'SAVE-003');
        expect(corrupt.messageKey, 'save003');
        expect(corrupt.retryable, isFalse);
        expect(corrupt, isNot(isA<StorageWriteException>()));
        expect(write, isNot(isA<CorruptDataException>()));
      },
    );

    test('a rejection is content-free', () {
      final ImportRejectedException rejection = ImportRejectedException(
        ImportRejectionKind.unsupportedStructure,
      );
      expect(rejection.toString(), contains('IMP-004'));
      expect(rejection.toString(), isNot(contains('formular.pdf')));
      expect(rejection.toString(), isNot(contains('content://')));
      expect(rejection.toString(), isNot(contains('%PDF')));
    });
  });

  group('capability evidence vocabulary', () {
    test('simulated evidence is structurally labelled SIMULATED', () {
      final CapabilityEvidence evidence = _simulatedEvidence();
      expect(evidence.evidenceClass, EvidenceClass.simulated);
      expect(evidence.evidenceClass.label, 'SIMULATED');
      expect(evidence.simulated, isTrue);
      expect(evidence.simulatedReason, 'web.simulated-adapter');
      expect(evidence.toString(), 'CapabilityEvidence(SIMULATED)');
      expect(evidence.evidenceClass.isRuntime, isTrue);
      expect(evidence.evidenceClass, isNot(EvidenceClass.emulator));
      expect(evidence.evidenceClass, isNot(EvidenceClass.device));
    });

    test(
      'Android evidence declares NONE until the harness attaches a class',
      () {
        final CapabilityEvidence evidence = _androidEvidence();
        expect(evidence.evidenceClass, EvidenceClass.none);
        expect(evidence.evidenceClass.label, 'NONE');
        expect(evidence.simulated, isFalse);
        expect(evidence.simulatedReason, isNull);
        expect(evidence.evidenceClass.isAndroid, isFalse);
        expect(evidence.evidenceClass.isRuntime, isFalse);
      },
    );

    test('the simulated flag is derived and cannot be inconsistent', () {
      final CapabilityEvidence evidence = CapabilityEvidence(
        evidenceClass: EvidenceClass.simulated,
        adapterId: 'web.sim.import.v1',
      );
      expect(evidence.simulated, isTrue);
      expect(
        () => CapabilityEvidence(
          evidenceClass: EvidenceClass.none,
          adapterId: 'android.pdfbox.v1',
          simulatedReason: 'web.simulated-adapter',
        ),
        throwsArgumentError,
      );
    });

    test('parses the four canonical report tokens', () {
      expect(EvidenceClass.parse('SIMULATED'), EvidenceClass.simulated);
      expect(EvidenceClass.parse('emulator'), EvidenceClass.emulator);
      expect(EvidenceClass.parse('DEVICE'), EvidenceClass.device);
      expect(EvidenceClass.parse('none'), EvidenceClass.none);
      expect(EvidenceClass.tryParse('chrome'), isNull);
    });

    test('every acceptance-relevant port result requires evidence', () {
      // Both constructors take `required CapabilityEvidence`; this is a
      // compile-time proof plus a runtime label check.
      expect(_source().evidence, isA<CapabilityEvidence>());
      expect(
        SourceIntegrity(
          readable: true,
          actualSha256: _sha256,
          pageCount: 1,
          evidence: _androidEvidence(),
        ).evidence,
        isA<CapabilityEvidence>(),
      );
    });
  });

  group('port signatures and descriptor', () {
    test('the port exposes exactly the documented method parameter types', () {
      // This proves parameter TYPES only: `verifySource` takes a plain String,
      // so a path or URI represented as a string would still compile. Content
      // validation remains the adapter's obligation.
      final DocumentImportPort port = _SignatureProbe();
      final Future<ImportedSource> Function(ImportRequest) pick =
          port.pickAndImport;
      final Future<SourceIntegrity> Function(String) verify = port.verifySource;
      expect(pick, isNotNull);
      expect(verify, isNotNull);
    });

    test('the import descriptor enforces a truthful evidence label', () {
      final DocumentImportPort port = _SignatureProbe();
      final CapabilityDescriptor descriptor = port.descriptor;

      // The probe's values are produced by production code
      // (`CapabilityDescriptor` + `CapabilityEvidence.simulated`), not copied
      // from this test.
      expect(descriptor.kind, CapabilityKind.documentImport);
      expect(descriptor.evidence.evidenceClass, EvidenceClass.simulated);
      expect(descriptor.isSimulated, descriptor.evidence.simulated);
      expect(descriptor.adapterId, descriptor.evidence.adapterId);

      // A simulated importer must never be relabelled as a real capability:
      // flipping only the flag keeps the production evidence and must fail.
      expect(
        () => CapabilityDescriptor(
          kind: descriptor.kind,
          adapterId: descriptor.adapterId,
          version: descriptor.version,
          isSimulated: !descriptor.evidence.simulated,
          evidence: descriptor.evidence,
        ),
        throwsArgumentError,
      );

      // A real import adapter must not claim simulated evidence either.
      expect(
        () => CapabilityDescriptor(
          kind: CapabilityKind.documentImport,
          adapterId: 'android.pdfbox.v1',
          version: '1',
          isSimulated: true,
          evidence: _androidEvidence(),
        ),
        throwsArgumentError,
      );

      // Identity drift between the port and its evidence is rejected, so a
      // descriptor cannot describe one adapter while labelling another.
      expect(
        () => CapabilityDescriptor(
          kind: CapabilityKind.documentImport,
          adapterId: 'android.other.v1',
          version: '1',
          isSimulated: false,
          evidence: _androidEvidence(),
        ),
        throwsArgumentError,
      );
    });

    test('the port signature has no File, Uri, or widget parameter', () {
      // `ImportRequest` has no path field; the two method tear-offs above have
      // no `File`, `Uri`, or widget parameter. The source id is still a String
      // (see the corrected claim in the signature test), so this is a
      // type-shape assertion, not a content guarantee.
      final DocumentImportPort port = _SignatureProbe();
      final Future<ImportedSource> Function(ImportRequest) pick =
          port.pickAndImport;
      expect(pick, isNotNull);
      expect(ImportRequest().toString(), isNot(contains('File')));
      expect(ImportRequest().toString(), isNot(contains('Uri')));
    });
  });
}

/// A no-op production interface probe; it never executes import behaviour.
final class _SignatureProbe implements DocumentImportPort {
  @override
  CapabilityDescriptor get descriptor => CapabilityDescriptor(
    kind: CapabilityKind.documentImport,
    adapterId: 'web.sim.import.v1',
    version: '1',
    isSimulated: true,
    evidence: _simulatedEvidence(),
    supportedFeatures: const <String>{'signature-probe'},
  );

  @override
  Future<ImportedSource> pickAndImport(ImportRequest request) {
    throw UnimplementedError('signature probe only');
  }

  @override
  Future<SourceIntegrity> verifySource(String sourceId) {
    throw UnimplementedError('signature probe only');
  }
}
