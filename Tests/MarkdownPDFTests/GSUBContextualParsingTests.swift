import Foundation
@testable import MarkdownPDF
import Testing

/// Structural parity witness for the GSUB contextual (type 5/6, format 3) parser: the
/// rules it reads from the Noto Naskh fixture must match, field for field, what an
/// independent tool (fontTools) decompiles from the same table. Ground-truth values
/// were taken from `fontTools` and are pinned here.
@Suite("GSUB contextual parsing")
struct GSUBContextualParsingTests {
    private func notoGSUB() throws -> GSUBTable {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/NotoNaskhArabic-Regular.ttf")
        let data = try Data(contentsOf: url)
        let metadata = try TrueTypeFontParser().parse(data)
        let record = try #require(metadata.table(named: "GSUB"))
        let start = Int(record.offset)
        let gsub = try GSUBTable(
            fontData: data,
            gsubTableRange: start ..< (start + Int(record.length)),
            scriptTag: "arab",
            numGlyphs: metadata.maxp.numGlyphs,
        )
        return try #require(gsub)
    }

    @Test("Reads the rlig type-5 contextual lookup (14) exactly as fontTools does")
    func readsType5ContextualLookup() throws {
        let gsub = try notoGSUB()

        // rlig runs lookup 14 (contextual refinement) then 15 (lam-alef ligature).
        #expect(gsub.orderedLookupIndices(feature: "rlig") == [14, 15])

        let lookup = try #require(gsub.parsedLookup(at: 14))
        #expect(lookup.lookupFlag == 8) // IgnoreMarks
        guard case let .contextual(rules) = lookup.kind else {
            Issue.record("lookup 14 should be contextual")
            return
        }
        // Two subtables -> two format-3 rules, each with two input coverages and no
        // backtrack/lookahead (type 5 is unchained).
        #expect(rules.count == 2)
        for rule in rules {
            #expect(rule.backtrack.isEmpty)
            #expect(rule.lookahead.isEmpty)
            #expect(rule.input.count == 2)
        }
        // Subtable 0: input coverage sizes 7 and 10; records apply lookup 2 at input
        // positions 0 and 1.
        #expect(rules[0].input[0] == [447, 452, 458, 464, 470, 475, 698])
        #expect(rules[0].input[1].count == 10)
        #expect(rules[0].lookupRecords == [
            SequenceLookupRecord(sequenceIndex: 0, lookupListIndex: 2),
            SequenceLookupRecord(sequenceIndex: 1, lookupListIndex: 2),
        ])
        // Subtable 1: a different initial coverage, applying lookup 3.
        #expect(rules[1].input[0] == [444, 451, 456, 462, 468, 474, 697])
        #expect(rules[1].lookupRecords == [
            SequenceLookupRecord(sequenceIndex: 0, lookupListIndex: 3),
            SequenceLookupRecord(sequenceIndex: 1, lookupListIndex: 3),
        ])

        // The nested lookups the records name are real single substitutions.
        for index: UInt16 in [2, 3] {
            let nested = try #require(gsub.parsedLookup(at: index))
            guard case .single = nested.kind else {
                Issue.record("nested lookup \(index) should be a single substitution")
                return
            }
        }
    }

    @Test("Reads the ccmp type-6 chained contextual lookup (24) exactly as fontTools does")
    func readsType6ChainedContextualLookup() throws {
        let gsub = try notoGSUB()
        let lookup = try #require(gsub.parsedLookup(at: 24))
        guard case let .contextual(rules) = lookup.kind else {
            Issue.record("lookup 24 should be contextual")
            return
        }
        #expect(rules.count == 2)
        // Subtable 0: no backtrack, one input, one lookahead, applying lookup 25.
        #expect(rules[0].backtrack.isEmpty)
        #expect(rules[0].input.count == 1)
        #expect(rules[0].lookahead.count == 1)
        #expect(rules[0].lookupRecords == [SequenceLookupRecord(sequenceIndex: 0, lookupListIndex: 25)])
        // Subtable 1: two lookahead coverages, applying lookup 26.
        #expect(rules[1].lookahead.count == 2)
        #expect(rules[1].lookupRecords == [SequenceLookupRecord(sequenceIndex: 0, lookupListIndex: 26)])
    }

    @Test("A class-based (format 2) contextual lookup is a documented, non-crashing gap")
    func classBasedContextualIsDeferred() throws {
        let gsub = try notoGSUB()
        // Lookup 10 (ccmp) is type 6 format 2 (class-based), which the format-3 parser
        // does not yet read: it must surface as a contextual lookup with no rules, not
        // a crash or a wrong parse.
        let lookup = try #require(gsub.parsedLookup(at: 10))
        guard case let .contextual(rules) = lookup.kind else {
            Issue.record("lookup 10 should be a (rule-less) contextual lookup")
            return
        }
        #expect(rules.isEmpty)
    }
}
