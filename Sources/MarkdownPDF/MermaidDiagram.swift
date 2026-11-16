import Foundation

struct MermaidDiagram: Equatable {
    var direction: Direction
    var nodes: [Node]
    var edges: [Edge]

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
                // incoming edges, which breaks a back-edge so layering can proceed. The
                // back-edge itself is still drawn later, so cycles render rather than fail.
                guard let next = nodes
                    .filter({ !processedNodes.contains($0.id) })
                    .min(by: { lhs, rhs in
                        let left = indegree[lhs.id] ?? 0
                        let right = indegree[rhs.id] ?? 0
                        return left != right ? left < right : lhs.id < rhs.id
                    })
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
    }

    struct Edge: Equatable {
        var source: String
        var target: String
        var label: String?
        var dashed: Bool = false
    }

    private struct SourceLine {
        var number: Int
        var text: String
    }

    private struct Endpoint {
        var id: String
        var label: String?
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
                let text = stripTrailingSemicolon(line.text)
                if let chain = parseChain(text) {
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

            guard !nodes.isEmpty else {
                return .unsupported("flowchart has no nodes")
            }

            return .diagram(MermaidDiagram(direction: direction, nodes: nodes, edges: edges))
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
            var dashed: Bool
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
                Edge(source: pair.0.id, target: pair.1.id, label: link.label, dashed: link.dashed)
            })
        }

        /// Cuts a line at each `-->` and `-.->`, with an optional `|label|` straight after the
        /// arrow. An arrow inside a quoted label or inside brackets is label text, not an edge.
        /// The plain `---` and thick `==>` links are not supported and are reported.
        private func splitChain(_ line: String) -> Outcome<Chain>? {
            var endpoints: [String] = []
            var links: [Link] = []
            var current = ""
            var insideQuotes = false
            var bracketDepth = 0
            var index = line.startIndex

            while index < line.endIndex {
                let character = line[index]
                if character == "\"" {
                    insideQuotes.toggle()
                } else if !insideQuotes {
                    if character == "[" {
                        bracketDepth += 1
                    } else if character == "]" {
                        bracketDepth = max(0, bracketDepth - 1)
                    }
                }

                guard !insideQuotes, bracketDepth == 0, character == "-" || character == "=" else {
                    current.append(character)
                    index = line.index(after: index)
                    continue
                }

                let rest = line[index...]
                let dashed = rest.hasPrefix("-.->")
                guard dashed || rest.hasPrefix("-->") else {
                    if rest.hasPrefix("---") || rest.hasPrefix("==>") {
                        return .failure("only solid `-->` and dashed `-.->` flowchart edges are supported")
                    }
                    current.append(character)
                    index = line.index(after: index)
                    continue
                }

                index = line.index(index, offsetBy: dashed ? 4 : 3)
                var label: String?
                if index < line.endIndex, line[index] == "|" {
                    let labelStart = line.index(after: index)
                    guard let labelEnd = line[labelStart...].firstIndex(of: "|") else {
                        return .failure("edge label is missing its closing `|`")
                    }
                    let text = Self.replacingLineBreaks(in: String(line[labelStart ..< labelEnd]), with: " ")
                        .split(whereSeparator: \.isWhitespace)
                        .joined(separator: " ")
                    label = text.isEmpty ? nil : text
                    index = line.index(after: labelEnd)
                }

                endpoints.append(current)
                links.append(Link(label: label, dashed: dashed))
                current = ""
            }

            // An unclosed quote or bracket hides every arrow after it. When the line does hold
            // an arrow, say so instead of reading the rest as one label.
            if insideQuotes || bracketDepth > 0, line.contains("-->") || line.contains("-.->") {
                return .failure("unbalanced quote or bracket in a line with an arrow")
            }
            guard !links.isEmpty else {
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

        private mutating func record(_ endpoint: Endpoint) -> Outcome<Void> {
            let label = endpoint.label ?? endpoint.id
            let explicit = endpoint.label != nil
            if let index = nodeIndexes[endpoint.id] {
                if explicit, nodes[index].hasExplicitLabel, nodes[index].label != label {
                    return .failure("node `\(endpoint.id)` has conflicting labels")
                }
                if explicit, !nodes[index].hasExplicitLabel {
                    nodes[index].label = label
                    nodes[index].hasExplicitLabel = true
                }
                return .success(())
            }

            nodeIndexes[endpoint.id] = nodes.count
            nodes.append(Node(id: endpoint.id, label: label, hasExplicitLabel: explicit))
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
            guard remainder.hasPrefix("["), remainder.hasSuffix("]") else {
                return .failure("only rectangle labels like `A[Label]` are supported")
            }

            let innerStart = remainder.index(after: remainder.startIndex)
            let innerEnd = remainder.index(before: remainder.endIndex)
            let label = Self.labelWithNewlines(unquoted(String(remainder[innerStart ..< innerEnd])))
            return .success(Endpoint(id: id, label: label.isEmpty ? id : label))
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
