import Foundation

enum PDFEmbeddedFontError: Error, Equatable, LocalizedError {
    case emptyGlyphSet(resourceName: String)
    case reservedBaseFontResourceName(String)
    case conflictingFontResource(resourceName: String)
    case conflictingCIDWidth(cid: UInt16, existing: UInt16, duplicate: UInt16)

    var errorDescription: String? {
        switch self {
        case let .emptyGlyphSet(resourceName):
            "Embedded font resource \(resourceName) has no mapped glyphs."
        case let .reservedBaseFontResourceName(resourceName):
            "Embedded font resource \(resourceName) conflicts with a base-font resource name."
        case let .conflictingFontResource(resourceName):
            "Embedded font resource \(resourceName) was used with different font programs or metadata."
        case let .conflictingCIDWidth(cid, existing, duplicate):
            "CID \(cid) has conflicting widths: \(existing) and \(duplicate)."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .emptyGlyphSet:
            "Skip empty text runs before recording embedded font usage."
        case .reservedBaseFontResourceName:
            "Use a resource name that is separate from the standard F1 to F4 base-font names."
        case .conflictingFontResource:
            "Use a stable resource name for one font program, or allocate a separate resource name for each font."
        case .conflictingCIDWidth:
            "Ensure each CID maps to one glyph advance width before writing the CIDFont widths array."
        }
    }
}
