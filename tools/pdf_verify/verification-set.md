# Export verification set and membership (T112, SC-005/SC-006)

Defined 2026-11-27. The rows are the `contracts/export-plan.md` §6 verification
set. Membership names who executes a check and with which tool. A tool that is
absent on the evidence host is named, not silently skipped.

Legend: **V1** = executable today with present tooling; **V2** = defined but
needs a tool that is absent on this host (`qpdf`, MuPDF); **V3** = task-owned
runtime acceptance (T109/T143/T334 driver) and therefore not proven by a host
command.

| §6 check | Tolerance / criterion | Tool | Member | Status |
| --- | --- | --- | --- | --- |
| Structural validity | must pass (`qpdf --check` external, PDFBox reload internal) | `qpdf --check` + PDFBox reload (in-app) | V1 (qpdf), V3 (reload) | `qpdf` PASS on the T344 artifact; the reload stays in-app |
| Page count and order | exact | `pdfinfo`, page-by-page `pdftoppm` | V1 | covered by T105/T334 artifacts |
| Page geometry | 0.01 pt | `pdfinfo` + `verify_artifact.py` | V1 | automated (sizes and rotation from pdfinfo) |
| Original appearance | pixel-identical outside overlays | `pdftoppm` + PPM mask compare (`verify_artifact.py`) | V1 | masked PASS on the T344 artifact |
| Value placement | ≤ 1 mm (2.835 pt), ascent 0.61 mm | `placement.py` + `verify_artifact.py` | V1 | **PROVEN** (T344 B; harness PASS) |
| Text content | exact after whitespace normalization | `pdftotext` | V1 | used in T105/T334 |
| No clipping | zero clipped values | `pdftotext -bbox` + rect tolerance (`verify_artifact.py`) | V1 | PASS on the T344 artifact |
| Checkbox states | exact | rendered ink-density comparison (`verify_artifact.py`) | V1 (implemented), T109 executes | T109 |
| Signatures | present, aspect preserved | rendered ink-density comparison + store read-back | V1 (implemented), T109 executes | T109 |
| No interactive controls | zero AcroForm fields | byte search `/AcroForm`, PDFBox | V1 | used in T334 |
| Printability | 300 dpi on two engines | `pdftoppm` + `mutool draw` | V1 | PASS (Poppler + MuPDF 1.28.5) |
| Source integrity | SHA-256 unchanged | `sha256sum` | V1 | used in T105/T334 |
| Artifact isolation | no `.pdf` after failure | driver + app test | V3 | T108/T334 driver |

## SC membership

- **SC-005** (opens/renders/prints in two independent readers): V1 rows +
  printability (V2). The second engine is blocked on MuPDF; the in-app PDFium
  preview does not satisfy "independent reader".
- **SC-006** (zero clipped/misplaced/wrong-checkbox/missing-signature):
  placement (V1) + checkbox/signature rows (V3, T109).
- `qpdf` 12.4.2 and MuPDF 1.28.5 are present; the V1 rows above were executed on the
  T344 artifact. Rows that need mark expectations remain `NOT_RUN` without them.
- **Artifact isolation** is an instance of **SC-010** (no false success, last saved state
  intact), owned by T108/T334; it is not part of SC-005/SC-006.
- Executable harness: `tools/pdf_verify/verify_artifact.py` runs every V1 row, including
  the masked appearance diff, the no-clipping measurement and the rendered mark
  comparison. Expectations for the T344 artifact are committed next to it.
