package de.feldexa.app.storage

import android.security.keystore.KeyInfo
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.security.KeyStore
import java.util.UUID
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * T025 `EMULATOR`/`DEVICE` tests against the real `AndroidKeyStore`.
 *
 * Safety rule: this class runs under the production application id, so it must
 * never enumerate, create, or delete a production aggregate alias. Every alias
 * used here is prefixed with a unique `feldexa.test.v1.<runToken>.` namespace
 * by [IsolatedTestBackend]. Cleanup deletes only the exact physical aliases
 * tracked by that backend instance; there is no `KeyStore.aliases()` sweep and
 * no production prefix match.
 *
 * The test uses the TEE path (`strongBoxSupported = false`) so alias mapping is
 * deterministic on every emulator/device. StrongBox selection remains covered
 * by the JVM policy tests; it is not a production-alias concern.
 */
@RunWith(AndroidJUnit4::class)
class KeystoreServiceInstrumentedTest {

    private lateinit var keyStore: KeyStore
    private lateinit var backend: IsolatedTestBackend
    private lateinit var service: KeystoreService

    private val documentOne = document()
    private val documentTwo = document()
    private val templateOne = template()

    @Before
    fun setUp() {
        keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        backend = IsolatedTestBackend()
        // Fail before touching Keystore if the isolation guard is broken.
        backend.validateIsolation(documentOne)
        service = KeystoreService(backend, strongBoxSupported = false)
    }

    @After
    fun tearDown() {
        backend.deleteCreatedTestAliases()
    }

    @Test
    fun realKeystoreWrapUnwrapRoundTripAndNoMasterAlias() {
        service.createAggregateKey(documentOne)

        val dek = randomDek()
        val wrapped = service.wrapDek(documentOne, dek)

        assertEquals(12, wrapped.wrapIv.size)
        assertEquals(48, wrapped.wrappedKey.size)
        assertTrue(dek.contentEquals(service.unwrapDek(documentOne, wrapped)))
        assertTrue(backend.hasTestAlias(documentOne))
        assertFalse(backend.containsLogicalAlias("feldexa.master.v1"))
    }

    @Test
    fun providerGeneratesFreshTwelveByteIvForEveryWrap() {
        service.createAggregateKey(documentOne)

        val first = service.wrapDek(documentOne, randomDek())
        val second = service.wrapDek(documentOne, randomDek())

        assertEquals(12, first.wrapIv.size)
        assertEquals(12, second.wrapIv.size)
        assertFalse(first.wrapIv.contentEquals(second.wrapIv))
        service.unwrapDek(documentOne, first)
        service.unwrapDek(documentOne, second)
    }

    @Test
    fun keyIsNonExportableAndDoesNotRequireUserAuthentication() {
        service.createAggregateKey(documentOne)

        val key = keyStore.getKey(backend.physicalAlias(documentOne), null) as SecretKey
        val encoded = try {
            key.encoded
        } catch (failure: UnsupportedOperationException) {
            null
        }
        assertNull(encoded)

        val keyInfo = keyInfo(documentOne)
        assertFalse(keyInfo.isUserAuthenticationRequired)
        assertEquals(256, keyInfo.keySize)
    }

    @Test
    fun eachAggregateUsesItsOwnDistinctAlias() {
        service.createAggregateKey(documentOne)
        service.createAggregateKey(documentTwo)
        service.createAggregateKey(templateOne)

        assertTrue(backend.hasTestAlias(documentOne))
        assertTrue(backend.hasTestAlias(documentTwo))
        assertTrue(backend.hasTestAlias(templateOne))
        assertFalse(backend.containsLogicalAlias("feldexa.master.v1"))
    }

    @Test
    fun oneLostAliasIsAggregateSave002AndSiblingsStillLoad() {
        service.createAggregateKey(documentOne)
        service.createAggregateKey(documentTwo)
        service.createAggregateKey(templateOne)
        val siblingDek = randomDek()
        val siblingWrapped = service.wrapDek(documentTwo, siblingDek)
        val templateWrapped = service.wrapDek(templateOne, randomDek())

        backend.deleteTestAlias(documentOne)

        val failure = assertThrows(KeyUnavailableException::class.java) {
            service.wrapDek(documentOne, randomDek())
        }
        assertEquals("SAVE-002", failure.code)
        assertFalse(failure.retryable)

        assertTrue(
            siblingDek.contentEquals(service.unwrapDek(documentTwo, siblingWrapped)),
        )
        service.unwrapDek(templateOne, templateWrapped)
    }

    @Test
    fun deletingEveryAliasIsGlobalSave008() {
        service.createAggregateKey(documentOne)
        service.createAggregateKey(documentTwo)

        backend.deleteTestAlias(documentOne)
        backend.deleteTestAlias(documentTwo)

        val failure = assertThrows(KeystoreUnavailableException::class.java) {
            service.wrapDek(documentOne, randomDek())
        }
        assertEquals("SAVE-008", failure.code)
        assertFalse(failure.retryable)
    }

    @Test
    fun createIsIdempotentAgainstTheRealKeystore() {
        service.createAggregateKey(documentOne)
        service.createAggregateKey(documentOne)

        val dek = randomDek()
        val wrapped = service.wrapDek(documentOne, dek)
        assertTrue(dek.contentEquals(service.unwrapDek(documentOne, wrapped)))
    }

    @Test
    fun deleteRemovesOnlyTheTargetAlias() {
        service.createAggregateKey(documentOne)
        service.createAggregateKey(documentTwo)
        service.createAggregateKey(templateOne)

        assertTrue(service.deleteAggregateKey(documentOne))

        assertFalse(backend.hasTestAlias(documentOne))
        assertTrue(backend.hasTestAlias(documentTwo))
        assertTrue(backend.hasTestAlias(templateOne))
    }

    @Test
    fun sweepRemovesOnlyAliasesWithoutAnAggregateDirectory() {
        service.createAggregateKey(documentOne)
        service.createAggregateKey(documentTwo)

        val result = service.sweepOrphanAliases { ref -> ref == documentOne }

        assertEquals(1, result.removedAliases)
        assertEquals(1, result.retainedAliases)
        assertTrue(backend.hasTestAlias(documentOne))
        assertFalse(backend.hasTestAlias(documentTwo))
    }

    @Test
    fun storeStatusReportsPerAggregateAndGlobalCases() {
        service.createAggregateKey(documentOne)
        service.createAggregateKey(documentTwo)

        val healthy = service.storeKeyStatus(listOf(documentOne, documentTwo))
        assertTrue(healthy.keyAvailable)
        assertFalse(healthy.globalFailure)

        backend.deleteTestAlias(documentOne)
        val aggregateLoss = service.storeKeyStatus(listOf(documentOne, documentTwo))
        assertFalse(aggregateLoss.keyAvailable)
        assertFalse(aggregateLoss.globalFailure)
        assertEquals("SAVE-002", aggregateLoss.reasonCode)

        backend.deleteTestAlias(documentTwo)
        val globalLoss = service.storeKeyStatus(listOf(documentOne, documentTwo))
        assertFalse(globalLoss.keyAvailable)
        assertTrue(globalLoss.globalFailure)
        assertEquals("SAVE-008", globalLoss.reasonCode)
    }

    @Test
    fun testAliasesAreIsolatedFromProductionAliases() {
        service.createAggregateKey(documentOne)

        val physical = backend.physicalAlias(documentOne)
        assertTrue(physical.startsWith(IsolatedTestBackend.NAMESPACE_PREFIX))
        assertTrue(keyStore.containsAlias(physical))
        // The production alias is never created by this test; checking its
        // absence is read-only and does not delete anything.
        assertFalse(keyStore.containsAlias(documentOne.alias))
    }

    @Test
    fun cleanupDoesNotDeleteForeignTestAlias() {
        val foreignBackend = AndroidKeystoreBackend()
        val foreignAlias = "feldexa.test.v1.${UUID.randomUUID()}.foreign"
        foreignBackend.generateAesKey(foreignAlias, strongBox = false)
        try {
            service.createAggregateKey(documentOne)

            backend.deleteCreatedTestAliases()

            assertTrue(foreignBackend.containsAlias(foreignAlias))
            assertFalse(backend.hasTestAlias(documentOne))
        } finally {
            foreignBackend.deleteAlias(foreignAlias)
        }
    }

    private fun keyInfo(ref: AggregateRef): KeyInfo {
        val key = keyStore.getKey(backend.physicalAlias(ref), null) as SecretKey
        val factory = SecretKeyFactory.getInstance(
            key.algorithm,
            "AndroidKeyStore",
        )
        return factory.getKeySpec(key, KeyInfo::class.java) as KeyInfo
    }

    private fun document() = AggregateRef(
        AggregateKind.DOCUMENT,
        UUID.randomUUID().toString(),
    )

    private fun template() = AggregateRef(
        AggregateKind.TEMPLATE,
        UUID.randomUUID().toString(),
    )

    private fun randomDek(): ByteArray {
        val dek = ByteArray(KeystoreService.DEK_SIZE_BYTES)
        java.security.SecureRandom().nextBytes(dek)
        return dek
    }

    /**
     * Test-only Keystore backend that maps every logical T025 alias into a
     * unique `feldexa.test.v1.<runToken>.` namespace. The production
     * `AndroidKeystoreBackend` is still used underneath, so the real Keystore
     * crypto and alias semantics are exercised.
     *
     * Cleanup is deliberate: [deleteCreatedTestAliases] iterates the exact
     * physical aliases this instance generated. It never enumerates the
     * KeyStore and never matches a production prefix.
     */
    private class IsolatedTestBackend : KeystoreBackend {

        private val delegate = AndroidKeystoreBackend()
        private val namespace =
            NAMESPACE_PREFIX + UUID.randomUUID().toString() + "."
        private val createdAliases = LinkedHashSet<String>()
        private val logicalByPhysical = HashMap<String, String>()

        fun physicalAlias(ref: AggregateRef): String = physicalAlias(ref.alias)

        fun physicalAlias(alias: String): String = namespace + alias

        fun hasTestAlias(ref: AggregateRef): Boolean =
            delegate.containsAlias(physicalAlias(ref))

        fun containsLogicalAlias(alias: String): Boolean =
            delegate.containsAlias(physicalAlias(alias))

        fun validateIsolation(ref: AggregateRef) {
            check(namespace.startsWith(NAMESPACE_PREFIX))
            check(physicalAlias(ref) != ref.alias)
            check(physicalAlias(ref).startsWith(NAMESPACE_PREFIX))
        }

        override fun providerAvailable(): Boolean = delegate.providerAvailable()

        override fun containsAlias(alias: String): Boolean =
            delegate.containsAlias(physicalAlias(alias))

        override fun listAliases(): Set<String> =
            createdAliases.mapNotNull { physical ->
                logicalByPhysical[physical]?.takeIf {
                    delegate.containsAlias(physical)
                }
            }.toSet()

        override fun isKeyUsable(alias: String): Boolean =
            delegate.isKeyUsable(physicalAlias(alias))

        override fun generateAesKey(alias: String, strongBox: Boolean) {
            val physical = physicalAlias(alias)
            createdAliases += physical
            logicalByPhysical[physical] = alias
            delegate.generateAesKey(physical, strongBox)
        }

        override fun deleteAlias(alias: String): Boolean {
            val physical = physicalAlias(alias)
            val deleted = delegate.deleteAlias(physical)
            if (deleted) {
                createdAliases.remove(physical)
                logicalByPhysical.remove(physical)
            }
            return deleted
        }

        fun deleteTestAlias(ref: AggregateRef): Boolean {
            val physical = physicalAlias(ref)
            val deleted = delegate.deleteAlias(physical)
            if (deleted) {
                createdAliases.remove(physical)
                logicalByPhysical.remove(physical)
            }
            return deleted
        }

        override fun encrypt(
            alias: String,
            aad: ByteArray,
            plaintext: ByteArray,
        ): WrappedDek =
            delegate.encrypt(physicalAlias(alias), aad, plaintext)

        override fun decrypt(
            alias: String,
            iv: ByteArray,
            aad: ByteArray,
            ciphertext: ByteArray,
        ): ByteArray =
            delegate.decrypt(physicalAlias(alias), iv, aad, ciphertext)

        /**
         * Deletes only exact aliases recorded by [generateAesKey], and only if
         * they still exist in the test namespace. No global enumeration, no
         * production prefix match.
         */
        fun deleteCreatedTestAliases() {
            for (physical in createdAliases.toList()) {
                if (!physical.startsWith(NAMESPACE_PREFIX)) continue
                if (delegate.containsAlias(physical)) {
                    runCatching { delegate.deleteAlias(physical) }
                }
            }
            createdAliases.clear()
            logicalByPhysical.clear()
        }

        companion object {
            const val NAMESPACE_PREFIX: String = "feldexa.test.v1."
        }
    }
}
