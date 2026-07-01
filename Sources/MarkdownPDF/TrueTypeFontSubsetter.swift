import Foundation

struct TrueTypeFontSubsetter {
    enum CIDToGIDMap: Equatable {
        case identity
        case stream(Data)
    }

    struct Subset: Equatable {
        var fontProgram: Data
        var metadata: TrueTypeFontParser.Metadata
        var originalGlyphIDs: [UInt16]
        var glyphIDMap: [UInt16: UInt16]
        var cidToGIDMap: CIDToGIDMap
        var glyphs: [TrueTypeGlyphMapper.Glyph]
    }

    private struct HorizontalMetric {
        var advanceWidth: UInt16
        var leftSideBearing: Int16
    }

    private struct GlyphTable {
        var glyf: Data
        var locations: [Int]
    }

    var fontData: Data
    var metadata: TrueTypeFontParser.Metadata

    init(data: Data, metadata: TrueTypeFontParser.Metadata) {
        fontData = data
        self.metadata = metadata
    }

    func compactCIDGlyphs(for glyphs: [TrueTypeGlyphMapper.Glyph]) throws -> [TrueTypeGlyphMapper.Glyph] {
        guard !glyphs.isEmpty else {
            throw TrueTypeFontSubsetError.emptyGlyphSet
        }

        try validateSubsetTables()
        try validateGlyphs(glyphs)
        let glyphTable = try glyphTable()
        let originalGlyphIDs = try closedGlyphIDs(
            startingWith: Set(glyphs.map(\.glyphID)),
            glyphTable: glyphTable,
        )
        let glyphIDMap = Dictionary(
            uniqueKeysWithValues: originalGlyphIDs.enumerated().map { index, glyphID in
                (glyphID, UInt16(index))
            },
        )

        return try glyphs.map { glyph in
            guard let compactCID = glyphIDMap[glyph.glyphID] else {
                throw TrueTypeFontSubsetError.invalidGlyphID(glyph.glyphID, numGlyphs: metadata.maxp.numGlyphs)
            }
            return TrueTypeGlyphMapper.Glyph(
                scalar: glyph.scalar,
                glyphID: glyph.glyphID,
                cid: compactCID,
                pdfCharacterCode: compactCID,
                advanceWidth: glyph.advanceWidth,
                width: glyph.width,
            )
        }
    }

    func subset(glyphs: [TrueTypeGlyphMapper.Glyph]) throws -> Subset {
        guard !glyphs.isEmpty else {
            throw TrueTypeFontSubsetError.emptyGlyphSet
        }

        try validateSubsetTables()
        try validateGlyphs(glyphs)
        let glyphTable = try glyphTable()
        let originalGlyphIDs = try closedGlyphIDs(
            startingWith: Set(glyphs.map(\.glyphID)),
            glyphTable: glyphTable,
        )
        let glyphIDMap = Dictionary(
            uniqueKeysWithValues: originalGlyphIDs.enumerated().map { index, glyphID in
                (glyphID, UInt16(index))
            },
        )
        let tables = try subsetTables(
            originalGlyphIDs: originalGlyphIDs,
            glyphIDMap: glyphIDMap,
            glyphTable: glyphTable,
            scalarMappings: scalarMappings(for: glyphs, glyphIDMap: glyphIDMap),
        )
        let fontProgram = Self.fontProgram(scalerType: metadata.scalerType, tables: tables)
        let subsetMetadata = try TrueTypeFontParser().parse(fontProgram)

        return try Subset(
            fontProgram: fontProgram,
            metadata: subsetMetadata,
            originalGlyphIDs: originalGlyphIDs,
            glyphIDMap: glyphIDMap,
            cidToGIDMap: cidToGIDMap(for: glyphs, glyphIDMap: glyphIDMap),
            glyphs: glyphs,
        )
    }

    private func validateGlyphs(_ glyphs: [TrueTypeGlyphMapper.Glyph]) throws {
        for glyph in glyphs {
            try validateGlyphID(glyph.glyphID)
        }
    }

    private func validateSubsetTables() throws {
        for tag in ["glyf", "loca"] where metadata.table(named: tag) == nil {
            throw TrueTypeFontSubsetError.missingRequiredTable(tag)
        }
    }

    private func validateGlyphID(_ glyphID: UInt16) throws {
        guard glyphID < metadata.maxp.numGlyphs else {
            throw TrueTypeFontSubsetError.invalidGlyphID(glyphID, numGlyphs: metadata.maxp.numGlyphs)
        }
    }

    private func closedGlyphIDs(
        startingWith usedGlyphIDs: Set<UInt16>,
        glyphTable: GlyphTable,
    ) throws -> [UInt16] {
        var selectedGlyphIDs = usedGlyphIDs
        selectedGlyphIDs.insert(0)
        var queue = Array(selectedGlyphIDs).sorted()
        var cursor = 0

        while cursor < queue.count {
            let glyphID = queue[cursor]
            cursor += 1

            for componentGlyphID in try componentGlyphIDs(for: glyphID, glyphTable: glyphTable)
                where selectedGlyphIDs.insert(componentGlyphID).inserted
            {
                queue.append(componentGlyphID)
            }
        }

        return [0] + selectedGlyphIDs.filter { $0 != 0 }.sorted()
    }

    private func componentGlyphIDs(for glyphID: UInt16, glyphTable: GlyphTable) throws -> [UInt16] {
        let glyphData = try glyphBytes(for: glyphID, glyphTable: glyphTable)
        guard !glyphData.isEmpty else {
            return []
        }

        let reader = TrueTypeByteReader(table: "glyf", bytes: [UInt8](glyphData))
        try reader.requireRange(offset: 0, count: 10)
        guard try reader.int16(at: 0) < 0 else {
            return []
        }

        var componentGlyphIDs: [UInt16] = []
        try walkCompositeGlyph(glyphID: glyphID, reader: reader) { componentGlyphID, _ in
            try validateGlyphID(componentGlyphID)
            componentGlyphIDs.append(componentGlyphID)
        }
        return componentGlyphIDs
    }

    private func subsetTables(
        originalGlyphIDs: [UInt16],
        glyphIDMap: [UInt16: UInt16],
        glyphTable: GlyphTable,
        scalarMappings: [UnicodeScalar: UInt16],
    ) throws -> [String: Data] {
        var tables = try Dictionary(
            uniqueKeysWithValues: metadata.tables.map { record in
                try (record.tag, tableData(for: record.tag))
            },
        )
        let glyfAndLoca = try subsetGlyfAndLoca(
            originalGlyphIDs: originalGlyphIDs,
            glyphIDMap: glyphIDMap,
            glyphTable: glyphTable,
        )
        let metrics = try horizontalMetrics(for: originalGlyphIDs)

        tables["glyf"] = glyfAndLoca.glyf
        tables["loca"] = glyfAndLoca.loca
        tables["hmtx"] = hmtxTable(metrics: metrics)
        tables["hhea"] = try hheaTable(metrics: metrics)
        tables["maxp"] = try maxpTable(
            glyphCount: UInt16(originalGlyphIDs.count),
            containsCompositeGlyphs: glyfAndLoca.containsCompositeGlyphs,
        )
        tables["head"] = try headTable()
        tables["cmap"] = cmapTable(scalarMappings: scalarMappings)
        return tables
    }

    private func scalarMappings(
        for glyphs: [TrueTypeGlyphMapper.Glyph],
        glyphIDMap: [UInt16: UInt16],
    ) throws -> [UnicodeScalar: UInt16] {
        var mappings: [UnicodeScalar: UInt16] = [:]
        for glyph in glyphs {
            guard let subsetGlyphID = glyphIDMap[glyph.glyphID] else {
                throw TrueTypeFontSubsetError.invalidGlyphID(glyph.glyphID, numGlyphs: metadata.maxp.numGlyphs)
            }
            if let existing = mappings[glyph.scalar] {
                guard existing == subsetGlyphID else {
                    throw TrueTypeFontSubsetError.conflictingScalarMapping(
                        glyph.scalar,
                        existing: existing,
                        duplicate: subsetGlyphID,
                    )
                }
            } else {
                mappings[glyph.scalar] = subsetGlyphID
            }
        }
        return mappings
    }

    private func cidToGIDMap(
        for glyphs: [TrueTypeGlyphMapper.Glyph],
        glyphIDMap: [UInt16: UInt16],
    ) throws -> CIDToGIDMap {
        var gidsByCID: [UInt16: UInt16] = [:]
        for glyph in glyphs {
            guard let subsetGlyphID = glyphIDMap[glyph.glyphID] else {
                throw TrueTypeFontSubsetError.invalidGlyphID(glyph.glyphID, numGlyphs: metadata.maxp.numGlyphs)
            }
            if let existing = gidsByCID[glyph.cid] {
                guard existing == subsetGlyphID else {
                    throw TrueTypeFontSubsetError.conflictingCIDMapping(
                        cid: glyph.cid,
                        existing: existing,
                        duplicate: subsetGlyphID,
                    )
                }
            } else {
                gidsByCID[glyph.cid] = subsetGlyphID
            }
        }

        if gidsByCID.allSatisfy({ cid, glyphID in cid == glyphID }) {
            return .identity
        }

        let maxCID = gidsByCID.keys.max() ?? 0
        var data = Data()
        for cid in UInt16(0) ... maxCID {
            Self.appendUInt16(gidsByCID[cid] ?? 0, to: &data)
        }
        return .stream(data)
    }

    private func subsetGlyfAndLoca(
        originalGlyphIDs: [UInt16],
        glyphIDMap: [UInt16: UInt16],
        glyphTable: GlyphTable,
    ) throws -> (glyf: Data, loca: Data, containsCompositeGlyphs: Bool) {
        var glyf = Data()
        var loca = Data()
        var containsCompositeGlyphs = false
        Self.appendUInt32(0, to: &loca)

        for originalGlyphID in originalGlyphIDs {
            let originalGlyphData = try glyphBytes(for: originalGlyphID, glyphTable: glyphTable)
            containsCompositeGlyphs = containsCompositeGlyphs || isCompositeGlyph(originalGlyphData)
            let rewrittenGlyphData = try rewrittenGlyphData(
                originalGlyphID: originalGlyphID,
                glyphData: originalGlyphData,
                glyphIDMap: glyphIDMap,
            )
            glyf.append(rewrittenGlyphData)
            while !glyf.count.isMultiple(of: 2) {
                glyf.append(0)
            }
            Self.appendUInt32(UInt32(glyf.count), to: &loca)
        }

        return (glyf: glyf, loca: loca, containsCompositeGlyphs: containsCompositeGlyphs)
    }

    private func rewrittenGlyphData(
        originalGlyphID: UInt16,
        glyphData: Data,
        glyphIDMap: [UInt16: UInt16],
    ) throws -> Data {
        guard !glyphData.isEmpty else {
            return glyphData
        }

        var bytes = [UInt8](glyphData)
        let reader = TrueTypeByteReader(table: "glyf", bytes: bytes)
        try reader.requireRange(offset: 0, count: 10)
        guard try reader.int16(at: 0) < 0 else {
            return glyphData
        }

        try walkCompositeGlyph(glyphID: originalGlyphID, reader: reader) { componentGlyphID, componentOffset in
            guard let subsetGlyphID = glyphIDMap[componentGlyphID] else {
                throw TrueTypeFontSubsetError.malformedGlyph(
                    glyphID: originalGlyphID,
                    reason: "component glyph id \(componentGlyphID) was not included in the subset closure",
                )
            }
            Self.writeUInt16(subsetGlyphID, at: componentOffset, in: &bytes)
        }
        return Data(bytes)
    }

    private func walkCompositeGlyph(
        glyphID _: UInt16,
        reader: TrueTypeByteReader,
        visitComponent: (UInt16, Int) throws -> Void,
    ) throws {
        var offset = 10
        var hasMoreComponents = true

        while hasMoreComponents {
            try reader.requireRange(offset: offset, count: 4)
            let flags = try reader.uint16(at: offset)
            let componentGlyphIDOffset = offset + 2
            let componentGlyphID = try reader.uint16(at: componentGlyphIDOffset)
            try visitComponent(componentGlyphID, componentGlyphIDOffset)

            offset += 4
            offset += flags & Self.argsAreWords != 0 ? 4 : 2
            if flags & Self.weHaveAScale != 0 {
                offset += 2
            } else if flags & Self.weHaveAnXAndYScale != 0 {
                offset += 4
            } else if flags & Self.weHaveATwoByTwo != 0 {
                offset += 8
            }
            try reader.requireRange(offset: offset, count: 0)
            hasMoreComponents = flags & Self.moreComponents != 0

            if !hasMoreComponents, flags & Self.weHaveInstructions != 0 {
                try reader.requireRange(offset: offset, count: 2)
                let instructionLength = try Int(reader.uint16(at: offset))
                offset += 2
                try reader.requireRange(offset: offset, count: instructionLength)
                offset += instructionLength
            }
        }
    }

    private func isCompositeGlyph(_ data: Data) -> Bool {
        guard data.count >= 2 else {
            return false
        }
        let numberOfContours = Int16(bitPattern: UInt16(data[0]) << 8 | UInt16(data[1]))
        return numberOfContours < 0
    }

    private func glyphTable() throws -> GlyphTable {
        try GlyphTable(glyf: tableData(for: "glyf"), locations: glyphLocations())
    }

    private func glyphBytes(for glyphID: UInt16, glyphTable: GlyphTable) throws -> Data {
        let index = Int(glyphID)
        let start = glyphTable.locations[index]
        let end = glyphTable.locations[index + 1]
        guard start <= end, end <= glyphTable.glyf.count else {
            throw TrueTypeFontSubsetError.malformedGlyph(
                glyphID: glyphID,
                reason: "loca offsets are unordered or outside the glyf table",
            )
        }
        return Data(glyphTable.glyf[start ..< end])
    }

    private func glyphLocations() throws -> [Int] {
        let loca = try tableData(for: "loca")
        let reader = TrueTypeByteReader(table: "loca", bytes: [UInt8](loca))
        let expectedEntries = Int(metadata.maxp.numGlyphs) + 1

        switch metadata.head.indexToLocFormat {
        case 0:
            let actualEntries = loca.count / 2
            guard actualEntries >= expectedEntries else {
                throw TrueTypeFontSubsetError.invalidLocaTable(
                    expectedEntries: expectedEntries,
                    actualEntries: actualEntries,
                )
            }
            return try (0 ..< expectedEntries).map { index in
                try Int(reader.uint16(at: index * 2)) * 2
            }
        case 1:
            let actualEntries = loca.count / 4
            guard actualEntries >= expectedEntries else {
                throw TrueTypeFontSubsetError.invalidLocaTable(
                    expectedEntries: expectedEntries,
                    actualEntries: actualEntries,
                )
            }
            return try (0 ..< expectedEntries).map { index in
                try Int(reader.uint32(at: index * 4))
            }
        default:
            throw TrueTypeFontSubsetError.malformedGlyph(
                glyphID: 0,
                reason: "head.indexToLocFormat must be 0 or 1",
            )
        }
    }

    private func horizontalMetrics(for glyphIDs: [UInt16]) throws -> [HorizontalMetric] {
        let hmtx = try tableData(for: "hmtx")
        let reader = TrueTypeByteReader(table: "hmtx", bytes: [UInt8](hmtx))
        return try glyphIDs.map { glyphID in
            try horizontalMetric(for: glyphID, reader: reader)
        }
    }

    private func horizontalMetric(for glyphID: UInt16, reader: TrueTypeByteReader) throws -> HorizontalMetric {
        let numberOfHMetrics = Int(metadata.hhea.numberOfHMetrics)
        let glyphIndex = Int(glyphID)

        if glyphIndex < numberOfHMetrics {
            let offset = glyphIndex * 4
            return try HorizontalMetric(
                advanceWidth: reader.uint16(at: offset),
                leftSideBearing: reader.int16(at: offset + 2),
            )
        }

        let lastMetricOffset = (numberOfHMetrics - 1) * 4
        let leftSideBearingOffset = numberOfHMetrics * 4 + (glyphIndex - numberOfHMetrics) * 2
        return try HorizontalMetric(
            advanceWidth: reader.uint16(at: lastMetricOffset),
            leftSideBearing: reader.int16(at: leftSideBearingOffset),
        )
    }

    private func hmtxTable(metrics: [HorizontalMetric]) -> Data {
        var data = Data()
        for metric in metrics {
            Self.appendUInt16(metric.advanceWidth, to: &data)
            Self.appendInt16(metric.leftSideBearing, to: &data)
        }
        return data
    }

    private func hheaTable(metrics: [HorizontalMetric]) throws -> Data {
        var data = try tableData(for: "hhea")
        try TrueTypeByteReader(table: "hhea", bytes: [UInt8](data)).requireRange(offset: 0, count: 36)
        let advanceWidthMax = metrics.map(\.advanceWidth).max() ?? 0
        Self.writeUInt16(advanceWidthMax, at: 10, in: &data)
        Self.writeUInt16(UInt16(metrics.count), at: 34, in: &data)
        return data
    }

    private func maxpTable(glyphCount: UInt16, containsCompositeGlyphs: Bool) throws -> Data {
        var data = try tableData(for: "maxp")
        try TrueTypeByteReader(table: "maxp", bytes: [UInt8](data)).requireRange(offset: 0, count: 6)
        Self.writeUInt16(glyphCount, at: 4, in: &data)

        if containsCompositeGlyphs, data.count >= 32 {
            let reader = TrueTypeByteReader(table: "maxp", bytes: [UInt8](data))
            let maxComponentElements = try max(reader.uint16(at: 28), 2)
            let maxComponentDepth = try max(reader.uint16(at: 30), 1)
            Self.writeUInt16(maxComponentElements, at: 28, in: &data)
            Self.writeUInt16(maxComponentDepth, at: 30, in: &data)
        }
        return data
    }

    private func headTable() throws -> Data {
        var data = try tableData(for: "head")
        try TrueTypeByteReader(table: "head", bytes: [UInt8](data)).requireRange(offset: 0, count: 54)
        Self.writeUInt32(0, at: 8, in: &data)
        Self.writeInt16(1, at: 50, in: &data)
        return data
    }

    private func cmapTable(scalarMappings: [UnicodeScalar: UInt16]) -> Data {
        if canUseFormat4CMap(scalarMappings: scalarMappings) {
            return format4CMapTable(scalarMappings: scalarMappings)
        }
        return format12CMapTable(scalarMappings: scalarMappings)
    }

    private func canUseFormat4CMap(scalarMappings: [UnicodeScalar: UInt16]) -> Bool {
        guard scalarMappings.keys.allSatisfy({ $0.value < 0xFFFF }) else {
            return false
        }
        let segmentCount = scalarMappings.count + 1
        let subtableLength = 16 + segmentCount * 8
        return subtableLength <= Int(UInt16.max)
    }

    private func format4CMapTable(scalarMappings: [UnicodeScalar: UInt16]) -> Data {
        let entries = scalarMappings
            .map { scalar, glyphID in (code: UInt16(scalar.value), glyphID: glyphID) }
            .sorted { lhs, rhs in lhs.code < rhs.code }
        let segmentCount = entries.count + 1
        let search = Self.searchValues(itemCount: segmentCount, itemSize: 2)
        let subtableLength = 16 + segmentCount * 8

        var subtable = Data()
        Self.appendUInt16(4, to: &subtable)
        Self.appendUInt16(UInt16(subtableLength), to: &subtable)
        Self.appendUInt16(0, to: &subtable)
        Self.appendUInt16(UInt16(segmentCount * 2), to: &subtable)
        Self.appendUInt16(search.searchRange, to: &subtable)
        Self.appendUInt16(search.entrySelector, to: &subtable)
        Self.appendUInt16(search.rangeShift, to: &subtable)
        for entry in entries {
            Self.appendUInt16(entry.code, to: &subtable)
        }
        Self.appendUInt16(0xFFFF, to: &subtable)
        Self.appendUInt16(0, to: &subtable)
        for entry in entries {
            Self.appendUInt16(entry.code, to: &subtable)
        }
        Self.appendUInt16(0xFFFF, to: &subtable)
        for entry in entries {
            Self.appendUInt16(UInt16(truncatingIfNeeded: Int(entry.glyphID) - Int(entry.code)), to: &subtable)
        }
        Self.appendUInt16(1, to: &subtable)
        for _ in 0 ..< segmentCount {
            Self.appendUInt16(0, to: &subtable)
        }

        var table = Data()
        Self.appendUInt16(0, to: &table)
        Self.appendUInt16(1, to: &table)
        Self.appendUInt16(3, to: &table)
        Self.appendUInt16(1, to: &table)
        Self.appendUInt32(12, to: &table)
        table.append(subtable)
        return table
    }

    private func format12CMapTable(scalarMappings: [UnicodeScalar: UInt16]) -> Data {
        let entries = scalarMappings
            .map { scalar, glyphID in (code: scalar.value, glyphID: UInt32(glyphID)) }
            .sorted { lhs, rhs in lhs.code < rhs.code }

        var subtable = Data()
        Self.appendUInt16(12, to: &subtable)
        Self.appendUInt16(0, to: &subtable)
        Self.appendUInt32(UInt32(16 + entries.count * 12), to: &subtable)
        Self.appendUInt32(0, to: &subtable)
        Self.appendUInt32(UInt32(entries.count), to: &subtable)
        for entry in entries {
            Self.appendUInt32(entry.code, to: &subtable)
            Self.appendUInt32(entry.code, to: &subtable)
            Self.appendUInt32(entry.glyphID, to: &subtable)
        }

        var table = Data()
        Self.appendUInt16(0, to: &table)
        Self.appendUInt16(1, to: &table)
        Self.appendUInt16(3, to: &table)
        Self.appendUInt16(10, to: &table)
        Self.appendUInt32(12, to: &table)
        table.append(subtable)
        return table
    }

    private func tableData(for tag: String) throws -> Data {
        guard let record = metadata.table(named: tag) else {
            throw TrueTypeFontSubsetError.missingRequiredTable(tag)
        }
        let bytes = [UInt8](fontData)
        let start = Int(record.offset)
        let end = start + Int(record.length)
        return Data(bytes[start ..< end])
    }

    private static func fontProgram(scalerType: UInt32, tables: [String: Data]) -> Data {
        let sortedTags = tables.keys.sorted()
        var records: [(tag: String, checksum: UInt32, offset: UInt32, length: UInt32)] = []
        var font = Data(count: 12 + sortedTags.count * 16)

        for tag in sortedTags {
            guard let table = tables[tag] else {
                continue
            }
            while !font.count.isMultiple(of: 4) {
                font.append(0)
            }
            records.append((
                tag: tag,
                checksum: checksum(table, tag: tag),
                offset: UInt32(font.count),
                length: UInt32(table.count),
            ))
            font.append(table)
        }

        writeUInt32(scalerType, at: 0, in: &font)
        writeUInt16(UInt16(sortedTags.count), at: 4, in: &font)
        let search = searchValues(itemCount: sortedTags.count, itemSize: 16)
        writeUInt16(search.searchRange, at: 6, in: &font)
        writeUInt16(search.entrySelector, at: 8, in: &font)
        writeUInt16(search.rangeShift, at: 10, in: &font)

        for (index, record) in records.enumerated() {
            let offset = 12 + index * 16
            writeTag(record.tag, at: offset, in: &font)
            writeUInt32(record.checksum, at: offset + 4, in: &font)
            writeUInt32(record.offset, at: offset + 8, in: &font)
            writeUInt32(record.length, at: offset + 12, in: &font)
        }

        if let headRecord = records.first(where: { $0.tag == "head" }) {
            let adjustment = 0xB1B0_AFBA &- checksum(font, tag: "sfnt")
            writeUInt32(adjustment, at: Int(headRecord.offset) + 8, in: &font)
        }
        return font
    }

    private static func searchValues(
        itemCount: Int,
        itemSize: Int,
    ) -> (searchRange: UInt16, entrySelector: UInt16, rangeShift: UInt16) {
        var maximumPower = 1
        var selector = 0
        while maximumPower * 2 <= itemCount {
            maximumPower *= 2
            selector += 1
        }
        let searchRange = maximumPower * itemSize
        return (
            searchRange: UInt16(searchRange),
            entrySelector: UInt16(selector),
            rangeShift: UInt16(itemCount * itemSize - searchRange),
        )
    }

    private static func checksum(_ data: Data, tag: String) -> UInt32 {
        var bytes = [UInt8](data)
        if tag == "head", bytes.count >= 12 {
            bytes[8] = 0
            bytes[9] = 0
            bytes[10] = 0
            bytes[11] = 0
        }
        while !bytes.count.isMultiple(of: 4) {
            bytes.append(0)
        }

        var sum: UInt32 = 0
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let word = UInt32(bytes[offset]) << 24
                | UInt32(bytes[offset + 1]) << 16
                | UInt32(bytes[offset + 2]) << 8
                | UInt32(bytes[offset + 3])
            sum = sum &+ word
        }
        return sum
    }

    private static func writeTag(_ tag: String, at offset: Int, in data: inout Data) {
        let bytes = Array(tag.utf8)
        precondition(bytes.count == 4, "TrueType table tags must have four bytes")
        for index in 0 ..< 4 {
            data[offset + index] = bytes[index]
        }
    }

    private static func writeUInt16(_ value: UInt16, at offset: Int, in data: inout Data) {
        data[offset] = UInt8((value >> 8) & 0xFF)
        data[offset + 1] = UInt8(value & 0xFF)
    }

    private static func writeInt16(_ value: Int16, at offset: Int, in data: inout Data) {
        writeUInt16(UInt16(bitPattern: value), at: offset, in: &data)
    }

    private static func writeUInt16(_ value: UInt16, at offset: Int, in bytes: inout [UInt8]) {
        bytes[offset] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 1] = UInt8(value & 0xFF)
    }

    private static func writeUInt32(_ value: UInt32, at offset: Int, in data: inout Data) {
        data[offset] = UInt8((value >> 24) & 0xFF)
        data[offset + 1] = UInt8((value >> 16) & 0xFF)
        data[offset + 2] = UInt8((value >> 8) & 0xFF)
        data[offset + 3] = UInt8(value & 0xFF)
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private static func appendInt16(_ value: Int16, to data: inout Data) {
        appendUInt16(UInt16(bitPattern: value), to: &data)
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private static let argsAreWords: UInt16 = 0x0001
    private static let moreComponents: UInt16 = 0x0020
    private static let weHaveAScale: UInt16 = 0x0008
    private static let weHaveAnXAndYScale: UInt16 = 0x0040
    private static let weHaveATwoByTwo: UInt16 = 0x0080
    private static let weHaveInstructions: UInt16 = 0x0100
}
