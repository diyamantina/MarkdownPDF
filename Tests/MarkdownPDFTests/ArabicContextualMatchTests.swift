import Foundation
@testable import MarkdownPDF
import Testing

/// Unit witness for the chained-context matcher (`ArabicShaper.matches`), which the
/// fixture's only applied contextual lookup (unchained) does not exercise. These pin
/// the backtrack and lookahead index math directly, so a regression there (e.g. a
/// flipped backtrack offset or a dropped lookahead check) fails a test even though the
/// end-to-end lam-alef parity would not notice.
@Suite("Arabic contextual matcher")
struct ArabicContextualMatchTests {
    private func glyphs(_ ids: [UInt16]) -> [ArabicShaper.ShapedGlyph] {
        ids.enumerated().map { index, id in
            ArabicShaper.ShapedGlyph(glyphID: id, sourceScalarRange: index ..< index + 1)
        }
    }

    @Test("Input-only rule matches only where every input coverage holds")
    func inputOnlyRule() {
        let rule = GSUBContextualRule(backtrack: [], input: [[10], [20]], lookahead: [], lookupRecords: [])
        let buffer = glyphs([5, 10, 20, 30])
        #expect(ArabicShaper.matches(rule, in: buffer, at: 1))
        #expect(!ArabicShaper.matches(rule, in: buffer, at: 0)) // 5,10 != 10,20
        #expect(!ArabicShaper.matches(rule, in: buffer, at: 2)) // 20,30 != 10,20
        // Input running past the buffer end never matches.
        #expect(!ArabicShaper.matches(rule, in: buffer, at: 3))
    }

    @Test("Backtrack must match the glyphs immediately before the input, in text order")
    func backtrackMatchesInTextOrder() {
        // backtrack stored text order: [7, 8] means glyph 7 two before input, 8 one
        // before. So at input index 3 the buffer must read [.., 7, 8, INPUT..].
        let rule = GSUBContextualRule(backtrack: [[7], [8]], input: [[9]], lookahead: [], lookupRecords: [])
        #expect(ArabicShaper.matches(rule, in: glyphs([1, 7, 8, 9, 2]), at: 3))
        // Wrong order (8 then 7) must not match: catches a flipped backtrack offset.
        #expect(!ArabicShaper.matches(rule, in: glyphs([1, 8, 7, 9, 2]), at: 3))
        // Not enough room before the input for the backtrack.
        #expect(!ArabicShaper.matches(rule, in: glyphs([8, 9, 2]), at: 1))
    }

    @Test("Lookahead must match the glyphs immediately after the input")
    func lookaheadMatchesAfterInput() {
        let rule = GSUBContextualRule(backtrack: [], input: [[9]], lookahead: [[11], [12]], lookupRecords: [])
        #expect(ArabicShaper.matches(rule, in: glyphs([9, 11, 12, 3]), at: 0))
        // Wrong lookahead content must not match: catches a dropped lookahead check.
        #expect(!ArabicShaper.matches(rule, in: glyphs([9, 11, 99, 3]), at: 0))
        // Not enough room after the input for the lookahead.
        #expect(!ArabicShaper.matches(rule, in: glyphs([9, 11]), at: 0))
    }

    @Test("A full backtrack + input + lookahead rule matches only in the exact context")
    func fullChainedRule() {
        let rule = GSUBContextualRule(
            backtrack: [[7]],
            input: [[9], [10]],
            lookahead: [[13]],
            lookupRecords: [],
        )
        #expect(ArabicShaper.matches(rule, in: glyphs([7, 9, 10, 13]), at: 1))
        #expect(!ArabicShaper.matches(rule, in: glyphs([8, 9, 10, 13]), at: 1)) // wrong backtrack
        #expect(!ArabicShaper.matches(rule, in: glyphs([7, 9, 99, 13]), at: 1)) // wrong second input
        #expect(!ArabicShaper.matches(rule, in: glyphs([7, 9, 10, 99]), at: 1)) // wrong lookahead
    }
}
