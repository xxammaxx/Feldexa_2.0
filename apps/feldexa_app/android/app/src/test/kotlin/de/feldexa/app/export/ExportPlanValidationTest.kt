package de.feldexa.app.export

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T104 host-JVM tests for the applier-side plan checks
 * (`contracts/export-plan.md` §4 and §6).
 *
 * The font is a deterministic fake, so these tests prove the geometry, overflow,
 * and glyph logic itself; the real Noto Sans subset is exercised by the
 * instrumented export run, not here (evidence class `NONE`).
 */
class ExportPlanValidationTest {

    private val metrics = FakeFontMetrics()

    @Test
    fun canonicalPlanHasNoFindings() {
        val plan = parse(
            ExportPlanFixtures.page(
                ops = listOf(
                    ExportPlanFixtures.textOp(),
                    ExportPlanFixtures.checkboxOp(),
                    ExportPlanFixtures.imageOp(),
                ),
            ),
        )
        assertTrue(ExportPlanValidator.findings(plan, metrics).isEmpty())
        assertNull(exportPlanFailure(ExportPlanValidator.findings(plan, metrics)))
    }

    @Test
    fun ctmThatIsNotTheNormativeMatrixIsAPayloadFailure() {
        val page = ExportPlanFixtures.page(
            ops = listOf(ExportPlanFixtures.textOp()),
            ctm = ExportPlanFixtures.ctm(1.0, 0.0, 0.0, 1.0, 0.0, 0.0),
        )
        val findings = ExportPlanValidator.findings(parse(page), metrics)
        assertEquals(listOf(ExportPlanValidator.CTM_MISMATCH_CODE), findings.map { it.code })
        assertEquals("ctm_mismatch", findings.single().reason)
        // `EXP-003` is "field outside the page"; a wrong matrix is a plan defect
        // and must not be reported as a document problem the user can fix.
        val failure = exportPlanFailure(findings)
        assertEquals("PLT-003", failure?.code)
        assertEquals("invalidPayload", failure?.details()?.get("category"))
        assertNull(failure?.details()?.get("pageIndex"))
    }

    @Test
    fun ctmMismatchWinsOverALaterGeometryFinding() {
        val page = ExportPlanFixtures.page(
            ops = listOf(
                ExportPlanFixtures.checkboxOp(
                    rect = ExportPlanFixtures.rect(590.0, 830.0, 20.0, 20.0),
                    pdfRect = ExportPlanFixtures.rect(590.0, 0.0, 20.0, 20.0),
                ),
            ),
            ctm = ExportPlanFixtures.ctm(1.0, 0.0, 0.0, 1.0, 0.0, 0.0),
        )
        val findings = ExportPlanValidator.findings(parse(page), metrics)
        assertEquals(
            listOf(ExportPlanValidator.CTM_MISMATCH_CODE, "EXP-003"),
            findings.map { it.code },
        )
        assertEquals("PLT-003", exportPlanFailure(findings)?.code)
    }

    @Test
    fun fixtureRotation180LiteralMatchesTheProductionCtm() {
        // The fixture's 180° matrix is a literal (`d = +1`) and is deliberately
        // not derived from `ExportPageGeometry.expectedCtm()`, so it cannot move
        // with a production formula change. Parsing that page must produce no
        // findings, which is what ties the two implementations together.
        val page = ExportPlanFixtures.page(
            rotation = 180,
            ops = listOf(
                ExportPlanFixtures.textOp(),
                ExportPlanFixtures.checkboxOp(),
                ExportPlanFixtures.imageOp(),
            ),
        )
        assertEquals(180, page.getValue("rotation"))
        assertTrue(ExportPlanValidator.findings(parse(page), metrics).isEmpty())
    }

    @Test
    fun ctmWithinThePointZeroOneToleranceIsAccepted() {
        val expected = ExportPlanFixtures.expectedCtm(0)
        val page = ExportPlanFixtures.page(
            ops = listOf(ExportPlanFixtures.textOp()),
            ctm = ExportPlanFixtures.ctm(
                a = expected.getValue("a") as Double,
                b = expected.getValue("b") as Double,
                c = expected.getValue("c") as Double,
                d = (expected.getValue("d") as Double) - 0.009,
                e = expected.getValue("e") as Double,
                f = expected.getValue("f") as Double,
            ),
        )
        assertTrue(ExportPlanValidator.findings(parse(page), metrics).isEmpty())
    }

    @Test
    fun rectOutsideThePageBlocksWithExp003() {
        val page = ExportPlanFixtures.page(
            ops = listOf(
                ExportPlanFixtures.checkboxOp(
                    rect = ExportPlanFixtures.rect(590.0, 830.0, 20.0, 20.0),
                    pdfRect = ExportPlanFixtures.rect(590.0, 0.0, 20.0, 20.0),
                ),
            ),
        )
        val findings = ExportPlanValidator.findings(parse(page), metrics)
        assertEquals("EXP-003", findings.single().code)
        assertEquals("outside_page", findings.single().reason)
    }

    @Test
    fun rectOvershootWithinTheHalfPointToleranceIsAccepted() {
        val page = ExportPlanFixtures.page(
            ops = listOf(
                ExportPlanFixtures.checkboxOp(
                    rect = ExportPlanFixtures.rect(0.0, 0.0, ExportPlanFixtures.PAGE_WIDTH + 0.4, 12.0),
                    pdfRect = ExportPlanFixtures.rect(0.0, 0.0, 12.0, 12.0),
                ),
            ),
        )
        assertTrue(ExportPlanValidator.findings(parse(page), metrics).isEmpty())
    }

    @Test
    fun overflowFlagBlocksWithExp001() {
        val page = ExportPlanFixtures.page(
            ops = listOf(ExportPlanFixtures.textOp(overflow = true)),
        )
        val findings = ExportPlanValidator.findings(parse(page), metrics)
        assertEquals("EXP-001", findings.single().code)
        assertEquals("overflow_flagged", findings.single().reason)
    }

    @Test
    fun tooManyLinesBlocksWithExp001() {
        val page = ExportPlanFixtures.page(
            ops = listOf(
                // 2 × 14.4 pt lines do not fit the 20 pt field (17 pt available).
                ExportPlanFixtures.textOp(lines = listOf("Zeile1", "Zeile2")),
            ),
        )
        val findings = ExportPlanValidator.findings(parse(page), metrics)
        assertEquals("EXP-001", findings.single().code)
        assertEquals("too_many_lines", findings.single().reason)
    }

    @Test
    fun tooWideLineBlocksWithExp001() {
        val page = ExportPlanFixtures.page(
            ops = listOf(
                // 20 characters × 0.6 em × 12 pt = 144 pt in a 40 pt wide field.
                ExportPlanFixtures.textOp(
                    rect = ExportPlanFixtures.rect(50.0, 100.0, 40.0, 20.0),
                    lines = listOf("Müller-Lüdenscheidt1"),
                ),
            ),
        )
        val findings = ExportPlanValidator.findings(parse(page), metrics)
        assertEquals("EXP-001", findings.single().code)
        assertEquals("too_wide", findings.single().reason)
    }

    @Test
    fun missingGlyphBlocksWithExp004() {
        val page = ExportPlanFixtures.page(
            ops = listOf(ExportPlanFixtures.textOp(lines = listOf("Wert \u20AC"))),
        )
        // A font without the euro sign must block instead of substituting.
        val findings = ExportPlanValidator.findings(
            parse(page),
            FakeFontMetrics(FakeFontMetrics.DEFAULT_COVERED - '\u20AC'),
        )
        assertEquals("EXP-004", findings.single().code)
        assertEquals("glyph_missing", findings.single().reason)
    }

    @Test
    fun germanCharactersPassWithTheBundledCoverage() {
        val page = ExportPlanFixtures.page(
            ops = listOf(ExportPlanFixtures.textOp(lines = listOf("Grüße, Müller & Söhne \u20AC"))),
        )
        assertTrue(ExportPlanValidator.findings(parse(page), metrics).isEmpty())
    }

    @Test
    fun failureAggregatesTheAffectedFieldCount() {
        val page = ExportPlanFixtures.page(
            ops = listOf(
                ExportPlanFixtures.textOp(fieldId = "f1", overflow = true),
                ExportPlanFixtures.textOp(fieldId = "f2", overflow = true),
            ),
        )
        val failure = exportPlanFailure(ExportPlanValidator.findings(parse(page), metrics))
        assertEquals("EXP-001", failure?.code)
        assertEquals(2, failure?.details()?.get("fieldCount"))
        assertEquals("exportBlocked", failure?.details()?.get("category"))
    }

    @Test
    fun failureCodesMapToTheirCatalogEntries() {
        assertEquals("exportBlocked", exportFailure("EXP-001").details()["category"])
        assertEquals("exportFailed", exportFailure("EXP-002").details()["category"])
        assertEquals("geometryInvalid", exportFailure("EXP-003").details()["category"])
        assertEquals("missingGlyph", exportFailure("EXP-004").details()["category"])
        assertEquals("sourceUnreadable", exportFailure("EXP-005").details()["category"])
        assertEquals("pageNotCopiable", exportFailure("EXP-006").details()["category"])
        assertEquals("storageFull", exportFailure("SAVE-001").details()["category"])
    }

    private fun parse(vararg pages: Map<String, Any?>): ExportPlan =
        ExportPlanParser.parse(ExportPlanFixtures.plan(pages = pages.toList()))
}
