// T099 diagnostics privacy suite (FR-081, host VM, evidence class NONE).
//
// Normative sources:
//   * `spec.md` FR-081 — diagnostic information must remain on the device and
//     must exclude document content, file names, recognized text, field
//     values, and signatures;
//   * `contracts/ports.md` §2.9 — scalar fields are limited to enums, counts,
//     durations, and error codes; nested maps, lists, and bytes are dropped;
//   * `packages/feldexa_adapters_android/lib/src/android_system_clients.dart`
//     — the production `AndroidDiagnosticsClient` ring buffer.
//
// The client is pure Dart (no platform channel), so the suite runs on the
// host VM. It feeds content-like payloads a buggy or malicious caller could
// pass and inspects the retained events through the test-only `debugEvents`
// accessor. The assertions pin the exclusion duty (§2.9 whitelist), not the
// historical behavior: free strings, paths, titles, OCR text, and field
// values must be gone; enums, counts, durations, and error codes survive.

library;

import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:flutter_test/flutter_test.dart';

/// Probe enum: a compile-time, content-free scalar that must survive.
enum _Probe { retained }

void main() {
  test('descriptor declares the on-device scalar-only ring buffer', () {
    final AndroidDiagnosticsClient client = AndroidDiagnosticsClient();
    expect(client.descriptor.kind.name, 'diagnostics');
    expect(client.descriptor.isSimulated, isFalse);
    expect(
      client.descriptor.supportedFeatures,
      containsAll(<String>['on-device', 'scalar-only', 'ring-buffer']),
    );
  });

  test('nested maps, lists, and byte payloads are dropped, not stored', () {
    final AndroidDiagnosticsClient client = AndroidDiagnosticsClient();
    client.event(
      'store.saveRevision',
      scalarFields: <String, Object?>{
        // Malicious or buggy caller input: every value below is document
        // content or metadata the contract forbids in diagnostics.
        'fieldValue': <String, Object?>{'nachname': 'Mustermann'},
        'ocrLines': <String>['Familienname', 'Mustermann'],
        'signatureBytes': <int>[1, 2, 3],
      },
    );
    final Map<String, Object?> event = client.debugEvents.single;
    expect(event['code'], 'store.saveRevision');
    // Only the stable code and the timestamp survive.
    expect(event.keys, unorderedEquals(<String>['code', 'atUtc']));
  });

  test('the ring buffer is capped at its capacity', () {
    final AndroidDiagnosticsClient client = AndroidDiagnosticsClient(
      capacity: 4,
    );
    for (int i = 0; i < 10; i++) {
      client.event('probe.count', scalarFields: <String, Object?>{'n': i});
    }
    expect(client.capacity, 4);
    expect(client.debugEvents, hasLength(4));
    expect(
      client.debugEvents.map((Map<String, Object?> event) => event['n']),
      <int>[6, 7, 8, 9],
    );
  });

  test('clear() empties the on-device buffer without throwing', () async {
    final AndroidDiagnosticsClient client = AndroidDiagnosticsClient();
    client.event('probe.clear', scalarFields: <String, Object?>{'n': 1});
    expect(client.debugEvents, hasLength(1));
    await client.clear();
    expect(client.debugEvents, isEmpty);
    // A cleared buffer stays usable.
    client.event('probe.clear', scalarFields: <String, Object?>{'n': 2});
    expect(client.debugEvents, hasLength(1));
  });

  test('§2.9 whitelist discards free strings, paths, titles, and OCR text', () {
    final AndroidDiagnosticsClient client = AndroidDiagnosticsClient();
    const String path = '/data/data/de.feldexa.app/files/doc.pdf';
    const String title = 'Familienname Mustermann';
    const String ocrText = 'Familienname: Mustermann';
    const String fieldValue = 'Mustermann';
    const String signature = 'Muster';
    const String bareTitle = 'mustermann';
    client.event(
      'store.saveRevision',
      scalarFields: <String, Object?>{
        // Content that FR-081 forbids: must not be retained under any key.
        'path': path,
        'title': title,
        'ocrText': ocrText,
        'fieldValue': fieldValue,
        'signatureValue': signature,
        'bareTitle': bareTitle,
        // Non-whitelisted scalar types and nested payloads.
        'nested': <String, Object?>{'titel': title},
        'lines': <String>[ocrText],
        'bytes': <int>[1, 2, 3],
        'nothing': null,
        'flag': true,
        'ratio': 0.5,
        'negative': -1,
        // Whitelisted values that must survive.
        'probe': _Probe.retained,
        'pageCount': 2,
        'duration': const Duration(milliseconds: 12),
        'errorCode': 'SAVE-003',
        'token': 'storage.ioError',
      },
    );

    final Map<String, Object?> event = client.debugEvents.single;
    expect(
      event.keys,
      unorderedEquals(<String>[
        'code',
        'probe',
        'pageCount',
        'duration',
        'errorCode',
        'token',
        'atUtc',
      ]),
    );
    expect(event['probe'], 'retained');
    expect(event['pageCount'], 2);
    expect(event['duration'], 12);
    expect(event['errorCode'], 'SAVE-003');
    expect(event['token'], 'storage.ioError');

    // No retained scalar may carry the smuggled content, under any key.
    final String flattened = client.debugEvents.toString();
    for (final String secret in <String>[
      path,
      title,
      ocrText,
      fieldValue,
      signature,
      bareTitle,
    ]) {
      expect(flattened, isNot(contains(secret)));
    }
    for (final Object? value in event.values) {
      expect(value, isNot(anyOf(path, title, ocrText, fieldValue, signature)));
    }
  });
}
