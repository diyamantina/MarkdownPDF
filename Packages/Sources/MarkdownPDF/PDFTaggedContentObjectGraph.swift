struct PDFTaggedContentObjectGraph {
    var taggedContent: PDFTaggedContent
    var structTreeRoot: PDFSyntax.Reference
    var parentTree: PDFSyntax.Reference
    var elementReferences: [PDFSyntax.Reference]
    var pageReferences: [PDFSyntax.Reference]

    var structTreeRootDictionary: PDFSyntax.Dictionary {
        var entries: [PDFSyntax.Dictionary.Entry] = [
            .init("Type", .pdfName("StructTreeRoot")),
            .init("K", .reference(elementReferences[taggedContent.documentElementID])),
            .init("ParentTree", .reference(parentTree)),
            .init("ParentTreeNextKey", .int(nextParentTreeKey)),
        ]
        if taggedContent.usesCodeRole {
            entries.append(
                .init(
                    "RoleMap",
                    .pdfDictionary([
                        .init("Code", .pdfName("Span")),
                    ]),
                ),
            )
        }
        return PDFSyntax.Dictionary(entries)
    }

    var parentTreeDictionary: PDFSyntax.Dictionary {
        var values: [PDFSyntax.Value] = []
        for pageIndex in taggedContent.marksByPage.keys.sorted() {
            let marks = taggedContent.marksByPage[pageIndex] ?? []
            values.append(.int(pageIndex))
            values.append(.pdfArray(marks.map { .reference(elementReferences[$0.elementID]) }))
        }
        return PDFSyntax.Dictionary([
            .init("Nums", .pdfArray(values)),
        ])
    }

    func elementDictionary(for element: PDFTaggedContent.Element) -> PDFSyntax.Dictionary {
        var entries: [PDFSyntax.Dictionary.Entry] = [
            .init("Type", .pdfName("StructElem")),
            .init("S", .pdfName(element.role.rawValue)),
            .init("P", .reference(parentReference(for: element))),
        ]
        if let firstPageIndex = firstMarkedPageIndex(in: element) {
            entries.append(.init("Pg", .reference(pageReferences[firstPageIndex])))
        }
        if !element.kids.isEmpty {
            entries.append(.init("K", kidsValue(element.kids)))
        }
        entries.append(contentsOf: element.attributes.pdfEntries)
        return PDFSyntax.Dictionary(entries)
    }

    private var nextParentTreeKey: Int {
        (taggedContent.marksByPage.keys.max() ?? -1) + 1
    }

    private func parentReference(for element: PDFTaggedContent.Element) -> PDFSyntax.Reference {
        guard let parentID = element.parentID else {
            return structTreeRoot
        }
        return elementReferences[parentID]
    }

    private func firstMarkedPageIndex(in element: PDFTaggedContent.Element) -> Int? {
        for kid in element.kids {
            switch kid {
            case let .mark(mark):
                return mark.pageIndex
            case let .element(id):
                if let pageIndex = firstMarkedPageIndex(in: taggedContent.elements[id]) {
                    return pageIndex
                }
            }
        }
        return nil
    }

    private func kidsValue(_ kids: [PDFTaggedContent.Kid]) -> PDFSyntax.Value {
        if kids.count == 1, let kid = kids.first {
            return kidValue(kid)
        }
        return .pdfArray(kids.map(kidValue))
    }

    private func kidValue(_ kid: PDFTaggedContent.Kid) -> PDFSyntax.Value {
        switch kid {
        case let .element(id):
            .reference(elementReferences[id])
        case let .mark(mark):
            .pdfDictionary([
                .init("Type", .pdfName("MCR")),
                .init("Pg", .reference(pageReferences[mark.pageIndex])),
                .init("MCID", .int(mark.mcid)),
            ])
        }
    }
}
