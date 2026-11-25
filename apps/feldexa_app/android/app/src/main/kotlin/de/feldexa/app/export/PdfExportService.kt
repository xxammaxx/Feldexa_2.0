package de.feldexa.app.export

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.tom_roush.pdfbox.multipdf.PDFMergerUtility
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDDocumentCatalog
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.common.PDMetadata
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import com.tom_roush.pdfbox.pdmodel.font.PDFont
import com.tom_roush.pdfbox.pdmodel.font.PDType0Font
import com.tom_roush.pdfbox.pdmodel.graphics.image.LosslessFactory
import com.tom_roush.pdfbox.pdmodel.graphics.image.PDImageXObject
import com.tom_roush.pdfbox.pdmodel.interactive.annotation.PDAnnotationWidget
import com.tom_roush.pdfbox.text.PDFTextStripper
import com.tom_roush.pdfbox.util.Matrix
import de.feldexa.app.OperationContext
import de.feldexa.app.PlatformFailure
import de.feldexa.app.PlatformRequest
import de.feldexa.app.PlatformService
import de.feldexa.app.storage.CorruptDataException
import de.feldexa.app.storage.KeyUnavailableException
import de.feldexa.app.storage.KeystoreUnavailableException
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.UUID

/**
 * T104: the PDFBox export applier for the `export` method prefix.
 *
 * Normative sources:
 *  - `contracts/export-plan.md` §5 (the ten applier steps) and §6 (the
 *    verification contract);
 *  - `contracts/platform-channel.md` §6 (`export.*` methods, progress phases,
 *    terminal codes) and §9 (cancellation, artifact deletion on detach);
 *  - `contracts/error-catalog.de.md` §4 (`EXP-001`…`EXP-006`, `SAVE-001`).
 *
 * What this class does, in the order of §5:
 *  1. load the stored source, assert page count and that it is not encrypted;
 *  2. flatten a pre-existing AcroForm in memory on the working copy, then
 *     import every source page unmodified through `PDFMergerUtility` (never
 *     rasterised, re-flowed, or rebuilt);
 *  3. remove residual field dictionaries and widget annotations and assert the
 *     output has no AcroForm (FR-069);
 *  4. embed Noto Sans Regular once, subsetted;
 *  5. append one overlay content stream per page under the display CTM, drawing
 *     the plan's ops in plan order (text, checkbox vector X, signature PNG);
 *  6. replace the source metadata: only `Producer`/`Creator` stay, plus a
 *     content-free XMP provenance record;
 *  7. write `cacheDir/feldexa_exports/<artifactId>.pdf.tmp`;
 *  8. reopen and verify page count, boxes, rotation, no interactive fields,
 *     extracted text (including German characters), the overlay bounds against
 *     the artifact's own page box, and that every planned glyph is encodable by
 *     the fonts the artifact references;
 *  9. atomically rename to `<artifactId>.pdf`;
 * 10. on any failure delete the temp file and the renamed file and fail with
 *     `EXP-002` — a failed export never leaves a `.pdf` behind and never
 *     touches the source.
 *
 * The stored source is proven unchanged exactly once, before the first write,
 * by comparing its SHA-256 with `plan.sourceSha256` (FR-073); the applier only
 * ever reads those bytes.
 *
 * Content rules: no failure carries a value, label, field id, path, or URI, and
 * this class performs no logging. Only the explicitly requested
 * `export.readArtifact` byte array leaves the facade.
 *
 * The plan decisions are not repeated here: `ExportPlanParser`,
 * `ExportPlanValidator`, and `ExportFontMetrics` own parsing and the blocking
 * checks so they stay unit-testable without an Android runtime.
 */
class PdfExportService(
    private val content: ExportContentSource,
    private val artifacts: ExportArtifactStore,
    private val regularFont: RegularFontSource,
    private val clock: () -> Long = System::currentTimeMillis,
    private val idGenerator: () -> String = { UUID.randomUUID().toString() },
) : PlatformService {

    override fun handle(request: PlatformRequest, context: OperationContext): Any? = when (request.method) {
        "export.validate" -> validate(request)
        "export.render" -> render(request, context)
        "export.readArtifact" -> artifacts.read(requireArtifactId(request.string("artifactId")))
        "export.deleteArtifact" -> deleteArtifact(request)
        else -> throw PlatformFailure.unsupported()
    }

    /**
     * `platform-channel.md` §9: engine detach deletes the session's export
     * artifacts. Durable documents, revisions, and sources are untouched.
     */
    override fun onFacadeDetached() {
        artifacts.deleteAll()
    }

    // ------------------------------------------------------------------
    // export.validate
    // ------------------------------------------------------------------

    /**
     * Re-runs the applier's own checks before anything is written (FR-068).
     *
     * `contracts/export-plan.md` §4 lists only *blocking* codes, so a plan that
     * fails a check is reported as its catalog code (`EXP-001`/`003`/`004`)
     * instead of a non-blocking warning list. A clean plan returns
     * `{ ok: true, warnings: [] }`.
     */
    private fun validate(request: PlatformRequest): Map<String, Any?> {
        val plan = ExportPlanParser.parse(requirePlan(request))
        exportPlanFailure(planFindings(plan))?.let { throw it }
        return linkedMapOf(
            "ok" to true,
            "warnings" to emptyList<Any?>(),
        )
    }

    private fun planFindings(plan: ExportPlan): List<ExportValidationFinding> {
        if (plan.fontAssetPath != EXPECTED_REGULAR_ASSET) {
            // The applier only ships the contract's regular font (`export-plan.md` §2).
            throw PlatformFailure.invalidPayload("platform.invalidEnum")
        }
        val fontBytes = readFontBytes()
        return PDDocument().use { scratch ->
            val font = PDType0Font.load(scratch, fontBytes.inputStream(), true)
            ExportPlanValidator.findings(plan, PdfBoxFontMetrics(font))
        }
    }

    // ------------------------------------------------------------------
    // export.render
    // ------------------------------------------------------------------

    private fun render(request: PlatformRequest, context: OperationContext): Map<String, Any?> {
        val plan = ExportPlanParser.parse(requirePlan(request))
        // FR-068: no write, no temp file, and no progress before the plan is
        // proven applicable.
        exportPlanFailure(planFindings(plan))?.let { throw it }

        report(context, PHASE_IMPORTING, 0.0)
        val source = readSource(plan)
        if (sha256Hex(source) != plan.sourceSha256) {
            // `export-plan.md` §4: the stored source is not the planned source.
            throw exportFailure("EXP-005")
        }

        artifacts.ensureDirectory()
        requireFreeSpace(source.size.toLong())

        val artifactId = idGenerator()
        if (!ExportArtifactStore.UUID_V4.matches(artifactId)) throw PlatformFailure.internal()
        val finalFile = artifacts.artifactFile(artifactId)
        val temporaryFile = artifacts.temporaryFile(artifactId)
        var published = false
        try {
            writeDocument(plan, source, temporaryFile, context)

            report(context, PHASE_VERIFYING, 0.85)
            val verification = verifyArtifact(temporaryFile, plan)

            // The last cancellation checkpoint precedes the rename, so a
            // cancelled run cannot leave a final artifact behind (§9).
            context.checkCancelled()
            report(context, PHASE_FINALIZING, 0.95)
            renameAtomically(temporaryFile, finalFile)
            // A cancellation that lands between the rename and the publication
            // must not publish either; the `finally` below removes the renamed
            // file because `published` is still false.
            context.checkCancelled()
            val byteSize = finalFile.length()
            if (byteSize < 1L) throw exportFailure("EXP-002")
            val sha256 = sha256Hex(finalFile)
            artifacts.publish(
                ExportArtifactStore.ArtifactRecord(
                    artifactId = artifactId,
                    file = finalFile,
                    byteSize = byteSize,
                    sha256 = sha256,
                    pageCount = plan.pageCount,
                ),
            )
            // Only a published artifact is kept: everything before this point
            // fails or cancels without leaving a document behind.
            published = true
            return linkedMapOf(
                "artifactId" to artifactId,
                "pageCount" to plan.pageCount,
                "byteSize" to byteSize,
                "sha256" to sha256,
                "verification" to verification,
            )
        } catch (failure: PlatformFailure) {
            throw failure
        } catch (failure: KeyUnavailableException) {
            throw PlatformFailure("SAVE-002", "keyUnavailable", false, "save.keyUnavailable")
        } catch (failure: KeystoreUnavailableException) {
            throw PlatformFailure(
                "SAVE-008", "keystoreUnavailable", failure.retryable, "save.keystoreUnavailable",
            )
        } catch (failure: IOException) {
            throw exportFailure("EXP-002")
        } catch (failure: Exception) {
            throw exportFailure("EXP-002")
        } finally {
            if (!published) {
                // §5.10 / §6 "Artifact isolation": a failed or cancelled run
                // leaves neither the temp file nor a file that already passed
                // the atomic rename behind.
                runCatching { temporaryFile.delete() }
                runCatching { finalFile.delete() }
            }
        }
    }

    /** §5 steps 1–7. */
    private fun writeDocument(
        plan: ExportPlan,
        source: ByteArray,
        temporaryFile: File,
        context: OperationContext,
    ) {
        PDDocument.load(source).use { sourceDocument ->
            if (sourceDocument.isEncrypted) throw exportFailure("EXP-005")
            if (sourceDocument.numberOfPages != plan.pageCount) {
                throw exportFailure(
                    "EXP-006",
                    pageIndex = firstUncopiablePageIndex(plan, sourceDocument.numberOfPages),
                )
            }
            flattenSourceAcroForm(sourceDocument)
            report(context, PHASE_IMPORTING, 0.1)

            PDDocument().use { output ->
                // §5 step 2: copy pages, resources, and content streams without
                // re-rendering; the stored source bytes are never modified.
                PDFMergerUtility().appendDocument(output, sourceDocument)
                if (output.numberOfPages != plan.pageCount) {
                    throw exportFailure(
                        "EXP-006",
                        pageIndex = firstUncopiablePageIndex(plan, output.numberOfPages),
                    )
                }

                // §5 step 3.
                removeFieldRemnants(output)
                report(context, PHASE_IMPORTING, 0.2)

                // §5 step 4: one subsetted embed of the bundled regular font.
                val font = PDType0Font.load(output, readFontBytes().inputStream(), true)

                // §5 step 5.
                drawOverlays(output, plan, font, context)
                // §5 step 6.
                sanitizeMetadata(output, plan)
                // §5 step 7.
                writeToFile(output, temporaryFile)
            }
        }
    }

    /**
     * §5 step 2a: flatten a pre-existing AcroForm **in memory** so existing
     * field appearances become ordinary page content.
     *
     * A source whose appearances cannot be flattened is not silently accepted:
     * dropping the appearances would change the document, so the export is
     * blocked. `EXP-002` is used because no single page can be named (the
     * contract's `EXP-006` names a page).
     */
    private fun flattenSourceAcroForm(document: PDDocument) {
        val catalog = document.documentCatalog ?: throw exportFailure("EXP-002")
        val acroForm = catalog.acroForm ?: return
        if (acroForm.fields.isEmpty()) return
        try {
            acroForm.flatten()
        } catch (failure: IOException) {
            throw exportFailure("EXP-002")
        } catch (failure: IllegalArgumentException) {
            throw exportFailure("EXP-002")
        }
        catalog.acroForm = null
    }

    /** §5 step 3: no residual field dictionaries, widgets, or AcroForm (FR-069). */
    private fun removeFieldRemnants(document: PDDocument) {
        val catalog = document.documentCatalog ?: throw exportFailure("EXP-002")
        catalog.acroForm = null
        for (page in document.pages) {
            val annotations = page.annotations
            if (annotations.isEmpty()) continue
            val kept = annotations.filterNot { it is PDAnnotationWidget }
            if (kept.size != annotations.size) page.annotations = kept
        }
        if (document.documentCatalog?.acroForm?.fields?.isNotEmpty() == true) {
            throw exportFailure("EXP-002")
        }
    }

    /** §5 step 5: one appended content stream per page, ops in plan order. */
    private fun drawOverlays(
        output: PDDocument,
        plan: ExportPlan,
        font: PDFont,
        context: OperationContext,
    ) {
        val images = HashMap<String, PDImageXObject>()
        try {
            for (page in plan.pages) {
                context.checkCancelled()
                if (page.index >= output.numberOfPages) {
                    throw exportFailure("EXP-006", pageIndex = page.index)
                }
                val target = output.getPage(page.index)
                PDPageContentStream(
                    output,
                    target,
                    PDPageContentStream.AppendMode.APPEND,
                    /* compress */ true,
                    /* resetContext */ true,
                ).use { stream ->
                    // `coordinates-and-geometry.md` §5: all ops are drawn in
                    // display space under the display→PDF CTM, so marks appear
                    // upright on all four rotations.
                    stream.transform(page.ctm.toMatrix())
                    for (op in page.ops) {
                        when (op) {
                            is ExportTextOp -> drawText(stream, font, page.index, op)
                            is ExportCheckboxOp -> drawCheckbox(stream, op)
                            is ExportImageOp ->
                                drawSignature(output, stream, plan.documentId, page.index, op, images)
                        }
                    }
                }
                val fraction = 0.2 + 0.6 * ((page.index + 1).toDouble() / plan.pageCount.toDouble())
                report(context, PHASE_DRAWING, fraction, page.index)
            }
        } finally {
            images.clear()
        }
    }

    private fun drawText(
        stream: PDPageContentStream,
        font: PDFont,
        pageIndex: Int,
        op: ExportTextOp,
    ) {
        if (op.lines.isEmpty()) throw exportFailure("EXP-001", pageIndex = pageIndex)
        stream.beginText()
        stream.setFont(font, op.fontSizePt.toFloat())
        // `export-plan.md` §2.2: black is the only v1 text color.
        stream.setNonStrokingColor(0f, 0f, 0f)
        // §3.1: left aligned with 1.5 pt padding; the plan's baseline already
        // includes the top padding, and lines advance by `lineHeightPt`.
        val left = op.rect.x + ExportPlanValidator.TEXT_PADDING_PT
        op.lines.forEachIndexed { lineIndex, line ->
            val baseline = op.rect.y + op.baselineFromTopPt + lineIndex * op.lineHeightPt
            // Display space grows downwards, so the text matrix carries `d = -1`;
            // without it the display CTM would draw the glyphs mirrored.
            stream.setTextMatrix(
                Matrix(1f, 0f, 0f, -1f, left.toFloat(), baseline.toFloat()),
            )
            stream.showText(line)
        }
        stream.endText()
    }

    private fun drawCheckbox(stream: PDPageContentStream, op: ExportCheckboxOp) {
        // `export-plan.md` §3.2: an unchecked box draws nothing at all.
        if (!op.checked) return
        val left = (op.rect.x + op.insetPt).toFloat()
        val top = (op.rect.y + op.insetPt).toFloat()
        val right = (op.rect.right - op.insetPt).toFloat()
        val bottom = (op.rect.bottom - op.insetPt).toFloat()
        if (right <= left || bottom <= top) return
        stream.setStrokingColor(0f, 0f, 0f)
        stream.setLineWidth(op.strokeWidthPt.toFloat())
        // Round caps, two strokes forming the X.
        stream.setLineCapStyle(1)
        stream.moveTo(left, top)
        stream.lineTo(right, bottom)
        stream.stroke()
        stream.moveTo(left, bottom)
        stream.lineTo(right, top)
        stream.stroke()
    }

    /** `export-plan.md` §3.3: transparent PNG, `contain` fit, centered, 1 pt padding. */
    private fun drawSignature(
        output: PDDocument,
        stream: PDPageContentStream,
        documentId: String,
        pageIndex: Int,
        op: ExportImageOp,
        images: MutableMap<String, PDImageXObject>,
    ) {
        val image = images.getOrPut(op.assetId) {
            loadSignatureImage(output, documentId, pageIndex, op.assetId)
        }
        val availableWidth = op.rect.width - 2 * SIGNATURE_PADDING_PT
        val availableHeight = op.rect.height - 2 * SIGNATURE_PADDING_PT
        if (availableWidth <= 0.0 || availableHeight <= 0.0) {
            throw exportFailure("EXP-001", pageIndex = pageIndex)
        }
        // The PNG pixel size is its 72 dpi point size; the contract allows at
        // most 2× that and never more.
        val widthPt = image.width.toDouble()
        val heightPt = image.height.toDouble()
        val scale = minOf(availableWidth / widthPt, availableHeight / heightPt, MAX_SIGNATURE_SCALE)
        val drawWidth = widthPt * scale
        val drawHeight = heightPt * scale
        val left = op.rect.x + SIGNATURE_PADDING_PT + (availableWidth - drawWidth) / 2
        val top = op.rect.y + SIGNATURE_PADDING_PT + (availableHeight - drawHeight) / 2
        stream.saveGraphicsState()
        // Flip once: the image's own y axis points up, the display space's down.
        stream.transform(Matrix(1f, 0f, 0f, -1f, left.toFloat(), (top + drawHeight).toFloat()))
        stream.drawImage(image, 0f, 0f, drawWidth.toFloat(), drawHeight.toFloat())
        stream.restoreGraphicsState()
    }

    private fun loadSignatureImage(
        output: PDDocument,
        documentId: String,
        pageIndex: Int,
        assetId: String,
    ): PDImageXObject {
        val bytes = try {
            content.loadSignature(documentId, assetId)
        } catch (failure: KeyUnavailableException) {
            throw failure
        } catch (failure: Exception) {
            throw exportFailure("EXP-002", pageIndex = pageIndex)
        }
        val bitmap: Bitmap = try {
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        } catch (failure: Exception) {
            null
        } ?: throw exportFailure("EXP-002", pageIndex = pageIndex)
        return try {
            LosslessFactory.createFromImage(output, bitmap)
        } finally {
            bitmap.recycle()
        }
    }

    /**
     * §5 step 6: keep only `Producer`/`Creator` and a content-free provenance
     * record, so a source title or author never leaks into the artifact.
     *
     * The record is written as XMP rather than as an Info dictionary entry
     * because a PDF name cannot carry the contract's `Feldexa/FieldProvenance`
     * spelling; the XMP property `feldexa:fieldProvenance` holds exactly the
     * `{page, ordinal, provenance}` tuples, with no label, value, field id, or
     * path.
     */
    private fun sanitizeMetadata(output: PDDocument, plan: ExportPlan) {
        val catalog: PDDocumentCatalog = output.documentCatalog ?: throw exportFailure("EXP-002")
        // Drop the source XMP: it can carry a title, an author, or a device.
        catalog.metadata = null
        val info = output.documentInformation
        info.title = null
        info.author = null
        info.subject = null
        info.keywords = null
        info.setCreationDate(null)
        info.setModificationDate(null)
        info.creator = ARTIFACT_AUTHOR
        info.producer = ARTIFACT_AUTHOR
        val xmp = PDMetadata(output)
        xmp.importXMPMetadata(provenanceXmp(plan).toByteArray(Charsets.UTF_8))
        catalog.metadata = xmp
    }

    /** §5 step 7: write the temp artifact and flush it to disk. */
    private fun writeToFile(document: PDDocument, target: File) {
        FileOutputStream(target).use { stream ->
            document.save(stream)
            stream.flush()
            runCatching { stream.fd.sync() }
        }
    }

    // ------------------------------------------------------------------
    // Verification (§5 step 8, §6)
    // ------------------------------------------------------------------

    /**
     * Reopens the temp artifact and proves every §6 invariant that the applier
     * itself can check. Any failed check is `EXP-002`: an artifact that is not
     * verifiably correct is never returned.
     *
     * Every flag of the returned record is decided on the reopened document: the
     * overlay bounds are computed from the artifact's own page box and the plan
     * matrix, and the glyph check runs against the fonts the artifact page
     * references. Nothing here is a restatement of the plan.
     *
     * The stored source is checked once, before any write, against
     * `plan.sourceSha256` (`render`); the applier only ever reads those bytes, so
     * a second hash of the same in-memory array would verify nothing about the
     * artifact.
     */
    private fun verifyArtifact(
        temporaryFile: File,
        plan: ExportPlan,
    ): Map<String, Any?> {
        PDDocument.load(temporaryFile).use { document ->
            if (document.numberOfPages != plan.pageCount) throw exportFailure("EXP-002")
            for (page in plan.pages) {
                val target = document.getPage(page.index)
                assertBox(target.mediaBox, page.geometry.mediaBox)
                assertBox(target.cropBox ?: target.mediaBox, page.geometry.cropBox)
                if (target.rotation != page.geometry.rotation) throw exportFailure("EXP-002")
                assertOverlayBounds(target.cropBox ?: target.mediaBox, page)
                assertPlannedGlyphsEmbedded(target, page)
            }

            val acroForm = document.documentCatalog?.acroForm
            if (acroForm != null && acroForm.fields.isNotEmpty()) throw exportFailure("EXP-002")
            for (page in document.pages) {
                if (page.annotations.any { it is PDAnnotationWidget }) throw exportFailure("EXP-002")
            }

            assertPlannedTextExtracted(document, plan)
            assertMetadata(document, plan)
        }
        return linkedMapOf(
            "pageCountMatches" to true,
            "mediaBoxesMatch" to true,
            "fontGlyphsPresent" to true,
            "noInteractiveFields" to true,
            "overlayBoundsWithinPage" to true,
            "checkedAt" to nowIso(),
        )
    }

    /**
     * §5 step 8: every op rectangle of a page must lie inside the page box the
     * artifact carries (`export-plan.md` §6). The display rect is mapped through
     * the plan matrix into the artifact's own CropBox; the plan's `pdfRect` is
     * not trusted here, and the tolerance is the plan's 0.01 pt.
     */
    private fun assertOverlayBounds(actualPageBox: PDRectangle?, page: ExportPlanPage) {
        val box = actualPageBox ?: throw exportFailure("EXP-002")
        val pageBox = ExportRect(
            x = box.lowerLeftX.toDouble(),
            y = box.lowerLeftY.toDouble(),
            width = box.width.toDouble(),
            height = box.height.toDouble(),
        )
        for (op in page.ops) {
            if (!page.ctm.map(op.rect).isInside(pageBox, ExportPlanParser.GEOMETRY_TOLERANCE_PT)) {
                throw exportFailure("EXP-002")
            }
        }
    }

    /**
     * §5 step 8 / §6 "Text content": every planned line must be encodable by an
     * embedded font that the artifact page actually references. A glyph missing
     * from the embedded subset fails here instead of being silently substituted.
     */
    private fun assertPlannedGlyphsEmbedded(target: PDPage, page: ExportPlanPage) {
        val lines = page.ops
            .filterIsInstance<ExportTextOp>()
            .flatMap { it.lines }
            .filter { it.isNotEmpty() }
        if (lines.isEmpty()) return
        val resources = target.resources ?: throw exportFailure("EXP-002")
        val fonts = mutableListOf<PDFont>()
        for (name in resources.fontNames) {
            val font = try {
                resources.getFont(name)
            } catch (failure: IOException) {
                throw exportFailure("EXP-002")
            } ?: throw exportFailure("EXP-002")
            if (font.isEmbedded) fonts += font
        }
        if (fonts.isEmpty()) throw exportFailure("EXP-002")
        for (line in lines) {
            if (fonts.none { canEncode(it, line) }) throw exportFailure("EXP-002")
        }
    }

    /** True when the artifact's font can encode every code point of [line]. */
    private fun canEncode(font: PDFont, line: String): Boolean = try {
        font.encode(line)
        true
    } catch (failure: IOException) {
        false
    } catch (failure: IllegalArgumentException) {
        // PDFBox reports a code point without a glyph exactly this way.
        false
    } catch (failure: UnsupportedOperationException) {
        false
    }

    private fun assertBox(actual: PDRectangle?, expected: ExportRect) {
        if (actual == null) throw exportFailure("EXP-002")
        if (!closeEnough(actual.lowerLeftX.toDouble(), expected.x, ExportPlanParser.GEOMETRY_TOLERANCE_PT) ||
            !closeEnough(actual.lowerLeftY.toDouble(), expected.y, ExportPlanParser.GEOMETRY_TOLERANCE_PT) ||
            !closeEnough(actual.width.toDouble(), expected.width, ExportPlanParser.GEOMETRY_TOLERANCE_PT) ||
            !closeEnough(actual.height.toDouble(), expected.height, ExportPlanParser.GEOMETRY_TOLERANCE_PT)
        ) {
            throw exportFailure("EXP-002")
        }
    }

    /**
     * §6 "Text content": every planned line must be extractable with its German
     * characters intact. Whitespace is normalised because extraction may
     * re-space glyph runs.
     */
    private fun assertPlannedTextExtracted(document: PDDocument, plan: ExportPlan) {
        val stripper = PDFTextStripper()
        stripper.sortByPosition = false
        val extracted = normalizeWhitespace(
            try {
                stripper.getText(document)
            } catch (failure: IOException) {
                throw exportFailure("EXP-002")
            },
        )
        for (page in plan.pages) {
            for (op in page.ops) {
                if (op !is ExportTextOp) continue
                for (line in op.lines) {
                    val needle = normalizeWhitespace(line)
                    if (needle.isEmpty()) continue
                    if (!extracted.contains(needle)) throw exportFailure("EXP-002")
                }
            }
        }
    }

    /** §5 step 6 verification: no source metadata, and a provenance record that matches the plan. */
    private fun assertMetadata(document: PDDocument, plan: ExportPlan) {
        val info = document.documentInformation
        if (info.title != null && info.title.isNotEmpty()) throw exportFailure("EXP-002")
        if (info.author != null && info.author.isNotEmpty()) throw exportFailure("EXP-002")
        if (info.subject != null && info.subject.isNotEmpty()) throw exportFailure("EXP-002")
        if (info.creator != ARTIFACT_AUTHOR || info.producer != ARTIFACT_AUTHOR) throw exportFailure("EXP-002")
        val xmp = document.documentCatalog?.metadata?.exportXMPMetadata()?.use { stream ->
            stream.readBytes().toString(Charsets.UTF_8)
        } ?: throw exportFailure("EXP-002")
        val record = provenanceTuples(plan)
        if (!xmp.contains(XMP_PROPERTY)) throw exportFailure("EXP-002")
        for (tuple in record) {
            if (!xmp.contains(tuple)) throw exportFailure("EXP-002")
        }
        if (record.size != plan.opCount) throw exportFailure("EXP-002")
    }

    // ------------------------------------------------------------------
    // export.readArtifact / export.deleteArtifact
    // ------------------------------------------------------------------

    private fun deleteArtifact(request: PlatformRequest): Map<String, Any?> {
        val artifactId = requireArtifactId(request.string("artifactId"))
        if (!artifacts.delete(artifactId)) throw exportFailure("EXP-002")
        return linkedMapOf("deleted" to true)
    }

    // ------------------------------------------------------------------
    // Shared helpers
    // ------------------------------------------------------------------

    private fun requirePlan(request: PlatformRequest): Map<String, Any?> =
        request.map("plan") ?: throw PlatformFailure.invalidPayload("platform.missingField")

    /** The facade validated the UUID shape; an unknown id is `EXP-002` (§6). */
    private fun requireArtifactId(value: String?): String =
        value ?: throw exportFailure("EXP-002")

    private fun readSource(plan: ExportPlan): ByteArray = try {
        content.loadSource(plan.documentId)
    } catch (failure: KeyUnavailableException) {
        throw failure
    } catch (failure: CorruptDataException) {
        throw exportFailure("EXP-005")
    } catch (failure: Exception) {
        throw exportFailure("EXP-005")
    }

    /**
     * Reopens the bundled Flutter asset
     * (`flutter_assets/assets/fonts/NotoSans-Regular.ttf`). The asset is part of
     * the APK, so a failure is an internal defect, not a document problem.
     */
    private fun readFontBytes(): ByteArray = try {
        regularFont.open().use { it.readBytes() }
    } catch (failure: Exception) {
        throw PlatformFailure.internal()
    }

    /** §5 preconditions: free space ≥ `2 × estimatedOutput + 32 MiB`. */
    private fun requireFreeSpace(sourceBytes: Long) {
        val estimatedOutput = sourceBytes + OUTPUT_OVERHEAD_BYTES
        val required = 2 * estimatedOutput + FREE_SPACE_HEADROOM_BYTES
        if (artifacts.usableSpaceBytes() < required) throw exportFailure("SAVE-001")
    }

    private fun renameAtomically(from: File, to: File) {
        try {
            Files.move(
                from.toPath(),
                to.toPath(),
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING,
            )
        } catch (failure: IOException) {
            throw exportFailure("EXP-002")
        }
        // Best effort: the rename is already atomic on this filesystem.
        runCatching {
            FileChannel.open(to.parentFile!!.toPath(), StandardOpenOption.READ).use { it.force(true) }
        }
    }

    private fun report(context: OperationContext, phase: String, fraction: Double, pageIndex: Int? = null) {
        // `exportProgress` also honours cancellation.
        context.exportProgress(phase, fraction.coerceIn(0.0, 1.0), pageIndex)
    }

    private fun provenanceXmp(plan: ExportPlan): String {
        val tuples = provenanceTuples(plan).joinToString(separator = "")
        return buildString {
            append("<?xpacket begin=\"\uFEFF\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n")
            append("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">\n")
            append(" <rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\n")
            append("  <rdf:Description rdf:about=\"\" xmlns:")
            append(XMP_NAMESPACE_PREFIX)
            append("=\"")
            append(XMP_NAMESPACE_URI)
            append("\">\n")
            append("   <")
            append(XMP_PROPERTY)
            append(">")
            append(tuples)
            append("</")
            append(XMP_PROPERTY)
            append(">\n")
            append("  </rdf:Description>\n")
            append(" </rdf:RDF>\n")
            append("</x:xmpmeta>\n")
            append("<?xpacket end=\"w\"?>")
        }
    }

    /**
     * `{page, ordinal, provenance}` tuples only (`export-plan.md` §5 step 6).
     * `p` = page index, `o` = op ordinal in plan order, `v` = provenance token;
     * no field id, label, value, path, or timestamp.
     */
    private fun provenanceTuples(plan: ExportPlan): List<String> = buildList {
        for (page in plan.pages) {
            page.ops.forEachIndexed { ordinal, op ->
                add("{\"p\":${page.index},\"o\":$ordinal,\"v\":\"${op.provenance.wireValue}\"}")
            }
        }
    }

    private fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") {
            "%02x".format(it.toInt() and 0xFF)
        }

    private fun sha256Hex(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { stream ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = stream.read(buffer)
                if (read <= 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xFF) }
    }

    private fun normalizeWhitespace(text: String): String =
        text.replace(WHITESPACE, " ").trim()

    private fun nowIso(): String = ISO_MILLIS.format(Instant.ofEpochMilli(clock()))

    private fun ExportCtm.toMatrix(): Matrix = Matrix(
        a.toFloat(),
        b.toFloat(),
        c.toFloat(),
        d.toFloat(),
        e.toFloat(),
        f.toFloat(),
    )

    companion object {
        /** `contracts/export-plan.md` §2 font contract. */
        const val EXPECTED_REGULAR_ASSET = "assets/fonts/NotoSans-Regular.ttf"

        /** `platform-channel.md` §6 progress phases. */
        const val PHASE_IMPORTING = "importing"
        const val PHASE_DRAWING = "drawing"
        const val PHASE_VERIFYING = "verifying"
        const val PHASE_FINALIZING = "finalizing"

        /** `export-plan.md` §3.3. */
        private const val SIGNATURE_PADDING_PT = 1.0
        private const val MAX_SIGNATURE_SCALE = 2.0

        /** §5 step 6: the only metadata values the artifact may carry. */
        private const val ARTIFACT_AUTHOR = "Feldexa"
        private const val XMP_NAMESPACE_PREFIX = "feldexa"
        private const val XMP_NAMESPACE_URI = "https://feldexa.de/ns/export/1.0/"
        private const val XMP_PROPERTY = "feldexa:fieldProvenance"

        private const val OUTPUT_OVERHEAD_BYTES = 4L * 1024L * 1024L
        private const val FREE_SPACE_HEADROOM_BYTES = 32L * 1024L * 1024L

        private val WHITESPACE = Regex("\\s+")

        private val ISO_MILLIS: DateTimeFormatter =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)
    }
}

/**
 * Read-only access to the stored source and its signature assets.
 *
 * Production adapts `EncryptedStore` (`loadDocument().sourceBytes` and
 * `readSignature`); tests would substitute an in-memory source. The service
 * never sees a path or a URI.
 */
interface ExportContentSource {
    fun loadSource(documentId: String): ByteArray

    fun loadSignature(documentId: String, assetId: String): ByteArray
}

/**
 * The bundled regular font as an openable stream.
 *
 * The font ships as a Flutter asset, so the production adapter opens
 * `flutter_assets/assets/fonts/NotoSans-Regular.ttf` from the `AssetManager`.
 */
fun interface RegularFontSource {
    fun open(): InputStream
}
