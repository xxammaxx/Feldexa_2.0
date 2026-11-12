# Contract: Editor and Filling Interactions

**Feature**: `001-scanned-form-workflow` | **UI package**: `packages/feldexa_ui` | **Surface**: Android touch and Chrome pointer/keyboard

The editor is a custom-painted page canvas with semantic overlays. This contract fixes the interaction behavior that must be identical on Web (`SIMULATED` evidence) and Android (`EMULATOR`/`DEVICE` evidence), so browser findings transfer (FR-089).

---

## 1. Layout regions

```text
┌─────────────────────────────────────────────┐
│ App bar: title · durability status · ⋮ menu │
├─────────────────────────────────────────────┤
│ Page strip (horizontal, page numbers,        │
│ analysis state, uncertainty badge)           │
├─────────────────────────────────────────────┤
│                                             │
│ Page viewport (pinch/scroll/zoom, overlays) │
│                                             │
├─────────────────────────────────────────────┤
│ Mode bar: Prüfen · Ausfüllen · Exportieren   │
└─────────────────────────────────────────────┘
```

- Small viewports (< 600 dp): the page strip collapses into a page indicator with previous/next buttons; the mode bar remains visible.
- The viewport never scrolls the page under the app bar; overlays are clipped to the viewport but geometry is not.
- The document overview is a separate route, reachable without losing edits (FR-039).

---

## 2. Selection

| Action | Behavior |
| --- | --- |
| Tap/click field | Select it; highlight with a 2 dp accent outline in view space (not part of geometry); show the type-appropriate control; announce semantics |
| Tap empty page area | Clear selection; dismiss keyboard |
| Tap another field | Move selection; keep the previous value committed |
| Tab / Shift+Tab (Web, hardware keyboard) | Move selection in field order; focus the control |
| Escape (Web) | Close the input control, keep the value if valid; second Escape clears selection |
| Long-press field | Context menu: „Feld bearbeiten“, „Feld löschen“, „Typ ändern“, „Feldreihenfolge“ |

Selected field overlays use an outline plus a corner handle indicator; color alone is never the only signal (FR-094).

---

## 3. Review mode (Prüfen)

- Suggestions are rendered with provenance styling:
  - machine suggestion: blue dashed outline (solid if confidence ≥ 0.75), `Vorschlag` badge;
  - confirmed machine field: green solid outline, `Bestätigt` badge;
  - user-created field: amber solid outline, `Selbst erstellt` badge;
  - conflicting suggestions: red conflict badge on both candidates;
  - uncertain suggestion: `unsicher` badge plus dashed outline.
- Per-field actions appear in a bottom sheet or side panel: „Übernehmen“, „Ablehnen“, „Löschen“, „Typ ändern“, „Größe/Position“, „In Reihenfolge verschieben“.
- Confirming a suggestion animates the badge change; rejecting removes it from the working set but leaves an undo affordance.
- Rejections and confirmations are undoable via the global undo action and `Ctrl/Cmd+Z` on Web.
- The review list (document order) shows page, index, label, type, provenance, confidence, conflict, and completion; the user can change the order by drag or move up/down actions (FR-026).
- A conflict cannot be resolved by a single swipe; each candidate requires an explicit choice (FR-025).

---

## 4. Geometry editing (move/resize)

| Gesture | Behavior |
| --- | --- |
| Drag body | Move the field; delta divided by current scale once; clamped to page bounds |
| Drag corner/edge handle | Resize from the opposite anchor; minimum 4 × 4 pt; aspect ratio free unless Shift (Web) is held for a square |
| Arrow keys (Web) | Move 1 pt; Shift+Arrow moves 10 pt |
| Alt+Arrow (Web) | Resize by 1 pt; Shift+Alt+Arrow by 10 pt |
| Two-finger pan/pinch | Pan/zoom the page, never edit geometry |
| Undo after drag | Restores the exact previous rect; no accumulated drift |

- Geometry changes are committed on gesture end (one command), not per frame; the autosave debounce starts at commit.
- Snapping (optional) suggests detected rulings within 2 pt and shows a guide; the user must confirm by releasing the pointer.
- Resizing never changes text content; overflow warnings update after commit.
- Handles are at least 24 dp in view space but never change the stored rect (hit slop only).

---

## 5. Filling mode (Ausfüllen)

| Field type | Control | Rules |
| --- | --- | --- |
| text | single-line text field | German IME; no autocorrect for numbers/IBAN; `\n` not accepted |
| number | numeric keyboard with comma and minus | German comma accepted, stored canonically; invalid rejected with `NUM-001` |
| date | text field + optional date picker | typing always possible; strict `Tag.Monat.Jahr`; picker disabled for years < 1900 or > current+50 |
| checkbox | tappable box with 48 dp hit slop | toggles on tap; export mark independent of hit area |
| multiline | multiline field, expandable sheet | `\n` preserved; no auto-shrink |
| signature | full-screen signature sheet | draw with finger/stylus/mouse; clear and undo; „Übernehmen“ stores ink only for this document |

- Selecting a field scrolls/zooms it into a readable view (FR-034) without changing geometry.
- The input control floats above the keyboard and never covers the selected field if the viewport can avoid it.
- Values commit on focus loss, „Fertig“, or Enter (single-line); invalid values remain in the control with a German error and are not stored.
- Next/previous field buttons and keyboard actions move focus in field order, preserving values (FR-033).
- Entered text that overflows shows the `FLD-001` warning immediately after commit; the value is kept (FR-037/FR-038).
- Checkbox state is stored per field; there is no group semantics.
- Signature is bound to the current document/field; no reuse library, no import from files.

---

## 6. Zoom, pan, and page navigation

- Pinch, scroll wheel with Ctrl/Cmd, and +/− buttons zoom within `0.5 × fitWidth … 8 × fitWidth`.
- Double-tap/double-click toggles between fit-width and 2× fit-width centered on the tap point.
- Page strip shows all pages with analysis state and unreadable/uncertain markers; tapping a page scrolls to it.
- Continuous vertical scrolling across pages is supported; the selected field stays selected when its page remains visible.
- Orientation change/resize recomputes fit scale but never modifies geometry.
- Browser URL reflects the document and page (`/documents/<id>?page=2`); reload restores the page and selection if the document is saved.

---

## 7. Durability and status

- The app bar always shows the durability label from the error catalog; no modal blocks editing for autosave.
- Save failure shows a persistent, dismissible banner with the German message and a „Erneut versuchen“ action; unsaved edits remain in memory.
- Leaving the editor with unsaved changes is allowed but warns: „Änderungen sind noch nicht dauerhaft gespeichert. Trotzdem zurück?“ with „Warten“ and „Verlassen“.
- The document overview shows per-field completion and the same durability status; it never shows a green check for unsaved work (FR-041/FR-046).

---

## 8. Undo, redo, and restore

- Global undo/redo actions in the app bar; Web keyboard shortcuts; Android accessibility actions.
- Commands merge within 500 ms for drag/resize/typing to avoid one undo per frame.
- Undo across page navigation works; undo after autosave marks the document dirty again.
- „Frühere Stände“ opens the revision history; a selected older revision is previewed read-only with a banner; restoring requires confirmation and creates a new revision (see data model §3.14).

---

## 9. Templates

- Template creation action „Als Vorlage speichern“ is enabled only after at least one field is confirmed; it shows what is excluded („Eingaben und Unterschriften werden nicht übernommen“).
- The template editor is layout-only: input controls are disabled, signature actions are absent, and a hint explains why.
- Saving shows the new version number and date; a previous version selector is read-only.
- Starting a document from a template opens a new document with empty values and the pinned layout.

---

## 10. Export flow

1. „PDF exportieren“ opens a preflight sheet: empty-field count, unresolved-suggestion count, blocking warnings (if any).
2. Blocking warnings list fields with page numbers and reasons; „Zu den Feldern“ jumps to the first one.
3. „Export starten“ shows progress phases with a cancel action.
4. Success opens a preview route with „Speichern“, „Teilen“, „Drucken“, and „Schließen“; the preview is the produced artifact.
5. Failure shows the German message, removes the partial artifact, and offers „Erneut versuchen“.
6. Closing the preview deletes the ephemeral artifact after the session.

No success message appears before artifact verification completes (FR-072).

---

## 11. Accessibility and responsiveness

- Every overlay exposes label, role, state, and actions; the painted canvas has an accessible sibling structure (semantics tree) in field order.
- Screen-reader focus follows visual reading order and field order; custom actions provide confirm/reject/edit.
- Text scale 200 % reflows sheets and dialogs; the canvas remains usable with pinch zoom.
- Minimum touch target 48 × 48 dp for primary controls; visual handles may be smaller but their hit area may not.
- Contrast: text 4.5:1, large text 3:1, control boundaries 3:1; status is never color-only.
- Keyboard: all actions reachable; visible focus ring; no keyboard trap in the canvas.
- Reduced motion: animations (zoom-to-field, badge changes) respect the platform accessibility setting.

---

## 12. Test matrix

| Area | Web (`SIMULATED`) | Android (`EMULATOR`/`DEVICE`) |
| --- | --- | --- |
| Selection and highlight | widget + integration | touch integration |
| Move/resize at 0.5×, 1×, 3×, 8× | geometry golden tests | touch drag test + geometry assertion |
| Rotation 0/90/180/270 and mixed sizes | widget tests | document fixture with rotations |
| Keyboard navigation and undo | Chrome integration | hardware keyboard optional; TalkBack actions |
| Filling all six types, German characters | Chrome integration | IME/touch integration |
| Overflow and invalid date/number | widget tests | integration with assertions |
| Signature | mouse/touch pointer | finger/stylus drawing |
| Autosave status and recovery | simulated store tests | force-stop/relaunch test |
| Template layout-only editor | widget test | integration |
| Export preflight/preview | simulated artifact | real artifact + verification |
| Accessibility semantics, 200 % scale, contrast | semantics tests + Chrome | TalkBack walkthrough |

Every row must pass in its stated class; Web results never satisfy the Android column (FR-088).
