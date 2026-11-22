import Foundation
@testable import MarkdownPDF
import Testing

/// A caller's emoji face is kept when the document needs the bundled text faces. With no text face given, a document with a character outside WinAnsi
/// (an emoji is one) gets the bundled DejaVu faces; the caller's `math` face was carried over and its `emoji` face was not, so the bundled colour face
/// silently replaced it. The face that draws is the one the PDF names.
@Suite("A caller's emoji face survives the bundled text faces")
struct CallerEmojiFaceTests {
    /// The bundled colour face under a name of the test's own, so the PDF says which face drew the emoji.
    private func callerFace() throws -> PDFOptions.EmbeddedFontSource {
        let bundled = try #require(BundledFonts.twemoji)
        return PDFOptions.EmbeddedFontSource(data: bundled.data, baseName: "CallerEmojiFace")
    }

    private func fontNames(_ data: Data) -> String {
        PDFInspector(data).text
    }

    @Test("with no text faces, the emoji face of the caller draws the emoji, not the bundled one")
    func callerFaceDraws() throws {
        let options = try PDFOptions(embeddedFonts: PDFOptions.EmbeddedFonts(emoji: callerFace()))
        let data = try MarkdownPDFRenderer(options: options).render(markdown: "a \u{1F9E9} b\n")
        let text = fontNames(data)
        // The base name of an embedded font is written behind a subset tag (`/ABCDEF+Name`); the font program's own name table also says Twemoji.
        #expect(text.contains("+CallerEmojiFace"), "the caller's emoji face is not in the PDF")
        #expect(!text.contains("+Twemoji"), "the bundled colour face replaced the caller's")
    }

    @Test("with no emoji face given, the bundled colour face draws, as before")
    func bundledFaceByDefault() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "a \u{1F9E9} b\n")
        #expect(fontNames(data).contains("+Twemoji"), "the bundled colour face is not in the PDF")
    }

    @Test("the caller's math face and emoji face are both kept")
    func mathAndEmoji() throws {
        let math = try #require(BundledFonts.latinModernMath)
        let options = try PDFOptions(
            embeddedFonts: PDFOptions.EmbeddedFonts(math: PDFOptions.EmbeddedFontSource(data: math.data, baseName: "CallerMathFace"), emoji: callerFace()),
            mathTypesetting: .enabled,
        )
        let data = try MarkdownPDFRenderer(options: options).render(markdown: "a \u{1F9E9} $\\int_0^1 x\\,dx$\n")
        let text = fontNames(data)
        #expect(text.contains("CallerEmojiFace") && text.contains("CallerMathFace"), "a caller's face is missing")
    }
}
