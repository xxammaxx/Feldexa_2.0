# T027 store-status progress

The Android adapter package now contains a partial `store.status` channel client. It validates the versioned envelope and returns the canonical `StoreStatus` with Android `NONE` evidence. Two host Flutter tests passed and `flutter analyze --no-pub` reported no issues. These checks do not establish Android runtime behavior.

T027 remains open: this client does not implement `SecureStorePort` and does not supply the other store or platform operations. In particular, the canonical port's `createDocument` and `saveRevision` interfaces require reconciliation with the channel request/response contract before a complete implementation can be claimed. No product contract or task completion mark has been changed.

## Contract audit and recovery stamp

`contracts/ports.md` §2.4 requires `createDocument(CreateDocumentRequest)` and a `StoredMeta` return from `saveRevision`. `contracts/platform-channel.md` §4 has no `store.createDocument` operation and returns only revision ID, commit time, hash, verification status, and prune count for `store.saveRevision`. Native `EncryptedStore.createDocument` requires an aggregate ID, metadata, staged source and initial revision; native `saveRevision` returns a verified `CommitReceipt`, not `StoredMeta`. The import method creates an aggregate as part of its own workflow but does not expose the port request as an independent store method. No precedence rule found in the examined normative sources makes either interface optional. A subsequent metadata read would require explicit consistency semantics to guarantee it describes the committed revision under concurrent saves. No method or return data is invented here.

The independently specified `store.recoveryStamp` request/response is implemented on the partial client with UUID and response validation and typed key/corruption failures. Six host tests passed and Flutter analysis was clean. This is host-only evidence; native channel services, a complete `SecureStorePort`, runtime integration, and the two conflicting operations remain open.

## Owner decision: create identity and initial revision

The owner approved changing the request and immediate contracts: `CreateDocumentRequest` carries the importer-assigned document ID and canonical initial `Revision`; it rejects a mismatched document ID or non-null parent. The store must persist those exact values once and reject a duplicate visible aggregate without overwriting it. Port, channel and storage-format descriptions now record this decision. The complete ports host suite passed 108/108 and analysis was clean.

This is an intermediate change: `store.createDocument` is described but not yet connected to the Android channel or staged-source service, and no duplicate-create or recovery runtime test has been performed for that channel. `saveRevision` still lacks a verified `StoredMeta` channel response. T027 remains open; no Android runtime or integration claim is made.

## Asynchronous client and save metadata follow-up

The partial Android client now correlates start replies with terminal result events, buffers early events, exposes cancellation IDs, and fails pending requests when the result stream closes. A partial save client accepts only a verified receipt and returns metadata obtained from `store.list` when its document ID and current head match that receipt; a changed head or missing metadata fails instead of constructing a successful result. Fourteen package host tests passed, and `flutter analyze --no-pub` was clean. These tests use mocked Flutter channels and are not Android runtime evidence.

The T024 channel implementation and real store service are not present on this branch. The save client therefore has not been exercised against native storage, and the list/readback consistency and production failure mappings still need integration review. The create channel, staged-source binding, remaining port methods, Android instrumentation, independent reviews and integration remain open; T027 is not complete.
