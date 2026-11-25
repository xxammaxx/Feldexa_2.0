package de.feldexa.app.export

/**
 * T104 host-JVM fixtures: canonical export-plan JSON maps.
 *
 * The shapes are the ones `packages/feldexa_export` serializes
 * (`contracts/export-plan.md` §2). Nothing here touches the filesystem, PDFBox,
 * or Android; the tests build the same map the platform channel would deliver.
 */
internal object ExportPlanFixtures {

    const val DOCUMENT_ID = "1b4e28ba-2fa1-4d3b-a1f8-6f2a3c4d5e6f"
    const val REVISION_ID = "9c858901-8a57-4791-81fe-4c455b099bc9"
    const val SOURCE_SHA256 = "0f343b0931126a20f133d67c2b018a3c1a4d9a7b6f4f9d2f6a0b8c1d2e3f4051"
    const val FONT_ASSET = "assets/fonts/NotoSans-Regular.ttf"
    const val SIGNATURE_ASSET = "d2a1b3c4-1234-4abc-8def-0123456789ab"

    const val PAGE_WIDTH = 595.28
    const val PAGE_HEIGHT = 841.89

    fun rect(x: Double, y: Double, width: Double, height: Double): Map<String, Any?> = linkedMapOf(
        "x" to x,
        "y" to y,
        "width" to width,
        "height" to height,
    )

    fun ctm(a: Double, b: Double, c: Double, d: Double, e: Double, f: Double): Map<String, Any?> =
        linkedMapOf("a" to a, "b" to b, "c" to c, "d" to d, "e" to e, "f" to f)

    /** The normative display→PDF matrix for [rotation] (`coordinates-and-geometry.md` §5). */
    fun expectedCtm(
        rotation: Int,
        crop: Map<String, Any?> = rect(0.0, 0.0, PAGE_WIDTH, PAGE_HEIGHT),
    ): Map<String, Any?> {
        val cx0 = crop.getValue("x") as Double
        val cy0 = crop.getValue("y") as Double
        val cx1 = cx0 + (crop.getValue("width") as Double)
        val cy1 = cy0 + (crop.getValue("height") as Double)
        return when (rotation) {
            0 -> ctm(1.0, 0.0, 0.0, -1.0, cx0, cy1)
            90 -> ctm(0.0, 1.0, 1.0, 0.0, cx0, cy0)
            180 -> ctm(-1.0, 0.0, 0.0, -1.0, cx1, cy0)
            else -> ctm(0.0, -1.0, -1.0, 0.0, cx1, cy1)
        }
    }

    fun displaySize(rotation: Int, crop: Map<String, Any?> = rect(0.0, 0.0, PAGE_WIDTH, PAGE_HEIGHT)): Map<String, Any?> {
        val width = crop.getValue("width") as Double
        val height = crop.getValue("height") as Double
        return linkedMapOf(
            "width" to if (rotation == 90 || rotation == 270) height else width,
            "height" to if (rotation == 90 || rotation == 270) width else height,
        )
    }

    fun page(
        index: Int = 0,
        rotation: Int = 0,
        crop: Map<String, Any?> = rect(0.0, 0.0, PAGE_WIDTH, PAGE_HEIGHT),
        ops: List<Map<String, Any?>> = emptyList(),
        ctm: Map<String, Any?> = expectedCtm(rotation, crop),
        displaySize: Map<String, Any?> = displaySize(rotation, crop),
    ): Map<String, Any?> = linkedMapOf(
        "index" to index,
        "rotation" to rotation,
        "mediaBox" to crop,
        "cropBox" to crop,
        "displaySize" to displaySize,
        "ctm" to ctm,
        "ops" to ops,
    )

    /**
     * A text op that passes every §2.2/§3.1 rule: 20 pt high field, 12 pt font,
     * 14.4 pt line height, 11.1 pt baseline, one short line.
     */
    fun textOp(
        fieldId: String = "f1",
        provenance: String = "machine",
        rect: Map<String, Any?> = rect(50.0, 100.0, 200.0, 20.0),
        pdfRect: Map<String, Any?> = rect(50.0, 721.89, 200.0, 20.0),
        fontSizePt: Double = 12.0,
        lineHeightPt: Double = 14.4,
        baselineFromTopPt: Double = 11.1,
        lines: List<String> = listOf("Müller-Lüdenscheidt"),
        overflow: Boolean = false,
    ): Map<String, Any?> = linkedMapOf(
        "op" to "text",
        "fieldId" to fieldId,
        "provenance" to provenance,
        "rect" to rect,
        "pdfRect" to pdfRect,
        "fontSizePt" to fontSizePt,
        "lineHeightPt" to lineHeightPt,
        "baselineFromTopPt" to baselineFromTopPt,
        "color" to "#000000",
        "lines" to lines,
        "overflow" to overflow,
    )

    fun checkboxOp(
        fieldId: String = "f2",
        checked: Boolean = true,
        rect: Map<String, Any?> = rect(420.0, 210.0, 12.0, 12.0),
        pdfRect: Map<String, Any?> = rect(420.0, 619.89, 12.0, 12.0),
    ): Map<String, Any?> = linkedMapOf(
        "op" to "checkbox",
        "fieldId" to fieldId,
        "provenance" to "user",
        "rect" to rect,
        "pdfRect" to pdfRect,
        "checked" to checked,
        "insetPt" to 1.8,
        "strokeWidthPt" to 0.9,
    )

    fun imageOp(
        fieldId: String = "f3",
        rect: Map<String, Any?> = rect(320.0, 720.0, 180.0, 50.0),
        pdfRect: Map<String, Any?> = rect(320.0, 71.89, 180.0, 50.0),
        assetId: String = SIGNATURE_ASSET,
    ): Map<String, Any?> = linkedMapOf(
        "op" to "image",
        "fieldId" to fieldId,
        "provenance" to "template",
        "rect" to rect,
        "pdfRect" to pdfRect,
        "assetId" to assetId,
        "fit" to "contain",
        "align" to "center",
    )

    fun plan(
        pages: List<Map<String, Any?>> = listOf(page(ops = listOf(textOp()))),
        pageCount: Int = pages.size,
        documentId: String = DOCUMENT_ID,
        revisionId: String = REVISION_ID,
        sourceSha256: String = SOURCE_SHA256,
        fontAsset: String = FONT_ASSET,
    ): Map<String, Any?> = linkedMapOf(
        "schemaVersion" to 1,
        "documentId" to documentId,
        "revisionId" to revisionId,
        "sourceSha256" to sourceSha256,
        "pageCount" to pageCount,
        "evidenceClass" to "emulator",
        "font" to linkedMapOf(
            "family" to "NotoSans",
            "regularAsset" to fontAsset,
            "boldAsset" to "assets/fonts/NotoSans-Bold.ttf",
            "metricsVersion" to "noto-sans-2.013-v1",
        ),
        "pages" to pages,
        "warnings" to emptyList<String>(),
        "info" to linkedMapOf("emptyFieldCount" to 0, "unresolvedSuggestionCount" to 0),
    )
}

/**
 * Deterministic fake metrics: every glyph of [covered] is available and one
 * character advances 0.6 em, which is close enough to Noto Sans for the
 * overflow arithmetic in the tests.
 */
internal class FakeFontMetrics(
    private val covered: Set<Char> = DEFAULT_COVERED,
) : ExportFontMetrics {

    override fun coversGlyphs(text: String): Boolean = text.all { it in covered }

    override fun advanceWidthPt(text: String, fontSizePt: Double): Double =
        text.length * 0.6 * fontSizePt

    companion object {
        /** ASCII plus the German characters of `export-plan.md` §3.1. */
        val DEFAULT_COVERED: Set<Char> =
            ((32..126).map { it.toChar() } + listOf('ä', 'ö', 'ü', 'Ä', 'Ö', 'Ü', 'ß', '€', '„', '“', '’', '–')).toSet()
    }
}
