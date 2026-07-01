struct PDFXObjectResource {
    var name: String
    var objectRef: PDFSyntax.Reference
    var kind: Kind

    var pdfEntry: PDFSyntax.Dictionary.Entry {
        .init(name, .reference(objectRef))
    }

    enum Kind: Equatable {
        case image
        case form
    }
}
