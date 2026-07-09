struct PDFType0FontObject {
    var resourceName: String
    var baseName: String
    var descendantFont: PDFSyntax.Reference
    /// Optional. Absent only when the font resource draws nothing but `.notdef`
    /// glyphs (every scalar it was asked to render was missing from its cmap), so
    /// there is no code with a recoverable character to map. `/ToUnicode` is
    /// optional in a plain PDF; a conformance profile never reaches this state
    /// because it refuses a missing glyph instead of drawing notdef.
    var toUnicodeMap: PDFSyntax.Reference?

    init(
        resourceName: String,
        baseName: String,
        descendantFont: PDFSyntax.Reference,
        toUnicodeMap: PDFSyntax.Reference?,
    ) {
        precondition(!resourceName.isEmpty, "Type 0 font objects require a resource name")
        precondition(!baseName.isEmpty, "Type 0 font objects require a base font name")
        self.resourceName = resourceName
        self.baseName = baseName
        self.descendantFont = descendantFont
        self.toUnicodeMap = toUnicodeMap
    }

    var pdfDictionary: PDFSyntax.Dictionary {
        var entries: [PDFSyntax.Dictionary.Entry] = [
            .init("Type", .pdfName("Font")),
            .init("Subtype", .pdfName("Type0")),
            .init("BaseFont", .pdfName(baseName)),
            .init("Encoding", .pdfName("Identity-H")),
            .init("DescendantFonts", .pdfArray([.reference(descendantFont)])),
        ]
        if let toUnicodeMap {
            entries.append(.init("ToUnicode", .reference(toUnicodeMap)))
        }
        return PDFSyntax.Dictionary(entries)
    }
}
