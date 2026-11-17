// T037 core import contract tests (host VM, evidence class NONE).
//
// These tests pin the core half of `spec.md` FR-001, FR-002, FR-004, FR-009,
// and FR-010 and the canonical types used by `contracts/ports.md` §2.1:
//   * `SourceFileRef` bounds: lowercase UUIDv4 id, 64 lowercase hex SHA-256,
//     size `1 … 83,886,080`, page count `1 … 100`, UTC import time, and a
//     display-only trimmed `originalName` that is never echoed in an error;
//   * `SourceIntegrityState` semantics for an imported source;
//   * `PageFailure` for the partially-readable `IMP-006` import: the page index
//     is a real page, the category is one of the three documented values, and
//     the value carries no content;
//   * `PageGeometry` preflight invariants: media box, effective crop box, and
//     the normalized rotation;
//   * the canonical-JSON save/reopen round trip of an imported source
//     reference: it stays byte-identical and immutable (FR-004).
//
// This file imports only `package:feldexa_core/...`. It must not import
// `feldexa_ports`: the dependency direction is one-way, and the existing
// `feldexa_ports/test/type_ownership_test.dart` owns the file-system guard for
// that rule.
//
// Host-VM only. This produces no SIMULATED, EMULATOR, or DEVICE runtime
// evidence and proves nothing about Android import or PDF parsing.

import 'dart:convert';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:flutter_test/flutter_test.dart';

const String _sha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _otherSha256 =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

String _uuid([int value = 1]) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

String _repeat(String unit, int count) =>
    List<String>.filled(count, unit).join();

DateTime _at([int minute = 0]) => DateTime.utc(2026, 11, 16, 9, 30, minute);

SourceFileRef _source({
  String? id,
  String? sha256,
  int sizeBytes = 1234,
  int pageCount = 1,
  String? originalName = 'formular.pdf',
  DateTime? importedAt,
  SourceIntegrityState integrity = SourceIntegrityState.verified,
  Map<String, Object?> unknownFields = const <String, Object?>{},
}) {
  return SourceFileRef(
    id: id ?? _uuid(),
    sha256: sha256 ?? _sha256,
    sizeBytes: sizeBytes,
    pageCount: pageCount,
    originalName: originalName,
    importedAt: importedAt ?? _at(),
    integrity: integrity,
    unknownFields: unknownFields,
  );
}

PageGeometry _a4Portrait() =>
    PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842));

PageGeometry _a4Rotated(int rotation) =>
    PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 595, 842), rotation: rotation);

PageFailure _failure({
  int pageIndex = 2,
  PageFailureCategory category = PageFailureCategory.unreadable,
  String messageKey = 'IMP-006',
}) {
  return PageFailure(
    pageIndex: pageIndex,
    category: category,
    messageKey: messageKey,
  );
}

void main() {
  group('SourceFileRef invariants (FR-001/FR-004)', () {
    test('accepts the documented size and page-count bounds', () {
      expect(_source(sizeBytes: 1, pageCount: 1).sizeBytes, 1);
      expect(_source(sizeBytes: 1, pageCount: 1).pageCount, 1);
      expect(_source(sizeBytes: 83886080, pageCount: 100).sizeBytes, 83886080);
      expect(_source(sizeBytes: 83886080, pageCount: 100).pageCount, 100);
      // Exercise the production constructor default directly; passing the
      // value through the helper would hide a changed constructor default.
      final SourceFileRef imported = SourceFileRef(
        id: _uuid(),
        sha256: _sha256,
        sizeBytes: 1,
        pageCount: 1,
        importedAt: _at(),
      );
      expect(imported.integrity, SourceIntegrityState.verified);
    });

    test('rejects an id that is not a lowercase UUIDv4', () {
      final List<String> invalid = <String>[
        '00000000-0000-4000-8000-00000000000A', // uppercase hex
        '00000000-0000-1000-8000-000000000001', // version 1
        '00000000-0000-4000-7000-000000000001', // wrong variant
        '00000000000040008000000000000001', // no dashes
        '',
      ];
      for (final String value in invalid) {
        expect(() => _source(id: value), throwsArgumentError, reason: value);
      }
    });

    test('rejects a sha256 that is not 64 lowercase hex characters', () {
      final List<String> invalid = <String>[
        _sha256.toUpperCase(),
        _sha256.substring(0, 63),
        '${_sha256}a',
        _repeat('g', 64),
        '',
      ];
      for (final String value in invalid) {
        expect(
          () => _source(sha256: value),
          throwsArgumentError,
          reason: value,
        );
      }
    });

    test('rejects sizeBytes outside 1 … 83,886,080', () {
      expect(maxSourceSizeBytes, 83886080);
      expect(() => _source(sizeBytes: 0), throwsArgumentError);
      expect(() => _source(sizeBytes: 83886081), throwsArgumentError);
    });

    test('rejects pageCount outside 1 … 100', () {
      expect(maxSourcePageCount, 100);
      expect(() => _source(pageCount: 0), throwsArgumentError);
      expect(() => _source(pageCount: 101), throwsArgumentError);
    });

    test('requires UTC importedAt', () {
      expect(
        _source(importedAt: DateTime.utc(2026, 11, 16)).importedAt.isUtc,
        isTrue,
      );
      expect(
        () => _source(importedAt: DateTime(2026, 11, 16)),
        throwsArgumentError,
      );
    });

    test('normalizes originalName as display-only metadata', () {
      expect(
        _source(originalName: '  formular.pdf  ').originalName,
        'formular.pdf',
      );
      expect(_source(originalName: '').originalName, isNull);
      expect(_source(originalName: '   ').originalName, isNull);
      expect(_source(originalName: null).originalName, isNull);
      final String max = List<String>.filled(255, 'a').join();
      expect(_source(originalName: max).originalName, max);
      expect(() => _source(originalName: '${max}b'), throwsArgumentError);
      expect(
        () => _source(originalName: 'form\u0000ular.pdf'),
        throwsArgumentError,
      );
      expect(
        () => _source(originalName: 'form\u007fular.pdf'),
        throwsArgumentError,
      );
    });

    test('never echoes the rejected original name in an error', () {
      const String sentinel = 'geheim';
      Object? caught;
      try {
        _source(originalName: '$sentinel\u0000.pdf');
      } on ArgumentError catch (error) {
        caught = error;
      }
      expect(caught, isA<ArgumentError>());
      expect(caught.toString(), isNot(contains(sentinel)));

      caught = null;
      try {
        _source(originalName: '$sentinel${_repeat('b', 300)}');
      } on ArgumentError catch (error) {
        caught = error;
      }
      expect(caught, isA<ArgumentError>());
      expect(caught.toString(), isNot(contains(sentinel)));
      // The name is display-only and is not part of the log identity.
      expect(_source().toString(), isNot(contains('formular.pdf')));
    });

    test('copyWith returns a new reference and leaves the original intact', () {
      final SourceFileRef original = _source();
      final SourceFileRef changed = original.copyWith(pageCount: 5);

      expect(identical(original, changed), isFalse);
      expect(original.pageCount, 1);
      expect(changed.pageCount, 5);
      expect(original, equals(_source()));

      final SourceFileRef trimmed = original.copyWith(
        originalName: '  neu.pdf ',
      );
      expect(trimmed.originalName, 'neu.pdf');
      expect(original.originalName, 'formular.pdf');
      final SourceFileRef cleared = original.copyWith(originalName: null);
      expect(cleared.originalName, isNull);
    });
  });

  group('SourceIntegrityState semantics', () {
    test('verified and unreadable use the documented wire tokens', () {
      expect(SourceIntegrityState.verified.wireName, 'verified');
      expect(SourceIntegrityState.unreadable.wireName, 'unreadable');
      expect(
        SourceIntegrityState.fromWire('verified'),
        SourceIntegrityState.verified,
      );
      expect(
        SourceIntegrityState.fromWire('unreadable'),
        SourceIntegrityState.unreadable,
      );
      expect(
        () => SourceIntegrityState.fromWire('deleted'),
        throwsFormatException,
      );
    });

    test('an unreadable imported source stays a valid, immutable reference', () {
      final SourceFileRef unreadable = _source(
        integrity: SourceIntegrityState.unreadable,
      );

      expect(unreadable.integrity, SourceIntegrityState.unreadable);
      expect(unreadable.id, _uuid());
      expect(unreadable.sha256, _sha256);
      // The reference is unreadable, not deleted: the bytes and identity stay.
      final Map<String, Object?> json = unreadable.toJson();
      expect(json['integrity'], 'unreadable');
      expect(json['id'], unreadable.id);
      expect(json['sha256'], unreadable.sha256);

      final SourceFileRef reopened = SourceFileRef.fromJson(json);
      expect(reopened, unreadable);
      expect(reopened.integrity, SourceIntegrityState.unreadable);
    });

    test('the imported reference compares equal to the same value', () {
      // `Object.hashCode` is not collision-free, so equality is the only
      // contract asserted here.
      final SourceFileRef verified = _source();
      expect(verified, equals(_source()));
    });
  });

  group('PageFailure invariants (IMP-006 partial import)', () {
    test('accepts the three documented categories', () {
      for (final PageFailureCategory category in PageFailureCategory.values) {
        final PageFailure failure = _failure(category: category);
        expect(failure.category, category);
        expect(failure.messageKey, 'IMP-006');
      }
      expect(
        PageFailureCategory.values
            .map((PageFailureCategory value) => value.wireName)
            .toSet(),
        <String>{'rasterization', 'unreadable', 'unsupported_structure'},
      );
    });

    test('rejects a negative page index', () {
      expect(() => _failure(pageIndex: -1), throwsArgumentError);
    });

    test(
      'rejects a message key that is not a catalog code, without echoing it',
      () {
        expect(
          () => _failure(messageKey: 'Seite 3 konnte nicht gelesen werden'),
          throwsArgumentError,
        );
        Object? caught;
        try {
          _failure(messageKey: 'Geheime Seite');
        } on ArgumentError catch (error) {
          caught = error;
        }
        expect(caught, isA<ArgumentError>());
        expect(caught.toString(), isNot(contains('Geheime')));
      },
    );

    test('rejects an unknown category wire token on read', () {
      expect(
        () => PageFailure.fromJson(<String, Object?>{
          'pageIndex': 0,
          'category': 'ocr',
          'messageKey': 'IMP-006',
        }),
        throwsFormatException,
      );
    });

    test('serializes only index, category, and message key', () {
      final PageFailure failure = _failure();
      expect(failure.toJson(), <String, Object?>{
        'pageIndex': 2,
        'category': 'unreadable',
        'messageKey': 'IMP-006',
      });
      expect(
        failure.toString(),
        'PageFailure(pageIndex: 2, category: unreadable)',
      );
      expect(failure.toString(), isNot(contains('IMP-006')));
      expect(PageFailure.fromJson(failure.toJson()), failure);
    });

    test('a failure must name the page it belongs to, inside the source', () {
      // The source has five pages; the failure for page 2 is attachable only
      // to page 2. (The ports `ImportedSource` additionally enforces
      // `pageIndex < pageCount`; the document aggregate enforces the full
      // contiguous page list.)
      final SourceFileRef source = _source(pageCount: 5);
      expect(source.pageCount, 5);

      final Page attached = Page(
        index: 2,
        geometry: _a4Portrait(),
        analysis: AnalysisState.failed,
        failure: _failure(pageIndex: 2),
      );
      expect(attached.failure!.pageIndex, 2);
      expect(attached.unreadable, isFalse);
      expect(Page.fromJson(attached.toJson()), attached);

      expect(
        () => Page(
          index: 2,
          geometry: _a4Portrait(),
          analysis: AnalysisState.failed,
          failure: _failure(pageIndex: 3),
        ),
        throwsArgumentError,
      );
      expect(
        () => Page(
          index: 2,
          geometry: _a4Portrait(),
          analysis: AnalysisState.failed,
        ),
        throwsArgumentError,
      );
      expect(
        () => Page(
          index: 2,
          geometry: _a4Portrait(),
          analysis: AnalysisState.complete,
          failure: _failure(pageIndex: 2),
        ),
        throwsArgumentError,
      );
    });
  });

  group('PageGeometry invariants (import preflight)', () {
    test('defaults the crop box to the media box', () {
      final PageGeometry geometry = _a4Portrait();
      expect(geometry.mediaBox, Rect.fromLTWH(0, 0, 595, 842));
      expect(geometry.cropBox, geometry.mediaBox);
      expect(geometry.rotation, 0);
      expect(geometry.displaySize, Size(595, 842));
    });

    test('intersects the crop box with the media box', () {
      final PageGeometry geometry = PageGeometry(
        mediaBox: Rect.fromLTWH(0, 0, 600, 800),
        cropBox: Rect.fromLTWH(-10, -20, 300, 400),
      );
      expect(geometry.cropBox, Rect.fromLTWH(0, 0, 290, 380));
      expect(geometry.displaySize, Size(290, 380));
      // A quarter turn swaps the visible dimensions.
      final PageGeometry rotated = PageGeometry(
        mediaBox: Rect.fromLTWH(0, 0, 600, 800),
        cropBox: Rect.fromLTWH(-10, -20, 300, 400),
        rotation: 90,
      );
      expect(rotated.displaySize, Size(380, 290));
    });

    test('rejects a crop box that does not overlap the media box', () {
      expect(
        () => PageGeometry(
          mediaBox: Rect.fromLTWH(0, 0, 600, 800),
          cropBox: Rect.fromLTWH(700, 900, 100, 100),
        ),
        throwsArgumentError,
      );
      expect(
        () => PageGeometry(
          mediaBox: Rect.fromLTWH(0, 0, 600, 800),
          cropBox: Rect.fromLTWH(600, 0, 100, 100),
        ),
        throwsArgumentError,
      );
    });

    test('accepts exactly the four normalized rotations', () {
      for (final int rotation in <int>[0, 90, 180, 270]) {
        expect(_a4Rotated(rotation).rotation, rotation);
      }
      for (final int rotation in <int>[-90, 45, 360, 1]) {
        expect(
          () => _a4Rotated(rotation),
          throwsArgumentError,
          reason: '$rotation',
        );
      }
    });

    test('displaySize follows the rotation', () {
      expect(_a4Rotated(0).displaySize, Size(595, 842));
      expect(_a4Rotated(90).displaySize, Size(842, 595));
      expect(_a4Rotated(180).displaySize, Size(595, 842));
      expect(_a4Rotated(270).displaySize, Size(842, 595));
    });

    test('a non-positive media box is rejected by Rect validation', () {
      // `PageGeometry` delegates box validation to `Rect`, so the throw happens
      // while constructing the rectangle, before the geometry constructor
      // runs. This case is pinned as rectangle validation, not as PageGeometry
      // validation.
      expect(() => Rect.fromLTWH(0, 0, 0, 842), throwsArgumentError);
      expect(
        () => PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 0, 842)),
        throwsArgumentError,
      );
    });

    test('round-trips media box, crop box, and rotation canonically', () {
      final PageGeometry geometry = PageGeometry(
        mediaBox: Rect.fromLTWH(0, 0, 600, 800),
        cropBox: Rect.fromLTWH(10, 20, 300, 400),
        rotation: 90,
      );
      final String first = canonicalJsonEncode(geometry.toJson());
      final Map<String, Object?> decoded =
          (jsonDecode(first) as Map<String, dynamic>).cast<String, Object?>();
      final PageGeometry reopened = PageGeometry.fromJson(decoded);

      expect(reopened, geometry);
      expect(canonicalJsonEncode(reopened.toJson()), first);
      expect(first, contains('"rotation":90'));
      expect(first, contains('"mediaBox"'));
      expect(first, contains('"cropBox"'));
    });

    test('rejects an invalid persisted rotation or box', () {
      expect(
        () => PageGeometry.fromJson(<String, Object?>{
          'mediaBox': <String, Object?>{
            'x': 0.0,
            'y': 0.0,
            'width': 595.0,
            'height': 842.0,
          },
          'rotation': 45,
        }),
        throwsFormatException,
      );
      expect(
        () => PageGeometry.fromJson(<String, Object?>{
          'mediaBox': <String, Object?>{
            'x': 0.0,
            'y': 0.0,
            'width': 595.0,
            'height': 842.0,
          },
          'rotation': 0.5,
        }),
        throwsFormatException,
      );
    });
  });

  group('canonical-JSON round trip of the imported source (FR-004)', () {
    test('survives a save and reopen byte-identically', () {
      final SourceFileRef source = _source(
        pageCount: 3,
        importedAt: DateTime.utc(2026, 11, 16, 9, 30, 15, 123),
      );

      final String saved = canonicalJsonEncode(source.toJson());
      final Map<String, Object?> reopenedJson =
          (jsonDecode(saved) as Map<String, dynamic>).cast<String, Object?>();
      final SourceFileRef reopened = SourceFileRef.fromJson(reopenedJson);

      expect(reopened, source);
      expect(canonicalJsonEncode(reopened.toJson()), saved);
      expect(
        canonicalJsonBytes(reopened.toJson()),
        orderedEquals(canonicalJsonBytes(source.toJson())),
      );
      // The identity of the encrypted source is unchanged by the round trip.
      expect(reopened.id, source.id);
      expect(reopened.sha256, source.sha256);
      expect(reopened.sizeBytes, source.sizeBytes);
      expect(reopened.pageCount, source.pageCount);
      expect(reopened.importedAt, source.importedAt);
      expect(reopened.integrity, source.integrity);
      expect(reopened.originalName, source.originalName);
    });

    test('retains unknown same-schema fields across the round trip', () {
      final SourceFileRef source = _source(
        unknownFields: <String, Object?>{'x-note': 'keep', 'x-count': 2},
      );

      final String saved = canonicalJsonEncode(source.toJson());
      expect(saved, contains('"x-note":"keep"'));
      final Map<String, Object?> reopenedJson =
          (jsonDecode(saved) as Map<String, dynamic>).cast<String, Object?>();
      final SourceFileRef reopened = SourceFileRef.fromJson(reopenedJson);

      expect(reopened, source);
      expect(reopened.toJson()['x-note'], 'keep');
      expect(reopened.toJson()['x-count'], 2);
      expect(canonicalJsonEncode(reopened.toJson()), saved);
    });

    test('a returned JSON map cannot mutate the reference', () {
      final SourceFileRef source = _source();

      final Map<String, Object?> first = source.toJson();
      first['originalName'] = 'changed.pdf';
      first['sha256'] = _otherSha256;

      expect(source.originalName, 'formular.pdf');
      expect(source.sha256, _sha256);
      expect(source.toJson()['originalName'], 'formular.pdf');
      expect(source.toJson()['sha256'], _sha256);
    });
  });
}
