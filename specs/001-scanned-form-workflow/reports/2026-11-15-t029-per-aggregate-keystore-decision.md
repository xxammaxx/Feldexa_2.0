# T029 Follow-up: Per-Aggregate Keystore Keys — Decision and Impact

- **Task**: T029 follow-up requirement review; resolution of the
  `2026-11-15-t029-priv001-key-loss-collision.md` finding
- **Date**: 2026-11-15, Europe/Berlin
- **Class**: `NONE` (host-VM contract and catalog verification; no Android
  runtime evidence)
- **Result**: `PARTIAL` — the contract decision is applied consistently in the
  normative artifacts and German texts; T025/T026 remain unimplemented, so no
  runtime key-loss proof exists
- **Base revision**: `8a508d7fe89c0c4277453a39af9a0f24df89cef7`
- **Tree state**: dirty with the files listed in §8 plus the pre-existing
  unstaged `apps/feldexa_app/android/gradlew.bat` line-ending change; the exact
  candidate SHA is recorded in the external `worker_done` attestation
- **Supersedes**: the open-decision status of
  `2026-11-15-t029-priv001-key-loss-collision.md`; that report remains the
  historical collision analysis and is not rewritten

## 1. Decision applied

The owner decided on 2026-11-15 that documents and templates use separate
Keystore keys, and that the existing isolation promise on key loss remains
binding. No further owner decision was made or invented.

Applied interpretation: one KEK per document and one KEK per template, not one
KEK shared by all documents plus one by all templates. A two-key split
(documents vs templates) would still make every document unreadable when one
document key is lost, so it would not preserve the binding cross-document
promise in FR-052, acceptance scenario 7, and `PRIV-001`. The per-aggregate
interpretation is the only one that satisfies the stated decision and the
existing promise.

Aliases:

- document: `feldexa.doc.v1.<documentId>`
- template: `feldexa.tpl.v1.<templateId>`

Each alias is a non-exportable Android Keystore AES-256-GCM key. The
aggregate's per-object DEKs are wrapped by its own KEK. No `feldexa.master.v1`
alias is part of the contract.

## 2. Contract changes

| Artifact | Change | Reason |
| --- | --- | --- |
| `contracts/storage-format.md` | KEK row now defines per-document/per-template aliases; added per-aggregate key lifecycle, creation before first ciphertext, deletion ordering (objects first, alias last), orphan-alias sweep, aggregate-scoped failure mapping, and key-loss listing behavior. `keyScheme=1` now means "DEK wrapped by the aggregate KEK". | Remove the single shared `feldexa.master.v1` architecture and make key-loss isolation mechanically possible. |
| `contracts/ports.md` | Removed the store-global `StoreStatus.keyAvailable`; per-aggregate availability is expressed through `StoredMeta.readable`/`unreadableReasonCode` and `KeyUnavailableException` (`SAVE-002`). Added per-aggregate creation, deletion, load/save, and empty-title rules. | A global key flag would be false/misleading when only one aggregate key is lost. |
| `contracts/platform-channel.md` | `store.status` no longer reports a global key flag; `storage.status` carries `kind`, `itemId`, and per-aggregate key availability; deletion and Keystore-loss tests are aggregate-scoped. | Keep the channel aligned with the port and expose the affected aggregate only. |
| `data-model.md` | `Unreadable` is explicitly per aggregate; losing one aggregate KEK does not transition other documents/templates; an unreadable aggregate is listed as "Nicht lesbar" without an invented title. | Preserve per-document state isolation. |
| `plan.md` | Storage architecture, structure comment, architecture decision 3, and key-loss risk row now use per-document/template KEKs. | Remove the plan's shared-master-key claim. |
| `research.md` | D-07 rewritten for per-aggregate KEKs; shared master key recorded as rejected; recovery semantics now aggregate-scoped; fault-injection and decision-summary rows updated. | Remove the internal D-07 contradiction and record the rejected alternative. |
| `quickstart.md` | Key-loss injection deletes one document's alias and verifies the affected document, a sibling document, and a template; repeated for one template alias. | Make the required test match the new contract. |
| `contracts/error-catalog.de.md` | `SAVE-002` now names the key for one document/template and still says other documents/templates are unaffected. `PRIV-001` now uses plural, per-item keys and says the affected item's data cannot be recovered while other items remain usable. Added the whole-Keystore/device-reset limit. | Keep the German catalog semantically consistent with the new key model. |
| `apps/feldexa_app/lib/l10n/app_de.arb` and generated l10n | Updated `save002` and `priv001` values and descriptions, then regenerated `app_localizations*.dart`. | Keep the ARB and runtime strings identical to the catalog. |
| `apps/feldexa_app/test/german_strings_test.dart` | Updated the PRIV-001 catalog lookup to the new wording. | The existing catalog→ARB mapping test must find the changed disclosure. |
| `tasks.md` | T025/T026 now own per-aggregate KEK creation, alias lifecycle, selection, deletion, and orphan-alias sweep; CR-11 records the owner decision and affected tasks. | Prevent T025/T026 from reimplementing the rejected shared master key. |
| `packages/feldexa_ports/lib/src/errors.dart` | Comment-only update: `KeyUnavailableException` describes the owning document's/template's key, not a device-wide key. | Keep the exception documentation consistent; no behavior changed. |

`spec.md` was reviewed and is unchanged: FR-052 and acceptance scenario 7
already require unrelated documents/templates to remain usable, and the
per-aggregate model now satisfies them. No user-facing German text other than
`SAVE-002` and `PRIV-001` changed; `IMP-007` and `FLD-001` keep their corrected
verbatim texts.

## 3. Consequences

- Deleting or invalidating one aggregate alias makes only that document or
  template unreadable with `SAVE-002`. Sibling documents, templates, and their
  aliases are untouched; ciphertext is not deleted.
- A whole-Keystore reset or device reset invalidates every alias. That remains
  a device-wide loss case; it is documented as a limit and is not claimed as
  per-aggregate isolation. This is inherent to Android Keystore, not a new
  product decision.
- `meta.fx1` is protected by the aggregate KEK. If the key is lost, the title
  and stored timestamps are also unreadable. The list must show a non-content
  "Nicht lesbar" entry with an empty title, and deletion must still be possible
  through that localized state. No plaintext index or shared metadata key was
  introduced.
- Each aggregate creates a Keystore key. StrongBox is best-effort; a failed
  StrongBox generation falls back to TEE, never software. Alias creation,
  deletion, and orphan-alias sweeping add lifecycle work to T025/T026.
- Listing now performs one metadata decryption per aggregate, so a 50-item list
  adds Keystore unwrap latency. T026/T097 must re-measure the list target; the
  contract still avoids source and revision decryption.
- FXC1 v1 is unchanged: `keyScheme=1` still describes a Keystore-wrapped DEK;
  only the KEK selection is per aggregate. No migration is needed because no
  storage implementation or persisted data exists yet.
- No Android implementation exists (T025/T026 open), so this report cannot
  claim emulator/device key-loss results.

## 4. Verification run

Toolchain: Flutter 3.47.7 (stable), Dart 3.13.5, workspace `pubspec.yaml` and
committed `pubspec.lock`. Commands ran from the repository root and named
package directories; logs were console-only and are not retained.

| Command | Working directory | Exit | Observed |
| --- | --- | --- | --- |
| `flutter pub get --offline` | repository root | 0 | workspace resolved from the committed lockfile |
| `flutter gen-l10n` | `apps/feldexa_app` | 0 | generated localization files regenerated from the updated ARB |
| `flutter test test/german_strings_test.dart` | `apps/feldexa_app` | 0 | 9 tests passed, including catalog↔ARB exact-text and key-mapping checks |
| `flutter test` | `apps/feldexa_app` | 0 | 65 tests passed |
| `flutter test` | `packages/feldexa_ports` | 0 | 33 tests passed |
| `flutter test` | `packages/feldexa_testkit` | 0 | 110 tests passed |
| `flutter analyze --no-pub` | repository root | 0 | No issues found |

These are host-VM checks (`NONE`). They prove that the changed contracts,
German catalog/ARB, generated localization, and exception vocabulary are
internally consistent and compile/pass. They do not prove Android Keystore
behavior, key-loss handling, listing, or deletion behavior.

## 5. Remaining limits

- T025/T026 are open; no `KeystoreService.kt` or `EncryptedStore.kt` exists, so
  no `EMULATOR` or `DEVICE` key-loss evidence can be produced.
- The per-aggregate key lifecycle, list placeholder, and deletion path are
  contract-level only until T025/T026 implement them.
- A whole-Keystore or device reset remains device-wide; no per-aggregate scheme
  can isolate that event.
- No independent review or self-approval is claimed.

## 6. Files changed

- `specs/001-scanned-form-workflow/contracts/storage-format.md`
- `specs/001-scanned-form-workflow/contracts/ports.md`
- `specs/001-scanned-form-workflow/contracts/platform-channel.md`
- `specs/001-scanned-form-workflow/contracts/error-catalog.de.md`
- `specs/001-scanned-form-workflow/data-model.md`
- `specs/001-scanned-form-workflow/plan.md`
- `specs/001-scanned-form-workflow/research.md`
- `specs/001-scanned-form-workflow/quickstart.md`
- `specs/001-scanned-form-workflow/tasks.md`
- `apps/feldexa_app/lib/l10n/app_de.arb`
- `apps/feldexa_app/lib/l10n/app_localizations.dart`
- `apps/feldexa_app/lib/l10n/app_localizations_de.dart`
- `apps/feldexa_app/test/german_strings_test.dart`
- `packages/feldexa_ports/lib/src/errors.dart`
- this report and `reports/README.md`

## 7. Review

Reviewer: _(blank; independent review required)_

Date:

Verdict:
