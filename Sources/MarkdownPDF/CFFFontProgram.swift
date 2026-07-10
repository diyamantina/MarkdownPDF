import Foundation

/// The full parsed contents of a `CFF ` (Compact Font Format, Adobe Type 2) program that
/// a subsetter needs: the per-glyph charstrings, the global and local subroutines they
/// call, and (for a CID-keyed font) the FDSelect that assigns each glyph to a Font DICT
/// and the FDArray of Private DICTs. `CFFFont` parses only the shape an embedder inspects
/// (glyph count, CID-keyedness, charset); this parses the byte tables a rewrite consumes.
///
/// Every read is bounds-checked through `TrueTypeByteReader`; malformed input throws a
/// typed error rather than trapping. Derived from the Adobe CFF and Type 2 Charstring
/// specifications (Adobe Tech Notes 5176 and 5177).
struct CFFFontProgram: Equatable {
    enum ParseError: Error, Equatable {
        case malformed(reason: String)
    }

    /// A Private DICT and its local subroutines, one per Font DICT. `defaultWidthX` and
    /// `nominalWidthX` decode a charstring's leading width operand, so the subset must
    /// carry them to keep advances correct.
    struct PrivateDict: Equatable {
        var defaultWidthX: Int
        var nominalWidthX: Int
        var localSubrs: [[UInt8]]
    }

    var isCIDKeyed: Bool
    var charstringType: Int
    /// Glyph id to CID (CID-keyed) or SID (name-keyed); length is the glyph count.
    var charset: [UInt16]
    /// The Registry-Ordering-Supplement operands of a CID-keyed font's `ROS`, needed to
    /// re-emit the subset's Top DICT. Empty for a name-keyed font.
    var ros: [Int32]
    /// One charstring (Type 2 bytecode) per glyph.
    var charStrings: [[UInt8]]
    /// The global subroutines, shared across all glyphs.
    var globalSubrs: [[UInt8]]
    /// The Font DICTs' Private DICTs. A name-keyed font has exactly one; a CID-keyed font
    /// has one per FDArray entry.
    var privateDicts: [PrivateDict]
    /// Glyph id to Font DICT index (into `privateDicts`); length is the glyph count. A
    /// name-keyed font maps every glyph to the single Private DICT (all zero).
    var fdSelect: [Int]
    /// The custom strings (String INDEX), indexed by `SID - 391`; standard strings
    /// (SID < 391) are not stored here. A subset re-emits the strings its `ROS` references.
    var strings: [[UInt8]]
    /// The font's PostScript name (the first, and only, Name INDEX entry).
    var fontName: [UInt8]
    /// Whether the Top DICT or any Font DICT carries an explicit `FontMatrix`. The
    /// subsetter re-emits neither, so it declines to subset such a font (the caller then
    /// embeds the whole program) rather than silently render it at the wrong scale.
    var hasExplicitFontMatrix: Bool

    var glyphCount: Int {
        charStrings.count
    }

    /// The bytes of the string with `sid`, or nil for a standard string (SID < 391, which
    /// the reader does not carry) or an out-of-range SID.
    func string(sid: Int) -> [UInt8]? {
        let index = sid - 391
        guard index >= 0, index < strings.count else {
            return nil
        }
        return strings[index]
    }

    init(bytes: [UInt8]) throws {
        let reader = TrueTypeByteReader(table: "CFF ", bytes: bytes)

        let major = try reader.uint8(at: 0)
        guard major == 1 else {
            throw ParseError.malformed(reason: "unsupported CFF major version \(major)")
        }
        let headerSize = try Int(reader.uint8(at: 2))

        // Name INDEX, Top DICT INDEX, String INDEX, Global Subr INDEX, in sequence.
        let nameIndex = try Self.index(reader: reader, at: headerSize)
        fontName = try nameIndex.objects.first.map { try reader.bytes(in: $0) } ?? Array("CIDFont".utf8)
        let topDictIndex = try Self.index(reader: reader, at: nameIndex.end)
        guard let topDictRange = topDictIndex.objects.first else {
            throw ParseError.malformed(reason: "the Top DICT INDEX is empty")
        }
        let stringIndex = try Self.index(reader: reader, at: topDictIndex.end)
        strings = try stringIndex.objects.map { try reader.bytes(in: $0) }
        let globalSubrIndex = try Self.index(reader: reader, at: stringIndex.end)
        globalSubrs = try globalSubrIndex.objects.map { try reader.bytes(in: $0) }

        let topDict = try Self.parseDictionary(reader: reader, range: topDictRange)
        ros = topDict[.ros] ?? []
        isCIDKeyed = topDict[.ros] != nil
        charstringType = topDict[.charstringType]?.first.map(Int.init) ?? 2

        guard let charStringsOffset = topDict[.charStrings]?.first.map(Int.init) else {
            throw ParseError.malformed(reason: "the Top DICT has no CharStrings offset")
        }
        let charStringsIndex = try Self.index(reader: reader, at: charStringsOffset)
        let glyphCount = charStringsIndex.objects.count
        guard glyphCount > 0 else {
            throw ParseError.malformed(reason: "the font has no glyphs")
        }
        charStrings = try charStringsIndex.objects.map { try reader.bytes(in: $0) }

        let charsetOffset = topDict[.charset]?.first.map(Int.init) ?? 0
        charset = try Self.parseCharset(reader: reader, offset: charsetOffset, glyphCount: glyphCount)

        if isCIDKeyed {
            guard let fdArrayOffset = topDict[.fdArray]?.first.map(Int.init),
                  let fdSelectOffset = topDict[.fdSelect]?.first.map(Int.init)
            else {
                throw ParseError.malformed(reason: "a CID-keyed font must have FDArray and FDSelect")
            }
            let fdArray = try Self.parseFDArray(reader: reader, offset: fdArrayOffset)
            privateDicts = fdArray.dicts
            fdSelect = try Self.parseFDSelect(reader: reader, offset: fdSelectOffset, glyphCount: glyphCount)
            hasExplicitFontMatrix = topDict[.fontMatrix] != nil || fdArray.hasFontMatrix
        } else {
            let privateDict = try Self.parsePrivate(reader: reader, operands: topDict[.privateDict] ?? [])
            privateDicts = [privateDict]
            fdSelect = [Int](repeating: 0, count: glyphCount)
            hasExplicitFontMatrix = topDict[.fontMatrix] != nil
        }
        for fd in fdSelect where fd < 0 || fd >= privateDicts.count {
            throw ParseError.malformed(reason: "FDSelect entry \(fd) is out of range")
        }
    }

    // MARK: - INDEX

    private struct IndexResult {
        var objects: [Range<Int>]
        var end: Int
    }

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

    // MARK: - DICT

    private enum Operator: Hashable {
        case charStrings // 17
        case charset // 15
        case charstringType // 12 6
        case ros // 12 30
        case fontMatrix // 12 7
        case fdArray // 12 36
        case fdSelect // 12 37
        case privateDict // 18
        case subrs // 19 (Private DICT)
        case defaultWidthX // 20 (Private DICT)
        case nominalWidthX // 21 (Private DICT)
        case other
    }

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
                    case 7: .fontMatrix
                    case 30: .ros
                    case 36: .fdArray
                    case 37: .fdSelect
                    default: .other
                    }
                } else {
                    op = switch byte {
                    case 15: .charset
                    case 17: .charStrings
                    case 18: .privateDict
                    case 19: .subrs
                    case 20: .defaultWidthX
                    case 21: .nominalWidthX
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

    // MARK: - FDArray / FDSelect / Private

    private static func parseFDArray(
        reader: TrueTypeByteReader,
        offset: Int,
    ) throws -> (dicts: [PrivateDict], hasFontMatrix: Bool) {
        let fdIndex = try index(reader: reader, at: offset)
        var dicts: [PrivateDict] = []
        dicts.reserveCapacity(fdIndex.objects.count)
        var hasFontMatrix = false
        for range in fdIndex.objects {
            let fontDict = try parseDictionary(reader: reader, range: range)
            if fontDict[.fontMatrix] != nil {
                hasFontMatrix = true
            }
            try dicts.append(parsePrivate(reader: reader, operands: fontDict[.privateDict] ?? []))
        }
        return (dicts, hasFontMatrix)
    }

    private static func parsePrivate(reader: TrueTypeByteReader, operands: [Int32]) throws -> PrivateDict {
        guard operands.count == 2 else {
            // No Private DICT (or a malformed operand pair): a font with no hinting still
            // has valid charstrings; default the widths and carry no local subrs.
            return PrivateDict(defaultWidthX: 0, nominalWidthX: 0, localSubrs: [])
        }
        let size = Int(operands[0])
        let privateOffset = Int(operands[1])
        let privateRange = privateOffset ..< privateOffset + size
        try reader.requireRange(offset: privateOffset, count: size)
        let privateDict = try parseDictionary(reader: reader, range: privateRange)
        let defaultWidthX = privateDict[.defaultWidthX]?.first.map(Int.init) ?? 0
        let nominalWidthX = privateDict[.nominalWidthX]?.first.map(Int.init) ?? 0
        var localSubrs: [[UInt8]] = []
        if let subrsOffset = privateDict[.subrs]?.first.map(Int.init) {
            // The Subrs offset is relative to the start of the Private DICT.
            let subrIndex = try index(reader: reader, at: privateOffset + subrsOffset)
            localSubrs = try subrIndex.objects.map { try reader.bytes(in: $0) }
        }
        return PrivateDict(defaultWidthX: defaultWidthX, nominalWidthX: nominalWidthX, localSubrs: localSubrs)
    }

    private static func parseFDSelect(reader: TrueTypeByteReader, offset: Int, glyphCount: Int) throws -> [Int] {
        let format = try reader.uint8(at: offset)
        var result = [Int](repeating: 0, count: glyphCount)
        switch format {
        case 0:
            try reader.requireRange(offset: offset + 1, count: glyphCount)
            for glyph in 0 ..< glyphCount {
                result[glyph] = try Int(reader.uint8(at: offset + 1 + glyph))
            }
        case 3:
            let rangeCount = try Int(reader.uint16(at: offset + 1))
            var cursor = offset + 3
            for _ in 0 ..< rangeCount {
                let first = try Int(reader.uint16(at: cursor))
                let fd = try Int(reader.uint8(at: cursor + 2))
                let next = try Int(reader.uint16(at: cursor + 3))
                guard first < next, next <= glyphCount else {
                    throw ParseError.malformed(reason: "FDSelect range is out of order")
                }
                for glyph in first ..< next {
                    result[glyph] = fd
                }
                cursor += 3
            }
        default:
            throw ParseError.malformed(reason: "unsupported FDSelect format \(format)")
        }
        return result
    }

    // MARK: - Charset

    private static func parseCharset(
        reader: TrueTypeByteReader,
        offset: Int,
        glyphCount: Int,
    ) throws -> [UInt16] {
        guard offset > 2 else {
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
