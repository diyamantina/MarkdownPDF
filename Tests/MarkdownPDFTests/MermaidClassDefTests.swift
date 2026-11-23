import Foundation
@testable import MarkdownPDF
import Testing

/// Mermaid `classDef NAME fill:#rrggbb,stroke:#rrggbb,stroke-width:Npx,color:#rrggbb` and `class A,B NAME`: the colours of the author, drawn as given on
/// the nodes of the class. The diagrams are the shape of the three of the post "SwiftUI has no List": `flowchart TB`, nodes `A["..."]`, stadiums
/// `A(["..."])`, `<br/>` in labels. Everything the engine does not draw is REPORTED by name, never printed as source.
@Suite("Mermaid classDef and class")
struct MermaidClassDefTests {
    private static let diagram = """
    flowchart TB
      A["Your data changes"] --> B["SwiftUI works out<br/>the difference"]
      B --> C["Insert, delete or move:<br/>one call to the container"]
      B --> F(["Row kept its place:<br/>no reload at all"])
      classDef hot fill:#ffcc00,stroke:#cc0000,stroke-width:3px,color:#003366
      class B,F hot
    """

    private static func fenced(_ body: String) -> String {
        "```mermaid\n\(body)\n```\n"
    }

    private func nodes(_ source: String) throws -> [String: MermaidDiagram.Node] {
        guard case let .diagram(diagram) = MermaidDiagram.parse(source) else {
            Issue.record("the diagram is not supported: \(MermaidDiagram.parse(source))")
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: diagram.nodes.map { ($0.id, $0) })
    }

    @Test("the four properties are read onto the nodes of the class, and a node without the class has no style")
    func propertiesOnNodes() throws {
        let byID = try nodes(Self.diagram)
        for id in ["B", "F"] {
            let style = try #require(byID[id]?.style, "node \(id) has no style")
            #expect(style.fill == PDFColor(red: 1, green: 0.8, blue: 0))
            #expect(style.stroke == PDFColor(red: 0.8, green: 0, blue: 0))
            #expect(style.strokeWidth == 3)
            #expect(style.textColor == PDFColor(red: 0, green: 0.2, blue: 0.4))
        }
        #expect(byID["A"]?.style == nil && byID["C"]?.style == nil)
    }

    @Test("a short #rgb colour is read, and two classes on a node apply in order")
    func shortColourAndOrder() throws {
        let byID = try nodes("""
        flowchart TB
          A["x"] --> B["y"]
          classDef one fill:#f00,stroke:#000
          classDef two fill:#0f0
          class A one
          class A two
        """)
        let style = try #require(byID["A"]?.style)
        #expect(style.fill == PDFColor(red: 0, green: 1, blue: 0), "the later class wins the fill")
        #expect(style.stroke == PDFColor(red: 0, green: 0, blue: 0), "the earlier class keeps what the later one does not set")
    }

    @Test("the colours are drawn: the fill, the stroke colour, the stroke width and the text colour are in the page content")
    func drawn() throws {
        let pdf = try MarkdownPDFRenderer().render(markdown: Self.fenced(Self.diagram))
        let text = String(decoding: pdf, as: UTF8.self)
        #expect(text.contains("1 0.800 0 rg"), "the fill of the class is not in the content")
        #expect(text.contains("0.800 0 0 RG"), "the stroke colour of the class is not in the content")
        #expect(text.contains("2.250 w"), "the stroke width (3px, 0.75 point each) is not in the content")
        #expect(text.contains("0 0.200 0.400 rg"), "the text colour of the class is not in the content")
    }

    @Test("a node without a class is drawn as before: a class that no node takes changes nothing")
    func unclassedUnchanged() throws {
        let plain = "flowchart TB\n  A[\"a\"] --> B[\"b\"]\n  B --> C(\"c\")\n"
        let defined = plain + "  classDef unused fill:#ffcc00,stroke:#cc0000\n"
        let before = try MarkdownPDFRenderer().render(markdown: Self.fenced(plain))
        let after = try MarkdownPDFRenderer().render(markdown: Self.fenced(defined))
        #expect(before == after)
        #expect(!String(decoding: before, as: UTF8.self).contains("1 0.800 0 rg"))
    }

    @Test("an unknown property is reported by name and the diagram is still drawn, never printed as source")
    func unknownProperty() throws {
        let source = Self.fenced("""
        flowchart TB
          A["First node"] --> B["Second node"]
          classDef hot fill:#ffcc00,font-weight:bold,stroke-dasharray:5
          class A hot
        """)
        let output = try MarkdownPDFRenderer().renderWithReport(markdown: source)
        let names = output.report.diagramNotes.filter { $0.kind == .unknownProperty }.map(\.name)
        #expect(names == ["font-weight", "stroke-dasharray"], Comment(rawValue: "\(output.report.diagramNotes)"))
        let words = try PDFDocumentReader(data: output.data).pages.flatMap(\.words).map(\.text)
        #expect(words.contains("First") && words.contains("Second"), Comment(rawValue: "\(words)"))
        #expect(!words.contains("Unsupported") && !words.contains("classDef"), Comment(rawValue: "\(words)"))
        #expect(String(decoding: output.data, as: UTF8.self).contains("1 0.800 0 rg"), "the properties that are known are still drawn")
    }

    @Test("a class line naming an undefined class, and one naming an undefined node, are reported by name")
    func undefinedNames() throws {
        let source = Self.fenced("""
        flowchart TB
          A["First"] --> B["Second"]
          classDef hot fill:#ffcc00
          class A missing
          class A,Z hot
        """)
        let output = try MarkdownPDFRenderer().renderWithReport(markdown: source)
        let notes = output.report.diagramNotes
        #expect(notes.contains { $0.kind == .undefinedClass && $0.name == "missing" }, Comment(rawValue: "\(notes)"))
        #expect(notes.contains { $0.kind == .undefinedNode && $0.name == "Z" }, Comment(rawValue: "\(notes)"))
        #expect(String(decoding: output.data, as: UTF8.self).contains("1 0.800 0 rg"), "A still takes the class it names correctly")
    }

    @Test("an invalid colour is reported by name and the property is not applied")
    func invalidColour() throws {
        let source = Self.fenced("flowchart TB\n  A[\"First\"] --> B[\"Second\"]\n  classDef hot fill:notacolour\n  class A hot\n")
        let output = try MarkdownPDFRenderer().renderWithReport(markdown: source)
        #expect(output.report.diagramNotes.contains { $0.kind == .invalidValue && $0.name == "fill" }, Comment(rawValue: "\(output.report.diagramNotes)"))
    }

    @Test("a text colour below the contrast ratio of 4.5 on its fill is reported, and the colours are not changed")
    func lowContrast() throws {
        let source = Self.fenced("""
        flowchart TB
          A["Pale"] --> B["Dark"]
          classDef pale fill:#ffff00,color:#ffffcc
          classDef good fill:#003366,color:#ffffff
          class A pale
          class B good
        """)
        let output = try MarkdownPDFRenderer().renderWithReport(markdown: source)
        let low = output.report.diagramNotes.filter { $0.kind == .lowContrast }
        #expect(low.map(\.name) == ["A"], Comment(rawValue: "\(output.report.diagramNotes)"))
        let text = String(decoding: output.data, as: UTF8.self)
        #expect(text.contains("1 1 0 rg") && text.contains("1 1 0.800 rg"), "the author's colours are drawn as given")
    }

    @Test("the strict mode throws on a note, naming it")
    func strictMode() throws {
        let source = Self.fenced("flowchart TB\n  A[\"x\"] --> B[\"y\"]\n  classDef hot font-weight:bold\n  class A hot\n")
        var options = PDFOptions()
        options.undrawnCharacters = .fail
        #expect {
            try MarkdownPDFRenderer(options: options).render(markdown: source)
        } throws: { error in
            (error as? LocalizedError)?.errorDescription?.contains("font-weight") == true
        }
    }
}
