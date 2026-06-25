@testable import MarkdownPDF
import Testing

@Suite("Mermaid PDF rendering")
struct MermaidRenderTests {
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
