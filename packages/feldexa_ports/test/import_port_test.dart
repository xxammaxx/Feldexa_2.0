// T037 `DocumentImportPort` contract tests (host VM, evidence class NONE).
//
// These tests pin `contracts/ports.md` §1, §2.1, §2.10, §3, and §4 together
// with `contracts/platform-channel.md` §3 and §12 and
// `spec.md` FR-001, FR-002, FR-004, FR-005, FR-008, FR-009, FR-010:
//   * single-page and multi-page image-only PDFs are accepted with the
//     documented `ImportedSource` and `PageGeometry` shape;
//   * encryption, unsupported structure, truncation, an unknown cause, an
//     oversized source, cancellation, storage exhaustion, and a failed staged
//     write map to the canonical typed rejection;
//   * a rejected import leaves no document, draft, template, stored record, or
//     staged source behind;
//   * the picked bytes are never modified, rewritten, or deleted, and
//     `verifySource` re-reads the stored source and reports the same hash;
//   * every result carries `CapabilityEvidence`, and a simulated result is
//     labelled `SIMULATED` and is never reported as a real capability.
//
// The deterministic import double below is defined in this file on purpose.
// `feldexa_ports` must not depend on `feldexa_adapters_simulated`, so the test
// mirrors the T028 adapter's observable contract instead of importing it. It
// implements a real SHA-256 only so the "written, read back, hash-verified"
// sequence is proven with the same digest the production contract names.
//
// This is a host-VM contract test: it proves nothing about Android, SAF, a
// real PDF parser, or any runtime. No Android/emulator/device evidence is
// produced. The SIMULATED results below are labelled `SIMULATED`.

import 'dart:collection';
import 'dart:typed_data';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// Adapter id used by the deterministic simulated double.
const String _adapterId = 'web.sim.import.v1';

/// The fixed import time of every result produced by the double.
final DateTime _importedAt = fixtureAt();

// ---------------------------------------------------------------------------
// Deterministic SHA-256
// ---------------------------------------------------------------------------

const List<int> _sha256K = <int>[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, //
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

int _rotr(int value, int bits) =>
    ((value >> bits) | (value << (32 - bits))) & 0xffffffff;

/// Returns the lowercase hex SHA-256 of [input].
String _sha256Hex(List<int> input) {
  final List<int> message = <int>[...input, 0x80];
  while (message.length % 64 != 56) {
    message.add(0);
  }
  final int bitLength = input.length * 8;
  for (int shift = 56; shift >= 0; shift -= 8) {
    message.add((bitLength >> shift) & 0xff);
  }
  final List<int> h = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  final List<int> w = List<int>.filled(64, 0);
  for (int offset = 0; offset < message.length; offset += 64) {
    for (int i = 0; i < 16; i++) {
      final int j = offset + i * 4;
      w[i] =
          ((message[j] << 24) |
              (message[j + 1] << 16) |
              (message[j + 2] << 8) |
              message[j + 3]) &
          0xffffffff;
    }
    for (int i = 16; i < 64; i++) {
      final int s0 =
          _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final int s1 =
          _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    int a = h[0];
    int b = h[1];
    int c = h[2];
    int d = h[3];
    int e = h[4];
    int f = h[5];
    int g = h[6];
    int hh = h[7];
    for (int i = 0; i < 64; i++) {
      final int s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final int ch = (e & f) ^ ((~e & 0xffffffff) & g);
      final int temp1 = (hh + s1 + ch + _sha256K[i] + w[i]) & 0xffffffff;
      final int s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final int maj = (a & b) ^ (a & c) ^ (b & c);
      final int temp2 = (s0 + maj) & 0xffffffff;
      hh = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }
    h[0] = (h[0] + a) & 0xffffffff;
    h[1] = (h[1] + b) & 0xffffffff;
    h[2] = (h[2] + c) & 0xffffffff;
    h[3] = (h[3] + d) & 0xffffffff;
    h[4] = (h[4] + e) & 0xffffffff;
    h[5] = (h[5] + f) & 0xffffffff;
    h[6] = (h[6] + g) & 0xffffffff;
    h[7] = (h[7] + hh) & 0xffffffff;
  }
  return h.map((int value) => value.toRadixString(16).padLeft(8, '0')).join();
}

// ---------------------------------------------------------------------------
// Deterministic import double (mirrors the T028 observable contract)
// ---------------------------------------------------------------------------

/// Fixture outcomes the double can produce.
enum _FakeStatus {
  valid,
  encrypted,
  unsupportedStructure,
  notPdf,
  truncated,
  unknownReason,
  writeFailure,
  readBackFailure,
}

/// One deterministic picker selection.
final class _FakeSelection {
  _FakeSelection({
    this.status = _FakeStatus.valid,
    List<int>? bytes,
    List<PageGeometry>? pages,
    List<PageFailure>? pageFailures,
    this.displayName = 'formular.pdf',
    this.title = 'Antrag',
    this.hasSelectableText = true,
    this.hasInteractiveFormFields = false,
  }) : bytes = Uint8List.fromList(bytes ?? _pdfBytes(256)),
       pages = List<PageGeometry>.unmodifiable(
         pages ?? <PageGeometry>[_a4Portrait()],
       ),
       pageFailures = List<PageFailure>.unmodifiable(
         pageFailures ?? const <PageFailure>[],
       );

  final _FakeStatus status;
  final Uint8List bytes;
  final List<PageGeometry> pages;
  final List<PageFailure> pageFailures;
  final String displayName;
  final String title;

  /// Metadata of the source, not an acceptance input. FR-002 requires an
  /// image-only PDF to be accepted on the same page-geometry terms.
  final bool hasSelectableText;

  /// Metadata of the source, not an acceptance input.
  final bool hasInteractiveFormFields;
}

/// One staged, verified source in the double's store.
final class _FakeStaged {
  _FakeStaged({
    required this.bytes,
    required this.sha256,
    required this.pageCount,
    required this.pageFailures,
  });

  final Uint8List bytes;
  final String sha256;
  final int pageCount;
  final List<PageFailure> pageFailures;
}

/// One document aggregate created by a successful import.
final class _FakeRecord {
  _FakeRecord({required this.documentId, required this.source});

  final String documentId;
  final SourceFileRef source;
}

/// Deterministic `DocumentImportPort` double.
///
/// It stages a defensive copy, reads it back, re-computes the digest, and only
/// then creates the document record. A rejection never leaves a staged source,
/// document, draft, template, or stored record behind.
final class _FakeDocumentImportAdapter implements DocumentImportPort {
  _FakeDocumentImportAdapter({
    CapabilityEvidence? evidence,
    this.capacityBytes = 1 << 20,
  }) : evidence =
           evidence ??
           CapabilityEvidence.simulated(
             adapterId: _adapterId,
             simulatedReason: 'web.simulated-adapter',
           );

  /// Evidence label of every result.
  final CapabilityEvidence evidence;

  /// Simulated staging capacity in bytes (`SAVE-001` when exceeded).
  final int capacityBytes;

  final Queue<_FakeSelection?> _selections = Queue<_FakeSelection?>();
  final Map<String, _FakeStaged> _staged = <String, _FakeStaged>{};
  final Map<String, _FakeRecord> documents = <String, _FakeRecord>{};
  final Map<String, Object?> drafts = <String, Object?>{};
  final Map<String, Object?> templates = <String, Object?>{};
  final Map<String, Object?> storedRecords = <String, Object?>{};

  int _idSequence = 100;

  @override
  CapabilityDescriptor get descriptor => CapabilityDescriptor(
    kind: CapabilityKind.documentImport,
    adapterId: evidence.adapterId,
    version: '1',
    isSimulated: evidence.simulated,
    evidence: evidence,
    supportedFeatures: const <String>{
      'fixture-catalog',
      'hash-verified-source',
      'typed-rejections',
    },
  );

  /// Queues one selection; null is an explicit user cancellation.
  void enqueue(_FakeSelection? selection) => _selections.add(selection);

  /// Queues one explicit user cancellation.
  void enqueueCancel() => _selections.add(null);

  /// Staged source ids in insertion order.
  List<String> get stagedSourceIds => List<String>.unmodifiable(_staged.keys);

  /// The staged bytes, or null when the source was removed.
  Uint8List? stagedBytes(String sourceId) => _staged[sourceId]?.bytes;

  String _newId() => fixtureUuid(_idSequence++);

  @override
  Future<ImportedSource> pickAndImport(ImportRequest request) async {
    if (_selections.isEmpty) {
      // An unconfigured double never invents an import.
      throw ImportCancelledException();
    }
    final _FakeSelection? selection = _selections.removeFirst();
    if (selection == null) {
      // FR-009 / §2.1: nothing is staged before this point.
      throw ImportCancelledException();
    }
    final Uint8List selectedBytes = selection.bytes;
    if (selectedBytes.length > request.maxBytes) {
      throw ImportRejectedException(ImportRejectionKind.tooLarge);
    }
    switch (selection.status) {
      case _FakeStatus.encrypted:
        throw ImportRejectedException(ImportRejectionKind.passwordProtected);
      case _FakeStatus.unsupportedStructure:
        throw ImportRejectedException(ImportRejectionKind.unsupportedStructure);
      case _FakeStatus.notPdf:
        throw ImportRejectedException(ImportRejectionKind.notPdf);
      case _FakeStatus.truncated:
        throw ImportRejectedException(ImportRejectionKind.truncated);
      case _FakeStatus.unknownReason:
        throw ImportRejectedException(ImportRejectionKind.unknownReason);
      case _FakeStatus.writeFailure:
        // The staged write failed; its temporary file is removed before the
        // typed failure is reported.
        throw StorageWriteException();
      case _FakeStatus.valid:
      case _FakeStatus.readBackFailure:
        break;
    }
    if (selectedBytes.length > capacityBytes) {
      // Capacity preflight before any source or aggregate becomes visible.
      throw StorageFullException();
    }

    final String documentId = _newId();
    final String sourceId = _newId();
    // Defensive copy: the picked bytes are never modified or reused in place.
    final Uint8List stagedBytes = Uint8List.fromList(selectedBytes);
    final String stagedSha256 = _sha256Hex(stagedBytes);
    _staged[sourceId] = _FakeStaged(
      bytes: stagedBytes,
      sha256: stagedSha256,
      pageCount: selection.pages.length,
      pageFailures: selection.pageFailures,
    );

    if (selection.status == _FakeStatus.readBackFailure) {
      _staged.remove(sourceId);
      throw ImportRejectedException(ImportRejectionKind.unreadable);
    }

    // Read back exactly what the store would return and verify the digest.
    final Uint8List? readBack = _staged[sourceId]?.bytes;
    if (readBack == null || _sha256Hex(readBack) != stagedSha256) {
      _staged.remove(sourceId);
      throw ImportRejectedException(ImportRejectionKind.unreadable);
    }

    final SourceFileRef source = SourceFileRef(
      id: sourceId,
      sha256: stagedSha256,
      sizeBytes: readBack.length,
      pageCount: selection.pages.length,
      originalName: selection.displayName,
      importedAt: _importedAt,
    );
    documents[documentId] = _FakeRecord(documentId: documentId, source: source);

    return ImportedSource(
      documentId: documentId,
      sourceId: sourceId,
      sha256: source.sha256,
      sizeBytes: readBack.length,
      pageCount: selection.pages.length,
      pages: selection.pages,
      pageFailures: selection.pageFailures,
      displayName: selection.displayName,
      evidence: evidence,
    );
  }

  @override
  Future<SourceIntegrity> verifySource(String sourceId) async {
    final _FakeStaged? staged = _staged[sourceId];
    if (staged == null) {
      return SourceIntegrity(readable: false, evidence: evidence);
    }
    final Uint8List readBack = Uint8List.fromList(staged.bytes);
    final String actual = _sha256Hex(readBack);
    return SourceIntegrity(
      readable:
          actual == staged.sha256 && readBack.length == staged.bytes.length,
      actualSha256: actual,
      pageCount: staged.pageCount,
      pageFailures: staged.pageFailures,
      evidence: evidence,
    );
  }
}

// ---------------------------------------------------------------------------
// Deterministic fixtures
// ---------------------------------------------------------------------------

/// Deterministic synthetic PDF-shaped bytes. The double never parses them.
Uint8List _pdfBytes(int length) {
  final Uint8List bytes = Uint8List(length);
  const List<int> header = <int>[
    0x25,
    0x50,
    0x44,
    0x46,
    0x2d,
    0x31,
    0x2e,
    0x37,
    0x0a,
  ];
  for (int index = 0; index < length; index++) {
    bytes[index] = index < header.length ? header[index] : index % 251;
  }
  return bytes;
}

PageGeometry _a4Portrait() =>
    PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842));

PageGeometry _a4Rotated(int rotation) =>
    PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842), rotation: rotation);

PageGeometry _a5Portrait() =>
    PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 420, 595));

/// Five image-only pages with portrait, landscape, A5, and both upside-down
/// orientations. The visible sizes are the preflight contract.
List<PageGeometry> _fivePageGeometry() => <PageGeometry>[
  _a4Portrait(),
  _a4Rotated(90),
  _a5Portrait(),
  _a4Rotated(180),
  _a4Rotated(270),
];

_FakeDocumentImportAdapter _simulatedAdapter({int capacityBytes = 1 << 20}) =>
    _FakeDocumentImportAdapter(capacityBytes: capacityBytes);

_FakeSelection _validSelection({
  int byteLength = 256,
  List<PageGeometry>? pages,
  List<PageFailure>? pageFailures,
  bool imageOnly = false,
  String displayName = 'formular.pdf',
}) {
  return _FakeSelection(
    bytes: _pdfBytes(byteLength),
    pages: pages,
    pageFailures: pageFailures,
    displayName: displayName,
    title: displayName,
    hasSelectableText: !imageOnly,
    hasInteractiveFormFields: false,
  );
}

Matcher _rejectedAs(ImportRejectionKind kind, String code) {
  return isA<ImportRejectedException>()
      .having((ImportRejectedException e) => e.kind, 'kind', kind)
      .having((ImportRejectedException e) => e.code, 'code', code)
      .having((ImportRejectedException e) => e.messageKey, 'messageKey', code)
      .having((ImportRejectedException e) => e.retryable, 'retryable', false);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SHA-256 double', () {
    test('matches the standard empty and "abc" vectors', () {
      // Proves the digest used by the double before it is trusted below.
      expect(
        _sha256Hex(const <int>[]),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        _sha256Hex(const <int>[0x61, 0x62, 0x63]),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });

  group('single-page and multi-page import (FR-001/FR-002)', () {
    test('accepts a single-page PDF with the documented shape', () async {
      final _FakeDocumentImportAdapter adapter = _simulatedAdapter();
      final _FakeSelection selection = _validSelection();
      adapter.enqueue(selection);

      final ImportedSource result = await adapter.pickAndImport(
        ImportRequest(),
      );

      expect(result.documentId, isNotEmpty);
      expect(result.sourceId, isNotEmpty);
      expect(result.sha256, _sha256Hex(selection.bytes));
      expect(result.sizeBytes, selection.bytes.length);
      expect(result.pageCount, 1);
      expect(result.pages.length, result.pageCount);
      expect(result.pageFailures, isEmpty);
      expect(result.displayName, 'formular.pdf');
      expect(result.evidence.evidenceClass, EvidenceClass.simulated);
      expect(adapter.documents, hasLength(1));
      expect(adapter.documents[result.documentId]!.source.id, result.sourceId);
      expect(
        adapter.documents[result.documentId]!.source.sha256,
        result.sha256,
      );
    });

    test('accepts a five-page image-only PDF and keeps page geometry', () async {
      final _FakeDocumentImportAdapter adapter = _simulatedAdapter();
      final List<PageGeometry> geometry = _fivePageGeometry();
      adapter.enqueue(
        _validSelection(
          byteLength: 4096,
          pages: geometry,
          imageOnly: true,
          displayName: 'scan.pdf',
        ),
      );

      final ImportedSource result = await adapter.pickAndImport(
        ImportRequest(),
      );

      expect(result.pageCount, 5);
      expect(result.pages.length, 5);
      expect(result.pageFailures, isEmpty);
      for (int index = 0; index < geometry.length; index++) {
        expect(result.pages[index], geometry[index], reason: 'page $index');
      }
      // The preflight contract is page geometry, not text or AcroForm content.
      expect(result.pages[0].rotation, 0);
      expect(result.pages[0].displaySize, Size(595, 842));
      expect(result.pages[1].rotation, 90);
      expect(result.pages[1].displaySize, Size(842, 595));
      expect(result.pages[2].displaySize, Size(420, 595));
      expect(result.pages[3].rotation, 180);
      expect(result.pages[4].rotation, 270);
      expect(result.pages[4].displaySize, Size(842, 595));
      expect(adapter.documents, hasLength(1));
    });

    test('accepts an image-only PDF on the same terms as a text PDF', () async {
      final _FakeDocumentImportAdapter adapter = _simulatedAdapter();
      final List<PageGeometry> geometry = _fivePageGeometry();
      final _FakeSelection textPdf = _validSelection(
        byteLength: 4096,
        pages: geometry,
        displayName: 'text.pdf',
      );
      final _FakeSelection imageOnly = _validSelection(
        byteLength: 4096,
        pages: geometry,
        imageOnly: true,
        displayName: 'image-only.pdf',
      );
      expect(textPdf.hasSelectableText, isTrue);
      expect(imageOnly.hasSelectableText, isFalse);
      expect(imageOnly.hasInteractiveFormFields, isFalse);
      adapter.enqueue(textPdf);
      adapter.enqueue(imageOnly);

      final ImportedSource text = await adapter.pickAndImport(ImportRequest());
      final ImportedSource image = await adapter.pickAndImport(ImportRequest());

      expect(image.pageCount, text.pageCount);
      expect(image.pages, text.pages);
      expect(image.pageFailures, text.pageFailures);
      expect(image.evidence, text.evidence);
      expect(adapter.documents, hasLength(2));
    });

    test('pin the 80 MiB cap on ImportRequest', () {
      expect(maxSourceSizeBytes, 83886080);
      expect(ImportRequest().maxBytes, 83886080);
      expect(ImportRequest(maxBytes: 83886080).maxBytes, 83886080);
      expect(() => ImportRequest(maxBytes: 0), throwsArgumentError);
      expect(() => ImportRequest(maxBytes: 83886081), throwsArgumentError);
    });

    test(
      'reports a partially readable source with IMP-006 and keeps pages',
      () async {
        final _FakeDocumentImportAdapter adapter = _simulatedAdapter();
        adapter.enqueue(
          _validSelection(
            pages: _fivePageGeometry(),
            pageFailures: <PageFailure>[
              PageFailure(
                pageIndex: 2,
                category: PageFailureCategory.unreadable,
                messageKey: 'IMP-006',
              ),
            ],
          ),
        );

        final ImportedSource result = await adapter.pickAndImport(
          ImportRequest(),
        );

        expect(result.pageCount, 5);
        expect(result.pages.length, 5);
        expect(result.pageFailures, hasLength(1));
        expect(result.pageFailures.single.pageIndex, 2);
        expect(
          result.pageFailures.single.category,
          PageFailureCategory.unreadable,
        );
        expect(result.pageFailures.single.messageKey, 'IMP-006');
        // IMP-006 is a successful import that still creates the document.
        expect(adapter.documents, hasLength(1));
        expect(adapter.documents[result.documentId]!.source.pageCount, 5);
      },
    );
  });

  group('typed rejections (FR-005/FR-008)', () {
    test('encrypted PDF is IMP-001 passwordProtected', () async {
      final _FakeDocumentImportAdapter adapter = _simulatedAdapter();
      adapter.enqueue(_FakeSelection(status: _FakeStatus.encrypted));

      await expectLater(
        adapter.pickAndImport(ImportRequest()),
        throwsA(_rejectedAs(ImportRejectionKind.passwordProtected, 'IMP-001')),
      );
      expect(adapter.stagedSourceIds, isEmpty);
      expect(adapter.documents, isEmpty);
    });

    test('unsupported PDF structure is IMP-004', () async {
      final _FakeDocumentImportAdapter adapter = _simulatedAdapter();
      adapter.enqueue(_FakeSelection(status: _FakeStatus.unsupportedStructure));

      await expectLater(
        adapter.pickAndImport(ImportRequest()),
        throwsA(
          _rejectedAs(ImportRejectionKind.unsupportedStructure, 'IMP-004'),
        ),
      );
      expect(adapter.stagedSourceIds, isEmpty);
    });

    test('a non-PDF is also IMP-004', () async {
      final _FakeDocumentImportAdapter adapter = _simulatedAdapter();
      adapter.enqueue(_FakeSelection(status: _FakeStatus.notPdf));

      await expectLater(
        adapter.pickAndImport(ImportRequest()),
        throwsA(_rejectedAs(ImportRejectionKind.notPdf, 'IMP-004')),
      );
    });

    test('a truncated PDF is IMP-002', () async {
      final _FakeDocumentImportAdapter adapter = _simulatedAdapter();
      adapter.enqueue(_FakeSelection(status: _FakeStatus.truncated));

      await expectLater(
        adapter.pickAndImport(ImportRequest()),
        throwsA(_rejectedAs(ImportRejectionKind.truncated, 'IMP-002')),
      );
    });

    test(
      'an unknown failure reason is IMP-005, never a password claim',
      () async {
        final _FakeDocumentImportAdapter adapter = _simulatedAdapter();
        adapter.enqueue(_FakeSelection(status: _FakeStatus.unknownReason));

        await expectLater(
          adapter.pickAndImport(ImportRequest()),
          throwsA(_rejectedAs(ImportRejectionKind.unknownReason, 'IMP-005')),
        );
        expect(adapter.stagedSourceIds, isEmpty);
        expect(adapter.documents, isEmpty);
      },
    );

    test('a source above the request cap is IMP-007', () async {
      final _FakeDocumentImportAdapter adapter = _simulatedAdapter();
      adapter.enqueue(_validSelection(byteLength: 65));

      await expectLater(
        adapter.pickAndImport(ImportRequest(maxBytes: 64)),
        throwsA(_rejectedAs(ImportRejectionKind.tooLarge, 'IMP-007')),
      );
      expect(adapter.stagedSourceIds, isEmpty);
      expect(adapter.documents, isEmpty);
    });

    test('a failed staged read-back removes the staged source', () async {
      final _FakeDocumentImportAdapter adapter = _simulatedAdapter();
      adapter.enqueue(_FakeSelection(status: _FakeStatus.readBackFailure));

      await expectLater(
        adapter.pickAndImport(ImportRequest()),
        throwsA(_rejectedAs(ImportRejectionKind.unreadable, 'IMP-002')),
      );
      expect(adapter.stagedSourceIds, isEmpty);
      expect(adapter.documents, isEmpty);
    });

    test(
      'user cancellation is ImportCancelledException with IMP-000',
      () async {
        final _FakeDocumentImportAdapter adapter = _simulatedAdapter();
        adapter.enqueueCancel();

        await expectLater(
          adapter.pickAndImport(ImportRequest()),
          throwsA(
            isA<ImportCancelledException>()
                .having(
                  (ImportCancelledException e) => e.code,
                  'code',
                  'IMP-000',
                )
                .having(
                  (ImportCancelledException e) => e.messageKey,
                  'messageKey',
                  'IMP-000',
                )
                .having(
                  (ImportCancelledException e) => e.retryable,
                  'retryable',
                  true,
                ),
          ),
        );
        expect(adapter.stagedSourceIds, isEmpty);
        expect(adapter.documents, isEmpty);
        expect(adapter.drafts, isEmpty);
        expect(adapter.templates, isEmpty);
        expect(adapter.storedRecords, isEmpty);
      },
    );

    test('storage exhaustion is StorageFullException with SAVE-001', () async {
      final _FakeDocumentImportAdapter adapter = _simulatedAdapter(
        capacityBytes: 128,
      );
      adapter.enqueue(_validSelection(byteLength: 256));

      await expectLater(
        adapter.pickAndImport(ImportRequest()),
        throwsA(
          isA<StorageFullException>()
              .having((StorageFullException e) => e.code, 'code', 'SAVE-001')
              .having(
                (StorageFullException e) => e.retryable,
                'retryable',
                true,
              ),
        ),
      );
      expect(adapter.stagedSourceIds, isEmpty);
      expect(adapter.documents, isEmpty);
      expect(adapter.drafts, isEmpty);
      expect(adapter.templates, isEmpty);
      expect(adapter.storedRecords, isEmpty);
    });

    test(
      'a failed staged write is StorageWriteException with SAVE-003',
      () async {
        final _FakeDocumentImportAdapter adapter = _simulatedAdapter();
        adapter.enqueue(_FakeSelection(status: _FakeStatus.writeFailure));

        await expectLater(
          adapter.pickAndImport(ImportRequest()),
          throwsA(
            isA<StorageWriteException>()
                .having((StorageWriteException e) => e.code, 'code', 'SAVE-003')
                .having(
                  (StorageWriteException e) => e.retryable,
                  'retryable',
                  true,
                ),
          ),
        );
        expect(adapter.stagedSourceIds, isEmpty);
        expect(adapter.documents, isEmpty);
        expect(adapter.drafts, isEmpty);
        expect(adapter.templates, isEmpty);
        expect(adapter.storedRecords, isEmpty);
      },
    );

    test('every rejection leaves no record (FR-009)', () async {
      final List<_FakeSelection> rejections = <_FakeSelection>[
        _FakeSelection(status: _FakeStatus.encrypted),
        _FakeSelection(status: _FakeStatus.unsupportedStructure),
        _FakeSelection(status: _FakeStatus.notPdf),
        _FakeSelection(status: _FakeStatus.truncated),
        _FakeSelection(status: _FakeStatus.unknownReason),
        _FakeSelection(status: _FakeStatus.writeFailure),
        _FakeSelection(status: _FakeStatus.readBackFailure),
      ];
      for (final _FakeSelection selection in rejections) {
        final _FakeDocumentImportAdapter adapter = _simulatedAdapter();
        adapter.enqueue(selection);
        await expectLater(
          adapter.pickAndImport(ImportRequest()),
          throwsA(isA<FeldexaException>()),
          reason: selection.status.name,
        );
        expect(adapter.documents, isEmpty, reason: selection.status.name);
        expect(adapter.drafts, isEmpty, reason: selection.status.name);
        expect(adapter.templates, isEmpty, reason: selection.status.name);
        expect(adapter.storedRecords, isEmpty, reason: selection.status.name);
        expect(adapter.stagedSourceIds, isEmpty, reason: selection.status.name);
      }
    });
  });

  group('source immutability and verifySource (FR-004)', () {
    test('picked bytes are never modified, rewritten, or deleted', () async {
      final _FakeDocumentImportAdapter adapter = _simulatedAdapter();
      final _FakeSelection selection = _validSelection(byteLength: 1024);
      final Uint8List original = Uint8List.fromList(selection.bytes);
      adapter.enqueue(selection);

      final ImportedSource result = await adapter.pickAndImport(
        ImportRequest(),
      );

      expect(selection.bytes, orderedEquals(original));
      expect(result.sha256, _sha256Hex(original));
      expect(result.sizeBytes, original.length);

      // The staged copy equals the original bytes but is not the same object.
      final Uint8List? staged = adapter.stagedBytes(result.sourceId);
      expect(staged, isNotNull);
      expect(staged, orderedEquals(original));
      expect(identical(staged, selection.bytes), isFalse);

      // verifySource re-reads the stored source and reports the same hash.
      final SourceIntegrity verified = await adapter.verifySource(
        result.sourceId,
      );
      expect(verified.readable, isTrue);
      expect(verified.actualSha256, result.sha256);
      expect(verified.pageCount, result.pageCount);
      expect(verified.pageFailures, isEmpty);
      expect(verified.evidence.evidenceClass, EvidenceClass.simulated);

      // A second read-back and the original selection still agree.
      final SourceIntegrity again = await adapter.verifySource(result.sourceId);
      expect(again.actualSha256, result.sha256);
      expect(selection.bytes, orderedEquals(original));
      expect(adapter.stagedBytes(result.sourceId), orderedEquals(original));
    });

    test('verifySource reports an unknown source as unreadable, without a path lookup', () async {
      final _FakeDocumentImportAdapter adapter = _simulatedAdapter();

      final SourceIntegrity missing = await adapter.verifySource(
        '00000000-0000-4000-8000-00000000ffff',
      );

      expect(missing.readable, isFalse);
      expect(missing.actualSha256, isNull);
      expect(missing.pageCount, isNull);
      expect(missing.evidence.evidenceClass, EvidenceClass.simulated);
      expect(adapter.documents, isEmpty);
    });

    test('the port surface takes ImportRequest/sourceId only, never a path, File, URI, or widget', () {
      final _FakeDocumentImportAdapter adapter = _simulatedAdapter();
      final DocumentImportPort port = adapter;

      // Compile-time proof of the two documented signatures. A `File`, a
      // `content://` URI, a path string, or a widget cannot be passed.
      final Future<ImportedSource> Function(ImportRequest) pick =
          port.pickAndImport;
      final Future<SourceIntegrity> Function(String) verify = port.verifySource;
      expect(pick, isNotNull);
      expect(verify, isNotNull);
      expect(port.descriptor.kind, CapabilityKind.documentImport);
      expect(port.descriptor.isSimulated, isTrue);
      expect(port.descriptor.evidence.evidenceClass, EvidenceClass.simulated);

      // ImportRequest carries only the bounded byte cap.
      expect(ImportRequest().maxBytes, maxSourceSizeBytes);
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

    test('cancelled and storageFull are not ImportRejectedException kinds', () {
      // §2.1 routes these two through their dedicated exceptions.
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

    test('dedicated exceptions keep their catalog codes', () {
      expect(ImportCancelledException().code, 'IMP-000');
      expect(ImportCancelledException().message, 'import.cancelled');
      expect(StorageFullException().code, 'SAVE-001');
      expect(StorageFullException().message, 'storage.full');
      expect(StorageWriteException().code, 'SAVE-003');
      expect(StorageWriteException().message, 'storage.writeFailed');
      // SAVE-003 has two concrete causes that must not collapse.
      expect(CorruptDataException().code, 'SAVE-003');
      expect(CorruptDataException(), isNot(isA<StorageWriteException>()));
      expect(StorageWriteException(), isNot(isA<CorruptDataException>()));
    });

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

  group('evidence labelling', () {
    test(
      'SIMULATED result carries simulated evidence and is never real',
      () async {
        final _FakeDocumentImportAdapter adapter = _simulatedAdapter();
        adapter.enqueue(_validSelection());

        final ImportedSource result = await adapter.pickAndImport(
          ImportRequest(),
        );

        expect(result.evidence.evidenceClass, EvidenceClass.simulated);
        expect(result.evidence.evidenceClass.label, 'SIMULATED');
        expect(result.evidence.simulated, isTrue);
        expect(result.evidence.simulatedReason, 'web.simulated-adapter');
        expect(result.evidence.evidenceClass, isNot(EvidenceClass.emulator));
        expect(result.evidence.evidenceClass, isNot(EvidenceClass.device));
        expect(result.evidence.evidenceClass.isRuntime, isTrue);
        expect(result.evidence.toString(), 'CapabilityEvidence(SIMULATED)');
        expect(result.toString(), contains('pageCount: 1'));
        expect(result.toString(), isNot(contains('formular.pdf')));
      },
    );

    test('Android-evidence result declares EvidenceClass.none until the harness labels it', () async {
      final _FakeDocumentImportAdapter adapter = _FakeDocumentImportAdapter(
        evidence: CapabilityEvidence.android(adapterId: 'android.pdfbox.v1'),
      );
      adapter.enqueue(_validSelection());

      final ImportedSource result = await adapter.pickAndImport(
        ImportRequest(),
      );

      expect(result.evidence.evidenceClass, EvidenceClass.none);
      expect(result.evidence.evidenceClass.label, 'NONE');
      expect(result.evidence.simulated, isFalse);
      expect(result.evidence.evidenceClass.isAndroid, isFalse);
      expect(result.evidence.evidenceClass.isRuntime, isFalse);
      expect(result.evidence.simulatedReason, isNull);
      expect(adapter.descriptor.isSimulated, isFalse);
    });
  });
}
