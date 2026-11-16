import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/services.dart';

import 'android_operation_client.dart';

/// Partial document-save client. It never fabricates a successful metadata result.
final class AndroidDocumentSaveClient {
  AndroidDocumentSaveClient({required this.operations, MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('de.feldexa/platform');

  final AndroidOperationClient operations;
  final MethodChannel _channel;

  Future<StoredMeta> saveRevision(SaveRevisionRequest request) async {
    final result = await operations.invoke(
      'store.saveRevision',
      <String, Object?>{
        'documentId': request.documentId,
        'revision': request.content.toJson(),
        'expectedHead': request.expectedHead,
        'kind': request.kind.wireName,
      },
    );
    if (result is! Map ||
        result['verified'] != true ||
        result['revisionId'] is! String ||
        result['committedAt'] is! String ||
        result['sha256'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(result['sha256'] as String) ||
        result['prunedRevisions'] is! int ||
        (result['prunedRevisions'] as int) < 0) {
      throw const FormatException('Invalid or unverified save receipt');
    }
    final committed = DateTime.tryParse(result['committedAt'] as String);
    if (committed == null || !committed.isUtc) {
      throw const FormatException('Invalid commit time');
    }
    final response = await _channel.invokeMethod<Object?>(
      'store.list',
      <String, Object?>{'schemaVersion': 1, 'kind': 'document'},
    );
    if (response is! Map ||
        response['schemaVersion'] != 1 ||
        response['ok'] != true ||
        response['data'] is! Map ||
        (response['data'] as Map)['items'] is! List) {
      throw const FormatException('Invalid store list response');
    }
    final entries = ((response['data'] as Map)['items'] as List)
        .whereType<Map<Object?, Object?>>()
        .where((item) => item['id'] == request.documentId)
        .toList();
    if (entries.length != 1) {
      throw StateError('Saved document metadata is unavailable');
    }
    final entry = entries.single;
    if (entry['latestRevisionId'] != result['revisionId']) {
      throw StateError('Stored head changed after save');
    }
    if (entry['kind'] != 'document' ||
        entry['title'] is! String ||
        entry['createdAt'] is! String ||
        entry['updatedAt'] is! String ||
        entry['readable'] is! bool ||
        (entry['lastDurableAt'] != null && entry['lastDurableAt'] is! String) ||
        (entry['unreadableReasonCode'] != null &&
            entry['unreadableReasonCode'] is! String)) {
      throw const FormatException('Invalid stored document metadata');
    }
    DateTime readUtc(String value) {
      final parsed = DateTime.tryParse(value);
      if (parsed == null || !parsed.isUtc) {
        throw const FormatException('Invalid metadata time');
      }
      return parsed;
    }

    try {
      return StoredMeta(
        id: request.documentId,
        kind: StoreKind.document,
        title: entry['title'] as String,
        createdAt: readUtc(entry['createdAt'] as String),
        updatedAt: readUtc(entry['updatedAt'] as String),
        latestRevisionId: entry['latestRevisionId'] as String,
        lastDurableAt: entry['lastDurableAt'] == null
            ? null
            : readUtc(entry['lastDurableAt'] as String),
        readable: entry['readable'] as bool,
        unreadableReasonCode: entry['unreadableReasonCode'] as String?,
      );
    } on ArgumentError {
      throw const FormatException('Invalid stored document metadata');
    }
  }
}
