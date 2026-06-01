struct PDFDocumentCatalog {
    var pages: PDFSyntax.Reference
    var displayDocumentTitle: Bool

    var pdfDictionary: PDFSyntax.Dictionary {
        var entries: [PDFSyntax.Dictionary.Entry] = [
            .init("Type", .pdfName("Catalog")),
            .init("Pages", .reference(pages)),
        ]
        if displayDocumentTitle {
            entries.append(
                .init(
                    "ViewerPreferences",
                    .pdfDictionary([
                        .init("DisplayDocTitle", .bool(true)),
                    ]),
                ),
            )
        }
        return PDFSyntax.Dictionary(entries)
    }
}
