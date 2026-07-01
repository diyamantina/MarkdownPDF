struct PDFCIDFontWidths: Equatable {
    enum Segment: Equatable {
        case array(startCID: Int, widths: [Int])
        case range(startCID: Int, endCID: Int, width: Int)
    }

    var segments: [Segment]

    init(segments: [Segment]) {
        precondition(!segments.isEmpty, "CID font widths require at least one segment")
        for segment in segments {
            switch segment {
            case let .array(startCID, widths):
                precondition(startCID >= 0, "CID font array width segments require a non-negative start CID")
                precondition(!widths.isEmpty, "CID font array width segments cannot be empty")
                precondition(widths.allSatisfy { $0 >= 0 }, "CID font widths must be non-negative")
            case let .range(startCID, endCID, width):
                precondition(startCID >= 0, "CID font range width segments require a non-negative start CID")
                precondition(endCID >= 0, "CID font range width segments require a non-negative end CID")
                precondition(startCID <= endCID, "CID font range width segments must be ordered")
                precondition(width >= 0, "CID font widths must be non-negative")
            }
        }
        self.segments = segments
    }

    var pdfValue: PDFSyntax.Value {
        .pdfArray(segments.flatMap(\.pdfValues))
    }
}

private extension PDFCIDFontWidths.Segment {
    var pdfValues: [PDFSyntax.Value] {
        switch self {
        case let .array(startCID, widths):
            [
                .int(startCID),
                .pdfArray(widths.map { .int($0) }),
            ]
        case let .range(startCID, endCID, width):
            [
                .int(startCID),
                .int(endCID),
                .int(width),
            ]
        }
    }
}
