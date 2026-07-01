struct PDFTaggedContentBuilder {
    private var elements: [PDFTaggedContent.Element] = [
        PDFTaggedContent.Element(
            id: 0,
            role: .document,
            parentID: nil,
            kids: [],
            attributes: PDFTaggedContent.Attributes(),
        ),
    ]
    private var elementStack: [Int] = [0]
    private var nextMCIDByPage: [Int: Int] = [:]
    private var marksByPage: [Int: [PDFTaggedContent.Mark]] = [:]

    mutating func beginElement(
        role: PDFTaggedContent.Role,
        attributes: PDFTaggedContent.Attributes = PDFTaggedContent.Attributes(),
    ) -> Int {
        let parentID = elementStack.last ?? 0
        let id = elements.count
        elements.append(
            PDFTaggedContent.Element(
                id: id,
                role: role,
                parentID: parentID,
                kids: [],
                attributes: attributes,
            ),
        )
        elements[parentID].kids.append(.element(id))
        elementStack.append(id)
        return id
    }

    mutating func endElement(_ id: Int) {
        guard elementStack.last == id, elementStack.count > 1 else {
            return
        }
        elementStack.removeLast()
    }

    mutating func markCurrentElement(onPage pageIndex: Int) -> (role: PDFTaggedContent.Role, mcid: Int)? {
        guard let elementID = elementStack.last, elementID != 0 else {
            return nil
        }

        let mcid = nextMCIDByPage[pageIndex] ?? 0
        nextMCIDByPage[pageIndex] = mcid + 1
        let mark = PDFTaggedContent.Mark(pageIndex: pageIndex, mcid: mcid, elementID: elementID)
        elements[elementID].kids.append(.mark(mark))
        marksByPage[pageIndex, default: []].append(mark)
        return (role: elements[elementID].role, mcid: mcid)
    }

    func build(language: String) -> PDFTaggedContent {
        PDFTaggedContent(
            language: language,
            elements: elements,
            marksByPage: marksByPage.mapValues { marks in
                marks.sorted { $0.mcid < $1.mcid }
            },
        )
    }
}
