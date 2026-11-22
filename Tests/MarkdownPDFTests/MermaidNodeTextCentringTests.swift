import Foundation
@testable import MarkdownPDF
import Testing

/// The text of a node is centred in its box, whatever the shape: a one-line label in a node of the minimum height used to sit about 4 pt high in a plain
/// rectangle. The first line's baseline lies at `top - (height - blockHeight) / 2 - fontSize`, the block being `lines * lineHeight` (`1.18 * fontSize`).
@Suite("Mermaid node text is centred in its box")
struct MermaidNodeTextCentringTests {
    /// The first filled rectangle's `x y width height` of the page content, which is the first node's box (the diagram frame is stroked and filled
    /// first, so the nodes' boxes are the ones that follow it).
    private func rectangles(_ data: Data) -> [(x: Double, y: Double, width: Double, height: Double)] {
        let tokens = PDFInspector(data).text.split(whereSeparator: \.isWhitespace).map(String.init)
        var found: [(x: Double, y: Double, width: Double, height: Double)] = []
        for (index, token) in tokens.enumerated() where token == "re" && index >= 4 {
            let numbers = tokens[(index - 4) ..< index].compactMap(Double.init)
            if numbers.count == 4 {
                found.append((numbers[0], numbers[1], numbers[2], numbers[3]))
            }
        }
        return found
    }

    @Test("a one-line label sits in the vertical middle of a plain rectangle (the other shapes are paths with no `re` to measure; centred by the same inset)", arguments: [
        "A[Hello]",
    ])
    func centred(node: String) throws {
        let data = try MarkdownPDFRenderer().render(markdown: "```mermaid\nflowchart TD\n  \(node)\n```\n")
        let word = try #require(PDFDocumentReader(data: data).pages.flatMap(\.words).first { $0.text == "Hello" })
        let box = try #require(rectangles(data).first { $0.width < 200 && $0.height < 60 } ?? nil, "the node's box is drawn as a rectangle or a path")
        let lineHeight = word.fontSize * 1.18
        let expectedBaseline = box.y + box.height - (box.height - lineHeight) / 2 - word.fontSize
        #expect(abs(word.y - expectedBaseline) < 0.05, Comment(rawValue: "\(node): baseline \(word.y), centred is \(expectedBaseline), box \(box)"))
    }
}
