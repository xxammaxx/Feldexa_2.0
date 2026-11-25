package de.feldexa.app.export

import de.feldexa.app.PlatformFailure
import java.io.File

/**
 * T104/T107: the session-scoped export artifact store.
 *
 * `contracts/platform-channel.md` §6/§7 limit the channel to the current
 * session's artifacts: `export.readArtifact`, `delivery.save/share/print`, and
 * `export.deleteArtifact` resolve an `artifactId` only against this registry,
 * never against a path or a URI. The files live in
 * `cacheDir/feldexa_exports/` (§11 point 8) and are the only files the
 * `FileProvider` exposes.
 *
 * Naming hygiene is enforced in one place: [artifactFile] refuses any id that
 * is not a lowercase UUIDv4, so an id can never become a path separator, a
 * relative segment, or a foreign file. Unknown ids are `EXP-002`
 * ("no such artifact"), never a filesystem error.
 */
class ExportArtifactStore(private val directory: File) {

    private val lock = Any()
    private val published = LinkedHashMap<String, ArtifactRecord>()

    /** A verified artifact of this session. */
    data class ArtifactRecord(
        val artifactId: String,
        val file: File,
        val byteSize: Long,
        val sha256: String,
        val pageCount: Int,
    )

    fun ensureDirectory() {
        if (!directory.exists() && !directory.mkdirs() && !directory.isDirectory) {
            throw exportFailure("EXP-002")
        }
    }

    /** Free space of the artifact filesystem for the `export-plan.md` §5 precondition. */
    fun usableSpaceBytes(): Long = directory.usableSpace

    /** The reserved final path for [artifactId]; the file may not exist yet. */
    fun artifactFile(artifactId: String): File {
        requireUuid(artifactId)
        return File(directory, "$artifactId.pdf")
    }

    /** The temporary sibling a render writes before the atomic rename. */
    fun temporaryFile(artifactId: String): File {
        requireUuid(artifactId)
        return File(directory, "$artifactId.pdf.tmp")
    }

    fun publish(record: ArtifactRecord) {
        requireUuid(record.artifactId)
        synchronized(lock) { published[record.artifactId] = record }
    }

    fun record(artifactId: String): ArtifactRecord? = synchronized(lock) { published[artifactId] }

    /**
     * Reads one published artifact for the preview.
     *
     * The read is bounded by [MAX_ARTIFACT_BYTES] and re-checks the recorded
     * size, so a file changed underneath the session cannot be streamed
     * unbounded and a truncated file is reported instead of previewed.
     */
    fun read(artifactId: String): ByteArray {
        val record = record(artifactId) ?: throw exportFailure("EXP-002")
        if (record.byteSize < 1 || record.byteSize > MAX_ARTIFACT_BYTES) throw exportFailure("EXP-002")
        val bytes = try {
            record.file.readBytes()
        } catch (failure: Exception) {
            throw exportFailure("EXP-002")
        }
        if (bytes.size.toLong() != record.byteSize) throw exportFailure("EXP-002")
        return bytes
    }

    /** Deletes one published artifact; returns false for an unknown id. */
    fun delete(artifactId: String): Boolean {
        val record = synchronized(lock) { published.remove(artifactId) } ?: return false
        record.file.delete()
        return true
    }

    /**
     * Deletes every artifact of this session (`platform-channel.md` §9: engine
     * detach "deletes session export artifacts"). Durable documents and sources
     * are never touched here.
     */
    fun deleteAll() {
        val records = synchronized(lock) {
            val copy = published.values.toList()
            published.clear()
            copy
        }
        records.forEach { runCatching { it.file.delete() } }
    }

    private fun requireUuid(artifactId: String) {
        if (!UUID_V4.matches(artifactId)) throw PlatformFailure.invalidIdentifier()
    }

    companion object {
        /** `platform-channel.md` §11 point 8: the only `FileProvider` path. */
        const val DIRECTORY_NAME = "feldexa_exports"

        /**
         * Bound for a session artifact handed to preview/save/share/print:
         * 2 × the 80 MiB source cap (`platform-channel.md` §10) is the largest
         * plausible output, and the preview holds it in memory once.
         */
        const val MAX_ARTIFACT_BYTES: Long = 160L * 1024L * 1024L

        val UUID_V4: Regex =
            Regex("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
    }
}
