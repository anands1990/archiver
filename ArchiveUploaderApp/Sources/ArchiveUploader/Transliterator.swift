import Foundation

/// Deterministic Devanagari → Latin transliteration (IAST-flavoured).
///
/// Exists as a fallback: IndicTrans2 sometimes returns the source text unchanged
/// instead of translating it — short and idiomatic phrases in particular
/// (`सत्यमेव जयते` came back as "Satyamev Jayate"). Those lines give the reader
/// no English whatsoever, so they are at least romanised into readable word
/// forms, which is enough to look up or recognise.
///
/// Pure Unicode table mapping — no model, no dictionary, no opinions.
enum Transliterator {

    /// The Devanagari Unicode block, used to spot un-transliterated text.
    static let devanagariRange: ClosedRange<Unicode.Scalar> = "\u{0900}"..."\u{097F}"

    // MARK: - Tables

    private static let consonants: [Unicode.Scalar: String] = [
        "क": "k",  "ख": "kh", "ग": "g",  "घ": "gh", "ङ": "ṅ",
        "च": "c",  "छ": "ch", "ज": "j",  "झ": "jh", "ञ": "ñ",
        "ट": "ṭ",  "ठ": "ṭh", "ड": "ḍ",  "ढ": "ḍh", "ण": "ṇ",
        "त": "t",  "थ": "th", "द": "d",  "ध": "dh", "न": "n",
        "प": "p",  "फ": "ph", "ब": "b",  "भ": "bh", "म": "m",
        "य": "y",  "र": "r",  "ल": "l",  "व": "v",
        "श": "ś",  "ष": "ṣ",  "स": "s",  "ह": "h",
    ]

    private static let independentVowels: [Unicode.Scalar: String] = [
        "अ": "a",  "आ": "ā",  "इ": "i",  "ई": "ī",  "उ": "u",  "ऊ": "ū",
        "ऋ": "ṛ",  "ॠ": "ṝ",  "ऌ": "ḹ",  "ए": "e",  "ऐ": "ai",
        "ओ": "o",  "औ": "au",
    ]

    private static let vowelSigns: [Unicode.Scalar: String] = [
        "ा": "ā",  "ि": "i",  "ी": "ī",  "ु": "u",  "ू": "ū",
        "ृ": "ṛ",  "े": "e",  "ै": "ai",  "ो": "o",  "ौ": "au",
    ]

    /// Consonants carrying a nukta are their own letters, not base + dot.
    private static let nuktaConsonants: [Unicode.Scalar: String] = [
        "क": "q",  "ख": "x",  "ग": "ġ",  "ज": "z",  "ड": "ṛ",  "ढ": "ṛh",
        "फ": "f",  "य": "ẏ",
    ]

    private static let virama = Unicode.Scalar("्")
    private static let anusvara = Unicode.Scalar("ं")
    private static let visarga = Unicode.Scalar("ः")
    private static let candrabindu = Unicode.Scalar("ँ")
    private static let nukta = Unicode.Scalar("़")
    private static let avagraha = Unicode.Scalar("ऽ")
    private static let danda = Unicode.Scalar("।")
    private static let om = Unicode.Scalar("ॐ")

    // MARK: - Public API

    /// True when `text` still contains Devanagari characters.
    static func containsDevanagari(_ text: String) -> Bool {
        text.unicodeScalars.contains { devanagariRange ~= $0 }
    }

    /// Romanises Devanagari text. Non-Devanagari content (Latin letters,
    /// punctuation, numerals) passes through untouched.
    static func romanize(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var out = ""
        out.reserveCapacity(scalars.count * 2)

        var i = 0
        while i < scalars.count {
            let scalar = scalars[i]
            i += 1

            // A nukta is a combining mark that follows its consonant.
            var nukta = false
            if i < scalars.count, scalars[i] == Transliterator.nukta {
                nukta = true
                i += 1
            }

            if let vowel = independentVowels[scalar] {
                out += vowel
                continue
            }

            if let base = consonants[scalar] {
                out += (nukta ? nuktaConsonants[scalar] : nil) ?? base

                // Dependent vowel sign — the inherent vowel is replaced.
                if i < scalars.count, let sign = vowelSigns[scalars[i]] {
                    out += sign
                    i += 1
                    continue
                }

                // Halant suppresses the inherent vowel.
                if i < scalars.count, scalars[i] == virama {
                    i += 1
                    continue
                }

                if i < scalars.count, scalars[i] == candrabindu {
                    out += "\u{0303}" // combining tilde (nasalised)
                    i += 1
                    continue
                }

                out += "a" // inherent vowel
                continue
            }

            switch scalar {
            case anusvara:   out += "ṃ"
            case visarga:    out += "ḥ"
            case avagraha:   out += "'"
            case danda:      out += "."
            case om:         out += "oṃ"
            case Unicode.Scalar("०"): out += "0"
            case Unicode.Scalar("१"): out += "1"
            case Unicode.Scalar("२"): out += "2"
            case Unicode.Scalar("३"): out += "3"
            case Unicode.Scalar("४"): out += "4"
            case Unicode.Scalar("५"): out += "5"
            case Unicode.Scalar("६"): out += "6"
            case Unicode.Scalar("७"): out += "7"
            case Unicode.Scalar("८"): out += "8"
            case Unicode.Scalar("९"): out += "9"
            default:
                if devanagariRange ~= scalar {
                    // Unknown Devanagari (rare vedic marks, spacing). Keep the
                    // shape of the line rather than dropping the word silently.
                    out += "?"
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }

        return out
    }
}
