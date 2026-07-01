import Foundation

enum TrueTypeFontSubsetError: Error, Equatable, LocalizedError {
    case emptyGlyphSet
    case missingRequiredTable(String)
    case invalidGlyphID(UInt16, numGlyphs: UInt16)
    case invalidLocaTable(expectedEntries: Int, actualEntries: Int)
    case malformedGlyph(glyphID: UInt16, reason: String)
    case conflictingScalarMapping(UnicodeScalar, existing: UInt16, duplicate: UInt16)
    case conflictingCIDMapping(cid: UInt16, existing: UInt16, duplicate: UInt16)

    var errorDescription: String? {
        switch self {
        case .emptyGlyphSet:
            "TrueType subsetting requires at least one used glyph."
        case let .missingRequiredTable(tag):
            "The TrueType font is missing required subset table `\(tag)`."
        case let .invalidGlyphID(glyphID, numGlyphs):
            "Glyph id \(glyphID) is outside the font glyph count \(numGlyphs)."
        case let .invalidLocaTable(expectedEntries, actualEntries):
            "The loca table has \(actualEntries) entries; expected at least \(expectedEntries)."
        case let .malformedGlyph(glyphID, reason):
            "Glyph id \(glyphID) cannot be subset: \(reason)"
        case let .conflictingScalarMapping(scalar, existing, duplicate):
            "Unicode scalar U+\(Self.hex(scalar.value)) maps to glyph ids \(existing) and \(duplicate)."
        case let .conflictingCIDMapping(cid, existing, duplicate):
            "CID \(cid) maps to subset glyph ids \(existing) and \(duplicate)."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .emptyGlyphSet:
            "Skip empty text runs before requesting a TrueType subset."
        case .missingRequiredTable:
            "Use a TrueType font with glyf and loca outline tables."
        case .invalidGlyphID:
            "Build glyph usage from the same parsed font metadata that will be subset."
        case .invalidLocaTable, .malformedGlyph:
            "Replace the font with a valid TrueType outline font."
        case .conflictingScalarMapping:
            "Use one stable glyph mapping for each Unicode scalar in a font subset."
        case .conflictingCIDMapping:
            "Assign each PDF CID to one subset glyph id before writing the CIDToGIDMap."
        }
    }

    private static func hex(_ value: UInt32) -> String {
        String(format: "%04X", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
