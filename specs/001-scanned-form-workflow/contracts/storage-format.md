# Contract: Encrypted Storage Format (`FXC1`)

**Feature**: `001-scanned-form-workflow` | **Implementations**: `android/storage/EncryptedStore.kt`, `android/storage/KeystoreService.kt`, `packages/feldexa_adapters_simulated` (dev only)

This contract defines the on-disk format, key handling, atomic commit protocol, recovery behavior, and failure semantics for documents, templates, revisions, sources, and signature assets. It is security-relevant: changes require review under Principles V, VI, and VII.

**Non-goals**: portability to another device, user-visible passwords, biometrics, cloud backup, and database queries. All are explicitly out of scope.

---

## 1. Directory layout

Root: Android `context.filesDir/feldexa/`, app-private, excluded from backup (`android:allowBackup="false"`, `dataExtractionRules` with no included domains).

```text
feldexa/
├── docs/
│   └── <documentId>/
│       ├── meta.fx1              # mutable metadata (atomic replace)
│       ├── head.fx1              # committed revision pointer (atomic replace)
│       ├── rev/
│       │   └── <revisionId>.fx1  # immutable revision snapshot
│       ├── src/
│       │   └── <sourceId>.fxc    # immutable encrypted original PDF
│       └── sig/
│           └── <assetId>.fxs     # immutable encrypted signature PNG
├── templates/
│   └── <templateId>/
│       ├── meta.fx1
│       ├── head.fx1              # points to latest template version
│       ├── ver/
│       │   └── <versionId>.fx1   # immutable template version
│       └── src/
│           └── <sourceId>.fxc
├── tmp/                          # staging; swept on startup and after commits
└── diagnostics/
    └── redacted.jsonl            # optional, redacted, size-capped
```

Rules:
- IDs are UUIDv4 strings validated against `^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`. Any other name is rejected before filesystem access (no traversal).
- `docs/` and `templates/` are separate namespaces; a document can never be opened as a template or vice versa.
- No thumbnails, no plaintext exports, no OCR text files.
- File permissions: owner-only (Android app sandbox default). No world-readable files, no `MODE_WORLD_*`.

---

## 2. `FXC1` container

All non-ephemeral objects use one container format, version 1.

### 2.1 Header (plaintext)

| Offset | Size | Field | Value / rule |
| --- | --- | --- | --- |
| 0 | 4 | magic | ASCII `FXC1` |
| 4 | 2 | version | `0x0001` big-endian |
| 6 | 2 | flags | bit 0: `chunked`; other bits must be 0 |
| 8 | 1 | keyScheme | `1` = DEK wrapped by the aggregate KEK |
| 9 | 1 | objectKind | `1` meta, `2` revision, `3` source, `4` signature, `5` template version |
| 10 | 2 | reserved | zero |
| 12 | 4 | chunkSize | 1,048,576 for large objects; 65,536 for metadata |
| 16 | 8 | plaintextLength | big-endian |
| 24 | 4 | chunkCount | `ceil(plaintextLength / chunkSize)`, 0 allowed for empty |
| 28 | 8 | noncePrefix | `SecureRandom`, unique per object; IV prefix |
| 36 | 4 | reserved | zero |
| 40 | 2 | wrapIvLength | 12 |
| 42 | 12 | wrapIv | AES-GCM IV for DEK wrapping |
| 54 | 2 | wrappedKeyLength | 48 (32-byte DEK + 16-byte tag) |
| 56 | 48 | wrappedKey | AES-256-GCM(KEK, DEK) |
| 104 | 32 | plaintextSha256 | hash of the complete plaintext |
| 136 | 20 | fileId | `SHA-256(kind ‖ ":" ‖ objectId)` truncated; stable object identity |
| 156 | 4 | headerCrc | CRC-32 of header bytes 0…155 for early corruption detection |
| **160** | | **header size** | |

Notes:
- The header is not encrypted: it contains no document content, only lengths, nonce, wrapped key, and hashes. There is **no separate header MAC** (avoiding GCM nonce reuse). Integrity is enforced by three independent mechanisms: tampering with `wrappedKey`/`wrapIv` makes DEK unwrap fail; tampering with `objectKind`, `chunkSize`, `plaintextLength`, `chunkCount`, `noncePrefix`, or `fileId` makes chunk authentication fail; tampering with `plaintextSha256` fails the verified hash comparison.
- `fileId` binds chunks to the object and prevents cross-object chunk splicing.
- `plaintextSha256` covers the exact plaintext including JSON formatting; it is the value compared against `head.fx1.sha256`.
- Implementations must reject `version > 1`, unknown flags, non-zero reserved bytes, `chunkCount` inconsistent with `plaintextLength`, a chunk size outside `{65_536, 1_048_576}`, a non-zero CRC mismatch, or a wrapped key of the wrong length.
- The KEK is selected from the aggregate context, not stored in the header: `docs/<documentId>/` uses the document's alias and `templates/<templateId>/` uses the template's alias (§2.3). A wrapped key moved to another aggregate fails to unwrap because that aggregate has a different KEK; `fileId` continues to prevent cross-object chunk splicing.

### 2.2 Chunk records

Each chunk is stored sequentially after the header:

```text
[ ciphertextLength bytes ][ 16-byte GCM tag ]
```

- Plaintext chunk length = `min(chunkSize, remainingLength)`; `ciphertextLength == plaintextLength` (AES-GCM does not expand).
- **IV construction (normative)**: `iv = noncePrefix[0..7] ‖ uint32BE(chunkIndex)`, where `noncePrefix` is 8 random bytes stored in header bytes 28…35. A unique DEK and nonce prefix are generated for every object; the same (DEK, noncePrefix, chunkIndex) tuple must never repeat.
- AAD (normative, UTF-8): `"FXC1|" + hex(fileId) + "|" + objectKind + "|" + chunkIndex + "|" + chunkCount + "|" + plaintextLength`.
- Decryption verifies every tag. A truncated final chunk, a missing chunk, a reordered chunk, or a changed `chunkCount` fails with `CorruptDataException` (`SAVE-003`).
- Empty object: `chunkCount = 0`, no chunk records, `plaintextSha256 = SHA-256("")`.

### 2.3 Encryption primitives

| Item | Value |
| --- | --- |
| Payload cipher | AES-256-GCM, 128-bit tag, no padding |
| DEK | 32 bytes from `java.security.SecureRandom` |
| KEK | One Android Keystore AES-256-GCM key per aggregate: `feldexa.doc.v1.<documentId>` for `docs/<documentId>/` and `feldexa.tpl.v1.<templateId>` for `templates/<templateId>/`; `setUserAuthenticationRequired(false)`; StrongBox best-effort when `FEATURE_STRONGBOX_KEYSTORE` is present, TEE otherwise. If StrongBox key generation fails, retry in the TEE; never fall back to software. |
| DEK wrapping | AES-GCM(aggregate KEK, DEK), AAD `"FXC1-DEK"`; IV random 12 bytes stored in header |
| Key export | Prohibited. The app can request unwrap operations; key bytes of the KEK are not retrievable |
| Nonce reuse | Must not occur: random 8-byte prefix per object + chunk counter; regenerating an object requires a new DEK and nonce |

**Keystore failure mapping**:
- Alias missing / key invalidated for one aggregate while at least one other aggregate key remains available → `KeyUnavailableException` (`SAVE-002`) for that aggregate; other aggregates use their own aliases and remain readable.
- A usable aggregate KEK whose wrapped DEK fails GCM authentication (tag mismatch) is an integrity/authentication failure → `CorruptDataException` (`SAVE-003`), not `SAVE-002`; the KEK remains available and no key is deleted. Corrupt chunk data follows the same `SAVE-003` rule (§5).
- Keystore provider unavailable at boot (e.g., locked device before first unlock) → retry once after a short delay; if still unavailable, the operation fails with `KeystoreUnavailableException` (`SAVE-008`) and no partial state. If the provider is available but every stored aggregate key is missing/invalidated (device-wide reset), the same global `SAVE-008` applies; do not emit per-aggregate `SAVE-002` messages that claim other aggregates are unaffected.

**Per-aggregate key lifecycle**:

- A document's alias is created with the aggregate directory before any encrypted object is written. A template's alias is created the same way before its first version commit. Key creation happens before the first ciphertext write; a failure leaves no visible aggregate.
- Deleting a document or template deletes its encrypted objects and directory first, then its alias (§3.6). No other alias is read or deleted.
- At startup, aliases under `feldexa.doc.v1.` or `feldexa.tpl.v1.` that have no corresponding aggregate directory are orphaned aliases and are deleted. An alias with an existing aggregate directory is never removed by the sweep.
- Key availability has two levels. `StoreStatus.keyAvailable` is the T013-compatible, non-fatal store-level summary: false when at least one known aggregate key is unavailable; it does not identify which aggregate or whether the failure is global, and does not make the whole store fail. Per-aggregate detail is reported by `StoredMeta.readable`/`unreadableReasonCode` and by `KeyUnavailableException` (`SAVE-002`), `KeystoreUnavailableException` (`SAVE-008`), or `CorruptDataException` (`SAVE-003`).
- A whole-Keystore reset or device reset invalidates every alias. That is device-wide loss reported as `SAVE-008`, not the per-aggregate `SAVE-002` case; the ciphertext may also be gone. It is disclosed under FR-051 and is not claimed as per-document isolation.

### 2.4 Plaintext formats

| Object | Plaintext |
| --- | --- |
| `meta.fx1` | Canonical JSON `DocumentMeta` / `TemplateMeta` (see data-model §4) |
| `rev/<id>.fx1` | Canonical JSON `RevisionContent` |
| `ver/<id>.fx1` | Canonical JSON `TemplateVersionContent` |
| `src/<id>.fxc` | Raw original PDF bytes, unmodified |
| `sig/<id>.fxs` | PNG bytes, alpha channel, trimmed |

Canonical JSON: sorted keys, UTF-8, no whitespace, UTC ISO-8601 with milliseconds, numbers without trailing zeros.

---

## 3. Atomic commit protocol

### 3.1 Saving a document revision

Preconditions: a valid in-memory snapshot, a current verified head, and the document's aggregate KEK is available. A missing/invalidated aggregate key fails that save with `SAVE-002` and leaves the previous head intact; other aggregates are unaffected.

1. **Serialize** the snapshot to canonical JSON; compute `plaintextSha256`; generate `revisionId`.
2. **Stage** `tmp/<txnId>.part` with `O_CREAT|O_EXCL`, write header + chunks, `fd.sync()`.
3. **Verify** by reopening the staged file, decrypting **all** chunks, recomputing SHA-256, and comparing the header and payload hash. Any mismatch → delete staged file, throw `CorruptDataException`.
4. **Promote** the revision: `rename(tmp/<txnId>.part, rev/<revisionId>.fx1)`; `fsync` the `rev/` directory.
5. **Stage head**: write `head.fx1` with `{revisionId, plaintextSha256, committedAt, parentRevisionId, kind, history}` to `tmp/<txnId>.head`, fsync, verify by decrypting and parsing.
6. **Promote head**: `rename(tmp/<txnId>.head, head.fx1)`, fsync the document directory.
7. **Read-back**: decrypt `head.fx1` and the referenced revision again; compare hashes. Only now may the caller be told `saved`.
8. **Prune**: after step 7 succeeded, compute the keep set from `history` (last 3 autosave + newest explicit + newest recovery + the verified head) and delete only those known-kind, non-kept revision files. Unknown-kind entries and untracked legacy files are retained, never guessed. Then rewrite `head.fx1` atomically with the surviving history entries (removing entries whose files are gone); a crash between deletion and this trim is reconciled on the next save/startup.
9. **Clean** `tmp/<txnId>*`.

**Head history (bounded known-kind order).** `history` is an array of `{revisionId, kind}` entries ordered oldest first, at most 16 entries. `kind` is `autosave`, `explicit`, `recovery`, or `null` for a legacy/unknown entry. It is built from the previous head's history (dropping entries whose files no longer exist), the previous head's own `{revisionId, kind}`, and the new revision. The cap bounds head size; entries older than the cap become untracked and are therefore retained by the pruner. A legacy `head.fx1` without `history` is valid and yields an empty history; no policy pruning occurs until a new history is written. A missing or unknown `kind` is never inferred from revision content or file order.

The durable order for a new revision is: stage data and fsync, read-back verify, set the monotonic revision mtime, `fsync(file)` so the mtime is durable, atomically rename, then fsync the parent directory. Only then does the head history/prune step run.

**Delete durability before history trim.** Pruning may shorten `history` only after the revision-directory fsync that follows the deletes succeeds. If that fsync fails, the head history stays complete, the deletions are not counted as durable, and the next startup/save must retry. This keeps a delete that is lost in a crash tracked, so the resurrected file cannot become untracked and bypass retention. A startup reconciliation follows the same rule: no history trim without a confirmed delete fsync. On retry, even when that attempt deletes nothing because the file is already missing from the namespace, a missing known history entry still triggers the directory fsync before it may be dropped; a save-side history rebuild retains unconfirmed missing entries until that confirmation.

**Bounded history never evicts an unconfirmed entry.** Before a save builds the 16-entry capped history, every known history entry already missing from the namespace must be confirmed absent by the revision-directory fsync. If that fsync fails, the save is refused with retryable `SAVE-003` before the new revision is staged or the head changes; the previous head and all revisions remain untouched. The cap therefore only drops entries that are durably absent or still exist (the latter remain untracked files, conservatively retained). A longer pending history or a separate pending-deletion ledger would be an alternative, but it requires an owner decision; this contract chooses the fail-closed refusal so no unconfirmed entry is silently discarded and the 16-entry bound remains intact.

If any step fails before step 6, the previous `head.fx1` and all previous revisions remain valid; the operation fails. If step 6 fails after rename (unlikely), a startup recovery check detects a head pointing to a missing revision and falls back (see §4).

### 3.2 Import commit (new document)

The importer supplies the document ID and initial revision to the store; the store persists those exact values once. A duplicate visible document is rejected without overwriting existing data. The import call returns only after the store has verified the initial commit.

Key setup: create `docs/<documentId>/` and alias `feldexa.doc.v1.<documentId>` before any encrypted object is written. If key creation fails, return `SAVE-002` with no visible document; the startup sweep removes an incomplete directory and its orphan alias.

1. Validate and stage the source object (`src/<sourceId>.fxc`) from the picked stream; count bytes, cap at 80 MiB (83,886,080 bytes), compute SHA-256 of plaintext.
2. Verify the staged source by decrypting and hashing.
3. Promote source; fsync.
4. Write and verify the initial revision (`rev/<id>.fx1`) containing pages and empty fields/values.
5. Write and verify `head.fx1`.
6. Write and verify `meta.fx1` with `createdAt`, `updatedAt`, title default, source ref, and `latestRevisionId`.
7. Only then return `ImportedSource` and make the document visible in the list.

A failure at any step removes staged files; if a promoted source/revision exists but `meta.fx1` was never written, the startup sweep removes the unreferenced directory (an import that never became visible). This is the only automatic deletion allowed; it never removes a visible document/template (FR-009, FR-076).

### 3.3 Template version commit

Same protocol as §3.1, but the promoted object goes to `ver/<versionId>.fx1`, `head.fx1` points to the latest version, and `meta.fx1` lists version pointers. Existing versions are never modified or deleted by a normal save. Documents pin `templateVersionId` at creation and are not touched (FR-104).

Template creation creates `templates/<templateId>/` and alias `feldexa.tpl.v1.<templateId>` before the first version is encrypted; a failed creation leaves no visible template and the startup sweep removes its orphan alias. Template versions and metadata use the template's alias; no document key is used.

**Creating a document from a template**: stage and verify a **new encrypted copy** of the template's source under `docs/<newDocumentId>/src/`, then write the initial revision with the pinned template version's field layout and empty values/signatures. The new document has no reference to `templates/…`; template deletion therefore cannot affect it (FR-059/FR-060/FR-099). The copy is bounded by the 80 MiB source cap and included in the free-space preflight.

### 3.4 Signature asset commit

Signature PNGs are written and verified before the revision that references them is committed. An orphaned signature asset (revision never committed) is unreferenced; the sweep removes it only if no revision or template version references it and it is older than 24 h.

### 3.5 Export artifact

Export artifacts are **not** part of the durable aggregate. They are written to `context.cacheDir/feldexa_exports/<artifactId>.pdf.tmp`, verified, renamed to `<artifactId>.pdf`, and reported. They are removed after delivery/preview dismissal or by the startup sweep. They are never included in backups (cache is excluded) and never placed in the document store.

### 3.6 Aggregate deletion

A user-confirmed deletion removes the aggregate's objects and directory first and its KEK alias last. If alias deletion fails after the objects are gone, the startup sweep removes the orphan alias; no ciphertext is left undecryptable by an early key deletion. Deleting a template never reads or deletes a derived document's alias, whose objects are independent encrypted copies (§3.3). An aggregate whose key is already unavailable remains deletable: the confirmation names the localized "Nicht lesbar" state instead of requiring an unreadable title.

---

## 4. Startup recovery and sweep

On app start (before the list is shown), run in this order:

1. Delete `tmp/` entries older than 24 h or with unknown names.
2. For each `docs/<id>/` and `templates/<id>/`:
   - If `meta.fx1` is missing or unreadable → the aggregate never became visible; if it contains only `src/` or `rev/` and no `meta`, delete the directory (import/template-create incomplete). Otherwise mark the list entry `Nicht lesbar` and keep it.
   - If `head.fx1` is missing/corrupt → find the newest revision whose hash verifies; if found, adopt it, set `fellBackToOlderRevision: true`, and surface "Es wurde ein älterer gespeicherter Stand wiederhergestellt" (`SAVE-004`). If none verify → mark `Nicht lesbar`; never delete.
   - If `head.fx1` points to a missing/corrupt revision → same fallback.
   - If `head.fx1` verifies and carries `history`, run the same known-kind retention step from §3.1 step 8 (head protected; unknown/untracked retained). Trim history only after the delete-directory fsync succeeds; on fsync failure keep the full history and retry on the next startup/save. A legacy head without history deletes nothing.
3. Delete unreferenced signature assets older than 24 h.
4. Delete export artifacts older than 24 h and any on session end.
5. Delete orphaned KEK aliases under `feldexa.doc.v1.` and `feldexa.tpl.v1.` that have no corresponding aggregate directory. Never delete an alias whose aggregate directory still exists.
6. Write a redacted recovery event with counts only (including orphan aliases removed, but no IDs, titles, or content).

Recovery never deletes a visible document/template, never re-encrypts, and never renames an aggregate.

---

## 5. Failure semantics and German messages

| Condition | Exception | Code | Durable state | User-facing effect |
| --- | --- | --- | --- | --- |
| Disk full / quota exceeded (`ENOSPC`, `EDQUOT`) | `StorageFullException` | `SAVE-001` | Last verified head intact; unsaved changes retained in memory with risk badge | Blocking German message with storage guidance; retry after freeing space |
| Short write / fsync failure | `StorageWriteException` | `SAVE-003` | Staged file removed; head intact | Save failure message; last durable state preserved |
| One aggregate's KEK alias missing / invalidated while other aggregate keys remain available | `KeyUnavailableException` | `SAVE-002` | Ciphertext untouched; other documents/templates load normally | Specific German key-unavailability message; no data presented as intact |
| Keystore provider unavailable, or no stored aggregate key remains (device-wide reset) | `KeystoreUnavailableException` | `SAVE-008` | Ciphertext untouched or device data gone; no false per-aggregate isolation claim | Global German key-store-unavailable message; retry for a temporary provider outage; no recovery after reset |
| DEK unwrap tag mismatch / corrupt chunk | `CorruptDataException` | `SAVE-003` | Ciphertext untouched | Specific unreadable message; isolation per object/aggregate |
| Head/revision mismatch after crash | recovery fallback | `SAVE-004` | Newest verified revision adopted | "Älterer gespeicherter Stand wiederhergestellt"; unsaved risk disclosed |
| Unknown newer schema | `SchemaTooNewException` | `SAVE-005` | Data untouched; writes refused | Message that a newer app version is required |
| Path/name validation failure | `SecurityException` | `PLT-002` | No I/O performed | Generic German error; no path details |
| Export temp write failure | `ExportFailedException` | `EXP-002` | No artifact presented | Export failure; temp removed |

No exception message may contain a file path, file name, document title, OCR text, field value, or signature data.

Per-aggregate isolation covers loss/invalidation of one aggregate's alias while other aggregate keys remain available. A whole-Keystore or device reset invalidates every alias and is device-wide loss reported as `SAVE-008`; no per-aggregate scheme can isolate it, and the ciphertext may also be gone.

**Key-loss listing limitation**: `meta.fx1` is encrypted with the aggregate KEK, so a lost aggregate key also hides that aggregate's title and stored timestamps. The store must still enumerate the directory as `readable = false` with `unreadableReasonCode = SAVE-002` for aggregate-scoped key loss, `SAVE-003` when the aggregate's stored data fails authentication, or `SAVE-008` for a global provider/reset condition; `StoredMeta.title` is the localized "Nicht lesbar" placeholder, never a ciphertext-derived title. The UI renders the matching localized state. No plaintext index or shared metadata key is introduced. Unaffected aggregates keep their own metadata keys.

---

## 6. Capacity and performance

- Max source size: 80 MiB (83,886,080 bytes); max pages: 100; max signature PNG: 2 MiB. The cap is derived from the 300 MB peak-memory budget: source bytes in Dart + PDFium's document copy + one render/analysis bitmap.
- Free-space preflight: require `2 × objectSize + 32 MiB` before import/save/export; otherwise fail early with `SAVE-001`/`IMP-007`.
- Chunk size 1 MiB: bounded memory during encryption/decryption (one chunk + tag), and per-chunk authentication enables reliable truncation detection.
- Listing 50 documents: decrypts only `meta.fx1` (estimated ≤ 8 KiB each) and `head.fx1` with each aggregate's own KEK; no source or revision decryption. An aggregate whose key is unavailable is returned as an unreadable placeholder without decrypting or inventing content. Per-aggregate key lookup adds one Keystore unwrap per listed aggregate and must be measured, not assumed.
- Revision pruning keeps at most 5 known revision objects per document by default (last 3 autosave + newest explicit + newest recovery + head); the bounded head history has at most 16 entries. Explicit-save revisions are retained until superseded. Legacy/unknown-kind/untracked revisions are retained conservatively, so the on-disk count can exceed 5 after an upgrade.

---

## 7. Test vectors and required tests

1. **Round-trip**: empty object, 1 byte, 65,535, 65,536, 1,048,575, 1,048,576, 1,048,577 bytes and a 20 MiB PDF → byte-identical plaintext, verified hash.
2. **Tamper**: flip one ciphertext byte, one header byte, reorder chunks, truncate the final chunk, change `chunkCount`, splice a chunk from another object → all must fail with `SAVE-003` and no plaintext output.
3. **Key**: delete one document's KEK alias → that document fails with `SAVE-002`, its ciphertext is unchanged, and a sibling document and a template with independent KEKs still load; no file is deleted. Repeat with one template alias and verify a sibling template/document loads.
4. **Crash**: kill the process at each commit step (fault injection) → old head readable or verified fallback; never a partially committed revision reported as success.
5. **Quota**: inject `ENOSPC` at stage, promote, and head-write points → no success reported, old head intact, staging cleaned.
6. **Import rejection**: password-protected/truncated/unknown file → no `docs/<id>/` directory after cleanup.
7. **Sweep**: stale `tmp/`, orphan signature, orphan export, incomplete import, and orphan KEK aliases with no aggregate directory → removed; visible documents/templates and their aliases untouched.
8. **Template immutability**: save two template versions; verify version 1 bytes unchanged and a derived document still references version 1.
9. **No plaintext on disk**: after import/save/export failures, scan the app data and cache directories for the PDF magic bytes (`%PDF-`) and known test phrases → none outside the encrypted container (export artifact excepted during an active preview).
10. **Backup exclusion**: verify the manifest/`dataExtractionRules` exclude all app data on a test install.
11. **Per-aggregate keys**: create two documents and one template; assert three distinct aliases with the documented prefixes and that no `feldexa.master.v1` alias exists. Delete one document alias; only that document returns `SAVE-002`, while the other document and the template load. Delete one template alias; only that template fails.
12. **Key-loss listing**: with one aggregate alias deleted, `list` returns that aggregate with `readable = false`, `unreadableReasonCode = SAVE-002`, the German "Nicht lesbar" placeholder title, and the other aggregates unchanged; the UI shows the localized unreadable state.
13. **Global key-store failure**: simulate an unavailable Keystore provider, and separately invalidate every aggregate alias. Each case returns `KeystoreUnavailableException` (`SAVE-008`), does not claim other aggregates are unaffected, and deletes no file; a temporary provider outage is retryable, the device-wide reset is not.
14. **Global listing**: in a global `SAVE-008` case, `list` returns every stored aggregate with `readable = false`, `unreadableReasonCode = SAVE-008`, and the "Nicht lesbar" placeholder; it does not emit per-aggregate `SAVE-002` claims.
