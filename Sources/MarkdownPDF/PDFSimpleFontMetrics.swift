struct PDFSimpleFontMetrics {
    var firstCharacter: Int
    var widths: [Int]

    init(firstCharacter: Int, widths: [Int]) {
        precondition(!widths.isEmpty, "PDF simple font metrics require at least one width")
        self.firstCharacter = firstCharacter
        self.widths = widths
    }

    var lastCharacter: Int {
        firstCharacter + widths.count - 1
    }

    var pdfEntries: [PDFSyntax.Dictionary.Entry] {
        [
            .init("FirstChar", .int(firstCharacter)),
            .init("LastChar", .int(lastCharacter)),
            .init("Widths", .pdfArray(widths.map { .int($0) })),
        ]
    }
}
