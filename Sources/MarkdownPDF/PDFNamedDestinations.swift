struct PDFNamedDestinations {
    var destinations: [ResolvedDestination]

    var pdfDictionary: PDFSyntax.Dictionary {
        let sorted = destinations.sorted { left, right in
            left.destination.name < right.destination.name
        }
        let nameValues = sorted.flatMap { resolved in
            [
                PDFSyntax.Value.pdfString(resolved.destination.name),
                .array(resolved.destination.destinationArray(page: resolved.page)),
            ]
        }

        return PDFSyntax.Dictionary([
            .init(
                "Dests",
                .pdfDictionary([
                    .init("Names", .pdfArray(nameValues)),
                ]),
            ),
        ])
    }

    struct ResolvedDestination {
        var destination: PDFHeadingDestination
        var page: PDFSyntax.Reference
    }
}
