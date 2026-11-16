// T027 Android `SecureStorePort` thin client.
//
// Normative sources:
//   * `contracts/ports.md` §2.4 and §2.10;
//   * `contracts/platform-channel.md` §4;
//   * `contracts/storage-format.md` §3–§5.
//
// The client never fabricates metadata. `createDocument` returns the
// `StoredMeta` the native store projected from the committed readable
// aggregate; `saveRevision` returns metadata only after the native receipt and
// the subsequent `store.list` agree on the committed head. Template channel
// payloads are not normatively specified yet, so those methods fail closed
// instead of inventing a second contract.

import 'package:crypto/crypto.dart' as crypto;

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/services.dart';

import 'android_channel.dart';
import 'android_operation_client.dart';

/// Recovery result of `store.startupRecovery` (T031 prerequisite).
///
/// Counts only; no id, title, path, or content.
final class AndroidRecoveryReport {
  const AndroidRecoveryReport({
    required this.tempEntriesRemoved,
    required this.incompleteAggregatesRemoved,
    required this.unreadableAggregates,
    required this.fallbackAdoptions,
    required this.orphanAliasesRemoved,
    required this.orphanAliasesRetained,
    required this.orphanAliasesFailed,
    required this.aliasSweepSkipped,
    required this.ambiguousRevisionOrder,
    required this.prunedRevisions,
  });

  final int tempEntriesRemoved;
  final int incompleteAggregatesRemoved;
  final int unreadableAggregates;
  final int fallbackAdoptions;
  final int orphanAliasesRemoved;
  final int orphanAliasesRetained;
  final int orphanAliasesFailed;
  final bool aliasSweepSkipped;
  final int ambiguousRevisionOrder;
  final int prunedRevisions;

  @override
  String toString() =>
      'AndroidRecoveryReport(temp: $tempEntriesRemoved, '
      'incomplete: $incompleteAggregatesRemoved, '
      'unreadable: $unreadableAggregates, '
      'fallbacks: $fallbackAdoptions)';
}

/// Android `SecureStorePort` implementation backed by the T026 store.
final class AndroidStoreClient implements SecureStorePort {
  AndroidStoreClient({
    MethodChannel? channel,
    AndroidOperationClient? operations,
    CapabilityEvidence? evidence,
  }) : _channel = channel ?? const MethodChannel('de.feldexa/platform'),
       _operations =
           operations ??
           AndroidOperationClient(
             channel: channel ?? const MethodChannel('de.feldexa/platform'),
           ),
       _evidence =
           evidence ??
           CapabilityEvidence.android(adapterId: 'android.store.v1');

  final MethodChannel _channel;
  final AndroidOperationClient _operations;
  final CapabilityEvidence _evidence;

  static final CapabilityDescriptor _descriptor = CapabilityDescriptor(
    kind: CapabilityKind.secureStore,
    adapterId: 'android.store.v1',
    version: '1',
    isSimulated: false,
    evidence: CapabilityEvidence.android(adapterId: 'android.store.v1'),
    supportedFeatures: const <String>[
      'fxc1',
      'android-keystore',
      'verified-readback',
      'document-create',
      'revision-history',
      'recovery-stamp',
      'native-startup-recovery',
    ],
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  CapabilityEvidence get evidence => _evidence;

  // ------------------------------------------------------------------
  // Reads
  // ------------------------------------------------------------------

  @override
  Future<StoreStatus> status() async {
    final Map<String, Object?> data = androidEnvelopeData(
      await _invoke('store.status', const <String, Object?>{}),
      method: 'store.status',
    );
    final Object? keyAvailable = data['keyAvailable'];
    final Object? objectCount = data['objectCount'];
    final Object? totalBytes = data['totalBytes'];
    if (keyAvailable is! bool || objectCount is! int || totalBytes is! int) {
      throw const FormatException('Invalid store status response');
    }
    return StoreStatus(
      keyAvailable: keyAvailable,
      objectCount: objectCount,
      totalBytes: totalBytes,
      evidence: _evidence,
    );
  }

  @override
  Future<List<StoredMeta>> list(StoreKind kind) async {
    final Map<String, Object?> data = androidEnvelopeData(
      await _invoke('store.list', <String, Object?>{'kind': kind.name}),
      method: 'store.list',
    );
    final Object? items = data['items'];
    if (items is! List) throw const FormatException('Invalid store list');
    final List<StoredMeta> result = <StoredMeta>[];
    for (final Object? item in items) {
      result.add(_storedMeta(androidMap(item, 'store.list item')));
    }
    return List<StoredMeta>.unmodifiable(result);
  }

  @override
  Future<LoadedDocument> loadDocument(String documentId) async {
    final Map<String, Object?> data = androidEnvelopeData(
      await _invoke('store.loadDocument', <String, Object?>{
        'documentId': documentId,
      }),
      method: 'store.loadDocument',
    );
    final Map<String, Object?> metaJson = androidMap(data['meta'], 'meta');
    final Map<String, Object?> revisionJson = androidMap(
      data['revision'],
      'revision',
    );
    final Map<String, Object?> head = androidMap(data['head'], 'head');
    final DocumentMeta meta = DocumentMeta.fromJson(metaJson);
    final RevisionContent content = RevisionContent.fromJson(revisionJson);
    final String expectedSha = androidSha256(
      head['plaintextSha256'],
      'head.plaintextSha256',
    );
    final String actualSha = _sha256(canonicalJsonBytes(revisionJson));
    if (actualSha != expectedSha) {
      throw const FormatException('Loaded revision does not match its head');
    }
    if (head['revisionId'] != meta.latestRevisionId) {
      throw const FormatException('Loaded head does not match metadata');
    }
    final Object? rawSource = androidEnvelopeValue(
      await _invoke('store.readSource', <String, Object?>{
        'documentId': documentId,
      }),
      method: 'store.readSource',
    );
    final Uint8List? source = androidBytes(rawSource);
    if (source == null || source.isEmpty) {
      throw FormatException(
        'Invalid decrypted source (${rawSource.runtimeType})',
      );
    }
    return LoadedDocument(
      meta: meta,
      content: content,
      sourceBytes: source,
      evidence: _evidence,
    );
  }

  @override
  Future<Uint8List> readSignature(String documentId, String assetId) async {
    final Object? data = androidEnvelopeValue(
      await _invoke('store.readSignature', <String, Object?>{
        'documentId': documentId,
        'assetId': assetId,
      }),
      method: 'store.readSignature',
    );
    final Uint8List? bytes = androidBytes(data);
    if (bytes == null) {
      throw const FormatException('Invalid signature response');
    }
    return bytes;
  }

  @override
  Future<RecoveryStamp> recoveryStamp(String id, StoreKind kind) async {
    final Map<String, Object?> data = androidEnvelopeData(
      await _invoke('store.recoveryStamp', <String, Object?>{
        'id': id,
        'kind': kind.name,
      }),
      method: 'store.recoveryStamp',
    );
    final Object? headCorrupt = data['headCorrupt'];
    final Object? fellBack = data['fellBackToOlderRevision'];
    if (headCorrupt is! bool || fellBack is! bool) {
      throw const FormatException('Invalid recovery stamp response');
    }
    final Object? verified = data['verifiedRevisionId'];
    final Object? committed = data['committedAt'];
    if (verified != null && verified is! String) {
      throw const FormatException('Invalid recovery revision');
    }
    if (committed != null && committed is! String) {
      throw const FormatException('Invalid recovery timestamp');
    }
    try {
      return RecoveryStamp(
        verifiedRevisionId: verified as String?,
        committedAt: committed == null
            ? null
            : androidUtc(committed, 'committedAt'),
        headCorrupt: headCorrupt,
        fellBackToOlderRevision: fellBack,
      );
    } on ArgumentError {
      throw const FormatException('Invalid recovery stamp response');
    }
  }

  // ------------------------------------------------------------------
  // Writes
  // ------------------------------------------------------------------

  /// Stages an encrypted source before the aggregate becomes visible.
  ///
  /// This is the T027 bridge for the SAF import service (T038) and the
  /// prerequisite for `createDocument`; it is deliberately not part of
  /// `SecureStorePort` because the import workflow owns picker/preflight.
  Future<void> stageSource({
    required String documentId,
    required String sourceId,
    required Uint8List bytes,
    required String sha256,
  }) async {
    final Map<String, Object?> data = androidEnvelopeData(
      await _invoke('store.stageSource', <String, Object?>{
        'documentId': documentId,
        'sourceId': sourceId,
        'bytes': bytes,
        'sha256': sha256,
      }),
      method: 'store.stageSource',
    );
    if (data['verified'] != true ||
        data['sourceId'] != sourceId ||
        data['sha256'] != sha256) {
      throw const FormatException('Invalid staged source receipt');
    }
  }

  @override
  Future<StoredMeta> createDocument(CreateDocumentRequest request) async {
    final Map<String, Object?> data = androidEnvelopeData(
      await _invoke('store.createDocument', <String, Object?>{
        'documentId': request.documentId,
        'title': request.title,
        'source': request.source.toJson(),
        'initialRevision': request.initialRevision.toJson(),
      }),
      method: 'store.createDocument',
    );
    final StoredMeta meta = _storedMeta(data);
    if (meta.id != request.documentId ||
        meta.latestRevisionId != request.initialRevision.id) {
      throw const FormatException('Created metadata does not match request');
    }
    if (!meta.readable) {
      throw const FormatException('Created document is not readable');
    }
    return meta;
  }

  @override
  Future<StoredMeta> saveRevision(SaveRevisionRequest request) async {
    final Map<String, Object?> receipt = androidMap(
      await _invokeAsync('store.saveRevision', <String, Object?>{
        'documentId': request.documentId,
        'revision': request.content.toJson(),
        'expectedHead': request.expectedHead,
        'kind': request.kind.wireName,
      }),
      'save receipt',
    );
    if (receipt['verified'] != true) {
      throw const FormatException('Save receipt is not verified');
    }
    final String revisionId = androidUuid(receipt['revisionId'], 'revisionId');
    final String sha256 = androidSha256(receipt['sha256'], 'sha256');
    androidUtc(receipt['committedAt'], 'committedAt');
    final Object? pruned = receipt['prunedRevisions'];
    if (pruned is! int || pruned < 0) {
      throw const FormatException('Invalid pruned revision count');
    }

    final List<StoredMeta> documents = await list(StoreKind.document);
    final List<StoredMeta> matching = documents
        .where((StoredMeta item) => item.id == request.documentId)
        .toList();
    if (matching.length != 1) {
      throw StateError('Saved document metadata is unavailable');
    }
    final StoredMeta meta = matching.single;
    if (meta.latestRevisionId != revisionId || !meta.readable) {
      throw StateError('Stored head changed after save');
    }
    final String canonicalSha = _sha256(
      canonicalJsonBytes(request.content.toJson()),
    );
    if (canonicalSha != sha256) {
      throw const FormatException('Save receipt hash does not match content');
    }
    return meta;
  }

  @override
  Future<void> writeSignature(WriteSignatureRequest request) async {
    final Map<String, Object?> data = androidMap(
      await _invokeAsync('store.writeSignature', <String, Object?>{
        'documentId': request.documentId,
        'assetId': request.assetId,
        'bytes': request.bytes,
        'sha256': request.sha256,
      }),
      'signature receipt',
    );
    if (data['verified'] != true) {
      throw const FormatException('Signature write is not verified');
    }
  }

  @override
  Future<void> delete(
    StoreKind kind,
    String id,
    DeleteConfirmation confirmation,
  ) async {
    final Map<String, Object?> data = androidEnvelopeData(
      await _invoke('store.delete', <String, Object?>{
        'kind': kind.name,
        'id': id,
        'confirm': <String, Object?>{
          'title': confirmation.title,
          'acknowledged': confirmation.acknowledged,
        },
      }),
      method: 'store.delete',
    );
    if (data['deleted'] != true) {
      throw const FormatException('Delete was not confirmed complete');
    }
  }

  /// Runs the native T026 startup recovery.
  ///
  /// T031's bootstrap must call this before `StartupSweep.run()` so stale temp
  /// files, incomplete aggregates, head fallbacks, and orphan aliases are
  /// reconciled before the list is shown. No recovery work is duplicated here.
  Future<AndroidRecoveryReport> runStartupRecovery() async {
    final Map<String, Object?> data = androidEnvelopeData(
      await _invoke('store.startupRecovery', const <String, Object?>{}),
      method: 'store.startupRecovery',
    );
    int count(String name) {
      final Object? value = data[name];
      if (value is! int || value < 0) {
        throw FormatException('Invalid recovery count $name');
      }
      return value;
    }

    final Object? skipped = data['aliasSweepSkipped'];
    if (skipped is! bool) {
      throw const FormatException('Invalid alias sweep state');
    }
    return AndroidRecoveryReport(
      tempEntriesRemoved: count('tempEntriesRemoved'),
      incompleteAggregatesRemoved: count('incompleteAggregatesRemoved'),
      unreadableAggregates: count('unreadableAggregates'),
      fallbackAdoptions: count('fallbackAdoptions'),
      orphanAliasesRemoved: count('orphanAliasesRemoved'),
      orphanAliasesRetained: count('orphanAliasesRetained'),
      orphanAliasesFailed: count('orphanAliasesFailed'),
      aliasSweepSkipped: skipped,
      ambiguousRevisionOrder: count('ambiguousRevisionOrder'),
      prunedRevisions: count('prunedRevisions'),
    );
  }

  // ------------------------------------------------------------------
  // Template surface stays fail-closed
  // ------------------------------------------------------------------

  @override
  Future<StoredMeta> createTemplate(CreateTemplateRequest request) {
    throw UnsupportedOperationException();
  }

  @override
  Future<StoredMeta> saveTemplateVersion(SaveTemplateVersionRequest request) {
    throw UnsupportedOperationException();
  }

  @override
  Future<LoadedTemplate> loadTemplate(String templateId, {String? versionId}) {
    throw UnsupportedOperationException();
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  Future<Object?> _invoke(String method, Map<String, Object?> payload) async {
    try {
      return await _channel.invokeMethod<Object?>(method, <String, Object?>{
        'schemaVersion': 1,
        ...payload,
      });
    } catch (error) {
      throwAndroidChannelError(error);
    }
  }

  Future<Object?> _invokeAsync(
    String method,
    Map<String, Object?> payload,
  ) async {
    try {
      return await _operations.invoke(method, payload);
    } catch (error) {
      throwAndroidChannelError(error);
    }
  }

  StoredMeta _storedMeta(Map<String, Object?> data) {
    final String kind = data['kind'] is String ? data['kind'] as String : '';
    if (kind != 'document' && kind != 'template') {
      throw const FormatException('Invalid stored metadata kind');
    }
    final Object? latest = data['latestRevisionId'];
    final Object? durable = data['lastDurableAt'];
    final Object? reason = data['unreadableReasonCode'];
    final Object? readable = data['readable'];
    if (readable is! bool ||
        (latest != null && latest is! String) ||
        (durable != null && durable is! String) ||
        (reason != null && reason is! String)) {
      throw const FormatException('Invalid stored metadata');
    }
    try {
      return StoredMeta(
        id: androidUuid(data['id'], 'stored id'),
        kind: kind == 'document' ? StoreKind.document : StoreKind.template,
        title: data['title'] is String
            ? data['title'] as String
            : (throw const FormatException('Invalid stored title')),
        createdAt: androidUtc(data['createdAt'], 'createdAt'),
        updatedAt: androidUtc(data['updatedAt'], 'updatedAt'),
        latestRevisionId: latest as String?,
        lastDurableAt: durable == null
            ? null
            : androidUtc(durable, 'lastDurableAt'),
        readable: readable,
        unreadableReasonCode: reason as String?,
      );
    } on ArgumentError {
      throw const FormatException('Invalid stored metadata');
    }
  }

  static String _sha256(List<int> bytes) =>
      crypto.sha256.convert(bytes).toString();
}
