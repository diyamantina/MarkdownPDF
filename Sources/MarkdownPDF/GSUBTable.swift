import Foundation

/// A general reader for the GSUB (glyph substitution) table, parsing the features
/// and lookups of a chosen script into a form the Arabic shaper can apply: single
/// substitutions (lookup type 1, the positional `isol`/`init`/`medi`/`fina` forms)
/// and ligatures (lookup type 4, e.g. `rlig` lam-alef).
///
/// This is deliberately separate from `OpenTypeShaper`'s Latin ligature parser: the
/// Latin path only needs `latn`/`liga` type-4 lookups and is left untouched. Every
/// read is bounds-checked through `TrueTypeByteReader`; unsupported lookup types and
/// subtable formats are skipped (not fatal) so a font with extra tables still shapes
/// the parts we support.
struct GSUBTable {
    enum GSUBTableError: Error, Equatable {
        case malformed(reason: String)
    }

    struct LigatureRule: Equatable {
        /// Component glyph ids after the first; the first is the coverage glyph.
        var componentGlyphIDs: [UInt16]
        var ligatureGlyphID: UInt16
    }

    private enum Lookup {
        /// Covered glyph id → substitute glyph id (GSUB lookup type 1).
        case single([UInt16: UInt16])
        /// Ligature substitutions keyed by first component (GSUB lookup type 4).
        case ligature([LigatureRule])
        /// A supported-in-principle but here-unused lookup type; ignored on apply.
        case unsupported
    }

    /// Feature tag → the feature's lookups, in ascending LookupList index order (the
    /// order OpenType applies them).
    private let featureLookups: [String: [Lookup]]
    private let numGlyphs: UInt16

    /// Parses the GSUB table of `data` for `scriptTag`, falling back to `DFLT`.
    /// Returns nil if the font has no GSUB table.
    init?(fontData: Data, gsubTableRange: Range<Int>?, scriptTag: String, numGlyphs: UInt16) throws {
        guard let gsubTableRange else {
            return nil
        }
        self.numGlyphs = numGlyphs
        let bytes = [UInt8](fontData[gsubTableRange])
        let reader = TrueTypeByteReader(table: "GSUB", bytes: bytes)

        try reader.requireRange(offset: 0, count: 10)
        let majorVersion = try reader.uint16(at: 0)
        guard majorVersion == 1 else {
            throw GSUBTableError.malformed(reason: "GSUB major version must be 1")
        }
        let scriptListOffset = try Int(reader.uint16(at: 4))
        let featureListOffset = try Int(reader.uint16(at: 6))
        let lookupListOffset = try Int(reader.uint16(at: 8))

        let featureIndices = try Self.enabledFeatureIndices(
            reader: reader,
            scriptListOffset: scriptListOffset,
            scriptTag: scriptTag,
        )
        guard !featureIndices.isEmpty else {
            featureLookups = [:]
            return
        }

        // feature index → (tag, lookup indices)
        let features = try Self.features(reader: reader, featureListOffset: featureListOffset)
        // Collect, per feature tag, the union of lookup indices from every enabled
        // feature record carrying that tag.
        var lookupIndicesByTag: [String: Set<UInt16>] = [:]
        for index in featureIndices {
            guard Int(index) < features.count else {
                throw GSUBTableError.malformed(reason: "feature index \(index) exceeds feature count")
            }
            let feature = features[Int(index)]
            lookupIndicesByTag[feature.tag, default: []].formUnion(feature.lookupIndices)
        }

        // Parse only the lookups actually referenced, once each.
        let neededIndices = Set(lookupIndicesByTag.values.flatMap(\.self))
        let parsedLookups = try Self.parseLookups(
            reader: reader,
            lookupListOffset: lookupListOffset,
            indices: neededIndices,
        )

        var result: [String: [Lookup]] = [:]
        for (tag, indices) in lookupIndicesByTag {
            result[tag] = indices.sorted().compactMap { parsedLookups[$0] }
        }
        featureLookups = result
    }

    /// Whether the font carries the Arabic positional-form features, i.e. it is
    /// shapeable through this table.
    var hasArabicJoiningFeatures: Bool {
        featureLookups["init"] != nil || featureLookups["medi"] != nil
            || featureLookups["fina"] != nil || featureLookups["isol"] != nil
    }

    /// Applies `feature`'s single substitutions to `glyph`, in lookup order. Each
    /// lookup substitutes at most once; a glyph not covered by a lookup passes
    /// through unchanged.
    func singleSubstitute(feature: String, glyph: UInt16) -> UInt16 {
        guard let lookups = featureLookups[feature] else {
            return glyph
        }
        var current = glyph
        for lookup in lookups {
            guard case let .single(map) = lookup, let substitute = map[current] else {
                continue
            }
            // Skip a substitution whose output is .notdef (glyph 0) or past the glyph
            // count: a format-1 delta is unguarded arithmetic, so a broken or hostile
            // font can produce an out-of-range id that would index hmtx/glyf out of
            // bounds once drawn. Keeping the input glyph is the safe, glyph-0-is-notdef
            // consistent choice.
            guard substitute != 0, substitute < numGlyphs else {
                continue
            }
            current = substitute
        }
        return current
    }

    /// The ligature rules of `feature` (type 4), across all its lookups.
    func ligatureRules(feature: String) -> [LigatureRule] {
        guard let lookups = featureLookups[feature] else {
            return []
        }
        return lookups.flatMap { lookup -> [LigatureRule] in
            if case let .ligature(rules) = lookup {
                return rules
            }
            return []
        }
    }

    // MARK: - Script / feature / lookup discovery

    private static func enabledFeatureIndices(
        reader: TrueTypeByteReader,
        scriptListOffset: Int,
        scriptTag: String,
    ) throws -> Set<UInt16> {
        try reader.requireRange(offset: scriptListOffset, count: 2)
        let scriptCount = try Int(reader.uint16(at: scriptListOffset))
        try reader.requireRange(offset: scriptListOffset + 2, count: scriptCount * 6)
        var selectedScriptOffset: Int?
        var fallbackScriptOffset: Int?
        for index in 0 ..< scriptCount {
            let recordOffset = scriptListOffset + 2 + index * 6
            let tag = try reader.tag(at: recordOffset)
            let scriptOffset = try scriptListOffset + Int(reader.uint16(at: recordOffset + 4))
            if tag == scriptTag {
                selectedScriptOffset = scriptOffset
            } else if tag == "DFLT" {
                fallbackScriptOffset = scriptOffset
            }
        }
        guard let scriptOffset = selectedScriptOffset ?? fallbackScriptOffset else {
            return []
        }
        try reader.requireRange(offset: scriptOffset, count: 2)
        let defaultLangSysOffset = try Int(reader.uint16(at: scriptOffset))
        guard defaultLangSysOffset != 0 else {
            return []
        }
        return try langSysFeatureIndices(reader: reader, offset: scriptOffset + defaultLangSysOffset)
    }

    private static func langSysFeatureIndices(reader: TrueTypeByteReader, offset: Int) throws -> Set<UInt16> {
        try reader.requireRange(offset: offset, count: 6)
        let requiredFeatureIndex = try reader.uint16(at: offset + 2)
        let featureIndexCount = try Int(reader.uint16(at: offset + 4))
        try reader.requireRange(offset: offset + 6, count: featureIndexCount * 2)
        var indices = Set<UInt16>()
        if requiredFeatureIndex != 0xFFFF {
            indices.insert(requiredFeatureIndex)
        }
        for index in 0 ..< featureIndexCount {
            try indices.insert(reader.uint16(at: offset + 6 + index * 2))
        }
        return indices
    }

    private struct Feature {
        var tag: String
        var lookupIndices: [UInt16]
    }

    private static func features(reader: TrueTypeByteReader, featureListOffset: Int) throws -> [Feature] {
        try reader.requireRange(offset: featureListOffset, count: 2)
        let featureCount = try Int(reader.uint16(at: featureListOffset))
        try reader.requireRange(offset: featureListOffset + 2, count: featureCount * 6)
        var features: [Feature] = []
        features.reserveCapacity(featureCount)
        for index in 0 ..< featureCount {
            let recordOffset = featureListOffset + 2 + index * 6
            let tag = try reader.tag(at: recordOffset)
            let featureOffset = try featureListOffset + Int(reader.uint16(at: recordOffset + 4))
            try reader.requireRange(offset: featureOffset, count: 4)
            let lookupIndexCount = try Int(reader.uint16(at: featureOffset + 2))
            try reader.requireRange(offset: featureOffset + 4, count: lookupIndexCount * 2)
            var lookupIndices: [UInt16] = []
            lookupIndices.reserveCapacity(lookupIndexCount)
            for lookup in 0 ..< lookupIndexCount {
                try lookupIndices.append(reader.uint16(at: featureOffset + 4 + lookup * 2))
            }
            features.append(Feature(tag: tag, lookupIndices: lookupIndices))
        }
        return features
    }

    private static func parseLookups(
        reader: TrueTypeByteReader,
        lookupListOffset: Int,
        indices: Set<UInt16>,
    ) throws -> [UInt16: Lookup] {
        try reader.requireRange(offset: lookupListOffset, count: 2)
        let lookupCount = try Int(reader.uint16(at: lookupListOffset))
        try reader.requireRange(offset: lookupListOffset + 2, count: lookupCount * 2)
        var result: [UInt16: Lookup] = [:]
        for index in indices.sorted() {
            guard Int(index) < lookupCount else {
                throw GSUBTableError.malformed(reason: "lookup index \(index) exceeds lookup count")
            }
            let lookupOffset = try lookupListOffset + Int(reader.uint16(at: lookupListOffset + 2 + Int(index) * 2))
            result[index] = try parseLookup(reader: reader, offset: lookupOffset)
        }
        return result
    }

    private static func parseLookup(reader: TrueTypeByteReader, offset: Int) throws -> Lookup {
        try reader.requireRange(offset: offset, count: 6)
        let lookupType = try reader.uint16(at: offset)
        // lookupFlag at offset+2 (RIGHT_TO_LEFT/IGNORE flags) is not consulted:
        // single substitution and lam-alef ligation are unaffected by the flags a
        // normal Arabic font sets, and honoring mark-skipping here would need GDEF.
        let subtableCount = try Int(reader.uint16(at: offset + 4))
        try reader.requireRange(offset: offset + 6, count: subtableCount * 2)
        var subtableOffsets: [Int] = []
        subtableOffsets.reserveCapacity(subtableCount)
        for index in 0 ..< subtableCount {
            try subtableOffsets.append(offset + Int(reader.uint16(at: offset + 6 + index * 2)))
        }

        switch lookupType {
        case 1:
            var map: [UInt16: UInt16] = [:]
            for subtableOffset in subtableOffsets {
                try parseSingleSubstitution(reader: reader, offset: subtableOffset, into: &map)
            }
            return .single(map)
        case 4:
            var rules: [LigatureRule] = []
            for subtableOffset in subtableOffsets {
                try rules.append(contentsOf: parseLigatureSubstitution(reader: reader, offset: subtableOffset))
            }
            return .ligature(rules)
        default:
            return .unsupported
        }
    }

    // MARK: - Subtable parsing

    private static func parseSingleSubstitution(
        reader: TrueTypeByteReader,
        offset: Int,
        into map: inout [UInt16: UInt16],
    ) throws {
        try reader.requireRange(offset: offset, count: 6)
        let format = try reader.uint16(at: offset)
        let coverageOffset = try offset + Int(reader.uint16(at: offset + 2))
        let coverage = try coverageGlyphIDs(reader: reader, offset: coverageOffset)
        switch format {
        case 1:
            let delta = try reader.int16(at: offset + 4)
            for glyph in coverage {
                let substitute = UInt16(truncatingIfNeeded: Int(glyph) + Int(delta))
                map[glyph] = substitute
            }
        case 2:
            let glyphCount = try Int(reader.uint16(at: offset + 4))
            try reader.requireRange(offset: offset + 6, count: glyphCount * 2)
            guard glyphCount == coverage.count else {
                throw GSUBTableError.malformed(reason: "single-substitution glyph count must match coverage")
            }
            for index in 0 ..< glyphCount {
                let substitute = try reader.uint16(at: offset + 6 + index * 2)
                map[coverage[index]] = substitute
            }
        default:
            throw GSUBTableError.malformed(reason: "single-substitution format must be 1 or 2")
        }
    }

    private static func parseLigatureSubstitution(reader: TrueTypeByteReader, offset: Int) throws -> [LigatureRule] {
        try reader.requireRange(offset: offset, count: 6)
        let format = try reader.uint16(at: offset)
        guard format == 1 else {
            throw GSUBTableError.malformed(reason: "ligature substitution format must be 1")
        }
        let coverageOffset = try offset + Int(reader.uint16(at: offset + 2))
        let ligatureSetCount = try Int(reader.uint16(at: offset + 4))
        try reader.requireRange(offset: offset + 6, count: ligatureSetCount * 2)
        let coverage = try coverageGlyphIDs(reader: reader, offset: coverageOffset)
        guard coverage.count == ligatureSetCount else {
            throw GSUBTableError.malformed(reason: "ligature coverage count must match ligature set count")
        }

        var rules: [LigatureRule] = []
        for index in 0 ..< ligatureSetCount {
            let ligatureSetOffset = try offset + Int(reader.uint16(at: offset + 6 + index * 2))
            try rules.append(contentsOf: ligatureRules(
                reader: reader,
                offset: ligatureSetOffset,
                firstGlyphID: coverage[index],
            ))
        }
        return rules
    }

    private static func ligatureRules(
        reader: TrueTypeByteReader,
        offset: Int,
        firstGlyphID: UInt16,
    ) throws -> [LigatureRule] {
        try reader.requireRange(offset: offset, count: 2)
        let ligatureCount = try Int(reader.uint16(at: offset))
        try reader.requireRange(offset: offset + 2, count: ligatureCount * 2)
        var rules: [LigatureRule] = []
        rules.reserveCapacity(ligatureCount)
        for index in 0 ..< ligatureCount {
            let ligatureOffset = try offset + Int(reader.uint16(at: offset + 2 + index * 2))
            try reader.requireRange(offset: ligatureOffset, count: 4)
            let ligatureGlyphID = try reader.uint16(at: ligatureOffset)
            let componentCount = try Int(reader.uint16(at: ligatureOffset + 2))
            guard componentCount >= 2 else {
                throw GSUBTableError.malformed(reason: "ligature component count must be at least 2")
            }
            try reader.requireRange(offset: ligatureOffset + 4, count: (componentCount - 1) * 2)
            var components = [firstGlyphID]
            components.reserveCapacity(componentCount)
            for component in 0 ..< componentCount - 1 {
                try components.append(reader.uint16(at: ligatureOffset + 4 + component * 2))
            }
            rules.append(LigatureRule(componentGlyphIDs: components, ligatureGlyphID: ligatureGlyphID))
        }
        return rules
    }

    private static func coverageGlyphIDs(reader: TrueTypeByteReader, offset: Int) throws -> [UInt16] {
        try reader.requireRange(offset: offset, count: 4)
        let format = try reader.uint16(at: offset)
        switch format {
        case 1:
            let glyphCount = try Int(reader.uint16(at: offset + 2))
            try reader.requireRange(offset: offset + 4, count: glyphCount * 2)
            return try (0 ..< glyphCount).map { index in
                try reader.uint16(at: offset + 4 + index * 2)
            }
        case 2:
            let rangeCount = try Int(reader.uint16(at: offset + 2))
            try reader.requireRange(offset: offset + 4, count: rangeCount * 6)
            var glyphs: [UInt16] = []
            for index in 0 ..< rangeCount {
                let rangeOffset = offset + 4 + index * 6
                let startGlyphID = try reader.uint16(at: rangeOffset)
                let endGlyphID = try reader.uint16(at: rangeOffset + 2)
                guard startGlyphID <= endGlyphID else {
                    throw GSUBTableError.malformed(reason: "coverage range is unordered")
                }
                glyphs.append(contentsOf: startGlyphID ... endGlyphID)
            }
            return glyphs
        default:
            throw GSUBTableError.malformed(reason: "coverage format must be 1 or 2")
        }
    }
}
