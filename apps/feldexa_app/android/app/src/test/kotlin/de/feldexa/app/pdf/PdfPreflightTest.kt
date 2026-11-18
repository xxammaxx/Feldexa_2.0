package de.feldexa.app.pdf

import com.tom_roush.pdfbox.io.RandomAccessBuffer
import com.tom_roush.pdfbox.io.RandomAccessRead
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T039 host-JVM preflight tests.
 *
 * These are `NONE`-class checks: no Android runtime, emulator, Keystore, SAF,
 * channel, viewer, or real document is touched. PDFBox-Android runs on the host
 * JVM; the few `android.util.Log` calls on PDFBox's damaged-input recovery
 * paths are neutralised by the test-only `isReturnDefaultValues` Gradle seam.
 */
class PdfPreflightTest {

    private val preflight = PdfPreflight()

    @Test
    fun `returns every page geometry in document order without swapping`() {
        val bytes = PdfTestDocuments.document(
            PdfTestDocuments.PageSpec(
                media = PdfTestDocuments.BoxSpec(0f, 0f, 595.28f, 841.89f),
                crop = PdfTestDocuments.BoxSpec(10f, 20f, 560f, 790f),
                rotation = 0,
            ),
            PdfTestDocuments.PageSpec(
                media = PdfTestDocuments.BoxSpec(0f, 0f, 595.28f, 419.53f),
                rotation = 90,
            ),
            PdfTestDocuments.PageSpec(
                media = PdfTestDocuments.BoxSpec(10f, 20f, 300f, 400f),
                crop = PdfTestDocuments.BoxSpec(20f, 30f, 250f, 380f),
                rotation = 270,
            ),
        )

        val result = success(preflight.preflight(source(bytes)))

        assertEquals(3, result.pageCount)
        assertTrue(result.pageFailures.isEmpty())
        assertEquals(listOf(0, 1, 2), result.pages.map { it.pageIndex })

        val first = result.pages[0]
        assertFalse(first.unreadable)
        assertBox(first.mediaBox, 0.0, 0.0, 595.28, 841.89)
        assertBox(first.cropBox, 10.0, 20.0, 560.0, 790.0)
        assertEquals(0, first.rotation ?: -1)

        val second = result.pages[1]
        assertBox(second.mediaBox, 0.0, 0.0, 595.28, 419.53)
        // CropBox absent -> equals the page's own MediaBox; no A4 assumption.
        assertBox(second.cropBox, 0.0, 0.0, 595.28, 419.53)
        assertEquals(90, second.rotation ?: -1)

        val third = result.pages[2]
        // Rotation 270 must not swap the stored MediaBox dimensions.
        assertBox(third.mediaBox, 10.0, 20.0, 300.0, 400.0)
        assertBox(third.cropBox, 20.0, 30.0, 250.0, 380.0)
        assertEquals(270, third.rotation ?: -1)
    }

    @Test
    fun `clips an oversized crop box to the media box`() {
        val bytes = PdfTestDocuments.document(
            PdfTestDocuments.PageSpec(
                media = PdfTestDocuments.BoxSpec(0f, 0f, 595.28f, 841.89f),
                crop = PdfTestDocuments.BoxSpec(-10f, -20f, 700f, 900f),
            ),
        )

        val page = success(preflight.preflight(source(bytes))).pages.single()

        assertBox(page.mediaBox, 0.0, 0.0, 595.28, 841.89)
        assertBox(page.cropBox, 0.0, 0.0, 595.28, 841.89)
    }

    @Test
    fun `accepts inherited media boxes and normalises quarter-turn rotations`() {
        val inherited = PdfTestDocuments.inheritedMediaBox(
            media = PdfTestDocuments.BoxSpec(0f, 0f, 400f, 500f),
            pageCount = 2,
        )
        val inheritedPages = success(preflight.preflight(source(inherited))).pages
        assertEquals(2, inheritedPages.size)
        inheritedPages.forEach { page ->
            assertBox(page.mediaBox, 0.0, 0.0, 400.0, 500.0)
        }

        val rotations = PdfTestDocuments.document(
            PdfTestDocuments.PageSpec(rotation = 90),
            PdfTestDocuments.PageSpec(rotation = 180),
            PdfTestDocuments.PageSpec(rotation = 270),
            PdfTestDocuments.PageSpec(rotation = 450),
            PdfTestDocuments.PageSpec(rotation = -90),
        )
        assertEquals(
            listOf(90, 180, 270, 90, 270),
            success(preflight.preflight(source(rotations))).pages.map { it.rotation },
        )
    }

    @Test
    fun `rejects a truncated PDF as IMP-002 before PDFBox leniency can drop pages`() {
        val valid = PdfTestDocuments.document(
            PdfTestDocuments.PageSpec(),
            PdfTestDocuments.PageSpec(),
            PdfTestDocuments.PageSpec(),
        )
        var loaderCalled = false
        val guarded = PdfPreflight(
            loader = PdfDocumentLoader {
                loaderCalled = true
                throw AssertionError("truncated input must not reach PDFBox")
            },
        )

        for (fraction in listOf(0.5, 0.9, 0.99)) {
            val failure = failure(guarded.preflight(source(PdfTestDocuments.truncate(valid, fraction))))
            assertFailure(failure, "IMP-002", "import.unreadable", "unreadable")
        }
        assertFalse("structural rejection must precede the PDFBox load", loaderCalled)
    }

    @Test
    fun `rejects headerless input as IMP-004 and a bare header as IMP-002`() {
        val loader = PdfDocumentLoader {
            throw AssertionError("non-PDF input must not reach PDFBox")
        }
        val guarded = PdfPreflight(loader = loader)

        listOf(
            ByteArray(0),
            "not a pdf at all".toByteArray(),
        ).forEach { bytes ->
            assertFailure(
                failure(guarded.preflight(source(bytes))),
                "IMP-004",
                "import.notPdf",
                "notPdf",
            )
        }

        // A bare PDF header is a truncated PDF, not a non-PDF file.
        assertFailure(
            failure(guarded.preflight(source(byteArrayOf(0x25, 0x50, 0x44, 0x46, 0x2d)))),
            "IMP-002",
            "import.unreadable",
            "unreadable",
        )
    }

    @Test
    fun `rejects a password-protected PDF as IMP-001 without a password path`() {
        val encrypted = PdfTestDocuments.encrypted(
            userPassword = "synthetic-user-password",
            ownerPassword = "synthetic-owner-password",
        )

        val failure = failure(preflight.preflight(source(encrypted)))

        assertFailure(failure, "IMP-001", "import.passwordProtected", "importRejected")
        val rendered = failure.toString() + failure.message + failure.details()
        assertFalse(rendered.contains("synthetic-user-password"))
        assertFalse(rendered.contains("synthetic-owner-password"))
    }

    @Test
    fun `does not treat empty-user-password encryption as readable`() {
        val encrypted = PdfTestDocuments.encrypted(
            userPassword = "",
            ownerPassword = "synthetic-owner-password",
        )

        val failure = failure(preflight.preflight(source(encrypted)))

        assertFailure(failure, "IMP-001", "import.unsupportedEncryption", "importRejected")
    }

    @Test
    fun `keeps readable pages when one page has no usable media box`() {
        val bytes = PdfTestDocuments.document(
            PdfTestDocuments.PageSpec(
                media = PdfTestDocuments.BoxSpec(0f, 0f, 595f, 842f),
            ),
            PdfTestDocuments.PageSpec(omitMediaBox = true),
            PdfTestDocuments.PageSpec(
                media = PdfTestDocuments.BoxSpec(2f, 3f, 200f, 100f),
                rotation = 90,
            ),
        )

        val result = success(preflight.preflight(source(bytes)))

        assertEquals(3, result.pageCount)
        assertTrue(result.partiallyReadable)
        assertEquals(1, result.pageFailures.size)

        val failed = result.pages[1]
        assertTrue(failed.unreadable)
        assertNull(failed.mediaBox)
        assertNull(failed.cropBox)
        assertNull(failed.rotation)
        assertNotNull(failed.pageFailure)
        assertEquals(1, failed.pageFailure!!.pageIndex)
        assertEquals("unsupported_structure", failed.pageFailure!!.category)
        assertEquals("IMP-006", failed.pageFailure!!.messageKey)

        // Readable pages keep their own geometry and order.
        assertBox(result.pages[0].mediaBox, 0.0, 0.0, 595.0, 842.0)
        assertBox(result.pages[2].mediaBox, 2.0, 3.0, 200.0, 100.0)
        assertEquals(90, result.pages[2].rotation ?: -1)
        assertSame(failed.pageFailure, result.pageFailures.single())
    }

    @Test
    fun `keeps readable pages when one page throws while reading`() {
        val document = PageFailingDocument(failingPages = setOf(1), pageCount = 3)
        val guarded = PdfPreflight(loader = PdfDocumentLoader { document })

        val result = success(guarded.preflight(source(PdfTestDocuments.document(PdfTestDocuments.PageSpec()))))

        assertEquals(3, result.pageCount)
        assertTrue(result.partiallyReadable)
        assertTrue(result.pages[1].unreadable)
        assertEquals("unreadable", result.pages[1].pageFailure!!.category)
        assertEquals("IMP-006", result.pages[1].pageFailure!!.messageKey)
        assertEquals(0, result.pages[0].rotation ?: -1)
        assertEquals(0, result.pages[2].rotation ?: -1)
        assertTrue(document.closed)
    }

    @Test
    fun `rejects a document when every page throws while reading`() {
        val document = PageFailingDocument(failingPages = setOf(0, 1), pageCount = 2)
        val guarded = PdfPreflight(loader = PdfDocumentLoader { document })

        val failure = failure(guarded.preflight(source(PdfTestDocuments.document(PdfTestDocuments.PageSpec()))))

        assertFailure(failure, "IMP-002", "import.unreadable", "unreadable")
        assertTrue(document.closed)
    }

    @Test
    fun `rejects a document when every page is unusable`() {
        val missingBoxes = PdfTestDocuments.document(
            PdfTestDocuments.PageSpec(omitMediaBox = true),
            PdfTestDocuments.PageSpec(omitMediaBox = true),
        )
        val missingFailure = failure(preflight.preflight(source(missingBoxes)))
        assertFailure(
            missingFailure,
            "IMP-004",
            "import.unsupportedStructure",
            "notPdf",
        )

        val zeroSized = PdfTestDocuments.document(
            PdfTestDocuments.PageSpec(
                media = PdfTestDocuments.BoxSpec(0f, 0f, 0f, 0f),
            ),
        )
        val zeroFailure = failure(preflight.preflight(source(zeroSized)))
        assertFailure(zeroFailure, "IMP-004", "import.unsupportedStructure", "notPdf")
    }

    @Test
    fun `rejects a zero-page PDF as unsupported structure`() {
        val failure = failure(preflight.preflight(source(PdfTestDocuments.emptyDocument())))
        assertFailure(failure, "IMP-004", "import.unsupportedStructure", "notPdf")
    }

    @Test
    fun `rejects an absurd reported page count before any page access`() {
        val document = ReportedPageCountDocument(10_000) {
            throw AssertionError("page access must not happen before the page-count bound")
        }
        val guarded = PdfPreflight(loader = PdfDocumentLoader { document })

        val failure = failure(
            guarded.preflight(source(PdfTestDocuments.document(PdfTestDocuments.PageSpec()))),
        )

        assertFailure(failure, "IMP-004", "import.unsupportedStructure", "notPdf")
        assertEquals(0, document.pageAccessCalls)
        assertTrue(document.closed)
    }

    @Test
    fun `rejects a 101-page document as IMP-004`() {
        val failure = failure(preflight.preflight(source(PdfTestDocuments.pages(101))))

        assertFailure(failure, "IMP-004", "import.unsupportedStructure", "notPdf")
    }

    @Test
    fun `accepts the 100-page boundary with every page geometry`() {
        val result = success(preflight.preflight(source(PdfTestDocuments.pages(100))))

        assertEquals(100, result.pageCount)
        assertTrue(result.pageFailures.isEmpty())
        assertEquals((0 until 100).toList(), result.pages.map { it.pageIndex })
        assertBox(result.pages.first().mediaBox, 0.0, 0.0, 595.28, 841.89)
        assertBox(result.pages.last().mediaBox, 0.0, 0.0, 595.28, 841.89)
    }

    @Test
    fun `rejects an over-limit page tree whose pages do not exist without walking`() {
        val document = ReportedPageCountDocument(101) {
            throw IOException("synthetic page does not exist")
        }
        val guarded = PdfPreflight(loader = PdfDocumentLoader { document })

        val failure = failure(
            guarded.preflight(source(PdfTestDocuments.document(PdfTestDocuments.PageSpec()))),
        )

        assertFailure(failure, "IMP-004", "import.unsupportedStructure", "notPdf")
        assertEquals(0, document.pageAccessCalls)
        assertTrue(document.closed)
    }

    @Test
    fun `classifies damaged parse failures as IMP-002`() {
        val guarded = PdfPreflight(
            loader = PdfDocumentLoader {
                throw IOException("synthetic damaged page tree")
            },
        )

        val failure = failure(guarded.preflight(source(PdfTestDocuments.document(PdfTestDocuments.PageSpec()))))

        assertFailure(failure, "IMP-002", "import.unreadable", "unreadable")
    }

    @Test
    fun `classifies an unsupported parser feature as IMP-004`() {
        val guarded = PdfPreflight(
            loader = PdfDocumentLoader {
                throw IOException("Unsupported synthetic xref filter")
            },
        )

        val failure = failure(guarded.preflight(source(PdfTestDocuments.document(PdfTestDocuments.PageSpec()))))

        assertFailure(failure, "IMP-004", "import.unsupportedStructure", "notPdf")
    }

    @Test
    fun `classifies an unsupported security handler as IMP-001`() {
        val guarded = PdfPreflight(
            loader = PdfDocumentLoader {
                throw IOException("No security handler for filter SyntheticPublicKey")
            },
        )

        val failure = failure(guarded.preflight(source(PdfTestDocuments.document(PdfTestDocuments.PageSpec()))))

        assertFailure(failure, "IMP-001", "import.unsupportedEncryption", "importRejected")
    }

    @Test
    fun `classifies an unexpected loader failure as IMP-005 without leaking its text`() {
        val guarded = PdfPreflight(
            loader = PdfDocumentLoader {
                throw IllegalStateException("synthetic internal detail /private/path")
            },
        )

        val failure = failure(guarded.preflight(source(PdfTestDocuments.document(PdfTestDocuments.PageSpec()))))

        assertFailure(failure, "IMP-005", "import.unknown", "internalError")
        val rendered = failure.toString() + failure.message + failure.details()
        assertFalse(rendered.contains("synthetic internal detail"))
        assertFalse(rendered.contains("/private/path"))
    }

    @Test
    fun `accepts a cross-reference-stream object header at startxref`() {
        val xrefStreamLike = (
            "%PDF-1.5\n" +
                "1 0 obj\n<<>>\nendobj\n" +
                "startxref\n9\n%%EOF\n"
            ).toByteArray(Charsets.ISO_8859_1)
        val document = TrackingDocument().apply {
            addPage(PDPage(PDRectangle(0f, 0f, 595f, 842f)))
        }
        val guarded = PdfPreflight(loader = PdfDocumentLoader { document })

        val result = success(guarded.preflight(source(xrefStreamLike)))

        assertEquals(1, result.pageCount)
        assertTrue(document.closed)
    }

    @Test
    fun `closes the PDF document it opens on every success path`() {
        val document = TrackingDocument().apply {
            addPage(PDPage(PDRectangle(0f, 0f, 595f, 842f)))
        }
        val guarded = PdfPreflight(loader = PdfDocumentLoader { document })

        success(guarded.preflight(source(PdfTestDocuments.document(PdfTestDocuments.PageSpec()))))

        assertTrue(document.closed)
    }

    @Test
    fun `never closes the caller-owned staged reader`() {
        val successSource = TrackingSource(
            RandomAccessBuffer(PdfTestDocuments.document(PdfTestDocuments.PageSpec())),
        )
        success(preflight.preflight(successSource))
        assertFalse(successSource.closed)
        successSource.close()

        val rejectedSource = TrackingSource(
            RandomAccessBuffer(PdfTestDocuments.truncate(PdfTestDocuments.document(PdfTestDocuments.PageSpec()), 0.5)),
        )
        failure(preflight.preflight(rejectedSource))
        assertFalse(rejectedSource.closed)
        rejectedSource.close()
    }

    @Test
    fun `failure details match the platform-channel shape and measured duration`() {
        var reads = 0
        val timed = PdfPreflight(
            clock = {
                reads++
                if (reads == 1) 1_000L else 1_042L
            },
        )

        val failure = failure(timed.preflight(source("not a pdf".toByteArray())))

        assertEquals(
            listOf(
                "schemaVersion",
                "category",
                "retryable",
                "pageIndex",
                "fieldCount",
                "durationMs",
            ),
            failure.details().keys.toList(),
        )
        assertEquals(1, failure.details()["schemaVersion"])
        assertEquals("notPdf", failure.details()["category"])
        assertEquals(false, failure.details()["retryable"])
        assertNull(failure.details()["pageIndex"])
        assertNull(failure.details()["fieldCount"])
        assertEquals(42L, failure.details()["durationMs"])
        assertEquals(2, reads)
    }

    @Test
    fun `failure messages are content-free stable machine keys`() {
        val cases = listOf(
            failure(preflight.preflight(source("not a pdf".toByteArray()))),
            failure(
                preflight.preflight(
                    source(
                        PdfTestDocuments.truncate(PdfTestDocuments.document(PdfTestDocuments.PageSpec()), 0.5),
                    ),
                ),
            ),
            failure(
                preflight.preflight(
                    source(
                        PdfTestDocuments.encrypted(
                            userPassword = "synthetic-user-password",
                            ownerPassword = "synthetic-owner-password",
                        ),
                    ),
                ),
            ),
        )
        val machineKey = Regex("^[a-z][A-Za-z0-9]*(?:\\.[a-z][A-Za-z0-9]*)+$")

        cases.forEach { failure ->
            assertTrue("unexpected message key: ${failure.message}", machineKey.matches(failure.message))
            val rendered = failure.message + failure.details()
            assertFalse(rendered.contains(".pdf"))
            assertFalse(rendered.contains("/"))
            assertFalse(rendered.contains("\\"))
            assertFalse(rendered.contains("content://"))
            assertFalse(rendered.contains("synthetic-user-password"))
            assertFalse(rendered.contains("synthetic-owner-password"))
        }
    }

    private fun source(bytes: ByteArray): RandomAccessBuffer = RandomAccessBuffer(bytes)

    private fun success(result: PdfPreflightResult): PdfPreflightSuccess {
        assertTrue("expected success but was $result", result is PdfPreflightSuccess)
        return result as PdfPreflightSuccess
    }

    private fun failure(result: PdfPreflightResult): PdfPreflightFailure {
        assertTrue("expected failure but was $result", result is PdfPreflightFailure)
        return result as PdfPreflightFailure
    }

    private fun assertFailure(
        failure: PdfPreflightFailure,
        code: String,
        message: String,
        category: String,
    ) {
        assertEquals(code, failure.code)
        assertEquals(message, failure.message)
        assertEquals(category, failure.category)
        assertFalse(failure.retryable)
        assertEquals(1, failure.details()["schemaVersion"])
        assertEquals(category, failure.details()["category"])
        assertEquals(false, failure.details()["retryable"])
        assertNull(failure.details()["pageIndex"])
        assertNull(failure.details()["fieldCount"])
        assertTrue((failure.details()["durationMs"] as Long) >= 0L)
    }

    private fun assertBox(
        box: PdfPageBox?,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
    ) {
        assertNotNull(box)
        assertEquals(x, box!!.x, 0.01)
        assertEquals(y, box.y, 0.01)
        assertEquals(width, box.width, 0.01)
        assertEquals(height, box.height, 0.01)
    }

    private class TrackingSource(
        private val delegate: RandomAccessRead,
    ) : RandomAccessRead by delegate {

        var closed: Boolean = false
            private set

        override fun close() {
            closed = true
            delegate.close()
        }
    }

    private class TrackingDocument : PDDocument() {

        var closed: Boolean = false
            private set

        override fun close() {
            closed = true
            super.close()
        }
    }

    private class ReportedPageCountDocument(
        private val reportedPageCount: Int,
        private val pageAccessor: (Int) -> PDPage,
    ) : PDDocument() {

        var pageAccessCalls: Int = 0
            private set

        var closed: Boolean = false
            private set

        override fun getNumberOfPages(): Int = reportedPageCount

        override fun getPage(pageIndex: Int): PDPage {
            pageAccessCalls++
            return pageAccessor(pageIndex)
        }

        override fun close() {
            closed = true
            super.close()
        }
    }

    private class PageFailingDocument(
        private val failingPages: Set<Int>,
        pageCount: Int,
    ) : PDDocument() {

        var closed: Boolean = false
            private set

        init {
            repeat(pageCount) {
                addPage(PDPage(PDRectangle(0f, 0f, 595f, 842f)))
            }
        }

        override fun getPage(pageIndex: Int): PDPage {
            if (pageIndex in failingPages) {
                throw IOException("synthetic page read failure")
            }
            return super.getPage(pageIndex)
        }

        override fun close() {
            closed = true
            super.close()
        }
    }
}
