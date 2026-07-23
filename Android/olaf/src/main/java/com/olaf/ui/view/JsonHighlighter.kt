package com.olaf.ui.view

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString

/**
 * Highlights JSON with regexes rather than a parser, so text broken by truncation — or a search
 * result that starts mid-document — still gets coloured.
 */
internal object JsonHighlighter {

    // Compiled once: these are constants, and a detail screen re-renders often.
    private val stringPattern = Regex("\"(?:\\\\.|[^\"\\\\])*\"")
    private val keyPattern = Regex("\"(?:\\\\.|[^\"\\\\])*\"(?=\\s*:)")
    private val numberPattern = Regex("(?<![\\w\"])-?\\d+(?:\\.\\d+)?(?![\\w\"])")
    private val literalPattern = Regex("\\b(?:true|false|null)\\b")

    private val stringColor = Color(0xFF2E9E4F)
    private val keyColor = Color(0xFF9B59D0)
    private val numberColor = Color(0xFF2596A8)
    private val literalColor = Color(0xFFCC7A00)

    fun highlight(text: String): AnnotatedString = buildAnnotatedString {
        append(text)
        // Order matters: strings first, then keys — a key is also a string, and must win.
        colorize(stringPattern, stringColor, text)
        colorize(keyPattern, keyColor, text)
        colorize(numberPattern, numberColor, text)
        colorize(literalPattern, literalColor, text)
    }

    private fun androidx.compose.ui.text.AnnotatedString.Builder.colorize(
        pattern: Regex,
        color: Color,
        source: String
    ) {
        pattern.findAll(source).forEach { match ->
            addStyle(SpanStyle(color = color), match.range.first, match.range.last + 1)
        }
    }
}
