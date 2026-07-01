enum PDFTextEncoding {
    /// Text used for the page's `/ActualText` span and as the source string the
    /// content-stream encoder walks. It is the original Unicode, unchanged, so
    /// extraction and copy recover the real characters even where the drawn
    /// glyph is a fallback. (Formerly this substituted "?" for non-ASCII.)
    static func portableText(for text: String) -> String {
        text
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
