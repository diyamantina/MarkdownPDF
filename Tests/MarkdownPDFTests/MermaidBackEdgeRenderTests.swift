import Foundation
@testable import MarkdownPDF
import Testing

/// A link that runs back over other nodes bends around them as an arc and its label sits clear of every node; a label wider than the gap
/// between two adjacent nodes lifts that link into an arc too. A diagram whose links have a free straight line is drawn with no curve at all.
@Suite("Mermaid back edges are routed around nodes")
struct MermaidBackEdgeRenderTests {
    private static let onegraph = """
    ```mermaid
    flowchart LR
      s["Your SwiftUI source"] --> g["Graph of values<br/>and parts"]
      g --> p["SwiftUI's picture"]
      p --> l["Core Animation layers"]
      l -.->|"OneGraph shows<br/>this whole path"| s
      r["A running app"] --> l2["Its real layers"]
      l2 -.->|"XRay Viewer<br/>starts here"| r
    ```
    """

    private func render(_ markdown: String) throws -> (words: [PDFDocumentReader.Word], content: String) {
        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        return try (PDFDocumentReader(data: data).pages.flatMap(\.words), PDFInspector(data).text)
    }

    /// The number of curve segments (the `c` operator) the page draws.
    private func curves(in content: String) -> Int {
        content.split(whereSeparator: \.isWhitespace).filter { $0 == "c" }.count
    }

    @Test("the diagram with two quoted back-edge labels is drawn, and the labels are printed without their quotes")
    func onegraph() throws {
        let text = try render(Self.onegraph).words.map(\.text)
        #expect(!text.contains("Unsupported"), Comment(rawValue: "\(text)"))
        #expect(text.contains("OneGraph") && text.contains("XRay"), Comment(rawValue: "\(text)"))
        #expect(!text.contains { $0.contains("\"") }, Comment(rawValue: "a quote is printed: \(text)"))
    }

    @Test("the back edge that runs over nodes is one arc: a curve, where a free link has none")
    func arcIsACurve() throws {
        let solid = Self.onegraph.replacingOccurrences(of: "-.->", with: "-->")
        #expect(try curves(in: render(solid).content) >= 1, "the back edge that runs over nodes is drawn as an arc")
    }

    @Test("an edge label's words overlap no node's words")
    func labelsClear() throws {
        let words = try render(Self.onegraph).words
        // Node text is the base size 0.88 of 11 pt = 9.68; an edge label is 0.72 of 11 pt = 7.92.
        let labels = words.filter { $0.fontSize < 9 }
        let nodes = words.filter { $0.fontSize >= 9 }
        #expect(!labels.isEmpty && !nodes.isEmpty)
        for label in labels {
            for node in nodes {
                let overlapsHorizontally = label.x < node.x + node.width && node.x < label.x + label.width
                let overlapsVertically = label.y - 0.25 * label.fontSize < node.y + 0.75 * node.fontSize
                    && node.y - 0.25 * node.fontSize < label.y + 0.75 * label.fontSize
                #expect(!(overlapsHorizontally && overlapsVertically), Comment(rawValue: "\(label.text) overlaps \(node.text)"))
            }
        }
    }

    @Test("a label wider than the gap between two neighbours is lifted clear of both")
    func wideLabelBetweenNeighbours() throws {
        let (words, content) = try render("```mermaid\nflowchart LR\n  a[Left] -->|a rather long label for a short gap| b[Right]\n```\n")
        #expect(!words.map(\.text).contains("Unsupported"))
        let label = try #require(words.first { $0.text == "rather" })
        let left = try #require(words.first { $0.text == "Left" })
        #expect(label.y > left.y + 0.75 * left.fontSize, Comment(rawValue: "the label (\(label.y)) is not above the nodes' text (\(left.y))"))
        #expect(curves(in: content) >= 1)
    }

    @Test("a diagram whose links are free draws no curve")
    func noCurves() throws {
        let (_, content) = try render("```mermaid\nflowchart LR\n  A[Start] -->|go| B[Middle] --> C[End]\n```\n")
        #expect(curves(in: content) == 0)
    }
}
