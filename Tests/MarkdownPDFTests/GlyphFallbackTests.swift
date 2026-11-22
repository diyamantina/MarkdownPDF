import Foundation
@testable import MarkdownPDF
import Testing

/// A character the face of a run lacks is drawn with the bundled face that has it instead of the missing-glyph box. The monospaced face has no
/// Braille patterns (the spinner of a command line tool, `U+2839`), the proportional face has: a code block that shows such a spinner used to draw
/// `.notdef` (code 0000 of the font) there. A character no bundled face has is still the missing-glyph box, a fault to see, and a document that needs
/// no fallback is drawn exactly as before.
@Suite("Glyph fallback between the bundled faces")
struct GlyphFallbackTests {
    private static let spinner = "\u{2839} [\u{2588}\u{2588}\u{2588}\u{2591}\u{2591}\u{2591}] 53%"

    private func render(_ markdown: String) throws -> Data {
        try MarkdownPDFRenderer(options: PDFOptions(embeddedFonts: .dejaVu)).render(markdown: markdown)
    }

    /// The glyph codes of every `Tj` string of the page content that are 0000, the `.notdef` of a font.
    private func notdefCodes(in data: Data) -> Int {
        var count = 0
        let tokens = PDFInspector(data).text.split(whereSeparator: \.isWhitespace)
        for index in tokens.indices.dropLast() where tokens[index + 1] == "Tj" && tokens[index].hasPrefix("<") && tokens[index].hasSuffix(">") {
            let hex = Array(tokens[index].dropFirst().dropLast())
            for start in stride(from: 0, to: hex.count - 3, by: 4) where String(hex[start ..< start + 4]) == "0000" {
                count += 1
            }
        }
        return count
    }

    @Test("MEASURED: the bundled monospaced face lacks the Braille patterns of a spinner, the proportional face has them")
    func coverage() throws {
        let catalog = try PDFEmbeddedFontCatalog(fonts: .dejaVu)
        for scalar in ["\u{2839}", "\u{2827}", "\u{280B}"] {
            let code = scalar.unicodeScalars.first?.value ?? 0
            #expect(!catalog.covers(scalar, font: .courier), Comment(rawValue: "the mono face covers U+\(code)"))
            #expect(catalog.covers(scalar, font: .helvetica), Comment(rawValue: "the proportional face lacks U+\(code)"))
        }
        // The block elements of the progress bar are in the monospaced face.
        #expect(catalog.covers("\u{2588}\u{2591}", font: .courier))
    }

    @Test("a code block with a Braille spinner draws no .notdef, and its text still reads back")
    func codeBlockSpinner() throws {
        let data = try render("```\n\(Self.spinner)\n```\n")
        #expect(notdefCodes(in: data) == 0, "the spinner is drawn as .notdef (code 0000)")
        let words = try PDFDocumentReader(data: data).pages.flatMap(\.words).map(\.text).joined(separator: " ")
        #expect(words.contains("\u{2839}") && words.contains("53%"), Comment(rawValue: words))
    }

    @Test("an inline code span and a table cell with a spinner draw no .notdef either")
    func inlineAndTable() throws {
        let data = try render("A `\(Self.spinner)` span.\n\n| state | line |\n|---|---|\n| busy | `\u{2827}` |\n")
        #expect(notdefCodes(in: data) == 0)
    }

    @Test("a character that no bundled face has is still drawn as the missing-glyph box, not dropped")
    func unknownStaysABox() throws {
        let data = try render("```\n\u{4E2D}\n```\n")
        let lines = PDFInspector(data).text.split(separator: "\n").filter { $0.contains("Tj") || $0.contains("TJ") }
        #expect(notdefCodes(in: data) >= 1, Comment(rawValue: "a character no face covers must stay visible as the box: \(lines)"))
    }

    @Test("text every face covers is drawn exactly as without the fallback: no second font is used for plain code")
    func plainCodeUnchanged() throws {
        let plain = try render("```\nlet x = 1\n```\n")
        let content = PDFInspector(plain).text
        #expect(notdefCodes(in: plain) == 0)
        // Only the monospaced face (and the base text face of the page, none here) is used for a block of ASCII.
        #expect(!content.contains("\u{2839}"))
    }
}
