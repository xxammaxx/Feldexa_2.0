package de.feldexa.app.export

import de.feldexa.app.PlatformFailure
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T104 host-JVM tests for the export-plan reader (`contracts/export-plan.md` §2).
 *
 * Evidence class `NONE`: no Android runtime, no PDF bytes, no emulator. These
 * tests prove the applier refuses a plan that the shared builder could not
 * legitimately produce, and that a canonical plan is read exactly as sent.
 */
class ExportPlanModelTest {

    @Test
    fun readsCanonicalPlanIncludingGeometryAndOps() {
        val plan = ExportPlanParser.parse(
            ExportPlanFixtures.plan(
                pages = listOf(
                    ExportPlanFixtures.page(
                        index = 0,
                        ops = listOf(
                            ExportPlanFixtures.textOp(),
                            ExportPlanFixtures.checkboxOp(),
                            ExportPlanFixtures.imageOp(),
                        ),
                    ),
                ),
            ),
        )

        assertEquals(ExportPlanFixtures.DOCUMENT_ID, plan.documentId)
        assertEquals(ExportPlanFixtures.REVISION_ID, plan.revisionId)
        assertEquals(ExportPlanFixtures.SOURCE_SHA256, plan.sourceSha256)
        assertEquals(1, plan.pageCount)
        assertEquals(3, plan.opCount)
        assertEquals(ExportPlanFixtures.FONT_ASSET, plan.fontAssetPath)
        assertEquals(0, plan.pages.single().geometry.rotation)
        assertTrue(plan.pages.single().ctm.matches(plan.pages.single().geometry.expectedCtm()))
        assertEquals(595.28, plan.pages.single().geometry.displayWidth, 0.0001)
        assertEquals(841.89, plan.pages.single().geometry.displayHeight, 0.0001)
        val text = plan.pages.single().ops.first() as ExportTextOp
        assertEquals(listOf("Müller-Lüdenscheidt"), text.lines)
        assertEquals(ExportProvenance.MACHINE, text.provenance)
        assertEquals(ExportProvenance.USER, (plan.pages.single().ops[1] as ExportCheckboxOp).provenance)
        assertEquals(ExportProvenance.TEMPLATE, (plan.pages.single().ops[2] as ExportImageOp).provenance)
    }

    @Test
    fun swapsDisplaySizeForQuarterTurnRotations() {
        val page = ExportPlanParser.parse(ExportPlanFixtures.plan()).pages.single()
        assertEquals(595.28, page.geometry.displayWidth, 0.0001)

        val rotated = ExportPlanParser.parse(
            ExportPlanFixtures.plan(
                pages = listOf(ExportPlanFixtures.page(index = 0, rotation = 90)),
            ),
        ).pages.single()
        assertEquals(841.89, rotated.geometry.displayWidth, 0.0001)
        assertEquals(595.28, rotated.geometry.displayHeight, 0.0001)
    }

    @Test
    fun rejectsPageCountThatDoesNotMatchThePageList() {
        val failure = assertThrows(PlatformFailure::class.java) {
            ExportPlanParser.parse(ExportPlanFixtures.plan(pageCount = 2))
        }
        assertEquals("PLT-003", failure.code)
    }

    @Test
    fun rejectsNonContiguousPageIndexes() {
        assertThrows(PlatformFailure::class.java) {
            ExportPlanParser.parse(
                ExportPlanFixtures.plan(
                    pages = listOf(
                        ExportPlanFixtures.page(index = 1),
                    ),
                ),
            )
        }
    }

    @Test
    fun rejectsDisplaySizeThatContradictsTheRotation() {
        val crop = ExportPlanFixtures.rect(0.0, 0.0, ExportPlanFixtures.PAGE_WIDTH, ExportPlanFixtures.PAGE_HEIGHT)
        assertThrows(PlatformFailure::class.java) {
            ExportPlanParser.parse(
                ExportPlanFixtures.plan(
                    pages = listOf(
                        ExportPlanFixtures.page(
                            rotation = 90,
                            crop = crop,
                            displaySize = linkedMapOf(
                                "width" to ExportPlanFixtures.PAGE_WIDTH,
                                "height" to ExportPlanFixtures.PAGE_HEIGHT,
                            ),
                        ),
                    ),
                ),
            )
        }
    }

    @Test
    fun rejectsUnknownOpDiscriminator() {
        val op = ExportPlanFixtures.textOp().toMutableMap()
        op["op"] = "stamp"
        val failure = assertThrows(PlatformFailure::class.java) {
            ExportPlanParser.parse(
                ExportPlanFixtures.plan(
                    pages = listOf(ExportPlanFixtures.page(ops = listOf(op))),
                ),
            )
        }
        assertEquals("platform.invalidEnum", failure.machineMessage)
    }

    @Test
    fun rejectsTwoOpsForTheSameFieldOnOnePage() {
        assertThrows(PlatformFailure::class.java) {
            ExportPlanParser.parse(
                ExportPlanFixtures.plan(
                    pages = listOf(
                        ExportPlanFixtures.page(
                            ops = listOf(
                                ExportPlanFixtures.textOp(fieldId = "f1"),
                                ExportPlanFixtures.checkboxOp(fieldId = "f1"),
                            ),
                        ),
                    ),
                ),
            )
        }
    }

    @Test
    fun rejectsMaterializedNewlinesAndTrailingSpaces() {
        assertThrows(PlatformFailure::class.java) {
            ExportPlanParser.parse(
                ExportPlanFixtures.plan(
                    pages = listOf(
                        ExportPlanFixtures.page(
                            ops = listOf(ExportPlanFixtures.textOp(lines = listOf("Zeile1\nZeile2"))),
                        ),
                    ),
                ),
            )
        }
        assertThrows(PlatformFailure::class.java) {
            ExportPlanParser.parse(
                ExportPlanFixtures.plan(
                    pages = listOf(
                        ExportPlanFixtures.page(
                            ops = listOf(ExportPlanFixtures.textOp(lines = listOf("Wert "))),
                        ),
                    ),
                ),
            )
        }
    }

    @Test
    fun rejectsIdentifiersAndHashesThatAreNotCanonical() {
        val badDocument = assertThrows(PlatformFailure::class.java) {
            ExportPlanParser.parse(ExportPlanFixtures.plan(documentId = "not-a-uuid"))
        }
        assertEquals("PLT-002", badDocument.code)
        assertEquals("platform.identifier", badDocument.machineMessage)

        val badHash = assertThrows(PlatformFailure::class.java) {
            ExportPlanParser.parse(ExportPlanFixtures.plan(sourceSha256 = "ABC"))
        }
        assertEquals("platform.invalidHash", badHash.machineMessage)
    }

    @Test
    fun rejectsMoreThanFiveHundredOpsPerPage() {
        val ops = (1..ExportPlanParser.MAX_OPS_PER_PAGE + 1).map {
            ExportPlanFixtures.textOp(fieldId = "f$it")
        }
        assertThrows(PlatformFailure::class.java) {
            ExportPlanParser.parse(
                ExportPlanFixtures.plan(pages = listOf(ExportPlanFixtures.page(ops = ops))),
            )
        }
    }

    @Test
    fun rejectsAbsoluteOrUriFontAssetPaths() {
        for (asset in listOf("/system/fonts/NotoSans.ttf", "file:///tmp/NotoSans.ttf", "../fonts/x.ttf")) {
            val failure = assertThrows(PlatformFailure::class.java) {
                ExportPlanParser.parse(ExportPlanFixtures.plan(fontAsset = asset))
            }
            assertEquals("platform.invalidString", failure.machineMessage)
        }
    }

    @Test
    fun rejectsUnknownProvenanceAndImageContract() {
        assertThrows(PlatformFailure::class.java) {
            ExportPlanParser.parse(
                ExportPlanFixtures.plan(
                    pages = listOf(
                        ExportPlanFixtures.page(
                            ops = listOf(ExportPlanFixtures.textOp(provenance = "guessed")),
                        ),
                    ),
                ),
            )
        }
        val image = ExportPlanFixtures.imageOp().toMutableMap()
        image["fit"] = "cover"
        assertThrows(PlatformFailure::class.java) {
            ExportPlanParser.parse(
                ExportPlanFixtures.plan(pages = listOf(ExportPlanFixtures.page(ops = listOf(image)))),
            )
        }
    }

    @Test
    fun rejectsWrongSchemaVersion() {
        val plan = ExportPlanFixtures.plan().toMutableMap()
        plan["schemaVersion"] = 2
        val failure = assertThrows(PlatformFailure::class.java) { ExportPlanParser.parse(plan) }
        assertEquals("platform.schemaVersionUnsupported", failure.machineMessage)
        assertNotEquals("PLT-002", failure.code)
    }
}
