import Foundation

public struct MarkdownParser: Sendable {
    public struct Options: Equatable, Sendable {
        public var mathTypesetting: Bool

        public init(mathTypesetting: Bool = false) {
            self.mathTypesetting = mathTypesetting
        }
    }

    public var options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    public func parse(_ markdown: String) -> MarkdownDocument {
        var parser = BlockParser(markdown: markdown, options: options)
        return MarkdownDocument(blocks: parser.parseBlocks())
    }
}

private struct BlockParser {
    private let options: MarkdownParser.Options
    private let inlineParser: InlineParser
    private var lines: [String]
    private var index: Int = 0

    init(markdown: String, options: MarkdownParser.Options) {
        self.options = options
        inlineParser = InlineParser(options: options)
        lines = Self.stripFrontMatter(
            markdown
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init),
        )
    }

    private static func stripFrontMatter(_ lines: [String]) -> [String] {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return lines
        }

        guard let endIndex = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return lines
        }

        return Array(lines.dropFirst(endIndex + 1))
    }

    mutating func parseBlocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []

        while index < lines.count {
            let line = lines[index]

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
            } else if let block = parseFencedCodeBlock() {
                blocks.append(block)
            } else if let block = parseHeading() {
                blocks.append(block)
            } else if let block = parseBlockQuote() {
                blocks.append(block)
            } else if let block = parseFootnoteDefinition() {
                blocks.append(block)
            } else if let block = parseDisplayMathBlock() {
                blocks.append(block)
            } else if let block = parseTable() {
                blocks.append(block)
            } else if let block = parseUnorderedList() {
                blocks.append(block)
            } else if let block = parseOrderedList() {
                blocks.append(block)
            } else if isThematicBreak(line) {
                blocks.append(.thematicBreak)
                index += 1
            } else if isPageBreak(line) {
                blocks.append(.pageBreak)
                index += 1
            } else if let block = parseHTMLBlock() {
                blocks.append(block)
            } else {
                blocks.append(parseParagraph())
            }
        }

        // A page break is a separator, not content. A trailing one would emit a
        // blank final page, so it carries no meaning and is dropped here, where
        // "trailing" is knowable. Leading and consecutive breaks collapse in the
        // renderer, which skips a break on a page that has drawn nothing.
        while blocks.last == .pageBreak {
            blocks.removeLast()
        }

        return blocks
    }

    private mutating func parseHeading() -> MarkdownBlock? {
        let line = lines[index]
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let level = trimmed.prefix(while: { $0 == "#" }).count

        guard (1 ... 6).contains(level),
              trimmed.dropFirst(level).first == " "
        else {
            return nil
        }

        let raw = trimmed
            .dropFirst(level)
            .trimmingCharacters(in: .whitespaces)
            .trimmingTrailingHashes()
        index += 1
        return .heading(level: level, content: inlineParser.parse(raw))
    }

    private mutating func parseFencedCodeBlock() -> MarkdownBlock? {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        let fence: String

        if trimmed.hasPrefix("```") {
            fence = "```"
        } else if trimmed.hasPrefix("~~~") {
            fence = "~~~"
        } else {
            return nil
        }

        let info = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
        index += 1

        var codeLines: [String] = []
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                index += 1
                break
            }
            codeLines.append(lines[index])
            index += 1
        }

        return .codeBlock(
            info: info.isEmpty ? nil : info,
            code: codeLines.joined(separator: "\n"),
        )
    }

    private mutating func parseBlockQuote() -> MarkdownBlock? {
        guard stripBlockQuoteMarker(from: lines[index]) != nil else {
            return nil
        }

        var quoteLines: [String] = []
        while index < lines.count, let stripped = stripBlockQuoteMarker(from: lines[index]) {
            quoteLines.append(stripped)
            index += 1
        }

        var nested = BlockParser(markdown: quoteLines.joined(separator: "\n"), options: options)
        return .blockQuote(nested.parseBlocks())
    }

    private mutating func parseDisplayMathBlock() -> MarkdownBlock? {
        guard options.mathTypesetting else {
            return nil
        }

        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("$$") else {
            return nil
        }

        if trimmed.count > 4, trimmed.hasSuffix("$$") {
            let start = trimmed.index(trimmed.startIndex, offsetBy: 2)
            let end = trimmed.index(trimmed.endIndex, offsetBy: -2)
            index += 1
            return .displayMath(MarkdownMath(source: String(trimmed[start ..< end]), mode: .display))
        }

        guard trimmed == "$$" else {
            return nil
        }

        var mathLines: [String] = []
        var cursor = index + 1
        while cursor < lines.count {
            if lines[cursor].trimmingCharacters(in: .whitespaces) == "$$" {
                index = cursor + 1
                return .displayMath(MarkdownMath(source: mathLines.joined(separator: "\n"), mode: .display))
            }
            mathLines.append(lines[cursor])
            cursor += 1
        }

        return nil
    }

    private mutating func parseTable() -> MarkdownBlock? {
        guard index + 1 < lines.count,
              lines[index].contains("|"),
              let alignments = parseSeparatorRow(lines[index + 1])
        else {
            return nil
        }

        let headers = splitTableRow(lines[index]).map(inlineParser.parse)
        guard !headers.isEmpty, headers.count == alignments.count else {
            return nil
        }

        index += 2
        var rows: [[[MarkdownInline]]] = []

        while index < lines.count {
            let line = lines[index]
            guard line.contains("|"), !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                break
            }

            var cells = splitTableRow(line).map(inlineParser.parse)
            if cells.count < headers.count {
                cells.append(contentsOf: Array(repeating: [], count: headers.count - cells.count))
            }
            if cells.count > headers.count {
                cells = Array(cells.prefix(headers.count))
            }
            rows.append(cells)
            index += 1
        }

        return .table(.init(headers: headers, alignments: alignments, rows: rows))
    }

    private mutating func parseUnorderedList() -> MarkdownBlock? {
        guard unorderedMarker(in: lines[index]) != nil else {
            return nil
        }

        let items = parseListItems(kind: .unordered)
        return .unorderedList(items)
    }

    private mutating func parseOrderedList() -> MarkdownBlock? {
        guard let first = orderedMarker(in: lines[index]) else {
            return nil
        }

        let start = first.number
        let items = parseListItems(kind: .ordered)
        return .orderedList(start: start, items: items)
    }

    /// Collects the items of one list, taking indentation seriously.
    ///
    /// A marker line at the list's own indent opens an item. Everything that
    /// follows and is indented to at least the item's content column belongs to
    /// that item, including blank lines that are themselves followed by indented
    /// content. Those lines are dedented by the content column and parsed as a
    /// document in their own right, which is what makes nested lists, lazy
    /// continuation paragraphs, and block content inside items work: the nested
    /// parser simply sees a smaller document.
    ///
    /// A marker indented to at least the previous item's content column is that
    /// item's content, and the continuation loop below swallows it. Anything still
    /// carrying a marker when control returns here is therefore a sibling, however
    /// it is indented. That keeps `- a` / ` - b` one two-item list, as CommonMark
    /// requires and as the flat parser already did.
    private mutating func parseListItems(kind: ListKind) -> [MarkdownBlock.ListItem] {
        var items: [MarkdownBlock.ListItem] = []

        while index < lines.count,
              let contentStart = contentColumn(of: lines[index], kind: kind)
        {
            var itemLines = [String(lines[index].dropFirst(contentStart))]
            index += 1

            while index < lines.count {
                let line = lines[index]
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    // A blank line continues the item only when indented content
                    // follows it. Otherwise it terminates the item, and the list.
                    guard let next = lines[(index + 1)...].first(where: {
                        !$0.trimmingCharacters(in: .whitespaces).isEmpty
                    }), Self.indentWidth(of: next) >= contentStart else {
                        break
                    }
                    itemLines.append("")
                    index += 1
                    continue
                }
                guard Self.indentWidth(of: line) >= contentStart else {
                    break
                }
                itemLines.append(String(line.dropFirst(contentStart)))
                index += 1
            }

            var checkbox: MarkdownBlock.ListItem.Checkbox?
            if let first = itemLines.first,
               let task = taskListItem(from: first.trimmingCharacters(in: .whitespaces))
            {
                checkbox = task.checkbox
                itemLines[0] = task.content
            }

            var nested = BlockParser(markdown: itemLines.joined(separator: "\n"), options: options)
            let blocks = nested.parseBlocks()
            items.append(.init(
                blocks: blocks.isEmpty ? [.paragraph([])] : blocks,
                checkbox: checkbox,
            ))

            // Loose list: blank lines sitting between two siblings belong to the
            // list, not after it. Without this a blank line splits one list into
            // two, and the second restarts an ordered list's numbering.
            var lookahead = index
            while lookahead < lines.count,
                  lines[lookahead].trimmingCharacters(in: .whitespaces).isEmpty
            {
                lookahead += 1
            }
            if lookahead < lines.count,
               contentColumn(of: lines[lookahead], kind: kind) != nil,
               Self.indentWidth(of: lines[lookahead]) < contentStart
            {
                index = lookahead
            }
        }

        return items
    }

    private enum ListKind {
        case unordered
        case ordered
    }

    /// The content column of a line that opens an item of `kind`, or nil when the
    /// line does not open one.
    private func contentColumn(of line: String, kind: ListKind) -> Int? {
        switch kind {
        case .unordered:
            unorderedMarker(in: line)
        case .ordered:
            orderedMarker(in: line)?.contentStart
        }
    }

    /// Leading whitespace, counted in characters so it lines up with the
    /// character offsets `unorderedMarker(in:)` and `orderedMarker(in:)` return.
    private static func indentWidth(of line: String) -> Int {
        line.count - line.trimmingLeadingSpaces().count
    }

    private mutating func parseHTMLBlock() -> MarkdownBlock? {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("<"), trimmed.hasSuffix(">") else {
            return nil
        }

        var htmlLines: [String] = []
        while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            htmlLines.append(lines[index])
            index += 1
        }

        return .html(htmlLines.joined(separator: "\n"))
    }

    private mutating func parseFootnoteDefinition() -> MarkdownBlock? {
        guard let marker = footnoteDefinitionMarker(in: lines[index]) else {
            return nil
        }

        var definitionLines = [String(lines[index].dropFirst(marker.contentStart))]
        index += 1

        while index < lines.count, let continuation = footnoteContinuationLine(lines[index]) {
            definitionLines.append(continuation)
            index += 1
        }

        let body = definitionLines.joined(separator: "\n")
        var nested = BlockParser(markdown: body, options: options)
        return .footnoteDefinition(label: marker.label, blocks: nested.parseBlocks())
    }

    private mutating func parseParagraph() -> MarkdownBlock {
        let start = index
        var paragraphLines: [String] = []

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                break
            }
            if index != start, startsBlock(line) {
                break
            }
            paragraphLines.append(line)
            index += 1

            if paragraphLines.count == 1,
               index < lines.count,
               let level = setextLevel(lines[index])
            {
                index += 1
                return .heading(
                    level: level,
                    content: inlineParser.parse(paragraphLines[0].trimmingCharacters(in: .whitespaces)),
                )
            }
        }

        return .paragraph(inlineParser.parse(paragraphLines.joined(separator: "\n")))
    }

    private func startsBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("# ") ||
            trimmed.hasPrefix("## ") ||
            trimmed.hasPrefix("### ") ||
            trimmed.hasPrefix("```") ||
            trimmed.hasPrefix("~~~") ||
            stripBlockQuoteMarker(from: line) != nil ||
            footnoteDefinitionMarker(in: line) != nil ||
            (options.mathTypesetting && trimmed.hasPrefix("$$")) ||
            unorderedMarker(in: line) != nil ||
            orderedMarker(in: line) != nil ||
            isThematicBreak(line)
    }

    private func stripBlockQuoteMarker(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else {
            return nil
        }

        return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private func unorderedMarker(in line: String) -> Int? {
        let trimmed = line.trimmingLeadingSpaces()
        guard trimmed.count >= 2 else {
            return nil
        }

        let first = trimmed[trimmed.startIndex]
        let second = trimmed[trimmed.index(after: trimmed.startIndex)]
        guard ["-", "+", "*"].contains(first), second == " " else {
            return nil
        }

        let skipped = line.count - trimmed.count
        return skipped + 2
    }

    private func taskListItem(from item: String) -> (checkbox: MarkdownBlock.ListItem.Checkbox, content: String)? {
        let marker: MarkdownBlock.ListItem.Checkbox
        if item.hasPrefix("[ ]") {
            marker = .unchecked
        } else if item.hasPrefix("[x]") || item.hasPrefix("[X]") {
            marker = .checked
        } else {
            return nil
        }

        let afterMarker = item.index(item.startIndex, offsetBy: 3)
        guard afterMarker == item.endIndex || item[afterMarker].isWhitespace else {
            return nil
        }

        let contentStart = item[afterMarker...].firstIndex { !$0.isWhitespace } ?? item.endIndex
        return (marker, String(item[contentStart...]))
    }

    private func orderedMarker(in line: String) -> (number: Int, contentStart: Int)? {
        let trimmed = line.trimmingLeadingSpaces()
        var digits = ""
        var cursor = trimmed.startIndex

        while cursor < trimmed.endIndex, trimmed[cursor].isNumber {
            digits.append(trimmed[cursor])
            cursor = trimmed.index(after: cursor)
        }

        guard !digits.isEmpty,
              cursor < trimmed.endIndex,
              trimmed[cursor] == "." || trimmed[cursor] == ")"
        else {
            return nil
        }

        let afterMarker = trimmed.index(after: cursor)
        guard afterMarker < trimmed.endIndex, trimmed[afterMarker] == " " else {
            return nil
        }

        let skipped = line.count - trimmed.count
        return (Int(digits) ?? 1, skipped + digits.count + 2)
    }

    private func footnoteDefinitionMarker(in line: String) -> (label: String, contentStart: Int)? {
        let leadingSpaces = line.prefix(while: { $0 == " " }).count
        guard leadingSpaces <= 3 else {
            return nil
        }

        let markerStart = line.index(line.startIndex, offsetBy: leadingSpaces)
        guard line[markerStart...].hasPrefix("[^") else {
            return nil
        }

        let labelStart = line.index(markerStart, offsetBy: 2)
        guard let labelEnd = line[labelStart...].firstIndex(of: "]") else {
            return nil
        }

        let label = String(line[labelStart ..< labelEnd])
        guard !label.isEmpty else {
            return nil
        }

        let colon = line.index(after: labelEnd)
        guard colon < line.endIndex, line[colon] == ":" else {
            return nil
        }

        var contentStart = line.index(after: colon)
        while contentStart < line.endIndex, line[contentStart].isWhitespace {
            contentStart = line.index(after: contentStart)
        }

        return (label, line.distance(from: line.startIndex, to: contentStart))
    }

    private func footnoteContinuationLine(_ line: String) -> String? {
        if line.hasPrefix("    ") {
            return String(line.dropFirst(4))
        }
        if line.hasPrefix("\t") {
            return String(line.dropFirst())
        }
        return nil
    }

    /// An explicit page break, written as an HTML comment so the same document
    /// stays clean in every other Markdown renderer, where a comment is invisible.
    ///
    /// Accepts `<!-- pagebreak -->`, `<!--pagebreak-->`, and `<!-- pageBreak -->`.
    /// Must be checked before ``parseHTMLBlock()``, which would otherwise swallow
    /// the comment and draw it as visible text.
    private func isPageBreak(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("<!--"), trimmed.hasSuffix("-->") else {
            return false
        }

        let body = trimmed
            .dropFirst("<!--".count)
            .dropLast("-->".count)
            .trimmingCharacters(in: .whitespaces)
        return body.lowercased() == "pagebreak"
    }

    private func isThematicBreak(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else {
            return false
        }

        let compact = trimmed.filter { $0 != " " && $0 != "\t" }
        guard let first = compact.first,
              first == "-" || first == "*" || first == "_"
        else {
            return false
        }

        return compact.allSatisfy { $0 == first } && compact.count >= 3
    }

    private func setextLevel(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            return nil
        }

        if trimmed.allSatisfy({ $0 == "=" }) {
            return 1
        }
        if trimmed.allSatisfy({ $0 == "-" }) {
            return 2
        }
        return nil
    }

    private func parseSeparatorRow(_ line: String) -> [MarkdownBlock.Alignment]? {
        let cells = splitTableRow(line)
        guard !cells.isEmpty else {
            return nil
        }

        var alignments: [MarkdownBlock.Alignment] = []
        for cell in cells {
            let value = cell.trimmingCharacters(in: .whitespaces)
            guard value.count >= 3,
                  value.drop(while: { $0 == ":" }).dropLast(value.hasSuffix(":") ? 1 : 0).allSatisfy({ $0 == "-" })
            else {
                return nil
            }

            if value.hasPrefix(":"), value.hasSuffix(":") {
                alignments.append(.center)
            } else if value.hasSuffix(":") {
                alignments.append(.trailing)
            } else {
                alignments.append(.leading)
            }
        }

        return alignments
    }

    private func splitTableRow(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") {
            value.removeFirst()
        }
        if value.hasSuffix("|") {
            value.removeLast()
        }

        var cells: [String] = []
        var current = ""
        var escaped = false

        for character in value {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }

        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }
}

private extension String {
    func trimmingLeadingSpaces() -> String {
        String(drop(while: { $0 == " " || $0 == "\t" }))
    }

    func trimmingTrailingHashes() -> String {
        var result = trimmingCharacters(in: .whitespaces)

        while result.hasSuffix("#") {
            result.removeLast()
        }

        return result.trimmingCharacters(in: .whitespaces)
    }
}
