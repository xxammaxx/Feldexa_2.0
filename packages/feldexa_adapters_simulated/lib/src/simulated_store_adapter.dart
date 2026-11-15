// T028 SIMULATED secure-store adapter.
//
// This is an in-memory development substitute for the Android FXC1 encrypted
// store. It deliberately makes no encryption, confidentiality, Keystore, or
// durability claim: `research.md` D-16 says the Web store is seeded from the
// deterministic fixture world and may be persisted only for reload tests.
//
// What it does preserve is the observable port contract that the application
// and UI depend on (`contracts/ports.md` §2.4):
//   * one aggregate per document/template, with an immutable source reference;
//   * `createDocument`/`createTemplate` before any revision/version;
//   * `saveRevision` commits atomically, verifies by re-reading the canonical
//     bytes, and only then moves the head and applies retention
//     (last 3 autosave + newest explicit + newest recovery + head);
//   * `saveTemplateVersion` appends immutable versions and prunes nothing;
//   * `delete` requires an acknowledged confirmation whose title names the
//     stored title (or the `Nicht lesbar` placeholder for an unreadable
//     aggregate);
//   * typed `SAVE-001`/`SAVE-002`/`SAVE-003`/`SAVE-008` failures leave the last
//     verified head intact where the contract requires it.
//
// Deterministic fault switches exist for UI and later failure-injection tests;
// they are development inputs, not fault injection of a real store.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_ports/feldexa_ports.dart';

import 'simulated_backend.dart';
import 'simulated_contract.dart';
import 'simulated_digest.dart';

/// Placeholder title for an unreadable aggregate (`contracts/ports.md` §2.4).
const String simulatedUnreadableTitle = 'Nicht lesbar';

/// In-memory deterministic `SecureStorePort` substitute.
final class SimulatedSecureStoreAdapter implements SecureStorePort {
  /// Creates the store adapter.
  ///
  /// [maxTotalBytes] optionally caps the logical object bytes so tests and the
  /// Web surface can exercise `SAVE-001`. It is null by default (unbounded).
  SimulatedSecureStoreAdapter({required this.backend, this.maxTotalBytes});

  /// Shared simulated backend.
  final SimulatedBackend backend;

  /// Optional logical capacity cap.
  final int? maxTotalBytes;

  final Set<String> _lostAggregateKeys = <String>{};
  bool _globalKeyUnavailable = false;
  bool _failNextWrite = false;
  bool _corruptNextCommit = false;

  static final CapabilityDescriptor _descriptor = simulatedDescriptor(
    kind: CapabilityKind.secureStore,
    adapterId: simulatedStoreAdapterId,
    supportedFeatures: const <String>[
      'in-memory',
      'verified-revision',
      'revision-retention',
      'immutable-template-versions',
      'typed-save-failures',
    ],
  );

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  /// Evidence label carried by every store result.
  CapabilityEvidence get evidence => _descriptor.evidence;

  /// Whether the simulated global key provider is marked unavailable.
  bool get isGlobalKeyUnavailable => _globalKeyUnavailable;

  /// Aggregate ids whose simulated key was marked unavailable.
  Set<String> get lostAggregateKeys =>
      Set<String>.unmodifiable(_lostAggregateKeys);

  /// Marks one aggregate key unavailable (`SAVE-002` for that aggregate only).
  void simulateAggregateKeyLoss(String id) {
    _lostAggregateKeys.add(id);
  }

  /// Restores one aggregate key.
  void restoreAggregateKey(String id) {
    _lostAggregateKeys.remove(id);
  }

  /// Marks the simulated key provider unavailable (`SAVE-008`).
  void simulateGlobalKeyUnavailable() {
    _globalKeyUnavailable = true;
  }

  /// Restores the simulated key provider.
  void restoreGlobalKey() {
    _globalKeyUnavailable = false;
  }

  /// Makes the next revision/version write fail before the head moves.
  void failNextWrite() {
    _failNextWrite = true;
  }

  /// Makes the next revision write fail its read-back verification.
  void corruptNextCommit() {
    _corruptNextCommit = true;
  }

  @override
  Future<StoreStatus> status() async {
    final bool keysAvailable =
        !_globalKeyUnavailable &&
        !_lostAggregateKeys.any(
          (String id) =>
              backend.document(id) != null || backend.template(id) != null,
        );
    int objectCount = 0;
    final int totalBytes = _totalBytes();
    objectCount += backend.stagedSources.length;
    objectCount += backend.documents.length;
    objectCount += backend.templates.length;
    for (final SimulatedDocumentRecord document in backend.documents.values) {
      objectCount += document.revisions.length;
      objectCount += document.signatures.length;
    }
    for (final SimulatedTemplateRecord template in backend.templates.values) {
      objectCount += template.versions.length;
    }
    return StoreStatus(
      keyAvailable: keysAvailable,
      objectCount: objectCount,
      totalBytes: totalBytes,
      evidence: evidence,
    );
  }

  @override
  Future<StoredMeta> createDocument(CreateDocumentRequest request) async {
    final SourceFileRef source = _validatedStagedSource(request.source);
    final DateTime now = backend.context.nowUtc();
    final SimulatedDocumentRecord record = SimulatedDocumentRecord(
      id: backend.context.newId(),
      title: request.title,
      createdAt: now,
      updatedAt: now,
      source: source,
      head: null,
      lastDurableAt: null,
    );
    backend.putDocument(record);
    return _projectDocument(record);
  }

  @override
  Future<StoredMeta> saveRevision(SaveRevisionRequest request) async {
    final SimulatedDocumentRecord? record = backend.document(
      request.documentId,
    );
    if (record == null) {
      throw ArgumentError('document does not exist');
    }
    _ensureAggregateKey(record.id);
    if (request.expectedHead != record.head) {
      throw ArgumentError(
        'expectedHead does not match the last verified revision',
      );
    }
    final RevisionContent content = request.content;
    final Uint8List canonicalBytes = Uint8List.fromList(
      canonicalJsonBytes(content.toJson()),
    );
    _checkCapacity(canonicalBytes.length);

    if (_failNextWrite) {
      _failNextWrite = false;
      // The staged write failed; the previous verified head is untouched.
      throw StorageWriteException();
    }

    final SimulatedRevisionRecord revision = SimulatedRevisionRecord(
      id: backend.context.newId(),
      kind: request.kind,
      content: content,
      committedAt: backend.context.nowUtc(),
      sequence: backend.nextSequence(),
      canonicalBytes: canonicalBytes,
      sha256: sha256Hex(canonicalBytes),
    );
    record.revisions[revision.id] = revision;

    // Read back exactly what was staged. A mismatch is `SAVE-003` and never an
    // optimistic success; the staged revision is discarded and the head stays.
    final SimulatedRevisionRecord? readBack = record.revisions[revision.id];
    final bool verified =
        readBack != null &&
        readBack.sha256 == sha256Hex(readBack.canonicalBytes) &&
        !_corruptNextCommit;
    _corruptNextCommit = false;
    if (!verified) {
      record.revisions.remove(revision.id);
      throw CorruptDataException();
    }

    final DateTime now = backend.context.nowUtc();
    record.head = revision.id;
    record.lastDurableAt = now;
    record.updatedAt = now;
    _applyDocumentRetention(record);
    return _projectDocument(record);
  }

  @override
  Future<LoadedDocument> loadDocument(String documentId) async {
    final SimulatedDocumentRecord? record = backend.document(documentId);
    if (record == null) {
      throw ArgumentError('document does not exist');
    }
    _ensureAggregateKey(record.id);
    final String? head = record.head;
    if (head == null) {
      throw StateError('document has no verified revision');
    }
    final SimulatedRevisionRecord revision = record.revisions[head]!;
    final RevisionContent content = _verifiedRevisionContent(revision);
    final Uint8List sourceBytes = _verifiedSourceBytes(record.source);
    return LoadedDocument(
      meta: _documentMeta(record),
      content: content,
      sourceBytes: sourceBytes,
      evidence: evidence,
    );
  }

  @override
  Future<Uint8List> readSignature(String documentId, String assetId) async {
    final SimulatedDocumentRecord? record = backend.document(documentId);
    if (record == null) {
      throw ArgumentError('document does not exist');
    }
    _ensureAggregateKey(record.id);
    final Uint8List? bytes = backend.signatureBytes(documentId, assetId);
    if (bytes == null) {
      throw ArgumentError('signature asset does not exist');
    }
    return bytes;
  }

  @override
  Future<void> writeSignature(WriteSignatureRequest request) async {
    final SimulatedDocumentRecord? record = backend.document(
      request.documentId,
    );
    if (record == null) {
      throw ArgumentError('document does not exist');
    }
    _ensureAggregateKey(record.id);
    final String actual = sha256Hex(request.bytes);
    if (actual != request.sha256) {
      // An asset whose declared hash does not match its bytes must never be
      // stored; `PLT-002` is the platform guard category.
      throw SecurityException();
    }
    _checkCapacity(request.bytes.length);
    backend.putSignature(request.documentId, request.assetId, request.bytes);
  }

  @override
  Future<List<StoredMeta>> list(StoreKind kind) async {
    final List<StoredMeta> entries = <StoredMeta>[];
    switch (kind) {
      case StoreKind.document:
        for (final SimulatedDocumentRecord record in backend.documents.values) {
          entries.add(_projectDocument(record));
        }
      case StoreKind.template:
        for (final SimulatedTemplateRecord record in backend.templates.values) {
          entries.add(_projectTemplate(record));
        }
    }
    entries.sort((StoredMeta a, StoredMeta b) {
      final int byUpdated = b.updatedAt.compareTo(a.updatedAt);
      return byUpdated != 0 ? byUpdated : a.id.compareTo(b.id);
    });
    return List<StoredMeta>.unmodifiable(entries);
  }

  @override
  Future<void> delete(
    StoreKind kind,
    String id,
    DeleteConfirmation confirmation,
  ) async {
    final String? expectedTitle = switch (kind) {
      StoreKind.document => _documentTitleForDelete(backend.document(id)),
      StoreKind.template => _templateTitleForDelete(backend.template(id)),
    };
    if (expectedTitle == null) {
      throw ArgumentError('aggregate does not exist');
    }
    if (!confirmation.acknowledged || confirmation.title != expectedTitle) {
      throw SecurityException();
    }
    switch (kind) {
      case StoreKind.document:
        backend.removeDocument(id);
      case StoreKind.template:
        backend.removeTemplate(id);
    }
  }

  @override
  Future<StoredMeta> createTemplate(CreateTemplateRequest request) async {
    final SourceFileRef source = _validatedStagedSource(request.source);
    if (request.pages.length != source.pageCount) {
      throw ArgumentError('pages.length must equal source.pageCount');
    }
    final TemplateVersionContent content = TemplateVersionContent(
      pageSnapshot: request.pages,
      fieldSnapshot: request.fields,
      fieldOrder: request.fieldOrder,
    );
    final Uint8List canonicalBytes = Uint8List.fromList(
      canonicalJsonBytes(content.toJson()),
    );
    _checkCapacity(canonicalBytes.length);
    if (_failNextWrite) {
      _failNextWrite = false;
      throw StorageWriteException();
    }
    final DateTime now = backend.context.nowUtc();
    final String templateId = backend.context.newId();
    final String versionId = backend.context.newId();
    final String hash = sha256Hex(canonicalBytes);
    final TemplateVersion version = TemplateVersion(
      id: versionId,
      templateId: templateId,
      versionNumber: 1,
      createdAt: now,
      fieldSnapshot: request.fields,
      pageSnapshot: request.pages,
      sha256: hash,
    );
    final SimulatedTemplateRecord record = SimulatedTemplateRecord(
      id: templateId,
      title: request.title,
      createdAt: now,
      updatedAt: now,
      source: source,
      head: versionId,
      versions: <String, SimulatedTemplateVersionRecord>{
        versionId: SimulatedTemplateVersionRecord(
          version: version,
          content: content,
          canonicalBytes: canonicalBytes,
          sha256: hash,
        ),
      },
    );
    if (!_verifyTemplateVersion(record.versions[versionId]!, content)) {
      throw CorruptDataException();
    }
    backend.putTemplate(record);
    return _projectTemplate(record);
  }

  @override
  Future<StoredMeta> saveTemplateVersion(
    SaveTemplateVersionRequest request,
  ) async {
    final SimulatedTemplateRecord? record = backend.template(
      request.templateId,
    );
    if (record == null) {
      throw ArgumentError('template does not exist');
    }
    _ensureAggregateKey(record.id);
    if (request.expectedHead != record.head) {
      throw ArgumentError(
        'expectedHead does not match the latest template version',
      );
    }
    final String? headId = record.head;
    final SimulatedTemplateVersionRecord? head = headId == null
        ? null
        : record.versions[headId];
    if (head == null) {
      throw StateError('template has no version');
    }
    final List<ConfirmedField> fields = request.fieldSnapshot.toList(
      growable: false,
    )..sort((ConfirmedField a, ConfirmedField b) => a.order.compareTo(b.order));
    final TemplateVersionContent content = TemplateVersionContent(
      pageSnapshot: request.pageSnapshot,
      fieldSnapshot: fields,
      fieldOrder: fields.map((ConfirmedField field) => field.id),
    );
    final Uint8List canonicalBytes = Uint8List.fromList(
      canonicalJsonBytes(content.toJson()),
    );
    _checkCapacity(canonicalBytes.length);
    if (_failNextWrite) {
      _failNextWrite = false;
      throw StorageWriteException();
    }
    final DateTime now = backend.context.nowUtc();
    final String versionId = backend.context.newId();
    final String hash = sha256Hex(canonicalBytes);
    final TemplateVersion version = TemplateVersion(
      id: versionId,
      templateId: record.id,
      versionNumber: head.version.versionNumber + 1,
      createdAt: now,
      fieldSnapshot: fields,
      pageSnapshot: request.pageSnapshot,
      sha256: hash,
    );
    record.versions[versionId] = SimulatedTemplateVersionRecord(
      version: version,
      content: content,
      canonicalBytes: canonicalBytes,
      sha256: hash,
    );
    final bool verified =
        !_corruptNextCommit &&
        _verifyTemplateVersion(record.versions[versionId]!, content);
    _corruptNextCommit = false;
    if (!verified) {
      record.versions.remove(versionId);
      throw CorruptDataException();
    }
    record.head = versionId;
    record.updatedAt = now;
    return _projectTemplate(record);
  }

  @override
  Future<LoadedTemplate> loadTemplate(
    String templateId, {
    String? versionId,
  }) async {
    final SimulatedTemplateRecord? record = backend.template(templateId);
    if (record == null) {
      throw ArgumentError('template does not exist');
    }
    _ensureAggregateKey(record.id);
    final String? selectedId = versionId ?? record.head;
    if (selectedId == null) {
      throw StateError('template has no version');
    }
    final SimulatedTemplateVersionRecord? selected =
        record.versions[selectedId];
    if (selected == null) {
      throw ArgumentError('template version does not exist');
    }
    final TemplateVersionContent content = _verifiedTemplateContent(selected);
    final StoredTemplate stored = StoredTemplate(
      meta: _templateMeta(record),
      version: selected.version,
      content: content,
    );
    final Uint8List sourceBytes = _verifiedSourceBytes(record.source);
    return LoadedTemplate(
      template: stored,
      sourceBytes: sourceBytes,
      evidence: evidence,
    );
  }

  @override
  Future<RecoveryStamp> recoveryStamp(String id, StoreKind kind) async {
    switch (kind) {
      case StoreKind.document:
        final SimulatedDocumentRecord? record = backend.document(id);
        if (record == null) {
          throw ArgumentError('document does not exist');
        }
        return RecoveryStamp(
          verifiedRevisionId: record.head,
          committedAt: record.lastDurableAt,
          headCorrupt: false,
          fellBackToOlderRevision: false,
        );
      case StoreKind.template:
        final SimulatedTemplateRecord? record = backend.template(id);
        if (record == null) {
          throw ArgumentError('template does not exist');
        }
        final String? headId = record.head;
        final SimulatedTemplateVersionRecord? head = headId == null
            ? null
            : record.versions[headId];
        return RecoveryStamp(
          verifiedRevisionId: record.head,
          committedAt: head?.version.createdAt,
          headCorrupt: false,
          fellBackToOlderRevision: false,
        );
    }
  }

  // --- document retention -------------------------------------------------

  /// Applies the contractual retention policy after a verified read-back.
  ///
  /// Known-kind revisions only: the head, the newest explicit revision, the
  /// newest recovery revision, and the last three autosaves are kept. The
  /// simulated store has no unknown/legacy entries to protect.
  void _applyDocumentRetention(SimulatedDocumentRecord record) {
    final List<SimulatedRevisionRecord> all = record.revisions.values.toList(
      growable: false,
    );
    final Set<String> keep = <String>{};
    if (record.head != null) {
      keep.add(record.head!);
    }
    final List<SimulatedRevisionRecord> autosaves =
        all
            .where(
              (SimulatedRevisionRecord r) => r.kind == RevisionKind.autosave,
            )
            .toList(growable: false)
          ..sort(
            (SimulatedRevisionRecord a, SimulatedRevisionRecord b) =>
                b.sequence.compareTo(a.sequence),
          );
    for (final SimulatedRevisionRecord revision in autosaves.take(3)) {
      keep.add(revision.id);
    }
    _keepNewestOfKind(all, RevisionKind.explicit, keep);
    _keepNewestOfKind(all, RevisionKind.recovery, keep);
    record.revisions.removeWhere(
      (String id, SimulatedRevisionRecord _) => !keep.contains(id),
    );
  }

  static void _keepNewestOfKind(
    List<SimulatedRevisionRecord> revisions,
    RevisionKind kind,
    Set<String> keep,
  ) {
    SimulatedRevisionRecord? newest;
    for (final SimulatedRevisionRecord revision in revisions) {
      if (revision.kind != kind) {
        continue;
      }
      if (newest == null || revision.sequence > newest.sequence) {
        newest = revision;
      }
    }
    if (newest != null) {
      keep.add(newest.id);
    }
  }

  // --- validation and projection -----------------------------------------

  SourceFileRef _validatedStagedSource(SourceFileRef source) {
    final SimulatedStagedSource? staged = backend.stagedSource(source.id);
    if (staged == null) {
      throw ArgumentError('source is not staged in the simulated backend');
    }
    if (staged.sha256 != source.sha256 ||
        staged.bytes.length != source.sizeBytes ||
        staged.pageCount != source.pageCount) {
      throw SecurityException();
    }
    return source;
  }

  Uint8List _verifiedSourceBytes(SourceFileRef source) {
    final Uint8List? bytes = backend.readStagedSource(source.id);
    if (bytes == null ||
        bytes.length != source.sizeBytes ||
        sha256Hex(bytes) != source.sha256) {
      throw CorruptDataException();
    }
    return bytes;
  }

  RevisionContent _verifiedRevisionContent(SimulatedRevisionRecord revision) {
    if (sha256Hex(revision.canonicalBytes) != revision.sha256) {
      throw CorruptDataException();
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(revision.canonicalBytes));
    } on FormatException {
      throw CorruptDataException();
    }
    if (decoded is! Map<Object?, Object?>) {
      throw CorruptDataException();
    }
    final Map<String, Object?> map = <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in decoded.entries)
        entry.key.toString(): entry.value,
    };
    try {
      final RevisionContent content = RevisionContent.fromJson(map);
      if (sha256Hex(canonicalJsonBytes(content.toJson())) != revision.sha256) {
        throw CorruptDataException();
      }
      return content;
    } on FormatException {
      throw CorruptDataException();
    } on ArgumentError {
      throw CorruptDataException();
    }
  }

  bool _verifyTemplateVersion(
    SimulatedTemplateVersionRecord version,
    TemplateVersionContent content,
  ) {
    return version.sha256 == sha256Hex(version.canonicalBytes) &&
        content.toJson().isNotEmpty &&
        sha256Hex(canonicalJsonBytes(content.toJson())) == version.sha256;
  }

  TemplateVersionContent _verifiedTemplateContent(
    SimulatedTemplateVersionRecord version,
  ) {
    if (sha256Hex(version.canonicalBytes) != version.sha256) {
      throw CorruptDataException();
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(version.canonicalBytes));
    } on FormatException {
      throw CorruptDataException();
    }
    if (decoded is! Map<Object?, Object?>) {
      throw CorruptDataException();
    }
    final Map<String, Object?> map = <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in decoded.entries)
        entry.key.toString(): entry.value,
    };
    try {
      final TemplateVersionContent content = TemplateVersionContent.fromJson(
        map,
      );
      if (sha256Hex(canonicalJsonBytes(content.toJson())) != version.sha256) {
        throw CorruptDataException();
      }
      return content;
    } on FormatException {
      throw CorruptDataException();
    } on ArgumentError {
      throw CorruptDataException();
    }
  }

  void _ensureAggregateKey(String id) {
    if (_globalKeyUnavailable) {
      throw KeystoreUnavailableException();
    }
    if (_lostAggregateKeys.contains(id)) {
      throw KeyUnavailableException();
    }
  }

  String? _unreadableReason(String id) {
    if (_globalKeyUnavailable) {
      return 'SAVE-008';
    }
    if (_lostAggregateKeys.contains(id)) {
      return 'SAVE-002';
    }
    return null;
  }

  StoredMeta _projectDocument(SimulatedDocumentRecord record) {
    final String? reason = _unreadableReason(record.id);
    return StoredMeta(
      id: record.id,
      kind: StoreKind.document,
      title: reason == null ? record.title : simulatedUnreadableTitle,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
      latestRevisionId: record.head,
      lastDurableAt: record.lastDurableAt,
      readable: reason == null,
      unreadableReasonCode: reason,
    );
  }

  StoredMeta _projectTemplate(SimulatedTemplateRecord record) {
    final String? reason = _unreadableReason(record.id);
    final String? headId = record.head;
    final SimulatedTemplateVersionRecord? head = headId == null
        ? null
        : record.versions[headId];
    return StoredMeta(
      id: record.id,
      kind: StoreKind.template,
      title: reason == null ? record.title : simulatedUnreadableTitle,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
      latestRevisionId: record.head,
      lastDurableAt: head?.version.createdAt,
      readable: reason == null,
      unreadableReasonCode: reason,
    );
  }

  String? _documentTitleForDelete(SimulatedDocumentRecord? record) {
    if (record == null) {
      return null;
    }
    return _unreadableReason(record.id) == null
        ? record.title
        : simulatedUnreadableTitle;
  }

  String? _templateTitleForDelete(SimulatedTemplateRecord? record) {
    if (record == null) {
      return null;
    }
    return _unreadableReason(record.id) == null
        ? record.title
        : simulatedUnreadableTitle;
  }

  DocumentMeta _documentMeta(SimulatedDocumentRecord record) {
    return DocumentMeta(
      id: record.id,
      title: record.title,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
      source: record.source,
      latestRevisionId: record.head,
      lastDurableAt: record.lastDurableAt,
    );
  }

  TemplateMeta _templateMeta(SimulatedTemplateRecord record) {
    final List<TemplateVersionPointer> pointers = record.versionsNewestFirst
        .map(
          (SimulatedTemplateVersionRecord version) => TemplateVersionPointer(
            versionId: version.version.id,
            versionNumber: version.version.versionNumber,
            createdAt: version.version.createdAt,
          ),
        )
        .toList(growable: false);
    if (pointers.isEmpty) {
      throw StateError('template has no version');
    }
    return TemplateMeta(
      id: record.id,
      title: record.title,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
      source: record.source,
      latestVersion: pointers.first,
      versions: pointers,
    );
  }

  int _totalBytes() {
    int total = 0;
    for (final SimulatedStagedSource source in backend.stagedSources.values) {
      total += source.bytes.length;
    }
    for (final SimulatedDocumentRecord document in backend.documents.values) {
      for (final SimulatedRevisionRecord revision
          in document.revisions.values) {
        total += revision.canonicalBytes.length;
      }
      for (final Uint8List signature in document.signatures.values) {
        total += signature.length;
      }
    }
    for (final SimulatedTemplateRecord template in backend.templates.values) {
      for (final SimulatedTemplateVersionRecord version
          in template.versions.values) {
        total += version.canonicalBytes.length;
      }
    }
    return total;
  }

  void _checkCapacity(int additionalBytes) {
    final int? limit = maxTotalBytes;
    if (limit != null && _totalBytes() + additionalBytes > limit) {
      throw StorageFullException();
    }
  }
}
