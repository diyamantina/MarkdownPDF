import Foundation
@testable import MarkdownPDF
import Testing

/// Line art and technical notation with no base-14 WinAnsi glyph (box drawing, block
/// elements, geometric shapes, arrows, super/subscripts, and dash/prime/space variants)
/// used to render as a wall of "?". Each now folds to an honest single-character ASCII
/// stand-in; symbols with no faithful ASCII form stay "?" rather than fold to nonsense.
@Suite("ASCII fallback transliteration")
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

    @Test("Folds arrows, shapes, super/subscripts, and dash/prime/space variants")
    func foldsOtherAsciiArt() throws {
        let cases: [(UnicodeScalar, Character)] = [
            // arrows
            ("\u{2192}", ">"), ("\u{2190}", "<"), ("\u{2191}", "^"), ("\u{2193}", "v"),
            ("\u{21D2}", ">"), ("\u{2194}", "-"), ("\u{2195}", "|"),
            // geometric shapes
            ("\u{25B2}", "^"), ("\u{25B6}", ">"), ("\u{25BC}", "v"), ("\u{25C0}", "<"),
            ("\u{25CF}", "#"), ("\u{25CB}", "o"), ("\u{25C6}", "#"), ("\u{25A0}", "#"), ("\u{25A1}", "o"),
            // super/subscripts fold to the base character
            ("\u{2070}", "0"), ("\u{2074}", "4"), ("\u{2079}", "9"), ("\u{2080}", "0"), ("\u{2089}", "9"),
            ("\u{207F}", "n"), ("\u{2071}", "i"), ("\u{207A}", "+"), ("\u{208B}", "-"),
            // prime, minus, hyphen, and space variants
            ("\u{2212}", "-"), ("\u{2032}", "'"), ("\u{2033}", "\""), ("\u{2011}", "-"), ("\u{2009}", " "),
        ]
        for (scalar, expected) in cases {
            #expect(
                PDFTextEncoding.encodedByte(for: scalar) == expected.asciiValue,
                "U+\(String(scalar.value, radix: 16)) should fold to '\(expected)'",
            )
        }
        // A symbol with no faithful ASCII form is left to "?", not folded to nonsense.
        for symbol in ["\u{2665}", "\u{2600}", "\u{2713}", "\u{2660}"] { // heart, sun, check, spade
            #expect(try PDFTextEncoding.encodedByte(for: #require(symbol.unicodeScalars.first)) == UInt8(ascii: "?"))
        }
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
