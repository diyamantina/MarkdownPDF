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
        for symbol in ["\u{2602}", "\u{262F}", "\u{266B}", "\u{2699}", "\u{2603}"] { // umbrella, yin-yang, notes, gear, snowman
            #expect(try PDFTextEncoding.encodedByte(for: #require(symbol.unicodeScalars.first)) == UInt8(ascii: "?"))
        }
    }

    @Test("Folds stars, card suits, checkmarks, crosses, and dingbat arrows")
    func foldsSymbols() {
        let cases: [(UnicodeScalar, Character)] = [
            // stars, sparkles, snowflakes, sun -> asterisk
            ("\u{2605}", "*"), ("\u{2606}", "*"), ("\u{2728}", "*"), ("\u{2744}", "*"),
            ("\u{2734}", "*"), ("\u{2600}", "*"), ("\u{2721}", "*"),
            // card suits -> initial
            ("\u{2660}", "S"), ("\u{2665}", "H"), ("\u{2663}", "C"), ("\u{2666}", "D"),
            ("\u{2664}", "S"), ("\u{2661}", "H"), ("\u{2667}", "C"), ("\u{2662}", "D"),
            ("\u{2764}", "H"),
            // checkmarks -> v, ballot / heavy crosses -> x
            ("\u{2713}", "v"), ("\u{2714}", "v"), ("\u{2611}", "v"),
            ("\u{2717}", "x"), ("\u{2718}", "x"), ("\u{2716}", "x"), ("\u{274C}", "x"), ("\u{2612}", "x"),
            // religious and heavy crosses -> + (daggers are WinAnsi, so excluded here)
            ("\u{2626}", "+"), ("\u{271D}", "+"), ("\u{271A}", "+"), ("\u{2719}", "+"),
            // heavy / dingbat arrows -> >
            ("\u{2794}", ">"), ("\u{279C}", ">"), ("\u{27A1}", ">"), ("\u{27BE}", ">"),
        ]
        for (scalar, expected) in cases {
            #expect(
                PDFTextEncoding.encodedByte(for: scalar) == expected.asciiValue,
                "U+\(String(scalar.value, radix: 16)) should fold to '\(expected)'",
            )
        }
        // U+27B0 is a curly loop, not an arrow, so it is not swept into ">".
        #expect(PDFTextEncoding.encodedByte(for: "\u{27B0}") == UInt8(ascii: "?"))
    }

    /// The compatibility-decomposition folds are derived from the Unicode standard (NFKD),
    /// not a hand-written list, so the full set of subscript letters is covered, including
    /// the seven a hand-picked list originally missed (h, k, l, m, p, s, t).
    @Test("Derives folds from the Unicode compatibility decomposition")
    func foldsFromCompatibilityDecomposition() {
        let cases: [(UnicodeScalar, Character)] = [
            // every subscript letter that decomposes to ASCII, not just the common few
            ("\u{2095}", "h"), ("\u{2096}", "k"), ("\u{2097}", "l"), ("\u{2098}", "m"),
            ("\u{209A}", "p"), ("\u{209B}", "s"), ("\u{209C}", "t"),
            // superscript letter and signs
            ("\u{2071}", "i"), ("\u{207F}", "n"), ("\u{207C}", "="), ("\u{207D}", "("), ("\u{207E}", ")"),
            // circled and fullwidth forms are compatibility variants that land on one scalar
            ("\u{2460}", "1"), ("\u{FF21}", "A"), ("\u{FF10}", "0"),
            // every Unicode space decomposes to a plain space
            ("\u{2003}", " "), ("\u{2009}", " "), ("\u{3000}", " "),
        ]
        for (scalar, expected) in cases {
            #expect(
                PDFTextEncoding.encodedByte(for: scalar) == expected.asciiValue,
                "U+\(String(scalar.value, radix: 16)) should fold to '\(expected)'",
            )
        }
        // The subscript schwa (U+2094 -> U+0259) has no ASCII decomposition, so it stays "?".
        #expect(PDFTextEncoding.encodedByte(for: "\u{2094}") == UInt8(ascii: "?"))
        // A vulgar fraction not in WinAnsi decomposes to three scalars, so it is not folded.
        #expect(PDFTextEncoding.encodedByte(for: "\u{2153}") == UInt8(ascii: "?")) // ⅓
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
