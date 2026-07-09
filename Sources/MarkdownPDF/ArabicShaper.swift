import Foundation

/// Arabic (cursive) shaping core: resolves each letter's positional form from the
/// Unicode joining algorithm, then applies the font's GSUB `isol`/`init`/`medi`/
/// `fina` single substitutions and the `rlig` ligatures (lam-alef). It produces the
/// logical-order glyph ids a correct shaper (HarfBuzz) produces; RTL visual ordering,
/// advances, and `/ToUnicode` are the caller's job and are not done here.
struct ArabicShaper {
    struct ShapedGlyph: Equatable {
        var glyphID: UInt16
        /// The source scalar indices this output glyph came from (a range so a
        /// ligature can record the cluster it consumed), for a later ToUnicode step.
        var sourceScalarRange: Range<Int>
    }

    // MARK: - Joining state machine (pure, testable)

    /// Whether the run contains any character that participates in cursive joining,
    /// i.e. is worth routing through this shaper.
    static func containsJoiningScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch ArabicJoiningType.of(scalar) {
            case .dualJoining, .rightJoining, .leftJoining, .joinCausing:
                true
            case .transparent, .nonJoining:
                false
            }
        }
    }

    /// Resolves the positional form of every scalar in logical order. Transparent
    /// marks are skipped when finding a letter's neighbours; non-joining characters
    /// break the cursive chain. Verified against HarfBuzz.
    static func positionalForms(for scalars: [UnicodeScalar]) -> [ArabicPositionalForm] {
        let types = scalars.map(ArabicJoiningType.of)
        var forms = [ArabicPositionalForm](repeating: .unshaped, count: scalars.count)

        for index in scalars.indices {
            let type = types[index]
            switch type {
            case .transparent, .nonJoining:
                continue // keeps its base glyph
            case .dualJoining, .rightJoining, .leftJoining, .joinCausing:
                break
            }

            let previousType = nearestNonTransparentType(in: types, before: index)
            let nextType = nearestNonTransparentType(in: types, after: index)

            let joinsPrevious: Bool = if let previousType {
                canJoinLeft(previousType) && canJoinRight(type)
            } else {
                false
            }
            let joinsNext: Bool = if let nextType {
                canJoinLeft(type) && canJoinRight(nextType)
            } else {
                false
            }

            forms[index] = form(for: type, joinsPrevious: joinsPrevious, joinsNext: joinsNext)
        }
        return forms
    }

    /// Can join to the character on its left (visually), i.e. the following
    /// character in logical order.
    private static func canJoinLeft(_ type: ArabicJoiningType) -> Bool {
        switch type {
        case .dualJoining, .leftJoining, .joinCausing: true
        case .rightJoining, .transparent, .nonJoining: false
        }
    }

    /// Can join to the character on its right (visually), i.e. the preceding
    /// character in logical order.
    private static func canJoinRight(_ type: ArabicJoiningType) -> Bool {
        switch type {
        case .dualJoining, .rightJoining, .joinCausing: true
        case .leftJoining, .transparent, .nonJoining: false
        }
    }

    private static func form(
        for type: ArabicJoiningType,
        joinsPrevious: Bool,
        joinsNext: Bool,
    ) -> ArabicPositionalForm {
        switch type {
        case .dualJoining, .joinCausing:
            if joinsPrevious, joinsNext { return .medial }
            if joinsPrevious { return .final }
            if joinsNext { return .initial }
            return .isolated
        case .rightJoining:
            return joinsPrevious ? .final : .isolated
        case .leftJoining:
            return joinsNext ? .initial : .isolated
        case .transparent, .nonJoining:
            return .unshaped
        }
    }

    private static func nearestNonTransparentType(
        in types: [ArabicJoiningType],
        before index: Int,
    ) -> ArabicJoiningType? {
        var cursor = index - 1
        while cursor >= 0 {
            if types[cursor] != .transparent {
                return types[cursor]
            }
            cursor -= 1
        }
        return nil
    }

    private static func nearestNonTransparentType(
        in types: [ArabicJoiningType],
        after index: Int,
    ) -> ArabicJoiningType? {
        var cursor = index + 1
        while cursor < types.count {
            if types[cursor] != .transparent {
                return types[cursor]
            }
            cursor += 1
        }
        return nil
    }

    // MARK: - Full shaping (base glyphs → positional forms → ligatures)

    var fontData: Data
    var metadata: TrueTypeFontParser.Metadata

    /// Shapes `text` into logical-order glyphs. Steps: base glyph per scalar via the
    /// cmap; per-glyph positional-form single substitution (`isol`/`init`/`medi`/
    /// `fina`); then `rlig` ligatures over the resulting glyphs (lam-alef and the
    /// like). Marks pass through in place.
    func shape(_ text: String) throws -> [ShapedGlyph] {
        let scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty else {
            return []
        }

        // Base glyphs, one per scalar, from the font cmap. `.useNotdef` keeps a
        // scalar the font lacks from aborting; the caller decides how to treat it.
        let mapper = TrueTypeGlyphMapper(data: fontData, metadata: metadata, missingGlyphPolicy: .useNotdef)
        let baseGlyphs = try mapper.map(text: text, fontSize: 1).glyphs.map(\.glyphID)
        guard baseGlyphs.count == scalars.count else {
            return zip(baseGlyphs.indices, baseGlyphs).map { index, glyph in
                ShapedGlyph(glyphID: glyph, sourceScalarRange: index ..< index + 1)
            }
        }

        let gsub = try GSUBTable(
            fontData: fontData,
            gsubTableRange: gsubTableRange(),
            scriptTag: "arab",
            numGlyphs: metadata.maxp.numGlyphs,
        )

        // Positional forms.
        let forms = Self.positionalForms(for: scalars)
        var glyphs = zip(baseGlyphs.indices, baseGlyphs).map { index, glyph in
            ShapedGlyph(glyphID: glyph, sourceScalarRange: index ..< index + 1)
        }
        if let gsub {
            for index in glyphs.indices {
                guard let feature = forms[index].featureTag else {
                    continue
                }
                glyphs[index].glyphID = gsub.singleSubstitute(feature: feature, glyph: glyphs[index].glyphID)
            }
            // rlig ligatures (lam-alef, ...) over the positional glyphs.
            glyphs = applyLigatures(gsub.ligatureRules(feature: "rlig"), to: glyphs)
        }
        return glyphs
    }

    private func gsubTableRange() -> Range<Int>? {
        guard let record = metadata.table(named: "GSUB") else {
            return nil
        }
        let start = Int(record.offset)
        let end = start + Int(record.length)
        guard start >= 0, end <= fontData.count, start <= end else {
            return nil
        }
        return start ..< end
    }

    /// Applies ligature rules with longest-match-first at each position. A matched
    /// run of component glyphs collapses to the ligature glyph, whose source range
    /// is the union of the components' ranges.
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
                          rule.ligatureGlyphID < metadata.maxp.numGlyphs
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
