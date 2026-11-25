package de.feldexa.app.export

import de.feldexa.app.PlatformFailure

/**
 * T104: the applier-side plan checks (`contracts/export-plan.md` §4 and §6).
 *
 * The shared Dart builder already decided layout; this validator only proves
 * that the plan it produced is applicable to the stored page: the CTM must be
 * the normative matrix for the stored geometry, every op must lie on the page,
 * no text may overflow, and every code point must exist in the bundled font.
 * It never re-wraps, re-sizes, or re-positions anything (FR-037/FR-038).
 *
 * Every finding is a *blocking* code from §4, so `export.validate` reports a
 * non-empty result as the catalog code rather than as a non-blocking warning.
 * The whole object is plain JVM Kotlin; the font knowledge arrives through
 * [ExportFontMetrics] so the checks are testable without PDFBox.
 */
object ExportPlanValidator {
    /** `coordinates-and-geometry.md` §6: rects may overshoot the page by 0.5 pt. */
    const val OUTSIDE_PAGE_TOLERANCE_PT = 0.5

    /** `export-plan.md` §3.1: 1.5 pt padding on all sides. */
    const val TEXT_PADDING_PT = 1.5

    fun findings(plan: ExportPlan, metrics: ExportFontMetrics): List<ExportValidationFinding> {
        val findings = mutableListOf<ExportValidationFinding>()
        for (page in plan.pages) {
            checkPage(page, metrics, findings)
        }
        return findings
    }

    private fun checkPage(
        page: ExportPlanPage,
        metrics: ExportFontMetrics,
        findings: MutableList<ExportValidationFinding>,
    ) {
        if (!page.geometry.expectedCtm().matches(page.ctm)) {
            findings += ExportValidationFinding(
                code = "EXP-003",
                reason = "ctm_mismatch",
                pageIndex = page.index,
                fieldId = null,
            )
        }
        val displayBox = page.geometry.displayBox
        for (op in page.ops) {
            if (!op.rect.isInside(displayBox, OUTSIDE_PAGE_TOLERANCE_PT)) {
                findings += ExportValidationFinding(
                    code = "EXP-003",
                    reason = "outside_page",
                    pageIndex = page.index,
                    fieldId = op.fieldId,
                )
            }
            if (op is ExportTextOp) checkText(page.index, op, metrics, findings)
        }
    }

    private fun checkText(
        pageIndex: Int,
        op: ExportTextOp,
        metrics: ExportFontMetrics,
        findings: MutableList<ExportValidationFinding>,
    ) {
        // `export-plan.md` §2.2: an overflowing plan is never produced; if this
        // one still says so, the export is blocked instead of clipped.
        if (op.overflow) {
            findings += ExportValidationFinding("EXP-001", "overflow_flagged", pageIndex, op.fieldId)
        }
        val availableHeight = op.rect.height - 2 * TEXT_PADDING_PT
        if (op.lines.size * op.lineHeightPt > availableHeight + ExportPlanParser.GEOMETRY_TOLERANCE_PT) {
            findings += ExportValidationFinding("EXP-001", "too_many_lines", pageIndex, op.fieldId)
        }
        if (op.baselineFromTopPt > op.rect.height + ExportPlanParser.GEOMETRY_TOLERANCE_PT) {
            findings += ExportValidationFinding("EXP-001", "baseline_outside_field", pageIndex, op.fieldId)
        }
        val availableWidth = op.rect.width - 2 * TEXT_PADDING_PT
        for (line in op.lines) {
            if (line.isEmpty()) continue
            if (!metrics.coversGlyphs(line)) {
                findings += ExportValidationFinding("EXP-004", "glyph_missing", pageIndex, op.fieldId)
                // One missing glyph per field is enough; the code blocks the export.
                continue
            }
            if (metrics.advanceWidthPt(line, op.fontSizePt) > availableWidth + ExportPlanParser.GEOMETRY_TOLERANCE_PT) {
                findings += ExportValidationFinding("EXP-001", "too_wide", pageIndex, op.fieldId)
            }
        }
    }
}

/** One blocking plan finding; the German summary lives in the catalog, not here. */
data class ExportValidationFinding(
    val code: String,
    val reason: String,
    val pageIndex: Int?,
    val fieldId: String?,
)

/**
 * The applier's complete font knowledge.
 *
 * Production wraps the bundled Noto Sans through PDFBox
 * (`PdfBoxFontMetrics`); tests pass a fake so the geometry and overflow checks
 * run without a font binary or an Android runtime.
 */
interface ExportFontMetrics {
    /** True when every code point of [text] has a glyph in the bundled font. */
    fun coversGlyphs(text: String): Boolean

    /** Text advance width of [text] at [fontSizePt] in display points. */
    fun advanceWidthPt(text: String, fontSizePt: Double): Double
}

/**
 * Maps the first blocking finding to its catalog failure (`export-plan.md` §4).
 *
 * `fieldCount` counts the affected fields of the same code so the blocking
 * dialog can say "N Felder" without the applier naming a label or a value.
 */
fun exportPlanFailure(findings: List<ExportValidationFinding>): PlatformFailure? {
    val first = findings.firstOrNull() ?: return null
    val affected = findings.count { it.code == first.code }
    return exportFailure(first.code, first.pageIndex, affected)
}

/**
 * Catalog-coded export failure with no document content.
 *
 * Only the codes of `error-catalog.de.md` §4 are accepted; the category and
 * machine message pairs are the facade's allowlisted ones
 * (`platform-channel.md` §2.2).
 */
internal fun exportFailure(
    code: String,
    pageIndex: Int? = null,
    fieldCount: Int? = null,
): PlatformFailure = when (code) {
    "EXP-001" -> PlatformFailure("EXP-001", "exportBlocked", false, "export.blocked", pageIndex, fieldCount)
    "EXP-002" -> PlatformFailure("EXP-002", "exportFailed", true, "export.failed", pageIndex, fieldCount)
    "EXP-003" -> PlatformFailure("EXP-003", "geometryInvalid", false, "export.geometryInvalid", pageIndex, fieldCount)
    "EXP-004" -> PlatformFailure("EXP-004", "missingGlyph", false, "export.missingGlyph", pageIndex, fieldCount)
    "EXP-005" -> PlatformFailure("EXP-005", "sourceUnreadable", false, "export.sourceUnreadable", pageIndex, fieldCount)
    "EXP-006" -> PlatformFailure("EXP-006", "pageNotCopiable", false, "export.pageNotCopiable", pageIndex, fieldCount)
    "SAVE-001" -> PlatformFailure("SAVE-001", "storageFull", true, "save.storageFull", pageIndex, fieldCount)
    else -> throw IllegalArgumentException("not an export failure code")
}
