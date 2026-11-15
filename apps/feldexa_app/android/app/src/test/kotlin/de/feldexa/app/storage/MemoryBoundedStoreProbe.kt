package de.feldexa.app.storage

import java.nio.file.Files
import java.security.MessageDigest
import java.util.UUID

/**
 * T026 review-correction memory probe.
 *
 * Runs in a child JVM with a 128 MiB heap and commits/verifies an 80 MiB
 * object. The pre-fix `readContainer` allocated a second 80 MiB plaintext
 * buffer during staged verification/read-back and therefore failed with
 * `OutOfMemoryError`; the streaming path keeps only one ciphertext and one
 * plaintext chunk buffer live.
 */
object MemoryBoundedStoreProbe {

    @JvmStatic
    fun main(args: Array<String>) {
        val root = Files.createTempDirectory("t026-memory-probe").toFile()
        try {
            val backend = TestStoreKeystoreBackend()
            val keystore = KeystoreService(backend, sleeper = {})
            val store = EncryptedStore(root, keystore)
            store.ensureLayout()
            val ref = AggregateRef(AggregateKind.DOCUMENT, UUID.randomUUID().toString())
            keystore.createAggregateKey(ref)
            val obj = RevisionObject(ref, UUID.randomUUID().toString())
            val plaintext = ByteArray(80 * 1024 * 1024) { 7 }
            store.commitObjectForTest(obj, plaintext)
            val sha = store.verifyObjectForTest(obj)
            val expected = MessageDigest.getInstance("SHA-256")
                .digest(plaintext)
                .joinToString("") { "%02x".format(it.toInt() and 0xFF) }
            check(sha == expected) { "sha mismatch" }
            println("MEMORY_PROBE_OK")
        } finally {
            root.deleteRecursively()
        }
    }
}
