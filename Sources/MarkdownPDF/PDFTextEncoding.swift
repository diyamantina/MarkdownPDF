import Foundation

enum PDFTextEncoding {
    /// Text used for the page's `/ActualText` span and as the source string the
    /// base-14 content-stream encoder walks. It is the original Unicode, unchanged,
    /// so extraction and copy recover the real characters even where the drawn glyph
    /// is a fallback. (Formerly this substituted "?" for non-ASCII.)
    ///
    /// NFC normalization for the base-14 path is applied downstream, not here: at
    /// ``PDFSyntax/LiteralString/serialized`` for the emitted WinAnsi bytes (so a
    /// decomposed diacritic draws as its single precomposed byte) and at
    /// ``portableScalars(for:)`` for the matching measured width. Keeping this
    /// faithful means the two consumers each normalize once and the value stays the
    /// authored text.
    static func portableText(for text: String) -> String {
        text
    }

    /// Removes the Unicode default-ignorable format controls that must render
    /// invisibly when the active font has no glyph for them: the zero-width space,
    /// joiner and non-joiner, the word joiner and invisible operators, the soft
    /// hyphen, the variation selectors, the Mongolian and shorthand and musical
    /// format controls, the Hangul fillers, and the byte order mark.
    ///
    /// Per Unicode, a default-ignorable code point the font cannot draw renders
    /// as nothing, not as a missing glyph. Without this strip these scalars paint
    /// `?` on the base-14 path (a visible hyphen for the soft hyphen) and, worse,
    /// abort the whole render on the embedded path: a cmap that omits them makes
    /// `TrueTypeGlyphMapper` throw `missingGlyph`. A ZWSP pasted from a web page is
    /// as plausible as a BOM, so removing them here keeps width, glyphs, and the
    /// `/ActualText` span consistent across both paths.
    ///
    /// This set is deliberately narrow. It excludes scalars that are
    /// default-ignorable for *glyph* purposes but are still semantically
    /// load-bearing, because dropping those changes meaning, not just appearance:
    /// - the explicit bidi controls (U+061C, U+200E/200F, U+202A...U+202E,
    ///   U+2066...U+2069) drive paragraph ordering; `BidiParagraphOrdering` owns
    ///   them and refuses text it cannot order rather than reorder it wrongly, so
    ///   stripping them here would silently produce UBA-divergent visual order;
    /// - the line and paragraph separators (U+2028/U+2029) are Zl/Zp word
    ///   boundaries, not default-ignorable, so deleting one fuses the words it
    ///   split;
    /// - the interlinear annotation controls (U+FFF9...U+FFFB) delimit ruby text,
    ///   so deleting a separator merges annotation into base text.
    /// It also excludes the reserved-but-unassigned default-ignorable code points:
    /// an unassigned scalar is a genuinely absent glyph, handled by the per-scalar
    /// fallback rather than silently dropped.
    static func strippingInvisibleFormatControls(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: isInvisibleFormatControl) else {
            return text
        }
        return String(String.UnicodeScalarView(text.unicodeScalars.filter { !isInvisibleFormatControl($0) }))
    }

    /// Whether `scalar` is a genuinely-invisible, semantically-inert
    /// default-ignorable format control (see
    /// ``strippingInvisibleFormatControls(_:)`` for the exclusions).
    static func isInvisibleFormatControl(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x00AD, // SOFT HYPHEN
             0x034F, // COMBINING GRAPHEME JOINER
             0x115F, 0x1160, // HANGUL CHOSEONG / JUNGSEONG FILLER
             0x17B4, 0x17B5, // KHMER VOWEL INHERENT AQ / AA
             0x180B ... 0x180F, // MONGOLIAN FREE VARIATION SELECTORS, VOWEL SEPARATOR
             0x200B ... 0x200D, // ZERO WIDTH SPACE, NON-JOINER, JOINER
             0x2060 ... 0x2064, // WORD JOINER + invisible operators
             0x206A ... 0x206F, // deprecated symmetric-swapping / shaping / digit format controls
             0x3164, // HANGUL FILLER
             0xFE00 ... 0xFE0F, // VARIATION SELECTORS 1-16
             0xFEFF, // ZERO WIDTH NO-BREAK SPACE / BYTE ORDER MARK
             0xFFA0, // HALFWIDTH HANGUL FILLER
             0x1BCA0 ... 0x1BCA3, // SHORTHAND FORMAT CONTROLS
             0x1D173 ... 0x1D17A, // MUSICAL SYMBOL begin / end format controls
             0xE0001, // LANGUAGE TAG
             0xE0020 ... 0xE007F, // TAG code points
             0xE0100 ... 0xE01EF: // VARIATION SELECTORS SUPPLEMENT
            true
        default:
            false
        }
    }

    /// Scalars used to measure run width: the NFC-normalized scalars (matching what
    /// ``portableText(for:)`` draws), with any scalar the base-14 WinAnsi set cannot
    /// draw mapped to the fallback glyph so the measured width matches what is
    /// painted. Normalizing here keeps the measured advance in step with the drawn
    /// bytes for a decomposed diacritic that folds to one WinAnsi code point.
    static func portableScalars(for text: String) -> [UnicodeScalar] {
        text.precomposedStringWithCanonicalMapping.unicodeScalars.map { scalar in
            // Measure the glyph that is actually drawn: the scalar itself, or its ASCII
            // stand-in, or the "?" fallback, so the advance matches the painted byte.
            if isRepresentable(scalar) {
                return scalar
            }
            return asciiApproximation(for: scalar) ?? replacementScalar
        }
    }

    /// The byte written to the content stream for a scalar under
    /// `/WinAnsiEncoding`. WinAnsi-representable scalars map to their CP1252
    /// byte; a scalar with an ASCII stand-in (box-drawing and block-element line
    /// art) draws that stand-in; anything else falls back to "?" (the original
    /// codepoint is preserved in the `/ActualText` span, so the text stays
    /// recoverable whichever glyph is drawn).
    static func encodedByte(for scalar: UnicodeScalar) -> UInt8 {
        if let byte = winAnsiByte(for: scalar) {
            return byte
        }
        if let approximation = asciiApproximation(for: scalar), let byte = winAnsiByte(for: approximation) {
            return byte
        }
        return UInt8(replacementScalar.value)
    }

    /// An ASCII stand-in the base-14 WinAnsi fonts can draw for a scalar they would
    /// otherwise paint as "?", so line art, diagrams, and technical notation keep their
    /// shape instead of dissolving into question marks. It covers only characters with an
    /// honest single-character ASCII match: the Box Drawing and Block Elements blocks
    /// (tree and table art), Geometric Shapes (diagram markers), the cardinal and double
    /// arrows, super- and sub-scripts (folded to their base character), and the dash,
    /// minus, prime, and Unicode-space variants. Characters with no faithful ASCII form
    /// (☀, ♠, ✓, most symbols and dingbats) are left to the "?" fallback rather than folded
    /// to something misleading. This changes the drawn (and, on the base-14 path, the
    /// extracted) glyph, the same trade the "?" fallback already made, but leaves a readable
    /// result; a font that covers the real characters (an embedded face) still draws them
    /// and is unaffected.
    static func asciiApproximation(for scalar: UnicodeScalar) -> UnicodeScalar? {
        let value = scalar.value
        // Superscript and subscript digits fold to the base digit.
        if value == 0x2070 || (0x2074 ... 0x2079).contains(value) { // superscript 0, 4-9
            return UnicodeScalar(0x30 + (value == 0x2070 ? 0 : value - 0x2074 + 4))
        }
        if (0x2080 ... 0x2089).contains(value) { // subscript 0-9
            return UnicodeScalar(0x30 + value - 0x2080)
        }
        switch value {
        // Box drawing: horizontal, vertical, diagonals, then corners/tees/crosses.
        case 0x2500, 0x2501, 0x2504, 0x2505, 0x2508, 0x2509,
             0x254C, 0x254D, 0x2550, 0x2574, 0x2576, 0x2578, 0x257A, 0x257C, 0x257E:
            return "-"
        case 0x2502, 0x2503, 0x2506, 0x2507, 0x250A, 0x250B,
             0x254E, 0x254F, 0x2551, 0x2575, 0x2577, 0x2579, 0x257B, 0x257D, 0x257F:
            return "|"
        case 0x2571:
            return "/"
        case 0x2572:
            return "\\"
        case 0x2573:
            return "X"
        case 0x2500 ... 0x257F: // remaining box drawing: corners, tees, crosses
            return "+"
        case 0x2580 ... 0x259F: // block elements and shades
            return "#"
        // Geometric shapes: triangles point their way, filled shapes to "#", outlines to "o".
        case 0x25B2 ... 0x25B5: // up triangles
            return "^"
        case 0x25B6 ... 0x25BB: // right triangles
            return ">"
        case 0x25BC ... 0x25BF: // down triangles
            return "v"
        case 0x25C0 ... 0x25C5: // left triangles
            return "<"
        case 0x25A1, 0x25A2, 0x25AB, 0x25AD, 0x25AF, 0x25B1, 0x25C7, 0x25CA, 0x25CB,
             0x25CE, 0x25E6, 0x25EF, 0x25FB, 0x25FD: // outline shapes / circles
            return "o"
        case 0x25A0 ... 0x25FF: // remaining filled shapes
            return "#"
        // Cardinal and double-headed arrows.
        case 0x2190, 0x21D0, 0x21E0, 0x21A4, 0x21BC, 0x21BD, 0x2B05:
            return "<"
        case 0x2192, 0x21D2, 0x21E2, 0x21A6, 0x21C0, 0x21C1, 0x2B95, 0x2B0E:
            return ">"
        case 0x2191, 0x21D1, 0x21E1, 0x21A5, 0x2B06:
            return "^"
        case 0x2193, 0x21D3, 0x21E3, 0x21A7, 0x2B07:
            return "v"
        case 0x2194, 0x21D4:
            return "-"
        case 0x2195, 0x21D5, 0x21A8:
            return "|"
        // Super- and sub-script signs and the common letters.
        case 0x207A, 0x208A:
            return "+"
        case 0x207B, 0x208B, 0x2212:
            return "-" // superscript/subscript minus, and the minus sign
        case 0x207C, 0x208C:
            return "="
        case 0x207D, 0x208D:
            return "("
        case 0x207E, 0x208E:
            return ")"
        case 0x2071:
            return "i"
        case 0x207F, 0x2099:
            return "n"
        case 0x2090:
            return "a"
        case 0x2091:
            return "e"
        case 0x2092:
            return "o"
        case 0x2093:
            return "x"
        // Prime marks and the dash / hyphen / space variants.
        case 0x2032, 0x2035:
            return "'"
        case 0x2033, 0x2034, 0x2036, 0x2037:
            return "\""
        case 0x2010, 0x2011, 0x2012, 0x2015, 0x2043:
            return "-"
        case 0x2000 ... 0x200A, 0x202F, 0x205F, 0x3000:
            return " "
        default:
            return nil
        }
    }

    /// Whether the base-14 fonts can draw `scalar` through WinAnsiEncoding.
    static func isRepresentable(_ scalar: UnicodeScalar) -> Bool {
        winAnsiByte(for: scalar) != nil
    }

    /// Maps a Unicode scalar to its Windows-1252 (WinAnsi) byte, or nil when the
    /// encoding cannot represent it. ASCII and Latin-1 map to their codepoint;
    /// the CP1252 0x80-0x9F block (curly quotes, dashes, euro, ...) is explicit.
    static func winAnsiByte(for scalar: UnicodeScalar) -> UInt8? {
        switch scalar.value {
        case 0x08, 0x09, 0x0A, 0x0C, 0x0D:
            UInt8(scalar.value)
        case 0x20 ... 0x7E:
            UInt8(scalar.value)
        case 0xA0 ... 0xFF:
            UInt8(scalar.value)
        default:
            cp1252HighBlock[scalar]
        }
    }

    /// The Unicode scalar a WinAnsi byte maps to, used to build the font's
    /// `/Widths` array. Undefined CP1252 codes (0x81, 0x8D, 0x8F, 0x90, 0x9D)
    /// map to the replacement scalar.
    static func winAnsiScalar(for byte: UInt8) -> UnicodeScalar {
        switch byte {
        case 0x80 ... 0x9F:
            cp1252HighScalars[byte] ?? replacementScalar
        default:
            UnicodeScalar(byte)
        }
    }

    static let replacementScalar: UnicodeScalar = "?"

    private static let cp1252HighScalars: [UInt8: UnicodeScalar] = {
        var map: [UInt8: UnicodeScalar] = [:]
        for (scalar, byte) in cp1252HighBlock {
            map[byte] = scalar
        }
        return map
    }()

    private static let cp1252HighBlock: [UnicodeScalar: UInt8] = [
        "\u{20AC}": 0x80, "\u{201A}": 0x82, "\u{0192}": 0x83, "\u{201E}": 0x84,
        "\u{2026}": 0x85, "\u{2020}": 0x86, "\u{2021}": 0x87, "\u{02C6}": 0x88,
        "\u{2030}": 0x89, "\u{0160}": 0x8A, "\u{2039}": 0x8B, "\u{0152}": 0x8C,
        "\u{017D}": 0x8E, "\u{2018}": 0x91, "\u{2019}": 0x92, "\u{201C}": 0x93,
        "\u{201D}": 0x94, "\u{2022}": 0x95, "\u{2013}": 0x96, "\u{2014}": 0x97,
        "\u{02DC}": 0x98, "\u{2122}": 0x99, "\u{0161}": 0x9A, "\u{203A}": 0x9B,
        "\u{0153}": 0x9C, "\u{017E}": 0x9E, "\u{0178}": 0x9F,
    ]
}
