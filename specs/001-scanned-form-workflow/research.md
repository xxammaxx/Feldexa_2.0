# Phase 0 Research: Scanned Form to Completed PDF Workflow

**Feature**: `001-scanned-form-workflow` | **Date**: 2026-11-12 | **Plan**: [plan.md](./plan.md)

**Status**: All technical unknowns resolved. No item remains `NEEDS CLARIFICATION`. Product ambiguities were already resolved in the specification's five clarifications; this document records only technical decisions.

Version facts below were checked on 2026-11-12 against pub.dev, Maven Central, and upstream release pages. Versions are pinned in `pubspec.lock` / Gradle version catalogs at implementation time; any change requires the dependency review in D-19.

---

## D-01 — Application framework and codebase split

**Decision**: One Flutter application (`apps/feldexa_app`) on Flutter 3.47 / Dart 3.13, with shared functionality in nine local Dart packages and a minimal Kotlin integration layer inside the Android host. No separate Web app, no parallel Compose app, no server.

**Rationale**: Constitution Principles II and III require one shared codebase, a browser development surface, and Android authority. Local packages enforce dependency direction: `feldexa_core` and `feldexa_export` never import Flutter widgets or platform plugins, so they remain testable with `dart test` and reusable on both targets.

**Alternatives considered**:
- *Kotlin Multiplatform / Compose Multiplatform*: rejected — the constitution fixes Flutter as the framework.
- *Separate Flutter Web app sharing a package*: rejected — two shells and two navigation stacks drift; the requirement is the same editor geometry and behavior in both.
- *Flutter Web as a distributable product*: rejected — Web is the mandated development and validation surface only.

---

## D-02 — PDF rendering engine

**Decision**: PDFium through `pdfrx` 2.12.0 (MIT; PDFium BSD-3-Clause) for page rasterization on Android and Web. Android uses the plugin's native PDFium build; Web uses the locally bundled PDFium WASM asset.

**Rationale**: A byte-faithful renderer is mandatory because pages must be displayed exactly as scanned and must not be re-rendered into the export. `pdfrx` supports Android and Web, accepts in-memory bytes (`openData`), exposes page sizes and render-to-image at arbitrary scale, and requires Flutter 3.47/Dart 3.13 (matches the chosen toolchain).

**Alternatives considered**:
- *Android `android.graphics.pdf.PdfRenderer`*: render-only, no Web equivalent, inconsistent between API levels, and would fork rendering behavior between platforms — rejected.
- *`flutter_pdfview`*: Android/iOS only, no Web — rejected.
- *MuPDF*: licensing (AGPL/commercial) conflicts with project distribution constraints — rejected.
- *Commercial SDKs (PSPDFKit/Nutrient, Apryse)*: licensing and cost, and unnecessary for rendering only — rejected.

**Verification obligation**: The Web build must serve `pdfium.wasm` and CanvasKit from local assets (no CDN), verified by running the browser suite with network disabled.

---

## D-03 — Android document import

**Decision**: Native Kotlin `ImportService` using the Storage Access Framework: `ActivityResultContracts.OpenDocument` (`ACTION_OPEN_DOCUMENT`, `application/pdf`), reading the returned `content://` URI through `ContentResolver.openInputStream` directly into the encrypted staging writer. No `file_picker`, no plaintext temporary file, no persistent URI permission.

**Rationale**: FR-001 requires the ordinary Android picker; FR-082 forbids plaintext caches. Streaming the picker stream into the `FXC1` writer satisfies both. SAF needs no storage permission, so the release manifest requests none. The source URI is released after import; the protected internal copy becomes the source of truth (FR-095/FR-096).

**Alternatives considered**:
- *`file_picker` package*: copies the picked file into a cache directory before Dart sees it — a plaintext copy outside the encrypted container; violates FR-082 and complicates cleanup — rejected.
- *`file_selector`*: same cache-copy concern and weaker SAF semantics on Android — rejected.
- *`MANAGE_EXTERNAL_STORAGE` / broad storage permissions*: unnecessary, privacy-hostile, Play-policy risk — rejected.

**Failure handling**: Picker cancellation is a no-op (no document/draft, no error banner). Stream failures map to `IMP-002`/`IMP-003`; size above 80 MiB maps to `IMP-007` with a German message that states the limit and suggests a smaller scan. Preflight runs before any index entry is created (FR-009).

---

## D-04 — PDF preflight, overlay export, and flattening

**Decision**: `com.tom-roush:pdfbox-android:2.0.27.0` (Apache-2.0) for:
1. Import preflight: parse, page count, per-page MediaBox/CropBox/rotation, encryption detection (`InvalidPasswordException` / `PDDocument.isEncrypted`), damaged-page identification, existing AcroForm detection.
2. Font metrics for export validation (`PDType0Font.getStringWidth`) in contract tests.
3. Export: create a new document, import pages unmodified, append overlay content streams, flatten any pre-existing AcroForm, verify, save atomically.

**Rationale**: PDFBox is the only mature, permissively licensed Android-capable library that both reads and writes PDF content streams with embedded TrueType fonts and images. PDFium cannot author. Appending a content stream preserves the original page content and appearance — satisfying Principle V and FR-063/FR-069 — while drawing the user's overlays into the page (not into interactive widgets).

**Alternatives considered**:
- *PDFium write support*: not exposed by `pdfrx`; PDFium has no stable authoring API — rejected.
- *Dart `pdf` package for production export*: cannot import existing PDF pages; re-rendering the original would violate Principle V — rejected for production (retained only for the `SIMULATED` Web artifact).
- *Syncfusion Flutter PDF*: commercial licence — rejected.
- *iText/APryse*: AGPL or commercial — rejected.
- *Adding annotations or AcroForm fields instead of content streams*: leaves interactive controls and depends on reader flattening, violating FR-069 — rejected.

**Plaintext handling**: Preflight reads the staged ciphertext through a seekable decrypting `RandomAccessRead` (chunk-aligned) so no plaintext PDF file is created. Export decrypts the source into a bounded in-memory buffer (≤80 MiB cap), writes to an app-private encrypted artifact, verifies by reopening, then produces the temporary preview only when the user requests a preview.

**Risk**: PDFBox-Android 2.0.27.0 tracks PDFBox 2.0.27, while upstream PDFBox is 2.0.37 (2026-07-15). Accepted because PdfBox-Android is the maintained Android port; CVE review at pin time is mandatory. If a security-relevant CVE affects 2.0.27 without an Android port update, the plan requires an explicit owner escalation rather than an unreviewed fork.

---

## D-05 — On-device OCR

**Decision**: Bundled ML Kit Text Recognition v2 (Latin) through `google_mlkit_text_recognition` 1.0.2 (MIT wrapper), using the **bundled** Android model (`com.google.mlkit:text-recognition`), not the Play-services-downloaded variant.

**Rationale**: German authority forms need good Latin-script accuracy including umlauts; the bundled model works on first launch offline, needs no Play Services, and processes images on-device. OCR is auxiliary input to geometry-first detection (Principle IV), so its occasional errors degrade confidence rather than break the workflow.

**Alternatives considered**:
- *Tesseract4Android / `flutter_tesseract_ocr`* (Apache-2.0): fully open, but weaker accuracy on noisy German forms and larger language-data assets; kept as a documented fallback if ML Kit's bundled model cannot be verified offline.
- *Cloud Vision / any remote OCR*: prohibited by Principle VI and FR-079.
- *Vision-language models*: explicitly out of scope.

**Verification obligation**: Android instrumentation test with radios disabled proves OCR succeeds on a synthetic page and that the process opens no sockets. Dependency review records ML Kit's proprietary binary terms and confirms no analytics/telemetry dependency is pulled in. The release manifest omits `INTERNET`, which also prevents accidental use. If the licence review rejects ML Kit's terms for this distribution model, the documented fallback is Tesseract4Android (Apache-2.0) behind the same `OcrPort`; the quality target is then re-measured on the frozen corpus rather than assumed.

---

## D-06 — Recognition technique

**Decision**: Geometry-first, deterministic hybrid detection in `feldexa_recognition` (pure Dart):
1. Raster analysis at 200 DPI (grayscale, Sauvola-style adaptive threshold on integral images, deskew estimate via projection profiles).
2. Morphological run-length detection of horizontal/vertical rules (table grids, underlines, boxes) and connected components of whitespace.
3. Label anchoring: OCR word/line boxes are matched to adjacent candidate regions (right-of, below, aligned-left, inside-cell) using distance/alignment scores; label keywords refine type.
4. Candidate typing: single-line, numeric, date, checkbox, multiline, signature, using geometry (height/aspect, small square), label lexicon (`Datum`, `Geburtsdatum`, `Name`, `Straße`, `PLZ`, `Ort`, `IBAN`, `Telefon`, `E-Mail`, `Unterschrift`, `Aktenzeichen`, …), and OCR character classes.
5. Confidence from independent cue agreement; uncertainty = `1 − confidence`; evidence records cue types without storing page images.
6. Conflict detection: IoU ≥ 0.5 between candidates marks both as conflicting; neither is dropped.
7. Deterministic ordering by page, then top-to-bottom/left-to-right in source points.

**Rationale**: Principle IV requires geometry and forbids OCR as the sole signal; FR-013 lists exactly these cues. Pure Dart keeps the same detector in browser and Android, so interaction findings transfer (FR-089). Determinism makes golden tests and evaluation reproducible.

**Alternatives considered**:
- *OCR-only heuristics*: fails on image-only forms and violates FR-013/FR-016.
- *Trained object detector (TFLite)*: adds model provenance, training data, and licensing burden; not justified before the journey works; out of scope for the first milestone.
- *Server-side layout analysis*: prohibited.

**Performance**: 200 DPI A4 = 1654×2339 px. Analysis uses integral images and run-length scans; OCR is invoked once per page on a 200 DPI bitmap; the whole pipeline runs in a long-lived isolate. Budget: ≤ 3 s median on the named device.

**Failure isolation**: Each page runs in its own try/catch with failure categories `rasterization`, `ocr`, `unsupported_structure`, `internal`; pages already analyzed keep their suggestions (FR-017/FR-019).

---

## D-07 — Secure storage and key management

**Decision**: Android-native encryption with a non-exportable Keystore key:
- Master key: AES-256-GCM in Android Keystore alias `feldexa.master.v1`, `setUserAuthenticationRequired(false)`, StrongBox when available, TEE fallback. Key bytes never leave the Keystore.
- Per-object data key: 32 random bytes from `SecureRandom`, wrapped by the master key (AES-GCM) and stored in the object header.
- Payload encryption: AES-256-GCM in 1 MiB chunks; 12-byte IV derived from an 8-byte random file nonce plus a 4-byte big-endian chunk counter; AAD = container magic ‖ fileId ‖ chunkIndex ‖ chunkCount ‖ plaintextLength. Final chunk authenticated; truncation and reordering fail.
- Metadata (document/template JSON, revisions, index/head pointers) uses the same container with a smaller chunk size.

**Rationale**: FR-049 requires device-bound key material not exportable by the app. A Dart-held master key (even inside `flutter_secure_storage`) is readable by the app process and would weaken the guarantee; Keystore-wrapped data keys keep the root key non-exportable. Per-object keys make every encrypted file self-contained: a corrupted wrapped key or ciphertext affects one object (for example one revision or signature), never other documents, templates, or their sources (FR-052). Loss of the Keystore master key itself is the unavoidable device-wide case and is disclosed in German (FR-051).

**Alternatives considered**:
- *`flutter_secure_storage` alone for whole documents*: designed for small key/value secrets; large blobs and atomicity are not its contract — rejected as the storage engine (it is also unnecessary once Kotlin owns the Keystore).
- *Jetpack `EncryptedFile`*: deprecated/limited, whole-file rewrite semantics, weaker failure reporting — rejected.
- *SQLCipher via `sqlite3` 3.x*: adds a database and native crypto library, but this scope needs revisioned objects, not relational queries; would still not provide non-exportable root keys by itself — rejected.
- *Plain app-private files*: violates FR-049 — rejected.
- *User password / biometric gate*: prohibited by FR-050 — rejected.

**Recovery semantics**: Missing/corrupt master key or unwrap failure maps to `SAVE-002`. The object remains on disk untouched; other documents use independent data keys and remain readable. No automatic re-keying or deletion.

---

## D-08 — Persistence model and atomicity

**Decision**: No database. Per-document encrypted objects with append-only revisions and an atomic head pointer (details in [contracts/storage-format.md](./contracts/storage-format.md)):
- `meta.fx1` — identity, kind, title, timestamps, source reference, template origin/version, current status.
- `rev/<revisionId>.fx1` — immutable snapshot of fields, values, ordering, verification, signature references.
- `head.fx1` — pointer to the committed revision with its SHA-256.
- `src/<sourceId>.fxc` — immutable encrypted original PDF.
- `sig/<assetId>.fxs` — immutable encrypted signature PNG (per document/field).
- `templates/.../ver/<versionId>.fx1` — immutable template versions; documents pin the version they were created from.

Commit order: write payload to `tmp/` → fsync → decrypt-and-hash read-back → rename → write head to `tmp/` → fsync → rename → read-back verify. Success is reported only after head verification. Keep the last 3 autosave revisions plus the last explicit-save revision; prune older ones only after a verified commit.

**Rationale**: This scope is a single-user library of at most a few hundred objects; a database adds native dependencies, migrations, and a second durability model. Revision files make atomicity and crash recovery explicit and make template-version pinning trivial. Listing 50+ documents reads small encrypted heads only.

**Alternatives considered**:
- *Drift/SQLite*: query power not needed; adds migration and key-management surface — rejected.
- *Single JSON file per document*: multi-MB PDF duplication or plaintext coupling, and no atomic multi-asset commit — rejected.
- *SharedPreferences*: not for document data — rejected.

**Startup sweep**: delete `tmp/` entries older than 24 h; if `head.fx1` is missing/corrupt, fall back to the newest verified revision and surface "unsaved changes may be lost" (`SAVE-004`); never delete the only readable revision automatically.

---

## D-09 — Autosave and lifecycle

**Decision**: A single-writer `AutosaveCoordinator` in `feldexa_application`:
- 2 s debounce after the last committed change;
- immediate flush on `AppLifecycleState.paused`/`inactive` (via `LifecyclePort`) and on explicit save;
- serialized queue: at most one commit in flight; newer changes coalesce into the next revision;
- every state change publishes `DurabilityStatus {saved, saving, unsaved(risk), failed(code)}` with `lastDurableAt` and `lastDurableRevisionId`;
- save success requires storage read-back confirmation (see D-08).

**Rationale**: FR-045/FR-046/FR-047 and SC-020 require a precise "saved" meaning and bounded loss. Coalescing prevents write storms during drag/resize.

**Alternatives considered**:
- *Save on every keystroke*: I/O and battery cost, no benefit — rejected.
- *Manual save only*: violates FR-045 — rejected.
- *Background isolate writer with no completion signal*: cannot honestly report durability — rejected.

---

## D-10 — Geometry and coordinate model

**Decision**: Store every rectangle in **PDF points** in the page's display space: origin at the top-left of the visible page box (CropBox intersected with MediaBox), x right, y down, after applying the page's `/Rotate`. Store page display width/height, rotation, and crop offsets with the page. One shared `PageGeometry` mapper converts between display points, view pixels (scale/offset), and PDF user space for each rotation.

**Rationale**: Principle V forbids device-pixel truth; FR-014 requires positions relative to original page geometry; FR-024/SC-017 require alignment across zoom, device, and export within 1 mm. Points are the PDF-native unit and avoid cumulative normalized-float error.

**Alternatives considered**:
- *Normalized 0..1*: convenient but loses the direct mapping to PDF user space and invites rounding drift — rejected.
- *Pixels at a fixed DPI*: breaks mixed page sizes/zoom — rejected.
- *Bottom-left PDF user space in the model*: matches PDF but complicates UI hit-testing and rotation; conversion is localized in one mapper instead — rejected.

Full conversion rules and worked examples: [contracts/coordinates-and-geometry.md](./contracts/coordinates-and-geometry.md).

---

## D-11 — Text layout, fonts, and clipping detection

**Decision**: Bundle Noto Sans Regular/Bold (SIL OFL 1.1) and generate `metrics.json` (units-per-em, ascender/descender, per-codepoint advance and glyph availability) at build time from the TTFs. `feldexa_export` lays out values deterministically:
- font size = `clamp(0.6 × fieldHeightPt, 7 pt, 12 pt)`, never auto-shrunk below 7 pt;
- single-line: no wrapping; overflow when measured width > rect width − 2 × 1.5 pt padding;
- multiline: explicit `\n` plus greedy word wrap at the same font size; overflow when line count × line height > rect height − padding;
- vertical placement: baseline at top padding + ascender × font size; horizontal alignment left by default, centered for checkbox-adjacent/short numeric fields only if the field was created centered? — **no**, alignment is always left for text to avoid surprising placement; checkbox marks are centered in their box;
- overflow blocks export with German message `EXP-001` listing field label, page, and reason; no truncation, shrinking, or omission (FR-037/FR-038/FR-068).

**Rationale**: Identical metrics in Dart and PDFBox make the warning match the artifact. Bundling the font removes dependence on device fonts and guarantees ä/ö/ü/ß/€/„“ coverage.

**Alternatives considered**:
- *System fonts / PDF standard fonts*: no guaranteed glyph coverage for German typography and no metric parity — rejected.
- *Auto-fit/auto-shrink*: explicitly prohibited ("no silent shrink") — rejected.
- *Measure text in Kotlin and send results back*: Android-only and would make Web warnings simulated guesses — rejected.

**Verification**: Contract test on emulator compares 200 sample strings/lengths against PDFBox `getStringWidth` within 0.5 pt; golden artifact test renders the PDF and measures ink bounds against the planned rect.

---

## D-12 — Checkbox and signature rendering

**Decision**: Checkbox state renders as two stroked diagonal lines forming an "X" inset 15 % of the box, stroke width `clamp(min(width,height) × 0.08, 0.6 pt, 1.4 pt)`, black, independent of fonts. Unchecked renders nothing. Signatures are stored as transparent PNG (trimmed to ink bounds, capped at 1024 px on the long edge) and drawn scaled to fit the field rect while preserving aspect ratio, centered, never upscaled beyond 2× source pixels.

**Rationale**: Vector marks avoid font/glyph differences and remain crisp in print; PNG signatures preserve the handwritten mark. Checkbox mark placement is independent of the tap hit area (edge case: very small checkboxes).

**Alternatives considered**:
- *ZapfDingbats check glyph*: font-dependent and visually inconsistent — rejected.
- *Raster checkbox images*: scaling artifacts and larger files — rejected.
- *Storing signature as vector strokes*: more faithful but adds a vector format and smoothing complexity; out of scope for the first milestone.

---

## D-13 — Export delivery on Android

**Decision**: A single `DeliveryService` Kotlin integration plus `printing` and `share_plus` on the Dart side:
- **Preview**: in-app PDF viewer (`pdfrx`) of the produced artifact, with "SIMULATED" nowhere in production and verification status visible.
- **Save**: `ACTION_CREATE_DOCUMENT` via SAF, writing the artifact bytes to the user-chosen URI, then re-reading the URI to confirm the written size matches.
- **Share**: `Intent.ACTION_SEND` with `FileProvider` (`content://de.feldexa.app.exports/...`, `grantUriPermission`), `application/pdf`.
- **Print**: Android `PrintManager` through `printing`'s `PdfPrintDocument` file path, or native `PrintManager` if the plugin's temp-file behavior conflicts with the plaintext rules.
- After delivery/preview dismissal the app-private artifact and any cache preview are deleted; `tmp/` sweep also removes stale export files.

**Rationale**: These are the standard Android flows required by FR-071. SAF avoids storage permissions; FileProvider avoids exposing internal paths.

**Alternatives considered**:
- *Writing to shared Downloads directly*: needs permissions or MediaStore handling and silently places sensitive files in a broadly readable location — rejected.
- *Email intent only*: violates FR-071's save/print/share breadth — rejected.
- *Third-party file-manager plugins*: extra surface, unclear temp handling — rejected.

---

## D-14 — State management and navigation

**Decision**: `flutter_riverpod` (MIT) for dependency injection and observable state; `go_router` (BSD-3) for routes `/`, `/documents/:id`, `/templates/:id`, `/documents/:id/export` with browser URL support.

**Rationale**: Ports must be injectable and replaceable per test; Riverpod provides compile-safe providers and easy overrides without a service locator. `go_router` gives the browser meaningful URLs and back/forward behavior that the editor must tolerate (FR-039).

**Alternatives considered**:
- *`provider` + manual injection*: workable but more boilerplate for the number of ports — rejected.
- *BLoC*: heavier ceremony than needed; no architectural requirement — rejected.
- *Navigator 1.0 only*: poor browser history/deep-link behavior — rejected.

---

## D-15 — Localization and German strings

**Decision**: Flutter gen-l10n with a single release locale `de`, ARB source `lib/l10n/app_de.arb`, no fallback locale in release. All error/recovery messages come from the error catalog contract; UI text may not be hard-coded in widgets. A CI-free local check fails on missing keys, unused keys, or non-German placeholder strings.

**Rationale**: FR-090/SC-014 require 100 % German user-facing strings. Centralizing them makes the audit mechanical and lets tests assert exact German messages for failure paths.

**Alternatives considered**:
- *Hard-coded strings*: fails auditability — rejected.
- *`intl` message lookup without gen-l10n*: less type-safe — rejected.
- *Multi-language from day one*: out of scope and adds risk of English leaks — rejected.

---

## D-16 — Web development adapters and SIMULATED labeling

**Decision**: `packages/feldexa_adapters_simulated` implements every port deterministically:
- Import: fixed fixture catalog from `assets/fixtures/` (synthetic PDFs + expected OCR JSON), selected by ID; no real file upload.
- OCR: pre-authored OCR blocks in fixture coordinates (deterministic, not live recognition).
- Secure storage: in-memory store seeded from a deterministic fixture manifest, optionally persisted to `window.localStorage` under `feldexa.sim.` for reload tests; no encryption claim.
- Export: `pdf` package builds a preview PDF with the same overlay rectangles plus a visible `SIMULATED` watermark and footer.
- Delivery: browser download of the simulated artifact, labeled `SIMULATED`.
- Rendering: the Web raster adapter uses the real PDFium engine on fixture bytes for visual fidelity, but declares `evidenceClass: simulated` because it is a development adapter and cannot produce Android runtime evidence.

Every adapter returns `CapabilityEvidence.simulated` with `reason` and `adapterId`. A persistent banner, structured log prefix `[SIMULATED]`, test report fields (`evidenceClass: SIMULATED`), and evaluation output consume that flag. The Android registry never imports the simulated package; a release-build assertion and a dependency-graph test enforce it.

**Rationale**: Constitution Principle II and FR-087/FR-088 require deterministic substitutes that are impossible to mistake for Android truth. Pre-authored OCR (rather than running the real detector on fixtures) isolates UI validation from detector variance; the real detector is exercised separately in unit tests and on Android.

**Alternatives considered**:
- *Running real detection in the browser*: valuable for development but makes UI tests depend on detector changes; excluded from the editor suite, allowed only in dedicated `feldexa_recognition` browser tests.
- *Real file picking in the browser*: non-deterministic inputs and no Android fidelity — rejected for acceptance runs (a manual-only "open local file" debug affordance may exist, labeled SIMULATED).
- *A mock server*: adds a network component that the product must never have — rejected.

---

## D-17 — Testing and artifact verification toolchain

**Decision**:
- Shared logic: `dart test`; Flutter widgets: `flutter test`; browser: `flutter test --platform chrome`.
- Android integration: `flutter test integration_test -d <emulator>` plus Kotlin `androidTest` for Keystore/SAF/PDFBox/ML Kit failure modes.
- Artifact verification: `qpdf --check` for structural validity, `pdftoppm` (Poppler/PDFium path is separate) and `mutool draw` (MuPDF) for independent rendering, page-image comparison against expected overlay renders, `pdftotext` for German character and line-break checks, and a hash comparison proving the source file is unchanged.
- Fault injection: `FaultInjectingStore` (ENOSPC, short write, fsync failure), Keystore alias deletion, revoked/corrupt key material, truncated/encrypted/corrupt PDF fixtures, and a clock port for debounce tests.
- Deterministic fixtures: all synthetic, versioned in `corpus-1.0.0`; no real personal documents anywhere.

**Rationale**: Principle V requires artifact-level export verification; SC-006 requires zero clipping/misplacement/checkbox/signature defects. Two renderers reduce the risk of validating with the same engine that produced the file.

**Alternatives considered**:
- *Only unit tests*: cannot prove the artifact — rejected.
- *Only the in-app viewer*: same engine family as the exporter's renderer and not independent — rejected.
- *Hosted device farms*: paid hosted CI not required; owner-provided devices/emulators suffice — rejected for the mandatory path.

---

## D-18 — Corpus, frozen metric definition, and manual baseline

**Decision**:
- Corpus `corpus-1.0.0`: at least **20 diverse real German authority forms** with documented provenance, legal basis (e.g., § 5 UrhG for official works where applicable), retrieval date, SHA-256, page geometry, and ground-truth field rectangles/types, plus additional synthetic generated forms used as the deterministic CI subset. Real forms must be rights-cleared and contain no personal data (blank forms, or redacted before inclusion); if a form cannot be rights-cleared, it is not counted toward the 20. Manifest and checksums are committed; PDFs live under `tools/corpus/`.
- Metric definition `metric-definition.v1.md` is frozen before the first scored run: a ground-truth field counts as detected when a suggestion has IoU ≥ 0.5 and the same type; each GT field matches at most one suggestion; extras count as false positives; unmatched GT fields are false negatives. Reported separately: TP, FP, FN, precision, recall, type accuracy among matches, and mean position IoU. No combined headline metric replaces these.
- Ground truth is independently produced/verified by someone other than the detector author, with a verification record in the manifest (who, when, method, disputed fields resolved before freezing). Disputed fields are resolved before the first scored run, never after seeing results.
- Manual baseline (SC-003): for each corpus form, record the number of fields a reference operator must add/move/resize/reclassify after detection; compare against fully manual placement with the same operator and tool. Reduction = 1 − (manual actions after detection / fully manual actions).
- Any change to corpus, ground truth, or matching rule creates a new corpus/metric version and a new, separately reported run; earlier results are never re-scored as the same run.

**Rationale**: Principle IV and the spec's Evidence rules require frozen data and separated error classes. Synthetic forms give exact ground truth and zero privacy risk; rights-cleared real forms provide realism.

**Alternatives considered**:
- *Public form dumps with unclear rights*: provenance risk — rejected.
- *Synthetic-only corpus*: insufficient realism for the 90 % target; kept as the deterministic CI subset while real forms are the authoritative subset — rejected as sole source.
- *Redefining matches after seeing results*: explicitly prohibited.

---

## D-19 — Dependency and licence review gate

**Decision**: Every dependency must pass a written review before pinning: licence compatibility, offline operation, absence of telemetry/network defaults, Android API level, maintenance status, and CVE scan at the pinned version.

| Dependency | Version | Licence | Telemetry/network default | Verdict |
| --- | --- | --- | --- | --- |
| Flutter / Dart | 3.47 / 3.13 | BSD-3 | None | Accepted |
| `pdfrx` | 2.12.0 | MIT (PDFium BSD-3) | None; WASM asset bundled locally | Accepted |
| `pdfbox-android` | 2.0.27.0 | Apache-2.0 | None | Accepted, CVE scan required |
| `google_mlkit_text_recognition` (bundled) | 1.0.2 | MIT wrapper; Google model terms | On-device bundled model; no analytics dependency | Accepted with offline instrumentation proof |
| Android Keystore / SAF / PrintManager / FileProvider | Platform | Android SDK | None | Accepted |
| `flutter_riverpod` | 2.x | MIT | None | Accepted |
| `go_router` | 16.x | BSD-3 | None | Accepted |
| `image` | 4.x | MIT | None | Accepted |
| `pdf` (Web simulation only) | ^3.11 | Apache-2.0 | None | Accepted, dev-only |
| `printing` | 5.x | Apache-2.0 | None in offline print path | Accepted |
| `share_plus` | 12.x | BSD-3 | None | Accepted |
| Noto Sans Regular/Bold | 2.013 | SIL OFL 1.1 | None | Accepted, licence file bundled |
| `qpdf`, Poppler, MuPDF (test tooling) | Host toolchain | Apache-2.0 / GPL-2.0 / AGPL-3.0 (tooling only) | None | Accepted as local test tools, not redistributed |

**Rejected dependencies**: analytics/crash SDKs (Firebase, Sentry), any cloud OCR/PDF service, ad or attribution SDKs, sync/account SDKs, commercial PDF SDKs, and packages that request `INTERNET` in the release path.

**Rationale**: Constitution Architecture Constraints require justification against privacy, offline operation, and licensing. Recording the review makes later additions auditable.

---

## D-20 — Named devices and performance methodology

**Decision**:
- **Representative production device** (only source for the 3 s claim): Samsung Galaxy A54 5G, Exynos 1380, 6 GB RAM, Android 14 (One UI 6.1), release build.
- **Routine emulator**: Pixel 7 API 35, x86_64, 4 GB RAM, cold boot per suite, exclusive Orca allocation.
- **Measurement**: per-stage timers recorded with corpus form ID, page index, DPI, build mode, device/emulator profile, thermal state (if available), and app version; median of ≥ 20 page runs after one warm-up; results stored as JSON and cited in every performance statement.

**Rationale**: Principle VIII forbids unmeasured performance claims and requires stated conditions. Emulator results can guide development but cannot support the device claim.

**Alternatives considered**:
- *Emulator-only timing*: rejected — not authoritative.
- *Latest flagship device*: not representative of the target audience; owner may approve an additional device as a second `DEVICE` class.

---

## D-21 — Accessibility implementation

**Decision**: Shared editor widgets expose semantics nodes for pages, field overlays (label, type, value state, provenance, conflict), and controls; focus order follows field order; all primary actions are reachable by keyboard on Web and TalkBack on Android; 48 dp minimum touch targets with overlays' visual geometry independent of hit slop; text scales to 200 % with reflow; contrast ≥ 4.5:1 for text and ≥ 3:1 for control boundaries; error states are text plus icon, never color-only; zoom-to-field animates without changing geometry.

**Rationale**: FR-091…FR-094 and SC-015. Semantics tests plus a TalkBack walkthrough are the evidence; visual inspection alone is insufficient.

**Alternatives considered**: Relying on Material defaults — insufficient because the editor uses a custom-painted overlay canvas; explicit semantics are required.

---

## D-22 — Build flavors and production safety

**Decision**: Android build types `debug`, `profile`, `release`; a `develop` flavor may include diagnostic tooling but never simulated adapters. Web builds are explicitly development artifacts stamped `SIMULATED` in the shell. Compile-time and runtime guards:
- conditional imports select `registry_android.dart` vs `registry_web.dart` vs `registry_unsupported.dart`;
- `registry_unsupported.dart` throws on all capabilities;
- release bootstrap asserts no adapter reports `isSimulated == true`;
- `android/app/src/release/AndroidManifest.xml` omits `INTERNET`; `debug` overlays it for the Flutter tooling;
- a build test inspects the resolved dependency graph and fails if the simulated package is reachable from the Android registry.

**Rationale**: Constitution Principle II forbids production dependence on simulated adapters; a structural guard is stronger than a code review promise.

**Alternatives considered**: Runtime `kIsWeb` checks only — allow accidental web code paths in Android builds and vice versa; rejected.

---

## Resolved unknowns

| Original unknown | Resolution |
| --- | --- |
| Which framework/language version | Flutter 3.47 / Dart 3.13; Kotlin 2.x integration only (D-01) |
| PDF rendering approach on Android and Web | `pdfrx` 2.12.0 + PDFium, locally bundled WASM (D-02) |
| Android document picking without plaintext cache | Native SAF streaming import (D-03) |
| How to export a flattened PDF without re-rendering pages | PDFBox-Android page import + overlay content stream + verification (D-04) |
| On-device OCR choice | Bundled ML Kit Latin, auxiliary to geometry-first detection (D-05) |
| Detection algorithm and determinism | Pure-Dart geometry-first hybrid with cue-based confidence (D-06) |
| Device-bound encryption without exportable keys | Keystore master key + wrapped per-object keys + chunked AES-GCM (D-07) |
| Storage and atomic save semantics | Revisioned encrypted objects with atomic head pointer (D-08) |
| Autosave timing and durability reporting | Serialized debounced coordinator with read-back verification (D-09) |
| Coordinate space and rotation handling | PDF points in page display space with one mapper (D-10) |
| Text measurement and clipping policy | Bundled font + generated metrics + explicit overflow block (D-11) |
| Template versioning and independence | Immutable template versions pinned by derived documents (D-08, data model) |
| How browser results stay honest | Structural `SIMULATED` evidence flag and separate registries (D-16, D-22) |
| How export correctness is proven | Two independent renderers + structural checks + pixel/text assertions (D-17) |
| Corpus and metric freezing | `corpus-1.0.0`, `metric-definition.v1.md`, separate error classes, manual baseline (D-18) |
| Named performance device and method | Samsung Galaxy A54 5G, release build, per-stage timers (D-20) |
| Accessibility acceptance method | Semantics tests + 200 % scale + TalkBack + contrast checks (D-21) |
