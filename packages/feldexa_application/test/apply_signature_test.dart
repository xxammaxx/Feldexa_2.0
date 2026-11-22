// T086A `applySignature` + `SignatureAsset` unit tests (issue #269).
//
// Evidence class: NONE. These are host-VM unit tests over the pure application
// command. They construct no platform channel, open no document, touch no
// store, and make no Android, device, or visual claim.
//
// They prove:
//   * the asset validates the PNG stream, the positive integer size, the
//     1024 px long-edge bound, and copies the bytes so caller mutation cannot
//     change an asset a revision already references;
//   * the SHA-256 is the real FIPS 180-4 digest of exactly those bytes, pinned
//     here against digests computed independently of this implementation (and
//     cross-checked against `package:crypto` in the app host suite);
//   * one bound revision carries the matching `SignatureValue` and
//     `SignatureMark` for exactly one field and page, with the field rectangle
//     and the captured UTC instant;
//   * pages, suggestions, the other fields, field order, other values and
//     signatures, verification, template origin, and unknown JSON extensions
//     are preserved;
//   * the command is document- and field-local: two independent revisions and
//     two fields never share ink, and nothing is cached between calls;
//   * a missing field, a non-signature field, a non-UTC instant, and an
//     invalid asset id are content-free `ArgumentError`s that leave the input
//     snapshot untouched.

@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:feldexa_application/src/review/apply_signature.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:flutter_test/flutter_test.dart';

const String _fieldSignature = '66666666-6666-4666-8666-666666666666';
const String _fieldOtherSignature = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const String _fieldText = '11111111-1111-4111-8111-111111111111';
const String _assetId = '77777777-7777-4777-8777-777777777777';
const String _otherAssetId = '88888888-8888-4888-8888-888888888888';
const String _templateId = '99999999-9999-4999-8999-999999999999';
const String _templateVersionId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
final String _oldSha256 = List<String>.filled(64, 'a').join();
final DateTime _initialTime = DateTime.utc(2026, 11, 20, 8);
final DateTime _capturedAt = DateTime.utc(2026, 11, 22, 9, 15);

/// A minimal, valid 1 × 1 RGBA PNG (70 bytes).
final Uint8List _tinyPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, //
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0xda, 0x63, 0x60, 0x60, 0x60, 0xf8, //
  0x0f, 0x00, 0x01, 0x04, 0x01, 0x00, 0x80, 0xbb, 0xd1, 0x5b, 0x00, 0x00, //
  0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

/// Independent SHA-256 of [_tinyPng] (`hashlib.sha256`).
const String _tinyPngSha256 =
    'dc5687b50f70cb95379bfced5a0eae768dd4382cd6b393ee77d65bbdd6373fbf';

/// Independent digests of the padding-shape fixtures below.
const String _twelveByteSha256 =
    '2ab12648bdc4e14426d3110f95e7e6e01413c6921d3ecb2dd9af0f78867fc6e9';
const String _fiftySixByteSha256 =
    '96d063502772b924c4a7a1719db18ce5312fe021399c15b4c15e589cd76f32b4';
const String _sixtyFourByteSha256 =
    '1dc91e14ceb0c219f894ef6c8c1ec21f57df22bfbb8281e3f4d76f8ac7dc5b01';
const String _oneHundredNineteenByteSha256 =
    '6fdce0a73dccd1e7d4bf03a6bfae51525cd1f4051583aed25e3f88301bb894c2';

const List<int> _pngMagic = <int>[137, 80, 78, 71, 13, 10, 26, 10];

Rect _rect(double top) => Rect.fromLTWH(20, top, 80, 16);

ConfirmedField _field(String id, FieldType type, int order, double top) {
  return ConfirmedField(
    id: id,
    pageIndex: 0,
    rect: _rect(top),
    type: type,
    provenance: Provenance.user,
    label: 'Feld $order',
    order: order,
    createdAt: _initialTime,
    updatedAt: _initialTime,
  );
}

RevisionContent _baseContent() {
  final List<ConfirmedField> fields = <ConfirmedField>[
    _field(_fieldText, FieldType.text, 0, 20),
    _field(_fieldSignature, FieldType.signature, 1, 40),
    _field(_fieldOtherSignature, FieldType.signature, 2, 60),
  ];
  return RevisionContent(
    pages: <Page>[
      Page(
        index: 0,
        geometry: PageGeometry(mediaBox: Rect.fromLTWH(0, 0, 200, 200)),
      ),
    ],
    suggestions: <FieldSuggestion>[
      FieldSuggestion(
        id: 's_p0_0001',
        pageIndex: 0,
        rect: _rect(140),
        proposedType: FieldType.text,
        confidence: 0.8,
        labelText: 'Hinweis',
        evidence: SuggestionEvidence(
          cues: const <SuggestionCue>[SuggestionCue.underline],
          ocrUsed: false,
        ),
      ),
    ],
    fields: fields,
    fieldOrder: <String>[for (final ConfirmedField field in fields) field.id],
    values: <String, FieldValue>{
      _fieldText: TextValue(text: 'Alt', lastEditedAt: _initialTime),
      // The other signature field is already signed: applying a new signature
      // to one field must not touch it.
      _fieldOtherSignature: SignatureValue(
        signatureAssetId: _otherAssetId,
        lastEditedAt: _initialTime,
      ),
    },
    signatures: <String, SignatureMark>{
      _fieldOtherSignature: SignatureMark(
        assetId: _otherAssetId,
        fieldId: _fieldOtherSignature,
        pageIndex: 0,
        rect: _rect(60),
        widthPx: 100,
        heightPx: 40,
        capturedAt: _initialTime,
        sha256: _oldSha256,
      ),
    },
    verification: <String, FieldVerification>{
      _fieldText: FieldVerification(
        state: FieldVerificationState.corrected,
        reviewedAt: _initialTime,
        warnings: const <WarningCode>[WarningCode.overflow],
      ),
    },
    templateOrigin: TemplateOrigin(
      templateId: _templateId,
      templateVersionId: _templateVersionId,
      templateVersionNumber: 3,
    ),
    unknownFields: <String, Object?>{
      'laterField': <String, Object?>{'enabled': true},
    },
  );
}

void main() {
  group('SignatureAsset', () {
    test('derives the FIPS 180-4 digest of exactly the supplied bytes', () {
      final SignatureAsset asset = SignatureAsset.fromPng(
        bytes: _tinyPng,
        widthPx: 1,
        heightPx: 1,
      );

      expect(asset.sha256, _tinyPngSha256);
      expect(asset.widthPx, 1);
      expect(asset.heightPx, 1);
      expect(asset.bytes, orderedEquals(_tinyPng));
      expect(asset.toString(), isNot(contains(_tinyPngSha256)));
    });

    test('hashes every SHA-256 padding shape correctly', () {
      final Map<Uint8List, String> fixtures = <Uint8List, String>{
        Uint8List.fromList(<int>[..._pngMagic, 0x61, 0x62, 0x63, 0x64]):
            _twelveByteSha256,
        Uint8List.fromList(<int>[
          ..._pngMagic,
          for (int index = 0; index < 48; index++) index,
        ]): _fiftySixByteSha256,
        Uint8List.fromList(<int>[
          ..._pngMagic,
          for (int index = 0; index < 56; index++) index,
        ]): _sixtyFourByteSha256,
        Uint8List.fromList(<int>[
          ..._pngMagic,
          for (int index = 0; index < 111; index++) (index * 7) % 256,
        ]): _oneHundredNineteenByteSha256,
      };

      for (final MapEntry<Uint8List, String> entry in fixtures.entries) {
        final SignatureAsset asset = SignatureAsset.fromPng(
          bytes: entry.key,
          widthPx: 16,
          heightPx: 16,
        );
        expect(asset.sha256, entry.value);
      }
    });

    test('copies the bytes so caller mutation cannot change the asset', () {
      final Uint8List source = Uint8List.fromList(_tinyPng);
      final SignatureAsset asset = SignatureAsset.fromPng(
        bytes: source,
        widthPx: 1,
        heightPx: 1,
      );
      final String digest = asset.sha256;
      source[source.length - 1] = 0x00;

      expect(asset.bytes, orderedEquals(_tinyPng));
      expect(asset.sha256, digest);
    });

    test('rejects empty, non-PNG, zero-sized, and oversized images', () {
      expect(
        () => SignatureAsset.fromPng(
          bytes: Uint8List(0),
          widthPx: 1,
          heightPx: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => SignatureAsset.fromPng(
          bytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9]),
          widthPx: 1,
          heightPx: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => SignatureAsset.fromPng(
          bytes: Uint8List.fromList(<int>[..._pngMagic, 0x00]),
          widthPx: 0,
          heightPx: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => SignatureAsset.fromPng(
          bytes: Uint8List.fromList(<int>[..._pngMagic, 0x00]),
          widthPx: 1,
          heightPx: signatureAssetMaxEdgePx + 1,
        ),
        throwsArgumentError,
      );
      // The documented upper bound itself is accepted.
      final SignatureAsset bound = SignatureAsset.fromPng(
        bytes: Uint8List.fromList(<int>[..._pngMagic, 0x00]),
        widthPx: signatureAssetMaxEdgePx,
        heightPx: 1,
      );
      expect(bound.widthPx, signatureAssetMaxEdgePx);
    });
  });

  group('applySignature', () {
    test('binds one asset to one field, page, and rectangle', () {
      final RevisionContent base = _baseContent();
      final SignatureAsset asset = SignatureAsset.fromPng(
        bytes: _tinyPng,
        widthPx: 220,
        heightPx: 80,
      );

      final SignatureChange change = applySignature(
        base,
        _fieldSignature,
        assetId: _assetId,
        asset: asset,
        capturedAt: _capturedAt,
      );

      final ConfirmedField field = base.fields.firstWhere(
        (ConfirmedField candidate) => candidate.id == _fieldSignature,
      );
      final SignatureValue value = change.value;
      expect(value.signatureAssetId, _assetId);
      expect(value.lastEditedAt, _capturedAt);
      final SignatureMark mark = change.mark;
      expect(mark.assetId, _assetId);
      expect(mark.fieldId, _fieldSignature);
      expect(mark.pageIndex, field.pageIndex);
      expect(mark.rect, field.rect);
      expect(mark.widthPx, 220);
      expect(mark.heightPx, 80);
      expect(mark.capturedAt, _capturedAt);
      expect(mark.sha256, asset.sha256);
      expect(mark.describesField(field), isTrue);

      // The single returned snapshot is a valid revision content whose value
      // and mark name the same asset, so neither can exist without the other.
      expect(change.content.values[_fieldSignature], same(value));
      expect(change.content.signatures[_fieldSignature], same(mark));
      expect(change.assetId, _assetId);
      expect(change.fieldId, _fieldSignature);
      expect(change.previousValue, isNull);
      expect(change.previousMark, isNull);
      expect(change.previousContent, same(base));
    });

    test('preserves every other revision member and the input snapshot', () {
      final RevisionContent base = _baseContent();
      final SignatureAsset asset = SignatureAsset.fromPng(
        bytes: _tinyPng,
        widthPx: 32,
        heightPx: 16,
      );

      final SignatureChange change = applySignature(
        base,
        _fieldSignature,
        assetId: _assetId,
        asset: asset,
        capturedAt: _capturedAt,
      );
      final RevisionContent next = change.content;

      expect(next.pages, equals(base.pages));
      expect(next.suggestions, equals(base.suggestions));
      expect(next.fields, equals(base.fields));
      expect(next.fieldOrder, equals(base.fieldOrder));
      expect(next.verification, equals(base.verification));
      expect(next.templateOrigin, base.templateOrigin);
      expect(next.unknownFields, equals(base.unknownFields));
      expect(
        next.signatures[_fieldOtherSignature],
        same(base.signatures[_fieldOtherSignature]),
      );
      expect(
        next.values[_fieldOtherSignature],
        same(base.values[_fieldOtherSignature]),
      );
      expect(next.values[_fieldText], same(base.values[_fieldText]));
      expect(next.values.length, base.values.length + 1);
      expect(next.signatures.length, base.signatures.length + 1);
      // The input snapshot is untouched.
      expect(base.values.containsKey(_fieldSignature), isFalse);
      expect(base.signatures.containsKey(_fieldSignature), isFalse);
    });

    test('replaces an existing signature of the same field', () {
      final RevisionContent base = _baseContent();
      final SignatureAsset asset = SignatureAsset.fromPng(
        bytes: _tinyPng,
        widthPx: 8,
        heightPx: 8,
      );
      final SignatureChange first = applySignature(
        base,
        _fieldOtherSignature,
        assetId: _assetId,
        asset: asset,
        capturedAt: _capturedAt,
      );
      final SignatureChange second = applySignature(
        first.content,
        _fieldOtherSignature,
        assetId: _otherAssetId,
        asset: asset,
        capturedAt: _capturedAt.add(const Duration(minutes: 5)),
      );

      expect(first.previousMark?.assetId, _otherAssetId);
      expect(second.previousMark?.assetId, _assetId);
      expect(second.content.signatures, hasLength(base.signatures.length));
      expect(
        second.content.signatures[_fieldOtherSignature]!.assetId,
        _otherAssetId,
      );
      expect(
        (second.content.values[_fieldOtherSignature]! as SignatureValue)
            .signatureAssetId,
        _otherAssetId,
      );
    });

    test('keeps two documents and fields independent (no global ink)', () {
      final RevisionContent base = _baseContent();
      final SignatureAsset alpha = SignatureAsset.fromPng(
        bytes: _tinyPng,
        widthPx: 10,
        heightPx: 10,
      );
      final SignatureAsset beta = SignatureAsset.fromPng(
        bytes: Uint8List.fromList(<int>[..._pngMagic, 0x01]),
        widthPx: 20,
        heightPx: 20,
      );

      final SignatureChange first = applySignature(
        base,
        _fieldSignature,
        assetId: _assetId,
        asset: alpha,
        capturedAt: _capturedAt,
      );
      final SignatureChange second = applySignature(
        base,
        _fieldOtherSignature,
        assetId: _otherAssetId,
        asset: beta,
        capturedAt: _capturedAt,
      );

      expect(first.mark.sha256, alpha.sha256);
      expect(second.mark.sha256, beta.sha256);
      expect(first.mark.sha256, isNot(second.mark.sha256));
      expect(first.content.signatures.containsKey(_fieldOtherSignature), isTrue);
      // The first receipt still describes only its own field and asset.
      expect(first.content.signatures[_fieldSignature]!.assetId, _assetId);
      expect(
        (first.content.values[_fieldSignature]! as SignatureValue)
            .signatureAssetId,
        _assetId,
      );
      // A third application on the untouched base yields the same result.
      final SignatureChange again = applySignature(
        base,
        _fieldSignature,
        assetId: _assetId,
        asset: alpha,
        capturedAt: _capturedAt,
      );
      expect(
        canonicalJsonEncode(again.content.toJson()),
        canonicalJsonEncode(first.content.toJson()),
      );
    });

    test('rejects a missing field, a wrong type, and a non-UTC instant', () {
      final RevisionContent base = _baseContent();
      final SignatureAsset asset = SignatureAsset.fromPng(
        bytes: _tinyPng,
        widthPx: 4,
        heightPx: 4,
      );

      expect(
        () => applySignature(
          base,
          _assetId,
          assetId: _assetId,
          asset: asset,
          capturedAt: _capturedAt,
        ),
        throwsArgumentError,
      );
      expect(
        () => applySignature(
          base,
          _fieldText,
          assetId: _assetId,
          asset: asset,
          capturedAt: _capturedAt,
        ),
        throwsArgumentError,
      );
      expect(
        () => applySignature(
          base,
          _fieldSignature,
          assetId: _assetId,
          asset: asset,
          capturedAt: DateTime(2026, 11, 22, 9, 15),
        ),
        throwsArgumentError,
      );
      expect(
        () => applySignature(
          base,
          _fieldSignature,
          assetId: 'not-an-asset-id',
          asset: asset,
          capturedAt: _capturedAt,
        ),
        throwsArgumentError,
      );
    });

    test('content-free errors never echo the field or asset id', () {
      final RevisionContent base = _baseContent();
      final SignatureAsset asset = SignatureAsset.fromPng(
        bytes: _tinyPng,
        widthPx: 4,
        heightPx: 4,
      );
      String message = '';
      try {
        applySignature(
          base,
          _fieldSignature,
          assetId: 'not-an-asset-id',
          asset: asset,
          capturedAt: _capturedAt,
        );
      } on ArgumentError catch (error) {
        message = error.toString();
      }
      expect(message, isNotEmpty);
      expect(message, isNot(contains(_fieldSignature)));
      expect(message, isNot(contains('not-an-asset-id')));
    });
  });
}
