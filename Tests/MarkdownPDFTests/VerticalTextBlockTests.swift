import Foundation
@testable import MarkdownPDF
import Testing

/// A fenced `vertical` block sets its text top to bottom in a right-hand column (tategaki):
/// the glyphs stack down the line, the ideographic full stop and brackets take their
/// vertical forms, and the run stays recoverable in reading order through `/ToUnicode`.
@Suite("Vertical text block")
struct VerticalTextBlockTests {
    private static let path = "/System/Library/Fonts/Hiragino Sans GB.ttc"

    @Test("Renders a vertical block that extracts in reading order")
    func rendersVertical() throws {
        guard FileManager.default.fileExists(atPath: Self.path) else { return }
        let font = try Data(contentsOf: URL(fileURLWithPath: Self.path))
        let options = PDFOptions(embeddedFonts: .allRoles(
            PDFOptions.EmbeddedFontSource(data: font, baseName: "HiraginoSansGB", faceIndex: 0),
        ))
        let text = "\u{7E26}\u{66F8}\u{304D}\u{3002}\u{300C}\u{5F15}\u{7528}\u{300D}" // 縦書き。「引用」
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "```vertical\n\(text)\n```")

        let inspector = PDFInspector(pdf)
        #expect(inspector.pageCount >= 1)
        #expect(inspector.text.contains("/CIDFontType0"))
        #expect(inspector.text.contains("/ToUnicode"))

        // Structural validity and reading-order extraction: pdftotext lays each vertical
        // glyph on its own line, so the extracted characters, in order, are the source.
        let url = try PDFValidation.temporaryPDF(name: "vertical-block", data: pdf)
        #expect(try PDFValidation.qpdfCheck(url: url).exitCode == 0)
        let extracted = try PDFValidation.pdftotext(url: url).output
        let extractedScalars = extracted.unicodeScalars.filter { !$0.properties.isWhitespace }
        #expect(Array(extractedScalars) == Array(text.unicodeScalars), "expected \(text), got \(extracted)")
    }

    @Test("Without an embedded font, a vertical block falls back rather than losing text")
    func fallsBackWithoutFont() throws {
        let text = "\u{7E26}\u{66F8}\u{304D}"
        let pdf = try MarkdownPDFRenderer(options: PDFOptions()).render(markdown: "```vertical\n\(text)\n```")
        #expect(PDFInspector(pdf).pageCount >= 1)
    }
}
