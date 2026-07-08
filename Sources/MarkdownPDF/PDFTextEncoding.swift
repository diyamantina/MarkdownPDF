enum PDFTextEncoding {
    /// Text used for the page's `/ActualText` span and as the source string the
    /// content-stream encoder walks. It is the original Unicode, unchanged, so
    /// extraction and copy recover the real characters even where the drawn
    /// glyph is a fallback. (Formerly this substituted "?" for non-ASCII.)
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

    /// Scalars used to measure run width: the original scalars, with any scalar
    /// the base-14 WinAnsi set cannot draw mapped to the fallback glyph so the
    /// measured width matches what is painted.
    static func portableScalars(for text: String) -> [UnicodeScalar] {
        text.unicodeScalars.map { isRepresentable($0) ? $0 : replacementScalar }
    }

    /// The byte written to the content stream for a scalar under
    /// `/WinAnsiEncoding`. WinAnsi-representable scalars map to their CP1252
    /// byte; anything else falls back to "?" (the original codepoint is still
    /// preserved in the `/ActualText` span, so the text stays recoverable).
    static func encodedByte(for scalar: UnicodeScalar) -> UInt8 {
        winAnsiByte(for: scalar) ?? UInt8(replacementScalar.value)
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
