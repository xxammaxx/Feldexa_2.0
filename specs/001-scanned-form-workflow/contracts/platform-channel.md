# Contract: Flutter ↔ Android Platform Channel

**Feature**: `001-scanned-form-workflow` | **Dart side**: `packages/feldexa_adapters_android` | **Kotlin side**: `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/`

The platform channel is the only boundary between shared Dart and Android production code. It is deliberately small, typed, validated, and free of document content in errors/logs. The Kotlin side implements capabilities; it must not contain UI, form logic, geometry decisions, layout, or field detection.

---

## 1. Channels

| Channel | Type | Purpose |
| --- | --- | --- |
| `de.feldexa/platform` | `MethodChannel` | request/response capabilities |
| `de.feldexa/events` | `EventChannel` | lifecycle signals and long-operation progress/cancellation |
| `de.feldexa/import` | `MethodChannel` (activity-bound) | picker result delivery; registered by `MainActivity` |

All method names are namespaced: `<domain>.<action>`. Payloads are `Map<String, Object?>` with a `schemaVersion` integer; binary payloads are `Uint8List` (never Base64 strings). Unknown top-level fields are rejected with `PLT-003` to catch version drift early.

The plugin facade is `FeldexaPlugin`; it delegates to services:

```text
FeldexaPlugin
├── ImportService        (SAF, streaming staging, preflight coordination)
├── PdfPreflight         (PDFBox parse/geometry/encryption/damage)
├── OcrService           (bundled ML Kit Latin)
├── KeystoreService      (master key, DEK wrap/unwrap)
├── EncryptedStore       (FXC1, revisions, atomic commits, sweep)
├── PdfExportService     (PDFBox page import + overlay + verification)
├── DeliveryService      (SAF save, FileProvider share, print)
└── DiagnosticsService   (redacted on-device events)
```

Rendering is not on the channel: `pdfrx` renders from bytes returned by `store.readSource` (real PDFium), keeping one renderer for Web and Android.

---

## 2. Common envelope

### 2.1 Success

```json
{ "schemaVersion": 1, "ok": true, "data": { } }
```

Dart adapters unwrap `data`; the envelope itself is not exposed to application code.

### 2.2 Error

A `PlatformException` with:
- `code`: catalog code (`IMP-002`, `SAVE-001`, …)
- `message`: a stable machine key, **not** a German UI sentence and **not** a path/name
- `details`:

```json
{
  "schemaVersion": 1,
  "category": "storageFull",
  "retryable": true,
  "pageIndex": null,
  "fieldCount": null,
  "durationMs": 1234
}
```

**Forbidden in `message`/`details`**: file paths, content URIs, document titles, original file names, OCR text, field values, signature bytes, page images, stack traces containing paths. Debug builds may log a stack trace locally with all of the above removed; release builds must not log document-related exceptions beyond the code.

### 2.3 Cancellation

Long operations return `PLT-004` (`cancelled`) when the user cancels. Cancellation must leave no visible partial state; the operation is responsible for deleting its own staged files.

---

## 3. Methods — import

### `import.pickAndImport`

Request:

```json
{
  "schemaVersion": 1,
  "maxBytes": 83886080,
  "titleHint": null
}
```

Flow: `MainActivity` launches `OpenDocument` (`application/pdf`), receives the URI, and streams `ContentResolver.openInputStream` through `EncryptedStore.stageSource`. Preflight runs on the staged ciphertext with a decrypting `RandomAccessRead`; on success the initial revision and meta are committed (storage-format §3.2).

Response `data`:

```json
{
  "sourceId": "…",
  "documentId": "…",
  "sha256": "…",
  "sizeBytes": 1234567,
  "pageCount": 3,
  "pages": [
    { "mediaBox": {"x":0,"y":0,"width":595.28,"height":841.89},
      "cropBox": {"x":0,"y":0,"width":595.28,"height":841.89},
      "rotation": 0 }
  ],
  "displayName": "antrag.pdf"
}
```

Errors: `IMP-001` password-protected, `IMP-002` unreadable/truncated, `IMP-003` missing, `IMP-004` not a PDF/unsupported, `IMP-005` unknown reason, `IMP-006` partially unreadable (success with page failures — see below), `IMP-007` too large, `SAVE-001` no space, `PLT-004` cancelled.

For `IMP-006`, the call **succeeds** with `pages[].unreadable = true` and a `pageFailures` array; it does not throw. This is the only partial-import case and it creates a document (FR-010).

### `import.verifySource`

Request `{ "schemaVersion":1, "sourceId":"…" }` → `{ "readable":true, "sha256":"…", "pageCount":3, "pageFailures":[] }`.

### `import.discardStaged`

Internal cleanup for a failed import: `{ "txnId":"…" }` → `{ "removed": true }`. Idempotent.

---

## 4. Methods — secure store

| Method | Request | Response |
| --- | --- | --- |
| `store.status` | `{}` | `{ keyAvailable, objectCount, totalBytes, keyAliasPresent }` |
| `store.list` | `{ "kind":"document"\|"template" }` | `{ items:[StoredMeta…] }` |
| `store.readSource` | `{ "documentId" }` | `Uint8List` (decrypted, capped 80 MiB) |
| `store.readSignature` | `{ "documentId", "assetId" }` | `Uint8List` (PNG) |
| `store.writeSignature` | `{ "documentId", "assetId", "bytes", "sha256" }` | `{ verified:true }` |
| `store.saveRevision` | `{ "documentId", "revision": {…}, "expectedHead": "…", "kind":"autosave"\|"explicit"\|"recovery" }` | `{ revisionId, committedAt, sha256, verified:true }` |
| `store.createTemplate` | `{ "template": {…}, "revision": {…} }` | `StoredMeta` |
| `store.saveTemplateVersion` | `{ "templateId", "version": {…}, "expectedHead":"…" }` | `{ versionId, versionNumber, verified:true }` |
| `store.loadDocument` | `{ "documentId" }` | `{ meta, revision, head }` (no source bytes) |
| `store.loadTemplate` | `{ "templateId", "versionId": null }` | `{ meta, version, head }` |
| `store.delete` | `{ "kind", "id", "confirm": { "title", "acknowledged": true } }` | `{ deleted:true, freedBytes }` |
| `store.recoveryStamp` | `{ "kind", "id" }` | `{ verifiedRevisionId, committedAt, headCorrupt, fellBackToOlderRevision }` |

Rules:
- `saveRevision` uses optimistic concurrency: `expectedHead` must equal the current verified head, otherwise `SAVE-006` (concurrent write) and the caller re-reads. The app is single-user, but autosave/lifecycle races are real.
- `store.loadDocument` returns no source bytes; the app calls `readSource` once, then releases the buffer when the viewport closes. The adapter may cache the decrypted buffer only in memory and only for the open document.
- `store.delete` validates `confirm.acknowledged == true` and `confirm.title` equals the stored title (case-sensitive, trimmed) to prevent accidental deletion; an empty title cannot be confirmed.
- No method accepts a path, URI, or file name. `assetId`, `documentId`, `templateId`, `revisionId` are UUID-validated.
- Revision size cap: 32 MiB plaintext (metadata + field values); larger is rejected with `SAVE-007` (invalid data), because field values are text/signature references only.

---

## 5. Methods — OCR

### `ocr.recognize`

Request:

```json
{
  "schemaVersion": 1,
  "pageIndex": 0,
  "imageWidth": 1654,
  "imageHeight": 2339,
  "pageWidthPt": 595.28,
  "pageHeightPt": 841.89,
  "format": "gray8",
  "bytes": "<Uint8List>",
  "language": "de"
}
```

Response:

```json
{
  "blocks": [
    {
      "text": "Name",
      "rect": { "x": 70.0, "y": 300.0, "width": 40.0, "height": 12.0 },
      "confidence": 0.91,
      "lines": [
        { "text": "Name", "rect": {…}, "confidence": 0.93 }
      ]
    }
  ],
  "engine": "mlkit-latin-bundled-v1",
  "durationMs": 1180
}
```

Rules:
- Coordinates are converted from raster pixels to source-page display points using the supplied page size and image size; no reliance on device density.
- The service must not open sockets; a bundled model is loaded once and reused. A missing model fails with `REC-001` and the caller falls back to geometry-only detection.
- Text is returned to the caller in memory only; it is not logged or cached by the service.
- Images are passed once per page; the service releases its bitmap reference after the call.
- If the page is rotated, the raster is already in display orientation; no extra rotation.

Errors: `REC-001` OCR unavailable, `REC-002` OCR failed, `PLT-003` invalid payload.

---

## 6. Methods — export

| Method | Request | Response |
| --- | --- | --- |
| `export.validate` | `{ "plan": {…} }` | `{ ok:true, warnings:[…] }` or throws `EXP-001/003/004` |
| `export.render` | `{ "plan": {…} }` | `{ artifactId, pageCount, byteSize, sha256, verification:{…} }` |
| `export.readArtifact` | `{ "artifactId" }` | `Uint8List` (PDF, for preview) |
| `export.deleteArtifact` | `{ "artifactId" }` | `{ deleted:true }` |

Rules:
- The applier recomputes the CTM from page geometry and rejects a plan whose `ctm` differs by more than 0.01.
- `export.render` runs on a background executor; progress is emitted on `de.feldexa/events` as `{ "event":"export.progress", "operationId":"…", "phase":"importing\|drawing\|verifying\|finalizing", "pageIndex":0, "fraction":0.4 }`.
- Progress events contain no content, labels, or values.
- `export.render` must complete verification (export-plan §5.8) before returning; a returned artifact is always verified.
- `export.readArtifact` is bounded and only serves the current session's artifact; unknown/expired IDs throw `EXP-002`.

Errors: `EXP-001` blocked by content, `EXP-002` export failed, `EXP-003` geometry invalid, `EXP-004` missing glyph, `EXP-005` source unreadable, `EXP-006` page not copiable, `SAVE-001` no space, `PLT-004` cancelled.

---

## 7. Methods — delivery

| Method | Request | Response |
| --- | --- | --- |
| `delivery.save` | `{ "artifactId", "suggestedName":"Antrag_ausgefuellt.pdf" }` | `{ completed, cancelled, locationHint }` |
| `delivery.share` | `{ "artifactId", "mimeType":"application/pdf" }` | `{ completed, cancelled }` |
| `delivery.print` | `{ "artifactId", "jobName":"Feldexa Dokument" }` | `{ completed, cancelled }` |

Rules:
- `suggestedName` is derived from the document title, sanitized (no path separators, max 120 chars, `.pdf` appended). It is never logged.
- `save` uses `ACTION_CREATE_DOCUMENT`; after writing, the service re-opens the returned URI and verifies the byte count. A mismatch reports failure, not success.
- `share` uses `FileProvider` with a temporary grant and `FLAG_GRANT_READ_URI_PERMISSION`; no `file://` URI is ever used.
- `print` uses `PrintManager`; the system print UI is the authority on completion.
- Delivery never deletes the durable document; it may delete the ephemeral artifact only after the user dismisses the preview or delivery completes.

---

## 8. Events

`de.feldexa/events` emits maps:

| Event | Payload | Notes |
| --- | --- | --- |
| `lifecycle` | `{ "state": "resumed"\|"inactive"\|"paused"\|"detached" }` | forwarded from `MainActivity` |
| `operation.progress` | `{ "operationId", "kind":"import\|analyze\|save\|export", "phase", "fraction", "pageIndex"? }` | coalesced; no content |
| `storage.status` | `{ "keyAvailable": bool, "reasonCode": null\|"SAVE-002" }` | emitted on key errors and on resume |
| `import.pickerResult` | `{ "correlationId", "cancelled": bool }` | result of the SAF picker |

Dart must tolerate duplicate/missed progress events; only the terminal method result is authoritative.

---

## 9. Threading, lifecycle, and cancellation

- Method call handlers return immediately and dispatch work to a bounded background executor; the main thread must never decrypt, parse PDFs, run OCR, or write files.
- The executor has at most 2 workers; import/export/OCR are serialized per document to avoid interleaved writes. A second save for the same document is rejected with `SAVE-006`.
- `MainActivity.onPause/onStop` forwards lifecycle; the Dart autosave coordinator flushes. The Kotlin side must not attempt its own autosave.
- Cancellation: a `cancel.operation` method (`{ "operationId" }` → `{ "cancelled": bool }`) requests cooperative cancellation; services check between pages/chunks. Cancellation cleans staged files and returns `PLT-004`.
- On `onDestroy`, close PDFium/PDFBox documents, cancel workers, and delete session export artifacts.
- Process death during a commit is handled by the storage recovery contract, not by the channel.

---

## 10. Payload validation and limits

| Limit | Value | Rejection |
| --- | --- | --- |
| Source PDF | 80 MiB | `IMP-007` |
| Signature PNG | 2 MiB, ≤ 1024 px long edge | `SAVE-007` |
| Revision JSON | 32 MiB | `SAVE-007` |
| OCR raster | ≤ 4096 px long edge, gray8/RGBA | `PLT-003` |
| Export plan | ≤ 8 MiB JSON, ≤ 500 ops/page, ≤ 100 pages | `PLT-003` |
| Method payload | ≤ 96 MiB total | `PLT-003` |
| UUID strings | strict regex | `PLT-002` |
| Strings | UTF-8, no NUL/control chars, length caps per field | `PLT-003` |

Every string that becomes a UI label is capped (title 200, field label 120, `labelText` 200) and rejected if it contains control characters. JSON parsing uses strict schemas; unknown fields are rejected (`PLT-003`) so a Dart/Kotlin version mismatch fails loudly instead of silently dropping data.

---

## 11. Security and logging rules

1. Never log method payloads, bytes, titles, values, OCR text, or URIs. Log only method name, duration, result code, and payload size.
2. Never include a path in an exception. Use `content://` only transiently inside the service, never in errors or analytics.
3. Never write picker URIs or Keystore data to SharedPreferences or files.
4. Do not enable `WebView` debugging, `dart:developer` HTTP logging, or `Print` statements in release.
5. Do not expose a generic "read any file" or "write any path" method; the channel surface is closed.
6. The release manifest omits `INTERNET`; the debug manifest may add it for Flutter tooling only.
7. `MainActivity` sets `FLAG_SECURE` on the editor/export routes to block screenshots and recents thumbnails of sensitive documents. This must be verified on the emulator (no thumbnail content in Recents).
8. `FileProvider` paths are limited to `cacheDir/feldexa_exports/`; no `filesDir` or root path is shared.

---

## 12. Contract tests

| Test | Class | Assertion |
| --- | --- | --- |
| Payload round-trip | Emulator instrumentation | every method accepts a minimal valid payload and rejects unknown fields, bad UUIDs, oversized payloads |
| Encryption detection | Emulator instrumentation | synthetic password-protected PDF → `IMP-001`; truncated PDF → `IMP-002`; random bytes → `IMP-004`; unreadable file → `IMP-005` |
| No plaintext leak | Emulator instrumentation | scan `filesDir`, `cacheDir`, logs, and Recents thumbnail after failures → no `%PDF`, no title, no value |
| Keystore loss | Emulator instrumentation | delete alias → `SAVE-002`; sibling document loads; no file deleted |
| Interrupted commit | Instrumentation with fault hook | kill/abort at each step → previous head readable or verified fallback, never a false success |
| OCR offline | Instrumentation | radios off → `ocr.recognize` succeeds; no sockets opened |
| Export verification | Instrumentation | returned artifact reopens, page count/boxes match, no AcroForm, text extraction contains German characters |
| Delivery | Instrumentation/manual | save writes to the chosen URI and verifies size; share grants a readable URI; print dialog opens |
| Concurrency | Instrumentation | two simultaneous `saveRevision` with the same `expectedHead` → exactly one success, one `SAVE-006` |
| Lifecycle | Instrumentation | backgrounding during edits flushes and reports saved only after verification |
