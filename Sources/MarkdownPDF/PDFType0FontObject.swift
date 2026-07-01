struct PDFType0FontObject {
    var resourceName: String
    var baseName: String
    var descendantFont: PDFSyntax.Reference
    var toUnicodeMap: PDFSyntax.Reference

    init(
        resourceName: String,
        baseName: String,
        descendantFont: PDFSyntax.Reference,
        toUnicodeMap: PDFSyntax.Reference,
    ) {
        precondition(!resourceName.isEmpty, "Type 0 font objects require a resource name")
        precondition(!baseName.isEmpty, "Type 0 font objects require a base font name")
        self.resourceName = resourceName
        self.baseName = baseName
        self.descendantFont = descendantFont
        self.toUnicodeMap = toUnicodeMap
    }

    var pdfDictionary: PDFSyntax.Dictionary {
        PDFSyntax.Dictionary([
            .init("Type", .pdfName("Font")),
            .init("Subtype", .pdfName("Type0")),
            .init("BaseFont", .pdfName(baseName)),
            .init("Encoding", .pdfName("Identity-H")),
            .init("DescendantFonts", .pdfArray([.reference(descendantFont)])),
            .init("ToUnicode", .reference(toUnicodeMap)),
        ])
    }
}
