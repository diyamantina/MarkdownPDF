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

    private struct MarkRecord: Equatable {
        var markClass: UInt16
        var anchor: GPOSAnchor
    }

    /// A mark-to-base (type 4) or mark-to-mark (type 6) subtable. The two are identical
    /// in shape: a set of marks (each with a class and an anchor) attach to a set of
    /// targets (each carrying one anchor per mark class).
    private struct MarkAttachmentSubtable: Equatable {
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

    private enum Lookup {
        case markAttachment(MarkAttachmentSubtable)
        case unsupported
    }

    private let lookupsByIndex: [UInt16: [Lookup]]
    private let featureLookupIndices: [String: [UInt16]]

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
        guard let subtables = lookupsByIndex[lookupIndex] else {
            return nil
        }
        for case let .markAttachment(subtable) in subtables {
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
    ) throws -> [UInt16: [Lookup]] {
        try reader.requireRange(offset: lookupListOffset, count: 2)
        let lookupCount = try Int(reader.uint16(at: lookupListOffset))
        try reader.requireRange(offset: lookupListOffset + 2, count: lookupCount * 2)
        var result: [UInt16: [Lookup]] = [:]
        for index in 0 ..< lookupCount {
            let lookupOffset = try lookupListOffset + Int(reader.uint16(at: lookupListOffset + 2 + index * 2))
            result[UInt16(index)] = try parseLookup(reader: reader, offset: lookupOffset)
        }
        return result
    }

    private static func parseLookup(reader: TrueTypeByteReader, offset: Int) throws -> [Lookup] {
        try reader.requireRange(offset: offset, count: 6)
        let lookupType = try reader.uint16(at: offset)
        let subtableCount = try Int(reader.uint16(at: offset + 4))
        try reader.requireRange(offset: offset + 6, count: subtableCount * 2)
        var subtableOffsets: [Int] = []
        subtableOffsets.reserveCapacity(subtableCount)
        for index in 0 ..< subtableCount {
            try subtableOffsets.append(offset + Int(reader.uint16(at: offset + 6 + index * 2)))
        }
        // Types 4 (mark-to-base) and 6 (mark-to-mark) share the same subtable shape:
        // a mark array attaching to a target array of per-class anchors. Other types
        // (1 single, 2 pair/kern, 3 cursive, 5 mark-to-ligature) are not applied.
        switch lookupType {
        case 4, 6:
            return try subtableOffsets.map { subtableOffset in
                guard let subtable = try parseMarkAttachment(reader: reader, offset: subtableOffset) else {
                    return .unsupported
                }
                return .markAttachment(subtable)
            }
        default:
            return [.unsupported]
        }
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
