# T029 Correction: PRIV-001 Global Reset Disclosure

- **Task**: T029 post-review follow-up after candidate `0ac8d3f`
- **Date**: 2026-11-15, Europe/Berlin
- **Class**: `NONE` (contract consistency, host-VM tests, and analysis)
- **Result**: `PASS` for the disclosure correction and host checks; no runtime
  claim
- **Base revision**: `0ac8d3ff465236e84e1d8d6b65d3942e79dea6ff`
- **Correction commit**: recorded in the external `worker_done` attestation
- **Pre-existing tree state**: `apps/feldexa_app/android/gradlew.bat` was
  modified before this task and remains untouched/uncommitted

## 1. Review finding

`PRIV-001` (the pre-loss key/backup disclosure) said only that other documents
and templates remain usable after one document/template key is lost. It did not
name the global exception: a device or Keystore reset can invalidate every
alias, making all stored documents/templates unreadable or removing them.
FR-051 requires the German disclosure before the loss case, so the pre-loss
text must state that global possibility truthfully.

This is a disclosure gap, not a new key architecture: the per-document/template
KEK decision and the single-aggregate isolation promise remain unchanged.

## 2. Correction applied

One sentence was added to `PRIV-001`:

> Ein Zurücksetzen des Geräts oder seiner Schlüssel kann dagegen alle
> gespeicherten Dokumente und Vorlagen unlesbar machen oder entfernen; eine
> Wiederherstellung ist dann nicht möglich.

The disclosure now covers both cases:

- a single document/template key loss: affected data is unrecoverable, other
  items remain usable (`SAVE-002`);
- a device/key reset: all stored items may be unreadable or removed, with no
  recovery (`SAVE-008`).

The correction does not change the per-aggregate key architecture, the
`SAVE-002`/`SAVE-008` split, any owner decision, or any German text outside
`PRIV-001`.

## 3. Artifacts updated

- `contracts/error-catalog.de.md` `PRIV-001` text and note.
- `apps/feldexa_app/lib/l10n/app_de.arb` `priv001` value and description, plus
  regenerated `app_localizations*.dart`.
- `apps/feldexa_app/test/german_strings_test.dart` explicit assertion that the
  disclosure names both aggregate isolation and the global reset exception.
- `tasks.md` CR-13 records the resolution.
- this report and `reports/README.md`.

## 4. Verification

Toolchain: Flutter 3.47.7 (stable), Dart 3.13.5, workspace `pubspec.yaml` and
committed `pubspec.lock`. Logs were console-only and are not retained.

| Command / check | Working directory | Exit | Observed |
| --- | --- | --- | --- |
| `flutter pub get --offline` | repository root | 0 | workspace resolved |
| `flutter test test/german_strings_test.dart` | `apps/feldexa_app` | 0 | 10 tests passed, including the PRIV-001 global-reset assertion and exact catalog→ARB mapping |
| `flutter test` | `apps/feldexa_app` | 0 | 80 tests passed |
| `flutter test` | `packages/feldexa_ports` | 0 | 108 tests passed |
| `flutter test` | `packages/feldexa_testkit` | 0 | 110 tests passed |
| `flutter analyze --no-pub` | repository root | 0 | No issues found |
| Dart formatting check | app German-string test | 0 | 0 files changed |
| `flutter gen-l10n` | `apps/feldexa_app` | 0 | generated text matches the ARB; no drift |

## 5. Remaining limits

- T091 still owns the first-run/first-save UI implementation of this
  disclosure; this correction is the service/catalog text only.
- No Android `EMULATOR` or `DEVICE` run; the disclosure cannot be observed in a
  running UI from this candidate.
- A device/key reset remains unrecoverable; the text now discloses it instead
  of promising blanket continued usability.
- The T023 browser registry check remains `UNAVAILABLE` (no Chrome), unrelated
  to this correction.
- No push, remote merge, or self-review is claimed.

## 6. Review

Reviewer: _(blank; independent review required)_

Date:

Verdict:
