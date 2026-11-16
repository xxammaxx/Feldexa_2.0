package de.feldexa.app.storage

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import java.io.ByteArrayOutputStream

/**
 * Instrumentation-only synthetic PNG factory.
 *
 * The platform `Bitmap` encoder is independent of the production PNG parser,
 * so a green validation test proves a real Android-decodable PNG was accepted,
 * not a fixture shaped to the parser. The same `BitmapFactory` decoder proves
 * the adversarial fixtures are still syntactically PNG before they are
 * rejected by the size/structure rules.
 */
internal object AndroidTestPng {

    fun validRgba(width: Int, height: Int): ByteArray {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        try {
            bitmap.eraseColor(Color.argb(255, 0x33, 0x66, 0x99))
            val out = ByteArrayOutputStream()
            check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)) {
                "Android PNG encoder failed"
            }
            return out.toByteArray()
        } finally {
            bitmap.recycle()
        }
    }

    fun decodedSize(png: ByteArray): Pair<Int, Int> {
        val options = BitmapFactory.Options()
        options.inJustDecodeBounds = true
        BitmapFactory.decodeByteArray(png, 0, png.size, options)
        return options.outWidth to options.outHeight
    }

    fun decode(png: ByteArray): Bitmap =
        BitmapFactory.decodeByteArray(png, 0, png.size)
            ?: error("the test fixture is not decodable by BitmapFactory")
}
