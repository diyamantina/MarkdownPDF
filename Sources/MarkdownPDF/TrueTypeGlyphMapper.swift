import Foundation

struct TrueTypeGlyphMapper {
    enum MissingGlyphPolicy: Equatable {
        case reject
        case useNotdef
    }

    struct TextMapping: Equatable {
        var sourceText: String
        var glyphs: [Glyph]

        var totalWidth: Double {
            glyphs.reduce(0) { $0 + $1.width }
        }
    }

    struct Glyph: Equatable {
        var scalar: UnicodeScalar
        var glyphID: UInt16
        var cid: UInt16
        var pdfCharacterCode: UInt16
        var advanceWidth: UInt16
        var width: Double
    }

    var fontData: [UInt8]
    var metadata: TrueTypeFontParser.Metadata
    var missingGlyphPolicy: MissingGlyphPolicy

    init(
        data: Data,
        metadata: TrueTypeFontParser.Metadata,
        missingGlyphPolicy: MissingGlyphPolicy = .reject,
    ) {
        fontData = [UInt8](data)
        self.metadata = metadata
        self.missingGlyphPolicy = missingGlyphPolicy
    }

    func map(text: String, fontSize: Double) throws -> TextMapping {
        guard fontSize.isFinite, fontSize > 0 else {
            throw TrueTypeGlyphMappingError.invalidFontSize(fontSize)
        }
        let lookup = try glyphLookup()
        let glyphs = try text.unicodeScalars.map { scalar in
            let resolved = try resolve(scalar: scalar, lookup: lookup)
            return try glyph(for: resolved.scalar, glyphID: resolved.glyphID, fontSize: fontSize)
        }
        return TextMapping(sourceText: text, glyphs: glyphs)
    }

    private func glyphLookup() throws -> GlyphLookup {
        guard let cmapRecord = metadata.table(named: "cmap") else {
            throw TrueTypeGlyphMappingError.missingTable("cmap")
        }

        let tableOffset = Int(cmapRecord.offset)
        let record = metadata.cmap.selectedUnicodeRecord
        let subtableOffset = tableOffset + Int(record.offset)
        let reader = TrueTypeByteReader(table: "cmap", bytes: fontData)
        switch record.format {
        case 4:
            return try .format4(Format4CMap(reader: reader, offset: subtableOffset))
        case 12:
            return try .format12(Format12CMap(reader: reader, offset: subtableOffset))
        default:
            throw TrueTypeGlyphMappingError.malformedCMap(
                format: record.format,
                reason: "selected cmap format is not supported",
            )
        }
    }

    /// Resolves a scalar to a glyph, returning the glyph id and the scalar that glyph actually
    /// represents (the base scalar when a sub/superscript was folded, so the ToUnicode mapping
    /// stays consistent for the shared glyph).
    private func resolve(scalar: UnicodeScalar, lookup: GlyphLookup) throws -> (glyphID: UInt16, scalar: UnicodeScalar) {
        if let glyphID = try lookup.glyphID(for: scalar) {
            return (glyphID, scalar)
        }

        // Many fonts (notably TeX math fonts such as Latin Modern Math) do not ship
        // precomposed Unicode sub/superscript glyphs, because subscripts are produced
        // by lowering a normal digit. Fold those codepoints to their base scalar and
        // render the base glyph if the font has it, rather than aborting the document. See #221.
        if let base = Self.subSuperscriptBase[scalar], let glyphID = try lookup.glyphID(for: base) {
            return (glyphID, base)
        }

        switch missingGlyphPolicy {
        case .reject:
            throw TrueTypeGlyphMappingError.missingGlyph(scalar)
        case .useNotdef:
            return (0, scalar)
        }
    }

    /// Precomposed Unicode subscript/superscript codepoints mapped to their base ASCII/Latin/Greek
    /// scalar. Used only as a fallback when the font lacks the precomposed glyph (see #221).
    static let subSuperscriptBase: [UnicodeScalar: UnicodeScalar] = {
        var map: [UnicodeScalar: UnicodeScalar] = [:]
        func add(_ from: UInt32, _ to: UnicodeScalar) {
            guard let scalar = UnicodeScalar(from) else { return }
            map[scalar] = to
        }
        // Subscript digits U+2080..U+2089 -> 0..9
        for d in 0 ... 9 {
            add(0x2080 + UInt32(d), UnicodeScalar(UInt8(0x30 + d)))
        }
        // Superscript digits: U+2070, U+00B9, U+00B2, U+00B3, U+2074..U+2079 -> 0..9
        add(0x2070, "0")
        add(0x00B9, "1")
        add(0x00B2, "2")
        add(0x00B3, "3")
        for d in 4 ... 9 {
            add(0x2070 + UInt32(d), UnicodeScalar(UInt8(0x30 + d)))
        }
        // Subscript operators U+208A..U+208E and superscript operators U+207A..U+207E
        let subOps: [(UInt32, UnicodeScalar)] = [(0x208A, "+"), (0x208B, "-"), (0x208C, "="), (0x208D, "("), (0x208E, ")")]
        let supOps: [(UInt32, UnicodeScalar)] = [(0x207A, "+"), (0x207B, "-"), (0x207C, "="), (0x207D, "("), (0x207E, ")")]
        for (cp, ch) in subOps + supOps {
            add(cp, ch)
        }
        // Latin subscript letters U+2090..U+209C
        let subLetters: [(UInt32, UnicodeScalar)] = [
            (0x2090, "a"), (0x2091, "e"), (0x2092, "o"), (0x2093, "x"), (0x2095, "h"), (0x2096, "k"),
            (0x2097, "l"), (0x2098, "m"), (0x2099, "n"), (0x209A, "p"), (0x209B, "s"), (0x209C, "t"),
        ]
        // Latin subscript letters from the Phonetic Extensions block U+1D62..U+1D6A
        let phoneticSub: [(UInt32, UnicodeScalar)] = [(0x1D62, "i"), (0x1D63, "r"), (0x1D64, "u"), (0x1D65, "v")]
        // Superscript Latin letters (common subset)
        let supLetters: [(UInt32, UnicodeScalar)] = [(0x2071, "i"), (0x207F, "n")]
        for (cp, ch) in subLetters + phoneticSub + supLetters {
            add(cp, ch)
        }
        return map
    }()

    private func glyph(for scalar: UnicodeScalar, glyphID: UInt16, fontSize: Double) throws -> Glyph {
        guard glyphID < metadata.maxp.numGlyphs else {
            throw TrueTypeGlyphMappingError.invalidGlyphID(UInt32(glyphID), numGlyphs: metadata.maxp.numGlyphs)
        }
        let advanceWidth = metadata.hmtx.advanceWidths[Int(glyphID)]
        let width = Double(advanceWidth) / Double(metadata.head.unitsPerEm) * fontSize
        return Glyph(
            scalar: scalar,
            glyphID: glyphID,
            cid: glyphID,
            pdfCharacterCode: glyphID,
            advanceWidth: advanceWidth,
            width: width,
        )
    }
}

private enum GlyphLookup {
    case format4(Format4CMap)
    case format12(Format12CMap)

    func glyphID(for scalar: UnicodeScalar) throws -> UInt16? {
        switch self {
        case let .format4(cmap):
            try cmap.glyphID(for: scalar)
        case let .format12(cmap):
            try cmap.glyphID(for: scalar)
        }
    }
}

private struct Format4CMap {
    struct Segment {
        var startCode: UInt16
        var endCode: UInt16
        var idDelta: Int16
        var idRangeOffset: UInt16
        var idRangeOffsetLocation: Int
    }

    var reader: TrueTypeByteReader
    var offset: Int
    var length: Int
    var segments: [Segment]

    init(reader: TrueTypeByteReader, offset: Int) throws {
        self.reader = reader
        self.offset = offset
        try reader.requireRange(offset: offset, count: 14)
        length = try Int(reader.uint16(at: offset + 2))
        let segCountX2 = try reader.uint16(at: offset + 6)
        guard segCountX2 > 0, segCountX2.isMultiple(of: 2) else {
            throw TrueTypeGlyphMappingError.malformedCMap(format: 4, reason: "segment count is invalid")
        }
        let segmentCount = Int(segCountX2 / 2)
        let minimumLength = 16 + segmentCount * 8
        guard length >= minimumLength else {
            throw TrueTypeGlyphMappingError.malformedCMap(format: 4, reason: "length cannot hold all segment arrays")
        }
        try reader.requireRange(offset: offset, count: length)

        let endCodeOffset = offset + 14
        let startCodeOffset = endCodeOffset + segmentCount * 2 + 2
        let idDeltaOffset = startCodeOffset + segmentCount * 2
        let idRangeOffsetOffset = idDeltaOffset + segmentCount * 2
        let reservedPad = try reader.uint16(at: endCodeOffset + segmentCount * 2)
        guard reservedPad == 0 else {
            throw TrueTypeGlyphMappingError.malformedCMap(format: 4, reason: "reserved pad must be zero")
        }

        var parsedSegments: [Segment] = []
        parsedSegments.reserveCapacity(segmentCount)
        var previousEndCode: UInt16?
        for index in 0 ..< segmentCount {
            let startCode = try reader.uint16(at: startCodeOffset + index * 2)
            let endCode = try reader.uint16(at: endCodeOffset + index * 2)
            guard startCode <= endCode else {
                throw TrueTypeGlyphMappingError.malformedCMap(format: 4, reason: "segment character range is unordered")
            }
            if let previousEndCode {
                guard previousEndCode < startCode else {
                    throw TrueTypeGlyphMappingError.malformedCMap(
                        format: 4,
                        reason: "segment ranges must be sorted and non-overlapping",
                    )
                }
            }
            try parsedSegments.append(
                Segment(
                    startCode: startCode,
                    endCode: endCode,
                    idDelta: reader.int16(at: idDeltaOffset + index * 2),
                    idRangeOffset: reader.uint16(at: idRangeOffsetOffset + index * 2),
                    idRangeOffsetLocation: idRangeOffsetOffset + index * 2,
                ),
            )
            previousEndCode = endCode
        }
        guard parsedSegments.last?.endCode == 0xFFFF else {
            throw TrueTypeGlyphMappingError.malformedCMap(format: 4, reason: "final sentinel segment is missing")
        }
        segments = parsedSegments
    }

    func glyphID(for scalar: UnicodeScalar) throws -> UInt16? {
        guard scalar.value <= 0xFFFF else {
            return nil
        }

        let code = UInt16(scalar.value)
        guard let segment = segments.first(where: { $0.startCode <= code && code <= $0.endCode }) else {
            return nil
        }
        guard code != 0xFFFF else {
            return nil
        }

        if segment.idRangeOffset == 0 {
            return UInt16(truncatingIfNeeded: Int(code) + Int(segment.idDelta))
        }

        let glyphOffset = segment.idRangeOffsetLocation
            + Int(segment.idRangeOffset)
            + (Int(code) - Int(segment.startCode)) * 2
        guard glyphOffset + 2 <= offset + length else {
            throw TrueTypeGlyphMappingError.malformedCMap(format: 4, reason: "glyph id array offset is outside subtable")
        }
        let rawGlyphID = try reader.uint16(at: glyphOffset)
        guard rawGlyphID != 0 else {
            return nil
        }
        return UInt16(truncatingIfNeeded: Int(rawGlyphID) + Int(segment.idDelta))
    }
}

private struct Format12CMap {
    struct Group {
        var startCharCode: UInt32
        var endCharCode: UInt32
        var startGlyphID: UInt32
    }

    var groups: [Group]

    init(reader: TrueTypeByteReader, offset: Int) throws {
        try reader.requireRange(offset: offset, count: 16)
        let length = try Int(reader.uint32(at: offset + 4))
        guard length >= 16, (length - 16).isMultiple(of: 12) else {
            throw TrueTypeGlyphMappingError.malformedCMap(format: 12, reason: "length is invalid")
        }
        let groupCount = try Int(reader.uint32(at: offset + 12))
        guard groupCount == (length - 16) / 12 else {
            throw TrueTypeGlyphMappingError.malformedCMap(format: 12, reason: "group count does not match length")
        }
        try reader.requireRange(offset: offset, count: length)

        var parsedGroups: [Group] = []
        parsedGroups.reserveCapacity(groupCount)
        for index in 0 ..< groupCount {
            let groupOffset = offset + 16 + index * 12
            let startCharCode = try reader.uint32(at: groupOffset)
            let endCharCode = try reader.uint32(at: groupOffset + 4)
            guard startCharCode <= endCharCode else {
                throw TrueTypeGlyphMappingError.malformedCMap(format: 12, reason: "group character range is unordered")
            }
            try parsedGroups.append(
                Group(
                    startCharCode: startCharCode,
                    endCharCode: endCharCode,
                    startGlyphID: reader.uint32(at: groupOffset + 8),
                ),
            )
        }
        groups = parsedGroups
    }

    func glyphID(for scalar: UnicodeScalar) throws -> UInt16? {
        let code = scalar.value
        guard let group = groups.first(where: { $0.startCharCode <= code && code <= $0.endCharCode }) else {
            return nil
        }
        let delta = code - group.startCharCode
        let glyphIDSum = group.startGlyphID.addingReportingOverflow(delta)
        guard !glyphIDSum.overflow else {
            throw TrueTypeGlyphMappingError.malformedCMap(format: 12, reason: "glyph id arithmetic overflows")
        }
        let glyphID = glyphIDSum.partialValue
        guard glyphID <= UInt32(UInt16.max) else {
            throw TrueTypeGlyphMappingError.invalidGlyphID(glyphID, numGlyphs: UInt16.max)
        }
        return UInt16(glyphID)
    }
}
