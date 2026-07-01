import Foundation

struct PDFEmbeddedFontResource: Equatable {
    var resourceName: String
    var baseName: String
    var fontProgram: Data
    var metadata: TrueTypeFontParser.Metadata

    init(
        resourceName: String,
        fontProgram: Data,
        metadata: TrueTypeFontParser.Metadata,
        baseName: String? = nil,
    ) {
        precondition(!resourceName.isEmpty, "Embedded font resources require a resource name")
        precondition(!fontProgram.isEmpty, "Embedded font resources require font program data")
        self.resourceName = resourceName
        self.fontProgram = fontProgram
        self.metadata = metadata
        self.baseName = Self.pdfBaseName(from: baseName ?? Self.metadataBaseName(metadata))
    }

    private static func metadataBaseName(_ metadata: TrueTypeFontParser.Metadata) -> String {
        metadata.names.namesByID[6]
            ?? metadata.names.namesByID[4]
            ?? metadata.names.namesByID[1]
            ?? "MarkdownPDFEmbeddedFont"
    }

    private static func pdfBaseName(from rawName: String) -> String {
        let sanitizedName = rawName.unicodeScalars.map { scalar -> String in
            if scalar.value >= 0x30, scalar.value <= 0x39
                || scalar.value >= 0x41, scalar.value <= 0x5A
                || scalar.value >= 0x61, scalar.value <= 0x7A
                || scalar.value == 0x2D
                || scalar.value == 0x5F
            {
                return String(scalar)
            }
            return "-"
        }.joined()
        let sanitized = sanitizedName
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return sanitized.isEmpty ? "MarkdownPDFEmbeddedFont" : sanitized
    }
}
