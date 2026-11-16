package de.feldexa.app.storage

import java.security.InvalidKeyException
import java.security.SecureRandom
import java.util.concurrent.atomic.AtomicInteger
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * T026 JVM test double for [KeystoreBackend].
 *
 * It performs real AES-256-GCM wrapping/unwrapping with random per-alias keys,
 * so the FXC1 tests exercise real authenticated encryption without an Android
 * runtime. The class is intentionally separate from the T025 `FakeBackend`
 * (which is private to its own test) because T026 needs provider faults,
 * invalidated aliases, and deterministic delete behaviour.
 */
class TestStoreKeystoreBackend : KeystoreBackend {

    val keys: LinkedHashMap<String, ByteArray> = LinkedHashMap()
    val unusable: MutableSet<String> = linkedSetOf()
    val generated: MutableList<Pair<String, Boolean>> = mutableListOf()
    val deleted: MutableList<String> = mutableListOf()

    var providerAvailableFlag: Boolean = true
    var providerFailuresRemaining: AtomicInteger = AtomicInteger(0)
    var failDeletes: Boolean = false
    var decryptProviderFailure: Boolean = false

    private val random = SecureRandom()

    override fun providerAvailable(): Boolean {
        if (providerFailuresRemaining.get() > 0) {
            providerFailuresRemaining.decrementAndGet()
            return false
        }
        return providerAvailableFlag
    }

    override fun containsAlias(alias: String): Boolean = keys.containsKey(alias)

    override fun listAliases(): Set<String> = keys.keys.toSet()

    override fun isKeyUsable(alias: String): Boolean =
        keys.containsKey(alias) && alias !in unusable

    override fun generateAesKey(alias: String, strongBox: Boolean) {
        generated += alias to strongBox
        keys[alias] = ByteArray(32).also { random.nextBytes(it) }
        unusable -= alias
    }

    override fun deleteAlias(alias: String): Boolean {
        if (failDeletes) return false
        deleted += alias
        keys.remove(alias)
        unusable.remove(alias)
        return true
    }

    override fun encrypt(
        alias: String,
        aad: ByteArray,
        plaintext: ByteArray,
    ): WrappedDek {
        val iv = ByteArray(KeystoreService.WRAP_IV_SIZE_BYTES).also {
            random.nextBytes(it)
        }
        val ciphertext = cipher(Cipher.ENCRYPT_MODE, alias, iv, aad)
            .doFinal(plaintext)
        return WrappedDek(iv, ciphertext)
    }

    override fun decrypt(
        alias: String,
        iv: ByteArray,
        aad: ByteArray,
        ciphertext: ByteArray,
    ): ByteArray {
        if (decryptProviderFailure) throw IllegalStateException("providerDown")
        return cipher(Cipher.DECRYPT_MODE, alias, iv, aad).doFinal(ciphertext)
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
}
