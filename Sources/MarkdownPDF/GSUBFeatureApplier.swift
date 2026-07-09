import Foundation

/// Applies a GSUB feature's lookups over a glyph buffer, independent of script. Single
/// and ligature lookups substitute directly; contextual lookups (type 5/6, format 3)
/// match a window and run their nested single substitutions, skipping marks when the
/// lookup sets `IgnoreMarks`. Used by the Arabic shaper (positional forms feed it the
/// `rlig`/`ccmp` features) and the Hebrew shaper (`ccmp` composition).
struct GSUBFeatureApplier {
    var gsub: GSUBTable
    /// Glyph classes for honoring `IgnoreMarks`; nil degrades to no mark skipping.
    var gdef: GDEFTable?
    /// The font's glyph count, to reject an out-of-range substitute glyph.
    var numGlyphs: UInt16

    /// GSUB/GPOS lookup flag bit that tells a lookup to skip mark glyphs (GDEF class 3)
    /// when matching, so a contextual rule reaches across an interposed mark.
    private static let ignoreMarksFlag: UInt16 = 0x0008

    /// Applies every lookup of `feature`, in LookupList (apply) order, over the buffer.
    func apply(feature: String, to glyphs: [ShapedGlyph]) -> [ShapedGlyph] {
        var buffer = glyphs
        for lookupIndex in gsub.orderedLookupIndices(feature: feature) {
            guard let lookup = gsub.parsedLookup(at: lookupIndex) else {
                continue
            }
            buffer = applyLookup(lookup, to: buffer)
        }
        return buffer
    }

    private func applyLookup(_ lookup: GSUBTable.ParsedLookup, to glyphs: [ShapedGlyph]) -> [ShapedGlyph] {
        switch lookup.kind {
        case let .single(map):
            glyphs.map { glyph in
                guard let substitute = map[glyph.glyphID], substitute != 0, substitute < numGlyphs else {
                    return glyph
                }
                var updated = glyph
                updated.glyphID = substitute
                return updated
            }
        case let .ligature(rules):
            applyLigatures(rules, to: glyphs)
        case let .contextual(rules):
            applyContextual(rules, to: glyphs, ignoreMarks: lookup.lookupFlag & Self.ignoreMarksFlag != 0)
        case .unsupported:
            glyphs
        }
    }

    /// Applies coverage-based (format 3) contextual rules over the buffer. A lookup that
    /// sets `IgnoreMarks` skips mark glyphs (GDEF class 3) when matching, so a contextual
    /// rule reaches across an interposed mark. On a match every nested single
    /// substitution named by the rule's `SequenceLookupRecord`s is applied at its
    /// matched buffer position; nested lookups of other types are a documented gap.
    private func applyContextual(
        _ rules: [GSUBContextualRule],
        to glyphs: [ShapedGlyph],
        ignoreMarks: Bool,
    ) -> [ShapedGlyph] {
        guard !rules.isEmpty else {
            return glyphs
        }
        let isMark: (UInt16) -> Bool = ignoreMarks ? { gdef?.isMark($0) ?? false } : { _ in false }
        var output = glyphs
        var index = 0
        while index < output.count {
            var advanced = false
            for rule in rules {
                guard let positions = Self.matchedInputPositions(rule, in: output, at: index, isMark: isMark) else {
                    continue
                }
                applyRecords(rule.lookupRecords, at: positions, in: &output)
                index = (positions.last ?? index) + 1
                advanced = true
                break
            }
            if !advanced {
                index += 1
            }
        }
        return output
    }

    /// The buffer positions of `rule`'s input glyphs when its backtrack, input, and
    /// lookahead coverages all match with the input beginning at `index`, or nil. Mark
    /// glyphs (per `isMark`) are skipped between matched positions, so a rule matches
    /// across an interposed mark. Pure in its arguments, so the index math is
    /// unit-testable on its own.
    static func matchedInputPositions(
        _ rule: GSUBContextualRule,
        in glyphs: [ShapedGlyph],
        at index: Int,
        isMark: (UInt16) -> Bool,
    ) -> [Int]? {
        guard rule.input.count >= 1, index < glyphs.count, !isMark(glyphs[index].glyphID),
              rule.input[0].contains(glyphs[index].glyphID)
        else {
            return nil
        }
        var positions = [index]
        for coverage in rule.input.dropFirst() {
            guard let next = nextPosition(after: positions[positions.count - 1], in: glyphs, isMark: isMark),
                  coverage.contains(glyphs[next].glyphID)
            else {
                return nil
            }
            positions.append(next)
        }
        // Backtrack is stored in text order (nearest to input is last), so walk backward
        // matching from the last entry.
        var back = index
        for coverage in rule.backtrack.reversed() {
            guard let previous = previousPosition(before: back, in: glyphs, isMark: isMark),
                  coverage.contains(glyphs[previous].glyphID)
            else {
                return nil
            }
            back = previous
        }
        var ahead = positions[positions.count - 1]
        for coverage in rule.lookahead {
            guard let next = nextPosition(after: ahead, in: glyphs, isMark: isMark),
                  coverage.contains(glyphs[next].glyphID)
            else {
                return nil
            }
            ahead = next
        }
        return positions
    }

    /// Whether `rule` matches at `index` with no mark skipping. Retained for the
    /// contiguous-match unit tests; the applier uses ``matchedInputPositions``.
    static func matches(_ rule: GSUBContextualRule, in glyphs: [ShapedGlyph], at index: Int) -> Bool {
        matchedInputPositions(rule, in: glyphs, at: index, isMark: { _ in false }) != nil
    }

    private static func nextPosition(after index: Int, in glyphs: [ShapedGlyph], isMark: (UInt16) -> Bool) -> Int? {
        var cursor = index + 1
        while cursor < glyphs.count {
            if !isMark(glyphs[cursor].glyphID) {
                return cursor
            }
            cursor += 1
        }
        return nil
    }

    private static func previousPosition(before index: Int, in glyphs: [ShapedGlyph], isMark: (UInt16) -> Bool) -> Int? {
        var cursor = index - 1
        while cursor >= 0 {
            if !isMark(glyphs[cursor].glyphID) {
                return cursor
            }
            cursor -= 1
        }
        return nil
    }

    /// Applies each record's nested single substitution at its matched buffer position.
    /// A record whose `sequenceIndex` falls outside the matched input is skipped (as
    /// HarfBuzz does): a spec-invalid font could otherwise name a position past the
    /// input and substitute a glyph outside the rule's match.
    private func applyRecords(
        _ records: [SequenceLookupRecord],
        at positions: [Int],
        in glyphs: inout [ShapedGlyph],
    ) {
        for record in records {
            let sequenceIndex = Int(record.sequenceIndex)
            guard sequenceIndex < positions.count else {
                continue
            }
            let position = positions[sequenceIndex]
            guard position < glyphs.count,
                  let nested = gsub.parsedLookup(at: record.lookupListIndex),
                  case let .single(map) = nested.kind,
                  let substitute = map[glyphs[position].glyphID],
                  substitute != 0, substitute < numGlyphs
            else {
                continue
            }
            glyphs[position].glyphID = substitute
        }
    }

    /// Collapses a matched run of component glyphs into the ligature glyph, longest
    /// match first, unioning the components' source ranges.
    private func applyLigatures(_ rules: [GSUBTable.LigatureRule], to glyphs: [ShapedGlyph]) -> [ShapedGlyph] {
        guard !rules.isEmpty else {
            return glyphs
        }
        let rulesByFirst = Dictionary(grouping: rules) { $0.componentGlyphIDs[0] }
            .mapValues { $0.sorted { $0.componentGlyphIDs.count > $1.componentGlyphIDs.count } }

        var output: [ShapedGlyph] = []
        var index = 0
        while index < glyphs.count {
            var matched = false
            if let candidates = rulesByFirst[glyphs[index].glyphID] {
                for rule in candidates {
                    let end = index + rule.componentGlyphIDs.count
                    // Skip a ligature whose output is .notdef or past the glyph count
                    // (same out-of-range guard as the single-substitution path).
                    guard end <= glyphs.count,
                          rule.ligatureGlyphID != 0,
                          rule.ligatureGlyphID < numGlyphs
                    else {
                        continue
                    }
                    let componentsMatch = zip(rule.componentGlyphIDs, glyphs[index ..< end])
                        .allSatisfy { expected, glyph in expected == glyph.glyphID }
                    guard componentsMatch else {
                        continue
                    }
                    let lower = glyphs[index].sourceScalarRange.lowerBound
                    let upper = glyphs[end - 1].sourceScalarRange.upperBound
                    output.append(ShapedGlyph(glyphID: rule.ligatureGlyphID, sourceScalarRange: lower ..< upper))
                    index = end
                    matched = true
                    break
                }
            }
            if !matched {
                output.append(glyphs[index])
                index += 1
            }
        }
        return output
    }
}
