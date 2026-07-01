@testable import MarkdownPDF
import Testing

@Suite("Chart legend truncation")
struct ChartLegendTruncationTests {
    @Test("A long series label truncates in the legend instead of failing the chart")
    func longSeriesLabelTruncates() throws {
        let markdown = """
        ```chart
        type: line
        x: 1, 2, 3
        series: A very long descriptive series label that overflows the legend = 1, 2, 3
        ```
        """

        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        let inspector = PDFInspector(data)

        // The chart renders rather than falling back to its source.
        #expect(!inspector.text.contains("Unsupported chart"))
        #expect(!inspector.text.contains("too wide"))
        #expect(!inspector.text.contains("type: line"))
        #expect(inspector.hasValidXrefOffsets())
    }

    @Test("A short series label still renders unchanged")
    func shortSeriesLabelRenders() throws {
        let markdown = """
        ```chart
        type: line
        x: 1, 2, 3
        series: Actual = 1, 2, 3
        ```
        """

        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        let inspector = PDFInspector(data)
        #expect(!inspector.text.contains("Unsupported chart"))
        #expect(inspector.hasValidXrefOffsets())
    }
}
