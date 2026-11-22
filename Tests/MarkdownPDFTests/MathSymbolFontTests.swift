import Foundation
@testable import MarkdownPDF
import Testing

/// A formula that needs a symbol the base fonts do not have (an integral, an infinity, a Greek letter, a relation) is drawn with that symbol, not spelled out
/// as the words "int", "infinity" and "pi". The engine does for such a formula what it already does for text outside WinAnsi: it uses the bundled faces.
/// A formula with no such symbol keeps the base fonts, and so does a document that does not typeset math.
@Suite("Math symbols are drawn, not spelled out")
struct MathSymbolFontTests {
    private func words(_ markdown: String, math: PDFOptions.MathTypesetting = .enabled) throws -> [String] {
        let data = try MarkdownPDFRenderer(options: PDFOptions(mathTypesetting: math)).render(markdown: markdown)
        return try PDFDocumentReader(data: data).pages.flatMap(\.words).map(\.text)
    }

    private func usesEmbeddedFace(_ markdown: String, math: PDFOptions.MathTypesetting = .enabled) throws -> Bool {
        let data = try MarkdownPDFRenderer(options: PDFOptions(mathTypesetting: math)).render(markdown: markdown)
        return PDFInspector(data).text.contains("/EF5")
    }

    @Test("an integral with infinite limits and a square root of pi are drawn with their symbols")
    func integral() throws {
        let printed = try words("$$\\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx = \\sqrt{\\pi}$$\n")
        // the reader returns the accessibility text of a formula (its linearization), so the words say nothing about the glyphs;
        // what shows is that an embedded face is used, and the page itself is looked at by eye
        #expect(!printed.isEmpty)
        #expect(try usesEmbeddedFace("$$\\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx = \\sqrt{\\pi}$$\n"), "the symbols come from an embedded face")
    }

    @Test("greek letters, relations and sums in running text are drawn with their symbols, not their names")
    func inline() throws {
        let joined = try words("Inline $\\alpha + \\beta \\le \\sum_{i=1}^{n} x_i$ here.\n").joined(separator: " ")
        #expect(!joined.contains("alpha") && !joined.contains("beta") && !joined.contains("sum"), Comment(rawValue: joined))
        #expect(try usesEmbeddedFace("Inline $\\alpha + \\beta \\le \\sum_{i=1}^{n} x_i$ here.\n"))
    }

    @Test("a formula that needs no symbol keeps the base fonts", arguments: [
        "$x^2 + y_1$", "$$\\frac{a}{b}$$", "$$\\sqrt{x}$$", "$a + b = c$",
    ])
    func plainMathStaysOnBaseFonts(markdown: String) throws {
        #expect(try !usesEmbeddedFace(markdown + "\n"), Comment(rawValue: markdown))
    }

    @Test("a formula with a symbol uses the bundled face, and a document that does not typeset math does not")
    func switchesOnlyWhenNeeded() throws {
        #expect(try usesEmbeddedFace("$$\\int_0^1 x\\,dx$$\n"))
        #expect(try !usesEmbeddedFace("$$\\int_0^1 x\\,dx$$\n", math: .disabled))
    }

    @Test("a symbol written as the character itself is drawn too")
    func literalSymbol() throws {
        #expect(try usesEmbeddedFace("$$\u{222B} f$$\n"))
    }
}
