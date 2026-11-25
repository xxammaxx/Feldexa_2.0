package de.feldexa.app.export

import com.tom_roush.pdfbox.pdmodel.font.PDFont
import java.io.IOException

/**
 * T104: the bundled-font metrics used by the plan checks and the overlay text.
 *
 * The applier must not fall back to a substitute font (`export-plan.md` §3.1):
 * a glyph that Noto Sans does not cover is a blocking `EXP-004`, so
 * [coversGlyphs] reports it instead of silently drawing a replacement.
 *
 * PDFBox reports a missing glyph as `IllegalArgumentException` from
 * `PDFont.encode` (`PCIDFontType2.encode` -> "No glyph for U+....").
 */
class PdfBoxFontMetrics(private val font: PDFont) : ExportFontMetrics {

    override fun coversGlyphs(text: String): Boolean = try {
        font.encode(text)
        true
    } catch (failure: IllegalArgumentException) {
        false
    } catch (failure: IOException) {
        false
    }

    override fun advanceWidthPt(text: String, fontSizePt: Double): Double = try {
        font.getStringWidth(text).toDouble() / 1000.0 * fontSizePt
    } catch (failure: IOException) {
        // Unmeasurable text must never be reported as fitting.
        Double.POSITIVE_INFINITY
    }
}
