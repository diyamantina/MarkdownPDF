struct PDFPageDictionary {
    var parent: PDFSyntax.Reference
    var mediaBox: PDFOptions.PageSize
    var resources: PDFSyntax.Dictionary
    var contents: PDFSyntax.Reference
    var annotations: [PDFSyntax.Reference]
    var structParents: Int?

    var pdfDictionary: PDFSyntax.Dictionary {
        var entries: [PDFSyntax.Dictionary.Entry] = [
            .init("Type", .pdfName("Page")),
            .init("Parent", .reference(parent)),
            .init(
                "MediaBox",
                .pdfArray([
                    .int(0),
                    .int(0),
                    .number(mediaBox.width),
                    .number(mediaBox.height),
                ]),
            ),
            .init("Resources", .dictionary(resources)),
            .init("Contents", .reference(contents)),
        ]
        if let structParents {
            entries.append(.init("StructParents", .int(structParents)))
        }
        if !annotations.isEmpty {
            entries.append(.init("Annots", .pdfArray(annotations.map { .reference($0) })))
        }
        return PDFSyntax.Dictionary(entries)
    }
}
