<!--
Sync Impact Report
==================
Version change: none → 1.0.0 (initial ratification)

Rationale for 1.0.0: This is the first ratified baseline of project governance.
No prior constitution existed, so no backward-compatibility question arises;
1.0.0 declares the initial binding set of ten principles plus the architecture,
workflow, and governance sections.

Modified principles: none (no prior version existed)
Added principles:
  - I.   Product Outcomes First
  - II.  Flutter Web-First Development
  - III. Android Is the Authoritative Platform
  - IV.  Automatic Field Recognition
  - V.   Document Integrity and Reliable Export
  - VI.  Privacy, Security, and Offline Operation
  - VII. Data Safety and User Control
  - VIII.Testability and Evidence
  - IX.  Official Spec Kit Development
  - X.   Autonomous Multi-Agent Governance
Added sections:
  - Architecture and Platform Constraints
  - Development Workflow and Quality Gates
  - Governance (expanded with amendment, versioning, and compliance rules)
Removed sections: none

Follow-up TODOs: none. All placeholders resolved.
Deferred to later Spec Kit stages (not constitutional gaps):
  - Concrete rights-cleared corpus selection, corpus licensing evidence, and the
    frozen metric definition file for Principle IV belong to the specification and
    planning artifacts, not to this document.
  - The named representative Android device profile for the three-second A4 target
    and for physical-device acceptance must be fixed in the plan and cited by every
    performance claim.
-->

# Feldexa 2.0 Constitution

Feldexa 2.0 is a new, independent, privacy-first application that transforms scanned,
non-fillable PDF forms into editable and reusable smart forms. This constitution is the
highest project-level development policy and is binding on every human and agent working
on the project.

## Core Principles

### I. Product Outcomes First

- Delivering useful, working software MUST take precedence over infrastructure
  experiments, endless planning, and artificial progress metrics.
- Development MUST proceed through small, complete, independently verifiable user-facing
  increments. An increment is complete only when a user can observe the intended behavior.
- Every implementation task MUST trace to an approved product requirement, a demonstrated
  defect, or a necessary reliability improvement. Tasks without such a trace MUST be
  rejected or re-scoped before implementation.
- Successful builds, passing isolated tests, and closed GitHub issues MUST NOT be reported
  as product completion, either individually or in aggregate.
- The first milestone MUST demonstrate the entire user journey end to end: importing a
  scanned PDF, automatic field recognition, user confirmation or correction of fields,
  filling the form, saving the work, and exporting a correctly completed and flattened PDF.
- Unnecessary architectural complexity, speculative abstraction, and duplicate
  implementations of the same capability MUST be avoided. Complexity MUST be justified by
  a demonstrated requirement and MUST be documented.
- Interrupted work MUST resume from preserved state rather than restart, and abandoned work
  MUST be explicitly recorded as abandoned.

**Rationale**: The failure mode this project guards against is a repository that looks
healthy (green pipelines, closed tickets) while no user can complete a form. Only observed
end-to-end behavior counts as progress.

### II. Flutter Web-First Development

- Flutter and Dart MUST form the shared application codebase for Web and Android.
- Flutter Web running in Chrome MUST be the preferred rapid development and UI-testing
  surface. User interfaces, document navigation, form overlays, field geometry, zooming,
  scrolling, editing, and responsive layout MUST be testable through the browser wherever
  technically practical.
- Platform-independent business logic MUST be shared between Web and Android and MUST NOT
  be reimplemented per platform.
- Platform-specific capabilities MUST be accessed only through explicit, injectable,
  testable interfaces. UI and domain layers MUST NOT call platform APIs directly.
- Web development MAY use deterministic fixtures and simulated adapters for capabilities
  that require Android. Every simulated result MUST be labeled `SIMULATED` in artifacts,
  test output, and reports.
- Browser test success MUST NEVER be represented as actual Android runtime verification.
- The Web development environment MUST NOT require uploading confidential documents to
  external services.
- Native Android integrations MAY be implemented where necessary but MUST NOT replace
  Flutter as the application framework, and a parallel Kotlin/Jetpack Compose application
  MUST NOT be created.
- The production application MUST NOT depend on browser-only test adapters, fixtures, or
  simulated platform implementations.

**Rationale**: Browser feedback is fast and cheap; Android is where users actually work.
Sharing one Dart codebase with explicit platform ports keeps the fast loop honest without
forking the product.

### III. Android Is the Authoritative Platform

- Android is the target platform for production, acceptance, and eventual distribution.
- Real Android functionality MUST be verified in an actual Android runtime. Web-only
  verification MUST NEVER satisfy an Android-specific acceptance gate.
- Android-specific capability areas include at minimum: document import, permissions,
  native OCR, secure storage, application lifecycle, and final PDF handling.
- The integrated Orca Android emulator MUST be the preferred environment for routine
  Android development and automated runtime testing.
- Shared emulator access MUST be coordinated to prevent conflicting sessions: an emulator
  instance MUST be allocated exclusively for the duration of a test run, and conflicting
  concurrent sessions MUST be refused rather than queued into an ambiguous state.
- Final physical-device acceptance MUST be performed separately when the requirement or the
  project owner demands it. Emulator evidence and physical-device evidence MUST be reported
  as distinct evidence classes.
- Kotlin or Java code is permitted only where justified by Android platform integration.
  Such code MUST be documented in the plan, kept to a minimal surface, and exposed to Dart
  through the same explicit interfaces required by Principle II.

**Rationale**: Emulators and browsers approximate; they do not certify. Declaring Android
authoritative prevents a Web-only illusion of correctness in storage, OCR, lifecycle, and
PDF output — the exact areas where this product can silently fail.

### IV. Automatic Field Recognition

- Feldexa MUST automatically detect input fields in scanned, non-fillable PDF forms.
- Supported field types MUST include at minimum text, numbers, dates, checkboxes,
  multiline text, and signature regions.
- Detection MUST take document geometry into account, including labels, ruling lines,
  borders, whitespace, tables, and spatial relationships. OCR text MAY inform detection but
  MUST NOT be the sole signal.
- Field suggestions MUST preserve their original page coordinates: every suggestion MUST
  carry the source page index and a rectangle in source-page coordinate space.
- Users MUST be able to confirm, reject, add, move, resize, and reclassify fields.
- Recognition results MUST distinguish machine-generated suggestions from user-confirmed
  fields, and that provenance MUST survive saving, reopening, and export.
- Automatic field recognition MUST substantially reduce manual field-placement work. The
  reduction MUST be demonstrated by a measured comparison against a documented manual
  baseline, not by assertion.
- The quality target is at least 90% correctly detected relevant fields, measured against
  an independently verified, rights-cleared corpus containing at least 20 diverse real
  German authority forms.
- Evaluation MUST distinguish and report separately: false positives, false negatives,
  field-type correctness, and spatial correctness.
- Measurement definitions and ground-truth reference data MUST be fixed and versioned
  before the first scoring run. Changing them after scoring requires a new, separately
  reported evaluation.
- Failed detection thresholds MUST be reported as failures. Results MUST NOT be redefined,
  re-sampled, or excluded post hoc in order to pass.

**Rationale**: The product promise is the elimination of tedious manual field placement.
Without a frozen corpus and separated error classes, "90%" becomes a slogan instead of a
measurement.

### V. Document Integrity and Reliable Export

- Original imported PDF content MUST remain immutable. Import, recognition, filling, and
  export MUST NOT alter, re-render, or reconstruct the original page appearance.
- A UI-independent document model MUST represent pages, recognized fields, positions,
  types, values, and verification state. The model MUST be serializable and testable
  without any widget or rendering dependency.
- Field positions MUST remain aligned with original page geometry across zoom levels,
  devices, and export. Geometry MUST be defined in source-page coordinates and mapped at
  render time; device-pixel arithmetic MUST NOT be the source of truth.
- OCR output MUST NOT replace or reconstruct the original PDF page appearance. Recognized
  text is auxiliary data about the page, never a substitute for it.
- User values MUST be applied through separate editable overlays, and export MUST flatten
  those overlays onto the original pages.
- Exported documents MUST be valid, flattened PDFs suitable for standard PDF readers,
  printing, and submission.
- Text clipping, misplaced fields, incorrect checkbox states, missing pages, and lost
  signatures MUST be treated as defects and MUST block acceptance. They MUST NOT be
  downgraded to cosmetic issues.
- Export correctness MUST be independently verified against the produced artifact
  (rendered and inspected), not inferred from UI state or unit-test assertions alone.
- Reusable empty form templates MUST be stored separately from completed documents, and a
  template MUST NOT contain entered values or signatures.

**Rationale**: A misaligned or clipped export destroys trust in a document product even if
every feature "works". Keeping the source bytes immutable and the model UI-independent is
what makes geometry and export verifiable at all.

### VI. Privacy, Security, and Offline Operation

- The complete Android core workflow MUST operate offline: import, recognition, filling,
  saving, and export MUST all function without network access.
- Private PDFs, OCR text, field values, user answers, and signatures MUST NOT be transmitted
  to external services. The core path MUST NOT require any remote call, and OCR MUST run
  on-device.
- All sensitive documents and drafts MUST be stored in Android app-private storage using
  authenticated application-level encryption backed by Android Keystore.
- No separate application password and no mandatory biometric unlock is required for the
  initial product.
- Encryption-key loss, backup limitations, and data-recovery behavior MUST be explicitly
  addressed in the specification, implemented deterministically, and explained to the user
  in German. The product MUST NOT imply recoverability that does not exist.
- Real personal documents MUST NOT be included in repositories, test fixtures, GitHub
  issues, agent logs, or remote evaluation services. Fixtures MUST be synthetic or
  rights-cleared.
- The application MUST NOT include automatic analytics, crash reporting, or usage
  telemetry, and MUST NOT add SDKs that transmit user or document data.
- Diagnostic information MUST remain on-device and MUST exclude sensitive document
  contents, including paths, file names, OCR text, field values, and signatures.
- All temporary plaintext handling MUST be minimized and controlled: lifetime, location,
  and deterministic cleanup MUST be defined, and plaintext MUST NOT persist in logs,
  caches, thumbnails, or backup artifacts.
- The application MUST provide understandable deletion and data-management behavior for
  documents, templates, drafts, and derived data.

**Rationale**: The product handles the most sensitive personal paperwork of its users. Any
convenience feature that leaks, logs, or silently backs up a document is disqualifying, not
a trade-off.

### VII. Data Safety and User Control

- A reusable empty template MUST be created only through an explicit user action. It MUST
  NOT be created implicitly by saving or exporting a document.
- Saving a template MUST preserve the document and the confirmed field structure while
  excluding entered values and signatures.
- Using a template MUST create an independent editable document. Edits to a derived
  document MUST NOT propagate to the template or to other derived documents.
- The application MUST NOT silently delete stored user documents to recover storage space.
- Storage-exhaustion failures MUST preserve the last successfully saved state and provide
  clear German recovery guidance.
- Unsupported encrypted or password-protected PDFs MUST be rejected with a German error
  message that names the cause and the unsupported state, without altering the source file.
- Missing, corrupted, or unsupported files MUST NOT produce falsely successful imports.
  Failure MUST be visible to the user in German.
- Saving and recovery MUST protect confirmed user work against avoidable loss. A save MUST
  be atomic (no partially written state is presented as success) and MUST NOT report
  success before the data is durably stored and readable.
- The application MUST NOT claim that unsaved in-memory edits are durably preserved, and
  MUST surface unsaved state as at risk.

**Rationale**: Users trust the app with work they cannot easily redo. Destructive cleanup,
optimistic save reporting, and ambiguous template semantics are the most common ways a
document app loses that trust irreversibly.

### VIII. Testability and Evidence

- Flutter analysis and automated Dart tests MUST validate shared application logic.
- Browser-based tests MUST validate document interaction, overlay geometry, navigation,
  field editing, zooming, scrolling, and responsive layout, and other suitable UI
  functionality.
- Android integration and end-to-end tests MUST validate real platform behavior.
- Evidence MUST be reported in separate, clearly labeled classes: `SIMULATED` (Web
  fixtures and simulated adapters), `EMULATOR` (Android emulator runtime), and `DEVICE`
  (physical Android device). Evidence MUST NOT be merged into a single unqualified claim.
- The product targets typical A4-page analysis within three seconds on representative
  Android hardware. Performance claims MUST state the measurement conditions, build mode,
  device or emulator profile, and input corpus. Unmeasured performance claims MUST NOT be
  made.
- Independent PDF export validation MUST verify the produced artifact itself.
- Privacy, encryption, recovery, OCR, field detection, and export MUST each have
  failure-case tests covering their documented failure modes, including at minimum: key
  unavailability, interrupted or exhausted storage, corrupted input, unsupported
  encryption, failed recognition, and rejected export.
- Passing tests are necessary but not sufficient evidence of a usable product. Acceptance
  requires the complete user journey to work on the authoritative platform.
- Paid hosted CI MUST NOT be required for ordinary development. Required checks MUST be
  runnable with the local and self-hosted toolchain.
- German MUST be the primary user-interface language. User-facing strings, error messages,
  and recovery guidance MUST be German and reviewed for clarity.
- Accessibility, semantic controls, scalable text, suitable contrast, and readable error
  states MUST be tested, not merely intended.

**Rationale**: This project depends on evidence produced by several very different
runtimes. Labeling evidence and refusing to let tests stand in for acceptance are what keep
"done" meaningful across browsers, emulators, and devices.

### IX. Official Spec Kit Development

- Official GitHub Spec Kit is the mandatory specification-driven development framework.
- The installed official Spec Kit commands MUST be used for Constitution, Specify,
  Clarify, Plan, Checklist, Tasks, Analyze, Implement, and Convergence where supported by
  the active installation.
- Manually creating equivalent-looking artifacts MUST NOT count as executing a Spec Kit
  command. Artifacts MUST record the command that produced them so provenance is auditable.
- Specifications MUST describe user needs and observable behavior. Technical
  implementation choices MUST be documented in the planning phase, not smuggled into
  specifications.
- Generated tasks MUST remain traceable to their approved specifications. Tasks that cannot
  be traced MUST be rejected rather than retro-fitted with a justification.
- The official GitHub Spec Kit extension MUST be used for task-to-issue conversion when that
  workflow is required. Existing issues MUST be searched before creating new ones; duplicate
  issues and speculative backlog expansion MUST be avoided.
- Missing or unavailable integrations MUST be reported accurately. A stage that could not be
  executed MUST NOT be described as executed or approximated by hand-written substitutes.
- Completed specification stages MUST NOT be unnecessarily recreated. Changes MUST go
  through the update or amendment path that the installed Spec Kit workflow provides.
- Specification-driven development MUST support delivery rather than become an independent
  objective.

**Rationale**: Spec Kit artifacts are only trustworthy when they are the genuine product of
the framework. Fake compliance with the process is worse than none, because it hides the
missing analysis behind well-formatted documents.

### X. Autonomous Multi-Agent Governance

The project uses one accountable Maintainer and specialized agents.

| Role | Agent | Responsibility |
| --- | --- | --- |
| Maintainer | Codex in Chat Mode | Overall coordination, prioritization, delegation, integration, recovery, and verified product delivery |
| Spec Kit Manager | OpenCode using `deepseek/deepseek-flash` | Executing official Spec Kit workflows and managing specification artifacts |
| Development Workers | DeepSeek Harness using the owner-configured DeepSeek Flash model | Implementing assigned tasks through the actual installed Spec Kit integration in isolated worktrees |
| Independent Reviewer | Codex CLI | Independent code-quality and requirements-fulfillment reviews |

Binding rules:

- There MUST be exactly one project-level Maintainer.
- Workers MUST operate in isolated worktrees. A worktree MUST have at most one active
  assignment at a time.
- Each worktree MUST remain available until verified integration or explicit abandonment.
  Abandonment MUST be recorded with its reason.
- Existing completed work MUST be inspected before duplicate implementation begins:
  branches, worktrees, issues, and prior reviews MUST be checked first.
- Independent reviews MUST evaluate the exact candidate revision, identified by commit.
  A review of any other revision is invalid for approval.
- Code quality and requirements fulfillment MUST both be reviewed.
- Failed reviews MUST lead to targeted corrections and renewed independent evaluation.
- Workers MUST NOT approve their own work. Author and reviewer MUST be different agents.
- Approved changes MUST be integrated into the canonical main branch, and the integrated
  result MUST be verified after integration.
- Ordinary authorized development MAY continue without repeated owner approval. Protected
  operations and unresolved significant product decisions MUST require explicit owner
  authorization.
- All agent-to-agent communication MUST be in English. The Maintainer MUST communicate with
  the project owner in German.
- Conflicts between principles, or a gate that cannot be met as written, MUST be escalated
  to the owner. Gates MUST NOT be silently lowered, re-labeled, or bypassed.

**Rationale**: Parallel agents multiply throughput and also multiply the damage of
self-approval, stale reviews, and duplicated work. Separating authorship from review and
pinning reviews to revisions are the minimum safeguards.

## Architecture and Platform Constraints

The binding architectural decision is: **Feldexa 2.0 is a Flutter Web-first development
project with Android as its authoritative production platform.** This decision is
non-negotiable while version 1.x of this constitution is in force.

- Single framework: Flutter/Dart only for application code. No parallel Kotlin/Jetpack
  Compose or other native application. Native code is limited to justified platform
  integration behind explicit interfaces.
- Shared core: domain model, field recognition orchestration, geometry mapping, form
  state, template logic, save/recovery logic, and export preparation MUST live in
  platform-independent Dart packages that both Web and Android consume.
- Ports and adapters: document import, OCR, secure storage, PDF rendering, and file export
  MUST be defined as interfaces with at least a real Android implementation and a Web
  implementation used for development. Production MUST NOT resolve a simulated adapter.
- Document model: pages, fields, geometry, values, provenance, and verification state MUST
  be representable without widgets, MUST be versioned, and MUST survive a
  save-reopen-export round trip without loss.
- Storage: documents, templates, and drafts MUST be stored encrypted in app-private
  storage, separated by kind, with atomic write semantics.
- Corpus and fixtures: the recognition corpus MUST be rights-cleared, independently
  verified, versioned, and never contain real personal data. Fixtures used in Web
  development MUST be deterministic.
- Dependencies: every third-party dependency MUST be justified against privacy,
  offline-operation, and licensing requirements. Dependencies that require network access,
  telemetry, or non-compatible licensing MUST NOT be accepted.
- Scope discipline: no feature unrelated to the approved specifications may be added to the
  codebase in anticipation of future needs.

## Development Workflow and Quality Gates

The mandatory cycle is:

Specification → Clarification → Planning → Task Generation → Implementation → Testing →
Independent Review → Correction → Integration → Verification.

Gates (each MUST pass before the next stage begins):

1. **Specification**: user needs and observable behavior captured through the official
   Specify workflow, with requirements-quality checks applied.
2. **Clarification**: open ambiguities resolved through the official Clarify workflow; no
   unresolved material ambiguity may enter planning.
3. **Planning**: technical approach, interfaces, data model, and risks documented in the
   plan; complexity justified.
4. **Task generation**: tasks traceable to specification requirements, dependency-ordered,
   and converted to issues where required through the official extension.
5. **Consistency analysis**: cross-artifact analysis confirms spec, plan, and tasks agree.
6. **Implementation and testing**: work performed in an isolated worktree with the
   evidence classes of Principle VIII, including failure-case tests.
7. **Independent review**: a different agent reviews the exact commit for both code quality
   and requirements fulfillment.
8. **Integration and verification**: approved work merged to canonical main, then the
   integrated result is re-verified.
9. **Convergence**: remaining gaps between specification and implementation are identified
   and closed through the official convergence workflow.

Definition of Done for a user-facing milestone:

- The complete user journey works on the authoritative platform, not only in the browser.
- German UI text and German error and recovery paths are present and readable.
- Offline operation of the core workflow is demonstrated in an Android runtime.
- Export has been independently validated on the produced PDF artifact.
- Privacy and data-safety failure cases are covered by tests.
- Simulated, emulator, and device evidence are reported separately.
- The change is independently reviewed at the integrated revision and verified after merge.

## Governance

**Authority.** This constitution supersedes all other project practices, templates,
conventions, and agent habits. In any conflict, the constitution prevails. Every plan,
task, review, and pull request MUST be checked against it, and reviewers MUST cite the
principle that a change satisfies or violates. A violation blocks integration. No agent may
silently weaken this document, and no practice may be introduced that contradicts it.

**Amendment procedure.** Amendments require, in order:

1. A written proposal stating the exact change, its justification, and its expected
   product impact.
2. A semantic version proposal with reasoning.
3. An impact analysis listing affected principles, specifications, plans, tasks, tests, and
   released artifacts.
4. Explicit approval by the project owner. Only the project owner may ratify amendments.
5. Execution through the genuine installed Spec Kit Constitution workflow, recording the
   new version, the ratification date, the amendment date, and the rationale in this file.

**Versioning policy.** This document follows semantic versioning:

- MAJOR: backward-incompatible governance change, removal or redefinition of a principle,
  or any weakening of the non-weakenable guarantees listed below.
- MINOR: a new principle or section, or materially expanded binding guidance.
- PATCH: clarifications, wording fixes, and non-semantic refinements.

**Non-weakenable guarantees.** The following MUST NOT be weakened by any PATCH or MINOR
amendment, and any attempt to weaken them is a MAJOR change requiring explicit owner
approval with documented justification and impact analysis:

- privacy, offline operation, and no-telemetry guarantees (Principle VI);
- document integrity and export correctness (Principle V);
- Android runtime verification and the Web-first/Android-truth architecture
  (Principles II and III);
- independent review with author/reviewer separation (Principle X);
- real product acceptance over test and process metrics (Principles I and VIII).

**Compliance review.** Compliance MUST be verified at every gate listed in the Development
Workflow and at each milestone. The review MUST confirm at minimum: evidence is correctly
labeled and separated, no telemetry or network path was introduced into the core workflow,
real personal documents are absent from the repository and logs, the recognition corpus is
rights-cleared and its metrics were frozen before scoring, and export was validated on the
artifact.

**Runtime guidance.** Operational execution detail belongs in the Spec Kit plan template,
the specification and task artifacts, and the per-worktree agent briefs. Those documents MUST
remain consistent with this constitution; where they conflict, this constitution governs and
the dependent document MUST be corrected.

**Version**: 1.0.0 | **Ratified**: 2026-11-12 | **Last Amended**: 2026-11-12
