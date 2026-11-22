import Foundation
@testable import MarkdownPDF
import Testing

/// A left-to-right diagram whose columns cannot fit the page width even at the smallest scale is drawn top to bottom instead, not given up as source:
/// a person redrawing a ten-step pipeline for a page would turn it, and every node and edge label stays. A diagram that fits is not turned.
@Suite("A diagram too wide for the page is turned top to bottom")
struct MermaidWideDiagramTests {
    private func words(_ markdown: String) throws -> [PDFDocumentReader.Word] {
        try PDFDocumentReader(data: MarkdownPDFRenderer().render(markdown: markdown)).pages.flatMap(\.words)
    }

    private static let pipeline = """
    ```mermaid
    flowchart LR
      f1["Fetch<br/>crawl-frameworks"] --> f2["Produce<br/>enrichment inputs"] --> f3["Swift feature<br/>table"] --> f4["Save the docs<br/>database first"] --> f5["Save the<br/>other databases"]
      f5 --> f6["Audit<br/>version coverage"] --> f7["Oracles"] --> f8["Gates"] --> f9["Smoke"] --> f10["Publish"]
    ```
    """

    @Test("a ten-step left-to-right pipeline is drawn, every node once, with no unsupported notice")
    func wide() throws {
        let printed = try words(Self.pipeline)
        let text = printed.map(\.text)
        #expect(!text.contains("Unsupported"), Comment(rawValue: "\(text)"))
        for node in ["Fetch", "Produce", "Swift", "Save", "Audit", "Oracles", "Gates", "Smoke", "Publish"] {
            #expect(text.contains(node), Comment(rawValue: "\(node) is missing: \(text)"))
        }
        // Drawn as a diagram, the source line `flowchart LR` is not printed as a code block.
        #expect(!text.contains("flowchart"), Comment(rawValue: "the diagram was given up as source: \(text)"))
    }

    @Test("the nodes of the turned diagram stand in one column, top to bottom in pipeline order")
    func turned() throws {
        let printed = try words(Self.pipeline)
        let fetch = try #require(printed.first { $0.text == "Fetch" })
        let publish = try #require(printed.first { $0.text == "Publish" })
        #expect(fetch.y > publish.y, "the first step is above the last")
        // A left-to-right ten-step row would put the last step far to the right of the first.
        #expect(abs(publish.x - fetch.x) < 120, Comment(rawValue: "first at x=\(fetch.x), last at x=\(publish.x): not one column"))
    }

    @Test("a short left-to-right diagram that fits keeps its direction")
    func fits() throws {
        let printed = try words("```mermaid\nflowchart LR\n  A[Start] --> B[Middle] --> C[End]\n```\n")
        let start = try #require(printed.first { $0.text == "Start" })
        let end = try #require(printed.first { $0.text == "End" })
        #expect(end.x > start.x + 100, "left to right: the end is to the right of the start")
        #expect(abs(end.y - start.y) < 1, "in one row")
    }
}
