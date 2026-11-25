package de.feldexa.app.delivery

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T107 host-JVM tests for the `suggestedName` hygiene of `delivery.save`
 * (`contracts/platform-channel.md` §7).
 *
 * Evidence class `NONE`: pure string policy, no Android runtime. The real SAF
 * write, share grant, and print dialog are instrumented/manual (§12).
 */
class DeliveryNamesTest {

    @Test
    fun keepsAnOrdinaryTitleAndAppendsThePdfSuffix() {
        assertEquals("Antrag_ausgefuellt.pdf", DeliveryNames.sanitizeSuggestedName("Antrag_ausgefuellt"))
        assertEquals("Antrag.pdf", DeliveryNames.sanitizeSuggestedName("Antrag.pdf"))
        assertEquals("Antrag.pdf", DeliveryNames.sanitizeSuggestedName("  Antrag  "))
    }

    @Test
    fun stripsDirectoryComponentsSoNoPathSurvives() {
        assertEquals("Antrag.pdf", DeliveryNames.sanitizeSuggestedName("/sdcard/Download/Antrag.pdf"))
        assertEquals("Antrag.pdf", DeliveryNames.sanitizeSuggestedName("..\\..\\Windows\\Antrag"))
        assertEquals("Antrag.pdf", DeliveryNames.sanitizeSuggestedName("../../Antrag"))
    }

    @Test
    fun removesControlCharactersAndFallsBackWhenNothingRemains() {
        val sanitized = DeliveryNames.sanitizeSuggestedName("Ant\u0000rag\u0007")
        assertEquals("Antrag.pdf", sanitized)
        assertEquals(
            DeliveryNames.DEFAULT_NAME + ".pdf",
            DeliveryNames.sanitizeSuggestedName("\u0000\u0001"),
        )
        assertEquals(
            DeliveryNames.DEFAULT_NAME + ".pdf",
            DeliveryNames.sanitizeSuggestedName(null),
        )
        assertEquals(
            DeliveryNames.DEFAULT_NAME + ".pdf",
            DeliveryNames.sanitizeSuggestedName("..."),
        )
    }

    @Test
    fun capsTheWholeNameAtTheContractLength() {
        val sanitized = DeliveryNames.sanitizeSuggestedName("T".repeat(400))
        assertEquals(DeliveryNames.MAX_SUGGESTED_NAME_LENGTH, sanitized.length)
        assertTrue(sanitized.endsWith(".pdf"))
    }

    @Test
    fun neverContainsAPathSeparatorOrAnUppercaseSuffix() {
        for (raw in listOf("a/b/c", "C:\\temp\\x", "Ordner/", "x.PDF", "x.pdf")) {
            val sanitized = DeliveryNames.sanitizeSuggestedName(raw)
            assertFalse(sanitized.contains('/'))
            assertFalse(sanitized.contains('\\'))
            assertFalse(sanitized.endsWith(".PDF"))
            assertTrue(sanitized.endsWith(".pdf"))
        }
    }
}
