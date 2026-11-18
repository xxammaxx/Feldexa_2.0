package de.feldexa.app.pdf

import com.tom_roush.pdfbox.cos.COSArray
import com.tom_roush.pdfbox.cos.COSDictionary
import com.tom_roush.pdfbox.cos.COSName
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.io.RandomAccessRead
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException
import java.io.IOException
import java.io.InputStream

/**
 * T039 PDF preflight: per-page geometry and conservative encryption/damage
 * classification.
 *
 * Normative sources:
 *  - `contracts/platform-channel.md` §3 (`import.pickAndImport` result shape,
 *    `IMP-001`…`IMP-006`, `pages[].unreadable`, `pageFailures`);
 *  - `contracts/coordinates-and-geometry.md` §1.1 (MediaBox/CropBox/rotation
 *    are reported in PDF points, in document order, without swapping);
 *  - `contracts/ports.md` §2.1 (`PageFailure` category/messageKey shape);
 *  - `spec.md` FR-003, FR-005, FR-006, FR-007, FR-010.
 *
 * The parser is PDFBox-Android. It is called without a password (PDFBox's
 * empty user password). The exact encryption signals are:
 *
 *  1. [InvalidPasswordException] from `PDDocument.load` means a non-empty
 *     user password is required. That is the only signal used for
 *     [PASSWORD_PROTECTED]; the exception text/path is never exposed.
 *  2. A successful load with `PDDocument.isEncrypted == true` means the file
 *     is encrypted but opens with the empty user password. It is still an
 *     unsupported encrypted PDF (FR-005), not a readable file, and is
 *     reported as [UNSUPPORTED_ENCRYPTION].
 *  3. PDFBox's known unsupported-security-handler failures (for example a
 *     public-key handler without a key or an unknown `/Filter`) are reported
 *     as [UNSUPPORTED_ENCRYPTION]. Password material is never requested,
 *     captured, stored, or logged.
 *
 * PDFBox is deliberately lenient and can load a file whose `%%EOF` or
 * `startxref` was cut off, silently dropping trailing pages. Before parsing,
 * the reader is therefore checked for a PDF header, a trailing `%%EOF`, a
 * `startxref` offset that points inside the file, and an `xref` table or
 * cross-reference-stream object header at that offset. A file that fails this
 * structural check is `IMP-002` (truncated/unreadable), never a plausible
 * partial import. This is a bounded structural pre-check, not a full PDF
 * validator.
 *
 * The class owns no storage, SAF, channel, viewer, or UI behaviour. The caller
 * owns [RandomAccessRead] and must close it; this class closes every
 * [PDDocument] it opens with `use`. It never logs document content and never
 * catches `Error` subclasses, which remain the facade's `PLT-001` concern.
 */
class PdfPreflight private constructor(
    private val loader: PdfDocumentLoader,
    private val clock: () -> Long,
) {

    constructor(clock: () -> Long = System::currentTimeMillis) : this(
        loader = PdfBoxDocumentLoader,
        clock = clock,
    )

    /**
     * Test seam only: replaces the PDFBox load call while keeping the real
     * structural check, page walk, classification, and close path.
     */
    internal constructor(loader: PdfDocumentLoader) : this(
        loader = loader,
        clock = System::currentTimeMillis,
    )

    /**
     * Runs preflight against a storage-agnostic, already-decrypted reader.
     *
     * The reader may represent staged ciphertext decrypted on the fly; this
     * method never inspects storage layout. It seeks to zero and consumes the
     * reader sequentially. The caller keeps ownership and must close it.
     */
    fun preflight(source: RandomAccessRead): PdfPreflightResult {
        val startedAt = clock()
        return try {
            preflightInternal(source, startedAt)
        } catch (failure: InvalidPasswordException) {
            reject(Rejection.PASSWORD_PROTECTED, startedAt)
        } catch (failure: IOException) {
            reject(classifyLoadFailure(failure), startedAt)
        } catch (failure: UnsupportedOperationException) {
            reject(Rejection.UNSUPPORTED_STRUCTURE, startedAt)
        } catch (failure: Exception) {
            reject(Rejection.UNKNOWN, startedAt)
        }
    }

    private fun preflightInternal(
        source: RandomAccessRead,
        startedAt: Long,
    ): PdfPreflightResult {
        when (inspectStructure(source)) {
            Structure.NOT_PDF -> return reject(Rejection.NOT_PDF, startedAt)
            Structure.TRUNCATED -> return reject(Rejection.READ_FAILED, startedAt)
            Structure.PDF -> Unit
        }

        source.seek(0)
        val document = loader.load(RandomAccessReadInputStream(source))
        document.use { open ->
            // An encrypted document can open successfully when its user
            // password is empty. FR-005 still rejects it; do not let PDFBox's
            // lenient empty-password success turn it into a readable file.
            if (open.isEncrypted) {
                return reject(Rejection.UNSUPPORTED_ENCRYPTION, startedAt)
            }

            val pageCount = try {
                open.numberOfPages
            } catch (failure: Exception) {
                return reject(Rejection.READ_FAILED, startedAt)
            }
            if (pageCount <= 0) {
                return reject(Rejection.UNSUPPORTED_STRUCTURE, startedAt)
            }
            // `plan.md` §Scale/Scope and `contracts/storage-format.md` §6 cap
            // a document at 100 pages. Bound the single reported count before
            // any per-page collection or walk, so a hostile page tree cannot
            // force unbounded allocation or page access.
            if (pageCount > MAX_PAGE_COUNT) {
                return reject(Rejection.UNSUPPORTED_STRUCTURE, startedAt)
            }

            val pages = ArrayList<PdfPreflightPage>(pageCount)
            for (index in 0 until pageCount) {
                pages += readPage(open, index)
            }
            val pageFailures = pages.mapNotNull { it.pageFailure }

            if (pageFailures.size == pageCount) {
                // A page failure is only IMP-006 data while at least one page
                // remains usable. With no readable page the whole document is
                // unusable and must be rejected.
                val unsupportedOnly =
                    pageFailures.all { it.category == PAGE_UNSUPPORTED_STRUCTURE }
                return reject(
                    if (unsupportedOnly) Rejection.UNSUPPORTED_STRUCTURE else Rejection.READ_FAILED,
                    startedAt,
                )
            }

            return PdfPreflightSuccess(pages = pages, pageFailures = pageFailures)
        }
    }

    private fun readPage(document: PDDocument, index: Int): PdfPreflightPage {
        return try {
            val page = document.getPage(index)
            if (!hasInheritableMediaBox(page)) {
                return unreadablePage(index, PAGE_UNSUPPORTED_STRUCTURE)
            }
            val mediaBox = page.mediaBox
            val cropBox = page.cropBox
            val rotation = page.rotation
            if (
                !isUsableBox(mediaBox) ||
                !isUsableBox(cropBox) ||
                rotation !in SUPPORTED_ROTATIONS
            ) {
                return unreadablePage(index, PAGE_UNSUPPORTED_STRUCTURE)
            }
            PdfPreflightPage(
                pageIndex = index,
                mediaBox = mediaBox.toPageBox(),
                cropBox = cropBox.toPageBox(),
                rotation = rotation,
                unreadable = false,
                pageFailure = null,
            )
        } catch (failure: UnsupportedOperationException) {
            unreadablePage(index, PAGE_UNSUPPORTED_STRUCTURE)
        } catch (failure: Exception) {
            unreadablePage(index, PAGE_UNREADABLE)
        }
    }

    private fun unreadablePage(index: Int, category: String): PdfPreflightPage {
        val failure = PdfPageFailure(
            pageIndex = index,
            category = category,
            messageKey = PAGE_FAILURE_MESSAGE_KEY,
        )
        return PdfPreflightPage(
            pageIndex = index,
            mediaBox = null,
            cropBox = null,
            rotation = null,
            unreadable = true,
            pageFailure = failure,
        )
    }

    private fun reject(rejection: Rejection, startedAt: Long): PdfPreflightFailure {
        val duration = (clock() - startedAt).coerceAtLeast(0L)
        return PdfPreflightFailure(
            code = rejection.code,
            message = rejection.message,
            category = rejection.category,
            retryable = false,
            durationMs = duration,
        )
    }

    private fun classifyLoadFailure(failure: IOException): Rejection {
        if (containsInvalidPassword(failure)) return Rejection.PASSWORD_PROTECTED
        val message = failure.message.orEmpty()
        return when {
            message.startsWith("No security handler for filter") ->
                Rejection.UNSUPPORTED_ENCRYPTION
            message.contains("decryption material is not compatible", ignoreCase = true) ->
                Rejection.UNSUPPORTED_ENCRYPTION
            message.contains("Cannot decrypt PDF", ignoreCase = true) ->
                Rejection.PASSWORD_PROTECTED
            message.contains("unsupported", ignoreCase = true) ->
                Rejection.UNSUPPORTED_STRUCTURE
            message.contains("not supported", ignoreCase = true) ->
                Rejection.UNSUPPORTED_STRUCTURE
            else -> Rejection.READ_FAILED
        }
    }

    private fun containsInvalidPassword(failure: Throwable): Boolean {
        var current: Throwable? = failure
        while (current != null) {
            if (current is InvalidPasswordException) return true
            current = current.cause
        }
        return false
    }

    /** Follows `/MediaBox` through the page tree without PDFBox's Letter fallback. */
    private fun hasInheritableMediaBox(page: PDPage): Boolean {
        val visited = HashSet<COSDictionary>()
        var node: COSDictionary? = page.cosObject
        while (node != null) {
            if (!visited.add(node)) return false
            if (node.containsKey(COSName.MEDIA_BOX)) {
                val value = node.getDictionaryObject(COSName.MEDIA_BOX)
                return value is COSArray && value.size() == 4
            }
            node = node.getDictionaryObject(COSName.PARENT) as? COSDictionary
        }
        return false
    }

    private fun isUsableBox(box: PDRectangle): Boolean {
        val width = box.width.toDouble()
        val height = box.height.toDouble()
        val x = box.lowerLeftX.toDouble()
        val y = box.lowerLeftY.toDouble()
        return width.isFinite() && width > 0.0 &&
            height.isFinite() && height > 0.0 &&
            x.isFinite() && y.isFinite()
    }

    private fun PDRectangle.toPageBox(): PdfPageBox = PdfPageBox(
        x = lowerLeftX.toDouble(),
        y = lowerLeftY.toDouble(),
        width = width.toDouble(),
        height = height.toDouble(),
    )

    private fun inspectStructure(source: RandomAccessRead): Structure {
        val length = source.length()
        if (length < PDF_HEADER.length) return Structure.NOT_PDF

        val header = readWindow(
            source = source,
            offset = 0L,
            length = minOf(length, HEADER_WINDOW_BYTES.toLong()).toInt(),
        )
        if (!String(header, Charsets.ISO_8859_1).contains(PDF_HEADER)) {
            return Structure.NOT_PDF
        }
        if (length < MINIMUM_PDF_BYTES) return Structure.TRUNCATED

        val tailLength = minOf(length, TAIL_WINDOW_BYTES.toLong()).toInt()
        val tail = readWindow(
            source = source,
            offset = length - tailLength,
            length = tailLength,
        )
        val tailText = String(tail, Charsets.ISO_8859_1)
        val eofIndex = tailText.lastIndexOf(EOF_MARKER)
        if (eofIndex < 0) return Structure.TRUNCATED

        val startXrefIndex = tailText.lastIndexOf(STARTXREF_MARKER)
        if (startXrefIndex < 0 || startXrefIndex > eofIndex) {
            return Structure.TRUNCATED
        }
        val xrefOffset = parseOffset(tailText, startXrefIndex + STARTXREF_MARKER.length)
            ?: return Structure.TRUNCATED
        if (xrefOffset <= 0L || xrefOffset >= length) return Structure.TRUNCATED

        val marker = readWindow(
            source = source,
            offset = xrefOffset,
            length = minOf(length - xrefOffset, XREF_MARKER_WINDOW_BYTES.toLong()).toInt(),
        )
        val markerText = String(marker, Charsets.ISO_8859_1)
            .trimStart { it.isWhitespace() || it == '\u0000' }
        if (!markerText.startsWith(CLASSIC_XREF_MARKER) &&
            !XREF_STREAM_OBJECT_HEADER.containsMatchIn(markerText)
        ) {
            return Structure.TRUNCATED
        }
        return Structure.PDF
    }

    private fun readWindow(
        source: RandomAccessRead,
        offset: Long,
        length: Int,
    ): ByteArray {
        if (offset < 0L || length <= 0) return ByteArray(0)
        val available = minOf(length.toLong(), source.length() - offset).toInt()
        if (available <= 0) return ByteArray(0)
        val bytes = ByteArray(available)
        source.seek(offset)
        var read = 0
        while (read < available) {
            val count = source.read(bytes, read, available - read)
            if (count <= 0) break
            read += count
        }
        return if (read == available) bytes else bytes.copyOf(read)
    }

    private fun parseOffset(text: String, from: Int): Long? {
        var index = from
        while (index < text.length && text[index].isWhitespace()) index++
        val start = index
        while (index < text.length && text[index].isDigit()) {
            if (index - start >= MAX_OFFSET_DIGITS) return null
            index++
        }
        if (index == start) return null
        return text.substring(start, index).toLongOrNull()
    }

    private enum class Structure {
        PDF,
        NOT_PDF,
        TRUNCATED,
    }

    private enum class Rejection(
        val code: String,
        val message: String,
        val category: String,
    ) {
        PASSWORD_PROTECTED(
            code = "IMP-001",
            message = "import.passwordProtected",
            category = "importRejected",
        ),
        UNSUPPORTED_ENCRYPTION(
            code = "IMP-001",
            message = "import.unsupportedEncryption",
            category = "importRejected",
        ),
        READ_FAILED(
            code = "IMP-002",
            message = "import.unreadable",
            category = "unreadable",
        ),
        NOT_PDF(
            code = "IMP-004",
            message = "import.notPdf",
            category = "notPdf",
        ),
        UNSUPPORTED_STRUCTURE(
            code = "IMP-004",
            message = "import.unsupportedStructure",
            category = "notPdf",
        ),
        UNKNOWN(
            code = "IMP-005",
            message = "import.unknown",
            category = "internalError",
        ),
    }

    private companion object {
        private const val SCHEMA_VERSION = 1
        private const val HEADER_WINDOW_BYTES = 1024
        private const val TAIL_WINDOW_BYTES = 64 * 1024
        private const val XREF_MARKER_WINDOW_BYTES = 64
        private const val MINIMUM_PDF_BYTES = 8L
        private const val MAX_PAGE_COUNT = 100
        private const val MAX_OFFSET_DIGITS = 18
        private const val PDF_HEADER = "%PDF-"
        private const val EOF_MARKER = "%%EOF"
        private const val STARTXREF_MARKER = "startxref"
        private const val CLASSIC_XREF_MARKER = "xref"
        private const val PAGE_UNREADABLE = "unreadable"
        private const val PAGE_UNSUPPORTED_STRUCTURE = "unsupported_structure"
        private const val PAGE_FAILURE_MESSAGE_KEY = "IMP-006"
        private val SUPPORTED_ROTATIONS = setOf(0, 90, 180, 270)
        private val XREF_STREAM_OBJECT_HEADER =
            Regex("^\\d+\\s+\\d+\\s+obj(?:\\s|$)")
    }
}

/** Storage-agnostic PDF load boundary; production uses PDFBox-Android. */
internal fun interface PdfDocumentLoader {
    fun load(stream: InputStream): PDDocument
}

internal object PdfBoxDocumentLoader : PdfDocumentLoader {
    override fun load(stream: InputStream): PDDocument =
        // Main-memory-only keeps PDFBox's working copy off disk: preflight
        // must not create a plaintext scratch file for a private document.
        PDDocument.load(stream, MemoryUsageSetting.setupMainMemoryOnly())
}

/**
 * Adapts a caller-owned [RandomAccessRead] to PDFBox's stream entry point.
 *
 * `close()` is intentionally a no-op: preflight does not own the staged
 * reader. PDFBox closes its own main-memory buffer when the [PDDocument] is
 * closed.
 */
private class RandomAccessReadInputStream(
    private val source: RandomAccessRead,
) : InputStream() {

    override fun read(): Int = source.read()

    override fun read(bytes: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        return source.read(bytes, offset, length)
    }

    override fun close() = Unit
}

/** A rectangle in PDF points, in the document's own user space. */
data class PdfPageBox(
    val x: Double,
    val y: Double,
    val width: Double,
    val height: Double,
)

/**
 * One page in document order.
 *
 * A readable page has all three geometry fields and `unreadable = false`.
 * An unreadable page has `unreadable = true`, no geometry, and exactly one
 * matching [pageFailure]; its index and position in the list are preserved so
 * readable pages keep their original order.
 */
data class PdfPreflightPage(
    val pageIndex: Int,
    val mediaBox: PdfPageBox?,
    val cropBox: PdfPageBox?,
    val rotation: Int?,
    val unreadable: Boolean,
    val pageFailure: PdfPageFailure? = null,
) {
    init {
        require(pageIndex >= 0) { "pageIndex must be non-negative" }
        require(unreadable == (pageFailure != null)) {
            "unreadable page must carry exactly one failure"
        }
        require(
            if (unreadable) {
                mediaBox == null && cropBox == null && rotation == null
            } else {
                mediaBox != null && cropBox != null && rotation != null
            },
        ) { "page geometry and unreadable state disagree" }
        require(!unreadable || pageFailure?.pageIndex == pageIndex) {
            "page failure index must match the page"
        }
    }
}

/**
 * One page-level failure in the canonical `PageFailure` shape
 * (`contracts/ports.md` §2.1): zero-based page index, core category token, and
 * the `IMP-006` catalog key. It carries no page image, content, path, or title.
 */
data class PdfPageFailure(
    val pageIndex: Int,
    val category: String,
    val messageKey: String,
) {
    init {
        require(pageIndex >= 0) { "pageIndex must be non-negative" }
        require(category in PAGE_FAILURE_CATEGORIES) {
            "category is not a core page-failure token"
        }
        require(messageKey == PAGE_FAILURE_MESSAGE_KEY) {
            "messageKey must be the IMP-006 catalog key"
        }
    }

    private companion object {
        private const val PAGE_FAILURE_MESSAGE_KEY = "IMP-006"
        private val PAGE_FAILURE_CATEGORIES = setOf("unreadable", "unsupported_structure")
    }
}

/** Successful preflight, including the `IMP-006` partial-page data path. */
data class PdfPreflightSuccess(
    val pages: List<PdfPreflightPage>,
    val pageFailures: List<PdfPageFailure>,
) : PdfPreflightResult() {

    init {
        require(pages.isNotEmpty()) { "successful preflight must contain pages" }
        require(pages.indices.all { pages[it].pageIndex == it }) {
            "pages must be in document order"
        }
        require(pageFailures == pages.mapNotNull { it.pageFailure }) {
            "pageFailures must match the page list"
        }
        require(pageFailures.isEmpty() || pages.any { !it.unreadable }) {
            "a fully unreadable document must be rejected, not returned as success"
        }
    }

    /** Equals the number of returned pages, including unreadable ones. */
    val pageCount: Int get() = pages.size

    /** True when at least one page is unreadable but the document stays usable. */
    val partiallyReadable: Boolean get() = pageFailures.isNotEmpty()
}

/**
 * A classified, content-free preflight failure.
 *
 * [message] is a stable machine key from the closed `import.*` namespace, not
 * a German sentence. [details] has exactly the `contracts/platform-channel.md`
 * §2.2 shape and never contains a path, URI, title, file name, page image, or
 * stack trace.
 */
data class PdfPreflightFailure(
    val code: String,
    val message: String,
    val category: String,
    val retryable: Boolean,
    val durationMs: Long,
    val pageIndex: Int? = null,
) : PdfPreflightResult() {

    init {
        require(code in FAILURE_CODES) { "code is not a T039 preflight code" }
        require(message in FAILURE_MESSAGES) { "message is not a stable preflight key" }
        require(category in FAILURE_CATEGORIES) { "category is not a content-free code" }
        require(durationMs >= 0L) { "durationMs must be non-negative" }
        require(pageIndex == null || pageIndex >= 0) { "pageIndex must be non-negative" }
    }

    /** The `contracts/platform-channel.md` §2.2 details object. */
    fun details(): Map<String, Any?> = linkedMapOf(
        "schemaVersion" to SCHEMA_VERSION,
        "category" to category,
        "retryable" to retryable,
        "pageIndex" to pageIndex,
        "fieldCount" to null,
        "durationMs" to durationMs,
    )

    private companion object {
        private const val SCHEMA_VERSION = 1
        private val FAILURE_CODES = setOf("IMP-001", "IMP-002", "IMP-004", "IMP-005")
        private val FAILURE_MESSAGES = setOf(
            "import.passwordProtected",
            "import.unsupportedEncryption",
            "import.unreadable",
            "import.notPdf",
            "import.unsupportedStructure",
            "import.unknown",
        )
        private val FAILURE_CATEGORIES = setOf(
            "importRejected",
            "unreadable",
            "notPdf",
            "internalError",
        )
    }
}

/** Typed preflight outcome: one success shape and one classified failure shape. */
sealed class PdfPreflightResult
