package de.feldexa.app.storage

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T025 security regression: the instrumented test runs under the production
 * application id, so its cleanup must never enumerate or delete production
 * aggregate aliases. This JVM test statically inspects the instrumentation
 * source and fails if a global prefix sweep, `KeyStore.aliases()` loop, or
 * direct production-alias deletion is reintroduced.
 *
 * This is a host-only safety net; it does not prove Android behavior.
 */
class InstrumentedKeystoreAliasSafetyTest {

    private val source: String = readInstrumentedTestSource()

    @Test
    fun `instrumented test has no global alias sweep`() {
        assertFalse(source.contains("deleteAllAggregateAliases"))
        assertFalse(source.contains("keyStore.aliases()"))
        assertFalse(source.contains("alias.startsWith(\"feldexa.doc.v1.\")"))
        assertFalse(source.contains("alias.startsWith(\"feldexa.tpl.v1.\")"))
        assertEquals(0, Regex("keyStore\\.deleteEntry").findAll(source).count())
    }

    @Test
    fun `instrumented aliases use a unique test namespace`() {
        assertTrue(source.contains("private class IsolatedTestBackend : KeystoreBackend"))
        assertTrue(source.contains("feldexa.test.v1."))
        assertTrue(source.contains("NAMESPACE_PREFIX + UUID.randomUUID()"))
        assertTrue(source.contains("check(physicalAlias(ref) != ref.alias)"))
        assertTrue(source.contains("validateIsolation"))
        assertTrue(source.contains("physicalAlias(ref).startsWith(NAMESPACE_PREFIX)"))
    }

    @Test
    fun `cleanup deletes only exact tracked test aliases`() {
        val cleanup = source
            .substringAfter("fun deleteCreatedTestAliases()")
            .substringBefore("companion object")

        assertTrue(cleanup.contains("for (physical in createdAliases.toList())"))
        assertTrue(
            cleanup.contains(
                "if (!physical.startsWith(NAMESPACE_PREFIX)) continue",
            ),
        )
        assertTrue(cleanup.contains("delegate.deleteAlias(physical)"))
        assertFalse(cleanup.contains("keyStore.aliases()"))
        assertFalse(cleanup.contains("feldexa.doc.v1."))
        assertFalse(cleanup.contains("feldexa.tpl.v1."))
    }

    private fun readInstrumentedTestSource(): String {
        val relative =
            "src/androidTest/kotlin/de/feldexa/app/storage/" +
                "KeystoreServiceInstrumentedTest.kt"
        val candidates = listOf(
            File(relative),
            File("app/$relative"),
            File("apps/feldexa_app/android/app/$relative"),
        )
        return candidates.firstOrNull { it.isFile }?.readText()
            ?: error("instrumented test source not found")
    }
}
