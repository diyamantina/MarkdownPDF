import Foundation

struct OpenTypeShaper {
    enum ValidationError: Error, Equatable, LocalizedError {
        case invalidFontSize(Double)
        case unsupportedScriptScalar(scalar: UnicodeScalar, scalarOffset: Int)
        case leadingCombiningMark(scalar: UnicodeScalar, scalarOffset: Int)
        case invalidGlyphID(UInt32, numGlyphs: UInt16)
        case unsupportedGSUBLookupFlag(UInt16)
        case malformedGSUB(reason: String)

        var errorDescription: String? {
            switch self {
            case let .invalidFontSize(fontSize):
                "OpenType shaping requires a positive finite font size, got \(fontSize)."
            case let .unsupportedScriptScalar(scalar, scalarOffset):
                "OpenType shaping does not yet support scalar U+\(Self.hex(scalar.value)) at scalar offset \(scalarOffset)."
            case let .leadingCombiningMark(scalar, scalarOffset):
                "OpenType shaping cannot attach combining mark U+\(Self.hex(scalar.value)) at scalar offset \(scalarOffset)."
            case let .invalidGlyphID(glyphID, numGlyphs):
                "OpenType shaping references glyph \(glyphID), but the font declares \(numGlyphs) glyphs."
            case let .unsupportedGSUBLookupFlag(lookupFlag):
                "OpenType shaping does not yet support GSUB lookup flag 0x\(Self.hex(UInt32(lookupFlag)))."
            case let .malformedGSUB(reason):
                "The GSUB table is malformed: \(reason)"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .invalidFontSize:
                "Pass a positive finite font size before shaping text."
            case .unsupportedScriptScalar:
                "Use the current shaper only for the supported Latin increment, or keep this text on the explicit fallback path."
            case .leadingCombiningMark:
                "Place combining marks after a supported Latin base scalar before shaping."
            case .invalidGlyphID:
                "Use OpenType substitution tables whose glyph ids are within the maxp glyph count."
            case .unsupportedGSUBLookupFlag:
                "Use lookup flag zero for this shaping increment, or keep the text on an explicit fallback path."
            case .malformedGSUB:
                "Replace the font with one whose GSUB lookup, feature, and coverage offsets are valid."
            }
        }

        private static func hex(_ value: UInt32) -> String {
            String(format: "%04X", locale: Locale(identifier: "en_US_POSIX"), value)
        }
    }

    struct LigatureRule: Equatable {
        var componentGlyphIDs: [UInt16]
        var ligatureGlyphID: UInt16
    }

    var data: Data
    var metadata: TrueTypeFontParser.Metadata
    var missingGlyphPolicy: TrueTypeGlyphMapper.MissingGlyphPolicy

    init(
        data: Data,
        metadata: TrueTypeFontParser.Metadata,
        missingGlyphPolicy: TrueTypeGlyphMapper.MissingGlyphPolicy = .reject,
    ) {
        self.data = data
        self.metadata = metadata
        self.missingGlyphPolicy = missingGlyphPolicy
    }

    func shape(text: String, fontSize: Double) throws -> ShapedTextMapping {
        guard fontSize.isFinite, fontSize > 0 else {
            throw ValidationError.invalidFontSize(fontSize)
        }

        let sourceScalars = Array(text.unicodeScalars)
        try validateSupportedScalars(sourceScalars)

        let baseMapping = try TrueTypeGlyphMapper(
            data: data,
            metadata: metadata,
            missingGlyphPolicy: missingGlyphPolicy,
        ).map(text: text, fontSize: fontSize)
        let rulesByFirstGlyph = try Dictionary(grouping: ligatureRules(), by: { $0.componentGlyphIDs[0] })
            .mapValues { rules in
                rules.sorted { lhs, rhs in lhs.componentGlyphIDs.count > rhs.componentGlyphIDs.count }
            }

        var clusters: [ShapedTextMapping.Cluster] = []
        var index = 0
        while index < sourceScalars.count {
            guard !Self.isCombiningMark(sourceScalars[index]) else {
                throw ValidationError.leadingCombiningMark(
                    scalar: sourceScalars[index],
                    scalarOffset: index,
                )
            }

            if let match = ligatureMatch(
                at: index,
                glyphs: baseMapping.glyphs,
                rulesByFirstGlyph: rulesByFirstGlyph,
            ) {
                let sourceEnd = markClusterEnd(startingAt: index + match.componentGlyphIDs.count, in: sourceScalars)
                let markGlyphs = baseMapping.glyphs[index + match.componentGlyphIDs.count ..< sourceEnd]
                    .map { ShapedTextMapping.Glyph($0) }
                let glyphs = try [shapedGlyph(glyphID: match.ligatureGlyphID, fontSize: fontSize)] + markGlyphs
                clusters.append(cluster(
                    sourceScalars: sourceScalars,
                    sourceRange: index ..< sourceEnd,
                    glyphs: glyphs,
                ))
                index = sourceEnd
            } else {
                let sourceEnd = markClusterEnd(startingAt: index + 1, in: sourceScalars)
                let glyphs = baseMapping.glyphs[index ..< sourceEnd].map { ShapedTextMapping.Glyph($0) }
                clusters.append(cluster(
                    sourceScalars: sourceScalars,
                    sourceRange: index ..< sourceEnd,
                    glyphs: glyphs,
                ))
                index = sourceEnd
            }
        }

        return try ShapedTextMapping(sourceText: text, clusters: clusters)
    }

    static func canShapeLatinIncrement(_ text: String) -> Bool {
        var canAttachCombiningMark = false
        for scalar in text.unicodeScalars {
            if isCombiningMark(scalar) {
                guard canAttachCombiningMark else {
                    return false
                }
                continue
            }
            guard isSupportedLatinIncrementScalar(scalar) else {
                return false
            }
            canAttachCombiningMark = isLatinBaseScalar(scalar)
        }
        return true
    }

    private func validateSupportedScalars(_ scalars: [UnicodeScalar]) throws {
        var canAttachCombiningMark = false
        for (offset, scalar) in scalars.enumerated() {
            if Self.isCombiningMark(scalar) {
                guard canAttachCombiningMark else {
                    throw ValidationError.leadingCombiningMark(scalar: scalar, scalarOffset: offset)
                }
                continue
            }

            guard Self.isSupportedLatinIncrementScalar(scalar) else {
                throw ValidationError.unsupportedScriptScalar(scalar: scalar, scalarOffset: offset)
            }
            canAttachCombiningMark = Self.isLatinBaseScalar(scalar)
        }
    }

    private func ligatureRules() throws -> [LigatureRule] {
        guard let gsubRecord = metadata.table(named: "GSUB") else {
            return []
        }
        do {
            let tableStart = Int(gsubRecord.offset)
            let tableLength = Int(gsubRecord.length)
            let bytes = Array(data)
            guard tableStart <= bytes.count, tableLength <= bytes.count - tableStart else {
                throw ValidationError.malformedGSUB(reason: "table bounds exceed the font data")
            }
            let tableBytes = Array(bytes[tableStart ..< tableStart + tableLength])
            return try GSUBLigatureParser(bytes: tableBytes, numGlyphs: metadata.maxp.numGlyphs).ligatureRules()
        } catch let error as ValidationError {
            throw error
        } catch let error as TrueTypeFontError {
            throw ValidationError.malformedGSUB(reason: error.errorDescription ?? String(describing: error))
        } catch {
            throw error
        }
    }

    private func ligatureMatch(
        at index: Int,
        glyphs: [TrueTypeGlyphMapper.Glyph],
        rulesByFirstGlyph: [UInt16: [LigatureRule]],
    ) -> LigatureRule? {
        let firstGlyphID = glyphs[index].glyphID
        guard let rules = rulesByFirstGlyph[firstGlyphID] else {
            return nil
        }
        return rules.first { rule in
            let endIndex = index + rule.componentGlyphIDs.count
            guard endIndex <= glyphs.count else {
                return false
            }
            return zip(rule.componentGlyphIDs, glyphs[index ..< endIndex]).allSatisfy { expected, actual in
                expected == actual.glyphID
            }
        }
    }

    private func shapedGlyph(glyphID: UInt16, fontSize: Double) throws -> ShapedTextMapping.Glyph {
        guard glyphID < metadata.maxp.numGlyphs else {
            throw ValidationError.invalidGlyphID(UInt32(glyphID), numGlyphs: metadata.maxp.numGlyphs)
        }
        let advanceWidth = metadata.hmtx.advanceWidths[Int(glyphID)]
        return ShapedTextMapping.Glyph(
            glyphID: glyphID,
            cid: glyphID,
            pdfCharacterCode: glyphID,
            advanceWidth: advanceWidth,
            advance: Double(advanceWidth) / Double(metadata.head.unitsPerEm) * fontSize,
        )
    }

    private func markClusterEnd(startingAt index: Int, in scalars: [UnicodeScalar]) -> Int {
        var endIndex = index
        while endIndex < scalars.count, Self.isCombiningMark(scalars[endIndex]) {
            endIndex += 1
        }
        return endIndex
    }

    private func cluster(
        sourceScalars: [UnicodeScalar],
        sourceRange: Range<Int>,
        glyphs: [ShapedTextMapping.Glyph],
    ) -> ShapedTextMapping.Cluster {
        let coveredScalars = Array(sourceScalars[sourceRange])
        return ShapedTextMapping.Cluster(
            sourceScalarRange: sourceRange,
            normalizedText: Self.string(from: coveredScalars),
            glyphs: glyphs,
            toUnicodeScalars: coveredScalars,
        )
    }

    private static func isSupportedLatinIncrementScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0009, 0x000A, 0x000D, 0x0020 ... 0x007E:
            true
        default:
            false
        }
    }

    private static func isLatinBaseScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0041 ... 0x005A, 0x0061 ... 0x007A:
            true
        default:
            false
        }
    }

    private static func isCombiningMark(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0300 ... 0x036F,
             0x1AB0 ... 0x1AFF,
             0x1DC0 ... 0x1DFF,
             0x20D0 ... 0x20FF,
             0xFE20 ... 0xFE2F:
            true
        default:
            false
        }
    }

    private static func string(from scalars: [UnicodeScalar]) -> String {
        String(String.UnicodeScalarView(scalars))
    }
}

private struct GSUBLigatureParser {
    private struct FeatureRecord {
        var tag: String
        var offset: Int
    }

    private struct LookupTable {
        var lookupType: UInt16
        var subtableOffsets: [Int]
    }

    private var reader: TrueTypeByteReader
    private var numGlyphs: UInt16

    init(bytes: [UInt8], numGlyphs: UInt16) {
        reader = TrueTypeByteReader(table: "GSUB", bytes: bytes)
        self.numGlyphs = numGlyphs
    }

    func ligatureRules() throws -> [OpenTypeShaper.LigatureRule] {
        try reader.requireRange(offset: 0, count: 10)
        let majorVersion = try reader.uint16(at: 0)
        guard majorVersion == 1 else {
            throw OpenTypeShaper.ValidationError.malformedGSUB(reason: "major version must be 1")
        }

        let scriptListOffset = try Int(reader.uint16(at: 4))
        let featureListOffset = try Int(reader.uint16(at: 6))
        let lookupListOffset = try Int(reader.uint16(at: 8))
        let enabledFeatureIndices = try scriptFeatureIndices(at: scriptListOffset, scriptTag: "latn")
        guard !enabledFeatureIndices.isEmpty else {
            return []
        }
        let lookupIndices = try ligatureLookupIndices(
            at: featureListOffset,
            enabledFeatureIndices: enabledFeatureIndices,
        )
        guard !lookupIndices.isEmpty else {
            return []
        }
        let lookupTables = try lookups(at: lookupListOffset, indices: lookupIndices)

        var rules: [OpenTypeShaper.LigatureRule] = []
        for lookup in lookupTables where lookup.lookupType == 4 {
            for subtableOffset in lookup.subtableOffsets {
                try rules.append(contentsOf: ligatureSubstitutionRules(at: subtableOffset))
            }
        }
        try validateGlyphIDs(in: rules)
        return rules
    }

    private func scriptFeatureIndices(at offset: Int, scriptTag: String) throws -> Set<UInt16> {
        try reader.requireRange(offset: offset, count: 2)
        let scriptCount = try Int(reader.uint16(at: offset))
        try reader.requireRange(offset: offset + 2, count: scriptCount * 6)
        var fallbackScriptOffset: Int?
        var selectedScriptOffset: Int?
        for index in 0 ..< scriptCount {
            let recordOffset = offset + 2 + index * 6
            let tag = try reader.tag(at: recordOffset)
            let scriptOffset = try offset + Int(reader.uint16(at: recordOffset + 4))
            if tag == scriptTag {
                selectedScriptOffset = scriptOffset
            } else if tag == "DFLT" {
                fallbackScriptOffset = scriptOffset
            }
        }

        guard let scriptOffset = selectedScriptOffset ?? fallbackScriptOffset else {
            return []
        }
        try reader.requireRange(offset: scriptOffset, count: 4)
        let defaultLangSysOffset = try Int(reader.uint16(at: scriptOffset))
        guard defaultLangSysOffset != 0 else {
            return []
        }
        return try langSysFeatureIndices(at: scriptOffset + defaultLangSysOffset)
    }

    private func langSysFeatureIndices(at offset: Int) throws -> Set<UInt16> {
        try reader.requireRange(offset: offset, count: 6)
        let requiredFeatureIndex = try reader.uint16(at: offset + 2)
        let featureIndexCount = try Int(reader.uint16(at: offset + 4))
        try reader.requireRange(offset: offset + 6, count: featureIndexCount * 2)
        var featureIndices = Set<UInt16>()
        if requiredFeatureIndex != 0xFFFF {
            featureIndices.insert(requiredFeatureIndex)
        }
        for index in 0 ..< featureIndexCount {
            try featureIndices.insert(reader.uint16(at: offset + 6 + index * 2))
        }
        return featureIndices
    }

    private func ligatureLookupIndices(at offset: Int, enabledFeatureIndices: Set<UInt16>) throws -> Set<UInt16> {
        try reader.requireRange(offset: offset, count: 2)
        let featureRecords = try featureRecords(at: offset)
        var lookupIndices = Set<UInt16>()
        for (featureIndex, record) in featureRecords.enumerated() {
            guard record.tag == "liga", enabledFeatureIndices.contains(UInt16(featureIndex)) else {
                continue
            }
            try lookupIndices.formUnion(featureLookupIndices(at: offset + record.offset))
        }
        return lookupIndices
    }

    private func featureRecords(at offset: Int) throws -> [FeatureRecord] {
        let featureCount = try Int(reader.uint16(at: offset))
        try reader.requireRange(offset: offset + 2, count: featureCount * 6)
        var records: [FeatureRecord] = []
        records.reserveCapacity(featureCount)
        for index in 0 ..< featureCount {
            let recordOffset = offset + 2 + index * 6
            try records.append(FeatureRecord(
                tag: reader.tag(at: recordOffset),
                offset: Int(reader.uint16(at: recordOffset + 4)),
            ))
        }
        return records
    }

    private func featureLookupIndices(at offset: Int) throws -> Set<UInt16> {
        try reader.requireRange(offset: offset, count: 4)
        let lookupIndexCount = try Int(reader.uint16(at: offset + 2))
        try reader.requireRange(offset: offset + 4, count: lookupIndexCount * 2)
        var lookupIndices = Set<UInt16>()
        for index in 0 ..< lookupIndexCount {
            try lookupIndices.insert(reader.uint16(at: offset + 4 + index * 2))
        }
        return lookupIndices
    }

    private func lookups(at offset: Int, indices: Set<UInt16>) throws -> [LookupTable] {
        try reader.requireRange(offset: offset, count: 2)
        let lookupCount = try Int(reader.uint16(at: offset))
        try reader.requireRange(offset: offset + 2, count: lookupCount * 2)
        var lookups: [LookupTable] = []
        for lookupIndex in indices.sorted() {
            guard lookupIndex < lookupCount else {
                throw OpenTypeShaper.ValidationError.malformedGSUB(reason: "lookup index \(lookupIndex) exceeds lookup count")
            }
            let lookupOffset = try offset + Int(reader.uint16(at: offset + 2 + Int(lookupIndex) * 2))
            try lookups.append(lookup(at: lookupOffset))
        }
        return lookups
    }

    private func lookup(at offset: Int) throws -> LookupTable {
        try reader.requireRange(offset: offset, count: 6)
        let lookupType = try reader.uint16(at: offset)
        let lookupFlag = try reader.uint16(at: offset + 2)
        guard lookupFlag == 0 else {
            throw OpenTypeShaper.ValidationError.unsupportedGSUBLookupFlag(lookupFlag)
        }
        let subtableCount = try Int(reader.uint16(at: offset + 4))
        try reader.requireRange(offset: offset + 6, count: subtableCount * 2)
        var subtableOffsets: [Int] = []
        subtableOffsets.reserveCapacity(subtableCount)
        for index in 0 ..< subtableCount {
            try subtableOffsets.append(offset + Int(reader.uint16(at: offset + 6 + index * 2)))
        }
        return LookupTable(lookupType: lookupType, subtableOffsets: subtableOffsets)
    }

    private func ligatureSubstitutionRules(at offset: Int) throws -> [OpenTypeShaper.LigatureRule] {
        try reader.requireRange(offset: offset, count: 6)
        let format = try reader.uint16(at: offset)
        guard format == 1 else {
            throw OpenTypeShaper.ValidationError.malformedGSUB(reason: "ligature substitution format must be 1")
        }
        let coverageOffset = try offset + Int(reader.uint16(at: offset + 2))
        let ligatureSetCount = try Int(reader.uint16(at: offset + 4))
        try reader.requireRange(offset: offset + 6, count: ligatureSetCount * 2)
        let coverageGlyphs = try coverageGlyphIDs(at: coverageOffset)
        guard coverageGlyphs.count == ligatureSetCount else {
            throw OpenTypeShaper.ValidationError.malformedGSUB(reason: "coverage glyph count must match ligature set count")
        }

        var rules: [OpenTypeShaper.LigatureRule] = []
        for index in 0 ..< ligatureSetCount {
            let ligatureSetOffset = try offset + Int(reader.uint16(at: offset + 6 + index * 2))
            try rules.append(contentsOf: ligatureRules(at: ligatureSetOffset, firstGlyphID: coverageGlyphs[index]))
        }
        return rules
    }

    private func coverageGlyphIDs(at offset: Int) throws -> [UInt16] {
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
                    throw OpenTypeShaper.ValidationError.malformedGSUB(reason: "coverage range is unordered")
                }
                glyphs.append(contentsOf: startGlyphID ... endGlyphID)
            }
            return glyphs
        default:
            throw OpenTypeShaper.ValidationError.malformedGSUB(reason: "coverage format must be 1 or 2")
        }
    }

    private func ligatureRules(at offset: Int, firstGlyphID: UInt16) throws -> [OpenTypeShaper.LigatureRule] {
        try reader.requireRange(offset: offset, count: 2)
        let ligatureCount = try Int(reader.uint16(at: offset))
        try reader.requireRange(offset: offset + 2, count: ligatureCount * 2)
        var rules: [OpenTypeShaper.LigatureRule] = []
        rules.reserveCapacity(ligatureCount)
        for index in 0 ..< ligatureCount {
            let ligatureOffset = try offset + Int(reader.uint16(at: offset + 2 + index * 2))
            try rules.append(ligatureRule(at: ligatureOffset, firstGlyphID: firstGlyphID))
        }
        return rules
    }

    private func ligatureRule(at offset: Int, firstGlyphID: UInt16) throws -> OpenTypeShaper.LigatureRule {
        try reader.requireRange(offset: offset, count: 4)
        let ligatureGlyphID = try reader.uint16(at: offset)
        let componentCount = try Int(reader.uint16(at: offset + 2))
        guard componentCount >= 2 else {
            throw OpenTypeShaper.ValidationError.malformedGSUB(reason: "ligature component count must be at least 2")
        }
        try reader.requireRange(offset: offset + 4, count: (componentCount - 1) * 2)
        var componentGlyphIDs = [firstGlyphID]
        componentGlyphIDs.reserveCapacity(componentCount)
        for index in 0 ..< componentCount - 1 {
            try componentGlyphIDs.append(reader.uint16(at: offset + 4 + index * 2))
        }
        return OpenTypeShaper.LigatureRule(
            componentGlyphIDs: componentGlyphIDs,
            ligatureGlyphID: ligatureGlyphID,
        )
    }

    private func validateGlyphIDs(in rules: [OpenTypeShaper.LigatureRule]) throws {
        for rule in rules {
            let glyphIDs = rule.componentGlyphIDs + [rule.ligatureGlyphID]
            for glyphID in glyphIDs where glyphID >= numGlyphs {
                throw OpenTypeShaper.ValidationError.invalidGlyphID(UInt32(glyphID), numGlyphs: numGlyphs)
            }
        }
    }
}
