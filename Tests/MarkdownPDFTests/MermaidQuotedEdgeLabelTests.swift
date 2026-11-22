import Foundation
@testable import MarkdownPDF
import Testing

/// A link label may be quoted, `A -->|"text"| B`, as a node label may: the quotes are not part of the text, and a quoted label can hold the
/// characters that end an unquoted one (`|`) or look like a link (`-->`). An unquoted label is unchanged.
@Suite("Mermaid quoted edge labels")
struct MermaidQuotedEdgeLabelTests {
    private func labels(_ body: String) -> [String?]? {
        guard case let .diagram(diagram) = MermaidDiagram.parse("flowchart LR\n\(body)") else {
            return nil
        }
        return diagram.edges.map(\.label)
    }

    @Test("the quotes are not part of the label", arguments: [
        ("A -->|\"shows the path\"| B", "shows the path"),
        ("A -.->|\"two<br/>lines\"| B", "two lines"),
        ("A -->|\"yes | no\"| B", "yes | no"),
        ("A -->|\"a --> b\"| B", "a --> b"),
        ("A -->|plain text| B", "plain text"),
        ("A -->|\"\"| B", nil),
    ])
    func unquoted(source: String, expected: String?) throws {
        let found = try #require(labels(source), Comment(rawValue: "\(source) did not parse"))
        #expect(found == [expected])
    }

    @Test("a quoted label in a chain keeps its own edge")
    func chain() throws {
        let found = try #require(labels("A -->|\"first | one\"| B -.->|second| C"))
        #expect(found == ["first | one", "second"])
    }

    @Test("a quote that is not closed is reported")
    func unclosed() {
        guard case let .unsupported(reason) = MermaidDiagram.parse("flowchart LR\nA -->|\"never closed| B") else {
            Issue.record("an unclosed quote must be reported")
            return
        }
        #expect(reason.contains("`|`") || reason.contains("quote"), Comment(rawValue: reason))
    }
}
