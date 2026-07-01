import Foundation

enum TrueTypeGlyphMappingError: Error, Equatable, LocalizedError {
    case invalidFontSize(Double)
    case missingTable(String)
    case missingGlyph(UnicodeScalar)
    case invalidGlyphID(UInt32, numGlyphs: UInt16)
    case malformedCMap(format: UInt16, reason: String)

    var errorDescription: String? {
        switch self {
        case let .invalidFontSize(fontSize):
            "Embedded-font glyph mapping requires a positive finite font size, got \(fontSize)."
        case let .missingTable(tag):
            "The TrueType font is missing required table `\(tag)` for glyph mapping."
        case let .missingGlyph(scalar):
            "The TrueType cmap does not contain U+\(Self.hex(scalar.value))."
        case let .invalidGlyphID(glyphID, numGlyphs):
            "The TrueType cmap references glyph \(glyphID), but the font declares \(numGlyphs) glyphs."
        case let .malformedCMap(format, reason):
            "The TrueType cmap format \(format) subtable is malformed: \(reason)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidFontSize:
            "Pass a positive finite font size before measuring TrueType glyph widths."
        case .missingTable:
            "Parse a complete TrueType font before mapping glyphs."
        case .missingGlyph:
            "Use a font whose Unicode cmap covers the source text, or enable the notdef fallback policy."
        case .invalidGlyphID:
            "Use a cmap whose glyph ids are within the maxp glyph count."
        case .malformedCMap:
            "Replace the font with a valid TrueType font."
        }
    }

    private static func hex(_ value: UInt32) -> String {
        String(format: "%04X", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
