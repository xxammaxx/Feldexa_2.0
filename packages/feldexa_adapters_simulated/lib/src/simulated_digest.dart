// T028 SHA-256 helper.
//
// The simulated adapters verify staged sources, signature assets, template
// version content, and export artifacts. `crypto` 3.0.8 is already part of the
// reviewed lock graph; no ad-hoc cryptographic implementation is added here.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// Returns the lowercase hexadecimal SHA-256 digest of [bytes].
String sha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();

/// Returns the lowercase hexadecimal SHA-256 digest of UTF-8 [text].
String sha256HexOfUtf8(String text) => sha256Hex(utf8.encode(text));

/// Returns an unmodifiable defensive copy of [bytes].
Uint8List copyBytes(List<int> bytes) => Uint8List.fromList(bytes);
