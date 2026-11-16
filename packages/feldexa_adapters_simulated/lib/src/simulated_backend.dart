// T028 shared in-memory state for the SIMULATED adapters.
//
// The Web substitutes share one deterministic backend so the import, raster,
// OCR, storage, export, and delivery adapters observe the same fixture-backed
// world. It is not an encrypted store and makes no confidentiality or
// durability claim: it is an in-memory development substitute, labelled
// `SIMULATED` on every result it produces.
//
// Nothing in this file reads the wall clock, `Random`, the file system, or the
// network. All state changes are driven by adapter calls and the deterministic
// [SimulatedAdapterContext].
library;

import 'dart:typed_data';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/feldexa_ports.dart';

import 'simulated_context.dart';
import 'simulated_digest.dart';
import 'simulated_fixtures.dart';

/// One staged, hash-verified source in the simulated backend.
final class SimulatedStagedSource {
  /// Creates a staged source.
  SimulatedStagedSource({
    required this.sourceId,
    required this.fixtureId,
    required this.bytes,
    required this.sha256,
    required this.pages,
    required this.importedAt,
  });

  /// UUIDv4 of the staged source object.
  final String sourceId;

  /// Fixture id the bytes came from.
  final String fixtureId;

  /// Defensive copy of the source bytes.
  final Uint8List bytes;

  /// Verified lowercase SHA-256.
  final String sha256;

  /// Display geometry in page order.
  final List<PageGeometry> pages;

  /// When the source was staged, in UTC.
  final DateTime importedAt;

  /// Page count.
  int get pageCount => pages.length;
}

/// One committed document revision in the simulated store.
final class SimulatedRevisionRecord {
  /// Creates a revision record.
  SimulatedRevisionRecord({
    required this.id,
    required this.kind,
    required this.content,
    required this.committedAt,
    required this.sequence,
    required this.canonicalBytes,
    required this.sha256,
  });

  /// UUIDv4 of the revision.
  final String id;

  /// Why the revision was written.
  final RevisionKind kind;

  /// Full snapshot.
  final RevisionContent content;

  /// Commit time, in UTC.
  final DateTime committedAt;

  /// Deterministic ordering counter independent of equal fixed timestamps.
  final int sequence;

  /// Canonical JSON bytes that were "written".
  final Uint8List canonicalBytes;

  /// SHA-256 of [canonicalBytes].
  final String sha256;
}

/// One document aggregate in the simulated store.
final class SimulatedDocumentRecord {
  /// Creates a document aggregate.
  SimulatedDocumentRecord({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.source,
    required this.head,
    required this.lastDurableAt,
    Map<String, SimulatedRevisionRecord>? revisions,
    Map<String, Uint8List>? signatures,
  }) : revisions = revisions ?? <String, SimulatedRevisionRecord>{},
       signatures = signatures ?? <String, Uint8List>{};

  /// UUIDv4 of the aggregate.
  final String id;

  /// Stored title.
  String title;

  /// Creation time, in UTC.
  DateTime createdAt;

  /// Last update time, in UTC.
  DateTime updatedAt;

  /// Immutable source reference.
  final SourceFileRef source;

  /// Verified revision head, or null before the first save.
  String? head;

  /// Last verified durable commit time, in UTC.
  DateTime? lastDurableAt;

  /// Known revisions by id.
  final Map<String, SimulatedRevisionRecord> revisions;

  /// Signature assets by asset id.
  final Map<String, Uint8List> signatures;

  /// The head revision record, when a save has committed.
  SimulatedRevisionRecord? get headRevision =>
      head == null ? null : revisions[head];
}

/// One immutable template version in the simulated store.
final class SimulatedTemplateVersionRecord {
  /// Creates a version record.
  SimulatedTemplateVersionRecord({
    required this.version,
    required this.content,
    required this.canonicalBytes,
    required this.sha256,
  });

  /// Canonical version record.
  final TemplateVersion version;

  /// Immutable version content.
  final TemplateVersionContent content;

  /// Canonical JSON bytes that were "written".
  final Uint8List canonicalBytes;

  /// SHA-256 of [canonicalBytes].
  final String sha256;
}

/// One template aggregate in the simulated store.
final class SimulatedTemplateRecord {
  /// Creates a template aggregate.
  SimulatedTemplateRecord({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.source,
    required this.head,
    Map<String, SimulatedTemplateVersionRecord>? versions,
  }) : versions = versions ?? <String, SimulatedTemplateVersionRecord>{};

  /// UUIDv4 of the aggregate.
  final String id;

  /// Stored title.
  String title;

  /// Creation time, in UTC.
  DateTime createdAt;

  /// Last update time, in UTC.
  DateTime updatedAt;

  /// Immutable source reference.
  final SourceFileRef source;

  /// Latest version id, or null before the first version.
  String? head;

  /// Versions by id.
  final Map<String, SimulatedTemplateVersionRecord> versions;

  /// Version records newest first.
  List<SimulatedTemplateVersionRecord> get versionsNewestFirst {
    final List<SimulatedTemplateVersionRecord> ordered =
        versions.values.toList(growable: false)..sort(
          (a, b) => b.version.versionNumber.compareTo(a.version.versionNumber),
        );
    return ordered;
  }
}

/// One exported preview artifact held by the simulated backend.
final class SimulatedArtifactRecord {
  /// Creates an artifact record.
  SimulatedArtifactRecord({required this.artifact, required this.bytes});

  /// Canonical artifact metadata.
  ExportArtifact artifact;

  /// Preview PDF bytes.
  final Uint8List bytes;
}

/// One recorded simulated delivery attempt.
final class SimulatedDeliveryRecord {
  /// Creates a delivery record.
  const SimulatedDeliveryRecord({
    required this.action,
    required this.artifactId,
    required this.completed,
    required this.at,
  });

  /// Attempted action.
  final DeliveryAction action;

  /// Artifact that was handed off.
  final String artifactId;

  /// Whether the simulated hand-off completed.
  final bool completed;

  /// Attempt time, in UTC.
  final DateTime at;
}

/// Where a deterministic raster came from, for OCR lookup.
final class SimulatedRasterOrigin {
  /// Creates a raster provenance record.
  const SimulatedRasterOrigin({
    required this.sourceId,
    required this.fixtureId,
    required this.pageIndex,
    required this.width,
    required this.height,
    required this.format,
  });

  /// Source id used for the render.
  final String sourceId;

  /// Fixture id behind the source.
  final String fixtureId;

  /// Rendered page index.
  final int pageIndex;

  /// Rendered width in pixels.
  final int width;

  /// Rendered height in pixels.
  final int height;

  /// Pixel format.
  final RasterFormat format;
}

/// Deterministic in-memory backing store shared by the six adapters.
final class SimulatedBackend {
  /// Creates an empty backend.
  ///
  /// [context] supplies the fixed clock and UUIDv4 sequence. One backend is
  /// shared by the adapters registered for a single Web build. [maxTotalBytes]
  /// optionally caps the logical object bytes shared by every adapter so
  /// import and store operations exercise the same deterministic `SAVE-001`
  /// capacity condition. It is null by default (unbounded); it is a logical
  /// in-memory cap, not a real free-space measurement.
  SimulatedBackend({SimulatedAdapterContext? context, int? maxTotalBytes})
    : context = context ?? SimulatedAdapterContext(),
      _maxTotalBytes = _validatedCapacity(maxTotalBytes);

  /// Deterministic clock and id source.
  final SimulatedAdapterContext context;

  int? _maxTotalBytes;

  /// Logical object-byte cap shared by import and store, or null when
  /// unbounded.
  ///
  /// Lowering the cap never deletes existing data; it only makes the next
  /// operation that would exceed the cap fail with `SAVE-001`.
  int? get maxTotalBytes => _maxTotalBytes;

  set maxTotalBytes(int? value) {
    _maxTotalBytes = _validatedCapacity(value);
  }

  static int? _validatedCapacity(int? value) {
    if (value != null && value < 0) {
      throw ArgumentError.value(value, 'maxTotalBytes', 'must not be negative');
    }
    return value;
  }

  bool _globalKeyUnavailable = false;
  final Set<String> _lostAggregateKeys = <String>{};

  /// Whether the simulated key provider is marked globally unavailable.
  ///
  /// The store and import adapters share this flag so a `SAVE-008` condition
  /// blocks visible aggregate creation, not only later loads/saves.
  bool get globalKeyUnavailable => _globalKeyUnavailable;

  /// Aggregate ids whose simulated key was marked unavailable.
  Set<String> get lostAggregateKeys =>
      Set<String>.unmodifiable(_lostAggregateKeys);

  /// Sets or clears the simulated global key-provider outage.
  void setGlobalKeyUnavailable(bool value) {
    _globalKeyUnavailable = value;
  }

  /// Sets or clears one aggregate's simulated key loss.
  void setAggregateKeyUnavailable(String id, bool value) {
    if (value) {
      _lostAggregateKeys.add(id);
    } else {
      _lostAggregateKeys.remove(id);
    }
  }

  final Map<String, SimulatedStagedSource> _sources =
      <String, SimulatedStagedSource>{};
  final Map<String, SimulatedDocumentRecord> _documents =
      <String, SimulatedDocumentRecord>{};
  final Map<String, SimulatedTemplateRecord> _templates =
      <String, SimulatedTemplateRecord>{};
  final Map<String, SimulatedArtifactRecord> _artifacts =
      <String, SimulatedArtifactRecord>{};
  final Map<String, SimulatedRasterOrigin> _rasterOrigins =
      <String, SimulatedRasterOrigin>{};
  final List<SimulatedDeliveryRecord> _deliveries = <SimulatedDeliveryRecord>[];

  /// Staged sources by source id.
  Map<String, SimulatedStagedSource> get stagedSources =>
      Map<String, SimulatedStagedSource>.unmodifiable(_sources);

  /// Document aggregates by id.
  Map<String, SimulatedDocumentRecord> get documents =>
      Map<String, SimulatedDocumentRecord>.unmodifiable(_documents);

  /// Template aggregates by id.
  Map<String, SimulatedTemplateRecord> get templates =>
      Map<String, SimulatedTemplateRecord>.unmodifiable(_templates);

  /// Preview artifacts by id.
  Map<String, SimulatedArtifactRecord> get artifacts =>
      Map<String, SimulatedArtifactRecord>.unmodifiable(_artifacts);

  /// Recorded simulated deliveries, oldest first.
  List<SimulatedDeliveryRecord> get deliveries =>
      List<SimulatedDeliveryRecord>.unmodifiable(_deliveries);

  /// Looks up a staged source.
  SimulatedStagedSource? stagedSource(String sourceId) => _sources[sourceId];

  /// Stages a hash-verified source.
  ///
  /// The bytes are copied and re-hashed; a hash disagreement throws
  /// [StorageWriteException] (`SAVE-003`) because the staged object would be
  /// unreadable, and no source becomes visible.
  SimulatedStagedSource stageSource({
    required String sourceId,
    required SimulatedFixture fixture,
    DateTime? importedAt,
  }) {
    final Uint8List bytes = copyBytes(fixture.bytes);
    final String actualSha256 = sha256Hex(bytes);
    if (actualSha256 != fixture.sha256 || bytes.length != fixture.sizeBytes) {
      throw StorageWriteException();
    }
    final SimulatedStagedSource source = SimulatedStagedSource(
      sourceId: sourceId,
      fixtureId: fixture.id,
      bytes: bytes,
      sha256: actualSha256,
      pages: fixture.geometries,
      importedAt: importedAt ?? context.nowUtc(),
    );
    _sources[sourceId] = source;
    return source;
  }

  /// Reads back a staged source and re-verifies its hash.
  ///
  /// Returns a copy so a caller cannot mutate the stored bytes.
  Uint8List? readStagedSource(String sourceId) {
    final SimulatedStagedSource? source = _sources[sourceId];
    return source == null ? null : copyBytes(source.bytes);
  }

  /// Looks up a document aggregate.
  SimulatedDocumentRecord? document(String documentId) =>
      _documents[documentId];

  /// Stores a document aggregate.
  void putDocument(SimulatedDocumentRecord record) {
    _documents[record.id] = record;
  }

  /// Removes a document aggregate and its signature assets.
  void removeDocument(String documentId) {
    _documents.remove(documentId);
  }

  /// Looks up a template aggregate.
  SimulatedTemplateRecord? template(String templateId) =>
      _templates[templateId];

  /// Stores a template aggregate.
  void putTemplate(SimulatedTemplateRecord record) {
    _templates[record.id] = record;
  }

  /// Removes a template aggregate.
  void removeTemplate(String templateId) {
    _templates.remove(templateId);
  }

  /// Removes a staged source unless another aggregate still owns it.
  ///
  /// `contracts/ports.md` §2.4 requires `delete` to remove the aggregate's
  /// objects without touching any other document or template. The staged
  /// source is owned by every aggregate that references the same immutable
  /// [SourceFileRef], so it is removed only after the last owner is gone. A
  /// source that no aggregate references at all is also removed because it has
  /// no remaining owner.
  ///
  /// Returns true when the source object was removed.
  bool removeSourceIfUnreferenced(String sourceId) {
    if (!_sources.containsKey(sourceId)) {
      return false;
    }
    final bool stillReferenced =
        _documents.values.any(
          (SimulatedDocumentRecord record) => record.source.id == sourceId,
        ) ||
        _templates.values.any(
          (SimulatedTemplateRecord record) => record.source.id == sourceId,
        );
    if (stillReferenced) {
      return false;
    }
    return _sources.remove(sourceId) != null;
  }

  /// Total logical object bytes currently held by the backend.
  ///
  /// This mirrors the stored objects (`src`, revision/version bodies, and
  /// signature assets) that the store capacity model accounts for.
  int get totalBytes {
    int total = 0;
    for (final SimulatedStagedSource source in _sources.values) {
      total += source.bytes.length;
    }
    for (final SimulatedDocumentRecord document in _documents.values) {
      for (final SimulatedRevisionRecord revision
          in document.revisions.values) {
        total += revision.canonicalBytes.length;
      }
      for (final Uint8List signature in document.signatures.values) {
        total += signature.length;
      }
    }
    for (final SimulatedTemplateRecord template in _templates.values) {
      for (final SimulatedTemplateVersionRecord version
          in template.versions.values) {
        total += version.canonicalBytes.length;
      }
    }
    return total;
  }

  /// Refuses an operation that would exceed the shared logical capacity.
  ///
  /// Storage exhaustion is the canonical `StorageFullException` (`SAVE-001`)
  /// and leaves all existing objects untouched (FR-074/FR-075). The check is
  /// performed before the caller makes the new object visible.
  void ensureCapacityFor(int additionalBytes) {
    if (additionalBytes < 0) {
      throw ArgumentError.value(
        additionalBytes,
        'additionalBytes',
        'must not be negative',
      );
    }
    final int? limit = _maxTotalBytes;
    if (limit != null && totalBytes + additionalBytes > limit) {
      throw StorageFullException();
    }
  }

  /// Reads a signature asset, returning a defensive copy.
  Uint8List? signatureBytes(String documentId, String assetId) {
    final SimulatedDocumentRecord? record = _documents[documentId];
    final Uint8List? bytes = record?.signatures[assetId];
    return bytes == null ? null : copyBytes(bytes);
  }

  /// Stores a new signature asset on a document aggregate.
  ///
  /// `contracts/storage-format.md` §1 marks `sig/<assetId>.fxs` immutable, so
  /// an existing asset id is never replaced: this returns false and leaves the
  /// prior bytes untouched. Returns true when the asset was stored.
  bool putSignature(String documentId, String assetId, Uint8List bytes) {
    final SimulatedDocumentRecord? record = _documents[documentId];
    if (record == null || record.signatures.containsKey(assetId)) {
      return false;
    }
    record.signatures[assetId] = copyBytes(bytes);
    return true;
  }

  /// Stores a preview artifact.
  void putArtifact(SimulatedArtifactRecord record) {
    _artifacts[record.artifact.id] = record;
  }

  /// Looks up a preview artifact.
  SimulatedArtifactRecord? artifact(String artifactId) =>
      _artifacts[artifactId];

  /// Removes a preview artifact.
  void removeArtifact(String artifactId) {
    _artifacts.remove(artifactId);
  }

  /// Registers the deterministic origin of one raster.
  void registerRasterOrigin(String digest, SimulatedRasterOrigin origin) {
    _rasterOrigins[digest] = origin;
  }

  /// Looks up the origin of one raster by digest.
  SimulatedRasterOrigin? rasterOrigin(String digest) => _rasterOrigins[digest];

  /// Forgets every raster registered for [sourceId].
  void forgetRasterOrigins(String sourceId) {
    _rasterOrigins.removeWhere(
      (String _, SimulatedRasterOrigin origin) => origin.sourceId == sourceId,
    );
  }

  /// Records one simulated delivery attempt.
  void recordDelivery(SimulatedDeliveryRecord record) {
    _deliveries.add(record);
  }

  /// Next deterministic sequence number for revision ordering.
  int nextSequence() => context.nextSequence();
}
