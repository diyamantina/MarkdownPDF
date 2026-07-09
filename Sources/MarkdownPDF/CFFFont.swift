import Foundation

/// A reader for the `CFF ` (Compact Font Format, Adobe Type 2) table that OpenType
/// fonts with PostScript outlines (`OTTO`) carry instead of `glyf`. It parses the
/// structure an embedder needs: the glyph count, whether the font is CID-keyed
/// (a `ROS` operator, the usual shape for CJK), the charstring type, and the charset
/// that maps each glyph id to its CID (CID-keyed) or SID (name-keyed).
///
/// This is a parser only. Emitting a subset `FontFile3` / `CIDFontType0` is the
/// separate, larger step it lays the groundwork for; the `glyf` embedding path is
/// untouched. Every read is bounds-checked through `TrueTypeByteReader`; malformed
/// input throws a typed error rather than trapping. Derived from the Adobe CFF and
/// Type 2 Charstring specifications.
struct CFFFont: Equatable {
    enum ParseError: Error, Equatable {
        case malformed(reason: String)
    }

    /// Whether the font is CID-keyed (carries a `ROS` operator). CJK OpenType fonts
    /// are almost always CID-keyed; `charset` then maps glyph id to CID.
    let isCIDKeyed: Bool
    /// The number of glyphs, i.e. the CharStrings INDEX count.
    let glyphCount: Int
    /// The charstring interpreter type (2 for modern CFF; the default when absent).
    let charstringType: Int
    /// Glyph id to CID (CID-keyed) or to SID (name-keyed). Length is `glyphCount`;
    /// glyph 0 is always `.notdef` (CID/SID 0).
    let charset: [UInt16]

    init(bytes: [UInt8]) throws {
        let reader = TrueTypeByteReader(table: "CFF ", bytes: bytes)

        // Header: major, minor, hdrSize, offSize (the last is the Top DICT INDEX
        // offset size, unused here). Only CFF major version 1 is Type 2; CFF2 (major
        // 2) is a different, variable-font format handled elsewhere.
        let major = try reader.uint8(at: 0)
        guard major == 1 else {
            throw ParseError.malformed(reason: "unsupported CFF major version \(major)")
        }
        let headerSize = try Int(reader.uint8(at: 2))

        // Name INDEX, then the Top DICT INDEX (one entry for a single-font CFF).
        let nameIndex = try Self.index(reader: reader, at: headerSize)
        let topDictIndex = try Self.index(reader: reader, at: nameIndex.end)
        guard let topDictRange = topDictIndex.objects.first else {
            throw ParseError.malformed(reason: "the Top DICT INDEX is empty")
        }

        let topDict = try Self.parseDictionary(reader: reader, range: topDictRange)
        isCIDKeyed = topDict[.ros] != nil
        charstringType = topDict[.charstringType]?.first.map(Int.init) ?? 2

        guard let charStringsOffset = topDict[.charStrings]?.first.map(Int.init) else {
            throw ParseError.malformed(reason: "the Top DICT has no CharStrings offset")
        }
        let charStringsIndex = try Self.index(reader: reader, at: charStringsOffset)
        glyphCount = charStringsIndex.objects.count
        guard glyphCount > 0 else {
            throw ParseError.malformed(reason: "the font has no glyphs")
        }

        let charsetOffset = topDict[.charset]?.first.map(Int.init) ?? 0
        charset = try Self.parseCharset(reader: reader, offset: charsetOffset, glyphCount: glyphCount)
    }

    // MARK: - INDEX

    private struct IndexResult {
        var objects: [Range<Int>]
        var end: Int
    }

    /// Reads a CFF INDEX at `offset`: a `count` (uint16), an `offSize`, a `count+1`
    /// array of 1-based offsets each `offSize` bytes, then the object data. Returns
    /// each object's absolute byte range and the offset just past the INDEX.
    private static func index(reader: TrueTypeByteReader, at offset: Int) throws -> IndexResult {
        let count = try Int(reader.uint16(at: offset))
        guard count > 0 else {
            return IndexResult(objects: [], end: offset + 2)
        }
        let offSize = try Int(reader.uint8(at: offset + 2))
        guard (1 ... 4).contains(offSize) else {
            throw ParseError.malformed(reason: "INDEX offSize \(offSize) is out of range")
        }
        let offsetsStart = offset + 3
        // Offsets are 1-based from the byte preceding the object data.
        let dataBase = offsetsStart + (count + 1) * offSize - 1
        try reader.requireRange(offset: offsetsStart, count: (count + 1) * offSize)

        var offsets: [Int] = []
        offsets.reserveCapacity(count + 1)
        for index in 0 ... count {
            try offsets.append(readOffset(reader: reader, at: offsetsStart + index * offSize, size: offSize))
        }
        guard offsets[0] == 1 else {
            throw ParseError.malformed(reason: "INDEX first offset must be 1")
        }

        var objects: [Range<Int>] = []
        objects.reserveCapacity(count)
        for index in 0 ..< count {
            let start = dataBase + offsets[index]
            let end = dataBase + offsets[index + 1]
            guard offsets[index] <= offsets[index + 1] else {
                throw ParseError.malformed(reason: "INDEX offsets are not monotonic")
            }
            try reader.requireRange(offset: start, count: end - start)
            objects.append(start ..< end)
        }
        return IndexResult(objects: objects, end: dataBase + offsets[count])
    }

    private static func readOffset(reader: TrueTypeByteReader, at offset: Int, size: Int) throws -> Int {
        var value = 0
        for byte in 0 ..< size {
            value = try value << 8 | Int(reader.uint8(at: offset + byte))
        }
        return value
    }

    // MARK: - Top DICT

    private enum Operator: Hashable {
        case charStrings // 17
        case charset // 15
        case charstringType // 12 6
        case ros // 12 30
        case other
    }

    /// Parses a DICT (Top DICT) into the operators this reader cares about mapped to
    /// their integer operands. Reals and unrelated operators are consumed but ignored.
    private static func parseDictionary(
        reader: TrueTypeByteReader,
        range: Range<Int>,
    ) throws -> [Operator: [Int32]] {
        var result: [Operator: [Int32]] = [:]
        var operands: [Int32] = []
        var cursor = range.lowerBound
        while cursor < range.upperBound {
            let byte = try reader.uint8(at: cursor)
            switch byte {
            case 0 ... 21:
                let op: Operator
                if byte == 12 {
                    cursor += 1
                    let second = try reader.uint8(at: cursor)
                    op = switch second {
                    case 6: .charstringType
                    case 30: .ros
                    default: .other
                    }
                } else {
                    op = switch byte {
                    case 15: .charset
                    case 17: .charStrings
                    default: .other
                    }
                }
                result[op] = operands
                operands = []
                cursor += 1
            case 28:
                try operands.append(Int32(reader.int16(at: cursor + 1)))
                cursor += 3
            case 29:
                try operands.append(Int32(bitPattern: reader.uint32(at: cursor + 1)))
                cursor += 5
            case 30:
                // Real number: nibble-encoded, terminated by 0xf. Consumed, not used.
                cursor += 1
                consume: while cursor < range.upperBound {
                    let pair = try reader.uint8(at: cursor)
                    cursor += 1
                    if pair & 0x0F == 0x0F || pair >> 4 == 0x0F {
                        break consume
                    }
                }
            case 32 ... 246:
                operands.append(Int32(byte) - 139)
                cursor += 1
            case 247 ... 250:
                let next = try Int32(reader.uint8(at: cursor + 1))
                operands.append((Int32(byte) - 247) * 256 + next + 108)
                cursor += 2
            case 251 ... 254:
                let next = try Int32(reader.uint8(at: cursor + 1))
                operands.append(-(Int32(byte) - 251) * 256 - next - 108)
                cursor += 2
            default:
                throw ParseError.malformed(reason: "invalid DICT byte \(byte)")
            }
        }
        return result
    }

    // MARK: - Charset

    /// Parses the charset into a glyph-id to CID/SID array of length `glyphCount`.
    /// Offsets 0/1/2 are the predefined charsets; a CID-keyed font always uses a
    /// custom charset (offset > 2), so the predefined case is the identity fallback.
    private static func parseCharset(
        reader: TrueTypeByteReader,
        offset: Int,
        glyphCount: Int,
    ) throws -> [UInt16] {
        guard offset > 2 else {
            // Predefined charset: glyph id maps to itself for our purposes (the CID
            // of a CID-keyed font is never predefined, so this only affects the rare
            // name-keyed-with-predefined-charset case, where identity is a safe base).
            return (0 ..< glyphCount).map { UInt16(truncatingIfNeeded: $0) }
        }
        var charset = [UInt16](repeating: 0, count: glyphCount)
        let format = try reader.uint8(at: offset)
        switch format {
        case 0:
            for glyph in 1 ..< glyphCount {
                charset[glyph] = try reader.uint16(at: offset + 1 + (glyph - 1) * 2)
            }
        case 1, 2:
            var cursor = offset + 1
            var glyph = 1
            while glyph < glyphCount {
                let first = try reader.uint16(at: cursor)
                cursor += 2
                let leftInRange: Int
                if format == 1 {
                    leftInRange = try Int(reader.uint8(at: cursor))
                    cursor += 1
                } else {
                    leftInRange = try Int(reader.uint16(at: cursor))
                    cursor += 2
                }
                for step in 0 ... leftInRange where glyph < glyphCount {
                    charset[glyph] = UInt16(truncatingIfNeeded: Int(first) + step)
                    glyph += 1
                }
            }
        default:
            throw ParseError.malformed(reason: "unsupported charset format \(format)")
        }
        return charset
    }
}
