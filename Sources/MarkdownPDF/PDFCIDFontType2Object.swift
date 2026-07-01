struct PDFCIDFontType2Object {
    enum CIDToGIDMap: Equatable {
        case identity
        case stream(PDFSyntax.Reference)

        var pdfValue: PDFSyntax.Value {
            switch self {
            case .identity:
                .pdfName("Identity")
            case let .stream(reference):
                .reference(reference)
            }
        }
    }

    var baseName: String
    var cidSystemInfo: PDFCIDSystemInfo
    var fontDescriptor: PDFSyntax.Reference
    var widths: PDFCIDFontWidths
    var cidToGIDMap: CIDToGIDMap

    init(
        baseName: String,
        cidSystemInfo: PDFCIDSystemInfo = .identity,
        fontDescriptor: PDFSyntax.Reference,
        widths: PDFCIDFontWidths,
        cidToGIDMap: CIDToGIDMap = .identity,
    ) {
        precondition(!baseName.isEmpty, "CIDFontType2 objects require a base font name")
        self.baseName = baseName
        self.cidSystemInfo = cidSystemInfo
        self.fontDescriptor = fontDescriptor
        self.widths = widths
        self.cidToGIDMap = cidToGIDMap
    }

    var pdfDictionary: PDFSyntax.Dictionary {
        PDFSyntax.Dictionary([
            .init("Type", .pdfName("Font")),
            .init("Subtype", .pdfName("CIDFontType2")),
            .init("BaseFont", .pdfName(baseName)),
            .init("CIDSystemInfo", .dictionary(cidSystemInfo.pdfDictionary)),
            .init("FontDescriptor", .reference(fontDescriptor)),
            .init("W", widths.pdfValue),
            .init("CIDToGIDMap", cidToGIDMap.pdfValue),
        ])
    }
}
