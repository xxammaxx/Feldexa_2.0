package de.feldexa.app.storage

import java.io.File

/**
 * T040 review-correction test helper: delegates the real store filesystem but
 * can refuse deletion of an aggregate directory or a `tmp/` entry.
 *
 * A `false` return from [deleteTree] models the store's cleanup contract: the
 * caller must treat it as residue, not as a silent success. The flags are
 * mutable so a test can stage normally and then arm the failure at the exact
 * commit/abort checkpoint it wants to exercise.
 */
internal class TestFailingDeleteIo(
    private val delegate: StoreIo = RealStoreIo(),
) : StoreIo by delegate {

    @Volatile
    var failAggregateDelete: Boolean = false

    @Volatile
    var failTempDelete: Boolean = false

    override fun deleteTree(file: File): Boolean {
        if (failAggregateDelete && file.parentFile?.name == "docs") return false
        if (failTempDelete && file.parentFile?.name == "tmp") return false
        return delegate.deleteTree(file)
    }
}
