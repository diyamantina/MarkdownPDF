import Foundation
@testable import MarkdownPDF
import Testing

/// A word wider than its table cell is cut by character; the closing punctuation mark that ends it (a full stop, a comma, a closing bracket) must stay
/// with the letter before it and never stand alone on a line of its own. The page margin is swept so that the cut falls on every position of the word,
/// the narrow cell being the margin-sensitive case: whatever the width, no line of the text layer is a closing mark alone.
@Suite("A closing punctuation mark never stands alone after a cut word")
struct ClosingPunctuationTests {
    private static let marks = [".", ",", ";", ":", "!", "?", ")", "]", "}"]

    private func words(_ markdown: String, rightMargin: Double) throws -> [String] {
        var options = PDFOptions(embeddedFonts: .dejaVu)
        options.margins = PDFOptions.Margins(top: 54, right: rightMargin, bottom: 54, left: 54)
        let data = try MarkdownPDFRenderer(options: options).render(markdown: markdown)
        return try PDFDocumentReader(data: data).pages.flatMap(\.words).map(\.text)
    }

    @Test("the table cell holding a long word and its full stop never leaves the full stop alone, at any width", arguments: marks)
    func tableCell(mark: String) throws {
        let table = "| a | b |\n|---|---|\n| Antidisestablishmentarianism\(mark) | x |\n"
        var alone: [Double] = []
        // 190 margins from 150 to 339 points: the cell is a few letters wide to a few words wide, the cut falls on every position of the word.
        for margin in stride(from: 150.0, to: 340.0, by: 1.0) {
            let found = try words(table, rightMargin: margin)
            if found.contains(mark) {
                alone.append(margin)
            }
        }
        #expect(alone.isEmpty, Comment(rawValue: "`\(mark)` stands alone at the right margins \(alone)"))
    }

    @Test("the word and its mark are one piece when they fit: nothing changes for a cell wide enough")
    func wideCellUnchanged() throws {
        let found = try words("| a |\n|---|\n| Word. |\n", rightMargin: 54)
        #expect(found.contains("Word."), Comment(rawValue: "\(found)"))
    }

    @Test("a long word with no mark is cut as before: the same parts, by character")
    func noMarkUnchanged() throws {
        let found = try words("| a | b |\n|---|---|\n| Antidisestablishmentarianism | x |\n", rightMargin: 280)
        #expect(found.joined().contains("Antidisestablishmentarianism"), Comment(rawValue: "\(found)"))
    }
}
