// Dependency-free hashing and encryption helpers for the T009 synthetic
// fixture generator.
//
// SHA-256 follows the same public-domain algorithm shape used by the T007
// font-metrics tool so `dart run tools/...` needs no package resolution.
// MD5 and RC4 are implemented only to emit a genuine 40-bit Standard Security
// Handler (V1/R2) PDF for the `IMP-001` protected-import fixture. They are
// never used for product storage or transport.

import 'dart:typed_data';

const List<int> _sha256K = <int>[
  0x428a2f98,
  0x71374491,
  0xb5c0fbcf,
  0xe9b5dba5,
  0x3956c25b,
  0x59f111f1,
  0x923f82a4,
  0xab1c5ed5,
  0xd807aa98,
  0x12835b01,
  0x243185be,
  0x550c7dc3,
  0x72be5d74,
  0x80deb1fe,
  0x9bdc06a7,
  0xc19bf174,
  0xe49b69c1,
  0xefbe4786,
  0x0fc19dc6,
  0x240ca1cc,
  0x2de92c6f,
  0x4a7484aa,
  0x5cb0a9dc,
  0x76f988da,
  0x983e5152,
  0xa831c66d,
  0xb00327c8,
  0xbf597fc7,
  0xc6e00bf3,
  0xd5a79147,
  0x06ca6351,
  0x14292967,
  0x27b70a85,
  0x2e1b2138,
  0x4d2c6dfc,
  0x53380d13,
  0x650a7354,
  0x766a0abb,
  0x81c2c92e,
  0x92722c85,
  0xa2bfe8a1,
  0xa81a664b,
  0xc24b8b70,
  0xc76c51a3,
  0xd192e819,
  0xd6990624,
  0xf40e3585,
  0x106aa070,
  0x19a4c116,
  0x1e376c08,
  0x2748774c,
  0x34b0bcb5,
  0x391c0cb3,
  0x4ed8aa4a,
  0x5b9cca4f,
  0x682e6ff3,
  0x748f82ee,
  0x78a5636f,
  0x84c87814,
  0x8cc70208,
  0x90befffa,
  0xa4506ceb,
  0xbef9a3f7,
  0xc67178f2,
];

int _rotr(int value, int count) {
  return ((value >> count) | (value << (32 - count))) & 0xFFFFFFFF;
}

/// Lowercase hexadecimal SHA-256 of [input].
String sha256Hex(List<int> input) {
  final int paddedLength = ((input.length + 9 + 63) ~/ 64) * 64;
  final Uint8List data = Uint8List(paddedLength);
  data.setRange(0, input.length, input);
  data[input.length] = 0x80;
  int bitLength = input.length * 8;
  for (int index = 0; index < 8; index++) {
    data[paddedLength - 1 - index] = bitLength & 0xFF;
    bitLength >>= 8;
  }

  int h0 = 0x6a09e667;
  int h1 = 0xbb67ae85;
  int h2 = 0x3c6ef372;
  int h3 = 0xa54ff53a;
  int h4 = 0x510e527f;
  int h5 = 0x9b05688c;
  int h6 = 0x1f83d9ab;
  int h7 = 0x5be0cd19;
  final Uint32List schedule = Uint32List(64);

  for (int block = 0; block < paddedLength; block += 64) {
    for (int index = 0; index < 16; index++) {
      final int base = block + index * 4;
      schedule[index] =
          (data[base] << 24) |
          (data[base + 1] << 16) |
          (data[base + 2] << 8) |
          data[base + 3];
    }
    for (int index = 16; index < 64; index++) {
      final int s0 =
          _rotr(schedule[index - 15], 7) ^
          _rotr(schedule[index - 15], 18) ^
          (schedule[index - 15] >> 3);
      final int s1 =
          _rotr(schedule[index - 2], 17) ^
          _rotr(schedule[index - 2], 19) ^
          (schedule[index - 2] >> 10);
      schedule[index] =
          (schedule[index - 16] + s0 + schedule[index - 7] + s1) & 0xFFFFFFFF;
    }

    int a = h0;
    int b = h1;
    int c = h2;
    int d = h3;
    int e = h4;
    int f = h5;
    int g = h6;
    int h = h7;
    for (int index = 0; index < 64; index++) {
      final int sum1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final int choose = (e & f) ^ ((~e & 0xFFFFFFFF) & g);
      final int temp1 =
          (h + sum1 + choose + _sha256K[index] + schedule[index]) & 0xFFFFFFFF;
      final int sum0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final int majority = (a & b) ^ (a & c) ^ (b & c);
      final int temp2 = (sum0 + majority) & 0xFFFFFFFF;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xFFFFFFFF;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xFFFFFFFF;
    }

    h0 = (h0 + a) & 0xFFFFFFFF;
    h1 = (h1 + b) & 0xFFFFFFFF;
    h2 = (h2 + c) & 0xFFFFFFFF;
    h3 = (h3 + d) & 0xFFFFFFFF;
    h4 = (h4 + e) & 0xFFFFFFFF;
    h5 = (h5 + f) & 0xFFFFFFFF;
    h6 = (h6 + g) & 0xFFFFFFFF;
    h7 = (h7 + h) & 0xFFFFFFFF;
  }

  final Uint8List digest = Uint8List(32);
  final List<int> words = <int>[h0, h1, h2, h3, h4, h5, h6, h7];
  for (int index = 0; index < 8; index++) {
    final int word = words[index];
    digest[index * 4] = (word >> 24) & 0xFF;
    digest[index * 4 + 1] = (word >> 16) & 0xFF;
    digest[index * 4 + 2] = (word >> 8) & 0xFF;
    digest[index * 4 + 3] = word & 0xFF;
  }
  return _hex(digest);
}

/// Lowercase hexadecimal rendering of [bytes].
String _hex(List<int> bytes) {
  final StringBuffer buffer = StringBuffer();
  for (final int byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

int _rotl(int value, int count) {
  return ((value << count) | (value >> (32 - count))) & 0xFFFFFFFF;
}

const List<int> _md5Shift = <int>[
  7,
  12,
  17,
  22,
  7,
  12,
  17,
  22,
  7,
  12,
  17,
  22,
  7,
  12,
  17,
  22,
  5,
  9,
  14,
  20,
  5,
  9,
  14,
  20,
  5,
  9,
  14,
  20,
  5,
  9,
  14,
  20,
  4,
  11,
  16,
  23,
  4,
  11,
  16,
  23,
  4,
  11,
  16,
  23,
  4,
  11,
  16,
  23,
  6,
  10,
  15,
  21,
  6,
  10,
  15,
  21,
  6,
  10,
  15,
  21,
  6,
  10,
  15,
  21,
];

const List<int> _md5K = <int>[
  0xd76aa478,
  0xe8c7b756,
  0x242070db,
  0xc1bdceee,
  0xf57c0faf,
  0x4787c62a,
  0xa8304613,
  0xfd469501,
  0x698098d8,
  0x8b44f7af,
  0xffff5bb1,
  0x895cd7be,
  0x6b901122,
  0xfd987193,
  0xa679438e,
  0x49b40821,
  0xf61e2562,
  0xc040b340,
  0x265e5a51,
  0xe9b6c7aa,
  0xd62f105d,
  0x02441453,
  0xd8a1e681,
  0xe7d3fbc8,
  0x21e1cde6,
  0xc33707d6,
  0xf4d50d87,
  0x455a14ed,
  0xa9e3e905,
  0xfcefa3f8,
  0x676f02d9,
  0x8d2a4c8a,
  0xfffa3942,
  0x8771f681,
  0x6d9d6122,
  0xfde5380c,
  0xa4beea44,
  0x4bdecfa9,
  0xf6bb4b60,
  0xbebfbc70,
  0x289b7ec6,
  0xeaa127fa,
  0xd4ef3085,
  0x04881d05,
  0xd9d4d039,
  0xe6db99e5,
  0x1fa27cf8,
  0xc4ac5665,
  0xf4292244,
  0x432aff97,
  0xab9423a7,
  0xfc93a039,
  0x655b59c3,
  0x8f0ccc92,
  0xffeff47d,
  0x85845dd1,
  0x6fa87e4f,
  0xfe2ce6e0,
  0xa3014314,
  0x4e0811a1,
  0xf7537e82,
  0xbd3af235,
  0x2ad7d2bb,
  0xeb86d391,
];

/// Raw 16-byte MD5 digest of [input].
///
/// Used only by the PDF Standard Security Handler key derivation; it is not a
/// content-integrity primitive for product data.
List<int> md5Bytes(List<int> input) {
  final List<int> message = <int>[...input];
  final int bitLength = input.length * 8;
  message.add(0x80);
  while (message.length % 64 != 56) {
    message.add(0);
  }
  for (int index = 0; index < 8; index++) {
    message.add((bitLength >> (8 * index)) & 0xFF);
  }

  int a0 = 0x67452301;
  int b0 = 0xefcdab89;
  int c0 = 0x98badcfe;
  int d0 = 0x10325476;

  for (int block = 0; block < message.length; block += 64) {
    final List<int> words = List<int>.filled(16, 0);
    for (int index = 0; index < 16; index++) {
      final int base = block + index * 4;
      words[index] =
          message[base] |
          (message[base + 1] << 8) |
          (message[base + 2] << 16) |
          (message[base + 3] << 24);
    }
    int a = a0;
    int b = b0;
    int c = c0;
    int d = d0;
    for (int index = 0; index < 64; index++) {
      int f;
      int g;
      if (index < 16) {
        f = (b & c) | ((~b & 0xFFFFFFFF) & d);
        g = index;
      } else if (index < 32) {
        f = (d & b) | ((~d & 0xFFFFFFFF) & c);
        g = (5 * index + 1) % 16;
      } else if (index < 48) {
        f = b ^ c ^ d;
        g = (3 * index + 5) % 16;
      } else {
        f = c ^ (b | (~d & 0xFFFFFFFF));
        g = (7 * index) % 16;
      }
      f = (f + a + _md5K[index] + words[g]) & 0xFFFFFFFF;
      a = d;
      d = c;
      c = b;
      b = (b + _rotl(f, _md5Shift[index])) & 0xFFFFFFFF;
    }
    a0 = (a0 + a) & 0xFFFFFFFF;
    b0 = (b0 + b) & 0xFFFFFFFF;
    c0 = (c0 + c) & 0xFFFFFFFF;
    d0 = (d0 + d) & 0xFFFFFFFF;
  }

  final List<int> digest = List<int>.filled(16, 0);
  final List<int> words = <int>[a0, b0, c0, d0];
  for (int index = 0; index < 4; index++) {
    final int word = words[index];
    digest[index * 4] = word & 0xFF;
    digest[index * 4 + 1] = (word >> 8) & 0xFF;
    digest[index * 4 + 2] = (word >> 16) & 0xFF;
    digest[index * 4 + 3] = (word >> 24) & 0xFF;
  }
  return digest;
}

/// RC4 stream cipher (legacy; only for the V1/R2 fixture).
List<int> rc4(List<int> key, List<int> data) {
  if (key.isEmpty) {
    throw ArgumentError('RC4 key must not be empty');
  }
  final List<int> state = List<int>.generate(256, (int index) => index);
  int j = 0;
  for (int index = 0; index < 256; index++) {
    j = (j + state[index] + key[index % key.length]) & 0xFF;
    final int swap = state[index];
    state[index] = state[j];
    state[j] = swap;
  }
  final List<int> output = List<int>.filled(data.length, 0);
  int i = 0;
  j = 0;
  for (int index = 0; index < data.length; index++) {
    i = (i + 1) & 0xFF;
    j = (j + state[i]) & 0xFF;
    final int swap = state[i];
    state[i] = state[j];
    state[j] = swap;
    output[index] = data[index] ^ state[(state[i] + state[j]) & 0xFF];
  }
  return output;
}

/// PDF Standard Security Handler, revision 2 (40-bit RC4).
///
/// The caller supplies both the owner and user passwords. The T009 fixture
/// uses a non-empty user password (`feldexa-user`) and a fixed owner password
/// (`feldexa-owner`), so a genuine PDF reader rejects an empty or wrong user
/// password and opens the content only with the documented password. `/Encrypt`
/// remains present, which is exactly the shape the Android preflight must
/// reject for `IMP-001`.
class PdfEncryption {
  PdfEncryption({
    required String ownerPassword,
    required String userPassword,
    required List<int> documentId,
  }) : _documentId = List<int>.unmodifiable(documentId) {
    final List<int> paddedOwner = _pad(ownerPassword);
    final List<int> paddedUser = _pad(userPassword);
    final List<int> ownerKey = md5Bytes(paddedOwner).sublist(0, 5);
    _ownerEntry = List<int>.unmodifiable(rc4(ownerKey, paddedUser));

    final List<int> permissionBytes = <int>[0xD4, 0xFF, 0xFF, 0xFF];
    final List<int> keyMaterial = <int>[
      ...paddedUser,
      ..._ownerEntry,
      ...permissionBytes,
      ..._documentId,
    ];
    _fileKey = List<int>.unmodifiable(md5Bytes(keyMaterial).sublist(0, 5));
    // Algorithm 4 (R2): /U is RC4(fileKey, the fixed 32-byte padding), not
    // the padded user password. Using paddedUser happened to work only for an
    // empty user password because padding('') equals the fixed padding.
    _userEntry = List<int>.unmodifiable(rc4(_fileKey, _padding));
  }

  static const List<int> _padding = <int>[
    0x28,
    0xBF,
    0x4E,
    0x5E,
    0x4E,
    0x75,
    0x8A,
    0x41,
    0x64,
    0x00,
    0x4E,
    0x56,
    0xFF,
    0xFA,
    0x01,
    0x08,
    0x2E,
    0x2E,
    0x00,
    0xB6,
    0xD0,
    0x68,
    0x3E,
    0x80,
    0x2F,
    0x0C,
    0xA9,
    0xFE,
    0x64,
    0x53,
    0x69,
    0x7A,
  ];

  final List<int> _documentId;
  late final List<int> _ownerEntry;
  late final List<int> _userEntry;
  late final List<int> _fileKey;

  /// The fixed `/P` value written into the encryption dictionary.
  static const int permissions = -44;

  /// PDF `/O` value as uppercase hexadecimal.
  String get ownerEntryHex => _hexUpper(_ownerEntry);

  /// PDF `/U` value as uppercase hexadecimal.
  String get userEntryHex => _hexUpper(_userEntry);

  /// Document ID repeated in the trailer as uppercase hexadecimal.
  String get documentIdHex => _hexUpper(_documentId);

  List<int> _objectKey(int objectNumber, int generation) {
    final List<int> material = <int>[
      ..._fileKey,
      objectNumber & 0xFF,
      (objectNumber >> 8) & 0xFF,
      (objectNumber >> 16) & 0xFF,
      generation & 0xFF,
      (generation >> 8) & 0xFF,
    ];
    return md5Bytes(material).sublist(0, 10);
  }

  /// Encrypts one stream payload with the per-object RC4 key.
  List<int> encryptStream(int objectNumber, int generation, List<int> data) {
    return rc4(_objectKey(objectNumber, generation), data);
  }

  /// Encrypts one PDF string payload (none are emitted by this generator).
  List<int> encryptString(int objectNumber, int generation, List<int> data) {
    return encryptStream(objectNumber, generation, data);
  }

  static List<int> _pad(String password) {
    final List<int> bytes = <int>[];
    for (final int byte in password.codeUnits) {
      if (byte > 0xFF) {
        throw ArgumentError('PDF passwords must be Latin-1');
      }
      bytes.add(byte);
    }
    final List<int> padded = List<int>.filled(32, 0);
    for (int index = 0; index < 32; index++) {
      padded[index] = index < bytes.length
          ? bytes[index]
          : _padding[index - bytes.length];
    }
    return padded;
  }

  static String _hexUpper(List<int> bytes) {
    final StringBuffer buffer = StringBuffer();
    for (final int byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return buffer.toString();
  }
}
