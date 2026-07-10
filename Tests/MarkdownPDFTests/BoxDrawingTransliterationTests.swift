import Foundation
@testable import MarkdownPDF
import Testing

/// Box-drawing and block-element line art (tree diagrams, ASCII tables) has no glyph in
/// the base-14 WinAnsi fonts, so it used to render as a wall of "?". It now folds to an
/// ASCII stand-in ("-", "|", "+", "/", "\", "X", "#") that keeps the diagram readable.
@Suite("Box drawing transliteration")
struct BoxDrawingTransliterationTests {
    @Test("Folds box-drawing scalars to their ASCII stand-in, not '?'")
    func foldsToAscii() {
        let cases: [(UnicodeScalar, Character)] = [
            ("\u{2500}", "-"), // horizontal
            ("\u{2501}", "-"), // heavy horizontal
            ("\u{2550}", "-"), // double horizontal
            ("\u{2502}", "|"), // vertical
            ("\u{2503}", "|"), // heavy vertical
            ("\u{251C}", "+"), // tee right
            ("\u{2524}", "+"), // tee left
            ("\u{252C}", "+"), // tee down
            ("\u{2534}", "+"), // tee up
            ("\u{253C}", "+"), // cross
            ("\u{250C}", "+"), // top-left corner
            ("\u{2518}", "+"), // bottom-right corner
            ("\u{256D}", "+"), // rounded corner
            ("\u{2571}", "/"), // diagonal
            ("\u{2572}", "\\"), // diagonal
            ("\u{2573}", "X"), // cross diagonals
            ("\u{2588}", "#"), // full block
            ("\u{2591}", "#"), // light shade
        ]
        for (scalar, expected) in cases {
            let byte = PDFTextEncoding.encodedByte(for: scalar)
            #expect(byte == expected.asciiValue, "U+\(String(scalar.value, radix: 16)) drew '\(Character(UnicodeScalar(byte)))', expected '\(expected)'")
            #expect(byte != PDFTextEncoding.replacementScalar.value.asciiByte, "must not fall back to '?'")
        }
        // A scalar with no stand-in still falls back to "?".
        #expect(PDFTextEncoding.encodedByte(for: "\u{2603}") == UInt8(ascii: "?")) // snowman
        // The measured scalar matches the drawn stand-in, so advances stay in step.
        #expect(PDFTextEncoding.portableScalars(for: "\u{251C}\u{2500}") == ["+", "-"])
    }

    @Test("A code-block tree renders as an ASCII diagram, not question marks")
    func rendersTree() throws {
        let tree = "```\nCV\n\u{251C}\u{2500}\u{2500} ContactInfo\n\u{251C}\u{2500}\u{2500} WorkExperience\n\u{2502}   \u{2514}\u{2500}\u{2500} Company\n\u{2514}\u{2500}\u{2500} Period\n```"
        let pdf = try MarkdownPDFRenderer(options: PDFOptions()).render(markdown: tree)
        let url = try PDFValidation.temporaryPDF(name: "box-drawing-tree", data: pdf)
        let text = try PDFValidation.pdftotext(url: url).output
        // The diagram is drawn with ASCII line art and carries no stray "?".
        #expect(text.contains("+-- ContactInfo"))
        #expect(text.contains("|"))
        #expect(!text.contains("?"), "box-drawing must not render as '?':\n\(text)")
    }
}

private extension UInt32 {
    var asciiByte: UInt8 {
        UInt8(truncatingIfNeeded: self)
    }
}
