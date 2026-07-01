@testable import MarkdownPDF
import Testing

@Suite("Mermaid diagram")
struct MermaidDiagramTests {
    @Test("Parses supported flowchart nodes and edges")
    func parsesSupportedFlowchartNodesAndEdges() {
        let result = MermaidDiagram.parse("""
        flowchart TD
            Input[Markdown source] --> Parse[Block parser]
            Parse --> Layout[Article layout]
            Layout --> PDF[PDF bytes]
        """)

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }

        #expect(diagram.direction == .topBottom)
        #expect(diagram.nodes.map(\.id) == ["Input", "Parse", "Layout", "PDF"])
        #expect(diagram.nodes.map(\.label) == ["Markdown source", "Block parser", "Article layout", "PDF bytes"])
        #expect(diagram.edges == [
            MermaidDiagram.Edge(source: "Input", target: "Parse", label: nil),
            MermaidDiagram.Edge(source: "Parse", target: "Layout", label: nil),
            MermaidDiagram.Edge(source: "Layout", target: "PDF", label: nil),
        ])
        #expect(diagram.layers().map { $0.map(\.id) } == [["Input"], ["Parse"], ["Layout"], ["PDF"]])
    }

    @Test("Parses dashed edges, plain and labeled")
    func parsesDashedEdges() {
        let result = MermaidDiagram.parse("""
        flowchart TD
            A[Source] -.-> B[Target]
            B -.->|feedback| A
        """)

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }

        #expect(diagram.edges == [
            MermaidDiagram.Edge(source: "A", target: "B", label: nil, dashed: true),
            MermaidDiagram.Edge(source: "B", target: "A", label: "feedback", dashed: true),
        ])
    }

    @Test("Lays out cyclic flowcharts by breaking back-edges instead of failing")
    func laysOutCycles() {
        let result = MermaidDiagram.parse("""
        flowchart TD
            A[First] --> B[Second]
            B --> A
        """)

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }

        let layers = diagram.layers()
        #expect(layers.flatMap { $0.map(\.id) }.sorted() == ["A", "B"])
        #expect(layers.allSatisfy { !$0.isEmpty })
    }

    @Test("Parses graph aliases, quoted labels, and edge labels")
    func parsesGraphAliasesQuotedLabelsAndEdgeLabels() {
        let result = MermaidDiagram.parse("""
        graph LR
            A["Input Markdown"] -->|parse| B["PDF bytes"];
        """)

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid graph")
            return
        }

        #expect(diagram.direction == .leftRight)
        #expect(diagram.nodes.map(\.label) == ["Input Markdown", "PDF bytes"])
        #expect(diagram.edges == [
            MermaidDiagram.Edge(source: "A", target: "B", label: "parse"),
        ])
    }

    @Test("Reports unsupported Mermaid syntax")
    func reportsUnsupportedMermaidSyntax() {
        let result = MermaidDiagram.parse("""
        sequenceDiagram
            Alice->>Bob: Hello
        """)

        guard case let .unsupported(reason) = result else {
            Issue.record("Expected unsupported Mermaid syntax")
            return
        }

        #expect(reason.contains("expected `flowchart TD` or `graph TD`"))
    }

    @Test("Reports Mermaid chart syntax as unsupported")
    func reportsMermaidChartSyntaxAsUnsupported() {
        let result = MermaidDiagram.parse("""
        pie title Unsupported chart
            "Alpha" : 3
        """)

        guard case let .unsupported(reason) = result else {
            Issue.record("Expected unsupported Mermaid chart syntax")
            return
        }

        #expect(reason.contains("expected `flowchart TD` or `graph TD`"))
    }

    @Test("Rejects conflicting explicit node labels")
    func rejectsConflictingExplicitNodeLabels() {
        let result = MermaidDiagram.parse("""
        flowchart TD
            A[First] --> B[Second]
            A[Changed] --> B
        """)

        guard case let .unsupported(reason) = result else {
            Issue.record("Expected conflicting label rejection")
            return
        }

        #expect(reason.contains("node `A` has conflicting labels"))
    }
}
