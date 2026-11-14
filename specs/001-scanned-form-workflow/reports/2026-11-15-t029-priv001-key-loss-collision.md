# T029 Follow-up: `PRIV-001` and Shared-Keystore-Key Loss

- **Task**: T029 follow-up requirement review (quality-review finding on
  `bf6338c`)
- **Date**: 2026-11-15, Europe/Berlin
- **Class**: `NONE` (host-VM contract analysis; no runtime evidence)
- **Result**: `PARTIAL` — the contract collision is established and options are
  documented; the product/security decision remains open
- **Base revision**: `dde4e8f76f146733fa93550e5e7d030c02de0f72`
- **Tree state at analysis**: clean except the pre-existing unstaged
  `apps/feldexa_app/android/gradlew.bat` line-ending change; this report and
  the reports index are added by the same change
- **Candidate SHA**: recorded in the external `worker_done` attestation, not in
  this report

This report does not change a German user-facing text, a requirement, a task,
or a normative contract. It records why a text-only correction is not
justified without an owner decision.

## 1. Review question

`PRIV-001` and `SAVE-002` state that after key loss the affected data is
unreadable while other documents and templates remain usable. The storage
contract uses one Android Keystore key, alias `feldexa.master.v1`, as the KEK
for every object. If that single alias is missing or invalidated, every wrapped
DEK fails to unwrap, so the two statements cannot both describe the same
system.

The review asked for all normative occurrences, the actual error context, and
concrete options with consequences if this is a real collision.

## 2. Normative key architecture

| Source | Statement |
| --- | --- |
| `contracts/storage-format.md:102-104` | One KEK: Android Keystore AES-256-GCM key, alias `feldexa.master.v1`; every object's DEK is wrapped as AES-GCM(KEK, DEK); key export prohibited. |
| `contracts/storage-format.md:59,70` | Every container header stores `keyScheme = 1` ("Keystore-wrapped DEK") and the wrapped 32-byte DEK. The header has no key identity beyond that single wrapping scheme. |
| `research.md:119-120` (D-07) | One master key in alias `feldexa.master.v1`; per-object data keys wrapped by that master key. |
| `plan.md:34` | Per-object 256-bit data key wrapped by a non-exportable Android Keystore master key. |
| `contracts/ports.md:178-183` | `StoreStatus.keyAvailable` is store-global, not per document. |
| `contracts/storage-format.md:129` | A save requires `status.keyAvailable == true`; the status is store-global. |
| `contracts/platform-channel.md:125,242` | `store.status` exposes `keyAvailable`/`keyAliasPresent`; `storage.status` reports `SAVE-002` — both are store-global, not per document. |
| `contracts/error-catalog.de.md:55` | Alias loss and unwrap failure both map to `SAVE-002`. |

The per-object DEK provides isolation for corruption of one object's wrapped
key or ciphertext. It does **not** provide isolation for loss of the shared
KEK: one alias unwraps every object's DEK.

The architecture decision itself acknowledges this in `research.md:124`:
"Loss of the Keystore master key itself is the unavoidable device-wide case."
The next paragraph, `research.md:133`, then says other documents remain
readable after a missing/corrupt master key. That is an internal contradiction
inside D-07.

## 3. Normative statements that promise per-document isolation

| Source | Statement | Collision |
| --- | --- | --- |
| `spec.md:224-226` (acceptance scenario 7) | Key material lost → affected data cannot be decrypted, and other documents/templates are left unaffected. | A shared KEK loss affects every document and template. |
| `spec.md:424-425` (edge case) | The affected data is unreadable, and unrelated documents, templates, and drafts remain intact. | Their ciphertext is intact but none can be decrypted while the KEK is unavailable. |
| `spec.md:555-556` (FR-052) | Lost key material must not damage unrelated documents, templates, or drafts. | If "damage" includes loss of usability, a shared KEK loss violates the requirement; the requirement does not distinguish object corruption from master-key loss. |
| `contracts/error-catalog.de.md:55` (`SAVE-002`) | "Andere Dokumente und Vorlagen sind davon nicht betroffen." | False for alias missing/invalidated; true only for a per-object unwrap failure. |
| `contracts/error-catalog.de.md:75-76` (`PRIV-001`) | Only "die betroffenen Dokumente" cannot be recovered; "Andere Dokumente bleiben unabhängig davon nutzbar." | False for loss of the device-bound shared key. |
| `contracts/storage-format.md:194` | KEK alias missing/invalidated → ciphertext untouched; other documents load normally. | Impossible with one shared alias. |
| `contracts/storage-format.md:219` (required test 3) | Delete the Keystore alias → a sibling document with a different DEK still loads. | A different DEK is still wrapped by the deleted KEK, so it cannot unwrap. |
| `contracts/ports.md:235-236` | A missing key only affects affected loads; other documents remain loadable. | With a store-global alias, all loads are affected. |
| `quickstart.md:192` | Delete the Keystore alias → sibling document still opens. | Same impossible expectation. |
| `contracts/platform-channel.md:297` | Keystore loss emulator test → sibling document loads. | Same impossible expectation. |
| `data-model.md:140` | `Unreadable` is per document and never transitions other documents. | A shared KEK loss transitions every document to unreadable. |
| `research.md:133` | Missing/corrupt master key → other documents remain readable. | Contradicts `research.md:119-124` and the single-alias architecture. |
| `plan.md:208` | Key-loss mitigation claims "per-document isolation". | Per-object DEK isolation does not cover master-key loss. |

## 4. Actual failure context

- There is no Android implementation yet: `KeystoreService.kt` and
  `EncryptedStore.kt` are absent and T025/T026 are still open
  (`tasks.md:177-178`). The `storage/` package directory contains only
  `.gitkeep`, and `MainActivity.kt` is the only Kotlin source file.
- The typed error exists: `packages/feldexa_ports/lib/src/errors.dart:259-266`
  defines `KeyUnavailableException` with code and `messageKey` `SAVE-002`.
- The test toolkit already injects `keystoreUnavailable` and
  `corruptKeyMaterial`, both as `SAVE-002`
  (`packages/feldexa_testkit/lib/src/faults/fault_kind.dart:23-26`), but these
  are fault classifications, not a storage implementation.
- There is therefore no executable key-loss path to reproduce on Android, and
  no `EMULATOR` or `DEVICE` evidence can be claimed. Host-VM tests can only
  prove that the current contracts, catalog, and exception vocabulary load and
  pass.

The failure classes must be kept distinct:

| Failure | Scope | Other documents usable? |
| --- | --- | --- |
| One object's wrapped DEK or ciphertext is corrupt | One object; `SAVE-002` or `SAVE-003` | Yes |
| Shared KEK alias missing/invalidated | Every object; `SAVE-002` | No; ciphertext is untouched and no file is deleted, but decryption fails |
| Entire Android Keystore reset / device reset | Every app key; data may also be gone | No |

The current texts collapse these classes into one `SAVE-002` message.

## 5. Why this is not a pure text defect

FR-052 and acceptance scenario 7 are binding requirements, not merely prose.
The storage contract and research decision D-07 choose a shared device-wide
KEK. Making the texts internally consistent therefore requires choosing which
obligation wins:

- correcting the texts to say "all documents become unreadable" changes the
  product promise in FR-052, the acceptance scenario, and `PRIV-001`; or
- keeping the "other documents remain usable" promise requires a different
  key architecture.

Neither is a T029 editorial change, and neither may be inferred without an
owner decision.

## 6. Options and consequences

### Option A — Keep the shared KEK; disclose device-wide loss

Keep `feldexa.master.v1` as the only KEK and make every statement accurate:
key loss affects all documents and templates; ciphertext is untouched and
nothing is deleted; no recovery is possible.

Consequences:

- Smallest implementation and no change to T025/T026 architecture.
- Requires changing `PRIV-001`, `SAVE-002`, the acceptance scenario, the edge
  case, FR-052 (or an explicit exception), `storage-format.md:194/219`,
  `ports.md:236`, `quickstart.md:192`, `platform-channel.md:297`,
  `data-model.md:140`, `research.md:133`, and the `plan.md:208` risk row.
- The required test changes to: delete the alias → every open fails with
  `SAVE-002`; no file deleted; ciphertext unchanged.
- Product/trust impact: the disclosure must say that one device-key loss makes
  all Feldexa documents unreadable, which is a stronger warning than today's
  "affected documents" wording.

### Option B — Per-document (or per-template) Keystore KEKs

Use a separate Keystore KEK per document/template aggregate. Each aggregate's
object DEKs are wrapped by its own KEK. Deleting or invalidating one alias then
affects only that aggregate; other aliases still unwrap.

Consequences:

- Preserves the single-aggregate isolation promise, but the container needs a
  key identity (for example an alias/key id in the header) and T025/T026 need
  alias creation, lookup, deletion, cleanup, status, and lifecycle rules.
- Deletion must remove the aggregate's alias; status must distinguish
  per-aggregate key availability; tests must delete one aggregate's alias and
  verify a sibling still loads.
- More Keystore keys and alias-management code; migration/versioning and
  orphan-alias sweep are new failure surfaces.
- A whole-Keystore reset or device reset still loses every key. FR-052's
  absolute "key material" wording must either exclude that global reset or
  accept that it is indistinguishable from device data loss. This option does
  not make unlimited device-key loss impossible to disclose honestly.

### Option C — Partitioned key rings

Use a small number of master KEKs by cohort. This limits the blast radius but
does not provide true per-document isolation; the grouping rule would be
arbitrary. Not recommended unless the owner accepts a documented partial
isolation guarantee.

### Option D — Redefine FR-052 as "no damage/deletion" and add a device-wide exception

Keep the shared KEK, interpret "damage" as corruption or deletion rather than
unreadability, and add an explicit device-wide key-loss case with its own
German message.

Consequences:

- Minimal code change, but requires a specification change and new/updated
  German texts; `PRIV-001` and `SAVE-002` would still need rewriting.
- Acceptance scenario 7 must distinguish object corruption from master-key
  loss, otherwise the scenario remains unverifiable.
- The product still cannot make unrelated documents usable after a shared KEK
  loss; only the wording of the guarantee changes.

### Option E — Key backup, escrow, or recovery

Add a recovery path for the KEK.

Consequences:

- Would allow recovery, but conflicts with FR-049 (non-exportable key material)
  and FR-051 (limited backups/no recovery), and requires a new security and
  privacy decision, key-custody design, and user flow.
- Not a text correction and not viable without explicit owner approval.

## 7. Recommendation

No normative text was changed. The collision requires an owner decision before
T025/T026 implement the storage layer. If the current shared-KEK architecture
is retained, Option A is the only internally consistent choice, but it changes
the FR-052/acceptance promise and needs specification approval. If the
per-document usability promise is binding, Option B is the smallest
architectural route, with the residual whole-Keystore-loss caveat made explicit.
Option D is acceptable only as an explicit requirement change, not as a silent
wording fix; Option E is out of scope without a new security decision.

## 8. Host-VM verification run

Toolchain: Flutter 3.47.7 (stable), Dart 3.13.5, workspace `pubspec.yaml` and
committed `pubspec.lock`. Commands ran from the repository root and the named
package directories. Logs were console-only and are not retained as artifacts.

| Command | Working directory | Exit | Observed |
| --- | --- | --- | --- |
| `flutter pub get --offline` | repository root | 0 | workspace packages resolved from the committed lockfile |
| `flutter test` | `apps/feldexa_app` | 0 | 65 tests passed |
| `flutter test` | `packages/feldexa_ports` | 0 | 33 tests passed |
| `flutter test` | `packages/feldexa_testkit` | 0 | 110 tests passed |
| `flutter analyze --no-pub` | repository root | 0 | No issues found |

These are host-VM checks (`NONE`). They prove that the current catalog,
exception vocabulary, and fault-injection surface compile and pass; they do not
prove Keystore behavior, key-loss handling, or German runtime rendering.

## 9. Not checked

- No Android `EMULATOR` or `DEVICE` run; T025/T026 do not exist yet.
- No key-loss reproduction at runtime is possible from this revision.
- No change to `PRIV-001`, `SAVE-002`, FR-052, acceptance scenario 7, or any
  other normative text was made.
- No independent review or product/security approval is claimed.

## 10. Files reviewed

- `spec.md` (FR-049–FR-052; acceptance scenario 7; key-loss edge case)
- `plan.md` (storage architecture; key-loss risk row)
- `research.md` (D-07)
- `data-model.md` (`Unreadable` state)
- `contracts/error-catalog.de.md` (`SAVE-002`, `PRIV-001`)
- `contracts/storage-format.md` (§2.3, §5, §7)
- `contracts/ports.md` (`StoreStatus`, `SecureStorePort`)
- `contracts/platform-channel.md` (Keystore-loss test)
- `quickstart.md` (key-loss injection)
- `tasks.md` (T025/T026 status)
- `packages/feldexa_ports/lib/src/errors.dart`
- `packages/feldexa_testkit/lib/src/faults/fault_kind.dart`

## 11. Review

Reviewer: _(blank; independent review required)_

Date:

Verdict:
