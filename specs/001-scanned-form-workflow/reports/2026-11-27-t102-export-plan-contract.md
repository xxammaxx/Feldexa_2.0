# T102 — export-plan schema contract test (path reconciliation)

**Date**: 2026-11-27 · **Candidate**: `bb4271d` (main) · **Evidence class**: `NONE` (host tests only)

## Result

The `contracts/export-plan.md` §2–§4 model contract is covered by
`packages/feldexa_export/test/export_contract_models_test.dart` (the
`ExportPlan v1 schema` group, strict version/geometry/CTM/op validation, and the
`ExportValidation` cases). The row names `test/export_plan_test.dart`, which was
never created: the suite lives in `export_contract_models_test.dart`, a single
file for the T022 models.

- Focused run: `flutter test --no-pub test/export_contract_models_test.dart test/preflight_test.dart` → **38/38 PASS**.
- Package run: `flutter test --no-pub` in `packages/feldexa_export` → **121/121 PASS**.
- `dart format` 340/0; `tools/repo` guards 19/19.

## Disposition

T102 is closed with a **superseded path**: the requirement (a §2 schema contract
test against the T022 `ExportPlan`/`ExportValidation` models) is met by
`export_contract_models_test.dart`. No product code changed.
