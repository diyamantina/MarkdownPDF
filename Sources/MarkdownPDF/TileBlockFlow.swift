/// The flow graph of a ```` ```tile flow ```` block: nodes in columns joined by arrows, laid out by a pure function of the graph.
///
/// The layout is the SAME closed form as the page's SVG, so a page and its print put every box in the same place: a node's layer is the length of the
/// longest path into it (0 for a node with no edge into it), its row is its place, in the order the nodes first appear, among the nodes of its layer;
/// x = margin + layer * (width + gap across), y = margin + row * (height + gap down), in whole units. The units are scaled to the page when the picture
/// is wider than the measure, by one factor for the whole picture.
extension TileBlock {
    struct Flow: Equatable {
        /// The title when the block writes one; the page's default `Flow` is not printed.
        var title: String?
        var nodes: [Node]
        var edges: [Edge]
        var layout: Layout

        static let longestID = 32
        static let longestLabel = 18
        static let mostNodes = 60
        static let mostEdges = 200

        struct Node: Equatable {
            var id: String
            var label: String?
            var status: Status?

            /// What the node shows: its label, or its name.
            var shown: String {
                label ?? id
            }
        }

        struct Edge: Equatable {
            var source: Int
            var target: Int
        }

        /// A layer and a row for each node, and the size of the picture, in whole units.
        struct Layout: Equatable {
            static let nodeWidth = 140
            static let nodeHeight = 40
            static let acrossGap = 60
            static let downGap = 24
            static let margin = 12
            /// The corner radius of a box, as the SVG's `rx`.
            static let radius = 8

            var layers: [Int]
            var rows: [Int]
            var width: Int
            var height: Int

            /// The graph must have no cycle.
            init(nodeCount: Int, edges: [Edge]) {
                var layers = [Int](repeating: 0, count: nodeCount)
                var incoming = [Int](repeating: 0, count: nodeCount)
                for edge in edges {
                    incoming[edge.target] += 1
                }
                var ready = (0 ..< nodeCount).filter { incoming[$0] == 0 }
                var next = 0
                while next < ready.count {
                    let node = ready[next]
                    next += 1
                    for edge in edges where edge.source == node {
                        layers[edge.target] = max(layers[edge.target], layers[node] + 1)
                        incoming[edge.target] -= 1
                        if incoming[edge.target] == 0 {
                            ready.append(edge.target)
                        }
                    }
                }
                var counts = [Int](repeating: 0, count: (layers.max() ?? 0) + 1)
                var rows: [Int] = []
                for layer in layers {
                    rows.append(counts[layer])
                    counts[layer] += 1
                }
                self.layers = layers
                self.rows = rows
                width = 2 * Self.margin + counts.count * Self.nodeWidth + (counts.count - 1) * Self.acrossGap
                let tallest = counts.max() ?? 1
                height = 2 * Self.margin + tallest * Self.nodeHeight + (tallest - 1) * Self.downGap
            }

            func x(ofLayer layer: Int) -> Int {
                Self.margin + layer * (Self.nodeWidth + Self.acrossGap)
            }

            func y(ofRow row: Int) -> Int {
                Self.margin + row * (Self.nodeHeight + Self.downGap)
            }
        }

        /// The first cycle found, walking the nodes in order and the edges in the order written: the positions of the nodes on it, the first one repeated
        /// at the end. Nil for a graph with no cycle.
        static func cycle(nodeCount: Int, edges: [Edge]) -> [Int]? {
            var state = [Int](repeating: 0, count: nodeCount)
            var stack: [Int] = []
            func visit(_ node: Int) -> [Int]? {
                state[node] = 1
                stack.append(node)
                for edge in edges where edge.source == node {
                    if state[edge.target] == 1, let start = stack.firstIndex(of: edge.target) {
                        return Array(stack[start...]) + [edge.target]
                    }
                    if state[edge.target] == 0, let found = visit(edge.target) {
                        return found
                    }
                }
                stack.removeLast()
                state[node] = 2
                return nil
            }
            for node in 0 ..< nodeCount where state[node] == 0 {
                if let found = visit(node) {
                    return found
                }
            }
            return nil
        }
    }
}
