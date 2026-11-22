import Foundation

struct MermaidDiagram: Equatable {
    var direction: Direction
    var nodes: [Node]
    var edges: [Edge]
    var groups: [Group] = []

    static func parse(_ source: String) -> ParseResult {
        var parser = Parser(source: source)
        return parser.parse()
    }

    func layers() -> [[Node]] {
        var indegree = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, 0) })
        var outgoing: [String: [String]] = [:]
        for edge in edges {
            outgoing[edge.source, default: []].append(edge.target)
            indegree[edge.target, default: 0] += 1
        }

        var queue = nodes.filter { indegree[$0.id] == 0 }.map(\.id)
        var processedNodes = Set<String>()
        var levels = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, 0) })

        while processedNodes.count < nodes.count {
            while !queue.isEmpty {
                let id = queue.removeFirst()
                processedNodes.insert(id)

                // Only forward edges (to a not-yet-processed node) inform layering and
                // release successors. A back-edge to an already-processed node is left for
                // drawing but does not bump levels, so cycles produce no empty layers.
                for target in outgoing[id, default: []] where !processedNodes.contains(target) {
                    levels[target] = max(levels[target, default: 0], levels[id, default: 0] + 1)
                    indegree[target, default: 0] -= 1
                    if indegree[target] == 0 {
                        queue.append(target)
                    }
                }
            }

            if processedNodes.count < nodes.count {
                // Cyclic input: release the unprocessed node with the fewest remaining
                // incoming edges, which breaks a back-edge so layering can proceed. Among
                // equals the node declared first goes first, where the author starts the
                // loop, so the edge back to it is the one drawn backwards. The back-edge
                // itself is still drawn later, so cycles render rather than fail.
                guard let next = nodes.enumerated()
                    .filter({ !processedNodes.contains($0.element.id) })
                    .min(by: { lhs, rhs in
                        let left = indegree[lhs.element.id] ?? 0
                        let right = indegree[rhs.element.id] ?? 0
                        return left != right ? left < right : lhs.offset < rhs.offset
                    })?.element
                else {
                    break
                }
                indegree[next.id] = 0
                queue.append(next.id)
            }
        }

        let maxLevel = levels.values.max() ?? 0
        var layers = Array(repeating: [Node](), count: maxLevel + 1)
        for node in nodes {
            layers[levels[node.id, default: 0]].append(node)
        }

        switch direction {
        case .bottomTop, .rightLeft:
            return layers.reversed()
        case .topBottom, .leftRight:
            return layers
        }
    }

    enum ParseResult: Equatable {
        case diagram(MermaidDiagram)
        case unsupported(String)
    }

    enum Direction: Equatable {
        case topBottom
        case bottomTop
        case leftRight
        case rightLeft

        init?(token: String) {
            switch token.uppercased() {
            case "TD", "TB":
                self = .topBottom
            case "BT":
                self = .bottomTop
            case "LR":
                self = .leftRight
            case "RL":
                self = .rightLeft
            default:
                return nil
            }
        }

        var isVertical: Bool {
            switch self {
            case .topBottom, .bottomTop:
                true
            case .leftRight, .rightLeft:
                false
            }
        }
    }

    struct Node: Equatable {
        var id: String
        var label: String
        var hasExplicitLabel: Bool
        var shape: Shape = .rectangle

        /// The outline a node is drawn with, named by the brackets around its label.
        enum Shape: Equatable, Sendable {
            /// `A[label]`
            case rectangle
            /// `A(label)`
            case rounded
            /// `A([label])`
            case stadium
            /// `A{label}`, a decision.
            case diamond

            /// The size of the box that holds a label of `text` size (the padded text rectangle). A diamond is larger than its text: the
            /// corner `(w/2, h/2)` of the text rectangle lies inside the outline `|x|/(W/2) + |y|/(H/2) = 1` exactly when `w/W + h/H <= 1`,
            /// and `W = 2w, H = 2h` gives `1/2 + 1/2 = 1`, the padded corners on the outline, so the text itself is inside it.
            func boxSize(forText text: (width: Double, height: Double)) -> (width: Double, height: Double) {
                switch self {
                case .diamond:
                    (width: text.width * 2, height: text.height * 2)
                case .rectangle, .rounded, .stadium:
                    text
                }
            }

            /// The corners of a diamond that fills the box `left, bottom, width, height`: the midpoints of its four sides, clockwise from the top.
            static func diamondOutline(left: Double, bottom: Double, width: Double, height: Double) -> [PDFPageCanvas.Point] {
                [
                    PDFPageCanvas.Point(x: left + width / 2, y: bottom + height),
                    PDFPageCanvas.Point(x: left + width, y: bottom + height / 2),
                    PDFPageCanvas.Point(x: left + width / 2, y: bottom),
                    PDFPageCanvas.Point(x: left, y: bottom + height / 2),
                ]
            }
        }
    }

    /// A link between two nodes, or between a node and a group, or between two groups.
    struct Edge: Equatable {
        /// How a link is drawn. `hidden` (`~~~`) takes part in the layout and draws nothing.
        enum Style: Equatable {
            case arrow
            case dashedArrow
            case line
            case dashedLine
            case hidden
        }

        var source: String
        var target: String
        var label: String?
        var style: Style

        init(source: String, target: String, label: String?, style: Style = .arrow) {
            self.source = source
            self.target = target
            self.label = label
            self.style = style
        }

        init(source: String, target: String, label: String?, dashed: Bool) {
            self.init(source: source, target: target, label: label, style: dashed ? .dashedArrow : .arrow)
        }

        var dashed: Bool {
            style == .dashedArrow || style == .dashedLine
        }

        var hasArrowhead: Bool {
            style == .arrow || style == .dashedArrow
        }

        var isDrawn: Bool {
            style != .hidden
        }
    }

    /// A `subgraph ... end` block: a titled frame around the nodes written inside it.
    struct Group: Equatable {
        var id: String
        var title: String
        /// The group's own `direction`; `nil` takes the diagram's.
        var direction: Direction?
        var members: [String]
    }

    /// The diagram with every group collapsed into one node of the group's id and title, each
    /// member's links moved to that node and the links inside a group dropped. Its layers place
    /// the groups and the nodes outside them.
    func collapsedForLayout() -> MermaidDiagram {
        var groupOfMember: [String: String] = [:]
        for group in groups {
            for member in group.members {
                groupOfMember[member] = group.id
            }
        }
        func representative(_ id: String) -> String {
            groupOfMember[id] ?? id
        }

        var collapsedNodes: [Node] = []
        var placedGroups = Set<String>()
        for node in nodes {
            guard let groupID = groupOfMember[node.id] else {
                collapsedNodes.append(node)
                continue
            }
            if placedGroups.insert(groupID).inserted, let group = groups.first(where: { $0.id == groupID }) {
                collapsedNodes.append(Node(id: group.id, label: group.title, hasExplicitLabel: true))
            }
        }

        var collapsedEdges: [Edge] = []
        for edge in edges {
            var mapped = edge
            mapped.source = representative(edge.source)
            mapped.target = representative(edge.target)
            if mapped.source != mapped.target {
                collapsedEdges.append(mapped)
            }
        }

        return MermaidDiagram(direction: direction, nodes: collapsedNodes, edges: collapsedEdges)
    }

    /// The nodes of one group, the links between them, and the group's direction, or the
    /// diagram's when the group has none.
    func innerDiagram(of group: Group) -> MermaidDiagram {
        let members = Set(group.members)
        return MermaidDiagram(
            direction: group.direction ?? direction,
            nodes: nodes.filter { members.contains($0.id) },
            edges: edges.filter { members.contains($0.source) && members.contains($0.target) },
        )
    }

    private struct SourceLine {
        var number: Int
        var text: String
    }

    private struct Endpoint {
        var id: String
        var label: String?
        var shape: Node.Shape = .rectangle
    }

    private struct Parser {
        private enum Outcome<Value> {
            case success(Value)
            case failure(String)
        }

        private var lines: [SourceLine]
        private var nodes: [Node] = []
        private var nodeIndexes: [String: Int] = [:]
        private var edges: [Edge] = []
        private var groups: [Group] = []
        private var groupLines: [Int] = []
        private var groupOfNode: [String: Int] = [:]
        private var openGroup: Int?
        private var currentLine = 0

        init(source: String) {
            lines = source
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
                .compactMap { offset, line in
                    let text = String(line).trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty, !text.hasPrefix("%%") else {
                        return nil
                    }
                    return SourceLine(number: offset + 1, text: text)
                }
        }

        mutating func parse() -> ParseResult {
            guard let header = lines.first else {
                return .unsupported("empty Mermaid block")
            }
            guard let direction = parseHeader(header.text) else {
                return .unsupported("line \(header.number): expected `flowchart TD` or `graph TD`")
            }

            for line in lines.dropFirst() {
                currentLine = line.number
                let text = stripTrailingSemicolon(line.text)
                if let keyword = parseKeywordStatement(text) {
                    if case let .failure(reason) = keyword {
                        return .unsupported("line \(line.number): \(reason)")
                    }
                } else if let chain = parseChain(text) {
                    switch chain {
                    case let .success(chainEdges):
                        edges.append(contentsOf: chainEdges)
                    case let .failure(reason):
                        return .unsupported("line \(line.number): \(reason)")
                    }
                } else {
                    switch parseNode(text) {
                    case .success:
                        break
                    case let .failure(reason):
                        return .unsupported("line \(line.number): \(reason)")
                    }
                }
            }

            if let open = openGroup {
                return .unsupported("line \(groupLines[open]): subgraph `\(groups[open].id)` is not closed with `end`")
            }
            if let reason = settleGroups() {
                return .unsupported(reason)
            }

            guard !nodes.isEmpty else {
                return .unsupported("flowchart has no nodes")
            }

            return .diagram(MermaidDiagram(direction: direction, nodes: nodes, edges: edges, groups: groups))
        }

        /// Reads `subgraph`, `direction` and `end`. Returns `nil` for any other line. A node
        /// that merely starts with one of these words, as `direction --> x` does, is not one.
        private mutating func parseKeywordStatement(_ text: String) -> Outcome<Void>? {
            let words = text.split(whereSeparator: \.isWhitespace)
            guard let first = words.first else {
                return nil
            }

            if text == "end" {
                guard openGroup != nil else {
                    return .failure("`end` without a matching `subgraph`")
                }
                openGroup = nil
                return .success(())
            }

            // `direction -->x` is an edge from a node named `direction`, not a statement.
            if first == "direction", words.count == 2, Self.link(startingAt: words[1]) == nil {
                guard let open = openGroup else {
                    return .failure("`direction` is only supported inside a subgraph")
                }
                guard let direction = Direction(token: String(words[1])) else {
                    return .failure("direction `\(words[1])` is not one of TD, TB, BT, LR, RL")
                }
                groups[open].direction = direction
                return .success(())
            }

            let header = text.dropFirst("subgraph".count).trimmingCharacters(in: .whitespaces)
            guard first == "subgraph", Self.link(startingAt: Substring(header)) == nil else {
                return nil
            }
            return openSubgraph(header: header)
        }

        private mutating func openSubgraph(header: String) -> Outcome<Void> {
            guard openGroup == nil else {
                return .failure("nested subgraphs are not supported")
            }
            guard !header.isEmpty else {
                return .failure("`subgraph` needs an id, as in `subgraph id[\"Title\"]`")
            }
            let endpoint: Endpoint
            switch parseEndpoint(header) {
            case let .success(parsed):
                endpoint = parsed
            case let .failure(reason):
                return .failure("invalid subgraph header: \(reason)")
            }
            guard !groups.contains(where: { $0.id == endpoint.id }) else {
                return .failure("subgraph `\(endpoint.id)` is declared twice")
            }

            groups.append(Group(id: endpoint.id, title: endpoint.label ?? endpoint.id, direction: nil, members: []))
            groupLines.append(currentLine)
            openGroup = groups.count - 1
            return .success(())
        }

        /// Checks every group once all lines are read. A group has at least one node. An id
        /// written as a node before its `subgraph` line, as in `A ~~~ G`, names the group, so
        /// that placeholder node is removed; an id that is also a labelled node or a member of
        /// a group is a clash.
        private mutating func settleGroups() -> String? {
            for (index, group) in groups.enumerated() {
                if group.members.isEmpty {
                    return "line \(groupLines[index]): subgraph `\(group.id)` has no nodes"
                }
                if let nodeIndex = nodeIndexes[group.id],
                   nodes[nodeIndex].hasExplicitLabel || groupOfNode[group.id] != nil
                {
                    return "line \(groupLines[index]): `\(group.id)` is both a node and a subgraph"
                }
            }

            // A link between a group and itself or its own node has no frame to join at.
            for (index, group) in groups.enumerated() {
                let members = Set(group.members)
                for edge in edges {
                    let touchesGroup = edge.source == group.id || edge.target == group.id
                    let inside = { (id: String) in id == group.id || members.contains(id) }
                    if touchesGroup, inside(edge.source), inside(edge.target) {
                        return "line \(groupLines[index]): a link between subgraph `\(group.id)` and itself or its own node is not supported"
                    }
                }
            }

            let groupIDs = Set(groups.map(\.id))
            nodes.removeAll { groupIDs.contains($0.id) }
            return nil
        }

        private func parseHeader(_ line: String) -> Direction? {
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count <= 2,
                  let keyword = parts.first?.lowercased(),
                  keyword == "flowchart" || keyword == "graph"
            else {
                return nil
            }

            guard parts.count == 2 else {
                return .topBottom
            }
            return Direction(token: parts[1])
        }

        /// One arrow between two endpoint texts of a chain, with its own label and line style.
        private struct Link {
            var label: String?
            var style: Edge.Style
        }

        /// The link that starts `rest`, with its length in characters, or `nil` when none does.
        /// `-->` and longer `--->`, `-.->`, plain `---` and longer, dotted `-.-`, and invisible
        /// `~~~` and longer. Two dashes alone, as in `a--b`, are text.
        private static func link(startingAt rest: Substring) -> (length: Int, style: Edge.Style)? {
            if rest.hasPrefix("-.->") {
                return (4, .dashedArrow)
            }
            if rest.hasPrefix("-.-") {
                return (3, .dashedLine)
            }
            if rest.hasPrefix("~~~") {
                return (rest.prefix { $0 == "~" }.count, .hidden)
            }
            let dashes = rest.prefix { $0 == "-" }.count
            let afterDashes = rest.dropFirst(dashes).first
            if dashes >= 2, afterDashes == ">" {
                return (dashes + 1, .arrow)
            }
            if dashes >= 3 {
                return (dashes, .line)
            }
            return nil
        }

        /// The bracket that closes each one that opens a node's label.
        private static let closingBracket: [Character: Character] = ["[": "]", "(": ")", "{": "}"]

        private static func mentionsLink(_ line: String) -> Bool {
            ["-->", "-.->", "-.-", "---", "~~~"].contains { line.contains($0) }
        }

        /// A line cut at its arrows: `endpoints.count == links.count + 1`.
        private struct Chain {
            var endpoints: [String]
            var links: [Link]
        }

        /// Reads a line as a chain of edges, `A --> B -.->|x| C`, one edge for each pair of
        /// neighbouring endpoints. Returns `nil` when the line holds no arrow, so it is a
        /// plain node declaration.
        private mutating func parseChain(_ line: String) -> Outcome<[Edge]>? {
            let chain: Chain
            switch splitChain(line) {
            case nil:
                return nil
            case let .failure(reason):
                return .failure(reason)
            case let .success(parts):
                chain = parts
            }

            var endpoints: [Endpoint] = []
            for (position, text) in chain.endpoints.enumerated() {
                switch parseEndpoint(text) {
                case let .success(endpoint):
                    endpoints.append(endpoint)
                case let .failure(reason):
                    return .failure(position == 0 ? "invalid edge source: \(reason)" : "invalid edge target: \(reason)")
                }
            }

            for endpoint in endpoints {
                switch record(endpoint) {
                case .success:
                    break
                case let .failure(reason):
                    return .failure(reason)
                }
            }

            return .success(zip(zip(endpoints, endpoints.dropFirst()), chain.links).map { pair, link in
                Edge(source: pair.0.id, target: pair.1.id, label: link.label, style: link.style)
            })
        }

        /// Cuts a line at each link (see `link(startingAt:)`), with an optional `|label|`
        /// straight after it. A link inside a quoted label or inside brackets is label text,
        /// not an edge. A line with no link that holds the thick `==>` or `===` link is reported
        /// as unsupported. A quote opens a quoted label only straight after `[`.
        private func splitChain(_ line: String) -> Outcome<Chain>? {
            var endpoints: [String] = []
            var links: [Link] = []
            var current = ""
            var insideQuotes = false
            var bracketDepth = 0
            // The bracket kind that opened the label (`[`, `(` or `{`), and the one that closes it. Only that kind is counted inside it.
            var opener: Character = "["
            var closer: Character = "]"
            var index = line.startIndex

            while index < line.endIndex {
                let character = line[index]
                if insideQuotes {
                    if character == "\"" {
                        insideQuotes = false
                    }
                } else if character == "\"" {
                    // A quote opens a quoted label only straight after a bracket (`[`, `(` or `{`). Anywhere else,
                    // as in `A[5" disk]`, it is a plain character of an unquoted label.
                    insideQuotes = bracketDepth > 0 && current.last { !$0.isWhitespace }.map { "[({".contains($0) } == true
                } else if bracketDepth == 0, let kind = Self.closingBracket[character] {
                    opener = character
                    closer = kind
                    bracketDepth = 1
                } else if character == opener {
                    bracketDepth += 1
                } else if character == closer {
                    bracketDepth = max(0, bracketDepth - 1)
                }

                guard !insideQuotes, bracketDepth == 0, character == "-" || character == "~",
                      let found = Self.link(startingAt: line[index...])
                else {
                    current.append(character)
                    index = line.index(after: index)
                    continue
                }

                index = line.index(index, offsetBy: found.length)
                var label: String?
                if index < line.endIndex, line[index] == "|" {
                    var labelStart = line.index(after: index)
                    // A quoted label (`|"text"|`) runs to the closing quote, so it may hold a `|` or a link; the quotes are not its text.
                    let quoted = labelStart < line.endIndex && line[labelStart] == "\""
                    if quoted {
                        labelStart = line.index(after: labelStart)
                    }
                    let labelEnd: String.Index
                    if quoted {
                        guard let closingQuote = line[labelStart...].firstIndex(of: "\""),
                              line.index(after: closingQuote) < line.endIndex,
                              line[line.index(after: closingQuote)] == "|"
                        else {
                            return .failure("a quoted edge label is missing its closing quote and `|`")
                        }
                        labelEnd = closingQuote
                    } else {
                        guard let closing = line[labelStart...].firstIndex(of: "|") else {
                            return .failure("edge label is missing its closing `|`")
                        }
                        labelEnd = closing
                    }
                    let text = Self.replacingLineBreaks(in: String(line[labelStart ..< labelEnd]), with: " ")
                        .split(whereSeparator: \.isWhitespace)
                        .joined(separator: " ")
                    label = text.isEmpty ? nil : text
                    index = line.index(after: quoted ? line.index(after: labelEnd) : labelEnd)
                }
                if found.style == .hidden, label != nil {
                    return .failure("an invisible `~~~` link cannot carry a label")
                }

                endpoints.append(current)
                links.append(Link(label: label, style: found.style))
                current = ""
            }

            // An unclosed quote or bracket hides every link after it. When the line does hold
            // one, say so instead of reading the rest as one label.
            if insideQuotes || bracketDepth > 0, Self.mentionsLink(line) {
                return .failure("unbalanced quote or bracket in a line with a link")
            }
            guard !links.isEmpty else {
                if line.contains("==>") || line.contains("===") {
                    return .failure("only solid `-->`, dashed `-.->`, plain `---` and invisible `~~~` flowchart links are supported")
                }
                return nil
            }
            endpoints.append(current)
            return .success(Chain(endpoints: endpoints, links: links))
        }

        /// Replaces each HTML line break (`<br>`, `<br/>`, `<br />`, in any case) with `replacement`.
        private static func replacingLineBreaks(in text: String, with replacement: String) -> String {
            var result = ""
            var index = text.startIndex
            while index < text.endIndex {
                if text[index] == "<", let end = lineBreakTagEnd(in: text, from: index) {
                    result += replacement
                    index = end
                } else {
                    result.append(text[index])
                    index = text.index(after: index)
                }
            }
            return result
        }

        /// The index just after a line break tag that starts at `start`, or `nil` when the text
        /// there is not one.
        private static func lineBreakTagEnd(in text: String, from start: String.Index) -> String.Index? {
            var cursor = text.index(after: start)

            func take(_ matches: (Character) -> Bool) -> Bool {
                guard cursor < text.endIndex, matches(text[cursor]) else {
                    return false
                }
                cursor = text.index(after: cursor)
                return true
            }

            func skipSpaces() {
                while take({ $0 == " " || $0 == "\t" }) {}
            }

            guard take({ $0 == "b" || $0 == "B" }), take({ $0 == "r" || $0 == "R" }) else {
                return nil
            }
            skipSpaces()
            _ = take { $0 == "/" }
            skipSpaces()
            return take { $0 == ">" } ? cursor : nil
        }

        /// A node label with each line break tag turned into a newline and no empty lines.
        private static func labelWithNewlines(_ label: String) -> String {
            replacingLineBreaks(in: label, with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }

        private mutating func parseNode(_ line: String) -> Outcome<Void> {
            switch parseEndpoint(line) {
            case let .success(endpoint):
                record(endpoint)
            case let .failure(reason):
                .failure(reason)
            }
        }

        /// Records a node and, inside a `subgraph`, makes it a member of that group. A node
        /// written outside any group stays where an earlier mention put it; one written inside
        /// two groups is rejected.
        private mutating func record(_ endpoint: Endpoint) -> Outcome<Void> {
            if case let .failure(reason) = recordNode(endpoint) {
                return .failure(reason)
            }
            guard let open = openGroup else {
                return .success(())
            }
            if let owner = groupOfNode[endpoint.id] {
                return owner == open ? .success(()) : .failure("node `\(endpoint.id)` is in more than one subgraph")
            }
            groupOfNode[endpoint.id] = open
            groups[open].members.append(endpoint.id)
            return .success(())
        }

        private mutating func recordNode(_ endpoint: Endpoint) -> Outcome<Void> {
            let label = endpoint.label ?? endpoint.id
            let explicit = endpoint.label != nil
            if let index = nodeIndexes[endpoint.id] {
                if explicit, nodes[index].hasExplicitLabel, nodes[index].label != label {
                    return .failure("node `\(endpoint.id)` has conflicting labels")
                }
                if explicit, !nodes[index].hasExplicitLabel {
                    nodes[index].label = label
                    nodes[index].shape = endpoint.shape
                    nodes[index].hasExplicitLabel = true
                }
                return .success(())
            }

            nodeIndexes[endpoint.id] = nodes.count
            nodes.append(Node(id: endpoint.id, label: label, hasExplicitLabel: explicit, shape: endpoint.shape))
            return .success(())
        }

        private func parseEndpoint(_ raw: String) -> Outcome<Endpoint> {
            let text = stripTrailingSemicolon(raw).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else {
                return .failure("empty endpoint")
            }

            var cursor = text.startIndex
            while cursor < text.endIndex, isNodeIDCharacter(text[cursor]) {
                cursor = text.index(after: cursor)
            }

            let id = String(text[..<cursor])
            guard !id.isEmpty else {
                return .failure("missing node identifier")
            }

            let remainder = text[cursor...].trimmingCharacters(in: .whitespaces)
            guard !remainder.isEmpty else {
                return .success(Endpoint(id: id, label: nil))
            }
            // A shape the renderer does not draw is named, never drawn as a rectangle.
            for opening in ["((", "{{", "[[", "[(", "[/", "[\\", ">"] where remainder.hasPrefix(opening) {
                return .failure("the node shape `\(opening)` is not supported; supported shapes are `[ ]`, `( )`, `([ ])` and `{ }`")
            }
            let pairs: [(open: String, close: String, shape: Node.Shape)] = [
                ("([", "])", .stadium), ("[", "]", .rectangle), ("(", ")", .rounded), ("{", "}", .diamond),
            ]
            guard let pair = pairs.first(where: { remainder.hasPrefix($0.open) && remainder.hasSuffix($0.close) }),
                  remainder.count >= pair.open.count + pair.close.count
            else {
                return .failure("only node shapes `A[Label]`, `A(Label)`, `A([Label])` and `A{Label}` are supported")
            }

            let innerStart = remainder.index(remainder.startIndex, offsetBy: pair.open.count)
            let innerEnd = remainder.index(remainder.endIndex, offsetBy: -pair.close.count)
            let label = Self.labelWithNewlines(unquoted(String(remainder[innerStart ..< innerEnd])))
            return .success(Endpoint(id: id, label: label.isEmpty ? id : label, shape: pair.shape))
        }

        private func isNodeIDCharacter(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_" || character == "-"
        }

        private func stripTrailingSemicolon(_ line: String) -> String {
            var text = line.trimmingCharacters(in: .whitespaces)
            if text.hasSuffix(";") {
                text.removeLast()
            }
            return text.trimmingCharacters(in: .whitespaces)
        }

        private func unquoted(_ label: String) -> String {
            let trimmed = label.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 2,
                  trimmed.first == "\"",
                  trimmed.last == "\""
            else {
                return trimmed
            }
            return String(trimmed.dropFirst().dropLast())
        }
    }
}
