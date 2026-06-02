struct PDFDocumentCatalog {
    var pages: PDFSyntax.Reference
    var outlines: PDFSyntax.Reference?
    var names: PDFSyntax.Dictionary?
    var metadata: PDFSyntax.Reference?
    var outputIntents: [PDFOutputIntent] = []
    var structTreeRoot: PDFSyntax.Reference?
    var language: String?
    var marked: Bool = false
    var displayDocumentTitle: Bool

    var pdfDictionary: PDFSyntax.Dictionary {
        var entries: [PDFSyntax.Dictionary.Entry] = [
            .init("Type", .pdfName("Catalog")),
            .init("Pages", .reference(pages)),
        ]
        if let outlines {
            entries.append(.init("Outlines", .reference(outlines)))
            entries.append(.init("PageMode", .pdfName("UseOutlines")))
        }
        if let names {
            entries.append(.init("Names", .dictionary(names)))
        }
        if let metadata {
            entries.append(.init("Metadata", .reference(metadata)))
        }
        if !outputIntents.isEmpty {
            entries.append(.init(
                "OutputIntents",
                .pdfArray(outputIntents.map { .dictionary($0.pdfDictionary) }),
            ))
        }
        if marked {
            entries.append(
                .init(
                    "MarkInfo",
                    .pdfDictionary([
                        .init("Marked", .bool(true)),
                    ]),
                ),
            )
        }
        if let structTreeRoot {
            entries.append(.init("StructTreeRoot", .reference(structTreeRoot)))
        }
        if let language {
            entries.append(.init("Lang", .pdfString(language)))
        }
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
