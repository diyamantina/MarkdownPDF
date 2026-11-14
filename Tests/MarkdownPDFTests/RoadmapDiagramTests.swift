import Foundation
import Testing

/// The roadmap diagram gate, run on the README of this repository, and the gate
/// itself held to diagrams with one known fault each.
@Suite("Roadmap diagrams")
struct RoadmapDiagramTests {
    private static func readme() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("README.md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static let palette = """
        classDef done fill:#e8f5e9,stroke:#2e7d32,color:#111;
        classDef active fill:#e3f2fd,stroke:#1565c0,color:#111;
    """

    private static func block(_ body: String) -> String {
        "flowchart TD\n\(body)\n\(palette)\n"
    }

    // MARK: The gate

    @Test("Every README diagram is vertical, defined, classed and within the legend, and the legend comes first")
    func readmeDiagramsAreValid() throws {
        let blocks = try RoadmapDiagram.blocks(in: Self.readme())
        try #require(!blocks.isEmpty, "roadmap: no mermaid diagrams found in README")

        for (index, block) in blocks.enumerated() {
            let issues = try RoadmapDiagram.issues(inBlock: block)
            #expect(issues.isEmpty, "roadmap: [diagram \(index)] \(issues.joined(separator: "; "))")
        }
        let firstIsLegend = try RoadmapDiagram.declaresPalette(blocks[0])
        #expect(firstIsLegend, "roadmap: first mermaid block is not the shared legend (no classDef palette)")
    }

    @Test("Every open epic appears in a README diagram")
    func openEpicsAppearInADiagram() async throws {
        let sections = try RoadmapDiagram.mermaidSections(in: Self.readme())
        switch await RoadmapDiagram.openEpics() {
        case let .skipped(why):
            // The forge cannot be reached: the gate stays usable offline.
            print("roadmap: SKIP epic coverage (\(why))")
        case let .numbers(epics):
            var missing: [Int] = []
            for epic in epics {
                let appears = try RoadmapDiagram.epic(epic, appearsIn: sections)
                if !appears, let number = Int(epic) {
                    missing.append(number)
                }
            }
            #expect(
                missing.isEmpty,
                "roadmap: epics with NO diagram: \(missing.sorted().map { "#\($0)" }). Rule: git-discipline Rule 1.8",
            )
            if missing.isEmpty {
                print("roadmap: all \(epics.count) open epics appear in a diagram")
            }
        }
    }

    // MARK: The gate against known faults

    @Test("A sound diagram has no issues")
    func soundBlock() throws {
        let block = Self.block("    A[\"First\"] --> B[\"Second\"]\n    B[\"Second\"]\n    C(\"Third\"):::active\n    class A,B done;")
        #expect(try RoadmapDiagram.issues(inBlock: block) == [])
    }

    @Test("A diagram that is not top down is reported, with the direction it has")
    func notVertical() throws {
        let sideways = "flowchart LR\n    A[\"One\"]\n\(Self.palette)\n    class A done;\n"
        #expect(try RoadmapDiagram.issues(inBlock: sideways) == ["not vertical (got 'flowchart LR')"])
        let none = "    A[\"One\"]\n\(Self.palette)\n    class A done;\n"
        #expect(try RoadmapDiagram.issues(inBlock: none) == ["not vertical (got 'no flowchart line')"])
    }

    @Test("A node an edge refers to and nothing defines is reported")
    func undefinedEdgeNode() throws {
        let block = Self.block("    A[\"One\"]\n    A --> Ghost\n    class A done;")
        #expect(try RoadmapDiagram.issues(inBlock: block) == ["edge nodes not defined: [\"Ghost\"]"])
    }

    @Test("A node with no class is reported")
    func unclassedNode() throws {
        let block = Self.block("    A[\"One\"]\n    B[\"Two\"]\n    class A done;")
        #expect(try RoadmapDiagram.issues(inBlock: block) == ["nodes with no class: [\"B\"]"])
    }

    @Test("A class the diagram does not declare is reported")
    func undeclaredClass() throws {
        let block = Self.block("    A[\"One\"]\n    class A review;")
        #expect(try RoadmapDiagram.issues(inBlock: block) == ["class not in classDef: [\"A: review\"]"])
    }

    @Test("A classDef outside the legend palette is reported")
    func classOutsideLegend() throws {
        let block = Self.block("    A[\"One\"]\n    classDef urgent fill:#f00;\n    class A urgent;")
        #expect(try RoadmapDiagram.issues(inBlock: block) == ["classDef outside legend palette: [\"urgent\"]"])
    }

    @Test("The legend is the block that declares the palette")
    func legendDetection() throws {
        let withPalette = try RoadmapDiagram.declaresPalette(Self.block("    A[\"One\"]"))
        let withoutDone = try RoadmapDiagram.declaresPalette("flowchart TD\n    A[\"One\"]\n    classDef active fill:#fff;\n")
        #expect(withPalette)
        #expect(!withoutDone)
    }

    @Test("Blocks and sections are cut out of a document where they are")
    func blocksAndSections() throws {
        let text = """
        # Title

        ## Legend

        ```mermaid
        flowchart TD
            L["Legend"]
        ```

        ## Prose only

        Epic #7 is mentioned here, outside any diagram section.

        ### A third level heading does not end a section

        ## Roadmap

        Epic #12 and [another](https://example.org/issues/34).

        ```mermaid
        flowchart TD
            R["Roadmap"]
        ```
        """
        #expect(try RoadmapDiagram.blocks(in: text) == ["flowchart TD\n    L[\"Legend\"]\n", "flowchart TD\n    R[\"Roadmap\"]\n"])
        let sections = try RoadmapDiagram.mermaidSections(in: text)
        #expect(sections.count == 2)
        #expect(sections.first?.hasPrefix("## Legend\n") == true)
        #expect(sections.last?.hasPrefix("## Roadmap\n") == true)

        // An epic counts when a section with a diagram names it, as #n or issues/n.
        // #12 does not stand for epic 1, and a mention outside a diagram section does not count.
        let found = try ["12", "34", "1", "7"].map { try RoadmapDiagram.epic($0, appearsIn: sections) }
        #expect(found == [true, true, false, false])
    }

    @Test("The answer of the issue API becomes epic numbers, and anything else a reason to skip")
    func epicAnswers() {
        let good = Data("[{\"number\": 131, \"title\": \"Math\"}, {\"number\": 49}]".utf8)
        #expect(RoadmapDiagram.epics(data: good, status: 200, error: nil) == .numbers(["131", "49"]))
        #expect(RoadmapDiagram.epics(data: Data("[]".utf8), status: 200, error: nil) == .numbers([]))

        #expect(RoadmapDiagram.epics(data: good, status: 503, error: nil) == .skipped("issue query failed: HTTP status 503"))
        #expect(RoadmapDiagram.epics(data: nil, status: nil, error: nil) == .skipped("issue query failed: HTTP status missing"))
        #expect(RoadmapDiagram.epics(data: Data("{\"message\": \"no\"}".utf8), status: 200, error: nil) == .skipped("issue query failed: the answer is not a list of issues"))
        #expect(RoadmapDiagram.epics(data: Data("[{\"title\": \"x\"}]".utf8), status: 200, error: nil) == .skipped("issue query failed: an issue has no number"))
        if case .numbers = RoadmapDiagram.epics(data: good, status: 200, error: CocoaError(.fileNoSuchFile)) {
            Issue.record("an error from the network must skip the check")
        }
    }
}
