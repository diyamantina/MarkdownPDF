import Foundation
@testable import MarkdownPDF
import MathTypeset
import Testing

/// A display formula in a tagged PDF is a `Formula` structure element whose alternative text is the spoken form of the
/// formula (PDF/UA-1, 7.9; WCAG 2.2, 1.1.1), so that assistive technology reads it instead of skipping a drawing. The
/// answer key is the library's own linearizer (`MathParser().parse(source).linearizedText`), the very text that is
/// already written as `/ActualText` over the drawn glyphs, read back through the library's own reader.
@Suite("Formula alternative text in tagged PDF")
struct PDFFormulaAlternativeTests {
    private func structure(of markdown: String) throws -> [PDFDocumentReader.StructureElement] {
        let data = try MarkdownPDFRenderer(options: PDFOptions(mathTypesetting: .enabled, taggedPDF: .enabled)).render(markdown: markdown)
        return try PDFDocumentReader(data: data).structure.flatMap(\.flattened)
    }

    private static let sources = [
        #"\frac{a}{b}"#,
        #"x^2 + y^2 = z^2"#,
        #"\sum_{i=1}^{n} i = \frac{n(n+1)}{2}"#,
        #"\sqrt{b^2 - 4ac}"#,
        #"\begin{matrix} a & b \\ c & d \end{matrix}"#,
    ]

    @Test("a display formula is a Formula element whose alt is the linearized text", arguments: sources)
    func displayFormulaCarriesItsSpokenForm(source: String) throws {
        let spoken = try MathParser().parse(source).linearizedText
        #expect(spoken.isEmpty == false, "the oracle must have something to say for \(source)")

        let elements = try structure(of: "$$\n\(source)\n$$\n")
        let formulas = elements.filter { $0.type == "Formula" }

        #expect(formulas.map(\.alternateText) == [spoken], "element types: \(elements.map(\.type))")
    }

    @Test("a paragraph is still a paragraph: the formula role is only for display math")
    func paragraphsAreNotFormulas() throws {
        let elements = try structure(of: "Plain text.\n")

        #expect(elements.contains { $0.type == "P" })
        #expect(elements.contains { $0.type == "Formula" } == false)
    }

    @Test("a display formula that cannot be parsed keeps its source as text and makes no Formula element")
    func unparsableFormulaIsNotAFormula() throws {
        let elements = try structure(of: "$$\n\\frac{a}{\n$$\n")

        #expect(elements.contains { $0.type == "Formula" } == false, "elements: \(elements.map(\.type))")
    }
}
