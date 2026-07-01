struct PDFDocumentPageTree {
    var kids: [PDFSyntax.Reference]

    var pdfDictionary: PDFSyntax.Dictionary {
        PDFSyntax.Dictionary([
            .init("Type", .pdfName("Pages")),
            .init("Kids", .pdfArray(kids.map { .reference($0) })),
            .init("Count", .int(kids.count)),
        ])
    }
}
