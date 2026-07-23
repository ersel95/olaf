package com.olaf.internal

/**
 * Call-site information (file, line, function) for a log call.
 *
 * iOS gets this for free at compile time via `#fileID`/`#line`/`#function`. Kotlin has no
 * equivalent, so it is recovered from the stack at runtime — and only when an entry is actually
 * going to be recorded, never for dropped logs.
 */
internal data class CallSite(
    val file: String,
    val line: Int,
    val function: String
) {

    companion object {
        val Unknown = CallSite("", 0, "")

        /** The first frame outside Olaf itself is the caller we want to attribute the log to. */
        fun capture(): CallSite {
            val stack = Throwable().stackTrace
            for (frame in stack) {
                if (isOlafFrame(frame.className)) continue
                return CallSite(
                    file = frame.fileName ?: frame.className.substringAfterLast('.'),
                    line = frame.lineNumber.coerceAtLeast(0),
                    function = frame.methodName
                )
            }
            return Unknown
        }

        private fun isOlafFrame(className: String): Boolean =
            className == "com.olaf.Olaf" ||
                className.startsWith("com.olaf.internal.") ||
                className.startsWith("com.olaf.network.")
    }
}
