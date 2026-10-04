@testable import MarkdownPDF
import Testing

/// Oracle: hand-written matches. Each case lists the lines and the exact
/// `(line, term)` hits the documented whole-word, case and diacritic-insensitive
/// rule must give.
@Suite("Index term matcher")
struct IndexTermMatcherTests {
    private func hits(_ terms: [String], in lines: [String]) -> [String] {
        let matcher = IndexTermMatcher(terms: terms.map { term in
            (IndexRegistry.entry(for: term)?.id ?? IndexEntryID(main: ""), term)
        })
        return matcher.matches(inLines: lines)
            .map { "\($0.line):\($0.entry.main)" }
            .sorted()
    }

    @Test("Whole words only, any case")
    func wholeWords() {
        #expect(hits(["layer"], in: ["The Layer tree and LAYER, layers, layering, relayer."]) == ["0:layer", "0:layer"])
        #expect(hits(["layer"], in: ["layer"]) == ["0:layer"])
        #expect(hits(["layer"], in: ["(layer)", "layer's", "layer-tree", "layer_tree", "layer2", "2layer"]) == [
            "0:layer", "1:layer", "2:layer", "3:layer",
        ])
        // Only letters and digits continue a word, so punctuation, hyphen and underscore separate.
    }

    @Test("Diacritics do not matter, in either direction")
    func diacritics() {
        #expect(hits(["cafe"], in: ["a Caf\u{E9} and a cafe and Cafe\u{301}"]) == ["0:cafe", "0:cafe", "0:cafe"])
        #expect(hits(["caf\u{E9}"], in: ["a cafe"]) == ["0:cafe"])
    }

    @Test("A multi-word term matches across whitespace and line breaks, on its first line")
    func multiWord() {
        #expect(hits(["layer tree"], in: ["see the layer   tree here"]) == ["0:layer tree"])
        #expect(hits(["layer tree"], in: ["see the layer", "tree here", "layer", "trees"]) == ["0:layer tree"])
        #expect(hits(["layer tree"], in: ["layer", "treehouse"]) == [])
    }

    @Test("Terms that start or end with punctuation match without a word boundary there")
    func punctuationEdges() {
        #expect(hits(["C++"], in: ["we like C++ a lot", "C+++"]) == ["0:c++", "1:c++"])
        #expect(hits(["C++"], in: ["ABC++"]) == [])
    }

    @Test("Overlapping terms are all reported")
    func overlapping() {
        #expect(hits(["layer", "layer tree"], in: ["the layer tree"]) == ["0:layer", "0:layer tree"])
    }

    @Test("An empty list or empty text finds nothing")
    func empty() {
        #expect(hits([], in: ["layer"]) == [])
        #expect(hits(["layer"], in: []) == [])
        #expect(hits(["layer"], in: [""]) == [])
        #expect(hits(["   "], in: ["layer"]) == [])
    }

    @Test("Entry terms split at the first greater-than sign")
    func entryParsing() throws {
        let plain = try #require(IndexRegistry.entry(for: "  Layer  "))
        #expect(plain.main == "Layer")
        #expect(plain.sub == nil)

        let nested = try #require(IndexRegistry.entry(for: "animation > timing function > easing"))
        #expect(nested.main == "animation")
        #expect(nested.sub == "timing function > easing")

        let emptySub = try #require(IndexRegistry.entry(for: "layer >"))
        #expect(emptySub.main == "layer")
        #expect(emptySub.sub == nil)

        #expect(IndexRegistry.entry(for: "") == nil)
        #expect(IndexRegistry.entry(for: "  > sub") == nil)
    }
}
