import Foundation
@testable import MarkdownPDF
import Testing

@Suite("TrueType font parser")
struct TrueTypeFontParserTests {
    @Test("Parses synthetic TrueType metadata and embedding policy")
    func parsesSyntheticTrueTypeMetadataAndEmbeddingPolicy() throws {
        let metadata = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data())

        #expect(metadata.scalerType == 0x0001_0000)
        #expect(metadata.tables.map(\.tag).sorted() == ["OS/2", "cmap", "head", "hhea", "hmtx", "maxp", "name", "post"])
        #expect(metadata.head.unitsPerEm == 1000)
        #expect(metadata.head.boundingBox == TrueTypeFontParser.FontBoundingBox(xMin: -20, yMin: -200, xMax: 980, yMax: 900))
        #expect(metadata.hhea.ascender == 800)
        #expect(metadata.hhea.descender == -200)
        #expect(metadata.hhea.numberOfHMetrics == 2)
        #expect(metadata.maxp.numGlyphs == 3)
        #expect(metadata.hmtx.advanceWidths == [500, 600, 600])
        #expect(metadata.cmap.version == 0)
        #expect(metadata.cmap.selectedUnicodeFormat == 4)
        #expect(metadata.cmap.encodingRecords.first?.platformID == 3)
        #expect(metadata.names.namesByID[1] == "MarkdownPDF Synthetic")
        #expect(metadata.names.namesByID[4] == "MarkdownPDF Synthetic Regular")
        #expect(metadata.os2.weightClass == 400)
        #expect(metadata.os2.widthClass == 5)
        #expect(metadata.os2.permissions.fsType == 0)
        #expect(!metadata.os2.permissions.restrictedLicenseEmbedding)
        #expect(!metadata.os2.permissions.noSubsetting)
        #expect(metadata.post.format == 3)
        #expect(metadata.post.italicAngle == 0)
    }

    @Test("Rejects malformed table checksums")
    func rejectsMalformedTableChecksums() {
        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(corruptChecksumTag: "hhea"))
        } verify: { error in
            guard case let .invalidTableChecksum(tag, _, _) = error else {
                Issue.record("Expected invalid table checksum")
                return
            }
            #expect(tag == "hhea")
        }
    }

    @Test("Rejects missing required tables")
    func rejectsMissingRequiredTables() {
        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(omitting: ["head"]))
        } verify: { error in
            #expect(error == .missingRequiredTable("head"))
        }
    }

    @Test("Rejects table directory ranges outside the font")
    func rejectsTableDirectoryRangesOutsideTheFont() {
        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(invalidBoundsTag: "hhea"))
        } verify: { error in
            guard case let .invalidTableBounds(tag, _, _, _) = error else {
                Issue.record("Expected invalid table bounds")
                return
            }
            #expect(tag == "hhea")
        }
    }

    @Test("Rejects unsupported Unicode cmap formats")
    func rejectsUnsupportedUnicodeCMapFormats() {
        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(cmapFormat: 0))
        } verify: { error in
            guard case .unsupportedCMap = error else {
                Issue.record("Expected unsupported cmap")
                return
            }
        }
    }

    @Test("Rejects malformed supported cmap lengths")
    func rejectsMalformedSupportedCMapLengths() {
        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(cmapFormat: 12, malformedCMapLength: true))
        } verify: { error in
            guard case let .malformedTable(tag, reason) = error else {
                Issue.record("Expected malformed cmap")
                return
            }
            #expect(tag == "cmap")
            #expect(reason.contains("format 12"))
        }
    }

    @Test("Rejects malformed format 4 cmap segment arrays")
    func rejectsMalformedFormat4CMapSegmentArrays() {
        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(cmapFormat: 4, malformedCMapLength: true))
        } verify: { error in
            guard case let .malformedTable(tag, reason) = error else {
                Issue.record("Expected malformed cmap")
                return
            }
            #expect(tag == "cmap")
            #expect(reason.contains("format 4"))
        }
    }

    @Test("Rejects malformed format 12 cmap group counts")
    func rejectsMalformedFormat12CMapGroupCounts() {
        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(cmapFormat: 12, invalidCMapGroupCount: true))
        } verify: { error in
            guard case let .malformedTable(tag, reason) = error else {
                Issue.record("Expected malformed cmap")
                return
            }
            #expect(tag == "cmap")
            #expect(reason.contains("group count"))
        }
    }

    @Test("Discovers format 12 Unicode cmap records")
    func discoversFormat12UnicodeCMapRecords() throws {
        let metadata = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(cmapFormat: 12))

        #expect(metadata.cmap.selectedUnicodeFormat == 12)
        #expect(metadata.cmap.encodingRecords.first?.format == 12)
    }

    @Test("Rejects name tables whose storage overlaps records")
    func rejectsNameTablesWhoseStorageOverlapsRecords() {
        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(overlappingNameStorage: true))
        } verify: { error in
            guard case let .malformedTable(tag, reason) = error else {
                Issue.record("Expected malformed name table")
                return
            }
            #expect(tag == "name")
            #expect(reason.contains("overlaps"))
        }
    }

    @Test("Rejects format 1 name storage overlapping language tags")
    func rejectsFormat1NameStorageOverlappingLanguageTags() {
        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(
                SyntheticTrueTypeFont.data(nameFormat: 1, overlappingLanguageTagStorage: true),
            )
        } verify: { error in
            guard case let .malformedTable(tag, reason) = error else {
                Issue.record("Expected malformed name table")
                return
            }
            #expect(tag == "name")
            #expect(reason.contains("language-tag"))
        }
    }

    @Test("Parses format 1 name tables with language tags")
    func parsesFormat1NameTablesWithLanguageTags() throws {
        let metadata = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(nameFormat: 1))

        #expect(metadata.names.namesByID[1] == "MarkdownPDF Synthetic")
    }

    @Test("Prefers Unicode names over earlier non-Unicode records")
    func prefersUnicodeNamesOverEarlierNonUnicodeRecords() throws {
        let metadata = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(leadingNonUnicodeName: true))

        #expect(metadata.names.namesByID[1] == "MarkdownPDF Synthetic")
    }

    @Test("Rejects malformed head records")
    func rejectsMalformedHeadRecords() {
        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(invalidHeadUnitsPerEm: true))
        } verify: { error in
            guard case let .malformedTable(tag, reason) = error else {
                Issue.record("Expected malformed head table")
                return
            }
            #expect(tag == "head")
            #expect(reason.contains("unitsPerEm"))
        }

        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(invalidHeadIndexToLocFormat: true))
        } verify: { error in
            guard case let .malformedTable(tag, reason) = error else {
                Issue.record("Expected malformed head table")
                return
            }
            #expect(tag == "head")
            #expect(reason.contains("indexToLocFormat"))
        }

        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(invalidHeadBoundingBox: true))
        } verify: { error in
            guard case let .malformedTable(tag, reason) = error else {
                Issue.record("Expected malformed head table")
                return
            }
            #expect(tag == "head")
            #expect(reason.contains("bounding box"))
        }
    }

    @Test("Rejects malformed metric table versions")
    func rejectsMalformedMetricTableVersions() {
        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(invalidHheaVersion: true))
        } verify: { error in
            guard case let .malformedTable(tag, reason) = error else {
                Issue.record("Expected malformed hhea table")
                return
            }
            #expect(tag == "hhea")
            #expect(reason.contains("version"))
        }

        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(invalidMaxpVersion: true))
        } verify: { error in
            guard case let .malformedTable(tag, reason) = error else {
                Issue.record("Expected malformed maxp table")
                return
            }
            #expect(tag == "maxp")
            #expect(reason.contains("version"))
        }
    }

    @Test("Rejects short required metadata tables")
    func rejectsShortRequiredMetadataTables() {
        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(shortOS2: true))
        } verify: { error in
            guard case let .truncated(table, _, _, _) = error else {
                Issue.record("Expected truncated OS/2 table")
                return
            }
            #expect(table == "OS/2")
        }
    }

    @Test("Rejects restricted and bitmap-only embedding policy")
    func rejectsRestrictedAndBitmapOnlyEmbeddingPolicy() {
        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(fsType: 0x0002))
        } verify: { error in
            #expect(error == .restrictedEmbedding(fsType: 0x0002))
        }

        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(fsType: 0x0200))
        } verify: { error in
            #expect(error == .bitmapOnlyEmbedding(fsType: 0x0200))
        }
    }

    @Test("Rejects no-subsetting fonts only when subsetting is required")
    func rejectsNoSubsettingFontsOnlyWhenSubsettingIsRequired() throws {
        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(fsType: 0x0100))
        } verify: { error in
            #expect(error == .subsettingRequired(fsType: 0x0100))
        }

        let metadata = try TrueTypeFontParser().parse(
            SyntheticTrueTypeFont.data(fsType: 0x0100),
            embeddingPolicy: .allowNoSubsetting,
        )

        #expect(metadata.os2.permissions.noSubsetting)
    }

    private func expectTrueTypeError(
        _ body: () throws -> Void,
        verify: (TrueTypeFontError) -> Void,
    ) {
        do {
            try body()
            Issue.record("Expected TrueType parser error")
        } catch let error as TrueTypeFontError {
            #expect(error.errorDescription != nil)
            #expect(error.recoverySuggestion != nil)
            verify(error)
        } catch {
            Issue.record("Expected TrueTypeFontError, got \(error)")
        }
    }
}

enum SyntheticTrueTypeFont {
    static func data(
        fsType: UInt16 = 0,
        cmapFormat: UInt16 = 4,
        omitting omittedTables: Set<String> = [],
        corruptChecksumTag: String? = nil,
        invalidBoundsTag: String? = nil,
        invalidHeadUnitsPerEm: Bool = false,
        invalidHeadIndexToLocFormat: Bool = false,
        invalidHeadBoundingBox: Bool = false,
        invalidHheaVersion: Bool = false,
        invalidMaxpVersion: Bool = false,
        malformedCMapLength: Bool = false,
        cmapFormat4UsesGlyphArray: Bool = false,
        invalidCMapFormat4SegmentRange: Bool = false,
        invalidCMapFormat4SegmentOrder: Bool = false,
        invalidCMapFormat4ReservedPad: Bool = false,
        invalidCMapGroupCount: Bool = false,
        cmapFormat12StartGlyphID: UInt32 = 1,
        nameFormat: UInt16 = 0,
        leadingNonUnicodeName: Bool = false,
        overlappingNameStorage: Bool = false,
        overlappingLanguageTagStorage: Bool = false,
        shortOS2: Bool = false,
        includeGlyphOutlines: Bool = false,
    ) -> Data {
        var tables = [
            "head": headTable(
                invalidUnitsPerEm: invalidHeadUnitsPerEm,
                invalidIndexToLocFormat: invalidHeadIndexToLocFormat,
                invalidBoundingBox: invalidHeadBoundingBox,
            ),
            "hhea": hheaTable(invalidVersion: invalidHheaVersion),
            "hmtx": hmtxTable(),
            "maxp": maxpTable(invalidVersion: invalidMaxpVersion, includeGlyphOutlines: includeGlyphOutlines),
            "cmap": cmapTable(
                format: cmapFormat,
                malformedLength: malformedCMapLength,
                format4UsesGlyphArray: cmapFormat4UsesGlyphArray,
                invalidFormat4SegmentRange: invalidCMapFormat4SegmentRange,
                invalidFormat4SegmentOrder: invalidCMapFormat4SegmentOrder,
                invalidFormat4ReservedPad: invalidCMapFormat4ReservedPad,
                invalidGroupCount: invalidCMapGroupCount,
                format12StartGlyphID: cmapFormat12StartGlyphID,
            ),
            "name": nameTable(
                format: nameFormat,
                leadingNonUnicodeName: leadingNonUnicodeName,
                overlappingStringStorage: overlappingNameStorage,
                overlappingLanguageTagStorage: overlappingLanguageTagStorage,
            ),
            "OS/2": os2Table(fsType: fsType, short: shortOS2),
            "post": postTable(),
        ].filter { !omittedTables.contains($0.key) }
        if includeGlyphOutlines {
            tables["glyf"] = glyfTable()
            tables["loca"] = locaTable()
        }

        var records: [(tag: String, checksum: UInt32, offset: UInt32, length: UInt32)] = []
        var font = Data(count: 12 + tables.count * 16)
        for tag in tables.keys.sorted() {
            guard let tableData = tables[tag] else {
                continue
            }
            while !font.count.isMultiple(of: 4) {
                font.append(0)
            }
            let checksum = checksum(tableData, tag: tag)
            records.append((
                tag: tag,
                checksum: tag == corruptChecksumTag ? checksum &+ 1 : checksum,
                offset: UInt32(font.count),
                length: UInt32(tableData.count),
            ))
            font.append(tableData)
        }

        writeUInt32(0x0001_0000, at: 0, in: &font)
        writeUInt16(UInt16(records.count), at: 4, in: &font)
        let search = searchValues(tableCount: records.count)
        writeUInt16(search.searchRange, at: 6, in: &font)
        writeUInt16(search.entrySelector, at: 8, in: &font)
        writeUInt16(search.rangeShift, at: 10, in: &font)

        for (index, record) in records.enumerated() {
            let offset = 12 + index * 16
            writeTag(record.tag, at: offset, in: &font)
            writeUInt32(record.checksum, at: offset + 4, in: &font)
            writeUInt32(
                record.tag == invalidBoundsTag ? UInt32(font.count + 32) : record.offset,
                at: offset + 8,
                in: &font,
            )
            writeUInt32(record.length, at: offset + 12, in: &font)
        }

        return font
    }

    private static func headTable(
        invalidUnitsPerEm: Bool,
        invalidIndexToLocFormat: Bool,
        invalidBoundingBox: Bool,
    ) -> Data {
        var data = Data(count: 54)
        writeUInt32(0x0001_0000, at: 0, in: &data)
        writeUInt32(0x5F0F_3CF5, at: 12, in: &data)
        writeUInt16(invalidUnitsPerEm ? 1 : 1000, at: 18, in: &data)
        writeInt16(invalidBoundingBox ? 981 : -20, at: 36, in: &data)
        writeInt16(-200, at: 38, in: &data)
        writeInt16(980, at: 40, in: &data)
        writeInt16(900, at: 42, in: &data)
        writeInt16(invalidIndexToLocFormat ? 2 : 0, at: 50, in: &data)
        return data
    }

    private static func hheaTable(invalidVersion: Bool) -> Data {
        var data = Data(count: 36)
        writeUInt32(invalidVersion ? 0 : 0x0001_0000, at: 0, in: &data)
        writeInt16(800, at: 4, in: &data)
        writeInt16(-200, at: 6, in: &data)
        writeUInt16(600, at: 10, in: &data)
        writeInt16(1, at: 18, in: &data)
        writeUInt16(2, at: 34, in: &data)
        return data
    }

    private static func maxpTable(invalidVersion: Bool, includeGlyphOutlines: Bool) -> Data {
        var data = Data()
        appendUInt32(invalidVersion ? 0 : 0x0001_0000, to: &data)
        appendUInt16(3, to: &data)
        guard includeGlyphOutlines else {
            return data
        }

        appendUInt16(4, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(2, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        return data
    }

    private static func glyfTable() -> Data {
        var data = Data()
        data.append(simpleRectangleGlyph(xMin: 40, yMin: 0, xMax: 560, yMax: 700))
        data.append(simpleRectangleGlyph(xMin: 70, yMin: 0, xMax: 540, yMax: 700))
        return data
    }

    private static func locaTable() -> Data {
        var data = Data()
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(UInt16(simpleRectangleGlyph(xMin: 40, yMin: 0, xMax: 560, yMax: 700).count / 2), to: &data)
        appendUInt16(UInt16(glyfTable().count / 2), to: &data)
        return data
    }

    private static func simpleRectangleGlyph(xMin: Int16, yMin: Int16, xMax: Int16, yMax: Int16) -> Data {
        var data = Data()
        appendInt16(1, to: &data)
        appendInt16(xMin, to: &data)
        appendInt16(yMin, to: &data)
        appendInt16(xMax, to: &data)
        appendInt16(yMax, to: &data)
        appendUInt16(3, to: &data)
        appendUInt16(0, to: &data)
        data.append(contentsOf: [0x01, 0x01, 0x01, 0x01])
        appendInt16(xMin, to: &data)
        appendInt16(xMax - xMin, to: &data)
        appendInt16(0, to: &data)
        appendInt16(xMin - xMax, to: &data)
        appendInt16(yMin, to: &data)
        appendInt16(0, to: &data)
        appendInt16(yMax - yMin, to: &data)
        appendInt16(0, to: &data)
        return data
    }

    private static func hmtxTable() -> Data {
        var data = Data()
        appendUInt16(500, to: &data)
        appendInt16(0, to: &data)
        appendUInt16(600, to: &data)
        appendInt16(0, to: &data)
        appendInt16(0, to: &data)
        return data
    }

    private static func cmapTable(
        format: UInt16,
        malformedLength: Bool,
        format4UsesGlyphArray: Bool,
        invalidFormat4SegmentRange: Bool,
        invalidFormat4SegmentOrder: Bool,
        invalidFormat4ReservedPad: Bool,
        invalidGroupCount: Bool,
        format12StartGlyphID: UInt32,
    ) -> Data {
        var data = Data()
        appendUInt16(0, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(3, to: &data)
        appendUInt16(1, to: &data)
        appendUInt32(12, to: &data)

        switch format {
        case 4:
            data.append(
                format4CMapSubtable(
                    malformedLength: malformedLength,
                    usesGlyphArray: format4UsesGlyphArray,
                    invalidSegmentRange: invalidFormat4SegmentRange,
                    invalidSegmentOrder: invalidFormat4SegmentOrder,
                    invalidReservedPad: invalidFormat4ReservedPad,
                ),
            )
        case 12:
            data.append(
                format12CMapSubtable(
                    malformedLength: malformedLength,
                    invalidGroupCount: invalidGroupCount,
                    startGlyphID: format12StartGlyphID,
                ),
            )
        default:
            var subtable = Data(count: 262)
            writeUInt16(format, at: 0, in: &subtable)
            writeUInt16(262, at: 2, in: &subtable)
            data.append(subtable)
        }

        return data
    }

    private static func format4CMapSubtable(
        malformedLength: Bool,
        usesGlyphArray: Bool,
        invalidSegmentRange: Bool,
        invalidSegmentOrder: Bool,
        invalidReservedPad: Bool,
    ) -> Data {
        var data = Data()
        appendUInt16(4, to: &data)
        appendUInt16(malformedLength ? 24 : usesGlyphArray ? 36 : 32, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(4, to: &data)
        appendUInt16(4, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(invalidSegmentOrder ? 0xFFFF : invalidSegmentRange ? 0x0040 : 0x0042, to: &data)
        appendUInt16(invalidSegmentOrder ? 0x0042 : 0xFFFF, to: &data)
        appendUInt16(invalidReservedPad ? 1 : 0, to: &data)
        appendUInt16(invalidSegmentOrder ? 0xFFFF : 0x0041, to: &data)
        appendUInt16(invalidSegmentOrder ? 0x0041 : 0xFFFF, to: &data)
        appendUInt16(usesGlyphArray ? 0 : 0xFFC0, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(usesGlyphArray ? 4 : 0, to: &data)
        appendUInt16(0, to: &data)
        if usesGlyphArray {
            appendUInt16(1, to: &data)
            appendUInt16(2, to: &data)
        }
        return data
    }

    private static func format12CMapSubtable(
        malformedLength: Bool,
        invalidGroupCount: Bool,
        startGlyphID: UInt32,
    ) -> Data {
        var data = Data()
        appendUInt16(12, to: &data)
        appendUInt16(0, to: &data)
        appendUInt32(malformedLength ? 0 : 28, to: &data)
        appendUInt32(0, to: &data)
        appendUInt32(invalidGroupCount ? 0 : 1, to: &data)
        appendUInt32(0x0041, to: &data)
        appendUInt32(0x0042, to: &data)
        appendUInt32(startGlyphID, to: &data)
        return data
    }

    private static func nameTable(
        format: UInt16,
        leadingNonUnicodeName: Bool,
        overlappingStringStorage: Bool,
        overlappingLanguageTagStorage: Bool,
    ) -> Data {
        let nonUnicodeFamily = Data("Wrong Family".utf8)
        let family = utf16BE("MarkdownPDF Synthetic")
        let full = utf16BE("MarkdownPDF Synthetic Regular")
        let recordCount = leadingNonUnicodeName ? 3 : 2
        let recordEnd = 6 + recordCount * 12
        let languageTagRecordLength = format == 1 ? 6 : 0
        let validStringOffset = recordEnd + languageTagRecordLength
        let stringOffset = if overlappingStringStorage {
            6
        } else if overlappingLanguageTagStorage {
            validStringOffset - 2
        } else {
            validStringOffset
        }
        var data = Data()
        appendUInt16(format, to: &data)
        appendUInt16(UInt16(recordCount), to: &data)
        appendUInt16(UInt16(stringOffset), to: &data)
        var storageOffset: UInt16 = 0
        if leadingNonUnicodeName {
            appendNameRecord(
                platformID: 1,
                encodingID: 0,
                nameID: 1,
                length: UInt16(nonUnicodeFamily.count),
                offset: storageOffset,
                to: &data,
            )
            storageOffset += UInt16(nonUnicodeFamily.count)
        }
        appendNameRecord(
            platformID: 3,
            encodingID: 1,
            nameID: 1,
            length: UInt16(family.count),
            offset: storageOffset,
            to: &data,
        )
        storageOffset += UInt16(family.count)
        appendNameRecord(
            platformID: 3,
            encodingID: 1,
            nameID: 4,
            length: UInt16(full.count),
            offset: storageOffset,
            to: &data,
        )
        if format == 1 {
            appendUInt16(1, to: &data)
            appendUInt16(0, to: &data)
            appendUInt16(0, to: &data)
        }
        if leadingNonUnicodeName {
            data.append(nonUnicodeFamily)
        }
        data.append(family)
        data.append(full)
        return data
    }

    private static func os2Table(fsType: UInt16, short: Bool) -> Data {
        var data = Data(count: short ? 10 : 78)
        writeUInt16(4, at: 0, in: &data)
        writeUInt16(400, at: 4, in: &data)
        writeUInt16(5, at: 6, in: &data)
        writeUInt16(fsType, at: 8, in: &data)
        return data
    }

    private static func postTable() -> Data {
        var data = Data(count: 32)
        writeUInt32(0x0003_0000, at: 0, in: &data)
        return data
    }

    private static func appendNameRecord(
        platformID: UInt16,
        encodingID: UInt16,
        nameID: UInt16,
        length: UInt16,
        offset: UInt16,
        to data: inout Data,
    ) {
        appendUInt16(platformID, to: &data)
        appendUInt16(encodingID, to: &data)
        appendUInt16(0x0409, to: &data)
        appendUInt16(nameID, to: &data)
        appendUInt16(length, to: &data)
        appendUInt16(offset, to: &data)
    }

    private static func searchValues(tableCount: Int) -> (searchRange: UInt16, entrySelector: UInt16, rangeShift: UInt16) {
        var maximumPower = 1
        var selector = 0
        while maximumPower * 2 <= tableCount {
            maximumPower *= 2
            selector += 1
        }
        let searchRange = maximumPower * 16
        return (
            searchRange: UInt16(searchRange),
            entrySelector: UInt16(selector),
            rangeShift: UInt16(tableCount * 16 - searchRange),
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

    private static func utf16BE(_ string: String) -> Data {
        var data = Data()
        for unit in string.utf16 {
            appendUInt16(unit, to: &data)
        }
        return data
    }

    private static func writeTag(_ tag: String, at offset: Int, in data: inout Data) {
        let bytes = Array(tag.utf8)
        precondition(bytes.count == 4)
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
}
