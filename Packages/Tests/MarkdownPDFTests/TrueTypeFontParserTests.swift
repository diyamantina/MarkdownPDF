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
        #expect(metadata.math == nil)
    }

    @Test("Parses renderable synthetic Latin witness font")
    func parsesRenderableSyntheticLatinWitnessFont() throws {
        let metadata = try TrueTypeFontParser().parse(
            SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true),
        )
        let tableTags = metadata.tables.map(\.tag).sorted()

        #expect(tableTags.contains("glyf"))
        #expect(tableTags.contains("loca"))
        #expect(metadata.maxp.numGlyphs == 28)
        #expect(metadata.hhea.numberOfHMetrics == 28)
        #expect(metadata.hmtx.advanceWidths[1] == 280)
        #expect(metadata.hmtx.advanceWidths[10] == 260)
        #expect(metadata.hmtx.advanceWidths[24] == 900)
    }

    @Test("Parses renderable synthetic CJK witness font")
    func parsesRenderableSyntheticCJKWitnessFont() throws {
        let metadata = try TrueTypeFontParser().parse(
            SyntheticTrueTypeFont.data(cmapFormat: 12, glyphProfile: .cjkWitness, includeGlyphOutlines: true),
        )
        let tableTags = metadata.tables.map(\.tag).sorted()

        #expect(tableTags.contains("glyf"))
        #expect(tableTags.contains("loca"))
        #expect(metadata.cmap.selectedUnicodeFormat == 12)
        #expect(metadata.maxp.numGlyphs == 5)
        #expect(metadata.hhea.numberOfHMetrics == 5)
        #expect(metadata.hmtx.advanceWidths == [500, 1000, 1000, 1000, 500])
    }

    @Test("Parses renderable synthetic CJK diacritic witness font")
    func parsesRenderableSyntheticCJKDiacriticWitnessFont() throws {
        let metadata = try TrueTypeFontParser().parse(
            SyntheticTrueTypeFont.data(
                cmapFormat: 12,
                glyphProfile: .cjkDiacriticWitness,
                includeGlyphOutlines: true,
            ),
        )

        #expect(metadata.cmap.selectedUnicodeFormat == 12)
        #expect(metadata.maxp.numGlyphs == 19)
        #expect(metadata.hhea.numberOfHMetrics == 19)
        #expect(Array(metadata.hmtx.advanceWidths[1 ... 9]) == [1000, 1000, 1000, 1000, 1000, 500, 280, 500, 0])
        #expect(Array(metadata.hmtx.advanceWidths[10 ... 18]) == [520, 500, 450, 250, 520, 500, 500, 500, 250])
    }

    @Test("Parses OpenType MATH constants glyph info variants and assembly")
    func parsesOpenTypeMathConstantsGlyphInfoVariantsAndAssembly() throws {
        let defaultMetadata = try TrueTypeFontParser().parse(SyntheticTrueTypeFont.data(includeMATHTable: true))
        #expect(defaultMetadata.math == nil)

        let metadata = try TrueTypeFontParser().parse(
            SyntheticTrueTypeFont.data(includeMATHTable: true),
            parseMathTable: true,
        )
        let math = try #require(metadata.math)

        #expect(math.majorVersion == 1)
        #expect(math.minorVersion == 0)
        #expect(math.constants.scriptPercentScaleDown == 80)
        #expect(math.constants.scriptScriptPercentScaleDown == 60)
        #expect(math.constants.delimitedSubFormulaMinHeight == 1500)
        #expect(math.constants.displayOperatorMinHeight == 900)
        #expect(math.constants.value(.axisHeight)?.value == 101)
        #expect(math.constants.value(.fractionRuleThickness)?.value == 134)
        #expect(math.constants.value(.radicalKernAfterDegree)?.value == 150)
        #expect(math.constants.radicalDegreeBottomRaisePercent == 60)

        #expect(math.glyphInfo.italicsCorrections == [
            TrueTypeMathTable.GlyphValueRecord(
                glyphID: 1,
                value: TrueTypeMathTable.MathValueRecord(value: 37, deviceOffset: 0),
            ),
        ])
        #expect(math.glyphInfo.topAccentAttachments == [
            TrueTypeMathTable.GlyphValueRecord(
                glyphID: 1,
                value: TrueTypeMathTable.MathValueRecord(value: 250, deviceOffset: 0),
            ),
        ])
        #expect(math.glyphInfo.extendedShapeGlyphIDs == [2])

        let kern = try #require(math.glyphInfo.mathKerns.first)
        #expect(kern.glyphID == 1)
        #expect(kern.topRight?.correctionHeights.map(\.value) == [-100, 400])
        #expect(kern.topRight?.kernValues.map(\.value) == [15, 5, -20])
        #expect(kern.topLeft == nil)
        #expect(kern.bottomRight == nil)
        #expect(kern.bottomLeft == nil)

        #expect(math.variants.minConnectorOverlap == 12)
        let vertical = try #require(math.variants.verticalConstructions.first)
        #expect(vertical.glyphID == 2)
        #expect(vertical.variants == [
            TrueTypeMathTable.GlyphVariant(glyphID: 1, advanceMeasurement: 900),
        ])
        #expect(vertical.assembly?.italicsCorrection.value == 11)
        #expect(vertical.assembly?.parts == [
            TrueTypeMathTable.GlyphPart(
                glyphID: 1,
                startConnectorLength: 10,
                endConnectorLength: 20,
                fullAdvance: 400,
                partFlags: 0,
            ),
            TrueTypeMathTable.GlyphPart(
                glyphID: 2,
                startConnectorLength: 15,
                endConnectorLength: 15,
                fullAdvance: 300,
                partFlags: 1,
            ),
        ])
        #expect(vertical.assembly?.parts.last?.isExtender == true)

        let horizontal = try #require(math.variants.horizontalConstructions.first)
        #expect(horizontal.glyphID == 1)
        #expect(horizontal.assembly == nil)
        #expect(horizontal.variants == [
            TrueTypeMathTable.GlyphVariant(glyphID: 2, advanceMeasurement: 800),
        ])
    }

    @Test("Rejects malformed OpenType MATH table offsets and record counts")
    func rejectsMalformedOpenTypeMathTableOffsetsAndRecordCounts() {
        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(
                SyntheticTrueTypeFont.data(includeMATHTable: true, invalidMATHConstantsOffset: true),
                parseMathTable: true,
            )
        } verify: { error in
            guard case let .malformedTable(tag, reason) = error else {
                Issue.record("Expected malformed MATH table")
                return
            }
            #expect(tag == "MATH")
            #expect(reason.contains("MathConstants"))
        }

        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(
                SyntheticTrueTypeFont.data(includeMATHTable: true, mismatchedMATHItalicsCount: true),
                parseMathTable: true,
            )
        } verify: { error in
            guard case let .malformedTable(tag, reason) = error else {
                Issue.record("Expected malformed MATH table")
                return
            }
            #expect(tag == "MATH")
            #expect(reason.contains("count"))
        }
    }

    @Test("Rejects OpenType MATH glyph IDs outside maxp")
    func rejectsOpenTypeMathGlyphIDsOutsideMaxp() {
        expectTrueTypeError {
            _ = try TrueTypeFontParser().parse(
                SyntheticTrueTypeFont.data(includeMATHTable: true, invalidMATHGlyphID: true),
                parseMathTable: true,
            )
        } verify: { error in
            guard case let .malformedTable(tag, reason) = error else {
                Issue.record("Expected malformed MATH table")
                return
            }
            #expect(tag == "MATH")
            #expect(reason.contains("maxp.numGlyphs"))
        }
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
    enum GlyphProfile {
        case basic
        case compositeWitness
        case cjkDiacriticWitness
        case cjkWitness
        case largeBMPWitness
        case latinWitness
        case latinLigature
        case rtlWitness
    }

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
        glyphProfile: GlyphProfile = .basic,
        includeGlyphOutlines: Bool = false,
        includeGSUBLigatures: Bool = false,
        includeMATHTable: Bool = false,
        invalidMATHConstantsOffset: Bool = false,
        mismatchedMATHItalicsCount: Bool = false,
        invalidMATHGlyphID: Bool = false,
    ) -> Data {
        let glyphSet = GlyphSet(profile: glyphProfile)
        var tables = [
            "head": headTable(
                invalidUnitsPerEm: invalidHeadUnitsPerEm,
                invalidIndexToLocFormat: invalidHeadIndexToLocFormat,
                invalidBoundingBox: invalidHeadBoundingBox,
            ),
            "hhea": hheaTable(invalidVersion: invalidHheaVersion, glyphSet: glyphSet),
            "hmtx": hmtxTable(glyphSet: glyphSet),
            "maxp": maxpTable(
                invalidVersion: invalidMaxpVersion,
                includeGlyphOutlines: includeGlyphOutlines,
                glyphSet: glyphSet,
            ),
            "cmap": cmapTable(
                format: cmapFormat,
                malformedLength: malformedCMapLength,
                format4UsesGlyphArray: cmapFormat4UsesGlyphArray,
                invalidFormat4SegmentRange: invalidCMapFormat4SegmentRange,
                invalidFormat4SegmentOrder: invalidCMapFormat4SegmentOrder,
                invalidFormat4ReservedPad: invalidCMapFormat4ReservedPad,
                invalidGroupCount: invalidCMapGroupCount,
                format12StartGlyphID: cmapFormat12StartGlyphID,
                glyphSet: glyphSet,
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
            if !omittedTables.contains("glyf") {
                tables["glyf"] = glyfTable(glyphSet: glyphSet)
            }
            if !omittedTables.contains("loca") {
                tables["loca"] = locaTable(glyphSet: glyphSet)
            }
        }
        if includeGSUBLigatures, !omittedTables.contains("GSUB") {
            tables["GSUB"] = gsubLigatureTable(glyphSet: glyphSet)
        }
        if includeMATHTable, !omittedTables.contains("MATH") {
            tables["MATH"] = mathTable(
                invalidConstantsOffset: invalidMATHConstantsOffset,
                mismatchedItalicsCount: mismatchedMATHItalicsCount,
                invalidGlyphID: invalidMATHGlyphID,
            )
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

    private static func hheaTable(invalidVersion: Bool, glyphSet: GlyphSet) -> Data {
        var data = Data(count: 36)
        writeUInt32(invalidVersion ? 0 : 0x0001_0000, at: 0, in: &data)
        writeInt16(800, at: 4, in: &data)
        writeInt16(-200, at: 6, in: &data)
        writeUInt16(glyphSet.advanceWidthMax, at: 10, in: &data)
        writeInt16(1, at: 18, in: &data)
        writeUInt16(glyphSet.numberOfHMetrics, at: 34, in: &data)
        return data
    }

    private static func maxpTable(
        invalidVersion: Bool,
        includeGlyphOutlines: Bool,
        glyphSet: GlyphSet,
    ) -> Data {
        var data = Data()
        appendUInt32(invalidVersion ? 0 : 0x0001_0000, to: &data)
        appendUInt16(glyphSet.numGlyphs, to: &data)
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
        appendUInt16(glyphSet.containsCompositeGlyphs ? 2 : 0, to: &data)
        appendUInt16(glyphSet.containsCompositeGlyphs ? 1 : 0, to: &data)
        return data
    }

    private static func glyfTable(glyphSet: GlyphSet) -> Data {
        var data = Data()
        for glyph in glyphSet.glyphs {
            data.append(glyphData(for: glyph))
        }
        return data
    }

    private static func locaTable(glyphSet: GlyphSet) -> Data {
        var data = Data()
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        var glyfOffset = 0
        for glyph in glyphSet.glyphs {
            glyfOffset += glyphData(for: glyph).count
            appendUInt16(UInt16(glyfOffset / 2), to: &data)
        }
        return data
    }

    private static func glyphData(for glyph: GlyphRecord) -> Data {
        if !glyph.components.isEmpty {
            return compositeGlyph(componentGlyphIDs: glyph.components)
        }
        guard let xMin = glyph.xMin, let xMax = glyph.xMax else {
            return Data()
        }
        return simpleRectangleGlyph(xMin: xMin, yMin: 0, xMax: xMax, yMax: 700)
    }

    private static func compositeGlyph(componentGlyphIDs: [UInt16]) -> Data {
        var data = Data()
        appendInt16(-1, to: &data)
        appendInt16(40, to: &data)
        appendInt16(0, to: &data)
        appendInt16(720, to: &data)
        appendInt16(700, to: &data)

        for (index, componentGlyphID) in componentGlyphIDs.enumerated() {
            var flags: UInt16 = 0x0001 | 0x0002
            if index + 1 < componentGlyphIDs.count {
                flags |= 0x0020
            }
            appendUInt16(flags, to: &data)
            appendUInt16(componentGlyphID, to: &data)
            appendInt16(Int16(index * 180), to: &data)
            appendInt16(0, to: &data)
        }
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

    private static func hmtxTable(glyphSet: GlyphSet) -> Data {
        if glyphSet.profile == .basic {
            var data = Data()
            appendUInt16(500, to: &data)
            appendInt16(0, to: &data)
            appendUInt16(600, to: &data)
            appendInt16(0, to: &data)
            appendInt16(0, to: &data)
            return data
        }

        var data = Data()
        appendUInt16(500, to: &data)
        appendInt16(0, to: &data)
        for glyph in glyphSet.glyphs {
            appendUInt16(glyph.advanceWidth, to: &data)
            appendInt16(0, to: &data)
        }
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
        glyphSet: GlyphSet,
    ) -> Data {
        var data = Data()
        appendUInt16(0, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(3, to: &data)
        appendUInt16(1, to: &data)
        appendUInt32(12, to: &data)

        switch format {
        case 4:
            if glyphSet.profile == .basic {
                data.append(
                    format4CMapSubtable(
                        malformedLength: malformedLength,
                        usesGlyphArray: format4UsesGlyphArray,
                        invalidSegmentRange: invalidFormat4SegmentRange,
                        invalidSegmentOrder: invalidFormat4SegmentOrder,
                        invalidReservedPad: invalidFormat4ReservedPad,
                    ),
                )
            } else {
                data.append(format4GlyphSetCMapSubtable(malformedLength: malformedLength, glyphSet: glyphSet))
            }
        case 12:
            if glyphSet.profile == .basic {
                data.append(
                    format12CMapSubtable(
                        malformedLength: malformedLength,
                        invalidGroupCount: invalidGroupCount,
                        startGlyphID: format12StartGlyphID,
                    ),
                )
            } else {
                data.append(format12GlyphSetCMapSubtable(
                    malformedLength: malformedLength,
                    invalidGroupCount: invalidGroupCount,
                    glyphSet: glyphSet,
                ))
            }
        default:
            var subtable = Data(count: 262)
            writeUInt16(format, at: 0, in: &subtable)
            writeUInt16(262, at: 2, in: &subtable)
            data.append(subtable)
        }

        return data
    }

    private static func format4GlyphSetCMapSubtable(malformedLength: Bool, glyphSet: GlyphSet) -> Data {
        if glyphSet.profile == .latinWitness {
            return format4LatinWitnessCMapSubtable(malformedLength: malformedLength)
        }

        let entries = glyphSet.encodedGlyphs
            .map { (code: UInt16($0.scalar.value), glyphID: $0.glyphID) }
            .sorted { lhs, rhs in lhs.code < rhs.code }
        let segmentCount = entries.count + 1
        let length = 16 + segmentCount * 8
        let search = cmapSearchValues(segmentCount: segmentCount)
        var data = Data()
        appendUInt16(4, to: &data)
        appendUInt16(malformedLength ? 24 : UInt16(length), to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(UInt16(segmentCount * 2), to: &data)
        appendUInt16(search.searchRange, to: &data)
        appendUInt16(search.entrySelector, to: &data)
        appendUInt16(search.rangeShift, to: &data)
        for entry in entries {
            appendUInt16(entry.code, to: &data)
        }
        appendUInt16(0xFFFF, to: &data)
        appendUInt16(0, to: &data)
        for entry in entries {
            appendUInt16(entry.code, to: &data)
        }
        appendUInt16(0xFFFF, to: &data)
        for entry in entries {
            appendUInt16(UInt16(truncatingIfNeeded: Int(entry.glyphID) - Int(entry.code)), to: &data)
        }
        appendUInt16(1, to: &data)
        for _ in 0 ..< segmentCount {
            appendUInt16(0, to: &data)
        }
        return data
    }

    private static func format4LatinWitnessCMapSubtable(malformedLength: Bool) -> Data {
        var data = Data()
        appendUInt16(4, to: &data)
        appendUInt16(malformedLength ? 24 : 40, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(6, to: &data)
        appendUInt16(4, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(2, to: &data)
        appendUInt16(0x0020, to: &data)
        appendUInt16(0x005A, to: &data)
        appendUInt16(0xFFFF, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0x0020, to: &data)
        appendUInt16(0x0041, to: &data)
        appendUInt16(0xFFFF, to: &data)
        appendInt16(-31, to: &data)
        appendInt16(-63, to: &data)
        appendInt16(1, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
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

    private static func format12GlyphSetCMapSubtable(
        malformedLength: Bool,
        invalidGroupCount: Bool,
        glyphSet: GlyphSet,
    ) -> Data {
        if glyphSet.profile == .latinWitness {
            return format12LatinWitnessCMapSubtable(
                malformedLength: malformedLength,
                invalidGroupCount: invalidGroupCount,
            )
        }

        let entries = glyphSet.encodedGlyphs
            .map { (code: $0.scalar.value, glyphID: UInt32($0.glyphID)) }
            .sorted { lhs, rhs in lhs.code < rhs.code }
        var data = Data()
        appendUInt16(12, to: &data)
        appendUInt16(0, to: &data)
        appendUInt32(malformedLength ? 0 : UInt32(16 + entries.count * 12), to: &data)
        appendUInt32(0, to: &data)
        appendUInt32(invalidGroupCount ? 0 : UInt32(entries.count), to: &data)
        for entry in entries {
            appendUInt32(entry.code, to: &data)
            appendUInt32(entry.code, to: &data)
            appendUInt32(entry.glyphID, to: &data)
        }
        return data
    }

    private static func format12LatinWitnessCMapSubtable(
        malformedLength: Bool,
        invalidGroupCount: Bool,
    ) -> Data {
        var data = Data()
        appendUInt16(12, to: &data)
        appendUInt16(0, to: &data)
        appendUInt32(malformedLength ? 0 : 40, to: &data)
        appendUInt32(0, to: &data)
        appendUInt32(invalidGroupCount ? 0 : 2, to: &data)
        appendUInt32(0x0020, to: &data)
        appendUInt32(0x0020, to: &data)
        appendUInt32(1, to: &data)
        appendUInt32(0x0041, to: &data)
        appendUInt32(0x005A, to: &data)
        appendUInt32(2, to: &data)
        return data
    }

    private static func mathTable(
        invalidConstantsOffset: Bool,
        mismatchedItalicsCount: Bool,
        invalidGlyphID: Bool,
    ) -> Data {
        let constants = mathConstantsTable()
        let glyphInfo = mathGlyphInfoTable(mismatchedItalicsCount: mismatchedItalicsCount)
        let variants = mathVariantsTable(invalidGlyphID: invalidGlyphID)
        let constantsOffset = UInt16(10)
        let glyphInfoOffset = UInt16(10 + constants.count)
        let variantsOffset = UInt16(10 + constants.count + glyphInfo.count)

        var data = Data()
        appendUInt16(1, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(invalidConstantsOffset ? 0xFF00 : constantsOffset, to: &data)
        appendUInt16(glyphInfoOffset, to: &data)
        appendUInt16(variantsOffset, to: &data)
        data.append(constants)
        data.append(glyphInfo)
        data.append(variants)
        return data
    }

    private static func mathConstantsTable() -> Data {
        var data = Data()
        appendInt16(80, to: &data)
        appendInt16(60, to: &data)
        appendUInt16(1500, to: &data)
        appendUInt16(900, to: &data)
        for (index, _) in TrueTypeMathTable.Constants.ValueName.allCases.enumerated() {
            appendMathValue(Int16(100 + index), to: &data)
        }
        appendInt16(60, to: &data)
        return data
    }

    private static func mathGlyphInfoTable(mismatchedItalicsCount: Bool) -> Data {
        let italics = mathGlyphValueTable(
            coverageGlyphIDs: [1],
            values: mismatchedItalicsCount ? [37, 38] : [37],
        )
        let topAccent = mathGlyphValueTable(coverageGlyphIDs: [1], values: [250])
        let extendedShapes = coverageFormat1([2])
        let kernInfo = mathKernInfoTable()

        var data = Data(count: 8)
        data.append(italics)
        data.append(topAccent)
        data.append(extendedShapes)
        data.append(kernInfo)

        var offset = 8
        writeUInt16(UInt16(offset), at: 0, in: &data)
        offset += italics.count
        writeUInt16(UInt16(offset), at: 2, in: &data)
        offset += topAccent.count
        writeUInt16(UInt16(offset), at: 4, in: &data)
        offset += extendedShapes.count
        writeUInt16(UInt16(offset), at: 6, in: &data)
        return data
    }

    private static func mathGlyphValueTable(
        coverageGlyphIDs: [UInt16],
        values: [Int16],
    ) -> Data {
        let coverage = coverageFormat1(coverageGlyphIDs)
        var data = Data()
        appendUInt16(UInt16(4 + values.count * 4), to: &data)
        appendUInt16(UInt16(values.count), to: &data)
        values.forEach { appendMathValue($0, to: &data) }
        data.append(coverage)
        return data
    }

    private static func mathKernInfoTable() -> Data {
        let coverage = coverageFormat1([1])
        let kern = mathKernTable()
        var data = Data(count: 12)
        data.append(coverage)
        data.append(kern)

        writeUInt16(12, at: 0, in: &data)
        writeUInt16(1, at: 2, in: &data)
        writeUInt16(UInt16(12 + coverage.count), at: 4, in: &data)
        writeUInt16(0, at: 6, in: &data)
        writeUInt16(0, at: 8, in: &data)
        writeUInt16(0, at: 10, in: &data)
        return data
    }

    private static func mathKernTable() -> Data {
        var data = Data()
        appendUInt16(2, to: &data)
        appendMathValue(-100, to: &data)
        appendMathValue(400, to: &data)
        appendMathValue(15, to: &data)
        appendMathValue(5, to: &data)
        appendMathValue(-20, to: &data)
        return data
    }

    private static func mathVariantsTable(invalidGlyphID: Bool) -> Data {
        let verticalCoverage = coverageFormat1([2])
        let horizontalCoverage = coverageFormat1([1])
        let verticalConstruction = mathGlyphConstructionTable(
            assembly: mathGlyphAssemblyTable(),
            variants: [(glyphID: invalidGlyphID ? 99 : 1, advanceMeasurement: 900)],
        )
        let horizontalConstruction = mathGlyphConstructionTable(
            assembly: nil,
            variants: [(glyphID: 2, advanceMeasurement: 800)],
        )

        var data = Data(count: 14)
        data.append(verticalCoverage)
        data.append(horizontalCoverage)
        data.append(verticalConstruction)
        data.append(horizontalConstruction)

        var offset = 14
        writeUInt16(12, at: 0, in: &data)
        writeUInt16(UInt16(offset), at: 2, in: &data)
        offset += verticalCoverage.count
        writeUInt16(UInt16(offset), at: 4, in: &data)
        offset += horizontalCoverage.count
        writeUInt16(1, at: 6, in: &data)
        writeUInt16(1, at: 8, in: &data)
        writeUInt16(UInt16(offset), at: 10, in: &data)
        offset += verticalConstruction.count
        writeUInt16(UInt16(offset), at: 12, in: &data)
        return data
    }

    private static func mathGlyphConstructionTable(
        assembly: Data?,
        variants: [(glyphID: UInt16, advanceMeasurement: UInt16)],
    ) -> Data {
        var data = Data()
        let assemblyOffset = assembly.map { _ in UInt16(4 + variants.count * 4) } ?? 0
        appendUInt16(assemblyOffset, to: &data)
        appendUInt16(UInt16(variants.count), to: &data)
        for variant in variants {
            appendUInt16(variant.glyphID, to: &data)
            appendUInt16(variant.advanceMeasurement, to: &data)
        }
        if let assembly {
            data.append(assembly)
        }
        return data
    }

    private static func mathGlyphAssemblyTable() -> Data {
        var data = Data()
        appendMathValue(11, to: &data)
        appendUInt16(2, to: &data)
        appendGlyphPart(glyphID: 1, start: 10, end: 20, fullAdvance: 400, flags: 0, to: &data)
        appendGlyphPart(glyphID: 2, start: 15, end: 15, fullAdvance: 300, flags: 1, to: &data)
        return data
    }

    private static func coverageFormat1(_ glyphIDs: [UInt16]) -> Data {
        var data = Data()
        appendUInt16(1, to: &data)
        appendUInt16(UInt16(glyphIDs.count), to: &data)
        glyphIDs.forEach { appendUInt16($0, to: &data) }
        return data
    }

    private static func appendMathValue(_ value: Int16, to data: inout Data) {
        appendInt16(value, to: &data)
        appendUInt16(0, to: &data)
    }

    private static func appendGlyphPart(
        glyphID: UInt16,
        start: UInt16,
        end: UInt16,
        fullAdvance: UInt16,
        flags: UInt16,
        to data: inout Data,
    ) {
        appendUInt16(glyphID, to: &data)
        appendUInt16(start, to: &data)
        appendUInt16(end, to: &data)
        appendUInt16(fullAdvance, to: &data)
        appendUInt16(flags, to: &data)
    }

    private static func gsubLigatureTable(glyphSet: GlyphSet) -> Data {
        guard let firstGlyphID = glyphSet.glyphID(for: "f"),
              let secondGlyphID = glyphSet.glyphID(for: "i"),
              let ligatureGlyphID = glyphSet.glyphID(named: "fi")
        else {
            preconditionFailure("The GSUB ligature fixture requires f, i, and fi glyphs")
        }

        let scriptList = gsubScriptListTable()
        let featureList = gsubFeatureListTable()
        let lookupList = gsubLookupListTable(
            firstGlyphID: firstGlyphID,
            secondGlyphID: secondGlyphID,
            ligatureGlyphID: ligatureGlyphID,
        )

        var data = Data()
        appendUInt16(1, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(10, to: &data)
        appendUInt16(UInt16(10 + scriptList.count), to: &data)
        appendUInt16(UInt16(10 + scriptList.count + featureList.count), to: &data)
        data.append(scriptList)
        data.append(featureList)
        data.append(lookupList)
        return data
    }

    private static func gsubScriptListTable() -> Data {
        var data = Data()
        appendUInt16(1, to: &data)
        appendTag("latn", to: &data)
        appendUInt16(8, to: &data)

        appendUInt16(4, to: &data)
        appendUInt16(0, to: &data)

        appendUInt16(0, to: &data)
        appendUInt16(0xFFFF, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(0, to: &data)
        return data
    }

    private static func gsubFeatureListTable() -> Data {
        var data = Data()
        appendUInt16(1, to: &data)
        appendTag("liga", to: &data)
        appendUInt16(8, to: &data)

        appendUInt16(0, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(0, to: &data)
        return data
    }

    private static func gsubLookupListTable(
        firstGlyphID: UInt16,
        secondGlyphID: UInt16,
        ligatureGlyphID: UInt16,
    ) -> Data {
        let subtable = gsubLigatureSubtable(
            firstGlyphID: firstGlyphID,
            secondGlyphID: secondGlyphID,
            ligatureGlyphID: ligatureGlyphID,
        )

        var data = Data()
        appendUInt16(1, to: &data)
        appendUInt16(4, to: &data)

        appendUInt16(4, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(8, to: &data)
        data.append(subtable)
        return data
    }

    private static func gsubLigatureSubtable(
        firstGlyphID: UInt16,
        secondGlyphID: UInt16,
        ligatureGlyphID: UInt16,
    ) -> Data {
        var data = Data()
        appendUInt16(1, to: &data)
        appendUInt16(18, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(8, to: &data)

        appendUInt16(1, to: &data)
        appendUInt16(4, to: &data)
        appendUInt16(ligatureGlyphID, to: &data)
        appendUInt16(2, to: &data)
        appendUInt16(secondGlyphID, to: &data)

        appendUInt16(1, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(firstGlyphID, to: &data)
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

    private struct GlyphSet {
        var profile: GlyphProfile
        var glyphs: [GlyphRecord]

        init(profile: GlyphProfile) {
            self.profile = profile
            glyphs = switch profile {
            case .basic:
                [
                    GlyphRecord(scalar: "A", advanceWidth: 600, xMin: 40, xMax: 560),
                    GlyphRecord(scalar: "B", advanceWidth: 600, xMin: 70, xMax: 540),
                ]
            case .compositeWitness:
                [
                    GlyphRecord(scalar: "A", advanceWidth: 600, xMin: 40, xMax: 560),
                    GlyphRecord(scalar: "B", advanceWidth: 620, xMin: 70, xMax: 540),
                    GlyphRecord(scalar: "C", advanceWidth: 740, xMin: 40, xMax: 720, components: [1, 2]),
                ]
            case .cjkDiacriticWitness:
                [
                    GlyphRecord(scalar: "漢", advanceWidth: 1000, xMin: 60, xMax: 940),
                    GlyphRecord(scalar: "字", advanceWidth: 1000, xMin: 60, xMax: 940),
                    GlyphRecord(scalar: "語", advanceWidth: 1000, xMin: 60, xMax: 940),
                    GlyphRecord(scalar: "仮", advanceWidth: 1000, xMin: 60, xMax: 940),
                    GlyphRecord(scalar: "名", advanceWidth: 1000, xMin: 60, xMax: 940),
                    GlyphRecord(scalar: "。", advanceWidth: 500, xMin: 120, xMax: 420),
                    GlyphRecord(scalar: " ", advanceWidth: 280, xMin: nil, xMax: nil),
                    GlyphRecord(scalar: "e", advanceWidth: 500, xMin: 50, xMax: 430),
                    GlyphRecord(scalar: "\u{0301}", advanceWidth: 0, xMin: 120, xMax: 260),
                    GlyphRecord(scalar: "L", advanceWidth: 520, xMin: 50, xMax: 450),
                    GlyphRecord(scalar: "a", advanceWidth: 500, xMin: 50, xMax: 430),
                    GlyphRecord(scalar: "t", advanceWidth: 450, xMin: 50, xMax: 390),
                    GlyphRecord(scalar: "i", advanceWidth: 250, xMin: 90, xMax: 170),
                    GlyphRecord(scalar: "n", advanceWidth: 520, xMin: 50, xMax: 470),
                    GlyphRecord(scalar: "x", advanceWidth: 500, xMin: 50, xMax: 440),
                    GlyphRecord(scalar: "1", advanceWidth: 500, xMin: 90, xMax: 420),
                    GlyphRecord(scalar: "2", advanceWidth: 500, xMin: 60, xMax: 430),
                    GlyphRecord(scalar: ".", advanceWidth: 250, xMin: 100, xMax: 150),
                ]
            case .cjkWitness:
                [
                    GlyphRecord(scalar: "漢", advanceWidth: 1000, xMin: 60, xMax: 940),
                    GlyphRecord(scalar: "字", advanceWidth: 1000, xMin: 60, xMax: 940),
                    GlyphRecord(scalar: "語", advanceWidth: 1000, xMin: 60, xMax: 940),
                    GlyphRecord(scalar: "。", advanceWidth: 500, xMin: 120, xMax: 420),
                ]
            case .largeBMPWitness:
                (0 ..< 8200).map { index in
                    GlyphRecord(
                        scalar: UnicodeScalar(UInt32(0x4000 + index)) ?? "A",
                        advanceWidth: 500,
                        xMin: nil,
                        xMax: nil,
                    )
                }
            case .latinWitness:
                [GlyphRecord(scalar: " ", advanceWidth: 280, xMin: nil, xMax: nil)]
                    + (UInt8(ascii: "A") ... UInt8(ascii: "Z")).map { byte in
                        let scalar = UnicodeScalar(byte)
                        let width = Self.latinWitnessAdvanceWidth(for: scalar)
                        return GlyphRecord(
                            scalar: scalar,
                            advanceWidth: width,
                            xMin: 50,
                            xMax: Int16(max(120, Int(width) - 70)),
                        )
                    }
            case .latinLigature:
                [
                    GlyphRecord(scalar: "f", advanceWidth: 420, xMin: 50, xMax: 350),
                    GlyphRecord(scalar: "i", advanceWidth: 250, xMin: 90, xMax: 170),
                    GlyphRecord(scalar: "l", advanceWidth: 250, xMin: 80, xMax: 160),
                    GlyphRecord(scalar: "e", advanceWidth: 500, xMin: 50, xMax: 430),
                    GlyphRecord(scalar: "\u{0301}", advanceWidth: 0, xMin: 120, xMax: 260),
                    GlyphRecord(scalar: nil, name: "fi", advanceWidth: 620, xMin: 40, xMax: 570),
                ]
            case .rtlWitness:
                Self.rtlWitnessGlyphs()
            }
        }

        var numGlyphs: UInt16 {
            UInt16(glyphs.count + 1)
        }

        var advanceWidthMax: UInt16 {
            max(500, glyphs.map(\.advanceWidth).max() ?? 0)
        }

        var containsCompositeGlyphs: Bool {
            glyphs.contains { !$0.components.isEmpty }
        }

        var encodedGlyphs: [(glyphID: UInt16, scalar: UnicodeScalar, glyph: GlyphRecord)] {
            glyphs.enumerated().compactMap { index, glyph in
                guard let scalar = glyph.scalar else {
                    return nil
                }
                return (glyphID: UInt16(index + 1), scalar: scalar, glyph: glyph)
            }
        }

        var numberOfHMetrics: UInt16 {
            switch profile {
            case .basic:
                2
            case .compositeWitness, .cjkDiacriticWitness, .cjkWitness, .largeBMPWitness, .latinWitness, .latinLigature, .rtlWitness:
                numGlyphs
            }
        }

        func glyphID(for scalar: UnicodeScalar) -> UInt16? {
            glyphs.enumerated().first { pair in
                pair.element.scalar == scalar
            }.map { pair in UInt16(pair.offset + 1) }
        }

        func glyphID(named name: String) -> UInt16? {
            glyphs.enumerated().first { pair in
                pair.element.name == name
            }.map { pair in UInt16(pair.offset + 1) }
        }

        private static func latinWitnessAdvanceWidth(for scalar: UnicodeScalar) -> UInt16 {
            switch scalar {
            case "I":
                260
            case "J", "L", "T":
                520
            case "M":
                840
            case "W":
                900
            case "N", "U":
                740
            case "R", "S", "Z":
                640
            default:
                600
            }
        }

        private static func rtlWitnessGlyphs() -> [GlyphRecord] {
            let punctuation: [UnicodeScalar] = [
                " ",
                ".",
                ",",
                ":",
                ";",
                "'",
                "\"",
                "(",
                ")",
                "[",
                "]",
                "{",
                "}",
                "<",
                ">",
            ]
            let uppercase = (UInt8(ascii: "A") ... UInt8(ascii: "Z")).map(UnicodeScalar.init)
            let digits = (UInt8(ascii: "0") ... UInt8(ascii: "9")).map(UnicodeScalar.init)
            let hebrew = (0x05D0 ... 0x05D4).compactMap(UnicodeScalar.init)
            let arabic = [0x0627, 0x0633, 0x0644, 0x0645].compactMap(UnicodeScalar.init)
            let arabicIndicDigits = (0x0661 ... 0x0663).compactMap(UnicodeScalar.init)

            return (punctuation + uppercase + digits + hebrew + arabic + arabicIndicDigits).map { scalar in
                let width: UInt16 = switch scalar.value {
                case 0x20:
                    280
                case 0x2C, 0x2E, 0x3A, 0x3B, 0x27, 0x22:
                    300
                case 0x28 ... 0x29, 0x3C ... 0x3E, 0x5B ... 0x5D, 0x7B ... 0x7D:
                    360
                case 0x30 ... 0x39, 0x0661 ... 0x0663:
                    520
                case 0x0590 ... 0x05FF, 0x0600 ... 0x06FF:
                    610
                default:
                    Self.latinWitnessAdvanceWidth(for: scalar)
                }

                return GlyphRecord(
                    scalar: scalar,
                    advanceWidth: width,
                    xMin: scalar.value == 0x20 ? nil : 40,
                    xMax: scalar.value == 0x20 ? nil : Int16(max(90, Int(width) - 60)),
                )
            }
        }
    }

    private struct GlyphRecord {
        var scalar: UnicodeScalar?
        var name: String?
        var advanceWidth: UInt16
        var xMin: Int16?
        var xMax: Int16?
        var components: [UInt16] = []

        init(
            scalar: UnicodeScalar?,
            name: String? = nil,
            advanceWidth: UInt16,
            xMin: Int16?,
            xMax: Int16?,
            components: [UInt16] = [],
        ) {
            self.scalar = scalar
            self.name = name
            self.advanceWidth = advanceWidth
            self.xMin = xMin
            self.xMax = xMax
            self.components = components
        }
    }

    private static func cmapSearchValues(segmentCount: Int) -> (
        searchRange: UInt16,
        entrySelector: UInt16,
        rangeShift: UInt16
    ) {
        var maximumPower = 1
        var selector = 0
        while maximumPower * 2 <= segmentCount {
            maximumPower *= 2
            selector += 1
        }
        let searchRange = maximumPower * 2
        return (
            searchRange: UInt16(searchRange),
            entrySelector: UInt16(selector),
            rangeShift: UInt16(segmentCount * 2 - searchRange),
        )
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

    private static func appendTag(_ tag: String, to data: inout Data) {
        let bytes = Array(tag.utf8)
        precondition(bytes.count == 4)
        data.append(contentsOf: bytes)
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
