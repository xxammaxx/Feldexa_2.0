# Contract: Flutter ↔ Android Platform Channel

**Feature**: `001-scanned-form-workflow` | **Dart side**: `packages/feldexa_adapters_android` | **Kotlin side**: `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/`

The platform channel is the only boundary between shared Dart and Android production code. It is deliberately small, typed, validated, and free of document content in errors/logs. The Kotlin side implements capabilities; it must not contain UI, form logic, geometry decisions, layout, or field detection.

---

## 1. Channels

| Channel | Type | Purpose |
| --- | --- | --- |
| `de.feldexa/platform` | `MethodChannel` | asynchronous start requests, synchronous request/response capabilities, and cancellation |
| `de.feldexa/events` | `EventChannel` | lifecycle signals and coalesced long-operation progress; never terminal results |
| `de.feldexa/results` | `EventChannel` | terminal `operation.result` for accepted asynchronous operations, with replay for a late listener |
| `de.feldexa/import` | `MethodChannel` (activity-bound) | picker result delivery; registered by `MainActivity` |

All method names are namespaced: `<domain>.<action>`. Payloads are `Map<String, Object?>` with a `schemaVersion` integer; binary payloads are `Uint8List` (never Base64 strings). Unknown top-level fields are rejected with `PLT-003` to catch version drift early.

Methods are either **synchronous** (the `de.feldexa/platform` reply is the terminal result) or **asynchronous** (the reply is a reliable start reply carrying `operationId`; progress follows on `de.feldexa/events` and the terminal result on `de.feldexa/results`). §2.4 is normative for both.

The plugin facade is `FeldexaPlugin`; it delegates to services:

```text
FeldexaPlugin
├── ImportService        (SAF, streaming staging, preflight coordination)
├── PdfPreflight         (PDFBox parse/geometry/encryption/damage)
├── OcrService           (bundled ML Kit Latin)
├── KeystoreService      (per-document/template KEKs, DEK wrap/unwrap)
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

Long operations return `PLT-004` (`cancelled`) when the user cancels. After an asynchronous start reply, cancellation is delivered as the terminal `operation.result` with `error.code = "PLT-004"`; before a start reply there is no operation id and the start rejection is a `PlatformException`. Cancellation must leave no visible partial state; the operation is responsible for deleting its own staged files.

### 2.4 Asynchronous start reply and terminal result

> **Owner decision (T024, 2026-11-15):** a reliable start reply carries
> `operationId`; progress and the terminal result follow on clearly defined
> channels. This supersedes the earlier interpretation that no result-side id was
> authorized. No other result signature or method is introduced.

The following methods are asynchronous:

`import.pickAndImport`, `import.verifySource`, `store.saveRevision`, `store.writeSignature`,
`store.createTemplate`, `store.saveTemplateVersion`, `ocr.recognize`,
`export.validate`, `export.render`.

All other methods are synchronous and retain the ordinary `MethodChannel` result.

**Start reply (authoritative acceptance).** After payload validation, service lookup, aggregate/SAVE-006 admission, and bounded-queue admission, the `de.feldexa/platform` call returns immediately with only:

```json
{ "schemaVersion": 1, "ok": true, "data": { "operationId": "…" } }
```

`data` contains no method-specific response data. `operationId` is a UUID. The reply is the reliable source of the id; no progress event is required to learn it. A validation, service-availability, queue-capacity, or concurrent-save rejection returns a `PlatformException` instead and creates no operation; in that case no result event is emitted.

**Terminal result.** Exactly one terminal result is produced for an accepted operation and emitted on `de.feldexa/results`:

```json
{
  "schemaVersion": 1,
  "event": "operation.result",
  "operationId": "…",
  "ok": true,
  "data": { }
}
```

On failure or cancellation, `data` is absent and `error` is present:

```json
{
  "schemaVersion": 1,
  "event": "operation.result",
  "operationId": "…",
  "ok": false,
  "error": {
    "code": "SAVE-001",
    "message": "save.storageFull",
    "details": {
      "schemaVersion": 1,
      "category": "storageFull",
      "retryable": true,
      "pageIndex": null,
      "fieldCount": null,
      "durationMs": 1234
    }
  }
}
```

`error.code`, `error.message`, and `error.details` use the same §2.2 contract as `PlatformException`; post-start failures are never thrown as `PlatformException` because the start reply was already sent.

**Ordering and race rules.**

- The start reply and the terminal result are independent signals. The terminal result may be published before the start reply is delivered when the worker finishes immediately; Dart MUST buffer an unknown `operationId` result and reconcile it with the start reply.
- Progress events are best-effort and may be duplicated, coalesced, or missed. They never replace the terminal result.
- A result may be delivered after `cancel.operation` returns `true`; that result is `PLT-004`.
- `cancel.operation` returns `false` when the id is unknown, invalid, or already terminal.
- After a terminal result, further progress for that operation is stale and MUST be ignored.

**Missing listener, replay, and retention.** Completed results are retained in memory for the current engine/session in a bounded store (at most 64 results, oldest evicted first). On every `de.feldexa/results` listener attach, all retained results are replayed; duplicates are allowed and Dart MUST deduplicate by `operationId`. On listener detach, results remain retained and are replayed on the next attach. If a result is evicted before any listener attaches, it is no longer recoverable; the start reply still proves acceptance. Results are never persisted; process death loses them.

**Lifecycle.** Activity configuration changes do not clear retained results. `onDestroy`/engine detach cancels workers, clears the result store, and stops emitting results; no result is delivered after teardown. The Kotlin side does not persist or retry results.

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

This is an asynchronous method (§2.4). The immediate reply is the start reply `{ "operationId": "…" }`. The following is the terminal result `data`:

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

Errors after the start reply are terminal result errors: `IMP-001` password-protected, `IMP-002` unreadable/truncated, `IMP-003` missing, `IMP-004` not a PDF/unsupported, `IMP-005` unknown reason, `IMP-006` partially unreadable (success with page failures — see below), `IMP-007` too large, `SAVE-001` no space, `PLT-004` cancelled. Validation/queue errors before acceptance are `PlatformException`s and create no operation.

For `IMP-006`, the terminal result **succeeds** with `pages[].unreadable = true` and a `pageFailures` array; it does not use the error branch. This is the only partial-import case and it creates a document (FR-010).

### `import.verifySource`

Asynchronous (§2.4). Request `{ "schemaVersion":1, "sourceId":"…" }`; start reply carries `operationId`; terminal result `data` is `{ "readable":true, "sha256":"…", "pageCount":3, "pageFailures":[] }`.

### `import.discardStaged`

Synchronous internal cleanup for a failed import: `{ "txnId":"…" }` → `{ "removed": true }`. Idempotent. This is not an operation and has no progress/result event.

---

## 4. Methods — secure store

The asynchronous methods are `store.writeSignature`, `store.saveRevision`,
`store.createTemplate`, and `store.saveTemplateVersion` (§2.4); their Response below
is terminal result `data`. The remaining store methods are synchronous.

| Method | Request | Response |
| --- | --- | --- |
| `store.status` | `{}` | `{ keyAvailable, objectCount, totalBytes }` |
| `store.list` | `{ "kind":"document"\|"template" }` | `{ items:[StoredMeta…] }` |
| `store.readSource` | `{ "documentId" }` | `Uint8List` (decrypted, capped 80 MiB) |
| `store.readSignature` | `{ "documentId", "assetId" }` | `Uint8List` (PNG) |
| `store.writeSignature` | `{ "documentId", "assetId", "bytes", "sha256" }` | `{ verified:true }` |
| `store.saveRevision` | `{ "documentId", "revision": {…}, "expectedHead": "…", "kind":"autosave"\|"explicit"\|"recovery" }` | start reply, then `{ revisionId, committedAt, sha256, verified:true }` |
| `store.createTemplate` | `{ "template": {…}, "revision": {…} }` | `StoredMeta` |
| `store.saveTemplateVersion` | `{ "templateId", "version": {…}, "expectedHead":"…" }` | `{ versionId, versionNumber, verified:true }` |
| `store.loadDocument` | `{ "documentId" }` | `{ meta, revision, head }` (no source bytes) |
| `store.loadTemplate` | `{ "templateId", "versionId": null }` | `{ meta, version, head }` |
| `store.delete` | `{ "kind", "id", "confirm": { "title", "acknowledged": true } }` | `{ deleted:true, freedBytes }` |
| `store.recoveryStamp` | `{ "kind", "id" }` | `{ verifiedRevisionId, committedAt, headCorrupt, fellBackToOlderRevision }` |

Rules:
- `saveRevision` uses optimistic concurrency: `expectedHead` must equal the current verified head, otherwise `SAVE-006` (concurrent write) and the caller re-reads. The app is single-user, but autosave/lifecycle races are real. A second concurrent save for the same `documentId` is rejected **before** the start reply with `PlatformException("SAVE-006")`; an `expectedHead` mismatch discovered by the storage service after the start reply is a terminal `operation.result` error with `SAVE-006`.
- `store.loadDocument` returns no source bytes; the app calls `readSource` once, then releases the buffer when the viewport closes. The adapter may cache the decrypted buffer only in memory and only for the open document.
- `store.delete` validates `confirm.acknowledged == true`. For a readable aggregate, `confirm.title` must equal the stored title (case-sensitive, trimmed); for an unreadable aggregate it must equal the stored "Nicht lesbar" placeholder. The confirmation UI still presents a destructive confirmation for the localized unreadable state. Deletion removes the aggregate's objects first and its own KEK alias last; no other alias is touched.
- `store.status.keyAvailable` is a store-level summary: false when at least one known aggregate key is unavailable or a global provider/reset condition exists. It does not identify the context and does not make the whole store fail; per-aggregate detail comes from `store.list` (`StoredMeta.readable`/`unreadableReasonCode`) and the `storage.status` event, whose `SAVE-002`/`SAVE-008` code distinguishes aggregate from global failure.
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

Asynchronous (§2.4): the immediate reply is the start reply `{ "operationId": "…" }`; the following is the terminal result `data`:

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

Errors after the start reply are terminal result errors: `REC-001` OCR unavailable, `REC-002` OCR failed. Validation/queue errors before acceptance are `PlatformException`s (`PLT-003`) and create no operation.

---

## 6. Methods — export

`export.validate` and `export.render` are asynchronous (§2.4); their Response below is terminal result `data`. `export.readArtifact` and `export.deleteArtifact` are synchronous.

| Method | Request | Response |
| --- | --- | --- |
| `export.validate` | `{ "plan": {…} }` | start reply, then `{ ok:true, warnings:[…] }` or terminal `EXP-001/003/004` |
| `export.render` | `{ "plan": {…} }` | start reply, then `{ artifactId, pageCount, byteSize, sha256, verification:{…} }` |
| `export.readArtifact` | `{ "artifactId" }` | `Uint8List` (PDF, for preview) |
| `export.deleteArtifact` | `{ "artifactId" }` | `{ deleted:true }` |

Rules:
- The applier recomputes the CTM from page geometry and rejects a plan whose `ctm` differs by more than 0.01.
- `export.render` runs on a background executor; progress is emitted on `de.feldexa/events` as `{ "event":"export.progress", "operationId":"…", "phase":"importing\|drawing\|verifying\|finalizing", "pageIndex":0, "fraction":0.4 }`.
- Progress events contain no content, labels, or values. They are best-effort and never replace the terminal result.
- `export.render` must complete verification (export-plan §5.8) before the terminal result is published; a returned artifact is always verified.
- `export.readArtifact` is bounded and only serves the current session's artifact; unknown/expired IDs throw `EXP-002` synchronously.
- `export.validate`/`export.render` failures after the start reply are terminal result errors: `EXP-001` blocked by content, `EXP-002` export failed, `EXP-003` geometry invalid, `EXP-004` missing glyph, `EXP-005` source unreadable, `EXP-006` page not copiable, `SAVE-001` no space, `PLT-004` cancelled. Validation/queue errors before acceptance remain `PlatformException`s.

---

## 7. Methods — delivery

Delivery methods are synchronous; the `de.feldexa/platform` reply is the terminal result and no `operation.result` is emitted.

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

### 8.1 `de.feldexa/events`

`de.feldexa/events` emits maps:

| Event | Payload | Notes |
| --- | --- | --- |
| `lifecycle` | `{ "state": "resumed"\|"inactive"\|"paused"\|"detached" }` | forwarded from `MainActivity` |
| `operation.progress` | `{ "operationId", "kind":"import\|analyze\|save\|export", "phase", "fraction", "pageIndex"? }` | coalesced; no content; best-effort |
| `export.progress` | `{ "operationId", "phase":"importing\|drawing\|verifying\|finalizing", "pageIndex"?, "fraction" }` | coalesced export alias from §6; no content; best-effort |
| `storage.status` | `{ "scope":"store"\|"aggregate", "kind":"document"\|"template"\|null, "itemId": string\|null, "keyAvailable": bool, "reasonCode": null\|"SAVE-002"\|"SAVE-008" }` | aggregate or global key error/resume; global uses `scope:"store"` with null kind/itemId; no title or content |
| `import.pickerResult` | `{ "correlationId", "cancelled": bool }` | result of the SAF picker |

Progress is best-effort; Dart MUST tolerate duplicate/missed progress events and MUST ignore progress after the terminal result. Progress never carries terminal data.

### 8.2 `de.feldexa/results`

`de.feldexa/results` emits exactly the `operation.result` maps defined in §2.4:

- success: `{ schemaVersion, event:"operation.result", operationId, ok:true, data }`
- failure/cancellation: `{ schemaVersion, event:"operation.result", operationId, ok:false, error:{ code, message, details } }`

The start reply is the reliable acceptance signal; the result channel is the only
terminal-data channel for asynchronous methods. Results are retained/replayed as
defined in §2.4: bounded at 64, replayed on listener attach, duplicate-tolerant,
deduplicated by `operationId`, and cleared on teardown. A result may arrive before
the start reply; Dart buffers unknown ids.

---

## 9. Threading, lifecycle, and cancellation

- Method call handlers return immediately. For asynchronous methods, the handler
  returns the start reply after bounded-queue admission; for synchronous methods it
  returns the terminal result. Work is dispatched to a bounded background executor;
  the main thread must never decrypt, parse PDFs, run OCR, or write files.
- The executor has at most 2 workers; import/export/OCR are serialized per document to avoid interleaved writes. A second concurrent save for the same document is rejected before a start reply with `SAVE-006`; a storage-level `expectedHead` mismatch after a start reply is the terminal result error `SAVE-006`.
- `MainActivity.onPause/onStop` forwards lifecycle; the Dart autosave coordinator flushes. The Kotlin side must not attempt its own autosave.
- **Cancellation.** `cancel.operation` (`{ "operationId" }` → `{ "cancelled": bool }`) is synchronous. Before the start reply no id exists and cancellation is impossible; after the start reply and before the terminal result, the facade cancels queued work immediately or flags running work for cooperative cancellation, and publishes terminal `PLT-004`. A queued cancellation frees its bounded queue slot. Cancellation cleans staged files and leaves no visible partial state. After a terminal result, cancellation returns `false`.
- **Terminal exactly once.** An accepted operation publishes one terminal result. Replay can duplicate delivery of the same stored result; Dart deduplicates by `operationId`. A start rejection (`PlatformException`) creates no operation and therefore no result.
- **Race.** Terminal result publication is independent of start-reply delivery; result-before-start is legal. Progress may arrive before or after either and is never authoritative.
- **Missing listener.** Completed results are retained and replayed when the result listener attaches; detaching the listener does not delete results. Results are bounded (64) and not persisted, so an evicted result is unrecoverable; the start reply remains the acceptance proof.
- **Lifecycle.** Activity configuration changes retain the engine result store. `onDestroy`/engine detach cancels workers, clears the result store, stops result emission, closes PDFium/PDFBox documents, and deletes session export artifacts. Process death loses in-memory results and is handled by the storage recovery contract, not by the channel.

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
| Async start reply | JVM contract + Emulator instrumentation | every asynchronous method returns `{operationId}` immediately with no method data; synchronous methods keep their direct result |
| Async terminal result | JVM contract + Emulator instrumentation | one `operation.result` success carries the method data; one failure/cancellation carries `{code,message,details}`; post-start failures never arrive as `PlatformException` |
| Async start rejection | JVM contract + Emulator instrumentation | validation, missing service, queue overflow, and concurrent same-document save reject with `PlatformException` and emit no result |
| Async race and late listener | JVM contract + Emulator instrumentation | a result completed before start-reply delivery or before listener attach is retained/replayed; duplicate replay is deduplicated by `operationId` |
| Async cancellation | JVM contract + Emulator instrumentation | queued or running cancellation yields one terminal `PLT-004` result; cancellation after terminal returns `false`; queued cancellation frees the bounded slot |
| Async lifecycle | JVM contract + Emulator instrumentation | result listener detach/reattach replays retained results; engine teardown clears the result store and emits nothing afterwards |
| Encryption detection | Emulator instrumentation | synthetic password-protected PDF → `IMP-001`; truncated PDF → `IMP-002`; random bytes → `IMP-004`; unreadable file → `IMP-005` |
| No plaintext leak | Emulator instrumentation | scan `filesDir`, `cacheDir`, logs, and Recents thumbnail after failures → no `%PDF`, no title, no value |
| Keystore loss | Emulator instrumentation | delete one document's alias → that document gets `SAVE-002`; sibling document and template load; no file deleted; repeat for one template alias. Invalidate all aliases or make the provider unavailable → global `SAVE-008`, no per-aggregate "others unaffected" claim, no file deleted |
| Interrupted commit | Instrumentation with fault hook | kill/abort at each step → previous head readable or verified fallback, never a false success |
| OCR offline | Instrumentation | radios off → `ocr.recognize` succeeds; no sockets opened |
| Export verification | Instrumentation | returned artifact reopens, page count/boxes match, no AcroForm, text extraction contains German characters |
| Delivery | Instrumentation/manual | save writes to the chosen URI and verifies size; share grants a readable URI; print dialog opens |
| Concurrency | Instrumentation | two simultaneous `saveRevision` with the same `expectedHead` → one start reply, one immediate `SAVE-006`; storage-level mismatch after a start is a terminal result `SAVE-006` |
| Lifecycle | Instrumentation | backgrounding during edits flushes and reports saved only after verification |
