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

    @Test("An unclosed bracket in a chain is reported with its line")
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
        arguments: ["A[item [1] --> B[x]", "A[\"open --> B", "A --> B[\"open --> C[y]"],
    )
    func unbalancedDelimitersAreReported(_ line: String) {
        guard case let .unsupported(reason) = MermaidDiagram.parse("flowchart TD\n    \(line)\n") else {
            Issue.record("Expected `\(line)` to be unsupported")
            return
        }
        #expect(reason.contains("unbalanced"))
    }

    @Test("A stray quote in an unquoted label is a plain character, however many there are")
    func strayQuotesInUnquotedLabelsArePlain() {
        let result = MermaidDiagram.parse("""
        flowchart TD
            A[5" x] --> B[6" y] --> C
            D --> E[5" disk]
        """)

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }

        #expect(diagram.nodes.map(\.id) == ["A", "B", "C", "D", "E"])
        #expect(diagram.nodes.map(\.label) == ["5\" x", "6\" y", "C", "D", "5\" disk"])
        #expect(diagram.edges.count == 3)
    }

    @Test("Hyphens in ids and arrows or dashes inside labels are text")
    func hyphensAndInnerArrowsAreText() {
        let result = MermaidDiagram.parse("""
        flowchart TD
            A-B --> C
            D[x - y] --> E[p --> q]
            F["a --- b"] --> G["c ==> d"]
            H[p --> q] --> I
        """)

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }

        #expect(diagram.nodes.map(\.id) == ["A-B", "C", "D", "E", "F", "G", "H", "I"])
        #expect(diagram.nodes.map(\.label)[6] == "p --> q")
        #expect(diagram.edges.count == 4)
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

    @Test("Thick links are still rejected, and the reason names the supported ones")
    func unsupportedLinkFormsAreStillRejected() {
        for line in ["A === B", "A ==> B"] {
            let result = MermaidDiagram.parse("flowchart TD\n    \(line)\n")
            guard case let .unsupported(reason) = result else {
                Issue.record("Expected `\(line)` to be unsupported")
                continue
            }
            #expect(reason.contains("`---`"))
            #expect(reason.contains("`~~~`"))
        }
    }

    @Test("A plain link joins two nodes without an arrowhead, dashed or not, and can carry a label")
    func parsesPlainLinks() {
        let result = MermaidDiagram.parse("""
        flowchart LR
            A --- B
            B ---|same| C -.- D
            D ----- E
            E ---> F
        """)

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }

        #expect(diagram.edges == [
            MermaidDiagram.Edge(source: "A", target: "B", label: nil, style: .line),
            MermaidDiagram.Edge(source: "B", target: "C", label: "same", style: .line),
            MermaidDiagram.Edge(source: "C", target: "D", label: nil, style: .dashedLine),
            MermaidDiagram.Edge(source: "D", target: "E", label: nil, style: .line),
            MermaidDiagram.Edge(source: "E", target: "F", label: nil, style: .arrow),
        ])
    }

    @Test("A plain link between ids written without spaces is still a link")
    func plainLinkWithoutSpaces() {
        let result = MermaidDiagram.parse("flowchart TD\n    a---b --> c\n")

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }

        #expect(diagram.nodes.map(\.id) == ["a", "b", "c"])
        #expect(diagram.edges.map(\.style) == [.line, .arrow])
    }

    @Test("An invisible link joins two nodes for layout only and has no label")
    func parsesInvisibleLinks() {
        let result = MermaidDiagram.parse("flowchart TD\n    A ~~~ B\n    B ~~~~ C\n")

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }

        #expect(diagram.edges.map(\.style) == [.hidden, .hidden])
        #expect(!MermaidDiagram.Edge(source: "A", target: "B", label: nil, style: .hidden).isDrawn)

        guard case let .unsupported(reason) = MermaidDiagram.parse("flowchart TD\n    A ~~~|x| B\n") else {
            Issue.record("Expected a labelled invisible link to be unsupported")
            return
        }
        #expect(reason.contains("invisible"))
    }

    @Test("A subgraph groups the nodes written inside it, with its title and direction")
    func parsesSubgraphs() {
        let result = MermaidDiagram.parse("""
        flowchart TB
            tick["ticks"] --> evaluate
            subgraph T["SwiftUI's thread"]
                direction LR
                evaluate["evaluates"] --> queue
            end
            subgraph R[The server]
                swap
            end
            subgraph Bare
                solo
            end
            T ~~~ R
        """)

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }

        #expect(diagram.nodes.map(\.id) == ["tick", "evaluate", "queue", "swap", "solo"])
        #expect(diagram.groups == [
            MermaidDiagram.Group(id: "T", title: "SwiftUI's thread", direction: .leftRight, members: ["evaluate", "queue"]),
            MermaidDiagram.Group(id: "R", title: "The server", direction: nil, members: ["swap"]),
            MermaidDiagram.Group(id: "Bare", title: "Bare", direction: nil, members: ["solo"]),
        ])
        // The group ids in the `~~~` line name groups, not nodes.
        #expect(diagram.edges == [
            MermaidDiagram.Edge(source: "tick", target: "evaluate", label: nil),
            MermaidDiagram.Edge(source: "evaluate", target: "queue", label: nil),
            MermaidDiagram.Edge(source: "T", target: "R", label: nil, style: .hidden),
        ])
    }

    @Test("A group can be named in a link before it is written")
    func groupNamedBeforeItIsWritten() {
        let result = MermaidDiagram.parse("""
        flowchart TB
            A ~~~ G
            subgraph G
                x
            end
        """)

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }

        #expect(diagram.nodes.map(\.id) == ["A", "x"])
        #expect(diagram.groups.map(\.id) == ["G"])
        #expect(diagram.edges == [MermaidDiagram.Edge(source: "A", target: "G", label: nil, style: .hidden)])
    }

    @Test("A title takes line breaks like a node label")
    func subgraphTitleLineBreaks() {
        let result = MermaidDiagram.parse("flowchart TD\n    subgraph S[\"one<br/>two\"]\n        a\n    end\n")

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }
        #expect(diagram.groups.first?.title == "one\ntwo")
    }

    @Test(
        "Subgraph misuse is reported with its line",
        arguments: [
            ("subgraph A\n subgraph B\n x\n end\n end", "nested"),
            ("subgraph A\n x", "not closed"),
            ("x\nend", "`end` without"),
            ("direction LR\nx", "inside a subgraph"),
            ("subgraph A\n direction XX\n x\n end", "direction"),
            ("subgraph A\n x\n end\nsubgraph B\n x\n end", "`x` is in more than one"),
            ("subgraph A\n end", "has no nodes"),
            ("subgraph A\n x\n end\nsubgraph A\n y\n end", "`A` is declared twice"),
            ("A[Label] --> x\nsubgraph A\n x\n end", "`A` is both"),
            ("subgraph A\n x --> A\n end", "`A` is both"),
            ("subgraph G\n a\n end\na --> G", "itself or its own node"),
            ("subgraph G\n a\n end\nG --> G", "itself or its own node"),
            ("subgraph G\n a\n end\nG ~~~ a", "itself or its own node"),
            ("subgraph\n x\n end", "needs an id"),
            ("subgraph A((B))\n x\n end", "subgraph"),
        ],
    )
    func subgraphMisuseIsReported(_ body: String, _ expected: String) {
        guard case let .unsupported(reason) = MermaidDiagram.parse("flowchart TD\n\(body)\n") else {
            Issue.record("Expected `\(body)` to be unsupported")
            return
        }
        #expect(reason.contains("line "), "\(reason)")
        #expect(reason.contains(expected), "\(reason)")
    }

    @Test("A node named like a keyword is still a node")
    func keywordLikeNodesAreNodes() {
        let result = MermaidDiagram.parse("""
        flowchart TD
            direction --> endpoint
            subgraphs --> End
            direction -->x
            subgraph ---> y
        """)

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }
        #expect(diagram.nodes.map(\.id) == ["direction", "endpoint", "subgraphs", "End", "x", "subgraph", "y"])
        #expect(diagram.groups.isEmpty)
    }

    @Test("Collapsing groups for layout maps each member to its group and drops inner edges")
    func collapsedDiagramForLayout() {
        let result = MermaidDiagram.parse("""
        flowchart TB
            subgraph U[UIKit]
                u1 --> u2
            end
            subgraph S[SwiftUI]
                s1 --> s2
            end
            u2 --> out
            out --> s1
            U ~~~ S
        """)

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }

        let collapsed = diagram.collapsedForLayout()
        #expect(collapsed.groups.isEmpty)
        #expect(collapsed.nodes.map(\.id) == ["U", "S", "out"])
        #expect(collapsed.nodes.map(\.label) == ["UIKit", "SwiftUI", "out"])
        #expect(collapsed.edges.map { "\($0.source)>\($0.target)" } == ["U>out", "out>S", "U>S"])
        #expect(collapsed.layers().map { $0.map(\.id) } == [["U"], ["out"], ["S"]])
    }

    @Test("The inside of a group is its own diagram with its own direction")
    func innerDiagramOfAGroup() {
        let result = MermaidDiagram.parse("""
        flowchart TB
            subgraph G
                direction LR
                a --> b --> c
            end
            subgraph H
                d --> e
            end
            c --> d
        """)

        guard case let .diagram(diagram) = result else {
            Issue.record("Expected supported Mermaid diagram")
            return
        }

        let inner = diagram.innerDiagram(of: diagram.groups[0])
        #expect(inner.direction == .leftRight)
        #expect(inner.nodes.map(\.id) == ["a", "b", "c"])
        #expect(inner.edges.count == 2)
        #expect(inner.layers().map { $0.map(\.id) } == [["a"], ["b"], ["c"]])

        // A group with no direction of its own takes the diagram's.
        #expect(diagram.innerDiagram(of: diagram.groups[1]).direction == .topBottom)
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
