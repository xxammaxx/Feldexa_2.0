# T113 — preflight unresolved-suggestion warning (ratified policy)

**Date**: 2026-11-27 · **Candidate**: `bb4271d` (main) · **Evidence class**: `NONE` (host tests only)

## What is implemented

- `packages/feldexa_export/lib/src/preflight.dart` builds the ratified
  OD-1/Q1=A policy: empty fields never block; unresolved overlapping suggestions
  are excluded from the plan and counted in `unresolvedSuggestionCount`; they do
  not block. FR-025 still governs the review UI.
- Wired into plan construction (`plan_builder.dart`) and the pre-export dialog
  (`apps/feldexa_app/lib/features/editor/editor_screen.dart`, ARB string
  `app_de.arb`).
- `preflight_test.dart` covers the unresolved group, including the counted but
  non-blocking case.

## Verification

- Focused: `flutter test --no-pub test/export_contract_models_test.dart test/preflight_test.dart` → **38/38 PASS**.
- Package: 121/121 PASS; `dart format` 340/0; `flutter analyze` 0 issues; guards 19/19.

## Disposition

T113 is closed: the row's "no task or test may treat the non-blocking behaviour
as settled" clause was the pre-decision wording; OD-1 is ratified (Q1=A,
2026-11-26), and `contracts/export-plan.md` §3.4, FR-062 and this report record
the settled policy. No product code changed in this step.
