package de.feldexa.app.export

import de.feldexa.app.PlatformFailure

/**
 * T104: the canonical export plan as the Android applier reads it.
 *
 * Normative source: `contracts/export-plan.md` §2 (schema v1) and
 * `contracts/coordinates-and-geometry.md` §5 (display→PDF matrix). The Dart
 * `packages/feldexa_export` model owns the plan; this file is the read-only
 * Android view of the same JSON. The applier makes **no** layout decisions:
 * it consumes `rect`, `pdfRect`, font sizes, baselines, checkbox insets, and
 * signature fit exactly as the shared builder produced them.
 *
 * Everything here is plain JVM Kotlin: no Android type, no PDFBox type, no
 * I/O. That keeps plan parsing and the geometry/overflow checks unit-testable
 * without an emulator (T104 acceptance) and keeps the PDFBox applier in
 * `PdfExportService` the only place that touches document bytes.
 */
data class ExportRect(
    val x: Double,
    val y: Double,
    val width: Double,
    val height: Double,
) {
    val right: Double get() = x + width
    val bottom: Double get() = y + height

    fun isFinite(): Boolean =
        x.isFinite() && y.isFinite() && width.isFinite() && height.isFinite()

    /** True when this rectangle lies inside [other] within [tolerance] points. */
    fun isInside(other: ExportRect, tolerance: Double): Boolean =
        x >= other.x - tolerance &&
            y >= other.y - tolerance &&
            right <= other.right + tolerance &&
            bottom <= other.bottom + tolerance
}

/** Display→PDF affine matrix: `u = a·x + c·y + e`, `v = b·x + d·y + f`. */
data class ExportCtm(
    val a: Double,
    val b: Double,
    val c: Double,
    val d: Double,
    val e: Double,
    val f: Double,
) {
    fun isFinite(): Boolean =
        a.isFinite() && b.isFinite() && c.isFinite() && d.isFinite() &&
            e.isFinite() && f.isFinite()

    /**
     * Coefficient comparison with the `contracts/export-plan.md` §6 tolerance.
     * The applier recomputes the matrix from the page geometry and rejects a
     * plan whose `ctm` differs by more than 0.01 (`platform-channel.md` §6).
     */
    fun matches(other: ExportCtm, tolerance: Double = ExportPlanParser.GEOMETRY_TOLERANCE_PT): Boolean =
        closeEnough(a, other.a, tolerance) &&
            closeEnough(b, other.b, tolerance) &&
            closeEnough(c, other.c, tolerance) &&
            closeEnough(d, other.d, tolerance) &&
            closeEnough(e, other.e, tolerance) &&
            closeEnough(f, other.f, tolerance)
}

/**
 * Stored page geometry from preflight: MediaBox, effective CropBox, `/Rotate`.
 *
 * The display box is derived, never read from the plan (`export-plan.md` §2.1;
 * `coordinates-and-geometry.md` §5): rotations 0/180 keep the crop size,
 * 90/270 swap it.
 */
data class ExportPageGeometry(
    val mediaBox: ExportRect,
    val cropBox: ExportRect,
    val rotation: Int,
) {
    val displayWidth: Double
        get() = if (rotation == 90 || rotation == 270) cropBox.height else cropBox.width

    val displayHeight: Double
        get() = if (rotation == 90 || rotation == 270) cropBox.width else cropBox.height

    /** `[0, 0, displayWidth, displayHeight]`. */
    val displayBox: ExportRect
        get() = ExportRect(0.0, 0.0, displayWidth, displayHeight)

    /** The normative display→PDF matrix for this geometry (`coordinates-and-geometry.md` §5). */
    fun expectedCtm(): ExportCtm {
        val cx0 = cropBox.x
        val cy0 = cropBox.y
        val cx1 = cropBox.right
        val cy1 = cropBox.bottom
        return when (rotation) {
            0 -> ExportCtm(a = 1.0, b = 0.0, c = 0.0, d = -1.0, e = cx0, f = cy1)
            90 -> ExportCtm(a = 0.0, b = 1.0, c = 1.0, d = 0.0, e = cx0, f = cy0)
            180 -> ExportCtm(a = -1.0, b = 0.0, c = 0.0, d = -1.0, e = cx1, f = cy0)
            270 -> ExportCtm(a = 0.0, b = -1.0, c = -1.0, d = 0.0, e = cx1, f = cy1)
            else -> throw IllegalArgumentException("unsupported rotation")
        }
    }
}

/** The T018 provenance vocabulary (`machine | user | template`). Never drawn. */
enum class ExportProvenance(val wireValue: String) {
    MACHINE("machine"),
    USER("user"),
    TEMPLATE("template"),
    ;

    companion object {
        fun fromWire(value: String?): ExportProvenance? =
            entries.firstOrNull { it.wireValue == value }
    }
}

/** One deterministic layout operation (`export-plan.md` §2.2). */
sealed interface ExportOp {
    val fieldId: String
    val provenance: ExportProvenance

    /** Display-space rectangle; drawing uses this plus the page CTM. */
    val rect: ExportRect

    /** Display rectangle mapped to PDF user space; artifact verification only. */
    val pdfRect: ExportRect
}

/** Text value operation; `lines` is already wrapped and trimmed by the builder. */
data class ExportTextOp(
    override val fieldId: String,
    override val provenance: ExportProvenance,
    override val rect: ExportRect,
    override val pdfRect: ExportRect,
    val fontSizePt: Double,
    val lineHeightPt: Double,
    val baselineFromTopPt: Double,
    val color: String,
    val lines: List<String>,
    val overflow: Boolean,
) : ExportOp

/** Checkbox mark operation; an unchecked box draws nothing (`export-plan.md` §3.2). */
data class ExportCheckboxOp(
    override val fieldId: String,
    override val provenance: ExportProvenance,
    override val rect: ExportRect,
    override val pdfRect: ExportRect,
    val checked: Boolean,
    val insetPt: Double,
    val strokeWidthPt: Double,
) : ExportOp

/** Signature-image operation; the PNG is resolved through the document's `assetId`. */
data class ExportImageOp(
    override val fieldId: String,
    override val provenance: ExportProvenance,
    override val rect: ExportRect,
    override val pdfRect: ExportRect,
    val assetId: String,
    val fit: String,
    val align: String,
) : ExportOp

/** One plan page, contiguous from index 0 (`export-plan.md` §2.1). */
data class ExportPlanPage(
    val index: Int,
    val geometry: ExportPageGeometry,
    val ctm: ExportCtm,
    val ops: List<ExportOp>,
)

/** The canonical v1 export plan. */
data class ExportPlan(
    val schemaVersion: Int,
    val documentId: String,
    val revisionId: String,
    val sourceSha256: String,
    val pageCount: Int,
    val evidenceClass: String,
    /** Relative Flutter asset path of the bundled regular font (`assets/fonts/...`). */
    val fontAssetPath: String,
    val pages: List<ExportPlanPage>,
    val opCount: Int,
)

/**
 * Strict reader for the plan JSON that arrives as `{ "plan": {...} }`.
 *
 * Every violation is a `PLT-003` payload failure: the facade already bounded
 * the map to 8 MiB (`platform-channel.md` §10), and a plan that does not match
 * schema v1 is a version-drift defect, not a document problem. Nothing here
 * echoes a field value, a label, or a coordinate into the failure.
 */
object ExportPlanParser {
    /** `platform-channel.md` §10: at most 100 pages and 500 ops per page. */
    const val MAX_PAGE_COUNT = 100
    const val MAX_OPS_PER_PAGE = 500

    /** `export-plan.md` §6 geometry tolerance. */
    const val GEOMETRY_TOLERANCE_PT = 0.01

    private const val SCHEMA_VERSION = 1

    private val UUID_V4 = Regex(
        "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    )
    private val SHA256 = Regex("^[0-9a-f]{64}$")
    private val EVIDENCE_CLASSES = setOf("simulated", "emulator", "device", "none")

    fun parse(plan: Map<String, Any?>): ExportPlan {
        val schemaVersion = requireInt(plan, "schemaVersion")
        if (schemaVersion != SCHEMA_VERSION) throw invalid("platform.schemaVersionUnsupported")
        val documentId = requireString(plan, "documentId")
        if (!UUID_V4.matches(documentId)) throw PlatformFailure.invalidIdentifier()
        val revisionId = requireString(plan, "revisionId")
        if (!UUID_V4.matches(revisionId)) throw PlatformFailure.invalidIdentifier()
        val sourceSha256 = requireString(plan, "sourceSha256")
        if (!SHA256.matches(sourceSha256)) throw invalid("platform.invalidHash")
        val pageCount = requireInt(plan, "pageCount")
        if (pageCount < 1 || pageCount > MAX_PAGE_COUNT) throw invalid("platform.valueOutOfRange")
        val evidenceClass = requireString(plan, "evidenceClass")
        if (evidenceClass !in EVIDENCE_CLASSES) throw invalid("platform.invalidEnum")
        val fontAssetPath = parseFontAssetPath(requireMap(plan, "font"))

        val rawPages = plan["pages"] as? List<*>
            ?: throw invalid("platform.missingField")
        if (rawPages.size != pageCount) throw invalid("platform.valueOutOfRange")
        val pages = rawPages.mapIndexed { position, raw ->
            parsePage(position, raw)
        }
        return ExportPlan(
            schemaVersion = schemaVersion,
            documentId = documentId,
            revisionId = revisionId,
            sourceSha256 = sourceSha256,
            pageCount = pageCount,
            evidenceClass = evidenceClass,
            fontAssetPath = fontAssetPath,
            pages = pages,
            opCount = pages.sumOf { it.ops.size },
        )
    }

    private fun parseFontAssetPath(font: Map<*, *>): String {
        val regular = font["regularAsset"] as? String
            ?: throw invalid("platform.missingField")
        // `export-plan.md` §2: asset paths are relative repo paths. An absolute
        // path or URI would leak a host location into the plan.
        if (regular.isEmpty() ||
            regular.startsWith("/") ||
            regular.contains("://") ||
            regular.contains("..")
        ) {
            throw invalid("platform.invalidString")
        }
        return regular
    }

    private fun parsePage(position: Int, raw: Any?): ExportPlanPage {
        val page = raw as? Map<*, *> ?: throw invalid("platform.invalidMap")
        val index = requireInt(page, "index")
        if (index != position) throw invalid("platform.valueOutOfRange")
        val rotation = requireInt(page, "rotation")
        if (rotation != 0 && rotation != 90 && rotation != 180 && rotation != 270) {
            throw invalid("platform.valueOutOfRange")
        }
        val mediaBox = parseRect(requireMap(page, "mediaBox"))
        val cropBox = parseRect(requireMap(page, "cropBox"))
        if (cropBox.width <= 0.0 || cropBox.height <= 0.0) throw invalid("platform.valueOutOfRange")
        val geometry = ExportPageGeometry(mediaBox = mediaBox, cropBox = cropBox, rotation = rotation)
        val displaySize = requireMap(page, "displaySize")
        if (!closeEnough(requireDouble(displaySize, "width"), geometry.displayWidth, GEOMETRY_TOLERANCE_PT) ||
            !closeEnough(requireDouble(displaySize, "height"), geometry.displayHeight, GEOMETRY_TOLERANCE_PT)
        ) {
            throw invalid("platform.valueOutOfRange")
        }
        val ctm = parseCtm(requireMap(page, "ctm"))
        val rawOps = page["ops"] as? List<*> ?: throw invalid("platform.missingField")
        if (rawOps.size > MAX_OPS_PER_PAGE) throw invalid("platform.valueOutOfRange")
        val ops = rawOps.map { parseOp(it) }
        // `export-plan.md` §2.1: at most one op per field per page.
        if (ops.mapTo(HashSet()) { it.fieldId }.size != ops.size) {
            throw invalid("platform.valueOutOfRange")
        }
        return ExportPlanPage(index = index, geometry = geometry, ctm = ctm, ops = ops)
    }

    private fun parseOp(raw: Any?): ExportOp {
        val op = raw as? Map<*, *> ?: throw invalid("platform.invalidMap")
        val fieldId = requireString(op, "fieldId")
        if (fieldId.isEmpty()) throw invalid("platform.invalidString")
        val provenance = ExportProvenance.fromWire(op["provenance"] as? String)
            ?: throw invalid("platform.invalidEnum")
        val rect = parseRect(requireMap(op, "rect"))
        val pdfRect = parseRect(requireMap(op, "pdfRect"))
        return when (val kind = op["op"] as? String) {
            "text" -> parseTextOp(op, fieldId, provenance, rect, pdfRect)
            "checkbox" -> parseCheckboxOp(op, fieldId, provenance, rect, pdfRect)
            "image" -> parseImageOp(op, fieldId, provenance, rect, pdfRect)
            else -> throw invalid("platform.invalidEnum")
        }
    }

    private fun parseTextOp(
        op: Map<*, *>,
        fieldId: String,
        provenance: ExportProvenance,
        rect: ExportRect,
        pdfRect: ExportRect,
    ): ExportTextOp {
        val color = requireString(op, "color")
        // `export-plan.md` §2.2: black is the only v1 color.
        if (color != "#000000") throw invalid("platform.invalidEnum")
        val rawLines = op["lines"] as? List<*> ?: throw invalid("platform.missingField")
        if (rawLines.isEmpty()) throw invalid("platform.valueOutOfRange")
        val lines = rawLines.map { line ->
            val text = line as? String ?: throw invalid("platform.invalidString")
            // `\n` is materialized into entries and trailing spaces are trimmed
            // by the builder (§3.1); a plan that still carries them is invalid.
            if (text.contains('\n') || text.any { Character.isISOControl(it) }) {
                throw invalid("platform.invalidString")
            }
            if (text.isNotEmpty() && text.last() == ' ') throw invalid("platform.invalidString")
            text
        }
        return ExportTextOp(
            fieldId = fieldId,
            provenance = provenance,
            rect = rect,
            pdfRect = pdfRect,
            fontSizePt = requireDouble(op, "fontSizePt"),
            lineHeightPt = requireDouble(op, "lineHeightPt"),
            baselineFromTopPt = requireDouble(op, "baselineFromTopPt"),
            color = color,
            lines = lines,
            overflow = requireBool(op, "overflow"),
        )
    }

    private fun parseCheckboxOp(
        op: Map<*, *>,
        fieldId: String,
        provenance: ExportProvenance,
        rect: ExportRect,
        pdfRect: ExportRect,
    ): ExportCheckboxOp = ExportCheckboxOp(
        fieldId = fieldId,
        provenance = provenance,
        rect = rect,
        pdfRect = pdfRect,
        checked = requireBool(op, "checked"),
        insetPt = requireDouble(op, "insetPt"),
        strokeWidthPt = requireDouble(op, "strokeWidthPt"),
    )

    private fun parseImageOp(
        op: Map<*, *>,
        fieldId: String,
        provenance: ExportProvenance,
        rect: ExportRect,
        pdfRect: ExportRect,
    ): ExportImageOp {
        val assetId = requireString(op, "assetId")
        if (assetId.isEmpty()) throw invalid("platform.invalidString")
        val fit = requireString(op, "fit")
        if (fit != "contain") throw invalid("platform.invalidEnum")
        val align = requireString(op, "align")
        if (align != "center") throw invalid("platform.invalidEnum")
        return ExportImageOp(
            fieldId = fieldId,
            provenance = provenance,
            rect = rect,
            pdfRect = pdfRect,
            assetId = assetId,
            fit = fit,
            align = align,
        )
    }

    private fun parseRect(raw: Map<*, *>): ExportRect {
        val rect = ExportRect(
            x = requireDouble(raw, "x"),
            y = requireDouble(raw, "y"),
            width = requireDouble(raw, "width"),
            height = requireDouble(raw, "height"),
        )
        if (!rect.isFinite()) throw invalid("platform.invalidNumber")
        return rect
    }

    private fun parseCtm(raw: Map<*, *>): ExportCtm {
        val ctm = ExportCtm(
            a = requireDouble(raw, "a"),
            b = requireDouble(raw, "b"),
            c = requireDouble(raw, "c"),
            d = requireDouble(raw, "d"),
            e = requireDouble(raw, "e"),
            f = requireDouble(raw, "f"),
        )
        if (!ctm.isFinite()) throw invalid("platform.invalidNumber")
        return ctm
    }

    private fun requireMap(source: Map<*, *>, name: String): Map<*, *> =
        source[name] as? Map<*, *> ?: throw invalid("platform.invalidMap")

    private fun requireString(source: Map<*, *>, name: String): String =
        source[name] as? String ?: throw invalid("platform.invalidString")

    private fun requireDouble(source: Map<*, *>, name: String): Double {
        val number = source[name] as? Number ?: throw invalid("platform.invalidNumber")
        val value = number.toDouble()
        if (!value.isFinite()) throw invalid("platform.invalidNumber")
        return value
    }

    private fun requireInt(source: Map<*, *>, name: String): Int {
        val number = source[name] as? Number ?: throw invalid("platform.invalidInteger")
        val asDouble = number.toDouble()
        if (!asDouble.isFinite() || asDouble % 1.0 != 0.0) throw invalid("platform.invalidInteger")
        if (asDouble < Int.MIN_VALUE || asDouble > Int.MAX_VALUE) throw invalid("platform.valueOutOfRange")
        return number.toInt()
    }

    private fun requireBool(source: Map<*, *>, name: String): Boolean =
        source[name] as? Boolean ?: throw invalid("platform.invalidPayload")

    private fun invalid(message: String): PlatformFailure = PlatformFailure.invalidPayload(message)
}

/** Float comparison with the plan tolerance. */
internal fun closeEnough(left: Double, right: Double, tolerance: Double): Boolean =
    kotlin.math.abs(left - right) <= tolerance
