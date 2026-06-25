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
}
