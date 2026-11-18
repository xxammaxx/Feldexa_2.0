# Tasks: Scanned Form to Completed PDF Workflow

**Input**: Design documents from `/specs/001-scanned-form-workflow/`
**Prerequisites**: `plan.md` (required), `spec.md` (required), `research.md`, `data-model.md`, `contracts/`, `quickstart.md`
**Command provenance**: Corrective regeneration through the registered command `speckit.tasks` (source `.opencode/commands/speckit.tasks.md`; installed manifest hash `6754ae39649c8e73a5ed376ad5cfcf04422e321a10e07c5ccd92fd1b9bccf776` from `.specify/integrations/opencode.manifest.json`) in OpenCode on 2026-11-12; model `deepseek/deepseek-flash` (DeepSeek V4.1 Flash 1017). Setup was resolved with `.specify/scripts/bash/setup-tasks.sh --json`. `.specify/extensions.yml` exists and registers no hooks (`hooks: {}`).

**Tests**: The specification's Evidence and Verification Rules and constitution Principle VIII require automated tests, failure-case tests, artifact verification, and separated evidence classes. Test tasks are therefore included deliberately, not as an optional TDD extra.

**Organization**: Tasks are grouped by user story so each story is an independently testable increment. The P1 stories form the full MVP journey: import → detect → review → fill → save → export. User Story 7 (Export) is P1 and therefore appears before User Story 6 (Templates, P2), as required by priority order.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task).
- **[Story]**: Which user story the task belongs to (`US1`…`US9`). Setup, Foundational, and Polish tasks have no story label.
- Every task names an exact file path.

## Path Conventions

This feature is a Flutter monorepo (see `plan.md` §Project Structure):

- Application: `apps/feldexa_app/`
- Shared packages: `packages/feldexa_*`
- Tooling: `tools/`
- Feature documents: `specs/001-scanned-form-workflow/`
- **Single evidence root**: every task-produced evidence report (dry run, recognition, export verification, local gate, quickstart validation, usability, acceptance, budget, device) lives under `specs/001-scanned-form-workflow/reports/`, indexed by `specs/001-scanned-form-workflow/reports/README.md` (T010). `tools/evaluation/` holds only scoring code, schemas, protocols, and benchmarks — never a second unlinked report root.

## Fixed Inputs and Review Gate

- The five settled clarifications in `spec.md` §Clarifications are fixed: protected internal source copy; debounced autosave roughly 2 seconds plus foreground flush and explicit save; minimal „Meine Dokumente“ list; editable template versions with immutable derived documents; strict German date validation.
- Constitution v1.0.0 is fixed. No task in this file amends the constitution, expands product scope, commits, or publishes.
- `checklists/precision-testability.md` remains reviewer-owned. Its 36 markers are intentionally untouched; this file does not claim reviewer approval. See `checklists/precision-testability-assessment.md` for the item-by-item assessment.

## Foundational Type Ownership

The following types are owned exactly once. A later task may consume an earlier task's type but must not redeclare it. This table is normative for T013–T022 and matches `contracts/ports.md` §1 and `data-model.md`.

| Owner | Package / file | Types |
| --- | --- | --- |
| T014 | `packages/feldexa_ports/lib/src/evidence.dart`, `errors.dart` | `EvidenceClass`, `CapabilityEvidence`, `FeldexaException` + typed exceptions, `ImportRejectionKind` |
| T013 | `packages/feldexa_ports/lib/src/descriptor.dart`, `registry.dart`, `ports/`, `dto/` | `CapabilityKind`, `CapabilityDescriptor`, `PlatformCapability`, `AdapterRegistry`, all 10 port interfaces, `ImportRequest`, `ImportedSource`, `SourceIntegrity`, `RasterRequest`, `RasterImage`, `RasterFormat`, `OcrRequest`, `OcrBlock`, `OcrLine`, `StoreKind`, `StoreStatus`, `StoredMeta`, `LoadedDocument`, `LoadedTemplate`, `CreateDocumentRequest`, `SaveRevisionRequest`, `CreateTemplateRequest`, `SaveTemplateVersionRequest`, `WriteSignatureRequest`, `DeleteConfirmation`, `RecoveryStamp`, `ExportRequest`, `ExportResult`, `ExportValidationResult`, `ExportOptions`, `DeliveryAction`, `DeliveryOutcome`, `AppLifecycleSignal` |
| T015 | `packages/feldexa_core/lib/src/geometry/rect.dart` | `Rect`, `Size`, `Point` |
| T016 | `packages/feldexa_core/lib/src/geometry/page_geometry.dart` | `PageGeometry` |
| T017 | `packages/feldexa_core/lib/src/model/document.dart`, `page_failure.dart`, `template_origin.dart`, `durable_pointer.dart`, `canonical_json.dart` | `Document`, `SourceFileRef`, `Page`, `PageFailure`, `AnalysisState`, `DocumentMeta`, `DocumentStatus`, `DocumentPreferences`, `TemplateOrigin`, `DurablePointer` |
| T018 | `packages/feldexa_core/lib/src/model/field.dart` | `FieldSuggestion`, `ConfirmedField`, `FieldValue` variants, `FieldVerification`, `SignatureMark`, `FieldType`, `Provenance`, `SuggestionEvidence`, `FieldValidation` |
| T020 | `packages/feldexa_core/lib/src/model/persistence.dart` | `DurabilityStatus`, `Revision`, `RevisionKind`, `RevisionContent` |
| T021 | `packages/feldexa_core/lib/src/model/template.dart` | `Template`, `TemplateVersion`, `TemplateVersionPointer`, `TemplateMeta`, `TemplateVersionContent`, `StoredTemplate` |
| T022 | `packages/feldexa_export/lib/src/model/export_plan.dart`, `export_artifact.dart` | `ExportPlan`, `ExportValidation`, `ExportArtifact`, `ArtifactVerification` |
| T057 | `packages/feldexa_recognition/lib/src/page_analysis.dart` | `FieldSuggestionSet` |
| T095 | `apps/feldexa_app/lib/features/start/stored_items.dart` | `DocumentSummary` projection of `StoredMeta` (not persisted) |

## Gate Order (Constitution Development Workflow)

- Gate 5 (cross-artifact consistency analysis) was executed through the registered `speckit.analyze` command on **2026-11-12, before any implementation**, and produced the report archived at `specs/001-scanned-form-workflow/reports/2026-11-12-analysis.md`. Implementation must not start until the CRITICAL and HIGH findings are either resolved in the artifacts or explicitly recorded as open owner decisions (see below).
- `T144` only **records** that completed pre-implementation gate-5 analysis and names the separate post-implementation convergence check (gate 9). `T144` is not the first execution of gate 5 and must never be treated as a post-implementation substitute for it.
- Gates 7 (independent review of the exact candidate revision), 8 (integration and verification), and 9 (post-integration convergence) are separate gates owned outside this task list. `T147` hands the exact candidate revision to them; no task in this file self-approves, merges, commits, or publishes.

## Open Owner Decisions (Do Not Invent)

These findings cannot be settled by an implementation task. Tasks that touch them implement only the currently documented plan behavior and must be revisited after the owner decides.

| ID | Decision needed | Current documented behavior | Affected tasks |
| --- | --- | --- | --- |
| OD-1 (CHK009) | Does export block until every overlapping suggestion conflict is resolved, or proceed with unresolved suggestions excluded and warned? | `contracts/export-plan.md` §3.4 is explicitly **provisional**: unresolved suggestions are excluded and warned without blocking. FR-062 now states that empty fields never block export and defers unresolved-suggestion handling to that provisional policy, while FR-025 remains binding and still requires the user to resolve overlapping suggestions. | T113 |
| OD-2 (CHK017) | Recruitment, prior familiarity, observation protocol, and timing boundaries for the SC-016 journey timing and the SC-018 5-of-5 first-time usability run. | `quickstart.md` §10 says five first-time users; no recruitment or protocol. | T137 |
| OD-3 (CHK026) | Written equivalence rule and approval for any device other than the Samsung Galaxy A54 5G used for SC-004. | Plan names the Galaxy A54 5G and also allows an owner-approved equivalent. | T141 |
| OD-4 (CHK024) | Numeric interaction/latency bound for the FR-100 50-item list "usable" criterion. | Plan Phase E says a 50-item list is tested; no numeric bound. | T097 |

**Unresolved documentation gap (not an owner decision, not a task instruction)**: `spec.md` edge case "overlaying a value on pre-filled scanned content" has no FR and no acceptance criterion. No task in this file implements or verifies that behavior; it must be closed by a future specification change, not invented here. The spec status stays **Draft**.

## Contradiction Resolutions Applied

These are the only genuine artifact contradictions found; each is resolved by the stated authority and is implemented or verified by a task. No settled clarification is reopened.

| ID | Contradiction | Governing resolution | Task |
| --- | --- | --- | --- |
| CR-1 (CHK001) | FR-045 "approximately 2 seconds" vs SC-020's strict final-2-second loss bound. | The debounce is a 2 s timer and never exceeds 2 s; the 300 ms plan budget is the commit step. | T089, T092 |
| CR-2 (CHK025) | SC-014 "100 % German" vs FR-087's mandatory untranslated `SIMULATED` token. | Constitution Principles II and VIII require the token; SC-014 applies to translatable strings, with `SIMULATED` allowlisted. | T133 |
| CR-3 (CHK028) | 80 MiB cap in plan/data model vs "80 MB" in `IMP-007`. | The contract is corrected before implementation: the cap is 80 MiB (83,886,080 bytes) and `IMP-007` already states it. T045 consumes and verifies the corrected catalog rather than re-aligning it. | T045 |
| CR-4 (CHK030) | FLD-001 said overflow "may be clipped" while FR-068/EXP-001 stop the export. | The contract is corrected before implementation: `FLD-001` already states that export is stopped until the text is shortened or the field enlarged. T084 consumes and verifies that wording. | T084 |
| CR-5 (CHK031) | Plan Phase C "frozen metric dry run" vs the pre-scoring freeze requirement. | Freeze corpus and metric v1 before any run; the dry run is explicitly unscored; the first scored run is Phase H. | T033, T034, T060, T142 |
| CR-6 (CHK026) | Named device vs "owner-approved equivalent". | Owner authorization is permitted, but an equivalence rule must be recorded; until then only the named device satisfies SC-004. | T141 |
| CR-7 | T013 forward-referenced canonical types created by later tasks | Canonical types are implemented first; T013 starts after T014 and T015–T022; no task ID changes. | T013, T014, T015–T022 |
| CR-8 | T013/T014 descriptor and error ownership overlapped | T014 owns evidence, errors, and `ImportRejectionKind`; T013 owns descriptors, interfaces, registry, and DTOs. | T013, T014 |
| CR-9 | 30 port/core/export types had no task-level owner and 11 port types were undefined | Added the Foundational Type Ownership table and `contracts/ports.md` §2.10; T022 owns export contract models; T013 owns port DTOs. | T013, T014, T017, T018, T020, T021, T022, T057, T095 |
| CR-10 | `ExportArtifact` was in core in T022 but in export in the contracts and plan | `feldexa_export` is authoritative; T022's path and scope now match; no second copy remains in core. | T022 |
| CR-11 (review 8a508d7) | `PRIV-001`/`SAVE-002` promised per-document/template isolation while `storage-format.md` used one shared Keystore KEK. | Owner decision 2026-11-15: one Keystore KEK per document and per template; isolation for loss/invalidation of one aggregate key remains binding. Whole-Keystore/device reset remains a disclosed device-wide loss. | T025, T026, T029 |
| CR-12 (review ae8237b) | Global Keystore provider outage was mapped to aggregate-scoped `SAVE-002`, whose German text claimed other aggregates were unaffected; a whole reset appeared only in an internal note. | Global provider outage and device-wide reset now use `SAVE-008` / `KeystoreUnavailableException`; `SAVE-002` is aggregate-scoped while other keys remain available. German catalog/ARB/generated text and tests distinguish both contexts; no new security decision. | T014, T025, T026, T029 |
| CR-13 (review 0ac8d3f) | `PRIV-001` promised that other documents/templates remain usable without naming the device/Keystore reset exception, contrary to FR-051's pre-loss disclosure duty. | The pre-loss disclosure now states that a device or key reset can make all stored documents/templates unreadable or remove them, while preserving aggregate isolation for a single key loss. Catalog/ARB/generated text and test updated; no architecture or owner decision change. | T029, T091 |
| CR-14 (review 992d3e1) | Port docs and the testkit fault taxonomy still described global Keystore unavailability as aggregate `SAVE-002`, while `storage-format.md` maps it to `SAVE-008`. | `secure_store_port.dart`/`store_dto.dart` now distinguish aggregate `SAVE-002` from global `SAVE-008`; `FaultKind.keystoreUnavailable` is `SAVE-008` and `corruptKeyMaterial` remains `SAVE-002`; testkit/ports tests updated. T025/T026 remain runtime implementation tasks. | T011, T025, T026, T029 |
| CR-15 (review f1c80f4) | `storage-format.md` §2.3 mapped an unwrap tag mismatch to `SAVE-002`, while §5 and §7 test 2, `ports.md` §3, and `errors.dart` mapped a wrapped-DEK authentication failure to `CorruptDataException` (`SAVE-003`); testkit `corruptKeyMaterial` remained `SAVE-002`. The 2026-11-15 owner decision originally covered aggregate key loss and global reset, not a tag mismatch with a usable KEK. | Owner decision 2026-11-15: unwrap authentication/tag mismatch is integrity damage `SAVE-003`. §2.3, the listing reason codes in storage-format/ports/data-model, the testkit fault taxonomy, and the regression tests now align; aggregate key loss remains `SAVE-002` and global provider/reset remains `SAVE-008`. T025 implementation is unchanged; Android instrumentation remains `NOT_RUN`. | T025, T026, T011, T014, T029 |
| CR-16 (review 2ae955c) | `KeystoreServiceInstrumentedTest` cleanup called `deleteAllAggregateAliases`, which enumerated and deleted every `feldexa.doc.v1.`/`feldexa.tpl.v1.` alias. Under the production application id `de.feldexa.app`, a connected instrumentation run could permanently remove real data KEKs. | Instrumentation tests now map every alias into a unique `feldexa.test.v1.<runToken>.` namespace via a test-only backend and clean up only the exact tracked test aliases; there is no `KeyStore.aliases()` enumeration or production-prefix sweep. A JVM static guard plus an Android foreign-test-alias regression enforce the rule. Android instrumentation remains `NOT_RUN` until a safe actual run. | T025 |
| CR-17 (review 55f2d06) | The T036/T025 merge removed any `FaultKind`/`faultExceptionFor` injection for aggregate-scoped key loss `SAVE-002`; testkit README still described `corruptKeyMaterial` as `SAVE-002`/`KeyUnavailableException`; the API 31 observation said no production alias was addressed although a read-only `containsAlias` check ran on a random production-form alias. | Restored `FaultKind.aggregateKeyUnavailable` → `KeyUnavailableException` (`SAVE-002`), kept `corruptKeyMaterial` → `CorruptDataException` (`SAVE-003`), corrected the testkit README and observation/merge wording, and added host regressions. Android source/APK identity is unchanged and no new Android run is claimed. | T025, T036 |
| CR-18 (review 3f86b93) | The replacement commit deleted the historical `2026-11-15-emulator-t025-keystore.md` without naming it as superseded and reclassified the actual API 31 run as `NONE`, although `reports/README.md` §2 reserves `NONE` for provenance and host checks. No allowed class represents an actual Android run outside the Orca-allocated Pixel 7 API 35. | Restored the historical report as a frozen superseded record, withdrew the false `NONE` replacement, and documented the class collision and options in `reports/2026-11-15-t025-api31-evidence-governance.md`; no convention, schema, or validator change and no Android acceptance claim. | T025, T032 |
| CR-19 (gate check 4cdff66) | The Pixel 7/API 35 `EMULATOR` gate cannot be safely started: `orca-ide emulator list` shows no T025 session, `orca-ide emulator devices` lists only API 31/36 AVDs, `sdkmanager --list_installed` has no `system-images;android-35`, and Orca `attach` only activates/boots an existing AVD without an exclusive worktree reservation. | Recorded `NOT_RUN` with the concrete cause and options; no existing AVD, image, or data was started, wiped, or adopted, and no profile label was faked. A future run needs an installed API 35 image plus an owner-approved exclusive allocation (or an Orca-provisioned Pixel 7 API 35). | T025 |
| CR-20 (gate check 1468869) | A temporary official API 35 google_apis x86_64 image and Pixel 7 AVD were created only under `/tmp` with no global SDK/AVD changes. Under TCG the guest reached adb (API 35) but `sys.boot_completed` never became `1`, `service check package` was absent, only init/kernel processes existed, system_server never registered `aidl/activity`, and the emulator logged missing AVX/F16C plus QEMU CPU hangs. | Recorded `FAIL`/`NOT_RUN` for stable boot; Orca attach and the 12 tests were not attempted, no EMULATOR evidence is claimed, and no existing device/data was touched. A conforming run needs KVM/AVX-capable hardware or an Orca-provisioned Pixel 7 API 35. | T025 |

## Requirement Traceability Matrix

| Requirements | Primary tasks |
| --- | --- |
| FR-001–FR-010 (import and source integrity) | T037–T049 |
| FR-011–FR-020 (field detection) | T050–T063 |
| FR-021–FR-030 (review and correction) | T064–T075 |
| FR-031–FR-042 (filling) | T076–T087 |
| FR-043–FR-053 (saving, durability, recovery) | T088–T096, T025 |
| FR-049, FR-050 (encrypted storage; no app password or biometric unlock) | T025, T093 |
| FR-054–FR-061 (reusable templates) | T114–T121 (FR-061 explicitly T115) |
| FR-058 (templates distinguishable from documents) | T095, T115 |
| FR-061 (no automatic template creation) | T115 |
| FR-062–FR-073 (export) | T102–T113 (FR-072 explicitly T108) |
| FR-072 (failed or partial export never reported as success) | T022, T106, T108, T143 |
| FR-074–FR-077 (storage exhaustion) | T094, T100 |
| FR-078–FR-082 (privacy and offline) | T098, T099, T138 |
| FR-083–FR-085 (understanding recognition) | T122–T125 |
| FR-086–FR-089 (development and validation surface) | T128–T132 |
| FR-090–FR-094 (accessibility and language) | T133, T134 |
| FR-095–FR-096 (imported source retention) | T040, T048 |
| FR-097–FR-100 (stored document access) | T095–T097 |
| FR-101–FR-106 (template editing and versions) | T115–T120 |
| FR-107–FR-110 (date entry) | T081 |

| Success Criterion | Verification task |
| --- | --- |
| SC-001, SC-002, SC-003 | T035, T142 |
| SC-004 | T135, T136 |
| SC-005, SC-006 | T109, T112, T143 |
| SC-007, SC-008 | T138 |
| SC-009, SC-020 | T092 |
| SC-010 | T094 (T108 covers the export-under-storage-pressure path; its direct criterion is FR-072) |
| SC-011 | T046 |
| SC-012, SC-021 | T120 |
| SC-013 | T114, T120 |
| SC-014 | T133 |
| SC-015 | T134 |
| SC-016, SC-018 | T137 (protocol recorded now; journey-timing and 5-of-5 runs executed and recorded after owner decision OD-2) |
| SC-017 | T070, T109 |
| SC-019 | T048 (byte identity and modification time, plus deletion-reopen/render/export from the protected internal copy) |
| SC-022 | T081 |

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the monorepo, toolchain, assets, and evidence scaffolding.

- [x] T001 Create the Flutter monorepo workspace and directory skeleton in `pubspec.yaml`, `apps/feldexa_app/`, `packages/`, and `tools/` per `plan.md` §Project Structure
- [x] T002 Initialize the Flutter application and Android host in `apps/feldexa_app/pubspec.yaml` and `apps/feldexa_app/android/app/build.gradle.kts` with `minSdk 26` and target/compile SDK 36 (enables FR-001 Android import runtime and FR-086 browser surface; constitution Architecture and Platform Constraints)
- [x] T003 Pin the dependencies and record the privacy/licence review in `apps/feldexa_app/pubspec.yaml` and `tools/dependency_review.md` per `plan.md` §Primary Dependencies
- [x] T004 [P] Configure analysis, formatting, and the local gate in `.analysis_options.yaml` and `tools/gate.sh` per `plan.md` §Testing and constitution Principle VIII (enables FR-088 evidence separation)
- [x] T005 [P] Create the German localization scaffold in `apps/feldexa_app/l10n.yaml` and `apps/feldexa_app/lib/l10n/app_de.arb` with `de` as the only release locale (FR-090)
- [x] T006 [P] Bundle Noto Sans Regular/Bold and the OFL licence in `apps/feldexa_app/assets/fonts/` (FR-067; plan §Architecture Decisions 6)
- [x] T007 Implement the font-advance metrics generator in `tools/metrics/generate_font_metrics.dart` and emit `apps/feldexa_app/assets/fonts/metrics.json` (enables FR-064 text layout and FR-068 clip detection)
- [X] T008 [P] Create the corpus manifest schema and checksum verifier in `tools/corpus/manifest.schema.json` and `tools/corpus/verify.sh` (constitution Principle IV)
- [x] T009 Create the deterministic synthetic fixture generator in `tools/corpus/synthetic/generate.dart` and its fixtures under `apps/feldexa_app/assets/fixtures/` (US9; FR-086)
- [x] T010 [P] Create the evidence report template and directory in `specs/001-scanned-form-workflow/reports/README.md` for the `SIMULATED`, `EMULATOR`, and `DEVICE` classes (constitution Principle VIII)
- [x] T011 [P] Create the test toolkit with a fake clock, fixture loader, and fault hooks in `packages/feldexa_testkit/lib/` (plan §Architecture Decisions 10)
- [x] T012 Create the shared `SIMULATED` banner and evidence-label widget in `packages/feldexa_ui/lib/src/simulated_banner.dart` (FR-087; constitution Principle II)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core contracts, models, platform ports, storage, and evidence infrastructure that every user story depends on.

**⚠️ CRITICAL**: No user-story implementation starts until this phase is complete.

**Execution order (normative; task IDs and phase membership stay unchanged):**

1. `T014` — evidence/error vocabulary; no canonical type dependency.
2. `T015`/`T016` — geometry, file-disjoint.
3. `T018` → `T017` → `T020` → `T021`; `T022` can proceed after `T015`/`T016`; `T019` follows `T018`. `TemplateOrigin` is owned by `T017`, which breaks the former `T017`↔`T021` cycle.
4. `T013` — ports, descriptors, registry, and DTOs; requires `T014` and `T015`–`T022`.
5. `T023`–`T031` — adapters/registries; `T023` requires `T013`; `T027`/`T028` also require `T014` and `T026`.

- [x] T013 Define every capability interface, `CapabilityKind`, `CapabilityDescriptor`, `PlatformCapability`, `AdapterRegistry`, and every port-local request/result DTO/enum in `packages/feldexa_ports/lib/feldexa_ports.dart` and `packages/feldexa_ports/lib/src/{ports,dto,descriptor.dart,registry.dart}` per `contracts/ports.md` §1, §2, and §4; add workspace dependencies on `feldexa_core` and `feldexa_export` (constitution Architecture and Platform Constraints; start only after T014 and T015–T022; no second declaration of a canonical type)
- [x] T014 Define the error taxonomy and capability evidence vocabulary in `packages/feldexa_ports/lib/src/errors.dart` and `packages/feldexa_ports/lib/src/evidence.dart`: `FeldexaException` plus every typed exception in `contracts/ports.md` §3 (including `StorageWriteException` for `SAVE-003` and the `PLT-002` `SecurityException` mapping), `ImportRejectionKind`, `EvidenceClass`, and `CapabilityEvidence`; cite `contracts/error-catalog.de.md` and `contracts/storage-format.md` §5; reconcile the already-implemented `feldexa_testkit` `EvidenceClass` by making the ports type canonical and having the toolkit consume it (or rename the toolkit type), without changing T011's task ID (constitution Principle VIII; T013 consumes this)
- [x] T015 [P] Implement `Rect`, `Size`, and `Point` value objects in `packages/feldexa_core/lib/src/geometry/rect.dart` with finite, positive-size invariants (`data-model.md` §2.2; enables FR-024 and SC-017); T015 owns `Rect`, `Size`, and `Point`
- [x] T016 Implement `PageGeometry` display-box, rotation, and CropBox mapping in `packages/feldexa_core/lib/src/geometry/page_geometry.dart` with tests in `packages/feldexa_core/test/geometry_test.dart` (`contracts/coordinates-and-geometry.md` §1–§2; enables FR-003 and SC-017); T016 owns `PageGeometry`, the single dimensions type used by the ports
- [x] T017 Define the versioned document aggregate, `TemplateOrigin`, `DurablePointer`, and canonical JSON encoding in `packages/feldexa_core/lib/src/model/document.dart`, `packages/feldexa_core/lib/src/model/page_failure.dart`, `packages/feldexa_core/lib/src/model/template_origin.dart`, `packages/feldexa_core/lib/src/model/durable_pointer.dart`, and `packages/feldexa_core/lib/src/model/canonical_json.dart` (`data-model.md` §3.1, §3.9, §3.13, §4; enables FR-043 and FR-044); T017 owns `Document`, `SourceFileRef`, `Page`, `PageFailure`, `AnalysisState`, `DocumentMeta`, `DocumentStatus`, `DocumentPreferences`, `TemplateOrigin`, and `DurablePointer` (`data-model.md` §3.1–§3.3, §3.9, §3.13, and §4.1)
- [x] T018 Implement `FieldSuggestion`, `ConfirmedField`, `FieldValue`, and `FieldVerification` in `packages/feldexa_core/lib/src/model/field.dart` with the enum and length constraints from `data-model.md` §3.4–§3.8 (enables FR-021, FR-028, and FR-031); T018 owns `FieldSuggestion`, `ConfirmedField`, `FieldValue` variants, `FieldVerification`, `SignatureMark`, `FieldType`, `Provenance`, `SuggestionEvidence`, and `FieldValidation` (`data-model.md` §3.4–§3.8)
- [x] T019 Implement the reclassification compatibility rules in `packages/feldexa_core/lib/src/model/reclassification.dart` and tests in `packages/feldexa_core/test/reclassification_test.dart` (FR-029; `data-model.md` §3.5)
- [x] T020 Implement `DurabilityStatus`, `Revision`, `RevisionKind`, and `RevisionContent` in `packages/feldexa_core/lib/src/model/persistence.dart` (FR-044/FR-046; `data-model.md` §2.5, §3.12); T020 owns these persistence types; `DurablePointer` is owned by T017
- [x] T021 Implement `Template`, `TemplateVersion`, `TemplateVersionPointer`, `TemplateMeta`, `TemplateVersionContent`, and `StoredTemplate` in `packages/feldexa_core/lib/src/model/template.dart` (FR-101–FR-106; `data-model.md` §3.10–§3.11); T021 owns these template types
- [x] T022 Define the export contract model `ExportPlan`, `ExportValidation`, `ExportArtifact`, and `ArtifactVerification`, and the `ExportArtifact` state machine, in `packages/feldexa_export/lib/src/model/export_plan.dart` and `packages/feldexa_export/lib/src/model/export_artifact.dart` with optimistic states forbidden; add the workspace dependency on `feldexa_core` (FR-072; `data-model.md` §3.15; `contracts/export-plan.md` §2; `contracts/ports.md` §1 and §2.5; T022 owns these export types)
- [x] T023 Implement the explicit adapter registry and release assertion in `apps/feldexa_app/lib/platform/registry.dart`, `registry_android.dart`, `registry_web.dart`, and `registry_unsupported.dart` (constitution Principle II; plan §Architecture Decisions 8)
- [x] T024 Implement the `FeldexaPlugin` MethodChannel/EventChannel facade in `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/FeldexaPlugin.kt` per `contracts/platform-channel.md` (enables FR-001, FR-013, and FR-095 platform calls). Main `d78114f` was merged without rewrite into the reviewed T024 candidate `8d4821f`; T025 is preserved. The missing Android instrumentation for `contracts/platform-channel.md` §12 was added as `FeldexaPluginInstrumentedTest` and passed 11/11 on 2026-11-15 on the Orca-allocated Pixel 7 API 35 AVD, together with the preserved T025 suite (23/23); no `DEVICE` or performance claim is made. See `reports/2026-11-15-emulator-t024-main-integration.md`. On 2026-11-16 the §12 payload-round-trip row was completed for every method: unknown fields (24/24), strict UUID regex (21 field instances across 16 methods, six malformed shapes each), and 96 MiB + 1 total payloads (24/24) passed as 14/14 T024 tests (26/26 with the preserved T025 suite) on the same Orca-allocated Pixel 7 API 35 KVM AVD; no `DEVICE` or performance claim is made. See `reports/2026-11-16-emulator-t024-payload-roundtrip.md`. On 2026-11-16 `origin/main` `2d793ad` was normal-merged into candidate `dac5e40` as merge `fc23b6c`, preserving T025/T026 storage and T028 adapters; 211 JVM tests and 45/45 Android tests (14 T024 + 12 T025 + 19 T026) passed on the same Orca Pixel 7 API 35 KVM AVD. See `reports/2026-11-16-emulator-t024-main-2d793ad-integration.md`. On 2026-11-16 the accepted Review A total-envelope finding was corrected: the §10 guard now counts the `StandardMethodCodec` method-name string, root map marker/count and every field key in addition to all values, allocation-free and without a second serialized copy; host below/exact/above regressions prove that a payload whose values fit is still rejected when the envelope exceeds the limit, and a real Android codec + `MethodChannel` boundary test proves acceptance at the exact encoded size and rejection one byte over. 214 JVM tests and 46/46 Android tests (15 T024 + 12 T025 + 19 T026) passed on the same Orca Pixel 7 API 35 KVM AVD. See `reports/2026-11-16-emulator-t024-total-payload-boundary.md`. On 2026-11-16 the Review A bounded-allocation finding on `bd78dca` was corrected: the `BigInteger` sizing no longer calls `toString(16)` and derives the exact `StandardMessageCodec` hexadecimal byte length from `signum`/`bitLength`/`bitCount` (zero, positive, negative and power-of-two semantics), `CharSequence` is scanned without `toString()`, and Collection Iterables no longer copy via `toList()`; host codec-equivalence, 64 Mi-bit large-`BigInteger` tiny-budget and fixed-112-byte payload-below/exact/above regressions plus real `StandardMessageCodec`/`StandardMethodCodec` Android regressions passed as 219 JVM tests and 48/48 Android tests (17 T024 + 12 T025 + 19 T026) on the same Orca Pixel 7 API 35 KVM AVD. See `reports/2026-11-16-emulator-t024-biginteger-sizing-correction.md`. On 2026-11-16 the accepted Review A negative-disambiguation finding was corrected: the §10 `BigInteger` branch now checks a cheap `signum`/`bitLength` representation-length lower bound before the exact negative power-of-two `bitCount()` disambiguation, so an oversized negative magnitude rejects without a full magnitude scan while accepted values stay byte-exact across zero, signs, powers and the 1/3/5-byte prefixes; a `BitCountTrackingBigInteger` test double proves zero `bitCount()` calls at budgets above 1/2 bytes but far below the encoded length, and near-boundary negatives stay exact through `PayloadSize` and the real facade. 221 JVM tests and 49/49 Android tests (18 T024 + 12 T025 + 19 T026) passed on the same Orca Pixel 7 API 35 KVM AVD, with app/test APKs byte-identical in-guest and debug-only largeHeap/main/release manifests unchanged. See `reports/2026-11-16-emulator-t024-negative-lower-bound-correction.md`.
- [x] T025 Implement per-document/template Keystore KEK creation, alias lifecycle, and DEK wrap/unwrap in `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage/KeystoreService.kt` (FR-049/FR-050/FR-052; `contracts/storage-format.md` §2.3/§3.6; plan §Storage). Implementation is host-complete. The owner decision applies unwrap authentication/tag mismatch as integrity `SAVE-003` (CR-15); aggregate key loss stays `SAVE-002` and global provider/reset `SAVE-008`. Instrumentation aliases are test-isolated with exact-only cleanup (CR-16). Android instrumentation: the requested Pixel 7/API 35 `EMULATOR` gate passed 12/12 on 2026-11-15 on a uniquely provisioned Pixel 7 API 35 AVD started and assigned through Orca with hardware acceleration (KVM, full boot, package service); the app/test APK identity was unchanged and exclusivity was verified by the Orca session and device state. The earlier non-accepting API 31 TCG observation and the TCG boot-failure record remain historical; no `DEVICE` acceptance and no performance claim are made. See `reports/2026-11-15-emulator-t025-pixel7-api35-kvm-keystore.md`.
- [x] T026 Implement the `FXC1` encrypted store with per-aggregate KEK selection, atomic commit, read-back verification, aggregate deletion, and stale-temp/orphan-alias sweep in `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage/EncryptedStore.kt` (FR-047/FR-052; `contracts/storage-format.md`). Owner decision implemented in `c30cb66`: bounded known-kind history in `head.fx1` (`{revisionId, kind}`, oldest first, at most 16 entries, atomic with the head), automatic retention after the verified read-back (last 3 autosave + newest explicit + newest recovery + protected head), conservative unknown/untracked legacy handling, startup reconciliation, and no template-version pruning. Prune durability corrected in `0c75c57`/`57ce38b`; capacity corrected in `df625d7`: before staging, a missing known history entry must be confirmed by the revision-directory fsync, otherwise the save is refused with retryable `SAVE-003` before any head change, so the 16-entry cap never silently evicts an unconfirmed entry. `storage-format.md`, `data-model.md`, `ports.md`, and `platform-channel.md` are updated. 123 JVM tests pass; the Pixel 7/API 35 `EMULATOR` gate passed 19/19 T026 and 31/31 including T025 with the real `AndroidKeyStore`; app/test APKs `753c9e285b2a...`/`290b1fca7ffc...` match in-guest; committed bundles `t026-head-history-2026-11-15`, `t026-prune-durability-2026-11-15`, `t026-prune-retry-2026-11-15`, and `t026-prune-cap-2026-11-15` (manifest `025d459c120b...`, `verify.sh` PASS) bind the evidence. No `DEVICE`, performance, push, merge, or self-review claim.
- [x] T027 Implement the Android Dart thin clients in `packages/feldexa_adapters_android/lib/` for import, OCR, storage, rendering, delivery, and clock ports (enables FR-001, FR-013, FR-043, FR-063, and FR-071) Implemented 2026-11-16: all defined Android thin clients (import/OCR/document store/raster/PDF export/delivery/clock/ids/lifecycle/diagnostics), the real `StoreService` over `EncryptedStore`+`AndroidKeyStore`, `store.stageSource`/`store.createDocument`/`store.saveRevision`/`store.loadDocument`/`store.list`/`store.delete`/`store.recoveryStamp`/`store.startupRecovery`, and the `AndroidPlatformRuntime` composition seam for T031. The Review-B-corrected candidate `94ef57b` (tree `0444e30`) passed 994 Dart host tests (20 in the Android adapter package), a 260-test JVM suite (13 XML files, including 21 `SignaturePng`, 53 `EncryptedStore`, and 10 `StoreService` cases), 20 channel + 34 storage instrumentation tests, and a real Dart→MethodChannel→native/Keystore E2E on Pixel 7/API 35. It corrects the accepted Review B finding on `db8ce0f` (independent Review A worker PASS; independent Review B worker FAIL solely because `SignaturePng` accepted RGB/indexed images without alpha or a valid `tRNS`): signature PNGs now accept native alpha colour types 4/6 and a validated `tRNS` transparency chunk for opaque types 0/2/3, and truly alpha-free RGB/indexed/grayscale fail with canonical `SAVE-007` without transcoding or mutating the signed bytes. The `tRNS` type, bit depth/sample range, palette length, ordering, and duplicate rules are enforced, `tRNS` on types 4/6 is rejected, and prior bytes/head/revisions stay unchanged. All earlier corrections remain: `MainActivity` composes the store on the normative `filesDir/feldexa/` root (the legacy `feldexa_store` directory is not deleted, renamed, or silently migrated; no migration is introduced), and `store.writeSignature` still validates a real PNG's chunk/CRC/IHDR structure and complete bounded IDAT decode with positive dimensions and a longest edge ≤1024 px before staging, preserving `PLT-002` immutability and returning canonical `SAVE-007` for invalid image/limit while keeping prior bytes/head/revisions. All earlier signature-immutability, raster-eviction, canonical-JSON, cryptography, read-back, source-ownership, and privacy fixes remain. The exact 281-file source manifest and APK/in-guest hashes are bound in the new `94ef57b` reports; the `db8ce0f`, `d45f4df`, and earlier reports are historical and superseded. The template channel payload is still only `{…}` in `contracts/platform-channel.md` §4, so the template methods fail closed (`PLT-001`) pending the template task; no template capability is claimed. See `reports/2026-11-16-emulator-t027-store-evidence-94ef57b.md` and the companion `reports/2026-11-16-t027-host-evidence-94ef57b.md`; the `db8ce0f`, `d45f4df`, and earlier 3a3202c/5b4c295 reports are historical and superseded.
- [x] T028 Implement deterministic `SIMULATED` adapters in `packages/feldexa_adapters_simulated/lib/` for import, page rasterization, storage, OCR, export, and delivery (FR-087; plan §Architecture Decisions 9). Implemented: fixture-catalogue projection with SHA-256/size/page-geometry/expected-OCR validation; fixture-selected import with typed `IMP-001`/`IMP-002`/`IMP-004`/`IMP-007`/`IMP-000` outcomes and staged read-back; deterministic raster keyed by the fixed context and a raster-fingerprint OCR lookup that returns the pre-authored German blocks; in-memory store with verified revision read-back, contractual retention (last 3 autosave + newest explicit + newest recovery + head), immutable template versions and immutable signature assets, `SAVE-001`/`SAVE-002`/`SAVE-003`/`SAVE-008` fault switches, placeholder-title deletion with reference-safe staged-source cleanup (a source shared by another document/template is preserved); preview-PDF export with `SIMULATED` watermark/footer, deterministic normalized trailer and blocking `EXP-001`/`EXP-003`/`EXP-004`/`EXP-005` validation; simulated save/share/print with cancellation. All six adapters return `CapabilityEvidence.simulated` (`web.sim.*.v1`). 97 host-VM tests plus the adapter-level Chrome `SIMULATED` journey pass (the full editor journey remains T128/open; FR-086 is not claimed complete); `dart compile js` succeeds with the export adapter retained; `export` checks request/plan identity, re-verifies actual staged source bytes against the persisted SHA-256, verifies each planned signature against the selected revision's `SignatureMark` and stored SHA-256 before drawing, derives its verification flags from the produced preview bytes, and maps field blocks vs source/page failures to the canonical `ExportBlockedException`/`ExportFailedException` while `validate` keeps the exact EXP code; signature writes refuse an existing asset id with `PLT-002`, preserve prior bytes/revisions, and reject an oversized PNG above 2 MiB with `SAVE-007` before hashing/copying/storing; import creates the returned document aggregate, refuses a full shared logical quota with `SAVE-001` before any visible source/aggregate while preserving prior data, and global `SAVE-008` blocks new store aggregates; raster dimensions are hard-capped; no `EMULATOR`, `DEVICE`, encryption, PDFBox, print-fidelity, performance, push, merge, or self-review claim. Evidence: `reports/2026-11-15-t028-evidence.md`.
- [x] T029 Build all German ARB keys from the **corrected** `contracts/error-catalog.de.md` in `apps/feldexa_app/lib/l10n/app_de.arb` and add `apps/feldexa_app/test/german_strings_test.dart` (FR-090; SC-014). The catalog already carries the corrected `IMP-007` (80 MiB / 83.886.080 Bytes) and `FLD-001` (export is stopped) strings; generate the ARB from that corrected text so T045/T084 only have to verify it.
- [x] T030 Add the font-metrics contract test in `packages/feldexa_export/test/font_metrics_test.dart` comparing Dart advances and glyph coverage against the bundled metrics (FR-067/FR-068)
- [x] T031 Implement startup recovery and temp/export-preview sweeping in `apps/feldexa_app/lib/bootstrap/startup_sweep.dart` (plan §Constraints). Integrated 2026-11-17 as PR #189 (merge `9e91b2d`) from candidate `056de35` (tree `f3dfbb5`) after two independent Codex PASS verdicts on that exact commit (Review A code quality, Review B requirements fulfilment). Delivers the bounded startup sweep with a native recovery deadline, `StartupSweep`/`runStartupSweepBounded`, session-end sweep, German `startupRecoveryIncomplete` notice, and native `EncryptedStore` deadline guards before every durable head promotion (fallback adoption and prune) with a dedicated `PromotionDeadlineReached` that never rewrites the head or maps to `SAVE-003`, plus accurate reporting of fsync-durable prune deletions. Evidence: `EMULATOR` — `flutter test integration_test/t031_startup_sweep_test.dart -d emulator-5554` passed 2/2 on exactly `056de35` (one documented 250 ms timing flake on the first post-update run is retained in the log and not counted as PASS); `NONE` — 170 focused JDK 17 tests (`FeldexaPluginTest` 104, `EncryptedStoreTest` 66) passed. Limits: the full JVM suite was not re-run in the last correction round (pre-existing `EncryptedStoreReviewTest` memory-probe failure, unchanged); reviewer-owned `precision-testability.md` remains 0/36 unchecked under the recorded owner authorization; no physical-device run is claimed. See `reports/2026-11-17-orca-emulator-integration-t031-evidence.md`, `reports/2026-11-17-t031-commit-boundary-evidence.md`, and `reports/2026-11-16-t031-evidence.md`.
- [x] T032 [P] Create the evidence report schema and validator in `tools/evaluation/report_schema.json` and `tools/evaluation/validate_report.dart` (constitution Principle VIII)
- [ ] T033 Assemble the rights-cleared corpus of at least 20 real German authority forms and record provenance in `tools/corpus/manifest.json` (constitution Principle IV; SC-001)
- [ ] T034 Freeze `corpus-1.0.0` and `metric-definition.v1.md` and implement the scorer in `tools/evaluation/metric-definition.v1.md` and `tools/evaluation/score.dart` before any scoring run (constitution Principle IV; SC-001/SC-002)
- [x] T035 [P] Record the manual-baseline protocol in `tools/evaluation/manual-baseline.md` using the add/move/resize/reclassify comparison from `research.md` D-18 (SC-003)
- [x] T036 Implement the failure-injection harness for clock, quota, keystore, and write interruption in `packages/feldexa_testkit/lib/src/faults.dart` and the `FakeRegistry` test seam from `contracts/ports.md` §4 (constitution Principle VIII)

**Checkpoint**: Contracts, models, ports, encryption, German strings, corpus, frozen metrics, and fault injection are ready. User stories can start after this.

---

## Phase 3: User Story 1 — Import Scanned PDF Documents (Priority: P1) 🎯 MVP slice

**Goal**: A user imports a scanned PDF through Android SAF, sees every original page unchanged, and gets specific German rejection messages without a stored record.

**Independent Test**: Import a single-page and a five-page image-only PDF; verify page count, order, orientation, dimensions, and pixel fidelity, and a byte-identical source. Import password-protected, truncated, non-PDF, unknown-failure, and partially damaged files and verify the exact German behavior and no document entry.

- [X] T037 [P] [US1] Write the import-port and preflight contract tests in `packages/feldexa_ports/test/import_port_test.dart` and `packages/feldexa_core/test/import_contract_test.dart` (FR-001/FR-002)
- [x] T038 [US1] Implement the SAF `ACTION_OPEN_DOCUMENT` streaming import in `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/import/ImportService.kt` (FR-001; FR-095) Integrated 2026-11-18 as PR #190 (merge `420f1bd`) from final candidate `f2dec00` (code tree `3f3e388`) after two independent Codex PASS verdicts on that candidate. Delivers the SAF `ACTION_OPEN_DOCUMENT` picker with stream-only URI consumption, bounded 64 KiB SHA-256 hashing, the 80 MiB (83,886,080-byte) cap, cancellation-safe staged-aggregate cleanup (late registration inside the handle lock, first-wins failure recording, failure read in the publication critical section), a lock-free repeated-cancel fast path, display-name resolution off the UI thread, and a schema-conformant evidence report (`reports/2026-11-17-t038-evidence.md`, validator PASS 1/1) with its `NONE` index row. Evidence `NONE`: 300 JVM tests / 0 failures (maintainer forced rerun, 161 tasks executed) and `flutter analyze` clean; no `EMULATOR`/`DEVICE` claim. Residual: a non-blocking interrupted-first-cancel reply window (`cancelled:false` while a queued claim may later succeed) lacks a regression test; T039/T040/T041/T045 remain deferred. CI NOT_REQUIRED (no configured workflows or protection).
- [x] T039 [US1] Implement PDF preflight with page geometry and encryption detection in `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/pdf/PdfPreflight.kt` (FR-003/FR-005/FR-006; `contracts/platform-channel.md`) Integrated 2026-11-18 as PR #191 (merge `cb94953`) from final candidate `23b145e` (code `b94519e` + `9db2d36`) after two independent Codex PASS verdicts. Delivers per-page mediaBox/cropBox/rotation in document order, encryption/damage classification (`IMP-001` without password capture, `IMP-002`, `IMP-004`, `IMP-005`, `IMP-006` with `pageFailures`, all-unreadable rejected), a documented 100-page bound enforced before allocation/page access (DoS review correction), and a rebuild-stable schema-conformant evidence report (`reports/2026-11-18-t039-evidence.md`, validator PASS 1/1) with its `NONE` index row. Evidence `NONE`: 304 tests/14 suites at the T039 candidate and 325/15 on the merged base, 0 failures (maintainer forced rerun), `assembleDebug` PASS, `flutter analyze` clean; no `EMULATOR`/`DEVICE` claim and no channel wiring (T040/T041/T042/T046 remain). Residual: German over-scale wording is a T041/owner question; the 100-page limit is the documented supported maximum. CI NOT_REQUIRED (no configured workflows or protection).
- [x] T040 [US1] Implement the streaming encrypted source copy in `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/import/ImportService.kt` and `.../storage/EncryptedStore.kt` (FR-004; FR-095/FR-096) Integrated 2026-11-18 as PR #193 (merge `ed594e9`) from final candidate `3b3f5ae` after two independent Codex PASS verdicts (incl. delta revalidation). Delivers true streaming encrypted source copy (64 KiB hash/count + 1 MiB FXC1 write passes, no plaintext temp), staged-source re-verification before atomic revision→head→meta commit with read-back and duplicate rejection, preflight on staged ciphertext via a seekable decrypting reader, deadlock-free cancellation during commit (lock-free claim inside the lifecycle lock; documented lock order), single stream ownership with exactly-once close and close-count tests, and cleanup failures propagated with documented precedence so `PLT-004` is never reported with residue. Evidence `NONE`: 357 JVM tests / 17 suites / 0 failures (maintainer forced rerun), `assembleDebug`, `flutter analyze`, report validator PASS and rebuild-stable; RED evidence for deadlock, stream leak, cleanup precedence and double-close. No `EMULATOR`/`DEVICE` claim (T046). Residuals: 1x1 placeholder for structurally unreadable pages (T044), late-cancel `PLT-004` with a complete document, cleanup residue surfaced as `SAVE-003` and swept at startup. CI NOT_REQUIRED.
- [x] T041 [US1] Map every import failure to the German catalog and suppress document creation in `apps/feldexa_app/lib/features/start/import_error_mapper.dart` (FR-005, FR-006, FR-007, FR-008, FR-009; `contracts/error-catalog.de.md` §1) Integrated 2026-11-18 as PR #192 (merge `bcf0424`) from final candidate `7df7e5d` after two independent Codex PASS verdicts. Delivers catalog-backed German presentation/recovery for import failures (`IMP-000`/`IMP-001`–`IMP-005`/`IMP-007`, `PLT-004`, import-reachable `SAVE-*`), an explicit unknown-cause `IMP-005` fallback with `isUnrecognized`, FR-007 truthfulness (password claim only for the typed kind or the canonical `import.rejected.passwordProtected` message; unsupported/noncanonical encryption presents the truthful `IMP-004` text with the flag false and a recorded owner/T045 wording follow-up), FR-009 suppression (sealed `ImportOutcome`, private candidate type, `createDocument` only after a verified source; tested for every rejection/cancellation path), and the `IMP-006` partial warning with ascending 1-based pages (`{pages}` wording stays T044/owner). Evidence `NONE`: 153 host tests / 13 files (22 mapper tests), `flutter analyze` and `dart format` clean, report validator PASS 1/1 and rebuild-stable. No `EMULATOR`/`DEVICE` claim; T040/T046 remain. CI NOT_REQUIRED.
- [x] T042 [US1] Implement the pdfrx page viewer and source-point geometry mapping in `apps/feldexa_app/lib/features/editor/page_view.dart` (FR-003; `contracts/coordinates-and-geometry.md`) Integrated 2026-11-18 as PR #194 (merge `01e01e5`) from final candidate `dc37fe3` after two independent Codex PASS verdicts (incl. merge-delta revalidation). Delivers the pdfrx viewer rendering the unchanged source through a custom `_PdfrxPage`/`PdfPage.renderForDisplay` path (no raw renderer logging; content-free `PageViewLoadFailure`), display-point geometry derived only from `PageGeometry.displaySize` (zoom/DPR-invariant round-trips, rotations incl. CropBox offsets, display-space hit-testing), the contract's 4096-px long-edge raster cap with 300 DPI/DPR limits, a documented 0.001 pt minimum page extent, a finite `desiredScale` ceiling, target-scale `fitWidth`, finiteness checks on derived rect extents and page-origin sums, one document per source, lazy viewport-limited pages and correct disposal. Evidence `NONE`: 41 viewer tests / 194 total / 14 files / 0 failures (maintainer forced receipt), analyze/format/validator PASS, real RED for the cap/min-extent/far-edge/desiredScale corrections; fitWidth RED limitation disclosed. Production PDFium pixels/gestures/Android are unverified (T046); T040/T043/T044 wiring remains. CI NOT_REQUIRED.
- [x] T043 [US1] Implement page-strip navigation that works before analysis finishes in `apps/feldexa_app/lib/features/editor/page_strip.dart` (US1 scenario 2; FR-018) Integrated 2026-11-18 as PR #195 (merge `1041962`) from candidate `b668922` after two independent Codex PASS verdicts. Delivers the page strip with ordered per-page state and unreadable/uncertain markers, full FR-018 usability while every page is still pending/analyzing, tap→`PageViewController.scrollToPage` delegation (no offset math), visible selection, compact prev/next below 600 dp and the full strip at ≥600 dp, German semantic labels/hints, ≥48 dp targets, non-colour state, 200% text scaling and a lazy 100-page list. Evidence `NONE`: 15 focused / 209 total host widget tests, analyze/format/validator PASS and rebuild-stable; no Android/TalkBack/golden claim. Residuals: hardcoded German analysis-state strings pending a catalog/ARB round, gesture-driven scroll does not update selection, and the strip is not yet routed into an editor screen. CI NOT_REQUIRED.
- [x] T044 [US1] Handle partially unreadable pages and the `IMP-006` warning in `apps/feldexa_app/lib/features/editor/page_state.dart` (FR-010) Integrated 2026-11-18 as PR #196 (merge `d675f0c`) from final candidate `bb9816b` (code `5c12655`) after two independent Codex PASS verdicts (incl. merge-delta revalidation). Delivers per-page state from persisted failure data, suppression of the T040 1x1 placeholder (unreadable pages expose `displaySize == null`), partial-import success with the catalog-backed `IMP-006` warning (ascending 1-based pages, `imp006`/`imp006Recovery`), and an explicit `PageStateFullyUnreadable` error for all-unreadable input; no codes/paths/URIs/titles in user text. Evidence `NONE`: 34 focused / 228 candidate / 243 merged-base host tests, analyze/format/validator PASS and rebuild-stable. Provenance corrected after a recorded Principle IX deviation (first pass read the skill file without invoking the registered command; a correction round invoked it). No Android/UI/TalkBack claim; wiring remains. CI NOT_REQUIRED.
- [x] T045 [US1] Enforce the 80 MiB (83,886,080-byte) import cap and **verify** the already-corrected `IMP-007` wording ("80 MiB (83.886.080 Bytes)") in `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/import/ImportService.kt` and `contracts/error-catalog.de.md` (FR-005; plan §Performance Goals; CHK028; CR-3). Assert that the ARB key generated from the T029 corrected catalog and the German rejection message match that text. Integrated 2026-11-18 as PR #197 (merge `18994a9`) from candidate `9c59e9a` after two independent Codex PASS verdicts. Verification-first: the 80 MiB (83,886,080-byte) cap and the corrected `IMP-007` text were already correct; no production/catalog/ARB/mapper change was needed. Adds five cap tests (cap−1/cap/cap+1, clamp above cap, constant/store binding), a real-store exact boundary (999/1,000/1,001 bytes), and an artifact-backed character-for-character assertion across catalog §1 `IMP-007`, ARB `imp007`, generated `AppLocalizationsDe.imp007` and the T041 mapper (accepts „80 MiB (83.886.080 Bytes)“, rejects „80 MB“). Evidence `NONE`: 363 JVM / 17 suites and 244 Dart / 16 files on the merged base (363/17 and 210/16 at the candidate), analyze/format/validator PASS and rebuild-stable. Provenance deviation recorded and corrected by a real registered-command invocation. No Android/80 MiB staging claim (T046). CI NOT_REQUIRED.
- [ ] T046 [US1] Add the Android import integration test for single, five-page, protected, truncated, non-PDF, unknown-failure, and partially damaged files in `apps/feldexa_app/integration_test/android_import_test.dart` (US1 Independent Test; SC-011)
- [ ] T047 [P] [US1] Add the `SIMULATED` browser import journey in `apps/feldexa_app/integration_test/web_import_test.dart` (FR-086/FR-087)
- [ ] T048 [US1] Add the source-integrity test in `apps/feldexa_app/integration_test/source_integrity_test.dart`: assert byte identity and unchanged modification time of the picked file, then move/delete the originally picked file, reopen, render, and export the saved document from the protected internal copy (FR-004/FR-095/FR-096; SC-019)
- [ ] T049 [US1] Add German import-message and error-semantics tests in `apps/feldexa_app/test/import_semantics_test.dart` (FR-006–FR-008; FR-094)

**Checkpoint**: US1 is independently usable and testable. No analysis or export is required to demonstrate it.

---

## Phase 4: User Story 2 — Automatically Detect Form Fields (Priority: P1)

**Goal**: Imported pages produce unconfirmed field suggestions from document geometry, with OCR as an auxiliary signal, per-page failure isolation, and honest uncertainty.

**Independent Test**: Run detection on a reference form with known ground truth; verify suggestions at expected positions with plausible types, suggestions distinct from confirmed fields, and a deliberately unreadable page not preventing suggestions on other pages.

- [ ] T050 [P] [US2] Write the suggestion-envelope contract test in `packages/feldexa_recognition/test/suggestion_schema_test.dart` (`contracts/recognition-output.md` §1–§2)
- [ ] T051 [US2] Implement 200 DPI grayscale page raster analysis in `packages/feldexa_recognition/lib/src/raster.dart` (`contracts/coordinates-and-geometry.md` §4)
- [ ] T052 [US2] Implement ruling-line, box, table-grid, whitespace, and alignment detectors in `packages/feldexa_recognition/lib/src/geometry_detector.dart` (FR-011/FR-013/FR-016)
- [ ] T053 [US2] Implement label proximity and keyword-driven type inference in `packages/feldexa_recognition/lib/src/type_inference.dart` (FR-012; `contracts/recognition-output.md` §3)
- [ ] T054 [US2] Implement the confidence and uncertainty model in `packages/feldexa_recognition/lib/src/confidence.dart` (FR-015/FR-083; `contracts/recognition-output.md` §3.3–§3.4)
- [ ] T055 [US2] Implement `IoU ≥ 0.5` conflict detection while retaining both candidates in `packages/feldexa_recognition/lib/src/conflicts.dart` (FR-025; `contracts/recognition-output.md` §6)
- [ ] T056 [US2] Implement the OCR port and bundled ML Kit adapter in `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/ocr/MlKitOcrService.kt` and `packages/feldexa_adapters_android/lib/src/ocr_adapter.dart` (FR-013; constitution Principles IV and VI)
- [ ] T057 [US2] Implement per-page analysis state and failure isolation in `packages/feldexa_recognition/lib/src/page_analysis.dart` (FR-017, FR-018, FR-019, FR-020; `contracts/recognition-output.md` §4); T057 owns `FieldSuggestionSet`
- [ ] T058 [US2] Persist suggestions, resolution states, and provenance in revisions in `packages/feldexa_core/lib/src/model/document.dart` (FR-014/FR-015; `contracts/recognition-output.md` §7)
- [ ] T059 [US2] Add the frozen strict-matching contract test in `tools/evaluation/test/metric_definition_test.dart` using the `IoU ≥ 0.5` and identical-type rule (SC-001/SC-002)
- [ ] T060 [US2] Run the explicitly unscored frozen-metric dry run and record it in `specs/001-scanned-form-workflow/reports/corpus-1.0.0-dry-run.md` after T033 and T034 (CHK031; constitution Principle IV; SC-001/SC-002; evidence root per this file's Evidence Discipline)
- [ ] T061 [US2] Add the Android recognition integration test on synthetic and corpus fixtures with per-page failure isolation in `apps/feldexa_app/integration_test/android_recognition_test.dart` (US2 Independent Test)
- [ ] T062 [P] [US2] Add the `SIMULATED` browser recognition test in `apps/feldexa_app/integration_test/web_recognition_test.dart` (FR-086/FR-087)
- [ ] T063 [US2] Record per-stage raster/OCR/detection timings in `tools/evaluation/benchmark_recognition.dart` for later SC-004 measurement (SC-004; `research.md` measurement decision)

**Checkpoint**: US2 delivers suggestions and failure isolation independently; no review or export is required.

---

## Phase 5: User Story 3 — Review and Correct Field Suggestions (Priority: P1)

**Goal**: The user confirms, rejects, adds, removes, moves, resizes, reclassifies, reorders, undoes, and restores fields, with geometry attached to the page at every zoom level.

**Independent Test**: Take a form with wrong, duplicated, and missing suggestions; perform every correction at several zoom levels and pages; verify geometry alignment, provenance distinction, undo/redo, and recovery of an earlier state.

- [ ] T064 [P] [US3] Write the suggestion-lifecycle contract test in `packages/feldexa_core/test/field_lifecycle_test.dart` (FR-021/FR-022/FR-028)
- [ ] T065 [US3] Implement confirm, reject, and undo lifecycle commands in `packages/feldexa_application/lib/src/review/confirm_suggestion.dart` (FR-021/FR-022/FR-027)
- [ ] T066 [US3] Implement add, remove, move, resize, and reclassify commands in `packages/feldexa_application/lib/src/review/edit_field.dart` (FR-023/FR-024/FR-029)
- [ ] T067 [US3] Implement bounded undo/redo with 500 ms command coalescing in `packages/feldexa_application/lib/src/review/command_history.dart` (FR-027; `data-model.md` §3.14)
- [ ] T068 [US3] Implement the conflict badge and per-candidate resolution sheet in `apps/feldexa_app/lib/features/editor/review_conflict_sheet.dart` (FR-025; `contracts/editor-interactions.md` §3)
- [ ] T069 [US3] Implement field-overlay painting from model coordinates in `packages/feldexa_ui/lib/src/field_overlay.dart` (FR-024; SC-017)
- [ ] T070 [US3] Property-test geometry round-trips at `0.5, 1, 1.75, 3, 8` zoom and rotations 0/90/180/270 with CropBox offsets in `packages/feldexa_core/test/geometry_roundtrip_test.dart` (SC-017; `contracts/coordinates-and-geometry.md` §6)
- [ ] T071 [US3] Add the Android touch drag/resize review test at 0.5×, 1×, 3×, and 8× in `apps/feldexa_app/integration_test/android_review_test.dart` (`contracts/editor-interactions.md` §12)
- [ ] T072 [P] [US3] Add the `SIMULATED` browser review interaction suite in `apps/feldexa_app/integration_test/web_review_test.dart` (FR-086/FR-089)
- [ ] T073 [US3] Implement field-order review and reordering in `apps/feldexa_app/lib/features/editor/field_order.dart` (FR-026)
- [ ] T074 [US3] Implement provenance badges for suggestion, confirmed, and user-created fields in `packages/feldexa_ui/lib/src/provenance_badge.dart` (FR-028)
- [ ] T075 [US3] Add the degraded-detection review test in `apps/feldexa_app/test/review_degraded_test.dart` (FR-030; US3 Independent Test)

**Checkpoint**: US3 works on its own and leaves the document fully usable when detection is wrong or absent.

---

## Phase 6: User Story 4 — Fill Forms Efficiently (Priority: P1)

**Goal**: The user selects any field, gets the right control, enters valid German values, sees completion state, and never loses characters or geometry.

**Independent Test**: Fill a two-page reference form entirely by touch on Android, including text, numbers, dates, checkboxes, multiline text, a drawn signature, and deliberately overflowing text; verify no truncation, all values survive navigation, and every field remains editable.

- [ ] T076 [P] [US4] Write the type-control contract test in `apps/feldexa_app/test/field_controls_test.dart` (FR-031/FR-032)
- [ ] T077 [US4] Implement field selection and visual highlight in `packages/feldexa_ui/lib/src/field_selection.dart` (FR-031)
- [ ] T078 [US4] Implement the zoom-to-field target formula and test in `packages/feldexa_core/lib/src/geometry/zoom.dart` and `packages/feldexa_core/test/zoom_test.dart` (FR-034; CHK005)
- [ ] T079 [US4] Implement single-line and multiline text controls with German IME support in `apps/feldexa_app/lib/features/fill/text_control.dart` (FR-033/FR-035/FR-039/FR-040)
- [ ] T080 [US4] Implement number parsing, German decimal comma, optional thousands separators, negative sign, and canonical storage in `packages/feldexa_core/lib/src/validation/number.dart` (FR-032; `data-model.md` §3.6; CHK007)
- [ ] T081 [US4] Implement strict `Tag.Monat.Jahr` date validation and `DATE-001`/`DATE-002` handling in `packages/feldexa_core/lib/src/validation/date.dart` (FR-107, FR-108, FR-109, FR-110; SC-022; clarification 5)
- [ ] T082 [US4] Implement the checkbox control with a 48 dp hit slop independent of the exported mark in `apps/feldexa_app/lib/features/fill/checkbox_control.dart` (FR-042; `contracts/editor-interactions.md` §5)
- [ ] T083 [US4] Implement the signature sheet bound to the current document only in `apps/feldexa_app/lib/features/fill/signature_sheet.dart` (FR-036)
- [ ] T084 [US4] Implement the overflow warning and **verify** the already-corrected `FLD-001` wording (export is stopped until the text is shortened or the field enlarged) against blocking `EXP-001` in `apps/feldexa_app/lib/features/fill/overflow_warning.dart` and `contracts/error-catalog.de.md` (FR-037/FR-038/FR-068; CHK030; CR-4). Assert that the ARB key generated from the T029 corrected catalog and the warning text match that string.
- [ ] T085 [US4] Implement per-field completion state for optional and empty fields in `apps/feldexa_app/lib/features/editor/field_completion.dart` (FR-041; CHK008)
- [ ] T086 [US4] Add the Android two-page touch fill test in `apps/feldexa_app/integration_test/android_fill_test.dart` (US4 Independent Test)
- [ ] T087 [P] [US4] Add the `SIMULATED` browser fill test in `apps/feldexa_app/integration_test/web_fill_test.dart` (FR-086/FR-087)

**Checkpoint**: US4 is independently fillable and preserves values, signatures, and geometry.

---

## Phase 7: User Story 5 — Save and Recover Work (Priority: P1)

**Goal**: Autosave, explicit save, foreground flush, atomic verified commits, key-loss isolation, storage-failure recovery, and the minimal „Meine Dokumente“ list.

**Independent Test**: Fill partially, save, force-stop, and reopen; verify geometry, types, values, and signatures. Edit without saving, force-stop, and verify the last durable state plus honest unsaved status. Repeat with unavailable key material and induced storage exhaustion.

- [ ] T088 [P] [US5] Write the durability-state contract test in `packages/feldexa_core/test/durability_test.dart` (FR-046; `data-model.md` §2.5)
- [ ] T089 [US5] Implement the 2 s debounced autosave, foreground flush, and explicit save in `packages/feldexa_application/lib/src/persistence/autosave.dart` (FR-045; SC-020; clarification 2; CHK001)
- [ ] T090 [US5] Implement atomic save orchestration with read-back verification in `packages/feldexa_application/lib/src/persistence/save_document.dart` (FR-043/FR-047/FR-048; FR-106 pattern)
- [ ] T091 [US5] Implement the durability labels, status surfaces, and the pre-emptive PRIV-001 key/backup disclosure in `apps/feldexa_app/lib/features/editor/durability_status.dart` (FR-046/FR-051; `contracts/error-catalog.de.md` §3)
- [ ] T092 [US5] Add the force-stop recovery test for edits older and newer than 2 seconds in `apps/feldexa_app/integration_test/android_autosave_recovery_test.dart` (SC-009/SC-020)
- [ ] T093 [US5] Add the key-loss isolation test in `apps/feldexa_app/integration_test/key_loss_test.dart`, and assert in the same suite that opening a saved document requires no separate app password and no mandatory biometric unlock (FR-052/FR-050; `quickstart.md` §8)
- [ ] T094 [US5] Add the storage-exhaustion and no-success-report test in `apps/feldexa_app/integration_test/storage_full_test.dart` (FR-074/FR-075/FR-076; SC-010)
- [ ] T095 [US5] Implement the start area with separate document and template groups in `apps/feldexa_app/lib/features/start/stored_items.dart`, showing each entry's title, last-edited date, and status (FR-058/FR-097/FR-098; clarification 3); T095 owns `DocumentSummary` as a projection of the port-level `StoredMeta`, not a second persisted type
- [ ] T096 [US5] Implement list deletion with a German confirmation naming what remains in `apps/feldexa_app/lib/features/start/delete_item.dart` (FR-053/FR-099)
- [ ] T097 [US5] Implement the 50-item list test in `apps/feldexa_app/integration_test/stored_list_50_test.dart` and keep it **blocked on owner decision OD-4** for the numeric interaction/latency bound; do not invent a bound, record the measured result as unratified until OD-4 is decided (FR-100; CHK024)
- [ ] T098 [US5] Verify no plaintext PDF, log, thumbnail, or backup residue in `apps/feldexa_app/integration_test/plaintext_leak_test.dart` (FR-082; CHK029)
- [ ] T099 [US5] Verify diagnostics exclude paths, file names, OCR text, values, and signatures in `apps/feldexa_app/test/diagnostics_privacy_test.dart` (FR-081)
- [ ] T100 [US5] Verify a blocked storage operation is retryable after space is freed without re-import in `apps/feldexa_app/integration_test/storage_retry_test.dart` (FR-077)
- [ ] T101 [P] [US5] Add the `SIMULATED` browser persistence and recovery test in `apps/feldexa_app/integration_test/web_persistence_test.dart` (FR-086/FR-087)

**Checkpoint**: US5 returns the last durable state honestly and never reports optimistic success.

---

## Phase 8: User Story 7 — Export a Completed PDF (Priority: P1)

**Goal**: Produce a flattened, self-contained PDF with original pages unchanged, values at their field positions, correct checkbox states and signatures, artifact-level verification, and no partial success.

**Independent Test**: Complete a two-page reference form with all field types and German characters, export, open in at least two independent readers, verify page count/appearance/placement/checkbox states/no clipping/printability, and verify the source document is unchanged.

- [ ] T102 [P] [US7] Write the export-plan schema contract test in `packages/feldexa_export/test/export_plan_test.dart` (`contracts/export-plan.md` §2); the test targets the T022 `ExportPlan`/`ExportValidation` models
- [ ] T103 [US7] Implement text layout, line breaking, baselines, and blocking clip detection in `packages/feldexa_export/lib/src/layout.dart` (FR-062/FR-064/FR-067/FR-068); build the T022 `ExportPlan` values from the confirmed document snapshot
- [ ] T104 [US7] Implement the PDFBox flattening applier that imports original pages and appends text, checkbox, and signature overlays in `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/export/PdfExportService.kt` (FR-063/FR-065/FR-066/FR-069; `contracts/export-plan.md` §5)
- [ ] T105 [US7] Implement the independent artifact verification harness in `tools/pdf_verify/verify.sh` using `qpdf`, Poppler, and MuPDF (FR-069; SC-005/SC-006; CHK019)
- [ ] T106 [US7] Implement the ephemeral export preview and its cleanup lifecycle in `apps/feldexa_app/lib/features/export/preview.dart` (FR-070/FR-072; CHK029)
- [ ] T107 [US7] Implement Android save, share, and print delivery flows in `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/delivery/DeliveryService.kt` (FR-071)
- [ ] T108 [US7] Add the failed/interrupted export test that asserts no final artifact exists in `apps/feldexa_app/integration_test/export_failure_test.dart` (FR-072; SC-010)
- [ ] T109 [US7] Add the Android two-page export and artifact-verification test in `apps/feldexa_app/integration_test/android_export_test.dart`: verify field placement, checkbox states, and signatures, and assert that suggestion/confirmed/user-created provenance survives save, reopen, and export in the working model while the flattened artifact still contains no interactive form controls (US7 Independent Test; FR-069/FR-073; SC-005/SC-006; constitution Principle IV)
- [ ] T110 [US7] Add the printability test with the Android print preview and two independent engines in `apps/feldexa_app/integration_test/print_test.dart` (SC-005; CHK019)
- [ ] T111 [P] [US7] Add the `SIMULATED` export watermark and non-production-artifact test in `apps/feldexa_app/integration_test/web_export_test.dart` (FR-087; `contracts/export-plan.md` §7)
- [ ] T112 [US7] Define the full export verification set and its membership in `tools/pdf_verify/verification-set.md` (SC-006; CHK018)
- [ ] T113 [US7] Implement the preflight unresolved-suggestion warning against the explicitly **provisional** `contracts/export-plan.md` §3.4 and the current FR-062 wording in `apps/feldexa_app/lib/features/export/preflight.dart`: empty fields never block export; unresolved overlapping suggestions are excluded and warned only under the provisional policy, and that behavior stays blocked on owner decision OD-1. No task or test may treat the non-blocking behavior as the settled export policy (FR-025/FR-062; CHK009)

**Checkpoint**: US7 is independently exportable and the artifact, not the UI, proves correctness.

---

## Phase 9: User Story 6 — Explicitly Save Reusable Empty Templates (Priority: P2)

**Goal**: An explicit "Als Vorlage speichern" action creates a value-free template; the template can be edited only as layout; each save creates an immutable new version; derived documents never change.

**Independent Test**: Create a template from a filled document; verify pages and confirmed fields but zero values/signatures. Create two documents from it, edit both, and verify the template and the sibling document are unchanged. Edit the template and verify existing documents keep their pinned version.

- [ ] T114 [P] [US6] Write the template-invariant contract test in `packages/feldexa_core/test/template_test.dart` (FR-054–FR-057; SC-013)
- [ ] T115 [US6] Implement the explicit "Als Vorlage speichern" flow with value and signature exclusion in `apps/feldexa_app/lib/features/templates/create_template.dart` (FR-054, FR-055, FR-056, FR-057, FR-061; clarification 4)
- [ ] T116 [US6] Implement the layout-only template editor with disabled value and signature controls in `apps/feldexa_app/lib/features/templates/template_editor.dart` (FR-101/FR-102; clarification 4)
- [ ] T117 [US6] Implement immutable template versions, derived-document pinning, and the "use a template" flow that creates a new independent document with empty values, copied source pages, and the pinned template version in `packages/feldexa_application/lib/src/templates/template_versions.dart` and `apps/feldexa_app/lib/features/templates/use_template.dart` (FR-059/FR-103/FR-104/FR-105; clarification 4)
- [ ] T118 [US6] Add the template-save atomicity test equivalent to the document-save rule in `apps/feldexa_app/integration_test/template_atomicity_test.dart` (FR-106; CHK035)
- [ ] T119 [US6] Add the template-deletion independence test in `apps/feldexa_app/integration_test/template_delete_test.dart` (FR-060/FR-099; CHK034)
- [ ] T120 [US6] Add the Android template independence and version suite in `apps/feldexa_app/integration_test/template_versions_test.dart` (FR-059; SC-012/SC-021)
- [ ] T121 [P] [US6] Add the `SIMULATED` browser template test in `apps/feldexa_app/integration_test/web_template_test.dart` (FR-086/FR-087)

**Checkpoint**: US6 is independently usable and never mutates a template or a sibling document.

---

## Phase 10: User Story 8 — Understand Recognition Quality (Priority: P2)

**Goal**: The user can see uncertainty, failed pages, machine suggestions, and confirmed fields, and no surface claims complete or error-free recognition.

**Independent Test**: Use a low-contrast, skewed form and a damaged page; verify uncertain suggestions are distinct from confident and confirmed fields, the damaged page is explained in German, the rest remains usable, and no surface claims full recognition.

- [ ] T122 [US8] Implement the confidence/uncertainty badge in `packages/feldexa_ui/lib/src/uncertainty_badge.dart` (FR-083)
- [ ] T123 [US8] Implement German failed-page and unsupported-structure explanations in `apps/feldexa_app/lib/features/editor/page_failure.dart` (FR-084; `contracts/error-catalog.de.md` REC-002/REC-003)
- [ ] T124 [US8] Implement provenance distinction in the document view and summary in `apps/feldexa_app/lib/features/editor/recognition_summary.dart` (FR-085)
- [ ] T125 [US8] Add the no-completeness-claim audit test in `apps/feldexa_app/test/recognition_honesty_test.dart` (US8 scenario 5; `contracts/error-catalog.de.md` §2)
- [ ] T126 [US8] Add the low-contrast, skewed, and damaged-page recognition test in `apps/feldexa_app/integration_test/android_recognition_degraded_test.dart` (US8 Independent Test; FR-083)
- [ ] T127 [P] [US8] Add the `SIMULATED` uncertainty presentation test in `apps/feldexa_app/integration_test/web_uncertainty_test.dart` (FR-086/FR-087)

**Checkpoint**: US8 is independently demonstrable and never overclaims recognition.

---

## Phase 11: User Story 9 — Fast Browser-Based Development and Validation (Priority: P2)

**Goal**: The full editing journey runs in Chrome on deterministic fixtures, every simulated result is labeled `SIMULATED`, and browser evidence is reported separately from Android evidence.

**Independent Test**: In Chrome, run the editing journey at several viewport sizes; verify geometry, overlays, navigation, editing, and accessibility; confirm every simulated platform result is labeled and browser results are never counted as Android evidence.

- [ ] T128 [US9] Implement the Chrome editing journey test in `apps/feldexa_app/integration_test/web_journey_test.dart` (FR-086; US9 Independent Test)
- [ ] T129 [US9] Wire `SIMULATED` labeling through the UI banner, structured logs, and report fields in `packages/feldexa_ui/lib/src/simulated_banner.dart` and `packages/feldexa_ports/lib/src/evidence.dart` (FR-087)
- [ ] T130 [US9] Add the evidence-separation assertion in `apps/feldexa_app/test/evidence_separation_test.dart` (FR-088; constitution Principle VIII)
- [ ] T131 [US9] Add the viewport, responsive-layout, and accessibility-semantics test in `apps/feldexa_app/integration_test/web_viewport_test.dart` (US9 scenario 5; FR-091; SC-015)
- [ ] T132 [US9] Add the browser/Android geometry-parity test in `apps/feldexa_app/integration_test/geometry_parity_test.dart` (FR-089; CHK011)

**Checkpoint**: US9 enables fast feedback without being misrepresented as Android acceptance.

---

## Phase 12: Polish and Cross-Cutting Verification

**Purpose**: Close the remaining precision, evidence, traceability, and acceptance gaps identified by the checklist assessment.

- [ ] T133 Run the release-only German-string audit with the `SIMULATED` allowlist in `apps/feldexa_app/test/german_release_audit_test.dart` (SC-014; FR-087; CHK023/CHK025; constitution Principles II and VIII)
- [ ] T134 Run the numeric accessibility audit at 200 % text, 4.5:1/3:1 contrast, and 48 dp targets in `apps/feldexa_app/integration_test/accessibility_audit_test.dart` (SC-015; FR-092/FR-093; CHK022)
- [ ] T135 Record the SC-004 performance protocol with ≥20 runs, one warm-up, representative page set, build mode, and device profile in `tools/evaluation/performance_protocol.md` (SC-004; CHK014)
- [ ] T136 Execute the Samsung Galaxy A54 5G performance run and record it in `specs/001-scanned-form-workflow/reports/2026-11-12-device-performance.md` (SC-004; CHK014)
- [ ] T137 Record the SC-016 journey-timing and SC-018 first-time-usability protocol in `tools/evaluation/journey_protocol.md`; participant and observation details remain blocked on owner decision OD-2. After OD-2 is resolved, execute the SC-016 journey-timing run and the SC-018 5-of-5 first-time usability run and record both results in `specs/001-scanned-form-workflow/reports/2026-11-12-usability.md`. Until OD-2 is decided this task stays explicitly blocked and executes neither run (SC-016/SC-018; CHK017)
- [ ] T138 Add the outbound-transmission and socket observation test plus release-manifest audit in `apps/feldexa_app/integration_test/network_observation_test.dart` (SC-007/SC-008; FR-078/FR-079/FR-080; CHK020)
- [ ] T139 Record corpus diversity strata and the provenance/rights record in `tools/corpus/manifest.json` and `tools/corpus/README.md` (constitution Principle IV; CHK033)
- [ ] T140 Record the plan-budget traceability table and label untraceable values as non-binding engineering budgets in `specs/001-scanned-form-workflow/reports/2026-11-12-budget-traceability.md` (CHK027; supports SC-004 and SC-016 budget evidence)
- [ ] T141 Record the named-device equivalence rule and obtain owner approval for any substitute in `specs/001-scanned-form-workflow/reports/2026-11-12-device-equivalence.md` (SC-004; CHK026; owner decision OD-3)
- [ ] T142 Execute the frozen scored recognition evaluation on the authoritative Android runtime and record TP/FP/FN, type accuracy, position accuracy, and the manual baseline in `specs/001-scanned-form-workflow/reports/2026-11-12-recognition.md` (SC-001/SC-002/SC-003; constitution Principle IV)
- [ ] T143 Execute the full-corpus export verification set and record zero clipped, misplaced, wrong-checkbox, and missing-signature defects in `specs/001-scanned-form-workflow/reports/2026-11-12-export-verification.md` (SC-005/SC-006; CHK018)
- [ ] T144 **Record** the gate-5 cross-artifact consistency analysis that was already executed through the registered `speckit.analyze` command on 2026-11-12 **before implementation**, archive its report as `specs/001-scanned-form-workflow/reports/2026-11-12-analysis.md`, list which CRITICAL/HIGH findings were resolved and which remain owner decisions, and name the separate post-implementation convergence check (gate 9) instead of re-running gate 5 (constitution Development Workflow gate 5; CHK032)
- [ ] T145 Run the complete local gate in `tools/gate.sh` and record zero analyzer failures and separated `SIMULATED` evidence in `specs/001-scanned-form-workflow/reports/2026-11-12-local-gate.md` (constitution Principle VIII; plan §Testing; enables FR-088/FR-089)
- [ ] T146 Execute the `quickstart.md` Web, emulator, artifact, failure-injection, and performance scenarios and record the outcomes in `specs/001-scanned-form-workflow/reports/2026-11-12-quickstart-validation.md` (constitution Definition of Done; supports SC-004–SC-010)
- [ ] T147 Assemble the final acceptance report with separated `SIMULATED`, `EMULATOR`, and `DEVICE` evidence in `specs/001-scanned-form-workflow/reports/2026-11-12-acceptance.md`, then hand the exact candidate revision to the independent review gate (gate 7), the integration/verification gate (gate 8), and the convergence gate (gate 9) and record their outcomes in the same report. This task does not self-approve; it creates no commit, merge, or publication (constitution Principles VIII and X; Definition of Done; supports SC-001–SC-022)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies; starts immediately.
- **Foundational (Phase 2)**: Depends on Setup; blocks every user story. Internal order is T014 → T015/T016 → T017/T018/T020/T021/T022 → T013 → T023… (see the Phase 2 execution-order block).
- **US1 Import (Phase 3)**: Depends on Foundational. It is the first MVP slice.
- **US2 Recognition (Phase 4)**: Depends on Foundational and US1 (imported pages are the input).
- **US3 Review (Phase 5)**: Depends on US2 for suggestions, but its add/move/resize path can be exercised on manually added fields.
- **US4 Fill (Phase 6)**: Depends on US3 for confirmed fields; can begin with manually added fields.
- **US5 Save/Recover (Phase 7)**: Depends on US1–US4 for meaningful content, but its storage core is independent.
- **US7 Export (Phase 8)**: Depends on US3 (confirmed fields), US4 (values/signatures), and US5 (durable revision).
- **US6 Templates (Phase 9)**: Depends on US3 (confirmed layout) and US7 (a document can be completed before templating).
- **US8 Recognition Quality (Phase 10)**: Depends on US2; can run alongside US3.
- **US9 Browser Surface (Phase 11)**: Depends on Setup and the story it exercises; it is continuous, not a final gate.
- **Polish (Phase 12)**: Depends on all desired user stories; T142, T143, and T145–T147 are final evidence gates, while T144 records the gate-5 analysis already completed before implementation.

### User Story Dependencies

- **US1 (P1)**: No user-story dependency; MVP start.
- **US2 (P1)**: Depends on US1.
- **US3 (P1)**: Depends on US2 for machine suggestions; independent for user-created fields.
- **US4 (P1)**: Depends on US3 for field structure.
- **US5 (P1)**: Depends on US1 for a document aggregate; its failure paths are independently testable.
- **US7 (P1)**: Depends on US3, US4, and US5.
- **US6 (P2)**: Depends on US3 and US7.
- **US8 (P2)**: Depends on US2.
- **US9 (P2)**: Depends on Setup; exercise it continuously.

### Within Each Story

1. Contract/model tests first where a contract exists.
2. Models and pure logic before platform adapters.
3. Adapters before integration tests.
4. Story-level integration test before the checkpoint.
5. Do not start the next priority story until the current checkpoint passes, unless the tasks are explicitly marked `[P]`.

### Parallel Opportunities

- Setup tasks `T004`, `T005`, `T006`, `T008`, `T010`, and `T011` are file-disjoint and parallel.
- Foundational tasks `T014`, `T032`, and `T035` can start after Setup. `T015`/`T016` are file-disjoint; after them, `T018` and `T022` are file-disjoint, `T019` follows `T018`, `T017` follows `T018`, `T020` follows `T017`, and `T021` follows `T017`/`T018`/`T020`. `T013` waits for `T014` and `T015`–`T022`; `T027`/`T028` wait for `T013`/`T023` and also need `T014`/`T026`; `T030`/`T031` wait for `T007`/`T029` and `T026` respectively.
- Within each story, `[P]` tests and file-disjoint components can run concurrently.
- After Foundational, US1 and the pure-Dart parts of US5 can start in parallel; US2 waits for US1's page input.
- Polish measurement tasks `T135`, `T137`, `T139`–`T141` can be prepared in parallel, but `T142`–`T147` depend on the implemented stories.

### Parallel Example: US1

```text
Task: "Write the import-port and preflight contract tests in packages/feldexa_ports/test/import_port_test.dart"
Task: "Add the SIMULATED browser import journey in apps/feldexa_app/integration_test/web_import_test.dart"
```

### Parallel Example: US3

```text
Task: "Write the suggestion-lifecycle contract test in packages/feldexa_core/test/field_lifecycle_test.dart"
Task: "Add the SIMULATED browser review interaction suite in apps/feldexa_app/integration_test/web_review_test.dart"
```

### Parallel Example: US7

```text
Task: "Write the export-plan schema contract test in packages/feldexa_export/test/export_plan_test.dart"
Task: "Add the SIMULATED export watermark test in apps/feldexa_app/integration_test/web_export_test.dart"
```

---

## Implementation Strategy

### MVP First

1. Complete Phase 1 (Setup) and Phase 2 (Foundational).
2. Complete US1 (Import), US2 (Recognition), US3 (Review), US4 (Fill), US5 (Save), and US7 (Export) in that order.
3. **STOP and VALIDATE**: run the US1–US5 and US7 independent tests on the Android emulator; do not call the MVP done until the complete journey works there.
4. Only then add US6 (Templates), US8 (Recognition Quality), and US9 (Browser surface polish) as P2 increments.

### Incremental Delivery

- Setup + Foundational → foundation ready.
- US1 → a trustworthy import.
- US2 → automatic suggestions with honest uncertainty.
- US3 → a corrected field structure.
- US4 → filled values.
- US5 → durable recovery.
- US7 → a verified flattened PDF (first releasable journey).
- US6 → reusable templates.
- US8 + US9 → quality and fast-feedback surfaces.
- Polish → frozen evaluation, accessibility, performance, and separated acceptance evidence.

### Evidence Discipline

- Never merge `SIMULATED`, `EMULATOR`, and `DEVICE` results.
- Browser success is never Android acceptance.
- A passing unit test is not product completion.
- Failed targets are reported as failures, not re-scored or re-labeled.
- Every task-produced evidence report goes to the single evidence root `specs/001-scanned-form-workflow/reports/`; `tools/evaluation/` holds only code, schemas, and protocols.
- Do not commit or publish as part of these tasks; integration and review are separate gates.

## Notes

- `[P]` marks file-disjoint or independent work only.
- The checklist markers in `checklists/precision-testability.md` remain untouched; `speckit-implement` must not modify them.
- The five settled clarifications and constitution v1.0.0 are fixed inputs.
- Owner decisions OD-1 through OD-4 are not silently answered by this task list.
- Gate 5 ran through the registered `speckit.analyze` command on 2026-11-12 **before implementation**; T144 records it and does not postpone or replace it.
- The GitHub issue mapping is recorded as `T001`→#1 … `T147`→#147 by task ID in the external issue tracker; this mapping and every live issue state are not verifiable from the git bundle and are unavailable from it. Expanded descriptions may make some issue titles stale; no issue is created, edited, or closed here, and no duplicate issue is produced.

## Corrective Regeneration Receipt

- **Command path**: registered command `speckit.tasks`, source `.opencode/commands/speckit.tasks.md`; setup via `.specify/scripts/bash/setup-tasks.sh --json`.
- **Installed manifest hash**: `6754ae39649c8e73a5ed376ad5cfcf04422e321a10e07c5ccd92fd1b9bccf776` (`.specify/integrations/opencode.manifest.json`), matching the on-disk command file.
- **Date**: 2026-11-12 (corrective regeneration of `specs/001-scanned-form-workflow/tasks.md`).
- **Base revision**: the prior authoring snapshot is not part of this candidate and is not required for verification (unavailable from the bundle); the current candidate is diffed against base `b3dbe29932c8a5bed13696406b6a2bcc80316ffa` with `git diff b3dbe29..HEAD`.
- **Preserved IDs**: all 147 identifiers `T001`–`T147` are preserved in the same order and the same phase; none added, removed, merged, renumbered, or reordered. Phase structure, dependency/parallel rules, and evidence rules are unchanged.
- **Analysis findings addressed**: C1 (gate order, T144 rewritten as a record task), C2 (T147 hands the exact revision to gates 7–9 without self-approval), G1 (T137 executes SC-016/SC-018 after OD-2), G2 (T048 deletion-reopen/render/export), G3 (T117 implements the FR-059 use-template flow), A1 (T113 cites the provisional §3.4 and FR-062, OD-1 unresolved), A2 (T097 stays blocked on OD-4, no invented bound), I2 (T095 shows status), I3/I4 (T045/T084 verify the corrected `IMP-007`/`FLD-001`; T029 consumes the corrected catalog), U4 (`tools/gate.sh`), U5 (single evidence root), I7/M1/M2 (traceability matrix and weak task traces corrected; T108 → FR-072), M3 (T093 asserts no app password / no mandatory biometric), U8 (T109 asserts provenance across save/reopen/export with no interactive controls in the flattened artifact), U7 (T029 consumes the corrected catalog; T045/T084 verify it).
- **Remaining unresolved findings / owner decisions**: OD-1 export conflict gating; OD-2 usability protocol and recruitment (blocks the T137 runs); OD-3 device equivalence; OD-4 50-item interaction bound. The pre-filled-scanned-content overlay edge case has no FR and is recorded as an unresolved documentation gap. `spec.md` status remains **Draft**.

## Format Validation

Every task line uses `- [x]` or `- [ ]` plus `T### [P?] [US#?] Description with exact file path`. Setup, Foundational, and Polish tasks omit the story label; every user-story phase task carries its `[US#]` label. No sample placeholder tasks remain.

## Completion Summary

- **Total tasks**: 147.
- **Per phase/story**: Setup 12; Foundational 24; US1 13; US2 14; US3 12; US4 12; US5 14; US7 12; US6 8; US8 6; US9 5; Polish 15.
- **Parallel opportunities**: 24 tasks carry `[P]`; the remaining dependencies are stated in the phase and dependency sections.
- **MVP scope**: US1 + US2 + US3 + US4 + US5 + US7 (the complete P1 journey on Android). US6, US8, and US9 follow as P2 increments.
- **Independent test criteria**: stated at the head of every user-story phase and implemented by that phase's integration test task.
- **Format validation**: all 147 task lines match `- [x]`/`- [ ]` plus `T### [P?] [US#?] Description with an exact file path`; IDs are sequential `T001`–`T147`; Setup, Foundational, and Polish tasks have no story label; every user-story task has its `[US#]` label; no template sample tasks remain.

## T013 Blocker Correction Receipt

- **Command path**: registered `speckit.analyze` (read-only baseline), registered `speckit.plan` (four design artifacts), and this registered `speckit.tasks` update; OpenCode, 2026-11-13. Exact command list and hashes: `reports/2026-11-13-t013-blocker-correction.md`.
- **Base/candidate verification**: base `b3dbe29932c8a5bed13696406b6a2bcc80316ffa`; candidate is the commit containing this file. Verify with `git diff --stat b3dbe29..HEAD`, `git diff --name-status b3dbe29..HEAD`, and `git show --stat HEAD`; no backup directory is required or included.
- **Preserved IDs**: all 147 identifiers `T001`–`T147` remain unique and in the same order; phase counts are unchanged (12/24/13/14/12/12/14/12/8/6/5/15); no task added, removed, merged, or renumbered.
- **Issue mapping**: `T001`→#1 … `T147`→#147 by task ID as recorded in this task list. Live GitHub issue states are external to this candidate and **unavailable from the bundle**; no issue was created, edited, or closed here.
- **Corrections**: CR-7 canonical-type ordering, CR-8 descriptor/error ownership, CR-9 DTO ownership and contract completion, CR-10 export-package boundary.
- **Post-analysis follow-up**: N1 assigns the existing `feldexa_testkit` `EvidenceClass` reconciliation to T014; N2 moves `TemplateOrigin` to T017 to break the `T017`↔`T021` cycle; R1 moves `DurablePointer` to T017 to break the `T017`↔`T020` cycle; N4/N5 complete the canonical-type lists, `StorageException` wording, `ExportBlockedException` payload, `FakeRegistry` ownership, and T017's file list.
- **Unchanged**: `spec.md`, the five clarifications, OD-1–OD-4, the constitution, and all source code.
