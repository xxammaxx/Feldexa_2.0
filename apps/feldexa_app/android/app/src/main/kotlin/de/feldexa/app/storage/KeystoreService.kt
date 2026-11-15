package de.feldexa.app.storage

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import java.security.InvalidKeyException
import java.security.KeyStore
import java.security.SecureRandom
import java.security.UnrecoverableKeyException
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * T025: per-aggregate Android Keystore key service.
 *
 * One non-exportable AES-256-GCM KEK exists per document and per template
 * (`feldexa.doc.v1.<documentId>` / `feldexa.tpl.v1.<templateId>`). Every FXC1
 * object's own 32-byte DEK is wrapped by that aggregate's KEK with AAD
 * `FXC1-DEK`; no master key exists (FR-049/FR-050/FR-052,
 * `contracts/storage-format.md` §2.3).
 *
 * Lifecycle rules:
 *  * [createAggregateKey] is called before the first ciphertext write and is
 *    idempotent. An existing but unusable key is never silently regenerated.
 *  * [deleteAggregateKey] removes exactly the named alias and is called by the
 *    store after the aggregate's objects and directory are gone (§3.6). A
 *    false result means the alias remains and the startup sweep must retry.
 *  * [sweepOrphanAliases] deletes only aliases without an existing aggregate
 *    directory; an alias whose directory still exists is never removed.
 *
 * Failure mapping:
 *  * one aggregate's key missing/invalidated while another aggregate key is
 *    usable → [KeyUnavailableException] (`SAVE-002`);
 *  * provider unavailable after one retry, or no aggregate key usable at all →
 *    [KeystoreUnavailableException] (`SAVE-008`);
 *  * a present KEK that cannot authenticate the wrapped DEK → corrupt key
 *    material ([CorruptDataException], `SAVE-003`).
 *
 * Key-loss classification counts any other usable aggregate alias in the
 * Keystore. T026 must run the startup orphan-alias sweep before serving loads,
 * otherwise an orphan alias could mask a device-wide reset. Provider retries
 * may sleep briefly, so callers must use a background executor rather than the
 * UI thread.
 *
 * The KEK bytes are never exposed: this class has no API that returns a
 * [SecretKey] or its encoding. [KeystoreBackend] implementations must keep that
 * property.
 */
class KeystoreService(
    private val backend: KeystoreBackend,
    private val secureRandom: SecureRandom = SecureRandom(),
    private val strongBoxSupported: Boolean = false,
    private val sleeper: (Long) -> Unit = { Thread.sleep(it) },
) {

    /**
     * Creates the aggregate KEK if it is absent and returns normally if it is
     * already usable. Key creation happens before any ciphertext write; a
     * failure leaves no alias behind and therefore no visible aggregate.
     *
     * @throws KeystoreUnavailableException when the provider is unavailable.
     * @throws KeyUnavailableException when an existing alias is unusable; it is
     *   never replaced, because replacing it would orphan existing ciphertext.
     * @throws PlatformSecurityException for an invalid aggregate id.
     */
    @Synchronized
    fun createAggregateKey(ref: AggregateRef) {
        requireValid(ref)
        requireProvider()
        val alias = ref.alias
        val exists = try {
            backend.containsAlias(alias)
        } catch (failure: Exception) {
            throw keystoreUnavailable()
        }
        if (exists) {
            if (isUsable(alias)) return
            // §3.2: a failed creation reports the aggregate-scoped code. An
            // existing aggregate with corrupt/invalidated key material keeps
            // its ciphertext; regenerating would destroy readability.
            throw KeyUnavailableException()
        }
        generateKey(alias)
    }

    /** Whether the aggregate currently has a usable Keystore key. */
    fun hasAggregateKey(ref: AggregateRef): Boolean {
        requireValid(ref)
        if (!providerAvailableWithRetry()) return false
        return try {
            containsAlias(ref.alias) && isUsable(ref.alias)
        } catch (failure: Exception) {
            false
        }
    }

    /**
     * Per-aggregate key state for listing and diagnostics. This method is
     * non-fatal: an unavailable provider is reported as
     * [AggregateKeyState.PROVIDER_UNAVAILABLE] instead of throwing.
     */
    fun aggregateKeyState(ref: AggregateRef): AggregateKeyState {
        requireValid(ref)
        if (!providerAvailableWithRetry()) {
            return AggregateKeyState.PROVIDER_UNAVAILABLE
        }
        return try {
            when {
                !containsAlias(ref.alias) -> AggregateKeyState.MISSING
                isUsable(ref.alias) -> AggregateKeyState.AVAILABLE
                else -> AggregateKeyState.INVALIDATED
            }
        } catch (failure: Exception) {
            AggregateKeyState.PROVIDER_UNAVAILABLE
        }
    }

    /**
     * Deletes exactly the given aggregate's alias, after its encrypted objects
     * and directory have been removed by the store (§3.6).
     *
     * Best-effort by contract: returns false when the alias could not be
     * removed now (provider unavailable or Keystore error). The startup
     * [sweepOrphanAliases] removes the resulting orphan. No other alias is
     * read or deleted.
     */
    @Synchronized
    fun deleteAggregateKey(ref: AggregateRef): Boolean {
        requireValid(ref)
        if (!providerAvailableWithRetry()) return false
        return try {
            backend.deleteAlias(ref.alias)
        } catch (failure: Exception) {
            false
        }
    }

    /**
     * Wraps a 32-byte DEK with the aggregate's KEK using AES-GCM, AAD
     * `FXC1-DEK`, and a fresh random 12-byte IV (§2.3). The returned wrapped
     * key is 48 bytes (32-byte DEK + 16-byte tag).
     */
    fun wrapDek(ref: AggregateRef, dek: ByteArray): WrappedDek {
        requireValid(ref)
        require(dek.size == DEK_SIZE_BYTES) {
            "DEK must be $DEK_SIZE_BYTES bytes"
        }
        requireProvider()
        if (!containsAlias(ref.alias) || !isUsable(ref.alias)) {
            throw keyLoss(ref)
        }
        val wrapIv = ByteArray(WRAP_IV_SIZE_BYTES).also(secureRandom::nextBytes)
        val wrappedKey = try {
            backend.encrypt(ref.alias, wrapIv, WRAP_AAD_BYTES, dek)
        } catch (failure: AEADBadTagException) {
            throw CorruptDataException()
        } catch (failure: UnrecoverableKeyException) {
            throw keyLoss(ref)
        } catch (failure: InvalidKeyException) {
            throw keyLoss(ref)
        } catch (failure: Exception) {
            throw keystoreUnavailable()
        }
        if (wrappedKey.size != WRAPPED_DEK_SIZE_BYTES) {
            throw CorruptDataException()
        }
        return WrappedDek(wrapIv, wrappedKey)
    }

    /**
     * Unwraps a DEK with the aggregate's KEK. A missing/invalidated KEK maps to
     * `SAVE-002`/`SAVE-008`; a wrapped DEK that fails GCM authentication while
     * the KEK is present maps to [CorruptDataException] (`SAVE-003`).
     */
    fun unwrapDek(ref: AggregateRef, wrapped: WrappedDek): ByteArray {
        requireValid(ref)
        requireProvider()
        if (wrapped.wrapIv.size != WRAP_IV_SIZE_BYTES ||
            wrapped.wrappedKey.size != WRAPPED_DEK_SIZE_BYTES
        ) {
            throw CorruptDataException()
        }
        if (!containsAlias(ref.alias) || !isUsable(ref.alias)) {
            throw keyLoss(ref)
        }
        val dek = try {
            backend.decrypt(
                ref.alias,
                wrapped.wrapIv,
                WRAP_AAD_BYTES,
                wrapped.wrappedKey,
            )
        } catch (failure: AEADBadTagException) {
            throw CorruptDataException()
        } catch (failure: UnrecoverableKeyException) {
            throw keyLoss(ref)
        } catch (failure: InvalidKeyException) {
            throw keyLoss(ref)
        } catch (failure: Exception) {
            throw keystoreUnavailable()
        }
        if (dek.size != DEK_SIZE_BYTES) {
            throw CorruptDataException()
        }
        return dek
    }

    /**
     * T013-compatible, non-fatal store-level key summary.
     *
     * `keyAvailable` is false when at least one known aggregate key is
     * unavailable. It does not identify the aggregate and never makes the
     * whole store throw. Per-aggregate detail is in
     * [unavailableAggregates] and [reasonCode] (`SAVE-002` for aggregate-scoped
     * loss while at least one key remains; `SAVE-008` for a provider outage or
     * a device-wide reset where no known key remains).
     */
    fun storeKeyStatus(
        knownAggregates: Collection<AggregateRef>,
    ): StoreKeyStatus {
        knownAggregates.forEach(::requireValid)
        val known = knownAggregates.distinct()
        if (!providerAvailableWithRetry()) {
            return StoreKeyStatus(
                providerAvailable = false,
                keyAvailable = false,
                globalFailure = true,
                reasonCode = SAVE_008,
                unavailableAggregates = known,
            )
        }
        return try {
            val unavailable = known.filterNot { ref ->
                containsAlias(ref.alias) && isUsable(ref.alias)
            }
            if (known.isNotEmpty() && unavailable.size == known.size) {
                // Provider is usable but no stored aggregate key remains: the
                // contract treats this as a device-wide reset, not as N
                // independent SAVE-002 messages claiming isolation.
                StoreKeyStatus(
                    providerAvailable = true,
                    keyAvailable = false,
                    globalFailure = true,
                    reasonCode = SAVE_008,
                    unavailableAggregates = known,
                )
            } else {
                StoreKeyStatus(
                    providerAvailable = true,
                    keyAvailable = unavailable.isEmpty(),
                    globalFailure = false,
                    reasonCode = if (unavailable.isEmpty()) null else SAVE_002,
                    unavailableAggregates = unavailable,
                )
            }
        } catch (failure: Exception) {
            StoreKeyStatus(
                providerAvailable = false,
                keyAvailable = false,
                globalFailure = true,
                reasonCode = SAVE_008,
                unavailableAggregates = known,
            )
        }
    }

    /**
     * Removes aliases under the two aggregate prefixes that have no
     * corresponding aggregate directory (§4 step 5). Only aliases without an
     * existing aggregate are deleted; an alias whose directory still exists is
     * never removed.
     *
     * [aggregateDirectoryExists] is supplied by the store (T026) so this
     * service never reads the document/template directory layout itself.
     */
    @Synchronized
    fun sweepOrphanAliases(
        aggregateDirectoryExists: (AggregateRef) -> Boolean,
    ): OrphanAliasSweep {
        requireProvider()
        val aliases = try {
            backend.listAliases()
        } catch (failure: Exception) {
            throw keystoreUnavailable()
        }
        var removed = 0
        var retained = 0
        var failed = 0
        for (alias in aliases) {
            val ref = parseAlias(alias)
            if (ref == null) {
                if (!hasAggregatePrefix(alias)) continue
                // A malformed prefixed alias cannot belong to a valid
                // aggregate directory, so it is an orphan.
                if (deleteQuietly(alias)) removed++ else failed++
                continue
            }
            val directoryExists = try {
                aggregateDirectoryExists(ref)
            } catch (failure: Exception) {
                throw keystoreUnavailable()
            }
            if (directoryExists) {
                retained++
                continue
            }
            if (deleteQuietly(alias)) removed++ else failed++
        }
        return OrphanAliasSweep(
            removedAliases = removed,
            retainedAliases = retained,
            failedAliases = failed,
        )
    }

    private fun generateKey(alias: String) {
        if (strongBoxSupported) {
            val strongBoxGenerationSucceeded = try {
                backend.generateAesKey(alias, strongBox = true)
                isUsable(alias)
            } catch (failure: Exception) {
                // StrongBox is best-effort: retry in the TEE, never in
                // software. Any StrongBox failure is covered here because the
                // platform reports it with device-specific exception types.
                false
            }
            if (strongBoxGenerationSucceeded) return
            deleteQuietly(alias)
        }
        try {
            backend.generateAesKey(alias, strongBox = false)
        } catch (failure: Exception) {
            deleteQuietly(alias)
            if (!providerAvailableWithRetry()) {
                throw keystoreUnavailable()
            }
            throw KeyUnavailableException()
        }
        if (!isUsable(alias)) {
            deleteQuietly(alias)
            throw KeyUnavailableException()
        }
    }

    /**
     * Maps a missing or invalidated aggregate key to the aggregate-scoped code
     * only when another aggregate key is usable. With no usable key left the
     * contract requires the global code and no false isolation claim.
     */
    private fun keyLoss(ref: AggregateRef): Nothing {
        val siblingAvailable = try {
            anyOtherUsableAggregateKey(ref)
        } catch (failure: Exception) {
            throw keystoreUnavailable()
        }
        if (siblingAvailable) {
            throw KeyUnavailableException()
        }
        throw KeystoreUnavailableException(retryable = false)
    }

    private fun anyOtherUsableAggregateKey(ref: AggregateRef): Boolean {
        val aliases = try {
            backend.listAliases()
        } catch (failure: Exception) {
            throw keystoreUnavailable()
        }
        for (alias in aliases) {
            if (alias == ref.alias) continue
            if (parseAlias(alias) == null) continue
            if (backend.isKeyUsable(alias)) return true
        }
        return false
    }

    private fun requireProvider() {
        if (!providerAvailableWithRetry()) {
            throw keystoreUnavailable()
        }
    }

    private fun providerAvailableWithRetry(): Boolean {
        if (backend.providerAvailable()) return true
        // Contract: retry once after a short delay (e.g. locked device before
        // first unlock). No partial state is created before this check.
        sleeper(PROVIDER_RETRY_DELAY_MS)
        return backend.providerAvailable()
    }

    private fun containsAlias(alias: String): Boolean = try {
        backend.containsAlias(alias)
    } catch (failure: Exception) {
        throw keystoreUnavailable()
    }

    private fun isUsable(alias: String): Boolean = try {
        backend.isKeyUsable(alias)
    } catch (failure: Exception) {
        throw keystoreUnavailable()
    }

    private fun deleteQuietly(alias: String): Boolean = try {
        backend.deleteAlias(alias)
    } catch (failure: Exception) {
        false
    }

    private fun keystoreUnavailable(): KeystoreUnavailableException =
        KeystoreUnavailableException(retryable = true)

    private fun requireValid(ref: AggregateRef) {
        if (!AggregateRef.isValidId(ref.id)) {
            throw PlatformSecurityException()
        }
    }

    private fun hasAggregatePrefix(alias: String): Boolean =
        AggregateKind.entries.any { alias.startsWith(it.aliasPrefix) }

    private fun parseAlias(alias: String): AggregateRef? {
        for (kind in AggregateKind.entries) {
            if (!alias.startsWith(kind.aliasPrefix)) continue
            val id = alias.removePrefix(kind.aliasPrefix)
            return if (AggregateRef.isValidId(id)) {
                AggregateRef(kind, id)
            } else {
                null
            }
        }
        return null
    }

    companion object {
        /** DEK length in bytes (§2.3). */
        const val DEK_SIZE_BYTES: Int = 32

        /** Random AES-GCM IV length for DEK wrapping (§2.3). */
        const val WRAP_IV_SIZE_BYTES: Int = 12

        /** 32-byte DEK plus 16-byte GCM tag (§2.1). */
        const val WRAPPED_DEK_SIZE_BYTES: Int = 48

        /** AAD that binds the wrapped DEK to the key-wrap purpose (§2.3). */
        const val WRAP_AAD: String = "FXC1-DEK"

        /** One retry after this delay when the provider is unavailable. */
        const val PROVIDER_RETRY_DELAY_MS: Long = 250L

        internal const val SAVE_002: String = "SAVE-002"
        internal const val SAVE_008: String = "SAVE-008"

        private const val ANDROID_KEYSTORE = "AndroidKeyStore"

        private val WRAP_AAD_BYTES: ByteArray = WRAP_AAD.toByteArray(Charsets.UTF_8)

        /**
         * Production factory. StrongBox is attempted only when the device
         * advertises it (API 28+); the service falls back to the TEE.
         */
        @JvmStatic
        fun forAndroid(context: Context): KeystoreService {
            val packageManager = context.applicationContext.packageManager
            val strongBoxSupported =
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
                    packageManager.hasSystemFeature(
                        PackageManager.FEATURE_STRONGBOX_KEYSTORE,
                    )
            return KeystoreService(
                backend = AndroidKeystoreBackend(),
                strongBoxSupported = strongBoxSupported,
            )
        }
    }
}

/**
 * Aggregate identity: a document or a template namespace plus its UUIDv4.
 * Aliases are derived, never stored separately.
 */
data class AggregateRef(
    val kind: AggregateKind,
    val id: String,
) {
    /** Full Keystore alias for this aggregate. */
    val alias: String
        get() = kind.aliasPrefix + id

    companion object {
        private val UUID_V4 = Regex(
            "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-" +
                "[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
        )

        /** Same UUIDv4 rule as `contracts/storage-format.md` §1. */
        fun isValidId(id: String): Boolean = UUID_V4.matches(id)
    }
}

/** The two aggregate namespaces; a document is never opened as a template. */
enum class AggregateKind(val aliasPrefix: String) {
    DOCUMENT("feldexa.doc.v1."),
    TEMPLATE("feldexa.tpl.v1."),
}

/** Per-aggregate key state without throwing on provider unavailability. */
enum class AggregateKeyState {
    AVAILABLE,
    MISSING,
    INVALIDATED,
    PROVIDER_UNAVAILABLE,
}

/**
 * Wrapped DEK as stored in the FXC1 header (`wrapIv` + `wrappedKey`).
 *
 * Defensive copies keep the header bytes stable. Equality is content-based so
 * tests and read-back verification can compare values. `toString()` never
 * prints key bytes.
 */
class WrappedDek(
    wrapIv: ByteArray,
    wrappedKey: ByteArray,
) {
    val wrapIv: ByteArray = wrapIv.copyOf()
    val wrappedKey: ByteArray = wrappedKey.copyOf()

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is WrappedDek) return false
        return wrapIv.contentEquals(other.wrapIv) &&
            wrappedKey.contentEquals(other.wrappedKey)
    }

    override fun hashCode(): Int =
        31 * wrapIv.contentHashCode() + wrappedKey.contentHashCode()

    override fun toString(): String =
        "WrappedDek(wrapIv=${wrapIv.size} bytes, " +
            "wrappedKey=${wrappedKey.size} bytes)"
}

/** Store-level key summary; never fatal to the whole store by itself. */
data class StoreKeyStatus(
    val providerAvailable: Boolean,
    val keyAvailable: Boolean,
    val globalFailure: Boolean,
    val reasonCode: String?,
    val unavailableAggregates: List<AggregateRef>,
)

/** Counts only; no aggregate ids or content in sweep diagnostics. */
data class OrphanAliasSweep(
    val removedAliases: Int,
    val retainedAliases: Int,
    val failedAliases: Int,
)

/**
 * Narrow seam around the Android Keystore so the lifecycle/failure policy is
 * testable on the JVM with a fake backend.
 *
 * Implementations must never return, print, or otherwise expose KEK bytes.
 * They must throw [AEADBadTagException] when wrapped-key authentication fails
 * and [InvalidKeyException] (including
 * [KeyPermanentlyInvalidatedException]) when the key is unusable.
 */
interface KeystoreBackend {
    /** Whether the Android Keystore provider can be loaded right now. */
    fun providerAvailable(): Boolean

    fun containsAlias(alias: String): Boolean

    fun listAliases(): Set<String>

    /** False when the alias exists but its key cannot be used. */
    fun isKeyUsable(alias: String): Boolean

    /**
     * Generates a non-exportable AES-256-GCM KEK. [strongBox] requests
     * StrongBox; the caller retries with `false` when the request fails.
     */
    fun generateAesKey(alias: String, strongBox: Boolean)

    /** Deletes the alias; returns true when it is absent or removed. */
    fun deleteAlias(alias: String): Boolean

    /** AES-GCM encrypt with the alias's key and the supplied AAD/IV. */
    fun encrypt(
        alias: String,
        iv: ByteArray,
        aad: ByteArray,
        plaintext: ByteArray,
    ): ByteArray

    /** AES-GCM decrypt with the alias's key and the supplied AAD/IV. */
    fun decrypt(
        alias: String,
        iv: ByteArray,
        aad: ByteArray,
        ciphertext: ByteArray,
    ): ByteArray
}

/**
 * Production backend over `AndroidKeyStore`.
 *
 * Keys are created with `setUserAuthenticationRequired(false)` (no app
 * password or biometric, FR-050) and are hardware-backed where the device
 * provides StrongBox/TEE. The KEK is never exported: no method returns a
 * [SecretKey] publicly.
 */
internal class AndroidKeystoreBackend : KeystoreBackend {

    override fun providerAvailable(): Boolean = try {
        requireKeyStore()
        true
    } catch (failure: Exception) {
        false
    }

    override fun containsAlias(alias: String): Boolean =
        requireKeyStore().containsAlias(alias)

    override fun listAliases(): Set<String> {
        val aliases = requireKeyStore().aliases()
        val result = LinkedHashSet<String>()
        while (aliases.hasMoreElements()) {
            result += aliases.nextElement()
        }
        return result
    }

    override fun isKeyUsable(alias: String): Boolean = try {
        requireKeyStore().getKey(alias, null) != null
    } catch (failure: UnrecoverableKeyException) {
        false
    } catch (failure: KeyPermanentlyInvalidatedException) {
        false
    } catch (failure: Exception) {
        throw failure
    }

    override fun generateAesKey(alias: String, strongBox: Boolean) {
        val builder = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setKeySize(KEY_SIZE_BITS)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setUserAuthenticationRequired(false)
            .setRandomizedEncryptionRequired(true)
        if (strongBox) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
                throw UnsupportedOperationException(
                    "StrongBox requires API 28",
                )
            }
            builder.setIsStrongBoxBacked(true)
        }
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEYSTORE,
        )
        generator.init(builder.build())
        generator.generateKey()
    }

    override fun deleteAlias(alias: String): Boolean {
        val keyStore = requireKeyStore()
        if (keyStore.containsAlias(alias)) {
            keyStore.deleteEntry(alias)
        }
        return true
    }

    override fun encrypt(
        alias: String,
        iv: ByteArray,
        aad: ByteArray,
        plaintext: ByteArray,
    ): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.ENCRYPT_MODE,
            requireKey(alias),
            GCMParameterSpec(TAG_SIZE_BITS, iv),
        )
        cipher.updateAAD(aad)
        return cipher.doFinal(plaintext)
    }

    override fun decrypt(
        alias: String,
        iv: ByteArray,
        aad: ByteArray,
        ciphertext: ByteArray,
    ): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            requireKey(alias),
            GCMParameterSpec(TAG_SIZE_BITS, iv),
        )
        cipher.updateAAD(aad)
        return cipher.doFinal(ciphertext)
    }

    private fun requireKey(alias: String): SecretKey {
        val key = requireKeyStore().getKey(alias, null) as? SecretKey
            ?: throw UnrecoverableKeyException("key unavailable")
        return key
    }

    private fun requireKeyStore(): KeyStore =
        KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    private companion object {
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val KEY_SIZE_BITS = 256
        const val TAG_SIZE_BITS = 128
    }
}
