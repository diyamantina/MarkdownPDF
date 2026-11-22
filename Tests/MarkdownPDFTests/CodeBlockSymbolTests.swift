import Foundation
@testable import MarkdownPDF
import Testing

/// A symbol or an emoji in a code block is DRAWN with a face that has it, not folded to an ASCII stand-in letter. A code run whose own font is not
/// embedded is written with the base-14 font, which holds WinAnsi only; the page-level text faces and the colour emoji face are there and were not
/// used for it, so the down arrow and the check mark became "v" and the package emoji "?" (found on a printed article, `⬇️ Downloading`, `✓ Extracted`,
/// `📦 Cupertino Setup`). The text layer keeps the original characters, read back by the package's own reader.
@Suite("Symbols and emoji in code blocks")
struct CodeBlockSymbolTests {
    private static let fence = "```\n\u{2B07}\u{FE0F} Downloading\n\u{2713} Extracted\n\u{1F4E6} Cupertino Setup\n```\n"

    /// The bundled text faces for the regular, bold and oblique roles and NO face for code: the code run is written with the base-14 monospaced font.
    private static var codeNotEmbedded: PDFOptions.EmbeddedFonts {
        var fonts = PDFOptions.EmbeddedFonts.dejaVu
        fonts.monospaced = nil
        return fonts
    }

    private static let configurations: [(name: String, fonts: PDFOptions.EmbeddedFonts)] = [
        ("every role embedded", .dejaVu),
        ("the code face not embedded", codeNotEmbedded),
    ]

    private func render(_ fonts: PDFOptions.EmbeddedFonts, _ markdown: String = fence) throws -> Data {
        try MarkdownPDFRenderer(options: PDFOptions(embeddedFonts: fonts)).render(markdown: markdown)
    }

    /// The strings of the base-14 `Tj` operators of the page content (`BT /F4 9.9 Tf 60 772 Td (let ) Tj ET`, one per word), joined: where a stand-in
    /// letter would be written.
    private func standardText(in data: Data) -> String {
        var joined = ""
        for line in PDFInspector(data).text.split(separator: "\n") where line.contains(") Tj") {
            guard let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")"), open < close else { continue }
            joined += line[line.index(after: open) ..< close]
        }
        return joined
    }

    @Test("the arrow, the check mark and the package are not written as the letters v and ?", arguments: configurations)
    func noStandIn(configuration: (name: String, fonts: PDFOptions.EmbeddedFonts)) throws {
        let data = try render(configuration.fonts)
        let string = standardText(in: data)
        #expect(!string.contains("v Extracted"), Comment(rawValue: "\(configuration.name): the check mark is written as v: \(string)"))
        #expect(!string.contains("? Cupertino"), Comment(rawValue: "\(configuration.name): the package is written as ?: \(string)"))
        #expect(!string.contains("v Downloading"), Comment(rawValue: "\(configuration.name): the arrow is written as v: \(string)"))
    }

    @Test("the text layer keeps the original characters, read back by the own reader", arguments: configurations)
    func textLayerKept(configuration: (name: String, fonts: PDFOptions.EmbeddedFonts)) throws {
        let data = try render(configuration.fonts)
        let text = try PDFDocumentReader(data: data).pages.flatMap(\.words).map(\.text).joined(separator: " ")
        // Scalar by scalar: the arrow comes with its emoji variation selector, one character that holds the arrow scalar.
        let scalars = Set(text.unicodeScalars)
        for expected in [UnicodeScalar(0x2B07), UnicodeScalar(0x2713), UnicodeScalar(0x1F4E6)].compactMap(\.self) {
            #expect(scalars.contains(expected), Comment(rawValue: "\(configuration.name): U+\(String(expected.value, radix: 16)) is not in the text layer: \(text)"))
        }
        for word in ["Downloading", "Extracted", "Cupertino", "Setup"] {
            #expect(text.contains(word), Comment(rawValue: "\(configuration.name): `\(word)` is not in the text layer: \(text)"))
        }
    }

    @Test("the emoji are drawn as colour layers and the check mark as a glyph, in the code block too", arguments: configurations)
    func drawn(configuration: (name: String, fonts: PDFOptions.EmbeddedFonts)) throws {
        let data = try render(configuration.fonts)
        let content = PDFInspector(data).text
        // Each emoji is one `/ActualText` span holding its layers as filled paths: two spans for the two emoji of the block.
        let spans = content.components(separatedBy: "/ActualText").count - 1
        #expect(spans >= 2, Comment(rawValue: "\(configuration.name): \(spans) /ActualText spans, expected the 2 emoji"))
        #expect(content.contains(" f\n") || content.contains(" f*\n"), Comment(rawValue: "\(configuration.name): no filled path, the emoji layers are not drawn"))
    }

    @Test("plain code with the code face not embedded is written exactly as before: base-14 text, no second face")
    func plainCodeUnchanged() throws {
        let data = try render(Self.codeNotEmbedded, "```\nlet x = 1\n```\n")
        #expect(standardText(in: data).contains("let x = 1"), Comment(rawValue: PDFInspector(data).text))
    }

    @Test("a run that mixes plain and symbol text keeps the order and the width: the next word starts after the symbol")
    func widthAgrees() throws {
        let data = try render(Self.codeNotEmbedded, "```\na \u{2713} b\n```\n")
        let words = try PDFDocumentReader(data: data).pages.flatMap(\.words)
        let a = words.first { $0.text == "a" }
        let check = words.first { $0.text == "\u{2713}" }
        let b = words.first { $0.text == "b" }
        #expect(a != nil && check != nil && b != nil, Comment(rawValue: "\(words.map(\.text))"))
        if let a, let check, let b {
            #expect(a.x < check.x && check.x < b.x, "the words are out of order")
            #expect(check.x + check.width <= b.x + 0.5, "the symbol overlaps the next word")
        }
    }
}
