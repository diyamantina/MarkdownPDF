import Foundation
@testable import MarkdownPDF
import Testing

/// A flow tile in the PDF: a dependency graph drawn as rounded boxes in columns joined by curved arrows, laid out by the SAME closed form as the page's SVG
/// (`TileDown` `FlowLayout`): a node's layer is the length of the longest path into it, its row is its place among the nodes of its layer in the order
/// they first appear, x = 12 + layer * 200, y = 12 + row * 64, boxes 140 by 40.
///
/// `fixture` is the shared answer key: the SAME table is in the TileDown repository (`FlowLayoutTests`), so a page's picture and its print can never put a
/// box in a different place. Each row: the lines of the tile, then the nodes in order with their layer, their row, x and y, and the size of the picture.
@Suite("Tile blocks: the flow graph")
struct TileFlowTests {
    struct Case: Sendable {
        var name: String
        var lines: String
        var nodes: [(id: String, layer: Int, row: Int, x: Int, y: Int)]
        var width: Int
        var height: Int
    }

    static let fixture: [Case] = [
        Case(
            name: "one edge",
            lines: "edge: a -> b",
            nodes: [("a", 0, 0, 12, 12), ("b", 1, 0, 212, 12)],
            width: 364,
            height: 64,
        ),
        Case(
            name: "the build pipeline of the docs",
            lines: "edge: parse -> build\nedge: build -> test\nedge: build -> package\nedge: test -> release\nedge: package -> release\nnode: test\nstatus: running",
            nodes: [("parse", 0, 0, 12, 12), ("build", 1, 0, 212, 12), ("test", 2, 0, 412, 12), ("package", 2, 1, 412, 76), ("release", 3, 0, 612, 12)],
            width: 764,
            height: 128,
        ),
        Case(
            name: "a longer path pushes a node right: a -> b, b -> c, a -> c puts c in the third column",
            lines: "edge: a -> b\nedge: b -> c\nedge: a -> c",
            nodes: [("a", 0, 0, 12, 12), ("b", 1, 0, 212, 12), ("c", 2, 0, 412, 12)],
            width: 564,
            height: 64,
        ),
        Case(
            name: "two sources into one node, rows in the order the nodes first appear",
            lines: "edge: a -> c\nedge: b -> c",
            nodes: [("a", 0, 0, 12, 12), ("c", 1, 0, 212, 12), ("b", 0, 1, 12, 76)],
            width: 364,
            height: 128,
        ),
        Case(
            name: "a node with no edge",
            lines: "node: solo\nlabel: Alone",
            nodes: [("solo", 0, 0, 12, 12)],
            width: 164,
            height: 64,
        ),
        Case(
            name: "three columns of different heights",
            lines: "edge: a -> b\nedge: a -> c\nedge: a -> d\nedge: b -> e",
            nodes: [("a", 0, 0, 12, 12), ("b", 1, 0, 212, 12), ("c", 1, 1, 212, 76), ("d", 1, 2, 212, 140), ("e", 2, 0, 412, 12)],
            width: 564,
            height: 192,
        ),
    ]

    private func flow(_ body: String) -> TileBlock.Flow? {
        if case let .tile(.flow(flow)) = TileBlock.parse(type: "flow", body: body) {
            return flow
        }
        return nil
    }

    private func refusal(_ body: String) -> String? {
        if case let .unsupported(reason) = TileBlock.parse(type: "flow", body: body) {
            return reason
        }
        return nil
    }

    @Test("the layout is the shared answer key, box for box", arguments: fixture)
    func sharedFixture(_ item: Case) throws {
        let flow = try #require(flow(item.lines), Comment(rawValue: item.name))
        #expect(flow.nodes.map(\.id) == item.nodes.map(\.id), Comment(rawValue: item.name))
        let layout = flow.layout
        #expect(layout.layers == item.nodes.map(\.layer), Comment(rawValue: item.name))
        #expect(layout.rows == item.nodes.map(\.row), Comment(rawValue: item.name))
        #expect(item.nodes.indices.map { layout.x(ofLayer: layout.layers[$0]) } == item.nodes.map(\.x), Comment(rawValue: item.name))
        #expect(item.nodes.indices.map { layout.y(ofRow: layout.rows[$0]) } == item.nodes.map(\.y), Comment(rawValue: item.name))
        #expect(layout.width == item.width && layout.height == item.height, Comment(rawValue: item.name))
    }

    @Test("a node shows its label or its name, and a title is kept only when written")
    func parts() throws {
        let flow = try #require(flow("title: Build pipeline\nedge: a -> b\nnode: a\nlabel: Parse\nstatus: done"))
        #expect(flow.title == "Build pipeline")
        #expect(flow.nodes[0] == .init(id: "a", label: "Parse", status: .done))
        #expect(flow.nodes[0].shown == "Parse" && flow.nodes[1].shown == "b")
        #expect(self.flow("edge: a -> b")?.title == nil)
        #expect(flow.edges == [.init(source: 0, target: 1)])
    }

    @Test("every mistake is a refusal that says what to change", arguments: [
        ("", "no node"),
        ("edge: a", "a -> b"),
        ("edge: a -> b -> c", "a -> b"),
        ("edge: a -> ", "a -> b"),
        ("edge: a b -> c", "node name"),
        ("edge: a -> a", "cycle"),
        ("edge: a -> b\nedge: b -> a", "cycle"),
        ("edge: a -> b\nedge: a -> b", "twice"),
        ("node: a\nnode: a", "twice"),
        ("label: x", "before any node"),
        ("node: a\nlabel: x\nlabel: y", "twice"),
        ("node: a\nlabel: 0123456789012345678", "18"),
        ("node: a\nstatus: ok", "running, waiting, blocked, done or failed"),
        ("edge: a -> b\ncolor: red", "color"),
        ("title: A\ntitle: B\nedge: a -> b", "title"),
    ])
    func refusals(body: String, mention: String) {
        let reason = refusal(body)
        #expect(reason?.contains(mention) == true, Comment(rawValue: reason ?? "no refusal"))
    }

    @Test("a node name is letters, digits, dash and underscore, up to 32 characters")
    func names() {
        #expect(flow("edge: a-1 -> b_2") != nil)
        #expect(flow("edge: \(String(repeating: "x", count: 32)) -> y") != nil)
        #expect(refusal("edge: \(String(repeating: "x", count: 33)) -> y")?.contains("node name") == true)
    }

    @Test("sixty nodes and two hundred edges are fine; sixty-one nodes are not")
    func limits() {
        let chain = (1 ..< 60).map { "edge: n\($0) -> n\($0 + 1)" }.joined(separator: "\n")
        #expect(flow(chain) != nil)
        #expect(refusal(chain + "\nedge: n60 -> n61")?.contains("60") == true)
    }

    // MARK: the PDF

    private func pdfWords(_ body: String) throws -> [PDFDocumentReader.Word] {
        let markdown = "```tile flow\n\(body)\n```\n"
        return try PDFDocumentReader(data: MarkdownPDFRenderer().render(markdown: markdown)).pages.flatMap(\.words)
    }

    @Test("the PDF prints the title and each node's text, in the order of the nodes, inside the page")
    func printed() throws {
        let words = try pdfWords("title: Build pipeline\nedge: parse -> build\nedge: build -> test\nnode: test\nlabel: Run tests\nstatus: running")
        #expect(words.map(\.text) == ["Build", "pipeline", "parse", "build", "Run", "tests"], Comment(rawValue: "\(words.map(\.text))"))
        #expect(words.allSatisfy { $0.width > 0 && $0.x >= 0 && $0.x + $0.width <= 595.28 })
    }

    @Test("the boxes are where the layout puts them, scaled by one factor to fit the page and no further")
    func boxesInThePDF() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "```tile flow\nedge: a -> b\nedge: b -> c\n```\n")
        let tokens = (String(data: data, encoding: .isoLatin1) ?? "").split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        // the picture is 564 wide: it fits a 487.28 point measure only when scaled
        let scale = 487.28 / 564
        let lefts = tokens.enumerated().compactMap { index, token -> Double? in
            guard token == "m", index >= 2, let x = Double(tokens[index - 2]) else { return nil }
            return x
        }
        // each rounded box starts its path at x + radius: a, b and c at layers 0, 1 and 2
        for layer in 0 ..< 3 {
            let expected = 54 + Double(12 + layer * 200) * scale + 8 * scale
            #expect(lefts.contains { abs($0 - expected) < 0.01 }, Comment(rawValue: "layer \(layer): \(expected) in \(lefts)"))
        }
    }

    @Test("a small graph is drawn at its own size, not stretched")
    func notStretched() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "```tile flow\nedge: a -> b\n```\n")
        let tokens = (String(data: data, encoding: .isoLatin1) ?? "").split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        let lefts = tokens.enumerated().compactMap { index, token -> Double? in
            guard token == "m", index >= 2, let x = Double(tokens[index - 2]) else { return nil }
            return x
        }
        // 364 wide fits 487.28: scale 1, so box b starts at 54 + 212 + 8
        #expect(lefts.contains { abs($0 - (54 + 212 + 8)) < 0.01 }, Comment(rawValue: "\(lefts)"))
    }

    @Test("a refused flow prints as a code block that says why")
    func refused() throws {
        let words = try pdfWords("edge: a -> b\nedge: b -> a").map(\.text)
        #expect(words.contains("Unsupported") && words.contains("cycle:"), Comment(rawValue: "\(words)"))
    }
}
