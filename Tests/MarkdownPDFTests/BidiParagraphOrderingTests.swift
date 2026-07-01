@testable import MarkdownPDF
import Testing

@Suite("Bidi paragraph ordering")
struct BidiParagraphOrderingTests {
    @Test("Keeps LTR paragraphs in logical order")
    func keepsLeftToRightParagraphsInLogicalOrder() throws {
        let paragraph = try BidiParagraphOrdering().order("Alpha 123 beta")

        #expect(paragraph.baseDirection == .leftToRight)
        #expect(paragraph.visualRuns == [
            BidiParagraphOrdering.Run(
                sourceScalarRange: 0 ..< 14,
                sourceText: "Alpha 123 beta",
                displayText: "Alpha 123 beta",
                direction: .leftToRight,
                embeddingLevel: 0,
            ),
        ])
    }

    @Test("Reverses RTL paragraph runs for visual order")
    func reversesRightToLeftParagraphRunsForVisualOrder() throws {
        let paragraph = try BidiParagraphOrdering().order(
            BidiFixtureText.hebrewABC + " " + BidiFixtureText.hebrewDE,
        )

        #expect(paragraph.baseDirection == .rightToLeft)
        #expect(paragraph.visualRuns == [
            BidiParagraphOrdering.Run(
                sourceScalarRange: 0 ..< 6,
                sourceText: BidiFixtureText.hebrewABC + " " + BidiFixtureText.hebrewDE,
                displayText: BidiFixtureText.hebrewDEVisual + " " + BidiFixtureText.hebrewABCVisual,
                direction: .rightToLeft,
                embeddingLevel: 1,
            ),
        ])
    }

    @Test("Orders mixed LTR and RTL runs in an LTR paragraph")
    func ordersMixedRunsInLeftToRightParagraph() throws {
        let paragraph = try BidiParagraphOrdering().order("abc " + BidiFixtureText.hebrewAB + " def")

        #expect(paragraph.baseDirection == .leftToRight)
        #expect(paragraph.visualRuns == [
            BidiParagraphOrdering.Run(
                sourceScalarRange: 0 ..< 4,
                sourceText: "abc ",
                displayText: "abc ",
                direction: .leftToRight,
                embeddingLevel: 0,
            ),
            BidiParagraphOrdering.Run(
                sourceScalarRange: 4 ..< 6,
                sourceText: BidiFixtureText.hebrewAB,
                displayText: BidiFixtureText.hebrewABVisual,
                direction: .rightToLeft,
                embeddingLevel: 1,
            ),
            BidiParagraphOrdering.Run(
                sourceScalarRange: 6 ..< 10,
                sourceText: " def",
                displayText: " def",
                direction: .leftToRight,
                embeddingLevel: 0,
            ),
        ])
    }

    @Test("Keeps numbers LTR inside an RTL paragraph")
    func keepsNumbersLeftToRightInsideRightToLeftParagraph() throws {
        let paragraph = try BidiParagraphOrdering().order(BidiFixtureText.hebrewAB + " 123 " + BidiFixtureText.hebrewGD)

        #expect(paragraph.baseDirection == .rightToLeft)
        #expect(paragraph.visualRuns == [
            BidiParagraphOrdering.Run(
                sourceScalarRange: 6 ..< 9,
                sourceText: " " + BidiFixtureText.hebrewGD,
                displayText: BidiFixtureText.hebrewGDVisual + " ",
                direction: .rightToLeft,
                embeddingLevel: 1,
            ),
            BidiParagraphOrdering.Run(
                sourceScalarRange: 3 ..< 6,
                sourceText: "123",
                displayText: "123",
                direction: .leftToRight,
                embeddingLevel: 2,
            ),
            BidiParagraphOrdering.Run(
                sourceScalarRange: 0 ..< 3,
                sourceText: BidiFixtureText.hebrewAB + " ",
                displayText: " " + BidiFixtureText.hebrewABVisual,
                direction: .rightToLeft,
                embeddingLevel: 1,
            ),
        ])
    }

    @Test("Keeps Arabic-Indic numbers LTR inside an RTL paragraph")
    func keepsArabicIndicNumbersLeftToRightInsideRightToLeftParagraph() throws {
        let paragraph = try BidiParagraphOrdering().order(
            BidiFixtureText.hebrewAB + " " + BidiFixtureText.arabicIndic12 + " " + BidiFixtureText.hebrewGD,
        )

        #expect(paragraph.baseDirection == .rightToLeft)
        #expect(paragraph.visualRuns == [
            BidiParagraphOrdering.Run(
                sourceScalarRange: 5 ..< 8,
                sourceText: " " + BidiFixtureText.hebrewGD,
                displayText: BidiFixtureText.hebrewGDVisual + " ",
                direction: .rightToLeft,
                embeddingLevel: 1,
            ),
            BidiParagraphOrdering.Run(
                sourceScalarRange: 3 ..< 5,
                sourceText: BidiFixtureText.arabicIndic12,
                displayText: BidiFixtureText.arabicIndic12,
                direction: .leftToRight,
                embeddingLevel: 2,
            ),
            BidiParagraphOrdering.Run(
                sourceScalarRange: 0 ..< 3,
                sourceText: BidiFixtureText.hebrewAB + " ",
                displayText: " " + BidiFixtureText.hebrewABVisual,
                direction: .rightToLeft,
                embeddingLevel: 1,
            ),
        ])
    }

    @Test("Mirrors paired punctuation in RTL visual runs")
    func mirrorsPairedPunctuationInRightToLeftVisualRuns() throws {
        let paragraph = try BidiParagraphOrdering().order(BidiFixtureText.hebrewAB + " (123) " + BidiFixtureText.hebrewGD)

        #expect(paragraph.baseDirection == .rightToLeft)
        #expect(paragraph.visualRuns.map(\.displayText).joined() == BidiFixtureText.hebrewGDVisual + " (123) " + BidiFixtureText.hebrewABVisual)
    }

    @Test("Detects RTL text")
    func detectsRightToLeftText() {
        let ordering = BidiParagraphOrdering()

        #expect(ordering.containsRightToLeftText(BidiFixtureText.hebrewAB))
        #expect(ordering.containsRightToLeftText("CODE " + BidiFixtureText.arabicSalam))
        #expect(!ordering.containsRightToLeftText("CODE 123"))
    }

    @Test("Rejects explicit bidi formatting controls")
    func rejectsExplicitBidiFormattingControls() throws {
        let controls: [UInt32] = [
            0x061C,
            0x200E,
            0x200F,
            0x202A,
            0x202B,
            0x202C,
            0x202D,
            0x202E,
            0x2066,
            0x2067,
            0x2068,
            0x2069,
        ]

        for value in controls {
            guard let control = UnicodeScalar(value) else {
                Issue.record("Invalid bidi control fixture")
                continue
            }

            do {
                _ = try BidiParagraphOrdering().order("abc\(String(control))def")
                Issue.record("Expected unsupported bidi control error")
            } catch let error as BidiParagraphOrdering.ValidationError {
                guard case let .unsupportedBidiControl(scalar, scalarOffset) = error else {
                    Issue.record("Unexpected bidi error")
                    return
                }
                #expect(scalar.value == value)
                #expect(scalarOffset == 3)
            }
        }
    }
}

private enum BidiFixtureText {
    static let hebrewAB = "\u{05D0}\u{05D1}"
    static let hebrewABC = "\u{05D0}\u{05D1}\u{05D2}"
    static let hebrewDE = "\u{05D3}\u{05D4}"
    static let hebrewGD = "\u{05D2}\u{05D3}"
    static let hebrewABVisual = "\u{05D1}\u{05D0}"
    static let hebrewABCVisual = "\u{05D2}\u{05D1}\u{05D0}"
    static let hebrewDEVisual = "\u{05D4}\u{05D3}"
    static let hebrewGDVisual = "\u{05D3}\u{05D2}"
    static let arabicIndic12 = "\u{0661}\u{0662}"
    static let arabicSalam = "\u{0633}\u{0644}\u{0627}\u{0645}"
}
