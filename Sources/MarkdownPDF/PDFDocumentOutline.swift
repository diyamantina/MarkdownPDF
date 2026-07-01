struct PDFDocumentOutline {
    var destinations: [PDFNamedDestinations.ResolvedDestination]

    func outlineObjects(
        root: PDFSyntax.Reference,
        itemReferences: [PDFSyntax.Reference],
    ) -> [PDFOutlineObject] {
        var nodes = destinations.enumerated().map { index, resolved in
            OutlineNode(index: index, resolved: resolved)
        }
        var stack: [Int] = []

        for index in nodes.indices {
            while let last = stack.last,
                  nodes[last].resolved.destination.level >= nodes[index].resolved.destination.level
            {
                stack.removeLast()
            }
            if let parent = stack.last {
                nodes[index].parent = parent
                nodes[parent].children.append(index)
            }
            stack.append(index)
        }

        let rootChildren = nodes.filter { $0.parent == nil }.map(\.index)
        var objects = [
            PDFOutlineObject(
                reference: root,
                dictionary: rootDictionary(
                    children: rootChildren,
                    nodes: nodes,
                    itemReferences: itemReferences,
                ),
            ),
        ]

        for node in nodes {
            objects.append(
                PDFOutlineObject(
                    reference: itemReferences[node.index],
                    dictionary: itemDictionary(
                        node: node,
                        nodes: nodes,
                        root: root,
                        itemReferences: itemReferences,
                    ),
                ),
            )
        }

        return objects
    }

    private func rootDictionary(
        children: [Int],
        nodes: [OutlineNode],
        itemReferences: [PDFSyntax.Reference],
    ) -> PDFSyntax.Dictionary {
        var entries: [PDFSyntax.Dictionary.Entry] = [
            .init("Type", .pdfName("Outlines")),
            .init("Count", .int(nodes.count)),
        ]
        if let first = children.first, let last = children.last {
            entries.append(.init("First", .reference(itemReferences[first])))
            entries.append(.init("Last", .reference(itemReferences[last])))
        }
        return PDFSyntax.Dictionary(entries)
    }

    private func itemDictionary(
        node: OutlineNode,
        nodes: [OutlineNode],
        root: PDFSyntax.Reference,
        itemReferences: [PDFSyntax.Reference],
    ) -> PDFSyntax.Dictionary {
        let siblings = siblingIndexes(for: node, nodes: nodes)
        var entries: [PDFSyntax.Dictionary.Entry] = [
            .init("Title", .pdfString(node.resolved.destination.title)),
            .init("Parent", .reference(parentReference(for: node, root: root, itemReferences: itemReferences))),
            .init("Dest", .array(node.resolved.destination.destinationArray(page: node.resolved.page))),
        ]

        if let previous = previousSibling(of: node.index, in: siblings) {
            entries.append(.init("Prev", .reference(itemReferences[previous])))
        }
        if let next = nextSibling(of: node.index, in: siblings) {
            entries.append(.init("Next", .reference(itemReferences[next])))
        }
        if let first = node.children.first, let last = node.children.last {
            entries.append(.init("First", .reference(itemReferences[first])))
            entries.append(.init("Last", .reference(itemReferences[last])))
            entries.append(.init("Count", .int(descendantCount(for: node, nodes: nodes))))
        }

        return PDFSyntax.Dictionary(entries)
    }

    private func siblingIndexes(for node: OutlineNode, nodes: [OutlineNode]) -> [Int] {
        guard let parent = node.parent else {
            return nodes.filter { $0.parent == nil }.map(\.index)
        }

        return nodes[parent].children
    }

    private func parentReference(
        for node: OutlineNode,
        root: PDFSyntax.Reference,
        itemReferences: [PDFSyntax.Reference],
    ) -> PDFSyntax.Reference {
        node.parent.map { itemReferences[$0] } ?? root
    }

    private func previousSibling(of index: Int, in siblings: [Int]) -> Int? {
        guard let position = siblings.firstIndex(of: index), position > siblings.startIndex else {
            return nil
        }
        return siblings[siblings.index(before: position)]
    }

    private func nextSibling(of index: Int, in siblings: [Int]) -> Int? {
        guard let position = siblings.firstIndex(of: index) else {
            return nil
        }
        let nextPosition = siblings.index(after: position)
        return nextPosition < siblings.endIndex ? siblings[nextPosition] : nil
    }

    private func descendantCount(for node: OutlineNode, nodes: [OutlineNode]) -> Int {
        node.children.reduce(node.children.count) { count, child in
            count + descendantCount(for: nodes[child], nodes: nodes)
        }
    }

    private struct OutlineNode {
        var index: Int
        var resolved: PDFNamedDestinations.ResolvedDestination
        var parent: Int?
        var children: [Int] = []
    }
}
