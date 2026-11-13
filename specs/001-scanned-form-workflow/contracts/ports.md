# Contract: Platform Ports

**Feature**: `001-scanned-form-workflow` | **Package**: `packages/feldexa_ports` | **Consumers**: `feldexa_application`, `feldexa_ui`, app registries

This contract is the only permitted way for application and UI code to reach a platform capability (constitution Principles II and III). Ports are Dart interfaces with no plugin imports. Implementations exist only in adapter packages. The app bootstrap resolves exactly one registry per build.

Conventions:
- All methods are asynchronous and report failures by throwing a typed `FeldexaException` (see §3). No method returns `null` to signal failure.
- No port accepts or returns a file path, a `File`, a `content://` URI, or a widget. Binary payloads are `Uint8List`.
- No port may log document content, file names, OCR text, field values, signature bytes, or paths.
- Every adapter exposes `CapabilityDescriptor`.
- Every result that can influence acceptance carries `CapabilityEvidence`.

**Shared types** used in signatures come from `feldexa_core` (`Rect`, `PageGeometry`, `Page`, `SourceFileRef`, `PageFailure`, `ConfirmedField`, `DocumentMeta`, `RevisionContent`, `RevisionKind`, `StoredTemplate`) and `feldexa_export` (`ExportPlan`, `ExportValidation`, `ExportArtifact`, `ArtifactVerification`). `feldexa_ports` depends only on those two pure packages; `feldexa_export` depends on `feldexa_core`; neither core nor export imports `feldexa_ports`; adapter packages depend on ports and platform SDKs.

**Type ownership (normative).** `feldexa_core` owns every canonical model type above; `feldexa_export` owns the four export contract types above. `packages/feldexa_ports/lib/src/evidence.dart` (T014) owns `EvidenceClass` and `CapabilityEvidence`. `packages/feldexa_ports/lib/src/errors.dart` (T014) owns `FeldexaException`, every typed exception in §3, and `ImportRejectionKind`. `packages/feldexa_ports/lib/src/descriptor.dart` (T013) owns `CapabilityKind`, `CapabilityDescriptor`, and `PlatformCapability`. `packages/feldexa_ports/lib/src/ports/` and `lib/src/dto/` (T013) own all 10 port interfaces, `AdapterRegistry`, and every remaining request/result DTO and enum in §2 and §4. T014 precedes T013; canonical core/export types precede both. No task may declare a second copy of a type owned by another task.

---

## 1. Capability evidence and descriptors

```dart
enum EvidenceClass { simulated, emulator, device, none }

enum CapabilityKind {
  documentImport, pageRaster, ocr, secureStore, pdfExport, delivery, lifecycle, clock, ids, diagnostics,
}

final class CapabilityEvidence {
  final EvidenceClass evidenceClass;
  final bool simulated;         // true iff evidenceClass == simulated
  final String adapterId;       // e.g. 'android.pdfbox.v1', 'web.sim.storage.v1'
  final String? simulatedReason;
  const CapabilityEvidence(...);
}

final class CapabilityDescriptor {
  final CapabilityKind kind;
  final String adapterId;
  final String version;         // adapter contract version, starts at '1'
  final bool isSimulated;
  final CapabilityEvidence evidence;
  final Set<String> supportedFeatures;
}

abstract interface class PlatformCapability {
  CapabilityDescriptor get descriptor;
}
```

**Rules**
- `evidenceClass` must be `simulated` for every adapter registered in the Web development registry, including the page-raster adapter. Web rasterization uses the real PDFium engine for visual fidelity, but it runs in a development environment on fixture-sourced bytes and cannot produce Android runtime evidence, so it is labeled `SIMULATED` like every other Web capability. Android adapters declare `evidenceClass: none` with `isSimulated: false`; the environment class (`EMULATOR`/`DEVICE`) is attached by the test harness.
- The Android registry must not import the simulated adapter package. A dependency-graph test asserts this.
- In release builds, `assertNoSimulatedAdapters(registry)` throws `FELDEXA-SIM-001` if a simulated capability is registered.
- A simulated adapter must be deterministic: same input → same output, no wall-clock, randomness, or network.

---

## 2. Ports

### 2.1 `DocumentImportPort`

```dart
enum ImportRejectionKind {
  passwordProtected, unsupportedEncryption, missing, unreadable, truncated,
  notPdf, unsupportedStructure, tooLarge, storageFull, cancelled, unknownReason,
}

final class ImportRequest { final int maxBytes; }        // default 80 MiB (83,886,080 bytes)

final class ImportedSource {
  final String documentId;
  final String sourceId;
  final String sha256;
  final int sizeBytes;
  final int pageCount;
  final List<PageGeometry> pages;
  final List<PageFailure> pageFailures;  // non-empty only for the partially-readable case
  final String? displayName;      // optional, user-visible only
  final CapabilityEvidence evidence;
}

abstract interface class DocumentImportPort implements PlatformCapability {
  /// Opens the platform document picker and streams the selection into the
  /// encrypted source store. Throws ImportRejectedException,
  /// StorageFullException, or StorageWriteException.
  Future<ImportedSource> pickAndImport(ImportRequest request);

  /// Re-validates an existing stored source without user interaction.
  Future<SourceIntegrity> verifySource(String sourceId);
}
```

`PageFailure` is the canonical `feldexa_core` value object owned by T017 (`data-model.md` §3.3): `pageIndex`, `category` (`rasterization | unreadable | unsupported_structure`), and `messageKey` (German catalog key, e.g. `IMP-006`). It is shown here only because port signatures use it.

`ImportRejectionKind` in the code block above is owned by T014 (`errors.dart`) because the import exceptions use it; T013 imports it and does not redeclare it.

```dart
final class SourceIntegrity {
  final bool readable;
  final String? actualSha256;
  final int? pageCount;
  final List<PageFailure> pageFailures;
}
```

**Contract**
- Cancellation throws `ImportCancelledException` and leaves no `meta`, `head`, `rev`, `src`, or list entry (FR-009).
- Password protection is reported only when the parser positively identifies encryption; otherwise `unknownReason` (FR-007).
- The method returns only after the encrypted source is written, read back, and hash-verified. No partial source object is visible to the library.
- The picked file is never modified; the adapter opens it read-only and drops URI permission after staging (FR-004).

### 2.2 `PageRasterPort`

```dart
final class RasterRequest {
  final String sourceId;
  final int pageIndex;
  final double scale;            // 1.0 == 72 dpi PDF points
  final RasterFormat format;     // rgba8888 | gray8
  final int maxDimensionPx;      // safety cap, default 4096
}

final class RasterImage {
  final Uint8List bytes;
  final int width;
  final int height;
  final int bytesPerRow;
  final RasterFormat format;
  final CapabilityEvidence evidence;
}

abstract interface class PageRasterPort implements PlatformCapability {
  Future<PageGeometry> pageDimensions(String sourceId, int pageIndex);
  Future<RasterImage> renderPage(RasterRequest request);
  Future<void> evict(String sourceId);
}
```

**Contract**
- Rendering is byte-faithful to the source page; no rotation or crop beyond PDFium's standard page rendering of the declared display box.
- Analysis uses `gray8` at 200 dpi equivalent (`scale = 200/72`); UI uses RGBA.
- Render failure maps to `RenderException` and never mutates stored data.
- Decrypted bytes are not cached outside process memory; `evict` releases page/document handles.

### 2.3 `OcrPort`

```dart
final class OcrRequest {
  final RasterImage image;
  final int pageIndex;
  final String languageHint;     // 'de' for production
}

final class OcrBlock {
  final Rect rect;               // source-page display points
  final String text;
  final double confidence;       // 0..1, best effort
  final List<OcrLine> lines;
}

abstract interface class OcrPort implements PlatformCapability {
  Future<List<OcrBlock>> recognize(OcrRequest request);
  Future<void> dispose();
}
```

**Contract**
- Fully on-device; the adapter must not open sockets (verified by instrumentation with radios off).
- Input is the analysis raster; output rectangles are converted by the adapter using the same page geometry as `PageRasterPort`.
- OCR failure is recoverable: the pipeline continues with geometry-only detection and lowers confidence; the page is not marked failed unless the raster itself failed (FR-017).

### 2.4 `SecureStorePort`

```dart
enum StoreKind { document, template }

final class StoreStatus {
  final bool keyAvailable;
  final int objectCount;
  final int totalBytes;
  final CapabilityEvidence evidence;
}

final class StoredMeta {
  final String id;
  final StoreKind kind;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? latestRevisionId;
  final DateTime? lastDurableAt;
  final bool readable;
  final String? unreadableReasonCode;
}

final class LoadedDocument {
  final DocumentMeta meta;
  final RevisionContent content;       // see data-model
  final Uint8List sourceBytes;         // decrypted, bounded; caller must release
  final CapabilityEvidence evidence;
}

abstract interface class SecureStorePort implements PlatformCapability {
  Future<StoreStatus> status();

  Future<StoredMeta> createDocument(CreateDocumentRequest request);
  Future<StoredMeta> saveRevision(SaveRevisionRequest request);   // atomic, verified
  Future<LoadedDocument> loadDocument(String documentId);
  Future<Uint8List> readSignature(String documentId, String assetId);
  Future<void> writeSignature(WriteSignatureRequest request);
  Future<List<StoredMeta>> list(StoreKind kind);
  Future<void> delete(StoreKind kind, String id, DeleteConfirmation confirmation);

  Future<StoredMeta> createTemplate(CreateTemplateRequest request);
  Future<StoredMeta> saveTemplateVersion(SaveTemplateVersionRequest request);
  Future<LoadedTemplate> loadTemplate(String templateId, {String? versionId});

  Future<RecoveryStamp> recoveryStamp(String id, StoreKind kind);
}

final class RecoveryStamp {
  final String? verifiedRevisionId;
  final DateTime? committedAt;
  final bool headCorrupt;
  final bool fellBackToOlderRevision;
}
```

`StoredMeta` is the single port-level list read model. It is projected from the persisted `DocumentMeta` or `TemplateMeta`; `DocumentSummary` in `data-model.md` is a UI projection of `StoredMeta` plus derived counts, not a second persisted type (T095).

**Contract**
- `saveRevision` returns success only after the new head is written and read back (FR-047).
- `delete` requires an explicit `DeleteConfirmation` naming the item; it deletes the aggregate's objects and records the deletion in the operation result. No other document/template is touched (FR-053/FR-099).
- `status` exposes key availability; a missing key does not throw for the whole store, only for affected loads (`SAVE-002`) (FR-052).
- `loadDocument` fails with `KeyUnavailableException` or `CorruptDataException`; other documents remain loadable.
- Storage exhaustion throws `StorageFullException`; the last durable head is untouched (FR-074/FR-075).
- No method accepts an arbitrary path. Object names are server-side (adapter-side) generated.

### 2.5 `PdfExportPort`

```dart
final class ExportRequest {
  final String documentId;
  final String revisionId;
  final ExportPlan plan;               // contracts/export-plan.md
  final ExportOptions options;         // flatten=true, embedFonts=true
}

final class ExportResult {
  final ExportArtifact artifact;
  final CapabilityEvidence evidence;
}

abstract interface class PdfExportPort implements PlatformCapability {
  Future<ExportValidation> validate(ExportPlan plan);
  Future<ExportResult> export(ExportRequest request);
  Future<Uint8List> readArtifact(String artifactId);   // for preview; bounded
  Future<void> deleteArtifact(String artifactId);
}
```

`ExportPlan`, `ExportValidation`, `ExportArtifact`, and `ArtifactVerification` are canonical `feldexa_export` contract-model types owned by T022; `feldexa_export` builds plans, `feldexa_ports` only consumes them.

**Contract**
- `validate` returns blocking warnings (overflow/misplacement) before any file is written (FR-068).
- `export` writes to a temp name, verifies by reopening, checks page count and media boxes, confirms no interactive form fields, then atomically renames. Failure removes the temp file (FR-072).
- The source document and stored working document are never modified (FR-073).
- The produced file is self-contained and flattened; the exported PDF is a normal PDF with no AcroForm widgets (FR-069).

### 2.6 `DeliveryPort`

```dart
enum DeliveryAction { save, share, print }

abstract interface class DeliveryPort implements PlatformCapability {
  Future<DeliveryOutcome> deliver({
    required DeliveryAction action,
    required String artifactId,
  });
}

final class DeliveryOutcome {
  final DeliveryAction action;
  final bool completed;
  final String? userVisibleLocationHint;  // German, no internal path
  final CapabilityEvidence evidence;
}
```

**Contract**
- `save` uses SAF `ACTION_CREATE_DOCUMENT`; the app never requests broad storage permission.
- `share` uses the Android share sheet through a `FileProvider` URI; `print` uses the system print flow.
- User cancellation is `completed: false, cancelled` and is not an error.
- Temporary preview bytes are removed after delivery/dismissal.

### 2.7 `LifecyclePort`

```dart
enum AppLifecycleSignal { resumed, inactive, paused, detached }

abstract interface class LifecyclePort implements PlatformCapability {
  Stream<AppLifecycleSignal> get signals;
}
```

**Contract**: `paused`/`inactive` triggers an autosave flush attempt before the app may be killed. Delivery is best-effort at OS level; the last verified commit is the only durability claim.

### 2.8 `ClockPort` and `IdPort`

```dart
abstract interface class ClockPort implements PlatformCapability {
  DateTime nowUtc();
}

abstract interface class IdPort implements PlatformCapability {
  String newId();                     // UUIDv4 in production
  String newIdempotencyKey();
}
```

Tests inject fixed clocks and deterministic ID sequences. Production uses system time and `Random.secure()`.

### 2.9 `DiagnosticsPort`

```dart
abstract interface class DiagnosticsPort implements PlatformCapability {
  void event(String code, {Map<String, Object?> scalarFields = const {}});
  Future<void> clear();
}
```

**Contract**: on-device only; no document content, names, text, values, or paths; scalar fields limited to enums, counts, durations, and error codes. Size-capped ring buffer. Never transmitted (FR-080/FR-081).

### 2.10 Port-local DTOs and enums

These declarations complete §2. They are owned by T013 and live under `packages/feldexa_ports/lib/src/dto/`. Canonical types (`Page`, `SourceFileRef`, `ConfirmedField`, `RevisionContent`, `RevisionKind`, `StoredTemplate`, `ExportPlan`, `ExportValidation`, `ExportArtifact`, `ArtifactVerification`) come from §1.

```dart
final class OcrLine {
  final Rect rect;
  final String text;
  final double confidence;
}

final class LoadedTemplate {
  final StoredTemplate template;
  final Uint8List sourceBytes;      // decrypted, bounded; caller must release
  final CapabilityEvidence evidence;
}

final class CreateDocumentRequest {
  final String title;
  final SourceFileRef source;       // immutable encrypted source already staged
}

final class SaveRevisionRequest {
  final String documentId;
  final String? expectedHead;       // null only before the first revision
  final RevisionContent content;
  final RevisionKind kind;          // autosave | explicit | recovery
}

final class CreateTemplateRequest {
  final String title;
  final SourceFileRef source;
  final List<Page> pages;
  final List<ConfirmedField> fields;
  final List<String> fieldOrder;
}

final class SaveTemplateVersionRequest {
  final String templateId;
  final String? expectedHead;
  final List<Page> pageSnapshot;
  final List<ConfirmedField> fieldSnapshot;
}

final class WriteSignatureRequest {
  final String documentId;
  final String assetId;
  final Uint8List bytes;
  final String sha256;
}

final class DeleteConfirmation {
  final String title;
  final bool acknowledged;
}

final class ExportOptions {
  final bool flatten;               // default true
  final bool embedFonts;            // default true
}
```

`RasterFormat` is `enum RasterFormat { rgba8888, gray8 }`. `ImportRejectionKind` is owned by T014 (`errors.dart`) because the import exceptions use it; `StoreKind`, `DeliveryAction`, and `AppLifecycleSignal` retain their declarations in §2.4, §2.6, and §2.7.

---

## 3. Error taxonomy

All errors extend `FeldexaException` with `code` (stable catalog code, never shown in the UI), `messageKey` (ARB key resolved to German at the UI boundary), `message` (stable machine key, never a German sentence), `retryable`, and `severity`. The full German text lives in [error-catalog.de.md](./error-catalog.de.md).

| Exception | Code prefix | Retryable | Maps to FR |
| --- | --- | --- | --- |
| `ImportRejectedException(kind)` | `IMP-*` | no | FR-005…FR-010 |
| `ImportCancelledException` | `IMP-000` | yes | FR-009 |
| `StorageFullException` | `SAVE-001` | yes after freeing space | FR-074…FR-077 |
| `KeyUnavailableException` | `SAVE-002` | no | FR-052 |
| `CorruptDataException` | `SAVE-003` | no | FR-047/FR-052 |
| `StorageWriteException` | `SAVE-003` | yes | FR-047 |
| `SecurityException` | `PLT-002` | no | platform guard |
| `SchemaTooNewException` | `SAVE-005` | no | FR-044 |
| `ExportBlockedException(List<String> fieldIds)` | `EXP-001` | yes | FR-068 |
| `ExportFailedException` | `EXP-002` | yes | FR-072 |
| `RenderException` | `PAGE-001` | yes | FR-010/FR-019 |
| `OcrUnavailableException` | `REC-001` | yes (geometry-only fallback) | FR-017 |
| `SimulatedInProductionException` | `SIM-001` | no | Principle II |
| `UnsupportedOperationException` | `PLT-001` | no | platform guard |

Catalog-only codes such as `SAVE-004`, `SAVE-006`, `SAVE-007`, `EXP-003`–`EXP-006`, `REC-002`–`REC-004`, `PLT-003`/`PLT-004`, `TPL-*`, `DEL-*`, `DATE-*`, `NUM-001`, `FLD-*`, and `PRIV-001` are not separate exception classes unless a row appears above; they are carried by the nearest typed exception or the operation result. `SAVE-003` has two concrete causes (`StorageWriteException`, `CorruptDataException`) and must never collapse into an optimistic success.

Rules:
- Exceptions never include raw bytes, names, text, or paths in `toString()`; structured fields are limited to codes, counts, indices, and durations.
- A failure must be visible in German; no silent catch. Recovery actions are part of the catalog.

---

## 4. Registry contract

```dart
abstract interface class AdapterRegistry {
  DocumentImportPort get import;
  PageRasterPort get raster;
  OcrPort get ocr;
  SecureStorePort get store;
  PdfExportPort get export;
  DeliveryPort get delivery;
  LifecyclePort get lifecycle;
  ClockPort get clock;
  IdPort get ids;
  DiagnosticsPort get diagnostics;

  bool get isDevelopmentEnvironment;
  bool get hasSimulatedCapabilities;
  List<CapabilityDescriptor> get descriptors;
}
```

`AdapterRegistry` is owned by T013 (`registry.dart`); it is an interface, not an implementation.

**Selection**
- `registry_android.dart` — real adapters only (`isDevelopmentEnvironment: false`, `hasSimulatedCapabilities: false`).
- `registry_web.dart` — simulated import/OCR/store/export/delivery + real PDFium raster + web lifecycle/clock/ids/diagnostics (`isDevelopmentEnvironment: true`, `hasSimulatedCapabilities: true`).
- `registry_unsupported.dart` — throws `PLT-001` for every capability (used for unsupported compile targets and tests).
- Selection uses conditional imports, never `kIsWeb` branches inside adapters.
- Production bootstrap: if `kReleaseMode && registry.hasSimulatedCapabilities` → fail fast with `SIM-001`.

**Test seam**: `feldexa_testkit` provides a `FakeRegistry` with deterministic clock, ID sequence, scripted lifecycle, and fault-injecting store/export adapters.

---

## 5. Port-to-requirement traceability

| Port | Requirements |
| --- | --- |
| `DocumentImportPort` | FR-001…FR-010, FR-095, FR-096, FR-078 |
| `PageRasterPort` | FR-003, FR-010, FR-018, FR-024, FR-034, FR-086, FR-089 |
| `OcrPort` | FR-011, FR-013, FR-019, FR-079 |
| `SecureStorePort` | FR-043…FR-053, FR-056…FR-060, FR-074…FR-077, FR-097…FR-106 |
| `PdfExportPort` | FR-062…FR-073 |
| `DeliveryPort` | FR-070, FR-071 |
| `LifecyclePort` | FR-045, FR-046, FR-051 |
| `DiagnosticsPort` | FR-080…FR-082 |
| Registry guards | FR-087, FR-088, FR-089 |
