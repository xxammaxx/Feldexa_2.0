# Task-to-Issue Reconciliation — 2026-11-12

**Repository**: `xxammaxx/Feldexa_2.0`
**Snapshot**: 2026-11-12T15:50:00Z, live `gh issue list --state all --limit 200 --json number,title,state`
**Tasks**: 147 (`T001`–`T147`, unique and sequential)
**Issues**: 147 (`#1`–`#147`, unique), **all OPEN**
**Mapping**: `T001`→#1 … `T147`→#147 by task ID (never by title)
**Duplicate issues created**: 0
**Issues closed/reopened/edited/commented**: 0

## Result

- Exact issue-title-to-current-description matches: **119**
- Stale issue titles due to corrected/expanded task descriptions: **28**
- Missing task IDs: **0**
- Missing issue numbers: **0**
- Duplicate task IDs or issue numbers: **0**
- Actions taken on GitHub: **none** (no create, edit, close, reopen, or comment)

The 28 stale titles are expected: the corrective regeneration preserved every task ID and expanded some descriptions without publishing new issue titles. The authoritative mapping remains the task ID, not the title. No issue was duplicated or closed prematurely.

## Stale Titles (Mapping Still Valid by ID)

| Task | Issue | State | Existing issue title |
| --- | --- | --- | --- |
| T002 | #2 | OPEN | T002: Initialize the Flutter application and Android host in `apps/feldexa_app/pubspec.yaml` and `apps/feldexa_app/andro… |
| T004 | #4 | OPEN | T004: Configure analysis, formatting, and the local gate in `.analysis_options.yaml` and `tool/gate.sh` per `plan.md` §T… |
| T007 | #7 | OPEN | T007: Implement the font-advance metrics generator in `tools/metrics/generate_font_metrics.dart` and emit `apps/feldexa_… |
| T015 | #15 | OPEN | T015: Implement `Rect`, `Size`, and `Point` value objects in `packages/feldexa_core/lib/src/geometry/rect.dart` with fin… |
| T016 | #16 | OPEN | T016: Implement `PageGeometry` display-box, rotation, and CropBox mapping in `packages/feldexa_core/lib/src/geometry/pag… |
| T017 | #17 | OPEN | T017: Define the versioned document aggregate and canonical JSON encoding in `packages/feldexa_core/lib/src/model/docume… |
| T018 | #18 | OPEN | T018: Implement `FieldSuggestion`, `ConfirmedField`, `FieldValue`, and `FieldVerification` in `packages/feldexa_core/lib… |
| T024 | #24 | OPEN | T024: Implement the `FeldexaPlugin` MethodChannel/EventChannel facade in `apps/feldexa_app/android/app/src/main/kotlin/d… |
| T027 | #27 | OPEN | T027: Implement the Android Dart thin clients in `packages/feldexa_adapters_android/lib/` for import, OCR, storage, rend… |
| T029 | #29 | OPEN | T029: Build all German ARB keys from `contracts/error-catalog.de.md` in `apps/feldexa_app/lib/l10n/app_de.arb` and add `… |
| T030 | #30 | OPEN | T030: Add the font-metrics contract test in `packages/feldexa_export/test/font_metrics_test.dart` comparing Dart advance… |
| T045 | #45 | OPEN | T045: Enforce the 80 MiB (83,886,080-byte) import cap and align `IMP-007` units in `apps/feldexa_app/android/app/src/mai… |
| T048 | #48 | OPEN | T048: Add the byte-identity and modification-time test in `apps/feldexa_app/integration_test/source_integrity_test.dart`… |
| T060 | #60 | OPEN | T060: Run the explicitly unscored frozen-metric dry run and record it in `tools/evaluation/reports/corpus-1.0.0-dry-run.… |
| T084 | #84 | OPEN | T084: Implement overflow warning and align `FLD-001` wording with blocking `EXP-001` in `apps/feldexa_app/lib/features/f… |
| T093 | #93 | OPEN | T093: Add the key-loss isolation test in `apps/feldexa_app/integration_test/key_loss_test.dart` (FR-052; `quickstart.md`… |
| T095 | #95 | OPEN | T095: Implement the start area with separate document and template groups in `apps/feldexa_app/lib/features/start/stored… |
| T097 | #97 | OPEN | T097: Define and test the 50-item list interaction bound in `apps/feldexa_app/integration_test/stored_list_50_test.dart`… |
| T109 | #109 | OPEN | T109: Add the Android two-page export and artifact-verification test in `apps/feldexa_app/integration_test/android_expor… |
| T113 | #113 | OPEN | T113: Implement the preflight unresolved-suggestion warning per current plan behavior in `apps/feldexa_app/lib/features/… |
| T117 | #117 | OPEN | T117: Implement immutable template versions and derived-document pinning in `packages/feldexa_application/lib/src/templa… |
| T137 | #137 | OPEN | T137: Record the SC-016 journey-timing and SC-018 first-time-usability protocol in `tools/evaluation/journey_protocol.md… |
| T140 | #140 | OPEN | T140: Record the plan-budget traceability table and label untraceable values as non-binding engineering budgets in `spec… |
| T142 | #142 | OPEN | T142: Execute the frozen scored recognition evaluation on the authoritative Android runtime and record TP/FP/FN, type ac… |
| T144 | #144 | OPEN | T144: Run the cross-artifact consistency analysis through the installed official `speckit-analyze` workflow and record i… |
| T145 | #145 | OPEN | T145: Run the complete local gate in `tool/gate.sh` and record zero analyzer failures and separated `SIMULATED` evidence… |
| T146 | #146 | OPEN | T146: Execute the `quickstart.md` Web, emulator, artifact, failure-injection, and performance scenarios and record the o… |
| T147 | #147 | OPEN | T147: Assemble the final acceptance report with separated `SIMULATED`, `EMULATOR`, and `DEVICE` evidence in `specs/001-s… |

Full per-task mapping, including the 119 exact matches, is in `2026-11-12-task-issue-mapping.json`.
