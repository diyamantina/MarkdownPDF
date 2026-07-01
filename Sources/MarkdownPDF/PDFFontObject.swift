struct PDFFontObject {
    var resourceName: String
    var baseName: String
    var subtype: String
    var encoding: String
    var metrics: PDFSimpleFontMetrics?
    var fontDescriptor: PDFFontDescriptor?
    var descendantFonts: [PDFSyntax.Reference]
    var toUnicodeMap: PDFSyntax.Reference?

    init(font: StandardFont, fontSet: PDFOptions.FontSet) {
        let baseName = font.baseName(in: fontSet)
        let usesBaseType1Font = font.subtype(in: fontSet) == "Type1"
        let subtype = usesBaseType1Font ? "Type1" : "TrueType"

        self.init(
            resourceName: font.rawValue,
            baseName: baseName,
            subtype: subtype,
            encoding: "WinAnsiEncoding",
            metrics: usesBaseType1Font ? nil : PDFSimpleFontMetrics(firstCharacter: 32, widths: font.widthsForPDF(in: fontSet)),
            fontDescriptor: usesBaseType1Font ? nil : PDFFontDescriptor(fontName: baseName, italicAngle: font.italicAngle),
        )
    }

    init(
        resourceName: String,
        baseName: String,
        subtype: String,
        encoding: String = "WinAnsiEncoding",
        metrics: PDFSimpleFontMetrics? = nil,
        fontDescriptor: PDFFontDescriptor? = nil,
        descendantFonts: [PDFSyntax.Reference] = [],
        toUnicodeMap: PDFSyntax.Reference? = nil,
    ) {
        self.resourceName = resourceName
        self.baseName = baseName
        self.subtype = subtype
        self.encoding = encoding
        self.metrics = metrics
        self.fontDescriptor = fontDescriptor
        self.descendantFonts = descendantFonts
        self.toUnicodeMap = toUnicodeMap
    }

    func pdfDictionary(fontDescriptor descriptorReference: PDFSyntax.Reference?) -> PDFSyntax.Dictionary {
        var entries: [PDFSyntax.Dictionary.Entry] = [
            .init("Type", .pdfName("Font")),
            .init("Subtype", .pdfName(subtype)),
            .init("BaseFont", .pdfName(baseName)),
            .init("Encoding", .pdfName(encoding)),
        ]

        if let metrics {
            entries.append(contentsOf: metrics.pdfEntries)
        }
        if let descriptorReference {
            entries.append(.init("FontDescriptor", .reference(descriptorReference)))
        }
        if !descendantFonts.isEmpty {
            entries.append(.init("DescendantFonts", .pdfArray(descendantFonts.map { .reference($0) })))
        }
        if let toUnicodeMap {
            entries.append(.init("ToUnicode", .reference(toUnicodeMap)))
        }

        return PDFSyntax.Dictionary(entries)
    }
}
