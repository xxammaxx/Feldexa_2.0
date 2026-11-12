# Feature Specification: Scanned Form to Completed PDF Workflow

**Feature Branch**: `001-scanned-form-workflow` (git branch not created — no git extension hook installed)

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: "Automatically transform scanned, non-fillable German PDF forms into editable, reusable smart forms that users can fill and export on Android. Feldexa is a privacy-first application intended to eliminate the need to print scanned forms or manually position every input field. The first feature MUST deliver a complete user journey from importing a scanned PDF to producing a correctly completed, flattened PDF." (full `/speckit.specify` request of 2026-11-12; all nine user stories, quality targets, edge cases, and scope boundaries below are derived from it)

## Clarifications

### Session 2026-11-12

- Q: When a PDF is imported, should Feldexa keep its own protected copy of the original file, or keep a reference to the file the user picked? → A: Protected internal copy — import copies the original into encrypted app storage, so a saved document stays usable if the source file is moved, renamed, deleted, or becomes inaccessible.
- Q: How often should Feldexa persist a document automatically, so that "saved" has one precise meaning? → A: Debounced autosave roughly 2 seconds after the last committed change, plus a save whenever the app leaves the foreground, plus an explicit save action.
- Q: Should this first feature include a home area that lists the user's stored documents and templates, or only the currently open document? → A: Minimal "Meine Dokumente" list — documents and templates shown separately with title, last-edited date, and status, openable and deletable from there; no search, folders, or tags.
- Q: Once a template has been saved, should the user be able to change its pages or field layout later, or is a template fixed and must be recreated when it needs correction? → A: Editable with versions — a template can be edited directly, each edit creates a new template version, and documents already created from it never change.
- Q: When a user fills a date field, should Feldexa accept only a real calendar date, accept any text, or require choosing from a date picker? → A: Strict date validation — only real calendar dates in German day.month.year form are accepted; impossible dates are rejected with a German message, and non-date needs are handled by reclassifying the field as text.

## User Scenarios & Testing *(mandatory)*

The feature delivers one continuous user journey:

**Import → Analyze → Detect Fields → Review → Fill → Save → Export**

Each story below is a slice of that journey with its own priority. P1 stories together form
the minimum releasable product: a user can bring in a scanned authority form, end up with
correctly placed fields, enter their information, keep the work, and hand in a correct PDF.

### User Story 1 - Import Scanned PDF Documents (Priority: P1)

A person receives a German authority form as a scanned PDF, usually by e-mail or download.
They open Feldexa, choose the file through the normal Android document picker, and see the
original pages exactly as they were scanned. Nothing about the file is changed, and nothing
leaves the device.

**Why this priority**: Without a trustworthy import there is no product. Import is also where
the most damaging silent failures occur (misreported success, damaged source, invented
"password protection"), so it carries the highest trust burden.

**Independent Test**: Import a single-page and a five-page image-only scanned PDF through the
Android app; verify page count, page order, orientation, page dimensions, and pixel-level
fidelity against the source, and verify the source file is byte-identical afterwards. Import a
password-protected PDF and verify a specific German error and that no document or draft was
created.

**Acceptance Scenarios**:

1. **Given** an image-only scanned PDF with no selectable text and no interactive form fields,
   **When** the user imports it, **Then** every page is displayed in its original order with
   original geometry, orientation, and visual content preserved.
2. **Given** a multi-page scanned form, **When** the user imports it, **Then** all pages are
   present and the user can move between them before analysis completes.
3. **Given** a file that is confirmed to be password-protected or otherwise encrypted in an
   unsupported way, **When** the user selects it, **Then** the import is rejected with a
   specific German message that names password protection as the reason, no password is
   requested or stored, and no document or draft is created.
4. **Given** a file that cannot be opened, is missing, is truncated, or is not a supported PDF,
   **When** the user selects it, **Then** the import is rejected with a German message that
   states the actual reason and does not claim password protection.
5. **Given** a file whose failure reason cannot be determined, **When** the import fails,
   **Then** the message states that the file could not be read and does not assert a cause.
6. **Given** a document where one page is damaged or unreadable but others are intact,
   **When** the user imports it, **Then** the readable pages remain usable, the affected page is
   clearly marked as unreadable, and the user is told that export of the full document is
   affected.
7. **Given** a successfully imported document, **When** the user checks the source file
   afterwards, **Then** the source is unchanged in content and modification time.

---

### User Story 2 - Automatically Detect Form Fields (Priority: P1)

After import, Feldexa analyzes the pages and proposes where the user is expected to write:
lines after labels, boxes, table cells, empty areas next to printed text, and small squares
for crosses. The user sees these proposals on the original pages, marked as suggestions
rather than as their own decisions.

**Why this priority**: Field detection is the product's core promise. Manual placement is the
work the user is trying to avoid, and the quality target of this feature lives here.

**Independent Test**: Run detection on a reference form with known ground truth and verify that
suggestions appear at the expected page positions with plausible types, that suggestions are
visually and semantically distinct from confirmed fields, and that a deliberately unreadable
page does not prevent suggestions on the remaining pages.

**Acceptance Scenarios**:

1. **Given** a scanned form with printed labels, lines, boxes, and blank regions, **When**
   analysis completes for a page, **Then** suggested fields appear at positions consistent with
   those visual cues and use types from the supported set.
2. **Given** a detected region that is single-line, numeric, date-like, checkbox-like,
   multiline, or a signature area, **When** the suggestion is created, **Then** its proposed type
   matches the visual context with the uncertainty of that proposal recorded.
3. **Given** printed text on the page, **When** analysis runs, **Then** printed text is not
   proposed as a field unless it is an empty region that visually belongs to a label.
4. **Given** any completed analysis, **When** the user views the result, **Then** every
   suggestion is presented as unconfirmed and none is treated as user intent.
5. **Given** a multi-page document under analysis, **When** the user opens the document,
   **Then** pages remain navigable and pages already analyzed show their suggestions.
6. **Given** a page that cannot be analyzed, **When** analysis of that page fails, **Then**
   previously processed pages keep their suggestions and the failed page is reported as failed
   with its reason.
7. **Given** any page, **When** the user wants a field the system did not propose, **Then** the
   user can add it manually without restriction.

---

### User Story 3 - Review and Correct Field Suggestions (Priority: P1)

The user checks the proposals, accepts the good ones, deletes wrong ones, adds what is missing,
drags and resizes regions so they sit exactly on the printed lines, and fixes field types. When
they zoom or change pages, the regions stay attached to the printed areas.

**Why this priority**: Recognition will never be perfect on real authority forms. A correction
workflow that is fast and precise is what converts approximate detection into a usable form,
and it is the fallback that keeps the product usable when detection quality drops.

**Independent Test**: Take a form with intentionally wrong, duplicated, and missing
suggestions; confirm, reject, add, remove, move, resize, and reclassify fields at several zoom
levels and on several pages; verify that geometry remains aligned to the printed page and that
a correction can be undone and redone.

**Acceptance Scenarios**:

1. **Given** a suggested field, **When** the user confirms it, **Then** it becomes a confirmed
   field and is distinguishable from remaining suggestions.
2. **Given** an incorrect suggestion, **When** the user rejects it, **Then** it disappears from
   the working field set and from export input, and the rejection can be undone.
3. **Given** a page with a missing input area, **When** the user adds a field, **Then** the field
   is created at the chosen position with a chosen type and is treated as user-created.
4. **Given** overlapping or duplicate suggestions, **When** the user reviews them, **Then** the
   conflict is visible, both candidates remain individually selectable, and the system does not
   silently drop either.
5. **Given** a field, **When** the user moves or resizes it, **Then** the new geometry is
   preserved exactly and remains aligned with the printed area at every zoom level and after
   reopening the document.
6. **Given** a field with the wrong type, **When** the user changes the type, **Then** the type
   changes, incompatible entered content is flagged rather than silently discarded, and the
   change is reversible.
7. **Given** a field the user previously corrected, **When** the user revises or restores an
   earlier state, **Then** the earlier geometry, type, and value state is recovered.
8. **Given** a document with many fields, **When** the user reviews them, **Then** the user can
   work through them in page and document order and can change that order.

---

### User Story 4 - Fill Forms Efficiently (Priority: P1)

The user taps a field on the page, the field highlights, the view zooms so the printed line and
the entered text are both readable, and the appropriate input control appears. They move
forward and backward through the fields, add a handwritten signature where needed, and return
to the overview without losing anything.

**Why this priority**: Filling is the moment the product does its job. An interface that makes
the user hunt for fields or hides their own input makes the whole journey pointless.

**Independent Test**: Fill a two-page reference form entirely by touch on an Android device,
including multiline text, numbers, dates, checkboxes, a drawn signature, and text that
deliberately exceeds its region; verify no value is truncated, all values survive page
navigation, and every field remains editable.

**Acceptance Scenarios**:

1. **Given** a confirmed field, **When** the user taps its position on the page, **Then** the
   field is selected, visually highlighted, and the corresponding input control is presented.
2. **Given** a selected field, **When** the user activates it, **Then** the view brings the field
   region into a readable view without changing field geometry.
3. **Given** a text, number, date, checkbox, multiline, or signature field, **When** the user
   enters a value, **Then** the control matches the field type and accepts valid German input,
   including umlauts and ß.
4. **Given** a filled field, **When** the user moves to the next or previous field, **Then**
   focus moves in field order and previously entered values remain intact.
5. **Given** a signature field, **When** the user draws a signature, **Then** the mark belongs to
   the current document only and is not stored as a reusable signature.
6. **Given** entered text that is longer than its field can display, **When** the value is
   accepted, **Then** the user is warned that the text may not fit, and no characters are
   silently removed.
7. **Given** entered values on one page, **When** the user navigates to another page and back,
   **Then** all values are still present and editable.
8. **Given** a partially filled form, **When** the user returns to the document overview,
   **Then** completion state per field is visible and the user can continue filling.
9. **Given** a date field, **When** the user enters an impossible date such as 31.02.2025 or a
   malformed entry, **Then** the value is rejected with a German message naming the expected
   day.month.year form and no invalid date is stored.
10. **Given** a printed area that expects a month, a range, or a word instead of a full date,
    **When** the user reclassifies that field as text, **Then** the field accepts free text.

---

### User Story 5 - Save and Recover Work (Priority: P1)

The user starts a long form, leaves the app, comes back later, and continues where they stopped.
If the app is closed by the system or crashes, the work that was reported as saved is still
there, and any work that was not saved is identified as at risk.

**Why this priority**: Authority forms take time. Losing a filled form because of a phone call or
a low-memory kill destroys trust more thoroughly than a missing feature.

**Independent Test**: Fill a form partially, save, force-stop the app, reopen the document and
verify all confirmed geometry, types, and values; then edit without saving, force-stop, and
verify the last saved state returns and unsaved changes are flagged. Repeat with encryption key
material unavailable and verify unrelated documents remain intact.

**Acceptance Scenarios**:

1. **Given** a partially filled document, **When** the user saves, **Then** the document,
   confirmed field positions, field types, values, signatures, and verification states are
   stored and reported as saved only after the stored state is readable.
2. **Given** a document being edited, **When** about 2 seconds pass after the last committed
   change or the app leaves the foreground, **Then** progress is preserved durably without the
   user having to request it, and the app indicates the last durable point.
3. **Given** a saved document, **When** the app is restarted, **Then** the document reopens with
   geometry, types, values, and signatures unchanged.
4. **Given** unsaved edits, **When** any surface reports status, **Then** it distinguishes saved
   state from unsaved state and never claims that unsaved edits are permanently stored.
5. **Given** a save that fails, **When** the failure occurs, **Then** the user sees a German
   message naming the failure, the last successfully saved state is preserved, and the
   unsaved changes remain available where feasible.
6. **Given** a saved document, **When** the user opens it, **Then** the stored content is
   readable only through the device's protected key material, without an app password or
   mandatory biometric prompt.
7. **Given** saved data whose key material is unavailable or lost, **When** the user opens it,
   **Then** the app explains in German that the data cannot be decrypted, does not present the
   document as intact, and leaves other documents and templates unaffected.
8. **Given** the user deletes a document, **When** the deletion completes, **Then** the user
   understands exactly what was deleted and what remains stored.
9. **Given** stored documents and templates, **When** the user returns to the start area,
   **Then** documents and templates are listed separately with title, last-edited date, and
   status, and the user can open either from the list.
10. **Given** a list entry, **When** the user deletes it from the list, **Then** the entry is
    removed after a German confirmation that names what will be deleted.

---

### User Story 6 - Explicitly Save Reusable Empty Templates (Priority: P2)

The user has just cleaned up the field layout of a form they receive every year. They choose
"Als Vorlage speichern" and later start a new, blank document from that template, with the same
pages and fields but none of their previous answers. When they later notice a field is missing,
they open the template itself, fix the layout, and save a new version — without touching any
document they already started from it.

**Why this priority**: Reuse is the difference between a one-off tool and a workflow the user
returns to. It is P2 because the first journey must work without it, but it must not be deferred
past the first milestone.

**Independent Test**: Create a template from a filled document, verify it contains pages and
confirmed fields but no values or signature; create two documents from the template, edit each,
and verify the template and the sibling document are unchanged.

**Acceptance Scenarios**:

1. **Given** a document whose field structure the user has reviewed, **When** the user chooses
   "Als Vorlage speichern", **Then** a template is created containing the original pages and the
   confirmed field definitions.
2. **Given** a document with entered values and a drawn signature, **When** the template is
   created, **Then** the template contains no entered values and no signature.
3. **Given** a stored template and a completed document, **When** the user views stored items,
   **Then** templates and documents are visibly distinguishable.
4. **Given** a template, **When** the user starts a new document from it, **Then** a new
   independent document opens with empty values and the template's confirmed fields.
5. **Given** a document created from a template, **When** the user edits fields or values,
   **Then** neither the template nor any other document derived from it changes.
6. **Given** an import or an export, **When** either completes, **Then** no template is created
   automatically.
7. **Given** a stored template, **When** the user opens it for editing, **Then** the user can
   change its field layout only, with no values or signatures available to enter.
8. **Given** an edited template, **When** the user saves the template, **Then** a new template
   version is created and identified as such, while documents already created from an earlier
   version keep their original layout unchanged.

---

### User Story 7 - Export a Completed PDF (Priority: P1)

The user finishes the form, exports it, looks at the result, and sends it to the authority. The
authority opens a normal PDF, sees the original form with the user's information placed where
the printed lines are, and prints it without surprises.

**Why this priority**: The export is the only artifact the recipient ever sees. An export that is
almost right is worthless, so this story carries artifact-level verification.

**Independent Test**: Complete a two-page reference form with text, numbers, dates, checked and
unchecked boxes, multiline text, umlauts, and a signature; export; open the result in at least
two independent PDF readers; verify page count, page appearance, value placement, checkbox
states, no clipping, and printability; verify the original document is unchanged.

**Acceptance Scenarios**:

1. **Given** a confirmed field set with values, **When** the user exports, **Then** the output
   contains every original page in the original order and appearance.
2. **Given** entered values, **When** the output is opened, **Then** each value appears at its
   field position in a readable size and is not clipped by the field boundary or the page edge.
3. **Given** checked and unchecked boxes, **When** the output is opened, **Then** exactly the
   intended boxes appear checked and others appear unchecked.
4. **Given** a signature the user intentionally included, **When** the output is opened,
   **Then** the signature mark is present at its position.
5. **Given** multiline values and German special characters, **When** the output is opened,
   **Then** line breaks and characters appear correctly.
6. **Given** content that does not fit or would be clipped, **When** the user starts the export,
   **Then** the export is stopped with a German warning identifying the affected fields, and the
   user can correct the values or geometry and retry.
7. **Given** a completed export, **When** the user reviews it, **Then** the user can open the
   produced file in a viewer before sharing, saving, or printing it.
8. **Given** a produced file, **When** the user saves, shares, or prints it on Android, **Then**
   the standard system flows are available.
9. **Given** a produced file, **When** it is opened in an ordinary PDF reader, **Then** it is
   fully self-contained, prints without requiring interaction, and shows no editable form
   controls.
10. **Given** a failed or interrupted export, **When** the user looks for the result, **Then** no
    partial file is presented as a successful export.

---

### User Story 8 - Understand Recognition Quality (Priority: P2)

The user can tell which regions the app guessed, which it is unsure about, which pages it could
not process, and which fields they themselves confirmed. The app never pretends to have
understood a form perfectly.

**Why this priority**: Honest uncertainty is what makes the correction workflow trustworthy.
Claiming certainty the system does not have causes users to submit wrong forms.

**Independent Test**: Use a low-contrast, skewed form and a form with a damaged page; verify
uncertain suggestions are distinguishable from confident ones and from confirmed fields, that
the damaged page is explained, that the rest of the document remains usable, and that no
surface claims full recognition.

**Acceptance Scenarios**:

1. **Given** a suggestion with low confidence, **When** the user views the document, **Then** the
   uncertainty is visible without the user opening a separate report.
2. **Given** a page that failed analysis or an unsupported structure, **When** the user views the
   document, **Then** the failure is explained in German and the page remains otherwise usable.
3. **Given** automatic suggestions and user-confirmed fields, **When** the user views the
   document, **Then** the two states are distinguishable at a glance and in any summary.
4. **Given** a partially detected document, **When** the user continues working, **Then** the
   user can add, correct, and fill fields normally.
5. **Given** any summary or status surface, **When** detection results are described, **Then** no
   surface states or implies that recognition is complete or error-free.

---

### User Story 9 - Fast Browser-Based Development and Validation (Priority: P2)

While the product is being built, the product owner opens the document editor in a local browser,
imports a controlled reference document, moves and resizes fields, zooms, navigates pages, and
checks layout at different window sizes — without deploying to Android for every change.

**Why this priority**: This is the project's mandated development and validation surface and
directly determines how fast the P1 stories can be verified. It is P2 because it enables value
rather than delivering it to end users.

**Independent Test**: In Chrome, run the full editing journey on controlled reference documents
at several viewport sizes and verify geometry, overlays, navigation, editing, and accessibility
semantics; then confirm that each simulated platform result is labeled SIMULATED and that browser
results are reported separately from Android results.

**Acceptance Scenarios**:

1. **Given** the development build, **When** the owner opens it in a local browser, **Then** the
   document editor runs and the main journey can be exercised without an Android device.
2. **Given** controlled reference documents, **When** browser tests run, **Then** they cover
   import, field display, selection, move, resize, reclassify, navigation, zoom, and filling.
3. **Given** platform-dependent behavior such as document picking, recognition, storage, or
   export, **When** the browser build substitutes a deterministic simulation, **Then** every
   simulated result is labeled SIMULATED in the interface, logs, and reports.
4. **Given** browser test results, **When** results are reported, **Then** they are reported
   separately from Android results and never counted as Android acceptance evidence.
5. **Given** different browser window sizes, **When** the editor is used, **Then** controls,
   overlays, and pages remain usable without overlap or inaccessible content.

---

### Edge Cases

- **Source file removed after import**: When the user later moves, renames, or deletes the picked
  file, the stored document MUST still open, render, and export completely from its protected
  copy.
- **Image-only scans**: Pages with no text layer MUST be fully usable; detection MUST NOT depend
  on selectable text being present.
- **Multi-page authority forms**: Every page MUST be analyzed, navigable, and exportable; a defect
  on one page MUST NOT invalidate others.
- **Mixed page sizes and orientations**: Each page MUST keep its own dimensions and orientation;
  fields MUST stay attached to their own page.
- **Rotated or skewed scans**: Skewed content MUST NOT cause suggestions to be silently placed at
  wrong coordinates; when orientation cannot be determined reliably, the app MUST mark the page
  as uncertain and rely on user correction. The original page appearance MUST NOT be altered.
- **Low-contrast documents**: Detection MUST still attempt a result, MUST mark reduced
  confidence, and MUST leave manual placement available.
- **Very small checkboxes**: Small boxes MUST be selectable and tappable at a usable zoom without
  the hit area changing the exported mark position.
- **Borderless input areas**: Regions without a printed border MUST be supported through label,
  alignment, and whitespace cues, and MUST be addable manually.
- **Tables with blank cells**: Cells MUST be individually addressable; duplicate suggestions on
  the same cell MUST be surfaced rather than silently merged.
- **Pre-filled scanned forms**: Printed values already in the scan MUST be treated as
  uneditable page content; the app MUST NOT claim to edit or remove them, and MUST allow
  overlaying values where the user needs to.
- **Labels above or beside fields**: Labels MUST be used to infer field identity and MUST NOT
  themselves become fields.
- **Conflicting or overlapping suggestions**: Both candidates MUST remain visible and
  individually resolvable; no automatic silent resolution.
- **Incorrect field classification**: Reclassification MUST be possible at any time and MUST
  report any entered value that becomes incompatible.
- **Missing or unreadable pages**: The document MUST remain partially usable, the defect MUST be
  visible, and export MUST NOT silently drop or replace the page.
- **Unsupported password-protected PDFs**: Rejection MUST be specific, MUST NOT request a
  password, and MUST NOT create a document or draft.
- **Long text that does not fit**: The user MUST be warned before finalization; content MUST NOT
  be truncated or omitted.
- **German special characters**: ä, ö, ü, ß, €, and German quotation marks MUST survive entry,
  storage, and export.
- **Impossible or ambiguous dates**: A date that does not exist in the calendar MUST be rejected
  with a German message; a field expecting a month or free text MUST be reclassifiable to text
  instead of forcing a fake date.
- **Unexpected app termination**: The last durably saved state MUST return; unsaved work MUST be
  identified as lost or at risk rather than silently assumed present.
- **Device storage exhaustion**: The operation MUST be blocked with a German message, the last
  saved state MUST survive, no stored document or template MUST be deleted automatically, and no
  partial file MUST be reported as a successful export.
- **Encryption-key loss or unavailable local data**: The affected data MUST be reported as
  unreadable, and unrelated documents, templates, and drafts MUST remain intact.
- **Independent template use**: Editing a document created from a template MUST NOT alter the
  template or sibling documents.
- **Template edited after documents exist**: Saving a new template version MUST leave every
  document already created from an earlier version unchanged, still fully fillable and
  exportable.
- **Different browser window sizes**: The editor MUST remain operable and legible at small and
  large viewports.
- **Different Android screen sizes and densities**: Field geometry MUST map consistently to the
  page regardless of screen size, density, or zoom.
- **Exported PDFs opened elsewhere**: The artifact MUST open, render, and print correctly in
  ordinary PDF software outside the product.

## Requirements *(mandatory)*

### Functional Requirements

**Import and source integrity**

- **FR-001**: Users MUST be able to import a PDF through the ordinary Android document selection
  and opening flows.
- **FR-002**: The system MUST accept single-page and multi-page PDFs, including image-only PDFs
  with no selectable text and no interactive form fields.
- **FR-003**: The system MUST display all pages of an imported document in their original order
  with original page dimensions, orientation, and visual appearance.
- **FR-004**: The system MUST never modify, rewrite, or delete the imported source file.
- **FR-005**: The system MUST reject password-protected or unsupported encrypted PDFs without
  requesting, capturing, or storing a password.
- **FR-006**: When password protection is confirmed, the system MUST show a specific German
  message naming that cause.
- **FR-007**: When the failure reason is uncertain, the system MUST NOT state or imply that the
  file is password-protected.
- **FR-008**: The system MUST report unsupported, unreadable, missing, truncated, or damaged
  files with a German message that states the actual failure category.
- **FR-009**: A rejected import MUST NOT create a document, a draft, a template, or a stored
  record.
- **FR-010**: If some pages of an otherwise usable document are unreadable, the system MUST keep
  the readable pages usable, mark the affected pages as unreadable, and inform the user that a
  full export is affected.

**Field detection**

- **FR-011**: The system MUST automatically analyze imported pages and propose candidate input
  regions without user action.
- **FR-012**: Proposed field types MUST cover single-line text, numeric, date, checkbox,
  multiline text, and signature regions.
- **FR-013**: Detection MUST use visible document structure, including labels, ruling lines,
  borders, boxes, whitespace, table cells, alignment, and spatial relationships between labels
  and empty regions.
- **FR-014**: Every proposed field MUST retain the page it belongs to and its position relative to
  that page's original geometry.
- **FR-015**: Every proposal MUST be recorded as an unconfirmed suggestion with an uncertainty
  indication, and MUST NOT be treated as user intent.
- **FR-016**: Printed text on the page MUST NOT be proposed as user input.
- **FR-017**: Detection MUST produce a result for each page independently, so that a failure on
  one page does not remove or invalidate results on other pages.
- **FR-018**: Pages MUST remain navigable and editable while analysis of other pages is still in
  progress or has failed.
- **FR-019**: A failed page analysis MUST be reported in German with its failure category.
- **FR-020**: Users MUST be able to create fields manually on any page at any time, including
  pages where detection failed.

**Review and correction**

- **FR-021**: Users MUST be able to confirm a suggested field so that it becomes part of the
  document's confirmed field set.
- **FR-022**: Users MUST be able to reject a suggested field, and the rejection MUST be
  reversible.
- **FR-023**: Users MUST be able to add fields, remove fields, move fields, resize fields, and
  change field types.
- **FR-024**: The system MUST preserve corrected geometry exactly and keep it aligned with the
  printed page across zoom levels, page navigation, reopening, and export.
- **FR-025**: The system MUST visibly surface overlapping or conflicting suggestions and MUST
  require the user to resolve them, without silently discarding either candidate.
- **FR-026**: The system MUST allow users to review fields in page and document order and to
  change that order.
- **FR-027**: Users MUST be able to revise or restore their previous corrections for a field or
  document.
- **FR-028**: The system MUST visually distinguish unconfirmed suggestions, confirmed fields, and
  user-created fields.
- **FR-029**: When a field type changes, the system MUST preserve compatible entered content and
  MUST flag incompatible content instead of discarding it silently.
- **FR-030**: A document MUST remain fully usable for review and filling when detection is
  incomplete, wrong, or absent.

**Filling**

- **FR-031**: Users MUST be able to select a field by touching or clicking its position on the
  page, and the selected field MUST be visually highlighted.
- **FR-032**: Selecting a field MUST present a control appropriate to its type: text, number,
  date, checkbox, multiline text, or signature.
- **FR-033**: Users MUST be able to move focus forward and backward through the fields in their
  defined order.
- **FR-034**: Selecting a field MUST bring its region into a readable view without altering field
  geometry.
- **FR-035**: Users MUST be able to enter and edit multiline text with line breaks preserved.
- **FR-036**: Users MUST be able to add a handwritten signature that belongs only to the current
  document.
- **FR-037**: The system MUST warn the user before finalization when entered content exceeds the
  space available for its field.
- **FR-038**: The system MUST NOT silently truncate, drop, reorder, or omit entered information.
- **FR-039**: Entered values MUST survive page navigation, view changes, and returning to the
  document overview.
- **FR-040**: Users MUST be able to edit previously entered values at any time before export.
- **FR-041**: The system MUST show per-field completion state in the document overview.
- **FR-042**: Checkbox fields MUST support a checked and an unchecked state, and the state MUST
  be individually settable per field.

**Saving, durability, and recovery**

- **FR-043**: Users MUST be able to save an incomplete document and reopen it later.
- **FR-044**: The system MUST preserve confirmed field geometry, types, values, signatures, and
  verification states across save and reopen.
- **FR-045**: The system MUST preserve progress durably without requiring a manual save, using
  these checkpoints: a 2-second debounce after the last committed change, never longer than
  2 seconds, whenever the app leaves the foreground, and on an explicit save action.
- **FR-046**: The system MUST distinguish saved state from unsaved state in every status surface
  and MUST NOT claim that unsaved in-memory edits are durably stored.
- **FR-047**: A save MUST be reported as successful only after the stored state is confirmed
  readable; a failed or interrupted save MUST be reported as a failure.
- **FR-048**: A failed save MUST preserve the last successfully saved state and MUST keep unsaved
  changes available where feasible.
- **FR-049**: Saved documents, drafts, field values, and signatures MUST be stored in
  app-private storage protected by encryption whose key material is bound to the device and not
  exportable by the app.
- **FR-050**: The system MUST NOT require a separate application password and MUST NOT require
  biometric unlock.
- **FR-051**: The system MUST explain in German, before it becomes relevant and again on failure,
  that backups of protected data are limited and that lost key material means the affected data
  cannot be recovered.
- **FR-052**: Unavailable or lost key material MUST produce a specific German error, MUST NOT
  present affected data as intact, and MUST NOT damage unrelated documents, templates, or drafts.
- **FR-053**: Users MUST be able to delete a document, draft, or template, and the system MUST
  state in German what is removed and what remains.

**Reusable templates**

- **FR-054**: The system MUST offer an explicit "Als Vorlage speichern" action.
- **FR-055**: The action MUST be available for a document whose field structure has been
  reviewed, meaning every field suggestion has been confirmed or rejected and every user-added
  field has a verification state other than unreviewed.
- **FR-056**: A saved template MUST contain the original pages and the confirmed field
  definitions.
- **FR-057**: A saved template MUST NOT contain entered values, answers, or handwritten
  signatures.
- **FR-058**: Templates MUST be stored and presented distinguishably from documents.
- **FR-059**: Using a template MUST create a new independent document with empty values.
- **FR-060**: Editing a document created from a template MUST NOT modify the template or any
  other derived document.
- **FR-061**: The system MUST NOT create a template automatically during import, analysis, save,
  or export.

**Export**

- **FR-062**: Users MUST be able to export a document as a completed PDF once its fields are
  confirmed; empty fields MUST NOT block export. Handling of unresolved overlapping
  suggestions remains subject to the documented provisional export preflight policy.
- **FR-063**: The exported PDF MUST contain every original page in the original order with the
  original visual appearance.
- **FR-064**: Entered values MUST be rendered at their field positions in a readable size and
  MUST NOT be clipped by the field boundary or the page edge.
- **FR-065**: Checkbox states MUST be rendered so that exactly the intended boxes appear checked
  and all others appear unchecked.
- **FR-066**: Signatures the user intentionally included MUST be rendered at their field
  position.
- **FR-067**: Multiline values, line breaks, and German special characters MUST be rendered
  correctly.
- **FR-068**: The system MUST stop the export and warn in German, naming the affected fields,
  when content would be clipped or would not fit.
- **FR-069**: The exported PDF MUST be a flattened, self-contained document that opens, renders,
  and prints correctly in ordinary PDF readers without interactive form controls.
- **FR-070**: Users MUST be able to review the exported result before sharing, saving, or
  printing it.
- **FR-071**: The system MUST support the standard Android flows for saving, sharing, and
  printing the exported file.
- **FR-072**: A failed, interrupted, or partial export MUST NOT be presented as a successful
  export, and MUST NOT leave a partial file in the place a successful export would occupy.
- **FR-073**: Exporting MUST NOT modify the imported source document or the stored working
  document.

**Storage-exhaustion behavior**

- **FR-074**: When storage is insufficient, the system MUST block the affected import, save, or
  export and MUST show a German message explaining the cause.
- **FR-075**: After a storage failure, the last successfully saved state MUST remain intact and
  any still-held unsaved changes MUST remain available where feasible with a visible risk
  warning.
- **FR-076**: The system MUST NOT delete stored documents, drafts, or templates to free space
  automatically.
- **FR-077**: After the user frees storage, the blocked operation MUST be retryable without
  re-importing or re-entering data.

**Privacy and offline operation**

- **FR-078**: The complete core journey — import, analysis, detection, review, filling, saving,
  reopening, and export — MUST work with no network connection.
- **FR-079**: The system MUST NOT transmit document content, page images, recognized text, field
  values, answers, signatures, or derived data to any external service.
- **FR-080**: The system MUST NOT include automatic analytics, crash reporting, or usage
  telemetry.
- **FR-081**: Diagnostic information, if any, MUST remain on the device and MUST exclude document
  content, file names, recognized text, field values, and signatures.
- **FR-082**: The system MUST NOT create, copy, or retain plaintext document data in logs,
  caches, thumbnails, temporary shared locations, or backups, except the user-requested
  export-preview file in app-private cache, which MUST be limited to the preview lifetime and
  swept on startup and session end.

**Understanding recognition results**

- **FR-083**: The system MUST visibly indicate uncertainty for low-confidence suggestions.
- **FR-084**: The system MUST explain failed pages or unsupported structures in German.
- **FR-085**: The system MUST allow users to distinguish automatic suggestions from confirmed
  fields in any summary surface, in addition to the document-view distinction required by
  FR-028.

**Development and validation surface**

- **FR-086**: The document editor and the main editing journey MUST be operable and inspectable
  in a local browser during development, using controlled reference documents.
- **FR-087**: Substituted platform behavior in the browser MUST be deterministic and MUST be
  labeled SIMULATED wherever it appears in the interface, logs, or reports.
- **FR-088**: Browser-based validation results MUST be reported separately from Android results
  and MUST NOT be used as evidence for Android-specific acceptance.
- **FR-089**: The exact same user-visible field geometry and interaction behavior MUST be
  exercised in the browser and on Android, so that browser findings transfer to the product.

**Accessibility and language**

- **FR-090**: All primary user-interface text, error messages, and recovery guidance MUST be in
  German.
- **FR-091**: All primary controls and navigation MUST be reachable and operable through
  accessibility semantics, including screen readers and focus traversal.
- **FR-092**: Text MUST remain readable and operable with enlarged system text settings and MUST
  support sufficient contrast for text and important controls.
- **FR-093**: Touch targets for primary controls MUST be large enough to operate reliably on a
  phone screen.
- **FR-094**: Error states MUST be readable text, not color-only or icon-only signals.

**Imported source retention**

- **FR-095**: Import MUST store the system's own protected copy of the original source document
  inside app-private encrypted storage, so that the working document remains fully usable if the
  user's picked file is later moved, renamed, deleted, or becomes inaccessible.
- **FR-096**: The protected copy MUST be treated as the document's source of truth for rendering
  and export, and MUST NOT be modified by any user action inside the app.

**Stored document access**

- **FR-097**: The system MUST provide a start area listing stored documents and stored templates
  as separate groups, each entry showing at least its title, last-edited date, and status.
- **FR-098**: Users MUST be able to open any stored document or template from that list.
- **FR-099**: Users MUST be able to delete a stored document or template from that list, after a
  German confirmation that names the item and states what will be removed.
- **FR-100**: The list MUST remain usable for a device holding at least 50 stored documents and
  templates without requiring search or filtering to reach an item.

**Template editing and versions**

- **FR-101**: Users MUST be able to open a stored template and edit its field layout, including
  adding, removing, moving, resizing, reclassifying, and reordering fields.
- **FR-102**: Template editing MUST be layout-only: no field values and no signatures can be
  entered or stored in a template.
- **FR-103**: Saving template changes MUST create a new template version with its own creation or
  modification date, and the version MUST be visible on the template.
- **FR-104**: Documents already created from an earlier template version MUST keep their original
  field structure and MUST NOT be updated, re-pointed, or rewritten when the template changes.
- **FR-105**: New documents created after a template change MUST use the latest saved version.
- **FR-106**: A template save MUST follow the same atomicity rule as a document save: it is
  reported as successful only after the stored version is confirmed readable.

**Date entry**

- **FR-107**: Date fields MUST validate input as a real calendar date in the German
  day.month.year form, accepting entries with or without leading zeros.
- **FR-108**: Impossible or malformed dates MUST be rejected with a German message that names the
  expected form, and MUST NOT be stored as a field value.
- **FR-109**: Users MUST be able to type date values; an additional date picker MAY be offered,
  but MUST NOT be the only input method.
- **FR-110**: When the user reclassifies a date field as text, it MUST accept free text without
  date validation.

### Key Entities

- **Document**: A user's working copy of an imported scanned PDF. Has pages, a confirmed field
  set, entered values, signatures, verification state, and a saved/unsaved status. Never
  modifies its source.
- **Source file**: The original imported PDF, preserved unchanged as the system's own protected
  copy inside app-private storage and used as the document's rendering and export basis. Has a
  size, page count, and integrity state.
- **Page**: One page of a document. Has an index, original dimensions, orientation, visual
  content, analysis state, and an optional failure reason.
- **Field suggestion**: A machine-proposed input region. Has page, position, proposed type,
  uncertainty indication, and a resolution state (unresolved, confirmed, rejected).
- **Confirmed field**: A field that belongs to the document's working structure. Has page,
  geometry, type, order, origin (suggested, user-created, template), and validation state.
- **Field value**: The content the user entered for a confirmed field. Has type-specific content
  (text, number, date, checkbox state, multiline text, signature mark), an overflow state, and a
  last-edited state.
- **Signature mark**: A handwritten mark belonging to one document and one field. Not reusable
  across documents.
- **Template**: A reusable empty form layout. Has original pages, confirmed field definitions,
  no values and no signatures, a version with a modification date, and a distinct identity from
  documents.
- **Draft / saved state**: The durable representation of a document at a point in time, including
  geometry, types, values, signatures, and verification states, with an indication of when it was
  last durably stored.
- **Export artifact**: The produced flattened PDF. Has a location, page count, verification
  result, and a success/failure state that is never optimistic.
- **Recognition evaluation record**: The measured result of running detection against the
  reference corpus. Has a frozen metric definition version, corpus version, device and
  conditions, and separately reported true positives, false positives, false negatives, type
  accuracy, and position accuracy.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: At least 90% of relevant fields on the reference corpus are detected correctly
  under the frozen strict-matching definition, measured using production recognition behavior on
  the authoritative Android platform.
- **SC-002**: The same evaluation run reports false positives, false negatives, field-type
  correctness, and spatial correctness separately, with counts and rates, and no combined
  headline number is used to replace them.
- **SC-003**: Manual placement work drops by at least 80% relative to fully manual placement,
  measured as the share of a form's fields that need no manual add, move, resize, or type change
  after the user's review.
- **SC-004**: A typical single A4 page is analyzed within 3 seconds (median) on a named
  representative Android device, with device characteristics, build type, and input document
  recorded with the result.
- **SC-005**: Every form in the reference corpus can be completed end to end and produces a
  flattened PDF that opens, renders, and prints in at least two independent PDF readers with no
  missing, reordered, or visually altered pages.
- **SC-006**: Across the full export verification set, the counts of clipped values, misplaced
  values, wrong checkbox states, and missing signatures are zero.
- **SC-007**: The complete core journey succeeds with the device in airplane mode, from import to
  export, with no network access required at any step.
- **SC-008**: Observing the app during the full offline journey shows zero outbound transmissions
  of document content, recognized text, field values, or signatures.
- **SC-009**: Every saved draft survives a normal app restart and a forced termination with all
  confirmed geometry, field types, values, and signatures intact in 100% of trials.
- **SC-010**: In 100% of induced storage-failure trials, no operation is reported as successful,
  the last saved state remains intact, and no stored document or template is deleted.
- **SC-011**: A password-protected PDF is rejected in 100% of trials with the specific German
  password-protection message, zero documents created, and a byte-identical source file.
- **SC-012**: A document created from a template never changes its template, and two documents
  created from the same template never change each other, in 100% of trials.
- **SC-013**: A template created from a filled document contains zero entered values and zero
  signature marks.
- **SC-014**: 100% of translatable user-facing strings in the release build are German, including
  errors and recovery guidance, with the constitutionally mandated untranslated `SIMULATED`
  evidence token allowlisted.
- **SC-015**: Accessibility checks pass on the primary journey: every control is reachable by
  screen reader and focus traversal, text scales to 200% without loss of function, text contrast
  meets the applicable minimum, and touch targets for primary controls meet the minimum usable
  size.
- **SC-016**: A two-page reference form is completed end to end — import, review, fill, save,
  export — with a median of 10 minutes or less for a user familiar with the form.
- **SC-017**: Field geometry measured from the rendered view matches the exported position within
  1 mm at A4 print scale, at every zoom level and on every tested screen size and density.
- **SC-018**: A first-time user, given only the app, can complete the full journey on Android
  without instruction beyond the on-screen German guidance, in 5 of 5 observed attempts.
- **SC-019**: In 100% of trials, a saved document still opens, renders, and exports after the
  originally picked file has been moved or deleted.
- **SC-020**: In 100% of forced-termination trials, at most the edits committed in the final 2
  seconds before termination are lost; every earlier committed edit is present after restart.
- **SC-021**: Editing a template and saving a new version leaves 100% of documents created from
  earlier versions unchanged, fillable, and exportable, while newly created documents use the new
  version.
- **SC-022**: In 100% of invalid-date trials, the value is rejected with a German message and no
  impossible date can be stored or exported.

## Evidence and Verification Rules

These rules govern how the success criteria and acceptance scenarios are proven. They exist
because the project produces evidence in several different environments.

- **Separated evidence classes**: Results MUST be reported as `SIMULATED` (browser with
  substitutes), `EMULATOR` (Android emulator), or `DEVICE` (physical Android device). Classes MUST
  NOT be merged into one unqualified claim.
- **Android authority**: Import, recognition, secure storage, permissions, and final PDF handling
  MUST be verified on a real Android runtime. Browser success MUST NOT satisfy these criteria.
- **Artifact-level export verification**: Export correctness MUST be judged by opening and
  inspecting the produced file in independent PDF software, not by inspecting app state.
- **Frozen measurement**: Corpus version, ground-truth reference data, matching rules, and scoring
  definitions MUST be fixed and versioned before the first scoring run. Later changes require a
  new, separately reported evaluation; earlier results MUST NOT be re-scored and presented as the
  same run.
- **Corpus provenance**: The reference corpus MUST contain at least 20 diverse real German
  authority forms with documented provenance and usage rights, and MUST contain no real personal
  data.
- **Honest reporting**: Failed targets MUST be reported as failures. Partial success MUST be
  described as partial, and no test, build, or closed task MUST be reported as product
  completion.

## Assumptions

- The project is delivered as a single shared application codebase with a browser-based
  development surface and Android as the production platform, per the project constitution.
  Detailed architecture, libraries, storage format, and recognition technique are planning
  decisions and are deliberately absent here.
- The reference corpus of at least 20 German authority forms will be assembled and rights-cleared
  during planning and before the first scored evaluation; its selection is not a specification
  decision.
- The representative Android device and emulator profile for performance measurement will be
  named in the plan, and every performance result will cite it.
- Signatures are drawn in the app for the current document only. Importing, photographing, or
  reusing a stored signature image is out of scope.
- Dates are validated as real calendar dates in day.month.year form (leading zeros optional).
  Fields whose printed area expects a month, a range, or free text are reclassified as text by
  the user rather than loosening date validation globally.
- Text that does not fit is warned about and left to the user to resolve by shortening or resizing
  the field. The system does not silently shrink, truncate, or auto-reformat entered text.
- Fields are not marked mandatory, and export is not blocked by empty fields; authority forms vary
  too much for a reliable general rule, and a blocking rule would risk preventing legitimate
  submissions. The user is informed of unfilled fields before export.
- Pre-filled values already printed in a scanned form remain part of the page image and cannot be
  edited or removed by the app.
- Documents are stored on the device only. There is no account, sync, or server component in this
  feature.
- The app is single-user per device; concurrent editing of the same document by multiple users is
  out of scope.
- A saved document's encryption is tied to device-bound key material, so copies of app-private
  data are not portable to another device. This limitation is disclosed to the user in German.
- Reference documents used in browser validation are controlled, synthetic, or rights-cleared,
  and no real personal document is used in tests, fixtures, logs, or reports.
- Recognition quality is improved after the journey works, driven by measured failures rather than
  by speculative tuning.

## Out of Scope (Initial Feature)

- iOS support.
- Camera-based scanning or photo capture of paper forms.
- Cloud or remote OCR, and any cloud PDF processing.
- Vision-language models for field detection.
- Destructive modification of original documents.
- User accounts, synchronization, or multi-device access.
- Subscription billing and commercial release management.
- A reusable stored-signature library.
- Automatic transmission of completed forms to authorities or other recipients.
- A second, non-shared user-interface implementation.
- Full document-library features: search, sorting options, folders, tags, and batch operations.
- Mandatory-field validation rules and form-specific business validation.
