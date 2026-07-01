import Foundation

enum TrueTypeFontError: Error, Equatable, LocalizedError {
    case emptyFont
    case unsupportedScalerType(UInt32)
    case truncated(table: String, offset: Int, needed: Int, tableLength: Int)
    case duplicateTable(String)
    case missingRequiredTable(String)
    case invalidTableBounds(tag: String, offset: UInt32, length: UInt32, fileLength: Int)
    case invalidTableChecksum(tag: String, expected: UInt32, actual: UInt32)
    case malformedTable(tag: String, reason: String)
    case unsupportedCMap(reason: String)
    case restrictedEmbedding(fsType: UInt16)
    case bitmapOnlyEmbedding(fsType: UInt16)
    case subsettingRequired(fsType: UInt16)
    case unsupportedFontFormat(format: String, guidance: String)

    var errorDescription: String? {
        switch self {
        case .emptyFont:
            "The TrueType font data is empty."
        case let .unsupportedScalerType(scalerType):
            "Unsupported TrueType scaler type 0x\(Self.hex(scalerType))."
        case let .truncated(table, offset, needed, tableLength):
            "The \(table) table is truncated at byte \(offset); needed \(needed) bytes in \(tableLength) bytes."
        case let .duplicateTable(tag):
            "The TrueType table directory contains duplicate `\(tag)` records."
        case let .missingRequiredTable(tag):
            "The TrueType font is missing required table `\(tag)`."
        case let .invalidTableBounds(tag, offset, length, fileLength):
            "The `\(tag)` table range offset \(offset), length \(length) exceeds the \(fileLength) byte font."
        case let .invalidTableChecksum(tag, expected, actual):
            "The `\(tag)` table checksum is 0x\(Self.hex(actual)); expected 0x\(Self.hex(expected))."
        case let .malformedTable(tag, reason):
            "The `\(tag)` table is malformed: \(reason)"
        case let .unsupportedCMap(reason):
            "Unsupported TrueType cmap table: \(reason)"
        case let .restrictedEmbedding(fsType):
            "The OS/2 fsType value 0x\(Self.hex(fsType)) restricts embedding."
        case let .bitmapOnlyEmbedding(fsType):
            "The OS/2 fsType value 0x\(Self.hex(fsType)) allows only bitmap embedding."
        case let .subsettingRequired(fsType):
            "The OS/2 fsType value 0x\(Self.hex(fsType)) forbids subsetting."
        case let .unsupportedFontFormat(format, _):
            "The \(format) font format is not supported for embedding yet."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .emptyFont:
            "Pass a complete TrueType font program."
        case .unsupportedScalerType:
            "Use a TrueType-flavored sfnt font with scaler type 0x00010000 or `true`."
        case .truncated, .invalidTableBounds:
            "Replace the font with an untruncated TrueType file."
        case .duplicateTable:
            "Use a font with one directory record for each table tag."
        case .missingRequiredTable:
            "Use a TrueType font that includes the required metadata tables."
        case .invalidTableChecksum:
            "Use an unmodified font or rebuild the table directory checksums."
        case .malformedTable:
            "Replace the font with a valid TrueType font."
        case .unsupportedCMap:
            "Use a font with a Unicode cmap subtable in format 4 or 12."
        case .restrictedEmbedding:
            "Choose a font whose license permits embedding."
        case .bitmapOnlyEmbedding:
            "Choose a font that permits outline embedding."
        case .subsettingRequired:
            "Choose a font that permits subsetting or use an embedding policy that does not require subsets."
        case let .unsupportedFontFormat(_, guidance):
            guidance
        }
    }

    private static func hex(_ value: UInt16) -> String {
        String(format: "%04X", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func hex(_ value: UInt32) -> String {
        String(format: "%08X", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
