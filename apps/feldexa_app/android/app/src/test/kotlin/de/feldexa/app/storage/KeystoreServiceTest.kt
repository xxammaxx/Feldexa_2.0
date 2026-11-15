package de.feldexa.app.storage

import java.security.InvalidKeyException
import java.security.ProviderException
import java.security.SecureRandom
import java.util.UUID
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T025 JVM policy tests.
 *
 * These run without an Android runtime and prove alias construction,
 * lifecycle ordering, StrongBox→TEE fallback, DEK wrap/unwrap, and the
 * `SAVE-002`/`SAVE-008`/`SAVE-003` mapping. They are `NONE` host checks; real
 * `AndroidKeyStore` behavior is covered by the instrumented test and is not
 * claimed here.
 */
class KeystoreServiceTest {

    private val documentId = UUID.randomUUID().toString()
    private val siblingDocumentId = UUID.randomUUID().toString()
    private val templateId = UUID.randomUUID().toString()

    private fun document(id: String = documentId) =
        AggregateRef(AggregateKind.DOCUMENT, id)

    private fun template(id: String = templateId) =
        AggregateRef(AggregateKind.TEMPLATE, id)

    private fun service(
        backend: FakeBackend,
        strongBoxSupported: Boolean = false,
        sleeps: MutableList<Long> = mutableListOf(),
    ) = KeystoreService(
        backend = backend,
        strongBoxSupported = strongBoxSupported,
        sleeper = { sleeps += it },
    )

    @Test
    fun `aliases use the documented per-aggregate prefixes`() {
        assertEquals("feldexa.doc.v1.$documentId", document().alias)
        assertEquals("feldexa.tpl.v1.$templateId", template().alias)
        assertFalse(document().alias.startsWith("feldexa.tpl."))
        assertFalse(template().alias.startsWith("feldexa.doc."))
        assertNotEquals("feldexa.master.v1", document().alias)
    }

    @Test
    fun `create generates one distinct key per document and template`() {
        val backend = FakeBackend()
        val service = service(backend)

        service.createAggregateKey(document())
        service.createAggregateKey(document(siblingDocumentId))
        service.createAggregateKey(template())

        assertEquals(
            listOf(document().alias, document(siblingDocumentId).alias, template().alias),
            backend.generated.map { it.first },
        )
        assertTrue(backend.generated.none { it.first.startsWith("feldexa.master.") })
        assertTrue(backend.keys.keys.none { it.startsWith("feldexa.master.") })
    }

    @Test
    fun `create is idempotent and never replaces an existing key`() {
        val backend = FakeBackend()
        val service = service(backend)

        service.createAggregateKey(document())
        val firstKey = backend.keys.getValue(document().alias).copyOf()
        service.createAggregateKey(document())

        assertEquals(1, backend.generated.size)
        assertTrue(firstKey.contentEquals(backend.keys.getValue(document().alias)))
    }

    @Test
    fun `create rejects an invalid aggregate id before touching the keystore`() {
        val backend = FakeBackend()
        val service = service(backend)

        val failure = assertThrows(PlatformSecurityException::class.java) {
            service.createAggregateKey(AggregateRef(AggregateKind.DOCUMENT, "not-a-uuid"))
        }

        assertEquals("PLT-002", failure.code)
        assertEquals(0, backend.providerChecks)
        assertTrue(backend.generated.isEmpty())
    }

    @Test
    fun `uppercase uuid is rejected before keystore access`() {
        val backend = FakeBackend()
        val service = service(backend)

        assertThrows(PlatformSecurityException::class.java) {
            service.createAggregateKey(
                AggregateRef(AggregateKind.DOCUMENT, documentId.uppercase()),
            )
        }
        assertEquals(0, backend.providerChecks)
    }

    @Test
    fun `provider outage retries once and then succeeds`() {
        val backend = FakeBackend(providerFailuresRemaining = 1)
        val sleeps = mutableListOf<Long>()
        val service = service(backend, sleeps = sleeps)

        service.createAggregateKey(document())

        assertEquals(2, backend.providerChecks)
        assertEquals(listOf(KeystoreService.PROVIDER_RETRY_DELAY_MS), sleeps)
        assertEquals(listOf(document().alias to false), backend.generated)
    }

    @Test
    fun `persistent provider outage is global SAVE-008 with no partial key`() {
        val backend = FakeBackend(providerFailuresRemaining = 2)
        val sleeps = mutableListOf<Long>()
        val service = service(backend, sleeps = sleeps)

        val failure = assertThrows(KeystoreUnavailableException::class.java) {
            service.createAggregateKey(document())
        }

        assertEquals("SAVE-008", failure.code)
        assertTrue(failure.retryable)
        assertEquals(2, backend.providerChecks)
        assertEquals(1, sleeps.size)
        assertTrue(backend.generated.isEmpty())
        assertTrue(backend.keys.isEmpty())
    }

    @Test
    fun `existing unusable key is reported as aggregate SAVE-002 and not regenerated`() {
        val backend = FakeBackend()
        val service = service(backend)
        backend.keys[document().alias] = ByteArray(32)
        backend.unusable += document().alias

        val failure = assertThrows(KeyUnavailableException::class.java) {
            service.createAggregateKey(document())
        }

        assertEquals("SAVE-002", failure.code)
        assertFalse(failure.retryable)
        assertTrue(backend.generated.isEmpty())
    }

    @Test
    fun `strongbox failure falls back to the tee`() {
        val backend = FakeBackend(strongBoxFailure = true)
        val service = service(backend, strongBoxSupported = true)

        service.createAggregateKey(document())

        assertEquals(
            listOf(document().alias to true, document().alias to false),
            backend.generated,
        )
    }

    @Test
    fun `strongbox is used when supported and succeeds`() {
        val backend = FakeBackend()
        val service = service(backend, strongBoxSupported = true)

        service.createAggregateKey(document())

        assertEquals(listOf(document().alias to true), backend.generated)
    }

    @Test
    fun `without strongbox only the tee is used`() {
        val backend = FakeBackend()
        val service = service(backend, strongBoxSupported = false)

        service.createAggregateKey(document())

        assertEquals(listOf(document().alias to false), backend.generated)
    }

    @Test
    fun `wrap and unwrap round-trip and use fresh ivs`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())
        val dek = randomBytes(KeystoreService.DEK_SIZE_BYTES)

        val first = service.wrapDek(document(), dek)
        val second = service.wrapDek(document(), dek)

        assertEquals(KeystoreService.WRAP_IV_SIZE_BYTES, first.wrapIv.size)
        assertEquals(KeystoreService.WRAPPED_DEK_SIZE_BYTES, first.wrappedKey.size)
        assertFalse(first.wrapIv.contentEquals(second.wrapIv))
        assertTrue(dek.contentEquals(service.unwrapDek(document(), first)))
        assertTrue(dek.contentEquals(service.unwrapDek(document(), second)))
    }

    @Test
    fun `wrap uses the FXC1-DEK aad`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())

        service.wrapDek(document(), randomBytes(KeystoreService.DEK_SIZE_BYTES))

        assertEquals(
            KeystoreService.WRAP_AAD,
            backend.lastAad?.toString(Charsets.UTF_8),
        )
    }

    @Test
    fun `wrap uses the provider-generated iv`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())

        val wrapped = service.wrapDek(document(), randomBytes(KeystoreService.DEK_SIZE_BYTES))

        assertTrue(backend.lastEncryptIv!!.contentEquals(wrapped.wrapIv))
        assertEquals(KeystoreService.WRAP_IV_SIZE_BYTES, wrapped.wrapIv.size)
    }

    @Test
    fun `unwrap uses the stored wrap iv`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())
        val wrapped = service.wrapDek(document(), randomBytes(KeystoreService.DEK_SIZE_BYTES))

        service.unwrapDek(document(), wrapped)

        assertTrue(backend.lastDecryptIv!!.contentEquals(wrapped.wrapIv))
    }

    @Test
    fun `wrap rejects a provider iv that is not twelve bytes`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())
        backend.providerIvOverride = ByteArray(16)

        val failure = assertThrows(KeystoreUnavailableException::class.java) {
            service.wrapDek(document(), randomBytes(KeystoreService.DEK_SIZE_BYTES))
        }

        assertEquals("SAVE-008", failure.code)
        assertTrue(failure.retryable)
    }

    @Test
    fun `wrap rejects a provider wrapped key of the wrong length`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())
        backend.truncateCiphertext = true

        val failure = assertThrows(KeystoreUnavailableException::class.java) {
            service.wrapDek(document(), randomBytes(KeystoreService.DEK_SIZE_BYTES))
        }

        assertEquals("SAVE-008", failure.code)
        assertTrue(failure.retryable)
    }

    @Test
    fun `wrap rejects a dek of the wrong length`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())

        assertThrows(IllegalArgumentException::class.java) {
            service.wrapDek(document(), ByteArray(KeystoreService.DEK_SIZE_BYTES - 1))
        }
    }

    @Test
    fun `missing key with a usable sibling is aggregate SAVE-002`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())
        service.createAggregateKey(document(siblingDocumentId))
        backend.deleteAlias(document().alias)

        val failure = assertThrows(KeyUnavailableException::class.java) {
            service.wrapDek(document(), randomBytes(KeystoreService.DEK_SIZE_BYTES))
        }

        assertEquals("SAVE-002", failure.code)
        assertFalse(failure.retryable)
        // The sibling is untouched and still usable.
        val dek = randomBytes(KeystoreService.DEK_SIZE_BYTES)
        val wrapped = service.wrapDek(document(siblingDocumentId), dek)
        assertTrue(dek.contentEquals(service.unwrapDek(document(siblingDocumentId), wrapped)))
    }

    @Test
    fun `invalidated key with a usable sibling is aggregate SAVE-002`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())
        service.createAggregateKey(template())
        backend.unusable += document().alias

        assertThrows(KeyUnavailableException::class.java) {
            service.wrapDek(document(), randomBytes(KeystoreService.DEK_SIZE_BYTES))
        }
    }

    @Test
    fun `missing key with no other key is global SAVE-008 without retry`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())
        backend.deleteAlias(document().alias)

        val failure = assertThrows(KeystoreUnavailableException::class.java) {
            service.wrapDek(document(), randomBytes(KeystoreService.DEK_SIZE_BYTES))
        }

        assertEquals("SAVE-008", failure.code)
        assertFalse(failure.retryable)
    }

    @Test
    fun `unwrap with a missing key maps to the same isolation rules`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())
        service.createAggregateKey(document(siblingDocumentId))
        val wrapped = service.wrapDek(document(), randomBytes(KeystoreService.DEK_SIZE_BYTES))
        backend.deleteAlias(document().alias)

        assertThrows(KeyUnavailableException::class.java) {
            service.unwrapDek(document(), wrapped)
        }

        backend.deleteAlias(document(siblingDocumentId).alias)
        assertThrows(KeystoreUnavailableException::class.java) {
            service.unwrapDek(document(), wrapped)
        }
    }

    @Test
    fun `usable kek with a tampered wrapped key is integrity SAVE-003 not key loss`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())
        val dek = randomBytes(KeystoreService.DEK_SIZE_BYTES)
        val wrapped = service.wrapDek(document(), dek)
        wrapped.wrappedKey[0] = (wrapped.wrappedKey[0].toInt() xor 0x01).toByte()

        val failure = assertThrows(CorruptDataException::class.java) {
            service.unwrapDek(document(), wrapped)
        }

        assertEquals("SAVE-003", failure.code)
        assertFalse(failure.retryable)
        // Integrity damage, not key loss: the KEK remains available and a
        // fresh wrap/unwrap still works for the same aggregate.
        assertTrue(service.hasAggregateKey(document()))
        val fresh = service.wrapDek(document(), dek)
        assertTrue(dek.contentEquals(service.unwrapDek(document(), fresh)))
    }

    @Test
    fun `wrong wrap iv or wrapped-key length is corrupt data`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())
        val wrapped = service.wrapDek(document(), randomBytes(KeystoreService.DEK_SIZE_BYTES))

        assertThrows(CorruptDataException::class.java) {
            service.unwrapDek(
                document(),
                WrappedDek(ByteArray(KeystoreService.WRAP_IV_SIZE_BYTES - 1), wrapped.wrappedKey),
            )
        }
        assertThrows(CorruptDataException::class.java) {
            service.unwrapDek(
                document(),
                WrappedDek(wrapped.wrapIv, ByteArray(KeystoreService.WRAPPED_DEK_SIZE_BYTES - 1)),
            )
        }
    }

    @Test
    fun `provider failure during unwrap is retryable SAVE-008`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())
        val wrapped = service.wrapDek(document(), randomBytes(KeystoreService.DEK_SIZE_BYTES))
        backend.decryptProviderFailure = true

        val failure = assertThrows(KeystoreUnavailableException::class.java) {
            service.unwrapDek(document(), wrapped)
        }

        assertEquals("SAVE-008", failure.code)
        assertTrue(failure.retryable)
    }

    @Test
    fun `delete removes only the target alias`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())
        service.createAggregateKey(document(siblingDocumentId))
        service.createAggregateKey(template())

        assertTrue(service.deleteAggregateKey(document()))

        assertFalse(backend.containsAlias(document().alias))
        assertTrue(backend.containsAlias(document(siblingDocumentId).alias))
        assertTrue(backend.containsAlias(template().alias))
    }

    @Test
    fun `delete of an absent alias is idempotent`() {
        val backend = FakeBackend()
        val service = service(backend)

        assertTrue(service.deleteAggregateKey(document()))
    }

    @Test
    fun `delete while the provider is unavailable removes nothing`() {
        val backend = FakeBackend(providerFailuresRemaining = 2)
        val service = service(backend)

        assertFalse(service.deleteAggregateKey(document()))
        assertEquals(0, backend.deleteCalls)
    }

    @Test
    fun `sweep removes only aliases without an aggregate directory`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())
        service.createAggregateKey(document(siblingDocumentId))
        service.createAggregateKey(template())
        backend.keys["feldexa.doc.v1.not-a-uuid"] = ByteArray(32)
        backend.keys["foreign.alias"] = ByteArray(32)

        val result = service.sweepOrphanAliases { ref ->
            ref == document() || ref == template()
        }

        assertEquals(2, result.removedAliases)
        assertEquals(2, result.retainedAliases)
        assertEquals(0, result.failedAliases)
        assertTrue(backend.containsAlias(document().alias))
        assertTrue(backend.containsAlias(template().alias))
        assertFalse(backend.containsAlias(document(siblingDocumentId).alias))
        assertFalse(backend.containsAlias("feldexa.doc.v1.not-a-uuid"))
        assertTrue(backend.containsAlias("foreign.alias"))
    }

    @Test
    fun `sweep keeps every alias whose directory exists`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())
        service.createAggregateKey(template())

        val result = service.sweepOrphanAliases { true }

        assertEquals(0, result.removedAliases)
        assertEquals(2, result.retainedAliases)
        assertTrue(backend.containsAlias(document().alias))
        assertTrue(backend.containsAlias(template().alias))
    }

    @Test
    fun `sweep fails closed when the provider is unavailable`() {
        val backend = FakeBackend(providerFailuresRemaining = 2)
        val service = service(backend)
        backend.keys[document().alias] = ByteArray(32)

        assertThrows(KeystoreUnavailableException::class.java) {
            service.sweepOrphanAliases { false }
        }
        assertEquals(0, backend.deleteCalls)
    }

    @Test
    fun `store status is available when every known key is usable`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())
        service.createAggregateKey(template())

        val status = service.storeKeyStatus(
            listOf(document(), template()),
        )

        assertTrue(status.providerAvailable)
        assertTrue(status.keyAvailable)
        assertFalse(status.globalFailure)
        assertNull(status.reasonCode)
        assertTrue(status.unavailableAggregates.isEmpty())
    }

    @Test
    fun `one missing key is a non-global SAVE-002 summary`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())
        service.createAggregateKey(document(siblingDocumentId))
        backend.deleteAlias(document().alias)

        val status = service.storeKeyStatus(
            listOf(document(), document(siblingDocumentId)),
        )

        assertTrue(status.providerAvailable)
        assertFalse(status.keyAvailable)
        assertFalse(status.globalFailure)
        assertEquals("SAVE-002", status.reasonCode)
        assertEquals(listOf(document()), status.unavailableAggregates)
    }

    @Test
    fun `all keys missing is a global SAVE-008 reset`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())
        service.createAggregateKey(template())
        backend.deleteAlias(document().alias)
        backend.deleteAlias(template().alias)

        val status = service.storeKeyStatus(listOf(document(), template()))

        assertTrue(status.providerAvailable)
        assertFalse(status.keyAvailable)
        assertTrue(status.globalFailure)
        assertEquals("SAVE-008", status.reasonCode)
        assertEquals(listOf(document(), template()), status.unavailableAggregates)
    }

    @Test
    fun `a single missing aggregate is global because no other key remains`() {
        val backend = FakeBackend()
        val service = service(backend)
        service.createAggregateKey(document())
        backend.deleteAlias(document().alias)

        val status = service.storeKeyStatus(listOf(document()))

        assertTrue(status.globalFailure)
        assertEquals("SAVE-008", status.reasonCode)
        assertFalse(status.keyAvailable)
    }

    @Test
    fun `provider outage in store status is global and non-fatal`() {
        val backend = FakeBackend(providerFailuresRemaining = 2)
        val service = service(backend)

        val status = service.storeKeyStatus(listOf(document(), template()))

        assertFalse(status.providerAvailable)
        assertFalse(status.keyAvailable)
        assertTrue(status.globalFailure)
        assertEquals("SAVE-008", status.reasonCode)
        assertEquals(listOf(document(), template()), status.unavailableAggregates)
    }

    @Test
    fun `empty known store is available when the provider is up`() {
        val backend = FakeBackend()
        val service = service(backend)

        val status = service.storeKeyStatus(emptyList())

        assertTrue(status.providerAvailable)
        assertTrue(status.keyAvailable)
        assertFalse(status.globalFailure)
        assertNull(status.reasonCode)
    }

    @Test
    fun `aggregate key states distinguish missing invalidated and available`() {
        val backend = FakeBackend()
        val service = service(backend)
        assertEquals(AggregateKeyState.MISSING, service.aggregateKeyState(document()))

        service.createAggregateKey(document())
        assertEquals(AggregateKeyState.AVAILABLE, service.aggregateKeyState(document()))

        backend.unusable += document().alias
        assertEquals(AggregateKeyState.INVALIDATED, service.aggregateKeyState(document()))

        val down = FakeBackend(providerFailuresRemaining = 2)
        assertEquals(
            AggregateKeyState.PROVIDER_UNAVAILABLE,
            service(down).aggregateKeyState(document()),
        )
    }

    @Test
    fun `has aggregate key is non-fatal during a provider outage`() {
        val backend = FakeBackend(providerFailuresRemaining = 2)
        val service = service(backend)

        assertFalse(service.hasAggregateKey(document()))
    }

    @Test
    fun `exception text never contains aggregate identity`() {
        val keyFailure = KeyUnavailableException()
        assertEquals("storage.keyUnavailable", keyFailure.message)
        assertEquals("KeyUnavailableException(code=SAVE-002, retryable=false)", keyFailure.toString())
        assertFalse(keyFailure.toString().contains(documentId))

        val globalFailure = KeystoreUnavailableException(retryable = false)
        assertEquals("storage.keystoreUnavailable", globalFailure.message)
        assertEquals("SAVE-008", globalFailure.code)
        assertFalse(globalFailure.retryable)

        val corrupt = CorruptDataException()
        assertEquals("storage.corruptData", corrupt.message)
        assertEquals("SAVE-003", corrupt.code)

        val rejected = PlatformSecurityException()
        assertEquals("PLT-002", rejected.code)
        assertFalse(rejected.toString().contains(documentId))
    }

    private fun randomBytes(size: Int): ByteArray =
        ByteArray(size).also { SecureRandom().nextBytes(it) }

    /**
     * In-memory backend: real AES-GCM (so AAD and tag checks are genuine) with
     * deterministic failure switches for the provider, StrongBox, and
     * invalidation paths. Key bytes never leave this fake.
     */
    private class FakeBackend(
        var providerFailuresRemaining: Int = 0,
        var strongBoxFailure: Boolean = false,
        var decryptProviderFailure: Boolean = false,
    ) : KeystoreBackend {

        val keys = LinkedHashMap<String, ByteArray>()
        val unusable = mutableSetOf<String>()
        val generated = mutableListOf<Pair<String, Boolean>>()
        var providerChecks = 0
        var deleteCalls = 0
        var lastAad: ByteArray? = null
        var lastEncryptIv: ByteArray? = null
        var lastDecryptIv: ByteArray? = null
        var providerIvOverride: ByteArray? = null
        var truncateCiphertext = false
        var failDeletes = false

        private val random = SecureRandom()

        override fun providerAvailable(): Boolean {
            providerChecks++
            if (providerFailuresRemaining > 0) {
                providerFailuresRemaining--
                return false
            }
            return true
        }

        override fun containsAlias(alias: String): Boolean = keys.containsKey(alias)

        override fun listAliases(): Set<String> = keys.keys.toSet()

        override fun isKeyUsable(alias: String): Boolean =
            keys.containsKey(alias) && alias !in unusable

        override fun generateAesKey(alias: String, strongBox: Boolean) {
            generated += alias to strongBox
            if (strongBox && strongBoxFailure) {
                throw ProviderException("strongbox down")
            }
            keys[alias] = ByteArray(KEY_SIZE).also { SecureRandom().nextBytes(it) }
            unusable -= alias
        }

        override fun deleteAlias(alias: String): Boolean {
            deleteCalls++
            if (failDeletes) return false
            keys.remove(alias)
            unusable.remove(alias)
            return true
        }

        override fun encrypt(
            alias: String,
            aad: ByteArray,
            plaintext: ByteArray,
        ): WrappedDek {
            lastAad = aad.copyOf()
            // Mirrors Android Keystore: the provider, not the caller, supplies
            // the random 12-byte GCM IV when IND-CPA is required.
            val iv = providerIvOverride?.copyOf()
                ?: ByteArray(KeystoreService.WRAP_IV_SIZE_BYTES).also {
                    random.nextBytes(it)
                }
            lastEncryptIv = iv.copyOf()
            val ciphertext = cipher(Cipher.ENCRYPT_MODE, alias, iv, aad)
                .doFinal(plaintext)
            val stored = if (truncateCiphertext) {
                ciphertext.copyOf(ciphertext.size - 1)
            } else {
                ciphertext
            }
            return WrappedDek(iv, stored)
        }

        override fun decrypt(
            alias: String,
            iv: ByteArray,
            aad: ByteArray,
            ciphertext: ByteArray,
        ): ByteArray {
            if (decryptProviderFailure) throw ProviderException("provider down")
            lastDecryptIv = iv.copyOf()
            return try {
                cipher(Cipher.DECRYPT_MODE, alias, iv, aad).doFinal(ciphertext)
            } catch (failure: AEADBadTagException) {
                throw failure
            }
        }

        private fun cipher(
            mode: Int,
            alias: String,
            iv: ByteArray,
            aad: ByteArray,
        ): Cipher {
            if (alias in unusable) throw InvalidKeyException("invalidated")
            val key = keys[alias] ?: throw InvalidKeyException("missing")
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                mode,
                SecretKeySpec(key, "AES"),
                GCMParameterSpec(128, iv),
            )
            cipher.updateAAD(aad)
            return cipher
        }

        private companion object {
            const val KEY_SIZE = 32
        }
    }
}
