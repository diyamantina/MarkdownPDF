struct PDFCIDSystemInfo: Equatable {
    var registry: String
    var ordering: String
    var supplement: Int

    init(registry: String, ordering: String, supplement: Int) {
        precondition(!registry.isEmpty, "CID system info requires a registry")
        precondition(!ordering.isEmpty, "CID system info requires an ordering")
        precondition(supplement >= 0, "CID system info supplement must be non-negative")
        self.registry = registry
        self.ordering = ordering
        self.supplement = supplement
    }

    static let identity = PDFCIDSystemInfo(
        registry: "Adobe",
        ordering: "Identity",
        supplement: 0,
    )

    var pdfDictionary: PDFSyntax.Dictionary {
        PDFSyntax.Dictionary([
            .init("Registry", .pdfString(registry)),
            .init("Ordering", .pdfString(ordering)),
            .init("Supplement", .int(supplement)),
        ])
    }
}
