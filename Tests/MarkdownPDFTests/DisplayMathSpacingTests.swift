import Foundation
@testable import MarkdownPDF
import Testing

/// A display formula has room after it: the cursor is the next line's baseline, and the glyphs rise an ascender (0.75 of the size) above it, so the baseline
/// of the paragraph after a formula must lie at least that ascender plus a visible gap below the formula's lowest ink. It used to lie only the formula style's
/// spacing below it, so a lower limit (a sum's `p in P`) touched the next line, and a formula pushed to the top of a page touched the paragraph under it.
@Suite("Display math has room before the next block")
struct DisplayMathSpacingTests {
    /// The body size of the paragraph that follows, and its ascender (0.75 of it, the convention the code block gap documents).
    private static let bodySize = 11.0
    private static let ascender = 0.75 * bodySize
    /// The smallest visible gap between the formula's lowest ink and the next line's tallest glyph.
    private static let visibleGap = 3.0

    /// A formula and how far its lowest ink hangs below its baseline, MEASURED as the layout box depth at the display size 11.88:
    /// a flat formula hangs by the descender of its tallest-descending glyph (not below 0), a sum with a lower limit by 14.52.
    private static let cases: [(formula: String, depth: Double)] = [
        ("\\text{scope} \\bmod 32 = 17", 0),
        ("\\text{scope}(P) = \\sum_{p \\in P} 2^{\\,b(p)}", 14.52),
        ("\\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx = \\sqrt{\\pi}", 0),
    ]

    private func pages(_ markdown: String) throws -> [PDFDocumentReader.Page] {
        try PDFDocumentReader(data: MarkdownPDFRenderer(options: PDFOptions(mathTypesetting: .enabled)).render(markdown: markdown)).pages
    }

    /// The baseline distance, on the page that holds both, from the formula (the words between "Before." and "After") to the paragraph after it,
    /// with `fillerLines` one-line paragraphs ahead so the page break falls at different places. Nil when they are on different pages.
    private func distance(_ formula: String, fillerLines: Int) throws -> Double? {
        let filler = (0 ..< fillerLines).map { "Filler line \($0)." }.joined(separator: "\n\n")
        let document = try pages("\(filler)\n\nBefore.\n\n$$\(formula)$$\n\nAfter the formula comes a paragraph.\n")
        for page in document {
            guard let after = page.words.first(where: { $0.text == "After" }) else { continue }
            let above = page.words.filter { $0.y > after.y + 1 && !$0.text.hasPrefix("Filler") && $0.text != "Before." && $0.text != "line" }
            guard let formulaBaseline = above.map(\.y).min() else { return nil }
            return formulaBaseline - after.y
        }
        return nil
    }

    @Test("wherever the page falls, the next paragraph's baseline clears the formula's lowest ink by the ascender and a gap", arguments: cases)
    func room(formula: String, depth: Double) throws {
        var seen = 0
        for fillerLines in 0 ..< 110 {
            guard let found = try distance(formula, fillerLines: fillerLines) else { continue }
            seen += 1
            let needed = depth + Self.ascender + Self.visibleGap
            #expect(found >= needed, Comment(rawValue: "\(formula) after \(fillerLines) filler lines: the next baseline is \(found) pt below the formula, needs \(needed)"))
        }
        #expect(seen > 0, "no case put the formula and the paragraph on one page")
    }
}
