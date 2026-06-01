import Foundation

struct TrueTypeFontParser {
    enum EmbeddingPolicy: Equatable {
        case allowNoSubsetting
        case requireSubsetting
    }

    struct Metadata: Equatable {
        var scalerType: UInt32
        var tables: [TableRecord]
        var head: Head
        var hhea: HorizontalHeader
        var maxp: MaximumProfile
        var hmtx: HorizontalMetrics
        var cmap: CharacterMap
        var names: NameTable
        var os2: OS2Metrics
        var post: PostScriptTable

        func table(named tag: String) -> TableRecord? {
            tables.first { $0.tag == tag }
        }
    }

    struct TableRecord: Equatable {
        var tag: String
        var checksum: UInt32
        var offset: UInt32
        var length: UInt32
    }

    struct Head: Equatable {
        var unitsPerEm: UInt16
        var boundingBox: FontBoundingBox
        var indexToLocFormat: Int16
    }

    struct FontBoundingBox: Equatable {
        var xMin: Int16
        var yMin: Int16
        var xMax: Int16
        var yMax: Int16
    }

    struct HorizontalHeader: Equatable {
        var ascender: Int16
        var descender: Int16
        var lineGap: Int16
        var advanceWidthMax: UInt16
        var numberOfHMetrics: UInt16
    }

    struct MaximumProfile: Equatable {
        var numGlyphs: UInt16
    }

    struct HorizontalMetrics: Equatable {
        var advanceWidths: [UInt16]
    }

    struct CharacterMap: Equatable {
        var version: UInt16
        var encodingRecords: [EncodingRecord]
        var selectedUnicodeRecord: EncodingRecord

        var selectedUnicodeFormat: UInt16 {
            selectedUnicodeRecord.format
        }
    }

    struct EncodingRecord: Equatable {
        var platformID: UInt16
        var encodingID: UInt16
        var offset: UInt32
        var format: UInt16
    }

    struct NameTable: Equatable {
        var namesByID: [UInt16: String]
    }

    private struct NameCandidate {
        var value: String
        var priority: Int
    }

    struct OS2Metrics: Equatable {
        var version: UInt16
        var weightClass: UInt16
        var widthClass: UInt16
        var permissions: EmbeddingPermissions
    }

    struct EmbeddingPermissions: Equatable {
        var fsType: UInt16

        var restrictedLicenseEmbedding: Bool {
            fsType & 0x0002 != 0
        }

        var previewAndPrintEmbedding: Bool {
            fsType & 0x0004 != 0
        }

        var editableEmbedding: Bool {
            fsType & 0x0008 != 0
        }

        var noSubsetting: Bool {
            fsType & 0x0100 != 0
        }

        var bitmapOnlyEmbedding: Bool {
            fsType & 0x0200 != 0
        }
    }

    struct PostScriptTable: Equatable {
        var format: Double
        var italicAngle: Double
    }

    func parse(
        _ data: Data,
        embeddingPolicy: EmbeddingPolicy = .requireSubsetting,
    ) throws -> Metadata {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else {
            throw TrueTypeFontError.emptyFont
        }

        let reader = TrueTypeByteReader(table: "sfnt", bytes: bytes)
        let scalerType = try reader.uint32(at: 0)
        guard Self.supportedScalerTypes.contains(scalerType) else {
            throw TrueTypeFontError.unsupportedScalerType(scalerType)
        }

        let numTables = try Int(reader.uint16(at: 4))
        let directoryLength = 12 + numTables * 16
        try reader.requireRange(offset: 0, count: directoryLength)

        let records = try tableRecords(reader: reader, count: numTables)
        let recordsByTag = Dictionary(uniqueKeysWithValues: records.map { ($0.tag, $0) })
        try Self.requiredTables.forEach { tag in
            if recordsByTag[tag] == nil {
                throw TrueTypeFontError.missingRequiredTable(tag)
            }
        }

        try validateTableChecksums(records: records, in: bytes)

        let head = try parseHead(table(named: "head", recordsByTag: recordsByTag, bytes: bytes))
        let hhea = try parseHorizontalHeader(table(named: "hhea", recordsByTag: recordsByTag, bytes: bytes))
        let maxp = try parseMaximumProfile(table(named: "maxp", recordsByTag: recordsByTag, bytes: bytes))
        let hmtx = try parseHorizontalMetrics(
            table(named: "hmtx", recordsByTag: recordsByTag, bytes: bytes),
            numberOfHMetrics: hhea.numberOfHMetrics,
            numGlyphs: maxp.numGlyphs,
        )
        let cmap = try parseCharacterMap(table(named: "cmap", recordsByTag: recordsByTag, bytes: bytes))
        let names = try parseNameTable(table(named: "name", recordsByTag: recordsByTag, bytes: bytes))
        let os2 = try parseOS2Metrics(
            table(named: "OS/2", recordsByTag: recordsByTag, bytes: bytes),
            embeddingPolicy: embeddingPolicy,
        )
        let post = try parsePostScriptTable(table(named: "post", recordsByTag: recordsByTag, bytes: bytes))

        return Metadata(
            scalerType: scalerType,
            tables: records,
            head: head,
            hhea: hhea,
            maxp: maxp,
            hmtx: hmtx,
            cmap: cmap,
            names: names,
            os2: os2,
            post: post,
        )
    }

    private func tableRecords(reader: TrueTypeByteReader, count: Int) throws -> [TableRecord] {
        var records: [TableRecord] = []
        var seenTags: Set<String> = []

        for index in 0 ..< count {
            let offset = 12 + index * 16
            let tag = try reader.tag(at: offset)
            guard seenTags.insert(tag).inserted else {
                throw TrueTypeFontError.duplicateTable(tag)
            }

            let checksum = try reader.uint32(at: offset + 4)
            let tableOffset = try reader.uint32(at: offset + 8)
            let length = try reader.uint32(at: offset + 12)
            let tableOffsetInt = Int(tableOffset)
            let lengthInt = Int(length)
            guard tableOffsetInt <= reader.count, lengthInt <= reader.count - tableOffsetInt else {
                throw TrueTypeFontError.invalidTableBounds(
                    tag: tag,
                    offset: tableOffset,
                    length: length,
                    fileLength: reader.count,
                )
            }

            records.append(TableRecord(tag: tag, checksum: checksum, offset: tableOffset, length: length))
        }

        return records
    }

    private func validateTableChecksums(records: [TableRecord], in bytes: [UInt8]) throws {
        for record in records {
            let actual = Self.checksum(tableBytes(record, in: bytes), tag: record.tag)
            if actual != record.checksum {
                throw TrueTypeFontError.invalidTableChecksum(
                    tag: record.tag,
                    expected: record.checksum,
                    actual: actual,
                )
            }
        }
    }

    private func parseHead(_ bytes: [UInt8]) throws -> Head {
        let reader = TrueTypeByteReader(table: "head", bytes: bytes)
        try reader.requireRange(offset: 0, count: 54)
        let magicNumber = try reader.uint32(at: 12)
        guard magicNumber == 0x5F0F_3CF5 else {
            throw TrueTypeFontError.malformedTable(tag: "head", reason: "magic number is invalid")
        }
        let unitsPerEm = try reader.uint16(at: 18)
        guard 16 ... 16384 ~= unitsPerEm else {
            throw TrueTypeFontError.malformedTable(tag: "head", reason: "unitsPerEm must be between 16 and 16384")
        }

        let boundingBox = try FontBoundingBox(
            xMin: reader.int16(at: 36),
            yMin: reader.int16(at: 38),
            xMax: reader.int16(at: 40),
            yMax: reader.int16(at: 42),
        )
        guard boundingBox.xMin <= boundingBox.xMax, boundingBox.yMin <= boundingBox.yMax else {
            throw TrueTypeFontError.malformedTable(tag: "head", reason: "bounding box minimums exceed maximums")
        }

        let indexToLocFormat = try reader.int16(at: 50)
        guard indexToLocFormat == 0 || indexToLocFormat == 1 else {
            throw TrueTypeFontError.malformedTable(tag: "head", reason: "indexToLocFormat must be 0 or 1")
        }

        return Head(
            unitsPerEm: unitsPerEm,
            boundingBox: boundingBox,
            indexToLocFormat: indexToLocFormat,
        )
    }

    private func parseHorizontalHeader(_ bytes: [UInt8]) throws -> HorizontalHeader {
        let reader = TrueTypeByteReader(table: "hhea", bytes: bytes)
        try reader.requireRange(offset: 0, count: 36)
        let version = try reader.uint32(at: 0)
        guard version == 0x0001_0000 else {
            throw TrueTypeFontError.malformedTable(tag: "hhea", reason: "version must be 1.0")
        }
        let numberOfHMetrics = try reader.uint16(at: 34)
        guard numberOfHMetrics > 0 else {
            throw TrueTypeFontError.malformedTable(tag: "hhea", reason: "numberOfHMetrics must be positive")
        }

        return try HorizontalHeader(
            ascender: reader.int16(at: 4),
            descender: reader.int16(at: 6),
            lineGap: reader.int16(at: 8),
            advanceWidthMax: reader.uint16(at: 10),
            numberOfHMetrics: numberOfHMetrics,
        )
    }

    private func parseMaximumProfile(_ bytes: [UInt8]) throws -> MaximumProfile {
        let reader = TrueTypeByteReader(table: "maxp", bytes: bytes)
        try reader.requireRange(offset: 0, count: 6)
        let version = try reader.uint32(at: 0)
        guard version == 0x0001_0000 else {
            throw TrueTypeFontError.malformedTable(tag: "maxp", reason: "version must be 1.0")
        }
        let numGlyphs = try reader.uint16(at: 4)
        guard numGlyphs > 0 else {
            throw TrueTypeFontError.malformedTable(tag: "maxp", reason: "numGlyphs must be positive")
        }
        return MaximumProfile(numGlyphs: numGlyphs)
    }

    private func parseHorizontalMetrics(
        _ bytes: [UInt8],
        numberOfHMetrics: UInt16,
        numGlyphs: UInt16,
    ) throws -> HorizontalMetrics {
        guard numberOfHMetrics <= numGlyphs else {
            throw TrueTypeFontError.malformedTable(
                tag: "hmtx",
                reason: "numberOfHMetrics exceeds numGlyphs",
            )
        }

        let reader = TrueTypeByteReader(table: "hmtx", bytes: bytes)
        let metricCount = Int(numberOfHMetrics)
        let glyphCount = Int(numGlyphs)
        let expectedLength = metricCount * 4 + (glyphCount - metricCount) * 2
        try reader.requireRange(offset: 0, count: expectedLength)

        var widths: [UInt16] = []
        for index in 0 ..< metricCount {
            try widths.append(reader.uint16(at: index * 4))
        }
        if let lastWidth = widths.last, glyphCount > metricCount {
            widths.append(contentsOf: Array(repeating: lastWidth, count: glyphCount - metricCount))
        }
        return HorizontalMetrics(advanceWidths: widths)
    }

    private func parseCharacterMap(_ bytes: [UInt8]) throws -> CharacterMap {
        let reader = TrueTypeByteReader(table: "cmap", bytes: bytes)
        try reader.requireRange(offset: 0, count: 4)
        let version = try reader.uint16(at: 0)
        guard version == 0 else {
            throw TrueTypeFontError.malformedTable(tag: "cmap", reason: "version must be 0")
        }

        let recordCount = try Int(reader.uint16(at: 2))
        guard recordCount > 0 else {
            throw TrueTypeFontError.malformedTable(tag: "cmap", reason: "encoding record count must be positive")
        }
        try reader.requireRange(offset: 4, count: recordCount * 8)

        var records: [EncodingRecord] = []
        var selectedRecord: EncodingRecord?
        for index in 0 ..< recordCount {
            let recordOffset = 4 + index * 8
            let platformID = try reader.uint16(at: recordOffset)
            let encodingID = try reader.uint16(at: recordOffset + 2)
            let subtableOffset = try reader.uint32(at: recordOffset + 4)
            let subtableOffsetInt = Int(subtableOffset)
            guard subtableOffsetInt <= reader.count - 2 else {
                throw TrueTypeFontError.invalidTableBounds(
                    tag: "cmap",
                    offset: subtableOffset,
                    length: 2,
                    fileLength: reader.count,
                )
            }

            let format = try reader.uint16(at: subtableOffsetInt)
            let length = try cmapSubtableLength(format: format, offset: subtableOffsetInt, reader: reader)
            let lengthInt = Int(length)
            guard subtableOffsetInt <= reader.count, lengthInt <= reader.count - subtableOffsetInt else {
                throw TrueTypeFontError.invalidTableBounds(
                    tag: "cmap",
                    offset: subtableOffset,
                    length: length,
                    fileLength: reader.count,
                )
            }

            let record = EncodingRecord(
                platformID: platformID,
                encodingID: encodingID,
                offset: subtableOffset,
                format: format,
            )
            records.append(record)
            if selectedRecord == nil, Self.isUnicodeEncoding(platformID: platformID, encodingID: encodingID),
               Self.supportedCMapFormats.contains(format)
            {
                selectedRecord = record
            }
        }

        guard let selectedRecord else {
            throw TrueTypeFontError.unsupportedCMap(
                reason: "no Unicode subtable uses format 4 or 12",
            )
        }
        return CharacterMap(version: version, encodingRecords: records, selectedUnicodeRecord: selectedRecord)
    }

    private func cmapSubtableLength(
        format: UInt16,
        offset: Int,
        reader: TrueTypeByteReader,
    ) throws -> UInt32 {
        switch format {
        case 4:
            try reader.requireRange(offset: offset, count: 14)
            let length = try UInt32(reader.uint16(at: offset + 2))
            guard length >= 24 else {
                throw TrueTypeFontError.malformedTable(tag: "cmap", reason: "format 4 length is too small")
            }
            let segCountX2 = try reader.uint16(at: offset + 6)
            guard segCountX2 > 0, segCountX2.isMultiple(of: 2) else {
                throw TrueTypeFontError.malformedTable(tag: "cmap", reason: "format 4 segment count is invalid")
            }
            let segmentCount = UInt32(segCountX2 / 2)
            let minimumLength = 16 + segmentCount * 8
            guard length >= minimumLength else {
                throw TrueTypeFontError.malformedTable(tag: "cmap", reason: "format 4 length cannot hold all segment arrays")
            }
            return length
        case 12:
            try reader.requireRange(offset: offset, count: 16)
            let length = try reader.uint32(at: offset + 4)
            guard length >= 16 else {
                throw TrueTypeFontError.malformedTable(tag: "cmap", reason: "format 12 length is invalid")
            }
            let groupDataLength = length - 16
            let groupCount = try reader.uint32(at: offset + 12)
            guard groupDataLength.isMultiple(of: 12), groupCount == groupDataLength / 12 else {
                throw TrueTypeFontError.malformedTable(tag: "cmap", reason: "format 12 group count does not match length")
            }
            return length
        default:
            try reader.requireRange(offset: offset, count: 4)
            return try UInt32(reader.uint16(at: offset + 2))
        }
    }

    private func parseNameTable(_ bytes: [UInt8]) throws -> NameTable {
        let reader = TrueTypeByteReader(table: "name", bytes: bytes)
        try reader.requireRange(offset: 0, count: 6)
        let format = try reader.uint16(at: 0)
        guard format == 0 || format == 1 else {
            throw TrueTypeFontError.malformedTable(tag: "name", reason: "format must be 0 or 1")
        }

        let count = try Int(reader.uint16(at: 2))
        let stringOffset = try Int(reader.uint16(at: 4))
        let recordEnd = 6 + count * 12
        try reader.requireRange(offset: 6, count: count * 12)
        let storageBoundary: Int
        if format == 1 {
            try reader.requireRange(offset: recordEnd, count: 2)
            let languageTagCount = try Int(reader.uint16(at: recordEnd))
            storageBoundary = recordEnd + 2 + languageTagCount * 4
            try reader.requireRange(offset: recordEnd + 2, count: languageTagCount * 4)
        } else {
            storageBoundary = recordEnd
        }
        guard stringOffset >= storageBoundary else {
            throw TrueTypeFontError.malformedTable(
                tag: "name",
                reason: "string storage overlaps name records or language-tag records",
            )
        }
        try reader.requireRange(offset: stringOffset, count: 0)
        var names: [UInt16: NameCandidate] = [:]

        for index in 0 ..< count {
            let recordOffset = 6 + index * 12
            let platformID = try reader.uint16(at: recordOffset)
            let encodingID = try reader.uint16(at: recordOffset + 2)
            let nameID = try reader.uint16(at: recordOffset + 6)
            let length = try Int(reader.uint16(at: recordOffset + 8))
            let offset = try Int(reader.uint16(at: recordOffset + 10))
            let start = stringOffset + offset
            try reader.requireRange(offset: start, count: length)
            let decodedName = try decodeNameString(
                platformID: platformID,
                encodingID: encodingID,
                bytes: Array(bytes[start ..< start + length]),
            )
            let candidate = NameCandidate(
                value: decodedName,
                priority: Self.namePriority(platformID: platformID, encodingID: encodingID),
            )
            if let existing = names[nameID] {
                if candidate.priority > existing.priority {
                    names[nameID] = candidate
                }
            } else {
                names[nameID] = candidate
            }
        }

        return NameTable(namesByID: names.mapValues(\.value))
    }

    private func decodeNameString(platformID: UInt16, encodingID: UInt16, bytes: [UInt8]) throws -> String {
        if platformID == 3 || (platformID == 0 && encodingID <= 4) {
            guard bytes.count.isMultiple(of: 2) else {
                throw TrueTypeFontError.malformedTable(tag: "name", reason: "UTF-16BE string has odd byte count")
            }
            let units = stride(from: 0, to: bytes.count, by: 2).map { index in
                UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
            }
            return String(decoding: units, as: UTF16.self)
        }

        return String(decoding: bytes, as: UTF8.self)
    }

    private func parseOS2Metrics(
        _ bytes: [UInt8],
        embeddingPolicy: EmbeddingPolicy,
    ) throws -> OS2Metrics {
        let reader = TrueTypeByteReader(table: "OS/2", bytes: bytes)
        try reader.requireRange(offset: 0, count: 78)
        let permissions = try EmbeddingPermissions(fsType: reader.uint16(at: 8))
        try validateEmbeddingPermissions(permissions, policy: embeddingPolicy)
        return try OS2Metrics(
            version: reader.uint16(at: 0),
            weightClass: reader.uint16(at: 4),
            widthClass: reader.uint16(at: 6),
            permissions: permissions,
        )
    }

    private func validateEmbeddingPermissions(
        _ permissions: EmbeddingPermissions,
        policy: EmbeddingPolicy,
    ) throws {
        if permissions.restrictedLicenseEmbedding {
            throw TrueTypeFontError.restrictedEmbedding(fsType: permissions.fsType)
        }
        if permissions.bitmapOnlyEmbedding {
            throw TrueTypeFontError.bitmapOnlyEmbedding(fsType: permissions.fsType)
        }
        if policy == .requireSubsetting, permissions.noSubsetting {
            throw TrueTypeFontError.subsettingRequired(fsType: permissions.fsType)
        }
    }

    private func parsePostScriptTable(_ bytes: [UInt8]) throws -> PostScriptTable {
        let reader = TrueTypeByteReader(table: "post", bytes: bytes)
        try reader.requireRange(offset: 0, count: 32)
        return try PostScriptTable(
            format: reader.fixed16Dot16(at: 0),
            italicAngle: reader.fixed16Dot16(at: 4),
        )
    }

    private func table(
        named tag: String,
        recordsByTag: [String: TableRecord],
        bytes: [UInt8],
    ) throws -> [UInt8] {
        guard let record = recordsByTag[tag] else {
            throw TrueTypeFontError.missingRequiredTable(tag)
        }
        return tableBytes(record, in: bytes)
    }

    private func tableBytes(_ record: TableRecord, in bytes: [UInt8]) -> [UInt8] {
        let offset = Int(record.offset)
        return Array(bytes[offset ..< offset + Int(record.length)])
    }

    private static func checksum(_ bytes: [UInt8], tag: String) -> UInt32 {
        var padded = bytes
        if tag == "head", padded.count >= 12 {
            padded[8] = 0
            padded[9] = 0
            padded[10] = 0
            padded[11] = 0
        }
        while !padded.count.isMultiple(of: 4) {
            padded.append(0)
        }

        var sum: UInt32 = 0
        for offset in stride(from: 0, to: padded.count, by: 4) {
            let word = UInt32(padded[offset]) << 24
                | UInt32(padded[offset + 1]) << 16
                | UInt32(padded[offset + 2]) << 8
                | UInt32(padded[offset + 3])
            sum = sum &+ word
        }
        return sum
    }

    private static func isUnicodeEncoding(platformID: UInt16, encodingID: UInt16) -> Bool {
        platformID == 0 || (platformID == 3 && (encodingID == 1 || encodingID == 10))
    }

    private static func namePriority(platformID: UInt16, encodingID: UInt16) -> Int {
        platformID == 3 || (platformID == 0 && encodingID <= 4) ? 2 : 1
    }

    private static let supportedScalerTypes: Set<UInt32> = [
        0x0001_0000,
        0x7472_7565,
    ]

    private static let supportedCMapFormats: Set<UInt16> = [4, 12]

    private static let requiredTables = [
        "head",
        "hhea",
        "hmtx",
        "maxp",
        "cmap",
        "name",
        "OS/2",
        "post",
    ]
}
