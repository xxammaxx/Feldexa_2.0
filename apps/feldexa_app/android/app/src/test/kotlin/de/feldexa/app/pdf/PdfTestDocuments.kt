package de.feldexa.app.pdf

import com.tom_roush.pdfbox.cos.COSName
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import com.tom_roush.pdfbox.pdmodel.encryption.AccessPermission
import com.tom_roush.pdfbox.pdmodel.encryption.StandardProtectionPolicy
import java.io.ByteArrayOutputStream

/**
 * Synthetic, in-memory PDF fixtures for the T039 host-JVM preflight tests.
 *
 * No file is written and no real document is used. The helper is kept in the
 * test source set only; production preflight has no fixture dependency.
 */
internal object PdfTestDocuments {

    data class BoxSpec(
        val x: Float,
        val y: Float,
        val width: Float,
        val height: Float,
    )

    data class PageSpec(
        val media: BoxSpec = BoxSpec(0f, 0f, 595.28f, 841.89f),
        val crop: BoxSpec? = null,
        val rotation: Int = 0,
        val omitMediaBox: Boolean = false,
    )

    fun document(vararg pages: PageSpec): ByteArray = PDDocument().use { document ->
        pages.forEach { spec ->
            val page = PDPage()
            if (spec.omitMediaBox) {
                page.cosObject.removeItem(COSName.MEDIA_BOX)
            } else {
                page.mediaBox = spec.media.toRectangle()
            }
            spec.crop?.let { page.cropBox = it.toRectangle() }
            page.rotation = spec.rotation
            document.addPage(page)
        }
        save(document)
    }

    fun emptyDocument(): ByteArray = PDDocument().use { document -> save(document) }

    fun inheritedMediaBox(media: BoxSpec, pageCount: Int): ByteArray =
        PDDocument().use { document ->
            document.pages.cosObject.setItem(COSName.MEDIA_BOX, media.toRectangle())
            repeat(pageCount) {
                val page = PDPage()
                page.cosObject.removeItem(COSName.MEDIA_BOX)
                document.addPage(page)
            }
            save(document)
        }

    fun encrypted(userPassword: String, ownerPassword: String): ByteArray {
        val plain = document(PageSpec())
        return PDDocument.load(plain).use { document ->
            val policy = StandardProtectionPolicy(
                ownerPassword,
                userPassword,
                AccessPermission(),
            )
            policy.encryptionKeyLength = 128
            document.protect(policy)
            save(document)
        }
    }

    fun truncate(bytes: ByteArray, fraction: Double): ByteArray {
        require(fraction in 0.0..1.0)
        return bytes.copyOf((bytes.size * fraction).toInt())
    }

    private fun save(document: PDDocument): ByteArray {
        val out = ByteArrayOutputStream()
        document.save(out)
        return out.toByteArray()
    }

    private fun BoxSpec.toRectangle(): PDRectangle =
        PDRectangle(x, y, width, height)
}
