import Foundation
@testable import MarkdownPDF
import Testing

/// A flowchart node takes the shape its brackets name: `[ ]` a rectangle, `( )` a rounded rectangle, `([ ])` a stadium, `{ }` a decision diamond.
/// A shape the renderer does not draw (`(( ))`, `{{ }}`, `[[ ]]`, `[( )]`, `[/ /]`, `>` ) is reported by name, never drawn as a rectangle.
@Suite("Mermaid node shapes")
struct MermaidNodeShapeTests {
    private func nodes(_ body: String) -> [MermaidDiagram.Node]? {
        guard case let .diagram(diagram) = MermaidDiagram.parse("flowchart TD\n\(body)") else {
            return nil
        }
        return diagram.nodes
    }

    private func reason(_ body: String) -> String? {
        guard case let .unsupported(reason) = MermaidDiagram.parse("flowchart TD\n\(body)") else {
            return nil
        }
        return reason
    }

    @Test("each bracket pair names its shape and keeps its label", arguments: [
        ("A[Plain label]", MermaidDiagram.Node.Shape.rectangle, "Plain label"),
        ("A(Rounded label)", .rounded, "Rounded label"),
        ("A([Stadium label])", .stadium, "Stadium label"),
        ("A{Does it do diagrams?}", .diamond, "Does it do diagrams?"),
        ("A{\"Quoted --> label\"}", .diamond, "Quoted --> label"),
        ("A(\"Rounded (nested) label\")", .rounded, "Rounded (nested) label"),
    ])
    func shapes(source: String, shape: MermaidDiagram.Node.Shape, label: String) throws {
        let parsed = try #require(nodes(source), Comment(rawValue: "\(source) did not parse: \(reason(source) ?? "?")"))
        #expect(parsed.map(\.shape) == [shape])
        #expect(parsed.map(\.label) == [label])
    }

    @Test("shapes work at both ends of an edge and in a chain")
    func inEdges() throws {
        let parsed = try #require(nodes("Idea[I want a flow] --> Tool{Does it do diagrams?} -->|yes| Done([Ship it])\nTool -->|no| Fix(Fix it)"))
        #expect(parsed.map(\.id) == ["Idea", "Tool", "Done", "Fix"])
        #expect(parsed.map(\.shape) == [.rectangle, .diamond, .stadium, .rounded])
    }

    @Test("a shape the renderer does not draw is reported by its brackets", arguments: [
        ("A((Circle))", "(("), ("A{{Hexagon}}", "{{"), ("A[[Subroutine]]", "[["), ("A[(Database)]", "[("), ("A[/Slanted/]", "[/"), ("A>Flag]", ">"),
    ])
    func unsupported(source: String, brackets: String) throws {
        let message = try #require(reason(source), Comment(rawValue: "\(source) parsed, but it must be reported"))
        #expect(message.contains("`\(brackets)"), Comment(rawValue: message))
        #expect(message.contains("not supported"), Comment(rawValue: message))
    }

    @Test("the diamond's outline is the four side midpoints of its box, in closed form")
    func outline() {
        let points = MermaidDiagram.Node.Shape.diamondOutline(left: 10, bottom: 20, width: 100, height: 60)
        #expect(points.map(\.x) == [60, 110, 60, 10])
        #expect(points.map(\.y) == [80, 50, 20, 50])
    }

    @Test("a diamond is laid out larger than the text it holds, so its corners stay inside the outline")
    func diamondInflation() {
        let box = MermaidDiagram.Node.Shape.diamond.boxSize(forText: (width: 100, height: 30))
        // The text rectangle's corner (w/2, h/2) lies on or inside |x|/(W/2) + |y|/(H/2) = 1 exactly when w/W + h/H <= 1.
        #expect(100 / box.width + 30 / box.height <= 1.0 + 1e-9)
        #expect(MermaidDiagram.Node.Shape.rectangle.boxSize(forText: (width: 100, height: 30)) == (width: 100, height: 30))
    }

    @Test("a decision flowchart renders as a diagram, with its labels and no unsupported notice")
    func renders() throws {
        let markdown = "```mermaid\ngraph TD\n  Idea[I want to explain a flow] --> Tool{Does my generator do diagrams?}\n  Tool -->|no| Fix(Fix it)\n  Tool -->|yes| Done([Ship it])\n```\n"
        let words = try PDFDocumentReader(data: MarkdownPDFRenderer().render(markdown: markdown)).pages.flatMap(\.words).map(\.text)
        #expect(!words.contains("Unsupported"), Comment(rawValue: "\(words)"))
        #expect(words.contains("generator") && words.contains("diagrams?") && words.contains("Ship") && words.contains("Fix"), Comment(rawValue: "\(words)"))
    }
}
