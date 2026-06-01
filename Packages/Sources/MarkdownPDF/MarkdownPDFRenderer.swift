import Foundation

public struct MarkdownPDFRenderer: Sendable {
    public var options: PDFOptions

    public init(options: PDFOptions = PDFOptions()) {
        self.options = options
    }

    public func render(
        markdown: String,
        assetsBaseURL: URL? = nil,
    ) throws -> Data {
        let document = MarkdownParser().parse(markdown)
        if options.tableOfContents.isEnabled {
            return try renderWithTableOfContents(document, assetsBaseURL: assetsBaseURL)
        }

        return try renderDocument(document, assetsBaseURL: assetsBaseURL).pdfData()
    }

    private func renderDocument(
        _ document: MarkdownDocument,
        assetsBaseURL: URL?,
        tableOfContentsEntries: [TableOfContentsEntry]? = nil,
    ) throws -> Layout {
        var layout = Layout(options: options, assetsBaseURL: assetsBaseURL)
        try layout.render(document, tableOfContentsEntries: tableOfContentsEntries)
        return layout
    }

    private func renderWithTableOfContents(
        _ document: MarkdownDocument,
        assetsBaseURL: URL?,
    ) throws -> Data {
        let maximumPasses = 6
        var entries = try renderDocument(document, assetsBaseURL: assetsBaseURL)
            .tableOfContentsEntries(maximumDepth: options.tableOfContents.maximumDepth)
        guard !entries.isEmpty else {
            return try renderDocument(document, assetsBaseURL: assetsBaseURL).pdfData()
        }

        for _ in 0 ..< maximumPasses {
            let layout = try renderDocument(
                document,
                assetsBaseURL: assetsBaseURL,
                tableOfContentsEntries: entries,
            )
            let nextEntries = layout.tableOfContentsEntries(maximumDepth: options.tableOfContents.maximumDepth)
            if nextEntries == entries {
                return try layout.pdfData()
            }
            entries = nextEntries
        }

        throw MarkdownPDFError.tableOfContentsDidNotConverge(maxPasses: maximumPasses)
    }
}

private struct TableOfContentsEntry: Equatable {
    var destinationName: String
    var title: String
    var level: Int
    var pageNumber: Int
}

private struct TableColumnMetrics {
    var minimumWidth: Double
    var preferredWidth: Double
}

private struct TablePreparedRow {
    var cellLines: [[[PDFTextRun]]]
}

private struct Layout {
    var options: PDFOptions
    var assetsBaseURL: URL?
    var pages: [PDFPageCanvas] = [PDFPageCanvas()]
    var images: [PDFImage] = []
    var imageCache: [String: PDFImage] = [:]
    var headingNames = PDFHeadingDestinationName()
    var y: Double
    var listDepth = 0

    init(options: PDFOptions, assetsBaseURL: URL?) {
        self.options = options
        self.assetsBaseURL = assetsBaseURL
        y = options.pageSize.height - options.margins.top
    }

    mutating func render(
        _ document: MarkdownDocument,
        tableOfContentsEntries: [TableOfContentsEntry]? = nil,
    ) throws {
        let tableOfContentsInsertionIndex = tableOfContentsEntries.map {
            $0.isEmpty ? nil : self.tableOfContentsInsertionIndex(for: document)
        } ?? nil

        if tableOfContentsInsertionIndex == 0, let tableOfContentsEntries {
            renderTableOfContents(tableOfContentsEntries)
        }

        for (index, block) in document.blocks.enumerated() {
            keepHeadingWithNextBlock(block, isLast: index == document.blocks.count - 1)
            try render(block)
            if tableOfContentsInsertionIndex == index + 1, let tableOfContentsEntries {
                renderTableOfContents(tableOfContentsEntries)
            }
        }
    }

    func pdfData() throws -> Data {
        try PDFDocumentWriter(
            pageSize: options.pageSize,
            fontSet: options.fontSet,
            pages: pages,
            images: images,
            title: options.title,
        ).data()
    }

    func tableOfContentsEntries(maximumDepth: Int) -> [TableOfContentsEntry] {
        pages.enumerated().flatMap { pageIndex, page in
            page.headingDestinations.compactMap { destination in
                guard destination.level <= maximumDepth else {
                    return nil
                }

                return TableOfContentsEntry(
                    destinationName: destination.name,
                    title: destination.title,
                    level: destination.level,
                    pageNumber: pageIndex + 1,
                )
            }
        }
    }

    private mutating func render(_ block: MarkdownBlock) throws {
        switch block {
        case let .heading(level, content):
            let size = headingSize(level)
            let topSpacing = headingTopSpacing(level)
            ensureSpace(size * 1.8 + topSpacing)
            addHeadingTopSpacing(topSpacing)
            addHeadingDestination(level: level, content: content, y: y + size * 0.4)
            drawWrapped(
                flatten(content, font: .helveticaBold, size: size),
                x: options.margins.left,
                maxWidth: contentWidth,
                lineHeight: size * 1.25,
            )
            y -= size * 0.5
        case let .paragraph(content):
            if try renderStandaloneImage(content) {
                y -= 12
            } else {
                drawWrapped(
                    flatten(content, font: .helvetica, size: options.baseFontSize),
                    x: options.margins.left,
                    maxWidth: contentWidth,
                    lineHeight: bodyLineHeight,
                )
                y -= paragraphSpacing
            }
        case let .blockQuote(blocks):
            ensureSpace(24)
            let left = options.margins.left
            currentPage.drawLine(
                x1: left,
                y1: y + 6,
                x2: left,
                y2: max(options.margins.bottom, y - 42),
                width: 2,
                color: .gray,
            )
            let savedLeft = options.margins.left
            options.margins.left += 14
            for nested in blocks {
                try render(nested)
            }
            options.margins.left = savedLeft
        case let .unorderedList(items):
            try renderList(items: items, start: nil)
        case let .orderedList(start, items):
            try renderList(items: items, start: start)
        case let .codeBlock(info, code):
            if isMermaidCodeBlock(info) {
                renderMermaidBlock(code)
            } else {
                renderCodeBlock(code)
            }
        case let .table(table):
            renderTable(table)
        case .thematicBreak:
            ensureSpace(18)
            currentPage.drawLine(
                x1: options.margins.left,
                y1: y,
                x2: options.pageSize.width - options.margins.right,
                y2: y,
                width: 0.75,
                color: .gray,
            )
            y -= 18
        case let .html(html):
            drawWrapped(
                [PDFTextRun(text: html, font: .courier, size: options.baseFontSize * 0.9, color: .gray)],
                x: options.margins.left,
                maxWidth: contentWidth,
                lineHeight: options.baseFontSize * 1.35,
            )
            y -= 9
        }
    }

    private func tableOfContentsInsertionIndex(for document: MarkdownDocument) -> Int {
        guard let first = document.blocks.first,
              case .heading(level: 1, _) = first
        else {
            return 0
        }

        return 1
    }

    private mutating func renderTableOfContents(_ entries: [TableOfContentsEntry]) {
        let titleSize = options.baseFontSize * 1.55
        let entrySize = options.baseFontSize * 0.95
        let lineHeight = entrySize * 1.35
        let widestPageNumber = entries
            .map { PDFTextRun(text: "\($0.pageNumber)", font: .helvetica, size: entrySize).width(fontSet: options.fontSet) }
            .max() ?? 0
        let pageColumnWidth = max(28, widestPageNumber + 8)
        let title = options.tableOfContents.title.trimmingCharacters(in: .whitespacesAndNewlines)

        ensureSpace(titleSize * 2.2 + lineHeight)
        drawRuns(
            [PDFTextRun(text: title.isEmpty ? "Table of Contents" : title, font: .helveticaBold, size: titleSize)],
            x: options.margins.left,
            y: y,
        )
        y -= titleSize * 1.45

        for entry in entries {
            renderTableOfContentsEntry(
                entry,
                entrySize: entrySize,
                lineHeight: lineHeight,
                pageColumnWidth: pageColumnWidth,
            )
        }

        y -= options.baseFontSize * 0.9
    }

    private mutating func renderTableOfContentsEntry(
        _ entry: TableOfContentsEntry,
        entrySize: Double,
        lineHeight: Double,
        pageColumnWidth: Double,
    ) {
        let indent = Double(max(0, entry.level - 1)) * 14
        let x = options.margins.left + indent
        let pageText = "\(entry.pageNumber)"
        let pageRun = PDFTextRun(text: pageText, font: .helvetica, size: entrySize)
        let pageX = options.pageSize.width - options.margins.right - pageRun.width(fontSet: options.fontSet)
        let titleWidth = max(36, contentWidth - indent - pageColumnWidth - 10)
        let titleLines = wrappedLines(
            [
                PDFTextRun(
                    text: entry.title,
                    font: .helvetica,
                    size: entrySize,
                    color: .link,
                    linkDestination: "#\(entry.destinationName)",
                ),
            ],
            maxWidth: titleWidth,
        )

        ensureSpace(Double(titleLines.count) * lineHeight)
        for (index, line) in titleLines.enumerated() {
            drawRuns(line, x: x, y: y)
            if index == titleLines.count - 1 {
                let lineWidth = line.reduce(0) { $0 + $1.width(fontSet: options.fontSet) }
                drawTableOfContentsLeader(from: x + lineWidth + 5, to: pageX - 5, y: y + entrySize * 0.3)
                currentPage.drawTextRun(pageRun, x: pageX, y: y, fontSet: options.fontSet)
            }
            y -= lineHeight
        }
    }

    private mutating func drawTableOfContentsLeader(from startX: Double, to endX: Double, y: Double) {
        guard endX - startX > 12 else {
            return
        }

        currentPage.drawLine(
            x1: startX,
            y1: y,
            x2: endX,
            y2: y,
            width: 0.25,
            color: PDFColor(red: 0.72, green: 0.72, blue: 0.72),
        )
    }

    private mutating func renderList(
        items: [MarkdownBlock.ListItem],
        start: Int?,
    ) throws {
        var number = start ?? 0
        listDepth += 1
        defer { listDepth -= 1 }
        for item in items {
            ensureSpace(bodyLineHeight)
            if start != nil {
                currentPage.drawTextRun(
                    PDFTextRun(text: "\(number).", font: .helvetica, size: options.baseFontSize),
                    x: options.margins.left,
                    y: y,
                    fontSet: options.fontSet,
                )
                number += 1
            }
            let savedLeft = options.margins.left
            options.margins.left += 24
            for block in item.blocks {
                try render(block)
            }
            options.margins.left = savedLeft
        }
        y -= listTrailingSpacing
    }

    private mutating func renderCodeBlock(_ code: String) {
        let size = options.baseFontSize * 0.9
        let lineHeight = size * 1.4
        let verticalPadding = 12.0
        let lines = code
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                wrappedLines(
                    [PDFTextRun(text: String(line), font: .courier, size: size)],
                    maxWidth: contentWidth,
                )
            }
            .flatMap(\.self)
        let drawableLines = lines.isEmpty ? [[]] : lines
        var lineOffset = 0

        while lineOffset < drawableLines.count {
            ensureSpace(lineHeight + verticalPadding)
            let lineCount = min(
                drawableLines.count - lineOffset,
                codeBlockLineCapacity(lineHeight: lineHeight, verticalPadding: verticalPadding),
            )
            renderCodeBlockFragment(
                Array(drawableLines[lineOffset ..< lineOffset + lineCount]),
                size: size,
                lineHeight: lineHeight,
                verticalPadding: verticalPadding,
            )
            lineOffset += lineCount
            if lineOffset < drawableLines.count {
                startNewPage()
            }
        }
    }

    private func isMermaidCodeBlock(_ info: String?) -> Bool {
        guard let language = info?
            .split(whereSeparator: \.isWhitespace)
            .first?
            .lowercased()
        else {
            return false
        }

        return language == "mermaid"
    }

    private mutating func renderMermaidBlock(_ code: String) {
        switch MermaidDiagram.parse(code) {
        case let .diagram(diagram):
            switch mermaidRenderPlan(for: diagram) {
            case let .plan(plan):
                ensureSpace(plan.height + 12)
                drawMermaidPlan(plan)
                y -= plan.height + 12
            case let .fallback(reason):
                renderUnsupportedMermaid(reason: reason, code: code)
            }
        case let .unsupported(reason):
            renderUnsupportedMermaid(reason: reason, code: code)
        }
    }

    private mutating func renderUnsupportedMermaid(reason: String, code: String) {
        renderCodeBlock("Unsupported Mermaid diagram: \(reason)\n\(code)")
    }

    private func mermaidRenderPlan(for diagram: MermaidDiagram) -> MermaidRenderPlanResult {
        guard let layers = diagram.layers() else {
            return .fallback("flowchart cycles are not supported")
        }

        switch measureMermaidNodes(diagram.nodes) {
        case let .fallback(reason):
            return .fallback(reason)
        case let .measurements(measurements):
            if diagram.direction.isVertical {
                return verticalMermaidRenderPlan(layers: layers, measurements: measurements, edges: diagram.edges)
            } else {
                return horizontalMermaidRenderPlan(layers: layers, measurements: measurements, edges: diagram.edges)
            }
        }
    }

    private func measureMermaidNodes(_ nodes: [MermaidDiagram.Node]) -> MermaidMeasurementResult {
        let fontSize = options.baseFontSize * 0.88
        let lineHeight = fontSize * 1.18
        let horizontalPadding = 10.0
        let verticalPadding = 7.0
        let maxNodeWidth = max(48, min(180, contentWidth - 20))
        let minNodeWidth = min(96, maxNodeWidth)
        let labelWidthLimit = max(24, maxNodeWidth - horizontalPadding * 2)
        var measurements: [String: MermaidNodeMeasurement] = [:]

        for node in nodes {
            let run = PDFTextRun(text: node.label, font: .helvetica, size: fontSize)
            let labelLines = wrappedLines([run], maxWidth: labelWidthLimit)
            let lineWidths = labelLines.map { line in
                line.reduce(0) { $0 + $1.width(fontSet: options.fontSet) }
            }
            let widestLine = lineWidths.max() ?? 0
            guard widestLine <= labelWidthLimit + 0.1 else {
                return .fallback("node label `\(node.label)` is wider than the diagram node limit")
            }

            measurements[node.id] = MermaidNodeMeasurement(
                id: node.id,
                labelLines: labelLines,
                width: max(minNodeWidth, widestLine + horizontalPadding * 2),
                height: max(34, Double(labelLines.count) * lineHeight + verticalPadding * 2),
                fontSize: fontSize,
                lineHeight: lineHeight,
                verticalPadding: verticalPadding,
            )
        }

        return .measurements(measurements)
    }

    private func verticalMermaidRenderPlan(
        layers: [[MermaidDiagram.Node]],
        measurements: [String: MermaidNodeMeasurement],
        edges: [MermaidDiagram.Edge],
    ) -> MermaidRenderPlanResult {
        let outerPadding = 8.0
        let rowSpacing = 36.0
        let preferredColumnSpacing = 24.0
        let minimumColumnSpacing = 12.0
        var boxes: [MermaidNodeBox] = []
        var offset = outerPadding

        for layer in layers {
            let layerMeasurements = layer.compactMap { measurements[$0.id] }
            let rowHeight = layerMeasurements.map(\.height).max() ?? 0
            var spacing = layerMeasurements.count > 1 ? preferredColumnSpacing : 0
            var rowWidth = layerMeasurements.reduce(0) { $0 + $1.width } + Double(max(0, layerMeasurements.count - 1)) * spacing
            if rowWidth > contentWidth {
                spacing = layerMeasurements.count > 1 ? minimumColumnSpacing : 0
                rowWidth = layerMeasurements.reduce(0) { $0 + $1.width } + Double(max(0, layerMeasurements.count - 1)) * spacing
            }
            guard rowWidth <= contentWidth + 0.1 else {
                return .fallback("diagram row is wider than the content area")
            }

            var x = options.margins.left + (contentWidth - rowWidth) / 2
            for measurement in layerMeasurements {
                boxes.append(MermaidNodeBox(
                    measurement: measurement,
                    x: x,
                    topOffset: offset + (rowHeight - measurement.height) / 2,
                ))
                x += measurement.width + spacing
            }
            offset += rowHeight + rowSpacing
        }

        let height = max(outerPadding * 2, offset - rowSpacing + outerPadding)
        guard height <= contentHeight else {
            return .fallback("diagram is taller than one page")
        }
        if let reason = mermaidEdgeLabelFallbackReason(
            boxes: boxes,
            edges: edges,
            planHeight: height,
        ) {
            return .fallback(reason)
        }

        return .plan(MermaidRenderPlan(height: height, boxes: boxes, edges: edges))
    }

    private func horizontalMermaidRenderPlan(
        layers: [[MermaidDiagram.Node]],
        measurements: [String: MermaidNodeMeasurement],
        edges: [MermaidDiagram.Edge],
    ) -> MermaidRenderPlanResult {
        let outerPadding = 8.0
        let columnSpacing = 34.0
        let compactColumnSpacing = 18.0
        let nodeSpacing = 20.0
        let layerMeasurements = layers.map { layer in
            layer.compactMap { measurements[$0.id] }
        }
        let columnWidths = layerMeasurements.map { $0.map(\.width).max() ?? 0 }
        let columnHeights = layerMeasurements.map { column in
            column.reduce(0) { $0 + $1.height } + Double(max(0, column.count - 1)) * nodeSpacing
        }

        var spacing = columnSpacing
        var totalWidth = columnWidths.reduce(0, +) + Double(max(0, columnWidths.count - 1)) * spacing
        if totalWidth > contentWidth {
            spacing = compactColumnSpacing
            totalWidth = columnWidths.reduce(0, +) + Double(max(0, columnWidths.count - 1)) * spacing
        }
        guard totalWidth <= contentWidth + 0.1 else {
            return .fallback("diagram columns are wider than the content area")
        }

        let innerHeight = columnHeights.max() ?? 0
        let height = innerHeight + outerPadding * 2
        guard height <= contentHeight else {
            return .fallback("diagram is taller than one page")
        }

        var boxes: [MermaidNodeBox] = []
        var x = options.margins.left + (contentWidth - totalWidth) / 2
        for columnIndex in layerMeasurements.indices {
            var topOffset = outerPadding + (innerHeight - columnHeights[columnIndex]) / 2
            for measurement in layerMeasurements[columnIndex] {
                boxes.append(MermaidNodeBox(
                    measurement: measurement,
                    x: x + (columnWidths[columnIndex] - measurement.width) / 2,
                    topOffset: topOffset,
                ))
                topOffset += measurement.height + nodeSpacing
            }
            x += columnWidths[columnIndex] + spacing
        }

        if let reason = mermaidEdgeLabelFallbackReason(
            boxes: boxes,
            edges: edges,
            planHeight: height,
        ) {
            return .fallback(reason)
        }

        return .plan(MermaidRenderPlan(height: height, boxes: boxes, edges: edges))
    }

    private func mermaidEdgeLabelFallbackReason(
        boxes: [MermaidNodeBox],
        edges: [MermaidDiagram.Edge],
        planHeight: Double,
    ) -> String? {
        let contentFrame = MermaidFrame(
            left: options.margins.left,
            top: 0,
            width: contentWidth,
            height: planHeight,
        )
        let boxesByID = Dictionary(uniqueKeysWithValues: boxes.map { ($0.id, $0) })
        let nodeFrames = boxes.map { $0.frame(topY: 0).expanded(by: 2) }

        for edge in edges {
            guard let label = edge.label,
                  let source = boxesByID[edge.source],
                  let target = boxesByID[edge.target]
            else {
                continue
            }

            let sourceFrame = source.frame(topY: 0)
            let targetFrame = target.frame(topY: 0)
            let endpoints = mermaidEdgeEndpoints(source: sourceFrame, target: targetFrame)
            let labelFrame = mermaidEdgeLabelFrame(label, start: endpoints.start, end: endpoints.end)

            guard contentFrame.contains(labelFrame) else {
                return "edge label `\(label)` does not fit inside the diagram content area"
            }
            if nodeFrames.contains(where: { labelFrame.intersects($0) }) {
                return "edge label `\(label)` collides with a diagram node"
            }
        }

        return nil
    }

    private mutating func drawMermaidPlan(_ plan: MermaidRenderPlan) {
        let topY = y
        currentPage.drawRectangle(
            x: options.margins.left - 4,
            y: topY - plan.height,
            width: contentWidth + 8,
            height: plan.height,
            stroke: PDFColor(red: 0.72, green: 0.78, blue: 0.84),
            fill: PDFColor(red: 0.97, green: 0.98, blue: 0.99),
        )

        let boxesByID = Dictionary(uniqueKeysWithValues: plan.boxes.map { ($0.id, $0) })
        for edge in plan.edges {
            guard let source = boxesByID[edge.source],
                  let target = boxesByID[edge.target]
            else {
                continue
            }
            drawMermaidEdge(edge, source: source, target: target, topY: topY)
        }

        for box in plan.boxes {
            drawMermaidNode(box, topY: topY)
        }
    }

    private mutating func drawMermaidEdge(
        _ edge: MermaidDiagram.Edge,
        source: MermaidNodeBox,
        target: MermaidNodeBox,
        topY: Double,
    ) {
        let sourceFrame = source.frame(topY: topY)
        let targetFrame = target.frame(topY: topY)
        let endpoints = mermaidEdgeEndpoints(source: sourceFrame, target: targetFrame)

        drawArrow(from: endpoints.start, to: endpoints.end)
        if let label = edge.label {
            drawMermaidEdgeLabel(label, start: endpoints.start, end: endpoints.end)
        }
    }

    private func mermaidEdgeEndpoints(
        source: MermaidFrame,
        target: MermaidFrame,
    ) -> (start: MermaidPoint, end: MermaidPoint) {
        let horizontalDistance = abs(target.centerX - source.centerX)
        let verticalDistance = abs(target.centerY - source.centerY)

        if horizontalDistance > verticalDistance {
            if target.centerX >= source.centerX {
                return (
                    MermaidPoint(x: source.right, y: source.centerY),
                    MermaidPoint(x: target.left, y: target.centerY),
                )
            }
            return (
                MermaidPoint(x: source.left, y: source.centerY),
                MermaidPoint(x: target.right, y: target.centerY),
            )
        }

        if target.centerY <= source.centerY {
            return (
                MermaidPoint(x: source.centerX, y: source.bottom),
                MermaidPoint(x: target.centerX, y: target.top),
            )
        }
        return (
            MermaidPoint(x: source.centerX, y: source.top),
            MermaidPoint(x: target.centerX, y: target.bottom),
        )
    }

    private mutating func drawArrow(from start: MermaidPoint, to end: MermaidPoint) {
        currentPage.drawLine(
            x1: start.x,
            y1: start.y,
            x2: end.x,
            y2: end.y,
            width: 0.8,
            color: PDFColor(red: 0.25, green: 0.31, blue: 0.38),
        )

        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0.1 else {
            return
        }

        let angle = atan2(dy, dx)
        let arrowLength = 6.0
        let spread = 0.48
        let first = MermaidPoint(
            x: end.x - arrowLength * cos(angle - spread),
            y: end.y - arrowLength * sin(angle - spread),
        )
        let second = MermaidPoint(
            x: end.x - arrowLength * cos(angle + spread),
            y: end.y - arrowLength * sin(angle + spread),
        )

        currentPage.drawLine(x1: end.x, y1: end.y, x2: first.x, y2: first.y, width: 0.8, color: PDFColor(red: 0.25, green: 0.31, blue: 0.38))
        currentPage.drawLine(x1: end.x, y1: end.y, x2: second.x, y2: second.y, width: 0.8, color: PDFColor(red: 0.25, green: 0.31, blue: 0.38))
    }

    private mutating func drawMermaidEdgeLabel(
        _ label: String,
        start: MermaidPoint,
        end: MermaidPoint,
    ) {
        let run = mermaidEdgeLabelRun(label)
        let frame = mermaidEdgeLabelFrame(label, start: start, end: end)
        currentPage.drawRectangle(
            x: frame.left,
            y: frame.bottom,
            width: frame.width,
            height: frame.height,
            stroke: nil,
            fill: PDFColor(red: 0.97, green: 0.98, blue: 0.99),
        )
        currentPage.drawTextRun(run, x: frame.left + 3, y: frame.bottom + 3, fontSet: options.fontSet)
    }

    private func mermaidEdgeLabelFrame(
        _ label: String,
        start: MermaidPoint,
        end: MermaidPoint,
    ) -> MermaidFrame {
        let run = mermaidEdgeLabelRun(label)
        let width = run.width(fontSet: options.fontSet)
        let height = run.size + 4
        return MermaidFrame(
            left: (start.x + end.x) / 2 - width / 2 - 3,
            top: (start.y + end.y) / 2 + height / 2,
            width: width + 6,
            height: height,
        )
    }

    private func mermaidEdgeLabelRun(_ label: String) -> PDFTextRun {
        PDFTextRun(
            text: label,
            font: .helveticaOblique,
            size: options.baseFontSize * 0.72,
            color: .gray,
        )
    }

    private mutating func drawMermaidNode(_ box: MermaidNodeBox, topY: Double) {
        let frame = box.frame(topY: topY)
        currentPage.drawRectangle(
            x: frame.left,
            y: frame.bottom,
            width: box.width,
            height: box.height,
            stroke: PDFColor(red: 0.18, green: 0.31, blue: 0.48),
            fill: PDFColor(red: 0.90, green: 0.94, blue: 0.98),
        )

        var textY = frame.top - box.verticalPadding - box.fontSize
        for line in box.labelLines {
            let lineWidth = line.reduce(0) { $0 + $1.width(fontSet: options.fontSet) }
            drawRuns(line, x: frame.left + (box.width - lineWidth) / 2, y: textY)
            textY -= box.lineHeight
        }
    }

    private mutating func renderTable(_ table: MarkdownBlock.Table) {
        let cellPadding = 4.0
        let fontSize = options.baseFontSize * 0.9
        let lineHeight = fontSize * 1.35
        let columns = tableColumnCount(table)
        let columnWidths = measuredTableColumnWidths(
            table,
            columns: columns,
            cellPadding: cellPadding,
            fontSize: fontSize,
        )
        let header = preparedTableRow(
            cells: table.headers,
            columns: columns,
            columnWidths: columnWidths,
            cellPadding: cellPadding,
            fontSize: fontSize,
            header: true,
        )

        renderPreparedTableRow(
            header,
            alignments: table.alignments,
            columnWidths: columnWidths,
            cellPadding: cellPadding,
            fontSize: fontSize,
            lineHeight: lineHeight,
            header: true,
            repeatedHeader: nil,
        )

        for row in table.rows {
            let preparedRow = preparedTableRow(
                cells: row,
                columns: columns,
                columnWidths: columnWidths,
                cellPadding: cellPadding,
                fontSize: fontSize,
                header: false,
            )
            renderPreparedTableRow(
                preparedRow,
                alignments: table.alignments,
                columnWidths: columnWidths,
                cellPadding: cellPadding,
                fontSize: fontSize,
                lineHeight: lineHeight,
                header: false,
                repeatedHeader: header,
            )
        }

        y -= 12
    }

    private func tableColumnCount(_ table: MarkdownBlock.Table) -> Int {
        let counts = [table.headers.count, table.alignments.count] + table.rows.map(\.count)
        return max(1, counts.max() ?? 1)
    }

    private func measuredTableColumnWidths(
        _ table: MarkdownBlock.Table,
        columns: Int,
        cellPadding: Double,
        fontSize: Double,
    ) -> [Double] {
        let minimumColumnWidth = min(36, contentWidth / Double(columns))
        let maximumColumnWidth = columns == 1 ? contentWidth : contentWidth * 0.65
        let metrics = (0 ..< columns).map { column in
            tableColumnMetrics(
                table,
                column: column,
                columns: columns,
                minimumWidth: minimumColumnWidth,
                maximumWidth: maximumColumnWidth,
                cellPadding: cellPadding,
                fontSize: fontSize,
            )
        }
        let preferredWidths = metrics.map(\.preferredWidth)
        let minimumWidths = metrics.map(\.minimumWidth)
        let preferredTotal = preferredWidths.reduce(0, +)

        if preferredTotal <= contentWidth {
            let slack = contentWidth - preferredTotal
            return preferredWidths.map { $0 + slack / Double(columns) }
        }

        let minimumTotal = minimumWidths.reduce(0, +)
        guard minimumTotal < contentWidth else {
            return Array(repeating: contentWidth / Double(columns), count: columns)
        }

        let shrinkableTotal = zip(preferredWidths, minimumWidths)
            .map { $0 - $1 }
            .reduce(0, +)
        guard shrinkableTotal > 0 else {
            return Array(repeating: contentWidth / Double(columns), count: columns)
        }

        let overflow = preferredTotal - contentWidth
        return zip(preferredWidths, minimumWidths).map { preferred, minimum in
            let shrinkable = preferred - minimum
            return preferred - overflow * (shrinkable / shrinkableTotal)
        }
    }

    private func tableColumnMetrics(
        _ table: MarkdownBlock.Table,
        column: Int,
        columns: Int,
        minimumWidth: Double,
        maximumWidth: Double,
        cellPadding: Double,
        fontSize: Double,
    ) -> TableColumnMetrics {
        let headerRuns = tableRuns(
            table.headers,
            column: column,
            font: .helveticaBold,
            size: fontSize,
        )
        let bodyRuns = table.rows.map {
            tableRuns($0, column: column, font: .helvetica, size: fontSize)
        }
        let allRuns = [headerRuns] + bodyRuns
        let contentWidths = allRuns.map { $0.reduce(0) { $0 + $1.width(fontSet: options.fontSet) } }
        let tokenWidths = allRuns
            .flatMap(tokenize)
            .filter { $0.text != "\n" }
            .map { $0.width(fontSet: options.fontSet) }
        let preferredContentWidth = contentWidths.max() ?? 0
        let widestTokenWidth = tokenWidths.max() ?? 0
        let paddedPreferredWidth = preferredContentWidth + cellPadding * 2
        let paddedTokenWidth = widestTokenWidth + cellPadding * 2
        let preferredWidth = min(maximumWidth, max(minimumWidth, paddedPreferredWidth))
        let tokenFloor = min(maximumWidth, max(minimumWidth, paddedTokenWidth))
        let fairFloor = max(minimumWidth, min(tokenFloor, contentWidth / Double(columns)))

        return TableColumnMetrics(
            minimumWidth: fairFloor,
            preferredWidth: max(preferredWidth, fairFloor),
        )
    }

    private func tableRuns(
        _ cells: [[MarkdownInline]],
        column: Int,
        font: StandardFont,
        size: Double,
    ) -> [PDFTextRun] {
        guard column < cells.count else {
            return []
        }
        return flatten(cells[column], font: font, size: size)
    }

    private func preparedTableRow(
        cells: [[MarkdownInline]],
        columns: Int,
        columnWidths: [Double],
        cellPadding: Double,
        fontSize: Double,
        header: Bool,
    ) -> TablePreparedRow {
        let cellLines = (0 ..< columns).map { column in
            let cell = column < cells.count ? cells[column] : []
            let width = column < columnWidths.count ? columnWidths[column] : contentWidth / Double(columns)
            return wrappedLines(
                flatten(cell, font: header ? .helveticaBold : .helvetica, size: fontSize),
                maxWidth: max(1, width - cellPadding * 2),
            )
        }
        return TablePreparedRow(cellLines: cellLines)
    }

    private mutating func renderPreparedTableRow(
        _ row: TablePreparedRow,
        alignments: [MarkdownBlock.Alignment],
        columnWidths: [Double],
        cellPadding: Double,
        fontSize: Double,
        lineHeight: Double,
        header: Bool,
        repeatedHeader: TablePreparedRow?,
    ) {
        let cellLines = row.cellLines
        let maxLines = max(1, cellLines.map(\.count).max() ?? 1)
        var lineOffset = 0

        while lineOffset < maxLines {
            ensureTableRowFragmentSpace(
                lineHeight + cellPadding * 2,
                header: repeatedHeader,
                alignments: alignments,
                columnWidths: columnWidths,
                cellPadding: cellPadding,
                fontSize: fontSize,
                lineHeight: lineHeight,
            )
            let lineCount = min(
                maxLines - lineOffset,
                tableRowLineCapacity(lineHeight: lineHeight, cellPadding: cellPadding),
            )
            renderTableRowFragment(
                cellLines: cellLines,
                alignments: alignments,
                columnWidths: columnWidths,
                cellPadding: cellPadding,
                fontSize: fontSize,
                lineHeight: lineHeight,
                header: header,
                lineOffset: lineOffset,
                lineCount: lineCount,
            )
            lineOffset += lineCount
            if lineOffset < maxLines {
                startNewPage()
                if let repeatedHeader {
                    renderPreparedTableRow(
                        repeatedHeader,
                        alignments: alignments,
                        columnWidths: columnWidths,
                        cellPadding: cellPadding,
                        fontSize: fontSize,
                        lineHeight: lineHeight,
                        header: true,
                        repeatedHeader: nil,
                    )
                }
            }
        }
    }

    private mutating func ensureTableRowFragmentSpace(
        _ height: Double,
        header: TablePreparedRow?,
        alignments: [MarkdownBlock.Alignment],
        columnWidths: [Double],
        cellPadding: Double,
        fontSize: Double,
        lineHeight: Double,
    ) {
        guard y - height < options.margins.bottom else {
            return
        }

        startNewPage()
        guard let header else {
            return
        }

        renderPreparedTableRow(
            header,
            alignments: alignments,
            columnWidths: columnWidths,
            cellPadding: cellPadding,
            fontSize: fontSize,
            lineHeight: lineHeight,
            header: true,
            repeatedHeader: nil,
        )

        if y - height < options.margins.bottom {
            startNewPage()
        }
    }

    private mutating func renderStandaloneImage(_ content: [MarkdownInline]) throws -> Bool {
        guard content.count == 1,
              case let .image(alt, source, _) = content[0]
        else {
            return false
        }

        if source.hasPrefix("http://") || source.hasPrefix("https://") {
            drawWrapped(
                [PDFTextRun(text: "[Remote image: \(alt.isEmpty ? source : alt)]", font: .helveticaOblique, size: options.baseFontSize, color: .gray)],
                x: options.margins.left,
                maxWidth: contentWidth,
                lineHeight: options.baseFontSize * 1.35,
            )
            return true
        }

        let image = try loadImage(source: source)

        let maxWidth = contentWidth
        let maxHeight = max(1, min(contentHeight, options.pageSize.height * 0.45))
        let widthScale = maxWidth / Double(image.width)
        let heightScale = maxHeight / Double(image.height)
        let scale = min(1, widthScale, heightScale)
        let drawWidth = Double(image.width) * scale
        let drawHeight = Double(image.height) * scale

        ensureSpace(drawHeight)
        currentPage.drawImage(
            name: image.name,
            x: options.margins.left,
            y: y - drawHeight,
            width: drawWidth,
            height: drawHeight,
        )
        y -= drawHeight
        return true
    }

    private mutating func loadImage(source: String) throws -> PDFImage {
        if let image = imageCache[source] {
            return image
        }

        let name = "Im\(images.count + 1)"
        let image = try PDFImage.load(source: source, baseURL: assetsBaseURL, name: name)
        images.append(image)
        imageCache[source] = image
        return image
    }

    private func flatten(
        _ inlines: [MarkdownInline],
        font: StandardFont,
        size: Double,
        color: PDFColor = .black,
        underline: Bool = false,
        strikethrough: Bool = false,
        linkDestination: String? = nil,
    ) -> [PDFTextRun] {
        var runs: [PDFTextRun] = []

        for inline in inlines {
            switch inline {
            case let .text(text):
                runs.append(PDFTextRun(text: text, font: font, size: size, color: color, underline: underline, strikethrough: strikethrough, linkDestination: linkDestination))
            case .softBreak:
                runs.append(PDFTextRun(text: " ", font: font, size: size, color: color, underline: underline, strikethrough: strikethrough, linkDestination: linkDestination))
            case .lineBreak:
                runs.append(PDFTextRun(text: "\n", font: font, size: size, color: color, underline: underline, strikethrough: strikethrough, linkDestination: linkDestination))
            case let .code(text):
                runs.append(PDFTextRun(
                    text: text,
                    font: .courier,
                    size: size * 0.95,
                    color: color,
                    underline: underline,
                    strikethrough: strikethrough,
                    linkDestination: linkDestination,
                ))
            case let .emphasis(children):
                runs.append(contentsOf: flatten(
                    children,
                    font: .helveticaOblique,
                    size: size,
                    color: color,
                    underline: underline,
                    strikethrough: strikethrough,
                    linkDestination: linkDestination,
                ))
            case let .strong(children):
                runs.append(contentsOf: flatten(
                    children,
                    font: .helveticaBold,
                    size: size,
                    color: color,
                    underline: underline,
                    strikethrough: strikethrough,
                    linkDestination: linkDestination,
                ))
            case let .strikethrough(children):
                runs.append(contentsOf: flatten(children, font: font, size: size, color: color, underline: underline, strikethrough: true, linkDestination: linkDestination))
            case let .link(children, destination, _):
                runs.append(contentsOf: flatten(children, font: font, size: size, color: .link, underline: true, strikethrough: strikethrough, linkDestination: destination))
            case let .image(alt, source, _):
                let label = alt.isEmpty ? source : alt
                runs.append(PDFTextRun(
                    text: "[Image: \(label)]",
                    font: .helveticaOblique,
                    size: size,
                    color: .gray,
                    underline: underline,
                    strikethrough: strikethrough,
                    linkDestination: linkDestination,
                ))
            }
        }

        return runs
    }

    private mutating func drawWrapped(
        _ runs: [PDFTextRun],
        x: Double,
        maxWidth: Double,
        lineHeight: Double,
    ) {
        for line in wrappedLines(runs, maxWidth: maxWidth) {
            ensureSpace(lineHeight)
            drawRuns(line, x: x, y: y)
            y -= lineHeight
        }
    }

    private mutating func renderCodeBlockFragment(
        _ lines: [[PDFTextRun]],
        size: Double,
        lineHeight: Double,
        verticalPadding: Double,
    ) {
        let height = Double(lines.count) * lineHeight + verticalPadding
        currentPage.drawRectangle(
            x: options.margins.left - 4,
            y: y - height + 4,
            width: contentWidth + 8,
            height: height,
            stroke: nil,
            fill: PDFColor(red: 0.95, green: 0.95, blue: 0.95),
        )

        for line in lines {
            drawRuns(line, x: options.margins.left, y: y - size)
            y -= lineHeight
        }
        y -= verticalPadding
    }

    private func codeBlockLineCapacity(
        lineHeight: Double,
        verticalPadding: Double,
    ) -> Int {
        max(1, Int(floor((availablePageHeight - verticalPadding) / lineHeight)))
    }

    private mutating func renderTableRowFragment(
        cellLines: [[[PDFTextRun]]],
        alignments: [MarkdownBlock.Alignment],
        columnWidths: [Double],
        cellPadding: Double,
        fontSize: Double,
        lineHeight: Double,
        header: Bool,
        lineOffset: Int,
        lineCount: Int,
    ) {
        let rowHeight = Double(lineCount) * lineHeight + cellPadding * 2
        let rowBottom = y - rowHeight
        var x = options.margins.left

        for column in 0 ..< cellLines.count {
            let columnWidth = column < columnWidths.count ? columnWidths[column] : 0
            currentPage.drawRectangle(
                x: x,
                y: rowBottom,
                width: columnWidth,
                height: rowHeight,
                stroke: .gray,
                fill: header ? PDFColor(red: 0.93, green: 0.93, blue: 0.93) : nil,
            )

            let visibleLines = cellLines[column].dropFirst(lineOffset).prefix(lineCount)
            var lineY = y - cellPadding - fontSize
            for line in visibleLines {
                let width = line.reduce(0) { $0 + $1.width(fontSet: options.fontSet) }
                let alignment = column < alignments.count ? alignments[column] : .leading
                let textX = switch alignment {
                case .leading:
                    x + cellPadding
                case .center:
                    x + (columnWidth - width) / 2
                case .trailing:
                    x + columnWidth - cellPadding - width
                }
                drawRuns(line, x: textX, y: lineY)
                lineY -= lineHeight
            }
            x += columnWidth
        }
        y = rowBottom
    }

    private func tableRowLineCapacity(
        lineHeight: Double,
        cellPadding: Double,
    ) -> Int {
        max(1, Int(floor((availablePageHeight - cellPadding * 2) / lineHeight)))
    }

    private func wrappedLines(
        _ runs: [PDFTextRun],
        maxWidth: Double,
    ) -> [[PDFTextRun]] {
        let tokens = tokenize(runs)
        var lines: [[PDFTextRun]] = []
        var current: [PDFTextRun] = []
        var currentWidth = 0.0

        for token in tokens.flatMap({ splitOversizedToken($0, maxWidth: maxWidth) }) {
            if token.text == "\n" {
                lines.append(current)
                current = []
                currentWidth = 0
                continue
            }

            let width = token.width(fontSet: options.fontSet)
            if currentWidth + width > maxWidth, !current.isEmpty {
                lines.append(current)
                current = [token]
                currentWidth = width
            } else {
                current.append(token)
                currentWidth += width
            }
        }

        if !current.isEmpty || lines.isEmpty {
            lines.append(current)
        }

        return lines
    }

    private func splitOversizedToken(
        _ token: PDFTextRun,
        maxWidth: Double,
    ) -> [PDFTextRun] {
        guard token.text != "\n",
              maxWidth > 0,
              token.width(fontSet: options.fontSet) > maxWidth
        else {
            return [token]
        }

        var parts: [PDFTextRun] = []
        var buffer = ""
        for character in token.text {
            let candidate = buffer + String(character)
            if !buffer.isEmpty,
               token.withText(candidate).width(fontSet: options.fontSet) > maxWidth
            {
                parts.append(token.withText(buffer))
                buffer = String(character)
            } else {
                buffer = candidate
            }
        }

        if !buffer.isEmpty {
            parts.append(token.withText(buffer))
        }
        return parts
    }

    private func tokenize(_ runs: [PDFTextRun]) -> [PDFTextRun] {
        var tokens: [PDFTextRun] = []

        for run in runs {
            var buffer = ""
            for character in run.text {
                if character == "\n" {
                    if !buffer.isEmpty {
                        tokens.append(run.withText(buffer))
                        buffer = ""
                    }
                    tokens.append(run.withText("\n"))
                } else if character == " " || character == "\t" {
                    buffer.append(" ")
                    tokens.append(run.withText(buffer))
                    buffer = ""
                } else {
                    buffer.append(character)
                }
            }
            if !buffer.isEmpty {
                tokens.append(run.withText(buffer))
            }
        }

        return tokens
    }

    private func drawRuns(
        _ runs: [PDFTextRun],
        x: Double,
        y: Double,
    ) {
        var cursor = x
        for run in runs {
            currentPage.drawTextRun(run, x: cursor, y: y, fontSet: options.fontSet)
            cursor += run.width(fontSet: options.fontSet)
        }
    }

    private mutating func ensureSpace(_ height: Double) {
        if y - height < options.margins.bottom {
            startNewPage()
        }
    }

    private mutating func startNewPage() {
        pages.append(PDFPageCanvas())
        y = pageTopY
    }

    private mutating func keepHeadingWithNextBlock(
        _ block: MarkdownBlock,
        isLast: Bool,
    ) {
        guard !isLast,
              case let .heading(level, _) = block
        else {
            return
        }

        let topSpacing = y < pageTopY - 1 ? headingTopSpacing(level) : 0
        let height = topSpacing + headingSize(level) * 1.8 + headingKeepWithNextHeight(level)
        ensureSpace(height)
    }

    private mutating func addHeadingTopSpacing(_ spacing: Double) {
        guard y < pageTopY - 1 else {
            return
        }

        y -= spacing
    }

    private mutating func addHeadingDestination(
        level: Int,
        content: [MarkdownInline],
        y: Double,
    ) {
        let title = plainText(content).trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? "Heading" : title
        currentPage.addHeadingDestination(
            PDFHeadingDestination(
                name: headingNames.uniqueName(for: displayTitle),
                title: displayTitle,
                level: level,
                x: options.margins.left,
                y: min(options.pageSize.height, y),
            ),
        )
    }

    private func plainText(_ inlines: [MarkdownInline]) -> String {
        inlines.map(plainText).joined()
    }

    private func plainText(_ inline: MarkdownInline) -> String {
        switch inline {
        case let .text(text), let .code(text):
            text
        case .softBreak, .lineBreak:
            " "
        case let .emphasis(children), let .strong(children), let .strikethrough(children):
            plainText(children)
        case let .link(children, _, _):
            plainText(children)
        case let .image(alt, source, _):
            alt.isEmpty ? source : alt
        }
    }

    private func headingTopSpacing(_ level: Int) -> Double {
        switch level {
        case 1:
            options.baseFontSize * 1.4
        case 2:
            options.baseFontSize * 1.8
        case 3:
            options.baseFontSize * 1.45
        case 4:
            options.baseFontSize * 0.95
        default:
            options.baseFontSize * 0.5
        }
    }

    private func headingKeepWithNextHeight(_ level: Int) -> Double {
        switch level {
        case 1, 2:
            options.baseFontSize * 9.0
        case 3:
            options.baseFontSize * 4.5
        default:
            options.baseFontSize * 2.6
        }
    }

    private func headingSize(_ level: Int) -> Double {
        switch level {
        case 1:
            options.baseFontSize * 2.0
        case 2:
            options.baseFontSize * 1.55
        case 3:
            options.baseFontSize * 1.3
        default:
            options.baseFontSize * 1.1
        }
    }

    private var bodyLineHeight: Double {
        options.baseFontSize * (listDepth > 0 ? 1.15 : 1.24)
    }

    private var paragraphSpacing: Double {
        listDepth > 0 ? 2 : 6
    }

    private var listTrailingSpacing: Double {
        listDepth > 1 ? 1 : 3
    }

    private var contentWidth: Double {
        options.pageSize.width - options.margins.left - options.margins.right
    }

    private var contentHeight: Double {
        options.pageSize.height - options.margins.top - options.margins.bottom
    }

    private var availablePageHeight: Double {
        y - options.margins.bottom
    }

    private var pageTopY: Double {
        options.pageSize.height - options.margins.top
    }

    private var currentPage: PDFPageCanvas {
        pages[pages.count - 1]
    }

    private enum MermaidMeasurementResult {
        case measurements([String: MermaidNodeMeasurement])
        case fallback(String)
    }

    private enum MermaidRenderPlanResult {
        case plan(MermaidRenderPlan)
        case fallback(String)
    }

    private struct MermaidRenderPlan {
        var height: Double
        var boxes: [MermaidNodeBox]
        var edges: [MermaidDiagram.Edge]
    }

    private struct MermaidNodeMeasurement {
        var id: String
        var labelLines: [[PDFTextRun]]
        var width: Double
        var height: Double
        var fontSize: Double
        var lineHeight: Double
        var verticalPadding: Double
    }

    private struct MermaidNodeBox {
        var id: String
        var labelLines: [[PDFTextRun]]
        var x: Double
        var topOffset: Double
        var width: Double
        var height: Double
        var fontSize: Double
        var lineHeight: Double
        var verticalPadding: Double

        init(measurement: MermaidNodeMeasurement, x: Double, topOffset: Double) {
            id = measurement.id
            labelLines = measurement.labelLines
            self.x = x
            self.topOffset = topOffset
            width = measurement.width
            height = measurement.height
            fontSize = measurement.fontSize
            lineHeight = measurement.lineHeight
            verticalPadding = measurement.verticalPadding
        }

        func frame(topY: Double) -> MermaidFrame {
            let top = topY - topOffset
            return MermaidFrame(left: x, top: top, width: width, height: height)
        }
    }

    private struct MermaidFrame {
        var left: Double
        var top: Double
        var width: Double
        var height: Double

        var right: Double {
            left + width
        }

        var bottom: Double {
            top - height
        }

        var centerX: Double {
            left + width / 2
        }

        var centerY: Double {
            top - height / 2
        }

        func contains(_ child: MermaidFrame) -> Bool {
            child.left >= left
                && child.right <= right
                && child.top <= top
                && child.bottom >= bottom
        }

        func intersects(_ other: MermaidFrame) -> Bool {
            left < other.right
                && right > other.left
                && bottom < other.top
                && top > other.bottom
        }

        func expanded(by amount: Double) -> MermaidFrame {
            MermaidFrame(
                left: left - amount,
                top: top + amount,
                width: width + amount * 2,
                height: height + amount * 2,
            )
        }
    }

    private struct MermaidPoint {
        var x: Double
        var y: Double
    }
}

private extension PDFTextRun {
    func withText(_ newText: String) -> PDFTextRun {
        PDFTextRun(
            text: newText,
            font: font,
            size: size,
            color: color,
            underline: underline,
            strikethrough: strikethrough,
            linkDestination: linkDestination,
        )
    }
}
