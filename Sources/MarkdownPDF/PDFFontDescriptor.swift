struct PDFFontDescriptor {
    var fontName: String
    var flags: Int = 32
    var fontBoundingBox: [Int] = [-200, -250, 1200, 1000]
    var italicAngle: Int
    var ascent: Int = 900
    var descent: Int = -220
    var capHeight: Int = 700
    var stemV: Int = 80
    var embeddedFontFile: EmbeddedFontFile?

    var pdfDictionary: PDFSyntax.Dictionary {
        var entries: [PDFSyntax.Dictionary.Entry] = [
            .init("Type", .pdfName("FontDescriptor")),
            .init("FontName", .pdfName(fontName)),
            .init("Flags", .int(flags)),
            .init("FontBBox", .pdfArray(fontBoundingBox.map { .int($0) })),
            .init("ItalicAngle", .int(italicAngle)),
            .init("Ascent", .int(ascent)),
            .init("Descent", .int(descent)),
            .init("CapHeight", .int(capHeight)),
            .init("StemV", .int(stemV)),
        ]

        if let embeddedFontFile {
            entries.append(embeddedFontFile.pdfEntry)
        }

        return PDFSyntax.Dictionary(entries)
    }

    enum EmbeddedFontFile {
        case type1(PDFSyntax.Reference)
        case trueType(PDFSyntax.Reference)
        case fontFile3(PDFSyntax.Reference)

        var pdfEntry: PDFSyntax.Dictionary.Entry {
            switch self {
            case let .type1(reference):
                .init("FontFile", .reference(reference))
            case let .trueType(reference):
                .init("FontFile2", .reference(reference))
            case let .fontFile3(reference):
                .init("FontFile3", .reference(reference))
            }
        }
    }
}
