// T086A signature-asset binding command (issue #269, US4).
//
// Owner: `packages/feldexa_application/lib/src/review/apply_signature.dart`
// (T086A).
//
// Normative sources:
//   * `spec.md` FR-036 (a handwritten signature belongs only to the current
//     document), FR-040 (entered values stay editable before export), FR-047
//     (only a verified revision is durable);
//   * `contracts/editor-interactions.md` §5 (the signature field opens a
//     full-screen sheet; „Übernehmen“ stores ink only for this document; no
//     reuse library and no import from files);
//   * `data-model.md` §3.5/§3.12 and the `RevisionContent` invariants — a
//     `SignatureValue` and its `SignatureMark` must name the same asset id,
//     and a mark must belong to a signature field on the same page;
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// What this file is
// -----------------
// Two pure steps that turn one captured ink snapshot into a storable signature
// asset and one revision snapshot:
//
//   1. [SignatureAsset.fromPng] validates the encoded PNG (magic, dimensions,
//      size bound), copies the bytes, and derives the SHA-256 the encrypted
//      store verifies on write and read-back;
//   2. [applySignature] binds that asset to exactly one confirmed signature
//      field of the supplied revision and returns the complete new snapshot
//      with the matching `SignatureValue` and `SignatureMark`.
//
// The command performs no I/O, reads no clock, generates no id, and mutates
// neither the revision nor any value it is given. The caller supplies the UTC
// capture instant and the asset id, calls `SecureStorePort.writeSignature`
// exactly once with [SignatureAsset.bytes]/[SignatureAsset.sha256], and
// persists the returned snapshot as one verified revision. Because the value
// and the mark are produced together, no revision can ever carry one without
// the other.
//
// Binding is per document and per field. There is no signature library, no
// cached or global ink, and no way to attach an asset that belongs to another
// document: the asset id is only meaningful inside the document aggregate that
// the caller writes, and the revision snapshot itself carries the field id and
// page index.
//
// SHA-256 note
// ------------
// The repository keeps `crypto` out of `feldexa_application` (it is a
// production dependency of the adapter packages only), and T086A may not add a
// dependency. The digest therefore uses the small, self-contained
// implementation below. It is a pure function of the bytes with no state, and
// the host tests pin it against published FIPS 180-4 vectors and against
// `package:crypto` for the exact bytes this command receives.
//
// Errors are content-free `ArgumentError`s: no id, label, page content, path,
// or signature byte is ever echoed.

import 'dart:typed_data';

import 'package:feldexa_core/feldexa_core.dart';

/// Longest allowed signature edge in pixels (`data-model.md` §3.12).
const int signatureAssetMaxEdgePx = 1024;

/// The eight bytes every PNG stream starts with.
const List<int> _pngMagic = <int>[137, 80, 78, 71, 13, 10, 26, 10];

/// One validated, immutable signature image ready for the encrypted store.
///
/// The bytes are a defensive copy, so later mutation of the caller's buffer
/// cannot change an asset that a revision already references. [sha256] is the
/// lowercase hex digest of exactly those bytes; the Android store recomputes it
/// on write and again after the read-back, so a mismatch fails closed.
final class SignatureAsset {
  /// Validates [bytes] as a PNG image of [widthPx] × [heightPx] pixels.
  ///
  /// Throws an [ArgumentError] for empty bytes, a non-PNG byte stream, a
  /// non-positive dimension, or an edge above [signatureAssetMaxEdgePx].
  factory SignatureAsset.fromPng({
    required Uint8List bytes,
    required int widthPx,
    required int heightPx,
  }) {
    if (bytes.isEmpty) {
      throw ArgumentError('the signature image must not be empty');
    }
    if (bytes.length < _pngMagic.length) {
      throw ArgumentError('the signature image must be a PNG stream');
    }
    for (int index = 0; index < _pngMagic.length; index++) {
      if (bytes[index] != _pngMagic[index]) {
        throw ArgumentError('the signature image must be a PNG stream');
      }
    }
    if (widthPx < 1 || heightPx < 1) {
      throw ArgumentError('the signature image size must be positive');
    }
    if (widthPx > signatureAssetMaxEdgePx ||
        heightPx > signatureAssetMaxEdgePx) {
      throw ArgumentError('the signature image long edge must be at most 1024');
    }
    final Uint8List copy = Uint8List.fromList(bytes);
    return SignatureAsset._(
      bytes: copy,
      sha256: _sha256Hex(copy),
      widthPx: widthPx,
      heightPx: heightPx,
    );
  }

  const SignatureAsset._({
    required this.bytes,
    required this.sha256,
    required this.widthPx,
    required this.heightPx,
  });

  /// Immutable PNG bytes of exactly this signature.
  final Uint8List bytes;

  /// Lowercase hex SHA-256 of [bytes].
  final String sha256;

  /// Image width in pixels, `1 … 1024`.
  final int widthPx;

  /// Image height in pixels, `1 … 1024`.
  final int heightPx;

  @override
  String toString() {
    // Content-free: no bytes, no digest of caller content.
    return 'SignatureAsset(widthPx: $widthPx, heightPx: $heightPx)';
  }
}

/// An immutable receipt for one applied signature asset.
///
/// [content] is the complete new revision snapshot in which the field's
/// `SignatureValue` and `SignatureMark` both name [assetId]; [previousContent]
/// is the exact input snapshot an undo can restore. [previousValue] and
/// [previousMark] are the replaced entries, or null when the field was
/// unsigned before.
final class SignatureChange {
  /// Creates a signature-change receipt.
  const SignatureChange({
    required this.content,
    required this.previousContent,
    required this.fieldId,
    required this.assetId,
    required this.mark,
    required this.value,
    required this.previousValue,
    required this.previousMark,
  });

  /// The new, fully validated revision snapshot.
  final RevisionContent content;

  /// The unchanged input snapshot.
  final RevisionContent previousContent;

  /// The id of the confirmed signature field that was signed.
  final String fieldId;

  /// UUIDv4 of the signature asset both the value and the mark reference.
  final String assetId;

  /// The stored signature mark.
  final SignatureMark mark;

  /// The stored signature value.
  final SignatureValue value;

  /// The replaced value, or null when the field had no value.
  final FieldValue? previousValue;

  /// The replaced mark, or null when the field was unsigned.
  final SignatureMark? previousMark;
}

/// Binds [asset] to one confirmed signature field of [content].
///
/// [fieldId] must name an existing confirmed field of type
/// [FieldType.signature]. [capturedAt] must be UTC and becomes both the mark's
/// capture instant and the value's edit instant. [assetId] must be a lowercase
/// UUIDv4 that the caller also uses for the store write; it is never reused
/// across documents or fields by this command.
///
/// Only `values[fieldId]` and `signatures[fieldId]` change. Pages, suggestions,
/// the other confirmed fields, field order, every other value and signature,
/// verification records, template origin, and unknown same-schema JSON fields
/// are copied unchanged. The mark's rectangle is the field's current rectangle
/// and its page index is the field's page index, so the asset can only ever
/// describe this document's field.
///
/// Throws an [ArgumentError] for a missing field, a non-signature field, a
/// non-UTC instant, or an invalid asset id. The message never contains
/// document content.
SignatureChange applySignature(
  RevisionContent content,
  String fieldId, {
  required String assetId,
  required SignatureAsset asset,
  required DateTime capturedAt,
}) {
  if (!capturedAt.isUtc) {
    throw ArgumentError('capturedAt must be UTC');
  }
  ConfirmedField? field;
  for (final ConfirmedField candidate in content.fields) {
    if (candidate.id == fieldId) {
      field = candidate;
      break;
    }
  }
  if (field == null) {
    throw ArgumentError('the field is not present in the revision');
  }
  if (field.type != FieldType.signature) {
    throw ArgumentError('the field is not a signature field');
  }
  final SignatureMark mark = SignatureMark(
    assetId: assetId,
    fieldId: fieldId,
    pageIndex: field.pageIndex,
    rect: field.rect,
    widthPx: asset.widthPx,
    heightPx: asset.heightPx,
    capturedAt: capturedAt,
    sha256: asset.sha256,
  );
  final SignatureValue value = SignatureValue(
    signatureAssetId: assetId,
    lastEditedAt: capturedAt,
  );
  final Map<String, FieldValue> values = <String, FieldValue>{
    for (final MapEntry<String, FieldValue> entry in content.values.entries)
      entry.key: entry.value,
    fieldId: value,
  };
  final Map<String, SignatureMark> signatures = <String, SignatureMark>{
    for (final MapEntry<String, SignatureMark> entry in content.signatures.entries)
      entry.key: entry.value,
    fieldId: mark,
  };
  final RevisionContent updated = RevisionContent(
    pages: content.pages,
    suggestions: content.suggestions,
    fields: content.fields,
    fieldOrder: content.fieldOrder,
    values: values,
    signatures: signatures,
    verification: content.verification,
    templateOrigin: content.templateOrigin,
    unknownFields: content.unknownFields,
  );
  return SignatureChange(
    content: updated,
    previousContent: content,
    fieldId: fieldId,
    assetId: assetId,
    mark: mark,
    value: value,
    previousValue: content.values[fieldId],
    previousMark: content.signatures[fieldId],
  );
}

/// Lowercase hex SHA-256 of [bytes] (FIPS 180-4).
///
/// Library-private on purpose: the command is the single production consumer
/// and every other hashing need in this repository is owned by an adapter that
/// already depends on `package:crypto`.
String _sha256Hex(List<int> bytes) {
  const List<int> k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  const int mask = 0xffffffff;
  int rotr(int value, int count) {
    return ((value >> count) | (value << (32 - count))) & mask;
  }

  // Padding: 0x80, zeros, and the 64-bit big-endian bit length.
  final int bitLength = bytes.length * 8;
  final int paddedLength = ((bytes.length + 9 + 63) ~/ 64) * 64;
  final Uint8List buffer = Uint8List(paddedLength);
  buffer.setRange(0, bytes.length, bytes);
  buffer[bytes.length] = 0x80;
  final ByteData lengthView = ByteData.sublistView(
    buffer,
    paddedLength - 8,
    paddedLength,
  );
  lengthView.setUint32(0, (bitLength ~/ 0x100000000) & mask);
  lengthView.setUint32(4, bitLength & mask);

  final List<int> hash = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  final List<int> schedule = List<int>.filled(64, 0);
  final ByteData words = ByteData.sublistView(buffer);

  for (int chunk = 0; chunk < paddedLength; chunk += 64) {
    for (int index = 0; index < 16; index++) {
      schedule[index] = words.getUint32(chunk + index * 4);
    }
    for (int index = 16; index < 64; index++) {
      final int s0 =
          rotr(schedule[index - 15], 7) ^
          rotr(schedule[index - 15], 18) ^
          (schedule[index - 15] >> 3);
      final int s1 =
          rotr(schedule[index - 2], 17) ^
          rotr(schedule[index - 2], 19) ^
          (schedule[index - 2] >> 10);
      schedule[index] =
          (schedule[index - 16] + s0 + schedule[index - 7] + s1) & mask;
    }
    int a = hash[0];
    int b = hash[1];
    int c = hash[2];
    int d = hash[3];
    int e = hash[4];
    int f = hash[5];
    int g = hash[6];
    int h = hash[7];
    for (int index = 0; index < 64; index++) {
      final int s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final int ch = (e & f) ^ ((~e & mask) & g);
      final int temp1 = (h + s1 + ch + k[index] + schedule[index]) & mask;
      final int s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final int maj = (a & b) ^ (a & c) ^ (b & c);
      final int temp2 = (s0 + maj) & mask;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & mask;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & mask;
    }
    hash[0] = (hash[0] + a) & mask;
    hash[1] = (hash[1] + b) & mask;
    hash[2] = (hash[2] + c) & mask;
    hash[3] = (hash[3] + d) & mask;
    hash[4] = (hash[4] + e) & mask;
    hash[5] = (hash[5] + f) & mask;
    hash[6] = (hash[6] + g) & mask;
    hash[7] = (hash[7] + h) & mask;
  }

  final StringBuffer hex = StringBuffer();
  for (final int word in hash) {
    hex.write(word.toRadixString(16).padLeft(8, '0'));
  }
  return hex.toString();
}
