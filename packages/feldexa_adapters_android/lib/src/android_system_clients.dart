// T027 Android clock, id, diagnostics, and lifecycle thin clients.
//
// These four capabilities are platform-neutral Dart adapters in the Android
// package because T028 explicitly left them to the T023/T027 composition seam
// (`packages/feldexa_adapters_simulated/lib/src/simulated_context.dart`).
// None of them touches document content.

import 'dart:math';

import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/services.dart';

/// Android UTC wall clock (`ClockPort`).
final class AndroidClockClient implements ClockPort {
  const AndroidClockClient();

  static final CapabilityDescriptor _descriptor = CapabilityDescriptor(
    kind: CapabilityKind.clock,
    adapterId: 'android.clock.v1',
    version: '1',
    isSimulated: false,
    evidence: CapabilityEvidence.android(adapterId: 'android.clock.v1'),
    supportedFeatures: const <String>['utc-wall-clock'],
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

/// Android UUIDv4/idempotency source (`IdPort`).
final class AndroidIdClient implements IdPort {
  AndroidIdClient({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  static final CapabilityDescriptor _descriptor = CapabilityDescriptor(
    kind: CapabilityKind.ids,
    adapterId: 'android.ids.v1',
    version: '1',
    isSimulated: false,
    evidence: CapabilityEvidence.android(adapterId: 'android.ids.v1'),
    supportedFeatures: const <String>['uuid-v4', 'idempotency-key'],
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  @override
  String newId() => _uuidV4();

  @override
  String newIdempotencyKey() => _uuidV4();

  String _uuidV4() {
    final List<int> bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final String raw = bytes.map(hex).join();
    return '${raw.substring(0, 8)}-${raw.substring(8, 12)}-'
        '${raw.substring(12, 16)}-${raw.substring(16, 20)}-'
        '${raw.substring(20)}';
  }
}

/// Content-free on-device diagnostics ring buffer (`DiagnosticsPort`).
///
/// Only scalar values are retained; nested maps, lists, bytes, titles, paths,
/// and OCR/field text are dropped rather than risking a content leak.
final class AndroidDiagnosticsClient implements DiagnosticsPort {
  AndroidDiagnosticsClient({this.capacity = 256}) {
    if (capacity < 1) {
      throw ArgumentError('capacity must be at least 1');
    }
  }

  final int capacity;
  final List<Map<String, Object?>> _events = <Map<String, Object?>>[];

  static final CapabilityDescriptor _descriptor = CapabilityDescriptor(
    kind: CapabilityKind.diagnostics,
    adapterId: 'android.diagnostics.v1',
    version: '1',
    isSimulated: false,
    evidence: CapabilityEvidence.android(adapterId: 'android.diagnostics.v1'),
    supportedFeatures: const <String>[
      'on-device',
      'scalar-only',
      'ring-buffer',
    ],
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  @override
  void event(
    String code, {
    Map<String, Object?> scalarFields = const <String, Object?>{},
  }) {
    final Map<String, Object?> event = <String, Object?>{'code': code};
    for (final MapEntry<String, Object?> entry in scalarFields.entries) {
      final Object? value = entry.value;
      if (value == null || value is String || value is num || value is bool) {
        event[entry.key] = value;
      }
    }
    event['atUtc'] = DateTime.now().toUtc().toIso8601String();
    _events.add(Map<String, Object?>.unmodifiable(event));
    if (_events.length > capacity) {
      _events.removeRange(0, _events.length - capacity);
    }
  }

  @override
  Future<void> clear() async {
    _events.clear();
  }
}

/// Android lifecycle signals from the shared `de.feldexa/events` channel.
final class AndroidLifecycleClient implements LifecyclePort {
  AndroidLifecycleClient({EventChannel? channel})
    : _channel = channel ?? const EventChannel('de.feldexa/events') {
    _signals = _channel
        .receiveBroadcastStream()
        .map(_toSignal)
        .where((AppLifecycleSignal? signal) => signal != null)
        .cast<AppLifecycleSignal>();
  }

  final EventChannel _channel;
  late final Stream<AppLifecycleSignal> _signals;

  static final CapabilityDescriptor _descriptor = CapabilityDescriptor(
    kind: CapabilityKind.lifecycle,
    adapterId: 'android.lifecycle.v1',
    version: '1',
    isSimulated: false,
    evidence: CapabilityEvidence.android(adapterId: 'android.lifecycle.v1'),
    supportedFeatures: const <String>[
      'resumed',
      'inactive',
      'paused',
      'detached',
    ],
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  @override
  Stream<AppLifecycleSignal> get signals => _signals;

  AppLifecycleSignal? _toSignal(Object? event) {
    if (event is! Map || event['event'] != 'lifecycle') return null;
    switch (event['state']) {
      case 'resumed':
        return AppLifecycleSignal.resumed;
      case 'inactive':
        return AppLifecycleSignal.inactive;
      case 'paused':
        return AppLifecycleSignal.paused;
      case 'detached':
        return AppLifecycleSignal.detached;
      default:
        return null;
    }
  }
}
