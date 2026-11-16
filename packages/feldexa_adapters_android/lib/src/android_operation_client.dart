import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';

/// An accepted operation and its eventual terminal data.
final class AndroidOperation {
  const AndroidOperation(this.operationId, this.result);
  final String operationId;
  final Future<Object?> result;
}

/// Correlates accepted asynchronous Android operations with terminal results.
final class AndroidOperationClient {
  AndroidOperationClient({MethodChannel? channel, Stream<Object?>? results})
    : _channel = channel ?? const MethodChannel('de.feldexa/platform') {
    _subscription =
        (results ??
                const EventChannel('de.feldexa/results')
                    .receiveBroadcastStream())
            .listen(_onResult, onError: _onStreamError, onDone: _onStreamDone);
  }

  final MethodChannel _channel;
  late final StreamSubscription<Object?> _subscription;
  final Map<String, Completer<Object?>> _pending = {};
  final LinkedHashMap<String, Map<Object?, Object?>> _early = LinkedHashMap();
  final LinkedHashSet<String> _completed = LinkedHashSet();
  bool _disposed = false;
  Object? _streamFailure;

  Future<Object?> invoke(String method, Map<String, Object?> payload) async {
    return (await start(method, payload)).result;
  }

  /// Returns the reliable cancellation ID as soon as the operation is accepted.
  Future<AndroidOperation> start(
    String method,
    Map<String, Object?> payload,
  ) async {
    if (_disposed) throw StateError('Operation client is disposed');
    if (payload.containsKey('schemaVersion')) {
      throw ArgumentError('schemaVersion is assigned by the client');
    }
    final start = await _channel.invokeMethod<Object?>(
      method,
      <String, Object?>{'schemaVersion': 1, ...payload},
    );
    if (_disposed) throw StateError('Operation client is disposed');
    if (_streamFailure != null) {
      throw StateError('Operation result stream is unavailable');
    }
    if (start is! Map ||
        start['schemaVersion'] != 1 ||
        start['ok'] != true ||
        start['data'] is! Map) {
      throw const FormatException('Invalid operation start reply');
    }
    final data = start['data'] as Map;
    final id = data['operationId'];
    if (data.length != 1 ||
        id is! String ||
        !_uuid.hasMatch(id) ||
        _pending.containsKey(id) ||
        _completed.contains(id)) {
      throw const FormatException('Invalid operation identifier');
    }
    final completer = Completer<Object?>();
    // A terminal error can precede the start reply; keep it observed until
    // the caller receives the operation and can attach its own handler.
    unawaited(
      completer.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    _pending[id] = completer;
    final early = _early.remove(id);
    if (early != null) _finish(id, early);
    return AndroidOperation(id, completer.future);
  }

  /// Requests cancellation; a winning cancellation arrives on [AndroidOperation.result].
  Future<bool> cancel(String id) async {
    if (_disposed) throw StateError('Operation client is disposed');
    if (!_uuid.hasMatch(id)) {
      throw ArgumentError('Invalid operation identifier');
    }
    final response = await _channel.invokeMethod<Object?>(
      'cancel.operation',
      <String, Object?>{'schemaVersion': 1, 'operationId': id},
    );
    if (response is! Map ||
        response['schemaVersion'] != 1 ||
        response['ok'] != true ||
        response['data'] is! Map ||
        (response['data'] as Map)['cancelled'] is! bool) {
      throw const FormatException('Invalid cancellation reply');
    }
    return (response['data'] as Map)['cancelled'] as bool;
  }

  void _onResult(Object? event) {
    if (_disposed ||
        event is! Map ||
        event['schemaVersion'] != 1 ||
        event['event'] != 'operation.result') {
      return;
    }
    final id = event['operationId'];
    if (id is! String || !_uuid.hasMatch(id) || _completed.contains(id)) return;
    final result = Map<Object?, Object?>.from(event);
    if (_pending.containsKey(id)) {
      _finish(id, result);
    } else {
      _early[id] = result;
      if (_early.length > 64) _early.remove(_early.keys.first);
    }
  }

  void _finish(String id, Map<Object?, Object?> result) {
    final completer = _pending.remove(id);
    if (completer == null) return;
    _completed.add(id);
    if (_completed.length > 64) _completed.remove(_completed.first);
    if (result['ok'] == true &&
        result.containsKey('data') &&
        !result.containsKey('error')) {
      completer.complete(result['data']);
    } else if (result['ok'] == false &&
        result['error'] is Map &&
        !result.containsKey('data')) {
      final error = result['error'] as Map;
      if (error['code'] is String &&
          (error['message'] == null || error['message'] is String)) {
        completer.completeError(
          PlatformException(
            code: error['code'] as String,
            message: error['message'] as String?,
            details: error['details'],
          ),
        );
      } else {
        completer.completeError(
          const FormatException('Invalid operation error'),
        );
      }
    } else {
      completer.completeError(
        const FormatException('Invalid operation result'),
      );
    }
  }

  void _onStreamError(Object error, StackTrace stack) {
    _streamFailure = error;
    for (final pending in _pending.values) {
      pending.completeError(error, stack);
    }
    _pending.clear();
  }

  void _onStreamDone() => _onStreamError(
    StateError('Operation result stream closed'),
    StackTrace.current,
  );

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription.cancel();
    _onStreamDone();
    _early.clear();
    _completed.clear();
  }
}

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);
