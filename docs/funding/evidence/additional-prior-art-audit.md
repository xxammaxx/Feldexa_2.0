# Additional Prior-Art Audit — Feldexa 2.0

Date: 2026-11-13 · Auditor: technical prior-art subagent
Method: shallow clones (`--depth 1`) into `/tmp/opencode/feldexa-research/prior-art/`, source-code inspection with file:line evidence. Web-only projects use official documentation as SECONDARY evidence, explicitly marked. GitHub API metadata was cross-checked for licenses where no LICENSE file exists. No access controls were bypassed; no claims are made beyond inspected evidence.

---

## 1. CommonForms (jbarrow/commonforms)

- URL: https://github.com/jbarrow/commonforms
- HEAD SHA: `f5f400727132f0c03ce8a8bffe4dc6416fa9cfd0`
- Last commit: 2026-06-17 ("Fix --help crash, remove debug print...")
- License: **NONE DECLARED**. No LICENSE file in repo; `pyproject.toml` has no license field; GitHub API returns `"license": null`. Code is visible but **not legally reusable** without author permission.
- Access status: **cloned**

Questions answered from source:

1. **Static non-fillable PDFs? YES — this is its core purpose.** It renders every page to a raster image (`render_pdf()`, `commonforms/inference.py:274-290`, `page.render(scale=2).to_pil()`) and runs object detection (YOLO via FFDNet or RF-DETR, `inference.py:37-190`) — no AcroForm required. It can also *replace* existing fields (`keep_existing_fields` flag, `inference.py:373,408-409`; `clear_existing_fields()` in `form_creator.py:134-149` strips `/AcroForm /Fields` and page `/Annots`). Output: a newly fillable PDF (`form_creator.py` writes `/FT /Tx`, `/Btn`, `/Sig` widget annotations).
2. **OCR of scanned PDFs? NO.** Dependency list (`pyproject.toml`) contains no OCR engine (no tesseract/paddleocr/easyocr — only ultralytics, rfdetr, onnxruntime, transformers, pypdf, pypdfium2, pillow). Text association comes exclusively from the embedded text layer via pypdfium2 (`extract_text_fragments()`, `inference.py:235-271`). On a pure scan, detection boxes are still produced but there is no text-layer evidence and no OCR of contents.
3. **Semantic mapping to schema identifiers (FIM or other)? NO.** Field names are auto-generated positionally: `name = f"{widget.widget_type.lower()}_{widget.page}_{i}"` → e.g. `textbox_0_1` (`inference.py:413`). No label extraction, no schema, no vocabulary. Closest thing to semantics is a heuristic that reclassifies a TextBox as a Signature when the text layer contains a "signature" label near the box (`promote_signature_widgets()`, `inference.py:308-365`).
4. **Coordinates output? PARTIAL (API only, not CLI).** `BoundingBox` is normalized 0–1 per page (`commonforms/utils.py:8-16`); `Widget` carries `widget_type, bounding_box, page` (`utils.py:19-26`). But `prepare_form()` returns `None` and the CLI (`__main__.py:59-72`) writes only the output PDF — no JSON/coordinates export. A consumer would have to reuse the detector classes directly.
5. **Confidence scores? NO (threshold only).** `--confidence` is a detection *threshold* (`__main__.py:43-47`; `inference.py:70,143`). Per-detection confidence is dropped: the `Widget` model (`utils.py:19-26`) has no confidence field.
6. **CLI/API reusable? YES.** Pip-installable (`pyproject.toml`, `[project.scripts] commonforms`), documented CLI flags and Python API (`prepare_form`), model download from HuggingFace hub (`inference.py:22-28`). Models FFDNet-S/L, FFDetr; classes limited to `TextBox / ChoiceButton / Signature` (`inference.py:44,122`).
- Extras: encrypted-PDF detection → dedicated error (`inference.py:388-391`, `exceptions.py`); reading-order sorting of widgets (`inference.py:193-232`); paper + dataset (arXiv 2509.16506) exist.

---

## 2. GSA pdf-filler (GSA/pdf-filler)

- URL: https://github.com/GSA/pdf-filler
- HEAD SHA: `405ed8bf34df0c404e3fd72f38509b5c20aff1b4`
- Last commit: 2026-08-17 (merge; project is a small, effectively archival Sinatra app)
- License: MIT. readme.md: "This project constitutes a United States Government Work under 17 USC 105 and is distributed under the terms of the MIT License."
- Access status: **cloned** (tiny: `app.rb` 39 LOC, `lib/pdf_filler.rb` 94 LOC)

Questions answered from source:

1. **Non-fillable/scanned PDFs? YES — but only with caller-supplied coordinates.** The service fills non-fillable PDFs by *stamping text* at x/y positions the API consumer must already know: key regex `^(?<x>[0-9]+),(?<y>[0-9]+)(,(?<page>[0-9]+))?$` (`lib/pdf_filler.rb:16`) and `pdf.draw_text value, :at => [x, y]` (`lib/pdf_filler.rb:52-60`). The readme confirms: "non-fillable... require passing X, Y coordinates... `x,y,page`... pointer coordinates from the bottom left hand corner". No detection, no layout analysis.
2. **OCR? NO.** Nothing in the code or deps (pdftk + prawn only, `lib/pdf_filler.rb:1-7`).
3. **Semantic mapping? NO.** Fillable fields are addressed by their existing AcroForm names (`@pdftk.fill_form` with non-coordinate keys, `lib/pdf_filler.rb:49`); field inventory comes from `pdftk dump_data_fields` (`lib/pdf_filler.rb:79-92`) — pure name/type/default listing, no interpretation.
4. **Coordinates? Input-only** (see #1). It never extracts or outputs coordinates of anything.
5. **Provenance/audit? NOT_FOUND_IN_REVIEWED_CODE.** No logging, no mapping records, no audit trail; everything flows through `Tempfile`s (`lib/pdf_filler.rb:34-45`).
- Reusable API: yes (REST endpoints `/fill`, `/fields.json`, `/form`, `app.rb:19-39`), but it is a web service, not a library.

---

## 3. SurveyJS (surveyjs/survey-library + surveyjs/survey-pdf, formerly "pdf-generator")

- URLs: https://github.com/surveyjs/survey-library · https://github.com/surveyjs/survey-pdf (the requested `surveyjs/pdf-generator` no longer exists: GitHub returns "Repository not found"; the project was renamed to survey-pdf)
- survey-library: HEAD `403b8483837d63007bc50c3bd354a53a004c6b1e`, last commit 2026-11-13 (same-day active), **MIT** (LICENSE: "MIT License, Copyright (c) 2015-2026 Devsoft Baltic OÜ").
- survey-pdf: HEAD `5765dea0da5b2f7e07395efdb64230bf64e5b58f`, last commit 2026-11-11 (Release 3.2.5), **COMMERCIAL license** (LICENSE: "Commercial developer license for SurveyJS Creator, SurveyJS PDF Generator and SurveyJS Dashboard libraries.").
- Access status: **both cloned**

Relevance as prior art for "legacy static PDF → structured schema mapping": **low/orthogonal.**

- survey-library renders *web* forms from JSON-defined questionnaires (packages: survey-core, *-ui packages, converter — all MIT per package.json). It is the opposite direction: schema → web form. It contains no PDF parsing at all (no AcroForm/pdftk references in `src/`; grep returned nothing).
- survey-pdf (`src/pdf_forms/`) contains a `PDFFormFiller` plugin that fills **existing interactive** AcroForm PDFs from survey answer data. The survey-field → PDF-field-ID mapping is a **manual, developer-authored configuration**: `fieldMap` — "Object keys are survey field names and object values are PDF form field IDs... To find the IDs, open your PDF document in any editor that allows viewing them" (`src/pdf_forms/forms-base.ts:22-35`; concrete class `src/pdf_forms/forms.ts`). Field discovery is delegated to third-party libs (`form.getFields()` in `src/pdf_forms/adapters/pdf-lib.ts:8`); adapters for pdf-lib and PDF.js.
- What it does NOT do (evidence above): no detection of fields in static PDFs, no OCR, no automated semantic mapping (the map is hand-written config), no confidence, no FIM/XDF awareness, and it is not open-source (commercial), so not reusable in a Prototype Fund context.

---

## 4. ozg (LilithWittmann/ozg)

- URL: https://github.com/LilithWittmann/ozg
- HEAD SHA: `e6732e5ad426a9b3b2beeb227ef22cb54ad3d52f`
- Last commit: 2022-11-08 (dormant ~4 years)
- License: MIT (LICENSE file: "Copyright (c) 2020 Lilith Wittmann")
- Access status: **cloned**

Questions answered from source (`ozg/xdatenfelder/parser.py`, 517 LOC total project):

1. **FIM XDF parsing → JSON Schema? YES (v1 and v2).** Version detection via `xmlns:xdf` namespace: constants `FIM_VERSION_1 = "urn:xoev-de:fim:standard:xdatenfelder_1"`, `FIM_VERSION_2 = "..._2"` with `FIM_VERSION_MAPPING` and `_check_fim_version()` raising on unsupported versions (`parser.py:404-410, 438-445`). Output is JSON Schema draft 2020-12 with `$defs` (`parser.py:484-517`), used for react-jsonschema-form (README).
2. **Fidelity of mapping:** FIM field art/datenfeld type → JSON types (`input/select/label`, `text/date/bool/num/num_int/num_currency/file/obj`, `parser.py:282-291`); `xdf_praezisierung` → `minLength/maxLength/minimum/maximum/pattern` (`parser.py:302-316`); `select` fields fetch genericode code lists from XRepository (`parser.py:234-242`, `fim_code_lists.py`); min/max occurrence (`xdf_anzahl`) → array minItems/maxItems and `required` (`parser.py:125-128, 195-208, 381-394`); group/structure hierarchy → nested objects with FIM IDs as property keys (`parser.py:388`).
3. **Version handling? MINIMAL.** Only namespace-based v1/v2 discrimination. Optional header metadata (status, gueltigAb/gueltigBis, versionshinweis, freigabedatum...) is explicitly *not* parsed — TODO at `parser.py:35-36`. No XDF 3.0 support.
4. **Does it map PDF fields to FIM IDs? NO.** There is no PDF code anywhere in the repository (grep for "pdf" across *.py/*.md returns nothing). It never touches PDFs.
5. **Explicitly NOT done:** XDF→XSD conversion (no XSD writer in code); README roadmap marks "conversions from json to xöv xml documents" and "implementation of xzufi standard" as unchecked `[ ]` (README Features section).

---

## 5. RuiqiZhan/PDFform-info-migration-tool

- URL: https://github.com/RuiqiZhan/PDFform-info-migration-tool
- HEAD SHA: `6a69dbf6328d95533c687c2b5e0b70b6a0658dd2`
- Last commit: 2026-04-28
- License: **NONE FOUND** (no LICENSE file, no license in README/requirements.txt) — code visible but not reusable.
- Access status: **cloned** (~2,000 LOC Python)

What it actually does (README + code):

- **Purpose:** migrate *filled values* from an old, filled **XFA or AcroForm** PDF into a new blank **AcroForm** template — i.e. data migration between form *versions*. README: "transfer structured form data between versioned PDF templates", "Out of Scope (MVP): **Static or flattened PDFs, OCR-based extraction**, Cloud deployment"; Limitations: "Static PDFs are not supported".
- **Type detection:** `detect_pdf_type()` byte-scans for `/XFA`, `/AcroForm`, `/Fields` and returns `xfa | acroform | static` (`src/detector.py:19-30`) — static is *detected but rejected* (`is_fillable_pdf`, `detector.py:33-35`).
- **Extraction:** raw-object PDF parsing of widget `/V` values with full-name paths, page and rect: `WidgetFieldInfo(name, full_name, value, page_number, rect)` (`src/extractor.py:25-30`); XFA packet extraction exists but the XFA path is commented out in favor of widget values (README "Current Extraction Note"); checkbox/radio button-state values explicitly NOT supported (README "Checkbox and Radio Button State").
- **Mapping:** **exact-name matching only** — `build_source_target_match_report(set(source_fields), target_field_names)` (`src/matcher.py:101-106`; `src/writer.py:175`) with duplicate/ambiguity splitting (`split_unambiguous_and_duplicated_fields`, `writer.py:213`). **No fuzzy matching or confidence in code** — fuzzy mapping with a ~0.85 confidence threshold is *roadmap milestone M8* (README), i.e. planned, not implemented. Target field coordinates are inventoried: `TargetFieldInfo` with page + rect (`src/writer.py:15-22`), `--list-target-fields`, `--page-coverage-report`.
- **Coordinates? YES** for both source (`extractor.py:25-30`) and target (`writer.py:15-22`) fields, used for reports and the UI overlay.
- **Provenance/review? PARTIAL, good:** candidate items with `status`, `status_note`, `selected_by_default` for human review (`src/matcher.py:32-47`); Tkinter review UI with per-field include/exclude toggles and safe "Generate Output" step (`src/ui_app.py`, README); read-back verification of written values (`read_back_widget_values`, `writer.py:141`); processing summary + coverage/skipped reports (README M7).
- **NOT done:** static PDFs, OCR, semantic/schema-driven mapping (only name equality), FIM/XDF, confidence-scored suggestions, schema-valid structured output (output is a filled AcroForm PDF only).

---

## 6. MACH formsolutions (mach.de) — ⚠️ DOC-ONLY EVIDENCE, NO SOURCE ACCESS

Access status: **proprietary/web-only**; blocker: no public source repository (product is commercial govtech, "Von dieser Übersicht ausgenommen sind Werkzeuge kommerzieller Anbieter" per FITKO FIM docs). All evidence below is from official documentation only:

- Docs hub: https://docs.machproforms.de (Anwendung + Administration), wiki.form-solutions.de; product page https://www.mach.de/formsolutions; Form-Solutions GmbH is part of machgruppe (mach.de press release).
- **PDF form support (doc quote):** documentation index lists "PDF-Formulare | Interaktive PDF-Formulare hochladen, aktualisieren und bereitstellen" plus dedicated pages: PDF-Formulare hochladen / aktualisieren / veröffentlichen / Inhaltsdaten exportieren / Vorbefüllung von PDF-Formularen / "Hinweise zur Nutzung von **interaktiven** PDF-Formularen". → documented scope is *interactive* (AcroForm) PDFs; nothing documents detection of fields in static/scanned PDFs and no OCR is mentioned anywhere in the public docs.
- **PDF Structure-API (doc quote, docs.machproforms.de/administration/PDFStructureAPI.html):** "Die Feldnamen der XML-Transferdaten entsprechen den Formularfeldern der PDF-Formulare. Für die automatische Auswertung der XML-Dateien ist es somit notwendig, die Formularfelder **im Vorfeld** zu analysieren. Hierfür bietet der Formular-Server die Funktion `SendFormFields` an." Returns a TXT with "Feldnamen, Feldeigenschaften und den Standardwert" for types CheckBox, Text, MultiLineText, PushButton, "Type not defined" (radio), READ_ONLY. Caveat: "die Auswertung funktioniert **nur mit PDF-Formularen**" (interactive only). → a *field-inventory* API for existing AcroForm fields; the semantic analysis step is explicitly left to the human/recipient beforehand. No coordinates are documented in the output.
- **Mapping capability:** form-editor pages "Mapping" and "Multi-Knoten-Mapping" (docs.machproforms.de/anwendung/Mapping.html) document manual mapping of assistant form components to XML schema nodes; server admin exposes a "Fieldmapping" property page and an "XML Schemata" module. → structured *output* mapping exists, but it is editor-driven configuration, not automated extraction; no FIM/XDF field-ID semantics are documented publicly.
- **Interfaces:** documented FIT-Connect transport integration (docs "Transportschnittstellen – FIT-Connect"), BundID/ZBP integrations, Submission-API, Payment/eID/OSCI modules.
- Summary: documented capabilities = interactive-PDF hosting/prefill/export, AcroForm field inventory API, manual schema mapping, FIT-Connect transport. **Not documented:** static-PDF field detection, OCR, automated semantic extraction, FIM field-ID mapping, confidence/abstention mechanisms. (DOC_ONLY_EVIDENCE throughout.)

---

## 7. FITKO FIM Schema-Repository + XDF + FIT-Connect — ⚠️ DOC-ONLY EVIDENCE (+ live artifact fetch)

Access status: documentation + public HTTP endpoints (infrastructure specs); no adapter code reviewed here beyond ozg (above).

- **FIM docs** (https://docs.fitko.de/fim/docs/, CC BY 4.0, updated 2025-03-08/2026-04-22): structure covers "Baustein Leistungen", "Baustein Datenfelder", "Baustein Prozesse", "Werkzeuge und Infrastruktur".
- **FIM-Portal API** (docs.fitko.de/fim/docs/quer/api): "Die Arbeit und Qualitätssicherung mit FIM-Daten... bietet das FIM-Portal eine API (fimportal.de/docs) an. Diese ermöglicht IT-Dienstleistern den Zugriff auf die im FIM-Portal sichtbaren Leistungen, **Datenfelder** und Prozesse..." → machine-readable FIM data-field catalog = the vocabulary a semantic mapper would need.
- **FIM Schema-Repository (verified live):** `https://schema.fim.fitko.net/immutable/schemas/S00000096V1.0_2024-01-22-1705941843575.schema.json` returns a JSON Schema **draft 2020-12** whose property keys **are FIM field IDs** (e.g. `"F60000243V1.1": {"title": "Straße", "type": "string", "minLength": 1, "maxLength": 55}`), with groups `G…`, version suffixes in IDs, and an immutable, timestamped, versioned URL naming scheme (`S…V1.0_<epoch>`). → schema-valid output with FIM IDs and **immutable schema versioning** already exists as infrastructure an adapter could BUILD ON and validate against.
- **FIT-Connect** (https://docs.fitko.de/fit-connect/, operated by FITKO, IT-Planungsrat product, free): federal transport infrastructure; REST Submission API + Java/.NET SDKs; metadata as **JSON Schema 2020-12** with versioned `schema.uri` identification and modular `dataSets` (V2 metadata); deprecation schedule documented ("Ab 27. Oktober 2026 verfügbare Versionen: 2.0.0, 2.1.0, 3.0" — V1 shut off 2026-10-27).
- **Schema validation** (docs.fitko.de/fit-connect/docs/getting-started/schema-validation): documented step-by-step validation of submissions against FIM JSON schemas fetched from `schema.fim.fitko.net` (checksum-verified `contentStructure`), FIM-XFall XSD via FIM-Portal, and XÖV XSD via XRepository REST API. Key quote: "**FIT-Connect unterstützt ausschließlich XSD-Schemadateien. Andere Formate, wie XDF, werden nicht direkt verarbeitet.** Bei der Veröffentlichung von Schemata ist sicherzustellen, dass immer eine XSD-Version verfügbar und referenziert ist. **Entsprechende Converter werden von FIM zur Verfügung gestellt oder sind in der Konzeption.**" → official acknowledgment that XDF→XSD conversion tooling is third-party/in-conception, not a shipped integrated service.
- **What's missing (the gap Feldexa targets):** across all FIM/FIT-Connect documentation there is **no tool that maps the visible fields of a legacy (static/scanned) PDF to FIM data-field IDs**. The ecosystem provides: the ID vocabulary (FIM-Portal API), the target schemas (schema.fim.fitko.net), validation practice (FIT-Connect docs), and XDF parsers from third parties (see §8) — but no extraction/mapping bridge from paper-era PDFs into that ecosystem.

---

## 8. Additional open-source projects found (GitHub search)

Search used: GitHub repository API queries `xdatenfelder`, `fimportal`, `form field extraction semantic pdf` (code search requires auth — not used; no bypass attempted).

| Project | URL | Evidence (GitHub API metadata) | Assessment |
|---|---|---|---|
| flxbe/xdatenfelder-xml | https://github.com/flxbe/xdatenfelder-xml | "A parser for XDatenfelder **v2.0 and v3.0.0** files", TypeScript, **EUPL-1.2**, pushed 2023-03-15 | Useful XDF 3.0 parsing prior art (ozg stops at v2) |
| flxbe/xdatenfelder-ts | https://github.com/flxbe/xdatenfelder-ts | "TypeScript modules to work with the german eGov standard xDatenfelder", EUPL-1.2, pushed 2023-03-11 | Library companion |
| flxbe/xdlint | https://github.com/flxbe/xdlint | "A linter for XDatenfelder", EUPL-1.2, pushed 2023-03-15 | Quality tooling |
| maschinenlesbar-org/fim-portal-cli | https://github.com/maschinenlasbar-org/fim-portal-cli | "TypeScript API client & CLI for the open FIM Portal API — XDatenfelder, XZuFi and XProzess", **AGPL-3.0**, pushed **2026-11-10** (active) | Current, maintained FIM vocabulary access tool — candidate building block |
| aivot-digital/xdf2gov | https://github.com/aivot-digital/xdf2gov | "microservice designed to convert xDatenfelder into Gover form definitions", Go, no license declared, pushed 2024-08-15 | Same adapter pattern (XDF→form definition), different target |
| codedust/awesome-egov-de | https://github.com/codedust/awesome-egov-de | "curated list of resources on egovernment in Germany" | Index for further discovery |
| open-formulieren/open-forms | https://github.com/open-formulieren/open-forms | "Smart and dynamic forms", 62★, pushed 2026-11-13; LICENSE.md: "Licensed under the **EUPL**" (GitHub API spdx_id: NOASSERTION due to file format) | Dutch municipal form platform: JSON/Open-Forms-spec defined web forms → submissions; PDF is an *output/generation* concern (PDF generation lives in separate infra repos). **Not** prior art for legacy-PDF→schema import; no static-PDF field extraction found in org repos searched |

No open-source project found in any search that performs semantic mapping of PDF form fields to FIM/XDF field identifiers — consistent with the gap described in §7.

---

## Summary matrix (project × capability)

Legend: IMPLEMENTED / PARTIAL / NOT_FOUND_IN_REVIEWED_CODE / UNKNOWN / NOT_TESTED / DOC_ONLY_EVIDENCE (⚠️ = no source access)

| Capability | CommonForms | GSA pdf-filler | SurveyJS (lib+pdf) | ozg | RuiqiZhan migration | MACH ⚠️ | FITKO FIM/FIT-Connect ⚠️ |
|---|---|---|---|---|---|---|---|
| Static non-fillable PDF import (detect fields) | IMPLEMENTED | NOT_FOUND_IN_REVIEWED_CODE (coords must be caller-supplied) | NOT_FOUND_IN_REVIEWED_CODE (interactive fill only, manual map) | NOT_FOUND_IN_REVIEWED_CODE (no PDF code) | NOT_FOUND_IN_REVIEWED_CODE (explicitly out of scope) | DOC_ONLY_EVIDENCE (docs scope = interactive PDFs) | UNKNOWN (ecosystem gap) |
| OCR / scans | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE (out of scope, README) | DOC_ONLY_EVIDENCE (not documented) | UNKNOWN |
| Layout/field detection | IMPLEMENTED (CNN detection, 3 classes) | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE | n/a | PARTIAL (AcroForm widget inventory only) | DOC_ONLY_EVIDENCE (field inventory via SendFormFields) | n/a |
| Semantic field interpretation | NOT_FOUND_IN_REVIEWED_CODE (positional names) | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE (manual fieldMap) | n/a (XDF semantics given, not derived) | NOT_FOUND_IN_REVIEWED_CODE (exact name match; fuzzy = roadmap M8) | DOC_ONLY_EVIDENCE (manual editor mapping) | UNKNOWN (no tool documented) |
| FIM/XDF schema import + versioning | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE | IMPLEMENTED (XDF v1+v2 parse; version check = namespace only; header versioning TODO) | NOT_FOUND_IN_REVIEWED_CODE | DOC_ONLY_EVIDENCE (XML Schemata module, no FIM detail) | DOC_ONLY_EVIDENCE (immutable versioned schema repo, live-verified) |
| Mapping to FIM data-field IDs | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE | DOC_ONLY_EVIDENCE (not documented) | DOC_ONLY_EVIDENCE (FIM IDs = schema property names; no PDF mapper) |
| Confidence / uncertainty | NOT_FOUND_IN_REVIEWED_CODE (threshold only, per-widget scores dropped) | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE (planned M8) | UNKNOWN | UNKNOWN |
| UNKNOWN/abstention mechanism | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE (raises on unsupported) | PARTIAL (duplicates/unmatched reported & skipped) | UNKNOWN | UNKNOWN |
| Human review workflow | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE | n/a | n/a | IMPLEMENTED (Tkinter UI, candidate toggles) | DOC_ONLY_EVIDENCE (editor-based) | n/a |
| Field-level provenance / audit | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE | NOT_FOUND_IN_REVIEWED_CODE | PARTIAL (summaries, coverage, read-back verification) | DOC_ONLY_EVIDENCE (transaction archive/export) | DOC_ONLY_EVIDENCE (FIT-Connect event log) |
| Schema-valid structured output | PARTIAL (fillable PDF, no schema) | NOT_FOUND_IN_REVIEWED_CODE (filled PDF) | PARTIAL (survey JSON → PDF fields) | IMPLEMENTED (JSON Schema 2020-12 from XDF) | PARTIAL (filled AcroForm PDF, no data schema) | DOC_ONLY_EVIDENCE (XML transfer data) | DOC_ONLY_EVIDENCE (validation against repo schemas) |
| Original-document integrity | PARTIAL (clones input PDF, adds annotations; can strip fields) | PARTIAL (pdftk fill preserves template) | n/a | n/a | IMPLEMENTED (writes new copy, read-back verify) | DOC_ONLY_EVIDENCE | DOC_ONLY_EVIDENCE (encrypted transport, hashes) |
| Offline / privacy | IMPLEMENTED (local CLI, models via HF download) | NOT_FOUND_IN_REVIEWED_CODE (fetches PDFs by URL over HTTP) | PARTIAL (client-side lib) | IMPLEMENTED (local parsing) | IMPLEMENTED (local CLI, README "run locally") | DOC_ONLY_EVIDENCE (self-hosted offering) | n/a (operated service) |
| Reusable API/CLI | IMPLEMENTED (pip CLI + API) | IMPLEMENTED (REST service) | PARTIAL (commercial SDK) | IMPLEMENTED (pip library) | IMPLEMENTED (CLI + UI) | DOC_ONLY_EVIDENCE (Servlet/API) | DOC_ONLY_EVIDENCE (REST APIs + SDKs) |
| Reproducible evaluation | PARTIAL (published dataset + paper; no eval harness in repo reviewed) | NOT_FOUND_IN_REVIEWED_CODE | n/a | PARTIAL (tests/test_fim_parser.py) | PARTIAL (sample data + read-back tests; no formal eval) | UNKNOWN | UNKNOWN |

**Headline gaps (all with code-level evidence, none inferred from README silence):** No reviewed project combines (a) detection of fields in static/scanned PDFs [only CommonForms does detection, but without OCR, without retained confidence, without semantic labels], (b) OCR, (c) semantic interpretation / mapping to FIM IDs, (d) confidence + abstention + human review, and (e) schema-valid FIM-ID output. FITKO infrastructure (FIM-Portal API, immutable schema repo, FIT-Connect validation) provides the target vocabulary and schemas but explicitly lacks the legacy-PDF→FIM-ID mapping bridge ("Converter … in der Konzeption"). CommonForms is the strongest reusable detection base — but it carries **no license**, which blocks direct code reuse (contact author or re-implement).
