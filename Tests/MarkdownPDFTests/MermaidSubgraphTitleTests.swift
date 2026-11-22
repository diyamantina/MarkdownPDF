import Foundation
@testable import MarkdownPDF
import Testing

/// A `subgraph` header may be a bare title of several words (`subgraph After 1.6.5`), as Mermaid allows: the title is the whole text.
/// The forms with an id (`subgraph id["Title"]`, `subgraph id`) are unchanged.
@Suite("Mermaid subgraph titles")
struct MermaidSubgraphTitleTests {
    private func titles(_ header: String) -> [String]? {
        let source = "flowchart TB\n  subgraph \(header)\n    A[One] --> B[Two]\n  end"
        guard case let .diagram(diagram) = MermaidDiagram.parse(source) else {
            return nil
        }
        return diagram.groups.map(\.title)
    }

    @Test("the title of a subgraph is what the header says", arguments: [
        ("After 1.6.5", "After 1.6.5"),
        ("The   hinge  ", "The hinge"),
        ("Before", "Before"),
        ("L[\"Layout\"]", "Layout"),
        ("id[Plain title]", "Plain title"),
    ])
    func title(header: String, expected: String) throws {
        let found = try #require(titles(header), Comment(rawValue: "subgraph \(header) did not parse"))
        #expect(found == [expected])
    }

    @Test("a header with a shape this renderer does not draw is still refused by name")
    func refused() {
        guard case let .unsupported(reason) = MermaidDiagram.parse("flowchart TB\n  subgraph G((Circle))\n    A --> B\n  end") else {
            Issue.record("a circle header must be reported")
            return
        }
        #expect(reason.contains("(("), Comment(rawValue: reason))
    }
}
