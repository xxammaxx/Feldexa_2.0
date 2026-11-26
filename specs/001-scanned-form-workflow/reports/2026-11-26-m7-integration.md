# M7 integration — owner decisions, T264A golden, lazy 50-item list

**Date**: 2026-11-26 (Europe/Berlin)
**Branch**: `xxammaxx/pi-m7-integration` · **PR**: #351 · **Base**: `cc3725442687c73e4482644d35e579acb9020177`
**Candidates**: `3c7f15f` (first review round), `a297ffa` (review corrections), final candidate after the review-A/B follow-up (documentation-only relative to `a297ffa`, plus comment wording)
**Device**: emulator only — `emulator-5554` (AVD `T025_Pixel7_API35_KVM_20261115`, API 35). No physical device was addressed.

## Scope

Integration of the verified local remediation state from the review chain M1–M7 (Owner Decisions Q1–Q11):

- **Spec/contracts/ledger**: `contracts/export-plan.md` §3.4 ratified (Q1=A); FR-111 + SC-023 for values over pre-filled printed content; SC-004 equivalence rule and the accepted 0.61 mm nominal font-ascent tolerance (Q3=B, #346); Q4/Q9 deferral, Q5/Q8 tracker authority, Q6/Q10 outcomes recorded; 14 previously unindexed reports added to the evidence index.
- **Recognition** (Q6=B, #350): `TypeInference.infer` takes the page's other candidate rectangles and rejects a same-row label when a nearer same-row candidate exists; the three call sites pass the candidate set. The frozen golden is byte-untouched.
- **App/test** (Q10=A, #318): `StoredItemsView` renders lazily (`CustomScrollView` + `SliverMainAxisGroup` + `SliverList.builder`); T097 host widget test for 50 entries / ≤500 ms / reachable; a host-only test asset fallback makes the app suite pass from the repository root.
- **Guards**: report-index completeness and tasks-ledger integrity (19 tests).

## Verification on the final candidate

| Check | Result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed .` | `PASS` — 339 files, 0 changed |
| `flutter analyze --no-pub` | `PASS` — 0 issues |
| `flutter test --no-pub` in `apps/feldexa_app` | `PASS` — 637/637 |
| `flutter test --no-pub apps/feldexa_app/test` from the repository root | `PASS` — 637/637 (was 558 pass / 11 fail before #318) |
| `python3 -m unittest discover -s tools/evaluation` | `PASS` — 60/60; golden `508ed9beed5a3844…` untouched (`git diff` empty) |
| `packages/*` Flutter tests | `PASS` — 1869 passed, 6 skipped |
| `python3 -m unittest discover -s tools/repo` | `PASS` — 19/19 |
| Maestro CLI flow `apps/feldexa_app/e2e/export_journey.yaml` | `PASS` — 90-94 s, 46 completed steps, no failed or skipped step |

Maestro receipt (`android_e2e_gate.py run` + `verify` on the final integration candidate; the receipt file in the run artifact names the exact commit and tree): `result=PASS`, `exit_code=0`, log sha256 `89506cad99c61b5da7f555b2a44c0a009d8130f518103d3eeadce71864241316`, `device_still_same=true`. The receipt's own note applies: it is CLI process evidence, and the installed APK identity is `UNVERIFIED`. The APK was built from `3c7f15f`; every later commit changes only documentation, comments and test-support code, so the installed product bytes are unchanged. The `a297ffa..final` delta is limited to that class and was re-gated on the final commit.

## Review dispositions

Two independent reviews were run on `3c7f15f`:

- **Review A (correctness/requirements, DeepSeek Flash)**: FAIL. Findings: ratification text contradicted by FR-062 / `export-plan.md` pipeline note / error catalog / T113 / OD-1 row; FR-111 carried an unimplemented editor MUST with no traceability; the 0.61 mm tolerance contradicted the no-clipping row; OD-4 recorded open and delivered.
- **Review B (tests/security/scope, GLM-5.3-Flash)**: BLOCK. Findings: the asset fallback ran on the web test platform (`Directory.current` throws there), served undeclared assets and accepted `..` keys; the ledger cross-reference had duplicate contradictory rows; T097 was checked without a report; guard tolerated unchecked evidence.

`a297ffa` addresses every P1: the ratification text is consistent (FR-062, pipeline note, catalog, T113, OD-1 row, A1 note), FR-111 keeps the export MUST and demotes the unimplemented editor hint to SHOULD with traceability and pending verification, the no-clipping row names the accepted tolerance, the OD-4 row records the answer, the cross-reference has one row per issue, and the fallback is host-only and limited to the keys parsed from `pubspec.yaml`.

## Not claimed, deferred, and residual

- **Recognition quality** (SC-001/002/005), **SC-016/SC-018 usability**, and **DEVICE/SC-004 acceptance** are deferred to the manual release phase (Q9=B). No DEVICE or recognition-quality claim is made.
- **SC-023** (overlay verification) is normative but its artifact-level verification is still pending; the editor overlap hint is planned, not implemented.
- **Browser test layer**: `NOT_RUN` on this host (no supported Chrome/Chromium; a Playwright Chromium attempt timed out). The `kIsWeb` guard is code-reviewed, not executed here.
- The 0.5 pt descender allowance in the no-clipping row is pre-existing contract text, not introduced by this integration.
- **Production wiring of label ownership** (`raster_page_stage.dart`) is covered only by unit tests plus the T264A golden gate; no application-level shared-label test exists yet.
