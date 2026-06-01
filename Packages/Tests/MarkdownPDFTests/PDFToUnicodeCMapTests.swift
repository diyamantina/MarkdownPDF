import Foundation
@testable import MarkdownPDF
import Testing

@Suite("PDF ToUnicode CMap")
struct PDFToUnicodeCMapTests {
    @Test("Serializes bfrange sections for consecutive one-to-one mappings")
    func serializesBfrangeSectionsForConsecutiveMappings() {
        let cmap = PDFToUnicodeCMap(mappings: [
            PDFToUnicodeCMap.Mapping(code: 3, unicode: "C"),
            PDFToUnicodeCMap.Mapping(code: 1, unicode: "A"),
            PDFToUnicodeCMap.Mapping(code: 2, unicode: "B"),
            PDFToUnicodeCMap.Mapping(code: 5, unicode: "\u{017D}"),
            PDFToUnicodeCMap.Mapping(code: 6, unicode: "\u{1F600}"),
        ])

        #expect(
            cmap.serialized
                ==
                """
                /CIDInit /ProcSet findresource begin
                12 dict begin
                begincmap
                /CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def
                /CMapName /MarkdownPDF-ToUnicode def
                /CMapType 2 def
                1 begincodespacerange
                <0000> <FFFF>
                endcodespacerange
                1 beginbfrange
                <0001> <0003> <0041>
                endbfrange
                2 beginbfchar
                <0005> <017D>
                <0006> <D83DDE00>
                endbfchar
                endcmap
                CMapName currentdict /CMap defineresource pop
                end
                end

                """,
        )
    }

    @Test("Chunks bfrange sections at PDF operator limits")
    func chunksBfrangeSectionsAtPDFOperatorLimits() throws {
        var mappings: [PDFToUnicodeCMap.Mapping] = []
        for index in 0 ..< 101 {
            let code = UInt16(1 + index * 3)
            let unicodeValue = UInt32(0x0100 + index * 3)
            let firstScalar = try #require(UnicodeScalar(unicodeValue))
            let secondScalar = try #require(UnicodeScalar(unicodeValue + 1))
            mappings.append(PDFToUnicodeCMap.Mapping(code: code, unicode: String(firstScalar)))
            mappings.append(PDFToUnicodeCMap.Mapping(code: code + 1, unicode: String(secondScalar)))
        }

        let serialized = PDFToUnicodeCMap(mappings: mappings).serialized
        let lines = serialized.split(separator: "\n").map(String.init)

        #expect(lines.count(where: { $0 == "100 beginbfrange" }) == 1)
        #expect(lines.count(where: { $0 == "1 beginbfrange" }) == 1)
        #expect(!lines.contains("101 beginbfrange"))
    }

    @Test("Builds deterministic mappings from glyph mapping output")
    func buildsDeterministicMappingsFromGlyphMappingOutput() throws {
        let fontData = SyntheticTrueTypeFont.data()
        let metadata = try TrueTypeFontParser().parse(fontData)
        let textMapping = try TrueTypeGlyphMapper(data: fontData, metadata: metadata).map(text: "ABA", fontSize: 12)

        let cmap = try PDFToUnicodeCMap(textMapping: textMapping)

        #expect(cmap.mappings == [
            PDFToUnicodeCMap.Mapping(code: 1, unicode: "A"),
            PDFToUnicodeCMap.Mapping(code: 2, unicode: "B"),
        ])
        #expect(cmap.serialized.contains("<0001> <0002> <0041>"))
    }

    @Test("Rejects conflicting glyph mapping output")
    func rejectsConflictingGlyphMappingOutput() {
        let textMapping = TrueTypeGlyphMapper.TextMapping(
            sourceText: "AB",
            glyphs: [
                glyph(scalar: "A", pdfCharacterCode: 1),
                glyph(scalar: "B", pdfCharacterCode: 1),
            ],
        )

        do {
            _ = try PDFToUnicodeCMap(textMapping: textMapping)
            Issue.record("Expected conflicting ToUnicode mapping")
        } catch let error as PDFToUnicodeCMapError {
            #expect(error == .conflictingMapping(code: 1, existing: "A", duplicate: "B"))
            #expect(error.errorDescription != nil)
            #expect(error.recoverySuggestion != nil)
        } catch {
            Issue.record("Expected PDFToUnicodeCMapError, got \(error)")
        }
    }

    @Test("Rejects empty glyph mapping output")
    func rejectsEmptyGlyphMappingOutput() {
        let textMapping = TrueTypeGlyphMapper.TextMapping(sourceText: "", glyphs: [])

        do {
            _ = try PDFToUnicodeCMap(textMapping: textMapping)
            Issue.record("Expected empty ToUnicode mapping")
        } catch let error as PDFToUnicodeCMapError {
            #expect(error == .emptyMapping)
            #expect(error.errorDescription != nil)
            #expect(error.recoverySuggestion != nil)
        } catch {
            Issue.record("Expected PDFToUnicodeCMapError, got \(error)")
        }
    }

    private func glyph(scalar: UnicodeScalar, pdfCharacterCode: UInt16) -> TrueTypeGlyphMapper.Glyph {
        TrueTypeGlyphMapper.Glyph(
            scalar: scalar,
            glyphID: pdfCharacterCode,
            cid: pdfCharacterCode,
            pdfCharacterCode: pdfCharacterCode,
            advanceWidth: 600,
            width: 7.2,
        )
    }
}
