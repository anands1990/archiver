import Foundation

/// Builds the bilingual interleaved Markdown document uploaded alongside the
/// original PDF. Pure functions — no I/O.
enum BilingualDocument {

    /// Splits raw OCR text into pages (form-feed separated) then into
    /// paragraphs (blank-line separated), dropping whitespace-only entries.
    /// Returns `pages[paragraphs]`.
    static func segment(_ text: String) -> [[String]] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let rawPages = normalized.components(separatedBy: "\u{0C}")

        return rawPages.map { page in
            page.components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    /// Renders the interleaved document. `pages[i]` is the list of
    /// `(source, translation)` paragraph pairs for page `i+1`.
    static func render(
        title: String,
        identifier: String,
        sourceLang: String,
        pages: [[(source: String, translation: String)]]
    ) -> String {
        var out: [String] = []
        out.append("# \(title.isEmpty ? identifier : title)")
        out.append("")
        out.append("> Source: https://archive.org/details/\(identifier)")
        out.append("> Translated from \(sourceLang) to English with IndicTrans2.")
        out.append("")
        out.append("---")
        out.append("")

        for (index, page) in pages.enumerated() where !page.isEmpty {
            out.append("## Page \(index + 1)")
            out.append("")
            for (source, translation) in page {
                out.append("**\(sourceLang)**")
                out.append("")
                out.append(source)
                out.append("")
                out.append("**English**")
                out.append("")
                out.append(translation.isEmpty ? "_(no translation)_" : translation)
                out.append("")
                out.append("---")
                out.append("")
            }
        }

        return out.joined(separator: "\n")
    }

    // MARK: - Untranslated-segment fallback

    /// Returns a usable rendering for one paragraph's translation, falling back
    /// to a romanisation of the source when the model echoed it back.
    ///
    /// IndicTrans2 gives up on phrases it cannot parse and returns the Sanskrit
    /// again — either verbatim in Devanagari, or romanised ("Satyamev Jayate").
    /// Either way the reader gets no English, so the source is romanised and
    /// marked instead: it is still enough to recognise the words and look them
    /// up. Real (if imperfect) translations are always passed through untouched.
    static func resolveTranslation(source: String, translated: String) -> String {
        let trimmed = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isEcho(source: source, translation: trimmed) else {
            return fallbackTranslation(source: source)
        }
        return trimmed
    }

    /// Text substituted for lines the model did not actually translate.
    static func fallbackTranslation(source: String) -> String {
        let roman = Transliterator.romanize(source).trimmingCharacters(in: .whitespacesAndNewlines)
        return roman.isEmpty ? "_(untranslated)_" : "_(untranslated)_ \(roman)"
    }

    /// True when `translation` is really the source coming back un-translated.
    ///
    /// Two signatures are detected: Devanagari still present in the output, or
    /// the output being the romanised source (with vowels dropped, as models do
    /// when they transliterate rather than translate).
    static func isEcho(source: String, translation: String) -> Bool {
        guard !translation.isEmpty else { return true }

        // Never left the source language.
        if Transliterator.containsDevanagari(translation) { return true }

        let sourceLatin = normalisedLatin(Transliterator.romanize(source))
        let translationLatin = normalisedLatin(translation)
        guard sourceLatin.count >= 6, translationLatin.count >= 6 else {
            // Too short to distinguish an echo from a legitimate short render.
            return false
        }

        // The model often drops vowels when it echoes, so a strict equality
        // check is not enough — "Satyamev Jayate" vs "Satyameva Jayate". Treat
        // either being a subsequence of the other as an echo.
        return isSubsequence(translationLatin, of: sourceLatin)
            || isSubsequence(sourceLatin, of: translationLatin)
    }

    /// Lowercase, diacritics stripped, letters and digits only.
    private static func normalisedLatin(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: nil)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    /// True when every character of `needle` appears in order inside `haystack`.
    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var remaining = haystack[...]
        for character in needle {
            guard let index = remaining.firstIndex(of: character) else { return false }
            remaining = remaining[remaining.index(after: index)...]
        }
        return true
    }
}