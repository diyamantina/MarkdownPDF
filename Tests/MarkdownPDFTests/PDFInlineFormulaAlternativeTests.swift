import Foundation
@testable import MarkdownPDF
import MathTypeset
import Testing

/// An inline formula drawn as a box (a fraction, a root, a matrix: it has no text of its own) in a tagged PDF is a
/// `Formula` structure element inside its paragraph, with the spoken form as alternative text (PDF/UA-1, 7.7, Matterhorn 17-001 and
/// 17-002; WCAG 2.2, 1.1.1). The answer key is the library's own linearizer read back through the library's own reader; the paragraph keeps
/// its own text.
@Suite("Inline formula alternative text in tagged PDF")
struct PDFInlineFormulaAlternativeTests {
    private func read(_ markdown: String) throws -> PDFDocumentReader {
        let options = PDFOptions(mathTypesetting: .enabled, taggedPDF: .enabled)
        let data = try MarkdownPDFRenderer(options: options).render(markdown: markdown)
        return try PDFDocumentReader(data: data)
    }

    private static let sources = [
        #"\frac{a}{b}"#,
        #"\sqrt{b^2 - 4ac}"#,
        #"\frac{n(n+1)}{2}"#,
    ]

    @Test("an inline box formula is a Formula inside the paragraph, with its spoken form", arguments: sources)
    func inlineFormulaCarriesItsSpokenForm(source: String) throws {
        let spoken = try MathParser().parse(source).linearizedText
        #expect(spoken.isEmpty == false)

        let document = try read("Before $\(source)$ after.\n")
        let paragraph = try #require(document.structure.flatMap(\.flattened).first { $0.type == "P" })

        let formulas = paragraph.flattened.filter { $0.type == "Formula" }
        #expect(formulas.map(\.alternateText) == [spoken], "paragraph children: \(paragraph.children.map(\.type))")
    }

    @Test("the paragraph keeps the words around the formula and stays one paragraph")
    func paragraphKeepsItsText() throws {
        let document = try read("Before $\\frac{a}{b}$ after.\n")

        #expect(document.text.contains("Before"))
        #expect(document.text.contains("after."))
        #expect(document.structure.flatMap(\.flattened).filter { $0.type == "P" }.count == 1)
    }

    @Test("two inline formulas in one paragraph are two Formula elements in reading order")
    func twoFormulasInOrder() throws {
        let first = try MathParser().parse(#"\frac{a}{b}"#).linearizedText
        let second = try MathParser().parse(#"\sqrt{c}"#).linearizedText

        let document = try read("One $\\frac{a}{b}$ and two $\\sqrt{c}$.\n")

        let formulas = document.structure.flatMap(\.flattened).filter { $0.type == "Formula" }
        #expect(formulas.map(\.alternateText) == [first, second])
    }

    @Test("an inline matrix is drawn as its spoken text, so the paragraph already reads it and no box is tagged")
    func inlineMatrixIsText() throws {
        let source = #"\begin{matrix} a & b \\ c & d \end{matrix}"#
        let spoken = try MathParser().parse(source).linearizedText

        let document = try read("Before $\(source)$ after.\n")

        #expect(document.text.contains(spoken), "text: \(document.text)")
    }

    @Test("a paragraph without a formula has no Formula element")
    func plainParagraph() throws {
        let document = try read("Just words here.\n")

        #expect(document.structure.flatMap(\.flattened).contains { $0.type == "Formula" } == false)
    }
}
