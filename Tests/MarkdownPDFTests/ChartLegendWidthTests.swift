import Foundation
@testable import MarkdownPDF
import Testing

/// The legend of a pie and of a doughnut draws each entry as `label value`. The legend column was sized from the labels alone, so a long label plus its
/// number ran past the chart box and the right margin (found in the final rebuild of the site: the doughnut of cupertino-v1-6-5 and the pie of
/// diagrams-in-markdown). The closed form: every word of a legend entry ends inside the content width, that is at or left of
/// `pageWidth - rightMargin`; the engine's advances come from the reader's `Word.width`, which is the AFM measurement the engine itself wrote.
@Suite("A pie or doughnut legend stays inside the content width")
struct ChartLegendWidthTests {
    private let rightEdge = PDFOptions.PageSize.a4.width - PDFOptions.Margins.standard.right

    private func words(_ markdown: String) throws -> [PDFDocumentReader.Word] {
        try PDFDocumentReader(data: MarkdownPDFRenderer().render(markdown: markdown)).pages.flatMap(\.words)
    }

    private func chart(_ kind: String, _ slices: [(String, Int)]) -> String {
        "```chart\ntype: \(kind)\ntitle: Share\n" + slices.map { "slice: \($0.0) = \($0.1)" }.joined(separator: "\n") + "\n```"
    }

    /// The words of the legend: those right of the plot, in the legend's column (x beyond 300 points), below the title.
    private func legendWords(_ markdown: String) throws -> [PDFDocumentReader.Word] {
        try words(markdown).filter { $0.x > 300 && $0.text != "Share" }
    }

    @Test("the pie of diagrams-in-markdown: a long label and its number end inside the content width")
    func pie() throws {
        let legend = try legendWords(chart("pie", [("Configuring the new generator", 45), ("Arguing about it online", 35), ("Actually writing posts", 20)]))
        #expect(legend.contains { $0.text == "45" }, "the legend was not found: \(legend.map(\.text))")
        // The column is wide enough for the whole entry (about 141 points of the 150 cap): nothing is shortened.
        #expect(!legend.contains { $0.text.hasSuffix("\u{2026}") }, "a label that fits was shortened: \(legend.map(\.text))")
        for word in legend {
            #expect(word.x + word.width <= rightEdge + 0.001, "\(word.text) ends at \(word.x + word.width), past \(rightEdge)")
        }
    }

    @Test("the doughnut of cupertino-v1-6-5: the same")
    func doughnut() throws {
        let legend = try legendWords(chart("doughnut", [("Tutorials and articles", 178), ("Series listings", 6), ("Mac Catalyst tutorials", 9)]))
        #expect(legend.contains { $0.text == "178" }, "\(legend.map(\.text))")
        for word in legend {
            #expect(word.x + word.width <= rightEdge + 0.001, "\(word.text) ends at \(word.x + word.width), past \(rightEdge)")
        }
    }

    @Test("a label too long for the column is shortened with an ellipsis and its number is kept")
    func longLabelKeepsItsNumber() throws {
        let long = "A label that is far too long to fit in the legend column of any pie chart at all"
        let legend = try legendWords(chart("pie", [(long, 1234), ("Short", 2)]))
        #expect(legend.contains { $0.text == "1234" }, "the number was cut: \(legend.map(\.text))")
        #expect(legend.contains { $0.text.hasSuffix("\u{2026}") }, "no ellipsis: \(legend.map(\.text))")
        for word in legend {
            #expect(word.x + word.width <= rightEdge + 0.001, "\(word.text) ends at \(word.x + word.width)")
        }
    }

    @Test("a short legend is as before: its entries stay where they were, unshortened")
    func shortLegendUnchanged() throws {
        let legend = try legendWords(chart("pie", [("Desktop", 62), ("Mobile", 31), ("Tablet", 7)]))
        let texts = legend.map(\.text)
        #expect(texts.contains("Desktop") && texts.contains("62") && texts.contains("Tablet"), "\(texts)")
        #expect(!texts.contains { $0.hasSuffix("\u{2026}") })
    }
}
