package de.feldexa.app.storage

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.zip.CRC32
import java.util.zip.Deflater

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

    /**
     * RGB8 with a valid `tRNS` transparency chunk. The Android `Bitmap`
     * encoder always emits RGBA, so this fixture is built by the test-only
     * encoder and then decoded by `BitmapFactory` in the test to prove it is a
     * real PNG before the production validator accepts it.
     */
    fun validRgbWithTransparency(width: Int, height: Int): ByteArray =
        rgb8(width, height, withTransparency = true)

    /** RGB8 with neither an alpha channel nor `tRNS` (opaque, SAVE-007). */
    fun opaqueRgb(width: Int, height: Int): ByteArray =
        rgb8(width, height, withTransparency = false)

    /** Grayscale+alpha 8-bit (native alpha colour type 4). */
    fun validGrayscaleAlpha(width: Int, height: Int): ByteArray {
        val raw = ByteArray((width * 2 + 1) * height)
        var cursor = 0
        repeat(height) {
            raw[cursor++] = 0
            repeat(width) {
                raw[cursor++] = 0x80.toByte()
                raw[cursor++] = 0xFF.toByte()
            }
        }
        return assemble(
            listOf(
                chunk("IHDR", ihdr(width, height, bitDepth = 8, colorType = 4)),
                chunk("IDAT", deflate(raw)),
                chunk("IEND", ByteArray(0)),
            ),
        )
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

    private fun rgb8(width: Int, height: Int, withTransparency: Boolean): ByteArray {
        val raw = ByteArray((width * 3 + 1) * height)
        var cursor = 0
        repeat(height) {
            raw[cursor++] = 0
            repeat(width) {
                raw[cursor++] = 0x11
                raw[cursor++] = 0x22
                raw[cursor++] = 0x33
            }
        }
        val chunks = ArrayList<ByteArray>()
        chunks += chunk("IHDR", ihdr(width, height, bitDepth = 8, colorType = 2))
        if (withTransparency) {
            chunks += chunk(
                "tRNS",
                byteArrayOf(0x00, 0x11, 0x00, 0x22, 0x00, 0x33),
            )
        }
        chunks += chunk("IDAT", deflate(raw))
        chunks += chunk("IEND", ByteArray(0))
        return assemble(chunks)
    }

    private fun ihdr(width: Int, height: Int, bitDepth: Int, colorType: Int): ByteArray =
        ByteBuffer.allocate(13).order(ByteOrder.BIG_ENDIAN).apply {
            putInt(width)
            putInt(height)
            put(bitDepth.toByte())
            put(colorType.toByte())
            put(0)
            put(0)
            put(0)
        }.array()

    private fun assemble(chunks: List<ByteArray>): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(MAGIC)
        for (chunk in chunks) out.write(chunk)
        return out.toByteArray()
    }

    private fun chunk(type: String, data: ByteArray): ByteArray {
        val typeBytes = type.toByteArray(Charsets.US_ASCII)
        val out = ByteArrayOutputStream()
        out.write(ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN).putInt(data.size).array())
        out.write(typeBytes)
        out.write(data)
        val crc = CRC32()
        crc.update(typeBytes)
        crc.update(data)
        out.write(ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN).putInt(crc.value.toInt()).array())
        return out.toByteArray()
    }

    private fun deflate(bytes: ByteArray): ByteArray {
        val deflater = Deflater()
        try {
            deflater.setInput(bytes)
            deflater.finish()
            val out = ByteArrayOutputStream()
            val buffer = ByteArray(4096)
            while (!deflater.finished()) {
                val count = deflater.deflate(buffer)
                out.write(buffer, 0, count)
            }
            return out.toByteArray()
        } finally {
            deflater.end()
        }
    }

    private val MAGIC = byteArrayOf(
        0x89.toByte(),
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
    )
}
