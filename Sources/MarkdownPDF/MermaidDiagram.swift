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
                if let edge = parseEdge(text) {
                    switch edge {
                    case let .success(edge):
                        edges.append(edge)
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

        private mutating func parseEdge(_ line: String) -> Outcome<Edge>? {
            if let range = line.range(of: "-->|") {
                let sourceText = String(line[..<range.lowerBound])
                let remainder = line[range.upperBound...]
                guard let labelEnd = remainder.firstIndex(of: "|") else {
                    return .failure("edge label is missing its closing `|`")
                }
                let label = String(remainder[..<labelEnd]).trimmingCharacters(in: .whitespaces)
                let targetText = String(remainder[remainder.index(after: labelEnd)...])
                return parseEdge(sourceText: sourceText, targetText: targetText, label: label.isEmpty ? nil : label)
            }

            if let range = line.range(of: "-->") {
                return parseEdge(
                    sourceText: String(line[..<range.lowerBound]),
                    targetText: String(line[range.upperBound...]),
                    label: nil,
                )
            }

            if let range = line.range(of: "-.->|") {
                let sourceText = String(line[..<range.lowerBound])
                let remainder = line[range.upperBound...]
                guard let labelEnd = remainder.firstIndex(of: "|") else {
                    return .failure("edge label is missing its closing `|`")
                }
                let label = String(remainder[..<labelEnd]).trimmingCharacters(in: .whitespaces)
                let targetText = String(remainder[remainder.index(after: labelEnd)...])
                return parseEdge(
                    sourceText: sourceText,
                    targetText: targetText,
                    label: label.isEmpty ? nil : label,
                    dashed: true,
                )
            }

            if let range = line.range(of: "-.->") {
                return parseEdge(
                    sourceText: String(line[..<range.lowerBound]),
                    targetText: String(line[range.upperBound...]),
                    label: nil,
                    dashed: true,
                )
            }

            if line.contains("---") || line.contains("==>") {
                return .failure("only solid `-->` and dashed `-.->` flowchart edges are supported")
            }

            return nil
        }

        private mutating func parseEdge(
            sourceText: String,
            targetText: String,
            label: String?,
            dashed: Bool = false,
        ) -> Outcome<Edge> {
            switch parseEndpoint(sourceText) {
            case let .success(source):
                switch parseEndpoint(targetText) {
                case let .success(target):
                    switch record(source) {
                    case .success:
                        break
                    case let .failure(reason):
                        return .failure(reason)
                    }
                    switch record(target) {
                    case .success:
                        break
                    case let .failure(reason):
                        return .failure(reason)
                    }
                    return .success(Edge(source: source.id, target: target.id, label: label, dashed: dashed))
                case let .failure(reason):
                    return .failure("invalid edge target: \(reason)")
                }
            case let .failure(reason):
                return .failure("invalid edge source: \(reason)")
            }
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
            let label = unquoted(String(remainder[innerStart ..< innerEnd]))
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
