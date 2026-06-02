@testable import MarkdownPDF
import Testing

@Suite("Line break opportunity detector")
struct LineBreakOpportunityDetectorTests {
    @Test("Keeps Latin whitespace wrapping compatible with existing tokenizer")
    func keepsLatinWhitespaceWrappingCompatibleWithExistingTokenizer() {
        let detector = LineBreakOpportunityDetector()

        #expect(detector.segments(in: "Alpha beta\tgamma") == ["Alpha ", "beta ", "gamma"])
        #expect(detector.opportunities(in: "Alpha beta\tgamma") == [
            LineBreakOpportunityDetector.Opportunity(scalarOffset: 6, kind: .allowed),
            LineBreakOpportunityDetector.Opportunity(scalarOffset: 11, kind: .allowed),
        ])
    }

    @Test("Keeps mandatory line breaks as separate segments")
    func keepsMandatoryLineBreaksAsSeparateSegments() {
        let detector = LineBreakOpportunityDetector()

        #expect(detector.segments(in: "Alpha\nBeta") == ["Alpha", "\n", "Beta"])
        #expect(detector.opportunities(in: "Alpha\nBeta") == [
            LineBreakOpportunityDetector.Opportunity(scalarOffset: 6, kind: .mandatory),
        ])
    }

    @Test("Adds no-space script opportunities")
    func addsNoSpaceScriptOpportunities() {
        let detector = LineBreakOpportunityDetector()

        #expect(detector.segments(in: "ภาษาไทย") == ["ภ", "า", "ษ", "า", "ไ", "ท", "ย"])
        #expect(detector.opportunities(in: "ภาษาไทย") == [
            LineBreakOpportunityDetector.Opportunity(scalarOffset: 1, kind: .allowed),
            LineBreakOpportunityDetector.Opportunity(scalarOffset: 2, kind: .allowed),
            LineBreakOpportunityDetector.Opportunity(scalarOffset: 3, kind: .allowed),
            LineBreakOpportunityDetector.Opportunity(scalarOffset: 4, kind: .allowed),
            LineBreakOpportunityDetector.Opportunity(scalarOffset: 5, kind: .allowed),
            LineBreakOpportunityDetector.Opportunity(scalarOffset: 6, kind: .allowed),
        ])
        #expect(detector.segments(in: "កខគ") == ["ក", "ខ", "គ"])
    }

    @Test("Adds CJK ID-class break opportunities")
    func addsCJKIDClassBreakOpportunities() {
        let detector = LineBreakOpportunityDetector()

        #expect(detector.segments(in: "漢字仮名") == ["漢", "字", "仮", "名"])
        #expect(detector.opportunities(in: "漢字仮名") == [
            LineBreakOpportunityDetector.Opportunity(scalarOffset: 1, kind: .allowed),
            LineBreakOpportunityDetector.Opportunity(scalarOffset: 2, kind: .allowed),
            LineBreakOpportunityDetector.Opportunity(scalarOffset: 3, kind: .allowed),
        ])
        #expect(detector.segments(in: "かなカナ") == ["か", "な", "カ", "ナ"])
        #expect(detector.segments(in: "한글") == ["한", "글"])
    }

    @Test("Protects CJK opening and closing punctuation boundaries")
    func protectsCJKOpeningAndClosingPunctuationBoundaries() {
        let detector = LineBreakOpportunityDetector()

        #expect(detector.segments(in: "「漢字」仮") == ["「漢", "字」", "仮"])
        #expect(detector.opportunities(in: "「漢字」仮") == [
            LineBreakOpportunityDetector.Opportunity(scalarOffset: 2, kind: .allowed),
            LineBreakOpportunityDetector.Opportunity(scalarOffset: 4, kind: .allowed),
        ])
        #expect(detector.segments(in: "漢。字") == ["漢。", "字"])
    }

    @Test("Does not split combining mark clusters")
    func doesNotSplitCombiningMarkClusters() {
        let detector = LineBreakOpportunityDetector()

        #expect(detector.segments(in: "ก\u{0E49}ก") == ["ก\u{0E49}", "ก"])
        #expect(detector.opportunities(in: "ก\u{0E49}ก") == [
            LineBreakOpportunityDetector.Opportunity(scalarOffset: 2, kind: .allowed),
        ])
        #expect(detector.segments(in: "e\u{0301}e") == ["e\u{0301}e"])
        #expect(detector.opportunities(in: "e\u{0301}e").isEmpty)
    }

    @Test("Protects punctuation boundaries")
    func protectsPunctuationBoundaries() {
        let detector = LineBreakOpportunityDetector()

        #expect(detector.segments(in: "Hello,world") == ["Hello,world"])
        #expect(detector.opportunities(in: "Hello,world").isEmpty)
        #expect(detector.segments(in: "(Alpha beta)") == ["(Alpha ", "beta)"])
    }
}
