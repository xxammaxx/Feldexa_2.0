package de.feldexa.app

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * T027 review correction: `MainActivity` must compose the store on the
 * normative `contracts/storage-format.md` §1 directory `filesDir/feldexa/`, not
 * the earlier candidate's `filesDir/feldexa_store/`.
 */
class MainActivityStoreRootTest {

    @Test
    fun productionStoreRootMatchesStorageContract() {
        assertEquals("feldexa", MainActivity.STORE_ROOT_DIR)
    }
}
