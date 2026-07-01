import Foundation
@testable import MarkdownPDF
import Testing

@Suite("TrueType font subsetter")
struct TrueTypeFontSubsetterTests {
    @Test("Builds deterministic compact subsets and CIDToGID streams")
    func buildsDeterministicCompactSubsetsAndCIDToGIDStreams() throws {
        let fontData = SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true)
        let metadata = try TrueTypeFontParser().parse(fontData)
        let glyphs = try TrueTypeGlyphMapper(data: fontData, metadata: metadata)
            .map(text: "WAVE", fontSize: 12)
            .glyphs

        let first = try TrueTypeFontSubsetter(data: fontData, metadata: metadata).subset(glyphs: glyphs)
        let second = try TrueTypeFontSubsetter(data: fontData, metadata: metadata).subset(glyphs: glyphs)

        #expect(first.fontProgram == second.fontProgram)
        #expect(first.fontProgram.count < fontData.count)
        #expect(first.originalGlyphIDs == [0, 2, 6, 23, 24])
        #expect(first.glyphIDMap == [0: 0, 2: 1, 6: 2, 23: 3, 24: 4])
        #expect(first.metadata.maxp.numGlyphs == 5)
        #expect(first.metadata.hhea.numberOfHMetrics == 5)
        #expect(first.metadata.hmtx.advanceWidths == [500, 600, 600, 600, 900])
        #expect(sfntChecksum(first.fontProgram) == 0xB1B0_AFBA)

        guard case let .stream(cidMapData) = first.cidToGIDMap else {
            Issue.record("Expected CIDToGIDMap stream for non-identity subset glyph ids")
            return
        }
        #expect(cidMapData.count == 50)
        #expect(uint16(at: 2 * 2, in: cidMapData) == 1)
        #expect(uint16(at: 6 * 2, in: cidMapData) == 2)
        #expect(uint16(at: 23 * 2, in: cidMapData) == 3)
        #expect(uint16(at: 24 * 2, in: cidMapData) == 4)
    }

    @Test("Builds compact deterministic CID glyph runs for identity subset maps")
    func buildsCompactDeterministicCIDGlyphRunsForIdentitySubsetMaps() throws {
        let fontData = SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true)
        let metadata = try TrueTypeFontParser().parse(fontData)
        let glyphs = try TrueTypeGlyphMapper(data: fontData, metadata: metadata)
            .map(text: "WAVE", fontSize: 12)
            .glyphs
        let subsetter = TrueTypeFontSubsetter(data: fontData, metadata: metadata)
        let compactGlyphs = try subsetter.compactCIDGlyphs(for: glyphs)
        let subset = try subsetter.subset(glyphs: compactGlyphs)

        #expect(compactGlyphs.map(\.glyphID) == [24, 2, 23, 6])
        #expect(compactGlyphs.map(\.cid) == [4, 1, 3, 2])
        #expect(compactGlyphs.map(\.pdfCharacterCode) == [4, 1, 3, 2])
        #expect(subset.originalGlyphIDs == [0, 2, 6, 23, 24])
        #expect(subset.cidToGIDMap == .identity)
    }

    @Test("Recursively includes and rewrites composite glyph components")
    func recursivelyIncludesAndRewritesCompositeGlyphComponents() throws {
        let fontData = SyntheticTrueTypeFont.data(glyphProfile: .compositeWitness, includeGlyphOutlines: true)
        let metadata = try TrueTypeFontParser().parse(fontData)
        let glyphs = try TrueTypeGlyphMapper(data: fontData, metadata: metadata)
            .map(text: "C", fontSize: 12)
            .glyphs

        let subset = try TrueTypeFontSubsetter(data: fontData, metadata: metadata).subset(glyphs: glyphs)

        #expect(subset.originalGlyphIDs == [0, 1, 2, 3])
        #expect(subset.metadata.maxp.numGlyphs == 4)
        #expect(subset.metadata.hmtx.advanceWidths == [500, 600, 620, 740])
        #expect(try compositeComponentGlyphIDs(forGlyphID: 3, in: subset.fontProgram) == [1, 2])
        #expect(sfntChecksum(subset.fontProgram) == 0xB1B0_AFBA)
    }

    @Test("Uses format 12 cmap when BMP format 4 would exceed UInt16 length")
    func usesFormat12CMapWhenBMPFormat4WouldExceedUInt16Length() throws {
        let fontData = SyntheticTrueTypeFont.data(
            cmapFormat: 12,
            glyphProfile: .largeBMPWitness,
            includeGlyphOutlines: true,
        )
        let metadata = try TrueTypeFontParser().parse(fontData)
        let glyphs = (0 ..< 8200).map { index in
            let glyphID = UInt16(index + 1)
            let scalar = UnicodeScalar(UInt32(0x4000 + index)) ?? "A"
            return TrueTypeGlyphMapper.Glyph(
                scalar: scalar,
                glyphID: glyphID,
                cid: glyphID,
                pdfCharacterCode: glyphID,
                advanceWidth: 500,
                width: 6,
            )
        }

        let subset = try TrueTypeFontSubsetter(data: fontData, metadata: metadata).subset(glyphs: glyphs)

        #expect(subset.metadata.maxp.numGlyphs == 8201)
        #expect(subset.metadata.cmap.selectedUnicodeFormat == 12)
        #expect(sfntChecksum(subset.fontProgram) == 0xB1B0_AFBA)
    }

    @Test("Rejects unsupported subset inputs with typed errors")
    func rejectsUnsupportedSubsetInputsWithTypedErrors() throws {
        let fontData = SyntheticTrueTypeFont.data()
        let metadata = try TrueTypeFontParser().parse(fontData)
        let glyphs = try TrueTypeGlyphMapper(data: fontData, metadata: metadata)
            .map(text: "A", fontSize: 12)
            .glyphs

        do {
            _ = try TrueTypeFontSubsetter(data: fontData, metadata: metadata).subset(glyphs: glyphs)
            Issue.record("Expected missing glyf table error")
        } catch let error as TrueTypeFontSubsetError {
            #expect(error == .missingRequiredTable("glyf"))
            #expect(error.errorDescription != nil)
            #expect(error.recoverySuggestion != nil)
        } catch {
            Issue.record("Expected TrueTypeFontSubsetError, got \(error)")
        }
    }

    private func compositeComponentGlyphIDs(forGlyphID glyphID: UInt16, in fontData: Data) throws -> [UInt16] {
        let metadata = try TrueTypeFontParser().parse(fontData)
        let glyf = try tableData(tag: "glyf", metadata: metadata, fontData: fontData)
        let locations = try glyphLocations(metadata: metadata, fontData: fontData)
        let start = locations[Int(glyphID)]
        let end = locations[Int(glyphID) + 1]
        let glyph = Data(glyf[start ..< end])
        let reader = TrueTypeByteReader(table: "glyf", bytes: [UInt8](glyph))
        try reader.requireRange(offset: 0, count: 10)

        var components: [UInt16] = []
        var offset = 10
        var hasMoreComponents = true
        while hasMoreComponents {
            try reader.requireRange(offset: offset, count: 4)
            let flags = try reader.uint16(at: offset)
            try components.append(reader.uint16(at: offset + 2))
            offset += 4
            offset += flags & 0x0001 != 0 ? 4 : 2
            if flags & 0x0008 != 0 {
                offset += 2
            } else if flags & 0x0040 != 0 {
                offset += 4
            } else if flags & 0x0080 != 0 {
                offset += 8
            }
            hasMoreComponents = flags & 0x0020 != 0
        }
        return components
    }

    private func glyphLocations(metadata: TrueTypeFontParser.Metadata, fontData: Data) throws -> [Int] {
        let loca = try tableData(tag: "loca", metadata: metadata, fontData: fontData)
        let reader = TrueTypeByteReader(table: "loca", bytes: [UInt8](loca))
        return try (0 ... Int(metadata.maxp.numGlyphs)).map { index in
            try Int(reader.uint32(at: index * 4))
        }
    }

    private func tableData(
        tag: String,
        metadata: TrueTypeFontParser.Metadata,
        fontData: Data,
    ) throws -> Data {
        let record = try #require(metadata.table(named: tag))
        let bytes = [UInt8](fontData)
        let start = Int(record.offset)
        let end = start + Int(record.length)
        return Data(bytes[start ..< end])
    }

    private func uint16(at offset: Int, in data: Data) -> UInt16 {
        let bytes = [UInt8](data)
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    private func sfntChecksum(_ data: Data) -> UInt32 {
        var bytes = [UInt8](data)
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
}
