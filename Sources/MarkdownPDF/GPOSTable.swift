import Foundation

/// A reader for the GPOS (glyph positioning) table, parsing the mark-attachment
/// lookups of a chosen script: mark-to-base (lookup type 4) and mark-to-mark (type 6),
/// subtable format 1. These place combining marks (Arabic harakat, Hebrew niqqud)
/// precisely on their base letter or on a preceding mark, which the advance-only path
/// cannot do.
///
/// Every read is bounds-checked through `TrueTypeByteReader`. Lookup types and
/// subtable formats this reader does not handle are recorded as unsupported and skipped
/// on apply, so a font with extra positioning tables still attaches the marks we can.
struct GPOSTable {
    enum GPOSTableError: Error, Equatable {
        case malformed(reason: String)
    }

    /// The anchor pair that attaches a mark to its target: the mark aligns its
    /// `markAnchor` with the target's `targetAnchor`, both in font units.
    struct Attachment: Equatable {
        var markAnchor: GPOSAnchor
        var targetAnchor: GPOSAnchor
    }

    struct MarkRecord: Equatable {
        var markClass: UInt16
        var anchor: GPOSAnchor
    }

    /// A mark-to-base (type 4) or mark-to-mark (type 6) subtable. The two are identical
    /// in shape: a set of marks (each with a class and an anchor) attach to a set of
    /// targets (each carrying one anchor per mark class).
    struct MarkAttachmentSubtable: Equatable {
        var markCoverage: [UInt16: Int]
        var marks: [MarkRecord]
        var targetCoverage: [UInt16: Int]
        /// Per target coverage index, an anchor per mark class (nil when absent).
        var targetAnchors: [[GPOSAnchor?]]
        var classCount: Int

        /// The attachment aligning `mark` onto `target`, or nil when either glyph is
        /// uncovered or the target has no anchor for the mark's class.
        func attachment(mark: UInt16, target: UInt16) -> Attachment? {
            guard let markIndex = markCoverage[mark], let targetIndex = targetCoverage[target],
                  markIndex < marks.count, targetIndex < targetAnchors.count
            else {
                return nil
            }
            let markRecord = marks[markIndex]
            let anchors = targetAnchors[targetIndex]
            guard Int(markRecord.markClass) < anchors.count, let targetAnchor = anchors[Int(markRecord.markClass)] else {
                return nil
            }
            return Attachment(markAnchor: markRecord.anchor, targetAnchor: targetAnchor)
        }
    }

    /// A single-adjustment (type 1) subtable. Format 1 carries one value shared by every
    /// covered glyph; format 2 carries a value per covered glyph. The value is added to
    /// the glyph's position, most often as a contextual refinement invoked by a chained
    /// context lookup (Hebrew holam is nudged 25 units when it follows a consonant).
    struct SinglePosSubtable: Equatable {
        var coverage: [UInt16: Int]
        /// Set for format 1 (one value for all); nil for format 2.
        var sharedValue: GPOSValueRecord?
        /// Per coverage index for format 2; empty for format 1.
        var perGlyphValues: [GPOSValueRecord]

        func value(for glyph: UInt16) -> GPOSValueRecord? {
            guard let index = coverage[glyph] else {
                return nil
            }
            if let sharedValue {
                return sharedValue
            }
            return index < perGlyphValues.count ? perGlyphValues[index] : nil
        }
    }

    /// A pair-adjustment (type 2) subtable, format 1 (explicit per-glyph pair sets) or
    /// format 2 (class-based). It returns the value applied to the first glyph of a pair;
    /// the second glyph's value is unused by the mark-positioning paths that invoke it.
    struct PairPosSubtable: Equatable {
        struct PairValue: Equatable {
            var secondGlyph: UInt16
            var firstValue: GPOSValueRecord
        }

        // Format 1
        var coverage: [UInt16: Int]
        var pairSets: [[PairValue]]
        // Format 2
        var classDef1: [UInt16: Int]
        var classDef2: [UInt16: Int]
        var classMatrix: [[GPOSValueRecord]]
        var class1Count: Int
        var class2Count: Int
        var isFormat1: Bool

        func firstValue(first: UInt16, second: UInt16) -> GPOSValueRecord? {
            if isFormat1 {
                guard let setIndex = coverage[first], setIndex < pairSets.count else {
                    return nil
                }
                return pairSets[setIndex].first { $0.secondGlyph == second }?.firstValue
            }
            guard coverage[first] != nil else {
                return nil
            }
            let class1 = classDef1[first] ?? 0
            let class2 = classDef2[second] ?? 0
            guard class1 < classMatrix.count, class2 < classMatrix[class1].count else {
                return nil
            }
            return classMatrix[class1][class2]
        }
    }

    /// A chained-context (type 8) subtable, format 3: the position matches when the
    /// glyphs before (backtrack, in reverse), at (input), and after (lookahead) the
    /// current position all fall in the given coverage sets, at which point each sequence
    /// lookup record applies a nested lookup at an offset into the input.
    struct ChainedContextSubtable: Equatable {
        var backtrackCoverage: [Set<UInt16>]
        var inputCoverage: [Set<UInt16>]
        var lookaheadCoverage: [Set<UInt16>]
        var sequenceLookups: [SequencePosLookup]
    }

    /// One nested-lookup application inside a chained-context match: apply the lookup at
    /// `lookupIndex` to the input glyph `sequenceIndex` positions past the match start.
    struct SequencePosLookup: Equatable {
        var sequenceIndex: Int
        var lookupIndex: UInt16
    }

    /// A parsed GPOS lookup, tagged by the subtable kind this reader handles. Types it
    /// does not model (cursive attachment, mark-to-ligature) carry their type number so a
    /// caller can record them as unsupported rather than mistaking them for a no-op.
    enum LookupKind: Equatable {
        case markAttachment([MarkAttachmentSubtable])
        case single([SinglePosSubtable])
        case pair([PairPosSubtable])
        case chainedContext([ChainedContextSubtable])
        case unsupported(type: UInt16)
    }

    private let lookupsByIndex: [UInt16: LookupKind]
    private let featureLookupIndices: [String: [UInt16]]

    /// The parsed kind of the lookup at `index`, for a caller that executes a feature's
    /// lookups in order (mark attachment interleaved with chained-context refinement).
    func lookupKind(at index: UInt16) -> LookupKind? {
        lookupsByIndex[index]
    }

    /// Whether the font carries mark/mkmk positioning for the selected script.
    var hasMarkPositioning: Bool {
        featureLookupIndices["mark"] != nil || featureLookupIndices["mkmk"] != nil
    }

    /// The lookup indices `feature` runs, in ascending (apply) order.
    func orderedLookupIndices(feature: String) -> [UInt16] {
        featureLookupIndices[feature] ?? []
    }

    /// The attachment of `mark` onto `target` under the lookup at `lookupIndex`, trying
    /// each of the lookup's subtables in order (the first that covers both wins).
    func attachment(lookupIndex: UInt16, mark: UInt16, target: UInt16) -> Attachment? {
        guard case let .markAttachment(subtables) = lookupsByIndex[lookupIndex] else {
            return nil
        }
        for subtable in subtables {
            if let attachment = subtable.attachment(mark: mark, target: target) {
                return attachment
            }
        }
        return nil
    }

    /// Parses the GPOS table of `data` for `scriptTag`, falling back to `DFLT`.
    /// Returns nil if the font has no GPOS table.
    init?(fontData: Data, gposTableRange: Range<Int>?, scriptTag: String) throws {
        guard let gposTableRange else {
            return nil
        }
        let bytes = [UInt8](fontData[gposTableRange])
        let reader = TrueTypeByteReader(table: "GPOS", bytes: bytes)

        try reader.requireRange(offset: 0, count: 10)
        let majorVersion = try reader.uint16(at: 0)
        guard majorVersion == 1 else {
            throw GPOSTableError.malformed(reason: "GPOS major version must be 1")
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
            lookupsByIndex = [:]
            featureLookupIndices = [:]
            return
        }

        let features = try Self.features(reader: reader, featureListOffset: featureListOffset)
        var indicesByTag: [String: [UInt16]] = [:]
        for index in featureIndices {
            guard Int(index) < features.count else {
                throw GPOSTableError.malformed(reason: "feature index \(index) exceeds feature count")
            }
            let feature = features[Int(index)]
            indicesByTag[feature.tag, default: []].append(contentsOf: feature.lookupIndices)
        }
        featureLookupIndices = indicesByTag.mapValues { Array(Set($0)).sorted() }

        lookupsByIndex = try Self.parseAllLookups(reader: reader, lookupListOffset: lookupListOffset)
    }

    // MARK: - Lookup parsing

    private static func parseAllLookups(
        reader: TrueTypeByteReader,
        lookupListOffset: Int,
    ) throws -> [UInt16: LookupKind] {
        try reader.requireRange(offset: lookupListOffset, count: 2)
        let lookupCount = try Int(reader.uint16(at: lookupListOffset))
        try reader.requireRange(offset: lookupListOffset + 2, count: lookupCount * 2)
        var result: [UInt16: LookupKind] = [:]
        for index in 0 ..< lookupCount {
            let lookupOffset = try lookupListOffset + Int(reader.uint16(at: lookupListOffset + 2 + index * 2))
            result[UInt16(index)] = try parseLookup(reader: reader, offset: lookupOffset)
        }
        return result
    }

    private static func parseLookup(reader: TrueTypeByteReader, offset: Int) throws -> LookupKind {
        try reader.requireRange(offset: offset, count: 6)
        let lookupType = try reader.uint16(at: offset)
        let subtableCount = try Int(reader.uint16(at: offset + 4))
        try reader.requireRange(offset: offset + 6, count: subtableCount * 2)
        var subtableOffsets: [Int] = []
        subtableOffsets.reserveCapacity(subtableCount)
        for index in 0 ..< subtableCount {
            try subtableOffsets.append(offset + Int(reader.uint16(at: offset + 6 + index * 2)))
        }
        // Type 9 wraps another lookup type through an extension offset; the mark features
        // read here use direct types. Handled: 1 (single), 2 (pair), 4/6 (mark
        // attachment), 8 (chained context). Unhandled types (3 cursive, 5 mark-to-
        // ligature, 7 context) carry their number so the executor skips them knowingly.
        switch lookupType {
        case 1:
            return try .single(subtableOffsets.compactMap { try parseSinglePos(reader: reader, offset: $0) })
        case 2:
            return try .pair(subtableOffsets.compactMap { try parsePairPos(reader: reader, offset: $0) })
        case 4, 6:
            return try .markAttachment(subtableOffsets.compactMap { try parseMarkAttachment(reader: reader, offset: $0) })
        case 8:
            return try .chainedContext(subtableOffsets.compactMap { try parseChainedContext(reader: reader, offset: $0) })
        default:
            return .unsupported(type: lookupType)
        }
    }

    // MARK: - Type 1 (single) / type 2 (pair) / type 8 (chained context)

    private static func parseSinglePos(reader: TrueTypeByteReader, offset: Int) throws -> SinglePosSubtable? {
        try reader.requireRange(offset: offset, count: 6)
        let format = try reader.uint16(at: offset)
        let coverageOffset = try offset + Int(reader.uint16(at: offset + 2))
        let valueFormat = try reader.uint16(at: offset + 4)
        let coverage = try coverageIndexMap(reader: reader, offset: coverageOffset)
        switch format {
        case 1:
            let value = try readValueRecord(reader: reader, offset: offset + 6, valueFormat: valueFormat)
            return SinglePosSubtable(coverage: coverage, sharedValue: value, perGlyphValues: [])
        case 2:
            let valueCount = try Int(reader.uint16(at: offset + 6))
            let slots = GPOSValueRecord.slotCount(valueFormat: valueFormat)
            var values: [GPOSValueRecord] = []
            values.reserveCapacity(valueCount)
            for index in 0 ..< valueCount {
                try values.append(readValueRecord(reader: reader, offset: offset + 8 + index * slots * 2, valueFormat: valueFormat))
            }
            return SinglePosSubtable(coverage: coverage, sharedValue: nil, perGlyphValues: values)
        default:
            return nil
        }
    }

    private static func parsePairPos(reader: TrueTypeByteReader, offset: Int) throws -> PairPosSubtable? {
        try reader.requireRange(offset: offset, count: 10)
        let format = try reader.uint16(at: offset)
        let coverageOffset = try offset + Int(reader.uint16(at: offset + 2))
        let valueFormat1 = try reader.uint16(at: offset + 4)
        let valueFormat2 = try reader.uint16(at: offset + 6)
        let coverage = try coverageIndexMap(reader: reader, offset: coverageOffset)
        let slots1 = GPOSValueRecord.slotCount(valueFormat: valueFormat1)
        let slots2 = GPOSValueRecord.slotCount(valueFormat: valueFormat2)
        switch format {
        case 1:
            let pairSetCount = try Int(reader.uint16(at: offset + 8))
            try reader.requireRange(offset: offset + 10, count: pairSetCount * 2)
            var pairSets: [[PairPosSubtable.PairValue]] = []
            pairSets.reserveCapacity(pairSetCount)
            for index in 0 ..< pairSetCount {
                let pairSetOffset = try offset + Int(reader.uint16(at: offset + 10 + index * 2))
                let pairValueCount = try Int(reader.uint16(at: pairSetOffset))
                let recordSize = 2 + (slots1 + slots2) * 2
                var values: [PairPosSubtable.PairValue] = []
                values.reserveCapacity(pairValueCount)
                for pair in 0 ..< pairValueCount {
                    let recordOffset = pairSetOffset + 2 + pair * recordSize
                    let secondGlyph = try reader.uint16(at: recordOffset)
                    let firstValue = try readValueRecord(reader: reader, offset: recordOffset + 2, valueFormat: valueFormat1)
                    values.append(PairPosSubtable.PairValue(secondGlyph: secondGlyph, firstValue: firstValue))
                }
                pairSets.append(values)
            }
            return PairPosSubtable(
                coverage: coverage, pairSets: pairSets,
                classDef1: [:], classDef2: [:], classMatrix: [], class1Count: 0, class2Count: 0,
                isFormat1: true,
            )
        case 2:
            let classDef1Offset = try offset + Int(reader.uint16(at: offset + 8))
            let classDef2Offset = try offset + Int(reader.uint16(at: offset + 10))
            let class1Count = try Int(reader.uint16(at: offset + 12))
            let class2Count = try Int(reader.uint16(at: offset + 14))
            let classDef1 = try classDefinitionMap(reader: reader, offset: classDef1Offset)
            let classDef2 = try classDefinitionMap(reader: reader, offset: classDef2Offset)
            let recordSize = (slots1 + slots2) * 2
            var matrix: [[GPOSValueRecord]] = []
            matrix.reserveCapacity(class1Count)
            for class1 in 0 ..< class1Count {
                var row: [GPOSValueRecord] = []
                row.reserveCapacity(class2Count)
                for class2 in 0 ..< class2Count {
                    let recordOffset = offset + 16 + (class1 * class2Count + class2) * recordSize
                    try row.append(readValueRecord(reader: reader, offset: recordOffset, valueFormat: valueFormat1))
                }
                matrix.append(row)
            }
            return PairPosSubtable(
                coverage: coverage, pairSets: [],
                classDef1: classDef1, classDef2: classDef2, classMatrix: matrix,
                class1Count: class1Count, class2Count: class2Count, isFormat1: false,
            )
        default:
            return nil
        }
    }

    private static func parseChainedContext(reader: TrueTypeByteReader, offset: Int) throws -> ChainedContextSubtable? {
        try reader.requireRange(offset: offset, count: 2)
        let format = try reader.uint16(at: offset)
        guard format == 3 else {
            return nil
        }
        var cursor = offset + 2
        func readCoverageList() throws -> [Set<UInt16>] {
            try reader.requireRange(offset: cursor, count: 2)
            let count = try Int(reader.uint16(at: cursor))
            try reader.requireRange(offset: cursor + 2, count: count * 2)
            var sets: [Set<UInt16>] = []
            sets.reserveCapacity(count)
            for index in 0 ..< count {
                let coverageOffset = try offset + Int(reader.uint16(at: cursor + 2 + index * 2))
                try sets.append(Set(coverageGlyphIDs(reader: reader, offset: coverageOffset)))
            }
            cursor += 2 + count * 2
            return sets
        }
        let backtrack = try readCoverageList()
        let input = try readCoverageList()
        let lookahead = try readCoverageList()
        try reader.requireRange(offset: cursor, count: 2)
        let recordCount = try Int(reader.uint16(at: cursor))
        try reader.requireRange(offset: cursor + 2, count: recordCount * 4)
        var records: [SequencePosLookup] = []
        records.reserveCapacity(recordCount)
        for index in 0 ..< recordCount {
            let recordOffset = cursor + 2 + index * 4
            let sequenceIndex = try Int(reader.uint16(at: recordOffset))
            let lookupIndex = try reader.uint16(at: recordOffset + 2)
            records.append(SequencePosLookup(sequenceIndex: sequenceIndex, lookupIndex: lookupIndex))
        }
        return ChainedContextSubtable(
            backtrackCoverage: backtrack, inputCoverage: input,
            lookaheadCoverage: lookahead, sequenceLookups: records,
        )
    }

    private static func readValueRecord(reader: TrueTypeByteReader, offset: Int, valueFormat: UInt16) throws -> GPOSValueRecord {
        var cursor = offset
        func next(_ bit: UInt16) throws -> Int {
            guard valueFormat & bit != 0 else {
                return 0
            }
            let value = try Int(reader.int16(at: cursor))
            cursor += 2
            return value
        }
        let xPlacement = try next(0x0001)
        let yPlacement = try next(0x0002)
        let xAdvance = try next(0x0004)
        let yAdvance = try next(0x0008)
        return GPOSValueRecord(xPlacement: xPlacement, yPlacement: yPlacement, xAdvance: xAdvance, yAdvance: yAdvance)
    }

    private static func classDefinitionMap(reader: TrueTypeByteReader, offset: Int) throws -> [UInt16: Int] {
        try reader.requireRange(offset: offset, count: 2)
        let format = try reader.uint16(at: offset)
        var map: [UInt16: Int] = [:]
        switch format {
        case 1:
            try reader.requireRange(offset: offset + 2, count: 4)
            let startGlyph = try reader.uint16(at: offset + 2)
            let glyphCount = try Int(reader.uint16(at: offset + 4))
            try reader.requireRange(offset: offset + 6, count: glyphCount * 2)
            for index in 0 ..< glyphCount {
                let classValue = try Int(reader.uint16(at: offset + 6 + index * 2))
                if classValue != 0 {
                    map[startGlyph + UInt16(index)] = classValue
                }
            }
        case 2:
            try reader.requireRange(offset: offset + 2, count: 2)
            let rangeCount = try Int(reader.uint16(at: offset + 2))
            try reader.requireRange(offset: offset + 4, count: rangeCount * 6)
            for index in 0 ..< rangeCount {
                let rangeOffset = offset + 4 + index * 6
                let startGlyph = try reader.uint16(at: rangeOffset)
                let endGlyph = try reader.uint16(at: rangeOffset + 2)
                let classValue = try Int(reader.uint16(at: rangeOffset + 4))
                guard startGlyph <= endGlyph else {
                    throw GPOSTableError.malformed(reason: "class range is unordered")
                }
                if classValue != 0 {
                    for glyph in startGlyph ... endGlyph {
                        map[glyph] = classValue
                    }
                }
            }
        default:
            throw GPOSTableError.malformed(reason: "class definition format must be 1 or 2")
        }
        return map
    }

    /// Parses a MarkBasePosFormat1 / MarkMarkPosFormat1 subtable (identical field
    /// layout: mark coverage, target coverage, class count, mark array, target array).
    /// Returns nil for an unhandled subtable format.
    private static func parseMarkAttachment(reader: TrueTypeByteReader, offset: Int) throws -> MarkAttachmentSubtable? {
        try reader.requireRange(offset: offset, count: 12)
        let format = try reader.uint16(at: offset)
        guard format == 1 else {
            return nil
        }
        let markCoverageOffset = try offset + Int(reader.uint16(at: offset + 2))
        let targetCoverageOffset = try offset + Int(reader.uint16(at: offset + 4))
        let classCount = try Int(reader.uint16(at: offset + 6))
        let markArrayOffset = try offset + Int(reader.uint16(at: offset + 8))
        let targetArrayOffset = try offset + Int(reader.uint16(at: offset + 10))
        guard classCount > 0 else {
            throw GPOSTableError.malformed(reason: "mark attachment class count must be positive")
        }

        let markCoverage = try coverageIndexMap(reader: reader, offset: markCoverageOffset)
        let targetCoverage = try coverageIndexMap(reader: reader, offset: targetCoverageOffset)
        let marks = try parseMarkArray(reader: reader, offset: markArrayOffset)
        let targetAnchors = try parseAnchorMatrix(reader: reader, offset: targetArrayOffset, classCount: classCount)
        return MarkAttachmentSubtable(
            markCoverage: markCoverage,
            marks: marks,
            targetCoverage: targetCoverage,
            targetAnchors: targetAnchors,
            classCount: classCount,
        )
    }

    private static func parseMarkArray(reader: TrueTypeByteReader, offset: Int) throws -> [MarkRecord] {
        try reader.requireRange(offset: offset, count: 2)
        let markCount = try Int(reader.uint16(at: offset))
        try reader.requireRange(offset: offset + 2, count: markCount * 4)
        var records: [MarkRecord] = []
        records.reserveCapacity(markCount)
        for index in 0 ..< markCount {
            let recordOffset = offset + 2 + index * 4
            let markClass = try reader.uint16(at: recordOffset)
            let anchorOffset = try Int(reader.uint16(at: recordOffset + 2))
            let anchor = try parseAnchor(reader: reader, offset: offset + anchorOffset)
            records.append(MarkRecord(markClass: markClass, anchor: anchor))
        }
        return records
    }

    /// A count-prefixed array of records, each `classCount` anchor offsets (relative to
    /// the array start; 0 = no anchor). Used for both BaseArray and Mark2Array.
    private static func parseAnchorMatrix(
        reader: TrueTypeByteReader,
        offset: Int,
        classCount: Int,
    ) throws -> [[GPOSAnchor?]] {
        try reader.requireRange(offset: offset, count: 2)
        let recordCount = try Int(reader.uint16(at: offset))
        try reader.requireRange(offset: offset + 2, count: recordCount * classCount * 2)
        var matrix: [[GPOSAnchor?]] = []
        matrix.reserveCapacity(recordCount)
        for record in 0 ..< recordCount {
            var anchors: [GPOSAnchor?] = []
            anchors.reserveCapacity(classCount)
            for classIndex in 0 ..< classCount {
                let anchorOffset = try Int(reader.uint16(at: offset + 2 + (record * classCount + classIndex) * 2))
                try anchors.append(anchorOffset == 0 ? nil : parseAnchor(reader: reader, offset: offset + anchorOffset))
            }
            matrix.append(anchors)
        }
        return matrix
    }

    private static func parseAnchor(reader: TrueTypeByteReader, offset: Int) throws -> GPOSAnchor {
        try reader.requireRange(offset: offset, count: 6)
        let format = try reader.uint16(at: offset)
        guard 1 ... 3 ~= format else {
            throw GPOSTableError.malformed(reason: "anchor format must be 1, 2, or 3")
        }
        // Formats 1/2/3 all begin with x, y in font units; the contour point (format 2)
        // and device tables (format 3) that follow are refinements not applied here.
        let x = try reader.int16(at: offset + 2)
        let y = try reader.int16(at: offset + 4)
        return GPOSAnchor(x: x, y: y)
    }

    private static func coverageIndexMap(reader: TrueTypeByteReader, offset: Int) throws -> [UInt16: Int] {
        let glyphs = try coverageGlyphIDs(reader: reader, offset: offset)
        var map: [UInt16: Int] = [:]
        map.reserveCapacity(glyphs.count)
        for (index, glyph) in glyphs.enumerated() {
            map[glyph] = index
        }
        return map
    }

    private static func coverageGlyphIDs(reader: TrueTypeByteReader, offset: Int) throws -> [UInt16] {
        try reader.requireRange(offset: offset, count: 4)
        let format = try reader.uint16(at: offset)
        switch format {
        case 1:
            let glyphCount = try Int(reader.uint16(at: offset + 2))
            try reader.requireRange(offset: offset + 4, count: glyphCount * 2)
            return try (0 ..< glyphCount).map { try reader.uint16(at: offset + 4 + $0 * 2) }
        case 2:
            let rangeCount = try Int(reader.uint16(at: offset + 2))
            try reader.requireRange(offset: offset + 4, count: rangeCount * 6)
            var glyphs: [UInt16] = []
            for index in 0 ..< rangeCount {
                let rangeOffset = offset + 4 + index * 6
                let startGlyphID = try reader.uint16(at: rangeOffset)
                let endGlyphID = try reader.uint16(at: rangeOffset + 2)
                guard startGlyphID <= endGlyphID else {
                    throw GPOSTableError.malformed(reason: "coverage range is unordered")
                }
                glyphs.append(contentsOf: startGlyphID ... endGlyphID)
            }
            return glyphs
        default:
            throw GPOSTableError.malformed(reason: "coverage format must be 1 or 2")
        }
    }

    // MARK: - Script / feature discovery (GPOS shares GSUB's header layout)

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
        let langSysOffset = scriptOffset + defaultLangSysOffset
        try reader.requireRange(offset: langSysOffset, count: 6)
        let requiredFeatureIndex = try reader.uint16(at: langSysOffset + 2)
        let featureIndexCount = try Int(reader.uint16(at: langSysOffset + 4))
        try reader.requireRange(offset: langSysOffset + 6, count: featureIndexCount * 2)
        var indices = Set<UInt16>()
        if requiredFeatureIndex != 0xFFFF {
            indices.insert(requiredFeatureIndex)
        }
        for index in 0 ..< featureIndexCount {
            try indices.insert(reader.uint16(at: langSysOffset + 6 + index * 2))
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
}
