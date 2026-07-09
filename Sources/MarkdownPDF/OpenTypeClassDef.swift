import Foundation

/// An OpenType ClassDef table (spec: OpenType chapter 2, "Class Definition Table").
/// It maps glyph ids to class values; any glyph not listed is class 0. Used by GDEF
/// (glyph classes for mark skipping) and by class-based contextual lookups (GSUB/GPOS
/// format 2).
///
/// Ranges are kept as-is and queried by scan rather than expanded into a per-glyph
/// dictionary, so a format-2 table covering a large glyph span stays compact.
struct OpenTypeClassDef: Equatable {
    /// Class 0 is the implicit default for any glyph outside every stored range.
    private let ranges: [ClassRange]

    private struct ClassRange: Equatable {
        var startGlyphID: UInt16
        var endGlyphID: UInt16
        var classValue: UInt16
    }

    /// The class assigned to `glyph`, or 0 when the glyph is not listed.
    func classValue(for glyph: UInt16) -> UInt16 {
        for range in ranges where glyph >= range.startGlyphID && glyph <= range.endGlyphID {
            return range.classValue
        }
        return 0
    }

    /// Parses a ClassDef at `offset` (relative to `reader`'s table bytes).
    static func parse(reader: TrueTypeByteReader, offset: Int) throws -> OpenTypeClassDef {
        try reader.requireRange(offset: offset, count: 2)
        let format = try reader.uint16(at: offset)
        switch format {
        case 1:
            try reader.requireRange(offset: offset + 2, count: 4)
            let startGlyphID = try reader.uint16(at: offset + 2)
            let glyphCount = try Int(reader.uint16(at: offset + 4))
            try reader.requireRange(offset: offset + 6, count: glyphCount * 2)
            // The run [startGlyphID, startGlyphID + glyphCount) must fit the glyph-id
            // space; a table that runs past 0xFFFF is malformed and must not wrap.
            guard Int(startGlyphID) + glyphCount <= 0x10000 else {
                throw GSUBTable.GSUBTableError.malformed(reason: "ClassDef format 1 run exceeds the glyph-id space")
            }
            var ranges: [ClassRange] = []
            ranges.reserveCapacity(glyphCount)
            for index in 0 ..< glyphCount {
                let classValue = try reader.uint16(at: offset + 6 + index * 2)
                guard classValue != 0 else {
                    continue // class 0 is the default; storing it wastes space
                }
                let glyphID = startGlyphID + UInt16(index)
                ranges.append(ClassRange(startGlyphID: glyphID, endGlyphID: glyphID, classValue: classValue))
            }
            return OpenTypeClassDef(ranges: ranges)
        case 2:
            try reader.requireRange(offset: offset + 2, count: 2)
            let rangeCount = try Int(reader.uint16(at: offset + 2))
            try reader.requireRange(offset: offset + 4, count: rangeCount * 6)
            var ranges: [ClassRange] = []
            ranges.reserveCapacity(rangeCount)
            for index in 0 ..< rangeCount {
                let recordOffset = offset + 4 + index * 6
                let startGlyphID = try reader.uint16(at: recordOffset)
                let endGlyphID = try reader.uint16(at: recordOffset + 2)
                let classValue = try reader.uint16(at: recordOffset + 4)
                guard startGlyphID <= endGlyphID else {
                    throw GSUBTable.GSUBTableError.malformed(reason: "ClassDef range is unordered")
                }
                guard classValue != 0 else {
                    continue
                }
                ranges.append(ClassRange(startGlyphID: startGlyphID, endGlyphID: endGlyphID, classValue: classValue))
            }
            return OpenTypeClassDef(ranges: ranges)
        default:
            throw GSUBTable.GSUBTableError.malformed(reason: "ClassDef format must be 1 or 2")
        }
    }
}
