import Foundation
@testable import MarkdownPDF
import Testing

/// In a chart with two series the swatch of the second sits to the left of its name, in the space between the two names. The space must be wide enough for
/// the swatch and its gaps: the swatch of "SwiftUI List" must not paint over the end of "NSTableView fed by hand". The chart is the one of the post
/// "SwiftUI has no List".
@Suite("A chart legend's swatch stays clear of the name before it")
struct ChartLegendSwatchTests {
    private static let chart = """
    ```chart
    type: bar
    title: What the feed costs at 100,000 rows
    x-label: Operation
    y-label: Milliseconds
    categories: Append 50 rows, Update one row
    series: NSTableView fed by hand = 0.67, 0.53
    series: SwiftUI List = 18.1, 17.3
    ```
    """

    @Test("the second swatch starts after the end of the first name, with a gap")
    func swatchClearOfPreviousName() throws {
        let pdf = try MarkdownPDFRenderer().render(markdown: Self.chart)
        let words = try PDFDocumentReader(data: pdf).pages.flatMap(\.words)
        let last = try #require(words.first { $0.text == "hand" }, "the legend's first name is not in the text")
        let nameEnd = last.x + last.width
        let text = String(decoding: pdf, as: UTF8.self)
        let expression = try NSRegularExpression(pattern: #"(-?[0-9.]+) (-?[0-9.]+) 10 8 re"#)
        let range = NSRange(text.startIndex..., in: text)
        let swatches = expression.matches(in: text, range: range).compactMap { match -> Double? in
            Range(match.range(at: 1), in: text).flatMap { Double(text[$0]) }
        }
        #expect(swatches.count == 2, Comment(rawValue: "\(swatches.count) legend swatches"))
        let second = try #require(swatches.max())
        #expect(second >= nameEnd + 2, Comment(rawValue: "the second swatch starts at \(second), the first name ends at \(nameEnd)"))
    }
}
