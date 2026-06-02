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
        var layout = try Layout(options: options, assetsBaseURL: assetsBaseURL)
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

private struct BidiLine {
    var visualRuns: [BidiPositionedRun]
}

private struct BidiPositionedRun {
    var sourceTextRun: PDFTextRun
    var displayText: String
    var x: Double
    var sourceScalarOffset: Int
}

private struct Layout {
    var options: PDFOptions
    var assetsBaseURL: URL?
    var pages: [PDFPageCanvas] = [PDFPageCanvas()]
    var images: [PDFImage] = []
    var imageCache: [String: PDFImage] = [:]
    var headingNames = PDFHeadingDestinationName()
    var embeddedFonts: PDFEmbeddedFontCatalog
    var taggedContentBuilder: PDFTaggedContentBuilder?
    var markedContentDepth = 0
    var y: Double
    var listDepth = 0

    init(options: PDFOptions, assetsBaseURL: URL?) throws {
        self.options = options
        self.assetsBaseURL = assetsBaseURL
        embeddedFonts = try PDFEmbeddedFontCatalog(fonts: options.embeddedFonts)
        taggedContentBuilder = options.taggedPDF.isEnabled ? PDFTaggedContentBuilder() : nil
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
            try renderTableOfContents(tableOfContentsEntries)
        }

        for (index, block) in document.blocks.enumerated() {
            keepHeadingWithNextBlock(block, isLast: index == document.blocks.count - 1)
            try render(block)
            if tableOfContentsInsertionIndex == index + 1, let tableOfContentsEntries {
                try renderTableOfContents(tableOfContentsEntries)
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
            streamCompression: options.streamCompression,
            taggedContent: taggedContentBuilder?.build(language: options.taggedPDF.language),
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
            let element = beginStructureElement(.heading(level: level))
            defer { endStructureElement(element) }
            let size = headingSize(level)
            let topSpacing = headingTopSpacing(level)
            ensureSpace(size * 1.8 + topSpacing)
            addHeadingTopSpacing(topSpacing)
            addHeadingDestination(level: level, content: content, y: y + size * 0.4)
            try drawWrapped(
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
                let element = beginStructureElement(.paragraph)
                defer { endStructureElement(element) }
                try drawWrapped(
                    flatten(content, font: .helvetica, size: options.baseFontSize),
                    x: options.margins.left,
                    maxWidth: contentWidth,
                    lineHeight: bodyLineHeight,
                )
                y -= paragraphSpacing
            }
        case let .blockQuote(blocks):
            let element = beginStructureElement(.blockQuote)
            defer { endStructureElement(element) }
            ensureSpace(24)
            let savedLeft = options.margins.left
            options.margins.left += 14
            y -= blockQuoteTopSpacing
            for nested in blocks {
                try render(nested)
            }
            y -= blockQuoteBottomSpacing
            options.margins.left = savedLeft
        case let .unorderedList(items):
            try renderList(items: items, start: nil)
        case let .orderedList(start, items):
            try renderList(items: items, start: start)
        case let .codeBlock(info, code):
            if isMermaidCodeBlock(info) {
                try renderMermaidBlock(code)
            } else if isChartCodeBlock(info) {
                try renderChartFenceBlock(code)
            } else {
                try renderCodeBlock(code, info: info)
            }
        case let .table(table):
            try renderTable(table)
        case .thematicBreak:
            ensureSpace(18)
            let artifact = beginArtifactIfTagged()
            defer { endMarkedContentIfNeeded(artifact) }
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
            let element = beginStructureElement(.paragraph)
            defer { endStructureElement(element) }
            try drawWrapped(
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

    private mutating func renderTableOfContents(_ entries: [TableOfContentsEntry]) throws {
        let tocElement = beginStructureElement(.tableOfContents)
        defer { endStructureElement(tocElement) }

        let titleSize = options.baseFontSize * 1.55
        let entrySize = options.baseFontSize * 0.95
        let lineHeight = entrySize * 1.35
        let widestPageNumber = try entries
            .map { try textWidth(PDFTextRun(text: "\($0.pageNumber)", font: .helvetica, size: entrySize)) }
            .max() ?? 0
        let pageColumnWidth = max(28, widestPageNumber + 8)
        let title = options.tableOfContents.title.trimmingCharacters(in: .whitespacesAndNewlines)

        ensureSpace(titleSize * 2.2 + lineHeight)
        let titleElement = beginStructureElement(.paragraph)
        try drawRuns(
            [PDFTextRun(text: title.isEmpty ? "Table of Contents" : title, font: .helveticaBold, size: titleSize)],
            x: options.margins.left,
            y: y,
        )
        endStructureElement(titleElement)
        y -= titleSize * 1.45

        for entry in entries {
            try renderTableOfContentsEntry(
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
    ) throws {
        let itemElement = beginStructureElement(.tableOfContentsItem)
        defer { endStructureElement(itemElement) }

        let indent = Double(max(0, entry.level - 1)) * 14
        let x = options.margins.left + indent
        let pageText = "\(entry.pageNumber)"
        let pageRun = PDFTextRun(text: pageText, font: .helvetica, size: entrySize)
        let pageRunWidth = try textWidth(pageRun)
        let pageX = options.pageSize.width - options.margins.right - pageRunWidth
        let titleWidth = max(36, contentWidth - indent - pageColumnWidth - 10)
        let titleLines = try wrappedLines(
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
            try drawRuns(line, x: x, y: y)
            if index == titleLines.count - 1 {
                let lineWidth = try textWidth(line)
                drawTableOfContentsLeader(from: x + lineWidth + 5, to: pageX - 5, y: y + entrySize * 0.3)
                try currentPage.drawTextRun(
                    pageRun,
                    x: pageX,
                    y: y,
                    fontSet: options.fontSet,
                    embeddedFonts: embeddedFonts,
                )
            }
            y -= lineHeight
        }
    }

    private mutating func drawTableOfContentsLeader(from startX: Double, to endX: Double, y: Double) {
        guard endX - startX > 12 else {
            return
        }

        let artifact = beginArtifactIfTagged()
        defer { endMarkedContentIfNeeded(artifact) }
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
        let listElement = beginStructureElement(
            .list,
            attributes: PDFTaggedContent.Attributes(
                listNumbering: start == nil ? .unordered : .ordered,
            ),
        )
        defer { endStructureElement(listElement) }

        var number = start ?? 0
        listDepth += 1
        defer { listDepth -= 1 }
        for item in items {
            let itemElement = beginStructureElement(.listItem)
            ensureSpace(bodyLineHeight)
            if start != nil {
                let labelElement = beginStructureElement(.listLabel)
                try drawRuns(
                    [PDFTextRun(text: "\(number).", font: .helvetica, size: options.baseFontSize)],
                    x: options.margins.left,
                    y: y,
                    applyBidi: false,
                )
                endStructureElement(labelElement)
                number += 1
            }
            let savedLeft = options.margins.left
            options.margins.left += 24
            let bodyElement = beginStructureElement(.listBody)
            for block in item.blocks {
                try render(block)
            }
            endStructureElement(bodyElement)
            options.margins.left = savedLeft
            endStructureElement(itemElement)
        }
        y -= listTrailingSpacing
    }

    private mutating func renderCodeBlock(_ code: String, info: String? = nil) throws {
        let codeElement = beginStructureElement(.code)
        defer { endStructureElement(codeElement) }

        let size = options.baseFontSize * 0.9
        let lineHeight = size * 1.4
        let padding = codeBlockPadding
        let codeAreaWidth = max(1, contentWidth - padding * 2)
        var syntaxHighlighter = syntaxHighlighter(for: info)
        let sourceLines = code.split(separator: "\n", omittingEmptySubsequences: false)
        let lines = try sourceLines
            .map { line in
                let displayText = expandCodeTabs(String(line))
                return try wrappedLines(
                    codeLineRuns(
                        displayText,
                        size: size,
                        syntaxHighlighter: &syntaxHighlighter,
                    ),
                    maxWidth: codeAreaWidth,
                )
            }
            .flatMap(\.self)
        let drawableLines = lines.isEmpty ? [[]] : lines
        var lineOffset = 0

        while lineOffset < drawableLines.count {
            ensureSpace(lineHeight + padding * 2)
            let lineCount = min(
                drawableLines.count - lineOffset,
                codeBlockLineCapacity(lineHeight: lineHeight, padding: padding),
            )
            try renderCodeBlockFragment(
                Array(drawableLines[lineOffset ..< lineOffset + lineCount]),
                size: size,
                lineHeight: lineHeight,
                padding: padding,
            )
            lineOffset += lineCount
            if lineOffset < drawableLines.count {
                startNewPage()
            }
        }

        y -= codeBlockFollowingGap
    }

    private func syntaxHighlighter(for info: String?) -> SourceCodeSyntaxHighlighter? {
        guard options.codeSyntaxHighlighting.isEnabled,
              let language = SourceCodeLanguage(hint: info)
        else {
            return nil
        }

        return SourceCodeSyntaxHighlighter(language: language)
    }

    private func codeLineRuns(
        _ line: String,
        size: Double,
        syntaxHighlighter: inout SourceCodeSyntaxHighlighter?,
    ) -> [PDFTextRun] {
        guard var highlighter = syntaxHighlighter else {
            return [PDFTextRun(text: line, font: .courier, size: size)]
        }

        let tokens = highlighter.tokens(for: line)
        syntaxHighlighter = highlighter
        return tokens.map { token in
            PDFTextRun(
                text: token.text,
                font: .courier,
                size: size,
                color: color(for: token.kind),
            )
        }
    }

    private func color(for tokenKind: SourceCodeTokenKind) -> PDFColor {
        switch tokenKind {
        case .text, .identifier, .error:
            .black
        case .keyword:
            .sourceCodeKeyword
        case .string:
            .sourceCodeString
        case .number:
            .sourceCodeNumber
        case .comment:
            .sourceCodeComment
        case .operatorToken:
            .sourceCodeOperator
        case .punctuation:
            .sourceCodePunctuation
        }
    }

    private func isMermaidCodeBlock(_ info: String?) -> Bool {
        codeBlockLanguage(info) == "mermaid"
    }

    private func isChartCodeBlock(_ info: String?) -> Bool {
        codeBlockLanguage(info) == "chart"
    }

    private func codeBlockLanguage(_ info: String?) -> String? {
        guard let language = info?
            .split(whereSeparator: \.isWhitespace)
            .first?
            .lowercased()
        else {
            return nil
        }

        return language
    }

    private mutating func renderMermaidBlock(_ code: String) throws {
        if ChartBlock.isMermaidPieCandidate(code) {
            switch ChartBlock.parseMermaidPie(code) {
            case let .chart(chart):
                try renderChart(chart, sourceCode: code, fallbackPrefix: "Unsupported Mermaid chart")
            case let .unsupported(reason):
                try renderUnsupportedMermaid(reason: "unsupported Mermaid pie chart: \(reason)", code: code)
            }
            return
        }

        switch MermaidDiagram.parse(code) {
        case let .diagram(diagram):
            switch try mermaidRenderPlan(for: diagram) {
            case let .plan(plan):
                ensureSpace(plan.height + 12)
                let figureElement = beginStructureElement(
                    .figure,
                    attributes: PDFTaggedContent.Attributes(alternateDescription: "Mermaid diagram"),
                )
                let marked = beginMarkedContentForCurrentElement()
                try drawMermaidPlan(plan)
                endMarkedContentIfNeeded(marked)
                endStructureElement(figureElement)
                y -= plan.height + 12
            case let .fallback(reason):
                try renderUnsupportedMermaid(reason: reason, code: code)
            }
        case let .unsupported(reason):
            try renderUnsupportedMermaid(reason: reason, code: code)
        }
    }

    private mutating func renderUnsupportedMermaid(reason: String, code: String) throws {
        try renderCodeBlock("Unsupported Mermaid diagram: \(reason)\n\(code)")
    }

    private mutating func renderChartFenceBlock(_ code: String) throws {
        switch ChartBlock.parseChartFence(code) {
        case let .chart(chart):
            try renderChart(chart, sourceCode: code, fallbackPrefix: "Unsupported chart")
        case let .unsupported(reason):
            try renderCodeBlock("Unsupported chart: \(reason)\n\(code)")
        }
    }

    private mutating func renderChart(
        _ chart: ChartBlock,
        sourceCode: String,
        fallbackPrefix: String,
    ) throws {
        switch try chartRenderPlan(for: chart) {
        case let .plan(plan):
            ensureSpace(plan.height + 12)
            switch try chartRenderPlan(for: chart) {
            case let .plan(positionedPlan):
                let figureElement = beginStructureElement(
                    .figure,
                    attributes: PDFTaggedContent.Attributes(
                        alternateDescription: chartAlternateDescription(positionedPlan.chart),
                    ),
                )
                let marked = beginMarkedContentForCurrentElement()
                try drawChartPlan(positionedPlan)
                endMarkedContentIfNeeded(marked)
                endStructureElement(figureElement)
                y -= positionedPlan.height + 12
            case let .fallback(reason):
                try renderCodeBlock("\(fallbackPrefix): \(reason)\n\(sourceCode)")
            }
        case let .fallback(reason):
            try renderCodeBlock("\(fallbackPrefix): \(reason)\n\(sourceCode)")
        }
    }

    private func chartAlternateDescription(_ chart: ChartBlock) -> String {
        if let title = chart.title, !title.isEmpty {
            return title
        }
        return switch chart.kind {
        case .pie:
            "Pie chart"
        case .bar:
            "Bar chart"
        case .line:
            "Line chart"
        case .scatter:
            "Scatter chart"
        }
    }

    private func chartRenderPlan(for chart: ChartBlock) throws -> ChartRenderPlanResult {
        guard contentWidth >= 180 else {
            return .fallback("content area is too narrow for native chart rendering")
        }

        let height = min(contentHeight, max(190, min(260, contentWidth * 0.55)))
        guard height >= 170 else {
            return .fallback("content area is too short for native chart rendering")
        }
        guard chart.series.count <= chartPalette.count else {
            return .fallback("too many series for the portable chart palette")
        }
        if let title = chart.title,
           try textWidth(PDFTextRun(text: title, font: .helveticaBold, size: chartTitleSize)) > contentWidth - 16
        {
            return .fallback("chart title is wider than the content area")
        }
        for series in chart.series {
            guard !series.name.isEmpty else {
                return .fallback("series names must not be empty")
            }
            guard try textWidth(PDFTextRun(text: series.name, font: .helvetica, size: chartLabelSize)) <= 92 else {
                return .fallback("series label `\(series.name)` is too wide for the chart legend")
            }
        }
        for label in chart.categories {
            guard !label.isEmpty else {
                return .fallback("category labels must not be empty")
            }
            guard try textWidth(PDFTextRun(text: label, font: .helvetica, size: chartLabelSize)) <= 80 else {
                return .fallback("category label `\(label)` is too wide for the portable chart profile")
            }
        }

        switch chart.kind {
        case .pie:
            return try pieChartRenderPlan(for: chart, height: height)
        case .bar, .line, .scatter:
            return try cartesianChartRenderPlan(for: chart, height: height)
        }
    }

    private func pieChartRenderPlan(for chart: ChartBlock, height: Double) throws -> ChartRenderPlanResult {
        guard let series = chart.series.first, !series.points.isEmpty else {
            return .fallback("pie chart has no slices")
        }
        let titleHeight = chart.title == nil ? 8.0 : 26.0
        let legendWidth = try max(92, min(150, widestChartLabelWidth(chart.categories) + 24))
        let plotWidth = contentWidth - legendWidth - 18
        let radius = min(plotWidth / 2 - 8, (height - titleHeight - 18) / 2)
        guard radius >= 42 else {
            return .fallback("pie chart leaves too little room for slices and legend")
        }

        return .plan(ChartRenderPlan(
            chart: chart,
            height: height,
            plotFrame: nil,
            xTicks: [],
            yTicks: [],
            xDomain: (0, 0),
            yDomain: (0, 0),
            pieRadius: radius,
            legendWidth: legendWidth,
        ))
    }

    private func cartesianChartRenderPlan(for chart: ChartBlock, height: Double) throws -> ChartRenderPlanResult {
        let allPoints = chart.series.flatMap(\.points)
        guard !allPoints.isEmpty else {
            return .fallback("chart has no data points")
        }

        let yValues = allPoints.map(\.y) + (chart.kind == .bar ? [0] : [])
        let yTicks = niceChartTicks(min: yValues.min() ?? 0, max: yValues.max() ?? 1, targetCount: 5)
        guard let yFirst = yTicks.first, let yLast = yTicks.last, yLast > yFirst else {
            return .fallback("chart y axis could not be scaled")
        }
        let yLabelWidth = try max(34, yTicks.map { try chartTextWidth(formatChartNumber($0)) }.max() ?? 34)
        let leftAxisWidth = min(max(38, yLabelWidth + 10), 68)
        let titleHeight = chart.title == nil ? 8.0 : 26.0
        let legendHeight = 30.0
        let bottomAxisHeight = chart.xLabel == nil ? 34.0 : 48.0
        let plotFrame = ChartFrame(
            left: options.margins.left + leftAxisWidth,
            top: y - titleHeight - legendHeight,
            width: contentWidth - leftAxisWidth - 12,
            height: height - titleHeight - legendHeight - bottomAxisHeight,
        )
        guard plotFrame.width >= 96, plotFrame.height >= 72 else {
            return .fallback("chart plot area is too small")
        }

        let xTicks: [Double]
        let xDomain: (min: Double, max: Double)
        switch chart.kind {
        case .bar:
            guard !chart.categories.isEmpty else {
                return .fallback("bar charts require categories")
            }
            let bandWidth = plotFrame.width / Double(chart.categories.count)
            for category in chart.categories {
                if try chartTextWidth(category) > bandWidth * 0.92 {
                    return .fallback("category label `\(category)` would overlap adjacent labels")
                }
            }
            xTicks = chart.series[0].points.map(\.x)
            xDomain = (0, Double(max(0, chart.categories.count - 1)))
        case .line:
            let values = allPoints.map(\.x)
            xDomain = expandedDomain(min: values.min() ?? 0, max: values.max() ?? 1)
            xTicks = chart.categories.isEmpty ? niceChartTicks(min: xDomain.min, max: xDomain.max, targetCount: 5) : chart.series[0].points.map(\.x)
            if !chart.categories.isEmpty {
                let bandWidth = plotFrame.width / Double(chart.categories.count)
                for category in chart.categories where try chartTextWidth(category) > bandWidth * 0.92 {
                    return .fallback("category label `\(category)` would overlap adjacent labels")
                }
            }
        case .scatter:
            let values = allPoints.map(\.x)
            let domain = expandedDomain(min: values.min() ?? 0, max: values.max() ?? 1)
            xTicks = niceChartTicks(min: domain.min, max: domain.max, targetCount: 5)
            xDomain = (xTicks.first ?? domain.min, xTicks.last ?? domain.max)
            if let reason = try chartTickOverlapReason(ticks: xTicks, domain: xDomain, plotFrame: plotFrame) {
                return .fallback(reason)
            }
        case .pie:
            xTicks = []
            xDomain = (0, 0)
        }

        return .plan(ChartRenderPlan(
            chart: chart,
            height: height,
            plotFrame: plotFrame,
            xTicks: xTicks,
            yTicks: yTicks,
            xDomain: xDomain,
            yDomain: (yFirst, yLast),
            pieRadius: nil,
            legendWidth: nil,
        ))
    }

    private func chartTickOverlapReason(
        ticks: [Double],
        domain: (min: Double, max: Double),
        plotFrame: ChartFrame,
    ) throws -> String? {
        guard ticks.count > 1, domain.max > domain.min else {
            return nil
        }
        let positions = ticks.map { plotFrame.left + ($0 - domain.min) / (domain.max - domain.min) * plotFrame.width }
        let widths = try ticks.map { try chartTextWidth(formatChartNumber($0)) }
        for index in 1 ..< ticks.count {
            let previousRight = positions[index - 1] + widths[index - 1] / 2
            let currentLeft = positions[index] - widths[index] / 2
            if currentLeft < previousRight + 4 {
                return "x axis tick labels would overlap"
            }
        }
        return nil
    }

    private mutating func drawChartPlan(_ plan: ChartRenderPlan) throws {
        let topY = y
        currentPage.drawRectangle(
            x: options.margins.left - 4,
            y: topY - plan.height,
            width: contentWidth + 8,
            height: plan.height,
            stroke: PDFColor(red: 0.72, green: 0.76, blue: 0.80),
            fill: PDFColor(red: 0.98, green: 0.985, blue: 0.99),
        )

        if let title = plan.chart.title {
            try drawChartText(
                title,
                x: options.margins.left + contentWidth / 2,
                y: topY - 17,
                font: .helveticaBold,
                size: chartTitleSize,
                alignment: .center,
            )
        }

        switch plan.chart.kind {
        case .pie:
            try drawPieChart(plan, topY: topY)
        case .bar:
            try drawBarChart(plan, topY: topY)
        case .line:
            try drawLineChart(plan, topY: topY)
        case .scatter:
            try drawScatterChart(plan, topY: topY)
        }
    }

    private mutating func drawPieChart(_ plan: ChartRenderPlan, topY: Double) throws {
        guard let radius = plan.pieRadius,
              let legendWidth = plan.legendWidth,
              let series = plan.chart.series.first
        else {
            return
        }

        let titleHeight = plan.chart.title == nil ? 8.0 : 26.0
        let centerX = options.margins.left + radius + 14
        let centerY = topY - titleHeight - (plan.height - titleHeight) / 2
        let total = series.points.reduce(0) { $0 + $1.y }
        var angle = Double.pi / 2

        for (index, point) in series.points.enumerated() {
            let sweep = -Double.pi * 2 * point.y / total
            let nextAngle = angle + sweep
            currentPage.drawPieSlice(
                centerX: centerX,
                centerY: centerY,
                radius: radius,
                startAngle: angle,
                endAngle: nextAngle,
                fill: chartPalette[index % chartPalette.count],
            )
            angle = nextAngle
        }

        let legendX = options.margins.left + contentWidth - legendWidth + 4
        var legendY = topY - titleHeight - 16
        for (index, point) in series.points.enumerated() {
            let color = chartPalette[index % chartPalette.count]
            currentPage.drawRectangle(x: legendX, y: legendY - 8, width: 9, height: 9, stroke: nil, fill: color)
            try drawChartText(
                "\(point.label ?? "") \(formatChartNumber(point.y))",
                x: legendX + 14,
                y: legendY - 7,
                size: chartLabelSize,
            )
            legendY -= 15
        }
    }

    private mutating func drawBarChart(_ plan: ChartRenderPlan, topY: Double) throws {
        guard let plotFrame = plan.plotFrame else {
            return
        }
        try drawCartesianBase(plan, plotFrame: plotFrame, topY: topY)

        let baselineY = chartY(0, domain: plan.yDomain, frame: plotFrame)
        let bandWidth = plotFrame.width / Double(plan.chart.categories.count)
        let groupWidth = bandWidth * 0.68
        let barWidth = max(2, groupWidth / Double(plan.chart.series.count))

        for (seriesIndex, series) in plan.chart.series.enumerated() {
            let color = chartPalette[seriesIndex % chartPalette.count]
            for (pointIndex, point) in series.points.enumerated() {
                let x = plotFrame.left
                    + Double(pointIndex) * bandWidth
                    + (bandWidth - groupWidth) / 2
                    + Double(seriesIndex) * barWidth
                let valueY = chartY(point.y, domain: plan.yDomain, frame: plotFrame)
                let y = min(baselineY, valueY)
                currentPage.drawRectangle(
                    x: x,
                    y: y,
                    width: max(1.5, barWidth - 1),
                    height: max(0.8, abs(valueY - baselineY)),
                    stroke: nil,
                    fill: color,
                )
            }
        }

        try drawCategoricalXAxis(categories: plan.chart.categories, plotFrame: plotFrame)
        try drawChartLegend(plan.chart.series.map(\.name), topY: topY)
    }

    private mutating func drawLineChart(_ plan: ChartRenderPlan, topY: Double) throws {
        guard let plotFrame = plan.plotFrame else {
            return
        }
        try drawCartesianBase(plan, plotFrame: plotFrame, topY: topY)

        for (seriesIndex, series) in plan.chart.series.enumerated() {
            let color = chartPalette[seriesIndex % chartPalette.count]
            let points = series.points.map {
                PDFPageCanvas.Point(
                    x: chartX($0.x, domain: plan.xDomain, frame: plotFrame),
                    y: chartY($0.y, domain: plan.yDomain, frame: plotFrame),
                )
            }
            currentPage.drawPolyline(points: points, width: 1.2, color: color)
            for point in points {
                currentPage.drawCircle(x: point.x, y: point.y, radius: 2.5, stroke: .white, fill: color)
            }
        }

        if plan.chart.categories.isEmpty {
            try drawNumericXAxis(ticks: plan.xTicks, domain: plan.xDomain, plotFrame: plotFrame)
        } else {
            try drawCategoricalXAxis(categories: plan.chart.categories, plotFrame: plotFrame)
        }
        try drawChartLegend(plan.chart.series.map(\.name), topY: topY)
    }

    private mutating func drawScatterChart(_ plan: ChartRenderPlan, topY: Double) throws {
        guard let plotFrame = plan.plotFrame else {
            return
        }
        try drawCartesianBase(plan, plotFrame: plotFrame, topY: topY)

        for (seriesIndex, series) in plan.chart.series.enumerated() {
            let color = chartPalette[seriesIndex % chartPalette.count]
            for point in series.points {
                let marker = PDFPageCanvas.Point(
                    x: chartX(point.x, domain: plan.xDomain, frame: plotFrame),
                    y: chartY(point.y, domain: plan.yDomain, frame: plotFrame),
                )
                if seriesIndex % 3 == 2 {
                    currentPage.drawPolygon(
                        points: [
                            PDFPageCanvas.Point(x: marker.x, y: marker.y + 3.2),
                            PDFPageCanvas.Point(x: marker.x - 3.2, y: marker.y - 2.8),
                            PDFPageCanvas.Point(x: marker.x + 3.2, y: marker.y - 2.8),
                        ],
                        stroke: .white,
                        fill: color,
                    )
                } else if seriesIndex % 3 == 1 {
                    currentPage.drawRectangle(
                        x: marker.x - 2.8,
                        y: marker.y - 2.8,
                        width: 5.6,
                        height: 5.6,
                        stroke: .white,
                        fill: color,
                    )
                } else {
                    currentPage.drawCircle(x: marker.x, y: marker.y, radius: 3, stroke: .white, fill: color)
                }
            }
        }

        try drawNumericXAxis(ticks: plan.xTicks, domain: plan.xDomain, plotFrame: plotFrame)
        try drawChartLegend(plan.chart.series.map(\.name), topY: topY)
    }

    private mutating func drawCartesianBase(
        _ plan: ChartRenderPlan,
        plotFrame: ChartFrame,
        topY _: Double,
    ) throws {
        for tick in plan.yTicks {
            let tickY = chartY(tick, domain: plan.yDomain, frame: plotFrame)
            currentPage.drawLine(
                x1: plotFrame.left,
                y1: tickY,
                x2: plotFrame.right,
                y2: tickY,
                width: 0.25,
                color: PDFColor(red: 0.84, green: 0.86, blue: 0.88),
            )
            try drawChartText(
                formatChartNumber(tick),
                x: plotFrame.left - 6,
                y: tickY - chartLabelSize * 0.35,
                size: chartLabelSize,
                color: .gray,
                alignment: .right,
            )
        }

        currentPage.drawLine(x1: plotFrame.left, y1: plotFrame.bottom, x2: plotFrame.left, y2: plotFrame.top, width: 0.65)
        currentPage.drawLine(x1: plotFrame.left, y1: plotFrame.bottom, x2: plotFrame.right, y2: plotFrame.bottom, width: 0.65)

        if let yLabel = plan.chart.yLabel {
            try drawChartText(
                yLabel,
                x: plotFrame.left,
                y: plotFrame.top - chartLabelSize - 5,
                size: chartLabelSize,
                color: .gray,
            )
        }
        if let xLabel = plan.chart.xLabel {
            try drawChartText(
                xLabel,
                x: plotFrame.left + plotFrame.width / 2,
                y: plotFrame.bottom - 36,
                size: chartLabelSize,
                color: .gray,
                alignment: .center,
            )
        }
    }

    private mutating func drawCategoricalXAxis(categories: [String], plotFrame: ChartFrame) throws {
        let bandWidth = plotFrame.width / Double(categories.count)
        for (index, category) in categories.enumerated() {
            try drawChartText(
                category,
                x: plotFrame.left + Double(index) * bandWidth + bandWidth / 2,
                y: plotFrame.bottom - 13,
                size: chartLabelSize,
                color: .gray,
                alignment: .center,
            )
        }
    }

    private mutating func drawNumericXAxis(
        ticks: [Double],
        domain: (min: Double, max: Double),
        plotFrame: ChartFrame,
    ) throws {
        for tick in ticks {
            let tickX = chartX(tick, domain: domain, frame: plotFrame)
            currentPage.drawLine(
                x1: tickX,
                y1: plotFrame.bottom,
                x2: tickX,
                y2: plotFrame.top,
                width: 0.2,
                color: PDFColor(red: 0.88, green: 0.89, blue: 0.91),
            )
            try drawChartText(
                formatChartNumber(tick),
                x: tickX,
                y: plotFrame.bottom - 13,
                size: chartLabelSize,
                color: .gray,
                alignment: .center,
            )
        }
    }

    private mutating func drawChartLegend(_ labels: [String], topY: Double) throws {
        guard !labels.isEmpty else {
            return
        }

        let y = topY - (labels.count > 1 ? 39 : 33)
        let textX = options.margins.left + 18
        let spacer = "   "
        let spacerWidth = try chartTextWidth(spacer)
        var textCursor = textX
        var legendText = ""

        for (index, label) in labels.enumerated() {
            let color = chartPalette[index % chartPalette.count]
            currentPage.drawRectangle(x: textCursor - 14, y: y - 7, width: 10, height: 8, stroke: nil, fill: color)
            let labelWidth = try chartTextWidth(label)
            textCursor += labelWidth
            legendText += label
            if index < labels.count - 1 {
                textCursor += spacerWidth
                legendText += spacer
            }
        }
        try drawChartText(legendText, x: textX, y: y - 6, size: chartLabelSize)
    }

    private mutating func drawChartText(
        _ text: String,
        x: Double,
        y: Double,
        font: StandardFont = .helvetica,
        size: Double? = nil,
        color: PDFColor = .black,
        alignment: ChartTextAlignment = .left,
    ) throws {
        let run = PDFTextRun(text: text, font: font, size: size ?? chartLabelSize, color: color)
        let width = try textWidth(run)
        let drawX = switch alignment {
        case .left:
            x
        case .center:
            x - width / 2
        case .right:
            x - width
        }
        try currentPage.drawTextRun(run, x: drawX, y: y, fontSet: options.fontSet, embeddedFonts: embeddedFonts)
    }

    private func chartX(_ value: Double, domain: (min: Double, max: Double), frame: ChartFrame) -> Double {
        guard domain.max > domain.min else {
            return frame.left
        }
        return frame.left + (value - domain.min) / (domain.max - domain.min) * frame.width
    }

    private func chartY(_ value: Double, domain: (min: Double, max: Double), frame: ChartFrame) -> Double {
        guard domain.max > domain.min else {
            return frame.bottom
        }
        return frame.bottom + (value - domain.min) / (domain.max - domain.min) * frame.height
    }

    private func niceChartTicks(min rawMin: Double, max rawMax: Double, targetCount: Int) -> [Double] {
        let domain = expandedDomain(min: rawMin, max: rawMax)
        let span = niceChartNumber(domain.max - domain.min, round: false)
        let step = niceChartNumber(span / Double(max(1, targetCount - 1)), round: true)
        let graphMin = floor(domain.min / step) * step
        let graphMax = ceil(domain.max / step) * step
        var ticks: [Double] = []
        var value = graphMin
        while value <= graphMax + step * 0.5, ticks.count < 20 {
            ticks.append(value)
            value += step
        }
        return ticks
    }

    private func niceChartNumber(_ value: Double, round: Bool) -> Double {
        guard value > 0 else {
            return 1
        }
        let exponent = floor(log10(value))
        let fraction = value / pow(10, exponent)
        let niceFraction: Double = if round {
            if fraction < 1.5 {
                1
            } else if fraction < 3 {
                2
            } else if fraction < 7 {
                5
            } else {
                10
            }
        } else if fraction <= 1 {
            1
        } else if fraction <= 2 {
            2
        } else if fraction <= 5 {
            5
        } else {
            10
        }
        return niceFraction * pow(10, exponent)
    }

    private func expandedDomain(min rawMin: Double, max rawMax: Double) -> (min: Double, max: Double) {
        if rawMax > rawMin {
            return (rawMin, rawMax)
        }
        let padding = max(1, abs(rawMin) * 0.1)
        return (rawMin - padding, rawMax + padding)
    }

    private func formatChartNumber(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0001 {
            return "\(Int(value.rounded()))"
        }
        let absValue = abs(value)
        if absValue >= 10 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
    }

    private func chartTextWidth(_ text: String) throws -> Double {
        try textWidth(PDFTextRun(text: text, font: .helvetica, size: chartLabelSize))
    }

    private func widestChartLabelWidth(_ labels: [String]) throws -> Double {
        try labels.map { try chartTextWidth($0) }.max() ?? 0
    }

    private func mermaidRenderPlan(for diagram: MermaidDiagram) throws -> MermaidRenderPlanResult {
        guard let layers = diagram.layers() else {
            return .fallback("flowchart cycles are not supported")
        }

        switch try measureMermaidNodes(diagram.nodes) {
        case let .fallback(reason):
            return .fallback(reason)
        case let .measurements(measurements):
            if diagram.direction.isVertical {
                return try verticalMermaidRenderPlan(layers: layers, measurements: measurements, edges: diagram.edges)
            } else {
                return try horizontalMermaidRenderPlan(layers: layers, measurements: measurements, edges: diagram.edges)
            }
        }
    }

    private func measureMermaidNodes(_ nodes: [MermaidDiagram.Node]) throws -> MermaidMeasurementResult {
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
            let labelLines = try wrappedLines([run], maxWidth: labelWidthLimit)
            let lineWidths = try labelLines.map { line in
                try textWidth(line)
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
    ) throws -> MermaidRenderPlanResult {
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
        if let reason = try mermaidEdgeLabelFallbackReason(
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
    ) throws -> MermaidRenderPlanResult {
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

        if let reason = try mermaidEdgeLabelFallbackReason(
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
    ) throws -> String? {
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
            let labelFrame = try mermaidEdgeLabelFrame(label, start: endpoints.start, end: endpoints.end)

            guard contentFrame.contains(labelFrame) else {
                return "edge label `\(label)` does not fit inside the diagram content area"
            }
            if nodeFrames.contains(where: { labelFrame.intersects($0) }) {
                return "edge label `\(label)` collides with a diagram node"
            }
        }

        return nil
    }

    private mutating func drawMermaidPlan(_ plan: MermaidRenderPlan) throws {
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
            try drawMermaidEdge(edge, source: source, target: target, topY: topY)
        }

        for box in plan.boxes {
            try drawMermaidNode(box, topY: topY)
        }
    }

    private mutating func drawMermaidEdge(
        _ edge: MermaidDiagram.Edge,
        source: MermaidNodeBox,
        target: MermaidNodeBox,
        topY: Double,
    ) throws {
        let sourceFrame = source.frame(topY: topY)
        let targetFrame = target.frame(topY: topY)
        let endpoints = mermaidEdgeEndpoints(source: sourceFrame, target: targetFrame)

        drawArrow(from: endpoints.start, to: endpoints.end)
        if let label = edge.label {
            try drawMermaidEdgeLabel(label, start: endpoints.start, end: endpoints.end)
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
    ) throws {
        let run = mermaidEdgeLabelRun(label)
        let frame = try mermaidEdgeLabelFrame(label, start: start, end: end)
        currentPage.drawRectangle(
            x: frame.left,
            y: frame.bottom,
            width: frame.width,
            height: frame.height,
            stroke: nil,
            fill: PDFColor(red: 0.97, green: 0.98, blue: 0.99),
        )
        try currentPage.drawTextRun(
            run,
            x: frame.left + 3,
            y: frame.bottom + 3,
            fontSet: options.fontSet,
            embeddedFonts: embeddedFonts,
        )
    }

    private func mermaidEdgeLabelFrame(
        _ label: String,
        start: MermaidPoint,
        end: MermaidPoint,
    ) throws -> MermaidFrame {
        let run = mermaidEdgeLabelRun(label)
        let width = try textWidth(run)
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

    private mutating func drawMermaidNode(_ box: MermaidNodeBox, topY: Double) throws {
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
            let lineWidth = try textWidth(line)
            try drawRuns(line, x: frame.left + (box.width - lineWidth) / 2, y: textY)
            textY -= box.lineHeight
        }
    }

    private mutating func renderTable(_ table: MarkdownBlock.Table) throws {
        let tableElement = beginStructureElement(.table)
        defer { endStructureElement(tableElement) }

        let cellPadding = 4.0
        let fontSize = options.baseFontSize * 0.9
        let lineHeight = fontSize * 1.35
        let columns = tableColumnCount(table)
        let columnWidths = try measuredTableColumnWidths(
            table,
            columns: columns,
            cellPadding: cellPadding,
            fontSize: fontSize,
        )
        let header = try preparedTableRow(
            cells: table.headers,
            columns: columns,
            columnWidths: columnWidths,
            cellPadding: cellPadding,
            fontSize: fontSize,
            header: true,
        )

        try renderPreparedTableRow(
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
            let preparedRow = try preparedTableRow(
                cells: row,
                columns: columns,
                columnWidths: columnWidths,
                cellPadding: cellPadding,
                fontSize: fontSize,
                header: false,
            )
            try renderPreparedTableRow(
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
    ) throws -> [Double] {
        let minimumColumnWidth = min(36, contentWidth / Double(columns))
        let maximumColumnWidth = columns == 1 ? contentWidth : contentWidth * 0.65
        let metrics = try (0 ..< columns).map { column in
            try tableColumnMetrics(
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
    ) throws -> TableColumnMetrics {
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
        let contentWidths = try allRuns.map { try textWidth($0) }
        let tokenWidths = try allRuns
            .flatMap(tokenize)
            .filter { $0.text != "\n" }
            .map { try textWidth($0) }
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
    ) throws -> TablePreparedRow {
        let cellLines = try (0 ..< columns).map { column in
            let cell = column < cells.count ? cells[column] : []
            let width = column < columnWidths.count ? columnWidths[column] : contentWidth / Double(columns)
            return try wrappedLines(
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
    ) throws {
        let cellLines = row.cellLines
        let maxLines = max(1, cellLines.map(\.count).max() ?? 1)
        var lineOffset = 0

        while lineOffset < maxLines {
            try ensureTableRowFragmentSpace(
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
            try renderTableRowFragment(
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
                    try renderPreparedTableRow(
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
    ) throws {
        guard y - height < options.margins.bottom else {
            return
        }

        startNewPage()
        guard let header else {
            return
        }

        try renderPreparedTableRow(
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
            let element = beginStructureElement(.paragraph)
            defer { endStructureElement(element) }
            try drawWrapped(
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
        let figureElement = beginStructureElement(
            .figure,
            attributes: PDFTaggedContent.Attributes(
                alternateDescription: alt.isEmpty ? source : alt,
            ),
        )
        let marked = beginMarkedContentForCurrentElement()
        currentPage.drawImage(
            name: image.name,
            x: options.margins.left,
            y: y - drawHeight,
            width: drawWidth,
            height: drawHeight,
        )
        endMarkedContentIfNeeded(marked)
        endStructureElement(figureElement)
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
    ) throws {
        for line in try wrappedLines(runs, maxWidth: maxWidth) {
            ensureSpace(lineHeight)
            try drawRuns(line, x: x, y: y, maxWidth: maxWidth)
            y -= lineHeight
        }
    }

    private mutating func renderCodeBlockFragment(
        _ lines: [[PDFTextRun]],
        size: Double,
        lineHeight: Double,
        padding: Double,
    ) throws {
        let topY = y
        let height = Double(lines.count) * lineHeight + padding * 2
        let artifact = beginArtifactIfTagged()
        currentPage.drawRectangle(
            x: options.margins.left,
            y: topY - height,
            width: contentWidth,
            height: height,
            stroke: nil,
            fill: PDFColor(red: 0.95, green: 0.95, blue: 0.95),
        )
        endMarkedContentIfNeeded(artifact)

        var lineY = topY - padding - size
        for line in lines {
            try drawRuns(line, x: options.margins.left + padding, y: lineY, applyBidi: false)
            lineY -= lineHeight
        }
        y = topY - height
    }

    private func codeBlockLineCapacity(
        lineHeight: Double,
        padding: Double,
    ) -> Int {
        max(1, Int(floor((availablePageHeight - padding * 2) / lineHeight)))
    }

    private func expandCodeTabs(_ line: String) -> String {
        var expanded = ""
        var column = 0

        for character in line {
            if character == "\t" {
                let spaces = codeBlockTabWidth - column % codeBlockTabWidth
                expanded += String(repeating: " ", count: spaces)
                column += spaces
            } else {
                expanded.append(character)
                column += 1
            }
        }

        return expanded
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
    ) throws {
        let rowElement = beginStructureElement(.tableRow)
        defer { endStructureElement(rowElement) }

        let rowHeight = Double(lineCount) * lineHeight + cellPadding * 2
        let rowBottom = y - rowHeight
        var x = options.margins.left

        for column in 0 ..< cellLines.count {
            let columnWidth = column < columnWidths.count ? columnWidths[column] : 0
            let artifact = beginArtifactIfTagged()
            currentPage.drawRectangle(
                x: x,
                y: rowBottom,
                width: columnWidth,
                height: rowHeight,
                stroke: .gray,
                fill: header ? PDFColor(red: 0.93, green: 0.93, blue: 0.93) : nil,
            )
            endMarkedContentIfNeeded(artifact)

            let visibleLines = cellLines[column].dropFirst(lineOffset).prefix(lineCount)
            let cellElement = beginStructureElement(
                header ? .tableHeader : .tableCell,
                attributes: header ? PDFTaggedContent.Attributes(tableHeaderScope: .column) : PDFTaggedContent.Attributes(),
            )
            var lineY = y - cellPadding - fontSize
            for line in visibleLines {
                let width = try textWidth(Array(line))
                let alignment = column < alignments.count ? alignments[column] : .leading
                let textX = switch alignment {
                case .leading:
                    x + cellPadding
                case .center:
                    x + (columnWidth - width) / 2
                case .trailing:
                    x + columnWidth - cellPadding - width
                }
                let drawWidth = alignment == .leading ? max(0, columnWidth - cellPadding * 2) : nil
                try drawRuns(Array(line), x: textX, y: lineY, maxWidth: drawWidth)
                lineY -= lineHeight
            }
            endStructureElement(cellElement)
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
    ) throws -> [[PDFTextRun]] {
        let tokens = tokenize(runs)
        var lines: [[PDFTextRun]] = []
        var current: [PDFTextRun] = []
        var currentWidth = 0.0

        for token in try tokens.flatMap({ try splitOversizedToken($0, maxWidth: maxWidth) }) {
            if token.text == "\n" {
                lines.append(current)
                current = []
                currentWidth = 0
                continue
            }

            let width = try textWidth(token)
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
    ) throws -> [PDFTextRun] {
        guard token.text != "\n",
              maxWidth > 0,
              try textWidth(token) > maxWidth
        else {
            return [token]
        }

        var parts: [PDFTextRun] = []
        var buffer = ""
        for character in token.text {
            let candidate = buffer + String(character)
            if !buffer.isEmpty,
               try textWidth(token.withText(candidate)) > maxWidth
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
        let lineBreaker = LineBreakOpportunityDetector()

        for run in runs {
            for segment in lineBreaker.segments(in: run.text) where !segment.isEmpty {
                tokens.append(run.withText(segment))
            }
        }

        return tokens
    }

    private mutating func beginStructureElement(
        _ role: PDFTaggedContent.Role,
        attributes: PDFTaggedContent.Attributes = PDFTaggedContent.Attributes(),
    ) -> Int? {
        guard var builder = taggedContentBuilder else {
            return nil
        }
        let id = builder.beginElement(role: role, attributes: attributes)
        taggedContentBuilder = builder
        return id
    }

    private mutating func endStructureElement(_ id: Int?) {
        guard let id, var builder = taggedContentBuilder else {
            return
        }
        builder.endElement(id)
        taggedContentBuilder = builder
    }

    private mutating func beginMarkedContentForCurrentElement() -> Bool {
        guard markedContentDepth == 0,
              var builder = taggedContentBuilder,
              let mark = builder.markCurrentElement(onPage: currentPageIndex)
        else {
            return false
        }

        taggedContentBuilder = builder
        markedContentDepth += 1
        currentPage.beginMarkedContent(tag: PDFSyntax.Name(mark.role.rawValue), mcid: mark.mcid)
        return true
    }

    private mutating func endMarkedContentIfNeeded(_ didBegin: Bool) {
        guard didBegin else {
            return
        }
        currentPage.endMarkedContent()
        markedContentDepth = max(0, markedContentDepth - 1)
    }

    private mutating func beginArtifactIfTagged() -> Bool {
        guard markedContentDepth == 0, taggedContentBuilder != nil else {
            return false
        }
        markedContentDepth += 1
        currentPage.beginArtifact()
        return true
    }

    private mutating func drawRuns(
        _ runs: [PDFTextRun],
        x: Double,
        y: Double,
        maxWidth: Double? = nil,
        applyBidi: Bool = true,
    ) throws {
        guard !runs.isEmpty else {
            return
        }

        let marked = beginMarkedContentForCurrentElement()
        defer { endMarkedContentIfNeeded(marked) }

        if applyBidi, let bidiLine = try bidiLine(from: runs, x: x, maxWidth: maxWidth) {
            for run in bidiLine.visualRuns.sorted(by: { $0.sourceScalarOffset < $1.sourceScalarOffset }) {
                try drawBidiPositionedRun(run, y: y)
            }
            return
        }

        var cursor = x
        for run in runs {
            try currentPage.drawTextRun(
                run,
                x: cursor,
                y: y,
                fontSet: options.fontSet,
                embeddedFonts: embeddedFonts,
            )
            cursor += try textWidth(run)
        }
    }

    private func bidiLine(
        from runs: [PDFTextRun],
        x: Double,
        maxWidth: Double?,
    ) throws -> BidiLine? {
        guard let template = runs.first,
              runs.allSatisfy({ isSingleStyleBidiRun($0, matching: template) })
        else {
            return nil
        }

        let logicalText = runs.map(\.text).joined()
        let ordering = BidiParagraphOrdering()
        guard ordering.containsRightToLeftText(logicalText) else {
            return nil
        }

        let paragraph = try ordering.order(logicalText)
        let visualRuns = paragraph.visualRuns.map { run in
            template.withText(run.displayText)
        }
        let lineWidth = try textWidth(visualRuns)
        var cursor = x
        if paragraph.baseDirection == .rightToLeft, let maxWidth {
            cursor += max(0, maxWidth - lineWidth)
        }

        var positionedRuns: [BidiPositionedRun] = []
        for run in paragraph.visualRuns {
            let positioned = try positionedBidiRuns(for: run, template: template, x: cursor)
            positionedRuns.append(contentsOf: positioned)
            cursor += try textWidth(template.withText(run.displayText))
        }
        return BidiLine(visualRuns: positionedRuns)
    }

    private func drawBidiPositionedRun(_ run: BidiPositionedRun, y: Double) throws {
        if let mapping = try mirroredBidiGlyphMapping(for: run),
           let entry = embeddedFonts.entry(for: run.sourceTextRun.font)
        {
            try currentPage.drawCIDText(
                mapping: mapping,
                fontResource: entry.resource,
                fontSize: run.sourceTextRun.size,
                x: run.x,
                y: y,
                color: run.sourceTextRun.color,
                decorationsFor: run.sourceTextRun,
            )
            return
        }

        try currentPage.drawTextRun(
            run.sourceTextRun,
            x: run.x,
            y: y,
            fontSet: options.fontSet,
            embeddedFonts: embeddedFonts,
        )
    }

    private func isSingleStyleBidiRun(_ run: PDFTextRun, matching template: PDFTextRun) -> Bool {
        run.font == template.font
            && run.size == template.size
            && run.color == template.color
            && run.underline == template.underline
            && run.strikethrough == template.strikethrough
            && run.linkDestination == nil
    }

    private func positionedBidiRuns(
        for run: BidiParagraphOrdering.Run,
        template: PDFTextRun,
        x: Double,
    ) throws -> [BidiPositionedRun] {
        let sourceCharacters = Array(run.sourceText)
        let displayCharacters = Array(run.displayText)
        let sourceScalarOffsets = scalarOffsetsByCharacter(in: run.sourceText)
        guard sourceCharacters.count == displayCharacters.count else {
            return [
                BidiPositionedRun(
                    sourceTextRun: template.withText(run.sourceText),
                    displayText: run.sourceText,
                    x: x,
                    sourceScalarOffset: run.sourceScalarRange.lowerBound,
                ),
            ]
        }

        var cursor = x
        var positionedRuns: [BidiPositionedRun] = []
        for displayIndex in sourceCharacters.indices {
            let sourceIndex = run.direction == .rightToLeft
                ? sourceCharacters.count - 1 - displayIndex
                : displayIndex
            let displayText = String(displayCharacters[displayIndex])
            let textRun = template.withText(String(sourceCharacters[sourceIndex]))
            positionedRuns.append(
                BidiPositionedRun(
                    sourceTextRun: textRun,
                    displayText: displayText,
                    x: cursor,
                    sourceScalarOffset: run.sourceScalarRange.lowerBound + sourceScalarOffsets[sourceIndex],
                ),
            )
            cursor += try textWidth(template.withText(displayText))
        }
        return positionedRuns
    }

    private func mirroredBidiGlyphMapping(for run: BidiPositionedRun) throws -> ShapedTextMapping? {
        guard run.sourceTextRun.text != run.displayText,
              let entry = embeddedFonts.entry(for: run.sourceTextRun.font),
              let sourceScalar = onlyScalar(in: run.sourceTextRun.text),
              let displayScalar = onlyScalar(in: run.displayText)
        else {
            return nil
        }
        let syntheticCode = try mirroredPDFCharacterCode(source: sourceScalar, display: displayScalar, entry: entry)

        let displayMapping = try embeddedFonts.mapping(
            for: run.sourceTextRun.withText(run.displayText),
            entry: entry,
        )
        guard let displayGlyph = displayMapping.glyphs.first, displayMapping.glyphs.count == 1 else {
            return nil
        }

        guard let syntheticScalar = UnicodeScalar(0x100000 + UInt32(syntheticCode)) else {
            throw PDFEmbeddedFontError.unavailableMirroredGlyphCode(source: sourceScalar, display: displayScalar)
        }
        let glyph = ShapedTextMapping.Glyph(
            glyphID: displayGlyph.glyphID,
            cid: syntheticCode,
            pdfCharacterCode: syntheticCode,
            advanceWidth: displayGlyph.advanceWidth,
            advance: displayGlyph.width,
            cmapScalar: syntheticScalar,
        )
        return try ShapedTextMapping(
            sourceText: run.sourceTextRun.text,
            clusters: [
                ShapedTextMapping.Cluster(
                    sourceScalarRange: 0 ..< 1,
                    normalizedText: run.displayText,
                    glyphs: [glyph],
                    toUnicodeScalars: [sourceScalar],
                ),
            ],
        )
    }

    private func mirroredPDFCharacterCode(
        source: UnicodeScalar,
        display: UnicodeScalar,
        entry: PDFEmbeddedFontCatalog.Entry,
    ) throws -> UInt16 {
        guard let pairOffset = mirroredPairOffset(source: source, display: display) else {
            throw PDFEmbeddedFontError.unavailableMirroredGlyphCode(source: source, display: display)
        }

        let code = UInt32(entry.resource.metadata.maxp.numGlyphs) + UInt32(pairOffset)
        guard code <= UInt16.max else {
            throw PDFEmbeddedFontError.unavailableMirroredGlyphCode(source: source, display: display)
        }
        return UInt16(code)
    }

    private func mirroredPairOffset(source: UnicodeScalar, display: UnicodeScalar) -> UInt16? {
        switch (source.value, display.value) {
        case (0x28, 0x29):
            1
        case (0x29, 0x28):
            2
        case (0x3C, 0x3E):
            3
        case (0x3E, 0x3C):
            4
        case (0x5B, 0x5D):
            5
        case (0x5D, 0x5B):
            6
        case (0x7B, 0x7D):
            7
        case (0x7D, 0x7B):
            8
        default:
            nil
        }
    }

    private func onlyScalar(in text: String) -> UnicodeScalar? {
        let scalars = Array(text.unicodeScalars)
        return scalars.count == 1 ? scalars[0] : nil
    }

    private func scalarOffsetsByCharacter(in text: String) -> [Int] {
        var offsets: [Int] = []
        var scalarOffset = 0
        for character in text {
            offsets.append(scalarOffset)
            scalarOffset += character.unicodeScalars.count
        }
        return offsets
    }

    private func textWidth(_ run: PDFTextRun) throws -> Double {
        try embeddedFonts.width(of: run, fallbackFontSet: options.fontSet)
    }

    private func textWidth(_ runs: [PDFTextRun]) throws -> Double {
        try runs.reduce(0) { partial, run in
            let width = try textWidth(run)
            return partial + width
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

    private var codeBlockPadding: Double {
        6
    }

    private var codeBlockFollowingGap: Double {
        max(8, options.baseFontSize * 0.75)
    }

    private var codeBlockTabWidth: Int {
        4
    }

    private var listTrailingSpacing: Double {
        listDepth > 1 ? 1 : 3
    }

    private var blockQuoteTopSpacing: Double {
        options.baseFontSize * 0.45
    }

    private var blockQuoteBottomSpacing: Double {
        options.baseFontSize * 0.55
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

    private var currentPageIndex: Int {
        pages.count - 1
    }

    private var chartTitleSize: Double {
        options.baseFontSize * 0.95
    }

    private var chartLabelSize: Double {
        max(7.2, options.baseFontSize * 0.72)
    }

    private var chartPalette: [PDFColor] {
        [
            PDFColor(red: 0.11, green: 0.47, blue: 0.71),
            PDFColor(red: 0.89, green: 0.47, blue: 0.20),
            PDFColor(red: 0.20, green: 0.63, blue: 0.17),
            PDFColor(red: 0.58, green: 0.40, blue: 0.74),
            PDFColor(red: 0.55, green: 0.34, blue: 0.29),
            PDFColor(red: 0.89, green: 0.10, blue: 0.11),
            PDFColor(red: 0.50, green: 0.50, blue: 0.50),
            PDFColor(red: 0.74, green: 0.74, blue: 0.13),
        ]
    }

    private enum ChartTextAlignment {
        case left
        case center
        case right
    }

    private enum ChartRenderPlanResult {
        case plan(ChartRenderPlan)
        case fallback(String)
    }

    private struct ChartRenderPlan {
        var chart: ChartBlock
        var height: Double
        var plotFrame: ChartFrame?
        var xTicks: [Double]
        var yTicks: [Double]
        var xDomain: (min: Double, max: Double)
        var yDomain: (min: Double, max: Double)
        var pieRadius: Double?
        var legendWidth: Double?
    }

    private struct ChartFrame {
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
