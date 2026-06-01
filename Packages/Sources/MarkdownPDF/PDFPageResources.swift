struct PDFPageResources {
    var fonts: [Entry] = []
    var imageXObjects: [Entry] = []
    var formXObjects: [Entry] = []
    var extGStates: [Entry] = []
    var patterns: [Entry] = []

    var pdfDictionary: PDFSyntax.Dictionary {
        var entries: [PDFSyntax.Dictionary.Entry] = []
        if !extGStates.isEmpty {
            entries.append(.init("ExtGState", .dictionary(PDFSyntax.Dictionary(extGStates.map(\.pdfEntry)))))
        }
        if !fonts.isEmpty {
            entries.append(.init("Font", .dictionary(PDFSyntax.Dictionary(fonts.map(\.pdfEntry)))))
        }

        let xObjects = imageXObjects + formXObjects
        if !xObjects.isEmpty {
            entries.append(.init("XObject", .dictionary(PDFSyntax.Dictionary(xObjects.map(\.pdfEntry)))))
        }
        if !patterns.isEmpty {
            entries.append(.init("Pattern", .dictionary(PDFSyntax.Dictionary(patterns.map(\.pdfEntry)))))
        }
        return PDFSyntax.Dictionary(entries)
    }

    struct Entry {
        var name: String
        var objectRef: PDFSyntax.Reference

        var pdfEntry: PDFSyntax.Dictionary.Entry {
            .init(name, .reference(objectRef))
        }
    }
}
