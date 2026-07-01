import Foundation

enum PDFToUnicodeCMapError: Error, Equatable, LocalizedError {
    case emptyMapping
    case conflictingMapping(code: UInt16, existing: String, duplicate: String)

    var errorDescription: String? {
        switch self {
        case .emptyMapping:
            "A ToUnicode CMap requires at least one emitted PDF character code."
        case let .conflictingMapping(code, existing, duplicate):
            "PDF character code \(code) maps to both `\(existing)` and `\(duplicate)`."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .emptyMapping:
            "Only create a ToUnicode CMap for embedded-font text that emitted at least one glyph."
        case .conflictingMapping:
            "Use a font code assignment where each emitted PDF character code maps to one Unicode scalar sequence."
        }
    }
}
