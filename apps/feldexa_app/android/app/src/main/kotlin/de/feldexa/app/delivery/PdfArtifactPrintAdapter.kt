package de.feldexa.app.delivery

import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import com.tom_roush.pdfbox.pdmodel.PDDocument
import java.io.File
import java.io.IOException

/**
 * T107: the `PrintDocumentAdapter` behind `delivery.print`.
 *
 * The artifact is already a verified, self-contained vector PDF
 * (`contracts/export-plan.md` §6 "Printability"), so the adapter hands those
 * bytes to the print service unchanged. It deliberately does **not** rebuild
 * the document through `PrintedPdfDocument`: that would rasterise the pages in
 * the app and make the printed result disagree with the verified artifact. The
 * document is short-lived: it is read once for the page count and once for the
 * write, and nothing is rendered here.
 */
class PdfArtifactPrintAdapter(
    private val file: File,
) : PrintDocumentAdapter() {

    override fun onLayout(
        oldAttributes: PrintAttributes?,
        newAttributes: PrintAttributes,
        cancellationSignal: CancellationSignal?,
        callback: LayoutResultCallback,
        extras: Bundle?,
    ) {
        if (cancellationSignal?.isCanceled == true) {
            callback.onLayoutCancelled()
            return
        }
        val pageCount = try {
            PDDocument.load(file).use { document -> document.numberOfPages }
        } catch (failure: IOException) {
            callback.onLayoutFailed(null)
            return
        }
        if (pageCount < 1) {
            callback.onLayoutFailed(null)
            return
        }
        val info = PrintDocumentInfo.Builder(file.name)
            .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
            .setPageCount(pageCount)
            .build()
        val changed = oldAttributes?.let { it != newAttributes } ?: true
        callback.onLayoutFinished(info, changed)
    }

    override fun onWrite(
        pages: Array<out PageRange>?,
        destination: ParcelFileDescriptor,
        cancellationSignal: CancellationSignal?,
        callback: WriteResultCallback,
    ) {
        try {
            ParcelFileDescriptor.AutoCloseOutputStream(destination).use { output ->
                file.inputStream().use { input ->
                    val buffer = ByteArray(COPY_BUFFER_BYTES)
                    while (true) {
                        if (cancellationSignal?.isCanceled == true) {
                            callback.onWriteCancelled()
                            return
                        }
                        val read = input.read(buffer)
                        if (read <= 0) break
                        output.write(buffer, 0, read)
                    }
                    output.flush()
                }
            }
            callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
        } catch (failure: IOException) {
            callback.onWriteFailed(null)
        }
    }

    private companion object {
        const val COPY_BUFFER_BYTES = 64 * 1024
    }
}
