import Foundation

enum PDFEmbeddedFontError: Error, Equatable, LocalizedError {
    case emptyGlyphSet(resourceName: String)
    case reservedBaseFontResourceName(String)
    case conflictingFontResource(resourceName: String)
    case conflictingCIDWidth(cid: UInt16, existing: UInt16, duplicate: UInt16)
    case conflictingToUnicodeMapping(code: UInt16, existing: String, duplicate: String)
    case unsupportedShapedToUnicodeCluster(sourceRange: Range<Int>, glyphCount: Int, scalarCount: Int)
    case unsupportedComplexScriptScalar(scalar: UnicodeScalar)
    case unavailableMirroredGlyphCode(source: UnicodeScalar, display: UnicodeScalar)

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
        case let .conflictingToUnicodeMapping(code, existing, duplicate):
            "PDF character code \(code) maps to both \(existing) and \(duplicate)."
        case let .unsupportedShapedToUnicodeCluster(sourceRange, glyphCount, scalarCount):
            "Shaped cluster \(sourceRange) has \(glyphCount) glyphs for \(scalarCount) source scalars, which is not supported for PDF emission yet."
        case let .unsupportedComplexScriptScalar(scalar):
            "Embedded-font PDF emission does not yet support complex-script scalar U+\(Self.hex(scalar.value))."
        case let .unavailableMirroredGlyphCode(source, display):
            "Embedded-font PDF emission cannot allocate a mirrored glyph code for U+\(Self.hex(source.value)) displayed as U+\(Self.hex(display.value))."
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
        case .conflictingToUnicodeMapping:
            "Assign one stable source Unicode sequence to each emitted PDF character code."
        case .unsupportedShapedToUnicodeCluster:
            "Keep this shaped run on an explicit unsupported path until its PDF ToUnicode mapping policy is defined."
        case .unsupportedComplexScriptScalar:
            "Keep complex-script text on an explicit unsupported path until shaping, ordering, extraction, and geometry witnesses cover that script."
        case .unavailableMirroredGlyphCode:
            "Use a font with spare CID space for mirrored punctuation or keep the input on an explicit unsupported path."
        }
    }

    private static func hex(_ value: UInt32) -> String {
        String(format: "%04X", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
