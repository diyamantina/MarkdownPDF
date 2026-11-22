import Foundation
@testable import MarkdownPDF
import Testing

/// A closing mark that follows an inline code span (`` `CATransform3D`. ``) is a token of its own for the line breaker, because the code span and the
/// text after it are separate runs. When the span ends a line, the mark must go to the next line WITH the span, never alone: no line of the text layer
/// is a closing mark by itself. The right margin is swept so that the span meets the end of the line at every position.
@Suite("A closing mark after an inline code span never stands alone")
struct ClosingPunctuationAfterCodeTests {
    private static let marks = [".", ",", ";", ":", "!", "?", ")"]

    private func words(_ markdown: String, rightMargin: Double) throws -> [String] {
        var options = PDFOptions(embeddedFonts: .dejaVu)
        options.margins = PDFOptions.Margins(top: 54, right: rightMargin, bottom: 54, left: 54)
        let data = try MarkdownPDFRenderer(options: options).render(markdown: markdown)
        return try PDFDocumentReader(data: data).pages.flatMap(\.words).map(\.text)
    }

    @Test("a table cell that ends with a code span and a mark, the real cell of the swiftui-3d-is-flat table", arguments: marks)
    func tableCell(mark: String) throws {
        let cell = "Per-view projection, initializable from `CATransform3D`\(mark)"
        let table = "| Claim | Status | Evidence |\n|---|---|---|\n| `CALayer.transform` | `rotation3DEffect` | \(cell) |\n"
        var alone: [Double] = []
        for margin in stride(from: 54.0, to: 330.0, by: 1.0) {
            if try words(table, rightMargin: margin).contains(mark) {
                alone.append(margin)
            }
        }
        #expect(alone.isEmpty, Comment(rawValue: "`\(mark)` stands alone at the right margins \(alone)"))
    }

    @Test("a paragraph that ends with a code span and a mark")
    func paragraph() throws {
        var alone: [Double] = []
        for margin in stride(from: 54.0, to: 330.0, by: 1.0) {
            let text = "Per-view projection, initializable from `CATransform3D`. Then more words follow after it.\n"
            if try words(text, rightMargin: margin).contains(".") {
                alone.append(margin)
            }
        }
        #expect(alone.isEmpty, Comment(rawValue: "`.` stands alone at the right margins \(alone)"))
    }

    @Test("the span and its mark are one piece when they fit: nothing changes for a wide cell")
    func wideCellUnchanged() throws {
        // The reader groups the span and the mark that touches it into one word.
        let found = try words("| a |\n|---|\n| from `CATransform3D`. |\n", rightMargin: 54)
        #expect(found.contains("CATransform3D."), Comment(rawValue: "\(found)"))
    }
}
