import Foundation
@testable import MarkdownPDF
import Testing

/// The y-axis title of a chart sits above the plot, over the top gridline, never inside the plot where the first bar and the axis line run through it.
/// The plot's top gridline is the one the largest tick label ("10" here) is drawn beside, so the title's baseline must lie above that label's baseline,
/// and below the legend line above the plot.
@Suite("A chart's y-axis title is above the plot")
struct ChartAxisTitleTests {
    private static let chart = """
    ```chart
    type: bar
    title: What it made hard
    y-label: pain (made up units)
    categories: A, B, C
    series: Before = 8, 7, 10
    ```
    """

    private func words(_ markdown: String) throws -> [PDFDocumentReader.Word] {
        try PDFDocumentReader(data: MarkdownPDFRenderer().render(markdown: markdown)).pages.flatMap(\.words)
    }

    @Test("the title lies above the top tick's baseline and below the legend, and starts at the axis")
    func above() throws {
        let printed = try words(Self.chart)
        let title = try #require(printed.first { $0.text == "pain" })
        let topTick = try #require(printed.first { $0.text == "10" })
        let legend = try #require(printed.first { $0.text == "Before" })
        #expect(title.y > topTick.y + 3, Comment(rawValue: "title baseline \(title.y) is not above the top tick \(topTick.y): it is inside the plot"))
        #expect(title.y + title.fontSize * 0.75 < legend.y - legend.fontSize * 0.25, Comment(rawValue: "title \(title.y) runs into the legend \(legend.y)"))
        #expect(title.x >= topTick.x, Comment(rawValue: "title starts at \(title.x), left of the tick labels at \(topTick.x)"))
    }
}
