import Foundation
@testable import MarkdownPDF
import Testing

@Suite("TrueType glyph mapper")
struct TrueTypeGlyphMapperTests {
    @Test("Maps format 4 scalars to glyph ids, CIDs, PDF codes, and widths")
    func mapsFormat4ScalarsToGlyphsAndWidths() throws {
        let fontData = SyntheticTrueTypeFont.data()
        let metadata = try TrueTypeFontParser().parse(fontData)

        let mapping = try TrueTypeGlyphMapper(data: fontData, metadata: metadata).map(text: "AB", fontSize: 12)

        #expect(mapping.sourceText == "AB")
        #expect(mapping.glyphs.map(\.scalar) == ["A", "B"])
        #expect(mapping.glyphs.map(\.glyphID) == [1, 2])
        #expect(mapping.glyphs.map(\.cid) == [1, 2])
        #expect(mapping.glyphs.map(\.pdfCharacterCode) == [1, 2])
        #expect(mapping.glyphs.map(\.advanceWidth) == [600, 600])
        #expect(abs(mapping.glyphs[0].width - 7.2) < 0.0001)
        #expect(abs(mapping.glyphs[1].width - 7.2) < 0.0001)
        #expect(abs(mapping.totalWidth - 14.4) < 0.0001)
    }

    @Test("Maps format 12 groups with the same text model")
    func mapsFormat12GroupsWithTheSameTextModel() throws {
        let fontData = SyntheticTrueTypeFont.data(cmapFormat: 12)
        let metadata = try TrueTypeFontParser().parse(fontData)

        let mapping = try TrueTypeGlyphMapper(data: fontData, metadata: metadata).map(text: "AB", fontSize: 10)

        #expect(metadata.cmap.selectedUnicodeFormat == 12)
        #expect(mapping.glyphs.map(\.glyphID) == [1, 2])
        #expect(abs(mapping.glyphs[0].width - 6) < 0.0001)
        #expect(abs(mapping.glyphs[1].width - 6) < 0.0001)
        #expect(abs(mapping.totalWidth - 12) < 0.0001)
    }

    @Test("Maps CJK format 12 scalars with fullwidth advances")
    func mapsCJKFormat12ScalarsWithFullwidthAdvances() throws {
        let fontData = SyntheticTrueTypeFont.data(cmapFormat: 12, glyphProfile: .cjkWitness)
        let metadata = try TrueTypeFontParser().parse(fontData)

        let mapping = try TrueTypeGlyphMapper(data: fontData, metadata: metadata).map(text: "漢字語。", fontSize: 10)

        #expect(metadata.cmap.selectedUnicodeFormat == 12)
        #expect(mapping.glyphs.map(\.scalar) == ["漢", "字", "語", "。"])
        #expect(mapping.glyphs.map(\.glyphID) == [1, 2, 3, 4])
        #expect(mapping.glyphs.map(\.advanceWidth) == [1000, 1000, 1000, 500])
        #expect(mapping.glyphs.map(\.width) == [10, 10, 10, 5])
        #expect(abs(mapping.totalWidth - 35) < 0.0001)
    }

    @Test("Maps format 4 glyph id arrays")
    func mapsFormat4GlyphIDArrays() throws {
        let fontData = SyntheticTrueTypeFont.data(cmapFormat4UsesGlyphArray: true)
        let metadata = try TrueTypeFontParser().parse(fontData)

        let mapping = try TrueTypeGlyphMapper(data: fontData, metadata: metadata).map(text: "AB", fontSize: 12)

        #expect(mapping.glyphs.map(\.glyphID) == [1, 2])
        #expect(mapping.glyphs.map(\.cid) == [1, 2])
        #expect(abs(mapping.totalWidth - 14.4) < 0.0001)
    }

    @Test("Rejects invalid font sizes")
    func rejectsInvalidFontSizes() throws {
        let fontData = SyntheticTrueTypeFont.data()
        let metadata = try TrueTypeFontParser().parse(fontData)

        for fontSize in [0, -1, Double.infinity, Double.nan] {
            expectGlyphMappingError {
                _ = try TrueTypeGlyphMapper(data: fontData, metadata: metadata).map(text: "A", fontSize: fontSize)
            } verify: { error in
                guard case let .invalidFontSize(reportedFontSize) = error else {
                    Issue.record("Expected invalid font size")
                    return
                }
                if fontSize.isNaN {
                    #expect(reportedFontSize.isNaN)
                } else {
                    #expect(reportedFontSize == fontSize)
                }
            }
        }
    }

    @Test("Rejects unordered format 4 segments during mapping")
    func rejectsUnorderedFormat4SegmentsDuringMapping() throws {
        let fontData = SyntheticTrueTypeFont.data(invalidCMapFormat4SegmentRange: true)
        let metadata = try TrueTypeFontParser().parse(fontData)

        expectGlyphMappingError {
            _ = try TrueTypeGlyphMapper(data: fontData, metadata: metadata).map(text: "A", fontSize: 12)
        } verify: { error in
            guard case let .malformedCMap(format, reason) = error else {
                Issue.record("Expected malformed cmap")
                return
            }
            #expect(format == 4)
            #expect(reason.contains("unordered"))
        }
    }

    @Test("Rejects unsorted format 4 segments during mapping")
    func rejectsUnsortedFormat4SegmentsDuringMapping() throws {
        let fontData = SyntheticTrueTypeFont.data(invalidCMapFormat4SegmentOrder: true)
        let metadata = try TrueTypeFontParser().parse(fontData)

        expectGlyphMappingError {
            _ = try TrueTypeGlyphMapper(data: fontData, metadata: metadata).map(text: "A", fontSize: 12)
        } verify: { error in
            guard case let .malformedCMap(format, reason) = error else {
                Issue.record("Expected malformed cmap")
                return
            }
            #expect(format == 4)
            #expect(reason.contains("sorted"))
        }
    }

    @Test("Rejects non-zero format 4 reserved pad during mapping")
    func rejectsNonZeroFormat4ReservedPadDuringMapping() throws {
        let fontData = SyntheticTrueTypeFont.data(invalidCMapFormat4ReservedPad: true)
        let metadata = try TrueTypeFontParser().parse(fontData)

        expectGlyphMappingError {
            _ = try TrueTypeGlyphMapper(data: fontData, metadata: metadata).map(text: "A", fontSize: 12)
        } verify: { error in
            guard case let .malformedCMap(format, reason) = error else {
                Issue.record("Expected malformed cmap")
                return
            }
            #expect(format == 4)
            #expect(reason.contains("reserved pad"))
        }
    }

    @Test("Rejects mapped glyph ids outside maxp glyph count")
    func rejectsMappedGlyphIDsOutsideMaximumProfileCount() throws {
        let fontData = SyntheticTrueTypeFont.data(cmapFormat: 12, cmapFormat12StartGlyphID: 99)
        let metadata = try TrueTypeFontParser().parse(fontData)

        expectGlyphMappingError {
            _ = try TrueTypeGlyphMapper(data: fontData, metadata: metadata).map(text: "A", fontSize: 12)
        } verify: { error in
            guard case let .invalidGlyphID(glyphID, numGlyphs) = error else {
                Issue.record("Expected invalid glyph id")
                return
            }
            #expect(glyphID == 99)
            #expect(numGlyphs == 3)
        }
    }

    @Test("Rejects or maps missing glyphs according to policy")
    func rejectsOrMapsMissingGlyphsAccordingToPolicy() throws {
        let fontData = SyntheticTrueTypeFont.data()
        let metadata = try TrueTypeFontParser().parse(fontData)

        expectGlyphMappingError {
            _ = try TrueTypeGlyphMapper(data: fontData, metadata: metadata).map(text: "Z", fontSize: 12)
        } verify: { error in
            guard case let .missingGlyph(scalar) = error else {
                Issue.record("Expected missing glyph")
                return
            }
            #expect(scalar == "Z")
        }

        let mapping = try TrueTypeGlyphMapper(
            data: fontData,
            metadata: metadata,
            missingGlyphPolicy: .useNotdef,
        ).map(text: "Z", fontSize: 12)

        #expect(mapping.glyphs.map(\.glyphID) == [0])
        #expect(mapping.glyphs.map(\.advanceWidth) == [500])
        #expect(abs(mapping.totalWidth - 6) < 0.0001)
    }

    private func expectGlyphMappingError(
        _ body: () throws -> Void,
        verify: (TrueTypeGlyphMappingError) -> Void,
    ) {
        do {
            try body()
            Issue.record("Expected TrueType glyph mapping error")
        } catch let error as TrueTypeGlyphMappingError {
            #expect(error.errorDescription != nil)
            #expect(error.recoverySuggestion != nil)
            verify(error)
        } catch {
            Issue.record("Expected TrueTypeGlyphMappingError, got \(error)")
        }
    }
}
