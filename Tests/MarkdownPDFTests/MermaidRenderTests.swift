@testable import MarkdownPDF
import Testing

@Suite("Mermaid PDF rendering")
struct MermaidRenderTests {
    @Test("A figure separates itself from the next block", arguments: [
        """
        flowchart LR
            A[Apps] --> B[Features]
        """,
    ])
    func mermaidDiagramAddsTrailingSpacing(_ diagram: String) throws {
        try expectFigureTrailingSpacing(fenceInfo: "mermaid", body: diagram)
    }

    @Test("A native chart separates itself from the next block")
    func chartAddsTrailingSpacing() throws {
        try expectFigureTrailingSpacing(fenceInfo: "chart", body: """
        type: bar
        title: Revenue
        categories: Q1, Q2
        series: Actual = 3, 5
        """)
    }

    /// Both figure paths draw a frame, then advance `y`. Without
    /// `figureTrailingSpacing` the following paragraph's ascender lands on that
    /// frame, so assert the gap is the block model's spacing, not the bare 12pt
    /// figure padding.
    private func expectFigureTrailingSpacing(fenceInfo: String, body: String) throws {
        let fence = "```"
        let markdown = "Above.\n\n\(fence)\(fenceInfo)\n\(body)\n\(fence)\n\nBelow.\n"
        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        let lines = PDFInspector(data).text.split(separator: "\n")

        // The figure frame is the widest filled rectangle on the page.
        let frameBottom = try #require(
            lines.compactMap { line -> (bottom: Double, width: Double)? in
                let parts = line.split(separator: " ")
                guard parts.count == 6, parts[4] == "re", parts[5] == "f",
                      let y = Double(parts[1]), let w = Double(parts[2])
                else { return nil }
                return (y, w)
            }
            .max { $0.width < $1.width }?.bottom,
            "no figure frame drawn for \(fenceInfo)",
        )

        let belowBaseline = try #require(
            lines.first { $0.contains("(Below") }
                .flatMap { line -> Double? in
                    let parts = line.split(separator: " ")
                    return parts.count > 5 ? Double(parts[5]) : nil
                },
            "no paragraph after the \(fenceInfo) figure",
        )

        let paragraphSpacing = 11 * PDFOptions.Theme.default.style(for: .paragraph).spacingAfterMultiplier
        #expect(abs((frameBottom - belowBaseline) - (12 + paragraphSpacing)) < 0.01)
        #expect(frameBottom - belowBaseline > 12)
    }

    @Test("A dashed edge inside a cycle renders without falling back to source")
    func dashedEdgeAndCycleRender() throws {
        let markdown = """
        ```mermaid
        flowchart TD
            A[First] --> B[Second]
            B -.->|feedback| A
        ```
        """

        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        let inspector = PDFInspector(data)

        // Neither the dashed edge nor the cycle drops the diagram to its source.
        #expect(!inspector.text.contains("Unsupported"))
        #expect(!inspector.text.contains("flowchart TD"))
        #expect(inspector.hasValidXrefOffsets())
    }

    @Test("A wide horizontal flowchart is scaled to fit instead of falling back")
    func wideHorizontalFlowchartScalesToFit() throws {
        let markdown = """
        ```mermaid
        flowchart LR
            T["Destination state, your data"] --> Cp["Copy"]
            Cp --> Inj["Intermediate value injected"]
            Inj --> Rn["Copy is rendered"]
        ```
        """

        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        let inspector = PDFInspector(data)

        // Four wide nodes in a row exceed the content width; the engine shrinks the
        // diagram to fit rather than dropping it to source.
        #expect(!inspector.text.contains("Unsupported"))
        #expect(!inspector.text.contains("flowchart LR"))
        #expect(inspector.hasValidXrefOffsets())
    }
}
