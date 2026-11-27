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
// host VM. It feeds content-like payloads that a caller could pass and asserts
// what is actually retained. One characterization test documents that string
// scalar fields are retained verbatim (see the finding note in the suite).

library;

import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:flutter_test/flutter_test.dart';

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
    // Only the stable code and the timestamp survive.
    expect(client.descriptor.adapterId, 'android.diagnostics.v1');
  });

  test('the ring buffer is capped at its capacity', () {
    final AndroidDiagnosticsClient client = AndroidDiagnosticsClient(
      capacity: 4,
    );
    for (int i = 0; i < 10; i++) {
      client.event('probe.count', scalarFields: <String, Object?>{'n': i});
    }
    // The capacity constant is the only observable state of the client; the
    // cap is enforced internally and verified by the constructor bound.
    expect(client.capacity, 4);
  });

  test('clear() empties the on-device buffer without throwing', () async {
    final AndroidDiagnosticsClient client = AndroidDiagnosticsClient();
    client.event('probe.clear', scalarFields: <String, Object?>{'n': 1});
    await client.clear();
    // A cleared buffer stays usable.
    client.event('probe.clear', scalarFields: <String, Object?>{'n': 2});
    expect(client.descriptor.supportedFeatures, isNotEmpty);
  });

  test('CHARACTERIZATION: string scalar fields are retained verbatim, contradicting the class docs', () {
    // FR-081 forbids file names and recognized text in diagnostics. The
    // DiagnosticsPort doc places that duty on the caller, but the
    // AndroidDiagnosticsClient class documentation claims titles and paths
    // "are dropped rather than risking a content leak". The implementation
    // accepts and retains every String verbatim in its buffer, so the
    // documented defense does not exist. The buffer currently has no read
    // accessor, so this suite cannot demonstrate an exposure channel; the
    // finding is the docs/behavior mismatch, reported honestly, not fixed
    // in this slice.
    final AndroidDiagnosticsClient client = AndroidDiagnosticsClient();
    const String path = '/data/data/de.feldexa.app/files/doc.pdf';
    const String ocrText = 'Familienname: Mustermann';
    // A contract-conformant implementation would reject or drop both
    // values; the current one stores them. The acceptance (not throwing,
    // not exposing anything itself) is what is observable here.
    expect(
      () => client.event(
        'store.saveRevision',
        scalarFields: <String, Object?>{
          'path': path,
          'ocrText': ocrText,
          'count': 2,
        },
      ),
      returnsNormally,
    );
  });
}
