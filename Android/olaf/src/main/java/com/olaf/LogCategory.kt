package com.olaf

/**
 * Module-based log grouping. String-backed, so every project can add its own categories:
 *
 * ```kotlin
 * val LogCategory.Companion.Transfers: LogCategory get() = LogCategory("transfers")
 * ```
 */
@JvmInline
value class LogCategory(val rawValue: String) {

    override fun toString(): String = rawValue

    // Suggested common categories — projects can extend these.
    companion object {
        val General = LogCategory("general")
        val Auth = LogCategory("auth")
        val Payment = LogCategory("payment")
        val Network = LogCategory("network")
        val Session = LogCategory("session")
        val Security = LogCategory("security")

        /** Screen transitions (push/sheet/popup/root). [Olaf.trackScreen] writes to this category. */
        val Navigation = LogCategory("navigation")

        /** Entries imported from the system log (Logcat). */
        val Logcat = LogCategory("logcat")

        /** Deserialization failures reported through `Olaf.logDecodingError`. */
        val Decoding = LogCategory("decoding")
    }
}
