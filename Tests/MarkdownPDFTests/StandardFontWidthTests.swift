@testable import MarkdownPDF
import Testing

/// The base-14 advance widths must match the Adobe Core-14 AFM metrics exactly.
///
/// Before this suite, any WinAnsi scalar outside ASCII that was neither in a small
/// hand-written punctuation table nor decomposable to an ASCII base fell back to
/// the width of `?` (556 for Helvetica). `Æ`, `ß`, `½`, `Ø`, the superscripts, and
/// the ordinals all measured at 556, so a line of them overran the page and, on
/// the embedded path, wrote wrong values into `/Widths` and overlapped. The tables
/// are now generated from the AFM files through the WinAnsi encoding vector.
///
/// The expected values below are the authoritative Adobe advances (Helvetica.afm,
/// Helvetica-Bold.afm), transcribed so the suite pins them without the AFM files
/// at test time.
@Suite("Standard font widths")
struct StandardFontWidthTests {
    /// Width in 1000-unit em space, i.e. the raw advance the AFM lists.
    private func advance(_ scalar: UnicodeScalar, _ font: StandardFont) -> Int {
        Int((font.width(of: String(scalar), size: 1000, fontSet: .pdfBase)).rounded())
    }

    @Test("High WinAnsi scalars carry their true Adobe advance, not the ? fallback", arguments: [
        // scalar, Helvetica advance, Helvetica-Bold advance (from the AFM)
        (Character("\u{00C6}"), 1000, 1000), // AE
        (Character("\u{00E6}"), 889, 889), //  ae
        (Character("\u{00D8}"), 778, 778), //  Oslash
        (Character("\u{00F8}"), 611, 611), //  oslash
        (Character("\u{00DF}"), 611, 611), //  germandbls
        (Character("\u{00BD}"), 834, 834), //  onehalf
        (Character("\u{00BC}"), 834, 834), //  onequarter
        (Character("\u{00BE}"), 834, 834), //  threequarters
        (Character("\u{00AA}"), 370, 370), //  ordfeminine
        (Character("\u{00BA}"), 365, 365), //  ordmasculine
        (Character("\u{00B9}"), 333, 333), //  onesuperior
        (Character("\u{00B2}"), 333, 333), //  twosuperior
        (Character("\u{00DE}"), 667, 667), //  Thorn
        (Character("\u{00FE}"), 556, 611), //  thorn (regular and bold differ)
        (Character("\u{00D0}"), 722, 722), //  Eth
        (Character("\u{00A6}"), 260, 280), //  brokenbar (regular and bold differ)
        (Character("\u{0152}"), 1000, 1000), // OE
        (Character("\u{2014}"), 1000, 1000), // emdash
        (Character("\u{20AC}"), 556, 556), //  Euro
    ])
    func highScalarAdvances(_ scalar: Character, _ helvetica: Int, _ bold: Int) throws {
        let value = try #require(scalar.unicodeScalars.first)
        #expect(advance(value, .helvetica) == helvetica)
        #expect(advance(value, .helveticaOblique) == helvetica) // oblique shares Helvetica advances
        #expect(advance(value, .helveticaBold) == bold)
        // The regression this fixes: none of these is the `?` fallback (556) unless
        // the AFM genuinely says so (the Euro is 556 by coincidence).
        if helvetica != 556 {
            #expect(advance(value, .helvetica) != 556, "\(value) fell back to the ? width")
        }
    }

    @Test("ASCII quotesingle and grave match the AFM, not the curly-quote width")
    func asciiPunctuationAdvances() {
        // These were both 222 (Helvetica) / 278 (bold), the curly-quote advance. The
        // AFM straight quote and grave are narrower and wider respectively.
        #expect(advance("'", .helvetica) == 191)
        #expect(advance("'", .helveticaBold) == 238)
        #expect(advance("`", .helvetica) == 333)
        #expect(advance("`", .helveticaBold) == 333)
    }

    @Test("Courier is monospaced at 600 for every WinAnsi scalar")
    func courierIsMonospaced() throws {
        for scalar in ["A", "\u{00C6}", "\u{00BD}", "\u{20AC}", "\u{2014}", " "] {
            #expect(try advance(Unicode.Scalar(#require(scalar.unicodeScalars.first)), .courier) == 600)
        }
    }
}
