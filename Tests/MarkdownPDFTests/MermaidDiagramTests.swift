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

    @Test("Parses a chain of edges on one line as one edge for each pair")
    func parsesEdgeChains() {
        let result = MermaidDiagram.parse("""
        flowchart LR
            g["runAnimationGroup<br/>duration 0.5"] --> a["view.animator()<br/>.alphaValue = 0.2"] --> r["the view animates<br/>instead of popping"]
        """)

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }

        #expect(diagram.nodes.map(\.id) == ["g", "a", "r"])
        #expect(diagram.nodes.map(\.label) == [
            "runAnimationGroup\nduration 0.5",
            "view.animator()\n.alphaValue = 0.2",
            "the view animates\ninstead of popping",
        ])
        #expect(diagram.edges == [
            MermaidDiagram.Edge(source: "g", target: "a", label: nil),
            MermaidDiagram.Edge(source: "a", target: "r", label: nil),
        ])
    }

    @Test("A chain keeps each edge's own label and dash")
    func parsesChainWithLabelsAndDashes() {
        let result = MermaidDiagram.parse("""
        flowchart TD
            A -->|first| B -.->|second| C --> D
        """)

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }

        #expect(diagram.nodes.map(\.id) == ["A", "B", "C", "D"])
        #expect(diagram.edges == [
            MermaidDiagram.Edge(source: "A", target: "B", label: "first"),
            MermaidDiagram.Edge(source: "B", target: "C", label: "second", dashed: true),
            MermaidDiagram.Edge(source: "C", target: "D", label: nil),
        ])
    }

    @Test("An arrow inside a quoted label is text, not an edge")
    func arrowInsideQuotedLabelIsText() {
        let result = MermaidDiagram.parse("""
        flowchart LR
            A["a --> b"] --> B["c -.-> d"]
        """)

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }

        #expect(diagram.nodes.map(\.label) == ["a --> b", "c -.-> d"])
        #expect(diagram.edges == [MermaidDiagram.Edge(source: "A", target: "B", label: nil)])
    }

    @Test("A chain with a bad endpoint is reported with its line and the role of the endpoint")
    func chainWithBadEndpointIsReported() {
        let result = MermaidDiagram.parse("""
        flowchart TD
            A --> B[unterminated --> C
        """)

        guard case let .unsupported(reason) = result else {
            Issue.record("Expected an unsupported chain")
            return
        }

        #expect(reason.contains("line 2"))
        #expect(reason.contains("unbalanced"))
    }

    @Test("A bad first endpoint is reported as the source, a bad later one as a target")
    func badEndpointsNameTheirRole() {
        func reason(_ line: String) -> String? {
            guard case let .unsupported(reason) = MermaidDiagram.parse("flowchart TD\n    \(line)\n") else {
                return nil
            }
            return reason
        }

        #expect(reason("A B --> C")?.contains("invalid edge source") == true)
        #expect(reason("A --> B C")?.contains("invalid edge target") == true)
        #expect(reason("A --> B --> C D")?.contains("invalid edge target") == true)
    }

    @Test(
        "An unclosed quote or bracket before an arrow is reported, never read as one label",
        arguments: ["A[5\" disk] --> B[ok]", "A[item [1] --> B[x]", "A --> B[5\" x] --> C[y]"],
    )
    func unbalancedDelimitersAreReported(_ line: String) {
        guard case let .unsupported(reason) = MermaidDiagram.parse("flowchart TD\n    \(line)\n") else {
            Issue.record("Expected `\(line)` to be unsupported")
            return
        }
        #expect(reason.contains("unbalanced"))
    }

    @Test("Hyphens in ids and arrows or dashes inside labels are text")
    func hyphensAndInnerArrowsAreText() {
        let result = MermaidDiagram.parse("""
        flowchart TD
            A-B --> C
            D[x - y] --> E[p --> q]
            F["a --- b"] --> G["c ==> d"]
        """)

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }

        #expect(diagram.nodes.map(\.id) == ["A-B", "C", "D", "E", "F", "G"])
        #expect(diagram.nodes.map(\.label) == ["A-B", "C", "x - y", "p --> q", "a --- b", "c ==> d"])
        #expect(diagram.edges.count == 3)
    }

    @Test("Only a real line break tag is replaced")
    func onlyRealLineBreakTagsAreReplaced() {
        let result = MermaidDiagram.parse("""
        flowchart TD
            A["x<brx>y"] --> B["a < b<b>c"]
            B --> C["<br/>"]
        """)

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }

        // A label that is only a line break falls back to the id.
        #expect(diagram.nodes.map(\.label) == ["x<brx>y", "a < b<b>c", "C"])
    }

    @Test("Spaces around a label and runs of spaces in an edge label are normalised")
    func labelWhitespaceIsNormalised() {
        let result = MermaidDiagram.parse("""
        flowchart TD
            A["  padded  "] --> B
            A -->|a   b| B
        """)

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }

        #expect(diagram.nodes.first?.label == "padded")
        #expect(diagram.edges.last?.label == "a b")
    }

    @Test("Line breaks in labels become newlines, in every spelling")
    func lineBreaksInLabelsBecomeNewlines() {
        let result = MermaidDiagram.parse("""
        flowchart TD
            A["one<br/>two"] --> B["one<br>two"]
            B --> C["one<br />two<BR/>three"]
        """)

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }

        #expect(diagram.nodes.map(\.label) == ["one\ntwo", "one\ntwo", "one\ntwo\nthree"])
    }

    @Test("A line break in an edge label is a space")
    func lineBreakInEdgeLabelIsASpace() {
        let result = MermaidDiagram.parse("""
        flowchart TD
            A -->|one<br/>two| B
        """)

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }

        #expect(diagram.edges == [MermaidDiagram.Edge(source: "A", target: "B", label: "one two")])
    }

    @Test("Solid and dashed edges still reject the thick and plain link forms")
    func unsupportedLinkFormsAreStillRejected() {
        for line in ["A === B", "A ==> B", "A --- B"] {
            let result = MermaidDiagram.parse("flowchart TD\n    \(line)\n")
            guard case .unsupported = result else {
                Issue.record("Expected `\(line)` to be unsupported")
                continue
            }
        }
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
