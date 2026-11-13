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
- [ ] T012 Create the shared `SIMULATED` banner and evidence-label widget in `packages/feldexa_ui/lib/src/simulated_banner.dart` (FR-087; constitution Principle II)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core contracts, models, platform ports, storage, and evidence infrastructure that every user story depends on.

**⚠️ CRITICAL**: No user-story implementation starts until this phase is complete.

- [ ] T013 Define every capability interface in `packages/feldexa_ports/lib/` per `contracts/ports.md` (constitution Architecture and Platform Constraints)
- [ ] T014 Define the error taxonomy and evidence classes in `packages/feldexa_ports/lib/src/errors.dart` and `packages/feldexa_ports/lib/src/evidence.dart` (constitution Principle VIII)
- [ ] T015 [P] Implement `Rect`, `Size`, and `Point` value objects in `packages/feldexa_core/lib/src/geometry/rect.dart` with finite, positive-size invariants (`data-model.md` §2.2; enables FR-024 and SC-017)
- [ ] T016 Implement `PageGeometry` display-box, rotation, and CropBox mapping in `packages/feldexa_core/lib/src/geometry/page_geometry.dart` with tests in `packages/feldexa_core/test/geometry_test.dart` (`contracts/coordinates-and-geometry.md` §1–§2; enables FR-003 and SC-017)
- [ ] T017 Define the versioned document aggregate and canonical JSON encoding in `packages/feldexa_core/lib/src/model/document.dart` and `packages/feldexa_core/lib/src/model/canonical_json.dart` (`data-model.md` §3.1, §4; enables FR-043 and FR-044)
- [ ] T018 Implement `FieldSuggestion`, `ConfirmedField`, `FieldValue`, and `FieldVerification` in `packages/feldexa_core/lib/src/model/field.dart` with the enum and length constraints from `data-model.md` §3.4–§3.8 (enables FR-021, FR-028, and FR-031)
- [ ] T019 Implement the reclassification compatibility rules in `packages/feldexa_core/lib/src/model/reclassification.dart` and tests in `packages/feldexa_core/test/reclassification_test.dart` (FR-029; `data-model.md` §3.5)
- [ ] T020 Implement `DurabilityStatus`, `Revision`, and `DurablePointer` in `packages/feldexa_core/lib/src/model/persistence.dart` (FR-044/FR-046; `data-model.md` §2.5, §3.12–§3.13)
- [ ] T021 Implement `Template`, `TemplateVersion`, and `TemplateOrigin` in `packages/feldexa_core/lib/src/model/template.dart` (FR-101–FR-106; `data-model.md` §3.9–§3.11)
- [ ] T022 Implement the `ExportArtifact` state machine in `packages/feldexa_core/lib/src/model/export_artifact.dart` with optimistic states forbidden (FR-072; `data-model.md` §3.15)
- [ ] T023 Implement the explicit adapter registry and release assertion in `apps/feldexa_app/lib/platform/registry.dart`, `registry_android.dart`, `registry_web.dart`, and `registry_unsupported.dart` (constitution Principle II; plan §Architecture Decisions 8)
- [ ] T024 Implement the `FeldexaPlugin` MethodChannel/EventChannel facade in `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/FeldexaPlugin.kt` per `contracts/platform-channel.md` (enables FR-001, FR-013, and FR-095 platform calls)
- [ ] T025 Implement Android Keystore master-key creation and DEK wrap/unwrap in `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage/KeystoreService.kt` (FR-049/FR-050; plan §Storage)
- [ ] T026 Implement the `FXC1` encrypted store with atomic commit, read-back verification, and stale-temp sweep in `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/storage/EncryptedStore.kt` (FR-047; `contracts/storage-format.md`)
- [ ] T027 Implement the Android Dart thin clients in `packages/feldexa_adapters_android/lib/` for import, OCR, storage, rendering, delivery, and clock ports (enables FR-001, FR-013, FR-043, FR-063, and FR-071)
- [ ] T028 Implement deterministic `SIMULATED` adapters in `packages/feldexa_adapters_simulated/lib/` for import, page rasterization, storage, OCR, export, and delivery (FR-087; plan §Architecture Decisions 9)
- [ ] T029 Build all German ARB keys from the **corrected** `contracts/error-catalog.de.md` in `apps/feldexa_app/lib/l10n/app_de.arb` and add `apps/feldexa_app/test/german_strings_test.dart` (FR-090; SC-014). The catalog already carries the corrected `IMP-007` (80 MiB / 83.886.080 Bytes) and `FLD-001` (export is stopped) strings; generate the ARB from that corrected text so T045/T084 only have to verify it.
- [ ] T030 Add the font-metrics contract test in `packages/feldexa_export/test/font_metrics_test.dart` comparing Dart advances and glyph coverage against the bundled metrics (FR-067/FR-068)
- [ ] T031 Implement startup recovery and temp/export-preview sweeping in `apps/feldexa_app/lib/bootstrap/startup_sweep.dart` (plan §Constraints)
- [ ] T032 [P] Create the evidence report schema and validator in `tools/evaluation/report_schema.json` and `tools/evaluation/validate_report.dart` (constitution Principle VIII)
- [ ] T033 Assemble the rights-cleared corpus of at least 20 real German authority forms and record provenance in `tools/corpus/manifest.json` (constitution Principle IV; SC-001)
- [ ] T034 Freeze `corpus-1.0.0` and `metric-definition.v1.md` and implement the scorer in `tools/evaluation/metric-definition.v1.md` and `tools/evaluation/score.dart` before any scoring run (constitution Principle IV; SC-001/SC-002)
- [ ] T035 [P] Record the manual-baseline protocol in `tools/evaluation/manual-baseline.md` using the add/move/resize/reclassify comparison from `research.md` D-18 (SC-003)
- [ ] T036 Implement the failure-injection harness for clock, quota, keystore, and write interruption in `packages/feldexa_testkit/lib/src/faults.dart` (constitution Principle VIII)

**Checkpoint**: Contracts, models, ports, encryption, German strings, corpus, frozen metrics, and fault injection are ready. User stories can start after this.

---

## Phase 3: User Story 1 — Import Scanned PDF Documents (Priority: P1) 🎯 MVP slice

**Goal**: A user imports a scanned PDF through Android SAF, sees every original page unchanged, and gets specific German rejection messages without a stored record.

**Independent Test**: Import a single-page and a five-page image-only PDF; verify page count, order, orientation, dimensions, and pixel fidelity, and a byte-identical source. Import password-protected, truncated, non-PDF, unknown-failure, and partially damaged files and verify the exact German behavior and no document entry.

- [ ] T037 [P] [US1] Write the import-port and preflight contract tests in `packages/feldexa_ports/test/import_port_test.dart` and `packages/feldexa_core/test/import_contract_test.dart` (FR-001/FR-002)
- [ ] T038 [US1] Implement the SAF `ACTION_OPEN_DOCUMENT` streaming import in `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/import/ImportService.kt` (FR-001; FR-095)
- [ ] T039 [US1] Implement PDF preflight with page geometry and encryption detection in `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/pdf/PdfPreflight.kt` (FR-003/FR-005/FR-006; `contracts/platform-channel.md`)
- [ ] T040 [US1] Implement the streaming encrypted source copy in `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/import/ImportService.kt` and `.../storage/EncryptedStore.kt` (FR-004; FR-095/FR-096)
- [ ] T041 [US1] Map every import failure to the German catalog and suppress document creation in `apps/feldexa_app/lib/features/start/import_error_mapper.dart` (FR-005, FR-006, FR-007, FR-008, FR-009; `contracts/error-catalog.de.md` §1)
- [ ] T042 [US1] Implement the pdfrx page viewer and source-point geometry mapping in `apps/feldexa_app/lib/features/editor/page_view.dart` (FR-003; `contracts/coordinates-and-geometry.md`)
- [ ] T043 [US1] Implement page-strip navigation that works before analysis finishes in `apps/feldexa_app/lib/features/editor/page_strip.dart` (US1 scenario 2; FR-018)
- [ ] T044 [US1] Handle partially unreadable pages and the `IMP-006` warning in `apps/feldexa_app/lib/features/editor/page_state.dart` (FR-010)
- [ ] T045 [US1] Enforce the 80 MiB (83,886,080-byte) import cap and **verify** the already-corrected `IMP-007` wording ("80 MiB (83.886.080 Bytes)") in `apps/feldexa_app/android/app/src/main/kotlin/de/feldexa/app/import/ImportService.kt` and `contracts/error-catalog.de.md` (FR-005; plan §Performance Goals; CHK028; CR-3). Assert that the ARB key generated from the T029 corrected catalog and the German rejection message match that text.
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
- [ ] T057 [US2] Implement per-page analysis state and failure isolation in `packages/feldexa_recognition/lib/src/page_analysis.dart` (FR-017, FR-018, FR-019, FR-020; `contracts/recognition-output.md` §4)
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
- [ ] T095 [US5] Implement the start area with separate document and template groups in `apps/feldexa_app/lib/features/start/stored_items.dart`, showing each entry's title, last-edited date, and status (FR-058/FR-097/FR-098; clarification 3)
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

- [ ] T102 [P] [US7] Write the export-plan schema contract test in `packages/feldexa_export/test/export_plan_test.dart` (`contracts/export-plan.md` §2)
- [ ] T103 [US7] Implement text layout, line breaking, baselines, and blocking clip detection in `packages/feldexa_export/lib/src/layout.dart` (FR-062/FR-064/FR-067/FR-068)
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
- **Foundational (Phase 2)**: Depends on Setup; blocks every user story.
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
- Foundational tasks `T015`, `T032`, and `T035` are parallel after their prerequisites. Model tasks `T017`–`T022` are file-disjoint once `T017` exists; `T027`/`T028` wait for `T013`/`T023`, and `T030`/`T031` wait for `T007`/`T029` and `T026` respectively.
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
- The GitHub issue mapping remains exactly `T001`→#1 … `T147`→#147 by task ID. Expanded descriptions may make some issue titles stale; no issue is created, edited, or closed here, and no duplicate issue is produced.

## Corrective Regeneration Receipt

- **Command path**: registered command `speckit.tasks`, source `.opencode/commands/speckit.tasks.md`; setup via `.specify/scripts/bash/setup-tasks.sh --json`.
- **Installed manifest hash**: `6754ae39649c8e73a5ed376ad5cfcf04422e321a10e07c5ccd92fd1b9bccf776` (`.specify/integrations/opencode.manifest.json`), matching the on-disk command file.
- **Date**: 2026-11-12 (corrective regeneration of `specs/001-scanned-form-workflow/tasks.md`).
- **Base revision**: `specs/001-scanned-form-workflow/reports/backups/2026-11-12T1520Z-pre-regeneration/tasks.md`.
- **Preserved IDs**: all 147 identifiers `T001`–`T147` are preserved in the same order and the same phase; none added, removed, merged, renumbered, or reordered. Phase structure, dependency/parallel rules, and evidence rules are unchanged.
- **Analysis findings addressed**: C1 (gate order, T144 rewritten as a record task), C2 (T147 hands the exact revision to gates 7–9 without self-approval), G1 (T137 executes SC-016/SC-018 after OD-2), G2 (T048 deletion-reopen/render/export), G3 (T117 implements the FR-059 use-template flow), A1 (T113 cites the provisional §3.4 and FR-062, OD-1 unresolved), A2 (T097 stays blocked on OD-4, no invented bound), I2 (T095 shows status), I3/I4 (T045/T084 verify the corrected `IMP-007`/`FLD-001`; T029 consumes the corrected catalog), U4 (`tools/gate.sh`), U5 (single evidence root), I7/M1/M2 (traceability matrix and weak task traces corrected; T108 → FR-072), M3 (T093 asserts no app password / no mandatory biometric), U8 (T109 asserts provenance across save/reopen/export with no interactive controls in the flattened artifact), U7 (T029 consumes the corrected catalog; T045/T084 verify it).
- **Remaining unresolved findings / owner decisions**: OD-1 export conflict gating; OD-2 usability protocol and recruitment (blocks the T137 runs); OD-3 device equivalence; OD-4 50-item interaction bound. The pre-filled-scanned-content overlay edge case has no FR and is recorded as an unresolved documentation gap. `spec.md` status remains **Draft**.

## Format Validation

Every task line uses `- [ ] T### [P?] [US#?] Description with exact file path`. Setup, Foundational, and Polish tasks omit the story label; every user-story phase task carries its `[US#]` label. No sample placeholder tasks remain.

## Completion Summary

- **Total tasks**: 147.
- **Per phase/story**: Setup 12; Foundational 24; US1 13; US2 14; US3 12; US4 12; US5 14; US7 12; US6 8; US8 6; US9 5; Polish 15.
- **Parallel opportunities**: 24 tasks carry `[P]`; the remaining dependencies are stated in the phase and dependency sections.
- **MVP scope**: US1 + US2 + US3 + US4 + US5 + US7 (the complete P1 journey on Android). US6, US8, and US9 follow as P2 increments.
- **Independent test criteria**: stated at the head of every user-story phase and implemented by that phase's integration test task.
- **Format validation**: all 147 task lines match `- [ ] T### [P?] [US#?] Description with an exact file path`; IDs are sequential `T001`–`T147`; Setup, Foundational, and Polish tasks have no story label; every user-story task has its `[US#]` label; no template sample tasks remain.
