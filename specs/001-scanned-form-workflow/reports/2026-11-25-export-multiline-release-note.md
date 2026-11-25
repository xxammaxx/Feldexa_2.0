# Export multiline release note — trailing `\n` no longer blocks, and the open limits

**Date**: 2026-11-25 (Europe/Berlin)
**Task / PR**: `T103` text layout, PR #336
**Branch**: `xxammaxx/release-export-dart` at `aa587b4`; the commit carrying this note is
recorded in the review record, not here.
**Scope**: Documentation only — one contract qualification in `contracts/export-plan.md`
§2.2 plus this note. No product code, no test, no run.

This note records the user-facing consequence of `e707c4d` and the limits that
the PR #336 review left open on purpose. It is documentation, not evidence of a
runtime run: everything below is pinned by host-VM tests (`NONE`), and no
Android export verification is claimed.

## 1. Release note

> Werte mit abschließendem Enter blockieren den Export nicht mehr
> (Verhaltensänderung, kein Schwellenwechsel).

A multiline value whose text ends in a closing `\n`, or in whitespace-only
paragraphs after the last visible line, used to materialize those blank
paragraphs as `lines` entries. The height check
`lines.length × lineHeightPt > available height` then blocked a field with
`EXP-001` (`too_many_lines`) although the visible text fitted the field. Since
`e707c4d` a trailing blank paragraph produces no line; an interior blank
paragraph still stays a line (`contracts/export-plan.md` §3.1).

This is a visible behavior change, not a threshold change: no padding, font
size, line height, tolerance, warning code, or German message changed, and a
field that genuinely overflows still blocks. Values that exported before
produce the same plan; only the trailing blank entries disappear.

Pinned by `packages/feldexa_export/test/layout_test.dart`: `'Hallo\n'` yields one
line and an op instead of `EXP-001`, `'Hallo   \n   '` yields
`lines == ['Hallo']` with `trimmedTrailingSpaceCount == 6`, and `'a\n\nb'` /
`'a\n\n\nb'` keep their interior blank paragraphs as lines.

## 2. Open limits (deliberately not closed in PR #336)

**(a) A leading blank paragraph still produces a line.** The trailing strip runs
only from the end of the value, so `'\nHallo'` lays out as `['', 'Hallo']` and
spends the first line slot. This is a deliberate boundary — only the trailing
side is normalized — but neither §3.1 (which names trailing and interior
paragraphs only) nor a test pins it today. A later change must not read the
current behavior as contractual, and no test asserts it.

**(b) The `trimmedTrailingSpaceCount` wording is narrower than the count.**
§3.1 says "trailing spaces at line ends are removed … and is recorded as
`trimmedTrailingSpaceCount` in info." The recorded number also includes the
whitespace of the trailing paragraphs that are dropped entirely: `'Hallo   \n   '`
reports `6` (three line-end spaces plus three paragraph spaces). The count is
correct for the characters actually removed; only the contract sentence does not
name the second part. Deliberately not reworded here, because §2.2 was the only
contract statement in scope.

**(c) The 180° export matrix is proven by corner literals only.** The 180° CTM is
pinned by mapping the four display-box corners onto the four PDF box corners
(`test/export_ctm_test.dart`) and by `ExportCtm.fromGeometry`, the same formula
`ExportPage` validates a plan against. `test/plan_builder_test.dart` covers
rotations 0 and 90 only, so no plan with `rotation: 180` is proven to pass
`ExportPlan.fromJson` into that validation. Consequence to keep in mind: a plan
serialized before `01835ba` (`ctm.d = −1`) is now rejected there — fail-closed and
harmless, because `ExportPlan` is transient and has no persistence path outside
the export round.

**(d) The golden render per rotation remains T108/T109.**
`contracts/coordinates-and-geometry.md` §5 requires each matrix to be verified by
the four corner mappings *and* a golden render per rotation. PR #336 delivers only
the corner half, and a golden render is the only check that makes the vertical
placement on 180° pages visible. Open acceptance point; no claim is made here that
the 180° overlay lands upright in a rendered PDF.

## 3. Not changed

- No product code and no test changed by this note.
- `contracts/export-plan.md` §3.1 unchanged; only the §2.2 `lines` row was
  qualified so that it defers to §3.1 instead of restating it.
- No warning code, message, threshold, or plan field added, removed, or renamed.
- No Android `EMULATOR` or `DEVICE` verification is claimed for the multiline
  change; that stays T109.
