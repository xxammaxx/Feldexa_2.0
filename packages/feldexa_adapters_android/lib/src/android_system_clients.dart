// T027 Android clock, id, diagnostics, and lifecycle thin clients.
//
// These four capabilities are platform-neutral Dart adapters in the Android
// package because T028 explicitly left them to the T023/T027 composition seam
// (`packages/feldexa_adapters_simulated/lib/src/simulated_context.dart`).
// None of them touches document content.

import 'dart:math';

import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
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
/// Enforces the `contracts/ports.md` §2.9 whitelist fail-closed: an event is
/// retained only under a stable event code in a known namespace; a field
/// entry only under a stable single-segment field name; and a value only as an
/// [Enum] name, non-negative integer count/duration, non-negative [Duration]
/// (stored as milliseconds), or catalog error code (`SAVE-003`). Everything
/// else — free text, file names, titles, paths, OCR content, field values,
/// signatures, bytes, `null`, booleans, doubles, nested maps, and lists — is
/// dropped before the event is buffered. The buffer is size-capped and never
/// transmitted.
final class AndroidDiagnosticsClient implements DiagnosticsPort {
  AndroidDiagnosticsClient({this.capacity = 256}) {
    if (capacity < 1) {
      throw ArgumentError('capacity must be at least 1');
    }
  }

  /// Stable catalog error code (`SAVE-003`); free text, titles, paths, file
  /// names, and dotted tokens never match this scalar lane.
  static final RegExp _errorCodePattern = RegExp(r'^[A-Z]{2,6}-[0-9]{3}$');

  /// Stable event-code namespaces accepted by this ring buffer. Unknown
  /// namespaces are dropped fail-closed instead of becoming a free-text lane.
  static const Set<String> _eventCodeNamespaces = <String>{
    'app',
    'analysis',
    'delivery',
    'diagnostics',
    'editor',
    'export',
    'import',
    'lifecycle',
    'operation',
    'probe',
    'raster',
    'recognition',
    'review',
    'save',
    'store',
    'template',
  };

  /// Dotted lower-camel event code (`save.completed`, `store.saveRevision`).
  static final RegExp _eventCodePattern = RegExp(
    r'^[a-z][a-zA-Z0-9]*(?:\.[a-z][a-zA-Z0-9]*){0,3}$',
  );

  /// Single stable field name, never a path or a dotted file name.
  static final RegExp _fieldNamePattern = RegExp(r'^[a-z][a-zA-Z0-9_]*$');

  /// Longest diagnostic code, key, or string scalar, never prose.
  static const int _maxCodeLength = 64;

  /// File-extension segments that mark a value as a file name or a path.
  ///
  /// Mirrors the `CapabilityEvidence` deny-list: a file name is not a stable
  /// diagnostic code even when it is lowercase.
  static const Set<String> _contentExtensionSegments = <String>{
    'pdf',
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'heic',
    'txt',
    'json',
    'xml',
    'csv',
    'doc',
    'docx',
    'eml',
    'zip',
    'fx1',
  };

  static bool _hasContentExtensionSegment(String value) =>
      value.split('.').any(_contentExtensionSegments.contains);

  static bool _isStableEventCode(String code) {
    if (code.length > _maxCodeLength ||
        !_eventCodePattern.hasMatch(code) ||
        _hasContentExtensionSegment(code)) {
      return false;
    }
    return _eventCodeNamespaces.contains(code.split('.').first);
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

  /// Test-only read accessor for the retained, content-free events.
  @visibleForTesting
  List<Map<String, Object?>> get debugEvents =>
      List<Map<String, Object?>>.unmodifiable(_events);

  @override
  void event(
    String code, {
    Map<String, Object?> scalarFields = const <String, Object?>{},
  }) {
    if (!_isStableEventCode(code)) {
      return; // Fail-closed: no event without a stable content-free code.
    }
    final Map<String, Object?> event = <String, Object?>{'code': code};
    for (final MapEntry<String, Object?> entry in scalarFields.entries) {
      final String key = entry.key;
      if (key.length > _maxCodeLength ||
          !_fieldNamePattern.hasMatch(key) ||
          _hasContentExtensionSegment(key)) {
        continue; // No free-form field names in the buffer.
      }
      final Object? value = _whitelistedScalar(entry.value);
      if (value != null) {
        event[key] = value;
      }
    }
    event['atUtc'] = DateTime.now().toUtc().toIso8601String();
    _events.add(Map<String, Object?>.unmodifiable(event));
    if (_events.length > capacity) {
      _events.removeRange(0, _events.length - capacity);
    }
  }

  /// Returns the whitelisted representation of a scalar, or `null` to drop it.
  static Object? _whitelistedScalar(Object? value) {
    if (value is Enum) {
      return value.name;
    }
    if (value is int) {
      return value < 0 ? null : value;
    }
    if (value is Duration) {
      return value.inMilliseconds < 0 ? null : value.inMilliseconds;
    }
    if (value is String &&
        value.length <= _maxCodeLength &&
        _errorCodePattern.hasMatch(value)) {
      return value;
    }
    return null;
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
