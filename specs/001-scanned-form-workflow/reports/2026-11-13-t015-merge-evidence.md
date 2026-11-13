# T015 Merge Evidence Report — Corrected Main into Reviewed Candidate

| Field | Value |
| --- | --- |
| Repository | `xxammaxx/Feldexa_2.0` |
| Task / issue | T015 / #15 |
| Evidence class | `NONE` (merge hygiene, static analysis, and host-VM tests only) |
| Result | `PASS` for the merge scope |
| Date / timezone | 2026-11-13 (Europe/Berlin) |
| Corrected main | `31c75e8346e195cf43218f91e37e78a0eda6f9f3` (merge of PR #163 / T013 correction) |
| Previous reviewed candidate | `6fc70869f8bbbd4c1fca0a1948de6a6bc1155411` |
| New candidate | recorded in the external attestation `refs/heads/t015-attestation-v2`; deliberately not asserted here |
| Branch | `xxammaxx/feldexa-t015-review-v1` |
| Toolchain | Flutter `3.47.7`, Dart `3.13.5` |
| Build identity | pure Dart package, no app APK or Web build produced |

## 1. Scope

This report records the merge of corrected `origin/main` into the reviewed T015
candidate. The correction changed the plan, data model, contracts, task
ownership, and evidence index; the candidate had changed `tasks.md` and the
report index. The merge therefore had to preserve both the corrected
Spec Kit artifacts and the T015 completion marker without rebasing, amending, or
rewriting the reviewed candidate.

The following were explicitly not done: no push, no pull-request merge, no issue
edit, no force push, no history rewrite, and no self-approval.

## 2. Merge shape

| Item | Value |
| --- | --- |
| First parent | `6fc70869f8bbbd4c1fca0a1948de6a6bc1155411` (reviewed T015 candidate) |
| Second parent | `31c75e8346e195cf43218f91e37e78a0eda6f9f3` (corrected integrated main) |
| Merge command | `git merge --no-ff --no-commit 31c75e8346e195cf43218f91e37e78a0eda6f9f3` |
| Merge commit | recorded in the external attestation; the final candidate adds only this report and its index row on top |
| Strategy | normal merge commit; the reviewed candidate remains an ancestor |
| Conflict files | exactly `specs/001-scanned-form-workflow/tasks.md` and `specs/001-scanned-form-workflow/reports/README.md` |

No other file conflicted. The corrected `plan.md`, `data-model.md`, and
`contracts/` are byte-identical to corrected main in the merge result.

## 3. Conflict resolution

| File | Conflict | Resolution |
| --- | --- | --- |
| `specs/001-scanned-form-workflow/tasks.md` | Candidate marked the old T015 line `[x]`; corrected main expanded T013–T018, added the Foundational Type Ownership table and normative execution order, and rewrote T015 to include the T015 ownership clause. | Took corrected main's complete file and re-applied the completion marker, producing `- [x] T015 ... ; T015 owns Rect, Size, and Point`. The corrected plan, type ownership, ordering, and all other task text are preserved. |
| `specs/001-scanned-form-workflow/reports/README.md` | Candidate appended the T015 evidence row after T012; corrected main changed the issue-mapping paragraph and appended the T013 blocker-correction row after T012. | Kept both rows. Corrected main's paragraph and T013 correction row are preserved; the T015 evidence row and this report's row follow them. |

The resolution is limited to these two files. No code file needed manual
conflict resolution.

## 4. Diff versus corrected main

At the merge commit, before this report and its index row were added:

```text
 packages/feldexa_core/lib/.gitkeep                 |   0
 packages/feldexa_core/lib/feldexa_core.dart        |   9 +
 packages/feldexa_core/lib/src/geometry/rect.dart   | 297 +++++++++++++++++
 packages/feldexa_core/pubspec.yaml                 |   4 +
 packages/feldexa_core/test/.gitkeep                |   0
 .../test/geometry_value_objects_test.dart          | 351 ++++++++++++++++++++
 .../reports/2026-11-13-t015-evidence.md            | 359 +++++++++++++++++++++
 specs/001-scanned-form-workflow/reports/README.md  |   1 +
 specs/001-scanned-form-workflow/tasks.md           |   2 +-
 9 files changed, 1022 insertions(+), 1 deletion(-)
```

| Path | Change versus main |
| --- | --- |
| `packages/feldexa_core/lib/.gitkeep` | deleted (directory now has real files) |
| `packages/feldexa_core/lib/feldexa_core.dart` | added |
| `packages/feldexa_core/lib/src/geometry/rect.dart` | added |
| `packages/feldexa_core/pubspec.yaml` | modified (test-only dev dependency) |
| `packages/feldexa_core/test/.gitkeep` | deleted (directory now has real files) |
| `packages/feldexa_core/test/geometry_value_objects_test.dart` | added |
| `specs/001-scanned-form-workflow/reports/2026-11-13-t015-evidence.md` | added |
| `specs/001-scanned-form-workflow/reports/README.md` | T015 rows plus this report's index row |
| `specs/001-scanned-form-workflow/tasks.md` | T015 line marked `[x]`; corrected text otherwise unchanged |

The final candidate adds this report and one README index row on top of the
merge commit. Its exact file list, byte sizes, and hashes, including the final
diff against main, are recorded in the external attestation and in
`worker_done`. A full `git diff 31c75e8..HEAD` patch is retained at
`.dart_tool/t015-vs-main-31c75e8.patch` for review.

## 5. Verification commands and results

All commands ran in the merge candidate clone. Exit code 0 is a pass.

| # | Command | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `git merge --no-ff --no-commit 31c75e8` | 0 after resolution | console only (not retained) | PASS, exactly two content conflicts |
| 2 | `python3 tools/evaluation/check_evidence_docs.py` | 0 | `.dart_tool/t015-merge-logs/evidence-check.log` | PASS, evidence documents consistent |
| 3 | `flutter pub get --offline` | 0 | `.dart_tool/t015-merge-logs/pub-get.log` | PASS |
| 4 | `flutter analyze --no-pub` | 0 | `.dart_tool/t015-merge-logs/analyze.log` | PASS, `No issues found!` |
| 5 | `flutter test --no-pub packages/feldexa_core` | 0 | `.dart_tool/t015-merge-logs/core-test.log` | PASS, `+24: All tests passed!` |
| 6 | `tools/gate.sh --offline --allow-absent --log-dir .dart_tool/gate-t015-merge` | 0 | `.dart_tool/t015-merge-logs/gate.log` | PASS with incomplete layers: 8 passed, 0 failed, 0 unavailable, 1 absent |
| 7 | `git diff --check 31c75e8..HEAD` | 0 | `.dart_tool/t015-merge-logs/diff-check.log` | PASS, no whitespace errors |
| 8 | `git diff --quiet 31c75e8..HEAD -- <plan/data-model/contracts>` | 0 | console only (not retained) | PASS, corrected artifacts unchanged |
| 9 | `flutter analyze --no-pub` and `flutter test --no-pub packages/feldexa_core` at the final candidate | 0 | recorded in the external attestation | PASS |

### Gate detail

```text
[ PASS] dependency resolution (pub.dev or cache) (evidence: none)
[ PASS] formatting (dart format, page width 80) (evidence: none)
[ PASS] static analysis (flutter analyze) (evidence: none)
[ PASS] shared package tests: feldexa_core (flutter test) (evidence: none (host VM))
[ PASS] shared package tests: feldexa_testkit (flutter test) (evidence: none (host VM))
[ PASS] shared package tests: feldexa_ui (flutter test) (evidence: none (host VM))
[ PASS] app unit/widget tests (flutter test) (evidence: none (host VM))
[ PASS] SIMULATED app browser/interaction tests (flutter test --platform chrome) (evidence: SIMULATED)
[ABSENT] SIMULATED browser integration test layer (no integration_test/web_*_test.dart)

Checks passed: 8; failed: 0; unavailable: 0; absent planned layers: 1
GATE PASSED WITH INCOMPLETE LAYERS (not a complete gate)
```

The absent layer belongs to the future browser integration suite (T128/T145), not
to this merge. The Chrome layer is the existing app suite and is `SIMULATED`; it
is not T015 acceptance evidence.

### Retained local logs

These are git-ignored, regenerable support artifacts; the candidate does not
contain them.

| Log | Bytes | SHA-256 |
| --- | ---: | --- |
| `.dart_tool/t015-merge-logs/evidence-check.log` | 299 | `9bd10031ac5043661d1a255e984b6e939a13c03142519a30cf99fe380bfa2d16` |
| `.dart_tool/t015-merge-logs/pub-get.log` | 221 | `bf43ac2d8521495d0a1eff3ece869a5550c2a9554d10b078ce5c40b5e84985cc` |
| `.dart_tool/t015-merge-logs/analyze.log` | 97 | `901de6436798e7e974c5bb973f3e92f753dd4b2b680c2c55ac9b52bd877820df` |
| `.dart_tool/t015-merge-logs/core-test.log` | 1753 | `3fa3020bfd92ec8e7a5d0ccb6f45735b5323d7f87f4186bac34fae0906814d29` |
| `.dart_tool/t015-merge-logs/gate.log` | 2665 | `acce25e1345467aaca00044d39eca92bd5f6431649860585660d09281acfa9db` |
| `.dart_tool/t015-merge-logs/diff-check.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |

## 6. Artifacts at the merge commit

This report's own row is omitted by construction; its byte size and SHA-256 are
recorded in the external attestation.

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Core package manifest | `packages/feldexa_core/pubspec.yaml` | 253 | `71e671d95f55ce346ed2a6d8388a59a70d4d1ce280ec32ac87abf0e8e43323c4` |
| Core barrel | `packages/feldexa_core/lib/feldexa_core.dart` | 310 | `4417cf06d300fb8ac062a83a63015e62e408e0a0b15345c37a9db754ee881b5f` |
| Geometry value objects | `packages/feldexa_core/lib/src/geometry/rect.dart` | 9626 | `9bc4a3632148c596ae2507365c6932d6ecb76bde329b41d3516c073c03545afd` |
| Geometry tests | `packages/feldexa_core/test/geometry_value_objects_test.dart` | 11092 | `854e83fd98391ccf9b9a61ec6b459548737deac97ec62c920cd5f6acd0bbce97` |
| Corrected tasks with T015 complete | `specs/001-scanned-form-workflow/tasks.md` | 65090 | `6b9a8461c19b2e544017e03710107e2a991e60939b47bc6b90e6d33aea7b22a0` |
| Evidence index with both rows | `specs/001-scanned-form-workflow/reports/README.md` | 14353 | `b903942e5240d0c4647bccd3978df5d0b6ad9f5615415acc50d876c7833212e4` |
| Reviewed T015 evidence | `specs/001-scanned-form-workflow/reports/2026-11-13-t015-evidence.md` | 20586 | `ddd564962b12fd569d984f9c0fb403f69f74ed0703006f0a0d74870aada89ce6` |

The code artifacts are unchanged from the reviewed candidate `6fc7086`; the
merge only corrected the Spec Kit text and re-applied the T015 marker.

## 7. Reproducibility

1. Start from corrected main `31c75e8346e195cf43218f91e37e78a0eda6f9f3`.
2. Fetch the reviewed candidate commit `6fc70869f8bbbd4c1fca0a1948de6a6bc1155411`
   from the previous bundle or clone.
3. Run `git merge --no-ff --no-commit 31c75e8`.
4. Resolve only `tasks.md` (corrected main plus `[x]` on T015) and
   `reports/README.md` (keep the T013 and T015 rows).
5. Run `flutter pub get --offline`, `flutter analyze --no-pub`, and
   `flutter test --no-pub packages/feldexa_core`; expect clean analysis and
   `+24: All tests passed!`.
6. Run `tools/gate.sh --offline --allow-absent` with `CHROME_EXECUTABLE` set;
   expect 8 passed, 0 failed, 0 unavailable, 1 absent planned layer. This is a
   qualified pass, not acceptance.
7. Confirm `git diff --quiet 31c75e8..HEAD -- <plan/data-model/contracts>` and
   `apps/feldexa_app/android/gradlew.bat` remains unstaged.

## 8. Pre-existing checkout artifact

`apps/feldexa_app/android/gradlew.bat` remains the same pre-existing CRLF/LF
line-ending artifact recorded by the earlier T015 evidence:

| Item | Value |
| --- | --- |
| Diff | 90 insertions / 90 deletions |
| Diff SHA-256 | `f3fb68ce7b6a3a22df47c2d0dc017fe8b7f2389a4529f0737d37fa4cdb474108` |
| Working-file SHA-256 | `c13c6e91b9a517783976de213d46398c661ea9e17651376d7301e839eaedcc62` |

It was not staged, reverted, committed, or included in the bundle. No other
unrelated checkout artifact was changed.

## 9. New candidate and transport

- **New candidate**: the merge commit plus this report and its README index row,
  on branch `xxammaxx/feldexa-t015-review-v1`. The exact SHA is recorded in the
  external attestation and `worker_done`.
- **Attestation**: `refs/heads/t015-attestation-v2` in the same clone and
  bundle. It records the final candidate SHA and tree, both parents, the
  conflict resolution, the report's byte size and SHA-256, changed-file hashes,
  the diff-vs-main patch hash, and final verification exit codes. The previous
  `refs/heads/t015-attestation` and its bundle remain untouched.
- **Bundle**: `.dart_tool/t015-review-v2.bundle`, self-contained, including the
  candidate branch and the new attestation ref. Its SHA-256 is reported in
  `worker_done` because it is created after the attestation.
- **Diff versus main**: `.dart_tool/t015-vs-main-31c75e8.patch` with the full
  `git diff 31c75e8..HEAD`; its hash is recorded in the attestation.
- **Not done**: no push, no pull-request merge, no issue closure (issue #15
  remains OPEN), no history rewrite, and no self-approval. Both independent
  reviews must repeat on the new candidate.

## 10. Limits

- The merge changes Spec Kit text, the report index, and one completion marker;
  it does not add runtime behavior. The T015 code evidence remains the reviewed
  host-VM result from `6fc7086`.
- The Chrome gate layer is `SIMULATED` app-suite evidence. No `EMULATOR` or
  `DEVICE` run was performed, and no Android behavior is claimed.
- The evidence checker validates the T010/T015 historical rows and the README;
  it does not replace independent review.
- The reviewer-owned `precision-testability.md` checklist remains untouched.
- Independent review, integration, post-merge verification, and convergence
  remain external gates.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
