package de.feldexa.app.delivery

/**
 * T107: hygiene for the one user-visible name delivery produces.
 *
 * `contracts/platform-channel.md` §7 requires a `suggestedName` derived from the
 * document title, sanitized: no path separators, at most 120 characters, `.pdf`
 * appended, never logged. The facade already rejects separators and control
 * characters, so this is the second, independent line of defence — and the only
 * place a name could otherwise become a path (the SAF picker treats it purely as
 * a display suggestion).
 *
 * Plain JVM Kotlin, so the unit tests need no Android runtime.
 */
object DeliveryNames {
    /** `contracts/platform-channel.md` §7. */
    const val MAX_SUGGESTED_NAME_LENGTH = 120

    const val PDF_SUFFIX = ".pdf"

    /** Neutral fallback; T041 owns any localized default title wording. */
    const val DEFAULT_NAME = "Feldexa_Dokument"

    /**
     * Returns a safe `.pdf` display name for [raw].
     *
     * Directory components, control characters, and redundant suffixes are
     * removed; the result is never empty and never longer than
     * [MAX_SUGGESTED_NAME_LENGTH] including its suffix.
     */
    fun sanitizeSuggestedName(raw: String?): String {
        val cleaned = (raw ?: "")
            .filterNot { it == '\u0000' || Character.isISOControl(it) }
        val withoutDirectories = cleaned
            .substringAfterLast('/')
            .substringAfterLast('\\')
            .trim()
        val withoutSuffix = if (withoutDirectories.endsWith(PDF_SUFFIX, ignoreCase = true)) {
            withoutDirectories.dropLast(PDF_SUFFIX.length)
        } else {
            withoutDirectories
        }
        val budget = MAX_SUGGESTED_NAME_LENGTH - PDF_SUFFIX.length
        val base = withoutSuffix.trim().take(budget)
        if (base.isEmpty()) return DEFAULT_NAME + PDF_SUFFIX
        // A name consisting only of dots would still be a traversal spelling.
        if (base.all { it == '.' }) return DEFAULT_NAME + PDF_SUFFIX
        return base + PDF_SUFFIX
    }
}
