package de.feldexa.app.storage

import android.security.keystore.KeyInfo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
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
 * Required evidence class for T025's key lifecycle and key-loss isolation is
 * the Android runtime; these tests are executed with
 * `connectedDebugAndroidTest` on an allocated device/emulator. A JVM run or a
 * browser run is not a substitute.
 *
 * Aliases created by this class are removed in [setUp]/[tearDown] so a failed
 * test cannot make later tests read a sibling key as missing.
 */
@RunWith(AndroidJUnit4::class)
class KeystoreServiceInstrumentedTest {

    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var keyStore: KeyStore
    private lateinit var service: KeystoreService

    private val documentOne = document()
    private val documentTwo = document()
    private val templateOne = template()

    @Before
    fun setUp() {
        keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        deleteAllAggregateAliases()
        service = KeystoreService.forAndroid(context)
    }

    @After
    fun tearDown() {
        deleteAllAggregateAliases()
    }

    @Test
    fun realKeystoreWrapUnwrapRoundTripAndNoMasterAlias() {
        service.createAggregateKey(documentOne)

        val dek = randomDek()
        val wrapped = service.wrapDek(documentOne, dek)

        assertEquals(12, wrapped.wrapIv.size)
        assertEquals(48, wrapped.wrappedKey.size)
        assertTrue(dek.contentEquals(service.unwrapDek(documentOne, wrapped)))
        assertTrue(keyStore.containsAlias(documentOne.alias))
        assertFalse(keyStore.containsAlias("feldexa.master.v1"))
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

        val key = keyStore.getKey(documentOne.alias, null) as SecretKey
        val encoded = try {
            key.encoded
        } catch (failure: UnsupportedOperationException) {
            null
        }
        assertNull(encoded)

        val keyInfo = keyInfo(documentOne.alias)
        assertFalse(keyInfo.isUserAuthenticationRequired)
        assertEquals(256, keyInfo.keySize)
    }

    @Test
    fun eachAggregateUsesItsOwnDistinctAlias() {
        service.createAggregateKey(documentOne)
        service.createAggregateKey(documentTwo)
        service.createAggregateKey(templateOne)

        assertTrue(keyStore.containsAlias("feldexa.doc.v1.${documentOne.id}"))
        assertTrue(keyStore.containsAlias("feldexa.doc.v1.${documentTwo.id}"))
        assertTrue(keyStore.containsAlias("feldexa.tpl.v1.${templateOne.id}"))
        assertFalse(keyStore.containsAlias("feldexa.master.v1"))
    }

    @Test
    fun oneLostAliasIsAggregateSave002AndSiblingsStillLoad() {
        service.createAggregateKey(documentOne)
        service.createAggregateKey(documentTwo)
        service.createAggregateKey(templateOne)
        val siblingDek = randomDek()
        val siblingWrapped = service.wrapDek(documentTwo, siblingDek)
        val templateWrapped = service.wrapDek(templateOne, randomDek())

        keyStore.deleteEntry(documentOne.alias)

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

        keyStore.deleteEntry(documentOne.alias)
        keyStore.deleteEntry(documentTwo.alias)

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

        assertFalse(keyStore.containsAlias(documentOne.alias))
        assertTrue(keyStore.containsAlias(documentTwo.alias))
        assertTrue(keyStore.containsAlias(templateOne.alias))
    }

    @Test
    fun sweepRemovesOnlyAliasesWithoutAnAggregateDirectory() {
        service.createAggregateKey(documentOne)
        service.createAggregateKey(documentTwo)

        val result = service.sweepOrphanAliases { ref -> ref == documentOne }

        assertEquals(1, result.removedAliases)
        assertEquals(1, result.retainedAliases)
        assertTrue(keyStore.containsAlias(documentOne.alias))
        assertFalse(keyStore.containsAlias(documentTwo.alias))
    }

    @Test
    fun storeStatusReportsPerAggregateAndGlobalCases() {
        service.createAggregateKey(documentOne)
        service.createAggregateKey(documentTwo)

        val healthy = service.storeKeyStatus(listOf(documentOne, documentTwo))
        assertTrue(healthy.keyAvailable)
        assertFalse(healthy.globalFailure)

        keyStore.deleteEntry(documentOne.alias)
        val aggregateLoss = service.storeKeyStatus(listOf(documentOne, documentTwo))
        assertFalse(aggregateLoss.keyAvailable)
        assertFalse(aggregateLoss.globalFailure)
        assertEquals("SAVE-002", aggregateLoss.reasonCode)

        keyStore.deleteEntry(documentTwo.alias)
        val globalLoss = service.storeKeyStatus(listOf(documentOne, documentTwo))
        assertFalse(globalLoss.keyAvailable)
        assertTrue(globalLoss.globalFailure)
        assertEquals("SAVE-008", globalLoss.reasonCode)
    }

    private fun keyInfo(alias: String): KeyInfo {
        val key = keyStore.getKey(alias, null) as SecretKey
        val factory = SecretKeyFactory.getInstance(
            key.algorithm,
            "AndroidKeyStore",
        )
        return factory.getKeySpec(key, KeyInfo::class.java) as KeyInfo
    }

    private fun deleteAllAggregateAliases() {
        val aliases = keyStore.aliases()
        while (aliases.hasMoreElements()) {
            val alias = aliases.nextElement()
            if (alias.startsWith("feldexa.doc.v1.") ||
                alias.startsWith("feldexa.tpl.v1.")
            ) {
                keyStore.deleteEntry(alias)
            }
        }
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
}
