// T027 shared Android MethodChannel/result-channel helpers.
//
// Normative sources:
//   * `contracts/platform-channel.md` §2.2, §2.4, §8, and §10 — envelopes,
//     start/result correlation, typed failures, and payload bounds;
//   * `contracts/ports.md` §3 — the portable exception taxonomy.
//
// The adapter package is the only place where a `PlatformException` code is
// translated into a portable `FeldexaException`. No helper logs or echoes a
// payload, title, source byte, OCR text, or path.

import 'dart:typed_data';

import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/services.dart';

/// Adapter-local failure for the catalog-only `SAVE-006` concurrency code.
///
/// `contracts/ports.md` §3 deliberately has no separate `SAVE-006` exception
/// class because the app re-reads the head and retries. A thin client still has
/// to surface the code without inventing a SAVE-003 cause, so this local type
/// carries the exact catalog code and no content.
final class AndroidConcurrentWriteException extends FeldexaException {
  AndroidConcurrentWriteException()
    : super(
        code: 'SAVE-006',
        messageKey: 'SAVE-006',
        message: 'storage.concurrentWrite',
        retryable: true,
        severity: ErrorSeverity.warning,
      );
}

/// Adapter-local failure for the catalog-only `SAVE-007` invalid-data code.
final class AndroidInvalidDataException extends FeldexaException {
  AndroidInvalidDataException()
    : super(
        code: 'SAVE-007',
        messageKey: 'SAVE-007',
        message: 'storage.invalidData',
        retryable: false,
        severity: ErrorSeverity.warning,
      );
}

/// Adapter-local failure for a user-cancelled operation (`PLT-004`).
///
/// Import cancellation keeps its dedicated `ImportCancelledException`; this
/// type covers the other asynchronous operations whose terminal result is
/// `PLT-004`.
final class AndroidOperationCancelledException extends FeldexaException {
  AndroidOperationCancelledException()
    : super(
        code: 'PLT-004',
        messageKey: 'PLT-004',
        message: 'platform.cancelled',
        retryable: true,
        severity: ErrorSeverity.info,
      );
}

/// Converts a thrown channel error into the portable taxonomy.
///
/// Unknown codes are rethrown unchanged so a future adapter cannot silently
/// turn an unclassified failure into a success or a misleading typed error.
Never throwAndroidChannelError(Object error) {
  if (error is! PlatformException) {
    throw error;
  }
  final String code = error.code;
  final String? message = error.message;
  final Map<Object?, Object?>? details = error.details is Map
      ? (error.details as Map).cast<Object?, Object?>()
      : null;
  switch (code) {
    case 'IMP-000':
      throw ImportCancelledException();
    case 'IMP-001':
      throw ImportRejectedException(
        message == 'import.unsupportedEncryption'
            ? ImportRejectionKind.unsupportedEncryption
            : ImportRejectionKind.passwordProtected,
      );
    case 'IMP-002':
      throw ImportRejectedException(
        message == 'import.rejected.truncated'
            ? ImportRejectionKind.truncated
            : ImportRejectionKind.unreadable,
      );
    case 'IMP-003':
      throw ImportRejectedException(ImportRejectionKind.missing);
    case 'IMP-004':
      throw ImportRejectedException(
        message == 'import.rejected.unsupportedStructure'
            ? ImportRejectionKind.unsupportedStructure
            : ImportRejectionKind.notPdf,
      );
    case 'IMP-005':
      throw ImportRejectedException(ImportRejectionKind.unknownReason);
    case 'IMP-007':
      throw ImportRejectedException(ImportRejectionKind.tooLarge);
    case 'SAVE-001':
      throw StorageFullException();
    case 'SAVE-002':
      throw KeyUnavailableException();
    case 'SAVE-003':
      if (message == 'save.writeFailed') {
        throw StorageWriteException();
      }
      throw CorruptDataException();
    case 'SAVE-005':
      throw SchemaTooNewException();
    case 'SAVE-006':
      throw AndroidConcurrentWriteException();
    case 'SAVE-007':
      throw AndroidInvalidDataException();
    case 'SAVE-008':
      final Object? retryable = details?['retryable'];
      throw KeystoreUnavailableException(
        retryable: retryable is bool ? retryable : true,
      );
    case 'EXP-001':
      // The channel error details carry only a count, not field ids. The
      // portable exception requires at least one opaque id; `unknown` is a
      // stable placeholder, never document content.
      throw ExportBlockedException(const <String>['unknown']);
    case 'EXP-002':
      throw ExportFailedException();
    case 'PLT-001':
      throw UnsupportedOperationException();
    case 'PLT-002':
      throw SecurityException();
    case 'PLT-004':
      throw AndroidOperationCancelledException();
    case 'REC-001':
      throw OcrUnavailableException();
    case 'PAGE-001':
      final Object? pageIndex = details?['pageIndex'];
      throw RenderException(
        pageIndex: pageIndex is int && pageIndex >= 0 ? pageIndex : 0,
      );
    default:
      throw error;
  }
}

/// Validates the `{schemaVersion, ok, data}` envelope of a synchronous method.
Map<String, Object?> androidEnvelopeData(
  Object? response, {
  required String method,
}) {
  return _stringKeyed(androidEnvelopeValue(response, method: method), method);
}

/// Validates a synchronous envelope and returns its untyped `data` value.
///
/// Binary methods (`store.readSource`, `store.readSignature`,
/// `export.readArtifact`) return bytes as `data`, not a map.
Object? androidEnvelopeValue(Object? response, {required String method}) {
  if (response is! Map ||
      response['schemaVersion'] != 1 ||
      response['ok'] != true) {
    throw FormatException('Invalid $method response envelope');
  }
  return response['data'];
}

Map<String, Object?> _stringKeyed(Object? value, String method) {
  if (value is! Map) {
    throw FormatException('Invalid $method response data');
  }
  final Map<String, Object?> result = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in value.entries) {
    final Object? key = entry.key;
    if (key is! String) {
      throw FormatException('Invalid $method response key');
    }
    result[key] = _deepValue(entry.value);
  }
  return result;
}

/// Recursively normalises codec maps and lists to `Map<String, Object?>` and
/// `List<Object?>`, which is what the canonical `fromJson` decoders require.
Object? _deepValue(Object? value) {
  if (value is Map) {
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      final Object? key = entry.key;
      if (key is! String) throw const FormatException('Invalid response key');
      result[key] = _deepValue(entry.value);
    }
    return result;
  }
  if (value is List) {
    return <Object?>[for (final Object? item in value) _deepValue(item)];
  }
  return value;
}

/// Converts a nested map value without assuming a concrete map type.
Map<String, Object?> androidMap(Object? value, String name) {
  if (value is! Map) throw FormatException('Invalid $name object');
  return _stringKeyed(value, name);
}

/// Converts a list of nested maps.
List<Map<String, Object?>> androidMapList(Object? value, String name) {
  if (value is! List) throw FormatException('Invalid $name list');
  return <Map<String, Object?>>[
    for (final Object? item in value) androidMap(item, name),
  ];
}

/// Normalises a platform binary response to [Uint8List].
///
/// Android encodes a Kotlin `ByteArray` as a typed byte list. Accepting both
/// the typed and plain list forms keeps the boundary tolerant of codec
/// versions without ever turning a failed read into fabricated bytes.
Uint8List? androidBytes(Object? value) {
  if (value is Uint8List) return value;
  if (value is List<int>) return Uint8List.fromList(value);
  if (value is ByteBuffer) return value.asUint8List();
  return null;
}

/// Returns a lowercase UUIDv4 or throws a safe format error.
String androidUuid(Object? value, String name) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(value)) {
    throw FormatException('$name must be a lowercase UUIDv4');
  }
  return value;
}

/// Returns a 64-character lowercase SHA-256 or throws a safe format error.
String androidSha256(Object? value, String name) {
  if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw FormatException('$name must be a lowercase SHA-256');
  }
  return value;
}

/// Parses a canonical UTC timestamp from a channel response.
DateTime androidUtc(Object? value, String name) {
  if (value is! String) throw FormatException('$name must be a timestamp');
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('$name must be a UTC timestamp');
  }
  return parsed;
}
