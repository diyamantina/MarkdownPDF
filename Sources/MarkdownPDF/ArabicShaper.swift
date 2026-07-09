import Foundation

/// Arabic (cursive) shaping core: resolves each letter's positional form from the
/// Unicode joining algorithm, then applies the font's GSUB `isol`/`init`/`medi`/
/// `fina` single substitutions and the `rlig` lookups in order, a coverage-based
/// contextual (type 5/6) refinement (e.g. the lam-alef glyph pair) followed by the
/// type-4 ligature. It produces the logical-order glyph ids a correct shaper
/// (HarfBuzz) produces; RTL visual ordering, advances, and `/ToUnicode` are the
/// caller's job and are not done here.
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

    /// The font's `arab` GSUB, parsed once at construction (nil when the font has no
    /// GSUB). Shaping and ``canShapeArabic`` reuse it, so the table is not re-parsed
    /// on the per-run, per-measurement hot path.
    private let gsub: GSUBTable?

    init(fontData: Data, metadata: TrueTypeFontParser.Metadata) {
        self.fontData = fontData
        self.metadata = metadata
        // Arabic shaping is an optional capability: a font with no `arab` GSUB (most
        // fonts) or a malformed one is simply not Arabic-shapeable and falls back to
        // the ordinary base-glyph path, so a parse failure is an expected
        // "not eligible" state, not a swallowed error. The font still renders.
        do {
            gsub = try GSUBTable(
                fontData: fontData,
                gsubTableRange: Self.gsubTableRange(fontData: fontData, metadata: metadata),
                scriptTag: "arab",
                numGlyphs: metadata.maxp.numGlyphs,
            )
        } catch {
            gsub = nil
        }
    }

    /// Whether this font actually carries the Arabic positional-form GSUB features,
    /// i.e. shaping it will do something. A font without them (a Latin font, or a
    /// synthetic test font) gains nothing from the shaper, so the caller keeps it on
    /// the ordinary path rather than routing it here.
    var canShapeArabic: Bool {
        gsub?.hasArabicJoiningFeatures ?? false
    }

    /// Shapes `text` into logical-order glyphs. Steps: base glyph per scalar via the
    /// cmap; per-glyph positional-form single substitution (`isol`/`init`/`medi`/
    /// `fina`); then `rlig` ligatures over the resulting glyphs (lam-alef and the
    /// like). Marks pass through in place.
    func shape(
        _ text: String,
        missingGlyphPolicy: TrueTypeGlyphMapper.MissingGlyphPolicy = .useNotdef,
    ) throws -> [ShapedGlyph] {
        let scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty else {
            return []
        }

        // Base glyphs, one per scalar, from the font cmap. The caller's policy
        // governs a scalar the font lacks: `.reject` refuses (conformance) and
        // `.useNotdef` keeps it from aborting the document.
        let mapper = TrueTypeGlyphMapper(data: fontData, metadata: metadata, missingGlyphPolicy: missingGlyphPolicy)
        let baseGlyphs = try mapper.map(text: text, fontSize: 1).glyphs.map(\.glyphID)
        guard baseGlyphs.count == scalars.count else {
            return zip(baseGlyphs.indices, baseGlyphs).map { index, glyph in
                ShapedGlyph(glyphID: glyph, sourceScalarRange: index ..< index + 1)
            }
        }

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
            // rlig: apply its lookups in LookupList order (a contextual refinement of
            // type 5/6, then the lam-alef ligature of type 4). Running the contextual
            // lookup first lets the font swap in its exact contextual glyph pair, so
            // the ligature that follows is the font's intended one rather than only the
            // canonical presentation form.
            glyphs = applyFeatureLookups("rlig", to: glyphs, gsub: gsub)
        }
        return glyphs
    }

    /// Applies every lookup of `feature`, in LookupList (apply) order, over the glyph
    /// buffer. Single and ligature lookups substitute as on the direct paths;
    /// contextual lookups (type 5/6) match a window and run their nested lookups.
    private func applyFeatureLookups(
        _ feature: String,
        to glyphs: [ShapedGlyph],
        gsub: GSUBTable,
    ) -> [ShapedGlyph] {
        var buffer = glyphs
        for lookupIndex in gsub.orderedLookupIndices(feature: feature) {
            guard let lookup = gsub.parsedLookup(at: lookupIndex) else {
                continue
            }
            buffer = applyLookup(lookup, to: buffer, gsub: gsub)
        }
        return buffer
    }

    private func applyLookup(
        _ lookup: GSUBTable.ParsedLookup,
        to glyphs: [ShapedGlyph],
        gsub: GSUBTable,
    ) -> [ShapedGlyph] {
        switch lookup.kind {
        case let .single(map):
            glyphs.map { glyph in
                guard let substitute = map[glyph.glyphID], substitute != 0, substitute < metadata.maxp.numGlyphs else {
                    return glyph
                }
                var updated = glyph
                updated.glyphID = substitute
                return updated
            }
        case let .ligature(rules):
            applyLigatures(rules, to: glyphs)
        case let .contextual(rules):
            applyContextual(rules, to: glyphs, gsub: gsub)
        case .unsupported:
            glyphs
        }
    }

    /// Applies coverage-based (format 3) contextual rules over the buffer. At each
    /// position the rule's backtrack, input, and lookahead coverages must all match
    /// (contiguously: mark skipping via GDEF/lookup flag is a later refinement, so
    /// contextual matches across an interposed mark are conservatively missed rather
    /// than mis-made). On a match every nested single substitution named by the rule's
    /// `SequenceLookupRecord`s is applied at its input position. Nested lookups of
    /// other types are a documented gap (the Noto rlig/ccmp rules use single subs).
    private func applyContextual(
        _ rules: [GSUBContextualRule],
        to glyphs: [ShapedGlyph],
        gsub: GSUBTable,
    ) -> [ShapedGlyph] {
        guard !rules.isEmpty else {
            return glyphs
        }
        var output = glyphs
        var index = 0
        while index < output.count {
            var advanced = false
            for rule in rules where matches(rule, in: output, at: index) {
                applyRecords(rule.lookupRecords, in: &output, inputStart: index, gsub: gsub)
                index += max(rule.input.count, 1)
                advanced = true
                break
            }
            if !advanced {
                index += 1
            }
        }
        return output
    }

    /// Whether `rule`'s backtrack/input/lookahead coverages all match the buffer with
    /// the input beginning at `index`.
    private func matches(_ rule: GSUBContextualRule, in glyphs: [ShapedGlyph], at index: Int) -> Bool {
        let inputEnd = index + rule.input.count
        guard rule.input.count >= 1, inputEnd <= glyphs.count else {
            return false
        }
        for offset in rule.input.indices where !rule.input[offset].contains(glyphs[index + offset].glyphID) {
            return false
        }
        // Backtrack is stored in text order: the last entry is the glyph immediately
        // before the input, so entry `k` sits at `index - (count - k)`.
        guard index >= rule.backtrack.count else {
            return false
        }
        for offset in rule.backtrack.indices {
            let position = index - (rule.backtrack.count - offset)
            if !rule.backtrack[offset].contains(glyphs[position].glyphID) {
                return false
            }
        }
        guard inputEnd + rule.lookahead.count <= glyphs.count else {
            return false
        }
        for offset in rule.lookahead.indices where !rule.lookahead[offset].contains(glyphs[inputEnd + offset].glyphID) {
            return false
        }
        return true
    }

    /// Applies each record's nested single substitution at its input position.
    private func applyRecords(
        _ records: [SequenceLookupRecord],
        in glyphs: inout [ShapedGlyph],
        inputStart: Int,
        gsub: GSUBTable,
    ) {
        for record in records {
            let position = inputStart + Int(record.sequenceIndex)
            guard position < glyphs.count,
                  let nested = gsub.parsedLookup(at: record.lookupListIndex),
                  case let .single(map) = nested.kind,
                  let substitute = map[glyphs[position].glyphID],
                  substitute != 0, substitute < metadata.maxp.numGlyphs
            else {
                continue
            }
            glyphs[position].glyphID = substitute
        }
    }

    /// Shapes `text` into a `ShapedTextMapping` in logical order: one cluster per
    /// output glyph, advances from the font `hmtx` scaled to `fontSize`, and each
    /// cluster's `toUnicodeScalars` the source scalars it consumed (so `/ToUnicode`
    /// recovers the original characters even though glyphs are positional forms and
    /// ligatures). The caller draws these clusters left-to-right for an LTR context
    /// or reversed for an RTL run; the mapping itself stays logical.
    func shapedMapping(
        text: String,
        fontSize: Double,
        missingGlyphPolicy: TrueTypeGlyphMapper.MissingGlyphPolicy = .useNotdef,
    ) throws -> ShapedTextMapping {
        let scalars = Array(text.unicodeScalars)
        let shaped = try shape(text, missingGlyphPolicy: missingGlyphPolicy)
        let unitsPerEm = Double(metadata.head.unitsPerEm)
        let advanceWidths = metadata.hmtx.advanceWidths

        var clusters: [ShapedTextMapping.Cluster] = []
        clusters.reserveCapacity(shaped.count)
        for glyph in shaped {
            let range = glyph.sourceScalarRange
            let clusterScalars = Array(scalars[range])
            let advanceWidth = Int(glyph.glyphID) < advanceWidths.count ? advanceWidths[Int(glyph.glyphID)] : 0
            let advance = unitsPerEm > 0 ? Double(advanceWidth) / unitsPerEm * fontSize : 0
            let cid = metadata.compositeCID(forGlyph: glyph.glyphID)
            clusters.append(ShapedTextMapping.Cluster(
                sourceScalarRange: range,
                normalizedText: String(String.UnicodeScalarView(clusterScalars)),
                glyphs: [ShapedTextMapping.Glyph(
                    glyphID: glyph.glyphID,
                    cid: cid,
                    pdfCharacterCode: cid,
                    advanceWidth: advanceWidth,
                    advance: advance,
                    // A positional form maps one base scalar to different glyphs by
                    // context (beh initial vs medial), which would collide in the
                    // subset font cmap. Give each glyph a synthetic, glyph-unique
                    // cmap scalar (harmless: the CID font uses CIDs, not this cmap).
                    // Extraction still uses the cluster's real `toUnicodeScalars`.
                    cmapScalar: UnicodeScalar(0x100000 + UInt32(glyph.glyphID)),
                )],
                toUnicodeScalars: clusterScalars,
            ))
        }
        return try ShapedTextMapping(sourceText: text, clusters: clusters)
    }

    private static func gsubTableRange(fontData: Data, metadata: TrueTypeFontParser.Metadata) -> Range<Int>? {
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
