import Foundation
@testable import MarkdownPDF
import Testing

@Suite("OpenType shaper")
struct OpenTypeShaperTests {
    @Test("Applies Latin ligatures from a GSUB fixture")
    func appliesLatinLigaturesFromGSUBFixture() throws {
        let shaper = try latinLigatureShaper(includeGSUBLigatures: true)

        let mapping = try shaper.shape(text: "file", fontSize: 10)

        #expect(mapping.sourceText == "file")
        #expect(mapping.clusters.map(\.sourceScalarRange) == [0 ..< 2, 2 ..< 3, 3 ..< 4])
        #expect(mapping.clusters.map(\.toUnicodeText) == ["fi", "l", "e"])
        #expect(mapping.clusters.map(\.pdfCharacterCodes) == [[6], [3], [4]])
        #expect(mapping.glyphs.map(\.glyphID) == [6, 3, 4])
        #expect(abs(mapping.totalAdvance - 13.7) < 0.0001)
    }

    @Test("Keeps combining marks in one source faithful cluster")
    func keepsCombiningMarksInOneSourceFaithfulCluster() throws {
        let shaper = try latinLigatureShaper(includeGSUBLigatures: true)

        let mapping = try shaper.shape(text: "e\u{0301}", fontSize: 10)

        #expect(mapping.sourceText == "e\u{0301}")
        #expect(mapping.clusters.count == 1)
        #expect(mapping.clusters[0].sourceScalarRange == 0 ..< 2)
        #expect(mapping.clusters[0].toUnicodeText == "e\u{0301}")
        #expect(mapping.clusters[0].glyphs.map(\.glyphID) == [4, 5])
        #expect(mapping.clusters[0].glyphs.map(\.advanceWidth) == [500, 0])
        #expect(mapping.totalAdvance == 5)
    }

    @Test("Keeps combining marks attached after a ligature")
    func keepsCombiningMarksAttachedAfterLigature() throws {
        let shaper = try latinLigatureShaper(includeGSUBLigatures: true)

        let mapping = try shaper.shape(text: "fi\u{0301}", fontSize: 10)

        #expect(mapping.clusters.count == 1)
        #expect(mapping.clusters[0].sourceScalarRange == 0 ..< 3)
        #expect(mapping.clusters[0].toUnicodeText == "fi\u{0301}")
        #expect(mapping.clusters[0].glyphs.map(\.glyphID) == [6, 5])
        #expect(mapping.clusters[0].pdfCharacterCodes == [6, 5])
        #expect(abs(mapping.totalAdvance - 6.2) < 0.0001)
    }

    @Test("Falls back to base glyph clusters when GSUB is absent")
    func fallsBackToBaseGlyphClustersWhenGSUBIsAbsent() throws {
        let shaper = try latinLigatureShaper(includeGSUBLigatures: false)

        let mapping = try shaper.shape(text: "file", fontSize: 10)

        #expect(mapping.clusters.map(\.sourceScalarRange) == [0 ..< 1, 1 ..< 2, 2 ..< 3, 3 ..< 4])
        #expect(mapping.clusters.map(\.toUnicodeText) == ["f", "i", "l", "e"])
        #expect(mapping.glyphs.map(\.glyphID) == [1, 2, 3, 4])
    }

    @Test("Rejects unsupported scripts with a typed error")
    func rejectsUnsupportedScriptsWithTypedError() throws {
        let shaper = try latinLigatureShaper(includeGSUBLigatures: true)

        do {
            _ = try shaper.shape(text: "\u{05D0}", fontSize: 10)
            Issue.record("Expected unsupported script scalar")
        } catch let error as OpenTypeShaper.ValidationError {
            #expect(error == .unsupportedScriptScalar(scalar: "\u{05D0}", scalarOffset: 0))
            #expect(error.errorDescription != nil)
            #expect(error.recoverySuggestion != nil)
        } catch {
            Issue.record("Expected OpenTypeShaper.ValidationError, got \(error)")
        }
    }

    @Test("Rejects leading combining marks with a typed error")
    func rejectsLeadingCombiningMarksWithTypedError() throws {
        let shaper = try latinLigatureShaper(includeGSUBLigatures: true)

        do {
            _ = try shaper.shape(text: "\u{0301}e", fontSize: 10)
            Issue.record("Expected leading combining mark")
        } catch let error as OpenTypeShaper.ValidationError {
            #expect(error == .leadingCombiningMark(scalar: "\u{0301}", scalarOffset: 0))
            #expect(error.errorDescription != nil)
            #expect(error.recoverySuggestion != nil)
        } catch {
            Issue.record("Expected OpenTypeShaper.ValidationError, got \(error)")
        }
    }

    @Test("Rejects invalid font sizes before glyph mapping")
    func rejectsInvalidFontSizesBeforeGlyphMapping() throws {
        let shaper = try latinLigatureShaper(includeGSUBLigatures: true)

        do {
            _ = try shaper.shape(text: "file", fontSize: 0)
            Issue.record("Expected invalid font size")
        } catch let error as OpenTypeShaper.ValidationError {
            #expect(error == .invalidFontSize(0))
            #expect(error.errorDescription != nil)
            #expect(error.recoverySuggestion != nil)
        } catch {
            Issue.record("Expected OpenTypeShaper.ValidationError, got \(error)")
        }
    }

    @Test("Rejects malformed GSUB tables with a typed error")
    func rejectsMalformedGSUBTablesWithTypedError() throws {
        let font = try latinLigatureFont(includeGSUBLigatures: true)
        var fontData = font.data
        let gsubOffset = try gsubTableOffset(in: font.metadata)
        fontData[gsubOffset] = 0
        fontData[gsubOffset + 1] = 2
        let shaper = OpenTypeShaper(data: fontData, metadata: font.metadata)

        do {
            _ = try shaper.shape(text: "file", fontSize: 10)
            Issue.record("Expected malformed GSUB table")
        } catch let error as OpenTypeShaper.ValidationError {
            #expect(error == .malformedGSUB(reason: "major version must be 1"))
            #expect(error.errorDescription != nil)
            #expect(error.recoverySuggestion != nil)
        } catch {
            Issue.record("Expected OpenTypeShaper.ValidationError, got \(error)")
        }
    }

    @Test("Rejects unsupported GSUB lookup flags with a typed error")
    func rejectsUnsupportedGSUBLookupFlagsWithTypedError() throws {
        let font = try latinLigatureFont(includeGSUBLigatures: true)
        var fontData = font.data
        let lookupFlagOffset = try gsubLookupFlagOffset(in: fontData, metadata: font.metadata)
        fontData[lookupFlagOffset] = 0
        fontData[lookupFlagOffset + 1] = 0x08
        let shaper = OpenTypeShaper(data: fontData, metadata: font.metadata)

        do {
            _ = try shaper.shape(text: "file", fontSize: 10)
            Issue.record("Expected unsupported GSUB lookup flag")
        } catch let error as OpenTypeShaper.ValidationError {
            #expect(error == .unsupportedGSUBLookupFlag(0x0008))
            #expect(error.errorDescription != nil)
            #expect(error.recoverySuggestion != nil)
        } catch {
            Issue.record("Expected OpenTypeShaper.ValidationError, got \(error)")
        }
    }

    private func latinLigatureShaper(includeGSUBLigatures: Bool) throws -> OpenTypeShaper {
        let font = try latinLigatureFont(includeGSUBLigatures: includeGSUBLigatures)
        return OpenTypeShaper(data: font.data, metadata: font.metadata)
    }

    private func latinLigatureFont(
        includeGSUBLigatures: Bool,
    ) throws -> (data: Data, metadata: TrueTypeFontParser.Metadata) {
        let fontData = SyntheticTrueTypeFont.data(
            glyphProfile: .latinLigature,
            includeGSUBLigatures: includeGSUBLigatures,
        )
        let metadata = try TrueTypeFontParser().parse(fontData)
        return (data: fontData, metadata: metadata)
    }

    private func gsubTableOffset(in metadata: TrueTypeFontParser.Metadata) throws -> Int {
        try Int(#require(metadata.table(named: "GSUB")).offset)
    }

    private func gsubLookupFlagOffset(
        in data: Data,
        metadata: TrueTypeFontParser.Metadata,
    ) throws -> Int {
        let tableOffset = try gsubTableOffset(in: metadata)
        let lookupListOffset = try tableOffset + Int(uint16(in: data, at: tableOffset + 8))
        let firstLookupOffset = try lookupListOffset + Int(uint16(in: data, at: lookupListOffset + 2))
        return firstLookupOffset + 2
    }

    private func uint16(in data: Data, at offset: Int) throws -> UInt16 {
        try #require(offset >= 0 && offset + 2 <= data.count)
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }
}
