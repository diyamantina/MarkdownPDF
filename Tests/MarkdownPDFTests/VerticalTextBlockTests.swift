import Foundation
@testable import MarkdownPDF
import Testing

/// A fenced `vertical` block sets its text top to bottom (tategaki): glyphs stack down a
/// line, lines advance right to left, a source line break starts a new column, and the run
/// stays recoverable in reading order (through `/ToUnicode`) with a reading-order extractor.
/// The glyph ids and advances were matched to CoreText in the shaper's own tests; these
/// tests cover the block layout and its PDF output.
@Suite("Vertical text block")
struct VerticalTextBlockTests {
    private static let path = "/System/Library/Fonts/Hiragino Sans GB.ttc"

    private static func hiragino() throws -> PDFOptions.EmbeddedFonts? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return .allRoles(PDFOptions.EmbeddedFontSource(data: data, baseName: "HiraginoSansGB", faceIndex: 0))
    }

    /// The per-character x positions the drawn glyphs occupy, in draw order, read from
    /// MuPDF's structured text. Distinct x values are the columns.
    private func characterColumns(_ pdf: Data) throws -> [Double] {
        let url = try PDFValidation.temporaryPDF(name: "vertical-columns", data: pdf)
        let stext = try PDFValidation.mutoolStructuredText(url: url).output
        let regex = try NSRegularExpression(pattern: #"<char [^>]*\bx="([0-9.]+)""#)
        let range = NSRange(stext.startIndex ..< stext.endIndex, in: stext)
        return regex.matches(in: stext, range: range).compactMap { match in
            Range(match.range(at: 1), in: stext).flatMap { Double(stext[$0]) }
        }
    }

    @Test("Extracts in reading order across multiple columns")
    func extractsInReadingOrder() throws {
        guard let fonts = try Self.hiragino() else { return }
        // Long enough to fill more than one column, so a geometry-only extractor would
        // scramble it; a reading-order extractor must recover the source exactly.
        let text = String(repeating: "\u{3042}\u{3044}\u{3046}\u{3048}\u{304A}\u{3002}", count: 30)
        let pdf = try MarkdownPDFRenderer(options: PDFOptions(embeddedFonts: fonts))
            .render(markdown: "```vertical\n\(text)\n```")
        let url = try PDFValidation.temporaryPDF(name: "vertical-reading-order", data: pdf)
        #expect(try PDFValidation.qpdfCheck(url: url).exitCode == 0)
        let extracted = try PDFValidation.pdftotextRaw(url: url).output
        let extractedScalars = extracted.unicodeScalars.filter { !$0.properties.isWhitespace }
        #expect(Array(extractedScalars) == Array(text.unicodeScalars))
        // It genuinely used more than one column (right-to-left, so x decreases).
        let columns = try Array(Set(characterColumns(pdf).map { ($0 / 5).rounded() * 5 })).sorted(by: >)
        #expect(columns.count >= 2, "expected multiple columns, got \(columns)")
    }

    @Test("A source line break starts a new column to the left")
    func newlineStartsColumn() throws {
        guard let fonts = try Self.hiragino() else { return }
        let options = PDFOptions(embeddedFonts: fonts)
        // One line, two glyphs: one column.
        let oneLine = try MarkdownPDFRenderer(options: options).render(markdown: "```vertical\n\u{4E00}\u{4E8C}\n```")
        let oneLineColumns = try Set(characterColumns(oneLine).map { ($0 / 5).rounded() })
        #expect(oneLineColumns.count == 1, "one line should be one column, got \(oneLineColumns)")
        // Two lines: two columns, the second to the left of the first.
        let twoLines = try MarkdownPDFRenderer(options: options)
            .render(markdown: "```vertical\n\u{4E00}\u{4E8C}\n\u{4E09}\u{56DB}\n```")
        let twoLineXs = try characterColumns(twoLines)
        let distinct = Array(Set(twoLineXs.map { ($0 / 5).rounded() * 5 }))
        #expect(distinct.count == 2, "two lines should be two columns, got \(distinct)")
        // The first-drawn glyph's column is to the right of the last-drawn glyph's column.
        try #expect(#require(twoLineXs.first) > #require(twoLineXs.last))
    }

    @Test("A tagged vertical block is PDF/UA-1 and PDF/A-2a conformant")
    func conforms() throws {
        guard let fonts = try Self.hiragino() else { return }
        let options = PDFOptions(
            embeddedFonts: fonts,
            title: "Vertical Conformance",
            taggedPDF: .enabled,
            conformance: .pdfUA1AndPDFA2A,
        )
        let pdf = try MarkdownPDFRenderer(options: options)
            .render(markdown: "```vertical\n\u{7E26}\u{66F8}\u{304D}\u{3002}\u{300C}\u{5F15}\u{7528}\u{300D}\n```")
        let ua1 = try PDFValidation.veraPDF(data: pdf, name: "vertical-ua1", flavour: "ua1")
        #expect(ua1.exitCode == 0, "veraPDF ua1 failed:\n\(ua1.output)")
        #expect(ua1.output.contains("\"compliant\" : true"))
        let a2a = try PDFValidation.veraPDF(data: pdf, name: "vertical-2a", flavour: "2a")
        #expect(a2a.exitCode == 0, "veraPDF 2a failed:\n\(a2a.output)")
        #expect(a2a.output.contains("\"compliant\" : true"))
    }

    @Test("Without vertical metrics the block falls back and keeps its text")
    func fallsBackAndKeepsText() throws {
        // An embedded Latin font has no vertical metrics; the block must fall back to a code
        // block that still shows the text rather than rendering tofu.
        let arialPath = "/System/Library/Fonts/Supplemental/Arial.ttf"
        guard FileManager.default.fileExists(atPath: arialPath) else { return }
        let arial = try Data(contentsOf: URL(fileURLWithPath: arialPath))
        let options = PDFOptions(embeddedFonts: .allRoles(PDFOptions.EmbeddedFontSource(data: arial, baseName: "Arial")))
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "```vertical\nHello World\n```")
        let url = try PDFValidation.temporaryPDF(name: "vertical-fallback", data: pdf)
        #expect(try PDFValidation.pdftotext(url: url).output.contains("Hello World"))
    }
}
